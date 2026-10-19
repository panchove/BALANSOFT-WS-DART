"""Tests de respaldo de estación (REQ-NF-BKP-001/002/003).

Cubre:
- Creación de snapshot (archivo gzip + manifiesto + conteos, sin credenciales).
- Restauración que reinserta filas eliminadas.
- Restauración que NO sobrescribe filas existentes (política de PK).
- Rechazo de snapshot de otra empresa (aislamiento multi-tenant).
- Endpoints: auto para cualquier autenticado; listar/descargar/restaurar ADMIN;
  restauración exige confirmación explícita.
- Rotación por retención.
"""

from __future__ import annotations

import gzip
import json
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.config import settings
from app.core.database import get_db
from app.models import (
    BoletoPesaje,
    Categoria,
    Empresa,
    Producto,
    Usuario,
)
from app.services.backup_service import BackupError, BackupService


@pytest_asyncio.fixture
async def admin_user(db: AsyncSession, empresa: Empresa) -> Usuario:
    u = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin",
        email=f"admin-bkp-{uuid.uuid4().hex[:6]}@test.com",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


@pytest_asyncio.fixture
async def auditor_user(db: AsyncSession, empresa: Empresa) -> Usuario:
    u = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Auditor",
        email=f"auditor-bkp-{uuid.uuid4().hex[:6]}@test.com",
        password_hash="x",
        rol="AUDITOR",
        activo=True,
    )
    db.add(u)
    await db.commit()
    await db.refresh(u)
    return u


def _build_app(db, usuario: Usuario, empresa: Empresa) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: usuario
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


@pytest_asyncio.fixture
async def app(db, empresa, admin_user) -> FastAPI:
    return _build_app(db, admin_user, empresa)


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


async def _empresa_con_datos(db: AsyncSession, empresa: Empresa) -> None:
    """Siembra categoría + producto + boleto de prueba para la empresa."""
    cat = Categoria(
        id_categoria=uuid.uuid4(),
        id_empresa=empresa.id_empresa,
        codigo="C-BKP",
        nombre="Categoría Backup",
    )
    db.add(cat)
    await db.flush()
    prod = Producto(
        id_producto=uuid.uuid4(),
        id_empresa=empresa.id_empresa,
        id_categoria=cat.id_categoria,
        codigo="P-BKP",
        nombre="Producto Backup",
        unidad_medida="TON",
        es_kardex=True,
    )
    db.add(prod)
    await db.flush()  # el boleto referencia a este producto (FK); debe existir antes
    db.add(
        BoletoPesaje(
            numero_boleto="BKP-0001",
            id_empresa=empresa.id_empresa,
            id_producto=prod.id_producto,
            fecha_hora_entrada=datetime.now(UTC).replace(tzinfo=None),
            peso_entrada_vehiculo=Decimal("5000"),
            peso_total_entrada=Decimal("5000"),
            peso_salida_vehiculo=Decimal(0),
            peso_total_salida=Decimal(0),
            peso_neto=Decimal("5000"),
            estado_boleto=BoletoPesaje.ESTADO_CERRADO,
            sincronizado=False,
            sync_intentos=0,
        )
    )
    await db.commit()


class TestCreacion:
    async def test_crear_snapshot_manifiesto_y_conteos(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))
        assert info.archivo.startswith(f"backup_{empresa.id_empresa}_")
        assert info.version == 1
        assert info.conteos["boletos_pesaje"] == 1
        assert info.conteos["categorias"] == 1
        assert info.conteos["productos"] == 1

        ruta = tmp_path / info.archivo
        with gzip.open(ruta, "rt", encoding="utf-8") as fh:
            manifiesto = json.load(fh)
        assert manifiesto["id_empresa"] == str(empresa.id_empresa)
        assert manifiesto["empresa"]["nombre_fiscal"] == empresa.nombre_fiscal
        assert manifiesto["version"] == 1
        # Decisión de diseño: el snapshot NO incluye credenciales ni usuarios.
        assert "usuarios" not in manifiesto["tablas"]
        assert "empresas" not in manifiesto["tablas"]
        assert "password" not in json.dumps(manifiesto, ensure_ascii=False).lower()


class TestRestauracion:
    async def test_restaurar_reinserta_eliminado(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))

        # Elimino el producto y su boleto (simula pérdida) y verifico que faltan.
        await db.execute(
            delete(BoletoPesaje).where(
                BoletoPesaje.id_empresa == empresa.id_empresa
            )
        )
        await db.execute(
            delete(Producto).where(Producto.id_empresa == empresa.id_empresa)
        )
        await db.commit()
        total = await db.scalar(
            select(func.count()).select_from(Producto).where(Producto.id_empresa == empresa.id_empresa)
        )
        assert total == 0

        resultado = await BackupService.restaurar(
            db, empresa, info.archivo, carpeta=str(tmp_path)
        )
        assert resultado["restaurados"]["productos"] == 1
        assert resultado["restaurados"]["boletos_pesaje"] == 1

        # El producto volvió con sus valores originales.
        prod = (
            await db.execute(select(Producto).where(Producto.id_empresa == empresa.id_empresa))
        ).scalar_one()
        assert prod.codigo == "P-BKP"
        assert prod.es_kardex is True

    async def test_restaurar_fallo_parcial_se_reporta(
        self, db: AsyncSession, empresa: Empresa, tmp_path, monkeypatch
    ):
        """Un fallo en una tabla no aborta el restore y se reporta (REQ-NF-BKP-002)."""
        from app.services import backup_service as bkp_module

        ahora = datetime.now(UTC).replace(tzinfo=None)
        nombre = BackupService._nombre_archivo(empresa.id_empresa, ahora)
        ruta = BackupService._directorio(str(tmp_path)) / nombre
        # Snapshot sintético con un solo boleto; el deserializador falla solo
        # para esa tabla → el resto de la restauración continúa.
        BackupService._escribir_snapshot(
            ruta,
            {
                "version": 1,
                "id_empresa": str(empresa.id_empresa),
                "empresa": {
                    "nombre_fiscal": empresa.nombre_fiscal,
                    "rif_nit": empresa.rif_nit,
                },
                "creado_en": ahora.isoformat(),
                "motivo": "manual",
                "conteos": {"boletos_pesaje": 1},
                "tablas": {
                    "boletos_pesaje": [
                        {
                            "id_boleto": str(uuid.uuid4()),
                            "id_empresa": str(empresa.id_empresa),
                            "numero_boleto": "TA-INCOMPLETO",
                        }
                    ]
                },
            },
        )

        real = bkp_module._deserializar_fila

        def _deserializar_que_falla(fila, modelo):
            if modelo.__tablename__ == "boletos_pesaje":
                raise RuntimeError("boom")
            return real(fila, modelo)

        monkeypatch.setattr(bkp_module, "_deserializar_fila", _deserializar_que_falla)

        resultado = await BackupService.restaurar(
            db, empresa, nombre, carpeta=str(tmp_path)
        )
        assert resultado["restaurados"]["boletos_pesaje"] == 0
        assert "boletos_pesaje" in resultado["advertencia"]

    async def test_restaurar_snapshot_danado_rechazado(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        """Un archivo corrupto con nombre válido responde BackupError (400)."""
        ahora = datetime.now(UTC).replace(tzinfo=None)
        nombre = BackupService._nombre_archivo(empresa.id_empresa, ahora)
        ruta = BackupService._directorio(str(tmp_path)) / nombre
        ruta.write_bytes(b"no es un snapshot gzip")

        with pytest.raises(BackupError):
            await BackupService.restaurar(
                db, empresa, nombre, carpeta=str(tmp_path)
            )

    async def test_restaurar_gzip_truncado_rechazado(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        """Un gzip truncado (interrupción real de escritura) responde 400, no 500."""
        ahora = datetime.now(UTC).replace(tzinfo=None)
        nombre = BackupService._nombre_archivo(empresa.id_empresa, ahora)
        ruta = BackupService._directorio(str(tmp_path)) / nombre
        completo = gzip.compress(json.dumps({"version": 1}).encode())
        ruta.write_bytes(completo[: len(completo) // 2])  # cortado por la mitad

        with pytest.raises(BackupError):
            await BackupService.restaurar(
                db, empresa, nombre, carpeta=str(tmp_path)
            )

    async def test_restaurar_manifiesto_no_dict_rechazado(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        """Un gzip válido con raíz no-objeto se rechaza como snapshot inválido."""
        ahora = datetime.now(UTC).replace(tzinfo=None)
        nombre = BackupService._nombre_archivo(empresa.id_empresa, ahora)
        ruta = BackupService._directorio(str(tmp_path)) / nombre
        ruta.write_bytes(gzip.compress(b"[1, 2, 3]"))

        with pytest.raises(BackupError):
            await BackupService.restaurar(
                db, empresa, nombre, carpeta=str(tmp_path)
            )

    def test_listar_omite_gzip_truncado(self, tmp_path):
        """Un fichero corrupto no aborta el listado (REQ-NF-BKP-003)."""
        id_empresa = uuid.uuid4()
        carpeta = str(tmp_path)
        ahora = datetime.now(UTC).replace(tzinfo=None)

        bueno = BackupService._directorio(carpeta) / BackupService._nombre_archivo(
            id_empresa, ahora
        )
        BackupService._escribir_snapshot(
            bueno,
            {
                "version": 1,
                "id_empresa": str(id_empresa),
                "empresa": {"nombre_fiscal": "X", "rif_nit": "J-1"},
                "creado_en": ahora.isoformat(),
                "motivo": "manual",
                "conteos": {},
            },
        )

        malo = BackupService._directorio(carpeta) / BackupService._nombre_archivo(
            id_empresa, ahora - timedelta(minutes=5)
        )
        completo = gzip.compress(b'{"version": 1}')
        malo.write_bytes(completo[: len(completo) // 2])

        info = BackupService.listar(id_empresa, carpeta=carpeta)
        assert len(info) == 1  # el truncado se omite, el bueno se lista

    async def test_restaurar_no_sobrescribe_existente(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))

        # Modifico el producto DESPUÉS del snapshot: la restauración no debe
        # revertir la modificación (política: nunca sobrescribir PK existente).
        prod = (
            await db.execute(select(Producto).where(Producto.id_empresa == empresa.id_empresa))
        ).scalar_one()
        prod.nombre = "Nombre editado después del respaldo"
        await db.commit()

        resultado = await BackupService.restaurar(
            db, empresa, info.archivo, carpeta=str(tmp_path)
        )
        assert resultado["restaurados"]["productos"] == 0

        prod_actual = (
            await db.execute(select(Producto).where(Producto.id_empresa == empresa.id_empresa))
        ).scalar_one()
        assert prod_actual.nombre == "Nombre editado después del respaldo"

    async def test_restaurar_snapshot_otra_empresa_rechazado(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))

        otra = Empresa(
            nombre_fiscal="Otra Empresa",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
            licencia_tier="CENTRAL",
            activa=True,
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)

        with pytest.raises(BackupError):
            await BackupService.restaurar(db, otra, info.archivo, carpeta=str(tmp_path))

    async def test_ruta_archivo_valida_pertenencia(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))
        with pytest.raises(BackupError):
            BackupService.ruta_archivo(
                uuid.uuid4(), info.archivo, carpeta=str(tmp_path)
            )

    async def test_restaurar_exige_respaldo_previo(
        self, db: AsyncSession, empresa: Empresa, tmp_path
    ):
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))
        # Un restore exitoso deja un snapshot de seguridad "pre-restauracion".
        await BackupService.restaurar(db, empresa, info.archivo, carpeta=str(tmp_path))
        motivos = {b.motivo for b in BackupService.listar(empresa.id_empresa, carpeta=str(tmp_path))}
        assert "pre-restauracion" in motivos


class TestEndpoints:
    async def test_auto_cualquier_autenticado(
        self, db: AsyncSession, empresa: Empresa, auditor_user: Usuario, tmp_path, monkeypatch
    ):
        monkeypatch.setattr(settings, "backup_dir", str(tmp_path))
        app_auditor = _build_app(db, auditor_user, empresa)
        transport = httpx.ASGITransport(app=app_auditor)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post("/api/v1/backups/auto")
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["archivo"].startswith(f"backup_{empresa.id_empresa}_")
        assert body["motivo"] == "auto"

    async def test_listar_requiere_admin(
        self, db: AsyncSession, empresa: Empresa, auditor_user: Usuario, tmp_path, monkeypatch
    ):
        monkeypatch.setattr(settings, "backup_dir", str(tmp_path))
        app_auditor = _build_app(db, auditor_user, empresa)
        transport = httpx.ASGITransport(app=app_auditor)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.get("/api/v1/backups")
        assert r.status_code == 403

    async def test_listar_y_restaurar_admin(
        self,
        db: AsyncSession,
        empresa: Empresa,
        admin_user: Usuario,
        tmp_path,
        monkeypatch,
    ):
        monkeypatch.setattr(settings, "backup_dir", str(tmp_path))
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))

        app_admin = _build_app(db, admin_user, empresa)
        transport = httpx.ASGITransport(app=app_admin)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            # Sin confirmación explícita → 400.
            r0 = await ac.post(f"/api/v1/backups/{info.archivo}/restore", json={"confirmar": False})
            assert r0.status_code == 400

    async def test_listar_admin_devuelve_snapshots(
        self, db: AsyncSession, empresa: Empresa, admin_user: Usuario, tmp_path, monkeypatch
    ):
        monkeypatch.setattr(settings, "backup_dir", str(tmp_path))
        await _empresa_con_datos(db, empresa)
        await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))

        app_admin = _build_app(db, admin_user, empresa)
        transport = httpx.ASGITransport(app=app_admin)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.get("/api/v1/backups")
        assert r.status_code == 200
        assert len(r.json()) == 1

    async def test_restaurar_endpoint_confirmado(
        self, db: AsyncSession, empresa: Empresa, admin_user: Usuario, tmp_path, monkeypatch
    ):
        monkeypatch.setattr(settings, "backup_dir", str(tmp_path))
        await _empresa_con_datos(db, empresa)
        info = await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))
        await db.execute(
            delete(BoletoPesaje).where(
                BoletoPesaje.id_empresa == empresa.id_empresa
            )
        )
        await db.execute(
            delete(Producto).where(Producto.id_empresa == empresa.id_empresa)
        )
        await db.commit()

        app_admin = _build_app(db, admin_user, empresa)
        transport = httpx.ASGITransport(app=app_admin)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post(
                f"/api/v1/backups/{info.archivo}/restore", json={"confirmar": True}
            )
        assert r.status_code == 200, r.text
        assert r.json()["restaurados"]["productos"] == 1


class TestRotacion:
    """Rotación GFS: abuelo (mensual), padre (semanal) e hijo (diario)."""

    async def test_rotacion_gfs_mismo_dia_conserva_ultimo(
        self, db: AsyncSession, empresa: Empresa, tmp_path, monkeypatch
    ):
        await _empresa_con_datos(db, empresa)
        monkeypatch.setattr(settings, "backup_retention_days", 0)
        await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))
        await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))
        # Dos snapshots del mismo día: el GFS conserva solo el último (hijo).
        restantes = list(tmp_path.glob(f"backup_{empresa.id_empresa}_*.json.gz"))
        assert len(restantes) == 1

    async def test_rotacion_gfs_niveles_abuelo_padre_hijo(
        self, db: AsyncSession, empresa: Empresa, tmp_path, monkeypatch
    ):
        # 31 snapshots diarios de enero 2026 (fechas fijas en el nombre).
        base = datetime(2026, 1, 1, 12, 0, 0)
        for i in range(31):
            nombre = BackupService._nombre_archivo(
                empresa.id_empresa, base + timedelta(days=i)
            )
            (tmp_path / nombre).write_bytes(b"x")

        monkeypatch.setattr(settings, "backup_retention_days", 0)
        monkeypatch.setattr(settings, "backup_keep_daily", 7)
        monkeypatch.setattr(settings, "backup_keep_weekly", 5)
        monkeypatch.setattr(settings, "backup_keep_monthly", 1)
        BackupService._rotar_gfs(empresa.id_empresa, carpeta=str(tmp_path))

        restantes = {
            p.name for p in tmp_path.glob(f"backup_{empresa.id_empresa}_*.json.gz")
        }
        # Hijos: 25-31 ene. Padres (último de cada semana ISO): 4, 11, 18 ene
        # (25 y 31 ya son hijos). Abuelo (último del mes): 31 ene (ya hijo).
        # base=1 ene → índice i = día (i+1) del mes.
        indices_esperados = [3, 10, 17, 24, 25, 26, 27, 28, 29, 30]
        esperados = {
            BackupService._nombre_archivo(
                empresa.id_empresa, base + timedelta(days=i)
            )
            for i in indices_esperados
        }
        assert restantes == esperados

    async def test_rotacion_gfs_limite_duro_de_edad(
        self, db: AsyncSession, empresa: Empresa, tmp_path, monkeypatch
    ):
        await _empresa_con_datos(db, empresa)
        viejo = tmp_path / BackupService._nombre_archivo(
            empresa.id_empresa,
            datetime.now(UTC).replace(tzinfo=None) - timedelta(days=40),
        )
        viejo.write_bytes(b"")
        monkeypatch.setattr(settings, "backup_retention_days", 30)
        await BackupService.crear(db, empresa, motivo="manual", carpeta=str(tmp_path))
        # El snapshot de hace 40 días cae fuera de la retención dura → se elimina.
        restantes = list(tmp_path.glob(f"backup_{empresa.id_empresa}_*.json.gz"))
        assert len(restantes) == 1
        assert restantes[0].name != viejo.name
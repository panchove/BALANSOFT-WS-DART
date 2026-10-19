"""Pruebas de las llaves de activación (un solo uso) para estaciones OPERADOR.

Cubre el contrato que pide el negocio:

- El ADMIN emite la llave de un usuario de **su** empresa (aislamiento).
- Emitir una nueva revoca la activa anterior ("un solo uso por usuario").
- El canje es de **un solo uso**: el segundo intento falla.
- El código se guarda hasheado; en claro solo se devuelve al emitirlo.
- Al consumirse se notifica al dueño con las sesiones usadas/disponibles.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import Empresa, LlaveActivacion, Notificacion, Usuario
from app.services.llave_activacion_service import (
    ESTADO_CONSUMIDA,
    hash_codigo,
    limite_sesiones_por_tier,
)

RUTA_LLAVES = "/api/v1/activacion/llaves"
RUTA_VALIDAR = "/api/v1/activacion/validar"


class TestLimiteSesionesPorTier:
    """Solo DEMO limita; el resto de planes no impone tope funcional local.

    Los planes Básico/Premium que emite el LM deben operar sin restricción:
    la concurrencia real la fija la licencia del LM/central
    (``licencias.max_sesiones``), no la estación.
    """

    def test_demo_limita_a_tres(self):
        assert limite_sesiones_por_tier("DEMO") == 3
        assert limite_sesiones_por_tier("demo") == 3

    def test_central_y_planes_sin_tope(self):
        assert limite_sesiones_por_tier("CENTRAL") is None
        assert limite_sesiones_por_tier("MONOPUESTO") is None
        assert limite_sesiones_por_tier("PREMIUM") is None
        assert limite_sesiones_por_tier("BASICA") is None

    def test_tier_desconocido_no_degrada(self):
        assert limite_sesiones_por_tier("") is None
        assert limite_sesiones_por_tier(None) is None
        assert limite_sesiones_por_tier("OTRO") is None


def _app(db, user: Usuario, empresa: Empresa) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: user
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


async def _cliente(app: FastAPI) -> httpx.AsyncClient:
    transport = httpx.ASGITransport(app=app)
    return httpx.AsyncClient(transport=transport, base_url="http://test")


@pytest_asyncio.fixture
async def admin(db, empresa) -> Usuario:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Test",
        email="admin@llaves.demo",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest_asyncio.fixture
async def operador(db, empresa) -> Usuario:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Operador Test",
        email="operador@llaves.demo",
        password_hash="x",
        rol="OPERADOR",
        activo=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest_asyncio.fixture
async def cliente(db, admin, empresa):
    async with await _cliente(_app(db, admin, empresa)) as ac:
        yield ac


class TestEmitirLlave:
    async def test_admin_emite_y_el_codigo_solo_se_ve_una_vez(self, db, cliente, operador):
        r = await cliente.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})
        assert r.status_code == 201, r.text
        cuerpo = r.json()
        codigo = cuerpo["codigo"]
        assert codigo.startswith("BS-")
        assert codigo == codigo.upper()
        # Sin caracteres ambiguos para el tecleo en estación.
        assert not set(codigo) & set("0O1I")
        assert cuerpo["codigo_preview"] == codigo[-6:]

        # En la BD solo queda el hash, nunca el código en claro.
        llave = (await db.execute(select(LlaveActivacion))).scalar_one()
        assert llave.codigo_hash == hash_codigo(codigo)
        assert codigo not in llave.codigo_hash
        assert llave.estado == "activa"
        assert llave.id_empresa == operador.id_empresa
        assert llave.expira_en is not None

    async def test_no_admin_no_puede_emitir(self, db, empresa, operador):
        otro = Usuario(
            id_empresa=empresa.id_empresa,
            nombre="Operador Dos",
            email="operador2@llaves.demo",
            password_hash="x",
            rol="OPERADOR",
            activo=True,
        )
        db.add(otro)
        await db.commit()
        await db.refresh(otro)

        async with await _cliente(_app(db, otro, empresa)) as ac:
            r = await ac.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})
        assert r.status_code == 403, r.text

    async def test_usuario_de_otra_empresa_no_existe(self, db, cliente):
        ajena = Empresa(
            nombre_fiscal="Otra Empresa",
            rif_nit="J-OTRA-0001",
            licencia_tier="CENTRAL",
            activa=True,
        )
        db.add(ajena)
        await db.commit()
        await db.refresh(ajena)

        intruso = Usuario(
            id_empresa=ajena.id_empresa,
            nombre="Intruso",
            email="intruso@ajena.demo",
            password_hash="x",
            rol="OPERADOR",
            activo=True,
        )
        db.add(intruso)
        await db.commit()
        await db.refresh(intruso)

        r = await cliente.post(RUTA_LLAVES, json={"id_usuario": str(intruso.id_usuario)})
        assert r.status_code == 400, r.text
        # Aislamiento: no se creó nada para la empresa ajena.
        assert (await db.execute(select(LlaveActivacion))).scalar_one_or_none() is None

    async def test_expira_horas_fuera_de_rango(self, cliente, operador):
        r = await cliente.post(
            RUTA_LLAVES,
            json={"id_usuario": str(operador.id_usuario), "expira_horas": 0},
        )
        assert r.status_code == 422, r.text

    async def test_nueva_llave_revoca_la_anterior(self, db, cliente, operador):
        await cliente.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})
        await cliente.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})

        llaves = (
            (
                await db.execute(
                    select(LlaveActivacion).order_by(LlaveActivacion.created_at)
                )
            )
            .scalars()
            .all()
        )
        assert len(llaves) == 2
        assert [ll.estado for ll in llaves] == ["revocada", "activa"]


class TestValidarLlave:
    async def test_un_solo_uso(self, db, cliente, operador):
        codigo = (
            await cliente.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})
        ).json()["codigo"]

        r = await cliente.post(
            RUTA_VALIDAR, json={"codigo": codigo, "hardware_id": "HW-OPER-1"}
        )
        assert r.status_code == 200, r.text
        assert r.json()["usuario_email"] == operador.email

        llave = (await db.execute(select(LlaveActivacion))).scalar_one()
        assert llave.estado == ESTADO_CONSUMIDA
        assert llave.consumida_por_hw == "HW-OPER-1"
        assert llave.consumida_en is not None

        # Segundo intento con el mismo código: ya no vale.
        r2 = await cliente.post(RUTA_VALIDAR, json={"codigo": codigo})
        assert r2.status_code == 400, r2.text

    async def test_codigo_invalido(self, cliente):
        r = await cliente.post(RUTA_VALIDAR, json={"codigo": "BS-ZZZZ-ZZZZ-ZZZZ"})
        assert r.status_code == 400, r.text

    async def test_tolera_minusculas_y_espacios(self, cliente, operador):
        codigo = (
            await cliente.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})
        ).json()["codigo"]
        r = await cliente.post(RUTA_VALIDAR, json={"codigo": f"  {codigo.lower()} "})
        assert r.status_code == 200, r.text

    async def test_expirada(self, db, cliente, empresa, operador):
        db.add(
            LlaveActivacion(
                id_empresa=empresa.id_empresa,
                id_usuario=operador.id_usuario,
                codigo_hash=hash_codigo("BS-VENC-IDA1-2345"),
                codigo_preview="12345",
                estado="activa",
                expira_en=datetime.now(UTC).replace(tzinfo=None) - timedelta(hours=1),
            )
        )
        await db.commit()

        # El codigo del POST tiene que ser el MISMO que se guardo: con otro, el
        # 400 lo devolveria «invalido» y el test pasaria por el motivo
        # equivocado (no por estar vencida).
        r = await cliente.post(RUTA_VALIDAR, json={"codigo": "BS-VENC-IDA1-2345"})
        assert r.status_code == 400, r.text
        assert "expir" in r.json()["detail"].lower(), r.text

    async def test_notifica_al_dueno_con_sesiones(self, db, cliente, empresa, operador):
        codigo = (
            await cliente.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})
        ).json()["codigo"]
        r = await cliente.post(RUTA_VALIDAR, json={"codigo": codigo, "hardware_id": "HW-9"})
        assert r.status_code == 200, r.text

        notif = (await db.execute(select(Notificacion))).scalar_one()
        assert notif.tipo == "activacion_equipo"
        assert notif.id_empresa == operador.id_empresa
        assert operador.email in (notif.mensaje or "")
        assert "sesiones" in (notif.mensaje or "")
        assert notif.dedup_key is not None and notif.dedup_key.startswith("llave_activacion:")

    async def test_no_expone_identificadores_de_tenant(self, cliente, operador, empresa):
        codigo = (
            await cliente.post(RUTA_LLAVES, json={"id_usuario": str(operador.id_usuario)})
        ).json()["codigo"]
        r = await cliente.post(RUTA_VALIDAR, json={"codigo": codigo})
        assert r.status_code == 200, r.text
        cuerpo = r.json()
        assert str(empresa.id_empresa) not in r.text
        assert str(operador.id_usuario) not in r.text
        assert set(cuerpo) == {"ok", "usuario_email", "empresa_nombre", "mensaje"}

    async def test_expirada_no_se_consume(self, db, cliente, operador):
        llave = LlaveActivacion(
            id_empresa=operador.id_empresa,
            id_usuario=operador.id_usuario,
            codigo_hash=hash_codigo("BS-VENC-VENC-VENC"),
            codigo_preview="VENC",
            estado="activa",
            expira_en=datetime.now(UTC).replace(tzinfo=None) - timedelta(minutes=1),
            created_at=datetime.now(UTC).replace(tzinfo=None),
            updated_at=datetime.now(UTC).replace(tzinfo=None),
        )
        db.add(llave)
        await db.commit()

        r = await cliente.post(RUTA_VALIDAR, json={"codigo": "BS-VENC-VENC-VENC"})
        assert r.status_code == 400, r.text
        await db.refresh(llave)
        # Una llave expirada no se consume: queda activa pero inutilizable.
        assert llave.estado == "activa"


@pytest.mark.parametrize("codigo_invalido", ["", "corto", "1234"])
async def test_codigo_demasiado_corto_es_422(cliente, codigo_invalido):
    r = await cliente.post(RUTA_VALIDAR, json={"codigo": codigo_invalido})
    assert r.status_code == 422, r.text

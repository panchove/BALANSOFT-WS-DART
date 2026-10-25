"""Pruebas HTTP del módulo CÁMARAS (CRUD, diagnóstico y captura de placa).

Estrategia de ``test_semaforos_api.py``: app FastAPI fresca con overrides de
dependencias sobre la BD real de tests. El HAL de la cámara se sustituye por un
doble para no abrir sockets reales.

Cubre las reglas del negocio confirmadas por el cliente:

- Las fotos de placa se piden **una sola vez por boleto**: la primera captura
  (en la entrada o en la salida) fija ``fotos_placa_tomadas``.
- ``password`` nunca se expone en las respuestas de la API.
- Aislamiento multi-tenant: una cámara de otra empresa da 404.
- Las fotos quedan como media del boleto con ``tipo = 'placa'``.
"""

from __future__ import annotations

import os
import uuid

import httpx
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.api.v1.endpoints import camaras as camaras_mod
from app.core.camara_hal import CamaraHAL
from app.core.database import get_db
from app.models import BoletoPesaje, Camara, Empresa, ImagenPesaje, Usuario

# JPEG mínimo válido (1x1) para las respuestas simuladas de la cámara.
JPEG_1X1 = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300ff"
    "ffc00011080001000103012200021101031101ffc4001f000001050101010101"
    "0100000000000000000102030405060708090a0bffc400b51000020103030204"
    "03030504040306677d0102031104052131061241510761711322328108144291a1"
    "b1c109233352f0156272d10a162434e125f11718191a262728292a3536373849"
    "4a535455565758595a636465666768696a737475767778797a83848586878889"
    "8a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5"
    "c6c7c8c9cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7"
    "f8f9fa14010100020203110103110100000000000000000000000000ffda000c"
    "03010002110311003f00fbfeffd9"
)


def _app_para(db, user: Usuario, empresa: Empresa) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: user
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


@pytest_asyncio.fixture
async def admin(db, empresa):
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Cámara",
        email=f"admin-{uuid.uuid4().hex[:6]}@camara.demo",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def operador(db, empresa):
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Operador Cámara",
        email=f"op-{uuid.uuid4().hex[:6]}@camara.demo",
        password_hash="x",
        rol="OPERADOR",
        activo=True,
    )
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def app(db, admin, empresa):
    return _app_para(db, admin, empresa)


@pytest_asyncio.fixture
async def client(app):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest_asyncio.fixture
async def boleto(db, empresa) -> BoletoPesaje:
    """Boleto PENDIENTE mínimo, con entrada ya registrada."""
    from datetime import UTC, datetime
    from decimal import Decimal

    b = BoletoPesaje(
        id_empresa=empresa.id_empresa,
        numero_boleto=f"TA-{uuid.uuid4().hex[:6]}",
        id_vehiculo="A1B2C3",
        fecha_hora_entrada=datetime.now(UTC).replace(tzinfo=None),
        peso_entrada_vehiculo=Decimal("10000.00"),
        estado_boleto="PENDIENTE",
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    return b


async def _crear_camara(db, empresa, descripcion="Cámara entrada", **extra) -> Camara:
    camara = Camara(
        id_empresa=empresa.id_empresa,
        descripcion=descripcion,
        url_snapshot=extra.pop("url_snapshot", "http://127.0.0.1/snapshot.jpg"),
        **extra,
    )
    db.add(camara)
    await db.commit()
    await db.refresh(camara)
    return camara


def _hal_falso(datos=JPEG_1X1, conecta=True):
    """HAL de cámara con el snapshot resuelto en memoria (sin red)."""

    class _HAL:
        def __init__(self, *args, **kwargs):
            pass

        async def obtener_snapshot(self):
            return datos if conecta else None

        async def probar(self):
            if not conecta:
                return (False, None)
            return (True, {"tamano_kb": round(len(datos) / 1024, 1), "ancho": 1, "alto": 1})

    return _HAL


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------
class TestCrudCamaras:
    async def test_lista_vacia(self, client):
        r = await client.get("/api/v1/camaras")
        assert r.status_code == 200
        assert r.json() == []

    async def test_crear_aplica_defaults(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "Cámara entrada", "url_snapshot": "http://127.0.0.1/s.jpg"},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["url_snapshot"] == "http://127.0.0.1/s.jpg"
        assert data["ubicacion"] == "ambos"
        assert data["activo"] is True
        assert data["password_configurada"] is False

    async def test_crear_guarda_password_pero_no_la_expone(self, client, db, empresa):
        r = await client.post(
            "/api/v1/camaras",
            json={
                "descripcion": "Cámara con clave",
                "url_snapshot": "http://10.0.0.5/snap.jpg",
                "usuario": "admin",
                "password": "secreta",
            },
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert "password" not in data
        assert data["password_configurada"] is True
        # El valor sí quedó en la BD.
        fila = (
            await db.execute(
                Camara.__table__.select().where(
                    Camara.id_camara == uuid.UUID(data["id_camara"])
                )
            )
        ).first()
        assert fila is not None
        assert fila.password == "secreta"

    async def test_url_sin_esquema_devuelve_400(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "Mala", "url_snapshot": "10.0.0.5/snap.jpg"},
        )
        assert r.status_code == 400
        assert "http" in r.json()["detail"].lower()

    async def test_ubicacion_invalida_devuelve_422(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "Mala", "url_snapshot": "http://x/s.jpg", "ubicacion": "arriba"},
        )
        assert r.status_code == 422

    async def test_actualizar_cambia_ubicacion(self, client, db, empresa):
        camara = await _crear_camara(db, empresa)
        r = await client.put(
            f"/api/v1/camaras/{camara.id_camara}",
            json={
                "descripcion": "Cámara salida",
                "url_snapshot": camara.url_snapshot,
                "ubicacion": "salida",
            },
        )
        assert r.status_code == 200, r.text
        assert r.json()["ubicacion"] == "salida"

    async def test_eliminar(self, client, db, empresa):
        camara = await _crear_camara(db, empresa)
        r = await client.delete(f"/api/v1/camaras/{camara.id_camara}")
        assert r.status_code == 204
        assert (await client.get("/api/v1/camaras")).json() == []

    async def test_camara_de_otra_empresa_da_404(self, client, db, empresa):
        otra = Empresa(nombre_fiscal="Otra", rif_nit=f"J-{uuid.uuid4().hex[:8]}")
        db.add(otra)
        await db.commit()
        ajena = await _crear_camara(db, otra, descripcion="Ajena")
        r = await client.delete(f"/api/v1/camaras/{ajena.id_camara}")
        assert r.status_code == 404


# ---------------------------------------------------------------------------
# Permisos
# ---------------------------------------------------------------------------
class TestPermisosCamaras:
    async def test_operador_no_puede_crear(self, db, operador, empresa):
        app = _app_para(db, operador, empresa)
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.post(
                "/api/v1/camaras",
                json={"descripcion": "Cámara", "url_snapshot": "http://x/s.jpg"},
            )
        assert r.status_code == 403

    async def test_snapshot_permitido_para_operador(self, db, empresa, operador, monkeypatch):
        camara = await _crear_camara(db, empresa)
        monkeypatch.setattr(camaras_mod, "get_camara_hal", lambda c: _hal_falso()())
        app_op = _app_para(db, operador, empresa)
        transport = httpx.ASGITransport(app=app_op)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            r = await ac.get(f"/api/v1/camaras/{camara.id_camara}/snapshot")
        assert r.status_code == 200
        assert r.headers["content-type"] == "image/jpeg"
        assert r.content == JPEG_1X1


# ---------------------------------------------------------------------------
# Diagnóstico
# ---------------------------------------------------------------------------
class TestDiagnosticoCamaras:
    async def test_probar_conecta(self, client, db, empresa, monkeypatch):
        camara = await _crear_camara(db, empresa)
        monkeypatch.setattr(camaras_mod, "get_camara_hal", lambda c: _hal_falso()())
        r = await client.post(f"/api/v1/camaras/{camara.id_camara}/probar")
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["conectado"] is True
        assert data["tamano_kb"] is not None

    async def test_probar_sin_respuesta_no_conecta(self, client, db, empresa, monkeypatch):
        camara = await _crear_camara(db, empresa)
        monkeypatch.setattr(
            camaras_mod, "get_camara_hal", lambda c: _hal_falso(conecta=False)()
        )
        r = await client.post(f"/api/v1/camaras/{camara.id_camara}/probar")
        assert r.status_code == 200
        assert r.json()["conectado"] is False


# ---------------------------------------------------------------------------
# HAL real (transporte simulado): content-type y tamaño
# ---------------------------------------------------------------------------
class TestCamaraHAL:
    async def test_snapshot_ok(self):
        hal = CamaraHAL(
            "http://x/s.jpg",
            transport=httpx.MockTransport(
                lambda req: httpx.Response(
                    200, content=JPEG_1X1, headers={"content-type": "image/jpeg"}
                )
            ),
        )
        assert await hal.obtener_snapshot() == JPEG_1X1

    async def test_content_type_no_imagen_se_rechaza(self):
        hal = CamaraHAL(
            "http://x/s.jpg",
            transport=httpx.MockTransport(
                lambda req: httpx.Response(
                    200, content=b"<html>", headers={"content-type": "text/html"}
                )
            ),
        )
        assert await hal.obtener_snapshot() is None

    async def test_http_500_se_rechaza(self):
        hal = CamaraHAL(
            "http://x/s.jpg",
            transport=httpx.MockTransport(lambda req: httpx.Response(500, content=b"x")),
        )
        assert await hal.obtener_snapshot() is None

    async def test_excede_max_bytes_se_rechaza(self):
        hal = CamaraHAL(
            "http://x/s.jpg",
            max_bytes=10,
            transport=httpx.MockTransport(
                lambda req: httpx.Response(
                    200, content=JPEG_1X1, headers={"content-type": "image/jpeg"}
                )
            ),
        )
        assert await hal.obtener_snapshot() is None


# ---------------------------------------------------------------------------
# Captura de placa por boleto
# ---------------------------------------------------------------------------
class TestCapturaPlaca:
    async def test_capturar_guarda_media_y_marca_el_flag(
        self, client, db, empresa, boleto, monkeypatch, tmp_path
    ):
        from app.core import camara_hal as hal_mod
        from app.core import config as config_mod

        monkeypatch.setattr(config_mod.settings, "media_dir", str(tmp_path))
        monkeypatch.setattr(hal_mod, "get_camara_hal", lambda c: _hal_falso()())
        monkeypatch.setattr(camaras_mod, "get_camara_hal", lambda c: _hal_falso()())
        camara = await _crear_camara(db, empresa)
        r = await client.post(
            f"/api/v1/camaras/{camara.id_camara}/capturar",
            json={"boleto": str(boleto.boleto), "foto": "placa_trasera"},
        )
        assert r.status_code == 201, r.text
        data = r.json()
        assert data["tipo"] == "placa"
        assert data["url"].startswith(f"/media/{boleto.boleto}/placa_trasera_")

        # El archivo existe en disco.
        nombre = data["url"].rsplit("/", 1)[-1]
        assert os.path.exists(os.path.join(str(tmp_path), str(boleto.boleto), nombre))

        await db.refresh(boleto)
        assert boleto.fotos_placa_tomadas is True

    async def test_primera_captura_fija_el_flag_y_no_se_repite(
        self, client, db, empresa, boleto, monkeypatch, tmp_path
    ):
        """Invariante: las fotos se piden una sola vez por boleto."""
        from app.core import config as config_mod

        monkeypatch.setattr(config_mod.settings, "media_dir", str(tmp_path))
        monkeypatch.setattr(camaras_mod, "get_camara_hal", lambda c: _hal_falso()())
        camara = await _crear_camara(db, empresa)

        primera = await client.post(
            f"/api/v1/camaras/{camara.id_camara}/capturar",
            json={"boleto": str(boleto.boleto), "foto": "placa_trasera"},
        )
        assert primera.status_code == 201
        await db.refresh(boleto)
        assert boleto.fotos_placa_tomadas is True

        # La segunda captura del mismo boleto no rompe nada (el flag sigue fijo).
        segunda = await client.post(
            f"/api/v1/camaras/{camara.id_camara}/capturar",
            json={"boleto": str(boleto.boleto), "foto": "frente"},
        )
        assert segunda.status_code == 201
        await db.refresh(boleto)
        assert boleto.fotos_placa_tomadas is True

    async def test_imagen_subida_de_tipo_placa_tambien_fija_el_flag(
        self, client, db, empresa, boleto, monkeypatch, tmp_path
    ):
        """La foto tomada con la cámara LOCAL (subida normal) también cuenta."""
        from app.core import config as config_mod

        monkeypatch.setattr(config_mod.settings, "media_dir", str(tmp_path))
        r = await client.post(
            f"/api/v1/weighing/{boleto.boleto}/imagenes/archivo",
            files={"file": ("placa.jpg", JPEG_1X1, "image/jpeg")},
            data={"tipo": "placa"},
        )
        assert r.status_code == 201, r.text
        await db.refresh(boleto)
        assert boleto.fotos_placa_tomadas is True

    async def test_capturar_boleto_inexistente_da_404(self, client, db, empresa, monkeypatch):
        monkeypatch.setattr(camaras_mod, "get_camara_hal", lambda c: _hal_falso()())
        camara = await _crear_camara(db, empresa)
        r = await client.post(
            f"/api/v1/camaras/{camara.id_camara}/capturar",
            json={"boleto": str(uuid.uuid4()), "foto": "frente"},
        )
        assert r.status_code == 404

    async def test_capturar_sin_snapshot_da_502(self, client, db, empresa, boleto, monkeypatch):
        monkeypatch.setattr(
            camaras_mod, "get_camara_hal", lambda c: _hal_falso(conecta=False)()
        )
        camara = await _crear_camara(db, empresa)
        r = await client.post(
            f"/api/v1/camaras/{camara.id_camara}/capturar",
            json={"boleto": str(boleto.boleto), "foto": "frente"},
        )
        assert r.status_code == 502

    async def test_foto_desconocida_da_422(self, client, db, empresa, boleto):
        camara = await _crear_camara(db, empresa)
        r = await client.post(
            f"/api/v1/camaras/{camara.id_camara}/capturar",
            json={"boleto": str(boleto.boleto), "foto": "techo"},
        )
        assert r.status_code == 422

    async def test_la_imagen_capturada_es_tipo_placa(
        self, client, db, empresa, boleto, monkeypatch, tmp_path
    ):
        from app.core import config as config_mod

        monkeypatch.setattr(config_mod.settings, "media_dir", str(tmp_path))
        monkeypatch.setattr(camaras_mod, "get_camara_hal", lambda c: _hal_falso()())
        camara = await _crear_camara(db, empresa)
        await client.post(
            f"/api/v1/camaras/{camara.id_camara}/capturar",
            json={"boleto": str(boleto.boleto), "foto": "placa_remolque"},
        )
        filas = (
            await db.execute(
                ImagenPesaje.__table__.select().where(ImagenPesaje.boleto == boleto.boleto)
            )
        ).all()
        assert len(filas) == 1
        assert filas[0].tipo == "placa"


# ---------------------------------------------------------------------------
# Origen de la cámara: IP vs local/USB (migración 030)
# ---------------------------------------------------------------------------
class TestOrigenCamara:
    async def test_crear_ip_por_defecto(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "IP", "url_snapshot": "http://10.0.0.9/s.jpg"},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["origen"] == "ip"
        assert data["dispositivo"] is None

    async def test_crear_local_exige_dispositivo(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "Local", "origen": "local"},
        )
        assert r.status_code == 400
        assert "dispositivo" in r.json()["detail"].lower()

    async def test_crear_local_ok_y_limpia_url(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={
                "descripcion": "Webcam USB",
                "origen": "local",
                "dispositivo": "/dev/video2",
                "url_snapshot": "http://sobra/x.jpg",
            },
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["origen"] == "local"
        assert data["dispositivo"] == "/dev/video2"
        # La URL se ignora/vacía para las locales.
        assert data["url_snapshot"] == ""

    async def test_ip_exige_url_valida(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "Mala", "origen": "ip", "url_snapshot": "ftp://x/s.jpg"},
        )
        assert r.status_code == 400

    async def test_origen_invalido_da_422(self, client):
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "Mala", "origen": "satelite"},
        )
        assert r.status_code == 422

    async def test_filtro_por_origen(self, client, db, empresa):
        await _crear_camara(db, empresa, descripcion="IP uno")
        await _crear_camara(
            db, empresa, descripcion="Local uno", origen="local", dispositivo="/dev/video0"
        )
        r = await client.get("/api/v1/camaras", params={"origen": "local"})
        assert r.status_code == 200
        data = r.json()
        assert len(data) == 1
        assert data[0]["descripcion"] == "Local uno"
        assert data[0]["origen"] == "local"

    async def test_crear_local_no_exige_url(self, client):
        """Invariante de mutación: sin el origen, la URL vacía daría 400."""
        r = await client.post(
            "/api/v1/camaras",
            json={"descripcion": "Local sin url", "origen": "local", "dispositivo": "/dev/video9"},
        )
        assert r.status_code == 200, r.text


# ---------------------------------------------------------------------------
# Descubrimiento de cámaras
# ---------------------------------------------------------------------------
class TestDescubrirCamaras:
    async def test_descubrir_incluye_locales(self, client, monkeypatch):
        monkeypatch.setattr(
            camaras_mod,
            "descubrir_camaras_locales",
            lambda: [
                {
                    "origen": "local",
                    "dispositivo": "/dev/video0",
                    "descripcion": "Integrated_Webcam_HD",
                    "url_snapshot": "",
                }
            ],
        )
        r = await client.get("/api/v1/camaras/descubrir")
        assert r.status_code == 200, r.text
        data = r.json()
        assert len(data) == 1
        assert data[0]["origen"] == "local"
        assert data[0]["dispositivo"] == "/dev/video0"
        assert data[0]["descripcion"] == "Integrated_Webcam_HD"

    async def test_descubrir_puede_omitir_locales(self, client, monkeypatch):
        monkeypatch.setattr(
            camaras_mod,
            "descubrir_camaras_locales",
            lambda: [{"origen": "local", "dispositivo": "/dev/video0", "descripcion": "X"}],
        )
        r = await client.get("/api/v1/camaras/descubrir", params={"incluir_locales": False})
        assert r.status_code == 200
        assert r.json() == []

    async def test_descubrir_incluye_registradas(self, client, db, empresa, monkeypatch):
        monkeypatch.setattr(camaras_mod, "descubrir_camaras_locales", lambda: [])
        await _crear_camara(db, empresa, descripcion="IP registrada")
        r = await client.get("/api/v1/camaras/descubrir")
        assert r.status_code == 200
        data = r.json()
        assert len(data) == 1
        assert data[0]["origen"] == "ip"
        assert data[0]["descripcion"] == "IP registrada"

    async def test_descubrir_aislado_por_empresa(self, client, db, empresa, monkeypatch):
        monkeypatch.setattr(camaras_mod, "descubrir_camaras_locales", lambda: [])
        otra = Empresa(nombre_fiscal="Otra", rif_nit=f"J-{uuid.uuid4().hex[:8]}")
        db.add(otra)
        await db.commit()
        await _crear_camara(db, otra, descripcion="Ajena")
        r = await client.get("/api/v1/camaras/descubrir")
        assert r.status_code == 200
        assert r.json() == []


# ---------------------------------------------------------------------------
# HAL de cámara local (ffmpeg) — comandos y degradación sin hardware
# ---------------------------------------------------------------------------
class TestCamaraLocalHAL:
    async def test_sin_ffmpeg_devuelve_none(self, monkeypatch):
        from app.core import camara_hal as hal_mod

        monkeypatch.setattr(hal_mod.shutil, "which", lambda n: None)
        hal = hal_mod.CamaraLocalHAL("/dev/videoX")
        assert await hal.obtener_snapshot() is None

    def test_comando_linux_usa_v4l2(self, monkeypatch):
        from app.core import camara_hal as hal_mod

        hal = hal_mod.CamaraLocalHAL("/dev/video0")
        cmd = hal._comando("/tmp/x.jpg")
        assert "-f" in cmd and "v4l2" in cmd
        assert "/dev/video0" in cmd
        assert cmd[-1] == "/tmp/x.jpg"

    def test_parseo_v4l2_agrupa_por_dispositivo(self):
        from app.core import camara_hal as hal_mod

        salida = (
            "Integrated_Webcam_HD: Integrate (usb-0000:00:14.0-11):\n"
            "\t/dev/video0\n"
            "\t/dev/video1\n"
            "\t/dev/media0\n"
        )
        mapa = hal_mod._parsear_v4l2(salida)
        assert mapa == {
            "/dev/video0": "Integrated_Webcam_HD",
            "/dev/video1": "Integrated_Webcam_HD",
        }

    async def test_get_camara_hal_elige_local_por_origen(self):
        from app.core import camara_hal as hal_mod

        hal = hal_mod.get_camara_hal(
            {"origen": "local", "dispositivo": "/dev/video0", "url_snapshot": ""}
        )
        assert isinstance(hal, hal_mod.CamaraLocalHAL)
        ip = hal_mod.get_camara_hal(
            {"origen": "ip", "url_snapshot": "http://x/s.jpg", "usuario": None, "password": None}
        )
        assert isinstance(ip, hal_mod.CamaraHAL)


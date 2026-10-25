"""Pruebas HTTP del módulo SEMÁFORO (CRUD, descubrimiento, diagnóstico, control).

Estrategia de ``test_categorias_seguridad.py``: app FastAPI fresca con overrides
de dependencias sobre la BD real de tests. El HAL y el vigilante se sustituyen
por dobles, de modo que ninguna prueba abre puertos reales ni habla con el
simulador BSDD.
"""

from __future__ import annotations

import os
import pty
import uuid
from decimal import Decimal

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import Balanza, Empresa, Usuario
from app.services.semaforo_service import Luces

ESTADO_BSDD = {
    "rojo": {"encendido": True, "modo": "fijo"},
    "amarillo": {"encendido": False, "modo": "apagado"},
    "verde": {"encendido": False, "modo": "apagado"},
    "zumbador": False,
    "fase": "EXTERNO",
    "automatico": False,
    "timestamp": "2026-10-19T12:00:00Z",
}


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
        nombre="Admin Semáforo",
        email=f"admin-{uuid.uuid4().hex[:6]}@semaforo.demo",
        password_hash="x",
        rol="ADMIN",
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


async def _crear_balanza(db, empresa, codigo="BAL-1") -> Balanza:
    balanza = Balanza(
        id_empresa=empresa.id_empresa,
        codigo=codigo,
        descripcion="Báscula de prueba",
        protocolo="tcp",
        activo=True,
    )
    db.add(balanza)
    await db.commit()
    await db.refresh(balanza)
    return balanza


class _HALFalso:
    def __init__(self, estado=None, acepta=True):
        self.estado = estado
        self.acepta = acepta
        self.enviados: list[dict] = []

    async def enviar_comando(self, payload):
        self.enviados.append(dict(payload))
        return self.acepta

    async def leer_estado(self):
        return self.estado


class _ControllerFalso:
    def __init__(self):
        self.asegurados: list[str] = []
        self.detenidos: list[str] = []
        self.manuales: list[tuple[str, dict]] = []
        self.fase: str | None = None
        self.luces: Luces | None = None

    async def asegurar(self, id_semaforo):
        self.asegurados.append(str(id_semaforo))

    async def detener(self, id_semaforo):
        self.detenidos.append(str(id_semaforo))

    async def enviar_manual(self, semaforo, comando):
        self.manuales.append((str(semaforo.id_semaforo), comando))
        return True

    def fase_actual(self, id_semaforo):
        return self.fase

    def luces_actuales(self, id_semaforo):
        return self.luces


# ---------------------------------------------------------------------------
# CRUD
# ---------------------------------------------------------------------------
class TestCrudSemaforos:
    async def test_lista_vacia(self, client):
        r = await client.get("/api/v1/semaforos")
        assert r.status_code == 200
        assert r.json() == []

    async def test_crear_http_aplica_defaults_del_simulador(self, client):
        r = await client.post(
            "/api/v1/semaforos",
            json={"descripcion": "Semáforo entrada", "protocolo": "http"},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["ip_address"] == "127.0.0.1"
        assert data["puerto_tcp"] == 8080
        assert data["puerto_com"] is None
        assert data["control_automatico"] is False
        assert data["activo"] is True

    async def test_crear_serial_normaliza_los_campos(self, client):
        r = await client.post(
            "/api/v1/semaforos",
            json={
                "descripcion": "Semáforo serial",
                "protocolo": "serial",
                "puerto_com": "/dev/bsdd_semaforo_acm",
                "baudrate": 115200,
            },
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["puerto_com"] == "/dev/bsdd_semaforo_acm"
        assert data["ip_address"] is None
        assert data["puerto_tcp"] is None

    async def test_serial_sin_puerto_com_devuelve_400(self, client):
        r = await client.post(
            "/api/v1/semaforos",
            json={"descripcion": "Semáforo roto", "protocolo": "serial"},
        )
        assert r.status_code == 400
        assert "puerto" in r.json()["detail"].lower()

    async def test_automatico_sin_balanza_devuelve_400(self, client):
        r = await client.post(
            "/api/v1/semaforos",
            json={
                "descripcion": "Automático sin báscula",
                "protocolo": "http",
                "control_automatico": True,
            },
        )
        assert r.status_code == 400

    async def test_balanza_de_otra_empresa_devuelve_404(self, client, db):
        ajena = Empresa(
            nombre_fiscal="Otra",
            nombre_comercial="Otra",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
            activa=True,
        )
        db.add(ajena)
        await db.commit()
        balanza_ajena = await _crear_balanza(db, ajena, codigo="AJENA")
        r = await client.post(
            "/api/v1/semaforos",
            json={
                "descripcion": "Con báscula ajena",
                "protocolo": "http",
                "id_balanza": str(balanza_ajena.id_balanza),
            },
        )
        assert r.status_code == 404

    async def test_actualizar(self, client, db, empresa, monkeypatch):
        balanza = await _crear_balanza(db, empresa)
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        controller = _ControllerFalso()
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller", lambda: controller
        )
        r = await client.put(
            f"/api/v1/semaforos/{creado['id_semaforo']}",
            json={
                "descripcion": "Semáforo actualizado",
                "protocolo": "http",
                "ip_address": "192.168.0.9",
                "puerto_tcp": 8081,
                "id_balanza": str(balanza.id_balanza),
                "control_automatico": True,
                "umbral_cero_kg": 8.5,
            },
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["descripcion"] == "Semáforo actualizado"
        assert data["ip_address"] == "192.168.0.9"
        assert data["control_automatico"] is True
        assert Decimal(str(data["umbral_cero_kg"])) == Decimal("8.5")

    async def test_actualizar_inexistente_devuelve_404(self, client):
        r = await client.put(
            f"/api/v1/semaforos/{uuid.uuid4()}",
            json={"descripcion": "Fantasma", "protocolo": "http"},
        )
        assert r.status_code == 404

    async def test_eliminar(self, client):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        r = await client.delete(f"/api/v1/semaforos/{creado['id_semaforo']}")
        assert r.status_code == 204
        assert (await client.get("/api/v1/semaforos")).json() == []


class TestAislamientoMultiTenant:
    async def test_no_se_ve_ni_se_controla_el_semaforo_de_otra_empresa(
        self, client, db
    ):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo A", "protocolo": "http"},
            )
        ).json()

        otra = Empresa(
            nombre_fiscal="Empresa B",
            nombre_comercial="B",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
            activa=True,
        )
        db.add(otra)
        await db.commit()
        user_b = Usuario(
            id_empresa=otra.id_empresa,
            nombre="Admin B",
            email="adminb@semaforo.demo",
            password_hash="x",
            rol="ADMIN",
            activo=True,
        )
        db.add(user_b)
        await db.commit()

        transport = httpx.ASGITransport(app=_app_para(db, user_b, otra))
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            assert (await ac.get("/api/v1/semaforos")).json() == []
            assert (
                await ac.post(f"/api/v1/semaforos/{creado['id_semaforo']}/probar")
            ).status_code == 404
            assert (
                await ac.get(f"/api/v1/semaforos/{creado['id_semaforo']}/estado")
            ).status_code == 404
            assert (
                await ac.delete(f"/api/v1/semaforos/{creado['id_semaforo']}")
            ).status_code == 404


# ---------------------------------------------------------------------------
# Diagnóstico
# ---------------------------------------------------------------------------
class TestProbarEstado:
    async def test_probar_conectado(self, client, monkeypatch):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        monkeypatch.setattr(
            "app.api.v1.endpoints.semaforos.get_semaforo_hal",
            lambda semaforo: _HALFalso(estado=ESTADO_BSDD),
        )
        r = await client.post(f"/api/v1/semaforos/{creado['id_semaforo']}/probar")
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["conectado"] is True
        assert data["estado"] == ESTADO_BSDD

    async def test_probar_sin_respuesta(self, client, monkeypatch):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        monkeypatch.setattr(
            "app.api.v1.endpoints.semaforos.get_semaforo_hal",
            lambda semaforo: _HALFalso(estado=None),
        )
        r = await client.post(f"/api/v1/semaforos/{creado['id_semaforo']}/probar")
        assert r.status_code == 200
        assert r.json()["conectado"] is False

    async def test_estado_incluye_fase_y_luces_de_la_app(self, client, monkeypatch):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        controller = _ControllerFalso()
        controller.fase = "PESANDO"
        controller.luces = Luces(rojo="on")
        monkeypatch.setattr(
            "app.api.v1.endpoints.semaforos.get_semaforo_hal",
            lambda semaforo: _HALFalso(estado=ESTADO_BSDD),
        )
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller", lambda: controller
        )
        r = await client.get(f"/api/v1/semaforos/{creado['id_semaforo']}/estado")
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["conectado"] is True
        assert data["fase"] == "PESANDO"
        assert data["luces"] == {
            "rojo": "on",
            "amarillo": "off",
            "verde": "off",
            "zumbador": False,
        }


# ---------------------------------------------------------------------------
# Control manual
# ---------------------------------------------------------------------------
class TestComandoManual:
    async def test_comando_valido_se_aplica(self, client, monkeypatch, db):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        controller = _ControllerFalso()
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller", lambda: controller
        )
        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/comando",
            json={"color": "verde", "action": "on"},
        )
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["aplicado"] is True
        assert data["comando"] == {"color": "verde", "action": "on"}
        assert controller.manuales and controller.manuales[0][1] == {
            "color": "verde",
            "action": "on",
        }

    async def test_comando_invalido_devuelve_422(self, client):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/comando",
            json={"color": "azul"},
        )
        assert r.status_code == 422

    async def test_comando_vacio_devuelve_422(self, client):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/comando", json={}
        )
        assert r.status_code == 422

    async def test_all_off(self, client, monkeypatch):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller",
            lambda: _ControllerFalso(),
        )
        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/comando", json={"all": "off"}
        )
        assert r.status_code == 200
        assert r.json()["comando"] == {"all": "off"}

    @pytest.mark.parametrize(
        ("payload", "esperado"),
        [
            ({"rojo": True}, {"color": "rojo", "action": "on"}),
            ({"rojo": False}, {"color": "rojo", "action": "off"}),
            ({"verde": "flash"}, {"color": "verde", "action": "flash"}),
            ({"luz": "amarillo"}, {"color": "amarillo", "action": "on"}),
            (
                {"rojo": True, "zumbador": True},
                {"color": "rojo", "action": "on", "zumbador": "on"},
            ),
        ],
    )
    async def test_atajos_planos_del_spec(
        self, client, monkeypatch, payload, esperado
    ):
        """Los atajos planos del SPEC §5.6 se aceptan y se canonizan."""
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        controller = _ControllerFalso()
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller", lambda: controller
        )
        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/comando", json=payload
        )
        assert r.status_code == 200, r.text
        assert r.json()["comando"] == esperado
        assert controller.manuales[0][1] == esperado


class TestAutomatico:
    async def test_activar_y_desactivar(self, client, monkeypatch, db, empresa):
        balanza = await _crear_balanza(db, empresa)
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={
                    "descripcion": "Semáforo",
                    "protocolo": "http",
                    "id_balanza": str(balanza.id_balanza),
                },
            )
        ).json()
        controller = _ControllerFalso()
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller", lambda: controller
        )
        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/automatico",
            json={"activo": True},
        )
        assert r.status_code == 200, r.text
        assert r.json()["control_automatico"] is True
        assert controller.asegurados == [creado["id_semaforo"]]

        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/automatico",
            json={"activo": False},
        )
        assert r.status_code == 200
        assert r.json()["control_automatico"] is False
        assert controller.detenidos == [creado["id_semaforo"]]

    async def test_activar_sin_balanza_devuelve_400(self, client, monkeypatch):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        r = await client.post(
            f"/api/v1/semaforos/{creado['id_semaforo']}/automatico",
            json={"activo": True},
        )
        assert r.status_code == 400


# ---------------------------------------------------------------------------
# Descubrimiento
# ---------------------------------------------------------------------------
class TestDescubrir:
    async def test_encuentra_el_simulador_y_no_duplica_registrados(
        self, client, monkeypatch
    ):
        # Ya hay uno registrado en 127.0.0.1:8080: no debe volver a proponerse.
        await client.post(
            "/api/v1/semaforos",
            json={
                "descripcion": "Ya registrado",
                "protocolo": "http",
                "ip_address": "127.0.0.1",
                "puerto_tcp": 8080,
            },
        )

        master, slave = pty.openpty()
        try:
            nombre = os.ttyname(slave)
            monkeypatch.setenv("BSDD_SEMAFORO_SERIAL_GLOBS", nombre)
            llamadas: list[tuple] = []

            async def _falso(protocolo, host, puerto, com):
                llamadas.append((protocolo, host, puerto, com))
                if protocolo == "http" and puerto == 8080:
                    return True, ESTADO_BSDD
                if protocolo == "serial":
                    return True, ESTADO_BSDD
                return False, None

            monkeypatch.setattr(
                "app.api.v1.endpoints.semaforos._probar_candidato", _falso
            )
            r = await client.get("/api/v1/semaforos/descubrir")
            assert r.status_code == 200, r.text
            data = r.json()
            protocolos = {d["protocolo"] for d in data}
            # El HTTP registrado se omitió, pero el serie simulado aparece.
            assert "serial" in protocolos
            assert not any(
                d["protocolo"] == "http" and d["puerto_tcp"] == 8080 for d in data
            )
        finally:
            os.close(master)
            os.close(slave)

    async def test_incluir_simulados_false_no_prueba_el_bsdd(self, client, monkeypatch):
        llamadas: list[tuple] = []

        async def _falso(protocolo, host, puerto, com):
            llamadas.append((protocolo, host, puerto, com))
            return False, None

        monkeypatch.setattr(
            "app.api.v1.endpoints.semaforos._probar_candidato", _falso
        )
        r = await client.get("/api/v1/semaforos/descubrir?incluir_simulados=false")
        assert r.status_code == 200
        assert not any(
            host == "127.0.0.1" and puerto == 8080 for _, host, puerto, _ in llamadas
        )

    async def test_registra_el_semaforo_serie_simulado_si_responde(
        self, client, monkeypatch
    ):
        master, slave = pty.openpty()
        try:
            nombre = os.ttyname(slave)
            monkeypatch.setenv("BSDD_SEMAFORO_SERIAL_GLOBS", nombre)

            async def _falso(protocolo, host, puerto, com):
                if protocolo == "serial" and com == nombre:
                    return True, ESTADO_BSDD
                return False, None

            monkeypatch.setattr(
                "app.api.v1.endpoints.semaforos._probar_candidato", _falso
            )
            r = await client.get("/api/v1/semaforos/descubrir")
            assert r.status_code == 200
            data = r.json()
            assert any(
                d["protocolo"] == "serial"
                and d["puerto_com"] == nombre
                and d["is_simulado"] is True
                for d in data
            )
        finally:
            os.close(master)
            os.close(slave)


# ---------------------------------------------------------------------------
# Integración: el vigilante arranca con el semáforo automático
# ---------------------------------------------------------------------------
class TestCreacionArrancaElVigilante:
    async def test_crear_automatico_asegura_el_vigilante(
        self, client, monkeypatch, db, empresa
    ):
        balanza = await _crear_balanza(db, empresa)
        controller = _ControllerFalso()
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller", lambda: controller
        )
        r = await client.post(
            "/api/v1/semaforos",
            json={
                "descripcion": "Automático",
                "protocolo": "http",
                "id_balanza": str(balanza.id_balanza),
                "control_automatico": True,
            },
        )
        assert r.status_code == 200, r.text
        assert controller.asegurados == [r.json()["id_semaforo"]]

    async def test_eliminar_detiene_el_vigilante(self, client, monkeypatch):
        creado = (
            await client.post(
                "/api/v1/semaforos",
                json={"descripcion": "Semáforo", "protocolo": "http"},
            )
        ).json()
        controller = _ControllerFalso()
        monkeypatch.setattr(
            "app.services.semaforo_service.get_semaforo_controller", lambda: controller
        )
        await client.delete(f"/api/v1/semaforos/{creado['id_semaforo']}")
        assert controller.detenidos == [creado["id_semaforo"]]

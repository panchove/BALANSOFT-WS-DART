"""Pruebas funcionales HTTP de los endpoints de pesaje y autenticación.

Usa una app FastAPI fresca (sin middleware de auditoría para aislar de la BD
real), override de dependencias (usuario/empresa/DB) y un License Manager falso
via monkeypatch de get_license_client.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator

import httpx
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.api.v1.endpoints import auth as auth_module
from app.api.v1.endpoints import inventario as inventario_module
from app.api.v1.endpoints import pesajes as pesajes_module
from app.core import scale_session as scale_session_module
from app.core.database import get_db
from app.core.license_client import LicenseInfo
from app.models import Auditoria, Usuario


class FakeLM:
    """Cliente LM falso que siempre valida de forma positiva."""

    def check(self, license_key: str):
        return {"tier": "ENTERPRISE", "status": "ACTIVE"}

    def validate(self, license_key: str, hardware_id: str, **kwargs):
        return LicenseInfo(valid=True, tier="ENTERPRISE", status="ACTIVE", message="ok")

    def activate(self, license_key: str, hardware_id: str, **kwargs):
        return {"ok": True, "status": "ACTIVE"}

    def validate_or_activate(self, license_key: str, hardware_id: str, **kwargs):
        return self.validate(license_key, hardware_id, **kwargs)

    def validate_cached(self, license_key: str, hardware_id: str, **kwargs):
        return self.validate_or_activate(license_key, hardware_id, **kwargs)


class FakeHAL:
    """HAL de balanza falso para probar el endpoint de conexión."""

    def __init__(self, peso: float | None = 100.0, estable: bool = True):
        self._peso = peso
        self._estable = estable

    async def read_weight(self) -> float | None:
        return self._peso

    async def is_stable(self, duration_seconds: int = 3, tolerance_kg: float = 0.5):
        return self._estable


@pytest_asyncio.fixture
async def app(db, empresa, monkeypatch) -> FastAPI:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Test",
        email="admin@test.demo",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()

    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: user
    application.dependency_overrides[get_current_empresa] = lambda: empresa

    monkeypatch.setattr(pesajes_module, "get_license_client", FakeLM)
    monkeypatch.setattr(auth_module, "get_license_client", FakeLM)
    return application


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


class TestPesajeEndpoints:
    async def test_create_pendiente(self, client, db):
        r = await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "XYZ-123",
                "transporte_nombre": "Trans Test",
                "conductor_nombre": "Pepe",
                "producto_nombre": "Cemento",
                "almacen_nombre": "Planta A",
                "balanza_nombre": "B1",
                "tercero_nombre": "Cliente X",
                "peso_entrada_vehiculo": "50000",
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["id_vehiculo"] == "XYZ-123"
        assert body["estado_boleto"] == "PENDIENTE"
        assert body["numero_boleto"].startswith("TA-")

    async def test_duplicado_pendiente_400(self, client):
        payload = {
            "id_vehiculo": "DUP-01",
            "transporte_nombre": "T",
            "conductor_nombre": "C",
            "producto_nombre": "P",
            "almacen_nombre": "A",
            "balanza_nombre": "B",
            "tercero_nombre": "X",
            "peso_entrada_vehiculo": "50000",
        }
        assert (await client.post("/api/v1/weighing/create", json=payload)).status_code == 200
        r2 = await client.post("/api/v1/weighing/create", json=payload)
        assert r2.status_code == 400
        assert "pendiente" in r2.json()["detail"]

    async def test_pendientes_lista(self, client):
        await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "PEN-01",
                "transporte_nombre": "T",
                "conductor_nombre": "C",
                "producto_nombre": "P",
                "almacen_nombre": "A",
                "balanza_nombre": "B",
                "tercero_nombre": "X",
                "peso_entrada_vehiculo": "50000",
            },
        )
        r = await client.get("/api/v1/weighing/pendientes")
        assert r.status_code == 200
        pen = [p for p in r.json() if p["id_vehiculo"] == "PEN-01"]
        assert pen
        assert pen[0]["transporte_nombre"] is not None
        assert pen[0]["conductor_nombre"] is not None

    async def test_pendientes_muestra_nombres_no_uuids(self, client):
        """El pendiente resuelve los nombres legibles desde el catálogo; nunca
        cuela el identificador crudo (UUID) en el campo de nombre."""
        await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "NOM-01",
                "transporte_nombre": "Transportes Expresos del Centro C.A.",
                "conductor_nombre": "C. Mendoza",
                "producto_nombre": "Cemento Tipo I a Granel",
                "almacen_nombre": "Silo Principal",
                "balanza_nombre": "Balanza Camionera",
                "tercero_nombre": "Corporación Venezolana de Cemento",
                "peso_entrada_vehiculo": "38250",
            },
        )
        r = await client.get("/api/v1/weighing/pendientes")
        assert r.status_code == 200
        pen = [p for p in r.json() if p["id_vehiculo"] == "NOM-01"][0]
        assert pen["transporte_nombre"] == "Transportes Expresos del Centro C.A."
        assert "C. Mendoza" in pen["conductor_nombre"]
        assert pen["producto_nombre"] == "Cemento Tipo I a Granel"
        assert pen["almacen_nombre"] == "Silo Principal"
        assert "fe000000" not in (pen.get("transporte_nombre") or "")

    async def test_boleto_detalle_resuelve_nombres_y_remolque(self, client):
        """El detalle de un boleto con remolque devuelve nombres legibles y la
        placa del remolque (el front lo usa en la UI)."""
        created = await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "DET-01",
                "transporte_nombre": "Transportes Expresos del Centro C.A.",
                "producto_nombre": "Cemento Tipo I a Granel",
                "almacen_nombre": "Silo Principal",
                "remolque": True,
                "remolque_placa": "RAP55M",
                "peso_entrada_vehiculo": "38250",
            },
        )
        assert created.status_code == 200, created.text
        boleto = created.json()["boleto"]
        r = await client.get(f"/api/v1/weighing/boleto/{boleto}")
        assert r.status_code == 200
        body = r.json()
        assert body["transporte_nombre"] == "Transportes Expresos del Centro C.A."
        assert body["producto_nombre"] == "Cemento Tipo I a Granel"
        assert body["remolque"] is True
        assert body["remolque_placa"] == "RAP55M"

    async def test_cerrar_calcula_neto(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "CIE-01",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "50000",
                },
            )
        ).json()
        boleto = created["boleto"]
        r = await client.post(
            f"/api/v1/weighing/close/{boleto}",
            json={"peso_salida_vehiculo": "45000", "densidad": "1.6"},
        )
        assert r.status_code == 200, r.text
        # El peso se serializa como Decimal -> string "5000.00"
        assert r.json()["peso_neto"] == "5000.00"

    async def test_pdf_genera(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "PDF-01",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "50000",
                },
            )
        ).json()
        boleto = created["boleto"]
        r = await client.get(f"/api/v1/weighing/{boleto}/pdf")
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("application/pdf")

    async def test_pdf_con_parametros_layout(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "LAYOUT-01",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "42000",
                },
            )
        ).json()
        boleto = created["boleto"]
        params = {
            "boletos_por_hoja": 3,
            "tamano_papel": "A4",
            "orientacion": "landscape",
            "mostrar_encabezado": False,
            "mostrar_detalles": False,
        }
        r = await client.get(f"/api/v1/weighing/{boleto}/pdf", params=params)
        assert r.status_code == 200
        assert r.headers["content-type"].startswith("application/pdf")

    async def test_txt_stream(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "TXT-01",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "35000",
                },
            )
        ).json()
        boleto = created["boleto"]
        r = await client.get(f"/api/v1/weighing/{boleto}/txt")
        assert r.status_code == 200
        assert "text/plain" in r.headers["content-type"]
        assert "TXT-01" in r.text

    async def test_txt_404_boleto_inexistente(self, client):
        r = await client.get(f"/api/v1/weighing/{uuid.uuid4()}/txt")
        assert r.status_code == 404

    async def test_404_boleto_inexistente(self, client):
        r = await client.get(f"/api/v1/weighing/boleto/{uuid.uuid4()}")
        assert r.status_code == 404

    async def test_list_con_filtro_estado(self, client):
        await client.post(
            "/api/v1/weighing/create",
            json={
                "id_vehiculo": "FIL-01",
                "transporte_nombre": "T",
                "conductor_nombre": "C",
                "producto_nombre": "P",
                "almacen_nombre": "A",
                "balanza_nombre": "B",
                "tercero_nombre": "X",
                "peso_entrada_vehiculo": "50000",
            },
        )
        r = await client.get("/api/v1/weighing/list", params={"estado": "PENDIENTE"})
        assert r.status_code == 200
        assert all(p["estado_boleto"] == "PENDIENTE" for p in r.json())

    async def test_create_guarda_formulario_avanzado_y_peso_manual(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "PM-01",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "50000",
                    "es_peso_manual": True,
                    "peso_neto_declarado": "4990",
                    "guia_sunagro": "SUNAGRO-TEST-99",
                    "medida": "M3",
                    "densidad": "1.6",
                    "unidades": "2",
                },
            )
        ).json()
        assert created["peso_neto_declarado"] == "4990.00"
        assert created["es_peso_manual"] is True
        boleto = created["boleto"]
        body = (await client.get(f"/api/v1/weighing/boleto/{boleto}")).json()
        assert body["es_peso_manual"] is True
        assert body["guia_sunagro"] == "SUNAGRO-TEST-99"
        assert body["medida"] == "M3"
        from decimal import Decimal as _D
        assert _D(str(body["densidad"])) == _D("1.6000")

    async def test_close_guarda_formulario_avanzado_y_peso_manual(self, client):
        created = (
            await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": "PM-02",
                    "transporte_nombre": "T",
                    "conductor_nombre": "C",
                    "producto_nombre": "P",
                    "almacen_nombre": "A",
                    "balanza_nombre": "B",
                    "tercero_nombre": "X",
                    "peso_entrada_vehiculo": "50000",
                },
            )
        ).json()
        boleto = created["boleto"]
        r = await client.post(
            f"/api/v1/weighing/close/{boleto}",
            json={
                "peso_salida_vehiculo": "45000",
                "es_peso_manual": True,
                "guia_sunagro": "SUNAGRO-C",
                "medida": "M3",
                "flete": "BS 100",
                "costo_flete": "250.00",
            },
        )
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["es_peso_manual"] is True
        detail = (await client.get(f"/api/v1/weighing/boleto/{boleto}")).json()
        assert detail["guia_sunagro"] == "SUNAGRO-C"
        assert detail["medida"] == "M3"
        assert detail["flete"] == "BS 100"
        assert detail["costo_flete"] == "250.00" or detail["costo_flete"] == 250.00


class TestAuthEndpoints:
    async def test_register_crea_admin(self, app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as ac:
            resp = await ac.post(
                "/api/v1/auth/register",
                json={
                    "empresa_nombre": "Empresa Nueva",
                    "empresa_rif": f"J-{uuid.uuid4().hex[:8]}",
                    "licencia_key": "LIC-DEMO-001",
                    "usuario_nombre": "Dueño",
                    "email": f"user{uuid.uuid4().hex[:6]}@test.demo",
                    "password": "secret123",
                },
            )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        assert body["access_token"]
        assert body["user"]["rol"] == "ADMIN"

    async def test_licencia_empresa_snapshot(self, app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as ac:
            resp = await ac.get("/api/v1/auth/license")
        assert resp.status_code == 200
        payload = resp.json()
        assert payload["valid"] is True
        assert payload["tier"] == "CENTRAL"
        assert payload["status"] == "ACTIVE"
        assert "registros_actuales" in payload

    async def test_login_credenciales_invalidas(self, app):
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://t") as ac:
            r = await ac.post(
                "/api/v1/auth/login",
                json={"email": "nobody@test.demo", "password": "wrong"},
            )
        assert r.status_code == 401


class TestDispositivosEndpoints:
    """Módulo de dispositivos: configuración y prueba de conexión de balanzas."""

    async def _crear_balanza(self, client, descripcion="B1", **extra):
        r = await client.post("/api/v1/balanzas", json={"descripcion": descripcion, **extra})
        assert r.status_code == 200, r.text
        return r.json()

    async def test_crear_balanza_con_hardware(self, client):
        body = await self._crear_balanza(
            client, ip_address="127.0.0.1", puerto_tcp=5555, protocolo="tcp"
        )
        assert body["ip_address"] == "127.0.0.1"
        assert body["puerto_tcp"] == 5555
        assert body["protocolo"] == "tcp"
        assert body["activo"] is True

    async def test_probar_sin_hardware_400(self, client):
        body = await self._crear_balanza(client)
        r = await client.post(f"/api/v1/balanzas/{body['id_balanza']}/probar")
        assert r.status_code == 400
        assert "hardware" in r.json()["detail"]

    async def test_probar_no_encontrada_404(self, client):
        r = await client.post(f"/api/v1/balanzas/{uuid.uuid4()}/probar")
        assert r.status_code == 404

    async def test_probar_conectado(self, client, monkeypatch):
        body = await self._crear_balanza(
            client, ip_address="192.168.0.50", puerto_tcp=5555, protocolo="tcp"
        )
        monkeypatch.setattr(
            scale_session_module,
            "get_scale_hal",
            lambda balanza: FakeHAL(12345.5, True),
        )
        r = await client.post(f"/api/v1/balanzas/{body['id_balanza']}/probar")
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["conectado"] is True
        assert data["peso_kg"] == 12345.5
        assert data["estable"] is True
        assert data["hardware"] == "tcp"
        assert data["protocolo"] == "tcp"

    async def test_probar_desconectado(self, client, monkeypatch):
        body = await self._crear_balanza(
            client, ip_address="192.168.0.99", puerto_tcp=5555, protocolo="tcp"
        )
        monkeypatch.setattr(
            scale_session_module,
            "get_scale_hal",
            lambda balanza: FakeHAL(None, False),
        )
        r = await client.post(f"/api/v1/balanzas/{body['id_balanza']}/probar")
        assert r.status_code == 200
        data = r.json()
        assert data["conectado"] is False
        assert data["detalle"]

    async def test_crear_balanza_simulada(self, client):
        sim = await self._crear_balanza(
            client,
            descripcion="Simulada",
            is_simulada=True,
            ip_address="127.0.0.1",
            puerto_tcp=5555,
            protocolo="tcp",
        )
        assert sim["is_simulada"] is True
        fisica = await self._crear_balanza(client, descripcion="Física")
        assert fisica["is_simulada"] is False

    async def test_descubrir_omite_registradas(self, client, monkeypatch):
        class FakeTcp:  # noqa: D106
            def __init__(self, host: str, port: int):
                self.host = host
                self.port = port

            async def read_weight(self) -> float:
                return 100.0

        monkeypatch.setattr(inventario_module, "TcpScaleHAL", FakeTcp)
        await self._crear_balanza(client, ip_address="127.0.0.1", puerto_tcp=5555, protocolo="tcp")
        r = await client.get("/api/v1/balanzas/descubrir")
        assert r.status_code == 200, r.text
        assert isinstance(r.json(), list)
        assert not any(d["protocolo"] == "tcp" and d["ip_address"] == "127.0.0.1" for d in r.json())

    async def test_descubrir_tcp_disponible(self, client, monkeypatch):
        class FakeTcp:  # noqa: D106
            def __init__(self, host: str, port: int):
                self.host = host
                self.port = port

            async def read_weight(self) -> float:
                return 321.5

        monkeypatch.setattr(inventario_module, "TcpScaleHAL", FakeTcp)
        r = await client.get("/api/v1/balanzas/descubrir")
        assert r.status_code == 200, r.text
        assert any(
            d["ip_address"] == "127.0.0.1" and d["puerto_tcp"] == 5555 and d["peso_kg"] == 321.5
            for d in r.json()
        )

    async def test_catalogo_sync_incluye_hardware(self, client):
        await self._crear_balanza(client, ip_address="10.0.0.7", puerto_tcp=5556, protocolo="tcp")
        r = await client.get("/api/v1/catalogo/sync")
        assert r.status_code == 200
        balanzas = r.json()["balanzas"]
        assert any(b["ip_address"] == "10.0.0.7" and b["puerto_tcp"] == 5556 for b in balanzas)


class TestCatalogoSyncPaginacion:
    """Paginación de /catalogo/sync (H11)."""

    async def _crear_almacenes(self, client, n: int) -> None:
        for i in range(n):
            r = await client.post(
                "/api/v1/almacenes",
                json={"codigo": f"ALM-{i:02d}", "nombre": f"Patio {i}"},
            )
            assert r.status_code == 200, r.text

    async def test_totales_sin_recorte(self, client):
        await self._crear_almacenes(client, 3)
        r = await client.get("/api/v1/catalogo/sync")
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["truncado"] is False
        assert body["totales"]["almacenes"] == 3
        assert len(body["almacenes"]) == 3

    async def test_limit_y_skip_paginan(self, client):
        await self._crear_almacenes(client, 3)
        r1 = await client.get("/api/v1/catalogo/sync?limit=2")
        assert r1.status_code == 200, r1.text
        page1 = r1.json()
        assert page1["truncado"] is True
        assert len(page1["almacenes"]) == 2
        assert page1["totales"]["almacenes"] == 3

        r2 = await client.get("/api/v1/catalogo/sync?limit=2&skip=2")
        page2 = r2.json()
        assert page2["truncado"] is False
        assert len(page2["almacenes"]) == 1
        ids1 = {a["id_almacen"] for a in page1["almacenes"]}
        ids2 = {a["id_almacen"] for a in page2["almacenes"]}
        assert not (ids1 & ids2)

    async def test_filtra_por_catalogo(self, client):
        await self._crear_almacenes(client, 2)
        r = await client.get("/api/v1/catalogo/sync?catalogo=almacenes")
        assert r.status_code == 200, r.text
        body = r.json()
        assert set(body["totales"]) == {"almacenes"}
        assert body["productos"] == []
        assert len(body["almacenes"]) == 2

    async def test_catalogo_desconocido_404(self, client):
        r = await client.get("/api/v1/catalogo/sync?catalogo=inventado")
        assert r.status_code == 404


class TestAuditoriaEndpoint:
    """Consulta del registro de auditoría (D4)."""

    async def _sembrar(self, db, empresa):
        db.add_all(
            [
                Auditoria(
                    id_empresa=empresa.id_empresa,
                    accion="CREATE",
                    entidad="boletos_pesaje",
                    entidad_id="TA-1",
                    detalle={"numero_boleto": "TA-00000001"},
                    ip="127.0.0.1",
                ),
                Auditoria(
                    id_empresa=empresa.id_empresa,
                    accion="DELETE",
                    entidad="marcas",
                    entidad_id="m-1",
                    ip="10.0.0.9",
                ),
            ]
        )
        await db.commit()

    async def test_listar_auditoria(self, client, db, empresa):
        await self._sembrar(db, empresa)
        r = await client.get("/api/v1/auditoria")
        assert r.status_code == 200, r.text
        filas = r.json()
        assert len(filas) == 2
        assert {f["accion"] for f in filas} == {"CREATE", "DELETE"}
        assert all(f["created_at"] for f in filas)

    async def test_filtra_por_entidad(self, client, db, empresa):
        await self._sembrar(db, empresa)
        r = await client.get("/api/v1/auditoria?entidad=marcas")
        assert r.status_code == 200, r.text
        filas = r.json()
        assert len(filas) == 1
        assert filas[0]["entidad"] == "marcas"


class TestListadoNoEsNMasUno:
    """El listado de boletos no debe enriquecer fila por fila (regresión P2).

    Con 50k boletos, `/weighing/list` y `/weighing/pendientes` tardaban ~450 ms
    p50 porque llamaban a `_enriquecer_pesaje_ticket` **por registro**, que lanza
    hasta 10 consultas: una página de 100 boletos se convertía en ~1000 idas y
    vueltas a PostgreSQL. Con `_enriquecer_pesajes_lista` son 7 consultas por
    página, constantes, y el p50 bajó a ~20 ms.

    Estos tests fijan esa propiedad: el número de sentencias SQL debe ser
    **constante** al crecer la página, no lineal. Sin ellos, reintroducir el
    enriquecimiento por fila pasaría inadvertido y volvería el costo por
    `limit` en producción.
    """

    @staticmethod
    async def _contar(ruta: str, client, params: dict) -> tuple[int, list[dict]]:
        """Ejecuta un listado contando las sentencias SQL que emite."""
        from sqlalchemy import event
        from sqlalchemy.engine import Engine

        counted: list[str] = []

        def _cuenta(conn, cursor, statement, parameters, context, executemany):
            counted.append(statement)

        event.listen(Engine, "after_cursor_execute", _cuenta)
        try:
            r = await client.get(ruta, params=params)
        finally:
            event.remove(Engine, "after_cursor_execute", _cuenta)
        assert r.status_code == 200, r.text
        return len(counted), r.json()

    async def _sembrar(self, client, n: int, prefijo: str) -> None:
        for i in range(n):
            r = await client.post(
                "/api/v1/weighing/create",
                json={
                    "id_vehiculo": f"{prefijo}-{i:03d}",
                    "transporte_nombre": f"Transporte {i % 7}",
                    "conductor_nombre": f"Conductor {i % 11}",
                    "producto_nombre": f"Producto {i % 13}",
                    "almacen_nombre": f"Almacen {i % 5}",
                    "balanza_nombre": f"Bal {i % 3}",
                    "tercero_nombre": f"Tercero {i % 9}",
                    "peso_entrada_vehiculo": str(20000 + i),
                },
            )
            assert r.status_code in (200, 201), r.text

    async def test_consultas_no_crecen_con_el_tamano_de_la_pagina(self, client):
        await self._sembrar(client, 12, "N1")
        consultas_4, filas_4 = await self._contar(
            "/api/v1/weighing/list", client, {"skip": 0, "limit": 4})
        consultas_12, filas_12 = await self._contar(
            "/api/v1/weighing/list", client, {"skip": 0, "limit": 12})
        assert len(filas_4) == 4
        assert len(filas_12) == 12
        # Con N+1 serían 3x más sentencias al triplicar el limit. Se admite un
        # margen por los COUNT de paginación, nunca un crecimiento lineal.
        assert consultas_12 <= consultas_4 + 4, (
            f"el listado volvió a consultar por fila: {consultas_4} → "
            f"{consultas_12} sentencias al pasar de 4 a 12 boletos"
        )

    async def test_nombres_legibles_por_pagina(self, client):
        """La resolución por lotes debe poblar los mismos nombres que antes."""
        await self._sembrar(client, 3, "N2")
        _, filas = await self._contar("/api/v1/weighing/list", client,
                                      {"skip": 0, "limit": 3})
        assert len(filas) == 3
        for f in filas:
            assert f["producto_nombre"] is not None
            assert f["conductor_nombre"] is not None
            assert f["transporte_nombre"] is not None
            assert f["almacen_nombre"] is not None
            assert f["balanza_nombre"] is not None
            assert f["tercero_nombre"] is not None

    async def test_pendientes_tambien_usa_resolucion_por_lotes(self, client):
        await self._sembrar(client, 5, "N3")
        consultas, filas = await self._contar(
            "/api/v1/weighing/pendientes", client, {"limit": 5})
        assert len(filas) == 5
        assert consultas <= 12, (
            f"/pendientes lanza {consultas} sentencias para 5 boletos; "
            f"debería resolverse por lotes (≤ 12)"
        )

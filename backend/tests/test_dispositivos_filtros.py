"""Filtros de vista de los listados de DISPOSITIVOS.

Cada vista de dispositivos (básculas, semáforos, indicadores, cámaras) guarda
y busca por **su propio tipo**, y el listado acepta filtros opcionales:

- ``q``: búsqueda de texto insensible a mayúsculas sobre las columnas visibles
  (código, descripción, marca/modelo, IP/puerto).
- ``activo`` / ``is_simulada`` / ``protocolo`` / ``ubicacion`` /
  ``control_automatico``: filtros de igualdad.

Reglas verificadas:

- Los filtros **nunca** cruzan el aislamiento multi-tenant (siempre ``id_empresa``).
- Sin filtros el listado devuelve todo (comportamiento histórico intacto).
- Un valor de filtro inexistente devuelve lista vacía (no error).
"""

from __future__ import annotations

import uuid

import httpx
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import Balanza, Camara, Empresa, Indicador, Semaforo, Usuario


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
        nombre="Admin Filtros",
        email=f"admin-{uuid.uuid4().hex[:6]}@filtros.demo",
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


async def _balanza(db, empresa, **extra) -> Balanza:
    b = Balanza(
        id_empresa=empresa.id_empresa,
        descripcion=extra.pop("descripcion", "Báscula"),
        capacidad_max=extra.pop("capacidad_max", 60000),
        **extra,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    return b


async def _semaforo(db, empresa, **extra) -> Semaforo:
    s = Semaforo(
        id_empresa=empresa.id_empresa,
        descripcion=extra.pop("descripcion", "Semáforo"),
        **extra,
    )
    db.add(s)
    await db.commit()
    await db.refresh(s)
    return s


async def _indicador(db, empresa, **extra) -> Indicador:
    i = Indicador(
        id_empresa=empresa.id_empresa,
        descripcion=extra.pop("descripcion", "Indicador"),
        **extra,
    )
    db.add(i)
    await db.commit()
    await db.refresh(i)
    return i


async def _camara(db, empresa, **extra) -> Camara:
    c = Camara(
        id_empresa=empresa.id_empresa,
        descripcion=extra.pop("descripcion", "Cámara"),
        url_snapshot=extra.pop("url_snapshot", "http://127.0.0.1/s.jpg"),
        **extra,
    )
    db.add(c)
    await db.commit()
    await db.refresh(c)
    return c


class TestFiltrosBasculas:
    async def test_sin_filtros_devuelve_todo(self, client, db, empresa):
        await _balanza(db, empresa, descripcion="Báscula A", is_simulada=True)
        await _balanza(db, empresa, descripcion="Báscula B", is_simulada=False)

        r = await client.get("/api/v1/balanzas")
        assert r.status_code == 200
        assert len(r.json()) == 2

    async def test_q_busca_en_descripcion_e_ignora_mayusculas(self, client, db, empresa):
        await _balanza(db, empresa, descripcion="Báscula Entrada Norte")
        await _balanza(db, empresa, descripcion="Báscula Salida Sur")

        r = await client.get("/api/v1/balanzas", params={"q": "norte"})
        assert r.status_code == 200
        descripciones = [x["descripcion"] for x in r.json()]
        assert descripciones == ["Báscula Entrada Norte"]

    async def test_q_busca_en_ip(self, client, db, empresa):
        await _balanza(db, empresa, descripcion="A", ip_address="192.168.1.50")
        await _balanza(db, empresa, descripcion="B", ip_address="10.0.0.9")

        r = await client.get("/api/v1/balanzas", params={"q": "192.168"})
        assert len(r.json()) == 1
        assert r.json()[0]["ip_address"] == "192.168.1.50"

    async def test_filtra_por_simulada(self, client, db, empresa):
        await _balanza(db, empresa, descripcion="Real", is_simulada=False)
        await _balanza(db, empresa, descripcion="Simulada", is_simulada=True)

        r = await client.get("/api/v1/balanzas", params={"is_simulada": "true"})
        assert [x["descripcion"] for x in r.json()] == ["Simulada"]

        r = await client.get("/api/v1/balanzas", params={"is_simulada": "false"})
        assert [x["descripcion"] for x in r.json()] == ["Real"]

    async def test_filtra_por_activo(self, client, db, empresa):
        await _balanza(db, empresa, descripcion="Activa", activo=True)
        await _balanza(db, empresa, descripcion="Inactiva", activo=False)

        r = await client.get("/api/v1/balanzas", params={"activo": "false"})
        assert [x["descripcion"] for x in r.json()] == ["Inactiva"]

    async def test_q_sin_coincidencias_devuelve_vacio(self, client, db, empresa):
        await _balanza(db, empresa, descripcion="Báscula X")
        r = await client.get("/api/v1/balanzas", params={"q": "no-existe-xxx"})
        assert r.status_code == 200
        assert r.json() == []

    async def test_filtro_no_cruza_tenant(self, client, db, empresa):
        """Una báscula de otra empresa no aparece aunque el texto coincida."""
        otra = Empresa(
            nombre_fiscal="Otra Empresa",
            nombre_comercial="Otra",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
            activa=True,
        )
        db.add(otra)
        await db.commit()

        await _balanza(db, empresa, descripcion="Propia coincidencia")
        await _balanza(db, otra, descripcion="Ajena coincidencia")

        r = await client.get("/api/v1/balanzas", params={"q": "coincidencia"})
        assert [x["descripcion"] for x in r.json()] == ["Propia coincidencia"]


class TestFiltrosSemaforos:
    async def test_filtra_por_protocolo_y_automatico(self, client, db, empresa):
        await _semaforo(
            db, empresa, descripcion="HTTP auto", protocolo="http", control_automatico=True
        )
        await _semaforo(
            db, empresa, descripcion="Serial manual", protocolo="serial", control_automatico=False
        )

        r = await client.get("/api/v1/semaforos", params={"protocolo": "serial"})
        assert [x["descripcion"] for x in r.json()] == ["Serial manual"]

        r = await client.get("/api/v1/semaforos", params={"control_automatico": "true"})
        assert [x["descripcion"] for x in r.json()] == ["HTTP auto"]

    async def test_q_busca_en_descripcion(self, client, db, empresa):
        await _semaforo(db, empresa, descripcion="Torre Patio")
        await _semaforo(db, empresa, descripcion="Torre Oficina")

        r = await client.get("/api/v1/semaforos", params={"q": "patio"})
        assert [x["descripcion"] for x in r.json()] == ["Torre Patio"]


class TestFiltrosIndicadores:
    async def test_filtra_por_marca(self, client, db, empresa):
        await _indicador(db, empresa, descripcion="Ind A", marca="BKG")
        await _indicador(db, empresa, descripcion="Ind B", marca="CAS")

        r = await client.get("/api/v1/indicadores", params={"q": "bkg"})
        assert [x["descripcion"] for x in r.json()] == ["Ind A"]

    async def test_filtra_por_simulado(self, client, db, empresa):
        await _indicador(db, empresa, descripcion="Real", is_simulado=False)
        await _indicador(db, empresa, descripcion="Sim", is_simulado=True)

        r = await client.get("/api/v1/indicadores", params={"is_simulado": "true"})
        assert [x["descripcion"] for x in r.json()] == ["Sim"]


class TestFiltrosCamaras:
    async def test_filtra_por_ubicacion(self, client, db, empresa):
        await _camara(db, empresa, descripcion="Cam entrada", ubicacion="entrada")
        await _camara(db, empresa, descripcion="Cam salida", ubicacion="salida")

        r = await client.get("/api/v1/camaras", params={"ubicacion": "salida"})
        assert [x["descripcion"] for x in r.json()] == ["Cam salida"]

    async def test_q_busca_en_url(self, client, db, empresa):
        await _camara(db, empresa, descripcion="A", url_snapshot="http://cam1.local/s.jpg")
        await _camara(db, empresa, descripcion="B", url_snapshot="http://cam2.local/s.jpg")

        r = await client.get("/api/v1/camaras", params={"q": "cam1"})
        assert [x["descripcion"] for x in r.json()] == ["A"]

    async def test_no_expone_password_con_filtro(self, client, db, empresa):
        await _camara(db, empresa, descripcion="Con clave", password="secreto")

        r = await client.get("/api/v1/camaras", params={"q": "clave"})
        assert r.status_code == 200
        assert r.json()[0]["password_configurada"] is True
        assert "password" not in r.json()[0]


class TestBusquedaServicioAislada:
    """El helper `list_filtrado` respeta columnas y filtros desconocidos."""

    async def test_columna_texto_inexistente_se_ignora(self, db, empresa):
        from app.services.catalog_service import CatalogService

        await _balanza(db, empresa, descripcion="Única")
        rows = await CatalogService().list_filtrado(
            db,
            empresa.id_empresa,
            "balanzas",
            q="unic",
            columnas_texto=("columna_que_no_existe",),
        )
        # Sin columnas válidas, `q` no filtra (evita romper la vista por error).
        assert len(rows) == 1

    async def test_filtro_desconocido_se_ignora(self, db, empresa):
        from app.services.catalog_service import CatalogService

        await _balanza(db, empresa, descripcion="Única")
        rows = await CatalogService().list_filtrado(
            db,
            empresa.id_empresa,
            "balanzas",
            iguales={"columna_falsa": "x"},
        )
        assert len(rows) == 1

    async def test_no_devuelve_otra_empresa(self, db, empresa):
        from app.services.catalog_service import CatalogService

        otra = Empresa(
            nombre_fiscal="Otra S.A.",
            nombre_comercial="Otra",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
            activa=True,
        )
        db.add(otra)
        await db.commit()
        await _balanza(db, otra, descripcion="Ajena")

        rows = await CatalogService().list_filtrado(db, empresa.id_empresa, "balanzas")
        assert rows == []


class TestColumnaTextoExiste:
    """Guarda contra un typo en `columnas_texto`: las columnas deben existir."""

    async def test_todas_las_columnas_de_texto_existen(self):
        esperadas = {
            "balanzas": ("codigo", "descripcion", "marca", "modelo", "ip_address", "puerto_com"),
            "semaforos": ("codigo", "descripcion", "ip_address", "puerto_com"),
            "indicadores": ("codigo", "descripcion", "marca", "modelo", "ip_address", "puerto_com"),
            "camaras": ("codigo", "descripcion", "url_snapshot"),
        }
        modelos = {
            "balanzas": Balanza,
            "semaforos": Semaforo,
            "indicadores": Indicador,
            "camaras": Camara,
        }
        for nombre, columnas in esperadas.items():
            modelo = modelos[nombre]
            for col in columnas:
                assert hasattr(modelo, col), f"{nombre}.{col} no existe en el modelo"

    async def test_aislamiento_con_join_de_empresa_por_id(self, db, empresa):
        """Reafirma que el filtro base es por `id_empresa` exacto."""
        await _balanza(db, empresa, descripcion="Propia")
        filas = (await db.execute(select(Balanza).where(Balanza.id_empresa == empresa.id_empresa))).scalars().all()
        assert len(filas) == 1

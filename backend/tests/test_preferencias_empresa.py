"""Pruebas de las preferencias de la empresa (idioma y formatos de exportación).

Cubren la configuración inicial de la instalación (docs/I18N_Y_ONBOARDING.md
REQ-NF-CFG-001, REQ-FN-CFG-004): ``PUT /api/v1/empresa`` solo por ADMIN, el
idioma de la empresa governa los tickets y ``empresas.formato_ticket`` decide
qué formato devuelve ``GET /api/v1/weighing/{boleto}/export``.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import BoletoPesaje, Usuario
from app.schemas import EmpresaPerfilOut


def _app_con_rol(db, empresa, rol: str) -> FastAPI:
    """App FastAPI con el usuario del rol indicado ya autenticado."""
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre=f"Usuario {rol}",
        email=f"{rol.lower()}-{uuid.uuid4().hex[:8]}@test.demo",
        password_hash="x",
        rol=rol,
        activo=True,
    )
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
    db.add(
        Usuario(
            id_empresa=empresa.id_empresa,
            nombre="Admin",
            email=f"admin-{uuid.uuid4().hex[:8]}@test.demo",
            password_hash="x",
            rol="ADMIN",
            activo=True,
        )
    )
    await db.commit()
    return _app_con_rol(db, empresa, "ADMIN")


@pytest_asyncio.fixture
async def operador(db, empresa):
    return _app_con_rol(db, empresa, "OPERADOR")


def _cliente(app: FastAPI) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")


class TestPerfilEmpresa:
    @pytest.mark.asyncio
    async def test_admin_actualiza_idioma_y_formatos(self, admin, empresa):
        async with _cliente(admin) as ac:
            r = await ac.put(
                "/api/v1/empresa",
                json={
                    "idioma": "pt",
                    "formato_ticket": "TXT",
                    "formato_reporte": "PDF",
                },
            )
        assert r.status_code == 200
        salida = EmpresaPerfilOut.model_validate(r.json())
        assert salida.idioma == "pt"
        assert salida.formato_ticket == "TXT"
        assert salida.formato_reporte == "PDF"

    @pytest.mark.asyncio
    async def test_idioma_invalido_es_rechazado(self, admin):
        async with _cliente(admin) as ac:
            r = await ac.put("/api/v1/empresa", json={"idioma": "fr"})
        assert r.status_code == 422

    @pytest.mark.asyncio
    async def test_formato_reporte_acepta_excel_y_rechaza_xlsx(self, admin):
        """Contrato con la app Flutter: envía EXCEL|PDF, nunca XLSX."""
        async with _cliente(admin) as ac:
            ok = await ac.put("/api/v1/empresa", json={"formato_reporte": "EXCEL"})
            mal = await ac.put("/api/v1/empresa", json={"formato_reporte": "XLSX"})
        assert ok.status_code == 200
        assert EmpresaPerfilOut.model_validate(ok.json()).formato_reporte == "EXCEL"
        assert mal.status_code == 422

    @pytest.mark.asyncio
    async def test_operador_no_puede_editar(self, operador):
        async with _cliente(operador) as ac:
            r = await ac.put("/api/v1/empresa", json={"idioma": "en"})
        assert r.status_code == 403
        # Sin Accept-Language el mensaje sale en el idioma por defecto (es).
        assert r.json()["detail"] == "Solo el ADMIN puede editar el perfil de la empresa."

    @pytest.mark.asyncio
    async def test_error_traducido_al_ingles(self, operador):
        async with _cliente(operador) as ac:
            r = await ac.put(
                "/api/v1/empresa",
                json={"idioma": "en"},
                headers={"Accept-Language": "en-US,en;q=0.9"},
            )
        assert r.status_code == 403
        assert r.json()["detail"] == "Only the ADMIN can edit the company profile."

    @pytest.mark.asyncio
    async def test_error_traducido_segun_accept_language(self, operador):
        async with _cliente(operador) as ac:
            r = await ac.put(
                "/api/v1/empresa",
                json={"idioma": "en"},
                headers={"Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8"},
            )
        assert r.status_code == 403
        assert r.json()["detail"] == "Somente o ADMIN pode editar o perfil da empresa."

    @pytest.mark.asyncio
    async def test_get_perfil_incluye_preferencias(self, operador, empresa):
        empresa.idioma = "en"
        empresa.formato_reporte = "PDF"
        async with _cliente(operador) as ac:
            r = await ac.get("/api/v1/empresa")
        assert r.status_code == 200
        cuerpo = r.json()
        assert cuerpo["idioma"] == "en"
        assert cuerpo["formato_reporte"] == "PDF"


class TestExportPorFormatoConfigurado:
    @staticmethod
    async def _boleto(db, empresa) -> BoletoPesaje:
        boleto = BoletoPesaje(
            id_empresa=empresa.id_empresa,
            numero_boleto="TA-00000042",
            id_vehiculo="ABC-123",
            fecha_hora_entrada=datetime.now(UTC).replace(tzinfo=None),
            peso_entrada_vehiculo="1000",
            estado_boleto=BoletoPesaje.ESTADO_PENDIENTE,
        )
        db.add(boleto)
        await db.commit()
        await db.refresh(boleto)
        return boleto

    @pytest.mark.asyncio
    async def test_export_respeta_formato_ticket_e_idioma(self, operador, db, empresa):
        boleto = await self._boleto(db, empresa)
        empresa.formato_ticket = "TXT"
        empresa.idioma = "en"
        async with _cliente(operador) as ac:
            r = await ac.get(f"/api/v1/weighing/{boleto.numero_boleto}/export")
        assert r.status_code == 200
        assert r.headers["content-disposition"].endswith('.txt"')
        assert "WEIGHING TICKET" in r.text

    @pytest.mark.asyncio
    async def test_export_usa_pdf_por_defecto(self, operador, db, empresa):
        boleto = await self._boleto(db, empresa)
        empresa.formato_ticket = "PDF"
        empresa.idioma = "es"
        async with _cliente(operador) as ac:
            r = await ac.get(f"/api/v1/weighing/{boleto.numero_boleto}/export")
        assert r.status_code == 200
        assert r.headers["content-disposition"].endswith('.pdf"')
        assert r.content[:4] == b"%PDF"

    @pytest.mark.asyncio
    async def test_param_idioma_tiene_prioridad_sobre_empresa(self, operador, db, empresa):
        boleto = await self._boleto(db, empresa)
        empresa.formato_ticket = "TXT"
        empresa.idioma = "es"
        async with _cliente(operador) as ac:
            r = await ac.get(
                f"/api/v1/weighing/{boleto.numero_boleto}/export",
                params={"idioma": "pt"},
            )
        assert r.status_code == 200
        assert "BILHETE DE PESAGEM" in r.text

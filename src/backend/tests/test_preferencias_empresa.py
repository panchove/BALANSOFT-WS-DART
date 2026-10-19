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
from app.models import BoletoPesaje, Empresa, Usuario
from app.schemas import EmpresaPerfilOut

TAMANOS = ("AUTOMATICO", "GRANDE", "MEDIANO", "PEQUENO")
FUENTE = "DejaVu"


def _app_con_tenant_real(db, usuario: Usuario) -> FastAPI:
    """App donde `get_current_empresa` **no** está sobrescrito.

    `_app_con_rol` (arriba) inyecta la empresa por `dependency_overrides`, así que
    el tenant llega fijo y un test de aislamiento pasa siempre: enmascararía
    justo el fallo que se quiere detectar. Aquí solo se sustituye la
    autenticación, y `get_current_empresa` resuelve la empresa desde
    `usuario.id_empresa`, igual que en producción.
    """
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: usuario
    return application


async def _crear_admin(db, empresa: Empresa, sufijo: str) -> Usuario:
    usuario = Usuario(
        id_empresa=empresa.id_empresa,
        nombre=f"Admin {sufijo}",
        email=f"admin-{sufijo}-{uuid.uuid4().hex[:8]}@test.demo",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(usuario)
    await db.commit()
    return usuario


async def _otra_empresa(db, sufijo: str = "B") -> Empresa:
    empresa = Empresa(
        nombre_fiscal=f"Empresa {sufijo}",
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        activa=True,
    )
    db.add(empresa)
    await db.commit()
    await db.refresh(empresa)
    return empresa


def _app_solo_db(db) -> FastAPI:
    """App sin overrides de autenticación, para `/auth/login-local`.

    Ese endpoint no depende de `get_current_user`: valida credenciales contra la
    BD, así que el login exercised es el real de la estación.
    """
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    return application


async def _usuario_local(db, empresa: Empresa, clave: str = "demo1234") -> Usuario:
    from app.core.security import hash_password

    usuario = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Local",
        email=f"local-{uuid.uuid4().hex[:8]}@test.demo",
        password_hash=hash_password(clave),
        rol="ADMIN",
        activo=True,
    )
    db.add(usuario)
    await db.commit()
    return usuario


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


# ---------------------------------------------------------------------------
# Tipografía del ticket (REQ-FN-009/014): `tamano_ticket_pdf` + `fuente_ticket_pdf`
# ---------------------------------------------------------------------------
class TestTipografiaTicketEnApi:
    @pytest.mark.asyncio
    async def test_get_devuelve_los_dos_campos_nuevos(self, operador, empresa):
        empresa.tamano_ticket_pdf = "GRANDE"
        empresa.fuente_ticket_pdf = FUENTE
        async with _cliente(operador) as ac:
            r = await ac.get("/api/v1/empresa")
        assert r.status_code == 200
        cuerpo = r.json()
        assert cuerpo["tamano_ticket_pdf"] == "GRANDE"
        assert cuerpo["fuente_ticket_pdf"] == FUENTE

    @pytest.mark.asyncio
    async def test_get_devuelve_los_defaults_si_no_hay_valores(self, operador):
        async with _cliente(operador) as ac:
            r = await ac.get("/api/v1/empresa")
        assert r.status_code == 200
        assert r.json()["tamano_ticket_pdf"] == "AUTOMATICO"
        assert r.json()["fuente_ticket_pdf"] == FUENTE

    @pytest.mark.asyncio
    @pytest.mark.parametrize("valor", TAMANOS)
    async def test_put_acepta_cada_paso_del_ticket(self, admin, valor):
        async with _cliente(admin) as ac:
            r = await ac.put("/api/v1/empresa", json={"tamano_ticket_pdf": valor})
        assert r.status_code == 200, r.text
        assert EmpresaPerfilOut.model_validate(r.json()).tamano_ticket_pdf == valor

    @pytest.mark.asyncio
    async def test_put_acepta_dejavu_como_fuente(self, admin):
        async with _cliente(admin) as ac:
            r = await ac.put("/api/v1/empresa", json={"fuente_ticket_pdf": FUENTE})
        assert r.status_code == 200
        assert EmpresaPerfilOut.model_validate(r.json()).fuente_ticket_pdf == FUENTE

    @pytest.mark.asyncio
    @pytest.mark.parametrize("valor", ["GIGANTE", "grande", "AUTO", "", "GRANDE "])
    async def test_put_rechaza_paso_fuera_del_literal(self, admin, valor):
        async with _cliente(admin) as ac:
            r = await ac.put("/api/v1/empresa", json={"tamano_ticket_pdf": valor})
        assert r.status_code == 422, r.text

    @pytest.mark.asyncio
    async def test_put_null_desfija_y_get_devuelve_el_default(self, admin, db, empresa):
        """`null` significa "sin fijar": se guarda NULL y GET normaliza al default.

        El plan define el campo de entrada como `Literal | None = Field(None)`, así
        que `null` es un valor válido, no un 422. Lo que no puede pasar es que un
        NULL tumbe la respuesta: por eso `EmpresaPerfilOut` lo traduce al default.
        """
        async with _cliente(admin) as ac:
            r = await ac.put("/api/v1/empresa", json={"tamano_ticket_pdf": None})
            assert r.status_code == 200, r.text
            assert r.json()["tamano_ticket_pdf"] == "AUTOMATICO"

        await db.refresh(empresa)
        assert empresa.tamano_ticket_pdf is None

        async with _cliente(admin) as ac:
            again = await ac.get("/api/v1/empresa")
        assert again.status_code == 200
        assert again.json()["tamano_ticket_pdf"] == "AUTOMATICO"

    @pytest.mark.asyncio
    @pytest.mark.parametrize("valor", ["Roboto", "dejavu", "Arial"])
    async def test_put_rechaza_fuente_fuera_del_literal(self, admin, valor):
        """REQ-FN-014: la API no puede ofrecer una familia que no sea DejaVu."""
        async with _cliente(admin) as ac:
            r = await ac.put("/api/v1/empresa", json={"fuente_ticket_pdf": valor})
        assert r.status_code == 422, r.text

    @pytest.mark.asyncio
    async def test_put_no_toca_la_persistencia_entre_peticiones(self, admin, db, empresa):
        """El valor enviado queda en la BD, no solo en la respuesta."""
        async with _cliente(admin) as ac:
            await ac.put("/api/v1/empresa", json={"tamano_ticket_pdf": "MEDIANO"})
        await db.refresh(empresa)
        assert empresa.tamano_ticket_pdf == "MEDIANO"

    @pytest.mark.asyncio
    @pytest.mark.parametrize(
        "payload",
        [
            {"tamano_ticket_pdf": "GRANDE"},
            {"fuente_ticket_pdf": "DejaVu"},
        ],
    )
    async def test_put_por_no_admin_es_403(self, operador, payload):
        async with _cliente(operador) as ac:
            r = await ac.put("/api/v1/empresa", json=payload)
        assert r.status_code == 403, r.text


class TestAislamientoTenanteTipografia:
    """Ajuste menor #2: el tenant se deriva del token, nunca del cuerpo."""

    @pytest.mark.asyncio
    async def test_get_solo_muestra_la_empresa_del_token(self, db, empresa):
        """GET como usuario de A no puede exponer los datos de B."""
        admin_a = await _crear_admin(db, empresa, "A")
        empresa_b = await _otra_empresa(db)
        empresa_b.tamano_ticket_pdf = "GRANDE"
        await db.commit()

        app = _app_con_tenant_real(db, admin_a)
        async with _cliente(app) as ac:
            r = await ac.get("/api/v1/empresa")

        assert r.status_code == 200
        assert r.json()["id_empresa"] == str(empresa.id_empresa)
        assert r.json()["tamano_ticket_pdf"] == "AUTOMATICO", "se filtró el valor de B"

    @pytest.mark.asyncio
    async def test_put_no_modifica_la_empresa_b(self, db, empresa):
        admin_a = await _crear_admin(db, empresa, "A")
        empresa_b = await _otra_empresa(db)

        app = _app_con_tenant_real(db, admin_a)
        async with _cliente(app) as ac:
            r = await ac.put("/api/v1/empresa", json={"tamano_ticket_pdf": "GRANDE"})
        assert r.status_code == 200

        await db.refresh(empresa_b)
        assert empresa_b.tamano_ticket_pdf == "AUTOMATICO", "B fue modificada por A"
        await db.refresh(empresa)
        assert empresa.tamano_ticket_pdf == "GRANDE"

    @pytest.mark.asyncio
    async def test_id_empresa_en_el_body_se_descarta(self, db, empresa):
        """Cubre el bucle `setattr` de empresa.py: el body no puede cambiar el tenant."""
        admin_a = await _crear_admin(db, empresa, "A")
        empresa_b = await _otra_empresa(db)
        empresa_b.tamano_ticket_pdf = "PEQUENO"
        await db.commit()

        app = _app_con_tenant_real(db, admin_a)
        async with _cliente(app) as ac:
            r = await ac.put(
                "/api/v1/empresa",
                json={"id_empresa": str(empresa_b.id_empresa), "tamano_ticket_pdf": "GRANDE"},
            )
        assert r.status_code == 200, r.text
        assert r.json()["id_empresa"] == str(empresa.id_empresa)

        await db.refresh(empresa_b)
        assert empresa_b.tamano_ticket_pdf == "PEQUENO", "B fue movida desde el body de A"
        await db.refresh(empresa)
        assert empresa.tamano_ticket_pdf == "GRANDE"


# ---------------------------------------------------------------------------
# T3b · La respuesta de login entrega la preferencia (REQ-FN-009)
# ---------------------------------------------------------------------------
class TestPreferenciaEnLogin:
    """Sin esto la app Flutter arranca sin la preferencia configurada."""

    @staticmethod
    async def _login(db, empresa: Empresa) -> dict:
        usuario = await _usuario_local(db, empresa)
        app = _app_solo_db(db)
        async with _cliente(app) as ac:
            r = await ac.post(
                "/api/v1/auth/login-local",
                json={"email": usuario.email, "password": "demo1234"},
            )
        assert r.status_code == 200, r.text
        return r.json()

    @pytest.mark.asyncio
    async def test_login_devuelve_los_dos_campos_con_el_default(self, db, empresa):
        cuerpo = await self._login(db, empresa)
        assert cuerpo["empresa"]["tamano_ticket_pdf"] == "AUTOMATICO"
        assert cuerpo["empresa"]["fuente_ticket_pdf"] == FUENTE

    @pytest.mark.asyncio
    async def test_login_refleja_el_valor_configurado(self, db, empresa):
        empresa.tamano_ticket_pdf = "GRANDE"
        await db.commit()
        cuerpo = await self._login(db, empresa)
        assert cuerpo["empresa"]["tamano_ticket_pdf"] == "GRANDE"

    @pytest.mark.asyncio
    async def test_login_normaliza_null_al_default(self, db, empresa):
        """Una columna heredada en NULL no puede devolver null al cliente.

        `CompanyOut` es `Literal` sin `| None`: si el mapeo no normalizara, la
        validación de respuesta fallaría con 500.
        """
        empresa.tamano_ticket_pdf = None
        empresa.fuente_ticket_pdf = None
        await db.commit()
        cuerpo = await self._login(db, empresa)
        assert cuerpo["empresa"]["tamano_ticket_pdf"] == "AUTOMATICO"
        assert cuerpo["empresa"]["fuente_ticket_pdf"] == FUENTE

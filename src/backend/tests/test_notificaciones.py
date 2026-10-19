"""Pruebas del centro de notificaciones y recordatorios (backend local).

Cubre las dos mitades del subsistema:

* **Servicio** (`app/services/notification_service.py`): idempotencia por
  ``dedup_key``, evaluación de cada evento (licencia, sync, boletos, series) y
  recurrencia de recordatorios.
* **API** (`app/api/v1/endpoints/notificaciones.py`): bandeja, resumen,
  lectura/archivado y CRUD de recordatorios, con aislamiento multi-tenant.

El canal nativo del SO se prueba con ``monkeypatch`` (no hay bus de sesión en
CI): lo relevante es que sin canal no se marca nada como entregado.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path

import httpx
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core import notification_scheduler as sched
from app.core.database import get_db
from app.models import (
    BoletoPesaje,
    Empresa,
    Notificacion,
    Recordatorio,
    SerieNumeracion,
    SyncQueue,
    Usuario,
)
from app.services import notification_service as svc


def _ahora() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


async def _empresa_extra(db) -> Empresa:
    """Segunda empresa (para probar aislamiento multi-tenant)."""
    otra = Empresa(
        nombre_fiscal="Otra Empresa",
        nombre_comercial="Otra S.A.",
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        licencia_tier="CENTRAL",
        licencia_status="ACTIVE",
        activa=True,
    )
    db.add(otra)
    await db.commit()
    await db.refresh(otra)
    return otra


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest_asyncio.fixture
async def admin(db, empresa) -> Usuario:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Notif",
        email=f"admin-{uuid.uuid4().hex[:6]}@test.demo",
        password_hash="x",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


@pytest_asyncio.fixture
async def app(db, empresa, admin) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: admin
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


# ---------------------------------------------------------------------------
# Servicio: alta e idempotencia
# ---------------------------------------------------------------------------


class TestCrearNotificacion:
    async def test_dedup_key_impide_duplicados(self, db, empresa):
        primera = await svc.crear_notificacion(
            db,
            id_empresa=empresa.id_empresa,
            tipo="prueba",
            titulo="Hola",
            dedup_key="clave-1",
        )
        segunda = await svc.crear_notificacion(
            db,
            id_empresa=empresa.id_empresa,
            tipo="prueba",
            titulo="Hola otra vez",
            dedup_key="clave-1",
        )
        await db.commit()
        assert primera is not None
        assert segunda is None
        filas = (await db.execute(select(Notificacion))).scalars().all()
        assert len(filas) == 1

    async def test_misma_clave_en_otra_empresa_si_crea(self, db, empresa):
        otra = await _empresa_extra(db)
        await svc.crear_notificacion(
            db,
            id_empresa=empresa.id_empresa,
            tipo="prueba",
            titulo="A",
            dedup_key="misma",
        )
        creada = await svc.crear_notificacion(
            db,
            id_empresa=otra.id_empresa,
            tipo="prueba",
            titulo="B",
            dedup_key="misma",
        )
        assert creada is not None

    async def test_sin_dedup_key_permite_repetir(self, db, empresa):
        for _ in range(3):
            creada = await svc.crear_notificacion(
                db, id_empresa=empresa.id_empresa, tipo="manual", titulo="Anuncio"
            )
            assert creada is not None
        await db.commit()

    async def test_severidad_invalida_cae_a_info(self, db, empresa):
        creada = await svc.crear_notificacion(
            db,
            id_empresa=empresa.id_empresa,
            tipo="prueba",
            titulo="X",
            severidad="inexistente",
        )
        assert creada is not None
        assert creada.severidad == "info"


# ---------------------------------------------------------------------------
# Servicio: eventos
# ---------------------------------------------------------------------------


class TestEvaluarLicencia:
    async def test_por_vencer_genera_aviso_y_no_duplica(self, db, empresa):
        empresa.licencia_expira = _ahora() + timedelta(days=5)
        await db.commit()

        assert await svc.evaluar_eventos(db) >= 1
        await db.commit()
        segunda = await svc.evaluar_eventos(db)
        await db.commit()
        assert segunda == 0, "re-evaluar el mismo día no debe duplicar el aviso"

        filas = (await db.execute(select(Notificacion))).scalars().all()
        assert [f.tipo for f in filas] == ["licencia_por_vencer"]

    async def test_vencida_genera_aviso_critico(self, db, empresa):
        empresa.licencia_expira = _ahora() - timedelta(days=1)
        await db.commit()

        await svc.evaluar_eventos(db)
        await db.commit()
        fila = (await db.execute(select(Notificacion))).scalar_one()
        assert fila.tipo == "licencia_vencida"
        assert fila.severidad == "critica"

    async def test_sin_fecha_no_genera_nada(self, db, empresa):
        empresa.licencia_expira = None
        await db.commit()
        assert await svc.evaluar_eventos(db) == 0


class TestEvaluarSync:
    async def test_pendiente_atrasado_genera_aviso(self, db, empresa):
        db.add(
            SyncQueue(
                id_empresa=empresa.id_empresa,
                entidad="boletos",
                operacion="create",
                entidad_id=str(uuid.uuid4()),
                pendiente=True,
                created_at=_ahora() - timedelta(hours=2),
            )
        )
        await db.commit()

        await svc.evaluar_eventos(db)
        await db.commit()
        tipos = [f.tipo for f in (await db.execute(select(Notificacion))).scalars().all()]
        assert "sync_pendiente" in tipos

    async def test_pendiente_reciente_no_genera_aviso(self, db, empresa):
        db.add(
            SyncQueue(
                id_empresa=empresa.id_empresa,
                entidad="boletos",
                operacion="create",
                entidad_id=str(uuid.uuid4()),
                pendiente=True,
                created_at=_ahora(),
            )
        )
        await db.commit()
        assert await svc.evaluar_eventos(db) == 0

    async def test_fallido_tras_reintentos_genera_aviso(self, db, empresa):
        db.add(
            SyncQueue(
                id_empresa=empresa.id_empresa,
                entidad="boletos",
                operacion="create",
                entidad_id=str(uuid.uuid4()),
                pendiente=True,
                intentos=99,
                error="timeout",
            )
        )
        await db.commit()

        await svc.evaluar_eventos(db)
        await db.commit()
        tipos = [f.tipo for f in (await db.execute(select(Notificacion))).scalars().all()]
        assert "sync_fallido" in tipos


class TestEvaluarBoletos:
    async def test_pendiente_antiguo_genera_aviso(self, db, empresa):
        db.add(
            BoletoPesaje(
                id_empresa=empresa.id_empresa,
                estado_boleto=BoletoPesaje.ESTADO_PENDIENTE,
                fecha_hora_entrada=_ahora() - timedelta(hours=30),
                peso_entrada_vehiculo=Decimal("1000.00"),
            )
        )
        await db.commit()

        await svc.evaluar_eventos(db)
        await db.commit()
        tipos = [f.tipo for f in (await db.execute(select(Notificacion))).scalars().all()]
        assert "boletos_pendientes" in tipos

    async def test_pendiente_reciente_no_genera_aviso(self, db, empresa):
        db.add(
            BoletoPesaje(
                id_empresa=empresa.id_empresa,
                estado_boleto=BoletoPesaje.ESTADO_PENDIENTE,
                fecha_hora_entrada=_ahora() - timedelta(hours=1),
                peso_entrada_vehiculo=Decimal("1000.00"),
            )
        )
        await db.commit()
        assert await svc.evaluar_eventos(db) == 0


class TestEvaluarSeries:
    async def test_serie_por_agotar(self, db, empresa):
        db.add(
            SerieNumeracion(
                id_empresa=empresa.id_empresa,
                nombre="TA",
                prefijo="TA-",
                siguiente=99_999_990,
                digitos=8,
                activa=True,
            )
        )
        await db.commit()

        await svc.evaluar_eventos(db)
        await db.commit()
        tipos = [f.tipo for f in (await db.execute(select(Notificacion))).scalars().all()]
        assert "serie_por_agotar" in tipos

    async def test_serie_inactiva_no_avisa(self, db, empresa):
        db.add(
            SerieNumeracion(
                id_empresa=empresa.id_empresa,
                nombre="TB",
                prefijo="TB-",
                siguiente=99_999_990,
                digitos=8,
                activa=False,
            )
        )
        await db.commit()
        assert await svc.evaluar_eventos(db) == 0


# ---------------------------------------------------------------------------
# Servicio: recordatorios
# ---------------------------------------------------------------------------


class TestRecordatorios:
    async def test_unico_dispara_y_se_desactiva(self, db, empresa):
        rec = Recordatorio(
            id_empresa=empresa.id_empresa,
            titulo="Revisar báscula",
            programada_para=_ahora() - timedelta(minutes=1),
            recurrencia="none",
            activo=True,
        )
        db.add(rec)
        await db.commit()
        await db.refresh(rec)

        assert await svc.evaluar_eventos(db) == 1
        await db.commit()
        await db.refresh(rec)
        assert rec.activo is False
        assert rec.ultima_ejecucion is not None

        # No vuelve a dispararse.
        assert await svc.evaluar_eventos(db) == 0

    async def test_diario_reprograma_al_futuro(self, db, empresa):
        rec = Recordatorio(
            id_empresa=empresa.id_empresa,
            titulo="Cierre del día",
            programada_para=_ahora() - timedelta(minutes=1),
            recurrencia="daily",
            activo=True,
        )
        db.add(rec)
        await db.commit()
        await db.refresh(rec)

        await svc.evaluar_eventos(db)
        await db.commit()
        await db.refresh(rec)
        assert rec.activo is True
        assert rec.programada_para > _ahora()

    async def test_salta_ciclos_vencidos_de_una_parada_larga(self, db, empresa):
        rec = Recordatorio(
            id_empresa=empresa.id_empresa,
            titulo="Diario",
            programada_para=_ahora() - timedelta(days=10),
            recurrencia="daily",
            activo=True,
        )
        db.add(rec)
        await db.commit()
        await db.refresh(rec)

        await svc.evaluar_eventos(db)
        await db.commit()
        await db.refresh(rec)
        # Un solo aviso, y la próxima programación queda por delante de ahora.
        total = (await db.execute(select(Notificacion))).scalars().all()
        assert len(total) == 1
        assert rec.programada_para > _ahora()
        assert rec.programada_para <= _ahora() + timedelta(days=1)

    def test_mes_siguiente_ajusta_dia_inexistente(self):
        assert svc._mes_siguiente(datetime(2026, 1, 31)) == datetime(2026, 2, 28)

    def test_mes_siguiente_cruza_el_anio(self):
        assert svc._mes_siguiente(datetime(2026, 12, 15)) == datetime(2027, 1, 15)

    def test_siguiente_none_sin_recurrencia(self):
        assert svc._siguiente(datetime(2026, 1, 1), "none") is None


# ---------------------------------------------------------------------------
# Servicio: despacho al sistema operativo
# ---------------------------------------------------------------------------


class TestDespachoOS:
    async def test_sin_canal_no_marca_entregada(self, db, empresa, monkeypatch):
        monkeypatch.setattr(svc, "canal_disponible", lambda: None)
        await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="Hola"
        )
        await db.commit()

        assert await svc.despachar_os_pendientes(db) == 0
        await db.commit()
        fila = (await db.execute(select(Notificacion))).scalar_one()
        assert fila.entregada_os_en is None

    async def test_con_canal_marca_y_no_reenvia(self, db, empresa, monkeypatch):
        enviados: list[str] = []

        def _falso(titulo: str, mensaje: str, severidad: str = "info") -> bool:
            enviados.append(titulo)
            return True

        monkeypatch.setattr(svc, "canal_disponible", lambda: "linux")
        monkeypatch.setattr(svc, "notificar_os", _falso)
        await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="Hola"
        )
        await db.commit()

        assert await svc.despachar_os_pendientes(db) == 1
        await db.commit()
        fila = (await db.execute(select(Notificacion))).scalar_one()
        assert fila.entregada_os_en is not None
        assert enviados == ["Hola"]

        # Segundo despacho: ya no se reenvía.
        assert await svc.despachar_os_pendientes(db) == 0
        assert enviados == ["Hola"]

    async def test_canal_que_falla_no_marca(self, db, empresa, monkeypatch):
        monkeypatch.setattr(svc, "canal_disponible", lambda: "linux")
        monkeypatch.setattr(svc, "notificar_os", lambda *a, **k: False)
        await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="Hola"
        )
        await db.commit()

        assert await svc.despachar_os_pendientes(db) == 0
        await db.commit()
        fila = (await db.execute(select(Notificacion))).scalar_one()
        assert fila.entregada_os_en is None


# ---------------------------------------------------------------------------
# API: bandeja
# ---------------------------------------------------------------------------


class TestBandeja:
    async def test_bandeja_vacia(self, client):
        r = await client.get("/api/v1/notificaciones")
        assert r.status_code == 200
        assert r.json() == []

    async def test_listar_y_resumen(self, client, db, empresa):
        await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="Uno"
        )
        await svc.crear_notificacion(
            db,
            id_empresa=empresa.id_empresa,
            tipo="prueba",
            titulo="Dos",
            severidad="alta",
        )
        await db.commit()

        r = await client.get("/api/v1/notificaciones")
        assert r.status_code == 200
        assert len(r.json()) == 2

        resumen = await client.get("/api/v1/notificaciones/resumen")
        assert resumen.status_code == 200
        cuerpo = resumen.json()
        assert cuerpo["no_leidas"] == 2
        assert cuerpo["total"] == 2
        assert cuerpo["por_severidad"] == {"info": 1, "alta": 1}

    async def test_leer_y_archivar(self, client, db, empresa):
        creada = await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="Uno"
        )
        await db.commit()
        assert creada is not None

        r = await client.post(f"/api/v1/notificaciones/{creada.id}/leer")
        assert r.status_code == 200
        assert r.json()["leida"] is True
        assert r.json()["estado"] == "leida"

        r = await client.post(f"/api/v1/notificaciones/{creada.id}/archivar")
        assert r.status_code == 200
        assert r.json()["estado"] == "archivado"

    async def test_leer_todas(self, client, db, empresa):
        for i in range(3):
            await svc.crear_notificacion(
                db, id_empresa=empresa.id_empresa, tipo="prueba", titulo=f"N{i}"
            )
        await db.commit()

        r = await client.post("/api/v1/notificaciones/leer-todas")
        assert r.status_code == 200
        assert r.json()["actualizadas"] == 3

        resumen = await client.get("/api/v1/notificaciones/resumen")
        assert resumen.json()["no_leidas"] == 0

    async def test_filtro_solo_no_leidas(self, client, db, empresa):
        una = await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="Uno"
        )
        await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="Dos"
        )
        await db.commit()
        assert una is not None

        await client.post(f"/api/v1/notificaciones/{una.id}/leer")

        todas = await client.get("/api/v1/notificaciones")
        assert len(todas.json()) == 2

        solo = await client.get("/api/v1/notificaciones", params={"solo_no_leidas": True})
        assert [n["titulo"] for n in solo.json()] == ["Dos"]

        leidas = await client.get("/api/v1/notificaciones", params={"estado": "leida"})
        assert [n["titulo"] for n in leidas.json()] == ["Uno"]

    async def test_404_de_otra_empresa(self, client, db):
        """Aislamiento: una notificación de otra empresa no es accesible."""
        otra = await _empresa_extra(db)
        ajena = await svc.crear_notificacion(
            db, id_empresa=otra.id_empresa, tipo="prueba", titulo="Ajena"
        )
        await db.commit()
        assert ajena is not None

        r = await client.get("/api/v1/notificaciones")
        assert r.json() == []

        r = await client.post(f"/api/v1/notificaciones/{ajena.id}/leer")
        assert r.status_code == 404

    async def test_probar_notificacion(self, client):
        r = await client.post("/api/v1/notificaciones/probar")
        assert r.status_code == 200
        assert r.json()["tipo"] == "prueba"


# ---------------------------------------------------------------------------
# API: recordatorios
# ---------------------------------------------------------------------------


class TestRecordatoriosAPI:
    async def test_crud_completo(self, client):
        programada = (_ahora() + timedelta(hours=2)).isoformat()
        creado = await client.post(
            "/api/v1/recordatorios",
            json={
                "titulo": "Llamar al cliente",
                "mensaje": "Confirmar despacho",
                "programada_para": programada,
                "recurrencia": "daily",
            },
        )
        assert creado.status_code == 201, creado.text
        ri = creado.json()
        assert ri["recurrencia"] == "daily"
        assert ri["activo"] is True

        r = await client.get("/api/v1/recordatorios")
        assert r.status_code == 200
        assert len(r.json()) == 1

        r = await client.patch(
            f"/api/v1/recordatorios/{ri['id']}", json={"activo": False}
        )
        assert r.status_code == 200
        assert r.json()["activo"] is False

        r = await client.delete(f"/api/v1/recordatorios/{ri['id']}")
        assert r.status_code == 204
        assert (await client.get("/api/v1/recordatorios")).json() == []

    async def test_recurrencia_invalida_rechazada(self, client):
        r = await client.post(
            "/api/v1/recordatorios",
            json={
                "titulo": "X",
                "programada_para": _ahora().isoformat(),
                "recurrencia": "cada_luna_llena",
            },
        )
        assert r.status_code == 422

    async def test_probar_recordatorio_crea_aviso_sin_reprogramar(self, client, db, empresa):
        programada = _ahora() + timedelta(days=1)
        rec = Recordatorio(
            id_empresa=empresa.id_empresa,
            titulo="Inventario",
            programada_para=programada,
            recurrencia="none",
            activo=True,
        )
        db.add(rec)
        await db.commit()
        await db.refresh(rec)

        r = await client.post(f"/api/v1/recordatorios/{rec.id}/probar")
        assert r.status_code == 200
        assert r.json()["tipo"] == "recordatorio"

        await db.refresh(rec)
        assert rec.activo is True
        assert rec.programada_para == programada

    async def test_recordatorio_de_otra_empresa_no_visible(self, client, db):
        otra = await _empresa_extra(db)
        ajeno = Recordatorio(
            id_empresa=otra.id_empresa,
            titulo="Ajeno",
            programada_para=_ahora(),
            recurrencia="none",
            activo=True,
        )
        db.add(ajeno)
        await db.commit()
        await db.refresh(ajeno)

        assert (await client.get("/api/v1/recordatorios")).json() == []
        assert (
            await client.patch(
                f"/api/v1/recordatorios/{ajeno.id}", json={"activo": False}
            )
        ).status_code == 404


# ---------------------------------------------------------------------------
# Notificador nativo (comando, no envío real)
# ---------------------------------------------------------------------------


class TestNotifier:
    def test_linux_mete_doble_guion_antes_del_titulo(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(notifier.shutil, "which", lambda _: "/usr/bin/notify-send")
        cmd = notifier._comando_linux("-u fake", "mensaje", "alta")
        assert cmd is not None
        # ``--`` corta las opciones: un título que empieza por ``-`` no se
        # interpreta como flag de notify-send.
        i = cmd.index("--")
        assert cmd[i + 1] == "-u fake"
        assert cmd[i + 2] == "mensaje"

    def test_linux_sin_binario_no_hay_comando(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(notifier.shutil, "which", lambda _: None)
        assert notifier._comando_linux("t", "m", "info") is None

    def test_el_icono_de_la_app_esta_en_el_repo(self):
        """El aviso nativo necesita el PNG: si falta o no es PNG, se cae al genérico."""
        from app.services import notifier

        ruta = notifier.ruta_icono()
        assert ruta is not None, "no se encontró assets/balansoft-ws.png"
        datos = Path(ruta).read_bytes()
        assert datos[:8] == b"\x89PNG\r\n\x1a\n", "el icono no es un PNG"

    def test_linux_usa_el_icono_de_la_app(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(notifier.shutil, "which", lambda _: "/usr/bin/notify-send")
        cmd = notifier._comando_linux("Prueba", "mensaje", "alta")
        assert cmd is not None
        assert cmd[cmd.index("-a") + 1] == "BALANSOFT-WS"
        assert cmd[cmd.index("-u") + 1] == "normal"
        # El icono de la app, no el genérico del tema.
        assert cmd[cmd.index("-i") + 1] == notifier.ruta_icono()
        assert Path(cmd[cmd.index("-i") + 1]).is_absolute(), (
            "notify-send exige ruta absoluta"
        )

    def test_linux_sin_archivo_de_icono_cae_al_generico(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(notifier.shutil, "which", lambda _: "/usr/bin/notify-send")
        monkeypatch.setattr(notifier, "ruta_icono", lambda: None)
        cmd = notifier._comando_linux("t", "m", "info")
        assert cmd is not None
        assert cmd[cmd.index("-i") + 1] == notifier.ICONO_RESPALDO

    def test_windows_con_icono_usa_generic_y_applogo(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        script = notifier._comando_windows("Título", "Mensaje")
        assert script is not None
        guion = script[-1]
        assert "ToastGeneric" in guion
        assert "appLogoOverride" in guion
        assert "file:///" in guion
        # El texto va escapado por nodos DOM, no interpolado en el XML.
        assert notifier._ps_cadena("Título") in guion

    def test_windows_sin_icono_conserva_la_plantilla_de_texto(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        monkeypatch.setattr(notifier, "ruta_icono", lambda: None)
        script = notifier._comando_windows("T", "M")
        assert script is not None
        assert "ToastText02" in script[-1]
        assert "appLogoOverride" not in script[-1]

    def test_windows_sin_icono_escapa_comillas_simples(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        monkeypatch.setattr(notifier, "ruta_icono", lambda: None)
        script = notifier._comando_windows("va'l", "M")
        assert script is not None
        assert "'va''l'" in script[-1]

    def test_windows_registra_el_aumid_antes_de_mostrar(self, monkeypatch):
        """Sin el AUMID en el registro Windows **descarta** el toast en silencio.

        `CreateToastNotifier` con un emisor desconocido no lanza ninguna
        excepción: el aviso simplemente no aparece. El guion tiene que dejar el
        AUMID registrado (las dos claves que documenta Microsoft para apps de
        escritorio sin identidad de paquete) **antes** del `.Show(...)`.
        """
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        script = notifier._comando_windows("Título", "Mensaje")
        assert script is not None
        guion = script[-1]
        assert "New-Item -Path $ka -Force" in guion
        assert "DisplayName" in guion
        assert "PushNotifications" in guion
        assert "app:desktop" in guion
        assert "NonImmersivePackage" in guion
        # El AUMID, no el nombre visible: el registro y el emisor coinciden.
        assert f"CreateToastNotifier({notifier._ps_cadena(notifier.AUMID)})" in guion
        assert (
            guion.index(notifier.CLAVE_AUMID)
            < guion.index("CreateToastNotifier(")
        )

    def test_windows_no_pisa_el_aumid_de_la_app(self, monkeypatch):
        """La app Flutter escribe la misma clave con su `CustomActivator`.

        Si el WServer la reescribiera en cada aviso borraría el activador con el
        que el clic en el toast abre la app, así que el registro va guardado por
        `Test-Path`.
        """
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        partes = notifier._comando_windows("T", "M")
        assert partes is not None
        guion = partes[-1]
        assert guion.count("if (-not (Test-Path $ka)) {") == 1
        assert guion.count("if (-not (Test-Path $kb)) {") == 1
        # Nada de `-Force` sobre `CustomActivator`: la clave no se toca si ya
        # existe.
        assert "CustomActivator" not in guion

    def test_windows_icono_del_aumid_es_una_uri_de_archivo(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        guion = notifier._comando_windows("T", "M")
        assert guion is not None
        assert "IconUri" in guion[-1]
        assert "file:///" in guion[-1]

    def test_sin_icono_no_registra_iconuri(self, monkeypatch):
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        monkeypatch.setattr(notifier, "ruta_icono", lambda: None)
        guion = notifier._comando_windows("T", "M")
        assert guion is not None
        assert "IconUri" not in guion[-1]
        assert "DisplayName" in guion[-1]

    def test_windows_escapa_comillas_en_las_claves_del_registro(self, monkeypatch):
        """Las claves del registro van como literal de PowerShell, no crudas."""
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        guion = notifier._comando_windows("T", "M")
        assert guion is not None
        assert (
            f"$ka = {notifier._ps_cadena(notifier.CLAVE_AUMID)};" in guion[-1]
        )
        assert (
            f"$kb = {notifier._ps_cadena(notifier.CLAVE_AUMID_BACKUP)};" in guion[-1]
        )

    def test_comando_windows_completo_se_puede_ejecutar(self, monkeypatch):
        """El guion es texto de PowerShell sintácticamente equilibrado.

        No se ejecuta PowerShell de verdad (no hay en CI Linux): se comprueba
        que las llaves y los paréntesis cierran, que es el error que dejaría el
        guion colgado y el aviso sin mostrarse **sin** error visible.
        """
        from app.services import notifier

        monkeypatch.setattr(
            notifier.shutil, "which", lambda _: "C:/Windows/powershell.exe"
        )
        partes = notifier._comando_windows("Título", "Mensaje")
        assert partes is not None
        guion = partes[-1]
        assert guion.count("{") == guion.count("}")
        assert guion.count("(") == guion.count(")")
        # Un solo `.Show(`: un toast por aviso.
        assert guion.count(".Show(") == 1
        # El literal de las claves termina en `;` (PowerShell ejecuta sentencias).
        assert guion.endswith(";")


# ---------------------------------------------------------------------------
# Carrera real del dedup (dos sesiones)
# ---------------------------------------------------------------------------


class TestCarreraDedup:
    async def test_duplicado_en_carrera_no_aborta_la_transaccion(
        self, db, empresa, _engine
    ):
        from sqlalchemy.ext.asyncio import (
            AsyncSession,
            async_sessionmaker,
        )

        factory = async_sessionmaker(
            bind=_engine, class_=AsyncSession, expire_on_commit=False
        )
        async with factory() as lider:
            # El líder registra el dedup_key SIN confirmar: el SELECT del otro
            # proceso lo ve vacío e intenta el INSERT → violación del índice
            # único (la carrera de verdad).
            await svc.crear_notificacion(
                lider,
                id_empresa=empresa.id_empresa,
                tipo="prueba",
                titulo="A",
                dedup_key="DUP",
            )
            tarea = asyncio.create_task(
                svc.crear_notificacion(
                    db,
                    id_empresa=empresa.id_empresa,
                    tipo="prueba",
                    titulo="B",
                    dedup_key="DUP",
                )
            )
            await asyncio.sleep(0.2)
            await lider.commit()
            resultado = await tarea

        assert resultado is None  # "ya existe", no un error
        # La transacción del segundo proceso SIGUE viva (el savepoint contuvo
        # la violación): puede crear otra notificación y confirmarla.
        nueva = await svc.crear_notificacion(
            db,
            id_empresa=empresa.id_empresa,
            tipo="prueba",
            titulo="C",
            dedup_key="OTRO",
        )
        assert nueva is not None
        await db.commit()
        titulos = set((await db.execute(select(Notificacion.titulo))).scalars())
        assert titulos == {"A", "C"}  # B se descartó, no se duplicó A


# ---------------------------------------------------------------------------
# Despacho por empresa (no cruza tenants)
# ---------------------------------------------------------------------------


class TestDespachoMultitenant:
    async def test_despacha_las_dos_empresas_sin_cruzar(self, db, empresa, monkeypatch):
        otra = await _empresa_extra(db)
        enviados: list[str] = []

        def _falso(titulo, mensaje, severidad="info"):
            enviados.append(titulo)
            return True

        monkeypatch.setattr(svc, "canal_disponible", lambda: "linux")
        monkeypatch.setattr(svc, "notificar_os", _falso)
        await svc.crear_notificacion(
            db, id_empresa=empresa.id_empresa, tipo="prueba", titulo="A"
        )
        await svc.crear_notificacion(
            db, id_empresa=otra.id_empresa, tipo="prueba", titulo="B"
        )
        await db.commit()

        assert await svc.despachar_os_pendientes(db) == 2
        await db.commit()
        assert sorted(enviados) == ["A", "B"]


# ---------------------------------------------------------------------------
# Superficie: permisos y rutas del centro
# ---------------------------------------------------------------------------


class TestPermisosNotificaciones:
    async def test_operador_lee_pero_no_dispara_ni_administra(self, db, empresa):
        operador = Usuario(
            id_empresa=empresa.id_empresa,
            nombre="Operador Notif",
            email=f"oper-{uuid.uuid4().hex[:6]}@test.demo",
            password_hash="x",
            rol="OPERADOR",
            activo=True,
        )
        db.add(operador)
        await db.commit()
        await db.refresh(operador)

        application = FastAPI()
        for router in API_ROUTERS:
            application.include_router(router)

        async def _get_db():
            yield db

        application.dependency_overrides[get_db] = _get_db
        application.dependency_overrides[get_current_user] = lambda: operador
        application.dependency_overrides[get_current_empresa] = lambda: empresa

        transport = httpx.ASGITransport(app=application)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            # La bandeja es para todos…
            assert (await ac.get("/api/v1/notificaciones")).status_code == 200
            assert (await ac.get("/api/v1/notificaciones/resumen")).status_code == 200
            assert (await ac.get("/api/v1/notificaciones/resumen")).json() == {
                "no_leidas": 0,
                "total": 0,
                "por_severidad": {},
            }
            assert (await ac.get("/api/v1/recordatorios")).status_code == 200
            # Marcar leídas también es del operador (la bandeja es suya)…
            assert (
                await ac.post("/api/v1/notificaciones/leer-todas")
            ).status_code == 200
            # …pero disparar y administrar exige ADMIN.
            assert (await ac.post("/api/v1/notificaciones/probar")).status_code == 403
            ajeno = uuid.uuid4()
            assert (
                await ac.delete(f"/api/v1/recordatorios/{ajeno}")
            ).status_code == 403
            assert (
                await ac.patch(
                    f"/api/v1/recordatorios/{ajeno}", json={"activo": False}
                )
            ).status_code == 403
            assert (
                await ac.post(f"/api/v1/recordatorios/{ajeno}/probar")
            ).status_code == 403

    def test_rutas_del_centro_no_estan_en_el_rol_servidor(self):
        from app.api.v1.endpoints import SERVER_ROUTERS

        def _paths(routers: list) -> set[str]:
            return {r.path for router in routers for r in getattr(router, "routes", [])}

        locales = _paths(API_ROUTERS)
        central = _paths(SERVER_ROUTERS)
        assert any(p.startswith("/api/v1/notificaciones") for p in locales)
        assert any(p.startswith("/api/v1/recordatorios") for p in locales)
        # El rol ``server`` no monta el centro: la central no tiene sus tablas.
        assert not any("notificacion" in p or "recordatorio" in p for p in central)


# ---------------------------------------------------------------------------
# Programador: esquema sin migrar (migración 023 ausente)
# ---------------------------------------------------------------------------


class TestSchedulerEsquemaIncompleto:
    """Un fallo de esquema da un aviso accionable, no un traceback por ciclo.

    Incidencia real: un ``uvicorn`` de desarrollo no aplica las migraciones
    (solo lo hace el WServer al arrancar), así que la migración 023
    (``notificaciones``/``recordatorios``) puede faltar en una BD existente.
    Antes el bucle registraba el traceback completo de PostgreSQL cada 60 s;
    ahora reconoce la tabla ausente y dice qué ejecutar.
    """

    def test_falta_tabla_se_reconoce_por_clase_y_por_texto(self):
        class UndefinedTableError(Exception):
            pass

        class Envoltorio(Exception):
            """Imita el error de SQLAlchemy: expone ``orig``."""

            def __init__(self, orig: BaseException) -> None:
                super().__init__("envoltorio de SQLAlchemy")
                self.orig = orig

        exc = Envoltorio(UndefinedTableError('relation "notificaciones" does not exist'))
        assert sched.falta_tabla(exc) is True
        assert (
            sched.falta_tabla(Exception('relation "recordatorios" does not exist'))
            is True
        )
        assert (
            sched.falta_tabla(Exception("Invalid object name 'dbo.notificaciones'"))
            is True
        )

    def test_falta_tabla_no_confunde_otros_fallos(self):
        assert sched.falta_tabla(Exception("deadlock detected")) is False

    async def test_ciclo_avisa_la_migracion_sin_escribir_traceback(self, caplog):
        programador = sched.NotificationScheduler(interval_seconds=5)
        programador._parar = asyncio.Event()
        intentos: list[str] = []

        async def _tick_falla() -> None:
            intentos.append("ciclo")
            raise Exception('relation "recordatorios" does not exist')

        programador._tick = _tick_falla  # type: ignore[method-assign]

        async def _detener() -> None:
            await asyncio.sleep(0.02)
            assert programador._parar is not None
            programador._parar.set()

        with caplog.at_level(logging.ERROR, logger="app.core.notification_scheduler"):
            await asyncio.gather(programador._bucle(), _detener())

        assert intentos, "el ciclo se intentó al menos una vez"
        errores = [r for r in caplog.records if r.levelno == logging.ERROR]
        assert errores, "debe quedar registrado el fallo"
        assert all("023" in r.getMessage() for r in errores)
        assert all(r.exc_info is None for r in errores), "sin traceback por ciclo"

"""Pruebas del semáforo de pesaje: decisión del LED y vigilante automático.

La decisión (``decidir_semaforo``) es una función **pura**: se prueba la matriz
completa de fases sin tocar la BD ni el hardware (docs/SEMAFORO.md). El
``SemaforoController`` se prueba con un HAL falso y una sesión de báscula falsa,
comprobando que solo se envían los **cambios** de luz y que el seguimiento no se
actualiza si el equipo no acepta el comando (así se reintenta en el ciclo
siguiente).
"""

from __future__ import annotations

import asyncio
import uuid
from datetime import datetime
from decimal import Decimal

import pytest

from app.models import Balanza, BoletoPesaje
from app.services import semaforo_service as svc
from app.services.semaforo_service import (
    FASE_AUTORIZADO,
    FASE_ESPERANDO,
    FASE_INESTABLE,
    FASE_PESANDO,
    FASE_SALIDA,
    FASE_SIN_BALANZA,
    ContextoSemaforo,
    Luces,
    SemaforoController,
    _luces_desde_comando,
    decidir_semaforo,
)

# ---------------------------------------------------------------------------
# Decisión pura
# ---------------------------------------------------------------------------


class TestDecidirSemaforo:
    @pytest.mark.parametrize(
        ("conectado", "peso", "estable", "pendiente", "salida", "fase", "luces"),
        [
            # 1. Sin lectura viva → ROJO (nadie autorizado).
            (False, None, False, False, False, FASE_SIN_BALANZA, {"rojo": "on"}),
            # 2. Salida concedida manda aunque el peso siga sobre la plataforma.
            (True, 0.0, True, False, True, FASE_SALIDA, {"verde": "on"}),
            (True, 12000.0, True, False, True, FASE_SALIDA, {"verde": "on"}),
            # 3a. Plataforma libre y sin ciclo abierto → VERDE (autorizado a subir).
            (True, 0.0, True, False, False, FASE_AUTORIZADO, {"verde": "on"}),
            # 3b. Ciclo abierto sin peso → ROJO (no autorizar otra entrada).
            (True, 0.0, True, True, False, FASE_ESPERANDO, {"rojo": "on"}),
            # 4a. Vehículo encima y sin estabilizar → ROJO + AMARILLO intermitente.
            (True, 12000.0, False, True, False, FASE_INESTABLE,
             {"rojo": "on", "amarillo": "flash"}),
            # 4b. Vehículo encima y estable → ROJO (pesaje en curso / capturado).
            (True, 12000.0, True, True, False, FASE_PESANDO, {"rojo": "on"}),
        ],
    )
    def test_matriz_de_fases(
        self, conectado, peso, estable, pendiente, salida, fase, luces
    ):
        decision = decidir_semaforo(
            ContextoSemaforo(
                conectado=conectado,
                peso_kg=peso,
                estable=estable,
                hay_pendiente=pendiente,
                salida_concedida=salida,
            )
        )
        assert decision.fase == fase
        esperado = {"rojo": "off", "amarillo": "off", "verde": "off", "zumbador": False}
        esperado.update(luces)
        assert decision.luces.como_dict() == esperado

    def test_el_umbral_de_cero_es_configurable(self):
        """Justo por debajo del umbral la plataforma sigue contando como libre."""
        justo_debajo = ContextoSemaforo(True, 4.9, True, False, False, umbral_cero_kg=5.0)
        justo_arriba = ContextoSemaforo(True, 5.1, True, True, False, umbral_cero_kg=5.0)
        assert decidir_semaforo(justo_debajo).fase == FASE_AUTORIZADO
        assert decidir_semaforo(justo_arriba).fase == FASE_PESANDO

    def test_umbral_mas_alto_obliga_a_esperar_mas_peso(self):
        ctx = ContextoSemaforo(True, 8.0, True, False, False, umbral_cero_kg=10.0)
        assert decidir_semaforo(ctx).fase == FASE_AUTORIZADO


class TestLuces:
    def test_como_comandos_fija_las_cuatro_salidas(self):
        cmds = Luces(rojo="on", amarillo="flash", verde="off", zumbador=True).como_comandos()
        assert cmds == [
            {"color": "rojo", "action": "on"},
            {"color": "amarillo", "action": "flash"},
            {"color": "verde", "action": "off"},
            {"zumbador": "on"},
        ]

    def test_diferencias_solo_devuelve_lo_que_cambia(self):
        actual = Luces(rojo="on")
        nuevo = Luces(verde="on")
        assert nuevo.diferencias(actual) == [
            {"color": "rojo", "action": "off"},
            {"color": "verde", "action": "on"},
        ]

    def test_sin_cambios_no_genera_comandos(self):
        luces = Luces(rojo="on", amarillo="flash")
        assert luces.diferencias(luces) == []

    def test_el_zumbador_cambia_solo(self):
        assert Luces(zumbador=True).diferencias(Luces()) == [{"zumbador": "on"}]


class TestLucesDesdeComando:
    def test_color_con_action(self):
        assert _luces_desde_comando(Luces(), {"color": "rojo", "action": "on"}) == Luces(
            rojo="on"
        )

    def test_intermitente(self):
        luces = _luces_desde_comando(Luces(), {"color": "amarillo", "action": "flash"})
        assert luces.amarillo == "flash"

    def test_all_off_apaga_todo(self):
        luces = _luces_desde_comando(
            Luces(rojo="on", amarillo="flash", zumbador=True), {"all": "off"}
        )
        assert luces == Luces()

    def test_reset_apaga_todo(self):
        luces = _luces_desde_comando(Luces(verde="on"), {"reset": True})
        assert luces == Luces()

    def test_zumbador(self):
        assert _luces_desde_comando(Luces(), {"zumbador": "on"}).zumbador is True


# ---------------------------------------------------------------------------
# Vigilante (con dobles de prueba)
# ---------------------------------------------------------------------------


class _SesionCtx:
    """Contexto async que devuelve una sesión ya construida (sin cerrarla)."""

    def __init__(self, session):
        self._s = session

    async def __aenter__(self):
        return self._s

    async def __aexit__(self, *exc):
        return False


class _HALFalso:
    """HAL que registra los comandos enviados y puede simular fallo."""

    def __init__(self, acepta: bool = True):
        self.acepta = acepta
        self.recibidos: list[dict] = []

    async def enviar_comando(self, payload):
        self.recibidos.append(dict(payload))
        return self.acepta

    async def leer_estado(self):  # pragma: no cover - no lo usa el vigilante
        return None


class _SesionBalanzaFalsa:
    def __init__(self, peso, estable):
        self.peso_kg = peso
        self.estable = estable


class _ManagerBalanzaFalso:
    def __init__(self, sesion):
        self._sesion = sesion

    async def obtener(self, balanza):  # noqa: ANN001
        if self._sesion is None:
            raise ValueError("sin sesión")
        return self._sesion


async def _crear_semaforo(db, empresa):
    balanza = Balanza(
        id_empresa=empresa.id_empresa,
        descripcion="Báscula Test",
        protocolo="tcp",
        activo=True,
    )
    db.add(balanza)
    await db.flush()
    from app.models import Semaforo

    semaforo = Semaforo(
        id_empresa=empresa.id_empresa,
        descripcion="Semáforo Test",
        protocolo="http",
        ip_address="127.0.0.1",
        puerto_tcp=8080,
        id_balanza=balanza.id_balanza,
        control_automatico=True,
        umbral_cero_kg=Decimal("5.0"),
    )
    db.add(semaforo)
    await db.commit()
    await db.refresh(semaforo)
    await db.refresh(balanza)
    return balanza, semaforo


async def _montar(monkeypatch, db, hal, sesion_balanza):
    monkeypatch.setattr(svc, "AsyncSessionLocal", lambda: _SesionCtx(db))
    monkeypatch.setattr(svc, "get_semaforo_hal", lambda semaforo: hal)
    monkeypatch.setattr(
        svc,
        "get_scale_session_manager",
        lambda: _ManagerBalanzaFalso(sesion_balanza),
    )


class TestVigilante:
    async def test_plataforma_libre_sin_ciclo_enciende_verde(self, db, empresa, monkeypatch):
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso()
        await _montar(
            monkeypatch, db, hal, _SesionBalanzaFalsa(peso=0.0, estable=True)
        )
        controller = SemaforoController(intervalo=0.05)
        key = str(semaforo.id_semaforo)

        assert await controller._tick(key) is True
        assert hal.recibidos == [{"color": "verde", "action": "on"}]
        assert controller.fase_actual(key) == FASE_AUTORIZADO
        assert controller.luces_actuales(key) == Luces(verde="on")

    async def test_segundo_ciclo_sin_cambios_no_reenvia(self, db, empresa, monkeypatch):
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso()
        await _montar(
            monkeypatch, db, hal, _SesionBalanzaFalsa(peso=0.0, estable=True)
        )
        controller = SemaforoController(intervalo=0.05)
        key = str(semaforo.id_semaforo)

        await controller._tick(key)
        await controller._tick(key)
        assert hal.recibidos == [{"color": "verde", "action": "on"}]

    async def test_peso_inestable_enciende_rojo_y_amarillo_intermitente(
        self, db, empresa, monkeypatch
    ):
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso()
        await _montar(
            monkeypatch, db, hal, _SesionBalanzaFalsa(peso=12000.0, estable=False)
        )
        controller = SemaforoController(intervalo=0.05)
        key = str(semaforo.id_semaforo)

        await controller._tick(key)
        assert {"color": "rojo", "action": "on"} in hal.recibidos
        assert {"color": "amarillo", "action": "flash"} in hal.recibidos
        assert controller.fase_actual(key) == FASE_INESTABLE

    async def test_comando_rechazado_no_actualiza_el_seguimiento(
        self, db, empresa, monkeypatch
    ):
        """Si el equipo no acepta, se reintenta el mismo cambio en el siguiente ciclo."""
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso(acepta=False)
        await _montar(
            monkeypatch, db, hal, _SesionBalanzaFalsa(peso=0.0, estable=True)
        )
        controller = SemaforoController(intervalo=0.05)
        key = str(semaforo.id_semaforo)

        await controller._tick(key)
        assert controller.luces_actuales(key) is None
        hal.acepta = True
        await controller._tick(key)
        assert controller.luces_actuales(key) == Luces(verde="on")

    async def test_sin_sesion_de_balanza_queda_rojo(self, db, empresa, monkeypatch):
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso()
        await _montar(monkeypatch, db, hal, _SesionBalanzaFalsa(peso=None, estable=False))
        controller = SemaforoController(intervalo=0.05)
        key = str(semaforo.id_semaforo)

        await controller._tick(key)
        assert hal.recibidos == [{"color": "rojo", "action": "on"}]
        assert controller.fase_actual(key) == FASE_SIN_BALANZA

    async def test_el_vigilante_termina_si_se_desactiva_el_automatico(
        self, db, empresa, monkeypatch
    ):
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso()
        await _montar(
            monkeypatch, db, hal, _SesionBalanzaFalsa(peso=0.0, estable=True)
        )
        controller = SemaforoController(intervalo=0.05)
        key = str(semaforo.id_semaforo)

        semaforo.control_automatico = False
        db.add(semaforo)
        await db.commit()
        assert await controller._tick(key) is False

    async def test_sin_boleto_pendiente_y_ultimo_cerrado_concede_salida(
        self, db, empresa, monkeypatch
    ):
        """El último ciclo cerrado (con fecha de salida) concede la vía libre."""
        balanza, semaforo = await _crear_semaforo(db, empresa)
        boleto = BoletoPesaje(
            id_empresa=empresa.id_empresa,
            id_balanza=balanza.id_balanza,
            numero_boleto="TA-00000001",
            fecha_hora_entrada=datetime(2026, 10, 1, 8, 0, 0),
            fecha_hora_salida=None,
            peso_entrada_vehiculo=Decimal("12000.00"),
            estado_boleto=BoletoPesaje.ESTADO_PENDIENTE,
        )
        db.add(boleto)
        await db.commit()
        await db.refresh(boleto)

        hal = _HALFalso()
        await _montar(
            monkeypatch, db, hal, _SesionBalanzaFalsa(peso=0.0, estable=True)
        )
        controller = SemaforoController(intervalo=0.05)
        key = str(semaforo.id_semaforo)

        # Con boleto pendiente y sin peso: no autoriza (ROJO/ESPERANDO).
        await controller._tick(key)
        assert controller.fase_actual(key) == FASE_ESPERANDO

        # Cierra el boleto (con fecha de salida) → vía libre para salir (VERDE).
        boleto.estado_boleto = BoletoPesaje.ESTADO_CERRADO
        boleto.fecha_hora_salida = datetime(2026, 10, 1, 9, 0, 0)
        db.add(boleto)
        await db.commit()

        await controller._tick(key)
        assert controller.fase_actual(key) == FASE_SALIDA


class TestCicloDeVidaDelVigilante:
    async def test_asegurar_es_idempotente_y_detener_cancela(
        self, db, empresa, monkeypatch
    ):
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso()
        await _montar(
            monkeypatch, db, hal, _SesionBalanzaFalsa(peso=0.0, estable=True)
        )
        controller = SemaforoController(intervalo=0.02)
        key = str(semaforo.id_semaforo)

        await controller.asegurar(key)
        tarea = controller._tareas[key]
        await controller.asegurar(key)
        assert controller._tareas[key] is tarea  # no se recrea
        assert controller.activo(key) is True

        await controller.detener(key)
        assert controller.activo(key) is False
        assert controller.fase_actual(key) is None

    async def test_asegurar_activos_solo_levanta_los_automaticos(
        self, db, empresa, monkeypatch
    ):
        _, semaforo = await _crear_semaforo(db, empresa)
        hal = _HALFalso()
        monkeypatch.setattr(svc, "AsyncSessionLocal", lambda: _SesionCtx(db))
        monkeypatch.setattr(svc, "get_semaforo_hal", lambda semaforo: hal)

        controller = SemaforoController(intervalo=0.02)
        await controller.asegurar_activos()
        assert controller.activo(str(semaforo.id_semaforo)) is True
        await controller.detener_todas()
        assert controller.activo(str(semaforo.id_semaforo)) is False

    async def test_detener_una_tarea_inexistente_no_falla(self):
        controller = SemaforoController()
        await controller.detener(uuid.uuid4())
        assert True


async def test_cancelar_tolerar_tarea_ya_terminada():
    async def _fallar():
        raise RuntimeError("boom")

    tarea = asyncio.ensure_future(_fallar())
    await asyncio.sleep(0)
    await svc._cancelar(tarea)  # no debe propagar la excepción

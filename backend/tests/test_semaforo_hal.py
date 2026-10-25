"""Pruebas del HAL del semáforo: normalización de comandos y transportes.

El semáforo **obedece** comandos; el contrato es el JSON del SPEC del simulador
BSDD (§4), idéntico en todos los canales. Aquí se cubre:

- ``normalizar_comando``: validación y limpieza del comando.
- ``HttpSemaforoHAL``: POST/GET contra ``/api/semaforo`` (con un transporte HTTP
  falso, sin abrir puertos reales).
- ``SerialSemaforoHAL``: líneas JSON por un pty real (mismo camino que un USB
  CDC-ACM).
- ``get_semaforo_hal``: elección del transporte por configuración.
"""

from __future__ import annotations

import json
import os
import pty
import time
from types import SimpleNamespace

import httpx
import pytest

from app.core.semaforo_hal import (
    HttpSemaforoHAL,
    SerialSemaforoHAL,
    get_semaforo_hal,
    normalizar_comando,
)

try:
    import serial  # noqa: F401

    _HAY_PYSERIAL = True
except ImportError:  # pragma: no cover - entorno sin pyserial
    _HAY_PYSERIAL = False

requiere_pyserial = pytest.mark.skipif(
    not _HAY_PYSERIAL, reason="pyserial no instalado (extra opcional)"
)


class TestNormalizarComando:
    def test_color_con_action(self):
        assert normalizar_comando({"color": "rojo", "action": "on"}) == {
            "color": "rojo",
            "action": "on",
        }

    def test_color_sin_action_implica_encender(self):
        assert normalizar_comando({"color": "verde"}) == {"color": "verde", "action": "on"}

    def test_intermitente(self):
        assert normalizar_comando({"color": "amarillo", "action": "flash"}) == {
            "color": "amarillo",
            "action": "flash",
        }

    def test_zumbador_booleano_se_normaliza(self):
        assert normalizar_comando({"zumbador": True}) == {"zumbador": "on"}
        assert normalizar_comando({"zumbador": False}) == {"zumbador": "off"}

    def test_all_off(self):
        assert normalizar_comando({"all": "off"}) == {"all": "off"}

    def test_reset(self):
        assert normalizar_comando({"reset": True}) == {"reset": True}

    def test_automatico(self):
        assert normalizar_comando({"automatico": False}) == {"automatico": False}

    def test_atajos_planos_por_color(self):
        # SPEC §5.6: el booleano enciende/apaga el color; la acción lo fija.
        assert normalizar_comando({"rojo": True}) == {"color": "rojo", "action": "on"}
        assert normalizar_comando({"rojo": False}) == {"color": "rojo", "action": "off"}
        assert normalizar_comando({"verde": "flash"}) == {
            "color": "verde",
            "action": "flash",
        }
        assert normalizar_comando({"amarillo": "on"}) == {
            "color": "amarillo",
            "action": "on",
        }

    def test_alias_luz(self):
        assert normalizar_comando({"luz": "verde"}) == {"color": "verde", "action": "on"}

    def test_color_gana_a_los_atajos_planos(self):
        # La forma canónica tiene prioridad, como en el parser de BSDD.
        assert normalizar_comando({"color": "verde", "rojo": True}) == {
            "color": "verde",
            "action": "on",
        }

    def test_atajo_plano_combinado_con_zumbador(self):
        assert normalizar_comando({"rojo": True, "zumbador": True}) == {
            "color": "rojo",
            "action": "on",
            "zumbador": "on",
        }

    def test_descarta_claves_desconocidas(self):
        assert normalizar_comando({"color": "rojo", "foo": 1}) == {
            "color": "rojo",
            "action": "on",
        }

    @pytest.mark.parametrize(
        "payload",
        [
            {"color": "azul"},
            {"color": "rojo", "action": "blink"},
            {"luz": "azul"},
            {"rojo": "quizá"},
            {"verde": 3},
            {"all": "on"},
            {"zumbador": "quizá"},
            {},
            {"foo": 1},
        ],
    )
    def test_comandos_invalidos(self, payload):
        with pytest.raises(ValueError):
            normalizar_comando(payload)

    def test_payload_no_es_objeto(self):
        with pytest.raises(ValueError):
            normalizar_comando(["color", "rojo"])  # type: ignore[arg-type]


class TestHttpSemaforoHAL:
    def _hal(self, handler):
        return HttpSemaforoHAL(
            "127.0.0.1", 8080, transport=httpx.MockTransport(handler)
        )

    async def test_enviar_comando_ok(self):
        capturado = {}

        def handler(request: httpx.Request) -> httpx.Response:
            capturado["url"] = str(request.url)
            capturado["body"] = json.loads(request.content.decode())
            return httpx.Response(200, json={"ok": True})

        hal = self._hal(handler)
        assert await hal.enviar_comando({"color": "verde", "action": "on"}) is True
        assert capturado["url"] == "http://127.0.0.1:8080/api/semaforo"
        assert capturado["body"] == {"color": "verde", "action": "on"}

    async def test_enviar_comando_error_http_devuelve_false(self):
        hal = self._hal(lambda request: httpx.Response(500))
        assert await hal.enviar_comando({"color": "rojo", "action": "on"}) is False

    async def test_enviar_comando_comando_invalido_no_toca_la_red(self):
        llamado = {"si": False}

        def handler(request: httpx.Request) -> httpx.Response:
            llamado["si"] = True
            return httpx.Response(200)

        hal = self._hal(handler)
        assert await hal.enviar_comando({"color": "azul"}) is False
        assert llamado["si"] is False

    async def test_enviar_comando_error_de_red_devuelve_false(self):
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("sin ruta")

        hal = self._hal(handler)
        assert await hal.enviar_comando({"color": "rojo", "action": "on"}) is False

    async def test_leer_estado_ok(self):
        estado = {
            "rojo": {"encendido": True, "modo": "fijo"},
            "amarillo": {"encendido": False, "modo": "apagado"},
            "verde": {"encendido": False, "modo": "apagado"},
            "zumbador": False,
            "fase": "EXTERNO",
            "automatico": False,
            "timestamp": "2026-10-19T12:00:00Z",
        }
        hal = self._hal(lambda request: httpx.Response(200, json=estado))
        assert await hal.leer_estado() == estado

    async def test_leer_estado_no_200_devuelve_none(self):
        hal = self._hal(lambda request: httpx.Response(404))
        assert await hal.leer_estado() is None

    async def test_leer_estado_inexistente_devuelve_none(self):
        def handler(request: httpx.Request) -> httpx.Response:
            raise httpx.ConnectError("equipo apagado")

        hal = self._hal(handler)
        assert await hal.leer_estado() is None

    async def test_leer_estado_si_no_es_objeto_devuelve_none(self):
        hal = self._hal(lambda request: httpx.Response(200, json=[1, 2, 3]))
        assert await hal.leer_estado() is None


# ---------------------------------------------------------------------------
# Serial real vía pty
# ---------------------------------------------------------------------------
@requiere_pyserial
class TestSerialSemaforoHAL:
    async def test_leer_estado_del_pty(self):
        master, slave = pty.openpty()
        try:
            nombre = os.ttyname(slave)
            hal = SerialSemaforoHAL(nombre, timeout=1.0)
            estado = {"verde": {"encendido": True}, "fase": "EXTERNO"}
            # Retraso para evitar que se lea antes de escribir
            import threading

            def _emit():
                time.sleep(0.3)
                try:
                    os.write(master, (json.dumps(estado) + "\n").encode())
                except OSError:
                    pass

            threading.Thread(target=_emit, daemon=True).start()
            assert await hal.leer_estado() == estado
        finally:
            os.close(master)
            os.close(slave)

    async def test_leer_estado_texto_plano_devuelve_none(self):
        master, slave = pty.openpty()
        try:
            nombre = os.ttyname(slave)
            hal = SerialSemaforoHAL(nombre, timeout=0.4)
            os.write(master, b"no soy json\n")
            assert await hal.leer_estado() is None
        finally:
            os.close(master)
            os.close(slave)

    async def test_enviar_comando_escribe_la_linea_json(self):
        master, slave = pty.openpty()
        try:
            nombre = os.ttyname(slave)
            hal = SerialSemaforoHAL(nombre, timeout=1.0)
            assert await hal.enviar_comando({"color": "rojo", "action": "on"}) is True
            # Leer lo escrito en el otro extremo del pty.
            os.set_blocking(master, False)
            recibido = b""
            limite = time.time() + 2.0
            while time.time() < limite and b"\n" not in recibido:
                try:
                    recibido += os.read(master, 4096)
                except BlockingIOError:
                    time.sleep(0.02)
            datos = json.loads(recibido.decode().strip())
            assert datos == {"color": "rojo", "action": "on"}
        finally:
            os.close(master)
            os.close(slave)

    async def test_puerto_inexistente_devuelve_false(self):
        hal = SerialSemaforoHAL("/dev/no_existe_semaforo_xyz", timeout=0.2)
        assert await hal.enviar_comando({"color": "rojo", "action": "on"}) is False
        assert await hal.leer_estado() is None


class TestGetSemaforoHAL:
    def test_protocolo_serial(self):
        hal = get_semaforo_hal(
            SimpleNamespace(
                protocolo="serial",
                puerto_com="/dev/bsdd_semaforo_acm",
                ip_address=None,
                puerto_tcp=None,
                baudrate=115200,
            )
        )
        assert isinstance(hal, SerialSemaforoHAL)
        assert hal.port == "/dev/bsdd_semaforo_acm"
        assert hal.baudrate == 115200

    def test_protocolo_http(self):
        hal = get_semaforo_hal(
            SimpleNamespace(
                protocolo="http",
                puerto_com=None,
                ip_address="192.168.1.50",
                puerto_tcp=8080,
                baudrate=None,
            )
        )
        assert isinstance(hal, HttpSemaforoHAL)
        assert hal.host == "192.168.1.50"
        assert hal.puerto == 8080

    def test_http_sin_direccion_cae_al_simulador_local(self):
        hal = get_semaforo_hal(
            SimpleNamespace(
                protocolo="http",
                puerto_com=None,
                ip_address=None,
                puerto_tcp=None,
                baudrate=None,
            )
        )
        assert isinstance(hal, HttpSemaforoHAL)
        assert hal.host == "127.0.0.1"
        assert hal.puerto == 8080

    def test_serial_sin_puerto_levanta_error(self):
        with pytest.raises(ValueError):
            get_semaforo_hal(
                SimpleNamespace(
                    protocolo="serial",
                    puerto_com=None,
                    ip_address=None,
                    puerto_tcp=None,
                    baudrate=9600,
                )
            )

    def test_protocolo_desconocido_sin_direccion_levanta_error(self):
        with pytest.raises(ValueError):
            get_semaforo_hal(
                SimpleNamespace(
                    protocolo="modbus",
                    puerto_com=None,
                    ip_address=None,
                    puerto_tcp=None,
                    baudrate=9600,
                )
            )

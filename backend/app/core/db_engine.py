"""Detección de motor de BD y guardias de esquema (soporte SQL Server Fase 1).

Contrato (docs/MANEJO_DB.md §11.5):

* El motor se decide **solo** por el prefijo de ``DATABASE_URL`` (no existen
  variables de entorno nuevas): ``postgresql+asyncpg://`` → PostgreSQL,
  ``mssql+aioodbc://`` → SQL Server. Ver ``PREFIJO_SYNC``.
* Este módulo NO importa ``app.core.config`` a nivel de módulo: los imports
  de config son perezosos (dentro de las funciones) para poder ser usado por
  el propio ``config.py`` sin ciclos.
* Fase 1 = **modo degradado**: el WServer arranca contra SQL Server aunque el
  esquema no exista todavía. Las operaciones que necesitan tablas responden
  503 con ``codigo=esquema_mssql_pendiente``; el esquema real (DDL) llega en
  Fase 2. El camino PostgreSQL no se toca: cualquier error de BD se re-lanza
  y produce el 500 de siempre.

Módulo deliberadamente ligero (solo stdlib a nivel de módulo) para que
``wserver.py`` pueda usarlo en el bootstrap sin importar la app completa.
"""

from __future__ import annotations

import re
import threading
import time
from typing import Literal
from urllib.parse import quote, unquote, unquote_plus, urlparse

from fastapi.responses import JSONResponse, Response

Motores = Literal["postgresql", "sqlserver"]

# Prefijo de DATABASE_URL (async) → prefijo de la URL sync equivalente.
# Es también la tabla de prefijos aceptados por detectar_motor().
PREFIJO_SYNC: dict[str, str] = {
    "postgresql+asyncpg://": "postgresql+psycopg2://",
    "postgresql://": "postgresql+psycopg2://",
    "postgresql+psycopg2://": "postgresql+psycopg2://",
    "mssql+aioodbc://": "mssql+pyodbc://",
    "mssql+pyodbc://": "mssql+pyodbc://",
    "mssql://": "mssql+pyodbc://",
}

MENSAJE_FASE_2 = (
    "El esquema de SQL Server se aplicará en Fase 2; el WServer funciona "
    "en modo degradado sin datos."
)

MENSAJE_SIN_CONEXION = (
    "No se pudo conectar a SQL Server. Verifica la base de datos y la URL DATABASE_URL."
)

CODIGO_ESQUEMA_PENDIENTE = "esquema_mssql_pendiente"
CODIGO_SIN_CONEXION = "sqlserver_sin_conexion"
CODIGO_SIN_DRIVERS = "sqlserver_sin_drivers"

# Mensaje accionable del 503 «sin drivers» (contrato con la app Flutter):
# incluye las dos cosas que el operador debe instalar: el extra de uv y el
# driver ODBC del sistema. El texto reutiliza el de error_drivers_faltantes(),
# pero como detalle del 503, no como abort del arranque (Opción B).
MENSAJE_SIN_DRIVERS = (
    "Faltan los drivers ODBC de SQL Server (DATABASE_URL=mssql+…). "
    "Instala el extra: uv sync --extra sqlserver (aioodbc, pyodbc) y el "
    "«Microsoft ODBC Driver 18 for SQL Server» del sistema."
)

# SQLSTATE que significan «el objeto no existe todavía» (42S02/42703/42P01/42704
# son los códigos T-SQL; 42P01/42703/42704 por compatibilidad con el texto PG).
_SQLSTATE_ESQUEMA = frozenset({"42S02", "42703", "42P01", "42704"})
_FRASES_ESQUEMA = (
    "invalid object name",
    "invalid column name",
    "does not exist",
    "could not find table",
    "no es válido el nombre del objeto",
    "no es válida la columna",
)
# SQLSTATE clase 08* = excepción de conexión; más frases de fallo de red/login.
_FRASES_CONEXION = (
    "login failed",
    "error de inicio de sesión",
    "cannot open database",
    "no se puede abrir",
    "connection refused",
    "could not connect",
    "tcp provider",
)


class EsquemaPendienteError(Exception):
    """El esquema de SQL Server aún no está aplicado (modo degradado Fase 1)."""


class DriversFaltantesError(Exception):
    """Sin drivers ODBC de SQL Server: modo degradado sin conexión posible.

    En vez de abortar el arranque (fail-fast), el WServer sigue vivo con
    health 200 y cualquier endpoint de BD responde 503 con
    ``codigo=sqlserver_sin_drivers`` (Opción B).
    """


# ---------------------------------------------------------------------------
# Caché de estado del esquema (por proceso)
# ---------------------------------------------------------------------------
_TTL_PENDIENTE_SEG = 60.0
_candado = threading.Lock()
_estado: str | None = None  # None | "pendiente" | "aplicado"
_estado_marcado_en: float = 0.0
_drivers_faltantes_sqlserver: bool = False


def estado_esquema() -> str | None:
    """Estado sembrado de la caché: ``None``, ``"pendiente"`` o ``"aplicado"``."""
    with _candado:
        return _estado


def marcar_estado_esquema(estado: str | None) -> None:
    """Siembra la caché (se revalida solo cuando queda ``"pendiente"`` vencido)."""
    global _estado, _estado_marcado_en
    if estado is not None and estado not in ("pendiente", "aplicado"):
        raise ValueError(f"Estado de esquema desconocido: {estado!r}")
    with _candado:
        _estado = estado
        _estado_marcado_en = time.monotonic()


def reiniciar_estado_esquema() -> None:
    """Vuelve la caché al valor inicial ``{"valor": None, "ts": 0.0}``.

    También restablece el flag de drivers faltantes: es el «reinicio total de
    la guardia» (arranque, tests y LOW-001). Uso: arranque, tests y LOW-001
    (un fallo de conexión al consultar el esquema no debe dejar un
    ``"pendiente"`` caduco que enmascare reintentos).
    """
    global _estado, _estado_marcado_en, _drivers_faltantes_sqlserver
    with _candado:
        _estado = None
        _estado_marcado_en = 0.0
        _drivers_faltantes_sqlserver = False


def marcar_drivers_faltantes() -> None:
    """Siembra que los drivers ODBC de SQL Server no están instalados.

    Lo llama ``database.py`` al capturar un ``ModuleNotFoundError`` al crear
    los engines con URL ``mssql+…`` (sin abortar el arranque). Persiste hasta
    ``reiniciar_estado_esquema()`` (p. ej. reinicio del WServer tras instalar
    el extra ``sqlserver``).
    """
    global _drivers_faltantes_sqlserver
    with _candado:
        _drivers_faltantes_sqlserver = True


def drivers_faltantes() -> bool:
    """True si los drivers ODBC de SQL Server no están disponibles."""
    with _candado:
        return _drivers_faltantes_sqlserver


def desactivar_pooling_pyodbc() -> None:
    """Desactiva el pooling interno de pyodbc (necesario con SQL Server).

    pyodbc 5+ activa por defecto un pool interno a nivel de proceso; al devolver
    una conexión con resultados pendientes (p. ej. tras ``executescript`` de
    un lote DDL) la siguiente consulta falla con ``HY000 Connection is busy
    with results for another command`` (flaky intermitente, ~27 % en la suite
    T8). SQLAlchemy gestiona su propio pool; desactivar el de pyodbc es la
    práctica recomendada con aioodbc/pyodbc y evita el error tanto en el
    bootstrap del WServer como en los tests contra el contenedor de prueba.
    """
    try:
        import pyodbc

        pyodbc.pooling = False
    except Exception:  # noqa: BLE001 (sin pyodbc no hay nada que desactivar)
        pass


def _estado_fresco() -> bool:
    """True mientras el ``"pendiente"`` marcado tenga menos de ``TTL``."""
    with _candado:
        return (time.monotonic() - _estado_marcado_en) <= _TTL_PENDIENTE_SEG


# ---------------------------------------------------------------------------
# Funciones puras (sin estado, sin imports de la app)
# ---------------------------------------------------------------------------
def _prefijo_de(url: str) -> str:
    """Prefijo exacto de la URL que está en la tabla (case-insensitive)."""
    if not isinstance(url, str) or not url.strip():
        raise ValueError(
            "DATABASE_URL vacía: no se puede determinar el motor. "
            f"Prefijos aceptados: {', '.join(PREFIJO_SYNC)}."
        )
    bajo = url.lower()
    for prefijo in PREFIJO_SYNC:
        if bajo.startswith(prefijo):
            return url[: len(prefijo)]
    esquema = url.split("://", 1)[0]
    raise ValueError(
        f"Prefijo de DATABASE_URL no soportado: {esquema!r}. "
        f"Prefijos aceptados: {', '.join(PREFIJO_SYNC)}."
    )


def detectar_motor(url: str) -> Motores:
    """Devuelve el motor a partir del prefijo de la URL (ValueError si no es válido)."""
    prefijo = _prefijo_de(url)
    return "sqlserver" if prefijo.lower().startswith("mssql") else "postgresql"


def puerto_default(motor: str) -> int:
    """Puerto por defecto del motor (PostgreSQL 5432 / SQL Server 1433)."""
    return 1433 if motor == "sqlserver" else 5432


def derivar_url_sync(url_async: str) -> str:
    """Cambia SOLO el prefijo de la URL async → sync.

    Los query params se conservan byte a byte (no hay parsing/re-serializado).
    """
    prefijo = _prefijo_de(url_async)
    return PREFIJO_SYNC[prefijo.lower()] + url_async[len(prefijo) :]


def sql_conteo_tablas(motor: str) -> str:
    """SQL de conteo de tablas del esquema por defecto del motor.

    SQL Server usa el esquema ``dbo`` (coherente con PG ``schemaname='public'``)
    y el mismo criterio aplica ``wserver._existe_esquema`` (LOW-002).
    """
    if motor == "sqlserver":
        return (
            "SELECT COUNT(*) FROM sys.tables "
            "WHERE SCHEMA_NAME(schema_id) = N'dbo'"
        )
    return "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'"


def _params_de(c: dict) -> dict[str, str]:
    """Query params del dict de ``_descomponer_url`` (acepta dict o string)."""
    params = c.get("params")
    if isinstance(params, dict):
        return dict(params)
    query = c.get("query") or ""
    salida: dict[str, str] = {}
    for par in str(query).split("&"):
        if "=" in par:
            clave, valor = par.split("=", 1)
            salida[clave] = valor
    return salida


def dsn_pyodbc(c: dict) -> str:
    """DSN de pyodbc a partir del dict de ``_descomponer_url``.

    El driver llega con ``+`` por los espacios en la URL
    (``ODBC+Driver+18+for+SQL+Server``) y aquí se desescapa a espacios reales.
    El resto de query params se copian tal cual (sin ``driver``).
    """
    driver = unquote_plus(str(c.get("driver") or "ODBC Driver 18 for SQL Server"))
    host = c.get("host") or "localhost"
    port = c.get("port") or puerto_default("sqlserver")
    partes = [
        f"DRIVER={{{driver}}};",
        f"SERVER={host},{port};",
        f"DATABASE={c.get('db') or ''};",
        f"UID={c.get('user') or ''};",
        f"PWD={c.get('password') or ''};",
    ]
    for clave, valor in _params_de(c).items():
        if clave.lower() == "driver":
            continue
        partes.append(f"{clave}={valor};")
    return "".join(partes)


# ---------------------------------------------------------------------------
# Guardia de esquema (gate de get_db)
# ---------------------------------------------------------------------------
async def _consultar_esquema_sqlserver() -> str | None:
    """Consulta barata ``sys.tables`` y siembra la caché con el resultado.

    Un error de BD se propaga a propósito: lo clasifica
    ``manejador_error_bd`` (503 de conexión vs 503 de esquema) en vez de
    traducirlo silenciosamente a «esquema pendiente».
    """
    from sqlalchemy import text  # import perezoso: mantiene el módulo ligero

    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as session:
        n = (await session.execute(text(sql_conteo_tablas("sqlserver")))).scalar_one()
    nuevo = "aplicado" if n and int(n) > 0 else "pendiente"
    marcar_estado_esquema(nuevo)
    return nuevo


async def asegurar_esquema_listo() -> None:
    """Gate de ``get_db``: en SQL Server exige esquema listo (o lo comprueba).

    * Motor PostgreSQL → retorno inmediato (camino intacto).
    * Estado ``None`` o ``"pendiente"`` vencido (TTL 60 s) → consulta barata.
    * Estado ``"pendiente"`` fresco → ``EsquemaPendienteError`` (503 Fase 2).
    * Estado ``"aplicado"`` → pegajoso, no vuelve a consultar.
    """
    from app.core.config import settings

    if detectar_motor(settings.database_url) != "sqlserver":
        return

    if drivers_faltantes():
        # Sin drivers no hay forma de consultar sys.tables. No se siembra TTL:
        # el flag persiste hasta el reinicio con el extra instalado, y el 503
        # sale con codigo=sqlserver_sin_drivers (contrato con la app Flutter).
        raise DriversFaltantesError(MENSAJE_SIN_DRIVERS)

    estado = estado_esquema()
    if estado is None or (estado == "pendiente" and not _estado_fresco()):
        try:
            estado = await _consultar_esquema_sqlserver()
        except Exception:
            # LOW-001: un fallo de conexión/ODBC al contar tablas restablece
            # la caché al valor inicial ANTES de propagar, para que no quede
            # un "pendiente" caduco que enmascare los reintentos.
            reiniciar_estado_esquema()
            raise
    if estado == "pendiente":
        raise EsquemaPendienteError(MENSAJE_FASE_2)


# ---------------------------------------------------------------------------
# Exception handlers globales
# ---------------------------------------------------------------------------
def _password_de(url: str) -> str:
    try:
        return unquote(urlparse(url).password or "")
    except Exception:  # noqa: BLE001 (URL rota: no hay password que enmascarar)
        return ""


# MED-001: patrones de password en mensajes de driver (case-insensitive).
# Conn-strings ODBC: `PWD=…`, `Password = …` → `password=***` (el valor se
# corta en el `;` del DSN: si la password contiene `;` se sana hasta ese
# separador, límite asumido). URLs: `://user:pwd@` → `://user:***@` (el valor
# puede contener `=`, se corta en `@`).
_PATRON_PWD_DSN = re.compile(r"(?i)\b(?:password|pwd)\s*=\s*([^;]+)")
_PATRON_PWD_URL = re.compile(r"(?i)://([^:@/]+):([^@/]+)@")


def sanear_password_en_mensaje(texto: str) -> str:
    """Sustituye por ``***`` las passwords embebidas en un mensaje de error.

    Cubre conn-strings ODBC (``PWD=valor`` / ``Password = valor``, con o sin
    espacios y en cualquier combinación de mayúsculas) y URLs
    (``://user:valor@``). El resto del mensaje no se toca. Idempotente:
    aplicarlo dos veces produce el mismo texto.
    """
    salida = _PATRON_PWD_DSN.sub("password=***", texto)
    return _PATRON_PWD_URL.sub(r"://\1:***@", salida)


def _texto_orig(exc: BaseException) -> str:
    """``str(exc.orig)`` con toda password embebida sustituida por ``***``.

    Se aplica SIEMPRE antes de incrustar el texto del driver en un log o en una
    respuesta: una URL mal formada o un DSN filtrado por pyodbc/psycopg2
    podrían contener la password en claro o percent-encoded.

    Tres capas (MED-001): (1) la password real de ``DATABASE_URL`` en crudo,
    (2) su versión percent-encoded, (3) los patrones ``PWD=``/``password=``
    y ``://user:pwd@`` de cualquier otro DSN que aparezca en el mensaje.
    """
    from app.core.config import settings

    texto = str(getattr(exc, "orig", None) or exc)
    pwd = _password_de(settings.database_url)
    if pwd:
        texto = texto.replace(pwd, "***")
        codificada = quote(pwd, safe="")
        if codificada != pwd:
            texto = texto.replace(codificada, "***")
    return sanear_password_en_mensaje(texto)


def _sqlstate(exc: BaseException) -> str:
    """SQLSTATE del error de BD (psycopg2 ``pgcode``, pyodbc ``args[0]``…)."""
    orig = getattr(exc, "orig", None) or exc
    for attr in ("pgcode", "sqlstate"):
        valor = getattr(orig, attr, None)
        if isinstance(valor, str) and valor:
            return valor
    args = getattr(orig, "args", ())
    if args and isinstance(args[0], str) and len(args[0]) == 5:
        return args[0]
    coincidencia = re.search(r"\[([0-9A-Za-z]{5})\]", str(orig))
    if coincidencia is None:
        coincidencia = re.search(r"\(([0-9A-Za-z]{5})\)", str(orig))
    return coincidencia.group(1) if coincidencia else ""


def manejador_esquema_pendiente(request, exc) -> JSONResponse:
    """503 de esquema pendiente (modo degradado SQL Server, Fase 1)."""
    return JSONResponse(
        status_code=503,
        content={
            "detail": MENSAJE_FASE_2,
            "codigo": CODIGO_ESQUEMA_PENDIENTE,
        },
    )


def manejador_drivers_faltantes(request, exc) -> JSONResponse:
    """503 de drivers ODBC ausentes (modo degradado, Opción B).

    El ``codigo`` es exactamente ``sqlserver_sin_drivers``: la app Flutter lo
    mira para pintar el aviso con la instrucción de instalación.
    """
    return JSONResponse(
        status_code=503,
        content={
            "detail": MENSAJE_SIN_DRIVERS,
            "codigo": CODIGO_SIN_DRIVERS,
        },
    )


def manejador_error_bd(request, exc) -> Response:
    """Traduce errores de BD SQL Server a 503 con significado.

    * Motor PostgreSQL (o prefijo ilegible) → se re-lanza ``exc``: respuesta
      500 byte-idéntica a la de siempre.
    * SQL Server con objeto ausente (42S02/42703/42P01/42704 o frases
      «invalid object name»…) → 503 ``esquema_mssql_pendiente``.
    * SQL Server sin conectividad (SQLSTATE 08* o «login failed»…) → 503
      ``sqlserver_sin_conexion``.
    * Cualquier otro → se re-lanza ``exc``.
    """
    import logging

    from app.core.config import settings

    log = logging.getLogger("balansoft_ws.db")

    try:
        motor = detectar_motor(settings.database_url)
    except ValueError:
        raise exc from None
    if motor != "sqlserver":
        raise exc

    texto = _texto_orig(exc)
    sqlstate = _sqlstate(exc).upper()
    bajo = texto.casefold()

    if sqlstate in _SQLSTATE_ESQUEMA or any(f in bajo for f in _FRASES_ESQUEMA):
        marcar_estado_esquema("pendiente")
        log.warning("SQL Server: objeto ausente → 503 Fase 2 (%s)", texto)
        return JSONResponse(
            status_code=503,
            content={
                "detail": MENSAJE_FASE_2,
                "codigo": CODIGO_ESQUEMA_PENDIENTE,
            },
        )

    if sqlstate.startswith("08") or any(f in bajo for f in _FRASES_CONEXION):
        log.warning("SQL Server: sin conexión → 503 (%s)", texto)
        return JSONResponse(
            status_code=503,
            content={
                "detail": MENSAJE_SIN_CONEXION,
                "codigo": CODIGO_SIN_CONEXION,
            },
        )

    log.warning("SQL Server: error no clasificado, se propaga (%s)", texto)
    raise exc


def error_drivers_faltantes(motor: str, exc: BaseException | None) -> RuntimeError:
    """RuntimeError con la instrucción de instalación de los drivers ODBC.

    Sigue existiendo para los avisos de consola del bootstrap del WServer
    (``wserver.py``) y para tests; el flujo de la API ya NO aborta con él:
    ``database.py`` siembra ``marcar_drivers_faltantes()`` en su lugar y el
    503 sale vía ``manejador_drivers_faltantes`` (Opción B).
    """
    if motor == "sqlserver":
        mensaje = MENSAJE_SIN_DRIVERS
    else:
        mensaje = f"Faltan los drivers del motor {motor!r} requerido por DATABASE_URL."
    if exc is not None:
        mensaje = f"{mensaje} Causa: {exc}"
    return RuntimeError(mensaje)


def registrar_manejadores_bd(app) -> None:
    """Registra los exception handlers globales de BD en la app FastAPI."""
    import sqlalchemy.exc

    app.add_exception_handler(EsquemaPendienteError, manejador_esquema_pendiente)
    app.add_exception_handler(DriversFaltantesError, manejador_drivers_faltantes)
    app.add_exception_handler(sqlalchemy.exc.DBAPIError, manejador_error_bd)

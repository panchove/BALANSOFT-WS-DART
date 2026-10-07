"""WServer — back-end local de Balansoft-WS, compilado con PyInstaller.

Responsabilidades:
  1. Resolver el directorio de runtime (config, media, logs, backups).
  2. Generar ``.env`` desde la plantilla embebida si no existe
     (con ``SECRET_KEY`` aleatoria por máquina).
  3. Asegurar la base de datos local: crearla si falta y aplicar el esquema
     canónico + migraciones de forma idempotente (sin depender de psql).
  4. Levantar la API FastAPI (APP_ROLE=local) con uvicorn.

Está pensado para ejecutarse de forma "frozen" (PyInstaller one-file), pero
también funciona en desarrollo:  ``uv run python wserver.py``.
"""

from __future__ import annotations

import argparse
import os
import re
import secrets
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any

# Directorio raíz de los archivos embebidos en el binario (PyInstaller).
if getattr(sys, "frozen", False):
    ROOT = Path(sys._MEIPASS)  # type: ignore[attr-defined]
else:
    ROOT = Path(__file__).resolve().parent

SCHEMA_LOCAL = "balansoft-ws-local.sql"
SCHEMA_SERVER = "balansoft-ws-server.sql"
ENV_PLANTILLA = ".env.plantilla"
MIGRACIONES_DIR = "migrations"

WSERVER_VERSION = "1.0.0"


def _exe_dir() -> Path:
    """Directorio que contiene el binario WServer (o el repo en desarrollo)."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return ROOT


def resolver_home() -> Path:
    """Directorio de runtime del WServer, en orden de prioridad:

    1. ``WSERVER_HOME`` (variable de entorno).
    2. El directorio del binario si ya contiene un ``.env`` (instalación hecha).
    3. ``~/.balansoft-ws/wserver`` (default multiplataforma).
    """
    env = os.environ.get("WSERVER_HOME")
    if env:
        return Path(env).expanduser().resolve()
    exe = _exe_dir()
    if (exe / ".env").exists():
        return exe
    return (Path.home() / ".balansoft-ws" / "wserver").resolve()


def asegurar_estructura(home: Path) -> None:
    """Crea el árbol de directorios del runtime y el ``.env`` si falta."""
    for sub in (".", "logs", "media", "keys", "backups"):
        (home / sub).mkdir(parents=True, exist_ok=True)

    env_file = home / ".env"
    if env_file.exists():
        _migrar_api_host_lan(env_file)
        return

    plantilla = ROOT / ENV_PLANTILLA
    if not plantilla.exists():
        raise FileNotFoundError(
            f"No se encontró la plantilla {ENV_PLANTILLA} en {ROOT}. "
            "El WServer necesita sus datos empaquetados para instalarse."
        )
    texto = plantilla.read_text(encoding="utf-8")
    texto = texto.replace("__SECRET_KEY__", secrets.token_hex(32))
    env_file.write_text(texto, encoding="utf-8")
    print(f"[WServer] .env generado en {env_file}")


def _migrar_api_host_lan(env_file: Path) -> None:
    """Migra instalaciones previas con ``API_HOST=127.0.0.1`` a ``0.0.0.0``.

    El WServer escucha en todas las interfaces por defecto para que clientes
    de la red local (ej. otro equipo operativo) puedan conectarse por IP. Es
    una migración idempotente; solo reescribe la clave si aún conserva el
    valor loopback por defecto.
    """
    try:
        texto = env_file.read_text(encoding="utf-8")
        nuevo = re.sub(
            r"^API_HOST=127\.0\.0\.1\s*$",
            "API_HOST=0.0.0.0",
            texto,
            flags=re.MULTILINE,
        )
        if nuevo != texto:
            env_file.write_text(nuevo, encoding="utf-8")
            print("[WServer] API_HOST migrado a 0.0.0.0 (acceso desde la red local).")
    except OSError as exc:
        print(f"[WServer] Aviso: no se pudo verificar API_HOST ({exc}).")


# ---------------------------------------------------------------------------
# Bootstrap de la base de datos local
# ---------------------------------------------------------------------------
def _descomponer_url(url: str) -> dict[str, Any]:
    """Extrae motor, host, puerto, usuario, password, bd y query de una URL.

    Normaliza los prefijos con driver (``postgresql+asyncpg``,
    ``mssql+aioodbc``…) a su forma base solo para poder parsearlos; el prefijo
    ORIGINAL se devuelve en la clave ``prefijo`` para poder reconstruir la URL
    byte a byte. El puerto por defecto depende del motor (5432 / 1433).
    """
    from urllib.parse import parse_qsl, unquote, urlparse

    from app.core.db_engine import detectar_motor, puerto_default

    motor = detectar_motor(url)
    corte = url.find("://")
    prefijo = url[: corte + 3] if corte >= 0 else "postgresql://"
    esquema_crudo = prefijo[:-3].lower()
    esquema_base = "postgresql" if esquema_crudo.startswith("postgresql") else "mssql"
    resto = url[corte + 3 :] if corte >= 0 else url
    p = urlparse(f"{esquema_base}://{resto}")
    return {
        "motor": motor,
        "prefijo": prefijo,
        "host": p.hostname or "localhost",
        "port": p.port or puerto_default(motor),
        "user": unquote(p.username or ""),
        "password": unquote(p.password or ""),
        "db": p.path.lstrip("/"),
        "query": p.query,
        "params": dict(parse_qsl(p.query)),
    }


def _existe_esquema(db_url_sync: str) -> bool:
    """True si la BD destino ya tiene tablas (esquema aplicado previamente)."""
    from app.core.db_engine import detectar_motor, dsn_pyodbc

    if detectar_motor(db_url_sync) == "sqlserver":
        # Fase 1: solo se puede detectar si alguien creó tablas a mano; el
        # DDL canónico (sys.tables) llega en Fase 2. LOW-002: el filtro es
        # explícito sobre el esquema dbo, como en PG schemaname='public'
        # (mismo criterio que sql_conteo_tablas de app/core/db_engine.py).
        try:
            import pyodbc
        except Exception:  # noqa: BLE001 (sin driver no hay forma de comprobar)
            return False
        c = _descomponer_url(db_url_sync)
        conn = None
        try:
            conn = pyodbc.connect(dsn_pyodbc(c), autocommit=True, timeout=3)
            cur = conn.cursor()
            cur.execute(
                "SELECT COUNT(*) FROM sys.tables WHERE SCHEMA_NAME(schema_id) = N'dbo'"
            )
            return bool(cur.fetchone()[0])
        except Exception:  # noqa: BLE001 (espejo del camino PG: cualquier fallo = False)
            return False
        finally:
            if conn is not None:
                conn.close()

    import psycopg2

    c = _descomponer_url(db_url_sync)
    try:
        with psycopg2.connect(
            host=c["host"],
            port=c["port"],
            user=c["user"],
            password=c["password"],
            dbname=c["db"],
            connect_timeout=3,
        ) as conn:
            conn.autocommit = True
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT EXISTS (SELECT 1 FROM pg_tables "
                    "WHERE schemaname = 'public')"
                )
                return bool(cur.fetchone()[0])
    except Exception:
        return False


def crear_bd_si_falta(db_url_sync: str) -> None:
    """Crea la base de datos si no existe.

    * PostgreSQL → conexión a la DB ``postgres`` (camino actual, sin cambios).
    * SQL Server → conexión a ``master`` con la sentencia idempotente
      ``IF DB_ID(N'…') IS NULL CREATE DATABASE […]``; si el usuario no tiene
      permisos se avisa y se continúa (no bloquea el arranque).
    """
    from app.core.db_engine import detectar_motor

    if detectar_motor(db_url_sync) == "sqlserver":
        _crear_bd_sqlserver(db_url_sync)
        return

    import psycopg2
    from psycopg2 import sql

    c = _descomponer_url(db_url_sync)
    conn = None
    try:
        # Sin context manager de la conexión: en psycopg2 usar ``with conn``
        # deja inactive el ``autocommit`` y CREATE DATABASE falla con
        # "cannot run inside a transaction block".
        conn = psycopg2.connect(
            host=c["host"],
            port=c["port"],
            user=c["user"],
            password=c["password"],
            dbname="postgres",
            connect_timeout=5,
        )
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM pg_database WHERE datname = %s", (c["db"],)
            )
            if cur.fetchone():
                return
            cur.execute(
                sql.SQL("CREATE DATABASE {}").format(sql.Identifier(c["db"]))
            )
            print(f"[WServer] Base de datos '{c['db']}' creada.")
    except Exception as exc:  # noqa: BLE001
        print(
            f"[WServer] ⚠ No se pudo verificar/crear '{c['db']}' "
            f"({c['host']}:{c['port']}): {exc}",
            file=sys.stderr,
        )
    finally:
        if conn is not None:
            conn.close()


def _crear_bd_sqlserver(db_url: str) -> None:
    """Crea la BD en SQL Server si falta (conexión a ``master``, autocommit).

    Idempotente y tolerante a permisos ausentes: un login sin
    ``CREATE DATABASE`` solo genera un aviso, porque en Fase 1 la BD puede
    venir ya creada por el administrador.
    """
    from app.core.db_engine import dsn_pyodbc

    import pyodbc

    c = _descomponer_url(db_url)
    nombre = str(c["db"])
    # Escapes T-SQL: comilla simple duplicada en la literal N'…' y corchete
    # duplicado en el identificador […].
    literal = nombre.replace("'", "''")
    identificador = nombre.replace("]", "]]")
    conn = None
    try:
        conn = pyodbc.connect(dsn_pyodbc({**c, "db": "master"}), autocommit=True, timeout=5)
        cur = conn.cursor()
        cur.execute(f"SELECT DB_ID(N'{literal}')")
        existia = cur.fetchone()[0] is not None
        if not existia:
            # Sentencia idempotente: si otra instancia lo creó en medio, no falla.
            cur.execute(
                f"IF DB_ID(N'{literal}') IS NULL CREATE DATABASE [{identificador}];"
            )
            print(f"[WServer] Base de datos '{nombre}' creada (SQL Server).")
        cur.close()
    except Exception as exc:  # noqa: BLE001
        print(
            f"[WServer] ⚠ No se pudo verificar/crear '{nombre}' "
            f"({c['host']}:{c['port']}): {exc}",
            file=sys.stderr,
        )
        print(
            "[WServer] ⚠ Si el usuario no tiene permiso CREATE DATABASE, crea la "
            "BD manualmente (o pide permisos) y vuelve a arrancar el WServer.",
            file=sys.stderr,
        )
    finally:
        if conn is not None:
            conn.close()


def _aplicar_sql(cur, ruta_absoluta: Path, etiqueta: str) -> None:
    """Ejecuta un archivo SQL sobre el cursor actual."""
    sql_texto = ruta_absoluta.read_text(encoding="utf-8")
    cur.execute(sql_texto)
    print(f"[WServer] Esquema aplicado: {etiqueta}")


def _migraciones_pendientes(cur, mig_dir: Path) -> list[Path]:
    """Devuelve los archivos de migración que aún no se han aplicado.

    Las instalaciones existentes (creadas antes de este registro) se marcan
    como aplicadas para no reejecutar el esquema canónico; a partir de ahí
    cada arranque aplica solo lo nuevo (REQ-NF-CFG-001 → migración 017).
    """
    cur.execute(
        "CREATE TABLE IF NOT EXISTS schema_migrations ("
        "version TEXT PRIMARY KEY, aplicada_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP)"
    )
    cur.execute("SELECT version FROM schema_migrations")
    aplicadas = {fila[0] for fila in cur.fetchall()}
    if not mig_dir.exists():
        return []
    archivos = sorted(mig_dir.glob("*.sql"))
    if not aplicadas:
        # Instalación previa sin registro: se reejecutan TODAS (son
        # idempotentes) y quedan registradas, para que las columnas nuevas
        # lleguen a estaciones ya instaladas.
        return archivos
    return [mig for mig in archivos if mig.name not in aplicadas]


def _registrar_migracion(cur, version: str) -> None:
    cur.execute(
        "INSERT INTO schema_migrations (version) VALUES (%s) ON CONFLICT DO NOTHING",
        (version,),
    )


def _asegurar_db_sqlserver(db_url: str) -> None:
    """Bootstrap SQL Server en Fase 1: SOLO crea la BD y comprueba tablas.

    No aplica ``balansoft-ws-local.sql`` ni ``migrations/*.sql`` (son DDL de
    PostgreSQL): el esquema de SQL Server llega en **Fase 2**. El resultado se
    siembra en la caché de ``app.core.db_engine`` para que la API responda
    503 «esquema pendiente» hasta entonces. **No falla el arranque.**
    """
    import importlib.util

    from app.core.db_engine import error_drivers_faltantes, marcar_estado_esquema

    if importlib.util.find_spec("pyodbc") is None:
        print(f"[WServer] ✗ {error_drivers_faltantes('sqlserver', None)}", file=sys.stderr)
        return

    c = _descomponer_url(db_url)
    try:
        crear_bd_si_falta(db_url)
        con_tablas = _existe_esquema(db_url)
    except Exception as exc:  # noqa: BLE001 (una BD inalcanzable no tumba el arranque)
        print(
            f"[WServer] ⚠ No se pudo verificar la BD de SQL Server '{c['db']}' "
            f"({c['host']}:{c['port']}): {exc}",
            file=sys.stderr,
        )
        con_tablas = False

    marcar_estado_esquema("aplicado" if con_tablas else "pendiente")
    print(
        "[WServer] SQL Server en modo degradado — Fase 2: el esquema de SQL Server "
        "se aplicará en Fase 2; el WServer funciona en modo degradado sin datos. "
        "No se aplican balansoft-ws-local.sql ni migrations/*.sql a esta base de datos."
    )
    print(
        "[WServer] Estado del esquema: "
        + ("pendiente (la API responderá 503 hasta Fase 2)" if not con_tablas else "tablas detectadas")
        + "."
    )


def asegurar_db(db_url_sync: str) -> None:
    """Crea la BD si falta y aplica el esquema local + migraciones pendientes.

    PostgreSQL (camino actual, sin cambios): idempotente; el esquema canónico
    solo se aplica cuando la BD está vacía y las migraciones de
    ``migrations/*.sql`` se aplican **en cada arranque** usando el registro
    ``schema_migrations``. Para un vaciado real: ``scripts/reset_db.sh``.

    SQL Server (Fase 1, modo degradado): ver ``_asegurar_db_sqlserver``; solo
    crea la BD y comprueba si hay tablas, sin aplicar DDL.
    """
    from app.core.db_engine import detectar_motor

    if detectar_motor(db_url_sync) == "sqlserver":
        _asegurar_db_sqlserver(db_url_sync)
        return

    c = _descomponer_url(db_url_sync)
    esquema_previo = _existe_esquema(db_url_sync)

    import psycopg2

    crear_bd_si_falta(db_url_sync)

    try:
        with psycopg2.connect(
            host=c["host"],
            port=c["port"],
            user=c["user"],
            password=c["password"],
            dbname=c["db"],
            connect_timeout=5,
        ) as conn:
            mig_dir = ROOT / MIGRACIONES_DIR
            with conn.cursor() as cur:
                if esquema_previo:
                    pendientes = _migraciones_pendientes(cur, mig_dir)
                else:
                    pendientes = []
            if esquema_previo:
                print("[WServer] Esquema local ya aplicado (no se re-esquemera).")
            else:
                with conn.cursor() as cur:
                    # Esquema canónico (incluye una transacción propia implicita).
                    _aplicar_sql(cur, ROOT / SCHEMA_LOCAL, SCHEMA_LOCAL)
                    conn.commit()
                with conn.cursor() as cur:
                    pendientes = _migraciones_pendientes(cur, mig_dir)
            for mig in pendientes:
                with conn.cursor() as mcur:
                    _aplicar_sql(mcur, mig, mig.name)
                    _registrar_migracion(mcur, mig.name)
                conn.commit()
            if not esquema_previo and not pendientes:
                # BD recién creada: registrar el estado para los próximos arranques.
                with conn.cursor() as cur:
                    for mig in sorted(mig_dir.glob("*.sql")) if mig_dir.exists() else []:
                        _registrar_migracion(cur, mig.name)
                conn.commit()
            print(
                "[WServer] Base de datos local lista "
                f"(migraciones aplicadas: {len(pendientes)})."
            )
    except Exception as exc:  # noqa: BLE001
        print(
            f"[WServer] ⚠ No se pudo inicializar la BD local '{c['db']}': {exc}",
            file=sys.stderr,
        )


def _procesar_script(uri: str, script: Path, etiqueta: str) -> None:
    # Código muerto en el arranque normal (lo usaban los scripts de soporte);
    # el bootstrap de SQL Server Fase 1 no lo invoca.
    import psycopg2

    c = _descomponer_url(uri)
    with psycopg2.connect(
        host=c["host"],
        port=c["port"],
        user=c["user"],
        password=c["password"],
        dbname=c["db"],
    ) as conn:
        with conn.cursor() as cur:
            cur.execute(script.read_text(encoding="utf-8"))
            conn.commit()
        print(f"[WServer] Aplicado: {etiqueta}")


# ---------------------------------------------------------------------------
# Arranque de la API
# ---------------------------------------------------------------------------

def _configurar_firewall(port: int) -> None:
    """Abre el puerto del API en el firewall local (best-effort).

    Usa ``pkexec`` (autenticación gráfica de polkit) para que el usuario no
    tenga que acordarse de ejecutar comandos manuales. Si no hay privilegios
    ni gestor de firewall, lo informa sin bloquear el arranque.
    """
    if not shutil.which("ufw"):
        return
    cmd_allow = shutil.which("pkexec") or shutil.which("sudo") or shutil.which("doas")
    if not cmd_allow:
        print(f"[WServer] Aviso: no se pudo abrir el puerto {port} en el firewall "
              "(ufw). Si falla el acceso remoto, ejecuta: sudo ufw allow {port}/tcp")
        return
    try:
        proc = subprocess.run(
            [cmd_allow, "ufw", "allow", f"{port}/tcp"],
            capture_output=True, text=True, timeout=90,
        )
        if proc.returncode == 0:
            print(f"[WServer] Firewall: puerto {port}/tcp abierto (ufw).")
        elif cmd_allow.endswith("pkexec"):
            print(f"[WServer] Firewall: usuario no autorizó abrir el puerto {port} "
                  f"({proc.stderr.strip() or 'cancelado'}).")
    except (subprocess.TimeoutExpired, OSError) as exc:
        print(f"[WServer] Firewall: no se pudo configurar ufw ({exc}).")


def _ip_local() -> str | None:
    """Devuelve la IP de la LAN desde donde se alcanzará el API (o ``None``)."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except OSError:
        return None


def _es_bind_red(host: str) -> bool:
    return host not in ("127.0.0.1", "localhost", "::1", "")


def _actualizar_env_si_aplica(home: Path, args: argparse.Namespace) -> None:
    """Actualiza el archivo .env con los parámetros proporcionados.

    Conserva el prefijo original del motor (``postgresql+asyncpg``,
    ``mssql+aioodbc``…) y su query string (p. ej. ``TrustServerCertificate``);
    ``DATABASE_URL_SYNC`` se reconstruye con ``PREFIJO_SYNC`` para que ambas
    líneas sigan apuntando al mismo motor.
    """
    if not any([args.db_host, args.db_port, args.db_user, args.db_pass, args.db_name, args.api_port, args.api_host]):
        return
        
    env_file = home / ".env"
    if not env_file.exists():
        return
        
    texto = env_file.read_text(encoding="utf-8")

    def _defaults_postgres() -> dict[str, object]:
        return {
            "motor": "postgresql",
            "prefijo": "postgresql+asyncpg://",
            "user": "balansoft",
            "password": "CHANGE_ME",
            "host": "localhost",
            "port": "5432",
            "db": "balansoft_ws_local",
            "query": "",
        }

    # 1. Localizar la URL actual (sin exigir puerto ni motor concreto)
    match = re.search(r"^DATABASE_URL=(.*)$", texto, flags=re.MULTILINE)
    if not match:
        print(
            "[WServer] ⚠ No se encontró DATABASE_URL en el .env; se usan los "
            "defaults PostgreSQL.",
            file=sys.stderr,
        )
        comp = _defaults_postgres()
    else:
        try:
            comp = _descomponer_url(match.group(1).strip())
        except ValueError as exc:
            print(
                f"[WServer] ⚠ DATABASE_URL ilegible ({exc}); se usan los "
                "defaults PostgreSQL.",
                file=sys.stderr,
            )
            comp = _defaults_postgres()

    # 2. Aplicar overrides
    curr_user = str(comp["user"])
    curr_pass = str(comp["password"])
    curr_host = str(comp["host"])
    curr_port = str(comp["port"])
    curr_db = str(comp["db"])
    query = str(comp["query"])
    prefijo = str(comp["prefijo"])

    new_user = args.db_user if args.db_user else curr_user
    new_pass = args.db_pass if args.db_pass else curr_pass
    new_host = args.db_host if args.db_host else curr_host
    new_port = args.db_port if args.db_port else curr_port
    new_db = args.db_name if args.db_name else curr_db

    # 3. Reconstruir conservando prefijo original y query original
    from urllib.parse import quote

    from app.core.db_engine import PREFIJO_SYNC

    def _url(pref: str) -> str:
        base = (
            f"{pref}{quote(str(new_user), safe='')}:{quote(str(new_pass), safe='')}"
            f"@{new_host}:{new_port}/{new_db}"
        )
        return f"{base}?{query}" if query else base

    new_url_async = _url(prefijo)
    new_url_sync = _url(PREFIJO_SYNC[prefijo.lower()])

    # 4. Reemplazar URLs en el texto (lambda: una password con '\g' o '\' no
    # debe interpretarse como referencia de grupo de re.sub)
    texto = re.sub(
        r"^DATABASE_URL=.*$", lambda _: f"DATABASE_URL={new_url_async}", texto, flags=re.MULTILINE
    )
    texto = re.sub(
        r"^DATABASE_URL_SYNC=.*$",
        lambda _: f"DATABASE_URL_SYNC={new_url_sync}",
        texto,
        flags=re.MULTILINE,
    )

    # 5. Reemplazar puerto / host del API si aplica
    if args.api_port:
        texto = re.sub(r"^API_PORT=.*$", f"API_PORT={args.api_port}", texto, flags=re.MULTILINE)
    if args.api_host:
        texto = re.sub(r"^API_HOST=.*$", f"API_HOST={args.api_host}", texto, flags=re.MULTILINE)
        
    env_file.write_text(texto, encoding="utf-8")
    print("[WServer] .env actualizado con los nuevos parámetros de configuración.")


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="WServer",
        description="Backend local de Balansoft-WS (API FastAPI).",
    )
    parser.add_argument("--version", action="store_true", help="muestra la versión")
    parser.add_argument("--home", type=str, help="override del directorio de runtime")
    parser.add_argument(
        "--no-bootstrap",
        action="store_true",
        help="no tocar la BD: solo levantar la API con la configuración existente",
    )
    # Argumentos de configuración de BD (PostgreSQL o SQL Server: el motor se
    # decide por el prefijo de DATABASE_URL, ver app/core/db_engine.py)
    parser.add_argument("--db-host", type=str, help="Host de la base de datos PostgreSQL o SQL Server")
    parser.add_argument("--db-port", type=str, help="Puerto de la base de datos PostgreSQL o SQL Server")
    parser.add_argument("--db-user", type=str, help="Usuario de la base de datos")
    parser.add_argument("--db-pass", type=str, help="Contraseña de la base de datos")
    parser.add_argument("--db-name", type=str, help="Nombre de la base de datos")
    parser.add_argument("--api-port", type=str, help="Puerto donde levantará la API local")
    parser.add_argument(
        "--api-host", type=str,
        help="Interfaz donde escucha la API (por defecto 0.0.0.0 = toda la red local)",
    )
    
    args = parser.parse_args()

    if args.version:
        print(f"WServer {WSERVER_VERSION}")
        return 0

    home = Path(args.home).expanduser().resolve() if args.home else resolver_home()
    asegurar_estructura(home)
    
    # Actualizar .env si se pasaron argumentos por consola
    _actualizar_env_si_aplica(home, args)

    # La configuración (.env) es relativa al CWD: la app se ejecuta desde home.
    os.chdir(home)

    # Bootstrap idempotente de la BD local (antes de levantar la API).
    if not args.no_bootstrap:
        from app.core.config import settings

        asegurar_db(settings.database_url_sync)

    # Importar la app tras chdir para que pydantic-settings lea el .env del home.
    from app.core.config import settings
    from app.main import app

    host = settings.api_host
    port = settings.api_port
    if _es_bind_red(host):
        _configurar_firewall(port)
    print(f"[WServer] Levantando API local en http://{host}:{port} "
          f"(env={settings.app_env})")
    ip = _ip_local()
    if _es_bind_red(host) and ip:
        print(f"[WServer] ✅ Accesible desde la red local en "
              f"http://{ip}:{port} (cliente/estación remota)")

    import uvicorn

    if settings.api_reload and not getattr(sys, "frozen", False):
        # En desarrollo, reload via uvicorn con el módulo (necesita argv).
        sys.argv = ["uvicorn", "app.main:app", "--host", host, "--port", str(port)]
        return uvicorn.main()
    uvicorn.run(app, host=host, port=port, log_level=settings.log_level.lower())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
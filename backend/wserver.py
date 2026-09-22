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
import secrets
import sys
from pathlib import Path

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


# ---------------------------------------------------------------------------
# Bootstrap de la base de datos local
# ---------------------------------------------------------------------------
def _descomponer_url(url: str) -> dict[str, object]:
    """Extrae host, puerto, usuario, password y bd de una URL SQLAlchemy."""
    from urllib.parse import unquote, urlparse

    u = url.replace("postgresql+psycopg2://", "postgresql://").replace(
        "postgresql+asyncpg://", "postgresql://"
    )
    p = urlparse(u)
    return {
        "host": p.hostname or "localhost",
        "port": p.port or 5432,
        "user": unquote(p.username or ""),
        "password": unquote(p.password or ""),
        "db": p.path.lstrip("/"),
    }


def _existe_esquema(db_url_sync: str) -> bool:
    """True si la BD local ya tiene tablas (esquema aplicado previamente)."""
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
    """Crea la base de datos si no existe (conexión a la DB 'postgres')."""
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


def _aplicar_sql(cur, ruta_absoluta: Path, etiqueta: str) -> None:
    """Ejecuta un archivo SQL sobre el cursor actual."""
    sql_texto = ruta_absoluta.read_text(encoding="utf-8")
    cur.execute(sql_texto)
    print(f"[WServer] Esquema aplicado: {etiqueta}")


def asegurar_db(db_url_sync: str) -> None:
    """Crea la BD si falta y aplica el esquema local + migraciones.

    Idempotente: si el esquema ya está aplicado (hay tablas) se omite el paso
    para arrancar rápido en cada inicio. Para un vaciado real:
    ``scripts/reset_db.sh``.
    """
    c = _descomponer_url(db_url_sync)
    if _existe_esquema(db_url_sync):
        print("[WServer] Esquema local ya aplicado (no se re-esquemera).")
        return

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
            with conn.cursor() as cur:
                # Esquema canónico (incluye una transacción propia implicita).
                _aplicar_sql(cur, ROOT / SCHEMA_LOCAL, SCHEMA_LOCAL)
                conn.commit()
                mig_dir = ROOT / MIGRACIONES_DIR
                if mig_dir.exists():
                    for mig in sorted(mig_dir.glob("*.sql")):
                        with conn.cursor() as mcur:
                            _aplicar_sql(mcur, mig, mig.name)
                            conn.commit()
                print("[WServer] Base de datos local lista (esquema + migraciones).")
    except Exception as exc:  # noqa: BLE001
        print(
            f"[WServer] ⚠ No se pudo inicializar la BD local '{c['db']}': {exc}",
            file=sys.stderr,
        )


def _procesar_script(uri: str, script: Path, etiqueta: str) -> None:
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
import re

def _actualizar_env_si_aplica(home: Path, args: argparse.Namespace) -> None:
    """Actualiza el archivo .env con los parámetros proporcionados."""
    if not any([args.db_host, args.db_port, args.db_user, args.db_pass, args.db_name, args.api_port]):
        return
        
    env_file = home / ".env"
    if not env_file.exists():
        return
        
    texto = env_file.read_text(encoding="utf-8")
    
    # 1. Extraer los valores actuales de DATABASE_URL
    match = re.search(r"DATABASE_URL=postgresql\+asyncpg://(.*?):(.*?)@(.*?):(\d+)/(.*)", texto)
    if match:
        curr_user, curr_pass, curr_host, curr_port, curr_db = match.groups()
    else:
        curr_user, curr_pass, curr_host, curr_port, curr_db = "balansoft", "CHANGE_ME", "localhost", "5432", "balansoft_ws_local"
        
    # 2. Aplicar overrides
    new_user = args.db_user if args.db_user else curr_user
    new_pass = args.db_pass if args.db_pass else curr_pass
    new_host = args.db_host if args.db_host else curr_host
    new_port = args.db_port if args.db_port else curr_port
    new_db = args.db_name if args.db_name else curr_db
    
    # 3. Reemplazar URLs en el texto
    new_url_async = f"postgresql+asyncpg://{new_user}:{new_pass}@{new_host}:{new_port}/{new_db}"
    new_url_sync = f"postgresql+psycopg2://{new_user}:{new_pass}@{new_host}:{new_port}/{new_db}"
    
    texto = re.sub(r"^DATABASE_URL=.*$", f"DATABASE_URL={new_url_async}", texto, flags=re.MULTILINE)
    texto = re.sub(r"^DATABASE_URL_SYNC=.*$", f"DATABASE_URL_SYNC={new_url_sync}", texto, flags=re.MULTILINE)
    
    # 4. Reemplazar puerto API si aplica
    if args.api_port:
        texto = re.sub(r"^API_PORT=.*$", f"API_PORT={args.api_port}", texto, flags=re.MULTILINE)
        
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
    # Argumentos de configuración de BD
    parser.add_argument("--db-host", type=str, help="Host de la base de datos PostgreSQL")
    parser.add_argument("--db-port", type=str, help="Puerto de la base de datos PostgreSQL")
    parser.add_argument("--db-user", type=str, help="Usuario de la base de datos")
    parser.add_argument("--db-pass", type=str, help="Contraseña de la base de datos")
    parser.add_argument("--db-name", type=str, help="Nombre de la base de datos")
    parser.add_argument("--api-port", type=str, help="Puerto donde levantará la API local")
    
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
    print(f"[WServer] Levantando API local en http://{host}:{port} "
          f"(env={settings.app_env})")

    import uvicorn

    if settings.api_reload and not getattr(sys, "frozen", False):
        # En desarrollo, reload via uvicorn con el módulo (necesita argv).
        sys.argv = ["uvicorn", "app.main:app", "--host", host, "--port", str(port)]
        return uvicorn.main()
    uvicorn.run(app, host=host, port=port, log_level=settings.log_level.lower())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
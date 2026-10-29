# -*- mode: python ; coding: utf-8 -*-
# ============================================================
# WServer.spec — Empaquetado one-file del backend local (API FastAPI)
#
# Build:  cd backend && uv run pyinstaller WServer.spec --noconfirm
# Salida: backend/dist/WServer/WServer   (binario único con todos los
#         datos embebidos: esquemas SQL, migraciones y plantilla .env)
# ============================================================

import importlib.util
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

ROOT = Path(SPECPATH).resolve()

# --- Datos embebidos (esquemas + migraciones + configuración de entorno) --------
datas = [
    (str(ROOT / "balansoft-ws-local.sql"), "."),
    (str(ROOT / "balansoft-ws-server.sql"), "."),
    (str(ROOT / ".env"), "."),
    (str(ROOT / ".env.plantilla"), "."),
]
# Icono de la app: lo usa el aviso nativo del SO (app/services/notifier.py).
# Sin él, una estación instalada caería al icono genérico del tema.
if (ROOT / "assets" / "balansoft-ws.png").exists():
    datas.append((str(ROOT / "assets" / "balansoft-ws.png"), "assets"))
for mig in sorted((ROOT / "migrations").glob("*.sql")):
    datas.append((str(mig), "migrations"))
# Esquema T-SQL de SQL Server (Fase 2): dentro de un subdirectorio para no
# confundirlo con el canónico de PostgreSQL.
if (ROOT / "sqlserver" / "balansoft-ws-local.sql").exists():
    datas.append((str(ROOT / "sqlserver" / "balansoft-ws-local.sql"), "sqlserver"))

# --- Módulos con import dinámico que PyInstaller no detecta solo -----------
hiddenimports = collect_submodules("app") + [
    "uvicorn.logging",
    "uvicorn.loops",
    "uvicorn.loops.auto",
    "uvicorn.loops.asyncio",
    "uvicorn.protocols",
    "uvicorn.protocols.http",
    "uvicorn.protocols.http.auto",
    "uvicorn.protocols.http.h11_impl",
    "uvicorn.protocols.http.httptools_impl",
    "uvicorn.protocols.websockets",
    "uvicorn.protocols.websockets.auto",
    "uvicorn.lifespan",
    "uvicorn.lifespan.on",
    "passlib.handlers.bcrypt",
    "bcrypt",
    "multipart",
    "email_validator",
    "asyncpg",
    "psycopg2",
]

# reportlab: las simbologías del código de barras se cargan por ``exec`` dentro
# de ``reportlab/graphics/barcode/widgets.py`` (``_BCW`` hace
# ``from reportlab.graphics.barcode.<modulo> import <Clase>``) y
# ``barcode/__init__.py::_reset`` importa ``eanbc`` y ``qr``; PyInstaller no ve
# esos imports (sus únicos hooks de reportlab son ``lib.utils`` y
# ``pdfbase._fontdata``) y el binario moría al arrancar con
# ``ModuleNotFoundError: No module named 'reportlab.graphics.barcode.code128'``
# —lo dispara el import del QR del boleto—. Se listan las que usa ``_reset``;
# quedan fuera ``dmtx`` (exige pylibdmtx) y ``test``.
hiddenimports += [
    f"reportlab.graphics.barcode.{modulo}"
    for modulo in (
        "common",
        "widgets",
        "code128",
        "code39",
        "code93",
        "eanbc",
        "ecc200datamatrix",
        "usps",
        "usps4s",
        "qr",
    )
]

# Drivers ODBC de SQL Server (extra `uv sync --extra sqlserver`): solo se
# empaquetan si están instalados en el entorno de build; los builds de
# PostgreSQL quedan exactamente igual que antes.
if importlib.util.find_spec("pyodbc") is not None:
    hiddenimports += ["pyodbc", "aioodbc"]

a = Analysis(
    [str(ROOT / "wserver.py")],
    pathex=[str(ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Paquetes que solo depuran/desarrollan y engordan el binario.
        "pytest",
        "pytest_asyncio",
        "mypy",
        "ruff",
    ],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="WServer",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    icon=str(ROOT / "wserver_icon.ico"),
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
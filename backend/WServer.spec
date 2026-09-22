# -*- mode: python ; coding: utf-8 -*-
# ============================================================
# WServer.spec — Empaquetado one-file del backend local (API FastAPI)
#
# Build:  cd backend && uv run pyinstaller WServer.spec --noconfirm
# Salida: backend/dist/WServer/WServer   (binario único con todos los
#         datos embebidos: esquemas SQL, migraciones y plantilla .env)
# ============================================================

from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

ROOT = Path(SPECPATH).resolve()

# --- Datos embebidos (esquemas + migraciones + plantilla de config) --------
datas = [
    (str(ROOT / "balansoft-ws-local.sql"), "."),
    (str(ROOT / "balansoft-ws-server.sql"), "."),
    (str(ROOT / ".env.plantilla"), "."),
]
for mig in sorted((ROOT / "migrations").glob("*.sql")):
    datas.append((str(mig), "migrations"))

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
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
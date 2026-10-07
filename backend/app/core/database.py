"""Configuración de la base de datos SQLAlchemy (async)."""

from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy import Engine, create_engine
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import settings


class Base(DeclarativeBase):
    pass


def _registrar_drivers_faltantes(url: str, exc: ModuleNotFoundError) -> bool:
    """Fase 1 SQL Server (Opción B): siembra el modo degradado y NO aborta.

    Si la URL es de SQL Server y faltan los drivers ODBC, marca el flag global
    en ``db_engine`` (el 503 ``sqlserver_sin_drivers`` saldrá por el gate de
    ``get_db``) y deja que el WServer arranque con health 200.

    Devuelve True si sembró (motor SQL Server); False si el motor no es
    SQL Server o su prefijo es ilegible — en ese caso el llamador re-lanza el
    ``ModuleNotFoundError`` original y el camino PostgreSQL queda byte-idéntico.
    """
    from app.core.db_engine import detectar_motor, marcar_drivers_faltantes

    try:
        motor = detectar_motor(url)
    except ValueError:
        return False
    if motor != "sqlserver":
        return False
    marcar_drivers_faltantes()
    return True


async_engine: AsyncEngine | None
try:
    async_engine = create_async_engine(
        settings.database_url,
        pool_size=10,
        max_overflow=20,
        echo=False,
    )
except ModuleNotFoundError as exc:
    if not _registrar_drivers_faltantes(settings.database_url, exc):
        raise
    async_engine = None

AsyncSessionLocal = async_sessionmaker(
    bind=async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)

# Engine síncrono solo para tareas de scripting (seed, mantenimiento)
sync_engine: Engine | None
try:
    sync_engine = create_engine(settings.database_url_sync, pool_pre_ping=True)
except ModuleNotFoundError as exc:
    if not _registrar_drivers_faltantes(settings.database_url_sync, exc):
        raise
    sync_engine = None
SyncSessionLocal = sessionmaker(bind=sync_engine, autoflush=False, expire_on_commit=False)

# ---------------------------------------------------------------------------
# Motor de la DB del SERVIDOR (cuenta y licencia). Solo se usa en despliegues
# con APP_ROLE=server (o desde el rol local para validar contra el central).
# create_async_engine no conecta hasta el primer uso: seguro para tests.
# ---------------------------------------------------------------------------
server_async_engine: AsyncEngine | None
try:
    server_async_engine = create_async_engine(
        settings.active_server_database_url,
        pool_size=5,
        max_overflow=10,
        echo=False,
    )
except ModuleNotFoundError as exc:
    if not _registrar_drivers_faltantes(settings.active_server_database_url, exc):
        raise
    server_async_engine = None

ServerSessionLocal = async_sessionmaker(
    bind=server_async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependencia de FastAPI para obtener una sesión asíncrona.

    En SQL Server (Fase 1, modo degradado) verifica antes que el esquema
    esté listo y, si no lo está, lanza ``EsquemaPendienteError`` → 503 sin
    llegar a tocar la BD. En PostgreSQL el pre-check sale de inmediato.
    """
    from app.core.db_engine import asegurar_esquema_listo

    await asegurar_esquema_listo()
    async with AsyncSessionLocal() as session:
        yield session


async def get_server_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependencia de FastAPI para sesiones de la DB del servidor (cuenta/licencia)."""
    async with ServerSessionLocal() as session:
        yield session

"""Configuración de la base de datos SQLAlchemy (async)."""

from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy import create_engine
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from app.core.config import settings


class Base(DeclarativeBase):
    pass


async_engine = create_async_engine(
    settings.database_url,
    pool_size=10,
    max_overflow=20,
    echo=False,
)

AsyncSessionLocal = async_sessionmaker(
    bind=async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)

# Engine síncrono solo para tareas de scripting (seed, mantenimiento)
sync_engine = create_engine(settings.database_url_sync, pool_pre_ping=True)
SyncSessionLocal = sessionmaker(bind=sync_engine, autoflush=False, expire_on_commit=False)

# ---------------------------------------------------------------------------
# Motor de la DB del SERVIDOR (cuenta y licencia). Solo se usa en despliegues
# con APP_ROLE=server (o desde el rol local para validar contra el central).
# create_async_engine no conecta hasta el primer uso: seguro para tests.
# ---------------------------------------------------------------------------
server_async_engine = create_async_engine(
    settings.active_server_database_url,
    pool_size=5,
    max_overflow=10,
    echo=False,
)

ServerSessionLocal = async_sessionmaker(
    bind=server_async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependencia de FastAPI para obtener una sesión asíncrona."""
    async with AsyncSessionLocal() as session:
        yield session


async def get_server_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependencia de FastAPI para sesiones de la DB del servidor (cuenta/licencia)."""
    async with ServerSessionLocal() as session:
        yield session

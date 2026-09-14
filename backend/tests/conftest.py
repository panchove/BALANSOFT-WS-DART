"""Configuración de pytest para Balansoft-WS backend.

Usa una base PostgreSQL dedicada (balansoft_ws_test) creada ad-hoc. Cada test
recibe una sesión asíncrona limpia; después de cada test se vacían todas las
tablas para aislar las pruebas entre sí.
"""

from __future__ import annotations

import asyncio
import os
import uuid
from collections.abc import AsyncGenerator

import pytest
import pytest_asyncio
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.models import Base, Empresa

# Overridable por TEST_DATABASE_URL para adaptarse al PostgreSQL del servidor.
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://sqlman:7767@localhost:5432/balansoft_ws_test",
)


@pytest.fixture(scope="session")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(scope="session")
async def _engine():
    engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def db(_engine) -> AsyncGenerator[AsyncSession, None]:
    """Sesión limpia por test. Al finalizar se vacían todas las tablas."""
    session_factory = async_sessionmaker(
        bind=_engine, class_=AsyncSession, expire_on_commit=False
    )
    async with session_factory() as session:
        yield session
    # Limpieza: truncar todas las tablas del modelo en una sola sentencia
    tabla = ", ".join(t.name for t in reversed(Base.metadata.sorted_tables))
    async with _engine.begin() as conn:
        await conn.execute(text(f"TRUNCATE TABLE {tabla} RESTART IDENTITY CASCADE"))


@pytest_asyncio.fixture
async def empresa(db: AsyncSession) -> Empresa:
    """Empresa de prueba reutilizable."""
    emp = Empresa(
        nombre_fiscal="Empresa Test",
        nombre_comercial="Test S.A.",
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        licencia_key=None,
        licencia_tier="CENTRAL",
        licencia_status="ACTIVE",
        activa=True,
    )
    db.add(emp)
    await db.commit()
    await db.refresh(emp)
    return emp

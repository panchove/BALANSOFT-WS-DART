"""Helpers compartidos por las pruebas del módulo Kardex / conceptos_kardex.

Centraliza lo que el ``conftest.py`` general no tiene: app FastAPI fresca con
*dependency overrides* (sin JWT real), una segunda empresa para verificar el
aislamiento multi-tenant y la siembra de catálogo (categoría, producto con
``es_kardex`` y almacén) que necesitan los ajustes manuales.

El patrón replica el de ``tests/test_endpoints.py``: la app se arma con
``API_ROUTERS`` y se sustituyen ``get_db``/``get_current_user``/
``get_current_empresa`` para que cada test corra sobre una sesión limpia.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import Almacen, Categoria, Empresa, Producto, Usuario

ROL_ADMIN = "ADMIN"


async def nueva_empresa(db: AsyncSession, nombre: str = "Empresa Test") -> Empresa:
    """Crea una empresa de prueba y la devuelve ya persistida."""
    emp = Empresa(
        nombre_fiscal=nombre,
        nombre_comercial=nombre,
        rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        licencia_tier="CENTRAL",
        licencia_status="ACTIVE",
        activa=True,
    )
    db.add(emp)
    await db.commit()
    await db.refresh(emp)
    return emp


async def usuario_admin(db: AsyncSession, empresa: Empresa) -> Usuario:
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Test",
        email=f"admin-{uuid.uuid4().hex[:6]}@test.demo",
        password_hash="x",
        rol=ROL_ADMIN,
        activo=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


def armar_app(db: AsyncSession, empresa: Empresa, usuario: Usuario) -> FastAPI:
    """App FastAPI aislada: solo routers locales y dependencias sustituidas."""
    app = FastAPI()
    for router in API_ROUTERS:
        app.include_router(router)

    async def _get_db():
        yield db

    app.dependency_overrides[get_db] = _get_db
    app.dependency_overrides[get_current_user] = lambda: usuario
    app.dependency_overrides[get_current_empresa] = lambda: empresa
    return app


@asynccontextmanager
async def cliente(
    db: AsyncSession, empresa: Empresa, usuario: Usuario | None = None
) -> AsyncGenerator[httpx.AsyncClient, None]:
    """Cliente HTTP contra la app de una empresa concreta (tenant activo)."""
    if usuario is None:
        usuario = await usuario_admin(db, empresa)
    app = armar_app(db, empresa, usuario)
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


CONCEPTOS_SISTEMA: tuple[tuple[int, str, str, str], ...] = (
    (0, "Saldo inicial", "inicial", "AMBOS"),
    (10, "Ingreso por báscula", "positivo", "INGRESO"),
    (60, "Despacho por báscula", "negativo", "DESPACHO"),
)


async def sembrar_conceptos_sistema(db: AsyncSession, empresa: Empresa) -> None:
    """Deja 0/10/60 para la empresa, como hace la migración 031 en producción.

    ``Base.metadata.create_all`` solo crea tablas: no ejecuta las migraciones,
    así que una empresa creada por ORM nace sin conceptos sembrados.
    """
    from app.models import ConceptoKardex

    for id_concepto, nombre, signo, aplica in CONCEPTOS_SISTEMA:
        existe = await db.execute(
            select(ConceptoKardex).where(
                ConceptoKardex.id_empresa == empresa.id_empresa,
                ConceptoKardex.id_concepto == id_concepto,
            )
        )
        if existe.scalar_one_or_none() is None:
            db.add(
                ConceptoKardex(
                    id_empresa=empresa.id_empresa,
                    id_concepto=id_concepto,
                    nombre=nombre,
                    signo=signo,
                    es_sistema=True,
                    activo=True,
                    aplica_a=aplica,
                )
            )
    await db.commit()


async def crear_concepto(
    db: AsyncSession,
    empresa: Empresa,
    id_concepto: int,
    nombre: str,
    signo: str = "positivo",
    activo: bool = True,
):
    """Crea un concepto configurable (no de sistema) por ORM."""
    from app.models import ConceptoKardex

    obj = ConceptoKardex(
        id_empresa=empresa.id_empresa,
        id_concepto=id_concepto,
        nombre=nombre,
        signo=signo,
        es_sistema=False,
        activo=activo,
        aplica_a="AMBOS",
    )
    db.add(obj)
    await db.commit()
    await db.refresh(obj)
    return obj


async def sembrar_catalogo(
    db: AsyncSession, empresa: Empresa
) -> tuple[Categoria, Producto, Almacen]:
    """Categoría + producto con ``es_kardex`` + almacén de la misma empresa."""
    cat = Categoria(
        id_empresa=empresa.id_empresa,
        codigo=f"C-{uuid.uuid4().hex[:6]}",
        nombre="Cemento",
    )
    db.add(cat)
    await db.flush()

    prod = Producto(
        id_empresa=empresa.id_empresa,
        id_categoria=cat.id_categoria,
        codigo=f"P-{uuid.uuid4().hex[:6]}",
        nombre="Cemento Tipo I",
        unidad_medida="KG",
        es_kardex=True,
        activo=True,
    )
    db.add(prod)

    alm = Almacen(
        id_empresa=empresa.id_empresa,
        codigo=f"A-{uuid.uuid4().hex[:6]}",
        nombre="Silo Principal",
    )
    db.add(alm)
    await db.commit()
    await db.refresh(cat)
    await db.refresh(prod)
    await db.refresh(alm)
    return cat, prod, alm

"""Pruebas de la API de Vínculos Báscula-Indicador (FastAPI).

Verifica:
- Creación de vínculos válidos.
- Rechazo si la báscula ya tiene un vínculo activo (400).
- Respeto y reutilización ante uq_vinculo_bascula si estaba inactivo.
- Listado filtrado por empresa (multi-tenant).
- Eliminación del vínculo (DELETE).
- Aislamiento multi-empresa (404 al intentar operar sobre báscula o vínculo ajeno).
"""

from __future__ import annotations

import uuid

import httpx
import pytest_asyncio
from fastapi import FastAPI

from app.api.dependencies import get_current_empresa, get_current_user
from app.api.v1.endpoints import API_ROUTERS
from app.core.database import get_db
from app.models import Balanza, Empresa, Indicador, Usuario, VinculoBalanzaIndicador


def _app_para(db, user: Usuario, empresa: Empresa) -> FastAPI:
    application = FastAPI()
    for router in API_ROUTERS:
        application.include_router(router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    application.dependency_overrides[get_current_user] = lambda: user
    application.dependency_overrides[get_current_empresa] = lambda: empresa
    return application


@pytest_asyncio.fixture
async def admin(db, empresa):
    user = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Vinculos",
        email=f"admin-vin-{uuid.uuid4().hex[:6]}@demo.com",
        password_hash="pass",
        rol="ADMIN",
        activo=True,
    )
    db.add(user)
    await db.commit()
    return user


@pytest_asyncio.fixture
async def app(db, admin, empresa):
    return _app_para(db, admin, empresa)


@pytest_asyncio.fixture
async def client(app):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


async def _crear_balanza(db, empresa, desc="Báscula Test") -> Balanza:
    b = Balanza(
        id_empresa=empresa.id_empresa,
        descripcion=desc,
        capacidad_max=50000,
        division=10,
        puerto_com="/dev/ttyUSB0",
        activo=True,
    )
    db.add(b)
    await db.commit()
    await db.refresh(b)
    return b


async def _crear_indicador(db, empresa, desc="Indicador Test") -> Indicador:
    ind = Indicador(
        id_empresa=empresa.id_empresa,
        descripcion=desc,
        protocolo="CONTINUO",
        puerto_com="/dev/ttyUSB1",
        baudrate=9600,
        activo=True,
    )
    db.add(ind)
    await db.commit()
    await db.refresh(ind)
    return ind


class TestVinculosApi:
    async def test_crear_vinculo_exitoso(self, client, db, empresa):
        bal = await _crear_balanza(db, empresa)
        ind = await _crear_indicador(db, empresa)

        payload = {
            "id_bascula": str(bal.id_balanza),
            "id_indicador": str(ind.id_indicador),
        }
        r = await client.post("/api/v1/vinculos", json=payload)
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["id_bascula"] == str(bal.id_balanza)
        assert data["id_indicador"] == str(ind.id_indicador)
        assert data["activo"] is True

    async def test_crear_vinculo_mismo_bascula_no_colisiona_uq(self, client, db, empresa):
        bal = await _crear_balanza(db, empresa)
        ind1 = await _crear_indicador(db, empresa, desc="Ind 1")
        ind2 = await _crear_indicador(db, empresa, desc="Ind 2")

        # Primer vínculo
        r1 = await client.post("/api/v1/vinculos", json={
            "id_bascula": str(bal.id_balanza),
            "id_indicador": str(ind1.id_indicador),
        })
        assert r1.status_code == 200
        id_vinc1 = r1.json()["id_vinculo"]

        # Segundo vínculo con la misma báscula mientras está activo -> rechaza con 400
        r_dupl = await client.post("/api/v1/vinculos", json={
            "id_bascula": str(bal.id_balanza),
            "id_indicador": str(ind2.id_indicador),
        })
        assert r_dupl.status_code == 400
        assert "ya tiene un indicador vinculado" in r_dupl.json()["detail"]

        # Marcar inactivo directamente en BD para probar reutilización ante uq_vinculo_bascula
        from sqlalchemy import select
        res_v = await db.execute(
            select(VinculoBalanzaIndicador).where(
                VinculoBalanzaIndicador.id_vinculo == uuid.UUID(id_vinc1)
            )
        )
        vinc_obj = res_v.scalar_one()
        vinc_obj.activo = False
        await db.commit()

        # Re-enlazar con nuevo indicador: debe reutilizar la fila sin violar uq_vinculo_bascula
        r2 = await client.post("/api/v1/vinculos", json={
            "id_bascula": str(bal.id_balanza),
            "id_indicador": str(ind2.id_indicador),
        })
        assert r2.status_code == 200, f"No debe fallar por uq_vinculo_bascula: {r2.text}"
        data = r2.json()
        assert data["id_vinculo"] == id_vinc1  # Misma fila reutilizada
        assert data["id_indicador"] == str(ind2.id_indicador)
        assert data["id_bascula"] == str(bal.id_balanza)
        assert data["activo"] is True

    async def test_listar_vinculos_empresa(self, client, db, empresa):
        bal = await _crear_balanza(db, empresa)
        ind = await _crear_indicador(db, empresa)
        await client.post("/api/v1/vinculos", json={
            "id_bascula": str(bal.id_balanza),
            "id_indicador": str(ind.id_indicador),
        })

        r = await client.get("/api/v1/vinculos")
        assert r.status_code == 200
        lista = r.json()
        assert len(lista) == 1
        assert lista[0]["id_bascula"] == str(bal.id_balanza)

    async def test_eliminar_vinculo(self, client, db, empresa):
        bal = await _crear_balanza(db, empresa)
        ind = await _crear_indicador(db, empresa)
        r_create = await client.post("/api/v1/vinculos", json={
            "id_bascula": str(bal.id_balanza),
            "id_indicador": str(ind.id_indicador),
        })
        id_vinculo = r_create.json()["id_vinculo"]

        r_del = await client.delete(f"/api/v1/vinculos/{id_vinculo}")
        assert r_del.status_code == 200
        assert r_del.json()["ok"] is True

        # Verificar que ya no está en el listado
        r_list = await client.get("/api/v1/vinculos")
        assert r_list.status_code == 200
        assert len(r_list.json()) == 0

    async def test_aislamiento_otra_empresa_da_404(self, client, db, empresa):
        otra = Empresa(
            nombre_fiscal=f"Otra Corp {uuid.uuid4().hex[:6]}",
            rif_nit=f"J-{uuid.uuid4().hex[:10]}",
        )
        db.add(otra)
        await db.commit()
        await db.refresh(otra)

        bal_ajena = await _crear_balanza(db, otra, desc="Báscula Ajena")
        ind = await _crear_indicador(db, empresa)

        # Intentar vincular báscula ajena
        r = await client.post("/api/v1/vinculos", json={
            "id_bascula": str(bal_ajena.id_balanza),
            "id_indicador": str(ind.id_indicador),
        })
        assert r.status_code == 404

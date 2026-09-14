"""Pruebas del flujo de recuperación de contraseña (forgot/reset)."""

from __future__ import annotations

from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta

import httpx
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import select

from app.api.v1.endpoints.auth import router as auth_router
from app.core.database import get_db
from app.core.security import hash_password, verify_password
from app.models import PasswordResetToken, Usuario
from app.services.password_reset_service import _hash_token


@pytest_asyncio.fixture
async def app(db, empresa) -> FastAPI:
    usuario = Usuario(
        id_empresa=empresa.id_empresa,
        nombre="Admin Reset",
        email="reset@test.demo",
        password_hash=hash_password("viejacontrasena"),
        rol="ADMIN",
        activo=True,
    )
    db.add(usuario)
    await db.commit()
    await db.refresh(usuario)

    application = FastAPI()
    application.include_router(auth_router)

    async def _get_db():
        yield db

    application.dependency_overrides[get_db] = _get_db
    return application


@pytest_asyncio.fixture
async def client(app) -> AsyncGenerator[httpx.AsyncClient, None]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


async def _get_usuario(db) -> Usuario:
    return (
        await db.execute(select(Usuario).where(Usuario.email == "reset@test.demo"))
    ).scalar_one()


def _add_token(db, usuario: Usuario, token: str, *, minutos: int = 10, usado: bool = False) -> None:
    db.add(
        PasswordResetToken(
            id_usuario=usuario.id_usuario,
            token_hash=_hash_token(token),
            expira=datetime.now(UTC).replace(tzinfo=None) + timedelta(minutes=minutos),
            usado=usado,
        )
    )


class TestForgotPassword:
    async def test_solicitud_responde_200_sin_revelar_email(self, client):
        r = await client.post(
            "/api/v1/auth/forgot-password", json={"email": "noexiste@test.demo"}
        )
        assert r.status_code == 200, r.text
        assert r.json()["message"]

    async def test_forgot_crea_token_hash_en_bd(self, client, db):
        r = await client.post(
            "/api/v1/auth/forgot-password", json={"email": "reset@test.demo"}
        )
        assert r.status_code == 200, r.text

        tokens = (
            await db.execute(
                select(PasswordResetToken).where(
                    PasswordResetToken.id_usuario == (await _get_usuario(db)).id_usuario
                )
            )
        ).scalars().all()
        assert len(tokens) == 1
        # Nunca se guarda el token en claro: solo su hash SHA-256 (64 hex)
        assert len(tokens[0].token_hash) == 64
        assert tokens[0].expira > datetime.now(UTC).replace(tzinfo=None)


class TestResetPassword:
    async def test_reset_con_token_valido(self, client, db):
        usuario = await _get_usuario(db)
        _add_token(db, usuario, "tok-valido")
        await db.commit()

        r = await client.post(
            "/api/v1/auth/reset-password",
            json={"token": "tok-valido", "new_password": "nuevacontrasena123"},
        )
        assert r.status_code == 200, r.text

        await db.refresh(usuario)
        assert verify_password("nuevacontrasena123", usuario.password_hash)

        # El token es de un solo uso
        r2 = await client.post(
            "/api/v1/auth/reset-password",
            json={"token": "tok-valido", "new_password": "otravez123"},
        )
        assert r2.status_code == 400

    async def test_reset_token_expirado_400(self, client, db):
        usuario = await _get_usuario(db)
        _add_token(db, usuario, "tok-vencido", minutos=-1)
        await db.commit()

        r = await client.post(
            "/api/v1/auth/reset-password",
            json={"token": "tok-vencido", "new_password": "nueva123456"},
        )
        assert r.status_code == 400

    async def test_reset_token_desconocido_400(self, client):
        r = await client.post(
            "/api/v1/auth/reset-password",
            json={"token": "token-inexistente", "new_password": "nueva123456"},
        )
        assert r.status_code == 400
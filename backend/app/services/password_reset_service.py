"""Servicio de recuperación de contraseña.

Genera tokens aleatorios de un solo uso; en BD solo se almacena su hash
SHA-256. El enlace se envía por correo si SMTP está configurado; en
desarrollo se registra en el log para permitir pruebas sin servidor de correo.
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import secrets
import smtplib
import ssl
from datetime import UTC, datetime, timedelta
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import hash_password
from app.models import PasswordResetToken, Usuario

logger = logging.getLogger(__name__)


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _enviar_email(destinatario: str, reset_link: str) -> None:
    """Envía el correo con el enlace de restablecimiento (bloqueante)."""
    if not settings.smtp_enabled:
        logger.info("SMTP deshabilitado. Enlace de restablecimiento: %s", reset_link)
        return

    if not settings.smtp_user or not settings.smtp_password:
        logger.warning(
            "SMTP habilitado pero faltan credenciales. Enlace: %s", reset_link
        )
        return

    message = MIMEMultipart("alternative")
    message["Subject"] = "BALANSOFT-WS — Restablecer contraseña"
    message["From"] = settings.smtp_from or settings.smtp_user
    message["To"] = destinatario

    texto = (
        f"Recibimos una solicitud para restablecer tu contraseña.\n\n"
        f"Abre el siguiente enlace (válido por "
        f"{settings.password_reset_expire_minutes} minutos):\n\n{reset_link}\n\n"
        f"Si no solicitaste este cambio, ignora este mensaje."
    )
    html = (
        f"<p>Recibimos una solicitud para restablecer tu contraseña.</p>"
        f'<p>Abre el siguiente enlace (válido por '
        f'{settings.password_reset_expire_minutes} minutos):</p>'
        f'<p><a href="{reset_link}">{reset_link}</a></p>'
        f"<p>Si no solicitaste este cambio, ignora este mensaje.</p>"
    )
    message.attach(MIMEText(texto, "plain"))
    message.attach(MIMEText(html, "html"))

    context = ssl.create_default_context()
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as server:
        server.starttls(context=context)
        server.login(settings.smtp_user, settings.smtp_password)
        server.sendmail(message["From"], [destinatario], message.as_string())


async def crear_token_reset(db: AsyncSession, usuario: Usuario) -> str:
    """Invalida tokens previos no usados y crea uno nuevo.

    Devuelve el token en claro (debe entregarse solo al dueño del correo).
    """
    # Invalidar tokens anteriores no usados
    anteriores = (
        await db.execute(
            select(PasswordResetToken).where(
                PasswordResetToken.id_usuario == usuario.id_usuario,
                PasswordResetToken.usado.is_(False),
            )
        )
    ).scalars().all()
    for token_old in anteriores:
        token_old.usado = True

    token = secrets.token_urlsafe(32)
    expires = datetime.now(UTC).replace(tzinfo=None) + timedelta(
        minutes=settings.password_reset_expire_minutes
    )
    db.add(
        PasswordResetToken(
            id_usuario=usuario.id_usuario,
            token_hash=_hash_token(token),
            expira=expires,
        )
    )
    await db.commit()
    return token


def build_reset_link(token: str) -> str:
    base = settings.password_reset_url_base.rstrip("/")
    return f"{base}?token={token}"


async def solicitar_reset_pwd(db: AsyncSession, email: str) -> None:
    """Proceso completo de solicitud: crea el token y envía el correo.

    No revela si el correo existe (respuesta uniforme 200).
    """
    usuario = (
        await db.execute(select(Usuario).where(Usuario.email == email.lower()))
    ).scalar_one_or_none()
    if usuario is None or not usuario.activo:
        return

    token = await crear_token_reset(db, usuario)
    await asyncio.to_thread(_enviar_email, usuario.email, build_reset_link(token))


async def reset_pwd(db: AsyncSession, token: str, new_password: str) -> bool:
    """Aplica un nuevo password si el token es válido y no está vencido."""
    registro = (
        await db.execute(
            select(PasswordResetToken).where(
                PasswordResetToken.token_hash == _hash_token(token)
            )
        )
    ).scalar_one_or_none()
    if registro is None or registro.usado:
        return False
    if registro.expira < datetime.now(UTC).replace(tzinfo=None):
        return False

    usuario = (
        await db.execute(
            select(Usuario).where(Usuario.id_usuario == registro.id_usuario)
        )
    ).scalar_one_or_none()
    if usuario is None:
        return False

    usuario.password_hash = hash_password(new_password)
    registro.usado = True
    await db.commit()
    return True
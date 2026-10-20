"""Servicio de llaves de activación (un solo uso) para estaciones OPERADOR.

El ADMIN de la cuenta emite, desde la estación titular, una llave para un
usuario local. El instalador de la estación cliente (OPERADOR, cliente delgado
sin WServer ni BD propios) la canjea **una única vez** contra la API del
titular; si el canje no valida, ese equipo no queda autorizado a operar.

Decisiones de diseño:

- El código se guarda **hasheado** (SHA-256), nunca en claro. Al emitirlo se
  devuelve una sola vez junto con un ``codigo_preview`` (últimos 6 caracteres)
  para que el ADMIN lo reconozca en la lista.
- El alfabeto **excluye** `0/O` y `1/I`: son caracteres que el operador confunde
  al teclearlos en una estación de pesaje.
- **Una sola llave activa por usuario**: emitir una nueva revoca la anterior
  (``estado='revocada'``). Es la lectura de "un solo uso por usuario".
- El canje lee la fila con ``FOR UPDATE``: dos instaladores simultáneos con el
  mismo código no pueden consumirlo dos veces (idempotencia de un solo uso).
- Al consumirse, la cuenta recibe una notificación con las sesiones
  usadas/disponibles, para que el dueño sepa que su código se utilizó.

Versión: 0.4.2-dev.56
Fecha: 2026-10-19
Estado: Vigente
Norma: ISO/IEC 27001 / ISO/IEC 25010
Fuente: Sistema BALANSOFT-WS
Autor: Lead Architect
"""

from __future__ import annotations

import hashlib
import logging
import secrets
import string
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Empresa,
    IdentidadLocal,
    LlaveActivacion,
    Usuario,
)
from app.services.notification_service import (
    crear_notificacion,
    despachar_os_pendientes,
)

log = logging.getLogger(__name__)

ESTADO_ACTIVA = "activa"
ESTADO_CONSUMIDA = "consumida"
ESTADO_REVOCADA = "revocada"

#: Alfabeto sin caracteres ambiguos (0/O, 1/I) para tecleo en estación.
_ALFABETO = "".join(c for c in string.ascii_uppercase + string.digits if c not in "0O1I")

#: Caducidad por defecto: una semana. La llave se comparte fuera de banda
#: (correo/WhatsApp) y el empleado puede instalar su estación días después; el
#: ADMIN puede pedir otra vigencia con ``expira_horas`` (1 h … 90 días).
_EXPIRA_HORAS_DEFAULT = 24 * 7
_EXPIRA_HORAS_MAX = 24 * 90


def _ahora() -> datetime:
    """UTC naive: la convención de los ``TIMESTAMP`` del proyecto."""
    return datetime.now(UTC).replace(tzinfo=None)


def generar_codigo() -> str:
    """Código ``BS-XXXX-XXXX-XXXX`` (12 caracteres útiles, ~10^19 combinaciones)."""
    bloques = ["".join(secrets.choice(_ALFABETO) for _ in range(4)) for _ in range(3)]
    return "-".join(["BS", *bloques])


def hash_codigo(codigo: str) -> str:
    """SHA-256 del código normalizado (sin espacios y en mayúsculas)."""
    return hashlib.sha256(normalizar_codigo(codigo).encode("utf-8")).hexdigest()


def normalizar_codigo(codigo: str) -> str:
    """El operador puede teclear espacios o minúsculas: se toleran ambos."""
    return "".join(codigo.split()).upper()


def limite_sesiones_por_tier(tier: str | None) -> int | None:
    """Límite de sesiones del tier (``None`` = sin límite).

    Solo DEMO limita (3). Cualquier otro tier —CENTRAL y los planes
    Básico/Premium que emita el LM— no impone tope funcional local: la
    concurrencia real la fija la licencia del LM/central
    (``licencias.max_sesiones``).
    """
    return 3 if (tier or "").upper() == "DEMO" else None


async def crear_llave(
    db: AsyncSession,
    *,
    empresa: Empresa,
    admin: Usuario,
    id_usuario: uuid.UUID,
    expira_horas: int | None = _EXPIRA_HORAS_DEFAULT,
) -> tuple[LlaveActivacion, str]:
    """Emite una llave para ``id_usuario`` (debe ser de ``empresa``).

    Devuelve ``(llave, codigo)``; el código en claro **no** se persiste.
    """
    usuario = (
        await db.execute(
            select(Usuario).where(
                Usuario.id_usuario == id_usuario,
                Usuario.id_empresa == empresa.id_empresa,
            )
        )
    ).scalar_one_or_none()
    if usuario is None:
        # Aislamiento multi-tenant: un usuario de otra empresa es "no existe".
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El usuario no existe en esta empresa",
        )

    horas = _EXPIRA_HORAS_DEFAULT if expira_horas is None else int(expira_horas)
    if not 1 <= horas <= _EXPIRA_HORAS_MAX:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"expira_horas debe estar entre 1 y {_EXPIRA_HORAS_MAX}",
        )

    ahora = _ahora()

    # "Un solo uso por usuario": una única llave activa a la vez.
    previas = (
        (
            await db.execute(
                select(LlaveActivacion).where(
                    LlaveActivacion.id_usuario == usuario.id_usuario,
                    LlaveActivacion.estado == ESTADO_ACTIVA,
                )
            )
        )
        .scalars()
        .all()
    )
    for previa in previas:
        previa.estado = ESTADO_REVOCADA
        previa.updated_at = ahora

    codigo = generar_codigo()
    llave = LlaveActivacion(
        id_empresa=empresa.id_empresa,
        id_usuario=usuario.id_usuario,
        codigo_hash=hash_codigo(codigo),
        codigo_preview=codigo[-6:],
        estado=ESTADO_ACTIVA,
        expira_en=ahora + timedelta(hours=horas),
        creado_por=admin.id_usuario,
        created_at=ahora,
        updated_at=ahora,
    )
    db.add(llave)
    await db.commit()
    await db.refresh(llave)
    return llave, codigo


async def validar_y_consumir(
    db: AsyncSession,
    *,
    codigo: str,
    hardware_id: str | None = None,
    ip: str | None = None,
    user_agent: str | None = None,
) -> tuple[LlaveActivacion, Usuario, Empresa]:
    """Canjea una llave activa y la marca consumida (una sola vez).

    Endpoint público (lo llama el instalador antes de existir sesión): el
    tenant lo determina la propia llave, nunca el cliente.
    """
    limpio = normalizar_codigo(codigo)
    if len(limpio) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Código de activación inválido",
        )

    llave = (
        await db.execute(
            select(LlaveActivacion)
            .where(LlaveActivacion.codigo_hash == hash_codigo(limpio))
            .with_for_update()
        )
    ).scalar_one_or_none()
    if llave is None or llave.estado != ESTADO_ACTIVA:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Código de activación inválido o ya utilizado",
        )
    if llave.expira_en is not None and llave.expira_en < _ahora():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El código de activación expiró",
        )

    usuario = await db.get(Usuario, llave.id_usuario)
    empresa = await db.get(Empresa, llave.id_empresa)
    if usuario is None or empresa is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Código de activación inválido",
        )

    ahora = _ahora()
    llave.estado = ESTADO_CONSUMIDA
    llave.consumida_en = ahora
    llave.consumida_por_hw = (hardware_id or "")[:255] or None
    llave.ip_consumo = (ip or "")[:45] or None
    llave.user_agent = (user_agent or "")[:255] or None
    llave.updated_at = ahora

    # Flush para que el conteo de sesiones incluya este consumo.
    await db.flush()
    await _notificar_activacion(db, empresa, usuario, llave, hardware_id)
    await db.commit()
    await db.refresh(llave)
    # Despacho inmediato al SO (post-commit, best-effort) para que el toast
    # aparezca en el instante del consumo, aunque el scheduler aún no corrió.
    try:
        from app.core.database import AsyncSessionLocal

        async with AsyncSessionLocal() as db_os:
            await despachar_os_pendientes(db_os, limit=20)
            await db_os.commit()
    except Exception as exc:  # noqa: BLE001 - best-effort
        log.debug("No se pudo despachar notificación OS post-commit al consumir llave: %s", exc)
    return llave, usuario, empresa


async def _notificar_activacion(
    db: AsyncSession,
    empresa: Empresa,
    usuario: Usuario,
    llave: LlaveActivacion,
    hardware_id: str | None,
) -> None:
    """Aviso al dueño: su código se usó y quedan ``x/y`` sesiones.

    ``dedup_key`` ligado al id de la llave: re-procesar la misma activación no
    duplica el aviso (idempotencia de la notificación).
    """
    usadas = (
        await db.scalar(
            select(func.count())
            .select_from(LlaveActivacion)
            .where(
                LlaveActivacion.id_empresa == empresa.id_empresa,
                LlaveActivacion.estado == ESTADO_CONSUMIDA,
            )
        )
        or 0
    )
    identidad = (await db.execute(select(IdentidadLocal))).scalar_one_or_none()
    tier = (identidad.licencia_tier if identidad else None) or empresa.licencia_tier
    limite = limite_sesiones_por_tier(tier)
    if limite is None:
        sesiones = f"{usadas} sesiones usadas (el plan no impone límite)"
    else:
        restantes = max(limite - usadas, 0)
        sesiones = f"quedan {restantes}/{limite} sesiones"

    mensaje = (
        f"El usuario {usuario.email} activó un equipo con una llave de su cuenta"
        f"{f' (hardware: {hardware_id})' if hardware_id else ''}. "
        f"Quedan registradas {sesiones}."
    )
    # Por el helper y no con un ``Notificacion(...)`` a mano: la tabla tiene
    # ``uq_notificaciones_empresa_dedup (id_empresa, dedup_key)``, así que un
    # INSERT directo de un dedup repetido reventaría la transacción del canje.
    # ``crear_notificacion`` resuelve el dedup con un SAVEPOINT y devuelve
    # ``None`` sin abortar el canje (esa es la idempotencia que se promete).
    await crear_notificacion(
        db,
        id_empresa=empresa.id_empresa,
        tipo="activacion_equipo",
        severidad="info",
        titulo="Equipo activado con llave de activación",
        mensaje=mensaje,
        origen="evento",
        dedup_key=f"llave_activacion:{llave.id}",
    )
    # Despacho inmediato al SO (best-effort). No debe interrumpir el canje.
    try:
        await despachar_os_pendientes(db, limit=10)
    except Exception as exc:  # noqa: BLE001 - best-effort
        log.debug("No se pudo despachar la notificación OS al consumir llave: %s", exc)

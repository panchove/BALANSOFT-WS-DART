"""Servicio de sincronización: procesamiento de pesajes offline entrantes."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import BoletoPesaje, Empresa, SyncLog
from app.schemas import SyncResultItem, WeighingSyncItem
from app.services.weighing_service import normalizar_estado


class SyncService:
    async def _asignar_numero_boleto(
        self, db: AsyncSession, pesaje: BoletoPesaje
    ) -> None:
        """Genera numero_boleto (TA-XXXXXX) si el item offline no lo trae."""
        if pesaje.numero_boleto:
            return
        rows = (await db.execute(select(BoletoPesaje.numero_boleto))).scalars().all()
        max_numero = 0
        for numero in rows:
            if numero and "-" in numero:
                try:
                    max_numero = max(max_numero, int(numero.rsplit("-", 1)[1]))
                except (ValueError, IndexError):
                    continue
        digitos = max(settings.boleto_digitos, len(str(max_numero + 1)))
        pesaje.numero_boleto = f"{settings.boleto_prefix}{max_numero + 1:0{digitos}d}"

    async def process_batch(
        self,
        db: AsyncSession,
        empresa: Empresa,
        pesajes: list[WeighingSyncItem],
    ) -> tuple[int, int, list[SyncResultItem]]:
        detalle: list[SyncResultItem] = []
        sincronizados = 0
        errores = 0

        for item in pesajes:
            try:
                boleto_uuid = uuid.UUID(item.boleto)
            except (ValueError, TypeError):
                boleto_uuid = None

            if boleto_uuid is None:
                errores += 1
                detalle.append(SyncResultItem(boleto=item.boleto, ok=False, mensaje="boleto inválido"))
                continue

            # Upsert determinístico por boleto
            existing = (
                await db.execute(
                    select(BoletoPesaje).where(
                        BoletoPesaje.id_empresa == empresa.id_empresa,
                        BoletoPesaje.boleto == boleto_uuid,
                    )
                )
            ).scalar_one_or_none()

            # Estados legacy normalizados a los del spec (PENDIENTE/CERRADO/...)
            estado_norm = normalizar_estado(item.estado_boleto)

            values = {
                "id_vehiculo": item.id_vehiculo,
                "remolque": item.remolque,
                "id_transporte": item.id_transporte,
                "id_conductor": item.id_conductor,
                "id_producto": item.id_producto,
                "id_almacen": item.id_almacen,
                "id_balanza": item.id_balanza,
                "tipo_tercero": item.tipo_tercero,
                "id_tercero": item.id_tercero,
                "multi_despacho_recepcion": item.multi_despacho_recepcion,
                "fecha_hora_entrada": item.fecha_hora_entrada,
                "peso_entrada_vehiculo": item.peso_entrada_vehiculo,
                "peso_entrada_remolque": item.peso_entrada_remolque,
                "fecha_hora_salida": item.fecha_hora_salida,
                "peso_salida_vehiculo": item.peso_salida_vehiculo,
                "peso_salida_remolque": item.peso_salida_remolque,
                "peso_bruto": item.peso_bruto,
                "peso_tara": item.peso_tara,
                "peso_neto": item.peso_neto,
                "diferencia_peso": item.diferencia_peso,
                "porcentaje_diferencia": item.porcentaje_diferencia,
                "densidad": item.densidad,
                "litros": item.litros,
                "unidades": item.unidades,
                "documento": item.documento,
                "flete": item.flete,
                "observaciones": item.observaciones,
                "estado_boleto": estado_norm,
                "sincronizado": True,
                "sync_intentos": 0,
                "updated_at": datetime.now(UTC).replace(tzinfo=None),
            }

            if existing is not None:
                for k, v in values.items():
                    setattr(existing, k, v)
            else:
                nuevo = BoletoPesaje(
                    boleto=boleto_uuid,
                    numero_boleto=item.numero_boleto,
                    id_empresa=empresa.id_empresa,
                    **values,
                )
                if not nuevo.numero_boleto:
                    await self._asignar_numero_boleto(db, nuevo)
                db.add(nuevo)
            sincronizados += 1
            detalle.append(
                SyncResultItem(
                    boleto=item.boleto, ok=True, mensaje="sincronizado"
                )
            )

        await db.commit()
        await self._log(db, empresa, "push", "pesajes", sincronizados, errores)
        await db.commit()
        return sincronizados, errores, detalle

    async def _log(
        self,
        db: AsyncSession,
        empresa: Empresa,
        tipo: str,
        entidad: str,
        registros: int,
        errores: int,
    ) -> None:
        db.add(
            SyncLog(
                id_empresa=empresa.id_empresa,
                tipo=tipo,
                entidad=entidad,
                registros=registros,
                errores=errores,
            )
        )

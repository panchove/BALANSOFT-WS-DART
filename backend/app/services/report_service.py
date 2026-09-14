"""Servicio de reportes estadísticos de pesaje (agregación SQL)."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import case, func, literal_column, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import BoletoPesaje, Empresa, Kardex, Tercero, Transporte


class ReportService:
    async def daily(self, db: AsyncSession, empresa: Empresa, day: date) -> dict:
        start = datetime(day.year, day.month, day.day)
        end = datetime(day.year, day.month, day.day, 23, 59, 59)

        # Base donde (MODEL.md): los ANULADOS no cuentan en ningún reporte
        base = [
            BoletoPesaje.id_empresa == empresa.id_empresa,
            BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
            BoletoPesaje.fecha_hora_entrada >= start,
            BoletoPesaje.fecha_hora_entrada <= end,
        ]
        base_prod = base

        # Agregación SQL para totales
        agg_stmt = select(
            func.count().label("total_pesajes"),
            func.count(case((BoletoPesaje.estado_boleto == "CERRADO", 1))).label("cerrados"),
            func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).label("peso_neto_total"),
        ).where(*base)
        agg = (await db.execute(agg_stmt)).one()

        # Desglose por producto
        prod_stmt = select(
            BoletoPesaje.id_producto,
            func.count().label("cantidad"),
            func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).label("peso_neto"),
        ).where(*base_prod).group_by(BoletoPesaje.id_producto)

        por_producto = [
            {
                "id_producto": str(r.id_producto) if r.id_producto else "SIN_PRODUCTO",
                "cantidad": r.cantidad,
                "peso_neto": float(r.peso_neto),
            }
            for r in (await db.execute(prod_stmt)).all()
        ]

        return {
            "fecha": day.isoformat(),
            "total_pesajes": agg.total_pesajes,
            "cerrados": agg.cerrados,
            "abiertos": agg.total_pesajes - agg.cerrados,
            "peso_neto_total": float(agg.peso_neto_total),
            "por_producto": por_producto,
        }

    async def monthly(self, db: AsyncSession, empresa: Empresa, year: int, month: int) -> dict:
        start = datetime(year, month, 1)
        nxt = datetime(year + 1, 1, 1) if month == 12 else datetime(year, month + 1, 1)

        base = [
            BoletoPesaje.id_empresa == empresa.id_empresa,
            BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
            BoletoPesaje.fecha_hora_entrada >= start,
            BoletoPesaje.fecha_hora_entrada < nxt,
        ]
        agg_stmt = select(
            func.count().label("total"),
            func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).label("peso_total"),
        ).where(*base)
        agg = (await db.execute(agg_stmt)).one()

        # Conteo por día usando SQL
        dia_stmt = select(
            func.date(BoletoPesaje.fecha_hora_entrada).label("fecha"),
            func.count().label("pesajes"),
        ).where(*base).group_by(literal_column("fecha")).order_by(literal_column("fecha"))

        por_dia = [
            {"fecha": str(r.fecha), "pesajes": r.pesajes}
            for r in (await db.execute(dia_stmt)).all()
        ]

        return {
            "periodo": f"{year:04d}-{month:02d}",
            "total_pesajes": agg.total,
            "peso_neto_total": float(agg.peso_total),
            "por_dia": por_dia,
        }

    async def vehicle(
        self,
        db: AsyncSession,
        empresa: Empresa,
        vehicle_id: str,
        date_from: datetime,
        date_to: datetime,
    ) -> dict:
        stmt = select(
            func.count().label("total"),
            func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).label("peso_total"),
            func.coalesce(func.avg(BoletoPesaje.peso_neto), 0).label("peso_promedio"),
        ).where(
            BoletoPesaje.id_empresa == empresa.id_empresa,
            BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
            BoletoPesaje.id_vehiculo == vehicle_id,
            BoletoPesaje.fecha_hora_entrada >= date_from,
            BoletoPesaje.fecha_hora_entrada <= date_to,
        )
        agg = (await db.execute(stmt)).one()

        return {
            "placa": vehicle_id,
            "desde": date_from.isoformat(),
            "hasta": date_to.isoformat(),
            "total_pesajes": agg.total,
            "peso_neto_total": float(agg.peso_total),
            "peso_promedio": float(agg.peso_promedio) if agg.total > 0 else None,
        }

    async def kardex_saldo(
        self,
        db: AsyncSession,
        empresa: Empresa,
        fecha_corte: datetime,
        id_producto: str | None = None,
        id_almacen: str | None = None,
    ) -> dict:
        """Saldo de kardex a fecha de corte (MODEL.md).

        SALDO FINAL = SALDO INICIAL + movimientos 01-49 (positivos)
                      - movimientos 50-99 (negativos), FILTRO A FECHA DE CORTE.
        El ID 10 (INGRESO POR BASCULA) incrementa y el 60 (DESPACHO POR
        BASCULA) decrementa; los ANULADOS se cancelan con su inverso.
        """
        stmt = (
            select(
                func.coalesce(
                    func.sum(
                        case(
                            (Kardex.id_movimiento < Kardex.RANGO_NEGATIVO_DESDE, Kardex.valor),
                            else_=-Kardex.valor,
                        )
                    ),
                    0,
                )
            )
            .where(
                Kardex.id_empresa == empresa.id_empresa,
                Kardex.fecha_kardex <= fecha_corte,
            )
        )
        if id_producto:
            stmt = stmt.where(Kardex.id_producto == id_producto)
        if id_almacen:
            stmt = stmt.where(Kardex.id_almacen == id_almacen)

        saldo = (await db.execute(stmt)).scalar() or 0

        rows = (
            (
                await db.execute(
                    select(
                        Kardex.id_producto,
                        func.coalesce(
                            func.sum(
                                case(
                                    (Kardex.id_movimiento < Kardex.RANGO_NEGATIVO_DESDE, Kardex.valor),
                                    else_=-Kardex.valor,
                                )
                            ),
                            0,
                        ).label("saldo"),
                    )
                    .where(
                        Kardex.id_empresa == empresa.id_empresa,
                        Kardex.fecha_kardex <= fecha_corte,
                    )
                    .group_by(Kardex.id_producto)
                )
            )
            .all()
        )

        return {
            "fecha_corte": fecha_corte.isoformat(),
            "saldo_total": float(saldo),
            "por_producto": [
                {
                    "id_producto": str(r.id_producto) if r.id_producto else "SIN_PRODUCTO",
                    "saldo": float(r.saldo),
                }
                for r in rows
            ],
        }

    async def kardex_detalle(
        self,
        db: AsyncSession,
        empresa: Empresa,
        fecha_desde: datetime,
        fecha_hasta: datetime,
        id_producto: str | None = None,
        id_almacen: str | None = None,
    ) -> dict:
        """Movimientos de Kardex en el rango con saldo acumulado (PRD §9.6).

        El saldo inicial es el acumulado de los movimientos anteriores a
        `fecha_desde`; cada fila acumula su propio signo
        (01-49 positivo, 50-99 negativo). Ordenado por fecha_kardex.
        """
        filtros_previos = [
            Kardex.id_empresa == empresa.id_empresa,
            Kardex.fecha_kardex < fecha_desde,
        ]
        filtros_rango = [
            Kardex.id_empresa == empresa.id_empresa,
            Kardex.fecha_kardex >= fecha_desde,
            Kardex.fecha_kardex <= fecha_hasta,
        ]
        if id_producto:
            filtros_previos.append(Kardex.id_producto == id_producto)
            filtros_rango.append(Kardex.id_producto == id_producto)
        if id_almacen:
            filtros_previos.append(Kardex.id_almacen == id_almacen)
            filtros_rango.append(Kardex.id_almacen == id_almacen)

        _signed = case(
            (Kardex.id_movimiento < Kardex.RANGO_NEGATIVO_DESDE, Kardex.valor),
            else_=-Kardex.valor,
        )
        saldo_inicial = (
            await db.execute(
                select(func.coalesce(func.sum(_signed), 0)).where(*filtros_previos)
            )
        ).scalar() or 0

        rows = (
            await db.execute(
                select(Kardex)
                .where(*filtros_rango)
                .order_by(Kardex.fecha_kardex, Kardex.id_kardex)
            )
        ).scalars().all()

        movimientos: list[dict] = []
        acumulado = Decimal(saldo_inicial)
        for k in rows:
            signo = 1 if k.id_movimiento < Kardex.RANGO_NEGATIVO_DESDE else -1
            valor_saldo = Decimal(k.valor) * signo
            acumulado += valor_saldo
            movimientos.append(
                {
                    "id_kardex": str(k.id_kardex),
                    "fecha": k.fecha_kardex.isoformat(),
                    "id_movimiento": k.id_movimiento,
                    "id_producto": str(k.id_producto) if k.id_producto else "SIN_PRODUCTO",
                    "id_almacen": str(k.id_almacen) if k.id_almacen else "SIN_ALMACEN",
                    "documento": k.documento,
                    "boleto": str(k.boleto) if k.boleto else None,
                    "valor": float(abs(Decimal(k.valor))),
                    "stock": float(acumulado),
                }
            )

        return {
            "fecha_desde": fecha_desde.isoformat(),
            "fecha_hasta": fecha_hasta.isoformat(),
            "saldo_inicial": float(saldo_inicial),
            "saldo_actual": float(acumulado),
            "movimientos": movimientos,
        }

    async def transportista(
        self,
        db: AsyncSession,
        empresa: Empresa,
        fecha_desde: datetime,
        fecha_hasta: datetime,
    ) -> dict:
        """Ranking de transportistas por volumen movilizado en el rango."""
        stmt = (
            select(
                BoletoPesaje.id_transporte,
                Transporte.razon_social,
                func.count().label("total_pesajes"),
                func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).label("peso_neto_total"),
                func.coalesce(func.avg(BoletoPesaje.peso_neto), 0).label("peso_promedio"),
            )
            .outerjoin(
                Transporte,
                Transporte.id_transporte == BoletoPesaje.id_transporte,
            )
            .where(
                BoletoPesaje.id_empresa == empresa.id_empresa,
                BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
                BoletoPesaje.fecha_hora_entrada >= fecha_desde,
                BoletoPesaje.fecha_hora_entrada <= fecha_hasta,
                BoletoPesaje.id_transporte.isnot(None),
            )
            .group_by(BoletoPesaje.id_transporte, Transporte.razon_social)
            .order_by(func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).desc())
        )
        rows = (await db.execute(stmt)).all()
        return {
            "desde": fecha_desde.isoformat(),
            "hasta": fecha_hasta.isoformat(),
            "total_transportistas": len(rows),
            "transportistas": [
                {
                    "id_transporte": str(r.id_transporte),
                    "razon_social": r.razon_social,
                    "total_pesajes": r.total_pesajes,
                    "peso_neto_total": float(r.peso_neto_total),
                    "peso_promedio": float(r.peso_promedio)
                    if r.total_pesajes > 0
                    else None,
                }
                for r in rows
            ],
        }

    async def tercero(
        self,
        db: AsyncSession,
        empresa: Empresa,
        fecha_desde: datetime,
        fecha_hasta: datetime,
        tipo_tercero: str | None = None,
    ) -> dict:
        """Volumen por cliente/proveedor (tercero) en el rango."""
        filtros = [
            BoletoPesaje.id_empresa == empresa.id_empresa,
            BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
            BoletoPesaje.fecha_hora_entrada >= fecha_desde,
            BoletoPesaje.fecha_hora_entrada <= fecha_hasta,
            BoletoPesaje.id_tercero.isnot(None),
        ]
        if tipo_tercero:
            filtros.append(BoletoPesaje.tipo_tercero == tipo_tercero.upper())
        stmt = (
            select(
                BoletoPesaje.id_tercero,
                Tercero.razon_social,
                BoletoPesaje.tipo_tercero,
                func.count().label("total_pesajes"),
                func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).label("peso_neto_total"),
            )
            .outerjoin(Tercero, Tercero.id_tercero == BoletoPesaje.id_tercero)
            .where(*filtros)
            .group_by(
                BoletoPesaje.id_tercero,
                Tercero.razon_social,
                BoletoPesaje.tipo_tercero,
            )
            .order_by(func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).desc())
        )
        rows = (await db.execute(stmt)).all()
        return {
            "desde": fecha_desde.isoformat(),
            "hasta": fecha_hasta.isoformat(),
            "tipo_tercero": tipo_tercero,
            "total_terceros": len(rows),
            "terceros": [
                {
                    "id_tercero": str(r.id_tercero),
                    "razon_social": r.razon_social,
                    "tipo_tercero": r.tipo_tercero,
                    "total_pesajes": r.total_pesajes,
                    "peso_neto_total": float(r.peso_neto_total),
                }
                for r in rows
            ],
        }

    async def peso_rango(
        self,
        db: AsyncSession,
        empresa: Empresa,
        fecha_desde: datetime,
        fecha_hasta: datetime,
    ) -> dict:
        """Distribución de pesos netos por bucket (SIN_PESO cuando no aplica)."""
        bucket = case(
            (BoletoPesaje.peso_neto <= 0, "SIN_PESO"),
            (BoletoPesaje.peso_neto <= 1000, "0-1t"),
            (BoletoPesaje.peso_neto <= 5000, "1-5t"),
            (BoletoPesaje.peso_neto <= 10000, "5-10t"),
            (BoletoPesaje.peso_neto <= 20000, "10-20t"),
            (BoletoPesaje.peso_neto <= 40000, "20-40t"),
            else_="40t+",
        )
        stmt = (
            select(
                bucket.label("rango"),
                func.count().label("cantidad"),
                func.coalesce(func.sum(BoletoPesaje.peso_neto), 0).label("peso_total"),
            )
            .where(
                BoletoPesaje.id_empresa == empresa.id_empresa,
                BoletoPesaje.estado_boleto != BoletoPesaje.ESTADO_ANULADO,
                BoletoPesaje.estado_boleto == BoletoPesaje.ESTADO_CERRADO,
                BoletoPesaje.fecha_hora_entrada >= fecha_desde,
                BoletoPesaje.fecha_hora_entrada <= fecha_hasta,
            )
            .group_by("rango")
            .order_by(func.min(BoletoPesaje.peso_neto))
        )
        rows = (await db.execute(stmt)).all()
        orden = ["SIN_PESO", "0-1t", "1-5t", "5-10t", "10-20t", "20-40t", "40t+"]
        _buckets = {r.rango: r for r in rows}
        total_pesajes = sum(r.cantidad for r in rows)
        return {
            "desde": fecha_desde.isoformat(),
            "hasta": fecha_hasta.isoformat(),
            "total_pesajes": total_pesajes,
            "rangos": [
                {
                    "rango": rango,
                    "cantidad": _buckets[rango].cantidad if rango in _buckets else 0,
                    "peso_total": float(_buckets[rango].peso_total)
                    if rango in _buckets
                    else 0.0,
                }
                for rango in orden
            ],
        }

    async def comparativo_mensual(
        self,
        db: AsyncSession,
        empresa: Empresa,
        year: int,
        month: int,
    ) -> dict:
        """Comparativo mes actual vs. mes anterior (PRD §9)."""
        if not (1 <= month <= 12):
            raise ValueError("Mes inválido")
        actual = await self.monthly(db, empresa, year, month)
        año_ant, mes_ant = (year - 1, 12) if month == 1 else (year, month - 1)
        anterior = await self.monthly(db, empresa, año_ant, mes_ant)

        def var_pct(a: float, b: float) -> float | None:
            if b == 0:
                return None if a == 0 else 100.0
            return round((a - b) / b * 100, 2)

        peso_a = actual["peso_neto_total"]
        peso_b = anterior["peso_neto_total"]
        cant_a = actual["total_pesajes"]
        cant_b = anterior["total_pesajes"]
        return {
            "mes_actual": actual["periodo"],
            "mes_anterior": anterior["periodo"],
            "actual": {
                "total_pesajes": cant_a,
                "peso_neto_total": peso_a,
            },
            "anterior": {
                "total_pesajes": cant_b,
                "peso_neto_total": peso_b,
            },
            "variacion_pesajes": var_pct(float(cant_a), float(cant_b)),
            "variacion_peso": var_pct(float(peso_a), float(peso_b)),
        }

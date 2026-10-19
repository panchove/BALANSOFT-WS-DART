"""Semilla inicial de catálogos para una empresa recién creada (REQ-FN-023).

Cuando una empresa nueva arranca por primera vez (por ``/register``,
``/login-central`` con espejo local o un login local posterior), el sistema
siembra un catálogo base de categorías, productos y un almacén principal para
que la estación quede operativa de inmediato, sin depender de conexión con el
servidor central.

Reglas (acordadas con PLANIFICADOR/VERIFICADOR):

- Solo aplica cuando la empresa **no tiene ningún catálogo** (0 categorías,
  0 productos y 0 almacenes). Si el operador ya cargó datos, no se toca nada.
- Los productos sembrados llevan ``es_kardex=True`` y existe el almacén
  ``PRINCIPAL`` (código ``ALM01``) para que la generación automática de
  movimientos Kardex tenga coherencia de inventario.
- La siembra es idempotente: una segunda llamada no duplica registros.
- Multi-tenant: todo se crea con el ``id_empresa`` del contexto autenticado
  (nunca del body). Solo aplica en el rol ``local`` (estación).
- ORM exclusivamente (cross-dialecto PostgreSQL/SQL Server, Fase 1-2).
"""

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime
from decimal import Decimal

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Almacen, Categoria, Empresa, Producto

logger = logging.getLogger(__name__)

#: Código del almacén principal sembrado.
ALMACEN_PRINCIPAL_CODIGO = "ALM01"
ALMACEN_PRINCIPAL_NOMBRE = "PRINCIPAL"

#: Categorías base: (código, nombre).
CATEGORIAS: list[tuple[str, str]] = [
    ("CEMENTO", "Cementos"),
    ("HARINAS", "Harinas"),
    ("GRANOS", "Graneles Agrícolas"),
    ("AGREGADOS", "Agregados y Áridos"),
    ("COMBUSTIBLES", "Combustibles y Lubricantes"),
    ("FERROSOS", "Materiales Ferrosos"),
]

#: Productos base: (código, nombre, código_categoría, unidad, densidad).
PRODUCTOS: list[tuple[str, str, str, str, Decimal]] = [
    ("CEM-GRANEL", "Cemento Tipo I a Granel", "CEMENTO", "TON", Decimal("1.5000")),
    ("CEM-SACOS", "Cemento en Sacos (42.5 kg)", "CEMENTO", "TON", Decimal("1.3000")),
    ("HAR-TRIGO", "Harina de Trigo Industrial", "HARINAS", "TON", Decimal("0.5500")),
    ("HAR-PREMIX", "Harina de Maíz Precocida", "HARINAS", "TON", Decimal("0.5000")),
    ("ARROZ-GRANEL", "Arroz a Granel", "GRANOS", "TON", Decimal("0.7500")),
    ("MAIZ-GRANEL", "Maíz Amarillo a Granel", "GRANOS", "TON", Decimal("0.7200")),
    ("SOYA-GRANEL", "Harina de Soya a Granel", "GRANOS", "TON", Decimal("0.7000")),
    ("GRAVILLA", "Grava Triturada (Árido)", "AGREGADOS", "TON", Decimal("1.6000")),
    ("ARENA-LAV", "Arena Lavada de Río", "AGREGADOS", "TON", Decimal("1.4500")),
    ("GASOIL-DIESEL", "Gasóleo (Diésel) a Granel", "COMBUSTIBLES", "TON", Decimal("0.8500")),
    ("FUEL-OIL", "Fuel Oil a Granel", "COMBUSTIBLES", "TON", Decimal("0.9800")),
    ("ACERO-CORR", "Acero Corrugado de Construcción", "FERROSOS", "TON", Decimal("7.8500")),
]


def _ahora_utc() -> datetime:
    """Timestamp naive UTC igual que los defaults de ``app.models``."""
    return datetime.now(UTC).replace(tzinfo=None)


class SeedResult:
    """Conteos de la siembra aplicada."""

    __slots__ = ("categorias", "productos", "almacenes")

    def __init__(self, categorias: int, productos: int, almacenes: int) -> None:
        self.categorias = categorias
        self.productos = productos
        self.almacenes = almacenes

    def to_dict(self) -> dict:
        return {
            "categorias": self.categorias,
            "productos": self.productos,
            "almacenes": self.almacenes,
        }


class SeedService:
    """Servicio de siembra inicial de catálogos (REQ-FN-023)."""

    @staticmethod
    async def empresa_sin_catalogo(db: AsyncSession, id_empresa: uuid.UUID) -> bool:
        """``True`` si la empresa no tiene categorías, productos ni almacenes."""
        for modelo in (Categoria, Producto, Almacen):
            total = await db.scalar(
                select(func.count()).select_from(modelo).where(modelo.id_empresa == id_empresa)
            )
            if total:
                return False
        return True

    @classmethod
    async def aplicar(cls, db: AsyncSession, empresa: Empresa) -> SeedResult:
        """Aplica la siembra base para una empresa.

        Lanza ``ValueError`` si la empresa ya tiene catálogos (no debe
        sobrescribir la operación existente). El commit lo hace el llamador.
        """
        if not await cls.empresa_sin_catalogo(db, empresa.id_empresa):
            raise ValueError(
                "La empresa ya tiene catálogos cargados; la siembra inicial no aplica."
            )

        ahora = _ahora_utc()

        categorias: dict[str, Categoria] = {}
        for codigo, nombre in CATEGORIAS:
            categoria = Categoria(
                id_categoria=uuid.uuid4(),
                id_empresa=empresa.id_empresa,
                codigo=codigo,
                nombre=nombre,
                activo=True,
                created_at=ahora,
                updated_at=ahora,
            )
            db.add(categoria)
            categorias[codigo] = categoria
        # Necesitamos los ids de categoría para los productos; flush parcial.
        await db.flush()

        for codigo, nombre, codigo_cat, unidad, densidad in PRODUCTOS:
            db.add(
                Producto(
                    id_producto=uuid.uuid4(),
                    id_empresa=empresa.id_empresa,
                    id_categoria=categorias[codigo_cat].id_categoria,
                    codigo=codigo,
                    nombre=nombre,
                    unidad_medida=unidad,
                    densidad_estandar=densidad,
                    es_kardex=True,
                    activo=True,
                    created_at=ahora,
                    updated_at=ahora,
                )
            )

        db.add(
            Almacen(
                id_almacen=uuid.uuid4(),
                id_empresa=empresa.id_empresa,
                codigo=ALMACEN_PRINCIPAL_CODIGO,
                nombre=ALMACEN_PRINCIPAL_NOMBRE,
                activo=True,
                created_at=ahora,
                updated_at=ahora,
            )
        )

        return SeedResult(
            categorias=len(CATEGORIAS), productos=len(PRODUCTOS), almacenes=1
        )

    @classmethod
    async def aplicar_si_aplicable(
        cls, db: AsyncSession, empresa: Empresa
    ) -> SeedResult | None:
        """Aplica la siembra solo si la empresa está vacía; si no, no hace nada.

        Protegido con un SAVEPOINT: si algo falla (BD caída, constraint…), se
        revierte solo la siembra y la transacción del llamador queda intacta
        (sus objetos no se expiran). Nunca lanza hacia arriba.
        """
        try:
            async with db.begin_nested():
                if not await cls.empresa_sin_catalogo(db, empresa.id_empresa):
                    return None
                resultado = await cls.aplicar(db, empresa)
            logger.info(
                "Seed inicial aplicado para empresa %s: %s",
                empresa.id_empresa,
                resultado.to_dict(),
            )
            return resultado
        except Exception:
            logger.exception(
                "Error aplicando seed inicial para empresa %s", empresa.id_empresa
            )
            return None

    @classmethod
    async def sembrar_si_aplicable(
        cls, db: AsyncSession, empresa: Empresa
    ) -> bool:
        """Siembra y confirma en una llamada 100 % protegida (REQ-FN-023).

        Pensado para los hooks de ``auth`` (register, login, login-central,
        login-local): un fallo de siembra **nunca** rompe el login/registro ni
        deja la sesión del llamador inconsistente (la siembra usa un SAVEPOINT,
        ver ``aplicar_si_aplicable``; no se hace ``rollback`` de la transacción
        del llamador, que expiraría sus objetos). Devuelve ``True`` solo si
        aplicó y confirmó; ante cualquier error devuelve ``False`` sin
        propagar excepciones.
        """
        resultado = await cls.aplicar_si_aplicable(db, empresa)
        if resultado is None:
            return False
        try:
            await db.commit()
            return True
        except Exception:
            logger.exception(
                "Error confirmando seed inicial para empresa %s", empresa.id_empresa
            )
            return False
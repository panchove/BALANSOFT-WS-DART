"""Respaldos de estación (REQ-NF-BKP-001/002/003).

Snapshot portable en JSON comprimido (gzip) del catálogo + operativo de una
empresa. Reglas acordadas con PLANIFICADOR/VERIFICADOR:

- **Alcance v1**: catálogo + operativo tenant-scoped. El snapshot **no**
  incluye ``empresas``, ``usuarios``, hashes ni credenciales; el manifiesto
  solo guarda ``id_empresa``, nombre fiscal, RIF y conteos por tabla.
- **Multi-tenant**: todo se filtra por el ``id_empresa`` del contexto
  autenticado (nunca del archivo). Al restaurar se verifica que el manifiesto
  pertenezca a la misma empresa.
- **Nunca sobrescribir una PK existente** en la restauración: solo se insertan
  filas ausentes. Antes de restaurar se crea SIEMPRE un respaldo de seguridad.
- **ORM exclusivamente** (cross-dialecto PostgreSQL/SQL Server). Sin SQL de
  motor ni utilidades externas (nunca pg_dump/psql).
- Los archivos viven en ``settings.backup_dir`` con el patrón
  ``backup_<id_empresa>_<UTC>.json.gz`` y se rotan con la política GFS
  (abuelo-padre-hijo): último snapshot de cada día/semana/mes dentro de las
  últimas N ventanas (``settings.backup_keep_daily/weekly/monthly``).
"""

from __future__ import annotations

import gzip
import json
import logging
import re
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any

from sqlalchemy import JSON, Boolean, DateTime, Numeric, select
from sqlalchemy import types as sqltypes
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import (
    Almacen,
    Balanza,
    BoletoPesaje,
    Camion,
    Categoria,
    Conductor,
    Empresa,
    Kardex,
    Marca,
    ModeloCamion,
    Producto,
    Remolque,
    SerieNumeracion,
    Tercero,
    Transporte,
)

logger = logging.getLogger(__name__)

#: Versión del formato de snapshot. Incrementar ante cambios de esquema del
#: archivo (la restauración rechaza versiones futuras).
VERSION_SNAPSHOT = 1

#: Tablas del snapshot en orden de dependencias (padres antes que hijos):
#: catálogo primero, después operativo (boletos y kardex). Los accesos a
#: atributos de modelo (``id_empresa``, ``__table__``…) se tipan como ``Any``
#: porque SQLAlchemy no expone ``__table__`` estáticamente en ``type[Base]``.
TABLAS_SNAPSHOT: tuple[type[Any], ...] = (
    Marca,
    ModeloCamion,
    Transporte,
    Camion,
    Remolque,
    Conductor,
    Categoria,
    Producto,
    Almacen,
    Balanza,
    Tercero,
    SerieNumeracion,
    BoletoPesaje,
    Kardex,
)

#: Patrón de nombre de archivo emitido por el servicio. El timestamp lleva
#: microsegundos para evitar colisiones entre snapshots del mismo segundo.
NOMBRE_ARCHIVO_RE = re.compile(
    r"^backup_([0-9a-f-]{36})_(\d{8}T\d{12}Z)\.json\.gz$"
)


def _ahora_utc() -> datetime:
    return datetime.now(UTC).replace(tzinfo=None)


def _es_columna_uuid(col) -> bool:
    """``postgresql.UUID`` extiende ``sqltypes.Uuid`` (verificado empíricamente)."""
    return isinstance(col.type, sqltypes.Uuid)


def _serializar_valor(valor):
    """Convierte un valor de ORM a JSON-safe sin perder precisión."""
    if isinstance(valor, uuid.UUID):
        return str(valor)
    if isinstance(valor, Decimal):
        # String para preservar la precisión exacta de NUMERIC.
        return str(valor)
    if isinstance(valor, datetime):
        return valor.isoformat()
    if isinstance(valor, bytes):
        return valor.hex()
    return valor


def _columna_para_json(col) -> bool:
    """True si la columna no debe serializarse (JSON/JSONB: fuera del alcance)."""
    return isinstance(col.type, JSON)


def _deserializar_fila(fila: dict, modelo) -> dict:
    """Reconvierte valores JSON-safe a tipos de bind del ORM (por tipo de columna)."""
    salida: dict = {}
    for columna in modelo.__table__.columns:
        nombre = columna.name
        if nombre not in fila:
            continue  # defaults de BD para columnas ausentes
        valor = fila[nombre]
        if valor is None:
            salida[nombre] = None
        elif _es_columna_uuid(columna):
            salida[nombre] = uuid.UUID(valor)
        elif isinstance(columna.type, DateTime):
            salida[nombre] = datetime.fromisoformat(valor)
        elif isinstance(columna.type, Numeric):
            salida[nombre] = Decimal(valor)
        elif isinstance(columna.type, Boolean):
            salida[nombre] = bool(valor)
        else:
            salida[nombre] = valor
    return salida


@dataclass
class BackupInfo:
    """Metadatos de un snapshot (sin cargar las filas)."""

    archivo: str
    creado_en: datetime
    motivo: str
    tamano_bytes: int
    id_empresa: uuid.UUID
    empresa_nombre: str | None
    empresa_rif: str | None
    conteos: dict[str, int] = field(default_factory=dict)
    version: int = 1

    def to_dict(self) -> dict:
        return {
            "archivo": self.archivo,
            "creado_en": self.creado_en.isoformat(),
            "motivo": self.motivo,
            "tamano_bytes": self.tamano_bytes,
            "id_empresa": str(self.id_empresa),
            "empresa_nombre": self.empresa_nombre,
            "empresa_rif": self.empresa_rif,
            "conteos": self.conteos,
            "version": self.version,
        }


class BackupError(Exception):
    """Error de respaldo con mensaje accionable para el usuario final."""


class BackupService:
    """Servicio de snapshots de estación (REQ-NF-BKP-001/002/003)."""

    # ------------------------------------------------------------------
    # Utilidades de archivo
    # ------------------------------------------------------------------
    @staticmethod
    def _directorio(carpeta: str | None = None) -> Path:
        directorio = Path(carpeta or settings.backup_dir).expanduser()
        directorio.mkdir(parents=True, exist_ok=True)
        return directorio

    @staticmethod
    def _nombre_archivo(id_empresa: uuid.UUID, cuando: datetime) -> str:
        return f"backup_{id_empresa}_{cuando.strftime('%Y%m%dT%H%M%S%fZ')}.json.gz"

    @classmethod
    def _ruta_segura(cls, carpeta: str | None, nombre: str) -> Path:
        """Valida el nombre del archivo (anti path-traversal) y devuelve su ruta."""
        if not NOMBRE_ARCHIVO_RE.fullmatch(nombre):
            raise BackupError("Nombre de respaldo inválido.")
        ruta = cls._directorio(carpeta) / nombre
        if not ruta.is_file():
            raise BackupError("El respaldo no existe.")
        return ruta

    @classmethod
    def ruta_archivo(
        cls, id_empresa: uuid.UUID, nombre: str, carpeta: str | None = None
    ) -> Path:
        """Ruta de un archivo existente, validando formato y pertenencia."""
        ruta = cls._ruta_segura(carpeta, nombre)
        coincidencia = NOMBRE_ARCHIVO_RE.fullmatch(nombre)
        if coincidencia and coincidencia.group(1) != str(id_empresa):
            raise BackupError("El respaldo pertenece a otra empresa.")
        return ruta

    @staticmethod
    def _leer_manifiesto(ruta: Path) -> dict:
        with gzip.open(ruta, "rt", encoding="utf-8") as fh:
            manifiesto = json.load(fh)
        if not isinstance(manifiesto, dict):
            raise ValueError("la raíz del manifiesto no es un objeto")
        return manifiesto

    @staticmethod
    def _escribir_snapshot(ruta: Path, payload: dict) -> None:
        with gzip.open(ruta, "wt", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))

    # ------------------------------------------------------------------
    # Creación
    # ------------------------------------------------------------------
    @classmethod
    async def crear(
        cls,
        db: AsyncSession,
        empresa: Empresa,
        motivo: str = "manual",
        carpeta: str | None = None,
    ) -> BackupInfo:
        """Crea un snapshot completo de la empresa y rota los antiguos."""
        ahora = _ahora_utc()
        ruta = cls._directorio(carpeta) / cls._nombre_archivo(empresa.id_empresa, ahora)

        tablas: dict[str, list[dict]] = {}
        conteos: dict[str, int] = {}
        for modelo in TABLAS_SNAPSHOT:
            filas = (
                await db.execute(
                    select(modelo).where(modelo.id_empresa == empresa.id_empresa)
                )
            ).scalars().all()
            payload_filas = []
            for fila in filas:
                registro = {}
                for columna in modelo.__table__.columns:
                    if _columna_para_json(columna):
                        continue
                    registro[columna.name] = _serializar_valor(
                        getattr(fila, columna.name)
                    )
                payload_filas.append(registro)
            tablas[modelo.__tablename__] = payload_filas
            conteos[modelo.__tablename__] = len(payload_filas)

        payload = {
            "version": VERSION_SNAPSHOT,
            "id_empresa": str(empresa.id_empresa),
            "empresa": {
                "nombre_fiscal": empresa.nombre_fiscal,
                "rif_nit": empresa.rif_nit,
            },
            "creado_en": ahora.isoformat(),
            "motivo": motivo,
            "conteos": conteos,
            "tablas": tablas,
        }
        cls._escribir_snapshot(ruta, payload)
        cls._rotar_gfs(empresa.id_empresa, carpeta=carpeta)

        info = BackupInfo(
            archivo=ruta.name,
            creado_en=ahora,
            motivo=motivo,
            tamano_bytes=ruta.stat().st_size,
            id_empresa=empresa.id_empresa,
            empresa_nombre=empresa.nombre_fiscal,
            empresa_rif=empresa.rif_nit,
            conteos=conteos,
            version=VERSION_SNAPSHOT,
        )
        logger.info(
            "Respaldo creado: %s (%d bytes, %d tablas)", ruta.name, ruta.stat().st_size, len(tablas)
        )
        return info

    @classmethod
    def _rotar_gfs(cls, id_empresa: uuid.UUID, carpeta: str | None = None) -> None:
        """Rotación abuelo-padre-hijo (GFS) de los snapshots de la empresa.

        Conserva el último snapshot de cada ventana (día = hijo, semana ISO =
        padre, mes calendario = abuelo) dentro de las últimas N ventanas
        configuradas (``backup_keep_daily`` / ``backup_keep_weekly`` /
        ``backup_keep_monthly``; ``0`` desactiva esa capa). Un snapshot puede
        pertenecer a varios niveles; el resto se elimina. ``backup_retention_days``
        actúa como límite duro opcional de edad: ``0`` = sin límite.

        El timestamp del NOMBRE es la fuente de verdad (no el mtime, que cambia
        al copiar el archivo). Mensualmente se conserva el más reciente aunque
        la configuración dejara todas las capas en 0.
        """
        snapshots: list[tuple[Path, datetime]] = []
        for ruta in cls._directorio(carpeta).glob(f"backup_{id_empresa}_*.json.gz"):
            coincidencia = NOMBRE_ARCHIVO_RE.fullmatch(ruta.name)
            if not coincidencia:
                continue
            creado_en = datetime.strptime(
                coincidencia.group(2)[:-1], "%Y%m%dT%H%M%S%f"
            )
            snapshots.append((ruta, creado_en))
        if not snapshots:
            return
        snapshots.sort(key=lambda par: par[1])  # más antiguos primero
        todos = snapshots  # lista completa, incluso los que exceden el límite duro

        if settings.backup_retention_days > 0:
            limite = _ahora_utc() - timedelta(days=settings.backup_retention_days)
            snapshots = [par for par in snapshots if par[1] >= limite]

        conservar: set[Path] = set()

        def _conservar_ultimo_de_ventanas(clave, cantidad: int) -> None:
            """Conserva el último snapshot de cada ventana, las últimas N."""
            ultimo_por_ventana: dict[Any, tuple[Path, datetime]] = {}
            for ruta, creado_en in snapshots:
                ultimo_por_ventana[clave(creado_en)] = (ruta, creado_en)
            for ventana in sorted(ultimo_por_ventana, reverse=True)[:cantidad]:
                conservar.add(ultimo_por_ventana[ventana][0])

        # Abuelo: último de cada mes calendario (las últimas N meses).
        _conservar_ultimo_de_ventanas(
            lambda c: (c.year, c.month), settings.backup_keep_monthly
        )
        # Padre: último de cada semana ISO (las últimas N semanas).
        _conservar_ultimo_de_ventanas(
            lambda c: c.isocalendar()[:2], settings.backup_keep_weekly
        )
        # Hijo: último de cada día (los últimos N días).
        _conservar_ultimo_de_ventanas(
            lambda c: c.date(), settings.backup_keep_daily
        )
        # Red de seguridad: el snapshot más reciente nunca se elimina.
        if snapshots:
            conservar.add(snapshots[-1][0])

        for ruta, _ in todos:
            if ruta in conservar:
                continue
            try:
                ruta.unlink()
                logger.info("Respaldo rotado (GFS): %s", ruta.name)
            except OSError:  # pragma: no cover - carrera con otro proceso
                logger.warning("No se pudo rotar el respaldo %s", ruta.name)

    # ------------------------------------------------------------------
    # Listado
    # ------------------------------------------------------------------
    @classmethod
    def listar(cls, id_empresa: uuid.UUID, carpeta: str | None = None) -> list[BackupInfo]:
        """Lista los snapshots de la empresa (más recientes primero)."""
        resultados: list[BackupInfo] = []
        for ruta in cls._directorio(carpeta).glob(f"backup_{id_empresa}_*.json.gz"):
            try:
                manifiesto = cls._leer_manifiesto(ruta)
            except (OSError, EOFError, json.JSONDecodeError, TypeError, ValueError):
                logger.warning("Respaldo ilegible, se omite: %s", ruta.name)
                continue
            creado_en = datetime.fromisoformat(manifiesto["creado_en"])
            resultados.append(
                BackupInfo(
                    archivo=ruta.name,
                    creado_en=creado_en,
                    motivo=manifiesto.get("motivo", "desconocido"),
                    tamano_bytes=ruta.stat().st_size,
                    id_empresa=id_empresa,
                    empresa_nombre=manifiesto.get("empresa", {}).get("nombre_fiscal"),
                    empresa_rif=manifiesto.get("empresa", {}).get("rif_nit"),
                    conteos=manifiesto.get("conteos", {}),
                    version=manifiesto.get("version", 0),
                )
            )
        resultados.sort(key=lambda b: b.creado_en, reverse=True)
        return resultados

    # ------------------------------------------------------------------
    # Restauración
    # ------------------------------------------------------------------
    @classmethod
    async def restaurar(
        cls,
        db: AsyncSession,
        empresa: Empresa,
        nombre_archivo: str,
        carpeta: str | None = None,
    ) -> dict:
        """Restaura un snapshot de la empresa (solo inserts de PK ausentes).

        - Crea un respaldo de seguridad previo obligatorio.
        - Verifica que el manifiesto pertenezca a la empresa autenticada.
        - Nunca sobrescribe filas existentes; los conflictos se omiten.
        - Cada tabla usa un SAVEPOINT: si falla una, continúa con las demás
          y la advertencia final informa qué tablas quedaron incompletas.
        """
        ruta = cls.ruta_archivo(empresa.id_empresa, nombre_archivo, carpeta)
        try:
            manifiesto = cls._leer_manifiesto(ruta)
        except (OSError, EOFError, json.JSONDecodeError, TypeError, ValueError):
            raise BackupError(
                "El respaldo está dañado o no es un snapshot válido."
            ) from None
        if manifiesto.get("version", 0) > VERSION_SNAPSHOT:
            raise BackupError(
                "El respaldo proviene de una versión más reciente del sistema."
            )
        if manifiesto.get("id_empresa") != str(empresa.id_empresa):
            raise BackupError(
                "El respaldo pertenece a otra empresa y no puede restaurarse aquí."
            )

        # Respaldo de seguridad previo (nunca opcional).
        await cls.crear(db, empresa, motivo="pre-restauracion", carpeta=carpeta)
        await db.commit()

        tablas = manifiesto.get("tablas", {})
        por_modelo = {m.__tablename__: m for m in TABLAS_SNAPSHOT}
        restaurados: dict[str, int] = {}
        #: Tablas que no pudieron restaurarse (se reportan en la advertencia).
        fallidas: list[str] = []

        for nombre_tabla in TABLAS_SNAPSHOT:
            nombre = nombre_tabla.__tablename__
            filas = tablas.get(nombre, [])
            if not filas:
                restaurados[nombre] = 0
                continue
            modelo = por_modelo[nombre]
            pks = [c.name for c in modelo.__table__.primary_key.columns]
            # Filtro multi-tenant sobre las filas del archivo.
            filas = [f for f in filas if f.get("id_empresa") == str(empresa.id_empresa)]
            if not filas:
                restaurados[nombre] = 0
                continue

            # Consulta directa de PKs existentes de la empresa (eficiente).
            col_pk = getattr(modelo, pks[0])
            filas_existentes = (
                await db.execute(
                    select(col_pk).where(modelo.id_empresa == empresa.id_empresa)
                )
            ).scalars().all()
            claves_existentes = {
                str(c) for c in filas_existentes
            }

            pendientes = [
                fila for fila in filas if str(fila.get(pks[0])) not in claves_existentes
            ]
            if not pendientes:
                restaurados[nombre] = 0
                continue

            try:
                insertables = [_deserializar_fila(f, modelo) for f in pendientes]
                async with db.begin_nested():
                    await db.execute(modelo.__table__.insert(), insertables)
                restaurados[nombre] = len(insertables)
                logger.info("Restauradas %d filas en %s", len(insertables), nombre)
            except Exception:  # anomalía FK/deserialización: se omite y se reporta
                logger.exception("Tabla %s no pudo restaurarse; se omite", nombre)
                restaurados[nombre] = 0
                fallidas.append(nombre)

        await db.commit()
        advertencia = (
            "Restauración completada sin sobrescribir registros existentes. "
            "Los datos se restauran tal como fueron guardados en el respaldo "
            "(incluido el estado de sincronización); solo se insertan los "
            "registros ausentes."
        )
        if fallidas:
            advertencia += (
                " Tablas incompletas: "
                + ", ".join(fallidas)
                + ". Revise el respaldo y vuelva a intentarlo."
            )
        return {"restaurados": restaurados, "advertencia": advertencia}
-- =============================================================================
-- BALANSOFT-WS · Migración 029 · Conceptos de inventario
-- -----------------------------------------------------------------------------
-- El árbol del menú dictado por el cliente pide **CONCEPTOS DE INVENTARIO**
-- bajo CATÁLOGOS. Hoy el motivo de un movimiento de kardex se escribe a mano en
-- `kardex.documento` (texto libre, VARCHAR(100) nullable): no hay catálogo, no
-- se puede filtrar ni reportar por motivo y cualquier errata se propaga.
--
-- Esta migración crea `conceptos_inventario` (catálogo por empresa, con
-- `tipo_movimiento` opcional para acotar qué conceptos aplican a un ingreso
-- `10` o a un despacho `60`) y enlaza el movimiento con su concepto mediante
-- `kardex.id_concepto` (nullable).
--
-- Compatibilidad: `kardex.documento` NO se borra. El ajuste de inventario sigue
-- guardando el texto para el histórico y los boletos ya registrados, pero la UI
-- pasa a elegir un concepto del catálogo (`id_concepto`). `id_concepto` es
-- *nullable* y aditivo, así que la estación sigue operando sin tocar nada.
--
-- Reflejo obligatorio en `balansoft-ws-local.sql` y en
-- `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 022/026/027/028).
-- =============================================================================

CREATE TABLE IF NOT EXISTS conceptos_inventario (
    id_concepto     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo          VARCHAR(20),
    nombre          VARCHAR(150) NOT NULL,
    descripcion     VARCHAR(255),
    -- ingreso (10) | despacho (60) | ajuste | ambos. NULL = aplica a todo.
    tipo_movimiento VARCHAR(10),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS conceptos_inventario_empresa_codigo_uk
    ON conceptos_inventario (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

-- Enlace opcional movimiento de kardex → concepto (NULL = sin concepto).
ALTER TABLE kardex
    ADD COLUMN IF NOT EXISTS id_concepto UUID REFERENCES conceptos_inventario(id_concepto);

CREATE INDEX IF NOT EXISTS kardex_id_concepto_idx
    ON kardex (id_concepto);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_conceptos_inventario_tipo'
    ) THEN
        ALTER TABLE conceptos_inventario
            ADD CONSTRAINT ck_conceptos_inventario_tipo
            CHECK (tipo_movimiento IS NULL OR tipo_movimiento IN ('ingreso', 'despacho', 'ajuste', 'ambos'));
    END IF;
END
$$;

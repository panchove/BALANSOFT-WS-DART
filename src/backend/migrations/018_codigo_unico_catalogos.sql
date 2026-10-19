-- =============================================================================
-- BALANSOFT-WS · Migración 018 · Código único por empresa en catálogos (esquema local)
-- -----------------------------------------------------------------------------
-- Garantiza a nivel de BD que el "código interno / personalizado" de cada
-- catálogo sea único dentro de su empresa (partiendo de la regla
-- "1 máquina local = 1 empresa"):
--
--   categorias, productos, terceros, transportes, almacenes y balanzas
--
-- Índice único PARCIAL: solo se exige unicidad cuando `codigo IS NOT NULL`,
-- de modo que los registros sin código interno siguen permitiéndose.
--
-- Idempotente: seguro re-ejecutarlo (CREATE UNIQUE INDEX IF NOT EXISTS). Si la
-- BD ya tiene códigos duplicados, primero se conserva el registro más antiguo
-- (created_at) y el resto se deja sin código (NULL) antes de crear el índice.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Sanea duplicados existentes (conserva el más antiguo por id_empresa+codigo)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    entidad record;
BEGIN
    FOR entidad IN SELECT tabla, id_col
                   FROM (VALUES
                       ('categorias',   'id_categoria'),
                       ('productos',    'id_producto'),
                       ('terceros',     'id_tercero'),
                       ('transportes',  'id_transporte'),
                       ('almacenes',    'id_almacen'),
                       ('balanzas',     'id_balanza')
                   ) AS t(tabla, id_col)
    LOOP
        EXECUTE format(
            'UPDATE %I AS p
                SET codigo = NULL
             FROM (
                  SELECT %I AS pk,
                         row_number() OVER (
                             PARTITION BY id_empresa, codigo
                             ORDER BY created_at, %I
                         ) AS rn
                    FROM %I
                   WHERE codigo IS NOT NULL
             ) AS r
            WHERE p.%I = r.pk
              AND r.rn > 1',
            entidad.tabla, entidad.id_col, entidad.id_col, entidad.tabla, entidad.id_col
        );
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------------
-- 2. Índices únicos parciales: UN codigo por empresa
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS categorias_empresa_codigo_uk
    ON public.categorias (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS productos_empresa_codigo_uk
    ON productos (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS terceros_empresa_codigo_uk
    ON terceros (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS transportes_empresa_codigo_uk
    ON transportes (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS almacenes_empresa_codigo_uk
    ON almacenes (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS balanzas_empresa_codigo_uk
    ON balanzas (id_empresa, codigo)
    WHERE codigo IS NOT NULL;
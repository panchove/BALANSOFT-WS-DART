-- =============================================================================
-- BALANSOFT-WS · Migración 013 · Productos requieren categoría (esquema local)
-- -----------------------------------------------------------------------------
-- Añade `productos.id_categoria` (FK a `categorias` del mismo esquema) y aplica
-- la regla de negocio "todo producto debe pertenecer a una categoría":
--   · Los productos existentes sin categoría se reasignan a una categoría
--     "General" propia de su empresa (creada si no existe).
--   · La columna termina NOT NULL, igual que el esquema canónico.
-- Idempotente: seguro re-ejecutarlo.
-- =============================================================================

ALTER TABLE productos ADD COLUMN IF NOT EXISTS id_categoria UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_productos_categorias'
    ) THEN
        ALTER TABLE productos
            ADD CONSTRAINT fk_productos_categorias
            FOREIGN KEY (id_categoria) REFERENCES categorias(id_categoria);
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS ix_productos_id_categoria
    ON productos (id_categoria);

DO $$
DECLARE
    v_id_empresa  UUID;
    v_id_categoria UUID;
BEGIN
    FOR v_id_empresa IN
        SELECT DISTINCT id_empresa FROM productos WHERE id_categoria IS NULL
    LOOP
        SELECT id_categoria INTO v_id_categoria
        FROM categorias
        WHERE id_empresa = v_id_empresa AND nombre = 'General'
        LIMIT 1;
        IF v_id_categoria IS NULL THEN
            INSERT INTO categorias (id_categoria, id_empresa, nombre)
            VALUES (gen_random_uuid(), v_id_empresa, 'General')
            RETURNING id_categoria INTO v_id_categoria;
        END IF;
        UPDATE productos
        SET id_categoria = v_id_categoria
        WHERE id_empresa = v_id_empresa AND id_categoria IS NULL;
    END LOOP;
END
$$;

ALTER TABLE productos ALTER COLUMN id_categoria SET NOT NULL;
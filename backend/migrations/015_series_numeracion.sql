-- =============================================================================
-- BALANSOFT-WS · Migración 015 · Series de numeración de documentos
-- -----------------------------------------------------------------------------
-- Empresa puede definir UNA O MÁS series de numeración (prefijo, dígitos,
-- inicio). En el "campo de trabajo" (estación) solo se elige CUÁL serie usar
-- por pesaje (`id_serie` en boletos_pesaje), y los reportes/gestión muestran
-- qué modelo de numeración se aplicó a cada boleto.
--
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 014). Nunca reutiliza
-- números (el "siguiente" se avanza con FOR UPDATE; ver weighing_service).
-- =============================================================================

CREATE TABLE IF NOT EXISTS series_numeracion (
    id_serie     UUID         PRIMARY KEY,
    id_empresa   UUID         NOT NULL REFERENCES empresas (id_empresa) ON DELETE CASCADE,
    nombre       VARCHAR(80)  NOT NULL,                  -- "Serie TA Facturación"
    prefijo      VARCHAR(20)  NOT NULL,                  -- "TA-" (obliga el guion? no; lo arma la UI)
    inicio       INTEGER      NOT NULL DEFAULT 1 CHECK (inicio >= 1),
    siguiente    INTEGER      NOT NULL,                  -- próximo número a emitir
    digitos      INTEGER      NOT NULL DEFAULT 8 CHECK (digitos BETWEEN 1 AND 20),
    activa       BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_serie_prefijo_no_vacio CHECK (btrim(prefijo) <> '')
);

ALTER TABLE boletos_pesaje
    ADD COLUMN IF NOT EXISTS id_serie UUID;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_series_numeracion_activa_empresa'
    ) THEN
        -- Solo UNA serie activa por empresa (la que usa el campo de trabajo).
        CREATE UNIQUE INDEX uq_series_numeracion_activa_empresa
            ON series_numeracion (id_empresa) WHERE activa;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_boletos_pesaje_id_serie'
    ) THEN
        ALTER TABLE boletos_pesaje
            ADD CONSTRAINT fk_boletos_pesaje_id_serie
            FOREIGN KEY (id_serie) REFERENCES series_numeracion (id_serie)
            ON DELETE SET NULL;
    END IF;
END
$$;

-- Seed idempotente: crea la serie principal para cada empresa que aún no tenga
-- ninguna, con prefijo TA- (patrón canónico de Settings) y `siguiente` =
-- MAX(numero legacy)+1 para no colisionar con los boletos ya emitidos.
DO $$
DECLARE
    r RECORD;
    max_num INTEGER;
    nuevo_id UUID;
BEGIN
    FOR r IN SELECT id_empresa FROM empresas e
    LOOP
        IF EXISTS (SELECT 1 FROM series_numeracion WHERE id_empresa = r.id_empresa) THEN
            CONTINUE;
        END IF;
        SELECT MAX(
            CASE WHEN numero_boleto ~ '^TA-[0-9]+$'
                 THEN NULLIF(SUBSTRING(numero_boleto FROM '[0-9]+$'), '')::INTEGER
                 ELSE 0 END
        ) + 1
          INTO max_num
          FROM boletos_pesaje
         WHERE id_empresa = r.id_empresa;
        max_num := COALESCE(max_num, 1);

        INSERT INTO series_numeracion
            (id_serie, id_empresa, nombre, prefijo, inicio, siguiente, digitos, activa)
        VALUES
            (gen_random_uuid(), r.id_empresa, 'Serie principal', 'TA-', 1, max_num, 8, TRUE)
        RETURNING id_serie INTO nuevo_id;

        UPDATE boletos_pesaje
           SET id_serie = nuevo_id
         WHERE id_empresa = r.id_empresa;
    END LOOP;
END
$$;

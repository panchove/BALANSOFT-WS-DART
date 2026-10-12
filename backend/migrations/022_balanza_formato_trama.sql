-- =============================================================================
-- BALANSOFT-WS · Migración 022 · Formato de trama y baudrate por balanza
-- -----------------------------------------------------------------------------
-- Añade a `balanzas` la configuración fina del HAL para básculas reales:
--   formato_trama VARCHAR(10) NOT NULL DEFAULT 'auto' → auto|json|ascii
--     * auto  → detecta JSON (simulador BSDD) vs ASCII continuo (indicador real)
--     * json  → solo JSON (simulador BSDD)
--     * ascii → solo flujo ASCII continuo (indicador real)
--   baudrate       INTEGER NOT NULL DEFAULT 9600       → solo serial
--   delimitador    VARCHAR(10) NULL                    → lf|cr|crlf|stx_etx (NULL = lf)
--
-- El default deja toda estación existente exactamente como hoy (auto/9600/NULL):
-- el simulador BSDD (JSON) sigue funcionando igual.
-- Reflejo obligatorio en `balansoft-ws-local.sql` (CREATE TABLE + bloque ALTER)
-- y en `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 021).
-- =============================================================================

ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS formato_trama VARCHAR(10);
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS baudrate INTEGER;
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS delimitador VARCHAR(10);

UPDATE balanzas SET formato_trama = 'auto' WHERE formato_trama IS NULL;
UPDATE balanzas SET baudrate = 9600 WHERE baudrate IS NULL;

ALTER TABLE balanzas ALTER COLUMN formato_trama SET DEFAULT 'auto';
ALTER TABLE balanzas ALTER COLUMN baudrate SET DEFAULT 9600;
ALTER TABLE balanzas ALTER COLUMN formato_trama SET NOT NULL;
ALTER TABLE balanzas ALTER COLUMN baudrate SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_balanzas_formato_trama'
    ) THEN
        ALTER TABLE balanzas
            ADD CONSTRAINT ck_balanzas_formato_trama
            CHECK (formato_trama IN ('auto', 'json', 'ascii'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_balanzas_baudrate'
    ) THEN
        ALTER TABLE balanzas
            ADD CONSTRAINT ck_balanzas_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_balanzas_delimitador'
    ) THEN
        ALTER TABLE balanzas
            ADD CONSTRAINT ck_balanzas_delimitador
            CHECK (delimitador IS NULL OR delimitador IN ('lf', 'cr', 'crlf', 'stx_etx'));
    END IF;
END
$$;

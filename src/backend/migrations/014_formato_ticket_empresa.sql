-- =============================================================================
-- BALANSOFT-WS · Migración 014 · Formato de ticket por defecto (esquema local)
-- -----------------------------------------------------------------------------
-- Añade `empresas.formato_ticket` (PDF|TXT). Define el formato que se usa SIEMPRE
-- al exportar el ticket desde Configuración; los modales de pesaje siguen
-- ofreciendo PDF o TXT explícitamente.
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 013).
-- =============================================================================

ALTER TABLE empresas ADD COLUMN IF NOT EXISTS formato_ticket VARCHAR(10);

UPDATE empresas SET formato_ticket = 'PDF' WHERE formato_ticket IS NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_formato_ticket'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_formato_ticket
            CHECK (formato_ticket IN ('PDF', 'TXT'));
    END IF;
END
$$;

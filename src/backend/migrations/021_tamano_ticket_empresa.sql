-- =============================================================================
-- BALANSOFT-WS · Migración 021 · Tipografía del ticket por empresa
-- -----------------------------------------------------------------------------
-- Añade a `empresas`:
--   tamano_ticket_pdf VARCHAR(20) → techo del auto-fit: AUTOMATICO/GRANDE/MEDIANO/PEQUENO
--   fuente_ticket_pdf  VARCHAR(20) → familia tipográfica: solo DejaVu
--
-- Ambas preferencias se entregan al cliente en la respuesta de login y se editan
-- con `PUT /api/v1/empresa` (solo ADMIN).
-- El default de ambas es lo que garantiza que toda estación existente siga
-- exactamente como hoy (REQ-FN-012).
-- Reflejo obligatorio en `balansoft-ws-local.sql` (CREATE TABLE + bloque ALTER).
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 014/016/017).
-- =============================================================================

ALTER TABLE empresas ADD COLUMN IF NOT EXISTS tamano_ticket_pdf VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS fuente_ticket_pdf VARCHAR(20);

UPDATE empresas SET tamano_ticket_pdf = 'AUTOMATICO' WHERE tamano_ticket_pdf IS NULL;
UPDATE empresas SET fuente_ticket_pdf = 'DejaVu' WHERE fuente_ticket_pdf IS NULL;

ALTER TABLE empresas ALTER COLUMN tamano_ticket_pdf SET DEFAULT 'AUTOMATICO';
ALTER TABLE empresas ALTER COLUMN fuente_ticket_pdf SET DEFAULT 'DejaVu';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_tamano_ticket_pdf'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_tamano_ticket_pdf
            CHECK (tamano_ticket_pdf IN ('AUTOMATICO', 'GRANDE', 'MEDIANO', 'PEQUENO'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_fuente_ticket_pdf'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_fuente_ticket_pdf
            CHECK (fuente_ticket_pdf IN ('DejaVu'));
    END IF;
END
$$;
-- =============================================================================
-- BALANSOFT-WS · Migración 017 · Idioma y formato de reporte de la empresa
-- -----------------------------------------------------------------------------
-- Añade a `empresas`:
--   idioma          VARCHAR(5)  (es|en|pt)  → idioma de tickets y reportes
--   formato_reporte VARCHAR(10) (EXCEL|PDF) → formato de exportación por defecto
--
-- Ambas preferencias se entregan al cliente en la respuesta de login y se
-- editan con `PUT /api/v1/empresa` (solo ADMIN).
-- Ver docs/I18N_Y_ONBOARDING.md (REQ-NF-CFG-001, REQ-NF-I18N-002).
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 014/016).
-- =============================================================================

ALTER TABLE empresas ADD COLUMN IF NOT EXISTS idioma VARCHAR(5);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS formato_reporte VARCHAR(10);

UPDATE empresas SET idioma = 'es' WHERE idioma IS NULL;
UPDATE empresas SET formato_reporte = 'EXCEL' WHERE formato_reporte IS NULL;

ALTER TABLE empresas ALTER COLUMN idioma SET DEFAULT 'es';
ALTER TABLE empresas ALTER COLUMN formato_reporte SET DEFAULT 'EXCEL';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_idioma'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_idioma
            CHECK (idioma IN ('es', 'en', 'pt'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_formato_reporte'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_formato_reporte
            CHECK (formato_reporte IN ('EXCEL', 'PDF'));
    END IF;
END
$$;

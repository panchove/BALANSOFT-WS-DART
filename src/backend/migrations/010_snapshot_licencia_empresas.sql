-- =============================================================================
-- BALANSOFT-WS · Migración 010 · Snapshot de licencia en empresas (esquema local)
-- -----------------------------------------------------------------------------
-- Alinea `empresas` (DB local de la estación) con el modelo SQLAlchemy actual:
--  1. agrega licencia_key / licencia_tier / licencia_status / licencia_expira,
--  2. relaja id_cuenta (ya no es NOT NULL; la cuenta se espeja por RIF/NIT,
--     el vínculo 1:1 con el servidor vive en identidad_local.id_cuenta).
-- Idempotente: seguro re-ejecutarlo.
-- =============================================================================

ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_key VARCHAR(255);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_tier VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_status VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_expira TIMESTAMP;
ALTER TABLE empresas ALTER COLUMN id_cuenta DROP NOT NULL;
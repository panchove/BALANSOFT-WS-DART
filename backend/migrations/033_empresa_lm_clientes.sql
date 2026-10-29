-- Migración 033: Campos de identidad del cliente del License Manager (LM) en empresa
-- Añade lm_client_id y lm_client_email a la tabla empresas para trazar la
-- identidad del cliente que valida el LM durante el setup inicial de la estación.
-- Idempotente: usa ADD COLUMN IF NOT EXISTS para no fallar en re-ejecuciones.

ALTER TABLE empresas ADD COLUMN IF NOT EXISTS lm_client_id UUID;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS lm_client_email VARCHAR(255);

CREATE INDEX IF NOT EXISTS idx_empresa_lm_client_email ON empresas(lm_client_email);

-- Comentarios de documentación (PostgreSQL)
COMMENT ON COLUMN empresas.lm_client_id IS 'ID del cliente en el License Manager (LM), asignado durante el setup inicial.';
COMMENT ON COLUMN empresas.lm_client_email IS 'Email del cliente en el License Manager (LM), asignado durante el setup inicial.';

-- =============================================================================
-- BALANSOFT-WS · Migración 009 · max_sesiones en licencias del servidor
-- -----------------------------------------------------------------------------
-- Controla las sesiones concurrentes permitidas por licencia (NULL = ilimitado).
-- Mantiene el aspecto de la tabla (ServerLicenciaOut) sincronizado con la
-- política de login del servidor (servidor.py → server_login).
-- =============================================================================

ALTER TABLE licencias ADD COLUMN IF NOT EXISTS max_sesiones INTEGER;
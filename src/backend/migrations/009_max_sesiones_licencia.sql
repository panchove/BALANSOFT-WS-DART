-- =============================================================================
-- BALANSOFT-WS · Migración 009 · max_sesiones en licencias del servidor
-- -----------------------------------------------------------------------------
-- Controla las sesiones concurrentes permitidas por licencia (NULL = ilimitado).
-- Mantiene el aspecto de la tabla (ServerLicenciaOut) sincronizado con la
-- política de login del servidor (servidor.py → server_login).
--
-- La tabla `licencias` solo existe en el esquema del SERVIDOR. En una estación
-- local (APP_ROLE=local) no existe, de modo que este paso debe NO operar en esa
-- base: en `balansoft-ws-server.sql` la columna ya viene en el CREATE TABLE.
-- =============================================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'licencias'
    ) THEN
        ALTER TABLE licencias ADD COLUMN IF NOT EXISTS max_sesiones INTEGER;
    END IF;
END $$;
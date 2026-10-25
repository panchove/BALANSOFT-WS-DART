-- =============================================================================
-- BALANSOFT-WS · Migración 031 · Marca, modelo y fabricante en cámaras
-- -----------------------------------------------------------------------------
-- Facilita la gestión de cámaras de pesaje permitiendo identificar fácilmente:
--   - `marca`      → Marca del dispositivo (ej. 'Logitech', 'Hikvision', 'Dahua').
--   - `modelo`     → Modelo del equipo (ej. 'C920', 'DS-2CD2043G2-I').
--   - `fabricante` → Fabricante opcional (ej. 'Logitech Inc.', 'Hangzhou Hikvision').
--
-- Columnas opcionales (nullable) que mantienen 100% retrocompatibilidad.
-- Reflejo en `balansoft-ws-local.sql` y `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo.
-- =============================================================================

ALTER TABLE camaras
    ADD COLUMN IF NOT EXISTS marca VARCHAR(100);

ALTER TABLE camaras
    ADD COLUMN IF NOT EXISTS modelo VARCHAR(100);

ALTER TABLE camaras
    ADD COLUMN IF NOT EXISTS fabricante VARCHAR(100);

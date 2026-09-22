-- =============================================================================
-- BALANSOFT-WS · Migración 016 · Ruta de exportación de reportes configurable
-- -----------------------------------------------------------------------------
-- Añade `empresas.ruta_exportacion_reportes` (VARCHAR(500)).
-- Permite al usuario ADMIN configurar la carpeta de destino para las
-- exportaciones de reportes (Excel, PDF, Kardex) compartida para todas las
-- sesiones de la empresa.
-- Idempotente: seguro re-ejecutarlo.
-- =============================================================================

ALTER TABLE empresas ADD COLUMN IF NOT EXISTS ruta_exportacion_reportes VARCHAR(500);

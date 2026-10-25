-- =============================================================================
-- BALANSOFT-WS · Migración 030 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Añade a `camaras` el **origen** de la cámara:
--   - `origen`      → 'ip' (default) | 'local' (USB/integrada de la PC).
--   - `dispositivo` → ruta del dispositivo para las locales (`/dev/video0`).
--
-- NO la aplica el arranque de PostgreSQL: `wserver._migraciones_pendientes`
-- excluye los archivos `*.mssql.sql` (sintaxis de otro motor). Para SQL Server
-- el esquema canónico `sqlserver/balansoft-ws-local.sql` ya incluye el estado
-- final (las migraciones plegadas 001-030), así que este archivo es el
-- equivalente de referencia para instalaciones SQL Server existentes.
-- =============================================================================

BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.camaras', N'origen') IS NULL BEGIN
    ALTER TABLE [dbo].[camaras] ADD [origen] NVARCHAR(10) DEFAULT N'ip' NOT NULL;
END

IF COL_LENGTH(N'dbo.camaras', N'dispositivo') IS NULL BEGIN
    ALTER TABLE [dbo].[camaras] ADD [dispositivo] NVARCHAR(255);
END

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'ck_camaras_origen') BEGIN
    ALTER TABLE [dbo].[camaras] ADD CONSTRAINT [ck_camaras_origen]
        CHECK ((origen) IN (N'ip', N'local'));
END

COMMIT TRANSACTION;

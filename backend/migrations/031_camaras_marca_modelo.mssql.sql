-- =============================================================================
-- BALANSOFT-WS · Migración 031 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Añade a `camaras` marca, modelo y fabricante:
--   - `marca`      → Marca del dispositivo.
--   - `modelo`     → Modelo del equipo.
--   - `fabricante` → Fabricante opcional.
-- =============================================================================

BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.camaras', N'marca') IS NULL BEGIN
    ALTER TABLE [dbo].[camaras] ADD [marca] NVARCHAR(100);
END

IF COL_LENGTH(N'dbo.camaras', N'modelo') IS NULL BEGIN
    ALTER TABLE [dbo].[camaras] ADD [modelo] NVARCHAR(100);
END

IF COL_LENGTH(N'dbo.camaras', N'fabricante') IS NULL BEGIN
    ALTER TABLE [dbo].[camaras] ADD [fabricante] NVARCHAR(100);
END

COMMIT TRANSACTION;

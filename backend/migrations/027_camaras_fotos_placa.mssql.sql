-- =============================================================================
-- BALANSOFT-WS · Migración 027 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Crea `camaras` (dispositivo de captura de placa por snapshot HTTP/JPEG) y
-- añade el flag `boletos_pesaje.fotos_placa_tomadas` más los interruptores por
-- empresa `fotos_placa_activas` / `fotos_placa_obligatorias`.
--
-- NO la aplica el arranque de PostgreSQL: `wserver._migraciones_pendientes`
-- excluye los archivos `*.mssql.sql` (sintaxis de otro motor). Para SQL Server
-- el esquema canónico `sqlserver/balansoft-ws-local.sql` ya incluye el estado
-- final (las migraciones plegadas 001-027), así que este archivo es el
-- equivalente de referencia para instalaciones SQL Server existentes.
-- =============================================================================

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.camaras', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[camaras] (
        [id_camara] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [descripcion] NVARCHAR(150) NOT NULL,
        [activo] BIT DEFAULT 1 NOT NULL,
        [is_simulada] BIT DEFAULT 0 NOT NULL,
        [url_snapshot] NVARCHAR(500) NOT NULL,
        [usuario] NVARCHAR(100),
        [password] NVARCHAR(255),
        [ubicacion] NVARCHAR(10) DEFAULT N'ambos' NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [ck_camaras_ubicacion] CHECK ((ubicacion) IN (N'entrada', N'salida', N'ambos')),
        CONSTRAINT [camaras_pkey] PRIMARY KEY (id_camara)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'camaras_id_empresa_fkey') BEGIN
    ALTER TABLE [dbo].[camaras] ADD CONSTRAINT [camaras_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'camaras_empresa_codigo_uk') BEGIN
    CREATE UNIQUE INDEX [camaras_empresa_codigo_uk] ON [dbo].[camaras] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END

IF COL_LENGTH(N'dbo.boletos_pesaje', N'fotos_placa_tomadas') IS NULL BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD [fotos_placa_tomadas] BIT DEFAULT 0 NOT NULL;
END

IF COL_LENGTH(N'dbo.empresas', N'fotos_placa_activas') IS NULL BEGIN
    ALTER TABLE [dbo].[empresas] ADD [fotos_placa_activas] BIT DEFAULT 0 NOT NULL;
END

IF COL_LENGTH(N'dbo.empresas', N'fotos_placa_obligatorias') IS NULL BEGIN
    ALTER TABLE [dbo].[empresas] ADD [fotos_placa_obligatorias] BIT DEFAULT 0 NOT NULL;
END

COMMIT TRANSACTION;

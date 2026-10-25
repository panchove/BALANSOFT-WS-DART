-- =============================================================================
-- BALANSOFT-WS · Migración 028 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Crea `indicadores` (terminal de peso: BKG LP7510, CAS C12001A, Transcell
-- TI500E, AND AD431, Cardinal UMC555, Toledo T4321, …) y enlaza la báscula
-- física con su indicador mediante `balanzas.id_indicador` (nullable).
--
-- NO la aplica el arranque de PostgreSQL: `wserver._migraciones_pendientes`
-- excluye los archivos `*.mssql.sql` (sintaxis de otro motor). Para SQL Server
-- el esquema canónico `sqlserver/balansoft-ws-local.sql` ya incluye el estado
-- final (las migraciones plegadas 001-028), así que este archivo es el
-- equivalente de referencia para instalaciones SQL Server existentes.
-- =============================================================================

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.indicadores', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[indicadores] (
        [id_indicador] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [descripcion] NVARCHAR(150) NOT NULL,
        [marca] NVARCHAR(100),
        [modelo] NVARCHAR(100),
        [activo] BIT DEFAULT 1 NOT NULL,
        [is_simulado] BIT DEFAULT 0 NOT NULL,
        [protocolo] NVARCHAR(20) DEFAULT N'tcp',
        [puerto_com] NVARCHAR(50),
        [ip_address] NVARCHAR(45),
        [puerto_tcp] INT,
        [formato_trama] NVARCHAR(10) DEFAULT N'auto' NOT NULL,
        [baudrate] INT DEFAULT 9600 NOT NULL,
        [delimitador] NVARCHAR(10),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [ck_indicadores_formato_trama] CHECK ((formato_trama) IN (N'auto', N'json', N'ascii')),
        CONSTRAINT [ck_indicadores_baudrate] CHECK ((baudrate) IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200)),
        CONSTRAINT [ck_indicadores_delimitador] CHECK ((delimitador IS NULL OR delimitador IN (N'lf', N'cr', N'crlf', N'stx_etx'))),
        CONSTRAINT [indicadores_pkey] PRIMARY KEY (id_indicador)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'indicadores_id_empresa_fkey') BEGIN
    ALTER TABLE [dbo].[indicadores] ADD CONSTRAINT [indicadores_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'indicadores_empresa_codigo_uk') BEGIN
    CREATE UNIQUE INDEX [indicadores_empresa_codigo_uk] ON [dbo].[indicadores] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END

IF COL_LENGTH(N'dbo.balanzas', N'id_indicador') IS NULL BEGIN
    ALTER TABLE [dbo].[balanzas] ADD [id_indicador] UNIQUEIDENTIFIER;
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'balanzas_id_indicador_fkey') BEGIN
    ALTER TABLE [dbo].[balanzas] ADD CONSTRAINT [balanzas_id_indicador_fkey] FOREIGN KEY (id_indicador) REFERENCES [dbo].[indicadores] (id_indicador);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'balanzas_id_indicador_idx') BEGIN
    CREATE INDEX [balanzas_id_indicador_idx] ON [dbo].[balanzas] (id_indicador);
END

COMMIT TRANSACTION;

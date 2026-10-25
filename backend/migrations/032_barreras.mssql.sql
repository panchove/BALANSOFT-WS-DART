-- =============================================================================
-- BALANSOFT-WS · Migración 032 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Crea `barreras`: dispositivos de control físico de acceso (abrir/cerrar).
-- =============================================================================

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.barreras', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[barreras] (
        [id_barrera] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [descripcion] NVARCHAR(150) NOT NULL,
        [activo] BIT DEFAULT 1 NOT NULL,
        [is_simulado] BIT DEFAULT 0 NOT NULL,
        [protocolo] NVARCHAR(20) DEFAULT N'http' NOT NULL,
        [ip_address] NVARCHAR(45),
        [puerto_tcp] INT,
        [puerto_com] NVARCHAR(50),
        [baudrate] INT DEFAULT 9600 NOT NULL,
        [ubicacion] NVARCHAR(10) DEFAULT N'ambos' NOT NULL,
        [control_automatico] BIT DEFAULT 0 NOT NULL,
        [tiempo_espera_segundos] INT DEFAULT 5 NOT NULL,
        [comando_abrir] NVARCHAR(255),
        [comando_cerrar] NVARCHAR(255),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [ck_barreras_protocolo] CHECK ((protocolo) IN (N'http', N'serial')),
        CONSTRAINT [ck_barreras_ubicacion] CHECK ((ubicacion) IN (N'entrada', N'salida', N'ambos')),
        CONSTRAINT [ck_barreras_baudrate] CHECK ((baudrate) IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200)),
        CONSTRAINT [barreras_pkey] PRIMARY KEY (id_barrera)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'barreras_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[barreras] ADD CONSTRAINT [barreras_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'barreras_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [barreras_empresa_codigo_uk] ON [dbo].[barreras] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END

COMMIT TRANSACTION;

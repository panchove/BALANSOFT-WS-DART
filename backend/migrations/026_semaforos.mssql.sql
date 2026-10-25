-- =============================================================================
-- BALANSOFT-WS · Migración 026 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Crea `semaforos`: la torre de 3 luces + zumbador como dispositivo actuador.
-- El semáforo obedece los comandos JSON del SPEC del simulador BSDD (§4) por
-- HTTP/REST (`127.0.0.1:8080/api/semaforo`, Fase 2) o por USB serie CDC-ACM
-- (`/dev/bsdd_semaforo_acm`, Fase 3); la app decide el LED según el peso en
-- vivo de la báscula vinculada y el estado del boleto (docs/SEMAFORO.md).
--
-- NO la aplica el arranque de PostgreSQL: `wserver._migraciones_pendientes`
-- excluye los archivos `*.mssql.sql` (sintaxis de otro motor). Para SQL Server
-- el esquema canónico `sqlserver/balansoft-ws-local.sql` ya incluye el estado
-- final (las migraciones plegadas 001-026), así que este archivo es el
-- equivalente de referencia para instalaciones SQL Server existentes.
-- =============================================================================

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.semaforos', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[semaforos] (
        [id_semaforo] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
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
        [id_balanza] UNIQUEIDENTIFIER,
        [control_automatico] BIT DEFAULT 0 NOT NULL,
        [umbral_cero_kg] DECIMAL(10,2) DEFAULT 5.0 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [ck_semaforos_protocolo] CHECK ((protocolo) IN (N'http', N'serial')),
        CONSTRAINT [ck_semaforos_baudrate] CHECK ((baudrate) IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200)),
        CONSTRAINT [semaforos_pkey] PRIMARY KEY (id_semaforo)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'semaforos_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[semaforos] ADD CONSTRAINT [semaforos_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'semaforos_id_balanza_fkey' ) BEGIN
    ALTER TABLE [dbo].[semaforos] ADD CONSTRAINT [semaforos_id_balanza_fkey] FOREIGN KEY (id_balanza) REFERENCES [dbo].[balanzas] (id_balanza);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'semaforos_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [semaforos_empresa_codigo_uk] ON [dbo].[semaforos] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END

COMMIT TRANSACTION;

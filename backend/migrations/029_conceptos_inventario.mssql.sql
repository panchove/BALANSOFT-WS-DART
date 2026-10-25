-- =============================================================================
-- BALANSOFT-WS · Migración 029 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Crea `conceptos_inventario` (catálogo de motivos de movimiento de kardex) y
-- enlaza el movimiento con su concepto mediante `kardex.id_concepto` (nullable).
--
-- NO la aplica el arranque de PostgreSQL: `wserver._migraciones_pendientes`
-- excluye los archivos `*.mssql.sql` (sintaxis de otro motor). Para SQL Server
-- el esquema canónico `sqlserver/balansoft-ws-local.sql` ya incluye el estado
-- final (las migraciones plegadas 001-029), así que este archivo es el
-- equivalente de referencia para instalaciones SQL Server existentes.
-- =============================================================================

BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.conceptos_inventario', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[conceptos_inventario] (
        [id_concepto] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [nombre] NVARCHAR(150) NOT NULL,
        [descripcion] NVARCHAR(255),
        [tipo_movimiento] NVARCHAR(10),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [ck_conceptos_inventario_tipo] CHECK ((tipo_movimiento IS NULL OR tipo_movimiento IN (N'ingreso', N'despacho', N'ajuste', N'ambos'))),
        CONSTRAINT [conceptos_inventario_pkey] PRIMARY KEY (id_concepto)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'conceptos_inventario_id_empresa_fkey') BEGIN
    ALTER TABLE [dbo].[conceptos_inventario] ADD CONSTRAINT [conceptos_inventario_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'conceptos_inventario_empresa_codigo_uk') BEGIN
    CREATE UNIQUE INDEX [conceptos_inventario_empresa_codigo_uk] ON [dbo].[conceptos_inventario] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END

IF COL_LENGTH(N'dbo.kardex', N'id_concepto') IS NULL BEGIN
    ALTER TABLE [dbo].[kardex] ADD [id_concepto] UNIQUEIDENTIFIER;
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'kardex_id_concepto_fkey') BEGIN
    ALTER TABLE [dbo].[kardex] ADD CONSTRAINT [kardex_id_concepto_fkey] FOREIGN KEY (id_concepto) REFERENCES [dbo].[conceptos_inventario] (id_concepto);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'kardex_id_concepto_idx') BEGIN
    CREATE INDEX [kardex_id_concepto_idx] ON [dbo].[kardex] (id_concepto);
END

COMMIT TRANSACTION;

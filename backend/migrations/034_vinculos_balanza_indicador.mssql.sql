IF OBJECT_ID(N'dbo.vinculos_balanza_indicador', N'U') IS NULL
BEGIN
    CREATE TABLE [dbo].[vinculos_balanza_indicador] (
        [id_vinculo] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL PRIMARY KEY,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [id_bascula] UNIQUEIDENTIFIER NOT NULL,
        [id_indicador] UNIQUEIDENTIFIER NOT NULL,
        [activo] BIT DEFAULT 0 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [fk_vinculo_empresa] FOREIGN KEY ([id_empresa]) REFERENCES [dbo].[empresas]([id_empresa]) ON DELETE CASCADE,
        CONSTRAINT [fk_vinculo_bascula] FOREIGN KEY ([id_bascula]) REFERENCES [dbo].[balanzas]([id_balanza]) ON DELETE CASCADE,
        CONSTRAINT [fk_vinculo_indicador] FOREIGN KEY ([id_indicador]) REFERENCES [dbo].[indicadores]([id_indicador]) ON DELETE CASCADE
    );
END;

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_vinculos_empresa' AND object_id = OBJECT_ID('dbo.vinculos_balanza_indicador'))
    CREATE INDEX [idx_vinculos_empresa] ON [dbo].[vinculos_balanza_indicador]([id_empresa]);

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_vinculos_bascula' AND object_id = OBJECT_ID('dbo.vinculos_balanza_indicador'))
    CREATE INDEX [idx_vinculos_bascula] ON [dbo].[vinculos_balanza_indicador]([id_bascula]);
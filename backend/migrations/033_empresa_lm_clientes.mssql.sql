-- Migración 033 para SQL Server: Campos de identidad del cliente del License Manager (LM) en empresa
-- Idempotente: verifica COL_LENGTH antes de añadir cada columna. Prohibido GO.

IF COL_LENGTH('dbo.empresas', 'lm_client_id') IS NULL
BEGIN
    ALTER TABLE dbo.empresas ADD lm_client_id UNIQUEIDENTIFIER NULL;
END

IF COL_LENGTH('dbo.empresas', 'lm_client_email') IS NULL
BEGIN
    ALTER TABLE dbo.empresas ADD lm_client_email NVARCHAR(255) NULL;
END

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'idx_empresa_lm_client_email' AND object_id = OBJECT_ID('dbo.empresas'))
BEGIN
    CREATE INDEX idx_empresa_lm_client_email ON dbo.empresas(lm_client_email);
END

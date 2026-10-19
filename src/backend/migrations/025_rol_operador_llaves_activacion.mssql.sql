-- =============================================================================
-- BALANSOFT-WS · Migración 025 · SQL Server (equivalente a la de PostgreSQL)
-- -----------------------------------------------------------------------------
-- Fusiona el rol TRABAJADOR dentro de OPERADOR y crea `llaves_activacion`.
--
-- NO la aplica el arranque de PostgreSQL: `wserver._migraciones_pendientes`
-- excluye los archivos `*.mssql.sql` (sintaxis de otro motor). Para SQL Server
-- el esquema canónico `sqlserver/balansoft-ws-local.sql` ya incluye el estado
-- final (las migraciones plegadas 001-025), así que este archivo es el
-- equivalente de referencia para instalaciones SQL Server existentes.
-- =============================================================================

BEGIN TRANSACTION;

-- 1. Datos: fusionar TRABAJADOR -> OPERADOR
UPDATE [dbo].[usuarios]
   SET [rol] = N'OPERADOR',
       [updated_at] = SYSUTCDATETIME()
 WHERE [rol] = N'TRABAJADOR';

-- permisos_acceso: la PK es (id_empresa, rol, modulo); borrar antes las filas
-- TRABAJADOR que colisionarían con una OPERADOR ya existente.
DELETE t
  FROM [dbo].[permisos_acceso] t
 WHERE t.[rol] = N'TRABAJADOR'
   AND EXISTS (
       SELECT 1 FROM [dbo].[permisos_acceso] o
        WHERE o.[id_empresa] = t.[id_empresa]
          AND o.[modulo] = t.[modulo]
          AND o.[rol] = N'OPERADOR'
   );

UPDATE [dbo].[permisos_acceso]
   SET [rol] = N'OPERADOR',
       [updated_at] = SYSUTCDATETIME()
 WHERE [rol] = N'TRABAJADOR';

-- 2. llaves_activacion
IF OBJECT_ID(N'dbo.llaves_activacion', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[llaves_activacion] (
        [id] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [id_usuario] UNIQUEIDENTIFIER NOT NULL,
        [codigo_hash] NVARCHAR(255) NOT NULL,
        [codigo_preview] NVARCHAR(40),
        [estado] NVARCHAR(20) DEFAULT N'activa' NOT NULL,
        [expira_en] DATETIME2(6),
        [consumida_en] DATETIME2(6),
        [consumida_por_hw] NVARCHAR(255),
        [ip_consumo] NVARCHAR(45),
        [user_agent] NVARCHAR(255),
        [creado_por] UNIQUEIDENTIFIER,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [chk_estado_llave] CHECK (estado IN (N'activa', N'consumida', N'revocada')),
        CONSTRAINT [llaves_activacion_pkey] PRIMARY KEY (id)
    );
    ALTER TABLE [dbo].[llaves_activacion]
        ADD CONSTRAINT [llaves_activacion_id_empresa_fkey]
        FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas](id_empresa) ON DELETE CASCADE;
    ALTER TABLE [dbo].[llaves_activacion]
        ADD CONSTRAINT [llaves_activacion_id_usuario_fkey]
        FOREIGN KEY (id_usuario) REFERENCES [dbo].[usuarios](id_usuario) ON DELETE CASCADE;
END

-- índices
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_llaves_empresa_usuario') CREATE INDEX idx_llaves_empresa_usuario ON llaves_activacion(id_empresa,id_usuario);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_llaves_estado') CREATE INDEX idx_llaves_estado ON llaves_activacion(estado);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'uq_llaves_codigo_hash') CREATE UNIQUE INDEX uq_llaves_codigo_hash ON llaves_activacion(codigo_hash);

-- 3. CHECK de usuarios y default del rol
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'chk_rol_usuario')
    ALTER TABLE [dbo].[usuarios] DROP CONSTRAINT [chk_rol_usuario];
ALTER TABLE [dbo].[usuarios]
    ADD CONSTRAINT [chk_rol_usuario] CHECK ([rol] IN (N'ADMIN', N'OPERADOR', N'AUDITOR'));

-- El default se cambia solo si aún apunta a TRABAJADOR (idempotente).
IF NOT EXISTS (
    SELECT 1
      FROM sys.default_constraints dc
      JOIN sys.columns c ON c.default_object_id = dc.object_id
     WHERE dc.parent_object_id = OBJECT_ID(N'dbo.usuarios')
       AND c.name = N'rol'
       AND dc.definition LIKE N'%OPERADOR%'
) BEGIN
    DECLARE @df_name SYSNAME;
    SELECT @df_name = dc.name
      FROM sys.default_constraints dc
      JOIN sys.columns c ON c.default_object_id = dc.object_id
     WHERE dc.parent_object_id = OBJECT_ID(N'dbo.usuarios')
       AND c.name = N'rol';
    IF @df_name IS NOT NULL
        EXEC(N'ALTER TABLE [dbo].[usuarios] DROP CONSTRAINT [' + @df_name + N']');
    ALTER TABLE [dbo].[usuarios] ADD CONSTRAINT [df_usuarios_rol] DEFAULT N'OPERADOR' FOR [rol];
END

COMMIT;

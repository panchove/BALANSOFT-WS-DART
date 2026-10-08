-- BALANSOFT-WS - Esquema canónico SQL Server (T-SQL)
-- Generado a partir del pg_dump --schema-only de la BD local migrada.
-- 27 tablas: 26 de negocio + schema_migrations. Idempotente: cada
-- objeto se crea solo si no existe. Prohibido GO: el migrador ejecuta
-- por lotes separados por ';'.
--
-- Equivalencias: UNIQUEIDENTIFIER (UUID), DATETIME2(6) (timestamp naive
-- UTC), NVARCHAR(MAX) (text/jsonb), BIT (boolean), DECIMAL (numeric),
-- SYSUTCDATETIME() en defaults de fechas (UTC), NEWID() en defaults UUID.

BEGIN TRANSACTION;

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;

IF OBJECT_ID(N'dbo.almacenes', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[almacenes] (
        [id_almacen] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [nombre] NVARCHAR(150) NOT NULL,
        [ubicacion] NVARCHAR(255),
        [capacidad_max_ton] DECIMAL(12,2),
        [stock_actual_ton] DECIMAL(12,2) DEFAULT 0 NOT NULL,
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [almacenes_pkey] PRIMARY KEY (id_almacen)
    );
END

IF OBJECT_ID(N'dbo.auditoria', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[auditoria] (
        [id_auditoria] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_usuario] UNIQUEIDENTIFIER,
        [id_empresa] UNIQUEIDENTIFIER,
        [accion] NVARCHAR(100) NOT NULL,
        [entidad] NVARCHAR(50),
        [entidad_id] NVARCHAR(100),
        [detalle] NVARCHAR(MAX),
        [ip] NVARCHAR(50),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [auditoria_pkey] PRIMARY KEY (id_auditoria)
    );
END

IF OBJECT_ID(N'dbo.balanzas', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[balanzas] (
        [id_balanza] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [descripcion] NVARCHAR(150) NOT NULL,
        [marca] NVARCHAR(100),
        [modelo] NVARCHAR(100),
        [capacidad_max] DECIMAL(12,2),
        [division] DECIMAL(12,2),
        [activo] BIT DEFAULT 1 NOT NULL,
        [is_simulada] BIT DEFAULT 0 NOT NULL,
        [puerto_com] NVARCHAR(50),
        [ip_address] NVARCHAR(45),
        [puerto_tcp] INT,
        [protocolo] NVARCHAR(20) DEFAULT N'tcp',
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [balanzas_pkey] PRIMARY KEY (id_balanza)
    );
END

IF OBJECT_ID(N'dbo.boletos_pesaje', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[boletos_pesaje] (
        [boleto] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [numero_boleto] NVARCHAR(30),
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [id_vehiculo] NVARCHAR(20),
        [remolque] BIT DEFAULT 0 NOT NULL,
        [id_remolque] UNIQUEIDENTIFIER,
        [id_transporte] UNIQUEIDENTIFIER,
        [id_conductor] NVARCHAR(20),
        [id_producto] UNIQUEIDENTIFIER,
        [id_almacen] UNIQUEIDENTIFIER,
        [id_balanza] UNIQUEIDENTIFIER,
        [tipo_tercero] NVARCHAR(30),
        [id_tercero] UNIQUEIDENTIFIER,
        [multi_despacho_recepcion] BIT DEFAULT 0 NOT NULL,
        [fecha_hora_entrada] DATETIME2(6) NOT NULL,
        [peso_entrada_vehiculo] DECIMAL(12,2) NOT NULL,
        [peso_entrada_remolque] DECIMAL(12,2),
        [foto_entrada_url] NVARCHAR(MAX),
        [fecha_hora_salida] DATETIME2(6),
        [peso_salida_vehiculo] DECIMAL(12,2),
        [peso_salida_remolque] DECIMAL(12,2),
        [foto_salida_url] NVARCHAR(MAX),
        [documento] NVARCHAR(100),
        [guia_sunagro] NVARCHAR(100),
        [medida] NVARCHAR(50),
        [flete] NVARCHAR(100),
        [costo_flete] DECIMAL(12,2),
        [observaciones] NVARCHAR(MAX),
        [creado_por] NVARCHAR(150),
        [salida_por] NVARCHAR(150),
        [modificado_por] NVARCHAR(150),
        [anulado_por] NVARCHAR(150),
        [motivo_anulacion] NVARCHAR(MAX),
        [peso_total_entrada] DECIMAL(12,2),
        [peso_total_salida] DECIMAL(12,2),
        [peso_neto] DECIMAL(12,2),
        [peso_neto_declarado] DECIMAL(12,2),
        [peso_diferencia] DECIMAL(12,2),
        [porcentaje_desviacion] DECIMAL(8,4),
        [peso_bruto] DECIMAL(12,2),
        [peso_tara] DECIMAL(12,2),
        [diferencia_peso] DECIMAL(12,2),
        [porcentaje_diferencia] DECIMAL(8,4),
        [densidad] DECIMAL(8,4),
        [litros] DECIMAL(12,2),
        [unidades] DECIMAL(12,2),
        [estado_boleto] NVARCHAR(20) DEFAULT N'PENDIENTE' NOT NULL,
        [es_peso_manual] BIT DEFAULT 0 NOT NULL,
        [sincronizado] BIT DEFAULT 0 NOT NULL,
        [sync_intentos] INT DEFAULT 0 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [id_serie] UNIQUEIDENTIFIER,
        CONSTRAINT [boletos_pesaje_peso_entrada_vehiculo_check] CHECK ((peso_entrada_vehiculo >= (0))),
        CONSTRAINT [boletos_pesaje_pkey] PRIMARY KEY (boleto)
    );
END

IF OBJECT_ID(N'dbo.camiones', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[camiones] (
        [id] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [placa] NVARCHAR(20) NOT NULL,
        [modelo_id] UNIQUEIDENTIFIER,
        [transporte_id] UNIQUEIDENTIFIER,
        [color] NVARCHAR(50),
        [foto_real_url] NVARCHAR(500),
        [tara_habitual] DECIMAL(12,2),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [camiones_pkey] PRIMARY KEY (id)
    );
END

IF OBJECT_ID(N'dbo.categorias', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[categorias] (
        [id_categoria] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(50),
        [nombre] NVARCHAR(150) NOT NULL,
        [descripcion] NVARCHAR(200),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [categorias_pkey] PRIMARY KEY (id_categoria)
    );
END

IF OBJECT_ID(N'dbo.conductores', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[conductores] (
        [cedula_dni] NVARCHAR(20) NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [nombre_completo] NVARCHAR(200) NOT NULL,
        [telefono] NVARCHAR(50),
        [licencia_conducir] NVARCHAR(50),
        [foto_url] NVARCHAR(500),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [conductores_pkey] PRIMARY KEY (cedula_dni)
    );
END

IF OBJECT_ID(N'dbo.configuraciones', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[configuraciones] (
        [clave] NVARCHAR(100) NOT NULL,
        [valor] NVARCHAR(MAX),
        [descripcion] NVARCHAR(MAX),
        [id_empresa] UNIQUEIDENTIFIER,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [configuraciones_pkey] PRIMARY KEY (clave)
    );
END

IF OBJECT_ID(N'dbo.empresas', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[empresas] (
        [id_empresa] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_cuenta] UNIQUEIDENTIFIER,
        [nombre_fiscal] NVARCHAR(255) NOT NULL,
        [nombre_comercial] NVARCHAR(255),
        [rif_nit] NVARCHAR(20) NOT NULL,
        [direccion] NVARCHAR(MAX),
        [telefono] NVARCHAR(50),
        [email] NVARCHAR(255),
        [logo_url] NVARCHAR(500),
        [formato_ticket] NVARCHAR(10) DEFAULT N'PDF',
        [formato_reporte] NVARCHAR(10) DEFAULT N'EXCEL',
        [idioma] NVARCHAR(5) DEFAULT N'es',
        [ruta_exportacion_reportes] NVARCHAR(500),
        [tamano_ticket_pdf] NVARCHAR(20) DEFAULT N'AUTOMATICO',
        [fuente_ticket_pdf] NVARCHAR(20) DEFAULT N'DejaVu',
        [licencia_key] NVARCHAR(255),
        [licencia_tier] NVARCHAR(20),
        [licencia_status] NVARCHAR(20),
        [licencia_expira] DATETIME2(6),
        [activa] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [ck_empresas_formato_reporte] CHECK ((formato_reporte) IN (N'EXCEL', N'PDF')),
        CONSTRAINT [ck_empresas_formato_ticket] CHECK ((formato_ticket) IN (N'PDF', N'TXT')),
        CONSTRAINT [ck_empresas_fuente_ticket_pdf] CHECK (((fuente_ticket_pdf) = N'DejaVu')),
        CONSTRAINT [ck_empresas_idioma] CHECK ((idioma) IN (N'es', N'en', N'pt')),
        CONSTRAINT [ck_empresas_tamano_ticket_pdf] CHECK ((tamano_ticket_pdf) IN (N'AUTOMATICO', N'GRANDE', N'MEDIANO', N'PEQUENO')),
        CONSTRAINT [empresas_pkey] PRIMARY KEY (id_empresa)
    );
END

IF OBJECT_ID(N'dbo.identidad_local', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[identidad_local] (
        [id] BIT DEFAULT 1 NOT NULL,
        [id_cuenta] UNIQUEIDENTIFIER NOT NULL,
        [rif_nit] NVARCHAR(20) NOT NULL,
        [nombre_fiscal] NVARCHAR(255) NOT NULL,
        [nombre_comercial] NVARCHAR(255),
        [licencia_key] NVARCHAR(255),
        [licencia_tier] NVARCHAR(20),
        [licencia_status] NVARCHAR(20),
        [licencia_expira] DATETIME2(6),
        [hardware_id] NVARCHAR(255),
        [rol_dispositivo] NVARCHAR(20) DEFAULT N'LOCAL' NOT NULL,
        [ultima_validacion] DATETIME2(6),
        [modo_offline] BIT DEFAULT 0 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [identidad_local_id_check] CHECK ((id = 1)),
        CONSTRAINT [identidad_local_pkey] PRIMARY KEY (id)
    );
END

IF OBJECT_ID(N'dbo.imagenes_pesaje', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[imagenes_pesaje] (
        [id_imagen] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [boleto] UNIQUEIDENTIFIER NOT NULL,
        [tipo] NVARCHAR(30) NOT NULL,
        [url] NVARCHAR(MAX) NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [imagenes_pesaje_pkey] PRIMARY KEY (id_imagen)
    );
END

IF OBJECT_ID(N'dbo.kardex', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[kardex] (
        [id_kardex] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [id_movimiento] INT NOT NULL,
        [fecha_kardex] DATETIME2(6) NOT NULL,
        [id_producto] UNIQUEIDENTIFIER,
        [id_almacen] UNIQUEIDENTIFIER,
        [fecha_documento] DATETIME2(6),
        [documento] NVARCHAR(100),
        [valor] DECIMAL(12,2) NOT NULL,
        [boleto] UNIQUEIDENTIFIER,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [kardex_pkey] PRIMARY KEY (id_kardex)
    );
END

IF OBJECT_ID(N'dbo.logs_sistema', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[logs_sistema] (
        [id_log] BIGINT IDENTITY(1,1) NOT NULL,
        [nivel] NVARCHAR(10) NOT NULL,
        [modulo] NVARCHAR(50),
        [mensaje] NVARCHAR(MAX) NOT NULL,
        [detalle] NVARCHAR(MAX),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [logs_sistema_pkey] PRIMARY KEY (id_log)
    );
END

IF OBJECT_ID(N'dbo.marcas', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[marcas] (
        [id_marca] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [nombre] NVARCHAR(100) NOT NULL,
        [logo_url] NVARCHAR(500),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [marcas_pkey] PRIMARY KEY (id_marca)
    );
END

IF OBJECT_ID(N'dbo.modelos_camion', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[modelos_camion] (
        [id_modelo_camion] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [marca_id] UNIQUEIDENTIFIER,
        [nombre] NVARCHAR(100) NOT NULL,
        [capacidad_carga_ton] DECIMAL(12,2),
        [foto_referencial_url] NVARCHAR(500),
        [ejes] INT,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [modelos_camion_pkey] PRIMARY KEY (id_modelo_camion)
    );
END

IF OBJECT_ID(N'dbo.parametros_sistema', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[parametros_sistema] (
        [parametro] NVARCHAR(100) NOT NULL,
        [valor] NVARCHAR(MAX),
        [grupo] NVARCHAR(50),
        [descripcion] NVARCHAR(MAX),
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [parametros_sistema_pkey] PRIMARY KEY (parametro)
    );
END

IF OBJECT_ID(N'dbo.password_reset_tokens', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[password_reset_tokens] (
        [id] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_usuario] UNIQUEIDENTIFIER NOT NULL,
        [token_hash] NVARCHAR(128) NOT NULL,
        [expira] DATETIME2(6) NOT NULL,
        [usado] BIT DEFAULT 0 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [password_reset_tokens_pkey] PRIMARY KEY (id)
    );
END

IF OBJECT_ID(N'dbo.permisos_acceso', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[permisos_acceso] (
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [rol] NVARCHAR(30) NOT NULL,
        [modulo] NVARCHAR(50) NOT NULL,
        [acceso] NVARCHAR(20) DEFAULT N'ver' NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [permisos_acceso_pkey] PRIMARY KEY (id_empresa, rol, modulo)
    );
END

IF OBJECT_ID(N'dbo.productos', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[productos] (
        [id_producto] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [id_categoria] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(50),
        [nombre] NVARCHAR(150) NOT NULL,
        [descripcion] NVARCHAR(200),
        [densidad_estandar] DECIMAL(8,4),
        [unidad_medida] NVARCHAR(20) DEFAULT N'TON' NOT NULL,
        [es_kardex] BIT DEFAULT 0 NOT NULL,
        [tolerancia] DECIMAL(8,4),
        [peso_unidad] DECIMAL(12,4),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [productos_pkey] PRIMARY KEY (id_producto)
    );
END

IF OBJECT_ID(N'dbo.remolques', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[remolques] (
        [id_remolque] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [placa] NVARCHAR(20) NOT NULL,
        [tipo_remolque] NVARCHAR(100),
        [tara_habitual] DECIMAL(12,2),
        [foto_url] NVARCHAR(500),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [remolques_pkey] PRIMARY KEY (id_remolque)
    );
END

IF OBJECT_ID(N'dbo.schema_migrations', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[schema_migrations] (
        [version] NVARCHAR(255) NOT NULL,
        [aplicada_en] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [schema_migrations_pkey] PRIMARY KEY (version)
    );
END

IF OBJECT_ID(N'dbo.series_numeracion', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[series_numeracion] (
        [id_serie] UNIQUEIDENTIFIER NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [nombre] NVARCHAR(80) NOT NULL,
        [prefijo] NVARCHAR(20) NOT NULL,
        [inicio] INT DEFAULT 1 NOT NULL,
        [siguiente] INT NOT NULL,
        [digitos] INT DEFAULT 8 NOT NULL,
        [activa] BIT DEFAULT 0 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [chk_serie_prefijo_no_vacio] CHECK ((LTRIM(RTRIM([prefijo])) <> N'')),
        CONSTRAINT [series_numeracion_digitos_check] CHECK ((digitos >= 1) AND (digitos <= 20)),
        CONSTRAINT [series_numeracion_inicio_check] CHECK ((inicio >= 1)),
        CONSTRAINT [series_numeracion_pkey] PRIMARY KEY (id_serie)
    );
END

IF OBJECT_ID(N'dbo.sync_logs', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[sync_logs] (
        [id_log] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER,
        [tipo] NVARCHAR(30) NOT NULL,
        [entidad] NVARCHAR(50),
        [registros] INT DEFAULT 0 NOT NULL,
        [errores] INT DEFAULT 0 NOT NULL,
        [detalle] NVARCHAR(MAX),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [sync_logs_pkey] PRIMARY KEY (id_log)
    );
END

IF OBJECT_ID(N'dbo.sync_queue', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[sync_queue] (
        [id_sync] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [entidad] NVARCHAR(50) NOT NULL,
        [operacion] NVARCHAR(20) NOT NULL,
        [entidad_id] NVARCHAR(100) NOT NULL,
        [payload] NVARCHAR(MAX) NOT NULL,
        [pendiente] BIT DEFAULT 1 NOT NULL,
        [intentos] INT DEFAULT 0 NOT NULL,
        [error] NVARCHAR(MAX),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [sync_queue_pkey] PRIMARY KEY (id_sync)
    );
END

IF OBJECT_ID(N'dbo.terceros', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[terceros] (
        [id_tercero] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [tipo] NVARCHAR(30) NOT NULL,
        [razon_social] NVARCHAR(200) NOT NULL,
        [identificacion_fiscal] NVARCHAR(20),
        [direccion] NVARCHAR(MAX),
        [telefono] NVARCHAR(50),
        [email] NVARCHAR(255),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [terceros_pkey] PRIMARY KEY (id_tercero)
    );
END

IF OBJECT_ID(N'dbo.transportes', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[transportes] (
        [id_transporte] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [codigo] NVARCHAR(20),
        [razon_social] NVARCHAR(150) NOT NULL,
        [identificacion_fiscal] NVARCHAR(20),
        [telefono] NVARCHAR(50),
        [contacto] NVARCHAR(150),
        [activo] BIT DEFAULT 1 NOT NULL,
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [transportes_pkey] PRIMARY KEY (id_transporte)
    );
END

IF OBJECT_ID(N'dbo.usuarios', N'U') IS NULL BEGIN
    CREATE TABLE [dbo].[usuarios] (
        [id_usuario] UNIQUEIDENTIFIER DEFAULT NEWID() NOT NULL,
        [id_empresa] UNIQUEIDENTIFIER NOT NULL,
        [id_credencial] UNIQUEIDENTIFIER,
        [nombre] NVARCHAR(150) NOT NULL,
        [email] NVARCHAR(255) NOT NULL,
        [password_hash] NVARCHAR(255),
        [rol] NVARCHAR(30) DEFAULT N'TRABAJADOR' NOT NULL,
        [activo] BIT DEFAULT 1 NOT NULL,
        [ultimo_login] DATETIME2(6),
        [created_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        [updated_at] DATETIME2(6) DEFAULT SYSUTCDATETIME() NOT NULL,
        CONSTRAINT [chk_rol_usuario] CHECK ((rol) IN (N'ADMIN', N'OPERADOR', N'AUDITOR', N'TRABAJADOR')),
        CONSTRAINT [usuarios_pkey] PRIMARY KEY (id_usuario)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'almacenes_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[almacenes] ADD CONSTRAINT [almacenes_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'auditoria_id_usuario_fkey' ) BEGIN
    ALTER TABLE [dbo].[auditoria] ADD CONSTRAINT [auditoria_id_usuario_fkey] FOREIGN KEY (id_usuario) REFERENCES [dbo].[usuarios] (id_usuario);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'balanzas_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[balanzas] ADD CONSTRAINT [balanzas_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_almacen_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_almacen_fkey] FOREIGN KEY (id_almacen) REFERENCES [dbo].[almacenes] (id_almacen);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_balanza_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_balanza_fkey] FOREIGN KEY (id_balanza) REFERENCES [dbo].[balanzas] (id_balanza);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_conductor_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_conductor_fkey] FOREIGN KEY (id_conductor) REFERENCES [dbo].[conductores] (cedula_dni);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_producto_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_producto_fkey] FOREIGN KEY (id_producto) REFERENCES [dbo].[productos] (id_producto);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_remolque_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_remolque_fkey] FOREIGN KEY (id_remolque) REFERENCES [dbo].[remolques] (id_remolque);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_tercero_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_tercero_fkey] FOREIGN KEY (id_tercero) REFERENCES [dbo].[terceros] (id_tercero);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'boletos_pesaje_id_transporte_fkey' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [boletos_pesaje_id_transporte_fkey] FOREIGN KEY (id_transporte) REFERENCES [dbo].[transportes] (id_transporte);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'camiones_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[camiones] ADD CONSTRAINT [camiones_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'camiones_modelo_id_fkey' ) BEGIN
    ALTER TABLE [dbo].[camiones] ADD CONSTRAINT [camiones_modelo_id_fkey] FOREIGN KEY (modelo_id) REFERENCES [dbo].[modelos_camion] (id_modelo_camion);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'camiones_transporte_id_fkey' ) BEGIN
    ALTER TABLE [dbo].[camiones] ADD CONSTRAINT [camiones_transporte_id_fkey] FOREIGN KEY (transporte_id) REFERENCES [dbo].[transportes] (id_transporte);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'categorias_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[categorias] ADD CONSTRAINT [categorias_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'conductores_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[conductores] ADD CONSTRAINT [conductores_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'configuraciones_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[configuraciones] ADD CONSTRAINT [configuraciones_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_boletos_pesaje_id_serie' ) BEGIN
    ALTER TABLE [dbo].[boletos_pesaje] ADD CONSTRAINT [fk_boletos_pesaje_id_serie] FOREIGN KEY (id_serie) REFERENCES [dbo].[series_numeracion] (id_serie) ON DELETE SET NULL;
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'fk_productos_categorias' ) BEGIN
    ALTER TABLE [dbo].[productos] ADD CONSTRAINT [fk_productos_categorias] FOREIGN KEY (id_categoria) REFERENCES [dbo].[categorias] (id_categoria);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'imagenes_pesaje_boleto_fkey' ) BEGIN
    ALTER TABLE [dbo].[imagenes_pesaje] ADD CONSTRAINT [imagenes_pesaje_boleto_fkey] FOREIGN KEY (boleto) REFERENCES [dbo].[boletos_pesaje] (boleto) ON DELETE CASCADE;
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'kardex_boleto_fkey' ) BEGIN
    ALTER TABLE [dbo].[kardex] ADD CONSTRAINT [kardex_boleto_fkey] FOREIGN KEY (boleto) REFERENCES [dbo].[boletos_pesaje] (boleto);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'kardex_id_almacen_fkey' ) BEGIN
    ALTER TABLE [dbo].[kardex] ADD CONSTRAINT [kardex_id_almacen_fkey] FOREIGN KEY (id_almacen) REFERENCES [dbo].[almacenes] (id_almacen);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'kardex_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[kardex] ADD CONSTRAINT [kardex_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'kardex_id_producto_fkey' ) BEGIN
    ALTER TABLE [dbo].[kardex] ADD CONSTRAINT [kardex_id_producto_fkey] FOREIGN KEY (id_producto) REFERENCES [dbo].[productos] (id_producto);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'marcas_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[marcas] ADD CONSTRAINT [marcas_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'modelos_camion_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[modelos_camion] ADD CONSTRAINT [modelos_camion_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'modelos_camion_marca_id_fkey' ) BEGIN
    ALTER TABLE [dbo].[modelos_camion] ADD CONSTRAINT [modelos_camion_marca_id_fkey] FOREIGN KEY (marca_id) REFERENCES [dbo].[marcas] (id_marca);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'password_reset_tokens_id_usuario_fkey' ) BEGIN
    ALTER TABLE [dbo].[password_reset_tokens] ADD CONSTRAINT [password_reset_tokens_id_usuario_fkey] FOREIGN KEY (id_usuario) REFERENCES [dbo].[usuarios] (id_usuario) ON DELETE CASCADE;
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'permisos_acceso_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[permisos_acceso] ADD CONSTRAINT [permisos_acceso_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'productos_id_categoria_fkey' ) BEGIN
    ALTER TABLE [dbo].[productos] ADD CONSTRAINT [productos_id_categoria_fkey] FOREIGN KEY (id_categoria) REFERENCES [dbo].[categorias] (id_categoria);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'productos_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[productos] ADD CONSTRAINT [productos_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'remolques_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[remolques] ADD CONSTRAINT [remolques_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'series_numeracion_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[series_numeracion] ADD CONSTRAINT [series_numeracion_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa) ON DELETE CASCADE;
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'sync_queue_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[sync_queue] ADD CONSTRAINT [sync_queue_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'terceros_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[terceros] ADD CONSTRAINT [terceros_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'transportes_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[transportes] ADD CONSTRAINT [transportes_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'usuarios_id_empresa_fkey' ) BEGIN
    ALTER TABLE [dbo].[usuarios] ADD CONSTRAINT [usuarios_id_empresa_fkey] FOREIGN KEY (id_empresa) REFERENCES [dbo].[empresas] (id_empresa);
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'almacenes_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [almacenes_empresa_codigo_uk] ON [dbo].[almacenes] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'balanzas_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [balanzas_empresa_codigo_uk] ON [dbo].[balanzas] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'categorias_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [categorias_empresa_codigo_uk] ON [dbo].[categorias] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_almacenes_empresa' ) BEGIN
    CREATE INDEX [idx_almacenes_empresa] ON [dbo].[almacenes] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_auditoria_fecha' ) BEGIN
    CREATE INDEX [idx_auditoria_fecha] ON [dbo].[auditoria] (created_at);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_auditoria_usuario' ) BEGIN
    CREATE INDEX [idx_auditoria_usuario] ON [dbo].[auditoria] (id_usuario);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_boletos_pesaje_conductor' ) BEGIN
    CREATE INDEX [idx_boletos_pesaje_conductor] ON [dbo].[boletos_pesaje] (id_conductor);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_boletos_pesaje_estado' ) BEGIN
    CREATE INDEX [idx_boletos_pesaje_estado] ON [dbo].[boletos_pesaje] (estado_boleto);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_boletos_pesaje_fechas' ) BEGIN
    CREATE INDEX [idx_boletos_pesaje_fechas] ON [dbo].[boletos_pesaje] (fecha_hora_entrada, fecha_hora_salida);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_boletos_pesaje_producto' ) BEGIN
    CREATE INDEX [idx_boletos_pesaje_producto] ON [dbo].[boletos_pesaje] (id_producto);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_boletos_pesaje_sync' ) BEGIN
    CREATE INDEX [idx_boletos_pesaje_sync] ON [dbo].[boletos_pesaje] (sincronizado);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_boletos_pesaje_vehiculo' ) BEGIN
    CREATE INDEX [idx_boletos_pesaje_vehiculo] ON [dbo].[boletos_pesaje] (id_vehiculo);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_camiones_empresa' ) BEGIN
    CREATE INDEX [idx_camiones_empresa] ON [dbo].[camiones] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_camiones_placa' ) BEGIN
    CREATE INDEX [idx_camiones_placa] ON [dbo].[camiones] (placa);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_kardex_empresa_fecha' ) BEGIN
    CREATE INDEX [idx_kardex_empresa_fecha] ON [dbo].[kardex] (id_empresa, fecha_kardex);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_kardex_producto_almacen' ) BEGIN
    CREATE INDEX [idx_kardex_producto_almacen] ON [dbo].[kardex] (id_producto, id_almacen);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_modelos_marca' ) BEGIN
    CREATE INDEX [idx_modelos_marca] ON [dbo].[modelos_camion] (marca_id);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_password_reset_usuario' ) BEGIN
    CREATE INDEX [idx_password_reset_usuario] ON [dbo].[password_reset_tokens] (id_usuario, usado);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_productos_empresa' ) BEGIN
    CREATE INDEX [idx_productos_empresa] ON [dbo].[productos] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_remolques_empresa' ) BEGIN
    CREATE INDEX [idx_remolques_empresa] ON [dbo].[remolques] (id_empresa, placa);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_sync_queue_pend' ) BEGIN
    CREATE INDEX [idx_sync_queue_pend] ON [dbo].[sync_queue] (pendiente, intentos);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_usuarios_empresa' ) BEGIN
    CREATE INDEX [idx_usuarios_empresa] ON [dbo].[usuarios] (id_empresa);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_usuarios_id_credencial' ) BEGIN
    CREATE INDEX [idx_usuarios_id_credencial] ON [dbo].[usuarios] (id_credencial);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'idx_usuarios_rol' ) BEGIN
    CREATE INDEX [idx_usuarios_rol] ON [dbo].[usuarios] (rol, activo);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_productos_id_categoria' ) BEGIN
    CREATE INDEX [ix_productos_id_categoria] ON [dbo].[productos] (id_categoria);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'productos_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [productos_empresa_codigo_uk] ON [dbo].[productos] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'terceros_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [terceros_empresa_codigo_uk] ON [dbo].[terceros] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'transportes_empresa_codigo_uk' ) BEGIN
    CREATE UNIQUE INDEX [transportes_empresa_codigo_uk] ON [dbo].[transportes] (id_empresa, codigo) WHERE (codigo IS NOT NULL);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'uq_boletos_pesaje_numero' ) BEGIN
    CREATE UNIQUE INDEX [uq_boletos_pesaje_numero] ON [dbo].[boletos_pesaje] (numero_boleto) WHERE (numero_boleto IS NOT NULL);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'uq_camiones_empresa_placa' ) BEGIN
    CREATE UNIQUE INDEX [uq_camiones_empresa_placa] ON [dbo].[camiones] (id_empresa, placa);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'uq_marcas_empresa_nombre' ) BEGIN
    CREATE UNIQUE INDEX [uq_marcas_empresa_nombre] ON [dbo].[marcas] (id_empresa, nombre);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'uq_modelos_empresa_nombre' ) BEGIN
    CREATE UNIQUE INDEX [uq_modelos_empresa_nombre] ON [dbo].[modelos_camion] (id_empresa, nombre);
END
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'uq_series_numeracion_activa_empresa' ) BEGIN
    CREATE UNIQUE INDEX [uq_series_numeracion_activa_empresa] ON [dbo].[series_numeracion] (id_empresa) WHERE (activa = 1);
END

COMMIT;

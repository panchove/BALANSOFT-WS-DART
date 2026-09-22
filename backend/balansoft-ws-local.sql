-- ============================================================
-- BALANSOFT-WS-LOCAL - SCHEMA OPERATIVO (MÁQUINA DEL CLIENTE)
-- Una sola empresa por máquina. Contiene TODO lo operativo:
-- usuarios locales con roles, flota, inventario, boletos,
-- kardex, auditoría local, configuración, etc.
-- Se sincroniza con balansoft_ws (servidor) mediante sync.
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 0. IDENTIDAD LOCAL (vínculo con la cuenta del servidor)
-- Solo una fila. Guarda el id_cuenta y datos de la licencia
-- cacheados para permitir trabajo offline.
-- ============================================================
CREATE TABLE IF NOT EXISTS identidad_local (
    id                  BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id = TRUE), -- solo 1 fila
    id_cuenta           UUID NOT NULL,           -- FK lógica a balansoft_ws.cuentas
    rif_nit             VARCHAR(20) NOT NULL,
    nombre_fiscal       VARCHAR(255) NOT NULL,
    nombre_comercial    VARCHAR(255),
    licencia_key        VARCHAR(255),
    licencia_tier       VARCHAR(20),
    licencia_status     VARCHAR(20),
    licencia_expira     TIMESTAMP,
    hardware_id         VARCHAR(255),            -- huella de esta máquina
    rol_dispositivo     VARCHAR(20) NOT NULL DEFAULT 'LOCAL', -- LOCAL / SERVIDOR_LOCAL
    ultima_validacion   TIMESTAMP,               -- última vez que se validó online
    modo_offline        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 1. EMPRESA (espejo local de la cuenta, para FKs internas)
-- ============================================================
CREATE TABLE IF NOT EXISTS empresas (
    id_empresa       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID,                          -- vínculo 1:1 con la cuenta del servidor
    nombre_fiscal    VARCHAR(255) NOT NULL,
    nombre_comercial VARCHAR(255),
    rif_nit          VARCHAR(20) NOT NULL UNIQUE,
    direccion        TEXT,
    telefono         VARCHAR(50),
    email            VARCHAR(255),
    logo_url         VARCHAR(500),
    formato_ticket   VARCHAR(10) DEFAULT 'PDF',
    ruta_exportacion_reportes VARCHAR(500),
    -- Snapshot de la licencia (validada contra el servidor central en login)
    licencia_key     VARCHAR(255),
    licencia_tier    VARCHAR(20),
    licencia_status  VARCHAR(20),
    licencia_expira  TIMESTAMP,
    activa           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Alineación idempotente para BDs creadas antes del snapshot de licencia.
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_key VARCHAR(255);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_tier VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_status VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_expira TIMESTAMP;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS formato_ticket VARCHAR(10);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS ruta_exportacion_reportes VARCHAR(500);
ALTER TABLE empresas ALTER COLUMN id_cuenta DROP NOT NULL;

-- ============================================================
-- 2. USUARIOS LOCALES (creados por el ADMIN local)
-- Roles: ADMIN / OPERADOR / AUDITOR / TRABAJADOR
-- El login se valida contra el servidor, pero el perfil
-- operativo vive aquí.
-- ============================================================
CREATE TABLE IF NOT EXISTS usuarios (
    id_usuario       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa       UUID NOT NULL REFERENCES empresas(id_empresa),
    -- Vínculo con la credencial global del servidor
    id_credencial    UUID,                       -- FK lógica a balansoft_ws.credenciales
    nombre           VARCHAR(150) NOT NULL,
    email            VARCHAR(255) NOT NULL UNIQUE,
    password_hash    VARCHAR(255),               -- caché local para modo offline
    rol              VARCHAR(30) NOT NULL DEFAULT 'TRABAJADOR',
                     -- ADMIN / OPERADOR / AUDITOR / TRABAJADOR
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    ultimo_login     TIMESTAMP,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_rol_usuario CHECK (rol IN ('ADMIN','OPERADOR','AUDITOR','TRABAJADOR'))
);

CREATE INDEX IF NOT EXISTS idx_usuarios_empresa ON usuarios (id_empresa);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol ON usuarios (rol, activo);

-- ============================================================
-- 3. DIRECTORIO / TRANSPORTES
-- ============================================================
CREATE TABLE IF NOT EXISTS transportes (
    id_transporte         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa            UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo                VARCHAR(20),
    razon_social          VARCHAR(150) NOT NULL,
    identificacion_fiscal VARCHAR(20),
    telefono              VARCHAR(50),
    contacto              VARCHAR(150),
    activo                BOOLEAN NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 4. FLOTA
-- ============================================================
CREATE TABLE IF NOT EXISTS marcas (
    id_marca     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa   UUID NOT NULL REFERENCES empresas(id_empresa),
    nombre       VARCHAR(100) NOT NULL,
    logo_url     VARCHAR(500),
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_marcas_empresa_nombre ON marcas (id_empresa, nombre);

CREATE TABLE IF NOT EXISTS modelos_camion (
    id_modelo_camion     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa           UUID NOT NULL REFERENCES empresas(id_empresa),
    marca_id             UUID REFERENCES marcas(id_marca),
    nombre               VARCHAR(100) NOT NULL,
    capacidad_carga_ton  NUMERIC(12,2),
    foto_referencial_url VARCHAR(500),
    ejes                 INTEGER,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_modelos_empresa_nombre ON modelos_camion (id_empresa, nombre);

CREATE TABLE IF NOT EXISTS camiones (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    placa         VARCHAR(20) NOT NULL,
    modelo_id     UUID REFERENCES modelos_camion(id_modelo_camion),
    transporte_id UUID REFERENCES transportes(id_transporte),
    color         VARCHAR(50),
    foto_real_url VARCHAR(500),
    tara_habitual NUMERIC(12,2),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_camiones_empresa_placa ON camiones (id_empresa, placa);

CREATE TABLE IF NOT EXISTS remolques (
    id_remolque   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    placa         VARCHAR(20) NOT NULL,
    tipo_remolque VARCHAR(100),
    tara_habitual NUMERIC(12,2),
    foto_url      VARCHAR(500),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_remolques_empresa ON remolques (id_empresa, placa);

-- ============================================================
-- 5. DIRECTORIO (conductores, terceros)
-- ============================================================
CREATE TABLE IF NOT EXISTS conductores (
    cedula_dni        VARCHAR(20) PRIMARY KEY,
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    nombre_completo   VARCHAR(200) NOT NULL,
    telefono          VARCHAR(50),
    licencia_conducir VARCHAR(50),
    foto_url          VARCHAR(500),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS terceros (
    id_tercero            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa            UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo                VARCHAR(20),
    tipo                  VARCHAR(30) NOT NULL,
    razon_social          VARCHAR(200) NOT NULL,
    identificacion_fiscal VARCHAR(20),
    direccion             TEXT,
    telefono              VARCHAR(50),
    email                 VARCHAR(255),
    activo                BOOLEAN NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 6. INVENTARIO
-- ============================================================
CREATE TABLE IF NOT EXISTS categorias (
    id_categoria      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo            VARCHAR(50),
    nombre            VARCHAR(150) NOT NULL,
    descripcion       VARCHAR(200),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS productos (
    id_producto       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    id_categoria      UUID NOT NULL REFERENCES categorias(id_categoria),
    codigo            VARCHAR(50),
    nombre            VARCHAR(150) NOT NULL,
    descripcion       VARCHAR(200),
    densidad_estandar NUMERIC(8,4),
    unidad_medida     VARCHAR(20) NOT NULL DEFAULT 'TON',
    es_kardex         BOOLEAN NOT NULL DEFAULT FALSE,
    tolerancia        NUMERIC(8,4),
    peso_unidad       NUMERIC(12,4),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS almacenes (
    id_almacen        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo            VARCHAR(20),
    nombre            VARCHAR(150) NOT NULL,
    ubicacion         VARCHAR(255),
    capacidad_max_ton NUMERIC(12,2),
    stock_actual_ton  NUMERIC(12,2) NOT NULL DEFAULT 0,
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS balanzas (
    id_balanza    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo        VARCHAR(20),
    descripcion   VARCHAR(150) NOT NULL,
    marca         VARCHAR(100),
    modelo        VARCHAR(100),
    capacidad_max NUMERIC(12,2),
    division      NUMERIC(12,2),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulada   BOOLEAN NOT NULL DEFAULT FALSE,
    puerto_com    VARCHAR(50),
    ip_address    VARCHAR(45),
    puerto_tcp    INTEGER,
    protocolo     VARCHAR(20) DEFAULT 'tcp',
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 7. TRANSACCIONAL - BOLETOS DE PESAJE
-- ============================================================
CREATE TABLE IF NOT EXISTS boletos_pesaje (
    boleto                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_boleto            VARCHAR(30) UNIQUE,
    id_empresa               UUID NOT NULL REFERENCES empresas(id_empresa),
    id_vehiculo              VARCHAR(20),
    remolque                 BOOLEAN NOT NULL DEFAULT FALSE,
    id_remolque              UUID REFERENCES remolques(id_remolque),
    id_transporte            UUID REFERENCES transportes(id_transporte),
    id_conductor             VARCHAR(20) REFERENCES conductores(cedula_dni),
    id_producto              UUID REFERENCES productos(id_producto),
    id_almacen               UUID REFERENCES almacenes(id_almacen),
    id_balanza               UUID REFERENCES balanzas(id_balanza),
    tipo_tercero             VARCHAR(30),
    id_tercero               UUID REFERENCES terceros(id_tercero),
    multi_despacho_recepcion BOOLEAN NOT NULL DEFAULT FALSE,

    fecha_hora_entrada       TIMESTAMP NOT NULL,
    peso_entrada_vehiculo    NUMERIC(12,2) NOT NULL CHECK (peso_entrada_vehiculo >= 0),
    peso_entrada_remolque    NUMERIC(12,2),
    foto_entrada_url         TEXT,

    fecha_hora_salida        TIMESTAMP,
    peso_salida_vehiculo     NUMERIC(12,2),
    peso_salida_remolque     NUMERIC(12,2),
    foto_salida_url          TEXT,

    documento                VARCHAR(100),
    flete                    VARCHAR(100),
    costo_flete              NUMERIC(12,2),
    observaciones            TEXT,

    -- Auditoría de operativas
    creado_por               VARCHAR(150),
    salida_por               VARCHAR(150),
    modificado_por           VARCHAR(150),
    anulado_por              VARCHAR(150),
    motivo_anulacion         TEXT,

    -- Cálculos MODEL.md
    peso_total_entrada       NUMERIC(12,2),
    peso_total_salida        NUMERIC(12,2),
    peso_neto                NUMERIC(12,2),
    peso_neto_declarado      NUMERIC(12,2),
    peso_diferencia          NUMERIC(12,2),
    porcentaje_desviacion    NUMERIC(8,4),

    -- Campos legacy
    peso_bruto               NUMERIC(12,2),
    peso_tara                NUMERIC(12,2),
    diferencia_peso          NUMERIC(12,2),
    porcentaje_diferencia    NUMERIC(8,4),
    densidad                 NUMERIC(8,4),
    litros                   NUMERIC(12,2),
    unidades                 NUMERIC(12,2),

    estado_boleto            VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    sincronizado             BOOLEAN NOT NULL DEFAULT FALSE,
    sync_intentos            INTEGER NOT NULL DEFAULT 0,
    created_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS imagenes_pesaje (
    id_imagen     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boleto        UUID NOT NULL REFERENCES boletos_pesaje(boleto) ON DELETE CASCADE,
    tipo          VARCHAR(30) NOT NULL,
    url           TEXT NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 8. KARDEX
-- ============================================================
CREATE TABLE IF NOT EXISTS kardex (
    id_kardex       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    id_movimiento   INTEGER NOT NULL,
    fecha_kardex    TIMESTAMP NOT NULL,
    id_producto     UUID REFERENCES productos(id_producto),
    id_almacen      UUID REFERENCES almacenes(id_almacen),
    fecha_documento TIMESTAMP,
    documento       VARCHAR(100),
    valor           NUMERIC(12,2) NOT NULL,
    boleto          UUID REFERENCES boletos_pesaje(boleto),
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_kardex_empresa_fecha ON kardex (id_empresa, fecha_kardex);
CREATE INDEX IF NOT EXISTS idx_kardex_producto_almacen ON kardex (id_producto, id_almacen);

-- ============================================================
-- 9. SINCRONIZACIÓN LOCAL (cola que se envía al servidor)
-- ============================================================
CREATE TABLE IF NOT EXISTS sync_queue (
    id_sync       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    entidad       VARCHAR(50) NOT NULL,
    operacion     VARCHAR(20) NOT NULL,
    entidad_id    VARCHAR(100) NOT NULL,
    payload       JSONB NOT NULL,
    pendiente     BOOLEAN NOT NULL DEFAULT TRUE,
    intentos      INTEGER NOT NULL DEFAULT 0,
    error         TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sync_logs (
    id_log        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID,
    tipo          VARCHAR(30) NOT NULL,
    entidad       VARCHAR(50),
    registros     INTEGER NOT NULL DEFAULT 0,
    errores       INTEGER NOT NULL DEFAULT 0,
    detalle       TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 10. AUDITORÍA LOCAL
-- ============================================================
CREATE TABLE IF NOT EXISTS auditoria (
    id_auditoria  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario    UUID REFERENCES usuarios(id_usuario),
    id_empresa    UUID,
    accion        VARCHAR(100) NOT NULL,
    entidad       VARCHAR(50),
    entidad_id    VARCHAR(100),
    detalle       JSONB,
    ip            VARCHAR(50),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS logs_sistema (
    id_log        BIGSERIAL PRIMARY KEY,
    nivel         VARCHAR(10) NOT NULL,
    modulo        VARCHAR(50),
    mensaje       TEXT NOT NULL,
    detalle       JSONB,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 11. CONFIGURACIÓN LOCAL
-- ============================================================
CREATE TABLE IF NOT EXISTS configuraciones (
    clave         VARCHAR(100) PRIMARY KEY,
    valor         TEXT,
    descripcion   TEXT,
    id_empresa    UUID REFERENCES empresas(id_empresa),
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS parametros_sistema (
    parametro     VARCHAR(100) PRIMARY KEY,
    valor         TEXT,
    grupo         VARCHAR(50),
    descripcion   TEXT,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 12. SEGURIDAD Y ACCESOS (matriz rol × módulo)
-- ============================================================
CREATE TABLE IF NOT EXISTS permisos_acceso (
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    rol           VARCHAR(30) NOT NULL,
    modulo        VARCHAR(50) NOT NULL,
    acceso        VARCHAR(20) NOT NULL DEFAULT 'ver',
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_empresa, rol, modulo)
);

-- ============================================================
-- ÍNDICES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_fechas    ON boletos_pesaje (fecha_hora_entrada, fecha_hora_salida);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_vehiculo  ON boletos_pesaje (id_vehiculo);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_conductor ON boletos_pesaje (id_conductor);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_producto  ON boletos_pesaje (id_producto);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_estado    ON boletos_pesaje (estado_boleto);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_sync      ON boletos_pesaje (sincronizado);
CREATE INDEX IF NOT EXISTS idx_camiones_empresa         ON camiones (id_empresa);
CREATE INDEX IF NOT EXISTS idx_camiones_placa           ON camiones (placa);
CREATE INDEX IF NOT EXISTS idx_modelos_marca            ON modelos_camion (marca_id);
CREATE INDEX IF NOT EXISTS idx_productos_empresa        ON productos (id_empresa);
CREATE INDEX IF NOT EXISTS idx_almacenes_empresa        ON almacenes (id_empresa);
CREATE INDEX IF NOT EXISTS idx_sync_queue_pend          ON sync_queue (pendiente, intentos);
CREATE INDEX IF NOT EXISTS idx_auditoria_usuario        ON auditoria (id_usuario);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha          ON auditoria (created_at);

COMMIT;
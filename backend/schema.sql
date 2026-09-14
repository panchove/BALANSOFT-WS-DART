-- ============================================================
-- BALANSOFT-WS - SCHEMA DE BASE DE DATOS DE NEGOCIO
-- Base separada: balansoft_ws (independiente del LM SGLB)
-- PostgreSQL 16+
-- ============================================================

BEGIN;

-- Extensiones
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. MÓDULO EMPRESA Y USUARIO
-- ============================================================

CREATE TABLE IF NOT EXISTS empresas (
    id_empresa       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre_fiscal    VARCHAR(255) NOT NULL,
    nombre_comercial VARCHAR(255),
    rif_nit          VARCHAR(20) NOT NULL UNIQUE,
    direccion        TEXT,
    telefono         VARCHAR(50),
    email            VARCHAR(255),
    licencia_key     VARCHAR(255),          -- clave de licencia en el LM (BWS)
    licencia_tier    VARCHAR(20),           -- DEMO / MONOPUESTA / CENTRAL
    licencia_status  VARCHAR(20),
    licencia_expira  TIMESTAMP,
    activa           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS usuarios (
    id_usuario       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa       UUID NOT NULL REFERENCES empresas(id_empresa),
    nombre           VARCHAR(150) NOT NULL,
    email            VARCHAR(255) NOT NULL UNIQUE,
    password_hash    VARCHAR(255) NOT NULL,
    rol              VARCHAR(30) NOT NULL DEFAULT 'OPERADOR', -- ADMIN / OPERADOR / SUPERVISOR
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 2. MÓDULO DIRECTORIO / TRANSPORTES
-- (antes de camiones, que lo referencia)
-- ============================================================

CREATE TABLE IF NOT EXISTS transportes (
    id_transporte        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa           UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo               VARCHAR(20),
    razon_social         VARCHAR(150) NOT NULL,
    identificacion_fiscal VARCHAR(20),
    telefono             VARCHAR(50),
    contacto             VARCHAR(150),
    activo               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 3. MÓDULO FLOTA
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
-- 4. MÓDULO DIRECTORIO (conductores, terceros)
-- ============================================================

CREATE TABLE IF NOT EXISTS conductores (
    cedula_dni      VARCHAR(20) PRIMARY KEY,
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    nombre_completo VARCHAR(200) NOT NULL,
    telefono        VARCHAR(50),
    licencia_conducir VARCHAR(50),
    foto_url        VARCHAR(500),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS terceros (
    id_tercero          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa          UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo              VARCHAR(20),
    tipo                VARCHAR(30) NOT NULL,   -- CLIENTE / PROVEEDOR / AMBOS
    razon_social        VARCHAR(200) NOT NULL,
    identificacion_fiscal VARCHAR(20),
    direccion           TEXT,
    telefono            VARCHAR(50),
    email               VARCHAR(255),
    activo              BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 5. MÓDULO INVENTARIO
-- ============================================================

CREATE TABLE IF NOT EXISTS productos (
    id_producto       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo            VARCHAR(50),
    nombre            VARCHAR(150) NOT NULL,
    descripcion       VARCHAR(200),
    densidad_estandar NUMERIC(8,4),
    unidad_medida     VARCHAR(20) NOT NULL DEFAULT 'TON',  -- TON / KG / M3 / UN
    es_kardex         BOOLEAN NOT NULL DEFAULT FALSE,      -- genera movimientos de kardex
    tolerancia        NUMERIC(8,4),                        -- % tolerancia comercial
    peso_unidad       NUMERIC(12,4),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS almacenes (
    id_almacen       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa       UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo           VARCHAR(20),
    nombre           VARCHAR(150) NOT NULL,
    ubicacion        VARCHAR(255),
    capacidad_max_ton NUMERIC(12,2),
    stock_actual_ton NUMERIC(12,2) NOT NULL DEFAULT 0,
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS balanzas (
    id_balanza      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo          VARCHAR(20),
    descripcion     VARCHAR(150) NOT NULL,
    marca           VARCHAR(100),
    modelo          VARCHAR(100),
    capacidad_max   NUMERIC(12,2),
    division        NUMERIC(12,2),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    puerto_com      VARCHAR(50),
    ip_address      VARCHAR(45),
    puerto_tcp      INTEGER,
    protocolo       VARCHAR(20) DEFAULT 'tcp',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 6. MÓDULO TRANSACCIONAL - BOLETOS DE PESAJE
-- ============================================================
-- El rediseño completo (numero_boleto CA- secuencial, estatus,
-- tipo_operacion, pesos simples) se completa en el Paso 3.

CREATE TABLE IF NOT EXISTS boletos_pesaje (
    boleto                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_boleto            VARCHAR(30) UNIQUE,  -- TA-00000001 secuencial, no se reutiliza
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

    -- Auditoría de operativas (MODEL.md)
    creado_por               VARCHAR(150),
    salida_por               VARCHAR(150),
    modificado_por           VARCHAR(150),
    anulado_por              VARCHAR(150),
    motivo_anulacion         TEXT,

    -- Cálculos MODEL.md: PTE/PTS/PNT/PND/PDF/PDV
    peso_total_entrada       NUMERIC(12,2),
    peso_total_salida        NUMERIC(12,2),
    peso_neto                NUMERIC(12,2),       -- PNT firmado
    peso_neto_declarado      NUMERIC(12,2),       -- PND
    peso_diferencia          NUMERIC(12,2),       -- PDF = PNT - PND
    porcentaje_desviacion    NUMERIC(8,4),        -- PDV = PDF / PND (%)

    -- Campos legacy (compatibilidad)
    peso_bruto               NUMERIC(12,2),
    peso_tara                NUMERIC(12,2),
    diferencia_peso          NUMERIC(12,2),
    porcentaje_diferencia    NUMERIC(8,4),
    densidad                 NUMERIC(8,4),
    litros                   NUMERIC(12,2),
    unidades                 NUMERIC(12,2),

    estado_boleto            VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE', -- PENDIENTE / CERRADO / MODIFICADO / ANULADO
    sincronizado             BOOLEAN NOT NULL DEFAULT FALSE,
    sync_intentos            INTEGER NOT NULL DEFAULT 0,
    created_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS imagenes_pesaje (
    id_imagen     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boleto        UUID NOT NULL REFERENCES boletos_pesaje(boleto) ON DELETE CASCADE,
    tipo          VARCHAR(30) NOT NULL,  -- placa / vehiculo / documento
    url           TEXT NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 6b. KARDEX (MODEL.md)
--     ID movimiento: 10 = INGRESO POR BASCULA (positivo),
--                    60 = DESPACHO POR BASCULA (negativo).
--     Los ANULADOS no generan kardex.
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
    valor           NUMERIC(12,2) NOT NULL,  -- magnitud; signo según id_movimiento
    boleto          UUID REFERENCES boletos_pesaje(boleto),
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_kardex_empresa_fecha ON kardex (id_empresa, fecha_kardex);
CREATE INDEX IF NOT EXISTS idx_kardex_producto_almacen ON kardex (id_producto, id_almacen);

-- ============================================================
-- 7. MÓDULO SINCRONIZACIÓN
-- ============================================================

CREATE TABLE IF NOT EXISTS sync_queue (
    id_sync       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    entidad       VARCHAR(50) NOT NULL,      -- pesaje / vehiculo / ...
    operacion     VARCHAR(20) NOT NULL,      -- create / update / delete
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
    tipo          VARCHAR(30) NOT NULL,     -- push / pull / full
    entidad       VARCHAR(50),
    registros     INTEGER NOT NULL DEFAULT 0,
    errores       INTEGER NOT NULL DEFAULT 0,
    detalle       TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 8. MÓDULO AUDITORÍA
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

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario  UUID NOT NULL REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    token_hash  VARCHAR(128) NOT NULL,
    expira      TIMESTAMP NOT NULL,
    usado       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_password_reset_usuario ON password_reset_tokens (id_usuario, usado);

CREATE TABLE IF NOT EXISTS logs_sistema (
    id_log        BIGSERIAL PRIMARY KEY,
    nivel         VARCHAR(10) NOT NULL,
    modulo        VARCHAR(50),
    mensaje       TEXT NOT NULL,
    detalle       JSONB,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 9. MÓDULO CONFIGURACIÓN
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
CREATE INDEX IF NOT EXISTS idx_usuarios_empresa         ON usuarios (id_empresa);

COMMIT;
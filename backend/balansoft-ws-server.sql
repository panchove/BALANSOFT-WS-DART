-- ============================================================
-- BALANSOFT-WS - SCHEMA DE CUENTA Y LICENCIA (SERVIDOR)
-- Esta base SOLO contiene información de la cuenta,
-- licencia, credenciales globales y sincronización.
-- NO contiene datos operativos del cliente.
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. CUENTAS (empresas registradas por el proveedor)
-- ============================================================
CREATE TABLE IF NOT EXISTS cuentas (
    id_cuenta        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Identificación fiscal de la empresa
    rif_nit          VARCHAR(20) NOT NULL UNIQUE,
    nombre_fiscal    VARCHAR(255) NOT NULL,
    nombre_comercial VARCHAR(255),
    -- Contacto del titular/admin
    email_admin      VARCHAR(255) NOT NULL UNIQUE,
    telefono         VARCHAR(50),
    direccion        TEXT,
    -- Estado de la cuenta
    activa           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 2. LICENCIAS (gestionadas por el proveedor)
-- ============================================================
CREATE TABLE IF NOT EXISTS licencias (
    id_licencia      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID NOT NULL REFERENCES cuentas(id_cuenta) ON DELETE CASCADE,
    licencia_key     VARCHAR(255) NOT NULL UNIQUE,   -- BWS-XXXX-XXXX-XXXX
    licencia_tier    VARCHAR(20) NOT NULL,           -- DEMO / MONOPUESTA / CENTRAL
    licencia_status  VARCHAR(20) NOT NULL DEFAULT 'ACTIVA', -- ACTIVA / SUSPENDIDA / EXPIRADA / REVOCADA
    fecha_emision    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_expira     TIMESTAMP NOT NULL,
    max_usuarios     INTEGER,                        -- según tier
    max_equipos      INTEGER,                        -- equipos autorizados a sincronizar
    -- Huella de la máquina autorizada (para MONOPUESTA)
    hardware_id      VARCHAR(255),
    -- Observaciones del proveedor
    notas            TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_licencias_cuenta ON licencias (id_cuenta, licencia_status);

-- ============================================================
-- 3. DISPOSITIVOS / EQUIPOS AUTORIZADOS
-- Cada máquina local que se conecta a esta cuenta.
-- ============================================================
CREATE TABLE IF NOT EXISTS dispositivos (
    id_dispositivo   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID NOT NULL REFERENCES cuentas(id_cuenta) ON DELETE CASCADE,
    id_licencia      UUID REFERENCES licencias(id_licencia),
    hardware_id      VARCHAR(255) NOT NULL UNIQUE,  -- huella única de la máquina
    nombre_equipo    VARCHAR(150),
    sistema_operativo VARCHAR(100),
    version_app      VARCHAR(50),
    rol_dispositivo  VARCHAR(20) NOT NULL DEFAULT 'LOCAL', -- LOCAL / SERVIDOR_LOCAL
    ip_local         VARCHAR(45),
    ultima_conexion  TIMESTAMP,
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_dispositivos_cuenta ON dispositivos (id_cuenta, activo);

-- ============================================================
-- 4. CREDENCIALES GLOBALES (para login desde cualquier equipo)
-- Solo se guarda lo mínimo: email + hash + cuenta + rol global.
-- Los roles operativos viven en la DB local.
-- ============================================================
CREATE TABLE IF NOT EXISTS credenciales (
    id_credencial    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID NOT NULL REFERENCES cuentas(id_cuenta) ON DELETE CASCADE,
    email            VARCHAR(255) NOT NULL UNIQUE,
    password_hash    VARCHAR(255) NOT NULL,
    rol_global       VARCHAR(30) NOT NULL DEFAULT 'OPERADOR', -- ADMIN / OPERADOR / AUDITOR / TRABAJADOR
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    ultimo_login     TIMESTAMP,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_credenciales_cuenta ON credenciales (id_cuenta, activo);

-- ============================================================
-- 5. SESIONES / TOKENS (JWT emitidos por el servidor)
-- ============================================================
CREATE TABLE IF NOT EXISTS sesiones (
    id_sesion        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_credencial    UUID NOT NULL REFERENCES credenciales(id_credencial) ON DELETE CASCADE,
    id_dispositivo   UUID REFERENCES dispositivos(id_dispositivo),
    token_hash       VARCHAR(128) NOT NULL,
    expira           TIMESTAMP NOT NULL,
    revocada         BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sesiones_credencial ON sesiones (id_credencial, revocada);

-- ============================================================
-- 6. SINCRONIZACIÓN (orquestada desde el servidor)
-- ============================================================
CREATE TABLE IF NOT EXISTS sync_sesiones (
    id_sync          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID NOT NULL REFERENCES cuentas(id_cuenta),
    id_dispositivo   UUID NOT NULL REFERENCES dispositivos(id_dispositivo),
    tipo             VARCHAR(20) NOT NULL,   -- push / pull / full
    estado           VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE', -- PENDIENTE / OK / ERROR
    registros_subidos INTEGER NOT NULL DEFAULT 0,
    registros_bajados INTEGER NOT NULL DEFAULT 0,
    errores          INTEGER NOT NULL DEFAULT 0,
    detalle          TEXT,
    iniciado         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finalizado       TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sync_cola (
    id_cola          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID NOT NULL REFERENCES cuentas(id_cuenta),
    id_dispositivo   UUID NOT NULL REFERENCES dispositivos(id_dispositivo),
    entidad          VARCHAR(50) NOT NULL,   -- pesaje / vehiculo / producto / ...
    operacion        VARCHAR(20) NOT NULL,   -- create / update / delete
    entidad_id       VARCHAR(100) NOT NULL,
    payload          JSONB NOT NULL,
    pendiente        BOOLEAN NOT NULL DEFAULT TRUE,
    intentos         INTEGER NOT NULL DEFAULT 0,
    error            TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sync_cola_pendiente ON sync_cola (pendiente, intentos);

-- ============================================================
-- 7. AUDITORÍA DEL SERVIDOR (solo eventos de cuenta/licencia)
-- ============================================================
CREATE TABLE IF NOT EXISTS auditoria_servidor (
    id_auditoria     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID REFERENCES cuentas(id_cuenta),
    id_credencial    UUID REFERENCES credenciales(id_credencial),
    accion           VARCHAR(100) NOT NULL,  -- login / logout / licencia_activada / sync / ...
    entidad          VARCHAR(50),
    entidad_id       VARCHAR(100),
    detalle          JSONB,
    ip               VARCHAR(50),
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 8. RECUPERACIÓN DE CONTRASEÑA (global)
-- ============================================================
CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_credencial    UUID NOT NULL REFERENCES credenciales(id_credencial) ON DELETE CASCADE,
    token_hash       VARCHAR(128) NOT NULL,
    expira           TIMESTAMP NOT NULL,
    usado            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 9. PANEL DEL PROVEEDOR (gestión interna)
-- ============================================================
CREATE TABLE IF NOT EXISTS proveedores_usuarios (
    id_usuario       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email            VARCHAR(255) NOT NULL UNIQUE,
    password_hash    VARCHAR(255) NOT NULL,
    nombre           VARCHAR(150) NOT NULL,
    rol              VARCHAR(30) NOT NULL DEFAULT 'SOPORTE', -- SUPERADMIN / SOPORTE / VENTAS
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMIT;
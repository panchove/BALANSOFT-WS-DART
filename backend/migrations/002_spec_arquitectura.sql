-- ============================================================
-- BALANSOFT-WS - MIGRACIÓN 002
-- Arquitectura del spec: marcas, modelos_camion, camiones
-- (reemplaza vehiculos), alineación de catálogos maestros a los
-- nombres del spec y renombrado de pesajes -> boletos_pesaje.
-- Aplicar: psql "$DATABASE_URL_SYNC" -f migrations/002_spec_arquitectura.sql
--
-- NOTA: El rediseño transaccional completo de boletos_pesaje
-- (numero_boleto secuencial CA-, estatus, tipo_operacion y pesos
-- simples entrada/salida) corresponde al Paso 3 (core de pesaje).
-- Aquí solo se renombra la tabla y se dejan anclas del spec.
-- ============================================================

BEGIN;

-- ============================================================
-- 1. MARCA DE VEHÍCULO
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

-- ============================================================
-- 2. MODELO DE CAMIÓN (pertenece a una marca)
-- ============================================================
CREATE TABLE IF NOT EXISTS modelos_camion (
    id_modelo_camion   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa         UUID NOT NULL REFERENCES empresas(id_empresa),
    marca_id           UUID REFERENCES marcas(id_marca),
    nombre             VARCHAR(100) NOT NULL,
    capacidad_carga_ton NUMERIC(12,2),
    foto_referencial_url VARCHAR(500),
    ejes               INTEGER,
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_modelos_empresa_nombre ON modelos_camion (id_empresa, nombre);

-- ============================================================
-- 3. CAMIONES (reemplaza vehiculos)
-- ============================================================
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

-- Migrar datos demo de vehiculos -> camiones (tara <- capacidad, foto -> foto_real_url)
INSERT INTO camiones (id_empresa, placa, color, foto_real_url, tara_habitual, activo)
SELECT id_empresa, placa, color, foto_url, capacidad, activo FROM vehiculos;

DROP TABLE IF EXISTS vehiculos CASCADE;

-- ============================================================
-- 4. REMOLQUES -> nombres del spec
-- ============================================================
ALTER TABLE remolques RENAME COLUMN tipo TO tipo_remolque;
ALTER TABLE remolques RENAME COLUMN peso_tara TO tara_habitual;
ALTER TABLE remolques DROP COLUMN IF EXISTS marca;
ALTER TABLE remolques DROP COLUMN IF EXISTS modelo;
ALTER TABLE remolques DROP COLUMN IF EXISTS capacidad;

-- ============================================================
-- 5. TRANSPORTES
-- ============================================================
ALTER TABLE transportes RENAME COLUMN nombre TO razon_social;
ALTER TABLE transportes ADD COLUMN IF NOT EXISTS identificacion_fiscal VARCHAR(20);

-- ============================================================
-- 6. CONDUCTORES
-- ============================================================
ALTER TABLE conductores RENAME COLUMN cedula TO cedula_dni;
ALTER TABLE conductores RENAME COLUMN licencia TO licencia_conducir;

-- ============================================================
-- 7. PRODUCTOS
-- ============================================================
ALTER TABLE productos ADD COLUMN IF NOT EXISTS nombre VARCHAR(150);
UPDATE productos SET nombre = descripcion WHERE nombre IS NULL;
ALTER TABLE productos ALTER COLUMN nombre SET NOT NULL;
ALTER TABLE productos RENAME COLUMN densidad TO densidad_estandar;
ALTER TABLE productos ADD COLUMN IF NOT EXISTS unidad_medida VARCHAR(20) NOT NULL DEFAULT 'TON';

-- ============================================================
-- 8. ALMACENES
-- ============================================================
ALTER TABLE almacenes ADD COLUMN IF NOT EXISTS capacidad_max_ton NUMERIC(12,2);
ALTER TABLE almacenes ADD COLUMN IF NOT EXISTS stock_actual_ton NUMERIC(12,2) NOT NULL DEFAULT 0;

-- ============================================================
-- 9. TERCEROS
-- ============================================================
ALTER TABLE terceros RENAME COLUMN nombre TO razon_social;
ALTER TABLE terceros RENAME COLUMN rif TO identificacion_fiscal;
ALTER TABLE terceros ADD COLUMN IF NOT EXISTS direccion TEXT;

-- ============================================================
-- 10. PESAJE -> BOLETOS_PESAJE (solo renombrado; core en Paso 3)
-- ============================================================
ALTER TABLE pesajes RENAME TO boletos_pesaje;
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS numero_boleto VARCHAR(20);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS foto_entrada_url TEXT;
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS foto_salida_url TEXT;

ALTER INDEX IF EXISTS idx_pesajes_fechas    RENAME TO idx_boletos_pesaje_fechas;
ALTER INDEX IF EXISTS idx_pesajes_vehiculo  RENAME TO idx_boletos_pesaje_vehiculo;
ALTER INDEX IF EXISTS idx_pesajes_conductor RENAME TO idx_boletos_pesaje_conductor;
ALTER INDEX IF EXISTS idx_pesajes_producto  RENAME TO idx_boletos_pesaje_producto;
ALTER INDEX IF EXISTS idx_pesajes_estado    RENAME TO idx_boletos_pesaje_estado;
ALTER INDEX IF EXISTS idx_pesajes_sync      RENAME TO idx_boletos_pesaje_sync;

-- Índices de los nuevos catálogos
CREATE INDEX IF NOT EXISTS idx_camiones_empresa     ON camiones (id_empresa);
CREATE INDEX IF NOT EXISTS idx_camiones_placa       ON camiones (placa);
CREATE INDEX IF NOT EXISTS idx_modelos_marca        ON modelos_camion (marca_id);
CREATE INDEX IF NOT EXISTS idx_productos_empresa    ON productos (id_empresa);
CREATE INDEX IF NOT EXISTS idx_almacenes_empresa    ON almacenes (id_empresa);

COMMIT;
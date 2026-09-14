-- ============================================================
-- BALANSOFT-WS - MIGRACIÓN 001
-- Tabla remolques + fotos de catálogos + códigos + costo_flete
-- Aplicar: psql "$DATABASE_URL_SYNC" -f migrations/001_remolques_y_fotos.sql
-- ============================================================

BEGIN;

-- 1. Tabla remolques
CREATE TABLE IF NOT EXISTS remolques (
    id_remolque     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    placa           VARCHAR(20) NOT NULL,
    tipo            VARCHAR(100),
    marca           VARCHAR(100),
    modelo          VARCHAR(100),
    peso_tara       NUMERIC(12,2),
    capacidad       NUMERIC(12,2),
    foto_url        VARCHAR(500),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_remolques_empresa ON remolques (id_empresa, placa);

-- 2. Fotos de catálogos
-- 'vehiculos' existía solo en esquemas previos (en el esquema final es 'camiones').
-- En instalaciones nuevas la columna ya viene en el schema.sql, así que se
-- protege con to_regclass para no fallar si la tabla no existe.
DO $$
BEGIN
    IF to_regclass('public.vehiculos') IS NOT NULL THEN
        ALTER TABLE vehiculos ADD COLUMN IF NOT EXISTS foto_url VARCHAR(500);
    END IF;
END $$;
ALTER TABLE conductores ADD COLUMN IF NOT EXISTS foto_url VARCHAR(500);

-- 3. Códigos de catálogos (T001, A1, BALANZA1, etc.)
ALTER TABLE transportes ADD COLUMN IF NOT EXISTS codigo VARCHAR(20);
ALTER TABLE almacenes ADD COLUMN IF NOT EXISTS codigo VARCHAR(20);
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS codigo VARCHAR(20);
ALTER TABLE terceros ADD COLUMN IF NOT EXISTS codigo VARCHAR(20);

-- 4. Pesaje: remolque vinculado y costo de flete
-- (En el esquema final la tabla es 'boletos_pesaje'; 'pesajes' solo existe en
-- esquemas previos. Ambos ALTER se protegen para no fallar en instalaciones nuevas.)
DO $$
BEGIN
    IF to_regclass('public.pesajes') IS NOT NULL THEN
        ALTER TABLE pesajes ADD COLUMN IF NOT EXISTS id_remolque UUID REFERENCES remolques(id_remolque);
        ALTER TABLE pesajes ADD COLUMN IF NOT EXISTS costo_flete NUMERIC(12,2);
    END IF;
END $$;

COMMIT;
-- =============================================================================
-- BALANSOFT-WS · Migración 028 · Indicadores (terminal de peso) separados de la
-- báscula física
-- -----------------------------------------------------------------------------
-- Hasta ahora `balanzas` mezclaba dos cosas: la **báscula física** (plataforma
-- de pesaje, la que tiene capacidad y división de la celda de carga) y el
-- **indicador** (el terminal que muestra/transmite el peso: BKG LP7510, CAS
-- C12001A, Transcell TI500E, AND AD431, Cardinal UMC555, Toledo T4321, …).
--
-- El árbol del menú dictado por el cliente pide **BÁSCULAS** e **INDICADORES**
-- como entidades separadas para que el ADMIN decida qué indicador va con qué
-- báscula. Esta migración crea `indicadores` (gemela de `balanzas`: protocolo,
-- puerto/ip, formato de trama, baudrate y delimitador viven aquí, porque son
-- propiedades del *terminal*, no de la plataforma) y `balanzas.id_indicador`
-- como enlace opcional (NULL = báscula todavía sin indicador asignado).
--
-- Compatibilidad: los campos de comunicación NO se borran de `balanzas`
-- (instalaciones existentes y el HAL siguen leyéndolos); `id_indicador` es
-- *nullable* y aditivo, así que la estación sigue operando sin tocar nada.
--
-- Reflejo obligatorio en `balansoft-ws-local.sql` y en
-- `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 022/026/027).
-- =============================================================================

CREATE TABLE IF NOT EXISTS indicadores (
    id_indicador  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo        VARCHAR(20),
    descripcion   VARCHAR(150) NOT NULL,
    marca         VARCHAR(100),
    modelo        VARCHAR(100),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulado   BOOLEAN NOT NULL DEFAULT FALSE,
    -- tcp|serial (mismos canales que soporta el HAL de balanza).
    protocolo     VARCHAR(20) DEFAULT 'tcp',
    puerto_com    VARCHAR(50),
    ip_address    VARCHAR(45),
    puerto_tcp    INTEGER,
    formato_trama VARCHAR(10) NOT NULL DEFAULT 'auto',
    baudrate      INTEGER NOT NULL DEFAULT 9600,
    delimitador   VARCHAR(10),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS indicadores_empresa_codigo_uk
    ON indicadores (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

-- Enlace opcional báscula → indicador (NULL = sin asignar).
ALTER TABLE balanzas
    ADD COLUMN IF NOT EXISTS id_indicador UUID REFERENCES indicadores(id_indicador);

CREATE INDEX IF NOT EXISTS balanzas_id_indicador_idx
    ON balanzas (id_indicador);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_indicadores_formato_trama'
    ) THEN
        ALTER TABLE indicadores
            ADD CONSTRAINT ck_indicadores_formato_trama
            CHECK (formato_trama IN ('auto', 'json', 'ascii'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_indicadores_baudrate'
    ) THEN
        ALTER TABLE indicadores
            ADD CONSTRAINT ck_indicadores_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_indicadores_delimitador'
    ) THEN
        ALTER TABLE indicadores
            ADD CONSTRAINT ck_indicadores_delimitador
            CHECK (delimitador IS NULL OR delimitador IN ('lf', 'cr', 'crlf', 'stx_etx'));
    END IF;
END
$$;

-- =============================================================================
-- BALANSOFT-WS · Migración 032 · Barreras de tránsito (actuador de control de acceso)
-- -----------------------------------------------------------------------------
-- Registra las barreras de tránsito como dispositivo del módulo Dispositivos.
-- Control de acceso abrir/cerrar mediante comandos lógicos por HTTP/REST o
-- por puerto serie/USB (docs/DISPOSITIVOS.md §5).
--
-- Columnas:
--   id_barrera             UUID PRIMARY KEY DEFAULT gen_random_uuid()
--   id_empresa             UUID NOT NULL REFERENCES empresas(id_empresa)
--   codigo                 VARCHAR(20) NULL
--   descripcion            VARCHAR(150) NOT NULL
--   activo                 BOOLEAN NOT NULL DEFAULT TRUE
--   is_simulado            BOOLEAN NOT NULL DEFAULT FALSE
--   protocolo              VARCHAR(20) NOT NULL DEFAULT 'http' (http|serial)
--   ip_address             VARCHAR(45) NULL
--   puerto_tcp             INTEGER NULL
--   puerto_com             VARCHAR(50) NULL
--   baudrate               INTEGER NOT NULL DEFAULT 9600
--   ubicacion              VARCHAR(10) NOT NULL DEFAULT 'ambos' (entrada|salida|ambos)
--   control_automatico     BOOLEAN NOT NULL DEFAULT FALSE
--   tiempo_espera_segundos INTEGER NOT NULL DEFAULT 5
--   comando_abrir          VARCHAR(255) NULL
--   comando_cerrar         VARCHAR(255) NULL
--   created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
--   updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
--
-- Reflejo obligatorio en `balansoft-ws-local.sql` y `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo.
-- =============================================================================

CREATE TABLE IF NOT EXISTS barreras (
    id_barrera             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa             UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo                 VARCHAR(20),
    descripcion            VARCHAR(150) NOT NULL,
    activo                 BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulado            BOOLEAN NOT NULL DEFAULT FALSE,
    protocolo              VARCHAR(20) NOT NULL DEFAULT 'http',
    ip_address             VARCHAR(45),
    puerto_tcp             INTEGER,
    puerto_com             VARCHAR(50),
    baudrate               INTEGER NOT NULL DEFAULT 9600,
    ubicacion              VARCHAR(10) NOT NULL DEFAULT 'ambos',
    control_automatico     BOOLEAN NOT NULL DEFAULT FALSE,
    tiempo_espera_segundos INTEGER NOT NULL DEFAULT 5,
    comando_abrir          VARCHAR(255),
    comando_cerrar         VARCHAR(255),
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS barreras_empresa_codigo_uk
    ON barreras (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_barreras_protocolo'
    ) THEN
        ALTER TABLE barreras
            ADD CONSTRAINT ck_barreras_protocolo
            CHECK (protocolo IN ('http', 'serial'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_barreras_ubicacion'
    ) THEN
        ALTER TABLE barreras
            ADD CONSTRAINT ck_barreras_ubicacion
            CHECK (ubicacion IN ('entrada', 'salida', 'ambos'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_barreras_baudrate'
    ) THEN
        ALTER TABLE barreras
            ADD CONSTRAINT ck_barreras_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
END
$$;

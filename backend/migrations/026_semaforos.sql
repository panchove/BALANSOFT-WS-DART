-- =============================================================================
-- BALANSOFT-WS · Migración 026 · Semáforos de pesaje (actuador de salida)
-- -----------------------------------------------------------------------------
-- Registra la torre de 3 luces + zumbador como dispositivo del módulo
-- Dispositivos. El semáforo NO mide; obedece los comandos JSON del SPEC del
-- simulador BSDD (§4) por HTTP/REST (`127.0.0.1:8080/api/semaforo`, Fase 2) o
-- por USB serie CDC-ACM (`/dev/bsdd_semaforo_acm`, Fase 3):
--   {"color":"rojo","action":"on"}  {"color":"verde","action":"on"}
--   {"color":"amarillo","action":"flash"}  {"all":"off"}  {"reset":true}
--
-- Esta app es la dueña de la decisión (docs/SEMAFORO.md): el vigilante del
-- backend lee el peso/estabilidad de la báscula vinculada (`id_balanza`) y el
-- estado del boleto, y enciende el LED que corresponde.
--
-- Columnas nuevas:
--   protocolo          VARCHAR(20) NOT NULL DEFAULT 'http' → http|serial
--   ip_address         VARCHAR(45)  → HTTP/REST
--   puerto_tcp         INTEGER      → HTTP/REST (default de app 8080)
--   puerto_com         VARCHAR(50)  → USB serie CDC-ACM
--   baudrate           INTEGER NOT NULL DEFAULT 9600
--   id_balanza         UUID NULL REFERENCES balanzas(id_balanza)
--   control_automatico BOOLEAN NOT NULL DEFAULT FALSE
--   umbral_cero_kg     NUMERIC(10,2) NOT NULL DEFAULT 5.0
--   is_simulado        BOOLEAN NOT NULL DEFAULT FALSE
--
-- Reflejo obligatorio en `balansoft-ws-local.sql` (CREATE TABLE + índice) y en
-- `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 022).
-- =============================================================================

CREATE TABLE IF NOT EXISTS semaforos (
    id_semaforo        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa         UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo             VARCHAR(20),
    descripcion        VARCHAR(150) NOT NULL,
    activo             BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulado        BOOLEAN NOT NULL DEFAULT FALSE,
    protocolo          VARCHAR(20) NOT NULL DEFAULT 'http',
    ip_address         VARCHAR(45),
    puerto_tcp         INTEGER,
    puerto_com         VARCHAR(50),
    baudrate           INTEGER NOT NULL DEFAULT 9600,
    id_balanza         UUID REFERENCES balanzas(id_balanza),
    control_automatico BOOLEAN NOT NULL DEFAULT FALSE,
    umbral_cero_kg     NUMERIC(10,2) NOT NULL DEFAULT 5.0,
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS semaforos_empresa_codigo_uk
    ON semaforos (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_semaforos_protocolo'
    ) THEN
        ALTER TABLE semaforos
            ADD CONSTRAINT ck_semaforos_protocolo
            CHECK (protocolo IN ('http', 'serial'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_semaforos_baudrate'
    ) THEN
        ALTER TABLE semaforos
            ADD CONSTRAINT ck_semaforos_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
END
$$;

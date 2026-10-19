-- =============================================================================
-- BALANSOFT-WS · Migración 023 · Centro de notificaciones y recordatorios
-- -----------------------------------------------------------------------------
-- Añade las dos tablas que sostienen el centro de avisos de la estación:
--
--   recordatorios   avisos programados por el usuario (diario/semanal/mensual),
--                   con `programada_para` y `ultima_ejecucion` para que el
--                   programador del backend (`app/core/notification_scheduler.py`)
--                   sepa cuándo disparar y cuándo reprogramar.
--
--   notificaciones  bandeja de avisos generados (eventos del sistema y
--                   recordatorios). `dedup_key` es única por empresa: da
--                   idempotencia al programador para que un mismo evento no
--                   genere dos avisos (ni dos avisos nativos del SO).
--
-- El programador vive en el backend local (WServer); por eso las tablas son
-- locales y NO se sincronizan con el servidor central.
--
-- Reflejo obligatorio en `balansoft-ws-local.sql` (CREATE TABLE + índices) y en
-- `sqlserver/balansoft-ws-local.sql` (bloques IF OBJECT_ID + índices + FK).
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 021/022).
-- =============================================================================

CREATE TABLE IF NOT EXISTS recordatorios (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa) ON DELETE CASCADE,
    id_usuario        UUID REFERENCES usuarios(id_usuario),
    titulo            VARCHAR(200) NOT NULL,
    mensaje           TEXT,
    programada_para   TIMESTAMP NOT NULL,
    recurrencia       VARCHAR(20) NOT NULL DEFAULT 'none',
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    ultima_ejecucion  TIMESTAMP,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS notificaciones (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa) ON DELETE CASCADE,
    tipo              VARCHAR(40) NOT NULL,
    severidad         VARCHAR(10) NOT NULL DEFAULT 'info',
    titulo            VARCHAR(200) NOT NULL,
    mensaje           TEXT,
    acciones          JSON,
    estado            VARCHAR(20) NOT NULL DEFAULT 'no_leida',
    origen            VARCHAR(20) NOT NULL DEFAULT 'evento',
    id_recordatorio   UUID REFERENCES recordatorios(id) ON DELETE SET NULL,
    id_referencia     UUID,
    dedup_key         VARCHAR(150),
    programada_para   TIMESTAMP,
    entregada_os_en   TIMESTAMP,
    leida_en          TIMESTAMP,
    expira_en         TIMESTAMP,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_notificaciones_empresa_dedup UNIQUE (id_empresa, dedup_key)
);

CREATE INDEX IF NOT EXISTS idx_notificaciones_empresa_estado
    ON notificaciones (id_empresa, estado);
CREATE INDEX IF NOT EXISTS idx_notificaciones_empresa_created
    ON notificaciones (id_empresa, created_at);
CREATE INDEX IF NOT EXISTS idx_recordatorios_empresa
    ON recordatorios (id_empresa, activo, programada_para);

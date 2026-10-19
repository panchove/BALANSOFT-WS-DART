-- ============================================================
-- 006_usuarios_id_credencial_y_identidad_local.sql
-- Sincroniza una BD unificada existente con la arquitectura de
-- dos BDs (docs/MANEJO_DB.md):
--   1) usuarios.id_credencial  -> vínculo con la credencial global
--   2) identidad_local         -> singleton de la estación (tier, licencia)
-- Idempotente y hacia adelante: seguro re-ejecutarlo.
-- ============================================================

-- Vínculo del usuario local con su credencial global (server).
ALTER TABLE usuarios ADD COLUMN IF NOT EXISTS id_credencial UUID;

CREATE INDEX IF NOT EXISTS idx_usuarios_id_credencial ON usuarios (id_credencial);

-- Identidad de la estación local (una sola fila, id = TRUE).
CREATE TABLE IF NOT EXISTS identidad_local (
    id                  BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id = TRUE),
    id_cuenta           UUID NOT NULL,           -- FK lógica a cuentas del servidor
    rif_nit             VARCHAR(20) NOT NULL,
    nombre_fiscal       VARCHAR(255) NOT NULL,
    nombre_comercial    VARCHAR(255),
    licencia_key        VARCHAR(255),
    licencia_tier       VARCHAR(20),
    licencia_status     VARCHAR(20),
    licencia_expira     TIMESTAMP,
    hardware_id         VARCHAR(255),
    rol_dispositivo     VARCHAR(20) NOT NULL DEFAULT 'LOCAL',
    ultima_validacion   TIMESTAMP,
    modo_offline        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
-- ============================================================
-- BALANSOFT-WS - MIGRACIÓN 004
-- Recuperación de contraseña (forgot-password / reset-password)
-- Aplicar: psql "$DATABASE_URL_SYNC" -f migrations/004_password_reset.sql
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario  UUID NOT NULL REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
    token_hash  VARCHAR(128) NOT NULL,
    expira      TIMESTAMP NOT NULL,
    usado       BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_password_reset_usuario ON password_reset_tokens (id_usuario, usado);

COMMIT;
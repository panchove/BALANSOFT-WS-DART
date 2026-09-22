-- =============================================================================
-- BALANSOFT-WS · Migración 012 · Seguridad y Accesos (esquema local)
-- -----------------------------------------------------------------------------
-- Tabla `permisos_acceso`: matriz rol × módulo por empresa. `acceso` admite
-- `ver` (solo lectura), `editar` (lectura/escritura) y `ninguno` (oculto).
-- La matriz por defecto vive en `app/core/seguridad_matrix.py`; los cambios
-- hechos desde "Seguridad y Accesos" se persisten aquí por empresa.
-- Idempotente: seguro re-ejecutarlo.
-- =============================================================================

CREATE TABLE IF NOT EXISTS permisos_acceso (
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    rol           VARCHAR(30) NOT NULL,
    modulo        VARCHAR(50) NOT NULL,
    acceso        VARCHAR(20) NOT NULL DEFAULT 'ver',
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_empresa, rol, modulo)
);
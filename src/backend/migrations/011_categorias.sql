-- =============================================================================
-- BALANSOFT-WS · Migración 011 · Módulo Categorías (esquema local)
-- -----------------------------------------------------------------------------
-- Añade la maestra `categorias` (repositorio de categorías de producto) usada
-- por el CRUD genérico de catálogos. Idempotente: seguro re-ejecutarlo.
-- =============================================================================

CREATE TABLE IF NOT EXISTS categorias (
    id_categoria      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo            VARCHAR(50),
    nombre            VARCHAR(150) NOT NULL,
    descripcion       VARCHAR(200),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
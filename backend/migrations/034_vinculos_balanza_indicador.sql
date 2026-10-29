-- Migración 034: Tabla de vínculos entre básculas e indicadores
-- Necesaria para que el puente de datos (IndicadorBridge) sepa qué báscula
-- está asociada a qué indicador físico.

CREATE TABLE IF NOT EXISTS vinculos_balanza_indicador (
    id_vinculo UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa UUID NOT NULL,
    id_bascula UUID NOT NULL,
    id_indicador UUID NOT NULL,
    activo BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_vinculo_empresa FOREIGN KEY (id_empresa) REFERENCES empresas(id_empresa) ON DELETE CASCADE,
    CONSTRAINT fk_vinculo_bascula FOREIGN KEY (id_bascula) REFERENCES balanzas(id_balanza) ON DELETE CASCADE,
    CONSTRAINT fk_vinculo_indicador FOREIGN KEY (id_indicador) REFERENCES indicadores(id_indicador) ON DELETE CASCADE
);

-- Índice para búsquedas rápidas por empresa y báscula
CREATE INDEX IF NOT EXISTS idx_vinculos_empresa ON vinculos_balanza_indicador(id_empresa);
CREATE INDEX IF NOT EXISTS idx_vinculos_bascula ON vinculos_balanza_indicador(id_bascula);
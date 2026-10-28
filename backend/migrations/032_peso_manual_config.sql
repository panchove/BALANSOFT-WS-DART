-- ============================================================================
-- 032_peso_manual_config
-- Configuración global de la empresa: permitir peso manual cuando no hay
-- báscula conectada. Solo el ADMIN puede cambiarla.
-- ============================================================================

INSERT INTO configuraciones (clave, valor, metadatos)
VALUES (
    'peso_manual_permitido',
    'true',
    '{"descripcion": "Permitir peso manual cuando no hay báscula conectada", "tipo": "bool"}'
)
ON CONFLICT (clave) DO NOTHING;
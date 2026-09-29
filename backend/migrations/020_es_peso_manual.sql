-- Marca si el peso del boleto se escribió manualmente (sin báscula).
-- La reflejan los tickets (básico: indicador "peso manual"; avanzado: detalle
-- completo del formulario).
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS es_peso_manual BOOLEAN NOT NULL DEFAULT FALSE;
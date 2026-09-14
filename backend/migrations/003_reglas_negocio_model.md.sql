-- ============================================================
-- Migración 003: Reglas de negocio alineadas a MODEL.md / AGENTS.md
--   - Estados: PENDIENTE / CERRADO / MODIFICADO / ANULADO
--   - numero_boleto secuencial TA-XXXXXX (único, no se reutiliza)
--   - Cálculos firmados: PTE/PTS/PNT/PND/PDF/PDV + auditoría de operativas
--   - Maestra productos: es_kardex / tolerancia / peso_unidad
--   - Tabla kardex (ingreso 10 / despacho 60 por báscula)
-- ============================================================

-- 1) Productos: campos de la maestra (MODEL.md)
ALTER TABLE productos ADD COLUMN IF NOT EXISTS es_kardex BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE productos ADD COLUMN IF NOT EXISTS tolerancia NUMERIC(8,4);
ALTER TABLE productos ADD COLUMN IF NOT EXISTS peso_unidad NUMERIC(12,4);

-- 2) Boleto: longitud/único del número de boleto + columnas nuevas
ALTER TABLE boletos_pesaje ALTER COLUMN numero_boleto TYPE VARCHAR(30);
CREATE UNIQUE INDEX IF NOT EXISTS uq_boletos_pesaje_numero ON boletos_pesaje (numero_boleto)
    WHERE numero_boleto IS NOT NULL;

ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS creado_por VARCHAR(150);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS salida_por VARCHAR(150);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS modificado_por VARCHAR(150);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS anulado_por VARCHAR(150);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS motivo_anulacion TEXT;

ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS peso_total_entrada NUMERIC(12,2);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS peso_total_salida NUMERIC(12,2);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS peso_neto_declarado NUMERIC(12,2);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS peso_diferencia NUMERIC(12,2);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS porcentaje_desviacion NUMERIC(8,4);

-- 3) Normalización de estados legacy (Abierto/Cerrado/Automático/COMPLETADO)
UPDATE boletos_pesaje SET estado_boleto = 'PENDIENTE'
  WHERE UPPER(estado_boleto) IN ('ABIERTO', 'AUTOMATICO', 'AUTOMÁTICO');
UPDATE boletos_pesaje SET estado_boleto = 'CERRADO' WHERE UPPER(estado_boleto) IN ('CERRADO', 'COMPLETADO');
UPDATE boletos_pesaje SET estado_boleto = 'ANULADO' WHERE UPPER(estado_boleto) IN ('ANULADO');

ALTER TABLE boletos_pesaje ALTER COLUMN estado_boleto SET DEFAULT 'PENDIENTE';
UPDATE boletos_pesaje SET estado_boleto = 'PENDIENTE' WHERE estado_boleto IS NULL OR estado_boleto = '';

-- 4) Numeración de boletos existentes sin número (legacy, genera TA- secuencial)
DO $$
DECLARE
    r RECORD;
    next_num INTEGER := 1;
    num_pad  TEXT;
BEGIN
    FOR r IN
        SELECT boleto FROM boletos_pesaje
        WHERE numero_boleto IS NULL OR numero_boleto = ''
        ORDER BY created_at
    LOOP
        num_pad := lpad(next_num::text, 8, '0');
        UPDATE boletos_pesaje
           SET numero_boleto = 'TA-' || num_pad
         WHERE boleto = r.boleto;
        next_num := next_num + 1;
    END LOOP;
END $$;

-- 5) Tabla kardex
CREATE TABLE IF NOT EXISTS kardex (
    id_kardex       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    id_movimiento   INTEGER NOT NULL,
    fecha_kardex    TIMESTAMP NOT NULL,
    id_producto     UUID REFERENCES productos(id_producto),
    id_almacen      UUID REFERENCES almacenes(id_almacen),
    fecha_documento TIMESTAMP,
    documento       VARCHAR(100),
    valor           NUMERIC(12,2) NOT NULL,
    boleto          UUID REFERENCES boletos_pesaje(boleto),
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_kardex_empresa_fecha ON kardex (id_empresa, fecha_kardex);
CREATE INDEX IF NOT EXISTS idx_kardex_producto_almacen ON kardex (id_producto, id_almacen);
-- =============================================================================
-- BALANSOFT-WS · Migración 024 · Ediciones con justificación, tope e impresión
-- -----------------------------------------------------------------------------
-- Requisito (cliente): un boleto solo se puede editar colocando la
-- justificación de la edición, y el administrador de la cuenta fija en
-- «Diseño de ticket» un máximo de ediciones por boleto para las otras sesiones
-- (el ADMIN nunca está sujeto al tope, pero sí justifica).
--
--   boletos_pesaje:
--     ediciones_count              INTEGER NOT NULL DEFAULT 0  → contador por boleto
--     motivo_modificacion_ultima   VARCHAR(500)                 → última justificación
--     ultimo_editor_nombre         VARCHAR(150)                 → último editor
--     max_ediciones_boleto_aplicado INTEGER                       → tope vigente al editar
--
--   empresas (config editable en «Diseño de ticket»):
--     max_ediciones_boleto   INTEGER     → NULL o 0 = sin tope
--     impresion_automatica   BOOLEAN NOT NULL DEFAULT FALSE
--     protocolo_impresion    VARCHAR(30) → predeterminada_so|raw_9100|lpd_cups|nombre_impresora
--     impresora_nombre       VARCHAR(255)
--     impresora_host         VARCHAR(100)
--     impresora_puerto       INTEGER
--
--   boletos_ediciones: historial inmutable, una fila por edición con su
--     justificación, quién/cuándo/desde qué IP y los campos antes/después.
--
-- Idempotente: seguro re-ejecutarla (mismo patrón que 022/023).
-- Reflejo obligatorio en `balansoft-ws-local.sql` (CREATE TABLE + bloque ALTER)
-- y en `sqlserver/balansoft-ws-local.sql`.
-- =============================================================================

BEGIN;

-- 1. boletos_pesaje: contador de ediciones y último motivo
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS ediciones_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS motivo_modificacion_ultima VARCHAR(500);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS ultimo_editor_nombre VARCHAR(150);
ALTER TABLE boletos_pesaje ADD COLUMN IF NOT EXISTS max_ediciones_boleto_aplicado INTEGER;

-- 2. empresas: tope de ediciones y configuración de impresión automática
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS max_ediciones_boleto INTEGER;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresion_automatica BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS protocolo_impresion VARCHAR(30);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresora_nombre VARCHAR(255);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresora_host VARCHAR(100);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresora_puerto INTEGER;

-- 3. Historial de ediciones (inmutable: solo INSERT)
CREATE TABLE IF NOT EXISTS boletos_ediciones (
    id_edicion          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa          UUID NOT NULL REFERENCES empresas(id_empresa) ON DELETE RESTRICT,
    boleto              UUID NOT NULL REFERENCES boletos_pesaje(boleto) ON DELETE RESTRICT,
    numero_boleto       VARCHAR(30),
    id_usuario          UUID REFERENCES usuarios(id_usuario) ON DELETE SET NULL,
    usuario_nombre      VARCHAR(150),
    rol_usuario         VARCHAR(30),
    fecha_edicion       TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    ip                  VARCHAR(45),
    justificacion       VARCHAR(500) NOT NULL,
    estado_anterior     VARCHAR(20) NOT NULL,
    estado_nuevo        VARCHAR(20) NOT NULL,
    campos_modificados  JSONB,
    edicion_numero      INTEGER NOT NULL,
    sync_operation_id   UUID,
    created_at          TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    CONSTRAINT ck_boletos_ediciones_estados CHECK (
        estado_anterior IN ('PENDIENTE', 'CERRADO', 'MODIFICADO') AND
        estado_nuevo IN ('PENDIENTE', 'CERRADO', 'MODIFICADO')
    ),
    CONSTRAINT ck_boletos_ediciones_edicion_num CHECK (edicion_numero >= 1),
    CONSTRAINT ck_boletos_ediciones_justificacion CHECK (char_length(trim(justificacion)) >= 10)
);

-- 4. Índices del historial
CREATE INDEX IF NOT EXISTS ix_boletos_ediciones_boleto_fecha
    ON boletos_ediciones (id_empresa, boleto, fecha_edicion);
CREATE INDEX IF NOT EXISTS ix_boletos_ediciones_boleto_num
    ON boletos_ediciones (id_empresa, boleto, edicion_numero);
CREATE INDEX IF NOT EXISTS ix_boletos_ediciones_usuario_fecha
    ON boletos_ediciones (id_usuario, fecha_edicion);
CREATE UNIQUE INDEX IF NOT EXISTS ux_boletos_ediciones_sync_op
    ON boletos_ediciones (sync_operation_id)
    WHERE sync_operation_id IS NOT NULL;

-- 5. CHECKs de la configuración de empresa
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_protocolo_impresion'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_protocolo_impresion
            CHECK (
                protocolo_impresion IS NULL OR
                protocolo_impresion IN (
                    'predeterminada_so', 'raw_9100', 'lpd_cups', 'nombre_impresora'
                )
            );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_max_ediciones_boleto'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_max_ediciones_boleto
            CHECK (max_ediciones_boleto IS NULL OR max_ediciones_boleto >= 0);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_impresora_puerto'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_impresora_puerto
            CHECK (impresora_puerto IS NULL OR impresora_puerto BETWEEN 1 AND 65535);
    END IF;
END
$$;

COMMIT;

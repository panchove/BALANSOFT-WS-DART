-- =============================================================================
-- BALANSOFT-WS · Migración 030 · Origen de la cámara (IP de red vs local/USB)
-- -----------------------------------------------------------------------------
-- La cámara de captura de placa (migración 027) nació solo como cámara **IP**
-- (`url_snapshot` = URL completa del JPEG). El cliente tiene además cámaras
-- **locales** enchufadas a la computadora (USB/integradas, `/dev/video*`), que
-- NO tienen URL de snapshot: el *frame* se captura con ffmpeg/v4l2 y el backend
-- lo sirve como si fuera un snapshot.
--
-- Se modela con dos columnas nuevas, sin romper lo existente:
--   - `origen`      → 'ip' (default, comportamiento previo) | 'local'.
--   - `dispositivo` → ruta del dispositivo para las locales (ej. `/dev/video0`).
--                     NULL para las de red (su `url_snapshot` manda).
--
-- Compatibilidad: las cámaras ya registradas quedan `origen='ip'` y siguen
-- funcionando igual. `url_snapshot` deja de ser obligatorio en el modelo (el
-- DDL conserva el NOT NULL con default '' para no alterar filas existentes; las
-- locales lo llevan vacío y NO se usa).
--
-- Reflejo obligatorio en `balansoft-ws-local.sql` y en
-- `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 022/026/027).
-- =============================================================================

ALTER TABLE camaras
    ADD COLUMN IF NOT EXISTS origen VARCHAR(10) NOT NULL DEFAULT 'ip';

ALTER TABLE camaras
    ADD COLUMN IF NOT EXISTS dispositivo VARCHAR(255);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_camaras_origen'
    ) THEN
        ALTER TABLE camaras
            ADD CONSTRAINT ck_camaras_origen
            CHECK (origen IN ('ip', 'local'));
    END IF;
END
$$;

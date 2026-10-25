-- =============================================================================
-- BALANSOFT-WS · Migración 027 · Cámaras de placa + fotos de placa por boleto
-- -----------------------------------------------------------------------------
-- Registra las **cámaras** de la estación como dispositivo del módulo
-- Dispositivos (gemela de `balanzas` y `semaforos`). Cada cámara apunta a un
-- snapshot HTTP/JPEG (`url_snapshot`, puede traer credenciales embebidas o
-- usar `usuario`/`password`) y declara en qué momento se la usa:
--   ubicacion = entrada | salida | ambos
--
-- Regla de negocio (confirmada por el cliente): las fotos de placa se piden
-- **una sola vez por boleto**, en la pesada que el operador elija (entrada o
-- salida); una vez capturadas NO se vuelven a pedir en la otra pesada.
--   - `boletos_pesaje.fotos_placa_tomadas` (flag persistido, viaja en el sync)
--     marca ese "ya se pidieron"; las imágenes en sí son media LOCAL.
--   - `empresas.fotos_placa_activas`      → el bloque aparece en el formulario.
--   - `empresas.fotos_placa_obligatorias` → sin fotos no se guarda la pesada.
--
-- Las fotos se guardan como media del boleto (`media/<boleto>/placa_*.jpg`) con
-- fila en `imagenes_pesaje.tipo = 'placa'` (mismo endpoint de imágenes de
-- pesaje), y **NUNCA** se incluyen en el ticket/PDF/TXT.
--
-- Reflejo obligatorio en `balansoft-ws-local.sql` y en
-- `sqlserver/balansoft-ws-local.sql`.
-- Idempotente: seguro re-ejecutarlo (mismo patrón que 022/026).
-- =============================================================================

CREATE TABLE IF NOT EXISTS camaras (
    id_camara     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo        VARCHAR(20),
    descripcion   VARCHAR(150) NOT NULL,
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulada   BOOLEAN NOT NULL DEFAULT FALSE,
    url_snapshot  VARCHAR(500) NOT NULL,
    usuario       VARCHAR(100),
    password      VARCHAR(255),
    ubicacion     VARCHAR(10) NOT NULL DEFAULT 'ambos',
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS camaras_empresa_codigo_uk
    ON camaras (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_camaras_ubicacion'
    ) THEN
        ALTER TABLE camaras
            ADD CONSTRAINT ck_camaras_ubicacion
            CHECK (ubicacion IN ('entrada', 'salida', 'ambos'));
    END IF;
END
$$;

-- Flag "las fotos de placa de este boleto ya se pidieron" (una sola vez).
ALTER TABLE boletos_pesaje
    ADD COLUMN IF NOT EXISTS fotos_placa_tomadas BOOLEAN NOT NULL DEFAULT FALSE;

-- Interruptores por empresa del bloque de fotos de placa.
ALTER TABLE empresas
    ADD COLUMN IF NOT EXISTS fotos_placa_activas BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE empresas
    ADD COLUMN IF NOT EXISTS fotos_placa_obligatorias BOOLEAN NOT NULL DEFAULT FALSE;

-- =============================================================================
-- BALANSOFT-WS · Migración 025 · Rol OPERADOR y llaves de activación
-- -----------------------------------------------------------------------------
-- Cambios:
-- 1. Fusiona el rol de usuario TRABAJADOR dentro de OPERADOR (quedan 3 roles:
--    ADMIN, OPERADOR, AUDITOR) en `usuarios` y `permisos_acceso`.
-- 2. Crea la tabla `llaves_activacion` (llaves de un solo uso para las
--    estaciones OPERADOR / cliente delgado).
--
-- Notas:
-- - `dispositivos` (con `chk_dispositivos_rol_sesion`) vive **solo** en la BD
--   del servidor central; su CHECK se actualiza en `balansoft-ws-server.sql`.
-- 2. Idempotente: puede reejecutarse sin efectos secundarios.
-- =============================================================================

BEGIN;

-- 1. Datos: fusionar el rol TRABAJADOR dentro de OPERADOR
UPDATE usuarios
   SET rol = 'OPERADOR',
       updated_at = CURRENT_TIMESTAMP
 WHERE rol = 'TRABAJADOR';

-- permisos_acceso: la PK es (id_empresa, rol, modulo), así que antes de
-- renombrar hay que borrar las filas TRABAJADOR que colisionarían con una
-- fila OPERADOR ya existente (el valor de OPERADOR manda).
DELETE FROM permisos_acceso t
 WHERE t.rol = 'TRABAJADOR'
   AND EXISTS (
       SELECT 1 FROM permisos_acceso o
        WHERE o.id_empresa = t.id_empresa
          AND o.modulo = t.modulo
          AND o.rol = 'OPERADOR'
   );

UPDATE permisos_acceso
   SET rol = 'OPERADOR',
       updated_at = CURRENT_TIMESTAMP
 WHERE rol = 'TRABAJADOR';

-- 2. TABLA llaves_activacion (local)
CREATE TABLE IF NOT EXISTS llaves_activacion (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa) ON DELETE CASCADE,
  id_usuario        UUID NOT NULL REFERENCES usuarios(id_usuario) ON DELETE CASCADE,
  codigo_hash       VARCHAR(255) NOT NULL,
  codigo_preview    VARCHAR(40),
  estado            VARCHAR(20) NOT NULL DEFAULT 'activa',
  expira_en         TIMESTAMP,
  consumida_en      TIMESTAMP,
  consumida_por_hw  VARCHAR(255),
  ip_consumo        VARCHAR(45),
  user_agent        VARCHAR(255),
  creado_por        UUID REFERENCES usuarios(id_usuario),
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_estado_llave CHECK (estado IN ('activa','consumida','revocada'))
);

CREATE INDEX IF NOT EXISTS idx_llaves_empresa_usuario ON llaves_activacion (id_empresa,id_usuario);
CREATE INDEX IF NOT EXISTS idx_llaves_estado ON llaves_activacion (estado);
CREATE UNIQUE INDEX IF NOT EXISTS uq_llaves_codigo_hash ON llaves_activacion (codigo_hash);

-- 3. CHECK de usuarios: quitar TRABAJADOR de los roles válidos
DO $$
BEGIN
  IF EXISTS (
      SELECT 1 FROM pg_constraint
       WHERE conname = 'chk_rol_usuario'
         AND conrelid = 'usuarios'::regclass
  ) THEN
    ALTER TABLE usuarios DROP CONSTRAINT chk_rol_usuario;
  END IF;
  ALTER TABLE usuarios
    ADD CONSTRAINT chk_rol_usuario
    CHECK (rol IN ('ADMIN','OPERADOR','AUDITOR'));
END$$;

-- Default del rol de usuario: OPERADOR (antes TRABAJADOR)
ALTER TABLE usuarios
  ALTER COLUMN rol SET DEFAULT 'OPERADOR';

-- Nota: `dispositivos` (con `chk_dispositivos_rol_sesion`) vive **solo** en la
-- BD del servidor central; su CHECK se actualiza en `balansoft-ws-server.sql`.

-- 4. Verificación (comentarios)
-- Tras esta migración: usuarios con rol TRABAJADOR = 0 (esperado)
--                      permisos_acceso con rol TRABAJADOR = 0 (esperado)

COMMIT;

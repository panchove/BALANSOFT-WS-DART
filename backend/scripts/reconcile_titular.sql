-- ============================================================
-- BALANSOFT-WS — Reconciliación del equipo TITULAR de una cuenta (rol server)
--
-- Uso (desde scripts/reconcile_titular.sh, que resuelve la URI):
--   psql "$URI" -v cuenta=<uuid> -v hw_nuevo=<machine-id> -v hw_viejo=<old|''> \
--        -v apply=0|1 -f reconcile_titular.sql
--
-- Qué hace, en una sola transacción:
--   1. Localiza la fila del hardware NUEVO y la del titular VIEJO.
--   2. Si el hardware nuevo no tiene fila y sí existe la del titular viejo,
--      RE-IDENTIFICA esa fila (preserva id_dispositivo → sesiones, sync,
--      historial de FK). Nunca hace DELETE.
--   3. Si no existe ninguna de las dos, CREA la fila del titular.
--   4. Promueve la fila del hardware nuevo a SERVIDOR_LOCAL / APROBADO /
--      ADMIN / activo (idempotente).
--   5. Reata la licencia ACTIVA de la cuenta al hardware nuevo y limpia el
--      hardware viejo de otras licencias (un solo dueño).
--   6. Degrada a LOCAL cualquier otro SERVIDOR_LOCAL de la cuenta.
--
-- Invariantes: filtra SIEMPRE por id_cuenta (multi-tenant); no borra filas;
-- re-ejecutable (no-op si ya está reconciliado).
-- ============================================================

\set ON_ERROR_STOP on

BEGIN;

-- Normaliza el hardware viejo: si no se pasa, usa el titular actual de la
-- licencia activa de la cuenta (misma regla que _licencia_activa del backend).
CREATE TEMP TABLE _rec ON COMMIT DROP AS
SELECT
    (SELECT d.id_dispositivo
       FROM dispositivos d
      WHERE d.id_cuenta = :'cuenta'::uuid
        AND btrim(d.hardware_id) = btrim(:'hw_nuevo')
      ORDER BY d.created_at
      LIMIT 1) AS id_nuevo,
    (SELECT d.id_dispositivo
       FROM dispositivos d
      WHERE d.id_cuenta = :'cuenta'::uuid
        AND btrim(d.hardware_id) = btrim(
              COALESCE(
                NULLIF(btrim(:'hw_viejo'), ''),
                (SELECT l.hardware_id
                   FROM licencias l
                  WHERE l.id_cuenta = :'cuenta'::uuid
                    AND l.hardware_id IS NOT NULL
                  ORDER BY l.fecha_expira ASC
                  LIMIT 1),
                ''))
      ORDER BY d.created_at
      LIMIT 1) AS id_viejo;

\echo '--- ANTES ------------------------------------------------------------'
SELECT id_dispositivo, btrim(hardware_id) AS hardware_id, rol_dispositivo,
       estado, rol_sesion, activo
  FROM dispositivos
 WHERE id_cuenta = :'cuenta'::uuid
 ORDER BY created_at;
SELECT licencia_key, licencia_status, licencia_tier, btrim(hardware_id) AS hardware_id
  FROM licencias
 WHERE id_cuenta = :'cuenta'::uuid
 ORDER BY fecha_expira;

-- 2) Re-identificar la fila del titular viejo si el hardware nuevo no existe.
UPDATE dispositivos d
   SET hardware_id      = btrim(:'hw_nuevo'),
       rol_dispositivo  = 'SERVIDOR_LOCAL',
       estado           = 'APROBADO',
       rol_sesion       = COALESCE(NULLIF(btrim(d.rol_sesion), ''), 'ADMIN'),
       activo           = TRUE,
       updated_at       = now()
 WHERE d.id_dispositivo = (SELECT id_viejo FROM _rec)
   AND (SELECT id_nuevo FROM _rec) IS NULL;

-- 3) Si no existía ninguna de las dos filas, crear el titular.
INSERT INTO dispositivos (id_cuenta, hardware_id, nombre_equipo, rol_dispositivo,
                          estado, rol_sesion, activo, created_at, updated_at)
SELECT :'cuenta'::uuid, btrim(:'hw_nuevo'), 'Equipo titular',
       'SERVIDOR_LOCAL', 'APROBADO', 'ADMIN', TRUE, now(), now()
 WHERE (SELECT id_nuevo FROM _rec) IS NULL
   AND (SELECT id_viejo FROM _rec) IS NULL;

-- 4) Promover la fila del hardware nuevo (idempotente).
UPDATE dispositivos
   SET rol_dispositivo = 'SERVIDOR_LOCAL',
       estado          = 'APROBADO',
       rol_sesion      = COALESCE(NULLIF(btrim(rol_sesion), ''), 'ADMIN'),
       activo          = TRUE,
       updated_at      = now()
 WHERE id_cuenta = :'cuenta'::uuid
   AND btrim(hardware_id) = btrim(:'hw_nuevo');

-- 5a) Reatar la licencia ACTIVA de la cuenta al hardware nuevo.
UPDATE licencias
   SET hardware_id = btrim(:'hw_nuevo'),
       updated_at  = now()
 WHERE id_licencia = (
        SELECT l.id_licencia
          FROM licencias l
         WHERE l.id_cuenta = :'cuenta'::uuid
           AND upper(l.licencia_status) IN ('ACTIVA', 'AVAILABLE', 'ACTIVE')
           AND l.fecha_expira >= now()
         ORDER BY l.fecha_expira ASC
         LIMIT 1);

-- 5b) Quitar el hardware viejo de CUALQUIER otra licencia de la cuenta
--     (impide un segundo dueño).
UPDATE licencias
   SET hardware_id = NULL,
       updated_at  = now()
 WHERE id_cuenta = :'cuenta'::uuid
   AND btrim(COALESCE(hardware_id, '')) = btrim(:'hw_viejo')
   AND btrim(COALESCE(hardware_id, '')) <> btrim(:'hw_nuevo');

-- 6) Un solo SERVIDOR_LOCAL por cuenta.
UPDATE dispositivos
   SET rol_dispositivo = 'LOCAL',
       updated_at      = now()
 WHERE id_cuenta = :'cuenta'::uuid
   AND btrim(hardware_id) <> btrim(:'hw_nuevo')
   AND rol_dispositivo = 'SERVIDOR_LOCAL';

\echo '--- DESPUES ----------------------------------------------------------'
SELECT id_dispositivo, btrim(hardware_id) AS hardware_id, rol_dispositivo,
       estado, rol_sesion, activo
  FROM dispositivos
 WHERE id_cuenta = :'cuenta'::uuid
 ORDER BY created_at;
SELECT licencia_key, licencia_status, licencia_tier, btrim(hardware_id) AS hardware_id
  FROM licencias
 WHERE id_cuenta = :'cuenta'::uuid
 ORDER BY fecha_expira;

-- :apply = 1 → confirma; cualquier otro valor → ensayo (ROLLBACK).
\if :apply
COMMIT;
\else
\echo '*** ENSAYO (no se aplicó nada). Repite con APPLY=1 para confirmar. ***'
ROLLBACK;
\endif

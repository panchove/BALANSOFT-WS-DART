-- ============================================================
-- 007_balanza_simulada.sql
-- Marca si la báscula es simulada (apunta al simulador BSDD)
-- o física. Complementa el módulo de dispositivos: al añadir
-- una báscula se pregunta si será simulada y el escaneo
-- detecta las básculas conectadas disponibles.
-- ============================================================

ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS is_simulada BOOLEAN NOT NULL DEFAULT FALSE;
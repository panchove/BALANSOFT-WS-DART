-- ============================================================
-- 005_balanza_hardware.sql
-- Configuración de hardware de balanza para el HAL (B7):
-- lectura de peso en vivo vía serial (puerto_com) o TCP
-- (ip_address + puerto_tcp). Todos los campos son nullable;
-- sin configuración, la balanza no tiene lectura hardware.
-- ============================================================

ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS puerto_com VARCHAR(50);
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS ip_address VARCHAR(45);
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS puerto_tcp INTEGER;
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS protocolo VARCHAR(20) DEFAULT 'tcp';
-- ============================================================
-- 008_empresa_perfil.sql
-- Perfil de la empresa local: logo para tickets y reportes.
-- El resto de los datos de contacto (dirección, teléfono, email)
-- ya existen en la tabla `empresas`.
-- ============================================================

ALTER TABLE empresas ADD COLUMN IF NOT EXISTS logo_url VARCHAR(500);

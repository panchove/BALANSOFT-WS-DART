-- =============================================================================
-- BALANSOFT-WS · Seed de datos demo de la estación SERVIDOR (Variedades S&S)
-- Restaura la operación de prueba tras un reset_total.sh (que respalda las BDs
-- desde v1.2.7 y, antes, solo el estado de la app).
--
-- Uso:  psql -v ON_ERROR_STOP=1 -h localhost -U sqlman -d balansoft_ws_local -f seed_reset_demo.sql
-- Nota: cambia :'EMP' si la empresa local regenerada tiene otro id.
-- =============================================================================
\set EMP 'b1cf7bbe-d540-488e-91ff-7f77cfa83240'

BEGIN;

-- Guard: si la empresa ya tiene boletos (p.ej. el seed ya corrió o hay operación
-- real), se aborta todo el lote ANTES de insertar nada (previene duplicados).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM boletos_pesaje WHERE id_empresa = 'b1cf7bbe-d540-488e-91ff-7f77cfa83240') THEN
        RAISE EXCEPTION 'La empresa ya tiene boletos. El seed NO aplica (evita duplicados).';
    END IF;
END $$;

-- Transportes (TRP-01 / TRP-02) ----------------------------------------------
INSERT INTO transportes (id_transporte, id_empresa, codigo, razon_social, activo, created_at, updated_at) VALUES
('fe000000-0000-0000-0000-000000000001', :'EMP', 'TRP-01', 'Transportes Expresos del Centro C.A.', TRUE, NOW(), NOW()),
('fe000000-0000-0000-0000-000000000002', :'EMP', 'TRP-02', 'Logística y Carga Pesada R.L.', TRUE, NOW(), NOW());

-- Conductores (por cédula) ------------------------------------------------------
INSERT INTO conductores (cedula_dni, id_empresa, nombre_completo, activo, created_at, updated_at) VALUES
('V-18293041', :'EMP', 'Carlos Eduardo Mendoza', TRUE, NOW(), NOW()),
('V-20192834', :'EMP', 'José Luis Rodríguez', TRUE, NOW(), NOW()),
('V-15928301', :'EMP', 'Manuel Enrique Silva', TRUE, NOW(), NOW());

-- Categorías de producto ----------------------------------------------------------
INSERT INTO categorias (id_categoria, id_empresa, codigo, nombre, activo, created_at, updated_at) VALUES
('f2000000-0000-0000-0000-000000000001', :'EMP', 'CEMENTO', 'Cementos', TRUE, NOW(), NOW()),
('f2000000-0000-0000-0000-000000000002', :'EMP', 'HARINAS', 'Harinas', TRUE, NOW(), NOW()),
('f2000000-0000-0000-0000-000000000003', :'EMP', 'GRANOS', 'Graneles Agrícolas', TRUE, NOW(), NOW());

-- Productos ----------------------------------------------------------------------
INSERT INTO productos (id_producto, id_empresa, id_categoria, codigo, nombre, es_kardex, activo, created_at, updated_at) VALUES
('f1000000-0000-0000-0000-000000000004', :'EMP', 'f2000000-0000-0000-0000-000000000001', 'CEM-GRANEL',   'Cemento Tipo I a Granel', FALSE, TRUE, NOW(), NOW()),
('f1000000-0000-0000-0000-000000000001', :'EMP', 'f2000000-0000-0000-0000-000000000002', 'HAR-TRIGO',    'Harina de Trigo Industrial (Sacos)', FALSE, TRUE, NOW(), NOW()),
('f1000000-0000-0000-0000-000000000002', :'EMP', 'f2000000-0000-0000-0000-000000000003', 'ARROZ-GRANEL', 'Arroz a Granel', FALSE, TRUE, NOW(), NOW());

-- Almacenes ------------------------------------------------------------------------
INSERT INTO almacenes (id_almacen, id_empresa, codigo, nombre, activo, created_at, updated_at) VALUES
('fa000000-0000-0000-0000-000000000001', :'EMP', 'SILO-01', 'Silo Principal - Materia Prima', TRUE, NOW(), NOW()),
('fa000000-0000-0000-0000-000000000002', :'EMP', 'ALM-CENTRO', 'Almacén Central Víveres', TRUE, NOW(), NOW());

-- Balanza ---------------------------------------------------------------------------
INSERT INTO balanzas (id_balanza, id_empresa, codigo, descripcion, activo, is_simulada, created_at, updated_at) VALUES
('fb000000-0000-0000-0000-000000000001', :'EMP', 'BLC-01', 'Balanza Camionera Entrada/Salida', TRUE, FALSE, NOW(), NOW());

-- Tercero (proveedor) ----------------------------------------------------------------
INSERT INTO terceros (id_tercero, id_empresa, codigo, tipo, razon_social, activo, created_at, updated_at) VALUES
('fc000000-0000-0000-0000-000000000001', :'EMP', 'PROV-CEM', 'PROVEEDOR', 'Corporación Venezolana de Cemento', TRUE, NOW(), NOW());

-- Remolque ----------------------------------------------------------------------------
INSERT INTO remolques (id_remolque, id_empresa, placa, activo, created_at, updated_at) VALUES
('fd000000-0000-0000-0000-000000000001', :'EMP', 'RAP55M', TRUE, NOW(), NOW());

-- Camiones (con transporte asignado) ---------------------------------------------------
INSERT INTO camiones (id, id_empresa, placa, transporte_id, color, tara_habitual, activo, created_at, updated_at) VALUES
(gen_random_uuid(), :'EMP', 'RAP44W', 'fe000000-0000-0000-0000-000000000001', NULL, NULL, TRUE, NOW(), NOW()),
(gen_random_uuid(), :'EMP', 'A99ZZ0', 'fe000000-0000-0000-0000-000000000002', NULL, NULL, TRUE, NOW(), NOW()),
(gen_random_uuid(), :'EMP', 'A31CX8', 'fe000000-0000-0000-0000-000000000001', NULL, NULL, TRUE, NOW(), NOW());

-- Serie de numeración (continúa en BOL-2026-0004) --------------------------------------
INSERT INTO series_numeracion (id_serie, id_empresa, nombre, prefijo, inicio, siguiente, digitos, activa, created_at, updated_at) VALUES
('aa000001-0000-0000-0000-000000000001', :'EMP', 'BOLETOS', 'BOL-2026', 1, 4, 4, TRUE, NOW(), NOW());

-- Boletos (01 y 03: datos exactos recuperados; 02: reconstruido coherente) --------------
INSERT INTO boletos_pesaje (
  boleto, numero_boleto, id_empresa, id_vehiculo, remolque, id_remolque, id_transporte,
  id_conductor, id_producto, id_almacen, id_balanza, tipo_tercero, id_tercero,
  multi_despacho_recepcion, fecha_hora_entrada, peso_entrada_vehiculo, peso_entrada_remolque,
  fecha_hora_salida, peso_salida_vehiculo, peso_salida_remolque, documento, flete, costo_flete,
  observaciones, creado_por, salida_por, peso_total_entrada, peso_total_salida, peso_neto,
  estado_boleto, sincronizado, created_at, updated_at, id_serie
) VALUES
(
 'fb000000-0000-0000-0000-000000000001', 'BOL-2026-0001', :'EMP', 'RAP44W', TRUE,
 'fd000000-0000-0000-0000-000000000001', 'fe000000-0000-0000-0000-000000000001',
 'V-18293041', 'f1000000-0000-0000-0000-000000000004', 'fa000000-0000-0000-0000-000000000001',
 'fb000000-0000-0000-0000-000000000001', 'PROVEEDOR', 'fc000000-0000-0000-0000-000000000001',
 FALSE, '2026-09-28 07:30:00', 38250.00, NULL, '2026-09-28 08:45:00', 15800.00, NULL,
 'FAC-2026-1042', 'FLT-882', 320.00, 'Despacho Cemento a Granel. Boleto completado.',
 'operador1', 'operador1', 38250.00, 15800.00, 22450.00,
 'CERRADO', TRUE, '2026-09-28 12:23:40.365339', '2026-09-28 12:23:40.365339', 'aa000001-0000-0000-0000-000000000001'
),
(
 'fb000000-0000-0000-0000-000000000002', 'BOL-2026-0002', :'EMP', 'A99ZZ0', FALSE,
 NULL, 'fe000000-0000-0000-0000-000000000002', 'V-20192834',
 'f1000000-0000-0000-0000-000000000001', 'fa000000-0000-0000-0000-000000000002',
 'fb000000-0000-0000-0000-000000000001', 'PROVEEDOR', 'fc000000-0000-0000-0000-000000000001',
 FALSE, '2026-09-28 09:15:00', 42500.00, NULL, '2026-09-28 10:55:00', 18250.00, NULL,
 'FAC-2026-1043', 'FLT-883', 300.00, 'Carga de Harina de Trigo en Sacos. Boleto completado.',
 'operador1', 'operador1', 42500.00, 18250.00, 24250.00,
 'CERRADO', TRUE, '2026-09-28 12:23:40.365339', '2026-09-28 12:23:40.365339', 'aa000001-0000-0000-0000-000000000001'
),
(
 'fb000000-0000-0000-0000-000000000003', 'BOL-2026-0003', :'EMP', 'A31CX8', FALSE,
 NULL, 'fe000000-0000-0000-0000-000000000001', 'V-15928301',
 'f1000000-0000-0000-0000-000000000002', 'fa000000-0000-0000-0000-000000000002',
 'fb000000-0000-0000-0000-000000000001', 'PROVEEDOR', 'fc000000-0000-0000-0000-000000000001',
 FALSE, '2026-09-28 10:00:00', 36500.00, NULL, NULL, NULL, NULL,
 'FAC-2026-1044', 'FLT-884', 280.00, 'Recepción de Arroz. Pendiente pesaje de tara en salida.',
 'operador1', NULL, 36500.00, NULL, NULL,
 'PENDIENTE', FALSE, '2026-09-28 12:23:40.365339', '2026-09-28 12:23:40.365339', 'aa000001-0000-0000-0000-000000000001'
);

COMMIT;
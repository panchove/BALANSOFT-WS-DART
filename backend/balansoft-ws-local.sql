-- ============================================================
-- BALANSOFT-WS-LOCAL - SCHEMA OPERATIVO (MÁQUINA DEL CLIENTE)
-- Una sola empresa por máquina. Contiene TODO lo operativo:
-- usuarios locales con roles, flota, inventario, boletos,
-- kardex, auditoría local, configuración, etc.
-- Se sincroniza con balansoft_ws (servidor) mediante sync.
-- ============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 0. IDENTIDAD LOCAL (vínculo con la cuenta del servidor)
-- Solo una fila. Guarda el id_cuenta y datos de la licencia
-- cacheados para permitir trabajo offline.
-- ============================================================
CREATE TABLE IF NOT EXISTS identidad_local (
    id                  BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id = TRUE), -- solo 1 fila
    id_cuenta           UUID NOT NULL,           -- FK lógica a balansoft_ws.cuentas
    rif_nit             VARCHAR(20) NOT NULL,
    nombre_fiscal       VARCHAR(255) NOT NULL,
    nombre_comercial    VARCHAR(255),
    licencia_key        VARCHAR(255),
    licencia_tier       VARCHAR(20),
    licencia_status     VARCHAR(20),
    licencia_expira     TIMESTAMP,
    hardware_id         VARCHAR(255),            -- huella de esta máquina
    rol_dispositivo     VARCHAR(20) NOT NULL DEFAULT 'LOCAL', -- LOCAL / SERVIDOR_LOCAL
    ultima_validacion   TIMESTAMP,               -- última vez que se validó online
    modo_offline        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 1. EMPRESA (espejo local de la cuenta, para FKs internas)
-- ============================================================
CREATE TABLE IF NOT EXISTS empresas (
    id_empresa       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_cuenta        UUID,                          -- vínculo 1:1 con la cuenta del servidor
    nombre_fiscal    VARCHAR(255) NOT NULL,
    nombre_comercial VARCHAR(255),
    rif_nit          VARCHAR(20) NOT NULL UNIQUE,
    direccion        TEXT,
    telefono         VARCHAR(50),
    email            VARCHAR(255),
    logo_url         VARCHAR(500),
    formato_ticket   VARCHAR(10) DEFAULT 'PDF',
    formato_reporte  VARCHAR(10) DEFAULT 'EXCEL',
    idioma           VARCHAR(5) DEFAULT 'es',
    ruta_exportacion_reportes VARCHAR(500),
    tamano_ticket_pdf VARCHAR(20) DEFAULT 'AUTOMATICO',
    fuente_ticket_pdf VARCHAR(20) DEFAULT 'DejaVu',
    -- Configuración de edición e impresión
    max_ediciones_boleto INTEGER,
    impresion_automatica BOOLEAN NOT NULL DEFAULT FALSE,
    protocolo_impresion  VARCHAR(30),
    impresora_nombre     VARCHAR(255),
    impresora_host       VARCHAR(100),
    impresora_puerto     INTEGER,
    -- Fotos de placa (migración 027): activa el bloque y lo hace obligatorio.
    fotos_placa_activas      BOOLEAN NOT NULL DEFAULT FALSE,
    fotos_placa_obligatorias BOOLEAN NOT NULL DEFAULT FALSE,
    -- Snapshot de la licencia (validada contra el servidor central en login)
    licencia_key     VARCHAR(255),
    licencia_tier    VARCHAR(20),
    licencia_status  VARCHAR(20),
    licencia_expira  TIMESTAMP,
    -- Identidad del cliente en el License Manager (LM), asignada durante el setup inicial.
    lm_client_id     UUID,
    lm_client_email  VARCHAR(255),
    activa           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Alineación idempotente para BDs creadas antes del snapshot de licencia.
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_key VARCHAR(255);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_tier VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_status VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS licencia_expira TIMESTAMP;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS lm_client_id UUID;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS lm_client_email VARCHAR(255);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS formato_ticket VARCHAR(10);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS ruta_exportacion_reportes VARCHAR(500);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS idioma VARCHAR(5) DEFAULT 'es';
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS formato_reporte VARCHAR(10) DEFAULT 'EXCEL';
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS tamano_ticket_pdf VARCHAR(20);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS fuente_ticket_pdf VARCHAR(20);
UPDATE empresas SET idioma = 'es' WHERE idioma IS NULL;
UPDATE empresas SET formato_reporte = 'EXCEL' WHERE formato_reporte IS NULL;
UPDATE empresas SET tamano_ticket_pdf = 'AUTOMATICO' WHERE tamano_ticket_pdf IS NULL;
UPDATE empresas SET fuente_ticket_pdf = 'DejaVu' WHERE fuente_ticket_pdf IS NULL;
ALTER TABLE empresas ALTER COLUMN tamano_ticket_pdf SET DEFAULT 'AUTOMATICO';
ALTER TABLE empresas ALTER COLUMN fuente_ticket_pdf SET DEFAULT 'DejaVu';


ALTER TABLE empresas ADD COLUMN IF NOT EXISTS max_ediciones_boleto INTEGER;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresion_automatica BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS protocolo_impresion VARCHAR(30);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresora_nombre VARCHAR(255);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresora_host VARCHAR(100);
ALTER TABLE empresas ADD COLUMN IF NOT EXISTS impresora_puerto INTEGER;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_tamano_ticket_pdf'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_tamano_ticket_pdf
            CHECK (tamano_ticket_pdf IN ('AUTOMATICO', 'GRANDE', 'MEDIANO', 'PEQUENO'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_fuente_ticket_pdf'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_fuente_ticket_pdf
            CHECK (fuente_ticket_pdf IN ('DejaVu'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_empresas_protocolo_impresion'
    ) THEN
        ALTER TABLE empresas
            ADD CONSTRAINT ck_empresas_protocolo_impresion
            CHECK (
                protocolo_impresion IS NULL OR
                protocolo_impresion IN ('predeterminada_so','raw_9100','lpd_cups','nombre_impresora')
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

ALTER TABLE empresas ALTER COLUMN id_cuenta DROP NOT NULL;

-- ============================================================
-- 2. USUARIOS LOCALES (creados por el ADMIN local)
-- Roles: ADMIN / OPERADOR / AUDITOR
-- El login se valida contra el servidor, pero el perfil
-- operativo vive aquí.
-- ============================================================
CREATE TABLE IF NOT EXISTS usuarios (
    id_usuario       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa       UUID NOT NULL REFERENCES empresas(id_empresa),
    -- Vínculo con la credencial global del servidor
    id_credencial    UUID,                       -- FK lógica a balansoft_ws.credenciales
    nombre           VARCHAR(150) NOT NULL,
    email            VARCHAR(255) NOT NULL UNIQUE,
    password_hash    VARCHAR(255),               -- caché local para modo offline
    rol              VARCHAR(30) NOT NULL DEFAULT 'OPERADOR',
                     -- ADMIN / OPERADOR / AUDITOR (el antiguo TRABAJADOR se
                     -- fusionó en OPERADOR en la migración 025)
    activo           BOOLEAN NOT NULL DEFAULT TRUE,
    ultimo_login     TIMESTAMP,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_rol_usuario CHECK (rol IN ('ADMIN','OPERADOR','AUDITOR'))
);

CREATE INDEX IF NOT EXISTS idx_usuarios_empresa ON usuarios (id_empresa);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol ON usuarios (rol, activo);

-- ============================================================
-- 3. DIRECTORIO / TRANSPORTES
-- ============================================================
CREATE TABLE IF NOT EXISTS transportes (
    id_transporte         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa            UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo                VARCHAR(20),
    razon_social          VARCHAR(150) NOT NULL,
    identificacion_fiscal VARCHAR(20),
    telefono              VARCHAR(50),
    contacto              VARCHAR(150),
    activo                BOOLEAN NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS transportes_empresa_codigo_uk
    ON transportes (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

-- ============================================================
-- 4. FLOTA
-- ============================================================
CREATE TABLE IF NOT EXISTS marcas (
    id_marca     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa   UUID NOT NULL REFERENCES empresas(id_empresa),
    nombre       VARCHAR(100) NOT NULL,
    logo_url     VARCHAR(500),
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_marcas_empresa_nombre ON marcas (id_empresa, nombre);

CREATE TABLE IF NOT EXISTS modelos_camion (
    id_modelo_camion     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa           UUID NOT NULL REFERENCES empresas(id_empresa),
    marca_id             UUID REFERENCES marcas(id_marca),
    nombre               VARCHAR(100) NOT NULL,
    capacidad_carga_ton  NUMERIC(12,2),
    foto_referencial_url VARCHAR(500),
    ejes                 INTEGER,
    created_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_modelos_empresa_nombre ON modelos_camion (id_empresa, nombre);

CREATE TABLE IF NOT EXISTS camiones (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    placa         VARCHAR(20) NOT NULL,
    modelo_id     UUID REFERENCES modelos_camion(id_modelo_camion),
    transporte_id UUID REFERENCES transportes(id_transporte),
    color         VARCHAR(50),
    foto_real_url VARCHAR(500),
    tara_habitual NUMERIC(12,2),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_camiones_empresa_placa ON camiones (id_empresa, placa);

CREATE TABLE IF NOT EXISTS remolques (
    id_remolque   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    placa         VARCHAR(20) NOT NULL,
    tipo_remolque VARCHAR(100),
    tara_habitual NUMERIC(12,2),
    foto_url      VARCHAR(500),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_remolques_empresa ON remolques (id_empresa, placa);

-- ============================================================
-- 5. DIRECTORIO (conductores, terceros)
-- ============================================================
CREATE TABLE IF NOT EXISTS conductores (
    cedula_dni        VARCHAR(20) PRIMARY KEY,
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    nombre_completo   VARCHAR(200) NOT NULL,
    telefono          VARCHAR(50),
    licencia_conducir VARCHAR(50),
    foto_url          VARCHAR(500),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS terceros (
    id_tercero            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa            UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo                VARCHAR(20),
    tipo                  VARCHAR(30) NOT NULL,
    razon_social          VARCHAR(200) NOT NULL,
    identificacion_fiscal VARCHAR(20),
    direccion             TEXT,
    telefono              VARCHAR(50),
    email                 VARCHAR(255),
    activo                BOOLEAN NOT NULL DEFAULT TRUE,
    created_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS terceros_empresa_codigo_uk
    ON terceros (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

-- ============================================================
-- 6. INVENTARIO
-- ============================================================
CREATE TABLE IF NOT EXISTS categorias (
    id_categoria      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo            VARCHAR(50),
    nombre            VARCHAR(150) NOT NULL,
    descripcion       VARCHAR(200),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS categorias_empresa_codigo_uk
    ON public.categorias (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE TABLE IF NOT EXISTS productos (
    id_producto       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    id_categoria      UUID NOT NULL REFERENCES categorias(id_categoria),
    codigo            VARCHAR(50),
    nombre            VARCHAR(150) NOT NULL,
    descripcion       VARCHAR(200),
    densidad_estandar NUMERIC(8,4),
    unidad_medida     VARCHAR(20) NOT NULL DEFAULT 'TON',
    es_kardex         BOOLEAN NOT NULL DEFAULT FALSE,
    tolerancia        NUMERIC(8,4),
    peso_unidad       NUMERIC(12,4),
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS productos_empresa_codigo_uk
    ON productos (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE TABLE IF NOT EXISTS almacenes (
    id_almacen        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo            VARCHAR(20),
    nombre            VARCHAR(150) NOT NULL,
    ubicacion         VARCHAR(255),
    capacidad_max_ton NUMERIC(12,2),
    stock_actual_ton  NUMERIC(12,2) NOT NULL DEFAULT 0,
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS almacenes_empresa_codigo_uk
    ON almacenes (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

CREATE TABLE IF NOT EXISTS balanzas (
    id_balanza    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo        VARCHAR(20),
    descripcion   VARCHAR(150) NOT NULL,
    marca         VARCHAR(100),
    modelo        VARCHAR(100),
    capacidad_max NUMERIC(12,2),
    division      NUMERIC(12,2),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulada   BOOLEAN NOT NULL DEFAULT FALSE,
    puerto_com    VARCHAR(50),
    ip_address    VARCHAR(45),
    puerto_tcp    INTEGER,
    protocolo     VARCHAR(20) DEFAULT 'tcp',
    formato_trama VARCHAR(10) NOT NULL DEFAULT 'auto',
    baudrate      INTEGER NOT NULL DEFAULT 9600,
    delimitador   VARCHAR(10),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS balanzas_empresa_codigo_uk
    ON balanzas (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

-- Alineación idempotente para BDs creadas antes del formato de trama (022).
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS formato_trama VARCHAR(10);
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS baudrate INTEGER;
ALTER TABLE balanzas ADD COLUMN IF NOT EXISTS delimitador VARCHAR(10);
UPDATE balanzas SET formato_trama = 'auto' WHERE formato_trama IS NULL;
UPDATE balanzas SET baudrate = 9600 WHERE baudrate IS NULL;
ALTER TABLE balanzas ALTER COLUMN formato_trama SET DEFAULT 'auto';
ALTER TABLE balanzas ALTER COLUMN baudrate SET DEFAULT 9600;
ALTER TABLE balanzas ALTER COLUMN formato_trama SET NOT NULL;
ALTER TABLE balanzas ALTER COLUMN baudrate SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_balanzas_formato_trama'
    ) THEN
        ALTER TABLE balanzas
            ADD CONSTRAINT ck_balanzas_formato_trama
            CHECK (formato_trama IN ('auto', 'json', 'ascii'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_balanzas_baudrate'
    ) THEN
        ALTER TABLE balanzas
            ADD CONSTRAINT ck_balanzas_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_balanzas_delimitador'
    ) THEN
        ALTER TABLE balanzas
            ADD CONSTRAINT ck_balanzas_delimitador
            CHECK (delimitador IS NULL OR delimitador IN ('lf', 'cr', 'crlf', 'stx_etx'));
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS indicadores (
    id_indicador  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo        VARCHAR(20),
    descripcion   VARCHAR(150) NOT NULL,
    marca         VARCHAR(100),
    modelo        VARCHAR(100),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulado   BOOLEAN NOT NULL DEFAULT FALSE,
    protocolo     VARCHAR(20) DEFAULT 'tcp',
    puerto_com    VARCHAR(50),
    ip_address    VARCHAR(45),
    puerto_tcp    INTEGER,
    formato_trama VARCHAR(10) NOT NULL DEFAULT 'auto',
    baudrate      INTEGER NOT NULL DEFAULT 9600,
    delimitador   VARCHAR(10),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS indicadores_empresa_codigo_uk
    ON indicadores (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

-- Enlace opcional báscula → indicador (migración 028).
ALTER TABLE balanzas
    ADD COLUMN IF NOT EXISTS id_indicador UUID REFERENCES indicadores(id_indicador);
CREATE INDEX IF NOT EXISTS balanzas_id_indicador_idx
    ON balanzas (id_indicador);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_indicadores_formato_trama'
    ) THEN
        ALTER TABLE indicadores
            ADD CONSTRAINT ck_indicadores_formato_trama
            CHECK (formato_trama IN ('auto', 'json', 'ascii'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_indicadores_baudrate'
    ) THEN
        ALTER TABLE indicadores
            ADD CONSTRAINT ck_indicadores_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_indicadores_delimitador'
    ) THEN
        ALTER TABLE indicadores
            ADD CONSTRAINT ck_indicadores_delimitador
            CHECK (delimitador IS NULL OR delimitador IN ('lf', 'cr', 'crlf', 'stx_etx'));
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS conceptos_inventario (
    id_concepto     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo          VARCHAR(20),
    nombre          VARCHAR(150) NOT NULL,
    descripcion     VARCHAR(255),
    tipo_movimiento VARCHAR(10),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS conceptos_inventario_empresa_codigo_uk
    ON conceptos_inventario (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

-- Enlace opcional kardex → concepto (migración 029): la columna se declara en
-- el CREATE TABLE de kardex; el índice va tras su creación.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_conceptos_inventario_tipo'
    ) THEN
        ALTER TABLE conceptos_inventario
            ADD CONSTRAINT ck_conceptos_inventario_tipo
            CHECK (tipo_movimiento IS NULL OR tipo_movimiento IN ('ingreso', 'despacho', 'ajuste', 'ambos'));
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS semaforos (
    id_semaforo       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo            VARCHAR(20),
    descripcion       VARCHAR(150) NOT NULL,
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulado       BOOLEAN NOT NULL DEFAULT FALSE,
    protocolo         VARCHAR(20) NOT NULL DEFAULT 'http',
    ip_address        VARCHAR(45),
    puerto_tcp        INTEGER,
    puerto_com        VARCHAR(50),
    baudrate          INTEGER NOT NULL DEFAULT 9600,
    id_balanza        UUID REFERENCES balanzas(id_balanza),
    control_automatico BOOLEAN NOT NULL DEFAULT FALSE,
    umbral_cero_kg    NUMERIC(10,2) NOT NULL DEFAULT 5.0,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS semaforos_empresa_codigo_uk
    ON semaforos (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_semaforos_protocolo'
    ) THEN
        ALTER TABLE semaforos
            ADD CONSTRAINT ck_semaforos_protocolo
            CHECK (protocolo IN ('http', 'serial'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_semaforos_baudrate'
    ) THEN
        ALTER TABLE semaforos
            ADD CONSTRAINT ck_semaforos_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
END
$$;

-- Cámaras de captura de placa (migración 027 + 030). origen 'ip' descarga el
-- snapshot HTTP/JPEG de url_snapshot; origen 'local' captura el frame de
-- `dispositivo` (USB/integrada). ubicacion declara si la cámara sirve en la
-- entrada, la salida o ambas.
CREATE TABLE IF NOT EXISTS camaras (
    id_camara     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo        VARCHAR(20),
    descripcion   VARCHAR(150) NOT NULL,
    marca         VARCHAR(100),
    modelo        VARCHAR(100),
    fabricante    VARCHAR(100),
    activo        BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulada   BOOLEAN NOT NULL DEFAULT FALSE,
    origen        VARCHAR(10) NOT NULL DEFAULT 'ip',
    url_snapshot  VARCHAR(500) NOT NULL DEFAULT '',
    dispositivo   VARCHAR(255),
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
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_camaras_origen'
    ) THEN
        ALTER TABLE camaras
            ADD CONSTRAINT ck_camaras_origen
            CHECK (origen IN ('ip', 'local'));
    END IF;
END
$$;

-- Barreras de tránsito (migración 032): actuador de control de acceso (abrir/cerrar).
CREATE TABLE IF NOT EXISTS barreras (
    id_barrera             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa             UUID NOT NULL REFERENCES empresas(id_empresa),
    codigo                 VARCHAR(20),
    descripcion            VARCHAR(150) NOT NULL,
    activo                 BOOLEAN NOT NULL DEFAULT TRUE,
    is_simulado            BOOLEAN NOT NULL DEFAULT FALSE,
    protocolo              VARCHAR(20) NOT NULL DEFAULT 'http',
    ip_address             VARCHAR(45),
    puerto_tcp             INTEGER,
    puerto_com             VARCHAR(50),
    baudrate               INTEGER NOT NULL DEFAULT 9600,
    ubicacion              VARCHAR(10) NOT NULL DEFAULT 'ambos',
    control_automatico     BOOLEAN NOT NULL DEFAULT FALSE,
    tiempo_espera_segundos INTEGER NOT NULL DEFAULT 5,
    comando_abrir          VARCHAR(255),
    comando_cerrar         VARCHAR(255),
    created_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS barreras_empresa_codigo_uk
    ON barreras (id_empresa, codigo)
    WHERE codigo IS NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_barreras_protocolo'
    ) THEN
        ALTER TABLE barreras
            ADD CONSTRAINT ck_barreras_protocolo
            CHECK (protocolo IN ('http', 'serial'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_barreras_ubicacion'
    ) THEN
        ALTER TABLE barreras
            ADD CONSTRAINT ck_barreras_ubicacion
            CHECK (ubicacion IN ('entrada', 'salida', 'ambos'));
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'ck_barreras_baudrate'
    ) THEN
        ALTER TABLE barreras
            ADD CONSTRAINT ck_barreras_baudrate
            CHECK (baudrate IN (1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200));
    END IF;
END
$$;

-- ============================================================
-- 7. TRANSACCIONAL - BOLETOS DE PESAJE
-- ============================================================
CREATE TABLE IF NOT EXISTS boletos_pesaje (
    boleto                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    numero_boleto            VARCHAR(30) UNIQUE,
    id_empresa               UUID NOT NULL REFERENCES empresas(id_empresa),
    id_vehiculo              VARCHAR(20),
    remolque                 BOOLEAN NOT NULL DEFAULT FALSE,
    id_remolque              UUID REFERENCES remolques(id_remolque),
    id_transporte            UUID REFERENCES transportes(id_transporte),
    id_conductor             VARCHAR(20) REFERENCES conductores(cedula_dni),
    id_producto              UUID REFERENCES productos(id_producto),
    id_almacen               UUID REFERENCES almacenes(id_almacen),
    id_balanza               UUID REFERENCES balanzas(id_balanza),
    tipo_tercero             VARCHAR(30),
    id_tercero               UUID REFERENCES terceros(id_tercero),
    multi_despacho_recepcion BOOLEAN NOT NULL DEFAULT FALSE,

    fecha_hora_entrada       TIMESTAMP NOT NULL,
    peso_entrada_vehiculo    NUMERIC(12,2) NOT NULL CHECK (peso_entrada_vehiculo >= 0),
    peso_entrada_remolque    NUMERIC(12,2),
    foto_entrada_url         TEXT,

    fecha_hora_salida        TIMESTAMP,
    peso_salida_vehiculo     NUMERIC(12,2),
    peso_salida_remolque     NUMERIC(12,2),
    foto_salida_url          TEXT,

    -- Fotos de placa (migración 027): TRUE cuando ya se pidieron una vez.
    fotos_placa_tomadas      BOOLEAN NOT NULL DEFAULT FALSE,

    documento                VARCHAR(100),
    guia_sunagro             VARCHAR(100),
    medida                   VARCHAR(50),
    flete                    VARCHAR(100),
    costo_flete              NUMERIC(12,2),
    observaciones            TEXT,

    -- Auditoría de operativas
    creado_por               VARCHAR(150),
    salida_por               VARCHAR(150),
    modificado_por           VARCHAR(150),
    anulado_por              VARCHAR(150),
    motivo_anulacion         TEXT,
    -- Ediciones
    ediciones_count          INTEGER NOT NULL DEFAULT 0,
    motivo_modificacion_ultima VARCHAR(500),
    ultimo_editor_nombre     VARCHAR(150),
    max_ediciones_boleto_aplicado INTEGER,

    -- Cálculos MODEL.md
    peso_total_entrada       NUMERIC(12,2),
    peso_total_salida        NUMERIC(12,2),
    peso_neto                NUMERIC(12,2),
    peso_neto_declarado      NUMERIC(12,2),
    peso_diferencia          NUMERIC(12,2),
    porcentaje_desviacion    NUMERIC(8,4),

    -- Campos legacy
    peso_bruto               NUMERIC(12,2),
    peso_tara                NUMERIC(12,2),
    diferencia_peso          NUMERIC(12,2),
    porcentaje_diferencia    NUMERIC(8,4),
    densidad                 NUMERIC(8,4),
    litros                   NUMERIC(12,2),
    unidades                 NUMERIC(12,2),

    estado_boleto            VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
    es_peso_manual           BOOLEAN NOT NULL DEFAULT FALSE,
    sincronizado             BOOLEAN NOT NULL DEFAULT FALSE,
    sync_intentos            INTEGER NOT NULL DEFAULT 0,
    created_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at               TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS imagenes_pesaje (
    id_imagen     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    boleto        UUID NOT NULL REFERENCES boletos_pesaje(boleto) ON DELETE CASCADE,
    tipo          VARCHAR(30) NOT NULL,
    url           TEXT NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 8. KARDEX
-- ============================================================
CREATE TABLE IF NOT EXISTS kardex (
    id_kardex       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa),
    id_movimiento   INTEGER NOT NULL,
    fecha_kardex    TIMESTAMP NOT NULL,
    id_producto     UUID REFERENCES productos(id_producto),
    id_almacen      UUID REFERENCES almacenes(id_almacen),
    fecha_documento TIMESTAMP,
    documento       VARCHAR(100),
    id_concepto     UUID REFERENCES conceptos_inventario(id_concepto),
    valor           NUMERIC(12,2) NOT NULL,
    boleto          UUID REFERENCES boletos_pesaje(boleto),
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_kardex_empresa_fecha ON kardex (id_empresa, fecha_kardex);
CREATE INDEX IF NOT EXISTS idx_kardex_producto_almacen ON kardex (id_producto, id_almacen);
CREATE INDEX IF NOT EXISTS kardex_id_concepto_idx ON kardex (id_concepto);

-- ============================================================
-- 9. SINCRONIZACIÓN LOCAL (cola que se envía al servidor)
-- ============================================================
CREATE TABLE IF NOT EXISTS sync_queue (
    id_sync       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    entidad       VARCHAR(50) NOT NULL,
    operacion     VARCHAR(20) NOT NULL,
    entidad_id    VARCHAR(100) NOT NULL,
    payload       JSONB NOT NULL,
    pendiente     BOOLEAN NOT NULL DEFAULT TRUE,
    intentos      INTEGER NOT NULL DEFAULT 0,
    error         TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sync_logs (
    id_log        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa    UUID,
    tipo          VARCHAR(30) NOT NULL,
    entidad       VARCHAR(50),
    registros     INTEGER NOT NULL DEFAULT 0,
    errores       INTEGER NOT NULL DEFAULT 0,
    detalle       TEXT,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 10. AUDITORÍA LOCAL
-- ============================================================
CREATE TABLE IF NOT EXISTS auditoria (
    id_auditoria  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_usuario    UUID REFERENCES usuarios(id_usuario),
    id_empresa    UUID,
    accion        VARCHAR(100) NOT NULL,
    entidad       VARCHAR(50),
    entidad_id    VARCHAR(100),
    detalle       JSONB,
    ip            VARCHAR(50),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS logs_sistema (
    id_log        BIGSERIAL PRIMARY KEY,
    nivel         VARCHAR(10) NOT NULL,
    modulo        VARCHAR(50),
    mensaje       TEXT NOT NULL,
    detalle       JSONB,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 11. CONFIGURACIÓN LOCAL
-- ============================================================
CREATE TABLE IF NOT EXISTS configuraciones (
    clave         VARCHAR(100) PRIMARY KEY,
    valor         TEXT,
    descripcion   TEXT,
    id_empresa    UUID REFERENCES empresas(id_empresa),
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS parametros_sistema (
    parametro     VARCHAR(100) PRIMARY KEY,
    valor         TEXT,
    grupo         VARCHAR(50),
    descripcion   TEXT,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- 12. SEGURIDAD Y ACCESOS (matriz rol × módulo)
-- ============================================================
CREATE TABLE IF NOT EXISTS permisos_acceso (
    id_empresa    UUID NOT NULL REFERENCES empresas(id_empresa),
    rol           VARCHAR(30) NOT NULL,
    modulo        VARCHAR(50) NOT NULL,
    acceso        VARCHAR(20) NOT NULL DEFAULT 'ver',
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id_empresa, rol, modulo)
);

-- ============================================================
-- 13. NOTIFICACIONES Y RECORDATORIOS (centro de avisos)
-- El programador del backend (app/core/notification_scheduler.py)
-- evalúa eventos y recordatorios vencidos y crea filas en
-- `notificaciones`; además dibuja el aviso nativo del SO.
-- `dedup_key` es única por empresa: da idempotencia al programador.
-- ============================================================
CREATE TABLE IF NOT EXISTS recordatorios (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa) ON DELETE CASCADE,
    id_usuario        UUID REFERENCES usuarios(id_usuario),
    titulo            VARCHAR(200) NOT NULL,
    mensaje           TEXT,
    programada_para   TIMESTAMP NOT NULL,
    recurrencia       VARCHAR(20) NOT NULL DEFAULT 'none',
    activo            BOOLEAN NOT NULL DEFAULT TRUE,
    ultima_ejecucion  TIMESTAMP,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS notificaciones (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_empresa        UUID NOT NULL REFERENCES empresas(id_empresa) ON DELETE CASCADE,
    tipo              VARCHAR(40) NOT NULL,
    severidad         VARCHAR(10) NOT NULL DEFAULT 'info',
    titulo            VARCHAR(200) NOT NULL,
    mensaje           TEXT,
    acciones          JSON,
    estado            VARCHAR(20) NOT NULL DEFAULT 'no_leida',
    origen            VARCHAR(20) NOT NULL DEFAULT 'evento',
    id_recordatorio   UUID REFERENCES recordatorios(id) ON DELETE SET NULL,
    id_referencia     UUID,
    dedup_key         VARCHAR(150),
    programada_para   TIMESTAMP,
    entregada_os_en   TIMESTAMP,
    leida_en          TIMESTAMP,
    expira_en         TIMESTAMP,
    created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_notificaciones_empresa_dedup UNIQUE (id_empresa, dedup_key)
);

-- ============================================================
-- ÍNDICES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_fechas    ON boletos_pesaje (fecha_hora_entrada, fecha_hora_salida);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_vehiculo  ON boletos_pesaje (id_vehiculo);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_conductor ON boletos_pesaje (id_conductor);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_producto  ON boletos_pesaje (id_producto);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_estado    ON boletos_pesaje (estado_boleto);
CREATE INDEX IF NOT EXISTS idx_boletos_pesaje_sync      ON boletos_pesaje (sincronizado);
CREATE INDEX IF NOT EXISTS idx_camiones_empresa         ON camiones (id_empresa);
CREATE INDEX IF NOT EXISTS idx_camiones_placa           ON camiones (placa);
CREATE INDEX IF NOT EXISTS idx_modelos_marca            ON modelos_camion (marca_id);
CREATE INDEX IF NOT EXISTS idx_productos_empresa        ON productos (id_empresa);
CREATE INDEX IF NOT EXISTS idx_almacenes_empresa        ON almacenes (id_empresa);
CREATE INDEX IF NOT EXISTS idx_sync_queue_pend          ON sync_queue (pendiente, intentos);
CREATE INDEX IF NOT EXISTS idx_auditoria_usuario        ON auditoria (id_usuario);
CREATE INDEX IF NOT EXISTS idx_auditoria_fecha          ON auditoria (created_at);
CREATE INDEX IF NOT EXISTS idx_notificaciones_empresa_estado  ON notificaciones (id_empresa, estado);
CREATE INDEX IF NOT EXISTS idx_notificaciones_empresa_created ON notificaciones (id_empresa, created_at);
CREATE INDEX IF NOT EXISTS idx_recordatorios_empresa    ON recordatorios (id_empresa, activo, programada_para);


-- ============================================================
-- 14. LLAVES DE ACTIVACIÓN (estaciones OPERADOR / cliente delgado)
-- El ADMIN emite una llave por usuario; el instalador de la estación
-- cliente la canjea UNA sola vez contra la API del titular. El código se
-- guarda hasheado (SHA-256); en claro solo se muestra al emitirlo.
-- ============================================================
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

CREATE INDEX IF NOT EXISTS idx_llaves_empresa_usuario ON llaves_activacion (id_empresa, id_usuario);
CREATE INDEX IF NOT EXISTS idx_llaves_estado          ON llaves_activacion (estado);
CREATE UNIQUE INDEX IF NOT EXISTS uq_llaves_codigo_hash ON llaves_activacion (codigo_hash);


-- ============================================================
-- 12. HISTORIAL DE EDICIONES DE BOLETOS
-- ============================================================
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
        estado_anterior IN ('PENDIENTE','CERRADO','MODIFICADO') AND
        estado_nuevo    IN ('PENDIENTE','CERRADO','MODIFICADO')
    ),
    CONSTRAINT ck_boletos_ediciones_edicion_num CHECK (edicion_numero >= 1),
    CONSTRAINT ck_boletos_ediciones_justificacion CHECK (char_length(trim(justificacion)) >= 10)
);

CREATE INDEX IF NOT EXISTS ix_boletos_ediciones_boleto_fecha
    ON boletos_ediciones (id_empresa, boleto, fecha_edicion);
CREATE INDEX IF NOT EXISTS ix_boletos_ediciones_boleto_num
    ON boletos_ediciones (id_empresa, boleto, edicion_numero);
CREATE INDEX IF NOT EXISTS ix_boletos_ediciones_usuario_fecha
    ON boletos_ediciones (id_usuario, fecha_edicion);
CREATE UNIQUE INDEX IF NOT EXISTS ux_boletos_ediciones_sync_op
    ON boletos_ediciones (sync_operation_id)
    WHERE sync_operation_id IS NOT NULL;

-- Migración 031: Catálogo de conceptos para Kardex (IDs 0-99)
CREATE TABLE IF NOT EXISTS conceptos_kardex (
  id_concepto     INTEGER NOT NULL,
  id_empresa      UUID NOT NULL REFERENCES empresas(id_empresa) ON DELETE RESTRICT,
  nombre          VARCHAR(100) NOT NULL,
  descripcion     TEXT,
  signo           VARCHAR(8) NOT NULL,
  es_sistema      BOOLEAN NOT NULL DEFAULT FALSE,
  activo          BOOLEAN NOT NULL DEFAULT TRUE,
  aplica_a        VARCHAR(20) NOT NULL DEFAULT 'AMBOS',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id_empresa, id_concepto),
  CONSTRAINT chk_ck_rango CHECK (id_concepto BETWEEN 0 AND 99),
  CONSTRAINT chk_ck_signo CHECK (signo IN ('inicial','positivo','negativo')),
  CONSTRAINT chk_ck_aplica_a CHECK (aplica_a IN ('INGRESO','DESPACHO','AJUSTE','AMBOS')),
  CONSTRAINT chk_ck_coherencia CHECK (
    (id_concepto = 0               AND signo = 'inicial')  OR
    (id_concepto BETWEEN 1  AND 49 AND signo = 'positivo') OR
    (id_concepto BETWEEN 50 AND 99 AND signo = 'negativo')
  )
);

CREATE INDEX IF NOT EXISTS idx_conceptos_kardex_empresa ON conceptos_kardex(id_empresa);
CREATE INDEX IF NOT EXISTS idx_conceptos_kardex_signo ON conceptos_kardex(signo);

-- Seed de conceptos del sistema por empresa
INSERT INTO conceptos_kardex (id_concepto, id_empresa, nombre, descripcion, signo, es_sistema, activo, aplica_a)
SELECT 0,  e.id_empresa, 'Saldo inicial',         'Saldo inicial del inventario', 'inicial',  TRUE, TRUE, 'AMBOS'
FROM empresas e
WHERE NOT EXISTS (SELECT 1 FROM conceptos_kardex ck WHERE ck.id_empresa = e.id_empresa AND ck.id_concepto = 0)
ON CONFLICT DO NOTHING;

INSERT INTO conceptos_kardex (id_concepto, id_empresa, nombre, descripcion, signo, es_sistema, activo, aplica_a)
SELECT 10, e.id_empresa, 'Ingreso por báscula',   'Ingreso generado por boleto de pesaje', 'positivo', TRUE, TRUE, 'INGRESO'
FROM empresas e
WHERE NOT EXISTS (SELECT 1 FROM conceptos_kardex ck WHERE ck.id_empresa = e.id_empresa AND ck.id_concepto = 10)
ON CONFLICT DO NOTHING;

INSERT INTO conceptos_kardex (id_concepto, id_empresa, nombre, descripcion, signo, es_sistema, activo, aplica_a)
SELECT 60, e.id_empresa, 'Despacho por báscula',  'Despacho generado por boleto de pesaje', 'negativo', TRUE, TRUE, 'DESPACHO'
FROM empresas e
WHERE NOT EXISTS (SELECT 1 FROM conceptos_kardex ck WHERE ck.id_empresa = e.id_empresa AND ck.id_concepto = 60)
ON CONFLICT DO NOTHING;

COMMIT;

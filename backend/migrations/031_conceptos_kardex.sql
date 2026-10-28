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

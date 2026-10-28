-- Migración 031 para SQL Server
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'conceptos_kardex')
BEGIN
    CREATE TABLE conceptos_kardex (
      id_concepto     INT NOT NULL,
      id_empresa      UNIQUEIDENTIFIER NOT NULL,
      nombre          NVARCHAR(100) NOT NULL,
      descripcion     NVARCHAR(MAX),
      signo           NVARCHAR(8) NOT NULL,
      es_sistema      BIT NOT NULL DEFAULT 0,
      activo          BIT NOT NULL DEFAULT 1,
      aplica_a        NVARCHAR(20) NOT NULL DEFAULT 'AMBOS',
      created_at      DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
      updated_at      DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
      CONSTRAINT pk_conceptos_kardex PRIMARY KEY (id_empresa, id_concepto),
      CONSTRAINT fk_conceptos_kardex_empresa FOREIGN KEY (id_empresa) REFERENCES empresas(id_empresa),
      CONSTRAINT chk_ck_rango CHECK (id_concepto BETWEEN 0 AND 99),
      CONSTRAINT chk_ck_signo CHECK (signo IN ('inicial','positivo','negativo')),
      CONSTRAINT chk_ck_aplica_a CHECK (aplica_a IN ('INGRESO','DESPACHO','AJUSTE','AMBOS')),
      CONSTRAINT chk_ck_coherencia CHECK (
        (id_concepto = 0               AND signo = 'inicial')  OR
        (id_concepto BETWEEN 1  AND 49 AND signo = 'positivo') OR
        (id_concepto BETWEEN 50 AND 99 AND signo = 'negativo')
      )
    );
    CREATE INDEX idx_conceptos_kardex_empresa ON conceptos_kardex(id_empresa);
    CREATE INDEX idx_conceptos_kardex_signo ON conceptos_kardex(signo);
END;

IF NOT EXISTS (SELECT 1 FROM conceptos_kardex WHERE id_concepto = 0)
BEGIN
  INSERT INTO conceptos_kardex (id_concepto, id_empresa, nombre, descripcion, signo, es_sistema, activo, aplica_a)
  SELECT 0, id_empresa, N'Saldo inicial', N'Saldo inicial del inventario', N'inicial', 1, 1, N'AMBOS' FROM empresas;
END;
IF NOT EXISTS (SELECT 1 FROM conceptos_kardex WHERE id_concepto = 10)
BEGIN
  INSERT INTO conceptos_kardex (id_concepto, id_empresa, nombre, descripcion, signo, es_sistema, activo, aplica_a)
  SELECT 10, id_empresa, N'Ingreso por báscula', N'Ingreso generado por boleto de pesaje', N'positivo', 1, 1, N'INGRESO' FROM empresas;
END;
IF NOT EXISTS (SELECT 1 FROM conceptos_kardex WHERE id_concepto = 60)
BEGIN
  INSERT INTO conceptos_kardex (id_concepto, id_empresa, nombre, descripcion, signo, es_sistema, activo, aplica_a)
  SELECT 60, id_empresa, N'Despacho por báscula', N'Despacho generado por boleto de pesaje', N'negativo', 1, 1, N'DESPACHO' FROM empresas;
END;

IF NOT EXISTS (SELECT 1 FROM configuraciones WHERE clave = N'peso_manual_permitido')
BEGIN
    INSERT INTO configuraciones (clave, valor, metadatos)
    VALUES (
        N'peso_manual_permitido',
        N'true',
        N'{"descripcion": "Permitir peso manual cuando no hay báscula conectada", "tipo": "bool"}'
    );
END;
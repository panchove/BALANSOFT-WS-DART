# Diseño de Software — Series y Numeración BALANSOFT-WS

**Versión:** 0.4.2-dev.56  
**Fecha:** 2026-10-19  
**Norma:** ISO/IEC 1016  
**Fuente:** Spec 002-series-numeracion / SRS BALANSOFT-WS  
**Autor:** Lead Architect  

## 1. Descomposición de Arquitectura

### 1.1 Lógica de Obtención de Número de Boleto

La obtención del siguiente número de boleto debe realizarse dentro de una transacción con bloqueo pesimista para garantizar sequentialidad y evitar condiciones de carrera.

#### Flujo en `WeighingService.create()`:

1. **Iniciar transacción**: `BEGIN` en PostgreSQL
2. **SELECT ... FOR UPDATE** en `series_numeracion` donde `id_empresa = :empresa` y `activa = TRUE`
3. **Incrementar** `siguiente`: `siguiente = siguiente + 1`
4. **Formatear número**: `f"{prefijo}-{siguiente:0{digitos}d}"` (ej: `TA-00000001`)
5. **UPDATE** `series_numeration` con nuevo valor de `siguiente`
6. **Commit** transacción

#### Representación SQL:

```sql
BEGIN;

-- Bloqueo pesimista de la fila de la serie
SELECT * FROM series_numeracion 
WHERE id_empresa = 'empresa-uuid' 
  AND activa = TRUE 
FOR UPDATE;

-- Actualizar siguiente número
UPDATE series_numeracion 
SET siguiente = siguiente + 1, 
    fecha_ultima_emision = NOW()
WHERE id_empresa = 'empresa-uuid';

-- Calcular número formateado
-- Ejemplo: prefijo='TA', digitos=8, siguiente=1 → 'TA-00000001'
-- SELECT concat(prefijo, '-', LPAD(siguiente::text, digitos, '0'))

COMMIT;
```

### 1.2 Restricción contra Borrado de Serie

Para evitar el borrado accidental de series con boletos asociados, se implementa una de estas opciones:

#### Opción A: Restricción en Base de Datos (Recomendada)

```sql
-- En la migración de creación de series_numeracion
ALTER TABLE series_numeracion
ADD CONSTRAINT no_borrar_con_boletos 
FOREIGN KEY (id) REFERENCES some_reference(id) 
ON DELETE RESTRICT;
```

O más realista, validación en la API antes del DELETE:

```sql
-- Verificar boletos asociados antes de borrar
SELECT COUNT(*) FROM boletos_pesaje 
WHERE id_serie = :serie_id AND estado_boleto != 'ANULADO';
```

Si `COUNT(*) > 0`: retornar 409 Conflict.

#### Opción B: Validación en API `PUT /series/{id}`

```python
@router.put("/series/{serie_id}")
def actualizar_serie(serie_id: UUID, db: AsyncSession = Depends(get_db)):
    # Verificar boletos asociados (no anulados)
    count = await db.execute(
        select(func.count()).select_from(BoletoPesaje)
        .where(BoletoPesaje.id_serie == serie_id)
        .where(BoletoPesaje.estado_boleto != 'ANULADO')
    )
    if count.scalar() > 0:
        raise HTTPException(
            status_code=409,
            detail="No se puede borrar serie con boletos asociados. "
                   "Anule o transfiera los boletos primero."
        )
    # Proceed with update
    ...
```

### 1.3 Formato de Número de Boleto

- **Estructura**: `PREFIX-NNNNNNNN` (ej: `TA-00000001`)
- **Predefinido en**: `series_numeracion` tabla (`prefijo`, `digitos`)
- **Ejemplos**:
  - `TA-00000001` (Transportes ABC, primera emisión)
  - `CL-00000100` (Clientes XYZ, emisión 100)
  - `MR-00000050` (Materiales, emisión 50)

### 1.4 Identificación por Empresa

Cada serie está asociada a exactamente una empresa (`id_empresa`):

- `series_numeracion.id_empresa FK → empresas.id_empresa PK`
- Una empresa puede tener múltiples series activas (diferentes prefijos)
- El `id_empresa` se filtra en TODA operación sobre series_numeracion
- El número de secuencia `siguiente` avanza de forma independiente por empresa

## 2. Diseño de Datos (Schema)

### 2.1 Tabla `series_numeracion` (PostgreSQL)

| Columna                | Tipo         | Restricciones                  | Descripción                                            |
|------------------------|--------------|--------------------------------|--------------------------------------------------------|
| `id_serie`             | UUID PK      | `DEFAULT gen_random_uuid()`    | Identificador único de la serie                        |
| `id_empresa`           | UUID FK      | NOT NULL, `ON DELETE RESTRICT` | Empresa dueña de la serie                              |
| `nombre`               | VARCHAR(100) | NOT NULL                       | Nombre descriptivo (ej: "Transportes ABC")             |
| `prefijo`              | VARCHAR(10)  | NOT NULL, único por empresa    | Prefijo del número de boleto (ej: "TA", "CL")          |
| `digitos`              | SMALLINT     | NOT NULL, ≥ 1                  | Cantidad de dígitos numéricos (ej: 8 para TA-00000001) |
| `siguiente`            | INTEGER      | NOT NULL, > 0                  | Siguiente número a asignar                             |
| `activa`               | BOOLEAN      | NOT NULL, DEFAULT TRUE         | Si la serie está activa o dada de baja                 |
| `fecha_creacion`       | TIMESTAMPTZ  | NOT NULL, DEFAULT NOW()        | Cuándo fue creada la serie                             |
| `fecha_ultima_emision` | TIMESTAMPTZ  |                                | Cuándo fue la última emisión                           |

### 2.2 Índices y Constraints

```sql
-- Índice compuesto por empresa para búsqueda rápida
CREATE INDEX idx_series_empresa ON series_numeracion(id_empresa);

-- Restricción: el prefijo debe ser único por empresa (no dos series iguales)
CREATE UNIQUE INDEX uq_series_empresa_prefijo 
ON series_numeracion(id_empresa, prefijo);

-- Restricción: siguiente siempre debe ser > 0
CHECK (siguiente > 0);
```

### 2.2 Restricciones de Negocio

| Restricción                             | Descripción                                      | Implementación                                         |
|-----------------------------------------|--------------------------------------------------|--------------------------------------------------------|
| **Siempre secuencial**                  | `siguiente` avanza 1 unidad por emisión          | `SELECT ... FOR UPDATE` en transacción                 |
| **Nunca reutilizar**                    | Un número emitido nunca se reasigna              | Aplicación lógica; borrar boleto no libera el número   |
| **No borrar con boletos**               | No se permite DELETE serie con boletos asociados | Validación en API; código 409 Conflict                 |
| **Una serie por empresa (por prefijo)** | `(id_empresa, prefijo)` es único                 | `UNIQUE INDEX` en BD                                   |
| **Serie activa vs inactiva**            | `activa = TRUE` para nuevas emisiones            | Fila en BD; `activa = FALSE` para series dadas de baja |

## 3. Interfaces de API

### 3.1 Endpoint: `POST /api/v1/weighing/create`

Este endpoint es el responsable de asignar el número de boleto:

1. Recibir datos del boleto entrada (placa, id_empresa, etc.)
2. **Llamada interna**: `assign_boleto_number(id_empresa)`:
   - `BEGIN`
   - `SELECT * FROM series_numeracion WHERE id_empresa = :empresa FOR UPDATE`
   - `UPDATE series_numeracion SET siguiente = siguiente + 1 WHERE id_empresa = :empresa`
   - `COMMIT`
   - Retornar número formateado: `f"{prefijo}-{siguiente:0{digitos}d}"`
3. Continuar con creación del boleto PENDIENTE con el número asignado

### 3.2 Endpoint: `DELETE /api/v1/series/{serie_id}` (ADMIN)

Validaciones previas:

1. Verificar que `serie_id` exista
2. **Contar boletos asociados** (no anulados):
   ```sql
   SELECT COUNT(*) FROM boletos_pesaje WHERE id_serie = :serie_id AND estado_boleto != 'ANULADO'
   ```
3. Si `COUNT(*) > 0`: retornar 409 Conflict con mensaje
4. Si `COUNT(*) = 0`: proceder con DELETE

### 3.3 Endpoint: `PUT /api/v1/series/{serie_id}` (ADMIN - Opcional)

Para reactivar una serie dada de baja o cambiar su configuración:

1. Verificar que la serie exista y pertenezca a la empresa del usuario
2. Si `activa = FALSE`: permitir reactivar (`activa = TRUE`)
3. Si des cambiar `prefijo` o `digitos`: validar que no entren en conflicto con series existentes

## 3. Restricciones y Limitaciones

### 3.1 Restricciones Técnicas

| Restricción                | Valor/Límite                                                   | Justificación                                              |
|----------------------------|----------------------------------------------------------------|------------------------------------------------------------|
| **Capacidad de secuencia** | Depende de `digitos`: 8 dígitos → 99,999,999 emisiones máximas | Diseño inicial; fácilmente extensible aumentando `digitos` |
| **Concurrencia**           | `SELECT ... FOR UPDATE` bloquea fila hasta commit              | Evita condiciones de carrera en múltiples operadores       |
| **Atomicidad**             | Transacción completa (BEGIN/COMMIT)                            | Garantiza consistencia ni falla parcialmente               |
| **Empresa aislada**        | `id_empresa` filtra toda operación                             | Multi-tenancy obligatorio (constitution.md §4)             |

### 3.2 Restricciones de Negocio

| Restricción                       | Descripción                                                                                   |
|-----------------------------------|-----------------------------------------------------------------------------------------------|
| **Nunca reutilizar números**      | Un número de boleto emitido (aún si el boleto fue anulado) nunca se reasigna a otro boleto    |
| **Serie con boletos = 409**       | `DELETE series_numeration` con boletos asociados (no anulados) retorna código 409             |
| **Mensaje obligatorio**           | API debe retornar mensaje explicativo: "No se puede borrar serie con boletos asociados..."    |
| **Transferencia antes de borrar** | Flujo recomendado: anular o transferir boletos a otra serie antes de intentar borrar la serie |

## 4. Rastreabilidad de Requisitos (ISO/IEC 1016)

| Requisito      | Diseño Implementado                                                            | Sección                           |
|----------------|--------------------------------------------------------------------------------|-----------------------------------|
| **FR-SDD-006** | `SELECT ... FOR UPDATE` en `series_numeracion` dentro de transacción           | §1.1 (flujo obtención número)     |
| **FR-SDD-007** | Validación en API `DELETE /series/{id}`; código 409 si boletos asociados       | §1.2 (restricción borrado)        |
| **PF-001**     | `SELECT ... FOR UPDATE` dentro transacción atómica; sin condiciones de carrera | §4 (restricciones técnicas)       |
| **SE-001**     | `id_empresa` filtra toda operación en `series_numeracion`                      | §1.4 (identificación por empresa) |
| **RE-001**     | Transacción atómica que no deja BD inconsistente ante cortes                   | §1.1 (paso 1-6: BEGIN/COMMIT)     |

## 5. Interfaces con Otras Capas

### 4.1 Entrada desde Capa de Negocio (WeighingService)

- **Llamada**: `assign_boleto_number(id_empresa)` dentro de `WeighingService.create()`
- **Retorno**: Tupla `(numero_boleto, id_serie)` ej: `("TA-00000001", series_id_uuids)`
- **Transacción**: Debe forms parte de la transacción completa de creación de boleto

### 4.2 Salida a Capa de Persistencia (PostgreSQL)

- **Tabla**: `series_numeracion`
- **Operaciones críticas**: `SELECT ... FOR UPDATE`, `UPDATE siguiente`, `INSERT/DELETE` (con validaciones)
- **Filtro obligatorio**: `id_empresa` en toda query sobre series_numeracion

### 4.3 Validación en Endpoint API

- **DELETE /series/{id}**: Verificación de boletos asociados antes de permitir borrado
- **PUT /series/{id}**: Validaciones según tipo de cambio (reactivar, cambiar prefijo/dígitos)
- **Respuesta 409**: Siempre acompañada de mensaje en español explicativo

## 5. Suposiciones y Restricciones

### 5.1 Suposiciones

- PostgreSQL 15+ como motor de BD (motor decide por prefijo de DATABASE_URL)
- SQLAlchemy 2.0 async (asyncpg) para operaciones de BD
- Cada empresa tiene al menos una serie activa configurada
- El hardware de báscula no interviene en la numeración (es gestión administrativa)

### 5.2 Restricciones

- **Sin reutilización**: Un número de boleto emitido nunca se reasigna, ni siquiera si el boleto fue anulado
- **Bloqueo pesimista obligatorio**: `SELECT ... FOR UPDATE` es indispensable; no se permite `SELECT simple` sin bloqueo para asignación de números
- **Idioma del mensaje**: Los mensajes de error 409 deben estar en español por defecto (i18n compatible)
- **.id_empresa obligatorio**: Debe filtrarse en toda operación sobre series_numeracion
- **Migraciones hand-made**: Cambios a `series_numeracion` van como migraciones SQL (001-025), idempotentes, sin Alembic
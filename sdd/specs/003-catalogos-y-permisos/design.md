# Diseño de Software — Catálogos y Permisos BALANSOFT-WS

**Versión:** 0.4.2-dev.56  
**Fecha:** 2026-10-19  
**Norma:** ISO/IEC 1016  
**Fuente:** Spec 003-catalogos-y-permisos / SRS BALANSOFT-WS  
**Autor:** Lead Architect  

## 1. Descomposición de Arquitectura

### 1.1 Capa de Servicios de Catálogos

| Servicio            | Responsabilidad                                                      | Endpoints Clave                   | Dependencias                                                                       |
|---------------------|----------------------------------------------------------------------|-----------------------------------|------------------------------------------------------------------------------------|
| `CatalogService`    | CRUD catálogos con filtrado `id_empresa` yvalidación unicidad código | `GET/POST/PUT/DELETE /catalogo/*` | `app/models/catalogos.py`, `app/core/db_engine.py`, `app/core/seguridad_matrix.py` |
| `PermissionService` | Validación de matriz 18×3 roles (ADMIN/OPERADOR/AUDITOR)             | `GET /api/v1/permissions/check`   | `app/core/seguridad_matrix.py`, `app/models/permisos_acceso.py`                    |

### 1.2 Modelos de Datos (SQLAlchemy 2.0 async)

#### 1.2.1 Tabla `empresas` (extendido)

| Columna            | Tipo         | Restricciones          | Descripción                                   |
|--------------------|--------------|------------------------|-----------------------------------------------|
| `id_empresa`       | UUID PK      | NOT NULL               | Identificador único de empresa                |
| `nombre_fiscal`    | VARCHAR(200) | NOT NULL               | Razón social de la empresa                    |
| `nombre_comercial` | VARCHAR(200) |                        | Nombre comercial o fantasa                    |
| `rif_nit`          | VARCHAR(20)  | UNIQUE, NOT NULL       | RIF/NIT fiscal (único a nivel global)         |
| `idioma`           | VARCHAR(5)   | DEFAULT 'es'           | Idioma de la empresa (es/en/pt)               |
| `formato_ticket`   | VARCHAR(10)  | DEFAULT 'PDF'          | Formato por defecto para tickets (PDF/TXT)    |
| `formato_reporte`  | VARCHAR(10)  | DEFAULT 'PDF'          | Formato por defecto para reportes (PDF/EXCEL) |
| `activa`           | BOOLEAN      | NOT NULL, DEFAULT TRUE | Si la empresa/estación está activa            |

#### 1.2.2 Tabla `permisos_acceso` (matriz 18×3)

| Columna      | Tipo                               | Restricciones                  | Descripción                           |
|--------------|------------------------------------|--------------------------------|---------------------------------------|
| `id_empresa` | UUID PK FK                         | NOT NULL, `ON DELETE RESTRICT` | Empresa a la que pertenece el permiso |
| `rol`        | ENUM('ADMIN','OPERADOR','AUDITOR') | NOT NULL                       | Rol del usuario                       |
| `modulo`     | ENUM de 18 módulos                 | NOT NULL                       | Módulo al que otorga acceso           |
| `acceso`     | ENUM('ver','editar','ninguno')     | NOT NULL                       | Nivel de acceso                       |

**Restricciones:**
- `(id_empresa, rol, modulo)` es ÚNICO (una persona no puede tener dos roles idénticos por módulo)
- **ADMIN forzado a `editar`**: en la tabla de configuración o validación de negocio, el rol ADMIN siempre tiene `acceso = 'editar'` para todos los módulos, no pudiendo ser cambiado a `ver` o `ninguno`

#### 1.2.3 Índices

```sql
-- Índice compuesto para unicidad de código por empresa
CREATE UNIQUE INDEX uq_codigo_empresa 
ON productos(codigo, id_empresa);

-- Igual en otras tablas catálogo que tengan campo 'codigo':
-- CREATE UNIQUE INDEX uq_marca_codigo ON marcas(codigo, id_empresa);
-- CREATE UNIQUE INDEX uq_transporte_codigo ON transportes(codigo, id_empresa);

-- Índice para búsquedas por rol y módulo
CREATE INDEX idx_permisos_empresa_rol ON permisos_acceso(id_empresa, rol);

-- Índice para búsquedas por módulo solo
CREATE INDEX idx_permisos_modulo ON permisos_acceso(modulo);
```

### 1.3 Validación de Unicidad por Compuesto (IDEA)

Para garantizar unicidad de `codigo` por empresa en catálogos:

#### 1.3.1 En Base de Datos

```sql
-- Ejemplo para tabla productos
CREATE UNIQUE INDEX uq_producto_codigo_empresa
ON productos(codigo, id_empresa);
```

Esto asegura que no existan dos productos con el mismo `codigo` dentro de la misma `empresa`.

#### 1.3.2 En Aplicación (FastAPI)

Validación adicional antes de INSERT/UPDATE:

```python
@catalog_router.post("/productos")
def crear_producto(db: AsyncSession = Depends(get_db), 
                   producto: ProductoCreate = Depends(),
                   current_user: Usuario = Depends(get_current_user)):
    # Verificar unicidad de código por empresa
    existing = await db.execute(
        select(Productos).where(
            Productos.codigo == producto.codigo,
            Productos.id_empresa == current_user.id_empresa
        )
    )
    if existing.scalar() is not None:
        raise HTTPException(
            status_code=409,
            detail=f"Ya existe un producto con código '{producto.codigo}' para esta empresa."
        )
    # Proceed with creation
    ...
```

### 1.4 Matriz de Permisos 18 Módulos × 3 Roles

Los 18 módulos definen las diferentes funcionalidades del sistema:

| Módulo ID | Nombre Módulo       | Descripción                                  |
|-----------|---------------------|----------------------------------------------|
| M1        | Pesaje              | Operaciones de entrada/salida de pesaje      |
| M2        | Catálogos           | CRUD de marcas, transportes, productos, etc. |
| M3        | Usuarios            | Gestión de usuarios de la estación           |
| M4        | Licencias           | Validación y gestión de licencias            |
| M5        | Reportes            | Reportes diarios, mensuales, exports         |
| M6        | Kardex              | Consultas de inventario y movimientos kardex |
| M7        | Sincronización      | Push/pull de datos local↔servidor            |
| M8        | Configuración       | Parámetros del sistema, preferencias         |
| M9        | Auditoría           | Logs y auditoría de operaciones              |
| M10       | Balanzas            | Configuración y gestión de básculas          |
| M11       | Transportes         | Flota y transporte management                |
| M12       | Conductores         | Registro y gestión de conductores            |
| M13       | Terceiros           | Terceros/clientes/proveedores                |
| M14       | Productos           | Catálogo completo de productos               |
| M15       | Almacenes           | Gestión de almacenes y inventario            |
| M16       | Series              | Numeración y series de boletos               |
| M17       | Perfil Empresa      | Datos de perfil corporativo                  |
| M18       | Ajustes Financieros | Ajustes de inventario, flete, costos         |

#### 1.4.1 Ejemplos de Permisos por Rol

| Módulo         | ADMIN        | OPERADOR                      | AUDITOR       |
|----------------|--------------|-------------------------------|---------------|
| M1 (Pesaje)    | ver + editar | ver + operar (entrada/salida) | ver           |
| M2 (Catálogos) | ver + editar | ver (solo lectura)            | ver           |
| M3 (Usuarios)  | ver + editar | ❌ ninguno                     | ❌ ninguno     |
| M4 (Licencias) | ver + editar | ❌ ninguno                     | ❌ ninguno     |
| M5 (Reportes)  | ver + editar | ver + básicos                 | ver           |
| M6 (Kardex)    | ver + editar | ver + básicos                 | ver           |
| M7 (Sync)      | ver + editar | ❌ ninguno                     | ❌ ninguno     |
| M8 (Config)    | ver + editar | ❌ ninguno                     | ❌ ninguno     |
| M9 (Auditoría) | ver + editar | ver                           | ver + reporte |
| M10 (Balanzas) | ver + editar | ❌ ninguno                     | ❌ ninguno     |
| M11-18         | variados     | variados                      | variados      |

**Regla crítica:** El rol ADMIN debe tener `acceso = 'editar'` en **todos** los módulos (M1 a M18) sin excepción. Esta restricción se implementa en la validación de dependencias FastAPI y no puede ser sobreescrita por configuración alguna.

### 1.5 Lógica de Dependencias FastAPI

```python
# Ejemplo de dependencia para validar permisos por módulo
def require_module_access(modulo_id: ModuleID):
    def dependency(current_user: Usuario = Depends(get_current_user)):
        # Verificar matriz de permisos
        permiso = await db.execute(
            select(PermisosAcceso).where(
                PermisosAcceso.id_empresa == current_user.id_empresa,
                PermisosAcceso.rol == current_user.rol,
                PermisosAcceso.modulo == modulo_id
            )
        )
        permiso = permiso.scalar_one_or_none()
        
        # ADMIN siempre tiene editar
        if current_user.rol == 'ADMIN':
            if permiso.acceso != 'editar':
                # ADMIN debería tener editar; si no, forzar editar
                permiso.acceso = 'editar'
                db.add(permiso)  # This is pseudo-code; real impl may differ
                await db.commit()
        
        # Verificar nivel de acceso
        if permiso.acceso == 'ninguno':
            raise HTTPException(status_code=403, detail="Sin permisos para este módulo")
        
        # permitido: 'ver' o 'editar'
        return current_user
    
    return dependency
```

## 2. Interfaces de API

### 2.1 Endpoints de Catálogos (Rol `local` y `server` con restricciones)

| Endpoint                                                                               | Método | Descripción                                               | Rol Requerido              |
|----------------------------------------------------------------------------------------|--------|-----------------------------------------------------------|----------------------------|
| `/catalogo/marcas`                                                                     | GET    | Listar marcas filtradas por `id_empresa`                  | Cualquier rol con `ver` M2 |
| `/catalogo/marcas`                                                                     | POST   | Crear nueva marca (validar unicidad `codigo` por empresa) | ADMIN M2                   |
| `/catalogo/marcas/{marca_id}`                                                          | GET    | Obtener marca por ID (con `id_empresa` filter)            | Cualquier rol con `ver` M2 |
| `/catalogo/marcas/{marca_id}`                                                          | PUT    | Actualizar marca (validar propiedad por `id_empresa`)     | ADMIN M2                   |
| `/catalogo/marcas/{marca_id}`                                                          | DELETE | Eliminar marca (solo si sin dependencias)                 | ADMIN M2                   |
| Igual para `/catalogo/transportes`, `/catalogo/productos`, `/catalogo/almacenes`, etc. |        |                                                           |                            |

### 2.2 Endpoints de Permisos

| Endpoint            | Método | Descripción                                                | Rol Requerido |
|---------------------|--------|------------------------------------------------------------|---------------|
| `/permisos/check`   | GET    | Verificar que el usuario tiene acceso al módulo solicitado | Cualquier rol |
| `/permisos/matriz`  | GET    | Obtener la matriz completa 18×3 configurada                | ADMIN         |
| `/permisos/asignar` | POST   | Asignar/modificar permiso de usuario a módulo              | ADMIN         |

### 2.3 Validación de Unicidad en Endpoints

Todos los endpoints de creación/actualización de catálogos deben validar unicidad usando el patrón:

```python
# Patrón reusable en catalog_service.py
async def validar_unicidad_codigo(db, codigo, id_empresa, modelo_excluyendo_id=None):
    query = select(modelo).where(modelo.codigo == codigo, modelo.id_empresa == id_empresa)
    if modelo_excluyendo_id:
        query = query.where(modelo.id != modelo_excluyendo_id)
    result = await db.execute(query)
    if result.scalar() is not None:
        raise HTTPException(
            status_code=409,
            detail=f"Ya existe un registro con código '{codigo}' para esta empresa."
        )
```

## 3. Políticas de Modo Offline

### 3.1 Sincronización Local ↔ Servidor

| Escenario                                    | Comportamiento                                                                                                                                  |
|----------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| **Sin internet, JWT válido y no expirado**   | Operar normally contra API local; todas las escrituras van a `sync_queue` local                                                                 |
| **Sin internet, JWT vencido**                | Login local con credenciales `usuarios.password_hash`; JWT local válido 7 días (`OFFLINE_GRACE_DAYS=7`)                                         |
| **Sin internet > 7 días después expiración** | Banner visual: "Licencia expirada. Contacte al administrador."; bloqueo de funcionalidades no críticas; modo solo lectura de boletos históricos |
| **Recuperar conexión**                       | Sincronización automática `POST /sync/push` sube pendientes; `GET /sync/pull` baja datos del servidor; consistencia por `id_empresa`            |

### 3.2 Cola de Sincronización (`sync_queue`)

- **Estructura**: `id_registro`, `tabla_afectada`, `datos_nuevos`, `datos_anteriores`, `timestamp`, `id_empresa`, `pendiente` (bool)
- **Operaciones**: INSERT, UPDATE, DELETE en catálogos, boletos, permisos, identidad_local
- **Idempotencia**: Cada entrada tiene `dedup_key` único (combinación de ID original + timestamp)
- **Resolución de conflictos**: "Último timestamp gana"; versión anterior guardada en tabla de ediciones (`boletos_ediciones`, `auditoria`)

## 4. Rastreabilidad de Requisitos (ISO/IEC 1016)

| Requisito      | Diseño Implementado                                                                      | Sección                                               |
|----------------|------------------------------------------------------------------------------------------|-------------------------------------------------------|
| **FR-SDD-008** | `CatalogService` con filtro `id_empresa` en TODAS queries CRUD                           | §1.1 (tabla de servicios)                             |
| **FR-SDD-009** | Índice compuesto `UNIQUE (id_empresa, codigo)` en BD + validación en servicio            | §1.3 (validación unicidad)                            |
| **FR-SDD-010** | Flujo offline-first: `sync_queue`, JWT local 7 días gracia, banner después 7 días        | §3 (políticas offline)                                |
| **FR-SDD-011** | `LicenseService.validar()` con firma Ed25519 contra LM; emisión llaves BS-XXXX-XXXX-XXXX | §1.2 (servicio licencia) — referenced, mainly FN spec |
| **FR-SDD-012** | Matriz permisos 18×3 en `permisos_acceso` tabla; ADMIN forzado a `editar` todo           | §1.4 (matriz permisos), §1.5 (dependencias FastAPI)   |
| **PF-001**     | Búsquedas catálogo con `id_empresa` < 10 ms; índices compositos adecuados                | §1.3 (índices)                                        |
| **SE-001**     | `id_empresa` en 100% queries catálogo y permisos; auditoría de fugas                     | §1.2 (modelos), §1.5 (validación siempre)             |
| **SE-002**     | Ed25519 validación licencias; bcrypt/argon2 passwords; JWT HMAC-SHA256                   | Referenciado en FR-SDD-011                            |

## 5. Interfaces con Otras Capas

### 5.1 Entrada desde Capa de Presentación (Flutter)

- **Endpoint**: `GET/POST/PUT/DELETE /api/v1/catalogo/*`
- **Autenticación**: JWT Bearer con `id_empresa` en payload
- **Validación previa**: `id_empresa` extraído del token, filtrado en todas las operaciones
- **Formato**: Datos según modelo Pydantic correspondiente (marca, producto, transporte, etc.)

### 5.2 Salida a Capa de Persistencia (PostgreSQL)

- **Tablas**: `marcas`, `transportes`, `productos`, `almacenes`, `conductores`, `terceros`, `permisos_acceso`, `empresas`
- **Filtro obligatorio**: `id_empresa` en toda query, INSERT, UPDATE, DELETE
- **Índices**: `UNIQUE (id_empresa, codigo)` en tablas con campo `codigo`
- **Restricciones**: `ON DELETE RESTRICT` en FK críticas

### 5.3 Entrada desde Capa de Seguridad (Validaciones)

- **`id_empresa`**: Siempre extraído del JWT `sub/payload`, nunca aceptado como parámetro sin validación previa
- **Rol**: `current_user.rol` determina qué módulos puede acceder (matriz 18×3)
- **Permiso**: `permiso.acceso` (`ver`/`editar`/`ninguno`) determina si la operación procede

### 5.4 Integración con Licencias (FR-SDD-011)

- **`POST /licencias/validar`**: Valida clave Ed25519 contra LM, retorna éxito/fallo
- **Emission llaves**: `POST /activacion/llaves` (ADMIN) emite `BS-XXXX-XXXX-XXXX` SHA-256, 7 días máx.
- **Canje llave**: `POST /activacion/validar` canjea la llave con `SELECT ... FOR UPDATE` sobre tabla de licencias

## 5. Suposiciones y Restricciones

### 5.1 Suposiciones

- Base de datos PostgreSQL 15+ con soporte para índices únicos compuestos
- JWT siempre incluye `id_empresa` en el payload (validado por `get_current_empresa`)
- Los 18 módulos están definidos y estables (no se añaden nuevos sin proceso formal)
- Las roles ADMIN/OPERADOR/AUDITOR ya están configurados en el sistema

### 5.2 Restricciones

- **id_empresa obligatorio**: Debe filtrarse en TODA operación sobre catálogos y permisos, sin excepciones
- **Índice compuesto único**: `UNIQUE (id_empresa, codigo)` en tablas catálogo que tengan campo `codigo` (productos, marcas, transportes, etc.)
- **ADMIN force editar**: El rol ADMIN debe tener `acceso = 'editar'` en todos los módulos (M1-M18), sin excepción posible por configuración
- **TRABAJADOR fusionado**: El rol TRABAJADOR ya no existe; fue fusionado en OPERADOR en migración 025
- **Migraciones hand-made**: Cambios a `permisos_acceso`, `empresas` (campos nuevos) van como migraciones SQL (001-025+), idempotentes
- **Sin nuevos módulos sin proceso**: Añadir un nuevo módulo a la matriz 18×3 requiere actualizar: diseño, implementación, tests, ADR, constitución, matriz global de trazabilidad
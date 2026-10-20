# Visión Lógica — BALANSOFT-WS

**Viewpoint:** ISO/IEC/IEEE 42010 - Visión Lógica (Logical View)

## 1. Propósito

La visión lógica describe los componentes del sistema, sus interfaces y las relaciones entre ellos, enfocándose en la funcionalidad observable por las partes interesadas. Esta vista responde a la preocupación de cómo el sistema se estructura conceptualmentepara satisfacer los requisitos funcionales y no funcionales.

## 2. Componentes del Sistema

### 2.1 Capa de Presentación (Flutter BLoC)

| Componente       | Responsabilidad                                                                     | Interfaces Clave                                       |
|------------------|-------------------------------------------------------------------------------------|--------------------------------------------------------|
| `PantallaBoleto` | Formulario de pesaje, vista de bolete, operaciones (entrada/salida/anular/imprimir) | `AppTranslations.tr`, `AppConfig.rol`, `StationRole`   |
| `Dashboard`      | KPIs, salud del sistema, últimos pesajes, estadísticas                              | `AppConfig.offline`, `SystemDiagnosticsScreen`         |
| `ScreenKardex`   | Consultar saldos, historial de movimientos, exportar                                | Filtros por producto/almacén/fecha, `Export PDF/Excel` |
| `SettingsScreen` | Preferencias de estación (tema, idioma, formato)                                    | `SharedPreferences`, `empresas.idioma`, `config.json`  |
| `AuthScreen`     | Login, registro, recuperación de cuenta                                             | `BCrypt`, validación `BALANSOFT-LM`, `hardware_id`     |

### 2.2 Capa de Aplicación (FastAPI Servicios)

| Servicio          | Responsabilidad                                                              | Endpoints Clave                                                                  |
|-------------------|------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| `WeighingService` | Lógica de pesaje: create, close, anular, update, cálculos kardex             | `POST /weighing/create`, `POST /weighing-close`, `PUT /{boleto}/anular`          |
| `CatalogService`  | CRUD catálogos: marcas, transportes, productos, almacenes, conductores, etc. | `GET/POST/PUT/DELETE /catalogo/*`                                                |
| `AuthService`     | Autenticación JWT, validación licencia, login local/offline                  | `POST /auth/login`, `POST /auth/login-local`, `POST /auth/refresh-token`         |
| `LicenseService`  | Validación Ed25519, tiers, emisión de llaves                                 | `POST /licencias/validar`, `POST /activacion/llaves`, `POST /activacion/validar` |
| `SyncService`     | Sincronización local↔servidor, resolución de conflictos                      | `POST /sync/push`, `GET /sync/pull`, `GET /sync/status`                          |
| `ReportService`   | Reportes PDF/Excel, tickets, exportación                                     | `GET /reports/daily`, `GET /reports/monthly`, `GET /boleto/{boleto}/pdf`         |
| `AuthRepository`  | Mejor esfuerzo sincronización identidad+usuarios tras login                  | `sincronizarIdentidadYUsuarios`, identidad_local, credenciales globales          |

### 2.3 Capa de Persistencia (BD)

| Entidad             | Atributos Clave                                                                         | Relaciones                                    |
|---------------------|-----------------------------------------------------------------------------------------|-----------------------------------------------|
| `empresas`          | `id_empresa PK`, `nombre_fiscal`, `nombre_comercial`, `rif_nit`, `idioma`               | 1:N a todas las entidades                     |
| `usuarios`          | `id_usuario PK`, `id_empresa FK`, `nombre`, `email UK`, `rol`                           | N:1 a empresas                                |
| `boletos_pesaje`    | `boleto PK`, `id_empresa FK`, `estado_boleto`, `peso_neto`, `fecha_hora_entrada/salida` | N:1 a empresas, balanzas, productos/almacenes |
| `kardex`            | `id_kardex PK`, `id_empresa FK`, `id_movimiento` (10/60), `valor`, `fecha_kardex`       | N:1 a empresas, opcional N:1 a boletos        |
| `series_numeracion` | `id_serie PK`, `id_empresa FK`, `nombre`, `prefijo`, `siguiente`, `digitos`, `activa`   | N:1 a empresas                                |
| `licencias`         | `id PK`, `id_cuenta FK`, `tier`, `status`, `hardware_id UK`, `expira`                   | N:1 a cuentas                                 |
| `permisos_acceso`   | `id_empresa PK`, `rol PK`, `modulo PK`, `acceso`                                        | Identifica por (empresa, rol, modulo)         |

#### 2.3.1 Columnas reservadas

Columnas que existen en el esquema, se persisten y viajan en el round-trip de sincronización,
pero **no tienen semántica de negocio definida**: ninguna consulta las lee, ninguna UI las expone
y ningún requisito las especifica. Se conservan de forma deliberada para no romper clientes ni
el round-trip, pero **no deben usarse** hasta que exista una decisión de negocio explícita.

| Columna | Tabla | Estado | Reglas |
|---------|-------|--------|--------|
| `multi_despacho_recepcion` | `boletos_pesaje` | Inerte (persiste y se sincroniza; 0 consultas la leen) | **No usarla**, **No borrarla**, **No quitarla del round-trip**, y no implementarla sin decisión de negocio |

> Origen: investigación de volumen sobre 10 000 boletos — marcar el flag no movió los tiempos
> de `reports/daily` ni `reports/monthly`, lo que confirma que la funcionalidad nunca se
> implementó y que la columna es puro costo de round-trip (≈35 bytes/boleto).

> Trazabilidad: `tests/test_api_docs.py::TestDocumentacionDeColumnasReservadas` falla si esta
> sección desaparece, si la columna se borra del DDL canónico
> (`src/backend/balansoft-ws-local.sql`) o si se leen sus tres reglas.

### 2.4 Capa de Integración Hardware (HAL)

| Módulo         | Protocolo                       | Marcas Compatibles                      | Responsabilidad                                                   |
|----------------|---------------------------------|-----------------------------------------|-------------------------------------------------------------------|
| `HAL_Serial`   | RS-232 / USB / Bluetooth RFCOMM | Toledo, Yaohua, Rice Lake, Torrey, Keli | Lectura de frames, parsing, checksum XOR                          |
| `HAL_TCP`      | Sockets TCP                     | Indicadores red serial/TCP              | Conexión persistente, reconexión con backoff                      |
| `FormatTicket` | Tabla canónica v3.24            | Epson, OKI (80mm/58mm)                  | Formato canónico 5 columnas, inicialización `ESC @`, corte `GS V` |

## 3. Interfaces de Componente

### 3.1 Interfaces de API FastAPI

Todos los endpoints siguen el patrón `/api/v1/*` y requieren autenticación JWT Bearer. El `id_empresa` se extrae del token y se filtra en todas las consultas.

#### Endpoints de Pesaje (Rol `local` solo)

| Endpoint                   | Método | Descripción                                   | Rol Requerido    |
|----------------------------|--------|-----------------------------------------------|------------------|
| `/weighing/create`         | POST   | Crear boleto entrada → PENDIENTE              | OPERADOR         |
| `/weighing-close/{boleto}` | POST   | Cerrar pesaje → CERRADO + kardex              | OPERADOR/ADMIN   |
| `/{boleto}`                | PUT    | Modificar boleto → MODIFICADO                 | ADMIN/SUPERVISOR |
| `/{boleto}/anular`         | PUT    | Anular boleto (motivo obligatorio)            | SUPERVISOR+      |
| `/pendientes`              | GET    | Boletos abiertos (PENDIENTE/MODIFICADO)       | Cualquier rol    |
| `/list`                    | GET    | Listado con filtros (fecha, vehículo, estado) | Cualquier rol    |
| `/{boleto}/pdf`            | GET    | Ticket PDF (ReportLab, marca ANULADO)         | Cualquier rol    |

#### Endpoints de Catálogos (Ambos roles, restricciones por rol)

| Endpoint      | Método          | Descripción              | Rol Requerido                         |
|---------------|-----------------|--------------------------|---------------------------------------|
| `/catalogo/*` | GET             | Consultas CRUD completas | OPERADOR (lectura), ADMIN (escritura) |
| `/catalogo/*` | POST/PUT/DELETE | Operaciones de catálogo  | ADMIN solo                            |

#### Endpoints de Seguridad y Licencias (Rol `server`)

| Endpoint              | Método       | Descripción                                | Rol Requerido      |
|-----------------------|--------------|--------------------------------------------|--------------------|
| `/auth/register`      | POST         | Crear empresa + usuario ADMIN              | Solo proveedor     |
| `/auth/login`         | POST         | Login online (valida LM)                   | Cualquier usuario  |
| `/licencias/validar`  | POST         | Validación Ed25519 contra LM               | Cualquier estación |
| `/activacion/llaves`  | POST (ADMIN) | Emitir llave un solo uso BS-XXXX-XXXX-XXXX | ADMIN              |
| `/activacion/validar` | POST         | Canje llave con SELECT FOR UPDATE          | Usuario con llave  |

#### Endpoints de Sincronización (Ambos roles)

| Endpoint       | Método | Descripción                         | Dirección      |
|----------------|--------|-------------------------------------|----------------|
| `/sync/push`   | POST   | Subir pendientes offline → servidor | Local → Server |
| `/sync/pull`   | GET    | Bajar datos servidor → local        | Server → Local |
| `/sync/status` | GET    | Estado de la cola sync              | Cualquier rol  |

### 3.2 Interfaces de Base de Datos

- **Motor**: PostgreSQL 15+ (o SQL Server en Fase 2)
- **ORM**: SQLAlchemy 2.0 async (asyncpg)
- **Migraciones**: Hand-made SQL (001-025), idempotentes, sin Alembic
- **Identificadores**: `gen_random_uuid()` (pgcrypto), UUID v4
- **Filtro obligatorio**: `id_empresa` en TODO query, INSERT, UPDATE, DELETE

### 3.3 Interfaces Hardware (HAL)

- **Puerto serie**: `/dev/ttyUSB0`, `/dev/ttyACM0`, RFCOMM Bluetooth
- **Indicadores TCP**: Host: Puerto configurables (ej: 9100, 10101)
- **Formato de frame**: Configurable (`lf`/`cr`/`crlf`/`stx_etx`, con/without checksum XOR)
- **Timeouts**: Lectura 1.0s a 2.0s, `writer.wait_closed()` con `asyncio.wait_for(timeout=2.0)`
- **Estabilidad**: Espera 3 segundos mínima antes de capturar peso

## 4. Flujos de Datos Lógicos

### 4.1 Flujo: Creación de Boleto Entrada

```
Operador → Flutter: Selecciona "Entrada" → Llena datos → POST /weighing/create
                                   ↓
FastAPI: Validar anti-duplicidad (placa + id_empresa) → SELECT FOR UPDATE
                                   ↓
DB: Insertar boleto PENDIENTE → Asignar numero_boleto (series_numeración FOR UPDATE)
                                   ↓
FastAPI: 201 Response con boleto creado
                                   ↓
Flutter: Mostrar formulario con peso por capturar
                                   ↓
Operador → Balanza: Captura peso (HAL serial/TCP) → PEC, PER
                                   ↓
Flutter: Peso capturado en formulario
                                   ↓
Operador → Flutter: Presiona "Guardar" → POST datos completos
```

### 4.2 Flujo: Cierre de Pesaje (Salida)

```
Operador → Flutter: Selecciona boleto PENDIENTE → "Salida" → Llena datos salida → POST /weighing-close
                                   ↓
FastAPI: Validar boleto PENDIENTE + id_empresa → UPDATE estado=CERRADO
                                   ↓
FastAPI: Calcular PTE, PTS, PNT, PDF, PDV
                                   ↓
FastAPI: Verificar tolerancia comercial (warning, no bloquea)
                                   ↓
FastAPI: Registrar movimiento Kardex ID 10 (ingreso) o 60 (despacho)
                                   ↓
DB: Actualizar kardex + saldo de inventario
                                   ↓
FastAPI: 200 Response boleto CERRADO
                                   ↓
Flutter: Mostrar boleto CERRADO + opciones (imprimir, nuevo)
```

### 4.3 Flujo: Anulación de Boleto

```
Operador → Flutter: Selecciona boleto → "Anular" → Ingresa motivo (≥10 caracteres) → PUT /{boleto}/anular
                                   ↓
FastAPI: Validar rol (SUPERVISOR+) + motivo length → UPDATE estado=ANULADO
                                   ↓
Si boleto estaba CERRADO:
   ↓
   FastAPI: Calcular peso neto original
   ↓
   FastAPI: Registrar movimiento kardex INVERSO (10 ↔ 60)
   ↓
   FastAPI: Actualizar saldos de inventario (cancelar efecto original)
FastAPI: 200 Response boleto ANULADO
                                   ↓
Flutter: Confirmar anulación + registrar auditoría
```

## 5. Preocupaciones Atendidas (Concerns)

| Concern                            | Cómo se aborda                                                                             |
|------------------------------------|--------------------------------------------------------------------------------------------|
| **Aislamiento multi-tenant**       | `id_empresa` en TODAS las queries, filtros, inserciones, validaciones                      |
| **Inmutabilidad metrológica**      | Peso capturado NUNCA editado; `es_manual=True` solo con autorización ADMIN/SUPERVISOR      |
| **Estados de bolete consistentes** | Máquina de estados: PENDIENTE → CERRADO/MODIFICADO → ANULADO; transiciones validadas       |
| **Anti-duplicidad**                | `SELECT ... WHERE placa + id_empresa` no tiene boleto PENDIENTE → código 400               |
| **Series numeracionales**          | `SELECT ... FOR UPDATE` en `series_numeración`; nevera reutilización; DELETE → 409         |
| **Modo offline**                   | Capa SQLite + sync_queue; operaciones PENDIENTE sincronizables al recuperar conexión       |
| **Performance**                    | Paginación `limit`/`skip` obligatoria; helper `_enriquecer_pesajes_lista` para evitar N+1  |
| **Seguridad**                      | JWT HMAC-SHA256 + validación Ed25519; matriz 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR) |
| **Metrología legal**               | Timestamp UTC ISO 8601; `id_balanza`; estado `stable`/`unstable`; rechazo > 105% capacidad |

## 6. Relación con Vistas Adyacentes

- **Vista de Despliegue** (`deployment-view.md`): Esta visión lógica describe los componentes que se despliegan en cada entorno (local vs server)
- **Vista de Implementación** (`implementation-view.md`): Los componentes aquí definidos se mapean a clases Python (FastAPI), Dart (Flutter) y archivos SQL (migraciones)
- **Correspondencias** (`correspondences.md`): Ver sección 7 para mapeo entre viewpoints
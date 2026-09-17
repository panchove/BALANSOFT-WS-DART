# ARCH.md — Arquitectura y Especificaciones del Sistema BALANSOFT

| Atributo       | Valor                                       |
|----------------|---------------------------------------------|
| **Documento**  | ARCH (Arquitectura)                         |
| **Versión**    | 2.0                                         |
| **Fecha**      | 2026-09-08                                  |
| **Estado**     | Vigente                                     |
| **Autor**      | Equipo BALANSOFT                            |
| **Norma**      | ISO/IEC/IEEE 42010 + 29148                  |
| **Fuente**     | PRD v2.0 (autoridad: `docs/PRD.md`)         |

### Cambios desde la versión anterior

- v2.0 (2026-09-08): **re-alineación al stack real de implementación** — FastAPI (Python 3.12+) + PostgreSQL 15 + Flutter (BLoC), API REST JWT `/api/v1/*`, multi-empresa por `id_empresa` (UUID) resuelto del JWT, kardex numérico (10/60), 4 estados del boleto con normalización legacy, esquema en `schema.sql` + migraciones SQL, despliegue con uvicorn/systemd. El HAL de hardware y las reglas de estabilidad/validación se trasladan a "integración futura vía estación/hardware". Reemplaza la reinvención .NET/WinForms de versiones previas.
- v2.4 (2026-08-20): ajustes de alineación con PRD v2.3 y AGENTS v1.1 — renombramiento del archivo (era `ARCHITECTURE.md`), limpieza de vestigios Vaadin (`*View` → `*Form`, `Views/` → `Forms/`), mermaid de §12.1 normalizado, esquema DB consistente con T-SQL, decisiones de UI en torno a **Modern Flat UI / MetroSet UI**.
- v2.3 (2026-08-20): re-migración de stack a **.NET Framework 4.8 + WinForms + EF6 + SQL Server Express 2022** (histórico, no vigente).
- v2.2 (2026-08-19): versión previa (Spring Boot 3.x + Vaadin 24+) (histórico, no vigente).

---

## 1. Visión General del Sistema

BALANSOFT es un **sistema de gestión de estación de pesaje industrial para camiones** con arquitectura **cliente-servidor**: backend **API REST FastAPI (Python 3.12+ async)** + frontend **Flutter (Dart, BLoC)** en modo kiosk. El backend se despliega con **uvicorn + systemd** sobre **PostgreSQL 15+**; el peso se recibe por API (pesaje manual restringido a ADMIN/SUPERVISOR). El control directo de hardware (balanzas, cámaras, semáforos y barreras) es **integración futura vía estación** — ver §9.

### 1.1 Decisiones Arquitectónicas Clave

| Decisión                                              | Justificación                                                                                    |
|-------------------------------------------------------|--------------------------------------------------------------------------------------------------|
| **Cliente-servidor: API REST JWT `/api/v1/*`**        | Backend **FastAPI async** desplegado con uvicorn/systemd; la UI **Flutter** consume los endpoints vía HTTP y DataSource remoto |
| **Multi-empresa por `id_empresa`**                    | Toda entidad lleva `id_empresa` (UUID FK a `empresas`); `get_current_empresa` lo resuelve del JWT (no existe `tenants`/`tenant_id`) |
| **PostgreSQL 15+ con SQLAlchemy 2.0 async**           | ORM async (asyncpg) alineado a FastAPI; esquema en `schema.sql` + migraciones SQL versionadas (sin EF) |
| **Kardex sin disparadores**                           | Saldo a fecha de corte **calculado** (sin `saldo_anterior`/`saldo_actual` ni trigger); inverso 10↔60 al anular CERRADO |
| **Offline-first en Flutter**                          | `sqflite` local + cola de sincronización (`pendiente/sincronizado`) + endpoints `/api/v1/sync/*` |
| **Sesión JWT (access + refresh)**                     | HS256 (python-jose); passwords con **BCrypt**; el contexto (usuario, rol, `id_empresa`) viaja firmado en el token |
| **Licencias (BALANSOFT-LM)**                          | Cliente HTTP contra SGLB, Ed25519 anti-fake-server, caché, tiers DEMO/MONOPUESTA/CENTRAL |
| **Modo kiosk (Flutter)**                              | Pantalla completa, sin bordes (Smoke test REQ-NF-OPE-001); tema claro/oscuro persistente (`ThemeController`) |

---

## 2. Arquitectura de Alto Nivel

```mermaid
flowchart TB
    subgraph Client["CLIENTE (Flutter/Dart — kiosk, offline-first)"]
        direction TB

        subgraph App["BALANSOFT App (Flutter + BLoC)"]
            UI[Pantallas (screens)\nAuth, Dashboard, Weighing, Catalogos, Reports]
            Bloc[BLoCs / Cubits\nAuthBloc, WeighingBloc, CatalogBloc, SyncBloc]
            Repos[Repositories + DataSource remoto/local]
            Local[(sqflite local + cola de sync\npendiente / sincronizado)]
        end

        UI --> Bloc
        Bloc --> Repos
        Repos --> Local
    end

    Repos -.REST /api/v1/* / JWT Bearer.-> API

    subgraph Server["SERVIDOR (Linux, uvicorn + systemd)"]
        API[FastAPI app/main.py\nMiddleware: Audit + CORSMiddleware + JWT]
        DEP[app/api/dependencies.py\nget_current_empresa / get_current_usuario]
        EP[Endpoints /api/v1\n/auth /weighing /catalogo /sync /reports /directorio /flota /inventario /exports /health]
        SVC[Servicios de dominio\nWeighingService, CatalogService, ReportService,\nSyncService, TicketService, LicenseService]
        ORM[SQLAlchemy 2.0 async\nmodels + schemas Pydantic v2]
    end

    API --> DEP
    API --> EP
    EP --> SVC
    SVC --> ORM
    SVC --> LM[BALANSOFT-LM (SGLB)\nLicencias Ed25519]

    ORM --> DB[(PostgreSQL 15\nbalansoft_ws multi-empresa)]

    classDef app fill:#e3f2fd,stroke:#1565c0,stroke-width:2px;
    classDef srv fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef db fill:#f3e5f5,stroke:#6a1b9a,stroke-width:2px;

    class App,UI,Bloc,Repos,Local app;
    class Server,API,DEP,EP,SVC,ORM srv;
    class DB db;
```

---

## 3. Stack Tecnológico

| Capa                 | Tecnología                          | Versión |
|----------------------|-------------------------------------|---------|
| **Runtime**          | Python                              | 3.12+   |
| **Framework Web**    | FastAPI (async)                     | Última  |
| **Frontend**         | Flutter (Dart) con BLoC             | Última estable |
| **ORM / Datos**      | SQLAlchemy 2.0 (async) + asyncpg    | 2.x     |
| **Validación**       | Pydantic v2                         | 2.x     |
| **Base de Datos**    | PostgreSQL                          | 15+     |
| **Esquema / Migraciones** | `schema.sql` (idempotente) + `migrations/*.sql` (sin Alembic) | — |
| **Sesión**           | JWT HS256 (python-jose) access + refresh | Última |
| **Hash de password** | BCrypt (passlib)                    | Última  |
| **PDF / Excel**      | ReportLab (tickets PDF, marca de agua ANULADO) / openpyxl | Última  |
| **Pruebas**          | pytest (backend), flutter_test (frontend) | Último |
| **Lint / Tipos**     | ruff, mypy (backend) / flutter analyze | Último |
| **Gestión de deps**  | uv (+ `uv sync`)                    | Última  |
| **Despliegue**       | uvicorn + systemd (`deploy/balansoft-ws.service`) + `scripts/setup_db.sh` | — |

---

## 4. Estructura del Proyecto

```text
backend/                        # API REST FastAPI (Python 3.12+, async)
├── app/
│   ├── main.py                 # App FastAPI: middlewares, routers, CORS, health
│   ├── api/
│   │   ├── dependencies.py     # get_current_empresa, get_current_usuario, permisos (_PERMISOS_PESO_MANUAL, _PERMISOS_ANULACION)
│   │   └── v1/endpoints/
│   │       ├── auth.py         # register, login, validate-license, refresh-token, logout
│   │       ├── pesajes.py      # weighing: create, close/{boleto}, anular/{boleto}, update pendientes, list, boleto/{boleto}, pdf, imagenes
│   │       ├── catalogo.py     # catálogos + sync de catálogo
│   │       ├── directorio.py   # transportes, conductores, terceros
│   │       ├── flota.py        # marcas, modelos_camion, camiones, remolques
│   │       ├── inventario.py   # productos, almacenes, balanzas
│   │       ├── reports.py      # reportes daily/monthly/vehicle
│   │       ├── exports.py      # exportación Excel
│   │       └── sync.py         # push, status, pull (offline-first)
│   ├── core/
│   │   ├── config.py           # Settings desde .env (pydantic-settings)
│   │   ├── database.py         # AsyncSession / async engine (asyncpg)
│   │   ├── security.py         # JWT (python-jose HS256) + BCrypt (passlib)
│   │   ├── license_client.py   # Cliente HTTP contra BALANSOFT-LM (SGLB, Ed25519)
│   │   └── audit.py            # AuditMiddleware (tabla `auditoria`)
│   ├── models/                 # Modelos SQLAlchemy 2.0 (mapean schema.sql)
│   ├── schemas/                # Pydantic v2 (DTOs de entrada/salida)
│   └── services/
│       ├── weighing_service.py # Crear/cerrar/anular/update/pendientes/list + cálculos PTE/PTS/PNT/PND/PDF/PDV + kardex 10/60
│       ├── catalog_service.py  # CRUD genérico de catálogos
│       ├── report_service.py   # Reportes daily/monthly/vehicle
│       ├── sync_service.py     # Cola offline (push/status/pull)
│       ├── ticket_service.py   # Tickets PDF con ReportLab
│       └── license_service.py  # Validación contra BALANSOFT-LM
├── schema.sql                  # Esquema final idempotente (~21 tablas, multi-empresa)
├── migrations/                 # Migraciones SQL versionadas (001..003*.sql, sin Alembic)
├── scripts/                    # setup_db.sh, seed_data.py, seed_simulacion.py, generate_signing_keys.py, start_api.sh
├── deploy/balansoft-ws.service # Unidad systemd de producción
└── tests/                      # pytest (BD de tests: PostgreSQL real `balansoft_ws_test`)

frontend/                       # App Flutter (Dart), BLoC, offline-first
└── lib/
    ├── core/                   # config, constants, theme, security, exceptions, utils, widgets
    ├── data/
    │   ├── datasources/        # remote (HTTP /api/v1/*) + local (sqflite)
    │   ├── mappers/            # DTO <-> entidad <-> modelo local
    │   ├── models/             # Modelos de datos (JSON de la API y filas sqflite)
    │   └── repositories/       # Implementaciones de repositorios (remoto + local + cola de sync)
    ├── domain/
    │   ├── entities/           # Entidades de negocio
    │   ├── repositories/       # Contratos de repositorio
    │   └── usecases/           # Casos de uso
    ├── presentation/
    │   ├── providers/bloc/     # auth, weighing, catalog, catalog_crud, license, sync (BLoC/Cubit)
    │   ├── providers/cubits/   # Cubits auxiliares
    │   ├── routes/             # Enrutado por sesión/rol
    │   ├── screens/            # auth, dashboard, weighing, catalog(s), reports, settings
    │   └── widgets/            # cards, common, forms (tema claro/oscuro)
    └── injection.dart          # Inyección de dependencias (repositorios/blocs)
```

---

## 5. Modelo de Dominio (Relaciones entre Entidades)

```mermaid
erDiagram
    empresas ||--o{ usuarios : tiene
    empresas ||--o{ transportes : tiene
    empresas ||--o{ marcas : tiene
    empresas ||--o{ modelos_camion : tiene
    empresas ||--o{ camiones : tiene
    empresas ||--o{ remolques : tiene
    empresas ||--o{ conductores : tiene
    empresas ||--o{ terceros : tiene
    empresas ||--o{ productos : tiene
    empresas ||--o{ almacenes : tiene
    empresas ||--o{ balanzas : tiene
    empresas ||--o{ boletos_pesaje : tiene
    empresas ||--o{ imagenes_pesaje : tiene
    empresas ||--o{ kardex : tiene
    empresas ||--o{ sync_queue : tiene
    empresas ||--o{ auditoria : tiene
    empresas ||--o{ logs_sistema : tiene

    marcas ||--o{ modelos_camion : agrupa
    transportes ||--o{ camiones : posee
    transportes ||--o{ conductores : emplea
    modelos_camion ||--o{ camiones : modela

    boletos_pesaje }o--|| transportes : transportado_por
    boletos_pesaje }o--|| conductores : asignado_a
    boletos_pesaje }o--|| camiones : vehiculo_principal
    boletos_pesaje }o--o| remolques : acoplado
    boletos_pesaje }o--|| productos : contiene
    boletos_pesaje }o--|| almacenes : ubicado_en
    boletos_pesaje }o--o| terceros : proveido_por
    boletos_pesaje }o--o| balanzas : pesado_en
    boletos_pesaje }o--o| usuarios : creado_por
    boletos_pesaje ||--o{ imagenes_pesaje : fotos

    kardex }o--|| productos : registra
    kardex }o--|| almacenes : ubicado_en
    kardex }o--o| boletos_pesaje : originado_por

    sync_queue }o--|| boletos_pesaje : encola

    empresas {
        UUID id PK
        VARCHAR nombre
        VARCHAR RIF
        TEXT direccion
        VARCHAR telefono
        VARCHAR email
        VARCHAR sistema_unidades
        VARCHAR unidad_peso
        VARCHAR timezone
        BOOLEAN activo
    }

    usuarios {
        UUID id PK
        UUID id_empresa FK
        VARCHAR username
        VARCHAR password_hash
        VARCHAR nombre
        VARCHAR rol
        BOOLEAN activo
    }

    boletos_pesaje {
        UUID id PK
        UUID id_empresa FK
        VARCHAR numero_boleto UNIQUE
        VARCHAR boleto_tipo
        TIMESTAMPTZ boleto_fecha
        VARCHAR estado_boleto
        VARCHAR placa
        UUID transporte_id FK
        UUID conductor_cedula_dni FK
        UUID producto_id FK
        UUID almacen_id FK
        UUID id_remolque FK
        UUID balanza_entrada_id FK
        UUID balanza_salida_id FK
        DECIMAL peso_entrada_vehiculo
        DECIMAL peso_salida_vehiculo
        DECIMAL peso_entrada_remolque
        DECIMAL peso_salida_remolque
        DECIMAL peso_total_entrada
        DECIMAL peso_total_salida
        DECIMAL peso_neto
        DECIMAL peso_neto_declarado
        DECIMAL peso_diferencia
        DECIMAL porcentaje_desviacion
        DECIMAL densidad
        DECIMAL litros
        VARCHAR documento
        DECIMAL flete
        DECIMAL costo_flete
        BOOLEAN remolque
        BOOLEAN multi_despacho_recepcion
        VARCHAR creado_por
        VARCHAR salida_por
        VARCHAR modificado_por
        VARCHAR anulado_por
        VARCHAR motivo_anulacion
        VARCHAR foto_entrada_url
        VARCHAR foto_salida_url
        TIMESTAMPTZ created_at
    }

    kardex {
        UUID id PK
        UUID id_empresa FK
        INT id_movimiento
        DECIMAL valor
        UUID id_producto FK
        UUID id_almacen FK
        TIMESTAMPTZ fecha_kardex
        TIMESTAMPTZ fecha_documento
        VARCHAR documento
        VARCHAR boleto
        UUID id_boleto FK
    }

    auditoria {
        UUID id_auditoria PK
        UUID id_usuario
        UUID id_empresa FK
        VARCHAR accion
        VARCHAR entidad
        VARCHAR entidad_id
        JSONB detalle
        VARCHAR ip
        TIMESTAMPTZ created_at
    }
```

> Las columnas mostradas son referenciales. El esquema físico autoritativo vive en `backend/schema.sql` (idempotente) y la historia en `backend/migrations/*.sql`. Todos los timestamps se persisten en **UTC** (`TIMESTAMPTZ`), los JSON en `JSONB`, y toda entidad porta `id_empresa` (UUID FK a `empresas`).

---

## 6. Máquina de Estados del Boleto

```mermaid
stateDiagram-v2
    [*] --> PENDIENTE

    PENDIENTE --> CERRADO : Registrar Salida
    PENDIENTE --> ANULADO : Anular (ADMIN/SUPERVISOR)

    CERRADO --> MODIFICADO : Update (ADMIN/SUPERVISOR)
    CERRADO --> ANULADO : Anular (ADMIN/SUPERVISOR)\nRequiere inverso en Kardex (10<->60)

    MODIFICADO --> ANULADO : Anular (ADMIN/SUPERVISOR)\nRequiere inverso en Kardex

    ANULADO --> [*]
    CERRADO --> [*]
    MODIFICADO --> [*]

    state PENDIENTE {
        [*] --> EsperandoSalida
    }

    state CERRADO {
        [*] --> FlujoCompleto
    }

    state MODIFICADO {
        [*] --> CorreccionAplicada
    }

    state ANULADO {
        [*] --> NoAfectaKardex
    }
```

> **Normalización legacy** (`WeighingService.normalizar_estado`): el estado persiste en `estado_boleto` con **4 valores** — `PENDIENTE`, `CERRADO`, `MODIFICADO`, `ANULADO` (definido en MODEL.md; `MODIFICADO` es un estado implementado que el PRD trató como transición). Valores históricos/legacy (`COMPLETADO`→`CERRADO`, `ABIERTO`/`AUTOMATICO`→`PENDIENTE`) se normalizan al leerse. Los estados `COMPLETADO`/`ABIERTO`/`AUTOMATICO` **no** son estados vigentes.

### 6.1 Definición de Estados

| Estado        | Descripción             | Reporta En        | Puede Transicionar A          |
|---------------|-------------------------|-------------------|-------------------------------|
| **PENDIENTE** | Tiene entrada, falta salida | "En Tránsito"     | CERRADO, ANULADO              |
| **CERRADO**   | Entrada + salida completas   | Ingreso/Despacho  | MODIFICADO, ANULADO (con Kardex inverso) |
| **MODIFICADO**| CERRADO corregido por ADMIN/SUPERVISOR | Ingreso/Despacho | ANULADO (con Kardex inverso) |
| **ANULADO**   | Anulado en entrada O salida | **Solo auditoría** | —                             |

### 6.2 Reglas de Negocio

- Solo **ADMIN/SUPERVISOR** puede anular (endpoint `anular/{boleto}` con `_PERMISOS_ANULACION`)
- La anulación requiere **motivo** obligatorio (`motivo_anulacion`)
- Anulado PENDIENTE → sin impacto en Kardex
- Anulado CERRADO (o MODIFICADO) → registra **movimiento INVERSO en Kardex (10↔60)** para cancelar el movimiento original **conservando la historia** (no se borra el registro original)
- PENDIENTE → solo se permite CERRAR (salida) o ANULAR
- El número de boleto `TA-00000001` es **secuencial y no reutilizable** (`numero_boleto VARCHAR(30) UNIQUE`)

---

## 7. Flujos de Pesaje

> El peso llega por **API** (pesaje manual restringido a ADMIN/SUPERVISOR vía `_PERMISOS_PESO_MANUAL`, o lecturas futuras vía estación — §9). Las acciones de hardware (barreras/semáforos) son **integración futura**.

### 7.1 Flujo de Entrada

```mermaid
flowchart TD
    INICIO[Operador presiona Entrada] --> TIPO{Tipo de pesaje?}

    TIPO -->|MANUAL (ADMIN/SUPERVISOR)| MANU[Ingreso manual de pesos]
    TIPO -->|Lectura futura vía estación| AUTO[Lectura de balanza - futuro §9]

    AUTO --> A1[Leer peso_entrada_vehiculo / remolque]
    A1 --> A2{Estable 3 seg? (futuro)}
    A2 -->|No| A1
    A2 -->|Sí| A3[Reseñar boleto con pesos de balanza]

    MANU --> M1[Ingresar placa / remolque si aplica]
    M1 --> M2[Seleccionar conductor/transporte/cliente-producto/almacén]
    M2 --> M3[Ingresar peso_entrada_vehiculo + peso_entrada_remolque si aplica]
    M3 --> M4[Documento, densidad, foto_entrada_url opcional]

    A3 --> CREAR[POST /api/v1/weighing/create]
    M4 --> CREAR
    CREAR --> CALC[Calcular peso_total_entrada = PEC + PER]
    CALC --> NUM[Generar numero_boleto seq: TA-00000001]
    NUM --> PEND[Crear boleto estado_boleto=PENDIENTE]
    PEND --> AUD[Registrar en auditoría\nAuditMiddleware + detalle JSONB]
    AUD --> OK[Boleto creado exitosamente]
    OK --> FIN[Operador continúa]
```

### 7.2 Flujo de Salida

```mermaid
flowchart TD
    INICIO[Operador presiona Salida] --> BUSCAR[GET /api/v1/weighing/pendientes o list]

    BUSCAR --> B1[Filtrar por placa]
    B1 --> B2[Mostrar resultados]
    B2 --> B3[Seleccionar boleto]

    B3 --> TIPO{Tipo de pesaje?}

    TIPO -->|MANUAL (ADMIN/SUPERVISOR)| MANU[Ingreso manual de pesos salida]
    TIPO -->|Lectura futura vía estación| AUTO[Lectura de balanza - futuro §9]

    AUTO --> A1[Leer peso_salida_vehiculo / remolque]
    A1 --> A2{Estable 3 seg? (futuro)}
    A2 -->|No| A1
    A2 -->|Sí| A3[Peso salida por balanza]

    MANU --> M1[Ingresar peso_salida_vehiculo + remolque si aplica]
    M1 --> A3

    A3 --> CALC[POST /api/v1/weighing/close/{boleto}]
    CALC --> PTE[Calcular PTE = PEC + PER]
    PTE --> PTS[Calcular PTS = PSC + PSR]
    PTS --> PNT[Peso neto = PTE - PTS]
    PNT --> DOC[Documento, flete, costo_flete, densidad]
    DOC --> SIGNO{¿Peso neto?}

    SIGNO -->|> 0| INGRESO[INGRESO - Inventario aumenta]
    SIGNO -->|< 0| DESPACHO[DESPACHO - Inventario disminuye]
    SIGNO -->|= 0| CERO[Peso neto = 0 - Sin movimiento]

    INGRESO --> K1[Kardex: id_movimiento=10 valor=+abs(peso_neto)]
    DESPACHO --> K2[Kardex: id_movimiento=60 valor=-abs(peso_neto)]
    CERO --> K3[No registrar en Kardex]

    K1 --> ACT[Boleto → CERRADO, salida_por=usuario]
    K2 --> ACT
    K3 --> ACT

    ACT --> AUD[Registrar en auditoría]
    AUD --> OK[Salida registrada exitosamente]
    OK --> FIN[Operador continúa]
```

### 7.3 Flujo de Anulación

```mermaid
flowchart TD
    INICIO[Operador selecciona Anular] --> TIPO{¿Estado del boleto?}

    TIPO -->|PENDIENTE| PEN[POST /api/v1/weighing/{boleto}/anular\nmotivo obligatorio]
    PEN --> PENOK[estado=ANULADO, sin impacto Kardex]

    TIPO -->|CERRADO o MODIFICADO| CER[POST /api/v1/weighing/{boleto}/anular\nmotivo obligatorio]
    CER --> INV[Registrar movimiento INVERSO en Kardex\n10 <-> 60, conservando historia]
    INV --> CEROK[estado=ANULADO, anulado_por=usuario]

    PENOK --> AUD[Registrar en auditoría]
    CEROK --> AUD
    AUD --> OK[Anulación registrada]

    style INV fill:#FFD700
```

---

## 8. Kardex (Control de Inventario por Peso)

### 8.1 Modelo Numerico de Movimientos

La tabla `kardex` utiliza **identificadores numéricos de movimiento** (`id_movimiento int`) — sin tabla `conceptos_kardex` ni conceptos textuales:

| Rango           | Signo | Valor almacenado     | Código | Significado               |
|-----------------|-------|---------------------|--------|---------------------------|
| **01–49**       | `+`   | Positivo (magnitud) | 10     | **INGRESO POR BASCULA**   |
| **50–99**       | `-`   | Positivo (magnitud) | 60     | **DESPACHO POR BASCULA**  |

- La columna `valor` guarda la **magnitud** (Decimal, positiva); el signo lo aporta `id_movimiento` (10 → +, 60 → −).
- **Rangos 01-49 = positivos** (ingresos), **rangos 50-99 = negativos** (despachos). El rango deja espacio a futuros tipos de movimiento sin cambiar el esquema.
- Al **anular un boleto CERRADO** se registra el movimiento **INVERSO (10↔60)** con la misma magnitud, **conservando la historia** (el registro original no se borra) — ver §6.2.

### 8.2 Lógica del Flujo Kardex

```mermaid
flowchart TD
    E[Entrada + Salida → Peso Neto > 0] -->|id_movimiento=10 valor=+peso| KE[Kardex +stock]
    S[Entrada + Salida → Peso Neto < 0] -->|id_movimiento=60 valor=peso| KS[Kardex -stock]
    CERO[Peso Neto = 0] --> NA[Sin movimiento en Kardex]
    AC[Anular CERRADO/MODIFICADO] -->|Inverso 10 a 60| INV[Cancelar el movimiento original\nconservando historia]
    AP[Ajuste Positivo futuro] -->|rango 01-49| KA+[Kardex +stock]
    AN[Ajuste Negativo futuro] -->|rango 50-99| KA-[Kardex -stock]

    KE -->|Almacén| ALM[Almacén del boleto]
    KS -->|Almacén| ALM
    INV -->|Almacén| ALM
    KA+ -->|Almacén| ALM
    KA- -->|Almacén| ALM

    style KE fill:#90EE90
    style KS fill:#FFB6C1
    style NA fill:#D3D3D3
    style INV fill:#FFD700
    style KA+ fill:#90EE90
    style KA- fill:#FFB6C1
```

### 8.3 Saldo a fecha de corte (calculado)

El saldo **no se persiste** (no existen `saldo_anterior`/`saldo_actual` ni trigger `trg_kardex_saldo`). Se calcula por producto/almacén a una fecha de corte:

```
SALDO FINAL = SALDO INICIAL + Σ(positivos, id_movimiento 01-49) − Σ(negativos, id_movimiento 50-99)
```

aplicado sobre los movimientos con `fecha_kardex <= fecha_corte`. El cálculo lo realiza `WeighingService._registrar_kardex` (y su inverso al anular), nunca un disparador SQL.

### 8.4 Convención de Signo

| Peso Neto              | Clasificación | Kardex                    | Inventario |
|------------------------|----------------|---------------------------|-----------|
| **> 0** (entrada > salida) | **INGRESO**    | `id_movimiento=10`, `valor=+peso` | Aumenta |
| **< 0** (salida > entrada) | **DESPACHO**   | `id_movimiento=60`, `valor=peso`  | Disminuye |
| **= 0**                | Sin movimiento | Ninguno                   | Sin cambios |

---

## 9. Integración Futura: Capa de Abstracción de Hardware (HAL) vía Estación

> ⚠️ **No implementado en el backend actual.** No existe HAL en FastAPI (sin lecturas serial/RS232/Modbus/RTSP, cámaras, semáforos ni barreras). El peso se recibe por **API** (pesaje manual restringido a ADMIN/SUPERVISOR en `_PERMISOS_PESO_MANUAL`, o lectura futura vía estación). Esta sección documenta los **requisitos de producto futuros** para cuando se integre hardware, y debe reajustarse al stack real (p. ej. drivers Python/async vía la estación) antes de implementarse.

### 9.1 Interfaz conceptual (requisito futuro)

La estación (futuro cliente de escritorio o firmware) expondría al backend las lecturas del indicador a través del API; el backend **no** hablaría protocolos directamente. Conceptualmente el indicador ofrecería:

```python
class IndicadorProtocol(Protocol):
    def leer_peso(self) -> float: ...          # peso en KG (base interna)
    def verificar_conexion(self) -> bool: ...
    def es_estable(self) -> bool: ...
    def tarar(self) -> bool: ...
    def zero(self) -> bool: ...
```

Implementaciones previstas (futuras): `IndicadorOptima`, `IndicadorModbusRTU`, `IndicadorToledo`, cámaras RTSP (`foto_entrada_url`/`foto_salida_url`), semáforos y barreras. La selección por protocolo la haría una fábrica (`HalFactory`) según la configuración del dispositivo, resolviendo el dispositivo por empresa/`id_empresa`.

### 9.2 Regla de estabilidad (requisito futuro, REQ-NF-ARQ-004)

Lectura aceptada solo tras **3 segundos ininterrumpidos de peso estable** (`TiempoEstabilidadSegundos = 3`). Reintentos 3× con timeout 5s; si todo falla → **Modo MANUAL** (peso manual + fotos opcionales, solo ADMIN/SUPERVISOR). La validación de unidades KG/LBS persiste como requisito de producto (el indicador jamás debe registrar en una unidad incompatible con la empresa).

### 9.3 Conversión de unidades (constantes vigentes, REQ-NF-ARQ-006)

La unidad interna es **KG**. Constantes de conversión (se usan en frontend/back, sin servicio dedicado):

| Conversión         | Factor     |
|--------------------|------------|
| **1 kg → lbs**     | **2.20462** |
| **1 lb → kg**      | **0.453592** |
| 1 litro → galones  | 0.264172   |
| 1 galón → litros   | 3.78541    |

### 9.4 Inicialización de hardware (requisito futuro)

```mermaid
flowchart TD
    INICIO[Estación inicia] --> HAL[Cargar HAL]
    HAL --> IND[Inicializar Indicadores]
    HAL --> CAM[Inicializar Cámaras]
    HAL --> SEM[Inicializar Semáforos]
    HAL --> BAR[Inicializar Barreras]

    IND --> IND1{Conexión OK?}
    IND1 -->|Sí| IND2[Estado: OPERATIVO]
    IND1 -->|No| IND3[Reintentar 3 veces]
    IND3 --> IND4{Conexión OK?}
    IND4 -->|Sí| IND2
    IND4 -->|No| IND5[Estado: OFFLINE → Modo MANUAL]

    CAM --> CAM1{Conexión RTSP OK?}
    CAM1 -->|Sí| CAM2[Estado: OPERATIVO]
    CAM1 -->|No| CAM3[Estado: OFFLINE → Sin fotos]

    SEM --> SEM1[Estado: APAGADO]
    BAR --> BAR1[Estado: BAJADA]

    IND2 --> OPERACION[Operación Normal]
    IND5 --> OPERACION
    CAM2 --> OPERACION
    CAM3 --> OPERACION
    SEM1 --> OPERACION
    BAR1 --> OPERACION

    OPERACION --> OP1[Leer peso del indicador]
    OP1 --> OP2{Peso estable 3 seg?}
    OP2 -->|Sí| OP3[Peso aceptado]
    OP2 -->|No| OP4[Esperar estabilidad]
    OP4 --> OP1

    OP3 --> OP5{Unidad compatible?}
    OP5 -->|Sí| OP6[Registrar peso]
    OP5 -->|No| OP7[ALERTA: Unidad incompatible]
    OP7 --> OP8[No registrar peso]

    OP6 --> OP9[Enviar lectura al backend /api/v1/weighing/*]
    OP9 --> OP10[Actualizar semáforo: VERDE futuro]
    OP10 --> OP11[Subir barrera futuro]
    OP11 --> OP12[Completar operación]
```

---

## 10. Servicios de Pesaje (MANUAL hoy, AUTOMATICO futuro)

BALANSOFT soporta **un solo servicio `WeighingService`** (FastAPI) que cubre crear/cerrar/anular/update de pendientes/listar. El peso llega por **API**:

- **MANUAL (vigente)**: pesos ingresados por ADMIN/SUPERVISOR (`_PERMISOS_PESO_MANUAL`) con fotos opcionales (`foto_entrada_url`/`foto_salida_url` vía `POST /weighing/{boleto}/imagenes`).
- **AUTOMATICO (futuro)**: lectura vía estación/hardware (ver §9); el flujo también cerraría a través del mismo endpoint `close/{boleto}`.

Los estados `AUTOMATICO`/`MANUAL` que el PRD trató como estados del boleto son **legacy**; el campo vigente es `estado_boleto` (4 valores, §6).

### 10.1 Endpoints de Pesaje (real)

| Método | Ruta                          | Función                              | Permiso mínimo |
|--------|-------------------------------|--------------------------------------|----------------|
| POST   | `/api/v1/weighing/create`     | Crear boleto PENDIENTE               | OPERADOR       |
| POST   | `/api/v1/weighing/close/{boleto}` | Peso salida, cierra a CERRADO + Kardex | OPERADOR    |
| POST   | `/api/v1/weighing/{boleto}/anular` | Anula con motivo (inverso 10↔60 si aplica) | ADMIN/SUPERVISOR |
| POST   | `/api/v1/weighing/update`     | Actualizar pendientes                | ADMIN/SUPERVISOR |
| GET    | `/api/v1/weighing/pendientes` | Lista boletos abiertos               | OPERADOR       |
| GET    | `/api/v1/weighing/list`       | Listado con filtros/estado           | OPERADOR       |
| GET    | `/api/v1/weighing/boleto/{boleto}` | Detalle por número                | OPERADOR       |
| GET    | `/api/v1/weighing/{boleto}/pdf` | Ticket PDF (ReportLab, marca ANULADO) | OPERADOR |
| GET    | `/api/v1/weighing/{boleto}/imagenes*` | Fotos del boleto           | OPERADOR       |

### 10.2 Cálculos de Peso (en `WeighingService`)

| Sigla | Fórmula                                             |
|-------|-----------------------------------------------------|
| **PEC** | peso_entrada_vehiculo (`peso_entrada_vehiculo`)    |
| **PER** | peso_entrada_remolque (`peso_entrada_remolque`)    |
| **PTE** | peso_total_entrada = PEC + PER                     |
| **PSC** | peso_salida_vehiculo (`peso_salida_vehiculo`)      |
| **PSR** | peso_salida_remolque (`peso_salida_remolque`)      |
| **PTS** | peso_total_salida = PSC + PSR                      |
| **PNT** | peso_neto = PTE − PTS                              |
| **PND** | peso_neto_declarado (declarado por el usuario)     |
| **PDF** | peso_diferencia = PNT − PND                        |
| **PDV** | porcentaje_desviacion = (PDF / PND) × 100          |
| **litros** | derivados de densidad y peso                    |

### 10.3 Flujo de Datos Comparativo (modos)

| Aspecto | MANUAL (vigente) | AUTOMATICO (futuro §9) |
| --------- | ----------- | -------- |
| **Lectura Peso** | Input por API (ADMIN/SUPERVISOR) | Estación → indicador |
| **Validación Unidad** | Responsabilidad del operador | Automática vs config empresa (2.20462 / 0.453592) |
| **Estabilidad 3s** | No aplica | Requerida (futuro) |
| **Fotos** | Opcionales (`/imagenes`) | Previstas (chuto/trailer) |
| **Requisito Balanza** | Balanza puede estar offline | Balanza operativa |
| **Campos Extra** | documento, flete, costo_flete, densidad, litros, observaciones | Mínimos |
| **Auditoría** | Peso + timestamp UTC + usuario + IP | Peso + timestamp + usuario |

---

## 11. Seguridad y Autorización

### 11.1 Jerarquía de Roles

```mermaid
flowchart TB
    ADMIN[ADMIN\nFull Access] --> SUPERVISOR[SUPERVISOR\nRead + Anul + Reports]
    SUPERVISOR --> OPERADOR[OPERADOR\nSolo Pesaje]

    classDef admin fill:#ffcdd2,stroke:#c62828;
    classDef super fill:#fff3e0,stroke:#e65100;
    classDef oper fill:#e8f5e9,stroke:#2e7d32;

    class ADMIN admin;
    class SUPERVISOR super;
    class OPERADOR oper;
```

| Role           | Catálogos    | Pesaje   | Kardex   | Consultas | Anular | Usuarios | Config Balanzas |
|----------------|--------------|----------|----------|----------|-------|----------|-----------------|
| **ADMIN**      | [OK] CRUD    | [OK]     | [OK]     | [OK]     | [OK]  | [OK]     | [OK]            |
| **SUPERVISOR** | [NO]         | [OK]     | [OK] Read| [OK]     | [OK]  | [NO]     | [NO]            |
| **OPERADOR**   | [NO]         | [OK]     | [OK] Read| [OK]     | [NO]  | [NO]     | [NO]            |

> **Peso manual y anulación** están restringidos además a ADMIN/SUPERVISOR vía las listas `_PERMISOS_PESO_MANUAL` / `_PERMISOS_ANULACION` en `app/api/dependencies.py`.

### 11.2 Seguridad a Nivel de Endpoint (FastAPI + JWT)

```python
# app/api/dependencies.py — contexto de autorización
async def get_current_empresa(
    credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer()),
    db: AsyncSession = Depends(get_db),
) -> Empresa:
    payload = decodificar_jwt(credentials.credentials)      # HS256 (python-jose)
    id_empresa = uuid.UUID(payload["id_empresa"])           # del JWT, no del body
    rol = payload["rol"]
    return Empresa(id=id_empresa, rol=rol, ...)

# Peso manual y anulación: solo ADMIN/SUPERVISOR
_PERMISOS_PESO_MANUAL = {"ADMIN", "SUPERVISOR"}
_PERMISOS_ANULACION = {"ADMIN", "SUPERVISOR"}

async def require_rol_permiso(
    permiso: set[str],
    current_empresa: Empresa = Depends(get_current_empresa),
) -> None:
    if current_empresa.rol not in permiso:
        raise HTTPException(status_code=403, detail="Rol sin permiso")
```

```python
# app/api/v1/endpoints/pesajes.py — ejemplo de uso
@router.post("/create", status_code=201)
async def crear_boleto(
    payload: BoletoCreate,
    db: AsyncSession = Depends(get_db),
    empresa: Empresa = Depends(get_current_empresa),   # id_empresa resuelto del JWT
) -> BoletoOut:
    return await WeighingService.crear_boleto(db, empresa, payload)

@router.post("/{boleto}/anular")
async def anular_boleto(
    boleto: str,
    body: AnularRequest,
    db: AsyncSession = Depends(get_db),
    empresa: Empresa = Depends(get_current_empresa),
    _: None = Depends(lambda: require_rol_permiso(_PERMISOS_ANULACION)),
) -> BoletoOut:
    return await WeighingService.anular_boleto(db, empresa, boleto, body.motivo)
```

El JWT (creado al login con usuario, rol y `id_empresa`) es el contexto de autorización; los endpoints devuelven datos **siempre filtrados por `id_empresa`** (multi-empresa obligatorio, REQ-NF-ARQ-001).

---

## 12. Arquitectura Frontend (Flutter / BLoC)

### 12.1 Estructura de Pantallas (Modo Kiosk)

```mermaid
flowchart TB
    subgraph Shell["MaterialApp + routes (presentation/routes)"]
        Theme["ThemeController: tema claro/oscuro persistente\n(SharedPreferences por dispositivo) - REQ-NF-OPE-002"]
        Fullscreen["Producción: fullscreen sin bordes\n(REQ-NF-OPE-001)"]
    end

    subgraph Screens["presentation/screens"]
        AuthScreens["auth/\nLoginScreen, RegisterScreen"]
        Dash["dashboard/\nDashboardScreen"]
        Weigh["weighing/\nWeighingScreen, EntradaScreen,\nSalidaScreen, BuscarScreen, AnularScreen"]
        Cat["catalog(s)/\nCatalogPlantilla + CRUD por catálogo"]
        Rep["reports/\nReportesScreen, ExportScreen"]
        Sett["settings/\nSettingsScreen"]
    end

    subgraph Bloc["presentation/providers/bloc"]
        AB[AuthBloc]
        WB[WeighingBloc]
        CB[CatalogBloc / CatalogCrudBloc]
        LB[LicenseBloc]
        SB[SyncBloc]
    end

    Common["core/theme + core/widgets\n(tokens de tema, widgets comunes)"]

    Shell --> Screens
    AuthScreens --> Dash
    Dash --> Weigh
    Dash --> Cat
    Dash --> Rep
    Dash --> Sett
    Weigh --> AB
    Weigh --> WB
    Cat --> CB
    Dash --> LB
    Dash --> SB
    Screens --> Common
```

### 12.2 Configuración de Kiosk y Tema

```dart
// main.dart (resumen) - router + tema persistente
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final injection = InjectionContainer(); // injection.dart: repos + blocs
  runApp(BalansoftApp(injection: injection));
}

// Tema claro/oscuro persistente (ThemeController, SharedPreferences)
class BalansoftApp extends StatelessWidget {
  final InjectionContainer injection;
  const BalansoftApp({super.key, required this.injection});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: injection.themeController, // REQ-NF-OPE-002
      child: MaterialApp(
        theme: AppTheme.light, darkTheme: AppTheme.dark,
        themeMode: injection.themeController.mode, // System/Light/Dark
        home: const SplashScreen(redirectTo: AppRoutes.LOGIN),
      ),
    );
  }
}
```

> Blocs y repositorios se inyectan desde `injection.dart`; las pantallas consumen el estado vía `BlocBuilder`/`BlocListener`. En producción la app corre en **kiosk** (pantalla completa sin bordes) y offline-first (sqflite + cola de sync).

### 12.3 Diseño UI del Dashboard

```mermaid
flowchart TB
    Header["BALANSOFT | Catálogos | Gestión | Consultar | Mantenimiento"]
    UserBar["Operador: Juan Pérez | Rol: OPERADOR | Empresa: Mi Empresa | [ONLINE] (5 pendientes) | Estado sync"]

    subgraph KPIs["KPI Cards"]
        KPI1["Pesajes Hoy: 47"]
        KPI2["Pendientes: 5"]
        KPI3["En Plataforma: 1"]
        KPI4["Cola de sync: 3"]
    end

    subgraph Estado["Estado del Sistema"]
        Sync["SYNC: [OK]/[pendiente: n]\n(datos locales ok)"]
        Lic["LICENCIA: [DEMO/MONOPUESTA/CENTRAL]\n(SGLB)"]
    end

    LastOp["Último: ABC-123 → 12,450 kg neto - hace 2 min"]

    Header --> UserBar
    UserBar --> KPIs
    KPIs --> Estado
    Estado --> LastOp
```

> La pantalla de hardware (indicador/cámaras/semáforo/barrera) se incorporará al dashboard **cuando exista la integración vía estación** (§9); hoy el peso se digita en la pantalla de pesaje (MANUAL, ADMIN/SUPERVISOR).

### 12.4 Pesaje Screen (Pantalla Principal de Pesaje)

```text
┌─────────────────────────────────────────────────────────────────────┐
│  BALANSOFT   [Catálogos] [Gestión] [Consultar] [Mantenimiento]      │
├─────────────────────────────────────────────────────────────────────┤
│  [← Volver]            GESTIÓN DE PESAJE                            │
├─────────────────────────────────────────────────────────────────────┤
│  Boleto: TA-00000125    Estado: PENDIENTE    Fecha: 11/08/2026      │
├──────────────────────────┬──────────────────────────────────────────┤
│  PLACA                  │  PESO ENTRADA (PEC)                       │
│  [ ABC-123       ]      │  peso_entrada_vehiculo: [___] kg          │
│                          │  peso_entrada_remolque (PER): [___] kg   │
│  CONDUCTOR              │  PESO SALIDA (PSC)                        │
│  [ Juan Pérez     ▼]    │  peso_salida_vehiculo: [___] kg           │
│  TRANSPORTE             │  peso_salida_remolque (PSR): [___] kg     │
│  [ Transportes X  ▼]    │                                          │
│  CLIENTE/PROVEEDOR      │  PTE: ______ PTS: ______                 │
│  [ Cementos SA    ▼]    │  NETO (PTE-PTS): ______                   │
│  PRODUCTO               │  DECLARADO: ______  DIF: ____ %: ____    │
│  [ Cemento       ▼]     │  DENSIDAD: ______ LITROS: ______          │
│  ALMACÉN                │                                          │
│  [ Principal     ▼]     │  FOTO ENTRADA: [Adjuntar]   (opcional)   │
│                         │  FOTO SALIDA: [Adjuntar]     (opcional)   │
├─────────────────────────┴──────────────────────────────────────────┤
│  DOCUMENTO: [________]   FLETE: [_____]   COSTO FLETE: [_____]     │
├─────────────────────────────────────────────────────────────────────┤
│  [ > Entrada ]  [ > Salida ]  [ [Search] Buscar ]  [ [X] Anular ]   │
│  [ [Print] PDF ]  [ [Exit] Salir ]                                  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 13. Reglas de Estabilidad y Validación de Peso (requisito futuro, REQ-NF-ARQ-004)

> Estas reglas aplican a la **lectura vía balanza**, que es **integración futura** (§9). Hoy no hay lectura automática en el backend; se documentan como requisito de producto para la estación de hardware. Los timestamps deben persistirse SIEMPRE en **UTC** (conversión a TZ local solo en la capa de presentación/Flutter — REQ-NF-ARQ-010..012).

### 13.1 Regla de estabilidad (3 segundos)

```python
TIEMPO_ESTABILIDAD_SEGUNDOS = 3

class EstabilidadService:
    """(Futuro: estación/HAL). Regla: 3 s ininterrumpidos de peso estable."""

    def __init__(self) -> None:
        self._tiempo_estable_inicio: datetime | None = None
        self._peso_estable: float | None = None

    def evaluar(self, peso_actual: float, es_estable: bool) -> StabilityResult:
        if not es_estable:
            self._tiempo_estable_inicio = None
            self._peso_estable = None
            return StabilityResult.waiting(TIEMPO_ESTABILIDAD_SEGUNDOS)

        ahora = datetime.now(timezone.utc)  # SIEMPRE UTC al persistir
        if self._tiempo_estable_inicio is None:
            self._tiempo_estable_inicio = ahora
            self._peso_estable = peso_actual
            return StabilityResult.stabilizing(TIEMPO_ESTABILIDAD_SEGUNDOS)

        transcurrido = (ahora - self._tiempo_estable_inicio).total_seconds()
        if transcurrido >= TIEMPO_ESTABILIDAD_SEGUNDOS:
            peso = self._peso_estable
            self._tiempo_estable_inicio = None
            self._peso_estable = None
            return StabilityResult.accepted(float(peso), transcurrido)
        return StabilityResult.stabilizing(TIEMPO_ESTABILIDAD_SEGUNDOS - transcurrido)
```

### 13.2 Validación de Compatibilidad de Unidades

```python
def validar_lectura(sistema: str, peso_lector: float, unidad_lector: str) -> ValidationResult:
    """sistema: 'METRICO' | 'IMPERIAL' (config de la empresa). (Futuro: estación/HAL)."""
    if sistema == "METRICO" and unidad_lector == "LBS":
        return ValidationResult.invalid(
            "ALERTA: Indicador en LBS pero sistema es Métrico (KG)",
            peso_lector, unidad_lector)
    if sistema == "IMPERIAL" and unidad_lector == "KG":
        return ValidationResult.invalid(
            "ALERTA: Indicador en KG pero sistema es Imperial (LBS)",
            peso_lector, unidad_lector)
    return ValidationResult.valid()
```

> Constantes de conversión vigentes (KG base interna): **1 kg = 2.20462 lbs** ⇔ **1 lb = 0.453592 kg** — ver §9.3 (REQ-NF-ARQ-006).

---

## 14. Plan de Contingencia para Balanzas

### 14.1 Tipos de Balanzas y Redundancia

```mermaid
flowchart LR
    subgraph Server["API BALANSOFT (FastAPI)"]
        W[WeighingService]
        BAL[Tabla balanzas por empresa]
        W --> BAL
    end

    subgraph Scales[Balanzas Configuradas (entidad `balanzas`)]
        B1[Balanza ENTRADA 1\nTipo: ENTRADA]
        B2[Balanza ENTRADA 2\nTipo: ENTRADA]
        B3[Balanza SALIDA 1\nTipo: SALIDA]
        B4[Balanza SALIDA 2\nTipo: SALIDA]
    end

    BAL --> B1
    BAL --> B2
    BAL --> B3
    BAL --> B4
```

> La comunicación física (serial/Modbus) con las balanzas es **integración futura** vía estación (§9); la entidad `balanzas` ya existe en el esquema y es configurable por empresa/`id_empresa`.

### 14.2 Escenarios de Fallo

| Tipo de Falla    | Causa                           | Solución                                          |
|------------------|---------------------------------|----------------------------------------------------|
| **Físico**       | Celdas dañadas, mantenimiento   | Mover camión a otra balanza operativa del mismo tipo |
| **Comunicación** | No hay lectura de balanza       | **Modo MANUAL** (ingreso manual de peso, ADMIN/SUPERVISOR) |

### 14.3 Lógica de Failover Automático

```mermaid
flowchart TD
    A[Balanza ENTRADA 1 en mantenimiento] --> B{¿Existe Balanza ENTRADA 2 operativa?}
    B -->|Sí| C[Mover camión a ENTRADA 2]
    B -->|No| D[Modo MANUAL]
    C --> E[Operar en ENTRADA 2]

    F[No se recibe lectura del indicador] --> G[Reintentar 3 veces, timeout 5s cada una]
    G --> H{¿Respuesta?}
    H -->|Sí| I[Leer peso normal]
    H -->|No| J[Modo MANUAL]
```

### 14.4 Comportamiento del Modo MANUAL

1. Un ADMIN/SUPERVISOR registra el peso manualmente (permiso `_PERMISOS_PESO_MANUAL`)
2. Ingresa `peso_entrada_vehiculo`/`peso_entrada_remolque` (y salida) vía API
3. Las fotos son **opcionales** (`foto_entrada_url`/`foto_salida_url` vía `/imagenes`)
4. La auditoría registra quién, desde qué IP y cuándo ingresó el peso
5. El sistema opera normalmente (calcula neto, registra Kardex 10/60, puede cerrar/anular)

---

## 15. Gestión de Licencias (BALANSOFT-LM / SGLB)

```mermaid
flowchart TD
    B[API inicia / login] --> A{Valida licencia en BALANSOFT-LM}
    A -->|Licencia válida| C[Sistema Opera Normalmente]
    A -->|Sin licencia / Expirada| D[Sistema Bloqueado / Modo Demo]

    C --> E[Operación Normal]
    D --> F[Funcionalidad Limitada\nSolo consulta, sin pesaje]

    style C fill:#90EE90
    style D fill:#FFB6C1
```

- **`LicenseClient`/`LicenseService`** en `backend/app/core/license_client.py` + `services/license_service.py`: cliente HTTP contra **BALANSOFT-LM (SGLB)**.
- Validación en endpoints `/api/v1/auth/register` y `/api/v1/auth/validate-license`.
- **Ed25519 anti-fake-server**: las licencias se firman con una clave pública (`.env`: `LICENSE_PUBLIC_KEY`); solo el servidor real de licencias puede firmar respuestas válidas.
- **Caché** de la licencia + período de gracia para modo offline.
- **Tiers**: `DEMO`, `MONOPUESTA`, `CENTRAL` con límites configurados (`DEMO_MAX_RECORDS`, etc.).
- Configuración por `.env`: `LICENSE_API_URL`, `LICENSE_ADMIN_URL`, `LICENSE_PUBLIC_KEY`, `LICENSE_PRODUCT_CODE`.

---

## 16. Zona Horaria y Localización

| Capa         | Almacenamiento                   | Visualización                                   |
|-------------|----------------------------------|-------------------------------------------------|
| PostgreSQL  | `TIMESTAMPTZ` UTC                 | `AT TIME ZONE 'UTC' AT TIME ZONE 'America/Caracas'` |
| Backend (Python/FastAPI) | `datetime.now(UTC)` (REQ-NF-ARQ-010) | Pydantic v2 entrega ISO 8601 UTC al cliente |
| Frontend (Flutter) | UTC desde el servicio (REQ-NF-ARQ-011) | Conversión a TZ local SOLO aquí (REQ-NF-ARQ-012) |

```sql
-- PostgreSQL: hora local desde UTC
SELECT boleto_fecha AT TIME ZONE 'UTC' AT TIME ZONE 'America/Caracas' AS fecha_local
FROM boletos_pesaje;
```

> Regla vigente (REQ-NF-ARQ-010/011/012): timestamps persistidos **siempre en UTC**, sin sufijo `Utc` en DTOs/entidades; la conversión a zona horaria local ocurre **únicamente** en la capa de presentación (Flutter).

### 16.1 Formatos Configurables por Empresa

| Parámetro           | Default         | Opciones                            |
|---------------------|-----------------|------------------------------------|
| `sistema_unidades`  | METRICO         | METRICO, IMPERIAL                  |
| `unidad_peso`       | KG              | KG, LBS                            |
| `unidad_volumen`    | LITROS          | LITROS, GALONES                    |
| `formato_numerico`  | #,##0.00        | Custom                             |
| `formato_fecha`     | DD/MM/YYYY      | DD/MM/YYYY, MM/DD/YYYY, YYYY-MM-DD |
| `formato_hora`      | HH:MM           | HH:MM, HH:MM:SS                    |
| `separador_decimal` | ,               | , or .                             |
| `separador_miles`   | .               | . or ,                             |
| `timezone`          | America/Caracas | IANA TZ database                   |

> Estos parámetros se resuelven por **empresa** (tabla `empresas`: `sistema_unidades`, `unidad_peso`, `timezone`) y se aplican en la capa de presentación.

### 16.2 Conversiones

```dart
// Flutter — constantes de conversión (base interna KG). Ver §9.3.
const double kgToLbs = 2.20462;
const double litrosToGalones = 0.264172;
const double lbsToKg = 0.453592;
const double galonesToLitros = 3.78541;

double kgToLbs(double kg) => double.parse((kg * kgToLbs).toStringAsFixed(2));
double lbsToKg(double lbs) => double.parse((lbs * lbsToKg).toStringAsFixed(2));
```

---

## 17. Auditoría y Registro

### 17.1 Trazabilidad de Auditoría (Cada Cambio Relevante)

```mermaid
flowchart LR
    Req["Petición HTTP /api/v1/*\n(JWT Bearer)"] --> MW["AuditMiddleware (FastAPI)\napp/core/audit.py"]
    MW --> SVC["Acción de servicio\n(crear/cerrar/anular/update/catálogos)"]
    SVC --> Insert["INSERT en tabla auditoria\n(repositorio de auditoría)"]
    Insert --> Auditoria["AUDITORIA\nid_auditoria UUID, id_empresa,\naccion, entidad, entidad_id,\ndetalle JSONB, ip, created_at"]
    Insert --> Usuario["id_usuario (del JWT)"]
    Insert --> IP["ip"]
    Insert --> TS["created_at (UTC)"]
    MW --> Logs["logs_sistema\n(INFO/WARN/ERROR)"]
```

| Acción              | Quién       | Qué                                 |
|---------------------|-------------|-------------------------------------|
| `RegistrarEntrada`  | OPERADOR    | Crea PENDIENTE (`create`)           |
| `RegistrarSalida`   | OPERADOR    | Cierra → CERRADO + Kardex 10/60     |
| `Actualizar`        | ADMIN/SUPERVISOR | CERRADO → MODIFICADO             |
| `Anular`            | ADMIN/SUPERVISOR | ANULADO + inverso Kardex si aplica |
| `CRUD Catálogos`    | ADMIN/SUPERVISOR | Crear/editar catálogos            |

> La tabla `auditoria` guarda `accion`, `entidad`, `entidad_id`, `detalle` (**JSONB**), `ip` y `created_at` (UTC). No existe `auditoria_boletos` ni `user_agent`/`campos_modificados` como columnas: el detalle de cambio viaja en el JSONB.

### 17.2 Logs del Sistema (`logs_sistema`)

| Level     | Eventos                                                     |
|-----------|-------------------------------------------------------------|
| **INFO**  | Login, boleto creado/cerrado, endpoints de catálogo        |
| **WARN**  | Peso manual permitido, sync pendiente, reintento de licencia |
| **ERROR** | Violación de constraint, licencia inválida, fallo de integración |

---

## 18. Arquitectura de Despliegue

### 18.1 Servidor (Producción, Linux + systemd)

```mermaid
flowchart TB
    subgraph Srv["Servidor Linux"]
        UWI["uvicorn app.main:app --port 8000\n(backend FastAPI)"]
        UNIT["balansoft-ws.service (systemd)\nbackend/deploy/balansoft-ws.service\nReinicio automático en fallo"]
        UWI --> UNIT
    end

    subgraph Client["Clientes Flutter"]
        KIOSK["Frontend Flutter (kiosk)\nweb/desktop/mobile\noffline-first sqflite"]
    end

    subgraph DB["PostgreSQL 15+"]
        PGHOST["balansoft_ws (multi-empresa)\n+ balansoft_ws_test para tests"]
    end

    subgraph LM["BALANSOFT-LM (SGLB)"]
        SW["Licencias Ed25519"]
    end

    KIOSK --"/api/v1/* (JWT)"--> UWI
    UWI --> PGHOST
    UWI --"validación de licencia"--> SW
```

### 18.2 Servicio systemd / Arranque Automático (Producción)

El backend se instala con **uv** (`uv sync`) y corre como servicio **systemd** (unidad `backend/deploy/balansoft-ws.service`). La BD se prepara/actualiza con `backend/scripts/setup_db.sh` (aplica `schema.sql` + `migrations/*.sql`).

```ini
# backend/deploy/balansoft-ws.service (resumen)
[Unit]
Description=API Estación de Pesaje BALANSOFT
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=/opt/balansoft-ws/backend
ExecStart=/opt/balansoft-ws/backend/.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10
EnvironmentFile=/opt/balansoft-ws/backend/.env

[Install]
WantedBy=multi-user.target
```

```bash
# Secuencia de instalación (resumen)
uv sync                                   # backend/ — instala deps en .venv
./scripts/setup_db.sh                     # backend/ — crea/actualiza BD (schema.sql + migrations)
sudo systemctl enable --now balansoft-ws  # backend/deploy/balansoft-ws.service
```

> El frontend Flutter se compila para el/los target(s) requeridos (web/desktop/mobile) y consume la misma API. No hay componente de escritorio window y el deploy Linux/JAR mencionado en versiones previas no aplica al stack actual.

---

## 19. Migraciones de Base de Datos (schema.sql + SQL versionado)

El esquema vive en **`backend/schema.sql`** (esquema final **idempotente**, `CREATE TABLE IF NOT EXISTS`, ~21 tablas) y la historia en **`backend/migrations/*.sql`** versionadas hacia adelante (**sin Alembic**, sin EF). La instalación/actualización la orquesta `backend/scripts/setup_db.sh`.

```text
backend/
├── schema.sql            # Esquema final idempotente: empresas, usuarios, catalogo (marcas,
│                         #   modelos_camion, camiones, remolques, transportes, conductores,
│                         #   terceros, productos, almacenes, balanzas), boletos_pesaje,
│                         #   imagenes_pesaje, kardex, sync_queue, sync_logs, auditoria,
│                         #   logs_sistema, configuraciones, parametros_sistema
└── migrations/
    ├── 001_remolques_y_fotos.sql       # remolques + foto_entrada_url/foto_salida_url
    ├── 002_spec_arquitectura.sql       # Ajustes de arquitectura (multi-empresa/kardex)
    └── 003_reglas_negocio_model.md.sql # Reglas de negocio (estados, kardex 10/60)
```

### 19.1 Kardex: sin trigger ni saldo persistido

No existe **ni trigger T-SQL `trg_kardex_saldo` ni columnas `saldo_anterior`/`saldo_actual`** en la tabla `kardex`. El saldo se **calcula** a fecha de corte (positivos − negativos por producto/almacén, rangos 01-49 / 50-99, §8.3) dentro de `WeighingService._registrar_kardex`. No hay tabla `conceptos_kardex`.

> Regla en repositorio: **nunca crear/modificar tablas a mano** en la base de datos. Todo cambio de esquema entra como migración SQL versionada en `backend/migrations/` y se refleja en `schema.sql`. El esquema de tests es un PostgreSQL real (`balansoft_ws_test`).

---

## 20. Operaciones de los servicios

La UI **Flutter consume la API REST** (`/api/v1/*`, JWT Bearer) vía los repositorios remotos de `frontend/lib/data`; en modo offline encola operaciones en `sync_queue` (tabla `sync_queue` + `SyncService`). Ver PRD §10 para la firma de los métodos públicos de cada servicio:

| Servicio                  | Responsabilidad principal                          |
|---------------------------|----------------------------------------------------|
| `AuthService` (endpoints) | register/login/validate-license/refresh-token/logout |
| `WeighingService`         | create/close/anular/update/pendientes/list + cálculos (PTE/PTS/PNT/PND/PDF/PDV) + kardex |
| `CatalogService`          | CRUD genérico de catálogos (marcas, modelos_camion, camiones, remolques, transportes, conductores, terceros, productos, almacenes, balanzas) |
| `ReportService`           | Reportes daily/monthly/vehicle + export Excel     |
| `SyncService`             | Cola offline push/status/pull                      |
| `TicketService`           | Tickets PDF con ReportLab (marca de agua ANULADO)  |
| `LicenseService`          | Validación contra BALANSOFT-LM (SGLB, Ed25519)     |

---

## 21. Estrategia de Pruebas

| Capa             | Herramienta                   | BD / Origen                |
|------------------|-------------------------------|----------------------------|
| **Backend (unit/integration)** | **pytest**               | PostgreSQL real `balansoft_ws_test` |
| **Lint / tipos** | ruff + mypy                    | `ruff check`, `mypy tests/` |
| **Frontend**     | **flutter_test**               | —                          |
| **Análisis estático Flutter** | flutter analyze         | —                          |
| **Modo kiosk / tema** | Smoke tests + Unit tests (REQ-NF-OPE-001/002) | flutter_test |

```bash
# Backend (estación) — desde backend/
uv sync
uv run pytest -q                     # todos los tests (PostgreSQL real)
uv run ruff check app tests          # lint
uv run mypy tests/                   # tipos

# Frontend — desde frontend/
flutter analyze                      # análisis estático
flutter test                         # tests de widgets/unit
```

> Estos comandos se ejecutan sobre el código real (`backend/` y `frontend/` de este repositorio). No son valores de referencia de un stack histórico.

---

## 22. Configuración (`.env`)

### 22.1 Variables vigentes (ver `backend/.env.example`)

```ini
# --- Entorno ---
APP_ENV=development|production
DEBUG_MODE=false
LOG_LEVEL=INFO
LOG_FILE=/var/log/balansoft-ws/app.log

# --- Conexión a Base de Datos (PostgreSQL, separada del LM) ---
DATABASE_URL=postgresql+asyncpg://USUARIO:PASSWORD@localhost:5432/balansoft_ws
DATABASE_URL_SYNC=postgresql+psycopg2://USUARIO:PASSWORD@localhost:5432/balansoft_ws

# --- LM Local (License Manager SGLB / BALANSOFT-LM) ---
LICENSE_API_URL=http://127.0.0.1:8080/api/v1
LICENSE_ADMIN_URL=http://127.0.0.1:5000
LICENSE_PUBLIC_KEY='-----BEGIN PUBLIC KEY-----...'   # Ed25519, una línea
LICENSE_PRODUCT_CODE=BWS

# --- API de Balansoft-WS ---
API_HOST=0.0.0.0
API_PORT=8000
API_RELOAD=false
API_WORKERS=4

# --- Seguridad interna (JWT de la app) ---
SECRET_KEY=CAMBIAR_CON: openssl rand -hex 32          # aleatoria, >=32 bytes
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=7

# --- CORS (orígenes del frontend Flutter Web) ---
CORS_ORIGINS=["https://app.balansoft.example.com"]

# --- Sincronización offline ---
SYNC_INTERVAL_MINUTES=2
MAX_OFFLINE_DAYS=30
MAX_SYNC_RETRIES=3

# --- Límites de licencia ---
DEMO_MAX_RECORDS=10
MONOPUESTA_MAX_USERS=1
CENTRAL_MAX_USERS=10
```

> No existe `SERVER_PORT=7000` ni perfiles simulados de hardware en la implementación actual (estarían asociados a una estación físico—integración futura §9). El `.env` local contiene credenciales de desarrollo reales: **rotar** `SECRET_KEY` y passwords en producción (no exponer `SECRET_KEY` ni claves).

---

## 23. Secuencias Clave

### 23.1 Ciclo Completo de Pesaje (Diagrama de Secuencia)

```mermaid
sequenceDiagram
    participant Op as Operador
    participant UI as Flutter Screen
    participant WB as WeighingBloc
    participant API as FastAPI /api/v1/weighing
    participant WS as WeighingService
    participant KS as Kardex (tabla)
    participant AUD as AuditMiddleware
    participant DB as PostgreSQL

    Op->>UI: Tap "Entrada" (peso manual ADMIN/SUPERVISOR)
    UI->>WB: CrearBoleto(payload)
    WB->>API: POST /weighing/create (JWT)
    API->>WS: crear_boleto(id_empresa, payload)
    WS->>WS: Calcular PTE = PEC + PER
    WS->>WS: Generar numero_boleto TA-00000001 (unique)
    WS->>DB: INSERT boletos_pesaje (PENDIENTE)
    WS->>AUD: RegistrarAuditoria(create, detalle JSONB)
    AUD-->>WS: OK
    WS-->>API: BoletoOut {numero_boleto, estado=PENDIENTE}
    API-->>WB: 201 Created
    WB-->>UI: Estado creado #TA-00000001

    Note over Op,DB: ... tiempo después ...

    Op->>UI: Tap "Salida" + seleccionar boleto
    UI->>WB: CerrarBoleto(numero)
    WB->>API: POST /weighing/close/{boleto} (JWT)
    API->>WS: cerrar_boleto(id_empresa, numero)
    WS->>WS: PTS = PSC + PSR; PNT = PTE - PTS
    alt PNT > 0
        WS->>KS: INSERT kardex id_movimiento=10 valor=+PNT (INGRESO)
    else PNT < 0
        WS->>KS: INSERT kardex id_movimiento=60 valor=abs(PNT) (DESPACHO)
    else PNT = 0
        WS->>KS: Sin movimiento
    end
    WS->>DB: UPDATE boletos_pesaje estado=CERRADO, salida_por=user
    WS->>AUD: RegistrarAuditoria(close, detalle JSONB)
    AUD-->>WS: OK
    WS-->>API: BoletoOut {estado=CERRADO, peso_neto=PNT}
    API-->>WB: OK
    WB-->>UI: Boleto CERRADO, neto=PNT kg
```

### 23.2 Anulación de Boleto CERRADO

```mermaid
sequenceDiagram
    participant Sup as ADMIN/SUPERVISOR
    participant UI as Flutter Screen
    participant API as FastAPI /api/v1/weighing
    participant WS as WeighingService
    participant DEP as dependencies (_PERMISOS_ANULACION)
    participant DB as PostgreSQL

    Sup->>UI: Tap "Anular" en boleto CERRADO (motivo)
    UI->>API: POST /weighing/{boleto}/anular (JWT)
    API->>DEP: require_rol_permiso(ADMIN/SUPERVISOR)
    DEP-->>API: OK
    API->>WS: anular_boleto(id_empresa, numero, motivo)
    WS->>DB: SELECT boleto + movimientos kardex asociados
    WS->>DB: INSERT kardex INVERSO (10<->60) mismo valor
    WS->>DB: UPDATE boletos_pesaje estado=ANULADO, motivo_anulacion=?, anulado_por=?
    WS->>API: BoletoOut {estado=ANULADO}
    API-->>UI: OK
    UI-->>Sup: "Boleto anulado, inverso registrado en Kardex"
```

---

## 24. Flujo de Desarrollo

### 24.1 Desarrollo Local (sobre el código real)

```bash
# 1. Preparar la BD PostgreSQL (crea/actualiza schema.sql + migrations)
./backend/scripts/setup_db.sh
# 2. Instalar deps e ir al entorno del backend
cd backend && uv sync
# 3. Levantar la API
uv run uvicorn app.main:app --port 8000
# 4. Frontend Flutter (development: ventana normal; producción: kiosk)
cd frontend && flutter run
```

### 24.2 Agregar Nueva Entidad

1. Añadir la tabla/columnas en `backend/migrations/*.sql` (nueva migración) y reflejarlas en `backend/schema.sql`.
2. Crear el modelo SQLAlchemy en `backend/app/models/` y el DTO Pydantic v2 en `backend/app/schemas/` (con `id_empresa`, timestamps UTC).
3. Exponer el CRUD en `backend/app/api/v1/endpoints/` usando `CatalogService` (CRUD genérico) o un endpoint propio.
4. Proteger el endpoint con `get_current_empresa` (id_empresa del JWT) y el rol requerido (`_PERMISOS_*`).
5. Agregar el repositorio/datasource + entidad/usecase/screen BloC en `frontend/lib/`.
6. Registrar dependencias en `frontend/lib/injection.dart`.
7. Escribir tests: `uv run pytest -q` (backend) y `flutter test` (frontend).

### 24.3 Integrar Hardware (cuando aplique, §9)

1. Documentar el protocolo y validar la lectura contra la estación prevista.
2. Integrar la lectura vía API (endpoints `weighing/*`) — el backend **no** habla protocolos directamente.
3. Aplicar las reglas de §9/§13 (estabilidad 3 s, unidades KG/LBS).
4. Probar primero con valores simulados (peso manual permitido a ADMIN/SUPERVISOR) y luego con la estación real.
5. No reintroducir perfil `production/simulated` de hardware en `.env` hasta definir la estación.

---

## 25. Validación de Diagramas Mermaid

Todos los diagramas usan sintaxis estándar de Mermaid. Para validar:

```bash
# Opción 1: VS Code + extensión Mermaid Preview
# Opción 2: Mermaid CLI
npm install -g @mermaid-js/mermaid-cli
mmdc -i docs/ARCH.md -o docs/architecture-diagrams.pdf
# Opción 3: editor en línea en mermaid.live
```

| Diagrama               | Tipo Mermaid      |
|------------------------|-------------------|
| Arquitectura de Componentes | `flowchart TB`    |
| Relación de Entidades      | `erDiagram`       |
| Máquina de Estados         | `stateDiagram-v2` |
| Flujos de Trabajo          | `flowchart TD/LR` |
| Diagrama de Secuencia      | `sequenceDiagram` |

---

## 26. Apéndice: Glosario

| Término         | Definición                                                                   |
|-----------------|------------------------------------------------------------------------------|
| **Boleto**      | Ticket de pesaje (`boletos_pesaje`; entrada + salida = un ciclo)            |
| **Chuto**       | Unidad tractora (cabina) del camión                                         |
| **Trailer**     | Remolque principal acoplado al chuto                                        |
| **Remolque**    | Remolque adicional (tabla `remolques`; campo `remolque` bool)               |
| **Peso Neto**   | PTE − PTS (positivo = ingreso, negativo = despacho)                         |
| **Kardex**      | Libro mayor de inventario inmutable por peso; `id_movimiento` 10 (INGRESO) / 60 (DESPACHO) |
| **HAL**         | Capa de Abstracción de Hardware — integración futura vía estación (§9)      |
| **Empresa**     | Unidad de negocio/tenancy: aislamiento de datos vía `id_empresa` (UUID, del JWT) |
| **Modo Kiosk**  | Frontend Flutter en pantalla completa, sin bordes (REQ-NF-OPE-001)          |
| **Modo MANUAL** | Modo de contingencia: peso ingresado por API, restringido a ADMIN/SUPERVISOR (`_PERMISOS_PESO_MANUAL`) |

---

*Generado a partir de PRD v2.0 — Sistema de Gestión de Estación de Pesaje Industrial BALANSOFT (alineado al stack real FastAPI + Flutter + PostgreSQL)*

---

## Historial de cambios

| Versión | Fecha       | Cambios                                                                       |
|---------|-------------|-------------------------------------------------------------------------------|
| 2.0     | 2026-09-08  | Re-alineación a la implementación real: FastAPI + Flutter + PostgreSQL, API REST JWT `/api/v1/*`, multi-empresa `id_empresa` (UUID) desde el JWT, 4 estados del boleto + normalización legacy, kardex numérico 10/60 con saldo a fecha de corte e inverso al anular, esquema `schema.sql` + `migrations/*.sql`, despliegue uvicorn/systemd. HAL y reglas de estabilidad/unidades pasan a "integración futura vía estación". |
| 2.4     | 2026-08-20  | Alineación con PRD v2.3 y AGENTS v1.1 (histórico, stack .NET/WinForms ya no vigente). |
| 2.3     | 2026-08-20  | Re-migración de stack a .NET Framework 4.8 + WinForms + EF6 + SQL Server Express 2022 (histórico, no vigente). |
| 2.2     | 2026-08-19  | Versión previa: Spring Boot 3.x + Vaadin 24+ (histórico, no vigente). |

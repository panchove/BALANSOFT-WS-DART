# Diseño de Software — Gestión de Pesajes BALANSOFT-WS

**Versión:** 0.4.2-dev.56  
**Fecha:** 2026-10-19  
**Norma:** ISO/IEC 1016  
**Fuente:** Spec 001-gestion-pesajes / SRS BALANSOFT-WS  
**Autor:** Lead Architect  

## 1. Descomposición de Arquitectura

### 1.1 Capa de Servicios (FastAPI / Python)

| Servicio          | Responsabilidad                                                                                   | Dependencias                                                           |
|-------------------|---------------------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| `WeighingService` | Lógica completa de pesaje: crear, cerrar, anular, modificar, cálculos PTE-PTS-PNT-PDF-PDV, kardex | `app/models/`, `app/core/db_engine.py`, `app/core/seguridad_matrix.py` |
| `AuthService`     | Autenticación JWT, validación licencia Ed25519, login local/offline                               | `app/core/security.py`, `app/api/v1/endpoints/licencias.py`            |
| `CatalogService`  | CRUD catálogos con filtrado `id_empresa`                                                          | `app/models/catalogos.py`, `app/core/db_engine.py`                     |

### 1.2 Modelos de Datos (SQLAlchemy 2.0 async)

| Entidad            | Atributos Clave                                                                         | Restricciones                                                                                                    | Relaciones                                                      |
|--------------------|-----------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------|
| `BoletoPesaje`     | `boleto PK`, `id_empresa FK`, `estado_boleto`, `peso_neto`, `fecha_hora_entrada/salida` | `estado_boleto` ∈ `['PENDIENTE', 'CERRADO', 'MODIFICADO', 'ANULADO']`<br>`id_empresa` obligatorio en ALL queries | N:1 a `Empresas`, N:1 a `Balanzas`, N:1 a `Productos/Almacenes` |
| `Kardex`           | `id_kardex PK`, `id_empresa FK`, `id_movimiento` (10/60), `valor`, `fecha_kardex`       | `id_movimiento` ∈ `[10, 60]`;<br>signo según movimiento (10=+, 60=-)<br>`id_empresa` obligatorio                 | N:1 a `Empresas`, N:1 a `Boletos` (opcional)                    |
| `SeriesNumeracion` | `id_serie PK`, `id_empresa FK`, `nombre`, `prefijo`, `siguiente`, `digitos`, `activa`   | `siguiente` avanza con `FOR UPDATE`, sin reutilización<br>`id_empresa` obligatorio                               | N:1 a `Empresas`                                                |

### 1.3 Interfaces de API (Contratos Pydantic)

#### WeighingCreate (entrada)

```python
class WeighingCreate(BaseModel):
    id_vehiculo: str = Field(..., min_length=1, max_length=20)
    remolque: bool = False
    id_remolque: UUID | None = None
    id_transporte: UUID | None = None
    id_conductor: str | None = None  # cédula DNI
    id_producto: UUID | None = None
    id_almacen: UUID | None = None
    id_balanza: UUID | None = None
    tipo_tercero: str | None = None
    id_tercero: UUID | None = None
    id_serie: UUID | None = None
    multi_despacho_recepcion: bool = False
    remolque_placa: str | None = None
    transporte_nombre: str | None = None
    conductor_cedula: str | None = None
    conductor_nombre: str | None = None
    producto_nombre: str | None = None
    almacen_nombre: str | None = None
    balanza_nombre: str | None = None
    tercero_nombre: str | None = None
    es_peso_manual: bool = False
    fecha_hora_entrada: datetime = Field(default_factory=lambda: datetime.now(UTC))
    peso_entrada_vehiculo: Decimal = Field(..., ge=0)  # PEC
    peso_entrada_remolque: Decimal | None = None  # PER
    documento: str | None = None
    guia_sunagro: str | None = None
    medida: str | None = None
    flete: str | None = None
    costo_flete: Decimal | None = None
    densidad: Decimal | None = None
    litros: Decimal | None = None
    unidades: Decimal | None = None
    observaciones: str | None = None

    @field_validator("peso_entrada_vehiculo")
    @classmethod
    def _no_negativo(cls, v: Decimal) -> Decimal:
        if v < 0:
            raise ValueError("El peso no puede ser negativo")
        return v
```

#### WeighingClose (cierre)

```python
class WeighingClose(BaseModel):
    es_peso_manual: bool = False
    fecha_hora_salida: datetime = Field(default_factory=lambda: datetime.now(UTC))
    peso_salida_vehiculo: Decimal = Field(..., ge=0)  # PSC
    peso_salida_remolque: Decimal | None = None  # PSR
    peso_neto_declarado: Decimal | None = None  # PND (peso declarado en la guía)
    densidad: Decimal | None = None
    litros: Decimal | None = None
    unidades: Decimal | None = None
    costo_flete: Decimal | None = None
    observaciones: str | None = None
    guia_sunagro: str | None = None
    medida: str | None = None
```

## 2. Diseño de Datos

### 2.1 Fórmulas de Cálculo

| Sigla   | Descripción                           | Fórmula                      |
|---------|---------------------------------------|------------------------------|
| **PEC** | Peso entrada camión (chuto + trailer) | dato (HAL)                   |
| **PER** | Peso entrada remolque (opcional)      | dato (HAL)                   |
| **PTE** | Peso total entrada                    | `PEC + PER`                  |
| **PSC** | Peso salida camión                    | dato (HAL)                   |
| **PSR** | Peso salida remolque                  | dato (HAL)                   |
| **PTS** | Peso total salida                     | `PSC + PSR`                  |
| **PNT** | Peso neto total                       | `PTE − PTS`                  |
| **PND** | Peso neto declarado (guía)            | dato (ingresado manualmente) |
| **PDF** | Peso diferencia                       | `PNT − PND`                  |
| **PDV** | Porcentaje desviación                 | `PDF / PND × 100`            |

### 2.2 Tolerancia Comercial

- Configurada en `productos.tolerancia` (porcentaje)
- Si `PDV > tolerancia`, el sistema emite advertencia (WARN level) pero **NO bloquea** el cierre
- El warning queda registrado en auditoría con `motivo_tolerancia_excedida`
- El kardex se genera igualmente con el movimiento correspondiente

### 2.3 Cálculo de Peso Neto y Signo

```
PNT = PTE − PTS

Si PNT > 0 → INGRESO POR BASCULA (Kardex ID 10, positivo)
Si PNT < 0 → DESPACHO POR BASCULA (Kardex ID 60, negativo)
Si PNT = 0 → Sin movimiento kardex (no se registra)
```

### 2.4 Al Anular CERRADO

- Se registra movimiento **inverso** en Kardex (INGRESO 10 ↔ DESPACHO 60)
- Conserva la historia original (no se borra ni reescribe)
- Actualiza saldos de inventario al efecto contrario del movimiento original

## 3. Diseño de Componentes

### 3.1 WeighingService (Core Business Logic)

```python
class WeighingService:
    
    async def create(self, db, weighing_data: WeighingCreate) -> BoletoPesaje:
        # 1. Validar anti-duplicidad: WHERE placa + id_empresa no tiene boleto PENDIENTE
        # 2. SELECT ... FOR UPDATE en series_numeracion para siguiente número
        # 3. Insertar boleto PENDIENTE
        # 4. Retornar boleto creado con numero_boleto
        pass
    
    async def close(self, db, boleto_id: UUID, close_data: WeighingClose) -> BoletoPesaje:
        # 1. Validar que boleto está en estado PENDIENTE
        # 2. Calcular PTE, PTS, PNT, PDF, PDV
        # 3. Verificar tolerancia comercial (warning, no bloquea)
        # 4. UPDATE boleto SET estado=CERRADO, pesos salida
        # 5. Registrar movimiento Kardex ID 10 (ingreso) o 60 (despacho)
        # 6. Retornar boleto CERRADO con todos los cálculos
        pass
    
    async def anul(self, db, boleto_id: UUID, motivo: str) -> BoletoPesaje:
        # 1. Validar rol (SUPERVISOR+)
        # 2. Validar motivo ≥ 10 caracteres
        # 3. Obtener peso neto original
        # 4. UPDATE boleto SET estado=ANULADO
        # 5. Si estaba CERRADO: registrar movimiento kardex INVERSO (10 ↔ 60)
        # 6. Retornar boleto ANULADO
        pass
    
    async def modify(self, db, boleto_id: UUID, modify_data) -> BoletoPesaje:
        # 1. Validar rol (ADMIN/SUPERVISOR)
        # 2. Validar que solo campos permitidos se modifican
        #    - documento, flete, costo_flete, observaciones, PND ✓
        #    - peso_entrada_vehiculo, peso_salida_vehiculo ✗ (bloqueado)
        # 3. Si boleto estaba CERRADO: pasar a MODIFICADO, incrementar ediciones_count
        # 4. Retornar boleto MODIFICADO
        pass
```

### 3.2 Kardex Service

```python
class KardexService:
    
    async def registrar(self, db, boleto: BoletoPesaje) -> Kardex:
        # 1. Calcular PNT = PTE - PTS
        # 2. Si PNT > 0: Kardex KARDEX_INGRESO (10, positivo, valor=abs(PNT))
        # 3. Si PNT < 0: Kardex KARDEX_DESPACHO (60, negativo, valor=abs(PNT))
        # 4. Si PNT = 0: No registrar kardex
        # 5. Solo si producto.es_kardex
        # 6. Retornar movimiento kardex registrado
        pass
    
    async def registrar_inverso(self, db, boleto: BoletoPesaje) -> Kardex:
        # 1. Por cada asiento original del boleto, agregar su opuesto
        # 2. INGRESO 10 <-> DESPACHO 60, conservando historia
        # 3. Actualizar saldos de inventario (cancelar efecto original)
        # 4. Retornar movimiento kardex inverso
        pass
```

## 4. Matriz de Trazabilidad de Requisitos (ISO/IEC 1016)

| Requisito      | Componente de Diseño                              | Sección/Atributo                                                                                                                        |
|----------------|---------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| **FR-SDD-001** | `WeighingService.create()`                        | Validación anti-duplicidad `WHERE placa + id_empresa`; `SELECT ... FOR UPDATE` series                                                   |
| **FR-SDD-002** | `WeighingService.close()`                         | Cálculos PTE-PTS-PNT-PDF-PDV; validación tolerancia; `Kardex.registrar()` ID 10/60                                                      |
| **FR-SDD-003** | `WeighingService.anul()`                          | Validación rol SUPERVISOR+; motivo ≥ 10 caracteres; auditoría usuario/fecha/IP/motivo; movimiento inverso kardex 10↔60                  |
| **FR-SDD-004** | `WeighingService.modify()`                        | Validación campos permitidos (documento, flete, costo_flete, observaciones, PND); peso báscula bloqueado; incrementar `ediciones_count` |
| **FR-SDD-005** | `WeighingService.close()`                         | `_aplicar_tolerancia()`: `PDV > tolerancia_producto` → WARN, no bloquea; kardex igual; API sin error                                    |
| **PF-001**     | `WeighingService` + `_enriquecer_pesajes_lista()` | p50 < 50 ms, p95 < 200 ms; paginación `limit`/`skip` obligatoria; sin N+1 queries                                                       |
| **SE-001**     | `WeighingService` + `AuthService`                 | `id_empresa` en TODAS las queries; ninguna fuga en `/metrics` ni logs públicos                                                          |
| **RE-001**     | `WeighingService.close()`                         | `asyncio.wait_for(writer.wait_closed(), timeout=2.0)`; timeouts acotados 1.0s a 2.0s                                                    |
| **MA-001**     | Todo el código                                    | `ruff check` 0 warnings; `flutter analyze` 0 errores; `mypy tests/` 0 fallos                                                            |
| **CO-001**     | `WeighingService`                                 | Hardware multi-marca: Toledo, Yaohua, Rice Lake, Torrey, Keli, Epson, OKI                                                               |

## 5. Interfaces con Otras Capas

### 4.1 Entrada desde Capa de Presentación (Flutter)

- **Endpoint**: `POST /api/v1/weighing/create`
- **Autenticación**: JWT Bearer con `id_empresa` en payload
- **Validación previa**: `id_empresa` extraído del token, filtrado en todas las operaciones
- **Formato**: Datos `WeighingCreate` Pydantic, campos opcionales según flujo

### 4.2 Salida a Capa de Persistencia (PostgreSQL)

- **Tabla**: `boletos_pesaje`
- **Campos obligatorios**: `id_empresa`, `estado_boleto`, `peso_entrada_vehiculo`, `fecha_hora_entrada`
- **Índices**: `idx_codigo_empresa` en catálogos, índice compuesto `(id_empresa, codigo)` en transportes/productos/almacenes

### 4.3 Salida a Hardware HAL

- **Comunicación**: Serial RS-232/USB o TCP sockets
- **Protocolo**: Frame parsing configurable (`lf`/`cr`/`crlf`/`stx_etx`, con/without checksum XOR)
- **Timeouts**: Lectura 1.0s a 2.0s, `writer.wait_closed()` con `asyncio.wait_for(timeout=2.0)`
- **Estabilidad**: Espera 3 segundos mínima antes de capturar peso

### 4.2 Entrada desde Hardware HAL

- **Frame recibido**: PEC (peso vehículo), PER (peso remolque, opcional)
- **Validación**: Peso ≥ 0, estabilidad 3 segundos, unidad compatible
- **Salida**: PEC y PER enviados a `WeighingService.create()` o `WeighingService.close()` dependiendo del flujo

## 5. Suposiciones y Restricciones

### 5.1 Suposiciones

- Base de datos PostgreSQL 15+ disponible y operativo
- Hardware de básculas compatible (o modo manual como alternativa)
- JWT válido con `id_empresa` en payload para todas las operaciones
- Licencias validadas contra License Manager (Ed25519)

### 5.2 Restricciones

- **Sin Alembic**: Todas las migraciones son hand-made en `src/backend/migrations/*.sql` (001-025), idempotentes
- **Motor BD por prefijo**: `db_engine.py` decide `postgresql` o `mssql` por prefijo de `DATABASE_URL`
- **Inmutabilidad metrológica**: Peso capturado NUNCA se edita ni sobrescribe en boletos CERRADOS/MODIFICADOS
- **id_empresa obligatorio**: Debe aparecer en TODA consulta, filtro, inserción o validación
- **Series numeración**: `SELECT ... FOR UPDATE`; nevera reutilización; DELETE con boletos → código 409
- **Modo offline**: Capa SQLite + sync_queue; operaciones PENDIENTE sincronizables al recuperar conexión
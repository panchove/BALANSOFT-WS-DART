# Análisis de volumen P2 — 50k boletos

**Fecha**: 2026-10-02
**Estado**: cerrado
**Base**: `balansoft_ws_volumen` (37 MB, 50 000 boletos + 8 470 asientos de kardex)
**Autor**: equipo BALANSOFT-WS
**Norma**: REQ-P2-001 (volumen representativo), `AGENTS.md` §Tests
**Fuente**: `backend/scripts/seed_volumen.py`, `backend/scripts/benchmark_volumen.py`, `docs/evidencia/volumen-benchmark.txt`

---

## 1. Qué se hizo

Se generó un volumen de **50 000 boletos** con distribución realista y se midieron
los **11 endpoints** de lectura más usados por la estación. La meta era encontrar
cuellos de botella **antes** de que aparecieran en una planta con carga real.

### 1.1 Composición del volumen

| Entidad | Cantidad | Nota |
|---|---:|---|
| Boletos | 50 000 | 12 meses, fechas distribuidas |
| Catálogos | 100 productos (20 con `es_kardex`), 20 almacenes, 500 camiones, 200 conductores, 50 transportes, 10 básculas | |
| Series de numeración | 5 | contadores alineados con lo emitido |
| Kardex | 8 470 | ID 10 = 7 988 · ID 60 = 482 |

Distribución de estados (la acordada, 70/20/5/5), medida sobre lo generado:

| Estado | Boletos | % |
|---|---:|---:|
| CERRADO | 34 957 | 69,9 |
| PENDIENTE | 10 051 | 20,1 |
| MODIFICADO | 2 538 | 5,1 |
| ANULADO | 2 454 | 4,9 |

### 1.2 Coherencia de la semilla

Un volumen incoherente daría un benchmark sin valor, así que se validan los
invariantes de negocio directamente en SQL. Los **10** pasan:

| Invariante | Resultado |
|---|---|
| CERRADO/MODIFICADO/ANULADO sin salida | 0 |
| PENDIENTE con salida | 0 |
| `peso_neto ≠ peso_bruto − peso_tara` | 0 |
| `fecha_hora_salida ≤ fecha_hora_entrada` | 0 |
| ANULADO sin motivo de anulación | 0 |
| ANULADO con kardex sin su par inverso | 0 |
| Kardex en boleto PENDIENTE | 0 |
| Kardex en producto sin `es_kardex` | 0 |
| `numero_boleto` duplicado | 0 |
| `series.siguiente ≠ emitidos + 1` | 0 |

El conteo de kardex cuadra con lo esperado de forma independiente:
`50 000 × 0,80 (no PENDIENTE) × 0,20 (producto con kardex) ≈ 8 000` asientos
originales, más `50 000 × 0,05 × 0,20 ≈ 500` inversos por anulación → ~8 500.
Medido: 8 470.

### 1.3 Metodología de medición

Decisiones que hay que tener presentes al leer los números:

- Transporte **ASGI en proceso**: sin red, sin uvicorn ni WebSocket. El tiempo
  atribuido es al endpoint + SQLAlchemy + PostgreSQL + serialización.
- `get_current_user` / `get_current_empresa` se resuelven contra la **empresa
  real sembrada**. La firma JWT se omite a propósito: son microsegundos y meterlos
  en el ruido taparía lo que se quiere medir (el acceso a datos).
- Rate limiting **desactivado** por defecto en `config.py`
  (`rate_limit_enabled = False`); si estuviera activo, varias mediciones darían
  429 y falsearían los percentiles.
- Cada escenario se repite 5 veces y se reportan **p50/p95/p99/máx**, no la
  media: en una estación de pesaje mandan los percentiles.
- Los parámetros se derivan de los datos sembrados (la placa con más boletos,
  un producto con kardex), no se inventan.
- Una pasada de calentamiento por escenario, para no medir el primer acceso a
  cada relación.

---

## 2. Resultados

### 2.1 Antes del arreglo (bug encontrado)

| Endpoint | p50 (ms) | p95 (ms) | Umbral | Estado |
|---|---:|---:|---:|---|
| `weighing/list` sin filtro | 445,5 | 462,1 | 200 | 🔴 2,3× |
| `weighing/list` placa + fechas | 445,5 | 505,0 | 300 | 🔴 1,7× |
| `weighing/list` página profunda | 473,0 | 487,2 | 300 | 🔴 1,6× |
| `weighing/list` por estado | 447,0 | 472,8 | 200 | 🔴 2,4× |
| `weighing/pendientes` | 462,7 | 505,4 | 100 | 🔴 **5,1×** |
| `reports/*` y `catalogo/sync` | 2,6 – 36,9 | ≤ 38,0 | 500 – 1000 | 🟢 |

**5 de 11 escenarios fuera de umbral**, todos en `weighing/*`.

### 2.2 Después del arreglo

| Endpoint | p50 (ms) | p95 (ms) | p99 (ms) | Umbral | Estado |
|---|---:|---:|---:|---:|---|
| `weighing/list` sin filtro | 20,2 | 23,0 | 23,0 | 200 | 🟢 |
| `weighing/list` placa + fechas | 14,2 | 19,8 | 19,8 | 300 | 🟢 |
| `weighing/list` página profunda | 34,9 | 35,3 | 35,3 | 300 | 🟢 |
| `weighing/list` por estado | 16,4 | 18,8 | 18,8 | 200 | 🟢 |
| `weighing/pendientes` | 12,7 | 13,9 | 13,9 | 100 | 🟢 |
| `reports/daily` | 4,0 | 4,1 | 4,1 | 500 | 🟢 |
| `reports/monthly` | 3,9 | 3,9 | 3,9 | 1000 | 🟢 |
| `reports/vehicle` (1 placa, 12 meses) | 2,8 | 5,9 | 5,9 | 500 | 🟢 |
| `reports/kardex/saldo` | 6,4 | 7,0 | 7,0 | 300 | 🟢 |
| `reports/kardex/detalle` | 17,9 | 19,3 | 19,3 | 500 | 🟢 |
| `catalogo/sync` (todo) | 26,3 | 27,9 | 27,9 | 1000 | 🟢 |

**11 de 11 dentro de umbral**, con margen amplio en todos los casos.

| Endpoint | p50 antes | p50 después | Mejora |
|---|---:|---:|---:|
| `weighing/pendientes` | 462,7 ms | 12,7 ms | **36×** |
| `weighing/list` sin filtro | 445,5 ms | 20,2 ms | **22×** |
| `weighing/list` por estado | 447,0 ms | 16,4 ms | **27×** |
| `weighing/list` página profunda | 473,0 ms | 34,9 ms | **14×** |

---

## 3. Causa raíz: N+1 en el enriquecimiento del listado

**No era un problema de índices.** El plan de ejecución del listado era
correcto desde el principio:

```
Index Scan Backward using idx_boletos_pesaje_fechas on boletos_pesaje
  (actual time=0.034..0.525 rows=100 loops=1)
Execution Time: 0.596 ms
```

Y el `COUNT` de paginación, 4,7 ms. Juntas: **~5 ms de las 450**.

El perfil de Python mostró la verdad: **7 025 llamadas a `execute` por 5
peticiones**, es decir **~1 400 consultas por petición**.

### Qué pasaba

`/weighing/list` y `/weighing/pendientes` recorían la página y llamaban a
`_enriquecer_pesaje_ticket` **una vez por boleto**. Esa función está diseñada
para **un** boleto (ticket impreso, PDF, cierre) y lanza hasta **10 consultas**:
remolque, producto, categoría, conductor, transporte, tercero, almacén, báscula,
color del camión y movimiento de kardex.

Una página de 100 boletos → **~1 000 idas y vueltas a PostgreSQL** para
rellenar nombres. Ese es el N+1 clásico, y explica que los cinco escenarios
costaran lo mismo: el costo lo ponía el número de filas, no el filtro.

Escala cuando el usuario pide `limit=1000`: el endpoint habría hecho ~10 000
consultas. En una estación con WServer de un solo worker, eso bloquea el event
loop y afecta a todos los endpoints, no solo al listado.

### El arreglo

`_enriquecer_pesajes_lista` resuelve **una vez por página**: una consulta por
catálogo (7 en total, constante respecto al `limit`) y se adjunta el nombre a
cada fila. Solo resuelve los **7 campos que `WeighingOut` serializa**; el resto
(kardex, color, categoría, tara) es exclusivo del ticket AVANZADO y se conserva
en `_enriquecer_pesaje_ticket`, que sigue siendo el camino de los endpoints de
un solo boleto.

Efecto secundario favorable: la versión por lotes **filtra todos los catálogos
por `id_empresa`**. La versión original solo lo hacía para camión y kardex y
buscaba el resto por clave primaria a secas. El tenant ahora lo decide el
contexto autenticado en los dos caminos, no solo en uno.

---

## 4. Cambios aplicados

| Archivo | Cambio |
|---|---|
| `app/api/v1/endpoints/pesajes.py` | Nueva `_enriquecer_pesajes_lista`; `/list` y `/pendientes` dejan de enriquecer fila por fila |
| `tests/test_endpoints.py` | `TestListadoNoEsNMasUno`: 3 tests de regresión |
| `scripts/seed_volumen.py` | Nuevo: semilla de 50k con 10 invariantes verificados |
| `scripts/benchmark_volumen.py` | Nuevo: 11 escenarios con p50/p95/p99 y umbrales |

**No se creó la migración `021_indices_volumen.sql`.** El plan del plan inicial
—no había ningún índice compuesto por `id_empresa`, y toda consulta filtra por
tenant— **resultó ser un problema teórico a 50k**: con un solo tenant, el
`Index Scan Backward` sobre fechas ya resuelve en 0,6 ms y no hay colisión que
filtrar. Añadir índices por una hipótesis no verificada solo encarece las
escrituras de pesajes (la operación más frecuente de la estación). Queda
documentado como vigilancia para multi-tenant real, no como trabajo pendiente.

---

## 5. Verificación

| Comprobación | Resultado |
|---|---|
| Backend rápido + E2E | **354 en verde** (320 + 34) |
| Ruff (`app tests`) | limpio |
| Mypy (`tests/`) | sin hallazgos |
| Tests de regresión del N+1 | 3/3 |
| **Prueba negativa de los tests** | reintroducido el N+1 a mano → **2 de 3 tests fallan**, el guard funciona |
| `/list` sigue devolviendo los nombres | verificado contra el volumen |

El último punto importa: un test que no falla cuando se rompe el comportamiento
que dice fijar no sirve de nada, así que se comprobó explícitamente.

---

## 5.b Pendiente y riesgos

| # | Riesgo / pendiente | Estado |
|---|---|---|
| R1 | `multi_despacho_recepcion` es una columna **inerte**: se persiste pero ninguna consulta la lee (§7). No afecta a ningún reporte | 🔴 Requiere decisión |
| R2 | Sin colisión real de `id_empresa` no se puede medir el peor caso multi-tenant. Con muchas empresas, el índice compuesto por tenant pasa a ser necesario | ⚠️ Vigilar |
| R3 | **Resuelto**: el costo de JWT + red TCP quedó medido en §6. No era la cota que se suponía (~20 ms, no 5–15) | ✅ Cerrado |
| R4 | **Nuevo**: `/weighing/list` alcanza su umbral de 200 ms p95 con **10 operadores** concurrentes (§6.3) | ⚠️ Vigilar |
| R5 | 50k boletos es el volumen acordado; una planta grande con varios años superaría los 100k | ℹ️ Aceptado |
| R6 | `scripts/seed_simulacion.py` tiene un aviso `B007` de Ruff preexistente (de H2b). `scripts/` está fuera del lint canónico (`ruff check app tests`) | ⚠️ Preexistente |
| R7 | La estación usa **un solo worker** (`uvicorn.run` sin `workers`): todo pasa por un event loop. Medido en §6, sin 5xx, pero el techo de ~40 req/s en listados es real | ⚠️ Vigilar |

---

## 6. P2c — JWT, red TCP y concurrencia (cierra la advertencia de los límites)

Las cifras de §2 son una **cota inferior**: transporte ASGI en proceso, sin red y
sin validar JWT. `scripts/benchmark_concurrencia.py` mide la diferencia completa
contra un servidor real.

### 6.1 Diseño

- **Un worker**, como la estación: `wserver.py` lanza `uvicorn.run(app, ...)` sin
  `workers`, o sea el valor por defecto (**1**). Toda la estación comparte un
  único event loop.
- **JWT auténtico**: cada operador virtual hace `POST /auth/login` y usa el token
  que devuelve el servidor. No se falsea la autenticación.
- **Cierre por operador**: cada operador espera su respuesta antes de pedir la
  siguiente, con 0,2 s de tiempo de pensar. Saturar sin pausa no representa a una
  persona frente a una pantalla.

### 6.2 Costo real de JWT + red

Con **1 operador** (el caso típico de una estación):

| Escenario | p50 | Qué aísla |
|---|---:|---|
| `/health` **sin** auth | 3,3 ms | Solo TCP + stack HTTP/ASGI |
| catálogo **con** auth | 10,2 ms | Lo anterior + JWT + dependencias |
| `/weighing/list` | 39,8 ms | + la consulta (20,2 ms medido en proceso) |

**El sobrecoste real es ~20 ms**, no los 5–15 ms que se suponía: ~7 ms de JWT y
dependencias de autenticación sobre el stack HTTP, más el socket y la
serialización JSON. Aun así, 39,8 ms p50 queda muy por debajo de los 200 ms de
umbral.

### 6.3 Escalado con operadores concurrentes

| Operadores | `/weighing/list` p50 | p95 | p99 | req/s | Umbral 200 ms |
|---:|---:|---:|---:|---:|---|
| 1 | 39,8 ms | 54,6 ms | 65,1 ms | 4,2 | 🟢 |
| 5 | 59,7 ms | 102,5 ms | 146,5 ms | 19,2 | 🟢 |
| 10 | 91,0 ms | **200,5 ms** | 238,7 ms | 33,3 | 🔴 en el umbral |
| 25 (saturación) | 604,8 ms | 1131,2 ms | 1309,8 ms | 39,2 | 🔴 |
| 50 (saturación) | 1133,6 ms | 2065,2 ms | 2527,5 ms | 42,9 | 🔴 |

**El umbral de 200 ms p95 se alcanza con 10 operadores concurrentes.** Para una
estación de pesaje —donde un operador genera peticiones aisladas y la carga real
es 1–3 usuarios— hay margen de sobra. Pero es el número a tener presente si una
planta concentrara muchas cabinas sobre el mismo WServer.

### 6.4 El techo de la estación

Bajo saturación, el rendimiento de los endpoints pesados **se plafona**:

| Operadores | `/weighing/list` req/s | p50 |
|---:|---:|---:|
| 10 | 45,2 | 196,7 ms |
| 25 | 39,2 | 604,8 ms |
| 50 | 42,9 | 1133,6 ms |

Añadir concurrencia no añade capacidad: solo agranda la cola. El techo está en
**~40–45 req/s** para los endpoints de listado, con 50k boletos y el N+1 ya
corregido.

**Control de validez**: el mismo cliente con `/health` alcanza **660 req/s**, así
que el techo es del servidor, no del cliente que genera la carga.

Y un dato tranquilizador: **cero errores 5xx** en todos los niveles, hasta 50
operadores. La estación degrada con latencia, no con caídas.

---

## 7. `multi_despacho_recepcion` es una columna inerte

Al revisar la advertencia R1 se investigó si el flag afectaba de verdad a los
reportes. **No lo hace, en absoluto.**

| Dónde | Estado |
|---|---|
| Esquema (`balansoft-ws-local.sql`) | columna `BOOLEAN NOT NULL DEFAULT FALSE` |
| Modelos y esquemas (3 campos) | se declara y se serializa |
| `weighing_service.create` | se copia al guardar |
| `sync_service` | se copia al sincronizar |
| Frontend (`model`, `mapper`, BD local) | solo ida y vuelta |
| **Consultas (`SELECT`/`WHERE`/`GROUP BY`/`ORDER BY`)** | **0 apariciones** |
| UI que lo exponga | ninguna |
| Semántica documentada | ninguna (`ARCH.md` solo la lista en el DDL) |

### Prueba empírica

No bastaba con el grep, así que se marcaron **10 000 boletos** con
`multi_despacho_recepcion = true` y se re-midieron los 11 escenarios:

| Endpoint | Antes | Con 10k marcados | Umbral |
|---|---:|---:|---:|
| `reports/daily` | 4,0 ms | 4,6 ms | 500 |
| `reports/monthly` | 3,9 ms | 3,9 ms | 1000 |
| `reports/kardex/saldo` | 6,4 ms | 6,5 ms | 300 |
| `reports/kardex/detalle` | 17,9 ms | 14,0 ms | 500 |

Idénticos dentro del ruido de medición. **Poner el flag en `true` no cambia
nada**, porque no hay código que lo lea. La degradación de 2–5× que se hipótese
no puede ocurrir, porque la condición que la causaría no está implementada.

Después se restauró el volumen a su estado original.

### Por qué importa

La advertencia era correcta en su intención pero su premisa era falsa. Esto deja
una decisión de producto, no de ingeniería:

1. **La columna está muerta.** Persiste un dato que nadie usa, ocupa espacio,
   viaja en cada sincronización y aparece en las APIs pública y de sync.
2. **No hay multi-despacho.** El sistema no modela una entrada con varios
   despachos: cada boleto es independiente. La feature no existe.
3. **Falta la definición.** Ningún documento dice qué debe hacer un
   multi-despacho (¿varios boletos con el mismo documento y pesos que suman la
   entrada? ¿kardex prorrateado?). Implementarlo sin eso sería inventar la regla.

**No se implementó ni se borró la columna**: borrarla rompe clientes y
sincronizaciones existentes, e implementarla exige una decisión de negocio que no
está tomada. Queda documentado para que la decisión sea explícita.

---

## 8. Cómo reproducir

```bash
cd backend

# 1. Crear la BD y sembrarla (tarda ~2 min)
uv run python scripts/seed_volumen.py --crear-bd

# 2. Medir en proceso: 11 escenarios x 5 repeticiones (cota inferior)
uv run python scripts/benchmark_volumen.py --salida docs/evidencia/volumen-benchmark.txt

# 3. Medir con JWT + TCP + concurrencia (levanta su propio uvicorn de 1 worker)
uv run python scripts/benchmark_concurrencia.py \
    --operadores 1,5,10 --duracion 15 \
    --salida docs/evidencia/volumen-benchmark-concurrente.txt

# 4. Hallar el techo de la estación (saturación pura)
uv run python scripts/benchmark_concurrencia.py --operadores 10,25,50 --sin-think

# 5. Liberar el disco
uv run python scripts/seed_volumen.py --drop-bd
```

La semilla usa `Random(20261002)`: el volumen es **reproducible**, así que las
comparaciones entre ejecuciones son válidas.
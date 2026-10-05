# TASKS 001 — Ajuste de tipografía del sistema y del ticket

**Versión:** 1.0
**Fecha:** 2026-10-02
**Estado:** Desglose aprobado, listo para ejecución
**Autor:** Agente planificador
**Plan:** `specs/001-tipografia-config/plan.md` v1.0
**Especificación:** `specs/001-tipografia-config/spec.md` v0.2
**Código escrito:** ninguno

---

## 0. Resumen del desglose

**11 tareas** (10 del desglose aprobado, con **T10 dividida en T10a y T10b** — el
ajuste #3, confirmado en §2).

| Rama | Tareas | Origen |
|------|--------|--------|
| 🔴 Gate | T1 | Medición de desbordes |
| 🔵 Backend — ticket | T2 → T3, T4 → T5 → T6 | Por empresa |
| 🟢 Frontend — sistema | T7 → T8 → T9 → T10a → T10b | Por dispositivo |

**Restricción dura:** `T4 ──precede──> T6`. No paralelizar. Ver `plan.md §2`.

**Total estimado:** ~255 min de trabajo efectivo (≈4 h 15), más el tiempo de
levantamiento del entorno E2E que consume T1.

| Tarea | Min | Rama |
|-------|-----|------|
| T1 `[GATE]` | 25 | Gate |
| T2 | 25 | Backend |
| T3 | 25 | Backend |
| T4 | 25 | Backend |
| T5 | 20 | Backend |
| T6 | 25 | Backend |
| T7 | 25 | Frontend |
| T8 | 20 | Frontend |
| T9 | 25 | Frontend |
| T10a | 20 | Frontend |
| T10b | 15 | Frontend |
| **Total** | **255** | |

---

## 1. T1 `[GATE]` — SPIKE: medición de desbordes a `textScaler` 1.40

| Campo | Contenido |
|-------|-----------|
| **RF que informa** | REQ-FN-002b, REQ-FN-008 |
| **Depende de** | — (ninguna) |
| **Duración** | ~25 min (+~5 por el wrapper de `REQ-FN-002c`) |
| **Descartable** | ✅ **Sí.** No se commitea. Su único entregable es el reporte |

### Qué hace

Mide el número de eventos `RenderFlex overflowed` con el factor de escala en **1.40**
(el extremo superior del selector) en las 4 pantallas críticas de REQ-FN-008:
formulario de pesaje, detalle del boleto, panel principal y pantalla de ajustes.

**Harness**: `integration_test/`, reutilizando el andamiaje existente de
`pesaje_flow_test.dart` (pump de la app real a 1400×860 en `:103-104,145`,
`di.init()`, `AppConfig`). Levantar antes con
`cd backend && bash scripts/e2e_flutter.sh up`.

**Por qué no widget tests unitarios**: `weighing_form_screen.dart` tiene 4153 líneas
y exige `CatalogBloc` (`:193`); el único test de detalle existente solo ejerce el
estado vacío (`weighing_detail_screen_test.dart:9-23,27`). Ver `plan.md §6.6`.

### Hecho cuando:

- [x] El entorno E2E está levantado y `frontend` compila para `-d linux`
- [x] Se ha recorrido **las 4 pantallas** con el factor en **1.40**
- [x] Existe un entero **`overflow_count`** (no una impresión qualitativa)
- [x] El reporte dice, por cada ocurrencia: **pantalla + factor + mensaje exacto**
      `RenderFlex overflowed`
- [x] El reporte está **entregado al Encargado**

### Resultado: ✅ **T1 pasa** — `overflow_count` = **0**

Reporte completo en [`evidencia/t1-reporte.md`](evidencia/t1-reporte.md). El
rango [0.85, 1.40] queda ratificado y se avanza a T2.

Durante la medición se corrigieron dos defectos **del spike** (no de la app): la
cabecera declaraba 1.50 mientras la constante ya valía 1.40, y el spike no
alcanzaba `detalle_boleto` porque buscaba el boleto recién cerrado en ENTRADAS
en vez de en SALIDAS. Los dos habrían producido un `0` falso.

### Criterio de salida (binario)

| `overflow_count` | Acción |
|:---:|---|
| **== 0** | ✅ **T1 pasa.** El rango [0.85, 1.40] queda ratificado. **Se avanza a T2** |
| **> 0** | 🛑 **PARAR.** No se avanza a T2 |

**Si `overflow_count > 0`, en este orden y sin excepciones:**

1. **PARAR.**
2. **Reportar** pantalla + factor + mensaje `RenderFlex overflowed` por ocurrencia.
3. **Reabrir la pregunta 5** de `spec.md §3` (rango del tamaño del sistema). El rango
   es una decisión, no un hecho; si el máximo no cabe, la decisión se revisa.
4. **No parchear T1.** Nada de paddings, `Flexible`, `isExpanded` ni alturas
   (`spec.md §4.2` punto 4 excluye ese refactor).
5. **No commitear T1.** Es descartable: solo se reporta.
6. La decisión sobre el rango la toma el Encargado.

---

## 2. T2 — Migración 021 + modelo + reflejo en el esquema canónico

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-009 (persistencia por `id_empresa`) |
| **Depende de** | T1 (gate) |
| **Duración** | ~25 min |

### ⚙️ AJUSTE #1 incorporado: actualizar **ambos** ficheros

La spec lo fijó así (`spec.md` F1, verificado en contra) y es el punto donde una
ejecución descuidada rompe instalaciones ya migradas. **T2 no está completa si se
toca solo uno de los dos ficheros.**

### Qué hace

Tres piezas:

1. **`backend/migrations/021_*.sql`** (archivo nuevo). Patrón copiado de
   `017_idioma_formato_reporte_empresa.sql`:
   - `ADD COLUMN IF NOT EXISTS` × 2
   - `UPDATE` de backfill de los NULL existentes
   - `SET DEFAULT` × 2
   - bloque `DO`/`IF NOT EXISTS` con 2 `CHECK` que admiten los valores de los
     `Literal` del schema
2. **`backend/app/models/__init__.py`**, clase `Empresa` (`:84-122`): 2 columnas
   nuevas tras `ruta_exportacion_reportes` (`:104-106`), con el mismo patrón
   `mapped_column(String(...), nullable=True, default=..., server_default=...)`.
3. **`backend/balansoft-ws-local.sql`**: las columnas en el
   `CREATE TABLE IF NOT EXISTS empresas` (`:39-61`) **Y** en el bloque de alineación
   `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (`:63-69`).

**Nombres de las columnas**: `tamano_ticket_pdf` (VARCHAR, valores
`AUTOMATICO|GRANDE|MEDIANO|PEQUENO`, default `AUTOMATICO`) y `fuente_ticket_pdf`
(VARCHAR, única familia admitida `DejaVu`, default `DejaVu`). El default `AUTOMATICO`
es lo que garantiza que toda estación existente siga **exactamente** como hoy
(REQ-FN-012).

### Hecho cuando:

- [x] `migrations/021_*.sql` existe, es **idempotente** y se aplica **dos veces**
      seguidas sin error (patrón `017`)
- [x] Los 2 `CHECK` evitan valores fuera del `Literal`
- [x] Las columnas existen en `models/__init__.py` (`Empresa`)
- [x] `balansoft-ws-local.sql` refleja las columnas **en los 2 sitios** (`CREATE
      TABLE` y bloque `ALTER`)
- [x] `empresas` conserva `id_empresa` como PK → constitución regla 1 (ya lo tiene;
      no se añade tabla ni columna con tenant)
- [x] `cd backend && uv run pytest -q` sigue en verde (el esquema de los tests sale
      de los modelos, `conftest.py:52-62`)
- [x] Verificación manual del `.sql` aplicada:
      `./scripts/setup_db.sh aplicar-migraciones` y comparar `\d empresas` con el
      modelo (`plan.md §7.6`)

### Resultado (2026-10-03)

- **Tests**: 18 nuevos en `backend/tests/test_migration_021_tamano_ticket.py`;
  **380/380** en verde (362 previos + 18). `ruff check app tests` limpio.
- **Las 2 columnas** (`tamano_ticket_pdf`, `fuente_ticket_pdf`) en los 3 sitios:
  migración 021, modelo `Empresa` (tras `ruta_exportacion_reportes`) y
  `balansoft-ws-local.sql` (`CREATE TABLE` **y** bloque `ALTER`).
- **Verificación end-to-end** en BD desechable `balansoft_ws_021check`, con el
  script real: `instalar` (esquema canónico) → `aplicar-migraciones` (001→021).
  La 021 se aplicó **dos veces** sin error (`NOTICE: column … already exists,
  skipping`): idempotencia confirmada sobre el esquema ya alineado.
- **`\d empresas` vs modelo**: coinciden tipo, longitud, nulabilidad y default en
  ambas columnas. Divergencia **preexistente** y ajena a la 021: `id_cuenta`
  existe en el esquema canónico y no está mapeada en el modelo.
- **F1 (`series_numeracion`)**: no afecta a la 021; la 015 ya la creó en
  `balansoft_ws_local`. Se mantiene como deuda documentada.
- **No se aplicó a `balansoft_ws_local`**: `wserver.py:231-265` aplica
  `migrations/*.sql` en el próximo arranque de la estación, que es el camino de
  producción. La verificación se hizo en copia aislada para no tocar datos de dev.
- **Aislamiento**: el `CHECK` admite `NULL` a propósito; las columnas son
  `nullable=True` para no romper instalaciones previas.

---

## 3. T3 — Schemas + `GET`/`PUT /empresa` + tests

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-009, REQ-FN-014, REQ-FN-018 |
| **Depende de** | T2 |
| **Duración** | ~25 min |

### ⚙️ AJUSTE #2 incorporado: test de lectura, no solo de escritura

La QA pidió reforzar REQ-FN-018 **más allá del PUT**. El test nuevo verifica que
`GET /empresa` **no** devuelve campos de empresas distintas. Es el test que detecta
una fuga por el canal de solo lectura, que es el que la auditoría de `spec.md §2.3`
no cubría (las dos superficies que enumera son `GET` y `PUT`, pero los tests
existentes de aislamiento solo ejercitan el `PUT`).

### Qué hace

1. **`backend/app/schemas/__init__.py`**: 2 campos en `EmpresaPerfilOut`
   (`:694-708`, con `Literal` + default) y 2 en `EmpresaPerfilUpdate`
   (`:711-722`, con `Literal` + `Field(None)`), copiando el patrón exacto de
   `idioma`/`formato_reporte` (`:704-705`, `:719-720`).
2. **`empresa.py`: sin cambios.** `GET`/`PUT` ya resuelven por
   `Depends(get_current_empresa)` (`:29`, `:39`) y el `PUT` itera con `setattr`
   (`:49-50`). Añadir campos a los schemas basta.
3. **`backend/tests/test_preferencias_empresa.py`**: tests nuevos con el estilo del
   fichero (helper `_app_con_rol`, `:26-46`; clase `TestPerfilEmpresa`).

### 🛡️ Trampa de aislamiento (verificada — leer antes de escribir el test)

El helper `_app_con_rol` hace
`dependency_overrides[get_current_empresa] = lambda: empresa` (`:45`). **Ese override
enmascararía justo el fallo que REQ-FN-018 busca.** El test de aislamiento:

- **NO** sobrescribe `get_current_empresa`; sobrescribe **solo** `get_current_user`
  con un usuario de la empresa **B** y deja que `dependencies.py:50-58` resuelva
  desde la BD.
- Crea la **segunda empresa dentro del test** (solo hay un fixture `empresa`,
  `conftest.py:78-93`) con `rif_nit` único (patrón `:84`).
- Comprueba que el `GET` de un usuario de B **no** ve los valores de A.

### Hecho cuando:

- [x] `EmpresaPerfilOut` y `EmpresaPerfilUpdate` exponen los 2 campos
- [x] `GET /empresa` y `PUT /empresa` los devuelven
- [x] `PUT` con un valor fuera del `Literal` → **422**
- [x] `PUT` por un rol no ADMIN → **403** (patrón existente `:109-114`)
- [x] **Test nuevo: `GET /empresa` de la empresa B no ve los campos de A**
- [x] Test: `PUT` de A no altera los valores de B (y viceversa)
- [x] Mass assignment sigue bloqueado (REQ-FN-018): `id_empresa` en el payload se
      descarta
- [x] `cd backend && uv run pytest -q tests/test_preferencias_empresa.py` en verde
- [x] `cd backend && uv run ruff check app tests` y `uv run mypy tests/` sin hallazgos

### Resultado (2026-10-03)

- **Tests**: 22 nuevos en `backend/tests/test_preferencias_empresa.py`;
  **402/402** en verde (380 previos + 22). `ruff check app tests` y `mypy tests/`
  limpios.
- **Solo se tocó `app/schemas/__init__.py`**: `empresa.py` quedó intacto, como
  preveía el plan (los `Literal` bastan; el `setattr` itera lo que el schema acepte).
- **Los tests de aislamiento se verificaron en negativo**: saboteando
  `get_current_empresa` (`dependencies.py`) para que devuelva la primera empresa
  en vez de la del token, los 3 tests de aislamiento fallan. Con `_app_con_rol`
  habrían pasado igual: el override de `get_current_empresa` fija el tenant y
  enmascararía la fuga.
- **Decisión que el plan no cubría (1)**: `EmpresaPerfilOut` No lleva `| None`
  (el plan pide el patrón de `idioma`), pero las columnas son `nullable=True`, así
  que un `NULL` heredado haría que `GET /empresa` fallara con **500** en la
  validación de respuesta. Se añadió un `field_validator(mode="before")` que
  traduce `NULL` → default de negocio, para que REQ-FN-012 no dependa de que el
  backfill de la 021 se haya aplicado. Cubierto por
  `test_put_null_desfija_y_get_devuelve_el_default`.
- **Decisión que el plan no cubría (2)**: `PUT {"tamano_ticket_pdf": null}` se
  acepta con **200**, no 422, porque el plan define el campo como
  `Literal | None = Field(None)` (igual que `idioma`). `null` significa "sin
  fijar": se guarda `NULL` y `GET` devuelve el default. Fijado por test.
- **Notación**: el valor es `PEQUENO` (sin ñ), el mismo del `CHECK` de la 021 y de
  `tasks.md`; no `PEQUEÑO`.
- **Fuera de T3**: la respuesta de **login** (`schemas/__init__.py:100-104`)
  todavía **no** expone los 2 campos, aunque el encabezado de la migración 021
  afirma que se entregan ahí. `plan.md §3.3` solo abarca `EmpresaPerfilOut` y
  `EmpresaPerfilUpdate`, así que queda pendiente para la tarea que toque login.
- **Hallazgo #3 (`server_default` divergente)**: **no afecta a T3**. `GET` y `PUT`
  funcionan porque las columnas sí están mapeadas y con default en el modelo.

---

## 4. T4 — Baseline del PDF (texto extraído) + no-regresión `AUTOMATICO` + sin red

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-012, REQ-FN-017 |
| **Depende de** | T2 |
| **Duración** | ~25 min |

### 🔒 PRECONDICIÓN DURA DE T6

**T6 no puede empezar hasta que esta tarea esté completada.** Ver `plan.md §2`.

Motivo en una línea: sin el baseline congelado, T6 cambia la escalera del auto-fit y
**nada puede detectar una regresión**, porque el único control se habría tomado
después del cambio.

**Comparación por texto extraído, nunca por bytes.** Verificado empíricamente en este
repo: dos generaciones del mismo PDF dan 45 330 bytes **iguales en longitud pero
distintos**, y la diferencia son **60 bytes**: el array `/ID` del trailer, que
ReportLab genera aleatoriamente. Las dos generaciones ocurrieron **en el mismo
segundo**, así que ni siquiera congelando el reloj se obtendría reproducibilidad.
El texto extraído, en cambio, es **idéntico** (646 caracteres).

### Qué hace

En `backend/tests/test_ticket_service.py`, **sin tocar `ticket_service.py`**:

1. **Baseline `AUTOMATICO`**: generar el PDF de `_boleto()`, extraer el texto con el
   helper `_extract` que **ya existe** (`:29-33`) y fijar el texto esperado
   normalizado como **constante en el test** (no un PDF binario en el repo).
   Añadir la comparación del **número de páginas** con el helper `_paginas`
   (`:36-39`).
2. **Normalización**: minúsculas, espacios colapsados, líneas vacías fuera, para que
   el test no dependa de cómo `pypdf` interprete los saltos de línea entre versiones.
3. **Sin red (REQ-FN-017)**: test de que `generar_ticket_pdf` **no** hace ninguna
   llamada saliente. La vía es verificar que el endpoint
   `GET /weighing/{boleto}/pdf` (`pesajes.py:495-523`) genera el PDF sin ningún
   cliente HTTP ni `LicenseClient`: la ruta ya es puramente local.

### Hecho cuando:

- [x] Existe el baseline: texto extraído esperado como constante en el test
- [x] El test pasa **contra el código actual, sin tocar `ticket_service.py`**
      ← este es el punto que hace válida la precondición de T6
- [x] El test normaliza el texto (no es frágil ante saltos de línea)
- [x] El test compara también el número de páginas
- [x] Test de que la generación no depende de la red central (REQ-FN-017)
- [x] `cd backend && uv run pytest -q tests/test_ticket_service.py` en verde
- [x] El total de tests backend ha subido respecto a 362 y **todo lo demás sigue
      verde**

---

## 5. T5 — Tests de peldaños (rojo primero)

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-010, REQ-FN-011, REQ-FN-015 |
| **Depende de** | T4 |
| **Duración** | ~20 min |

### Qué hace

**Solo tests, en rojo.** Ninguna implementación. Orden de escritura dentro de la
tarea (rojo primero, según `plan.md §7.3`):

| # | Test | Por qué este primero |
|---|------|----------------------|
| 1 | `PEQUENO` arranca la escalera en **7.5** y no trunca | El requisito más fuerte y el más fácil de romper |
| 2 | `GRANDE` + 4 por hoja ⇒ **comportamiento intacto** | Distingue el filtro (correcto) de reemplazar el primer elemento (incorrecto) |
| 3 | `MEDIANO` arranca en **9.0** | Cubre el tercer peldaño |
| 4 | Orden descendente y piso preservado | REQ-FN-011 |
| 5 | `AUTOMATICO` no cambia nada (reforza T4) | |
| 6 | `PEQUENO` + `POS_58` + 4 por hoja (CE-04): nunca trunca | Caso límite de `spec.md §7` |
| 7 | TXT ignora la tipografía (REQ-FN-013) | `generar_ticket_txt` (`:1567`) no recibe fuente ni la recibirá |
| 8 | Fallback Helvetica si DejaVu no registra (REQ-FN-016) | `_registrar_ttf` (`:389,424-428`) |

**Casos clave con el diseño por filtrado** (`plan.md §4.1`). `escala_candidatas` son
**4 escaleras** de 11/10/10/9 elementos, con primeros valores 10.5 / 9.5 / 8.5 / 8.0:

| Paso | n=1 | n=2 | n=3 | n=4 |
|------|-----|-----|-----|-----|
| `GRANDE` (10.5) | 10.5 → 5.5 | 9.5 → 5.0 | 8.5 → 4.0 | 8.0 → 4.0 |
| `MEDIANO` (9.0) | **9.0** → 5.5 | **9.0** → 5.0 | 8.5 → 4.0 | 8.0 → 4.0 |
| `PEQUENO` (7.5) | **7.5** → 5.5 | **7.5** → 5.0 | **7.5** → 4.0 | **7.5** → 4.0 |
| `AUTOMATICO` | 10.5 → 5.5 | 9.5 → 5.0 | 8.5 → 4.0 | 8.0 → 4.0 |

Fíjate en la fila `GRANDE`: con 4 por hoja la escalera **no cambia** (8.0 ≤ 10.5) →
es exactamente lo que exige CE-05 («comportamiento idéntico al actual»). Y en
`PEQUENO`, con 4 por hoja la escalera **sí** arranca en 7.5 → es lo que exige CE-04.
**Ningún otro diseño satisface los dos.**

### Hecho cuando:

- [ ] Los tests existen y **fallan en rojo** por la razón correcta (falta el peldaño
      inicial), no por un error de sintaxis o de importación
- [ ] `PEQUENO` con `boletos_por_hoja=4` arranca en 7.5 (CE-04)
- [ ] `GRANDE` con `boletos_por_hoja=4` **no** cambia nada (CE-05)
- [ ] `AUTOMATICO` es idéntico al baseline de T4
- [ ] El piso de cada escalera se preserva (el fallback de
      `ticket_service.py:1171-1173` sigue siendo válido)
- [ ] TXT y el fallback Helvetica están cubiertos
- [ ] **Ningún fichero de producción ha sido modificado** en esta tarea

---

## 6. T6 — Implementación del peldaño inicial

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-010, REQ-FN-011, REQ-FN-013, REQ-FN-015, REQ-FN-016, REQ-FN-021, REQ-FN-022 |
| **Depende de** | **T5 Y T4 completada** |
| **Duración** | ~25 min |

### 🔒 `T4 ──precede──> T6` (restricción dura)

**No paralelizar T4 con T6.** «Escribir el test de T4» y «tener el baseline válido»
son estados distintos: T6 solo puede empezar cuando el test de T4 **pasa contra el
código sin tocar**.

### Qué hace

En `backend/app/services/ticket_service.py`:

1. **Extraer `_ESCALAS_ACTUALES`** como constante de módulo con los valores
   actuales **intactos** (11/10/10/9). Mover la tabla de un literal local a una
   constante con nombre **no cambia el comportamiento**.
2. **Función pura `escalera_efectiva(hoy, paso_configurado)`** (`plan.md §4.1`):
   con `AUTOMATICO` devuelve `hoy` **idéntico** (identidad); con un paso, filtra
   cada escalera por el techo. Testeable sin ReportLab ni BD.
3. **Leer el paso** con `getattr(empresa, "tamano_ticket_pdf", "AUTOMATICO")`.
   **`getattr` es obligatorio, no opcional**: los tests existentes construyen la
   empresa con `SimpleNamespace` (`test_ticket_service.py:139-152`, usada en **20**
   llamadas) ⇒ el acceso directo lanzaría `AttributeError` en 20 tests. Es el mismo
   patrón que ya usa el módulo en `:447`.
4. **Una línea cambiada** en `_build_pdf`: la asignación de `escala_candidatas` pasa
   a usar `escalera_efectiva`. El doble bucle, `_caben()` y el fallback **no se
   tocan**.

### Lo que esta tarea NO toca

| No tocar | Por qué |
|----------|---------|
| `pesajes.py` | `get_weighing_pdf` ya pasa `empresa=empresa` (`:507-523`) |
| `generar_ticket_txt` / `_build_txt` | REQ-FN-013: el TXT es texto plano |
| `_caben()`, el doble bucle, el fallback | La garantía de no truncar está repartida entre los tres |
| `printer_preset.dart` | REQ-FN-021: sigue siendo la autoridad sobre papel/márgenes/copias |
| La fuente | REQ-FN-014: **solo** DejaVu; `FUENTE`/`FUENTE_BOLD` (`:71-72`) no cambian |
| El docstring de `_estilos_simples` | Dice «3 → 9.0 \| 4 → 8.5» y el código real es 8.5/8.0 (`plan.md` #8). Si se toca, es documentación explícita del valor real, **no** un arreglo en silencio |
| Boletos existentes | REQ-FN-022: solo cambia la generación futura |

### Hecho cuando:

- [ ] `AUTOMATICO` produce un PDF con **texto extraído idéntico** al baseline de T4
      (REQ-FN-012)
- [ ] Los tests de T5 pasan **todos** (de rojo a verde)
- [ ] `PEQUENO` arranca en 7.5 en las 4 variantes de `boletos_por_hoja`
- [ ] `GRANDE` + 4 por hoja no altera el resultado (CE-05)
- [ ] Ningún boleto existente cambia: no hay migración de datos ni `UPDATE`
- [ ] `PrinterPreset` sin campos de fuente (REQ-FN-021)
- [ ] La fuente sigue siendo solo DejaVu (REQ-FN-014)
- [ ] Fallback Helvetica intacto (REQ-FN-016)
- [ ] `cd backend && uv run pytest -q` en verde (362 → 362 + los nuevos)
- [ ] `uv run ruff check app tests` y `uv run mypy tests/` sin hallazgos

---

## 7. T7 — i18n es/en/pt con paridad + controlador local de tipografía

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-005, REQ-FN-007, REQ-FN-019 |
| **Depende de** | T1 (gate) |
| **Duración** | ~25 min |

### Qué hace

1. **`frontend/lib/core/i18n/translations.dart`**: claves nuevas en **los 3
   diccionarios** — `es` (`:12-752`), `en` (`:753-1473`), `pt` (`:1474-2204`).
   Prefijo nuevo `typo_*` para no colisionar con `theme_system` (`:38`), que ya
   existe para el modo de tema. Incluye las **5 familias** de REQ-FN-007
   (`Sistema (por defecto)`, `Sans Serif`, `Serif`, `Monospace`, `Roboto`).
2. **`frontend/lib/core/theme/typography_controller.dart`** (archivo nuevo):
   `ChangeNotifier` paralelo a `ThemeController` (35 líneas,
   `theme_controller.dart:6-35`), con la familia de UI y el factor 0.85–1.40, y
   **clamp** de lectura por si el valor guardado en preferencias está corrupto
   (patrón `index.clamp(...)` de `:26`).
3. **`frontend/lib/data/datasources/local/local_storage.dart`**: persistencia con el
   patrón de `PrinterPreset` — clave `static const` (`:24`) y
   `setString(jsonEncode(...))` / `getString` con default (`:116-128`).
   **Ruta real verificada**: `lib/data/datasources/local/`, **no**
   `lib/core/services/` (`plan.md` #6).
4. **`main.dart:42`**: crear el controlador como `final` de nivel superior, igual
   que `themeController`, y sumarlo al `Listenable.merge` de `:211`.

### Hecho cuando:

- [ ] Las claves nuevas existen en **es, en y pt** con traducción real (no la clave
      como valor)
- [ ] `cd frontend && flutter test test/unit/i18n_test.dart` en verde — el test de
      paridad es `:55-70` y sigue comprobando igualdad exacta de los 3 conjuntos
- [ ] Ninguna clave queda vacía (mismo fichero, `:72-79`)
- [ ] El factor se persiste y **se restaura en el siguiente arranque**
      (REQ-FN-005)
- [ ] Un valor corrupto en preferencias no rompe la app (cae al default)
- [ ] El factor se mantiene dentro de [0.85, 1.40]
- [ ] `cd frontend && flutter analyze` limpio — **los warnings son error**
      (`AGENTS.md` v3.11)
- [ ] Los 15 `fontFamily` con `'monospace'` **siguen monoespaciados** (H-7: cifra
      verificada; 12 directos + 3 ternarias)

---

## 8. T8 — Tests de `textScaler` + clamp + iconos (rojo primero)

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-001, REQ-FN-002, REQ-FN-002b, REQ-FN-003 |
| **Depende de** | T7 |
| **Duración** | ~20 min |

### Qué hace

**Solo tests, en rojo.** Plantilla de estilo: **no existe**
`theme_controller_test.dart`; se copia `locale_controller_test.dart:11-13`
(`TestWidgetsFlutterBinding.ensureInitialized()` +
`SharedPreferences.setMockInitialValues({})`) (`plan.md` #7).

| # | Test | Verifica |
|---|------|----------|
| 1 | factor 0.85 aplicado | extremo inferior del selector |
| 2 | factor 1.40 aplicado | extremo superior del selector |
| 3 | **clamp a 1.60** con factor externo de 2.0 | REQ-FN-002b: el clamp acota lo externo, no lo que eligió el operador |
| 4 | el selector **nunca** produce > 1.40 aunque el clamp sea 1.60 | el clamp no limita la elección del operador |
| 5 | `iconTheme` escala con el factor | REQ-FN-003 (hoy **no existe ningún `iconTheme`**: 0 resultados en todo `frontend/lib/`) |
| 6 | familia aplicada al `textTheme` | REQ-FN-001 |
| 7 | `factor = 1.0` reproduce el comportamiento actual | no-regresión: `factor_efectivo(1.0, 1.0) == 1.0` |
| 8 | los `fontSize:` fijos escalan | REQ-FN-002 sobre los 322 literales |

### Hecho cuando:

- [ ] Los tests existen y **fallan en rojo** por la razón correcta
- [ ] El clamp se prueba con un factor externo **superior a 1.60**
- [ ] Hay un test explícito de que el selector **no** puede pasar de 1.40
- [ ] `factor = 1.0` es una demostración de no-regresión
- [ ] **Ningún fichero de producción ha sido modificado** en esta tarea

---

## 9. T9 — Implementación: clamp técnico, `textScaler`, escalado de iconos

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-001, REQ-FN-002, REQ-FN-002b, **REQ-FN-002c**, REQ-FN-003, REQ-FN-004, REQ-FN-006 |
| **Depende de** | T8 |
| **Duración** | ~25 min |

### ⚠️ Corrección obligatoria respecto a la spec —Gap cerrado, noystery

`REQ-FN-002b` nombra `MediaQuery.clampTextScaler`. **Ese método no existe en el
SDK de este proyecto** (Flutter 3.47.2): `grep -rn "clampTextScaler"` sobre
`packages/flutter/lib/` → **0 resultados**. Las APIs reales son
`MediaQuery.withClampedTextScaling` (`media_query.dart:1503`) y
`TextScaler.clamp` (`text_scaler.dart:62`). Ver `plan.md §5.2` y `plan.md` #1.

**El criterio de aceptación del requisito no cambia** (clamp de [0.85, 1.60]); solo
cambia la API que lo expresa.

**`REQ-FN-002c` (nuevo, `spec.md` H-15):** al elegir el enfoque (A) —un wrapper
propio que multiplica el factor del operador por el escalado del SO— la clase
**debe implementar los tres** miembros de la interfaz `TextScaler`:

| Miembro | Estado | Nota |
|---------|--------|------|
| `scale` | abstracto | lógica propia: `interno.scale(fs) * factor` |
| **`clamp`** | **abstracto en esta versión** (`text_scaler.dart:62`) | ** delegar en `interno.clamp(...)`**. Sin él **no compila** |
| `textScaleFactor` | abstracto **y** `@Deprecated` (`:54-58`) | implementar con `// ignore: deprecated_member_use` **obligatorio** |

### Qué hace

1. **`main.dart:212`**: añadir un `builder:` al `MaterialApp` que
   (a) acota el `textScaler` heredado con `.clamp(minScaleFactor: 0.85,
   maxScaleFactor: 1.60)` y (b) compone encima el factor del operador mediante
   el wrapper de (A), con los **tres** miembros de `REQ-FN-002c`.
2. **`app_theme.dart`**: `buildLightTheme()` (`:60`) y `buildDarkTheme()` (`:146`)
   pasan a **aceptar parámetros** (hoy no aceptan ninguno) y **ganan `iconTheme`**
   (hoy no existe ninguno). Aplicar la familia al `textTheme`.
3. **`main.dart:217-218`**: pasar los parámetros en las 2 llamadas existentes.

### ✅ `[VERIFICAR]` resuelto — **no** abrir la opción (B)

La incógnita era si (A) dispara avisos y si la supresión acotada basta.
**Comprobado compilando una subclase real** (`flutter analyze`):

| Miembros implementados | `flutter analyze` | exit |
|---|---|:--:|
| `scale` + `textScaleFactor` sin `clamp` | `error Missing concrete implementation of 'TextScaler.clamp'` | **1** |
| los 3, **sin** `// ignore` | `info deprecated_member_use` | **1** |
| los 3, **con** `// ignore: deprecated_member_use` | **`No issues found!`** | **0** |

Conclusión: **la supresión es obligatoria, no un recurso de último recurso.** La
degradación a la opción (B) queda **descartada**; no se pierde el escalado no
lineal del SO.

### Hecho cuando:

- [ ] Los tests de T8 pasan **todos**
- [ ] Un factor externo de 2.0 se ve acotado a **1.60**
- [ ] El factor del operador llega a **1.40** sin que el clamp lo recorte
- [ ] Los 322 `fontSize:` hardcodeados escalan **sin tocar ninguno**
- [ ] Los iconos de `AppBar`, botones y navegación escalan
- [ ] El cambio se aplica **sin reiniciar** la app (REQ-FN-004)
- [ ] Una familia no instalada **no falla ni muestra error** (REQ-FN-006)
- [ ] `cd frontend && flutter analyze` → `No issues found!`
- [ ] El wrapper `TextScaler` implementa **`scale` + `clamp` + `textScaleFactor`**, con
      `// ignore: deprecated_member_use` **solo** en `textScaleFactor` (REQ-FN-002c)
- [ ] `cd frontend && flutter test` en verde (158 → 158 + los nuevos)
- [ ] Los 15 `fontFamily` con `'monospace'` siguen intactos (cifra verificada)

---

## 10. T10a — Pantalla de ajustes (selector + i18n)

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-001, REQ-FN-003, REQ-FN-006, REQ-FN-007, REQ-FN-019 |
| **Depende de** | T9 |
| **Duración** | ~20 min |

### ⚙️ AJUSTE #3 incorporado: T10 se divide

La estimación de 30 min para T10 era corta: son **dos** unidades de trabajo con
riesgos distintos (una pantalla con i18n vs. una batería de pruebas de layout en
extremos). Se divide en **T10a** (pantalla + i18n) y **T10b** (overflow + contraste).
Desglose aprobado: **10 → 11 tareas**.

### Qué hace

1. **`frontend/lib/presentation/screens/settings/typography_settings_screen.dart`**
   (archivo nuevo): selector de **familia** (las 5 de REQ-FN-007) y de **tamaño**
   (0.85–1.40), y selector del **paso del ticket** (`AUTOMATICO` / `GRANDE` /
   `MEDIANO` / `PEQUENO`), este último **solo para ADMIN**.
2. **Patrón a copiar**: `_ThemeSelector` (`settings_screen.dart:1419-1445`) —
   `AnimatedBuilder(animation: controller, builder: …)` + `RadioGroup` +
   `RadioListTile(dense: true)`.
3. **Entrada en el hub**: 1 punto en la tarjeta "Apariencia e Idioma"
   (`settings_screen.dart:204-212`).
4. **Selector del ticket → `PUT /api/v1/empresa`** (solo ADMIN), leyendo con
   `GET /api/v1/empresa`.

### Lo que esta tarea NO toca

| No tocar | Por qué |
|----------|---------|
| Los 7 títulos hardcodeados del hub | H-8 / `spec.md §4.2` punto 7: ítem aparte. La entrada nueva **sí** se traduce; corregir las existentes es otro trabajo |
| Los `fontSize:` hardcodeados | `spec.md §4.2` punto 4 |
| La dependencia `google_fonts` | `spec.md §4.2` punto 6: declarado en `pubspec.yaml:47` con **0** usos en `lib/`; retirarla es un cambio con su propio radio de impacto |
| `ticket_preview_dialog.dart` | `spec.md §4.2` punto 8: el preview usa Roboto (`:517`, `:671`) y el PDF DejaVu; no se pueden alinear |
| `PrinterPreset` | REQ-FN-021 |

### Hecho cuando:

- [x] La pantalla ofrece las **5 familias** de REQ-FN-007 con etiquetas en es/en/pt
- [x] El tamaño ofrece el rango 0.85–1.40 y se aplica **sin reinicio** — dentro de
      la pantalla; la aplicación global es de T9 y sigue pendiente (ver Resultado)
- [x] El paso del ticket se guarda vía `PUT /api/v1/empresa` y se **relee** con
      `GET /api/v1/empresa`
- [x] El selector del ticket **solo** se ve para ADMIN (el `PUT` ya devuelve 403 para
      los demás: `test_preferencias_empresa.py:109-114`)
- [x] `cd frontend && flutter test test/unit/i18n_test.dart` en verde (paridad)
- [x] `cd frontend && flutter analyze` limpio
- [x] El hub no ha ganado literales en español nuevos

### Resultado (2026-10-05)

- **Tests**: 16 nuevos — 5 del controlador, 1 de i18n y **10 de widget** para la
  pantalla (`test/widget/typography_settings_screen_test.dart`, con `ApiClient`
  falso que guarda lo que recibe por `PUT` y lo devuelve por `GET`). Frontend
  **162 → 178** en verde; `flutter analyze` → `No issues found!`.
- **Hueco 1 cerrado (REQ-FN-007)**: `TypographyController` gana `familiaUi`
  (`SharedPreferences`, clave `app.familiaUi`), `setFamiliaUi`,
  `familiaUiFontFamily` y las listas `familiasUi` / `tamanosTicket`. Los
  identificadores de familia son internos (`SISTEMA`, `SANS_SERIF`, `SERIF`,
  `MONOSPACE`, `ROBOTO`) y el controlador es quien los traduce a `fontFamily`
  (`null` / `sans-serif` / `serif` / `monospace` / `Roboto`): la pantalla no
  contiene **ningún** nombre de fuente y la cifra de `fontFamily` con
  `'monospace'` sigue en **15** —12 literales `fontFamily: 'monospace'` y 3
  ternarias—, verificado con el mismo patrón amplio de H-16 para no repetir el
  error de estrecharlo. H-7 intacto. Una preferencia corrupta —y un
  `tamanoTicketPdf` corrupto— caen al valor por defecto sin romper el arranque.
- **Hueco 2 cerrado**: `_guardarTamanoTicketEnEmpresa()` hace
  `PUT /api/v1/empresa` con `tamano_ticket_pdf` y **vuelve a leer** con
  `GET /api/v1/empresa`; lo que se
  muestra es lo que quedó guardado, no lo que se pidió (el servidor es la
  autoridad del PDF). Al abrir, la pantalla también relee el valor de la empresa
  (`addPostFrameCallback`, cuando el `AuthBloc` ya está resuelto). **Ningún
  `catch` mudo**: `PUT`/`GET` fallidos dan `SnackBar` + `debugPrint`, y el valor
  local se conserva con un aviso que dice que **los boletos siguen con el tamaño
  anterior** (no promete una sincronización que no existe: H-4).
- **Hueco 3 cerrado**: el `SegmentedButton` del ticket va dentro de
  `if (_esAdmin)`, con el patrón `context.select<AuthBloc, String?>` de
  `settings_screen.dart:1005-1012`. Para un rol distinto de ADMIN no se hace
  ninguna llamada: ni `PUT` (que daría 403) ni `GET`. La tarjeta informativa de
  la fuente **sí** se ve para todos: informa, no configura.
- **i18n**: 14 claves nuevas `tipografia_*` en los **3** idiomas, **656 claves
  por idioma** (629 en `HEAD` + 13 de T7 + 14 de T10a). Traducción real, nunca la
  clave como valor: p. ej. `tipografia_familia_monospace` es `Monospace` en es/en
  y **`Monoespaçada`** en pt, y el test lo verifica para que una traducción
  ausente disfrazada de copia en español no pase por buena.
- **Decisión 1 — etiquetas del hub**: la entrada que **ya existía** en
  `settings_screen.dart` (escritorio `:215-232` y móvil `:346-357`) pasa de
  `tipografia_ticket_titulo` / `tipografia_ticket_scale` a `tipografia_titulo` /
  `tipografia_subtitulo`. Motivo: la tarjeta se titulaba «Tamaño y fuente del
  ticket PDF» y abre una pantalla que además configura la interfaz. Son 4
  sustituciones de clave, **cero literales nuevos** en el hub y **sin tocar** los
  7 títulos hardcodeados que la tarea excluye. Las dos claves viejas quedan sin
  uso en `lib/` (no se borran: son datos de i18n, no código).
- **Decisión 2 — vista previa**: la tarjeta de familia muestra un espécimen
  (`AaBbCc 0123456789`) con la familia elegida, porque la familia **todavía no se
  aplica a la app**: T9 no está hecha. Sin ella, elegir una familia no se vería
  cambiar nada y el control parecería roto.
- **Hallazgo — T9 sigue pendiente**: `app_theme.dart` no acepta parámetros ni
  aplica la familia al `textTheme`, y `main.dart` no compone el `TextScaler` en el
  `MaterialApp`. Por eso «se aplica sin reiniciar» es cierto **dentro** de esta
  pantalla (el controlador actualiza al instante, sin reinicio ni diálogo) y
  pendiente **fuera** de ella. Es trabajo de T9, no de T10a. De paso:
  `ClampedTextScaler` y `TextScalerProvider` usan un techo de **1.50**, no el
  `[0.85, 1.60]` de REQ-FN-002b.
- **Verificado en negativo**: saboteando la validación de `load()` y
  `setFamiliaUi`, los 2 tests de familia fallan; mostrando el `SegmentedButton`
  a todos los roles, o quitando el `GET` posterior al `PUT`, fallan los 2 tests
  correspondientes del widget test.

---

## 11. T10b — Tests de overflow en extremos + contraste

| Campo | Contenido |
|-------|-----------|
| **RF que cubre** | REQ-FN-001, REQ-FN-002, REQ-FN-003, REQ-FN-006, REQ-FN-007, REQ-FN-008, REQ-FN-019, REQ-FN-020 |
| **Depende de** | T10a |
| **Duración** | ~15 min |

### Qué hace

Verificación de REQ-FN-008 (el requisito que T1 **informó**) y de REQ-FN-020, en el
harness de `integration_test/` que T1 dejó montado.

| # | Caso | Verifica |
|---|------|----------|
| 1 | Las 4 pantallas críticas a **1.40**, tema claro | REQ-FN-008 / CE-02 |
| 2 | Las 4 pantallas críticas a **0.85**, tema oscuro | REQ-FN-008 / CE-01 |
| 3 | Contraste **AA** en las etiquetas del ajuste, tema claro **y** oscuro | REQ-FN-020 |
| 4 | Cambio de idioma con el tamaño en el extremo | REQ-FN-019 / CE-11 |
| 5 | Familia `Serif` no instalada | REQ-FN-006 / CE-03: cae a la del sistema sin error |
| 6 | Iconos escalados proporcionalmente | REQ-FN-003 |

### Hecho cuando:

- [x] `overflow_count == 0` en las 4 pantallas a **1.40** (CE-02)
- [x] `overflow_count == 0` en las 4 pantallas a **0.85** con tema oscuro (CE-01)
- [x] Contraste AA verificado en claro y oscuro con cualquier tamaño del rango
- [x] Cambio de idioma en el extremo: etiquetas traducidas **y** sin overflow (CE-11)
- [ ] `Serif` inexistente: sin error y sin diálogo (CE-03) — **BLOQUEADO por un
      desborde real; ver abajo**
- [x] Si aparece **cualquier** overflow: **PARAR y aplicar el procedimiento de §1**;
      **no** parchear los layouts (`spec.md §4.2` punto 4) — el procedimiento se
      aplicó: se reproductió, se/localizó el factor y la familia, y **no** se
      tocó ningún layout
- [x] `cd frontend && flutter analyze` limpio
- [ ] `cd frontend && flutter test` en verde — bloqueado por el caso 5

### Resultado: 🛑 **T10b NO pasa** — 5 de 6 casos verdes, el caso 5 encuentra un
### desborde real

| Caso | Veredicto | Evidencia |
|------|:---------:|-----------|
| 1 · 4 pantallas a 1.40, tema claro | ✅ | `overflow_count: 0`, las 4 pantallas alcanzadas, 12/12 etiquetas leídas |
| 2 · 4 pantallas a 0.85, tema oscuro | ✅ | `overflow_count: 0`, `factor_efectivo=0.85`, `tema=dark` en las 4 pantallas |
| 3 · Contraste AA claro y oscuro | ✅ | 15.43:1 (claro) y 14.00:1 (oscuro) contra el mínimo AA de 4.5:1 |
| 4 · es/en/pt en el extremo | ✅ | `overflow_count: 0` y las 12 etiquetas leídas **en los tres idiomas** |
| 5 · familia `Serif` | 🛑 | **`RenderFlex overflowed by 60 pixels on the right`** en Ajustes |
| 6 · Iconos escalados | ✅ | Lineal en 41 muestras de [0.85, 1.40]; renderizado 17/20/28 px |

Reproducible: el desborde del caso 5 apareció en **dos** corridas completas y en
una corrida aislada del caso 5.

#### El desborde (el motivo del 🛑)

| Dato | Valor |
|------|-------|
| Pantalla | Ajustes (`ajustes`) |
| Factor del selector | **1.40** (factor efectivo medido en el árbol: `1.4`) |
| Factor del SO | 1.0 |
| Familia de UI | **`SERIF`** |
| Mensaje exacto | `A RenderFlex overflowed by 60 pixels on the right.` |
| Ocurrencias | 2 (la pantalla se construye dos veces al navegar) |

**Por qué solo con `Serif`:** los casos 1 y 4 recorren la misma pantalla a 1.40
con la familia del sistema y dan `overflow_count: 0`. La familia serif ocupa más
anchura de glifo al mismo tamaño, y eso es lo que desborda. El defecto lo hace
**alcanzable** el selector de familias de REQ-FN-007; no existía antes de este
spec, pero ahora un operador lo provoca con un toque.

**Lo que NO se ha hecho, y por qué:** el `Row` culpable **no** está identificado.
Se revisaron a mano los `Row` de `settings_screen.dart` (líneas 276, 592, 705,
734, 857, 1142, 1164, 1431, 1504) y los dos de `app_sidebar.dart`: todos usan
`Expanded`, `Flexible` o `Spacer`, y el único sin flex (1504, el encabezado de
«Idioma») lleva un texto de una palabra que no puede exceder 60 px. El volcado
del árbol de render tomado en el momento del desborde **no** lo identifica
(`debugDumpRenderTree` se ejecuta antes del relayout, así que el `RenderFlex`
todavía no marca `OVERFLOWING`; en la versión de Flutter de este repo la cadena
sale como `during layout`). Parchear sin saber cuál es sería adivinar, que es
justo lo que `spec.md §4.2` punto 4 prohíbe. **Queda pendiente identificarlo** con
un widget test que monte la pantalla con los datos reales (empresa, licencia,
conexión) en vez de con los dobles de `settings_screen_test.dart`, que con datos
falsos **no** reproducen el desborde.

#### Bugs reales corregidos por T10b

1. **`setState() called during build` al abrir Ajustes → Tipografía.**
   `TypographyController.load()` notificaba siempre, aunque no cambiara nada, y se
   llama desde el `initState` de la pantalla y desde el de la app: marcaba como
   sucio el `ListenableBuilder` de `TipografiaScope` **durante el build** y
   Flutter lanzaba la aserción. Salía en cada apertura de la pantalla. Corregido
   en `typography_controller.dart`: `load()` notifica solo si un valor cambió de
   verdad. Regresión fijada en
   `test/core/controllers/typography_controller_clamp_test.dart` (verificada en
   rojo con una mutación que devuelve el `notifyListeners()` incondicional).

2. **El `overflow_count: 0` del caso 2 era inicialmente falso.** El primer intento
   del harness reportaba `factor_efectivo=1.4` en el caso de factor 0.85, porque
   `TypographyController` es un singleton *lazy* que captura `AppConfig.prefs` al
   construirse y el contenedor de dependencias no se rehacía entre casos: el caso
   2 medía el factor del caso 1. Es la misma clase de defecto que dejó el `0`
   falso de T1. El harness ahora **mide** el factor efectivo en el árbol montado y
   falla si no es el del caso (`factorEfectivo()`), y reconstruye el controlador
   por caso (`_reconstruirTipografia`).

#### Ficheros de T10b

| Fichero | Qué es |
|---------|--------|
| `integration_test/t10b_harness.dart` | Recorrido, captura de overflows y medición del factor/tema efectivo |
| `integration_test/t10b_test.dart` | Los 4 casos E2E (1, 2, 4 y 5) con su veredicto |
| `test/typography/t10b_contrast_test.dart` | Caso 3: contraste AA en claro y oscuro (5 tests) |
| `test/typography/t10b_iconos_test.dart` | Caso 6: linealidad y extremo inferior (4 tests) |

Los casos 3 y 6 no son E2E porque son propiedades del tema, no de una pantalla.
El subtítulo del hub («Familia, tamaño y ticket PDF») no se comprueba aquí: es
de Ajustes, no de la pantalla de tipografía, y la hub ya queda registrada como
pantalla `ajustes`.

**Comando:** `cd frontend && DISPLAY=:0 flutter test
integration_test/t10b_test.dart -d linux` (el entorno E2E debe estar levantado:
`cd backend && bash scripts/e2e_flutter.sh up`).

---

## 12. Cobertura RF → tarea

| RF | Descripción corta | Tareas | ¿Cubierta? |
|----|-------------------|--------|:----------:|
| REQ-FN-001 | Familia de UI aplicada a todos los textos | T8, T9, T10a, T10b | ⚠️ Ajustes desborda 60 px con `Serif` a 1.40 (T10b caso 5) |
| REQ-FN-002 | Factor 0.85–1.40 sobre los textos, incluidos los fijos | T8, T9, T10b | ✅ |
| REQ-FN-002b | Clamp técnico [0.85, 1.60] | T1, T8, T9 | ✅ |
| REQ-FN-003 | Iconos escalados proporcionalmente | T8, T9, T10a, T10b | ✅ |
| REQ-FN-004 | Cambio sin reinicio | T9 | ✅ |
| REQ-FN-005 | Persistencia por dispositivo | T7 | ✅ |
| REQ-FN-006 | Familia no disponible → default, sin error | T9, T10b | ⚠️ El comportamiento es correcto; T10b caso 5 no cierra por el desborde asociado |
| REQ-FN-007 | 5 familias mínimas | T7, T10a, T10b | ⚠️ Las 5 existen y se aplican; falta el layout de Ajustes para `Serif` a 1.40 |
| REQ-FN-008 | Sin overflow en 4 pantallas en los extremos | T1, T10b | ⚠️ Verificado en ambos extremos **con la familia del sistema**; con `Serif` a 1.40 hay un desborde |
| REQ-FN-009 | Persistencia por `id_empresa` | T2, T3 | ✅ |
| REQ-FN-010 | El paso configurado es el peldaño inicial | T5, T6 | ✅ |
| REQ-FN-011 | Orden descendente y nada truncado | T5, T6 | ✅ |
| REQ-FN-012 | `AUTOMATICO` → texto extraído idéntico | T4, T6 | ✅ |
| REQ-FN-013 | TXT ignora la tipografía | T5, T6 | ✅ |
| REQ-FN-014 | Solo DejaVu | T3, T6 | ✅ |
| REQ-FN-015 | Peldaños 10.5 / 9.0 / 7.5 | T5, T6 | ✅ |
| REQ-FN-016 | Fallback Helvetica sin fallar | T5, T6 | ✅ |
| REQ-FN-017 | PDF sin red central | T4 | ✅ |
| REQ-FN-018 | Aislamiento entre empresas | T3 | ✅ |
| REQ-FN-019 | Paridad es/en/pt | T7, T10a, T10b | ✅ |
| REQ-FN-020 | Contraste AA claro/oscuro | T10b | ✅ |
| REQ-FN-021 | `PrinterPreset` intacto | T6 | ✅ |
| REQ-FN-022 | Ningún boleto existente alterado | T6 | ✅ |

### Verificación: 23/23 declarados, sin huérfanos; 4 con nota de T10b

⚠️ Las 4 filas con nota están **declaradas y asignadas a una tarea, pero su
verificación quedó incompleta** por el desborde del caso 5 de T10b (`§11`). No es
un requisito huérfano: es un requisito **a medio verificar**. El detalle está en
`§11`, no aquí, para no duplicar el informe.

**23 requisitos** declarados en `spec.md §5` (001, 002, 002b, 003, 004, 005, 006,
007, 008, 009, 010, 011, 012, 013, 014, 015, 016, 017, 018, 019, 020, 021, 022)
coinciden con las **23 filas** de la tabla.

| Comprobación | Resultado |
|--------------|-----------|
| RF declarados en la spec | 23 |
| RF con al menos una tarea | 23 |
| **Huérfanos** (RF sin tarea) | **0** |
| **Tareas sin RF** (cada tarea cubre ≥1) | **0** — las 11 tareas tienen RF asignado |

**Ningún requisito queda sin cubrir.** No hay que reportar huecos.

**Nota sobre REQ-FN-012**: se declara cubierto por T4 (el baseline) **y** T6 (que lo
consume). La pareja es inseparable por diseño: T4 crea el control, T6 lo somete a
prueba. Si T6 se ejecutara sin T4, REQ-FN-012 quedaría *declarado* pero no
*verificado*.

---

## 13. Comandos de verificación

```bash
# ── Backend ────────────────────────────────────────────────────────────────
cd backend
uv run pytest -q                     # 362 + los nuevos, en verde
uv run ruff check app tests          # line-length 100
uv run mypy tests/

# Fallback si `uv` no está en PATH (AGENTS.md lo advierte; en esta máquina sí lo está):
backend/.venv/bin/python -m pytest -q

# ── Frontend ───────────────────────────────────────────────────────────────
cd frontend
flutter test
flutter analyze                     # los warnings son ERROR (AGENTS.md v3.11)

# ── E2E de UI (necesario para T1 y T10b) ───────────────────────────────────
cd backend && bash scripts/e2e_flutter.sh up
cd frontend
flutter test integration_test/pesaje_flow_test.dart -d linux    # local: DISPLAY=:0
# en CI: xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux
```

**Cifras de referencia verificadas antes de empezar** (`plan.md §7.2`):

| Medida | Valor | Origen |
|--------|-------|--------|
| Tests backend totales | **362** | `uv run pytest -q --collect-only` → `362 tests collected in 1.28s` |
| Tests en los 2 ficheros a tocar | **63**, verdes | `uv run pytest -q tests/test_ticket_service.py tests/test_preferencias_empresa.py` → `63 passed in 9.12s` |
| Tests frontend | 158 | `AGENTS.md` §Tests — **`[VERIFICAR]`** con `flutter test` |

---

**Fin de `tasks.md` v1.0.** 11 tareas · 23/23 RF cubiertos · 0 huérfanos ·
restricción dura `T4 ──precede──> T6` · T1 `[GATE]` descartable con
reapertura de la pregunta 5 si `overflow_count > 0`. No se ha escrito código.
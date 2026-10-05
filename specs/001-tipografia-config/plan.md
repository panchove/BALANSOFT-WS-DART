# PLAN 001 — Ajuste de tipografía del sistema y del ticket

**Versión:** 1.0
**Fecha:** 2026-10-02
**Estado:** Plan aprobado para ejecución
**Autor:** Agente planificador
**Especificación:** `specs/001-tipografia-config/spec.md` v0.2 (aprobada por QA)
**Norma:** `docs/constitution.md`, `AGENTS.md`, `docs/MANEJO_DB.md`
**Fuente:** Verificación directa sobre el código (ver §9). No se usó documentación legacy.
**Código escrito:** ninguno. Este documento y `tasks.md` son los únicos artefactos.

---

## 1. Puntos de decisión bloqueantes

### 1.1 T1 `[GATE]` — Medición de desbordes antes de construir nada

**T1 es bloqueante y va primero.** Sin su resultado, el rango 85 %–150 % es una
suposición y el resto del trabajo construye sobre ella.

| Aspecto | Contenido |
|---------|-----------|
| Qué mide | Número de `RenderFlex overflowed` en las 4 pantallas críticas de `REQ-FN-008`, con el factor de escala en **1.40** (el extremo superior del selector) |
| Pantallas | 1) formulario de pesaje · 2) detalle del boleto · 3) panel principal · 4) pantalla de ajustes |
| Harness | `frontend/integration_test/` — el E2E existente (`pesaje_flow_test.dart:145`) ya hace `await tester.pumpWidget(const app.BalansoftApp())` sobre la app real a 1400×860 (`pesaje_flow_test.dart:103-104`). Reutiliza `di.init()`, `AppConfig` y el andamiaje `backend/scripts/e2e_flutter.sh` |
| Alternativa descartada | Widget tests unitarios con `pumpWidget` de cada pantalla aislada. **Descartada y verificada**: `weighing_form_screen.dart` tiene 4153 líneas y exige `CatalogBloc` (`weighing_form_screen.dart:193`); `dashboard_screen.dart` (894) y `weighing_detail_screen.dart` (1155) también consumen blocs. El test existente `weighing_detail_screen_test.dart` solo ejerce el estado vacío. Medir así no es medir la pantalla real |
| Cómo se mide | Contar eventos de `FlutterError`/excepciones con el texto `RenderFlex overflowed` durante el recorrido de las 4 pantallas; el resultado es un entero: `overflow_count` |
| Tiempo | ~25 min (incluye levantar el entorno E2E) |

**Criterio de salida (binario, sin interpretación):**

| `overflow_count` | Veredicto | Acción |
|:---:|---|---|
| **0** | ✅ **T1 pasa** | Se continúa a T2. El rango [0.85, 1.40] queda **ratificado** |
| **> 0** | 🛑 **PARAR** | **No** se avanza a T2 |

**Si `overflow_count > 0`, el procedimiento obligatorio es:**

1. **PARAR.** No commitear T1. **T1 es descartable**: su único entregable es el reporte.
2. Reportar, por cada ocurrencia: **pantalla**, **factor** (1.40) y el **mensaje exacto**
   `RenderFlex overflowed`, con el `RenderFlex` implicado.
3. **Reabrir la pregunta 5** de `spec.md §3` (rango del tamaño del sistema). El rango
   [0.85, 1.40] es una decisión, no un hecho; si el máximo no cabe, la decisión se
   revisa antes de seguir construyendo.
4. **No parchear T1.** No se ajustan paddings, `Flexible`, `isExpanded` ni alturas
   para forzar el verde. `spec.md §4.2` punto 4 excluye explícitamente el rediseño de
   layouts de altura fija: es un proyecto de refactor, no un ajuste.
5. El reporte se entrega al Encargado. La decisión sobre el rango la toma él.

### 1.2 T4 ──precede──> T6 (restricción dura, tratada en §2)

### 1.3 Puntos de decisión no bloqueantes

| # | Punto | Resolución |
|---|-------|-----------|
| D-a | ¿El PDF necesita un parámetro nuevo en la API? | **No.** `pesajes.py:495-523` ya inyecta `empresa: Empresa = Depends(get_current_empresa)` y lo pasa a `generar_ticket_pdf`. El backend lee el ajuste de su propia BD. §6.1 |
| D-b | ¿Hace falta sincronización offline? | **No** (`spec.md` H-4). El PDF lo genera el backend local, que es quien guarda el ajuste |
| D-c | ¿La tipografía del ticket entra en `PrinterPreset`? | **No** (REQ-FN-021). `printer_preset.dart:1-16` no tiene campos de fuente y sigue siendo la autoridad sobre papel, márgenes, copias y boletos por hoja |
| D-d | ¿`iconTheme` existe hoy? | **No.** `grep -rn "iconTheme\|IconThemeData" frontend/lib/` → **0 resultados**. REQ-FN-003 crea una superficie nueva, no modifica una existente. §6.4 |

---

## 2. Tabla de dependencias

```
T1  [GATE] ──┬──────────────────────────────► T7 ──► T8 ──► T9 ──► T10a ──► T10b
              │
              └─► T2 ─┬─► T3
                     │
                     └─► T4 ══╗
                            ║  ║
                            ║  ╚═════╦══► T5 ──► T6
                            ╚════════╝
```

| Tarea | Depende de | Bloqueada por |
|-------|-----------|---------------|
| **T1** `[GATE]` | — | nada |
| **T2** | T1 | gate |
| **T3** | T2 | |
| **T4** | T2 | |
| **T5** | T4 | |
| **T6** | **T5 Y T4 completada** | **`T4 ──precede──> T6`** |
| **T7** | T1 | gate |
| **T8** | T7 | |
| **T9** | T8 | |
| **T10a** | T9 | |
| **T10b** | T10a | |

### 🔒 Restricción dura: `T4 ──precede──> T6`

**T6 no puede empezar hasta que T4 esté completada.**

- **Motivo**: T6 es la primera tarea que **mueve la escalera de auto-fit**
  (`ticket_service.py:1142-1147`). T4 captura el **baseline** del PDF con
  `AUTOMATICO` (REQ-FN-012). Sin ese baseline congelado, cualquier cambio de T6
  es **indetectable**: un PDF degradado pasaría los tests porque ya no hay con qué
  compararlo. El baseline es el control, y un control que se toma *después* del
  cambio no es un control.
- **Prohibición explícita: T4 y T6 NO pueden ejecutarse en paralelo**, ni aunque
  T4 haya terminado de *escribir* el test: hace falta que el test **pase** contra
  el código sin tocar. "Escribir el test" y "tener el baseline válido" son estados
  distintos.
- **Cómo se verifica el cumplimiento**: T5 (tests de peldaños, rojo primero) puede
  empezar tras T4; T6 no. El orden real es T4 → T5 → T6.

**Otras restricciones de orden (no duras):**
- T3 y T4 pueden ir en paralelo entre sí (ambas cuelgan de T2 y tocan ficheros
  distintos: `schemas/__init__.py` + `empresa.py` frente a `test_ticket_service.py`).
- T7 no depende de la rama del ticket: puede avanzar en cuanto T1 libere el gate.

---

## 3. Archivos y responsabilidades por capa

### 3.1 Backend — capa Router

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `backend/app/api/v1/endpoints/empresa.py` | **Sin cambios.** `GET`/`PUT` iteran el payload con `setattr` sobre el objeto ya filtrado (`empresa.py:49-50`) y `EmpresaPerfilOut`/`EmpresaPerfilUpdate` se amplia en los schemas. Tocar el router sería redundante | T3 |
| `backend/app/api/v1/endpoints/pesajes.py` | **Sin cambios.** `get_weighing_pdf` ya pasa `empresa=empresa` (`pesajes.py:507-523`); `generar_ticket_txt` (`pesajes.py:542`) no recibe fuente y no la recibirá | T6 |
| `backend/app/api/dependencies.py` | **Sin cambios.** `get_current_empresa` ya filtra por `current_user.id_empresa` (`dependencies.py:52-58`) | T2/T3 |

### 3.2 Backend — capa Service

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `backend/app/services/ticket_service.py` | (**a**) Leer el paso configurado de `empresa` con `getattr` y default `AUTOMATICO`; (**b**) función pura que devuelve la escalera efectiva tratando *hoy* como parámetro; (**c**) aplicar la escalera devuelta al bucle existente sin reescribirlo | T6 |

### 3.3 Backend — capa Schema (Pydantic)

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `backend/app/schemas/__init__.py` | 2 campos nuevos en `EmpresaPerfilOut` (`Literal` + default) y 2 en `EmpresaPerfilUpdate` (`Literal` + `Field(None)`), siguiendo el patrón exacto de `idioma`/`formato_reporte` (`schemas/__init__.py:704-705` y `719-720`) | T3 |

### 3.4 Backend — capa Model

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `backend/app/models/__init__.py` | 2 columnas nuevas en `Empresa` (`:84-122`), tras `ruta_exportacion_reportes`, replicando `mapped_column(String(...), nullable=True, default=..., server_default=...)` | T2 |

> Las columnas viven en `empresas`, que **ya tiene `id_empresa` como PK**
> (`models/__init__.py:87-89`; `balansoft-ws-local.sql:40`). Constitución regla 1
> satisfecha por construcción: no hay tabla nueva ni columna nueva con `id_empresa`.

### 3.5 Backend — capa Migration

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `backend/migrations/021_*.sql` | **Archivo nuevo.** Patrón de `017_idioma_formato_reporte_empresa.sql`: `ADD COLUMN IF NOT EXISTS` ×2 → `UPDATE` de backfill a NULL → `SET DEFAULT` ×2 → bloque `DO`/`IF NOT EXISTS` con 2 `CHECK` sobre los `Literal` | T2 |
| `backend/balansoft-ws-local.sql` | **Reflejo en 2 sitios del mismo fichero**: las columnas en el `CREATE TABLE IF NOT EXISTS empresas` (`:39-61`) **y** los `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` del bloque de alineación (`:63-69`) | T2 |

> **Verificado en contra** (`spec.md` F1): el convenio *sí* es mantener ambos
> ficheros al día con las migraciones `ALTER`. Las 4 columnas de la 017
> (`idioma`, `formato_reporte`, `formato_ticket`, `ruta_exportacion_reportes`)
> están todas en el `CREATE TABLE` de `balansoft-ws-local.sql:49-52`.
> Por tanto 021 va en **ambos** ficheros. La omisión de `series_numeracion` que
> reporta F1 es de la migración 015 y está fuera de alcance.

> **Distribución**: las estaciones ya instaladas reciben la 021 automáticamente:
> `wserver.py:231-265` aplica `migrations/*.sql` **en cada arranque** usando el
> registro `schema_migrations`.

### 3.6 Backend — capa Tests

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `backend/tests/test_ticket_service.py` | Baseline de texto extraído (REQ-FN-012), escalera por peldaño (REQ-FN-010/011/015), no-dependencia de la red (REQ-FN-017) | T4, T5 |
| `backend/tests/test_preferencias_empresa.py` | Persistencia por `id_empresa` (REQ-FN-009), validación de enums (REQ-FN-014), aislamiento de `GET` y `PUT` (REQ-FN-018) | T3 |

### 3.7 Flutter — capa Presentation

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `frontend/lib/presentation/screens/settings/typography_settings_screen.dart` | **Archivo nuevo.** Selector de familia + tamaño de la UI, y selector del paso del ticket (solo ADMIN) | T10a |
| `frontend/lib/presentation/screens/settings/settings_screen.dart` | **1 punto de entrada** en la tarjeta "Apariencia e Idioma" (`settings_screen.dart:204-212`). **No** se traducen los títulos hardcodeados (H-8, fuera de alcance) | T10a |
| `frontend/lib/presentation/widgets/ticket_preview_dialog.dart` | **Sin cambios.** Renderiza en Roboto (`:517`, `:671`) mientras el PDF usa DejaVu; `spec.md §4.2` punto 8 lo declara imposible de alinear | — |
| `frontend/integration_test/` | Harness de medición de `overflow_count` de T1 y verificación de REQ-FN-008 | T1, T10b |

### 3.8 Flutter — capa Application

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `frontend/lib/core/theme/typography_controller.dart` | **Archivo nuevo.** `ChangeNotifier` paralelo a `ThemeController`: familia de UI + factor 0.85–1.40, persistido con el patrón de `local_storage.dart` | T7 |

> Capa *Application* y no *Core*, por simetría con `ThemeController`, que vive en
> `core/theme/` y se pasa por constructor (`settings_screen.dart:26`, `home_shell.dart:47`).
> El repositorio global `di` no se toca: `main.dart:42` crea el controlador como
> `final` de nivel superior, igual que `themeController`.

### 3.9 Flutter — capa Domain

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `frontend/lib/domain/entities/...` | **Sin entidad nueva.** El ajuste de UI es un valor de preferencias, no una entidad de negocio; el del ticket viaja en el perfil de empresa ya existente | — |
| `frontend/lib/domain/entities/printer_preset.dart` | **Sin cambios** (REQ-FN-021). Se documenta que **no** debe crecer con campos de fuente | T6 |

### 3.10 Flutter — capa Data

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `frontend/lib/data/datasources/local/local_storage.dart` | Persistencia del ajuste de UI, con el patrón de `PrinterPreset` (`:24` clave `static const`, `:116-128` `setString(jsonEncode(...))` / `getString` con default) | T7 |

> **Corrección de ruta**: el enunciado del desglose citaba
> `frontend/lib/core/services/local_storage.dart`. **No existe.** La ruta real es
> `frontend/lib/data/datasources/local/local_storage.dart` (130 líneas), lo que además
> confirma la capa *datos* de la arquitectura. `spec.md §2.1` sí acertaba al citar
> `lib/domain/entities/printer_preset.dart`.

### 3.11 Flutter — capa Infrastructure

| Archivo | Responsabilidad | Tarea |
|---------|----------------|-------|
| `frontend/lib/main.dart` | Único punto de cableado: `builder:` del `MaterialApp` (`:212`) para el clamp del `textScaler`, y `theme:`/`darkTheme:` (`:217-218`) para la familia | T9 |
| `frontend/lib/core/theme/app_theme.dart` | `buildLightTheme()`/`buildDarkTheme()` pasan a **aceptar parámetros** (hoy son sin argumentos, `:60` y `:146`) y **ganan `iconTheme`** (hoy no existe) | T9 |
| `frontend/lib/core/i18n/translations.dart` | Claves nuevas **en los 3 diccionarios**: `es` (`:12-752`), `en` (`:753-1473`), `pt` (`:1474-2204`) | T7 |

---

## 4. Funciones puras con «hoy» como parámetro

**Principio:** el comportamiento actual se trata como un **valor de entrada**, no
como código a reescribir. Cada función pura recibe el «hoy» explícito, de modo que
`AUTOMATICO` sea indistinguible del presente por construcción y que el test de
no-regresión sea trivialmente cierto (REQ-FN-012).

### 4.1 Escalera efectiva del auto-fit (backend)

```
funcion escalera_efectiva(
    hoy: dict[int, list[float]],      # las 4 escaleras de ESCALA_CANDIDATAS, tal cual
    paso_configurado: str            # "AUTOMATICO" | "GRANDE" | "MEDIANO" | "PEQUENO"
) -> dict[int, list[float]]

    si paso_configurado == "AUTOMATICO":
        devolver hoy                   # ← identidad. Cero cambio de comportamiento.

    techo = 10.5 si GRANDE else 9.0 si MEDIANO else 7.5
    para cada (n_try, escalera) en hoy.items():
        filtrada = [t para t en escalera si t <= techo]
        # invariante: la escalera ya está ordenada de forma descendente y su
        # último elemento (el piso) siempre es <= techo, luego filtrada nunca
        # queda vacía y nunca pierde el piso.
        nuevo[n_try] = filtrada
    devolver nuevo
```

**Por qué el filtro y no "reemplazar el primer elemento".** Es la única forma de
satisfacer **CE-04 y CE-05 a la vez**. `escala_candidatas` son **4 escaleras
distintas, una por `boletos_por_hoja`** (`ticket_service.py:1142-1147`), con
primeros elementos 10.5 / 9.5 / 8.5 / 8.0:

| Diseño | CE-05 (`GRANDE` + 4 por hoja ⇒ idéntico al actual) | CE-04 (`PEQUENO` + 4 por hoja ⇒ empieza en 7.5) |
|--------|:---:|:---:|
| Reemplazar el primer elemento por el peldaño configurado | ❌ pasa de 8.0 a 10.5 → cambia el comportamiento | ✅ |
| **Filtrar por techo (elegido)** | ✅ 8.0 ≤ 10.5 → escalera intacta | ✅ arranca en 7.5 |
| Limitar el cambio a `n_try == 1` | ✅ | ❌ con 4 por hoja seguiría empezando en 8.0 |

**Invariantes que preserva el filtro** (`REQ-FN-011`):
- **Orden descendente**: la sublista de una lista ordenada conserva el orden.
- **Nada se trunca**: el piso (último elemento, 5.5/5.0/4.0/4.0) siempre sobrevive
  al filtro porque es el menor ⇒ `escala_candidatas[n][-1]` no cambia ⇒ el fallback
  de `ticket_service.py:1171-1173` sigue siendo válido sin tocarlo.
- El bucle `for n_try in range(n, 0, -1)` (`ticket_service.py:1151`) y la llamada a
  `_caben()` (`ticket_service.py:1163`) **no se reescriben**: solo cambia el `cand`
  que consume el bucle interno (`ticket_service.py:1153`).

### 4.2 Factor efectivo del `textScaler` (Flutter)

```
funcion factor_efectivo(
    factor_operador: double,   # 0.85 .. 1.40, lo que eligió el operador
    factor_externo: double,   # lo que venga de fuera (accesibilidad del SO, ancestros)
    minimo: double = 0.85,
    maximo: double = 1.60     # clamp técnico de REQ-FN-002b
) -> double

    # El selector nunca supera 1.40 < 1.60 ⇒ el clamp no limita la elección del
    # operador; solo acota lo externo.
    return acota(factor_operador * factor_externo, minimo, maximo)
```

**El «hoy» como parámetro**: `factor_operador = 1.0` y `factor_externo = 1.0`
reproducen exactamente el comportamiento actual (sin escalado), así que el test
puede afirmar `factor_efectivo(1.0, 1.0) == 1.0` como prueba de no-regresión.

### 4.3 Escala de iconos (Flutter)

```
funcion escala_iconos(factor: double, base: double = TAMANO_ICONO_BASE) -> double
    return base * factor
```

**El «hoy» como parámetro**: `escala_iconos(1.0)` devuelve `TAMANO_ICONO_BASE`, que es
el valor que Flutter usa por defecto cuando no hay `iconTheme` — de modo que
`factor == 1.0` es exactamente el estado actual.

---

## 5. Pseudocódigo

### 5.1 (a) Peldaño inicial del auto-fit

```
# ── ticket_service.py, lectura del ajuste ────────────────────────────────────
# getattr con default: obligatorio. Ver §6.2.
paso_configurado = getattr(empresa, "tamano_ticket_pdf", "AUTOMATICO")

# ── ticket_service.py, nueva función pura (testeable sin BD ni ReportLab) ────
TECHO_POR_PASO = {GRANDE: 10.5, MEDIANO: 9.0, PEQUENO: 7.5, AUTOMATICO: None}

funcion escalera_efectiva(hoy, paso_configurado):        # §4.1
    ...

# ── ticket_service.py, dentro de _build_pdf, 1 línea cambiada ────────────────
# ANTES (línea 1142):  escala_candidatas = { 1: [...], 2: [...], 3: [...], 4: [...] }
# DESPUÉS:             escala_candidatas = escalera_efectiva(_ESCALAS_ACTUALES, paso)
```

`_ESCALAS_ACTUALES` se extrae como constante de módulo **con los valores actuales
intactos** (10.5…5.5 / 9.5…5.0 / 8.5…4.0 / 8.0…4.0). Extraer la constante **no**
cambia el comportamiento: es la misma tabla, movida de un literal local a una
constante con nombre, y es lo que permite que `escalera_efectiva` la tome como
parámetro («hoy» como valor).

El resto de `_build_pdf` queda **intacto**, incluida la línea
`st = _estilos_simples(escala_candidatas[1][-1])` del fallback
(`ticket_service.py:1173`), que sigue siendo válida porque el piso nunca se filtra.

### 5.2 (b) Clamp del `textScaler`

**⚠ Corrección obligatoria respecto a la spec.** `REQ-FN-002b` nombra
`MediaQuery.clampTextScaler`. **Ese método no existe en el SDK de este proyecto.**
Verificado:

| Búsqueda | Resultado |
|----------|-----------|
| `grep -rn "clampTextScaler" /home/yohander/flutter/packages/flutter/lib/` | **0 resultados** |
| `grep -rn "clampTextScaler" /home/yohander/flutter/packages/flutter/lib/src/widgets/media_query.dart` | **0 resultados** |

Las APIs reales que cumplen la misma intención, ambas verificadas por lectura del SDK:

| API real | Ubicación verificada | Forma |
|----------|---------------------|-------|
| `MediaQuery.withClampedTextScaling({minScaleFactor, maxScaleFactor, child})` | `media_query.dart:1503` | widget estático; internamente hace `data.textScaler.clamp(...)` (`:1517-1520`) |
| `TextScaler.clamp({minScaleFactor, maxScaleFactor})` | `text_scaler.dart:62` | método de instancia; acota a `[min*fontSize, max*fontSize]` (`:128-131`) |

```
# ── main.dart, dentro de MaterialApp (línea 212), un builder NUEVO ───────────
builder: (context, hijo) {
    factorOperador = typographyController.factor        # 0.85 .. 1.40
    mq = MediaQuery.of(context)

    # (1) Red de seguridad sobre lo que venga de fuera: la API real del SDK.
    #     Un factor externo de 2.0 del SO queda acotado a 1.60.
    mqSeguro = mq.copyWith(
        textScaler: mq.textScaler.clamp(
            minScaleFactor: 0.85,
            maxScaleFactor: 1.60,
        ),
    )

    # (2) El factor del operador se compone por encima.
    return MediaQuery(
        data: mqSeguro.copyWith(textScaler: escalar(typographyController, mqSeguro)),
        child: hijo,
    )
}
```

**Composición del factor (el punto delicado).** El `textScaler` del operador y el
del SO son dos entradas distintas y `TextScaler` no tiene operador de producto. Hay
que elegir:

| Opción | Cómo | Ventaja | Inconveniente |
|--------|------|---------|---------------|
| **(A) Wrapper que multiplica** *(elegida)* | Clase `TextScaler` que en `scale(fontSize)` devuelve `interno.scale(fontSize) * factor` | Conserva el escalado no lineal del SO; el clamp se aplica al factor externo y el del operador se compone encima | `TextScaler` **exige implementar 3 miembros**: `scale`, **`clamp`** y `textScaleFactor`. Este último es abstracto **y `@Deprecated`** (`text_scaler.dart:54-58`) → supresión **acotada y obligatoria** `// ignore: deprecated_member_use`. Verificado empíricamente (tabla en `spec.md` H-15) |
| (B) `TextScaler.linear(op * ext)` | Multiplica numéricamente | Trivial y totalmente testeable | Lee el getter `@Deprecated` (`flutter analyze` lo trata como **error**, `AGENTS.md` v3.11) y **aplana** el escalado no lineal del SO a lineal |
| (C) `TextScaler.linear(op)` | Ignora el SO | La más simple | Inutiliza la accesibilidad del SO: contradice el spirit de REQ-FN-002b, que lo menciona explícitamente como la amenaza que el clamp debe acotar |

> **✅ `[VERIFICAR]` RESUELTO antes de T9** — la incógnita era si (A) dispara
> avisos de `deprecated_member_use` y si la supresión acotada basta.
> **Respuesta: sí dispara, y sí basta.** Comprobado compilando una subclase real
> contra el SDK de este proyecto (`flutter analyze`, no lectura de firmas):
>
> | Miembros implementados | `flutter analyze` | exit |
> |---|---|:--:|
> | `scale` + `textScaleFactor` sin `clamp` | `error Missing concrete implementation of 'TextScaler.clamp'` | **1** |
> | los 3, **sin** `// ignore` | `info deprecated_member_use` | **1** |
> | los 3, **con** `// ignore: deprecated_member_use` | **`No issues found!`** | **0** |
>
> **Dos consecuencias que este plan tenía equivocadas:**
> 1. **`clamp` también es abstracto** en esta versión (`text_scaler.dart:62`). El
>    wrapper debe implementarlo delegando en `interno.clamp(...)`. Sin este
>    miembro, T9 **no compila** → `REQ-FN-002c`.
> 2. **La supresión no es un recurso de último recurso**: es obligatoria. Sin ella
>    `flutter analyze` sale con 1 y la CI queda roja.
>
> La degradación a (B) **queda descartada**: no es necesaria. Sibling de
> `spec.md` H-15.

**Por qué el clamp técnico es 1.60 y no 1.40** (`REQ-FN-002b`): el selector
produce como máximo 1.40 y el mínimo es 0.85. Con un techo igual al del selector el
clamp no aportaría nada; con 1.60 queda un margen real para acotar factores externos
sin poder tocar lo que el operador eligió. Verificado en el SDK: `clamp` acota
`[minScaleFactor*fontSize, maxScaleFactor*fontSize]` (`text_scaler.dart:129`),
es decir, acota **el factor**, no el tamaño absoluto.

### 5.3 (c) Escalado de iconos

`app_theme.dart` **no define hoy ningún `iconTheme`** (0 resultados en todo
`frontend/lib/`). Hay que crearlo, no modificarlo.

```
# ── app_theme.dart: buildLightTheme() y buildDarkTheme() pasan a aceptar parámetros
buildLightTheme(familia: ..., factorIconos: ...) :
    ...
    base = base.copyWith(
        textTheme: base.textTheme.apply(fontFamily: familia),
        iconTheme: IconThemeData(size: TAMANO_ICONO_BASE * factorIconos),
    )
    ...

# ── main.dart: única línea que cambia en el cableado
theme:     buildLightTheme(familia: f, factorIconos: factorIconos),
darkTheme: buildDarkTheme(familia: f, factorIconos: factorIconos),
```

**Alcance real del escalado de iconos.** Este mecanismo cubre los iconos que
heredan de `ThemeData.iconTheme`: `AppBar`, botones, `ListTile`, `Icon` sueltos y
los del sidebar y la barra de navegación. **No** cubre un `Icon` con `size:` escrito
a mano. Recuento verificado para resolver el riesgo de `spec.md §9`:

| Riesgo de `spec.md §9` | Verificación | Veredicto |
|------------------------|--------------|-----------|
| «`textScaler` no cubre los `fontSize` de `CustomPaint`» | `grep -rn "CustomPaint\|CustomPainter" frontend/lib/` → **2 resultados**: `scale_monitor_widget.dart:552` (uso) y `:571` (clase `_TrianglePainter`) | **Riesgo descartado.** Es el **único** `CustomPaint` del proyecto y pinta un triángulo de `Size(9,5)` (`scale_monitor_widget.dart:553-554`); **no dibuja texto**. El `Text` contiguo (`:559-561`) es un `Text` normal y sí escala con `textScaler` |

---

## 6. Decisiones justificadas con la alternativa descartada

### 6.1 El PDF no gana parámetro de API — alternativa: parámetro `?paso_ticket=`

**Elegido:** el backend lee el ajuste de su propia BD.
**Descartado:** aceptar el paso por query param desde Flutter.

`get_weighing_pdf` (`pesajes.py:495-523`) ya recibe
`empresa: Empresa = Depends(get_current_empresa)` y lo pasa a `generar_ticket_pdf`.
Y desde Flutter, `weighing_detail_screen.dart:300-315` ya envía el `PrinterPreset`
completo por parámetro. Si el paso fuera un parámetro, el cliente podría pedir un
paso que su empresa no tiene configurado (p. ej. `PEQUENO` en una empresa en
`GRANDE`), es decir, el control de acceso se volvería opcional. Con la lectura desde
la BD, **el cliente no puede influir**: el aislamiento queda por construcción
(REQ-FN-018) y el cambio de alcance es cero en `pesajes.py` **y** cero en el
repositorio Flutter.

### 6.2 `getattr` con default `AUTOMATICO` en lugar de acceso directo al atributo

**Elegido:** `getattr(empresa, "tamano_ticket_pdf", "AUTOMATICO")`.
**Descartado:** `empresa.tamano_ticket_pdf`.

Verificado: `test_ticket_service.py:139-152` construye la empresa de prueba con
`SimpleNamespace`, y se usa en **20** llamadas del fichero
(`grep -c "_empresa_demo()\|_empresa_contacto(" → 20`). Un `SimpleNamespace` **no**
tiene el atributo nuevo ⇒ acceso directo ⇒ `AttributeError` en 20 tests existentes.
`getattr` con default es además el patrón ya establecido en el mismo módulo para
exactamente estasituación: `ticket_service.py:447` usa
`getattr(empresa, "logo_url", None)` con el comentario de que un logo roto no puede
tumbar el ticket.

### 6.3 Filtrar la escalera en vez de reescribir el bucle de auto-fit

**Elegido:** función pura que devuelve la escalera efectiva; el bucle no se toca.
**Descartado:** reescribir el `for n_try … for ts …` con la lógica del peldaño
dentro.

`spec.md H-2` garantiza que el auto-fit nunca trunca, y esa garantía está repartida
en tres sitios: `_caben()` (`ticket_service.py:1073-1091`), el doble bucle
(`:1151-1169`) y el fallback `if not n_fit` (`:1171-1173`). Reescribirlo
reintroduciría el riesgo de que una nueva ruta saltee `_caben`. Con el filtro, el
camino de medición es **el mismo código**; solo cambia la lista que se le pasa.
Aporta además que la función sea testeable sin ReportLab ni BD.

### 6.4 `iconTheme` como superficie nueva — alternativa: `IconButtonTheme`/`TextStyle` por widget

**Elegido:** `iconTheme` en `buildLightTheme()`/`buildDarkTheme()`.
**Descartado:** tocar los widgets con icono uno por uno.

No existe ningún `iconTheme` hoy, así que los iconos heredan el valor por defecto de
Material. Añadirlo en el tema los cubre **de una vez** desde `AppBar` hasta el
sidebar, sin lo que REQ-FN-003 llama «los iconos de `AppBar`, botones y acciones de
navegación». Editar widget por widget sería el refactor que `spec.md §4.2` punto 4
excluye.

### 6.5 `builder:` del `MaterialApp` en vez de envolver cada pantalla

**Elegido:** un `builder:` en el `MaterialApp` de `main.dart:212`.
**Descartado:** un `InheritedWidget` propio (`TypographyScope`) consultado en cada
pantalla.

`builder` es el punto oficial de Flutter para manipular `MediaQuery` de forma
global, se inserta **por encima** de todas las rutas y **por debajo** de
`Navigator`, de modo que las rutas, diálogos y `showDialog` quedan cubiertos sin
tocar una sola pantalla. Es también donde `MaterialApp` expone los parámetros de
tema que ya se pasan en `:217-218`.

### 6.6 La prueba de desbordes va en el canal de integración, no en widget tests

**Elegido:** `integration_test/` reutilizando el harness de `pesaje_flow_test.dart`.
**Descartado:** 4 widget tests con `pumpWidget` de cada pantalla.

Verificado: `weighing_form_screen.dart` tiene 4153 líneas y requiere `CatalogBloc`
(`:193`); el único test de detalle existente
(`weighing_detail_screen_test.dart:9-23`) solo ejerce el estado vacío, porque con
contenido real la pantalla «requiere `WeighingBloc` y `AuthBloc`» (comentario del
propio test, `:27`). Un widget test que no monta la pantalla real mide otra cosa.
El coste es que T1 necesita el entorno E2E levantado (`scripts/e2e_flutter.sh up`),
y eso está dentro de los ~25 min estimados.

### 6.7 El ajuste de UI no se expone en el `ThemeController` — alternativa: ampliarlo

**Elegido:** `TypographyController` nuevo y paralelo.
**Descartado:** añadir la familia y el factor a `ThemeController`.

`ThemeController` (`theme_controller.dart:6-35`) tiene **35 líneas** y una sola
responsabilidad: un `TemaApp` de 3 valores en la clave `balansoft.tema` (`:25,31`).
Meterle dos conceptos más (familia + factor, con validación de rango) mezcla dos
ajustes con conceptos muy distintos y obliga a revisar los 4 sitios que ya lo reciben
por constructor (`main.dart:42`, `settings_screen.dart:26,1421`,
`home_shell.dart:47`, `preferences_screen.dart:17,155`). Un controlador nuevo que
extiende `Listenable` se integra en el `AnimatedBuilder` que ya existe en
`main.dart:211` sin tocar ninguna de esas firmas.

---

## 7. Estrategia de tests

### 7.1 Comandos reales

| Objetivo | Comando | Nota |
|----------|---------|------|
| Backend rápido | `cd backend && uv run pytest -q` | **328** tests rápidos (`-m "not e2e"`) |
| Backend E2E | `cd backend && uv run pytest tests/e2e` | **34** tests |
| Recuento total | `cd backend && uv run pytest -q --collect-only` | **362** — verificado en esta máquina: `362 tests collected in 1.28s` |
| Lint backend | `cd backend && uv run ruff check app tests` | line-length 100 |
| Tipos backend | `cd backend && uv run mypy tests/` | |
| Frontend | `cd frontend && flutter test` | **158** tests unit/widget |
| Análisis Flutter | `cd frontend && flutter analyze` | **los warnings son error** (`AGENTS.md` v3.11) |
| E2E de UI | `cd frontend && flutter test integration_test/pesaje_flow_test.dart -d linux` | local: `DISPLAY=:0`; CI: `xvfb-run -a` |

> **Fallback verificado en esta máquina.** `AGENTS.md` afirma que `uv` no está en
> PATH. Hoy **sí lo está** (`which uv` → `/home/yohander/.local/bin/uv`), pero el
> fallback sigue siendo válido y es el que usa la doc: `backend/.venv/bin/python -m pytest -q`.
> Verificado: `backend/.venv/bin/python -c "import pytest,reportlab,pypdf"` → OK.
> No usar `backend/.venv.broken` (`AGENTS.md`).

### 7.2 Baseline numérico verificado antes de empezar

| Medida | Valor verificado | Cómo |
|--------|------------------|------|
| Tests backend totales | **362** | `uv run pytest -q --collect-only` |
| Tests en los 2 ficheros que se tocan | **63, en verde** | `uv run pytest -q tests/test_ticket_service.py tests/test_preferencias_empresa.py` → `63 passed in 9.12s` |
| Tests frontend | 158 | `AGENTS.md` §Tests (`[VERIFICAR]` con `flutter test` en la máquina de ejecución) |
| Desajustes esperados | **0** | Salir de `plan.md` con 362 y entrar en T6 con 362 |

### 7.3 Qué test va primero, en rojo, y por qué

**Orden de escritura de los tests** (rojo primero, en todos los casos):

| # | Test (rojo primero) | Tarea | Por qué este primero |
|---|--------------------|-------|----------------------|
| 1 | Baseline `AUTOMATICO`: texto extraído idéntico | **T4** | Es el **control** de T6. Si no es lo primero, T6 se ejecuta a ciegas |
| 2 | `PEQUENO` arranca la escalera en 7.5 y no trunca | T5 | Es el caso con el requisito más fuerte y el más fácil de romper |
| 3 | `GRANDE` + 4 por hoja = comportamiento intacto | T5 | Es el caso que distingue el filtro (correcto) de reemplazar el primer elemento (incorrecto). Falla en rojo si se eligió mal |
| 4 | `GET /empresa` no devuelve campos de otra empresa | T3 | Refuerza REQ-FN-018 por el canal de **lectura**, que el PUT ya cubre. Es el ajuste que la QA pidió |
| 5 | `textScaler` en 1.40 y clamp en 1.60 | T8 | El clamp es la red de seguridad; si el clamp no está, cualquier valor externo rompe el layout |

**Regla:** ningún test se escribe después de su implementación salvo los de T1 y
T10b, que son **mediciones**, no verificaciones de comportamiento nuevo.

### 7.4 Cobertura de tests por requisito

| RF | Test | Tarea |
|----|------|-------|
| REQ-FN-001 | familia aplicada al `textTheme` del tema | T9 |
| REQ-FN-002 | factor aplicado en [0.85, 1.40] | T9 |
| REQ-FN-002b | clamp a 1.60 con factor externo de 2.0 | T9 |
| REQ-FN-002c | subclase `TextScaler` con `scale`+`clamp`+`textScaleFactor` e `ignore` acotado | T9 |
| REQ-FN-003 | `iconTheme` escala con el factor | T9 |
| REQ-FN-004 | cambio sin reinicio (`AnimatedBuilder` ya notifica) | T9 |
| REQ-FN-005 | persiste y restaura en el arranque | T7 |
| REQ-FN-006 | familia inexistente no falla | T10b |
| REQ-FN-007 | 5 familias ofrecidas | T10a |
| REQ-FN-008 | `overflow_count == 0` en 4 pantallas a 1.40 | T1, T10b |
| REQ-FN-009 | persiste por `id_empresa` | T3 |
| REQ-FN-010 | el paso configurado es el peldaño inicial | T5 |
| REQ-FN-011 | orden descendente y nada truncado | T5 |
| REQ-FN-012 | texto extraído idéntico con `AUTOMATICO` | T4 |
| REQ-FN-013 | TXT ignora la tipografía | T5 |
| REQ-FN-014 | solo DejaVu | T3 |
| REQ-FN-015 | peldaños 10.5 / 9.0 / 7.5 | T5 |
| REQ-FN-016 | fallback Helvetica sin fallar | T5 |
| REQ-FN-017 | el PDF no toca la red central | T4 |
| REQ-FN-018 | aislamiento en lectura y escritura | T3 |
| REQ-FN-019 | paridad es/en/pt | T7 |
| REQ-FN-020 | contraste AA en claro y oscuro | T10b |
| REQ-FN-021 | `PrinterPreset` intacto | T6 |
| REQ-FN-022 | ningún boleto existente alterado | T4 |

### 7.5 Trampa de aislamiento en los tests (verificada)

El helper `_app_con_rol` de `test_preferencias_empresa.py:26-46` hace
`dependency_overrides[get_current_empresa] = lambda: empresa`. **Ese override
enmascararía exactamente el fallo que REQ-FN-018 quiere detectar**: la empresa se
inyecta, así que el filtro por `id_empresa` de `dependencies.py:52-58` nunca se
ejercita.

Por eso el test de aislamiento (CE-07) debe **no** sobrescribir
`get_current_empresa`, sino solo `get_current_user` (con un usuario de la empresa B)
y dejar que la dependencia real resuelva desde la BD.

Además `conftest.py` expone **un solo** fixture `empresa` (`conftest.py:78-93`), así
que la segunda empresa del caso CE-07 se crea dentro del propio test con un
`rif_nit` único (el patrón es `rif_nit=f"J-{uuid.uuid4().hex[:10]}"`,
`conftest.py:84`).

### 7.6 El esquema de los tests viene de los modelos, no del `.sql`

`conftest.py:52-62` construye la BD con `Base.metadata.create_all`. **El fichero
`migrations/021_*.sql` no lo ejecuta ningún test.** Consecuencia: el modelo (T2) es
lo que hace pasar los tests, y la migración hay que revisarla **a mano** contra el
modelo. Verificación recomendada: aplicar la migración en una BD desechable con
`./scripts/setup_db.sh aplicar-migraciones` y comparar `\d empresas` con el modelo.

---

## 8. Baseline del PDF

### 8.1 Por qué **texto extraído** y no bytes

**Verificado empíricamente en este repositorio**, generando dos veces el mismo
boleto con `_build_pdf(_boleto())`:

| Medida | Resultado |
|--------|-----------|
| ¿Bytes iguales? | **No** (`b1 == b2` → `False`) |
| Longitud | 45 330 bytes en ambos |
| Bytes que difieren | **60**, todos en las posiciones 45 142-45 201 |
| Contexto de la diferencia | `r\n<<\n/ID \n[<8e84adb6fe7a94a5d36fdc98` |
| `/ID` del trailer | **distinto en cada generación** (array aleatorio de 2×16 bytes) |
| Metadatos | `/CreationDate` y `/ModDate` presentes (`D:20261002163207-04'00'`) |
| **¿Texto extraído igual?** | **Sí** — 646 caracteres, idénticos |

**Por qué la comparación byte a byte es imposible, no solo frágil:** las dos
generaciones de la prueba ocurrieron **en el mismo segundo**, así que
`CreationDate`/`ModDate` eran idénticos y aun así los bytes difieren. La única
causa es el `/ID`, que ReportLab genera **aleatoriamente** por documento. Ni
sincronizando el reloj ni congelando metadatos se obtendría reproducibilidad byte a
byte.

El requisito se satisface entonces sobre lo que el operador percibe: el contenido
renderizado y su orden. De ahí el texto extraído con `pypdf`.

**El test ya existe casi hecho.** `test_ticket_service.py:29-33` ya define
`_extract(p, **kwargs)`, que hace exactamente
`"\n".join(page.extract_text() or "" for page in PdfReader(buf).pages)`.
T4 solo tiene que **usarlo**, no escribir la infraestructura.

### 8.2 Por qué el baseline se captura **antes** de tocar `ticket_service.py`

1. **El baseline es una referencia, y una referencia se toma antes de mover el
   objeto.** Si T6 se ejecuta primero y T4 después, el test de no-regresión
   compararía el código nuevo consigo mismo: pasaría siempre y no probaría nada.
2. **Un `AUTOMATICO` mal implementado es indistinguible del correcto a simple
   vista.** `_build_pdf` tiene un doble bucle con 40 candidatos
   (`ticket_service.py:1142-1147`); un cambio de un decimal en un valor mueve la
   tipografía de un boleto entero sin que nada falle. Solo una comparación previa
   lo delata.
3. **Es la única defensa contra el riesgo «Regresión en PDFs existentes»
   (severidad **Alta**, `spec.md §9`).** Boletos emitidos son documentos legales:
   lo que se imprime a partir de hoy debe seguir siendo lo mismo que se imprimía
   ayer cuando la empresa está en `AUTOMATICO` (el default, `spec.md §3`).
4. **Es un requisito cerrado con la QA** (REQ-FN-012). El gate no es negociable.
5. **Restricción dura `T4 ──precede──> T6`** (§2): sin el baseline, T6 no arranca.

### 8.3 Qué guarda exactamente el baseline

No un fichero binario en el repo (se regrediría y no es revisable). El test:

1. Genera el PDF **antes** del cambio y captura su texto extraído.
2. Lo normaliza (minúsculas, espacios colapsados, líneas vacías fuera) para que
   no dependa de cómo `pypdf` interprete los saltos de línea de una versión a otra.
3. Tras el cambio, con la empresa en `AUTOMATICO`, compara el texto normalizado y
   además el **número de páginas** (el helper `_paginas` ya existe,
   `test_ticket_service.py:36-39`).

El paso 1 se materializa como una **constante esperada** en el test (el texto
esperado, ~646 caracteres para el boleto de prueba), **no** como un PDF binario.

---

## 9. Evidencia: discrepancias entre la spec v0.2 y el código real

Encontradas al verificar. **Ninguna invalida el alcance**; la #1 sí exige
reescribir el enunciado de un requisito antes de implementar.

### #1 🔴 `MediaQuery.clampTextScaler` **no existe** en Flutter 3.47.2

`REQ-FN-002b` nombra un método inexistente. Verificado con
`grep -rn "clampTextScaler" /home/yohander/flutter/packages/flutter/lib/` → **0
resultados**. Las APIs reales son `MediaQuery.withClampedTextScaling`
(`media_query.dart:1503`) y `TextScaler.clamp` (`text_scaler.dart:62`).
**Acción**: §5.2 usa la API real; el criterio de aceptación de REQ-FN-002b (clamp
de [0.85, 1.60]) se mantiene intacto. Adicionalmente, `TextScaler.textScaleFactor`
está marcado `@Deprecated` (`text_scaler.dart:54-58`) y **`flutter analyze` trata
los warnings como error** (`AGENTS.md` v3.11), así que leerlo rompe la CI.

### #2 🟠 La escalera no tiene 11 peldaños: tiene **4 escaleras de 11/10/10/9**

`spec.md §2.4` menciona «una escalera automática de 11 peldaños». Realidad
(`ticket_service.py:1142-1147`): un **diccionario indexado por `boletos_por_hoja`**
con 4 listas de 11, 10, 10 y 9 elementos (**40 candidatos**). El 11 es correcto
solo para `boletos_por_hoja = 1`.
**Consecuencia real**: CE-04 y CE-05 **se contradicen** si se implementa «el peldaño
inicial» como reemplazo del primer elemento (ver §4.1). De ahí el diseño por
filtrado, que es el único que satisface ambas.

### #3 🟠 H-8 es incorrecto tal como está redactado

Dice «**16 títulos hardcodeados en español y 0 con `.tr()`**». Verificado:
`settings_screen.dart` tiene **43 usos de `.tr()`** y su título principal sí lo es
(`settings_screen.dart:151`, `'settings_title'.tr()`). Los literales en español
hardcodeados son **7 títulos únicos** en **10 apariciones** (3 de ellos duplicados
por aparecer en la lista y en la cabecera): `Cuenta y Empresa`, `Apariencia e
Idioma`, `Servidor Local (WServer)`, `Báscula por defecto en ENTRADAS/SALIDAS`,
`Carpeta de reportes (Cuenta)/(Predeterminada)`.
**La conclusión se mantiene** (el hub no está traducido) y **el ítem sigue fuera de
alcance** (`spec.md §4.2` punto 7). Solo se corrige la cifra.

### #4 ✅ CONFIRMADO — H-7: son **15** `fontFamily` con `'monospace'`

**El planner acertó y una "corrección" posterior lo revertió por error** (`spec.md`
H-16). `grep -rn "monospace" frontend/lib/ --include=*.dart` → **15 ocurrencias** en
8 archivos, y **todas** son `fontFamily`: 12 directas más 3 ternarias
`formato == 'TXT' ? 'monospace' : 'Roboto'` (`ticket_design_screen.dart:467`,
`ticket_preview_dialog.dart:517,671`). El patrón estrecho
`grep "fontFamily: 'monospace'"` devuelve 12 y omite las 3 ternarias.

### #5 ✅ CONFIRMADO — H-1: son **14** apariciones de `textTheme`, no «~11»

El planner acertó; la corrección posterior no. `grep -rn "textTheme"
frontend/lib/ --include=*.dart | wc -l` → **14**: **12 usos** (`apply`×2,
`bodySmall`×1, `headlineMedium`×2, `titleLarge`×3, `titleMedium`×1,
`titleSmall`×3) y **2 definiciones** dentro del propio tema. La conclusión se
mantiene: 322 literales frente a 12 usos.

### #6 🟡 `local_storage.dart` no está en `core/services/`

Ruta real: `frontend/lib/data/datasources/local/local_storage.dart` (130 líneas).
Refuerza la capa *datos* de la arquitectura. `spec.md §2.1` acertaba con
`lib/domain/entities/printer_preset.dart`.

### #7 🟡 No existe `theme_controller_test.dart`

`frontend/test/unit/` no lo tiene. Plantilla a copiar:
`locale_controller_test.dart:11-13` (`TestWidgetsFlutterBinding.ensureInitialized()`
+ `SharedPreferences.setMockInitialValues({})`).

### #8 🟡 `_estilos_simples` documenta mal su propia tabla

Su docstring (`ticket_service.py:536-538`) dice «1 → 10.5 | 2 → 9.5 | 3 → 9.0 |
4 → 8.5», pero los primeros elementos reales de `escala_candidatas` son
10.5 / 9.5 / **8.5** / **8.0**. Inconsistencia **preexistente**. T6 no debe
«arreglarla» en silencio al extraer la constante; si se toca el docstring, es
documentación explícita del valor real.

### #9 🟡 Las migraciones `.sql` no las ejecuta ningún test

`conftest.py:52-62` usa `Base.metadata.create_all`. La coherencia entre
`021_*.sql` y el modelo es **manual**. Ver §7.6.

### #10 🟢 `uv` **sí** está en PATH en esta máquina

`which uv` → `/home/yohander/.local/bin/uv`, contra lo que dice `AGENTS.md`. El
fallback `backend/.venv/bin/python -m pytest -q` sigue siendo válido y documentado.

### #11 🟢 Recuento de claves i18n: **630**, no 621

Contado por regex sobre `translations.dart`: 630 claves en cada uno de los tres
diccionarios (es/en/**pt idénticos**, luego **la paridad se cumple**). La cifra 621
de `AGENTS.md` usa otro criterio de conteo. El test de paridad que hay que mantener
en verde es `i18n_test.dart:55-70`.

### #12 🟢 `escala_candidatas[1][-1]` sobrevive al filtro

Verificado: es el piso de cada escalera (5.5 / 5.0 / 4.0 / 4.0), siempre ≤ cualquier
techo ⇒ el fallback de `ticket_service.py:1171-1173` no necesita cambios.

---

## 10. Trazabilidad de cifras del plan

Toda cifra de este documento y su origen:

| Cifra | Origen |
|-------|--------|
| 362 tests | `cd backend && uv run pytest -q --collect-only` → `362 tests collected in 1.28s` |
| 63 tests, 9.12 s | `cd backend && uv run pytest -q tests/test_ticket_service.py tests/test_preferencias_empresa.py` → `63 passed in 9.12s` |
| 20 usos de `_empresa_demo` | `grep -c "_empresa_demo()\|_empresa_contacto(" backend/tests/test_ticket_service.py` → 20 |
| 332 `fontSize:` / 322 literales | `grep -rn "fontSize:" frontend/lib/ \| wc -l` y filtro con número |
| 14 `textTheme` (12 usos + 2 definiciones) | `grep -rn "textTheme" frontend/lib/ \| wc -l` |
| 15 `monospace` | `grep -rn "monospace" frontend/lib/ --include=*.dart` → 15 líneas (12 directas + 3 ternarias) |
| 3 `'Roboto'` | `grep -rn "'Roboto'" frontend/lib/` → 3 |
| 0 `iconTheme` | `grep -rn "iconTheme\|IconThemeData" frontend/lib/` → vacío |
| 0 `GoogleFonts.` | `grep -rn "GoogleFonts" frontend/lib/ \| wc -l` → 0 |
| `google_fonts: ^6.1.0` | `frontend/pubspec.yaml:47` |
| Roboto 171 676 / 170 760 B | `ls -la …/material_fonts/Roboto-{Regular,Bold}.ttf` |
| 1 `CustomPaint` (2 coincidencias) | `grep -rn "CustomPaint\|CustomPainter" frontend/lib/` → `scale_monitor_widget.dart:552,571` |
| 630 claves × 3 idiomas | conteo por regex sobre `translations.dart` |
| 43 `.tr()` / 7 títulos únicos | `grep -c "\.tr("` y barrido de literales en `settings_screen.dart` |
| 45 330 B / 60 B distintos / `/ID` | ejecución empírica de `_build_pdf(_boleto())` dos veces |
| 646 caracteres de texto | misma ejecución (`len(t1)`) |
| 4153 / 894 / 1155 / 1558 líneas | `wc -l` de las 4 pantallas |
| 1 solo fixture `empresa` | `grep -n "def empresa" backend/tests/conftest.py` → `:79` |
| 11/10/10/9 peldaños | lectura de `ticket_service.py:1142-1147` |
| `media_query.dart:1503`, `text_scaler.dart:62` | lectura del SDK de Flutter 3.47.2 |
| Flutter 3.47.2 | `flutter --version` |
| 158 tests frontend | `AGENTS.md` §Tests — **`[VERIFICAR]`** ejecutando `flutter test` |

---

**Fin del plan v1.0.** No se ha escrito código. Siguiente artefacto: `tasks.md`.
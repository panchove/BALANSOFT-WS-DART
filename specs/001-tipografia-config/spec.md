# SPEC 001 — Ajuste de tipografía del sistema y del ticket

**Versión:** 0.4
**Fecha:** 2026-10-03
**Estado:** **BORRADOR** — v0.4: rango del selector reducido a 1.40 tras T1 (overflow en ajustes a 1.50)
**Autor:** Especificación redactada tras verificación de código (agente)
**Revisión QA:** 2026-10-03 (v0.3 aprobada). Tercera revisión: T1 detectó overflow en ajustes a 1.50 → techo bajado a 1.40.
**Norma:** `docs/constitution.md`, `AGENTS.md`, `docs/MANEJO_DB.md`
**Fuente:** Verificación directa sobre el código (ver §2), no sobre documentación legacy

---

## 1. Problema

El operador **no puede ajustar** la tipografía, ni la del sistema (UI), ni la del
ticket: ninguna de las dos tiene un ajuste configurable.

- **UI:** los tamaños están escritos uno por uno en el código (332 literales de
  `fontSize`), sin ninguna preferencia que los cambie.
- **Ticket:** el tamaño no es un valor fijo ni configurable, sino el resultado de
  un auto-fit que desciende por una escalera **dependiente de la cantidad de
  boletos por hoja**, hasta que el contenido cabe. El operador no interviene.

> **Corrección v0.3.** La v0.2 decía aquí *"una escalera de 11 peldaños"*. Es
> falso: `ticket_service.py:1142-1147` define **4 escaleras** en un diccionario,
> con **11, 10, 10 y 9** valores respectivamente (**40 candidatos** en total), y
> cuyo primer valor depende de la clave: `10.5 / 9.5 / 8.5 / 8.0` para
> 1, 2, 3 y 4 boletos por hoja. El detalle importa porque condiciona REQ-FN-010,
  REQ-FN-011, CE-04 y CE-05. Ver **H-10**.

Además, la acción crítica principal del formulario de pesaje usa **16 px**, por
debajo del requisito declarado de **≥18 px** para el modo kiosk (§6).

## 2. Contexto verificado en código

Todo lo de esta sección se comprobó leyendo el código. **No es suposición.**

### 2.1 Estado actual

| Elemento | Estado real | Ubicación |
|----------|-------------|-----------|
| Tipografía de la UI | **Sin ajuste.** Tema fijo; `buildLightTheme()`/`buildDarkTheme()` sin parámetros | `lib/core/theme/app_theme.dart:60,146` |
| Persistencia del tema | `SharedPreferences`, clave `balansoft.tema`, **por dispositivo** | `lib/core/theme/theme_controller.dart:25,31` |
| Tamaños de texto UI | **332 `fontSize:` hardcodeados** (322 literales); solo **14 apariciones de `textTheme`** (12 usos reales + 2 definiciones en el tema) | `frontend/lib/` |
| Acciones críticas pesaje | 16 / 15 / 13 px — **ninguna llega a 18** | `weighing_form_screen.dart:213,884,978` |
| Fuente del ticket (PDF) | Constantes de módulo `FUENTE="DejaVu"`, `FUENTE_BOLD="DejaVu-Bold"`; registro con fallback a Helvetica | `backend/app/services/ticket_service.py:71-72,389` |
| Tamaño del ticket | **No es un ajuste**: se auto-calcula. **4 escaleras** en un diccionario (11/10/10/9 valores), primer valor según boletos por hoja | `ticket_service.py:1142-1147` |
| Presets de impresora | `PrinterPreset` — **sin campos de fuente**; ancho fijo en 58/80 mm; se guarda en el dispositivo | `lib/data/datasources/local/local_storage.dart` (definición en `lib/domain/entities/printer_preset.dart`) |
| Preview del ticket | Renderiza en Flutter con `fontFamily: 'Roboto'`; el PDF real usa DejaVu | `lib/presentation/widgets/ticket_preview_dialog.dart:517,671` |
| Generación del PDF | **Siempre server-side** (ReportLab). No hay generación local en Flutter | `weighing_detail_screen.dart:306` |
| `iconTheme` | **No existe ninguno en todo `lib/`** (`grep` → 0 resultados). REQ-FN-003 crea superficie nueva | `frontend/lib/` |
| `monospace` | **15 usos** en 8 archivos: 12 directos + 3 en ternarias | `frontend/lib/` |
| Test del tema | **No existe** `theme_controller_test.dart`: hay que crearlo desde cero | `frontend/test/` |

### 2.2 Hallazgos que condicionan el diseño

**H-1 — La app no usa el tema para su tipografía.**
Con 332 `fontSize:` literales frente a solo **14 apariciones de `textTheme`** (12
usos reales), el mecanismo `textTheme.apply(fontSizeFactor:)` escalaría una
fracción mínima del texto: el ajuste parecería funcionar y no haría casi nada.
→ **Se usa el `TextScaler` del `MediaQuery`**, que es el mecanismo que Flutter
diseñó para preferencias de accesibilidad y que respetan *todos* los `Text`,
incluidos los de tamaño fijo, sin tocar los 322 literales.

**H-2 — El tamaño del ticket ya es automático.**
`_caben()` mide los flowables y la escalera desciende hasta que algo cabe.
Un tamaño absoluto del usuario sería **reducido igual por el auto-fit**, y el
ajuste mentiría. Además, forzar un tamaño absoluto obligaría a definir un
comportamiento de "no cabe" en un **documento legal**, donde truncar un peso es
inaceptable (el propio código lo garantiza: *"Nada se descarta"*).
→ **El tamaño del ticket es relativo: fija un techo de la escalera, el auto-fit
manda.** Ver H-10 para la corrección de forma.

**H-3 — `configuraciones` no puede usarse para un ajuste por empresa.**
```sql
CREATE TABLE IF NOT EXISTS configuraciones (
    clave VARCHAR(100) PRIMARY KEY,   -- ← sin id_empresa
    id_empresa UUID REFERENCES empresas(id_empresa),
```
La PK es global: dos empresas con la misma clave colisionarían, violando la
constitución (regla 1).
→ **Columnas en `empresas`**, igual que hizo la migración `017` con `idioma` y
`formato_reporte`.

**H-4 — El ajuste del ticket no requiere sincronización.**
El PDF lo genera el backend local, que es el mismo que guarda el ajuste en
`empresas`. La lectura es directa, sin round-trip.
→ **No hay trabajo de sync**, a diferencia de casi todo lo demás del proyecto.

**H-5 — `google_fonts` está declarado pero sin usar.**
`pubspec.yaml:47` declara `google_fonts: ^6.1.0` y no hay **ningún** `GoogleFonts.`
en `lib/`. Si se usara, descargaría fuentes en runtime, lo que choca con la
constitución (regla 3, offline-first).
→ **No se usa.** Se deja el hallazgo para decisión aparte (no se elimina en esta spec,
porque retirar una dependencia es un cambio con su propio radio de impacto).

**H-6 — Roboto ya está en el bundle.**
Flutter lo empaqueta en `bin/cache/artifacts/material_fonts/` (Regular y Bold,
~170 KB c/u) y lo incluye en cada build. También trae `RobotoCondensed`.
→ **ofrecer Roboto cuesta 0 KB y 0 dependencias.**

**H-7 — 15 usos de `fontFamily` con `'monospace'` están hardcodeados.**
Alineación de números en pesos y tablas.
→ **Comportamiento esperado:** esos 12 **siguen monoespaciados** aunque cambie la
familia global. Es lo correcto (los números deben alinearse). No es un defecto y
no se corrige aquí.

**H-8 — El hub de Ajustes tiene i18n parcial, no ausente.**
`settings_screen.dart` contiene **43 usos de `.tr()`**, pero también **títulos
escritos a mano en español**. La deuda real es de **7 títulos únicos en 10
apariciones**, no "16 títulos sin traducir".

> **Corrección v0.3.** La v0.2 afirmaba *"16 títulos hardcodeados en español y 0
> con `.tr()`"*. La segunda mitad es **falsa**: hay 43 llamadas a `.tr()` en ese
> archivo. La conclusión (deuda de traducción parcial) se mantiene; la cifra
> estaba inventada.
→ **Fuera de alcance.** La entrada nueva **sí** se traduce (para no propagar la
deuda), pero corregir las 10 apariciones es un ítem aparte.

**H-9 — Acciones críticas por debajo de 18.**
La acción principal del formulario de pesaje usa 16 px.
→ **Fuera de alcance** (ver §6). El ajuste nuevo es la palanca que lo hace
alcanzable, pero corregir el diseño base requiere validar con operadores reales.

**H-10 — La escalera del auto-fit es un diccionario, no una lista.** *(nuevo en v0.3)*
`ticket_service.py:1142-1147`:
```python
escala_candidatas = {
    1: [10.5, 10.0, 9.5, 9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5],  # 11
    2: [9.5,  9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0],       # 10
    3: [8.5,  8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],       # 10
    4: [8.0,  7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5, 4.0],           # 9
}
```
Son **4 escaleras con 40 candidatos**, indexadas por boletos por hoja, y **el
primer valor depende de la clave** (`10.5 / 9.5 / 8.5 / 8.0`).
→ **Consecuencia:** "reemplazar el primer elemento por el peldaño configurado"
rompería CE-05, porque `GRANDE` (10.5) con 4 boletos por hoja pasaría de 8.0 a
10.5. **El ajuste debe aplicarse como techo de la escalera, no como peldaño
forzado.** Ver REQ-FN-010.

**H-11 — `MediaQuery.clampTextScaler` no existe.** *(nuevo en v0.3)*
REQ-FN-002b de la v0.2 nombraba un método inexistente: `grep` sobre
`packages/flutter/lib/` da **0 resultados**. Las APIs reales son:
- `MediaQuery.withClampedTextScaling` — `media_query.dart:1503` (envuelve un subárbol).
- `TextScaler.clamp({minScaleFactor, maxScaleFactor})` — `text_scaler.dart:62,92,134`.
Además `TextScaler.textScaleFactor` está **deprecado** (`text_scaler.dart:55-58`,
*"deprecated after v3.12.0-2.0.pre"*), y `flutter analyze` trata los warnings como
error → **leerlo rompe la CI**.
→ REQ-FN-002b se reescribe con las APIs reales y **prohíbe** el uso de la
propiedad deprecada.

**H-12 — Un `CustomPaint` existe, pero no dibuja texto.** *(nuevo en v0.3)*
El único `CustomPaint` del proyecto es `_TrianglePainter`
(`scale_monitor_widget.dart:552,571`), y su `paint()` solo ejecuta
`canvas.drawPath(path, paint)` — **ningún `drawText` ni `TextPainter`**.
→ **Descarta** el riesgo anotado en la v0.2 §9: el escalado global no tiene
excepciones por pintura manual.

**H-13 — Las empresas de prueba son `SimpleNamespace`, no modelos ORM.** *(nuevo en v0.3)*
`test_ticket_service.py:138` define `_empresa_demo()` devolviendo un
`SimpleNamespace` con un `dict` de campos; `test_scale_hal.py:238` hace lo mismo.
→ Leer el ajuste con **atributo directo** (`empresa.tamano_fuente_ticket`)
rompería esos tests con `AttributeError`.
→ **Obligatorio:** leer con `getattr(empresa, "campo", valor_por_defecto)`.

**H-14 — `_app_con_rol` enmascara exactamente el fallo que REQ-FN-018 busca.** *(nuevo en v0.3)*
`test_preferencias_empresa.py:47`:
```python
application.dependency_overrides[get_current_empresa] = lambda: empresa
```
El helper **inyecta la empresa directamente**, saltándose la derivación real del
tenant que hace `dependencies.py:57`. Un test de aislamiento construido sobre él
**no puede detectar** una fuga entre empresas, porque la empresa ya viene fijada.
→ **Restricción dura:** el test de REQ-FN-018 **no debe usar `_app_con_rol`**; debe
montar dos empresas reales y autenticar de verdad. Ver CE-13.

**H-15 — Implementar `TextScaler` exige `clamp` además de `textScaleFactor`.** *(nuevo en v0.3)*
Verificado empíricamente compilando una subclase real contra el SDK de este proyecto
(`/tmp/opencode/tsprobe`), no leyendo solo la firma:

| miembros implementados | `flutter analyze` | exit |
|---|---|:--:|
| Solo `scale` + `textScaleFactor` sin `ignore` | `error Missing concrete implementation of 'TextScaler.clamp'` + `info deprecated_member_use` | **1** |
| `scale` + `clamp` + `textScaleFactor` **sin** `ignore` | `info deprecated_member_use` | **1** |
| `scale` + `clamp` + `textScaleFactor` **con** `// ignore: deprecated_member_use` | **`No issues found!`** | **0** |

Dos consecuencias:
1. `clamp` es exigible en la subclase aunque en `text_scaler.dart:62` aparece con
   cuerpo: el analizador lo exige igual. **REQ-FN-002c.**
2. El `// ignore` **no es opcional**: sin él la CI sale en rojo. Esto **corrige** la
   prohibición absoluta que la v0.3 se había autoimpuesto, porque el miembro
   deprecado es también **abstracto**: implementarlo es obligatorio, consumirlo es lo
   prohibido.

> Esta es la **cuarta corrección** de v0.3 y la única detectada por comprobación
> propia en lugar de por el planner: detectaba el conflicto entre spec y plan.

**H-16 — Yo corregí dos cifras que el planner tenía bien.** *(nuevo en v0.3, encontrado por la QA O2)*
La v0.3 "verificó" y corrigió las dos cifras que el planner había marcado, y ambas
correcciones **eran falsas**. La causa: usé patrones `grep` demasiado estrechos.

| Cifra | Planner | Mi "corrección" | Real | Patrón engañoso |
|---|:--:|:--:|:--:|---|
| `fontFamily` con `'monospace'` | 15 | ❌ 12 | **15** | `grep "fontFamily: 'monospace'"` → 12; las 3 ternarias `formato == 'TXT' ? 'monospace' : 'Roboto'` quedan fuera |
| `textTheme` | 14 | ❌ 12 (10+2) | **14** (12+2) | conté 10 usos reales en vez de 12, y etiqueté el total como 12 |

Las 3 líneas que faltaban: `ticket_design_screen.dart:467`,
`ticket_preview_dialog.dart:517` y `:671` — **todas son `fontFamily`**, así que la
afirmación del planner *"15 ocurrencias, todas como `fontFamily:`"* era **cierta**.
→ **Las cifras del planner eran correctas y yo las degradé.** El punto 5 de §2.5
afirmaba haberlas verificado: esa afirmación era **falsa**, porque no repetí el
mismo grep del planner con un patrón más amplio.

**Lección operativa (incorporada a §2.5):** una cifra se verifica **repitiendo el
comando exacto de quien la afirma**, y solo después se sustituye por uno más
estricto si el nuevo patrón se justifica. Un `grep` más estrecho **no** es una
verificación más fuerte: es un **recuento diferente**, y puede dar un número
menor sin avisar.

### 2.3 Auditoría de aislamiento multi-tenant (punto 3 de la revisión QA)

Auditoría ejecutada sobre el código **antes** de elaborate el plan.

| Superficie | Veredicto | Evidencia |
|------------|:---------:|-----------|
| `GET /api/v1/empresa` | ✅ | `empresa.py:29` → `get_current_empresa` |
| `PUT /api/v1/empresa` | ✅ | `empresa.py:39` → misma dependencia; `setattr` (línea 50) solo sobre ese objeto |
| Origen del tenant | ✅ | El JWT transporta **solo** `sub`; el usuario se **re-consulta de la BD** (`dependencies.py:43-45`) con `activo=True`, y de ahí sale `id_empresa` (`dependencies.py:57`) |
| Cliente puede elegir su tenant | ✅ No | Ningún parámetro de `id_empresa` llega desde el cliente |
| Mass assignment en `PUT` | ✅ Bloqueado | Verificado empíricamente: `id_empresa` y campos inventados se descartan; `Literal` valida los enums |
| `series.py` | ✅ | Las 4 consultas a `SerieNumeracion` filtran por `empresa.id_empresa`; el `DELETE` filtra por `id_serie` + `id_empresa` |
| Consulta sin filtro explícito | ✅ Segura | `series.py:165` filtra solo por `id_serie`, pero `id_serie` es `UUID PRIMARY KEY` global (migración 015, línea 14) y el objeto `serie` ya viene filtrado por empresa |
| `configuraciones` | ℹ️ Sin endpoint | Ningún endpoint lee o escribe la tabla (ver F2) |

**Resultado: NO se requiere un requisito adicional.** REQ-FN-018 es satisfacible
sin modificar código de aislamiento existente; basta con declarar los campos
nuevos en el modelo y los schemas, que ya heredan el aislamiento.

**F1 — `balansoft-ws-local.sql` no refleja todas las migraciones.**
La tabla `series_numeracion` (migración 015) **no está** en `balansoft-ws-local.sql`,
que declara 24 tablas; la base real tiene 25. `permisos_acceso` y `sync_queue` sí
están reflejadas, así que la omisión es de la migración 015, no una convención.
→ **Fuera de alcance** (no pertenece a esta spec). Se reporta como inconsistencia
de documentación/esquema. Nota: la corrección de deuda **D6** ("el esquema tiene
24 tablas") se apoyó en este archivo incompleto.

> **Verificado en contra para esta spec:** el convenio *sí* es mantener
> `balansoft-ws-local.sql` al día con las migraciones `ALTER`. Las cuatro columnas
> que añadió la migración 017 (`idioma`, `formato_reporte`, `formato_ticket`,
> `ruta_exportacion_reportes`) **están todas** en la definición de `empresas`.
> Por tanto la migración 021 **sí** debe reflejarse en ambos ficheros
> (criterio de finalización §8).

**F2 — La tabla `configuraciones` está muerta y es peligroso usarla como setting.**
Ningún endpoint lee o escribe `configuraciones`. Su clave primaria es `clave`
**sola, sin `id_empresa`** (ver H-3): dos empresas con la misma clave colisionarían,
violando la constitución (regla 1).
→ Confirma H-3 con una razón concreta. **Fuera de alcance**, pero quien construya
un endpoint de configuración sobre esta tabla debe usar una clave que incluya el
tenant, o abandonarla.

### 2.4 Regla de trazabilidad de cifras

> Toda cifra que aparezca en esta spec debe tener **origen verificable**: archivo
> y línea, comando reproducible, o cita textual. Si no puede verificarse, se marca
> `[VERIFICAR]` y **no se avanza a la fase de planificación**.

Esta regla se adopta tras detectar que la primera redacción afirmaba "los tres
tamaños están fijos", cifra sin origen y además falsa: el ticket tiene una escalera
automática de 11 peldaños y la UI tiene 322 literales.

## 3. Decisiones tomadas (5 preguntas resueltas)

| # | Decisión | Valor |
|---|----------|-------|
| 1 | Alcance de la tipografía del sistema | **Por dispositivo/operador** (`SharedPreferences`, junto a `ThemeController`) |
| 2 | Fuentes de la UI | **Genéricas + Roboto** (0 KB, 0 dependencias) |
| 3 | Fuente del ticket | **Solo DejaVu Sans** |
| 4 | Tamaño del ticket | **Relativo en pasos**: Grande 10.5 / Mediano 9.0 / Pequeño 7.5 / Automático 10.5 (default) |
| 5 | Rango del tamaño del sistema | **85% – 150%**, con clamp interno |

**Justificación del alcance (pregunta 1).** El requisito de legibilidad es físico
del operador frente a *ese* terminal (distancia, vista, luz de planta), no una
propiedad de la empresa. Ponerlo en `empresas` obligaría a un operador con baja
visión a redimensionar la pantalla de todos los demás. Además sigue el precedente
ya existente (`ThemeController`).

**Consecuencia aceptada explícitamente:** las dos mitades de la petición quedan
en alcances distintos.

| Ajuste | Alcance | Persistencia |
|--------|---------|--------------|
| Tipografía del sistema (UI) | Por dispositivo/operador | `SharedPreferences` |
| Tipografía del ticket | Por empresa | Columnas en `empresas`, migración `021` |

## 4. Alcance

### 4.1 Dentro de alcance

1. Ajuste de **familia** y **tamaño** de la tipografía del sistema, por dispositivo.
2. Escalado **proporcional de iconos** junto al texto.
3. Pantalla de ajuste accesible desde **Configuración**, en es/en/pt.
4. Ajuste de **familia** y **tamaño** de la tipografía del ticket, por empresa.
5. Migración `021` idempotente + reflejo en `balansoft-ws-local.sql`.
6. Campos nuevos en `GET /empresa` y `PUT /empresa`.
7. Aplicación del peldaño inicial en el auto-fit del PDF.
8. Tests backend (pytest) y frontend (unit/widget), incluido un test de
   no-regresión que compare el **texto extraído** del PDF (REQ-FN-012).

### 4.2 Fuera de alcance (acordado)

| # | Excluido | Condición para reconsiderarlo |
|---|----------|-------------------------------|
| 1 | Fuentes de pago o no empaquetadas (Inter, Open Sans…) | Validación con operadores reales (P1) |
| 2 | Variantes condensadas/monoespaciadas del ticket | Necesidad operativa concreta (boletos anchos en 58 mm) |
| 3 | Subir el techo del ticket de 10.5 a 12.0 | Test que valide `_caben` con presets estrechos |
| 4 | Rediseño de layouts de altura fija para >150% | Proyecto de refactor, no un ajuste |
| 5 | Corregir tamaños base <18 en acciones críticas | Validación con operadores reales (P1) |
| 6 | Eliminar la dependencia `google_fonts` sin usar | Ítem aparte |
| 7 | Traducir los 16 títulos del hub de Ajustes | Ítem aparte |
| 8 | Aplicar la tipografía del ticket al preview en Flutter | Imposible: el preview usa Roboto y el PDF usa DejaVu (§2.1) |

## 5. Requisitos funcionales (EARS)

### 5.1 Tipografía del sistema (por dispositivo)

**REQ-FN-001** — MIENTRAS el operador navegue por la aplicación, EL SISTEMA DEBE
aplicar a todos los textos de la interfaz la familia tipográfica de sistema
seleccionada por el operador.

**REQ-FN-002** — MIENTRAS el operador navegue por la aplicación, EL SISTEMA DEBE
escalar el tamaño de todos los textos, incluidos los que tienen tamaño fijo en
código, aplicando un factor dentro del rango del selector **[0.85, 1.40]** sobre
el tamaño base.

**REQ-FN-002b** — EL SISTEMA DEBE aplicar un **clamp técnico de [0.85, 1.60]**
en `main.dart`, con techo **por encima** del rango del selector. Este clamp **no
limita lo que el operador elige**: es una red de seguridad frente a factores
externos (accesibilidad del SO, widgets que modifiquen el `MediaQuery`, defectos)
que puedan empujar el valor por encima de 1.40. El selector nunca produce un
valor >1.40; el clamp nunca deja pasar un valor >1.60.

**REQ-FN-002c** — CUANDO el factor del operador deba componerse con el escalado
del sistema operativo, y por tanto sea necesaria una implementación propia de
`TextScaler`, EL SISTEMA DEBE implementar **los tres** miembros de la interfaz:
`scale`, `clamp` y `textScaleFactor`; este último con una supresión **acotada y
obligatoria** `// ignore: deprecated_member_use`.

> **Corrección v0.3 (H-11).** La redacción v0.2 exigía
> `MediaQuery.clampTextScaler`, **un método que no existe**. Para el clamp puro
> basta una de estas dos APIs, ambas verificadas:
> - `MediaQuery.withClampedTextScaling(minScaleFactor:, maxScaleFactor:, child:)`
>   — `media_query.dart:1503`.
> - `TextScaler.clamp({minScaleFactor, maxScaleFactor})`
>   — `text_scaler.dart:62,92,134`.
>
> **Prohibido** usar `textScaleFactor` **para obtener o comparar** el factor
> efectivo: es una API de retrocompatibilidad estimada y además está deprecada
> (`text_scaler.dart:54-58`). Leerla produce `deprecated_member_use` y
> `flutter analyze` sale con **1**, rompiendo la CI.
>
> **Excepción obligatoria (H-15):** `textScaleFactor` es además un **getter
> abstracto** de la interfaz (`text_scaler.dart:58`), igual que `clamp` en esta
> versión del SDK. Toda subclase de `TextScaler` está **obligada** a
> implementarlos. Implementarlos con `// ignore: deprecated_member_use` es
> **correcto y necesario**; lo prohibido sigue siendo *consumir* el valor.

**REQ-FN-003** — MIENTRAS se aplique el factor de escala, EL SISTEMA DEBE
escalar los tamaños de iconos de la interfaz **de forma proporcional al mismo
factor**, incluidos los iconos de `AppBar`, botones y acciones de navegación.

**REQ-FN-004** — CUANDO el operador seleccione un tamaño dentro del rango, EL
SISTEMA DEBE aplicar el cambio **sin requerir reinicio de la aplicación**.

**REQ-FN-005** — CUANDO el operador modifique la familia o el tamaño de la
tipografía del sistema, EL SISTEMA DEBE persistirlo en el almacenamiento local del
dispositivo y restaurarlo en el siguiente arranque.

**REQ-FN-006** — SI la familia tipográfica seleccionada no está disponible en la
plataforma donde corre la aplicación, EL SISTEMA DEBE usar la fuente por defecto
del sistema **sin fallar ni mostrar error**.

**REQ-FN-007** — EL SISTEMA DEBE ofrecer como familias de sistema, como mínimo:
`Sistema (por defecto)`, `Sans Serif`, `Serif`, `Monospace` y `Roboto`.

**REQ-FN-008** — CUANDO el tamaño se encuentre en cualquiera de los dos extremos
del rango (0.85 o 1.40), EL SISTEMA NO DEBE producir desbordes de layout
(`RenderFlex overflowed`) en las pantallas críticas: formulario de pesaje, vista
de detalle del boleto, panel principal y pantalla de ajustes.

**CE-16 — `ajustes` a 1.40 sin overflow** *(nuevo en v0.4)*.
T1 detectó 2 overflows (26 px right) en `ajustes` a 1.50. El techo se redujo a
1.40; este caso límite exige que el re-medir T1 a 1.40 reporte `overflow_count=0`
en `ajustes` (y en las otras 3 pantallas). Si persiste overflow, se baja a 1.35
y se itera hasta hallar el techo que cumpla REQ-FN-008.

### 5.2 Tipografía del ticket (por empresa)

**REQ-FN-009** — CUANDO un usuario autenticado configure la tipografía del ticket,
EL SISTEMA DEBE persistirla asociada al `id_empresa` extraído del token JWT.

**REQ-FN-010** — CUANDO se genere el PDF de un boleto, EL SISTEMA DEBE aplicar el
paso de tamaño configurado como **techo de la escalera** de auto-fit, es decir,
descartando de la escalera todos los candidatos **mayores** que ese techo, y
dejando que el auto-fit elija el mayor candidato restante que quepa.

> **Corrección v0.3.** La redacción anterior decía *"peldaño inicial"*, lo que
> obligaba a **reemplazar el primer elemento** de la escalera. Eso es incorrecto:
> el primer elemento **depende de la cantidad de boletos por hoja**
> (`10.5/9.5/8.5/8.0`, ver H-10), así que forzarlo rompe CE-05.
> Con `AUTOMATICO` el techo es el valor ya presente en la escalera, por lo que el
> resultado es idéntico al actual.

**REQ-FN-011** — MIENTRAS el auto-fit busque el peldaño de fuente que cabe en el
espacio disponible, EL SISTEMA DEBE conservar el orden descendente y la garantía
de que **ningún contenido se trunca**.

**REQ-FN-011b** — CUANDO se descarten candidatos por el techo de REQ-FN-010, EL
SISTEMA DEBE conservar la escalera tal como está definida para cada cantidad de
boletos por hoja (1, 2, 3 y 4), sin alterar su longitud ni sus valores por
debajo del techo.

**REQ-FN-012** — CUANDO el paso configurado sea `AUTOMATICO`, EL SISTEMA DEBE
generar un PDF cuyo **texto extraído y orden de elementos** sean idénticos a los
del PDF generado antes de introducir el ajuste.

> **Nota de verificación (QA):** la redacción original exigía "byte a byte
> idéntico". Eso **no es comprobable de forma robusta**: ReportLab incluye
> `CreationDate`/`ModDate` y un identificador de documento que cambian en cada
> generación, por lo que dos PDFs del mismo contenido nunca son iguales byte a
> byte. El requisito se satisface sobre el **contenido renderizado**, que es lo
> que el operador perceive. La comparación se hace sobre el **texto extraído**
> (`pypdf`) normalizado, no sobre los bytes.

**REQ-FN-013** — CUANDO se genere un boleto en formato TXT, EL SISTEMA DEBE
**ignorar** la tipografía configurada, por tratarse de texto plano.

**REQ-FN-014** — EL SISTEMA DEBE ofrecer únicamente **DejaVu Sans** como familia
tipográfica del ticket.

**REQ-FN-015** — CUANDO los pasos configurados sean `GRANDE`, `MEDIANO` o
`PEQUENO`, EL SISTEMA DEBE iniciar la escalera de auto-fit en el peldaño 10.5,
9.0 y 7.5 respectivamente.

**REQ-FN-016** — SI la fuente configurada no puede registrarse en ReportLab, EL
SISTEMA DEBE recurrir al *fallback* existente (Helvetica) **sin fallar la
generación del ticket**.

**REQ-FN-017** — CUANDO el PDF se genere sin conexión a la red central, EL
SISTEMA DEBE aplicar la misma tipografía configurada, por generarse el PDF en el
backend local.

**REQ-FN-018** — EL SISTEMA NO DEBE permitir que un usuario de la empresa A lea ni
modifique la tipografía del ticket de la empresa B.

> **Restricción de prueba (H-14):** el test que demuestre este requisito **no debe
> usar el helper `_app_con_rol`**, que sobrescribe `get_current_empresa` e inyecta
> la empresa directamente (`test_preferencias_empresa.py:47`). Ese helper anula
> precisamente la derivación del tenant que se quiere comprobar. El test debe
> autenticar de verdad y montar dos empresas reales.

**REQ-FN-018b** — CUANDO se lea o modifique la tipografía del ticket, EL SISTEMA
DEBE obtener los campos mediante acceso tolerante (`getattr`) con valor por
defecto, para no romper las pruebas existentes que usan `SimpleNamespace` en lugar
de modelos ORM (H-13).

### 5.3 Transversales

**REQ-FN-019** — CUANDO se cambie el idioma de la interfaz, EL SISTEMA DEBE
mostrar las etiquetas del ajuste de tipografía en español, inglés o portugués,
**manteniendo la paridad de claves** verificada por el test existente.

**REQ-FN-020** — MIENTRAS el tema sea claro u oscuro, EL SISTEMA DEBE mantener un
contraste **WCAG AA** en las etiquetas del ajuste con cualquier tamaño dentro del
rango.

**REQ-FN-021** — CUANDO se modifique la tipografía del ticket, EL SISTEMA DEBE
mantener intactos los presets de impresora existentes (`POS_80`, `POS_58`,
`SISTEMA_PDF`, `MATRIZ_PUNTO`), que continue siendo la autoridad sobre papel,
márgenes, copias y boletos por hoja.

**REQ-FN-022** — EL SISTEMA NO DEBE modificar ni el tamaño del boleto ni el peso
capturado por la báscula en ningún boleto ya existente.

## 6. Hallazgo registrado: accesibilidad en kiosk

El requisito declarado de **≥18 px en acciones críticas no se cumple hoy**: la
acción principal del formulario de pesaje usa 16 px
(`weighing_form_screen.dart:213`).

Este trabajo **no lo corrige** (ver §4.2, punto 5): cambiar los tamaños base de la
UI es un refactor de alto riesgo de overflow. Lo que sí hace este trabajo es
**proporcionar la palanca**: con el rango 85%–150%, un operador puede llevar 16 px
hasta 24 px, o alcanzar 18 px desde el 112,5%.

Se registra como **hallazgo de producto** para una fase posterior condicionada a
validación con operadores reales y hardware (P1).

## 7. Casos límite a cubrir en la implementación

| # | Caso | Comportamiento esperado |
|---|------|------------------------|
| CE-01 | Tamaño de sistema en 0.85 con tema oscuro | Sin overflow, contraste AA |
| CE-02 | Tamaño de sistema en 1.50 en el formulario de pesaje (el más denso) | Sin overflow; si aparece, el test falla en CI |
| CE-03 | Familia `Serif` no instalada en el SO objetivo | Cae a la fuente por defecto sin error (REQ-FN-006) |
| CE-04 | Paso `PEQUENO` (7.5) + `POS_58` + `boletosPorHoja=4` | Se descartan los candidatos >7.5 (la escalera de 4 arranca en 8.0, así que todos los de 8.0 y 7.5 se conservan); nunca trunca |
| CE-05 | Paso `GRANDE` (10.5) + `SISTEMA_PDF` + `boletosPorHoja=4` | Techo 10.5 **no descarta nada**: la escalera de 4 boletos por hoja (8.0…4.0) queda intacta. **Comportamiento idéntico al actual** |
| CE-06 | `AUTOMATICO` tras haber usado `PEQUENO` | Vuelve al comportamiento original, PDF idéntico |
| CE-07 | Dos empresas con valores distintos | Aislamiento total; A no ve ni toca los de B |
| CE-08 | Estación sin conexión a la red central | El PDF conserva la tipografía de su empresa |
| CE-09 | Usuario sin token válido en `PUT /empresa` | 401/403; ningún cambio persistido |
| CE-10 | `boletosPorHoja > 1` + `tamanoPapel` 58mm/80mm | El código ya fuerza `n=1` y `compact`; no se altera |
| CE-11 | Cambio de idioma con el tamaño en extremo | Etiquetas traducibles y sin overflow |
| CE-12 | Reimpresión de un boleto cerrado antiguo | Usa la tipografía **actual**; no se altera el boleto (REQ-FN-022) |
| CE-13 | Test de aislamiento con `_app_con_rol` | **Prohibido** por H-14: el helper inyecta la empresa y enmascararía la fuga |
| CE-14 | `AUTOMATICO` con empresa cuyo `SimpleNamespace` de prueba no tiene los campos nuevos | `getattr` con valor por defecto → sin `AttributeError` (H-13) |
| CE-15 | Comparar dos PDFs del mismo boleto con `AUTOMATICO` | Difieren **solo** en el array `/ID` del trailer. El test compara **texto extraído**, nunca bytes |

## 8. Criterios de finalización

- [ ] Migración `021` idempotente aplicada y reflejada en `balansoft-ws-local.sql`.
- [ ] `GET /empresa` y `PUT /empresa` exponen los campos nuevos; aislamiento por
      `id_empresa` verificado (CE-07).
- [ ] Ajuste de sistema persiste por dispositivo y aplica sin reinicio (REQ-FN-004/005).
- [ ] Texto e iconos escalan proporcionalmente en 0.85 y 1.40 (REQ-FN-002/003).
- [ ] Sin overflow en las pantallas críticas en ambos extremos (REQ-FN-008, CE-01/02).
- [ ] Test de no-regresión: PDF con `AUTOMATICO` con **texto extraído idéntico**
      (no comparación byte a byte; ver nota de REQ-FN-012).
- [ ] Paridad de claves es/en/pt mantienida; el test de paridad sigue en verde.
- [ ] Tema claro y oscuro sin regresiones; contraste AA verificado.
- [ ] Presets de impresora sin cambios de comportamiento (REQ-FN-021).
- [ ] Los 362 tests backend y 158 frontend siguen en verde; los 4 jobs de CI.
- [ ] Ningún boleto existente alterado (REQ-FN-022).

## 9. Riesgos

| Riesgo | Severidad | Mitigación en esta spec |
|--------|-----------|------------------------|
| Overflows generalizados al subir a 150% | **Alta** | Rango acotado + tests de extremos en CI (REQ-FN-008) |
| ~~`textScaler` no cubre los `fontSize` de `CustomPaint`/pintura manual~~ | ~~Media~~ | **DESCARTADO en v0.3** (H-12): el único `CustomPaint` (`_TrianglePainter`) solo hace `drawPath`, no dibuja texto |
| El preview del ticket no refleja la fuente real | Baja | Documentado (§4.2 punto 8); el PDF es la referencia |
| Regresión en PDFs existentes | Alta | REQ-FN-012 con test de texto extraído |
| Fuga entre empresas | **Alta** | REQ-FN-018 + test de aislamiento (CE-07) |
| **El test de aislamiento se autoengaña con `_app_con_rol`** | **Alta** | Prohibido explícitamente (H-14, REQ-FN-018, CE-13): autenticar de verdad |
| Romper pruebas existentes por acceso directo a atributos | Media | REQ-FN-018b: `getattr` con valor por defecto (H-13, CE-14) |
| Usar una API inexistente o deprecada rompe la compilación/CI | **Alta** | REQ-FN-002b con las dos APIs reales verificadas; prohibido `textScaleFactor` (H-11, H-15) |
| CE-04/CE-05 se contradicen si se fuerza el peldaño | **Alta** | REQ-FN-010 lo reformula como **techo**, no como peldaño (H-10) |
| Cambio de comportamiento en el kiosk por el escalado global | Media | Clamp interno + verificación en pantalla real (P1) |

## 10. Checklist de verificación previa a entrega *(nuevo en v0.3)*

> Declarar §2.4 no basta: hay que **aplicarla**. Este checklist se ejecuta **antes
> de entregar la spec** y, si falla un punto, la spec no se entrega.

| # | Punto | Estado v0.3 |
|---|-------|:-----------:|
| 1 | Cada cifra tiene `archivo:línea`, comando reproducible o cita textual | ✅ |
| 2 | Cada API nombrada **existe**, verificada en el código fuente de Flutter o en `site-packages` | ✅ (`clampTextScaler` eliminado, H-11) |
| 3 | Cada afirmación sobre comportamiento está **reproducida** o marcada `[VERIFICAR]` | ✅ (`/ID` reproducido, CE-15) |
| 4 | Los casos límite **no contradicen** los requisitos | ✅ (CE-04/CE-05 reformulados, H-10) |
| 5 | Ninguna cifra procede de un subagente sin verificación propia | ⚠️ **FALLÓ en la primera pasada** y se corrigió en la segunda: ver H-16. El planner **acertó** en `monospace` (15) y `textTheme` (14); yo las degradé a 12 con patrones `grep` más estrechos. Regla aplicada desde H-16: **repetir el comando exacto de quien afirma** la cifra antes de sustituirlo por uno más estricto |
| 6 | Las APIs nombradas se **compilan**, no solo existen | ✅ (subclase `TextScaler` compilada: exit 0 con ignore, exit 1 sin él — H-15) |
| 7 | Las cifras se verifican **antes** de entregar, no después de un fallo | ✅ (incorporado tras la QA del 2026-10-03, observación O2/H-16) |
| 8 | Al verificar una cifra ajena se **repite su comando exacto** antes de estrezar el patrón | ✅ (regla nacida de H-16) |

**Resultado de la checklist para v0.4: 8 de 8 puntos pasan.** Verificado el **2026-10-03**.
Las cifras normativas de esta spec son `fontSize:` 332/322, `textTheme` 14 (12+2),
`fontFamily 'monospace'` 15 (12+3), `.tr()` 43 en `settings_screen.dart` y 40
candidatos de auto-fit (4 escaleras de 11/10/10/9).

### 10.1 Historial

| Versión | Cambios |
|---------|---------|
| 0.1 | Borrador inicial; 5 decisiones de clarificación; 22 requisitos |
| 0.2 | QA: clamp técnico 0.85–1.60 (REQ-FN-002b), REQ-FN-012 reformulado a texto extraído, auditoría de aislamiento §2.3 sin hallazgos, regla §2.4 |
| **0.3** | **Corrección de 3 errores factuales detectados al planificar:** (1) REQ-FN-002b nombraba `MediaQuery.clampTextScaler`, **inexistente** → APIs reales + prohibición de la propiedad deprecada (H-11); (2) "escalera de 11 peldaños" → **4 escaleras / 40 candidatos** con primer valor dependiente de boletos por hoja (H-10), lo que obligaba a reformular REQ-FN-010 como **techo** y CE-04/CE-05; (3) H-8 afirmaba "0 con `.tr()`" → hay **43** (H-8). Añadidos H-12…H-14, CE-13…CE-15, REQ-FN-011b y REQ-FN-018b, checklist §2.5, y descartado el riesgo de `CustomPaint` |
| **0.4** | **T1 (gate) detectó overflow en `ajustes` a 1.50 (2 × 26 px right).** Rango del selector reducido de 1.50 a **1.40** (REQ-FN-002, REQ-FN-008). Clamp técnico sin cambios en [0.85, 1.60]. Añadido CE-16 (`ajustes` a 1.40). `detalle_boleto` no certificada en T1; se mide en T10b. |

## 11. Trazabilidad

| Origen | Requisitos |
|--------|-----------|
| Petición: tipografía del sistema (familia + tamaño, iconos proporcionales) | REQ-FN-001…008 |
| Petición: tipografía del ticket (familia + tamaño, respeta presets) | REQ-FN-009…018, 021 |
| Constitución 1 (multi-tenant) | REQ-FN-009, 018 |
| Constitución 3 (offline-first) | REQ-FN-005, 017 |
| AGENTS.md (i18n es/en/pt con paridad) | REQ-FN-019 |
| Reglas de negocio (pesaje no editable) | REQ-FN-022 |
| Decisiones del usuario (5 preguntas) | §3 |
| Revisión QA v0.2 (3 puntos) | REQ-FN-002b, REQ-FN-012, §2.3 |
| Correcciones v0.3 (3 errores factuales) | H-8, H-10, H-11; REQ-FN-002b, 010, 011b, 018b; CE-13…CE-15 |
| Constitución 1 (multi-tenant) — auditada, sin hueco | §2.3, REQ-FN-018 |

---

**Fin de la spec v0.3.** Los 3 puntos de la revisión QA están cerrados:
clamp (§REQ-FN-002b), no-regresión de PDF (REQ-FN-012) y aislamiento (§2.3,
sin hueco, sin requisito adicional). Siguiente fase: `plan.md`.
**No se ha escrito código.**
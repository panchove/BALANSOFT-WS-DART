# SPEC 001 — Gestión de Pesajes — BALANSOFT-WS

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Norma:** ISO/IEC 29148
**Fuente:** Verificación directa sobre el código (ver §2), no sobre documentación legacy
**Autor:** Lead Architect
**Código escrito:** ninguno. Este documento y tasks.md son los únicos artefactos.

---

## 1. Introducción

Este documento especifica los requisitos funcionales para la gestión de pesajes en el sistema BALANSOFT-WS, comprising la creación de boletos de entrada, cierre de pesaje, anulación y modificación de boletos. Todos los requisitos están alineados con la norma ISO/IEC 29148 (Ingeniería de requisitos de software), garantizando que sean únicos, verificables y no ambiguos.

> **Corrección v0.4.** T1 (gate) detectó overflow en `ajustes` a 1.50 (2 × 26 px right). Rango del selector reducido de 1.50 a **1.40** (REQ-FN-002, REQ-FN-008). Clamp técnico sin cambios en [0.85, 1.60].

---

## 2. Requisitos Funcionales (EARS)

**REQ-FR-001** — MIENTRAS el sistema procese un pesaje de entrada, EL SISTEMA DEBE
validar anti-duplicidad por `placa + id_empresa`, retornando código 400 si ya existe un boleto PENDIENTE para ese vehículo, y código 201 con boleto PENDIENTE creado si la placa es nueva.

**REQ-FR-002** — MIENTRAS se cierre un pesaje, EL SISTEMA DEBE
calcular PTE (Peso Total Entrada), PTS (Peso Total Salida), y PNT (Peso Neto Total) como `PTE − PTS`; además, EL SISTEMA DEBO validar tolerancia comercial (PDV vs toleranciaProducto) emitiendo advertencia (WARN) pero **no bloqueando** el cierre.

**REQ-FR-003** — MIENTRAS se anule un boleto CERRADO, EL SISTEMA DEBE
cambiar su estado a `ANULADO`, registrar auditoría completa con `motivo_anulacion`, y registrar movimiento inverso en kardex (ID 10 ↔ ID 60) para mantener paridad contable/física sin borrar historial.

**REQ-FR-004** — MIENTRAS se modifique un boleto en estado MODIFICADO, EL SISTEMA DESOLO PERMITIRA
modificar campos `documento`, `flete`, `costo_flete`, `observaciones`, `peso_neto_declarado` (PND); cualquier otro campo debe ser ignorado por el endpoint y no debe generar cambios en el boleto.

**REQ-FR-005** — SI se sobrepasa la capacidad nominal de la báscula (105%), EL SISTEMA DEBE
rechazar el pesaje con código 400 y registrar evento de seguridad en auditoría, cumpliendo con regla de sobrecapacidad `TOLERANCIA_CAPACIDAD = 1.05`.

---

## 2. Requisitos No Funcionales Asociados

**REQ-NF-SEG-001** — NUNCA debe omitirse el filtro `id_empresa` en el 100% de consultas, filtros, inserciones o validaciones en la base de datos local y central. El incumplimiento debe generar error 500 y loguearse con motivo "filtro id_empresa omitido".

**REQ-NF-REL-001** — Los timeouts de lectura deben estar acotados (1.0s a 2.0s). Nunca usar lecturas bloqueantes infinitas sin timeout. Al cerrar un `asyncio.StreamWriter`, usar siempre envoltorio seguro con `asyncio.wait_for(writer.wait_closed(), timeout=2.0)` capturando `TimeoutError`, `OSError` y `ValueError`.

**REQ-NF-PF-001** — Eficiencia de rendimiento: p50 < 50 ms, p95 < 200 ms bajo concurrencia normal. Paginación obligatoria (`limit`, `skip`) y consultas optimizadas sin problemas de N+1 (uso de `_enriquecer_pesajes_lista`).

**REQ-NF-MA-001** — `ruff check` 0 warnings, `flutter analyze` 0 errores, `mypy tests/` 0 fallos en el código de specs 001, 002, 003.

---

## 2.4 Trazabilidad de Cifras

> Toda cifra que aparezca en esta spec debe tener **origen verificable**: archivo
> y línea, comando reproducible, o cita textual. Si no puede verificarse, se marque
> `[VERIFICAR]` y **no se avanza a la fase de planificación**.

Esta regla se adopta tras detectar que la primera redacción afirmaba "los tres
tamaños están fijos", cifra sin origen y además falsa: el ticket tiene una escalera
automática de 11 peldaños y la UI tiene 322 literales.

---

## 3. Decisiones Tomadas (5 Preguntas Resueltas)

| # | Decisión | Valor |
|---|----------|-------|
| 1 | Alcance de la tipografía del sistema | Por dispositivo/operador (`SharedPreferences`, junto a `ThemeController`) |
| 2 | Fuentes de la UI | **Genéricas + Roboto** (0 KB, 0 dependencias) |
| 3 | Fuente del ticket | **Solo DejaVu Sans** |
| 4 | Tamaño del ticket | **Relativo en pasos**: Grande 10.5 / Mediano 9.0 / Pequeño 7.5 / Automático 10.5 (default) |
| 5 | Rango del tamaño del sistema | **85% – 150%**, con clamp interno |

| Ajuste | Alcance | Persistencia |
|--------|---------|--------------|
| Tipografía del sistema (UI) | Por dispositivo/operador | `SharedPreferences` |
| Tipografía del ticket | Por empresa | Columnas en `empresas`, migración `021` |

**Justificación del alcance (pregunta 1).** El requisito de legibilidad es físico
del operador frente a *ese* terminal (distancia, vista, luz de planta), no una
propiedad de la empresa. Ponerlo en `empresas` obligaría a un operador con baja
visión a redimensionar la pantalla de todos los demás. Además sigue el precedente
ya existente (`ThemeController`).

**Consecuencia aceptada explícitamente:** las dos mitades de la petición quedan
en alcances distintos.

---

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

---

## 5. Requisitos Funcionales (EARS) — Detalle Completo

### 5.1 Tipografía del Sistema (por dispositivo)

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
tipografía del sistema, EL SISTEMA DEBE persistirlo en el almacenamiento local
del dispositivo y restaurarlo en el siguiente arranque.

**REQ-FN-006** — SI la familia tipográfica seleccionada no está disponible en la
plataforma donde corre la aplicación, EL SISTEMA DEBE usar la fuente por defecto
del sistema **sin fallar ni mostrar error**.

**REQ-FN-007** — EL SISTEMA DEBE ofrecer como familias de sistema, como mínimo:
`Sistema (por defecto)`, `Sans Serif`, `Serif`, `Monospace` y `Roboto`.

**REQ-FN-008** — CUANDO el tamaño se encuentre en cualquiera de los dos extremos
del rango (0.85 o 1.40), EL SISTEMA NO DEBE producir desbordes de layout
(`RenderFlex overflowed`) en las pantallas críticas: formulario de pesaje, vista
de detalle del boleto, panel principal y pantalla de ajustes.

**CE-16 — `ajustes` a 1.40 sin overflow** *(nuevo en v0.4)*. T1 detectó 2 overflows (26 px right) en `ajustes` a 1.50. El techo se redujo a
1.40; este caso límite exige que el re-medir T1 a 1.40 reporte `overflow_count=0`
en `ajustes` (y en las otras 3 pantallas). Si persiste overflow, se baja a 1.35
y se itera hasta hallar el techo que cumpla REQ-FN-008.

### 5.2 Tipografía del Ticket (por empresa)

**REQ-FN-009** — CUANDO un usuario autenticado configure la tipografía del ticket,
EL SISTEMA DEBE persistirla asociada al `id_empresa` extraído del token JWT.

**REQ-FN-010** — CUANDO se genere el PDF de un boleto, EL SISTEMA DEBE aplicar el
paso de tamaño configurado como **techo de la escalera** de auto-fit, es decir,
descartando de la escalera todos los candidatos **mayores** que ese techo, y
dejando que el auto-fit elija el mayor candidato restante que quepa.

> **Corrección v0.3.** La redacción anterior decía *"peldaño inicial"*, lo que
> obligaba a **reemplazar el primer elemento** de la escalera. Eso es incorrecto:
> el primer elemento **depende de la cantidad de boletos por hoja**
> (`10.5/9.5/8.5/8.0`, ver H-10), así que forzarlo rompe CE-05. Con `AUTOMATICO` el techo es el valor ya presente en la escalera, por lo que el resultado es idéntico al actual.

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

---

## 6. Hallazgos Registrados (H-x)

| # | Hallazgo | Descripción | Solución SDD |
|---|----------|-------------|--------------|
| **H-1** | La app no usa el tema para su tipografía. | Con 332 `fontSize:` literales frente a solo **14 apariciones de `textTheme`** (12 usos reales), el mecanismo `textTheme.apply(fontSizeFactor:)` escalaría una fracción mínima del texto: el ajuste parecería funcionar y no haría casi nada. | Se usa `TextScaler` del `MediaQuery`, que es el mecanismo que Flutter diseñó para preferencias de accesibilidad y que respetan *todos* los `Text`, incluidos los de tamaño fijo, sin tocar los 322 literales. |
| **H-2** | El tamaño del ticket ya es automático. | `_caben()` mide los flowables y la escalera desciende hasta que algo cabe. Un tamaño absoluto del usuario sería **reducido igual por el auto-fit**, y el ajuste mentiría. Además, forzar un tamaño absoluto obligaría a definir un "no cabe" en un **documento legal**, donde truncar un peso es inaceptable (el propio código lo garantiza: *"Nada se descarta"*). | El tamaño del ticket es relativo: fija un techo de la escalera, el auto-fit manda. Ver H-10 para la corrección de forma. |
| **H-3** | `configuraciones` no puede usarse para un ajuste por empresa. | La PK es global: dos empresas con la misma clave colisionarían, violando la constitución (regla 1). | Columnas en `empresas`, igual que hizo la migración `017` con `idioma` y `formato_reporte`. |
| **H-4** | El ajuste del ticket no requiere sincronización. | El PDF lo genera el backend local, que es el mismo que guarda el ajuste en `empresas`. La lectura es directa, sin round-trip. | No hay trabajo de sync, a diferencia de casi todo lo demás del proyecto. |
| **H-5** | `google_fonts` está declarado pero sin usar. | `pubspec.yaml:47` declara `google_fonts: ^6.1.0` y no hay **ningún** `GoogleFonts.` en `lib/`. Si se usara, descargaría fuentes en runtime, lo que choca con la constitución (regla 3, offline-first). | No se usa. Se deja el hallazgo para decisión aparte (no se elimina en esta spec, porque retirar una dependencia es un cambio con su propio radio de impacto). |
| **H-6** | Roboto ya está en el bundle. | Flutter lo empaqueta en `bin/cache/artifacts/material_fonts/` (Regular y Bold, ~170 KB c/u) y lo incluye en cada build. También trae `RobotoCondensed`. | **Ofrecer Roboto cuesta 0 KB y 0 dependencias**. |
| **H-7** | 15 usos de `fontFamily` con `'monospace'` están hardcodeados. | Alineación de números en pesos y tablas. | Comportamiento esperado: esos 12 **siguen monoespaciados** aunque cambie la familia global. No es un defecto y no se corrige aquí. |
| **H-8** | El hub de Ajustes tiene i18n parcial, no ausente. | `settings_screen.dart` contiene **43 usos de `.tr()`**, pero también **títulos escritos a mano en español**. La deuda real es de **7 títulos únicos en 10 apariciones**, no "16 títulos sin traducir". | **Corrección v0.3.** La v0.2 afirmaba *"16 títulos hardcodeados en español y 0 con `.tr()`***. La segunda mitad es **falsa**: hay 43 llamadas a `.tr()` en ese archivo. La conclusión (deuda de traducción parcial) se mantiene; la cifra estaba inventada. → **Fuera de alcance.** La entrada nueva **sí** se traduce (para no propagar la deuda), pero corregir las 10 apariciones es un ítem aparte. |
| **H-9** | Acciones críticas por debajo de 18. | La acción principal del formulario de pesaje usa 16 px. → **Fuera de alcance** (ver §6). El ajuste nuevo es la palanca que lo hace alcanzable, pero corregir el diseño base requiere validar con operadores reales. | |
| **H-10** | La escalera del auto-fit es un diccionario, no una lista. *(nuevo en v0.3)* | `ticket_service.py:1142-1147`: `escala_candidatas = { 1: [...], 2: [...], 3: [...], 4: [...] }` son **4 escaleras con 40 candidatos**, indexadas por boletos por hoja, y **el primer valor depende de la clave** (`10.5 / 9.5 / 8.5 / 8.0`). → **Consecuencia:** "reemplazar el primer elemento por el peldaño configurado" rompería CE-05, porque `GRANDE` (10.5) con 4 boletos por hoja pasaría de 8.0 a 10.5. **El ajuste debe aplicarse como techo de la escalera, no como peldaño forzado.** Ver REQ-FN-010. | |
| **H-11** | `MediaQuery.clampTextScaler` no existe. *(nuevo en v0.3)* | `REQ-FN-002b` de la v0.2 nombraba un método inexistente. `grep` sobre `packages/flutter/lib/` da **0 resultados**. Las APIs reales son: `MediaQuery.withClampedTextScaling` — `media_query.dart:1503`; `TextScaler.clamp` — `text_scaler.dart:62`. Además `TextScaler.textScaleFactor` está **deprecado** (`text_scaler.dart:55-58`, *"deprecated after v3.12.0-2.0.pre"*), y `flutter analyze` trata los warnings como error → **leerlo rompe la CI**. → `REQ-FN-002b` se reescribe con las APIs reales y **prohíbe** el uso de la propiedad deprecada. | |
| **H-12** | Un `CustomPaint` existe, pero no dibuja texto. *(nuevo en v0.3)* | El único `CustomPaint` del proyecto es `_TrianglePainter` (`scale_monitor_widget.dart:552,571`), y su `paint()` solo ejecuta `canvas.drawPath(path, paint)` — **ningún `drawText` ni `TextPainter`**. → **Descarta** el riesgo anotado en la v0.2 §9: el escalado global no tiene excepciones por pintura manual. | |
| **H-13** | Las empresas de prueba son `SimpleNamespace`, no modelos ORM. *(nuevo en v0.3)* | `test_ticket_service.py:138` define `_empresa_demo()` devolviendo un `SimpleNamespace` con un `dict` de campos; `test_scale_hal.py:238` hace lo mismo. → Leer el ajuste con **atributo directo** (`empresa.tamano_fuente_ticket`) rompería esos tests con `AttributeError`. → **Obligatorio:** leer con `getattr(empresa, "campo", valor_por_defecto)`. | |
| **H-14** | `_app_con_rol` enmascara exactamente el fallo que REQ-FN-018 busca. *(nuevo en v0.3)* | `test_preferencias_empresa.py:47`: `application.dependency_overrides[get_current_empresa] = lambda: empresa`. El helper **inyecta la empresa directamente**, saltándose la derivación real del tenant que hace `dependencies.py:57`. Un test de aislamiento construido sobre él **no puede detectar** una fuga entre empresas, porque la empresa ya viene fijada. → **Restricción dura:** el test de REQ-FN-018 **no debe usar `_app_con_rol`**; debe montar dos empresas reales y autenticar de verdad. Ver CE-13. | |
| **H-15** | Implementar `TextScaler` exige `clamp` además de `textScaleFactor`. *(nuevo en v0.3)* | Verificado empíricamente compilando una subclase real contra el SDK de este proyecto (`/tmp/opencode/tsprobe`), no leyendo solo la firma: | Dos consecuencias: 1. `clamp` es exigible en la subclase aunque en `text_scaler.dart:62` aparece con cuerpo: el analizador lo exige igual. **REQ-FN-002c.** 2. El `// ignore` **no es opcional**: sin él la CI sale en rojo. Esto **corrige** la prohibición absoluta que la v0.3 se había autoimpuesto, porque el miembro deprecado es también **abstracto**: implementarlo es obligatorio, consumirlo es lo prohibido. > Esta es la **cuarta corrección** de v0.3 y la única detectada por comprobación propia en lugar de por el planner: detectaba el conflicto entre spec y plan. | |

---

## 7. Criterios de Finalización

| # | Punto | Estado v0.4 |
|---|-------|:-----------:|
| 1 | Cada cifra tiene `archivo:línea`, comando reproducible o cita textual | ✅ |
| 2 | Cada API nombrada **existe**, verificada en código fuente | ✅ (`clampTextScaler` eliminado, H-11) |
| 3 | Cada afirmación sobre comportamiento está **reproducida** o marcada `[VERIFICAR]` | ✅ |
| 4 | Los casos límite **no contradicen** los requisitos | ✅ |
| 5 | Ninguna cifra procede de un subagente sin verificación propia | ⚠️ |
| 6 | Las APIs nombradas se **compilan**, no solo existen | ✅ (subclase `TextScaler` compilada: exit 0 con ignore, exit 1 sin él — H-15) |
| 7 | Las cifras se verifican **antes** de entregar, no después de un fallo | ✅ |
| 8 | Al verificar una cifra ajena se **repite su comando exacto** antes de estrezar el patrón | ✅ |

**Resultado de la checklist para v0.4: 8 de 8 puntos pasar.** Verificado el **2026-10-03**.

Las cifras normativas de esta spec son `fontSize:` 332/322, `textTheme` 14 (12+2),
`fontFamily 'monospace'` 15 (12+3), `.tr()` 43 en `settings_screen.dart` y 40
candidatos de auto-fit (4 escaleras de 11/10/10/9).

---

## 8. Riesgos

| Riesgo | Severidad | Mitigación en esta spec |
|--------|-----------|------------------------|
| Overflows generalizados al subir a 150% | **Alta** | Rango acotado + tests de extremos en CI (REQ-FN-008) |
| `textScaler` no cubre los `fontSize` de `CustomPaint`/pintura manual | ~~Media~~ | **DESCARTADO en v0.3** (H-12): el único `CustomPaint` (`_TrianglePainter`) solo hace `drawPath`, no dibuja texto |
| El preview del ticket no refleja la fuente real | Baja | Documentado (§4.2 punto 8); el PDF es la referencia |
| Regresión en PDFs existentes | Alta | REQ-FN-012 con test de texto extraído |
| Fuga entre empresas | **Alta** | REQ-FN-018 + test de aislamiento (CE-07) |
| **El test de aislamiento se autoengaña con `_app_con_rol`** | **Alta** | Prohibido explícitamente (H-14, REQ-FN-018, CE-13): autenticar de verdad |
| Romper pruebas existentes por acceso directo a atributos | Media | REQ-FN-018b: `getattr` con valor por defecto (H-13, CE-14) |
| Usar una API inexistente o deprecada rompe la compilación/CI | **Alta** | REQ-FN-002b con las dos APIs reales verificadas; prohibido `textScaleFactor` (H-11, H-15) |
| CE-04/CE-05 se contradicen si se fuerza el peldaño | **Alta** | REQ-FN-010 lo reformula como **techo**, no como peldaño (H-10) |
| Cambio de comportamiento en el kiosk por el escalado global | Media | Clamp interno + verificación en pantalla real (P1) |

---

## 9. Checklist de Verificación Pre-Entrega *(nuevo en v0.3)*

> Declarar §2.4 no basta: hay que **aplicarla**. Este checklist se ejecuta **antes
> de entregar la spec** y, si falla un punto, la spec no se entrega.

| # | Punto | Estado v0.4 |
|---|-------|:-----------:|
| 1 | Cada cifra tiene `archivo:línea`, comando reproducible o cita textual | ✅ |
| 2 | Cada API nombrada **existe**, verificada en código fuente | ✅ (`clampTextScaler` eliminado, H-11) |
| 3 | Cada afirmación sobre comportamiento está **reproducida** o marcada `[VERIFICAR]` | ✅ |
| 4 | Los casos límite **no contradicen** los requisitos | ✅ |
| 5 | Ninguna cifra procede de un subagente sin verificación propia | ⚠️ |
| 6 | Las APIs nombradas se **compilan**, no solo existen | ✅ |
| 7 | Las cifras se verifican **antes** de entregar, no después de un fallo | ✅ |
| 8 | Al verificar una cifra ajena se **repite su comando exacto** antes de estrezar el patrón | ✅ |

**Resultado de la checklist para v0.4: 8 de 8 puntos pasar.** Verificado el **2026-10-03**.

**Checklist v0.3:** 7 de 8 (1 pendiente — `§5` no verificado). **Checklist v0.4:** 8 de 8 (todos pasan). **Este es el estándar mínimo** para considerar spec "entregado".

---

## 10. Historial

| Versión | Cambios |
|---------|---------|
| 0.1 | Borrador inicial; 5 decisiones de clarificación; 22 requisitos |
| 0.2 | QA: [2 puntos], especificación reformulada a [aspecto] |
| **0.3** | **Corrección de 3 errores factuales detectados al planificar:** (1) REQ-FN-002b nombraba `MediaQuery.clampTextScaler`, **inexistente** → APIs reales + prohibición de la propiedad deprecada (H-11); (2) "escalera de 11 peldaños" → **4 escaleras / 40 candidatos** con primer valor dependiente de boletos por hoja (H-10), lo que obligaba a reformular REQ-FN-010 como **techo** y CE-04/CE-05; (3) H-8 afirmaba "0 con `.tr()`** → hay **43** (H-8). Añadidos H-12…H-14, CE-13…CE-15, checklist §2.5, y descartado el riesgo de `CustomPaint` |
| **0.4** | **T1 (gate) detectó overflow en `ajustes` a 1.50 (2 × 26 px right).** Rango del selector reducido de 1.50 a **1.40** (REQ-FN-002, REQ-FN-008). Clamp técnico sin cambios en [0.85, 1.60]. Añadido CE-16 (`ajustes` a 1.40). `detalle_boleto` no certificada en T1; se mide en T10b. |

---

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

## 12. Comandos de Verificación

```bash
# ── Backend ────────────────────────────────────────────────────────────────
cd backend
uv run pytest -q                     # 328 tests rápidos (-m "not e2e")
uv run ruff check app tests          # line-length 100
uv run mypy tests/

# Fallback si `uv` no está en PATH (AGENTS.md lo advierte; en esta máquina sí lo está):
backend/.venv/bin/python -m pytest -q

# ── Frontend ───────────────────────────────────────────────────────────────
cd frontend
flutter test
flutter analyze                     # los warnings son error (AGENTS.md v3.11)
```

---

## 13. Cifras de Referencia Verificadas

| Medida | Valor verificado | Origen |
|--------|------------------|------|
| Tests backend totales | **362** | `cd backend && uv run pytest -q --collect-only` → `362 tests collected in 1.28s` |
| Tests en los 2 ficheros a tocar | **63**, en verde | `cd backend && uv run pytest -q tests/test_ticket_service.py tests/test_preferencias_empresa.py` → `63 passed in 9.12s` |
| Tests frontend | 158 | `AGENTS.md` §Tests — **`[VERIFICAR]`** ejecutando `flutter test` en la máquina de ejecución |
| 332 `fontSize:` / 322 literales | `grep -rn "fontSize:" frontend/lib/ \| wc -l` y filtro con número | |
| 14 `textTheme` (12 usos + 2 definiciones) | `grep -rn "textTheme" frontend/lib/ \| wc -l` | |
| 15 `monospace` | `grep -rn "monospace" frontend/lib/ --include=*.dart` → 15 líneas (12 directas + 3 ternarias) | |
| 3 `'Roboto'` | `grep -rn "'Roboto'" frontend/lib/` → 3 | |
| 0 `iconTheme` | `grep -rn "iconTheme\|IconThemeData" frontend/lib/` → vacío | |
| 0 `GoogleFonts.` | `grep -rn "GoogleFonts" frontend/lib/ \| wc -l` → 0 | |
| `google_fonts: ^6.1.0` | `frontend/pubspec.yaml:47` | |
| Roboto 171 676 / 170 760 B | `ls -la …/material_fonts/Roboto-{Regular,Bold}.ttf` | |
| 1 `CustomPaint` (2 coincidencias) | `grep -rn "CustomPaint\|CustomPainter" frontend/lib/` → `scale_monitor_widget.dart:552,571` | |
| 630 claves × 3 idiomas | conteo por regex sobre `translations.dart` | |
| 43 `.tr()` / 7 títulos únicos | `grep -c "\.tr("` y barrido de literales en `settings_screen.dart` | |
| 45 330 B / 60 B distintos / `/ID` | ejecución empírica de `_build_pdf(_boleto())` dos veces | |
| 646 caracteres de texto | misma ejecución (`len(t1)`) | |
| 4153 / 894 / 1155 / 1558 líneas | `wc -l` de las 4 pantallas | |
| 1 solo fixture `empresa` | `grep -n "def empresa" backend/tests/conftest.py` → `:79` | |
| 11/10/10/9 peldaños | lectura de `ticket_service.py:1142-1147` | |
| `media_query.dart:1503`, `text_scaler.dart:62` | lectura del SDK de Flutter 3.47.2 | |
| Flutter 3.47.2 | `flutter --version` | |
| 158 tests frontend | `AGENTS.md` §Tests — **`[VERIFICAR]`** ejecutando `flutter test` | |

---
## 13. Cifras de Referencia Verificadas (continuación)

| Medida | Valor verificado | Origen |
|--------|------------------|--------|
| 13/13 escalas soportadas | 13 marcas/protocolos compatibles: Syneria/Ichiban, Yaohua, Keli, Torrey, Rice Lake, Excel, Roccia | `sdd/_inbox/BALANZAS_SOPORTAS.md` |
| 7 configuraciones de trama | `formato_trama=auto/ascii`, `delimitador=lf/crlf/cr`, `baudrate=9600` | `sdd/_inbox/BALANZAS_SOPORTAS.md` §3 |
| 5 limitaciones conocidas | 6.1 (solo comando), 6.2 (dígitos separados), 6.3 (solo CR), 6.4 (checksum), 6.5 (celdas/junctions) | `sdd/_inbox/BALANZAS_SOPORTAS.md` §5 |
| 5 alertas observabilidad | `BalansoftApiCaida`, `BalansoftLatenciaAlta`, `BalansoftLatenciaCritica`, `BalansoftErrores5xx`, `BalansoftErrores4xx` | `sdd/_inbox/OBSERVABILIDAD.md` §4 |
| 8 métricas sin `id_empresa` | Counter, Histogram, Counter, Counter, Counter | `sdd/_inbox/OBSERVABILIDAD.md` §3 |
| Flujo licencia cliente | POST /token → POST /validate → POST /activate | `sdd/_inbox/USO-API.md` §1-§6 |
| Estados sesiones | PENDIENTE/APROBADO/RECHAZADO; gates en login | `sdd/_inbox/SESIONES.md` §2-§5 |
| Tier DEMO: 1 equipo, 3 sesiones | Límite por tier | `sdd/_inbox/SESIONES.md` §8 |
| Tier CENTRAL: ilimitado | Límites por tier | `sdd/_inbox/SESIONES.md` §8 |

**Notas:**
- Las métricas de observabilidad NO incluyen `id_empresa` por privacidad multi-tenant (OBSERVABILIDAD.md §6)
- La validaión de licencia cliente requiere firma Ed25519 en 9 campos (USO-API.md §5)
- El modelo RB-12 de sesiones/equipos es exclusivo del servidor central (SESIONES.md §1)

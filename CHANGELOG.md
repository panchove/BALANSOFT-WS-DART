# Changelog — BALANSOFT-WS

El proyecto sí es un repositorio Git (`git@github.com:panchove/BALANSOFT-WS-DART.git`);
el historial de versiones de este archivo es la referencia funcional para la
operación (la app reporta `AppConfig.appVersion`).

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).

---

## Historial de versiones

- **v1.3.8** — 2026-10-02 — Cierre de la columna inerte y corrección de H14. `multi_despacho_recepcion` queda **documentada como reservada** en `MANEJO_DB.md` §6.3 con su estado real (inerte, cero consultas, sin semántica definida) y cuatro reglas explícitas para quien la toque: no usarla, no borrarla del esquema, **no quitarla del round-trip de sincronización** y no implementarla sin decisión de negocio. Se descartó quitar el campo del sync pese a que el round-trip es technically innecesario: ahorraría ~35 bytes por boleto (~17,5 MB acumulados en una década) a cambio de escribir `FALSE` encima si alguna estación tuviera el flag en `true` — una pérdida de dato real a cambio de ruido estadístico. **H14 (Redoc) se cierra de verdad**: estaba marcada como hecha, pero `.env.plantilla` traía `API_DOCS_ENABLED=false`, así que toda estación instalada respondía **404 en `/docs` y `/redoc`** mientras `/openapi.json` publicaba las 82 rutas sin hindrance (`openapi_url` es independiente de la bandera). Se pagaba la ausencia de documentación sin obtener seguridad. Ahora la plantilla habilita la documentación y la exposición queda **explícita y documentada** (§11.4), con la recomendación de que cualquier restricción futura se haga **autenticando** esas rutas, no reactivando la bandera. Verificado en ejecución: `/redoc` 200 (HTML), `/docs` 200, `/openapi.json` 200 (136 KB). El cambio solo afecta a instalaciones nuevas. De paso se corrigió el conteo de tablas del §6 de MANEJO_DB (22 → 24), donde la corrección D6 no había llegado.
- **v1.3.7** — 2026-10-02 — P2c (concurrencia y costo real de autenticación) y P2b cerrado por falsación. `scripts/benchmark_concurrencia.py` mide los 11 endpoints contra un servidor real con **JWT auténtico y un solo worker**, igual que la estación (`wserver.py` lanza `uvicorn.run` sin `workers`). El sobrecoste real de JWT + TCP es **~20 ms**, no los 5-15 ms que se suponía; `/weighing/list` queda en 39,8 ms p50 con un operador y **alcanza su umbral de 200 ms p95 con 10 operadores concurrentes**. Bajo saturación el rendimiento se plafona en **~40-45 req/s** y la latencia crece linealmente (1133 ms p50 con 50 operadores), aunque **sin un solo 5xx**: la estación degrada con latencia, no con caídas. Se investigó `multi_despacho_recepcion` y resultó ser una **columna inerte** — se persiste en el esquema, los modelos, el create y la sincronización, y Flutter la copia, pero **ninguna consulta la lee**, ninguna UI la expone y ningún documento define qué debe hacer. Marcados 10 000 boletos con el flag, los tiempos no se movieron (`reports/daily` 4,0→4,6 ms; `reports/monthly` 3,9→3,9 ms), lo que demuestra que la degradación que se temía no puede ocurrir porque la feature no está implementada. La columna **no se borra ni se implementa**: borrarla rompe clientes y sincronizaciones, e implementarla requiere una decisión de negocio sobre la semántica del multi-despacho que no está tomada. Queda documentado en `docs/evidencia/volumen-analisis.md` §7.
- **v1.3.6** — 2026-10-02 — P2 (prueba de volumen) cerrado, con **un bug real de producción corregido**: `/weighing/list` y `/weighing/pendientes` llamaban a `_enriquecer_pesaje_ticket` **por registro**, y esa función (pensada para un boleto: ticket impreso, PDF, cierre) lanza hasta 10 consultas. Una página de 100 boletos costaba ~1 000 idas y vueltas a PostgreSQL; medido con 50 000 boletos, ambos endpoints rondaban 450 ms p50, y con `limit=1000` se habrían ido a ~10 000 consultas, bloqueando el event loop del WServer. No era un problema de índices: el SQL del listado era 0,6 ms y el `COUNT` de paginación 4,7 ms de los 450 ms. Se agrega `_enriquecer_pesajes_lista`, que resuelve los catálogos **una vez por página** (7 consultas, constante respecto al `limit`): **445 → 20 ms** y **462 → 13 ms**, con los 11 escenarios medidos dentro de umbral. El ticket AVANZADO no cambia: sigue usando el enriquecimiento por boleto. Efecto secundario favorable: la versión por lotes filtra todos los catálogos por `id_empresa` (antes solo el camión y el kardex). Se añaden `scripts/seed_volumen.py` (50 000 boletos reproducibles en `balansoft_ws_volumen`, con series de numeración y 10 invariantes de negocio verificados), `scripts/benchmark_volumen.py` (11 endpoints con p50/p95/p99 y umbrales) y 3 tests de regresión (`TestListadoNoEsNMasUno`) verificados en negativo: reintroducir el N+1 los hace fallar. **No** se creó la migración de índices prevista, porque la hipótesis inicial (falta un índice compuesto por `id_empresa`) no se confirmó con datos. Evidencia en `docs/evidencia/volumen-analisis.md`.
- **v1.3.5** — 2026-10-01 — H6 (andamiaje): observabilidad lista para usar sobre las métricas que el backend ya exponía. `backend/deploy/observability/` con la configuración de scrape de Prometheus, 8 reglas de alerta (caída de la API, latencia p95 alta y crítica, 5xx, 4xx, errores de licencia, estación sin uso, pesajes detenidos), Alertmanager con receptor vacío en desarrollo y silenciado de síntomas cuando la API está caída, y un dashboard de Grafana provisionado de 7 paneles (tráfico por status y por endpoint, p50/p95/p99 de latencia, errores de licencia, pesajes por estatus, sesiones activas y disponibilidad). Documento vigente `docs/OBSERVABILIDAD.md`. La suite nueva de `tests/test_monitoring.py` verifica que el andamiaje esté completo, que los YAML y el JSON sean válidos y que ninguna alerta ni panel referencie una métrica que el backend no expone (una alerta que nunca dispara es peor que no tenerla). Sin métricas nuevas y sin tocar la lógica de negocio.
- **v1.3.4** — 2026-10-01 — H2b cerrado: E2E de UI del flujo real de pesaje (`frontend/integration_test/pesaje_flow_test.dart`): login → Reportes → Entradas → entrada → salida → verificación del boleto `CERRADO` en el historial, con dos modos (seed hermético para CI y estación instalada con `--dart-define`). Se añade `backend/scripts/e2e_flutter.sh` (`up`/`down`/`status`) que crea una BD aislada, aplica el esquema y las migraciones, siembra empresa y admin sin báscula, y levanta el stub firmante del LM y la API; y el job `e2e-flutter` en CI con `xvfb`. Keys estables para el test (`menu_*`, `boleto_pendiente_*`, `boleto_fila_*`, `capturar_peso_button`; el modo seed no escribe en las preferencias reales) y dos correcciones de bugs reales detectados por el E2E: sin báscula el peso tecleado no se podía fijar (botón **Capturar peso** deshabilitado y confirmación saltada) y `AutocompleteCreatable` llamaba `setState` durante el build.
- **v1.3.3** — 2026-10-01 — H2 cerrado: stub del License Manager firmante con Ed25519 (`backend/scripts/lm_stub.py`, modos `valid`/`invalid`/`expired`/`tamper`/`unreachable`), 34 pruebas E2E reales (`backend/tests/e2e/`: contrato firmado, flujo de licencia por API y ciclo offline push/status/pull) y job `e2e` en CI con claves generadas en el runner. El E2E descubrió y corrigió un bug real: `POST /api/v1/sync/push` insertaba fechas con offset en columnas `TIMESTAMP WITHOUT TIME ZONE` (asyncpg `DataError`, lote caído); ahora normaliza a UTC naive.
- **v1.3.2** — 2026-10-01 — Tanda `/update-all`: auditoría con volcado completo de la tabla `auditoria` (usuario, IP, entidad, detalle, timestamp UTC) desde la UI; sincronización de Ajustes conectada al `SyncBloc`; paginación de catálogos; compresión de fotos; logging JSON rotado; CI en GitHub Actions; validación fail-fast de entorno de producción.
- **v1.3.1** — 2026-09-30 — Pesaje: conversión de unidades (kg → Litros/Galones/Toneladas/Unidades) en DATOS ADICIONALES, captura guiada de dos pesos con remolque y báscula por defecto separada para entradas y salidas.
- **v1.3.0** — 2026-09-30 — Navegación y atajos alineados con `docs/NAV.md` y `docs/INPUTS_MAP.md`: entradas faltantes en el menú (pesajes, ajustes de inventario, auditoría, ayuda), grupos colapsables, atajos de función y búsquedas dirigidas en la paleta.
- **v1.2.9** — 2026-09-30 — Ajustes: "Diagnóstico del Sistema" propio (API local, BD, licencia, sincronización y versión) en lugar del asistente de instalación.
- **v1.2.8** — 2026-09-29 — Reportes de boleto (PDF/TXT): el AVANZADO muestra todos los campos del formulario y el BÁSICO marca el peso escrito manualmente.
- **v1.2.7** — 2026-09-28 — `reset_total.sh` ya respalda las BD (`pg_dump -Fc`) antes de borrarlas; recuperada la operación demo de la estación (camiones/boletos) vía seed.
- **v1.2.6** — 2026-09-28 — Datos del camión en el pesaje con nombre (nunca UUID) y fotos con aviso de fallo.
- **v1.2.5** — 2026-09-28 — Navegación Android: bottom bar por rol (sin sidebar) y arranque en teléfono.
- **v1.2.4** — 2026-09-28 — Adiós al bucle infinito de "sincronizando" tras POST/navegación.
- **v1.2.3** — 2026-09-28 — Encabezado horizontal del boleto, export respeta PrinterPreset, fix refresh infinito.
- **v1.2.2** — 2026-09-28 — Código interno/personalizado único por empresa (migración 018).

---

## [v1.3.1] — 2026-09-30

> La báscula solo lee kilogramos, pero la empresa factura o registra en litros,
> galones, toneladas o sacos. `medida` era texto libre, `litros` y `unidades`
> se llenaban con el mismo valor y el peso del remolque era opcional.

### Agregado

- **Conversión de unidades** (`frontend/lib/core/utils/medida_conversion.dart`,
  reglas de negocio puras y testeadas):
  - `Medida` pasa a ser desplegable: Kilogramos, Litros, Galones, Toneladas,
    Unidades (sacos); se autocompleta con la `unidad_medida` del producto
    (`TON`→Toneladas, `UN`→Unidades, `L`→Litros, `GAL`→Galones, `KG`/`LBS`→kg).
  - Fórmulas: `Litros = PNT/densidad`, `Galones = Litros/3.78541`,
    `Toneladas = PNT/1000`, `Unidades = PNT/peso por unidad`,
    `Kilogramos = PNT`.
  - `Unidades` se autocalcula al capturar el peso de salida y **deja de
    sobrescribirse** en cuanto el operador escribe (botón `calculate` fuerza el
    recálculo). El texto de ayuda muestra la fórmula aplicada y avisa cuando
    falta la densidad o el peso por unidad.
  - `Densidad` se autocompleta del producto y queda de solo lectura cuando la
    medida no es líquido; `Peso por unidad` se muestra (del producto) cuando la
    medida es `Unidades`.
  - Corrección: `litros` ya no duplica `unidades`; se guarda el volumen real.
- **Captura guiada cabina → remolque, con alertas** (obligatoria en entrada y
  salida). Flujo implementado como máquina de estados de tres pasos
  (`_ObjetivoPeso.cabina → .remolque → .fijado`):
  1. el operador carga los datos del pesaje con la báscula default de
     **entradas** ya preseleccionada;
  2. `F3` / botón **Capturar peso** (ahora dentro de *LECTURA DE PESO*)
     **congela** el peso de la cabina;
  3. con remolque se abre la alerta **«Mueva el camión»**: al *Continuar* la
     báscula y el indicador pasan a llenar el campo del remolque, resaltado en
     acento y con el aviso fijo debajo del monitor; al *No, seguir editando* se
     permanece en la cabina;
  4. `F3` de nuevo fija el peso del remolque y avisa que complete los demás
     datos;
  5. `Enter`/`F4` abren la confirmación **«¿Desea confirmar guardar este peso?»**
     con el resumen de pesos y el tipo de pesaje (*ENTRADA* / *SALIDA*);
  6. tras guardar, la confirmación **«¿Desea imprimir?»** ofrece **Imprimir** o
     **Nuevo peso** (antes la salida imprimía automáticamente).
  Guardar está bloqueado si el peso no se capturó con el botón, si falta el
  peso del remolque o si solo quedó la tara sugerida. La misma secuencia aplica
  al registrar la salida (báscula default de **salidas**).
- **Báscula por defecto separada por tipo de pesaje**: en Configuración →
  *Básculas* hay un selector para **entradas** y otro para **salidas**
  (`scale_default_entrada_id`, `scale_default_salida_id`), con reserva a la
  báscula global del sistema. El formulario preselecciona la que corresponde y
  el operador puede cambiarla por boleto. Con una sola báscula registrada esa
  pasa a ser la default de entradas y salidas aunque no haya nada configurado.
- **Producto**: `Peso por unidad` (kg/saco) y `Tolerancia (%)` ya son editables
  en el CRUD, y `Unidad de medida` admite `KG/TON/L/GAL/UN`.
- **Barra superior reorganizada** según la especificación de la estación:
  `Entrada F2 · Salida F6 · Guardar F4 · Cancelar Esc · Imprimir F5 ·
  Salir Esc` sobre las tres columnas *LECTURA DE PESO · DATOS DEL PESAJE ·
  RESUMEN*. `F3` salió de la barra y vive en el botón **Capturar peso** de
  *LECTURA DE PESO*; el chip *Imprimir* duplicado del `AppBar` se eliminó.
  El botón **Buscar** quedó alineado al inicio de la barra y abre el panel de
  búsqueda rápida de pesos (ver más abajo).
- **Resumen de pesos y tolerancia** en *LECTURA DE PESO*, bajo la tabla de
  lectura (según `docs/DOCUMENTACION VIEJA/MODEL.md`): fechas de entrada/salida,
  peso camión, peso remolque, peso total, **PNT = PTE − PTS**, **PND**,
  **PDF = PNT − PND**, **PDV = PDF / PND (%)**, la tolerancia del producto
  seleccionado y el **Estado** (*DENTRO* / *SOBRE* / *BAJO*) con el rango
  aceptado `PND ± tol.`. Sin PND o tolerancia muestra `-` en vez de
  `#¡DIV/0!` / `#¡VALOR!`.
- **Búsqueda rápida de pesos** (botón **Buscar** de la barra): panel con filtro
  *Todos / Pendientes / Cerrados* y búsqueda por placa, boleto, conductor,
  producto, transporte, tercero, documento o guía. *Traer al formulario* carga
  el pesaje como **copia editable** (aviso amarillo): al guardar se registra un
  **nuevo** pesaje con la fecha/hora actual y el original **no** se modifica; el
  número de boleto no se arrastra.
- **Protección de datos sin guardar**: la estación **arranca maximizada**; al
  presionar `Esc` en el formulario o la **X** de la ventana con información
  capturada y sin guardar se pide confirmación antes de cerrar/limpiar (nuevas
  claves `weighing_unsaved_*` en es/en/pt).

### Sin cambios en backend

`weighings.medida/densidad/litros/unidades`, `peso_entrada_remolque`,
`peso_salida_remolque` y `productos.peso_unidad` ya existían (migraciones
`019`/`020`); no hizo falta migración ni endpoint nuevo.

---

## [v1.3.0] — 2026-09-30

> La barra lateral solo exponía 16 de los módulos que describe `docs/NAV.md`,
> faltaban las hojas de operación (pesajes), ajustes de inventario, auditoría,
> diagnóstico, licencia, conexiones y ayuda; además las teclas `F1`, `F5`, `F6`
> y `F12` de `docs/INPUTS_MAP.md` no hacían nada y la paleta no resolvía las
> búsquedas por boleto, placa o conductor.

### Agregado
- Entradas nuevas del menú: **Pesaje Automático** (`F1`), **Pesaje Manual**
  (`F2`), **Ajustes de Inventario** (`Ctrl+A`), **Auditoría del Sistema** y la
  sección **Ayuda y Soporte**; el mismo árbol alimenta el menú lateral de
  escritorio y la hoja de navegación móvil.
- **Diagnóstico del Sistema**, **Administración de Licencia** y **Conexiones**
  quedan fuera del sidebar (para no saturarlo) y se alcanzan desde la paleta
  `Ctrl + K` o con `go:diagnostico`, `go:licencia`, `go:conexiones`.
- Hojas-acción en `MenuNode` (`accion`): no ocupan índice de página y se
  filtran por `rolesPermitidos`, sin tocar la matriz de
  `seguridad` (siguen siendo 18 módulos).
- Chips de atajo a la derecha de cada entrada del menú y en la hoja móvil.
- Búsqueda dirigida en la paleta (`Ctrl+K`): `t:#123` (boleto), `p:A12BC3`
  (placa) y `c:V12345678` (conductor) llevan el texto al buscador de destino.
- `FocusSearchBus`: el atajo `F6` enfoca el buscador de la pantalla activa.
- Comandos nuevos en la paleta: diagnóstico, licencia, conexiones, ayuda,
  camiones, conductores, transporte y documentos; se corrigieron tres entradas
  que apuntaban a grupos sin página (`go:flota`, `go:inventario_base`,
  `go:empresa`).

### Cambiado
- `home_shell`: las teclas de operación (`F1`, `F5`, `F6`, `F12`) solo responden
  cuando el shell es la ruta visible, de modo que **no roban** `F2`–`F6` al
  formulario de pesaje, que conserva sus atajos propios.
- `F5` refresca el módulo visible según su origen (catálogos vía
  `CatalogCrudCubit`, pesajes vía `WeighingBloc`, resto reconstruyendo la vista).
- El buscador de entradas/salidas filtra por **placa o boleto**.
- Módulo `reportes` renombrado a **Reportes Generales** en la matriz por defecto
  y en el backend (misma clave, sin migración).

### Corregido
- `filtrarMenu` respeta `rolesPermitidos` en las hojas-acción: los módulos
  restringidos (diagnóstico, licencia, conexiones, auditoría) ya no son visibles
  para roles sin permiso.
- La etiqueta «Inventario (Stock Físico)» del menú lateral era ambigua con
  «Ajustes de Inventario»; ahora cada uno tiene nombre propio.
- Texto nuevo en español, inglés y portugués (paridad de 547 claves).

---

## [v1.2.9] — 2026-09-30

> En Configuración, el acceso "Integridad del Sistema" abría el asistente de
> instalación (revisión de servicio de PostgreSQL, drivers, puertos y
> permisos del sistema operativo), que es lo contrario de lo que un operador
> de una estación ya instalada necesita: saber si la API, la base de datos, la
> licencia y la sincronización están bien, sin salir de la app.

- Nueva pantalla `SystemDiagnosticsScreen` con cinco tarjetas de **solo
  lectura**: API local, base de datos, licencia, sincronización y versión.
- Resumen superior (todo en orden / avisos / problemas), botón de refresco y
  *pull to refresh*; los cinco chequeos se resuelven en paralelo.
- El asistente `EnvironmentCheckScreen` queda reservado para el flujo de
  instalación; ya no se abre desde Configuración.
- `ApiClient.syncStatus()` nuevo (`GET /api/v1/sync/status`) para mostrar
  pendientes y fecha de la última sincronización.
- Textos nuevos en español, inglés y portugués (paridad de 541 claves).

---

## [v1.2.8] — 2026-09-29

> En los tickets de boleto, el reporte AVANZADO salía casi igual al BÁSICO y no
> reflejaba la información del formulario, mientras que los pesos escritos a mano
> (que la aplicación ya distinguía en la captura) no se marcaban en ningún lugar.
> Ahora el AVANZADO imprime todos los campos capturados (guía SUNAGRO, medida,
> flete, costo flete, unidades, densidad, resultado, color del camión y operador)
> y el BÁSICO advierte con un aviso destacado cuando el peso fue manual, con el
> operador que lo registró.

### Agregado
- **Columna `es_peso_manual`** en `boletos_pesaje` (migración `020_es_peso_manual.sql`): persiste si el peso fue escrito manualmente (antes solo existía en tiempo de captura y se perdía). Queda en `balansoft-ws-local.sql`.
- **Persistencia del formulario en `create`/`close`** (`WeighingCreate` extendido): `guia_sunagro`, `medida`, `peso_neto_declarado`, `densidad`, `litros` y `unidades` ya no se descartan al registrar el boleto.
- **Reporte AVANZADO completo** en `ticket_service.py` (PDF hoja + térmico + TXT): muestra todos los campos del formulario vía el helper `_pares_avanzado`, incluida la fila de color de camión (resuelto desde `camiones.color` en `_enriquecer_pesaje_ticket`).
- **Bloque "DATOS DEL CATÁLOGO Y CONTROL" en el AVANZADO** (`_pares_catalogo`): refleja las entidades maestro del pesaje (empresa RIF, tercero código/RIF, conductor cédula/teléfono/licencia, transporte código/RIF, remolque tipo/tara, categoría, producto código/unidad/manejo de kardex, almacén código/capacidad/stock, balanza código/capacidad/división) y los registros de control derivados (movimiento de kardex `INGRESO`/`DESPACHO` con su valor, y estado de sincronización). Solo imprime filas con dato.
- **Enriquecimiento extendido**: `_enriquecer_pesaje_ticket` ahora resuelve los catálogos completos (no solo nombres) y consulta el kardex vinculado al boleto, de modo que el ticket nunca imprime UUIDs y el AVANZADO refleja todo lo que registró o creó el ciclo de pesaje.
- **Aviso de peso manual en el BÁSICO**: marcador "PESO MANUAL" (negrita roja en PDF) + operador registrador.
- **Campo `es_peso_manual`** en la respuesta de la API (`WeighingOut`) para que el flujo conozca el modo de captura.
- **Pruebas**: 6 unitarias de contenido (avanzado/total, básico mínimo, aviso manual, legibilidad del térmico/compacto con el bloque completo) y 2 de integración de persistencia (create y close guardan formulario + peso manual).
- **Selector persistente "Tipo de Ticket" (Básico/Avanzado)** en `Diseño de Ticket` (`ticket_design_screen.dart`): guarda la elección en el `PrinterPreset` de `LocalStorage`, de modo que todos los botones de imprimir/reimprimir respetan el tipo configurado (antes solo se podía elegir dentro del diálogo de vista previa y se perdía al salir).

### Corregido
- **La app exportaba "básico" aunque el preset fuera "Avanzado"**: los botones de imprimir/reimprimir del formulario y del detalle del pesaje (`_reimprimirTicket` en `weighing_form_screen.dart` y `weighing_detail_screen.dart`) llamaban a la API sin enviar `tipo_ticket`, así que siempre generaban el BÁSICO. Ahora envían `tipoTicket: preset.tipoTicket` (PDF y TXT).
- **El PDF AVANZADO se recortaba en silencio** cuando `boletosPorHoja` era 2–4: el contenido no cabía en el frame fijo y `Frame.addFromList` descartaba el excedente (imprimía un "básico" cortado). Ahora `_build_pdf` calcula cuántos boletos caben enteros por página a una escala legible y las copias restantes fluyen a páginas siguientes; nada se pierde (verificado: 3 y 4 por hoja imprimen la guía SUNAGRO, los catálogos, el estado de sincronización y las firmas en todas las copias, repartidos en más páginas).
- **`_caben` mide contra la altura útil del Frame** (alto − top/bottom padding), para que la última fila (firmas) no se recorte en casos límite.

### Cambiado
- **El BÁSICO ya no imprime los campos de firma** (operador y conductor), ni en el PDF de hoja, ni en el térmico, ni en el TXT: eran los que empujaban la hoja a 2 páginas al imprimir 3 boletos por hoja. El **AVANZADO los mantiene**. La vista previa de la app (`ticket_preview_dialog.dart`) refleja el mismo criterio. Con esta medida, tres boletos BÁSICOS caben en una sola hoja (verificado: 1 página, sin truncar); si además llevan el logo de la empresa y todos los datos del formulario, tres boletos completos ya no caben a escala legible y el excedente pasa a la página siguiente en lugar de recortarse.

### Nota
- Los boletos ya existentes quedan con `es_peso_manual = FALSE` (default); el valor solo se llena en capturas nuevas.
- En la BD dev se marcó el boleto `BOL-20260004` con `es_peso_manual`, guía/medida/costo de flete de ejemplo para validar el render del ticket.

---

## [v1.2.7] — 2026-09-28

> Un `reset_total.sh` para pruebas de instalación borraba las bases locales de
> PostgreSQL sin dejar copia (solo respaldaba el estado de la app y el runtime del
> WServer), y la estación SERVIDOR re-activada quedaba sin camiones/boletos
> catalogados. Ahora el reset respalda las BD antes de eliminarlas y existe un
> seed para reponer la operación demo.

### Corregido
- **Pérdida silenciosa de datos**: `scripts/reset_total.sh` hacía
  `DROP DATABASE` de `balansoft_ws`, `balansoft_ws_local` y `balansoft_ws_server`
  con `pg_terminate_backend`, sin respaldo previo. Un reset dejaba la empresa
  re-activada pero con catálogos, camiones y boletos vacíos.

### Agregado
- **Respaldo previo obligatorio en `reset_total.sh`**: antes de cada DROP se
  ejecuta `pg_dump -Fc` de cada base existente hacia `backups/<ts>/db/*.pgdump`.
  Si `pg_dump` no está disponible, o el respaldo de una base falla, el script
  **aborta y no borra nada**.
- **`backend/scripts/seed_reset_demo.sql`**: repone la operación demo de la
  estación SERVIDOR bajo la empresa local actual: categorías/productos (Cemento,
  Harina en Sacos, Arroz), transportes, conductores, almacenes, balanza, tercero,
  remolque, los camiones RAP44W/A99ZZ0/A31CX8 con su transporte asignado, la
  serie `BOL-2026` (siguiente 0004) y los boletos `BOL-2026-0001` (CERRADO),
  `BOL-2026-0002` (CERRADO) y `BOL-2026-0003` (PENDIENTE). Idempotente de facto:
  usa los mismos UUID y `ON ERROR STOP`.

---

## [v1.2.6] — 2026-09-28

> Los datos relacionados al camión (transporte, conductor, producto, almacén,
> balanza, tercero) se muestran con **nombre legible** en el detalle y el ticket
> del pesaje —nunca más como UUID—, y si la subida de fotos falla, el usuario es
> avisado en lugar de perderlas en silencio.

### Corregido
- **No se imprime más el UUID en el boleto de pesaje**: el detalle
  (`weighing_detail_screen.dart`) y la vista de impresión del ticket
  (`ticket_preview_dialog.dart`) mostraban `ID: ff000000…` o el UUID crudo de
  transporte, conductor, producto, almacén, balanza y tercero cuando el nombre no
  estaba resuelto. Ahora, si no hay nombre, se muestra `—`/`N/A`; jamás el id.
- **`GET /api/v1/weighing/pendientes` no resolvía nombres**: era la única ruta de
  pesajes que serializaba sin enriquecer (`*_nombre` siempre null), así que un
  boleto pendiente imprimía el UUID. Ahora enriquece igual que `/list` y el
  detalle (`_enriquecer_pesaje_ticket`).

### Agregado
- **Pesaje auto-completa el Transporte desde el camión**: al seleccionar un camión
  que tiene transporte asignado (`transporte_id`), el formulario de pesaje precarga
  la razón social del transporte correspondiente.
- **Aviso de fotos no subidas**: la subida de fotos del pesaje abandonaba en
  silencio (`catch` vacío) y el boleto quedaba sin fotos sin explicación. Ahora el
  formulario informa cuántas fotos no pudieron subirse.

---

## [v1.2.5] — 2026-09-28

> Compatibilidad total con Android (teléfono). La app dejó de funcionar solo en
> escritorio con teclado: ahora arranca y navega en móvil con una barra inferior
> que expone todas las acciones según el rol, sin sidebar.

### Agregado
- **`MobileNavSheet`** (`mobile_nav_sheet.dart`): menú móvil de lista agrupada que
  reemplaza al sidebar en Android. Muestra **todos** los módulos accesibles para el
  rol del usuario (misma matriz `AppSidebar.menuTree` + `AccesosRepository`), con
  acciones inferiores de Configuración (si el rol puede) y Cerrar sesión.
- **Bottom bar dinámico por rol** (`_BottomNavBar`): si el rol accede a ≤4 módulos
  los expone **todos** directamente; si accede a más, muestra los 4 principales +
  "Más" (abre el menú móvil). El dashboard ya no abre un sidebar al pulsar "Más".
- **`AppSidebar` público reutilizable**: `AppSidebar.menuTree`, `filtrarMenu` y
  `traducir` se exponen como estáticos para compartir el árbol y su filtrado por
  rol entre desktop y móvil.

### Corregido
- **Android arrancaba pero no conectaba**: `AndroidManifest.xml` no declaraba
  `android.permission.INTERNET` ni permitía tráfico claro
  (`usesCleartextTraffic`), por lo que todo `http://...` fallaba en el teléfono al
  cumplir Android 9+ el bloqueo de cleartext. Ahora existe el permiso y el tráfico
  HTTP plano está habilitado.
- **Android no compilaba con las dependencias actuales**: `connectivity_plus 4.x`
  compila contra `android-33` mientras sus dependencias (fragment 1.7.1, window,
  activity, core) exigen `compileSdk ≥ 34`. Se fuerza `compileSdk 36` en todos los
  submódulos desde `android/build.gradle.kts` (vía `afterEvaluate` registrado al
  inicio del script, antes de `evaluationDependsOn(":app")`).

---

## [v1.2.4] — 2026-09-28

> Tras hacer un POST, retroceder o cambiar de módulo, la estación podía quedar
> "cargando en bucle" mostrando sincronizando sin terminar nunca (solo se resolvía
> yendo a Inicio y regresando). Causa: `WeighingBloc` es global y tras la
> sincronización quedaba en `WeighingSyncComplete` sin que ninguna pantalla
> pidiera el listado de nuevo; el Dashboard y un listado recién abierto solo
> renderizaban con `WeighingListLoaded`.

### Corregido
- **`WeighingBloc` se auto-recupera tras sincronizar**: al terminar
  `SyncWeighingsEvent` encola automáticamente un `ListWeighingsEvent()`, por lo
  que el estado global siempre vuelve a `WeighingListLoaded` (datos frescos) y ni
  el Dashboard ni los módulos Entradas/Salidas quedan en el spinner infinito.
- **Dashboard** (`dashboard_screen.dart`): guarda la última lista cargada y sigue
  renderizándola durante estados transitorios (sync/detalle/crear); recuperación
  explícita tras `WeighingSyncComplete` sin datos y vista de error con reintento
  en lugar del spinner eterno.
- **`WeighingListScreen`**: si tiene `_items == null` y el estado global es un
  estado terminal sin listado (p. ej. `SyncComplete`), lanza una recarga
  automática (con guarda `_solicitandoCarga` anti-bucle) para no quedarse
  cargando indefinidamente.
- **`WeighingDetailScreen`**: cachea el último detalle renderizado, así un
  `Loading`/`Sync`/`ListLoaded` ajeno deja de blanquear la vista con un spinner
  infinito.
- **`WeighingFormScreen`**: el overlay de "Guardando pesaje…" se descarta ante
  estados globales ajenos a la operación del formulario (listado, sync, detalle),
  evitando quedarse en bucle mostrando el spinner.
- **Impresión desde Entradas/Salidas**: al quedar desbloqueada la carga del
  módulo (causa del reporte previo), la impresión del boleto desde el listado
  vuelve a ser accesible; el flujo ya enviaba el `PrinterPreset` al backend.

### Añadido
- Test de bloc actualizado: `sync emite SyncComplete y recarga automáticamente el
  listado` (verifica la secuencia `Syncing → SyncComplete → Loading →
  ListLoaded`) en `frontend/test/unit/weighing_bloc_test.dart`.
- Verificado: `flutter analyze` sin issues, `flutter test` **120/120** ✓.

---

## [v1.2.3] — 2026-09-28

> Encabezado del boleto en layout **horizontal (logo izquierda | datos derecha)**,
> el export respeta el diseño configurado (`PrinterPreset`) y desaparece el
> "refresh infinito" al volver al listado de pesajes.

### Corregido
- **Encabezado del ticket**: el logo ahora va en la columna izquierda y a la
  derecha dos líneas (nombre + RIF arriba; dirección + contactos abajo), igual en
  PDF (`ticket_service.py`) y TXT (marco `━|━` con `[LOGO]`); en térmico solo
  datos alineados a la izquierda. Antes todo quedaba centrado en vertical.
- **La divisoria `|` del encabezado se dibuja siempre** (también sin logo):
  `_build_boleto_simple` usa la tabla con la columna izquierda de logo vacía en
  lugar del bloque de texto suelto, así el PDF y la previsualización Flutter
  (`ticket_preview_dialog.dart`, ahora `Row` horizontal con `Container` gris
  vertical) coinciden en cualquier configuración.
- **Datos de contacto provienen de `empresas`**: verificado contra
  `balansoft_ws_local` (nombre, RIF, dirección, teléfono, email y `logo_url` en
  `media/uploads/`) — los "textos fantasma" del diagnóstico eran artefactos de
  extracción de texto de `pdfminer` (p. ej. un `;` tras "S&S" o la dirección
  partida), no datos de la BD ni texto hardcodeado en el backend.
- **Export no respetaba el diseño**: `weighing_list_screen`, `weighing_detail_screen`
  y `weighing_form_screen` no enviaban el `PrinterPreset`; ahora leen
  `LocalStorage.getPrinterPreset()` y pasan `boletosPorHoja`, `tamanoPapel`,
  `orientacion`, `mostrarEncabezado` y `mostrarDetalles` al backend (antes
  siempre salía 1 boleto/hoja Letter portrait).
- **Pesajes congelado en "refresh infinito"**: `WeighingListScreen` se quedaba en
  spinner indefinido porque `WeighingBloc` es global y cualquier estado que no
  fuera `ListLoaded` (detalle, crear, sync) rompía la lista; ahora conserva la
  última lista cargada, recarga al volver del detalle/formulario
  (`RouteAware.didPopNext`) y muestra un estado de error con reintento en lugar de
  un spinner eterno.

### Añadido
- Test visual TXT verificando el ancho de 100 columnas del nuevo encabezado
  (los 43 tests de ticket del backend siguen en verde).

---

## [v1.2.2] — 2026-09-28

> El "código interno / personalizado" de los catálogos queda **único por empresa**
> a nivel de BD (índice único parcial `(id_empresa, codigo) WHERE codigo IS NOT NULL`),
> con mensaje claro de conflicto en la API. Verificado: backend `268/268` ✓, `ruff` ✓.

### Corregido
- `categorias`, `productos`, `terceros`, `transportes`, `almacenes` y `balanzas`
  ahora exigen un `codigo` (interno/personalizado) **único dentro de la empresa**;
  los registros sin código sí pueden repetirse (índice parcial). Antes la BD
  permitía duplicados y la validación dependía solo de la UI.
- `CatalogService` distingue la violación de unicidad y responde `409` con el
  código en conflicto: `Ya existe un <entidad> con el código 'X'` al **crear** y
  al **actualizar** (antes, actualizar a un código repetido terminaba en 500).

### Añadido
- Migración **018** `_codigo_unico_catalogos.sql`: sanea duplicados existentes
  (conserva el más antiguo por `created_at`, resto queda sin código) y crea los
  índices únicos parciales. Idempotente (verificada dos veces).
- Índices equivalentes en el esquema canónico `balansoft-ws-local.sql` y como
  `__table_args__` en los modelos ORM (la `balansoft_ws_test` y estaciones nuevas
  ya nacen con la restricción).

### Verificado
- 5 tests nuevos en `test_categorias_seguridad.py`: duplicado al crear y al
  actualizar (409 + fila intacta), mismo código en otra empresa permitido,
  `codigo NULL` repetido permitido, y la regla aplicada a otros catálogos.
- Suite completa backend `268/268`; `ruff` limpio; `mypy` sin errores nuevos.

---

## [v1.2.1] — 2026-09-28

> Boleto/comprobante de pesaje con los datos de contacto y logo de la estación
> emisora (teléfono, dirección, email y logo), tanto en el PDF como en el TXT y
> en la vista previa de Flutter. Verificado: backend `263/263` ✓, `ruff` ✓,
> frontend `120/120` ✓, `flutter analyze` ✓.

### Añadido
- **Boleto (backend)** (`app/services/ticket_service.py`)
  - Encabezado con **logo** de la estación: se resuelve la ruta `/media/...` contra
    `settings.media_dir`, se incrusta centrado (máx. 12 mm alto / 45 mm ancho) y se
    omite si el archivo falta o está corrupto (no rompe el PDF).
  - **Línea de contacto** `Tel.: X · Dirección: Y · email` bajo el RIF (gris, cuerpo
    menor); sin email en el ticket térmico. TXT la envuelve a `ANCHO_TXT`.
  - Los datos nacen de `empresas`: `telefono`, `direccion`, `email` y `logo_url`.
- **Boleto (Flutter)**
  - `TicketPreviewDialog` (vista previa) carga el perfil real de la estación
    (`getEmpresaPerfil`) y pinta logo + nombre + RIF + contacto igual que el PDF;
    sustituye los datos demo hardcodeados. El térmico omite el logo.
  - Nuevo parámetro `empresaPerfilFuture` para inyectar el perfil sin tocar GetIt
    en tests.
- **i18n**: claves `ticket_company_phone` / `ticket_company_address` (es/en/pt).

### Verificado
- Backend: 43 tests de `test_ticket_service.py` (encabezado, logo, TXT, una página
  en todas las configuraciones) + suite completa `263/263`.
- Frontend: 120 tests (3 nuevos del encabezado del preview); `flutter analyze` limpio.

---

## [v1.2.0] — 2026-09-28

> Onboarding de instalación en dos modos (Servidor / Trabajador) y corrección del
> modelo de cuenta/dispositivos. Verificado: backend `248/248` ✓, `ruff` ✓,
> frontend `117/117` ✓, `flutter analyze` ✓, `flutter build linux --release` ✓.

### Añadido

- **Instalación en dos modos**
  - Flujo `SERVIDOR`: preferencias → modo → entorno → BD local → activación contra
    el central → empresa **precargada** (RIF y razón social de solo lectura) →
    dashboard con la sesión ya abierta, sin volver a pedir credenciales.
  - Flujo `TRABAJADOR` (cliente delgado): preferencias → modo → host/puerto +
    `/health` → login contra la API del servidor titular. No crea BD ni WServer.
  - `POST /api/v1/auth/login-central` acepta `modo_solicitado`; un equipo que no
    es titular y pide `SERVIDOR` recibe `403` indicando cuál equipo **sí** lo es.
- **Panel del proveedor**
  - `POST /api/v1/panel/cuentas/{id_cuenta}/titular` → reata la licencia a un
    equipo registrado y recalcula los roles (`SERVIDOR_LOCAL` / `LOCAL`), para
    corregir cuentas mal configuradas sin editar la base a mano.
  - El detalle de cuenta devuelve `dispositivos[]` y `hardware_titular`; la UI
    lista los equipos con el botón **"Designar titular"**.
- `i18n` es/en/pt para los textos de modo, activación, empresa precargada y
  trabajador (`docs/I18N_Y_ONBOARDING.md` v1.2, REQ-NF-ONB-010..015).

### Corregido

- **Titular de la licencia**: el rol del dispositivo se decidía por el orden de
  inserción de la fila y solo se asignaba al crearla, así que una cuenta podía
  quedar con el equipo equivocado como `SERVIDOR_LOCAL` y la instalación en
  modo Servidor se bloqueaba con `403`. Ahora la fuente de verdad es
  `licencias.hardware_id` (la misma que ata el `ADMIN`) y el rol se recalcula en
  cada login: no puede haber dos `SERVIDOR_LOCAL` y las cuentas mal aprobadas se
  autocorrigen (`docs/MANEJO_DB.md` §13).
- **Licencia virgen (`AVAILABLE`)**: el estado `AVAILABLE` del LM se guardaba tal
  cual en `licencias.licencia_status` y el central lo leía como licencia
  rechazada (`_licencia_activa` exigía `ACTIVA`), así que una licencia sin
  usar bloqueaba la instalación en modo Servidor y el panel mostraba
  "rechazada o inactiva (estatus AVAILABLE)". Ahora `AVAILABLE` = **virgen**: la
  cuenta queda `ACTIVA` y el primer equipo que valida se amarra a la licencia
  como titular único (`SERVIDOR_LOCAL`), que es lo que el panel muestra como
  "Disponible".
- El mensaje de error de activación ya no oculta el `detail` del central ni
  confunde "API local caída" con "el central rechazó la cuenta" (502 con causa).
- `scripts/reset_total.sh`: el borrado del keyring ya no falla por entradas
  fantasma de GNOME Keyring, y una compilación fallida no borra el bundle previo.

### Seguridad

- Rotar la contraseña de cualquier cuenta compartida por chat: las credenciales
  de los diagnósticos quedan expuestas en el historial.

---

## [v1.1.0] — 2026-09-11

> Iteración de cierre según `ACTUAR.md` (B1–B6 y M1–M4). Frontend verificado:
> `flutter test` (52/52) ✓, `flutter analyze` ✓ y `flutter build linux --release` ✓.
> Pendiente de entorno con PostgreSQL: `uv run pytest -q` (backend) y smoke test.

### Añadido

- **Seguridad**
  - Tokens JWT migrados a `flutter_secure_storage` (B1, T1.1) con migración
    one-shot desde `SharedPreferences`.
  - Endpoint `forgot-password` + `reset-password` en backend y pantallas
    `ForgotPasswordScreen` / `ResetPasswordScreen` (B3, T1.3).
- **Cumplimiento**
  - Tabla `auditoria` con escrituras reales en pesajes y catálogos
    (create/update/delete) — `audit_service.py` (B5, T2.2).
  - Consumo de `max_sync_retries` y `SYNC_INTERVAL_MINUTES`: columna `fallido`
    e `intentos_sync`, `pushWeighing`, reintentos y sección de pesajes fallidos
    en el dashboard (B6, T2.3).
  - Modo kiosk fullscreen (B4, T2.1).
- **Cierre (Fase 3)**
  - Health check `GET /api/v1/health` + badge de estado del backend en el
    dashboard con re-check cada 30 s (M1, T3.1).
  - UI de exportación a Excel en la pantalla de reportes (M3, T3.3).
  - UI Kardex completa con filtros, movimientos con saldo acumulado y
    exportación PDF/Excel (M4, T3.4): backend `kardex/detalle` +
    `reports/export/kardex/{excel,pdf}`.

### Cambiado

- `signature_verifier.dart` eliminado (B2, T1.2).
- `database_helper` a versión 4 (columna `fallido`), `weighing_repository`
  respeta `maxSyncRetries` y marca pesajes fallidos.
- `SyncBloc` con timer periódico configurable y verificación de salud del
  backend; `ApiClient` admite inyección de `Dio` y nuevos métodos de kardex.
- `DOCUMENTACION-BALANSOFT-WS.md` movida a `docs/legacy/` con header
  "NO AUTORITATIVO" (M2, T3.2).

### Corregido

- Comparación de conectividad en `WeighingRepository._isConnected` (operaba
  sobre `List<ConnectivityResult>` con `!=`).

### Pendientes futuros

- B7 · HAL de balanza (peso por API; integración futura vía estación).
- B8 · Estabilidad de pesada 3 s y conversión KG/LBS activas.

---

## [v1.0.0] — 2026-09-08

### Añadido

- Backend FastAPI multi-empresa: auth JWT (BCrypt), catálogos (flota/inventario/
  directorio), pesaje con reglas MODEL (estados, cálculos, kardex 10/60),
  sincronización offline, reportes, exportación a Excel, tickets PDF,
  auditoría en `logs_sistema` e integración de licencias Ed25519.
- Frontend Flutter (BLoC, offline-first con `sqflite`): login/registro,
  dashboard, pesaje, catálogos, reportes, tema persistente.
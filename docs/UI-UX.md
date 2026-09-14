# UI/UX Guide - BALANSOFT

| Atributo       | Valor                                                       |
|----------------|-------------------------------------------------------------|
| **Documento**  | UI-UX Guide                                                 |
| **Versión**    | 2.0                                                         |
| **Fecha**      | 2026-09-08                                                  |
| **Estado**     | Vigente                                                     |
| **Autor**      | Equipo BALANSOFT                                            |
| **Norma**      | ISO/IEC/IEEE 42010 + 29148                                  |
| **Stack UI**   | **Flutter (Dart)** — Material 3 sobre **Modern Flat UI** (paleta plana) + Tema claro/oscuro persistente (SharedPreferences) |
| **Contexto**   | Sistema de pesaje industrial, operación continua en patio, multi-rol y modo kiosk (cliente-servidor contra FastAPI). |

### Cambios desde la versión anterior

- v2.0 (2026-09-08): re-alineación al stack de implementación **Flutter/Dart** (reemplaza WinForms/.NET): screens Flutter en lugar de `Form`s WinForms, BLoC en lugar de DI in-process, Material 3 plano en lugar de MetroSet UI. REGLAS UX intactas.
- v1.3 (2026-08-20): adopción de **Modern Flat UI / MetroSet UI** como referencia visual. Las directrices de tokens, colores y tema se aplican sobre los controles `MetroSet_*` y la paleta plana de Metro.
- v1.2 (2026-08-20): re-migración del stack a .NET Framework 4.8 + WinForms (antes Vaadin).
- v1.1 (2026-08-20): redacción inicial en español sobre WinForms.

---

## 1. Objetivo del Diseño

Definir criterios UI/UX consistentes para todas las vistas del sistema, priorizando:

- Rapidez operativa en flujos de pesaje.
- Claridad visual en ambientes industriales.
- Prevención de errores de captura.
- Accesibilidad y contraste adecuado (WCAG AA).
- Consistencia entre módulos CRUD, gestión y consulta.

---

## 2. Principios UX

1. **Operación primero:** Las acciones primarias siempre visibles y con confirmación clara.
2. **Contexto inmediato:** Cada pantalla debe mostrar módulo, tenant activo y estado operativo.
3. **Error prevenible:** Validar antes de guardar, bloquear estados inválidos, mensajes concretos.
4. **Mínimos clics:** Flujo completo de entrada/salida en menos de 6 interacciones principales.
5. **Legibilidad en patio:** Tipografía, tamaño y contraste optimizados para distancia media.
6. **Consistencia visual:** Misma estructura de CRUD, grillas y formularios en todo catálogo.
7. **Modo oscuro útil:** Dark mode pensado para turnos nocturnos y reducción de fatiga ocular.

---

## 3. Arquitectura de Navegación

### 3.1 Rutas actuales (Flutter ↔ screens)

La navegación en Flutter es por rutas (`Navigator`/`go_router`). La tabla muestra la ruta conceptual y su rol.

| Módulo                 | Screen                    | Ruta            | Rol                         |
|------------------------|---------------------------|-----------------|----------------------------|
| Login                  | `AuthScreen`              | `/login`        | Público                     |
| Pesaje principal       | `WeighingFormScreen`      | `/`             | ADMIN, SUPERVISOR, OPERADOR |
| Dashboard              | `DashboardScreen`         | `/dashboard`    | ADMIN, SUPERVISOR, OPERADOR |
| Catálogos           | `CatalogsScreen`          | `/catalogos`    | ADMIN, SUPERVISOR           |
| Reportes               | `ReportsScreen`           | `/reportes`     | ADMIN, SUPERVISOR           |
| Configuración          | `SettingsScreen`          | `/configuracion`| ADMIN                       |
| Kiosk                  | `KioskScreen` (fullscreen)| `/kiosk`        | OPERADOR                    |

### 3.2 Estructura de menú (HomeShell/drawer)

- Dashboard
- Pesaje
- Catálogos
- Reportes
- Configuración

Regla UI: destacar sección activa, mantener accesos de rol ocultos cuando no aplican, y no mostrar opciones no autorizadas. En Flutter esto se traduce en filtrar los items del drawer según el rol del usuario autenticado (BLoC).

---

## 4. Patrones de Pantalla

### 4.1 Patrón CRUD estándar

Todas las vistas CRUD deben incluir:

1. Encabezado con título + botón primario `Nuevo`.
2. `DataTable`/lista con columnas claves + columna de acciones (`Editar`, `Eliminar`).
3. Formulario inferior (o modal `showDialog`) con validaciones en línea (`Form`/`TextFormField`).
4. Confirmación explícita en eliminación (diálogo `AlertDialog` con `Acción`/`Cancelar`).
5. Mensajes de resultado propios (SnackBar/NotificationBar): estado éxito/error.

### 4.2 Patrón de Gestión Operacional

Aplicable a `WeighingFormScreen` y Kiosk:

1. Estado de peso visible en formato grande (`Text` con `ThemeData.textTheme` ampliado).
2. Acciones primarias: leer balanza, entrada, salida.
3. Flujo bloqueado cuando faltan datos críticos (botón `onPressed: null`).
4. Indicadores de hardware y captura fotográfica en el mismo contexto.

### 4.3 Patrón de Consulta

Aplicable a reportes y consultas de boletos:

1. Filtros por fecha y entidad en cabecera.
2. Lista/`DataTable` con paginación (`skip/limit` desde la API).
3. Resumen superior de KPIs (totales, balance, conteos).
4. Exportación visible pero secundaria.

---

## 5. Diseño Visual y Tokens

### 5.1 Tipografía y jerarquía

- Título de pantalla: claro y único por vista.
- Etiquetas de campos: texto directo, sin ambigüedades.
- Evitar bloques extensos; usar grupos visuales con spacing consistente.

### 5.2 Espaciado

- Márgenes consistentes por vista (`Padding`/`Margin` de widgets).
- Formularios en `Card` o `Container` con borde suave (`BorderRadius`) y separación vertical clara.

### 5.3 Colores semánticos

- Primario: acciones de guardar/continuar.
- Éxito: confirmaciones de operación.
- Error: validaciones, fallos de hardware o negocio.
- Advertencia: acciones irreversibles (anular/eliminar).

---

## 6. Tema Claro/Oscuro (Material 3 sobre Modern Flat UI)

### 6.1 Reglas de tema

1. Temas soportados: `light` y `dark`. La paleta es la de **Material 3** (`ColorScheme.fromSeed`), con superficies planas y esquinas consistentes.
2. Preferencia persistida por dispositivo (`ThemeController` con `SharedPreferences`, clave `balansoft.tema`).
3. Cambio de tema inmediato sin recargar la pantalla (`ThemeMode` sobre `MaterialApp`).
4. Contraste mínimo WCAG AA en ambos temas.

### 6.2 Recomendación operativa

- `claro` por defecto para administración.
- `oscuro` recomendado para kiosk y turnos nocturnos.

### 6.3 Consideraciones de implementación Flutter

- **Widgets a usar**: `FilledButton`, `OutlinedButton`, `TextFormField`, `Switch`, `DropdownButtonFormField`, `LabeledInput`. Usar siempre los temas globales; no mezclar widgets propios con estilos sueltos que rompan la coherencia plana.
- **No hardcodear** colores en cada widget. Definir tokens planos en `app_theme.dart` (primario/superficie/texto/éxito/error/advertencia) y consumir vía `Theme.of(context)`.
- `app_theme.dart` es el orquestador del tema; el cambio se dispara desde `ThemeController` (ChangeNotifier) y `MaterialApp` lo aplica en caliente.
- Para controles de toque, usar tamaños de fuente grandes (≥ 18 en acciones críticas de kiosk).
- Iconografía plana y monocromática; evitar sombras/skeuomorfismo.

---

## 7. UX de Validaciones y Mensajes

### 7.1 Validación de formularios

- Marcar campos obligatorios con asterisco/aunque no con `ErrorProvider` (usar `validator` de `TextFormField`).
- Mostrar mensaje junto al campo cuando sea posible (`validator`/`autovalidateMode`).
- No permitir guardado con estado inválido (botón deshabilitado o validador bloqueante).

### 7.2 Mensajería

- Éxito: confirmar operación y entidad afectada.
- Error: describir causa accionable (ej. duplicado, campo faltante, sesión sin empresa).
- Evitar mensajes genéricos tipo "falló" sin contexto.

### 7.3 Confirmaciones críticas

Usar `AlertDialog` con acciones `Confirmar`/`Cancelar` para:

- Eliminar registros.
- Anular boletos cerrados.
- Reinicios/acciones de mantenimiento que alteren operación.

---

## 8. Accesibilidad

1. Contraste AA en light/dark.
2. Controles con tamaño clic/tap cómodo para guantes ligeros.
3. Navegación por teclado funcional en formularios y listas (`Tab`, `Enter`, `Esc`).
4. Iconos siempre acompañados de texto cuando la acción sea crítica.
5. Estados no depender solo del color (agregar texto o badge).

---

## 9. UX para Kiosk

### 9.1 Requisitos

- Fullscreen estable (mode kiosk de Flutter: pantalla completa, sin bordes del SO).
- UI simplificada, sin navegación innecesaria.
- Botones grandes para operación rápida.
- Mensajes de error visibles a distancia.

### 9.2 Flujo recomendado

1. Iniciar turno.
2. Seleccionar tipo de pesaje (si aplica).
3. Leer peso/capturar evidencia.
4. Confirmar entrada o salida.
5. Mostrar comprobante y volver a estado de espera.

### 9.3 Failsafe operativo

- Si falla hardware, ofrecer ruta guiada a modo manual.
- Registrar claramente que la operación fue manual.

---

## 10. Checklist UI/UX por Vista

Antes de marcar una vista como DONE:

1. Screen correspondiente y rol correcto.
2. Header claro con acción principal.
3. `DataTable`/lista y formulario consistentes con el patrón.
4. Validaciones funcionales (`validator`).
5. Mensajes de éxito/error claros.
6. Confirmación en acciones destructivas.
7. Comportamiento correcto en light y dark.
8. Responsive/scaling básico funcional.
9. Sin texto placeholder pendiente (`TODO`) visible al usuario.

---

## 11. Criterios de Aceptación UI/UX del Proyecto

1. Navegación por módulos consistente y sin pantallas huérfanas.
2. Flujos críticos de pesaje operables sin ambigüedad.
3. CRUDs con comportamiento uniforme.
4. Tema claro/oscuro persistente por dispositivo.
5. Cumplimiento de contraste y accesibilidad mínimos.
6. Soporte operativo real para modo kiosk.

---

## 12. Roadmap UI/UX

### Sprint II.2

- CRUDs individuales de Product, Vehicle, Client, Warehouse.
- Unificación de comportamiento de formularios y acciones.

### Sprint II.3

- Refinamiento de `WeighingFormScreen` para flujos AUTOMATICO/MANUAL.
- UX de errores de hardware y confirmaciones de negocio.

### Sprint II.4

- `SettingsScreen` con selector de tema por dispositivo.
- Ajustes finales de kiosk para operación continua.

---

**Documento vivo:** actualizar junto con `PRD.md`, `ARCH.md` y `AGENTS.md` cuando cambien forms, roles o patrones de interacción.

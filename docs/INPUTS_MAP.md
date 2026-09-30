Perfecto, entiendo. Quieres un mapeo **más lógico y estándar** (tipo apps de escritorio modernas), no uno tan "custom".

Aquí tienes una **propuesta coherente** y luego los cambios en el código para aplicarla.

---

## Propuesta de mapeo (más lógica y estándar)

### 1. Global (Interfaz y entorno)

| Atajo | Acción | Razón |
|---|---|---|
| `Ctrl + B` | Mostrar / Ocultar **Sidebar** | Estándar VS Code / IDEs |
| `Ctrl + K` | **Paleta de comandos** | Estándar VS Code / Linear |
| `Ctrl + H` | Ir a **Inicio / Dashboard** | Home = H |
| `Ctrl + Shift + T` | Cambiar **Tema** claro/oscuro | Theme = T |
| `F11` | **Pantalla completa** | Estándar universal |
| `F9` | **Maximizar / Restaurar** ventana | Consistente con F10/F11 |
| `Ctrl + Enter` | **Pantalla completa** (alternativa a F11) | Para teclados con fila F en modo medios (FnLock) |
| `Ctrl + Alt + Enter` | **Maximizar / Restaurar** (alternativa a F9) | Ídem |
| **`Ctrl + Q`** | **Salir de la aplicación** | Estándar universal (Q = Quit) |
| `Esc` | **Cancelar / cerrar modal** | Estándar universal |

> ❌ Quitamos `Ctrl + Shift + Q` (raro). Lo reemplazamos por `Ctrl + Q`.

---

### 2. Crear (Nuevo)

| Atajo | Acción | Razón |
|---|---|---|
| **`Ctrl + N`** | **Nuevo Pesaje** (entrada) | N = New, el flujo más usado |
| `Ctrl + Shift + N` | **Nuevo Pesaje Manual** | Variante explícita |
| `Ctrl + Alt + N` | **Nuevo Pesaje Automático** | Otra variante |
| `Ctrl + Shift + V` | **Nuevo Vehículo / Camión** | V = Vehicle |
| `Ctrl + Shift + D` | **Nuevo Conductor** | D = Driver |
| `Ctrl + Shift + T` | **Nuevo Transporte** | T = Transport |

> ⚠️ Ojo con `Ctrl + Shift + T`: choca con el "cambiar tema". **Reasigno el tema** a `Ctrl + Shift + L` (Light) o `Ctrl + Shift + D` (Dark toggle). Ver abajo.

---

### 3. Navegación rápida a módulos

Aquí los números tienen sentido solo para lo más usado, y luego letras mnemónicas:

| Atajo | Módulo |
|---|---|
| `Ctrl + 1` | **Inicio / Dashboard** |
| `Ctrl + 2` | **Entradas** (Ingresos) |
| `Ctrl + 3` | **Salidas** (Despachos) |
| `Ctrl + 4` | **Reportes** |
| `Ctrl + 5` | **Kardex** |
| `Alt + C` | **Clientes / Terceros** (C = Clientes) |
| `Alt + F` | **Flota y Transporte** (F = Flota) |
| `Alt + P` | **Productos** (P = Productos) |
| `Alt + A` | **Almacenes** (A = Almacén) |
| `Alt + U` | **Usuarios** (U = Usuarios) |
| `Alt + D` | **Dispositivos** (D = Dispositivos) |
| `Alt + S` | **Seguridad** (S = Seguridad) |
| `Ctrl + ,` | **Configuración** (estándar apps modernas) |

---

### 4. Acciones operativas

| Atajo | Acción |
|---|---|
| **`F2`** | Pesaje rápido (atajo de operación, ya lo usas) |
| **`F5`** | Imprimir / refrescar el ticket actual |
| `Ctrl + A` | Ajustes de inventario |
| `Ctrl + L` | **Bloquear pantalla / Cerrar sesión** (L = Lock) |

---

### 5. Sobre los comandos de la paleta

Se mantienen como están, **no tocan teclas**. La paleta (`Ctrl+K`) sigue aceptando `go:wm`, `new:ticket`, etc. Eso está bien y no hay que cambiarlo. Lo único que cambia es que **los atajos físicos** ahora son más lógicos.

---

## Cambios en el código (`home_shell.dart`)

Reemplaza el método `_onKey` y los helpers `_destinoPorAlt` / `_aperturaPorAlt` / `_manejarCtrlNumero` por estos:

```dart
bool _onKey(KeyEvent event) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
  final key = event.logicalKey;
  final kb = HardwareKeyboard.instance;
  final ctrl = kb.isControlPressed || kb.isMetaPressed;
  final shift = kb.isShiftPressed;
  final alt = kb.isAltPressed;

  // ── Teclas de función (sin modificadores) ───────────────────────────────
  if (event is KeyDownEvent) {
    if (key == LogicalKeyboardKey.f2) {
      _abrirNuevoPesaje();
      return true;
    }
    if (key == LogicalKeyboardKey.f5) {
      _imprimirActual();
      return true;
    }
    if (key == LogicalKeyboardKey.f9) {
      _alternarMaximizado();
      return true;
    }
    if (key == LogicalKeyboardKey.f10) {
      _toggleSidebar();
      return true;
    }
    if (key == LogicalKeyboardKey.f11) {
      _alternarPantallaCompleta();
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      // Esc: si hay un modal abierto, lo cierra el propio modal. Aquí solo
      // limpiamos el foco de inputs para no interferir.
      return false;
    }
    // Backspace/Delete para volver atrás si no hay input en foco
    if (!ctrl &&
        !alt &&
        (key == LogicalKeyboardKey.backspace ||
            key == LogicalKeyboardKey.delete) &&
        !_hayTextoEnFoco()) {
      _volverAtras();
      return true;
    }
  }

  // ── Ctrl + tecla ────────────────────────────────────────────────────────
  if (ctrl && !alt) {
    // Ctrl+Q → salir
    if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyQ) {
      _salirDelSistema();
      return true;
    }
    // Ctrl+N → nuevo pesaje
    if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyN) {
      _abrirNuevoPesaje();
      return true;
    }
    // Ctrl+Shift+N → nuevo pesaje manual (mismo form por ahora)
    if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyN) {
      _abrirNuevoPesaje();
      return true;
    }
    // Ctrl+Shift+V → nuevo vehículo
    if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyV) {
      _abrirNuevoVehiculo();
      return true;
    }
    // Ctrl+Shift+D → nuevo conductor
    if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyD) {
      _abrirNuevoConductor();
      return true;
    }
    // Ctrl+Shift+T → nuevo transporte (solo si tienes ese flujo; si no, quítalo)
    if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyT) {
      _irA('transportes');
      return true;
    }
    // Ctrl+Shift+L → cambiar tema
    if (event is KeyDownEvent && shift && key == LogicalKeyboardKey.keyL) {
      _alternarTema();
      return true;
    }
    // Ctrl+B → toggle sidebar
    if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyB) {
      _toggleSidebar();
      return true;
    }
    // Ctrl+K → paleta de comandos
    if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyK) {
      _toggleCommandPalette();
      return true;
    }
    // Ctrl+H → inicio
    if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyH) {
      _irA('inicio');
      return true;
    }
    // Ctrl+L → cerrar sesión / bloquear
    if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyL) {
      _cerrarSesion();
      return true;
    }
    // Ctrl+A → ajustes de inventario
    if (event is KeyDownEvent && !shift && key == LogicalKeyboardKey.keyA) {
      _abrirAjustesInventario();
      return true;
    }
    // Ctrl+, → configuración
    if (event is KeyDownEvent && key == LogicalKeyboardKey.comma) {
      _abrirConfiguracion();
      return true;
    }
    // Ctrl+1..5 → navegación rápida
    if (event is KeyDownEvent) {
      final idx = _numeroCtrl(key);
      if (idx != null) {
        _cambiarIndice(idx);
        return true;
      }
    }
  }

  // ── Alt + tecla (navegación mnemónica) ──────────────────────────────────
  if (alt && !ctrl && event is KeyDownEvent) {
    final destino = _destinoPorAlt(key);
    if (destino != null) {
      _irA(destino);
      return true;
    }
  }

  return false;
}

/// Mapea Ctrl+1..5 a índices de página.
///   1 → Inicio (0)
///   2 → Entradas (10)
///   3 → Salidas (11)
///   4 → Reportes (12)
///   5 → Kardex (9)
int? _numeroCtrl(LogicalKeyboardKey key) {
  final d = key.keyLabel;
  if (d.isEmpty || d.length != 1) return null;
  switch (d) {
    case '1':
      return _claveAIndice('inicio');
    case '2':
      return _claveAIndice('entradas');
    case '3':
      return _claveAIndice('salidas');
    case '4':
      return _claveAIndice('reportes');
    case '5':
      return _claveAIndice('kardex');
    default:
      return null;
  }
}

/// Alt + letra → módulo destino (mnemónico).
String? _destinoPorAlt(LogicalKeyboardKey key) {
  switch (key) {
    case LogicalKeyboardKey.keyC:
      return 'terceros';   // Clientes / Proveedores
    case LogicalKeyboardKey.keyF:
      return 'camiones';   // Flota
    case LogicalKeyboardKey.keyP:
      return 'productos';  // Productos
    case LogicalKeyboardKey.keyA:
      return 'almacenes';  // Almacenes
    case LogicalKeyboardKey.keyK:
      return 'kardex';     // Kardex
    case LogicalKeyboardKey.keyU:
      return 'usuarios';   // Usuarios
    case LogicalKeyboardKey.keyD:
      return 'dispositivos'; // Dispositivos
    case LogicalKeyboardKey.keyS:
      return 'seguridad';  // Seguridad
    case LogicalKeyboardKey.keyR:
      return 'reportes';   // Reportes
    default:
      return null;
  }
}
```

**Borra** los métodos viejos `_aperturaPorAlt` y `_manejarCtrlNumero` (ya no se usan).

---

## Actualiza `docs/ATAJOS.md` (o donde tengas la tabla)

Aquí está la tabla reescrita para que quede **coherente y ordenada**:

```markdown
# Atajos de teclado — Balansoft-WS

## 1. Interfaz y entorno

| Atajo | Acción |
|---|---|
| `Ctrl + B` | Mostrar / Ocultar Sidebar |
| `Ctrl + K` | Paleta de comandos / búsqueda rápida |
| `Ctrl + H` | Ir a Inicio / Dashboard |
| `Ctrl + Shift + L` | Cambiar tema (claro / oscuro) |
| `Ctrl + ,` | Abrir Configuración |
| `F9` | Maximizar / Restaurar ventana |
| `F11` | Pantalla completa (modo kiosco) |
| `Ctrl + Q` | Salir del sistema (con confirmación) |
| `Esc` | Cerrar modal / cancelar |

## 2. Crear (nuevos registros)

| Atajo | Acción |
|---|---|
| `Ctrl + N` | Nuevo Pesaje (entrada) |
| `Ctrl + Shift + N` | Nuevo Pesaje Manual |
| `Ctrl + Shift + V` | Nuevo Vehículo / Camión |
| `Ctrl + Shift + D` | Nuevo Conductor |
| `Ctrl + Shift + T` | Nuevo Transporte |

## 3. Navegación rápida

| Atajo | Módulo |
|---|---|
| `Ctrl + 1` | Inicio |
| `Ctrl + 2` | Entradas |
| `Ctrl + 3` | Salidas |
| `Ctrl + 4` | Reportes |
| `Ctrl + 5` | Kardex |
| `Alt + C` | Clientes / Terceros |
| `Alt + F` | Flota y Transporte |
| `Alt + P` | Productos |
| `Alt + A` | Almacenes |
| `Alt + K` | Kardex |
| `Alt + R` | Reportes |
| `Alt + U` | Usuarios |
| `Alt + D` | Dispositivos |
| `Alt + S` | Seguridad |

## 4. Acciones operativas

| Atajo | Acción |
|---|---|
| `F2` | Pesaje rápido |
| `F5` | Imprimir / refrescar ticket |
| `Ctrl + A` | Ajustes de inventario |
| `Ctrl + L` | Cerrar sesión / bloquear |

## 5. Paleta de comandos (`Ctrl + K`)

Además de las teclas físicas, la paleta acepta comandos escritos:

- `go:wm`, `go:wa` — Pesaje Manual / Automático
- `go:in`, `go:out` — Entradas / Salidas
- `go:fleet` — Flota y Transporte
- `cfg:dev` — Dispositivos de campo
- `new:ticket`, `w:in` — Nuevo pesaje
- `new:truck`, `add:camion` — Nuevo vehículo
- `new:driver`, `add:chofer` — Nuevo conductor
- `t:#123` — Abrir ticket
- `p:A12BC3` — Buscar placa
- `c:V12345678` — Buscar conductor
```

---

## Resumen de la lógica aplicada

| Antes | Ahora | Por qué |
|---|---|---|
| `Ctrl + Shift + Q` para salir | **`Ctrl + Q`** | Estándar universal (Q = Quit) |
| `Ctrl + Shift + N` para nuevo pesaje | **`Ctrl + N`** | Estándar universal (N = New) |
| `Alt + 1` / `Alt + 2` para pesaje manual/auto | `F2` (rápido) y `Ctrl+N` (entrada) | Menos atajos raros, más intuitivos |
| `Ctrl + Shift + L` cambiaba tema y bloqueaba | Solo cambia tema; bloqueo en `Ctrl + L` | Sin colisiones |
| `Alt + I` para inventario | `Alt + P` productos, `Alt + A` almacenes | Mnemónico real |
| `Alt + A` auditoría | `Ctrl + A` ajustes inventario | Coherente con Ctrl+N, Ctrl+B |
| `Ctrl + Shift + S` configuración | **`Ctrl + ,`** | Estándar apps modernas (VS Code, Slack, Notion) |
| Atajos `Ctrl+Shift+T` para transporte y tema | `Ctrl+Shift+T` transporte; tema en `Ctrl+Shift+L` | Sin colisiones |




# Documentación de Atajos de Teclado — Balansoft-WS

Esta guía contiene la asignación completa y estandarizada de accesos directos para la estación de pesaje industrial. El esquema está diseñado para minimizar el uso del mouse durante la operación en balanza.

---

## 1. Flujo de Operación de Báscula (Teclas de Función $F1$–$F12$)

Diseñado para operar directamente desde la fila superior del teclado en la terminal de báscula.

| Tecla | Acción | Descripción / Contexto |
|---|---|---|
| **`F2`** | **Entrada** | Limpia el formulario y abre un pesaje de **entrada**; la báscula default de entradas queda preseleccionada. |
| **`F3`** | **Capturar Peso** | Fija la lectura en curso como peso del paso activo (cabina o remolque). Es **obligatorio** antes de guardar. Botón en *LECTURA DE PESO*. |
| **`F4`** | **Guardar** | Valida, pide la confirmación final (*"¿Desea confirmar guardar este peso?"*) y guarda el pesaje de entrada o registra la salida. `Enter` hace lo mismo cuando el foco no está en un campo de texto. |
| **`F5`** | **Imprimir** | Abre el selector de impresión de boletos (incluye el último boleto registrado). |
| **`F6`** | **Salida** | Abre el selector de boleto pendiente; al elegirlo carga los datos y la báscula default de **salidas**. |
| **`Esc`** | **Cancelar / Salir** | Cierra la alerta abierta si hay una; en la pantalla de pesaje sale de la vista. **Si hay captura sin guardar pide confirmación** (*"Hay información capturada… ¿Desea cancelar de todos modos?"*). El botón *Cancelar* (mismo `Esc` en su etiqueta) limpia el formulario; `F12` queda como atajo global de *Cancelar Operación*. |
| **`F7`** | **Nuevo Vehículo / Camión** | Abre el modal de registro rápido de vehículos/flota sin perder el ticket actual. |
| **`F8`** | **Nuevo Conductor** | Abre el modal de registro rápido de choferes. |
| **`F9`** | **Maximizar / Restaurar** | Alterna el tamaño de la ventana (ideal para pantallas compactas de balanza). |
| **`F10`** | **Mostrar / Ocultar Sidebar** | Colapsa o expande el menú lateral para mayor área de trabajo. |
| **`F11`** | **Pantalla Completa** | Activa/desactiva el modo kiosco. |
| **`F12`** | **Cancelar Operación** | Limpia el formulario activo o descarta el ticket en borrador. |

> `F4` estaba documentado como *Tarar / Cero*. Sigue **pendiente**: el HAL
> (`app/core/scale_hal.py`) solo lee (`read_weight`, `is_stable`) y no envía
> comandos de tara/cero, que dependen del fabricante. Hoy `F4` guarda; el
> monitor aplica el flag de peso neto con el botón `T`.

### 1.1 Captura guiada cabina → remolque (obligatoria)

| Paso | Acción del operador | Resultado en pantalla |
|---|---|---|
| 1 | Carga los datos del pesaje | Báscula de **entrada** preseleccionada. La lectura en vivo llena *Peso Entrada Vehículo*. |
| 2 | Presiona **Capturar peso** (`F3`) con la cabina en la báscula | El peso queda **congelado** en el campo de la cabina. |
| 3 | Con remolque, aparece la alerta **"Mueva el camión"** | Al *Continuar*, la báscula y el indicador pasan a llenar el campo del remolque (resaltado en acento, bajo la alerta); el aviso queda fijo en *LECTURA DE PESO*. Al *No, seguir editando* se permanece en la cabina. |
| 4 | Mueve el camión hasta que el remolque esté sobre la báscula y presiona **Capturar peso** (`F3`) | Ambos pesos quedan congelados; aviso *"Complete los demás datos y presione Enter para guardar"*. |
| 5 | Completa los demás datos y presiona `Enter` (o `F4`) | Confirmación *"¿Desea confirmar guardar este peso?"* con el resumen de pesos y el tipo de pesaje (*ENTRADA* / *SALIDA*). |
| 6 | Tras guardar | Confirmación *"¿Desea imprimir?"* → **Imprimir** o **Nuevo peso**. |
| 7 | Si presiona `Esc` o la **X** de la ventana con datos sin guardar | Alerta de confirmación: *"Hay información … que no ha sido guardada. ¿Desea … de todos modos?"*. Solo cierra/limpia si confirma. |

Reglas: la captura es obligatoria también en **salida** (mismo mecanismo para
cabina y remolque); guardar sin haber pulsado *Capturar peso* se rechaza; la
tara sugerida del remolque no cuenta como captura; con una sola báscula
registrada esa es la default de entradas y salidas. La estación **arranca
maximizada**.

### 1.2 Resumen de pesos y tolerancia (LECTURA DE PESO)

Bajo la tabla de lectura se muestra el bloque **CONTROL DE PESOS Y TOLERANCIA**
según `docs/DOCUMENTACION VIEJA/MODEL.md`: fechas de entrada/salida, peso camión,
peso remolque, peso total, **PNT = PTE − PTS**, **PND**, **PDF = PNT − PND**,
**PDV = PDF / PND (%)**, la tolerancia del producto seleccionado y el
**Estado** (*DENTRO* / *SOBRE* / *BAJO*) con el rango aceptado `PND ± tol.`.
Sin PND o tolerancia se muestra `-` en vez de `#¡DIV/0!` / `#¡VALOR!`.
---

## 2. Acciones de Creación y Entidades (`Ctrl` / `Ctrl + Shift`)

| Atajo | Acción | Descripción |
|---|---|---|
| `Ctrl + N` | Nuevo Pesaje Estándar | Crea una nueva entrada/pesaje rápido. |
| `Ctrl + Shift + N` | Nuevo Pesaje Manual | Vía alternativa para apertura manual. |
| `Ctrl + Shift + V` | Nuevo Vehículo | Registro de camión/placa. |
| `Ctrl + Shift + D` | Nuevo Conductor | Registro de chofer (*Driver*). |
| `Ctrl + Shift + T` | Nuevo Transporte | Módulo/Registro de empresa transportista. |
| `Ctrl + A` | Ajustes de Inventario | Abre el panel de corrección/ajuste manual de stock. |

---

## 3. Entorno e Interfaz Global

| Atajo | Acción | Descripción |
|---|---|---|
| `Ctrl + B` | Alternar Sidebar | Muestra u oculta la barra lateral. |
| `Ctrl + K` | Paleta de Comandos | Abre la búsqueda rápida ejecutable por comandos. |
| `Ctrl + H` | Inicio / Dashboard | Regresa al panel principal (*Home*). |
| `Ctrl + Shift + L` | Cambiar Tema | Alterna entre modo claro y oscuro (*Light/Dark*). |
| `Ctrl + ,` | Configuración | Abre el panel de ajustes de la aplicación. |
| `Ctrl + L` | Bloquear / Cerrar Sesión | Cierra la sesión activa por seguridad (*Lock*). |
| `Ctrl + Q` | Salir del Sistema | Muestra el diálogo de confirmación para cerrar la app (*Quit*). |
| `Esc` | Cerrar / Cancelar | Cierra el modal o diálogo activo. |
| `Backspace` / `Delete` | Volver Atrás | Navega a la vista anterior (solo si no hay un input de texto enfocado). |

---

## 4. Navegación Rápida por Módulos

### Vía Números (`Ctrl + Nro`)
| Atajo | Módulo Destino |
|---|---|
| `Ctrl + 1` | Inicio / Dashboard |
| `Ctrl + 2` | Entradas (Ingresos) |
| `Ctrl + 3` | Salidas (Despachos) |
| `Ctrl + 4` | Reportes |
| `Ctrl + 5` | Kardex / Inventario |

### Vía Teclas Mnemónicas (`Alt + Letra`)
| Atajo | Módulo Destino | Clave Mnemónica |
|---|---|---|
| `Alt + C` | Clientes / Terceros | **C**lientes |
| `Alt + F` | Flota y Vehículos | **F**lota |
| `Alt + P` | Productos | **P**roductos |
| `Alt + A` | Almacenes | **A**lmacén |
| `Alt + K` | Kardex | **K**ardex |
| `Alt + R` | Reportes | **R**eportes |
| `Alt + U` | Usuarios | **U**suarios |
| `Alt + D` | Dispositivos de Campo | **D**ispositivos |
| `Alt + S` | Seguridad y Permisos | **S**eguridad |

---

## 5. Paleta de Comandos (`Ctrl + K`)

Comandos rápidos disponibles para escribir en la paleta:

* **Navegación:** `go:wm` (Pesaje Manual), `go:wa` (Pesaje Auto), `go:in` (Entradas), `go:out` (Salidas), `go:fleet` (Flota), `cfg:dev` (Dispositivos).
* **Creación:** `new:ticket` / `w:in` (Nuevo ticket), `new:truck` / `add:camion` (Nuevo vehículo), `new:driver` / `add:chofer` (Nuevo conductor).
* **Búsqueda rápida:**
  * `t:#123` → Busca ticket número 123.
  * `p:A12BC3` → Busca por placa de vehículo.
  * `c:V12345678` → Busca por cédula/RIF de conductor o cliente.
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

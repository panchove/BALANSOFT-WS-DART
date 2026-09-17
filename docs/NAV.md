 
 ```
================================================================================
                      TOP NAVBAR (HEAD / ACCESO RÁPIDO)
================================================================================
[ ☰ Toggle Sidebar ]  [ Logo / Nombre ]                     [ 👤 Usuario | 🚪 ]   <--- EL HEAD ES OPCIONAL EN CASO DE QUE SEA TABLET O TELEFONO Y NO SE VEA EL LOGO E INFORMACION DE LA CUENTA EN EL SIDEBAR YA QUE SE OCULTA EN PANTALLAS PEQUEÑAS
────────────────────────────────────────────────────────────────────────────────
 Botones de Acción Rápida:
 [ 📝 Pesaje Manual ]  [ 🤖 Pesaje Auto ]  [ 📦 Ajustes Inv. ]  [ 📥/📤 Movs. ]  [ 🛡️ Auditoría ]  [ ❓ Ayuda ]
================================================================================


================================================================================
                             SIDEBAR (MENÚ LATERAL)
================================================================================
-----------------------------
 📊 INICIO
-----------------------------
 📦 INFORMACION - LISTA
   ├── 👥 Entidades - MENÚ DESPLEGABLE
   │     ├── Clientes
   │     ├── Proveedores
   │     └── Usuarios del Sistema
   ├── 🚛 Flota y Transporte - MENÚ DESPLEGABLE
   │     ├── Camiones / Vehículos
   │     ├── Conductores
   │     └── Empresas de Transporte
   ├── 🏬 Inventario Base - MENÚ DESPLEGABLE
   │     ├── Categorías
   │     ├── Productos
   │     └── Almacenes
   └── 📋 Kardex (Conceptos de Movimiento)
------------------------------------
 📈 REPORTES - Lista
   ├── 📥 Ingresos (Entradas)
   ├── 📤 Despachos (Salidas)
   └── 🧮 Inventario (Stock Físico)
---------------------------------------
 ⚙️ MANTENIMIENTO Y CONFIGURACIÓN (Vista Interna / Subsecciones) - LISTA
   ├── 🔌 Dispositivos de Campo (Básculas, Periféricos)
   ├── 👤 Seguridad y Accesos (Roles y Permisos)
   ├── 📄 Empresa y Documentos
   └── 🛠️ Configuración General
```


**Atajos de Teclado Globales del Sistema**

Mapeo de comandos para el control general del sistema y navegación del entorno, manteniendo una estructura corta e intuitiva.

---

### 1. Control de Interfaz y Entorno Global

| Atajo | Acción | Contexto |
| --- | --- | --- |
| `Ctrl + B` / `F10` | **Mostrar / Ocultar Sidebar (Menú Lateral)** | Global |
| `Ctrl + K` / `F2` | **Abrir Paleta de Comandos / Búsqueda Rápida** | Global |
| `Ctrl + H` | Ir a **Dashboard / Inicio** | Global |
| `Ctrl + Shift + L` | Cambiar **Tema (Claro / Oscuro)** | Global |
| `F11` | Alternar **Pantalla Completa** (Modo Báscula / Kiosco) | Global |
| `F9` | **Maximizar / Restaurar** la ventana | Global (escritorio) |
| `Ctrl + Shift + Q` | **Salir del sistema** (cerrar la aplicación, con confirmación) | Global (escritorio) |
| `Esc` | **Cerrar modales, cancelar o limpiar búsquedas** | Global |

---

### 2. Navegación Rápida a Módulos (Nivel Principal)

| Atajo | Módulo Destino |
| --- | --- |
| `Alt + 1` | **Pesaje Manual** |
| `Alt + 2` | **Pesaje Automático** |
| `Alt + 3` | **Consultas: Entradas** |
| `Alt + 4` | **Consultas: Salidas** |
| `Alt + 5` | **Ajustes de Inventario** |
| `Alt + C` | Catálogo de **Clientes / Proveedores** |
| `Alt + F` | Catálogo de **Flota y Transporte** |
| `Alt + I` | Catálogo de **Inventario Base** |
| `Alt + R` | **Reportes** |
| `Alt + A` | **Auditoría** |
| `Ctrl + Shift + S` | **Mantenimiento / Configuración General** |

---

### 3. Operaciones de Acción Global

| Atajo | Acción |
| --- | --- |
| `Ctrl + Shift + N` | Abrir modal rápido: **Nuevo Ticket de Pesaje** |
| `Ctrl + Shift + T` | Abrir modal rápido: **Nuevo Vehículo / Chuto** |
| `Ctrl + Shift + D` | Abrir modal rápido: **Nuevo Conductor** |
| `Ctrl + Shift + L` | **Bloquear Pantalla / Cerrar Sesión** |

---

En la consola de búsqueda (Paleta de Comandos `Ctrl + K`), el usuario escribirá **términos directos, códigos o prefijos cortos** para navegar o ejecutar acciones sin tocar el mouse.

El buscador interpretará lo que escribas según tres modalidades:

---

### 1. Búsqueda Directa por Nombre (Navegación Normal)

Escribes la palabra clave del módulo y te sugiere el destino en tiempo real:

* `pesaje` $\rightarrow$ Lleva a *Pesaje Manual* / *Pesaje Automático*
* `clientes` $\rightarrow$ Abre el catálogo de *Clientes*
* `chofer` o `conductor` $\rightarrow$ Abre la lista de *Conductores*
* `empresa` $\rightarrow$ Abre la *Configuración de Empresa*

---

### 2. Atajos de Comando Rápido (Sintaxis Corta)

Comandos ultracortos para usuarios avanzados que buscan máxima velocidad:

| Lo que escribes | Acción que ejecuta |
| --- | --- |
| `go:wm` | Salta directamente a **Pesaje Manual** |
| `go:wa` | Salta directamente a **Pesaje Automático** |
| `go:in` | Abre la consulta de **Entradas** |
| `go:out` | Abre la consulta de **Salidas** |
| `go:fleet` | Abre el catálogo de **Flota y Transporte** |
| `cfg:dev` | Abre la configuración de **Dispositivos de Campo (Básculas)** |

---

### 3. Comandos de Acción Rápida (Prefijo `new:` o `add:`)

Abre un modal o formulario de registro directo desde cualquier pantalla:

* `new:ticket` o `w:in` $\rightarrow$ Abre el formulario para un nuevo Pesaje de Entrada.
* `new:truck` o `add:camion` $\rightarrow$ Abre la ventana rápida para registrar un Chuto/Trailer.
* `new:driver` o `add:chofer` $\rightarrow$ Abre la ventana para registrar un nuevo Conductor.

---

### 4. Búsqueda Operativa Directa (Prefijo de Búsqueda)

Escribes directamente el identificador para ir a un registro específico:

* `t:SERIE-00000123` o `#123` $\rightarrow$ Abre la ficha del **Ticket #123**.
* `p:A12BC3` $\rightarrow$ Busca la **Placa A12BC3** en la flota de camiones.
* `c:V12345678` $\rightarrow$ Busca al conductor por su cédula o DNI.
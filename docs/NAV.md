 
 ```
================================================================================
                      TOP NAVBAR (HEAD / ACCESO RÁPIDO)
================================================================================
[ ☰ Toggle Sidebar ]  [ Logo / Nombre ] [INFORMACION DE LA EMPRESA TITULAR]     [ 🔔 Notificaciones | SYNC/LOCAL | 👤 Usuario | 🚪 ]   <--- EL HEAD ES OPCIONAL EN CASO DE QUE SEA TABLET O TELEFONO Y NO SE VEA EL LOGO E INFORMACION DE LA CUENTA EN EL SIDEBAR YA QUE SE OCULTA EN PANTALLAS PEQUEÑAS

 La campana 🔔 muestra el contador de avisos no leídos (sonda el backend local) y abre el CENTRO DE NOTIFICACIONES
 (historial, marcar leídas/archivar). Desde ahí el ADMIN entra a RECORDATORIOS (avisos programados, con hora y recurrencia).
────────────────────────────────────────────────────────────────────────────────
 Botones de Acción Rápida:
 [ 📝 Pesaje Manual ]  [ 🤖 Pesaje Auto ]  [ 📦 Ajustes Inv. ]  [ 📥/📤 Movs. ]  [ 🛡️ Auditoría ]  [ ❓ Ayuda ]
================================================================================


================================================================================
                             SIDEBAR (MENÚ LATERAL)
================================================================================
 📊 INICIO (Dashboard)                                 [Ctrl + 1 / Ctrl + H]
--------------------------------------------------------------------------------
 📦 CATÁLOGOS
   ├── Clientes                                        [Alt + C]
   ├── Proveedores
   ├── -----------------------------------------------------------------------
   ├── Transportes                                     [Ctrl + ⇧ + T]
   ├── Conductores                                     [F8]
   ├── Camiones / Vehículos                            [Alt + F]
   ├── -----------------------------------------------------------------------
   ├── Categorías
   ├── Productos                                       [Alt + P]
   ├── -----------------------------------------------------------------------
   └── Almacenes                                       [Alt + A]
   ├── -----------------------------------------------------------------------
   └── Conceptos de Inventario
--------------------------------------------------------------------------------
 🧭 GESTIÓN
   ├── Peso Manual                                     [F2]
   ├── Peso Automático                                 [F1]
   ├── -----------------------------------------------------------------------
   └── Inventario (Ajustes de Inventario)              [Ctrl + A]
--------------------------------------------------------------------------------
 🔎 CONSULTAR
   ├── Entradas                                        [Ctrl + 2]
   ├── Salidas                                         [Ctrl + 3]
   ├── -----------------------------------------------------------------------
   ├── Ingresos                                        [Alt + I]
   ├── Despachos                                       [Alt + E]
   ├── -----------------------------------------------------------------------
   └── Auditoría del Sistema
--------------------------------------------------------------------------------
 📈 REPORTES
   ├── Reportes Generales                              [Ctrl + 4]
   ├── Kardex (Movimientos)                            [Ctrl + 5 / Alt + K]
   ├── -----------------------------------------------------------------------
   ├── Diarios
   ├── Mensuales
   └── Personalizado
--------------------------------------------------------------------------------
 ⚙️ MANTENIMIENTO (ADMIN)
   ├── Empresa y Documentos
   ├── -----------------------------------------------------------------------
   ├── Usuarios del Sistema                            [Alt + U]
   ├── Roles
   ├── Seguridad y Accesos (Roles y Permisos)          [Alt + S]
   ├── -----------------------------------------------------------------------
   ├── Semáforos
   ├── Cámaras
   ├── Impresoras
   ├── Básculas                                        [Alt + D]
   ├── Indicadores
   ├── -----------------------------------------------------------------------
   ├── Diseño de Ticket
   └── Configuración General                           [Ctrl + ,]
--------------------------------------------------------------------------------
 ❓ AYUDA Y SOPORTE
   ├── Ayuda y Soporte
   ├── -----------------------------------------------------------------------
   ├── Manuales
   ├── Página Web
   ├── Versión
   └── Tutorial

 Nota: el menú es data-driven (`menu.json`); esta es la estructura de FÁBRICA.
 Diagnóstico del Sistema, Administración de Licencia y Conexiones se alcanzan
 desde la paleta de comandos (Ctrl + K) y desde Configuración, no desde el
 sidebar.

```

---

## Menú lateral configurable (`menu.json`)

El sidebar **no está hardcodeado**: en cada arranque la app lee un archivo JSON y
construye el menú desde ahí. Editando ese archivo se pueden **agregar opciones**,
**quitarlas**, **reordenarlas** y **moverlas** entre secciones/grupos, además de
insertar **líneas separadoras**.

- **Implementación**: `frontend/lib/core/config/menu_config.dart` (`MenuNode`,
  `MenuIconos`, `MenuConfigPaths`, `MenuConfig`).
- **Consumo**: `presentation/widgets/app_sidebar.dart` (escritorio),
  `presentation/widgets/mobile_nav_sheet.dart` (menú móvil) y
  `presentation/screens/dashboard/home_shell.dart` (bottom bar + navegación).
- **Carga**: `main.dart` → `await MenuConfig.cargar()` antes de `runApp`.
- Un JSON inválido o ausente **degrada al menú de fábrica**: nunca impide arrancar.

### Ubicación del archivo

Mismo contrato de rutas que `config.json` (`StationConfigPaths`):

| Prioridad | Ruta | Uso |
|-----------|------|-----|
| 1 | `~/.config/balansoftws/menu.json` | Override del usuario (gana) |
| 2 | `/etc/balansoftws/menu.json` (Linux) · `%ProgramData%\BalansoftWS\menu.json` (Windows) | Menú del sistema/instalador |

Si no existe en ningún lado, la app **siembra** el archivo en el override con el
árbol por defecto (formateado con sangría), para que siempre haya algo que editar.
Los cambios se aplican **al reiniciar la app**.

### Estructura

```json
{
  "version": 1,
  "menu": [
    {
      "tipo": "seccion",
      "label": "INICIO",
      "hijos": [
        { "tipo": "opcion", "label": "Inicio", "clave": "inicio", "icono": "dashboard_outlined", "icono_activo": "dashboard", "atajo": "Ctrl+1" }
      ]
    },
    {
      "tipo": "seccion",
      "label": "CATÁLOGOS",
      "hijos": [
        { "tipo": "opcion", "label": "Clientes", "clave": "clientes", "icono": "handshake_outlined", "atajo": "Alt+C" },
        { "tipo": "opcion", "label": "Proveedores", "clave": "proveedores", "icono": "storefront_outlined" },
        { "tipo": "separador" },
        { "tipo": "opcion", "label": "Kardex", "clave": "kardex", "icono": "table_rows_outlined", "roles": ["ADMIN", "OPERADOR"] },
        {
          "tipo": "grupo",
          "label": "Mi grupo",
          "icono": "inventory_2_outlined",
          "hijos": [
            { "tipo": "opcion", "label": "Productos", "clave": "productos" }
          ]
        }
      ]
    }
  ]
}
```

### Tipos de nodo (`tipo`)

| `tipo` | Qué dibuja | Campos |
|--------|-----------|--------|
| `seccion` | Encabezado de sección (no colapsable: sus hijos se dibujan siempre) | `label`, `i18n`, `icono`, `roles`, `hijos` |
| `grupo` | Grupo desplegable con icono (arranca colapsado) | `label`, `i18n`, `icono`, `roles`, `hijos` |
| `opcion` | Hoja de menú que navega | `label`, `i18n`, `icono`, `icono_activo`, `atajo`, `roles` + **`clave`** o **`accion`** |
| `separador` | Línea divisoria entre opciones | — |

### Destinos válidos

- **`clave`** — abre una pantalla del shell. Valores admitidos:
  `inicio`, `terceros`, `clientes`, `proveedores`, `camiones`, `conductores`,
  `transportes`, `categorias`, `productos`, `almacenes`, `kardex`, `entradas`,
  `salidas`, `ingresos`, `despachos`, `reportes`, `usuarios`, `dispositivos`,
  `dispositivos_basculas`, `dispositivos_indicadores`, `dispositivos_semaforos`,
  `dispositivos_camaras`, `dispositivos_impresoras`,
  `seguridad`, `documentos_empresa`, `diseno_ticket`, `configuracion`.
- **`accion`** — ejecuta un comando del shell (debe empezar por `go:`):
  `go:pesaje_automatico`, `go:pesaje_manual`, `go:ajustes`, `go:auditoria`,
  `go:sesiones`, `go:diagnostico`, `go:licencia`, `go:conexiones`, `go:ayuda`.

Una opción con `clave` desconocida se **descarta** y el motivo queda en
`MenuConfig.errores`; el resto del menú sigue funcionando.

### Reglas y comportamiento

- **Orden**: el orden visual es exactamente el del JSON (dentro de cada nivel).
- **Roles**: `roles` filtra quién ve la opción. Si se omite, la opción se rige
  por la matriz de accesos (`AccesosDefault` / `Seguridad y Accesos`) usando su
  `clave`. Para las hojas-acción (sin `clave`), `roles` ausente = todos.
- **i18n**: si se indica `i18n` (p. ej. `"menu_inicio"`), esa clave manda. Si no,
  se traduce por el mapa etiqueta→clave. Una etiqueta personalizada se muestra
  literal.
- **Iconos**: se referencian por **nombre** (`dashboard_outlined`,
  `smart_toy_outlined`, …). Un nombre desconocido cae a un icono de respaldo en
  vez de romper la pantalla. El catálogo completo está en `MenuIconos.mapa`.
- **Separadores**: se recortan los que quedan al inicio, al final o consecutivos
  (también tras la poda por rol), para no dejar líneas sueltas.
- **Bottom bar (móvil)**: los separadores no son hojas y no ocupan índice, así
  que no aparecen como pestañas.

### Probar sin tocar la máquina

`MenuConfigPaths.pruebasOverrideDir` / `pruebasSistemaDir` redirigen las rutas
(solo tests). `MenuConfig.inyectarParaPruebas(arbol)` fija el árbol efectivo.
Cobertura: `test/unit/menu_config_test.dart` (23 casos) y
`test/widget/navigation_shortcuts_test.dart` (separadores, reordenamiento y la
estructura de fábrica del menú).

### Diagnóstico

`MenuConfig.errores` acumula los problemas del último `cargar()` (clave
desconocida, acción sin `go:`, JSON inválido, ítem sin `tipo`, …) y
`MenuConfig.ruta` dice qué archivo se leyó. `MenuConfig.restaurarDefecto()`
vuelve al menú de fábrica (y borra el override).


# Inventario de Navegación y Configuración del Menú

## 1. Inventario: Todo lo alcanzable desde el Sidebar

Cada opción del menú resuelve su destino de forma estable (por clave → índice, o por acción → comando `go:*`), nunca por su posición visual.

### Hojas‑página (Clave → Índice en `_pages` de `home_shell.dart`)

| # | Opción | Clave | Pantalla |
| :--- | :--- | :--- | :--- |
| **0** | Inicio | `inicio` | `presentation/screens/dashboard/dashboard_screen.dart` |
| **1** | Terceros (unificado) | `terceros` | `presentation/screens/catalog/catalog_crud_screen.dart` |
| **2** | Usuarios del Sistema | `usuarios` | `presentation/screens/settings/usuarios_screen.dart` |
| **3** | Camiones / Vehículos | `camiones` | `catalog/catalog_crud_screen.dart` |
| **4** | Conductores | `conductores` | `catalog/catalog_crud_screen.dart` |
| **5** | Transportes | `transportes` | `catalog/catalog_crud_screen.dart` |
| **6** | Categorías | `categorias` | `catalog/catalog_crud_screen.dart` |
| **7** | Productos | `productos` | `catalog/catalog_crud_screen.dart` |
| **8** | Almacenes | `almacenes` | `catalog/catalog_crud_screen.dart` |
| **9** | Kardex | `kardex` | `presentation/screens/kardex/kardex_screen.dart` |
| **10** | Entradas | `entradas` | `presentation/screens/weighing/weighing_list_screen.dart` *(filtro estado)* |
| **11** | Salidas | `salidas` | `weighing/weighing_list_screen.dart` *(estado inicial CERRADO)* |
| **12** | Reportes Generales | `reportes` | `presentation/screens/reports/reports_screen.dart` |
| **13** | Básculas | `dispositivos_basculas` | `presentation/screens/dispositivos/basculas_screen.dart` *(vista propia; búsqueda + filtros)* |
| **14** | Seguridad y Accesos | `seguridad` | `presentation/screens/seguridad/seguridad_screen.dart` |
| **15** | Empresa y Documentos | `documentos_empresa` | `presentation/screens/empresa/documentos_empresa_screen.dart` |
| **16** | Configuración | `configuracion` | `presentation/screens/settings/settings_screen.dart` |
| **17** | Diseño de Ticket | `diseno_ticket` | `presentation/screens/settings/ticket_design_screen.dart` |
| **18** | Clientes | `clientes` | `catalog/catalog_crud_screen.dart` *(terceros con `tipo` CLIENTE)* |
| **19** | Proveedores | `proveedores` | `catalog/catalog_crud_screen.dart` *(terceros con `tipo` PROVEEDOR)* |
| **20** | Roles | `roles` | `presentation/screens/roles/roles_screen.dart` *(informativo; enlaza a la matriz de accesos)* |
| **21** | Ingresos | `ingresos` | `presentation/screens/weighing/weighing_list_screen.dart` *(movimiento kardex 10, `kardex_mov=10`)* |
| **22** | Despachos | `despachos` | `presentation/screens/weighing/weighing_list_screen.dart` *(movimiento kardex 60, `kardex_mov=60`)* |
| **23** | Básculas | `dispositivos_basculas` | `presentation/screens/dispositivos/basculas_screen.dart` *(vista propia; búsqueda + filtros)* |
| **24** | Indicadores | `dispositivos_indicadores` | `presentation/screens/dispositivos/indicadores_screen.dart` *(vista propia; búsqueda + filtros)* |
| **25** | Semáforos | `dispositivos_semaforos` | `presentation/screens/dispositivos/semaforos_screen.dart` *(vista propia; búsqueda + filtros)* |
| **26** | Cámaras | `dispositivos_camaras` | `presentation/screens/dispositivos/camaras_screen.dart` *(vista propia; búsqueda + filtros por `origen`; «Detectar» cámaras locales/USB con badge `IP`/`LOCAL`)* |
| **27** | Barreras | `dispositivos_barreras` | `presentation/screens/dispositivos/barreras_screen.dart` *(vista propia; búsqueda + filtros)* |
| **28** | Impresoras | `dispositivos_impresoras` | `presentation/screens/dispositivos/impresoras_screen.dart` *(vista propia; búsqueda + filtros)* |
| **29** | Conceptos Kardex | `conceptos_inventario` | `presentation/screens/inventario/conceptos_kardex_screen.dart` *(catálogo `conceptos_kardex`, migración 031 — ver sección propia más abajo)* |

> **Nota sobre la clave 29:** la clave de menú sigue siendo `conceptos_inventario`
> por compatibilidad con los `menu.json` ya instalados, pero la pantalla y el
> backend apuntan al catálogo **`conceptos_kardex`** (migración 031). El catálogo
> antiguo `conceptos_inventario` (migración 029) sigue existiendo en la API para
> no romper clientes, pero **ya no lo usan los ajustes manuales**.

> **Clientes / Proveedores** son la **misma tabla `terceros`** filtrada por
> `tipo` (`AppCatalogos.clienteResource` / `proveedorResource`). **Ingresos /
> Despachos** son la **misma lista de pesajes** segmentada por el asiento de
> kardex del boleto (`WeighingListScreen.tipoMovimiento`), que ahora se filtra
> **en el servidor** con `GET /weighing/list?kardex_mov=10|60`; el KPI
> «Total ingresado / Total despachado» viene de `GET /weighing/resumen`.

### Conceptos Kardex (migración 031)

Catálogo de **IDs 0-99** que da nombre a los movimientos de inventario. Reglas:

| Rango | Signo | Quién lo define |
| :--- | :--- | :--- |
| `00` | inicial | **Sistema** (saldo inicial, no genera movimiento) |
| `01`–`49` | positivo | ADMIN (ajustes manuales) |
| `10` | positivo | **Sistema** (ingreso por báscula, al cerrar boleto con PNT ≥ 0) |
| `50`–`59` | negativo | ADMIN (ajustes manuales) |
| `60` | negativo | **Sistema** (despacho por báscula, al cerrar boleto con PNT < 0) |
| `61`–`99` | negativo | ADMIN (ajustes manuales) |

- La pantalla **solo ofrece IDs huecos** y deriva el signo del rango: el ID
  define el signo, nunca al revés.
- Los conceptos del sistema (0/10/60) **no se pueden borrar** (`409`) ni cambiar
  de signo (`422`); sí se pueden renombrar.
- Un concepto con movimientos **no se borra**: se ofrece **desactivar**.
- `GET /reports/kardex/detalle` devuelve `concepto_nombre`, `concepto_signo`,
  `concepto_es_sistema` y `origen` (`Báscula` / `Manual` / `Sistema`).
- El ajuste manual (`POST /inventario/ajustes`) exige `id_concepto` no-sistema y
  una cantidad del **mismo signo**; el movimiento queda con
  `id_movimiento = id_concepto` y auditado con el motivo.

### Hojas‑acción (`accion` → `go:*` resuelto por `home_shell.ejecutarAccion`)

| Opción | Acción | Destino |
| :--- | :--- | :--- |
| **Peso Automático** | `go:pesaje_automatico` | `weighing/weighing_form_screen.dart` *(modo auto)* |
| **Peso Manual** | `go:pesaje_manual` | `weighing/weighing_form_screen.dart` *(modo manual)* |
| **Inventario** | `go:ajustes` | `presentation/screens/ajustes_inventario/ajustes_inventario_screen.dart` |
| **Auditoría del Sistema** | `go:auditoria` | `presentation/screens/auditoria/auditoria_screen.dart` |
| **Ayuda y Soporte** | `go:ayuda` | `presentation/screens/ayuda/ayuda_screen.dart` |
| **Manuales** | `go:ayuda_manuales` | Abre el manual de usuario en el navegador externo (`core/constants/ayuda_links.dart`) |
| **Página Web** | `go:ayuda_pagina` | Abre `http://www.balansoft.com.ve` en el navegador externo |
| **Versión** | `go:ayuda_version` | Diálogo con la versión del cliente (`AppConfig.appVersion`) y de la API (`GET /environment`) |
| **Tutorial** | `go:ayuda_tutorial` | Abre la guía rápida (`mostrarGuiaRapida`) |
| **Sesiones y Equipos** | `go:sesiones` | `presentation/screens/sesiones/sesion_equipo_screen.dart` *(solo paleta/Configuración)* |
| **Diagnóstico del Sistema** | `go:diagnostico` | `presentation/screens/diagnostico/diagnostico_screen.dart` *(solo paleta)* |
| **Administración de Licencia** | `go:licencia` | `presentation/screens/licencia/licencia_screen.dart` *(solo paleta)* |
| **Conexiones (API Local / Servidor)** | `go:conexiones` | `presentation/screens/conexiones/conexiones_screen.dart` *(solo paleta)* |

---

## 2. Menú Configurable por JSON

- **Archivo:** `frontend/lib/core/config/menu_config.dart`
- **Ruta del JSON:** `~/.config/balansoftws/menu.json` *(override del usuario, prioridad alta)* → `/etc/balansoftws/menu.json` *(sistema)*.
  - *Nota:* Si no existe, la app lo siembra automáticamente con el árbol por defecto formateado para facilitar su edición.

### Estructura de Ejemplo

```json
{
  "version": 1,
  "menu": [
    {
      "tipo": "seccion",
      "label": "CATÁLOGOS",
      "hijos": [
        {
          "tipo": "opcion",
          "label": "Clientes",
          "clave": "clientes",
          "icono": "handshake_outlined",
          "icono_activo": "handshake",
          "atajo": "Alt+C"
        },
        { "tipo": "separador" },
        {
          "tipo": "opcion",
          "label": "Kardex",
          "clave": "kardex",
          "icono": "table_rows_outlined",
          "roles": ["ADMIN", "OPERADOR"]
        },
        {
          "tipo": "grupo",
          "label": "Mi grupo",
          "icono": "inventory_2_outlined",
          "hijos": [
            {
              "tipo": "opcion",
              "label": "Productos",
              "clave": "productos"
            }
          ]
        }
      ]
    }
  ]
}

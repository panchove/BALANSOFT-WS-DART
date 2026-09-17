### Estatus de Transacciones

* **Pendiente:** Pesaje de entrada realizado; esperando el pesaje de salida para completar el proceso.
* **Cerrado:** Proceso de pesaje completado con captura de Tara y Peso Bruto.
* **Anulado:** Ticket o transacción cancelada (requiere auditoría).
* **Modificado:** Registros ajustados manualmente por el operador. **Regla de negocio:** *El peso registrado por la báscula nunca puede ser editado.*

---

### ROLES DE USUARIO
- Admin.
- Operador.
- Auditor.
- Trabajador.

### Mapeo de Navegación del Sistema

#### 1. Catálogos (Datos Maestros)

| Módulo | Descripción / Reglas |
| --- | --- |
| **Clientes** | Registro de entidades receptoras. Clasificación: `C` (Cliente) / `A` (Ambos). |
| **Proveedores** | Registro de entidades proveedoras. Clasificación: `P` (Proveedor) / `A` (Ambos). |
| **Flota y Transporte** | Registro de **Camiones**, **Conductores** y **Empresas de Transporte**. |
| **Inventario Base** | Registro de **Categorías**, **Productos** y **Almacenes**. |
| **Kardex** | Configuración de **Conceptos de Movimiento** para el control de inventario. |

> **Estructura de Unidad Tractora:**
> * **Configuración estándar:** Chuto + Trailer (+ Remolque opcional).
> * **Placa Chuto / Tractocamión:** Campo obligatorio (Requerido).
> * **Placa Remolque / Batea:** Campo opcional.
> 
> 

---

#### 2. Gestión (Operaciones)

* **Pesaje Manual (Flujo Clientes / Entradas - Salidas):** Operador captura y valida manualmente los datos de pesaje.
* **Pesaje Automático (Flujo Proveedores / Proceso Automatizado):** Lectura e integración directa desde indicadores/sensores.
* **Ajustes de Inventario:** Modificación y control directo de existencias en almacén.

---

#### 3. Consultas

* **Entradas:** Historial de vehículos ingresados y pesajes de tara/bruto pendientes o cerrados.
* **Salidas:** Historial de despachos terminados.
* **Auditoría:** Registro detallado de acciones, cambios de estado y modificaciones por usuario.

---

#### 4. Reportes

* **Ingresos (Entradas):** Consolidado de recepción de materia prima o productos por proveedor/cliente.
* **Despachos (Salidas):** Consolidado de mercancía despachada.
* **Inventario:** Balance de stock físico actual según movimientos de báscula.

---

#### 5. Mantenimiento y Configuración

* **Dispositivos de Campo:**
* Básculas (Configuración de puertos serie/red e indicadores).
* *Periféricos (Próxima Fase / A Futuro):* Semáforos, Barreras de acceso, Cámaras LPR/CCTV.


* **Seguridad y Accesos:**
* Control de **Roles** y **Usuarios**.


* **Definición de Documentos y Empresa:**
* **Configuración de Formato de Documentos:** (Ejemplo: `SERIE-000000001`).
* **Perfil de Empresa:** Datos fiscales, subida de Logo y activación de envío automático de comprobantes por Email (`Boolean`).


* **Configuración General del Sistema:**
* Apariencia (Tema claro/oscuro).
* Idioma de la interfaz.
* Asignación de **Impresora por Defecto** y **Báscula por Defecto**.



---

#### 6. Ayuda

* **Soporte Técnico.**
* **Información del Sistema (HBN / Acerca de).**

---

### Principales Mejoras Aplicadas

1. **Unificación de términos:** Se agruparon las entidades relacionadas en subsecciones (ej. *Flota y Transporte*, *Inventario Base*).
2. **Clarificación de Reglas de Negocio:** Se explicitó la regla que impide modificar el peso del operador dentro de los estatus.
3. **Estandarización de Mantenimiento:** Se separó la configuración técnica de periféricos de la configuración global del sistema y datos de empresa.
4. **Corrección de tipografías:** Corrección de términos como "Conecptos", "Remlque", "Bascucla" y "Manula".
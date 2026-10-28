# Especificaciones Técnicas de Hardware e Integración (BALANSOFT-WS)

Este documento define el comportamiento, los límites y la lógica de vinculación de los dispositivos periféricos del sistema de pesaje. La app actúa como el **orquestador central**, leyendo datos de entrada y redirigiendo acciones a los dispositivos de salida.

---

## 1. Básculas (Fuente de Peso - Entrada Primaria)

Las básculas son los dispositivos de entrada primarios del sistema. Su lectura define el peso utilizado en el pesaje de la estación.

*   **Conexiones soportadas:** Serie (RS-232), USB y TCP/IP (para básculas emuladas).
*   **Cantidad permitida:** Mínimo 1, máximo 2 activas simultáneamente.
*   **Modos de operación:**
    *   **Modo Automático:** Las básculas tienen prioridad absoluta. El peso se lee directamente del hardware.
    *   **Modo Manual:** Las básculas se desactivan lógicamente. El peso se ingresa manualmente en la interfaz.
    *   **Degradación:** Si el sistema está en modo automático y no detecta ninguna báscula activa, debe notificar al usuario y autorredirigir el flujo a **Modo Manual**.

### ⚠️ Restricción Crítica de Puerto (Inexchangeable)

> **El puerto de conexión de una báscula NUNCA debe modificarse libremente una vez identificada.**

> **Razón:** El puerto (ya sea `puerto_com` serial o `ip_address:puerto_tcp`) es el identificador único del dispositivo físico. Si una básica aparece configurada con `/dev/ttyUSB0` o `192.168.1.50:502`, ese dato **no es editable** en la interfaz de usuario mientras la básica esté en línea o tenga pesajes procesados.

**Reglas de edición de puerto:**

| Condición | Estado del Campo Puerto |
|-----------|------------------------|
| Báscula en línea (última lectura dentro del timeout) | **Read-only** (solo vista, no editable) |
| Báscula con boleto abierto/PENDIENTE | **Read-only** (bloqueado) |
| Báscula sin actividad > 5 minutos y rol ADMIN | editable, pero sistema sugiere re-descubrimiento |
| Rol no-ADMIN en cualquier caso | **No editable** bajo ningún concepto |

**La app debe:**

1. **Mostrar el puerto actual** con color/estado indicador (verde=activo, gris=inactivo)
2. **Bloquear el campo** de protocolo/puertos si la básica tiene lecturas recientes
3. **Solo permitir cambio** en modo ADMIN con diálogo de confirmación: "¿Desvincular báscula por 1 minuto para cambio de puerto?"
4. **Validar que el nuevo puerto** no colisione con otra básica activa en el mismo gateway
5. **Derivar puerto del indicador** automáticamente desde la básica vinculada (no como campo independiente editable)

**UI Esperada para Báscula:**
```
protocol: tcp (dropdown, read-only si activa)
ip_address: 192.168.1.50 (solo lectura si serial, editable si tcp y inactiva)
puerto_tcp: 502 (solo lectura si protocolo serial)
puerto_com: /dev/ttyUSB0 (solo lectura si protocolo tcp)
baudrate: 9600 (editable siempre que báscula inactiva)
formato_trama: auto (editable siempre que báscula inactiva)
delimitador: lf (editable siempre que báscula inactiva)
```

---

## 2. Indicadores (Pantallas de Peso - Salida Esclava)

Los indicadores son dispositivos de **salida** (esclavos). No miden peso; su única función es mostrar el valor que la aplicación les envía.

*   **Conexiones soportadas:** Principalmente puerto serie (RS-232/USB).
*   **Cantidad permitida:** Mínimo 1, máximo 2 activos simultáneamente.
*   **Lógica de vinculación:** La app debe permitir crear un "puente" software entre una báscula y un indicador.
    *   *Ejemplo:* `Báscula 1` se vincula a `Indicador 1` y `Indicador 2`.
    *   *Ejemplo:* `Báscula 1` y `Báscula 2` envían sus pesos a un único `Indicador 1`.
*   **Flujo de datos:** La app lee el peso de la básica asignada y ejecuta un `write()` hacia el puerto del indicador vinculado con el formato de trama configurado.

### ⚠️ Restricción Crítica de Puerto (Derivado, no editable)

> **El puerto serial de un indicador NO debe ser un campo editable independiente.**

> **Razón:** El puerto del indicador **debe derivarse automáticamente** de la básica vinculada. No existe razón para que el usuario configure un puerto serial distinto en el indicador si este debe leer el peso de una básica específica.

**Reglas de puerto para indicadores:**

| Escenario | Configuración de Puerto |
|-----------|------------------------|
| Indicador vinculado a una básica | **Read-only**, valor derivado de `basic.puerto_com` o `basic.ip_address:puerto_tcp` |
| Indicador sin vincular | Campo oculto o deshabilitado; sistema sugiere vincular a básica |
| Cambio de básica vinculada | El puerto se actualiza automáticamente al nuevo básica selección |

**La app debe:**

1. **Mostrar el puerto derivado** en formato read-only con etiqueta "Puerto de la básica vinculada"
2. **No mostrar campos** `puerto_com`, `baudrate`, `formato_trama`, `delimitador` como editables independientes
3. **Heredar configuración** de trama y baudrate desde la básica vinculada
4. **Solo permitir** configuración de: `id_bascula_vinculada`, `marca`, `modelo`, `activo`

**UI Esperada para Indicador:**
```
marca: [input text, opcional]
modelo: [input text, opcional]
activo: [switch]
puerto_serial: /dev/ttyUSB1 (read-only, " derivado de básica: básica-01 ")
formato_trama: auto (read-only, heredado de básica)
baudrate: 9600 (read-only, heredado de básica)
```

---

## 3. Semáforos (Torres de Luz)

Dispositivos de señalización visual/auditiva controlados por cambios de corriente o comandos lógicos.

*   **Conexiones soportadas:** HTTP (Web Switch), USB, o microcontroladores (Arduino/ESP32) que acepten JSON.
*   **Tipos de hardware:** Torres de luz (normalmente de 3 a 6 colores) con o sin zumbador (speaker).
*   **Configuración requerida:**
    *   Dado que existen múltiples fabricantes, el sistema debe permitir configurar **el comando exacto** (JSON o trama serie) para encender/apagar cada color y el zumbador de forma individual.

**Configuración UI:**
```
tipo_conexión: http|serial|mqtt
direccion_url: http://192.168.1.50:8080 (solo http, read-only después guardar)
comando_rojo: {"action":"on"} (JSON editor)
comando_verde: {"action":"off"} (JSON editor)
comando_zumbador: {"toggle":true} (JSON editor)
canales: 3 (selector 3-6 colores)
```

---

## 4. Cámaras (Captura de Placas)

Dispositivos utilizados exclusivamente para la captura de imágenes de las placas de los vehículos.

*   **Conexiones soportadas:** IP, Serie, USB.
*   **Cantidad permitida:** Mínimo 1, máximo 2 activas.
*   **Lógica de operación:** El sistema debe permitir al usuario configurar el **momento de la captura**:
    *   Captura a la **Entrada** (cuando el camión sube a la báscula).
    *   Captura a la **Salida** (cuando el camión abandona la estación).

**Configuración UI:**
```
origen: ip|local
url_snapshot: http://192.168.1.50/snapshot.jpg (solo IP)
dispositivo: Integrated_Webcam (solo local)
ubicacion: entrada|salida|ambos
usar_entrada: [switch - solo si ubicacion=ambos]
usar_salida: [switch - solo si ubicacion=ambos]
```

---

## 5. Barreras de Tránsito

Dispositivos de control físico de acceso (abrir/cerrar). Al igual que los semáforos, operan mediante pulsos de corriente o comandos lógicos.

*   **Conexiones soportadas:** HTTP, USB, controladores lógicos (Arduino/ESP32) o conexión eléctrica directa (relé).
*   **Configuración requerida:**
    *   El sistema debe permitir configurar los comandos/acciones para **Abrir** y **Cerrar** la barrera.

**Configuración UI:**
```
tipo_conexión: http|usb|relé
comando_abrir: {"pulse":true, "duration":2} (JSON editor)
comando_cerrar: {"pulse":true, "duration":1} (JSON editor)
tiempo_pulso: 2 (segundos, input number)
modo_auto: [switch] - activar con semáforo
```

---

## 6. Impresoras (Emisión de Tickets)

Dispositivos de salida para la emisión física del ticket de pesaje.

*   **Cantidad permitida:** Múltiples impresoras registradas en el sistema.
*   **Lógica de operación:**
    *   El usuario puede definir una impresora por defecto.
    *   El sistema **solo envía el documento (PDF)** del ticket generado. La impresora (o su driver) se encarga del renderizado final y la impresión física.

**Configuración UI:**
```
nombre_impresora: impresora_cocina_01 (texto libre)
tipo: POS_80|POS_58|SISTEMA_PDF|MATRIZ_PUNTO
predeterminada: [switch - activa por defecto en nuevos boletos]
test_impresión: [button] - imprime ticket de prueba
```

---

## 7. Matriz de Reglas de Negocio (Vinculación Entrada/Salida)

Para garantizar la operatividad de la estación con cualquier cantidad de hardware disponible, el sistema debe aplicar las siguientes reglas de auto-configuración para los flujos de **Entrada** y **Salida**:

| Escenario de Hardware | Configuración Requerida en el Sistema |
| :--- | :--- |
| **1 Báscula + 1 Indicador** | El único indicador y la única báscula se configuran para operar tanto en la **Entrada** como en la **Salida** automáticamente. |
| **2 Básculas + 1 Indicador** | El indicador se vincula a ambas básculas. Debe mostrar dinámicamente el valor de la básica que esté en uso (Entrada o Salida). |
| **1 Báscula + 2 Indicadores** | La única básica se vincula a ambos indicadores, enviando el mismo peso a los dos simultáneamente, sin importar el modo. |
| **2 Básculas + 2 Indicadores** | **Vinculación directa y exclusiva:** *Báscula de Entrada → Indicador de Entrada* y *Báscula de Salida → Indicador de Salida*. |

### Implicaciones de la Restricción de Puerto en la Matriz:

| Regla | Aplicación de Restricción de Puerto |
|-------|-------------------------------------|
| **1B + 1I** | Puerto del indicador = puerto de la básica (read-only, derivado) |
| **2B + 1I** | Indicador muestra peso de la básica activa; puerto siempre derivado |
| **1B + 2I** | Misma básica envía a los 2 indicadores; puertos idénticos y derivados |
| **2B + 2I** | **Báscula Entrada → Puerto Entrada** y **Báscula Salida → Puerto Salida** (cada puerto derivado de su básica respectiva, **ningún puerto editable manualmente**) |

---

## 8. Reglas de Protección de Datos (Aplicación Obligatoria)

Estas reglas son **INVARIABLES** y de cumplimiento obligatorio en todo desarrollo:

1. **Identidad de puerto = Identidad de dispositivo:**  
   Si `basic_1` tiene `puerto_com = /dev/ttyUSB0`, ese campo es **solo lectura** mientras la básica esté en línea o tenga pesajes pendientes. No se permite escribir `FALSE` ni valores vacíos que rompan la trazabilidad.

2. **Cambio controlado por ADMIN solo:**  
   Solo un administrador puede solicitar cambio de puerto, y el sistema debe:
   - Desvincular temporalmente la básica
   - Ejecutir re-descubrimiento automático
   - Restaurar configuración original si falla el nuevo puerto

3. **Derivación automática obligatoria:**  
   Puerto serial del indicador **siempre** debe derivarse de la básica vinculada. No existe caso de uso donde un indicador tenga puerto serial distinto a su básica asignada.

4. **Validación en tiempo real en UI:**  
   La interfaz debe impedir guardar cualquier forma si:
   - El nuevo puerto ya está en uso por otra básica o indicador
   - La básica está en modo monitoreo activo
   - Hay boletos abiertos con esa básica

5. **Sin campos puerto duplicados:**  
   No existirán campos `puerto_com` independientes en básculas e indicadores que puedan desyncronizarse. El indicador hereda, nunca independiente.

---

### Nota de Implementación para Desarrolladores

- **Backend:** Validar restricciones en FastAPI endpoints antes de aceptar modificaciones de puerto
- **Frontend:** Campos `disabled` o `read-only` según estado de básica; diálogos de confirmación para ADMIN
- **Base de datos:** Campo `puerto_com`/`ip_address` en tablas `balanzas` y `indicadores` debe tener constraint `UNIQUE` por `id_empresa`
- **Tests:** Cobertura para casos de bloqueo de edición cuando básica activa, y casos de cambio exitoso solo ADMIN
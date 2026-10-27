# Especificaciones Técnicas de Hardware e Integración (BALANSOFT-WS)

Este documento define el comportamiento, los límites y la lógica de vinculación de los dispositivos periféricos del sistema de pesaje. La app actúa como el **orquestador central**, leyendo datos de entrada y redirigiendo acciones a los dispositivos de salida.

---

## 1. Básculas (Fuente de Peso)
Las básculas son los dispositivos de entrada primarios del sistema. Su lectura define el peso utilizado en el pesaje de la estación.

*   **Conexiones soportadas:** Serie (RS-232), USB y TCP/IP (para básculas emuladas).
*   **Cantidad permitida:** Mínimo 1, máximo 2 activas simultáneamente.
*   **Modos de operación:**
    *   **Modo Automático:** Las básculas tienen prioridad absoluta. El peso se lee directamente del hardware.
    *   **Modo Manual:** Las básculas se desactivan lógicamente. El peso se ingresa manualmente en la interfaz.
    *   **Degradación:** Si el sistema está en modo automático y no detecta ninguna báscula activa, debe notificar al usuario y autorredirigir el flujo a **Modo Manual**.

---

## 2. Indicadores (Pantallas de Peso)
Los indicadores son dispositivos de **salida** (esclavos). No miden peso; su única función es mostrar el valor que la aplicación les envía.

*   **Conexiones soportadas:** Principalmente puerto serie (RS-232/USB).
*   **Cantidad permitida:** Mínimo 1, máximo 2 activos simultáneamente.
*   **Lógica de vinculación:** La app debe permitir crear un "puente" software entre una báscula y un indicador.
    *   *Ejemplo:* `Báscula 1` se vincula a `Indicador 1` y `Indicador 2`.
    *   *Ejemplo:* `Báscula 1` y `Báscula 2` envían sus pesos a un único `Indicador 1`.
*   **Flujo de datos:** La app lee el peso de la báscula asignada y ejecuta un `write()` hacia el puerto del indicador vinculado con el formato de trama configurado.

---

## 3. Semáforos (Torres de Luz)
Dispositivos de señalización visual/auditiva controlados por cambios de corriente o comandos lógicos.

*   **Conexiones soportadas:** HTTP (Web Switch), USB, o microcontroladores (Arduino/ESP32) que acepten JSON.
*   **Tipos de hardware:** Torres de luz (normalmente de 3 a 6 colores) con o sin zumbador (speaker).
*   **Configuración requerida:**
    *   Dado que existen múltiples fabricantes, el sistema debe permitir configurar **el comando exacto** (JSON o trama serie) para encender/apagar cada color y el zumbador de forma individual.

---

## 4. Cámaras (Captura de Placas)
Dispositivos utilizados exclusivamente para la captura de imágenes de las placas de los vehículos.

*   **Conexiones soportadas:** IP, Serie, PS2 o USB.
*   **Cantidad permitida:** Mínimo 1, máximo 2 activas.
*   **Lógica de operación:** El sistema debe permitir al usuario configurar el **momento de la captura**:
    *   Captura a la **Entrada** (cuando el camión sube a la báscula).
    *   Captura a la **Salida** (cuando el camión abandona la estación).

---

## 5. Barreras de Tránsito
Dispositivos de control físico de acceso (abrir/cerrar). Al igual que los semáforos, operan mediante pulsos de corriente o comandos lógicos.

*   **Conexiones soportadas:** HTTP, USB, controladores lógicos (Arduino/ESP32) o conexión eléctrica directa (relé).
*   **Configuración requerida:**
    *   El sistema debe permitir configurar los comandos/acciones para **Abrir** y **Cerrar** la barrera.

---

## 6. Impresoras (Emisión de Tickets)
Dispositivos de salida para la emisión física del ticket de pesaje.

*   **Cantidad permitida:** Múltiples impresoras registradas en el sistema.
*   **Lógica de operación:**
    *   El usuario puede definir una impresora por defecto.
    *   El sistema **solo envía el documento (PDF)** del ticket generado. La impresora (o su driver) se encarga del renderizado final y la impresión física.

---

## 7. Matriz de Reglas de Negocio (Vinculación Entrada/Salida)

Para garantizar la operatividad de la estación con cualquier cantidad de hardware disponible, el sistema debe aplicar las siguientes reglas de auto-configuración para los flujos de **Entrada** y **Salida**:

| Escenario de Hardware          | Configuración Requerida en el Sistema                                                                                           |
|:-------------------------------|:--------------------------------------------------------------------------------------------------------------------------------|
| **1 Báscula + 1 Indicador**    | El único indicador y la única báscula se configuran para operar tanto en la **Entrada** como en la **Salida** automáticamente.  |
| **2 Básculas + 1 Indicador**   | El indicador se vincula a ambas básculas. Debe mostrar dinámicamente el valor de la báscula que esté en uso (Entrada o Salida). |
| **1 Báscula + 2 Indicadores**  | La única báscula se vincula a ambos indicadores, enviando el mismo peso a los dos simultáneamente, sin importar el modo.        |
| **2 Básculas + 2 Indicadores** | Vinculación directa y exclusiva: *Báscula de Entrada → Indicador de Entrada* y *Báscula de Salida → Indicador de Salida*.       |
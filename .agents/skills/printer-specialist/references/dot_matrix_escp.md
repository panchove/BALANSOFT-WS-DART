# IMPRESORAS MATRICIALES (ESC/P, EPSON LX-350 / FX-890) Y FORMULARIO CONTINUO

Guía técnica para la emisión de boletos de pesaje en papel químico autocopiante (original + 2 copias carbón) mediante impresoras matriciales de impacto.

---

## 1. Características del Entorno de Pesaje con Matriciales

- **Robustez contra polvo y vibración:** En tolvas de áridos, cementeras y canteras, las impresoras térmicas se desgastan rápido por polvo abrasivo. Las matriciales de 9 agujas (como la EPSON LX-350) son el estándar indiscutible.
- **Validez Legal de la Copia Carbón:** El impacto físico de las agujas atraviesa el papel químico dejando copias idénticas e inalterables para el chofer, la empresa de transporte y el archivo fiscal.

---

## 2. Comandos Principales Epson ESC/P y ESC/P2

| Comando | Hex | Significado | Uso en BALANSOFT-WS |
|---|---|---|---|
| `ESC @` | `1B 40` | Reset / Inicializar | Limpia parámetros previos y coloca la cabeza en inicio. |
| `ESC P` | `1B 50` | 10 CPI (Pica) | Modo normal: 80 columnas en ancho de 8 pulgadas. |
| `ESC M` | `1B 4D` | 12 CPI (Elite) | 96 columnas en 8 pulgadas. |
| `ESC SI` | `0F` | Comprimido (17 CPI) | 136 columnas en 8 pulgadas. Ideal para tablas anchas. |
| `ESC x 0` | `1B 78 00` | Modo Draft (Borrador) | Impresión de ultra-alta velocidad (347 caracteres/segundo). |
| `ESC E` | `1B 45` | Negrita activada | Resalta títulos y números de boleto. |
| `ESC F` | `1B 46` | Negrita cancelada | Regresa al texto estándar. |
| `ESC C n` | `1B 43 n` | Longitud de página en líneas | `n=33`: Media Carta (5.5 pulgadas a 6 LPI). `n=66`: Carta completa. |
| `ESC 2` | `1B 32` | Espaciado de línea 1/6 pulgada | 6 líneas por pulgada (LPI estándar). |
| `ESC 0` | `1B 30` | Espaciado de línea 1/8 pulgada | 8 líneas por pulgada (compacto). |

---

## 3. Manejo de Formulario Continuo (Media Carta / 5.5")

Un error muy común es emitir un `Form Feed` (`FF` / `\x0C`) que avanza 11 pulgadas completas, desperdiciando la mitad de la hoja de formulario continuo:

- **Estrategia BALANSOFT-WS:**
  1. Al inicio del ticket se envía `ESC C 33` fijando la página a 33 líneas (media carta).
  2. Al terminar la impresión se envía `FF` (`\x0C`): la impresora avanza automáticamente y con precisión milimétrica hasta la perforación de la siguiente media página.
  3. No se requieren saltos de línea manuales redundantes.

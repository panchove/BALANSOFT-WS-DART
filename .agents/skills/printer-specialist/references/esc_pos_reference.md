# REFERENCIA DE COMANDOS ESC/POS PARA IMPRESORAS TÉRMICAS

Esta guía contiene la tabla de secuencias de escape estándar ESC/POS utilizadas en las impresoras térmicas de 80 mm (POS-80) y 58 mm (POS-58) en BALANSOFT-WS.

---

## 1. Comandos Principales de Control

| Función | Hex | ASCII | Descripción |
|---|---|---|---|
| **Inicializar** | `1B 40` | `ESC @` | Restablece fuentes, márgenes y modos a los valores predeterminados de hardware. Siempre enviar al inicio de un ticket. |
| **Alineación** | `1B 61 n` | `ESC a n` | `n=0`: Izquierda (Left), `n=1`: Centro (Center), `n=2`: Derecha (Right). |
| **Negrita (Bold)** | `1B 45 n` | `ESC E n` | `n=1`: Activa negrita, `n=0`: Desactiva negrita. |
| **Subrayado** | `1B 2D n` | `ESC - n` | `n=1`: 1 punto grosor, `n=2`: 2 puntos grosor, `n=0`: Desactivado. |
| **Tamaño de Fuente** | `1D 21 n` | `GS ! n` | Doble ancho y doble alto combinados. `n=0x00`: Normal, `n=0x11`: Doble alto y doble ancho. |
| **Avanzar Papel** | `1B 64 n` | `ESC d n` | Imprime el buffer y avanza `n` líneas de papel. |
| **Corte Parcial** | `1D 56 01` | `GS V 1` | Ejecuta corte de papel dejando un pequeño punto de unión. |
| **Corte con Avance**| `1D 56 41 n` | `GS V 'A' n` | Avanza `n` puntos y ejecuta corte completo (`n=0` o `n=3`). |

---

## 2. Códigos de Barras y Códigos QR

### Código de Barras (Code 128)
```text
GS w 2       (Ancho de barra = 2 puntos)
GS h 60      (Altura de código = 60 puntos)
GS H 2       (Texto numérico debajo del código)
GS k 73 <len> <datos>  (CODE128)
```

### Código QR en Modelo 2 (GS ( k)
1. Tipo de modelo: `\x1D\x28\x6B\x04\x00\x31\x41\x32\x00`
2. Tamaño de módulo (dot size = 4): `\x1D\x28\x6B\x03\x00\x31\x43\x04`
3. Nivel de corrección de error (M = 15%): `\x1D\x28\x6B\x03\x00\x31\x45\x31`
4. Almacenar datos: `\x1D\x28\x6B <pL> <pH> \x31\x50\x30 <data>`
5. Imprimir QR almacenado: `\x1D\x28\x6B\x03\x00\x31\x51\x30`

---

## 3. Manejo de Caracteres en Español (Latin-1 / CP850 / CP437)

Para evitar la corrupción de tildes y caracteres especiales (`Ñ`, `ñ`, `Á`, `É`, `Í`, `Ó`, `Ú`, `°`):
- Seleccionar la tabla de caracteres correcta mediante:
  `ESC t 2` (CP850 Multilingual) o `ESC t 16` (Windows-1252 Latin-1).
- Codificar siempre el stream de salida en `latin-1` o `cp850`.

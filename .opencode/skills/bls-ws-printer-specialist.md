---
name: printer-specialist
description: Formateo, spooling e impresión física de tickets industriales en BALANSOFT-WS para impresoras térmicas ESC/POS (80mm/58mm) y matriciales de impacto ESC/P (Epson LX-350 / FX-890) con paridad de tabla canónica.
---

# Printer Specialist Skill — BALANSOFT-WS

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 42001 / ISO/IEC 17025
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


## Modos de Impresión Industriales

1. **Impresoras Térmicas (ESC/POS 80mm / 58mm)**:
   - Emisión de tickets estándar con comandos de corte de papel, negrita, alineación y códigos QR/Barcode según ISO/IEC 18004 e ISO/IEC 15417.
2. **Impresoras Matriciales de Impacto (ESC/P 9-pines: Epson LX-350, FX-890, OKI Microline)**:
   - Manejo de papel continuo y copias químicas carbón.
   - Envío de texto monoespaciado puro sin drivers gráficos de Windows/Linux para máxima velocidad y nitidez en ambiente industrial hostil.
   - Longitud de página configurada vía secuencias ESC/P (`ESC C \x1E` para media carta / 30 líneas).
3. **Generación PDF y Vista Previa en Pantalla**:
   - Mantiene paridad visual 1:1 con el ticket físico.

## Tabla Canónica de 5 Columnas (v3.24)

Todo ticket debe presentar la matriz canónica estandarizada:
```
+-----------------------------------------------------------------------+
|  ETIQUETA  |   FECHA / HORA    |  CAMIÓN  |  REMOLQUE  |     TOTAL    |
+------------+-------------------+----------+------------+--------------+
| ENTRADA    | 19/10/2026 08:30  | 14.250   |   8.300    |   22.550 kg  |
| SALIDA     | 19/10/2026 09:45  |  6.100   |   3.400    |    9.500 kg  |
| NETO       |                   |  8.150   |   4.900    |   13.050 kg  |
| GUÍA       |                   |          |            |   13.000 kg  |
| DIFERENCIA |                   |          |            |      +50 kg  |
+-----------------------------------------------------------------------+
```

## Herramientas MCP Disponibles

- **`format_ticket_weights_table`**: Genera la representación canónica en texto plano verificada para impresión antes del envío a puerto serie o spooler.
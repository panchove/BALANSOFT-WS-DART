# REGLA DE PARIDAD DE LAYOUT DE TICKETS (FLUTTER ↔ BACKEND)

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 25010 / ISO/IEC 17025
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


En BALANSOFT-WS el boleto de pesaje impreso (PDF/TXT) debe coincidir milimétricamente con la vista previa que el operador ve en pantalla antes de imprimir.

## 1. Fuente de Verdad
- **El layout canónico reside en Flutter:**
  `frontend/lib/presentation/widgets/ticket_preview_dialog.dart`
- Cualquier cambio estructural (nuevos campos, orden de filas, etiquetas, firmas) debe implementarse **primero** en Flutter y **luego** reflejarse exactamente en:
  `backend/app/services/ticket_service.py`

## 2. La Tabla LECTURA DE PESOS (Especificación v3.24)
La tabla de pesos es **ÚNICA** para los tres formatos: rollo térmico (80mm/58mm), hoja suelta (media carta/Carta/A4) y TXT matricial:

- **5 Columnas fijas:**
  `[ (etiqueta) | Fec, Hrs | CAMIÓN | REMOLQUE | TOTAL ]`
- **Fila 1 (ENTRADA):**
  - Columna 1: `ENTRADA:`
  - Columna 2: `dd/mm/aaaa – HH:MM` (guion medio U+2013)
  - Columna 3: Kilos entrada camión (o vacío si no aplica)
  - Columna 4: Kilos entrada remolque (o vacío si no aplica)
  - Columna 5: Kilos totales de entrada
- **Fila 2 (SALIDA, solo si el boleto ya completó pesaje de salida):**
  - Columna 1: `SALIDA:`
  - Columna 2: `dd/mm/aaaa – HH:MM`
  - Columna 3: Kilos salida camión
  - Columna 4: Kilos salida remolque
  - Columna 5: Kilos totales de salida
- **Fila 3 (TOTALES, solo si hay salida):**
  - Columna 1: `TOTALES:`
  - Columna 2: Vacía
  - Columna 3: Neto camión (`abs(pe_c - ps_c)`)
  - Columna 4: Neto remolque (`abs(pe_r - ps_r)`)
  - Columna 5: Neto total (`abs(pe_tot - ps_tot)`)
- **Fila 4 (PESO NETO, final):**
  - Columna 1: `PESO NETO:`
  - Columna 2: Valor neto total (`10.000,00 kg`)
  - Columna 3: Sufijo de operación: `(INGRESO)` o `(DESPACHO)`
  - Columnas 4 y 5: Vacías

## 3. Comportamiento Responsive y Auto-Ajuste
- En ReportLab (PDF), el cálculo de anchos de columna utiliza `_REQUIERE_TABLA_PESOS` y `_RATIOS_TABLA_PESOS`.
- Un boleto anulado siempre lleva la marca de agua diagonal `ANULADO` en rojo (`ROJO_ANULADO = #C53030`).
- En impresión térmica de 58mm o 80mm, el tamaño tipográfico se ajusta uniformemente (`_tamano_tabla_pesos()`) para las 5 columnas, evitando saltos de línea antiestéticos.
---
name: printer-specialist
description: >-
  Especialista en impresoras industriales (térmicas ESC/POS, matriciales de impacto ESC/P formulario continuo,
  PDF ReportLab y spooler de tickets) para BALANSOFT-WS. Usar para formatos de boleto de pesaje, comandos de impresión
  directa, sincronización estricta entre Flutter y backend, y corte/copias de tickets.
---

# Printer Specialist Skill — BALANSOFT-WS

Guía integral para la generación, renderizado y spooling de tickets de pesaje en impresoras térmicas de punto de venta (POS), matriciales de formulario continuo con copias carbón y formatos en hoja suelta (ReportLab PDF).

## 1. Regla de Paridad Flutter ↔ Backend

- **Fuente Canónica:** `frontend/lib/presentation/widgets/ticket_preview_dialog.dart`.
- **Backend Generator:** `backend/app/services/ticket_service.py`.
- **Estructura fija del boleto:**
  1. `DATOS GENERALES` (Nº Boleto, Empresa, Placa, Remolque, Chofer, Producto, Almacén, Transportista).
  2. `LECTURA DE PESOS` (Tabla de 5 columnas idéntica en los tres formatos).
  3. `DATOS DE CONTROL` (Peso Declarado, Diferencia, Desviación %).
  4. `OBSERVACIONES Y FIRMAS` (Operador, Conductor).

## 2. Tipos de Impresoras Soportadas

| Tipo de Impresora | Protocolo / Lenguaje | Ancho / Formato | Conexión Típica | Particularidades |
|---|---|---|---|---|
| **Térmica 80mm** (POS-80) | ESC/POS estándar | 80 mm (48 columnas texto normal) | USB `/dev/usb/lp0` o Red TCP 9100 | Corte con `GS V \x41 \x00` tras 4 líneas en blanco. Fuente compacta. |
| **Térmica 58mm** (POS-58) | ESC/POS estándar | 58 mm (32 columnas texto normal) | USB o Bluetooth SPP | Rejilla comprimida a 4.5 pt. Auto-ajuste para evitar desbordes. |
| **Matricial de Impacto** | Epson ESC/P y ESC/P2 | Formulario continuo (Media Carta o Carta) | USB `/dev/usb/lp*` o Paralelo LPT1 | Tractor feed, copias autocopiantes (1 original + 2 copias). Impresión rápida en modo Draft 10/12 CPI sin gráficos. |
| **Láser / Tinta** | PDF / Spooler SO | Media Carta, Carta (Letter), A4 | Driver de SO / Red | Generación con ReportLab, escala tipográfica adaptativa, marca de agua si está `ANULADO`. |

*Ver detalles en [esc_pos_reference.md](./references/esc_pos_reference.md) y [dot_matrix_escp.md](./references/dot_matrix_escp.md).*

## 3. La Tabla LECTURA DE PESOS (5 Columnas)

Especificación canónica v3.24:
```text
==============================================================================
             | Fec, Hrs           | CAMIÓN       | REMOLQUE     | TOTAL       
------------------------------------------------------------------------------
ENTRADA:     | 15/10/2026 – 08:30 | 12.345,67 kg |  8.000,00 kg | 20.345,67 kg
SALIDA:      | 15/10/2026 – 09:15 |  4.200,00 kg |  3.100,00 kg |  7.300,00 kg
TOTALES:     |                    |  8.145,67 kg |  4.900,00 kg | 13.045,67 kg
------------------------------------------------------------------------------
PESO NETO:   | 13.045,67 kg       | (INGRESO)    |              |             
==============================================================================
```
- La columna `REMOLQUE` queda vacía si el camión no lleva remolque.
- La fila `SALIDA:` y `TOTALES:` solo se imprimen cuando el boleto tiene pesaje de salida (`fecha_hora_salida` no es null).
- En tickets pendientes de salida, solo se imprime la fila `ENTRADA:`.

## 4. Scripts y Utilidades

- **Previsualizar ticket en formato TXT matricial:**
  [preview_txt_ticket.py](./scripts/preview_txt_ticket.py)
  ```bash
  backend/.venv/bin/python .agents/skills/printer-specialist/scripts/preview_txt_ticket.py --boleto-id <uuid>
  ```
- **Inspeccionar y decodificar secuencias ESC/POS binarias:**
  [inspect_escpos.py](./scripts/inspect_escpos.py)
  ```bash
  backend/.venv/bin/python .agents/skills/printer-specialist/scripts/inspect_escpos.py /tmp/ticket.bin
  ```

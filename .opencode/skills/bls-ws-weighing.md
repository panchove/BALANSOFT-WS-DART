---
name: weighing
description: Orquestador maestro del flujo de pesaje industrial en BALANSOFT-WS. Coordinación entre captura de hardware, transacciones de camiones (tara, bruto, neto), Kardex y emisión de boletos.
---

# Master Weighing Workflow — BALANSOFT-WS

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 42001 / ISO/IEC 17025 / OIML R 76-1
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


## 1. Invariantes Metrológicas y de Negocio

1. **Inmutabilidad de la Lectura**: El peso capturado del hardware nunca se altera directamente. Si se requiere ajuste, se registra el valor original y el valor corregido en auditoría.
2. **Ciclo de Estados del Boleto**:
   `PENDIENTE` -> `CERRADO` / `MODIFICADO` -> `ANULADO`.
   No se permiten saltos arbitrarios de estado.
3. **Unicidad de Camión en Patio**: Un mismo camión no puede tener dos boletos simultáneos en estado `PENDIENTE`.
4. **Impacto en Kardex**:
   - **Ingreso / Recepción (Kardex 10)**: Pesaje Inicial (Bruto) -> Pesaje Final (Tara) -> Neto = Bruto - Tara.
   - **Despacho / Salida (Kardex 60)**: Pesaje Inicial (Tara) -> Pesaje Final (Bruto) -> Neto = Bruto - Tara.
   - **Anulación**: Genera asiento inverso de contra-valor para revertir saldo.
5. **Series de Numeración**: Asignación atómica protegida con `FOR UPDATE` para garantizar secuencias estrictamente consecutivas sin saltos ni duplicados.

## 2. Comandos de Verificación Rápida

- **Tests de básculas y parser en backend:**
  ```bash
  cd src/backend && uv run pytest tests/test_scale_parser.py tests/test_scale_hal.py -v
  ```
- **Tests de integración de flujo de pesaje en frontend:**
  ```bash
  cd src/frontend && flutter test test/unit/weighing_test.dart test/unit/kardex_bloc_test.dart
  ```
- **Herramientas de simulación MCP:**
  Usar `simulate_scale_frame`, `parse_scale_frame` y `calculate_truck_weights` desde el servidor MCP `balansoft-hardware`.
---
name: truck-weighing-system
description: >-
  Especialista en camiones, pesos y reglas del negocio de pesaje industrial para BALANSOFT-WS.
  Usar para vehículos pesados (chuto, semirremolque, b-tren, rígido), ciclos de pesaje (entrada/salida, recepción/despacho),
  tara fija vs pesada, pesaje por ejes, control de sobrecarga, Kardex 10/60, tolerancias y mermas.
---

# Truck Weighing System Skill — BALANSOFT-WS

Guía integral del dominio de transporte pesado, tipologías de camiones, dinámica de pesaje en básculas puente camioneras y contabilidad de inventarios (Kardex).

## 1. Tipologías de Vehículos de Carga y Ejes

En transporte industrial los vehículos se clasifican por su configuración de chasis y número de ejes:

| Configuración | Denominación Común | Ejes | Capacidad Bruta Típica | Esquema |
|---|---|---|---|---|
| **C2** | Camión Rígido 2 Ejes | 2 (1 simple + 1 motriz) | 16.000 – 18.000 kg | O ——— O |
| **C3** | Doble Troque / Volquete | 3 (1 simple + tándem motriz) | 24.000 – 28.000 kg | O ——— OO |
| **C4** | Cuatro Manos | 4 (2 direccionales + tándem) | 30.000 – 32.000 kg | OO ——— OO |
| **T3-S2** | Chuto 3 Ejes + Batea 2 Ejes | 5 (1 + tándem + tándem remolque) | 40.000 – 44.000 kg | O —— OO —— OO |
| **T3-S3** | Chuto 3 Ejes + Batea 3 Ejes | 6 (1 + tándem + trídem remolque) | 48.000 – 52.000 kg | O —— OO —— OOO |
| **B-Tren** | Bitrén / Doble Remolque | 7 a 9 ejes | Hasta 60.000 – 75.000 kg | O —— OO —— OO —— OO |

*Ver límites de peso por eje y normativa vial en [truck_configurations_and_axles.md](./references/truck_configurations_and_axles.md).*

## 2. El Ciclo de Doble Pesada en Estación Camionera

Todo pesaje industrial consta de dos capturas físicas separadas en el tiempo:

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    CICLO DE PESAJE                          │
  ├──────────────────────────────┬──────────────────────────────┤
  │       RECEPCIÓN (COMPRA)     │      DESPACHO (VENTA)        │
  ├──────────────────────────────┼──────────────────────────────┤
  │ 1. ENTRADA = PESO BRUTO      │ 1. ENTRADA = TARA (Vacío)    │
  │    (Camión cargado)          │                              │
  │ 2. Descarga en silo/almacén  │ 2. Carga en tolva/almacén    │
  │ 3. SALIDA  = TARA (Vacío)    │ 3. SALIDA  = PESO BRUTO      │
  │                              │    (Camión lleno)            │
  ├──────────────────────────────┴──────────────────────────────┤
  │ NETO TOTAL = | TOTAL ENTRADA - TOTAL SALIDA |               │
  │ Desglose independiente:                                     │
  │   - Neto Camión   = | Entrada Camión - Salida Camión |      │
  │   - Neto Remolque = | Entrada Remolque - Salida Remolque |  │
  └─────────────────────────────────────────────────────────────┘
```

*Ver detalle metrológico en [weighing_cycle_and_invariants.md](./references/weighing_cycle_and_invariants.md).*

## 3. Integración con Kardex e Inventario Físico

- **Operación ID 10 (INGRESO):** Aumenta stock (+cantidad). Asentado en RECEPCIÓN de carga.
- **Operación ID 60 (DESPACHO):** Disminuye stock (-cantidad). Asentado en VENTA o traslado de salida.
- **Anulación y Reversión:**
  - Al anular un boleto `CERRADO`, se crea un registro de reversión en `kardex` con el signo exactamente opuesto.
  - El boleto pasa a estado `ANULADO`, preservando la auditoría completa.
- Ver [kardex_and_inventory.md](./references/kardex_and_inventory.md).

## 4. Concurrencia de Series de Numeración

- La numeración oficial del boleto (`TA-00000001`) se asigna mediante `SELECT ... FOR UPDATE` sobre la tabla `series_numeracion` para evitar saltos o números duplicados cuando varios operadores trabajan al mismo tiempo.
- Ver [series_locking_and_concurrency.md](./references/series_locking_and_concurrency.md).

## 5. Scripts y Herramientas

- **Calculadora y validador de pesos de camión:**
  [truck_weight_calculator.py](./scripts/truck_weight_calculator.py)
  ```bash
  backend/.venv/bin/python .agents/skills/truck-weighing-system/scripts/truck_weight_calculator.py \
    --pe-camion 12500 --ps-camion 4200 \
    --pe-remolque 8500 --ps-remolque 3100 \
    --operacion RECEPCION --declarado 13650
  ```

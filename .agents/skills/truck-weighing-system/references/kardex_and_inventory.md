# INTEGRACIÓN CON KARDEX E INVENTARIO FÍSICO DE PLANTA

Mapeo entre las operaciones de pesaje en báscula y los movimientos contables/físicos en almacenes.

---

## 1. Tipos de Movimiento de Kardex

En la tabla `kardex` de BALANSOFT-WS:
- `id_tipo_movimiento = 10` (**INGRESO**):
  - Corresponde a Recepción de Materia Prima / Compras.
  - El peso neto capturado entra con **signo positivo (+)**.
  - Aumenta las existencias en el `id_almacen` asociado al `id_producto`.
- `id_tipo_movimiento = 60` (**DESPACHO**):
  - Corresponde a Venta a Clientes / Despacho de Producto Terminado.
  - El peso neto capturado sale con **signo negativo (-)**.
  - Disminuye las existencias en el `id_almacen`.

---

## 2. Reversión Automática en Anulaciones

Cuando un boleto `CERRADO` es anulado:
1. No se borra la fila original de `kardex` (regla de auditoría fiscal).
2. Se inserta un **nuevo registro de contra-asiento** en `kardex`:
   - Si el movimiento original fue ID 10 (+15.000 kg), el contra-asiento se registra por -15.000 kg con descripción `"Anulación boleto TA-00000001"`.
   - Si fue ID 60 (-15.000 kg), el contra-asiento se registra por +15.000 kg.
3. El saldo final del almacén queda matemáticamente restituido sin alterar los saldos históricos de auditoría.

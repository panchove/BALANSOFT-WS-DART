---
name: kardex
description: Gestión de inventario y Kardex de BALANSOFT-WS. Usar para movimientos de inventario, entradas, salidas, anulaciones y reversión automática.
---

# BALANSOFT-WS Kardex Skill

## Principio

El Kardex debe representar el historial contable/operativo del inventario.

## Regla principal

No eliminar movimientos históricos para corregir una operación.

Preferir movimientos de reversión.

## Anulación

Cuando se anula un documento cerrado que produjo inventario:

1. localizar movimientos originales;
2. validar que sean reversibles;
3. generar movimientos inversos;
4. registrar referencia al documento original;
5. ejecutar todo dentro de una transacción.

## Movimientos

El sistema utiliza tipos existentes del proyecto.

Cuando se utilicen:

10 = entrada

60 = salida

NO asumir que estos códigos significan lo mismo en todos los contextos sin revisar la implementación existente.

## Idempotencia

La reversión debe ser idempotente.

No generar dos reversiones para una misma anulación.

## Auditoría

La reversión debe conservar referencia hacia:

- documento original;
- movimiento original;
- usuario;
- fecha;
- motivo.

## Transacciones

Documento + Kardex + reversión + auditoría deben permanecer consistentes.

Si falla una parte crítica:

rollback.

## Inventario

No confiar en balances enviados desde Flutter.

El backend debe determinar el resultado correcto.

## Testing

Probar:

- entrada;
- salida;
- anulación;
- reversión;
- doble anulación;
- inventario insuficiente cuando aplique;
- rollback.
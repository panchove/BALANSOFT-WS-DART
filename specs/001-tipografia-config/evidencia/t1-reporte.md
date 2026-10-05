# T1 `[GATE]` — Reporte de medición de desbordes a `textScaler` 1.40

| Campo | Valor |
|-------|-------|
| **Tarea** | T1 (SPIKE, descartable) |
| **Factor medido** | **1.40** |
| **`overflow_count`** | **0** |
| **Pantallas medidas** | **4 de 4** |
| **Criterio de salida** | ✅ `== 0` → T1 pasa; rango [0.85, 1.40] ratificado |

## Comando

```
cd backend && bash scripts/e2e_flutter.sh up
cd frontend && DISPLAY=:0 flutter test integration_test/t1_overflow_spike_test.dart -d linux
```

## Salida del spike

```
[T1] textScaler efectivo = 1.4
[T1] diálogo de confirmación de guardado: true
[T1] diálogo de impresión: true
[T1] boleto pendiente de salida: true
=== T1 REPORTE ===
factor_medido: 1.4
pantallas_alcanzadas: login, panel_principal, panel_principal, ajustes,
                      formulario_pesaje, detalle_boleto, detalle_boleto
pantallas_no_alcanzadas:
overflow_count: 0
=== FIN T1 ===
```

## Las 4 pantallas críticas de REQ-FN-008

| Pantalla | Alcanzada | Desbordes |
|----------|:----------:|:---------:|
| Formulario de pesaje | ✅ | 0 |
| Detalle del boleto | ✅ | 0 |
| Panel principal | ✅ | 0 |
| Pantalla de ajustes | ✅ | 0 |

## Incidencias durante la medición

Ninguna de desbordes. Se corrigieron dos defectos **del propio spike**, no de la app:

1. **Factor equivocado**: la constante ya valía `1.40`, pero la cabecera y el nombre
   del test decían `1.50`. El entregable se reportaba con un factor que no se
   medía.
2. **`detalle_boleto` sin medir** (3 de 4 pantallas): el spike cerraba la entrada y
   buscaba la fila del boleto en ENTRADAS, pero un boleto recién cerrado vive en
   SALIDAS (`weighing_list_screen.dart` se abre con `estadoInicial: 'CERRADO'`
   desde `home_shell.dart:85`). Se añadió el cierre completo (entrada + salida) y
   la búsqueda en los dos listados.

Ambos fallos habrían producido un `overflow_count` de 0 **falso**: el primero
reportaba un factor no medido, y el segundo-certificaba menos pantallas de las
exigidas. Ninguno era un defecto de BALANSOFT-WS.

## Nota

El spike **no se commitea** (`tasks.md §1`, punto 5). Este reporte es el
entregable.

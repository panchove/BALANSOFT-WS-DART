# CONCURRENCIA TRANSACCIONAL Y BLOQUEO EN SERIES DE NUMERACIÓN

Cómo BALANSOFT-WS garantiza números de boleto consecutivos y sin colisiones en entornos de pesaje multi-operador y multi-estación.

---

## 1. El Problema de la Numeración Concurrente

Si dos operadores confirman la entrada de un camión en el mismo milisegundo:
- Una lectura simple `SELECT ultimo_numero FROM series_numeracion` haría que ambos obtuvieran el mismo número (ej: `TA-00000005`).
- Uno de los dos fallaría por violación de unicidad (`unique constraint`), o peor aún, se crearía un duplicado.

---

## 2. La Solución: Bloqueo Pesimista `FOR UPDATE`

En `backend/app/api/v1/endpoints/series.py` y `weighing_service.py`:

```python
stmt = (
    select(SerieNumeracion)
    .where(
        SerieNumeracion.id_serie == id_serie,
        SerieNumeracion.id_empresa == id_empresa,
    )
    .with_for_update()  # <-- Bloqueo pesimista a nivel de fila
)
serie = (await db.execute(stmt)).scalar_one()

siguiente_contador = serie.ultimo_numero + 1
serie.ultimo_numero = siguiente_contador

# Formatear número con prefijo y dígitos configurados
numero_boleto = f"{serie.prefijo}-{siguiente_contador:0{serie.longitud_digitos}d}"
```

### Garantías:
- La base de datos bloquea la fila de la serie hasta que el commit se completa.
- La segunda transacción espera milisegundos en la cola y recibe el siguiente número correlativo sin saltos ni bloqueos muertos.

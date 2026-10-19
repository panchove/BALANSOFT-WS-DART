# GRAMÁTICA DE TRAMAS, PARSEO Y CHECKSUMS EN PESAJE INDUSTRIAL

Documentación matemática y algorítmica del parser de BALANSOFT-WS (`app/core/scale_parser.py`).

---

## 1. Principio Anti-Falso-Positivo

En pesaje de pesados (camiones de hasta 80.000 kg), fijar un valor erróneo a un boleto acarrea consecuencias legales y financieras graves. Por tanto:

1. **Un número desnudo NO es un peso:**
   - La cadena `1234567890` o `01` carece de contexto semántico.
   - Para que un token sea considerado candidato a peso, debe poseer al menos uno de los siguientes atributos:
     - **Signo explícito:** `+` o `-` (incluso precedido de espacio como `-  12.50`).
     - **Punto decimal:** un valor con parte fraccionaria (ej: `320.00`).
     - **Unidad de masa adherida o separada:** `kg`, `kgs`, `lb`, `lbs`, `ton`, `tons`, `t`, `g`.
2. **Ambigüedad = Rechazo Inmediato:**
   - Si una línea contiene múltiples números que no coinciden (ej: `123.4 567.8`), la función retorna `(None, None, 'ambiguo')`.
   - Es preferible perder un cuadro de lectura y esperar al siguiente en la ráfaga continua que registrar una cifra espuria.

---

## 2. Algoritmo de Checksum XOR (Toledo / Keli)

El checksum se calcula aplicando la operación binaria XOR a cada byte del payload entre `STX` (0x02) y `ETX` (0x03):

```python
def calcular_checksum_xor(payload: str) -> str:
    xor_val = 0
    for b in payload.encode("latin-1", errors="ignore"):
        xor_val ^= b
    return f"{xor_val:02X}"
```

### Ejemplo de Verificación:
- Trama recibida: `\x02ST,GS,+00320.00kg\x032B`
- Payload: `ST,GS,+00320.00kg`
- Bytes: `[0x53, 0x54, 0x2C, 0x47, 0x53, 0x2C, 0x2B, 0x30, 0x30, 0x33, 0x32, 0x30, 0x2E, 0x30, 0x30, 0x6B, 0x67]`
- XOR acumulado = `0x2B`
- Checksum recibido tras ETX = `2B`
- Coincidencia exacta: trama aceptada.

---

## 3. Delimitadores de Trama Soportados

| Delimitador | Byte(s) Hex | Indicadores que lo utilizan |
|---|---|---|
| `lf` | `0x0A` (`\n`) | Estándar por defecto Linux, microcontroladores y TCP |
| `cr` | `0x0D` (`\r`) | Indicadores seriales antiguos (Yaohua, Rice Lake) |
| `crlf` | `0x0D 0x0A` (`\r\n`) | Toledo, Torrey, emuladores Windows |
| `stx_etx` | `0x03` (`ETX`) | Keli, Toledo con enmarcado STX/ETX |

En `scale_hal.py`, la lectura se realiza con `readuntil(delimitador)` y se limpian caracteres de control residuales antes del parseo numérico.

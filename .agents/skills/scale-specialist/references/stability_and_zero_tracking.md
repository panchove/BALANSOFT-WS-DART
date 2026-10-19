# DETECCIÓN DE ESTABILIDAD, ZERO TRACKING Y TOLERANCIAS DE CAPACIDAD

Reglas metrológicas de pesaje en BALANSOFT-WS para garantizar la captura de pesos reales sin perturbaciones mecánicas o viento.

---

## 1. Detección de Estabilidad

Un camión sobre la plataforma puede oscilar por amortiguadores, viento o frenado. El sistema debe asegurar que el peso está quieto antes de confirmar el pesaje.

### Caso A: El Indicador Emite Token de Estado
Protocolos como Toledo, Torrey y Keli incluyen banderas en la trama:
- `ST` (Stable): Peso en reposo metrológico. Se marca `estable=True`.
- `US` (Unstable / Motion): La plataforma se está moviendo. Se marca `estable=False`.
- `OL` (Overload): El peso excede la capacidad física de las celdas de carga. La lectura se rechaza (`motivo='sobrecarga'`).

### Caso B: El Indicador No Emite Token (Yaohua `=`, Rice Lake `01+`, MT-SICS)
Cuando la trama no contiene token (`estado=None`):
1. La sesión acumula una ventana deslizante de las últimas $N$ muestras (típicamente 5 lecturas a 5–10 Hz).
2. Se evalúa la dispersión máxima entre las lecturas:
   $$\Delta_{\text{peso}} = \max(W_1 \dots W_n) - \min(W_1 \dots W_n)$$
3. Si $\Delta_{\text{peso}} \le \text{TOLERANCIA\_VARIACION}$ (ej: 5.0 kg en báscula de 60t), la lectura se clasifica como `estable=True`.
4. Si la diferencia excede el margen, se considera en movimiento (`estable=False`).

---

## 2. Límites de Capacidad Máxima

Para proteger la integridad del sistema contra valores anómalos o descalibración:
- `capacidad_max` se define por báscula en la tabla `balanzas` (ej: 60.000 kg).
- `TOLERANCIA_CAPACIDAD = 1.05` (5% de sobrecapacidad admisible antes de rechazo estricto).
- Si el peso parseado supera `capacidad_max * 1.05`, la función `parse_weight_frame` devuelve `(None, None, 'sobre_capacidad')`.

---

## 3. Seguimiento de Cero (Zero Tracking / Center of Zero)

- Todo indicador industrial dispone de una banda de seguimiento automático de cero (Auto Zero Tracking, AZT) típicamente entre $\pm 0.5 d$ y $\pm 3 d$ divisiones de escala (en camiones, $1d = 10\text{ kg}$).
- En BALANSOFT-WS, pesos entre $-10\text{ kg}$ y $+10\text{ kg}$ corresponden a plataforma vacía.
- La báscula nunca debe permitir registrar un boleto de camión con peso neto igual o inferior a 0 kg.

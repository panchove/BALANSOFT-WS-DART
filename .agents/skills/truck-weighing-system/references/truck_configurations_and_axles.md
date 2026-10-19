# CONFIGURACIONES DE CAMIONES, EJES Y LÍMITES DE PESO VIAL

Guía técnica sobre distribución de cargas por eje y límites máximos según la normativa de transporte terrestre industrial (MTC / COVENIN 2402 / Ley de Cargas).

---

## 1. Tipos de Ejes en Vehículos de Carga

1. **Eje Simple Direccional (1 eje, 2 neumáticos):**
   - Rueda en el tren delantero del camión o chuto.
   - Límite de carga típico: **6.000 kg (6t)** a **7.000 kg (7t)**.
2. **Eje Simple No Direccional (1 eje, 4 neumáticos / dual):**
   - Límite de carga típico: **10.000 kg (10t)** a **11.000 kg (11t)**.
3. **Eje Tándem (Doble eje, 8 neumáticos):**
   - Tren de 2 ejes interconectados por balancín.
   - Límite de carga típico: **18.000 kg (18t)** a **22.000 kg (22t)**.
4. **Eje Trídem (Triple eje, 12 neumáticos):**
   - Tren de 3 ejes común en bateas, tolvas y cisternas pesadas.
   - Límite de carga típico: **24.000 kg (24t)** a **27.000 kg (27t)**.

---

## 2. Pesaje por Ejes (Axle Weighing) vs Báscula Puente Completa

Existen dos tipos de básculas para vehículos de carga:
- **Báscula Puente Completa (Full Platform):**
  - La plataforma mide entre 18 y 24 metros de largo.
  - El vehículo entra por completo con todos sus ejes a la vez.
  - La báscula captura directamente el Peso Bruto Total del vehículo de una sola lectura.
- **Báscula por Ejes (Axle Scale / Pesa Ejes):**
  - Plataforma corta (3 a 5 metros).
  - El camión avanza lentamente y pesa eje por eje:
    1. Eje delantero (direccional): $P_1$
    2. Eje tándem tractor (motriz): $P_2$
    3. Eje tándem/trídem del remolque: $P_3$
    4. Peso Total: $P_{\text{total}} = P_1 + P_2 + P_3$
  - Permite verificar que ningún eje sobrepase la capacidad legal de la vía para evitar multas de sobrecarga en peajes viales.

---

## 3. Desglose Camión + Remolque en BALANSOFT-WS

BALANSOFT-WS soporta el desglose físico cuando el camión lleva remolque desenganchable:
- `peso_entrada_vehiculo`: Chuto/Cabezal al entrar.
- `peso_entrada_remolque`: Semirremolque/Batea al entrar.
- `peso_salida_vehiculo`: Chuto/Cabezal al salir.
- `peso_salida_remolque`: Semirremolque/Batea al salir.
- La tabla de lectura de pesos calcula los netos independientes de cada unidad móvil:
  $$\text{Neto Camión} = |P_{\text{EC}} - P_{\text{SC}}|$$
  $$\text{Neto Remolque} = |P_{\text{ER}} - P_{\text{SR}}|$$
  $$\text{Neto Total} = \text{Neto Camión} + \text{Neto Remolque}$$

# REGLAS DE SEGURIDAD OPERATIVA E INVARIABLES DE PESAJE INDUSTRIAL

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 17025 / OIML R 76-1
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


En todo desarrollo, modificación de endpoints, pantallas o modelos de BALANSOFT-WS, estas reglas son **INVARIABLES** y de obligatorio cumplimiento:

## 1. Inmutabilidad del Peso Capturado
- **El peso leído de la báscula NUNCA se edita ni se sobrescribe.**
- Si el usuario teclea peso manual, se registra explícitamente como `es_manual=True` y se audita con su usuario responsable. Solo roles con permiso (`ADMIN`/`SUPERVISOR`) pueden autorizar pesajes manuales.
- Los campos `peso_entrada_vehiculo`, `peso_entrada_remolque`, `peso_salida_vehiculo`, `peso_salida_remolque` reflejan la verdad física del pesaje en el momento exacto.

## 2. Ciclo de Vida del Boleto de Pesaje
- Los únicos estados válidos son: `PENDIENTE -> CERRADO/MODIFICADO -> ANULADO`.
- Al crear una entrada, el boleto nace en estado `PENDIENTE`.
- **Regla anti-duplicidad**: Un camión/placa no puede tener dos boletos en estado `PENDIENTE` simultáneamente. Si se intenta abrir un nuevo pesaje para un vehículo con boleto pendiente, la API debe rechazarlo con código 400.
- Al registrar la salida, el boleto pasa a `CERRADO`.
- Una modificación de datos complementarios (conductor, producto, almacén, guía) tras el cierre pasa el boleto a `MODIFICADO`, incrementa `ediciones_count` y registra `BoletoEdicion` con el motivo obligatorio.
- Una anulación exige `motivo_anulacion`, pasa el estado a `ANULADO`, libera el vehículo y registra la auditoría correspondiente.

## 3. Integración con Kardex e Inventario Físico
- Movimiento ID `10`: **INGRESO** (Recepción de materia prima / compras). Signo positivo (+), incrementa las existencias en el almacén del producto.
- Movimiento ID `60`: **DESPACHO** (Venta / Despacho a clientes). Signo negativo (-), descuenta las existencias en el almacén.
- **Regla de Anulación**: Al anular un boleto `CERRADO`, el sistema registra de inmediato un contra-asiento en Kardex con el movimiento inverso exacto (`-neto` si era ingreso, `+neto` si era despacho) para mantener la paridad contable/física sin borrar el historial.

## 4. Series de Numeración y Concurrencia Transaccional
- El número secuencial del boleto (`numero_boleto`, ej: `TA-00000001`) se deriva de la tabla `series_numeracion`.
- La obtención del siguiente número debe realizarse **dentro de una transacción con bloqueo pesimista** (`SELECT ... FOR UPDATE`), evitando condiciones de carrera en estaciones con múltiples operadores concurrentes.
- Un número de boleto emitido nunca se reasigna ni se reutiliza.
- No se permite borrar una serie de numeración si ya tiene boletos asociados (código 409).

## 5. Aislamiento Multi-Tenant
- Cada consulta, filtro, inserción o validación en la base de datos local y central debe incluir obligatoriamente el filtro por `id_empresa`.
- Ninguna métrica de Prometheus (`/metrics`) ni log público debe exponer el `id_empresa` o datos sensibles de clientes.
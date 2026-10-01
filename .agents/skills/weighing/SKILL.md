---
name: weighing
description: Pesaje industrial de BALANSOFT-WS. Usar para básculas RS232, USB, TCP, lectura de peso, estabilidad, tara, bruto, neto, boletos e integración de estaciones.
---

# BALANSOFT-WS Weighing Skill

## Objetivo

Implementar pesaje industrial confiable.

## Fuentes

El sistema puede recibir peso mediante:

- RS232;
- USB;
- TCP;
- otros protocolos soportados por la infraestructura existente.

No asumir un protocolo específico sin inspeccionar el código/configuración.

## Lectura

El lector debe manejar:

- datos incompletos;
- ruido;
- caracteres inválidos;
- desconexiones;
- reconexiones;
- timeouts;
- cambios de formato.

## Peso

Separar conceptualmente:

tare
gross
net

Cuando corresponda:

net = gross - tare

No recalcular valores históricos arbitrariamente.

## Estabilidad

No considerar automáticamente cualquier lectura como válida.

Respetar el mecanismo de estabilidad configurado por el sistema.

## Tara

La tara puede ser:

- manual;
- registrada;
- asociada al vehículo;
- obtenida según el flujo existente.

No sobrescribir una tara existente sin regla explícita.

## Boleto

Un boleto debe preservar el estado del proceso.

Ejemplo conceptual:

draft
→ weighing
→ completed
→ closed
→ cancelled

No introducir estados nuevos sin revisar todo el flujo.

## Pesaje cerrado

Una vez cerrado, los valores históricos deben permanecer auditables.

## Anulación

La anulación no debe destruir información histórica.

Si produjo inventario, debe generar la reversión correspondiente.

## Offline

El pesaje debe poder registrarse localmente.

## Hardware

La capa de hardware debe estar aislada de UI y lógica empresarial.

## Testing

Probar:

- lectura válida;
- lectura corrupta;
- desconexión;
- reconexión;
- peso estable;
- tara;
- bruto;
- neto;
- cierre;
- anulación.
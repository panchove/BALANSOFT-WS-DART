```# WORKFLOW / MODEL

Como se deben mostrar los datos en el formulario

-- DATOS --
Serie - Boleto: TA-00000001            Fecha/Hora: 07/09/2026 13:00
        Camion: ALT369                   Remolque: Si/No
    Transporte: 00000001 TRANSPORTE DEMO
     Conductor: 12345678 FULANO DE TAL
      Producto: 00000001 PRODUCTO PRUEBA
       Almacen: 00000001 ALMACEN DE PRUEBA
     Seleccion: PROVEEDOR
  Razon Social: 00000001 PROVEEDOR DE PRUEBA

-- LECTURA --                          Fecha/Hora         Peso Camion  Peso Remolque    Peso Total
Balanza Entrada: BALANZA PRINCIPAL     07/09/2026 13:25    999,999.99     999,999.99    999,999.99
 Balanza Salida: BALANZA PRINCIPAL     07/09/2026 13:45    999,999.99     999,999.99    999,999.99
                                                           ---------------------------------------
                                               Peso Neto:  999,999.99     999,999.99    999,999.99
                                         Peso Declarado / Diferencia:     999,999.99    999,999.99

-- DATOS ADICIONALES --
   Documento: 12345678901234567890  Guia SUNAGRO: 12345678901234567890
   Medida: Litros             Unidades: 999,999,99     Densidad: 0,99999999  Resultado: 999,999.99

-- OBSERVACIONES --
   12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345
   12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345
   12345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345

## Operativas

  Entrada -> Dar entrada al Camion
   Salida -> Dar Salida a un camion que previamente tenga su entrada
Modificar -> Permite Modificar cualquier campo del formulario
   Anular -> Marcar como ANULADO el documento que se este mostrando en el formulario (no se pierde correlativo)
   Buscar -> Buscar y mostrar en formulario cualquier Boleto
 Imprimir -> Se imprime el boleto que se esta mostrando en pantalla (PDF / Impresora)
  Guardar -> Se persiste el tickets solo cuando este en modo Entrada/Salida/Modificar
 Cancelar -> Se limpia el formulario solo cuando este en modo Entrada/Salida/Modificar
    Salir -> Cierra el formulario

## Estados del Ticket

 PENDIENTE -> Se dio una entrada al camion y esta PENDIENTE por salida, se marca el camion que tiene entrada con  timestamp
   CERRADO -> Se dio salida al camion y se CIERRA el ticket, se libera el camion de su marca
MODIFICADO -> El ticket ha sido modificado
   ANULADO -> El ticket esta marcado como ANULADO

## AUDITORIA

La siguientes operativas debera persistir el id usuario responsable de dicha operacion
ENTRADA, SALIDA, ANULADO, MODIFICADO

## Calculos

Para ENTRADA Inicializar los campos numericos a 0,00

- PTE = PESO TOTAL ENTRADA
- PTS = PESO TOTAL SALIDA
- PEC = PESO ENTRADA CAMION (Chuto + Trailer)
- PSC = PESO SALIDA CAMION (Chuto + Trailer)
- PER = PESO ENTRADA REMOLQUE (Remolque)
- PSR = PESO SALIDA REMOLQUE (Remolque)
- PNT = PESO NETO TOTAL

- PND = PESO NETO DECLARADO (Es el peso que viene declarado en la guia)
- PDF = PESO DIFERENCIA (la diferencia entre peso neto total y peso neto declarado)
- PDV = PORCENTAJE DESVIACION

- PTE = PEC + PER
- PTS = PSC + PSR
- PNT = PTE - PTS
- PDF = PNT - PND (+/-)
- PDV = PDF / PND (%)

NOTA: La tolerancia se establece en la maestra de productos, la tabla que sze muestra solo es indicativo

## Tabla de Tolerancias Comerciales Habituales (Por Industria)

Si no han pactado un porcentaje exacto en el contrato de compraventa, el mercado industrial suele utilizar los siguientes estándares de tolerancia comercial para cargamentos por camión o tren:

| Tipo de Materia Prima / Producto                      | Tolerancia Comercial Típica | Causa Principal de la Variación                                 |
|-------------------------------------------------------|-----------------------------|-----------------------------------------------------------------|
| Minerales de alta densidad (Hierro, carbón, chatarra) | $\pm 1.0\%$ a $\pm 1.5\%$   | Calibración de básculas pesadas y residuos retenidos en tolvas. |
| Cereales y Granos (Maíz, soya, trigo)                 | $\pm 0.5\%$ a $\pm 0.8\%$   | Evaporación o absorción de humedad ambiental y polvo.           |
| Productos Químicos / Líquidos (Combustibles, aceites) | $\pm 0.3\%$ a $\pm 0.5\%$   | Expansión térmica por cambios de temperatura y evaporación.     |
| Materiales de Construcción (Cemento, agregados)       | $\pm 1.0\%$                 | Volatilidad del polvo durante la carga/descarga.                |

NOTA: Esta tabla es solo informativa, el operador del software debe conocer los valores a aplicar

## Ejemplo Práctico: Despacho de 45,000 kg (45 Toneladas)

Imagina un cargamento de Maíz donde el peso declarado en la factura de origen es de 45,000 kg y se acordó una tolerancia comercial del 0.5%.

   1. Calcular los kilos permitidos de tolerancia: $$45,000 \text{ kg} \times 0.005 = \mathbf{225 \text{ kg}}$$
   2. Definir el rango de aceptación: El camión debe llegar a la báscula de destino pesando entre 44,775 kg y 45,225 kg.
   3. Escenario de Evaluación:
      - Si en el destino la báscula marca 44,850 kg (faltan 150 kg): La diferencia se considera una merma normal del viaje porque está por debajo de los 225 kg permitidos.
      - Si en el destino la báscula marca 44,600 kg (faltan 400 kg): Se superó el 0.5% permitido. Se emite un mensaje de advertencia por el faltante

## Validadciones

Todos los movimientos deben tener un almacen asociado si el producto lo exige
Si el PNT > 0 Se considera una entrada en almacen
Si el PNT <> 0 Se considera una salida de almacen
No se puede dar ENTRADA al mismo CAMION si tiene un ENTRADA PREVIA, se debe anular el boleto anterior de ser el caso
Cuando se ejecuta SALIDA, se debe mostrar los camiones que estan PENDIENTES POR SALIDA y escoger aquel que se le dara SALIDA
Los tickets ANULADOS no se tomaran en cuenta para ningun reporte estadistico o de gestion

## Tipos de Movimientos de Kardex

| ID    | Descripcion              |
|-------|--------------------------|
| 00    | SALDO INICIAL            |
| 01-09 | DEFINIBLE POR EL USUARIO |
| 10    | INGRESO POR BASCULA      |
| 11-49 | DEFINIBLE POR EL USUARIO |
| 50-59 | DEFINIBLE POR EL USUARIO |
| 60    | DESPACHO POR BASCULA     |
| 61-99 | DEFINIBLE POR EL USUARIO |

Los ID cuyo rango van entre 01-49 seran tomados como movimientos positivos
Los ID cuyo rango van entre 50-99 seran tomados como movimientos negativos

Para determinar el saldo:

SALDO FINAL = SALDO INICIAL + SUMA MOVIMIENTO POSITIVOS - SUMA MOVIMIENTOS NEGATIVOS
FILTRO: A FECHA DE CORTE

Los datos a registrar en el KARDEX son los siguientes:
ID, FECHA_KARDEX, PRODUCTO, ALMACEN, FECHA_DOCUMENTO, DOCUMENTO, VALOR (PESO)

## Productos

La maestra de productos debe contener
ID, DENOMINACION, ES_KARDEX,  MEDIDA, DENSIDAD, TOLERANCIA, PESO_UNIDAD
```

# REGLA DE PARIDAD DE LAYOUT: FLUTTER ↔ BACKEND

Especificación detallada de campos y alineaciones entre `TicketPreviewDialog` y `ticket_service.py`.

---

## 1. Zonas del Boleto de Hoja (Carta / Media Carta / A4)

1. **Encabezado de Empresa:**
   - Si tiene logo: Tabla de 2 columnas `[Logo (izq) | Nombre, RIF/NIT, Teléfono, Dirección (der)]`.
   - Si no tiene logo: Texto alineado a la izquierda.
2. **Título del Boleto:**
   - Título configurado por la empresa (ej: `BOLETO DE PESAJE DE ENTRADA/SALIDA`), centrado y en negrita.
3. **Bloque de Datos Generales (2 columnas balanceadas):**
   - Columna Izquierda: Nº Boleto, Fecha Entrada, Placa Camión, Remolque (si aplica), Conductor (Nombre y Cédula).
   - Columna Derecha: Tipo de Operación, Producto, Almacén de Destino/Origen, Transportista, Guía Sunagro/Documento.
4. **Tabla LECTURA DE PESOS (5 columnas):**
   - Ver especificación en SKILL.md.
5. **Datos de Control y Comparativa (si aplica):**
   - Peso Declarado, Diferencia en kg, Porcentaje de Desviación (%).
6. **Observaciones:**
   - Texto libre de observaciones o condiciones de la carga.
7. **Firmas de Responsabilidad:**
   - Línea de firma del Operador de Báscula y línea de firma del Conductor/Transportista.

---

## 2. Zonas del Boleto Térmico (80mm / 58mm)

- Layout apilado compacto.
- Ancho útil:
  - 80 mm: ~72 mm imprimibles.
  - 58 mm: ~48 mm imprimibles.
- Encabezado centrado.
- Datos clave con etiqueta en negrita a la izquierda y valor a la derecha.
- Tabla LECTURA DE PESOS: Se ajusta tipográficamente mediante `_tamano_tabla_pesos` sin cortar horizontalmente los números.
- Código QR inferior con el identificador del boleto y URL de consulta.
- Marca de agua diagonal en rojo si el estado es `ANULADO`.

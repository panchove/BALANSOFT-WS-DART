---
name: flutter-ui-pro
description: Guía y estándares de diseño UI/UX profesional para Flutter y Dart. Úsala cuando el usuario pida diseñar, construir o refactorizar interfaces, formularios compactos, modales estéticos, componentes visuales, tipografía, paletas de colores o layouts en Flutter.
---

# Flutter UI/UX Professional Skill

## Descripción
Esta skill establece los principios, reglas y buenas prácticas para la creación de interfaces modernas, profesionales, compactas y de alto rendimiento en Dart y Flutter, enfocándose en la optimización de espacio, legibilidad en sistemas industriales/comerciales y diseño de reportes e impresiones.

## Cuándo usar esta skill
- Al diseñar pantallas de captura de datos, formularios pesados o tableros de control.
- Al definir o refactorizar temas visuales (`ThemeData`), paletas de colores y tipografía.
- Al optimizar el espacio en pantalla para evitar scroll innecesario o desbordamientos (`overflow`).
- Al maquetar vistas de reportes, tiquetes o documentos de impresión.

---

## 1. Principios de Diseño y Paleta de Colores

### Sistema de Colores (Industrial & Moderno)
- **Primary / Dominante:** Tonos oscuros/profundos (azul marino, gris grafito) para barras de navegación y encabezados.
- **Secondary / Acento:** Tonos vibrantes (azul eléctrico, esmeralda, ámbar) para botones de acción principal (CTA) y estados activos.
- **Backgrounds:** Fondo neutro claro (`#F8F9FA` o `#F1F5F9`) para reducir fatiga visual; contenedores de tarjetas en blanco puro (`#FFFFFF`) con bordes finos.
- **Feedback Visual:** 
  - Exitoso: Verde (`#10B981`)
  - Advertencia: Naranja/Ámbar (`#F59E0B`)
  - Error: Rojo (`#EF4444`)
  - Información: Azul (`#3B82F6`)

---

## 2. Ahorro de Espacio y Optimización de Formularios

Para formularios con múltiples campos o pantallas con densidad de información alta:

### Diseño Compacto
1. **Paddings & Spacings:**
   - Usa un grid base de **4px / 8px**.
   - Espaciado estándar entre inputs: `SizedBox(height: 12.0)` o máximo `16.0`.
   - Padding interno de contenedores: `EdgeInsets.all(12.0)` o `16.0`.

2. **Form Fields Estilizados:**
   - Usa `InputDecoration.dense: true` para reducir la altura vertical de los campos.
   - Aplica `contentPadding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0)`.
   - Utiliza `OutlineInputBorder` con `borderRadius` sutil (`6.0` a `8.0` px).
   - Coloca etiquetas (`labels`) flotantes o encabezados compactos arriba de los campos.

3. **Layout Multi-columna:**
   - Aprovecha `Row` combinado con `Expanded` para organizar campos relacionados en una misma línea (ej. *Ancho | Alto*, *Cédula | Nombre*).
   - Usa `Wrap` con `spacing: 8.0` para etiquetas, chips o filtros rápidos.

---

## 3. Maquetación de Vistas y Reportes

### Pantallas de Reportes y Tiquetes
- **Encabezados:** Limpios y jerárquicos. Título principal en negrita (`FontWeight.bold`), subtítulos en tonos grises (`Colors.grey[600]`).
- **Tablas de Datos:** 
  - Usa `DataTable` o `ListView.builder` con filas alternadas en color (zebra striping) para facilitar la lectura.
  - Mantén fuentes monospaced (`RobotoMono`, `Courier`) para cifras numéricas, alineadas siempre a la **derecha**.
- **Resumen Totales:** Tarjetas destacadas en la parte inferior o lateral con fondo contrastante y tipografía de mayor tamaño (`fontSize: 18.0` a `24.0`).

---

## 4. Estándares de Código Dart/Flutter

### Uso de Widgets y Performance
- **Constructores `const`:** Aplica `const` en todos los widgets estáticos para evitar re-renders innecesarios.
- **Componentización:** Divide la interfaz en micro-widgets reutilizables (`_buildHeader()`, `_buildCard()`, o clases independientes) en lugar de un único árbol de widgets gigante.
- **Responsive Layout:**
  - Usa `LayoutBuilder` o `MediaQuery` para ajustar entre layouts de escritorio/tablet y móviles.
  - Implementa `SingleChildScrollView` con `ClampingScrollPhysics` para evitar desbordamientos en pantallas pequeñas.

---

## 5. Plantilla Base para Inputs Profesionales

```dart
InputDecoration buildCompactInputDecoration({
  required String labelText,
  IconData? prefixIcon,
  String? hintText,
}) {
  return InputDecoration(
    isDense: true,
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8.0),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8.0),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8.0),
      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
    ),
  );
}
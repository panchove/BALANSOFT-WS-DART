---
name: i18n-translator
description: Traduce y gestiona la internacionalización del proyecto BALANSOFT-WS-DART para los idiomas Español (ES), Inglés (EN) y Portugués (PT). Úsala para traducir títulos, mensajes, textos de interfaz, formularios, validaciones y reportes.
---

# i18n Translator Skill

## Descripción
Esta skill proporciona las pautas, diccionarios de contexto y reglas para traducir o adaptar todos los componentes visuales e impresos de la aplicación a Español (ES), Inglés (EN) y Portugués (PT).

## Cuándo usar esta skill
- Al agregar nuevas pantallas, formularios o reportes que requieran textos en múltiples idiomas.
- Al traducir o generar archivos de localización (`.arb`, `.json` o clases de traducción en Dart).
- Al revisar que la terminología técnica e industrial (pesaje, tiquetes, básculas, licencias) mantenga coherencia en los tres idiomas.

## Reglas de Traducción

1. **Glosario Domínico e Industrial (Contexto Básculas / Sistema):**
   - **ES:** Tiquete / Peso Bruto / Peso Tara / Peso Neto / Licencia
   - **EN:** Ticket / Gross Weight / Tare Weight / Net Weight / License
   - **PT:** Bilhete (o Ticket) / Peso Bruto / Peso Tara / Peso Líquido / Licença

2. **Formato de Archivos y Claves (Keys):**
   - Usa nomenclatura `camelCase` para las claves de traducción (ej: `lblGrossWeight`, `msgSaveSuccess`, `rptTitleDailySummary`).
   - Mantén exactamente los mismos marcadores de posición (`{variable}` o `$variable`) en los tres idiomas.

3. **Estructura de Salida Espacial:**
   - **Español (ES):** Idioma base por defecto.
   - **Inglés (EN):** Conciso, orientado a interfaces UI estándar.
   - **Portugués (PT):** Variante PT-BR habitual en software industrial.

## Flujo de Trabajo

1. **Identificación de Textos:** Extrae todos los strings hardcodeados del widget, vista o reporte de Dart.
2. **Generación de Keys:** Crea claves descriptivas organizadas por sección (`common.`, `form.`, `reports.`, `errors.`).
3. **Mapeo de Traducciones:** Genera la entrada correspondiente para los 3 idiomas asegurando el tono profesional.
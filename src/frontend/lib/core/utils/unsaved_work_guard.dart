// ============================================================================
// Versión: 0.4.2-dev.56
// Fecha: 2026-10-19
// Estado: Vigente
// Norma: ISO/IEC 25010 / ISO/IEC 27001
// Fuente: Sistema BALANSOFT-WS
// Autor: Lead Architect
// ============================================================================

/// Registro global de "trabajo sin guardar" para el cierre de la ventana.
///
/// La estación de pesaje puede quedar con captura a medias (pesaje tomado de la
/// báscula, datos del camión, copia de un boleto anterior…) y el operador podría
/// cerrar la app con la "X" de la esquina, perdiendo ese trabajo.
///
/// `main.dart` consulta [tieneDatosSinGuardar] en `onWindowClose()` y solo
/// destruye la ventana si no hay nada pendiente (o si el operador confirma).
library;

/// Valor global compartido entre la pantalla de pesaje y el cierre de ventana.
bool tieneDatosSinGuardar = false;

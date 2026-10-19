# NORMATIVA Y ESTÁNDARES ISO/IEC EN BALANSOFT-WS

Todo desarrollo, refactorización, endpoint, servicio, interfaz y protocolo en BALANSOFT-WS debe regirse estrictamente por las siguientes normas internacionales ISO/IEC:

---

## 1. ISO/IEC 25010 — Calidad del Producto Software (SQuaRE)

El código debe satisfacer rigurosamente las 8 características de calidad de software:

1. **Adecuación Funcional (Functional Suitability):**
   - Las reglas de negocio de pesaje, cálculo de netos, tolerancia de merma y movimientos Kardex (10/60) deben ser exactas, completas y verificadas por pruebas unitarias.
2. **Eficiencia de Desempeño (Performance Efficiency):**
   - Latencias de endpoints de pesaje y catálogos: p50 < 50 ms, p95 < 200 ms bajo concurrencia normal.
   - Paginación obligatoria (`limit`, `skip`) y consultas optimizadas sin problemas de N+1 (uso de `_enriquecer_pesajes_lista`).
3. **Compatibilidad e Interoperabilidad (Compatibility):**
   - Interoperabilidad probada con hardware multi-marca (Toledo, Yaohua, Rice Lake, Torrey, Keli, Epson, OKI).
   - Coexistencia pacífica en red LAN (`0.0.0.0:8000`) y con puertos seriales locales.
4. **Fiabilidad y Resiliencia (Reliability):**
   - Manejo de desconexiones abruptas en sockets TCP con timeout en `writer.wait_closed()`.
   - Recuperación automática ante cortes de red y persistencia offline con cola de sincronización (`sync_queue`).
5. **Seguridad (Security):**
   - Confidencialidad: Aislamiento multi-tenant por `id_empresa` en el 100% de las consultas.
   - Integridad: Inmutabilidad física del peso capturado de la celda de carga. Firma digital Ed25519 en validación de licencias.
   - No repudio y Trazabilidad: Registro auditable de cada creación, modificación (`BoletoEdicion`) y anulación con usuario responsable, IP y timestamp.
6. **Mantenibilidad (Maintainability):**
   - Modularidad estricta: Capa HAL desacoplada del parser de texto; servicios desacoplados de rutas FastAPI; blocs desacoplados de vistas Flutter.
   - Código limpio sin warnings (`ruff check` y `flutter analyze` siempre en verde).
7. **Portabilidad (Portability):**
   - WServer empaquetado en binario autocontenido (PyInstaller one-file).
   - Compatibilidad multiplataforma Linux y Windows.

---

## 2. ISO/IEC 17025 & OIML R 76-1 / WELMEC — Metrología Legal e Integridad de Medición

En sistemas vinculados a instrumentos de pesaje no automáticos (NAWI):

- **Inmutabilidad Metrológica:** El software no debe permitir la alteración arbitraria ni el suavizado falseado de pesos físicos una vez capturados y firmados por el operador.
- **Trazabilidad de la Medición:** Cada pesaje registrado debe almacenar:
  - Identificador único de la báscula (`id_balanza`).
  - Marca de tiempo en UTC (ISO 8601).
  - Estado de estabilidad metrológica (`stable` / `unstable`).
  - Modo de captura (`es_manual = false` si provino de hardware real).
- **Control de Sobrecapacidad:** Rechazo estricto si el valor supera el 105% de la capacidad nominal de la báscula (`TOLERANCIA_CAPACIDAD = 1.05`).
- **Seguimiento de Cero:** Validación metrológica para impedir el pesaje de boletos con peso neto nulo o negativo.

---

## 3. ISO/IEC 27001 — Seguridad de la Información

- **Criptografía:**
  - Contraseñas con hashing robusto (bcrypt/argon2).
  - Tokens JWT firmados con HMAC-SHA256 y secreto criptográfico aleatorio de alta entropía (`openssl rand -hex 32`).
  - Licencias validadas con firmas asimétricas Ed25519 de curva elíptica.
- **Control de Acceso:**
  - Matriz de permisos por módulo y rol (`ADMIN`, `OPERADOR`, `AUDITOR`, `TRABAJADOR`).
  - Verificación en backend mediante dependencias FastAPI (`require_admin`, etc.).
- **Privacidad y Multi-Tenancy:**
  - Ninguna métrica de Prometheus (`/metrics`) ni log de sistema debe exponer identificadores de empresas clientes (`id_empresa`) ni información fiscal confidencial.

---

## 4. ISO 8601 — Representación de Fecha y Hora

- **Almacenamiento y Tránsito:** Todas las fechas y horas se procesan, persisten y transmiten en **UTC** con formato estándar ISO 8601:
  `YYYY-MM-DDTHH:MM:SSZ`
- **Presentación:** La conversión a la zona horaria local del cliente se realiza exclusivamente en la capa de presentación de Flutter al renderizar componentes o tickets.

---

## 5. ISO/IEC 10646 & Estándares de Codificación

- **Unicode / UTF-8:** Codificación predeterminada para base de datos, API REST, logs y archivos de configuración.
- **ISO/IEC 8859-1 (Latin-1) / CP850:** Utilizado de forma estricta en el spooling binario para impresoras térmicas ESC/POS e impresoras matriciales ESC/P para garantizar la correcta reproducción de tildes, diéresis y la letra `Ñ` sin secuencias corruptas.
- **ISO/IEC 18004:** Especificación para la generación de códigos QR bidimensionales impresos en tickets de pesaje.
- **ISO/IEC 15417:** Especificación para códigos de barras Code 128 lineales.

---

## 6. ISO/IEC/IEEE 29119 — Pruebas de Software

- Todos los cambios deben contar con pruebas automatizadas en suite:
  - Unit tests y widget tests (FastAPI / Flutter).
  - Tests E2E herméticos con stub criptográfico del License Manager.
  - Verificación por mutación: comprobar que los tests fallen si se revierte o corrompe el comportamiento probado.

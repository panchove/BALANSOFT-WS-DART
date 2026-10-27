# BALANSOFT-WS System Constitution

1. **Aislamiento Multi-Tenant Estricto:**
   - Toda tabla en PostgreSQL (salvo tablas maestras globales) DEBE contener la columna `id_empresa` de tipo UUID.
   - Todo endpoint protegido en FastAPI DEBE filtrar las operaciones de lectura/escritura por la empresa extraída del token JWT.

2. **Asincronía en Backend:**
   - Queda prohibido el uso de llamadas bloqueantes/síncronas en el código de FastAPI.
   - Todas las interacciones con PostgreSQL deben usar SQLAlchemy 2.0 Async + asyncpg.

3. **Arquitectura Offline-First:**
   - El cliente Flutter DEBE permitir el pesaje e impresión de tickets sin conexión activa a la red.
   - La sincronización NUNCA debe bloquear la interfaz de usuario ni interrumpir la captura de peso desde los sensores RS232/USB/TCP.

4. **Inmutabilidad y Auditoría de Boletos:**
   - Los boletos no se eliminan físicamente (`DELETE`).
   - El estado `ANULADO` exige generar automáticamente un movimiento inverso en Kardex (códigos 10/60) para garantizar la consistencia contable.

5. **Estrategia de Estado Frontend:**
   - La lógica de negocio en Flutter se gestionará exclusivamente con el patrón BLoC/Cubit.
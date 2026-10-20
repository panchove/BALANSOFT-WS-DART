# Partes Interesadas y Preocupaciones — BALANSOFT-WS

Según ISO/IEC/IEEE 42010, la documentación de arquitectura debe identificar las partes interesadas y sus concerns (preocupaciones). A continuación se registra cada parte interesada relevante y sus concerns asociados.

## 1. Operador de Estación de Pesaje

### Concerns Principales
- **Precisión del peso**: Validar que el peso capturado de la báscula sea exacto y refleje la realidad física
- **Facilidad de uso**: Interfaz intuitiva, atajos de teclado familiares (F2, F5, Esc, etc.), mínimo uso de mouse
- **Retroalimentación inmediata**: Confirmación visual y auditiva de operaciones realizadas
- **Modo offline**: Poder operar sin conexión a red por periodos cortos (máx. 7 días gracia)
- **Bloqueo de peso**: Que el peso báscula no sea editable por roles no autorizados
- **Historial claro**: Poder consultar el estado y historial de boletes anteriores

### Relación con Requisitos
- `REQ-NF-ONB-001`: Onboarding que capture idioma y tema
- `REQ-FN-001`: Creación de boleto entrada con validación anti-duplicidad
- `REQ-FN-002`: Cierre de pesaje con cálculos PTE-PTS-PNT-PDF-PDV
- `REQ-NF-SEG-004`: Sin modificación de peso por operador común

## 2. Administrador del Sistema

### Concerns Principales
- **Gestión de licencias**: Validación y activación de licencias Ed25519 contra License Manager
- **Configuración multi-empresa**: Aislamiento total por `id_empresa`, sin fugas de datos
- **Mantenimiento de catálogos**: CRUD completo para catálogos (marcas, transportes, productos, etc.)
- **Generación de reportes**: Reportes diarios/mensuales en formatos PDF/Excel
- **Seguridad del sistema**: Control de acceso, auditoría de todas las operaciones
- **Modo servidor**: Gestión central de cuentas, licencias y sincronización

### Relación con Requisitos
- `REQ-FN-011`: Validación de licencias Ed25519 contra LM
- `REQ-FN-012`: Matriz de permisos 18 módulos × 3 roles
- `REQ-NF-SEG-001`: Aislamiento multi-tenant en 100% de consultas
- `REQ-NF-I18N-001`: Interfaz completa en es/en/pt
- `REQ-NF-CFG-001`: Preferencias por empresa (idioma, formato ticket, formato reporte)

## 3. Supervisor / Auditor

### Concerns Principales
- **Integridad de auditoría**: Registro completo de quién, cuándo, por qué y qué se modificó
- **Inmutabilidad metrológica**: Verificar que pesos no hayan sido alterados falsamente
- **Rastreabilidad completa**: Poder rastrear cada bolete desde creación hasta anulación
- **Movimientos kardex inversos**: Anulación de boleto CERRADO debe registrar movimiento inverso exacto
- **Estados de bolete**: Garantizar que la máquina de estados sea consistente (PENDIENTE → CERRADO/MODIFICADO → ANULADO)

### Relación con Requisitos
- `REQ-FN-003`: Anulación de boleto CERRADO con motivo obligatorio
- `REQ-FN-004`: Modificación de boleto MODIFICADO (campos permitidos restringidos)
- `REQ-NF-SEG-002`: Criptografía (bcrypt/argon2, JWT HMAC-SHA256, Ed25519)
- `REQ-NF-REL-001`: Manejo de desconexiones con timeout acotado
- `REQ-NF-REL-002`: Recuperación automática con backoff exponencial

## 4. Departamento de TI / Infraestructura

### Concerns Principales
- **Arquitectura dual BD**: Separación `balansoft_ws` (servidor) / `balansoft_ws_local` (cliente)
- **Sincronización bidireccional**: Consistencia de datos entre servidor y clientes locales
- **Despliegue WServer**: PyInstaller one-file, instalación automática, generación de `.env`
- **Rendimiento de endpoints**: Latencias p50 < 50 ms, p95 < 200 ms bajo concurrencia
- **Paginación obligatoria**: Todos los endpoints de lista deben soportar `limit` y `skip`
- **Prevención N+1 queries**: Uso de helpers `_enriquecer_pesajes_lista`

### Relación con Requisitos
- `REQ-NF-PF-001`: Eficiencia de desempeño (p50 < 50 ms, p95 < 200 ms)
- `REQ-NF-PF-002`: Paginación obligatoria con `limit`/`skip`
- `REQ-NF-ONB-010`: Modo estación (SERVIDOR u OPERADOR)
- `REQ-NF-ONB-005`: Formato números/fechas por idioma
- `REQ-NF-CFG-003`: Tema de app preferencia dispositivo

## 5. Licencia Manager (BALANSOFT-LM) / Proveedor

### Concerns Principales
- **Validación de licencia**: Firma Ed25519 contra clave asimétrica
- **Un solo uso por hardware**: `hardware_id` único por licencia
- **Tiers DEMO/MONOPUESTA/CENTRAL**: Diferentes niveles de funcionalidad
- **Expiración y gracia**: Licencia DEMO 30 días, gracia 7 días después expiración
- **Key management**: Gestión de claves públicas/privadas sin exposición

### Relación con Requisitos
- `REQ-FN-011`: Validación de licencias Ed25519
- `REQ-FN-012`: Matriz de permisos y roles
- `REQ-NF-SEG-003`: Licencias con firmas Ed25519
- `REQ-NF-ONB-011`: Solo titular de licencia puede instalarse como Servidor
- `REQ-NF-ONB-012`: Modo Servidor verifica licencia contra central

## 6. Hardware de Báscula / Integración Industrial

### Concerns Principales
- **Compatibilidad multi-marca**: Toledo, Yaohua, Rice Lake, Torrey, Keli, Epson, OKI
- **Comunicación fiable**: Puertos serial RS-232, TCP sockets, Bluetooth RFCOMM
- **Estabilidad de lectura**: Tiempo de espera acotado (1.0s a 2.0s) para lecturas serie
- **Frame parsing**: XOR checksum, delimitadores (lf/cr/crlf/stx_etx)
- **Inmutabilidad de datos**: Que el software no altere el peso físico capturado
- **Fallback software**: Modo manual cuando hardware no está disponible

### Relación con Requisitos
- `REQ-NF-SEG-005`: Control de sobrecapacidad (> 105% capacidad nominal)
- `REQ-NF-MET-001`: Inmutabilidad metrológica (peso capturado NUNCA editado)
- `REQ-FN-001`: Anti-duplicidad por `placa + id_empresa`
- `REQ-NF-REL-001`: Timeouts acotados en lecturas serie (1.0s a 2.0s)
- `REQ-NF-REL-002`: Reconexión con backoff exponencial

## 7. Usuarios Finales (Empresas Transportistas)

### Concerns Principales
- **Facturación correcta**: Pesajes precisos para cálculo de flete y costos
- **Reportes de gestión**: Inventario actualizado en tiempo real
- **Acceso a historial**: Consultar boletes pasados, kardex, saldos
- **Impresión de tickets**: Formato canónico, legible, con todos los datos requeridos
- **Modo kiosk**: Aplicación en pantalla completa sin accesos accidentales

### Relación con Requisitos
- `REQ-NF-ONB-015`: Modo operador cliente delgado
- `REQ-FN-008`: Consultas CRUD a catálogos con filtrado `id_empresa`
- `REQ-FN-009`: Validación unicidad `codigo` por empresa
- `REQ-NF-POR-001`: Portabilidad WServer Linux/Windows
- `REQ-NF-USA-001`: Usabilidad en estación de pesaje kiosk

## Matriz de Correspondencia Preocupación → Requisito

| Parte Interesada        | Concern Principal                        | ID Requisito Asociado                   |
|-------------------------|------------------------------------------|-----------------------------------------|
| Operador                | Peso exacto, modo offline                | REQ-FN-001 a REQ-FN-005                 |
| Administrador           | Licencias, seguridad, catálogos          | REQ-FN-011 a REQ-FN-012, REQ-NF-SEG-001 |
| Supervisor              | Auditoría, estados, kardex inverso       | REQ-FN-003 a REQ-FN-004, REQ-NF-REL-001 |
| TI / Infraestructura    | Arquitectura BD, rendimiento, paginación | REQ-NF-PF-001 a REQ-NF-PF-002           |
| License Manager         | Validación Ed25519, tiers, expiración    | REQ-FN-011, REQ-NF-SEG-003              |
| Hardware báscula        | Compatibilidad, fiabilidad, checksum     | REQ-NF-SEG-005, REQ-NF-REL-001          |
| Empresas transportistas | Facturación, reportes, impresiones       | REQ-FN-008 a REQ-FN-009, REQ-NF-POR-001 |
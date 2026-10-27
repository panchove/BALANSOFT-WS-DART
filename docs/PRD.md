# PRD — BALANSOFT-WS (Borrador para revisión)

**Versión:** 0.1 (Borrador)
**Fecha:** 2026-10-26
**Estado:** Propuesta inicial — requiere validación del equipo de producto
**Autor:** Análisis consolidado a partir de la documentación existente
**Fuente:** `constitution.md`, `TERMINOS_CONDICIONES.md`, `MANEJO_DB.md`, `SESIONES.md`, `PLANES-PAGOS.md`, `MODELO_ESTANDAR.md`, `NAV.md`, `SEMAFORO.md`, `DISPOSITIVOS.md`, `BALANZAS_SOPORTADAS.md`, `I18N_Y_ONBOARDING.md`, `OBSERVABILIDAD.md`, `USO-API.md`, `AGENTS.md`, `ACTUAR.md`, `CHANGELOG.md`

> **Nota:** Este documento es un esqueleto. Los campos marcados con `[DECISIÓN PENDIENTE]` requieren que el equipo de producto (no solo desarrollo) confirme la decisión. Los marcados con `[A VALIDAR]` requieren verificación con cliente real o con el Proveedor.

---

## 1. Visión y Propósito

### 1.1. Problema que resuelve
Las estaciones de pesaje industrial para camiones operan en entornos donde la conectividad a internet es intermitente o inexistente, y donde la **trazabilidad metrológica** del peso capturado es un requisito legal y comercial. Los sistemas tradicionales dependen de una conexión permanente a un servidor central, lo que los hace frágiles ante caídas de red, y no siempre garantizan la inmutabilidad del peso registrado.

BALANSOFT-WS resuelve esto mediante una arquitectura **offline-first** donde la estación opera de forma autónoma contra su propia base de datos local, y la sincronización con el servidor central es **best-effort** y nunca bloquea la operación de pesaje.

### 1.2. Propuesta de valor
- **Operación ininterrumpida:** el pesaje, la impresión de tickets y el registro de boletos funcionan sin conexión a internet.
- **Trazabilidad metrológica:** el peso leído de la báscula **nunca se edita**; cualquier ajuste manual queda auditado.
- **Multi-tenant estricto:** cada empresa ve solo sus datos; el aislamiento se garantiza en cada consulta.
- **Licenciamiento centralizado:** el Proveedor controla la activación, el número de sesiones y la vigencia desde un servidor central.
- **Integración de hardware real:** básculas de múltiples marcas (Toledo, Rice Lake, Yaohua, Keli, Torrey, etc.), semáforos, indicadores, cámaras e impresoras.

### 1.3. Objetivos medibles
| Objetivo                 | Métrica                                                           | Fuente                                     |
|--------------------------|-------------------------------------------------------------------|--------------------------------------------|
| Operación sin red        | 100% de pesajes y tickets funcionan offline                       | `MANEJO_DB.md` §8.3, `ACTUAR.md`           |
| Rendimiento              | p50 < 50 ms, p95 < 200 ms en endpoints de listado                 | `OBSERVABILIDAD.md`, `ACTUAR.md` (P2c)     |
| Inmutabilidad del peso   | 0 ediciones de peso capturado; 100% de ajustes manuales auditados | `constitution.md` §4, `MODELO_ESTANDAR.md` |
| Aislamiento multi-tenant | 0 fugas entre empresas verificadas por test                       | `AGENTS.md`, `OBSERVABILIDAD.md` §6        |
| Cobertura de idiomas     | es/en/pt al 100% en UI, tickets y reportes                        | `I18N_Y_ONBOARDING.md`                     |
| Estabilidad              | 0 bugs bloqueantes abiertos                                       | `ACTUAR.md`                                |

---

## 2. Usuarios Objetivo (Personas)

### 2.1. ADMIN (Administrador de la Empresa)
- **Quién es:** el responsable de la operación de la estación de pesaje en la empresa cliente.
- **Qué necesita:** configurar la empresa, gestionar usuarios y roles, aprobar equipos, emitir llaves de activación, ver reportes, auditar.
- **Dónde opera:** principalmente en el `SERVIDOR_LOCAL` (la máquina titular de la licencia).

### 2.2. OPERADOR (Operador de Báscula)
- **Quién es:** el trabajador que captura los pesos en la estación.
- **Qué necesita:** un flujo de pesaje rápido, teclado-céntrico, con captura guiada cabina→remolque, y confirmación antes de guardar.
- **Dónde opera:** en cualquier equipo `LOCAL` (operador) aprobado por el ADMIN.

### 2.3. AUDITOR
- **Quién es:** el responsable de verificar la trazabilidad y consistencia de los registros.
- **Qué necesita:** acceso de solo lectura a boletos, kardex, reportes y auditoría; capacidad de modificar/anular boletos (según `MANEJO_DB.md` §4).
- **Dónde opera:** en un equipo `LOCAL` con rol de sesión `AUDITOR`.

### 2.4. Proveedor (BALANSOFT)
- **Quién es:** el equipo que comercializa y da soporte al sistema.
- **Qué necesita:** un panel para crear cuentas, asignar licencias, designar titulares, ver el estado de las cuentas.
- **Dónde opera:** en el servidor central (`APP_ROLE=server`).

### 2.5. [DECISIÓN PENDIENTE] ¿Hay un usuario "Trabajador"?
`MODELO_ESTANDAR.md` lista cuatro roles (Admin, Operador, Auditor, Trabajador), pero `MANEJO_DB.md` §4 dice que OPERADOR "absorbe el antiguo rol TRABAJADOR". ¿Se elimina formalmente "Trabajador" del modelo de producto?

---

## 3. Alcance del Producto

### 3.1. Dentro del alcance
- Estación de pesaje (backend FastAPI + frontend Flutter) con arquitectura offline-first.
- WServer (backend local compilado) para estaciones `SERVIDOR`.
- Servidor central (API + BD) para licenciamiento, cuentas, sesiones y sincronización.
- Panel del proveedor (BALASOFT-UI) para gestión de cuentas y licencias.
- Integración de dispositivos: básculas (serial/TCP), semáforos (HTTP/serial), indicadores, cámaras, impresoras.
- Sincronización bidireccional (catálogos, usuarios, boletos) entre local y central.
- Internacionalización es/en/pt.
- Observabilidad (Prometheus/Grafana) y auditoría.
- Instalador (BALANSOFT-INSTALLER) que decide el rol y escribe `config.json`.

### 3.2. Fuera del alcance
- **Instaladores** (Linux `.deb`, Windows Inno, Android APK): `MANEJO_DB.md` los declara fuera de alcance "por ahora".
- **Alta disponibilidad:** `OBSERVABILIDAD.md` §8 la declara innecesaria para una estación.
- **TLS/HTTPS en producción:** pendiente (P3 en `ACTUAR.md`), requiere dominio y certificado.
- **Firma de código del WServer:** pendiente (H4), requiere certificados.
- **Canal de notificación de alertas (correo/Slack):** pendiente de infraestructura (`OBSERVABILIDAD.md` §8).
- **Panel del proveedor en otros idiomas:** `I18N_Y_ONBOARDING.md` §6 lo marca como "se traduce después".

### 3.3. [DECISIÓN PENDIENTE] Alcance de la integración de hardware
`DISPOSITIVOS.md` menciona barreras de tránsito (§5) pero no hay evidencia en `CHANGELOG.md` ni en `NAV.md` de que estén implementadas. ¿Están en el alcance actual o son roadmap futuro?

---

## 4. Modelo Comercial y Licenciamiento

### 4.1. Modalidad única: CENTRAL
Según `TERMINOS_CONDICIONES.md` §2.1, BALANSOFT-WS se comercializa **exclusivamente** bajo licencia `CENTRAL` (multisesión). No se venden `MONOPUESTO` ni `DEMO`.

### 4.2. Planes: Básico y Premium
| Aspecto            | Básico                             | Premium                            | Fuente                         |
|--------------------|------------------------------------|------------------------------------|--------------------------------|
| Módulos avanzados  | Excluidos                          | Incluidos                          | `TERMINOS_CONDICIONES.md` §4   |
| Número de sesiones | Definido por el cliente al comprar | Definido por el cliente al comprar | `TERMINOS_CONDICIONES.md` §2.3 |
| Costo              | Menor                              | Mayor                              | `TERMINOS_CONDICIONES.md` §2.3 |

### 4.3. [DECISIÓN PENDIENTE CRÍTICA] ¿Cómo se traduce "Básico vs. Premium" en el producto?
Existe una **contradicción directa** entre documentos:

- **`TERMINOS_CONDICIONES.md` §4.1** dice que el Plan Básico **excluye módulos avanzados** (reportes avanzados, exportación múltiple, diseño de ticket avanzado, auditoría extendida, conceptos personalizables, series múltiples).
- **`PLANES-PAGOS.md` §2** y **`AGENTS.md`** dicen que la estación WS **no gatea funciones por `plan_type`**; todos los módulos están disponibles sin importar el plan. Lo único que la licencia impone es el **límite de sesiones**.

**Opciones para resolver:**
1.  **La restricción es comercial, no técnica:** el contrato dice "Básico excluye X", pero la app no lo enforcea. El Proveedor confía en la buena fe del cliente o en auditorías posteriores. **(Inconsistente con la práctica habitual de licenciamiento de software).**
2.  **La restricción es técnica pero no está implementada aún:** el código actual no gatea, pero debería hacerlo. Sería una deuda funcional no documentada como tal.
3.  **`TERMINOS_CONDICIONES.md` está desactualizado:** el modelo de negocio cambió a "solo sesiones" y el documento legal no se actualizó.
4.  **La restricción se aplica en el LM, no en la estación:** el LM podría no emitir features para Básico, y la estación las ignora (según `PLANES-PAGOS.md`), pero el panel del proveedor sí las oculta. Esto es inconsistente porque el cliente vería las funciones en la app.

**Recomendación:** resolver esta contradicción **antes** de cualquier otra tarea de producto. Sin claridad aquí, no se puede priorizar correctamente ni comunicar al cliente qué está comprando.

### 4.4. [DECISIÓN PENDIENTE] Tier DEMO
- `TERMINOS_CONDICIONES.md` dice que **no se vende**.
- El código lo soporta (`PLANES-PAGOS.md`, `SESIONES.md`).
- **¿Para qué existe?** ¿Demos comerciales? ¿Uso interno? ¿Está obsoleto y debe eliminarse del código?
- **Recomendación:** si no se vende, documentar su propósito (ej. "solo para demos comerciales del Proveedor, no comercializable") y asegurarse de que el panel del proveedor no permita emitir DEMO por error.

### 4.5. Límite de sesiones
- El cliente define el número de sesiones al comprar (`TERMINOS_CONDICIONES.md` §2.3).
- El LM lo registra en `licencias.max_sesiones`.
- La estación lo enforcea: `DEMO` → 3; `CENTRAL` → `licencias.max_sesiones`.
- **Regla:** al alcanzar el tope, los dispositivos adicionales reciben "sin cupos disponibles" (`TERMINOS_CONDICIONES.md` §4.3).

---

## 5. Historias de Usuario Priorizadas

> **Nota:** esta sección es un extracto. Un PRD completo tendría decenas de historias. Se listan las más representativas por dominio, con criterios de aceptación verificables y referencia al documento fuente.

### 5.1. Autenticación y Licenciamiento

#### HU-01: Login central-first con fallback offline
**Como** ADMIN, **quiero** que la estación intente primero validar contra el servidor central y, si no hay red, permita el login local con las credenciales cacheadas, **para** poder operar aunque se caiga internet.
- **Criterios de aceptación:**
    - Con red: `POST /api/v1/auth/login` contra el central; si la licencia es válida, se crea/actualiza la sesión local.
    - Sin red: `POST /api/v1/auth/login-local` contra la API local, validando contra `usuarios.password_hash`.
    - Si el JWT expiró y no hay red, se permite el login local dentro de `OFFLINE_GRACE_DAYS`.
    - Después de `MAX_OFFLINE_DAYS`, solo se permite consulta, no operaciones nuevas.
- **Fuente:** `MANEJO_DB.md` §8.1–8.3.

#### HU-02: Activación de estación operador con llave de un solo uso
**Como** ADMIN del `SERVIDOR_LOCAL`, **quiero** emitir una llave de activación de un solo uso para autorizar un nuevo equipo operador, **para** controlar quién se conecta a mi cuenta.
- **Criterios de aceptación:**
    - `POST /api/v1/activacion/llaves` (solo ADMIN) devuelve el código en claro **una sola vez** (`BS-XXXX-XXXX-XXXX`), con `codigo_preview` para reconocerlo.
    - La llave caduca a los 7 días (configurable 1 h – 90 días).
    - Emitir una nueva llave para el mismo usuario **revoca** la anterior.
    - `POST /api/v1/activacion/validar` (sin auth) canjea la llave con `FOR UPDATE` (idempotente).
    - El instalador exige la llave en el paso 1c; sin llave válida, no se recibe cuenta.
- **Fuente:** `MANEJO_DB.md` §13.7.

#### HU-03: Aprobación de equipos por la tutora (RB-12)
**Como** tutora de la cuenta, **quiero** aprobar o rechazar los nuevos equipos que intentan conectarse, **para** evitar accesos no autorizados.
- **Criterios de aceptación:**
    - Un equipo nuevo de licencia `CENTRAL` nace `PENDIENTE` y no abre sesión (403).
    - La tutora lo ve en "Sesiones y Equipos" y puede aprobarlo con un rol (`ADMIN`/`OPERADOR`/`AUDITOR`) o rechazarlo.
    - Al aprobar, la sesión se abre con el rol asignado; al rechazar, se revocan sus sesiones abiertas.
    - El equipo titular no puede rechazarse ni cambiársele el rol.
- **Fuente:** `SESIONES.md` §3–6.

### 5.2. Pesaje

#### HU-04: Captura guiada cabina → remolque
**Como** OPERADOR, **quiero** capturar el peso de la cabina y luego el del remolque con un flujo guiado, **para** no equivocarme al registrar un vehículo con dos pesos.
- **Criterios de aceptación:**
    - `F3` / botón "Capturar peso" congela el peso de la cabina.
    - Con remolque, aparece la alerta "Mueva el camión"; al continuar, la báscula pasa a llenar el campo del remolque.
    - `F3` de nuevo fija el peso del remolque.
    - `Enter`/`F4` abren confirmación con resumen de pesos y tipo (ENTRADA/SALIDA).
    - Guardar sin captura previa se rechaza.
- **Fuente:** `CHANGELOG.md` v1.3.1, `INPUTS_MAP.md` §1.1.

#### HU-05: Inmutabilidad del peso capturado
**Como** AUDITOR, **quiero** que el peso leído de la báscula nunca pueda editarse, **para** garantizar la trazabilidad metrológica.
- **Criterios de aceptación:**
    - El peso capturado no se edita; cualquier ajuste manual se marca como `es_peso_manual = TRUE` y queda auditado.
    - Un boleto anulado no se borra; su estado pasa a `ANULADO` y se genera un movimiento inverso en Kardex (10↔60).
    - Las ediciones de un boleto (`MODIFICADO`) solo afectan a `documento`, `flete`, `costo_flete`, `observaciones`, `peso_neto_declarado`.
- **Fuente:** `constitution.md` §4, `MODELO_ESTANDAR.md`, `MANEJO_DB.md` §3, §5.

#### HU-06: Operación offline con semáforo y báscula
**Como** OPERADOR, **quiero** que el semáforo y la báscula sigan funcionando aunque se caiga internet, **para** no interrumpir el flujo de pesaje.
- **Criterios de aceptación:**
    - El semáforo es controlado por la app (no por el servidor central): la app decide el LED según el peso y el estado del boleto.
    - La lectura de la báscula es local (HAL serial/TCP); no depende de red.
    - Si el envío al semáforo falla, se reintenta en el siguiente ciclo sin inundar el dispositivo.
- **Fuente:** `SEMAFORO.md` §4–6, `DISPOSITIVOS.md`.

### 5.3. Sincronización

#### HU-07: Sincronización bidireccional best-effort
**Como** ADMIN, **quiero** que los datos (catálogos, usuarios, boletos) se sincronicen con el central cuando haya red, **para** tener respaldo y consistencia entre equipos.
- **Criterios de aceptación:**
    - `POST /sync/push` (local → server) y `GET /sync/pull` (server → local) funcionan sin bloquear la UI.
    - La sincronización se reintenta en caso de fallo, con backoff.
    - Los conflictos se resuelven por último timestamp.
    - El estado de sincronización es visible en el dashboard (`sync_status`).
- **Fuente:** `MANEJO_DB.md` §9.1, §10 (Fase 2), `CHANGELOG.md` v1.3.3.
- **Estado:** push/pull implementados; resolución de conflictos y sync de boletos **pendientes** (`MANEJO_DB.md` §10 Fase 2).

### 5.4. Reportes y Auditoría

#### HU-08: Reportes avanzados (Premium)
**Como** ADMIN, **quiero** acceder a reportes avanzados (transportista, tercero, rango de peso, comparativo mensual), **para** analizar la operación.
- **Criterios de aceptación:**
    - Los reportes están disponibles en la UI (`NAV.md` → Reportes).
    - La exportación respeta el formato configurado (`formato_reporte`).
    - **[DECISIÓN PENDIENTE]** ¿Estos reportes deben estar gateados por plan (Básico/Premium)? Ver §4.3.
- **Fuente:** `TERMINOS_CONDICIONES.md` §4.1, `NAV.md`, `CHANGELOG.md` (v1.3.6 menciona "reportes avanzados" implementados).

#### HU-09: Auditoría completa y consultable
**Como** AUDITOR, **quiero** ver un registro detallado de acciones (usuario, IP, timestamp, entidad), **para** investigar incidentes.
- **Criterios de aceptación:**
    - `GET /api/v1/auditoria` devuelve la tabla completa con filtros; solo ADMIN/AUDITOR.
    - La UI muestra usuario/email, IP, entidad, detalle y timestamp UTC.
    - Las acciones sensibles (aprobación de equipos, comandos de semáforo, emisión de llaves) quedan registradas.
- **Fuente:** `AGENTS.md`, `CHANGELOG.md` v1.3.2, `OBSERVABILIDAD.md` §1.

### 5.5. Onboarding e Instalación

#### HU-10: Instalación con rol decidido por el instalador
**Como** Proveedor, **quiero** que el instalador escriba el rol (`SERVIDOR`/`OPERADOR`) y la URL de la API en `config.json`, **para** que la app arranque en `/login` sin asistente.
- **Criterios de aceptación:**
    - `config.json` contiene exactamente `api_base_url` + `rol` (sin degradación ni fallback).
    - Si falta o es inválido, la app muestra `PantallaErrorConfig` y no opera.
    - Migración única del legado de preferencias del wizard anterior.
- **Fuente:** `CHANGELOG.md` v1.4.1, `I18N_Y_ONBOARDING.md` §4.

---

## 6. Requisitos No Funcionales

| ID              | Requisito                                              | Criterio                             | Fuente                     |
|-----------------|--------------------------------------------------------|--------------------------------------|----------------------------|
| REQ-NF-PERF-001 | p50 < 50 ms, p95 < 200 ms en endpoints de listado      | Medido con 50k boletos               | `ACTUAR.md` P2             |
| REQ-NF-SEC-001  | Multi-tenant: toda query filtra por `id_empresa`       | 0 excepciones; verificado por test   | `constitution.md` §1       |
| REQ-NF-SEC-002  | JWT con Ed25519 para firma de licencias                | Firma verificada en cada `/validate` | `USO-API.md` §6            |
| REQ-NF-SEC-003  | Rate limiting (documentado su límite por worker)       | Redis pendiente                      | `AGENTS.md` D5             |
| REQ-NF-I18N-001 | es/en/pt al 100% en UI, tickets, reportes              | 621 claves × 3 idiomas               | `I18N_Y_ONBOARDING.md`     |
| REQ-NF-OBS-001  | `/metrics` con 5 métricas, sin `id_empresa`            | Verificado por test                  | `OBSERVABILIDAD.md` §3, §6 |
| REQ-NF-ARQ-001  | Offline-first: pesaje e impresión sin red              | 100% funcional                       | `constitution.md` §3       |
| REQ-NF-ARQ-002  | Asincronía en backend (SQLAlchemy 2.0 Async + asyncpg) | Prohibido bloqueo                    | `constitution.md` §2       |
| REQ-NF-MET-001  | Peso inmutable, tolerancia 105%, trazabilidad          | OIML R 76-1                          | `AGENTS.md`                |
| REQ-NF-UX-001   | Flujo de pesaje teclado-céntrico (F2–F12)              | Documentado en `INPUTS_MAP.md`       | `INPUTS_MAP.md`            |

---

## 7. Dependencias y Restricciones

| Dependencia                          | Impacto                                                               | Estado                                                |
|--------------------------------------|-----------------------------------------------------------------------|-------------------------------------------------------|
| **LM (License Manager)**             | Validación de licencias; sin LM, la estación opera en modo degradado  | Implementado (Ed25519, stub para CI)                  |
| **WServer (PyInstaller)**            | Backend local para `SERVIDOR`; requiere recompilación en cada release | Implementado                                          |
| **Instalador (BALANSOFT-INSTALLER)** | Decide rol y escribe `config.json`                                    | Fuera de alcance de este repo                         |
| **PostgreSQL 15+**                   | Motor de BD (soportado); SQL Server es Fase 2                         | Implementado (PG); SQL Server parcial                 |
| **Hardware de básculas**             | Serial/TCP; marcas soportadas en `BALANZAS_SOPORTADAS.md`             | Implementado; falta validación con hardware real (P1) |
| **Semáforos (BSDD)**                 | HTTP/serial; comandos JSON                                            | Implementado; Modbus/MQTT diferidos                   |
| **TLS/HTTPS**                        | Requerido para producción                                             | Pendiente (P3)                                        |
| **Dominio + certificado**            | Requerido para TLS                                                    | Pendiente                                             |

---

## 8. Métricas de Éxito

| Métrica                   | Objetivo                   | Cómo se mide                              |
|---------------------------|----------------------------|-------------------------------------------|
| Uptime de la estación     | > 99% en horario operativo | `balansoft_http_requests_total` + alertas |
| Latencia p95              | < 200 ms                   | `balansoft_api_latency_seconds`           |
| Errores de licencia       | < 5 en 15 min              | `balansoft_license_errors_total`          |
| Pesajes completados       | > 0 por turno              | `balansoft_pesajes_total` (CERRADO)       |
| Tickets impresos          | 100% de pesajes CERRADOS   | Auditoría                                 |
| Satisfacción del operador | [A VALIDAR]                | Encuesta post-implementación              |

---

## 9. Roadmap y Priorización

Basado en `ACTUAR.md` y el análisis de este PRD:

### Fase 0: Resolución de ambigüedades (inmediato)
1.  **Resolver la contradicción Básico/Premium** (§4.3). Sin esto, no se puede priorizar correctamente.
2.  **Definir el propósito del tier DEMO** (§4.4).
3.  **Decidir si "Trabajador" se elimina formalmente** (§2.5).
4.  **Decidir si las barreras de tránsito están en alcance** (§3.3).
5.  **Crear el PRD autoritativo** (este documento, tras validación).

### Fase 1: Cierre técnico (corto plazo, ~1 semana)
- F1: Regenerar `balansoft-ws-local.sql` desde el esquema real (`ACTUAR.md` §7).
- F2: Decidir sobre la tabla `configuraciones` (eliminar o añadir `id_empresa` a la PK).
- D7: Decidir el título del ticket (PDF vs. Flutter).
- D8: Cerrar el síntoma original del "instalador no termina en modo operador".

### Fase 2: Hardening e infraestructura (~2 semanas)
- H3: Backup automático del LM.
- H4: Firma de código del WServer.
- H12: Auditoría de lecturas sensibles (opcional).
- H15: Manual de operador.

### Fase 3: Validación con cliente (~10 días)
- P1: Pruebas con balanza física.
- P3: HTTPS/TLS con nginx.
- P4: Manuales de usuario con capturas.
- P5: Proceso de soporte formal.
- P6: CI/CD completo.
- P7: Backups del LM automatizados.
- P8: Regenerar WServer + bundles.

---

## 10. Anexos

### A. Glosario
- **Boleto:** registro de un pesaje (entrada/salida), con estados `PENDIENTE`, `CERRADO`, `MODIFICADO`, `ANULADO`.
- **Kardex:** registro de movimientos de inventario (ID 10 = ingreso, ID 60 = despacho).
- **SERVIDOR_LOCAL:** equipo titular de la licencia; ejecuta el WServer.
- **LOCAL:** equipo operador; cliente delgado del `SERVIDOR_LOCAL`.
- **LM:** License Manager; servidor central que valida licencias.
- **BSDD:** simulador de semáforo.

### B. Referencias documentales
- `constitution.md` — Reglas invariables (multi-tenant, asincronía, offline-first, inmutabilidad, BLoC).
- `TERMINOS_CONDICIONES.md` — Modelo comercial.
- `MANEJO_DB.md` — Arquitectura de 2 BDs, modelo de cuenta, flujo de login.
- `SESIONES.md` — Aprobación de equipos (RB-12).
- `PLANES-PAGOS.md` — Tiers y límites.
- `MODELO_ESTANDAR.md` — Reglas de negocio del boleto.
- `NAV.md` — Mapa de navegación.
- `SEMAFORO.md` — Integración del semáforo.
- `DISPOSITIVOS.md` — Integración de hardware.
- `BALANZAS_SOPORTADAS.md` — Matriz de compatibilidad de básculas.
- `I18N_Y_ONBOARDING.md` — Idiomas y onboarding.
- `OBSERVABILIDAD.md` — Métricas y alertas.
- `USO-API.md` — Integración del cliente de licencias.
- `AGENTS.md` — Reglas técnicas y comandos.
- `ACTUAR.md` — Pendientes técnicos.
- `CHANGELOG.md` — Historia de cambios.

### C. Preguntas abiertas para el equipo de producto
1.  ¿Básico/Premium gatea funciones o solo sesiones? (§4.3)
2.  ¿Para qué existe el tier DEMO? (§4.4)
3.  ¿Se elimina "Trabajador" del modelo? (§2.5)
4.  ¿Las barreras de tránsito están en alcance? (§3.3)
5.  ¿Cuál es el título canónico del ticket? (D7 en `AGENTS.md`)
6.  ¿Cuál es el síntoma exacto del bug del instalador en modo operador? (D8 en `AGENTS.md`)
7.  ¿Se auditan las lecturas sensibles o solo las escrituras? (H12)
8.  ¿Qué contiene el manual de operador? (H15)

---

*Documento en borrador. Requiere validación del equipo de producto antes de considerarse autoritativo. Las secciones marcadas con `[DECISIÓN PENDIENTE]` y las preguntas del Anexo C son el punto de partida para la revisión.*
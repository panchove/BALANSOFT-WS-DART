# Matriz de Trazabilidad de Requisitos — BALANSOFT-WS

**Versión:** 1.0 (borrador)  
**Fecha:** 2026-10-26  
**Estado:** En construcción (Fase 2 completada)

---

## Plantilla de Tabla Maestra

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-XXXX-000 | (si aplica) | RF | DOMINIO | Descripción clara del requisito | Test o criterio verificable | `archivo:línea` | `doc.md §X` | ESTADO | Contradicciones, gaps, etc. |

---

## Índice por Dominio (se rellena en Fase 10)

| Dominio | RFs | RNFs | RBs | Total |
|---------|-----|------|-----|-------|
| AUTH | 10 | 5 | 35 | 50 |
| WEIGHING | 14 | 3 | 46 | 63 |
| CATALOG | 20 | 0 | 68 | 88 |
| KARDEX | 3 | 0 | 18 | 21 |
| SYNC | 4 | 0 | 9 | 13 |
| LICENSE | 5 | 0 | 18 | 23 |
| SESSIONS | 4 | 1 | 5 | 10 |
| SEMAFORO | 6 | 0 | 6 | 12 |
| DEVICES | 7 | 0 | 30 | 37 |
| REPORTS | 7 | 0 | 0 | 7 |
| AUDIT | 2 | 1 | 4 | 7 |
| I18N | 0 | 2 | 1 | 3 |
| OBSERVABILITY | 0 | 3 | 3 | 6 |
| INSTALLER | 0 | 0 | 0 | 0 |
| WSERVER | 0 | 0 | 0 | 0 |
| PRINTING | 0 | 0 | 6 | 6 |
| USUARIOS | 0 | 0 | 2 | 2 |
| EMPRESA | 0 | 0 | 7 | 7 |
| SEGURIDAD | 0 | 0 | 2 | 2 |
| SERIES | 0 | 0 | 3 | 3 |
| BACKUP | 0 | 0 | 3 | 3 |
| **TOTAL** | **82** | **15** | **265** | **362** |

---

## FASE 1 — ESQUEMA DE BASE DE DATOS: REGLAS DE NEGOCIO (RB) EXTRAÍDAS

Fuentes: `backend/balansoft-ws-local.sql`, `backend/balansoft-ws-server.sql`, `backend/migrations/*.sql` (001–032)

### Sección: AUTH — Autenticación y Autorización

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-AUTH-001 | – | RB | AUTH | Singleton `identidad_local`: solo una fila permitida (`id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id = TRUE)`) | Test: INSERT segunda fila falla | `balansoft-ws-local.sql:18-19` | MANEJO_DB.md §13 | IMPLEMENTADO | Garantiza una sola identidad local por máquina |
| RB-AUTH-002 | – | RB | AUTH | `identidad_local.id_cuenta` NOT NULL — vínculo obligatorio a cuenta central | Test: INSERT sin id_cuenta falla | `balansoft-ws-local.sql:20` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| RB-AUTH-003 | – | RB | AUTH | `identidad_local.rol_dispositivo` DEFAULT 'LOCAL', solo valores 'LOCAL'/'SERVIDOR_LOCAL' | Test: valores válidos aceptados, inválidos rechazados | `balansoft-ws-local.sql:29` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| RB-AUTH-004 | – | RB | AUTH | `empresas.rif_nit` UNIQUE — RIF/NIT único global (no por empresa) | Test: duplicado falla con 23505 | `balansoft-ws-local.sql:44` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-AUTH-005 | – | RB | AUTH | `usuarios.email` UNIQUE — email único global (no por empresa) | Test: duplicado falla con 23505 | `balansoft-ws-local.sql:157` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-AUTH-006 | – | RB | AUTH | `usuarios.rol` CHECK IN ('ADMIN','OPERADOR','AUDITOR') — 3 roles válidos (TRABAJADOR fusionado en 025) | Test: rol inválido rechazado | `balansoft-ws-local.sql:166` | MANEJO_DB.md §4, migración 025 | IMPLEMENTADO | Migración 025 elimina TRABAJADOR |
| RB-AUTH-007 | – | RB | AUTH | `usuarios.id_empresa` FK NOT NULL — todo usuario pertenece a una empresa | Test: INSERT sin id_empresa falla | `balansoft-ws-local.sql:153` | MANEJO_DB.md §4 | IMPLEMENTADO | Multi-tenancy obligatorio |
| RB-AUTH-008 | – | RB | AUTH | `permisos_acceso` PK compuesta (id_empresa, rol, modulo) — matriz por empresa | Test: duplicado mismo empresa/rol/modulo falla | `balansoft-ws-local.sql:798-804` | MANEJO_DB.md §12, SEGURIDAD.md | IMPLEMENTADO | 18 módulos × 3 roles |
| RB-AUTH-009 | – | RB | AUTH | `permisos_acceso.acceso` DEFAULT 'ver', valores 'ver'/'editar'/'ninguno' | Test: default aplicado | `balansoft-ws-local.sql:802` | MANEJO_DB.md §12 | IMPLEMENTADO | |
| RB-AUTH-010 | – | RB | AUTH | Server: `cuentas.rif_nit` UNIQUE, `cuentas.email_admin` UNIQUE | Test: duplicados fallan | `balansoft-ws-server.sql:18,22` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| RB-AUTH-011 | – | RB | AUTH | Server: `credenciales.email` UNIQUE — credencial global única | Test: duplicado falla | `balansoft-ws-server.sql:91` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| RB-AUTH-012 | – | RB | AUTH | Server: `dispositivos.hardware_id` UNIQUE — huella máquina única global | Test: duplicado falla | `balansoft-ws-server.sql:63` | MANEJO_DB.md §13 | IMPLEMENTADO | |

---

### Sección: WEIGHING — Pesaje

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-WEIGH-001 | – | RB | WEIGHING | `boletos_pesaje.numero_boleto` UNIQUE — número de boleto único global (no se reutiliza) | Test: duplicado falla con 23505 | `balansoft-ws-local.sql:624` | MANEJO_DB.md §6, MODELO_ESTANDAR.md | IMPLEMENTADO | Secuencial TA-XXXXXX |
| RB-WEIGH-002 | – | RB | WEIGHING | `boletos_pesaje.peso_entrada_vehiculo` CHECK (>= 0) — peso entrada no negativo | Test: peso negativo rechazado | `balansoft-ws-local.sql:639` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-WEIGH-003 | – | RB | WEIGHING | `boletos_pesaje.estado_boleto` DEFAULT 'PENDIENTE' — estados válidos: PENDIENTE/CERRADO/MODIFICADO/ANULADO | Test: default aplicado, normalización legacy | `balansoft-ws-local.sql:687`, migración 003:33-39 | MANEJO_DB.md §6, MODELO_ESTANDAR.md | IMPLEMENTADO | Migración 003 normaliza legacy |
| RB-WEIGH-004 | – | RB | WEIGHING | `boletos_pesaje.es_peso_manual` DEFAULT FALSE — flag peso manual vs báscula | Test: default FALSE | `balansoft-ws-local.sql:688`, migración 020 | MANEJO_DB.md §6 | IMPLEMENTADO | Peso manual solo ADMIN/SUPERVISOR |
| RB-WEIGH-005 | – | RB | WEIGHING | `boletos_pesaje.fotos_placa_tomadas` DEFAULT FALSE — fotos de placa una sola vez por boleto | Test: primera captura pone TRUE, segunda no pide | `balansoft-ws-local.sql:649`, migración 027:59-60 | MANEJO_DB.md, SEMAFORO.md | IMPLEMENTADO | Regla cliente: una sola vez |
| RB-WEIGH-006 | – | RB | WEIGHING | `boletos_pesaje.fecha_hora_entrada` NOT NULL — entrada obligatoria | Test: INSERT sin fecha falla | `balansoft-ws-local.sql:638` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-WEIGH-007 | – | RB | WEIGHING | `boletos_pesaje.multi_despacho_recepcion` DEFAULT FALSE — flag reservado/inactivo | Test: default FALSE | `balansoft-ws-local.sql:636` | MANEJO_DB.md §6.3 | IMPLEMENTADO | Columna inerte (DOCUMENTADO-NO-IMPLEMENTADO en lógica) |
| RB-WEIGH-008 | – | RB | WEIGHING | `boletos_pesaje.ediciones_count` DEFAULT 0 — contador de ediciones | Test: incrementa en UPDATE | `balansoft-ws-local.sql:665` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-009 | – | RB | WEIGHING | `imagenes_pesaje.boleto` FK CASCADE — imágenes se borran con boleto | Test: DELETE boleto borra imágenes | `balansoft-ws-local.sql:697` | – | IMPLEMENTADO | |
| RB-WEIGH-010 | – | RB | WEIGHING | `boletos_ediciones.estado_anterior` IN ('PENDIENTE','CERRADO','MODIFICADO') | Test: estado inválido rechazado | `balansoft-ws-local.sql:921-923`, migración 024 | MANEJO_DB.md | IMPLEMENTADO | No permite ANULADO como anterior |
| RB-WEIGH-011 | – | RB | WEIGHING | `boletos_ediciones.estado_nuevo` IN ('PENDIENTE','CERRADO','MODIFICADO') | Test: estado inválido rechazado | `balansoft-ws-local.sql:921-923` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-012 | – | RB | WEIGHING | `boletos_ediciones.edicion_numero` >= 1 — número de edición positivo | Test: 0 rechazado | `balansoft-ws-local.sql:925` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-013 | – | RB | WEIGHING | `boletos_ediciones.justificacion` TRIM >= 10 chars — motivo obligatorio mínimo 10 | Test: <10 chars rechazado | `balansoft-ws-local.sql:926` | MANEJO_DB.md, MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-WEIGH-014 | – | RB | WEIGHING | `boletos_ediciones` UNIQUE INDEX (sync_operation_id) WHERE NOT NULL — idempotencia sync | Test: mismo sync_op no duplica | `balansoft-ws-local.sql:935-937` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-015 | – | RB | WEIGHING | Series numeración: `series_numeracion.siguiente` contador transaccional, `activa` UNIQUE por empresa | Test: solo una activa, contador avanza FOR UPDATE | `balansoft-ws-local.sql` (mig 015), migración 015:13-37 | MANEJO_DB.md §6, MODELO_ESTANDAR.md | IMPLEMENTADO | Migración 015 crea tabla |

---

### Sección: CATALOG — Catálogos

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-CAT-001 | – | RB | CATALOG | `empresas.tamano_ticket_pdf` CHECK IN ('AUTOMATICO','GRANDE','MEDIANO','PEQUENO') | Test: valor inválido rechazado | `balansoft-ws-local.sql:106-107` | MANEJO_DB.md, Spec 001 REQ-FN-015 | IMPLEMENTADO | |
| RB-CAT-002 | – | RB | CATALOG | `empresas.fuente_ticket_pdf` CHECK IN ('DejaVu') — solo DejaVu permitida | Test: otra fuente rechazada | `balansoft-ws-local.sql:112-114` | MANEJO_DB.md, Spec 001 | IMPLEMENTADO | |
| RB-CAT-003 | – | RB | CATALOG | `empresas.protocolo_impresion` CHECK IN ('predeterminada_so','raw_9100','lpd_cups','nombre_impresora') | Test: protocolo inválido rechazado | `balansoft-ws-local.sql:119-124` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-004 | – | RB | CATALOG | `empresas.max_ediciones_boleto` CHECK (IS NULL OR >= 0) — no negativo | Test: -1 rechazado | `balansoft-ws-local.sql:129-131` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-005 | – | RB | CATALOG | `empresas.impresora_puerto` CHECK (IS NULL OR BETWEEN 1 AND 65535) | Test: puerto 0 o 65536 rechazado | `balansoft-ws-local.sql:136-138` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-006 | – | RB | CATALOG | `empresas.idioma` DEFAULT 'es' — idioma por defecto español | Test: default 'es' | `balansoft-ws-local.sql:51,86` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | |
| RB-CAT-007 | – | RB | CATALOG | `transportes.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL — código único por empresa | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:187-189` | MANEJO_DB.md | IMPLEMENTADO | Índice parcial |
| RB-CAT-008 | – | RB | CATALOG | `marcas.nombre` UNIQUE INDEX (id_empresa, nombre) — nombre único por empresa | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:202` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-009 | – | RB | CATALOG | `modelos_camion.nombre` UNIQUE INDEX (id_empresa, nombre) | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:215` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-010 | – | RB | CATALOG | `camiones.placa` UNIQUE INDEX (id_empresa, placa) — placa única por empresa | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:230` | MANEJO_DB.md, MODELO_ESTANDAR.md | IMPLEMENTADO | Regla: no dos boletos PENDIENTE misma placa |
| RB-CAT-011 | – | RB | CATALOG | `terceros.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:274-276` | MANEJO_DB.md | IMPLEMENTADO | Índice parcial |
| RB-CAT-012 | – | RB | CATALOG | `categorias.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:291-293` | MANEJO_DB.md | IMPLEMENTADO | Índice parcial |
| RB-CAT-013 | – | RB | CATALOG | `productos.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:311-313` | MANEJO_DB.md | IMPLEMENTADO | Índice parcial |
| RB-CAT-014 | – | RB | CATALOG | `productos.unidad_medida` DEFAULT 'TON' — unidad por defecto toneladas | Test: default 'TON' | `balansoft-ws-local.sql:303` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-CAT-015 | – | RB | CATALOG | `productos.es_kardex` DEFAULT FALSE — flag control kardex | Test: default FALSE | `balansoft-ws-local.sql:304` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-CAT-016 | – | RB | CATALOG | `almacenes.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:327-329` | MANEJO_DB.md | IMPLEMENTADO | Índice parcial |
| RB-CAT-017 | – | RB | CATALOG | `almacenes.stock_actual_ton` DEFAULT 0 — stock inicial cero | Test: default 0 | `balansoft-ws-local.sql:322` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-018 | – | RB | CATALOG | `balanzas.formato_trama` CHECK IN ('auto','json','ascii') — formatos válidos | Test: formato inválido rechazado | `balansoft-ws-local.sql:372-374`, mig 022 | MANEJO_DB.md, BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 022 |
| RB-CAT-019 | – | RB | CATALOG | `balanzas.baudrate` CHECK IN (1200,2400,4800,9600,19200,38400,57600,115200) | Test: baudrate inválido rechazado | `balansoft-ws-local.sql:377-381`, mig 022 | MANEJO_DB.md, BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-CAT-020 | – | RB | CATALOG | `balanzas.delimitador` CHECK IN ('lf','cr','crlf','stx_etx') | Test: delimitador inválido rechazado | `balansoft-ws-local.sql:384-388`, mig 022 | MANEJO_DB.md, BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-CAT-021 | – | RB | CATALOG | `balanzas.is_simulada` DEFAULT FALSE — flag báscula simulada | Test: default FALSE | `balansoft-ws-local.sql:341` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-022 | – | RB | CATALOG | `indicadores` mismos CHECKs que balanzas (formato_trama, baudrate, delimitador) | Test: mismos valores válidos | `balansoft-ws-local.sql:428-444`, mig 028 | MANEJO_DB.md, BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 028 separa indicador |
| RB-CAT-023 | – | RB | CATALOG | `conceptos_inventario.tipo_movimiento` CHECK IN ('ingreso','despacho','ajuste','ambos') | Test: tipo inválido rechazado | `balansoft-ws-local.sql:474-476`, mig 029 | MANEJO_DB.md | IMPLEMENTADO | Migración 029 |

---

### Sección: KARDEX — Kardex e Inventario

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-KAR-001 | – | RB | KARDEX | `kardex.id_movimiento` INTEGER NOT NULL — ID numérico (10=INGRESO, 60=DESPACHO, rangos 01-49 +, 50-99 -) | Test: IDs 10/60 funcionan, signo por rango | `balansoft-ws-local.sql:709`, mig 003:62 | MANEJO_DB.md §6, MODELO_ESTANDAR.md | IMPLEMENTADO | Kardex numérico sin tabla conceptos |
| RB-KAR-002 | – | RB | KARDEX | `kardex.valor` NUMERIC(12,2) NOT NULL — magnitud siempre positiva, signo por id_movimiento | Test: valor negativo rechazado | `balansoft-ws-local.sql:716` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-KAR-003 | – | RB | KARDEX | `kardex.fecha_kardex` NOT NULL — fecha obligatoria | Test: INSERT sin fecha falla | `balansoft-ws-local.sql:710` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-KAR-004 | – | RB | KARDEX | `kardex.id_empresa` FK NOT NULL — multi-tenancy obligatorio | Test: sin id_empresa falla | `balansoft-ws-local.sql:708` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-KAR-005 | – | RB | KARDEX | `kardex.boleto` FK a boletos_pesaje — trazabilidad a boleto origen | Test: FK válida | `balansoft-ws-local.sql:717` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-KAR-006 | – | RB | KARDEX | `kardex.id_concepto` FK nullable a conceptos_inventario — concepto opcional | Test: NULL permitido | `balansoft-ws-local.sql:715,464-465`, mig 029 | MANEJO_DB.md | IMPLEMENTADO | Migración 029 |
| RB-KAR-007 | – | RB | KARDEX | Anular CERRADO → movimiento inverso (10↔60) sin borrar original — en lógica servicio | Test: test_anular_cerrado_genera_inverso | `weighing_service.py:_registrar_kardex_inverso` | MANEJO_DB.md §6.3, MODELO_ESTANDAR.md | IMPLEMENTADO | Lógica en servicio, no BD |
| RB-KAR-008 | – | RB | KARDEX | Saldo = Σ positivos (01-49) − Σ negativos (50-99) a fecha corte — calculado, no persistido | Test: saldo coincide con fórmula | `weighing_service.py` | MANEJO_DB.md §6.3, MODELO_ESTANDAR.md | IMPLEMENTADO | No hay trigger ni columnas saldo |

---

### Sección: SYNC — Sincronización Offline-First

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SYNC-001 | – | RB | SYNC | `sync_queue.pendiente` DEFAULT TRUE — nuevas operaciones pendientes por defecto | Test: default TRUE | `balansoft-ws-local.sql:734` | MANEJO_DB.md §9, SESIONES.md | IMPLEMENTADO | |
| RB-SYNC-002 | – | RB | SYNC | `sync_queue.intentos` DEFAULT 0 — contador reintentos | Test: incrementa en fallo | `balansoft-ws-local.sql:735` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-SYNC-003 | – | RB | SYNC | `sync_queue.entidad` + `operacion` + `entidad_id` — clave lógica de idempotencia | Test: misma entidad/op/id no duplica | `balansoft-ws-local.sql:730-732` | MANEJO_DB.md | IMPLEMENTADO | Lógica en servicio |
| RB-SYNC-004 | – | RB | SYNC | `sync_logs.registros` + `errores` DEFAULT 0 — contadores por lote | Test: default 0 | `balansoft-ws-local.sql:746-747` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-SYNC-005 | – | RB | SYNC | Server: `sync_cola.pendiente` DEFAULT TRUE, `intentos` DEFAULT 0 — cola recepción central | Test: default TRUE/0 | `balansoft-ws-server.sql:142-143` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: LICENSE — Licencia y License Manager

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-LIC-001 | – | RB | LICENSE | `licencias.licencia_key` UNIQUE — clave licencia única global (formato BWS-XXXX-XXXX-XXXX) | Test: duplicado falla | `balansoft-ws-server.sql:37` | MANEJO_DB.md, PLANES-PAGOS.md | IMPLEMENTADO | |
| RB-LIC-002 | – | RB | LICENSE | `licencias.licencia_tier` NOT NULL — tier obligatorio (DEMO/MONOPUESTA/CENTRAL) | Test: NULL rechazado | `balansoft-ws-server.sql:38` | PLANES-PAGOS.md, SESIONES.md | IMPLEMENTADO | |
| RB-LIC-003 | – | RB | LICENSE | `licencias.licencia_status` CHECK IN ('ACTIVA','SUSPENDIDA','EXPIRADA','REVOCADA') DEFAULT 'ACTIVA' | Test: estado inválido rechazado | `balansoft-ws-server.sql:39` | PLANES-PAGOS.md, SESIONES.md | IMPLEMENTADO | |
| RB-LIC-004 | – | RB | LICENSE | `licencias.max_sesiones` INTEGER — límite sesiones concurrentes (NULL = ilimitado) | Test: NULL = ilimitado, número = tope | `balansoft-ws-server.sql:44`, mig 009 | SESIONES.md, PLANES-PAGOS.md | IMPLEMENTADO | Fuente única: `limite_sesiones_por_tier()` |
| RB-LIC-005 | – | RB | LICENSE | `licencias.hardware_id` — huella máquina para MONOPUESTA (1 equipo) | Test: MONOPUESTA valida hardware | `balansoft-ws-server.sql:46` | PLANES-PAGOS.md | IMPLEMENTADO | |
| RB-LIC-006 | – | RB | LICENSE | `empresas` snapshot licencia (licencia_key, tier, status, expira) — cache offline | Test: snapshot actualizado en login | `balansoft-ws-local.sql:66-69`, mig 010 | MANEJO_DB.md, SESIONES.md | IMPLEMENTADO | Migración 010 |
| RB-LIC-007 | – | RB | LICENSE | `llaves_activacion.codigo_hash` UNIQUE — SHA-256 de llave, un solo uso | Test: mismo hash no se inserta | `balansoft-ws-local.sql:882,898`, mig 025 | MANEJO_DB.md §13.7 | IMPLEMENTADO | Migración 025 |

---

### Sección: SESSIONS — Gestión de Sesiones

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SES-001 | – | RB | SESSIONS | `sesiones.token_hash` NOT NULL — hash del JWT almacenado | Test: INSERT sin hash falla | `balansoft-ws-server.sql:109` | SESIONES.md | IMPLEMENTADO | |
| RB-SES-002 | – | RB | SESSIONS | `sesiones.expira` NOT NULL — expiración obligatoria | Test: sin expiración falla | `balansoft-ws-server.sql:110` | SESIONES.md | IMPLEMENTADO | |
| RB-SES-003 | – | RB | SESSIONS | `sesiones.revocada` DEFAULT FALSE — revocación explícita | Test: default FALSE | `balansoft-ws-server.sql:111` | SESIONES.md | IMPLEMENTADO | Logout marca TRUE |

---

### Sección: SEMAFORO — Semáforo de Pesaje

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SEM-001 | – | RB | SEMAFORO | `semaforos.protocolo` CHECK IN ('http','serial') — solo HTTP/REST o USB serie | Test: protocolo inválido rechazado | `balansoft-ws-local.sql:508-510`, mig 026 | SEMAFORO.md | IMPLEMENTADO | Migración 026, Modbus/MQTT diferidos |
| RB-SEM-002 | – | RB | SEMAFORO | `semaforos.control_automatico` DEFAULT FALSE — modo manual por defecto | Test: default FALSE | `balansoft-ws-local.sql:494` | SEMAFORO.md | IMPLEMENTADO | App dueña de decisión |
| RB-SEM-003 | – | RB | SEMAFORO | `semaforos.umbral_cero_kg` DEFAULT 5.0 — umbral estabilidad para decisión | Test: default 5.0 | `balansoft-ws-local.sql:495` | SEMAFORO.md | IMPLEMENTADO | |
| RB-SEM-004 | – | RB | SEMAFORO | `semaforos.id_balanza` FK nullable — vínculo opcional a báscula para control auto | Test: NULL permitido, FK válida | `balansoft-ws-local.sql:493` | SEMAFORO.md | IMPLEMENTADO | |

---

### Sección: DEVICES — Dispositivos (Básculas, Indicadores, Cámaras, Impresoras, Barreras)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-DEV-001 | – | RB | DEVICES | `balanzas.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:352-354` | DISPOSITIVOS.md, BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Índice parcial |
| RB-DEV-002 | – | RB | DEVICES | `indicadores.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:412-414` | DISPOSITIVOS.md | IMPLEMENTADO | Índice parcial |
| RB-DEV-003 | – | RB | DEVICES | `semaforos.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:499-501` | DISPOSITIVOS.md, SEMAFORO.md | IMPLEMENTADO | Índice parcial |
| RB-DEV-004 | – | RB | DEVICES | `camaras.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:545-547` | DISPOSITIVOS.md | IMPLEMENTADO | Índice parcial |
| RB-DEV-005 | – | RB | DEVICES | `barreras.codigo` UNIQUE INDEX (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: duplicado misma empresa falla | `balansoft-ws-local.sql:589-591` | DISPOSITIVOS.md | IMPLEMENTADO | Índice parcial |
| RB-DEV-006 | – | RB | DEVICES | `camaras.ubicacion` CHECK IN ('entrada','salida','ambos') — dónde opera la cámara | Test: valor inválido rechazado | `balansoft-ws-local.sql:554-556`, mig 027/030 | DISPOSITIVOS.md | IMPLEMENTADO | Migración 027+030 |
| RB-DEV-007 | – | RB | DEVICES | `camaras.origen` CHECK IN ('ip','local') — IP (HTTP/JPEG) o local (USB/ffmpeg) | Test: valor inválido rechazado | `balansoft-ws-local.sql:561-563`, mig 030 | DISPOSITIVOS.md | IMPLEMENTADO | Migración 030 añade origen local |
| RB-DEV-008 | – | RB | DEVICES | `camaras.url_snapshot` NOT NULL DEFAULT '' — obligatoria solo para origen 'ip' | Test: IP sin URL falla en validación app | `balansoft-ws-local.sql:537` | DISPOSITIVOS.md | IMPLEMENTADO | Validación en endpoint |
| RB-DEV-009 | – | RB | DEVICES | `barreras.ubicacion` CHECK IN ('entrada','salida','ambos') | Test: valor inválido rechazado | `balansoft-ws-local.sql:605-607`, mig 032 | DISPOSITIVOS.md | IMPLEMENTADO | Migración 032 |
| RB-DEV-010 | – | RB | DEVICES | `barreras.tiempo_espera_segundos` DEFAULT 5 — tiempo apertura | Test: default 5 | `balansoft-ws-local.sql:583` | DISPOSITIVOS.md | IMPLEMENTADO | Migración 032 |
| RB-DEV-011 | – | RB | DEVICES | `barreras.comando_abrir` / `comando_cerrar` VARCHAR(255) — comandos personalizados | Test: comandos se envían | `balansoft-ws-local.sql:584-585`, mig 032 | DISPOSITIVOS.md | IMPLEMENTADO | Migración 032 |
| RB-DEV-012 | – | RB | DEVICES | `balanzas.id_indicador` FK nullable a indicadores — enlace opcional báscula→indicador | Test: NULL permitido, FK válida | `balansoft-ws-local.sql:417-418`, mig 028 | DISPOSITIVOS.md, BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 028 |
| RB-DEV-013 | – | RB | DEVICES | `balanzas.capacidad_max` / `division` NUMERIC(12,2) — metrología básica | Test: valores numéricos válidos | `balansoft-ws-local.sql:338-339` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-DEV-014 | – | RB | DEVICES | `indicadores.marca`/`modelo` VARCHAR(100) — catálogo marcas (BKG, CAS, Toledo, etc.) | Test: valores libres | `balansoft-ws-local.sql:398-399` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 028 |
| RB-DEV-015 | – | RB | DEVICES | `camaras.marca`/`modelo`/`fabricante` — info identificación cámara | Test: valores libres | `balansoft-ws-local.sql:531-533` | DISPOSITIVOS.md | IMPLEMENTADO | Migración 027/030/031 |
| RB-DEV-016 | – | RB | DEVICES | `semaforos.baudrate` / `barreras.baudrate` CHECK lista estándar (1200–115200) | Test: baudrate inválido rechazado | `balansoft-ws-local.sql:515-517,612-614` | DISPOSITIVOS.md, SEMAFORO.md | IMPLEMENTADO | |
| RB-DEV-017 | – | RB | DEVICES | `semaforos.is_simulado` / `barreras.is_simulado` / `camaras.is_simulada` DEFAULT FALSE | Test: default FALSE | `balansoft-ws-local.sql:486,574,534` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-DEV-018 | – | RB | DEVICES | `barreras.protocolo` CHECK IN ('http','serial') — mismos canales que semáforo | Test: protocolo inválido rechazado | `balansoft-ws-local.sql:598-600`, mig 032 | DISPOSITIVOS.md | IMPLEMENTADO | Migración 032 |

---

### Sección: AUDIT — Auditoría

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-AUD-001 | – | RB | AUDIT | `auditoria.detalle` JSONB — detalle flexible de cambios | Test: JSONB válido almacenado | `balansoft-ws-local.sql:762` | MANEJO_DB.md §12, USO-API.md | IMPLEMENTADO | |
| RB-AUD-002 | – | RB | AUDIT | Server: `auditoria_servidor.detalle` JSONB — auditoría eventos cuenta/licencia | Test: JSONB válido | `balansoft-ws-server.sql:161` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: I18N — Internacionalización

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-I18N-001 | – | RB | I18N | `empresas.idioma` DEFAULT 'es' CHECK length 5 — idioma empresa (es/en/pt) | Test: default 'es', ISO 639-1 | `balansoft-ws-local.sql:51,86` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | 621 claves por idioma en frontend |

---

### Sección: PRINTING — Impresión de Tickets

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-PRT-001 | – | RB | PRINTING | `empresas.formato_ticket` DEFAULT 'PDF' — PDF/TXT | Test: default 'PDF' | `balansoft-ws-local.sql:49` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-PRT-002 | – | RB | PRINTING | `empresas.formato_reporte` DEFAULT 'EXCEL' — EXCEL/PDF | Test: default 'EXCEL' | `balansoft-ws-local.sql:50` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-PRT-003 | – | RB | PRINTING | `empresas.tamano_ticket_pdf` CHECK ('AUTOMATICO','GRANDE','MEDIANO','PEQUENO') | Test: ver RB-CAT-001 | `balansoft-ws-local.sql:106-107` | MANEJO_DB.md, Spec 001 | IMPLEMENTADO | |
| RB-PRT-004 | – | RB | PRINTING | `empresas.fuente_ticket_pdf` CHECK ('DejaVu') — solo DejaVu Sans | Test: ver RB-CAT-002 | `balansoft-ws-local.sql:112-114` | MANEJO_DB.md, Spec 001 | IMPLEMENTADO | |
| RB-PRT-005 | – | RB | PRINTING | `empresas.protocolo_impresion` CHECK ('predeterminada_so','raw_9100','lpd_cups','nombre_impresora') | Test: ver RB-CAT-003 | `balansoft-ws-local.sql:119-124` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-PRT-006 | – | RB | PRINTING | `empresas.impresora_puerto` CHECK (1-65535) — puerto TCP válido | Test: ver RB-CAT-005 | `balansoft-ws-local.sql:136-138` | MANEJO_DB.md | IMPLEMENTADO | |

---

## FASE 2 — MODELOS ORM: REGLAS DE NEGOCIO Y RF EXTRAÍDAS

Fuentes: `backend/app/models/__init__.py` (1121 líneas, 45 modelos locales), `backend/app/models_server.py` (298 líneas, 10 modelos servidor)

### Sección: AUTH — Autenticación y Autorización (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-AUTH-013 | – | RB | AUTH | `IdentidadLocal.id` PK booleana DEFAULT TRUE — garantiza singleton (1 fila/máquina) | Test: 2da fila falla PK | `models/__init__.py:66` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| RB-AUTH-014 | – | RB | AUTH | `IdentidadLocal.rol_dispositivo` DEFAULT 'LOCAL' — valores 'LOCAL'/'SERVIDOR_LOCAL' | Test: default LOCAL | `models/__init__.py:76` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| RB-AUTH-015 | – | RB | AUTH | `Usuario.rol` DEFAULT 'OPERADOR' — 3 roles (ADMIN/OPERADOR/AUDITOR), TRABAJADOR fusionado | Test: default OPERADOR | `models/__init__.py:166` | MANEJO_DB.md §4, mig 025 | IMPLEMENTADO | |
| RB-AUTH-016 | – | RB | AUTH | `Usuario.id_empresa` FK NOT NULL — usuario siempre pertenece a empresa | Test: FK obligatoria | `models/__init__.py:159-161` | MANEJO_DB.md §4 | IMPLEMENTADO | |
| RB-AUTH-017 | – | RB | AUTH | `Usuario.password_hash` String(255) — caché local para login offline | Test: hash almacenado | `models/__init__.py:165` | MANEJO_DB.md §9 | IMPLEMENTADO | |
| RB-AUTH-018 | – | RB | AUTH | `Empresa.activa` DEFAULT TRUE — empresa activa por defecto | Test: default TRUE | `models/__init__.py:140` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUTH-019 | – | RB | AUTH | `PermisoAcceso` PK compuesta (id_empresa, rol, modulo) — matriz 18 módulos × 3 roles | Test: PK compuesta | `models/__init__.py:1116-1121` | MANEJO_DB.md §12 | IMPLEMENTADO | |
| RB-AUTH-020 | – | RB | AUTH | `PermisoAcceso.acceso` DEFAULT 'ver' — acceso base lectura | Test: default 'ver' | `models/__init__.py:1121` | MANEJO_DB.md §12 | IMPLEMENTADO | |
| RB-AUTH-021 | – | RB | AUTH | Server: `Dispositivo.estado` CHECK ('PENDIENTE','APROBADO','RECHAZADO') DEFAULT 'APROBADO' — RB-12 | Test: estados válidos, default APROBADO | `models_server.py:106-110,130-132` | SESIONES.md, MANEJO_DB.md | IMPLEMENTADO | Aprobación equipos CENTRAL |
| RB-AUTH-022 | – | RB | AUTH | Server: `Dispositivo.rol_sesion` CHECK ('ADMIN','OPERADOR','AUDITOR') — rol asignado al aprobar | Test: rol válido asignado | `models_server.py:110,134` | SESIONES.md | IMPLEMENTADO | |
| RB-AUTH-023 | – | RB | AUTH | Server: `Dispositivo.rol_dispositivo` DEFAULT 'LOCAL' — 'LOCAL'/'SERVIDOR_LOCAL' | Test: default LOCAL | `models_server.py:127` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| RB-AUTH-024 | – | RB | AUTH | Server: `Credencial.rol_global` DEFAULT 'OPERADOR' — rol global para login central | Test: default OPERADOR | `models_server.py:161` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUTH-025 | – | RB | AUTH | Server: `ProveedorUsuario.rol` DEFAULT 'SOPORTE' — SUPERADMIN/SOPORTE/VENTAS | Test: default SOPORTE | `models_server.py:293` | – | IMPLEMENTADO | Panel proveedor |

---

### Sección: WEIGHING — Pesaje (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-WEIGH-016 | – | RB | WEIGHING | `BoletoPesaje.ESTADO_*` constantes: PENDIENTE/CERRADO/MODIFICADO/ANULADO + alias COMPLETADO=CERRADO | Test: constantes definidas | `models/__init__.py:783-787` | MODELO_ESTANDAR.md | IMPLEMENTADO | Normalización legacy en servicio |
| RB-WEIGH-017 | – | RB | WEIGHING | `BoletoPesaje.numero_boleto` UNIQUE nullable — único si existe, no reutilizable | Test: duplicado falla | `models/__init__.py:790` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-WEIGH-018 | – | RB | WEIGHING | `BoletoPesaje.id_serie` FK nullable a series_numeracion — serie opcional por boleto | Test: FK válida o NULL | `models/__init__.py:794-796` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-WEIGH-019 | – | RB | WEIGHING | `BoletoPesaje.peso_entrada_vehiculo` Numeric(12,2) NOT NULL — peso entrada obligatorio | Test: NOT NULL | `models/__init__.py:824` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-WEIGH-020 | – | RB | WEIGHING | `BoletoPesaje.fotos_placa_tomadas` DEFAULT FALSE — flag 1 vez por boleto | Test: default FALSE | `models/__init__.py:835-837` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-021 | – | RB | WEIGHING | `BoletoPesaje.ediciones_count` DEFAULT 0 — contador ediciones | Test: default 0, incrementa | `models/__init__.py:855-857` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-022 | – | RB | WEIGHING | `BoletoPesaje.es_peso_manual` DEFAULT FALSE — marca peso manual (auditado en ticket) | Test: default FALSE | `models/__init__.py:881` | MANEJO_DB.md | IMPLEMENTADO | Peso manual = flag + auditoría |
| RB-WEIGH-023 | – | RB | WEIGHING | `BoletoPesaje.sincronizado` DEFAULT FALSE — flag sync offline | Test: default FALSE | `models/__init__.py:882` | MANEJO_DB.md §9 | IMPLEMENTADO | |
| RB-WEIGH-024 | – | RB | WEIGHING | `SerieNumeracion.activa` DEFAULT FALSE — solo 1 activa por empresa (UNIQUE INDEX parcial) | Test: 1 activa max | `models/__init__.py:766` + mig 015 | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-WEIGH-025 | – | RB | WEIGHING | `SerieNumeracion.siguiente` INTEGER NOT NULL — contador transaccional (FOR UPDATE en servicio) | Test: avanza atómicamente | `models/__init__.py:764` | MANEJO_DB.md §6 | IMPLEMENTADO | Lógica en weighing_service |
| RB-WEIGH-026 | – | RB | WEIGHING | `BoletoEdicion` historial inmutable — justificación obligatoria, no actualizable/borrable | Test: justificación ≥10, inmutable | `models/__init__.py:959-998` | MANEJO_DB.md, MODELO_ESTANDAR.md | IMPLEMENTADO | Migración 024 |
| RB-WEIGH-027 | – | RB | WEIGHING | `BoletoEdicion.estado_anterior/nuevo` IN ('PENDIENTE','CERRADO','MODIFICADO') — CHECK | Test: inválido rechazado | `models/__init__.py:989-990` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-028 | – | RB | WEIGHING | `BoletoEdicion.edicion_numero` >= 1 — secuencia edición por boleto | Test: ≥1 | `models/__init__.py:992` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-029 | – | RB | WEIGHING | `BoletoEdicion.justificacion` String(500) NOT NULL — motivo obligatorio | Test: NOT NULL | `models/__init__.py:988` | MANEJO_DB.md | IMPLEMENTADO | Migración 024 exige ≥10 |
| RB-WEIGH-030 | – | RB | WEIGHING | `BoletoEdicion.sync_operation_id` UNIQUE INDEX WHERE NOT NULL — idempotencia sync | Test: mismo op no duplica | `models/__init__.py:993-995` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-031 | – | RB | WEIGHING | `BoletoPesaje` campos cálculo: PTE/PTS/PNT/PND/PDF/PDV + legacy bruto/tara/dif — firmados en servicio | Test: cálculos coinciden MODEL.md | `models/__init__.py:862-877` | MODELO_ESTANDAR.md | IMPLEMENTADO | Lógica en weighing_service |
| RB-WEIGH-032 | – | RB | WEIGHING | `ImagenPesaje.boleto` FK CASCADE — imágenes borradas con boleto | Test: CASCADE funciona | `models/__init__.py:1042-1044` | – | IMPLEMENTADO | |
| RB-WEIGH-033 | – | RB | WEIGHING | `PasswordResetToken.token_hash` SHA-256 — token único recuperación (solo hash) | Test: hash almacenado | `models/__init__.py:1010` | – | IMPLEMENTADO | |

---

### Sección: CATALOG — Catálogos (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-CAT-024 | – | RB | CATALOG | Helper `_idx_codigo_empresa()` — índice único parcial (id_empresa, codigo) WHERE codigo IS NOT NULL | Test: índice creado en 8 modelos | `models/__init__.py:39-53` | MANEJO_DB.md | IMPLEMENTADO | Patrón reutilizable |
| RB-CAT-025 | – | RB | CATALOG | `Empresa.formato_ticket` DEFAULT 'PDF' server_default='PDF' | Test: default 'PDF' | `models/__init__.py:100-102` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-026 | – | RB | CATALOG | `Empresa.formato_reporte` DEFAULT 'EXCEL' server_default='EXCEL' | Test: default 'EXCEL' | `models/__init__.py:103-105` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-027 | – | RB | CATALOG | `Empresa.idioma` DEFAULT 'es' server_default='es' NOT NULL | Test: default 'es' | `models/__init__.py:106-108` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | |
| RB-CAT-028 | – | RB | CATALOG | `Empresa.tamano_ticket_pdf` DEFAULT 'AUTOMATICO' server_default='AUTOMATICO' | Test: default AUTOMATICO | `models/__init__.py:112-114` | Spec 001 REQ-FN-015 | IMPLEMENTADO | |
| RB-CAT-029 | – | RB | CATALOG | `Empresa.fuente_ticket_pdf` DEFAULT 'DejaVu' server_default='DejaVu' | Test: default DejaVu | `models/__init__.py:115-117` | Spec 001 REQ-FN-014 | IMPLEMENTADO | |
| RB-CAT-030 | – | RB | CATALOG | `Empresa.max_ediciones_boleto` NULLABLE — NULL/0 = sin tope (ADMIN no sujeto) | Test: NULL = ilimitado | `models/__init__.py:120` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-031 | – | RB | CATALOG | `Empresa.fotos_placa_activas/obligatorias` DEFAULT FALSE — config fotos placa | Test: defaults FALSE | `models/__init__.py:130-135` | MANEJO_DB.md | IMPLEMENTADO | Migración 027 |
| RB-CAT-032 | – | RB | CATALOG | `Empresa.licencia_*` snapshot (key, tier, status, expira) — cache offline | Test: actualizado en login | `models/__init__.py:136-139` | SESIONES.md | IMPLEMENTADO | |
| RB-CAT-033 | – | RB | CATALOG | `Empresa.usuarios` relationship cascade="all, delete-orphan" — usuarios borrados con empresa | Test: cascade funciona | `models/__init__.py:148-150` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-034 | – | RB | CATALOG | `Producto.es_kardex` DEFAULT FALSE — flag control inventario | Test: default FALSE | `models/__init__.py:358` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-CAT-035 | – | RB | CATALOG | `Producto.unidad_medida` DEFAULT 'TON' — unidad base | Test: default 'TON' | `models/__init__.py:355` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-CAT-036 | – | RB | CATALOG | `Producto.tolerancia` Numeric(8,4) nullable — % tolerancia comercial | Test: nullable | `models/__init__.py:359` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-CAT-037 | – | RB | CATALOG | `Producto.peso_unidad` Numeric(12,4) nullable — kg por unidad (para conversión) | Test: nullable | `models/__init__.py:360` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-CAT-038 | – | RB | CATALOG | `Almacen.stock_actual_ton` DEFAULT 0 NOT NULL — stock inicial cero | Test: default 0 | `models/__init__.py:384-386` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-039 | – | RB | CATALOG | `Balanza.formato_trama` DEFAULT 'auto' NOT NULL — auto|json|ascii | Test: default 'auto' | `models/__init__.py:419-421` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 022 |
| RB-CAT-040 | – | RB | CATALOG | `Balanza.baudrate` DEFAULT 9600 NOT NULL — serial | Test: default 9600 | `models/__init__.py:423-425` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-CAT-041 | – | RB | CATALOG | `Balanza.delimitador` nullable — lf|cr|crlf|stx_etx, NULL=lf | Test: NULL = lf | `models/__init__.py:427` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-CAT-042 | – | RB | CATALOG | `Balanza.id_indicador` FK nullable — enlace opcional a Indicador (mig 028) | Test: NULL o FK válida | `models/__init__.py:430-432` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Compatibilidad legacy |
| RB-CAT-043 | – | RB | CATALOG | `Indicador` mismos campos comms que Balanza — entidad separada terminal vs plataforma | Test: campos idénticos | `models/__init__.py:628-641` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 028 |
| RB-CAT-044 | – | RB | CATALOG | `VinculoBalanzaIndicador` PK + 2 UNIQUE (id_bascula, id_indicador) — 1:1 bidireccional | Test: 1 báscula = 1 indicador max | `models/__init__.py:652-656` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 028, tabla explícita |
| RB-CAT-045 | – | RB | CATALOG | `ConceptoInventario.tipo_movimiento` nullable CHECK ('ingreso','despacho','ajuste','ambos') | Test: valores válidos | `models/__init__.py:704` | MANEJO_DB.md | IMPLEMENTADO | Migración 029 |

---

### Sección: KARDEX — Kardex e Inventario (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-KAR-009 | – | RB | KARDEX | `Kardex.KARDEX_INGRESO = 10`, `KARDEX_DESPACHO = 60` — constantes en modelo | Test: constantes accesibles | `models/__init__.py:1066-1067` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-KAR-010 | – | RB | KARDEX | `Kardex.RANGO_NEGATIVO_DESDE = 50` — límite rangos negativos | Test: constante 50 | `models/__init__.py:1069` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-KAR-011 | – | RB | KARDEX | `Kardex.valor` Numeric(12,2) NOT NULL — magnitud positiva (signo por id_movimiento) | Test: NOT NULL, >0 | `models/__init__.py:1092` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-KAR-012 | – | RB | KARDEX | `Kardex.id_concepto` FK nullable a conceptos_inventario — concepto opcional | Test: NULL permitido | `models/__init__.py:1089-1091` | MANEJO_DB.md | IMPLEMENTADO | Migración 029 |
| RB-KAR-013 | – | RB | KARDEX | `Kardex.boleto` FK nullable — trazabilidad a boleto origen | Test: FK válida o NULL | `models/__init__.py:1093-1095` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-KAR-014 | – | RB | KARDEX | Cálculo signo por rango: 01-49 positivo, 50-99 negativo — en lógica servicio | Test: signo correcto | `models/__init__.py:1068-1070` + service | MODELO_ESTANDAR.md | IMPLEMENTADO | No CHECK en BD, lógica servicio |

---

### Sección: SYNC — Sincronización (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SYNC-006 | – | RB | SYNC | `SyncQueue.payload` JSONB DEFAULT {} — payload flexible | Test: default {} | `models/__init__.py:907` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-SYNC-007 | – | RB | SYNC | `SyncQueue.pendiente` DEFAULT TRUE, `intentos` DEFAULT 0 — cola con reintentos | Test: defaults | `models/__init__.py:908-909` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-SYNC-008 | – | RB | SYNC | Server: `SyncColaItem.payload` JSONB (sin default) — cola recepción central | Test: JSONB requerido | `models_server.py:233` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: LICENSE — Licencia (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-LIC-008 | – | RB | LICENSE | `Licencia.licencia_key` UNIQUE — BWS-XXXX-XXXX-XXXX | Test: UNIQUE | `models_server.py:77` | PLANES-PAGOS.md | IMPLEMENTADO | |
| RB-LIC-009 | – | RB | LICENSE | `Licencia.licencia_tier` NOT NULL String(20) — DEMO/MONOPUESTA/CENTRAL | Test: NOT NULL | `models_server.py:78` | PLANES-PAGOS.md | IMPLEMENTADO | |
| RB-LIC-010 | – | RB | LICENSE | `Licencia.licencia_status` DEFAULT 'ACTIVA' — CHECK en BD server | Test: default ACTIVA | `models_server.py:79` | PLANES-PAGOS.md | IMPLEMENTADO | |
| RB-LIC-011 | – | RB | LICENSE | `Licencia.max_sesiones` NULLABLE — límite sesiones (NULL = ilimitado) | Test: NULL = ilimitado | `models_server.py:84` | SESIONES.md | IMPLEMENTADO | Fuente única: `limite_sesiones_por_tier()` |
| RB-LIC-012 | – | RB | LICENSE | `Licencia.hardware_id` NULLABLE — huella para MONOPUESTA | Test: MONOPUESTA valida | `models_server.py:85` | PLANES-PAGOS.md | IMPLEMENTADO | |
| RB-LIC-013 | – | RB | LICENSE | `LlaveActivacion.codigo_hash` UNIQUE — SHA-256, un solo uso | Test: UNIQUE hash | `models/__init__.py:28` (import) | MANEJO_DB.md §13.7 | IMPLEMENTADO | Modelo en llave_activacion.py |
| RB-LIC-014 | – | RB | LICENSE | `LlaveActivacion.estado` CHECK ('activa','consumida','revocada') DEFAULT 'activa' | Test: estados válidos | `models/llave_activacion.py` | MANEJO_DB.md §13.7 | IMPLEMENTADO | Migración 025 |

---

### Sección: SESSIONS — Sesiones (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SES-004 | – | RB | SESSIONS | `Sesion.token_hash` String(128) NOT NULL — hash JWT | Test: NOT NULL | `models_server.py:186` | SESIONES.md | IMPLEMENTADO | |
| RB-SES-005 | – | RB | SESSIONS | `Sesion.expira` DateTime NOT NULL — expiración obligatoria | Test: NOT NULL | `models_server.py:187` | SESIONES.md | IMPLEMENTADO | |
| RB-SES-006 | – | RB | SESSIONS | `Sesion.revocada` DEFAULT FALSE — revocación explícita | Test: default FALSE | `models_server.py:188` | SESIONES.md | IMPLEMENTADO | |

---

### Sección: SEMAFORO — Semáforo (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SEM-005 | – | RB | SEMAFORO | `Semaforo.protocolo` DEFAULT 'http' server_default='http' NOT NULL | Test: default 'http' | `models/__init__.py:467-469` | SEMAFORO.md | IMPLEMENTADO | |
| RB-SEM-006 | – | RB | SEMAFORO | `Semaforo.baudrate` DEFAULT 9600 server_default='9600' NOT NULL | Test: default 9600 | `models/__init__.py:473-475` | SEMAFORO.md | IMPLEMENTADO | |
| RB-SEM-007 | – | RB | SEMAFORO | `Semaforo.control_automatico` DEFAULT FALSE server_default='false' NOT NULL | Test: default FALSE | `models/__init__.py:481-483` | SEMAFORO.md | IMPLEMENTADO | |
| RB-SEM-008 | – | RB | SEMAFORO | `Semaforo.umbral_cero_kg` DEFAULT 5.0 server_default='5.0' NOT NULL Numeric(10,2) | Test: default 5.0 | `models/__init__.py:485-490` | SEMAFORO.md | IMPLEMENTADO | |
| RB-SEM-009 | – | RB | SEMAFORO | `Semaforo.id_balanza` FK nullable — báscula para control automático | Test: NULL o FK válida | `models/__init__.py:477-479` | SEMAFORO.md | IMPLEMENTADO | |

---

### Sección: DEVICES — Dispositivos (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-DEV-019 | – | RB | DEVICES | `Balanza.is_simulada` DEFAULT FALSE — flag simulación | Test: default FALSE | `models/__init__.py:413` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-DEV-020 | – | RB | DEVICES | `Balanza.protocolo` DEFAULT 'tcp' — tcp|serial | Test: default 'tcp' | `models/__init__.py:417` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-DEV-021 | – | RB | DEVICES | `Indicador.is_simulado` DEFAULT FALSE | Test: default FALSE | `models/__init__.py:627` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-DEV-022 | – | RB | DEVICES | `Indicador.protocolo` DEFAULT 'tcp' nullable | Test: default 'tcp' | `models/__init__.py:628` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-DEV-023 | – | RB | DEVICES | `Semaforo.is_simulado` DEFAULT FALSE | Test: default FALSE | `models/__init__.py:465` | SEMAFORO.md | IMPLEMENTADO | |
| RB-DEV-024 | – | RB | DEVICES | `Camara.origen` DEFAULT 'ip' server_default='ip' NOT NULL — ip|local | Test: default 'ip' | `models/__init__.py:527-529` | DISPOSITIVOS.md | IMPLEMENTADO | Migración 030 |
| RB-DEV-025 | – | RB | DEVICES | `Camara.url_snapshot` DEFAULT '' NOT NULL — obligatoria si origen='ip' | Test: default '' | `models/__init__.py:531` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-DEV-026 | – | RB | DEVICES | `Camara.dispositivo` NULLABLE — ruta /dev/video* para origen='local' | Test: NULL si IP | `models/__init__.py:533` | DISPOSITIVOS.md | IMPLEMENTADO | ffmpeg capture |
| RB-DEV-027 | – | RB | DEVICES | `Camara.ubicacion` DEFAULT 'ambos' server_default='ambos' NOT NULL | Test: default 'ambos' | `models/__init__.py:539-541` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-DEV-028 | – | RB | DEVICES | `Camara.password` nullable — NUNCA devuelta por API (solo hash en BD) | Test: API no devuelve | `models/__init__.py:537` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-DEV-029 | – | RB | DEVICES | `Barrera.protocolo` DEFAULT 'http' NOT NULL | Test: default 'http' | `models/__init__.py:571-573` | DISPOSITIVOS.md | IMPLEMENTADO | Migración 032 |
| RB-DEV-030 | – | RB | DEVICES | `Barrera.tiempo_espera_segundos` DEFAULT 5 server_default='5' | Test: default 5 | `models/__init__.py:586-588` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-DEV-031 | – | RB | DEVICES | `Barrera.control_automatico` DEFAULT FALSE | Test: default FALSE | `models/__init__.py:583-585` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-DEV-032 | – | RB | DEVICES | `Barrera.comando_abrir/cerrar` VARCHAR(255) nullable — comandos personalizados | Test: strings enviados | `models/__init__.py:589-590` | DISPOSITIVOS.md | IMPLEMENTADO | |

---

### Sección: AUDIT — Auditoría (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-AUD-003 | – | RB | AUDIT | `Auditoria.detalle` JSON (no JSONB en ORM) — detalle cambios | Test: JSON serializable | `models/__init__.py:952` | MANEJO_DB.md | IMPLEMENTADO | JSON vs JSONB en BD |
| RB-AUD-004 | – | RB | AUDIT | `Auditoria.id_empresa` NULLABLE — opcional (eventos sin empresa) | Test: NULL permitido | `models/__init__.py:948` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUD-005 | – | RB | AUDIT | Server: `AuditoriaServidor.detalle` JSONB — eventos cuenta/licencia | Test: JSONB | `models_server.py:260` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUD-006 | – | RB | AUDIT | `BoletoEdicion.campos_modificados` JSON — diff antes/después | Test: JSON diff | `models/__init__.py:991` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: REPORTS — Reportes (ORM)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| *(sin modelos específicos)* | – | – | REPORTS | Reportes generados vía consultas SQL dinámicas en `report_service.py` — sin modelos ORM dedicados | Test: report_service tests | `services/report_service.py` | MANEJO_DB.md, USO-API.md | IMPLEMENTADO | Solo servicio, no modelos |

---

## FASE 3 — ESQUEMAS PYDANTIC: VALIDACIONES DE ENTRADA (RB) EXTRAÍDAS

Fuente: `backend/app/schemas/__init__.py` (1407 líneas), `backend/app/schemas/vinculos.py` (21 líneas)

### Sección: AUTH — Autenticación y Autorización (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-AUTH-026 | – | RB | AUTH | `RegisterRequest`: empresa_nombre 3-255, empresa_rif 5-20, usuario_nombre 3-150, password 6-128, licencia_key 1-255 | Test: límites válidos/inválidos | `schemas/__init__.py:18-23` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUTH-027 | – | RB | AUTH | `LoginRequest`: EmailStr + password + hardware/device info opcional | Test: email válido requerido | `schemas/__init__.py:27-34` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUTH-028 | – | RB | AUTH | `LoginCentralRequest.modo_solicitado` Literal['SERVIDOR','TRABAJADOR','OPERADOR'] — TRABAJADOR alias de OPERADOR | Test: alias TRABAJADOR=OPERADOR | `schemas/__init__.py:57` | MANEJO_DB.md, migración 025 | IMPLEMENTADO | Alias para instaladores legacy |
| RB-AUTH-029 | – | RB | AUTH | `ValidateLicenseRequest`: licencia_key opcional + hardware_id + device info | Test: valida sin licencia_key si hay cache | `schemas/__init__.py:60-66` | SESIONES.md | IMPLEMENTADO | Cache offline |
| RB-AUTH-030 | – | RB | AUTH | `ForgotPasswordRequest`: EmailStr único | Test: email válido | `schemas/__init__.py:69-70` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUTH-031 | – | RB | AUTH | `ResetPasswordRequest`: token 10-128 chars, new_password 6-128 | Test: longitudes válidas | `schemas/__init__.py:73-75` | MANEJO_DB.md | IMPLEMENTADO | Token de un solo uso |
| RB-AUTH-032 | – | RB | AUTH | `UserOut` / `CompanyOut` from_attributes=True — serialización ORM→API | Test: respuesta API correcta | `schemas/__init__.py:85-116` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-AUTH-033 | – | RB | AUTH | `CompanyOut.tamano_ticket_pdf` Literal['AUTOMATICO','GRANDE','MEDIANO','PEQUENO'] DEFAULT 'AUTOMATICO' | Test: default AUTOMATICO | `schemas/__init__.py:114` | Spec 001 REQ-FN-015 | IMPLEMENTADO | Spec 001 trazabilidad |
| RB-AUTH-034 | – | RB | AUTH | `CompanyOut.fuente_ticket_pdf` Literal['DejaVu'] DEFAULT 'DejaVu' | Test: default DejaVu | `schemas/__init__.py:115` | Spec 001 REQ-FN-014 | IMPLEMENTADO | Spec 001 trazabilidad |
| RB-AUTH-035 | – | RB | AUTH | `LicenseInfoOut.features` dict default_factory=dict — features no gatean (solo info) | Test: dict vacío si no hay | `schemas/__init__.py:133` | PLANES-PAGOS.md | IMPLEMENTADO | Contradicción TERMINOS §4.1 |

---

### Sección: CATALOG — Catálogos (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-CAT-046 | – | RB | CATALOG | `CamionCreate.placa` 2-20 chars obligatoria | Test: <2 o >20 rechaza | `schemas/__init__.py:158` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-CAT-047 | – | RB | CATALOG | `MarcaCreate.nombre` 2-100 chars obligatoria | Test: límites | `schemas/__init__.py:173` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-048 | – | RB | CATALOG | `ModeloCamionCreate.nombre` 2-100 chars, capacidad_carga_ton opcional Decimal | Test: nombre obligatorio | `schemas/__init__.py:188` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-049 | – | RB | CATALOG | `RemolqueCreate.placa` 2-20 chars obligatoria | Test: límites | `schemas/__init__.py:204` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-CAT-050 | – | RB | CATALOG | `TransporteCreate.razon_social` min 2 chars obligatoria, codigo opcional | Test: razon_social requerida | `schemas/__init__.py:221` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-051 | – | RB | CATALOG | `ConductorCreate.cedula_dni` 4-20 chars, nombre_completo min 3 | Test: cédula formato | `schemas/__init__.py:236` | MANEJO_DB.md | IMPLEMENTADO | PK cédula en BD |
| RB-CAT-052 | – | RB | CATALOG | `CategoriaCreate.nombre` min 2, codigo opcional, activo default TRUE | Test: default activo | `schemas/__init__.py:251-255` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-053 | – | RB | CATALOG | `ProductoCreate.id_categoria` UUID obligatorio (FK), unidad_medida max 20 default 'TON' | Test: FK requerida | `schemas/__init__.py:274-281` | MODELO_ESTANDAR.md | IMPLEMENTADO | Migración 013: id_categoria NOT NULL |
| RB-CAT-054 | – | RB | CATALOG | `ProductoCreate.tolerancia` / `peso_unidad` Decimal nullable — tolerancia comercial % | Test: nullable | `schemas/__init__.py:283-284` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-CAT-055 | – | RB | CATALOG | `AlmacenCreate.stock_actual_ton` Decimal nullable | Test: nullable | `schemas/__init__.py:301` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-056 | – | RB | CATALOG | `BalanzaCreate`: puerto_tcp gt=0 le=65535, protocolo pattern '^(tcp|serial)$', formato_trama pattern '^(auto|json|ascii)$', baudrate Field(9600) + validator, delimitador pattern '^(lf|cr|crlf|stx_etx)$' | Test: validators coinciden CHECKs BD | `schemas/__init__.py:336-340,344-355` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Validators evitan IntegrityError |
| RB-CAT-057 | – | RB | CATALOG | `BalanzaCreate.id_indicador` UUID nullable — enlace opcional a Indicador (mig 028) | Test: NULL o FK válida | `schemas/__init__.py:342` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Compatibilidad legacy |
| RB-CAT-058 | – | RB | CATALOG | `SemaforoCreate`: protocolo pattern '^(http|serial)$', puerto_tcp gt=0 le=65535, baudrate 9600 + validator, id_balanza UUID nullable, umbral_cero_kg Decimal ge=0 le=100000 default 5.0 | Test: validators | `schemas/__init__.py:410-417,419-429` | SEMAFORO.md | IMPLEMENTADO | |
| RB-CAT-059 | – | RB | CATALOG | `SemaforoComandoIn`: color/luz Literal['rojo','amarillo','verde'], action Literal['on','off','flash'], atajos planos (rojo/amarillo/verde bool|action), zumbador, all, reset, automatico — SPEC §4/§5.6 | Test: todos formatos SPEC aceptados | `schemas/__init__.py:464-474` | SEMAFORO.md | IMPLEMENTADO | Contrato JSON normalizado |
| RB-CAT-060 | – | RB | CATALOG | `CamaraCreate`: origen Literal['ip','local'], url_snapshot max 500 (obligatoria si ip), dispositivo max 255 (obligatoria si local), password max 255, ubicacion Literal['entrada','salida','ambos'] | Test: validación condicional en endpoint | `schemas/__init__.py:541-548` | DISPOSITIVOS.md | IMPLEMENTADO | Migración 027+030 |
| RB-CAT-061 | – | RB | CATALOG | `CamaraOut.password_configurada` bool — password NUNCA se expone en API | Test: API no devuelve password | `schemas/__init__.py:530` | DISPOSITIVOS.md | IMPLEMENTADO | Seguridad |
| RB-CAT-062 | – | RB | CATALOG | `IndicadorCreate`: protocolo pattern '^(tcp|serial)$', formato_trama pattern '^(auto|json|ascii)$', baudrate 9600 + validator, delimitador pattern '^(lf|cr|crlf|stx_etx)$' | Test: validators coinciden BD | `schemas/__init__.py:619-625,627-637` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 028 |
| RB-CAT-063 | – | RB | CATALOG | `ConceptoInventarioCreate.tipo_movimiento` pattern '^(ingreso|despacho|ajuste|ambos)$' | Test: valores válidos | `schemas/__init__.py:662-664` | MANEJO_DB.md | IMPLEMENTADO | Migración 029 |
| RB-CAT-064 | – | RB | CATALOG | `BarreraCreate`: protocolo pattern '^(http|serial)$', puerto_tcp gt=0 le=65535, ubicacion pattern '^(entrada|salida|ambos)$', tiempo_espera_segundos ge=1 le=3600 default 5, comando_abrir/cerrar max 255, baudrate validator | Test: validators | `schemas/__init__.py:698-707,709-718` | DISPOSITIVOS.md | IMPLEMENTADO | Migración 032 |
| RB-CAT-065 | – | RB | CATALOG | `BarreraUpdate`: campos opcionales con mismos validators, baudrate nullable + validator | Test: partial update | `schemas/__init__.py:721-748` | DISPOSITIVOS.md | IMPLEMENTADO | |
| RB-CAT-066 | – | RB | CATALOG | `TerceroCreate.tipo` pattern '^(CLIENTE|PROVEEDOR|AMBOS)$', email EmailStr nullable | Test: tipo válido | `schemas/__init__.py:799` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-CAT-067 | – | RB | CATALOG | `CatalogSyncResponse`: paginación H11 — `totales` dict reales, `truncado` bool si recortado por limit | Test: totales + truncado | `schemas/__init__.py:807-824` | MANEJO_DB.md | IMPLEMENTADO | H11 paginación |

---

### Sección: WEIGHING — Pesaje (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-WEIGH-034 | – | RB | WEIGHING | `WeighingCreate.id_vehiculo` 1-20 chars obligatorio (placa chuto) | Test: obligatorio | `schemas/__init__.py:834` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-WEIGH-035 | – | RB | WEIGHING | `WeighingCreate.peso_entrada_vehiculo` Decimal ge=0 (validator _no_negativo) | Test: <0 rechaza | `schemas/__init__.py:860,873-878` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-WEIGH-036 | – | RB | WEIGHING | `WeighingCreate`: creación inline (get-or-create) — remolque_placa, transporte_nombre, conductor_cedula/nombre, producto_nombre, almacen_nombre, balanza_nombre, tercero_nombre | Test: crea si no existe | `schemas/__init__.py:847-855` | MANEJO_DB.md | IMPLEMENTADO | Operador no pre-carga catálogos |
| RB-WEIGH-037 | – | RB | WEIGHING | `WeighingCreate.es_peso_manual` default FALSE — solo ADMIN/SUPERVISOR en endpoint | Test: default FALSE | `schemas/__init__.py:858` | MANEJO_DB.md | IMPLEMENTADO | Permiso en endpoint |
| RB-WEIGH-038 | – | RB | WEIGHING | `WeighingClose`: peso_salida_vehiculo ge=0, fecha_hora_salida default now(UTC) | Test: ge=0 | `schemas/__init__.py:882-885` | MODELO_ESTANDAR.md | IMPLEMENTADO | |
| RB-WEIGH-039 | – | RB | WEIGHING | `WeighingAnular.motivo` min 10 max 500 chars — motivo obligatorio | Test: <10 rechaza | `schemas/__init__.py:901` | MODELO_ESTANDAR.md | IMPLEMENTADO | Migración 024 ≥10 |
| RB-WEIGH-040 | – | RB | WEIGHING | `WeighingUpdate.justificacion` min 10 max 500 — obligatoria al editar | Test: obligatoria | `schemas/__init__.py:917` | MANEJO_DB.md | IMPLEMENTADO | Registra en boletos_ediciones |
| RB-WEIGH-041 | – | RB | WEIGHING | `BoletoEdicionOut`: campos inmutables (fecha_edicion UTC, ip, justificacion, estado_anterior/nuevo, edicion_numero) | Test: from_attributes | `schemas/__init__.py:920-936` | MANEJO_DB.md | IMPLEMENTADO | Historial inmutable |
| RB-WEIGH-042 | – | RB | WEIGHING | `WeighingOut.fotos_placa_tomadas` bool — flag 1 vez por boleto (mig 027) | Test: TRUE tras captura | `schemas/__init__.py:1007` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-WEIGH-043 | – | RB | WEIGHING | `WeighingOut.kardex_mov` int nullable — 10/60/None (sin asiento si PENDIENTE) | Test: 10/60/None | `schemas/__init__.py:1005` | MODELO_ESTANDAR.md | IMPLEMENTADO | Enriquecido por servidor |
| RB-WEIGH-044 | – | RB | WEIGHING | `WeighingSyncItem.estado_boleto` default 'Abierto' — sync offline usa string legacy | Test: default 'Abierto' | `schemas/__init__.py:1044` | SYNC offline | IMPLEMENTADO | Normalizado en servidor |
| RB-WEIGH-045 | – | RB | WEIGHING | `SyncBatchRequest`: equipos + pesajes list[WeighingSyncItem] — push offline | Test: batch push | `schemas/__init__.py:1049-1051` | MANEJO_DB.md §9 | IMPLEMENTADO | |
| RB-WEIGH-046 | – | RB | WEIGHING | `SyncStatusResponse.usando_licencia_demo` bool — flag DEMO en status | Test: bool presente | `schemas/__init__.py:1070` | SESIONES.md | IMPLEMENTADO | |

---

### Sección: SYNC — Sincronización (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SYNC-009 | – | RB | SYNC | `IdentidadUpdate.licencia_expira` validator `_licencia_naive_utc` — convierte a UTC naive (evita DataError en columnas TIMESTAMP WITHOUT TIME ZONE) | Test: tz-aware → naive UTC | `schemas/__init__.py:1109-1114` | MANEJO_DB.md, bug E2E | IMPLEMENTADO | Bug real corregido por E2E |

---

### Sección: LICENSE — Licencia (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-LIC-015 | – | RB | LICENSE | `LlaveActivacionCreateRequest.expira_horas` ge=1 le=2160 (90 días) — vigencia llave | Test: 1h a 90d | `schemas/__init__.py:1382` | MANEJO_DB.md §13.7 | IMPLEMENTADO | |
| RB-LIC-016 | – | RB | LICENSE | `LlaveActivacionCreateResponse.codigo` devuelto **una sola vez** (en BD solo hash SHA-256) | Test: codigo presente solo en respuesta | `schemas/__init__.py:1390` | MANEJO_DB.md §13.7 | IMPLEMENTADO | Un solo uso |
| RB-LIC-017 | – | RB | LICENSE | `LlaveActivacionValidarRequest.codigo` 8-64 chars + hardware_id opcional — canje sin auth | Test: sin auth, valida hash | `schemas/__init__.py:1399-1400` | MANEJO_DB.md §13.7 | IMPLEMENTADO | Instalador cliente |
| RB-LIC-018 | – | RB | LICENSE | `LlaveActivacionValidarResponse`: ok, usuario_email, empresa_nombre, mensaje | Test: respuesta exitosa | `schemas/__init__.py:1403-1407` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: DEVICES — Dispositivos (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-DEV-033 | – | RB | DEVICES | `VinculoCreate`: id_bascula + id_indicador UUID obligatorios — enlace 1:1 | Test: FKs requeridas | `schemas/vinculos.py:8-10` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Migración 028 |
| RB-DEV-034 | – | RB | DEVICES | `VinculoOut.from_attributes=True` — serialización ORM | Test: respuesta API | `schemas/vinculos.py:20` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: USUARIOS — Usuarios Locales (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-USR-001 | – | RB | AUTH | `UsuarioCreate`: nombre 3-150, email EmailStr, password 6-128, rol pattern '^(ADMIN|OPERADOR|AUDITOR)$' default OPERADOR | Test: rol válido | `schemas/__init__.py:1124-1128` | MANEJO_DB.md §4 | IMPLEMENTADO | 3 roles tras mig 025 |
| RB-USR-002 | – | RB | AUTH | `UsuarioUpdate`: campos opcionales, rol pattern '^(ADMIN|OPERADOR|AUDITOR)$', password 6-128 si se envía | Test: partial update | `schemas/__init__.py:1131-1135` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: EMPRESA — Perfil Empresa (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-EMP-001 | – | RB | CATALOG | `EmpresaPerfilOut.idioma` Literal['es','en','pt'] DEFAULT 'es' — i18n 3 idiomas | Test: es/en/pt | `schemas/__init__.py:1168` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | 621 claves/idioma |
| RB-EMP-002 | – | RB | CATALOG | `EmpresaPerfilOut.tamano_ticket_pdf` / `fuente_ticket_pdf` Literal con defaults — Spec 001 REQ-FN-014/015 | Test: defaults | `schemas/__init__.py:1170-1171` | Spec 001 | IMPLEMENTADO | Trazabilidad Spec 001 |
| RB-EMP-003 | – | RB | CATALOG | `EmpresaPerfilOut.max_ediciones_boleto` int nullable ge=0 le=1000 — tope ediciones (ADMIN no sujeto) | Test: límites | `schemas/__init__.py:1173` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-EMP-004 | – | RB | CATALOG | `EmpresaPerfilUpdate.protocolo_impresion` Literal['predeterminada_so','raw_9100','lpd_cups','nombre_impresora'] | Test: valores válidos | `schemas/__init__.py:1214-1216` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-EMP-005 | – | RB | CATALOG | `EmpresaPerfilUpdate.impresora_puerto` ge=1 le=65535 — puerto TCP válido | Test: 1-65535 | `schemas/__init__.py:1219` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-EMP-006 | – | RB | CATALOG | `EmpresaPerfilOut.fotos_placa_activas/obligatorias` bool — config fotos placa (mig 027) | Test: bool | `schemas/__init__.py:1180-1181` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-EMP-007 | – | RB | CATALOG | `EmpresaPerfilUpdate._nulo_a_default` validator: tamano_ticket_pdf/fuente_ticket_pdf NULL → default negocio (compatibilidad legacy) | Test: NULL → default | `schemas/__init__.py:1184-1194` | Spec 001 REQ-FN-012 | IMPLEMENTADO | REQ-FN-012 no-regresión |

---

### Sección: SEGURIDAD — Matriz de Accesos (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SEC-001 | – | RB | AUTH | `AccesoUpdate.acceso` pattern '^(ver|editar|ninguno)$' — solo 3 valores | Test: solo 3 valores | `schemas/__init__.py:1242` | MANEJO_DB.md §12 | IMPLEMENTADO | Matriz 18×3 |
| RB-SEC-002 | – | RB | AUTH | `RolOut`: clave, nombre, descripcion, usuarios count, modulos_editar/ver/ninguno counts | Test: counts correctos | `schemas/__init__.py:1245-1255` | MANEJO_DB.md | IMPLEMENTADO | Endpoint /seguridad/roles |

---

### Sección: SERIES — Series de Numeración (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-SER-001 | – | RB | WEIGHING | `SerieNumeracionCreate`: nombre 1-80, prefijo 1-20, inicio ge=1, digitos 1-20 default 8, activa default FALSE | Test: límites | `schemas/__init__.py:1257-1262` | MANEJO_DB.md §6 | IMPLEMENTADO | |
| RB-SER-002 | – | RB | WEIGHING | `SerieNumeracionUpdate`: digitos 1-20, nombre/prefijo opcionales | Test: límites | `schemas/__init__.py:1265-1268` | MANEJO_DB.md | IMPLEMENTADO | |
| RB-SER-003 | – | RB | WEIGHING | `SerieNumeracionOut`: id_serie, id_empresa, siguiente (contador), activa, timestamps | Test: contador visible | `schemas/__init__.py:1271-1282` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: KARDEX — Ajustes de Inventario (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-KAR-015 | – | RB | KARDEX | `AjusteInventarioCreate.id_movimiento` Literal[10,60] — solo INGRESO (10) o DESPACHO (60) | Test: solo 10 o 60 | `schemas/__init__.py:1306-1308` | MODELO_ESTANDAR.md | IMPLEMENTADO | Kardex numérico |
| RB-KAR-016 | – | RB | KARDEX | `AjusteInventarioCreate.valor_kg` Decimal gt=0 — peso ajustado positivo (signo por id_movimiento) | Test: >0 | `schemas/__init__.py:1311` | MODELO_ESTANDAR.md | IMPLEMENTADO | Magnitud positiva |
| RB-KAR-017 | – | RB | KARDEX | `AjusteInventarioCreate.id_concepto` UUID nullable — concepto opcional (catálogo mig 029), documento legacy opcional max 100 | Test: NULL o FK válida | `schemas/__init__.py:1312-1319` | MANEJO_DB.md | IMPLEMENTADO | Compatibilidad documento |
| RB-KAR-018 | – | RB | KARDEX | `AjusteInventarioOut`: id_kardex, id_movimiento, valor, documento, fecha_kardex — registro generado | Test: campos completos | `schemas/__init__.py:1323-1336` | MANEJO_DB.md | IMPLEMENTADO | |

---

### Sección: BACKUP — Respaldos (Schemas)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| RB-BKP-001 | – | RB | OBSERVABILITY | `BackupOut`: archivo, creado_en, motivo, tamano_bytes, id_empresa, conteos dict, version | Test: metadatos completos | `schemas/__init__.py:1348-1359` | MANEJO_DB.md | IMPLEMENTADO | GFS rotation |
| RB-BKP-002 | – | RB | OBSERVABILITY | `BackupRestoreRequest.confirmar` bool default FALSE — confirmación explícita | Test: default FALSE | `schemas/__init__.py:1362-1363` | MANEJO_DB.md | IMPLEMENTADO | Seguridad |
| RB-BKP-003 | – | RB | OBSERVABILITY | `BackupRestoreResponse`: archivo, restaurados dict, advertencia | Test: respuesta | `schemas/__init__.py:1366-1369` | MANEJO_DB.md | IMPLEMENTADO | |

---

## Sección: AUTH — Autenticación y Autorización (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-AUTH-001 | – | RF | AUTH | POST /api/v1/auth/register — Alta empresa + primer ADMIN + valida licencia LM | Test: 201 + tokens + empresa creada | `auth.py:113-183` | MANEJO_DB.md, SESIONES.md | IMPLEMENTADO | Valida unicidad email/RIF, seed catálogos |
| REQ-FN-AUTH-002 | – | RF | AUTH | POST /api/v1/auth/login — Login local + valida licencia LM (cache + refresh) | Test: 200 + tokens + licencia válida | `auth.py:186-285` | MANEJO_DB.md, SESIONES.md | IMPLEMENTADO | Valida ADMIN en otra máquina (hardware_id), seed catálogos |
| REQ-FN-AUTH-003 | – | RF | AUTH | POST /api/v1/auth/login-central — Login CENTRAL-first con espejo local + reintento timeout | Test: 200 local mirror + tokens | `auth.py:288-543` | MANEJO_DB.md §13 | IMPLEMENTADO | 1 reintento ConnectTimeout/ReadTimeout; 502 si falla red |
| REQ-FN-AUTH-004 | – | RF | AUTH | POST /api/v1/auth/login-local — Login OFFLINE sin consultar LM (token offline:true) | Test: 200 + offline=true | `auth.py:546-587` | MANEJO_DB.md | IMPLEMENTADO | Modo sin red |
| REQ-FN-AUTH-005 | – | RF | AUTH | POST /api/v1/auth/validate-license — Valida licencia en tiempo real (force_remote) | Test: 200 + status/tier | `auth.py:590-640` | SESIONES.md | IMPLEMENTADO | Sincroniza licencia_e_identidad |
| REQ-FN-AUTH-006 | – | RF | AUTH | GET /api/v1/auth/license — Snapshot licencia (tier, status, expira, límites, uso DEMO) | Test: 200 + features dict | `auth.py:643-702` | SESIONES.md, PLANES-PAGOS.md | IMPLEMENTADO | Re-valida en vivo; DEMO limita max_registros/sesiones |
| REQ-FN-AUTH-007 | – | RF | AUTH | POST /api/v1/auth/refresh-token — Rotación access+refresh (JWT HS256) | Test: nuevo access_token | `auth.py:705-726` | SESIONES.md | IMPLEMENTADO | |
| REQ-FN-AUTH-008 | – | RF | AUTH | POST /api/v1/auth/forgot-password — Solicita reset (siempre 200, no revela email) | Test: 200 | `auth.py:729-745` | MANEJO_DB.md | IMPLEMENTADO | SMTP o log |
| REQ-FN-AUTH-009 | – | RF | AUTH | POST /api/v1/auth/reset-password — Cambia contraseña con token único | Test: 200 si token válido | `auth.py:748-757` | MANEJO_DB.md | IMPLEMENTADO | 400 si token inválido/expirado |
| REQ-FN-AUTH-010 | – | RF | AUTH | POST /api/v1/auth/logout — Stateless (auditoría) | Test: 200 | `auth.py:760-762` | MANEJO_DB.md | IMPLEMENTADO | Cliente descarta token |
| REQ-NF-AUTH-001 | – | RNF | AUTH | Multi-tenancy: get_current_empresa extrae id_empresa del JWT (no del body) | Test: query filtrada por id_empresa | `dependencies.py` | MANEJO_DB.md §4 | IMPLEMENTADO | Constitución regla 1 |
| REQ-NF-AUTH-002 | – | RNF | AUTH | Roles: require_admin / require_catalog_manager / require_auditor en endpoints | Test: 403 si rol insuficiente | `auth.py:118,126,175,388,393,637,668` | MANEJO_DB.md §4 | IMPLEMENTADO | ADMIN/SUPERVISOR/AUDITOR |
| REQ-NF-AUTH-003 | – | RNF | AUTH | Peso manual: _PERMISOS_PESO_MANUAL = {ADMIN, SUPERVISOR} (403 si otro) | Test: 403 OPERADOR con es_peso_manual | `pesajes.py:86-92,231` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-NF-AUTH-004 | – | RNF | AUTH | Anulación: _PERMISOS_ANULACION = {ADMIN, SUPERVISOR} (403 si otro) | Test: 403 OPERADOR anula | `pesajes.py:95-101,393` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-NF-AUTH-005 | – | RNF | AUTH | Login-central: timeout configurable CENTRAL_TIMEOUT (default 30s) + 1 reintento | Test: timeout <30s, reintento <1s | `auth.py:55-62,332-355` | MANEJO_DB.md §11 | IMPLEMENTADO | Socket caliente reintentos |

---

## Sección: WEIGHING — Pesaje (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-WEIGH-001 | – | RF | WEIGHING | POST /api/v1/weighing/create — Crea boleto PENDIENTE (inline get-or-create catálogos) | Test: 201 + WeighingOut | `pesajes.py:223-291` | MANEJO_DB.md §6 | IMPLEMENTADO | Valida licencia LM, peso_manual permisos, doble PENDIENTE |
| REQ-FN-WEIGH-002 | – | RF | WEIGHING | POST /api/v1/weighing/close/{boleto} — Registra salida + cierra CERRADO + Kardex 10/60 | Test: 200 + kardex_mov 10/60 | `pesajes.py:352-381` | MANEJO_DB.md §6 | IMPLEMENTADO | Valida peso_manual, enriquece ticket |
| REQ-FN-WEIGH-003 | – | RF | WEIGHING | PUT /api/v1/weighing/{boleto}/anular — Anula con motivo ≥10 + kardex inverso si CERRADO | Test: 200 + ANULADO + inverso | `pesajes.py:384-409` | MODELO_ESTANDAR.md | IMPLEMENTADO | Solo ADMIN/SUPERVISOR, libera vehículo |
| REQ-FN-WEIGH-004 | – | RF | WEIGHING | GET /api/v1/weighing/pendientes — Lista PENDIENTE/MODIFICADO sin salida (paginado) | Test: 200 + lista paginada | `pesajes.py:412-421` | MANEJO_DB.md | IMPLEMENTADO | skip/limit, _enriquecer_pesajes_lista (8 queries) |
| REQ-FN-WEIGH-005 | – | RF | WEIGHING | GET /api/v1/weighing/list — Historial con filtros fecha/vehículo/estado (paginado) | Test: 200 + filtros | `pesajes.py:424-446` | USO-API.md | IMPLEMENTADO | date_from/date_to/vehicle_id/estado |
| REQ-FN-WEIGH-006 | – | RF | WEIGHING | GET /api/v1/weighing/boleto/{boleto} — Detalle completo enriquecido | Test: 200 + WeighingOut | `pesajes.py:449-459` | USO-API.md | IMPLEMENTADO | _enriquecer_pesaje_ticket |
| REQ-FN-WEIGH-007 | – | RF | WEIGHING | PUT /api/v1/weighing/{boleto} — Modifica campos (CERRADO→MODIFICADO) + justificación ≥10 | Test: 200 + ediciones_count++ | `pesajes.py:637-665` | MANEJO_DB.md | IMPLEMENTADO | ADMIN exento tope ediciones, registra en boletos_ediciones |
| REQ-FN-WEIGH-008 | – | RF | WEIGHING | GET /api/v1/weighing/{boleto}/pdf — Ticket PDF ReportLab (idioma, copias, papel, QR) | Test: 200 application/pdf | `pesajes.py:559-593` | MANEJO_DB.md, Spec 001 | IMPLEMENTADO | Parámetros: tipo_ticket, tamano_papel, orientacion, mostrar_qr |
| REQ-FN-WEIGH-009 | – | RF | WEIGHING | GET /api/v1/weighing/{boleto}/txt — Ticket TXT plano (impresora matricial) | Test: 200 text/plain | `pesajes.py:596-610` | MANEJO_DB.md | IMPLEMENTADO | Formato empresa |
| REQ-FN-WEIGH-010 | – | RF | WEIGHING | GET /api/v1/weighing/{boleto}/export — Descarga en formato empresa (PDF/TXT) | Test: 200 + formato config | `pesajes.py:613-634` | MANEJO_DB.md | IMPLEMENTADO | Usa empresas.formato_ticket |
| REQ-FN-WEIGH-011 | – | RF | WEIGHING | GET /api/v1/weighing/{boleto}/ediciones — Historial ediciones (BoletoEdicionOut) | Test: 200 + lista | `pesajes.py:668-680` | MANEJO_DB.md | IMPLEMENTADO | Justificación, diff JSON, usuario, IP |
| REQ-FN-WEIGH-012 | – | RF | WEIGHING | CRUD imágenes boleto (GET/POST/DELETE /{boleto}/imagenes + upload archivo) | Test: 201/200/204 | `pesajes.py:688-804` | MANEJO_DB.md | IMPLEMENTADO | tipo: placa/vehiculo/documento/entrada/salida/otros |
| REQ-FN-WEIGH-013 | – | RF | WEIGHING | GET /api/v1/weighing/scale/{balanza_id}/live — Peso en vivo HAL (sesión persistente) | Test: 200 + PesoEnVivoOut | `pesajes.py:820-852` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Sesión persistente ScaleSessionManager |
| REQ-FN-WEIGH-014 | – | RF | WEIGHING | POST /api/v1/files/upload — Sube foto catálogo (multipart, compresión Pillow) | Test: 201 + url + tamano_kb | `pesajes.py:301-316` | MANEJO_DB.md | IMPLEMENTADO | Comprime 1600px max, JPEG q80 |
| REQ-NF-WEIGH-001 | – | RNF | WEIGHING | _enriquecer_pesajes_lista: 8 consultas por página (N+1 eliminado) — p50 20ms vs 450ms | Test: benchmark 50k boletos | `pesajes.py:108-220` | docs/evidencia/volumen-analisis.md | IMPLEMENTADO | 7 consultas fijas por página |
| REQ-NF-WEIGH-002 | – | RNF | WEIGHING | Multi-tenancy: id_empresa del JWT en TODAS las queries (get_current_empresa) | Test: aislamiento tenant | `pesajes.py:228,358,416,452` | Constitución | IMPLEMENTADO | |
| REQ-NF-WEIGH-003 | – | RNF | WEIGHING | DEMO max_registros limit (settings.demo_max_records=10) en create | Test: 403 si >10 | `pesajes.py:278-280` | SESIONES.md | IMPLEMENTADO | Control por licencia |

---

## Sección: CATALOG — Catálogos (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-CAT-001 | – | RF | CATALOG | GET /api/v1/catalogo/sync — Snapshot combinado todos catálogos (paginación H11: limit/skip/totales/truncado) | Test: 200 + totales+truncado | `catalogo.py` | MANEJO_DB.md, USO-API.md | IMPLEMENTADO | H11: limit 1-5000, catalogo repetible |
| REQ-FN-CAT-002 | – | RF | CATALOG | CRUD /marcas (GET/POST/PUT/DELETE) — require_catalog_manager | Test: 200/201/200/204 | `flota.py:35-94` | MANEJO_DB.md | IMPLEMENTADO | DELETE 400 si tiene modelos |
| REQ-FN-CAT-003 | – | RF | CATALOG | CRUD /modelos-camion (GET/POST/PUT/DELETE) — filtro por marca_id | Test: 200 + filtro marca | `flota.py:102-158` | MANEJO_DB.md | IMPLEMENTADO | GET /marcas/{id}/modelos |
| REQ-FN-CAT-004 | – | RF | CATALOG | CRUD /camiones (GET/POST/PUT/DELETE + /buscar por placa ILIKE) | Test: 200 + buscar ILIKE | `flota.py:179-247` | MANEJO_DB.md | IMPLEMENTADO | /buscar?placa= |
| REQ-FN-CAT-005 | – | RF | CATALOG | CRUD /remolques (GET/POST/PUT/DELETE) | Test: 200/201/200/204 | `flota.py:255-307` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-CAT-006 | – | RF | CATALOG | CRUD /productos (GET/POST/PUT/DELETE) — valida id_categoria FK + require_catalog_manager | Test: 409 si categoría otra empresa | `inventario.py:56-139` | MODELO_ESTANDAR.md | IMPLEMENTADO | id_categoria NOT NULL (mig 013) |
| REQ-FN-CAT-007 | – | RF | CATALOG | CRUD /categorias (GET/POST/PUT/DELETE) — require_catalog_manager | Test: 200/201/200/204 | `inventario.py:147-220` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-CAT-008 | – | RF | CATALOG | CRUD /almacenes (GET/POST/PUT/DELETE) — require_catalog_manager | Test: 200/201/200/204 | `inventario.py:228-301` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-CAT-009 | – | RF | CATALOG | CRUD /balanzas (GET/POST/PUT/DELETE + /descubrir + /probar) — require_admin | Test: filtros q/activo/is_simulada/protocolo | `inventario.py:309-528` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Descubrimiento TCP/serial/ptys |
| REQ-FN-CAT-010 | – | RF | CATALOG | CRUD /transportes (GET/POST/PUT/DELETE) | Test: 200/201/200/204 | `directorio.py` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-CAT-011 | – | RF | CATALOG | CRUD /conductores (GET/POST/PUT/DELETE) | Test: 200/201/200/204 | `directorio.py` | MANEJO_DB.md | IMPLEMENTADO | PK cédula_dni |
| REQ-FN-CAT-012 | – | RF | CATALOG | CRUD /terceros (GET/POST/PUT/DELETE) — tipo CLIENTE/PROVEEDOR/AMBOS | Test: 200/201/200/204 | `directorio.py` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-CAT-013 | – | RF | CATALOG | GET /api/v1/config/account — Info unificada estación (identidad+empresa+licencia+uso DEMO) | Test: 200 + estructura | `config.py` | USO-API.md | IMPLEMENTADO | Sin auth (público) |
| REQ-FN-CAT-014 | – | RF | CATALOG | GET/PUT /api/v1/empresa — Perfil fiscal/comercial/logo/formatos/idioma (ADMIN edita) | Test: 200 + campos actualizados | `empresa.py` | MANEJO_DB.md | IMPLEMENTADO | Valida RIF único |
| REQ-FN-CAT-015 | – | RF | CATALOG | GET/PUT /api/v1/identity — Singleton identidad_local (vínculo cuenta central) | Test: 200 | `identity.py` | MANEJO_DB.md §13 | IMPLEMENTADO | |
| REQ-FN-CAT-016 | – | RF | CATALOG | CRUD /series (GET/POST/PUT/PUT activa/DELETE) — 409 si tiene boletos | Test: 409 DELETE usado | `series.py` | MANEJO_DB.md §6 | IMPLEMENTADO | Numeración secuencial |
| REQ-FN-CAT-017 | – | RF | CATALOG | CRUD /usuarios (GET/POST/PUT/DELETE) — roles ADMIN/OPERADOR/AUDITOR + cola sync credenciales | Test: rol válido | `usuarios.py` | MANEJO_DB.md §4 | IMPLEMENTADO | Encola credencial para sync |
| REQ-FN-CAT-018 | – | RF | CATALOG | GET/PUT /api/v1/seguridad/matriz — Matriz efectiva rol×módulo (ADMIN no degradable) | Test: ADMIN forced editar | `seguridad.py` | MANEJO_DB.md §12 | IMPLEMENTADO | 18 módulos × 3 roles |
| REQ-FN-CAT-019 | – | RF | CATALOG | GET /api/v1/environment — Estado instalación (plataforma, Python, BD, esquema, HAL) | Test: 200 sin auth | `entorno.py` | MANEJO_DB.md | IMPLEMENTADO | Público |
| REQ-FN-CAT-020 | – | RF | CATALOG | POST /api/v1/inventario/ajustes — Ajuste kardex manual (id_movimiento 10/60, id_concepto, valor_kg>0) | Test: 201 + AjusteInventarioOut | `inventario.py:587-680` | MANEJO_DB.md, MODELO_ESTANDAR.md | IMPLEMENTADO | Solo ADMIN, es_kardex=true |

---

## Sección: KARDEX — Kardex e Inventario (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-KAR-001 | – | RF | KARDEX | GET /api/v1/reports/kardex/saldo — Saldo por producto/almacén a fecha corte | Test: 200 + saldo calculado | `reports.py` | MODELO_ESTANDAR.md | IMPLEMENTADO | Σ 01-49 − Σ 50-99 |
| REQ-FN-KAR-002 | – | RF | KARDEX | GET /api/v1/reports/kardex/detalle — Movimientos con filtros (producto, almacén, fechas) | Test: 200 + paginado | `reports.py` | MODELO_ESTANDAR.md | IMPLEMENTADO | Export Excel/PDF |
| REQ-FN-KAR-003 | – | RF | KARDEX | POST /api/v1/inventario/ajustes — Movimiento manual 10/60 (ver CAT-020) | Test: 201 + kardex generado | `inventario.py:587-680` | MANEJO_DB.md | IMPLEMENTADO | Solo ADMIN, es_kardex=true |

---

## Sección: SYNC — Sincronización Offline-First (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SYNC-001 | – | RF | SYNC | POST /api/v1/sync/push — Sube pendientes offline (cola idempotente, normaliza UTC naive) | Test: 200 + sincronizados | `sync.py` | MANEJO_DB.md §9 | IMPLEMENTADO | _naive_utc fix bug E2E |
| REQ-FN-SYNC-002 | – | RF | SYNC | GET /api/v1/sync/status — Estado cola (pendientes, última sync, max_offline_dias, demo) | Test: 200 + campos | `sync.py` | SESIONES.md | IMPLEMENTADO | usando_licencia_demo bool |
| REQ-FN-SYNC-003 | – | RF | SYNC | GET /api/v1/sync/pull — Baja datos del servidor (catálogos, usuarios) | Test: 200 + datos | `sync.py` | MANEJO_DB.md §9 | IMPLEMENTADO | |
| REQ-FN-SYNC-004 | – | RF | SYNC | POST /api/v1/sync/usuarios/entregados — Confirma recepción usuarios (orquesta frontend) | Test: 200 | `sync.py` | MANEJO_DB.md | IMPLEMENTADO | Frontend orquesta |

---

## Sección: LICENSE — Licencia y License Manager (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-LIC-001 | – | RF | LICENSE | POST /api/v1/auth/register — Valida licencia LM al crear empresa (check Ed25519) | Test: 400 si LM inválida | `auth.py:141-153` | PLANES-PAGOS.md | IMPLEMENTADO | Ed25519 anti-fake-server |
| REQ-FN-LIC-002 | – | RF | LICENSE | POST /api/v1/auth/login — Valida licencia LM en cada login (cache + degradación offline) | Test: 403 si expirada/suspendida | `auth.py:227-268` | SESIONES.md | IMPLEMENTADO | Cache TTL 300s |
| REQ-FN-LIC-003 | – | RF | LICENSE | GET /api/v1/auth/license — Snapshot con límites tier (DEMO max_registros/sesiones, features {}) | Test: features dict vacío | `auth.py:643-702` | PLANES-PAGOS.md | IMPLEMENTADO | NO gatea por features (contradicción TERMINOS §4.1) |
| REQ-FN-LIC-004 | – | RF | LICENSE | POST /api/v1/activacion/llaves — ADMIN emite llave 1 uso (SHA-256, 7d default, máx 90d) | Test: 201 + codigo plano 1 vez | `activacion.py` | MANEJO_DB.md §13.7 | IMPLEMENTADO | Revoca llave anterior usuario |
| REQ-FN-LIC-005 | – | RF | LICENSE | POST /api/v1/activacion/validar — Canje sin auth (FOR UPDATE, avisa dueño con sesiones usadas) | Test: 200 + usuario_email | `activacion.py` | MANEJO_DB.md §13.7 | IMPLEMENTADO | Instalador exige en paso 1c |

---

## Sección: SESSIONS — Gestión de Sesiones (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SES-001 | – | RF | SESSIONS | Server: POST /api/v1/auth/login — Registra dispositivo, RB-12 aprobación (PENDIENTE/APROBADO/RECHAZADO) | Test: 403 si PENDIENTE/RECHAZADO | `servidor.py:597-821` | SESIONES.md | IMPLEMENTADO | DEMO 1 equipo, CENTRAL aprueba |
| REQ-FN-SES-002 | – | RF | SESSIONS | Server: GET /api/v1/auth/sesiones — Lista equipos + estado + rol_sesion (solo ADMIN global) | Test: 200 + items | `servidor.py:918-943` | SESIONES.md | IMPLEMENTADO | Tutora aprueba/rechaza |
| REQ-FN-SES-003 | – | RF | SESSIONS | Server: PATCH /api/v1/auth/sesiones/{id} — Aprueba/rechaza + asigna rol_sesion (ADMIN) | Test: 200 + rol_sesion | `servidor.py:946-1031` | SESIONES.md | IMPLEMENTADO | Rechazar revoca sesiones |
| REQ-FN-SES-004 | – | RF | SESSIONS | Server: POST /api/v1/auth/refresh-token — Rotación con revocación + detección reuso (robo) | Test: 401 si reuso | `servidor.py:824-892` | SESIONES.md | IMPLEMENTADO | Rotación ciega previo |
| REQ-NF-SES-001 | – | RNF | SESSIONS | Límite sesiones: DEMO=3, resto=licencias.max_sesiones (fuente única: limite_sesiones_por_tier) | Test: 403 si excede | `servidor.py:747-766` | SESIONES.md | IMPLEMENTADO | get_server_credencial verifica |

---

## Sección: SEMAFORO — Semáforo de Pesaje (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SEM-001 | – | RF | SEMAFORO | CRUD /semaforos (GET/POST/PUT/DELETE) — require_admin + filtros vista (q/activo/is_simulado/protocolo/control_automatico) | Test: filtros opcionales | `semaforos.py:125-232` | SEMAFORO.md | IMPLEMENTADO | CatalogService.list_filtrado |
| REQ-FN-SEM-002 | – | RF | SEMAFORO | GET /semaforos/descubrir — Escanea HTTP (127.0.0.1:8080) + serie (BSDD + USB + ptys) | Test: 200 + candidatos | `semaforos.py:268-377` | SEMAFORO.md | IMPLEMENTADO | Include_simulados |
| REQ-FN-SEM-003 | – | RF | SEMAFORO | POST /semaforos/{id}/probar — Lee estado SPEC §3 (conectado/estado JSON) | Test: 200 + SemaforoPruebaOut | `semaforos.py:385-415` | SEMAFORO.md | IMPLEMENTADO | HAL get_semaforo_hal |
| REQ-FN-SEM-004 | – | RF | SEMAFORO | GET /semaforos/{id}/estado — Estado equipo + fase/luces app (vigilante 0.5s) | Test: 200 + fase/luces | `semaforos.py:418-447` | SEMAFORO.md | IMPLEMENTADO | Controller luces_actuales |
| REQ-FN-SEM-005 | – | RF | SEMAFORO | POST /semaforos/{id}/comando — Envía comando manual (SPEC §4/§5.6: color/action, zumbador, all, reset) | Test: 200 + aplicado | `semaforos.py:450-491` | SEMAFORO.md | IMPLEMENTADO | normalizar_comando + auditoría |
| REQ-FN-SEM-006 | – | RF | SEMAFORO | POST /semaforos/{id}/automatico — Activa/desactiva vigilante (requiere id_balanza) | Test: 200 + control_automatico | `semaforos.py:494-534` | SEMAFORO.md | IMPLEMENTADO | Controller asegurar/detener |

---

## Sección: DEVICES — Dispositivos (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-DEV-001 | – | RF | DEVICES | CRUD /indicadores (GET/POST/PUT/DELETE + /descubrir + /enlazar) — require_admin, filtros vista | Test: filtros q/activo/is_simulado/protocolo | `indicadores.py:77-284` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | POST/DELETE /enlazar (409 si balanzas) |
| REQ-FN-DEV-002 | – | RF | DEVICES | CRUD /semaforos — ver SEM-001 a SEM-006 | Test: completo | `semaforos.py` | SEMAFORO.md | IMPLEMENTADO | |
| REQ-FN-DEV-003 | – | RF | DEVICES | CRUD /camaras (GET/POST/PUT/DELETE + /descubrir + /probar + /snapshot + /stream + /capturar) — filtros origen | Test: IP/local, snapshot proxy, stream MJPEG | `camaras.py:132-437` | DISPOSITIVOS.md | IMPLEMENTADO | Origen ip/local, password no expuesta |
| REQ-FN-DEV-004 | – | RF | DEVICES | CRUD /barreras (GET/POST/PUT/PUT/DELETE + /probar + /estado + /comando + /automatico) | Test: filtros protocolo/ubicacion | `barreras.py` | DISPOSITIVOS.md | IMPLEMENTADO | Migración 032 |
| REQ-FN-DEV-005 | – | RF | DEVICES | CRUD /balanzas — ver CAT-009 | Test: completo | `inventario.py:309-528` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| REQ-FN-DEV-006 | – | RF | DEVICES | POST /indicadores/{id}/balanzas/{id}/enlazar — Enlace 1:1 (409 si balanzas enlazadas al borrar) | Test: 409 DELETE con enlaces | `indicadores.py:204-284` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Tabla VinculoBalanzaIndicador |
| REQ-FN-DEV-007 | – | RF | DEVICES | GET /dispositivos — Lista simple (compatibilidad) | Test: 200 | `dispositivos.py` | DISPOSITIVOS.md | IMPLEMENTADO | Legacy |

---

## Sección: REPORTS — Reportes (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-REP-001 | – | RF | REPORTS | GET /api/v1/reports/daily — Diario (hoy) con filtros, ANULADOS excluidos | Test: 200 + datos | `reports.py` | MANEJO_DB.md | IMPLEMENTADO | Paginado |
| REQ-FN-REP-002 | – | RF | REPORTS | GET /api/v1/reports/monthly — Mensual (mes en curso) | Test: 200 | `reports.py` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-REP-003 | – | RF | REPORTS | GET /api/v1/reports/vehicle/{id} — Por vehículo | Test: 200 | `reports.py` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-REP-004 | – | RF | REPORTS | GET /api/v1/reports/kardex/saldo — Saldo a fecha corte (Σ 01-49 − Σ 50-99) | Test: saldo correcto | `reports.py` | MODELO_ESTANDAR.md | IMPLEMENTADO | Calculado, no persistido |
| REQ-FN-REP-005 | – | RF | REPORTS | GET /api/v1/reports/kardex/detalle — Movimientos filtrados | Test: 200 + paginado | `reports.py` | MODELO_ESTANDAR.md | IMPLEMENTADO | Export Excel/PDF |
| REQ-FN-REP-006 | – | RF | REPORTS | GET /api/v1/reports/export/{excel,pdf} + kardex/{excel,pdf} — Con encabezado institucional, logo, formato numérico por idioma | Test: 200 + archivo | `exports.py` | USO-API.md | IMPLEMENTADO | 36215 líneas exports.py |
| REQ-FN-REP-007 | – | RF | REPORTS | Presets: /reports/diarios (hoy), /reports/mensuales (mes), /reports/personalizado (rango libre) | Test: 200 + preset aplicado | `reports.py` + frontend | NAV.md | IMPLEMENTADO | Spec 001 REQ-FN-019 |

---

## Sección: AUDIT — Auditoría (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-AUD-001 | – | RF | AUDIT | GET /api/v1/auditoria — Tabla completa (acción, entidad, entidad_id, detalle JSON, email, IP, UTC) | Test: 200 + filtros | `auditoria.py` | MANEJO_DB.md | IMPLEMENTADO | Solo ADMIN/AUDITOR |
| REQ-FN-AUD-002 | – | RF | AUDIT | Filtros: entidad/accion/fecha_desde/fecha_hasta/skip/limit (1-500, default 100) | Test: filtros funcionan | `auditoria.py` | MANEJO_DB.md | IMPLEMENTADO | Multi-tenant (id_empresa) |
| REQ-NF-AUD-001 | – | RNF | AUDIT | AuditMiddleware registra POST/PUT/PATCH/DELETE en logs_sistema + auditoria (best-effort) | Test: auditoría creada | `audit.py` | MANEJO_DB.md | IMPLEMENTADO | No bloquea request si falla |

---

## Sección: I18N — Internacionalización (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-I18N-001 | – | RNF | I18N | Backend: ?idioma= / Accept-Language → resolve_lang (es/en/pt) | Test: 3 idiomas | `i18n.py` + endpoints | I18N_Y_ONBOARDING.md | IMPLEMENTADO | 621 claves/idioma |
| REQ-NF-I18N-002 | – | RNF | I18N | Frontend: translations.dart 621 claves × 3, paridad verificada por test | Test: i18n_test.dart | `translations.dart` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | |

---

## Sección: OBSERVABILITY — Observabilidad (Endpoints)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-OBS-001 | – | RNF | OBSERVABILITY | GET /metrics — Prometheus (balansoft_http_requests_total, _latency_seconds, _pesajes_total, _license_errors_total, _active_users) | Test: métricas presentes | `monitoring.py` | OBSERVABILIDAD.md | IMPLEMENTADO | _normalize_path → {id} |
| REQ-NF-OBS-002 | – | RNF | OBSERVABILITY | Rate limiting sliding window (cachetools) 429 + Retry-After — no distribuido (Redis pendiente) | Test: 403/429 | `rate_limit.py` | OBSERVABILIDAD.md | IMPLEMENTADO | No shared between workers |
| REQ-NF-OBS-003 | – | RNF | OBSERVABILITY | Logging: consola + archivo rotado (size), formato text/json (LOG_FORMAT), logrotate system | Test: archivo rotado | `logging_config.py` | OBSERVABILIDAD.md | IMPLEMENTADO | deploy/balansoft-ws.logrotate |

---

## Sección: INSTALLER — Instalador y Onboarding

*Se poblará en Fase 9*

---

## Sección: WSERVER — Runtime Local

*Se poblará en Fase 9*

---

## Sección: PRINTING — Impresión de Tickets

*Se poblará en Fases 5–6*

---

## Apéndice: Referencias Rápidas a Código Crítico

| Archivo | Qué contiene | Relevante para |
|---------|--------------|----------------|
| `backend/balansoft-ws-local.sql` | Esquema local canónico (31 tablas) | FASE 1 — RB de BD |
| `backend/balansoft-ws-server.sql` | Esquema servidor (10 tablas) | FASE 1 — RB de BD |
| `backend/migrations/*.sql` | 30+ migraciones idempotentes | FASE 1 — RB de BD |
| `backend/app/models/__init__.py` | 45 modelos ORM local (1121 líneas) | FASE 2 — RB de ORM |
| `backend/app/models_server.py` | 10 modelos ORM servidor (298 líneas) | FASE 2 — RB de ORM |
| `backend/app/schemas/__init__.py` | Esquemas Pydantic request/response (1407 líneas) | FASE 3 — RB de validación |
| `backend/app/schemas/vinculos.py` | Schemas enlace balanza-indicador | FASE 3 — RB de validación |
| `backend/app/api/v1/endpoints/` | Endpoints REST | FASE 4 — RF de API |
| `backend/app/services/` | Lógica de negocio pura | FASE 5 — RF + RB |
| `backend/app/core/` | Config, seguridad, HAL, monitoring, BD engine | FASE 6 — RNF + RB |
| `backend/tests/` | Tests backend (1100+ unit + 34 E2E) | FASE 7 — Criterios de aceptación |
| `frontend/lib/presentation/screens/` | Pantallas Flutter | FASE 8 — RF de UI |
| `frontend/lib/bloc/` | BLoCs/Cubits | FASE 8 — Flujos de usuario |
| `frontend/lib/data/repositories/` | Repositorios + sync queue | FASE 8 — RNF offline-first |
| `frontend/lib/core/i18n/` | Traducciones (621 claves × 3) | FASE 8 — RNF usabilidad |
| `frontend/lib/core/config/station_config.dart` | config.json, StationRole | FASE 8 — RF instalador |
| `backend/wserver.py` | WServer bootstrap | FASE 9 — RF WServer |
| `backend/WServer.spec` | PyInstaller spec | FASE 9 — RNF portabilidad |
| `BALANSOFT-INSTALLER/gui/steps/` | Pasos del instalador Tk | FASE 9 — RF instalador |

---

## FASE 6 — CORE: CONFIGURACIÓN, SEGURIDAD, HAL, MONITOREO, BD ENGINE (RNF + RB)

Fuentes: `backend/app/core/*.py`

### Sección: CONFIG — Configuración Centralizada (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-CFG-001 | – | RNF | CONFIG | `Settings` con pydantic-settings: `.env` + env vars, case-insensitive, extra=ignore | Test: carga settings | `config.py:21-27` | MANEJO_DB.md §11 | IMPLEMENTADO | |
| REQ-NF-CFG-002 | – | RNF | CONFIG | `app_role`: "local" (estación) \| "server" (central) — selecciona BD y routers | Test: rol correcto | `config.py:41` | MANEJO_DB.md | IMPLEMENTADO | Arquitectura 2 BDs |
| REQ-NF-CFG-003 | – | RNF | CONFIG | `central_timeout` default 30s (1-600s) + 1 reintento único en login-central | Test: timeout + retry | `config.py:49` | MANEJO_DB.md §11 | IMPLEMENTADO | ConectTimeout/ReadTimeout |
| REQ-NF-CFG-004 | – | RNF | CONFIG | Fail-fast producción: aborta si DEBUG_MODE=true o SECRET_KEY default o LM public key ausente | Test: ValueError en prod | `config.py:168-210` | MANEJO_DB.md | IMPLEMENTADO | _validar_entorno_produccion |
| REQ-NF-CFG-005 | – | RNF | CONFIG | Motor BD por prefijo DATABASE_URL (postgresql+asyncpg:// \| mssql+aioodbc://) sin env vars nuevas | Test: motor correcto | `config.py:213-247` | MANEJO_DB.md §11.5 | IMPLEMENTADO | _coherencia_motores |
| REQ-NF-CFG-006 | – | RNF | CONFIG | `database_url_sync` derivado en memoria si vacío/incoherente (PREFIJO_SYNC) | Test: sync URL correcta | `config.py:220-226` | MANEJO_DB.md | IMPLEMENTADO | derivar_url_sync |
| REQ-NF-CFG-007 | – | RNF | CONFIG | Rate limiting: enabled/disabled, login=5, register=3, password=5, window=60s | Test: 429 si excede | `config.py:143-149` | OBSERVABILIDAD.md | IMPLEMENTADO | Sliding window cachetools |
| REQ-NF-CFG-008 | – | RNF | CONFIG | Backups GFS: retention_days=0 (sin límite), keep_daily=7, weekly=5, monthly=12 | Test: retención correcta | `config.py:154-166` | MANEJO_DB.md §11 | IMPLEMENTADO | Rotación abuelo-padre-hijo |
| REQ-NF-CFG-009 | – | RNF | CONFIG | `license_product_code="WS"` (default config.py es "BWS" — ojo) | Test: código correcto | `config.py:63` | MANEJO_DB.md | IMPLEMENTADO | LM espera "WS" |
| REQ-NF-CFG-010 | – | RNF | CONFIG | Logging: log_format text\|json, rotación size (5MB default, 5 backups) | Test: archivo rotado | `config.py:90-96` | OBSERVABILIDAD.md | IMPLEMENTADO | RotatingFileHandler |

---

### Sección: SEGURIDAD — Matriz de Permisos (RF + RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SEC-001 | – | RF | SECURITY | Matriz 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR) con acceso ver/editar/ninguno | Test: matriz correcta | `seguridad_matrix.py:15-115` | MANEJO_DB.md §12 | IMPLEMENTADO | 45 módulos definidos |
| REQ-FN-SEC-002 | – | RF | SECURITY | ADMIN forzado a "editar" en todos los módulos (no degradable) | Test: ADMIN siempre editar | `seguridad_matrix.py:53` | MANEJO_DB.md §12 | IMPLEMENTADO | MATRIZ_DEFECTO |
| REQ-FN-SEC-003 | – | RF | SECURITY | OPERADOR: edita inicio/terceros/clientes/proveedores/camiones/conductores/transportes/categorias/productos/almacenes/entradas/salidas/reportes/diseno_ticket/ajustes_inventario/reportes_* | Test: accesos OPERADOR | `seguridad_matrix.py:54-83` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-SEC-004 | – | RF | SECURITY | AUDITOR: ver la mayoría, edita solo inicio/reportes/reportes_* | Test: accesos AUDITOR | `seguridad_matrix.py:85-114` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-NF-SEC-001 | – | RNF | SECURITY | `permisos_acceso` tabla PK (id_empresa, rol, modulo) — override por empresa | Test: override persiste | `seguridad_matrix.py:47` + tabla BD | MANEJO_DB.md §12 | IMPLEMENTADO | Matriz efectiva = BD o default |

---

### Sección: I18N — Internacionalización (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-I18N-001 | – | RNF | I18N | Backend: `i18n.py` con diccionarios es/en/pt, `t()` resuelve por `?idioma=` o `Accept-Language` | Test: 3 idiomas | `i18n.py` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | 621 claves/idioma |
| REQ-NF-I18N-002 | – | RNF | I18N | Frontend: `translations.dart` 621 claves × 3 idiomas, paridad verificada por test | Test: paridad | `translations.dart` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | |

---

### Sección: MONITORING — Observabilidad (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-OBS-001 | – | RNF | OBSERVABILITY | `MetricsMiddleware`: balansoft_http_requests_total (method,endpoint,status) | Test: métrica expuesta | `monitoring.py:33-37` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-002 | – | RNF | OBSERVABILITY | `REQUEST_LATENCY` Histogram buckets 0.01-5.0s (method,endpoint) | Test: buckets correctos | `monitoring.py:39-44` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-003 | – | RNF | OBSERVABILITY | `PESAJES_TOTAL` Counter (estatus, tier) + `LICENSE_ERRORS` (tier, reason) + `ACTIVE_USERS` (tier) | Test: contadores negocio | `monitoring.py:46-62` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-004 | – | RNF | OBSERVABILITY | `_normalize_path()`: UUIDs e IDs numéricos → `{id}` (cardinalidad acotada) | Test: path normalizado | `monitoring.py:69-76` | OBSERVABILIDAD.md | IMPLEMENTADO | NUNCA id_empresa en métricas |
| REQ-NF-OBS-005 | – | RNF | OBSERVABILITY | `GET /metrics` endpoint Prometheus (fuera de OpenAPI), flag METRICS_ENABLED | Test: 200 text/plain | `monitoring.py:128-129` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-005 | – | RNF | OBSERVABILITY | Rate limiting sliding window (cachetools) 429 + Retry-After, /health /metrics exentos | Test: 429 + header | `rate_limit.py` | OBSERVABILIDAD.md | IMPLEMENTADO | No distribuido (Redis pendiente) |
| REQ-NF-OBS-006 | – | RNF | OBSERVABILITY | Logging: consola + archivo rotado (RotatingFileHandler), text\|json (LOG_FORMAT) | Test: archivo rotado | `logging_config.py` | OBSERVABILIDAD.md | IMPLEMENTADO | deploy/balansoft-ws.logrotate |

---

### Sección: SCALE — HAL de Básculas (RF + RB)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SCL-001 | – | RF | DEVICES | `ScaleHAL` abstracto: read_weight(), is_stable(), conectar/leer_muestra/cerrar (persistente) | Test: interfaz | `scale_hal.py:96-134` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| REQ-FN-SCL-002 | – | RF | DEVICES | `SerialScaleHAL`: pyserial, lock por puerto (threading.Lock), reintenta 3x, timeout 1s | Test: lock serial | `scale_hal.py:136-256` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Concurrencia serial |
| REQ-FN-SCL-003 | – | RF | DEVICES | `TcpScaleHAL`: asyncio, auto-detección JSON/ASCII, emparejamiento persistente, buffer drenado | Test: auto-detect | `scale_hal.py:278-569` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Auto-detect formato |
| REQ-FN-SCL-004 | – | RF | DEVICES | `ScaleSession`: conexión viva + caché último peso + reconexión backoff (0.5-5s) | Test: reconexión | `scale_session.py:62-192` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | 1 task/balanza |
| REQ-FN-SCL-005 | – | RF | DEVICES | `ScaleSessionManager`: 1 sesión/balanza, recrea si cambia config (clave incluye formato/baudrate/delimitador) | Test: recrea sesión | `scale_session.py:216-270` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | `get_scale_session_manager()` |
| REQ-FN-SCL-006 | – | RF | DEVICES | `get_scale_hal()`: prioridad TCP (ip+puerto) → serial (puerto_com), propaga formato/baudrate/delimitador | Test: HAL correcto | `scale_hal.py:584-620` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Factory |
| RB-SCL-001 | – | RB | DEVICES | `parse_weight_frame()`: multi-marca (Toledo/GSI, Rice Lake, MT-SICS, signo suelto, STX/ETX+XOR) | Test: parsers | `scale_parser.py:177-206` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Parser puro |
| RB-SCL-002 | – | RB | DEVICES | Anti-falso-positivo: rechaza números desnudos (dirección, checksum); requiere signo/decimal/unidad | Test: rechaza desnudos | `scale_parser.py:104-174` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Principio anti-falso-positivo |
| RB-SCL-003 | – | RB | DEVICES | Tolerancia capacidad 105% (TOLERANCIA_CAPACIDAD=1.05) — rechaza sobrecarga | Test: 105% rechaza | `scale_parser.py:48,172` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | OIML R 76-1 |
| RB-SCL-004 | – | RB | DEVICES | Delimitadores: lf\|cr\|crlf\|stx_etx (configurable por balanza) | Test: delimitadores | `scale_hal.py:51-56` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-SCL-004 | – | RB | DEVICES | Checksum XOR (Toledo/GSI) opcional en parser | Test: checksum valida | `scale_parser.py:80-89` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | validar_checksum |

---

### Sección: SEMAFORO — HAL de Semáforo (RF + RB)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SMH-001 | – | RF | SEMAFORO | `SemaforoHAL` abstracto: leer_estado(), enviar_comando(), conectar/cerrar | Test: interfaz | `semaforo_hal.py` | SEMAFORO.md | IMPLEMENTADO | |
| REQ-FN-SMH-002 | – | RF | SEMAFORO | `HttpSemaforoHAL` (POST/GET 127.0.0.1:8080/api/semaforo) + `SerialSemaforoHAL` (/dev/bsdd_semaforo_acm) | Test: ambos HAL | `semaforo_hal.py` | SEMAFORO.md | IMPLEMENTADO | HTTP + USB serie |
| REQ-FN-SMH-003 | – | RF | SEMAFORO | `normalizar_comando()`: forma canónica + alias `luz` + atajos planos `{"rojo":true}` + `zumbador` + `all/reset/automatico` | Test: 12 atajos planos | `semaforo_hal.py` + `semaforo_service.py:163-178` | SEMAFORO.md | IMPLEMENTADO | SPEC §5.6 |
| RB-SMH-001 | – | RB | SEMAFORO | Protocolo: http\|serial (Modbus/MQTT diferidos) | Test: solo 2 valores | `semaforo_hal.py` + BD CHECK | SEMAFORO.md | IMPLEMENTADO | Migración 026 |

---

### Sección: DB_ENGINE — Motor de BD por Prefijo (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-DBE-001 | – | RNF | DB | Motor decidido SOLO por prefijo DATABASE_URL (postgresql+asyncpg:// \| mssql+aioodbc://) sin env vars nuevas | Test: motor correcto | `db_engine.py:209-212` | MANEJO_DB.md §11.5 | IMPLEMENTADO | detectar_motor() |
| REQ-NF-DBE-002 | – | RNF | DB | `database_url_sync` derivado en memoria si vacío/incoherente (PREFIJO_SYNC) | Test: sync URL correcta | `db_engine.py:220-226` | MANEJO_DB.md §11.5 | IMPLEMENTADO | derivar_url_sync() |
| REQ-NF-DBE-003 | – | RNF | DB | SQL Server Fase 1 (modo degradado): drivers opcionales (extra sqlserver), WServer NO aplica DDL | Test: arranca sin drivers | `db_engine.py` + `database.py` | MANEJO_DB.md §11.5 | IMPLEMENTADO | Opción B |
| REQ-NF-DBE-004 | – | RNF | DB | WServer sin drivers → 503 `sqlserver_sin_drivers` (no aborta arranque, Opción B) | Test: 503 código | `db_engine.py:144-154, 416-428` | MANEJO_DB.md §11.5 | IMPLEMENTADO | DriversFaltantesError |
| REQ-NF-DBE-005 | – | RNF | DB | Esquema ausente/servidor caído → 503 `esquema_mssql_pendiente` / `sqlserver_sin_conexion` | Test: 503 códigos | `db_engine.py:405-478` | MANEJO_DB.md §11.5 | IMPLEMENTADO | manejador_error_bd |
| REQ-NF-DBE-006 | – | RNF | DB | Caché estado esquema (TTL 60s) + reinicio total en `reiniciar_estado_esquema()` | Test: TTL 60s | `db_engine.py:106-142` | MANEJO_DB.md §11.5 | IMPLEMENTADO | Caché thread-safe |
| REQ-NF-DBE-006 | – | RNF | DB | Pyodbc pooling desactivado (`pyodbc.pooling=False`) para evitar HY000 "Connection is busy" | Test: sin HY000 | `db_engine.py:163-179` | MANEJO_DB.md | IMPLEMENTADO | `desactivar_pooling_pyodbc()` |

---

### Sección: LICENSE — Cliente License Manager (RNF + RB)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-LIC-001 | – | RNF | LICENSE | Flujo anti-fake-server: POST /token → POST /validate → verifica firma Ed25519 (9 SIGNED_FIELDS) | Test: firma válida | `license_client.py:124-140` | USO-API.md | IMPLEMENTADO | Ed25519 |
| REQ-NF-LIC-002 | – | RNF | LICENSE | Anti-replay: nonce único en memoria (por proceso), server_time ±5min/+24h asimétrico | Test: nonce + time window | `license_client.py:158-178, 181-189` | USO-API.md | IMPLEMENTADO | Ventana asimétrica |
| REQ-NF-LIC-003 | – | RNF | LICENSE | Cache TTL 300s (`license_cache_ttl_seconds`) + degradación offline si LM inaccesible | Test: cache + fallback | `license_client.py:237-242, 433-473` | SESIONES.md | IMPLEMENTADO | `validate_cached()` |
| REQ-NF-LIC-004 | – | RNF | LICENSE | `validate_or_activate()`: auto-activa si AVAILABLE/DEVICE_NOT_REGISTERED (no en HARDWARE_MISMATCH) | Test: auto-activación | `license_client.py:369-431` | MANEJO_DB.md | IMPLEMENTADO | Auto-activación |
| REQ-NF-LIC-004 | – | RNF | LICENSE | LM Stub para E2E: FastAPI firma Ed25519 real, modos valid/invalid/expired/tamper/unreachable | Test: 33 tests E2E | `scripts/lm_stub.py` | ../AGENTS.md | IMPLEMENTADO | Claves efímeras en CI |
| RB-LIC-022 | – | RB | LICENSE | Límite sesiones: `limite_sesiones_por_tier()` → DEMO=3, resto=None (fuente única para /auth/license) | Test: DEMO=3 | `llave_activacion_service.py:84-92` | SESIONES.md | IMPLEMENTADO | Usado en /auth/license |
| RB-LIC-023 | – | RB | LICENSE | Llave activación: BS-XXXX-XXXX-XXXX (SHA-256, 7d default, máx 90d, alfabeto sin 0/O/1/I) | Test: formato + hash | `llave_activacion_service.py:54-71` | MANEJO_DB.md | IMPLEMENTADO | `_ALFABETO` |
| RB-LIC-024 | – | RB | LICENSE | Una llave activa por usuario: emitir nueva → revoca anterior (estado=revocada) | Test: previa revocada | `llave_activacion_service.py:132-146` | MANEJO_DB.md | IMPLEMENTADO | Un solo uso/usuario |
| RB-LIC-025 | – | RB | LICENSE | Canje: SELECT FOR UPDATE + valida estado=activa + expira_en > ahora → consumida + notifica dueño | Test: 400 si consumida | `llave_activacion_service.py:166-217` | MANEJO_DB.md | IMPLEMENTADO | Idempotente FOR UPDATE |
| RB-LIC-026 | – | RB | LICENSE | Notificación dueño: dedup_key=`llave_activacion:{id}` + sesiones usadas/quedan según tier | Test: idempotente | `llave_activacion_service.py:238-289` | MANEJO_DB.md | IMPLEMENTADO | SAVEPOINT dedup |

---

## Sección: INSTALLER — Instalador y Onboarding

*Se poblará en Fase 9*

---

## Sección: WSERVER — Runtime Local

*Se poblará en Fase 9*

---

## Apéndice: Referencias Rápidas a Código Crítico

| Archivo | Qué contiene | Relevante para |
|---------|--------------|----------------|
| `backend/balansoft-ws-local.sql` | Esquema local canónico (31 tablas) | FASE 1 — RB de BD |
| `backend/balansoft-ws-server.sql` | Esquema servidor (10 tablas) | FASE 1 — RB de BD |
| `backend/migrations/*.sql` | 30+ migraciones idempotentes | FASE 1 — RB de BD |
| `backend/app/models/__init__.py` | 45 modelos ORM local (1121 líneas) | FASE 2 — RB de ORM |
| `backend/app/models_server.py` | 10 modelos ORM servidor (298 líneas) | FASE 2 — RB de ORM |
| `backend/app/schemas/__init__.py` | Esquemas Pydantic request/response (1407 líneas) | FASE 3 — RB de validación |
| `backend/app/schemas/vinculos.py` | Schemas enlace balanza-indicador | FASE 3 — RB de validación |
| `backend/app/api/v1/endpoints/` | Endpoints REST | FASE 4 — RF de API |
| `backend/app/services/` | Lógica de negocio pura | FASE 5 — RF + RB |
| `backend/app/core/config.py` | Config centralizada (pydantic-settings) | FASE 6 — RNF |
| `backend/app/core/seguridad_matrix.py` | Matriz 18 módulos × 3 roles | FASE 6 — RF |
| `backend/app/core/monitoring.py` | Métricas Prometheus | FASE 6 — RNF |
| `backend/app/core/scale_parser.py` | Parser tramas básculas multi-marca | FASE 6 — RF + RB |
| `backend/app/core/scale_hal.py` | HAL serial/TCP + factory | FASE 6 — RF |
| `backend/app/core/scale_session.py` | Sesiones persistentes básculas | FASE 6 — RF |
| `backend/app/core/db_engine.py` | Motor BD por prefijo + guardias | FASE 6 — RNF |
| `backend/app/core/license_client.py` | Cliente LM Ed25519 + cache | FASE 6 — RNF + RB |
| `backend/app/core/seguridad_matrix.py` | Matriz 18 módulos × 3 roles | FASE 6 — RF |
| `backend/app/core/scale_parser.py` | Parser tramas básculas | FASE 6 — RB |
| `backend/app/core/semaforo_hal.py` | HAL semáforo HTTP/Serial | FASE 6 — RF |
| `backend/app/core/i18n.py` | i18n backend | FASE 6 — RNF |
| `backend/app/core/rate_limit.py` | Rate limiting sliding window | FASE 6 — RNF |
| `backend/app/core/logging_config.py` | Logging rotado text/json | FASE 6 — RNF |
| `backend/tests/` | Tests backend (1100+ unit + 34 E2E) | FASE 7 — Criterios aceptación |
| `frontend/lib/presentation/screens/` | Pantallas Flutter | FASE 8 — RF de UI |
| `frontend/lib/bloc/` | BLoCs/Cubits | FASE 8 — Flujos usuario |
| `frontend/lib/data/repositories/` | Repositorios + sync queue | FASE 8 — RNF offline-first |
| `frontend/lib/core/i18n/` | Traducciones (621 claves × 3) | FASE 8 — RNF usabilidad |
| `frontend/lib/core/config/station_config.dart` | config.json, StationRole | FASE 8 — RF instalador |
| `backend/wserver.py` | WServer bootstrap | FASE 9 — RF WServer |
| `backend/WServer.spec` | PyInstaller spec | FASE 9 — RNF portabilidad |
| `BALANSOFT-INSTALLER/gui/steps/` | Pasos del instalador Tk | FASE 9 — RF instalador |

| Archivo | Qué contiene | Relevante para |
|---------|--------------|----------------|
| `backend/balansoft-ws-local.sql` | Esquema local canónico (31 tablas) | FASE 1 — RB de BD |
| `backend/balansoft-ws-server.sql` | Esquema servidor (10 tablas) | FASE 1 — RB de BD |
| `backend/migrations/*.sql` | 30+ migraciones idempotentes | FASE 1 — RB de BD |
| `backend/app/models/__init__.py` | 45 modelos ORM local (1121 líneas) | FASE 2 — RB de ORM |
| `backend/app/models_server.py` | 10 modelos ORM servidor (298 líneas) | FASE 2 — RB de ORM |
| `backend/app/schemas/` | Esquemas Pydantic request/response | FASE 3 — RB de validación |
| `backend/app/api/v1/endpoints/` | Endpoints REST | FASE 4 — RF de API |
| `backend/app/services/` | Lógica de negocio pura | FASE 5 — RF + RB |
| `backend/app/core/` | Config, seguridad, HAL, monitoring, BD engine | FASE 6 — RNF + RB |
| `backend/tests/` | Tests backend (1100+ unit + 34 E2E) | FASE 7 — Criterios de aceptación |
| `frontend/lib/presentation/screens/` | Pantallas Flutter | FASE 8 — RF de UI |
| `frontend/lib/bloc/` | BLoCs/Cubits | FASE 8 — Flujos de usuario |
| `frontend/lib/data/repositories/` | Repositorios + sync queue | FASE 8 — RNF offline-first |
| `frontend/lib/core/i18n/` | Traducciones (621 claves × 3) | FASE 8 — RNF usabilidad |
| `frontend/lib/core/config/station_config.dart` | config.json, StationRole | FASE 8 — RF instalador |
| `backend/wserver.py` | WServer bootstrap | FASE 9 — RF WServer |
| `backend/WServer.spec` | PyInstaller spec | FASE 9 — RNF portabilidad |
| `BALANSOFT-INSTALLER/gui/steps/` | Pasos del instalador Tk | FASE 9 — RF instalador |

---

## FASE 6 — CORE: CONFIGURACIÓN, SEGURIDAD, HAL, MONITOREO, BD ENGINE (RNF + RB)

Fuentes: `backend/app/core/*.py`

### Sección: CONFIG — Configuración Centralizada (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-CFG-001 | – | RNF | CONFIG | `Settings` con pydantic-settings: `.env` + env vars, case-insensitive, extra=ignore | Test: carga settings | `config.py:21-27` | MANEJO_DB.md §11 | IMPLEMENTADO | |
| REQ-NF-CFG-002 | – | RNF | CONFIG | `app_role`: "local" (estación) \| "server" (central) — selecciona BD y routers | Test: rol correcto | `config.py:41` | MANEJO_DB.md | IMPLEMENTADO | Arquitectura 2 BDs |
| REQ-NF-CFG-003 | – | RNF | CONFIG | `central_timeout` default 30s (1-600s) + 1 reintento único en login-central | Test: timeout + retry | `config.py:49` | MANEJO_DB.md §11 | IMPLEMENTADO | ConectTimeout/ReadTimeout |
| REQ-NF-CFG-004 | – | RNF | CONFIG | Fail-fast producción: aborta si DEBUG_MODE=true o SECRET_KEY default o LM public key ausente | Test: ValueError en prod | `config.py:168-210` | MANEJO_DB.md | IMPLEMENTADO | _validar_entorno_produccion |
| REQ-NF-CFG-005 | – | RNF | CONFIG | Motor BD por prefijo DATABASE_URL (postgresql+asyncpg:// \| mssql+aioodbc://) sin env vars nuevas | Test: motor correcto | `config.py:213-247` | MANEJO_DB.md §11.5 | IMPLEMENTADO | _coherencia_motores |
| REQ-NF-CFG-006 | – | RNF | CONFIG | `database_url_sync` derivado en memoria si vacío/incoherente (PREFIJO_SYNC) | Test: sync URL correcta | `config.py:220-226` | MANEJO_DB.md | IMPLEMENTADO | derivar_url_sync |
| REQ-NF-CFG-007 | – | RNF | CONFIG | Rate limiting: enabled/disabled, login=5, register=3, password=5, window=60s | Test: 429 si excede | `config.py:143-149` | OBSERVABILIDAD.md | IMPLEMENTADO | Sliding window cachetools |
| REQ-NF-CFG-008 | – | RNF | CONFIG | Backups GFS: retention_days=0 (sin límite), keep_daily=7, weekly=5, monthly=12 | Test: retención correcta | `config.py:154-166` | MANEJO_DB.md §11 | IMPLEMENTADO | Rotación abuelo-padre-hijo |
| REQ-NF-CFG-009 | – | RNF | CONFIG | `license_product_code="WS"` (default config.py es "BWS" — ojo) | Test: código correcto | `config.py:63` | MANEJO_DB.md | IMPLEMENTADO | LM espera "WS" |
| REQ-NF-CFG-010 | – | RNF | CONFIG | Logging: log_format text\|json, rotación size (5MB default, 5 backups) | Test: archivo rotado | `config.py:90-96` | OBSERVABILIDAD.md | IMPLEMENTADO | RotatingFileHandler |

---

### Sección: SEGURIDAD — Matriz de Permisos (RF + RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SEC-001 | – | RF | SECURITY | Matriz 18 módulos × 3 roles (ADMIN/OPERADOR/AUDITOR) con acceso ver/editar/ninguno | Test: matriz correcta | `seguridad_matrix.py:15-115` | MANEJO_DB.md §12 | IMPLEMENTADO | 45 módulos definidos |
| REQ-FN-SEC-002 | – | RF | SECURITY | ADMIN forzado a "editar" en todos los módulos (no degradable) | Test: ADMIN siempre editar | `seguridad_matrix.py:53` | MANEJO_DB.md §12 | IMPLEMENTADO | MATRIZ_DEFECTO |
| REQ-FN-SEC-003 | – | RF | SECURITY | OPERADOR: edita inicio/terceros/clientes/proveedores/camiones/conductores/transportes/categorias/productos/almacenes/entradas/salidas/reportes/diseno_ticket/ajustes_inventario/reportes_* | Test: accesos OPERADOR | `seguridad_matrix.py:54-83` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-FN-SEC-004 | – | RF | SECURITY | AUDITOR: ver la mayoría, edita solo inicio/reportes/reportes_* | Test: accesos AUDITOR | `seguridad_matrix.py:85-114` | MANEJO_DB.md | IMPLEMENTADO | |
| REQ-NF-SEC-001 | – | RNF | SECURITY | `permisos_acceso` tabla PK (id_empresa, rol, modulo) — override por empresa | Test: override persiste | `seguridad_matrix.py:47` + tabla BD | MANEJO_DB.md §12 | IMPLEMENTADO | Matriz efectiva = BD o default |

---

### Sección: I18N — Internacionalización (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-I18N-001 | – | RNF | I18N | Backend: `i18n.py` con diccionarios es/en/pt, `t()` resuelve por `?idioma=` o `Accept-Language` | Test: 3 idiomas | `i18n.py` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | 621 claves/idioma |
| REQ-NF-I18N-002 | – | RNF | I18N | Frontend: `translations.dart` 621 claves × 3 idiomas, paridad verificada por test | Test: paridad | `translations.dart` | I18N_Y_ONBOARDING.md | IMPLEMENTADO | |

---

### Sección: MONITORING — Observabilidad (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-OBS-001 | – | RNF | OBSERVABILITY | `MetricsMiddleware`: balansoft_http_requests_total (method,endpoint,status) | Test: métrica expuesta | `monitoring.py:33-37` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-002 | – | RNF | OBSERVABILITY | `REQUEST_LATENCY` Histogram buckets 0.01-5.0s (method,endpoint) | Test: buckets correctos | `monitoring.py:39-44` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-003 | – | RNF | OBSERVABILITY | `PESAJES_TOTAL` Counter (estatus, tier) + `LICENSE_ERRORS` (tier, reason) + `ACTIVE_USERS` (tier) | Test: contadores negocio | `monitoring.py:46-62` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-004 | – | RNF | OBSERVABILITY | `_normalize_path()`: UUIDs e IDs numéricos → `{id}` (cardinalidad acotada) | Test: path normalizado | `monitoring.py:69-76` | OBSERVABILIDAD.md | IMPLEMENTADO | NUNCA id_empresa en métricas |
| REQ-NF-OBS-005 | – | RNF | OBSERVABILITY | `GET /metrics` endpoint Prometheus (fuera de OpenAPI), flag METRICS_ENABLED | Test: 200 text/plain | `monitoring.py:128-129` | OBSERVABILIDAD.md | IMPLEMENTADO | |
| REQ-NF-OBS-005 | – | RNF | OBSERVABILITY | Rate limiting sliding window (cachetools) 429 + Retry-After, /health /metrics exentos | Test: 429 + header | `rate_limit.py` | OBSERVABILIDAD.md | IMPLEMENTADO | No distribuido (Redis pendiente) |
| REQ-NF-OBS-006 | – | RNF | OBSERVABILITY | Logging: consola + archivo rotado (RotatingFileHandler), text\|json (LOG_FORMAT) | Test: archivo rotado | `logging_config.py` | OBSERVABILIDAD.md | IMPLEMENTADO | deploy/balansoft-ws.logrotate |

---

### Sección: SCALE — HAL de Básculas (RF + RB)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SCL-001 | – | RF | DEVICES | `ScaleHAL` abstracto: read_weight(), is_stable(), conectar/leer_muestra/cerrar (persistente) | Test: interfaz | `scale_hal.py:96-134` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| REQ-FN-SCL-002 | – | RF | DEVICES | `SerialScaleHAL`: pyserial, lock por puerto (threading.Lock), reintenta 3x, timeout 1s | Test: lock serial | `scale_hal.py:136-256` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Concurrencia serial |
| REQ-FN-SCL-003 | – | RF | DEVICES | `TcpScaleHAL`: asyncio, auto-detección JSON/ASCII, emparejamiento persistente, buffer drenado | Test: auto-detect | `scale_hal.py:278-569` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Auto-detect formato |
| REQ-FN-SCL-004 | – | RF | DEVICES | `ScaleSession`: conexión viva + caché último peso + reconexión backoff (0.5-5s) | Test: reconexión | `scale_session.py:62-192` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | 1 task/balanza |
| REQ-FN-SCL-005 | – | RF | DEVICES | `ScaleSessionManager`: 1 sesión/balanza, recrea si cambia config (clave incluye formato/baudrate/delimitador) | Test: recrea sesión | `scale_session.py:216-270` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | `get_scale_session_manager()` |
| REQ-FN-SCL-006 | – | RF | DEVICES | `get_scale_hal()`: prioridad TCP (ip+puerto) → serial (puerto_com), propaga formato/baudrate/delimitador | Test: HAL correcto | `scale_hal.py:584-620` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Factory |
| RB-SCL-001 | – | RB | DEVICES | `parse_weight_frame()`: multi-marca (Toledo/GSI, Rice Lake, MT-SICS, signo suelto, STX/ETX+XOR) | Test: parsers | `scale_parser.py:177-206` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Parser puro |
| RB-SCL-002 | – | RB | DEVICES | Anti-falso-positivo: rechaza números desnudos (dirección, checksum); requiere signo/decimal/unidad | Test: rechaza desnudos | `scale_parser.py:104-174` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | Principio anti-falso-positivo |
| RB-SCL-003 | – | RB | DEVICES | Tolerancia capacidad 105% (TOLERANCIA_CAPACIDAD=1.05) — rechaza sobrecarga | Test: 105% rechaza | `scale_parser.py:48,172` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | OIML R 76-1 |
| RB-SCL-004 | – | RB | DEVICES | Delimitadores: lf\|cr\|crlf\|stx_etx (configurable por balanza) | Test: delimitadores | `scale_hal.py:51-56` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | |
| RB-SCL-004 | – | RB | DEVICES | Checksum XOR (Toledo/GSI) opcional en parser | Test: checksum valida | `scale_parser.py:80-89` | BALANZAS_SOPORTADAS.md | IMPLEMENTADO | validar_checksum |

---

### Sección: SEMAFORO — HAL de Semáforo (RF + RB)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-FN-SMH-001 | – | RF | SEMAFORO | `SemaforoHAL` abstracto: leer_estado(), enviar_comando(), conectar/cerrar | Test: interfaz | `semaforo_hal.py` | SEMAFORO.md | IMPLEMENTADO | |
| REQ-FN-SMH-002 | – | RF | SEMAFORO | `HttpSemaforoHAL` (POST/GET 127.0.0.1:8080/api/semaforo) + `SerialSemaforoHAL` (/dev/bsdd_semaforo_acm) | Test: ambos HAL | `semaforo_hal.py` | SEMAFORO.md | IMPLEMENTADO | HTTP + USB serie |
| REQ-FN-SMH-003 | – | RF | SEMAFORO | `normalizar_comando()`: forma canónica + alias `luz` + atajos planos `{"rojo":true}` + `zumbador` + `all/reset/automatico` | Test: 12 atajos planos | `semaforo_hal.py` + `semaforo_service.py:163-178` | SEMAFORO.md | IMPLEMENTADO | SPEC §5.6 |
| RB-SMH-001 | – | RB | SEMAFORO | Protocolo: http\|serial (Modbus/MQTT diferidos) | Test: solo 2 valores | `semaforo_hal.py` + BD CHECK | SEMAFORO.md | IMPLEMENTADO | Migración 026 |

---

### Sección: DB_ENGINE — Motor de BD por Prefijo (RNF)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-DBE-001 | – | RNF | DB | Motor decidido SOLO por prefijo DATABASE_URL (postgresql+asyncpg:// \| mssql+aioodbc://) sin env vars nuevas | Test: motor correcto | `db_engine.py:209-212` | MANEJO_DB.md §11.5 | IMPLEMENTADO | detectar_motor() |
| REQ-NF-DBE-002 | – | RNF | DB | `database_url_sync` derivado en memoria si vacío/incoherente (PREFIJO_SYNC) | Test: sync URL correcta | `db_engine.py:220-226` | MANEJO_DB.md §11.5 | IMPLEMENTADO | derivar_url_sync() |
| REQ-NF-DBE-003 | – | RNF | DB | SQL Server Fase 1 (modo degradado): drivers opcionales (extra sqlserver), WServer NO aplica DDL | Test: arranca sin drivers | `db_engine.py` + `database.py` | MANEJO_DB.md §11.5 | IMPLEMENTADO | Opción B |
| REQ-NF-DBE-004 | – | RNF | DB | WServer sin drivers → 503 `sqlserver_sin_drivers` (no aborta arranque, Opción B) | Test: 503 código | `db_engine.py:144-154, 416-428` | MANEJO_DB.md §11.5 | IMPLEMENTADO | DriversFaltantesError |
| REQ-NF-DBE-005 | – | RNF | DB | Esquema ausente/servidor caído → 503 `esquema_mssql_pendiente` / `sqlserver_sin_conexion` | Test: 503 códigos | `db_engine.py:405-478` | MANEJO_DB.md §11.5 | IMPLEMENTADO | manejador_error_bd |
| REQ-NF-DBE-006 | – | RNF | DB | Caché estado esquema (TTL 60s) + reinicio total en `reiniciar_estado_esquema()` | Test: TTL 60s | `db_engine.py:106-142` | MANEJO_DB.md §11.5 | IMPLEMENTADO | Caché thread-safe |
| REQ-NF-DBE-006 | – | RNF | DB | Pyodbc pooling desactivado (`pyodbc.pooling=False`) para evitar HY000 "Connection is busy" | Test: sin HY000 | `db_engine.py:163-179` | MANEJO_DB.md | IMPLEMENTADO | `desactivar_pooling_pyodbc()` |

---

### Sección: LICENSE — Cliente License Manager (RNF + RB)

| ID | ID original (spec) | Tipo | Dominio | Descripción | Criterio de aceptación | Fuente (código) | Fuente (doc) | Estado | Notas |
|----|-------------------|------|---------|-------------|------------------------|-----------------|--------------|--------|-------|
| REQ-NF-LIC-001 | – | RNF | LICENSE | Flujo anti-fake-server: POST /token → POST /validate → verifica firma Ed25519 (9 SIGNED_FIELDS) | Test: firma válida | `license_client.py:124-140` | USO-API.md | IMPLEMENTADO | Ed25519 |
| REQ-NF-LIC-002 | – | RNF | LICENSE | Anti-replay: nonce único en memoria (por proceso), server_time ±5min/+24h asimétrico | Test: nonce + time window | `license_client.py:158-178, 181-189` | USO-API.md | IMPLEMENTADO | Ventana asimétrica |
| REQ-NF-LIC-003 | – | RNF | LICENSE | Cache TTL 300s (`license_cache_ttl_seconds`) + degradación offline si LM inaccesible | Test: cache + fallback | `license_client.py:237-242, 433-473` | SESIONES.md | IMPLEMENTADO | `validate_cached()` |
| REQ-NF-LIC-004 | – | RNF | LICENSE | `validate_or_activate()`: auto-activa si AVAILABLE/DEVICE_NOT_REGISTERED (no en HARDWARE_MISMATCH) | Test: auto-activación | `license_client.py:369-431` | MANEJO_DB.md | IMPLEMENTADO | Auto-activación |
| REQ-NF-LIC-004 | – | RNF | LICENSE | LM Stub para E2E: FastAPI firma Ed25519 real, modos valid/invalid/expired/tamper/unreachable | Test: 33 tests E2E | `scripts/lm_stub.py` | ../AGENTS.md | IMPLEMENTADO | Claves efímeras en CI |
| RB-LIC-022 | – | RB | LICENSE | Límite sesiones: `limite_sesiones_por_tier()` → DEMO=3, resto=None (fuente única para /auth/license) | Test: DEMO=3 | `llave_activacion_service.py:84-92` | SESIONES.md | IMPLEMENTADO | Usado en /auth/license |
| RB-LIC-023 | – | RB | LICENSE | Llave activación: BS-XXXX-XXXX-XXXX (SHA-256, 7d default, máx 90d, alfabeto sin 0/O/1/I) | Test: formato + hash | `llave_activacion_service.py:54-71` | MANEJO_DB.md | IMPLEMENTADO | `_ALFABETO` |
| RB-LIC-024 | – | RB | LICENSE | Una llave activa por usuario: emitir nueva → revoca anterior (estado=revocada) | Test: previa revocada | `llave_activacion_service.py:132-146` | MANEJO_DB.md | IMPLEMENTADO | Un solo uso/usuario |
| RB-LIC-025 | – | RB | LICENSE | Canje: SELECT FOR UPDATE + valida estado=activa + expira_en > ahora → consumida + notifica dueño | Test: 400 si consumida | `llave_activacion_service.py:166-217` | MANEJO_DB.md | IMPLEMENTADO | Idempotente FOR UPDATE |
| RB-LIC-026 | – | RB | LICENSE | Notificación dueño: dedup_key=`llave_activacion:{id}` + sesiones usadas/quedan según tier | Test: idempotente | `llave_activacion_service.py:238-289` | MANEJO_DB.md | IMPLEMENTADO | SAVEPOINT dedup |

---

## Sección: INSTALLER — Instalador y Onboarding

*Se poblará en Fase 9*

---

## Sección: WSERVER — Runtime Local

*Se poblará en Fase 9*

---

## Apéndice: Referencias Rápidas a Código Crítico

| Archivo | Qué contiene | Relevante para |
|---------|--------------|----------------|
| `backend/balansoft-ws-local.sql` | Esquema local canónico (31 tablas) | FASE 1 — RB de BD |
| `backend/balansoft-ws-server.sql` | Esquema servidor (10 tablas) | FASE 1 — RB de BD |
| `backend/migrations/*.sql` | 30+ migraciones idempotentes | FASE 1 — RB de BD |
| `backend/app/models/__init__.py` | 45 modelos ORM local (1121 líneas) | FASE 2 — RB de ORM |
| `backend/app/models_server.py` | 10 modelos ORM servidor (298 líneas) | FASE 2 — RB de ORM |
| `backend/app/schemas/__init__.py` | Esquemas Pydantic request/response (1407 líneas) | FASE 3 — RB de validación |
| `backend/app/schemas/vinculos.py` | Schemas enlace balanza-indicador | FASE 3 — RB de validación |
| `backend/app/api/v1/endpoints/` | Endpoints REST | FASE 4 — RF de API |
| `backend/app/services/` | Lógica de negocio pura | FASE 5 — RF + RB |
| `backend/app/core/config.py` | Config centralizada (pydantic-settings) | FASE 6 — RNF |
| `backend/app/core/seguridad_matrix.py` | Matriz 18 módulos × 3 roles | FASE 6 — RF |
| `backend/app/core/monitoring.py` | Métricas Prometheus | FASE 6 — RNF |
| `backend/app/core/scale_parser.py` | Parser tramas básculas multi-marca | FASE 6 — RF + RB |
| `backend/app/core/scale_hal.py` | HAL serial/TCP + factory | FASE 6 — RF |
| `backend/app/core/scale_session.py` | Sesiones persistentes básculas | FASE 6 — RF |
| `backend/app/core/db_engine.py` | Motor BD por prefijo + guardias | FASE 6 — RNF |
| `backend/app/core/license_client.py` | Cliente LM Ed25519 + cache | FASE 6 — RNF + RB |
| `backend/app/core/seguridad_matrix.py` | Matriz 18 módulos × 3 roles | FASE 6 — RF |
| `backend/app/core/scale_parser.py` | Parser tramas básculas | FASE 6 — RB |
| `backend/app/core/semaforo_hal.py` | HAL semáforo HTTP/Serial | FASE 6 — RF |
| `backend/app/core/i18n.py` | i18n backend | FASE 6 — RNF |
| `backend/app/core/rate_limit.py` | Rate limiting sliding window | FASE 6 — RNF |
| `backend/app/core/logging_config.py` | Logging rotado text/json | FASE 6 — RNF |
| `backend/tests/` | Tests backend (1100+ unit + 34 E2E) | FASE 7 — Criterios aceptación |
| `frontend/lib/presentation/screens/` | Pantallas Flutter | FASE 8 — RF de UI |
| `frontend/lib/bloc/` | BLoCs/Cubits | FASE 8 — Flujos usuario |
| `frontend/lib/data/repositories/` | Repositorios + sync queue | FASE 8 — RNF offline-first |
| `frontend/lib/core/i18n/` | Traducciones (621 claves × 3) | FASE 8 — RNF usabilidad |
| `frontend/lib/core/config/station_config.dart` | config.json, StationRole | FASE 8 — RF instalador |
| `backend/wserver.py` | WServer bootstrap | FASE 9 — RF WServer |
| `backend/WServer.spec` | PyInstaller spec | FASE 9 — RNF portabilidad |
| `BALANSOFT-INSTALLER/gui/steps/` | Pasos del instalador Tk | FASE 9 — RF instalador |
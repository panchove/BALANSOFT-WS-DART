# Inventario de Documentación — BALANSOFT-WS

**Versión:** 1.0  
**Fecha:** 2026-10-26  
**Estado:** Vigente

---

## Resumen de Estructura

```
docs/
├── *.md (13 archivos raíz)
├── evidencia/ (3 archivos)
├── DOCUMENTACION VIEJA/ (7 archivos + legacy/)
├── requisitos/ (carpeta de trabajo actual)
specs/ (en raíz, no en docs/)
└── 001-tipografia-config/ (spec formal + plan + tasks + evidencia)
```

---

## 1. Documentación Raíz (docs/*.md) — DOCUMENTACIÓN VIGENTE

| Archivo                   | Propósito                                                                     | Estado                     | IDs propios               | Tipo fuente                           |
|---------------------------|-------------------------------------------------------------------------------|----------------------------|---------------------------|---------------------------------------|
| `MANEJO_DB.md`            | Arquitectura de dos BD, setup dev, flujo login, estado y plan                 | **Vigente / Autoritativa** | No (usa REQ-FN/AR/INT/UX) | Arquitectura + Requisitos             |
| `NAV.md`                  | Navegación/sidebar, claves de menú, índices                                   | **Vigente / Autoritativa** | No                        | UI/UX                                 |
| `INPUTS_MAP.md`           | Atajos de teclado de la UI                                                    | **Vigente / Autoritativa** | No                        | UX                                    |
| `MODELO_ESTANDAR.md`      | Roles y reglas de negocio invariables                                         | **Vigente / Autoritativa** | No                        | Reglas de negocio                     |
| `I18N_Y_ONBOARDING.md`    | i18n (es/en/pt, 621 claves) y onboarding                                      | **Vigente / Autoritativa** | No                        | RNF Usabilidad                        |
| `USO-API.md`              | Documentación de endpoints                                                    | **Vigente / Autoritativa** | No                        | API Contract                          |
| `SESIONES.md`             | Gestión de sesiones, límites por tier                                         | **Vigente / Autoritativa** | No                        | RB + RNF                              |
| `PLANES-PAGOS.md`         | Planes DEMO/Básico/Premium, features, límites                                 | **Vigente / Autoritativa** | No                        | RB + RF (CONTRADICCIÓN conocida)      |
| `OBSERVABILIDAD.md`       | Métricas, alertas, diagnóstico, Grafana                                       | **Vigente / Autoritativa** | No                        | RNF Observabilidad                    |
| `BALANZAS_SOPORTADAS.md`  | Matriz de marcas/protocolos de indicadores reales                             | **Vigente / Autoritativa** | No                        | RF Integración Hardware               |
| `SEMAFORO.md`             | Ciclo del semáforo, integración, API, HAL                                     | **Vigente / Autoritativa** | No                        | RF + RB SEMAFORO                      |
| `DISPOSITIVOS.md`         | Dispositivos de campo (básculas, indicadores, semáforos, cámaras, impresoras) | **Vigente / Autoritativa** | No                        | RF DEVICES                            |
| `TERMINOS_CONDICIONES.md` | Contrato comercial, tiers, features, SLA                                      | **Vigente / Contrato**     | No                        | RB Comercial (CONTRADICCIÓN conocida) |
| `constitution.md`         | Reglas invariables del proyecto (5 reglas)                                    | **Vigente / Constitución** | No                        | Principios arquitectónicos            |

---

## 2. docs/evidencia/ — EVIDENCIA EMPÍRICA (RNF Performance)

| Archivo                             | Propósito                                           | Estado        | Métricas clave                     | Tipo fuente |
|-------------------------------------|-----------------------------------------------------|---------------|------------------------------------|-------------|
| `volumen-analisis.md`               | Análisis P2: 50k boletos, 11 endpoints, p50/p95/p99 | **Evidencia** | p50/p95/p99 por endpoint, umbrales | RNF PERF    |
| `volumen-benchmark.txt`             | Resultados benchmark de volumen                     | **Evidencia** | 11 endpoints medidos               | RNF PERF    |
| `volumen-benchmark-concurrente.txt` | Resultados benchmark concurrencia (P2c)             | **Evidencia** | JWT+TCP reales, 1/5/10 operadores  | RNF PERF    |

---

## 3. specs/ (en raíz del repo) — SPECS FORMALES

| Ruta                                     | Propósito                                       | Estado                   | IDs propios                 | Tipo fuente  |
|------------------------------------------|-------------------------------------------------|--------------------------|-----------------------------|--------------|
| `specs/001-tipografia-config/spec.md`    | Spec formal: ajuste tipografía sistema + ticket | **Spec v0.4 (BORRADOR)** | **REQ-FN-001 a REQ-FN-022** | Spec formal  |
| `specs/001-tipografia-config/plan.md`    | Plan de implementación aprobado                 | **Plan v1.0**            | T1–T10b (tareas)            | Plan técnico |
| `specs/001-tipografia-config/tasks.md`   | Tasks desglosadas                               | **Tasks**                | Tareas atómicas             | Ejecución    |
| `specs/001-tipografia-config/evidencia/` | Evidencia de tests T1, T10b                     | **Evidencia**            | Overflow 60px T10b          | Evidencia    |

---

## 4. docs/DOCUMENTACION VIEJA/ — LEGACY (NO AUTORITATIVO)

| Archivo                                | Propósito                                             | Estado     | IDs propios                  | Tipo fuente               |
|----------------------------------------|-------------------------------------------------------|------------|------------------------------|---------------------------|
| `PRD.md`                               | PRD v2.0 (re-alineación a stack real FastAPI/Flutter) | **Legacy** | REQ-FN/NF/AR/INT/UX (viejos) | Requisitos históricos     |
| `ARCH.md`                              | Arquitectura v2.0 (stack real, sin HAL en backend)    | **Legacy** | REQ-NF-ARQ-XXX               | Arquitectura histórica    |
| `MODEL.md`                             | Workflow/formulario, cálculos, kardex, tolerancias    | **Legacy** | No (descripción operativa)   | Modelo de datos histórico |
| `IMPLEMENTADO.md`                      | Inventario v2.2 (lo construido verificado vs código)  | **Legacy** | No                           | Inventario histórico      |
| `DEPLOY.md`                            | Despliegue (systemd, nginx, scripts)                  | **Legacy** | No                           | Ops histórico             |
| `RESUMEN-API-LICENCIAS.md`             | Resumen API licencias                                 | **Legacy** | No                           | API histórico             |
| `UI-UX.md`                             | UI/UX (Modern Flat UI / MetroSet)                     | **Legacy** | No                           | UI histórico              |
| `legacy/DOCUMENTACION-BALANSOFT-WS.md` | Doc paralela NO autoritativa (.NET/WinForms)          | **Legacy** | No                           | Legacy profundo           |

**Nota:** La carpeta `DOCUMENTACION VIEJA` tiene espacio y mayúsculas en el nombre. Usar comillas en comandos shell.

---

## 5. Carpetas No Encontradas (RUTA NO ENCONTRADA)

| Ruta esperada      | Estado real                                    | Acción                               |
|--------------------|------------------------------------------------|--------------------------------------|
| `docs/specs/`      | **NO EXISTE** — specs está en raíz (`/specs/`) | Registrado; usar ruta real `/specs/` |
| `docs/requisitos/` | **EXISTE** (creada en Fase 0)                  | Carpeta de trabajo actual            |

---

## 6. Mapeo de Dominios a Documentación

| Dominio       | Docs Vigentes                                          | Specs                  | Evidencia    | Legacy                                        |
|---------------|--------------------------------------------------------|------------------------|--------------|-----------------------------------------------|
| AUTH          | MANEJO_DB.md, SESIONES.md, USO-API.md                  | —                      | —            | PRD.md §9, ARCH.md §11                        |
| WEIGHING      | MANEJO_DB.md §6, MODELO_ESTANDAR.md, USO-API.md        | Spec 001 (ticket)      | —            | PRD.md §5, MODEL.md, ARCH.md §6-7             |
| CATALOG       | MANEJO_DB.md, NAV.md, USO-API.md                       | —                      | —            | PRD.md, ARCH.md                               |
| KARDEX        | MANEJO_DB.md, MODELO_ESTANDAR.md, USO-API.md           | —                      | —            | PRD.md §6, MODEL.md, ARCH.md §8               |
| SYNC          | MANEJO_DB.md, SESIONES.md, USO-API.md                  | —                      | —            | PRD.md, ARCH.md                               |
| LICENSE       | MANEJO_DB.md, PLANES-PAGOS.md, SESIONES.md, USO-API.md | —                      | —            | PRD.md, ARCH.md §15, RESUMEN-API-LICENCIAS.md |
| SESSIONS      | SESIONES.md, PLANES-PAGOS.md                           | —                      | —            | PRD.md, ARCH.md                               |
| SEMAFORO      | SEMAFORO.md, DISPOSITIVOS.md, NAV.md                   | —                      | —            | — (nuevo v3.29+)                              |
| DEVICES       | DISPOSITIVOS.md, BALANZAS_SOPORTADAS.md, NAV.md        | —                      | —            | PRD.md §7, ARCH.md §9                         |
| REPORTS       | MANEJO_DB.md, USO-API.md                               | —                      | volumen-*.md | PRD.md, ARCH.md                               |
| AUDIT         | MANEJO_DB.md, USO-API.md                               | —                      | —            | PRD.md, ARCH.md §17                           |
| I18N          | I18N_Y_ONBOARDING.md, NAV.md                           | Spec 001 (i18n claves) | —            | PRD.md, ARCH.md                               |
| OBSERVABILITY | OBSERVABILIDAD.md, MANEJO_DB.md                        | —                      | —            | ARCH.md                                       |
| INSTALLER     | I18N_Y_ONBOARDING.md, MANEJO_DB.md §9-13               | —                      | —            | PRD.md, ARCH.md                               |
| WSERVER       | MANEJO_DB.md §11.5, scripts/                           | —                      | —            | ARCH.md, IMPLEMENTADO.md                      |
| PRINTING      | DISPOSITIVOS.md, USO-API.md                            | Spec 001 (ticket)      | —            | PRD.md §5.5, ARCH.md                          |

---

## 7. Contradicciones Conocidas (Pre-identificadas)

| Tema                 | Doc A (dice X)                                        | Doc B (dice Y)                                              | Código (hace Z)                                    | Prioridad |
|----------------------|-------------------------------------------------------|-------------------------------------------------------------|----------------------------------------------------|-----------|
| Gateo Básico/Premium | TERMINOS_CONDICIONES.md §4.1: "Plan Básico excluye X" | PLANES-PAGOS.md §2 + AGENTS.md: "NO se gatea por plan"      | Licencia no gatea features; solo límite sesiones   | **ALTA**  |
| HAL en backend       | PRD.md v2.0 §5: "NO hay HAL en backend"               | ARCH.md v2.0 §1: "HAL futura via estación"                  | `app/core/scale_hal.py` EXISTE (serial/TCP + live) | **MEDIA** |
| Roles usuario        | PRD.md §4: ADMIN/SUPERVISOR/OPERADOR                  | MANEJO_DB.md: ADMIN/OPERADOR/AUDITOR (TRABAJADOR fusionado) | Código: ADMIN/OPERADOR/AUDITOR (migración 025)     | **BAJA**  |
| Esquema BD           | PRD.md: `schema.sql`                                  | MANEJO_DB.md: `balansoft-ws-local.sql` + migraciones        | `balansoft-ws-local.sql` + 30 migraciones          | **BAJA**  |

---

## 8. Próximos Pasos

1. **Fase 1**: Extraer RBs de `balansoft-ws-local.sql`, `balansoft-ws-server.sql`, `migrations/*.sql`
2. **Fase 2**: Extraer RBs de modelos ORM (`app/models/`, `models_server.py`)
3. **Fase 3**: Extraer RBs de schemas Pydantic (`app/schemas/`)
4. **Fase 4**: Extraer RFs de endpoints (`app/api/v1/endpoints/`)
5. **Fase 5**: Extraer RFs+RBs de servicios (`app/services/`)
6. **Fase 6**: Extraer RNFs+RBs de core (`app/core/`)
7. **Fase 7**: Extraer criterios de aceptación de tests (`backend/tests/`, `frontend/test/`)
8. **Fase 8**: Extraer RFs de UI Flutter (`frontend/lib/`)
9. **Fase 9**: Extraer RFs de instalador y WServer
10. **Fase 10**: Consolidar + procesar specs/001, evidencia/, DOCUMENTACION VIEJA/
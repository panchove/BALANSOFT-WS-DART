# Auditoría y Gobernanza de Agentes y Skills — BALANSOFT-WS

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 25010 / ISO/IEC 27001 / ISO/IEC 42001 / ISO/IEC 17025  
**Fuente:** Sistema BALANSOFT-WS  
**Autor:** Lead Architect  

---

## 1. Identificación y Trazabilidad

### Requisitos y Decisiones Arquitectónicas Asociadas
- **AR-030**: Topología agéntica estricta de un único orquestador primario (`mode: primary`) y subagentes especializados (`mode: subagent`).
- **AR-031**: Control de accesos de herramientas y ejecución de comandos mediante modelo RBAC agéntico conforme a ISO/IEC 27001 e ISO/IEC 42001 (AIMS).
- **AR-032**: Paridad de paths de ejecución entre configuración de entorno (`opencode.json`), suite de tests (`pytest`, `flutter`) y MCP servers sobre la ruta raíz `src/`.
- **AR-033**: Política de versionado SemVer 2.0.0 Pre-release (`0.y.z-dev.B`) y trazabilidad de Git Tags: los commits regulares de desarrollo no llevan tag; únicamente los commits formales de release (`chore(release): ...`) reciben un Git Tag anotado `vX.Y.Z-dev.B`.
- **AR-034**: Sistema de Gestión de Inteligencia Artificial (AIMS) conforme a ISO/IEC 42001: delimitación estricta del alcance de los modelos y subagentes, trazabilidad de prompts/decisiones y prohibición categórica de inferencia probabilística sobre magnitudes metrológicas de pesaje legal.
- **REQ-NF-SEG-004**: El agente auditor y verificador (`bls-ws-test-qa`) tiene denegación explícita de modificación de ficheros (`deny edit/write`), garantizando separación de funciones e independencia de auditoría.

---

## 2. Propósito y Alcance

Este documento certifica el estado formal, la estructura de permisos, la gobernanza de ejecución y el catálogo de habilidades (skills) de los agentes de inteligencia artificial y automatización en el proyecto **BALANSOFT-WS**, en conformidad con:
- **ISO/IEC 25010 (Calidad del Producto Software)**: Mantenibilidad, adecuación funcional y fiabilidad.
- **ISO/IEC 27001 (Seguridad de la Información)**: Principio de mínimo privilegio, segregación de tareas y trazabilidad de cambios.
- **ISO/IEC 42001:2023 (Sistemas de Gestión de Inteligencia Artificial - AIMS)**: Gobernanza del ciclo de vida agéntico, gestión de riesgos de IA, explicabilidad y supervisión humana del orquestador.
- **ISO/IEC 17025 / OIML R 76-1 (Metrología Industrial)**: Control riguroso de agentes y reglas que tocan la captura de peso, estabilidad y emisión de tickets.

---

## 3. Matriz de Agentes y Gobernanza de Permisos

Se define la jerarquía donde únicamente **`bls-ws-lead-architect`** tiene rol primario de coordinación general:

| Identificador Agente             | Rol Operativo                   | Modo       | Política de Permisos (RBAC)                        | Justificación Normativa                                                          |
|:---------------------------------|:--------------------------------|:-----------|:---------------------------------------------------|:---------------------------------------------------------------------------------|
| **`bls-ws-lead-architect`**      | Lead Architect                  | `primary`  | `allow *`                                          | Orquestador principal, define arquitectura y delega trabajo.                     |
| **`bls-ws-planner`**             | Planificador / PM               | `subagent` | `deny *`, `allow read, grep, glob`                 | Análisis y diseño de tareas sin modificar código directamente.                   |
| **`bls-ws-engineer`**            | Ingeniero Implementador         | `subagent` | `allow *`                                          | Implementación de código en frontend, backend y WServer.                         |
| **`bls-ws-db-specialist`**       | Especialista Base de Datos      | `subagent` | `allow *`                                          | Gestión de 2 BDs, motor por prefijo y migraciones 001–025.                       |
| **`bls-ws-test-qa`**             | Auditor y Revisor QA            | `subagent` | `deny edit, write`, `allow read, grep, glob, bash` | Independencia de auditoría: no modifica código, solo verifica y ejecuta pruebas. |
| **`bls-ws-test-orchestration`**  | Orquestador de Tests            | `subagent` | `allow *`                                          | Ejecución de las 3 suites de tests (935 unit, 34 E2E, 405 flutter).              |
| **`bls-ws-ci-cd`**               | DevOps & CI/CD                  | `subagent` | `allow *`                                          | Workflows de GitHub Actions y scripts operacionales.                             |
| **`bls-ws-flutter-integration`** | Integración Flutter             | `subagent` | `allow *`                                          | Ciclo de vida Flutter, modo seed/instalado y hot reload.                         |
| **`bls-ws-ui-ux`**               | Especialista UI/UX              | `subagent` | `allow *`                                          | Accesibilidad WCAG, sistema de diseño e i18n (621 claves).                       |
| **`bls-ws-hardware-specialist`** | Especialista Hardware & Tickets | `subagent` | `allow *`                                          | HAL de básculas, concurrencia RS-232/TCP y paridad de tickets canónicos.         |
| **`bls-ws-mermaid-diagrammer`**   | Especialista Diagramación       | `subagent` | `allow *`                                          | Modelado visual Mermaid (flujos de pesaje, secuencias C4, ER y máquinas estado). |

---

## 4. Auditoría de Habilidades (Skills)

### 4.1. Catálogo Activo y Homologado
Se eliminaron archivos sin frontmatter y scripts huérfanos. El catálogo vigente consta de 13 skills con especificación YAML completa:

1. **`architecture`** (`bls-ws-architecture.md`): Principios de diseño modular, separación de capas y coordinación de runtime.
2. **`fastapi`** (`bls-ws-fastapi.md`): Capa de servicios REST, validación con Pydantic y reglas de negocio backend.
3. **`flutter`** (`bls-ws-flutter.md`): Arquitectura limpia Flutter, BLoC, inyección de dependencias y UI responsiva.
4. **`kardex`** (`bls-ws-kardex.md`): Movimientos de inventario 10 (Ingreso) y 60 (Despacho), y reversión automática en anulación.
5. **`licensing`** (`bls-ws-licensing.md`): Validación criptográfica Ed25519, activación por llaves de un solo uso y límites de sesión.
7. **`mssql`** (`bls-ws-mssql.md`): Soporte de SQL Server, motor por prefijo de DATABASE_URL, modo degradado de Fase 1 y caché de esquema (TTL 60s).
8. **`multitenancy`** (`bls-ws-multitenancy.md`): Aislamiento riguroso por `id_empresa` en endpoints, consultas y logs.
9. **`offline-sync`** (`bls-ws-offline-sync.md`): Flujo offline-first, cola de eventos local con UUIDv4 e idempotencia.
10. **`postgresql`** (`bls-ws-postgresql.md`): Fuente de verdad de datos, índices, constraints y migraciones incrementales.
11. **`printer-specialist`** (`bls-ws-printer-specialist.md`): Impresoras térmicas ESC/POS y matriciales ESC/P con tabla canónica de 5 columnas.
12. **`scale-specialist`** (`bls-ws-scale-specialist.md`): Decodificación de indicadores, HAL físico y gestión de sesiones persistentes.
13. **`security`** (`bls-ws-security.md`): Matriz de permisos (18 módulos × 3 roles), sanitización de datos y JWT.
14. **`testing`** (`bls-ws-testing.md`): Directrices de aseguramiento de calidad y prevención de regresiones.
15. **`weighing`** (`bls-ws-weighing.md`): Flujo maestro de pesaje, ciclo de estados del boleto e invariantes metrológicas.

### 4.2. Registro de Acciones de Depuración y Saneamiento
- **Archivos Huérfanos Depurados:** Eliminación de scripts temporales sueltos (`printer-specialist_*.py`, `scale-specialist_*.py`, `tcp-bluetooth-io_*.py`, `truck-weighing-system_*.py`) cuyas capacidades fueron delegadas formalmente al servidor MCP nativo `src/backend/scripts/mcp_hardware_server.py`.
- **Eliminación de Subarchivos no Indexables:** Saneamiento de fragmentos Markdown sin cabecera YAML en `.opencode/skills/` que no cumplían el estándar de especificación.
- **Normalización de Rutas:** Corrección global de todas las rutas de testing y ejecución de `backend/` y `frontend/` hacia `src/backend/` y `src/frontend/`, estandarizando el uso de `uv run` como gestor determinista de dependencias.

---

## 5. Control de Cambios y Firma Editorial

| Versión   | Fecha      | Resumen de la Modificación                                                                                                                                             | Autor               |
|:----------|:-----------|:-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|:--------------------|
| **1.4.2** | 2026-10-19 | Regularización de agentes (1 primario, 9 subagentes), alta de `bls-ws-hardware-specialist`, depuración de skills obsoletos y armonización de rutas en `opencode.json`. | Lead Architect / QA |

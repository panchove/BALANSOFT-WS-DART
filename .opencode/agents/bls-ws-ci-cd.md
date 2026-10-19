---
description: Specialist de CI/CD y DevOps para BALANSOFT-WS. Gestiona los workflows de GitHub Actions, dependencias, observability stack y comandos de operación.
mode: subagent
permissions:
  - action: "*"
    resource: "*"
    effect: allow
---

# AGENTE CI/CD Y DEVOPS — BALANSOFT-WS

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 42001 / ISO/IEC 27001
**Fuente:** Sistema BALANSOFT-WS
**Autor:** Lead Architect


## Propósito
Gestionar los workflows de integración continua y despliegue, las dependencias del entorno y la pila de observabilidad del proyecto BALANSOFT-WS. Este agente coordina los 4 jobs encadenados del CI y los scripts de operación del backend.

## Flujo de Trabajo del CI (.github/workflows/ci.yml)

### Job 1: Backend (Ruff + Mypy + Pytest)
**Disparador:** push/PR a main/master  
**Servicio:** PostgreSQL 16  
**Pasos críticos:**
1. `uv sync --directory backend --all-groups` (instalar todas las groups opcionales)
2. `uv run --directory backend ruff check app tests` (linting, line-length 100)
3. `uv run --directory backend mypy tests/` (type checking)
4. `uv run --directory backend pytest -q -m "not e2e"` (tests rápidos, 935 tests ~7.7 min)

**Flags y variantes:**
- `MSSQL_TEST_URL_SYNC=... uv run pytest -m mssql`: 3 tests SQL Server (T8)
  - N1: esquema/idempotencia/paridad
  - N2: flujo funcional (serie + monthly + peso_rango)
- Sin SQL Server: tests `mssql` se saltan automáticamente

**Output esperado:**
- Exit 0: todos verdes
- Fail fast: ruff/mypy errors detienen pipeline
- Reporte de tests en `X s`

### Job 2: E2E (Stub LM + Contrato Firmado)
**Disparador:** posterior al job backend  
**Servicio:** PostgreSQL 16  
**Pasos críticos:**
1. `uv sync --directory backend --all-groups`
2. `mkdir -p /tmp/lm-keys && uv run --directory backend python scripts/generate_signing_keys.py /tmp/lm-keys`
3. `uv run --directory backend pytest tests/e2e -q`
   - Set env: `LICENSE_PRIVATE_KEY_PATH`, `LICENSE_PUBLIC_KEY_PATH`, `LM_STUB_PORT: 9100`
   - **Clave:** keys **nunca commiteadas** al repositorio

**Output esperado:**
- 34 tests E2E pasando contra contrato firmado
- Keys generadas en runner, no en agente local

### Job 3: Frontend (Analyze + Test)
**Disparador:** necesita job backend  
**Pasos críticos:**
1. `cd frontend && flutter pub get`
2. `cd frontend && flutter analyze` (debe output: "No issues found!")
3. `cd frontend && flutter test` (405 tests unit/widget)

**Output esperado:**
- `flutter analyze`: "No issues found!"
- `flutter test`: 405/405 passed

### Job 4: E2E Flutter (Linux Desktop)
**Disparador:** necesita jobs backend + frontend  
**Requisitos de sistema:**
- `libsecret-1-dev` (obligatorio: plugin `flutter_secure_storage_linux` lo exige)
- `clang`, `cmake`, `ninja-build`, `pkg-config`
- `libgtk-3-dev`, `xvfb`
- `flutter config --enable-linux-desktop`

**Pasos críticos:**
1. `sudo apt-get update && sudo apt-get install -y --no-install-recommends ... libsecret-1-dev`
2. `flutter config --enable-linux-desktop`
3. `bash backend/scripts/e2e_flutter.sh up` (BD aislada + seed + stub LM + API en 127.0.0.1:8000)
4. `xvfb-run -a flutter test integration_test/pesaje_flow_test.dart -d linux` (con retry)

**Output esperado:**
- 1/1 test E2E verde (modo seed o instalada)
- Vuelca logs en fallo: `/tmp/balansoft-e2e-flutter/api.log` y `lm.log`
- Fallo aborta pipeline si no hay dependencias de sistema

## Gestión de Dependencias y Entorno

### Problemas Comunes de Entorno
1. **`uv` no en PATH:**
   - Solución: usar `backend/.venv/bin/python -m pytest -q` como fallback
   - El repositorio tiene `.venv/` gitignored con pytest/ruff/mypy

2. **`libsecret-1-dev` faltante en CI:**
   - El workflow e2e-flutter falla antes de compilar
   - Requerido: `sudo apt-get install -y --no-install-recommends libsecret-1-dev`

3. **Dependencies out of sync:**
   - `uv sync --all-groups` debe ejecutarse antes que `ruff` o `mypy`
   - Lockfile `uv.lock` se actualiza automáticamente

### Comandos de Operación Comunes

#### Reinicio Total de BD
```bash
# Desde raíz del repositorio
./scripts/reset_total.sh
# Respalda con pg_dump -Fc antes de borrar y aborta si falla
```

#### Verificación de Estación
```bash
./scripts/verify.sh
```

#### Setup de Base de Datos Local
```bash
./scripts/setup_db.sh instalar
# Aplica esquema local sobre balansoft_ws_local
```

#### Generación de Keys para E2E
```bash
mkdir -p /tmp/lm-keys
uv run --directory backend python scripts/generate_signing_keys.py /tmp/lm-keys
# Set env vars antes de e2e:
# LICENSE_PRIVATE_KEY_PATH=/tmp/lm-keys/key_privada.pem
# LICENSE_PUBLIC_KEY_PATH=/tmp/lm-keys/key_publica.pem
```

## Observability Stack (H6)

### Estructura en `src/backend/deploy/observability/`
- `prometheus.yml`: job `balansoft-api` scrape
- `alerts/balansoft-alerts.yml`: 8 reglas de alerta
  - Caída de API, latencia p95 alta/crítica, 5xx, 4xx, errores de licencia, estación sin uso, pesajes detenidos
- `alertmanager.yml`: receptor `null` en dev (silencia síntomas cuando API caída)
- `docker-compose.observability.yml`: scrape, 8 alertas, receptor vacío
- `README.md`: documentación vigente `docs/OBSERVABILIDAD.md`

### Métricas Monitoreadas
- `balansoft_http_requests_total` (contador por método, ruta, status)
- `balansoft_api_latency_seconds` (histograma con buckets 0.01-5.0s)
- `balansoft_pesajes_total` (por estatus y tier)
- `balansoft_license_errors_total` (por tier y reason)
- `balansoft_active_users` (sesiones activas estimadas)

**Nota crítica:** Ninguna métrica lleva `id_empresa` (multi-tenancy: `/metrics` no puede filtrar por tenant).

### Alertas Clave (8 reglas)
1. **Caída de API** — API inaccesible
2. **Latencia p95 alta** — umbral configurado
3. **Errores 5xx** — tasa de errores de servidor
4. **Errores 4xx** — tasa de errores de cliente
5. **Errores de licencia** — LM inalcanzable o inválida
6. **Estación sin uso** — pesajes detenidos demasiado tiempo
7. **Latencia p95 crítica** — umbral superior
8. **Sin uso de métrica** — alerta que nunca dispara (peor que no tenerla)

## Integración con Otros Agentes
- **`bls-ws-architecture.md`**: Decisiones sobre qué métricas exponer (cardinalidad, id_empresa)
- **`bls-ws-planner.md`**: Priorizar habilitación de canales de notificación, retención, TLS
- **`bls-ws-monitor-agent`** (por crear): Parsear alertas y decidir acciones
- **`bls-ws-iso-documentador.md`**: Asegurar que la documentación de métricas cumpla ISO/IEC 25010 (sobre calidad y testabilidad)

## Limitaciones
- No puede instalar system packages en runners de GitHub (needs sudo/apt-get en runner propio)
- No puede controlar el entorno de ejecución del WServer (reinicios, configuración de puertos)
- No puede modificar el flujo de `generate_signing_keys.py` (keys nunca commiteadas por diseño)

## Integración con Scripts del Repositorio
El agente coordina con estos scripts críticos:
- `scripts/e2e_flutter.sh` (up/down/status)
- `scripts/reset_db.sh` (vacía ambas BD)
- `scripts/reset_total.sh` (raíz, respalda con pg_dump)
- `scripts/verify.sh` (verificación de estación)
- `scripts/build_wserver.sh` (compila WServer one-file)
- `scripts/mcp_hardware_server.py` (servidor MCP stdio JSON-RPC)

---

## Protocolo de Versionado SemVer y Release Bumping

Bajo la instrucción de `bls-ws-lead-architect`, este agente ejecuta el bumping sincronizado de versión:

### 1. Cuándo se incrementa:
- **Build Number (`-dev.B`)**: En cada iteración o release previo a producción (`git rev-list --count HEAD`).
- **PATCH (`0.4.X`)**: Correcciones de bugs, hotfixes y mejoras sin cambios en contratos de API ni tablas.
- **MINOR (`0.X.0`)**: Nuevos módulos funcionales, catálogos o protocolos de básculas/impresoras.
- **MAJOR (`1.0.0`)**: Primer lanzamiento formal y productivo para clientes finales.

### 2. Archivos sincronizados en bloque:
1. `opencode.json` (`version: "0.4.2-dev.56"`)
2. `src/frontend/pubspec.yaml` (`version: 0.4.2-dev.56`)
3. `src/frontend/lib/core/config/app_config.dart` (`appVersion = '0.4.2-dev.56'`, `appBuild = 56`)
4. `src/backend/pyproject.toml` (`version = "0.4.2.dev56"`)
5. `CHANGELOG.md` (creación del encabezado `## [vX.Y.Z-dev.B] — YYYY-MM-DD`)
6. Documentos editoriales: `docs/PRD.md`, `docs/AGENTS_SKILLS_ISO_AUDIT.md` y `EULA.md`.

### 3. Etiquetado Git:
Tras verificar que los tests pasen en verde, genera el tag de release:
```bash
git tag -a v0.4.2-dev.56 -m "Release v0.4.2-dev.56"
```
# ==============================================================================
# BALANSOFT-WS — Makefile de Automatización y Operación
# Sistema estación pesaje industrial multi-empresa: FastAPI + Flutter + WServer
# ==============================================================================

.DEFAULT_GOAL := help
SHELL := /bin/bash

# Rutas del proyecto
BACKEND_DIR := src/backend
FRONTEND_DIR := src/frontend

# ==============================================================================
# AYUDA
# ==============================================================================
.PHONY: help
help: ## Muestra este menú de ayuda
	@echo "======================================================================"
	@echo "                  BALANSOFT-WS — AUTOMATIZACIÓN                       "
	@echo "======================================================================"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ==============================================================================
# CALIDAD DE CÓDIGO Y LINTING
# ==============================================================================
.PHONY: lint lint-backend lint-frontend
lint-backend: ## Ejecuta linter ruff y type checker mypy en backend
	@echo "==> [Backend] Verificando ruff..."
	cd $(BACKEND_DIR) && uv run ruff check app tests
	@echo "==> [Backend] Verificando mypy..."
	cd $(BACKEND_DIR) && uv run mypy tests/

lint-frontend: ## Ejecuta flutter analyze en frontend
	@echo "==> [Frontend] Verificando flutter analyze..."
	cd $(FRONTEND_DIR) && flutter analyze

lint: lint-backend lint-frontend ## Ejecuta todo el análisis estático (backend + frontend)

.PHONY: format
format: ## Aplica formateo automático en backend (ruff) y frontend (dart format)
	@echo "==> [Backend] Formateando con ruff..."
	cd $(BACKEND_DIR) && uv run ruff format app tests
	@echo "==> [Frontend] Formateando con dart format..."
	cd $(FRONTEND_DIR) && dart format lib/ test/

# ==============================================================================
# PRUEBAS (TESTING)
# ==============================================================================
.PHONY: test test-backend test-frontend test-e2e test-mssql
test-backend: ## Ejecuta los 935 tests rápidos unitarios del backend
	@echo "==> [Backend] Ejecutando tests unitarios rápidos..."
	cd $(BACKEND_DIR) && uv run pytest -q -m "not e2e"

test-frontend: ## Ejecuta los 405 tests unit/widget de Flutter
	@echo "==> [Frontend] Ejecutando tests Flutter..."
	cd $(FRONTEND_DIR) && flutter test

test: test-backend test-frontend ## Ejecuta todas las pruebas unitarias (backend + frontend)

test-e2e: ## Ejecuta los 34 tests E2E contra el stub firmante del LM
	@echo "==> [Backend] Ejecutando tests E2E de licencias y sync..."
	cd $(BACKEND_DIR) && uv run pytest tests/e2e -q

test-mssql: ## Ejecuta pruebas de integración SQL Server (requiere MSSQL_TEST_URL_SYNC)
	@echo "==> [Backend] Ejecutando pruebas MSSQL..."
	cd $(BACKEND_DIR) && uv run pytest -m mssql

test-e2e-ui: ## Ejecuta el test E2E de interfaz de usuario Flutter en Linux
	@echo "==> [Frontend] Ejecutando E2E UI pesaje flow..."
	cd $(FRONTEND_DIR) && flutter test integration_test/pesaje_flow_test.dart -d linux

# ==============================================================================
# DESARROLLO Y EJECUCIÓN LOCAL
# ==============================================================================
.PHONY: dev-backend dev-frontend run-mcp
dev-backend: ## Levanta la API local FastAPI en modo desarrollo (:8000 con reload)
	@echo "==> Iniciando backend dev en http://127.0.0.1:8000..."
	cd $(BACKEND_DIR) && uv run uvicorn app.main:app --port 8000 --reload

dev-frontend: ## Lanza el cliente Flutter de escritorio en Linux
	@echo "==> Iniciando cliente Flutter desktop..."
	cd $(FRONTEND_DIR) && flutter run -d linux

run-mcp: ## Ejecuta el servidor MCP de hardware sobre stdio (JSON-RPC)
	@echo "==> Iniciando servidor MCP de hardware..."
	cd $(BACKEND_DIR) && uv run python scripts/mcp_hardware_server.py

# ==============================================================================
# GESTIÓN DE BASE DE DATOS Y ESTACIÓN
# ==============================================================================
.PHONY: db-verify db-reset db-install
db-verify: ## Ejecuta el script de verificación de la estación
	cd $(BACKEND_DIR) && ./scripts/verify.sh

db-reset: ## Vacía ambas bases de datos con el esquema canónico
	cd $(BACKEND_DIR) && ./scripts/reset_db.sh

db-install: ## Aplica el esquema canónico local
	cd $(BACKEND_DIR) && ./scripts/setup_db.sh instalar

# ==============================================================================
# COMPILACIÓN Y EMPAQUETADO (BUILD)
# ==============================================================================
.PHONY: build-wserver
build-wserver: ## Compila el binario ejecutable WServer one-file con PyInstaller
	@echo "==> Compilando WServer runtime..."
	cd $(BACKEND_DIR) && ./scripts/build_wserver.sh

# ==============================================================================
# GOBERNANZA DE RELEASE Y VERSIONADO
# ==============================================================================
.PHONY: version-info release-tag
version-info: ## Muestra la versión actual del proyecto y número de build
	@echo "Versión oficial: $$(grep '\"version\"' opencode.json | awk -F '\"' '{print $$4}')"
	@echo "Total commits (build): $$(git rev-list --count HEAD)"
	@echo "Último tag Git: $$(git describe --tags --always 2>/dev/null || echo 'Sin tags')"

release-tag: ## Crea el Git Tag anotado con la versión actual de opencode.json
	@VERSION=$$(grep '"version"' opencode.json | awk -F '"' '{print $$4}'); \
	echo "==> Creando Git Tag anotado para v$$VERSION..."; \
	git tag -a "v$$VERSION" -m "Release v$$VERSION" && \
	echo "Tag v$$VERSION creado exitosamente. Usa 'git push origin v$$VERSION' para publicarlo."

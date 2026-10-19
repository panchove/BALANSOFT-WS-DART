# WORKFLOW DE DESARROLLO CON OPENCODE EN BALANSOFT-WS

Guía para maximizar la productividad y precisión al programar en BALANSOFT-WS utilizando OpenCode o herramientas de programación agéntica.

---

## 1. Comandos de Verificación Rápida

| Objetivo | Comando |
|---|---|
| **Backend Tests Unitarios** | `cd backend && .venv/bin/python -m pytest -q -m "not e2e"` |
| **Backend Tests E2E Licencia** | `cd backend && .venv/bin/python -m pytest tests/e2e` |
| **Backend Linter (Ruff)** | `cd backend && .venv/bin/ruff check app tests` |
| **Backend Type Checker (Mypy)** | `cd backend && .venv/bin/mypy tests/` |
| **Frontend Análisis (Flutter)** | `cd frontend && flutter analyze` |
| **Frontend Tests Unit/Widget** | `cd frontend && flutter test` |
| **Frontend E2E Flujo Pesaje** | `cd frontend && flutter test integration_test/pesaje_flow_test.dart -d linux` |

---

## 2. Reglas de Oro para Asistentes y Agentes

1. **No inventar protocolos de básculas:**
   - Usar siempre la matriz de `scale-specialist`.
   - Probar tramas nuevas contra `app.core.scale_parser.parse_weight_frame` usando el script de prueba o el servidor MCP.
2. **Respetar la paridad del boleto:**
   - La tabla LECTURA DE PESOS de 5 columnas no se modifica en Python sin modificar primero `ticket_preview_dialog.dart` en Flutter.
3. **Inmutabilidad del peso:**
   - Ningún endpoint ni pantalla puede permitir sobreescribir el peso capturado de la báscula física.
4. **Verificar antes de commitear:**
   - `ruff check app tests` en backend y `flutter analyze` en frontend deben mantenerse limpios de advertencias o errores.

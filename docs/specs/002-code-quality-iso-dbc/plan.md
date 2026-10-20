# Plan de Acción: Homologación de Código ISO 25010, Clean/Clear Code y DbC

**Versión:** 0.4.2-dev.56  
**Fecha:** 2026-10-19  
**Estado:** Propuesta Aprobada  
**Norma:** ISO/IEC 25010 / ISO/IEC 42001 / ISO/IEC 27001 / ISO/IEC 17025  
**Fuente:** Sistema BALANSOFT-WS  
**Autor:** Lead Architect  

---

## 1. Diagnóstico Inicial y Metas de Calidad

| Dimensión                          |         Estado Actual          |        Meta del Plan         | Indicador de Éxito                                                     |
|------------------------------------|:------------------------------:|:----------------------------:|------------------------------------------------------------------------|
| **Documentación Backend (Python)** |  35.8% clases / 54.3% métodos  |   **> 90%** en capas clave   | Docstrings Sphinx/Google en todos los servicios y routers.             |
| **Documentación Frontend (Dart)**  |  23.5% clases / 11.6% métodos  |   **> 85%** en capas clave   | Doc comments `///` en Repositories, BLoCs y Data Sources.              |
| **Design by Contract (DbC)**       |    Precondiciones Pydantic     | **Pre + Post + Invariantes** | Asertos explícitos de invariantes metrológicos en servicios de pesaje. |
| **Modularidad / Clean Code**       | `ticket_service.py` monolítico | **Arquitectura Desacoplada** | Desglose en submódulos especializados de renderizado.                  |

---

## 2. Fases de Ejecución

### Fase 1: Cobertura Documental ISO 25010 en Backend (Python)
- **Alcance**: `src/backend/app/services/`, `src/backend/app/api/v1/endpoints/` y `src/backend/app/models.py`.
- **Estándar Docstring**:
  ```python
  def registrar_pesaje(self, datos: PesajeCreate, usuario_id: int) -> BoletoPesaje:
      """Registra una pesada inicial o final en la estación.

      Precondiciones:
          - La báscula debe reportar estabilidad metrológica.
          - El usuario debe pertenecer al tenant activo (id_empresa).

      Poscondiciones:
          - El boleto queda persistido en estado EN_CURSO o CERRADO.
          - Se emite asiento de auditoría inmutable.

      Raises:
          BalanzaInestableError: Si el hardware reporta fluctuación de peso.
          TenantMismatchError: Si hay discrepancia de id_empresa.
      """
  ```

### Fase 2: Documentación de Interfaces y Contratos en Frontend (Dart)
- **Alcance**: `src/frontend/lib/domain/`, `src/frontend/lib/data/repositories/` y `src/frontend/lib/presentation/blocs/`.
- **Estándar Doc Comments (`///`)**:
  - Documentar cada clase de repositorio con su contrato de negocio.
  - Documentar eventos y estados de los BLoCs principales (`WeighingBloc`, `KardexBloc`, `SyncBloc`).

### Fase 3: Refuerzo de Invariantes DbC (Design by Contract)
1. **Invariante Metrológica (OIML R 76-1 / ISO 17025)**:
   - Añadir validación pos-cálculo en `src/backend/app/services/ticket_service.py` y `pesajes.py`:
     `Neto == (Bruto - Tara)` con precisión decimal `ROUND_HALF_UP`, fallando de forma segura si hay inconsistencia aritmética.
2. **Invariante Multi-Tenant (ISO 27001)**:
   - Validar que cada query ejecutada en `src/backend/app/api/` contenga explícitamente `id_empresa`.

### Fase 4: Desglose de "God Objects" (Clean / Clear Code)
- Reorganizar `src/backend/app/services/ticket_service.py` (3.025 líneas) en un paquete modular:
  - `app/services/ticket/generator_pdf.py` (Carta / A4)
  - `app/services/ticket/generator_thermal.py` (80mm / 58mm)
  - `app/services/ticket/table_builder.py` (Tabla canónica de 5 columnas)
  - `app/services/ticket/service.py` (Fachada pública sin romper contratos existentes)

---

## 3. Plan de Verificación y No-Regresión
1. Ejecutar linters tras cada lote: `make lint` (`ruff check`, `mypy`).
2. Ejecutar la suite completa de pruebas de backend: `make test-backend` (935 unitarios + 34 E2E).
3. Verificar que no se altere la API pública de FastAPI ni los esquemas Pydantic v2.

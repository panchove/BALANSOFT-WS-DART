# ISO/IEC 25010 / 27001 / 42001 Document Template — Balansoft-WS

**Versión:** 0.4.2-dev.56
**Fecha:** 2026-10-19
**Estado:** Vigente
**Norma:** ISO/IEC 25010 / ISO/IEC 27001 / ISO/IEC 42001
**Fuente:** Sistema BALANSOFT-WS

**Esta plantilla define la estructura normalizada que deben seguir todos los documentos `.md` del repositorio `docs/` para garantizar trazabilidad normativa ISO.**

> **Contexto:** El repositorio utiliza identificadores trazables `REQ-FN-NNN` (funcionales), `REQ-NF-<área>-NNN` (no funcionales), `AR-NNN` (arquitectura), `INT-NNN` (interfaces), `UX-NNN` (experiencia de usuario). La presente plantilla asegura que cada documento pueda ser auditado y rastreado desde su identificador hasta su contenido versiónado.

---

## 1. Cabecera editorial (obligatoria)

Todo documento debe iniciar con los siguientes campos, en el orden y formato indicados. Los campos están en **negrita** para resaltarlos en el renderizado.

| Campo       | Descripción                                                                                                 | Ejemplo                                                                     |
|-------------|-------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| **Versión** | Número de versión semántica o de acuerdo a la política de release del proyecto.                             | `0.4.2-dev.56`, `1.0`, `2.7`                                                |
| **Fecha**   | Fecha de la versión en formato `YYYY-MM-DD`.                                                                | `2026-10-19`                                                                |
| **Estado**  | Estado de estabilidad del documento. Valores recomendados: `Vigente`, `Borrador`, `Obsoleto`, `Sustituido`. | `Vigente`, `Borrador`                                                       |
| **Norma**   | Normas ISO/IEC aplicables al contenido del documento. Múltiples normas separadas por barra inclinada.       | `ISO/IEC 25010`, `ISO/IEC 17025 / OIML R 76-1`, `ISO/IEC 27001`, `ISO/IEC 42001`, `ISO 8601` |
| **Fuente**  | Origen o autoridad del documento. Normalmente `Sistema BALANSOFT-WS` o nombre del equipo/rol.               | `Sistema BALANSOFT-WS`, `Equipo de Pesaje`, `Arquitectura`                  |
| **Autor**   | Persona o rol responsable de la versión actual. Opcional en documentos heredados.                           | `Arquitecto`, `Equipo de Base de Datos`, `Desarrollo Frontend`              |

> **Formato recomendado:**
> ```
> **Versión:** 0.4.2-dev.56
> **Fecha:** 2026-10-19
> **Estado:** Vigente
> **Norma:** <valor>
> **Fuente:** <valor>
> ```

---

## 2. Identificación de requisitos (opcional pero recomendado)

Si el documento está asociado a requisitos del proyecto, debe incluir una sección de identificación de requisitos alineados con la convención del repositorio.

> **Identificadores compatibles:**
> - `REQ-FN-NNN` — Requisitos funcionales
> - `REQ-NF-<área>-NNN` — Requisitos no funcionales (área: ONB, ARQ, BAL, etc.)
> - `AR-NNN` — Decisiones de arquitectura
> - `INT-NNN` — Interfaces de usuario / componentes
> - `UX-NNN` — Aspectos de experiencia de usuario

> **Ejemplo de sección:**
> ```
> ### Requisitos asociados
>
> - **REQ-FN-010**: Cuando se genere el PDF de un boleto, el sistema debe aplicar el formato de tabla de 5 columnas...
> - **REQ-NF-ONB-001**: El paso 1 de la instalación pide idioma y tema antes de necesitar la API.
> - **AR-012**: El motor de BD se decide solo por el prefijo de DATABASE_URL.
> ```

---

## 3. Propósito y alcance

Descripción libre del documento en formato Markdown. Debe responder:

- ¿Qué problema o área del sistema documenta?
- ¿Quiénes son los lectores objetivo?
- ¿Qué se espera lograr con este documento?

> **Ejemplo:**
> ```
> ## Propósito
>
> Este documento describe la arquitectura de bases de datos dual (server/local) de BALANSOFT-WS, definiendo la separación entre `balansoft_ws` (servidor central) y `balansoft_ws_local` (máquina del cliente), sus responsabilidades respectivas y la regla fundamental: una máquina local = una empresa = una cuenta.
> ```

---

## 4. Estructura del contenido

El cuerpo del documento debe seguir una estructura lógica y consistente. Se recomienda el uso de encabezados Markdown en el siguiente orden:

1. **Introducción / Contexto** — descripción del ámbito.
2. **Definiciones y siglas** — si el documento usa términos técnicos específicos.
3. **Arquitectura o modelo** — diagramas, tablas, flujos.
4. **Configuración o ajustes** — parámetros, valores por defecto, rangos válidos.
5. **Operaciones** — pasos, flujos de trabajo, estados posibles.
6. **Limitaciones y consideraciones** — restricciones conocidas, excepciones.
7. **Referencias** — documentos relacionados, normas, códigos fuente.

> **Notas de estilo:**
> - Usar tablas para datos tabulares (neveras de pesos, matrices de compatibilidad).
> - Usar listas enumeradas o con viñetas para pasos y opciones.
> - Incluir identificadores de requisito `REQ-FN-NNN` o `REQ-NF-...` en el texto cuando se cite un requisito.
> - Mantener coherencia en la unidad de medida (mm, pt, kg, ms, etc.) según el contexto.

---

## 5. Control de revisión (opcional)

Para documentos que experimentan cambios frecuentes, incluir un historial de revisiones al final del documento:

| Versión | Fecha        | Cambios                         | Autor      | Norma afectada  |
|---------|--------------|---------------------------------|------------|-----------------|
| `1.0`   | `2023-01-15` | versión inicial                 | `Equipo`   | `ISO/IEC 25010` |
| `1.1`   | `2023-03-22` | agregada sección de operaciones | `Personal` | `ISO/IEC 27001` |

> **Nota:** Si el documento ya tiene historial de cambios en su propio cuerpo (como `CHANGELOG.md` a nivel de proyecto), no es necesario duplicarlo aquí. Este campo es opcional para documentos estables.

---

## 6. Referencias cruzadas

Relación con otros documentos del repositorio, usando rutas relativas `docs/`.

> **Ejemplo:**
> ```
> ### Referencias
>
> - `[MANEJO_DB.md](/docs/MANEJO_DB.md)` — Arquitectura de bases de datos dual, §11.5.
> - `[MODELO_ESTANDAR.md](/docs/MODELO_ESTANDAR.md)` — Roles de usuario y reglas de negocio.
> - `[AGENTS.md](/AGENTS.md)` — Guía para agentes OpenCode.
> ```

> **Recomendación:** Usar siempre rutas relativas Starting with `docs/` para documentos dentro de la carpeta `docs/`, y `/AGENTS.md` / `/CHANGELOG.md` para los archivos raíz. Evitar rutas absolutas o referencias a ubicaciones que no existen aún.

---

## 7. Clave de versiónado

Para rastrear cambios entre versiones sucesivas:

- **Incremento de `MAYOR`**: cambios incompatibles o restructuración significativa.
- **Incremento de `MINOR`**: nuevas funcionalidades, secciones añadidas, sin romper compatibilidad.
- **Incremento de `PATCH`**: correcciones de errores tipográficos, actualización de fechas, sin cambio semántico.

> **Política del proyecto:** la versión debe aparecer en la cabecera editorial y, cuando el documento forme parte de un release público (ej. PRD v1.4.2), debe coincidir con la versión global del sistema.

---

## 8. Clasificación y metadatos (opcional)

> **Clasificación:** `Público` (recomendado), `Interno`, `Confidencial`.
>
> **Entorno:** `Desarrollo`, `Producción`, `Pruebas`, `Kiosco`.
>
> **Soporte:** `Equipe de Base de Datos`, `Equipe de Frontend`, `Equipe de Integración`.

> Estos campos son opcionales y se incluyen solo cuando el documento requiere control de acceso o información operativa adicional.

---

### Referencias normativas (informativo)

Los documentos que citen normas ISO deben incluirlas en esta sección al final:

- `ISO/IEC 25010` — Calidad de producto de software (SQuaRE).
- `ISO/IEC 17025` — Requisitos generales para la competencia de laboratorios de pruebas y calibración.
- `OIML R 76-1` — Metrología legal — Requisitos generales y modelo metrológico para la verificación legal de básculas y básculas para pesaje no automático.
- `ISO/IEC 27001` — Tecnologías de la información — Técnicas de seguridad — Sistemas de gestión de seguridad de la información.
- `ISO 8601` — Representaciones de fecha y hora.
- `ISO/IEC 10646` — Conjunto de caracteres — Universal Coded Character Set (UCS).
- `ISO/IEC 8859-1` — Conjuntos de caracteres — Parte 1: alfabetos latinos.

> **Política del proyecto:** al citar una norma ISO, verificar que su contenido sea coherente con la descripción y el alcance del documento. Citas a normas que no se aplican al tema del documento serán señaladas en auditoría.

---

## Aplicación a los documentos existentes

Los documentos `.md` en `docs/` deben reestructurarse para incluir, como mínimo, la **Sección 1 (Cabecera editorial)**. Los documentos que ya tienen esta cabecera (verificados en la sesión actual) son:

- `constitution.md`
- `INPUTS_MAP.md`
- `MODELO_ESTANDAR.md`
- `NAV.md`
- `OBSERVABILIDAD.md`
- `PLANES-PAGOS.md`
- `SEMAFORO.md`
- `SESIONES.md`
- `USO-API.md`

Los documentos que aún no tienen la cabecera completa y deben actualizarse son:

- `TODO.md` — tiene `Fecha` y `Estado` en el cuerpo, pero no la cabecera formal.
- `BALANZAS_SOPORTADAS.md` — tiene una tabla de metadatos al final, pero no la cabecera editorial al inicio.
- `I18N_Y_ONBOARDING.md` — tiene `Versión` y `Fecha` en **negrita** al inicio, cumple el requisito.
- `MANEJO_DB.md` — tiene `Versión`, `Fecha`, `Estado` y `Norma`/`Fuente` en la cabecera.
- `NAV.md` — tiene `Versión` y `Fecha` en la cabecera (añadida en esta sesión).
- `PRD.md` — tiene `Versión`, `Fecha`, `Estado` y `Norma`/`Fuente` en la cabecera.
- `SEMAFORO.md` — tiene `Versión` y `Fecha` en la cabecera (añadida en esta sesión).
- `SESIONES.md` — tiene `Versión` y `Fecha` en la cabecera (añadida en esta sesión).
- `USO-API.md` — tiene `Versión` y `Fecha` en la cabecera (añadida en esta sesión).

> **Acción recomendada:** Ejecutar el script de normalización o actualizar manualmente los documentos que faltan la cabecera editorial (Versión, Fecha, Estado, Norma, Fuente) al inicio del archivo, tras el título principal. Esto garantiza la trazabilidad ISO completa para todos los documentos del repositorio.
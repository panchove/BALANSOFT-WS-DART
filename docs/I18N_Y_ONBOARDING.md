# BALANSOFT-WS: Internacionalización (es/en/pt) y Onboarding de Primera Instalación

**Versión:** 1.2
**Fecha:** 2026-09-25
**Estado:** Vigente
**Autor:** Equipo BALANSOFT
**Norma:** REQ-FN-NNN (funcional), REQ-NF-<área>-NNN (no funcional), UX-NNN (interacción)
**Fuente:** `backend/app/core/i18n.py`, `frontend/lib/core/i18n/`, `backend/app/api/v1/endpoints/empresa.py`, `backend/app/api/v1/endpoints/servidor.py`, `docs/MANEJO_DB.md` §9.6 y §13

---

## 1. Alcance

Todo el sistema debe funcionar íntegramente en **español, inglés y portugués (es/en/pt)**: interfaz, títulos, formularios, mensajes, validaciones, alertas, botones, estados vacíos, **vista previa e impresión de boletos**, exportaciones (Excel/PDF) y textos de reportes. Además, la **primera instalación** debe capturar las preferencias del usuario antes de operar.

| Superficie | Idioma | Regla |
|-----------|:------:|-------|
| Interfaz Flutter (pantallas, títulos, formularios, `SnackBar`, diálogos) | es/en/pt | Sin literales sueltos: todo pasa por `AppTranslations.tr` |
| Boletos impresos y vista previa (PDF/TXT) | es/en/pt | La vista previa **debe** mostrar el mismo idioma que el archivo generado |
| Exportaciones Excel/PDF y sus encabezados | es/en/pt | Incluidos rótulos, pie de página y "RIF/Tel/Dirección" |
| API JSON de reportes | es/en/pt | Las **claves** no cambian; las etiquetas se traducen con el mismo `t()` |
| Backend (mensajes de error de API) | es/en/pt | Los `detail` se resuelven con el idioma resuelto de la petición |
| WServer (consola de arranque) | es/en/pt | Mensajes de consola en los 3 idiomas según `IDIOMA` del `.env` |

> **Regla dura:** si un texto visible al usuario final no existe en las tres
> tablas de traducción, la funcionalidad se considera incompleta. El paridad
> de claves se verifica en tests (`tests/test_i18n.py` y test espejo en Flutter).

---

## 2. Identificadores de requisito

### 2.1 Internacionalización

| ID | Requisito | Criterio de aceptación |
|----|-----------|------------------------|
| **REQ-NF-I18N-001** | La interfaz completa, sus títulos, formularios, mensajes, alertas y estados vacíos deben existir en es/en/pt | Todas las pantallas llamar `tr()`; 0 literales de UI sin traducir en los flujos cubiertos |
| **REQ-NF-I18N-002** | El idioma se persiste por empresa en la BD local (`empresas.idioma`) y se entrega en la respuesta de login | Tras reiniciar la app y volver a entrar, tickets y reportes salen en el idioma elegido |
| **REQ-NF-I18N-003** | Precedencia de idioma: `?idioma=`/`?lang=` > `Accept-Language` (con q-values) > `empresas.idioma` > `es` | `Accept-Language: pt-BR,pt;q=0.9,en;q=0.8` devuelve `pt`; `es-ES,es;q=0.9,en;q=0.8` devuelve `es` |
| **REQ-NF-I18N-004** | Números y fechas se formatean según el idioma | `1.234,56` en es/pt y `1,234.56` en en, tanto en pantalla como en PDF/Excel |
| **REQ-NF-I18N-005** | La vista previa del boleto y el archivo generado usan el mismo idioma y el mismo diseño | Previsualizar en EN y descargar produce el mismo texto en EN |
| **REQ-NF-I18N-006** | Las etiquetas de los reportes exportados están traducidas (incluye pie: "Página", "Impreso", "Sistema") | Kardex y pesajes en los 3 idiomas sin literales fijas |

### 2.2 Onboarding / primera instalación

| ID | Requisito | Criterio de aceptación |
|----|-----------|------------------------|
| **REQ-NF-ONB-001** | El paso 1 de la instalación pide **idioma y tema** antes de necesitar la API | Al abrir la app por primera vez se muestra la selección de idioma/tema ya traducida |
| **REQ-NF-ONB-002** | La instalación solo se completa si la API local responde (`/api/v1/health`) | Una URL inválida o un WServer caído **no** advances al login; se muestra el error traducido |
| **REQ-NF-ONB-003** | Tras el primer login del `ADMIN` se muestra la configuración inicial: datos de empresa, logo, formato de ticket, carpeta de reportes y formato de reportes | El wizard guarda todo y deja la empresa operativa |
| **REQ-NF-ONB-010** | La instalación empieza eligiendo el **modo de la estación**: `SERVIDOR` (titular de la licencia) o `TRABAJADOR` (cliente delgado) | El modo queda persistido en `AppConfig.modoEstacion` y define el resto del flujo |
| **REQ-NF-ONB-011** | Solo la máquina **titular de la licencia** puede instalarse como Servidor: lo decide el servidor central al validar la cuenta | Un equipo no titular recibe `403` y la instrucción de instalarse como Trabajador |
| **REQ-NF-ONB-012** | El modo Servidor pide el **correo y la contraseña** entregados por el proveedor y los valida contra el servidor central, lo que **verifica la licencia** en esa máquina | Sin respuesta del central o sin licencia activa la instalación del modo Servidor no continúa |
| **REQ-NF-ONB-013** | Los datos de la empresa llegan **precargados** del servidor central; el operador solo completa lo que falta | Razón social y RIF se muestran de solo lectura; dirección, teléfono, correo, logo, formatos y carpeta son editables |
| **REQ-NF-ONB-014** | La sesión creada al validar la cuenta **se conserva**: tras guardar los datos de empresa se entra al sistema sin volver a escribir la contraseña | El `access_token` del central queda en `SecureStorageService` y la empresa se guarda con `PUT /api/v1/empresa` |
| **REQ-NF-ONB-015** | El modo Trabajador solo necesita la **dirección y el puerto** del Servidor de la cuenta, y verifica la API antes de pedir el login | No crea base de datos local ni levanta WServer; el login usa las credenciales de `usuarios` que creó el administrador del Servidor |
| **REQ-NF-ONB-004** | El onboarding es **idempotente**: se marca completado una sola vez | Reiniciar la app no vuelve a mostrar el wizard |
| **REQ-NF-ONB-005** | Los datos no técnicos (empresa, logo, formatos, carpeta) pueden omitirse, pero el idioma, el tema y la verificación de la API son obligatorios | "Omitir ahora" solo aparece en los pasos no técnicos |

### 2.3 Preferencias persistidas

| ID | Requisito | Criterio de aceptación |
|----|-----------|------------------------|
| **REQ-NF-CFG-001** | Preferencias por **empresa** en la BD local: `idioma`, `formato_ticket` (`PDF`/`TXT`), `formato_reporte` (`EXCEL`/`PDF`) | Editables por `ADMIN` en `PUT /api/v1/empresa`; llegan al cliente en el login |
| **REQ-NF-CFG-002** | La **carpeta de reportes** es preferencia de la **estación** (ruta local), con aviso si no existe o no es escribible | Si no es escribible se avisa y se cae a la carpeta por defecto del sistema |
| **REQ-NF-CFG-003** | El **tema de la app** (claro/oscuro/sistema) es preferencia del dispositivo, no de la empresa | Cambiar de estación no cambia el tema; se elige en el paso 1 de instalación |
| **REQ-FN-CFG-004** | `formato_ticket` y `formato_reporte` **gobiernan de verdad** la exportación: la opción elegida es la que se ofrece por defecto | No se vuelve a hardcodear `PDF` en la lista de pesajes ni `EXCEL` en reportes |

---

## 3. Arquitectura

### 3.1 Backend

```
app/core/i18n.py        # TRANSLATIONS es/en/pt, t(), resolve_lang(), normalizar_idioma()
app/core/formato.py     # formatear_numero(), formatear_fecha() por idioma
app/models/__init__.py # Empresa.idioma, Empresa.formato_reporte
migrations/017_*        # + empresas.idioma, empresas.formato_reporte (idempotente)
```

- **Un solo diccionario canónico** para tickets, reportes y API.
- **`resolve_lang(request, param_lang, defecto)`** parsea `Accept-Language` con
  q-values reales (no por *substring*), por eso `pt-BR` ya no cae en `en`.
- **`IDIOMA` en `.env`** define el idioma por defecto del WServer (consola y
  `detail` de error sin empresa asociada).
- El idioma **no** se manda solo por cabecera: la app envía
  `Accept-Language: <idioma activo>` y el backend lo usa como último recurso
  antes del default.

### 3.2 Frontend

```
lib/core/i18n/locale_controller.dart   # idioma del dispositivo (SharedPreferences)
lib/core/i18n/translations.dart        # 3 tablas de traducción + tr() por clave o texto
lib/core/config/app_config.dart        # preferencias operativas (offline, sync, onboarding)
lib/core/config/station_config.dart    # config.json del instalador (api_base_url + rol)
lib/presentation/screens/settings/     # configuración persistente + wizard inicial post-login
lib/presentation/screens/auth/         # login/registro/recuperación (entrada única de la app)
```

- La app arranca **siempre en `/login`** (ver §4.3): `_rutaInicial()` ya no
  depende de banderas de instalación; el rol de la estación llega de
  `config.json` (`station_config.dart` → `AppConfig.rol`).
- `SaveFileUtils.esRutaEscribible()` valida la carpeta de reportes creando y
  borrando un archivo de prueba; si falla, se avisa y se usa la predeterminada.
- `tr()` acepta argumentos posicionales extra: `'ticket_cut_i'.tr(null, ['2'])`
  sustituye `{0}` en los tres idiomas.

- `AppTranslations.tr()` acepta **clave** (`'save'`) o **texto español**
  (`'Guardar'`), lo que permite migrar pantalla por pantalla sin romper.
- El idioma se **sincroniza** con la empresa: al login se aplica el del
  servidor; al cambiarlo en Ajustes se hace `PUT /api/v1/empresa` (best-effort,
  sin bloquear la UI si la API está caída).

### 3.3 WServer y migraciones

- `wserver.py` aplica **migraciones pendientes en cada arranque** (registro en
  `schema_migrations`), no solo cuando la BD está vacía; de lo contrario las
  estaciones ya instaladas nunca recibirían las columnas nuevas.
- Las migraciones son idempotentes y nunca borran datos: solo `ADD COLUMN IF
  NOT EXISTS`, `UPDATE ... WHERE ... IS NULL` y `CHECK` defensivos.

---

## 4. Modos de estación (decisión del instalador)

El **instalador** (`BALANSOFT-INSTALLER`, repo aparte) pregunta el rol
(`SERVIDOR` | `TRABAJADOR`) en un paso previo y escribe `config.json`
(`api_base_url` + `rol`). La app Flutter **no tiene asistente de instalación**:
arranca en `/login`, y el rol solo condiciona el comportamiento operativo
(REQ-NF-ONB-010). El detalle del modelo de cuenta y dispositivos está en
`MANEJO_DB.md §13`.

### 4.1 Modo Servidor Local (titular de la licencia)

| # | Paso | Pantalla | Persistencia |
|---|------|----------|--------------|
| 1 | Asegurar el WServer local y entrar | `auth/login_screen.dart` | `config.json` (`rol=SERVIDOR`, `api_base_url` local); `WServerManager.ensureRunning()` en el login |
| 2 | **Datos de empresa (post-login)** | `settings/initial_setup_screen.dart` | `onboarding_completado`, `PUT /api/v1/empresa`, logo, formatos, carpeta de reportes |
| 3 | Entrar al sistema | `dashboard` | — |

### 4.2 Modo Trabajador Local (cliente delgado)

| # | Paso | Pantalla | Persistencia |
|---|------|----------|--------------|
| 1 | Entrar contra la API del titular | `auth/login_screen.dart` | `config.json` (`rol=TRABAJADOR`, `api_base_url` del Servidor) |
| 2 | Login con credencial local | `auth/login_screen.dart` | Token del Servidor de la cuenta |

### 4.3 Reglas de navegación

- `_rutaInicial()` (`frontend/lib/main.dart`) devuelve **siempre `/login`**.
  Si `config.json` falta o es inválido, `main()` muestra `PantallaErrorConfig`
  (texto es/en hardcodeado, sin claves i18n) y la app no opera: no inventa rol
  ni URL.
- Los datos de empresa del primer `ADMIN` se capturan **tras el login** con la
  sesión abierta (a diferencia del flujo pre-login anterior). `CompanyDraft`
  sigue como respaldo: lo aplica `AuthRepository.login()` cuando el login
  devuelve la cuenta y aún no hay empresa configurada.
- El backend decide la autoridad en cada login: el primer dispositivo activo de
  la cuenta es `SERVIDOR_LOCAL` y el resto `LOCAL` (REQ-NF-ONB-011). La app ya
  no envía `modo_solicitado`; el endpoint central lo acepta como campo opcional
  y responde `403` si un no titular lo pide.
- Razón social y RIF llegan del central y se muestran de solo lectura en el
  formulario de empresa: son la identidad de la cuenta y se cambian desde el
  panel del proveedor.
- El Trabajador **no** es un cliente que "ve" la central: entra contra la API
  de la estación titular con las credenciales de `usuarios`, y por eso
  `LoginScreen` no llama `WServerManager.ensureRunning()` en ese modo.
- **Conexiones** (Ajustes / menú): ver y corregir la URL de la API; guarda en
  el override de usuario del `config.json` **conservando el rol** y solo acepta
  si `/api/v1/health` responde.

---

## 5. Mapa de la preferencia → dueño

| Preferencia | Dueño | Dónde se guarda | Quién la cambia |
|-------------|-------|-----------------|-----------------|
| Idioma | Estación + empresa (espejo) | `SharedPreferences` + `empresas.idioma` | Cualquiera (Ajustes) |
| Tema | Estación | `SharedPreferences` | Cualquiera (Ajustes) |
| Datos de empresa (nombre, RIF, dirección, telf, email) | Empresa | `empresas` | `ADMIN` |
| Logo | Empresa | `empresas.logo_url` (vía `POST /api/v1/files/upload`) | `ADMIN` |
| Formato de ticket (`PDF`/`TXT`) | Empresa | `empresas.formato_ticket` | `ADMIN` |
| Formato de reportes (`EXCEL`/`PDF`) | Empresa | `empresas.formato_reporte` | `ADMIN` |
| Carpeta de reportes | Estación (ruta local) | `SharedPreferences` + `empresas.ruta_exportacion_reportes` | `ADMIN` |
| Diseño de ticket (papel, orientación, por hoja) | Estación | `SharedPreferences` (`printer_preset`) | `ADMIN` |

---

## 6. Cobertura y plan de cierre

| Superficie | Estado | Nota |
|------------|:------:|------|
| Diccionarios backend (tickets, reportes, rótulos) | ✅ | 100 claves × 3 idiomas con paridad verificada por test |
| `Accept-Language` con q-values | ✅ | `app/core/i18n.py` ordena por `q=`; `pt-BR` cae en Portuguese |
| Números/fechas por idioma | ✅ | `app/core/formato.py`: es/pt `1.234,56`, en `1,234.56`; fechas `dd/mm/aaaa` |
| Preferencias de empresa (`idioma`, `formato_reporte`) | ✅ | `migrations/017` + `PUT /api/v1/empresa` + respuesta de login |
| Formato de reportes aplicado | ✅ | `GET /reports/export/pdf` y `GET /weighing/{boleto}/export` respetan la empresa |
| Onboarding por modo (servidor / trabajador) | ✅ | El rol lo escribe el instalador en `config.json`; la app arranca en `/login` y `StationRole` condiciona `WServerManager` y el cierre de ventana |
| Activación de cuenta y verificación de licencia | ✅ | Se valida en el propio login (`AuthRepository.login()` central-first o local); el backend responde 403 si un no titular pide rol de servidor |
| Empresa precargada desde el central | ✅ | El formulario post-login usa razón social/RIF del login; `CompanySetupForm.initialLock` mantiene solo lectura |
| Sesión conservada tras la activación | ✅ | Tokens en `SecureStorageService` + `CheckAuthStatusEvent`; la empresa se guarda con la sesión abierta y se entra al dashboard |
| Trabajador cliente delgado | ✅ | `config.json` trae la URL del titular; `LoginScreen` no levanta WServer en ese modo |
| Respaldo pre-login (sin sesión) | ✅ | `CompanyDraft` se conserva como respaldo y lo aplica `AuthRepository.login()` |
| Idioma de empresa aplicado en la estación | ✅ | Ajustes hace `PUT /api/v1/empresa`; también al cambiar idioma |
| Paridad de claves Flutter | ✅ | 541 claves × 3 idiomas (`test/unit/i18n_test.dart`) |
| Textos fijos en pantallas | ✅ | Lotes cerrados: pesajes, ajustes, dispositivos, ticket design/preview, kardex, catálogos, empresa/documentos, usuarios, seguridad, auditoría, ayuda, auth y setup |
| Verificación de integridad sin reinicio | ✅ | Diagnóstico propio `SystemDiagnosticsScreen` (Ajustes): 5 tarjetas de solo lectura (API, BD, licencia, sync, versión) con 4 llamadas GET en paralelo |
| Provisión de la estación (`config.json`) | ✅ | `test/unit/station_config_test.dart`: URL, rol, prioridad override/sistema, error duro sin degradación, migración única, modo 0600 |
| Pruebas del borrador de empresa | ✅ | `test/unit/company_draft_test.dart` (round-trip, logo base64, limpieza, normalización de idioma) |
| Vista previa del boleto vs. boleto impreso | ✅ | `ticket_preview_dialog.dart` usa las mismas claves del ticket |
| Panel web del proveedor (`BALASOFT-UI`) | ⏳ | Fuera de la app de estación: se traduce después |
| WServer aplica migraciones al reiniciar | ⏳ | Implementado; falta prueba de integración sobre BD instalada |

**Regla de cierre:** esta tabla se marca ✅ solo cuando el requisito tiene
código **y** test. Los identificadores `REQ-*` de la sección 2 son la fuente
de verdad del alcance.

**Pruebas de provisión y onboarding**: `test/unit/station_config_test.dart`
(carga de `config.json`, validación de URL, rol estricto, prioridad
override/sistema, error duro, migración única, permisos 0600) y
`test/unit/company_draft_test.dart` (round-trip, logo base64, limpieza,
normalización de idioma). El flujo de login y el wizard post-login se cubren
con el E2E de UI (`integration_test/pesaje_flow_test.dart`), que usa
`AppConfig.rol = StationRole.servidor` en modo seed.

---

## 7. Referencias

- `MANEJO_DB.md` §6.2 (esquema local), §9.6 (WServer / modo instalación),
  §13 (modelo de cuenta y dispositivos, flujo por modo)
- `MODELO_ESTANDAR.md` — roles; solo el `ADMIN` edita datos de empresa y formatos
- `NAV.md` — mapa de navegación (Ajustes → Configuración general)
- `backend/app/core/i18n.py`, `backend/app/core/formato.py`
- `frontend/lib/core/i18n/translations.dart`

---

*Documento vigente. Cualquier cambio en idiomas, onboarding o preferencias debe
actualizar esta tabla antes que el código.*

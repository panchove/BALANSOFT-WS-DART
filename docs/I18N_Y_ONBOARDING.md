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
lib/core/config/app_config.dart        # api_base_url + banderas de instalación por modo
lib/core/config/cuenta_activada.dart  # snapshot del central para precargar la empresa
lib/data/repositories/activacion_repository.dart  # login central + sesión + licencia
lib/presentation/screens/setup/        # preferencias → modo → entorno/activación/trabajador
lib/presentation/screens/settings/     # configuración persistente + wizard inicial
```

- El arranque depende del estado y **del modo** (ver §4.3): `_rutaInicial()` en
  `main.dart` usa `setup_preferencias_completado`, `modo_estacion`,
  `licencia_verificada`, `empresaSetupCapturado` y `localApiConfigured`.
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

## 4. Flujo de primera instalación

El paso 1 (idioma y tema) es común; del paso 2 en adelante el flujo **depende
del modo elegido** (REQ-NF-ONB-010). El detalle de reglas, endpoints y
preferencias está en `MANEJO_DB.md §13`.

### 4.1 Modo Servidor Local (titular de la licencia)

| # | Paso | Pantalla | Persistencia |
|---|------|----------|--------------|
| 1 | Idioma y tema | `setup/preferences_screen.dart` | `setup_preferencias_completado`, `balansoft.idioma`, `balansoft.tema` |
| 2 | **Elegir modo** | `setup/mode_selection_screen.dart` | `modo_estacion = SERVIDOR` |
| 3 | Verificar entorno | `setup/environment_check_screen.dart` | — (WServer, PostgreSQL, red) |
| 4 | Base de datos local | `setup/database_config_screen.dart` | `api_base_url` (solo si `/health` responde) |
| 5 | **Validar cuenta y licencia** | `setup/activation_screen.dart` | `licencia_verificada`, `es_titular_licencia`, `cuenta.activada`, tokens |
| 6 | **Datos de empresa (precargados)** | `setup/company_setup_screen.dart` | `empresa_setup_capturado`, `PUT /api/v1/empresa`, logo |
| 7 | Entrar al sistema | `dashboard` | `onboarding_completado` |

### 4.2 Modo Trabajador Local (cliente delgado)

| # | Paso | Pantalla | Persistencia |
|---|------|----------|--------------|
| 1 | Idioma y tema | `setup/preferences_screen.dart` | `setup_preferencias_completado` |
| 2 | **Elegir modo** | `setup/mode_selection_screen.dart` | `modo_estacion = TRABAJADOR` |
| 3 | **Conexión al Servidor** | `setup/worker_connection_screen.dart` | `api_base_url` (IP/URL + puerto, tras verificar `/health`) |
| 4 | Login con credencial local | `auth/login_screen.dart` | Token del Servidor de la cuenta |

### 4.3 Reglas de navegación

- El paso 4/5 no deja avanzar si la API guardada no responde
  `/api/v1/health`.
- La cuenta se valida **antes** de capturar la empresa (al revés del flujo
  pre-login anterior): por eso la empresa ya se guarda directo en la BD local
  con la sesión abierta y **no** hace falta `CompanyDraft` en este camino. El
  borrador se conserva como respaldo cuando no hay sesión.
- El central devuelve `license.puede_ser_servidor`: el primer dispositivo
  activo de la cuenta es `SERVIDOR_LOCAL` y el resto `LOCAL`. La app lo pide
  explícitamente con `modo_solicitado: SERVIDOR` y el backend responde `403`
  si la máquina no es titular (REQ-NF-ONB-011).
- Razón social y RIF llegan del central y se muestran de solo lectura
  (`CompanySetupForm.initialLock`): son la identidad de la cuenta y se
  cambian desde el panel del proveedor.
- Al validar la cuenta la sesión **queda abierta**: se guardan
  `access_token`/`refresh_token`, se dispara `CheckAuthStatusEvent` y tras
  guardar la empresa se entra directo al dashboard (REQ-NF-ONB-014).
- El Trabajador **no** es un cliente que "ve" la central: entra contra la API
  de la estación titular con las credenciales de `usuarios`, y por eso
  `LoginScreen` no llama `WServerManager.ensureRunning()` en ese modo.
- `_rutaInicial()` reanuda según el estado: sin preferencias →
  `/setup_preferences`; sin modo → `/mode_selection`; trabajador sin conexión →
  `/worker_connection`; servidor sin licencia verificada → `/setup`; servidor
  verificado sin empresa → `/company_setup`; en cualquier otro caso →
  `/login`.
- `AppConfig.instalacionCompletada` es **por modo**: el trabajador cierra con
  su conexión, el servidor con licencia + empresa.
- Los pasos de empresa se pueden **omitir** solo cuando no hay sesión (respaldo
  legacy); con la cuenta validada la empresa es obligatoria para entrar.
- La carpeta de reportes avisa si la ruta no es escribible y ofrece el valor
  por defecto.
- Todo el flujo se puede repetir desde **Ajustes → Configuración general** y
  desde **Documentos de empresa → Perfil de la empresa**.

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
| Onboarding por modo (servidor / trabajador) | ✅ | `mode_selection_screen.dart` persiste el modo; cada modo tiene su ruta de instalación (`main.dart` → `_rutaInicial()`) |
| Activación de cuenta y verificación de licencia | ✅ | `activation_screen.dart` + `ActivacionRepository` (central con `modo_solicitado`); el backend responde 403 si la máquina no es titular |
| Empresa precargada desde el central | ✅ | `CuentaActivada` guarda el snapshot; `CompanySetupForm.initialLock` deja razón social y RIF de solo lectura |
| Sesión conservada tras la activación | ✅ | Tokens en `SecureStorageService` + `CheckAuthStatusEvent`; la empresa se guarda con la sesión abierta y se entra al dashboard |
| Trabajador cliente delgado | ✅ | `worker_connection_screen.dart` verifica `/health`; `LoginScreen` no levanta WServer en ese modo |
| Respaldo pre-login (sin sesión) | ✅ | `CompanyDraft` se conserva como camino legacy y lo aplica `AuthRepository.login()` |
| Idioma de empresa aplicado en la estación | ✅ | Ajustes hace `PUT /api/v1/empresa`; también al cambiar idioma |
| Paridad de claves Flutter | ✅ | 489 claves × 3 idiomas (`test/unit/i18n_test.dart`) |
| Textos fijos en pantallas | ✅ | Lotes cerrados: pesajes, ajustes, dispositivos, ticket design/preview, kardex, catálogos, empresa/documentos, usuarios, seguridad, auditoría, ayuda, auth y setup |
| Verificación de integridad sin reinicio | ✅ | `EnvironmentCheckScreen(setupMode: false)` es de solo lectura (`WServerManager.isOnline()`), no arranca el WServer y libera el estado en `finally` |
| Pruebas del borrador de empresa | ✅ | `test/unit/company_draft_test.dart` (round-trip, logo base64, limpieza, normalización de idioma) |
| Vista previa del boleto vs. boleto impreso | ✅ | `ticket_preview_dialog.dart` usa las mismas claves del ticket |
| Panel web del proveedor (`BALASOFT-UI`) | ⏳ | Fuera de la app de estación: se traduce después |
| WServer aplica migraciones al reiniciar | ⏳ | Implementado; falta prueba de integración sobre BD instalada |

**Regla de cierre:** esta tabla se marca ✅ solo cuando el requisito tiene
código **y** test. Los identificadores `REQ-*` de la sección 2 son la fuente
de verdad del alcance.

**Pruebas del flujo de instalación** (`test/widget/setup_screens_test.dart`,
`test/widget/activation_screen_test.dart`): sin errores de layout en 1366×768 y
1024×600 (incluidas `/activation` y `/worker_connection`), validación de correo
y contraseña, mensaje 403 de licencia ya activa en otro equipo, navegación a
`/company_setup` con la cuenta validada, y persistencia de `modo_estacion`,
`licenciaVerificada` y `empresaSetupCapturado`.

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

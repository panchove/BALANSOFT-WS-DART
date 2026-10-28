# Plan de Implementación: Despliegue 100% Local (WServer) + Instalador con Licencia LM

Este es el plan de acción completo, estructurado por fases y responsabilidades, para transformar el sistema actual (que dependía de la nube para usuarios) en un sistema donde **el instalador y el WServer local gestionan las cuentas**, usando el LM únicamente como validador de licencia.

---

## FASE 0: Análisis y Base de Datos Local

**Objetivo:** Preparar la base de datos local para recibir la identidad del cliente del LM.

1.  **Migración de Base de Datos (Backend WS):**
    *   Añadir columnas a la tabla `empresa`:
        *   `lm_client_id` (String/UUID): El ID del cliente en el LM.
        *   `lm_client_email` (String): El email registrado en el LM.
        *   `lm_license_key` (String): La licencia activa (si no estaba ya).
    *   Asegurar que la tabla `usuarios` tenga el campo `password_hash` (si no lo tiene ya para el login local).

---

## FASE 1: El Instalador (Launcher / Script)

**Objetivo:** Bloquear la instalación si la licencia no es válida.

1.  **Interfaz del Instalador:**
    *   Una pantalla simple (puede ser Flutter o un script con diálogo) que pida: `Ingrese su License Key`.
2.  **Validación contra el LM:**
    *   El instalador llama al backend del LM: `POST /api/v1/token` y luego `GET /{license_key}/check`.
    *   **Condición de Éxito:** El LM debe responder `valid: true` y `has_client: true`.
    *   **Condición de Fallo:** Si no tiene cliente asignado, expiró o no existe, el instalador muestra un error y no permite continuar.
3.  **Guardado de Estado:**
    *   Si es válida, el instalador guarda la `license_key` en un archivo local (ej. `config.json` o variable de entorno) y procede a descomprimir/instalar los archivos de la app (WServer y Flutter).

---

## FASE 2: Backend Local (WServer / FastAPI)

**Objetivo:** Crear los endpoints para inicializar la cuenta sin depender de la nube y atender el login.

1.  **Endpoint `POST /api/v1/setup/validar-licencia`:**
    *   Recibe la `license_key` (del instalador).
    *   Consulta al LM en tiempo real.
    *   Devuelve a Flutter: `client_email`, `client_name`, `tier`, `expires_at`. (Estos datos pre-llenarán la pantalla de inicio).
2.  **Endpoint `POST /api/v1/setup/crear-admin` (El núcleo del cambio):**
    *   **Recibe:** `license_key`, `password`, `nombre_comercial`, `rif_nit`, `direccion`, `telefono`, `logo`.
    *   **Acción:**
        1.  Verifica que la base de datos local esté vacía (que no exista ya una empresa).
        2.  Valida la licencia por última vez contra el LM.
        3.  **Crea la Empresa:** Guarda los datos del formulario + `lm_client_id` y `lm_client_email` obtenidos del LM.
        4.  **Crea el Usuario:** Guarda el `email` (obtenido del LM) y el hash de la `password` (ingresada por el usuario), con rol `ADMIN`.
        5.  Genera un token JWT local para iniciar sesión automáticamente.
    *   **Retorna:** El JWT y los datos del usuario/empresa para que Flutter entre directo al Dashboard.
3.  **Modificar Middleware de Seguridad:**
    *   El login normal (`/api/v1/auth/login`) ahora valida contra la DB local, no contra la nube.
    *   Cada vez que se inicie sesión, se puede consultar al LM en segundo plano (`/validate`) para actualizar el estado de la licencia (vigencia) y bloquear el sistema si expiró.

---

## FASE 3: Frontend (Flutter) - Pantalla de Configuración Inicial

**Objetivo:** Adaptar la pantalla de la Imagen 2 para crear la cuenta en lugar de sincronizar.

1.  **Detección de "Primera Vez":**
    *   Al arrancar la app, si el endpoint local `GET /empresa` devuelve vacío o `null`, redirigir a la pantalla de **Configuración Inicial** (en lugar del Login).
2.  **Diseño de la Pantalla:**
    *   **Bloque 1 (Solo lectura):** Muestra los datos obtenidos del LM (Email, RIF, Nombre Fiscal). El usuario no puede cambiar el Email porque es el dueño de la licencia.
    *   **Bloque 2 (Editable):** Logo, Dirección, Teléfono, Nombre Comercial (el usuario los ajusta a su gusto).
    *   **Bloque 3 (NUEVO):** Contraseña y Confirmar Contraseña (validando que tengan mínimo 8 caracteres, mayúscula, etc.).
    *   **Botón:** "Crear Cuenta e Iniciar Sesión".
3.  **Flujo:**
    *   El usuario llena los datos y la contraseña.
    *   La app hace `POST /api/v1/setup/crear-admin`.
    *   Si es exitoso, guarda el JWT y navega al `HomeShell`.

---

## FASE 4: Limpieza de la Nube (Deprecación)

**Objetivo:** Eliminar todo rastro de creación de usuarios en la nube.

1.  **Eliminar Endpoints en la Nube:**
    *   Borrar los endpoints de WS Nube relacionados con la creación de usuarios, empresas o sincronización de contraseñas.
2.  **Eliminar Lógica en Flutter:**
    *   Quitar cualquier pantalla o lógica de "Registro de usuario en la nube".
    *   Quitar los métodos de `ApiClient` que apuntaban a la URL de la nube para temas de cuenta.
3.  **El LM se mantiene intacto:** Solo se usan sus endpoints `/token`, `/check`, `/activate` y `/validate`.

---

## FASE 5: Pruebas y Validación (QA)

1.  **Instalación Limpia:** Probar el instalador con una licencia sin cliente (debe fallar) y con una licencia válida (debe pasar).
2.  **Creación de Cuenta:** Verificar que la app muestra el email del LM bloqueado, permite poner contraseña y crea el usuario en la DB local.
3.  **Login Posterior:** Cerrar la app, abrirla de nuevo. Debe mostrar la pantalla de Login normal (porque la empresa ya existe), validar la contraseña local y entrar.
4.  **Licencia Expirada/Revocada:** Modificar la fecha de expiración en el LM (o desactivar la licencia) y forzar la validación. El WServer local debe bloquear las operaciones.

---

### ¿Por dónde empezamos a picar código?

Te sugiero empezar por el **Backend (FASE 2)**. Si el WServer local no tiene los endpoints `validar-licencia` y `crear-admin`, el frontend no podrá avanzar.
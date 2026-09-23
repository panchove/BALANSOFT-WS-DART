# Sistema de Licencias y Sesiones – BalansoFT SG "Software Ganadero"

## Tipos de Licencias

### Licencias Centrales (Básicas, Premium)
- **Multisesiones:** Permite múltiples sesiones simultáneas en diferentes dispositivos.
- **Uso de roles:** Cada sesión puede tener un rol específico o compartir los mismos permisos.
- **Uso compartido de información:** Todos los dispositivos conectados comparten la misma información en tiempo real.
- **Credenciales compartidas:** Una sola cuenta puede usarse en múltiples dispositivos hasta alcanzar el límite de sesiones permitido.

### Licencias Monopuestas (Básicas, Premium)
- **Sesión Única:** Permite solo una sesión activa a la vez.
- **Acceso Total:** El usuario único realiza el trabajo de todos los roles.
- **Vinculación por Hardware:** Solo puede abrirse en el dispositivo registrado (`hardware_id`).
- **Huella compuesta (RB-01):** el `hardware_id` es un SHA-256 versionado (`hw_v2_…`) sobre hardware de bajo nivel, inmune a actualizaciones del SO:
  - **Android:** ID de MediaDrm/Widevine (chip de seguridad) o ID persistente cifrado en Android Keystore como respaldo. Sobreviven a las OTAs (a diferencia del `ANDROID_ID`, que puede variar).
  - **Linux:** DMI/SMBIOS `/sys/class/dmi/id/product_uuid` (placa) + `board_serial` + `/etc/machine-id`.
  - **Windows:** WMI `Win32_ComputerSystemProduct.UUID` (placa) + `Win32_BIOS.SerialNumber` + serial del disco.
  - El hash **no** incluye `fingerprint`/`incremental`/`serialNumber` (cambian en cada OTA/patch) ni RAM/disco libres (varían entre ejecuciones).
  - **Migración:** `FingerprintService.legacy()` devuelve la huella v1 (SHA-256 puro de 64 hex) para no perder la ligadura de equipos ya registrados; el login envía `legacy_hardware_id` y el backend migra la MONOPUESTO al hash nuevo. Implementación: `client/lib/data/license/license_service.dart` + nativos Android/Linux/Windows. Columnas `hardware_id` `String(96)` (migración 0021).

---

## Verificación de Sesiones y Reglas de Negocio

El sistema valida el tipo de licencia (`CENTRAL` o `MONOPUESTA`), disponibilidad de cupos, distribuidor asociado y `hardware_id`.

### Reglas de Acceso por Dispositivo
1. **Regla General:** Si el dispositivo tiene una licencia vigente vinculada, solo puede abrir esa cuenta. Intentar abrir otra redirige automáticamente al login de la cuenta activa.
2. **Usuario Titular:** No puede abrir otra cuenta en su dispositivo hasta que su licencia venza o pase por un proceso de recuperación (notificar al proveedor para invalidarla y reactivar en un dispositivo virgen).
3. **Subcliente (CENTRAL):** Redirige a la cuenta CENTRAL asignada. Para usar otra cuenta, el subcliente debe cerrar la sesión actual en el dispositivo.
4. **Equipo nuevo en CENTRAL (login):** Al iniciar sesión desde un `hardware_id` que todavía no está inscrito en la licencia (`licencia_dispositivo`), el login registra el equipo en el proveedor (`POST /activate`, respeta `max_activations`) **antes** de `/validate`. Sin ese paso, el proveedor devuelve `HARDWARE_MISMATCH` (`valid:false`) y la licencia quedaría marcada INVALID → bloqueo "no está vigente" en el 2º equipo. Implementado en `backend/app/api/v1/auth.py` (helper `_es_dispositivo_nuevo`). El endpoint `/licencias/validar` NO auto-registra equipos nuevos (solo recupera `DEVICE_NOT_REGISTERED`): el registro del 2º equipo ocurre en el login autenticado; si el dispositivo ya inició sesión, la revalidación periódica ya encuentra su `hardware_id` inscrito y valida correctamente.

### Administración de sesiones por dispositivo (RB-12)
Una **sesión** equivale a un **dispositivo** (`hardware_id`): el modelo `LicenciaDispositivo` tiene `rol` (nullable) y `estado` (`PENDIENTE`/`APROBADO`/`RECHAZADO`).

5. **Dispositivo dueño (tutor):** El primer equipo en activar la licencia CENTRAL queda como dueño (`es_dueno=True`). Se auto-aprueba con rol `ADMIN_CUENTA` al registrarse. No se puede modificar su estado/rol desde la gestión de sesiones.
6. **Equipo nuevo → pendiente:** Un 2º equipo CENTRAL se registra como `PENDIENTE` sin rol. El login es rechazado con 403 ("pendiente de aprobación") hasta que la tutora lo apruebe desde "Configuración → Gestión de usuarios → Sesiones".
7. **Aprobación exige rol:** No se puede aprobar un dispositivo sin asignarle un rol. La aprobación usa `PATCH /auth/sesiones/{id}` con `{"estado": "APROBADO", "rol": "OPERADOR"}` (u otro de los 5 roles válidos).
8. **Rol de la sesión prevalece:** El rol asignado a la sesión (`dispositivo.rol`) se usa para permisos en lugar del rol del usuario. Si el usuario es ADMIN_CUENTA pero la sesión tiene rol OPERADOR, esa sesión solo tiene permisos de OPERADOR. Si el dispositivo no tiene rol asignado (`rol=NULL`), se usa el rol del usuario (backward-compatible).
9. **Backend de permisos (effectivo):** `GET /auth/me` devuelve el `rol_efectivo` (sesión/dispositivo o usuario). `_check_permission` en `roles.py` lee `getattr(usuario, 'rol_efectivo', None) or usuario.rol`. El JWT incluye `hardware_id` para resolver el rol en cada request.
10. **Rechazo/revocación:** Una sesión puede ser rechazada (`estado=RECHAZADO`) o revocada posteriormente; si el dispositivo tiene una sesión rechazada, `get_current_user` la bloquea (403) y el login la rechaza.

**Endpoints de sesiones (RB-12):**
- `GET /auth/sesiones` — lista todas las sesiones de las licencias CENTRAL de la cuenta (admin only).
- `PATCH /auth/sesiones/{id}` — aprueba/rechaza una sesión, o cambia su rol (admin only; aprobar exige `rol`).

---

## Flujo de Verificación (Mermaid)

```mermaid
flowchart TD
    A[Inicio: Usuario intenta abrir cuenta] --> B{¿Dispositivo tiene licencia activa?}
    
    %% Dispositivo con licencia previa
    B -->|Sí| C{¿Es el Titular de la cuenta?}
    C -->|Sí| E[Redirigir a su cuenta activa]
    C -->|No| F{¿Es Subcliente de CENTRAL?}
    
    E --> G[Ingresar contraseña de cuenta activa]
    G --> M[Acceso Concedido]
    
    F -->|Sí| H[Redirigir a cuenta CENTRAL]
    F -->|No| D[Procesar Login Nuevo]
    
    H --> J{¿Desea salir de la CENTRAL?}
    J -->|Sí| K[Cerrar sesión actual]
    J -->|No| L[Ingresar credenciales CENTRAL]
    
    K --> D
    L --> M

    %% Dispositivo virgen / sesión cerrada
    B -->|No| D
    
    D --> N[Verificar tipo de licencia solicitada]
    N --> O{¿Tipo de Licencia?}
    
    O -->|MONOPUESTA| P{¿Coincide hardware_id?}
    P -->|Sí| M
    P -->|No| S[Acceso Denegado: HWID no autorizado]
    
    O -->|CENTRAL| Q{¿Hay cupo disponible?}
    Q -->|Sí| M
    Q -->|No| T[Acceso Denegado: Sin cupos disponibles]
# DEPLOY.md — Instalación y despliegue en servidor de BALANSOFT-WS

| Atributo  | Valor |
|-----------|-------|
| **Documento** | DEPLOY.md |
| **Versión** | 1.0 |
| **Fecha** | 2026-09-14 |
| **Estado** | Vigente |
| **Autor** | Equipo BALANSOFT |
| **Norma** | ISO/IEC/IEEE 42010 + 29148 |
| **Fuente** | `docs/PRD.md` (autoridad), `docs/ARCH.md` §18–19, `backend/scripts/*` |

---

## 1. Propósito y alcance

Este documento describe **cómo instalar el backend de BALANSOFT-WS en un servidor
de producción** (Linux + systemd + PostgreSQL) a partir del repositorio clonado
desde GitHub, y cómo integrarlo con el **License Manager (SGLB)**.

Cubre la **API solamente** (FastAPI/uvicorn). El frontend Flutter se compila por
separado y se despliega en las estaciones de pesaje (Linux/Android); consume esta
API por HTTP/HTTPS.

> La instalación está **automatizada por `backend/scripts/install_cliente.sh`**,
> que ejecuta en orden: `.env` → esquema BD → migraciones → servicio systemd →
> verificación. Este documento explica ese flujo paso a paso para que un operador
> del servidor pueda seguirlo y validarlo manualmente.

---

## 2. Arquitectura de despliegue

```mermaid
flowchart LR
    subgraph Servidor[Servidor Linux]
        NGINX["nginx (TLS/HTTPS, opcional)"]
        API["uvicorn (4 workers)<br/>:8000"]
        PG[("PostgreSQL<br/>balansoft_ws")]
        LM["BALANSOFT-LM (SGLB)<br/>:8080 (API) / :5000 (admin)"]
        API --> PG
        API --> LM
        NGINX --> API
    end
    EST["Estación Flutter Linux"] -->|HTTPS| NGINX
```

Piezas instaladas por este guion:

| Componente | Descripción |
|------------|-------------|
| Backend FastAPI | Código en `/opt/balansoft-ws/backend/`, entorno virtual en `.venv/` |
| PostgreSQL | Base `balansoft_ws` (esquema de `schema.sql` + `migrations/*.sql`) |
| systemd | Unidad `balansoft-ws.service` (4 workers uvicorn, usuario `balansoft`) |
| .env | Configuración de producción (`SECRET_KEY`, BD, CORS, licencia) |
| Backups | `scripts/backup.sh` vía cron (pg_dump + media) |
| License Manager | Servicio externo resolvible en `LICENSE_API_URL` |

---

## 3. Prerrequisitos del servidor

Sistema operativo recomendado: **Ubuntu 24.04 / Debian 12** (systemd + apt).
Versiones: **Python ≥ 3.12**, **PostgreSQL ≥ 15** (16 recomendado), `psql`,
`pg_dump`, `git`, `curl`, `openssl` y **`uv`** (gestor de paquetes).

```bash
# como root (o con sudo)
apt update && apt upgrade -y
apt install -y git curl ca-certificates openssl postgresql postgresql-client python3 python3-venv

# uv (gestor de dependencias oficial del proyecto) — disponible para todos los usuarios
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
uv --version   # verificar
python3 --version  # debe ser >= 3.12; si no, uv descargará un Python 3.12 gestionado automáticamente
```

> `uv` resuelve automáticamente un intérprete Python ≥ 3.12 según `pyproject.toml`
> (`requires-python`), descargándolo si el del sistema es más antiguo.

---

## 4. Paso a paso de instalación

### 4.1 Crear el usuario de servicio

```bash
adduser --system --group --shell /usr/sbin/nologin --home /opt/balansoft-ws balansoft
```

### 4.2 Crear el rol y la base de datos PostgreSQL

```bash
sudo -u postgres psql <<'SQL'
CREATE ROLE balansoft LOGIN PASSWORD 'CAMBIAR_POR_CONTRASENA_FUERTE' CREATEDB;
SQL
```

El rol necesita `CREATEDB` porque `setup_db.sh` crea la base `balansoft_ws` si no
existe. (Alternativa equivalente: `sudo -u postgres createdb -O balansoft balansoft_ws`).

### 4.3 Clonar el repositorio

```bash
mkdir -p /opt/balansoft-ws
chown balansoft:balansoft /opt/balansoft-ws
sudo -u balansoft git clone git@github.com:panchove/BALANSOFT-WS-DART.git /opt/balansoft-ws
```

> Si el servidor no tiene acceso SSH a GitHub, clona con HTTPS habilitando un
> *personal access token*, o copia el árbol sin los directorios excluidos
> (`.venv/`, `.env`, `media/`, `backups/`, caches).

### 4.4 Preparar el directorio de logs

```bash
mkdir -p /var/log/balansoft-ws
chown -R balansoft:balansoft /var/log/balansoft-ws
```

### 4.5 Crear y completar `.env`

El instalador copia `.env.example` → `.env` y genera un `SECRET_KEY` fuerte
automáticamente. **Edítalo antes** para las credenciales de la BD y el CORS:

```bash
cd /opt/balansoft-ws/backend
sudo -u balansoft cp .env.example .env
sudo -u balansoft nano .env   # o vim / teclado del operador
```

Campos obligatorios a ajustar:

| Variable | Valor de ejemplo |
|----------|------------------|
| `DATABASE_URL` | `postgresql+asyncpg://balansoft:LA_CONTRASENA@localhost:5432/balansoft_ws` |
| `DATABASE_URL_SYNC` | `postgresql+psycopg2://balansoft:LA_CONTRASENA@localhost:5432/balansoft_ws` |
| `SECRET_KEY` | `openssl rand -hex 32` (si lo dejas por defecto, el instalador lo regenera) |
| `CORS_ORIGINS` | Orígenes del frontend web/estación, p. ej. `["https://peso.empresa.example"]` |
| `LICENSE_PUBLIC_KEY` | Clave pública Ed25519 del LM (ver §5) |
| `APP_ENV` | `production` |
| `API_DOCS_ENABLED` | `false` (recomendado en producción) |

Verificación local del valor seguro:

```bash
openssl rand -hex 32   # úsalo como SECRET_KEY si no confías en el generador automático
```

### 4.6 Instalar dependencias con `uv`

```bash
cd /opt/balansoft-ws/backend
sudo -u balansoft uv sync
```

Crea `.venv/` y resuelve las 26 dependencias declaradas en `pyproject.toml`
(bloqueadas por `uv.lock`).

### 4.7 Instalar esquema y migraciones

```bash
sudo -u balansoft bash scripts/setup_db.sh instalar          # crea BD + aplica schema.sql
sudo -u balansoft bash scripts/setup_db.sh aplicar-migraciones  # aplica migrations/*.sql en orden
```

Ambos comandos leen `DATABASE_URL_SYNC` del `.env`.

### 4.8 (Opcional) Datos demo para primera prueba

```bash
sudo -u balansoft bash scripts/setup_db.sh seed
# credenciales demo: admin@balansoft.demo / demo1234  → cambia la contraseña tras el primer login
```

En producción **no** se ejecuta o se hace solo en un entorno de pruebas.

### 4.9 Instalar el servicio systemd

La unidad `deploy/balansoft-ws.service` se ajusta a las rutas/usuarios reales:

```bash
cd /opt/balansoft-ws/backend
INSTALL_PREFIX=/opt/balansoft-ws APP_USER=balansoft SEED=false bash scripts/install_cliente.sh
```

`install_cliente.sh` hace en un solo pase lo descrito en §4.5–§4.9 (`.env` +
`schema.sql` + migraciones + unidad systemd + `verify.sh`). Si ya seguiste los
pasos manuales, replica al final la instalación de la unidad:

```bash
sudo install -m 0644 deploy/balansoft-ws.service /etc/systemd/system/balansoft-ws.service
sudo systemctl daemon-reload
sudo systemctl enable balansoft-ws
```

> **Importante:** la unidad la ejecuta el usuario `balansoft`. Por tanto el
> `.venv/`, `.env` y `media/` deben pertenecer a `balansoft`
> (`chown -R balansoft:balansoft /opt/balansoft-ws`). No ejecutar `uv sync` como root.

### 4.10 Arrancar y validar

```bash
sudo systemctl start balansoft-ws
sudo systemctl status balansoft-ws --no-pager
journalctl -u balansoft-ws -f                       # logs en vivo
curl http://127.0.0.1:8000/api/v1/health            # → {"status":"healthy", ...}
```

### 4.11 Ejecutar la verificación completa

```bash
cd /opt/balansoft-ws/backend
API_PORT=8000 bash scripts/verify.sh
```

Chequeos (salida `0` = servidor correcto, `1` = fallos críticos):

1. Python ≥ 3.12
2. `psql` y `pg_dump` presentes
3. Conexión a BD + esquema (tablas > 5)
4. `.env` presente y `SECRET_KEY` con entropía (≥ 32 chars, no por defecto)
5. `GET /api/v1/health` → 200
6. Servicio `balansoft-ws` activo y habilitado
7. License Manager accesible vía `LICENSE_API_URL`

---

## 5. Integración con el License Manager (SGLB)

BALANSOFT-WS valida licencias contra el **BALANSOFT-LM** local usando un flujo
anti-fake-server: obtiene un token y verifica la **firma Ed25519** de la respuesta
de `/validate` con la clave pública embebida en `.env`.

```mermaid
sequenceDiagram
    participant BW as BALANSOFT-WS (backend)
    participant LM as BALANSOFT-LM (SGLB)
    BW->>LM: POST /api/v1/token (license_key)
    LM-->>BW: token (Bearer)
    BW->>LM: POST /api/v1/validate (hardware + product_code)
    LM-->>BW: respuesta firmada Ed25519
    BW->>BW: verifica firma + server_time (anti-fake-server)
```

### 5.1 Instalar y arrancar el LM

El LM (SGLB) es un producto aparte; despliégalo en el mismo servidor o uno
alcanzable:

- API del LM: `http://<host>:8080/api/v1`
- Consola de administración: `http://<host>:5000`

Verifica su health desde el servidor:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/api/v1/health   # 200 (o 404 válido)
```

### 5.2 Claves Ed25519

El LM firma las respuestas con su clave **privada**; BALANSOFT-WS las verifica con
la **pública**. Dos escenarios:

- **El LM ya tiene su par de claves** (recomendado): copia su clave pública PEM en
  `LICENSE_PUBLIC_KEY` del `.env`, en una sola línea (codificando los saltos de
  línea como `\n`, o entre comillas dobles).
- **Par recién generado** (si el LM se instala por primera vez): genera un par y
  confíguralo en el LM:

```bash
cd /opt/balansoft-ws/backend
sudo -u balansoft uv run python scripts/generate_signing_keys.py keys_lm
# → keys_lm/key_privada.pem   (cárgala como clave de firma del LM)
# → keys_lm/key_publica.pem   (pégalas en LICENSE_PUBLIC_KEY del .env)
```

> ⚠️ `LICENSE_PUBLIC_KEY` debe ser el contenido completo del PEM
> (`-----BEGIN PUBLIC KEY----- … -----END PUBLIC KEY-----`) en una única línea.
> Nunca subir `key_privada.pem` al repositorio.

### 5.3 Configuración resultante en `.env`

```ini
LICENSE_API_URL=http://127.0.0.1:8080/api/v1
LICENSE_ADMIN_URL=http://127.0.0.1:5000
LICENSE_PUBLIC_KEY='-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----'
LICENSE_PRODUCT_CODE=BWS
```

### 5.4 Crear la licencia de la empresa

1. En la consola del LM (`LICENSE_ADMIN_URL`) crea una licencia para el producto
   `BWS` con tier `DEMO`, `MONOPUESTA` o `CENTRAL`.
2. Asocia esa `license_key` a la empresa en la BD (los campos `licencia_key`,
   `licencia_tier`, `licencia_expira` de la tabla `empresas`) o configura la
   licencia/activación desde la API de autenticación del backend
   (ver endpoints `/api/v1/auth/*licencias*` en OpenAPI).
3. Reinicia la API y consulta `/api/v1/health`; luego repite `scripts/verify.sh`
   y confirma el chequeo [7] del LM.

---

## 6. Operación y mantenimiento

### Backups programados (cron)

```bash
crontab -u balansoft -e
# línea sugerida (diario 02:30):
30 2 * * * /opt/balansoft-ws/backend/scripts/backup.sh >> /var/log/balansoft-backup.log 2>&1
```

`backup.sh` genera `pg_dump -Fc` (BD) + `tar.gz` (media) en
`backend/backups/` con retención de `BACKUP_RETENTION_DAYS` (default 30).

### Actualizar a una versión nueva

```bash
cd /opt/balansoft-ws
sudo -u balansoft git pull                    # trae código + nuevas migraciones
cd backend
sudo -u balansoft uv sync                     # actualiza dependencias
bash scripts/setup_db.sh aplicar-migraciones  # aplica nuevas migraciones/*.sql
sudo systemctl restart balansoft-ws
API_PORT=8000 bash scripts/verify.sh
```

### Monitoreo

- Métricas Prometheus: `GET http://127.0.0.1:8000/metrics`
- Logs: `journalctl -u balansoft-ws -f` y `LOG_FILE`
  (`/var/log/balansoft-ws/app.log`)

---

## 7. Notas de seguridad (checklist)

- [ ] `SECRET_KEY` generada con `openssl rand -hex 32` (≥ 32 bytes) y única por servidor.
- [ ] `DATABASE_URL_*` con credenciales reales (no el placeholder del `.env.example`); rotar en producción.
- [ ] `.env` fuera del repositorio: git lo ignora (`backend/.env` en `.gitignore`).
- [ ] `CORS_ORIGINS` restringida a los orígenes reales del frontend (nunca `*` en producción).
- [ ] `APP_ENV=production` y `DEBUG_MODE=false`; `RATE_LIMIT_*` activados.
- [ ] `LICENSE_PUBLIC_KEY` corresponde al LM real (anti-fake-server).
- [ ] Puertos: exponer solo `:8000` (o `:443` vía nginx/TLS); mantener `:8080` y `:5432` internos.
- [ ] Backups periódicos verificados (probarse con `pg_restore --list`).

---

## 8. Solución de problemas frecuentes

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| `setup_db.sh` no conecta | Credenciales placeholder en `.env` | Completar `DATABASE_URL_SYNC` |
| `ModuleNotFoundError` en tests/servicio | `.venv` creado como root | `sudo rm -rf backend/.venv` y re-ejecutar `uv sync` como `balansoft` |
| API arranca pero 403/500 en login | Falta empresa o `SECRET_KEY` débil | `setup_db.sh seed` + regenerar `SECRET_KEY` |
| `verify.sh` falla chequeo [7] | LM caído o `LICENSE_PUBLIC_KEY` mal | Arrancar LM, revisar §5 |
| Servicio no levanta tras `start` | Permisos de `.env`/`.venv` o puerto ocupado | `chown -R balansoft` + `journalctl -u balansoft-ws -n 50` |
| Fotos no se muestran | Falta `media/` (se crea al arrancar) | Verificar `os.makedirs` en `app/main.py` y permisos del usuario |

---

## 9. Referencias del proceso

| Paso | Script / archivo |
|------|------------------|
| Instalación completa automatizada | `backend/scripts/install_cliente.sh` |
| Esquema / migraciones / seed | `backend/scripts/setup_db.sh` (`instalar`, `aplicar-migraciones`, `seed`) |
| Backup | `backend/scripts/backup.sh` |
| Verificación post-instalación | `backend/scripts/verify.sh` |
| Par de claves LM | `backend/scripts/generate_signing_keys.py` |
| Unidad systemd | `backend/deploy/balansoft-ws.service` |
| Plantilla de configuración | `backend/.env.example` |
| Frontend (estaciones) | `frontend/` (compilar para Linux/Android por separado) |
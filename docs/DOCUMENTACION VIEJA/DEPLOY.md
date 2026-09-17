# DEPLOY.md — Instalación y despliegue en servidor de BALANSOFT-WS

| Atributo  | Valor |
|-----------|-------|
| **Documento** | DEPLOY.md |
| **Versión** | 1.1 |
| **Fecha** | 2026-09-14 |
| **Estado** | Vigente |
| **Autor** | Equipo BALANSOFT |
| **Norma** | ISO/IEC/IEEE 42010 + 29148 |
| **Fuente** | `docs/PRD.md` (autoridad), `docs/ARCH.md` §18–19, `docs/RESUMEN-API-LICENCIAS.md` (topología real), `backend/scripts/*` |

---

## 1. Propósito y alcance

Este documento describe **cómo instalar el backend de BALANSOFT-WS en un servidor
de producción** (Linux + systemd + PostgreSQL) a partir del repositorio clonado
desde GitHub, y cómo integrarlo con el **License Manager (BALANSOFT-LM / SGLB)**.

Cubre la **API solamente** (FastAPI/uvicorn). El frontend Flutter se compila por
separado y se despliega en las estaciones de pesaje (Linux/Android); consume esta
API por HTTP/HTTPS.

> Los valores de puertos, servicios y rutas de este documento reflejan la
> **instalación real del servidor de producción** descrita en
> `docs/RESUMEN-API-LICENCIAS.md`: API en `:8002`, LM en `:9001/:9000`, repo en
> `/var/www/BALANSOFT-WS-DART` y clave pública del LM en `backend/keys/lm_public_key.pem`.

La instalación está **automatizada por `backend/scripts/install_cliente.sh`**,
que ejecuta en orden: `.env` → esquema BD → migraciones → servicio systemd →
verificación. Este documento explica ese flujo paso a paso para que un operador
del servidor pueda seguirlo y validarlo manualmente.

---

## 2. Arquitectura de despliegue

```mermaid
flowchart LR
    subgraph Servidor[Servidor Linux]
        NGINX["nginx (TLS/HTTPS, opcional)"]
        API["uvicorn (4 workers)<br/>balansoft-ws.service :8002"]
        PG[("PostgreSQL<br/>balansoft_ws")]
        LM["BALANSOFT-LM (SGLB)<br/>balansoft-lm-api.service :9001<br/>balansoft-lm.service :9000 (portal)"]
        API --> PG
        API --> LM
        NGINX --> API
    end
    EST["Estación Flutter Linux"] -->|HTTPS| NGINX
```

Topología real del servidor (puertos ocupados):

| Servicio | Endpoint | Nota |
|----------|----------|------|
| BALANSOFT-WS API | `0.0.0.0:8002` | Este guion la instala/actualiza; estaciones desktop Flutter por LAN |
| BALANSOFT-LM API (validación) | `127.0.0.1:9001/api/v1` | Ya desplegado (existe en el servidor) |
| BALANSOFT-LM Portal (admin) | `127.0.0.1:9000` | Ya desplegado |
| Landing / otros | `:8000`, `:8001` | Ya desplegado (`balansoft.service`, `balansoft-sg.service`) |

Piezas instaladas por este guion:

| Componente | Descripción |
|------------|-------------|
| Backend FastAPI | Código en `/var/www/BALANSOFT-WS-DART/backend/`, entorno virtual en `.venv/` |
| PostgreSQL | Base `balansoft_ws` (esquema de `schema.sql` + `migrations/*.sql`) |
| systemd | Unidad `balansoft-ws.service` desde `deploy/balansoft-ws.service.prod` (4 workers uvicorn, usuario `serverman`) |
| .env | Configuración de producción (`SECRET_KEY`, BD, CORS, licencia) |
| Backups | `scripts/backup.sh` vía cron (pg_dump + media) |
| License Manager | Resolvible en `LICENSE_API_URL` (LM local en `:9001`) |

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

> Los pasos usan la ruta real del servidor (`/var/www/BALANSOFT-WS-DART`) y el
> usuario del servicio (`serverman`). En otro servidor, ajusta ambas.

### 4.1 Usuario y directorio del repo

```bash
# El repo vive en /var/www/BALANSOFT-WS-DART propiedad del usuario del servicio.
sudo chown -R serverman:serverman /var/www/BALANSOFT-WS-DART
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
cd /var/www   # el usuario del servicio debe poder escribir
sudo -u serverman git clone git@github.com:panchove/BALANSOFT-WS-DART.git
```

> Si el servidor no tiene acceso SSH a GitHub, clona con HTTPS habilitando un
> *personal access token*, o copia el árbol sin los directorios excluidos
> (`.venv/`, `.env`, `media/`, `backups/`, `keys/`, `logs/`, caches).
> También puedes clonar en el home y luego `sudo mv` al destino final (ver
> troubleshooting §8).

### 4.4 Preparar el directorio de logs

```bash
sudo mkdir -p /var/log/balansoft-ws
sudo chown -R serverman:serverman /var/log/balansoft-ws
```

### 4.5 Crear y completar `.env`

El instalador copia `.env.example` → `.env` y genera un `SECRET_KEY` fuerte
automáticamente. **Edítalo antes** para las credenciales de la BD y el CORS:

```bash
cd /var/www/BALANSOFT-WS-DART/backend
sudo -u serverman cp .env.example .env
sudo -u serverman nano .env   # o vim / teclado del operador
```

Campos obligatorios a ajustar:

| Variable | Valor de ejemplo |
|----------|------------------|
| `DATABASE_URL` | `postgresql+asyncpg://balansoft:LA_CONTRASENA@localhost:5432/balansoft_ws` |
| `DATABASE_URL_SYNC` | `postgresql+psycopg2://balansoft:LA_CONTRASENA@localhost:5432/balansoft_ws` |
| `SECRET_KEY` | `openssl rand -hex 32` (si lo dejas por defecto, el instalador lo regenera) |
| `CORS_ORIGINS` | Orígenes del frontend web/estación, p. ej. `["https://peso.empresa.example"]` |
| `LICENSE_PUBLIC_KEY_PATH` | `keys/lm_public_key.pem` (relativo al backend; ver §5) |
| `APP_ENV` | `production` |
| `API_DOCS_ENABLED` | `false` (recomendado en producción) |

Verificación local del valor seguro:

```bash
openssl rand -hex 32   # úsalo como SECRET_KEY si no confías en el generador automático
```

### 4.6 Copiar la clave pública del LM

La clave pública Ed25519 del LM vive en `backend/keys/lm_public_key.pem`
(carpeta `keys/` ignorada por git). El backend la lee desde `LICENSE_PUBLIC_KEY_PATH`
al arrancar. Como ya es la instalación real, copia la clave existente del servidor
(o desde el LM si se regenera):

```bash
cd /var/www/BALANSOFT-WS-DART/backend
sudo -u serverman mkdir -p keys
# copiar desde el origen real del servidor, p. ej.:
sudo -u serverman cp /ruta/origen/lm_public_key.pem keys/lm_public_key.pem
sudo -u serverman chmod 600 keys/lm_public_key.pem
```

### 4.7 Instalar dependencias con `uv`

```bash
cd /var/www/BALANSOFT-WS-DART/backend
sudo -u serverman uv sync
```

Crea `.venv/` y resuelve las dependencias declaradas en `pyproject.toml`
(bloqueadas por `uv.lock`).

### 4.8 Instalar esquema y migraciones

```bash
sudo -u serverman bash scripts/setup_db.sh instalar          # crea BD + aplica schema.sql
sudo -u serverman bash scripts/setup_db.sh aplicar-migraciones  # aplica migrations/*.sql en orden
```

Ambos comandos leen `DATABASE_URL_SYNC` del `.env`. Las migraciones son
**idempotentes** (usan `to_regclass`/`information_schema`), por lo que funcionan
tanto en instalaciones nuevas como en actualizaciones de esquemas previos.

### 4.9 (Opcional) Datos demo para primera prueba

```bash
sudo -u serverman bash scripts/setup_db.sh seed
# credenciales demo: admin@balansoft.demo / demo1234  → cambia la contraseña tras el primer login
```

En producción **no** se ejecuta o se hace solo en un entorno de pruebas.

### 4.10 Instalar el servicio systemd

Para el servidor real se usa la unidad **`deploy/balansoft-ws.service.prod`**
(ya precargada con las rutas reales, puerto `8002`, bind `0.0.0.0` y usuario
`serverman`). El bind `0.0.0.0` es intencional: las estaciones desktop Flutter se
conectan por LAN indicando la IP del servidor (mismo patrón que BALANSOFT-SG);
por eso **restringir** `:8002` en el firewall solo al subnet de estaciones.

```bash
cd /var/www/BALANSOFT-WS-DART/backend
sudo install -m 0644 deploy/balansoft-ws.service.prod /etc/systemd/system/balansoft-ws.service
sudo systemctl daemon-reload
sudo systemctl enable balansoft-ws
```

Alternativa automatizada desde un servidor genérico (ajusta `INSTALL_PREFIX`/`APP_USER`):

```bash
cd /ruta/al/repo/backend
INSTALL_PREFIX=/var/www/BALANSOFT-WS-DART APP_USER=serverman API_PORT=8002 SEED=false \
  bash scripts/install_cliente.sh
```

> **Importante:** la unidad la ejecuta el usuario del servicio (`serverman`). Por
> tanto el `.venv/`, `.env`, `media/`, `backups/` y `keys/` deben pertenecerle
> (`chown -R serverman:serverman /var/www/BALANSOFT-WS-DART`). No ejecutar `uv sync` como root.

### 4.11 Arrancar y validar

```bash
sudo systemctl start balansoft-ws
sudo systemctl status balansoft-ws --no-pager
journalctl -u balansoft-ws -f                       # logs en vivo
curl http://127.0.0.1:8002/api/v1/health            # → {"status":"healthy", ...}
```

### 4.12 Ejecutar la verificación completa

```bash
cd /var/www/BALANSOFT-WS-DART/backend
bash scripts/verify.sh
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
de `/validate` con la clave pública del LM (vía `LICENSE_PUBLIC_KEY_PATH`).

```mermaid
sequenceDiagram
    participant BW as BALANSOFT-WS (backend)
    participant LM as BALANSOFT-LM (SGLB :9001)
    BW->>LM: POST /api/v1/token (license_key)
    LM-->>BW: token (Bearer)
    BW->>LM: POST /api/v1/validate (hardware + product_code)
    LM-->>BW: respuesta firmada Ed25519
    BW->>BW: verifica firma + server_time (anti-fake-server)
```

### 5.1 Componentes del LM en el servidor real

| Componente | Servicio | Endpoint |
|------------|----------|----------|
| BALANSOFT-LM API (validación) | `balansoft-lm-api.service` | `127.0.0.1:9001/api/v1` |
| BALANSOFT-LM Portal (admin) | `balansoft-lm.service` | `127.0.0.1:9000` |
| Landing / otros | `balansoft.service`, `balansoft-sg.service` | `:8000`, `:8001` |

Verifica su health desde el servidor:

```bash
curl -s http://127.0.0.1:9001/api/v1/health    # LM API arriba (200 o 404 válido)
curl -s http://127.0.0.1:8002/api/v1/health    # WS arriba
```

### 5.2 Claves Ed25519

El LM firma las respuestas con su clave **privada**; BALANSOFT-WS las verifica con
la **pública**.

- El **LM real ya tiene su par de claves**. Su clave privada vive únicamente ahí:
  `/var/www/BALANSOFT-LM/keys/ml_private_key.pem` (permisos `600`); **nunca** debe
  subirse al repositorio. La pública se instala en
  `backend/keys/lm_public_key.pem` (ver §4.6).
- **Par recién generado** (solo si se instala un LM nuevo): genera un par con
  `scripts/generate_signing_keys.py`;

```bash
cd /var/www/BALANSOFT-WS-DART/backend
sudo -u serverman uv run python scripts/generate_signing_keys.py keys_lm
# → keys_lm/key_privada.pem   (cárgala como clave de firma del LM)
# → keys_lm/key_publica.pem   (cópiala a keys/lm_public_key.pem)
```

> ⚠️ La clave pública no es secreto (puede estar en el repo del lado del cliente);
> la **privada** sí lo es y nunca debe subirse.

### 5.3 Configuración resultante en `.env`

```ini
LICENSE_API_URL=http://127.0.0.1:9001/api/v1
LICENSE_ADMIN_URL=http://127.0.0.1:9000
LICENSE_PUBLIC_KEY_PATH=keys/lm_public_key.pem   # clave pública del LM (Ed25519)
LICENSE_PRODUCT_CODE=WS
```

> `LICENSE_PUBLIC_KEY_PATH` es la vía recomendada en servidores (archivo PEM).
> Como alternativa, `LICENSE_PUBLIC_KEY` acepta el PEM en una sola línea.

### 5.4 Crear y enlazar la licencia de la empresa

1. En el **portal del LM** (`http://<servidor>:9000`) crea una licencia del
   producto **WS** con tier `DEMO`, `MONOPUESTA` o `CENTRAL` para el cliente.
2. El cliente crea su empresa con `POST /api/v1/auth/register` enviando ese
   `licencia_key`: el WS la valida (`check`) contra el LM y cachea
   `tier/status/vencimiento` en la tabla `empresas`
   (`licencia_key`, `licencia_tier`, `licencia_status`, `licencia_expira`).
   (Alternativa: actualizar `empresas.licencia_key` por admin/DBA.)
3. A partir de ahí, cada login y cada **creación de pesaje** validan la licencia
   contra el LM; el `hardware_id` debe coincidir con el del `fingerprint` activado
   para los tiers DEMO/MONOPUESTA (un solo dispositivo).
4. Valida el estado con `POST /api/v1/auth/validate-license` (ADMIN) o consulta el
   snapshot `GET /api/v1/auth/license`, y repite `bash scripts/verify.sh`
   (chequeo [7]).

> Si `empresas.licencia_key` está **vacía**, la empresa opera sin validación
> online (estado `SIN_LICENCIA`, típico de la empresa demo).

---

## 6. Operación y mantenimiento

### Backups programados (cron)

```bash
crontab -u serverman -e
# línea sugerida (diario 02:30):
30 2 * * * /var/www/BALANSOFT-WS-DART/backend/scripts/backup.sh >> /var/log/balansoft-backup.log 2>&1
```

`backup.sh` genera `pg_dump -Fc` (BD) + `tar.gz` (media) en
`backend/backups/` con retención de `BACKUP_RETENTION_DAYS` (default 30).

### Actualizar a una versión nueva

```bash
cd /var/www/BALANSOFT-WS-DART
sudo -u serverman git pull                    # trae código + nuevas migraciones
cd backend
sudo -u serverman uv sync                     # actualiza dependencias
bash scripts/setup_db.sh aplicar-migraciones  # aplica nuevas migraciones/*.sql
sudo systemctl restart balansoft-ws
bash scripts/verify.sh
```

### Monitoreo

- Métricas Prometheus: `GET http://127.0.0.1:8002/metrics`
- Logs: `journalctl -u balansoft-ws -f` y `LOG_FILE`
  (`/var/log/balansoft-ws/app.log`)

---

## 7. Notas de seguridad (checklist)

- [ ] `SECRET_KEY` generada con `openssl rand -hex 32` (≥ 32 bytes) y única por servidor.
- [ ] `DATABASE_URL_*` con credenciales reales (no el placeholder del `.env.example`); rotar en producción.
- [ ] `.env` fuera del repositorio: git lo ignora (`backend/.env` en `.gitignore`).
- [ ] `CORS_ORIGINS` restringida a los orígenes reales del frontend (nunca `*` en producción).
- [ ] `APP_ENV=production` y `DEBUG_MODE=false`; `RATE_LIMIT_*` activados.
- [ ] `LICENSE_PUBLIC_KEY_PATH` apunta al PEM real del LM (anti-fake-server); clave privada del LM nunca en el repo.
- [ ] Puertos: uvicorn escucha en `0.0.0.0:8002`; abrir en el firewall solo el acceso de las estaciones desktop a `:8002` (y si hay dominio, `:443` vía nginx/TLS como en BALANSOFT-SG); mantener `:9000`, `:9001`, `:8000`, `:8001` y `:5432` internos.
- [ ] Backups periódicos verificados (probarse con `pg_restore --list`).

---

## 8. Solución de problemas frecuentes

| Síntoma | Causa probable | Solución |
|---------|----------------|----------|
| `setup_db.sh` no conecta | Credenciales placeholder en `.env` | Completar `DATABASE_URL_SYNC` |
| `ModuleNotFoundError` en tests/servicio | `.venv` creado como root | `sudo rm -rf backend/.venv` y re-ejecutar `uv sync` como `serverman` |
| API arranca pero 403/500 en login | Falta empresa o `SECRET_KEY` débil | `setup_db.sh seed` + regenerar `SECRET_KEY` |
| `verify.sh` falla chequeo [7] | LM caído o `LICENSE_PUBLIC_KEY_PATH` mal | Arrancar LM (`:9001`), revisar §5 |
| Servicio no levanta tras `start` | Permisos de `.env`/`.venv` o puerto ocupado | `chown -R serverman` + `journalctl -u balansoft-ws -n 50` |
| `try: Permission denied (publickey)` al clonar con `sudo` | root no tiene la clave SSH del deploy | Clonar como `serverman` en el home y `sudo mv` a `/var/www` + `sudo chown -R serverman:serverman` |
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
| Unidad systemd **servidor real** | `backend/deploy/balansoft-ws.service.prod` |
| Unidad systemd genérica | `backend/deploy/balansoft-ws.service` |
| Plantilla de configuración | `backend/.env.example` |
| Topología real y validación de licencias | `docs/RESUMEN-API-LICENCIAS.md` |
| Frontend (estaciones) | `frontend/` (compilar para Linux/Android por separado) |
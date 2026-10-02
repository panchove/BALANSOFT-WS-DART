# Observabilidad de BALANSOFT-WS (H6)

Stack de desarrollo para ver lo que ya expone el backend: Prometheus + Grafana +
Alertmanager. **No hay que instalar nada en la estación** para que funcione: el
endpoint `/metrics` ya existe.

Documento normativo del alcance: [`docs/OBSERVABILIDAD.md`](../../../docs/OBSERVABILIDAD.md).

---

## 1. Qué hay aquí

| Archivo | Para qué sirve |
|---------|----------------|
| `prometheus.yml` | Configura el scrape de `/metrics` (job `balansoft-api`) |
| `alerts/balansoft-alerts.yml` | Reglas de alerta sobre las métricas existentes |
| `alertmanager.yml` | Enrutado y silenciado de alertas (receptor vacío por defecto) |
| `grafana/provisioning/` | Datasource y carga automática de dashboards |
| `grafana/dashboards/balansoft-overview.json` | Panorama de la estación (7 paneles) |
| `docker-compose.observability.yml` | Levanta los tres servicios en dev |

Las **métricas no se crean aquí**: todas salen de `backend/app/core/monitoring.py`.
Si añades una métrica al backend, actualiza este directorio y
`docs/OBSERVABILIDAD.md` a la par.

---

## 2. Levantar en desarrollo

```bash
cd backend
docker compose -f deploy/observability/docker-compose.observability.yml up -d
```

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| Prometheus | http://localhost:9090 | — |
| Grafana | http://localhost:3000 | `admin` / `admin` (**solo dev**) |
| Alertmanager | http://localhost:9093 | — |

La API debe estar corriendo aparte y con `METRICS_ENABLED=true` (el valor por
defecto ya lo está):

```bash
cd backend && uvicorn app.main:app --port 8000
curl -s http://localhost:8000/metrics | head
```

En Prometheus → **Status → Targets**, el objetivo `balansoft-api` debe estar
`UP`. Si aparece `DOWN`, casi siempre es que el backend no corre o que
`METRICS_ENABLED=false`.

Parar todo:

```bash
docker compose -f deploy/observability/docker-compose.observability.yml down
```

### Validar la configuración antes de desplegar

```bash
promtool check config deploy/observability/prometheus.yml
promtool check rules deploy/observability/alerts/balansoft-alerts.yml
amtool check-config deploy/observability/alertmanager.yml
docker compose -f deploy/observability/docker-compose.observability.yml config
```

---

## 3. Instalar Prometheus nativo (estación o servidor)

```bash
sudo cp deploy/observability/prometheus.yml /etc/prometheus/prometheus.yml
sudo cp -r deploy/observability/alerts /etc/prometheus/rules
# En prometheus.yml, cambia el target host.docker.internal:8000 por la IP
# o el nombre de host real de la estación (API_HOST=0.0.0.0 la hace
# alcanzable desde la LAN).
sudo promtool check config /etc/prometheus/prometheus.yml
sudo systemctl reload prometheus
```

---

## 4. Qué muestran las alertas

| Alerta | Severidad | Condición | Cuándo mirar |
|--------|-----------|-----------|--------------|
| `BalansoftApiCaida` | critical | `up == 0` durante 2 min | El proceso del backend no está vivo |
| `BalansoftLatenciaAlta` | warning | p95 > 1 s durante 10 min | Consultas lentas o estación saturada |
| `BalansoftLatenciaCritica` | critical | p95 > 2,5 s durante 5 min | El operador percibe la estación colgada |
| `BalansoftErrores5xx` | critical | > 0,5 5xx/s durante 10 min | Bug en el backend; ver log JSON |
| `BalansoftErrores4xx` | warning | > 1 4xx/s durante 15 min | Credenciales malas o acceso indebido |
| `BalansoftErroresLicencia` | critical | > 5 fallos de licencia en 15 min | LM caído o licencia rechazada |
| `BalansoftLicenciaSinUso` | info | 0 sesiones en 3 h | Estación posiblemente abandonada |
| `BalansoftPesajesDetenidos` | warning | se cierran pesajes y ninguno queda pendiente | Flujo de entrada atascado |

Las reglas de `alertmanager.yml` ya silencian las alertas de latencia y 5xx
cuando `BalansoftApiCaida` está activa: si la API está caída, esos síntomas son
consecuencia y no causa.

---

## 5. Pendiente de infraestructura

Esto **no** se puede cerrar desde el repositorio; requiere decisiones y accesos
del proveedor:

- **Canal de notificación real.** El receptor por defecto es `null` (se
  descarta todo). Hay que definir a quién llega un correo o mensaje y añadir el
  `webhook_configs` comentado en `alertmanager.yml`.
- **Retención y tamaño.** El compose retiene 15 días en el contenedor. En
  producción hace falta decidir volumen (disco, TSDB remoto) y su respaldo.
- **TLS y autenticación.** Prometheus, Grafana y Alertmanager se publican solo
  en `127.0.0.1`. Exponerlos exige proxy inverso con TLS
  (ver `deploy/balansoft-ws.nginx`) y autenticación real.
- **Alta Availability / redundancia.** Nada de esto es alta disponibilidad: es
  un punto único de fallo aceptable en una estación de pesaje.
- **Certificados y firma de binarios** (H4) y **backups del LM** (H3): siguen
  bloqueados por acceso externo.

---

## 6. Nota de privacidad

Las métricas son agregadas y técnicas: no llevan `id_empresa` ni datos de
boletos. Los identificadores de ruta se normalizan a `{id}` para acotar la
cardinalidad. No añadas como *label* nada que identifique a una empresa o a un
operador: convertiría el endpoint `/metrics` en una fuga de datos entre
tenant, y la tarjeta de multi-tenancy lo prohíbe.
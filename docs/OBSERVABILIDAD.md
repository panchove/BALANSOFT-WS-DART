# Observabilidad de BALANSOFT-WS

Métricas de la estación y del servidor central: qué expone el backend, cómo se
consume y qué alertas hay. Documento vigente del alcance.

**Ver también**: [`backend/deploy/observability/README.md`](../backend/deploy/observability/README.md) (cómo levantar el stack) y `app/core/monitoring.py` (implementación).

---

## Encabezado editorial

| Campo | Valor |
|-------|-------|
| Versión | 1.0 |
| Fecha | 2026-10-01 |
| Estado | Vigente |
| Autor | Equipo BALANSOFT-WS |
| Norma | AGENTS.md v3.6, `docs/MANEJO_DB.md` |
| Fuente | `backend/app/core/monitoring.py`, `backend/app/core/config.py`, `backend/app/main.py`, `backend/deploy/observability/` |

---

## 1. Alcance

`GET /metrics` expone el estado técnico del proceso: tráfico, latencia,
volumen de pesajes, incidencias de licencia y sesiones. Sirve para saber si la
estación está sana; **no** sustituye a la tabla `auditoria`, que es la fuente
de verdad para trazabilidad de acciones de usuario.

Lo que este documento **no** cubre (y está en otro lado):

| Necesidad | Dónde resolverla |
|-----------|------------------|
| Quién hizo qué y cuándo | `GET /api/v1/auditoria` (endpoint `auditoria.py`) |
| Reglas de negocio de pesaje | `docs/MODELO_ESTANDAR.md` |
| Sincronización offline | `docs/MANEJO_DB.md` |

---

## 2. Activación

| Variable | Por defecto | Efecto |
|----------|-------------|--------|
| `METRICS_ENABLED` | `true` | `false` desactiva tanto el middleware como el endpoint `/metrics` |

En `app/main.py` el middleware `MetricsMiddleware` y la ruta `/metrics` se
montan solo si el flag está activo. Con el flag apagado, Prometheus verá un 404
y disparará `BalansoftApiCaida`: es el comportamiento esperado, no un fallo.

El endpoint **no requiere autenticación**: Prometheus lo consulta sin token.
Por eso solo debe publicarse en la red interna (por defecto la API escucha en
`0.0.0.0:8000` dentro de la LAN de la estación) y nunca detrás de internet sin
proxy con TLS.

---

## 3. Catálogo de métricas (INT-101)

Cinco métricas. Todas agregadas y técnicas: **ninguna lleva `id_empresa`** (ver
§6).

### 3.1 `balansoft_http_requests_total` — Counter

Requests atendidos, por código de respuesta.

| Label | Valores | Significado |
|-------|---------|-------------|
| `method` | `GET`, `POST`, `PUT`, `DELETE` | Método HTTP |
| `endpoint` | Ruta normalizada a `{id}` | Ej. `/api/v1/weighing/boleto/{id}` |
| `status` | Código HTTP | `200`, `401`, `409`, `500`… |

```promql
sum by (status) (rate(balansoft_http_requests_total[5m]))
topk(10, sum by (endpoint) (rate(balansoft_http_requests_total[5m])))
```

### 3.2 `balansoft_api_latency_seconds` — Histogram

Latencia por request, en segundos. Buckets: `0.01, 0.05, 0.1, 0.25, 0.5, 1.0,
2.5, 5.0`. Labels: `method`, `endpoint` (sin `status`).

```promql
histogram_quantile(0.95, sum by (le, endpoint) (rate(balansoft_api_latency_seconds_bucket[5m])))
```

### 3.3 `balansoft_pesajes_total` — Counter

| Label | Valores |
|-------|---------|
| `estatus` | `PENDIENTE`, `CERRADO`, `ANULADO` |
| `tier` | `DEMO`, `CENTRAL` |

Un boleto cuenta **una vez por estado que alcanza**: al abrirlo se incrementa
`PENDIENTE`, al cerrarlo `CERRADO`, al anularlo `ANULADO`. No hay `MODIFICADO`
porque la métrica sigue la transición de estados, no cada edición.

### 3.4 `balansoft_license_errors_total` — Counter

| Label | Valores |
|-------|---------|
| `tier` | `DEMO`, `CENTRAL` |
| `reason` | Motivo del fallo (LM inalcanzable, licencia inválida, expirada, tamper) |

Es la señal más valiosa en campo: si sube, la estación opera en modo degradado.

### 3.5 `balansoft_active_users` — Counter

Inicios de sesión exitosos acumulados por `tier`. Es un **contador desde el
arranque del proceso**, no un gauge de sesiones vivas: el dashboard lo muestra
como acumulado y la alerta `BalansoftLicenciaSinUso` compara `increase(...)`
para saber si hubo logins en una ventana.

---

## 4. Cardinalidad

`_normalize_path()` sustituye UUIDs y segmentos numéricos por `{id}` antes de
etiquetar. Sin eso, `/api/v1/weighing/boleto/<uuid>` crearía una serie por
boleto y la memoria de Prometheus explotaría en una estación con volumen.

Consecuencia práctica: en las métricas **no** se puede identificar un boleto
concreto. Para eso está la base de datos y la auditoría.

---

## 5. Alertas (INT-102)

Definidas en `backend/deploy/observability/alerts/balansoft-alerts.yml`.

| Alerta | Severidad | Condición |
|--------|-----------|-----------|
| `BalansoftApiCaida` | critical | `up{job="balansoft-api"} == 0` por 2 min |
| `BalansoftLatenciaAlta` | warning | p95 > 1 s por 10 min |
| `BalansoftLatenciaCritica` | critical | p95 > 2,5 s por 5 min |
| `BalansoftErrores5xx` | critical | > 0,5 5xx/s por 10 min |
| `BalansoftErrores4xx` | warning | > 1 4xx/s por 15 min |
| `BalansoftErroresLicencia` | critical | > 5 fallos de licencia en 15 min |
| `BalansoftLicenciaSinUso` | info | 0 sesiones en 3 h |
| `BalansoftPesajesDetenidos` | warning | se cierran pesajes y ninguno queda pendiente |

Cada alerta lleva `severity` y un `runbook` con el enlace a la sección de
diagnóstico de este documento. `alertmanager.yml` silencia latencia y 5xx
cuando `BalansoftApiCaida` está activa: son síntoma, no causa.

### Probar las reglas

```bash
promtool check rules backend/deploy/observability/alerts/balansoft-alerts.yml
```

---

## 6. Multi-tenancy y privacidad

Las métricas son agregadas y **no incluyen `id_empresa`**, por dos razones:

1. **Fuga entre tenant.** Un `label` por empresa expone el tráfico de cada
   cliente a quien pueda leer `/metrics`. La tarjeta de multi-tenancy lo
   prohíbe: el `id_empresa` se determina siempre desde el contexto
   autenticado, nunca desde datos del cliente.
2. **Cardinalidad.** Una instalación con muchas empresas multiplicaría las
   series sin aportar valor operativo.

Consecuencia: las métricas dicen *cuánto* pesa el sistema, nunca *de quién*.
El detalle por empresa sale de `auditoria` (filtrable por fecha y entidad).

`backend/tests/test_monitoring.py` verifica esta regla: falla si alguien añade
`id_empresa` como label en el andamiaje de observabilidad.

---

## 7. Diagnóstico

Guía de lectura de síntomas:

| Síntoma | Dónde mirar primero | Qué hacer |
|---------|--------------------|-----------|
| Panel en gris, sin datos | Prometheus → Status → Targets | Backend caído, `METRICS_ENABLED=false` o target mal configurado |
| p95 alto en un solo endpoint | `topk` de requests: si además es el más tráfico, es carga; si es Poco y lento, es una consulta | Revisar índices y la query en `services/` |
| `license_errors_total` subiendo | Label `reason`: `unreachable` es red; `invalid`/`expired` es licencia | Red primero; si es licencia, `GET /api/v1/auth/license` |
| 4xx sostenidos | Tabla `auditoria` (`accion`, `email`, `ip`) | Credenciales o cliente desactualizado |
| `up == 0` | Log del WServer / journald | El proceso no está vivo |

El backend escribe log estructurado con `LOG_FORMAT=json`, que incluye la misma
información con más detalle (ver `app/core/logging_config.py` y
`docs/MANEJO_DB.md` §11).

---

## 8. Pendiente de infraestructura

| Ítem | Por qué no se cierra aquí |
|------|---------------------------|
| Canal de notificación (correo/Slack) | Requiere decidir destinatarios y credenciales del servicio |
| Retención a largo plazo y réplicas | Requiere definir almacenamiento y su respaldo |
| TLS y autenticación en Prometheus/Grafana | Requiere dominio y certificado (mismo bloqueo que H4/H3) |
| Alta disponibilidad | Fuera de alcance: una estación no necesita HA |

El receptor de Alertmanager es `null` a propósito: en desarrollo no debe
llegar ninguna notificación real.

> **Detalle que costó una caída en bucle**: en `alertmanager.yml` el nombre del
> receptor va **entrecomillado** (`receiver: "null"`). Sin comillas, YAML
> interpreta `null` como el valor nulo y Alertmanager aborta el arranque con
> `missing name in receiver`, reiniciándose en bucle. La suite
> `backend/tests/test_monitoring.py` lo verifica.
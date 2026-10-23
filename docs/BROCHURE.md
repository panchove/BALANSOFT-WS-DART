# BALANSOFT-WS — Brochure Comercial
**Sistema estación pesaje industrial multi-empresa**
FastAPI + Flutter + WServer (PyInstaller) + HAL básculas
Versión: 0.4.2-dev.56 | Idioma: español

---

## ¿Por qué BALANSOFT-WS?

El cliente no compra un lector de báscula: compra **tranquilidad** para cerrar el mes, responder a una auditoría y saber qué pasó con cada camión.

Menos errores, más control y **costo operativo reducido**. El sistema resuelve estos dolores:

- ❌ Pesajes anotados a mano que se pierden o se repiten
- ❌ Inventario que no cuadra por salidas no registradas a tiempo
- ❌ Reportes armados al final del mes, con errores y tarde
- ❌ Discusiones sin evidencia: no se sabe quién pesó, cuándo ni con qué báscula
- ❌ Operación detenida cuando falla internet

✓ Un boleto único, numerado y trazable por cada entrada y salida
✓ Kardex automático: cada pesaje mueve el inventario del almacén
✓ Reportes diarios, mensuales y comparativos listos para exportar
✓ Trazabilidad completa: usuario, IP, fecha UTC, ediciones y anulaciones con evidencia
✓ Operación local que sigue funcionando sin conexión a internet

---

## 10 Bondades que venden solas

| #  | Bondad                           | Beneficio                                                                                                                       |
|----|----------------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| 1  | Opera sin internet               | La estación trabaja contra su base de datos local; si se cae la red, el pesaje continúa y la sincronización se reanuda después  |
| 2  | Un solo sistema de punta a punta | Catálogos, pesaje, inventario, ticket, reportes y auditoría en el mismo lugar; menos planillas, menos reprocesos, menos errores |
| 3  | Habla con básculas reales        | Serial RS-232/USB y TCP/IP, con parser multi-marca (Toledo/GSI, Yaohua, Keli, Torrey, Rice Lake, más)                           |
| 4  | El ticket sale como debe salir   | Rollos 58/80 mm, media carta, carta y APDF o TXT; vista idéntica a la preview                                                   |
| 5  | Trazabilidad metrológica         | El peso capturado no se edita; cada boleto guarda báscula, modo de captura, usuario, fecha UTC y estabilidad                    |
| 6  | Kardex automático                | Movimiento 10 = Ingreso (+), Movimiento 60 = Despacho (−); anulación registra el contra-asiento exacto                          |
| 7  | Reportes para decidir            | Diario, mensual, por vehículo, transportista, tercero, rango de peso, comparativo mensual y Kardex; exportables a Excel y PDF   |
| 8  | Seguridad por roles              | Matriz de permisos por módulo (ADMIN/OPERADOR/AUDITOR); cada empresa configura su matriz                                        |
| 9  | Crece con la operación           | DEMO (hasta 10 boletos, 3 sesiones) → CENTRAL (estaciones ilimitadas, sincronización) sin reinstalar                            |
| 10 | Implementación rápida            | Puesta en marcha en 1–3 días; acompañamiento en capacitación y checklist de aceptación                                          |

---

## Arquitectura en una mirada

- **Dos roles:** `APP_ROLE=local` (estación operativa) o `server` (central de cuenta/licencia/sync/panel)
- **Motor BD por prefijo:** `postgresql…` o `mssql…`; sin nuevas env vars
- **Sin Alembic:** migraciones hand-made `src/backend/migrations/*.sql` (001–025), idempotentes, aplicadas por WServer al arrancar
- **WServer:** binario PyInstaller one-file; 1ª instalación genera `.env` desde `.env.plantilla` (SECRET_KEY aleatoria) y aplica migraciones
- **Licencia:** estación no gatea por `features`/`plan_type`. Tope local: `limite_sesiones_por_tier()` → DEMO = 3, resto `None`; tope real lo pone `licencias.max_sesiones` del central
- **Llaves de activación:** `POST /api/v1/activacion/llaves` → BS-XXXX-XXXX-XXXX (SHA-256, expira 1 h–90 días, default 7)
- **Series numeración:** `SELECT … FOR UPDATE` por empresa, contador transaccional; `DELETE` de una serie usada responde **409**
- **Multi-tenencia obligatoria:** `id_empresa` en **toda** consulta, filtro, inserción o validación; ninguna métrica Prometheus ni log público lo exponga
- **i18n:** 139 claves × es/en/pt en backend; 848 × es/en/pt en frontend; idioma vía `?idioma=` / `Accept-Language`
- **Paridad ticket:** layout canónico en Flutter (`ticket_preview_dialog.dart`); backend debe reflejarse exactamente (tabla 5 columnas v3.24)

---

## Casos de uso por sector

| Sector                   | Dolor típico                                       | Cómo responde BALANSOFT-WS                            |
|--------------------------|----------------------------------------------------|-------------------------------------------------------|
| Agroindustria            | Recepción de materia prima con planillas y demoras | Pesaje rápido, ticket y Kardex de ingreso automático  |
| Molinos y balanceados    | Inventario que no cuadra con las salidas           | Movimiento 60 por despacho y reportes por producto    |
| Puertos y terminales     | Alto volumen y necesidad de evidencia              | Multiestación, auditoría y reportes por transportista |
| Cemento y áridos         | Control de sobrecarga y despacho                   | Capacidad máxima, peso en vivo y ticket con neto      |
| Reciclaje                | Compras a terceros y trazabilidad                  | Terceros, productos, Kardex y reportes por proveedor  |
| Químicos y fertilizantes | Densidad, litros y unidades                        | Datos adicionales y conversiones por producto         |
| Alimentos y bebidas      | Control de recepción y despacho                    | Entrada/salida, fotos y auditoría de cambios          |
| Transporte de carga      | Viajes y toneladas por placa                       | Reporte por vehículo y por transportista              |

---

## Ruta de crecimiento

```
Demo → Piloto → Central → Expansión
Un equipo, 10 boletos, todos los módulos → Operación real controlada → Todos los módulos, sin recortes → Más plantas y equipos, más sincronización
```

- **Defina cantidad de estaciones, sesiones simultáneas, volumen de boletos y si requiere sincronización central.**
- **Ideal para piloto, feria o prueba en planta** (DEMO)
- **Ideal para operación real, varias estaciones y sync** (CENTRAL)

---

## Kit para el distribuidor (guión de 15 minutos)

1. **Minuto 0-2 · Contexto:** ¿Cuántos camiones pesa al día? ¿Cómo registra hoy entrada, salida y ticket?
2. **Minuto 2-5 · Entrada:** Cree un boleto con placa, producto y peso en vivo. ¿Lleva inventario por almacén o por producto?
3. **Minuto 5-8 · Salida y neto:** Cierre el ciclo y muestre el cálculo. ¿Cuántas personas operan y quién administra?
4. **Minuto 8-11 · Ticket:** Genere el PDF, muestre la vista previa. ¿Tiene internet estable en la caseta?
5. **Minuto 11-13 · Kardex y reporte:** Enseñe el movimiento y exporte el día. ¿Recibe auditorías o clientes que exigen evidencia?
6. **Minuto 13-15 · Auditoría y cierre:** Muestre el registro y proponga el piloto. ¿Qué reporte pide gerencia cada mes? ¿Cuál es el costo de un error de peso o de un boleto perdido?

**Manejo de objeciones:**
- "Ya tengo una báscula." → BALANSOFT-WS se integra con su indicador; no tiene que cambiar el equipo
- "No tengo internet en la caseta." → La estación trabaja local y sincroniza cuando haya enlace
- "Es caro." → Compárelo con el costo de un boleto perdido, una diferencia de inventario o una auditoría sin evidencia
- "Mi gente no sabe de sistemas." → La pantalla está pensada para operación: elegir, capturar, imprimir. Incluye guía de bienvenida y capacitación
- "¿Y si se cae la computadora?" → Hay respaldo automático, respaldo manual y restauración con respaldo de seguridad previo
- "¿Puedo empezar pequeño?" → Sí. DEMO permite probar con un equipo y todos los módulos; luego se pasa a CENTRAL sin reinstalar

---

## Datos clave

- **Versión:** 0.4.2-dev.56 | **Fecha:** Octubre 2026
- **Idiomas:** Español · Inglés · Portugués
- **Formatos de ticket:** Rollos 80 mm, rollos 58 mm, media carta, carta, A4; PDF y TXT
- **Hardware compatible:** Toledo, Yaohua, Rice Lake, Torrey, Keli, Excel y más (parser multi-marca)
- **Base de datos:** PostgreSQL (o SQL Server Fase 1 modo degradado)
- **Licencias:** DEMO (hasta 10 boletos, 3 sesiones) → CENTRAL (ilimitado, sujeto a licencia)
- **Despliegue:** WServer binario PyInstaller; estación titular con PostgreSQL local; estaciones operadoras en LAN

---

*Documento comercial preparado para distribuidores y canales de venta autorizados de BALANSOFT. Las funcionalidades, límites y especificaciones corresponden a la versión 0.4.2-dev.56 y pueden variar según la licencia, la configuración de la estación y el hardware del cliente. Las marcas de básculas e impresoras mencionadas pertenecen a sus respectivos titulares y se citan solo como referencia de compatibilidad. Este documento no constituye una oferta contractual; la propuesta económica y el alcance definitivo se formalizan por escrito con el distribuidor autorizado.*

BALANSOFT-WS · Dossier de producto v3.28 · Octubre 2026
from reportlab.lib.pagesizes import half_letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.lib import colors

# Use BALANSOFT-WS project colors
# Primary: #1a3a5c (dark blue)
# Accent: #2c5f8a (lighter blue)
# Background: #f0f4f8 (light gray for body)
# Text: #1a3a5c (dark for readability)

output_path = 'docs/BROCHURE.pdf'

doc = SimpleDocTemplate(
    output_path,
    pagesize=half_letter,
    rightMargin=0.6*inch,
    leftMargin=0.6*inch,
    topMargin=0.6*inch,
    bottomMargin=0.6*inch
)

styles = getSampleStyleSheet()
story = []

# Color definitions
PRIMARY_COLOR = colors.HexColor('#1a3a5c')
ACCENT_COLOR = colors.HexColor('#2c5f8a')
LIGHT_BG = colors.HexColor('#f5f5f5')
DARK_TEXT = colors.HexColor('#1a3a5c')
MEDIUM_TEXT = colors.HexColor('#333333')
WHITE = colors.white

# Title page styling
story.append(Spacer(1, 1.5*inch))

# Main title with primary color
title_text = Paragraph('BALANSOFT-WS', ParagraphStyle(
    'Title', parent=styles['Title'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=28))
story.append(title_text)

subtitle_text = Paragraph('Brochure Comercial', ParagraphStyle(
    'Subtitle', parent=styles['Subtitle'],
    textColor=ACCENT_COLOR, fontName='Helvetica', fontSize=16))
story.append(subtitle_text)

story.append(Spacer(1, 0.3*inch))

# Version line
version_text = Paragraph('Sistema estación pesaje industrial multi-empresa', ParagraphStyle(
    'Version', parent=styles['Normal'],
    textColor=MEDIUM_TEXT, fontName='Helvetica', fontSize=10))
story.append(version_text)

version_text2 = Paragraph('FastAPI + Flutter + WServer (PyInstaller) + HAL básculas', ParagraphStyle(
    'Version2', parent=styles['Normal'],
    textColor=MEDIUM_TEXT, fontName='Helvetica', fontSize=10))
story.append(version_text2)

version_text3 = Paragraph('Versión: 0.4.2-dev.56 | Idioma: español', ParagraphStyle(
    'Version3', parent=styles['Normal'],
    textColor=MEDIUM_TEXT, fontName='Helvetica', fontSize=10))
story.append(version_text3)

story.append(Spacer(1, 0.5*inch))

# Horizontal line with primary color
line = Table([[None]], colWidths=[4*inch])
line.setStyle(TableStyle([
    ('LINEBELOW', (0, 0), (-1, -1), 2, PRIMARY_COLOR),
    ('TOPPADDING', (0, 0), (-1, -1), 0),
    ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
]))
story.append(line)

story.append(Spacer(1, 0.5*inch))

# --- Sección: ¿Por qué BALANSOFT-WS? ---
story.append(Paragraph('¿Por qué BALANSOFT-WS?', ParagraphStyle(
    'SectionHeading', parent=styles['Heading2'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=14)))

story.append(Paragraph(
    'El cliente no compra un lector de báscula: compra <b>tranquilidad</b> para cerrar el mes, responder a una auditoría y saber qué pasó con cada camión.',
    ParagraphStyle('Body', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    'Menos errores, más control y <b>costo operativo reducido</b>. El sistema resuelve estos dolores:',
    ParagraphStyle('Body2', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))

dolores = [
    '❌ Pesajes anotados a mano que se pierden o se repiten',
    '❌ Inventario que no cuadra por salidas no registradas a tiempo',
    '❌ Reportes armados al final del mes, con errores y tarde',
    '❌ Discusiones sin evidencia: no se sabe quién pesó, cuándo ni con qué báscula',
    '❌ Operación detenida cuando falla internet'
]
for d in dolores:
    story.append(Paragraph(d, ParagraphStyle('Dolor', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))

story.append(Paragraph(
    '✓ Un boleto único, numerado y trazable por cada entrada y salida',
    ParagraphStyle('Benefit', parent=styles['Normal'], textColor=colors.HexColor('#27ae60'), fontName='Helvetica-Bold', fontSize=9)))
story.append(Paragraph(
    '✓ Kardex automático: cada pesaje mueve el inventario del almacén',
    ParagraphStyle('Benefit2', parent=styles['Normal'], textColor=colors.HexColor('#27ae60'), fontName='Helvetica-Bold', fontSize=9)))
story.append(Paragraph(
    '✓ Reportes diarios, mensuales y comparativos listos para exportar',
    ParagraphStyle('Benefit3', parent=styles['Normal'], textColor=colors.HexColor('#27ae60'), fontName='Helvetica-Bold', fontSize=9)))
story.append(Paragraph(
    '✓ Trazabilidad completa: usuario, IP, fecha UTC, ediciones y anulaciones con evidencia',
    ParagraphStyle('Benefit4', parent=styles['Normal'], textColor=colors.HexColor('#27ae60'), fontName='Helvetica-Bold', fontSize=9)))
story.append(Paragraph(
    '✓ Operación local que sigue funcionando sin conexión a internet',
    ParagraphStyle('Benefit5', parent=styles['Normal'], textColor=colors.HexColor('#27ae60'), fontName='Helvetica-Bold', fontSize=9)))
story.append(Spacer(1, 0.3*inch))

# --- Sección: 10 Bondades que venden solas ---
story.append(Paragraph('10 Bondades que venden solas', ParagraphStyle(
    'SectionHeading', parent=styles['Heading2'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=14)))

story.append(Paragraph(
    'Cada bondad responde a un dolor concreto de la operación. Úselas como argumentos de conversación, no como lista de características.',
    ParagraphStyle('Body', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))

# Table with bondades using project colors
data = [
    ['#', 'Bondad', 'Beneficio'],
    ['1', 'Opera sin internet', 'La estación trabaja contra su base de datos local; si se cae la red, el pesaje continúa y la sincronización se reanuda después'],
    ['2', 'Un solo sistema de punta a punta', 'Catálogos, pesaje, inventario, ticket, reportes y auditoría en el mismo lugar; menos planillas, menos reprocesos, menos errores'],
    ['3', 'Habla con básculas reales', 'Serial RS-232/USB y TCP/IP, con parser multi-marca (Toledo/GSI, Yaohua, Keli, Torrey, Rice Lake, más)'],
    ['4', 'El ticket sale como debe salir', 'Rollos 58/80 mm, media carta, carta y A4; PDF o TXT; vista idéntica a la preview'],
    ['5', 'Trazabilidad metrológica', 'El peso capturado no se edita; cada boleto guarda báscula, modo de captura, usuario, fecha UTC y estabilidad'],
    ['6', 'Kardex automático', 'Movimiento 10 = Ingreso (+), Movimiento 60 = Despacho (−); anulación registra el contra-asiento exacto'],
    ['7', 'Reportes para decidir', 'Diario, mensual, por vehículo, transportista, tercero, rango de peso, comparativo mensual y Kardex; exportables a Excel y PDF'],
    ['8', 'Seguridad por roles', 'Matriz de permisos por módulo (ADMIN/OPERADOR/AUDITOR); cada empresa configura su matriz'],
    ['9', 'Crece con la operación', 'DEMO (hasta 10 boletos, 3 sesiones) → CENTRAL (estaciones ilimitadas, sincronización) sin reinstalar'],
    ['10', 'Implementación rápida', 'Puesta en marcha en 1–3 días; acompañamiento en capacitación y checklist de aceptación'],
]

t = Table(data, colWidths=[0.3*inch, 1.8*inch, 2.5*inch])
# Style the table with project colors
t.setStyle(TableStyle([
    # Header row
    ('BACKGROUND', (0, 0), (-1, 0), PRIMARY_COLOR),
    ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
    ('FONTSIZE', (0, 0), (-1, 0), 8),
    ('BOTTOMPADDING', (0, 0), (-1, 0), 4),
    ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
    # Data rows
    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, LIGHT_BG]),
    # Alternate row shading
    ('TEXTCOLOR', (0, 1), (-1, -1), DARK_TEXT),
    ('FONTSIZE', (0, 1), (-1, -1), 8),
]))
story.append(t)
story.append(Spacer(1, 0.3*inch))

# --- Arquitectura en una mirada ---
story.append(Paragraph('Arquitectura en una mirada', ParagraphStyle(
    'SectionHeading', parent=styles['Heading2'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=14)))

story.append(Paragraph(
    '• <b>Dos roles:</b> <font color="#1a3a5c">APP_ROLE=local</font> (estación operativa) o <font color="#1a3a5c">server</font> (central de cuenta/licencia/sync/panel)',
    ParagraphStyle('Body', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>Motor BD por prefijo:</b> <font color="#1a3a5c">postgresql…</font> o <font color="#1a3a5c">mssql…</font>; sin nuevas env vars',
    ParagraphStyle('Body2', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>Sin Alembic:</b> migraciones hand-made <font color="#1a3a5c">src/backend/migrations/*.sql</font> (001–025), idempotentes, aplicadas por WServer al arrancar',
    ParagraphStyle('Body3', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>WServer:</b> binario PyInstaller one-file; 1ª instala genera <font color="#1a3a5c">.env</font> desde <font color="#1a3a5c">.env.plantilla</font> (SECRET_KEY aleatoria) y aplica migraciones',
    ParagraphStyle('Body4', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>Licencia:</b> estación no gatea por <font color="#1a3a5c">features</font>/<font color="#1a3a5c">plan_type</font>. Tope local: <font color="#1a3a5c">limite_sesiones_por_tier()</font> → DEMO = 3, resto <font color="#1a3a5c">None</font>; tope real lo pone <font color="#1a3a5c">licencias.max_sesiones</font> del central',
    ParagraphStyle('Body5', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>Llaves de activación:</b> <font color="#1a3a5c">POST /api/v1/activacion/llaves</font> → BS-XXXX-XXXX-XXXX (SHA-256, expira 1 h–90 días, default 7)',
    ParagraphStyle('Body6', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>Series numeración:</b> <font color="#1a3a5c">SELECT … FOR UPDATE</font> por empresa, contador transaccional; <font color="#1a3a5c">DELETE</font> de una serie usada responde <font color="#1a3a5c">409</font>',
    ParagraphStyle('Body7', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>Multi-tenencia obligatoria:</b> <font color="#1a3a5c">id_empresa</font> en <font color="#1a3a5c">toda</font> consulta, filtro, inserción o validación; ninguna métrica Prometheus ni log público lo exponga',
    ParagraphStyle('Body8', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>i18n:</b> <font color="#1a3a5c">139 claves × es/en/pt</font> en backend; <font color="#1a3a5c">848 × es/en/pt</font> en frontend; idioma vía <font color="#1a3a5c">?idioma=</font> / <font color="#1a3a5c">Accept-Language</font>',
    ParagraphStyle('Body9', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '• <b>Paridad ticket:</b> layout canónico en Flutter (<font color="#1a3a5c">ticket_preview_dialog.dart</font>); backend debe reflejarse exactamente (tabla 5 columnas v3.24)',
    ParagraphStyle('Body10', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Spacer(1, 0.3*inch))

# --- Casos de uso por sector ---
story.append(Paragraph('Casos de uso por sector', ParagraphStyle(
    'SectionHeading', parent=styles['Heading2'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=14)))

data2 = [
    ['Sector', 'Dolor típico', 'Cómo responde BALANSOFT-WS'],
    ['Agroindustria', 'Recepción de materia prima con planillas y demoras', 'Pesaje rápido, ticket y Kardex de ingreso automático'],
    ['Molinos y balanceados', 'Inventario que no cuadra con las salidas', 'Movimiento 60 por despacho y reportes por producto'],
    ['Puertos y terminales', 'Alto volumen y necesidad de evidencia', 'Multiestación, auditoría y reportes por transportista'],
    ['Cemento y áridos', 'Control de sobrecarga y despacho', 'Capacidad máxima, peso en vivo y ticket con neto'],
    ['Reciclaje', 'Compras a terceros y trazabilidad', 'Terceros, productos, Kardex y reportes por proveedor'],
    ['Químicos y fertilizantes', 'Densidad, litros y unidades', 'Datos adicionales y conversiones por producto'],
    ['Alimentos y bebidas', 'Control de recepción y despacho', 'Entrada/salida, fotos y auditoría de cambios'],
    ['Transporte de carga', 'Viajes y toneladas por placa', 'Reporte por vehículo y por transportista'],
]

t2 = Table(data2, colWidths=[1.3*inch, 2.0*inch, 1.5*inch])
t2.setStyle(TableStyle([
    ('BACKGROUND', (0, 0), (-1, 0), PRIMARY_COLOR),
    ('TEXTCOLOR', (0, 0), (-1, 0), WHITE),
    ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
    ('FONTSIZE', (0, 0), (-1, 0), 8),
    ('BOTTOMPADDING', (0, 0), (-1, 0), 4),
    ('GRID', (0, 0), (-1, -1), 0.5, colors.black),
    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [WHITE, LIGHT_BG]),
    ('TEXTCOLOR', (0, 1), (-1, -1), DARK_TEXT),
    ('FONTSIZE', (0, 1), (-1, -1), 8),
]))
story.append(t2)
story.append(Spacer(1, 0.3*inch))

# --- Ruta de crecimiento ---
story.append(Paragraph('Ruta de crecimiento', ParagraphStyle(
    'SectionHeading', parent=styles['Heading2'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=14)))

story.append(Paragraph(
    '<b>Demo → Piloto → Central → Expansión</b>',
    ParagraphStyle('Body', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    'Un equipo, 10 boletos, todos los módulos → Operación real controlada → Todos los módulos, sin recortes → Más plantas y equipos, más sincronización',
    ParagraphStyle('Body2', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Spacer(1, 0.3*inch))

# --- Kit para el distribuidor ---
story.append(Paragraph('Kit para el distribuidor (guión de 15 minutos)', ParagraphStyle(
    'SectionHeading', parent=styles['Heading2'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=14)))

story.append(Paragraph(
    '1. <b>Minuto 0-2 · Contexto:</b> ¿Cuántos camiones pesa al día? ¿Cómo registra hoy entrada, salida y ticket?',
    ParagraphStyle('Bullet', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '2. <b>Minuto 2-5 · Entrada:</b> Cree un boleto con placa, producto y peso en vivo. ¿Lleva inventario por almacén o por producto?',
    ParagraphStyle('Bullet2', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '3. <b>Minuto 5-8 · Salida y neto:</b> Cierre el ciclo y muestre el cálculo. ¿Cuántas personas operan y quién administra?',
    ParagraphStyle('Bullet3', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '4. <b>Minuto 8-11 · Ticket:</b> Genere el PDF, muestre la vista previa. ¿Tiene internet estable en la caseta?',
    ParagraphStyle('Bullet4', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '5. <b>Minuto 11-13 · Kardex y reporte:</b> Enseñe el movimiento y exporte el día. ¿Recibe auditorías o clientes que exijan evidencia?',
    ParagraphStyle('Bullet5', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '6. <b>Minuto 13-15 · Auditoría y cierre:</b> Muestre el registro y proponga el piloto. ¿Qué reporte pide gerencia cada mes? ¿Cuál es el costo de un error de peso o de un boleto perdido?',
    ParagraphStyle('Bullet6', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))

story.append(Paragraph('<b>Manejo de objeciones:</b>',
    ParagraphStyle('SubBullet', parent=styles['Normal'], textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=9)))
story.append(Paragraph(
    '- "Ya tengo una báscula." → BALANSOFT-WS se integra con su indicador; no tiene que cambiar el equipo',
    ParagraphStyle('Obs', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '- "No tengo internet en la caseta." → La estación trabaja local y sincroniza cuando haya enlace',
    ParagraphStyle('Obs2', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '- "Es caro." → Compárelo con el costo de un boleto perdido, una diferencia de inventario o una auditoría sin evidencia',
    ParagraphStyle('Obs3', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '- "Mi gente no sabe de sistemas." → La pantalla está pensada para operación: elegir, capturar, imprimir. Incluye guía de bienvenida y capacitación',
    ParagraphStyle('Obs4', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '- "¿Y si se cae la computadora?" → Hay respaldo automático, respaldo manual y restauración con respaldo de seguridad previo',
    ParagraphStyle('Obs5', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Paragraph(
    '- "¿Puedo empezar pequeño?" → Sí. DEMO permite probar con un equipo y todos los módulos; luego se pasa a CENTRAL sin reinstalar',
    ParagraphStyle('Obs6', parent=styles['Normal'], textColor=DARK_TEXT, fontName='Helvetica', fontSize=9)))
story.append(Spacer(1, 0.3*inch))

# --- Datos clave ---
story.append(Paragraph('Datos clave', ParagraphStyle(
    'SectionHeading', parent=styles['Heading2'],
    textColor=PRIMARY_COLOR, fontName='Helvetica-Bold', fontSize=14)))

data3 = [
    ['Versión', '0.4.2-dev.56'],
    ['Fecha', 'Octubre 2026'],
    ['Idiomas', 'Español · Inglés · Portugués'],
    ['Formatos de ticket', 'Rollos 80 mm, rollos 58 mm, media carta, carta, A4; PDF y TXT'],
    ['Hardware compatible', 'Toledo, Yaohua, Rice Lake, Torrey, Keli, Excel y más (parser multi-marca)'],
    ['Base de datos', 'PostgreSQL (o SQL Server Fase 1 modo degradado)'],
    ['Licencias', 'DEMO (hasta 10 boletos, 3 sesiones) → CENTRAL (ilimitado, sujeto a licencia)'],
    ['Despliegue', 'WServer binario PyInstaller; estación titular con PostgreSQL local; estaciones operadoras en LAN'],
]

t3 = Table(data3, colWidths=[1.6*inch, 3.2*inch])
t3.setStyle(TableStyle([
    ('FONTNAME', (0, 0), (0, -1), 'Helvetica-Bold'),
    ('FONTSIZE', (0, 0), (-1, -1), 9),
    ('GRID', (0, 0), (-1, -1), 0.5, PRIMARY_COLOR),
    ('BACKGROUND', (0, 0), (0, -1), LIGHT_BG),
]))
story.append(t3)

# Build the PDF
doc.build(story)
print(f'PDF creado en: {output_path}')
print('Colores utilizados: PRIMARY_COLOR=#1a3a5c, LIGHT_BG=#f5f5f5, DARK_TEXT=#1a3a5c')
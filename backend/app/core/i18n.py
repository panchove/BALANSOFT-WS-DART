"""Módulo de internacionalización (i18n) para tickets y reportes en Backend."""

from __future__ import annotations

from fastapi import Request

IDIOMAS: tuple[str, ...] = ("es", "en", "pt")
IDIOMA_DEFAULT = "es"

TRANSLATIONS: dict[str, dict[str, str]] = {
    "es": {
        # Ticket
        "titulo_boleto": "BOLETO DE PESAJE DE BALANSOFT",
        "doc_anulado": "DOCUMENTO ANULADO",
        "doc_anulado_banner": "*** DOCUMENTO ANULADO ***",
        "motivo": "Motivo",
        "no_especificado": "No especificado",
        "lectura_pesos": "LECTURA DE PESOS",
        "datos_adicionales": "DATOS ADICIONALES",
        "observaciones": "OBSERVACIONES",
        "peso_neto": "PESO NETO",
        "peso_declarado": "PESO DECLARADO",
        "peso_declarado_diferencia": "PESO DECLARADO / DIFERENCIA",
        "diferencia": "DIFERENCIA",
        "desviacion": "DESVIACIÓN",
        "fecha_hora": "Fecha/Hora",
        "peso_camion": "Peso Camion",
        "peso_remolque": "Peso Remolque",
        "peso_total": "Peso Total",
        "balanza_entrada": "Balanza Entrada",
        "balanza_salida": "Balanza Salida",
        "fecha_entrada": "Fecha/Hora Entrada",
        "fecha_salida": "Fecha/Hora Salida",
        "vehiculo": "Vehículo",
        "camion": "Camión",
        "remolque": "Remolque",
        "conductor": "Conductor",
        "transporte": "Transporte",
        "producto": "Producto",
        "almacen": "Almacén",
        "cliente_proveedor": "Cliente/Proveedor",
        "razon_social": "Razón Social",
        "seleccion": "Selección",
        "serie_boleto": "Serie - Boleto",
        "tipo_tercero": "Tipo",
        "camion_color": "Color Camión",
        "peso_manual": "PESO MANUAL",
        "operador": "Operador",
        # Catálogos y control del ticket AVANZADO
        "datos_catalogo": "DATOS DEL CATÁLOGO Y CONTROL",
        "categoria": "Categoría",
        "unidad": "Unidad",
        "telefono": "Teléfono",
        "licencia": "Licencia",
        "cedula": "Cédula",
        "rif": "RIF",
        "capacidad": "Capacidad",
        "division": "División",
        "tara": "Tara",
        "tipo_remolque": "Tipo Remolque",
        "sincronizado": "Sincronizado",
        "kardex": "Kardex",
        "empresa": "Empresa",
        "balanza": "Balanza",
        "sincronizado_si": "Sí",
        "sincronizado_no": "No",
        "documento": "Documento",
        "densidad": "Densidad",
        "volumen": "Volumen",
        "unidades": "Unidades",
        "firma_conductor": "Firma Conductor",
        "firma_operador": "Firma Operador",
        "ingreso": "INGRESO",
        "despacho": "DESPACHO",
        "estado": "Estado",
        "impreso": "Impreso",
        # Reportes Excel / PDF
        "reporte_pesajes": "REPORTE DE PESAJES",
        "reporte_pesajes_vehiculos": "REPORTE DE PESAJE DE VEHÍCULOS",
        "reporte_kardex": "REPORTE DE MOVIMIENTOS DE KARDEX",
        "kardex_inventario": "KARDEX DE INVENTARIO",
        "periodo": "Período",
        "al": "al",
        "total": "Total",
        "pesajes": "pesajes",
        "movimientos": "movimientos",
        "saldo_inicial": "Saldo Inicial",
        "saldo_final": "Saldo Final",
        "saldo_actual": "Saldo Actual",
        "total_pesajes": "Total Pesajes",
        "cerrados": "Cerrados",
        "abiertos": "Abiertos",
        "peso_neto_total": "Peso Neto Total (kg)",
        "peso_bruto": "Peso Bruto",
        "peso_tara": "Peso Tara",
        "codigo": "Código",
        "valor": "Valor",
        "stock": "Stock",
        "referencia": "Referencia",
        "col_boleto": "Boleto",
        "col_fecha": "Fecha / Hora",
        "col_fecha_corta": "Fecha",
        "col_vehiculo": "Vehículo",
        "col_conductor": "Conductor",
        "col_producto": "Producto",
        "col_almacen": "Almacén",
        "col_neto": "Neto (kg)",
        "col_estado": "Estado",
        "col_documento": "Documento",
        "col_movimiento": "Movimiento",
        "col_entrada": "Entrada",
        "col_salida": "Salida",
        "col_saldo": "Saldo",
        # Rótulos institucionales y valores por defecto
        "etiqueta_rif": "RIF",
        "etiqueta_telefono": "Tel.",
        "etiqueta_direccion": "Dirección",
        "etiqueta_email": "Email",
        "pagina": "Página",
        "sistema": "Sistema",
        "sistema_pesaje": "Sistema de Pesaje",
        "sin_datos": "Sin datos",
        "si": "Sí",
        "no": "No",
        "sin_placa": "Sin Placa",
        "boleto_sin_numero": "Boleto s/n",
        "na": "N/A",
        "solo_admin_edita_empresa": "Solo el ADMIN puede editar el perfil de la empresa.",
        "rif_nit_ya_registrado": "El RIF/NIT ya está registrado en otra empresa.",
        "estado_pendiente": "PENDIENTE",
        "estado_cerrado": "CERRADO",
        "estado_modificado": "MODIFICADO",
        "estado_anulado": "ANULADO",
    },
    "en": {
        # Ticket
        "titulo_boleto": "BALANSOFT WEIGHING TICKET",
        "doc_anulado": "VOIDED DOCUMENT",
        "doc_anulado_banner": "*** VOIDED DOCUMENT ***",
        "motivo": "Reason",
        "no_especificado": "Not specified",
        "lectura_pesos": "WEIGHT READINGS",
        "datos_adicionales": "ADDITIONAL DATA",
        "observaciones": "NOTES / OBSERVATIONS",
        "peso_neto": "NET WEIGHT",
        "peso_declarado": "DECLARED WEIGHT",
        "peso_declarado_diferencia": "DECLARED WEIGHT / DIFFERENCE",
        "diferencia": "DIFFERENCE",
        "desviacion": "DEVIATION",
        "fecha_hora": "Date/Time",
        "peso_camion": "Truck Weight",
        "peso_remolque": "Trailer Weight",
        "peso_total": "Total Weight",
        "balanza_entrada": "Entry Scale",
        "balanza_salida": "Exit Scale",
        "fecha_entrada": "Entry Date/Time",
        "fecha_salida": "Exit Date/Time",
        "vehiculo": "Vehicle",
        "camion": "Truck",
        "remolque": "Trailer",
        "conductor": "Driver",
        "transporte": "Transport",
        "producto": "Product",
        "almacen": "Warehouse",
        "cliente_proveedor": "Customer / Supplier",
        "razon_social": "Company Name",
        "seleccion": "Selection",
        "serie_boleto": "Series - Ticket",
        "tipo_tercero": "Type",
        "camion_color": "Truck Color",
        "peso_manual": "MANUAL WEIGHT",
        "operador": "Operator",
        "datos_catalogo": "CATALOG & CONTROL DATA",
        "categoria": "Category",
        "unidad": "Unit",
        "telefono": "Phone",
        "licencia": "License",
        "cedula": "ID",
        "rif": "Tax ID",
        "capacidad": "Capacity",
        "division": "Division",
        "tara": "Tare",
        "tipo_remolque": "Trailer Type",
        "sincronizado": "Synced",
        "kardex": "Kardex",
        "empresa": "Company",
        "balanza": "Scale",
        "sincronizado_si": "Yes",
        "sincronizado_no": "No",
        "documento": "Document",
        "densidad": "Density",
        "volumen": "Volume",
        "unidades": "Units",
        "firma_conductor": "Driver Signature",
        "firma_operador": "Operator Signature",
        "ingreso": "INBOUND",
        "despacho": "OUTBOUND",
        "estado": "Status",
        "impreso": "Printed",
        # Reports
        "reporte_pesajes": "WEIGHING REPORT",
        "reporte_pesajes_vehiculos": "VEHICLE WEIGHING REPORT",
        "reporte_kardex": "KARDEX MOVEMENTS REPORT",
        "kardex_inventario": "INVENTORY KARDEX",
        "periodo": "Period",
        "al": "to",
        "total": "Total",
        "pesajes": "weighings",
        "movimientos": "movements",
        "saldo_inicial": "Initial Balance",
        "saldo_final": "Final Balance",
        "saldo_actual": "Current Balance",
        "total_pesajes": "Total Weighings",
        "cerrados": "Closed",
        "abiertos": "Open",
        "peso_neto_total": "Total Net Weight (kg)",
        "peso_bruto": "Gross Weight",
        "peso_tara": "Tare Weight",
        "codigo": "Code",
        "valor": "Value",
        "stock": "Stock",
        "referencia": "Reference",
        "col_boleto": "Ticket",
        "col_fecha": "Date / Time",
        "col_fecha_corta": "Date",
        "col_vehiculo": "Vehicle",
        "col_conductor": "Driver",
        "col_producto": "Product",
        "col_almacen": "Warehouse",
        "col_neto": "Net (kg)",
        "col_estado": "Status",
        "col_documento": "Document",
        "col_movimiento": "Movement",
        "col_entrada": "Inbound",
        "col_salida": "Outbound",
        "col_saldo": "Balance",
        # Rótulos institucionales y valores por defecto
        "etiqueta_rif": "Tax ID",
        "etiqueta_telefono": "Phone",
        "etiqueta_direccion": "Address",
        "etiqueta_email": "Email",
        "pagina": "Page",
        "sistema": "System",
        "sistema_pesaje": "Weighing System",
        "sin_datos": "No data",
        "si": "Yes",
        "no": "No",
        "sin_placa": "No Plate",
        "boleto_sin_numero": "Ticket n/a",
        "na": "N/A",
        "solo_admin_edita_empresa": "Only the ADMIN can edit the company profile.",
        "rif_nit_ya_registrado": "This tax ID is already registered for another company.",
        "estado_pendiente": "PENDING",
        "estado_cerrado": "CLOSED",
        "estado_modificado": "MODIFIED",
        "estado_anulado": "VOIDED",
    },
    "pt": {
        # Ticket
        "titulo_boleto": "BILHETE DE PESAGEM BALANSOFT",
        "doc_anulado": "DOCUMENTO ANULADO",
        "doc_anulado_banner": "*** DOCUMENTO ANULADO ***",
        "motivo": "Motivo",
        "no_especificado": "Não especificado",
        "lectura_pesos": "LEITURA DE PESOS",
        "datos_adicionales": "DADOS ADICIONAIS",
        "observaciones": "OBSERVAÇÕES",
        "peso_neto": "PESO LÍQUIDO",
        "peso_declarado": "PESO DECLARADO",
        "peso_declarado_diferencia": "PESO DECLARADO / DIFERENÇA",
        "diferencia": "DIFERENÇA",
        "desviacion": "DESVIO",
        "fecha_hora": "Data/Hora",
        "peso_camion": "Peso Caminhão",
        "peso_remolque": "Peso Reboque",
        "peso_total": "Peso Total",
        "balanza_entrada": "Balança Entrada",
        "balanza_salida": "Balança Saída",
        "fecha_entrada": "Data/Hora Entrada",
        "fecha_salida": "Data/Hora Saída",
        "vehiculo": "Veículo",
        "camion": "Caminhão",
        "remolque": "Reboque",
        "conductor": "Motorista",
        "transporte": "Transporte",
        "producto": "Produto",
        "almacen": "Armazém",
        "cliente_proveedor": "Cliente / Fornecedor",
        "razon_social": "Razão Social",
        "seleccion": "Seleção",
        "serie_boleto": "Série - Bilhete",
        "tipo_tercero": "Tipo",
        "camion_color": "Cor do Caminhão",
        "peso_manual": "PESO MANUAL",
        "operador": "Operador",
        "datos_catalogo": "DADOS DO CATÁLOGO E CONTROLE",
        "categoria": "Categoria",
        "unidad": "Unidade",
        "telefono": "Telefone",
        "licencia": "Licença",
        "cedula": "RG/CPF",
        "rif": "CNPJ/RIF",
        "capacidad": "Capacidade",
        "division": "Divisão",
        "tara": "Tara",
        "tipo_remolque": "Tipo Reboque",
        "sincronizado": "Sincronizado",
        "kardex": "Kardex",
        "empresa": "Empresa",
        "balanza": "Balança",
        "sincronizado_si": "Sim",
        "sincronizado_no": "Não",
        "documento": "Documento",
        "densidad": "Densidade",
        "volumen": "Volume",
        "unidades": "Unidades",
        "firma_conductor": "Assinatura do Motorista",
        "firma_operador": "Assinatura do Operador",
        "ingreso": "ENTRADA",
        "despacho": "SAÍDA",
        "estado": "Status",
        "impreso": "Impresso",
        # Reports
        "reporte_pesajes": "RELATÓRIO DE PESAGENS",
        "reporte_pesajes_vehiculos": "RELATÓRIO DE PESAGEM DE VEÍCULOS",
        "reporte_kardex": "RELATÓRIO DE MOVIMENTOS DE KARDEX",
        "kardex_inventario": "KARDEX DE ESTOQUE",
        "periodo": "Período",
        "al": "a",
        "total": "Total",
        "pesajes": "pesagens",
        "movimientos": "movimentos",
        "saldo_inicial": "Saldo Inicial",
        "saldo_final": "Saldo Final",
        "saldo_actual": "Saldo Atual",
        "total_pesajes": "Total de Pesagens",
        "cerrados": "Fechados",
        "abiertos": "Abertos",
        "peso_neto_total": "Peso Líquido Total (kg)",
        "peso_bruto": "Peso Bruto",
        "peso_tara": "Peso Tara",
        "codigo": "Código",
        "valor": "Valor",
        "stock": "Estoque",
        "referencia": "Referência",
        "col_boleto": "Bilhete",
        "col_fecha": "Data / Hora",
        "col_fecha_corta": "Data",
        "col_vehiculo": "Veículo",
        "col_conductor": "Motorista",
        "col_producto": "Produto",
        "col_almacen": "Armazém",
        "col_neto": "Líquido (kg)",
        "col_estado": "Status",
        "col_documento": "Documento",
        "col_movimiento": "Movimento",
        "col_entrada": "Entrada",
        "col_salida": "Saída",
        "col_saldo": "Saldo",
        # Rótulos institucionais e valores padrão
        "etiqueta_rif": "RIF",
        "etiqueta_telefono": "Tel.",
        "etiqueta_direccion": "Endereço",
        "etiqueta_email": "E-mail",
        "pagina": "Página",
        "sistema": "Sistema",
        "sistema_pesaje": "Sistema de Pesagem",
        "sin_datos": "Sem dados",
        "si": "Sim",
        "no": "Não",
        "sin_placa": "Sem Placa",
        "boleto_sin_numero": "Bilhete s/n",
        "na": "N/A",
        "solo_admin_edita_empresa": "Somente o ADMIN pode editar o perfil da empresa.",
        "rif_nit_ya_registrado": "Este RIF/NIT já está cadastrado para outra empresa.",
        "estado_pendiente": "PENDENTE",
        "estado_cerrado": "FECHADO",
        "estado_modificado": "MODIFICADO",
        "estado_anulado": "ANULADO",
    },
}


def t(key: str, lang: str = IDIOMA_DEFAULT) -> str:
    """Devuelve la traducción para una clave dada según el idioma (es, en, pt)."""
    normalized = normalizar_idioma(lang) or IDIOMA_DEFAULT
    lang_dict = TRANSLATIONS.get(normalized, TRANSLATIONS[IDIOMA_DEFAULT])
    return lang_dict.get(key, TRANSLATIONS[IDIOMA_DEFAULT].get(key, key))


def normalizar_idioma(valor: str | None) -> str | None:
    """Normaliza un tag de idioma ('pt-BR', 'en_US', 'ES') a 'es'|'en'|'pt'.

    Devuelve ``None`` si no corresponde a un idioma soportado.
    """
    if not valor:
        return None
    base = valor.strip().lower().replace("_", "-").split("-")[0]
    return base if base in IDIOMAS else None


def _q_de_accept_language(cabecera: str) -> list[tuple[str, float]]:
    """Extrae (idioma, calidad) de una cabecera ``Accept-Language``.

    Acepta el formato real de los navegadores (``pt-BR,pt;q=0.9,en;q=0.8``)
    en lugar de buscar subcadenas, que hacía que cualquier ``en`` ganara
    sobre ``pt``.
    """
    candidatos: list[tuple[str, float]] = []
    for parte in cabecera.split(","):
        tag, _, params = parte.strip().partition(";")
        idioma = normalizar_idioma(tag)
        if idioma is None:
            continue
        calidad = 1.0
        for param in params.split(";"):
            clave, _, valor = param.strip().partition("=")
            if clave.strip().lower() == "q":
                try:
                    calidad = float(valor)
                except ValueError:
                    calidad = 0.0
        if calidad > 0:
            candidatos.append((idioma, calidad))
    return candidatos


def idioma_de_accept_language(cabecera: str | None) -> str | None:
    """Devuelve el idioma preferido de una cabecera ``Accept-Language``."""
    if not cabecera:
        return None
    candidatos = _q_de_accept_language(cabecera)
    if not candidatos:
        return None
    mejor_calidad = max(calidad for _, calidad in candidatos)
    for idioma, calidad in candidatos:
        if calidad == mejor_calidad:
            return idioma
    return candidatos[0][0]


def idioma_del_servidor() -> str:
    """Idioma por defecto configurado en el servidor (``.env``: IDIOMA_DEFAULT)."""
    from app.core.config import settings

    return normalizar_idioma(settings.idioma_default) or IDIOMA_DEFAULT


def resolve_lang(
    request: Request | None,
    param_lang: str | None = None,
    defecto: str | None = None,
) -> str:
    """Resuelve el idioma de la petición.

    Precedencia: parámetro de query > ``Accept-Language`` > ``defecto``
    (normalmente ``empresas.idioma``) > ``IDIOMA_DEFAULT`` del servidor.
    """
    for candidato in (param_lang, _idioma_de_query(request)):
        idioma = normalizar_idioma(candidato)
        if idioma:
            return idioma
    if request is not None:
        idioma = idioma_de_accept_language(request.headers.get("accept-language"))
        if idioma:
            return idioma
    return normalizar_idioma(defecto) or idioma_del_servidor() or IDIOMA_DEFAULT


def _idioma_de_query(request: Request | None) -> str | None:
    if request is None:
        return None
    return request.query_params.get("idioma") or request.query_params.get("lang")


ESTADOS_BOLETO: dict[str, str] = {
    "PENDIENTE": "estado_pendiente",
    "CERRADO": "estado_cerrado",
    "MODIFICADO": "estado_modificado",
    "ANULADO": "estado_anulado",
}


def traducir_estado_boleto(estado: str | None, lang: str = IDIOMA_DEFAULT) -> str:
    """Traduce el estado del boleto (PENDIENTE/CERRADO/...) al idioma activo.

    Los estados son parte del modelo de datos, pero se muestran impresos al
    usuario final, así que en tickets y reportes deben traducirse.
    """
    if not estado:
        return ""
    clave = ESTADOS_BOLETO.get(estado.strip().upper())
    return t(clave, lang) if clave else estado

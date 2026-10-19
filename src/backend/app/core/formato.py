"""Formateo de números y fechas según el idioma activo (es/en/pt).

Fuente única para tickets, exportaciones y reportes: evita que cada servicio
mantenga su propia copia (y su propio separador fijo en español).
"""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal, InvalidOperation

from app.core.i18n import IDIOMA_DEFAULT, normalizar_idioma

SIN_DATO = "—"


def formatear_numero(
    valor: Decimal | float | int | str | None,
    decimales: int = 2,
    lang: str = IDIOMA_DEFAULT,
) -> str:
    """Formatea un número con los separadores del idioma.

    es/pt → ``1.234,56`` · en → ``1,234.56``
    """
    idioma = normalizar_idioma(lang) or IDIOMA_DEFAULT
    if valor is None or valor == "":
        return f"{0:.{decimales}f}".replace(".", ",") if idioma != "en" else f"{0:.{decimales}f}"
    try:
        if isinstance(valor, Decimal):
            numero = float(valor)
        elif isinstance(valor, (int, float)):
            numero = float(valor)
        else:
            numero = float(str(valor).replace(",", "."))
    except (ValueError, InvalidOperation, TypeError):
        return str(valor)
    texto = f"{numero:,.{decimales}f}"
    if idioma == "en":
        return texto
    return texto.replace(",", "X").replace(".", ",").replace("X", ".")


def formatear_fecha(
    valor: date | datetime | str | None,
    lang: str = IDIOMA_DEFAULT,
    con_hora: bool = False,
    vacio: str = SIN_DATO,
) -> str:
    """Formatea una fecha en el formato regional ``dd/mm/aaaa`` (+ hora).

    Se mantiene ``dd/mm/aaaa`` en los tres idiomas porque la audiencia es
    latinoamericana; lo que cambia por idioma es el separador de miles y la
    coma decimal (ver :func:`formatear_numero`).
    """
    normalizar_idioma(lang)  # valida el idioma; no cambia el formato regional
    if valor is None or valor == "":
        return vacio
    if isinstance(valor, str):
        texto = valor
        try:
            valor = datetime.fromisoformat(texto.replace("Z", "+00:00"))
        except ValueError:
            return texto[:19] if len(texto) >= 10 else texto
    if isinstance(valor, date) and not isinstance(valor, datetime):
        valor = datetime(valor.year, valor.month, valor.day)
    return valor.strftime("%d/%m/%Y %H:%M" if con_hora else "%d/%m/%Y")

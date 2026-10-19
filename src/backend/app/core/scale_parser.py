"""Parser de tramas de básculas industriales reales (multi-marca).

Extrae el peso de una **línea ASCII** emitida por indicadores reales
(Toledo/GSI ``ST,GS,+00320.00kg``, Rice Lake/iQ con dirección ``01+000320.0``,
Mettler Toledo MT-SICS ``S S 320.00 kg``, etc.) y clasifica su estabilidad.

El parser es **puro**: no toca red, serial ni base de datos. Lo usan tanto
``SerialScaleHAL`` como ``TcpScaleHAL`` (``app/core/scale_hal.py``) para que la
robustez numérica viva en un único sitio y sea testeable sin hardware.

Principio anti-falso-positivo
-----------------------------
Un número desnudo (``1234567890``, la dirección ``01``, un checksum) **no** es
un peso: carece de señal semántica. Por eso un token solo se acepta como
candidato si trae **signo**, **decimal**, **unidad** o venía precedido de un
token de signo suelto. Ante ambigüedad (varios números distintos en la línea)
se rechaza la trama: es preferible ``None`` (y que la sesión reintente) que
fijar un peso equivocado a un boleto.
"""

from __future__ import annotations

import json
import re

# ---------------------------------------------------------------------------
# Constantes de estado (Toledo/GSI y variantes)
# ---------------------------------------------------------------------------
ESTADO_ESTABLE = "stable"
ESTADO_INESTABLE = "unstable"
ESTADO_SOBRECARGA = "overload"

# Unidades conocidas que pueden ir pegadas al número. Se prueban de más larga
# a más corta para no dejar restos (``KGS`` antes que ``G``).
_UNIDADES = ("KGS", "KG", "LBS", "LB", "TONS", "TON", "G", "T")
_RE_UNIDAD_FINAL = re.compile(r"(?:" + "|".join(_UNIDADES) + r")$", re.IGNORECASE)

# Token numérico válido: signo opcional + dígitos + decimal opcional.
_RE_NUM = re.compile(r"^[+-]?\d+(?:\.\d+)?$")
# Números con signo embebido (p. ej. dirección adherida ``01+000320.0``).
_RE_NUM_EMBEBIDO = re.compile(r"[+-]\s*\d+(?:\.\d+)?")
# Colapsa el espacio entre un signo y sus dígitos (``-  12.50`` → ``-12.50``).
_RE_SIGNO_ESPACIO = re.compile(r"([+-])\s+")
# Separadores de campo en las tramas ASCII (coma, punto y coma, espacios).
_RE_SEPARADOR = re.compile(r"[,;\s]+")

MAX_DECIMALES = 3
TOLERANCIA_CAPACIDAD = 1.05


def _separar_tokens(texto: str) -> list[str]:
    return [t for t in _RE_SEPARADOR.split(texto.strip()) if t]


def _extraer_payload(linea: str) -> tuple[str, str | None]:
    """Devuelve ``(payload, checksum)`` de la trama.

    - Limpia ``NUL``/``CR``/``LF`` y los delimitadores de control ``STX``/
      ``ETX`` que puedan colarse en el payload (p. ej. un frame leído con
      ``readuntil(b"\\x03")`` conserva el ``ETX`` final).
    - Si hay ``STX`` (0x02), toma el contenido hasta ``ETX`` (0x03) y lo que
      siga (2 hex) se considera checksum; se descarta el resto.
    """
    limpio = linea.replace("\x00", "")
    idx_stx = limpio.find("\x02")
    payload: str
    if idx_stx != -1:
        idx_etx = limpio.find("\x03", idx_stx + 1)
        if idx_etx != -1:
            payload = limpio[idx_stx + 1 : idx_etx]
            resto = limpio[idx_etx + 1 :].strip()
            checksum = resto if re.fullmatch(r"[0-9A-Fa-f]{2}", resto) else None
            return payload.replace("\x02", "").replace("\x03", "").strip(), checksum
        # STX sin ETX: nos quedamos con lo que va tras el STX.
        limpio = limpio[idx_stx + 1 :]
    payload = limpio.replace("\x02", "").replace("\x03", "")
    return payload.strip(), None


def _checksum_valido(payload: str, checksum_hex: str) -> bool:
    """XOR de todos los bytes del payload == checksum (formato Toledo/GSI)."""
    try:
        esperado = int(checksum_hex, 16)
    except ValueError:
        return False
    xor = 0
    for byte in payload.encode("latin-1", errors="ignore"):
        xor ^= byte
    return xor == esperado


def _clasificar_estado(payload: str) -> str | None:
    """Devuelve ``stable``/``unstable``/``overload`` o ``None``."""
    tokens = {t.upper() for t in _separar_tokens(payload)}
    if "OL" in tokens:
        return ESTADO_SOBRECARGA
    if "ST" in tokens:
        return ESTADO_ESTABLE
    if "US" in tokens:
        return ESTADO_INESTABLE
    return None


def _candidato(normalizado: str) -> tuple[float, int] | None:
    """Convierte un token normalizado en ``(valor, decimales)`` si es número."""
    if not _RE_NUM.match(normalizado):
        return None
    decimales = len(normalizado.split(".", 1)[1]) if "." in normalizado else 0
    try:
        return float(normalizado), decimales
    except ValueError:
        return None


def _extraer_numero(
    payload: str, capacidad_max: float | None
) -> tuple[float | None, str | None]:
    """Extrae **un** peso de la trama.

    Devuelve ``(peso, None)`` si es válido; ``(None, motivo)`` con ``motivo``
    ∈ ``{sin_numero, ambiguo, sobre_capacidad, precision}`` en caso contrario.
    """
    candidatos: list[tuple[float, int]] = []
    signo_pendiente: str | None = None

    for token in _separar_tokens(payload):
        # Token de signo suelto: se aplica al siguiente número (``-  12.50``).
        if token in ("+", "-"):
            signo_pendiente = token
            continue

        tenia_unidad = bool(_RE_UNIDAD_FINAL.search(token))
        cuerpo = _RE_UNIDAD_FINAL.sub("", token)
        cuerpo = _RE_SIGNO_ESPACIO.sub(r"\1", cuerpo).replace(",", ".")
        if not cuerpo:
            continue

        tenia_signo = cuerpo[0] in "+-"
        # Señal semántica: signo, decimal, unidad o signo suelto previo.
        tiene_senal = tenia_signo or "." in cuerpo or tenia_unidad or signo_pendiente
        if not tiene_senal:
            # Número desnudo (dirección, checksum): NO es un peso.
            continue

        numero = _candidato(cuerpo)
        if numero is None:
            continue
        valor, decimales = numero
        if signo_pendiente == "-":
            valor = -abs(valor)
        elif signo_pendiente == "+":
            valor = abs(valor)
        signo_pendiente = None
        candidatos.append((valor, decimales))

    if not candidatos:
        # Fallback: signo embebido (dirección adherida al número).
        for hallado in _RE_NUM_EMBEBIDO.findall(payload):
            normalizado = _RE_SIGNO_ESPACIO.sub(r"\1", hallado).replace(",", ".")
            numero = _candidato(normalizado)
            if numero is not None:
                candidatos.append(numero)

    if len(candidatos) > 1:
        return None, "ambiguo"
    if not candidatos:
        return None, "sin_numero"

    valor, decimales = candidatos[0]
    if decimales > MAX_DECIMALES:
        return None, "precision"
    if capacidad_max is not None and abs(valor) > capacidad_max * TOLERANCIA_CAPACIDAD:
        return None, "sobre_capacidad"
    return valor, None


def parse_weight_frame(
    linea: str,
    *,
    capacidad_max: float | None = None,
    validar_checksum: bool = False,
) -> tuple[float | None, str | None, str | None]:
    """Parsea una trama ASCII de báscula.

    Devuelve ``(peso_kg, status, motivo)``:

    - ``motivo is None`` cuando se leyó un peso correcto;
    - ``status`` ∈ ``{stable, unstable, overload, None}``;
    - ``motivo`` ∈ ``{vacio, checksum, sobrecarga, sin_numero, ambiguo,
      sobre_capacidad, precision}`` si no hubo peso.
    """
    payload, checksum = _extraer_payload(linea)
    if not payload:
        return None, None, "vacio"

    if validar_checksum and checksum is not None and not _checksum_valido(payload, checksum):
        return None, None, "checksum"

    status = _clasificar_estado(payload)
    if status == ESTADO_SOBRECARGA:
        return None, status, "sobrecarga"

    peso = _extraer_numero(payload, capacidad_max)
    if peso[0] is None:
        return None, status, peso[1]
    return peso[0], status, None


def clasificar_trama(linea: str) -> str | None:
    """Clasifica una línea de red: ``"json"``, ``"ascii"`` o ``None``.

    El JSON del simulador BSDD gana siempre; si no, se intenta el parser ASCII.
    Se usa en ``TcpScaleHAL`` para la auto-detección de formato.
    """
    texto = linea.strip()
    if not texto:
        return None
    try:
        payload = json.loads(texto)
    except ValueError:
        pass
    else:
        if isinstance(payload, dict) and payload.get("weight_kg") is not None:
            return "json"
    peso, _status, _motivo = parse_weight_frame(linea)
    return "ascii" if peso is not None else None

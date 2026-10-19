#!/usr/bin/env python3
"""Servidor TCP de prueba ligero para simulación de indicador de pesaje.

Escucha en el puerto indicado y emite tramas Toledo o Yaohua cada 200ms.
Si recibe un comando 'P' o 'T', responde de acuerdo al protocolo.

Uso:
    python tcp_echo_indicator.py --port 5555 --peso 32500.0
"""

from __future__ import annotations

import argparse
import asyncio
import sys


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, peso_init: float):
    addr = writer.get_extra_info("peername")
    print(f"[+] Indicador TCP: Conexión entrante desde {addr}")
    peso = peso_init
    try:
        while True:
            # Enviar trama Toledo estándar
            frame = f"ST,GS,+{abs(peso):08.2f}kg\r\n".encode("latin-1")
            writer.write(frame)
            await writer.drain()

            # Chequear si llegó algún comando sin bloquear
            try:
                line = await asyncio.wait_for(reader.read(128), timeout=0.2)
                if line:
                    cmd = line.decode("ascii", errors="ignore").strip().upper()
                    print(f"[*] Comando recibido de {addr}: {cmd}")
                    if cmd == "T" or cmd == "Z":
                        peso = 0.0
                    elif cmd == "P":
                        pass
            except asyncio.TimeoutError:
                pass
    except (ConnectionResetError, BrokenPipeError, asyncio.CancelledError):
        pass
    finally:
        print(f"[-] Indicador TCP: Conexión cerrada con {addr}")
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def main():
    parser = argparse.ArgumentParser(description="Servidor TCP de pesaje industrial")
    parser.add_argument("--port", type=int, default=5555, help="Puerto TCP (default: 5555)")
    parser.add_argument("--peso", type=float, default=28450.0, help="Peso base en kg")
    args = parser.parse_args()

    server = await asyncio.start_server(lambda r, w: handle_client(r, w, args.peso), "0.0.0.0", args.port)
    print(f"[*] Indicador TCP escuchando en 0.0.0.0:{args.port} | Peso: {args.peso} kg")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n[*] Servidor detenido.")

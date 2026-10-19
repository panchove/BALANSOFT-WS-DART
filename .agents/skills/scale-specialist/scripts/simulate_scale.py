#!/usr/bin/env python3
"""Simulador de báscula industrial en vivo (TCP o Serial PTY).

Permite probar el HAL de BALANSOFT-WS (tanto en backend FastAPI como en Flutter)
sin necesidad de contar con un indicador físico conectado.

Uso:
    # Servidor TCP en puerto 5555 emitiendo Yaohua a 24.500 kg
    python simulate_scale.py --tcp 5555 --indicator yaohua --peso 24500

    # Servidor TCP emitiendo Toledo a 10 Hz
    python simulate_scale.py --tcp 5555 --indicator toledo --peso 320.5 --hz 10

    # Puerto Serie virtual (Linux PTY)
    python simulate_scale.py --serial /tmp/ttyV0 --indicator toledo --peso 15000
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
import time

# Helper de generación de tramas
def generar_frame(indicator: str, peso: float, estable: bool = True) -> bytes:
    st = "ST" if estable else "US"
    sign = "+" if peso >= 0 else "-"
    abs_p = abs(peso)

    if indicator == "toledo":
        # Toledo / GSI: ST,GS,+00320.00kg\r\n
        w_str = f"{abs_p:08.2f}"
        return f"{st},GS,{sign}{w_str}kg\r\n".encode("latin-1")
    elif indicator == "yaohua":
        # Yaohua modo continuo '=': =+000023.5kg\r\n
        w_str = f"{abs_p:07.1f}"
        return f"={sign}{w_str}kg\r\n".encode("latin-1")
    elif indicator == "rice_lake":
        # Rice Lake EDP: 01+000320.0\r\n
        w_str = f"{abs_p:07.1f}"
        return f"01{sign}{w_str}\r\n".encode("latin-1")
    elif indicator == "torrey":
        # Torrey LQ: ST,GS,+00042.5kg\r\n
        w_str = f"{abs_p:07.1f}"
        return f"{st},GS,{sign}{w_str}kg\r\n".encode("latin-1")
    elif indicator == "keli":
        # Keli STX/ETX + XOR Checksum
        payload = f"{st},GS,{sign}{abs_p:08.2f}kg"
        xor_sum = 0
        for b in payload.encode("latin-1"):
            xor_sum ^= b
        return f"\x02{payload}\x03{xor_sum:02X}\r\n".encode("latin-1")
    elif indicator == "mtsics":
        s_tok = "S" if estable else "D"
        return f"S {s_tok} {abs_p:.2f} kg\r\n".encode("latin-1")
    else:
        # BSDD JSON
        stat_tok = "stable" if estable else "unstable"
        return f'{{"weight_kg": {peso}, "status": "{stat_tok}"}}\n'.encode("utf-8")


async def run_tcp_server(port: int, indicator: str, peso_base: float, hz: float, fluctuar: bool):
    interval = 1.0 / hz
    print(f"[*] Iniciando simulador TCP en 0.0.0.0:{port}")
    print(f"[*] Indicador: {indicator} | Peso base: {peso_base} kg | Frecuencia: {hz} Hz")

    async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        addr = writer.get_extra_info("peername")
        print(f"[+] Cliente conectado desde {addr}")
        step = 0
        try:
            while True:
                actual_peso = peso_base
                estable = True
                if fluctuar:
                    # Alternar ligeras oscilaciones cada 10 ciclos
                    step += 1
                    if (step % 15) < 3:
                        actual_peso += (step % 5) * 2.0
                        estable = False

                frame = generar_frame(indicator, actual_peso, estable)
                writer.write(frame)
                await writer.drain()
                await asyncio.sleep(interval)
        except (ConnectionResetError, BrokenPipeError, asyncio.CancelledError):
            pass
        finally:
            print(f"[-] Cliente desconectado {addr}")
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    server = await asyncio.start_server(handle_client, "0.0.0.0", port)
    async with server:
        await server.serve_forever()


def run_serial_pty(pty_path: str, indicator: str, peso_base: float, hz: float):
    interval = 1.0 / hz
    master, slave = os.openpty()
    slave_name = os.ttyname(slave)

    if os.path.exists(pty_path) or os.path.islink(pty_path):
        os.remove(pty_path)
    os.symlink(slave_name, pty_path)

    print(f"[*] Simulador serial iniciado en PTY: {slave_name}")
    print(f"[*] Enlace simbólico activo: {pty_path} -> {slave_name}")
    print(f"[*] Indicador: {indicator} | Peso base: {peso_base} kg")

    try:
        while True:
            frame = generar_frame(indicator, peso_base, True)
            os.write(master, frame)
            time.sleep(interval)
    except KeyboardInterrupt:
        pass
    finally:
        os.close(master)
        os.close(slave)
        if os.path.islink(pty_path):
            os.remove(pty_path)
        print("\n[*] Simulador serial finalizado.")


def main():
    parser = argparse.ArgumentParser(description="Simulador de báscula industrial en vivo")
    parser.add_argument("--tcp", type=int, help="Puerto TCP para escuchar (ej: 5555)")
    parser.add_argument("--serial", type=str, help="Ruta de enlace serie virtual PTY (ej: /tmp/ttyV0)")
    parser.add_argument(
        "--indicator",
        type=str,
        default="toledo",
        choices=["toledo", "yaohua", "rice_lake", "torrey", "keli", "mtsics", "bsdd_json"],
        help="Tipo de indicador a simular",
    )
    parser.add_argument("--peso", type=float, default=15000.0, help="Peso en kg")
    parser.add_argument("--hz", type=float, default=5.0, help="Frecuencia en Hz (lecturas por segundo)")
    parser.add_argument("--fluctuar", action="store_true", help="Simular oscilaciones de viento/movimiento")

    args = parser.parse_args()

    if not args.tcp and not args.serial:
        parser.print_help()
        print("\nError: Debe especificar al menos --tcp <puerto> o --serial <ruta_pty>")
        sys.exit(1)

    if args.tcp:
        try:
            asyncio.run(run_tcp_server(args.tcp, args.indicator, args.peso, args.hz, args.fluctuar))
        except KeyboardInterrupt:
            print("\n[*] Servidor TCP detenido.")
    elif args.serial:
        run_serial_pty(args.serial, args.indicator, args.peso, args.hz)


if __name__ == "__main__":
    main()

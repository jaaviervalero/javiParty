#!/usr/bin/env python3
"""Simulador de servidor DSU: hace de "móvil" para probar javiParty sin móvil.

Uso:
    python3 tools/dsu_simulator.py                 # 1 mando, teclado
    python3 tools/dsu_simulator.py --controllers 2 # 2 mandos (slots 0 y 1)
    python3 tools/dsu_simulator.py --auto          # se mueve solo, sin teclado

Teclas (en esta terminal):
    flechas   cruceta            z / x / c / v   A / B / 1 / 2
    - / +     − / +
    w a s d   inclinar           r               enderezar (plano)
    espacio   sacudida           h               HOME (overlay de depuración)
    1-4       elegir mando       q               salir

Responde a peticiones de info y de datos como lo haría la app del móvil, y deja
de enviar a un cliente si no renueva su suscripción en 5 s.
"""
import argparse
import math
import os
import random
import select
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsu_packets as dsu  # noqa: E402

SUB_TIMEOUT = 5.0
PRESS_TIME = 0.15
SHAKE_TIME = 0.35

# tecla -> (byte, bit). Mismos bits que el mando de javiParty y el diseño Wiimote de
# DSU Controller: A = 0x40, B = 0x80, 1 = 0x10, 2 = 0x20, − = SHARE, + = OPTIONS.
KEY_BUTTONS = {
    "UP": (1, 0x10), "DOWN": (1, 0x40), "LEFT": (1, 0x80), "RIGHT": (1, 0x20),
    "z": (2, 0x40), "x": (2, 0x80), "c": (2, 0x10), "v": (2, 0x20),
    "-": (1, 0x01), "+": (1, 0x08),
}


class Pad:
    def __init__(self, slot):
        self.slot = slot
        self.mac = bytes([0x02, 0x51, 0x4D, 0x00, 0x00, slot])  # MAC local inventada
        self.pressed = {}   # (byte, bit) -> instante en que se suelta
        self.home_until = 0.0
        self.tilt = [0.0, 0.0]
        self.prev_tilt = [0.0, 0.0]
        self.shake_until = 0.0
        self.accel = (0.0, 0.0, -1.0)
        self.gyro = (0.0, 0.0, 0.0)
        self.ts_us = 0

    def update(self, now, dt, auto):
        if auto:
            self.tilt = [0.45 * math.sin(now * 0.7 + self.slot), 0.35 * math.sin(now * 0.5 + 2 * self.slot)]
            if random.random() < dt * 0.3:
                self.shake_until = now + SHAKE_TIME
            if random.random() < dt * 0.5:
                self.pressed[(2, 0x40)] = now + PRESS_TIME
        tx, ty = self.tilt
        tz = -math.sqrt(max(0.0, 1.0 - tx * tx - ty * ty))
        ax, ay, az = tx, ty, tz
        if now < self.shake_until:
            ax += random.uniform(-3, 3)
            ay += random.uniform(-3, 3)
            az += random.uniform(-3, 3)
        # Giroscopio aproximado a partir de la velocidad de inclinación (°/s).
        if dt > 0:
            gp = math.degrees(math.asin(max(-1, min(1, ty))) - math.asin(max(-1, min(1, self.prev_tilt[1])))) / dt
            gr = math.degrees(math.asin(max(-1, min(1, tx))) - math.asin(max(-1, min(1, self.prev_tilt[0])))) / dt
        else:
            gp = gr = 0.0
        self.prev_tilt = list(self.tilt)
        self.accel = (ax, ay, az)
        self.gyro = (gp, 0.0, gr)
        self.ts_us = int(now * 1_000_000)

    def buttons(self, now):
        b1 = b2 = 0
        for (byte, bit), until in list(self.pressed.items()):
            if now < until:
                if byte == 1:
                    b1 |= bit
                else:
                    b2 |= bit
            else:
                del self.pressed[(byte, bit)]
        return b1, b2, 1 if now < self.home_until else 0


def read_keys():
    """Lee las teclas disponibles sin bloquear (stdin en modo cbreak)."""
    keys = []
    while select.select([sys.stdin], [], [], 0)[0]:
        ch = os.read(sys.stdin.fileno(), 1).decode(errors="ignore")
        if ch == "\x1b":
            seq = os.read(sys.stdin.fileno(), 2).decode(errors="ignore")
            keys.append({"[A": "UP", "[B": "DOWN", "[C": "RIGHT", "[D": "LEFT"}.get(seq, ""))
        else:
            keys.append(ch)
    return keys


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=dsu.PORT)
    ap.add_argument("--controllers", type=int, default=1, choices=[1, 2, 3, 4])
    ap.add_argument("--rate", type=float, default=60.0, help="paquetes por segundo")
    ap.add_argument("--auto", action="store_true", help="movimiento automático, sin teclado")
    args = ap.parse_args()

    server_id = random.getrandbits(32)
    pads = [Pad(i) for i in range(args.controllers)]
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", args.port))
    sock.setblocking(False)
    # cliente (ip, puerto) -> {"slots": set | None (todos), "last": t, "pn": contador}
    clients = {}
    current = 0

    interactive = sys.stdin.isatty() and not args.auto
    old_term = None
    if interactive:
        import termios
        import tty
        old_term = termios.tcgetattr(sys.stdin)
        tty.setcbreak(sys.stdin.fileno())

    print(f"Simulador DSU en UDP :{args.port} con {args.controllers} mando(s). "
          f"{'Teclado activo (q para salir).' if interactive else 'Modo automático.'}")
    period = 1.0 / args.rate
    last = time.monotonic()
    next_send = last
    try:
        while True:
            now = time.monotonic()
            dt = now - last
            last = now

            # --- Peticiones entrantes ---
            while True:
                try:
                    data, addr = sock.recvfrom(1024)
                except BlockingIOError:
                    break
                parsed = dsu.parse_client_packet(data)
                if not parsed:
                    continue
                msg_type, payload, _cid = parsed
                if msg_type == dsu.MSG_INFO and len(payload) >= 4:
                    count = int.from_bytes(payload[:4], "little", signed=True)
                    for slot in payload[4:4 + max(0, min(count, 4))]:
                        if slot < len(pads):
                            pkt = dsu.info_response(server_id, slot, mac=pads[slot].mac)
                        else:
                            pkt = dsu.info_response(server_id, slot, state=0, model=0, connection=0, battery=0)
                        sock.sendto(pkt, addr)
                elif msg_type == dsu.MSG_DATA and len(payload) >= 8:
                    flags, slot = payload[0], payload[1]
                    if addr not in clients:
                        print(f"\r\nCliente suscrito: {addr[0]}:{addr[1]}")
                    c = clients.setdefault(addr, {"slots": set(), "last": now, "pn": 0})
                    if flags == 0:
                        c["slots"] = None
                    elif flags & 1 and c["slots"] is not None:
                        c["slots"].add(slot)
                    elif flags & 2 and c["slots"] is not None:
                        for p in pads:
                            if p.mac == bytes(payload[2:8]):
                                c["slots"].add(p.slot)
                    c["last"] = now
                elif msg_type == dsu.MSG_VERSION:
                    sock.sendto(dsu.build_packet(dsu.MSG_VERSION, dsu.VERSION.to_bytes(2, "little"), server_id), addr)

            for addr in [a for a, c in clients.items() if now - c["last"] > SUB_TIMEOUT]:
                print(f"\r\nCliente sin renovar, dejo de enviar: {addr[0]}:{addr[1]}")
                del clients[addr]

            # --- Teclado ---
            if interactive:
                for k in read_keys():
                    pad = pads[current]
                    if k == "q":
                        return
                    if k in KEY_BUTTONS:
                        pad.pressed[KEY_BUTTONS[k]] = now + PRESS_TIME
                    elif k in "1234" and k and int(k) <= len(pads):
                        current = int(k) - 1
                    elif k == " ":
                        pad.shake_until = now + SHAKE_TIME
                    elif k == "h":
                        pad.home_until = now + PRESS_TIME
                    elif k == "r":
                        pad.tilt = [0.0, 0.0]
                    elif k in "wasd" and k:
                        i, d = {"a": (0, -0.15), "d": (0, 0.15), "w": (1, -0.15), "s": (1, 0.15)}[k]
                        pad.tilt[i] = max(-0.9, min(0.9, pad.tilt[i] + d))

            # --- Envío de datos ---
            if now >= next_send:
                next_send += period
                if next_send < now:
                    next_send = now + period
                for pad in pads:
                    pad.update(now, period, args.auto)
                for addr, c in clients.items():
                    for pad in pads:
                        if c["slots"] is not None and pad.slot not in c["slots"]:
                            continue
                        c["pn"] += 1
                        b1, b2, home = pad.buttons(now)
                        sock.sendto(dsu.data_response(
                            server_id, pad.slot, c["pn"], buttons1=b1, buttons2=b2, home=home,
                            timestamp_us=pad.ts_us, accel=pad.accel, gyro=pad.gyro, mac=pad.mac), addr)
                if interactive:
                    p = pads[current]
                    sys.stdout.write(f"\rmando {current + 1}  incl x {p.tilt[0]:+.2f} y {p.tilt[1]:+.2f}  "
                                     f"clientes {len(clients)}   ")
                    sys.stdout.flush()
            time.sleep(0.002)
    except KeyboardInterrupt:
        pass
    finally:
        if old_term is not None:
            import termios
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_term)
        print()


if __name__ == "__main__":
    main()

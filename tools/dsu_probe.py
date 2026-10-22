#!/usr/bin/env python3
"""Sonda guiada de un móvil DSU: averigua qué bit manda cada botón de la app y
cómo orienta los ejes del acelerómetro y del giroscopio.

    python3 tools/dsu_probe.py            # busca el móvil en la red
    python3 tools/dsu_probe.py --ip 192.168.1.50

Ejecútalo en una terminal normal (necesita que veas las instrucciones en vivo) y
con javiParty CERRADO. Guarda el resultado en tools/probe_result.json.
"""
import argparse
import json
import math
import os
import random
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsu_packets as dsu  # noqa: E402

sys.stdout.reconfigure(line_buffering=True)

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe_result.json")

BUTTON_STEPS = [
    ("A", "Pulsa A (el botón morado grande)"),
    ("B", "Pulsa B (la barra ancha)"),
    ("1", "Pulsa 1"),
    ("2", "Pulsa 2"),
    ("MINUS", "Pulsa − (menos)"),
    ("PLUS", "Pulsa + (más)"),
    ("HOME", "Pulsa la casita (HOME)"),
    ("DPAD_UP", "Pulsa la cruceta hacia ARRIBA (según ves la pantalla en vertical)"),
    ("DPAD_RIGHT", "Pulsa la cruceta hacia la DERECHA (según ves la pantalla en vertical)"),
]

MOTION_STEPS = [
    ("flat", "still", "Deja el móvil QUIETO sobre la mesa, pantalla hacia arriba."),
    ("pointing", "still", "Cógelo en VERTICAL como un mando de Wii (A arriba), apuntando a la tele, y quieto."),
    ("turn_right", "rotate", "Desde ahí, apunta hacia la DERECHA de la tele girando el brazo (unos 45°)."),
    ("point_up", "rotate", "Vuelve al centro y ahora apunta hacia ARRIBA, al techo (unos 45°)."),
    ("twist_right", "rotate", "Vuelve al centro y gira la muñeca a la DERECHA, como un pomo (unos 45°)."),
    ("sideways", "still", "Ponlo en HORIZONTAL con las dos manos (cruceta a la izquierda, 1 y 2 a la derecha), quieto."),
    ("steer_right", "rotate", "En horizontal, gíralo como un VOLANTE hacia la derecha (unos 45°)."),
]


class Phone:
    def __init__(self, sock, addr, slot):
        self.sock, self.addr, self.slot = sock, addr, slot
        self.client_id = random.getrandbits(32)
        self.last_sub = 0.0
        self.last = None
        self.count = 0

    def pump(self, timeout=0.02):
        """Renueva la suscripción y devuelve los paquetes de datos recibidos."""
        now = time.monotonic()
        if now - self.last_sub > 1.0:
            try:
                self.sock.sendto(dsu.data_request(self.client_id, self.slot), self.addr)
                self.last_sub = now
            except BlockingIOError:
                pass  # buffer lleno: se reintenta en la siguiente vuelta
        out = []
        end = now + timeout
        while time.monotonic() < end:
            try:
                data, addr = self.sock.recvfrom(1024)
            except BlockingIOError:
                time.sleep(0.002)
                continue
            msg = dsu.parse_server_packet(data)
            if msg and msg["type"] == dsu.MSG_DATA and msg["slot"] == self.slot:
                msg["rx"] = time.monotonic()
                self.last = msg
                self.count += 1
                out.append(msg)
        return out


def local_prefix():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.1.1", 9))
        ip = s.getsockname()[0]
    finally:
        s.close()
    return ip.rsplit(".", 1)[0] + "."


def find_phone(ip=None):
    """Escanea con un socket propio y bloqueante: al mandar a muchas IPs que no
    existen, el kernel retiene los paquetes esperando a ARP y el buffer de envío
    se llena; en modo no bloqueante eso hacía saltarse IPs (o fallar después)."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.settimeout(5.0)
    cid = random.getrandbits(32)
    targets = [ip] if ip else [local_prefix() + str(h) for h in range(1, 255)]
    print(f"Buscando servidores DSU en {'la IP ' + ip if ip else targets[0].rsplit('.', 1)[0] + '.x'}…", flush=True)
    found = {}
    for attempt in range(3):
        for t in targets:
            try:
                sock.sendto(dsu.info_request(cid), (t, dsu.PORT))
            except OSError:
                pass
        end = time.monotonic() + 2.0
        sock.settimeout(0.1)
        while time.monotonic() < end:
            try:
                data, addr = sock.recvfrom(1024)
            except (socket.timeout, BlockingIOError):
                continue
            msg = dsu.parse_server_packet(data)
            if msg and msg["type"] == dsu.MSG_INFO and msg["state"] == 2:
                found.setdefault(addr, msg["slot"])
        sock.settimeout(5.0)
        if found:
            break
    sock.close()
    return found


def wait_press(phone, timeout=20.0):
    """Espera a que no haya nada pulsado, luego a una pulsación; devuelve los bits."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        phone.pump()
        if phone.last and phone.last["buttons"] == 0:
            break
    seen = 0
    while time.monotonic() < end:
        for m in phone.pump():
            seen |= m["buttons"]
        if seen and phone.last and phone.last["buttons"] == 0:
            return seen
    return seen


def countdown(text, secs=3):
    print(f"\n>> {text}")
    for i in range(secs, 0, -1):
        print(f"   {i}…", end="", flush=True)
        time.sleep(1)
    print("  ¡YA!", flush=True)


def capture(phone, seconds):
    msgs = []
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        msgs.extend(phone.pump())
    return msgs


def mean(vectors):
    n = max(1, len(vectors))
    return [sum(v[i] for v in vectors) / n for i in range(3)]


def integrate(msgs, bias):
    """Integra el giroscopio (°/s) en grados, usando el timestamp del móvil si vale."""
    total = [0.0, 0.0, 0.0]
    for a, b in zip(msgs, msgs[1:]):
        dt = (b["ts"] - a["ts"]) / 1e6
        if not 0 < dt < 0.1:
            dt = b["rx"] - a["rx"]
        for i in range(3):
            total[i] += (b["gyro"][i] - bias[i]) * dt
    return total


def fmt(v):
    return "(" + ", ".join(f"{x:+.3f}" for x in v) + ")"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ip")
    args = ap.parse_args()

    found = find_phone(args.ip)
    if not found:
        print("No encuentro ningún móvil. ¿Está la app abierta, en primer plano y en la misma wifi?")
        return 1
    addr, slot = next(iter(found.items()))
    print(f"Móvil encontrado: {addr[0]}:{addr[1]} slot {slot}")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.setblocking(False)
    phone = Phone(sock, addr, slot)

    t0 = time.monotonic()
    capture(phone, 2.0)
    rate = phone.count / (time.monotonic() - t0)
    print(f"Recibiendo datos: {rate:.0f} paquetes/s")
    if phone.count == 0:
        print("No llegan datos tras suscribirme. ¿Está javiParty abierto? Ciérralo y repite.")
        return 1

    result = {"phone": addr[0], "pps": rate, "buttons": {}, "motion": {}}

    print("\n=== BOTONES === (móvil en vertical, como en la foto)")
    for key, text in BUTTON_STEPS:
        print(f"\n>> {text}", flush=True)
        bits = wait_press(phone)
        names = dsu.button_names(bits)
        result["buttons"][key] = {"bits": bits, "names": names}
        print(f"   → {' + '.join(names) if names else 'NO DETECTADO'}")

    print("\n=== MOVIMIENTO === (cada paso: 3 s para colocarte, luego se mide)")
    bias = [0.0, 0.0, 0.0]
    for key, kind, text in MOTION_STEPS:
        countdown(text)
        msgs = capture(phone, 1.5 if kind == "still" else 2.5)
        if not msgs:
            print("   (sin datos)")
            continue
        acc = mean([m["accel"] for m in msgs])
        gyr = mean([m["gyro"] for m in msgs])
        entry = {"accel_mean": acc, "gyro_mean": gyr, "samples": len(msgs)}
        if key == "flat":
            bias = gyr
            noise = math.sqrt(sum(sum((m["gyro"][i] - gyr[i]) ** 2 for i in range(3)) for m in msgs) / len(msgs))
            entry["gyro_noise_dps"] = noise
            print(f"   gravedad {fmt(acc)} g · deriva giro {fmt(gyr)} °/s · ruido {noise:.2f} °/s")
        elif kind == "still":
            print(f"   gravedad {fmt(acc)} g")
        else:
            rot = integrate(msgs, bias)
            entry["gyro_integrated_deg"] = rot
            axis = max(range(3), key=lambda i: abs(rot[i]))
            print(f"   giro integrado (pitch, yaw, roll) {fmt(rot)} ° → eje dominante "
                  f"{['pitch', 'yaw', 'roll'][axis]} {'+' if rot[axis] > 0 else '−'}")
        result["motion"][key] = entry
        print("   vuelve a la posición de antes…", flush=True)
        time.sleep(1.0)

    with open(OUT, "w") as f:
        json.dump(result, f, indent=2)
    print(f"\nListo. Resultado guardado en {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

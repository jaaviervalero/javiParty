#!/usr/bin/env python3
"""Deduce automáticamente cómo mapea una app DSU los ejes del giroscopio.

    python3 tools/dsu_gyro_probe.py [--ip 192.168.1.50]

Con el móvil girando libremente, la gravedad vista desde el móvil (acelerómetro)
cambia según  dg/dt = g × ω  (ω = velocidad angular en ejes del móvil, rad/s).
Probamos las 48 asignaciones posibles gyro[i] -> eje con signo (6 permutaciones x
8 signos) y nos quedamos con la que mejor explica el cambio de la gravedad.
No hace falta hacer gestos precisos: solo mover el móvil despacio en todas direcciones.
Guarda la serie cruda en tools/probe_motion.json.
"""
import argparse
import itertools
import json
import math
import os
import socket
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsu_probe import Phone, capture, countdown, find_phone, mean  # noqa: E402

sys.stdout.reconfigure(line_buffering=True)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe_motion.json")
AXES = "xyz"


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def smooth(series, k=4):
    out = []
    for i in range(len(series)):
        lo, hi = max(0, i - k), min(len(series), i + k + 1)
        out.append(mean(series[lo:hi]))
    return out


def analyse(msgs, bias):
    """Devuelve las asignaciones ordenadas por error: (error_rel, escala, perm, signos)."""
    g = smooth([m["accel"] for m in msgs])
    w = smooth([[m["gyro"][i] - bias[i] for i in range(3)] for m in msgs])
    t = []
    for m in msgs:  # tiempo en s: timestamp del móvil si es coherente, si no el de llegada
        t.append(m["ts"] / 1e6)
    if any(not 0 <= b - a < 0.2 for a, b in zip(t, t[1:])):
        t = [m["rx"] for m in msgs]
    rows = []
    d = 3
    for i in range(d, len(msgs) - d):
        dt = t[i + d] - t[i - d]
        if dt <= 0:
            continue
        dg = [(g[i + d][k] - g[i - d][k]) / dt for k in range(3)]
        mag = math.sqrt(sum(x * x for x in g[i]))
        if not 0.85 < mag < 1.15:  # aceleración lineal fuerte: la "gravedad" no es fiable
            continue
        rows.append((dg, g[i], [math.radians(x) for x in w[i]]))
    results = []
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            num = den = 0.0
            preds = []
            for dg, gi, wi in rows:
                omega = [signs[a] * wi[perm[a]] for a in range(3)]  # ω en ejes x,y,z del móvil
                pred = cross(gi, omega)
                preds.append(pred)
                num += sum(dg[k] * pred[k] for k in range(3))
                den += sum(pred[k] * pred[k] for k in range(3))
            scale = num / den if den > 0 else 0.0
            if scale <= 0:
                # Invertir los 3 signos con escala negativa encaja igual de bien en la
                # ecuación, pero es físicamente falso: la escala real es +1 (°/s).
                continue
            err = sum(sum((dg[k] - scale * p[k]) ** 2 for k in range(3)) for (dg, _, _), p in zip(rows, preds))
            tot = sum(sum(x * x for x in dg) for dg, _, _ in rows) or 1.0
            results.append((err / tot, scale, perm, signs))
    results.sort(key=lambda r: r[0])
    return results, len(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ip")
    ap.add_argument("--seconds", type=float, default=15.0)
    args = ap.parse_args()
    found = find_phone(args.ip)
    if not found:
        print("No encuentro ningún móvil (app abierta, en primer plano, misma wifi, javiParty cerrado).")
        return 1
    addr, slot = next(iter(found.items()))
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.setblocking(False)
    phone = Phone(sock, addr, slot)
    capture(phone, 1.0)
    print(f"Móvil {addr[0]} slot {slot}: {phone.count} paquetes en 1 s")

    countdown("Deja el móvil QUIETO sobre la mesa (mido la deriva del giroscopio).")
    still = capture(phone, 2.0)
    bias = mean([m["gyro"] for m in still])
    print(f"   deriva {[round(x, 3) for x in bias]} °/s")

    countdown(f"Ahora cógelo y MUÉVELO DESPACIO en todas direcciones durante {args.seconds:.0f} s:\n"
              "   apunta a sitios distintos, inclínalo, gíralo como un volante, ponlo boca abajo…\n"
              "   (despacio y sin sacudirlo; lo importante es que gire mucho)")
    t0 = time.monotonic()
    msgs = []
    while time.monotonic() - t0 < args.seconds:
        msgs.extend(capture(phone, 1.0))
        print(f"   {args.seconds - (time.monotonic() - t0):4.0f} s…", flush=True)
    print("   ¡Para! Analizando…")

    with open(OUT, "w") as f:
        json.dump({"bias": bias, "samples": [{k: m[k] for k in ("ts", "rx", "accel", "gyro", "buttons")}
                                             for m in msgs]}, f)

    results, n = analyse(msgs, bias)
    if n < 100:
        print(f"Pocas muestras útiles ({n}). Repite moviéndolo más despacio y durante más rato.")
        return 1
    best, second = results[0], results[1]
    err, scale, perm, signs = best
    print(f"\nMuestras útiles: {n}")
    print("Mejor asignación (ω en ejes del móvil, X ancho, Y perpendicular a la pantalla, Z largo):")
    for a in range(3):
        print(f"   ω{AXES[a]} = {'+' if signs[a] > 0 else '-'}gyro[{perm[a]}]  "
              f"({['pitch', 'yaw', 'roll'][perm[a]]})")
    print(f"   error relativo {err:.3f} (segunda mejor {second[0]:.3f}) · escala {scale:.2f} (≈1 si son °/s)")
    if err > 0.5 or second[0] - err < 0.1:
        print("   ⚠ Resultado poco claro: repite girándolo más y más despacio.")
    print(f"Serie cruda guardada en {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

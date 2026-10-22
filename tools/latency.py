#!/usr/bin/env python3
"""Resume las líneas "LAT ..." que escribe el juego con --lat (o ?lat=1 en el
navegador): ida y vuelta (RTT) por tipo de mando y paquetes por segundo.

    godot3 --path . -- --lat --dsu=192.168.1.50 | tee lat.log
    python3 tools/latency.py lat.log [más.log ...]

RTT de cada tipo:
  dsu      petición de info -> respuesta del móvil (UDP), una cada 2 s
  web-lan  ping -> pong por WebSocket (APK de la tele / escritorio), una por segundo
  web-rtc  ping -> pong por WebRTC (versión de navegador), una por segundo
El retardo de una pulsación es más o menos RTT/2 más el tiempo hasta el frame
siguiente; el DSU suma además la espera hasta su siguiente paquete (1/pps).
"""
import statistics
import sys
from collections import defaultdict


def pct(xs, p):
    xs = sorted(xs)
    k = (len(xs) - 1) * p / 100.0
    lo = int(k)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def parse(lines):
    rows = defaultdict(list)  # (tipo, id) -> [dict]
    for line in lines:
        i = line.find("LAT ")
        if i < 0:
            continue
        parts = line[i:].split()
        if len(parts) < 4:
            continue
        row = {"t": int(parts[1])}
        for kv in parts[4:]:
            k, _, v = kv.partition("=")
            try:
                row[k] = float(v)
            except ValueError:
                pass
        if "rtt" in row:
            rows[(parts[2], parts[3])].append(row)
    return rows


def main():
    files = sys.argv[1:] or ["-"]
    lines = []
    for f in files:
        lines += (sys.stdin if f == "-" else open(f, encoding="utf-8", errors="replace")).readlines()
    rows = parse(lines)
    if not rows:
        print("No hay líneas LAT. ¿Arrancaste el juego con --lat (o ?lat=1)?")
        return 1
    print("%-8s %-10s %4s %7s %7s %7s %7s %7s %6s" % (
        "tipo", "mando", "n", "mín", "mediana", "p90", "p99", "máx", "pps"))
    for (kind, ident), rs in sorted(rows.items()):
        rtt = [r["rtt"] for r in rs]
        pps = [r["pps"] for r in rs if r.get("pps", 0) > 0]
        print("%-8s %-10s %4d %7.1f %7.1f %7.1f %7.1f %7.1f %6s" % (
            kind, ident[:10], len(rtt), min(rtt), statistics.median(rtt), pct(rtt, 90),
            pct(rtt, 99), max(rtt), "%.0f" % statistics.median(pps) if pps else "-"))
    print("(RTT en ms)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Genera el mando oficial de javiParty para la app DSU Controller (v3.0.6+).

    python3 tools/make_layout.py                 # imprime el enlace y abre el QR
    python3 tools/make_layout.py --size 393x852  # tamaño de Ajustes de la app (ancho x alto en vertical)

Formato (sacado del código de https://gamepad-layout.vercel.app/, el editor oficial):
  dsu-controller://layout?action=add&data=<base64 de este texto>
  línea 1:  1,<ancho>,<alto>,<orientación 1 vertical | 2 horizontal>   (ancho/alto en vertical)
  resto:    <tipo>,<nombre>,<etiqueta>,<principal 0/1>,<x>,<y>,<ancho>,<alto>,<r_si>:<r_sd>:<r_id>:<r_ii>
            tipo: 1 botón, 2 cruceta, 3 joystick, 4 botón de sistema. Máximo 18 componentes.
            En horizontal, x/y van en coordenadas de la pantalla girada (alto x ancho).

Los botones usan los MISMOS bits DSU que el diseño Wiimote de la app (A = 0x40,
B = 0x80), así que el juego los entiende igual con uno u otro (ver input/pad.gd).
"""
import argparse
import base64
import os
import subprocess
import sys

BASIC, DPAD, JOYSTICK, SYSTEM = 1, 2, 3, 4


def round_btn(name, label, x, y, d, primary=False):
    r = d // 2
    return (BASIC, name, label, primary, x, y, d, d, (r, r, r, r))


def layout(w, h):
    """Componentes en horizontal: pantalla de h (ancho) x w (alto). Estilo mando de
    salón: stick arriba a la izquierda, cruceta abajo, A/B a la derecha y la fila
    − HOME + centrada en mitad de la pantalla."""
    W, H = h, w  # dimensiones de la pantalla girada
    side = round(W * 0.075)                       # margen lateral (esquinas redondeadas / notch)
    stick = round(H * 0.36)
    dpad = round(H * 0.56)
    a = round(H * 0.34)
    b = round(H * 0.25)
    sys_d = 48
    gap = 22
    stick_x, stick_y = side, round(H * 0.06)
    dpad_x = side + round(stick * 0.35)
    dpad_y = H - dpad - round(H * 0.04)
    a_x = W - side - a
    a_y = H - a - round(H * 0.17)
    b_x = a_x - round(b * 0.95)
    b_y = a_y - round(b * 0.95)
    row_w = 3 * sys_d + 2 * gap
    row_x = (W - row_w) // 2
    row_y = (H - sys_d) // 2
    return [
        (JOYSTICK, "leftStick", "", False, stick_x, stick_y, stick, stick, ()),
        (DPAD, "", "", False, dpad_x, dpad_y, dpad, dpad, ()),
        # La app no respeta los nombres del editor: medido en iPhone, "circle" llega
        # como bit 0x20 y "triangle" como 0x10 (intercambia este<->sur y norte<->oeste).
        # Con eso, "cross" -> 0x40 y "square" -> 0x80: los bits de A y B del Wiimote.
        round_btn("cross", "A", a_x, a_y, a, primary=True),
        round_btn("square", "B", b_x, b_y, b),
        # La app dibuja los botones de sistema con su icono (ignora la etiqueta), así
        # que − y + van como botones normales pequeños con el mismo nombre/bit.
        round_btn("share", "-", row_x, row_y, sys_d),
        (SYSTEM, "home", "", True, row_x + sys_d + gap, row_y, sys_d, sys_d, ()),
        round_btn("options", "+", row_x + 2 * (sys_d + gap), row_y, sys_d),
    ]


def encode(w, h, components):
    text = f"1,{w},{h},2"
    for t, name, label, primary, x, y, cw, ch, rounded in components:
        text += "\n" + ",".join(str(v) for v in (
            t, name, label, int(primary), x, y, cw, ch, ":".join(str(r) for r in rounded)))
    return text, "dsu-controller://layout?action=add&data=" + base64.b64encode(text.encode("latin-1")).decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", default="393x852", help="ancho x alto del móvil en vertical (puntos)")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "controller", "javiparty_qr.png"))
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()
    w, h = (int(v) for v in args.size.lower().split("x"))
    text, link = encode(w, h, layout(w, h))
    print("Datos del mando:\n" + text + "\n\nEnlace:\n" + link)
    try:
        subprocess.run(["qrencode", "-s", "10", "-m", "2", "-o", args.out, link], check=True)
        print(f"\nQR guardado en {args.out}")
        if not args.no_open:
            subprocess.Popen(["xdg-open", args.out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("\n(instala 'qrencode' para generar el QR)", file=sys.stderr)


if __name__ == "__main__":
    main()

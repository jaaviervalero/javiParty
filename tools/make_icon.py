#!/usr/bin/env python3
"""Genera los iconos de lanzador de javiParty, con el mismo lenguaje visual que el
menú: fondo claro con degradado, la onda cian de WiiBackground y la tipografía
Nunito del juego ("javi" en gris + "Party" en cian, y los cuatro colores de
jugador como puntos).

    python3 tools/make_icon.py [carpeta_destino]

Escribe en la raíz del proyecto (o donde se le diga):
  icon.png                      512x512  icono de proyecto y `launcher_icons/main_192x192`
  icon_foreground_432x432.png   solo el logo, transparente, dentro de la zona segura
  icon_background_432x432.png   solo el fondo (degradado + ondas)
  icon.ico                      icono del .exe de Windows (16-256 px)

Android recorta el icono adaptativo hasta el 66% central (círculo de 285 px de los
432), así que el logo se dibuja al 52% del lienzo para que no lo corte ninguna
máscara. El `export_presets.cfg` apunta a los tres ficheros en `launcher_icons/*`.

Ojo: Godot 3.6 no sabe poner banner de Android TV ni la categoría LEANBACK_LAUNCHER
(eso es de Godot 4); con esto se cambia el icono de la app, que es lo que enseñan
los lanzadores de la tele.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

BG_TOP = (251, 252, 253)
BG_BOTTOM = (219, 229, 238)
TEXT = (91, 102, 112)
ACCENT = (51, 181, 229)
DOTS = [(47, 168, 224), (236, 90, 90), (76, 191, 107), (242, 163, 58)]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_BLACK = os.path.join(ROOT, "assets/fonts/Nunito-Black.ttf")


def gradient(size, top, bottom):
    strip = Image.new("RGB", (1, size[1]))
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        strip.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return strip.resize(size)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def background(size, radius):
    """Degradado claro + dos ondas cian suaves abajo, como WiiBackground."""
    bg = gradient(size, BG_TOP, BG_BOTTOM).convert("RGBA")
    waves = Image.new("RGBA", size, (0, 0, 0, 0))
    wd = ImageDraw.Draw(waves)
    w, h = size
    for base_off, amp, alpha in ((0.16, 0.020, 26), (0.10, 0.014, 36)):
        base_y = h - h * base_off
        pts = [(x, base_y + math.sin(x / w * math.tau * 1.2) * h * amp) for x in range(0, w + 1, 4)]
        pts += [(w, h), (0, h)]
        wd.polygon(pts, fill=ACCENT + (alpha,))
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.paste(Image.alpha_composite(bg, waves), (0, 0), rounded_mask(size, radius))
    return out


def logo(size, scale):
    """'javi' / 'Party' apilados + los cuatro colores de jugador, recortado a la
    tinta para que quede centrado de verdad (el ascendente de la 'j' descentra)."""
    w, h = size
    box = int(min(w, h) * scale)          # lado de la zona segura
    line_h = int(box * 0.30)
    dot_r = int(box * 0.045)
    gap_lines = int(box * 0.02)
    gap_dots = int(box * 0.045)
    dot_gap = int(box * 0.135)

    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT_BLACK, line_h)
    total = line_h * 2 + gap_lines + gap_dots + dot_r * 2
    y = (h - total) // 2
    for txt, col in (("javi", TEXT), ("Party", ACCENT)):
        tw = d.textlength(txt, font=font)
        d.text(((w - tw) / 2, y), txt, font=font, fill=col + (255,))
        y += line_h + gap_lines
    y += gap_dots - gap_lines
    x0 = (w - (dot_gap * 3 + dot_r * 2)) / 2
    for i, col in enumerate(DOTS):
        cx = x0 + i * dot_gap + dot_r
        d.ellipse([cx - dot_r, y, cx + dot_r, y + dot_r * 2], fill=col + (255,))
    return layer.crop(layer.getbbox()), box


def compose(size, radius, with_bg, scale):
    base = background(size, radius) if with_bg else Image.new("RGBA", size, (0, 0, 0, 0))
    lg, box = logo(size, scale)
    pos = ((size[0] - lg.width) // 2, (size[1] - lg.height) // 2)
    base.alpha_composite(lg, pos)
    ink = (pos[0], pos[1], pos[0] + lg.width, pos[1] + lg.height)
    return base, ink, box


def check(name, ink, box, size):
    w, h = size
    iw, ih = ink[2] - ink[0], ink[3] - ink[1]
    cx, cy = (ink[0] + ink[2]) / 2, (ink[1] + ink[3]) / 2
    print("%s: %dx%d, logo %dx%d, centro (%.0f,%.0f), zona segura %d px"
          % (name, w, h, iw, ih, cx, cy, box))
    assert iw <= box and ih <= box, "%s: el logo se sale de la zona segura" % name
    assert abs(cx - w / 2) <= 2 and abs(cy - h / 2) <= 2, "%s: logo descentrado" % name
    assert ink[0] >= 0 and ink[1] >= 0 and ink[2] <= w and ink[3] <= h, "%s: recortado" % name


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else ROOT
    img, ink, box = compose((512, 512), 112, True, 0.62)
    check("icon.png", ink, box, (512, 512))
    img.save(os.path.join(out, "icon.png"))
    # El .exe de Windows necesita .ico (lo incrusta rcedit al exportar).
    img.save(os.path.join(out, "icon.ico"), sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

    # El logo al 52%: Android recorta el adaptativo hasta el 66% central.
    fg, ink, box = compose((432, 432), 0, False, 0.52)
    check("icon_foreground_432x432.png", ink, box, (432, 432))
    fg.save(os.path.join(out, "icon_foreground_432x432.png"))

    background((432, 432), 0).save(os.path.join(out, "icon_background_432x432.png"))
    print("Escritos los iconos en", out)


main()

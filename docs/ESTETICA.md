# Dirección de arte de javiParty

Objetivo: que cada minijuego tenga **su ambiente** (un sitio: playa, gimnasio, lago,
jardín de noche...) sin perder el aire de consola de salón de los 2000: limpio, luminoso,
redondo y amable. Y que vaya **fluido en una Android TV modesta** (Mali-G31, 1–2 GB).

## 1. El estilo en cinco reglas

1. **Luminoso y suave.** Colores pastel saturados a medias, cielos claros, nada de negro
   puro ni fondos oscuros enteros (como mucho un anochecer lila claro).
2. **Todo redondo.** Esquinas redondeadas, bolas, colinas, nubes de círculos. Sin
   picos agresivos salvo en lo que sea peligro.
3. **Volumen sencillo.** Base + zona inferior un poco más oscura + reflejo blanco
   translúcido arriba a la izquierda (`DrawKit.glossy_ball`). Sombra difusa en el suelo
   (`DrawKit.soft_shadow`).
4. **Los jugadores mandan.** El decorado es más claro y menos saturado que los jugadores;
   los colores de jugador (azul, rojo, verde, naranja) solo se usan para lo suyo.
   Si el fondo compite con una bola, aclara el fondo.
5. **Marco de tele de juguete.** La arena es un rectángulo redondeado con ambiente propio,
   sombra suave y borde blanco grueso (`DrawKit.arena_frame` + `DrawKit.arena_border`).

## 2. Paleta

- Interfaz: `WiiTheme` (blancos, grises `TEXT`/`TEXT_SOFT`, acento cian `ACCENT`).
- Ambientes: `DrawKit.SKY_TOP/SKY_BOTTOM`, `GRASS*`, `WATER*`, `SAND*`, `WOOD*`, `STONE`.
  Puedes definir los tuyos como constantes, siguiendo la misma luminosidad.
- Premios `DrawKit.GOLD` (ffd34d), peligro `DrawKit.DANGER` (e25555).

## 3. Rendimiento: lo que se dibuja y cuándo

La tele es lenta en **relleno de píxeles** y en **llamadas de dibujo**. Así que:

- **Escenario estático → `_draw_scenery(ci)`.** Cielo, suelo, decorado, marco de la arena:
  se dibuja **una vez** y se reutiliza. Si cambia (rara vez), `redraw_scenery()`.
- **`_draw()` solo con lo que se mueve** (jugadores, proyectiles, efectos). Se repite cada frame.
- Animación de ambiente **barata**: 2–6 elementos que se mueven (nubes que derivan, olas
  con `phase`, peces al fondo). Nada de cientos de partículas: máximo ~150 cosas pequeñas
  en pantalla a la vez.
- Recortar polígonos (`clip` en `DrawKit.hills`/`waves`) solo en `_draw_scenery`.
- Círculos ≤ 48 segmentos; `draw_circle` ya es barato. Evita capas a pantalla completa
  translúcidas apiladas en `_draw()` (cada una es relleno de 1280x720).
- Sin shaders, sin texturas grandes, sin luces ni partículas de GPU.

## 4. Kit de dibujo (`core/draw_kit.gd`, clase `DrawKit`)

Todas reciben el `CanvasItem` donde dibujar (en `_draw` es `self`; en `_draw_scenery`, `ci`):

| Función | Para |
|---|---|
| `arena_frame(ci, rect, top, bottom)` / `arena_border(ci, rect)` | marco de la arena (fondo y borde) |
| `rounded_rect_points(rect, radio)` | contorno para recortar decorado a la arena |
| `vgradient`, `rounded_vgradient` | degradados |
| `hills(ci, rect, y, amp, color, fase, ondas, clip)` | colinas |
| `waves(ci, rect, y, amp, color, fase, largo, clip)` | agua y olas (animable con `fase`) |
| `cloud`, `sun`, `flower`, `grass_tufts` | decorado |
| `glossy_ball`, `player_ball`, `soft_shadow`, `ellipse` | personajes y objetos |
| `star`, `sparkle` | premios y brillos |
| `panel`, `outlined_text` | carteles y textos sobre fondos con color |

## 5. Miniatura del selector (`minigames/<id>/thumb.gd`)

Cada juego trae su "imagen de canal", dibujada por código:

```gdscript
extends RefCounted
## Miniatura de "<juego>" para el selector.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("..."), Color("..."))
	# ...una escena reconocible del juego, con sus elementos clave en grande
```

- `r` mide unos 248x138. Dibuja **solo dentro de `r`**; las esquinas las redondea el selector.
- Una composición clara: el ambiente del juego + 1–3 elementos protagonistas grandes
  (p. ej. dos bolas de jugador y el objeto del juego). Sin texto.
- Se dibuja una vez al entrar en el selector: puede ser algo más detallada que un frame del juego.

## 6. Referencia

`minigames/estrellas/` (escenario en `_draw_scenery` + `thumb.gd`).

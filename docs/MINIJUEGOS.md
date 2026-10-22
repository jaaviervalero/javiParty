# Normas para crear minijuegos de javiParty

Estas normas son obligatorias. El ejemplo de referencia es `minigames/estrellas/estrellas.gd`:
léelo entero antes de empezar y copia su estructura.

## 1. Qué es un minijuego aquí

- Partida **corta** (30–60 s, nunca más de 90), para **1 a 4 jugadores** a la vez en la
  **misma pantalla** (sin pantalla dividida en este lote).
- Se entiende en **una frase**. Si necesitas dos, simplifícalo.
- Divertido desde el primer segundo, con algo de caos y remontadas posibles.
- Se juega con el **mando de javiParty** en el móvil (horizontal): **stick, cruceta, A y B**.
  - **No** se usan giroscopio, acelerómetro ni pantalla táctil.
  - **No** se usan −, + ni HOME: + es la pausa (la gestiona la base) y HOME el overlay de depuración.
  - Stick y cruceta deben valer los dos para moverse (patrón: `p.stick()` si no es cero, si no `p.dpad()`).
  - **A** es la acción principal; **B** la secundaria (o nada).
- Estética propia, clara y amable (blancos, grises suaves, acento cian y el color de cada
  jugador). Nada de personajes, nombres, música o estética de Nintendo ni de ninguna marca.

## 2. Estructura de archivos

```
minigames/<id>/<id>.tscn   # nodo raíz Node2D con el script <id>.gd
minigames/<id>/<id>.gd     # extends MinigameBase
minigames/<id>/thumb.gd    # miniatura del selector (ver docs/ESTETICA.md)
minigames/<id>/*.gd        # (opcional) scripts auxiliares, cargados con preload()
```

- `<id>` en minúsculas, sin espacios ni tildes (`duelo`, `sumo`…).
- La escena es mínima; todo se crea por código:
  ```
  [gd_scene format=3]

  [ext_resource type="Script" path="res://minigames/<id>/<id>.gd" id="1"]

  [node name="<NombreEnCamelCase>" type="Node2D"]
  script = ExtResource("1")
  ```
- **No** toques nada fuera de `minigames/<id>/` (ni core, ni ui, ni el registro, ni
  project.godot). Si crees que hace falta algo en la base, dilo en tu informe.
- **No** uses `class_name` en los minijuegos (chocarían entre sí). Clases internas
  (`class Bola:`) sí.

## 3. La clase base (`core/minigame_base.gd`)

La base hace la intro (título, frase, controles, "pulsad A"), la cuenta atrás, el
temporizador, el HUD (título, tiempo, puntuaciones), la pausa y los resultados.
El juego **solo** sobrescribe estos hooks:

| Hook | Cuándo | Para qué |
|---|---|---|
| `_configure()` | antes de todo | `title`, `instructions`, `controls`, `duration`, `lower_is_better`, `show_scores` |
| `_setup()` | `players` ya relleno | crear el escenario y el estado de cada jugador |
| `_game_start()` | tras "¡YA!" | arrancar lo que dependa de empezar |
| `_game_process(delta)` | cada frame jugando | **toda** la lógica |
| `_game_end()` | al acabar | último ajuste de `scores` |
| `format_score(v)` | HUD y resultados | p. ej. `"%.2f s" % v` |
| `_draw_scenery(ci)` | una vez (y con `redraw_scenery()`) | escenario estático, dibujando sobre `ci` |
| `_draw()` | cada frame (la base llama a `queue_redraw()`) | dibujar lo que se mueve |

Prohibido definir `_ready`, `_process`, `_physics_process`, `_input` o `_unhandled_input`.

API disponible: `players: Array[Player]`, `scores` (vía `add_score(p, n)`,
`set_score(p, v)`, `get_score(p)`), `is_playing()`, `finish()` (terminar ya),
`time_left`, `elapsed`, `ARENA` (Rect2(32, 96, 1216, 600): zona de juego bajo el HUD),
`loc({"es": ..., "en": ...})`, `font(peso)`, `draw_text_centered(texto, centro, tamaño, color)`.

Puntuación: al acabar se ordena a los jugadores por `scores` (mayor gana; con
`lower_is_better = true`, menor gana). Los empates comparten puesto. Asegúrate de que la
puntuación final refleje de verdad quién ha ganado (p. ej. en eliminación: puntos por
ronda sobrevivida o por orden de eliminación).

**Siempre** hay límite de tiempo (`duration`). Los juegos de rondas o eliminación llaman a
`finish()` cuando ya está decidido, pero el tiempo los corta igual si se alarga.

## 4. Entrada (`Player`)

```gdscript
p.stick()                 # Vector2 analógico, -1..1, Y hacia abajo, ya con zona muerta
p.dpad()                  # Vector2 de la cruceta (-1/0/1), Y hacia abajo
p.is_pressed(Pad.A)       # mantenido
p.just_pressed(Pad.A)     # pulsado este frame
p.just_released(Pad.B)
p.is_connected_now()      # si se desconecta, sus entradas valen 0; el juego sigue
p.color, p.index (0..3)
```

El stick también activa los bits de la cruceta (Pad.UP…), así que en juegos digitales
basta con `just_pressed(Pad.LEFT)`.

## 5. Dibujo y rendimiento (Android TV con Mali-G31 y 1–2 GB)

- Resolución lógica **1280x720**. La franja superior de 84 px es del HUD.
- Dibuja con `_draw()` (`draw_circle`, `draw_rect`, `draw_colored_polygon`,
  `draw_style_box(WiiTheme.panel_style(...))`, `draw_arc`, `draw_polyline`…). Pocas
  entidades como **datos** (arrays o clases internas), no un nodo por entidad.
- Si usas nodos, que sean pocos (menos de ~100 en total). **Nada** de shaders, GPUParticles,
  luces, post-procesado, texturas grandes ni assets externos. Física: a mano (como en el
  ejemplo), no RigidBody.
- Polígonos de pocos lados (círculos de ≤ 48 segmentos). Sin bucles O(n²) grandes.
- Todo depende de `delta`: nada de "x por frame".

## 6. Estilo visual

**Lee `docs/ESTETICA.md`**: cada juego tiene su ambiente, con `DrawKit` y `_draw_scenery`.

- Fondo general: lo pone la base (claro con rayas). Encima, la arena con su ambiente:
  `DrawKit.arena_frame(ci, ARENA, cielo, suelo)` ... decorado ... `DrawKit.arena_border(ci, ARENA)`.
- Colores: `p.color` para todo lo de cada jugador; `WiiTheme.TEXT`, `TEXT_SOFT`, `ACCENT`,
  `ACCENT_DARK`, `PANEL_BORDER`, `SHADOW`. Amarillo `Color("ffd34d")` para premios y rojo
  suave `Color("e25555")` para peligro.
- Formas redondeadas con brillo (círculo + reflejo blanco translúcido arriba a la
  izquierda), sombras suaves (`WiiTheme.SHADOW`), animaciones de "squash" y rebote.
  Que se lea desde el sofá: elementos grandes y texto de al menos 20 px.
- Cada jugador lleva su **número** dentro o encima (`draw_text_centered`).
- Texto solo con letras, números y signos normales: **nada** de emojis, flechas Unicode,
  ★, etc. (Nunito no los tiene y en la tele salen cuadros).

## 7. Sonido

`Sfx.play(nombre, tono := 1.0)` con: `move`, `accept`, `back`, `pop`, `star`, `dash`,
`wave`, `join`, `leave`. Varía el tono para dar vida (`randf_range(0.9, 1.1)`). Sin
archivos de audio.

## 8. Textos

Todos los textos visibles en **español e inglés** con `loc({"es": ..., "en": ...})`.
`instructions` es UNA frase. `controls` lista lo que se usa:
`[["stick", {...}], [Pad.A, {...}], [Pad.B, {...}]]`.

## 9. Código

- GDScript 4 **tipado** (`var x := 0.0`, `-> void`), tabuladores, constantes en
  MAYÚSCULAS para todo número "mágico" (velocidades, tiempos, tamaños).
- Comentarios en español, breves, solo donde no sea obvio.
- Sin `print()` en el juego terminado.

## 10. Prueba obligatoria

```bash
tools/smoke.sh <id>
```

Juega la partida entera con 4 bots y con 1 bot que pulsan al azar, a velocidad x4.
Tiene que decir `OK` en los dos casos, **sin ningún** `SCRIPT ERROR`, `Parse Error` ni
`ERROR`. Si los bots al azar no pueden acabar una partida, el límite de tiempo la acaba.
Comprueba también mentalmente qué pasa con 1 jugador y con 4.

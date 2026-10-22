# Reglas de migración a Godot 3.6 (GLES2)

El proyecto pasa de Godot 4.7 (GDScript 2) a **Godot 3.6.3** para que arranque en la
tele (Mali-470, OpenGL ES 2.0). Este documento es la referencia obligatoria al tocar
cualquier `.gd` o `.tscn`. El ejemplo ya migrado es `core/minigame_base.gd` +
`minigames/estrellas/estrellas.gd`: si dudas, cópialo de ahí.

## Comandos

```bash
godot3 --version                     # 3.6.3
godot3 --headless --path . --editor --quit   # importar (crea .import)
tools/smoke.sh <id>                 # test de un minijuego (usa godot3)
godot3 --headless --path . -s tests/run_tests.gd
```

Ojo con dos trampas del modo headless:

- `--editor --quit` **aborta el escaneo** si tarda (`Scan thread aborted`) y, cuando
  eso pasa, no llega a escribir la caché de `class_name`
  (`.import/global_script_class_cache.cfg`). Sin ese fichero fallan en cascada todos
  los scripts (`The identifier "DrawKit" isn't declared...`). Si se pierde, relanza
  `godot3 --path . --editor` **sin** `--quit` y espera a que aparezca.
  `tools/smoke.sh` solo importa si la caché no existe.
- `--check-only -s <script>` **no registra los autoloads**: da falsos positivos
  (`The identifier "Fonts"/"Sfx"/"DSUClient" isn't declared in the current scope`).
  Úsalos solo para descartar errores de sintaxis/tipos, no como criterio final.

## GDScript: diferencias obligatorias

| Godot 4 | Godot 3.6 |
|---|---|
| `extends RefCounted` | `extends Reference` |
| `Array[T]` / `var a: Array[Foo]` | `Array` (sin tipado de elementos) |
| `static var x` | **no existe**: usa un campo en un autoload (`GameFlow`, `Settings`) |
| `func(x): ...` (lambda) | no existe: método con nombre + `funcref(self, "_metodo")` o `connect` con binds |
| `signal s(a: Array)` | `signal s(a)` |
| `s.emit(x)` | `emit_signal("s", x)` |
| `obj.sig.connect(cb)` | `obj.connect("sig", self, "_metodo")` |
| `obj.sig.connect(cb.bind(x))` | `obj.connect("sig", self, "_metodo", [x])` |
| `await x` | `yield(x, "signal")` |
| `await get_tree().create_timer(s).timeout` | `yield(get_tree().create_timer(s), "timeout")` |
| `super.metodo()` | `.metodo()` |
| `Callable` | `FuncRef` (`funcref`) |
| `clampf/lerpf/minf/maxf/absf/signf` | `clamp/lerp/min/max/abs/sign` |
| `randf_range(a,b)` / `randi_range(a,b)` | `rand_range(a,b)` / `randi() % n` (¡no existen globales!) |
| `Array.filter(...)` | bucle con `if` y un array auxiliar |
| `get_viewport().set_input_as_handled()` | `get_tree().set_input_as_handled()` |
| `Packed*Array` | `Pool*Array` (`PoolByteArray`, `PoolVector2Array`, `PoolColorArray`, `PoolStringArray`, `PoolIntArray`, `PoolRealArray`) |
| `Vector2i` | `Vector2` |
| `PackedByteArray.slice(a,b)` | `PoolByteArray.subarray(a,b)` |
| `String.to_ascii_buffer()` | `String.to_ascii()` |
| `String.hex_decode()` / `PoolByteArray.hex_encode()` | no existen: helpers propios |
| `JSON.parse_string(s)` | `JSON.parse(s).result` |
| `FileAccess.get_file_as_string(p)` | `File.new().get_as_text()` |
| `OS.get_cmdline_user_args()` | no existe: filtra `OS.get_cmdline_args()` tras `--` |
| `Node.process_mode = PROCESS_MODE_ALWAYS` | `pause_mode = Node.PAUSE_MODE_PROCESS` |
| `Node.process_mode = PROCESS_MODE_DISABLED` | `pause_mode = Node.PAUSE_MODE_STOP` |
| `queue_redraw()` | `update()` |
| `PackedScene.instantiate()` | `PackedScene.instance()` |
| `get_tree().change_scene_to_file(p)` | `get_tree().change_scene(p)` |
| `Time.get_ticks_msec/usec()` | `OS.get_ticks_msec/usec()` |
| `Time.get_time_string_from_system()` | `OS.get_time()` (Dictionary hour/minute) |
| `find_child(name, true, false)` | `find_node(name, true, false)` |
| `Vector2.from_angle(a)` | `Vector2(cos(a), sin(a))` |
| `Node.NOTIFICATION_WM_GO_BACK_REQUEST` | igual |
| `InputEventKey.physical_keycode/keycode` | `physical_scancode` / `scancode` (tipo `int`) |

### Bucles y `match`
`for i in n:` sigue valiendo (int). `match` igual. `:=` sigue valiendo.
Constantes: `const X := 1.0` vale; `Color("bfe6fb")` vale.

## Nodos y Control

| Godot 4 | Godot 3.6 |
|---|---|
| `Control.custom_minimum_size` | `rect_min_size` |
| `Control.position` | `rect_position` |
| `Control.size` | `rect_size` |
| `Control.scale` | `rect_scale` |
| `Control.pivot_offset` | `rect_pivot_offset` |
| `Control.offset_left/top/right/bottom` | `margin_left/top/right/bottom` |
| `set_anchors_preset(Control.PRESET_FULL_RECT)` | `set_anchors_and_margins_preset(Control.PRESET_WIDE)` |
| `set_anchors_preset(PRESET_TOP_WIDE)` | `set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)` |
| `add_theme_font_override("font", f)` | `add_font_override("font", f)` |
| `add_theme_color_override("font_color", c)` | `add_color_override("font_color", c)` |
| `add_theme_constant_override("separation", n)` | `add_constant_override("separation", n)` |
| `add_theme_stylebox_override("panel", s)` | `add_stylebox_override("panel", s)` |
| `add_theme_font_size_override("font_size", n)` | **no existe**: la fuente ya lleva el tamaño |
| `Label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER` | `align = Label.ALIGN_CENTER` |
| `Label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER` | `valign = Label.VALIGN_CENTER` |
| `Label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART` | `autowrap = true` |
| `Label.auto_translate_mode = ...` | quitar (no existe) |
| `l.grab_focus.call_deferred()` | `l.call_deferred("grab_focus")` |
| `resized.connect(queue_redraw)` | `connect("resized", self, "update")` |
| `TextureRect.expand_mode = EXPAND_IGNORE_SIZE` | `expand = true` |
| `TextureRect.stretch_mode = STRETCH_KEEP_ASPECT_CENTERED` | igual |
| `ScrollContainer.horizontal_scroll_mode` | `scroll_horizontal_enabled = false` |
| `ScrollContainer.vertical_scroll_mode` | `scroll_vertical_enabled` |
| `MarginContainer` `margin_*` override | `add_constant_override("margin_left", n)` |
| `Control.get_theme_default_font()` | `Fonts.get_font(weight, size)` |
| `panel.reset_size()` | ajustar `rect_min_size` a mano |

### Tweens
No hay `create_tween()`. Usa `core/anim.gd`:

```gdscript
Anim.scale_to(control, Vector2(1.6, 1.6), Vector2.ONE, 0.25)  # rect_scale
Anim.node_scale_to(node2d, ...)                                # scale
Anim.fade_out(control, 0.4, 0.15)                              # modulate:a y queue_free
```

## Fuentes y texto (lo más delicado)

En Godot 3.6 **el tamaño va dentro de la fuente** (`DynamicFont.size`). No existe
`draw_string(..., size, color)` ni `get_string_size(text, ..., size)`.

```gdscript
# Tema: fuente ya dimensionada (cacheada por peso+tamaño)
var f := Fonts.get_font(800, 30)          # 400/600/700/800/900
label.add_font_override("font", f)

# Dibujo
var f := Fonts.get_font(800, 30)
var ts := f.get_string_size(texto)        # sin argumentos extra
ci.draw_string(f, pos, texto, color)      # sin alineación/tamaño
```

En `MinigameBase` hay atajos equivalentes:

```gdscript
font(weight := 800, size := 24) -> DynamicFont
draw_text_centered(texto, centro, size, color, weight := 800)
```

`DrawKit.outlined_text(ci, weight, center, text, size, color, outline, outline_size)`
dibuja texto con contorno.

## Escenas `.tscn`

Formato 2 (el de Godot 3), ids sin comillas:

```
[gd_scene load_steps=2 format=2]

[ext_resource path="res://minigames/sumo/sumo.gd" type="Script" id=1]

[node name="Sumo" type="Node2D"]
script = ExtResource( 1 )
```

Un `Control` raíz a pantalla completa:

```
[node name="MainMenu" type="Control"]
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource( 1 )
```

## Temas

`ThemeDB` no existe. En cada pantalla raíz (`main_menu`, `minigame_select`) se hace
`theme = WiiTheme.build()`. Los `Label`/`Button` creados por código usan overrides
(`add_font_override`, etc.). `Theme.set_font_size` no existe: usa
`theme.set_font("font", "LineEdit", Fonts.get_font(600, 26))`.

## Rendimiento / renderer

- `GLES2`, sin shaders ni partículas. Lo dibujado por código funciona igual.
- `CanvasItem.draw_string`/`draw_polygon`/`draw_colored_polygon`/`draw_style_box` existen.
- `draw_string_outline` **no** existe (usa `DrawKit.outlined_text`).
- El marco de la arena, `DrawKit`, etc. se portan sin cambios salvo lo de esta tabla.

## Clases globales

`class_name` sigue valiendo (el proyecto debe importarse una vez con el editor headless).
Autoloads: `Settings`, `Fonts`, `Sfx`, `DSUClient`, `NetworkScanner`, `PlayerManager`,
`GameFlow`, `DebugOverlay`. `MinigameBase.headless_test` ya no existe: es
`Settings.headless_test` (lo usan los tests).

## API que no existe en 3.6.3 y su sustituto

Todo esto se comprobó ejecutando el motor, no leyendo docs. Los errores de *tipo*
salen en el parseo (`--check-only`), pero los de *método* solo aparecen al ejecutar:
por eso `tools/smoke.sh` es la prueba de verdad.

### Tipos básicos

| No existe | Usa |
|---|---|
| `Color.lerp(c, t)`, `Vector2.lerp(v, t)` | `.linear_interpolate(c, t)` |
| `Vector2.orthogonal()` | `.tangent()` |
| `Vector2.from_angle(a)` | `Vector2(cos(a), sin(a))` |
| `Array.is_empty()`, `Dictionary.is_empty()` | `.empty()` |
| `Array.reverse()` | `.invert()` |
| `Array.remove_at(i)` | `.remove(i)` |
| `Array.slice(begin)` (un solo argumento) | `.slice(begin, end)` |
| `Array.filter/map(...)` | bucle manual |
| `sort_custom(func(a, b): ...)` | `sort_custom(self, "_cmp")` con método con nombre |
| `Rect2.intersection(b)` | `.clip(b)` |
| `maxi/mini/absi/clampi` | `max/int(...)`/`max`/`min`/`abs`/`clamp` |
| `String.unicode_at(i)` | no hay: usa el código literal o `ord()` |
| `String.hex_to_int()` con "0x" o longitudes raras | decodifica a mano (ver `tests/run_tests.gd::_unhex`) |
| `seed` como nombre de parámetro | es palabra reservada: `seed_value` |

### Pool arrays

| No existe | Usa |
|---|---|
| `PoolByteArray.duplicate()` (ni `PoolVector2Array.duplicate()`) | `PoolByteArray(x)` / `PoolVector2Array(x)` |
| `subarray(a, b)` con `b` exclusivo | **`b` es inclusivo**: `subarray(a, b - 1)`; fuera de rango da error |
| `encode_u16/u32/...` y `decode_*` | no existen: `StreamPeerBuffer` (LE) o helpers `_u16_at/_u32_at` |
| `to_ascii_buffer()` | `String.to_ascii()` |

### Control / tema

| No existe | Usa |
|---|---|
| `StyleBox.set_content_margin_all(n)` | `content_margin_left/right/top/bottom = n` |
| `BoxContainer.ALIGNMENT_*` | `BoxContainer.ALIGN_CENTER/ALIGN_BEGIN/ALIGN_END` |
| `Control.clip_contents` | `rect_clip_content` |
| `Control.z_index` (sí en `Node2D`) | `raise()` / `move_child()` |
| `CanvasItem.texture_filter` y `TEXTURE_FILTER_*` | filtro en el `.import` (`flags/filter=false`) |
| `Tween.transition_type/ease_type` (propiedades) | van como argumentos de `interpolate_property(...)` |
| `Tween.stop()` | `stop_all()` |
| `draw_set_transform(pos)` con 1 argumento | `draw_set_transform(pos, 0.0, Vector2.ONE)` |
| `Geometry2D.intersect_polygons()` | `Geometry.intersect_polygons_2d()` |
| `draw_string(..., size, ...)` | tamaño dentro de la fuente (`Fonts.get_font`) |

## Prohibido en minijuegos

- `class_name` en `minigames/<id>/` (choca entre sí). Clases internas (`class Ball:`) sí.
- `static var`, lambdas, `await`, `Array[T]`, `Vector2i`, `Packed*Array`.
- Tocar nada fuera de `minigames/<id>/`.

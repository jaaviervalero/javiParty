class_name WiiBackground
extends Control
## Fondo de las pantallas: degradado vertical claro con rayas horizontales finas
## y una franja ondulada suave abajo. Se dibuja solo al cambiar de tamaño.

const STRIPE_STEP := 4


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([WiiTheme.BG_TOP, WiiTheme.BG_TOP, WiiTheme.BG_BOTTOM, WiiTheme.BG_BOTTOM]))
	var y := 0.0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), WiiTheme.STRIPE, 1.0)
		y += STRIPE_STEP
	# Onda inferior: dos bandas cian translúcidas.
	_wave(h - 70.0, 18.0, Color(WiiTheme.ACCENT, 0.10))
	_wave(h - 48.0, 12.0, Color(WiiTheme.ACCENT, 0.14))


func _wave(base_y: float, amp: float, color: Color) -> void:
	var pts := PackedVector2Array()
	var steps := 48
	for i in steps + 1:
		var x := size.x * i / steps
		pts.append(Vector2(x, base_y + sin(i / float(steps) * TAU * 1.2) * amp))
	pts.append(Vector2(size.x, size.y))
	pts.append(Vector2(0, size.y))
	draw_colored_polygon(pts, color)

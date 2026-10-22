class_name WiiBackground
extends Control
## Fondo de las pantallas: degradado vertical claro con rayas horizontales finas
## y una franja ondulada suave abajo. Se dibuja solo al cambiar de tamaño.

const STRIPE_STEP := 4


func _ready() -> void:
	set_anchors_and_margins_preset(Control.PRESET_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("resized", self, "update")


func _draw() -> void:
	var w := rect_size.x
	var h := rect_size.y
	draw_polygon(
		PoolVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PoolColorArray([WiiTheme.BG_TOP, WiiTheme.BG_TOP, WiiTheme.BG_BOTTOM, WiiTheme.BG_BOTTOM]))
	var y := 0.0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), WiiTheme.STRIPE, 1.0)
		y += STRIPE_STEP
	# Onda inferior: dos bandas cian translúcidas.
	_wave(h - 70.0, 18.0, Color(WiiTheme.ACCENT, 0.10))
	_wave(h - 48.0, 12.0, Color(WiiTheme.ACCENT, 0.14))


func _wave(base_y: float, amp: float, color: Color) -> void:
	var pts := PoolVector2Array()
	var steps := 48
	for i in steps + 1:
		var x: float = rect_size.x * i / steps
		pts.append(Vector2(x, base_y + sin(i / float(steps) * TAU * 1.2) * amp))
	pts.append(Vector2(rect_size.x, rect_size.y))
	pts.append(Vector2(0, rect_size.y))
	draw_colored_polygon(pts, color)

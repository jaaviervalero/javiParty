extends Reference
## Miniatura de "Al compás" para el selector: escenario de concierto con
## guirnalda, altavoces y las dos formas de nota llegando a la línea.

const BULB_COLORS = [
	Color("ffb3a7"), Color("ffe08a"), Color("a9ddf5"), Color("c3ecb0"), Color("e0c8f5"),
]


static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("e4ecfb"), Color("fff0da"))
	# Guirnalda de bombillas.
	var pts := PoolVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		pts.append(Vector2(lerp(r.position.x + 8, r.end.x - 8, t),
				r.position.y + 10 + sin(t * PI) * 9))
	ci.draw_polyline(pts, Color("cfd8e0"), 2.0, true)
	for i in pts.size():
		var c: Color = BULB_COLORS[i % BULB_COLORS.size()]
		ci.draw_circle(pts[i] + Vector2(0, 5), 5.5, Color(c, 0.22))
		ci.draw_circle(pts[i] + Vector2(0, 5), 3.5, c)
	# Altavoces redondeados en las esquinas de abajo.
	_speaker(ci, Vector2(r.position.x + 26, r.end.y - 22))
	_speaker(ci, Vector2(r.end.x - 26, r.end.y - 22))
	# Línea de golpeo.
	var hx := r.position.x + r.size.x * 0.34
	ci.draw_line(Vector2(hx, r.position.y + 24), Vector2(hx, r.end.y - 12),
			Color(WiiTheme.ACCENT, 0.6), 4.0, true)
	ci.draw_line(Vector2(hx, r.position.y + 24), Vector2(hx, r.end.y - 12),
			Color(1, 1, 1, 0.8), 1.5, true)
	# Notas protagonistas: círculo y rombo camino de la línea.
	_note_circle(ci, Vector2(r.position.x + r.size.x * 0.6, r.position.y + r.size.y * 0.44),
			15, Color("2fa8e0"))
	_note_diamond(ci, Vector2(r.position.x + r.size.x * 0.76, r.position.y + r.size.y * 0.62), 17)


static func _note_circle(ci: CanvasItem, c: Vector2, rad: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0, 3), rad, Color(0.2, 0.3, 0.4, 0.14))
	ci.draw_circle(c, rad, col)
	ci.draw_circle(c + Vector2(-rad * 0.28, -rad * 0.3), rad * 0.34, Color(1, 1, 1, 0.5))
	ci.draw_arc(c, rad - 1.0, 0, TAU, 28, Color(1, 1, 1, 0.85), 2.5, true)


static func _note_diamond(ci: CanvasItem, c: Vector2, rad: float) -> void:
	var pts := PoolVector2Array()
	for i in 4:
		pts.append(c + Vector2.UP.rotated(i * TAU / 4.0) * rad)
	var shadow := PoolVector2Array()
	for p in pts:
		shadow.append(p + Vector2(0, 3))
	ci.draw_colored_polygon(shadow, Color(0.2, 0.3, 0.4, 0.14))
	ci.draw_colored_polygon(pts, WiiTheme.ACCENT_DARK)
	var inner := PoolVector2Array()
	for i in 4:
		inner.append(c + Vector2.UP.rotated(i * TAU / 4.0 + TAU / 8.0) * (rad * 0.42))
	ci.draw_colored_polygon(inner, Color(1, 1, 1, 0.55))
	var outline := PoolVector2Array(pts)
	outline.append(pts[0])
	ci.draw_polyline(outline, Color(1, 1, 1, 0.85), 2.5, true)


static func _speaker(ci: CanvasItem, center: Vector2) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color("b9c6d6")
	st.border_color = Color("93a4b8")
	st.set_border_width_all(2)
	st.set_corner_radius_all(7)
	ci.draw_style_box(st, Rect2(center - Vector2(17, 11), Vector2(34, 22)))
	ci.draw_circle(center, 6.5, Color("93a4b8"))
	ci.draw_circle(center, 4.0, Color("d6e0ea"))

extends RefCounted
## Miniatura de "Para el reloj" para el selector: reloj de bolsillo en el taller.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	# Pared clara con engranajes pastel.
	DrawKit.vgradient(ci, r, Color("f8f2e7"), Color("ecdcc6"))
	_gear(ci, r.position + Vector2(40.0, 40.0), 34.0, 9, 0.2, Color("cfe2da"))
	_gear(ci, r.position + Vector2(r.size.x - 38.0, 46.0), 26.0, 8, -0.15, Color("f0dcc6"))
	# Mesa de madera.
	ci.draw_rect(Rect2(r.position.x, r.end.y - 22.0, r.size.x, 22.0), Color("d8b184"))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 22.0, r.size.x, 6.0), Color("e8cba4"))
	ci.draw_line(Vector2(r.position.x + 30.0, r.end.y - 8.0),
			Vector2(r.position.x + 90.0, r.end.y - 8.0), Color("b98d60"), 2.0, true)
	# Reloj de bolsillo grande.
	var c := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.46)
	ci.draw_arc(c + Vector2(0, -46.0), 9.0, 0.0, TAU, 14, Color("c9a75a"), 4.0, true)
	ci.draw_rect(Rect2(c + Vector2(-7, -44.0), Vector2(14, 12)), Color("d3b268"))
	ci.draw_circle(c + Vector2(0, 4.0), 48.0, Color(0.5, 0.42, 0.32, 0.14))
	ci.draw_circle(c, 47.0, Color("dcd0bd"))
	ci.draw_circle(c, 41.0, Color("fff8ea"))
	ci.draw_circle(c + Vector2(-15, -16), 12.0, Color(1, 1, 1, 0.55))
	for i in 12:
		var a := TAU * float(i) / 12.0
		ci.draw_line(c + Vector2(cos(a) * 34.0, sin(a) * 34.0),
				c + Vector2(cos(a) * 38.0, sin(a) * 38.0), Color(0.48, 0.44, 0.38, 0.45), 2.0, true)
	ci.draw_line(c, c + Vector2(-16, -14), Color("5b6670"), 3.0, true)
	ci.draw_line(c, c + Vector2(11, -24), Color("5b6670"), 2.5, true)
	ci.draw_circle(c, 4.0, Color("b8891b"))


static func _gear(ci: CanvasItem, center: Vector2, rad: float, teeth: int, angle: float,
		col: Color) -> void:
	var pts := PackedVector2Array()
	for i in teeth * 2:
		var a := angle + TAU * float(i) / float(teeth * 2)
		pts.append(center + Vector2.from_angle(a) * (rad if i % 2 == 0 else rad * 0.78))
	ci.draw_colored_polygon(pts, col)
	ci.draw_circle(center, rad * 0.55, col.darkened(0.05))
	ci.draw_circle(center, rad * 0.22, Color.WHITE)

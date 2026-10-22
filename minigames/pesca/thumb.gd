extends Reference
## Miniatura de "A pescar" para el selector: muelle, pescador, caña y pez.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	# Cielo y agua.
	DrawKit.vgradient(ci, r, Color("eef8fd"), Color("cfeaf3"))
	var water_y := r.position.y + r.size.y * 0.4
	DrawKit.vgradient(ci, Rect2(r.position.x, water_y, r.size.x, r.end.y - water_y),
			Color("d9f0f8"), Color("b6dfec"))
	# Orilla de arena con juncos.
	# Recortada a la miniatura: la elipse sobresale por la izquierda.
	var shore := PoolVector2Array()
	for i in 24:
		var a = TAU * i / 24.0
		shore.append(Vector2(r.position.x + 6.0, r.end.y - 22.0) + Vector2(cos(a) * 52.0, sin(a) * 36.0))
	DrawKit.clipped_polygon(ci, shore, PoolVector2Array([r.position, Vector2(r.end.x, r.position.y),
			r.end, Vector2(r.position.x, r.end.y)]), Color("f0e0b8"))
	for i in 4:
		var bx = r.position.x + 15.0 + i * 9.0
		var tip := Vector2(bx + (i % 2) * 4.0, water_y - 18.0 - (i % 3) * 8.0)
		ci.draw_line(Vector2(bx, r.end.y - 26.0), tip, Color("7fae6a"), 2.0, true)
		DrawKit.ellipse(ci, tip + Vector2(0, 3.0), Vector2(3.0, 7.0), Color("9a6b4a"))
	# Nenúfares.
	for p in [Vector2(r.position.x + 42.0, r.end.y - 16.0),
			Vector2(r.position.x + 210.0, r.position.y + 112.0)]:
		DrawKit.ellipse(ci, p, Vector2(18.0, 7.0), Color("6fb862"))
		DrawKit.ellipse(ci, p + Vector2(0, -2.0), Vector2(15.0, 5.5), Color("8fce7e"))
	# Muelle de madera.
	var dock_y := r.position.y + 26.0
	ci.draw_rect(Rect2(r.position.x, dock_y, r.size.x, 14.0), Color("e6d3b3"))
	for i in 4:
		ci.draw_line(Vector2(r.position.x, dock_y + 4.0 + i * 4.0),
				Vector2(r.end.x, dock_y + 4.0 + i * 4.0), Color("cdb894"), 1.5)
	# Pescador con caña y sedal.
	var fisher := Vector2(r.position.x + 62.0, dock_y - 2.0)
	DrawKit.glossy_ball(ci, fisher, 18.0, Color("2fa8e0"))
	var rod_tip := Vector2(r.position.x + 128.0, r.position.y + 44.0)
	ci.draw_line(fisher + Vector2(8, -8), rod_tip, Color("a77a4e"), 3.0, true)
	var hook := Vector2(r.position.x + 140.0, r.position.y + 86.0)
	ci.draw_line(rod_tip, hook, Color("7f8c96"), 1.5, true)
	# Pez grande junto al anzuelo.
	var fish := Vector2(r.position.x + 164.0, r.position.y + 92.0)
	DrawKit.ellipse(ci, fish, Vector2(26.0, 14.0), Color("f7c58e"))
	ci.draw_colored_polygon(PoolVector2Array([
		fish + Vector2(20, 0), fish + Vector2(34, -12), fish + Vector2(34, 12)]),
		Color("e9ae72"))
	ci.draw_circle(fish + Vector2(-12, -4), 4.0, Color(1, 1, 1, 0.9))
	ci.draw_circle(fish + Vector2(-11, -4), 2.0, Color("2c3540"))

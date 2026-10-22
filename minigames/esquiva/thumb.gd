extends Reference
## Miniatura de "Esquiva": pista de parqué con bolas rojas y un jugador esquivando.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("ecd6b0"), Color("e3c79c"))
	# Bandas de parqué.
	var band := r.size.y / 6.0
	for i in 6:
		var y = r.position.y + i * band
		if i % 2 == 0:
			ci.draw_rect(Rect2(r.position.x, y, r.size.x, band), Color(0.95, 0.86, 0.7, 0.35))
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color("d3b485", 0.35), 1.0)
		var x := r.position.x + (26.0 if i % 2 == 0 else 70.0)
		while x < r.end.x:
			ci.draw_line(Vector2(x, y), Vector2(x, y + band), Color("d3b485", 0.3), 1.0)
			x += 90.0
	# Pared acolchada arriba y líneas de pista.
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 18.0)), Color("bcd7e6"))
	ci.draw_line(Vector2(r.position.x, 18.0 + r.position.y),
			Vector2(r.end.x, 18.0 + r.position.y), Color(1, 1, 1, 1), 2.0)
	var inner := Rect2(r.position + Vector2(16, 28), r.size - Vector2(32, 44))
	ci.draw_rect(inner, Color(1, 1, 1, 0.7), false, 3.0)
	ci.draw_line(Vector2(inner.position.x, inner.get_center().y),
			Vector2(inner.end.x, inner.get_center().y), Color(1, 1, 1, 0.7), 3.0)
	ci.draw_arc(inner.get_center(), 28.0, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 3.0, true)
	# Proyectiles rojos con estela.
	var shots: Array = [Vector2(58, 52), Vector2(196, 44), Vector2(178, 112)]
	for s in shots:
		var p = r.position + s
		ci.draw_circle(p - Vector2(16, 4), 5.0, Color("e25555", 0.18))
		ci.draw_circle(p - Vector2(9, 2), 7.0, Color("e25555", 0.3))
		ci.draw_circle(p, 10.0, Color("e25555"))
		ci.draw_circle(p + Vector2(-3, -3), 4.0, Color(1, 1, 1, 0.5))
	# Jugador esquivando.
	DrawKit.glossy_ball(ci, r.position + Vector2(r.size.x * 0.5, r.size.y * 0.58), 19.0,
			Color("2fa8e0"))
	ci.draw_arc(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.58), 26.0, 0.0, TAU, 32,
			Color(Color("33b5e5"), 0.8), 3.0, true)

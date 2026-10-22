extends Reference
## Miniatura de "¡Desenfunda!" para el selector: oeste al mediodía y señal.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	# Cielo cálido y sol.
	DrawKit.vgradient(ci, r, Color("ffe4bd"), Color("fff6e6"))
	DrawKit.sun(ci, r.position + Vector2(r.size.x - 38.0, 30.0), 18.0)
	# Mesetas y suelo de tierra.
	DrawKit.hills(ci, r, r.end.y - 34.0, 9.0, Color("ecc9ad"), 0.7, 1.5)
	DrawKit.ellipse(ci, r.position + Vector2(74.0, r.size.y - 30.0), Vector2(40.0, 20.0),
			Color("e2b795"))
	DrawKit.hills(ci, r, r.end.y - 20.0, 6.0, Color("eed9b4"), 2.3, 1.2)
	# Cactus redondeado.
	var cb := Vector2(r.position.x + 40.0, r.end.y - 18.0)
	ci.draw_line(cb + Vector2(0, -52.0), cb, Color("9fd18a"), 14.0, true)
	ci.draw_circle(cb + Vector2(0, -52.0), 7.0, Color("9fd18a"))
	ci.draw_circle(cb, 7.0, Color("9fd18a"))
	ci.draw_line(cb + Vector2(0, -34.0), cb + Vector2(-18.0, -34.0), Color("7fbc72"), 9.0, true)
	ci.draw_line(cb + Vector2(-18.0, -34.0), cb + Vector2(-18.0, -48.0), Color("7fbc72"), 9.0, true)
	ci.draw_circle(cb + Vector2(-18.0, -48.0), 4.5, Color("7fbc72"))
	# Señal grande, lo que más destaca.
	var sig := r.position + Vector2(r.size.x * 0.6, r.size.y * 0.42)
	ci.draw_circle(sig + Vector2(0, 6.0), 32.0, Color(0.2, 0.3, 0.4, 0.16))
	ci.draw_circle(sig, 30.0, Color("ffd34d"))
	ci.draw_circle(sig + Vector2(-9.0, -11.0), 15.0, Color(1, 1, 1, 0.45))
	ci.draw_arc(sig, 30.0, 0.0, TAU, 32, Color("e8b21f"), 3.0, true)
	# Jugadores.
	DrawKit.glossy_ball(ci, r.position + Vector2(r.size.x * 0.36, r.size.y - 20.0), 15.0,
			Color("2fa8e0"))
	DrawKit.glossy_ball(ci, r.position + Vector2(r.size.x * 0.76, r.size.y - 22.0), 15.0,
			Color("ec5a5a"))

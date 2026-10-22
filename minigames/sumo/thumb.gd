extends Reference
## Miniatura de "Sumo de bolas": plataforma flotante sobre el mar de nubes.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("c8ecfb"), Color("f2fbff"))
	DrawKit.sun(ci, r.position + Vector2(r.size.x - 42, 32), 14)
	# Mar de nubes por debajo.
	DrawKit.cloud(ci, r.position + Vector2(46, r.size.y - 32), 0.55)
	DrawKit.cloud(ci, r.position + Vector2(r.size.x - 64, r.size.y - 20), 0.65)
	DrawKit.cloud(ci, r.position + Vector2(r.size.x * 0.18, r.size.y - 8), 0.5)
	# Plataforma con canto y anillos.
	var c := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.55)
	var pr := 46.0
	DrawKit.soft_shadow(ci, c + Vector2(0, 32), pr * 1.8)
	ci.draw_circle(c + Vector2(0, 8), pr - 1.0, Color("dcc6a3"))
	ci.draw_circle(c, pr, Color("fbf1dd"))
	ci.draw_arc(c, pr * 0.62, 0.0, TAU, 32, Color(DrawKit.WOOD_DARK, 0.2), 2.0, true)
	ci.draw_arc(c, pr * 0.32, 0.0, TAU, 32, Color(DrawKit.WOOD_DARK, 0.2), 2.0, true)
	DrawKit.ellipse(ci, c + Vector2(-14, -20), Vector2(22, 8), Color(1, 1, 1, 0.2))
	ci.draw_arc(c, pr - 1.0, 0.0, TAU, 40, Color(1, 1, 1, 1), 4.0, true)
	# Dos bolas empujándose.
	DrawKit.glossy_ball(ci, c + Vector2(-19, -7), 17.0, Color("2fa8e0"))
	DrawKit.glossy_ball(ci, c + Vector2(20, 4), 17.0, Color("ec5a5a"))

extends Reference
## Miniatura de "Rey de la colina" para el selector: pradera y zona dorada.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("b9e59b"), Color("8ed16f"))
	# Manchas de césped.
	DrawKit.ellipse(ci, r.position + r.size * Vector2(0.26, 0.3), Vector2(56.0, 24.0), Color("7cc45e", 0.3))
	DrawKit.ellipse(ci, r.position + r.size * Vector2(0.7, 0.7), Vector2(62.0, 26.0), Color("c6ea9f", 0.35))
	# Camino de tierra.
	var path_y := r.position.y + r.size.y * 0.78
	ci.draw_colored_polygon(PoolVector2Array([
		Vector2(r.position.x, path_y), Vector2(r.end.x, path_y - 14.0),
		Vector2(r.end.x, path_y + 12.0), Vector2(r.position.x, path_y + 26.0)]),
		Color("e8d6a8", 0.6))
	# Flores.
	for p in [Vector2(0.12, 0.72), Vector2(0.2, 0.5), Vector2(0.85, 0.36), Vector2(0.72, 0.82),
			Vector2(0.48, 0.16)]:
		DrawKit.flower(ci, r.position + r.size * p, 5.0, Color(1, 1, 1, 1))
	# Zona brillante.
	var c := r.position + Vector2(r.size.x * 0.48, r.size.y * 0.56)
	var zr := 34.0
	ci.draw_circle(c, zr * 1.3, Color("ffd34d", 0.12))
	ci.draw_circle(c, zr, Color("ffd34d", 0.22))
	ci.draw_circle(c, zr * 0.8, Color(1.0, 0.96, 0.74, 0.35))
	ci.draw_arc(c, zr, 0, TAU, 40, Color("ffd34d", 0.95), 6.0, true)
	ci.draw_arc(c, zr + 9.0, -0.4, 2.4, 28, Color("6fe3f5", 0.65), 4.0, true)
	# Dos bolas peleando por la zona.
	DrawKit.glossy_ball(ci, c + Vector2(-30.0, -18.0), 19.0, Color("2fa8e0"))
	DrawKit.glossy_ball(ci, c + Vector2(28.0, 20.0), 19.0, Color("ec5a5a"))

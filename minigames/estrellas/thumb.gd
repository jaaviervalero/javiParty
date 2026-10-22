extends Reference
## Miniatura de "Estrellas" para el selector: jardín al anochecer con estrellas y bolas.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("a7b6f2"), Color("f3d9ec"))
	for p in [Vector2(0.12, 0.2), Vector2(0.3, 0.12), Vector2(0.55, 0.28), Vector2(0.9, 0.5), Vector2(0.45, 0.08)]:
		ci.draw_circle(r.position + r.size * p, 2.0, Color(1, 1, 1, 0.85))
	ci.draw_circle(r.position + Vector2(r.size.x - 44, 36), 22, Color("fff6d8"))
	DrawKit.hills(ci, r, r.end.y - 38, 12, Color("c7b5ea"), 0.6, 1.8)
	DrawKit.hills(ci, r, r.end.y - 20, 8, Color("b3dc9c"), 2.2, 1.4)
	DrawKit.star(ci, r.position + Vector2(r.size.x * 0.5, r.size.y * 0.38), 26, 0.2)
	DrawKit.star(ci, r.position + Vector2(r.size.x * 0.18, r.size.y * 0.62), 15, -0.3)
	DrawKit.sparkle(ci, r.position + Vector2(r.size.x * 0.62, r.size.y * 0.2), 8)
	DrawKit.glossy_ball(ci, r.position + Vector2(r.size.x * 0.34, r.size.y * 0.62), 20, Color("2fa8e0"))
	DrawKit.glossy_ball(ci, r.position + Vector2(r.size.x * 0.72, r.size.y * 0.66), 20, Color("ec5a5a"))

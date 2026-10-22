extends Reference
## Miniatura de "Banderas en la playa": cielo, mar, arena, una bandera y dos
## corredores lanzándose a por ella.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	var sea_y := r.position.y + r.size.y * 0.34
	var sand_y := r.position.y + r.size.y * 0.58
	DrawKit.vgradient(ci, Rect2(r.position, Vector2(r.size.x, sea_y - r.position.y)),
			Color("d6effa"), Color("eef8fd"))
	DrawKit.sun(ci, r.position + Vector2(r.size.x - 36, 22), 13)
	DrawKit.cloud(ci, r.position + Vector2(56, 22), 0.55)
	DrawKit.vgradient(ci, Rect2(r.position.x, sea_y, r.size.x, sand_y - sea_y), Color("8fd3ec"), Color("b9e2f0"))
	DrawKit.waves(ci, Rect2(r.position.x, sea_y, r.size.x, sand_y - sea_y), sea_y + 14, 2.5,
			Color(1, 1, 1, 0.35), 0.5, 60.0)
	ci.draw_rect(Rect2(r.position.x, sand_y, r.size.x, r.end.y - sand_y), Color("f7e6c4"))
	ci.draw_rect(Rect2(r.position.x, sand_y, r.size.x, 6), Color("ecd2a3"))
	DrawKit.waves(ci, Rect2(r.position.x, sand_y - 3, r.size.x, 8), sand_y, 1.5, Color(1, 1, 1, 0.8), 1.0, 40.0)
	# Bandera clavada en la arena.
	var pole := Vector2(r.position.x + r.size.x * 0.74, r.end.y - 22)
	DrawKit.soft_shadow(ci, pole + Vector2(0, 2), 22)
	ci.draw_line(pole, pole + Vector2(0, -52), Color("8e99a3"), 3.0, true)
	ci.draw_colored_polygon(PoolVector2Array([pole + Vector2(1, -52), pole + Vector2(30, -44),
		pole + Vector2(1, -34)]), Color("33b5e5"))
	ci.draw_circle(pole + Vector2(0, -53), 3.5, DrawKit.GOLD)
	# Corredores: uno lanzado en plancha y otro detrás.
	DrawKit.glossy_ball(ci, Vector2(r.position.x + r.size.x * 0.48, r.end.y - 30), 17, Color("ec5a5a"))
	DrawKit.glossy_ball(ci, Vector2(r.position.x + r.size.x * 0.22, r.end.y - 26), 15, Color("2fa8e0"))
	for i in 3:
		ci.draw_line(Vector2(r.position.x + r.size.x * 0.36 - i * 4, r.end.y - 36 + i * 6),
				Vector2(r.position.x + r.size.x * 0.3 - i * 4, r.end.y - 36 + i * 6), Color(1, 1, 1, 0.8), 2.0, true)

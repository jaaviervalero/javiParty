extends Reference
## Miniatura de "Tanquecitos" para el selector: cajón de arena y dos tanques.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("f9ecc4"), Color("ecd39b"))
	# Piedrecitas y matojos del cajón.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 12:
		var p := r.position + Vector2(rng.randf_range(10.0, r.size.x - 10.0),
				rng.randf_range(10.0, r.size.y - 10.0))
		ci.draw_circle(p, rng.randf_range(1.2, 2.6), Color("c9b184", 0.6))
	DrawKit.grass_tufts(ci, r.position + Vector2(24.0, r.size.y - 12.0),
			r.position + Vector2(r.size.x - 24.0, r.size.y - 12.0), 7, DrawKit.GRASS_DARK, 5)
	# Bloque de madera en el centro.
	var blk := Rect2(r.position + Vector2(r.size.x * 0.5 - 30.0, r.size.y * 0.5 - 2.0),
			Vector2(60.0, 30.0))
	ci.draw_colored_polygon(DrawKit.rounded_rect_points(blk.grow(3.0), 9.0), DrawKit.WOOD_DARK)
	ci.draw_colored_polygon(DrawKit.rounded_rect_points(blk, 8.0), DrawKit.WOOD)
	ci.draw_line(blk.position + Vector2(8.0, 8.0), Vector2(blk.end.x - 8.0, blk.position.y + 8.0),
			Color(1, 1, 1, 0.4), 3.0, true)
	# Dos tanques de juguete apuntándose.
	_draw_tank(ci, r.position + Vector2(52.0, 94.0), Vector2(0.72, -1.0), Color("2fa8e0"))
	_draw_tank(ci, r.position + Vector2(r.size.x - 52.0, 44.0), Vector2(-1.0, 0.8), Color("ec5a5a"))
	# Bala entre los dos.
	DrawKit.soft_shadow(ci, r.position + Vector2(r.size.x * 0.5, 42.0), 18.0)
	ci.draw_circle(r.position + Vector2(r.size.x * 0.5, 38.0), 8.0, Color("ffd34d"))
	ci.draw_circle(r.position + Vector2(r.size.x * 0.5 - 2.0, 36.0), 3.0, Color(1, 1, 1, 0.7))


static func _draw_tank(ci: CanvasItem, pos: Vector2, aim: Vector2, color: Color) -> void:
	var n := aim.normalized()
	DrawKit.soft_shadow(ci, pos + Vector2(0, 20.0), 46.0)
	ci.draw_line(pos + n * 8.0, pos + n * 36.0, color.darkened(0.25), 11.0, true)
	ci.draw_circle(pos + n * 36.0, 5.5, color.darkened(0.18))
	ci.draw_circle(pos, 23.0, color.darkened(0.12))
	ci.draw_circle(pos + Vector2(0, -2.0), 21.0, color)
	ci.draw_circle(pos + Vector2(-7.0, -9.0), 8.0, Color(1, 1, 1, 0.42))

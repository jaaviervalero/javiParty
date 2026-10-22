extends RefCounted
## Miniatura de "Infla el globo" para el selector: feria y globo gigante.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("bfe9fb"), Color("fdf3e3"))
	# Césped.
	var gy := r.position.y + r.size.y * 0.78
	ci.draw_rect(Rect2(r.position.x, gy, r.size.x, r.end.y - gy), Color("a8dd8a"))
	ci.draw_rect(Rect2(r.position.x, r.end.y - 14.0, r.size.x, 14.0), Color("86c96a"))
	# Carpa de rayas al fondo.
	var cx := r.position.x + r.size.x * 0.6
	var body := Rect2(cx - 34.0, gy - 44.0, 68.0, 44.0)
	for i in 5:
		var x0 := body.position.x + body.size.x * float(i) / 5.0
		var x1 := body.position.x + body.size.x * float(i + 1) / 5.0
		ci.draw_rect(Rect2(x0, body.position.y, x1 - x0, body.size.y),
				Color("ffb1a8") if i % 2 == 0 else Color("fff4e0"))
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(body.position.x - 8.0, body.position.y), Vector2(body.end.x + 8.0, body.position.y),
		Vector2(cx, body.position.y - 26.0)]), Color("ffb1a8"))
	ci.draw_line(Vector2(body.position.x - 8.0, body.position.y),
			Vector2(body.end.x + 8.0, body.position.y), Color.WHITE, 3.0, true)
	# Guirnalda de banderines.
	var x0 := r.position.x + 10.0
	var x1 := r.end.x - 10.0
	var y0 := r.position.y + 12.0
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(Vector2(lerpf(x0, x1, t), y0 + sin(t * PI) * 20.0))
	ci.draw_polyline(pts, Color(WiiTheme.TEXT_SOFT, 0.5), 2.0, true)
	var cols := [Color("ffb3c1"), Color("ffe08a"), Color("a8e6cf"), Color("b8c9f5"), Color("e3c6f2")]
	for i in 11:
		var t := (float(i) + 0.5) / 11.0
		var p := Vector2(lerpf(x0, x1, t), y0 + sin(t * PI) * 20.0)
		ci.draw_colored_polygon(PackedVector2Array([
			p + Vector2(-7.0, 0.0), p + Vector2(7.0, 0.0), p + Vector2(0.0, 14.0)]), cols[i % cols.size()])
	# Globo protagonista.
	var c := r.position + Vector2(r.size.x * 0.4, r.size.y * 0.52)
	DrawKit.soft_shadow(ci, Vector2(c.x, gy + 4.0), 64.0)
	ci.draw_line(c + Vector2(0, 36.0), Vector2(c.x, gy - 2.0), Color(WiiTheme.TEXT_SOFT, 0.6), 2.5, true)
	ci.draw_circle(c, 34.0, Color("2fa8e0").darkened(0.12))
	ci.draw_circle(c + Vector2(0, -3.0), 32.0, Color("2fa8e0"))
	ci.draw_circle(c + Vector2(0, 9.0), 24.0, Color("2fa8e0").darkened(0.08))
	ci.draw_circle(c + Vector2(-11.0, -13.0), 11.0, Color(1, 1, 1, 0.45))
	ci.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-8.0, 34.0), c + Vector2(8.0, 34.0), c + Vector2(0.0, 44.0)]),
		Color("2fa8e0").darkened(0.12))
	# Un segundo globo más pequeño al fondo.
	ci.draw_circle(r.position + Vector2(r.size.x * 0.8, r.size.y * 0.36), 16.0, Color("ec5a5a", 0.85))
	ci.draw_circle(r.position + Vector2(r.size.x * 0.8 - 5.0, r.size.y * 0.36 - 5.0), 5.0,
			Color(1, 1, 1, 0.35))

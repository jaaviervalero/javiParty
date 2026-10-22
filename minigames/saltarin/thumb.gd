extends RefCounted
## Miniatura de "Pajarito saltarín" para el selector: mañana de campo, postes de
## madera y el pájaro de un jugador en mitad del hueco.

const WOOD := Color("c99a6b")
const WOOD_DARK := Color("a77a4e")
const LEAF := Color("a9de8a")
const LEAF_LIGHT := Color("c4edaa")


static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("cdeafd"), Color("f4fbf3"))
	DrawKit.sun(ci, r.position + Vector2(r.size.x - 34, 28), 14)
	DrawKit.cloud(ci, r.position + Vector2(48, 30), 0.42)
	DrawKit.cloud(ci, r.position + Vector2(178, 46), 0.32)
	DrawKit.hills(ci, r, r.end.y - 24, 9, Color("cfe6bf"), 0.4, 1.7)
	DrawKit.hills(ci, r, r.end.y - 13, 6, Color("a9da8f"), 2.3, 1.3)
	# Postes de madera con copa de hojas, dejando un hueco en medio.
	var cx := r.position.x + r.size.x * 0.22
	_post(ci, Rect2(cx, r.position.y, 20, r.size.y * 0.4),
			r.position.y + r.size.y * 0.4, true)
	_post(ci, Rect2(cx, r.position.y + r.size.y * 0.66, 20, r.size.y * 0.34),
			r.position.y + r.size.y * 0.66, false)
	# Pájaro protagonista.
	var bp := r.position + Vector2(r.size.x * 0.58, r.size.y * 0.5)
	DrawKit.glossy_ball(ci, bp, 13, Color("2fa8e0"))
	ci.draw_colored_polygon(PackedVector2Array([
		bp + Vector2(11, -1), bp + Vector2(19, -5), bp + Vector2(19, 3)]), Color("f2a33a"))
	ci.draw_circle(bp + Vector2(5, -5), 2.4, Color.WHITE)
	ci.draw_circle(bp + Vector2(5.6, -5), 1.1, Color(0.2, 0.3, 0.4))
	# Otra columna asomando por la derecha: sensación de avance.
	_post(ci, Rect2(r.position.x + r.size.x * 0.86, r.position.y, 20, r.size.y * 0.46),
			r.position.y + r.size.y * 0.46, true)
	_post(ci, Rect2(r.position.x + r.size.x * 0.86, r.position.y + r.size.y * 0.72, 20,
			r.size.y * 0.28), r.position.y + r.size.y * 0.72, false)


static func _post(ci: CanvasItem, rect: Rect2, tip_y: float, tip_at_bottom: bool) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = WOOD
	st.border_color = WOOD_DARK
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	ci.draw_style_box(st, rect)
	var inset := -6.0 if tip_at_bottom else 6.0
	var cx := rect.position.x + rect.size.x * 0.5
	for i in 3:
		ci.draw_circle(Vector2(cx + (i - 1) * 6.0, tip_y + inset), 6.0, LEAF)
	ci.draw_circle(Vector2(cx, tip_y + inset * 0.6), 5.0, LEAF_LIGHT)

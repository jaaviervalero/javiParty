extends Reference
## Miniatura de "Concurso de dominadas": barra al aire libre con dos bolas colgadas.

const METAL := Color("b6c2ca")
const METAL_DARK := Color("7f8c96")


static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("cdeefb"), Color("eef8fe"))
	DrawKit.sun(ci, r.position + Vector2(r.size.x - 34.0, 28.0), 15.0)
	DrawKit.cloud(ci, r.position + Vector2(r.size.x * 0.2, r.size.y * 0.18), 0.5,
			Color(1, 1, 1, 0.85))
	DrawKit.hills(ci, r, r.end.y - 34.0, 10.0, Color("bfe0b3"), 1.1, 1.6)
	DrawKit.hills(ci, r, r.end.y - 20.0, 6.0, Color("add5a1"), 2.8, 1.5)
	DrawKit.grass_tufts(ci, Vector2(r.position.x + 12.0, r.end.y - 6.0),
			Vector2(r.end.x - 12.0, r.end.y - 6.0), 10, Color("94c287"), 4)
	# Barra con postes hasta el césped.
	var bar_y := r.position.y + r.size.y * 0.34
	var x0 := r.position.x + r.size.x * 0.16
	var x1 := r.position.x + r.size.x * 0.84
	var ground := r.end.y - 14.0
	for side in [-1.0, 1.0]:
		var px: float = x0 if side < 0.0 else x1
		ci.draw_line(Vector2(px, bar_y), Vector2(px, ground), METAL, 5.0, true)
		ci.draw_line(Vector2(px - 1.5, bar_y), Vector2(px - 1.5, ground),
				Color(1, 1, 1, 0.35), 1.5, true)
	ci.draw_line(Vector2(x0, bar_y), Vector2(x1, bar_y), METAL_DARK, 7.0, true)
	ci.draw_line(Vector2(x0, bar_y - 2.0), Vector2(x1, bar_y - 2.0),
			Color(1, 1, 1, 0.45), 2.0, true)
	# Una bola arriba (dominada hecha) y otra colgada al lado.
	_draw_lifter(ci, Vector2(r.position.x + r.size.x * 0.38, bar_y + 16.0), bar_y,
			Color("2fa8e0"))
	_draw_lifter(ci, Vector2(r.position.x + r.size.x * 0.63, bar_y + 38.0), bar_y,
			Color("ec5a5a"))


## Bola con los brazos hasta la barra.
static func _draw_lifter(ci: CanvasItem, body: Vector2, bar_y: float, color: Color) -> void:
	var radius := 16.0
	var arm := color.darkened(0.22)
	for side in [-1.0, 1.0]:
		var hand := Vector2(body.x + side * radius * 0.5, bar_y)
		var shoulder := body + Vector2(side * radius * 0.55, -radius * 0.2)
		var elbow := (shoulder + hand) * 0.5 + Vector2(side * radius * 0.5, 0.0)
		ci.draw_polyline(PoolVector2Array([shoulder, elbow, hand]), arm, 5.0, true)
		ci.draw_circle(hand, 2.8, arm)
	DrawKit.glossy_ball(ci, body, radius, color, false)

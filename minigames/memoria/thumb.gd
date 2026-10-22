extends RefCounted
## Miniatura de "Sigue la secuencia" para el selector: teatrillo con telones y
## los cuatro botones de dirección alrededor de un foco.

const PETAL_COLORS: Array[Color] = [
	Color("9ad4f0"), Color("ffc98f"), Color("f6a9c9"), Color("a9e0a4"),
]
const DIR_VECS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]


static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("e9def9"), Color("fdf1e2"))
	var floor_y := r.end.y - 34.0
	# Foco de luz sobre el escenario.
	DrawKit.ellipse(ci, r.position + Vector2(r.size.x * 0.5, r.size.y * 0.56),
			Vector2(r.size.x * 0.42, r.size.y * 0.46), Color(1.0, 0.98, 0.82, 0.32))
	# Suelo de tablas claras.
	ci.draw_rect(Rect2(r.position.x, floor_y, r.size.x, r.end.y - floor_y), Color("eedcbd"))
	for i in 3:
		ci.draw_line(Vector2(r.position.x, floor_y + 8 + i * 10),
				Vector2(r.end.x, floor_y + 8 + i * 10), Color("d9c096"), 1.5)
	# Telones laterales con pliegues.
	ci.draw_rect(Rect2(r.position.x, r.position.y, 26, floor_y - r.position.y), Color("e7a9c0"))
	ci.draw_rect(Rect2(r.end.x - 26, r.position.y, 26, floor_y - r.position.y), Color("e7a9c0"))
	for i in 2:
		ci.draw_rect(Rect2(r.position.x + 8 + i * 9, r.position.y, 4, floor_y - r.position.y),
				Color("d68aa8"))
		ci.draw_rect(Rect2(r.end.x - 17 - i * 9, r.position.y, 4, floor_y - r.position.y),
				Color("d68aa8"))
	# Guardamalleta superior ondulada.
	ci.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 18), Color("e7a9c0"))
	var bx := r.position.x + 17.0
	while bx < r.end.x:
		ci.draw_circle(Vector2(bx, r.position.y + 18), 10, Color("e7a9c0"))
		ci.draw_circle(Vector2(bx, r.position.y + 18), 8, Color("d68aa8"))
		bx += 20.0
	# Los cuatro botones de dirección, con uno encendido.
	var center := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.56)
	for d in 4:
		var pos: Vector2 = center + DIR_VECS[d] * 32.0
		var base: Color = PETAL_COLORS[d]
		if d == 1:
			ci.draw_circle(pos, 24, Color(base, 0.3))
		ci.draw_circle(pos + Vector2(0, 3), 18, Color(0.2, 0.3, 0.4, 0.14))
		ci.draw_circle(pos, 17, base)
		ci.draw_circle(pos + Vector2(0, 3), 13, base.darkened(0.06))
		ci.draw_circle(pos + Vector2(-5, -6), 6, Color(1, 1, 1, 0.45))
		var dir: Vector2 = DIR_VECS[d]
		var tip := pos + dir * 8.5
		var side := dir.orthogonal() * 3.8
		ci.draw_colored_polygon(PackedVector2Array([tip, pos + dir * 1.4 + side,
				pos + dir * 1.4 - side]), Color(base.darkened(0.32), 0.92))

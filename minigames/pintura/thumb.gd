extends Reference
## Miniatura de "Pinta el suelo": patio de baldosas con dos bolas y un power-up.

static func draw(ci: CanvasItem, r: Rect2) -> void:
	DrawKit.vgradient(ci, r, Color("c9ecb4"), Color("8fd16b"))
	# Jardín: setos y flores en los bordes del patio.
	for i in 4:
		ci.draw_circle(r.position + Vector2(34 + i * 62, r.size.y - 5), 13.0, Color("79c45a"))
	for i in 3:
		DrawKit.flower(ci, r.position + Vector2(66 + i * 66, r.size.y - 7), 4.0,
				Color(1, 1, 1, 1) if i % 2 == 0 else Color("ffd1e3"))
	# Tablero de baldosas claras.
	var board := Rect2(r.position + Vector2(20, 22), Vector2(208, 83))
	var cell := board.size.x / 10.0
	var rows := 4
	ci.draw_rect(board, Color("f6f0e2"))
	for cy in rows:
		for cx in 10:
			if (cx + cy) % 2 == 0:
				ci.draw_rect(Rect2(board.position + Vector2(cx, cy) * cell, Vector2(cell, cell)),
						Color("ece3d0"))
	# Territorio pintado por los dos jugadores.
	var blue_cells: Array = [Vector2(1, 2), Vector2(2, 2), Vector2(2, 3),
			Vector2(1, 3), Vector2(3, 2)]
	for c in blue_cells:
		ci.draw_rect(Rect2(board.position + Vector2(c) * cell, Vector2(cell, cell)),
				Color("2fa8e0").lightened(0.35))
	var red_cells: Array = [Vector2(6, 1), Vector2(7, 1), Vector2(6, 2),
			Vector2(7, 2), Vector2(8, 2)]
	for c in red_cells:
		ci.draw_rect(Rect2(board.position + Vector2(c) * cell, Vector2(cell, cell)),
				Color("ec5a5a").lightened(0.35))
	ci.draw_rect(board, Color(1, 1, 1, 1), false, 2.0)
	# Power-up glossy junto a la bola roja.
	var pu := board.position + Vector2(cell * 8.7, cell * 2.6)
	ci.draw_circle(pu, 14.0, Color("8e4ec6"))
	ci.draw_arc(pu, 14.0, 0.0, TAU, 28, Color(1, 1, 1, 1), 3.0, true)
	ci.draw_circle(pu + Vector2(-4, -5), 4.0, Color(1, 1, 1, 0.6))
	var bolt := PoolVector2Array([pu + Vector2(2, -8), pu + Vector2(-5, 1), pu + Vector2(-1, 1),
			pu + Vector2(-2, 8), pu + Vector2(6, -1), pu + Vector2(2, -1)])
	ci.draw_colored_polygon(bolt, Color("ffd34d"))
	# Las dos bolas.
	DrawKit.glossy_ball(ci, board.position + Vector2(cell * 2.7, cell * 3.0), 16.0, Color("2fa8e0"))
	DrawKit.glossy_ball(ci, board.position + Vector2(cell * 7.0, cell * 1.8), 16.0, Color("ec5a5a"))

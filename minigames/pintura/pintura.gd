extends MinigameBase
## "Pinta el suelo": cada jugador es una bola que repinta el suelo a su color al
## pasar. Por las casillas aparecen power-ups (bomba, brocha grande y rayo) que
## se cogen rodando por encima. Gana quien tenga más casillas al final.

const BALL_RADIUS := 26.0
const MAX_SPEED := 380.0
const STEER := 9.0
const CELL := 40.0
const COLS := 30
const ROWS := 15
const PAINT_REACH := 29.0      # radio de pintura al rodar (algo más de media casilla)

# Power-ups
const BOMB := 0
const BRUSH := 1
const SPEED := 2
const POWERUP_RADIUS := 24.0
const POWERUP_MAX := 3
const POWERUP_INTERVAL := 4.0
const POWERUP_INITIAL := 2
const BOMB_CELLS := 3.0        # radio de la explosión, en casillas
const BRUSH_TIME := 6.0
const BRUSH_RADIUS_MULT := 1.35
const SPEED_TIME := 5.0
const SPEED_MULT := 1.7
const BRUSH_COLOR := Color("8e4ec6")
const SPEED_COLOR := Color("ffd34d")
const BOMB_COLOR := Color("e25555")

# Ambiente: patio soleado de baldosas claras con jardín alrededor.
const PATIO := Color("f6f0e2")
const PATIO_DARK := Color("ece3d0")
const GARDEN := Color("9bd774")
const GARDEN_DARK := Color("77bd55")
const HEDGE := Color("79c45a")


class Ball:
	var player: Player
	var pos: Vector2
	var vel := Vector2.ZERO
	var brush_left := 0.0       # segundos de brocha grande
	var speed_left := 0.0       # segundos de rayo
	var squash := 1.0


class Powerup:
	var kind: int
	var pos: Vector2
	var cell: Vector2i
	var age := 0.0


var _balls: Array[Ball] = []
var _powerups: Array[Powerup] = []
var _owner := PackedInt32Array()   # 0 = vacía; si no, index del jugador + 1
var _count := [0, 0, 0, 0]
var _colors: Array[Color] = []
var _waves: Array = []             # [pos, t, radio_max, color]
var _confetti: Array = []          # [pos, vel, color, vida]
var _spawn_timer := POWERUP_INTERVAL


func _configure() -> void:
	title = {"es": "Pinta el suelo", "en": "Paint the floor"}
	instructions = {"es": "Pinta más casillas que nadie rodando por el suelo y cogiendo power-ups.",
		"en": "Paint more tiles than anyone by rolling around and grabbing power-ups."}
	controls = [
		["stick", {"es": "Moverse", "en": "Move"}],
		["dpad", {"es": "Moverse", "en": "Move"}],
	]
	duration = 45.0


func _setup() -> void:
	_owner.resize(COLS * ROWS)
	_owner.fill(0)
	_colors.resize(4)
	for p in players:
		_colors[p.index] = p.color
	var n := players.size()
	var step := 180.0
	var start := -step * (n - 1) * 0.5
	var center := _grid_origin() + Vector2(COLS * CELL, ROWS * CELL) * 0.5
	for i in n:
		var b := Ball.new()
		b.player = players[i]
		b.pos = center + Vector2(start + step * i, 0)
		_balls.append(b)
	for i in POWERUP_INITIAL:
		_spawn_powerup()


func _game_start() -> void:
	_spawn_timer = POWERUP_INTERVAL


func _game_process(delta: float) -> void:
	for b in _balls:
		_update_ball(b, delta)
	_collide_balls()
	for b in _balls:
		_paint_trail(b)
	_pickups()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = POWERUP_INTERVAL
		if _powerups.size() < POWERUP_MAX:
			_spawn_powerup()
	_sync_scores()
	_update_effects(delta)


func _update_ball(b: Ball, delta: float) -> void:
	b.brush_left = maxf(0.0, b.brush_left - delta)
	b.speed_left = maxf(0.0, b.speed_left - delta)
	b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 10.0))
	var p := b.player
	var dir := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	var top := MAX_SPEED * (SPEED_MULT if b.speed_left > 0.0 else 1.0)
	if dir != Vector2.ZERO:
		b.vel = b.vel.lerp(dir.normalized() * top, 1.0 - exp(-STEER * delta))
	else:
		b.vel *= exp(-STEER * 0.6 * delta)
	b.pos += b.vel * delta
	_bounce(b)


func _bounce(b: Ball) -> void:
	var r := _grid_rect().grow(-_ball_radius(b))
	if b.pos.x < r.position.x:
		b.pos.x = r.position.x
		b.vel.x = absf(b.vel.x) * 0.7
		b.squash = 0.85
	elif b.pos.x > r.end.x:
		b.pos.x = r.end.x
		b.vel.x = -absf(b.vel.x) * 0.7
		b.squash = 0.85
	if b.pos.y < r.position.y:
		b.pos.y = r.position.y
		b.vel.y = absf(b.vel.y) * 0.7
		b.squash = 0.85
	elif b.pos.y > r.end.y:
		b.pos.y = r.end.y
		b.vel.y = -absf(b.vel.y) * 0.7
		b.squash = 0.85


func _ball_radius(b: Ball) -> float:
	return BALL_RADIUS * (BRUSH_RADIUS_MULT if b.brush_left > 0.0 else 1.0)


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a := _balls[i]
			var b := _balls[j]
			var d := b.pos - a.pos
			var dist := d.length()
			var min_dist := _ball_radius(a) + _ball_radius(b)
			if dist >= min_dist or dist < 0.01:
				continue
			var n := d / dist
			var overlap := min_dist - dist
			a.pos -= n * overlap * 0.5
			b.pos += n * overlap * 0.5
			var rel := (b.vel - a.vel).dot(n)
			if rel < 0.0:
				a.vel += n * rel * 0.9
				b.vel -= n * rel * 0.9
				a.squash = 0.88
				b.squash = 0.88


# --- Power-ups ---

func _spawn_powerup() -> void:
	var o := _grid_origin()
	for _attempt in 40:
		var cell := Vector2i(randi_range(0, COLS - 1), randi_range(0, ROWS - 1))
		var pos := o + Vector2((cell.x + 0.5) * CELL, (cell.y + 0.5) * CELL)
		if not _spot_is_free(pos):
			continue
		var pu := Powerup.new()
		pu.kind = randi_range(0, 2)
		pu.pos = pos
		pu.cell = cell
		_powerups.append(pu)
		return


func _spot_is_free(pos: Vector2) -> bool:
	for b in _balls:
		if b.pos.distance_to(pos) < BALL_RADIUS + POWERUP_RADIUS + 24.0:
			return false
	for pu in _powerups:
		if pu.pos.distance_to(pos) < CELL * 2.0:
			return false
	return true


func _pickups() -> void:
	for i in range(_powerups.size() - 1, -1, -1):
		var pu := _powerups[i]
		for b in _balls:
			if b.pos.distance_to(pu.pos) <= _ball_radius(b) + POWERUP_RADIUS:
				_powerups.remove_at(i)
				_apply_powerup(b, pu)
				break


func _apply_powerup(b: Ball, pu: Powerup) -> void:
	match pu.kind:
		BOMB:
			_explode(b)
		BRUSH:
			b.brush_left = BRUSH_TIME
			b.squash = 1.25
			_burst(pu.pos, BRUSH_COLOR, 14)
			Sfx.play("star", randf_range(0.95, 1.1))
		SPEED:
			b.speed_left = SPEED_TIME
			b.squash = 1.25
			_burst(pu.pos, SPEED_COLOR, 14)
			Sfx.play("dash", randf_range(1.0, 1.15))


func _explode(b: Ball) -> void:
	var owner := b.player.index + 1
	_paint(b.pos, BOMB_CELLS * CELL, owner)
	_waves.append([b.pos, 0.0, BOMB_CELLS * CELL, b.player.color])
	_burst(b.pos, b.player.color, 28)
	b.squash = 1.4
	Sfx.play("wave", randf_range(0.9, 1.05))


# --- Pintura ---

func _paint_trail(b: Ball) -> void:
	if b.brush_left > 0.0:
		_paint_brush(b.pos, b.player.index + 1)
	else:
		_paint(b.pos, PAINT_REACH, b.player.index + 1)


## 3x3 casillas alrededor de la casilla donde está la bola.
func _paint_brush(center: Vector2, owner: int) -> void:
	var o := _grid_origin()
	var cx := int(floor((center.x - o.x) / CELL))
	var cy := int(floor((center.y - o.y) / CELL))
	for y in range(cy - 1, cy + 2):
		if y < 0 or y >= ROWS:
			continue
		for x in range(cx - 1, cx + 2):
			if x < 0 or x >= COLS:
				continue
			_set_cell(y * COLS + x, owner)


func _grid_origin() -> Vector2:
	return ARENA.position + Vector2((ARENA.size.x - COLS * CELL) * 0.5,
			(ARENA.size.y - ROWS * CELL) * 0.5)


func _grid_rect() -> Rect2:
	return Rect2(_grid_origin(), Vector2(COLS * CELL, ROWS * CELL))


func _paint(center: Vector2, radius: float, owner: int) -> void:
	var o := _grid_origin()
	var c0 := Vector2i(int(floor((center.x - radius - o.x) / CELL)),
			int(floor((center.y - radius - o.y) / CELL)))
	var c1 := Vector2i(int(floor((center.x + radius - o.x) / CELL)),
			int(floor((center.y + radius - o.y) / CELL)))
	c0.x = clampi(c0.x, 0, COLS - 1)
	c0.y = clampi(c0.y, 0, ROWS - 1)
	c1.x = clampi(c1.x, 0, COLS - 1)
	c1.y = clampi(c1.y, 0, ROWS - 1)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cc := o + Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
			if cc.distance_to(center) <= radius:
				_set_cell(cy * COLS + cx, owner)


func _set_cell(idx: int, owner: int) -> void:
	var prev := _owner[idx]
	if prev == owner:
		return
	if prev > 0:
		_count[prev - 1] -= 1
	_owner[idx] = owner
	_count[owner - 1] += 1


func _sync_scores() -> void:
	for p in players:
		set_score(p, _count[p.index])


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(120.0, 420.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.5, 0.9)])


func _update_effects(delta: float) -> void:
	for pu in _powerups:
		pu.age += delta
	for w in _waves:
		w[1] += delta * 1.8
	_waves = _waves.filter(func(w): return w[1] < 1.0)
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 500) * delta
		c[3] -= delta
	_confetti = _confetti.filter(func(c): return c[3] > 0.0)


func _game_end() -> void:
	_sync_scores()


# --- Dibujo ---

## Jardín y base del tablero: se pinta una sola vez (ver MinigameBase._draw_scenery).
func _draw_scenery(ci: CanvasItem) -> void:
	# Jardín: solo asoma por los márgenes y las esquinas redondeadas de la arena.
	var garden := Rect2(0.0, 84.0, 1280.0, 636.0)
	ci.draw_rect(garden, GARDEN)
	DrawKit.grass_tufts(ci, Vector2(24.0, 704.0), Vector2(1256.0, 704.0), 26, GARDEN_DARK, 5)
	# Setos redondos en los bordes, lejos de las esquinas.
	for i in 11:
		var hx := 100.0 + i * 110.0
		ci.draw_circle(Vector2(hx, ARENA.end.y + 12.0), 24.0, HEDGE)
		ci.draw_circle(Vector2(hx - 12.0, ARENA.end.y + 15.0), 15.0, HEDGE.lightened(0.08))
	for i in 5:
		var hy := 170.0 + i * 100.0
		ci.draw_circle(Vector2(ARENA.position.x - 10.0, hy), 20.0, HEDGE)
		ci.draw_circle(Vector2(ARENA.end.x + 10.0, hy + 46.0), 20.0, HEDGE)
	for i in 9:
		DrawKit.flower(ci, Vector2(90.0 + i * 138.0, ARENA.end.y + 14.0), 4.5,
				Color.WHITE if i % 2 == 0 else Color("ffd1e3"))
	DrawKit.arena_frame(ci, ARENA, PATIO, PATIO_DARK)
	_draw_patio(ci)
	# Devuelve las esquinas redondeadas al tablero y cierra con el borde blanco.
	DrawKit.round_corners_mask(ci, ARENA, 30.0, GARDEN)
	DrawKit.arena_border(ci, ARENA)


## Baldosas del patio y rejilla: estático, así que va con el escenario.
func _draw_patio(ci: CanvasItem) -> void:
	var o := _grid_origin()
	var size := Vector2(COLS * CELL, ROWS * CELL)
	var board := Rect2(o, size)
	ci.draw_rect(board, PATIO)
	# Damero muy suave de bloques 2x2 (no se come el color de las casillas pintadas).
	for by in range(0, ROWS, 2):
		for bx in range(0, COLS, 2):
			if (bx + by) % 4 != 0:
				continue
			var r := Rect2(o + Vector2(bx * CELL, by * CELL),
					Vector2(CELL * 2.0, CELL * 2.0)).intersection(board)
			if r.has_area():
				ci.draw_rect(r, PATIO_DARK)
	# Junta sutil en vez de un borde por casilla: menos llamadas de dibujo.
	var line := Color(0.35, 0.42, 0.48, 0.10)
	for cx in range(COLS + 1):
		var x := o.x + cx * CELL
		ci.draw_line(Vector2(x, o.y), Vector2(x, o.y + size.y), line, 1.0)
	for cy in range(ROWS + 1):
		var y := o.y + cy * CELL
		ci.draw_line(Vector2(o.x, y), Vector2(o.x + size.x, y), line, 1.0)
	ci.draw_rect(board, WiiTheme.PANEL_BORDER, false, 3.0)


func _draw() -> void:
	_draw_paint()
	for pu in _powerups:
		_draw_powerup(pu)
	for w in _waves:
		var t: float = w[1]
		draw_arc(w[0], w[2] * t, 0.0, TAU, 48, Color(w[3], 0.6 * (1.0 - t)),
				6.0 * (1.0 - t) + 1.0, true)
	for b in _balls:
		_draw_ball(b)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)),
				Color(c[2], clampf(c[3] * 2.0, 0.0, 1.0)))


## Solo las casillas pintadas: el resto del patio ya está en el escenario.
func _draw_paint() -> void:
	var o := _grid_origin()
	for cy in ROWS:
		for cx in COLS:
			var owner := _owner[cy * COLS + cx]
			if owner <= 0:
				continue
			draw_rect(Rect2(o + Vector2(cx * CELL, cy * CELL), Vector2(CELL, CELL)),
					_colors[owner - 1].lightened(0.35))


func _draw_powerup(pu: Powerup) -> void:
	var bob := sin(pu.age * 4.0) * 3.0
	var c := pu.pos + Vector2(0, bob)
	var pulse := 1.0 + sin(pu.age * 5.0) * 0.05
	var r := POWERUP_RADIUS * pulse
	var kind := BRUSH_COLOR
	match pu.kind:
		BOMB:
			kind = BOMB_COLOR
		SPEED:
			kind = SPEED_COLOR
	DrawKit.soft_shadow(self, pu.pos + Vector2(0, 18.0), r * 1.7)
	draw_circle(c, r + 5.0, Color(kind, 0.18))
	draw_circle(c, r, Color.WHITE)
	draw_circle(c + Vector2(0, r * 0.22), r * 0.78, Color(kind, 0.14))
	draw_arc(c, r, 0.0, TAU, 32, kind, 3.5, true)
	# Brillo glossy arriba a la izquierda.
	DrawKit.ellipse(self, c + Vector2(-r * 0.32, -r * 0.42), Vector2(r * 0.34, r * 0.18),
			Color(1, 1, 1, 0.65))
	match pu.kind:
		BOMB:
			_draw_icon_bomb(c)
		BRUSH:
			_draw_icon_brush(c)
		SPEED:
			_draw_icon_bolt(c)


func _draw_icon_bomb(c: Vector2) -> void:
	draw_circle(c + Vector2(0, 2), 9.0, WiiTheme.ACCENT_DARK)
	draw_circle(c + Vector2(-3, -1), 3.0, Color(1, 1, 1, 0.45))
	draw_line(c + Vector2(5, -7), c + Vector2(9, -12), WiiTheme.ACCENT_DARK, 3.0, true)
	draw_circle(c + Vector2(10, -13), 3.2, Color("ffd34d"))


func _draw_icon_brush(c: Vector2) -> void:
	draw_set_transform(c, -0.7, Vector2.ONE)
	draw_rect(Rect2(-3.0, -14.0, 6.0, 15.0), WiiTheme.ACCENT_DARK)
	draw_rect(Rect2(-7.0, -1.0, 14.0, 4.0), WiiTheme.ACCENT_DARK)
	var pts := PackedVector2Array([Vector2(-7, 3), Vector2(7, 3), Vector2(5, 12), Vector2(-5, 12)])
	draw_colored_polygon(pts, WiiTheme.ACCENT)
	draw_set_transform(Vector2.ZERO)


func _draw_icon_bolt(c: Vector2) -> void:
	var pts := PackedVector2Array([
		c + Vector2(2, -14), c + Vector2(-9, 2), c + Vector2(-1, 2),
		c + Vector2(-3, 14), c + Vector2(9, -3), c + Vector2(1, -3),
	])
	draw_colored_polygon(pts, Color("ffd34d"))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, WiiTheme.ACCENT_DARK, 2.5, true)


func _draw_ball(b: Ball) -> void:
	var col := b.player.color
	if not b.player.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	var r := _ball_radius(b)
	# Estela del rayo.
	if b.speed_left > 0.0 and b.vel.length() > 40.0:
		var back := b.pos - b.vel.normalized() * (r * 0.4)
		for i in 3:
			draw_circle(back - b.vel.normalized() * (i * 13.0), r * (0.7 - i * 0.15),
					Color(col, 0.24 - i * 0.06))
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos + Vector2(0, 6), 0.0, Vector2(stretch.x * 1.1, 0.35))
	draw_circle(Vector2.ZERO, r, WiiTheme.SHADOW)
	draw_set_transform(b.pos, 0.0, stretch)
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2(0, r * 0.25), r * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.38, Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(b.player.index + 1), b.pos, int(26.0 * r / BALL_RADIUS), Color.WHITE)
	# Aros con el tiempo que le queda a cada efecto activo.
	var ring := r + 8.0
	if b.brush_left > 0.0:
		_draw_effect_ring(b.pos, ring, b.brush_left / BRUSH_TIME, BRUSH_COLOR)
		ring += 8.0
	if b.speed_left > 0.0:
		_draw_effect_ring(b.pos, ring, b.speed_left / SPEED_TIME, SPEED_COLOR)


func _draw_effect_ring(center: Vector2, radius: float, frac: float, color: Color) -> void:
	draw_arc(center, radius, 0.0, TAU, 32, Color(color, 0.18), 5.0, true)
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(frac, 0.0, 1.0), 32,
			color, 5.0, true)

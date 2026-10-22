extends MinigameBase
## "Pinta el suelo": cada jugador es una bola que repinta el suelo a su color al
## pasar. A lanza un salpicón y B da un sprint. Gana quien tenga más casillas.

const BALL_RADIUS := 26.0
const MAX_SPEED := 380.0
const STEER := 9.0
const CELL := 40.0
const COLS := 30
const ROWS := 15
const PAINT_REACH := 29.0      # radio de pintura al rodar (algo más de media casilla)
const SPLAT_RADIUS := 2.5      # en casillas
const SPLAT_COOLDOWN := 3.0
const SPRINT_TIME := 0.6
const SPRINT_MULT := 1.8
const SPRINT_COOLDOWN := 2.0


class Ball:
	var player: Player
	var pos: Vector2
	var vel := Vector2.ZERO
	var splat_cd := 0.0
	var sprint_cd := 0.0
	var sprint_left := 0.0
	var squash := 1.0


var _balls: Array[Ball] = []
var _owner := PackedInt32Array()   # 0 = vacía; si no, index del jugador + 1
var _count := [0, 0, 0, 0]
var _colors: Array[Color] = []
var _rings: Array = []             # [pos, t, color]
var _time := 0.0


func _configure() -> void:
	title = {"es": "Pinta el suelo", "en": "Paint the floor"}
	instructions = {"es": "Pinta más casillas que nadie pasando por encima y con salpicones.",
		"en": "Paint more tiles than anyone by rolling over them and splatting."}
	controls = [
		["stick", {"es": "Moverse", "en": "Move"}],
		[Pad.A, {"es": "Salpicón", "en": "Splat"}],
		[Pad.B, {"es": "Sprint", "en": "Sprint"}],
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


func _game_process(delta: float) -> void:
	_time += delta
	for b in _balls:
		_update_ball(b, delta)
		_paint(b.pos, PAINT_REACH, b.player.index + 1)
	_collide_balls()
	_sync_scores()
	_update_effects(delta)


func _update_ball(b: Ball, delta: float) -> void:
	b.splat_cd = maxf(0.0, b.splat_cd - delta)
	b.sprint_cd = maxf(0.0, b.sprint_cd - delta)
	b.sprint_left = maxf(0.0, b.sprint_left - delta)
	b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 10.0))
	var p := b.player
	var dir := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	var top := MAX_SPEED * (SPRINT_MULT if b.sprint_left > 0.0 else 1.0)
	if dir != Vector2.ZERO:
		b.vel = b.vel.lerp(dir.normalized() * top, 1.0 - exp(-STEER * delta))
	else:
		b.vel *= exp(-STEER * 0.6 * delta)
	if p.just_pressed(Pad.A) and b.splat_cd <= 0.0:
		b.splat_cd = SPLAT_COOLDOWN
		b.squash = 1.3
		_paint(b.pos, SPLAT_RADIUS * CELL, p.index + 1)
		_rings.append([b.pos, 0.0, p.color])
		Sfx.play("pop", randf_range(0.9, 1.05))
	if p.just_pressed(Pad.B) and b.sprint_cd <= 0.0:
		b.sprint_cd = SPRINT_COOLDOWN
		b.sprint_left = SPRINT_TIME
		Sfx.play("dash", randf_range(1.0, 1.15))
	b.pos += b.vel * delta
	_bounce(b)


func _bounce(b: Ball) -> void:
	var r := _grid_rect().grow(-BALL_RADIUS)
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


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a := _balls[i]
			var b := _balls[j]
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= BALL_RADIUS * 2.0 or dist < 0.01:
				continue
			var n := d / dist
			var overlap := BALL_RADIUS * 2.0 - dist
			a.pos -= n * overlap * 0.5
			b.pos += n * overlap * 0.5
			var rel := (b.vel - a.vel).dot(n)
			if rel < 0.0:
				a.vel += n * rel * 0.9
				b.vel -= n * rel * 0.9
				a.squash = 0.88
				b.squash = 0.88


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


func _update_effects(delta: float) -> void:
	for r in _rings:
		r[1] += delta * 2.2
	_rings = _rings.filter(func(r): return r[1] < 1.0)


func _game_end() -> void:
	_sync_scores()


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	_draw_floor()
	for r in _rings:
		var t: float = r[1]
		draw_arc(r[0], 10.0 + SPLAT_RADIUS * CELL * t, 0.0, TAU, 48,
				Color(r[2], 0.6 * (1.0 - t)), 6.0 * (1.0 - t) + 1.0, true)
	for b in _balls:
		_draw_ball(b)


func _draw_floor() -> void:
	var o := _grid_origin()
	var empty := Color("eef2f5")
	for cy in ROWS:
		for cx in COLS:
			var owner := _owner[cy * COLS + cx]
			var col := empty
			if owner > 0:
				col = _colors[owner - 1].lightened(0.35)
			draw_rect(Rect2(o + Vector2(cx * CELL, cy * CELL), Vector2(CELL, CELL)), col)
	# Rejilla sutil en vez de un borde por casilla: menos llamadas de dibujo.
	var line := Color(0.35, 0.42, 0.48, 0.10)
	for cx in range(COLS + 1):
		var x := o.x + cx * CELL
		draw_line(Vector2(x, o.y), Vector2(x, o.y + ROWS * CELL), line, 1.0)
	for cy in range(ROWS + 1):
		var y := o.y + cy * CELL
		draw_line(Vector2(o.x, y), Vector2(o.x + COLS * CELL, y), line, 1.0)
	draw_rect(Rect2(o, Vector2(COLS * CELL, ROWS * CELL)), WiiTheme.PANEL_BORDER, false, 3.0)


func _draw_ball(b: Ball) -> void:
	var col := b.player.color
	if not b.player.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	# Rastro del sprint.
	if b.sprint_left > 0.0 and b.vel.length() > 40.0:
		var back := b.pos - b.vel.normalized() * 16.0
		draw_circle(back, BALL_RADIUS * 0.8, Color(col, 0.22))
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos + Vector2(0, 6), 0.0, Vector2(stretch.x * 1.1, 0.35))
	draw_circle(Vector2.ZERO, BALL_RADIUS, WiiTheme.SHADOW)
	draw_set_transform(b.pos, 0.0, stretch)
	draw_circle(Vector2.ZERO, BALL_RADIUS, col)
	draw_circle(Vector2(0, BALL_RADIUS * 0.25), BALL_RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-BALL_RADIUS * 0.3, -BALL_RADIUS * 0.35), BALL_RADIUS * 0.38,
			Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(b.player.index + 1), b.pos, 26, Color.WHITE)
	# Recarga del salpicón.
	if b.splat_cd > 0.0:
		var t := 1.0 - b.splat_cd / SPLAT_COOLDOWN
		draw_arc(b.pos, BALL_RADIUS + 8.0, -PI * 0.5, -PI * 0.5 + TAU * t, 24,
				Color(col, 0.6), 3.0, true)

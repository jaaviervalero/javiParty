extends MinigameBase
## "Lluvia de monedas": caen monedas, gemas y bombas. Cada jugador se mueve solo
## en horizontal por el suelo y salta para atrapar premios. Las bombas aturden y
## restan puntos.

const BALL_RADIUS := 28.0
const MOVE_SPEED := 520.0
const MOVE_ACCEL := 12.0
const JUMP_SPEED := 900.0
const GRAVITY := 2400.0
const GROUND_Y := 670.0          # ARENA.end.y (696) menos el borde del suelo
const ITEM_COIN := 0
const ITEM_GEM := 1
const ITEM_BOMB := 2
const COIN_RADIUS := 15.0
const GEM_RADIUS := 23.0
const BOMB_RADIUS := 17.0
const COIN_SCORE := 1
const GEM_SCORE := 3
const BOMB_PENALTY := 2
const STUN_TIME := 1.5
const SPAWN_MAX := 1.15
const SPAWN_MIN := 0.38
const FALL_SPEED := 210.0
const FALL_ACCEL := 40.0


class Ball:
	var player: Player
	var pos: Vector2
	var vx := 0.0
	var vy := 0.0
	var on_ground := true
	var stun := 0.0
	var squash := 1.0


class Item:
	var kind := ITEM_COIN
	var pos: Vector2
	var vel := FALL_SPEED
	var spin := 0.0
	var gone := false


var _balls: Array[Ball] = []
var _items: Array[Item] = []
var _spawn_timer := 0.7
var _time := 0.0
var _pops: Array = []     # [pos, texto, color, t]
var _bursts: Array = []   # [pos, vel, color, vida]


func _configure() -> void:
	title = {"es": "Lluvia de monedas", "en": "Coin shower"}
	instructions = {"es": "Atrapa monedas y gemas, esquiva las bombas y salta para llegar más alto.",
		"en": "Catch coins and gems, dodge the bombs and jump to reach higher."}
	controls = [
		["stick", {"es": "Moverse (izquierda y derecha)", "en": "Move (left and right)"}],
		[Pad.A, {"es": "Saltar", "en": "Jump"}],
	]
	duration = 40.0


func _setup() -> void:
	var n := players.size()
	var step := 260.0
	var start := -step * (n - 1) * 0.5
	var cx := ARENA.get_center().x
	for i in n:
		var b := Ball.new()
		b.player = players[i]
		b.pos = Vector2(cx + start + step * i, GROUND_Y - BALL_RADIUS)
		_balls.append(b)


func _game_start() -> void:
	_spawn_timer = 0.7


func _game_process(delta: float) -> void:
	_time += delta
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_item()
		var t := clampf(elapsed / duration, 0.0, 1.0)
		_spawn_timer = lerpf(SPAWN_MAX, SPAWN_MIN, t) * randf_range(0.85, 1.15)
	for b in _balls:
		_update_ball(b, delta)
	_collide_balls()
	_update_items(delta)
	_update_effects(delta)


func _update_ball(b: Ball, delta: float) -> void:
	b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 10.0))
	if b.stun > 0.0:
		b.stun = maxf(0.0, b.stun - delta)
		b.vx = move_toward(b.vx, 0.0, MOVE_SPEED * 3.0 * delta)
	else:
		var p := b.player
		var s := p.stick()
		var axis := s.x if s != Vector2.ZERO else p.dpad().x
		b.vx = move_toward(b.vx, axis * MOVE_SPEED, MOVE_SPEED * MOVE_ACCEL * delta)
		if p.just_pressed(Pad.A) and b.on_ground:
			b.vy = -JUMP_SPEED
			b.on_ground = false
			b.squash = 1.25
			Sfx.play("move", randf_range(0.55, 0.7))
	b.pos.x = clampf(b.pos.x + b.vx * delta,
			ARENA.position.x + BALL_RADIUS, ARENA.end.x - BALL_RADIUS)
	if not b.on_ground:
		b.vy += GRAVITY * delta
		b.pos.y += b.vy * delta
		if b.pos.y >= GROUND_Y - BALL_RADIUS:
			b.pos.y = GROUND_Y - BALL_RADIUS
			if b.vy > 400.0:
				Sfx.play("move", 0.5)
			b.vy = 0.0
			b.on_ground = true
			b.squash = 0.85


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a := _balls[i]
			var b := _balls[j]
			if absf(a.pos.y - b.pos.y) > BALL_RADIUS * 1.4:
				continue
			var d := b.pos.x - a.pos.x
			var min_d := BALL_RADIUS * 2.0
			if absf(d) >= min_d:
				continue
			var side := 1.0 if d >= 0.0 else -1.0
			var push := (min_d - absf(d)) * 0.5
			a.pos.x -= side * push
			b.pos.x += side * push
			var avg := (a.vx + b.vx) * 0.5
			a.vx = lerpf(a.vx, avg, 0.4)
			b.vx = lerpf(b.vx, avg, 0.4)
			a.squash = 0.9
			b.squash = 0.9
			a.pos.x = clampf(a.pos.x, ARENA.position.x + BALL_RADIUS, ARENA.end.x - BALL_RADIUS)
			b.pos.x = clampf(b.pos.x, ARENA.position.x + BALL_RADIUS, ARENA.end.x - BALL_RADIUS)


func _spawn_item() -> void:
	var it := Item.new()
	var r := randf()
	if r < 0.12:
		it.kind = ITEM_GEM
	elif r < 0.30:
		it.kind = ITEM_BOMB
	else:
		it.kind = ITEM_COIN
	var margin := 60.0
	it.pos = Vector2(randf_range(ARENA.position.x + margin, ARENA.end.x - margin),
			ARENA.position.y - 20.0)
	it.vel = FALL_SPEED * randf_range(0.85, 1.15)
	_items.append(it)


func _update_items(delta: float) -> void:
	for it in _items:
		it.vel += FALL_ACCEL * delta
		it.pos.y += it.vel * delta
		it.spin += delta * 2.4
		if it.pos.y >= GROUND_Y:
			it.gone = true
			continue
		for b in _balls:
			if b.pos.distance_to(it.pos) < BALL_RADIUS + _item_radius(it.kind) * 0.8:
				_collect(b, it)
				break
	_items = _items.filter(func(it): return not it.gone)


func _collect(b: Ball, it: Item) -> void:
	it.gone = true
	var p := b.player
	match it.kind:
		ITEM_COIN:
			add_score(p, COIN_SCORE)
			_pop(b.pos + Vector2(0, -46), "+%d" % COIN_SCORE, Color("c99b00"))
			_burst(it.pos, Color("ffd34d"), 8)
			Sfx.play("star", randf_range(1.0, 1.2))
		ITEM_GEM:
			add_score(p, GEM_SCORE)
			_pop(b.pos + Vector2(0, -46), "+%d" % GEM_SCORE, WiiTheme.ACCENT_DARK)
			_burst(it.pos, WiiTheme.ACCENT, 14)
			Sfx.play("accept", randf_range(1.2, 1.35))
		ITEM_BOMB:
			b.stun = STUN_TIME
			set_score(p, maxi(0, int(get_score(p)) - BOMB_PENALTY))
			_pop(b.pos + Vector2(0, -46), "-%d" % BOMB_PENALTY, Color("e25555"))
			_burst(it.pos, Color("e25555"), 18)
			Sfx.play("wave", 0.8)


func _item_radius(kind: int) -> float:
	match kind:
		ITEM_GEM:
			return GEM_RADIUS
		ITEM_BOMB:
			return BOMB_RADIUS
	return COIN_RADIUS


func _pop(at: Vector2, text: String, color: Color) -> void:
	_pops.append([at, text, color, 0.0])


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(90.0, 360.0)
		_bursts.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.4, 0.8)])


func _update_effects(delta: float) -> void:
	for p in _pops:
		p[3] += delta
	_pops = _pops.filter(func(p): return p[3] < 0.9)
	for c in _bursts:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 700.0) * delta
		c[3] -= delta
	_bursts = _bursts.filter(func(c): return c[3] > 0.0)


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	_draw_ground()
	for it in _items:
		_draw_item(it)
	for b in _balls:
		_draw_ball(b)
	for c in _bursts:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)),
				Color(c[2], clampf(c[3] * 2.0, 0.0, 1.0)))
	for p in _pops:
		var t: float = p[3]
		draw_text_centered(p[1], p[0] + Vector2(0, -40.0 * t), 26,
				Color(p[2], clampf(1.0 - t / 0.9, 0.0, 1.0)))


func _draw_ground() -> void:
	var floor_rect := Rect2(ARENA.position.x, GROUND_Y, ARENA.size.x, ARENA.end.y - GROUND_Y)
	draw_rect(floor_rect, Color("e8edf1"))
	draw_line(Vector2(ARENA.position.x + 14, GROUND_Y), Vector2(ARENA.end.x - 14, GROUND_Y),
			WiiTheme.PANEL_BORDER, 4.0)


func _draw_item(it: Item) -> void:
	var r := _item_radius(it.kind)
	if it.pos.y < ARENA.position.y + r:
		return  # todavía no ha entrado en la zona visible
	match it.kind:
		ITEM_COIN:
			var sx := 0.35 + 0.65 * absf(cos(it.spin))
			draw_set_transform(it.pos, 0.0, Vector2(sx, 1.0))
			draw_circle(Vector2.ZERO, r, Color("ffd34d"))
			draw_circle(Vector2.ZERO, r * 0.62, Color("ffe89a"))
			draw_arc(Vector2.ZERO, r - 1.0, 0.0, TAU, 24, Color("d9a300"), 2.5, true)
			draw_set_transform(Vector2.ZERO)
		ITEM_GEM:
			var pts := PackedVector2Array()
			for i in 4:
				pts.append(it.pos + Vector2.UP.rotated(it.spin * 0.8 + i * TAU / 4.0) * r)
			draw_colored_polygon(pts, WiiTheme.ACCENT)
			var outline := pts.duplicate()
			outline.append(pts[0])
			draw_polyline(outline, Color.WHITE, 3.0, true)
			draw_circle(it.pos + Vector2(-r * 0.25, -r * 0.25), r * 0.24,
					Color(1, 1, 1, 0.5))
		ITEM_BOMB:
			draw_circle(it.pos, r, Color("e25555"))
			draw_circle(it.pos + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.4))
			draw_line(it.pos + Vector2(r * 0.5, -r * 0.6), it.pos + Vector2(r * 0.9, -r * 1.2),
					Color("5b6670"), 3.0)
			draw_circle(it.pos + Vector2(r * 0.95, -r * 1.25), 4.0, Color("ffd34d"))


func _draw_ball(b: Ball) -> void:
	var alpha := 1.0
	if b.stun > 0.0:
		alpha = 0.4 + 0.6 * absf(sin(_time * 18.0))
	var height := clampf((GROUND_Y - BALL_RADIUS - b.pos.y) / 260.0, 0.0, 1.0)
	var shadow_scale := lerpf(1.0, 0.55, height)
	# Sombra en el suelo, más pequeña cuanto más alto salta.
	draw_set_transform(Vector2(b.pos.x, GROUND_Y - 4.0), 0.0,
			Vector2(shadow_scale * 1.15, 0.3))
	draw_circle(Vector2.ZERO, BALL_RADIUS, Color(WiiTheme.SHADOW, WiiTheme.SHADOW.a * alpha))
	draw_set_transform(Vector2.ZERO)
	var col := b.player.color
	if not b.player.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	col.a = alpha
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos, 0.0, stretch)
	draw_circle(Vector2.ZERO, BALL_RADIUS, col)
	draw_circle(Vector2(0, BALL_RADIUS * 0.25), BALL_RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-BALL_RADIUS * 0.3, -BALL_RADIUS * 0.35), BALL_RADIUS * 0.38,
			Color(1, 1, 1, 0.4 * alpha))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(b.player.index + 1), b.pos, 28, Color(1, 1, 1, alpha))
	if b.stun > 0.0:
		draw_arc(b.pos, BALL_RADIUS + 8.0, 0.0, TAU, 24, Color("e25555", 0.8), 4.0, true)
		draw_text_centered("!", b.pos + Vector2(0, -BALL_RADIUS - 24.0), 28,
				Color("e25555", alpha))

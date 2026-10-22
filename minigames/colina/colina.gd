extends MinigameBase
## "Rey de la colina": una zona circular cambia de sitio cada 8 s. Solo suma
## quien esté SOLO dentro (1 punto cada 0.5 s). A da una embestida para echar
## a los demás.

const BALL_RADIUS := 30.0
const MAX_SPEED := 400.0
const STEER := 8.5
const LUNGE_SPEED := 700.0
const LUNGE_PUSH := 950.0
const LUNGE_RADIUS := 120.0
const LUNGE_COOLDOWN := 1.0
const ZONE_RADIUS := 110.0
const ZONE_PERIOD := 8.0
const ZONE_WARN := 1.5
const ZONE_EDGE_MARGIN := 12.0  # distancia mínima de la zona al borde de la arena
const ZONE_MIN_JUMP := 380.0     # la zona nueva aparece al menos así de lejos
const TICK := 0.5


class Ball:
	var player: Player
	var pos: Vector2
	var vel := Vector2.ZERO
	var lunge_cd := 0.0
	var lunge_t := 0.0
	var squash := 1.0
	var aim := Vector2.RIGHT


var _balls: Array[Ball] = []
var _zone_pos := Vector2.ZERO
var _zone_next := Vector2.ZERO
var _zone_timer := ZONE_PERIOD
var _ring_t := 0.0
var _ring_player: Player = null
var _contested := false
var _confetti: Array = []
var _time := 0.0


func _configure() -> void:
	title = {"es": "Rey de la colina", "en": "King of the Hill"}
	instructions = {"es": "Quédate solo en la zona brillante y echa a los demás.",
		"en": "Stay alone in the glowing zone and push the others out."}
	controls = [
		["stick", {"es": "Moverse", "en": "Move"}],
		[Pad.A, {"es": "Embestida", "en": "Charge"}],
	]
	duration = 50.0


func _setup() -> void:
	var c := ARENA.get_center()
	_zone_pos = c
	_zone_next = _random_zone_pos()
	for p in players:
		var b := Ball.new()
		b.player = p
		var ang := -PI / 2.0 + TAU * float(p.index) / float(maxi(1, players.size()))
		b.pos = c + Vector2.RIGHT.rotated(ang) * 220.0
		_balls.append(b)


func _game_process(delta: float) -> void:
	_time += delta
	_update_zone(delta)
	for b in _balls:
		_update_ball(b, delta)
	_collide_balls()
	_update_scoring(delta)
	_update_effects(delta)


## Siguiente zona: en cualquier parte (también pegada a bordes y esquinas) y lejos
## de la actual, para que haya que cruzar la arena. Se prueban varios candidatos y
## se queda el primero suficientemente lejano.
func _random_zone_pos() -> Vector2:
	var lo := ARENA.position + Vector2(ZONE_RADIUS + ZONE_EDGE_MARGIN, ZONE_RADIUS + ZONE_EDGE_MARGIN)
	var hi := ARENA.end - Vector2(ZONE_RADIUS + ZONE_EDGE_MARGIN, ZONE_RADIUS + ZONE_EDGE_MARGIN)
	var best := Vector2(randf_range(lo.x, hi.x), randf_range(lo.y, hi.y))
	for i in 16:
		if best.distance_to(_zone_pos) >= ZONE_MIN_JUMP:
			break
		best = Vector2(randf_range(lo.x, hi.x), randf_range(lo.y, hi.y))
	return best


func _update_zone(delta: float) -> void:
	_zone_timer -= delta
	if _zone_timer <= 0.0:
		_zone_pos = _zone_next
		_zone_next = _random_zone_pos()
		_zone_timer = ZONE_PERIOD
		_ring_t = 0.0
		_ring_player = null
		_burst(_zone_pos, WiiTheme.ACCENT, 18)
		Sfx.play("wave", 1.3)


func _update_ball(b: Ball, delta: float) -> void:
	var p := b.player
	b.lunge_cd = maxf(0.0, b.lunge_cd - delta)
	b.lunge_t = maxf(0.0, b.lunge_t - delta)
	b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 10.0))
	var dir := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	if dir != Vector2.ZERO:
		b.aim = dir.normalized()
		b.vel = b.vel.lerp(dir * MAX_SPEED, 1.0 - exp(-STEER * delta))
	else:
		b.vel *= exp(-STEER * 0.5 * delta)
	if p.just_pressed(Pad.A) and b.lunge_cd <= 0.0:
		_lunge(b)
	b.pos += b.vel * delta
	b.pos = _clamped_arena(b.pos, BALL_RADIUS)


func _lunge(b: Ball) -> void:
	b.lunge_cd = LUNGE_COOLDOWN
	b.lunge_t = 0.25
	b.vel += b.aim * LUNGE_SPEED
	b.squash = 1.3
	_burst(b.pos + b.aim * 16.0, b.player.color, 10)
	Sfx.play("dash", randf_range(0.95, 1.1))
	for o in _balls:
		if o == b:
			continue
		var d := o.pos - b.pos
		if d.length() < LUNGE_RADIUS + BALL_RADIUS and d.length() > 0.01:
			o.vel += d.normalized() * LUNGE_PUSH * (1.0 - d.length() / (LUNGE_RADIUS + BALL_RADIUS))
			o.squash = 0.82
			_burst(o.pos, o.player.color, 6)
			Sfx.play("pop", randf_range(0.9, 1.1))


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a := _balls[i]
			var b := _balls[j]
			var d := b.pos - a.pos
			var dist := d.length()
			if dist < BALL_RADIUS * 2.0 and dist > 0.01:
				var n := d / dist
				var overlap := BALL_RADIUS * 2.0 - dist
				a.pos = _clamped_arena(a.pos - n * overlap * 0.5, BALL_RADIUS)
				b.pos = _clamped_arena(b.pos + n * overlap * 0.5, BALL_RADIUS)
				var rel := (b.vel - a.vel).dot(n)
				if rel < 0.0:
					a.vel += n * rel * 0.95
					b.vel -= n * rel * 0.95
					if absf(rel) > 260.0:
						Sfx.play("pop", randf_range(0.9, 1.2))


func _update_scoring(delta: float) -> void:
	var inside: Array[Ball] = []
	for b in _balls:
		if b.pos.distance_to(_zone_pos) < ZONE_RADIUS - BALL_RADIUS * 0.4:
			inside.append(b)
	_contested = inside.size() >= 2
	if inside.size() == 1:
		var b := inside[0]
		if _ring_player != b.player:
			_ring_player = b.player
			_ring_t = 0.0
		_ring_t += delta
		if _ring_t >= TICK:
			_ring_t -= TICK
			add_score(b.player)
			Sfx.play("star", randf_range(0.95, 1.08))
	else:
		_ring_player = null
		_ring_t = 0.0


func _clamped_arena(pos: Vector2, r: float) -> Vector2:
	return Vector2(clampf(pos.x, ARENA.position.x + r, ARENA.end.x - r),
			clampf(pos.y, ARENA.position.y + r, ARENA.end.y - r))


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(100.0, 380.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.4, 0.8)])


func _update_effects(delta: float) -> void:
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 380) * delta
		c[3] -= delta
	_confetti = _confetti.filter(func(c): return c[3] > 0.0)


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	draw_rect(ARENA.grow(-10.0), Color("f2f6f8"))
	_draw_zone()
	for b in _balls:
		_draw_ball(b)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(3, 3), Vector2(6, 6)), Color(c[2], clampf(c[3] * 2.0, 0.0, 1.0)))


func _draw_zone() -> void:
	var ring_col := WiiTheme.ACCENT
	if _ring_player != null:
		ring_col = _ring_player.color
	elif _contested:
		ring_col = Color("e25555")
	# Relleno suave que late.
	var pulse := 1.0 + sin(_time * 4.0) * 0.03
	draw_circle(_zone_pos, ZONE_RADIUS * pulse, Color(ring_col, 0.13))
	draw_circle(_zone_pos, ZONE_RADIUS * 0.72, Color(ring_col, 0.10))
	var lw := 8.0
	if _contested:
		# Zona disputada: parpadea.
		lw = 5.0 + 4.0 * absf(sin(_time * 9.0))
		draw_arc(_zone_pos, ZONE_RADIUS, 0, TAU, 48, Color(1.0, 0.35, 0.35, 0.85), lw, true)
		draw_text_centered(loc({"es": "¡Disputada!", "en": "Contested!"}),
				_zone_pos + Vector2(0, -ZONE_RADIUS - 26.0), 26, Color("e25555"))
	else:
		draw_arc(_zone_pos, ZONE_RADIUS, 0, TAU, 48, Color(ring_col, 0.9), lw, true)
		if _ring_player != null:
			# Anillo de progreso hacia el siguiente punto.
			var t := clampf(_ring_t / TICK, 0.0, 1.0)
			draw_arc(_zone_pos, ZONE_RADIUS + 13.0, -PI / 2.0, -PI / 2.0 + TAU * t,
					40, _ring_player.color, 9.0, true)
			draw_text_centered(str(_ring_player.index + 1),
					_zone_pos + Vector2(0, -ZONE_RADIUS - 26.0), 24, _ring_player.color)
	# Aviso de la próxima zona.
	if _zone_timer <= ZONE_WARN:
		var a := 0.35 + 0.35 * absf(sin(_time * 7.0))
		draw_arc(_zone_next, ZONE_RADIUS * 0.6, 0, TAU, 40, Color(WiiTheme.ACCENT_DARK, a), 5.0, true)
		draw_arc(_zone_next, ZONE_RADIUS, 0, TAU, 40, Color(WiiTheme.ACCENT_DARK, a * 0.6), 3.0, true)
		draw_circle(_zone_next, 8.0, Color(WiiTheme.ACCENT_DARK, a))


func _draw_ball(b: Ball) -> void:
	var col := b.player.color
	if not b.player.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	if b.lunge_t > 0.0:
		col = col.lightened(0.15)
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos + Vector2(0, 6), 0, Vector2(stretch.x * 1.1, 0.35))
	draw_circle(Vector2.ZERO, BALL_RADIUS, WiiTheme.SHADOW)
	draw_set_transform(b.pos, 0, stretch)
	draw_circle(Vector2.ZERO, BALL_RADIUS, col)
	draw_circle(Vector2(0, BALL_RADIUS * 0.25), BALL_RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-BALL_RADIUS * 0.3, -BALL_RADIUS * 0.35), BALL_RADIUS * 0.38, Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(b.player.index + 1), b.pos, 26, Color.WHITE)

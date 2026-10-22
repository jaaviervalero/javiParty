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
# Ambiente: pradera en primavera.
const MEADOW_TOP := Color("b9e59b")
const MEADOW_BOTTOM := Color("8ed16f")
const PATCH_DARK := Color("7cc45e")
const PATCH_LIGHT := Color("c6ea9f")
const PATH := Color("e8d6a8")
const BUSH := Color("6fb851")
const ZONE_GOLD := Color("ffd34d")
const ZONE_CYAN := Color("6fe3f5")


class Ball:
	var player: Player
	var pos: Vector2
	var vel := Vector2.ZERO
	var lunge_cd := 0.0
	var lunge_t := 0.0
	var squash := 1.0
	var aim := Vector2.RIGHT


var _balls: Array = []
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
		var ang := -PI / 2.0 + TAU * float(p.index) / float(max(1, players.size()))
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
	var best := Vector2(rand_range(lo.x, hi.x), rand_range(lo.y, hi.y))
	for i in 16:
		if best.distance_to(_zone_pos) >= ZONE_MIN_JUMP:
			break
		best = Vector2(rand_range(lo.x, hi.x), rand_range(lo.y, hi.y))
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
	b.lunge_cd = max(0.0, b.lunge_cd - delta)
	b.lunge_t = max(0.0, b.lunge_t - delta)
	b.squash = lerp(b.squash, 1.0, min(1.0, delta * 10.0))
	var dir: Vector2 = p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	if dir != Vector2.ZERO:
		b.aim = dir.normalized()
		b.vel = b.vel.linear_interpolate(dir * MAX_SPEED, 1.0 - exp(-STEER * delta))
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
	Sfx.play("dash", rand_range(0.95, 1.1))
	for o in _balls:
		if o == b:
			continue
		var d: Vector2 = o.pos - b.pos
		if d.length() < LUNGE_RADIUS + BALL_RADIUS and d.length() > 0.01:
			o.vel += d.normalized() * LUNGE_PUSH * (1.0 - d.length() / (LUNGE_RADIUS + BALL_RADIUS))
			o.squash = 0.82
			_burst(o.pos, o.player.color, 6)
			Sfx.play("pop", rand_range(0.9, 1.1))


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a: Ball = _balls[i]
			var b: Ball = _balls[j]
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
					if abs(rel) > 260.0:
						Sfx.play("pop", rand_range(0.9, 1.2))


func _update_scoring(delta: float) -> void:
	var inside: Array = []
	for b in _balls:
		if b.pos.distance_to(_zone_pos) < ZONE_RADIUS - BALL_RADIUS * 0.4:
			inside.append(b)
	_contested = inside.size() >= 2
	if inside.size() == 1:
		var b: Ball = inside[0]
		if _ring_player != b.player:
			_ring_player = b.player
			_ring_t = 0.0
		_ring_t += delta
		if _ring_t >= TICK:
			_ring_t -= TICK
			add_score(b.player)
			Sfx.play("star", rand_range(0.95, 1.08))
	else:
		_ring_player = null
		_ring_t = 0.0


func _clamped_arena(pos: Vector2, r: float) -> Vector2:
	return Vector2(clamp(pos.x, ARENA.position.x + r, ARENA.end.x - r),
			clamp(pos.y, ARENA.position.y + r, ARENA.end.y - r))


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * rand_range(100.0, 380.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color(1, 1, 1, 1), rand_range(0.4, 0.8)])


func _update_effects(delta: float) -> void:
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 380) * delta
		c[3] -= delta
	var live_confetti: Array = []
	for c in _confetti:
		if c[3] > 0.0:
			live_confetti.append(c)
	_confetti = live_confetti


# --- Dibujo ---

## Ambiente fijo: pradera en primavera. Se pinta una vez.
func _draw_scenery(ci: CanvasItem) -> void:
	DrawKit.arena_frame(ci, ARENA, MEADOW_TOP, MEADOW_BOTTOM)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	# Manchas suaves de césped de dos tonos.
	for i in 10:
		var p := Vector2(rng.randf_range(ARENA.position.x + 60.0, ARENA.end.x - 60.0),
				rng.randf_range(ARENA.position.y + 60.0, ARENA.end.y - 60.0))
		var radii := Vector2(rng.randf_range(90.0, 210.0), rng.randf_range(40.0, 80.0))
		var col: Color = PATCH_DARK if i % 2 == 0 else PATCH_LIGHT
		DrawKit.ellipse(ci, p, radii, Color(col, 0.32))
	_draw_path(ci)
	# Matas en los bordes y flores repartidas (siempre las mismas).
	for i in 9:
		var t := float(i) / 8.0
		var p := Vector2(lerp(ARENA.position.x + 50.0, ARENA.end.x - 50.0, t),
				ARENA.position.y + 40.0 if i % 2 == 0 else ARENA.end.y - 42.0)
		DrawKit.ellipse(ci, p + Vector2(0, 6.0), Vector2(30.0, 10.0), Color(BUSH, 0.25))
		ci.draw_circle(p, 20.0, BUSH)
		ci.draw_circle(p + Vector2(-12.0, -4.0), 13.0, Color(BUSH, 0.85))
		ci.draw_circle(p + Vector2(11.0, -6.0), 11.0, Color(PATCH_DARK, 0.9))
		ci.draw_circle(p + Vector2(-2.0, -12.0), 7.0, Color(1, 1, 1, 0.18))
	for i in 16:
		var p := Vector2(rng.randf_range(ARENA.position.x + 70.0, ARENA.end.x - 70.0),
				rng.randf_range(ARENA.position.y + 80.0, ARENA.end.y - 70.0))
		var petal := Color(1, 1, 1, 1) if i % 3 == 0 else Color("ffd1e3") if i % 3 == 1 else Color("ffe9a8")
		DrawKit.flower(ci, p, rng.randf_range(5.0, 8.0), petal)
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 36.0, ARENA.end.y - 18.0),
			Vector2(ARENA.end.x - 36.0, ARENA.end.y - 18.0), 16, DrawKit.GRASS_DARK, 8)
	DrawKit.arena_border(ci, ARENA)


## Camino de tierra que cruza la pradera por abajo.
func _draw_path(ci: CanvasItem) -> void:
	var steps := 16
	var base_y := ARENA.end.y - 110.0
	var pts := PoolVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		pts.append(Vector2(ARENA.position.x - 10.0 + (ARENA.size.x + 20.0) * t,
				base_y + sin(t * TAU * 0.8) * 46.0 - 30.0))
	for i in steps + 1:
		var t := 1.0 - float(i) / steps
		pts.append(Vector2(ARENA.position.x - 10.0 + (ARENA.size.x + 20.0) * t,
				base_y + sin(t * TAU * 0.8) * 46.0 + 30.0))
	DrawKit.clipped_polygon(ci, pts, DrawKit.rounded_rect_points(ARENA, 30), Color(PATH, 0.55))


## MinigameBase llama a queue_redraw() cada frame: aquí solo lo que se mueve.
func _draw() -> void:
	_draw_petals()
	_draw_zone()
	for b in _balls:
		_draw_ball(b)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(3, 3), Vector2(6, 6)), Color(c[2], clamp(c[3] * 2.0, 0.0, 1.0)))


## Pétalos que flotan despacio: cuatro, baratos.
func _draw_petals() -> void:
	for i in 4:
		var t := _time * 0.3 + float(i) * 1.7
		var p := Vector2(ARENA.position.x + fposmod(t * 110.0 + float(i) * 300.0, ARENA.size.x),
				ARENA.position.y + 90.0 + fposmod(t * 46.0 + float(i) * 170.0, ARENA.size.y - 140.0))
		draw_set_transform(p, sin(t) * 0.9, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, 5.0, Color("ffd1e3", 0.8))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_zone() -> void:
	var ring_col := WiiTheme.ACCENT
	if _ring_player != null:
		ring_col = _ring_player.color
	elif _contested:
		ring_col = Color("e25555")
	# Halo dorado que late: la zona tiene que verse desde el sofá.
	var pulse := 1.0 + sin(_time * 3.2) * 0.05
	var glow := ZONE_RADIUS * pulse
	draw_circle(_zone_pos, glow * 1.30, Color(ZONE_GOLD, 0.10))
	draw_circle(_zone_pos, glow * 1.12, Color(ZONE_GOLD, 0.16))
	draw_circle(_zone_pos, glow * 0.88, Color(1.0, 0.96, 0.74, 0.32))
	# Aros cian girando por fuera del dorado.
	var spin := _time * 0.7
	draw_arc(_zone_pos, glow + 18.0, spin, spin + TAU * 0.72, 40, Color(ZONE_CYAN, 0.55), 4.0, true)
	draw_arc(_zone_pos, glow + 27.0, -spin * 0.8, -spin * 0.8 + TAU * 0.5, 36,
			Color(ZONE_CYAN, 0.3), 3.0, true)
	draw_arc(_zone_pos, glow + 6.0, 0, TAU, 48, Color(ZONE_GOLD, 0.95), 6.0, true)
	# Relleno del estado (jugador, disputada...).
	draw_circle(_zone_pos, ZONE_RADIUS * pulse, Color(ring_col, 0.13))
	draw_circle(_zone_pos, ZONE_RADIUS * 0.72, Color(ring_col, 0.10))
	var lw := 8.0
	if _contested:
		# Zona disputada: parpadea.
		lw = 5.0 + 4.0 * abs(sin(_time * 9.0))
		draw_arc(_zone_pos, ZONE_RADIUS, 0, TAU, 48, Color(1.0, 0.35, 0.35, 0.85), lw, true)
		draw_text_centered(loc({"es": "¡Disputada!", "en": "Contested!"}),
				_zone_pos + Vector2(0, -ZONE_RADIUS - 26.0), 26, Color("e25555"))
	else:
		draw_arc(_zone_pos, ZONE_RADIUS, 0, TAU, 48, Color(ring_col, 0.9), lw, true)
		if _ring_player != null:
			# Anillo de progreso hacia el siguiente punto.
			var t := clamp(_ring_t / TICK, 0.0, 1.0)
			draw_arc(_zone_pos, ZONE_RADIUS + 13.0, -PI / 2.0, -PI / 2.0 + TAU * t,
					40, _ring_player.color, 9.0, true)
			draw_text_centered(str(_ring_player.index + 1),
					_zone_pos + Vector2(0, -ZONE_RADIUS - 26.0), 24, _ring_player.color)
	# Aviso de la próxima zona.
	if _zone_timer <= ZONE_WARN:
		var a := 0.35 + 0.35 * abs(sin(_time * 7.0))
		draw_arc(_zone_next, ZONE_RADIUS * 0.6, 0, TAU, 40, Color(WiiTheme.ACCENT_DARK, a), 5.0, true)
		draw_arc(_zone_next, ZONE_RADIUS, 0, TAU, 40, Color(WiiTheme.ACCENT_DARK, a * 0.6), 3.0, true)
		draw_circle(_zone_next, 8.0, Color(WiiTheme.ACCENT_DARK, a))


func _draw_ball(b: Ball) -> void:
	var col := b.player.color
	if not b.player.is_connected_now():
		col = col.linear_interpolate(Color("c8ced4"), 0.7)
	if b.lunge_t > 0.0:
		col = col.lightened(0.15)
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos + Vector2(0, 6), 0, Vector2(stretch.x * 1.1, 0.35))
	draw_circle(Vector2.ZERO, BALL_RADIUS, WiiTheme.SHADOW)
	draw_set_transform(b.pos, 0, stretch)
	draw_circle(Vector2.ZERO, BALL_RADIUS, col)
	draw_circle(Vector2(0, BALL_RADIUS * 0.25), BALL_RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-BALL_RADIUS * 0.3, -BALL_RADIUS * 0.35), BALL_RADIUS * 0.38, Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_text_centered(str(b.player.index + 1), b.pos, 26, Color(1, 1, 1, 1))

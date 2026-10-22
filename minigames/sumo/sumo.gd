extends MinigameBase
## "Sumo de bolas": todos sobre una plataforma circular que encoge. Empuja y
## embiste para echar a los demás; la última bola en pie gana la ronda.
## Hasta 3 rondas. Con un solo jugador lo persiguen dos bolas grises.

const BALL_RADIUS := 28.0
const MAX_SPEED := 360.0
const BOT_SPEED := 260.0
const STEER := 8.0
const DASH_SPEED := 500.0
const DASH_COOLDOWN := 1.0
const PLATFORM_RADIUS := 260.0
const PLATFORM_MIN_RADIUS := 70.0
const SHRINK_SPEED := 5.5
const ROUNDS := 3
const ROUND_PAUSE := 1.8
const SOLO_ROUND_TIME := 20.0
const SOLO_BOTS := 2
const FALL_TIME := 0.7
const BOT_COLOR := Color("aeb8c2")

# Ambiente: plataforma de madera clara flotando sobre un mar de nubes.
const SKY_TOP := Color("c8ecfb")
const SKY_BOTTOM := Color("f2fbff")
const CLOUD_HAZE := Color("dff2fb")
const PLATFORM_TOP := Color("fbf1dd")
const PLATFORM_EDGE := Color("dcc6a3")
const PLATFORM_DANGER := Color("ffe0e0")


## Una bola. player == null en los bots del modo de un jugador.
class Ball:
	var player: Player
	var color: Color
	var pos: Vector2
	var vel := Vector2.ZERO
	var face := Vector2.RIGHT
	var dash_cd := 0.0
	var squash := 1.0
	var alive := true
	var fall := 0.0
	var bot := false


var _balls: Array[Ball] = []
var _center := Vector2.ZERO
var _radius := PLATFORM_RADIUS
var _round := 0
var _round_time := 0.0
var _pause_left := 0.0
var _in_pause := false
var _banner := ""
var _banner_color := WiiTheme.TEXT
var _time := 0.0
var _solo := false
var _rings: Array = []      # [pos, t, color]
var _confetti: Array = []   # [pos, vel, color, vida]


func _configure() -> void:
	title = {"es": "Sumo de bolas", "en": "Ball sumo"}
	instructions = {"es": "Empuja y embiste: la última bola sobre la plataforma gana la ronda.",
		"en": "Push and dash: the last ball on the platform wins the round."}
	controls = [
		["stick", {"es": "Moverse", "en": "Move"}],
		[Pad.A, {"es": "Embestir", "en": "Dash"}],
	]
	duration = 75.0


func _setup() -> void:
	_center = ARENA.get_center()
	_solo = players.size() <= 1


func _game_start() -> void:
	_round = 0
	_start_round()


func _start_round() -> void:
	_round += 1
	_round_time = 0.0
	_radius = PLATFORM_RADIUS
	_center = ARENA.get_center()
	_in_pause = false
	_pause_left = 0.0
	_banner = ""
	_balls.clear()
	if _solo:
		_spawn(players[0], _center + Vector2(-140, 0), false)
		for i in SOLO_BOTS:
			_spawn(null, _center + Vector2(130, -70 + 140 * i), true)
	else:
		var n := players.size()
		for i in n:
			var ang := -PI * 0.5 + TAU * float(i) / float(n)
			_spawn(players[i], _center + Vector2(cos(ang), sin(ang)) * 150.0, false)
	Sfx.play("join", randf_range(1.0, 1.1))


func _spawn(p: Player, pos: Vector2, bot: bool) -> void:
	var b := Ball.new()
	b.player = p
	b.color = p.color if p != null else BOT_COLOR
	b.pos = pos
	b.bot = bot
	_balls.append(b)


func _game_process(delta: float) -> void:
	_time += delta
	_update_effects(delta)
	if _in_pause:
		_pause_left -= delta
		if _pause_left <= 0.0:
			if _round >= ROUNDS:
				finish()
			else:
				_start_round()
		return
	_round_time += delta
	_radius = maxf(PLATFORM_MIN_RADIUS, _radius - SHRINK_SPEED * delta)
	for b in _balls:
		if b.alive:
			_update_ball(b, delta)
		else:
			b.fall += delta
	_collide_balls()
	_check_falls()
	_check_round_end()


func _update_ball(b: Ball, delta: float) -> void:
	b.dash_cd = maxf(0.0, b.dash_cd - delta)
	b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 10.0))
	var dir := _control_dir(b)
	if dir != Vector2.ZERO:
		b.face = dir
		var top := BOT_SPEED if b.bot else MAX_SPEED
		b.vel = b.vel.lerp(dir * top, 1.0 - exp(-STEER * delta))
	else:
		b.vel *= exp(-STEER * 0.5 * delta)
	if not b.bot and b.player.just_pressed(Pad.A) and b.dash_cd <= 0.0:
		b.vel += b.face.normalized() * DASH_SPEED
		b.dash_cd = DASH_COOLDOWN
		b.squash = 1.35
		_rings.append([b.pos, 0.0, b.color])
		Sfx.play("dash", randf_range(0.95, 1.1))
	b.pos += b.vel * delta


func _control_dir(b: Ball) -> Vector2:
	if not b.bot:
		var p := b.player
		var d := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
		return d.normalized() if d.length() > 1.0 else d
	var target := _player_ball()
	if target == null or not target.alive:
		return Vector2.ZERO
	var to := target.pos - b.pos
	if to.length() < 1.0:
		return Vector2.ZERO
	# Persecución con un ligero zigzag para que no vayan en línea recta perfecta.
	var side := to.normalized().orthogonal() * sin(_time * 2.2 + b.pos.x * 0.01) * 0.5
	return (to.normalized() + side).normalized()


func _player_ball() -> Ball:
	for b in _balls:
		if b.player != null:
			return b
	return null


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a := _balls[i]
			var b := _balls[j]
			if not a.alive or not b.alive:
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist >= BALL_RADIUS * 2.0 or dist < 0.01:
				continue
			var n := d / dist
			var overlap := BALL_RADIUS * 2.0 - dist
			a.pos -= n * overlap * 0.5
			b.pos += n * overlap * 0.5
			# Choque elástico con masas iguales.
			var rel := (b.vel - a.vel).dot(n)
			if rel < 0.0:
				a.vel += n * rel
				b.vel -= n * rel
				a.squash = 0.86
				b.squash = 0.86
				if absf(rel) > 240.0:
					Sfx.play("pop", randf_range(0.9, 1.15))


func _check_falls() -> void:
	for b in _balls:
		if b.alive and b.pos.distance_to(_center) > _radius:
			b.alive = false
			b.fall = 0.0
			b.squash = 1.0
			_rings.append([b.pos, 0.0, b.color])
			_burst(b.pos, b.color, 10)
			Sfx.play("leave", randf_range(0.9, 1.1))


func _check_round_end() -> void:
	var alive_players := 0
	var alive_bots := 0
	var last_alive: Ball = null
	for b in _balls:
		if not b.alive:
			continue
		if b.player == null:
			alive_bots += 1
		else:
			alive_players += 1
			last_alive = b
	if _solo:
		if alive_players == 0:
			_end_round(loc({"es": "Los bots ganan la ronda", "en": "The bots win the round"}),
					BOT_COLOR, false)
		elif alive_bots == 0:
			add_score(players[0], 1)
			_end_round(loc({"es": "Has echado a los bots: +1", "en": "You pushed the bots out: +1"}),
					players[0].color, true)
		elif _round_time >= SOLO_ROUND_TIME:
			add_score(players[0], 1)
			_end_round(loc({"es": "Has sobrevivido: +1", "en": "You survived: +1"}),
					players[0].color, true)
	else:
		if alive_players > 1:
			return
		if alive_players == 1:
			add_score(last_alive.player, 1)
			var txt := loc({"es": "Jugador %d gana la ronda", "en": "Player %d wins the round"}) \
					% (last_alive.player.index + 1)
			_end_round(txt, last_alive.color, true)
		else:
			_end_round(loc({"es": "Nadie sobrevive la ronda", "en": "Nobody survives the round"}),
					WiiTheme.TEXT_SOFT, false)


func _end_round(text: String, color: Color, won: bool) -> void:
	_banner = text
	_banner_color = color
	_in_pause = true
	_pause_left = ROUND_PAUSE
	if won:
		Sfx.play("star", randf_range(1.0, 1.1))
	else:
		Sfx.play("back", 0.9)


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(100.0, 380.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.45, 0.85)])


func _update_effects(delta: float) -> void:
	for r in _rings:
		r[1] += delta * 2.4
	_rings = _rings.filter(func(r): return r[1] < 1.0)
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-2.5 * delta) + Vector2(0, 400.0) * delta
		c[3] -= delta
	_confetti = _confetti.filter(func(c): return c[3] > 0.0)


# --- Dibujo ---

## Cielo y mar de nubes: se pinta una sola vez (ver MinigameBase._draw_scenery).
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	DrawKit.arena_frame(ci, ARENA, SKY_TOP, SKY_BOTTOM)
	DrawKit.sun(ci, Vector2(ARENA.end.x - 120, ARENA.position.y + 76), 30)
	# Suelo de nubes: dos capas de colinas muy claras recortadas a la arena.
	DrawKit.hills(ci, ARENA, ARENA.end.y - 92, 30, Color(CLOUD_HAZE, 0.75), 1.4, 1.7, clip)
	DrawKit.hills(ci, ARENA, ARENA.end.y - 44, 18, Color(1, 1, 1, 0.9), 3.1, 1.3, clip)
	# Nubes fijas alrededor del centro (que lo ocupa la plataforma).
	var spots: Array[Vector3] = [
		Vector3(ARENA.position.x + 150, ARENA.position.y + 250, 1.15),
		Vector3(ARENA.end.x - 160, ARENA.position.y + 300, 1.0),
		Vector3(ARENA.position.x + 190, ARENA.end.y - 70, 1.35),
		Vector3(ARENA.end.x - 200, ARENA.end.y - 90, 1.25),
	]
	for s in spots:
		DrawKit.cloud(ci, Vector2(s.x, s.y), s.z, Color(1, 1, 1, 0.85))
	DrawKit.arena_border(ci, ARENA)


## Nubes que derivan despacio por detrás de la plataforma (lo único animado del fondo).
func _draw_clouds() -> void:
	var bases: Array[Vector2] = [
		Vector2(ARENA.position.x + 170, ARENA.position.y + 150),
		Vector2(ARENA.end.x - 190, ARENA.position.y + 240),
		Vector2(ARENA.position.x + 210, ARENA.end.y - 80),
	]
	for i in bases.size():
		var drift := Vector2(sin(_time * 0.12 + i * 1.9) * 34.0, sin(_time * 0.08 + i) * 8.0)
		DrawKit.cloud(self, bases[i] + drift, 0.75 + i * 0.1, Color(1, 1, 1, 0.7))


func _draw() -> void:
	_draw_clouds()
	_draw_platform()
	for r in _rings:
		var t: float = r[1]
		draw_arc(r[0], 20.0 + 70.0 * t, 0.0, TAU, 48, Color(r[2], 0.55 * (1.0 - t)),
				5.0 * (1.0 - t) + 1.0, true)
	for b in _balls:
		_draw_ball(b)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)),
				Color(c[2], clampf(c[3] * 2.0, 0.0, 1.0)))
	_draw_round_label()
	if _in_pause and _banner != "":
		_draw_banner()


func _draw_platform() -> void:
	var danger := 1.0 - clampf((_radius - PLATFORM_MIN_RADIUS)
			/ (PLATFORM_RADIUS - PLATFORM_MIN_RADIUS), 0.0, 1.0)
	var top := PLATFORM_TOP.lerp(PLATFORM_DANGER, danger * 0.7)
	var edge := PLATFORM_EDGE.lerp(PLATFORM_DANGER.darkened(0.08), danger * 0.55)
	# Sombra en las nubes y canto: dos discos desplazados abajo dan volumen.
	DrawKit.soft_shadow(self, _center + Vector2(0, _radius * 0.35 + 22.0), _radius * 1.7)
	draw_circle(_center + Vector2(0, 16.0), _radius - 2.0, edge.darkened(0.12))
	draw_circle(_center + Vector2(0, 8.0), _radius - 1.0, edge)
	draw_circle(_center, _radius, top)
	# Anillos de madera pintada, muy suaves.
	var rings: Array[float] = [0.36, 0.58, 0.78, 0.94]
	for f in rings:
		draw_arc(_center, maxf(8.0, _radius * f), 0.0, TAU, 48,
				Color(DrawKit.WOOD_DARK, 0.14), 2.0, true)
	DrawKit.ellipse(self, _center + Vector2(-_radius * 0.3, -_radius * 0.45),
			Vector2(_radius * 0.46, _radius * 0.2), Color(1, 1, 1, 0.16))
	draw_arc(_center, _radius - 2.5, 0.0, TAU, 48, Color.WHITE, 5.0, true)


func _draw_ball(b: Ball) -> void:
	if not b.alive and b.fall >= FALL_TIME:
		return
	var alpha := 1.0
	var shrink := 1.0
	if not b.alive:
		var t := clampf(b.fall / FALL_TIME, 0.0, 1.0)
		alpha = 1.0 - t
		shrink = 1.0 - t * 0.75
	var col: Color = b.color
	if b.player != null and not b.player.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	col.a = alpha
	var r := BALL_RADIUS * shrink
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos + Vector2(0, 6), 0.0, Vector2(stretch.x * 1.1, 0.35))
	draw_circle(Vector2.ZERO, r, Color(WiiTheme.SHADOW, WiiTheme.SHADOW.a * alpha))
	draw_set_transform(b.pos, 0.0, stretch * shrink)
	draw_circle(Vector2.ZERO, BALL_RADIUS, col)
	draw_circle(Vector2(0, BALL_RADIUS * 0.25), BALL_RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-BALL_RADIUS * 0.3, -BALL_RADIUS * 0.35), BALL_RADIUS * 0.38,
			Color(1, 1, 1, 0.4 * alpha))
	draw_set_transform(Vector2.ZERO)
	if b.player != null:
		if b.alive:
			draw_text_centered(str(b.player.index + 1), b.pos, 28, Color(1, 1, 1, alpha))
		# Aro de recarga de la embestida.
		if b.alive and b.dash_cd > 0.0:
			var t := 1.0 - b.dash_cd / DASH_COOLDOWN
			draw_arc(b.pos, BALL_RADIUS + 8.0, -PI * 0.5, -PI * 0.5 + TAU * t, 24,
					Color(b.color, 0.55), 3.0, true)
	elif b.alive:
		# Los bots no llevan número: un aro interior claro los distingue.
		draw_arc(b.pos, BALL_RADIUS * 0.5, 0.0, TAU, 24, Color(1, 1, 1, 0.5), 3.0, true)


func _draw_round_label() -> void:
	if _round <= 0 or _in_pause:
		return
	var txt := ""
	if _solo:
		var left := maxf(0.0, SOLO_ROUND_TIME - _round_time)
		txt = loc({"es": "Sobrevive %d s", "en": "Survive %d s"}) % int(ceil(left))
	else:
		txt = loc({"es": "Ronda %d de %d", "en": "Round %d of %d"}) % [_round, ROUNDS]
	draw_text_centered(txt, Vector2(_center.x, ARENA.position.y + 24.0), 22, WiiTheme.TEXT_SOFT)


func _draw_banner() -> void:
	var size := Vector2(640, 130)
	var rect := Rect2(_center - size * 0.5, size)
	var st := WiiTheme.panel_style(26, _banner_color)
	st.set_border_width_all(4)
	draw_style_box(st, rect)
	draw_text_centered(_banner, _center + Vector2(0, -12), 28, WiiTheme.TEXT)
	var sub := loc({"es": "Ronda %d de %d", "en": "Round %d of %d"}) % [_round, ROUNDS]
	draw_text_centered(sub, _center + Vector2(0, 34), 22, WiiTheme.TEXT_SOFT)

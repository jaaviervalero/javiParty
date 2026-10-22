extends MinigameBase
## "Banderas en la playa": todos empiezan tumbados en la arena y, tras la señal,
## hay que levantarse y correr machacando A para coger una bandera. Siempre hay
## una bandera menos que jugadores vivos: quien se queda sin ella cae eliminado.
## Con 1 jugador se compite contra un rival fantasma que acelera cada ronda.

const RUNNER_RADIUS := 22.0
const START_X := 120.0
const FLAG_X := 883.0          # ~70% del ancho de la arena
const GRAB_X := 861.0
const HORIZON := 272.0
const SAND_TOP := 430.0
const RUN_TOP := 486.0
const RUN_BOTTOM := 668.0
const POLE_H := 54.0
const PREP_MIN := 1.5
const PREP_MAX := 4.0
const PENALTY := 1.0
const RISE_TIME := 0.32
const IMPULSE := 115.0
const MAX_RUN_SPEED := 520.0
const RUN_DRAG := 2.4
const ROUND_TIMEOUT := 9.0
const ROUND_PAUSE := 1.7
const CELEBRATE_PAUSE := 2.2
const SIGNAL_FLASH_TIME := 0.55
const GHOST_BASE_SPEED := 215.0
const GHOST_STEP_SPEED := 50.0
const FLAG_DX := [-34.0, 20.0, -8.0]

enum Phase { PREP, RACE, ROUND_END }


class Runner:
	var player: Player = null
	var ghost := false
	var index := 0
	var color := Color(1, 1, 1, 1)
	var lane_y := 0.0
	var x := 0.0
	var vx := 0.0
	var rise := 0.0
	var penalty := 0.0
	var false_start := false
	var has_flag := false
	var flag = null
	var squash := 1.0
	var step := 0.0
	var eliminated := false


class Flag:
	var base := Vector2.ZERO
	var taken := false
	var phase := 0.0


var _solo := false
var _runners: Array = []
var _round_runners: Array = []
var _eliminated_this_round: Array = []
var _flags: Array = []
var _sand_dots: Array = []
var _confetti: Array = []   # [pos, vel, color, vida]
var _dust: Array = []       # [pos, vel, vida]
var _round_num := 1
var _phase: int = Phase.PREP
var _phase_t := 0.0
var _prep_time := PREP_MIN
var _signal_flash := 0.0
var _celebrating := false
var _solo_lost := false
var _final_winner: Player = null
var _bonus_given := false
var _time := 0.0


func _configure() -> void:
	title = {"es": "Banderas en la playa", "en": "Beach flags"}
	instructions = {"es": "Machaca A para correr y coge una bandera antes que nadie.",
		"en": "Mash A to run and grab a flag before anyone else."}
	controls = [
		[Pad.A, {"es": "Correr machacando", "en": "Mash to run"}],
	]
	duration = 75.0


func _setup() -> void:
	_solo = players.size() == 1
	for i in players.size():
		var r := Runner.new()
		r.player = players[i]
		r.index = players[i].index
		r.color = players[i].color
		_runners.append(r)
	if _solo:
		var g := Runner.new()
		g.ghost = true
		g.index = -1
		g.color = Color("b9c3cc")
		_runners.append(g)
	# Motas de arena, generadas una sola vez.
	var inner := _inner()
	for i in 70:
		_sand_dots.append(Vector2(rand_range(inner.position.x + 24.0, inner.end.x - 24.0),
				rand_range(SAND_TOP + 30.0, inner.end.y - 14.0)))
	_begin_round()


func _game_process(delta: float) -> void:
	_time += delta
	_phase_t += delta
	_signal_flash = max(0.0, _signal_flash - delta / SIGNAL_FLASH_TIME)
	match _phase:
		Phase.PREP:
			_process_prep()
		Phase.RACE:
			_process_race(delta)
		Phase.ROUND_END:
			_process_round_end()
	_update_effects(delta)


func _game_end() -> void:
	# El ganador final suma uno extra para quedar claramente primero.
	if _final_winner != null and not _bonus_given:
		_bonus_given = true
		add_score(_final_winner, 1)


# =====================================================================
# Rondas
# =====================================================================

func _begin_round() -> void:
	_phase = Phase.PREP
	_phase_t = 0.0
	_prep_time = rand_range(PREP_MIN, PREP_MAX)
	_signal_flash = 0.0
	_celebrating = false
	_solo_lost = false
	_eliminated_this_round.clear()
	_round_runners.clear()
	for r in _runners:
		if not r.eliminated:
			_round_runners.append(r)
	var n := _round_runners.size()
	for i in n:
		var r: Runner = _round_runners[i]
		r.lane_y = lerp(RUN_TOP, RUN_BOTTOM, (float(i) + 0.5) / float(n))
		r.x = START_X
		r.vx = 0.0
		r.rise = 0.0
		r.penalty = 0.0
		r.false_start = false
		r.has_flag = false
		r.flag = null
		r.squash = 1.0
		r.step = 0.0
	_spawn_flags()


func _spawn_flags() -> void:
	_flags.clear()
	var count := 1 if _solo else _round_runners.size() - 1
	count = max(count, 1)
	var top := SAND_TOP + 52.0
	var bot := ARENA.end.y - 34.0
	for i in count:
		var f := Flag.new()
		var t := (float(i) + 0.5) / float(count)
		var dx: float = FLAG_DX[i % 3] if count > 1 else 0.0
		f.base = Vector2(FLAG_X + dx, lerp(top, bot, t))
		f.phase = randf() * TAU
		_flags.append(f)


func _process_prep() -> void:
	for r in _round_runners:
		if r.ghost or r.false_start:
			continue
		if r.player.just_pressed(Pad.A):
			r.false_start = true
			r.squash = 0.7
			Sfx.play("back", rand_range(0.8, 0.95))
	if _phase_t >= _prep_time:
		_signal()


func _signal() -> void:
	_phase = Phase.RACE
	_phase_t = 0.0
	_signal_flash = 1.0
	Sfx.play("accept")
	for r in _round_runners:
		r.penalty = PENALTY if r.false_start else 0.0


func _process_race(delta: float) -> void:
	for r in _round_runners:
		if r.has_flag:
			continue
		if r.ghost:
			r.rise = min(1.0, r.rise + delta / RISE_TIME)
			if r.rise < 1.0:
				continue
			r.x += _ghost_speed() * delta
			r.step += delta * 10.0
			if r.x >= GRAB_X:
				r.x = GRAB_X
				_try_grab(r)
			continue
		if r.penalty > 0.0:
			r.penalty = max(0.0, r.penalty - delta)
			continue
		r.rise = min(1.0, r.rise + delta / RISE_TIME)
		if r.rise < 1.0:
			continue
		# Cada pulsación es un impulso; sin pulsar, la velocidad se apaga.
		if r.player.just_pressed(Pad.A):
			r.vx = min(MAX_RUN_SPEED, r.vx + IMPULSE)
			r.squash = 1.18
		r.vx *= exp(-RUN_DRAG * delta)
		r.x += r.vx * delta
		if r.vx > 140.0:
			r.step += delta * (5.0 + r.vx * 0.02)
			if randf() < delta * 14.0:
				_puff(r)
		if r.x >= GRAB_X:
			r.x = GRAB_X
			_try_grab(r)
	if _free_count() == 0:
		_end_round()
	elif _phase_t >= ROUND_TIMEOUT:
		_end_round()


func _try_grab(r: Runner) -> void:
	if r.has_flag:
		return
	var f := _free_flag()
	if f == null:
		return
	f.taken = true
	r.has_flag = true
	r.flag = f
	r.vx = 0.0
	r.squash = 1.3
	Sfx.play("pop", rand_range(0.95, 1.15))
	_burst(f.base, r.color if not r.ghost else Color("c3ccd4"), 12)


func _free_flag() -> Flag:
	for f in _flags:
		if not f.taken:
			return f
	return null


func _free_count() -> int:
	var n := 0
	for f in _flags:
		if not f.taken:
			n += 1
	return n


func _ghost_speed() -> float:
	return GHOST_BASE_SPEED + GHOST_STEP_SPEED * float(_round_num - 1)


func _player_runner() -> Runner:
	for r in _runners:
		if not r.ghost:
			return r
	return null


func _end_round() -> void:
	if _phase == Phase.ROUND_END:
		return
	# Si no llegó nadie, reparte las banderas libres por orden de llegada.
	while _free_count() > 0:
		var best: Runner = null
		for r in _round_runners:
			if r.has_flag:
				continue
			if best == null or r.x > best.x:
				best = r
		if best == null:
			break
		_try_grab(best)

	_eliminated_this_round.clear()
	for r in _round_runners:
		if r.has_flag:
			if not r.ghost:
				add_score(r.player)
		elif not r.ghost:
			r.eliminated = true
			_eliminated_this_round.append(r)
			Sfx.play("leave", rand_range(0.9, 1.1))

	_phase = Phase.ROUND_END
	_phase_t = 0.0
	if _solo:
		var pr := _player_runner()
		if pr == null or not pr.has_flag:
			_solo_lost = true
			Sfx.play("back", 0.85)
		else:
			Sfx.play("star", 1.05)
	else:
		var left := 0
		for r in _runners:
			if not r.ghost and not r.eliminated:
				left += 1
		if left <= 1:
			_celebrating = true
			for r in _runners:
				if not r.ghost and not r.eliminated:
					_final_winner = r.player
					_burst(Vector2(FLAG_X, 500.0), r.color, 26)
					break
			Sfx.play("star", 1.05)


func _process_round_end() -> void:
	if _phase_t < ROUND_PAUSE:
		return
	if _solo:
		if _solo_lost:
			finish()
		else:
			_round_num += 1
			_begin_round()
	else:
		if _celebrating:
			if _phase_t >= CELEBRATE_PAUSE:
				finish()
		else:
			_round_num += 1
			_begin_round()


# =====================================================================
# Efectos
# =====================================================================

func _puff(r: Runner) -> void:
	if _dust.size() >= 70:
		return
	_dust.append([Vector2(r.x - 12.0, r.lane_y - 2.0),
			Vector2(rand_range(-50.0, -12.0), rand_range(-34.0, -8.0)), 0.35])


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * rand_range(90.0, 320.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color(1, 1, 1, 1), rand_range(0.45, 0.85)])


func _update_effects(delta: float) -> void:
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 500) * delta
		c[3] -= delta
	var live_confetti: Array = []
	for c in _confetti:
		if c[3] > 0.0:
			live_confetti.append(c)
	_confetti = live_confetti
	for d in _dust:
		d[0] += d[1] * delta
		d[1] = d[1] * exp(-2.5 * delta) + Vector2(0, 60) * delta
		d[2] -= delta
	var live_dust: Array = []
	for d in _dust:
		if d[2] > 0.0:
			live_dust.append(d)
	_dust = live_dust
	for r in _round_runners:
		r.squash = lerp(r.squash, 1.0, min(1.0, delta * 10.0))


# =====================================================================
# Dibujo
# =====================================================================

func _inner() -> Rect2:
	return ARENA.grow(-8.0)


func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	_draw_beach()
	_draw_start_line()
	if _phase == Phase.RACE and _signal_flash > 0.0:
		draw_rect(_inner(), Color(1.0, 0.92, 0.5, 0.30 * _signal_flash))
	_draw_flags()
	for r in _round_runners:
		_draw_runner(r)
	_draw_dust()
	_draw_confetti()
	_draw_phase_text()


func _draw_beach() -> void:
	var inner := _inner()
	# Cielo.
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, HORIZON - inner.position.y)), Color("e8f6fd"))
	# Sol con halo.
	var sun := Vector2(inner.end.x - 120.0, inner.position.y + 62.0)
	draw_circle(sun, 46.0, Color(1.0, 0.88, 0.5, 0.18))
	draw_circle(sun, 30.0, Color("ffe08a"))
	# Nubes y gaviotas.
	_draw_cloud(Vector2(inner.position.x + 230.0 + sin(_time * 0.2) * 12.0, inner.position.y + 54.0), 1.0)
	_draw_cloud(Vector2(inner.position.x + 700.0 + sin(_time * 0.15 + 1.0) * 16.0, inner.position.y + 36.0), 0.8)
	_draw_gull(Vector2(inner.position.x + 540.0, inner.position.y + 88.0), 1.0)
	_draw_gull(Vector2(inner.position.x + 596.0, inner.position.y + 70.0), 0.7)
	# Mar con olas suaves.
	draw_rect(Rect2(inner.position.x, HORIZON, inner.size.x, SAND_TOP - HORIZON), Color("b9e2f0"))
	draw_rect(Rect2(inner.position.x, HORIZON, inner.size.x, 46.0), Color("c8ebf6"))
	_draw_waves(inner.position.x, inner.end.x, HORIZON + 2.0, 5.0, 1.5, Color(1, 1, 1, 0.75), 4.0)
	_draw_waves(inner.position.x, inner.end.x, HORIZON + 52.0, 4.0, 1.1, Color(1, 1, 1, 0.45), 3.0)
	_draw_waves(inner.position.x, inner.end.x, HORIZON + 112.0, 3.0, 0.9, Color(1, 1, 1, 0.35), 2.5)
	# Arena y espuma de la orilla.
	draw_rect(Rect2(inner.position.x, SAND_TOP, inner.size.x, inner.end.y - SAND_TOP), Color("f7e6c4"))
	draw_rect(Rect2(inner.position.x, SAND_TOP, inner.size.x, 20.0), Color("ecd2a3"))
	_draw_waves(inner.position.x, inner.end.x, SAND_TOP + 3.0, 3.5, 1.2, Color(1, 1, 1, 0.85), 4.0)
	for d in _sand_dots:
		draw_circle(d, 2.0, Color("e9d5aa"))


func _draw_waves(x0: float, x1: float, y: float, amp: float, speed: float, color: Color, width: float) -> void:
	var pts := PoolVector2Array()
	var n := 25
	for k in n:
		var x: float = lerp(x0, x1, float(k) / float(n - 1))
		pts.append(Vector2(x, y + sin(_time * speed + k * 0.55) * amp))
	draw_polyline(pts, color, width, true)


func _draw_cloud(c: Vector2, s: float) -> void:
	var col := Color(1, 1, 1, 0.85)
	draw_circle(c, 22.0 * s, col)
	draw_circle(c + Vector2(20.0, 4.0) * s, 16.0 * s, col)
	draw_circle(c + Vector2(-20.0, 6.0) * s, 14.0 * s, col)


func _draw_gull(c: Vector2, s: float) -> void:
	var col := Color("8fa5b2")
	draw_polyline(PoolVector2Array([c + Vector2(-10, 2) * s, c + Vector2(0, -3) * s,
			c + Vector2(10, 2) * s]), col, 2.5, true)


func _draw_start_line() -> void:
	var y := SAND_TOP + 34.0
	while y < 684.0:
		draw_line(Vector2(START_X, y), Vector2(START_X, min(y + 13.0, 684.0)),
				Color(1, 1, 1, 0.8), 4.0)
		y += 21.0
	draw_text_centered(loc({"es": "Salida", "en": "Start"}), Vector2(START_X, SAND_TOP + 18.0),
			20, Color("b39a6d"))


func _draw_flags() -> void:
	for f in _flags:
		if f.taken:
			continue
		_draw_flag(f.base, WiiTheme.ACCENT, _time * 4.0 + f.phase, 1.0)


func _draw_flag(base: Vector2, col: Color, phase: float, alpha: float) -> void:
	if alpha <= 0.0:
		return
	draw_set_transform(base + Vector2(0, 4), 0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 12.0, Color(WiiTheme.SHADOW, 0.8 * alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var top := base + Vector2(0, -POLE_H)
	draw_line(base, top, Color(0.55, 0.6, 0.65, alpha), 4.0, true)
	draw_circle(top, 4.5, Color(1.0, 0.83, 0.3, alpha))
	var w := sin(phase) * 4.0
	var pts := PoolVector2Array([
		top + Vector2(2, 2),
		top + Vector2(24.0 + w * 0.4, 8.0 + w),
		top + Vector2(21.0 + w * 0.3, 20.0 + w * 0.7),
		top + Vector2(2, 16),
	])
	draw_colored_polygon(pts, Color(col, alpha))
	draw_line(pts[0], pts[3], Color(1, 1, 1, 0.45 * alpha), 2.0, true)


func _draw_runner(r: Runner) -> void:
	var col := r.color
	if r.ghost:
		col = Color("c3ccd4")
	elif r.eliminated:
		col = col.linear_interpolate(Color("c8ced4"), 0.8)
	elif r.player != null and not r.player.is_connected_now():
		col = col.linear_interpolate(Color("c8ced4"), 0.55)
	var bob := 0.0
	if r.rise > 0.85 and r.vx > 20.0:
		bob = abs(sin(r.step)) * 4.0
	var ease_rise := r.rise * r.rise * (3.0 - 2.0 * r.rise)
	var lying := Vector2(r.x, r.lane_y - 8.0)
	var standing := Vector2(r.x, r.lane_y - RUNNER_RADIUS - bob)
	var c := lying.linear_interpolate(standing, ease_rise)
	var sx: float = lerp(1.35, 1.0, ease_rise) / r.squash
	var sy: float = lerp(0.5, 1.0, ease_rise) * r.squash
	# Sombra.
	draw_set_transform(Vector2(r.x, r.lane_y + 2.0), 0, Vector2(1.35, 0.32))
	draw_circle(Vector2.ZERO, RUNNER_RADIUS, WiiTheme.SHADOW)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Cuerpo: bola aplastada tumbado, redonda de pie.
	draw_set_transform(c, 0, Vector2(sx, sy))
	draw_circle(Vector2.ZERO, RUNNER_RADIUS, col)
	draw_circle(Vector2(0, RUNNER_RADIUS * 0.24), RUNNER_RADIUS * 0.76, col.darkened(0.08))
	draw_circle(Vector2(-RUNNER_RADIUS * 0.3, -RUNNER_RADIUS * 0.34),
			RUNNER_RADIUS * 0.34, Color(1, 1, 1, 0.42))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if r.ghost:
		draw_circle(c + Vector2(-7, -4), 3.4, Color("6b7680"))
		draw_circle(c + Vector2(7, -4), 3.4, Color("6b7680"))
	else:
		draw_text_centered(str(r.index + 1), c, 22, Color(1, 1, 1, 1) if not r.eliminated else Color("eef1f3"))
	# Bandera en la mano.
	if r.has_flag and r.flag != null:
		var hand := c + Vector2(RUNNER_RADIUS * 0.65, -RUNNER_RADIUS * 0.95)
		draw_line(c + Vector2(RUNNER_RADIUS * 0.3, -RUNNER_RADIUS * 0.2), hand,
				col.darkened(0.2), 5.0, true)
		_draw_flag(hand, col if not r.eliminated else Color("aab4bc"), _time * 4.0 + float(r.index), 1.0)
	# Avisos.
	if r.false_start and (r.penalty > 0.0 or _phase == Phase.PREP):
		draw_text_centered(loc({"es": "¡Salida nula!", "en": "False start!"}),
				c + Vector2(0, -RUNNER_RADIUS - 18.0), 20, Color("e25555"))
	elif r.eliminated and _phase == Phase.ROUND_END:
		draw_text_centered(loc({"es": "Sin bandera", "en": "No flag"}),
				c + Vector2(0, -RUNNER_RADIUS - 18.0), 20, Color("e25555"))


func _draw_dust() -> void:
	for d in _dust:
		var t: float = d[2]
		draw_circle(d[0], 3.0 + 3.0 * (1.0 - t / 0.35), Color(1.0, 0.95, 0.85, 0.55 * t / 0.35))


func _draw_confetti() -> void:
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)), Color(c[2], clamp(c[3] * 2.0, 0.0, 1.0)))


func _draw_phase_text() -> void:
	if not is_playing():
		return
	var inner := _inner()
	draw_text_centered(loc({"es": "Ronda %d", "en": "Round %d"}) % _round_num,
			Vector2(inner.position.x + 90.0, inner.position.y + 26.0), 22, WiiTheme.TEXT_SOFT)

	match _phase:
		Phase.PREP:
			var center := Vector2(640, inner.position.y + 106.0)
			draw_style_box(WiiTheme.panel_style(24, WiiTheme.ACCENT),
					Rect2(center.x - 200.0, center.y - 38.0, 400.0, 76.0))
			draw_text_centered(loc({"es": "Preparados...", "en": "Ready..."}), center, 40, WiiTheme.TEXT)
		Phase.RACE:
			if _signal_flash > 0.0:
				var s := 1.0 + _signal_flash * 0.5
				draw_set_transform(Vector2(640, inner.position.y + 112.0), 0, Vector2(s, s))
				draw_text_centered(loc({"es": "¡YA!", "en": "GO!"}), Vector2.ZERO, 110,
						Color(0.86, 0.62, 0.05, clamp(_signal_flash * 1.6, 0.0, 1.0)))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		Phase.ROUND_END:
			var center := Vector2(640, inner.position.y + 108.0)
			if _solo:
				if _solo_lost:
					draw_text_centered(loc({"es": "El fantasma llega antes", "en": "The ghost got there first"}),
							center, 38, Color("e25555"))
				else:
					draw_text_centered(loc({"es": "¡Bandera! +1", "en": "Flag! +1"}),
							center, 46, WiiTheme.ACCENT_DARK)
					draw_text_centered(loc({"es": "El fantasma acelera", "en": "The ghost speeds up"}),
							center + Vector2(0, 44), 22, WiiTheme.TEXT_SOFT)
			elif _celebrating and _final_winner != null:
				draw_text_centered(loc({"es": "¡Jugador %d gana!", "en": "Player %d wins!"}) % (_final_winner.index + 1),
						center, 52, _final_winner.color.darkened(0.15))
				draw_text_centered(loc({"es": "Última bandera", "en": "Last flag"}),
						center + Vector2(0, 44), 22, WiiTheme.TEXT_SOFT)
			elif not _eliminated_this_round.empty():
				var e: Runner = _eliminated_this_round[0]
				draw_text_centered(loc({"es": "Jugador %d sin bandera", "en": "Player %d missed out"}) % (e.index + 1),
						center, 38, Color("e25555"))

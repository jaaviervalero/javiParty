extends MinigameBase
## "Esquiva": vista desde arriba. Stick o cruceta para moverse (rápido y preciso)
## y A para un escudo breve: todo proyectil que toca el escudo pasa a ser tuyo y
## sale hacia donde apuntas; si le da a otro jugador, tú ganas una vida.
## De los bordes salen bolas rojas cada vez más rápidas y cada 10 s cruza un
## barrido con un hueco. Puntos = segundos sobrevividos; los vivos al final, 5 extra.

const BALL_RADIUS := 20.0
const MOVE_SPEED := 540.0
const RESPONSE := 22.0
const LIVES := 3
const MAX_LIVES := 5
const INVULN_TIME := 1.5
const SHIELD_TIME := 0.4
const SHIELD_COOLDOWN := 4.0
const SHOT_RADIUS := 11.0
const SHOT_SPEED_START := 150.0
const SHOT_SPEED_GAIN := 4.5
const SHOT_INTERVAL_START := 1.5
const SHOT_INTERVAL_END := 0.34
const SHOT_INTERVAL_GAIN := 0.02
const AIM_CHANCE := 0.3
const AIM_MIN_TIME := 8.0
const TRAIL_MAX := 7
const BOUNCE_SPEEDUP := 1.15    # el proyectil devuelto sale algo más rápido
const BOUNCE_MIN_SPEED := 260.0
const BOUNCE_MAX_SPEED := 900.0
const POPUP_TIME := 0.9
const FLASH_TIME := 0.45
const SWEEP_PERIOD := 10.0
const SWEEP_SPEED := 210.0
const SWEEP_HALF := 14.0
const SWEEP_GAP := 200.0
const SURVIVOR_BONUS := 5
const SHOT_COLOR := Color("e25555")


class Sweep:
	var vertical := true
	var pos := 0.0
	var gap_center := 0.0
	var dir := 1


class Dodger:
	var player: Player
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var lives := 3
	var invuln := 0.0
	var shield := 0.0
	var shield_cd := 0.0
	var eliminated := false
	var squash := 1.0


class Shot:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var radius := 11.0
	var trail: Array[Vector2] = []
	## null = bola de la arena; si no, el proyectil es de ese jugador.
	var owner: Dodger = null
	var alive := true


var _dodgers: Array[Dodger] = []
var _shots: Array[Shot] = []
var _sweeps: Array[Sweep] = []
var _popups: Array = []   # [pos, t, color]: "+1" al ganar una vida
var _flashes: Array = []  # [pos, t, color]: destello de la vida ganada
var _shot_timer := 1.0
var _next_sweep := SWEEP_PERIOD
var _sweep_vertical := true
var _time := 0.0
var _panel_style: StyleBoxFlat
var _sweep_style: StyleBoxFlat


func _configure() -> void:
	title = {"es": "Esquiva", "en": "Dodge!"}
	instructions = {
		"es": "Esquiva todo; con el escudo (A) devuelves proyectiles y si das a otro ganas una vida.",
		"en": "Dodge everything; your shield (A) deflects projectiles, and hitting another player earns you a life."}
	controls = [
		["stick", {"es": "Moverse", "en": "Move"}],
		["dpad", {"es": "Moverse", "en": "Move"}],
		[Pad.A, {"es": "Escudo: devuelve y ataca", "en": "Shield: deflect and attack"}],
	]
	duration = 60.0


func _setup() -> void:
	_panel_style = WiiTheme.panel_style(30)
	_sweep_style = StyleBoxFlat.new()
	_sweep_style.bg_color = Color("e25555")
	_sweep_style.border_color = Color("c74646")
	_sweep_style.set_border_width_all(3)
	_sweep_style.set_corner_radius_all(14)
	_sweep_style.shadow_color = WiiTheme.SHADOW
	_sweep_style.shadow_size = 6
	_sweep_style.shadow_offset = Vector2(0, 3)
	_sweep_style.anti_aliasing = true

	var n := players.size()
	var center := ARENA.get_center()
	for i in n:
		var d := Dodger.new()
		d.player = players[i]
		if n == 1:
			d.pos = center
		else:
			var ang := -PI * 0.5 + TAU * i / n
			d.pos = center + Vector2(cos(ang) * 270.0, sin(ang) * 150.0)
		d.pos.x = clampf(d.pos.x, ARENA.position.x + BALL_RADIUS + 8,
				ARENA.end.x - BALL_RADIUS - 8)
		d.pos.y = clampf(d.pos.y, ARENA.position.y + BALL_RADIUS + 8,
				ARENA.end.y - BALL_RADIUS - 8)
		_dodgers.append(d)


func _game_start() -> void:
	_shot_timer = 1.0
	_next_sweep = SWEEP_PERIOD
	_sweep_vertical = true


func _game_process(delta: float) -> void:
	_time += delta
	_update_effects(delta)

	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_spawn_shot()
		_shot_timer = maxf(SHOT_INTERVAL_END,
				SHOT_INTERVAL_START - elapsed * SHOT_INTERVAL_GAIN)

	if elapsed >= _next_sweep:
		_spawn_sweep()
		_next_sweep += SWEEP_PERIOD

	_update_shots(delta)
	_update_sweeps(delta)

	for d in _dodgers:
		_update_dodger(d, delta)
	for d in _dodgers:
		_collide_dodger(d)

	var keep_shots: Array[Shot] = []
	for s in _shots:
		if s.alive:
			keep_shots.append(s)
	_shots = keep_shots

	var any_alive := false
	for d in _dodgers:
		if d.eliminated:
			continue
		any_alive = true
		set_score(d.player, int(elapsed))
	if not any_alive:
		finish()


func _game_end() -> void:
	for d in _dodgers:
		if not d.eliminated:
			set_score(d.player, int(elapsed) + SURVIVOR_BONUS)


func _update_dodger(d: Dodger, delta: float) -> void:
	d.squash = lerpf(d.squash, 1.0, minf(1.0, delta * 10.0))
	if d.eliminated:
		return
	d.invuln = maxf(0.0, d.invuln - delta)
	d.shield = maxf(0.0, d.shield - delta)
	d.shield_cd = maxf(0.0, d.shield_cd - delta)

	var p := d.player
	if p.just_pressed(Pad.A) and d.shield_cd <= 0.0:
		d.shield = SHIELD_TIME
		d.shield_cd = SHIELD_COOLDOWN
		d.squash = 1.25
		Sfx.play("dash", randf_range(1.0, 1.2))

	var dir := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	if dir.length() > 1.0:
		dir = dir.normalized()
	d.vel = d.vel.lerp(dir * MOVE_SPEED, 1.0 - exp(-RESPONSE * delta))
	if dir == Vector2.ZERO:
		d.vel *= exp(-RESPONSE * 1.2 * delta)
	d.pos += d.vel * delta
	d.pos.x = clampf(d.pos.x, ARENA.position.x + BALL_RADIUS + 6,
			ARENA.end.x - BALL_RADIUS - 6)
	d.pos.y = clampf(d.pos.y, ARENA.position.y + BALL_RADIUS + 6,
			ARENA.end.y - BALL_RADIUS - 6)


func _spawn_shot() -> void:
	var side := randi() % 4
	var pos := Vector2.ZERO
	match side:
		0:
			pos = Vector2(ARENA.position.x - 12, randf_range(ARENA.position.y, ARENA.end.y))
		1:
			pos = Vector2(ARENA.end.x + 12, randf_range(ARENA.position.y, ARENA.end.y))
		2:
			pos = Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.position.y - 12)
		_:
			pos = Vector2(randf_range(ARENA.position.x, ARENA.end.x), ARENA.end.y + 12)

	var target := Vector2(randf_range(ARENA.position.x + 60, ARENA.end.x - 60),
			randf_range(ARENA.position.y + 60, ARENA.end.y - 60))
	if elapsed > AIM_MIN_TIME and randf() < minf(0.45, AIM_CHANCE + (elapsed - AIM_MIN_TIME) * 0.004):
		var nearest: Dodger = null
		var best := INF
		for d in _dodgers:
			if d.eliminated:
				continue
			var dist := d.pos.distance_squared_to(pos)
			if dist < best:
				best = dist
				nearest = d
		if nearest != null:
			target = nearest.pos

	var shot := Shot.new()
	shot.pos = pos
	shot.radius = SHOT_RADIUS
	var speed := SHOT_SPEED_START + minf(elapsed, 60.0) * SHOT_SPEED_GAIN
	shot.vel = (target - pos).normalized() * speed
	_shots.append(shot)
	Sfx.play("pop", randf_range(0.7, 0.88))


func _update_shots(delta: float) -> void:
	for s in _shots:
		if not s.alive:
			continue
		s.trail.append(s.pos)
		if s.trail.size() > TRAIL_MAX:
			s.trail.pop_front()
		s.pos += s.vel * delta
		if not ARENA.grow(60.0).has_point(s.pos):
			s.alive = false


func _spawn_sweep() -> void:
	var sweep := Sweep.new()
	sweep.vertical = _sweep_vertical
	_sweep_vertical = not _sweep_vertical
	if sweep.vertical:
		var from_left := randf() < 0.5
		sweep.dir = 1 if from_left else -1
		sweep.pos = ARENA.position.x - 20.0 if from_left else ARENA.end.x + 20.0
		sweep.gap_center = randf_range(ARENA.position.y + SWEEP_GAP * 0.5 + 30.0,
				ARENA.end.y - SWEEP_GAP * 0.5 - 30.0)
	else:
		var from_top := randf() < 0.5
		sweep.dir = 1 if from_top else -1
		sweep.pos = ARENA.position.y - 20.0 if from_top else ARENA.end.y + 20.0
		sweep.gap_center = randf_range(ARENA.position.x + SWEEP_GAP * 0.5 + 30.0,
				ARENA.end.x - SWEEP_GAP * 0.5 - 30.0)
	_sweeps.append(sweep)
	Sfx.play("wave")


func _update_sweeps(delta: float) -> void:
	var keep: Array[Sweep] = []
	for sweep in _sweeps:
		sweep.pos += sweep.dir * SWEEP_SPEED * delta
		var gone := false
		if sweep.vertical:
			gone = sweep.pos < ARENA.position.x - 60.0 or sweep.pos > ARENA.end.x + 60.0
		else:
			gone = sweep.pos < ARENA.position.y - 60.0 or sweep.pos > ARENA.end.y + 60.0
		if not gone:
			keep.append(sweep)
	_sweeps = keep


func _collide_dodger(d: Dodger) -> void:
	if d.eliminated:
		return
	for s in _shots:
		if not s.alive or s.owner == d:
			continue  # un proyectil propio no te hace nada
		if d.pos.distance_to(s.pos) >= BALL_RADIUS + s.radius:
			continue
		if d.shield > 0.0:
			_capture_shot(d, s)
		elif d.invuln > 0.0:
			s.alive = false
		else:
			s.alive = false
			if s.owner != null:
				_award_life(s.owner)
			_hit_dodger(d)
			break
	for sweep in _sweeps:
		if _sweep_hits(d, sweep):
			_hit_dodger(d)
			break


func _capture_shot(d: Dodger, s: Shot) -> void:
	# El escudo se queda con el proyectil: pasa a ser suyo y sale hacia donde apunta.
	var p := d.player
	var dir := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	if dir == Vector2.ZERO:
		dir = -s.vel.normalized() if s.vel.length() > 0.01 else (s.pos - d.pos).normalized()
	dir = dir.normalized()
	s.owner = d
	s.pos = d.pos + dir * (BALL_RADIUS + s.radius + 2.0)
	var speed := clampf(s.vel.length() * BOUNCE_SPEEDUP, BOUNCE_MIN_SPEED, BOUNCE_MAX_SPEED)
	s.vel = dir * speed
	s.trail.clear()
	Sfx.play("pop", randf_range(1.1, 1.3))


func _award_life(owner: Dodger) -> void:
	# Los eliminados no reviven y con el máximo de vidas ya no se gana más.
	if owner.eliminated or owner.lives >= MAX_LIVES:
		return
	owner.lives += 1
	owner.squash = 1.3
	_popups.append([owner.pos, 0.0, owner.player.color])
	_flashes.append([owner.pos, 0.0, owner.player.color])
	Sfx.play("star")


func _update_effects(delta: float) -> void:
	for popup in _popups:
		popup[1] += delta
	_popups = _popups.filter(func(popup): return popup[1] < POPUP_TIME)
	for flash in _flashes:
		flash[1] += delta
	_flashes = _flashes.filter(func(flash): return flash[1] < FLASH_TIME)


func _sweep_hits(d: Dodger, sweep: Sweep) -> bool:
	var half_gap := SWEEP_GAP * 0.5
	if sweep.vertical:
		if absf(d.pos.x - sweep.pos) > SWEEP_HALF + BALL_RADIUS:
			return false
		return d.pos.y < sweep.gap_center - half_gap + BALL_RADIUS \
				or d.pos.y > sweep.gap_center + half_gap - BALL_RADIUS
	if absf(d.pos.y - sweep.pos) > SWEEP_HALF + BALL_RADIUS:
		return false
	return d.pos.x < sweep.gap_center - half_gap + BALL_RADIUS \
			or d.pos.x > sweep.gap_center + half_gap - BALL_RADIUS


func _hit_dodger(d: Dodger) -> void:
	if d.eliminated or d.invuln > 0.0:
		return
	d.lives -= 1
	d.invuln = INVULN_TIME
	Sfx.play("back", randf_range(0.9, 1.08))
	if d.lives <= 0:
		d.eliminated = true
		d.shield = 0.0
		set_score(d.player, int(elapsed))
		Sfx.play("leave")


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(_panel_style, ARENA)
	_draw_grid()
	for sweep in _sweeps:
		_draw_sweep(sweep)
	for s in _shots:
		_draw_shot(s)
	for d in _dodgers:
		_draw_dodger(d)
	for flash in _flashes:
		_draw_flash(flash)
	for popup in _popups:
		_draw_popup(popup)


func _draw_grid() -> void:
	var step := 100.0
	var x := ARENA.position.x + step
	while x < ARENA.end.x:
		draw_line(Vector2(x, ARENA.position.y), Vector2(x, ARENA.end.y),
				Color(0.2, 0.3, 0.4, 0.05), 2.0)
		x += step
	var y := ARENA.position.y + step
	while y < ARENA.end.y:
		draw_line(Vector2(ARENA.position.x, y), Vector2(ARENA.end.x, y),
				Color(0.2, 0.3, 0.4, 0.05), 2.0)
		y += step


func _draw_shot(s: Shot) -> void:
	var col := SHOT_COLOR if s.owner == null else s.owner.player.color
	if s.trail.size() >= 2:
		var pts := PackedVector2Array()
		for point in s.trail:
			pts.append(point)
		draw_polyline(pts, Color(col, 0.22), s.radius * 1.3, true)
	var glow := s.radius + 3.0 + sin(_time * 8.0) * 1.5
	draw_circle(s.pos, glow, Color(col, 0.18))
	draw_circle(s.pos, s.radius, col)
	draw_circle(s.pos + Vector2(-s.radius * 0.3, -s.radius * 0.3), s.radius * 0.4,
			Color(1, 1, 1, 0.45))


func _draw_flash(flash: Array) -> void:
	var t: float = flash[1] / FLASH_TIME
	var col: Color = flash[2]
	draw_circle(flash[0], BALL_RADIUS + 8.0 + t * 40.0, Color(col, 0.3 * (1.0 - t)))
	draw_arc(flash[0], BALL_RADIUS + 8.0 + t * 60.0, 0.0, TAU, 32,
			Color(col, 0.9 * (1.0 - t)), 4.0 * (1.0 - t) + 1.0, true)


func _draw_popup(popup: Array) -> void:
	var t: float = popup[1] / POPUP_TIME
	var at: Vector2 = popup[0] + Vector2(0, -BALL_RADIUS - 26.0 - t * 46.0)
	draw_text_centered("+1", at, 30, Color(popup[2], 1.0 - t))


func _draw_sweep(sweep: Sweep) -> void:
	var half_gap := SWEEP_GAP * 0.5
	if sweep.vertical:
		var gap_top := sweep.gap_center - half_gap
		var gap_bottom := sweep.gap_center + half_gap
		if gap_top > ARENA.position.y:
			draw_style_box(_sweep_style, Rect2(sweep.pos - SWEEP_HALF, ARENA.position.y,
					SWEEP_HALF * 2.0, gap_top - ARENA.position.y))
		if gap_bottom < ARENA.end.y:
			draw_style_box(_sweep_style, Rect2(sweep.pos - SWEEP_HALF, gap_bottom,
					SWEEP_HALF * 2.0, ARENA.end.y - gap_bottom))
		_draw_gap_edges(Vector2(sweep.pos - SWEEP_HALF, gap_top),
				Vector2(sweep.pos + SWEEP_HALF, gap_bottom))
	else:
		var gap_left := sweep.gap_center - half_gap
		var gap_right := sweep.gap_center + half_gap
		if gap_left > ARENA.position.x:
			draw_style_box(_sweep_style, Rect2(ARENA.position.x, sweep.pos - SWEEP_HALF,
					gap_left - ARENA.position.x, SWEEP_HALF * 2.0))
		if gap_right < ARENA.end.x:
			draw_style_box(_sweep_style, Rect2(gap_right, sweep.pos - SWEEP_HALF,
					ARENA.end.x - gap_right, SWEEP_HALF * 2.0))
		_draw_gap_edges(Vector2(gap_left, sweep.pos - SWEEP_HALF),
				Vector2(gap_right, sweep.pos + SWEEP_HALF))


func _draw_gap_edges(a: Vector2, b: Vector2) -> void:
	var c := Color(WiiTheme.ACCENT, 0.85)
	draw_rect(Rect2(a, b - a), c, false, 3.0)


func _draw_dodger(d: Dodger) -> void:
	var col := d.player.color
	if d.eliminated:
		col = Color("b9c1c9")
	var alpha := 1.0
	if d.invuln > 0.0 and not d.eliminated:
		alpha = 0.35 if fmod(d.invuln, 0.2) < 0.1 else 1.0

	draw_set_transform(d.pos + Vector2(0, 5), 0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, BALL_RADIUS, Color(WiiTheme.SHADOW, WiiTheme.SHADOW.a * alpha))
	draw_set_transform(d.pos, 0, Vector2(1.0 / d.squash, d.squash))
	draw_circle(Vector2.ZERO, BALL_RADIUS, Color(col, alpha))
	draw_circle(Vector2(-BALL_RADIUS * 0.3, -BALL_RADIUS * 0.35), BALL_RADIUS * 0.4,
			Color(1, 1, 1, 0.4 * alpha))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(d.player.index + 1), d.pos, 22, Color(1, 1, 1, alpha))

	if d.shield > 0.0:
		draw_arc(d.pos, BALL_RADIUS + 9.0, 0.0, TAU, 32,
				Color(WiiTheme.ACCENT, 0.9), 4.0, true)
	elif d.shield_cd > 0.0 and not d.eliminated:
		var ready := 1.0 - d.shield_cd / SHIELD_COOLDOWN
		draw_arc(d.pos, BALL_RADIUS + 9.0, -PI * 0.5, -PI * 0.5 + TAU * ready, 24,
				Color(WiiTheme.ACCENT, 0.35), 3.0, true)

	var hearts_y := maxf(d.pos.y - BALL_RADIUS - 20.0, ARENA.position.y + 12.0)
	var pips := maxi(LIVES, d.lives)  # se dibujan tantas como vidas tenga, hasta 5
	var start_x := d.pos.x - (pips - 1) * 7.0
	for i in pips:
		var pip := d.player.color if i < d.lives else Color("d7dee4")
		draw_circle(Vector2(start_x + i * 14.0, hearts_y), 5.0, pip)

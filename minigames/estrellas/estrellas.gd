extends MinigameBase
## EJEMPLO DE REFERENCIA para todos los minijuegos (ver docs/MINIJUEGOS.md).
## "Estrellas": cada jugador es una bola; recoge más estrellas que nadie.
## Stick o cruceta para moverse, A para un impulso, B para una onda que empuja.
## Todo se dibuja en _draw (sin nodos por entidad) y toda la lógica va en _game_process.
## El decorado fijo (jardín al anochecer) va en _draw_scenery, que se pinta UNA vez.

const RADIUS := 34.0
const MAX_SPEED := 420.0      # px/s
const STEER := 9.0            # lo rápido que la velocidad sigue al control (1/s)
const DASH_SPEED := 750.0
const DASH_COOLDOWN := 0.6
const WAVE_COOLDOWN := 1.2
const WAVE_RADIUS := 260.0
const WAVE_PUSH := 900.0
const STAR_COUNT := 4
const STAR_RADIUS := 22.0
# Ambiente: jardín al anochecer.
const SKY_TOP := Color("a7b6f2")
const SKY_BOTTOM := Color("f3d9ec")
const HILL_FAR := Color("c7b5ea")
const HILL_NEAR := Color("b3dc9c")
const MOON := Color("fff6d8")


## Estado de cada jugador: una clase interna simple, sin nodos.
class Ball:
	var player: Player
	var pos: Vector2
	var vel := Vector2.ZERO
	var dash_cd := 0.0
	var wave_cd := 0.0
	var squash := 1.0


var _balls: Array[Ball] = []
var _stars: Array[Vector2] = []
var _star_anim: Array[float] = []
var _waves: Array = []      # [pos, t, color]
var _confetti: Array = []   # [pos, vel, color, vida]
var _time := 0.0


func _configure() -> void:
	title = {"es": "Estrellas", "en": "Stars"}
	instructions = {"es": "Recoge más estrellas que nadie y empuja a los demás.",
		"en": "Grab more stars than anyone and push the others around."}
	controls = [
		["stick", {"es": "Moverse", "en": "Move"}],
		[Pad.A, {"es": "Impulso", "en": "Dash"}],
		[Pad.B, {"es": "Onda expansiva", "en": "Shockwave"}],
	]
	duration = 40.0


func _setup() -> void:
	for p in players:
		var b := Ball.new()
		b.player = p
		b.pos = ARENA.get_center() + Vector2(-270 + 180 * p.index, 0)
		_balls.append(b)
	for i in STAR_COUNT:
		_stars.append(_random_star_pos())
		_star_anim.append(0.0)


func _game_process(delta: float) -> void:
	for b in _balls:
		_update_ball(b, delta)
	_collide_balls()
	_update_effects(delta)


func _random_star_pos() -> Vector2:
	var m := 60.0
	return Vector2(randf_range(ARENA.position.x + m, ARENA.end.x - m),
			randf_range(ARENA.position.y + m, ARENA.end.y - m))


func _update_ball(b: Ball, delta: float) -> void:
	var p := b.player
	b.dash_cd = maxf(0.0, b.dash_cd - delta)
	b.wave_cd = maxf(0.0, b.wave_cd - delta)
	b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 10.0))

	# Stick analógico si se usa; si no, la cruceta. La velocidad persigue al control:
	# responde al instante pero conserva algo de inercia.
	var dir := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	if dir != Vector2.ZERO:
		b.vel = b.vel.lerp(dir * MAX_SPEED, 1.0 - exp(-STEER * delta))
	else:
		b.vel *= exp(-STEER * 0.5 * delta)

	if p.just_pressed(Pad.A) and b.dash_cd <= 0.0:
		var d := dir if dir != Vector2.ZERO else (b.vel.normalized() if b.vel.length() > 30.0 else Vector2.RIGHT)
		b.vel += d.normalized() * DASH_SPEED
		b.dash_cd = DASH_COOLDOWN
		b.squash = 1.35
		Sfx.play("dash")

	if p.just_pressed(Pad.B) and b.wave_cd <= 0.0:
		b.wave_cd = WAVE_COOLDOWN
		_wave(b)

	b.pos += b.vel * delta
	var lo := ARENA.position + Vector2(RADIUS, RADIUS)
	var hi := ARENA.end - Vector2(RADIUS, RADIUS)
	if b.pos.x < lo.x or b.pos.x > hi.x:
		b.pos.x = clampf(b.pos.x, lo.x, hi.x)
		b.vel.x *= -0.7
		b.squash = 0.85
	if b.pos.y < lo.y or b.pos.y > hi.y:
		b.pos.y = clampf(b.pos.y, lo.y, hi.y)
		b.vel.y *= -0.7
		b.squash = 0.85

	for i in _stars.size():
		if _star_anim[i] <= 0.0 and b.pos.distance_to(_stars[i]) < RADIUS + STAR_RADIUS:
			add_score(p)
			_star_anim[i] = 1.0
			_burst(_stars[i], Color("ffd34d"), 14)
			Sfx.play("star", randf_range(0.95, 1.1))


func _wave(b: Ball) -> void:
	_waves.append([b.pos, 0.0, b.player.color])
	_burst(b.pos, b.player.color, 24)
	Sfx.play("wave")
	for o in _balls:
		if o == b:
			continue
		var d := o.pos - b.pos
		if d.length() < WAVE_RADIUS and d.length() > 0.01:
			o.vel += d.normalized() * WAVE_PUSH * (1.0 - d.length() / WAVE_RADIUS)
			o.squash = 0.8


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a := _balls[i]
			var b := _balls[j]
			var d := b.pos - a.pos
			var dist := d.length()
			if dist < RADIUS * 2.0 and dist > 0.01:
				var n := d / dist
				var overlap := RADIUS * 2.0 - dist
				a.pos -= n * overlap * 0.5
				b.pos += n * overlap * 0.5
				var rel := (b.vel - a.vel).dot(n)
				if rel < 0.0:
					a.vel += n * rel * 0.9
					b.vel -= n * rel * 0.9
					if absf(rel) > 200.0:
						Sfx.play("pop", randf_range(0.9, 1.2))


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(120.0, 420.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.5, 0.9)])


func _update_effects(delta: float) -> void:
	_time += delta
	for i in _stars.size():
		if _star_anim[i] > 0.0:
			_star_anim[i] -= delta * 2.5
			if _star_anim[i] <= 0.0:
				_stars[i] = _random_star_pos()
	for w in _waves:
		w[1] += delta * 2.2
	_waves = _waves.filter(func(w): return w[1] < 1.0)
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 500) * delta
		c[3] -= delta
	_confetti = _confetti.filter(func(c): return c[3] > 0.0)


# --- Dibujo ---

## Decorado estático: se dibuja una sola vez (ver MinigameBase._draw_scenery).
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	DrawKit.arena_frame(ci, ARENA, SKY_TOP, SKY_BOTTOM)
	# Estrellitas de fondo fijas (semilla fija: siempre el mismo cielo).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 46:
		var p := Vector2(rng.randf_range(ARENA.position.x + 30, ARENA.end.x - 30),
				rng.randf_range(ARENA.position.y + 24, ARENA.position.y + ARENA.size.y * 0.55))
		ci.draw_circle(p, rng.randf_range(1.5, 3.2), Color(1, 1, 1, rng.randf_range(0.5, 0.9)))
	var moon := Vector2(ARENA.end.x - 130, ARENA.position.y + 90)
	ci.draw_circle(moon, 62, Color(MOON, 0.25))
	ci.draw_circle(moon, 46, MOON)
	ci.draw_circle(moon + Vector2(-14, -8), 9, Color(0.85, 0.8, 0.7, 0.35))
	ci.draw_circle(moon + Vector2(12, 14), 6, Color(0.85, 0.8, 0.7, 0.35))
	DrawKit.cloud(ci, Vector2(ARENA.position.x + 210, ARENA.position.y + 120), 1.2, Color(1, 1, 1, 0.55))
	DrawKit.cloud(ci, Vector2(ARENA.get_center().x + 120, ARENA.position.y + 70), 0.8, Color(1, 1, 1, 0.45))
	DrawKit.hills(ci, ARENA, ARENA.end.y - 150, 40, HILL_FAR, 0.6, 1.8, clip)
	DrawKit.hills(ci, ARENA, ARENA.end.y - 80, 26, HILL_NEAR, 2.2, 1.4, clip)
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 40, ARENA.end.y - 30),
			Vector2(ARENA.end.x - 40, ARENA.end.y - 30), 22, DrawKit.GRASS_DARK, 3)
	for i in 7:
		DrawKit.flower(ci, Vector2(ARENA.position.x + 120 + i * 170, ARENA.end.y - 46 + (i % 2) * 18), 5,
				Color.WHITE if i % 2 == 0 else Color("ffd1e3"))
	DrawKit.arena_border(ci, ARENA)


## MinigameBase llama a queue_redraw() cada frame: aquí solo lo que se mueve.
func _draw() -> void:
	for i in _stars.size():
		var s := 1.0 + sin(_time * 4.0 + i) * 0.08
		if _star_anim[i] > 0.0:
			s = 1.0 + (1.0 - _star_anim[i]) * 0.8
		var a := 1.0 if _star_anim[i] <= 0.0 else _star_anim[i]
		_draw_star(_stars[i], STAR_RADIUS * s, _time * 0.8 + i, a)
	for w in _waves:
		var t: float = w[1]
		draw_arc(w[0], WAVE_RADIUS * t, 0, TAU, 48, Color(w[2], 0.6 * (1.0 - t)), 6.0 * (1.0 - t) + 1.0)
	for b in _balls:
		_draw_ball(b)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)), Color(c[2], clampf(c[3] * 2.0, 0.0, 1.0)))


func _draw_ball(b: Ball) -> void:
	var col := b.player.color
	if not b.player.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos + Vector2(0, 6), 0, Vector2(stretch.x * 1.1, 0.35))
	draw_circle(Vector2.ZERO, RADIUS, WiiTheme.SHADOW)
	draw_set_transform(b.pos, 0, stretch)
	draw_circle(Vector2.ZERO, RADIUS, col)
	draw_circle(Vector2(0, RADIUS * 0.25), RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-RADIUS * 0.3, -RADIUS * 0.35), RADIUS * 0.38, Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(b.player.index + 1), b.pos, 30, Color.WHITE)


func _draw_star(c: Vector2, r: float, rot: float, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.UP.rotated(rot + i * TAU / 10.0) * rr)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_colored_polygon(pts, Color(1.0, 0.83, 0.3, alpha))
	draw_polyline(outline, Color(1, 1, 1, alpha), 3.0, true)

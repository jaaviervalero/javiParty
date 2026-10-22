extends MinigameBase
## "Concurso de dominadas": cada jugador cuelga de su barra y hace dominadas
## pulsando A cuando la aguja de fuerza cruza la zona verde. Fallar resta agarre.
## B sacude los brazos: agranda la zona, pero bloquea 1,2 s.

const BAR_Y := 250.0
const GROUND_Y := 500.0
const BODY_RADIUS := 30.0
const HANG_Y := BAR_Y + 88.0
const UP_Y := BAR_Y - BODY_RADIUS - 4.0
const GRIP_SPREAD := 24.0
const POST_OFFSET := 68.0
const CROSS_HALF := 84.0

const FORCE_OFFSET := 102.0
const FORCE_W := 38.0
const FORCE_H := 210.0
const FORCE_TOP := BAR_Y + 20.0
const GRIP_W := 70.0
const GRIP_Y := FORCE_TOP + FORCE_H + 18.0
const GRIP_H := 16.0

const ZONE_CENTER := 0.5
const BASE_ZONE_HALF := 0.15
const MIN_ZONE_HALF := 0.06
const ZONE_SHRINK := 0.007
const REST_ZONE_GAIN := 0.024
const BASE_NEEDLE_SPEED := 0.85
const MAX_NEEDLE_SPEED := 1.65
const NEEDLE_ACCEL := 0.04
const REST_SPEED_RELIEF := 0.05
const REST_TIME := 1.2
const GRIP_MAX := 100.0
const MISS_GRIP := 20.0
const SHAKE_TIME := 0.35
const FALL_TIME := 0.8
const ALL_OUT_DELAY := 1.0

const PULL_UP_TIME := 0.20
const PULL_BOUNCE_TIME := 0.12
const PULL_DOWN_TIME := 0.24
const PULL_TOTAL := 0.56
const PULL_OVERSHOOT := 1.06
const PULL_BOUNCE_LOW := 0.95

const ZONE_COLOR := Color("4cbf6b")
const DANGER_COLOR := Color("e25555")
const METAL := Color("b6c2ca")
const METAL_DARK := Color("7f8c96")
# Ambiente: gimnasio al aire libre, luminoso y pastel.
const SKY := Color("e3f4fc")
const HILL_FAR := Color("bfe0b3")
const HILL_NEAR := Color("add5a1")
const GRASS_GROUND := Color("d5ecc6")
const GRASS_EDGE := Color("bfe0ae")
const GRASS_TUFT := Color("94c287")


## Estado de cada jugador: una clase interna simple, sin nodos.
class Lifter:
	var player: Player
	var x := 0.0
	var needle := 0.5
	var needle_dir := 1.0
	var zone_half := 0.15
	var speed := 0.85
	var pull_t := -1.0
	var lift := 0.0
	var pulls := 0
	var grip := 100.0
	var rest_t := 0.0
	var shake := 0.0
	var grip_flash := 0.0
	var out := false
	var fall_t := 0.0
	var fall_from := Vector2.ZERO
	var fall_dir := 1.0
	var landed := false


var _lifters: Array = []
var _sparks: Array = []   # [pos, vel, color, vida]
var _time := 0.0
var _out_clock := 0.0


func _configure() -> void:
	title = {"es": "Concurso de dominadas", "en": "Pull-up contest"}
	instructions = {"es": "Pulsa A cuando la aguja esté en la zona verde para hacer dominadas; B para descansar los brazos.",
		"en": "Press A when the needle is in the green zone to do a pull-up; B to rest your arms."}
	controls = [
		[Pad.A, {"es": "Dominada en la zona buena", "en": "Pull-up in the good zone"}],
		[Pad.B, {"es": "Descansar los brazos", "en": "Rest your arms"}],
	]
	duration = 35.0


func _setup() -> void:
	var n := players.size()
	for i in n:
		var l := Lifter.new()
		l.player = players[i]
		l.x = ARENA.position.x + ARENA.size.x * (float(i) + 0.5) / float(max(n, 1))
		if n == 1:
			# En solitario, centrar el conjunto personaje + barra de fuerza.
			l.x -= 52.0
		l.needle = rand_range(0.2, 0.8)
		l.needle_dir = 1.0 if randf() < 0.5 else -1.0
		l.zone_half = BASE_ZONE_HALF
		l.speed = BASE_NEEDLE_SPEED
		l.grip = GRIP_MAX
		_lifters.append(l)


func _game_start() -> void:
	_out_clock = 0.0


func _game_process(delta: float) -> void:
	_time += delta
	_update_effects(delta)
	var any_alive := false
	for l in _lifters:
		_update_lifter(l, delta)
		if not l.out:
			any_alive = true
	if any_alive:
		_out_clock = 0.0
	else:
		_out_clock += delta
		if _out_clock >= ALL_OUT_DELAY:
			_out_clock = 0.0
			finish()


func _update_lifter(l: Lifter, delta: float) -> void:
	l.shake = max(0.0, l.shake - delta)
	l.grip_flash = max(0.0, l.grip_flash - delta)

	if l.out:
		l.fall_t += delta
		if not l.landed and l.fall_t >= FALL_TIME:
			l.landed = true
			_burst(Vector2(l.x + l.fall_dir * 24.0, GROUND_Y - 10.0), l.player.color, 8)
			Sfx.play("pop", 0.7)
		return

	if l.rest_t > 0.0:
		l.rest_t = max(0.0, l.rest_t - delta)

	# La aguja sube y baja sola, cada vez más rápido.
	l.needle += l.needle_dir * l.speed * delta
	if l.needle >= 1.0:
		l.needle = 1.0
		l.needle_dir = -1.0
	elif l.needle <= 0.0:
		l.needle = 0.0
		l.needle_dir = 1.0

	if l.pull_t >= 0.0:
		l.pull_t += delta
		if l.pull_t >= PULL_TOTAL:
			l.pull_t = -1.0
			l.lift = 0.0
		else:
			l.lift = _pull_lift(l.pull_t)

	# Descansando, subiendo o sacudiéndose: no se puede pulsar todavía.
	if l.rest_t > 0.0 or l.pull_t >= 0.0 or l.shake > 0.0:
		return

	if l.player.just_pressed(Pad.A):
		if abs(l.needle - ZONE_CENTER) <= l.zone_half:
			_do_pull_up(l)
		else:
			_miss(l)
	elif l.player.just_pressed(Pad.B):
		_rest(l)


func _do_pull_up(l: Lifter) -> void:
	l.pull_t = 0.0
	l.pulls += 1
	add_score(l.player, 1)
	# Cansancio personal: zona más pequeña y aguja más rápida.
	l.zone_half = max(MIN_ZONE_HALF, l.zone_half - ZONE_SHRINK)
	l.speed = min(MAX_NEEDLE_SPEED, l.speed + NEEDLE_ACCEL)
	_burst(Vector2(l.x, BAR_Y), l.player.color, 10)
	Sfx.play("pop", min(1.0 + 0.05 * float(l.pulls), 1.9))


func _miss(l: Lifter) -> void:
	l.shake = SHAKE_TIME
	l.grip = max(0.0, l.grip - MISS_GRIP)
	l.grip_flash = 0.45
	Sfx.play("back", rand_range(0.7, 0.85))
	_burst(Vector2(l.x, BAR_Y + 24.0), DANGER_COLOR, 6)
	if l.grip <= 0.0:
		l.out = true
		l.fall_t = 0.0
		l.landed = false
		l.lift = 0.0
		l.pull_t = -1.0
		l.rest_t = 0.0
		l.fall_from = _body_pos(l)
		l.fall_dir = -1.0 if randf() < 0.5 else 1.0
		Sfx.play("leave", rand_range(0.9, 1.05))


func _rest(l: Lifter) -> void:
	l.rest_t = REST_TIME
	l.zone_half = min(BASE_ZONE_HALF, l.zone_half + REST_ZONE_GAIN)
	l.speed = max(BASE_NEEDLE_SPEED, l.speed - REST_SPEED_RELIEF)
	Sfx.play("wave", 1.25)


## Curva de la dominada: sube con inercia, rebota arriba y baja suave.
func _pull_lift(t: float) -> float:
	if t < PULL_UP_TIME:
		return _smooth(t / PULL_UP_TIME) * PULL_OVERSHOOT
	var t2 := t - PULL_UP_TIME
	if t2 < PULL_BOUNCE_TIME:
		return lerp(PULL_OVERSHOOT, PULL_BOUNCE_LOW, _smooth(t2 / PULL_BOUNCE_TIME))
	var t3 := t - PULL_UP_TIME - PULL_BOUNCE_TIME
	return lerp(PULL_BOUNCE_LOW, 0.0, _smooth(t3 / PULL_DOWN_TIME))


func _smooth(t: float) -> float:
	var k := clamp(t, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


func _body_pos(l: Lifter) -> Vector2:
	var y: float = lerp(HANG_Y, UP_Y, l.lift)
	var sway := sin(_time * 2.2 + float(l.player.index) * 1.7) * 2.5 * (1.0 - l.lift)
	var shake: float = sin(_time * 55.0) * 5.0 * clamp(l.shake / SHAKE_TIME, 0.0, 1.0)
	return Vector2(l.x + sway + shake, y)


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * rand_range(80.0, 260.0)
		_sparks.append([at, v, color if i % 2 == 0 else Color(1, 1, 1, 1), rand_range(0.35, 0.6)])


func _update_effects(delta: float) -> void:
	for s in _sparks:
		s[0] += s[1] * delta
		s[1] = s[1] * exp(-2.8 * delta) + Vector2(0, 460.0) * delta
		s[3] -= delta
	var live_sparks: Array = []
	for s in _sparks:
		if s[3] > 0.0:
			live_sparks.append(s)
	_sparks = live_sparks


# --- Dibujo ---

## Decorado estático: gimnasio al aire libre, pintado una sola vez.
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	DrawKit.arena_frame(ci, ARENA, SKY, SKY)
	DrawKit.sun(ci, Vector2(ARENA.end.x - 118.0, ARENA.position.y + 92.0), 32.0)
	# Colinas al fondo; el césped tapa su parte baja.
	DrawKit.hills(ci, ARENA, GROUND_Y + 20.0, 55.0, HILL_FAR, 1.1, 1.5, clip)
	DrawKit.hills(ci, ARENA, GROUND_Y + 42.0, 28.0, HILL_NEAR, 2.8, 1.7, clip)
	# Césped y borde, recortados a las esquinas redondeadas de la arena.
	DrawKit.clipped_polygon(ci, PoolVector2Array([
		Vector2(ARENA.position.x, GROUND_Y), Vector2(ARENA.end.x, GROUND_Y),
		ARENA.end, Vector2(ARENA.position.x, ARENA.end.y)]), clip, GRASS_GROUND)
	DrawKit.clipped_polygon(ci, PoolVector2Array([
		Vector2(ARENA.position.x, GROUND_Y), Vector2(ARENA.end.x, GROUND_Y),
		Vector2(ARENA.end.x, GROUND_Y + 9.0), Vector2(ARENA.position.x, GROUND_Y + 9.0)]),
		clip, GRASS_EDGE)
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 50.0, GROUND_Y + 118.0),
			Vector2(ARENA.end.x - 50.0, GROUND_Y + 118.0), 26, GRASS_TUFT, 5)
	for i in 8:
		DrawKit.flower(ci, Vector2(ARENA.position.x + 96.0 + i * 148.0,
				GROUND_Y + 152.0 + float(i % 3) * 10.0), 5.0,
				Color(1, 1, 1, 1) if i % 2 == 0 else Color("ffd1e3"))
	for l in _lifters:
		_draw_stand(ci, l)
	DrawKit.arena_border(ci, ARENA)


## MinigameBase llama a queue_redraw() cada frame: aquí solo lo que se mueve.
func _draw() -> void:
	# Nubes que derivan despacio.
	for i in 3:
		var c := Vector2(ARENA.position.x + 150.0 + i * 380.0 + sin(_time * 0.35 + i * 1.7) * 12.0,
				ARENA.position.y + 52.0 + float(i % 2) * 34.0)
		DrawKit.cloud(self, c, 0.9 + float(i % 2) * 0.2, Color(1.0, 1.0, 1.0, 0.9))
	for l in _lifters:
		_draw_force_bar(l)
		_draw_grip_meter(l)
	for s in _sparks:
		draw_circle(s[0], 3.0, Color(s[2], clamp(s[3] * 3.0, 0.0, 1.0)))
	for l in _lifters:
		_draw_lifter(l)


## Soporte de cada jugador: colchoneta, postes y barra. No se mueve nunca.
func _draw_stand(ci: CanvasItem, l: Lifter) -> void:
	# Colchoneta del color del jugador.
	var mat := Rect2(l.x - 100.0, GROUND_Y + 44.0, 200.0, 54.0)
	var ms := WiiTheme.panel_style(18, Color(l.player.color, 0.45), Color(l.player.color, 0.13))
	ms.set_border_width_all(0)
	ms.shadow_size = 0
	ci.draw_style_box(ms, mat)
	# Postes.
	for side in [-1.0, 1.0]:
		var px: float = l.x + side * POST_OFFSET
		ci.draw_line(Vector2(px + 3.0, GROUND_Y + 2.0), Vector2(px + 3.0, BAR_Y + 2.0),
				Color(WiiTheme.SHADOW, 0.35), 13.0, true)
		ci.draw_line(Vector2(px, GROUND_Y), Vector2(px, BAR_Y), METAL, 13.0, true)
		ci.draw_line(Vector2(px - 3.0, GROUND_Y - 2.0), Vector2(px - 3.0, BAR_Y + 4.0),
				Color(1.0, 1.0, 1.0, 0.4), 4.0, true)
		ci.draw_circle(Vector2(px, BAR_Y), 7.0, METAL)
		ci.draw_circle(Vector2(px, GROUND_Y), 7.0, METAL.darkened(0.1))
	# Barra con remates del color del jugador.
	ci.draw_line(Vector2(l.x - CROSS_HALF + 2.0, BAR_Y + 4.0),
			Vector2(l.x + CROSS_HALF + 2.0, BAR_Y + 4.0), Color(WiiTheme.SHADOW, 0.35), 16.0, true)
	ci.draw_line(Vector2(l.x - CROSS_HALF, BAR_Y), Vector2(l.x + CROSS_HALF, BAR_Y),
			METAL_DARK, 15.0, true)
	ci.draw_line(Vector2(l.x - CROSS_HALF, BAR_Y - 4.0), Vector2(l.x + CROSS_HALF, BAR_Y - 4.0),
			Color(1.0, 1.0, 1.0, 0.35), 4.0, true)
	for side in [-1.0, 1.0]:
		ci.draw_circle(Vector2(l.x + side * CROSS_HALF, BAR_Y), 10.0, l.player.color)
		ci.draw_circle(Vector2(l.x + side * CROSS_HALF - 2.0, BAR_Y - 3.0), 3.5,
				Color(1.0, 1.0, 1.0, 0.45))


func _draw_force_bar(l: Lifter) -> void:
	var x := l.x + FORCE_OFFSET
	var rect := Rect2(x - FORCE_W * 0.5, FORCE_TOP, FORCE_W, FORCE_H)
	var st := WiiTheme.panel_style(19, l.player.color, Color("f4f7f9"))
	st.shadow_size = 4
	draw_style_box(st, rect)
	if l.out:
		draw_rect(rect.grow(-2.0), Color(1.0, 1.0, 1.0, 0.6))
		draw_line(rect.position + Vector2(8.0, 8.0), rect.end - Vector2(8.0, 8.0),
				Color(DANGER_COLOR, 0.7), 6.0, true)
		draw_line(Vector2(rect.end.x - 8.0, rect.position.y + 8.0),
				Vector2(rect.position.x + 8.0, rect.end.y - 8.0), Color(DANGER_COLOR, 0.7), 6.0, true)
		return
	# Zona buena.
	var zy1 := FORCE_TOP + (1.0 - (ZONE_CENTER + l.zone_half)) * FORCE_H
	var zy2 := FORCE_TOP + (1.0 - (ZONE_CENTER - l.zone_half)) * FORCE_H
	draw_rect(Rect2(rect.position.x + 4.0, zy1, FORCE_W - 8.0, zy2 - zy1), ZONE_COLOR)
	draw_line(Vector2(rect.position.x + 4.0, zy1), Vector2(rect.end.x - 4.0, zy1),
			Color(1.0, 1.0, 1.0, 0.65), 2.0)
	draw_line(Vector2(rect.position.x + 4.0, zy2), Vector2(rect.end.x - 4.0, zy2),
			Color(1.0, 1.0, 1.0, 0.65), 2.0)
	# Aguja.
	var ny := FORCE_TOP + (1.0 - l.needle) * FORCE_H
	draw_line(Vector2(rect.position.x - 7.0, ny), Vector2(rect.end.x + 7.0, ny),
			WiiTheme.TEXT.darkened(0.3), 8.0, true)
	draw_circle(Vector2(rect.end.x + 8.0, ny), 6.0, l.player.color.darkened(0.12))
	draw_circle(Vector2(rect.position.x - 8.0, ny), 6.0, l.player.color.darkened(0.12))
	# Pista de descanso.
	if l.rest_t > 0.0:
		draw_rect(rect.grow(-2.0), Color(1.0, 1.0, 1.0, 0.45))
		draw_text_centered("B", Vector2(x, FORCE_TOP - 28.0), 22, WiiTheme.ACCENT_DARK)
	else:
		draw_text_centered("A", Vector2(x, FORCE_TOP - 28.0), 22, l.player.color.darkened(0.12))


func _draw_grip_meter(l: Lifter) -> void:
	var gx := l.x + FORCE_OFFSET - GRIP_W * 0.5
	var ratio: float = clamp(l.grip / GRIP_MAX, 0.0, 1.0)
	var track := WiiTheme.panel_style(8, WiiTheme.PANEL_BORDER, Color(1.0, 1.0, 1.0, 0.95))
	track.shadow_size = 3
	track.content_margin_left = 0
	track.content_margin_right = 0
	track.content_margin_top = 0
	track.content_margin_bottom = 0
	draw_style_box(track, Rect2(gx, GRIP_Y, GRIP_W, GRIP_H))
	if ratio > 0.0:
		var fill := ZONE_COLOR
		if ratio <= 0.3:
			fill = DANGER_COLOR
		elif ratio <= 0.6:
			fill = Color("ffd34d")
		draw_rect(Rect2(gx + 3.0, GRIP_Y + 3.0, (GRIP_W - 6.0) * ratio, GRIP_H - 6.0), fill)
	if l.grip_flash > 0.0:
		draw_rect(Rect2(gx, GRIP_Y, GRIP_W, GRIP_H),
				Color(DANGER_COLOR, l.grip_flash * 0.55))


func _draw_lifter(l: Lifter) -> void:
	var p := l.player
	var col := p.color
	if not p.is_connected_now():
		col = col.linear_interpolate(Color("c8ced4"), 0.7)
	if l.out:
		var t: float = clamp(l.fall_t / FALL_TIME, 0.0, 1.0)
		var e := t * t
		var pos := Vector2(
				lerp(l.fall_from.x, l.fall_from.x + l.fall_dir * 30.0, e),
				lerp(l.fall_from.y, GROUND_Y - BODY_RADIUS * 0.8, e))
		_draw_body(pos, col.linear_interpolate(Color("9aa4ac"), 0.45), p, true)
		return
	var body := _body_pos(l)
	_draw_arms(l, body, col)
	_draw_body(body, col, p, false)
	if l.rest_t > 0.0:
		var t: float = clamp(l.rest_t / REST_TIME, 0.0, 1.0)
		draw_arc(body, BODY_RADIUS + 12.0, -PI * 0.5, -PI * 0.5 + TAU * t,
				28, Color(WiiTheme.ACCENT, 0.85), 5.0, true)


func _draw_arms(l: Lifter, body: Vector2, col: Color) -> void:
	var arm := col.darkened(0.22)
	var flare := 10.0 + 30.0 * l.lift
	if l.rest_t > 0.0:
		flare += sin(_time * 34.0) * 5.0
	for side in [-1.0, 1.0]:
		var sh := body + Vector2(side * BODY_RADIUS * 0.55, -BODY_RADIUS * 0.18)
		var hand := Vector2(l.x + side * GRIP_SPREAD, BAR_Y)
		var mid := (sh + hand) * 0.5
		var elbow := mid + Vector2(side * flare, 8.0 + 10.0 * l.lift)
		draw_polyline(PoolVector2Array([sh, elbow, hand]), arm, 14.0, true)
		draw_circle(sh, 7.0, arm)
		draw_circle(elbow, 7.5, arm)
		draw_circle(hand, 8.0, arm)
		draw_circle(hand + Vector2(0.0, -3.0), 3.5, Color(1.0, 1.0, 1.0, 0.35))


func _draw_body(pos: Vector2, col: Color, p: Player, out: bool) -> void:
	draw_circle(pos, BODY_RADIUS, col)
	draw_circle(pos + Vector2(0.0, BODY_RADIUS * 0.25), BODY_RADIUS * 0.75, col.darkened(0.08))
	draw_circle(pos + Vector2(-BODY_RADIUS * 0.3, -BODY_RADIUS * 0.35), BODY_RADIUS * 0.38,
			Color(1.0, 1.0, 1.0, 0.42))
	draw_text_centered(str(p.index + 1), pos, 28, Color(1.0, 1.0, 1.0, 0.75 if out else 1.0))

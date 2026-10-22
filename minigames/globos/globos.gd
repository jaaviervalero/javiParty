extends MinigameBase
## "Infla el globo": cada jugador machaca A para inflar su globo; se desinfla solo.
## Al llegar al máximo explota, suma un punto y empieza otro globo.

const PUMP_GAIN := 0.075      # tamaño que añade cada pulsación (0..1)
const DEFLATE := 0.05         # lo que se desinfla por segundo
const TENSE_AT := 0.65        # a partir de aquí tiembla y se aclara
const MIN_R := 26.0
const MAX_R := 88.0
const BALLOON_Y := 380.0
const PUMP_Y := 600.0
const NOZZLE_Y := 548.0
const MAX_COL_W := 340.0
const COL_MARGIN := 12.0


class Balloon:
	var player: Player
	var cx := 640.0
	var fill := 0.0
	var squash := 1.0
	var pump := 0.0
	var style: StyleBoxFlat


var _balloons: Array[Balloon] = []
var _confetti: Array = []   # [pos, vel, color, vida]
var _flashes: Array = []    # [pos, t, color]
var _time := 0.0


func _configure() -> void:
	title = {"es": "Infla el globo", "en": "Pump it up"}
	instructions = {"es": "Machaca A para inflar tu globo: el que más globos reviente gana.",
		"en": "Mash A to inflate your balloon: the most balloons popped wins."}
	controls = [
		[Pad.A, {"es": "Inflar", "en": "Pump"}],
	]
	duration = 30.0


func format_score(value) -> String:
	return str(int(value))


func _col_width() -> float:
	return minf(ARENA.size.x / float(maxi(players.size(), 1)), MAX_COL_W)


func _col_left() -> float:
	return ARENA.get_center().x - _col_width() * float(players.size()) * 0.5


func _setup() -> void:
	var colw := _col_width()
	var left := _col_left()
	for i in players.size():
		var b := Balloon.new()
		b.player = players[i]
		b.cx = left + colw * (i + 0.5)
		b.style = WiiTheme.panel_style(24, Color(0, 0, 0, 0), Color(players[i].color, 0.08))
		b.style.shadow_size = 0
		_balloons.append(b)


func _game_process(delta: float) -> void:
	_time += delta
	for b in _balloons:
		b.fill = maxf(0.0, b.fill - DEFLATE * delta)
		b.pump = maxf(0.0, b.pump - delta * 6.0)
		b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 9.0))
		if b.player.just_pressed(Pad.A):
			b.fill = minf(1.0, b.fill + PUMP_GAIN)
			b.pump = 1.0
			b.squash = 1.12
			Sfx.play("move", randf_range(0.85, 1.15))
			if b.fill >= 1.0:
				_pop(b)
	_update_effects(delta)


func _pop(b: Balloon) -> void:
	var c := Vector2(b.cx, BALLOON_Y)
	add_score(b.player)
	_burst(c, b.player.color, 22)
	_flashes.append([c, 0.0, b.player.color])
	Sfx.play("pop", randf_range(0.95, 1.1))
	b.fill = 0.0
	b.squash = 0.4


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(90.0, 390.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.5, 0.9)])


func _update_effects(delta: float) -> void:
	for f in _flashes:
		f[1] += delta * 2.5
	_flashes = _flashes.filter(func(f): return f[1] < 1.0)
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 520) * delta
		c[3] -= delta
	_confetti = _confetti.filter(func(c): return c[3] > 0.0)


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	var colw := _col_width()
	var left := _col_left()
	for i in _balloons.size():
		var rect := Rect2(left + colw * i + COL_MARGIN, ARENA.position.y + COL_MARGIN,
				colw - COL_MARGIN * 2.0, ARENA.size.y - COL_MARGIN * 2.0)
		draw_style_box(_balloons[i].style, rect)
	for b in _balloons:
		_draw_balloon(b)
		_draw_pump(b)
	for f in _flashes:
		var t: float = f[1]
		draw_arc(f[0], 40.0 + t * 190.0, 0.0, TAU, 40, Color(f[2], 1.0 - t), 6.0 * (1.0 - t) + 1.0)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)), Color(c[2], clampf(c[3] * 2.5, 0.0, 1.0)))


func _draw_balloon(b: Balloon) -> void:
	var p := b.player
	var r := lerpf(MIN_R, MAX_R, b.fill)
	var tension := clampf((b.fill - TENSE_AT) / (1.0 - TENSE_AT), 0.0, 1.0)
	var shake := Vector2(sin(_time * 42.0 + p.index * 1.7) * 5.0 * tension,
			cos(_time * 51.0 + p.index * 1.3) * 3.0 * tension)
	var c := Vector2(b.cx, BALLOON_Y) + shake
	var bottom := c + Vector2(0, r * 1.12 * b.squash)

	# Hilo del globo al inflador
	draw_line(bottom + Vector2(0, 18), Vector2(b.cx, NOZZLE_Y), Color(WiiTheme.TEXT_SOFT, 0.55), 3.0)

	# Sombra en el suelo de la columna
	draw_set_transform(Vector2(b.cx, BALLOON_Y + r * 1.12 + 8), 0, Vector2(1.15, 0.3))
	draw_circle(Vector2.ZERO, r, WiiTheme.SHADOW)
	draw_set_transform(Vector2.ZERO)

	# Cuerpo del globo (elipse con squash)
	var col := p.color if p.is_connected_now() else p.color.lerp(Color("c8ced4"), 0.7)
	col = col.lerp(Color.WHITE, tension * 0.5)
	draw_set_transform(c, 0, Vector2(1.0 / b.squash, b.squash * 1.12))
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2(0, r * 0.25), r * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.36, Color(1, 1, 1, 0.45))
	draw_set_transform(Vector2.ZERO)

	# Anillo de tensión cuando está a punto de estallar
	if tension > 0.0:
		draw_arc(c, r * 1.14 + 7.0, 0.0, TAU, 40, Color("e25555", 0.55 * tension), 4.0)

	# Nudo
	var knot := PackedVector2Array([bottom + Vector2(-9, 0), bottom + Vector2(9, 0), bottom + Vector2(0, 18)])
	draw_colored_polygon(knot, col.darkened(0.12))

	var num_col := Color.WHITE.lerp(p.color.darkened(0.45), tension)
	draw_text_centered(str(p.index + 1), c, int(clampf(r * 0.65, 20.0, 42.0)), num_col)


func _draw_pump(b: Balloon) -> void:
	var p := b.player
	var col := p.color if p.is_connected_now() else p.color.lerp(Color("c8ced4"), 0.7)
	# Boquilla
	draw_rect(Rect2(b.cx - 9, NOZZLE_Y, 18, PUMP_Y - NOZZLE_Y), col.darkened(0.25))
	# Cuerpo
	var st := WiiTheme.panel_style(14, col.darkened(0.15), col)
	st.shadow_size = 2
	draw_style_box(st, Rect2(b.cx - 40, PUMP_Y, 80, 42))
	# Mango que baja al machacar
	draw_rect(Rect2(b.cx - 26, PUMP_Y - 24 + 12 * b.pump, 52, 12), col.darkened(0.12))
	draw_text_centered("A", Vector2(b.cx, PUMP_Y + 21), 22, Color.WHITE)

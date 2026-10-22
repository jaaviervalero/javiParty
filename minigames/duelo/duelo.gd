extends MinigameBase
## "¡Desenfunda!": rondas de reflejos. Tras una espera aleatoria aparece una
## señal grande; el primero en pulsar A gana la ronda. Quien se adelanta queda
## fuera de esa ronda. 5 rondas y gana quien más gane.

const ROUNDS := 5
const PREP_MIN := 1.5           # espera mínima antes de la señal (s)
const PREP_MAX := 4.5           # espera máxima antes de la señal (s)
const SIGNAL_TIMEOUT := 3.0     # si nadie pulsa, la ronda se anula
const RESULT_PAUSE := 1.8       # pausa para ver el resultado de la ronda
const SOLO_FAST_SEC := 0.4      # con 1 jugador: reacción que puntúa
const BALL_RADIUS := 42.0
const SIGNAL_RADIUS := 132.0
const SIGNAL_CENTER := Vector2(640, 330)
const BALL_Y := 596.0
const MAX_COL_W := 340.0
const COL_MARGIN := 10.0
# Ambiente: oeste amable a mediodía.
const SKY_WARM_TOP := Color("ffe4bd")
const SKY_WARM_BOTTOM := Color("fff6e6")
const MESA_FAR := Color("ecc9ad")
const MESA_NEAR := Color("e2b795")
const DIRT := Color("eed9b4")
const DIRT_LIGHT := Color("f5e6c9")
const CACTUS := Color("9fd18a")
const CACTUS_DARK := Color("7fbc72")
const DRY_GRASS := Color("c9b483")
const TUMBLE := Color(0.62, 0.48, 0.32, 0.5)

enum Phase { PREP, SIGNAL, RESULT }


class Duelist:
	var player: Player
	var pos := Vector2.ZERO
	var squash := 1.0
	var out_this_round := false
	var reaction := -1.0


var _duelists: Array[Duelist] = []
var _phase := Phase.PREP
var _phase_t := 0.0
var _prep_time := PREP_MIN
var _round := 1
var _signal_t := 0.0
var _winner: Duelist = null
var _void := false
var _void_early := false   # ronda anulada porque todos se adelantaron
var _time := 0.0


func _configure() -> void:
	title = {"es": "¡Desenfunda!", "en": "Draw!"}
	instructions = {"es": "Pulsa A en cuanto aparezca la señal; si te adelantas, quedas fuera de la ronda.",
		"en": "Press A as soon as the signal appears; jump the gun and you sit the round out."}
	controls = [
		[Pad.A, {"es": "Pulsar en la señal", "en": "Press on the signal"}],
	]
	duration = 60.0


func _col_width() -> float:
	return minf(ARENA.size.x / float(maxi(players.size(), 1)), MAX_COL_W)


func _col_left() -> float:
	return ARENA.get_center().x - _col_width() * float(players.size()) * 0.5


func _setup() -> void:
	var colw := _col_width()
	var left := _col_left()
	for i in players.size():
		var d := Duelist.new()
		d.player = players[i]
		d.pos = Vector2(left + colw * (i + 0.5), BALL_Y)
		_duelists.append(d)


func _game_start() -> void:
	_round = 1
	_start_round()


func _start_round() -> void:
	_phase = Phase.PREP
	_phase_t = 0.0
	_prep_time = randf_range(PREP_MIN, PREP_MAX)
	_signal_t = 0.0
	_winner = null
	_void = false
	_void_early = false
	for d in _duelists:
		d.out_this_round = false
		d.reaction = -1.0
		d.squash = 1.0
	Sfx.play("move", 0.8)


func _game_process(delta: float) -> void:
	_time += delta
	_phase_t += delta
	for d in _duelists:
		d.squash = lerpf(d.squash, 1.0, minf(1.0, delta * 8.0))

	match _phase:
		Phase.PREP:
			_process_prep()
		Phase.SIGNAL:
			_process_signal(delta)
		Phase.RESULT:
			if _phase_t >= RESULT_PAUSE:
				if _void:
					_start_round()  # la ronda anulada se repite
				else:
					_round += 1
					if _round > ROUNDS:
						finish()
					else:
						_start_round()


func _process_prep() -> void:
	var all_out := true
	for d in _duelists:
		if d.out_this_round:
			continue
		if d.player.just_pressed(Pad.A):
			d.out_this_round = true
			d.squash = 0.65
			Sfx.play("back", randf_range(0.9, 1.1))
		else:
			all_out = false
	if all_out:
		# Todos se han adelantado: la ronda no cuenta y se repite.
		_void = true
		_void_early = true
		_end_round()
	elif _phase_t >= _prep_time:
		_phase = Phase.SIGNAL
		_phase_t = 0.0
		_signal_t = 0.0
		Sfx.play("star", 1.3)


func _process_signal(delta: float) -> void:
	_signal_t += delta
	var pressed := false
	for d in _duelists:
		if d.out_this_round or d.reaction >= 0.0:
			continue
		if d.player.just_pressed(Pad.A):
			d.reaction = _signal_t
			d.squash = 1.5
			pressed = true
			if _winner == null:
				_winner = d
	if pressed:
		Sfx.play("pop", randf_range(1.0, 1.2))
	if _winner != null:
		_end_round()
	elif _signal_t >= SIGNAL_TIMEOUT:
		_void = true
		_end_round()


func _end_round() -> void:
	if not _void and _winner != null:
		# Con 1 jugador solo puntúan las reacciones rápidas.
		if players.size() > 1 or _winner.reaction < SOLO_FAST_SEC:
			add_score(_winner.player)
			Sfx.play("accept", 1.1)
	else:
		Sfx.play("back", 0.8)
	_phase = Phase.RESULT
	_phase_t = 0.0


# --- Dibujo ---

## Escenario fijo: se pinta una vez (MinigameBase._draw_scenery).
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	DrawKit.arena_frame(ci, ARENA, SKY_WARM_TOP, SKY_WARM_BOTTOM)
	# Sol grande de mediodía.
	DrawKit.sun(ci, Vector2(ARENA.end.x - 160.0, ARENA.position.y + 96.0), 52.0)
	# Mesetas y dunas redondeadas al fondo.
	DrawKit.hills(ci, ARENA, ARENA.end.y - 176.0, 22.0, MESA_FAR, 0.7, 1.5, clip)
	_draw_mesa(ci, ARENA.position.x + 250.0, ARENA.end.y - 168.0, 260.0, 96.0, MESA_NEAR, clip)
	_draw_mesa(ci, ARENA.position.x + 985.0, ARENA.end.y - 166.0, 200.0, 76.0, MESA_FAR, clip)
	# Suelo de tierra clara.
	DrawKit.hills(ci, ARENA, ARENA.end.y - 136.0, 12.0, DIRT, 0.7, 1.4, clip)
	DrawKit.hills(ci, ARENA, ARENA.end.y - 48.0, 7.0, DIRT_LIGHT, 2.4, 1.1, clip)
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 50.0, ARENA.end.y - 34.0),
			Vector2(ARENA.end.x - 50.0, ARENA.end.y - 34.0), 14, DRY_GRASS, 5)
	# Piedras redondeadas.
	var rocks := [Vector2(ARENA.position.x + 150.0, ARENA.end.y - 44.0),
		Vector2(ARENA.position.x + 430.0, ARENA.end.y - 26.0),
		Vector2(ARENA.end.x - 210.0, ARENA.end.y - 40.0),
		Vector2(ARENA.end.x - 470.0, ARENA.end.y - 22.0)]
	for i in rocks.size():
		DrawKit.ellipse(ci, rocks[i], Vector2(20.0 - i * 2.0, 9.0 - i), Color("d8bf9c"))
	# Cactus suaves a los lados.
	_draw_cactus(ci, Vector2(ARENA.position.x + 130.0, ARENA.end.y - 120.0), 96.0, 1.0)
	_draw_cactus(ci, Vector2(ARENA.end.x - 120.0, ARENA.end.y - 110.0), 78.0, 0.8)
	# Columnas fijas de cada jugador.
	var colw := _col_width()
	var left := _col_left()
	for i in _duelists.size():
		var r := Rect2(left + colw * i + COL_MARGIN, ARENA.position.y + COL_MARGIN,
				colw - COL_MARGIN * 2.0, ARENA.size.y - COL_MARGIN * 2.0)
		var st := WiiTheme.panel_style(24, Color(0, 0, 0, 0), Color(_duelists[i].player.color, 0.08))
		st.shadow_size = 0
		ci.draw_style_box(st, r)
	DrawKit.arena_border(ci, ARENA)


## Meseta de dibujos animados: base ancha y cima redondeada.
func _draw_mesa(ci: CanvasItem, cx: float, base_y: float, w: float, h: float, color: Color,
		clip: PackedVector2Array) -> void:
	var top := base_y - h
	var pts := PackedVector2Array()
	pts.append(Vector2(cx - w * 0.5, base_y))
	pts.append(Vector2(cx - w * 0.34, top + h * 0.3))
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		pts.append(Vector2(cx + cos(a) * w * 0.34, top + h * 0.3 + sin(a) * h * 0.3))
	pts.append(Vector2(cx + w * 0.5, base_y))
	DrawKit.clipped_polygon(ci, pts, clip, color)
	# Cima más clara donde da el sol.
	var lit := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		lit.append(Vector2(cx + cos(a) * w * 0.3, top + h * 0.24 + sin(a) * h * 0.22))
	DrawKit.clipped_polygon(ci, lit, clip, Color(color.lightened(0.12), 0.45))


## Cactus redondeado, sin pinchos agresivos.
func _draw_cactus(ci: CanvasItem, base: Vector2, h: float, s: float) -> void:
	var w := 22.0 * s
	ci.draw_rect(Rect2(base.x - w * 0.5, base.y - h, w, h), CACTUS)
	ci.draw_circle(Vector2(base.x, base.y - h), w * 0.5, CACTUS)
	ci.draw_circle(Vector2(base.x, base.y), w * 0.5, CACTUS)
	_draw_cactus_arm(ci, Vector2(base.x, base.y - h * 0.58), -1.0, 26.0 * s, 18.0 * s)
	_draw_cactus_arm(ci, Vector2(base.x, base.y - h * 0.4), 1.0, 20.0 * s, 14.0 * s)
	ci.draw_line(Vector2(base.x - w * 0.22, base.y - h + 10.0 * s),
			Vector2(base.x - w * 0.22, base.y - 8.0), Color(1, 1, 1, 0.22), 3.0, true)


func _draw_cactus_arm(ci: CanvasItem, from: Vector2, dir: float, len_x: float, up: float) -> void:
	var elbow := from + Vector2(dir * len_x, 0)
	var tip := elbow + Vector2(0, -up)
	ci.draw_line(from, elbow, CACTUS_DARK, 10.0, true)
	ci.draw_line(elbow, tip, CACTUS_DARK, 10.0, true)
	ci.draw_circle(from, 5.0, CACTUS_DARK)
	ci.draw_circle(elbow, 5.0, CACTUS_DARK)
	ci.draw_circle(tip, 5.0, CACTUS_DARK)


## Dos matojos rodando despacio (ambiente barato).
func _draw_tumbleweeds() -> void:
	_draw_tumbleweed(_tumble_pos(0.0, 44.0), 15.0)
	_draw_tumbleweed(_tumble_pos(2.7, 32.0), 11.0)


func _tumble_pos(phase: float, speed: float) -> Vector2:
	# Recorren la arena de lado a lado, sin salirse del marco.
	var lo := ARENA.position.x + 26.0
	var hi := ARENA.end.x - 26.0
	var t := fmod(_time * speed / (hi - lo) + phase * 0.11, 1.0)
	var x := lerpf(lo, hi, t)
	var y := ARENA.end.y - 74.0 - absf(sin(_time * 2.4 + phase)) * 14.0
	return Vector2(x, y)


func _draw_tumbleweed(p: Vector2, r: float) -> void:
	var spin := _time * 2.2
	draw_arc(p, r, 0.0, TAU, 16, TUMBLE, 2.0, true)
	draw_arc(p, r * 0.62, spin, spin + TAU * 0.8, 12, TUMBLE, 1.8, true)
	for i in 5:
		var a := spin + TAU * float(i) / 5.0
		draw_line(p + Vector2.from_angle(a) * r * 0.3, p + Vector2.from_angle(a) * r * 0.92,
				TUMBLE, 1.8, true)


## MinigameBase llama a queue_redraw() cada frame: aquí solo lo que se mueve.
func _draw() -> void:
	_draw_tumbleweeds()
	draw_text_centered(loc({"es": "Ronda %d de %d", "en": "Round %d of %d"}) % [_round, ROUNDS],
			Vector2(640, ARENA.position.y + 46), 26, WiiTheme.TEXT_SOFT)

	match _phase:
		Phase.PREP:
			_draw_prep()
		Phase.SIGNAL:
			_draw_signal()
		Phase.RESULT:
			_draw_result()

	for d in _duelists:
		_draw_duelist(d)

	if players.size() == 1:
		draw_text_centered(loc({"es": "Menos de 0.40 s para puntuar", "en": "Under 0.40 s to score"}),
				Vector2(640, ARENA.position.y + 84), 20, WiiTheme.TEXT_SOFT)


func _draw_prep() -> void:
	var pulse := 1.0 + sin(_time * 2.5) * 0.03
	draw_circle(SIGNAL_CENTER + Vector2(0, 10), SIGNAL_RADIUS * 0.78 * pulse, WiiTheme.SHADOW)
	draw_circle(SIGNAL_CENTER, SIGNAL_RADIUS * 0.78 * pulse, Color("eef3f7"))
	draw_text_centered(loc({"es": "Preparados...", "en": "Ready..."}), SIGNAL_CENTER, 54, WiiTheme.TEXT)
	for i in 3:
		var a := 0.3 + 0.7 * maxf(0.0, sin(_time * 3.2 - i * 0.7))
		draw_circle(SIGNAL_CENTER + Vector2(-40 + i * 40, 70), 10, Color(WiiTheme.ACCENT, a))


func _draw_signal() -> void:
	var pulse := 1.0 + sin(_phase_t * 20.0) * 0.035
	draw_circle(SIGNAL_CENTER + Vector2(0, 12), SIGNAL_RADIUS * pulse, WiiTheme.SHADOW)
	draw_circle(SIGNAL_CENTER, SIGNAL_RADIUS * pulse, Color("ffd34d"))
	draw_circle(SIGNAL_CENTER + Vector2(-34, -40), SIGNAL_RADIUS * 0.52, Color(1, 1, 1, 0.4))
	draw_arc(SIGNAL_CENTER, SIGNAL_RADIUS * pulse, 0.0, TAU, 48, Color("e8b21f"), 5.0, true)
	draw_text_centered(loc({"es": "¡YA!", "en": "NOW!"}), SIGNAL_CENTER, 78, Color("6b4e00"))


func _draw_result() -> void:
	if _void:
		draw_text_centered(loc({"es": "Ronda anulada", "en": "Round void"}), Vector2(640, 310), 50, Color("e25555"))
		var why := loc({"es": "Todos se adelantaron", "en": "Everyone jumped early"})
		if not _void_early:
			why = loc({"es": "Nadie pulsó a tiempo", "en": "Nobody pressed in time"})
		draw_text_centered(why, Vector2(640, 366), 26, WiiTheme.TEXT_SOFT)
	elif _winner != null:
		draw_text_centered(loc({"es": "Gana el jugador %d", "en": "Player %d wins"}) % (_winner.player.index + 1),
				Vector2(640, 300), 46, WiiTheme.TEXT)
		draw_text_centered("%d ms" % int(round(_winner.reaction * 1000.0)), Vector2(640, 372), 58,
				_winner.player.color.darkened(0.25))


func _draw_duelist(d: Duelist) -> void:
	var p := d.player
	var col := p.color
	if d.out_this_round or not p.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	var stretch := Vector2(1.0 / d.squash, d.squash)
	draw_set_transform(d.pos + Vector2(0, 8), 0, Vector2(stretch.x * 1.05, 0.35))
	draw_circle(Vector2.ZERO, BALL_RADIUS, WiiTheme.SHADOW)
	draw_set_transform(d.pos, 0, stretch)
	draw_circle(Vector2.ZERO, BALL_RADIUS, col)
	draw_circle(Vector2(0, BALL_RADIUS * 0.25), BALL_RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-BALL_RADIUS * 0.3, -BALL_RADIUS * 0.35), BALL_RADIUS * 0.38, Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(p.index + 1), d.pos, 34, Color.WHITE)

	var status := ""
	var scol := WiiTheme.TEXT_SOFT
	if d.out_this_round:
		status = loc({"es": "¡Antes de tiempo!", "en": "Too soon!"})
		scol = Color("e25555")
	elif d.reaction >= 0.0:
		status = "%d ms" % int(round(d.reaction * 1000.0))
		scol = p.color.darkened(0.25)
	if status != "":
		draw_text_centered(status, d.pos + Vector2(0, BALL_RADIUS + 36), 26, scol)

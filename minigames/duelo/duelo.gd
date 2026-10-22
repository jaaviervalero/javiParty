extends MinigameBase
## "Duelo al sol": rondas de reflejos. Tras una espera aleatoria aparece una
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
	title = {"es": "Duelo al sol", "en": "Showdown"}
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

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	var colw := _col_width()
	var left := _col_left()
	for i in _duelists.size():
		var r := Rect2(left + colw * i + COL_MARGIN, ARENA.position.y + COL_MARGIN,
				colw - COL_MARGIN * 2.0, ARENA.size.y - COL_MARGIN * 2.0)
		var st := WiiTheme.panel_style(24, Color(0, 0, 0, 0), Color(_duelists[i].player.color, 0.08))
		st.shadow_size = 0
		draw_style_box(st, r)

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

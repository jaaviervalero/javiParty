extends MinigameBase
## "Para el reloj": cada jugador para su propio cronómetro lo más cerca posible
## de un objetivo secreto a la vista. Los números se ocultan al segundo y medio.
## Gana quien menos se desvía en total (3 rondas).

const ROUNDS := 3
const TARGET_MIN := 3.0
const TARGET_MAX := 7.0
const TARGET_STEP := 0.5
const CLOCK_VISIBLE_SEC := 1.5   # los números se ven solo al principio
const TIMEOUT_EXTRA := 3.0       # margen tras el objetivo antes de contar como parado
const REVEAL_PAUSE := 2.5
const COL_TOP := 256.0
const COL_BOTTOM := 682.0
const MAX_COL_W := 340.0
const COL_MARGIN := 10.0

enum Phase { RUN, REVEAL }


class Racer:
	var player: Player
	var stopped := false
	var time := 0.0
	var err := 0.0
	var total := 0.0   # suma de errores (se guarda con set_score: add_score trunca a int)
	var best := false
	var flash := 0.0
	var cx := 640.0
	var style: StyleBoxFlat


var _racers: Array[Racer] = []
var _targets: Array[float] = []
var _round := 0  # 0..ROUNDS-1
var _phase := Phase.RUN
var _clock := 0.0
var _phase_t := 0.0
var _time := 0.0
var _hidden_sound := false


func _configure() -> void:
	title = {"es": "Para el reloj", "en": "Stop the clock"}
	instructions = {"es": "Para tu cronómetro lo más cerca posible del objetivo: el que menos se desvíe gana.",
		"en": "Stop your timer as close to the target as you can: the smallest miss wins."}
	controls = [
		[Pad.A, {"es": "Parar tu cronómetro", "en": "Stop your timer"}],
	]
	duration = 75.0
	lower_is_better = true


func format_score(value) -> String:
	return "%.2f s" % float(value)


func _col_width() -> float:
	return minf(ARENA.size.x / float(maxi(players.size(), 1)), MAX_COL_W)


func _col_left() -> float:
	return ARENA.get_center().x - _col_width() * float(players.size()) * 0.5


func _setup() -> void:
	for i in ROUNDS:
		_targets.append(_random_target())
	var colw := _col_width()
	var left := _col_left()
	for i in players.size():
		var r := Racer.new()
		r.player = players[i]
		r.cx = left + colw * (i + 0.5)
		r.style = WiiTheme.panel_style(24, Color(0, 0, 0, 0), Color(players[i].color, 0.08))
		r.style.shadow_size = 0
		_racers.append(r)


func _random_target() -> float:
	return float(randi_range(int(TARGET_MIN / TARGET_STEP), int(TARGET_MAX / TARGET_STEP))) * TARGET_STEP


func _game_start() -> void:
	_round = 0
	_start_round()


func _start_round() -> void:
	_phase = Phase.RUN
	_clock = 0.0
	_phase_t = 0.0
	_hidden_sound = false
	for r in _racers:
		r.stopped = false
		r.time = 0.0
		r.err = 0.0
		r.best = false
		r.flash = 0.0
	Sfx.play("move", 0.9)


func _game_process(delta: float) -> void:
	_time += delta
	_phase_t += delta
	if _phase == Phase.RUN:
		_run_round(delta)
	else:
		for r in _racers:
			r.flash = maxf(0.0, r.flash - delta * 2.0)
		if _phase_t >= REVEAL_PAUSE:
			_round += 1
			if _round >= ROUNDS:
				finish()
			else:
				_start_round()


func _run_round(delta: float) -> void:
	_clock += delta
	for r in _racers:
		r.flash = maxf(0.0, r.flash - delta * 2.0)
		if not r.stopped and r.player.just_pressed(Pad.A):
			r.stopped = true
			r.time = _clock
			r.flash = 1.0
			Sfx.play("pop", randf_range(0.95, 1.15))

	if not _hidden_sound and _clock >= CLOCK_VISIBLE_SEC:
		_hidden_sound = true
		Sfx.play("back", 1.25)

	var all_stopped := true
	for r in _racers:
		if not r.stopped:
			all_stopped = false
	if all_stopped:
		_reveal()
	elif _clock >= _targets[_round] + TIMEOUT_EXTRA:
		# Se acabó el margen: quien no haya parado cuenta como parado ahora.
		for r in _racers:
			if not r.stopped:
				r.stopped = true
				r.time = _targets[_round] + TIMEOUT_EXTRA
				Sfx.play("back", randf_range(0.9, 1.05))
		_reveal()


## Suma un error al total del jugador. Se usa set_score porque add_score tiene el
## parámetro tipado como int (truncaría los decimales).
func _add_error(r: Racer, amount: float) -> void:
	r.total += amount
	set_score(r.player, r.total)


func _reveal() -> void:
	_phase = Phase.REVEAL
	_phase_t = 0.0
	var target := _targets[_round]
	var best_err := INF
	for r in _racers:
		r.err = absf(r.time - target)
		best_err = minf(best_err, r.err)
	for r in _racers:
		r.best = r.err <= best_err + 0.0001
		_add_error(r, r.err)
	Sfx.play("star", randf_range(0.95, 1.1))


func _game_end() -> void:
	if _round >= ROUNDS:
		return
	if _phase == Phase.RUN:
		# La ronda en curso también cuenta al agotarse el tiempo: quien no haya
		# parado recibe el error máximo (objetivo + margen), no el margen a secas.
		var target := _targets[_round]
		for r in _racers:
			if r.stopped:
				_add_error(r, absf(r.time - target))
			else:
				_add_error(r, target + TIMEOUT_EXTRA)
	# Rondas que no se llegaron a jugar: desvío máximo para todos.
	for i in range(_round + 1, ROUNDS):
		for r in _racers:
			_add_error(r, _targets[i] + TIMEOUT_EXTRA)


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	var target := _targets[mini(_round, ROUNDS - 1)]
	draw_text_centered(loc({"es": "Objetivo", "en": "Target"}) + "  " + ("%.2f s" % target),
			Vector2(640, ARENA.position.y + 52), 46, WiiTheme.TEXT)
	draw_text_centered(loc({"es": "Ronda %d de %d", "en": "Round %d of %d"}) % [_round + 1, ROUNDS],
			Vector2(640, ARENA.position.y + 104), 24, WiiTheme.TEXT_SOFT)

	var colw := _col_width()
	var left := _col_left()
	var hidden := _clock >= CLOCK_VISIBLE_SEC
	for i in _racers.size():
		var r := _racers[i]
		var rect := Rect2(left + colw * i + COL_MARGIN, COL_TOP,
				colw - COL_MARGIN * 2.0, COL_BOTTOM - COL_TOP)
		draw_style_box(r.style, rect)
		if r.best:
			var hl := WiiTheme.panel_style(24, Color("ffd34d"), Color(0, 0, 0, 0))
			hl.shadow_size = 0
			hl.set_border_width_all(5)
			draw_style_box(hl, rect)
			draw_text_centered(loc({"es": "Mejor", "en": "Best"}), Vector2(r.cx, COL_TOP + 26), 24,
					Color("b8891b"))

		_draw_racer(r, hidden)


func _draw_racer(r: Racer, hidden: bool) -> void:
	var p := r.player
	var col := p.color if p.is_connected_now() else p.color.lerp(Color("c8ced4"), 0.7)

	# Ficha del jugador
	var cy := COL_TOP + 90.0
	draw_circle(Vector2(r.cx, cy) + Vector2(0, 6), 36, WiiTheme.SHADOW)
	draw_circle(Vector2(r.cx, cy), 36, col)
	draw_circle(Vector2(r.cx - 11, cy - 12), 14, Color(1, 1, 1, 0.4))
	draw_text_centered(str(p.index + 1), Vector2(r.cx, cy), 30, Color.WHITE)
	if r.flash > 0.0:
		draw_arc(Vector2(r.cx, cy), 36.0 + (1.0 - r.flash) * 46.0, 0.0, TAU, 32,
				Color(p.color, r.flash * 0.8), 6.0)

	# Reloj
	var shown := "???"
	var tcol := WiiTheme.TEXT_SOFT
	if r.stopped:
		shown = "%.2f" % r.time
		tcol = col.darkened(0.25)
	elif not hidden:
		shown = "%.2f" % _clock
		tcol = WiiTheme.TEXT
	draw_text_centered(shown, Vector2(r.cx, COL_TOP + 190), 56, tcol)

	# Estado
	if r.stopped:
		draw_text_centered(loc({"es": "Parado", "en": "Stopped"}), Vector2(r.cx, COL_TOP + 252), 24,
				WiiTheme.ACCENT_DARK)
	else:
		draw_text_centered(loc({"es": "En marcha", "en": "Running"}), Vector2(r.cx, COL_TOP + 252), 22,
				WiiTheme.TEXT_SOFT)

	# Error al revelar
	if _phase == Phase.REVEAL:
		var ecol := Color("e25555") if r.err > 1.0 else WiiTheme.TEXT
		if r.best:
			ecol = Color("b8891b")
		draw_text_centered(loc({"es": "Error", "en": "Miss"}), Vector2(r.cx, COL_TOP + 312), 22, WiiTheme.TEXT_SOFT)
		draw_text_centered("%.2f s" % r.err, Vector2(r.cx, COL_TOP + 358), 34, ecol)

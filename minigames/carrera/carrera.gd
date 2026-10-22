extends MinigameBase
## "Carrera de pulgares": una calle por jugador. Se corre alternando A y B; repetir
## el mismo botón hace tropezar. Hay dos vallas por calle: cuando aparece el aviso,
## hay que pulsar arriba en el momento justo. Gana quien llega antes a los 100 m.

const LANE_GAP := 8.0
const START_MARGIN := 74.0
const FINISH_MARGIN := 86.0
const RUNNER_RADIUS := 18.0
const MAX_SPEED := 12.0
const IMPULSE := 1.5
const DECAY := 2.8
const STUMBLE_TIME := 0.4
const STUMBLE_KEEP := 0.72
const JUMP_TIME := 0.45
const JUMP_HEIGHT := 26.0
const WARN_DIST := 14.0
const JUMP_WINDOW := 6.0
const MISS_GRACE := 2.5
const HURDLES := [38.0, 72.0]
const FINISH_METERS := 100.0
const END_DELAY := 1.5
const DNF_SCORE := 999.0


class Runner:
	var player: Player
	var meters := 0.0
	var speed := 0.0
	var last_btn := 0
	var stumble_t := 0.0
	var jump_t := 0.0
	var squash := 1.0
	var finished := false
	var arrival := 0.0
	var place := 0
	var lane := Rect2()
	var cleared: Array[bool] = []
	var missed: Array[bool] = []


var _runners: Array[Runner] = []
var _finish_count := 0
var _ending := false
var _end_t := 0.0
var _time := 0.0
var _start_x := 0.0
var _finish_x := 0.0
var _panel_style: StyleBoxFlat
var _warn_style: StyleBoxFlat


func _configure() -> void:
	title = {"es": "Carrera de pulgares", "en": "Thumb sprint"}
	instructions = {"es": "Alterna A y B para correr y pulsa arriba para saltar las vallas.",
		"en": "Alternate A and B to run and press up to jump the hurdles."}
	controls = [
		[Pad.A, {"es": "Correr (alterna con B)", "en": "Run (alternate with B)"}],
		[Pad.B, {"es": "Correr (alterna con A)", "en": "Run (alternate with A)"}],
		[Pad.UP, {"es": "Saltar la valla", "en": "Jump the hurdle"}],
	]
	duration = 45.0
	lower_is_better = true


func _setup() -> void:
	_panel_style = WiiTheme.panel_style(20)
	_warn_style = StyleBoxFlat.new()
	_warn_style.bg_color = Color("ffe1e1")
	_warn_style.border_color = Color("e25555")
	_warn_style.set_border_width_all(2)
	_warn_style.set_corner_radius_all(12)
	_warn_style.shadow_color = WiiTheme.SHADOW
	_warn_style.shadow_size = 3
	_warn_style.shadow_offset = Vector2(0, 2)
	_warn_style.anti_aliasing = true

	var n := players.size()
	var lane_h := (ARENA.size.y - LANE_GAP * (n - 1)) / n
	_start_x = ARENA.position.x + START_MARGIN
	_finish_x = ARENA.end.x - FINISH_MARGIN
	for i in n:
		var lane := Rect2(ARENA.position.x, ARENA.position.y + i * (lane_h + LANE_GAP),
				ARENA.size.x, lane_h)
		var runner := Runner.new()
		runner.player = players[i]
		runner.lane = lane
		for h in HURDLES:
			runner.cleared.append(false)
			runner.missed.append(false)
		_runners.append(runner)
		set_score(players[i], 0.0)


func _game_start() -> void:
	_finish_count = 0
	_ending = false
	_end_t = 0.0
	for runner in _runners:
		runner.meters = 0.0
		runner.speed = 0.0
		runner.last_btn = 0
		runner.finished = false
		set_score(runner.player, 0.0)


func _game_process(delta: float) -> void:
	_time += delta
	for runner in _runners:
		_update_runner(runner, delta)
		if not runner.finished:
			set_score(runner.player, elapsed)
	if _ending:
		_end_t += delta
		if _end_t >= END_DELAY:
			finish()


func _game_end() -> void:
	for runner in _runners:
		if not runner.finished:
			set_score(runner.player, DNF_SCORE)


func _update_runner(runner: Runner, delta: float) -> void:
	runner.squash = lerpf(runner.squash, 1.0, minf(1.0, delta * 10.0))
	runner.stumble_t = maxf(0.0, runner.stumble_t - delta)
	runner.jump_t = maxf(0.0, runner.jump_t - delta)
	if runner.finished:
		runner.speed = 0.0
		return

	var p := runner.player
	if runner.stumble_t <= 0.0:
		if p.just_pressed(Pad.A):
			_press(runner, Pad.A)
		elif p.just_pressed(Pad.B):
			_press(runner, Pad.B)
		if p.just_pressed(Pad.UP):
			_jump(runner)

	if runner.stumble_t <= 0.0:
		runner.speed = maxf(0.0, runner.speed - DECAY * delta)

	runner.meters += runner.speed * delta

	for i in HURDLES.size():
		if runner.cleared[i] or runner.missed[i]:
			continue
		var hurdle: float = HURDLES[i]
		if runner.meters > hurdle + MISS_GRACE:
			runner.missed[i] = true
			_stumble(runner)

	if runner.meters >= FINISH_METERS:
		runner.meters = FINISH_METERS
		runner.finished = true
		runner.arrival = elapsed
		runner.place = _finish_count + 1
		_finish_count += 1
		set_score(p, runner.arrival)
		Sfx.play("star", randf_range(0.95, 1.1))
		if _finish_count == _runners.size():
			_ending = true
			_end_t = 0.0


func _press(runner: Runner, btn: int) -> void:
	if runner.last_btn == btn:
		_stumble(runner)
		runner.last_btn = 0
		return
	runner.last_btn = btn
	runner.speed = minf(MAX_SPEED, runner.speed + IMPULSE)
	runner.squash = 1.18
	Sfx.play("move", randf_range(1.15, 1.45))


func _jump(runner: Runner) -> void:
	if runner.jump_t > 0.0:
		return
	runner.jump_t = JUMP_TIME
	runner.squash = 1.25
	var cleared_one := false
	for i in HURDLES.size():
		if runner.cleared[i] or runner.missed[i]:
			continue
		if absf(runner.meters - HURDLES[i]) <= JUMP_WINDOW:
			runner.cleared[i] = true
			cleared_one = true
	if cleared_one:
		Sfx.play("pop", randf_range(1.0, 1.2))
	else:
		Sfx.play("dash", 1.4)


func _stumble(runner: Runner) -> void:
	if runner.stumble_t > 0.0:
		return
	runner.stumble_t = STUMBLE_TIME
	runner.speed *= STUMBLE_KEEP
	Sfx.play("back", randf_range(0.9, 1.05))


func _meter_to_x(meters: float) -> float:
	return _start_x + (_finish_x - _start_x) * clampf(meters / FINISH_METERS, 0.0, 1.0)


func _ordinal(n: int) -> String:
	if TranslationServer.get_locale().substr(0, 2) == "en":
		var suffix := "th"
		if n % 10 == 1 and n % 100 != 11:
			suffix = "st"
		elif n % 10 == 2 and n % 100 != 12:
			suffix = "nd"
		elif n % 10 == 3 and n % 100 != 13:
			suffix = "rd"
		return "%d%s" % [n, suffix]
	return "%dº" % n


func format_score(value) -> String:
	if float(value) >= DNF_SCORE:
		return "--"
	return "%.2f s" % float(value)


# --- Dibujo ---

func _draw() -> void:
	for runner in _runners:
		draw_style_box(_panel_style, runner.lane)
	for runner in _runners:
		_draw_track_marks(runner.lane)
	for runner in _runners:
		_draw_hurdles(runner)
	for runner in _runners:
		_draw_warning(runner)
	for runner in _runners:
		_draw_runner(runner)


func _draw_track_marks(lane: Rect2) -> void:
	# Salida y meta a cuadros.
	draw_rect(Rect2(_start_x - 2.0, lane.position.y, 4.0, lane.size.y), WiiTheme.ACCENT)
	var sq := 10.0
	var y := lane.position.y
	var k := 0
	while y < lane.end.y:
		var col := Color("5b6670") if k % 2 == 0 else Color.WHITE
		var h := minf(sq, lane.end.y - y)
		draw_rect(Rect2(_finish_x - 5.0, y, 10.0, h), col)
		y += sq
		k += 1


func _draw_hurdles(runner: Runner) -> void:
	var y := runner.lane.get_center().y
	for i in HURDLES.size():
		var x := _meter_to_x(HURDLES[i])
		var col := Color("e25555")
		if runner.cleared[i]:
			col = Color("9fd7ad")
		elif runner.missed[i]:
			col = Color("b9c1c9")
		if runner.cleared[i]:
			# Valla saltada: la barra queda baja, en el suelo.
			draw_line(Vector2(x - 17.0, y + 16.0), Vector2(x + 17.0, y + 16.0), col, 5.0)
		else:
			draw_line(Vector2(x - 14.0, y + 16.0), Vector2(x - 14.0, y - 6.0), col, 4.0)
			draw_line(Vector2(x + 14.0, y + 16.0), Vector2(x + 14.0, y - 6.0), col, 4.0)
			draw_line(Vector2(x - 18.0, y - 6.0), Vector2(x + 18.0, y - 6.0), col, 5.0)


func _draw_warning(runner: Runner) -> void:
	if runner.finished:
		return
	for i in HURDLES.size():
		if runner.cleared[i] or runner.missed[i]:
			continue
		var hurdle: float = HURDLES[i]
		if runner.meters < hurdle - WARN_DIST or runner.meters >= hurdle:
			continue
		var x := _meter_to_x(hurdle)
		var wy := runner.lane.get_center().y - 44.0 + sin(_time * 9.0) * 3.0
		draw_style_box(_warn_style, Rect2(x - 48.0, wy - 15.0, 96.0, 30.0))
		draw_text_centered(loc({"es": "Arriba", "en": "Up"}), Vector2(x, wy), 20,
				Color("c74646"))


func _draw_runner(runner: Runner) -> void:
	var lane := runner.lane
	var x := _meter_to_x(runner.meters)
	var y := lane.get_center().y
	var lift := 0.0
	if runner.jump_t > 0.0:
		lift = sin((1.0 - runner.jump_t / JUMP_TIME) * PI) * JUMP_HEIGHT
	var wobble := 0.0
	if runner.stumble_t > 0.0:
		wobble = sin(runner.stumble_t * 40.0) * 0.35

	draw_set_transform(Vector2(x, y - lift + 5.0), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, RUNNER_RADIUS, WiiTheme.SHADOW)
	draw_set_transform(Vector2(x, y - lift), wobble,
			Vector2(1.0 / runner.squash, runner.squash))
	var col := runner.player.color
	if runner.finished:
		col = col.lerp(Color.WHITE, 0.15)
	draw_circle(Vector2.ZERO, RUNNER_RADIUS, col)
	draw_circle(Vector2(-RUNNER_RADIUS * 0.3, -RUNNER_RADIUS * 0.35),
			RUNNER_RADIUS * 0.35, Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(runner.player.index + 1), Vector2(x, y - lift), 20, Color.WHITE)

	if runner.finished:
		var tx := clampf(x, ARENA.position.x + 34.0, ARENA.end.x - 34.0)
		draw_text_centered(_ordinal(runner.place), Vector2(tx, y - lift - RUNNER_RADIUS - 18.0),
				22, runner.player.color.darkened(0.15))

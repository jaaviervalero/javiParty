extends MinigameBase
## "Sigue la secuencia": la máquina ilumina una secuencia de direcciones y todos
## los jugadores la repiten a la vez con la cruceta o el stick. Fallar elimina.

const PETAL_DIST := 132.0
const PETAL_RADIUS := 80.0
const STEP_SEC := 0.62          # duración de cada paso durante la demostración
const LIGHT_FRAC := 0.66        # parte del paso que el pétalo está encendido
const REPEAT_PER_STEP := 1.2    # segundos para repetir, por paso
const GAP_SEC := 1.1
const START_STEPS := 3

## 0 arriba, 1 derecha, 2 abajo, 3 izquierda. Tonos pastel, distintos de los jugadores.
const PETAL_COLORS: Array[Color] = [
	Color("9ad4f0"), Color("ffc98f"), Color("f6a9c9"), Color("a9e0a4"),
]
const DIRS: Array[int] = [Pad.UP, Pad.RIGHT, Pad.DOWN, Pad.LEFT]
const DIR_VECS := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
# Ambiente: pequeño teatro con telones pastel, tablas claras y foco suave.
const STAGE_TOP := Color("e9def9")
const STAGE_BOTTOM := Color("fdf1e2")
const CURTAIN := Color("e7a9c0")
const CURTAIN_DARK := Color("d68aa8")
const CURTAIN_LIGHT := Color("f5c4d5")
const FLOOR := Color("eedcbd")
const FLOOR_DARK := Color("d9c096")
const SPOTLIGHT := Color(1.0, 0.98, 0.82, 0.24)
const MOTE := Color(1.0, 0.94, 0.62)

enum Phase { WATCH, REPEAT, GAP }


class MemPlayer:
	var player: Player
	var alive := true
	var progress := 0
	var done_round := false


var _states: Array[MemPlayer] = []
var _seq: Array[int] = []
var _phase := Phase.GAP
var _phase_t := 0.0
var _round := 0
var _pressed_flash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _watch_played := -1
var _amb_t := 0.0


func _configure() -> void:
	title = {"es": "Sigue la secuencia", "en": "Follow the sequence"}
	instructions = {"es": "Mira la secuencia de direcciones y repítela con la cruceta.",
		"en": "Watch the direction sequence and repeat it with the D-pad."}
	controls = [
		["dpad", {"es": "Repetir la secuencia", "en": "Repeat the sequence"}],
		["stick", {"es": "También vale", "en": "Works too"}],
	]
	duration = 90.0


func _setup() -> void:
	for p in players:
		var s := MemPlayer.new()
		s.player = p
		_states.append(s)


func _game_start() -> void:
	_next_round()


func _next_round() -> void:
	_round += 1
	_seq.clear()
	var steps := START_STEPS + _round - 1
	var last := -1
	for i in steps:
		var d := randi() % 4
		if d == last and randf() < 0.6:
			d = (d + 1 + randi() % 3) % 4
		_seq.append(d)
		last = d
	for s in _states:
		s.progress = 0
		s.done_round = false
	_pressed_flash.fill(0.0)
	_watch_played = -1
	_phase = Phase.WATCH
	_phase_t = 0.0


func _game_process(delta: float) -> void:
	_amb_t += delta
	for d in 4:
		_pressed_flash[d] = maxf(0.0, _pressed_flash[d] - delta)
	match _phase:
		Phase.WATCH:
			_tick_watch(delta)
		Phase.REPEAT:
			_tick_repeat(delta)
		Phase.GAP:
			_phase_t += delta
			if _phase_t >= GAP_SEC:
				_next_round()


func _tick_watch(delta: float) -> void:
	var idx := int(_phase_t / STEP_SEC)
	if idx != _watch_played and idx < _seq.size():
		_watch_played = idx
		Sfx.play("move")  # mismo sonido en todas: solo vale la vista
	_phase_t += delta
	if idx >= _seq.size():
		_phase = Phase.REPEAT
		_phase_t = REPEAT_PER_STEP * float(_seq.size())


func _tick_repeat(delta: float) -> void:
	for s in _states:
		if s.alive and not s.done_round:
			_try_input(s)
	# Estado tras las entradas de este frame.
	var alive_any := false
	var pending := false
	for s in _states:
		if s.alive:
			alive_any = true
			if not s.done_round:
				pending = true
	if not alive_any:
		finish()
		return
	if not pending:
		_phase = Phase.GAP
		_phase_t = 0.0
		Sfx.play("accept")
		return
	_phase_t -= delta
	if _phase_t <= 0.0:
		# Se acabó el tiempo: los que no hayan terminado quedan eliminados.
		for s in _states:
			if s.alive and not s.done_round:
				s.alive = false
				Sfx.play("back", randf_range(0.9, 1.05))
		var still := false
		for s in _states:
			if s.alive:
				still = true
		if not still:
			finish()
			return
		_phase = Phase.GAP
		_phase_t = 0.0


func _try_input(s: MemPlayer) -> void:
	var expected := _seq[s.progress]
	var pressed: Array[int] = []
	for d in 4:
		if s.player.just_pressed(DIRS[d]):
			pressed.append(d)
	if pressed.is_empty():
		return
	if expected in pressed:
		_pressed_flash[expected] = 0.22
		s.progress += 1
		Sfx.play("pop")
		if s.progress >= _seq.size():
			s.done_round = true
			add_score(s.player)
			Sfx.play("star")
	else:
		var wrong: int = pressed[0]
		_pressed_flash[wrong] = 0.22
		s.alive = false
		Sfx.play("back", 0.8)


# --- Dibujo ---

## Escenario fijo del teatrillo: pared, tablas, foco y telones.
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	DrawKit.arena_frame(ci, ARENA, STAGE_TOP, STAGE_BOTTOM)
	var floor_y := ARENA.end.y - 116.0
	# Suelo de tablas claras.
	DrawKit.clipped_polygon(ci, PackedVector2Array([
		Vector2(ARENA.position.x, floor_y), Vector2(ARENA.end.x, floor_y),
		ARENA.end, Vector2(ARENA.position.x, ARENA.end.y)]), clip, FLOOR)
	for i in 5:
		var ly := floor_y + 22.0 + i * 23.0
		ci.draw_line(Vector2(ARENA.position.x + 30, ly), Vector2(ARENA.end.x - 30, ly),
				Color(FLOOR_DARK, 0.7), 2.0, true)
	var px := ARENA.position.x + 96.0
	while px < ARENA.end.x - 40.0:
		ci.draw_line(Vector2(px, floor_y + 18), Vector2(px, ARENA.end.y - 8),
				Color(FLOOR_DARK, 0.45), 2.0, true)
		px += 152.0
	# Foco de luz suave bajo el panel de direcciones.
	DrawKit.ellipse(ci, Vector2(640, 408), Vector2(330, 220), SPOTLIGHT)
	DrawKit.ellipse(ci, Vector2(640, 408), Vector2(210, 150), Color(1.0, 0.99, 0.9, 0.22))
	# Telones laterales con pliegues.
	_draw_side_curtain(ci, clip, ARENA.position.x, floor_y)
	_draw_side_curtain(ci, clip, ARENA.end.x - 150.0, floor_y)
	# Guardamalleta superior ondulada, muy clara para que el texto de fase se lea.
	var val_h := 34.0
	DrawKit.clipped_polygon(ci, PackedVector2Array([
		ARENA.position, Vector2(ARENA.end.x, ARENA.position.y),
		Vector2(ARENA.end.x, ARENA.position.y + val_h),
		Vector2(ARENA.position.x, ARENA.position.y + val_h)]), clip, Color("f9e4ec"))
	var bx := ARENA.position.x + 52.0
	while bx < ARENA.end.x - 26.0:
		DrawKit.ellipse(ci, Vector2(bx, ARENA.position.y + val_h), Vector2(24, 10), CURTAIN_LIGHT)
		bx += 52.0
	ci.draw_line(Vector2(ARENA.position.x + 34, ARENA.position.y + 10),
			Vector2(ARENA.end.x - 34, ARENA.position.y + 10), Color("e8c46a"), 3.0, true)
	DrawKit.arena_border(ci, ARENA)


func _draw_side_curtain(ci: CanvasItem, clip: PackedVector2Array, x: float, floor_y: float) -> void:
	var w := 150.0
	DrawKit.clipped_polygon(ci, PackedVector2Array([
		Vector2(x, ARENA.position.y), Vector2(x + w, ARENA.position.y),
		Vector2(x + w, floor_y), Vector2(x, floor_y)]), clip, CURTAIN)
	for i in 4:
		var fx := x + 14.0 + i * 36.0
		DrawKit.clipped_polygon(ci, PackedVector2Array([
			Vector2(fx, ARENA.position.y), Vector2(fx + 15.0, ARENA.position.y),
			Vector2(fx + 15.0, floor_y), Vector2(fx, floor_y)]), clip,
			CURTAIN_DARK if i % 2 == 0 else CURTAIN_LIGHT)


## Solo lo que se mueve: motas de polvo en el foco, pétalos, textos y jugadores.
func _draw() -> void:
	# Motas doradas flotando despacio en el haz de luz.
	for i in 4:
		var mt := fmod(_amb_t * 0.3 + i * 0.27, 1.0)
		var mx := 640.0 + sin(_amb_t * 0.8 + i * 1.7) * (70.0 + i * 22.0)
		var my := 552.0 - mt * 200.0
		draw_circle(Vector2(mx, my), 3.0 + float(i % 2), Color(MOTE, 0.45 * sin(mt * PI)))
	var center := Vector2(640, 396)
	var lit := _lit_index()
	for d in 4:
		_draw_petal(center, d, lit == d, _pressed_flash[d] > 0.0)
	# Texto de fase y ronda.
	var phase_txt := ""
	var phase_col := WiiTheme.ACCENT_DARK
	if _phase == Phase.WATCH:
		phase_txt = loc({"es": "Mira...", "en": "Watch..."})
	elif _phase == Phase.REPEAT:
		phase_txt = loc({"es": "¡Repite!", "en": "Repeat!"})
	else:
		phase_txt = loc({"es": "¡Bien!", "en": "Nice!"})
		phase_col = WiiTheme.TEXT_SOFT
	draw_text_centered(phase_txt, Vector2(640, 126), 30, phase_col)
	var round_txt := loc({"es": "Ronda %d  ·  %d pasos", "en": "Round %d  ·  %d steps"}) % [_round, _seq.size()]
	draw_text_centered(round_txt, Vector2(640, 158), 20, WiiTheme.TEXT_SOFT, 600)
	_draw_players_row()


func _lit_index() -> int:
	if _phase == Phase.GAP:
		return -1
	if _seq.is_empty():
		return -1
	if _phase == Phase.WATCH:
		var idx := int(_phase_t / STEP_SEC)
		if idx >= _seq.size():
			return -1
		var frac := fmod(_phase_t, STEP_SEC) / STEP_SEC
		return _seq[idx] if frac < LIGHT_FRAC else -1
	# Repetir: se ilumina el pétalo que toca si alguien lo ha pulsado.
	for d in 4:
		if _pressed_flash[d] > 0.0:
			return d
	return -1


func _draw_petal(center: Vector2, d: int, is_lit: bool, flash: bool) -> void:
	var off: Vector2 = DIR_VECS[d] * PETAL_DIST
	var pos: Vector2 = center + off
	var base: Color = PETAL_COLORS[d]
	var active := is_lit or flash
	var col := base if active else base.lerp(Color.WHITE, 0.42)
	draw_circle(pos + Vector2(0, 8), PETAL_RADIUS + 4.0, WiiTheme.SHADOW)
	if active:
		# Encendido claro: halo y botón saturado, imposible confundirlo.
		draw_circle(pos, PETAL_RADIUS + 16.0, Color(base, 0.30))
		draw_circle(pos, PETAL_RADIUS + 5.0, Color(base, 0.5))
	draw_circle(pos, PETAL_RADIUS, col)
	draw_circle(pos + Vector2(0, PETAL_RADIUS * 0.18), PETAL_RADIUS * 0.78, col.darkened(0.06))
	draw_circle(pos + Vector2(-PETAL_RADIUS * 0.3, -PETAL_RADIUS * 0.34), PETAL_RADIUS * 0.34,
			Color(1, 1, 1, 0.42))
	draw_arc(pos, PETAL_RADIUS - 1.0, 0, TAU, 32, Color(1, 1, 1, 0.6), 3.0, true)
	# Triángulo que apunta hacia fuera (sin flechas Unicode), en tono oscuro para
	# que se lea tanto apagado como encendido.
	var dir: Vector2 = DIR_VECS[d]
	var tip := pos + dir * PETAL_RADIUS * 0.5
	var side := dir.orthogonal() * PETAL_RADIUS * 0.22
	var pts := PackedVector2Array([tip, pos + dir * PETAL_RADIUS * 0.08 + side,
			pos + dir * PETAL_RADIUS * 0.08 - side])
	draw_colored_polygon(pts, Color(base.darkened(0.32), 0.92))


func _draw_players_row() -> void:
	var n := maxi(1, _states.size())
	var slot_w := ARENA.size.x / float(n)
	var spacing := 16.0
	if not _seq.is_empty():
		spacing = minf(16.0, 210.0 / float(_seq.size()))
	var y := ARENA.end.y - 46.0
	for i in _states.size():
		var s := _states[i]
		var p := s.player
		var cx := ARENA.position.x + slot_w * (float(i) + 0.5)
		var dots_w := float(_seq.size()) * spacing
		var total := 40.0 + 10.0 + dots_w
		var x := cx - total * 0.5
		var col := p.color
		if not s.alive:
			col = Color("b8c0c8")
		draw_circle(Vector2(x + 20, y + 5), 20, WiiTheme.SHADOW)
		draw_circle(Vector2(x + 20, y), 20, col)
		draw_circle(Vector2(x + 13, y - 6), 7, Color(1, 1, 1, 0.4))
		draw_text_centered(str(p.index + 1), Vector2(x + 20, y), 18, Color.WHITE)
		# Puntos de progreso.
		for k in _seq.size():
			var dot := Vector2(x + 50 + spacing * (float(k) + 0.5), y)
			var done := s.progress > k
			var dc := col.darkened(0.1) if done else Color("dde3e8")
			if not s.alive:
				dc = Color("d4d9de") if not done else Color("b8c0c8")
			draw_circle(dot, minf(5.0, spacing * 0.32), dc)
		if s.done_round:
			draw_arc(Vector2(x + 20, y), 27, 0, TAU, 24, Color("ffd34d"), 4.0, true)
		if not s.alive:
			var c := Vector2(x + 20, y)
			draw_line(c + Vector2(-11, -11), c + Vector2(11, 11), Color("e25555"), 4.0, true)
			draw_line(c + Vector2(11, -11), c + Vector2(-11, 11), Color("e25555"), 4.0, true)

extends MinigameBase
## "Cuenta ovejas": primero cruzan ovejas (y algún lobo que no se cuenta); luego
## cada jugador marca cuántas ha visto y confirma con A. Gana el más cercano.

const ROUNDS := 2
const COUNT_SEC := 15.0
const ANSWER_SEC := 10.0
const REVEAL_SEC := 4.0
const ANSWER_START := 10
const ANSWER_MAX := 99
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.09

enum Phase { COUNT, ANSWER, REVEAL }


class Critter:
	var kind := 0            # 0 oveja, 1 lobo
	var spawn_t := 0.0
	var start_x := 0.0
	var x := 0.0
	var y := 0.0
	var speed := 0.0
	var dir := 1
	var size := 1.0
	var wobble := 0.0


var _phase := Phase.COUNT
var _phase_t := 0.0
var _round := 0
var _critters: Array[Critter] = []
var _real_count := 0
var _answers: Array[int] = []
var _confirmed: Array[bool] = []
var _up_t: Array[float] = []
var _down_t: Array[float] = []
var _closest: Array[int] = []


func _configure() -> void:
	title = {"es": "Cuenta ovejas", "en": "Count the sheep"}
	instructions = {"es": "Cuenta las ovejas que cruzan (los lobos no cuentan) y marca el total.",
		"en": "Count the sheep that cross (wolves don't count) and enter the total."}
	controls = [
		["dpad", {"es": "Subir o bajar el número", "en": "Raise or lower the number"}],
		[Pad.A, {"es": "Confirmar", "en": "Confirm"}],
	]
	duration = 70.0
	lower_is_better = true


func _game_start() -> void:
	_round = 0
	_start_round()


func _start_round() -> void:
	_phase = Phase.COUNT
	_phase_t = 0.0
	_critters.clear()
	_answers.clear()
	_confirmed.clear()
	_up_t.clear()
	_down_t.clear()
	_closest.clear()
	_build_round()


func _build_round() -> void:
	var n_sheep := randi_range(12, 25)
	var n_wolves := 3 if _round == 0 else 7
	var speed_lo := 170.0 if _round == 0 else 235.0
	var speed_hi := 270.0 if _round == 0 else 350.0
	var top := ARENA.position.y + 96.0
	var bottom := ARENA.end.y - 76.0
	for i in n_sheep:
		var e := Critter.new()
		e.kind = 0
		e.spawn_t = randf_range(0.2, 6.0)
		e.y = randf_range(top, bottom)
		e.dir = 1 if randf() < 0.5 else -1
		e.start_x = -70.0 if e.dir == 1 else 1350.0
		e.speed = randf_range(speed_lo, speed_hi)
		e.size = randf_range(0.85, 1.15)
		e.wobble = randf() * TAU
		_critters.append(e)
	# Algunas ovejas van en grupo (misma altura y salida, velocidad distinta).
	var groups := 0
	var idx := 2
	while idx < _critters.size() and groups < 3:
		if randf() < 0.55:
			var e2: Critter = _critters[idx]
			var prev: Critter = _critters[idx - 1]
			e2.spawn_t = prev.spawn_t + randf_range(-0.1, 0.3)
			e2.y = clampf(prev.y + randf_range(-30.0, 30.0), top, bottom)
			e2.dir = prev.dir
			e2.start_x = -70.0 if e2.dir == 1 else 1350.0
			e2.speed = clampf(prev.speed + randf_range(-35.0, 35.0), speed_lo, speed_hi)
			e2.wobble = prev.wobble + randf_range(-0.4, 0.4)
			groups += 1
			idx += 2
		else:
			idx += 1
	_real_count = n_sheep
	# Lobos: más rápidos y más numerosos en la segunda ronda.
	for i in n_wolves:
		var w := Critter.new()
		w.kind = 1
		w.spawn_t = randf_range(0.4, 6.5)
		w.y = randf_range(top, bottom)
		w.dir = 1 if randf() < 0.5 else -1
		w.start_x = -70.0 if w.dir == 1 else 1350.0
		w.speed = randf_range(speed_lo + 50.0, speed_hi + 70.0)
		w.size = randf_range(0.95, 1.2)
		w.wobble = randf() * TAU
		_critters.append(w)


func _game_process(delta: float) -> void:
	match _phase:
		Phase.COUNT:
			_tick_count(delta)
		Phase.ANSWER:
			_tick_answer(delta)
		Phase.REVEAL:
			_tick_reveal(delta)


func _tick_count(delta: float) -> void:
	_phase_t += delta
	for e in _critters:
		var age := _phase_t - e.spawn_t
		if age <= 0.0:
			continue
		e.x = e.start_x + float(e.dir) * e.speed * age
	if _phase_t >= COUNT_SEC:
		_start_answer()


func _start_answer() -> void:
	_phase = Phase.ANSWER
	_phase_t = 0.0
	_critters.clear()
	for p in players:
		_answers.append(ANSWER_START)
		_confirmed.append(false)
		_up_t.append(0.0)
		_down_t.append(0.0)
	Sfx.play("accept")


func _tick_answer(delta: float) -> void:
	_phase_t += delta
	for i in players.size():
		if _confirmed[i]:
			continue
		var p := players[i]
		if p.just_pressed(Pad.UP):
			_change(i, 1)
			_up_t[i] = REPEAT_DELAY
		elif p.is_pressed(Pad.UP):
			_up_t[i] = maxf(0.0, _up_t[i] - delta)
			if _up_t[i] <= 0.0:
				_change(i, 1)
				_up_t[i] = REPEAT_RATE
		else:
			_up_t[i] = 0.0
		if p.just_pressed(Pad.DOWN):
			_change(i, -1)
			_down_t[i] = REPEAT_DELAY
		elif p.is_pressed(Pad.DOWN):
			_down_t[i] = maxf(0.0, _down_t[i] - delta)
			if _down_t[i] <= 0.0:
				_change(i, -1)
				_down_t[i] = REPEAT_RATE
		else:
			_down_t[i] = 0.0
		if p.just_pressed(Pad.A):
			_confirmed[i] = true
			Sfx.play("accept")
	if _phase_t >= ANSWER_SEC:
		_start_reveal()


func _change(i: int, amount: int) -> void:
	_answers[i] = clampi(_answers[i] + amount, 0, ANSWER_MAX)
	Sfx.play("move", 1.18 if amount > 0 else 0.88)


func _start_reveal() -> void:
	_phase = Phase.REVEAL
	_phase_t = 0.0
	_closest.clear()
	var best := 999999
	for i in players.size():
		var err := absi(_answers[i] - _real_count)
		add_score(players[i], err)
		if err < best:
			best = err
			_closest.clear()
			_closest.append(i)
		elif err == best:
			_closest.append(i)
	Sfx.play("star")


func _tick_reveal(delta: float) -> void:
	_phase_t += delta
	if _phase_t < REVEAL_SEC:
		return
	if _round < ROUNDS - 1:
		_round += 1
		_start_round()
	else:
		finish()


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	match _phase:
		Phase.COUNT:
			_draw_count()
		Phase.ANSWER:
			_draw_answer(false)
		Phase.REVEAL:
			_draw_answer(true)


func _draw_count() -> void:
	var top := ARENA.position.y + 96.0
	var bottom := ARENA.end.y - 76.0
	for e in _critters:
		var age := _phase_t - e.spawn_t
		if age <= 0.0:
			continue
		if e.x < -110.0 or e.x > 1390.0:
			continue
		var y := clampf(e.y + sin((_phase_t + e.wobble) * 3.0) * 5.0 * e.size, top - 20.0, bottom + 20.0)
		if e.kind == 0:
			_draw_sheep(Vector2(e.x, y), e.size, e.dir)
		else:
			_draw_wolf(Vector2(e.x, y), e.size, e.dir)
	# Cabecera de la fase.
	draw_style_box(WiiTheme.panel_style(24), Rect2(430, 112, 420, 54))
	draw_text_centered(loc({"es": "Cuenta las ovejas", "en": "Count the sheep"}),
			Vector2(640, 139), 26, WiiTheme.TEXT)
	var secs := int(ceil(COUNT_SEC - _phase_t))
	draw_text_centered(str(secs), Vector2(1195, 139), 26, WiiTheme.ACCENT_DARK)
	draw_text_centered(loc({"es": "Ronda %d/2", "en": "Round %d/2"}) % (_round + 1),
			Vector2(100, 139), 20, WiiTheme.TEXT_SOFT)


func _draw_answer(reveal: bool) -> void:
	if reveal:
		draw_text_centered(loc({"es": "Había %d ovejas", "en": "There were %d sheep"}) % _real_count,
				Vector2(640, 178), 28, WiiTheme.TEXT_SOFT)
		draw_text_centered(str(_real_count), Vector2(640, 252), 96, WiiTheme.ACCENT_DARK)
	else:
		draw_text_centered(loc({"es": "¿Cuántas ovejas has contado?", "en": "How many sheep did you count?"}),
				Vector2(640, 168), 34, WiiTheme.TEXT)
		var secs := int(ceil(ANSWER_SEC - _phase_t))
		draw_text_centered(str(secs), Vector2(1195, 139), 26, WiiTheme.ACCENT_DARK)
		draw_text_centered(loc({"es": "Ronda %d/2", "en": "Round %d/2"}) % (_round + 1),
				Vector2(100, 139), 20, WiiTheme.TEXT_SOFT)
	var n := maxi(1, players.size())
	for i in players.size():
		_draw_answer_panel(i, _panel_rect(i, n, reveal), reveal, n)


func _panel_rect(i: int, n: int, reveal: bool) -> Rect2:
	var yo := 50.0 if reveal else 0.0
	if n <= 1:
		return Rect2(400, 330 + yo, 480, 240)
	if n == 2:
		return Rect2(140 + 520.0 * i, 340 + yo, 460, 230)
	var col := i % 2
	var row := int(i / 2.0)
	return Rect2(155 + 500.0 * col, 300 + yo + 175.0 * row, 470, 160)


func _draw_answer_panel(i: int, rect: Rect2, reveal: bool, n: int) -> void:
	var p := players[i]
	var confirmed := _confirmed[i]
	var bg := Color.WHITE
	if confirmed and not reveal:
		bg = p.color.lerp(Color.WHITE, 0.88)
	var st := WiiTheme.panel_style(28, p.color, bg)
	st.set_border_width_all(4)
	draw_style_box(st, rect)
	# Bola del jugador con su número.
	var bc := rect.position + Vector2(46, 44)
	draw_circle(bc + Vector2(0, 3), 22, WiiTheme.SHADOW)
	draw_circle(bc, 22, p.color)
	draw_circle(bc + Vector2(-6, -8), 7, Color(1, 1, 1, 0.4))
	draw_text_centered(str(p.index + 1), bc, 18, Color.WHITE)
	# Respuesta grande.
	var big := 80 if n <= 2 else 62
	var nc := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.56)
	draw_text_centered(str(_answers[i]), nc, big, p.color.darkened(0.15))
	# Estado o error.
	var status := ""
	var scol := WiiTheme.TEXT_SOFT
	if reveal:
		var err := absi(_answers[i] - _real_count)
		if i in _closest:
			status = loc({"es": "Más cerca · Error: %d", "en": "Closest · Off by %d"}) % err
			scol = Color("c99400")
		else:
			status = loc({"es": "Error: %d", "en": "Off by %d"}) % err
			scol = WiiTheme.TEXT
	else:
		status = loc({"es": "Listo", "en": "Ready"}) if confirmed \
				else loc({"es": "A: confirmar", "en": "A: confirm"})
		if confirmed:
			scol = p.color.darkened(0.1)
	draw_text_centered(status, Vector2(rect.get_center().x, rect.end.y - 20), 20, scol)
	if reveal and i in _closest:
		var focus := StyleBoxFlat.new()
		focus.bg_color = Color(0, 0, 0, 0)
		focus.draw_center = false
		focus.border_color = Color("ffd34d")
		focus.set_border_width_all(6)
		focus.set_corner_radius_all(34)
		focus.set_expand_margin_all(5)
		focus.anti_aliasing = true
		draw_style_box(focus, rect)


func _draw_sheep(pos: Vector2, s: float, dir: int) -> void:
	var outline := Color("b7c1cb")
	var wool := Color("eef2f6")
	# Patas.
	draw_line(pos + Vector2(-10 * s, 16 * s), pos + Vector2(-10 * s, 30 * s), Color("c2cad2"), 4.0 * s)
	draw_line(pos + Vector2(10 * s, 16 * s), pos + Vector2(10 * s, 30 * s), Color("c2cad2"), 4.0 * s)
	# Nube de lana: tres bolas con contorno.
	for o in [Vector2(-15, 2), Vector2(12, -4), Vector2(0, -15)]:
		draw_circle(pos + o * s, 24.0 * s, outline)
	for o in [Vector2(-15, 2), Vector2(12, -4), Vector2(0, -15)]:
		draw_circle(pos + o * s, 21.0 * s, wool)
	draw_circle(pos + Vector2(-19, -12) * s, 8.0 * s, Color(1, 1, 1, 0.85))
	# Cabeza gris en el lado hacia el que camina.
	var head := pos + Vector2(dir * 30.0, 4.0) * s
	draw_circle(head, 13.0 * s, Color("b9c3cd"))
	draw_circle(head + Vector2(-5, -9) * s, 5.0 * s, Color("a6b1bc"))
	draw_circle(head + Vector2(6, -9) * s, 5.0 * s, Color("a6b1bc"))
	draw_circle(head + Vector2(dir * 4.0, -1.0) * s, 2.6 * s, WiiTheme.TEXT)
	# Patitas de la cabeza (orejas de color claro).
	draw_circle(head + Vector2(dir * 3.0, 8.0) * s, 3.0 * s, Color("e7ebf0"))


func _draw_wolf(pos: Vector2, s: float, dir: int) -> void:
	var body := Color("6f7985")
	var dark := Color("5a636e")
	# Cuerpo puntiagudo.
	var pts := PackedVector2Array()
	for i in 8:
		var r := (26.0 if i % 2 == 0 else 16.0) * s
		pts.append(pos + Vector2.UP.rotated(i * TAU / 8.0 + 0.2) * r)
	draw_colored_polygon(pts, body)
	# Hocico hacia el lado de avance.
	var snout := PackedVector2Array([
		pos + Vector2(dir * 14.0, -9.0) * s,
		pos + Vector2(dir * 38.0, 1.0) * s,
		pos + Vector2(dir * 14.0, 10.0) * s,
	])
	draw_colored_polygon(snout, dark)
	# Orejas.
	var ear1 := PackedVector2Array([
		pos + Vector2(-8, -22) * s, pos + Vector2(-14, -38) * s, pos + Vector2(2, -28) * s,
	])
	var ear2 := PackedVector2Array([
		pos + Vector2(6, -24) * s, pos + Vector2(12, -40) * s, pos + Vector2(18, -26) * s,
	])
	draw_colored_polygon(ear1, dark)
	draw_colored_polygon(ear2, dark)
	# Ojo y cola.
	draw_circle(pos + Vector2(dir * 12.0, -8.0) * s, 3.2 * s, Color("e25555"))
	draw_line(pos + Vector2(-dir * 22.0, 2.0) * s, pos + Vector2(-dir * 40.0, -12.0) * s,
			dark, 6.0 * s)

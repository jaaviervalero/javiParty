extends MinigameBase
## "Cuenta ovejas": primero cruzan ovejas (y algún lobo que no se cuenta); luego
## cada jugador marca cuántas ha visto y confirma con A. Gana el más cercano.
##
## Mecánica intacta: 2 rondas, 15 s de conteo, 10 s de respuesta y 4 s de revelación.
## Todo el escenario y los personajes se dibujan con primitivas en _draw (sin
## texturas, shaders ni nodos por entidad).

const ROUNDS := 2
const COUNT_SEC := 15.0
const ANSWER_SEC := 10.0
const REVEAL_SEC := 4.0
const ANSWER_START := 10
const ANSWER_MAX := 99
const REPEAT_DELAY := 0.35
const REPEAT_RATE := 0.09

# --- Escenario ---
const SCENERY_INSET := 10.0
const SKY_BANDS := 12
const SKY_TOP := Color("a9dcf2")
const SKY_BOTTOM := Color("eaf7ef")
const SUN_GLOW := Color(1.0, 0.93, 0.68)
const SUN_COLOR := Color("ffe9a6")
const CLOUD_COLOR := Color(1, 1, 1, 0.86)
const HILL_FAR := Color("c6e4b5")
const HILL_MID := Color("a7d694")
const HILL_NEAR := Color("8acb7c")
const GRASS_TUFT := Color("66ab5c")
const FLOWER_COLORS := [Color("ffffff"), Color("ffe08a"), Color("f6b7d0"), Color("cbb8ef")]
const CLOUDS := [
	[Vector2(80.0, 76.0), 1.0, 8.0],
	[Vector2(470.0, 128.0), 0.78, 5.0],
	[Vector2(820.0, 58.0), 1.12, 11.0],
	[Vector2(1090.0, 122.0), 0.7, 4.0],
]

# --- Valla y salto ---
const GATE_X := 640.0
const FENCE_Y := 596.0
const FENCE_HEIGHT := 62.0
const FENCE_GAP := 150.0
const FENCE_WOOD := Color("b98452")
const FENCE_WOOD_DARK := Color("95653a")
const FENCE_WOOD_LIGHT := Color("d2a273")
const HOP_HALF_W := 92.0
const HOP_HEIGHT := 30.0

# --- Personajes ---
const WOOL := Color("faf9f4")
const WOOL_SHADE := Color("e1e6dc")
const SHEEP_HEAD := Color("6f7c88")
const SHEEP_DARK := Color("58646f")
const SHEEP_MUZZLE := Color("9fabb4")
const WOLF_BODY := Color("7f95aa")
const WOLF_DARK := Color("61798e")
const WOLF_LIGHT := Color("adc0cf")
const WOLF_EAR := Color("c9a9b8")
const EYE_DARK := Color("2f3942")

# --- Animación de los paneles ---
const CONFIRM_POP := 0.32
const REVEAL_POP := 0.45
const PANEL_APPEAR := 0.22

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


var _phase: int = Phase.COUNT
var _phase_t := 0.0
var _round := 0
var _critters: Array = []
var _real_count := 0
var _answers: Array = []
var _confirmed: Array = []
var _up_t: Array = []
var _down_t: Array = []
var _closest: Array = []
var _confirm_t: Array = []

var _time := 0.0
# Rebaño en una capa recortada al prado: así entran y salen poco a poco por los
# lados en vez de aparecer de golpe. _cv/_cv_origin: dónde dibujan ovejas y lobos.
var _herd: Control
var _cv = self
var _cv_origin := Vector2.ZERO
var _tufts: Array = []
var _flowers: Array = []  # [[Vector2, índice de color]]


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


func _setup() -> void:
	var clip_rect := ARENA.grow(-SCENERY_INSET)
	_herd = Control.new()
	_herd.rect_position = clip_rect.position
	_herd.rect_size = clip_rect.size
	_herd.rect_clip_content = true
	_herd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_herd.connect("draw", self, "_draw_herd")
	add_child(_herd)
	# Matitas y flores del prado, fijas durante toda la partida.
	var inner := ARENA.grow(-SCENERY_INSET)
	for i in 26:
		_tufts.append(Vector2(rand_range(inner.position.x + 18.0, inner.end.x - 18.0),
				rand_range(inner.position.y + 424.0, inner.end.y - 12.0)))
	for i in 18:
		_flowers.append([Vector2(rand_range(inner.position.x + 26.0, inner.end.x - 26.0),
				rand_range(inner.position.y + 434.0, inner.end.y - 24.0)),
				randi() % FLOWER_COLORS.size()])


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
	_confirm_t.clear()
	_build_round()


func _build_round() -> void:
	var n_sheep := randi() % 14 + 12
	var n_wolves := 3 if _round == 0 else 7
	var speed_lo := 170.0 if _round == 0 else 235.0
	var speed_hi := 270.0 if _round == 0 else 350.0
	# Solo visual: el rebaño cruza sobre el prado, nunca por el cielo.
	var top := ARENA.position.y + 330.0
	var bottom := ARENA.end.y - 76.0
	for i in n_sheep:
		var e := Critter.new()
		e.kind = 0
		e.spawn_t = rand_range(0.2, 6.0)
		e.y = rand_range(top, bottom)
		e.dir = 1 if randf() < 0.5 else -1
		e.start_x = -70.0 if e.dir == 1 else 1350.0
		e.speed = rand_range(speed_lo, speed_hi)
		e.size = rand_range(0.8, 1.2)
		e.wobble = randf() * TAU
		_critters.append(e)
	# Algunas ovejas van en grupo (misma altura y salida, velocidad distinta).
	var groups := 0
	var idx := 2
	while idx < _critters.size() and groups < 3:
		if randf() < 0.55:
			var e2: Critter = _critters[idx]
			var prev: Critter = _critters[idx - 1]
			e2.spawn_t = prev.spawn_t + rand_range(-0.1, 0.3)
			e2.y = clamp(prev.y + rand_range(-30.0, 30.0), top, bottom)
			e2.dir = prev.dir
			e2.start_x = -70.0 if e2.dir == 1 else 1350.0
			e2.speed = clamp(prev.speed + rand_range(-35.0, 35.0), speed_lo, speed_hi)
			e2.wobble = prev.wobble + rand_range(-0.4, 0.4)
			groups += 1
			idx += 2
		else:
			idx += 1
	_real_count = n_sheep
	# Lobos: más rápidos y más numerosos en la segunda ronda.
	for i in n_wolves:
		var w := Critter.new()
		w.kind = 1
		w.spawn_t = rand_range(0.4, 6.5)
		w.y = rand_range(top, bottom)
		w.dir = 1 if randf() < 0.5 else -1
		w.start_x = -70.0 if w.dir == 1 else 1350.0
		w.speed = rand_range(speed_lo + 50.0, speed_hi + 70.0)
		w.size = rand_range(0.95, 1.2)
		w.wobble = randf() * TAU
		_critters.append(w)


func _game_process(delta: float) -> void:
	_time += delta
	_herd.update()
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
		var age = _phase_t - e.spawn_t
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
		_confirm_t.append(0.0)
	Sfx.play("accept")


func _tick_answer(delta: float) -> void:
	_phase_t += delta
	for i in players.size():
		_confirm_t[i] = max(0.0, _confirm_t[i] - delta)
		if _confirmed[i]:
			continue
		var p = players[i]
		if p.just_pressed(Pad.UP):
			_change(i, 1)
			_up_t[i] = REPEAT_DELAY
		elif p.is_pressed(Pad.UP):
			_up_t[i] = max(0.0, _up_t[i] - delta)
			if _up_t[i] <= 0.0:
				_change(i, 1)
				_up_t[i] = REPEAT_RATE
		else:
			_up_t[i] = 0.0
		if p.just_pressed(Pad.DOWN):
			_change(i, -1)
			_down_t[i] = REPEAT_DELAY
		elif p.is_pressed(Pad.DOWN):
			_down_t[i] = max(0.0, _down_t[i] - delta)
			if _down_t[i] <= 0.0:
				_change(i, -1)
				_down_t[i] = REPEAT_RATE
		else:
			_down_t[i] = 0.0
		if p.just_pressed(Pad.A):
			_confirmed[i] = true
			_confirm_t[i] = CONFIRM_POP
			Sfx.play("accept")
	if _phase_t >= ANSWER_SEC:
		_start_reveal()


func _change(i: int, amount: int) -> void:
	_answers[i] = clamp(_answers[i] + amount, 0, ANSWER_MAX)
	Sfx.play("move", 1.18 if amount > 0 else 0.88)


func _start_reveal() -> void:
	_phase = Phase.REVEAL
	_phase_t = 0.0
	_closest.clear()
	var best := 999999
	for i in players.size():
		var err := abs(_answers[i] - _real_count)
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


# =====================================================================
# Dibujo general
# =====================================================================

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	_draw_sky()
	_draw_hills()
	_draw_meadow_details()
	if _phase == Phase.COUNT:
		_draw_count()
	else:
		_draw_fence()
		# Velo claro para que los paneles se lean bien sobre el prado.
		draw_rect(ARENA.grow(-SCENERY_INSET), Color(0.97, 0.99, 1.0, 0.62))
		_draw_answer(_phase == Phase.REVEAL)


func _draw_sky() -> void:
	var inner := ARENA.grow(-SCENERY_INSET)
	var horizon := inner.position.y + 430.0
	# Franjas horizontales: degradado suave sin shaders.
	for i in SKY_BANDS:
		var t0 := float(i) / float(SKY_BANDS)
		var t1 := float(i + 1) / float(SKY_BANDS)
		var y0 = lerp(inner.position.y, horizon, t0)
		var y1 = lerp(inner.position.y, horizon, t1) + 1.0
		draw_rect(Rect2(inner.position.x, y0, inner.size.x, y1 - y0), SKY_TOP.linear_interpolate(SKY_BOTTOM, t0))
	# Sol con halo, meciéndose muy despacio.
	var sun := Vector2(inner.end.x - 186.0,
			inner.position.y + 118.0 + sin(_time * 0.5) * 3.0)
	draw_circle(sun, 86.0, Color(SUN_GLOW, 0.10))
	draw_circle(sun, 66.0, Color(SUN_GLOW, 0.16))
	draw_circle(sun, 46.0, SUN_COLOR)
	draw_circle(sun + Vector2(-13, -13), 19.0, Color(1, 1, 1, 0.35))
	# Nubes lentas, cada una a su velocidad (paralaje).
	var span := inner.size.x + 320.0
	for c in CLOUDS:
		var base: Vector2 = c[0]
		var x := inner.position.x - 160.0 + fposmod(base.x + _time * float(c[2]), span)
		var y := inner.position.y + base.y + sin(_time * 0.6 + base.x * 0.01) * 4.0
		# Se desvanecen al llegar a los bordes para no salirse del marco.
		var half := 55.0 * float(c[1])
		var edge := min(x - half - inner.position.x, inner.end.x - half - x)
		var alpha := clamp(edge / 80.0, 0.0, 1.0)
		if alpha > 0.0:
			_draw_cloud(Vector2(x, y), float(c[1]), alpha)


func _draw_cloud(c: Vector2, s: float, alpha := 1.0) -> void:
	var col := Color(CLOUD_COLOR, CLOUD_COLOR.a * alpha)
	draw_circle(c + Vector2(0, 2) * s, 25.0 * s, col)
	draw_circle(c + Vector2(-30, 8) * s, 19.0 * s, col)
	draw_circle(c + Vector2(30, 7) * s, 21.0 * s, col)
	draw_circle(c + Vector2(-11, 14) * s, 16.0 * s, col)
	draw_circle(c + Vector2(16, 14) * s, 15.0 * s, col)


func _draw_hills() -> void:
	var inner := ARENA.grow(-SCENERY_INSET)
	_draw_hill(inner, inner.position.y + 280.0, 24.0, 0.0062, _time * 0.12, HILL_FAR)
	_draw_hill(inner, inner.position.y + 330.0, 30.0, 0.0085, _time * 0.22 + 1.4, HILL_MID)
	_draw_hill(inner, inner.position.y + 390.0, 26.0, 0.0110, _time * 0.34 + 3.1, HILL_NEAR)


func _draw_hill(inner: Rect2, base_y: float, amp: float, freq: float, phase: float,
		color: Color) -> void:
	var pts := PoolVector2Array()
	var steps := 26
	for k in steps + 1:
		var x := inner.position.x + inner.size.x * float(k) / float(steps)
		var d := x - inner.position.x
		var y := base_y + sin(d * freq + phase) * amp + sin(d * freq * 2.4 + phase * 1.7) * amp * 0.35
		pts.append(Vector2(x, y))
	pts.append(Vector2(inner.end.x, inner.end.y))
	pts.append(Vector2(inner.position.x, inner.end.y))
	draw_colored_polygon(pts, color)


func _draw_meadow_details() -> void:
	for t in _tufts:
		var sway := sin(_time * 1.2 + t.x * 0.02) * 2.0
		draw_line(t, t + Vector2(-4 + sway, -10), GRASS_TUFT, 3.0)
		draw_line(t, t + Vector2(1 + sway, -14), GRASS_TUFT, 3.0)
		draw_line(t, t + Vector2(5 + sway, -9), GRASS_TUFT, 3.0)
	for f in _flowers:
		var pos: Vector2 = f[0]
		var col: Color = FLOWER_COLORS[int(f[1])]
		var sway := sin(_time * 1.4 + pos.x * 0.03) * 1.5
		var head := pos + Vector2(sway, -13.0)
		draw_line(pos, head, GRASS_TUFT, 2.0)
		for k in 4:
			var a := TAU * float(k) / 4.0 + 0.4
			draw_circle(head + Vector2(cos(a), sin(a)) * 5.0, 3.6, col)
		draw_circle(head, 2.6, Color("ffcf4d"))


# =====================================================================
# Fase de conteo
# =====================================================================

func _draw_count() -> void:
	_draw_fence()
	_draw_count_header()


## Ovejas y lobos, dibujados en la capa recortada (encima de la valla).
func _draw_herd() -> void:
	if _phase != Phase.COUNT:
		return
	var top := ARENA.position.y + 330.0
	var bottom := ARENA.end.y - 76.0
	var list: Array = []
	for e in _critters:
		if _phase_t - e.spawn_t <= 0.0:
			continue
		var y := clamp(e.y + sin((_time + e.wobble) * 3.0) * 5.0 * e.size,
				top - 20.0, bottom + 20.0)
		list.append([y, e])
	list.sort_custom(self, "_cmp_critter_y")
	_cv = _herd
	_cv_origin = _herd.rect_position
	_herd.draw_set_transform(-_cv_origin, 0.0, Vector2.ONE)
	for item in list:
		_draw_critter(item[1], item[0])
	_cv = self
	_cv_origin = Vector2.ZERO


## Orden por altura para que los que están más abajo se dibujen encima.
func _cmp_critter_y(a, b) -> bool:
	return a[0] < b[0]


func _draw_count_header() -> void:
	_panel(Rect2(410, 112, 460, 54), 27, WiiTheme.ACCENT, Color(1, 1, 1, 0.96), 3)
	draw_text_centered(loc({"es": "Cuenta las ovejas", "en": "Count the sheep"}),
			Vector2(640, 139), 28, WiiTheme.TEXT)
	_draw_round_pill()
	var frac := clamp(1.0 - _phase_t / COUNT_SEC, 0.0, 1.0)
	_draw_timer(Vector2(1186, 139), int(ceil(COUNT_SEC - _phase_t)), frac)


func _draw_critter(e: Critter, y: float) -> void:
	var base := Vector2(e.x, y)
	# Salto al pasar por la puerta de la valla.
	var hop := 0.0
	var d := abs(e.x - GATE_X)
	if d < HOP_HALF_W:
		hop = sin((1.0 - d / HOP_HALF_W) * PI) * HOP_HEIGHT * e.size
	var gait := _time * 9.0 + e.wobble * 2.0
	if e.kind == 0:
		_draw_sheep(base, e.size, e.dir, hop, gait)
	else:
		_draw_wolf(base, e.size, e.dir, hop, gait)


func _draw_fence() -> void:
	var inner := ARENA.grow(-SCENERY_INSET)
	var left := inner.position.x + 6.0
	var right := inner.end.x - 6.0
	var gap_l := GATE_X - FENCE_GAP * 0.5
	var gap_r := GATE_X + FENCE_GAP * 0.5
	var top := FENCE_Y - FENCE_HEIGHT
	# Sombra al pie de la valla.
	draw_rect(Rect2(left, FENCE_Y + 2.0, right - left, 9.0), Color(0.22, 0.38, 0.18, 0.10))
	# Travesaños de madera.
	for seg in [[left, gap_l], [gap_r, right]]:
		var x0: float = seg[0]
		var x1: float = seg[1]
		for hy in [top + 16.0, top + 40.0]:
			draw_rect(Rect2(x0, hy, x1 - x0, 11.0), FENCE_WOOD)
			draw_rect(Rect2(x0, hy, x1 - x0, 4.0), FENCE_WOOD_LIGHT)
	# Postes.
	var x := left
	while x <= right:
		if x < gap_l - 4.0 or x > gap_r + 4.0:
			_draw_fence_post(Vector2(x, FENCE_Y), top - 4.0)
		x += 118.0
	# Postes de la puerta, algo más altos y con la barra baja que saltan.
	_draw_fence_post(Vector2(gap_l, FENCE_Y), top - 12.0)
	_draw_fence_post(Vector2(gap_r, FENCE_Y), top - 12.0)
	draw_rect(Rect2(gap_l, FENCE_Y - 18.0, gap_r - gap_l, 9.0), FENCE_WOOD_DARK)
	draw_rect(Rect2(gap_l, FENCE_Y - 18.0, gap_r - gap_l, 3.0), FENCE_WOOD_LIGHT)


func _draw_fence_post(base: Vector2, top_y: float) -> void:
	var h := base.y - top_y + 4.0
	draw_rect(Rect2(base.x - 7.0, top_y, 14.0, h), FENCE_WOOD)
	draw_rect(Rect2(base.x - 7.0, top_y, 5.0, h), FENCE_WOOD_LIGHT)
	draw_circle(Vector2(base.x, top_y), 7.0, FENCE_WOOD)


# =====================================================================
# Fase de respuesta y revelación
# =====================================================================

func _draw_answer(reveal: bool) -> void:
	if reveal:
		_draw_reveal_header()
	else:
		_draw_answer_header()
	var n := max(1, players.size())
	var app := clamp(_phase_t / PANEL_APPEAR, 0.0, 1.0)
	var grow := 0.94 + 0.06 * app
	for i in players.size():
		_draw_answer_panel(i, _scale_rect(_panel_rect(i, n, reveal), grow), reveal, n)


func _draw_answer_header() -> void:
	_draw_round_pill()
	_panel(Rect2(360, 112, 560, 58), 29, WiiTheme.ACCENT, Color(1, 1, 1, 0.96), 3)
	draw_text_centered(loc({"es": "¿Cuántas ovejas has contado?", "en": "How many sheep did you count?"}),
			Vector2(640, 141), 30, WiiTheme.TEXT)
	var frac := clamp(1.0 - _phase_t / ANSWER_SEC, 0.0, 1.0)
	_draw_timer(Vector2(1186, 141), int(ceil(ANSWER_SEC - _phase_t)), frac)


func _draw_reveal_header() -> void:
	_draw_round_pill()
	_panel(Rect2(430, 112, 420, 54), 27, WiiTheme.ACCENT, Color(1, 1, 1, 0.96), 3)
	draw_text_centered(loc({"es": "Había %d ovejas", "en": "There were %d sheep"}) % _real_count,
			Vector2(640, 139), 26, WiiTheme.TEXT_SOFT)
	# Número real con un pequeño rebote al aparecer.
	var pop := 1.0
	if _phase_t < REVEAL_POP:
		pop = 1.0 + sin(_phase_t / REVEAL_POP * PI) * 0.40
	_panel(Rect2(515, 176, 250, 128), 34, WiiTheme.ACCENT, Color(1, 1, 1, 1), 3)
	draw_set_transform(Vector2(640, 240), 0.0, Vector2(pop, pop))
	draw_text_centered(str(_real_count), Vector2.ZERO, 76, WiiTheme.ACCENT_DARK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _panel_rect(i: int, n: int, reveal: bool) -> Rect2:
	var yo := 50.0 if reveal else 0.0
	if n <= 1:
		return Rect2(400, 330 + yo, 480, 240)
	if n == 2:
		return Rect2(140 + 520.0 * i, 340 + yo, 460, 230)
	var col := i % 2
	var row := int(i / 2.0)
	return Rect2(155 + 500.0 * col, 300 + yo + 175.0 * row, 470, 160)


func _scale_rect(r: Rect2, s: float) -> Rect2:
	var c := r.get_center()
	var size := r.size * s
	return Rect2(c - size * 0.5, size)


func _draw_answer_panel(i: int, rect: Rect2, reveal: bool, n: int) -> void:
	var p = players[i]
	var confirmed = _confirmed[i]
	var winner := reveal and i in _closest
	var bg := Color(1, 1, 1, 1)
	if confirmed and not reveal:
		bg = p.color.linear_interpolate(Color(1, 1, 1, 1), 0.86)
	# Panel con sombra suave y borde del color del jugador.
	var st := WiiTheme.panel_style(28, p.color, bg)
	st.set_border_width_all(4)
	st.shadow_size = 8
	draw_style_box(st, rect)
	# Bola del jugador con su número.
	var bc := rect.position + Vector2(50, 46)
	draw_circle(bc + Vector2(0, 3), 24, WiiTheme.SHADOW)
	draw_circle(bc, 24, p.color)
	draw_circle(bc + Vector2(0, 7), 17, p.color.darkened(0.10))
	draw_circle(bc + Vector2(-7, -9), 8, Color(1, 1, 1, 0.45))
	draw_text_centered(str(p.index + 1), bc, 21, Color(1, 1, 1, 1))
	# Aviso visual al confirmar.
	if not reveal and _confirm_t[i] > 0.0:
		var k = 1.0 - _confirm_t[i] / CONFIRM_POP
		draw_arc(bc, 27.0 + k * 22.0, 0.0, TAU, 32, Color(p.color, 0.65 * (1.0 - k)), 4.0, true)
	# Respuesta grande, con pequeño rebote al confirmar.
	var pop := 1.0
	if not reveal and _confirm_t[i] > 0.0:
		var ck = 1.0 - _confirm_t[i] / CONFIRM_POP
		pop = 1.0 + sin(ck * PI) * 0.22
	var big := 78 if n <= 2 else 58
	var nc := Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.54)
	draw_set_transform(nc, 0.0, Vector2(pop, pop))
	draw_text_centered(str(_answers[i]), Vector2.ZERO, big, p.color.darkened(0.18))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Estado del jugador.
	var status := ""
	var scol := WiiTheme.TEXT_SOFT
	if reveal:
		var err := abs(_answers[i] - _real_count)
		if winner:
			status = loc({"es": "Más cerca · Error: %d", "en": "Closest · Off by %d"}) % err
			scol = Color("c99400")
		else:
			status = loc({"es": "Error: %d", "en": "Off by %d"}) % err
			scol = WiiTheme.TEXT
	else:
		status = loc({"es": "Listo", "en": "Ready"}) if confirmed \
				else loc({"es": "A: confirmar", "en": "A: confirm"})
		if confirmed:
			scol = p.color.darkened(0.18)
	var pill_y := rect.end.y - 42.0
	if confirmed and not reveal:
		var pill := Rect2(rect.get_center().x - 62.0, pill_y, 124.0, 30.0)
		var pst := WiiTheme.panel_style(15, p.color, p.color.linear_interpolate(Color(1, 1, 1, 1), 0.80))
		pst.set_border_width_all(2)
		pst.shadow_size = 0
		draw_style_box(pst, pill)
	draw_text_centered(status, Vector2(rect.get_center().x, pill_y + 14.0), 20, scol, 700)
	# Ganador de la ronda: aro y brillo de su color.
	if winner:
		var pulse := 0.5 + 0.5 * sin(_time * 5.0)
		for g in 3:
			var ring := StyleBoxFlat.new()
			ring.bg_color = Color(0, 0, 0, 0)
			ring.draw_center = false
			ring.border_color = Color(p.color, 0.42 - g * 0.11 + pulse * 0.14)
			ring.set_border_width_all(5 - g)
			ring.set_corner_radius_all(34)
			ring.set_expand_margin_all(2.0 + g * 3.0 + pulse * 2.0)
			ring.anti_aliasing = true
			draw_style_box(ring, rect)
		for k in 8:
			var a := _time * 1.6 + TAU * float(k) / 8.0
			var sp := rect.get_center() + Vector2(cos(a) * (rect.size.x * 0.5 + 10.0),
					sin(a) * (rect.size.y * 0.5 + 10.0))
			draw_circle(sp, 3.0 + sin(_time * 6.0 + k) * 1.2, Color("ffd34d"))


# --- Piezas comunes de la cabecera ---

func _draw_round_pill() -> void:
	var st := WiiTheme.panel_style(20, WiiTheme.PANEL_BORDER, Color(1, 1, 1, 0.92))
	st.set_border_width_all(2)
	draw_style_box(st, Rect2(58, 116, 132, 46))
	draw_text_centered(loc({"es": "Ronda %d/2", "en": "Round %d/2"}) % (_round + 1),
			Vector2(124, 139), 19, WiiTheme.TEXT_SOFT, 700)


func _draw_timer(center: Vector2, secs: int, frac: float) -> void:
	var col := Color("e25555") if secs <= 3 else WiiTheme.ACCENT
	var st := WiiTheme.panel_style(28, col, Color(1, 1, 1, 0.96))
	st.set_border_width_all(3)
	draw_style_box(st, Rect2(center - Vector2(28, 28), Vector2(56, 56)))
	if frac < 1.0:
		draw_arc(center, 33.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color(col, 0.85), 4.0, true)
	draw_text_centered(str(secs), center, 28, col)


func _panel(rect: Rect2, radius: int, border: Color, bg: Color, border_w: int) -> void:
	var st := WiiTheme.panel_style(radius, border, bg)
	st.set_border_width_all(border_w)
	st.shadow_size = 7
	draw_style_box(st, rect)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	_cv.draw_set_transform(center - _cv_origin, 0.0, radii)
	_cv.draw_circle(Vector2.ZERO, 1.0, color)
	_cv.draw_set_transform(-_cv_origin, 0.0, Vector2.ONE)


# =====================================================================
# Ovejas y lobos
# =====================================================================

func _draw_sheep(base: Vector2, s: float, dir: int, hop: float, gait: float) -> void:
	var body := base - Vector2(0, hop)
	# Sombra en el suelo: se encoge al saltar.
	var sh := clamp(1.0 - hop / (HOP_HEIGHT * 2.0), 0.5, 1.0)
	_ellipse(Vector2(base.x, base.y + 30.0 * s), Vector2(28.0 * s * sh, 9.0 * s * sh), WiiTheme.SHADOW)
	# Patas con marcha alterna.
	var sw := sin(gait) * 4.5 * s
	_cv.draw_line(Vector2(body.x - 12.0 * s + sw, body.y + 8.0 * s),
			Vector2(body.x - 12.0 * s + sw * 1.4, body.y + 29.0 * s), SHEEP_DARK, 5.0 * s)
	_cv.draw_line(Vector2(body.x + 11.0 * s - sw, body.y + 8.0 * s),
			Vector2(body.x + 11.0 * s - sw * 1.4, body.y + 29.0 * s), SHEEP_DARK, 5.0 * s)
	_cv.draw_line(Vector2(body.x - 1.0 * s - sw * 0.7, body.y + 9.0 * s),
			Vector2(body.x - 1.0 * s - sw, body.y + 28.0 * s), SHEEP_DARK.darkened(0.12), 4.0 * s)
	_cv.draw_line(Vector2(body.x + 18.0 * s + sw * 0.7, body.y + 9.0 * s),
			Vector2(body.x + 18.0 * s + sw, body.y + 28.0 * s), SHEEP_DARK.darkened(0.12), 4.0 * s)
	# Lana: base con sombra y varios copos blancos.
	_ellipse(body + Vector2(0, 4) * s, Vector2(24.0 * s, 17.0 * s), WOOL_SHADE)
	for o in [Vector2(-17, 1), Vector2(-6, -10), Vector2(8, -11),
			Vector2(19, -1), Vector2(8, 9), Vector2(-8, 9)]:
		_cv.draw_circle(body + o * s, 12.5 * s, WOOL)
	_cv.draw_circle(body + Vector2(-9, -13) * s, 6.0 * s, Color(1, 1, 1, 0.9))
	# Cabeza.
	var head := body + Vector2(dir * 25.0, 1.0) * s
	_ellipse(head + Vector2(-dir * 4.0, -8.0) * s, Vector2(7.0, 4.5) * s, SHEEP_HEAD.darkened(0.08))
	_cv.draw_circle(head, 12.0 * s, SHEEP_HEAD)
	_cv.draw_circle(head + Vector2(-dir * 1.0, -10.0) * s, 7.0 * s, WOOL)
	_ellipse(head + Vector2(dir * 7.0, 3.0) * s, Vector2(7.0, 5.0) * s, SHEEP_MUZZLE)
	var eye := head + Vector2(dir * 3.0, -3.0) * s
	_cv.draw_circle(eye, 3.6 * s, Color(1, 1, 1, 1))
	_cv.draw_circle(eye + Vector2(dir * 1.1, 0.2) * s, 1.9 * s, EYE_DARK)
	_cv.draw_circle(eye + Vector2(0, -0.9) * s, 0.7 * s, Color(1, 1, 1, 0.9))
	_cv.draw_circle(head + Vector2(dir * 11.0, 1.5) * s, 1.6 * s, Color("48545e"))


func _draw_wolf(base: Vector2, s: float, dir: int, hop: float, gait: float) -> void:
	var body := base - Vector2(0, hop)
	var sh := clamp(1.0 - hop / (HOP_HEIGHT * 2.0), 0.5, 1.0)
	_ellipse(Vector2(base.x, base.y + 31.0 * s), Vector2(30.0 * s * sh, 9.5 * s * sh), WiiTheme.SHADOW)
	# Patas.
	var sw := sin(gait) * 5.0 * s
	for off in [-16.0, -5.0, 9.0, 20.0]:
		var x = body.x + off * s
		var swing := sw if off < 0.0 else -sw
		_cv.draw_line(Vector2(x, body.y + 10.0 * s), Vector2(x + swing, body.y + 30.0 * s),
				WOLF_DARK, 6.0 * s)
	# Cola poblada hacia atrás.
	var tail_a := body + Vector2(-dir * 16.0, -2.0) * s
	var tail_b := body + Vector2(-dir * 40.0, -20.0) * s
	_cv.draw_line(tail_a, tail_b, WOLF_DARK, 9.0 * s)
	_cv.draw_circle(tail_b, 7.0 * s, WOLF_LIGHT)
	# Cuerpo y pecho claro.
	_ellipse(body + Vector2(0, 1.0) * s, Vector2(27.0 * s, 17.0 * s), WOLF_BODY)
	_ellipse(body + Vector2(dir * 10.0, 6.0) * s, Vector2(14.0 * s, 11.0 * s), WOLF_LIGHT)
	# Cabeza.
	var head := body + Vector2(dir * 27.0, -13.0) * s
	_ellipse(head + Vector2(dir * 8.0, 1.0) * s, Vector2(15.0, 9.0) * s, WOLF_BODY)
	_cv.draw_circle(head, 12.5 * s, WOLF_BODY)
	# Orejas puntiagudas.
	_cv.draw_colored_polygon(PoolVector2Array([
		head + Vector2(-8, -8) * s, head + Vector2(-13, -26) * s, head + Vector2(0, -12) * s]),
		WOLF_DARK)
	_cv.draw_colored_polygon(PoolVector2Array([
		head + Vector2(4, -10) * s, head + Vector2(6, -28) * s, head + Vector2(14, -7) * s]),
		WOLF_DARK)
	_cv.draw_colored_polygon(PoolVector2Array([
		head + Vector2(-6, -11) * s, head + Vector2(-10, -22) * s, head + Vector2(-2, -13) * s]),
		WOLF_EAR)
	_cv.draw_colored_polygon(PoolVector2Array([
		head + Vector2(6, -12) * s, head + Vector2(7, -24) * s, head + Vector2(11, -9) * s]),
		WOLF_EAR)
	# Hocico y nariz.
	_ellipse(head + Vector2(dir * 12.0, 2.0) * s, Vector2(9.0, 6.0) * s, WOLF_LIGHT)
	_cv.draw_circle(head + Vector2(dir * 19.0, 1.0) * s, 2.6 * s, EYE_DARK)
	# Ojos grandes y amables.
	var eye := head + Vector2(dir * 4.0, -4.0) * s
	_cv.draw_circle(eye, 4.0 * s, Color(1, 1, 1, 1))
	_cv.draw_circle(eye + Vector2(dir * 1.2, 0.2) * s, 2.1 * s, EYE_DARK)
	_cv.draw_circle(eye + Vector2(-0.4, -1.2) * s, 0.8 * s, Color(1, 1, 1, 0.95))
	# Sonrisa.
	_cv.draw_line(head + Vector2(dir * 12.0, 7.0) * s, head + Vector2(dir * 16.0, 6.0) * s,
			WOLF_DARK, 1.8 * s)

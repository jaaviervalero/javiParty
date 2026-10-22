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
# Ambiente: feria al aire libre.
const SKY_TOP_G := Color("bfe9fb")
const SKY_BOTTOM_G := Color("fdf3e3")
const GROUND_TOP := Color("a8dd8a")
const GROUND_BOTTOM := Color("86c96a")
const GROUND_Y := 590.0
const TENT_STRIPE := Color("ffb1a8")
const TENT_CREAM := Color("fff4e0")
const BUNTING_COLORS = [Color("ffb3c1"), Color("ffe08a"), Color("a8e6cf"),
		Color("b8c9f5"), Color("e3c6f2")]
const AMBIENT_COLORS = [Color("ffc2d1"), Color("ffe6a1"), Color("bfe6fb")]
# [x en fracción de la arena, velocidad, desfase]
const AMBIENT_BALLOONS = [[0.22, 0.28, 0.0], [0.52, 0.22, 0.45], [0.80, 0.25, 0.78]]


class Balloon:
	var player: Player
	var cx := 640.0
	var fill := 0.0
	var squash := 1.0
	var pump := 0.0
	var style: StyleBoxFlat


var _balloons: Array = []
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
	return min(ARENA.size.x / float(max(players.size(), 1)), MAX_COL_W)


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
		b.fill = max(0.0, b.fill - DEFLATE * delta)
		b.pump = max(0.0, b.pump - delta * 6.0)
		b.squash = lerp(b.squash, 1.0, min(1.0, delta * 9.0))
		if b.player.just_pressed(Pad.A):
			b.fill = min(1.0, b.fill + PUMP_GAIN)
			b.pump = 1.0
			b.squash = 1.12
			Sfx.play("move", rand_range(0.85, 1.15))
			if b.fill >= 1.0:
				_pop(b)
	_update_effects(delta)


func _pop(b: Balloon) -> void:
	var c := Vector2(b.cx, BALLOON_Y)
	add_score(b.player)
	_burst(c, b.player.color, 22)
	_flashes.append([c, 0.0, b.player.color])
	Sfx.play("pop", rand_range(0.95, 1.1))
	b.fill = 0.0
	b.squash = 0.4


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * rand_range(90.0, 390.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color(1, 1, 1, 1), rand_range(0.5, 0.9)])


func _update_effects(delta: float) -> void:
	for f in _flashes:
		f[1] += delta * 2.5
	var live_flashes: Array = []
	for f in _flashes:
		if f[1] < 1.0:
			live_flashes.append(f)
	_flashes = live_flashes
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 520) * delta
		c[3] -= delta
	var live_confetti: Array = []
	for c in _confetti:
		if c[3] > 0.0:
			live_confetti.append(c)
	_confetti = live_confetti


# --- Dibujo ---

## Ambiente fijo: feria al aire libre con carpa y guirnalda. Se pinta una vez.
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	DrawKit.arena_frame(ci, ARENA, SKY_TOP_G, SKY_BOTTOM_G)
	DrawKit.sun(ci, Vector2(ARENA.end.x - 170.0, ARENA.position.y + 140.0), 30.0, 0.3)
	DrawKit.hills(ci, ARENA, GROUND_Y - 70.0, 26.0, Color("b7e69c"), 1.2, 1.6, clip)
	_draw_tent(ci, clip)
	# Césped del suelo, con una banda más oscura al fondo.
	var ground := PoolVector2Array([
		Vector2(ARENA.position.x, GROUND_Y), Vector2(ARENA.end.x, GROUND_Y),
		Vector2(ARENA.end.x, ARENA.end.y), Vector2(ARENA.position.x, ARENA.end.y)])
	DrawKit.clipped_polygon(ci, ground, clip, GROUND_TOP)
	var lower := PoolVector2Array([
		Vector2(ARENA.position.x, ARENA.end.y - 36.0), Vector2(ARENA.end.x, ARENA.end.y - 36.0),
		Vector2(ARENA.end.x, ARENA.end.y), Vector2(ARENA.position.x, ARENA.end.y)])
	DrawKit.clipped_polygon(ci, lower, clip, GROUND_BOTTOM)
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 30.0, GROUND_Y + 14.0),
			Vector2(ARENA.end.x - 30.0, GROUND_Y + 14.0), 28, DrawKit.GRASS_DARK, 7)
	_draw_bunting(ci)
	# Columnas de cada jugador (translúcidas y fijas).
	var colw := _col_width()
	var left := _col_left()
	for i in _balloons.size():
		var rect := Rect2(left + colw * i + COL_MARGIN, ARENA.position.y + COL_MARGIN,
				colw - COL_MARGIN * 2.0, ARENA.size.y - COL_MARGIN * 2.0)
		ci.draw_style_box(_balloons[i].style, rect)
	DrawKit.arena_border(ci, ARENA)


## Carpa de rayas pastel al fondo, con banderín.
func _draw_tent(ci: CanvasItem, clip: PoolVector2Array) -> void:
	var cx := ARENA.get_center().x
	var body := Rect2(cx - 130.0, GROUND_Y - 150.0, 260.0, 150.0)
	var stripes := 7
	for i in stripes:
		var x0 := body.position.x + body.size.x * float(i) / stripes
		var x1 := body.position.x + body.size.x * float(i + 1) / stripes
		var col: Color = TENT_STRIPE if i % 2 == 0 else TENT_CREAM
		DrawKit.clipped_polygon(ci, PoolVector2Array([
			Vector2(x0, body.position.y), Vector2(x1, body.position.y),
			Vector2(x1, body.end.y), Vector2(x0, body.end.y)]), clip, col)
	# Tejado triangular y faldón blanco.
	DrawKit.clipped_polygon(ci, PoolVector2Array([
		Vector2(body.position.x - 16.0, body.position.y),
		Vector2(body.end.x + 16.0, body.position.y),
		Vector2(cx, body.position.y - 78.0)]), clip, TENT_STRIPE)
	ci.draw_line(Vector2(body.position.x - 16.0, body.position.y),
			Vector2(body.end.x + 16.0, body.position.y), Color(1, 1, 1, 1), 5.0, true)
	# Entrada.
	DrawKit.clipped_polygon(ci, PoolVector2Array([
		Vector2(cx - 34.0, body.end.y), Vector2(cx - 34.0, body.end.y - 54.0),
		Vector2(cx + 34.0, body.end.y - 54.0), Vector2(cx + 34.0, body.end.y)]),
		clip, Color(TENT_CREAM, 0.85))
	# Mástil y banderín.
	ci.draw_line(Vector2(cx, body.position.y - 78.0), Vector2(cx, body.position.y - 112.0),
			Color(WiiTheme.TEXT_SOFT, 0.7), 3.0)
	ci.draw_colored_polygon(PoolVector2Array([
		Vector2(cx, body.position.y - 112.0), Vector2(cx + 30.0, body.position.y - 102.0),
		Vector2(cx, body.position.y - 92.0)]), Color("ffe08a"))


## Guirnalda de banderines de colores pastel arriba del todo.
func _draw_bunting(ci: CanvasItem) -> void:
	var x0 := ARENA.position.x + 24.0
	var x1 := ARENA.end.x - 24.0
	var y0 := ARENA.position.y + 26.0
	var sag := 52.0
	var pts := PoolVector2Array()
	var n := 16
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector2(lerp(x0, x1, t), y0 + sin(t * PI) * sag))
	ci.draw_polyline(pts, Color(WiiTheme.TEXT_SOFT, 0.5), 2.0, true)
	for i in 14:
		var t := (float(i) + 0.5) / 14.0
		var p := Vector2(lerp(x0, x1, t), y0 + sin(t * PI) * sag)
		var col: Color = BUNTING_COLORS[i % BUNTING_COLORS.size()]
		ci.draw_colored_polygon(PoolVector2Array([
			p + Vector2(-13.0, 0.0), p + Vector2(13.0, 0.0), p + Vector2(0.0, 27.0)]), col)


## MinigameBase llama a queue_redraw() cada frame: aquí solo lo que se mueve.
func _draw() -> void:
	_draw_ambient()
	for b in _balloons:
		_draw_balloon(b)
		_draw_pump(b)
	for f in _flashes:
		var t: float = f[1]
		draw_arc(f[0], 40.0 + t * 190.0, 0.0, TAU, 40, Color(f[2], 1.0 - t), 6.0 * (1.0 - t) + 1.0)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)), Color(c[2], clamp(c[3] * 2.5, 0.0, 1.0)))


## Globos sueltos que suben despacio al fondo (ambiente barato y translúcido).
func _draw_ambient() -> void:
	for i in AMBIENT_BALLOONS.size():
		var a: Array = AMBIENT_BALLOONS[i]
		var t := fposmod(_time * float(a[1]) + float(a[2]), 1.0)
		var p := Vector2(ARENA.position.x + ARENA.size.x * float(a[0]) + sin(t * TAU) * 26.0,
				ARENA.position.y + 60.0 + (ARENA.size.y - 120.0) * (1.0 - t))
		var col: Color = AMBIENT_COLORS[i % AMBIENT_COLORS.size()]
		# Se desvanecen al aparecer por abajo y al perderse arriba.
		var fade := clamp(sin(t * PI), 0.0, 1.0)
		DrawKit.ellipse(self, p, Vector2(15.0, 19.0), Color(col, 0.34 * fade))
		draw_circle(p + Vector2(-5.0, -7.0), 5.0, Color(1, 1, 1, 0.25 * fade))
		draw_line(p + Vector2(0, 19.0), p + Vector2(0, 33.0), Color(1, 1, 1, 0.25 * fade), 2.0, true)


func _draw_balloon(b: Balloon) -> void:
	var p := b.player
	var r: float = lerp(MIN_R, MAX_R, b.fill)
	var tension: float = clamp((b.fill - TENSE_AT) / (1.0 - TENSE_AT), 0.0, 1.0)
	var shake := Vector2(sin(_time * 42.0 + p.index * 1.7) * 5.0 * tension,
			cos(_time * 51.0 + p.index * 1.3) * 3.0 * tension)
	var c: Vector2 = Vector2(b.cx, BALLOON_Y) + shake
	var bottom := c + Vector2(0, r * 1.12 * b.squash)

	# Hilo del globo al inflador
	draw_line(bottom + Vector2(0, 18), Vector2(b.cx, NOZZLE_Y), Color(WiiTheme.TEXT_SOFT, 0.55), 3.0)

	# Sombra en el suelo de la columna
	draw_set_transform(Vector2(b.cx, BALLOON_Y + r * 1.12 + 8), 0, Vector2(1.15, 0.3))
	draw_circle(Vector2.ZERO, r, WiiTheme.SHADOW)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Cuerpo del globo (elipse con squash)
	var col: Color = p.color if p.is_connected_now() else p.color.linear_interpolate(Color("c8ced4"), 0.7)
	col = col.linear_interpolate(Color(1, 1, 1, 1), tension * 0.5)
	draw_set_transform(c, 0, Vector2(1.0 / b.squash, b.squash * 1.12))
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2(0, r * 0.25), r * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.36, Color(1, 1, 1, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Anillo de tensión cuando está a punto de estallar
	if tension > 0.0:
		draw_arc(c, r * 1.14 + 7.0, 0.0, TAU, 40, Color("e25555", 0.55 * tension), 4.0)

	# Nudo
	var knot := PoolVector2Array([bottom + Vector2(-9, 0), bottom + Vector2(9, 0), bottom + Vector2(0, 18)])
	draw_colored_polygon(knot, col.darkened(0.12))

	var num_col := Color(1, 1, 1, 1).linear_interpolate(p.color.darkened(0.45), tension)
	draw_text_centered(str(p.index + 1), c, int(clamp(r * 0.65, 20.0, 42.0)), num_col)


func _draw_pump(b: Balloon) -> void:
	var p := b.player
	var col: Color = p.color if p.is_connected_now() else p.color.linear_interpolate(Color("c8ced4"), 0.7)
	# Boquilla
	draw_rect(Rect2(b.cx - 9, NOZZLE_Y, 18, PUMP_Y - NOZZLE_Y), col.darkened(0.25))
	# Cuerpo
	var st := WiiTheme.panel_style(14, col.darkened(0.15), col)
	st.shadow_size = 2
	draw_style_box(st, Rect2(b.cx - 40, PUMP_Y, 80, 42))
	# Mango que baja al machacar
	draw_rect(Rect2(b.cx - 26, PUMP_Y - 24 + 12 * b.pump, 52, 12), col.darkened(0.12))
	draw_text_centered("A", Vector2(b.cx, PUMP_Y + 21), 22, Color(1, 1, 1, 1))

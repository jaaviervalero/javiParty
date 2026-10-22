extends MinigameBase
## "Pajarito saltarín": el arena se divide en franjas, una por jugador. Con A se
## aletea y la gravedad tira hacia abajo; hay que pasar entre las columnas, que
## llegan de derecha a izquierda con la MISMA secuencia de huecos en todas las
## franjas. Chocar cuesta una vida (3 por jugador). Puntos = columnas superadas.

const BIRD_RADIUS := 15.0
const BIRD_X := 110.0
# La física va en proporción a la altura de la franja: con 1 jugador la franja es
# grande y con 4 es pequeña, pero el control se siente igual en las dos.
const GRAVITY_FRAC := 6.0
const FLAP_FRAC := 1.58
const MAX_FALL_FRAC := 3.0
const BAND_GAP := 12.0
const BAND_PAD := 8.0
const LIVES := 3
const INVULN_TIME := 1.0
const COLUMN_WIDTH := 58.0
const COLUMN_SPACING := 300.0
const GAP_FRAC := 0.42
const MAX_GAP := 280.0
const SPEED_START := 230.0
const SPEED_GAIN := 3.0
const SPEED_MAX := 430.0
const GAP_MIN_FRAC := 0.21
const GAP_MAX_FRAC := 0.79
# Ambiente: mañana de campo con colinas, nubes y postes de madera.
const SKY_TOP := Color("cdeafd")
const SKY_BOTTOM := Color("f4fbf3")
const HILL_FAR := Color("cfe6bf")
const HILL_NEAR := Color("a9da8f")
const LEAF := Color("a9de8a")
const LEAF_LIGHT := Color("c4edaa")
const CLOUD_COL := Color(1, 1, 1, 0.9)
const PARALLAX_FRAC := 0.12   # lo despacio que derivan las nubes respecto a las columnas
const CLOUDS := [
	[Vector2(120, 58), 0.95],
	[Vector2(520, 128), 0.7],
	[Vector2(880, 74), 0.82],
]


class Bird:
	var player: Player
	var pos := Vector2.ZERO
	var vy := 0.0
	var lives := 3
	var invuln := 0.0
	var eliminated := false
	var squash := 1.0
	var band := Rect2()


class Column:
	var x := 0.0
	var gap_center := 0.5  # fracción de la altura de la franja
	var scored := false


var _birds: Array[Bird] = []
var _columns: Array[Column] = []
var _band_rects: Array[Rect2] = []
var _speed := SPEED_START
var _spawn_acc := 0.0
var _parallax := 0.0
var _panel_style: StyleBoxFlat
var _column_style: StyleBoxFlat


func _configure() -> void:
	title = {"es": "Pajarito saltarín", "en": "Flappy hop"}
	instructions = {"es": "Pulsa A para aletear y pasa entre las columnas sin chocar.",
		"en": "Tap A to flap and slip through the columns without crashing."}
	controls = [[Pad.A, {"es": "Aletear", "en": "Flap"}]]
	duration = 60.0


func _setup() -> void:
	# Franjas translúcidas: dejan ver el cielo y el decorado del fondo.
	_panel_style = WiiTheme.panel_style(22, Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.26))
	_panel_style.shadow_size = 0
	# Postes de madera redondeados (nada que recuerde a tuberías verdes).
	_column_style = StyleBoxFlat.new()
	_column_style.bg_color = DrawKit.WOOD
	_column_style.border_color = DrawKit.WOOD_DARK
	_column_style.set_border_width_all(2)
	_column_style.set_corner_radius_all(16)
	_column_style.shadow_color = WiiTheme.SHADOW
	_column_style.shadow_size = 4
	_column_style.shadow_offset = Vector2(0, 2)
	_column_style.anti_aliasing = true

	var n := players.size()
	var band_h := (ARENA.size.y - BAND_GAP * (n - 1)) / n
	for i in n:
		var band := Rect2(ARENA.position.x, ARENA.position.y + i * (band_h + BAND_GAP),
				ARENA.size.x, band_h)
		_band_rects.append(band)
		var bird := Bird.new()
		bird.player = players[i]
		bird.band = band
		bird.pos = Vector2(band.position.x + BIRD_X, band.get_center().y)
		_birds.append(bird)


func _game_start() -> void:
	_spawn_acc = 0.0
	_speed = SPEED_START
	for bird in _birds:
		bird.pos.y = bird.band.get_center().y
		bird.vy = 0.0
	# La pista ya arranca con columnas a la vista: hay acción desde el primer segundo.
	for i in 3:
		_columns.append(_make_column(ARENA.position.x + BIRD_X + 420.0 + i * COLUMN_SPACING))


func _game_process(delta: float) -> void:
	_speed = minf(SPEED_MAX, SPEED_START + elapsed * SPEED_GAIN)
	_parallax += _speed * PARALLAX_FRAC * delta
	_spawn_acc += _speed * delta
	if _spawn_acc >= COLUMN_SPACING:
		_spawn_acc -= COLUMN_SPACING
		_spawn_column()

	# Columnas: la misma x y el mismo hueco relativo para todas las franjas.
	for col in _columns:
		col.x -= _speed * delta
		if not col.scored and col.x + COLUMN_WIDTH * 0.5 < ARENA.position.x + BIRD_X:
			col.scored = true
			var scored_any := false
			for bird in _birds:
				if not bird.eliminated:
					add_score(bird.player)
					scored_any = true
			if scored_any:
				Sfx.play("star", randf_range(1.0, 1.15))

	var keep: Array[Column] = []
	for col in _columns:
		if col.x + COLUMN_WIDTH * 0.5 > ARENA.position.x - 60.0:
			keep.append(col)
	_columns = keep

	for bird in _birds:
		_update_bird(bird, delta)

	var any_alive := false
	for bird in _birds:
		if not bird.eliminated:
			any_alive = true
	if not any_alive:
		finish()


func _spawn_column() -> void:
	_columns.append(_make_column(ARENA.end.x + COLUMN_WIDTH * 0.5 + 10.0))


func _make_column(x: float) -> Column:
	var col := Column.new()
	col.x = x
	col.gap_center = randf_range(GAP_MIN_FRAC, GAP_MAX_FRAC)
	return col


func _update_bird(bird: Bird, delta: float) -> void:
	if bird.eliminated:
		return
	bird.invuln = maxf(0.0, bird.invuln - delta)
	bird.squash = lerpf(bird.squash, 1.0, minf(1.0, delta * 10.0))

	var gravity := GRAVITY_FRAC * bird.band.size.y
	if bird.player.just_pressed(Pad.A):
		bird.vy = -FLAP_FRAC * bird.band.size.y
		bird.squash = 1.3
		Sfx.play("dash", randf_range(1.1, 1.3))

	bird.vy = minf(MAX_FALL_FRAC * bird.band.size.y, bird.vy + gravity * delta)
	bird.pos.y += bird.vy * delta

	var top := bird.band.position.y + BIRD_RADIUS + BAND_PAD
	var bottom := bird.band.end.y - BIRD_RADIUS - BAND_PAD
	if bird.pos.y < top or bird.pos.y > bottom:
		bird.pos.y = clampf(bird.pos.y, top, bottom)
		bird.vy = -bird.vy * 0.4  # rebota; durante la invulnerabilidad no se queda pegado
		_hit_bird(bird)

	for col in _columns:
		if _bird_hits_column(bird, col):
			_hit_bird(bird)
			break


func _hit_bird(bird: Bird) -> void:
	if bird.eliminated or bird.invuln > 0.0:
		return
	bird.lives -= 1
	bird.invuln = INVULN_TIME
	Sfx.play("back", randf_range(0.9, 1.05))
	if bird.lives <= 0:
		bird.eliminated = true
		bird.vy = 0.0
		Sfx.play("leave")
	else:
		bird.pos.y = bird.band.get_center().y
		bird.vy = -FLAP_FRAC * bird.band.size.y * 0.5


func _bird_hits_column(bird: Bird, col: Column) -> bool:
	var half := COLUMN_WIDTH * 0.5
	var left := col.x - half
	var right := col.x + half
	if bird.pos.x + BIRD_RADIUS <= left or bird.pos.x - BIRD_RADIUS >= right:
		return false
	var band_h := bird.band.size.y
	var gap_h := minf(band_h * GAP_FRAC, MAX_GAP)
	var gap_top := bird.band.position.y + col.gap_center * band_h - gap_h * 0.5
	var gap_bottom := gap_top + gap_h
	var top_rect := Rect2(left, bird.band.position.y, COLUMN_WIDTH,
			maxf(0.0, gap_top - bird.band.position.y))
	var bottom_rect := Rect2(left, gap_bottom, COLUMN_WIDTH,
			maxf(0.0, bird.band.end.y - gap_bottom))
	return _circle_rect(bird.pos, BIRD_RADIUS, top_rect) \
			or _circle_rect(bird.pos, BIRD_RADIUS, bottom_rect)


func _circle_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x),
			clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_squared_to(closest) < radius * radius


# --- Dibujo ---

## Decorado estático: mañana de campo, con el sol, colinas, césped y las franjas.
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	DrawKit.arena_frame(ci, ARENA, SKY_TOP, SKY_BOTTOM)
	DrawKit.sun(ci, Vector2(ARENA.end.x - 108, ARENA.position.y + 90), 38.0)
	DrawKit.hills(ci, ARENA, ARENA.end.y - 118, 34, HILL_FAR, 0.4, 1.7, clip)
	DrawKit.hills(ci, ARENA, ARENA.end.y - 64, 22, HILL_NEAR, 2.3, 1.3, clip)
	# Césped al pie de la arena.
	DrawKit.hills(ci, ARENA, ARENA.end.y - 34, 7, DrawKit.GRASS, 1.2, 2.4, clip)
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 44, ARENA.end.y - 24),
			Vector2(ARENA.end.x - 44, ARENA.end.y - 24), 26, DrawKit.GRASS_DARK, 5)
	for i in 6:
		DrawKit.flower(ci, Vector2(ARENA.position.x + 110 + i * 200, ARENA.end.y - 32 - (i % 2) * 10),
				4, Color.WHITE if i % 2 == 0 else Color("ffd1e3"))
	# Franjas de cada jugador, translúcidas sobre el paisaje.
	for band in _band_rects:
		ci.draw_style_box(_panel_style, band)
	DrawKit.arena_border(ci, ARENA)


## Solo lo que se mueve: nubes en parallax, columnas y pájaros.
func _draw() -> void:
	for c in CLOUDS:
		var base: Vector2 = c[0]
		var x := ARENA.position.x + 80.0 + fposmod(base.x - _parallax, ARENA.size.x - 160.0)
		DrawKit.cloud(self, Vector2(x, ARENA.position.y + base.y), c[1], CLOUD_COL)
	for col in _columns:
		for band in _band_rects:
			_draw_column(col, band)
	for bird in _birds:
		_draw_bird(bird)
	for bird in _birds:
		_draw_band_info(bird)


func _draw_column(col: Column, band: Rect2) -> void:
	if col.x + COLUMN_WIDTH * 0.5 <= band.position.x or col.x - COLUMN_WIDTH * 0.5 >= band.end.x:
		return
	var band_h := band.size.y
	var gap_h := minf(band_h * GAP_FRAC, MAX_GAP)
	var gap_top := band.position.y + col.gap_center * band_h - gap_h * 0.5
	var gap_bottom := gap_top + gap_h
	var top_h := gap_top - band.position.y
	var bottom_h := band.end.y - gap_bottom
	if top_h > 2.0:
		_draw_post(Rect2(col.x - COLUMN_WIDTH * 0.5, band.position.y, COLUMN_WIDTH, top_h), gap_top, false)
	if bottom_h > 2.0:
		_draw_post(Rect2(col.x - COLUMN_WIDTH * 0.5, gap_bottom, COLUMN_WIDTH, bottom_h), gap_bottom, true)


## Poste de madera con vetas y copa de hojas en el extremo que mira al hueco.
func _draw_post(rect: Rect2, tip_y: float, tip_at_bottom: bool) -> void:
	draw_style_box(_column_style, rect)
	var cx := rect.position.x + COLUMN_WIDTH * 0.5
	if rect.size.y > 44.0:
		draw_line(Vector2(cx - 9, rect.position.y + 16), Vector2(cx - 9, rect.end.y - 16),
				Color(DrawKit.WOOD_DARK, 0.28), 2.0, true)
		draw_line(Vector2(cx + 10, rect.position.y + 24), Vector2(cx + 10, rect.end.y - 24),
				Color(DrawKit.WOOD_DARK, 0.18), 2.0, true)
	# Las hojas quedan dentro del poste (solo 3 px de vuelo): el hueco se lee igual
	# que la caja de colisión.
	var inset := -10.0 if tip_at_bottom else 10.0
	for i in 3:
		var dx := (i - 1) * 13.0
		draw_circle(Vector2(cx + dx, tip_y + inset), 13.0, LEAF)
	draw_circle(Vector2(cx, tip_y + inset * 0.6), 12.0, LEAF_LIGHT)


func _draw_bird(bird: Bird) -> void:
	var col := bird.player.color
	if bird.eliminated:
		col = Color("b9c1c9")
	var alpha := 1.0
	if bird.invuln > 0.0 and not bird.eliminated:
		alpha = 0.35 if fmod(bird.invuln, 0.18) < 0.09 else 1.0

	draw_set_transform(bird.pos + Vector2(0, 5), 0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, BIRD_RADIUS, Color(WiiTheme.SHADOW, WiiTheme.SHADOW.a * alpha))
	draw_set_transform(bird.pos, 0, Vector2(1.0 / bird.squash, bird.squash))
	draw_circle(Vector2.ZERO, BIRD_RADIUS, Color(col, alpha))
	draw_circle(Vector2(-BIRD_RADIUS * 0.3, -BIRD_RADIUS * 0.35), BIRD_RADIUS * 0.38,
			Color(1, 1, 1, 0.45 * alpha))
	# Ala y ojo, dentro de la bola (el tamaño no cambia).
	draw_circle(Vector2(-BIRD_RADIUS * 0.18, BIRD_RADIUS * 0.22), BIRD_RADIUS * 0.4,
			Color(col.darkened(0.16), alpha))
	draw_circle(Vector2(BIRD_RADIUS * 0.34, -BIRD_RADIUS * 0.3), BIRD_RADIUS * 0.17,
			Color(1, 1, 1, 0.9 * alpha))
	draw_circle(Vector2(BIRD_RADIUS * 0.38, -BIRD_RADIUS * 0.3), BIRD_RADIUS * 0.08,
			Color(0.2, 0.3, 0.4, 0.8 * alpha))
	draw_colored_polygon(PackedVector2Array([
		Vector2(BIRD_RADIUS * 0.8, 0),
		Vector2(BIRD_RADIUS * 0.8 + 9, -4),
		Vector2(BIRD_RADIUS * 0.8 + 9, 4),
	]), Color("f2a33a", alpha))
	draw_set_transform(Vector2.ZERO)
	draw_text_centered(str(bird.player.index + 1), bird.pos, 18, Color(1, 1, 1, alpha))


func _draw_band_info(bird: Bird) -> void:
	var band := bird.band
	for i in LIVES:
		var pip := bird.player.color if i < bird.lives else Color("d7dee4")
		draw_circle(Vector2(band.position.x + 24 + i * 16, band.position.y + 22), 6, pip)
	draw_text_centered(str(int(get_score(bird.player))),
			Vector2(band.end.x - 30, band.position.y + 22), 20, WiiTheme.TEXT_SOFT)

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
var _panel_style: StyleBoxFlat
var _column_style: StyleBoxFlat


func _configure() -> void:
	title = {"es": "Pajarito saltarín", "en": "Flappy hop"}
	instructions = {"es": "Pulsa A para aletear y pasa entre las columnas sin chocar.",
		"en": "Tap A to flap and slip through the columns without crashing."}
	controls = [[Pad.A, {"es": "Aletear", "en": "Flap"}]]
	duration = 60.0


func _setup() -> void:
	_panel_style = WiiTheme.panel_style(22)
	_column_style = StyleBoxFlat.new()
	_column_style.bg_color = Color("c6d3dd")
	_column_style.border_color = Color("a9bac7")
	_column_style.set_border_width_all(2)
	_column_style.set_corner_radius_all(14)
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

func _draw() -> void:
	for band in _band_rects:
		draw_style_box(_panel_style, band)
	for col in _columns:
		for band in _band_rects:
			_draw_column(col, band)
	for bird in _birds:
		_draw_bird(bird)
	for bird in _birds:
		_draw_band_info(bird)


func _draw_column(col: Column, band: Rect2) -> void:
	var left := col.x - COLUMN_WIDTH * 0.5
	var band_h := band.size.y
	var gap_h := minf(band_h * GAP_FRAC, MAX_GAP)
	var gap_top := band.position.y + col.gap_center * band_h - gap_h * 0.5
	var gap_bottom := gap_top + gap_h
	var top_h := gap_top - band.position.y
	var bottom_h := band.end.y - gap_bottom
	if top_h > 2.0 and col.x + COLUMN_WIDTH * 0.5 > band.position.x \
			and col.x - COLUMN_WIDTH * 0.5 < band.end.x:
		draw_style_box(_column_style, Rect2(left, band.position.y, COLUMN_WIDTH, top_h))
	if bottom_h > 2.0 and col.x + COLUMN_WIDTH * 0.5 > band.position.x \
			and col.x - COLUMN_WIDTH * 0.5 < band.end.x:
		draw_style_box(_column_style, Rect2(left, gap_bottom, COLUMN_WIDTH, bottom_h))


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

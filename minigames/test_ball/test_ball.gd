extends Node2D
## Juego de prueba "tonto" para comprobar el mando, solo con botones (pensado para el
## mando de javiParty, tools/make_layout.py): stick o cruceta mueven la bola, A da un
## impulso, B lanza una onda que empuja a los demás y + vuelve al menú.
## Recoger estrellas suma puntos. Sin motor de físicas: todo a mano y en un _draw.

const MENU_SCENE := "res://ui/main_menu.tscn"
const ARENA := Rect2(40, 110, 1200, 560)
const RADIUS := 34.0
const MAX_SPEED := 420.0      # px/s con la cruceta
const STEER := 9.0            # lo rápido que la velocidad sigue a la cruceta (1/s)
const DASH_SPEED := 750.0
const DASH_COOLDOWN := 0.6
const WAVE_COOLDOWN := 1.2
const WAVE_RADIUS := 260.0
const WAVE_PUSH := 900.0
const STAR_COUNT := 3
const STAR_RADIUS := 22.0

class Ball:
	var player: Player
	var pos: Vector2
	var vel := Vector2.ZERO
	var dash_cd := 0.0
	var wave_cd := 0.0
	var squash := 1.0

var _balls: Array[Ball] = []
var _stars: Array[Vector2] = []
var _star_anim: Array[float] = []
var _waves: Array = []      # [pos, t, color]
var _confetti: Array = []   # [pos, vel, color, life]
var _font: Font
var _help: Label
var _empty: Label
var _time := 0.0


func _ready() -> void:
	PlayerManager.ui_navigation_enabled = false
	_font = WiiTheme.font(800)
	var ui := CanvasLayer.new()
	add_child(ui)
	var bg := WiiBackground.new()
	ui.layer = -1
	ui.add_child(bg)
	var hud := CanvasLayer.new()
	add_child(hud)
	_help = Label.new()
	_help.text = "TEST_HELP"
	_help.position = Vector2(0, 676)
	_help.size = Vector2(1280, 30)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.add_theme_font_size_override("font_size", 18)
	_help.add_theme_color_override("font_color", WiiTheme.TEXT_SOFT)
	hud.add_child(_help)
	_empty = Label.new()
	_empty.text = "TEST_NO_PLAYERS"
	_empty.position = Vector2(0, 360)
	_empty.size = Vector2(1280, 40)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.add_theme_font_size_override("font_size", 30)
	hud.add_child(_empty)
	for i in STAR_COUNT:
		_stars.append(_random_star_pos())
		_star_anim.append(0.0)
	PlayerManager.player_joined.connect(func(_p): _sync_balls())
	_sync_balls()


func _exit_tree() -> void:
	PlayerManager.ui_navigation_enabled = true


func _sync_balls() -> void:
	for p in PlayerManager.active_players():
		var exists := false
		for b in _balls:
			if b.player == p:
				exists = true
		if not exists:
			var b := Ball.new()
			b.player = p
			b.pos = ARENA.get_center() + Vector2(-270 + 180 * p.index, 0)
			_balls.append(b)


func _random_star_pos() -> Vector2:
	var m := 60.0
	return Vector2(randf_range(ARENA.position.x + m, ARENA.end.x - m),
			randf_range(ARENA.position.y + m, ARENA.end.y - m))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_exit()


func _exit() -> void:
	Sfx.play("back")
	get_tree().change_scene_to_file(MENU_SCENE)


func _process(delta: float) -> void:
	_time += delta
	_empty.visible = PlayerManager.connected_players().is_empty()
	for b in _balls:
		_update_ball(b, delta)
	_collide_balls()
	_update_effects(delta)
	queue_redraw()


func _update_ball(b: Ball, delta: float) -> void:
	var p := b.player
	b.dash_cd = maxf(0.0, b.dash_cd - delta)
	b.wave_cd = maxf(0.0, b.wave_cd - delta)
	b.squash = lerpf(b.squash, 1.0, minf(1.0, delta * 10.0))
	if not p.is_connected_now():
		b.vel *= exp(-4.0 * delta)
		b.pos += b.vel * delta
		return

	if p.just_pressed(Pad.PLUS):
		_exit()
		return

	# La cruceta fija una velocidad objetivo y la bola la alcanza rápido: responde
	# al instante pero conserva algo de inercia (y los empujones se notan).
	# Stick analógico si se está usando; si no, la cruceta.
	var target := p.stick() * MAX_SPEED if p.stick() != Vector2.ZERO else p.dpad().normalized() * MAX_SPEED
	b.vel = b.vel.lerp(target, 1.0 - exp(-STEER * delta)) if target != Vector2.ZERO \
			else b.vel * exp(-STEER * 0.5 * delta)

	if p.just_pressed(Pad.A) and b.dash_cd <= 0.0:
		var dir := p.dpad().normalized()
		if dir == Vector2.ZERO:
			dir = b.vel.normalized() if b.vel.length() > 30.0 else Vector2.RIGHT
		b.vel += dir * DASH_SPEED
		b.dash_cd = DASH_COOLDOWN
		b.squash = 1.35
		Sfx.play("dash")

	if p.just_pressed(Pad.B) and b.wave_cd <= 0.0:
		b.wave_cd = WAVE_COOLDOWN
		_wave(b)

	b.pos += b.vel * delta
	# Rebote con los bordes de la arena.
	var lo := ARENA.position + Vector2(RADIUS, RADIUS)
	var hi := ARENA.end - Vector2(RADIUS, RADIUS)
	if b.pos.x < lo.x or b.pos.x > hi.x:
		b.pos.x = clampf(b.pos.x, lo.x, hi.x)
		b.vel.x *= -0.7
		b.squash = 0.85
	if b.pos.y < lo.y or b.pos.y > hi.y:
		b.pos.y = clampf(b.pos.y, lo.y, hi.y)
		b.vel.y *= -0.7
		b.squash = 0.85

	for i in _stars.size():
		if _star_anim[i] <= 0.0 and b.pos.distance_to(_stars[i]) < RADIUS + STAR_RADIUS:
			p.score += 1
			_star_anim[i] = 1.0
			_burst(_stars[i], Color("ffd34d"), 14)
			Sfx.play("star", randf_range(0.95, 1.1))


func _wave(b: Ball) -> void:
	_waves.append([b.pos, 0.0, b.player.color])
	_burst(b.pos, b.player.color, 24)
	Sfx.play("wave")
	for o in _balls:
		if o == b:
			continue
		var d := o.pos - b.pos
		if d.length() < WAVE_RADIUS and d.length() > 0.01:
			o.vel += d.normalized() * WAVE_PUSH * (1.0 - d.length() / WAVE_RADIUS)
			o.squash = 0.8


func _collide_balls() -> void:
	for i in _balls.size():
		for j in range(i + 1, _balls.size()):
			var a := _balls[i]
			var b := _balls[j]
			var d := b.pos - a.pos
			var dist := d.length()
			if dist < RADIUS * 2.0 and dist > 0.01:
				var n := d / dist
				var overlap := RADIUS * 2.0 - dist
				a.pos -= n * overlap * 0.5
				b.pos += n * overlap * 0.5
				var rel := (b.vel - a.vel).dot(n)
				if rel < 0.0:
					a.vel += n * rel * 0.9
					b.vel -= n * rel * 0.9
					if absf(rel) > 200.0:
						Sfx.play("pop", randf_range(0.9, 1.2))


func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(120.0, 420.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.5, 0.9)])


func _update_effects(delta: float) -> void:
	for i in _stars.size():
		if _star_anim[i] > 0.0:
			_star_anim[i] -= delta * 2.5
			if _star_anim[i] <= 0.0:
				_stars[i] = _random_star_pos()
	for w in _waves:
		w[1] += delta * 2.2
	_waves = _waves.filter(func(w): return w[1] < 1.0)
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 500) * delta
		c[3] -= delta
	_confetti = _confetti.filter(func(c): return c[3] > 0.0)


# --- Dibujo ---

func _draw() -> void:
	_draw_hud()
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	for i in _stars.size():
		var s := 1.0 + sin(_time * 4.0 + i) * 0.08
		if _star_anim[i] > 0.0:
			s = 1.0 + (1.0 - _star_anim[i]) * 0.8
		var a := 1.0 if _star_anim[i] <= 0.0 else _star_anim[i]
		_draw_star(_stars[i], STAR_RADIUS * s, _time * 0.8 + i, a)
	for w in _waves:
		var t: float = w[1]
		draw_arc(w[0], WAVE_RADIUS * t, 0, TAU, 48, Color(w[2], 0.6 * (1.0 - t)), 6.0 * (1.0 - t) + 1.0)
	for b in _balls:
		_draw_ball(b)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(4, 4), Vector2(8, 8)), Color(c[2], clampf(c[3] * 2.0, 0.0, 1.0)))


func _draw_ball(b: Ball) -> void:
	var col := b.player.color
	if not b.player.is_connected_now():
		col = col.lerp(Color("c8ced4"), 0.7)
	var stretch := Vector2(1.0 / b.squash, b.squash)
	draw_set_transform(b.pos + Vector2(0, 6), 0, Vector2(stretch.x * 1.1, 0.35))
	draw_circle(Vector2.ZERO, RADIUS, WiiTheme.SHADOW)
	draw_set_transform(b.pos, 0, stretch)
	draw_circle(Vector2.ZERO, RADIUS, col)
	draw_circle(Vector2(0, RADIUS * 0.25), RADIUS * 0.75, col.darkened(0.08))
	draw_circle(Vector2(-RADIUS * 0.3, -RADIUS * 0.35), RADIUS * 0.38, Color(1, 1, 1, 0.4))
	draw_set_transform(Vector2.ZERO)
	var num := str(b.player.index + 1)
	var ts := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
	draw_string(_font, b.pos + Vector2(-ts.x / 2, ts.y * 0.32), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)


func _draw_star(c: Vector2, r: float, rot: float, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2.UP.rotated(rot + i * TAU / 10.0) * rr)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_colored_polygon(pts, Color(1.0, 0.83, 0.3, alpha))
	draw_polyline(outline, Color(1, 1, 1, alpha), 3.0, true)


func _draw_hud() -> void:
	var title := tr("TEST_TITLE")
	draw_string(_font, Vector2(48, 66), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, WiiTheme.TEXT)
	var x := 1240.0
	for i in range(PlayerManager.MAX_PLAYERS - 1, -1, -1):
		var p := PlayerManager.players[i]
		if p == null:
			continue
		# Píldora: bola con el número del jugador, estrella y puntos.
		var txt := str(p.score)
		var w := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 112
		x -= w
		var rect := Rect2(x, 30, w, 48)
		var style := WiiTheme.panel_style(24, p.color if p.is_connected_now() else WiiTheme.PANEL_BORDER)
		style.set_border_width_all(3)
		draw_style_box(style, rect)
		draw_circle(Vector2(x + 26, 54), 15, p.color)
		var num := str(i + 1)
		var ns := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(_font, Vector2(x + 26 - ns.x / 2, 61), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		_draw_star(Vector2(x + 64, 54), 13, 0.0, 1.0)
		draw_string(_font, Vector2(x + 84, 63), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, p.color.darkened(0.15))
		x -= 12

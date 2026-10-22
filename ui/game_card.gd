extends Button
## Tarjeta de un minijuego en el selector, al estilo "canal": miniatura redondeada
## y nombre debajo. La miniatura la dibuja `minigames/<id>/thumb.gd` (función
## estática `draw(ci, rect)`); si no existe, se pinta una genérica. Solo se redibuja
## al cambiar el foco, así que no cuesta nada mientras está quieta.

const SIZE := Vector2(266, 196)
const THUMB_MARGIN := 9.0
const THUMB_H := 138.0
const THUMB_RADIUS := 16.0
const FOCUS_SCALE := 1.06

var game: Dictionary
var _thumb: Script
var _art: Control
var _tween: Tween


func _init(p_game: Dictionary) -> void:
	game = p_game
	var path: String = "res://minigames/%s/thumb.gd" % game.id
	if ResourceLoader.exists(path):
		_thumb = load(path)


func _ready() -> void:
	rect_min_size = SIZE
	rect_pivot_offset = SIZE / 2
	text = ""
	# Fondo siempre blanco (la máscara de esquinas de la miniatura es blanca).
	var normal := WiiTheme.panel_style(24)
	var hot: StyleBoxFlat = normal.duplicate()
	hot.border_color = WiiTheme.ACCENT
	hot.set_border_width_all(3)
	add_stylebox_override("normal", normal)
	add_stylebox_override("hover", hot)
	add_stylebox_override("pressed", hot)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = WiiTheme.ACCENT
	focus.set_border_width_all(5)
	focus.set_corner_radius_all(28)
	focus.set_expand_margin_all(5)
	focus.anti_aliasing = true
	add_stylebox_override("focus", focus)

	_art = Control.new()
	_art.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.connect("draw", self, "_draw_art")
	add_child(_art)
	connect("focus_entered", self, "_on_focus", [true])
	connect("focus_exited", self, "_on_focus", [false])


func _on_focus(on: bool) -> void:
	if on:
		raise()
	if _tween != null and is_instance_valid(_tween):
		_tween.stop_all()
		_tween.queue_free()
	var target := Vector2.ONE * (FOCUS_SCALE if on else 1.0)
	_tween = Anim.scale_to(self, rect_scale, target, 0.18)
	_art.update()


func _draw_art() -> void:
	var r := Rect2(THUMB_MARGIN, THUMB_MARGIN, SIZE.x - THUMB_MARGIN * 2, THUMB_H)
	if _thumb:
		_thumb.call("draw", _art, r)
	else:
		_draw_fallback(r)
	DrawKit.round_corners_mask(_art, r, THUMB_RADIUS, Color(1, 1, 1, 1))
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = Color(WiiTheme.PANEL_BORDER, 0.9)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(int(THUMB_RADIUS))
	frame.anti_aliasing = true
	_art.draw_style_box(frame, r)
	# Nombre del juego.
	var name_text := MinigameBase.loc(game.title)
	var fs := 21
	var f := Fonts.get_font(800, fs)
	var ts := f.get_string_size(name_text)
	while ts.x > SIZE.x - 24 and fs > 15:
		fs -= 1
		f = Fonts.get_font(800, fs)
		ts = f.get_string_size(name_text)
	var y := r.end.y + (SIZE.y - r.end.y) / 2 + ts.y * 0.3
	var col := WiiTheme.ACCENT_DARK if has_focus() else WiiTheme.TEXT
	_art.draw_string(f, Vector2((SIZE.x - ts.x) / 2, y), name_text, col)


## Miniatura genérica: degradado con la inicial del juego.
func _draw_fallback(r: Rect2) -> void:
	var hue := float(hash(game.id) % 360) / 360.0
	DrawKit.vgradient(_art, r, Color.from_hsv(hue, 0.35, 1.0), Color.from_hsv(hue, 0.55, 0.9))
	DrawKit.cloud(_art, r.position + Vector2(52, 36), 0.6)
	DrawKit.outlined_text(_art, 900, r.get_center(), MinigameBase.loc(game.title).left(1),
			64, Color.from_hsv(hue, 0.6, 0.75))

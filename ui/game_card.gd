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

static var _name_font: Font

var game: Dictionary
var _thumb: Script
var _art: Control
var _tween: Tween


func _init(p_game: Dictionary) -> void:
	game = p_game
	var path := "res://minigames/%s/thumb.gd" % game.id
	if ResourceLoader.exists(path):
		_thumb = load(path)


func _ready() -> void:
	custom_minimum_size = SIZE
	pivot_offset = SIZE / 2
	text = ""
	# Fondo siempre blanco (la máscara de esquinas de la miniatura es blanca).
	var normal := WiiTheme.panel_style(24)
	var hot := normal.duplicate() as StyleBoxFlat
	hot.border_color = WiiTheme.ACCENT
	hot.set_border_width_all(3)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hot)
	add_theme_stylebox_override("pressed", hot)
	add_theme_stylebox_override("hover_pressed", hot)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = WiiTheme.ACCENT
	focus.set_border_width_all(5)
	focus.set_corner_radius_all(28)
	focus.set_expand_margin_all(5)
	focus.anti_aliasing = true
	add_theme_stylebox_override("focus", focus)

	_art = Control.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	add_child(_art)
	focus_entered.connect(_on_focus.bind(true))
	focus_exited.connect(_on_focus.bind(false))


func _on_focus(on: bool) -> void:
	z_index = 1 if on else 0
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector2.ONE * (FOCUS_SCALE if on else 1.0), 0.18)
	_art.queue_redraw()


func _draw_art() -> void:
	var r := Rect2(THUMB_MARGIN, THUMB_MARGIN, SIZE.x - THUMB_MARGIN * 2, THUMB_H)
	if _thumb:
		_thumb.draw(_art, r)
	else:
		_draw_fallback(r)
	DrawKit.round_corners_mask(_art, r, THUMB_RADIUS, Color.WHITE)
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.border_color = Color(WiiTheme.PANEL_BORDER, 0.9)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(int(THUMB_RADIUS))
	frame.anti_aliasing = true
	_art.draw_style_box(frame, r)
	# Nombre del juego.
	if _name_font == null:
		_name_font = WiiTheme.font(800)
	var f := _name_font
	var name_text := MinigameBase.loc(game.title)
	var fs := 21
	var col := WiiTheme.ACCENT_DARK if has_focus() else WiiTheme.TEXT
	var ts := f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	while ts.x > SIZE.x - 24 and fs > 15:
		fs -= 1
		ts = f.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var y := r.end.y + (SIZE.y - r.end.y) / 2 + ts.y * 0.3
	_art.draw_string(f, Vector2((SIZE.x - ts.x) / 2, y), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Miniatura genérica: degradado con la inicial del juego.
func _draw_fallback(r: Rect2) -> void:
	var hue := float(hash(game.id) % 360) / 360.0
	DrawKit.vgradient(_art, r, Color.from_hsv(hue, 0.35, 1.0), Color.from_hsv(hue, 0.55, 0.9))
	DrawKit.cloud(_art, r.position + Vector2(52, 36), 0.6)
	DrawKit.outlined_text(_art, WiiTheme.font(900), r.get_center(), MinigameBase.loc(game.title).left(1),
			64, Color.from_hsv(hue, 0.6, 0.75))

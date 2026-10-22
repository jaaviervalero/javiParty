class_name PlayerCard
extends PanelContainer
## Tarjeta de un hueco de jugador en la pantalla de conexión (estilo "canal").

var index := 0
var _dot: Control
var _name: Label
var _status: Label
var _detail: Label
var _was_connected := false
var _tween: Tween


func _init(p_index: int) -> void:
	index = p_index


func _ready() -> void:
	rect_min_size = Vector2(260, 210)
	rect_pivot_offset = rect_min_size / 2
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGN_CENTER
	box.add_constant_override("separation", 6)
	add_child(box)

	_dot = Control.new()
	_dot.rect_min_size = Vector2(0, 76)
	_dot.connect("draw", self, "_draw_dot")
	box.add_child(_dot)

	_name = _label(box, 26, WiiTheme.TEXT)
	_status = _label(box, 18, WiiTheme.TEXT_SOFT)
	_detail = _label(box, 15, WiiTheme.TEXT_SOFT)
	refresh()


func _label(parent: Node, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.align = Label.ALIGN_CENTER
	l.add_font_override("font", Fonts.get_font(700, font_size))
	l.add_color_override("font_color", color)
	parent.add_child(l)
	return l


func _player():
	return PlayerManager.players[index]


func refresh() -> void:
	var p = _player()
	var connected: bool = p != null and p.is_connected_now()
	_name.text = tr("PLAYER_N") % (index + 1)
	if p == null:
		_status.text = tr("WAITING_PLAYER")
		_detail.text = ""
	else:
		_status.text = tr("STATUS_CONNECTED") if connected else tr("STATUS_DISCONNECTED")
		var c = p.controller
		_detail.text = "%s · %s %s" % [c.ip, tr("BATTERY"), battery_text(c.battery)]
	var style := WiiTheme.panel_style(26, PlayerManager.COLORS[index] if connected else WiiTheme.PANEL_BORDER)
	if connected:
		style.set_border_width_all(4)
	add_stylebox_override("panel", style)
	modulate.a = 1.0 if p != null else 0.75
	if connected and not _was_connected:
		_pop()
	_was_connected = connected
	_dot.update()


func _pop() -> void:
	rect_scale = Vector2(0.9, 0.9)
	if _tween != null and is_instance_valid(_tween):
		_tween.stop_all()
		_tween.queue_free()
	_tween = Anim.scale_to(self, Vector2(0.9, 0.9), Vector2.ONE, 0.35)


func _draw_dot() -> void:
	var p = _player()
	var center := Vector2(_dot.rect_size.x / 2, _dot.rect_size.y / 2)
	var col: Color = PlayerManager.COLORS[index]
	if p == null or not p.is_connected_now():
		col = col.linear_interpolate(Color("d6dce2"), 0.75)
	# Bola con brillo: base, sombra inferior y reflejo superior.
	_dot.draw_circle(center + Vector2(0, 3), 34, WiiTheme.SHADOW)
	_dot.draw_circle(center, 34, col)
	_dot.draw_circle(center + Vector2(-9, -11), 13, Color(1, 1, 1, 0.35))
	var f := Fonts.get_font(800, 34)
	var num := str(index + 1)
	var tsize := f.get_string_size(num)
	_dot.draw_string(f, center + Vector2(-tsize.x / 2, tsize.y * 0.32), num,
			Color(1, 1, 1, 1))


static func battery_text(b: int) -> String:
	match b:
		0xEE: return TranslationServer.translate("BAT_CHARGING")
		0xEF: return TranslationServer.translate("BAT_CHARGED")
		1, 2, 3, 4, 5: return TranslationServer.translate("BAT_%d" % b)
	return TranslationServer.translate("BAT_0")

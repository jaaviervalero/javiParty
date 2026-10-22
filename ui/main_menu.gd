extends Control
## Pantalla de inicio / conexión: los mandos aparecen solos en las 4 tarjetas
## mientras la búsqueda está activa. Todo se maneja con el foco de Godot, así que
## vale el mando de la tele, el teclado o el D-pad de cualquier móvil.

const SELECT_SCENE := "res://ui/minigame_select.tscn"
const QR_TEXTURE := "res://assets/controller/javiparty_qr.png"

var _cards: Array = []
var _status: Label
var _clock: Label
var _scan_btn: Button
var _lang_btn: Button
var _first_btn: Button
var _ip_dialog: Control
var _ip_edit: LineEdit
var _ip_error: Label
var _qr_dialog: Control
var _qr_btn: Button
var _refresh_timer := 0.0


func _ready() -> void:
	theme = WiiTheme.build()
	PlayerManager.ui_navigation_enabled = true
	for ip in Settings.manual_servers:
		DSUClient.add_server(ip)
	NetworkScanner.start()
	_build()
	PlayerManager.connect("player_joined", self, "_on_player_event", ["join"])
	PlayerManager.connect("player_reconnected", self, "_on_player_event", ["join"])
	PlayerManager.connect("player_left", self, "_on_player_event", ["leave"])
	_first_btn.call_deferred("grab_focus")


func _exit_tree() -> void:
	NetworkScanner.stop()


func _build() -> void:
	add_child(WiiBackground.new())

	var root := VBoxContainer.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.margin_left = 56
	root.margin_right = -56
	root.margin_top = 36
	root.margin_bottom = -40
	root.add_constant_override("separation", 18)
	add_child(root)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGN_CENTER
	title_row.add_constant_override("separation", 0)
	root.add_child(title_row)
	title_row.add_child(_title_label("javi", WiiTheme.TEXT))
	title_row.add_child(_title_label("Party", WiiTheme.ACCENT))

	var tagline := Label.new()
	tagline.text = "TAGLINE"
	tagline.align = Label.ALIGN_CENTER
	tagline.add_color_override("font_color", WiiTheme.TEXT_SOFT)
	tagline.add_font_override("font", Fonts.get_font(600, 22))
	root.add_child(tagline)

	var cards_row := HBoxContainer.new()
	cards_row.alignment = BoxContainer.ALIGN_CENTER
	cards_row.add_constant_override("separation", 22)
	cards_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cards_row)
	for i in PlayerManager.MAX_PLAYERS:
		var card := PlayerCard.new(i)
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cards_row.add_child(card)
		_cards.append(card)

	_status = Label.new()
	_status.align = Label.ALIGN_CENTER
	_status.autowrap = true
	_status.rect_min_size = Vector2(0, 56)
	_status.add_font_override("font", Fonts.get_font(600, 18))
	root.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGN_CENTER
	buttons.add_constant_override("separation", 10)
	root.add_child(buttons)
	_first_btn = _button(buttons, "BTN_PLAY", "_on_play")
	_scan_btn = _button(buttons, "BTN_SCAN_ON", "_on_toggle_scan")
	_qr_btn = _button(buttons, "BTN_QR", "_open_qr_dialog")
	_button(buttons, "BTN_MANUAL_IP", "_open_ip_dialog")
	_lang_btn = _button(buttons, "BTN_LANGUAGE", "_on_language")
	_button(buttons, "BTN_DEBUG", "toggle_debug_overlay")

	_clock = Label.new()
	_clock.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_RIGHT)
	_clock.margin_left = -130
	_clock.margin_top = -44
	_clock.margin_right = -24
	_clock.margin_bottom = -10
	_clock.align = Label.ALIGN_RIGHT
	_clock.add_color_override("font_color", WiiTheme.TEXT_SOFT)
	_clock.add_font_override("font", Fonts.get_font(600, 20))
	add_child(_clock)

	_build_ip_dialog()
	_build_qr_dialog()


func _title_label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", Fonts.get_font(800, 72))
	l.add_color_override("font_color", color)
	return l


## Los botones se conectan por nombre de método (en 3.6 no hay lambdas).
func _button(parent: Node, text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_font_override("font", Fonts.get_font(700, 19))
	b.connect("pressed", self, "_on_button_pressed", [method])
	b.connect("focus_entered", Sfx, "play", ["move"])
	parent.add_child(b)
	return b


func _on_button_pressed(method: String) -> void:
	Sfx.play("accept")
	call(method)


func toggle_debug_overlay() -> void:
	DebugOverlay.toggle()


func _build_ip_dialog() -> void:
	_ip_dialog = Control.new()
	_ip_dialog.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_ip_dialog.visible = false
	add_child(_ip_dialog)

	var dim := ColorRect.new()
	dim.color = Color(0.85, 0.9, 0.94, 0.7)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_ip_dialog.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_ip_dialog.add_child(center)
	var panel := PanelContainer.new()
	panel.rect_min_size = Vector2(520, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "MANUAL_IP_TITLE"
	title.add_font_override("font", Fonts.get_font(800, 30))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "MANUAL_IP_HINT"
	hint.add_font_override("font", Fonts.get_font(600, 17))
	hint.add_color_override("font_color", WiiTheme.TEXT_SOFT)
	box.add_child(hint)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "192.168.1.50"
	_ip_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_ip_edit.connect("text_submitted", self, "_on_ip_submitted")
	box.add_child(_ip_edit)
	_ip_error = Label.new()
	_ip_error.add_color_override("font_color", Color("d9534f"))
	_ip_error.add_font_override("font", Fonts.get_font(600, 16))
	box.add_child(_ip_error)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGN_END
	row.add_constant_override("separation", 12)
	box.add_child(row)
	_button(row, "BTN_CANCEL", "_close_ip_dialog")
	_button(row, "BTN_CONNECT", "_on_connect_ip")


func _on_ip_submitted(_text: String) -> void:
	_on_connect_ip()


## Diálogo con el QR del mando de javiParty para escanearlo con DSU Controller.
func _build_qr_dialog() -> void:
	_qr_dialog = Control.new()
	_qr_dialog.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_qr_dialog.visible = false
	add_child(_qr_dialog)
	var dim := ColorRect.new()
	dim.color = Color(0.85, 0.9, 0.94, 0.7)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_qr_dialog.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_qr_dialog.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 28)
	panel.add_child(row)
	var qr := TextureRect.new()
	qr.texture = load(QR_TEXTURE)
	qr.expand = true
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.rect_min_size = Vector2(400, 400)
	row.add_child(qr)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGN_CENTER
	box.rect_min_size = Vector2(380, 0)
	box.add_constant_override("separation", 16)
	row.add_child(box)
	var title := Label.new()
	title.text = "QR_TITLE"
	title.add_font_override("font", Fonts.get_font(800, 32))
	box.add_child(title)
	var steps := Label.new()
	steps.text = "QR_STEPS"
	steps.autowrap = true
	steps.add_font_override("font", Fonts.get_font(600, 19))
	steps.add_color_override("font_color", WiiTheme.TEXT_SOFT)
	box.add_child(steps)
	var close_row := HBoxContainer.new()
	box.add_child(close_row)
	_qr_dialog.set_meta("close", _button(close_row, "BTN_CLOSE", "_close_qr_dialog"))


func _open_qr_dialog() -> void:
	_qr_dialog.visible = true
	var close: Button = _qr_dialog.get_meta("close")
	close.grab_focus()


func _close_qr_dialog() -> void:
	_qr_dialog.visible = false
	_qr_btn.grab_focus()


func _open_ip_dialog() -> void:
	_ip_error.text = ""
	_ip_dialog.visible = true
	_ip_edit.grab_focus()


func _close_ip_dialog() -> void:
	_ip_dialog.visible = false
	_first_btn.grab_focus()


func _on_connect_ip() -> void:
	var ip: String = _ip_edit.text.strip_edges()
	if not LAN.is_ipv4(ip):
		_ip_error.text = tr("INVALID_IP")
		Sfx.play("back")
		return
	DSUClient.add_server(ip)
	Settings.add_manual_server(ip)
	_close_ip_dialog()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _ip_dialog.visible:
		Sfx.play("back")
		_close_ip_dialog()
		get_tree().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _qr_dialog.visible:
		Sfx.play("back")
		_close_qr_dialog()
		get_tree().set_input_as_handled()


func _on_play() -> void:
	get_tree().change_scene(SELECT_SCENE)


func _on_toggle_scan() -> void:
	if NetworkScanner.active:
		NetworkScanner.stop()
	else:
		NetworkScanner.start()


func _on_language() -> void:
	Settings.cycle_locale()


func _on_player_event(_p, sound: String) -> void:
	Sfx.play(sound)
	for c in _cards:
		c.refresh()


func _process(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < 0.25:
		return
	_refresh_timer = 0.0
	for c in _cards:
		c.refresh()
	_scan_btn.text = "BTN_SCAN_ON" if NetworkScanner.active else "BTN_SCAN_OFF"
	var t := OS.get_time()
	_clock.text = "%02d:%02d" % [t.hour, t.minute]
	_status.text = _status_text()


func _status_text() -> String:
	if not NetworkScanner.active:
		return tr("SCAN_IDLE")
	if NetworkScanner.sweeps > 0 and NetworkScanner.subnets.empty():
		return tr("NO_NETWORK")
	if NetworkScanner.should_warn():
		return tr("NOTHING_FOUND")
	var nets := PoolStringArray()
	for s in NetworkScanner.subnets:
		nets.append(s + "x")
	return tr("SCANNING") % ", ".join(nets) + "\n" + tr("HOW_TO_CONNECT")

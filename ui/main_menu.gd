extends Control
## Pantalla de inicio / conexión: los mandos aparecen solos en las 4 tarjetas
## mientras la búsqueda está activa. Todo se maneja con el foco de Godot, así que
## vale el mando de la tele, el teclado o el D-pad de cualquier móvil.

const SELECT_SCENE := "res://ui/minigame_select.tscn"
const QR_TEXTURE := "res://assets/controller/javiparty_qr.png"
const Qr := preload("res://ui/qr.gd")

var _cards: Array = []
var _status: Label
var _clock: Label
var _scan_btn: Button
var _lang_btn: Button
var _first_btn: Button
var _ip_dialog: Control
var _ip_edit: LineEdit
var _ip_error: Label
# Diálogo del mando web: el QR se genera al abrirlo con la URL de WebHub.
var _web_qr_dialog: Control
var _web_qr_btn: Button
var _web_qr_tex: TextureRect
var _web_qr_img := ImageTexture.new()
var _web_qr_url: Label
var _web_qr_steps: Label
var _web_qr_error: Label
# Diálogo antiguo del mando DSU: textura fija dentro de la app.
var _dsu_qr_dialog: Control
var _dsu_qr_btn: Button
var _refresh_timer := 0.0
# En el navegador no hay DSU (UDP) ni IP manual del móvil: esos botones sobran.
var _html5: bool = OS.has_feature("HTML5")


func _ready() -> void:
	theme = WiiTheme.build()
	PlayerManager.ui_navigation_enabled = true
	if not _html5:
		for ip in Settings.manual_servers:
			DSUClient.add_server(ip)
		NetworkScanner.start()
	WebHub.start()  # se queda abierto durante las partidas (los móviles siguen conectados)
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
	_status.rect_min_size = Vector2(0, 84)  # hasta tres líneas (aviso + pistas)
	_status.add_font_override("font", Fonts.get_font(600, 18))
	root.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGN_CENTER
	buttons.add_constant_override("separation", 10)
	root.add_child(buttons)
	_first_btn = _button(buttons, "BTN_PLAY", "_on_play")
	_scan_btn = _button(buttons, "BTN_SCAN_ON", "_on_toggle_scan")
	_web_qr_btn = _button(buttons, "BTN_QR", "_open_qr_dialog")
	_dsu_qr_btn = _button(buttons, "BTN_QR_DSU", "_open_dsu_qr_dialog")
	var manual_ip_btn := _button(buttons, "BTN_MANUAL_IP", "_open_ip_dialog")
	_lang_btn = _button(buttons, "BTN_LANGUAGE", "_on_language")
	_button(buttons, "BTN_DEBUG", "toggle_debug_overlay")
	if _html5:
		_scan_btn.visible = false
		_dsu_qr_btn.visible = false
		manual_ip_btn.visible = false

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
	_build_dsu_qr_dialog()


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
	# En 3.6 la señal se llama "text_entered" (no "text_submitted", que es la de 4).
	_ip_edit.connect("text_entered", self, "_on_ip_submitted")
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


## Diálogo "Escanea para jugar": QR generado con la URL del mando web. Se
## regenera cada vez que se abre porque la IP de la tele puede haber cambiado.
func _build_qr_dialog() -> void:
	_web_qr_dialog = Control.new()
	_web_qr_dialog.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_web_qr_dialog.visible = false
	add_child(_web_qr_dialog)
	var dim := ColorRect.new()
	dim.color = Color(0.85, 0.9, 0.94, 0.7)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_web_qr_dialog.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_web_qr_dialog.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 28)
	panel.add_child(row)

	# Columna izquierda: el QR, o el aviso si no hay red.
	var qr_box := VBoxContainer.new()
	qr_box.alignment = BoxContainer.ALIGN_CENTER
	qr_box.rect_min_size = Vector2(400, 400)
	qr_box.add_constant_override("separation", 12)
	row.add_child(qr_box)
	_web_qr_tex = TextureRect.new()
	_web_qr_tex.texture = _web_qr_img
	_web_qr_tex.expand = true
	_web_qr_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_web_qr_tex.rect_min_size = Vector2(400, 400)
	qr_box.add_child(_web_qr_tex)
	_web_qr_error = Label.new()
	_web_qr_error.text = "WEB_QR_NO_NETWORK"
	_web_qr_error.align = Label.ALIGN_CENTER
	_web_qr_error.autowrap = true
	_web_qr_error.add_font_override("font", Fonts.get_font(600, 22))
	_web_qr_error.add_color_override("font_color", Color("d9534f"))
	_web_qr_error.visible = false
	qr_box.add_child(_web_qr_error)

	# Columna derecha: título, URL para teclearla a mano y pasos.
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGN_CENTER
	box.rect_min_size = Vector2(380, 0)
	box.add_constant_override("separation", 16)
	row.add_child(box)
	var title := Label.new()
	title.text = "WEB_QR_TITLE"
	title.add_font_override("font", Fonts.get_font(800, 32))
	box.add_child(title)
	_web_qr_url = Label.new()
	_web_qr_url.autowrap = true
	_web_qr_url.add_font_override("font", Fonts.get_font(700, 28))
	_web_qr_url.add_color_override("font_color", WiiTheme.ACCENT_DARK)
	box.add_child(_web_qr_url)
	_web_qr_steps = Label.new()
	_web_qr_steps.text = "WEB_QR_STEPS_HTML5" if _html5 else "WEB_QR_STEPS"
	_web_qr_steps.autowrap = true
	_web_qr_steps.add_font_override("font", Fonts.get_font(600, 19))
	_web_qr_steps.add_color_override("font_color", WiiTheme.TEXT_SOFT)
	box.add_child(_web_qr_steps)
	var close_row := HBoxContainer.new()
	box.add_child(close_row)
	_web_qr_dialog.set_meta("close", _button(close_row, "BTN_CLOSE", "_close_qr_dialog"))


func _open_qr_dialog() -> void:
	var url: String = WebHub.controller_url()
	var has_url := url != ""
	_web_qr_tex.visible = has_url
	_web_qr_error.visible = not has_url
	_web_qr_url.visible = has_url
	_web_qr_steps.visible = has_url
	if has_url:
		_web_qr_url.text = url
		var img := Qr.to_image(url, 10, 4)
		if img != null:
			_web_qr_img.create_from_image(img)
			_web_qr_tex.texture = _web_qr_img
		else:
			# Texto demasiado largo para un QR (no debería pasar con una URL).
			_web_qr_tex.visible = false
			_web_qr_error.visible = true
	_web_qr_dialog.visible = true
	var close: Button = _web_qr_dialog.get_meta("close")
	close.grab_focus()


func _close_qr_dialog() -> void:
	_web_qr_dialog.visible = false
	_web_qr_btn.grab_focus()


## Diálogo con el QR del mando de javiParty para escanearlo con DSU Controller.
func _build_dsu_qr_dialog() -> void:
	_dsu_qr_dialog = Control.new()
	_dsu_qr_dialog.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_dsu_qr_dialog.visible = false
	add_child(_dsu_qr_dialog)
	var dim := ColorRect.new()
	dim.color = Color(0.85, 0.9, 0.94, 0.7)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_dsu_qr_dialog.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_dsu_qr_dialog.add_child(center)
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
	_dsu_qr_dialog.set_meta("close", _button(close_row, "BTN_CLOSE", "_close_dsu_qr_dialog"))


func _open_dsu_qr_dialog() -> void:
	_dsu_qr_dialog.visible = true
	var close: Button = _dsu_qr_dialog.get_meta("close")
	close.grab_focus()


func _close_dsu_qr_dialog() -> void:
	_dsu_qr_dialog.visible = false
	_dsu_qr_btn.grab_focus()


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
	elif event.is_action_pressed("ui_cancel") and _web_qr_dialog.visible:
		Sfx.play("back")
		_close_qr_dialog()
		get_tree().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _dsu_qr_dialog.visible:
		Sfx.play("back")
		_close_dsu_qr_dialog()
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
	if _html5:
		# En la web no hay búsqueda DSU: solo el recordatorio del mando web.
		return tr("SCAN_QR_HINT_WEB")
	var text := ""
	if not NetworkScanner.active:
		text = tr("SCAN_IDLE")
	elif NetworkScanner.sweeps > 0 and NetworkScanner.subnets.empty():
		text = tr("NO_NETWORK")
	elif NetworkScanner.should_warn():
		text = tr("NOTHING_FOUND")
	else:
		var nets := PoolStringArray()
		for s in NetworkScanner.subnets:
			nets.append(s + "x")
		text = tr("SCANNING") % ", ".join(nets) + "\n" + tr("HOW_TO_CONNECT")
	# Sin nadie conectado todavía, se recuerda que el móvil puede ser el mando.
	if PlayerManager.active_players().empty() and WebHub.is_running():
		text += "\n" + tr("SCAN_QR_HINT")
	return text

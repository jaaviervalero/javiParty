extends Control
## Selector de juego libre: cualquier minijuego del catálogo.

var _first: Button


func _ready() -> void:
	PlayerManager.ui_navigation_enabled = true
	add_child(WiiBackground.new())
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 64
	root.offset_right = -64
	root.offset_top = 40
	root.offset_bottom = -40
	root.add_theme_constant_override("separation", 22)
	add_child(root)

	var title := Label.new()
	title.text = MinigameBase.loc({"es": "Juego libre", "en": "Free play"})
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", WiiTheme.font(800))
	title.add_theme_font_size_override("font_size", 52)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	for g in MinigameRegistry.GAMES:
		var b := _button(grid, MinigameBase.loc(g.title), GameFlow.play_free.bind(g.id))
		b.custom_minimum_size = Vector2(270, 90)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _first == null:
			_first = b

	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(back_row)
	var back := _button(back_row, MinigameBase.loc({"es": "Volver", "en": "Back"}), _back)
	if _first == null:
		_first = back
	_first.grab_focus.call_deferred()


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.pressed.connect(func(): Sfx.play("accept"); cb.call())
	b.focus_entered.connect(Sfx.play.bind("move"))
	parent.add_child(b)
	return b


func _back() -> void:
	get_tree().change_scene_to_file(GameFlow.MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Sfx.play("back")
		_back()

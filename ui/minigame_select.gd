extends Control
## Selector de juego libre: rejilla de "canales" con una miniatura por minijuego y,
## abajo, la ficha del que tiene el foco (nombre e instrucciones). Recuerda el último
## juego elegido para volver a él al terminar la partida.

const GameCard := preload("res://ui/game_card.gd")
const COLUMNS := 4

static var _last_id := ""
static var _info_cache := {}  # id -> instructions (dict ES/EN)

var _cards: Array = []
var _info_title: Label
var _info_text: Label


func _ready() -> void:
	PlayerManager.ui_navigation_enabled = true
	add_child(WiiBackground.new())

	# --- Cabecera: título, jugadores y volver ---
	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 72
	header.offset_right = -72
	header.offset_top = 26
	header.add_theme_constant_override("separation", 18)
	add_child(header)
	var title := _label(MinigameBase.loc({"es": "Juego libre", "en": "Free play"}), 44, WiiTheme.TEXT, 800)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var dots := Control.new()
	dots.custom_minimum_size = Vector2(4 * 44, 56)
	dots.draw.connect(_draw_players.bind(dots))
	header.add_child(dots)
	var back := Button.new()
	back.text = MinigameBase.loc({"es": "Volver", "en": "Back"})
	back.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	back.add_theme_font_size_override("font_size", 19)
	back.pressed.connect(func() -> void: Sfx.play("back"); _back())
	back.focus_entered.connect(Sfx.play.bind("move"))
	header.add_child(back)

	# --- Rejilla de canales ---
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 56
	scroll.offset_right = -56
	scroll.offset_top = 100
	scroll.offset_bottom = -150
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	add_child(scroll)
	# Margen interior para que la tarjeta ampliada y el halo de foco no se corten.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	margin.add_child(grid)
	var focus_card: Button = null
	for g in MinigameRegistry.GAMES:
		var card: Button = GameCard.new(g)
		card.pressed.connect(_play.bind(g.id))
		card.focus_entered.connect(_on_card_focus.bind(g))
		grid.add_child(card)
		_cards.append(card)
		if focus_card == null or g.id == _last_id:
			focus_card = card

	# --- Ficha del juego con el foco ---
	var info := PanelContainer.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_left = 72
	info.offset_right = -72
	info.offset_top = -136
	info.offset_bottom = -26
	var st := WiiTheme.panel_style(26)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	info.add_theme_stylebox_override("panel", st)
	add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	info.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	_info_title = _label("", 28, WiiTheme.ACCENT_DARK, 800)
	col.add_child(_info_title)
	_info_text = _label("", 21, WiiTheme.TEXT_SOFT, 600)
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info_text)
	var hint := _label(MinigameBase.loc({"es": "A  Jugar\nB  Volver", "en": "A  Play\nB  Back"}),
			20, WiiTheme.TEXT_SOFT, 700)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)

	if focus_card:
		focus_card.grab_focus.call_deferred()
	else:
		back.grab_focus.call_deferred()
	PlayerManager.player_joined.connect(func(_p) -> void: dots.queue_redraw())
	PlayerManager.player_left.connect(func(_p) -> void: dots.queue_redraw())


func _on_card_focus(g: Dictionary) -> void:
	Sfx.play("move")
	_info_title.text = MinigameBase.loc(g.title)
	_info_text.text = MinigameBase.loc(_instructions(g))


## Instrucciones del juego: se leen de su propio _configure() (sin meterlo en el
## árbol) para no duplicar textos en el registro. Se cachean.
func _instructions(g: Dictionary) -> Dictionary:
	if not _info_cache.has(g.id):
		var node: Node = (load(g.scene) as PackedScene).instantiate()
		var d := {}
		if node.has_method("_configure"):
			node.call("_configure")
			d = node.get("instructions")
		node.free()
		_info_cache[g.id] = d
	return _info_cache[g.id]


func _play(id: String) -> void:
	_last_id = id
	Sfx.play("accept")
	GameFlow.play_free(id)


## Bolitas de los jugadores conectados, en su color y con su número.
func _draw_players(c: Control) -> void:
	var f := WiiTheme.font(800)
	var x := c.size.x - 22.0
	var list := PlayerManager.active_players()
	list.reverse()
	for p in list:
		DrawKit.player_ball(c, Vector2(x, c.size.y / 2 - 2), 17, p.color, p.index + 1, f, p.is_connected_now())
		x -= 44.0


func _label(text: String, size: int, color: Color, weight: int) -> Label:
	var l := Label.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.add_theme_font_override("font", WiiTheme.font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _back() -> void:
	get_tree().change_scene_to_file(GameFlow.MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Sfx.play("back")
		_back()

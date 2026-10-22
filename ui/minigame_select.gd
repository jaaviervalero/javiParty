extends Control
## Selector de juego libre: rejilla de "canales" con una miniatura por minijuego y,
## abajo, la ficha del que tiene el foco (nombre e instrucciones). Recuerda el último
## juego elegido para volver a él al terminar la partida (GameFlow, porque en 3.6 no
## hay static var).

const GameCard := preload("res://ui/game_card.gd")
const COLUMNS := 4

var _cards: Array = []
var _info_title: Label
var _info_text: Label


func _ready() -> void:
	theme = WiiTheme.build()
	PlayerManager.ui_navigation_enabled = true
	add_child(WiiBackground.new())

	# --- Cabecera: título, jugadores y volver ---
	var header := HBoxContainer.new()
	header.set_anchors_and_margins_preset(Control.PRESET_TOP_WIDE)
	header.margin_left = 72
	header.margin_right = -72
	header.margin_top = 26
	header.add_constant_override("separation", 18)
	add_child(header)
	var title := _label(MinigameBase.loc({"es": "Juego libre", "en": "Free play"}), 44, WiiTheme.TEXT, 800)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var dots := Control.new()
	dots.rect_min_size = Vector2(4 * 44, 56)
	dots.connect("draw", self, "_draw_players", [dots])
	header.add_child(dots)
	var back := Button.new()
	back.text = MinigameBase.loc({"es": "Volver", "en": "Back"})
	back.add_font_override("font", Fonts.get_font(700, 19))
	back.connect("pressed", self, "_on_button_pressed", ["_back"])
	back.connect("focus_entered", Sfx, "play", ["move"])
	header.add_child(back)

	# --- Rejilla de canales ---
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	scroll.margin_left = 56
	scroll.margin_right = -56
	scroll.margin_top = 100
	scroll.margin_bottom = -150
	scroll.scroll_horizontal_enabled = false
	scroll.scroll_vertical_enabled = true
	scroll.follow_focus = true
	_hide_scrollbar(scroll)
	add_child(scroll)
	# Margen interior para que la tarjeta ampliada y el halo de foco no se corten.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_constant_override("h_separation", 22)
	grid.add_constant_override("v_separation", 22)
	margin.add_child(grid)
	var focus_card: Button = null
	for g in MinigameRegistry.GAMES:
		var card: Button = GameCard.new(g)
		card.connect("pressed", self, "_play", [g.id])
		card.connect("focus_entered", self, "_on_card_focus", [g])
		grid.add_child(card)
		_cards.append(card)
		if focus_card == null or g.id == GameFlow.last_game_id:
			focus_card = card

	# --- Ficha del juego con el foco ---
	var info := PanelContainer.new()
	info.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_WIDE)
	info.margin_left = 72
	info.margin_right = -72
	info.margin_top = -136
	info.margin_bottom = -26
	var st := WiiTheme.panel_style(26)
	st.content_margin_left = 30
	st.content_margin_right = 30
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	info.add_stylebox_override("panel", st)
	add_child(info)
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 24)
	info.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGN_CENTER
	col.add_constant_override("separation", 2)
	row.add_child(col)
	_info_title = _label("", 28, WiiTheme.ACCENT_DARK, 800)
	col.add_child(_info_title)
	_info_text = _label("", 21, WiiTheme.TEXT_SOFT, 600)
	_info_text.autowrap = true
	col.add_child(_info_text)
	var hint := _label(MinigameBase.loc({"es": "A  Jugar\nB  Volver", "en": "A  Play\nB  Back"}),
			20, WiiTheme.TEXT_SOFT, 700)
	hint.align = Label.ALIGN_RIGHT
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(hint)

	if focus_card:
		focus_card.call_deferred("grab_focus")
	else:
		back.call_deferred("grab_focus")
	PlayerManager.connect("player_joined", dots, "update")
	PlayerManager.connect("player_left", dots, "update")


## En Godot 3.6 las barras del ScrollContainer llevan sus propios estilos: con
## estilos vacíos no ocupan ni se ven (el desplazamiento sigue funcionando).
func _hide_scrollbar(scroll: ScrollContainer) -> void:
	var vs := scroll.get_v_scrollbar()
	for name in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		vs.add_stylebox_override(name, StyleBoxEmpty.new())


func _on_button_pressed(method: String) -> void:
	Sfx.play("accept")
	call(method)


func _on_card_focus(g: Dictionary) -> void:
	Sfx.play("move")
	_info_title.text = MinigameBase.loc(g.title)
	_info_text.text = MinigameBase.loc(_instructions(g))


## Instrucciones del juego: se leen de su propio _configure() (sin meterlo en el
## árbol) para no duplicar textos en el registro. Se cachean.
func _instructions(g: Dictionary) -> Dictionary:
	if not GameFlow.info_cache.has(g.id):
		var node: Node = (load(g.scene) as PackedScene).instance()
		var d := {}
		if node.has_method("_configure"):
			node.call("_configure")
			d = node.get("instructions")
		node.free()
		GameFlow.info_cache[g.id] = d
	return GameFlow.info_cache[g.id]


func _play(id: String) -> void:
	GameFlow.last_game_id = id
	Sfx.play("accept")
	GameFlow.play_free(id)


## Bolitas de los jugadores conectados, en su color y con su número.
func _draw_players(c: Control) -> void:
	var x := c.rect_size.x - 22.0
	var list := PlayerManager.active_players()
	list.invert()
	for p in list:
		DrawKit.player_ball(c, Vector2(x, c.rect_size.y / 2 - 2), 17, p.color, p.index + 1,
				800, p.is_connected_now())
		x -= 44.0


func _label(text: String, size: int, color: Color, weight: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", Fonts.get_font(weight, size))
	l.add_color_override("font_color", color)
	return l


func _back() -> void:
	get_tree().change_scene(GameFlow.MENU_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Sfx.play("back")
		_back()

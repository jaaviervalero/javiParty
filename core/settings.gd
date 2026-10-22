extends Node
## Autoload "Settings": ajustes persistentes, idioma, acciones de entrada y tema.

const PATH := "user://settings.cfg"

var locale := ""                       # "" = idioma del sistema
var debug_overlay := false
var manual_servers := PackedStringArray()  # IPs añadidas a mano, se reconectan al arrancar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for t in Strings.build_translations():
		TranslationServer.add_translation(t)
	_load()
	apply_locale()
	_setup_input()
	# El tema va DENTRO del tema por defecto de Godot: el de la ventana raíz solo se
	# hereda si todos los padres son Control/Window, y los HUD cuelgan de CanvasLayer.
	var theme := WiiTheme.build()
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = theme.default_font
	ThemeDB.get_default_theme().default_font_size = theme.default_font_size
	get_tree().root.theme = theme


func apply_locale() -> void:
	var loc := locale
	if loc == "":
		loc = "es" if OS.get_locale_language() == "es" else "en"
	TranslationServer.set_locale(loc)


func current_locale() -> String:
	return TranslationServer.get_locale().substr(0, 2)


func cycle_locale() -> void:
	locale = "en" if current_locale() == "es" else "es"
	apply_locale()
	save()


func add_manual_server(ip: String) -> void:
	if not manual_servers.has(ip):
		manual_servers.append(ip)
		save()


func _setup_input() -> void:
	# Mando de la tele: el D-pad y OK ya llegan como ui_* (flechas/Enter).
	_add_key("ui_accept", KEY_KP_ENTER)
	_add_action("debug_toggle")
	_add_key("debug_toggle", KEY_F3)
	_add_key("debug_toggle", KEY_MENU)


func _add_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _add_key(action: String, keycode: Key) -> void:
	_add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	InputMap.action_add_event(action, ev)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	locale = cfg.get_value("general", "locale", "")
	debug_overlay = cfg.get_value("general", "debug_overlay", false)
	manual_servers = cfg.get_value("network", "manual_servers", PackedStringArray())


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("general", "locale", locale)
	cfg.set_value("general", "debug_overlay", debug_overlay)
	cfg.set_value("network", "manual_servers", manual_servers)
	cfg.save(PATH)

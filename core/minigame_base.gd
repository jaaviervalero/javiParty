class_name MinigameBase
extends Node2D
## Base de TODOS los minijuegos. Se encarga de lo común para que cada juego solo
## programe su lógica:
##   INTRO      título, instrucción de una frase y controles; empieza cuando todos
##              pulsan A (o a los INTRO_AUTOSTART_SEC, o con OK en el mando de la tele)
##   COUNTDOWN  3, 2, 1, ¡YA!
##   PLAYING    llama a _game_process(delta) cada frame; cuenta atrás de `duration`
##   RESULTS    clasificación; A (o tiempo) para seguir
## + pausa (Continuar / Salir) con el botón + de cualquier móvil o "atrás" en la tele.
##
## Un juego hereda de esto y SOLO sobrescribe los hooks (_configure, _setup,
## _game_start, _game_process, _game_end). No debe definir _ready/_process/_input.
## Normas completas: docs/MINIJUEGOS.md

signal finished(placements)

enum State { INTRO, COUNTDOWN, PLAYING, RESULTS }

const INTRO_AUTOSTART_SEC := 12.0
const RESULTS_AUTOCONTINUE_SEC := 12.0
const HUD_HEIGHT := 84.0
## Zona de juego por defecto (debajo del HUD, con margen).
const ARENA := Rect2(32, 96, 1216, 600)

# --- Configuración (rellenar en _configure) ---
var title := {"es": "", "en": ""}
## UNA frase que explica el juego.
var instructions := {"es": "", "en": ""}
## Controles que se muestran en la intro: [[control, {"es": ..., "en": ...}], ...]
## donde control es Pad.A, Pad.B, Pad.UP... o "stick" / "dpad".
var controls: Array = []
## Duración en segundos (30-60 normalmente, máximo 90). Siempre hay límite: los
## juegos de eliminación llaman a finish() antes si ya hay ganador.
var duration := 45.0
## true si gana el que tiene MENOS puntuación (p. ej. tiempos).
var lower_is_better := false
## Mostrar las píldoras de puntuación en el HUD.
var show_scores := true
## Fondo claro estándar detrás del juego.
var use_default_background := true

# --- Estado (leer desde el juego) ---
var players: Array = []
var scores := {}  # player.index -> número
var state: int = State.INTRO
var time_left := 0.0
var elapsed := 0.0  # segundos jugados (solo cuenta en PLAYING)
var paused := false

var _hud: CanvasLayer
var _overlay: Control
var _timer_label: Label
var _ready_flags := {}
var _state_time := 0.0
var _last_tick := -1
var _placements: Array = []
var _pause_box: Control
var _scenery: Node2D


# =====================================================================
# Hooks para los juegos
# =====================================================================

## Rellena title, instructions, controls, duration... No uses `players` aquí.
func _configure() -> void:
	pass

## Crea el escenario. `players` ya está relleno (1 a 4 jugadores).
func _setup() -> void:
	pass

## Justo al terminar la cuenta atrás.
func _game_start() -> void:
	pass

## Cada frame mientras se juega (no se llama en pausa ni fuera de PLAYING).
func _game_process(_delta: float) -> void:
	pass

## Al acabar (por tiempo o por finish()), antes de calcular la clasificación.
## Último momento para ajustar `scores`.
func _game_end() -> void:
	pass

## Texto de la puntuación en el HUD y en los resultados.
func format_score(value) -> String:
	return str(int(value))

## Escenario ESTÁTICO (cielo, suelo, decorado, panel de la arena...). Se dibuja una
## vez, detrás de _draw(), y solo se repite al llamar a redraw_scenery(). Dibuja sobre
## `ci` (ci.draw_rect..., DrawKit.cloud(ci, ...)), no sobre self. Así _draw(), que va
## cada frame, solo pinta lo que se mueve: clave para que vaya fluido en la tele.
func _draw_scenery(_ci: CanvasItem) -> void:
	pass


# =====================================================================
# API para los juegos
# =====================================================================

func is_playing() -> bool:
	return state == State.PLAYING and not paused


## Sin tipo a propósito: con `amount := 1` GDScript lo fija a int y truncaría
## puntuaciones decimales (tiempos, errores...).
func add_score(p: Player, amount = 1) -> void:
	scores[p.index] = scores.get(p.index, 0) + amount


func set_score(p: Player, value) -> void:
	scores[p.index] = value


func get_score(p: Player):
	return scores.get(p.index, 0)


## Vuelve a dibujar el escenario estático (si ha cambiado algo de él).
func redraw_scenery() -> void:
	_scenery.update()


## Termina la partida ya (p. ej. solo queda uno vivo).
func finish() -> void:
	if state != State.PLAYING:
		return
	_enter_results()


## Texto según el idioma actual: loc({"es": "Hola", "en": "Hi"}).
static func loc(d: Dictionary) -> String:
	return d.get(TranslationServer.get_locale().substr(0, 2), d.get("es", ""))


## Fuente del juego (Nunito). En Godot 3.6 el tamaño va dentro de la fuente.
func font(weight := 800, size := 24) -> DynamicFont:
	return Fonts.get_font(weight, size)


## Dibuja un texto centrado en `center` (para usar dentro de _draw).
func draw_text_centered(text: String, center: Vector2, size: int, color: Color, weight := 800) -> void:
	var f := font(weight, size)
	var ts := f.get_string_size(text)
	draw_string(f, center + Vector2(-ts.x / 2, ts.y * 0.32), text, color)


# =====================================================================
# Máquina de estados (no tocar desde los juegos)
# =====================================================================

func _ready() -> void:
	_configure()
	duration = clamp(duration, 5.0, 90.0)
	players = PlayerManager.active_players()
	for p in players:
		scores[p.index] = 0
	PlayerManager.ui_navigation_enabled = false
	if use_default_background:
		var bg_layer := CanvasLayer.new()
		bg_layer.layer = -1
		bg_layer.add_child(WiiBackground.new())
		add_child(bg_layer)
	# Capa del escenario estático: hija que se pinta detrás del propio juego.
	_scenery = Node2D.new()
	_scenery.show_behind_parent = true
	_scenery.connect("draw", self, "_draw_scenery_bound", [_scenery])
	add_child(_scenery)
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	_setup()
	_enter_intro()


func _draw_scenery_bound(ci: CanvasItem) -> void:
	_draw_scenery(ci)


func _exit_tree() -> void:
	PlayerManager.ui_navigation_enabled = true


func _process(delta: float) -> void:
	_state_time += delta
	match state:
		State.INTRO:
			_process_intro()
		State.COUNTDOWN:
			_process_countdown()
		State.PLAYING:
			_process_playing(delta)
		State.RESULTS:
			_process_results()
	update()
	_hud_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Mando de la tele / teclado: OK avanza, "atrás" pausa.
	if event.is_action_pressed("ui_accept"):
		match state:
			State.INTRO:
				_enter_countdown()
			State.RESULTS:
				_continue()
			State.PLAYING:
				if paused:
					_set_paused(false)
	elif event.is_action_pressed("ui_cancel"):
		if state == State.PLAYING:
			if paused:
				_quit_to_menu()
			else:
				_set_paused(true)
		elif state == State.INTRO:
			_quit_to_menu()


# --- INTRO ---

func _enter_intro() -> void:
	state = State.INTRO
	_state_time = 0.0
	_ready_flags.clear()
	_overlay = _make_panel_overlay()
	var box: VBoxContainer = _overlay.get_meta("box")
	box.add_child(_label(loc(title), 52, WiiTheme.TEXT, 800))
	box.add_child(_label(loc(instructions), 24, WiiTheme.TEXT_SOFT, 600, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("hseparation", 18)
	grid.add_constant_override("vseparation", 10)
	for c in controls:
		grid.add_child(_control_pill(c[0]))
		grid.add_child(_label(loc(c[1]), 22, WiiTheme.TEXT, 600))
	var center := CenterContainer.new()
	center.add_child(grid)
	box.add_child(center)
	var ready_row := HBoxContainer.new()
	ready_row.alignment = BoxContainer.ALIGN_CENTER
	ready_row.add_constant_override("separation", 14)
	ready_row.name = "ReadyRow"
	box.add_child(ready_row)
	box.add_child(_label(loc({"es": "Pulsad A cuando estéis listos", "en": "Press A when you're ready"}),
			20, WiiTheme.ACCENT_DARK, 700))
	_refresh_ready_row()


func _process_intro() -> void:
	for p in players:
		if p.just_pressed(Pad.A) and not _ready_flags.has(p.index):
			_ready_flags[p.index] = true
			Sfx.play("accept")
			_refresh_ready_row()
	var all_ready := true
	for p in players:
		if p.is_connected_now() and not _ready_flags.has(p.index):
			all_ready = false
	if (all_ready and not _ready_flags.empty()) or _state_time > INTRO_AUTOSTART_SEC:
		_enter_countdown()


func _refresh_ready_row() -> void:
	if _overlay == null:
		return
	var row: HBoxContainer = _overlay.find_node("ReadyRow", true, false)
	if row == null:
		return
	for c in row.get_children():
		c.queue_free()
	for p in players:
		var dot := Panel.new()
		dot.rect_min_size = Vector2(44, 44)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(22)
		st.bg_color = p.color if _ready_flags.has(p.index) else p.color.linear_interpolate(Color(1, 1, 1, 1), 0.75)
		st.border_color = p.color
		st.set_border_width_all(3)
		dot.add_stylebox_override("panel", st)
		var l := _label(str(p.index + 1), 22, Color(1, 1, 1, 1), 800)
		l.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		l.valign = Label.VALIGN_CENTER
		dot.add_child(l)
		row.add_child(dot)


# --- COUNTDOWN ---

func _enter_countdown() -> void:
	if state != State.INTRO:
		return
	_free_overlay()
	state = State.COUNTDOWN
	_state_time = 0.0
	_last_tick = -1


func _process_countdown() -> void:
	var step := int(_state_time / 0.75)
	if step != _last_tick:
		_last_tick = step
		if step < 3:
			_big_flash(str(3 - step), WiiTheme.TEXT)
			Sfx.play("move", 0.8)
		elif step == 3:
			_big_flash(loc({"es": "¡YA!", "en": "GO!"}), WiiTheme.ACCENT)
			Sfx.play("accept")
			state = State.PLAYING
			time_left = duration
			elapsed = 0.0
			_game_start()


# --- PLAYING ---

func _process_playing(delta: float) -> void:
	for p in players:
		if p.just_pressed(Pad.PLUS):
			_set_paused(not paused)
			return
	if paused:
		for p in players:
			if p.just_pressed(Pad.A):
				_set_paused(false)
			elif p.just_pressed(Pad.B):
				_quit_to_menu()
		return
	time_left = max(0.0, time_left - delta)
	elapsed += delta
	var secs: int = int(ceil(time_left))
	if secs <= 5 and secs != _last_tick and secs > 0:
		_last_tick = secs
		Sfx.play("move", 1.4)
	_game_process(delta)
	if state == State.PLAYING and time_left <= 0.0:
		_enter_results()


func _set_paused(value: bool) -> void:
	paused = value
	if _pause_box:
		_pause_box.queue_free()
		_pause_box = null
	if paused:
		Sfx.play("back")
		_pause_box = _make_panel_overlay()
		var box: VBoxContainer = _pause_box.get_meta("box")
		box.add_child(_label(loc({"es": "Pausa", "en": "Paused"}), 48, WiiTheme.TEXT, 800))
		box.add_child(_label(loc({"es": "A: continuar  ·  B: salir al menú", "en": "A: resume  ·  B: quit to menu"}),
				24, WiiTheme.TEXT_SOFT, 600))
	else:
		Sfx.play("accept")


# --- RESULTS ---

func _enter_results() -> void:
	state = State.RESULTS
	_state_time = 0.0
	_game_end()
	_placements = compute_placements()
	Sfx.play("star")
	_overlay = _make_panel_overlay()
	var box: VBoxContainer = _overlay.get_meta("box")
	box.add_child(_label(loc({"es": "Resultados", "en": "Results"}), 46, WiiTheme.TEXT, 800))
	for r in _placements:
		box.add_child(_result_row(r))
	box.add_child(_label(loc({"es": "Pulsa A para continuar", "en": "Press A to continue"}),
			20, WiiTheme.ACCENT_DARK, 700))


## Clasificación: [{player, place (1..4), score}] ordenada por puesto.
## Los empates comparten puesto.
func compute_placements() -> Array:
	var sorted: Array = players.duplicate()
	sorted.sort_custom(self, "_compare_players")
	var out: Array = []
	var place := 0
	var prev = null
	for i in sorted.size():
		var p: Player = sorted[i]
		var s = get_score(p)
		if i == 0 or s != prev:
			place = i + 1
		prev = s
		out.append({"player": p, "place": place, "score": s})
	return out


func _compare_players(a: Player, b: Player) -> bool:
	var sa = get_score(a)
	var sb = get_score(b)
	if sa == sb:
		return a.index < b.index
	return sa < sb if lower_is_better else sa > sb


func _process_results() -> void:
	if _state_time < 1.0:
		return  # que nadie se lo salte sin querer
	for p in players:
		if p.just_pressed(Pad.A):
			_continue()
			return
	if _state_time > RESULTS_AUTOCONTINUE_SEC:
		_continue()


func _continue() -> void:
	if state != State.RESULTS or _state_time < 1.0:
		return
	state = State.INTRO  # evita dobles llamadas mientras cambia la escena
	Sfx.play("accept")
	emit_signal("finished", _placements)
	if not Settings.headless_test:
		GameFlow.minigame_done(_placements)


func _quit_to_menu() -> void:
	if Settings.headless_test:
		return
	Sfx.play("back")
	GameFlow.quit_to_menu()


# =====================================================================
# HUD y overlays
# =====================================================================

func _hud_redraw() -> void:
	if not _hud.has_meta("canvas"):
		var c := Control.new()
		c.set_anchors_and_margins_preset(Control.PRESET_WIDE)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.connect("draw", self, "_draw_hud_bound", [c])
		_hud.add_child(c)
		_hud.move_child(c, 0)
		_hud.set_meta("canvas", c)
	var canvas: Control = _hud.get_meta("canvas")
	canvas.update()


func _draw_hud_bound(c: Control) -> void:
	_draw_hud(c)


func _draw_hud(c: Control) -> void:
	if state == State.INTRO:
		return
	# Título a la izquierda
	var f_title := Fonts.get_font(800, 30)
	c.draw_string(f_title, Vector2(36, 58), loc(title), WiiTheme.TEXT, 420)
	# Tiempo en el centro
	var secs: int = int(ceil(time_left)) if state != State.COUNTDOWN else int(duration)
	var t_rect := Rect2(640 - 60, 22, 120, 52)
	var warn: bool = secs <= 5 and state == State.PLAYING
	var st := WiiTheme.panel_style(26, Color("e25555") if warn else WiiTheme.PANEL_BORDER)
	st.set_border_width_all(3)
	c.draw_style_box(st, t_rect)
	var txt := str(secs)
	var f_time := Fonts.get_font(800, 32)
	var ts := f_time.get_string_size(txt)
	c.draw_string(f_time, Vector2(640 - ts.x / 2, 60), txt,
			Color("e25555") if warn else WiiTheme.TEXT)
	# Puntuaciones a la derecha
	if not show_scores:
		return
	var f_score := Fonts.get_font(800, 24)
	var f_num := Fonts.get_font(800, 18)
	var x := 1250.0
	for i in range(players.size() - 1, -1, -1):
		var p: Player = players[i]
		var s: String = format_score(get_score(p))
		var w: float = f_score.get_string_size(s).x + 70
		x -= w
		var ps := WiiTheme.panel_style(24, p.color if p.is_connected_now() else WiiTheme.PANEL_BORDER)
		ps.set_border_width_all(3)
		c.draw_style_box(ps, Rect2(x, 24, w, 48))
		c.draw_circle(Vector2(x + 26, 48), 15, p.color)
		var n := str(p.index + 1)
		var ns := f_num.get_string_size(n)
		c.draw_string(f_num, Vector2(x + 26 - ns.x / 2, 55), n, Color(1, 1, 1, 1))
		c.draw_string(f_score, Vector2(x + 50, 57), s, p.color.darkened(0.2))
		x -= 10


func _make_panel_overlay() -> Control:
	var root := Control.new()
	root.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	var dim := ColorRect.new()
	dim.color = Color(0.9, 0.93, 0.96, 0.75)
	dim.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.rect_min_size = Vector2(640, 0)
	var st := WiiTheme.panel_style(30)
	st.content_margin_left = 32
	st.content_margin_right = 32
	st.content_margin_top = 32
	st.content_margin_bottom = 32
	panel.add_stylebox_override("panel", st)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_constant_override("separation", 16)
	panel.add_child(box)
	root.set_meta("box", box)
	_hud.add_child(root)
	panel.rect_pivot_offset = Vector2(320, 150)
	Anim.scale_to(panel, Vector2(0.92, 0.92), Vector2.ONE, 0.3)
	return root


func _free_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _label(text: String, size: int, color: Color, weight := 600, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.align = Label.ALIGN_CENTER
	l.add_font_override("font", Fonts.get_font(weight, size))
	l.add_color_override("font_color", color)
	if wrap:
		l.autowrap = true
		l.rect_min_size = Vector2(576, 0)
	return l


func _control_pill(control) -> Control:
	# Sin flechas ni símbolos raros: Nunito no los tiene y en la tele saldrían cuadros.
	var names := {Pad.A: "A", Pad.B: "B", Pad.UP: loc({"es": "Arriba", "en": "Up"}),
		Pad.DOWN: loc({"es": "Abajo", "en": "Down"}), Pad.LEFT: loc({"es": "Izquierda", "en": "Left"}),
		Pad.RIGHT: loc({"es": "Derecha", "en": "Right"}),
		Pad.MINUS: "-", Pad.PLUS: "+", "stick": loc({"es": "Stick", "en": "Stick"}),
		"dpad": loc({"es": "Cruceta", "en": "D-pad"})}
	var text: String = names.get(control, str(control))
	var panel := PanelContainer.new()
	var st := WiiTheme.panel_style(20, WiiTheme.ACCENT)
	st.bg_color = Color("8e4ec6") if control is int and control == Pad.A else WiiTheme.ACCENT_LIGHT
	st.shadow_size = 0
	st.content_margin_left = 6
	st.content_margin_right = 6
	st.content_margin_top = 6
	st.content_margin_bottom = 6
	st.content_margin_left = 16
	st.content_margin_right = 16
	panel.add_stylebox_override("panel", st)
	panel.add_child(_label(text, 20, Color(1, 1, 1, 1) if control is int and control == Pad.A else WiiTheme.ACCENT_DARK, 800))
	return panel


func _result_row(r: Dictionary) -> Control:
	var p: Player = r.player
	var row := PanelContainer.new()
	var st := WiiTheme.panel_style(22, p.color)
	st.set_border_width_all(3)
	st.shadow_size = 2
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	st.content_margin_left = 18
	st.content_margin_right = 18
	row.add_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 16)
	row.add_child(h)
	var place := _label("%dº" % r.place, 30, p.color.darkened(0.15), 800)
	place.rect_min_size = Vector2(60, 0)
	h.add_child(place)
	var name_l := _label(loc({"es": "Jugador %d", "en": "Player %d"}) % (p.index + 1), 26, WiiTheme.TEXT, 700)
	name_l.align = Label.ALIGN_LEFT
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_l)
	h.add_child(_label(format_score(r.score), 26, WiiTheme.TEXT_SOFT, 700))
	return row


func _big_flash(text: String, color: Color) -> void:
	# Ocupa toda la pantalla con el texto centrado, y escala desde el centro.
	var l := _label(text, 140, color, 800)
	l.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.rect_pivot_offset = get_viewport_rect().size / 2
	_hud.add_child(l)
	l.rect_scale = Vector2(1.6, 1.6)
	Anim.scale_to(l, Vector2(1.6, 1.6), Vector2.ONE, 0.25)
	Anim.fade_out(l, 0.4, 0.15)

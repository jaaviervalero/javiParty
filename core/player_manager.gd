extends Node
## Autoload "PlayerManager": asocia mandos DSU a jugadores 1-4.
##
## - Un mando nuevo ocupa el primer hueco libre.
## - Si un mando se desconecta, el jugador conserva su hueco y su puntuación;
##   si el mismo dispositivo (MAC, o IP+slot) vuelve, recupera su jugador.
## - Mientras ui_navigation_enabled, el D-pad/A/B de cualquier móvil mueve la UI
##   como el mando de la tele, y HOME abre/cierra el overlay de depuración.
##   Los botones son los lógicos de Pad (ya traducidos según el diseño del móvil).

signal player_joined(player)
signal player_left(player)         # desconexión (el hueco se mantiene)
signal player_reconnected(player)
signal player_removed(player)      # hueco liberado

const MAX_PLAYERS := 4
# Paleta propia por jugador: azul, rojo, verde, naranja.
const COLORS := [
	Color("2fa8e0"), Color("ec5a5a"), Color("4cbf6b"), Color("f2a33a"),
]

var players: Array = [null, null, null, null]
var ui_navigation_enabled := true

# En los menús el móvil va en vertical: cruceta para moverse, A acepta, B atrás.
var _NAV := {
	Pad.UP: "ui_up",
	Pad.DOWN: "ui_down",
	Pad.LEFT: "ui_left",
	Pad.RIGHT: "ui_right",
	Pad.A: "ui_accept",
	Pad.B: "ui_cancel",
}


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	process_priority = -90  # después de DSUClient, antes que las escenas
	DSUClient.connect("controller_connected", self, "_on_controller_connected")
	DSUClient.connect("controller_disconnected", self, "_on_controller_disconnected")


func active_players() -> Array:
	var out: Array = []
	for p in players:
		if p != null:
			out.append(p)
	return out


func connected_players() -> Array:
	var out: Array = []
	for p in players:
		if p != null and p.is_connected_now():
			out.append(p)
	return out


func remove_player(index: int) -> void:
	var p = players[index]
	if p == null:
		return
	players[index] = null
	emit_signal("player_removed", p)


func _on_controller_connected(ctrl) -> void:
	var id: String = ctrl.device_id()
	# 1) El mismo mando (misma IP:puerto#slot) que ya tenía jugador: vuelve al suyo.
	#    Va primero porque es la identidad segura (p. ej. la MAC llegó tarde).
	for p in players:
		if p != null and p.controller == ctrl:
			p.device_id = id
			emit_signal("player_reconnected", p)
			return
	# 2) Mismo dispositivo con otro mando (cambió de IP): solo si ese jugador está
	#    DESCONECTADO. La app DSU Controller de iPhone manda la misma MAC inventada
	#    en todos los móviles (iOS no da la real), así que la MAC no basta: sin esta
	#    condición el móvil de un amigo le quitaba el jugador 1 al que ya jugaba.
	for p in players:
		if p != null and p.device_id == id and not p.is_connected_now():
			p.controller = ctrl
			emit_signal("player_reconnected", p)
			return
	for i in MAX_PLAYERS:
		if players[i] == null:
			var p := Player.new(i, COLORS[i], tr("PLAYER_N") % (i + 1))
			p.device_id = id
			p.controller = ctrl
			players[i] = p
			emit_signal("player_joined", p)
			return
	# Más de 4 mandos: se ignora (sigue visible en el overlay de depuración).


func _on_controller_disconnected(ctrl) -> void:
	for p in players:
		if p != null and p.controller == ctrl:
			emit_signal("player_left", p)


func _process(_delta: float) -> void:
	for p in players:
		if p != null:
			p.update_buttons()
	if ui_navigation_enabled:
		_phone_ui_navigation()
	for p in players:
		if p != null and p.just_pressed(Pad.HOME):
			DebugOverlay.toggle()


## Traduce botones de los móviles a acciones ui_* para que la UI se maneje
## igual con el mando de la tele, el teclado o cualquier móvil.
func _phone_ui_navigation() -> void:
	for p in players:
		if p == null:
			continue
		for bit in _NAV:
			if p.just_pressed(bit):
				_fire_action(_NAV[bit], true)
			elif p.just_released(bit):
				_fire_action(_NAV[bit], false)


func _fire_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

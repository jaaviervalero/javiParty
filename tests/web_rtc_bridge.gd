extends SceneTree
## Tests headless del puente WebRTC del mando web (web_rtc_bridge.gd) y de su
## integración con WebHub, SIN navegador ni red:
##   cd /home/javier/Projects/javiParty-web && timeout 60 godot3 --headless --path . -s tests/web_rtc_bridge.gd
##
## Se inyecta un jpNet falso (misma interfaz que window.jpNet) en el puente, y el
## puente en WebHub con start_with(). Así se prueban la sala de 4 letras, el
## reparto de eventos (connect/msg/disconnect) y el protocolo de siempre
## (hello -> welcome, in, disconnect) sin abrir puertos.
## Sale con código 0 si todo pasa y 1 si algo falla.

## No se preload-ea web_hub.gd: referencia MinigameBase, que en modo `-s` falla
## al preload ("Fonts isn't declared in the current scope"). Se usa el autoload.
const WebRtcBridge := preload("res://net/web_rtc_bridge.gd")

const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const MENU_CONTROLS := [["dpad", ""], ["A", ""], ["B", ""]]
const UID_A := "mobile-gggg-0007"


## jpNet falso: encola eventos y apunta lo que le piden. Los métodos son los
## mismos que la interfaz de la página (ver net/web_rtc_bridge.gd).
class FakeJpNet:
	var events: Array = []
	var started: Array = []   # salas con las que se llamó a start()
	var sent: Array = []      # [{"peer": int, "text": String}]
	var closed: Array = []    # peers cerrados
	var stopped := false
	var state := "connecting"
	var raw_override = null   # si no es null, poll() devuelve esto tal cual
	var none_mode := false    # simula jpNet.poll() === undefined/null

	func start(room: String) -> void:
		started.append(room)

	func poll():
		if none_mode:
			return null
		if raw_override != null:
			return str(raw_override)
		var out := to_json(events)
		events = []
		return out

	func send(peer: int, text: String) -> void:
		sent.append({"peer": peer, "text": text})

	func close(peer: int) -> void:
		closed.append(peer)

	func stop() -> void:
		stopped = true

	func status() -> String:
		return state


var _wh = null
var _pm = null
var _fake = null
var _bridge = null
var _ev: Array = []

var _checks_ok := 0
var _checks_fail := 0
var _cases_total := 0
var _cases_ok := 0
var _cases_fail := 0
var _case_name := ""
var _case_failed := false


func _init() -> void:
	_run()


func _run() -> void:
	# Deja que los autoloads (WebHub, PlayerManager) hagan su _ready.
	yield(self, "idle_frame")
	_wh = root.get_node("WebHub")
	_pm = root.get_node("PlayerManager")
	_wh.connect("controller_connected", self, "_ev_wh_connected")
	_wh.connect("controller_disconnected", self, "_ev_wh_disconnected")
	_wh.connect("controller_updated", self, "_ev_wh_updated")
	_pm.connect("player_joined", self, "_ev_pm_joined")
	_pm.connect("player_left", self, "_ev_pm_left")

	test_room()
	test_hello()
	test_input()
	test_disconnect()
	test_without_js()
	test_broken_poll()

	_finish()


# --- Casos ---

func test_room() -> void:
	_start("sala de 4 letras sin ambigüedades generada en start()")
	var r: String = _bridge.room
	check(_bridge.start(), "start() devuelve true")
	check(_bridge.is_running(), "is_running() true aunque jpNet tarde")
	check(r.length() == 4, "la sala tiene 4 letras (%s)" % r)
	var valid := true
	for i in r.length():
		if ROOM_ALPHABET.find(r[i]) < 0:
			valid = false
	check(valid, "solo letras válidas, sin I ni O")
	check(_fake.started.size() == 1 and str(_fake.started[0]) == r,
			"jpNet.start() recibe la sala una vez")
	check(_bridge.status() == "connecting", "status() es el de jpNet")

	_wh.start_with(_bridge)
	check(_wh.is_running(), "WebHub arranca con el puente")
	check(_wh.room() == r, "WebHub.room() devuelve la misma sala")
	check(_wh.transport_status() == "connecting", "WebHub.transport_status() delega")
	_bridge.start()
	check(_fake.started.size() == 1, "start() dos veces no vuelve a arrancar jpNet")
	_end()


func test_hello() -> void:
	_start("connect + hello -> controller_connected, welcome y layout por jpNet.send")
	_fake.events = [
		{"e": "connect", "peer": 1, "ip": ""},
		{"e": "msg", "peer": 1, "text": to_json({"t": "hello", "id": UID_A, "v": 1})},
	]
	_bridge.poll()

	var pad = _wh.pads.get(UID_A)
	check(pad != null, "se crea el WebPad")
	if pad != null:
		check(pad.connected and pad.peer == 1, "el pad queda conectado al peer 1")
	check(_has_event("wh_connected:" + UID_A), "WebHub emite controller_connected")
	check(_pm.players[0] != null and _pm.players[0].controller == pad,
			"PlayerManager le da el jugador 1")

	var w := _one("welcome", 1)
	check(not w.empty(), "el móvil recibe welcome por jpNet.send")
	if not w.empty():
		check(int(w.get("player", 0)) == 1, "welcome: jugador 1")
		check(str(w.get("color", "")) != "", "welcome: color")
	check(_one("layout", 1).size() > 0, "y el layout del mando")
	_end()


func test_input() -> void:
	_start("msg 'in' -> el WebPad refleja los botones y emite controller_updated")
	_hello(1, UID_A)
	var pad = _wh.pads.get(UID_A)
	if pad == null:
		check(false, "no se creó el WebPad")
		_end()
		return

	var bits: int = Pad.UP | Pad.A | Pad.TWO
	_fake.events = [{"e": "msg", "peer": 1,
			"text": to_json({"t": "in", "b": bits, "x": 0.5, "y": -0.25, "n": 1})}]
	_fake.sent = []
	_bridge.poll()
	check(pad.buttons == bits, "buttons = UP|A|2")
	check(_near(pad.left_stick.x, 0.5) and _near(pad.left_stick.y, -0.25),
			"left_stick = (0.5, -0.25)")
	check(_has_event("wh_updated:" + UID_A), "WebHub emite controller_updated")
	check(_messages("welcome").empty(), "no se reenvía welcome")
	_end()


func test_disconnect() -> void:
	_start("disconnect -> controller_disconnected y el pad queda desconectado")
	_hello(1, UID_A)
	var pad = _wh.pads.get(UID_A)
	if pad == null:
		check(false, "no se creó el WebPad")
		_end()
		return

	_fake.events = [{"e": "disconnect", "peer": 1}]
	_fake.sent = []
	_bridge.poll()
	check(not pad.connected, "el pad queda desconectado")
	check(_has_event("wh_disconnected:" + UID_A), "WebHub emite controller_disconnected")
	check(_has_event("pm_left:0"), "PlayerManager conserva el hueco y avisa")
	check(_wh._peer_pad.empty(), "el peer se olvida")
	check(_wh.pads.has(UID_A), "el WebPad sigue para reconectar")
	_end()


func test_without_js() -> void:
	_start("sin jpNet (fuera del navegador): start/poll/send/close no rompen")
	var fake := FakeJpNet.new()
	var bridge := WebRtcBridge.new()  # js_api = null y no es HTML5
	check(bridge.start(), "start() devuelve true")
	check(bridge.is_running(), "is_running() true (estado connecting)")
	check(bridge.room.length() == 4, "la sala se genera igualmente")
	check(bridge.status() == "waiting-js", "status() = waiting-js")
	bridge.poll()  # no debe romper
	bridge.send(1, "hola")
	bridge.close(1)
	check(bridge.status() == "waiting-js", "sigue esperando a jpNet")
	check(bridge.is_running(), "y sigue en marcha")

	# jpNet aparece después (net.js termina de cargar): se arranca con la sala.
	fake.events = [{"e": "connect", "peer": 2, "ip": ""}]
	bridge.js_api = fake
	bridge.poll()
	check(fake.started.size() == 1 and str(fake.started[0]) == bridge.room,
			"al aparecer jpNet se llama a start(room)")
	check(bridge.status() == "connecting", "status() pasa a ser el de jpNet")
	_end()


func test_broken_poll() -> void:
	_start("poll con texto roto, JSON que no es lista o null: sin romper")
	_fake.raw_override = "{esto no es json"
	_bridge.poll()
	check(_wh.pads.empty(), "JSON roto: ningún pad")

	_fake.raw_override = to_json({"e": "connect", "peer": 1})
	_bridge.poll()
	check(_wh.pads.empty(), "objeto en vez de lista: se ignora")

	_fake.raw_override = "[1,\"dos\",null,{\"e\":\"desconocido\"}]"
	_bridge.poll()
	check(_wh.pads.empty(), "eventos raros: se saltan")

	_fake.none_mode = true
	_bridge.poll()
	_fake.none_mode = false
	_fake.raw_override = null
	check(_bridge.is_running(), "el puente sigue en marcha tras la basura")

	# Y después de la basura, un evento bueno se procesa igual.
	_fake.events = [
		{"e": "connect", "peer": 1, "ip": ""},
		{"e": "msg", "peer": 1, "text": to_json({"t": "hello", "id": UID_A, "v": 1})},
	]
	_bridge.poll()
	var pad = _wh.pads.get(UID_A)
	check(pad != null and pad.connected, "un connect+hello posterior funciona")
	_end()


# --- Estado entre casos ---

func _start(name: String) -> void:
	_case_name = name
	_case_failed = false

	_fake = FakeJpNet.new()
	_bridge = WebRtcBridge.new()
	_bridge.js_api = _fake
	_wh._transport = null
	_wh.start_with(_bridge)
	_wh.pads = {}
	_wh._peer_pad = {}
	_wh._peer_ip = {}
	_wh.stats = {"rx": 0, "bad_json": 0, "bad_hello": 0, "full": 0}
	_wh._controls = MENU_CONTROLS
	_wh._ping_timer = 0.0
	_wh._ping_n = 0
	_wh._ping_sent = {}
	_pm.players = [null, null, null, null]
	_pm.ui_navigation_enabled = false

	_ev = []


func _end() -> void:
	_cases_total += 1
	if _case_failed:
		_cases_fail += 1
		print("FALLO  ", _case_name)
	else:
		_cases_ok += 1
		print("ok     ", _case_name)


func _hello(peer: int, uid: String) -> void:
	_fake.events = [
		{"e": "connect", "peer": peer, "ip": ""},
		{"e": "msg", "peer": peer, "text": to_json({"t": "hello", "id": uid, "v": 1})},
	]
	_bridge.poll()


# --- Registro de señales ---

func _ev_wh_connected(ctrl) -> void:
	_ev.append("wh_connected:" + str(ctrl.uid))


func _ev_wh_disconnected(ctrl) -> void:
	_ev.append("wh_disconnected:" + str(ctrl.uid))


func _ev_wh_updated(ctrl) -> void:
	_ev.append("wh_updated:" + str(ctrl.uid))


func _ev_pm_joined(p) -> void:
	_ev.append("pm_joined:%d" % p.index)


func _ev_pm_left(p) -> void:
	_ev.append("pm_left:%d" % p.index)


func _has_event(ev: String) -> bool:
	return _ev.has(ev)


# --- Utilidades ---

## Mensajes capturados de un tipo; con `peer` != null, solo los de ese peer.
func _messages(type: String, peer = null) -> Array:
	var out: Array = []
	for m in _fake.sent:
		var parsed := JSON.parse(m.text)
		if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = parsed.result
		if str(d.get("t", "")) != type:
			continue
		if peer != null and int(m.peer) != int(peer):
			continue
		out.append(d)
	return out


func _one(type: String, peer = null) -> Dictionary:
	var msgs := _messages(type, peer)
	return msgs[0] if not msgs.empty() else {}


func _near(a: float, b: float, eps := 1e-5) -> bool:
	return abs(a - b) <= eps


func check(ok: bool, what: String) -> void:
	if ok:
		_checks_ok += 1
	else:
		_checks_fail += 1
		_case_failed = true
		print("       fallo: ", what)


func _finish() -> void:
	_pm.ui_navigation_enabled = true
	if _cases_fail == 0:
		print("WEB_RTC_BRIDGE OK %d/%d" % [_cases_ok, _cases_total])
		quit(0)
	else:
		print("WEB_RTC_BRIDGE FAIL %d/%d (%d comprobaciones fallidas de %d)" % [
				_cases_ok, _cases_total, _checks_fail, _checks_ok + _checks_fail])
		quit(1)

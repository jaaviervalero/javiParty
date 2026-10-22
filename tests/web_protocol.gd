extends SceneTree
## Tests headless del protocolo del mando web (WebHub), SIN red real:
##   cd /home/javier/Projects/javiParty-web && timeout 60 godot3 --headless --path . -s tests/web_protocol.gd
##
## Llama directamente a WebHub._on_peer_connected / _on_message /
## _on_peer_disconnected con un transporte falso que apunta lo enviado, así que no
## abre puertos ni WebSocket. Comprueba hello/welcome, identidad por id del móvil,
## entradas ("in"), reconexión, mismo id desde otro peer, sala llena, mensajes
## inválidos y el layout contextual (docs/WEB.md, "Protocolo" y fase 1).
## Sale con código 0 si todo pasa y 1 si algo falla.

## Copias de las constantes que usa el test. No se preload-ean web_hub.gd ni
## player_manager.gd: web_hub referencia MinigameBase, que a su vez usa el autoload
## "Fonts", y en modo `-s` el preload falla ("Fonts isn't declared in the current
## scope"). Los autoloads sí están en el árbol tras el primer idle_frame.
const COLORS := [
	Color("2fa8e0"), Color("ec5a5a"), Color("4cbf6b"), Color("f2a33a"),
]
const PROTOCOL_VERSION := 1
const MENU_CONTROLS := [["dpad", ""], ["A", ""], ["B", ""]]

const UID_A := "mobile-aaaa-0001"
const UID_B := "mobile-bbbb-0002"
const UID_C := "mobile-cccc-0003"
const UID_D := "mobile-dddd-0004"
const UID_E := "mobile-eeee-0005"


## Transporte falso: captura los envíos y los cierres. Los métodos son los que
## WebHub usa de WebLanServer (_send -> send, _broadcast, close, poll, is_running).
class FakeTransport:
	var sent: Array = []    # [{"peer": int, "text": String}]
	var closed: Array = []  # peers cerrados
	var running := true

	func poll() -> void:
		pass

	func is_running() -> bool:
		return running

	func send(peer: int, text: String) -> void:
		sent.append({"peer": peer, "text": text})

	func close(peer: int) -> void:
		closed.append(peer)


var _fake = null
var _wh = null
var _pm = null
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
	_fake = FakeTransport.new()
	_wh.connect("controller_connected", self, "_ev_wh_connected")
	_wh.connect("controller_disconnected", self, "_ev_wh_disconnected")
	_wh.connect("controller_updated", self, "_ev_wh_updated")
	_pm.connect("player_joined", self, "_ev_pm_joined")
	_pm.connect("player_left", self, "_ev_pm_left")
	_pm.connect("player_reconnected", self, "_ev_pm_reconnected")
	_pm.connect("player_removed", self, "_ev_pm_removed")

	test_hello()
	test_two_mobiles()
	test_input()
	test_reconnect()
	test_duplicate_peer()
	test_reconnect_input_after_reload()
	test_replace_input_after_reload()
	test_full()
	test_bad_messages()
	test_layout()

	_finish()


# --- Casos ---

func test_hello() -> void:
	_start("hello válido -> controller_connected + welcome con jugador 1 y color")
	_hello(1, UID_A)

	var pad = _wh.pads.get(UID_A)
	check(pad != null, "se crea un WebPad para el id")
	if pad != null:
		check(pad.connected and pad.peer == 1, "el pad queda conectado al peer")
		check(pad.ip == "192.168.1.10", "guarda la IP del peer")
	var p = _pm.players[0]
	check(p != null and p.controller == pad, "PlayerManager crea el jugador 1 con ese mando")
	check(_has_event("wh_connected:" + UID_A), "WebHub emite controller_connected")

	var w := _one("welcome", 1)
	check(not w.empty(), "el móvil recibe welcome")
	if not w.empty():
		check(int(w.get("player", 0)) == 1, "welcome: player 1")
		check(str(w.get("color", "")) == "#" + COLORS[0].to_html(false),
				"welcome: color del jugador 1")
		check(int(w.get("v", 0)) == PROTOCOL_VERSION, "welcome: versión del protocolo")
	_end()


func test_two_mobiles() -> void:
	_start("dos móviles con ids distintos -> jugadores 1 y 2, sin pisarse")
	_hello(1, UID_A)
	_hello(2, UID_B)

	var pa = _wh.pads.get(UID_A)
	var pb = _wh.pads.get(UID_B)
	check(_pm.players[0] != null and _pm.players[0].controller == pa, "el primero es jugador 1")
	check(_pm.players[1] != null and _pm.players[1].controller == pb, "el segundo es jugador 2")
	check(_pm.active_players().size() == 2, "hay exactamente dos jugadores")
	check(_wh.pads.size() == 2, "y dos WebPads distintos")

	var w := _one("welcome", 2)
	check(int(w.get("player", 0)) == 2, "el segundo recibe welcome de jugador 2")
	check(str(w.get("color", "")) == "#" + COLORS[1].to_html(false),
			"el segundo recibe el color del jugador 2")
	_end()


func test_input() -> void:
	_start("mensaje 'in' con bits y stick -> el WebPad refleja buttons/left_stick")
	_hello(1, UID_A)
	var pad = _wh.pads.get(UID_A)
	if pad == null:
		check(false, "no se creó el WebPad")
		_end()
		return

	var bits: int = Pad.UP | Pad.A | Pad.TWO
	_wh._on_message(1, to_json({"t": "in", "b": bits, "x": 0.5, "y": -0.25, "n": 1}))
	check(pad.buttons == bits, "buttons = UP|A|2 (0x%x)" % bits)
	check(_near(pad.left_stick.x, 0.5) and _near(pad.left_stick.y, -0.25),
			"left_stick = (0.5, -0.25)")
	check(pad.packet_number == 1 and pad.packets_total == 1, "cuenta el paquete")
	check(_has_event("wh_updated:" + UID_A), "WebHub emite controller_updated")

	_wh._on_message(1, to_json({"t": "in", "b": 0, "x": 2.0, "y": -2.0, "n": 2}))
	check(_near(pad.left_stick.x, 1.0) and _near(pad.left_stick.y, -1.0),
			"el stick se limita a -1..1")
	_end()


func test_reconnect() -> void:
	_start("reconexión con otro peer y el mismo id -> mismo jugador")
	_hello(1, UID_A)
	var pad = _wh.pads.get(UID_A)
	if pad == null:
		check(false, "no se creó el WebPad")
		_end()
		return

	_wh._on_peer_disconnected(1)
	check(not pad.connected, "al desconectar, el pad queda desconectado")
	check(_pm.players[0] != null and _pm.players[0].controller == pad,
			"el jugador conserva el hueco")

	_hello(7, UID_A)
	check(pad.connected and pad.peer == 7, "el pad vuelve con el peer nuevo")
	check(_wh.pads.size() == 1, "no se crea otro WebPad")
	check(_pm.active_players().size() == 1, "no se crea otro jugador")
	check(_pm.players[0].controller == pad, "el jugador 1 recupera el mando")
	check(_has_event("pm_reconnected:0"), "PlayerManager emite player_reconnected")
	check(_count_events("pm_joined:") == 1, "solo hubo un player_joined en total")

	var w := _one("welcome", 7)
	check(int(w.get("player", 0)) == 1, "el welcome nuevo sigue diciendo jugador 1")
	_end()


func test_duplicate_peer() -> void:
	_start("mismo id desde un segundo peer -> sustituye al viejo, sin duplicar jugador")
	_hello(1, UID_A)
	var pad = _wh.pads.get(UID_A)
	if pad == null:
		check(false, "no se creó el WebPad")
		_end()
		return

	_hello(2, UID_A)
	check(_wh.pads.size() == 1, "sigue habiendo un solo WebPad")
	check(pad.peer == 2 and pad.connected, "el pad apunta al peer nuevo")
	check(_fake.closed.has(1), "se cierra la conexión vieja")
	check(_pm.active_players().size() == 1, "sigue habiendo un solo jugador")
	check(_pm.players[0].controller == pad, "el jugador 1 apunta al mismo WebPad")
	check(_count_events("pm_joined:") == 1, "no se emite un player_joined nuevo")
	check(_has_event("pm_reconnected:0"), "se trata como reconexión del jugador 1")
	check(_has_event("wh_disconnected:" + UID_A), "avisa de la desconexión del peer viejo")

	var w := _one("welcome", 2)
	check(int(w.get("player", 0)) == 1, "el peer nuevo recibe welcome de jugador 1")
	_end()


func test_reconnect_input_after_reload() -> void:
	_start("tras reconectar, la secuencia nueva (n=1..) se acepta, no se descarta")
	_hello(1, UID_A)
	var pad = _wh.pads.get(UID_A)
	if pad == null:
		check(false, "no se creó el WebPad")
		_end()
		return

	# Sesión vieja: n = 1..10. El contador se queda en 10 (< 64).
	for n in range(1, 11):
		_wh._on_message(1, to_json({"t": "in", "b": Pad.A, "x": 0.0, "y": 0.0, "n": n}))
	check(pad.packet_number == 10, "la sesión vieja deja packet_number = 10")

	# Recargar la página: el móvil vuelve con el mismo id desde otro peer y su
	# secuencia empieza otra vez en 1. mark_disconnected() debe reiniciar el contador.
	_wh._on_peer_disconnected(1)
	_hello(9, UID_A)
	var dropped: int = pad.dropped_old
	var total: int = pad.packets_total
	var bits: int = Pad.B | Pad.DOWN
	_wh._on_message(9, to_json({"t": "in", "b": bits, "x": -0.5, "y": 0.5, "n": 1}))
	check(pad.buttons == bits, "el 'in' nuevo se refleja (B|DOWN)")
	check(pad.packet_number == 1, "packet_number vuelve a 1")
	check(pad.dropped_old == dropped, "no se descarta como paquete viejo")
	check(pad.packets_total == total + 1, "cuenta el paquete nuevo")
	check(_near(pad.left_stick.x, -0.5) and _near(pad.left_stick.y, 0.5),
			"también el stick del 'in' nuevo")
	check(_pm.active_players().size() == 1, "sigue siendo el mismo jugador")
	_end()


func test_replace_input_after_reload() -> void:
	_start("sustitución (mismo id, otro peer sin desconectar): el 'in' nuevo se acepta")
	_hello(1, UID_A)
	var pad = _wh.pads.get(UID_A)
	if pad == null:
		check(false, "no se creó el WebPad")
		_end()
		return

	for n in range(1, 11):
		_wh._on_message(1, to_json({"t": "in", "b": Pad.A, "x": 0.0, "y": 0.0, "n": n}))
	check(pad.packet_number == 10, "la sesión vieja deja packet_number = 10")

	# Otra pestaña (o recarga) con el mismo id, sin que el peer viejo se haya
	# desconectado: WebHub marca el pad desconectado y lo reengancha al peer nuevo.
	_hello(2, UID_A)
	var dropped: int = pad.dropped_old
	var total: int = pad.packets_total
	var bits: int = Pad.ONE | Pad.LEFT
	_wh._on_message(2, to_json({"t": "in", "b": bits, "x": 0.0, "y": 0.0, "n": 1}))
	check(pad.peer == 2, "el pad apunta al peer nuevo")
	check(pad.buttons == bits, "el 'in' nuevo se refleja (1|LEFT)")
	check(pad.packet_number == 1, "packet_number vuelve a 1")
	check(pad.dropped_old == dropped, "no se descarta como paquete viejo")
	check(pad.packets_total == total + 1, "cuenta el paquete nuevo")
	check(_wh.pads.size() == 1 and _pm.active_players().size() == 1,
			"sin WebPad ni jugador duplicados")
	_end()


func test_full() -> void:
	_start("5 móviles -> el quinto recibe full y no hay quinto jugador")
	var uids := [UID_A, UID_B, UID_C, UID_D]
	for i in uids.size():
		_hello(i + 1, uids[i])

	check(_pm.active_players().size() == 4, "los cuatro primeros tienen jugador")
	var seen := {}
	for p in _pm.active_players():
		seen[p.controller] = true
	check(seen.size() == 4, "cada jugador tiene su propio WebPad")
	var w4 := _one("welcome", 4)
	check(int(w4.get("player", 0)) == 4, "el cuarto recibe welcome de jugador 4")

	_fake.sent = []
	_hello(5, UID_E)
	check(_wh.stats.full == 1, "stats.full sube a 1")
	check(_messages("full", 5).size() == 1, "el quinto recibe {\"t\":\"full\"}")
	check(_messages("welcome", 5).empty(), "y no recibe welcome")
	check(_pm.active_players().size() == 4, "no se crea un quinto jugador")
	check(_wh.pads.size() == 5, "WebHub registra el pad, pero sin jugador")
	_end()


func test_bad_messages() -> void:
	_start("JSON roto e hello con id inválido -> stats, sin mando ni jugador")
	_wh._on_message(1, "{esto no es json")
	_wh._on_message(1, "[1,2,3]")  # JSON válido pero no es un objeto
	_wh._on_message(2, to_json({"t": "hello", "id": "corto"}))
	_wh._on_message(3, to_json({"t": "hello", "id": "id con espacios!"}))

	check(_wh.stats.rx == 4, "stats.rx cuenta los 4 mensajes")
	check(_wh.stats.bad_json == 2, "stats.bad_json = 2")
	check(_wh.stats.bad_hello == 2, "stats.bad_hello = 2")
	check(_wh.pads.empty(), "no se crea ningún WebPad")
	check(_pm.active_players().empty(), "no se crea ningún jugador")
	check(_fake.closed.has(2) and _fake.closed.has(3),
			"se cierra la conexión del hello inválido")
	_end()


func test_layout() -> void:
	_start("set_controls([]) -> difunde el layout de menús a cada peer")
	_hello(1, UID_A)
	_hello(2, UID_B)
	_fake.sent = []

	_wh.set_controls([])
	check(_messages("layout").size() == 2, "un layout por móvil conectado")
	check(_messages("layout", 1).size() == 1, "llega al peer 1")
	check(_messages("layout", 2).size() == 1, "llega al peer 2")
	for d in _messages("layout"):
		check(to_json(d.get("controls", [])) == to_json(MENU_CONTROLS),
				"el layout es el de menús (dpad + A + B)")
	_end()


# --- Estado entre casos ---

func _start(name: String) -> void:
	_case_name = name
	_case_failed = false

	_wh._transport = _fake
	_wh.pads = {}
	_wh._peer_pad = {}
	_wh._peer_ip = {}
	_wh.stats = {"rx": 0, "bad_json": 0, "bad_hello": 0, "full": 0}
	_wh._controls = MENU_CONTROLS
	_wh._ping_timer = 0.0
	_wh._ping_n = 0
	_wh._ping_sent = {}
	_pm.players = [null, null, null, null]
	# Sin navegación UI en el test (PlayerManager._process no llega a correr aquí,
	# pero así el test no altera el estado global si se ejecuta junto a otros).
	_pm.ui_navigation_enabled = false

	_fake.sent = []
	_fake.closed = []
	_fake.running = true
	_ev = []


func _end() -> void:
	_cases_total += 1
	if _case_failed:
		_cases_fail += 1
		print("FALLO  ", _case_name)
	else:
		_cases_ok += 1
		print("ok     ", _case_name)


func _hello(peer: int, uid: String, ip := "192.168.1.10") -> void:
	_wh._on_peer_connected(peer, ip)
	_wh._on_message(peer, to_json({"t": "hello", "id": uid, "v": 1}))


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


func _ev_pm_reconnected(p) -> void:
	_ev.append("pm_reconnected:%d" % p.index)


func _ev_pm_removed(p) -> void:
	_ev.append("pm_removed:%d" % p.index)


func _has_event(ev: String) -> bool:
	return _ev.has(ev)


func _count_events(prefix: String) -> int:
	var n := 0
	for ev in _ev:
		if str(ev).begins_with(prefix):
			n += 1
	return n


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
		print("WEB_PROTOCOL OK %d/%d" % [_cases_ok, _cases_total])
		quit(0)
	else:
		print("WEB_PROTOCOL FAIL %d/%d (%d comprobaciones fallidas de %d)" % [
				_cases_ok, _cases_total, _checks_fail, _checks_ok + _checks_fail])
		quit(1)

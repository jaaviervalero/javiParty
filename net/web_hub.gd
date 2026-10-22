extends Node
## Autoload "WebHub": mandos web (móviles con la página web/controller/).
## Emite las mismas señales que DSUClient, así que PlayerManager trata igual a
## los dos tipos de mando. El transporte depende de la plataforma:
##   - APK de la tele y escritorio: WebLanServer (el juego es el servidor, en la LAN).
##   - HTML5: puente WebRTC (fase 3 de docs/WEB.md).
##
## Protocolo (JSON, un mensaje por evento; detalle en docs/WEB.md):
##   móvil -> host: hello {id, v}, in {b, x, y, n}, pong {n}
##   host -> móvil: welcome {player, color}, full, layout {controls}, vibrate {ms}, ping {n}

signal controller_connected(ctrl)
signal controller_disconnected(ctrl)
signal controller_updated(ctrl)

const WebLanServer := preload("res://net/web_lan_server.gd")
const WebRtcBridge := preload("res://net/web_rtc_bridge.gd")
## Página del mando en GitHub Pages; la sala va detrás del "#".
const PAGES_BASE := "https://jaaviervalero.github.io/javiParty/m/#"
const PROTOCOL_VERSION := 1
const TIMEOUT_MSEC := 3000
const PING_SEC := 1.0
## Mando de los menús: cruceta para moverse, A acepta, B atrás.
const MENU_CONTROLS := [["dpad", ""], ["A", ""], ["B", ""]]

var pads := {}  # uid -> WebPad
var stats := {"rx": 0, "bad_json": 0, "bad_hello": 0, "full": 0}

var _transport = null
var _peer_pad := {}     # peer -> WebPad
var _peer_ip := {}      # peer -> ip (hasta que manda hello)
var _ping_timer := 0.0
var _ping_n := 0
var _ping_sent := {}    # n -> msec
var _controls: Array = MENU_CONTROLS


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	process_priority = -95  # después de DSUClient, antes que PlayerManager



## Lo llama el menú principal (no _ready) para que los tests headless no abran puertos.
func start() -> bool:
	if _transport != null:
		return _transport.is_running()
	# En HTML5 no hay LAN: los móviles se conectan por WebRTC (fase 3).
	var t = WebRtcBridge.new() if OS.has_feature("HTML5") else WebLanServer.new()
	return start_with(t)


## Arranca con un transporte ya creado (los tests le pasan uno falso).
func start_with(transport) -> bool:
	if _transport != null:
		return _transport.is_running()
	if transport == null:
		return false
	_transport = transport
	_transport.connect("peer_connected", self, "_on_peer_connected")
	_transport.connect("peer_disconnected", self, "_on_peer_disconnected")
	_transport.connect("message", self, "_on_message")
	return _transport.start()


func stop() -> void:
	if _transport == null:
		return
	for pad in pads.values():
		if pad.connected:
			pad.mark_disconnected()
			emit_signal("controller_disconnected", pad)
	_transport.stop()
	_transport = null
	_peer_pad.clear()
	_peer_ip.clear()


func is_running() -> bool:
	return _transport != null and _transport.is_running()


## Dirección que va en el QR: "http://192.168.1.17:8080", o "" sin red/servidor.
func controller_url() -> String:
	if not is_running():
		return ""
	if OS.has_feature("HTML5"):
		var r := room()
		return PAGES_BASE + r if r != "" else ""
	var ip := LAN.best_private_ipv4(IP.get_local_addresses())
	if ip == "":
		return ""
	return "http://%s:%d" % [ip, _transport.http_port]


## Sala de 4 letras del transporte WebRTC; "" con la LAN o sin transporte.
func room() -> String:
	if _transport == null:
		return ""
	var r = _transport.get("room")
	return str(r) if r != null else ""


## Estado del transporte: el de jpNet en HTML5 ("off", "connecting", "ready",
## "error:<motivo>" o "waiting-js"), y "ready"/"off" con la LAN.
func transport_status() -> String:
	if _transport == null:
		return "off"
	if _transport.has_method("status"):
		return str(_transport.status())
	return "ready" if _transport.is_running() else "off"


func connected_pads() -> Array:
	var out: Array = []
	for pad in pads.values():
		if pad.connected:
			out.append(pad)
	return out


## Botones que enseña el mando. `controls` con el formato de MinigameBase.controls:
## [[Pad.A o "stick"/"dpad", {"es": .., "en": ..}], ...]. Vacío = mando de menús.
func set_controls(controls: Array) -> void:
	_controls = MENU_CONTROLS if controls.empty() else _controls_to_wire(controls)
	_broadcast({"t": "layout", "controls": _controls})


func vibrate(ctrl, ms := 60) -> void:
	if ctrl != null and ctrl.peer != 0:
		_send(ctrl.peer, {"t": "vibrate", "ms": int(clamp(ms, 10, 1000))})


# --- Bucle ---

func _process(delta: float) -> void:
	if _transport == null:
		return
	_transport.poll()
	var now := OS.get_ticks_msec()
	_ping_timer += delta
	if _ping_timer >= PING_SEC:
		_ping_timer = 0.0
		_ping_n += 1
		_ping_sent[_ping_n] = now
		_ping_sent.erase(_ping_n - 10)
		_broadcast({"t": "ping", "n": _ping_n})
	for pad in pads.values():
		if pad.connected and now - pad.last_data_msec > TIMEOUT_MSEC:
			_transport.close(pad.peer)
			_drop(pad)


# --- Transporte ---

func _on_peer_connected(peer: int, ip: String) -> void:
	_peer_ip[peer] = ip


func _on_peer_disconnected(peer: int) -> void:
	_peer_ip.erase(peer)
	if _peer_pad.has(peer):
		_drop(_peer_pad[peer])


func _on_message(peer: int, text: String) -> void:
	stats.rx += 1
	var parsed := JSON.parse(text)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		stats.bad_json += 1
		return
	var msg: Dictionary = parsed.result
	match str(msg.get("t", "")):
		"hello":
			_on_hello(peer, msg)
		"in":
			var pad = _peer_pad.get(peer)
			if pad != null:
				pad.apply_input(msg, OS.get_ticks_msec())
				emit_signal("controller_updated", pad)
		"pong":
			var pad = _peer_pad.get(peer)
			var n := int(msg.get("n", -1))
			if pad != null and _ping_sent.has(n):
				pad.rtt_ms = float(OS.get_ticks_msec() - _ping_sent[n])
				pad.last_data_msec = OS.get_ticks_msec()


func _on_hello(peer: int, msg: Dictionary) -> void:
	var uid := str(msg.get("id", ""))
	if not _valid_uid(uid):
		stats.bad_hello += 1
		_peer_ip.erase(peer)
		_transport.close(peer)
		return
	var pad = pads.get(uid)
	if pad == null:
		pad = WebPad.new(uid)
		pads[uid] = pad
	elif pad.connected and pad.peer != peer:
		# El mismo móvil con otra pestaña o tras reconectar: se queda la nueva.
		var old: int = pad.peer
		_peer_pad.erase(old)
		_transport.close(old)
		pad.mark_disconnected()
		emit_signal("controller_disconnected", pad)
	pad.peer = peer
	pad.ip = str(_peer_ip.get(peer, ""))
	pad.connected = true
	pad.last_data_msec = OS.get_ticks_msec()
	_peer_pad[peer] = pad
	emit_signal("controller_connected", pad)

	# PlayerManager ya le ha dado (o no) un jugador al recibir la señal.
	var player = _player_of(pad)
	if player == null:
		stats.full += 1
		_send(peer, {"t": "full"})
		return
	_send(peer, {"t": "welcome", "player": player.index + 1,
			"color": "#" + player.color.to_html(false), "v": PROTOCOL_VERSION})
	_send(peer, {"t": "layout", "controls": _controls})


func _drop(pad) -> void:
	_peer_pad.erase(pad.peer)
	if pad.connected:
		pad.mark_disconnected()
		emit_signal("controller_disconnected", pad)


# --- Utilidades ---

func _player_of(pad):
	for p in PlayerManager.players:
		if p != null and p.controller == pad:
			return p
	return null


func _send(peer: int, msg: Dictionary) -> void:
	_transport.send(peer, to_json(msg))


func _broadcast(msg: Dictionary) -> void:
	if _transport == null:
		return
	var text := to_json(msg)
	for peer in _peer_pad:
		_transport.send(peer, text)


static func _valid_uid(uid: String) -> bool:
	if uid.length() < 8 or uid.length() > 64:
		return false
	for i in uid.length():
		var c := uid.ord_at(i)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45
		if not ok:
			return false
	return true


## [[Pad.A, {"es": "Embestir"}], ["stick", {...}]] -> [["A", "Embestir"], ["stick", "Moverse"]]
static func _controls_to_wire(controls: Array) -> Array:
	var out: Array = []
	for c in controls:
		var what = c[0]
		var name: String = what if typeof(what) == TYPE_STRING else str(Pad.NAMES.get(what, ""))
		if name == "":
			continue
		var label: String = MinigameBase.loc(c[1]) if c.size() > 1 and typeof(c[1]) == TYPE_DICTIONARY else ""
		out.append([name, label])
	return out

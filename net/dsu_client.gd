extends Node
## Autoload "DSUClient": lado CLIENTE del protocolo DSU.
## La tele es cliente; cada móvil es un servidor UDP (normalmente en 26760).
##
## Usa UN solo PacketPeerUDP para suscripciones y datos (el escáner tiene el suyo,
## ver network_scanner.gd) y separa lo que llega por IP:puerto de origen. Flujo con cada servidor:
##   1. Petición de info de los slots 0-3 (se repite cada INFO_REFRESH_SEC y sirve
##      también para medir el RTT).
##   2. Por cada slot "conectado" de la respuesta, suscripción a datos por slot.
##   3. Renovación de la suscripción cada KEEPALIVE_SEC; el servidor deja de enviar
##      si no se renueva y no avisa al desconectarse, así que aplicamos TIMEOUT_MSEC.

signal controller_connected(ctrl: DSUController)
signal controller_disconnected(ctrl: DSUController)
signal controller_updated(ctrl: DSUController)

const KEEPALIVE_SEC := 1.0
const INFO_REFRESH_SEC := 2.0
const TIMEOUT_MSEC := 3000
## Si llega un packet_number menor que el último pero a más de esta distancia,
## asumimos que la app del móvil se ha reiniciado (el contador vuelve a 0).
const RESTART_GAP := 64

var client_id := 0
var local_port := 0
var controllers := {}  # key -> DSUController
var stats := {
	"rx": 0, "bad_size": 0, "bad_magic": 0, "bad_version": 0, "bad_crc": 0,
	"unknown_type": 0, "unknown_sender": 0,
}

var _udp := PacketPeerUDP.new()
var _servers := {}  # "ip:port" -> {ip, port, info_sent_usec, rtt_ms}
var _keepalive_timer := 0.0
var _info_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100  # antes que cualquier escena que lea los mandos
	client_id = randi()
	_bind()


func _bind() -> void:
	# Solo IPv4: así el broadcast del escáner funciona sin sorpresas de dual-stack.
	var err := _udp.bind(0, "0.0.0.0")
	if err != OK:
		for p in range(26761, 26800):
			err = _udp.bind(p, "0.0.0.0")
			if err == OK:
				break
	if err != OK:
		push_error("DSUClient: no se pudo abrir un puerto UDP local (%s)" % error_string(err))
		return
	_udp.set_broadcast_enabled(true)
	local_port = _udp.get_local_port()


# --- API pública ---

## Registra un servidor (IP manual o descubierto) y le pide info al momento.
func add_server(ip: String, port := DSUProtocol.PORT) -> void:
	var k := "%s:%d" % [ip, port]
	if not _servers.has(k):
		_servers[k] = {"ip": ip, "port": port, "info_sent_usec": 0, "rtt_ms": -1.0}
	_send_info_request(_servers[k])


func remove_server(ip: String, port := DSUProtocol.PORT) -> void:
	_servers.erase("%s:%d" % [ip, port])
	for k in controllers.keys():
		var c: DSUController = controllers[k]
		if c.ip == ip and c.port == port:
			if c.connected:
				c.mark_disconnected()
				controller_disconnected.emit(c)
			controllers.erase(k)


func has_server(ip: String, port := DSUProtocol.PORT) -> bool:
	return _servers.has("%s:%d" % [ip, port])


func server_count() -> int:
	return _servers.size()


func connected_controllers() -> Array[DSUController]:
	var out: Array[DSUController] = []
	for c in controllers.values():
		if c.connected:
			out.append(c)
	return out


# --- Bucle ---

func _process(delta: float) -> void:
	_poll()

	_keepalive_timer += delta
	if _keepalive_timer >= KEEPALIVE_SEC:
		_keepalive_timer = 0.0
		# Renovamos también los desconectados: si la app vuelve, los datos vuelven solos.
		for c in controllers.values():
			_send_data_request(c)

	_info_timer += delta
	if _info_timer >= INFO_REFRESH_SEC:
		_info_timer = 0.0
		for s in _servers.values():
			_send_info_request(s)

	var now := Time.get_ticks_msec()
	for c in controllers.values():
		if c.connected and now - c.last_data_msec > TIMEOUT_MSEC:
			c.mark_disconnected()
			controller_disconnected.emit(c)


func _poll() -> void:
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		stats.rx += 1
		var msg := DSUProtocol.parse(pkt)
		if not msg.ok:
			stats[msg.error] += 1
			continue
		match msg.type:
			DSUProtocol.MSG_INFO:
				_on_info(ip, port, msg)
			DSUProtocol.MSG_DATA:
				_on_data(ip, port, msg)


func _on_info(ip: String, port: int, msg: Dictionary) -> void:
	var k := "%s:%d" % [ip, port]
	if not _servers.has(k):
		stats.unknown_sender += 1
		return

	var server: Dictionary = _servers[k]
	# RTT: la primera respuesta tras cada petición (llegan hasta 4, una por slot).
	if server.info_sent_usec > 0:
		server.rtt_ms = (Time.get_ticks_usec() - server.info_sent_usec) / 1000.0
		server.info_sent_usec = 0

	var ck := "%s:%d#%d" % [ip, port, msg.slot]
	var ctrl: DSUController = controllers.get(ck)
	if msg.slot_state == DSUProtocol.SLOT_CONNECTED:
		if ctrl == null:
			ctrl = DSUController.new(ip, port, msg.slot)
			controllers[ck] = ctrl
		ctrl.apply_info(msg)
		if not ctrl.connected and Time.get_ticks_msec() - ctrl.subscribed_msec > 500:
			_send_data_request(ctrl)  # no esperar al siguiente keep-alive
	if ctrl:
		ctrl.rtt_ms = server.rtt_ms


func _on_data(ip: String, port: int, msg: Dictionary) -> void:
	if not msg.connected:
		return
	var ck := "%s:%d#%d" % [ip, port, msg.slot]
	var ctrl: DSUController = controllers.get(ck)
	if ctrl == null:
		if not _servers.has("%s:%d" % [ip, port]):
			stats.unknown_sender += 1
			return
		ctrl = DSUController.new(ip, port, msg.slot)
		controllers[ck] = ctrl

	# Descartar paquetes viejos o duplicados (UDP puede desordenarlos), salvo que
	# el contador haya vuelto a empezar o el mando viniera de estar desconectado.
	var pn: int = msg.packet_number
	if ctrl.connected and pn <= ctrl.packet_number and ctrl.packet_number - pn < RESTART_GAP:
		ctrl.dropped_old += 1
		return

	ctrl.apply_data(msg, Time.get_ticks_usec())
	if not ctrl.connected:
		ctrl.connected = true
		controller_connected.emit(ctrl)
	controller_updated.emit(ctrl)


# --- Envío ---

func _send(ip: String, port: int, pkt: PackedByteArray) -> void:
	_udp.set_dest_address(ip, port)
	_udp.put_packet(pkt)


func _send_info_request(server: Dictionary) -> void:
	server.info_sent_usec = Time.get_ticks_usec()
	_send(server.ip, server.port, DSUProtocol.build_info_request([0, 1, 2, 3], client_id))


func _send_data_request(ctrl: DSUController) -> void:
	ctrl.subscribed_msec = Time.get_ticks_msec()
	# Suscripción por slot (flag 1); la MAC va a cero porque no se usa.
	_send(ctrl.ip, ctrl.port, DSUProtocol.build_data_request(1, ctrl.slot, PackedByteArray(), client_id))

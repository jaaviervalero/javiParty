extends Node
## Autoload "NetworkScanner": descubre móviles con servidor DSU en la red local.
##
## Cada INTERVAL_SEC manda una petición de info a todas las IP de cada /24 privada
## local (y al broadcast de esa /24). Toda IP que responda con un paquete DSU válido
## y un slot conectado se registra en DSUClient, que se suscribe a sus datos.
##
## Va en un HILO y con SU PROPIO socket a propósito: enviar a 254 IPs que en su
## mayoría no existen deja los paquetes retenidos en el kernel esperando a ARP; el
## buffer de envío se llena y PacketPeerUDP.put_packet() se bloquea (es bloqueante)
## hasta ~3 s. En el hilo principal eso congelaba el juego en cada barrido.
##
## Solo debe estar activo en pantallas de lobby/conexión; en partida, stop().

signal server_found(ip, port)

const INTERVAL_SEC := 3.0
## Tras este tiempo escaneando sin ningún mando, la UI muestra consejos.
const WARN_AFTER_SEC := 12.0
const THREAD_TICK_MSEC := 15

var active := false
var subnets := PoolStringArray()  # prefijos tipo "192.168.1."
var sweeps := 0

var _thread: Thread
var _mutex := Mutex.new()
var _running := false          # protegido por _mutex
var _pending_subnets := PoolStringArray()  # para el hilo, protegido por _mutex
var _sweep_requested := false  # protegido por _mutex
var _found: Array = []         # [[ip, port], ...] del hilo al principal, protegido por _mutex
var _timer := 0.0
var _active_time := 0.0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS


func start() -> void:
	if active:
		return
	active = true
	_active_time = 0.0
	_timer = INTERVAL_SEC  # primer barrido inmediato
	_running = true
	_thread = Thread.new()
	_thread.start(self, "_thread_main", DSUClient.client_id)


func stop() -> void:
	if not active:
		return
	active = false
	_mutex.lock()
	_running = false
	_mutex.unlock()
	_thread.wait_to_finish()
	_thread = null


func _exit_tree() -> void:
	stop()


## true si llevamos un rato escaneando y no hay ningún mando enviando datos.
func should_warn() -> bool:
	return active and _active_time > WARN_AFTER_SEC and DSUClient.connected_controllers().empty()


func _process(delta: float) -> void:
	if not active:
		return
	_active_time += delta
	_timer += delta
	if _timer >= INTERVAL_SEC:
		_timer = 0.0
		subnets = LAN.private_ipv4_prefixes(IP.get_local_addresses())
		sweeps += 1
		_mutex.lock()
		_pending_subnets = subnets
		_sweep_requested = true
		_mutex.unlock()

	_mutex.lock()
	var found := _found
	_found = []
	_mutex.unlock()
	for f in found:
		if not DSUClient.has_server(f[0], f[1]):
			DSUClient.add_server(f[0], f[1])
			emit_signal("server_found", f[0], f[1])


# --- Hilo de escaneo: solo usa su socket y las variables protegidas ---

func _thread_main(client_id: int) -> void:
	var sock := PacketPeerUDP.new()
	if sock.listen(0, "0.0.0.0") != OK:
		push_error("NetworkScanner: no se pudo abrir el socket de escaneo")
		return
	sock.set_broadcast_enabled(true)
	var probe := DSUProtocol.build_info_request([0, 1, 2, 3], client_id)
	while true:
		_mutex.lock()
		var running := _running
		var do_sweep := _sweep_requested
		var nets := _pending_subnets
		_sweep_requested = false
		_mutex.unlock()
		if not running:
			break
		if do_sweep:
			for prefix in nets:
				_send(sock, prefix + "255", probe)  # broadcast: barato, algunas apps lo atienden
				for host in range(1, 255):
					_send(sock, prefix + str(host), probe)
		_receive(sock)
		OS.delay_msec(THREAD_TICK_MSEC)
	sock.close()


func _send(sock: PacketPeerUDP, ip: String, pkt: PoolByteArray) -> void:
	sock.set_dest_address(ip, DSUProtocol.PORT)
	sock.put_packet(pkt)  # puede bloquear un rato; por eso estamos en un hilo


func _receive(sock: PacketPeerUDP) -> void:
	while sock.get_available_packet_count() > 0:
		var pkt := sock.get_packet()
		var ip := sock.get_packet_ip()
		var port := sock.get_packet_port()
		var msg := DSUProtocol.parse(pkt)
		if msg.ok and msg.type == DSUProtocol.MSG_INFO and msg.slot_state == DSUProtocol.SLOT_CONNECTED:
			_mutex.lock()
			_found.append([ip, port])
			_mutex.unlock()

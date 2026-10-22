extends Reference
## Transporte del mando web en la LAN (APK de la tele y escritorio): el propio
## juego hace de servidor y el móvil se conecta directo, sin internet.
##
##   http://<ip>:<puerto>      página del mando (web/controller/, va dentro del pck)
##   ws://<ip>:<puerto + 1>    mensajes del mando (JSON, ver docs/WEB.md)
##
## Dos puertos porque WebSocketServer de 3.6 no sirve HTTP normal. El HTTP es un
## TCP_Server mínimo: solo GET de los ficheros de la página. Lo usa WebHub, que
## llama a poll() cada frame y escucha estas señales.

signal peer_connected(peer, ip)
signal peer_disconnected(peer)
signal message(peer, text)

const PAGE_DIR := "res://web/controller/"
const FILES := {
	"/": "index.html",
	"/index.html": "index.html",
	"/controller.js": "controller.js",
	"/style.css": "style.css",
}
const TYPES := {
	"html": "text/html; charset=utf-8",
	"js": "application/javascript; charset=utf-8",
	"css": "text/css; charset=utf-8",
}
## Puertos de la página a probar, por orden (el WebSocket va en el siguiente).
const PORTS := [8080, 8090, 8180, 8280, 47800]
const HTTP_TIMEOUT_MSEC := 3000
const MAX_REQUEST := 4096

var http_port := 0
var ws_port := 0

var _http := TCP_Server.new()
var _ws := WebSocketServer.new()
var _pending: Array = []  # [{conn: StreamPeerTCP, buf: PoolByteArray, since: msec}]
var _files := {}          # nombre -> PoolByteArray (se leen una vez)


## Abre los dos puertos. false si no se pudo con ninguno de PORTS.
func start() -> bool:
	_ws.connect("client_connected", self, "_on_ws_connected")
	_ws.connect("client_disconnected", self, "_on_ws_disconnected")
	_ws.connect("data_received", self, "_on_ws_data")
	for p in PORTS:
		if _http.listen(p) != OK:
			continue
		if _ws.listen(p + 1, PoolStringArray(), false) != OK:
			_http.stop()
			continue
		http_port = p
		ws_port = p + 1
		return true
	push_error("WebLanServer: no hay puertos libres para el mando web")
	return false


func stop() -> void:
	_http.stop()
	_ws.stop()
	for r in _pending:
		r.conn.disconnect_from_host()
	_pending.clear()
	http_port = 0
	ws_port = 0


func is_running() -> bool:
	return http_port != 0


func poll() -> void:
	if not is_running():
		return
	_ws.poll()
	while _http.is_connection_available():
		_pending.append({"conn": _http.take_connection(), "buf": PoolByteArray(),
				"since": OS.get_ticks_msec()})
	var still: Array = []
	for r in _pending:
		if not _serve_step(r):
			still.append(r)
	_pending = still


func send(peer: int, text: String) -> void:
	if _ws.has_peer(peer):
		_ws.get_peer(peer).put_packet(text.to_utf8())


func close(peer: int) -> void:
	if _ws.has_peer(peer):
		_ws.disconnect_peer(peer)


# --- WebSocket ---

func _on_ws_connected(peer: int, _protocol: String) -> void:
	# Texto: el navegador recibe strings y no Blobs.
	_ws.get_peer(peer).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	emit_signal("peer_connected", peer, _ws.get_peer_address(peer))


func _on_ws_disconnected(peer: int, _was_clean := false) -> void:
	emit_signal("peer_disconnected", peer)


func _on_ws_data(peer: int) -> void:
	var p := _ws.get_peer(peer)
	while p.get_available_packet_count() > 0:
		var pkt := p.get_packet()
		if pkt.size() <= MAX_REQUEST:
			emit_signal("message", peer, pkt.get_string_from_utf8())


# --- HTTP ---

## Lee lo que haya de la petición; cuando está entera, responde y cierra.
## true si la conexión ya está terminada.
func _serve_step(r: Dictionary) -> bool:
	var conn: StreamPeerTCP = r.conn
	if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return true
	var n := conn.get_available_bytes()
	if n > 0:
		var got: Array = conn.get_partial_data(n)
		if got[0] == OK:
			# PoolByteArray va por valor: r.buf.append_array() cambiaría una copia
			# y la petición no se acumularía nunca (el navegador se quedaba colgado).
			var buf: PoolByteArray = r.buf
			buf.append_array(got[1])
			r.buf = buf
	var text: String = r.buf.get_string_from_ascii()
	if text.find("\r\n\r\n") < 0:
		if r.buf.size() > MAX_REQUEST or OS.get_ticks_msec() - r.since > HTTP_TIMEOUT_MSEC:
			conn.disconnect_from_host()
			return true
		return false
	_respond(conn, text)
	conn.disconnect_from_host()
	return true


func _respond(conn: StreamPeerTCP, request: String) -> void:
	var first: PoolStringArray = request.split("\r\n", false, 1)[0].split(" ")
	if first.size() < 2 or first[0] != "GET":
		_send_http(conn, "405 Method Not Allowed", "text/plain", "GET only".to_utf8())
		return
	var path: String = first[1].split("?", true, 1)[0].split("#", true, 1)[0]
	if not FILES.has(path):
		_send_http(conn, "404 Not Found", "text/plain", "not found".to_utf8())
		return
	var name: String = FILES[path]
	var body := _file(name)
	if body.empty():
		_send_http(conn, "500 Internal Server Error", "text/plain", "missing file".to_utf8())
		return
	_send_http(conn, "200 OK", TYPES[name.get_extension()], body)


func _send_http(conn: StreamPeerTCP, status: String, type: String, body: PoolByteArray) -> void:
	var head := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n" % [status, type, body.size()]
	head += "Cache-Control: no-cache\r\nConnection: close\r\n\r\n"
	conn.put_data(head.to_ascii())
	conn.put_data(body)


func _file(name: String) -> PoolByteArray:
	if not _files.has(name):
		var f := File.new()
		if f.open(PAGE_DIR + name, File.READ) != OK:
			return PoolByteArray()
		_files[name] = f.get_buffer(f.get_len())
		f.close()
	return _files[name]

extends Reference
## Transporte del mando web en HTML5 (portátil): el WebRTC vive en JavaScript,
## en la página del host (web/host/net.js), y aquí solo se traduce su interfaz a
## las mismas señales que WebLanServer. Lo usa WebHub, que llama a poll() cada
## frame y escucha estas señales.
##
## Interfaz que expone la página en `window.jpNet` (ver docs/WEB.md, fase 3):
##   jpNet.start(room)                       abre la sala y espera a los móviles
##   jpNet.poll() -> string                  JSON array de eventos pendientes:
##       {"e":"connect","peer":int,"ip":""}
##       {"e":"disconnect","peer":int}
##       {"e":"msg","peer":int,"text":string}
##   jpNet.send(peer, text) · jpNet.close(peer) · jpNet.stop()
##   jpNet.status() -> "off"|"connecting"|"ready"|"error:<motivo>"
##
## jpNet puede tardar en existir (net.js carga como módulo): start() deja el
## puente en marcha igualmente y poll() lo busca en cada frame sin romper.
##
## En los tests (fuera del navegador) se inyecta `js_api` con la misma interfaz.

signal peer_connected(peer, ip)
signal peer_disconnected(peer)
signal message(peer, text)

## Sala: 4 letras sin ambigüedades (sin I ni O, que se confunden con 1 y 0).
const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const ROOM_LENGTH := 4

var room := ""
## Objeto con la interfaz de jpNet. Si no es null se usa en vez del navegador
## (tests). Lo normal es dejarlo a null.
var js_api = null

var _running := false
var _js = null          # JavaScriptObject de jpNet, una vez existe
var _started_js := false  # ya se llamó a jpNet.start(room)


## Abre la sala. true aunque jpNet aún no exista (estado "connecting").
func start() -> bool:
	if _running:
		return true
	room = _random_room()
	_running = true
	_started_js = false
	_ensure_js()
	return true


func stop() -> void:
	if _js != null and _started_js:
		_js.stop()
	_running = false
	_js = null
	_started_js = false
	room = ""


func is_running() -> bool:
	return _running


## "off"|"connecting"|"ready"|"error:<motivo>" de jpNet, o "waiting-js" mientras
## el objeto JavaScript no exista todavía.
func status() -> String:
	var js = _ensure_js()
	if js == null:
		return "waiting-js"
	var s = js.status()
	return str(s) if typeof(s) == TYPE_STRING else "connecting"


## Lee los eventos que haya encolado jpNet y los emite como señales.
func poll() -> void:
	if not _running:
		return
	var js = _ensure_js()
	if js == null:
		return
	var raw = js.poll()
	if typeof(raw) != TYPE_STRING:
		return
	var parsed := JSON.parse(raw)
	if parsed.error != OK or typeof(parsed.result) != TYPE_ARRAY:
		return
	for ev in parsed.result:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		match str(ev.get("e", "")):
			"connect":
				emit_signal("peer_connected", int(ev.get("peer", 0)), str(ev.get("ip", "")))
			"disconnect":
				emit_signal("peer_disconnected", int(ev.get("peer", 0)))
			"msg":
				emit_signal("message", int(ev.get("peer", 0)), str(ev.get("text", "")))


func send(peer: int, text: String) -> void:
	if not _running:
		return
	var js = _ensure_js()
	if js != null:
		js.send(peer, text)


func close(peer: int) -> void:
	if not _running:
		return
	var js = _ensure_js()
	if js != null:
		js.close(peer)


# --- Utilidades ---

## Devuelve el objeto con la interfaz de jpNet (inyectado o del navegador).
## La primera vez que aparece lo arranca con la sala ya generada.
func _ensure_js():
	if js_api != null:
		if _running and not _started_js:
			_started_js = true
			js_api.start(room)
		return js_api
	if _js != null:
		return _js
	if not OS.has_feature("HTML5"):
		return null
	# get_interface escribe un error en consola si no existe: se mira antes.
	if str(JavaScript.eval("typeof window.jpNet", true)) != "object":
		return null
	_js = JavaScript.get_interface("jpNet")
	if _js != null and _running and not _started_js:
		_started_js = true
		_js.start(room)
	return _js


## Generador propio y sembrado: el global no se siembra en ningún sitio y la sala
## saldría igual en cada partida.
func _random_room() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for i in ROOM_LENGTH:
		out += ROOM_ALPHABET[rng.randi() % ROOM_ALPHABET.length()]
	return out

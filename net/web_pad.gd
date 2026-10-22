class_name WebPad
extends Reference
## Mando web: un móvil con la página del mando (web/controller/) abierta.
## Tiene los mismos campos que DSUController que lee el resto del juego, así que
## PlayerManager, Player, las tarjetas y el overlay lo tratan igual. Lo crea y
## actualiza WebHub.
##
## Diferencias con DSU:
## - `buttons` ya son botones LÓGICOS de Pad (el móvil no tiene diseños que
##   traducir): el jugador usa Pad.LAYOUT_WEB, que es la identidad.
## - La identidad es un id aleatorio que el móvil guarda en su navegador, no la
##   MAC: recargar la página o bloquear el móvil devuelve el mismo jugador.

var uid: String      # id del navegador del móvil
var peer := 0        # id del transporte (conexión WebSocket o WebRTC)
var ip := ""
var port := 0
var slot := 0
var key: String      # "web:<uid>"

var connected := false
var battery := 0
var mac := PoolByteArray([0, 0, 0, 0, 0, 0])
var model := 0
var connection := 0

# Último estado recibido
var buttons := 0
var left_stick := Vector2.ZERO
var right_stick := Vector2.ZERO
var analog := PoolByteArray()
var touch1 := {}
var touch2 := {}
var accel := Vector3.ZERO
var gyro := Vector3.ZERO
var motion_timestamp := 0
var packet_number := -1
var last_data_msec := 0

# Estadísticas para el overlay de depuración
var packets_total := 0
var dropped_old := 0
var pps := 0.0
var interval_ms := 0.0
var jitter_ms := 0.0
var rtt_ms := -1.0
var _pps_count := 0
var _pps_window_start := 0


func _init(p_uid: String) -> void:
	uid = p_uid
	key = "web:" + uid


func device_id() -> String:
	return key


## Mensaje "in" del móvil: {"b": bits, "x": -1..1, "y": -1..1, "n": secuencia}.
func apply_input(msg: Dictionary, now_msec: int) -> void:
	var n := int(msg.get("n", 0))
	# Por WebSocket llegan en orden; el número solo descarta repetidos tras reconectar.
	if connected and n <= packet_number and packet_number - n < 64:
		dropped_old += 1
		return
	packet_number = n
	buttons = int(msg.get("b", 0)) & 0x7FF
	left_stick = Vector2(clamp(float(msg.get("x", 0.0)), -1.0, 1.0),
			clamp(float(msg.get("y", 0.0)), -1.0, 1.0))
	last_data_msec = now_msec
	packets_total += 1
	_pps_count += 1
	if _pps_window_start == 0:
		_pps_window_start = now_msec
	var window := now_msec - _pps_window_start
	if window >= 1000:
		pps = _pps_count * 1000.0 / window
		_pps_count = 0
		_pps_window_start = now_msec


func mark_disconnected() -> void:
	connected = false
	peer = 0
	packet_number = -1  # la página recargada vuelve a contar desde 1
	pps = 0.0
	buttons = 0
	left_stick = Vector2.ZERO
	_pps_count = 0
	_pps_window_start = 0


func is_pressed(button: int) -> bool:
	return (buttons & button) != 0

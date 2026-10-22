class_name DSUController
extends Reference
## Estado crudo de un mando DSU: un par (servidor IP:puerto, slot).
## Lo crea y actualiza DSUClient; el resto del juego solo lo lee.

var ip: String
var port: int
var slot: int
var key: String  # "ip:puerto#slot", único por mando

# Info del dispositivo (parte común de las respuestas)
var mac := PoolByteArray([0, 0, 0, 0, 0, 0])
var model := 0       # 0 N/A, 1 sin giroscopio o parcial, 2 giroscopio completo
var connection := 0  # 0 N/A, 1 USB, 2 Bluetooth
var battery := 0

## true mientras llegan datos; pasa a false tras DSUClient.TIMEOUT_MSEC sin datos.
var connected := false
var subscribed_msec := 0

# Último estado recibido
var buttons := 0
var left_stick := Vector2.ZERO
var right_stick := Vector2.ZERO
var analog := PoolByteArray()
var touch1 := {}
var touch2 := {}
var accel := Vector3.ZERO  # g
var gyro := Vector3.ZERO   # °/s (pitch, yaw, roll)
var motion_timestamp := 0  # µs, del móvil
var packet_number := -1
var last_data_msec := 0

# Estadísticas para el overlay de depuración
var packets_total := 0
var dropped_old := 0
var pps := 0.0
var interval_ms := 0.0  # media móvil del intervalo entre paquetes
var jitter_ms := 0.0    # media móvil de la desviación de ese intervalo
var rtt_ms := -1.0      # ida y vuelta de la petición de info (latencia aproximada)
var _pps_count := 0
var _pps_window_start := 0
var _last_rx_usec := 0


func _init(p_ip: String, p_port: int, p_slot: int) -> void:
	ip = p_ip
	port = p_port
	slot = p_slot
	key = "%s:%d#%d" % [ip, port, slot]


## Identidad estable para reconectar al mismo jugador: la MAC si la app la manda,
## si no la IP + slot.
func device_id() -> String:
	if DSUProtocol.is_zero_mac(mac):
		return "%s#%d" % [ip, slot]
	return DSUProtocol.mac_to_string(mac)


func apply_info(msg: Dictionary) -> void:
	mac = msg.mac
	model = msg.model
	connection = msg.connection
	battery = msg.battery


func apply_data(msg: Dictionary, now_usec: int) -> void:
	apply_info(msg)
	packet_number = msg.packet_number
	buttons = msg.buttons
	left_stick = msg.left_stick
	right_stick = msg.right_stick
	analog = msg.analog
	touch1 = msg.touch1
	touch2 = msg.touch2
	accel = msg.accel
	gyro = msg.gyro
	motion_timestamp = msg.motion_timestamp
	last_data_msec = now_usec / 1000
	packets_total += 1
	_update_stats(now_usec)


func _update_stats(now_usec: int) -> void:
	if _last_rx_usec > 0:
		var dt := (now_usec - _last_rx_usec) / 1000.0
		if dt < 1000.0:  # ignora huecos largos (reconexiones)
			if interval_ms == 0.0:
				interval_ms = dt
			interval_ms = lerp(interval_ms, dt, 0.05)
			jitter_ms = lerp(jitter_ms, abs(dt - interval_ms), 0.05)
	_last_rx_usec = now_usec

	_pps_count += 1
	var now_msec := now_usec / 1000
	if _pps_window_start == 0:
		_pps_window_start = now_msec
	var window := now_msec - _pps_window_start
	if window >= 1000:
		pps = _pps_count * 1000.0 / window
		_pps_count = 0
		_pps_window_start = now_msec


func mark_disconnected() -> void:
	connected = false
	pps = 0.0
	buttons = 0
	_pps_count = 0
	_pps_window_start = 0
	_last_rx_usec = 0


func is_pressed(button: int) -> bool:
	return (buttons & button) != 0

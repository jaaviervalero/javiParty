class_name DSUProtocol
extends Reference
## Construcción y parseo de paquetes del protocolo DSU (cemuhook) v1001.
## Sin estado ni red: solo bytes <-> Dictionary, para poder testearlo aislado.
## Referencia: https://v1993.github.io/cemuhook-protocol/
##
## Todo es little-endian. En Godot 3.6 PoolByteArray no tiene encode_*/decode_*:
## StreamPeerBuffer escribe en little-endian por defecto (big_endian = false) y
## los enteros sueltos se leen a mano con los helpers _u16_at/_u32_at/_u64_at.
##
## Estructura de cualquier paquete:
##   [0..3]   magic  "DSUC" (cliente→servidor) / "DSUS" (servidor→cliente)
##   [4..5]   u16    versión del protocolo (1001)
##   [6..7]   u16    longitud SIN los 16 bytes de cabecera (incluye message_type)
##   [8..11]  u32    CRC32 del paquete entero con este campo a 0
##   [12..15] u32    id del emisor (aleatorio, fijo durante la sesión)
##   [16..19] u32    message_type
##   [20..]          payload

const PORT := 26760
const VERSION := 1001
const MAGIC_CLIENT := "DSUC"
const MAGIC_SERVER := "DSUS"
const HEADER_SIZE := 16
const PAYLOAD_OFFSET := 20  # cabecera + message_type

const MSG_VERSION := 0x100000
const MSG_INFO := 0x100001
const MSG_DATA := 0x100002

const SLOT_NOT_CONNECTED := 0
const SLOT_RESERVED := 1
const SLOT_CONNECTED := 2

const INFO_PAYLOAD_SIZE := 12   # parte común (11) + byte 0
const DATA_PAYLOAD_SIZE := 80

# Botones normalizados en un único int. Los 16 bits bajos son literalmente
# los dos bytes del paquete (byte 16 << 8 | byte 17), en el orden de la
# especificación, del bit más significativo al menos.
const BTN_DPAD_LEFT := 0x8000
const BTN_DPAD_DOWN := 0x4000
const BTN_DPAD_RIGHT := 0x2000
const BTN_DPAD_UP := 0x1000
const BTN_OPTIONS := 0x0800
const BTN_R3 := 0x0400
const BTN_L3 := 0x0200
const BTN_SHARE := 0x0100
const BTN_Y := 0x0080
const BTN_B := 0x0040
const BTN_A := 0x0020
const BTN_X := 0x0010
const BTN_R1 := 0x0008
const BTN_L1 := 0x0004
const BTN_R2 := 0x0002
const BTN_L2 := 0x0001
# Estos dos van en bytes propios en el paquete; los añadimos por encima.
const BTN_HOME := 0x10000
const BTN_TOUCH := 0x20000

const BUTTON_NAMES := {
	BTN_DPAD_LEFT: "LEFT", BTN_DPAD_DOWN: "DOWN", BTN_DPAD_RIGHT: "RIGHT", BTN_DPAD_UP: "UP",
	BTN_OPTIONS: "OPTIONS", BTN_R3: "R3", BTN_L3: "L3", BTN_SHARE: "SHARE",
	BTN_Y: "Y", BTN_B: "B", BTN_A: "A", BTN_X: "X",
	BTN_R1: "R1", BTN_L1: "L1", BTN_R2: "R2", BTN_L2: "L2",
	BTN_HOME: "HOME", BTN_TOUCH: "TOUCH",
}

# --- CRC32 (el estándar de zlib/IEEE 802.3, polinomio reflejado 0xEDB88320) ---

## Godot 3.6 no tiene `static var`, así que no se cachea la tabla de 256 enteros:
## se calcula bit a bit por byte. Los paquetes son pequeños (~100 Hz), sobra.
static func crc32(data: PoolByteArray) -> int:
	var crc := 0xFFFFFFFF
	for b in data:
		crc ^= b
		for k in 8:
			if crc & 1:
				crc = 0xEDB88320 ^ (crc >> 1)
			else:
				crc = crc >> 1
	return crc ^ 0xFFFFFFFF


# --- Lectura de enteros little-endian (sin encode_*/decode_* en 3.6) ---

static func _u16_at(b: PoolByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)


static func _u32_at(b: PoolByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)


static func _u64_at(b: PoolByteArray, o: int) -> int:
	var v := 0
	for i in 8:
		v |= b[o + i] << (8 * i)
	return v


# --- Construcción ---

## Monta un paquete completo: cabecera + message_type + payload, con CRC.
static func build_packet(msg_type: int, payload: PoolByteArray, sender_id: int,
		magic := MAGIC_CLIENT) -> PoolByteArray:
	var sp := StreamPeerBuffer.new()
	sp.put_data(magic.to_ascii())
	sp.put_u16(VERSION)
	sp.put_u16(4 + payload.size())  # message_type cuenta en la longitud
	sp.put_u32(0)                   # CRC a 0 mientras se calcula
	sp.put_u32(sender_id & 0xFFFFFFFF)
	sp.put_u32(msg_type)
	sp.put_data(payload)
	sp.seek(8)
	sp.put_u32(crc32(sp.data_array))
	return sp.data_array


static func build_version_request(sender_id: int) -> PoolByteArray:
	return build_packet(MSG_VERSION, PoolByteArray(), sender_id)


## Petición de info: i32 con el nº de slots (máx. 4) + 1 byte por slot.
static func build_info_request(slots: Array, sender_id: int) -> PoolByteArray:
	var count := min(slots.size(), 4)
	var sp := StreamPeerBuffer.new()
	sp.put_u32(count)
	for i in count:
		sp.put_u8(int(slots[i]) & 0xFF)
	return build_packet(MSG_INFO, sp.data_array, sender_id)


## Suscripción a datos: u8 flags (0 todos, 1 por slot, 2 por MAC) + u8 slot + 6 bytes MAC.
## El servidor deja de enviar si no se renueva: hay que reenviarla cada ~1 s.
static func build_data_request(flags: int, slot: int, mac := PoolByteArray(),
		sender_id := 0) -> PoolByteArray:
	var sp := StreamPeerBuffer.new()
	sp.put_u8(flags & 0xFF)
	sp.put_u8(slot & 0xFF)
	for i in 6:
		sp.put_u8(mac[i] if i < mac.size() else 0)
	return build_packet(MSG_DATA, sp.data_array, sender_id)


# --- Parseo ---

## Valida y parsea un paquete recibido. Siempre devuelve un Dictionary con "ok".
## Si ok == false, "error" es uno de: "bad_size", "bad_magic", "bad_version", "bad_crc",
## "unknown_type". Si ok == true, incluye "type", "sender_id" y los campos del mensaje.
static func parse(pkt: PoolByteArray, expected_magic := MAGIC_SERVER) -> Dictionary:
	if pkt.size() < PAYLOAD_OFFSET:
		return {"ok": false, "error": "bad_size"}
	if pkt.subarray(0, 3).get_string_from_ascii() != expected_magic:
		return {"ok": false, "error": "bad_magic"}
	if _u16_at(pkt, 4) != VERSION:
		return {"ok": false, "error": "bad_version"}
	var length := _u16_at(pkt, 6)
	if length < 4 or pkt.size() < HEADER_SIZE + length:
		return {"ok": false, "error": "bad_size"}  # demasiado corto: se descarta
	if pkt.size() > HEADER_SIZE + length:
		pkt = pkt.subarray(0, HEADER_SIZE + length - 1)  # demasiado largo: se trunca (lo dice la spec)
	var crc := _u32_at(pkt, 8)
	var zeroed := PoolByteArray(pkt)  # copia: en 3.6 PoolByteArray no tiene duplicate()
	for i in 4:
		zeroed[8 + i] = 0
	if crc32(zeroed) != crc:
		return {"ok": false, "error": "bad_crc"}

	var msg := {
		"ok": true,
		"sender_id": _u32_at(pkt, 12),
		"type": _u32_at(pkt, 16),
	}
	var payload_size := length - 4
	match msg.type:
		MSG_VERSION:
			if payload_size < 2:
				return {"ok": false, "error": "bad_size"}
			msg.max_version = _u16_at(pkt, PAYLOAD_OFFSET)
		MSG_INFO:
			if payload_size < INFO_PAYLOAD_SIZE:
				return {"ok": false, "error": "bad_size"}
			_parse_shared(pkt, PAYLOAD_OFFSET, msg)
		MSG_DATA:
			if payload_size < DATA_PAYLOAD_SIZE:
				return {"ok": false, "error": "bad_size"}
			_parse_data(pkt, PAYLOAD_OFFSET, msg)
		_:
			return {"ok": false, "error": "unknown_type"}
	return msg


## Parte común de las respuestas (11 bytes):
##   +0 slot, +1 estado del slot, +2 modelo, +3 tipo de conexión,
##   +4..+9 MAC (6 bytes), +10 batería.
static func _parse_shared(pkt: PoolByteArray, o: int, msg: Dictionary) -> void:
	msg.slot = pkt[o]
	msg.slot_state = pkt[o + 1]
	msg.model = pkt[o + 2]
	msg.connection = pkt[o + 3]
	msg.mac = pkt.subarray(o + 4, o + 9)
	msg.battery = pkt[o + 10]


## Payload de datos (80 bytes), offsets relativos al inicio del payload:
##   0  parte común (11)          36 toque 1 (6)
##   11 u8  conectado             42 toque 2 (6)
##   12 u32 número de paquete     48 u64 timestamp de movimiento (µs)
##   16 u8  botones 1 (D-pad...)  56 f32 x3 acelerómetro X,Y,Z (g)
##   17 u8  botones 2 (Y,B,A...)  68 f32 x3 giroscopio pitch,yaw,roll (°/s)
##   18 u8  HOME, 19 u8 TOUCH
##   20..23 sticks LX, LY, RX, RY (u8, 128 = centro, Y positiva = ARRIBA)
##   24..35 analógicos: D-pad izq/abajo/der/arriba, Y, B, A, X, R1, L1, R2, L2
static func _parse_data(pkt: PoolByteArray, o: int, msg: Dictionary) -> void:
	_parse_shared(pkt, o, msg)
	msg.connected = pkt[o + 11] != 0
	msg.packet_number = _u32_at(pkt, o + 12)
	var buttons := (pkt[o + 16] << 8) | pkt[o + 17]
	if pkt[o + 18] != 0:
		buttons |= BTN_HOME
	if pkt[o + 19] != 0:
		buttons |= BTN_TOUCH
	msg.buttons = buttons
	# Sticks normalizados a [-1, 1] con Y hacia ARRIBA (convención DSU, no la de Godot).
	msg.left_stick = Vector2(_stick(pkt[o + 20]), _stick(pkt[o + 21]))
	msg.right_stick = Vector2(_stick(pkt[o + 22]), _stick(pkt[o + 23]))
	msg.analog = pkt.subarray(o + 24, o + 35)
	msg.touch1 = _parse_touch(pkt, o + 36)
	msg.touch2 = _parse_touch(pkt, o + 42)
	msg.motion_timestamp = _u64_at(pkt, o + 48)
	var sp := StreamPeerBuffer.new()
	sp.data_array = pkt
	sp.seek(o + 56)
	msg.accel = Vector3(sp.get_float(), sp.get_float(), sp.get_float())
	# Vector3(pitch, yaw, roll) en °/s, tal cual los manda el servidor.
	sp.seek(o + 68)
	msg.gyro = Vector3(sp.get_float(), sp.get_float(), sp.get_float())


static func _stick(v: int) -> float:
	return clamp((v - 128) / 127.0, -1.0, 1.0)


## Toque: u8 activo, u8 id, u16 X, u16 Y.
static func _parse_touch(pkt: PoolByteArray, o: int) -> Dictionary:
	return {
		"active": pkt[o] != 0,
		"id": pkt[o + 1],
		"pos": Vector2(_u16_at(pkt, o + 2), _u16_at(pkt, o + 4)),
	}


# --- Utilidades ---

static func mac_to_string(mac: PoolByteArray) -> String:
	var parts := PoolStringArray()
	for b in mac:
		parts.append("%02x" % b)
	return ":".join(parts)


static func is_zero_mac(mac: PoolByteArray) -> bool:
	for b in mac:
		if b != 0:
			return false
	return true


static func buttons_to_string(buttons: int) -> String:
	var names := PoolStringArray()
	for bit in BUTTON_NAMES:
		if buttons & bit:
			names.append(BUTTON_NAMES[bit])
	return " ".join(names)

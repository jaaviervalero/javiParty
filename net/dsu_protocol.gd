class_name DSUProtocol
extends RefCounted
## Construcción y parseo de paquetes del protocolo DSU (cemuhook) v1001.
## Sin estado ni red: solo bytes <-> Dictionary, para poder testearlo aislado.
## Referencia: https://v1993.github.io/cemuhook-protocol/
##
## Todo es little-endian. Los métodos encode_*/decode_* de PackedByteArray
## de Godot usan little-endian siempre (marshalls.h), así que valen tal cual.
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

static var _crc_table := PackedInt64Array()


# --- CRC32 (el estándar de zlib/IEEE 802.3, polinomio reflejado 0xEDB88320) ---

static func _build_crc_table() -> void:
	_crc_table.resize(256)
	for n in 256:
		var c := n
		for k in 8:
			if c & 1:
				c = 0xEDB88320 ^ (c >> 1)
			else:
				c = c >> 1
		_crc_table[n] = c


static func crc32(data: PackedByteArray) -> int:
	if _crc_table.is_empty():
		_build_crc_table()
	var crc := 0xFFFFFFFF
	for b in data:
		crc = _crc_table[(crc ^ b) & 0xFF] ^ (crc >> 8)
	return crc ^ 0xFFFFFFFF


# --- Construcción ---

## Monta un paquete completo: cabecera + message_type + payload, con CRC.
static func build_packet(msg_type: int, payload: PackedByteArray, sender_id: int,
		magic := MAGIC_CLIENT) -> PackedByteArray:
	var pkt := PackedByteArray()
	pkt.resize(PAYLOAD_OFFSET)
	var m := magic.to_ascii_buffer()
	for i in 4:
		pkt[i] = m[i]
	pkt.encode_u16(4, VERSION)
	pkt.encode_u16(6, 4 + payload.size())  # message_type cuenta en la longitud
	pkt.encode_u32(8, 0)                    # CRC a 0 mientras se calcula
	pkt.encode_u32(12, sender_id & 0xFFFFFFFF)
	pkt.encode_u32(16, msg_type)
	pkt.append_array(payload)
	pkt.encode_u32(8, crc32(pkt))
	return pkt


static func build_version_request(sender_id: int) -> PackedByteArray:
	return build_packet(MSG_VERSION, PackedByteArray(), sender_id)


## Petición de info: i32 con el nº de slots (máx. 4) + 1 byte por slot.
static func build_info_request(slots: Array, sender_id: int) -> PackedByteArray:
	var count := mini(slots.size(), 4)
	var payload := PackedByteArray()
	payload.resize(4 + count)
	payload.encode_s32(0, count)
	for i in count:
		payload[4 + i] = int(slots[i]) & 0xFF
	return build_packet(MSG_INFO, payload, sender_id)


## Suscripción a datos: u8 flags (0 todos, 1 por slot, 2 por MAC) + u8 slot + 6 bytes MAC.
## El servidor deja de enviar si no se renueva: hay que reenviarla cada ~1 s.
static func build_data_request(flags: int, slot: int, mac := PackedByteArray(),
		sender_id := 0) -> PackedByteArray:
	var payload := PackedByteArray()
	payload.resize(8)
	payload[0] = flags & 0xFF
	payload[1] = slot & 0xFF
	for i in mini(mac.size(), 6):
		payload[2 + i] = mac[i]
	return build_packet(MSG_DATA, payload, sender_id)


# --- Parseo ---

## Valida y parsea un paquete recibido. Siempre devuelve un Dictionary con "ok".
## Si ok == false, "error" es uno de: "bad_size", "bad_magic", "bad_version", "bad_crc",
## "unknown_type". Si ok == true, incluye "type", "sender_id" y los campos del mensaje.
static func parse(pkt: PackedByteArray, expected_magic := MAGIC_SERVER) -> Dictionary:
	if pkt.size() < PAYLOAD_OFFSET:
		return {"ok": false, "error": "bad_size"}
	if pkt.slice(0, 4).get_string_from_ascii() != expected_magic:
		return {"ok": false, "error": "bad_magic"}
	if pkt.decode_u16(4) != VERSION:
		return {"ok": false, "error": "bad_version"}
	var length := pkt.decode_u16(6)
	if length < 4 or pkt.size() < HEADER_SIZE + length:
		return {"ok": false, "error": "bad_size"}  # demasiado corto: se descarta
	if pkt.size() > HEADER_SIZE + length:
		pkt = pkt.slice(0, HEADER_SIZE + length)  # demasiado largo: se trunca (lo dice la spec)
	var crc := pkt.decode_u32(8)
	var zeroed := pkt.duplicate()
	zeroed.encode_u32(8, 0)
	if crc32(zeroed) != crc:
		return {"ok": false, "error": "bad_crc"}

	var msg := {
		"ok": true,
		"sender_id": pkt.decode_u32(12),
		"type": pkt.decode_u32(16),
	}
	var payload_size := length - 4
	match msg.type:
		MSG_VERSION:
			if payload_size < 2:
				return {"ok": false, "error": "bad_size"}
			msg.max_version = pkt.decode_u16(PAYLOAD_OFFSET)
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
static func _parse_shared(pkt: PackedByteArray, o: int, msg: Dictionary) -> void:
	msg.slot = pkt[o]
	msg.slot_state = pkt[o + 1]
	msg.model = pkt[o + 2]
	msg.connection = pkt[o + 3]
	msg.mac = pkt.slice(o + 4, o + 10)
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
static func _parse_data(pkt: PackedByteArray, o: int, msg: Dictionary) -> void:
	_parse_shared(pkt, o, msg)
	msg.connected = pkt[o + 11] != 0
	msg.packet_number = pkt.decode_u32(o + 12)
	var buttons := (pkt[o + 16] << 8) | pkt[o + 17]
	if pkt[o + 18] != 0:
		buttons |= BTN_HOME
	if pkt[o + 19] != 0:
		buttons |= BTN_TOUCH
	msg.buttons = buttons
	# Sticks normalizados a [-1, 1] con Y hacia ARRIBA (convención DSU, no la de Godot).
	msg.left_stick = Vector2(_stick(pkt[o + 20]), _stick(pkt[o + 21]))
	msg.right_stick = Vector2(_stick(pkt[o + 22]), _stick(pkt[o + 23]))
	msg.analog = pkt.slice(o + 24, o + 36)
	msg.touch1 = _parse_touch(pkt, o + 36)
	msg.touch2 = _parse_touch(pkt, o + 42)
	msg.motion_timestamp = pkt.decode_u64(o + 48)
	msg.accel = Vector3(pkt.decode_float(o + 56), pkt.decode_float(o + 60), pkt.decode_float(o + 64))
	# Vector3(pitch, yaw, roll) en °/s, tal cual los manda el servidor.
	msg.gyro = Vector3(pkt.decode_float(o + 68), pkt.decode_float(o + 72), pkt.decode_float(o + 76))


static func _stick(v: int) -> float:
	return clampf((v - 128) / 127.0, -1.0, 1.0)


## Toque: u8 activo, u8 id, u16 X, u16 Y.
static func _parse_touch(pkt: PackedByteArray, o: int) -> Dictionary:
	return {
		"active": pkt[o] != 0,
		"id": pkt[o + 1],
		"pos": Vector2i(pkt.decode_u16(o + 2), pkt.decode_u16(o + 4)),
	}


# --- Utilidades ---

static func mac_to_string(mac: PackedByteArray) -> String:
	var parts := PackedStringArray()
	for b in mac:
		parts.append("%02x" % b)
	return ":".join(parts)


static func is_zero_mac(mac: PackedByteArray) -> bool:
	for b in mac:
		if b != 0:
			return false
	return true


static func buttons_to_string(buttons: int) -> String:
	var names := PackedStringArray()
	for bit in BUTTON_NAMES:
		if buttons & bit:
			names.append(BUTTON_NAMES[bit])
	return " ".join(names)

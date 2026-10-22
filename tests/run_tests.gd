extends SceneTree
## Tests del parseo DSU. Ejecutar:
##   godot3 --headless --path . -s tests/run_tests.gd
## Los paquetes de ejemplo los genera tools/gen_fixtures.py con una implementación
## independiente en Python (struct + zlib.crc32).

const P := preload("res://net/dsu_protocol.gd")
const Lan := preload("res://net/lan.gd")
const PadT := preload("res://input/pad.gd")
const FIXTURES := "res://tests/fixtures/dsu_fixtures.json"

var _passed := 0
var _failed := 0


func _init() -> void:
	var fx: Dictionary = JSON.parse(_read_text(FIXTURES)).result
	test_crc(fx)
	test_data_packet(fx)
	test_info_packets(fx)
	test_client_requests(fx)
	test_rejections(fx)
	test_truncation(fx)
	test_scanner_prefixes()
	test_pad_layout()
	print("\n%d OK, %d FALLOS" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _read_text(path: String) -> String:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## Godot 3.6 no tiene String.hex_decode() ni PoolByteArray.hex_encode().
## (String.hex_to_int() exige longitudes de 1/2/4/8/16 y falla con "0x", así que
## se decodifica a mano.)
const HEX_DIGITS := "0123456789abcdef"

func _unhex(h: String) -> PoolByteArray:
	var out := PoolByteArray()
	h = h.strip_edges().to_lower()
	for i in range(0, h.length() - 1, 2):
		out.append(HEX_DIGITS.find(h[i]) * 16 + HEX_DIGITS.find(h[i + 1]))
	return out


func _u16(b: PoolByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)


func _u32(b: PoolByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)


func _hex(b: PoolByteArray) -> String:
	var s := ""
	for x in b:
		s += "%02x" % x
	return s


func check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FALLO: " + what)


func near(a: float, b: float, eps := 1e-5) -> bool:
	return abs(a - b) <= eps


func test_crc(fx: Dictionary) -> void:
	var c: Dictionary = fx.crc_check
	check(P.crc32(String(c.ascii).to_ascii()) == int(c.crc), "CRC32 de '123456789' = 0xCBF43926")
	# El CRC de cada fixture lo calculó Python; si parse() lo acepta, coincide.
	for name in ["data", "info", "info_empty"]:
		var pkt := _unhex(fx[name].hex)
		var zeroed := PoolByteArray(pkt)
		for i in range(8, 12):
			zeroed[i] = 0
		check(P.crc32(zeroed) == _u32(pkt, 8), "CRC del fixture '%s' coincide con zlib" % name)


func test_data_packet(fx: Dictionary) -> void:
	var pkt := _unhex(fx.data.hex)
	var e: Dictionary = fx.data.expect
	check(pkt.size() == 100, "el paquete de datos mide 100 bytes")
	var m := P.parse(pkt)
	check(m.ok, "parse de datos ok")
	if not m.ok:
		return
	check(m.type == int(e.type), "tipo = datos")
	check(m.sender_id == int(e.sender_id), "sender_id")
	check(m.slot == int(e.slot), "slot")
	check(m.slot_state == int(e.slot_state), "estado del slot")
	check(m.model == int(e.model), "modelo")
	check(m.connection == int(e.connection), "tipo de conexión")
	check(_hex(m.mac) == e.mac, "MAC")
	check(m.battery == int(e.battery), "batería (cargando 0xEE)")
	check(m.connected == e.connected, "conectado")
	check(m.packet_number == int(e.packet_number), "packet_number")
	check(m.buttons == int(e.buttons), "botones: %x vs %x" % [m.buttons, int(e.buttons)])
	check(m.buttons & P.BTN_DPAD_LEFT and m.buttons & P.BTN_DPAD_UP and m.buttons & P.BTN_SHARE,
			"bits del byte 1 (izq, arriba, share)")
	check(m.buttons & P.BTN_A and m.buttons & P.BTN_Y and m.buttons & P.BTN_L2 and m.buttons & P.BTN_HOME,
			"bits del byte 2 + HOME (A, Y, L2)")
	check(not (m.buttons & P.BTN_B) and not (m.buttons & P.BTN_TOUCH), "B y TOUCH sin pulsar")
	check(near(m.left_stick.x, e.left_stick[0]) and near(m.left_stick.y, e.left_stick[1]), "stick izquierdo")
	check(near(m.right_stick.x, e.right_stick[0]) and near(m.right_stick.y, e.right_stick[1]), "stick derecho")
	check(_hex(m.analog) == e.analog, "analógicos")
	check(m.touch1.active and m.touch1.id == int(e.touch1.id)
			and m.touch1.pos == Vector2(int(e.touch1.x), int(e.touch1.y)), "toque 1")
	check(not m.touch2.active, "toque 2 inactivo")
	check(m.motion_timestamp == int(e.motion_timestamp), "timestamp de movimiento (u64)")
	for i in 3:
		check(near(m.accel[i], e.accel[i]), "acelerómetro[%d]" % i)
		check(near(m.gyro[i], e.gyro[i], 1e-3), "giroscopio[%d]" % i)


func test_info_packets(fx: Dictionary) -> void:
	var pkt := _unhex(fx.info.hex)
	check(pkt.size() == 32, "la respuesta de info mide 32 bytes")
	var m := P.parse(pkt)
	var e: Dictionary = fx.info.expect
	check(m.ok and m.type == P.MSG_INFO, "parse de info ok")
	if m.ok:
		check(m.slot == int(e.slot) and m.slot_state == P.SLOT_CONNECTED, "info: slot 2 conectado")
		check(_hex(m.mac) == e.mac and m.battery == int(e.battery), "info: MAC y batería")
	var m2 := P.parse(_unhex(fx.info_empty.hex))
	check(m2.ok and m2.slot == 3 and m2.slot_state == P.SLOT_NOT_CONNECTED, "info: slot vacío")


func test_client_requests(fx: Dictionary) -> void:
	var ir: Dictionary = fx.client_info_request
	var built := P.build_info_request(ir.slots, int(ir.client_id))
	check(_hex(built) == ir.hex, "petición de info idéntica byte a byte a la de Python")
	var dr: Dictionary = fx.client_data_request
	built = P.build_data_request(int(dr.flags), int(dr.slot), PoolByteArray(), int(dr.client_id))
	check(_hex(built) == dr.hex, "petición de datos idéntica byte a byte a la de Python")
	check(built.size() == 28 and _u16(built, 6) == 12, "petición de datos: 28 bytes, length 12")


func test_rejections(fx: Dictionary) -> void:
	var good := _unhex(fx.data.hex)

	var bad_crc := PoolByteArray(good)
	bad_crc[60] = bad_crc[60] ^ 0x01  # un bit del acelerómetro
	check(P.parse(bad_crc).get("error") == "bad_crc", "se rechaza un bit cambiado (CRC)")

	var bad_magic := PoolByteArray(good)
	bad_magic[3] = 67  # "C" (0x43): "DSUC" desde un servidor
	check(P.parse(bad_magic).get("error") == "bad_magic", "se rechaza magic incorrecta")

	var bad_version := PoolByteArray(good)
	bad_version[4] = 1000 & 0xFF
	bad_version[5] = (1000 >> 8) & 0xFF
	check(P.parse(bad_version).get("error") == "bad_version", "se rechaza versión != 1001")

	check(P.parse(good.subarray(0, 59)).get("error") == "bad_size", "se rechaza paquete truncado")
	check(P.parse(PoolByteArray([1, 2, 3])).get("error") == "bad_size", "se rechaza basura corta")


func test_truncation(fx: Dictionary) -> void:
	# La spec dice que si sobra algo tras 'length' se trunca, no se descarta.
	var longer := _unhex(fx.data.hex)
	longer.append_array(PoolByteArray([0xDE, 0xAD, 0xBE, 0xEF]))
	var m := P.parse(longer)
	check(m.ok and m.packet_number == 4242, "bytes de más al final se ignoran")


func test_scanner_prefixes() -> void:
	var r := Lan.private_ipv4_prefixes(PoolStringArray([
		"127.0.0.1", "192.168.1.16", "100.120.118.47", "10.0.5.3", "172.20.1.1",
		"172.32.0.1", "fe80::1", "192.168.1.200"]))
	check(r == PoolStringArray(["10.0.5.", "172.20.1.", "192.168.1."]),
			"escáner: solo /24 privadas, sin duplicados ni Tailscale (%s)" % str(r))


func test_pad_layout() -> void:
	# Bits medidos con tools/dsu_probe.py en DSU Controller (iPhone), diseño Wiimote.
	var L: Dictionary = PadT.LAYOUT_DSUCONTROLLER_WIIMOTE
	var V: int = PadT.Grip.VERTICAL
	check(PadT.from_raw(64, L, V) == PadT.A, "Wiimote: A del móvil (bit 0x40) -> A")
	check(PadT.from_raw(128, L, V) == PadT.B, "Wiimote: B del móvil (bit 0x80) -> B")
	check(PadT.from_raw(16, L, V) == PadT.ONE, "Wiimote: 1 del móvil (bit 0x10) -> 1")
	check(PadT.from_raw(32, L, V) == PadT.TWO, "Wiimote: 2 del móvil (bit 0x20) -> 2")
	check(PadT.from_raw(256, L, V) == PadT.MINUS and PadT.from_raw(2048, L, V) == PadT.PLUS, "Wiimote: - y +")
	check(PadT.from_raw(65536, L, V) == PadT.HOME, "Wiimote: HOME")
	check(PadT.from_raw(4096, L, V) == PadT.UP, "vertical: cruceta arriba -> UP")
	var H: int = PadT.Grip.HORIZONTAL
	check(PadT.from_raw(4096, L, H) == PadT.LEFT, "horizontal: flecha de arriba del móvil -> izquierda")
	check(PadT.from_raw(8192, L, H) == PadT.UP, "horizontal: flecha derecha del móvil -> arriba")
	check(PadT.from_raw(8192 | 32, L, H) == PadT.UP | PadT.TWO, "horizontal: los botones no rotan")

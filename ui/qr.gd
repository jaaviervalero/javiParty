extends Reference
## Codificador QR (modo byte, UTF-8). Port de "QR Code generator library" de Project Nayuki (MIT).
##
## API estática (se usa con preload, sin class_name):
##   var Qr = preload("res://ui/qr.gd")
##   var modulos := Qr.encode("hola")        # Array de filas, cada fila Array de bool
##   var img := Qr.to_image("hola", 8, 4)    # Image RGB8 lista para save_png()
##   Qr.draw(self, rect, "hola")             # pintado directo sobre un CanvasItem
##
## Trampas de Godot 3.6 que afectan aquí: los enteros son de 64 bits, así que en
## GF(256) y en los BCH se enmascara a mano; PoolByteArray se copia por valor (hay
## que rellenarlo elemento a elemento) y no hay Array.fill con tamaño.
## Todo es estático porque las funciones estáticas no pueden tocar estado de instancia.

# ---------------------------------------------------------------------------
# Tablas por versión y nivel de corrección (el índice 0 no se usa, como en Nayuki)
# ---------------------------------------------------------------------------

## Codewords de corrección por bloque, [nivel][versión]. Niveles: 0=L, 1=M, 2=Q, 3=H.
const ECC_CODEWORDS_PER_BLOCK := [
	[-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
	[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
	[-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
	[-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
]

## Número de bloques por versión, [nivel][versión].
const NUM_ECC_BLOCKS := [
	[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
	[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
	[-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
	[-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
]

## Bits de formato del nivel de corrección: L=1, M=0, Q=3, H=2 (ISO/IEC 18004).
const ECC_FORMAT_BITS := [1, 0, 3, 2]

const MIN_VERSION := 1
const MAX_VERSION := 40

# Penalizaciones de la máscara (ISO/IEC 18004).
const PENALTY_N1 := 3
const PENALTY_N2 := 3
const PENALTY_N3 := 40
const PENALTY_N4 := 10


# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

## Devuelve la matriz de módulos: Array de filas, cada fila un Array de bool
## (true = módulo negro). `ecc`: 0=L, 1=M, 2=Q, 3=H. Elige la versión mínima que
## quepa y la mejor máscara (0-7) por penalización. Si el texto no cabe en la
## versión 40 devuelve [] (y avisa por push_error).
static func encode(text: String, ecc := 1) -> Array:
	var level := int(clamp(ecc, 0, 3))
	var data := text.to_utf8()
	var version := _pick_version(data.size(), level)
	if version == 0:
		push_error("Qr.encode: el texto no cabe en la versión 40 (%d bytes)" % data.size())
		return []
	var codewords := _data_codewords(data, version, level)
	return _build_matrix(version, level, _add_ecc_and_interleave(codewords, version, level))


## Image FORMAT_RGB8 con el QR en negro sobre blanco y una quiet zone de `border`
## módulos. Devuelve null si el texto no cabe.
static func to_image(text: String, scale := 8, border := 4) -> Image:
	var modules := encode(text)
	if modules.empty():
		return null
	var n := modules.size()
	var s := int(scale)
	var b := int(border)
	var side := (n + b * 2) * s
	var img := Image.new()
	img.create(side, side, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	img.lock()
	for y in n:
		for x in n:
			if modules[y][x]:
				_fill_block(img, (x + b) * s, (y + b) * s, s)
	img.unlock()
	return img


## Dibuja el QR centrado y cuadrado dentro de `rect`, con el fondo `light` en todo
## el rect y 2 módulos de margen alrededor de los módulos.
static func draw(ci: CanvasItem, rect: Rect2, text: String,
		dark := Color(0.1, 0.12, 0.14), light := Color(1, 1, 1)) -> void:
	ci.draw_rect(rect, light, true)
	var modules := encode(text)
	if modules.empty():
		return
	var n := modules.size()
	var side: float = min(rect.size.x, rect.size.y)
	if side <= 0.0:
		return
	var origin: Vector2 = rect.position + (rect.size - Vector2(side, side)) * 0.5
	var m: float = side / float(n + 4)  # n módulos + 2 de margen por lado
	for y in n:
		var top: float = origin.y + (y + 2) * m
		var bottom: float = origin.y + (y + 3) * m
		for x in n:
			if modules[y][x]:
				var left: float = origin.x + (x + 2) * m
				var right: float = origin.x + (x + 3) * m
				# El +0.5 evita costuras entre módulos contiguos por redondeo.
				ci.draw_rect(Rect2(left, top, right - left + 0.5, bottom - top + 0.5), dark, true)


# ---------------------------------------------------------------------------
# Versión y capacidad
# ---------------------------------------------------------------------------

static func _pick_version(num_bytes: int, level: int) -> int:
	# Segmento byte: 4 bits de modo + campo de longitud + 8 bits por byte.
	for v in range(MIN_VERSION, MAX_VERSION + 1):
		if 4 + _char_count_bits(v) + num_bytes * 8 <= _num_data_codewords(v, level) * 8:
			return v
	return 0


## Bits del campo "número de caracteres" del modo byte según la versión.
static func _char_count_bits(version: int) -> int:
	return 8 if version <= 9 else 16


## Número de módulos de datos disponibles (antes de quitar corrección).
static func _num_raw_data_modules(version: int) -> int:
	var result := (16 * version + 128) * version + 64
	if version >= 2:
		var num_align := version / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
		if version >= 7:
			result -= 36
	return result


static func _num_data_codewords(version: int, level: int) -> int:
	return (_num_raw_data_modules(version) / 8
			- ECC_CODEWORDS_PER_BLOCK[level][version] * NUM_ECC_BLOCKS[level][version])


# ---------------------------------------------------------------------------
# Bits de datos, corrección Reed-Solomon y entrelazado
# ---------------------------------------------------------------------------

## Codewords de datos: modo byte + longitud + bytes + terminador + relleno.
static func _data_codewords(data: PoolByteArray, version: int, level: int) -> PoolByteArray:
	var bits := []
	_append_bits(bits, 0x4, 4)  # modo byte (0100)
	_append_bits(bits, data.size(), _char_count_bits(version))
	for i in data.size():
		_append_bits(bits, data[i], 8)

	var capacity := _num_data_codewords(version, level) * 8
	_append_bits(bits, 0, min(4, capacity - bits.size()))  # terminador
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)       # hasta completar byte
	var pad := 0xEC
	while bits.size() < capacity:
		_append_bits(bits, pad, 8)
		pad ^= 0xEC ^ 0x11

	var result := PoolByteArray()
	result.resize(bits.size() / 8)
	for i in result.size():
		var b := 0
		for j in 8:
			if bits[i * 8 + j]:
				b |= 1 << (7 - j)
		result[i] = b
	return result


static func _append_bits(bits: Array, value: int, length: int) -> void:
	for i in range(length - 1, -1, -1):
		bits.append(((value >> i) & 1) != 0)


## Multiplicación en GF(2^8) con el polinomio 0x11D. Los enteros de 3.6 son de
## 64 bits, así que hay que enmascarar el resultado de cada desplazamiento.
static func _gf_multiply(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = ((z << 1) & 0xFF) ^ (0x11D if (z & 0x80) != 0 else 0)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


## Polinomio generador de Reed-Solomon de grado `degree` (coeficientes de mayor a
## menor potencia, sin el término líder que siempre es 1).
static func _rs_divisor(degree: int) -> PoolByteArray:
	var result := PoolByteArray()
	result.resize(degree)
	for i in degree:
		result[i] = 0
	result[degree - 1] = 1
	var root := 1
	for _i in degree:
		for j in result.size():
			result[j] = _gf_multiply(result[j], root)
			if j + 1 < result.size():
				result[j] = result[j] ^ result[j + 1]
		root = _gf_multiply(root, 0x02)
	return result


## Resto de dividir `data` por el generador: son los codewords de corrección.
static func _rs_remainder(data: PoolByteArray, divisor: PoolByteArray) -> PoolByteArray:
	var result := PoolByteArray()
	result.resize(divisor.size())
	for i in result.size():
		result[i] = 0
	for k in data.size():
		var factor: int = data[k] ^ result[0]
		for i in range(result.size() - 1):
			result[i] = result[i + 1]
		result[result.size() - 1] = 0
		for i in result.size():
			result[i] = result[i] ^ _gf_multiply(divisor[i], factor)
	return result


## Parte los datos en bloques, añade ECC a cada uno y los entrelaza.
static func _add_ecc_and_interleave(data: PoolByteArray, version: int, level: int) -> PoolByteArray:
	var num_blocks: int = NUM_ECC_BLOCKS[level][version]
	var ecc_len: int = ECC_CODEWORDS_PER_BLOCK[level][version]
	var raw_codewords := _num_raw_data_modules(version) / 8
	var num_short_blocks := num_blocks - raw_codewords % num_blocks
	var short_block_len := raw_codewords / num_blocks

	var blocks := []
	var divisor := _rs_divisor(ecc_len)
	var k := 0
	for i in num_blocks:
		var dat_len: int = short_block_len - ecc_len + (0 if i < num_short_blocks else 1)
		var dat := PoolByteArray()
		dat.resize(dat_len)
		for j in dat_len:
			dat[j] = data[k + j]
		k += dat_len

		var ecc := _rs_remainder(dat, divisor)
		var block := PoolByteArray()
		block.resize(short_block_len + 1)
		for j in block.size():
			block[j] = 0
		for j in dat_len:
			block[j] = dat[j]
		for j in ecc.size():
			block[block.size() - ecc_len + j] = ecc[j]
		blocks.append(block)

	var result := PoolByteArray()
	result.resize(raw_codewords)
	var pos := 0
	for i in blocks[0].size():
		for j in blocks.size():
			# Los bloques cortos no tienen el byte de relleno: se salta.
			if i != short_block_len - ecc_len or j >= num_short_blocks:
				result[pos] = blocks[j][i]
				pos += 1
	return result


# ---------------------------------------------------------------------------
# Matriz: patrones de función, datos, máscara
# ---------------------------------------------------------------------------

static func _build_matrix(version: int, level: int, codewords: PoolByteArray) -> Array:
	var size := version * 4 + 17
	var modules := _make_bool_matrix(size)
	var is_function := _make_bool_matrix(size)

	_draw_function_patterns(modules, is_function, version, level, size)
	_draw_codewords(modules, is_function, codewords, size)

	# La mejor máscara es la de menor penalización (probando la info de formato real).
	var best_mask := 0
	var best_penalty := -1
	for mask in 8:
		_apply_mask(modules, is_function, mask, size)
		_draw_format_bits(modules, is_function, level, mask, size)
		var penalty := _penalty_score(modules, size)
		if best_penalty < 0 or penalty < best_penalty:
			best_penalty = penalty
			best_mask = mask
		_apply_mask(modules, is_function, mask, size)  # deshacer (XOR)
	_apply_mask(modules, is_function, best_mask, size)
	_draw_format_bits(modules, is_function, level, best_mask, size)
	return modules


static func _make_bool_matrix(size: int) -> Array:
	var matrix := []
	for _y in size:
		var row := []
		for _x in size:
			row.append(false)
		matrix.append(row)
	return matrix


static func _set_function(modules: Array, is_function: Array, x: int, y: int, dark: bool) -> void:
	modules[y][x] = dark
	is_function[y][x] = true


static func _bit(value: int, index: int) -> bool:
	return ((value >> index) & 1) != 0


static func _draw_function_patterns(modules: Array, is_function: Array,
		version: int, level: int, size: int) -> void:
	# Patrones de temporización (fila y columna 6).
	for i in size:
		_set_function(modules, is_function, 6, i, i % 2 == 0)
		_set_function(modules, is_function, i, 6, i % 2 == 0)

	# Tres patrones de búsqueda (esquinas salvo la inferior derecha).
	_draw_finder(modules, is_function, 3, 3, size)
	_draw_finder(modules, is_function, size - 4, 3, size)
	_draw_finder(modules, is_function, 3, size - 4, size)

	# Patrones de alineación (ninguno sobre las esquinas de búsqueda).
	var align_pos := _alignment_positions(version, size)
	var num_align := align_pos.size()
	for i in num_align:
		for j in num_align:
			if not ((i == 0 and j == 0) or (i == 0 and j == num_align - 1)
					or (i == num_align - 1 and j == 0)):
				_draw_alignment(modules, is_function, align_pos[i], align_pos[j])

	_draw_format_bits(modules, is_function, level, 0, size)  # provisional
	_draw_version(modules, is_function, version, size)


static func _alignment_positions(version: int, size: int) -> Array:
	var result := []
	if version == 1:
		return result
	var num_align := version / 7 + 2
	var step := (26 if version == 32
			else (version * 4 + num_align * 2 + 1) / (num_align * 2 - 2) * 2)
	for _i in num_align:
		result.append(0)
	result[0] = 6
	var pos := size - 7
	for i in range(num_align - 1, 0, -1):
		result[i] = pos
		pos -= step
	return result


static func _draw_finder(modules: Array, is_function: Array, x: int, y: int, size: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var dist: int = max(abs(dx), abs(dy))  # norma infinito
			var xx: int = x + dx
			var yy: int = y + dy
			if xx >= 0 and xx < size and yy >= 0 and yy < size:
				_set_function(modules, is_function, xx, yy, dist != 2 and dist != 4)


static func _draw_alignment(modules: Array, is_function: Array, x: int, y: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_function(modules, is_function, x + dx, y + dy, max(abs(dx), abs(dy)) != 1)


## Información de formato: 5 bits de datos + BCH(15,5) con el generador 0x537.
static func _draw_format_bits(modules: Array, is_function: Array,
		level: int, mask: int, size: int) -> void:
	var data: int = (ECC_FORMAT_BITS[level] << 3) | mask
	var rem: int = data
	for _i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412

	# Primera copia, alrededor del patrón de búsqueda superior izquierdo.
	for i in range(0, 6):
		_set_function(modules, is_function, 8, i, _bit(bits, i))
	_set_function(modules, is_function, 8, 7, _bit(bits, 6))
	_set_function(modules, is_function, 8, 8, _bit(bits, 7))
	_set_function(modules, is_function, 7, 8, _bit(bits, 8))
	for i in range(9, 15):
		_set_function(modules, is_function, 14 - i, 8, _bit(bits, i))

	# Segunda copia, repartida entre las otras dos esquinas.
	for i in 8:
		_set_function(modules, is_function, size - 1 - i, 8, _bit(bits, i))
	for i in range(8, 15):
		_set_function(modules, is_function, 8, size - 15 + i, _bit(bits, i))
	_set_function(modules, is_function, 8, size - 8, true)  # siempre oscuro


## Información de versión (solo a partir de la 7): 6 bits + BCH(18,6) con 0x1F25.
static func _draw_version(modules: Array, is_function: Array, version: int, size: int) -> void:
	if version < 7:
		return
	var rem := version
	for _i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits := (version << 12) | rem
	for i in 18:
		var dark := _bit(bits, i)
		var a: int = size - 11 + i % 3
		var b: int = i / 3
		_set_function(modules, is_function, a, b, dark)
		_set_function(modules, is_function, b, a, dark)


## Colocación en zigzag (dos columnas a la vez, de derecha a izquierda, subiendo y
## bajando), saltándose los módulos de función.
static func _draw_codewords(modules: Array, is_function: Array,
		codewords: PoolByteArray, size: int) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x: int = right - j
				var upward := ((right + 1) & 2) == 0
				var y: int = (size - 1 - vert) if upward else vert
				if not is_function[y][x] and i < codewords.size() * 8:
					modules[y][x] = _bit(codewords[i >> 3], 7 - (i & 7))
					i += 1
		right -= 2


static func _apply_mask(modules: Array, is_function: Array, mask: int, size: int) -> void:
	for y in size:
		for x in size:
			if is_function[y][x]:
				continue
			var invert := false
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = (x * y) % 2 + (x * y) % 3 == 0
				6: invert = ((x * y) % 2 + (x * y) % 3) % 2 == 0
				7: invert = ((x + y) % 2 + (x * y) % 3) % 2 == 0
			if invert:
				modules[y][x] = not modules[y][x]


# ---------------------------------------------------------------------------
# Penalización de la máscara
# ---------------------------------------------------------------------------

static func _penalty_score(modules: Array, size: int) -> int:
	var result := 0

	# Rachas iguales en fila y patrones parecidos a los de búsqueda.
	for y in size:
		var run_color := false
		var run_len := 0
		var history := [0, 0, 0, 0, 0, 0, 0]
		for x in size:
			if modules[y][x] == run_color:
				run_len += 1
				if run_len == 5:
					result += PENALTY_N1
				elif run_len > 5:
					result += 1
			else:
				_add_run(run_len, history, size)
				if not run_color:
					result += _count_finder_runs(history) * PENALTY_N3
				run_color = modules[y][x]
				run_len = 1
		result += _end_run(run_color, run_len, history, size) * PENALTY_N3

	# Lo mismo en columna.
	for x in size:
		var run_color := false
		var run_len := 0
		var history := [0, 0, 0, 0, 0, 0, 0]
		for y in size:
			if modules[y][x] == run_color:
				run_len += 1
				if run_len == 5:
					result += PENALTY_N1
				elif run_len > 5:
					result += 1
			else:
				_add_run(run_len, history, size)
				if not run_color:
					result += _count_finder_runs(history) * PENALTY_N3
				run_color = modules[y][x]
				run_len = 1
		result += _end_run(run_color, run_len, history, size) * PENALTY_N3

	# Bloques de 2x2 del mismo color.
	for y in size - 1:
		for x in size - 1:
			var color = modules[y][x]
			if (color == modules[y][x + 1] and color == modules[y + 1][x]
					and color == modules[y + 1][x + 1]):
				result += PENALTY_N2

	# Equilibrio de oscuros y claros: k tal que (45-5k)% <= oscuros/total <= (55+5k)%.
	var dark := 0
	for y in size:
		for x in size:
			if modules[y][x]:
				dark += 1
	var total := size * size
	var k := (abs(dark * 20 - total * 10) + total - 1) / total - 1
	result += k * PENALTY_N4
	return result


static func _add_run(run_len: int, history: Array, size: int) -> void:
	var n := run_len
	if history[0] == 0:
		n += size  # borde claro al principio
	for i in range(history.size() - 1, 0, -1):
		history[i] = history[i - 1]
	history[0] = n


static func _count_finder_runs(history: Array) -> int:
	var n: int = history[1]
	var core: bool = (n > 0 and history[2] == n and history[3] == n * 3
			and history[4] == n and history[5] == n)
	var count := 0
	if core and history[0] >= n * 4 and history[6] >= n:
		count += 1
	if core and history[6] >= n * 4 and history[0] >= n:
		count += 1
	return count


static func _end_run(current_color: bool, current_len: int, history: Array, size: int) -> int:
	var length := current_len
	if current_color:
		_add_run(length, history, size)
		length = 0
	length += size  # borde claro al final
	_add_run(length, history, size)
	return _count_finder_runs(history)


# ---------------------------------------------------------------------------
# Pintado
# ---------------------------------------------------------------------------

static func _fill_block(img: Image, px: int, py: int, scale: int) -> void:
	for y in scale:
		for x in scale:
			img.set_pixel(px + x, py + y, Color(0, 0, 0))

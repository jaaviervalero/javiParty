class_name Pad
extends RefCounted
## Botones LÓGICOS del juego, estilo Wiimote: cruceta, A, B, 1, 2, −, +, HOME.
## Los minijuegos usan solo estos; cada app DSU los manda en bits distintos, así que
## se traducen con un "layout" (bit DSU crudo -> botón lógico).

const UP := 1
const DOWN := 2
const LEFT := 4
const RIGHT := 8
const A := 16
const B := 32
const ONE := 64
const TWO := 128
const MINUS := 256
const PLUS := 512
const HOME := 1024

const NAMES := {
	UP: "UP", DOWN: "DOWN", LEFT: "LEFT", RIGHT: "RIGHT", A: "A", B: "B",
	ONE: "1", TWO: "2", MINUS: "-", PLUS: "+", HOME: "HOME",
}

## Diseño "Wiimote" de DSU Controller (iPhone/Android), medido con tools/dsu_probe.py:
## manda la POSICIÓN en el rombo, no la letra (A a la derecha, B arriba, 1 a la
## izquierda, 2 abajo). La cruceta va referida al móvil en vertical.
const LAYOUT_DSUCONTROLLER_WIIMOTE := {
	DSUProtocol.BTN_DPAD_UP: UP, DSUProtocol.BTN_DPAD_DOWN: DOWN,
	DSUProtocol.BTN_DPAD_LEFT: LEFT, DSUProtocol.BTN_DPAD_RIGHT: RIGHT,
	DSUProtocol.BTN_B: A, DSUProtocol.BTN_Y: B,
	DSUProtocol.BTN_X: ONE, DSUProtocol.BTN_A: TWO,
	DSUProtocol.BTN_SHARE: MINUS, DSUProtocol.BTN_OPTIONS: PLUS,
	DSUProtocol.BTN_HOME: HOME,
}

## Cómo sujeta el jugador el móvil. En HORIZONTAL (cruceta a la izquierda, 1 y 2 a
## la derecha, como un mando de NES) la cruceta gira 90°: la flecha "arriba" del
## móvil apunta a la izquierda del jugador.
enum Grip { VERTICAL, HORIZONTAL }


static func from_raw(raw: int, layout: Dictionary, grip := Grip.VERTICAL) -> int:
	var out := 0
	for bit in layout:
		if raw & bit:
			out |= layout[bit]
	if grip == Grip.HORIZONTAL:
		out = _rotate_dpad(out)
	return out


static func _rotate_dpad(b: int) -> int:
	var rest := b & ~(UP | DOWN | LEFT | RIGHT)
	if b & UP:
		rest |= LEFT
	if b & RIGHT:
		rest |= UP
	if b & DOWN:
		rest |= RIGHT
	if b & LEFT:
		rest |= DOWN
	return rest


static func to_string_names(b: int) -> String:
	var names := PackedStringArray()
	for bit in NAMES:
		if b & bit:
			names.append(NAMES[bit])
	return " ".join(names)


## Vector de la cruceta (x a la derecha, y hacia abajo, como en Godot).
static func dpad_vector(b: int) -> Vector2:
	return Vector2(float(b & RIGHT != 0) - float(b & LEFT != 0), float(b & DOWN != 0) - float(b & UP != 0))

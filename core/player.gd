class_name Player
extends Reference
## Un jugador (1-4). Sobrevive a desconexiones: si el mismo dispositivo vuelve,
## PlayerManager le reasigna su controller.

var index: int        # 0..3
var color: Color
var name: String
var device_id: String # ver DSUController.device_id()
var controller = null # DSUController (sin tipo para evitar dependencias circulares)
var score := 0
## Traducción de bits DSU a botones lógicos (Pad.*). De momento todos usan el
## diseño Wiimote de DSU Controller; más adelante será configurable por móvil.
var layout: Dictionary = Pad.LAYOUT_DSUCONTROLLER_WIIMOTE
## Sujeción actual: cada minijuego la fija al empezar (ver Pad.Grip).
var grip: int = Pad.Grip.VERTICAL
## Jugador simulado (tests automáticos): sus entradas vienen de bot_buttons/bot_stick.
var bot := false
var bot_buttons := 0
var bot_stick := Vector2.ZERO

const STICK_DEADZONE := 0.15
const STICK_PRESS := 0.55
const STICK_RELEASE := 0.4

## Botones lógicos del frame actual y del anterior, para just_pressed/just_released.
var _prev_buttons := 0
var _cur_buttons := 0


func _init(p_index: int, p_color: Color, p_name: String) -> void:
	index = p_index
	color = p_color
	name = p_name


func is_connected_now() -> bool:
	return bot or (controller != null and controller.connected)


## Llamado una vez por frame por PlayerManager.
func update_buttons() -> void:
	_prev_buttons = _cur_buttons
	if not is_connected_now():
		_cur_buttons = 0
		return
	if bot:
		_cur_buttons = bot_buttons | _stick_as_dpad()
		return
	_cur_buttons = Pad.from_raw(controller.buttons, layout, grip) | _stick_as_dpad()


## Stick analógico con Y hacia ABAJO (convención de Godot). La spec DSU dice que la Y
## positiva es arriba, pero DSU Controller la manda hacia abajo (medido en iPhone),
## así que se usa tal cual.
func stick() -> Vector2:
	if not is_connected_now():
		return Vector2.ZERO
	var v: Vector2 = bot_stick if bot else controller.left_stick
	return Vector2.ZERO if v.length() < STICK_DEADZONE else v


## El stick también cuenta como cruceta (para menús y juegos digitales), con
## histéresis para que no parpadee cerca del umbral.
func _stick_as_dpad() -> int:
	var v := stick()
	var out := 0
	for dir in [[Pad.RIGHT, v.x], [Pad.LEFT, -v.x], [Pad.DOWN, v.y], [Pad.UP, -v.y]]:
		var threshold: float = STICK_RELEASE if _prev_buttons & dir[0] else STICK_PRESS
		if dir[1] > threshold:
			out |= dir[0]
	return out


func buttons() -> int:
	return _cur_buttons


func is_pressed(button: int) -> bool:
	return (_cur_buttons & button) != 0


func just_pressed(button: int) -> bool:
	return (_cur_buttons & button) != 0 and (_prev_buttons & button) == 0


func just_released(button: int) -> bool:
	return (_cur_buttons & button) == 0 and (_prev_buttons & button) != 0


func dpad() -> Vector2:
	return Pad.dpad_vector(_cur_buttons)

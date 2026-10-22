class_name Player
extends RefCounted
## Un jugador (1-4). Sobrevive a desconexiones: si el mismo dispositivo vuelve,
## PlayerManager le reasigna su controller.

var index: int        # 0..3
var color: Color
var name: String
var device_id: String # ver DSUController.device_id()
var controller: DSUController
var score := 0
## Traducción de bits DSU a botones lógicos (Pad.*). De momento todos usan el
## diseño Wiimote de DSU Controller; más adelante será configurable por móvil.
var layout: Dictionary = Pad.LAYOUT_DSUCONTROLLER_WIIMOTE
## Sujeción actual: cada minijuego la fija al empezar (ver Pad.Grip).
var grip := Pad.Grip.VERTICAL

## Botones lógicos del frame actual y del anterior, para just_pressed/just_released.
var _prev_buttons := 0
var _cur_buttons := 0


func _init(p_index: int, p_color: Color, p_name: String) -> void:
	index = p_index
	color = p_color
	name = p_name


func is_connected_now() -> bool:
	return controller != null and controller.connected


## Llamado una vez por frame por PlayerManager.
func update_buttons() -> void:
	_prev_buttons = _cur_buttons
	_cur_buttons = Pad.from_raw(controller.buttons, layout, grip) if is_connected_now() else 0


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

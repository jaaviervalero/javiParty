extends Node
## Autoload "GameFlow": modos de juego. De momento solo "juego libre": se elige
## cualquier minijuego del catálogo y al terminar se vuelve al selector.
## También guarda estado compartido entre pantallas (Godot 3.6 no tiene static var).

const MENU_SCENE := "res://ui/main_menu.tscn"
const SELECT_SCENE := "res://ui/minigame_select.tscn"

## Lo activa el test automático: al terminar no cambia de escena.
var headless_test := false

## Último minijuego elegido en el selector (para recordar el foco).
var last_game_id := ""
## id -> instrucciones (dict ES/EN), para la ficha del selector.
var info_cache := {}


func play_free(id: String) -> void:
	var g := MinigameRegistry.by_id(id)
	if g.empty():
		push_error("GameFlow: minijuego desconocido '%s'" % id)
		return
	get_tree().change_scene(g.scene)


## Lo llama MinigameBase al pulsar A en los resultados.
func minigame_done(_placements: Array) -> void:
	get_tree().change_scene(SELECT_SCENE)


func quit_to_menu() -> void:
	get_tree().change_scene(SELECT_SCENE)

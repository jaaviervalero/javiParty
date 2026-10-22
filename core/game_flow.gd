extends Node
## Autoload "GameFlow": modos de juego. De momento solo "juego libre": se elige
## cualquier minijuego del catálogo y al terminar se vuelve al selector.

const MENU_SCENE := "res://ui/main_menu.tscn"
const SELECT_SCENE := "res://ui/minigame_select.tscn"


func play_free(id: String) -> void:
	var g := MinigameRegistry.by_id(id)
	if g.is_empty():
		push_error("GameFlow: minijuego desconocido '%s'" % id)
		return
	get_tree().change_scene_to_file(g.scene)


## Lo llama MinigameBase al pulsar A en los resultados.
func minigame_done(_placements: Array) -> void:
	get_tree().change_scene_to_file(SELECT_SCENE)


func quit_to_menu() -> void:
	get_tree().change_scene_to_file(SELECT_SCENE)

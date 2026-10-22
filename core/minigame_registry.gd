class_name MinigameRegistry
extends RefCounted
## Lista de minijuegos disponibles. Cada entrada: id (carpeta en res://minigames/),
## escena y título en los dos idiomas (para el selector, sin tener que cargar la escena).

const GAMES := [
	{"id": "estrellas", "scene": "res://minigames/estrellas/estrellas.tscn",
		"title": {"es": "Estrellas", "en": "Stars"}},
]


static func by_id(id: String) -> Dictionary:
	for g in GAMES:
		if g.id == id:
			return g
	return {}

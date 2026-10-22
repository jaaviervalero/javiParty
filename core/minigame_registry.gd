class_name MinigameRegistry
extends RefCounted
## Lista de minijuegos disponibles. Cada entrada: id (carpeta en res://minigames/),
## escena y título en los dos idiomas (para el selector, sin tener que cargar la escena).

const GAMES := [
	{"id": "estrellas", "scene": "res://minigames/estrellas/estrellas.tscn",
		"title": {"es": "Estrellas", "en": "Stars"}},
	{"id": "sumo", "scene": "res://minigames/sumo/sumo.tscn",
		"title": {"es": "Sumo de bolas", "en": "Ball sumo"}},
	{"id": "pintura", "scene": "res://minigames/pintura/pintura.tscn",
		"title": {"es": "Pinta el suelo", "en": "Paint the floor"}},
	{"id": "lluvia", "scene": "res://minigames/lluvia/lluvia.tscn",
		"title": {"es": "Lluvia de monedas", "en": "Coin shower"}},
	{"id": "saltarin", "scene": "res://minigames/saltarin/saltarin.tscn",
		"title": {"es": "Pajarito saltarín", "en": "Flappy hop"}},
	{"id": "esquiva", "scene": "res://minigames/esquiva/esquiva.tscn",
		"title": {"es": "Esquiva", "en": "Dodge!"}},
	{"id": "carrera", "scene": "res://minigames/carrera/carrera.tscn",
		"title": {"es": "Carrera de pulgares", "en": "Thumb sprint"}},
]


static func by_id(id: String) -> Dictionary:
	for g in GAMES:
		if g.id == id:
			return g
	return {}

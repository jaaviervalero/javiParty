class_name MinigameRegistry
extends RefCounted
## Lista de minijuegos disponibles. Cada entrada: id (carpeta en res://minigames/),
## escena y título en los dos idiomas (para el selector, sin tener que cargar la escena).
## Fuera del catálogo (código conservado): lluvia, carrera.

const GAMES := [
	{"id": "estrellas", "scene": "res://minigames/estrellas/estrellas.tscn",
		"title": {"es": "Estrellas", "en": "Stars"}},
	{"id": "sumo", "scene": "res://minigames/sumo/sumo.tscn",
		"title": {"es": "Sumo de bolas", "en": "Ball sumo"}},
	{"id": "pintura", "scene": "res://minigames/pintura/pintura.tscn",
		"title": {"es": "Pinta el suelo", "en": "Paint the floor"}},
	{"id": "saltarin", "scene": "res://minigames/saltarin/saltarin.tscn",
		"title": {"es": "Pajarito saltarín", "en": "Flappy hop"}},
	{"id": "esquiva", "scene": "res://minigames/esquiva/esquiva.tscn",
		"title": {"es": "Esquiva", "en": "Dodge!"}},
	{"id": "memoria", "scene": "res://minigames/memoria/memoria.tscn",
		"title": {"es": "Sigue la secuencia", "en": "Follow the sequence"}},
	{"id": "ritmo", "scene": "res://minigames/ritmo/ritmo.tscn",
		"title": {"es": "Al compás", "en": "On the beat"}},
	{"id": "ovejas", "scene": "res://minigames/ovejas/ovejas.tscn",
		"title": {"es": "Cuenta ovejas", "en": "Count the sheep"}},
	{"id": "tanques", "scene": "res://minigames/tanques/tanques.tscn",
		"title": {"es": "Tanquecitos", "en": "Tiny tanks"}},
	{"id": "colina", "scene": "res://minigames/colina/colina.tscn",
		"title": {"es": "Rey de la colina", "en": "King of the hill"}},
	{"id": "pesca", "scene": "res://minigames/pesca/pesca.tscn",
		"title": {"es": "A pescar", "en": "Gone fishing"}},
	{"id": "duelo", "scene": "res://minigames/duelo/duelo.tscn",
		"title": {"es": "Duelo al sol", "en": "Showdown"}},
	{"id": "cronometro", "scene": "res://minigames/cronometro/cronometro.tscn",
		"title": {"es": "Para el reloj", "en": "Stop the clock"}},
	{"id": "globos", "scene": "res://minigames/globos/globos.tscn",
		"title": {"es": "Infla el globo", "en": "Pump it up"}},
]


static func by_id(id: String) -> Dictionary:
	for g in GAMES:
		if g.id == id:
			return g
	return {}

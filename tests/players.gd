extends SceneTree
## Tests de asignación de mandos a jugadores (PlayerManager):
##   godot3 --headless --path . -s tests/players.gd
##
## Regresión de un fallo real: al conectarse el móvil de un amigo, el primero se
## quedaba sin jugador. La app DSU Controller de iPhone no puede leer la MAC real
## (iOS no la da), así que todos los móviles mandan la misma MAC inventada; como
## device_id() prefiere la MAC, el segundo móvil "era" el primero y PlayerManager
## le pasaba el jugador 1, dejando al dueño sin mando.

const Ctrl := preload("res://net/dsu_controller.gd")
const SAME_MAC := [0x02, 0x00, 0x00, 0x00, 0x00, 0x01]

var _passed := 0
var _failed := 0
var _pm


func _init() -> void:
	_run()


func _run() -> void:
	yield(self, "idle_frame")
	_pm = root.get_node("PlayerManager")

	_reset()
	var a = _phone("192.168.1.21", SAME_MAC)
	var b = _phone("192.168.1.30", SAME_MAC)
	_pm._on_controller_connected(a)
	_pm._on_controller_connected(b)
	check(_pm.players[0] != null and _pm.players[0].controller == a,
			"misma MAC: el primer móvil sigue siendo el jugador 1")
	check(_pm.players[1] != null and _pm.players[1].controller == b,
			"misma MAC: el segundo móvil entra como jugador 2")

	# El jugador 1 se va y vuelve: recupera SU hueco, no el del amigo.
	a.connected = false
	_pm._on_controller_disconnected(a)
	a.connected = true
	_pm._on_controller_connected(a)
	check(_pm.players[0].controller == a and _pm.players[1].controller == b,
			"misma MAC: al reconectar cada uno vuelve a su jugador")

	# Si el amigo se va y el jugador 1 sigue, el amigo vuelve a su hueco (2).
	b.connected = false
	_pm._on_controller_disconnected(b)
	b.connected = true
	_pm._on_controller_connected(b)
	check(_pm.players[1].controller == b and _pm.players[0].controller == a,
			"misma MAC: el amigo vuelve a su hueco sin tocar el del otro")
	check(_pm.active_players().size() == 2, "no se crean jugadores de más (%d)" % _pm.active_players().size())

	# MAC distintas (Android): cada uno el suyo, como siempre.
	_reset()
	var c = _phone("192.168.1.40", [0x10, 1, 2, 3, 4, 5])
	var d = _phone("192.168.1.41", [0x10, 1, 2, 3, 4, 6])
	_pm._on_controller_connected(c)
	_pm._on_controller_connected(d)
	check(_pm.players[0].controller == c and _pm.players[1].controller == d,
			"MAC distintas: dos jugadores")

	# Mismo móvil que cambia de IP (MAC real): recupera su jugador.
	c.connected = false
	_pm._on_controller_disconnected(c)
	var c2 = _phone("192.168.1.50", [0x10, 1, 2, 3, 4, 5])
	_pm._on_controller_connected(c2)
	check(_pm.players[0].controller == c2, "MAC real y otra IP: recupera su jugador")
	check(_pm.active_players().size() == 2, "y no ocupa un hueco nuevo")

	_reset()
	_finish()


func _phone(ip: String, mac: Array):
	var c = Ctrl.new(ip, 26760, 0)
	c.mac = PoolByteArray(mac)
	c.connected = true
	return c


func _reset() -> void:
	_pm.players = [null, null, null, null]


func check(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
		print("  ok   ", msg)
	else:
		_failed += 1
		print("  FALLO ", msg)


func _finish() -> void:
	print("\n%d OK, %d FALLOS" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

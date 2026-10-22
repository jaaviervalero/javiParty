extends Node
## Test automático de un minijuego con 4 bots que pulsan al azar:
##   tools/smoke.sh <id>        (o: godot3 --headless --path . tests/minigame_smoke.tscn -- <id> [n])
## Con ventana y un tercer argumento, guarda una captura a mitad de partida:
##   godot3 --path . tests/minigame_smoke.tscn -- <id> <n> <captura.png>
## Recorre intro, cuenta atrás, partida y resultados a velocidad x4 y comprueba que
## termina con una clasificación válida. Los errores de script los detecta smoke.sh.

const TIME_SCALE := 4.0
const TIMEOUT_MSEC := 90000

var _game: MinigameBase
var _start := 0
var _shot_path := ""


func _ready() -> void:
	var args := _user_args()
	if args.empty():
		_fail("falta el id del minijuego (… -- <id>)")
		return
	var id: String = args[0]
	var path := "res://minigames/%s/%s.tscn" % [id, id]
	if not ResourceLoader.exists(path):
		_fail("no existe %s" % path)
		return
	Settings.headless_test = true
	var n := 4 if args.size() < 2 else int(args[1])
	if args.size() > 2:
		_shot_path = args[2]
	for i in n:
		var p := Player.new(i, PlayerManager.COLORS[i], "Bot %d" % (i + 1))
		p.bot = true
		PlayerManager.players[i] = p
	var scene: PackedScene = load(path)
	var inst = scene.instance()
	if not inst is MinigameBase:
		_fail("la escena raíz de %s no hereda de MinigameBase" % path)
		return
	_game = inst
	_game.connect("finished", self, "_on_finished")
	Engine.time_scale = TIME_SCALE
	_start = OS.get_ticks_msec()
	add_child(_game)
	print("SMOKE: %s con %d bots (título: %s, duración %.0f s)" % [id, n,
			MinigameBase.loc(_game.title), _game.duration])
	if MinigameBase.loc(_game.title) == "" or MinigameBase.loc(_game.instructions) == "":
		_fail("faltan title o instructions en _configure()")


## Godot 3.6 no tiene OS.get_cmdline_user_args(): se filtra lo que va tras "--".
func _user_args() -> PoolStringArray:
	var out := PoolStringArray()
	var after := false
	for a in OS.get_cmdline_args():
		if after:
			out.append(a)
		elif a == "--":
			after = true
	return out


func _process(_delta: float) -> void:
	if _game == null:
		return
	if OS.get_ticks_msec() - _start > TIMEOUT_MSEC:
		_fail("no terminó en %d s reales (¿falta límite de tiempo o finish()?)" % (TIMEOUT_MSEC / 1000))
		return
	if _shot_path != "" and _game.state == MinigameBase.State.PLAYING \
			and _game.elapsed > min(_game.duration * 0.4, 4.0):
		var path := _shot_path
		_shot_path = ""
		yield(VisualServer, "frame_post_draw")
		var img: Image = get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png(path)
		print("SMOKE: captura en ", path)
	# Bots: machacan botones y mueven el stick al azar.
	for p in PlayerManager.active_players():
		var b := 0
		for bit in [Pad.A, Pad.B, Pad.UP, Pad.DOWN, Pad.LEFT, Pad.RIGHT]:
			if randf() < 0.15:
				b |= bit
		p.bot_buttons = b
		p.bot_stick = (p.bot_stick + Vector2(rand_range(-0.3, 0.3), rand_range(-0.3, 0.3))).limit_length(1.0)


func _on_finished(placements: Array) -> void:
	if placements.size() != PlayerManager.active_players().size():
		_fail("la clasificación tiene %d entradas" % placements.size())
		return
	var desc := PoolStringArray()
	for r in placements:
		desc.append("J%d %dº (%s)" % [r.player.index + 1, r.place, _game.format_score(r.score)])
	print("SMOKE: resultados ", ", ".join(desc))
	print("SMOKE OK")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	printerr("SMOKE FALLO: " + msg)
	get_tree().quit(1)

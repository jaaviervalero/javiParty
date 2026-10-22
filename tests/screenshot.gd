extends Node
## Captura de pantalla para revisar la UI sin mirar la ventana:
##   godot3 --path . tests/screenshot.tscn -- <escena.tscn> <salida.png> [método a llamar]

func _ready() -> void:
	var args := PoolStringArray()
	var after := false
	for a in OS.get_cmdline_args():
		if after:
			args.append(a)
		elif a == "--":
			after = true
	var scene: Node = load(args[0]).instance()
	add_child(scene)
	if args.size() > 2:
		scene.call_deferred(args[2])
	yield(get_tree().create_timer(1.2), "timeout")
	yield(VisualServer, "frame_post_draw")
	var img: Image = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png(args[1])
	get_tree().quit()

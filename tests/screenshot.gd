extends Node
## Captura de pantalla para revisar la UI sin mirar la ventana:
##   godot --path . tests/screenshot.tscn -- <escena.tscn> <salida.png> [método a llamar]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: Node = load(args[0]).instantiate()
	add_child(scene)
	if args.size() > 2:
		scene.call_deferred(args[2])
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[1])
	get_tree().quit()

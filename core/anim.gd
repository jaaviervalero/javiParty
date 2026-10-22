class_name Anim
extends Reference
## Tweens de Godot 3.6 (no existe create_tween()). Cada tween es un nodo Tween
## temporal que se cuelga del Control y se libera al terminar.

const TRANS := Tween.TRANS_BACK
const EASE := Tween.EASE_OUT


## Escala un Control (rect_scale) desde `from` hasta `to`.
static func scale_to(control: Control, from: Vector2, to: Vector2, duration := 0.25,
		delay := 0.0) -> Tween:
	var tw := Tween.new()
	control.add_child(tw)
	tw.interpolate_property(control, "rect_scale", from, to, duration, TRANS, EASE, delay)
	tw.connect("tween_all_completed", tw, "queue_free")
	tw.start()
	return tw


## Escala un Node2D (scale) desde `from` hasta `to`.
static func node_scale_to(node: Node2D, from: Vector2, to: Vector2, duration := 0.25,
		delay := 0.0) -> Tween:
	var tw := Tween.new()
	node.add_child(tw)
	tw.interpolate_property(node, "scale", from, to, duration, TRANS, EASE, delay)
	tw.connect("tween_all_completed", tw, "queue_free")
	tw.start()
	return tw


## Desvanece y libera el Control.
static func fade_out(control: Control, duration := 0.4, delay := 0.0) -> Tween:
	var tw := Tween.new()
	control.add_child(tw)
	tw.interpolate_property(control, "modulate:a", 1.0, 0.0, duration,
			Tween.TRANS_LINEAR, Tween.EASE_IN, delay)
	tw.connect("tween_all_completed", control, "queue_free")
	tw.start()
	return tw

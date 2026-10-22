extends SceneTree
## Test de UI del selector: al mover el foco, la rejilla NO debe reordenarse.
##   godot3 --headless --path . -s tests/ui_focus.gd
##
## Regresión de un fallo real: `game_card._on_focus` hacía `raise()` para poner la
## tarjeta enfocada por encima de las demás, pero en 3.6 `Control` no tiene
## `z_index` y `raise()` reordena los hijos del `GridContainer`: la tarjeta con
## foco (incluida la del arranque) se iba a la última celda y todas las demás se
## desplazaban, así que los iconos "bailaban" al recorrer el menú. En la tele se
## veía a la primera; ningún smoke test lo pillaba porque no mueven el foco.

const SELECT := "res://ui/minigame_select.tscn"
const COLUMNS := 4   # columnas de la rejilla del selector

var _passed := 0
var _failed := 0


func _init() -> void:
	var scene: Node = load(SELECT).instance()
	root.add_child(scene)
	_run(scene)


func _run(scene: Node) -> void:
	yield(self, "idle_frame")
	yield(self, "idle_frame")

	var grid = _find_grid(scene)
	check(grid != null, "el selector monta una GridContainer")
	if grid == null:
		_finish()
		return

	var order: Array = _ids(grid)
	check(order.size() > 4, "la rejilla tiene tarjetas (%d)" % order.size())
	check(order == _registry_ids(), "el orden inicial es el del registro de minijuegos")

	# 1) Enfocar cada tarjeta, como hace el propio selector al arrancar.
	for i in order.size():
		grid.get_children()[i].grab_focus()
		yield(self, "idle_frame")
		check(_ids(grid) == order, "enfocar la tarjeta %d no reordena la rejilla" % i)

	# 2) Y moverse con la cruceta de verdad (flechas, que es lo que manda la
	#    cruceta del mando de la tele; los móviles van a las mismas acciones ui_*).
	grid.get_children()[1].grab_focus()
	yield(self, "idle_frame")
	var start := _focused_index(grid)
	check(start == 1, "se puede poner el foco donde se quiera (%d)" % start)
	_press(KEY_RIGHT)
	yield(self, "idle_frame")
	var right := _focused_index(grid)
	check(right == start + 1, "la cruceta a la derecha pasa a la siguiente (%d -> %d)" % [start, right])
	_press(KEY_DOWN)
	yield(self, "idle_frame")
	var down := _focused_index(grid)
	check(down == right + 4, "la cruceta abajo baja una fila de 4 (%d -> %d)" % [right, down])
	check(_ids(grid) == order, "moverse con la cruceta no reordena la rejilla")
	var now := _focused_index(grid)
	check(now >= 0, "el foco sigue en una tarjeta del selector")

	# 3) La tarjeta enfocada no se sale de su celda: ni ella ni su halo de foco.
	var card: Control = grid.get_children()[now]
	var cell := card.rect_position
	var grow := (card.rect_size.x * 0.06) / 2.0 + 10.0   # escala + halo de foco
	check(cell.x - grow >= 0.0 and cell.y - grow >= 0.0,
			"la tarjeta ampliada cabe en su hueco sin tapar a las vecinas")

	# 4) Separación real entre tarjetas. Si el nombre de la constante de tema no es
	#    el de 3.6, el override se ignora en silencio y quedan a 4 px: pegadas, con
	#    la tarjeta ampliada pisando a las vecinas.
	var a: Control = grid.get_children()[0]
	var b: Control = grid.get_children()[1]
	var gap := b.rect_position.x - (a.rect_position.x + a.rect_size.x)
	check(gap >= 16, "hay separación entre tarjetas (%d px, no pegadas)" % gap)
	var row_gap = grid.get_children()[4].rect_position.y - (a.rect_position.y + a.rect_size.y)
	check(row_gap >= 16, "hay separación entre filas (%d px)" % row_gap)

	# 5) La rejilla entera cabe en lo que se ve: ni tarjetas ni halos cortados.
	var scroll = _find_scroll(scene)
	check(scroll != null, "el selector monta un ScrollContainer")
	if scroll != null:
		var view: Rect2 = scroll.get_global_rect()
		var first: Rect2 = grid.get_children()[0].get_global_rect()
		var last_col: Rect2 = grid.get_children()[COLUMNS - 1].get_global_rect()
		check(first.position.x - grow >= view.position.x,
				"la columna de la izquierda cabe con su halo (%.0f >= %.0f)" % [first.position.x - grow, view.position.x])
		check(last_col.end.x + grow <= view.end.x,
				"la columna de la derecha cabe con su halo (%.0f <= %.0f)" % [last_col.end.x + grow, view.end.x])
	_finish()


func _find_scroll(n: Node):
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r = _find_scroll(c)
		if r != null:
			return r
	return null


func _find_grid(n: Node):
	if n is GridContainer:
		return n
	for c in n.get_children():
		var r = _find_grid(c)
		if r != null:
			return r
	return null


func _ids(grid) -> Array:
	var out := []
	for ch in grid.get_children():
		out.append(ch.game.id)
	return out


func _registry_ids() -> Array:
	var out := []
	for g in MinigameRegistry.GAMES:
		out.append(g.id)
	return out


func _focused_index(grid) -> int:
	var i := 0
	for ch in grid.get_children():
		if ch.has_focus():
			return i
		i += 1
	return -1


func _press(scancode: int) -> void:
	# Flecha de teclado, que es lo mismo que manda la cruceta del mando de la tele
	# (las dos van a las acciones ui_* de serie).
	var down := InputEventKey.new()
	down.scancode = scancode
	down.physical_scancode = scancode
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.scancode = scancode
	up.physical_scancode = scancode
	up.pressed = false
	Input.parse_input_event(up)


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

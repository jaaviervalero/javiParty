extends Node
## Autoload "Fonts": caché de DynamicFont por peso y tamaño.
## En Godot 3.6 el tamaño va DENTRO de la fuente (no se pasa a draw_string), así que
## cada combinación peso/tamaño es un recurso. Esto lo cachea para no recrearlo.

const PATHS := {
	400: "res://assets/fonts/Nunito-Regular.ttf",
	600: "res://assets/fonts/Nunito-SemiBold.ttf",
	700: "res://assets/fonts/Nunito-Bold.ttf",
	800: "res://assets/fonts/Nunito-ExtraBold.ttf",
	900: "res://assets/fonts/Nunito-Black.ttf",
}

var _cache := {}


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS


func get_font(weight := 600, size := 22) -> DynamicFont:
	var w := _nearest(weight)
	var key := "%d:%d" % [w, size]
	if not _cache.has(key):
		var f := DynamicFont.new()
		f.font_data = load(PATHS[w])
		f.size = size
		f.use_filter = true
		_cache[key] = f
	return _cache[key]


## Fuente con contorno (texto sobre fondos de color). No se cachea: se usa poco.
func outlined(weight := 800, size := 22, outline_size := 8, outline_color := Color(1, 1, 1, 1)) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(PATHS[_nearest(weight)])
	f.size = size
	f.use_filter = true
	f.outline_size = outline_size
	f.outline_color = outline_color
	return f


func _nearest(weight: int) -> int:
	if weight >= 900:
		return 900
	if weight >= 800:
		return 800
	if weight >= 700:
		return 700
	if weight >= 500:
		return 600
	return 400

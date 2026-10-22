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


## Fuente con contorno (texto sobre fondos de color). También se cachea: se usa
## dentro de _draw(), y una fuente nueva por llamada se libera al salir de la
## función mientras el motor aún tiene que pintar sus letras (en el navegador eso
## llena la consola de "id_map" y acaba tumbando el juego).
func outlined(weight := 800, size := 22, outline_size := 8, outline_color := Color(1, 1, 1, 1)) -> DynamicFont:
	var w := _nearest(weight)
	var key := "%d:%d:o%d:%s" % [w, size, outline_size, outline_color.to_html()]
	if not _cache.has(key):
		var f := DynamicFont.new()
		f.font_data = load(PATHS[w])
		f.size = size
		f.use_filter = true
		f.outline_size = outline_size
		f.outline_color = outline_color
		_cache[key] = f
	return _cache[key]


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

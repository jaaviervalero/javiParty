extends SceneTree
## Genera los PNG de unos QR de prueba para comprobarlos con zbarimg:
##   mkdir -p /tmp/qrt && godot3 --headless --path . -s tests/qr_test.gd -- /tmp/qrt
##   for f in /tmp/qrt/qr_*.png; do zbarimg -q --raw "$f"; done
##
## Escribe qr_0.png, qr_1.png... y expected.txt (las mismas cadenas, una por línea,
## en el mismo orden) para poder comparar el texto decodificado. Cada caso prueba
## algo: URL corta, URL con fragmento, ASCII mínimo, un QR de WiFi (con espacios y
## puntos y coma), una cadena larga (versión >= 7, con información de versión) y
## UTF-8 multibyte (ñ y emoji).

const Qr := preload("res://ui/qr.gd")

const CASES := [
	"http://192.168.1.17:8080",
	"https://jaaviervalero.github.io/javiParty/m#KQZT",
	"HOLA",
	"WIFI:T:WPA;S:MiCasa 5G;P:clave-de-prueba_123;;",
	# Exactamente 150 caracteres: versión alta (>= 7), con información de versión.
	"https://jaaviervalero.github.io/javiParty/m#KQZT?j=1&sala=Salon%20de%20casa&p1=Ana&p2=Luis&p3=Marta&p4=Javi&modo=party&rondas=5&v=3&tema=playa&fin=123",
	"¡Jugador ñ! 🎉",
]


func _init() -> void:
	var out := _output_dir()
	var dir := Directory.new()
	if not dir.dir_exists(out):
		dir.make_dir_recursive(out)

	for n in CASES.size():
		var text: String = CASES[n]
		var modules := Qr.encode(text)
		if modules.empty():
			print("qr_%d.png  FALLO: no cabe (%s)" % [n, text])
			continue
		var path := out.plus_file("qr_%d.png" % n)
		Qr.to_image(text, 8, 4).save_png(path)
		print("qr_%d.png  %d modulos  %s" % [n, modules.size(), text])

	_write_expected(out.plus_file("expected.txt"))
	quit()


## Godot 3.6 no tiene OS.get_cmdline_user_args(): se filtra lo que va tras "--".
func _output_dir() -> String:
	var args := PoolStringArray()
	var after := false
	for a in OS.get_cmdline_args():
		if after:
			args.append(a)
		elif a == "--":
			after = true
	return args[0] if args.size() > 0 else "."


func _write_expected(path: String) -> void:
	var text := ""
	for c in CASES:
		text += c + "\n"
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		print("no se pudo escribir ", path)
		return
	f.store_string(text)
	f.close()

class_name DrawKit
extends RefCounted
## Primitivas de dibujo con la estética de javiParty (consola de salón de los 2000:
## formas redondas, brillos suaves, sombras difusas, colores limpios). Todas reciben
## el CanvasItem en el que dibujar, así que valen en _draw() y en _draw_scenery().
## Pensadas para ir fluidas en Android TV: pocos vértices y sin shaders.

const SHADOW := Color(0.2, 0.3, 0.4, 0.16)
const HIGHLIGHT := Color(1, 1, 1, 0.42)

# Paleta de ambientes (cielos, agua, hierba, arena...) coherente entre juegos.
const SKY_TOP := Color("bfe6fb")
const SKY_BOTTOM := Color("eef8fe")
const GRASS := Color("8fd16b")
const GRASS_DARK := Color("6fb851")
const GRASS_LIGHT := Color("b6e59a")
const WATER := Color("6cc6ea")
const WATER_DARK := Color("3fa6d6")
const SAND := Color("f3dfac")
const SAND_DARK := Color("e2c784")
const WOOD := Color("c99a6b")
const WOOD_DARK := Color("a77a4e")
const STONE := Color("d6dde3")
const GOLD := Color("ffd34d")
const DANGER := Color("e25555")


## Rectángulo con degradado vertical.
static func vgradient(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Contorno de un rectángulo redondeado (para rellenos con degradado o bordes).
static func rounded_rect_points(rect: Rect2, radius: float, steps := 6) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var pts := PackedVector2Array()
	var centers := [rect.end - Vector2(r, r), Vector2(rect.position.x + r, rect.end.y - r),
		rect.position + Vector2(r, r), Vector2(rect.end.x - r, rect.position.y + r)]
	for k in 4:
		for i in steps + 1:
			pts.append(centers[k] + Vector2.from_angle(PI / 2 * k + PI / 2 * i / steps) * r)
	return pts


## Rectángulo redondeado con degradado vertical.
static func rounded_vgradient(ci: CanvasItem, rect: Rect2, radius: float, top: Color, bottom: Color) -> void:
	var pts := rounded_rect_points(rect, radius)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		cols[i] = top.lerp(bottom, (pts[i].y - rect.position.y) / rect.size.y)
	ci.draw_polygon(pts, cols)


## Marco estándar de la zona de juego con ambiente propio: sombra suave, fondo con
## degradado (o sin él si top == bottom) y borde blanco grueso, como una tele de juguete.
static func arena_frame(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color, radius := 30.0) -> void:
	var sh := WiiTheme.panel_style(int(radius), Color(0, 0, 0, 0), Color(0, 0, 0, 0))
	sh.shadow_size = 10
	sh.shadow_offset = Vector2(0, 4)
	ci.draw_style_box(sh, rect)
	rounded_vgradient(ci, rect, radius, top, bottom)


## Borde blanco del marco: llamarlo al final del escenario (encima del decorado) para
## tapar lo que se salga por las esquinas.
static func arena_border(ci: CanvasItem, rect: Rect2, radius := 30.0, width := 6.0) -> void:
	var pts := rounded_rect_points(rect.grow(width / 2.0 - 1.0), radius + width / 2.0)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color.WHITE, width, true)


## Polígono recortado a `clip` (p. ej. rounded_rect_points de la arena). Recortar
## cuesta algo de CPU: úsalo en el escenario estático, no cada frame. Sin clip, tal cual.
static func clipped_polygon(ci: CanvasItem, pts: PackedVector2Array, clip: PackedVector2Array,
		color: Color) -> void:
	if clip.is_empty():
		ci.draw_colored_polygon(pts, color)
		return
	# La intersección de dos polígonos simples no tiene agujeros: se pintan todas las partes.
	for part in Geometry2D.intersect_polygons(pts, clip):
		ci.draw_colored_polygon(part, color)


## Elipse rellena (16-32 segmentos según tamaño).
static func ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var n := clampi(int(maxf(radii.x, radii.y) / 3.0), 12, 32)
	var pts := PackedVector2Array()
	pts.resize(n)
	for i in n:
		var a := TAU * i / n
		pts[i] = center + Vector2(cos(a) * radii.x, sin(a) * radii.y)
	ci.draw_colored_polygon(pts, color)


## Sombra difusa bajo un objeto (elipse aplastada con un halo más claro).
static func soft_shadow(ci: CanvasItem, center: Vector2, width: float, alpha := 1.0) -> void:
	ellipse(ci, center, Vector2(width * 0.62, width * 0.2), Color(SHADOW, SHADOW.a * 0.6 * alpha))
	ellipse(ci, center, Vector2(width * 0.5, width * 0.14), Color(SHADOW, SHADOW.a * alpha))


## Bola con volumen: base, zona inferior más oscura y reflejo arriba a la izquierda.
## Es el "personaje" estándar de los jugadores.
static func glossy_ball(ci: CanvasItem, center: Vector2, r: float, color: Color, shadow := true) -> void:
	if shadow:
		soft_shadow(ci, center + Vector2(0, r * 0.95), r * 2.0)
	ci.draw_circle(center, r, color.darkened(0.12))
	ci.draw_circle(center + Vector2(0, -r * 0.08), r * 0.9, color)
	ci.draw_circle(center + Vector2(-r * 0.32, -r * 0.38), r * 0.36, HIGHLIGHT)
	ci.draw_circle(center + Vector2(-r * 0.42, -r * 0.48), r * 0.14, Color(1, 1, 1, 0.7))


## Bola de jugador con su número en blanco.
static func player_ball(ci: CanvasItem, center: Vector2, r: float, color: Color, number: int,
		font: Font, active := true) -> void:
	var col := color if active else color.lerp(Color("c8ced4"), 0.7)
	glossy_ball(ci, center, r, col)
	var size := int(r * 0.9)
	var txt := str(number)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	ci.draw_string(font, center + Vector2(-ts.x / 2, ts.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


## Nube esponjosa hecha de círculos.
static func cloud(ci: CanvasItem, center: Vector2, scale := 1.0, color := Color(1, 1, 1, 0.9)) -> void:
	var s := 30.0 * scale
	ellipse(ci, center + Vector2(0, s * 0.5), Vector2(s * 2.0, s * 0.55), Color(color, color.a * 0.5))
	for c in [Vector2(-1.2, 0.2), Vector2(-0.4, -0.35), Vector2(0.5, -0.2), Vector2(1.2, 0.25), Vector2(0, 0.3)]:
		ci.draw_circle(center + c * s, s * (0.75 if c.y < 0 else 0.62), color)


## Colinas suaves que rellenan desde base_y hasta el fondo de rect.
static func hills(ci: CanvasItem, rect: Rect2, base_y: float, amplitude: float, color: Color,
		phase := 0.0, waves := 1.6, clip := PackedVector2Array()) -> void:
	var pts := PackedVector2Array()
	var steps := 28
	for i in steps + 1:
		var t := float(i) / steps
		var x := rect.position.x + rect.size.x * t
		pts.append(Vector2(x, base_y - sin(t * TAU * waves * 0.5 + phase) * amplitude
				- sin(t * TAU * waves + phase * 1.7) * amplitude * 0.35))
	pts.append(rect.end)
	pts.append(Vector2(rect.position.x, rect.end.y))
	clipped_polygon(ci, pts, clip, color)


## Olas: banda ondulada (para agua) que puede animarse con `phase`.
static func waves(ci: CanvasItem, rect: Rect2, base_y: float, amplitude: float, color: Color,
		phase := 0.0, length := 120.0, clip := PackedVector2Array()) -> void:
	var pts := PackedVector2Array()
	var x := rect.position.x
	while x <= rect.end.x + 0.5:
		pts.append(Vector2(x, base_y + sin(x / length * TAU + phase) * amplitude))
		x += length / 6.0
	pts.append(Vector2(rect.end.x, rect.end.y))
	pts.append(Vector2(rect.position.x, rect.end.y))
	clipped_polygon(ci, pts, clip, color)


## Panel redondeado con borde y sombra (como las tarjetas de la interfaz).
static func panel(ci: CanvasItem, rect: Rect2, radius := 24, border := Color("cfd8e0"),
		bg := Color.WHITE, border_width := 2) -> void:
	var st := WiiTheme.panel_style(radius, border, bg)
	st.set_border_width_all(border_width)
	ci.draw_style_box(st, rect)


## Destello de cuatro puntas (premios, brillos).
static func sparkle(ci: CanvasItem, center: Vector2, size: float, color := Color.WHITE) -> void:
	var w := size * 0.22
	ci.draw_colored_polygon(PackedVector2Array([
		center + Vector2(0, -size), center + Vector2(w, -w), center + Vector2(size, 0), center + Vector2(w, w),
		center + Vector2(0, size), center + Vector2(-w, w), center + Vector2(-size, 0), center + Vector2(-w, -w),
	]), color)


## Estrella de 5 puntas con borde blanco.
static func star(ci: CanvasItem, center: Vector2, r: float, rot := 0.0, color := GOLD) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(center + Vector2.UP.rotated(rot + i * TAU / 10.0) * rr)
	ci.draw_colored_polygon(pts, color)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(1, 1, 1, color.a), maxf(2.0, r * 0.12), true)


## Sol con rayos suaves (rot permite girarlos despacio).
static func sun(ci: CanvasItem, center: Vector2, r: float, rot := 0.0) -> void:
	for i in 12:
		var a := rot + TAU * i / 12.0
		var d := Vector2.from_angle(a)
		var p := d.orthogonal() * r * 0.18
		ci.draw_colored_polygon(PackedVector2Array([center + d * r * 1.15 + p, center + d * r * 1.6,
			center + d * r * 1.15 - p]), Color(1.0, 0.9, 0.5, 0.55))
	ci.draw_circle(center, r * 1.12, Color(1.0, 0.93, 0.6, 0.5))
	ci.draw_circle(center, r, Color("ffe17a"))
	ci.draw_circle(center + Vector2(-r * 0.3, -r * 0.3), r * 0.35, Color(1, 1, 1, 0.35))


## Texto con contorno (legible sobre cualquier fondo).
static func outlined_text(ci: CanvasItem, font: Font, center: Vector2, text: String, size: int,
		color: Color, outline := Color.WHITE, outline_size := 8) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var pos := center + Vector2(-ts.x / 2, ts.y * 0.32)
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline_size, outline)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Hierba: matojos de briznas sobre una línea (para decorar escenarios estáticos).
static func grass_tufts(ci: CanvasItem, from: Vector2, to: Vector2, count: int, color := GRASS_DARK,
		seed := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var p := from.lerp(to, rng.randf())
		var h := rng.randf_range(8.0, 16.0)
		for k in 3:
			var off := (k - 1) * 4.0
			ci.draw_line(p + Vector2(off, 0), p + Vector2(off * 1.8, -h * (1.0 if k == 1 else 0.7)), color, 2.5, true)


## Tapa las esquinas de `rect` con `color` para que lo dibujado dentro parezca
## redondeado (sin shaders ni recortes: se pinta encima con el color del fondo).
static func round_corners_mask(ci: CanvasItem, rect: Rect2, radius: float, color: Color) -> void:
	var corners := [
		[rect.position, Vector2(1, 1)],
		[Vector2(rect.end.x, rect.position.y), Vector2(-1, 1)],
		[rect.end, Vector2(-1, -1)],
		[Vector2(rect.position.x, rect.end.y), Vector2(1, -1)],
	]
	for c in corners:
		var corner: Vector2 = c[0]
		var dir: Vector2 = c[1]
		var center := corner + dir * radius
		# Polígono entre la esquina y el cuarto de arco que va de un borde al otro.
		var a0 := Vector2(-dir.x, 0).angle()
		var span := wrapf(Vector2(0, -dir.y).angle() - a0, -PI, PI)
		var pts := PackedVector2Array([corner])
		var steps := 8
		for i in steps + 1:
			pts.append(center + Vector2.from_angle(a0 + span * i / steps) * radius)
		ci.draw_colored_polygon(pts, color)


## Flor sencilla (5 pétalos + centro).
static func flower(ci: CanvasItem, center: Vector2, r: float, petal := Color.WHITE, middle := GOLD) -> void:
	for i in 5:
		ci.draw_circle(center + Vector2.from_angle(TAU * i / 5.0 - PI / 2) * r, r * 0.75, petal)
	ci.draw_circle(center, r * 0.7, middle)

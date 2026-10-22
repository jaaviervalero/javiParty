extends MinigameBase
## "A pescar": vista lateral de un estanque. Cada jugador mueve su anzuelo en
## vertical; cuando un pez pica hay que pulsar A con la aguja dentro de la zona.
## Peces grandes valen más y dan menos margen; las botas restan.

const DOCK_Y := 144.0
const WATER_TOP := 200.0
const FISHER_RADIUS := 21.0
const HOOK_RADIUS := 13.0
const HOOK_SPEED := 230.0
const REEL_SPEED := 620.0
const HOOK_MIN_Y := WATER_TOP + 30.0
const COL_MARGIN := 96.0
const BITE_TIME := 2.0
const NEEDLE_SPEED := 1.45
const ZONE_DRIFT := 0.16
const CAUGHT_TIME := 0.7
const ESCAPE_TIME := 1.4

const KINDS := [0, 1, 2, 3]  # pequeño, mediano, grande, bota
const VALUES := [1, 3, 5, -2]
const RADII := [14.0, 20.0, 29.0, 18.0]
const SPEEDS := [115.0, 78.0, 48.0, 62.0]
const ZONE_W := [0.34, 0.25, 0.14, 0.30]
const KIND_COLORS := [Color("8ed4e8"), Color("f7c58e"), Color("b6a4e8"), Color("a08262")]
const FISH_COUNTS := [5, 3, 2, 2]
# Ambiente: estanque luminoso de mañana.
const WATER_LIGHT := Color("d9f0f8")
const WATER_DEEP := Color("b6dfec")
const BANK_SAND := Color("f0e0b8")
const REED := Color("7fae6a")
const REED_DARK := Color("5f9450")
const CATKIN := Color("9a6b4a")
const LILY := Color("8fce7e")
const LILY_DARK := Color("6fb862")


class Fisher:
	var player: Player
	var x := 0.0
	var hook_y := 0.0
	var bite_fish = null
	var bite_t := 0.0
	var needle := 0.0
	var needle_dir := 1.0
	var zone_center := 0.5
	var zone_dir := 1.0
	var zone_w := 0.3
	var shake := 0.0
	var sfx_t := 0.0


class Fish:
	var kind := 0
	var pos := Vector2.ZERO
	var dir := 1.0
	var speed := 100.0
	var base_speed := 100.0
	var r := 16.0
	var bump := 0.0       # fase de la cola
	var biting := false
	var caught_t := 0.0
	var caught_from := Vector2.ZERO
	var owner_fisher = null
	var escape_t := 0.0


var _fishers: Array[Fisher] = []
var _fish: Array[Fish] = []
var _confetti: Array = []
var _time := 0.0


func _configure() -> void:
	title = {"es": "A pescar", "en": "Gone Fishing"}
	instructions = {"es": "Baja el anzuelo, espera a que pique y pulsa A en el momento justo.",
		"en": "Lower your hook, wait for a bite and press A at the right moment."}
	controls = [
		["stick", {"es": "Subir y bajar el anzuelo", "en": "Raise and lower the hook"}],
		[Pad.A, {"es": "Clavar el pez", "en": "Hook the fish"}],
		[Pad.B, {"es": "Recoger rápido", "en": "Reel in fast"}],
	]
	duration = 45.0


func _setup() -> void:
	var n := players.size()
	var usable := ARENA.size.x - COL_MARGIN * 2.0
	for i in n:
		var p := players[i]
		var f := Fisher.new()
		f.player = p
		f.x = ARENA.position.x + COL_MARGIN + usable * (float(i) + 0.5) / float(n)
		f.hook_y = WATER_TOP + 70.0
		_fishers.append(f)
	for i in KINDS.size():
		for j in FISH_COUNTS[i]:
			_fish.append(_make_fish(i, true))


func _make_fish(kind: int, anywhere: bool) -> Fish:
	var f := Fish.new()
	f.kind = kind
	f.r = RADII[kind]
	f.speed = SPEEDS[kind] * randf_range(0.85, 1.15)
	f.base_speed = f.speed
	f.dir = -1.0 if randf() < 0.5 else 1.0
	var lo_y := WATER_TOP + 50.0
	var hi_y := ARENA.end.y - 46.0
	f.pos.y = randf_range(lo_y, hi_y)
	if anywhere:
		f.pos.x = randf_range(ARENA.position.x + 40.0, ARENA.end.x - 40.0)
	else:
		f.pos.x = ARENA.end.x + 70.0 if f.dir < 0.0 else ARENA.position.x - 70.0
	return f


func _game_process(delta: float) -> void:
	_time += delta
	for f in _fishers:
		_update_fisher(f, delta)
	for fi in _fish:
		_update_fish(fi, delta)
	_check_bites()
	_update_effects(delta)


# --- Pescadores ---

func _update_fisher(f: Fisher, delta: float) -> void:
	f.sfx_t = maxf(0.0, f.sfx_t - delta)
	f.shake = maxf(0.0, f.shake - delta)
	var p := f.player
	if f.bite_fish != null:
		# Minijuego de tensión: la aguja va y viene; A en la zona verde.
		f.bite_t -= delta
		f.needle += f.needle_dir * NEEDLE_SPEED * delta
		if f.needle >= 1.0:
			f.needle = 1.0
			f.needle_dir = -1.0
		elif f.needle <= 0.0:
			f.needle = 0.0
			f.needle_dir = 1.0
		# La zona buena también se mueve despacio.
		var half := f.zone_w * 0.5
		f.zone_center += f.zone_dir * ZONE_DRIFT * delta
		if f.zone_center >= 1.0 - half - 0.04:
			f.zone_center = 1.0 - half - 0.04
			f.zone_dir = -1.0
		elif f.zone_center <= half + 0.04:
			f.zone_center = half + 0.04
			f.zone_dir = 1.0
		if p.just_pressed(Pad.A):
			var ok := absf(f.needle - f.zone_center) <= f.zone_w * 0.5
			_end_bite(f, ok)
		elif p.is_pressed(Pad.B) or f.bite_t <= 0.0:
			_end_bite(f, false)
		return
	var dir_y := 0.0
	var stick := p.stick()
	var digital := p.dpad()
	if absf(stick.y) > 0.05:
		dir_y = signf(stick.y)
	elif digital.y != 0.0:
		dir_y = digital.y
	var speed := HOOK_SPEED
	if p.is_pressed(Pad.B):
		dir_y = -1.0
		speed = REEL_SPEED
	if dir_y != 0.0:
		f.hook_y = clampf(f.hook_y + dir_y * speed * delta, HOOK_MIN_Y, _hook_max_y())
		if f.sfx_t <= 0.0:
			f.sfx_t = 0.22
			Sfx.play("move", randf_range(0.9, 1.05))


func _hook_max_y() -> float:
	return ARENA.end.y - 38.0


func _check_bites() -> void:
	for f in _fishers:
		if f.bite_fish != null or f.hook_y < WATER_TOP + 24.0:
			continue
		var hook := Vector2(f.x, f.hook_y)
		for fi in _fish:
			if fi.biting or fi.caught_t > 0.0 or fi.escape_t > 0.0:
				continue
			if hook.distance_to(fi.pos) < fi.r + HOOK_RADIUS:
				_start_bite(f, fi)
				break


func _start_bite(f: Fisher, fi: Fish) -> void:
	f.bite_fish = fi
	fi.biting = true
	fi.owner_fisher = f
	f.bite_t = BITE_TIME
	f.needle = 0.0
	f.needle_dir = 1.0
	f.zone_w = ZONE_W[fi.kind]
	f.zone_center = randf_range(f.zone_w * 0.5 + 0.06, 1.0 - f.zone_w * 0.5 - 0.06)
	f.zone_dir = -1.0 if randf() < 0.5 else 1.0
	f.shake = 0.3
	# El pez se queda enganchado junto al anzuelo.
	fi.pos = Vector2(f.x, clampf(f.hook_y, WATER_TOP + 30.0, _hook_max_y()))
	Sfx.play("pop", randf_range(0.85, 1.1))


func _end_bite(f: Fisher, ok: bool) -> void:
	var fi: Fish = f.bite_fish
	f.bite_fish = null
	if fi == null:
		return
	fi.biting = false
	if ok:
		# Capturado: sube con el anzuelo y suma.
		fi.caught_t = CAUGHT_TIME
		fi.caught_from = fi.pos
		add_score(f.player, VALUES[fi.kind])
		_burst(fi.pos, KIND_COLORS[fi.kind], 12)
		if fi.kind == 3:
			Sfx.play("back", 0.7)
		else:
			Sfx.play("star", randf_range(0.95, 1.15))
	else:
		# Se escapa: se aleja nadando rápido y no vuelve a picar de momento.
		fi.escape_t = ESCAPE_TIME
		fi.dir = -fi.dir
		fi.speed = fi.base_speed * 2.0
		fi.bump = 0.0
		Sfx.play("back", randf_range(0.8, 1.0))


# --- Peces ---

func _update_fish(fi: Fish, delta: float) -> void:
	fi.bump += delta * (10.0 + fi.speed * 0.05)
	if fi.escape_t > 0.0:
		fi.escape_t = maxf(0.0, fi.escape_t - delta)
		if fi.escape_t <= 0.0:
			fi.speed = fi.base_speed
	if fi.caught_t > 0.0:
		fi.caught_t = maxf(0.0, fi.caught_t - delta / CAUGHT_TIME)
		var f: Fisher = fi.owner_fisher
		var top := Vector2(f.x, DOCK_Y + FISHER_RADIUS) if f != null else fi.caught_from
		fi.pos = fi.caught_from.lerp(top, 1.0 - fi.caught_t)
		if fi.caught_t <= 0.0:
			_respawn(fi)
		return
	if fi.biting:
		return
	fi.pos.x += fi.dir * fi.speed * delta
	if fi.pos.x < ARENA.position.x - 90.0 or fi.pos.x > ARENA.end.x + 90.0:
		_respawn(fi)


func _respawn(fi: Fish) -> void:
	var fresh := _make_fish(fi.kind, false)
	fi.pos = fresh.pos
	fi.dir = fresh.dir
	fi.speed = fresh.speed
	fi.base_speed = fresh.base_speed
	fi.biting = false
	fi.caught_t = 0.0
	fi.escape_t = 0.0
	fi.owner_fisher = null
	fi.bump = 0.0


# --- Efectos ---

func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * randf_range(80.0, 300.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color.WHITE, randf_range(0.4, 0.8)])


func _update_effects(delta: float) -> void:
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 380) * delta
		c[3] -= delta
	_confetti = _confetti.filter(func(c): return c[3] > 0.0)


# --- Dibujo ---

## Escenario fijo: se pinta una vez (MinigameBase._draw_scenery).
func _draw_scenery(ci: CanvasItem) -> void:
	var clip := DrawKit.rounded_rect_points(ARENA, 30)
	var inner := ARENA.grow(-10.0)
	DrawKit.arena_frame(ci, ARENA, Color("f2fbff"), Color("bfe4f0"))
	# Cielo claro sobre el muelle.
	ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, WATER_TOP - inner.position.y)),
			Color("eef7fb"))
	# Agua del estanque, más profunda al fondo.
	var water := Rect2(inner.position.x, WATER_TOP, inner.size.x, inner.end.y - WATER_TOP)
	DrawKit.vgradient(ci, water, WATER_LIGHT, WATER_DEEP)
	# Reflejos suaves bajo los postes y brillo del cielo.
	for i in 7:
		var rx := inner.position.x + 40.0 + i * (inner.size.x - 80.0) / 6.0
		DrawKit.ellipse(ci, Vector2(rx, WATER_TOP + 34.0), Vector2(17.0, 4.0), Color(1, 1, 1, 0.32))
	DrawKit.ellipse(ci, Vector2(inner.position.x + 300.0, WATER_TOP + 12.0), Vector2(190.0, 9.0),
			Color(1, 1, 1, 0.18))
	# Muelle de madera.
	ci.draw_rect(Rect2(inner.position.x, inner.position.y, inner.size.x,
			WATER_TOP - inner.position.y), Color("e6d3b3"))
	for i in 6:
		var ly := inner.position.y + 10.0 + i * 18.0
		ci.draw_line(Vector2(inner.position.x, ly), Vector2(inner.end.x, ly), Color("cdb894"), 3.0)
	# Postes del muelle sobre el agua.
	for i in 7:
		var px := inner.position.x + 40.0 + i * (inner.size.x - 80.0) / 6.0
		ci.draw_line(Vector2(px, WATER_TOP - 14.0), Vector2(px, WATER_TOP + 16.0),
				Color("a8885f"), 8.0)
	# Orilla de arena a la izquierda.
	var bank := PackedVector2Array([
		Vector2(inner.position.x, WATER_TOP - 4.0),
		Vector2(inner.position.x + 168.0, WATER_TOP + 8.0),
		Vector2(inner.position.x + 118.0, WATER_TOP + 74.0),
		Vector2(inner.position.x + 40.0, WATER_TOP + 150.0),
		Vector2(inner.position.x, WATER_TOP + 190.0),
	])
	DrawKit.clipped_polygon(ci, bank, clip, BANK_SAND)
	# Juncos y cañas en la orilla.
	_draw_reeds(ci, Vector2(inner.position.x + 54.0, WATER_TOP + 34.0), 5, 11)
	_draw_reeds(ci, Vector2(inner.position.x + 132.0, WATER_TOP + 46.0), 3, 23)
	# Nenúfares.
	for i in 3:
		var p := Vector2(inner.position.x + 250.0 + i * 66.0, WATER_TOP + 136.0 + (i % 2) * 72.0)
		DrawKit.ellipse(ci, p, Vector2(25.0, 10.0), LILY_DARK)
		DrawKit.ellipse(ci, p + Vector2(0, -2.0), Vector2(22.0, 8.0), LILY)
	DrawKit.flower(ci, Vector2(inner.position.x + 382.0, WATER_TOP + 133.0), 6.0,
			Color("ffd1e3"), Color("fff3c4"))
	DrawKit.arena_border(ci, ARENA)


## Juncos: tallos verdes con espiga en la punta.
func _draw_reeds(ci: CanvasItem, base: Vector2, count: int, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var bx := base.x + rng.randf_range(-26.0, 26.0)
		var h := rng.randf_range(54.0, 92.0)
		var lean := rng.randf_range(-12.0, 12.0)
		var tip := Vector2(bx + lean, base.y - h)
		ci.draw_line(Vector2(bx, base.y), tip, REED, 3.0, true)
		ci.draw_line(Vector2(bx, base.y - h * 0.42),
				Vector2(bx + lean * 0.5 + 11.0, base.y - h * 0.66), REED_DARK, 2.0, true)
		DrawKit.ellipse(ci, tip + Vector2(lean * 0.08, 6.0), Vector2(4.0, 12.0), CATKIN)


## MinigameBase llama a queue_redraw() cada frame: aquí solo lo que se mueve.
func _draw() -> void:
	_draw_water_bands()
	for fi in _fish:
		_draw_fish(fi)
	for f in _fishers:
		_draw_fisher(f)
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(3, 3), Vector2(6, 6)), Color(c[2], clampf(c[3] * 2.0, 0.0, 1.0)))


## Dos bandas de olas animadas (baratas: solo la franja alta del agua).
func _draw_water_bands() -> void:
	var inner := ARENA.grow(-10.0)
	DrawKit.waves(self, Rect2(inner.position.x, WATER_TOP, inner.size.x, 92.0),
			WATER_TOP + 28.0, 5.0, Color(1, 1, 1, 0.16), _time * 0.9, 140.0)
	DrawKit.waves(self, Rect2(inner.position.x, WATER_TOP + 62.0, inner.size.x, 104.0),
			WATER_TOP + 98.0, 4.0, Color(0.72, 0.9, 0.96, 0.18), _time * 0.6 + 2.0, 180.0)


func _draw_fisher(f: Fisher) -> void:
	var p := f.player
	var col := p.color
	var base := Vector2(f.x, DOCK_Y)
	# Anzuelo y sedal (tiembla cuando pica).
	var shake_x := 0.0
	if f.bite_fish != null:
		shake_x = sin(_time * 42.0) * 3.5
	var hook := Vector2(f.x + shake_x, f.hook_y)
	draw_line(base, hook + Vector2(0, -6), Color("7f8c96"), 2.5, true)
	draw_arc(hook + Vector2(0, 2), 9.0, -PI * 0.15, PI * 1.15, 16, Color("5b6670"), 3.5, true)
	draw_circle(hook + Vector2(0, -10), 4.0, Color("e25555"))
	# Pescador.
	draw_circle(base + Vector2(0, 5), FISHER_RADIUS, WiiTheme.SHADOW)
	draw_circle(base, FISHER_RADIUS, col)
	draw_circle(base + Vector2(-FISHER_RADIUS * 0.3, -FISHER_RADIUS * 0.32),
			FISHER_RADIUS * 0.34, Color(1, 1, 1, 0.45))
	draw_text_centered(str(p.index + 1), base, 20, Color.WHITE)
	if f.bite_fish != null:
		_draw_tension(f, hook)


func _draw_tension(f: Fisher, hook: Vector2) -> void:
	var w := 190.0
	var x0 := f.x - w * 0.5
	var y := hook.y - 52.0
	var box := Rect2(x0, y, w, 20.0)
	var st := WiiTheme.panel_style(10, f.player.color)
	st.shadow_size = 3
	draw_style_box(st, box)
	# Zona buena.
	var zx := x0 + (f.zone_center - f.zone_w * 0.5) * w
	draw_rect(Rect2(zx, y + 3.0, f.zone_w * w, 14.0), Color("4cbf6b"))
	# Aguja.
	var nx := x0 + f.needle * w
	draw_rect(Rect2(nx - 3.0, y - 4.0, 6.0, 28.0), f.player.color.darkened(0.15))
	draw_text_centered("A", Vector2(f.x, y - 22.0), 24, f.player.color.darkened(0.1))
	# Cuenta atrás de la picada.
	draw_arc(hook, 26.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(f.bite_t / BITE_TIME, 0.0, 1.0),
			28, Color(f.player.color, 0.55), 4.0, true)


func _draw_fish(fi: Fish) -> void:
	var alpha := 1.0
	if fi.caught_t > 0.0:
		alpha = clampf(fi.caught_t * 1.6, 0.0, 1.0)
	if fi.kind == 3:
		_draw_boot(fi.pos, fi.dir, alpha)
		return
	var col: Color = KIND_COLORS[fi.kind]
	var rx := fi.r * 1.25
	var ry := fi.r * 0.62
	var wiggle := sin(fi.bump) * 0.18
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(fi.pos + Vector2(cos(a) * rx * fi.dir, sin(a) * ry))
	draw_colored_polygon(pts, Color(col, alpha))
	# Cola triangular a contralto del morro.
	var tail_x := fi.pos.x - fi.dir * rx * 0.92
	var tw := fi.r * 0.6
	var tail := PackedVector2Array([
		Vector2(tail_x, fi.pos.y),
		Vector2(tail_x - fi.dir * fi.r * 0.7, fi.pos.y - tw + wiggle * fi.r * 0.4),
		Vector2(tail_x - fi.dir * fi.r * 0.7, fi.pos.y + tw + wiggle * fi.r * 0.4),
	])
	draw_colored_polygon(tail, Color(col.darkened(0.12), alpha))
	# Aleta y ojo.
	draw_circle(fi.pos + Vector2(-fi.dir * fi.r * 0.12, -fi.r * 0.18),
			fi.r * 0.28, Color(1, 1, 1, 0.35 * alpha))
	var eye := fi.pos + Vector2(fi.dir * rx * 0.55, -ry * 0.2)
	draw_circle(eye, fi.r * 0.15, Color(1, 1, 1, alpha))
	draw_circle(eye + Vector2(fi.dir * 2.0, 0), fi.r * 0.08, Color(0.2, 0.25, 0.3, alpha))
	# Vale X puntos: rayas para que se distinga el tamaño de un vistazo.
	var stripes := fi.kind + 1
	for i in stripes:
		var sx := fi.pos.x - fi.dir * (fi.r * 0.3 - i * fi.r * 0.28)
		draw_line(Vector2(sx, fi.pos.y - ry * 0.45), Vector2(sx, fi.pos.y + ry * 0.45),
				Color(1, 1, 1, 0.35 * alpha), 3.0)


func _draw_boot(pos: Vector2, dir: float, alpha: float) -> void:
	var col := Color(KIND_COLORS[3], alpha)
	var pts := PackedVector2Array([
		pos + Vector2(-10 * dir, -16),
		pos + Vector2(4 * dir, -16),
		pos + Vector2(6 * dir, 2),
		pos + Vector2(22 * dir, 8),
		pos + Vector2(22 * dir, 16),
		pos + Vector2(-10 * dir, 16),
		pos + Vector2(-10 * dir, -4),
	])
	draw_colored_polygon(pts, col)
	draw_line(pos + Vector2(-14 * dir, 15), pos + Vector2(24 * dir, 15),
			Color(0.2, 0.15, 0.1, 0.55 * alpha), 4.0)
	draw_circle(pos + Vector2(8 * dir, -6), 2.5, Color(1, 1, 1, 0.5 * alpha))

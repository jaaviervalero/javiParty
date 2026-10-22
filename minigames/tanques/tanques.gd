extends MinigameBase
## "Tanquecitos": arena con bloques; cada jugador es un tanque. El cañón apunta
## hacia donde te mueves y las balas rebotan dos veces en paredes y bloques.
## A dispara, B da un acelerón. Con 1 jugador hay dianas móviles.

const TANK_RADIUS := 22.0
const TANK_SPEED := 210.0
const BOOST_SPEED := 520.0
const BOOST_TIME := 0.28
const BOOST_COOLDOWN := 2.0
const BULLET_RADIUS := 7.0
const BULLET_SPEED := 430.0
const BULLET_COOLDOWN := 0.35
const BULLET_MAX_OWN := 3
const BULLET_MAX_BOUNCES := 2
const RESPAWN_TIME := 1.5
const INVULN_TIME := 1.5
const TARGET_RADIUS := 26.0
const TARGET_SPEED := 170.0
const EDGE := 34.0
# Ambiente: cajón de arena del jardín.
const SAND_TOP := Color("f9ecc4")
const SAND_BOTTOM := Color("ecd39b")
const SAND_MARK := Color("dcc287")
const PEBBLE := Color("c9b184")
const POLLEN := Color("fff3c4")


## Un tanque y su estado (sin nodos).
class Tank:
	var player: Player
	var pos: Vector2
	var home: Vector2
	var aim := Vector2.RIGHT
	var cool := 0.0
	var boost_cd := 0.0
	var boost_t := 0.0
	var boost_dir := Vector2.ZERO
	var dead_t := 0.0
	var invuln := 0.0
	var recoil := 0.0


## Una bala con dueño y rebotes restantes.
class Bullet:
	var owner_tank: Tank
	var pos: Vector2
	var vel: Vector2
	var bounces := 0
	var dead := false


var _tanks: Array = []
var _bullets: Array = []
var _blocks: Array = []
var _targets: Array = []  # [pos, vel, radio]
var _confetti: Array = []  # [pos, vel, color, vida]
var _time := 0.0
var _single := false


func _configure() -> void:
	title = {"es": "Tanquecitos", "en": "Tiny Tanks"}
	instructions = {"es": "Dispara a los demás tanques: las balas rebotan dos veces.",
		"en": "Shoot the other tanks: bullets bounce twice."}
	controls = [
		["stick", {"es": "Mover y apuntar", "en": "Move and aim"}],
		[Pad.A, {"es": "Disparar", "en": "Shoot"}],
		[Pad.B, {"es": "Acelerón", "en": "Boost"}],
	]
	duration = 50.0


func _setup() -> void:
	_single = players.size() == 1
	var c := ARENA.get_center()
	# Bloques simétricos respecto al centro de la arena.
	_blocks = [
		Rect2(c + Vector2(-90, -16), Vector2(180, 32)),
		Rect2(c + Vector2(-238, -196), Vector2(36, 150)),
		Rect2(c + Vector2(202, -196), Vector2(36, 150)),
		Rect2(c + Vector2(-260, 74), Vector2(150, 34)),
		Rect2(c + Vector2(110, 74), Vector2(150, 34)),
		Rect2(c + Vector2(-18, -256), Vector2(36, 120)),
		Rect2(c + Vector2(-18, 136), Vector2(36, 120)),
	]
	var corners := [c + Vector2(-470, -210), c + Vector2(470, -210),
			c + Vector2(-470, 210), c + Vector2(470, 210)]
	for p in players:
		var t := Tank.new()
		t.player = p
		t.home = corners[p.index]
		t.pos = t.home
		t.aim = (c - t.pos).normalized()
		_tanks.append(t)
	if _single:
		for i in 2:
			_targets.append([c + Vector2(-200 + 400 * i, -120), Vector2(0, 0)])


func _game_start() -> void:
	for i in _targets.size():
		_targets[i][1] = Vector2.RIGHT.rotated(randf() * TAU) * TARGET_SPEED


func _game_process(delta: float) -> void:
	_time += delta
	for t in _tanks:
		_update_tank(t, delta)
	_collide_tanks()
	_update_bullets(delta)
	_update_targets(delta)
	_update_effects(delta)


# --- Tanques ---

func _update_tank(t: Tank, delta: float) -> void:
	t.cool = max(0.0, t.cool - delta)
	t.boost_cd = max(0.0, t.boost_cd - delta)
	t.boost_t = max(0.0, t.boost_t - delta)
	t.recoil = max(0.0, t.recoil - delta * 5.0)
	if t.dead_t > 0.0:
		t.dead_t -= delta
		if t.dead_t <= 0.0:
			t.pos = t.home
			t.invuln = INVULN_TIME
		return
	t.invuln = max(0.0, t.invuln - delta)
	var p := t.player
	var dir := p.stick() if p.stick() != Vector2.ZERO else p.dpad().normalized()
	if dir != Vector2.ZERO:
		t.aim = dir.normalized()
	var move := dir * TANK_SPEED
	if t.boost_t > 0.0:
		move += t.boost_dir * BOOST_SPEED * (t.boost_t / BOOST_TIME)
	t.pos += move * delta
	_collide_blocks(t)
	t.pos = _clamped_arena(t.pos, TANK_RADIUS)
	if p.just_pressed(Pad.A) and t.cool <= 0.0:
		_fire(t)
	if p.just_pressed(Pad.B) and t.boost_cd <= 0.0:
		t.boost_cd = BOOST_COOLDOWN
		t.boost_t = BOOST_TIME
		t.boost_dir = t.aim
		Sfx.play("dash", 1.15)


func _collide_blocks(t: Tank) -> void:
	for b in _blocks:
		var n := _circle_rect_normal(t.pos, TANK_RADIUS, b)
		if n != Vector2.ZERO:
			var closest := _closest_point(t.pos, b)
			var inside: bool = b.has_point(t.pos)
			var push := TANK_RADIUS - t.pos.distance_to(closest)
			if inside:
				push = TANK_RADIUS + _inside_depth(t.pos, b)
			t.pos = _clamped_arena(t.pos + n * push, TANK_RADIUS)


func _collide_tanks() -> void:
	for i in _tanks.size():
		for j in range(i + 1, _tanks.size()):
			var a: Tank = _tanks[i]
			var b: Tank = _tanks[j]
			if a.dead_t > 0.0 or b.dead_t > 0.0:
				continue
			var d := b.pos - a.pos
			var dist := d.length()
			if dist < TANK_RADIUS * 2.0 and dist > 0.01:
				var n := d / dist
				var push := (TANK_RADIUS * 2.0 - dist) * 0.5
				a.pos = _clamped_arena(a.pos - n * push, TANK_RADIUS)
				b.pos = _clamped_arena(b.pos + n * push, TANK_RADIUS)


func _fire(t: Tank) -> void:
	if _own_bullets(t) >= BULLET_MAX_OWN:
		return
	var b := Bullet.new()
	b.owner_tank = t
	b.pos = t.pos + t.aim * (TANK_RADIUS + BULLET_RADIUS + 2.0)
	b.vel = t.aim * BULLET_SPEED
	_bullets.append(b)
	t.cool = BULLET_COOLDOWN
	t.recoil = 1.0
	t.pos -= t.aim * 3.0
	Sfx.play("pop", rand_range(0.75, 0.85))


func _own_bullets(t: Tank) -> int:
	var n := 0
	for b in _bullets:
		if b.owner_tank == t:
			n += 1
	return n


# --- Balas ---

func _update_bullets(delta: float) -> void:
	var lo := ARENA.position + Vector2(BULLET_RADIUS, BULLET_RADIUS)
	var hi := ARENA.end - Vector2(BULLET_RADIUS, BULLET_RADIUS)
	for b in _bullets:
		if b.dead:
			continue
		b.pos += b.vel * delta
		# Paredes de la arena: rebote o fin si ya gastó los dos.
		var hit_x: bool = b.pos.x <= lo.x or b.pos.x >= hi.x
		var hit_y: bool = b.pos.y <= lo.y or b.pos.y >= hi.y
		if hit_x or hit_y:
			b.pos.x = clamp(b.pos.x, lo.x, hi.x)
			b.pos.y = clamp(b.pos.y, lo.y, hi.y)
			if b.bounces >= BULLET_MAX_BOUNCES:
				b.dead = true
				continue
			b.bounces += 1
			if hit_x:
				b.vel.x *= -1.0
			if hit_y:
				b.vel.y *= -1.0
			Sfx.play("move", rand_range(1.3, 1.6))
			_burst(b.pos, Color("9fb4c6"), 3)
			continue
		# Bloques.
		var bounced := false
		for blk in _blocks:
			var nr := _circle_rect_normal(b.pos, BULLET_RADIUS, blk)
			if nr == Vector2.ZERO:
				continue
			bounced = true
			if b.bounces >= BULLET_MAX_BOUNCES:
				b.dead = true
				break
			b.bounces += 1
			b.vel = b.vel.bounce(nr)
			b.pos += nr * (BULLET_RADIUS + 2.0)
			Sfx.play("move", rand_range(1.3, 1.6))
			_burst(b.pos, Color("9fb4c6"), 3)
			break
		if bounced:
			continue
		# Tanques.
		var hit := false
		for t in _tanks:
			if t.dead_t > 0.0:
				continue
			if t.pos.distance_to(b.pos) >= TANK_RADIUS + BULLET_RADIUS:
				continue
			if t == b.owner_tank:
				# Las propias no hacen nada hasta el primer rebote.
				if b.bounces == 0:
					continue
				set_score(t.player, max(0, get_score(t.player) - 1))
				_explode(t)
			elif t.invuln <= 0.0:
				add_score(b.owner_tank.player)
				_explode(t)
			hit = true
			break
		if hit:
			b.dead = true
			continue
		# Dianas (1 jugador).
		for tg in _targets:
			if b.pos.distance_to(tg[0]) < TARGET_RADIUS + BULLET_RADIUS:
				add_score(b.owner_tank.player)
				_burst(tg[0], Color("ffd34d"), 16)
				tg[0] = _random_target_pos()
				tg[1] = Vector2.RIGHT.rotated(randf() * TAU) * TARGET_SPEED
				Sfx.play("star", rand_range(0.95, 1.1))
				b.dead = true
				break
	var live_bullets: Array = []
	for b in _bullets:
		if not b.dead:
			live_bullets.append(b)
	_bullets = live_bullets


func _explode(t: Tank) -> void:
	_burst(t.pos, t.player.color, 26)
	Sfx.play("wave", 1.2)
	t.dead_t = RESPAWN_TIME
	t.boost_t = 0.0


# --- Dianas ---

func _update_targets(delta: float) -> void:
	for tg in _targets:
		tg[0] += tg[1] * delta
		var lo := ARENA.position + Vector2(TARGET_RADIUS, TARGET_RADIUS)
		var hi := ARENA.end - Vector2(TARGET_RADIUS, TARGET_RADIUS)
		if tg[0].x < lo.x or tg[0].x > hi.x:
			tg[0].x = clamp(tg[0].x, lo.x, hi.x)
			tg[1].x *= -1.0
		if tg[0].y < lo.y or tg[0].y > hi.y:
			tg[0].y = clamp(tg[0].y, lo.y, hi.y)
			tg[1].y *= -1.0
		for blk in _blocks:
			var n := _circle_rect_normal(tg[0], TARGET_RADIUS, blk)
			if n != Vector2.ZERO:
				tg[1] = tg[1].bounce(n)
				tg[0] += n * 4.0
				break


func _random_target_pos() -> Vector2:
	var c := ARENA.get_center()
	for i in 12:
		var q := c + Vector2(rand_range(-460, 460), rand_range(-220, 220))
		var ok := true
		for blk in _blocks:
			if blk.grow(TARGET_RADIUS + 6.0).has_point(q):
				ok = false
				break
		if ok:
			return q
	return c


# --- Efectos ---

func _burst(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var v := Vector2.RIGHT.rotated(randf() * TAU) * rand_range(80.0, 360.0)
		_confetti.append([at, v, color if i % 2 == 0 else Color(1, 1, 1, 1), rand_range(0.4, 0.8)])


func _update_effects(delta: float) -> void:
	for c in _confetti:
		c[0] += c[1] * delta
		c[1] = c[1] * exp(-3.0 * delta) + Vector2(0, 400) * delta
		c[3] -= delta
	var live: Array = []
	for c in _confetti:
		if c[3] > 0.0:
			live.append(c)
	_confetti = live


# --- Utilidades de colisión ---

func _clamped_arena(pos: Vector2, r: float) -> Vector2:
	return Vector2(clamp(pos.x, ARENA.position.x + r, ARENA.end.x - r),
			clamp(pos.y, ARENA.position.y + r, ARENA.end.y - r))


func _closest_point(p: Vector2, rect: Rect2) -> Vector2:
	return Vector2(clamp(p.x, rect.position.x, rect.end.x), clamp(p.y, rect.position.y, rect.end.y))


## Normal (hacia fuera) si el círculo toca el rectángulo; ZERO si no.
func _circle_rect_normal(center: Vector2, r: float, rect: Rect2) -> Vector2:
	var cp := _closest_point(center, rect)
	var d := center - cp
	if d.length() > 0.001:
		return d / d.length() if d.length() < r else Vector2.ZERO
	# Centro dentro del rectángulo: sale por el lado más cercano.
	var dl := center.x - rect.position.x
	var dr := rect.end.x - center.x
	var dt := center.y - rect.position.y
	var db := rect.end.y - center.y
	var m := min(min(dl, dr), min(dt, db))
	if m == dl:
		return Vector2.LEFT
	if m == dr:
		return Vector2.RIGHT
	if m == dt:
		return Vector2.UP
	return Vector2.DOWN


func _inside_depth(center: Vector2, rect: Rect2) -> float:
	var dl := center.x - rect.position.x
	var dr := rect.end.x - center.x
	var dt := center.y - rect.position.y
	var db := rect.end.y - center.y
	return min(min(dl, dr), min(dt, db))


# --- Dibujo ---

## Ambiente fijo: cajón de arena del jardín. Se pinta una vez.
func _draw_scenery(ci: CanvasItem) -> void:
	DrawKit.arena_frame(ci, ARENA, SAND_TOP, SAND_BOTTOM)
	# Huellas y piedrecitas repartidas (semilla fija: siempre las mismas).
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 8:
		var p := Vector2(rng.randf_range(ARENA.position.x + 90.0, ARENA.end.x - 90.0),
				rng.randf_range(ARENA.position.y + 90.0, ARENA.end.y - 70.0))
		var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
		for k in 2:
			DrawKit.ellipse(ci, p + dir * (k * 18.0 - 9.0), Vector2(8.0, 4.5), Color(SAND_MARK, 0.5))
	for i in 26:
		var p := Vector2(rng.randf_range(ARENA.position.x + 40.0, ARENA.end.x - 40.0),
				rng.randf_range(ARENA.position.y + 40.0, ARENA.end.y - 30.0))
		ci.draw_circle(p, rng.randf_range(1.6, 3.4), Color(PEBBLE, rng.randf_range(0.45, 0.8)))
	# Matas de hierba en los bordes del cajón.
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 34.0, ARENA.end.y - 16.0),
			Vector2(ARENA.end.x - 34.0, ARENA.end.y - 16.0), 20, DrawKit.GRASS_DARK, 5)
	DrawKit.grass_tufts(ci, Vector2(ARENA.position.x + 42.0, ARENA.position.y + 30.0),
			Vector2(ARENA.position.x + 250.0, ARENA.position.y + 30.0), 6, DrawKit.GRASS_DARK, 9)
	DrawKit.grass_tufts(ci, Vector2(ARENA.end.x - 250.0, ARENA.position.y + 30.0),
			Vector2(ARENA.end.x - 42.0, ARENA.position.y + 30.0), 6, DrawKit.GRASS_DARK, 21)
	# Bloques de madera: se crean en _setup y no cambian durante la partida.
	for blk in _blocks:
		_draw_block(ci, blk)
	DrawKit.arena_border(ci, ARENA)


## Bloque de madera de juguete: canto oscuro, cara clara y brillo arriba.
func _draw_block(ci: CanvasItem, blk: Rect2) -> void:
	DrawKit.soft_shadow(ci, Vector2(blk.get_center().x, blk.end.y + 4.0), blk.size.x * 0.8, 0.55)
	ci.draw_colored_polygon(DrawKit.rounded_rect_points(blk.grow(4.0), 12.0), DrawKit.WOOD_DARK)
	ci.draw_colored_polygon(DrawKit.rounded_rect_points(blk, 10.0), DrawKit.WOOD)
	ci.draw_line(blk.position + Vector2(8.0, 8.0), Vector2(blk.end.x - 8.0, blk.position.y + 8.0),
			Color(1, 1, 1, 0.35), 5.0, true)
	ci.draw_line(Vector2(blk.position.x + 8.0, blk.get_center().y + 2.0),
			Vector2(blk.end.x - 8.0, blk.get_center().y + 2.0), Color(DrawKit.WOOD_DARK, 0.35), 2.0)


## MinigameBase llama a queue_redraw() cada frame: aquí solo lo que se mueve.
func _draw() -> void:
	_draw_pollen()
	for tg in _targets:
		_draw_target(tg[0])
	for t in _tanks:
		_draw_tank(t)
	for b in _bullets:
		draw_circle(b.pos, BULLET_RADIUS + 2.0, Color(0, 0, 0, 0.10))
		draw_circle(b.pos, BULLET_RADIUS, b.owner_tank.player.color.lightened(0.15))
		draw_circle(b.pos + Vector2(-1.5, -1.5), BULLET_RADIUS * 0.4, Color(1, 1, 1, 0.7))
	for c in _confetti:
		draw_rect(Rect2(c[0] - Vector2(3, 3), Vector2(6, 6)), Color(c[2], clamp(c[3] * 2.0, 0.0, 1.0)))


## Polen flotando: tres motas baratas para dar vida al jardín.
func _draw_pollen() -> void:
	for i in 3:
		var t := _time * 0.22 + float(i) * 2.3
		var p := Vector2(ARENA.position.x + fposmod(t * 150.0 + float(i) * 380.0, ARENA.size.x),
				ARENA.position.y + 150.0 + float(i) * 150.0 + sin(t * 1.8) * 46.0)
		draw_circle(p, 6.0, Color(POLLEN, 0.22))
		draw_circle(p, 3.0, Color(POLLEN, 0.75))


func _draw_tank(t: Tank) -> void:
	var col := t.player.color
	if t.dead_t > 0.0:
		# Fantasma en su esquina con cuenta atrás.
		draw_arc(t.home, TANK_RADIUS + 10.0, -PI / 2.0, -PI / 2.0 + TAU * (1.0 - t.dead_t / RESPAWN_TIME),
				32, Color(col, 0.5), 5.0, true)
		draw_circle(t.home, TANK_RADIUS, Color(col, 0.22))
		return
	var blink := t.invuln > 0.0 and int(t.invuln * 10.0) % 2 == 0
	if blink:
		col = col.linear_interpolate(Color(1, 1, 1, 1), 0.65)
	# Sombra difusa de tanque de juguete.
	DrawKit.soft_shadow(self, t.pos + Vector2(0, 6), TANK_RADIUS * 2.0)
	# Cañón detrás del cuerpo.
	var ret := t.recoil * 6.0
	var muzzle := t.pos + t.aim * (TANK_RADIUS + 14.0 - ret)
	draw_line(t.pos + t.aim * 6.0, muzzle, col.darkened(0.25), 12.0, true)
	draw_circle(muzzle, 6.0, col.darkened(0.18))
	# Cuerpo redondeado.
	draw_circle(t.pos, TANK_RADIUS, col)
	draw_circle(t.pos + Vector2(0, TANK_RADIUS * 0.22), TANK_RADIUS * 0.8, col.darkened(0.08))
	draw_circle(t.pos + Vector2(-TANK_RADIUS * 0.32, -TANK_RADIUS * 0.34), TANK_RADIUS * 0.36, Color(1, 1, 1, 0.45))
	draw_text_centered(str(t.player.index + 1), t.pos, 24, Color(1, 1, 1, 1))


func _draw_target(center: Vector2) -> void:
	var pulse := 1.0 + sin(_time * 5.0) * 0.06
	draw_circle(center + Vector2(0, 4), TARGET_RADIUS * pulse, WiiTheme.SHADOW)
	draw_circle(center, TARGET_RADIUS * pulse, Color("ffd34d"))
	draw_circle(center, TARGET_RADIUS * 0.68 * pulse, Color(1, 1, 1, 1))
	draw_circle(center, TARGET_RADIUS * 0.38 * pulse, Color("e25555"))
	draw_circle(center, TARGET_RADIUS * 0.14 * pulse, Color(1, 1, 1, 1))

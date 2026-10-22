extends MinigameBase
## "Al compás": cada jugador tiene su carril; las notas llegan de derecha a
## izquierda a la línea de golpeo. Círculo = A, rombo = B. Todos los carriles
## reciben la misma secuencia, generada a ~110 BPM (acelera a mitad de partida).

const BPM_START := 110.0
const BPM_LATE := 132.0
const BPM_SWITCH := 22.0       # segundo de partida en el que acelera
const APPROACH := 2.0          # segundos que una nota tarda en llegar a la línea
const HIT_X := 182.0           # línea de golpeo, dentro de ARENA
const NOTE_R := 26.0
const PERFECT_WIN := 0.06      # ±60 ms
const GOOD_WIN := 0.12         # ±120 ms
const ATTEMPT_WIN := 0.28      # margen para emparejar un botón con su nota
const MISS_GRACE := 0.12
const COMBO_MULT := 10
const FEEDBACK_SEC := 0.8
const MAX_FEEDBACK := 24

const KIND_A := 0
const KIND_B := 1


class Note:
	var t := 0.0
	var kind := KIND_A
	var judged: Array[bool] = []


class Track:
	var player: Player
	var combo := 0


var _tracks: Array[Track] = []
var _notes: Array[Note] = []
var _feedback: Array = []      # [carril, texto, edad, color]
var _rings: Array = []         # [carril, edad, color]
var _song_t := 0.0
var _beat_phase := 0.0
var _miss_cd := 0.0


func _configure() -> void:
	title = {"es": "Al compás", "en": "On the beat"}
	instructions = {"es": "Pulsa A en los círculos y B en los rombos al llegar a la línea.",
		"en": "Press A on circles and B on diamonds as they reach the line."}
	controls = [
		[Pad.A, {"es": "Notas círculo", "en": "Circle notes"}],
		[Pad.B, {"es": "Notas rombo", "en": "Diamond notes"}],
	]
	duration = 45.0


func _setup() -> void:
	for p in players:
		var tr := Track.new()
		tr.player = p
		_tracks.append(tr)


func _game_start() -> void:
	_song_t = 0.0
	_beat_phase = 0.0
	_build_song()


func _build_song() -> void:
	_notes.clear()
	var t := 2.0
	while t < duration - 1.5:
		var bpm := BPM_START if t < BPM_SWITCH else BPM_LATE
		var beat := 60.0 / bpm
		var kind := randi() % 2
		_add_note(t, kind)
		var roll := randf()
		if roll < 0.18:
			# Doble: dos notas seguidas medio beat, de distinto tipo.
			_add_note(t + beat * 0.5, 1 - kind)
			t += beat * 1.6
		elif roll < 0.36:
			# Silencio de tres beats.
			t += beat * 3.0
		else:
			t += beat * (1.0 if randf() < 0.65 else 2.0)


func _add_note(at: float, kind: int) -> void:
	var n := Note.new()
	n.t = at
	n.kind = kind
	n.judged.resize(_tracks.size())
	n.judged.fill(false)
	_notes.append(n)


func _game_process(delta: float) -> void:
	_song_t += delta
	_miss_cd = maxf(0.0, _miss_cd - delta)
	_beat_phase += delta * _bpm_at(_song_t) / 60.0

	for i in _tracks.size():
		var tr := _tracks[i]
		if tr.player.just_pressed(Pad.A):
			_attempt(i, KIND_A)
		if tr.player.just_pressed(Pad.B):
			_attempt(i, KIND_B)
	_update_misses()

	for f in _feedback:
		f[2] += delta
	_feedback = _feedback.filter(func(f): return f[2] < FEEDBACK_SEC)
	for r in _rings:
		r[1] += delta
	_rings = _rings.filter(func(r): return r[1] < 0.3)


func _bpm_at(t: float) -> float:
	return BPM_START if t < BPM_SWITCH else BPM_LATE


func _attempt(lane: int, kind: int) -> void:
	var best_i := -1
	var best_dt := ATTEMPT_WIN
	for i in _notes.size():
		var n: Note = _notes[i]
		if n.judged[lane]:
			continue
		var d := absf(n.t - _song_t)
		if d < best_dt:
			best_dt = d
			best_i = i
	if best_i < 0:
		return
	var note: Note = _notes[best_i]
	note.judged[lane] = true
	var tr := _tracks[lane]
	var col := tr.player.color
	if note.kind != kind:
		tr.combo = 0
		Sfx.play("back", 0.8)
		_feedback.append([lane, loc({"es": "Fallo", "en": "Miss"}), 0.0, Color("e25555")])
	elif best_dt <= PERFECT_WIN:
		tr.combo += 1
		var mul := 2 if tr.combo >= COMBO_MULT else 1
		add_score(tr.player, 3 * mul)
		_rings.append([lane, 0.0, Color("ffd34d")])
		var pitch := (1.14 if note.kind == KIND_B else 0.94) * randf_range(0.98, 1.05)
		Sfx.play("star", pitch)
		_feedback.append([lane, loc({"es": "¡Perfecto!", "en": "Perfect!"}), 0.0, Color("ffd34d")])
	elif best_dt <= GOOD_WIN:
		tr.combo += 1
		var mul2 := 2 if tr.combo >= COMBO_MULT else 1
		add_score(tr.player, 1 * mul2)
		_rings.append([lane, 0.0, col])
		var pitch2 := (1.22 if note.kind == KIND_B else 1.0) * randf_range(0.97, 1.05)
		Sfx.play("pop", pitch2)
		_feedback.append([lane, loc({"es": "Bien", "en": "Good"}), 0.0, col.darkened(0.1)])
	else:
		tr.combo = 0
		Sfx.play("back", 0.9)
		_feedback.append([lane, loc({"es": "Fallo", "en": "Miss"}), 0.0, Color("e25555")])
	if _feedback.size() > MAX_FEEDBACK:
		_feedback = _feedback.slice(_feedback.size() - MAX_FEEDBACK)


func _update_misses() -> void:
	for i in _notes.size():
		var n: Note = _notes[i]
		if n.t + MISS_GRACE >= _song_t:
			continue
		for lane in _tracks.size():
			if n.judged[lane]:
				continue
			n.judged[lane] = true
			_tracks[lane].combo = 0
			if _miss_cd <= 0.0:
				_miss_cd = 0.08
				Sfx.play("back", 0.75)
			if randf() < 0.5:
				_feedback.append([lane, loc({"es": "Fallo", "en": "Miss"}), 0.0, Color("e25555")])
				if _feedback.size() > MAX_FEEDBACK:
					_feedback = _feedback.slice(_feedback.size() - MAX_FEEDBACK)


# --- Dibujo ---

func _draw() -> void:
	draw_style_box(WiiTheme.panel_style(30), ARENA)
	var n := maxi(1, _tracks.size())
	var lane_h := (ARENA.size.y - 16.0) / float(n)
	# Pulse del metrónomo: la línea late con cada beat.
	var pulse := 1.0 - fmod(_beat_phase, 1.0)
	var line_w := 7.0 + pulse * 6.0
	# Fondos y separadores de carril.
	for i in _tracks.size():
		var y := ARENA.position.y + 8.0 + lane_h * (float(i) + 0.5)
		var col := _tracks[i].player.color
		draw_rect(Rect2(ARENA.position.x + 6, y - lane_h * 0.5 + 2, ARENA.size.x - 12, lane_h - 4),
				Color(col, 0.05))
		if i > 0:
			draw_line(Vector2(ARENA.position.x + 20, y - lane_h * 0.5),
					Vector2(ARENA.end.x - 20, y - lane_h * 0.5), Color("e4e9ee"), 2.0)
	# Línea de golpeo (pulsa con el beat).
	draw_line(Vector2(HIT_X, ARENA.position.y + 10), Vector2(HIT_X, ARENA.end.y - 10),
			Color(WiiTheme.ACCENT, 0.35 + pulse * 0.45), line_w, true)
	draw_line(Vector2(HIT_X, ARENA.position.y + 10), Vector2(HIT_X, ARENA.end.y - 10),
			Color(1, 1, 1, 0.75), 2.0, true)
	# Notas y elementos de cada carril.
	for i in _tracks.size():
		var y2 := ARENA.position.y + 8.0 + lane_h * (float(i) + 0.5)
		_draw_track(_tracks[i], y2)
		draw_arc(Vector2(HIT_X, y2), NOTE_R + 6.0, 0, TAU, 24,
				Color(_tracks[i].player.color, 0.35), 2.0, true)
		for note in _notes:
			if note.judged[i]:
				continue
			var dt: float = note.t - _song_t
			if dt > APPROACH or dt < -0.35:
				continue
			var x := HIT_X + dt * _px_per_sec()
			_draw_note(Vector2(x, y2), note.kind, _tracks[i].player.color)
	for f in _feedback:
		var lane_i: int = f[0]
		if lane_i >= _tracks.size():
			continue
		var fy: float = ARENA.position.y + 8.0 + lane_h * (float(lane_i) + 0.5) - 34.0 - float(f[2]) * 34.0
		var a := clampf(1.0 - f[2] / FEEDBACK_SEC, 0.0, 1.0)
		draw_text_centered(f[1], Vector2(HIT_X + 190, fy), 22, Color(f[3], a))
	for r in _rings:
		var lane_r: int = r[0]
		if lane_r >= _tracks.size():
			continue
		var ry := ARENA.position.y + 8.0 + lane_h * (float(lane_r) + 0.5)
		draw_arc(Vector2(HIT_X, ry), NOTE_R + 18.0 + r[1] * 80.0, 0, TAU, 24,
				Color(r[2], 0.8 * (1.0 - r[1] / 0.3)), 3.0, true)


func _px_per_sec() -> float:
	return (ARENA.end.x - 20.0 - HIT_X) / APPROACH


func _draw_track(tr: Track, y: float) -> void:
	var p := tr.player
	var col := p.color if p.is_connected_now() else Color("c8ced4")
	var c := Vector2(HIT_X - 72.0, y)
	draw_circle(c + Vector2(0, 4), 24, WiiTheme.SHADOW)
	draw_circle(c, 24, col)
	draw_circle(c + Vector2(-7, -8), 8, Color(1, 1, 1, 0.4))
	draw_text_centered(str(p.index + 1), c, 22, Color.WHITE)
	if tr.combo >= COMBO_MULT:
		draw_text_centered("x2", Vector2(HIT_X - 72.0, y + 38.0), 22, Color("ffd34d"))
	elif tr.combo > 1:
		draw_text_centered(str(tr.combo), Vector2(HIT_X - 72.0, y + 38.0), 18, WiiTheme.TEXT_SOFT)


func _draw_note(c: Vector2, kind: int, col: Color) -> void:
	if kind == KIND_A:
		draw_circle(c + Vector2(0, 4), NOTE_R, WiiTheme.SHADOW)
		draw_circle(c, NOTE_R, col)
		draw_circle(c + Vector2(-NOTE_R * 0.28, -NOTE_R * 0.3), NOTE_R * 0.32,
				Color(1, 1, 1, 0.5))
		draw_arc(c, NOTE_R - 1.0, 0, TAU, 24, Color(1, 1, 1, 0.85), 3.0, true)
	else:
		var pts := PackedVector2Array()
		for i in 4:
			pts.append(c + Vector2.UP.rotated(i * TAU / 4.0) * (NOTE_R + 4.0))
		var shadow := PackedVector2Array()
		for pt in pts:
			shadow.append(pt + Vector2(0, 4))
		draw_colored_polygon(shadow, WiiTheme.SHADOW)
		draw_colored_polygon(pts, WiiTheme.ACCENT_DARK)
		var inner := PackedVector2Array()
		for i in 4:
			inner.append(c + Vector2.UP.rotated(i * TAU / 4.0 + TAU / 8.0) * (NOTE_R * 0.42))
		draw_colored_polygon(inner, Color(1, 1, 1, 0.55))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(1, 1, 1, 0.85), 3.0, true)

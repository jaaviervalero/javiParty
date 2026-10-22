extends Node
## Autoload "Sfx": sonidos cortos sintetizados al arrancar (sin assets externos).
## Sfx.play("move" | "accept" | "back" | "pop" | "star" | "dash" | "wave" | "join" | "leave")

const RATE := 22050
const VOICES := 6

var _streams := {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		_players.append(p)
	# Cada sonido: lista de notas [frecuencia_inicio, frecuencia_fin, duración_s].
	_streams.move = _synth([[1500, 1500, 0.025]], 0.25)
	_streams.accept = _synth([[880, 880, 0.06], [1320, 1320, 0.09]], 0.4)
	_streams.back = _synth([[700, 500, 0.09]], 0.35)
	_streams.pop = _synth([[500, 1400, 0.07]], 0.45)
	_streams.star = _synth([[1046, 1046, 0.05], [1318, 1318, 0.05], [1568, 1568, 0.1]], 0.35)
	_streams.dash = _synth([[300, 900, 0.1]], 0.35)
	_streams.wave = _synth([[220, 60, 0.3]], 0.6, true)
	_streams.join = _synth([[660, 660, 0.07], [990, 990, 0.07], [1320, 1320, 0.12]], 0.4)
	_streams.leave = _synth([[990, 990, 0.07], [660, 660, 0.12]], 0.4)


func play(sound: String, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.play()


## Sintetiza notas con barrido de frecuencia (onda casi senoidal con un toque de
## armónico, que suena a "blip" limpio) y envolvente de ataque/caída rápidos.
func _synth(notes: Array, volume: float, noisy := false) -> AudioStreamSample:
	var data := PoolByteArray()
	var phase := 0.0
	for note in notes:
		var n := int(note[2] * RATE)
		for i in n:
			var t := float(i) / n
			var freq: float = lerp(note[0], note[1], t)
			phase += TAU * freq / RATE
			var s := sin(phase) * 0.8 + sin(phase * 2.0) * 0.15
			if noisy:
				s = s * 0.6 + rand_range(-0.4, 0.4) * (1.0 - t)
			var env := min(1.0, i / (RATE * 0.004)) * pow(1.0 - t, 1.5)
			var v := int(clamp(s * env * volume, -1.0, 1.0) * 32767.0)
			data.append(v & 0xFF)
			data.append((v >> 8) & 0xFF)
	var wav := AudioStreamSample.new()
	wav.format = AudioStreamSample.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

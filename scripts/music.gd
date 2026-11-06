extends Node
## City 2 City Wrestling - a tiny procedural menu beat (no audio assets).
##
## A two-bar gritty boom-bap loop at 90 BPM: pitched-down kick, crunchy snare with a short
## slap-back, swung hats, a sub bass line and a little vinyl crackle, bit-crushed like the
## sound effects in audio.gd. It is synthesized a few hits per frame (no hitch on the
## web), then loops quietly.
##
## Usage:
##   var music: Node = preload("res://scripts/music.gd").new()
##   add_child(music)          # starts synthesizing in the background
##   music.start()             # plays as soon as the loop is ready (call after a user gesture)
##   music.fade_out(0.5)

const MIX_RATE: int = 22050
const BPM: float = 90.0
const STEPS: int = 32                 # two bars of 16ths
const SWING: float = 0.03             # seconds the off-beat 8ths are pushed late
const VOLUME_DB: float = -13.0
const SILENT_DB: float = -60.0

static var _cached: AudioStreamWAV = null

var _buf: PackedFloat32Array = PackedFloat32Array()
var _jobs: Array = []                 # [kind, start_seconds, velocity, extra]
var _encode_at: int = -1              # >= 0 while converting to 16-bit
var _data: PackedByteArray = PackedByteArray()
var _gain: float = 1.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _player: AudioStreamPlayer = null
var _want_play: bool = false
var _target_db: float = VOLUME_DB
var _db: float = SILENT_DB
var _fade_rate: float = 20.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.name = "Beat"
	_player.volume_db = SILENT_DB
	add_child(_player)
	if _cached != null:
		_player.stream = _cached
		return
	_rng.seed = 9002
	var step_len: float = 60.0 / BPM / 4.0
	var n: int = int(step_len * STEPS * MIX_RATE)
	_buf.resize(n)
	_buf.fill(0.0)
	var kicks: Array[int] = [0, 10, 16, 23, 26]
	var snares: Array[int] = [4, 12, 20, 28]
	# Sub bass notes: [step, hz, length in steps]
	var bass: Array = [[0, 55.0, 6], [10, 55.0, 4], [16, 43.65, 6], [23, 49.0, 3], [26, 41.2, 6]]
	for s in kicks:
		_jobs.append(["kick", s * step_len, 1.0, 0.0])
	for s in snares:
		_jobs.append(["snare", s * step_len, 1.0 if s % 8 == 4 else 0.9, 0.0])
	for b: Array in bass:
		_jobs.append(["bass", float(b[0]) * step_len, 0.8, float(b[1]) + float(b[2]) * 1000.0])
	for s in range(0, STEPS, 2):
		var t: float = s * step_len
		if (s / 2) % 2 == 1:
			t += SWING
		if s == 30 or s == 14:
			_jobs.append(["ohat", t, 0.55, 0.0])
		else:
			_jobs.append(["hat", t, 0.75 if s % 4 == 0 else 0.45, 0.0])
	_jobs.append(["crackle", 0.0, 1.0, 0.0])


func start() -> void:
	_want_play = true
	_target_db = VOLUME_DB
	_fade_rate = 6.0


func fade_out(seconds: float = 0.6) -> void:
	_target_db = SILENT_DB
	_fade_rate = 60.0 / maxf(seconds, 0.05)


func _process(delta: float) -> void:
	if _player.stream == null:
		_synth_step()
		return
	if _want_play and not _player.playing and _target_db > SILENT_DB:
		_player.play()
	if _db < _target_db:
		_db = minf(_target_db, _db + _fade_rate * 6.0 * delta)
	else:
		_db = maxf(_target_db, _db - _fade_rate * delta)
	_player.volume_db = _db
	if _player.playing and _target_db <= SILENT_DB and _db <= SILENT_DB + 1.0:
		_player.stop()


# ------------------------------------------------------------------ synthesis (incremental)

func _synth_step() -> void:
	if not _jobs.is_empty():
		for i in 2:
			if _jobs.is_empty():
				break
			var j: Array = _jobs.pop_front()
			_render(j[0], j[1], j[2], j[3])
		if _jobs.is_empty():
			var peak: float = 0.0001
			for i in _buf.size():
				peak = maxf(peak, absf(_buf[i]))
			_gain = 1.4 / peak
			_data.resize(_buf.size() * 2)
			_encode_at = 0
		return
	if _encode_at >= 0:
		var end: int = mini(_encode_at + 20000, _buf.size())
		for i in range(_encode_at, end):
			var v: float = tanh(_buf[i] * _gain) * 0.9
			var s: int = int(roundf(v * 2047.0)) * 16  # 12-bit grit, like audio.gd
			_data.encode_s16(i * 2, clampi(s, -32768, 32767))
		_encode_at = end
		if _encode_at >= _buf.size():
			var wav: AudioStreamWAV = AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = MIX_RATE
			wav.stereo = false
			wav.data = _data
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = _buf.size()
			_cached = wav
			_player.stream = wav
			_encode_at = -1
			_buf = PackedFloat32Array()


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _add(i: int, v: float) -> void:
	# Wraps around so tails at the end of the loop spill into its start (seamless loop).
	var n: int = _buf.size()
	var k: int = i % n
	_buf[k] = _buf[k] + v


func _render(kind: String, t0: float, vel: float, extra: float) -> void:
	var i0: int = int(t0 * MIX_RATE)
	match kind:
		"kick":
			var n: int = int(0.42 * MIX_RATE)
			var ph: float = 0.0
			for i in n:
				var t: float = float(i) / MIX_RATE
				var f: float = 45.0 + 95.0 * exp(-t * 28.0)
				ph += TAU * f / MIX_RATE
				var v: float = sin(ph) * exp(-t * 7.5) * 1.1
				if i < 90:
					v += _noise() * 0.5 * (1.0 - float(i) / 90.0)
				_add(i0 + i, v * vel)
		"snare":
			var n: int = int(0.3 * MIX_RATE)
			var lp: float = 0.0
			var ph: float = 0.0
			for i in n:
				var t: float = float(i) / MIX_RATE
				var x: float = _noise()
				lp += 0.35 * (x - lp)
				var hp: float = x - lp * 0.7
				ph += TAU * 185.0 / MIX_RATE
				var v: float = hp * exp(-t * 16.0) * 0.55 + sin(ph) * exp(-t * 30.0) * 0.45
				_add(i0 + i, v * vel)
				_add(i0 + i + int(0.07 * MIX_RATE), v * vel * 0.22)  # slap-back off the fence
		"hat", "ohat":
			var dur: float = 0.06 if kind == "hat" else 0.28
			var dec: float = 70.0 if kind == "hat" else 11.0
			var n: int = int(dur * MIX_RATE)
			var lp: float = 0.0
			for i in n:
				var t: float = float(i) / MIX_RATE
				var x: float = _noise()
				lp += 0.55 * (x - lp)
				_add(i0 + i, (x - lp) * exp(-t * dec) * 0.28 * vel)
		"bass":
			var hz: float = fmod(extra, 1000.0)
			var steps: float = floorf(extra / 1000.0)
			var dur: float = steps * 60.0 / BPM / 4.0
			var n: int = int(dur * MIX_RATE)
			var ph: float = 0.0
			for i in n:
				var t: float = float(i) / MIX_RATE
				ph += TAU * hz / MIX_RATE
				var env: float = minf(1.0, t * 200.0) * exp(-t * 2.2) * minf(1.0, (dur - t) * 30.0)
				_add(i0 + i, (sin(ph) + 0.25 * sin(ph * 2.0)) * env * 0.55 * vel)
		"crackle":
			var n: int = _buf.size()
			var i: int = 0
			while i < n:
				i += 200 + _rng.randi() % 1400
				if i >= n:
					break
				var amp: float = _rng.randf_range(0.02, 0.07)
				for k in 12:
					_add(i + k, _noise() * amp * (1.0 - k / 12.0))

extends Node
## City 2 City Wrestling - procedural audio (no audio assets; everything is synthesized here).
##
## Usage (from main.gd):
##   var audio: Node = preload("res://scripts/audio.gd").new()
##   add_child(audio)                     # clips are synthesized in _ready
##   audio.play("punch")                  # one-shot, random pitch 1 +/- 0.08
##   audio.play("big_thud", 3.0, 0.03)    # louder, less pitch variation
##   audio.ring_bell(3)                   # ding-ding-ding, 0.35 s apart
##   audio.start_crowd()                  # looping crowd murmur bed
##   audio.set_crowd_intensity(0.7)       # 0..1, call as often as you like (smoothed)
##   audio.stop_crowd()                   # fades out, then stops
##
## Sound names: "punch", "kick", "thud", "big_thud", "rope", "bell", "count",
##              "whoosh", "pop", "ooh", "boo",
##              backyard/hardcore: "chair", "metal", "wood", "crack", "whoa",
##              "cheer_small", "climb", "dive_whoosh", "thud_concrete" (slam on the patio)
##              (plus "crowd_loop", used internally: a small backyard crowd + crickets).
##
## All clips are 16-bit mono 22050 Hz AudioStreamWAV, lightly bit-crushed for a
## late-90s cartridge feel. Noise uses a fixed-seed RandomNumberGenerator so the
## sounds are identical every launch.

const MIX_RATE: int = 22050
const POOL_SIZE: int = 10
const CROWD_MIN_DB: float = -22.0
const CROWD_MAX_DB: float = -6.0
const CROWD_SILENT_DB: float = -60.0
const BELL_GAP: float = 0.35

var clips: Dictionary = {}
# Synthesized clips survive scene reloads (REMATCH), so the ~340k-sample synthesis
# runs once per launch instead of on every reload.
static var _cache: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()      # deterministic synthesis noise
var _play_rng: RandomNumberGenerator = RandomNumberGenerator.new() # runtime pitch variation
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _crowd_player: AudioStreamPlayer = null
var _crowd_intensity: float = 0.3
var _crowd_db: float = CROWD_SILENT_DB
var _crowd_on: bool = false
var _warned: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 19990415
	_play_rng.randomize()
	_build_clips()
	for i in range(POOL_SIZE):
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.name = "Sfx%d" % i
		add_child(p)
		_pool.append(p)
	_crowd_player = AudioStreamPlayer.new()
	_crowd_player.name = "Crowd"
	_crowd_player.stream = clips["crowd_loop"]
	_crowd_player.volume_db = CROWD_SILENT_DB
	add_child(_crowd_player)


func _process(delta: float) -> void:
	if _crowd_player == null:
		return
	var target: float = CROWD_SILENT_DB
	if _crowd_on:
		target = lerpf(CROWD_MIN_DB, CROWD_MAX_DB, _crowd_intensity)
	var k: float = clampf(delta * 3.0, 0.0, 1.0)
	if _crowd_on and _crowd_db < CROWD_MIN_DB:
		k = clampf(delta * 6.0, 0.0, 1.0) # quick fade-in from silence
	_crowd_db = lerpf(_crowd_db, target, k)
	_crowd_player.volume_db = _crowd_db
	if not _crowd_on and _crowd_player.playing and _crowd_db < CROWD_SILENT_DB + 4.0:
		_crowd_player.stop()


# ------------------------------------------------------------------ public API

func play(sound: String, volume_db: float = 0.0, pitch_variation: float = 0.08) -> void:
	if not clips.has(sound) or _pool.is_empty():
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("audio.gd: unknown sound '%s'" % sound)
		return
	var p: AudioStreamPlayer = _pool[_next_player]
	_next_player = (_next_player + 1) % _pool.size()
	p.stop()
	p.stream = clips[sound]
	p.volume_db = volume_db
	var v: float = absf(pitch_variation)
	p.pitch_scale = maxf(0.05, 1.0 + _play_rng.randf_range(-v, v))
	p.play()


func ring_bell(times: int = 3) -> void:
	for i in range(maxi(times, 1)):
		if not is_inside_tree():
			return
		play("bell", 0.0, 0.0)
		if i < times - 1:
			await get_tree().create_timer(BELL_GAP, true).timeout


func set_crowd_intensity(v: float) -> void:
	_crowd_intensity = clampf(v, 0.0, 1.0)


func start_crowd() -> void:
	_crowd_on = true
	if _crowd_player != null and not _crowd_player.playing:
		_crowd_db = CROWD_SILENT_DB
		_crowd_player.volume_db = _crowd_db
		_crowd_player.play()


func stop_crowd() -> void:
	_crowd_on = false # _process fades it out and stops the player


# ------------------------------------------------------------------ synthesis

func _build_clips() -> void:
	if not _cache.is_empty():
		clips = _cache
		return
	clips["punch"] = _to_wav(_synth_hit(0.06, 180.0, 120.0, 0.55, 2600.0), false)
	clips["kick"] = _to_wav(_synth_hit(0.09, 130.0, 80.0, 0.7, 1800.0), false)
	clips["thud"] = _to_wav(_synth_slam(0.35, 70.0, 48.0, 0.5), false)
	clips["big_thud"] = _to_wav(_synth_slam(0.6, 62.0, 36.0, 0.85), false)
	clips["rope"] = _to_wav(_synth_rope(0.25), false)
	clips["bell"] = _to_wav(_synth_bell(1.3), false)
	clips["count"] = _to_wav(_synth_count(0.08), false)
	clips["whoosh"] = _to_wav(_synth_whoosh(0.2), false)
	clips["pop"] = _to_wav(_synth_pop(1.5), false)
	clips["ooh"] = _to_wav(_synth_ooh(1.0, 210.0, 0.85), false)
	clips["boo"] = _to_wav(_synth_ooh(1.1, 150.0, 0.7), false)
	clips["chair"] = _to_wav(_synth_metal(0.5, PackedFloat32Array([412.0, 967.0, 1433.0, 1871.0, 2389.0, 2953.0]),
			PackedFloat32Array([7.0, 8.5, 10.0, 12.0, 14.0, 17.0]), 0.0, 3200.0), false)
	clips["metal"] = _to_wav(_synth_metal(0.6, PackedFloat32Array([173.0, 268.0, 391.0, 547.0, 811.0, 1190.0]),
			PackedFloat32Array([6.0, 7.0, 8.0, 10.0, 13.0, 16.0]), 1.0, 1500.0), false)
	clips["wood"] = _to_wav(_synth_wood(0.15), false)
	clips["crack"] = _to_wav(_synth_crack(0.7), false)
	clips["whoa"] = _to_wav(_synth_whoa(1.1), false)
	clips["cheer_small"] = _to_wav(_synth_cheer_small(1.4), false)
	clips["climb"] = _to_wav(_synth_creak(0.45), false)
	clips["dive_whoosh"] = _to_wav(_synth_dive_whoosh(0.7), false)
	clips["crowd_loop"] = _to_wav(_synth_crowd_loop(3.0), true)
	clips["thud_concrete"] = _to_wav(_synth_concrete_slam(0.45), false)
	_cache = clips


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


func _coef(cutoff_hz: float) -> float:
	# One-pole low-pass coefficient: y += a * (x - y)
	return 1.0 - exp(-TAU * cutoff_hz / float(MIX_RATE))


func _n(seconds: float) -> int:
	return maxi(1, int(seconds * float(MIX_RATE)))


## Slap / thwack: high-passed noise crack + pitched-down body thump.
func _synth_hit(dur: float, f0: float, f1: float, body_amt: float, crack_hz: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	var lp2: float = 0.0
	var a_lp: float = _coef(crack_hz * 2.2)
	var a_hp: float = _coef(crack_hz * 0.35)
	var phase: float = 0.0
	var sr: float = float(MIX_RATE)
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var nz: float = _noise()
		lp += a_lp * (nz - lp)
		lp2 += a_hp * (lp - lp2)
		var crack: float = (lp - lp2) * exp(-t * 70.0)
		var f: float = lerpf(f0, f1, x)
		phase += TAU * f / sr
		var body: float = sin(phase) * exp(-t * 28.0) * body_amt
		var atk: float = minf(1.0, float(i) / 22.0)
		buf[i] = (crack * 1.4 + body) * atk * (1.0 - x * x)
	return buf


## Mat slam: falling sub sine + low-passed noise + springy ring rattle.
func _synth_slam(dur: float, f0: float, f1: float, rattle_amt: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var phase: float = 0.0
	var lp: float = 0.0
	var a_lp: float = _coef(420.0)
	var rat_lp: float = 0.0
	var a_rat: float = _coef(5000.0)
	var partials: PackedFloat32Array = PackedFloat32Array([311.0, 397.0, 463.0, 541.0, 598.0])
	var pdec: PackedFloat32Array = PackedFloat32Array([9.0, 11.0, 13.0, 15.0, 18.0])
	var pph: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var heavy: float = clampf((dur - 0.3) * 2.0, 0.0, 1.0)
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var f: float = f1 + (f0 - f1) * exp(-t * 14.0)
		phase += TAU * f / sr
		var body: float = sin(phase) * exp(-t * (9.0 - heavy * 3.5))
		body += sin(phase * 2.0) * 0.25 * exp(-t * 20.0)
		var nz: float = _noise()
		lp += a_lp * (nz - lp)
		var thump: float = lp * 2.2 * exp(-t * (22.0 - heavy * 8.0))
		var rattle: float = 0.0
		for k in range(partials.size()):
			# slight downward "spring" wobble on each partial
			var pf: float = partials[k] * (1.0 + 0.03 * sin(t * 37.0 + float(k)))
			pph[k] = pph[k] + TAU * pf / sr
			rattle += sin(pph[k]) * exp(-t * pdec[k])
		rat_lp += a_rat * (nz - rat_lp)
		rattle = rattle * 0.12 * rattle_amt + rat_lp * 0.18 * rattle_amt * exp(-t * 25.0)
		var atk: float = minf(1.0, float(i) / 40.0)
		buf[i] = (body * 1.1 + thump + rattle) * atk * (1.0 - x * x * x)
	return buf


## Concrete slam: the mat slam's body with no springy rattle, plus a hard bright slap
## (high-passed noise) and a short gritty scrape tail: harsher and louder than "thud".
func _synth_concrete_slam(dur: float) -> PackedFloat32Array:
	var buf: PackedFloat32Array = _synth_slam(dur, 95.0, 52.0, 0.0)
	var slap: PackedFloat32Array = _synth_hit(minf(dur, 0.12), 240.0, 140.0, 0.35, 3800.0)
	var n: int = buf.size()
	var sr: float = float(MIX_RATE)
	var lp: float = 0.0
	var a_lp: float = _coef(2500.0)
	for i in range(n):
		var t: float = float(i) / sr
		var s: float = buf[i] * 1.15
		if i < slap.size():
			s += slap[i] * 1.6
		var nz: float = _noise()
		lp += a_lp * (nz - lp)
		s += (nz - lp) * 0.22 * exp(-t * 18.0)
		buf[i] = clampf(s * 1.1, -1.0, 1.0)
	return buf


## Rope bounce: low Karplus-Strong pluck plus a pitch-bending "boing" sine.
func _synth_rope(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var period: int = int(sr / 98.0)
	var ks: PackedFloat32Array = PackedFloat32Array()
	ks.resize(period)
	for j in range(period):
		ks[j] = _noise()
	var idx: int = 0
	var prev: float = 0.0
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var cur: float = ks[idx]
		var nxt: float = ks[(idx + 1) % period]
		var avg: float = (cur + nxt) * 0.5 * 0.985
		ks[idx] = avg
		idx = (idx + 1) % period
		prev += 0.5 * (cur - prev)
		var f: float = 150.0 * exp(-t * 6.0) + 82.0
		phase += TAU * f / sr
		var boing: float = sin(phase + 0.6 * sin(phase * 0.5)) * exp(-t * 11.0)
		var atk: float = minf(1.0, float(i) / 30.0)
		buf[i] = (prev * 0.9 + boing * 0.75) * atk * (1.0 - x * x)
	return buf


## Ring bell ding: 880 / 1320 / 2310 Hz partials with exponential decay + strike.
func _synth_bell(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var w1: float = TAU * 880.0 / sr
	var w2: float = TAU * 1320.0 / sr
	var w3: float = TAU * 2310.0 / sr
	var w4: float = TAU * 1763.0 / sr
	var hp_lp: float = 0.0
	var a_hp: float = _coef(2000.0)
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var fi: float = float(i)
		var s: float = sin(w1 * fi) * exp(-t * 3.2)
		s += sin(w2 * fi) * 0.6 * exp(-t * 4.0)
		s += sin(w3 * fi) * 0.4 * exp(-t * 6.5)
		s += sin(w4 * fi) * 0.15 * exp(-t * 9.0)
		var nz: float = _noise()
		hp_lp += a_hp * (nz - hp_lp)
		var strike: float = (nz - hp_lp) * exp(-t * 160.0) * 0.8
		var atk: float = minf(1.0, fi / 12.0)
		buf[i] = (s * 0.6 + strike) * atk * (1.0 - x * x)
	return buf


## Referee mat slap: crisp, short, a little low knock.
func _synth_count(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var lp: float = 0.0
	var lp2: float = 0.0
	var a1: float = _coef(6000.0)
	var a2: float = _coef(900.0)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var nz: float = _noise()
		lp += a1 * (nz - lp)
		lp2 += a2 * (lp - lp2)
		var slap: float = (lp - lp2) * exp(-t * 90.0) * 1.6
		phase += TAU * (140.0 - 50.0 * x) / sr
		var knock: float = sin(phase) * exp(-t * 45.0) * 0.6
		var atk: float = minf(1.0, float(i) / 8.0)
		buf[i] = (slap + knock) * atk * (1.0 - x)
	return buf


## Whoosh: band-passed noise whose centre sweeps up then down.
func _synth_whoosh(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	var lp2: float = 0.0
	for i in range(n):
		var x: float = float(i) / float(n)
		var sweep: float = sin(x * PI)
		var fc: float = 400.0 + 2400.0 * sweep
		var a1: float = _coef(fc * 1.6)
		var a2: float = _coef(fc * 0.6)
		var nz: float = _noise()
		lp += a1 * (nz - lp)
		lp2 += a2 * (lp - lp2)
		var env: float = pow(sweep, 1.5)
		buf[i] = (lp - lp2) * env * 2.0
	return buf


## Crowd pop: noise swell band-passed ~500-2500 Hz, with jittery "many voices"
## amplitude flutter and a few shouting voices on top.
func _synth_pop(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var lp: float = 0.0
	var lp2: float = 0.0
	var a1: float = _coef(2500.0)
	var a2: float = _coef(500.0)
	var flut: float = 0.5
	var flut_t: float = 0.5
	var a_flut: float = _coef(14.0)
	var vf: PackedFloat32Array = PackedFloat32Array([330.0, 415.0, 470.0, 560.0])
	var vp: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var vlp: float = 0.0
	var a_v: float = _coef(1400.0)
	var attack: float = 0.15
	for i in range(n):
		var t: float = float(i) / sr
		if i % 600 == 0:
			flut_t = _rng.randf_range(0.55, 1.0)
		flut += a_flut * (flut_t - flut)
		var nz: float = _noise()
		lp += a1 * (nz - lp)
		lp2 += a2 * (lp - lp2)
		var bed: float = (lp - lp2) * 2.2 * flut
		var voices: float = 0.0
		for k in range(vf.size()):
			var f: float = vf[k] * (1.0 + 0.12 * minf(t * 3.0, 1.0)) * (1.0 + 0.02 * sin(t * (5.0 + float(k)) * TAU))
			vp[k] = vp[k] + f / sr
			voices += (fposmod(vp[k], 1.0) * 2.0 - 1.0) # sawtooth
		vlp += a_v * (voices - vlp)
		var env: float = 0.0
		if t < attack:
			env = t / attack
		else:
			env = exp(-(t - attack) * 2.2)
		buf[i] = (bed + vlp * 0.08) * env
	return buf


## "Oooh" / "boo": several detuned buzzy voices through an "oo" low-pass vowel,
## plus a low noise bed, with a slight pitch sag at the end.
func _synth_ooh(dur: float, base_hz: float, sag: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var det: PackedFloat32Array = PackedFloat32Array([0.94, 0.98, 1.0, 1.03, 1.07, 1.12])
	var ph: PackedFloat32Array = PackedFloat32Array([0.0, 0.17, 0.41, 0.66, 0.23, 0.89])
	var v1: float = 0.0
	var v2: float = 0.0
	var a_v: float = _coef(520.0)
	var nlp: float = 0.0
	var nlp2: float = 0.0
	var a_n1: float = _coef(800.0)
	var a_n2: float = _coef(220.0)
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var bend: float = lerpf(1.0, sag, x * x)
		var voices: float = 0.0
		for k in range(det.size()):
			var f: float = base_hz * det[k] * bend * (1.0 + 0.015 * sin(t * TAU * (4.0 + float(k) * 0.7)))
			ph[k] = ph[k] + f / sr
			voices += fposmod(ph[k], 1.0) * 2.0 - 1.0
		v1 += a_v * (voices - v1)
		v2 += a_v * (v1 - v2) # two poles for a rounder "oo"
		var nz: float = _noise()
		nlp += a_n1 * (nz - nlp)
		nlp2 += a_n2 * (nlp - nlp2)
		var bed: float = (nlp - nlp2) * 1.2
		var env: float = minf(1.0, t / 0.18) * (1.0 - pow(x, 2.5))
		buf[i] = (v2 * 0.35 + bed) * env
	return buf


## Backyard crowd bed: a dozen friends standing close (a thin, near chatter band with
## quick random swells, no stadium rumble) plus crickets (4.5 kHz sine chirps).
## Generated long and crossfaded end-into-start so it loops without a click.
func _synth_crowd_loop(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var fade: int = _n(0.25)
	var total: int = n + fade
	var sr: float = float(MIX_RATE)
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(total)
	var l1: float = 0.0
	var h1: float = 0.0
	var l2: float = 0.0
	var h2: float = 0.0
	var a_l1: float = _coef(1700.0)
	var a_h1: float = _coef(450.0)
	var a_l2: float = _coef(3000.0)
	var a_h2: float = _coef(1500.0)
	var m1: float = 0.5
	var m1_t: float = 0.5
	var m2: float = 0.4
	var m2_t: float = 0.4
	var a_m: float = _coef(4.0)
	var a_m2: float = _coef(9.0)
	# Crickets: a chirp is 3 short 4.5 kHz pulses (40 Hz gate); one every ~0.55-1.1 s.
	var w_cr: float = TAU * 4500.0 / sr
	var w_gate: float = TAU * 40.0 / sr
	var chirp_at: int = _n(0.3)
	var chirp_len: int = _n(0.075)
	var chirp_gain: float = 0.08
	for i in range(total):
		if i % 2900 == 0:
			m1_t = _rng.randf_range(0.25, 1.0) # fewer people: deeper, quicker swells
		if i % 1300 == 0:
			m2_t = _rng.randf_range(0.0, 1.0)
		m1 += a_m * (m1_t - m1)
		m2 += a_m2 * (m2_t - m2)
		var nz: float = _noise()
		l1 += a_l1 * (nz - l1)
		h1 += a_h1 * (l1 - h1)
		var nz2: float = _noise()
		l2 += a_l2 * (nz2 - l2)
		h2 += a_h2 * (l2 - h2)
		var cr: float = 0.0
		var ci: int = i - chirp_at
		if ci >= 0 and ci < chirp_len:
			var gate: float = maxf(0.0, sin(w_gate * float(ci)))
			cr = sin(w_cr * float(i)) * gate * gate * chirp_gain
		elif ci >= chirp_len:
			chirp_at = i + _n(_rng.randf_range(0.55, 1.1))
			chirp_gain = _rng.randf_range(0.05, 0.1)
		raw[i] = (l1 - h1) * m1 * 1.2 + (l2 - h2) * m2 * 0.5 + cr
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		buf[i] = raw[i]
	for i in range(fade):
		var g: float = float(i) / float(fade)
		# equal-power crossfade: tail (past loop end) fades out over the head
		buf[i] = raw[i] * sin(g * PI * 0.5) + raw[n + i] * cos(g * PI * 0.5)
	return buf


## Metal clang (folding chair / trash can): inharmonic partials with a fast attack
## and a short ring, a high-passed noise strike, and an optional low hollow "boom".
func _synth_metal(dur: float, partials: PackedFloat32Array, decays: PackedFloat32Array, boom: float, strike_hz: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var np: int = partials.size()
	var ws: PackedFloat32Array = PackedFloat32Array()
	var pph: PackedFloat32Array = PackedFloat32Array()
	ws.resize(np)
	pph.resize(np)
	for k in range(np):
		ws[k] = TAU * partials[k] / sr
		pph[k] = 0.0
	var hp_lp: float = 0.0
	var a_hp: float = _coef(strike_hz)
	var b_lp: float = 0.0
	var a_b: float = _coef(300.0)
	var bph: float = 0.0
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		# slight wobble = the panel flexing after the hit
		var wob: float = 1.0 + 0.004 * sin(t * TAU * 9.0)
		var ring: float = 0.0
		for k in range(np):
			pph[k] = pph[k] + ws[k] * wob
			ring += sin(pph[k]) * exp(-t * decays[k]) / (1.0 + float(k) * 0.25)
		var nz: float = _noise()
		hp_lp += a_hp * (nz - hp_lp)
		var strike: float = (nz - hp_lp) * exp(-t * 90.0) * 1.3
		var low: float = 0.0
		if boom > 0.0:
			bph += TAU * (70.0 + 50.0 * exp(-t * 20.0)) / sr
			b_lp += a_b * (nz - b_lp)
			low = (sin(bph) * exp(-t * 9.0) + b_lp * 2.0 * exp(-t * 25.0)) * boom
		var atk: float = minf(1.0, float(i) / 10.0)
		buf[i] = (ring * 0.32 + strike + low) * atk * (1.0 - x * x)
	return buf


## 2x4 thwack: dry hollow knock (two damped wood modes) + a band-passed click.
func _synth_wood(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var lp: float = 0.0
	var lp2: float = 0.0
	var a1: float = _coef(3500.0)
	var a2: float = _coef(900.0)
	var p1: float = 0.0
	var p2: float = 0.0
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var nz: float = _noise()
		lp += a1 * (nz - lp)
		lp2 += a2 * (lp - lp2)
		var click: float = (lp - lp2) * exp(-t * 110.0) * 1.8
		p1 += TAU * (240.0 - 40.0 * x) / sr
		p2 += TAU * 690.0 / sr
		var body: float = sin(p1) * exp(-t * 38.0) + sin(p2) * 0.5 * exp(-t * 60.0)
		var atk: float = minf(1.0, float(i) / 6.0)
		buf[i] = (click + body * 0.8) * atk * (1.0 - x)
	return buf


## Table break: big snap, a run of splintering noise bursts and crackle, a low thump.
func _synth_crack(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var hp_lp: float = 0.0
	var a_hp: float = _coef(1200.0)
	var bp_lp: float = 0.0
	var bp_lp2: float = 0.0
	var a_b1: float = _coef(4200.0)
	var a_b2: float = _coef(700.0)
	var t_lp: float = 0.0
	var a_t: float = _coef(260.0)
	var phase: float = 0.0
	var burst_env: float = 1.0
	var crackle: float = 0.0
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var nz: float = _noise()
		# initial snap
		hp_lp += a_hp * (nz - hp_lp)
		var snap: float = (nz - hp_lp) * exp(-t * 55.0) * 1.6
		# splinter bursts: random re-triggers, denser early on
		if _rng.randf() < 0.0025 * exp(-t * 5.0):
			burst_env = _rng.randf_range(0.5, 1.0)
		burst_env *= 0.9975
		bp_lp += a_b1 * (nz - bp_lp)
		bp_lp2 += a_b2 * (bp_lp - bp_lp2)
		var bursts: float = (bp_lp - bp_lp2) * burst_env * 1.5
		# crackle: sparse ticks that ring very briefly
		if _rng.randf() < 0.02 * exp(-t * 4.0):
			crackle = _rng.randf_range(-1.0, 1.0)
		crackle *= 0.8
		# low thump (wrestler + table hitting the ground)
		t_lp += a_t * (nz - t_lp)
		phase += TAU * (48.0 + 60.0 * exp(-t * 18.0)) / sr
		var thump: float = sin(phase) * exp(-t * 8.0) * 0.9 + t_lp * 2.0 * exp(-t * 14.0)
		var atk: float = minf(1.0, float(i) / 12.0)
		buf[i] = (snap + bursts + crackle * 0.6 + thump) * atk * (1.0 - x * x)
	return buf


## "WHOOOA!" from a handful of friends: buzzy voices whose pitch and vowel formant
## rise ("whoo" -> "OA"), over band-passed breathy noise, swelling then dropping off.
func _synth_whoa(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var base: PackedFloat32Array = PackedFloat32Array([180.0, 205.0, 240.0, 290.0, 330.0])
	var ph: PackedFloat32Array = PackedFloat32Array([0.0, 0.31, 0.57, 0.12, 0.83])
	var vl: float = 0.0
	var vh: float = 0.0
	var nl: float = 0.0
	var nh: float = 0.0
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		var rise: float = smoothstep(0.0, 0.55, x)
		var voices: float = 0.0
		for k in range(base.size()):
			var f: float = base[k] * (0.85 + 0.45 * rise) * (1.0 + 0.02 * sin(t * TAU * (5.0 + float(k))))
			ph[k] = ph[k] + f / sr
			voices += fposmod(ph[k], 1.0) * 2.0 - 1.0
		# vowel: formant centre glides 350 Hz ("oo") -> 900 Hz ("ah")
		var fc: float = 350.0 + 550.0 * rise
		vl += _coef(fc * 1.5) * (voices - vl)
		vh += _coef(fc * 0.5) * (vl - vh)
		var nz: float = _noise()
		nl += _coef(fc * 2.5) * (nz - nl)
		nh += _coef(fc * 0.7) * (nl - nh)
		var env: float = smoothstep(0.0, 0.35, x) * (1.0 - smoothstep(0.6, 1.0, x))
		buf[i] = ((vl - vh) * 0.35 + (nl - nh) * 1.2) * env
	return buf


## Small backyard cheer (~a dozen people, not a stadium): a few whooping voices that
## re-pitch and glide up on each whoop, scattered hand claps and a thin chatter band.
func _synth_cheer_small(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var nv: int = 5
	var vf: PackedFloat32Array = PackedFloat32Array()
	var vp: PackedFloat32Array = PackedFloat32Array()
	var vg: PackedFloat32Array = PackedFloat32Array()
	var vt: PackedFloat32Array = PackedFloat32Array() # start time of this voice's current whoop
	vf.resize(nv)
	vp.resize(nv)
	vg.resize(nv)
	vt.resize(nv)
	for k in range(nv):
		vf[k] = _rng.randf_range(260.0, 620.0)
		vp[k] = _rng.randf()
		vg[k] = _rng.randf_range(0.4, 1.0)
		vt[k] = _rng.randf_range(0.0, 0.25)
	var vl: float = 0.0
	var vh: float = 0.0
	var a_vl: float = _coef(2200.0)
	var a_vh: float = _coef(500.0)
	var bl: float = 0.0
	var bh: float = 0.0
	var a_bl: float = _coef(2600.0)
	var a_bh: float = _coef(700.0)
	var clap: float = 0.0
	var cl_lp: float = 0.0
	var a_cl: float = _coef(1500.0)
	for i in range(n):
		var t: float = float(i) / sr
		var voices: float = 0.0
		for k in range(nv):
			var age: float = t - vt[k]
			if age > 0.45:
				# this person's next whoop
				vt[k] = t + _rng.randf_range(0.0, 0.2)
				vf[k] = _rng.randf_range(260.0, 620.0)
				vg[k] = _rng.randf_range(0.4, 1.0)
				age = t - vt[k]
			if age > 0.0:
				var f: float = vf[k] * (1.0 + 0.5 * minf(age * 4.0, 1.0)) # "whoo-OO" upward glide
				vp[k] = vp[k] + f / sr
				var ve: float = minf(age * 20.0, 1.0) * exp(-age * 5.0)
				voices += (fposmod(vp[k], 1.0) * 2.0 - 1.0) * ve * vg[k]
		vl += a_vl * (voices - vl)
		vh += a_vh * (vl - vh)
		var nz: float = _noise()
		bl += a_bl * (nz - bl)
		bh += a_bh * (bl - bh)
		if _rng.randf() < 0.0012:
			clap = _rng.randf_range(0.6, 1.0)
		clap *= 0.992
		cl_lp += a_cl * (nz - cl_lp)
		var claps: float = (nz - cl_lp) * clap
		var env: float = minf(t / 0.08, 1.0) * exp(-maxf(t - 0.3, 0.0) * 2.2)
		buf[i] = ((vl - vh) * 0.3 + (bl - bh) * 0.6 + claps * 0.7) * env
	return buf


## Creak (rope / homemade turnbuckle under weight): stick-slip pulse train with a
## wandering, jittery period through a woody band-pass.
func _synth_creak(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var sr: float = float(MIX_RATE)
	var ph: float = 0.0
	var bl: float = 0.0
	var bh: float = 0.0
	var a_bl: float = _coef(1800.0)
	var a_bh: float = _coef(600.0)
	for i in range(n):
		var t: float = float(i) / sr
		var x: float = float(i) / float(n)
		# pitch wanders 70 -> 160 Hz and back, with jitter (stick-slip)
		var f: float = 70.0 + 90.0 * sin(x * PI) + _rng.randf_range(-15.0, 15.0)
		ph += f / sr
		var pulse: float = 0.0
		if ph >= 1.0:
			ph -= 1.0
			pulse = _rng.randf_range(0.7, 1.0)
		bl += a_bl * (pulse - bl)
		bh += a_bh * (bl - bh)
		var strain: float = maxf(0.0, sin(x * TAU - 0.3)) + 0.25
		var atk: float = minf(1.0, t / 0.03)
		buf[i] = (bl - bh) * strain * atk * (1.0 - x * x)
	return buf


## Long dive whoosh: band-passed noise whose centre rises steadily, building and then
## cut off sharply (the impact follows), with a fluttery low wind layer.
func _synth_dive_whoosh(dur: float) -> PackedFloat32Array:
	var n: int = _n(dur)
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)
	var lp: float = 0.0
	var lp2: float = 0.0
	var wl: float = 0.0
	var a_w: float = _coef(380.0)
	for i in range(n):
		var x: float = float(i) / float(n)
		var fc: float = 300.0 + 2700.0 * x * x
		var nz: float = _noise()
		lp += _coef(fc * 1.5) * (nz - lp)
		lp2 += _coef(fc * 0.65) * (lp - lp2)
		wl += a_w * (nz - wl)
		var flutter: float = 0.75 + 0.25 * sin(x * TAU * 11.0)
		var env: float = pow(x, 1.3) * (1.0 - smoothstep(0.88, 1.0, x))
		buf[i] = ((lp - lp2) * 2.0 + wl * 1.2) * env * flutter
	return buf


## Normalize, soft-clip, light bit-crush, encode as 16-bit little-endian PCM.
func _to_wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n: int = buf.size()
	var peak: float = 0.0001
	for i in range(n):
		peak = maxf(peak, absf(buf[i]))
	var gain: float = 1.25 / peak
	var data: PackedByteArray = PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var v: float = tanh(buf[i] * gain) * 0.92
		var s: int = int(roundf(v * 2047.0)) * 16 # ~12-bit cartridge grit
		s = clampi(s, -32768, 32767)
		data.encode_s16(i * 2, s)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav

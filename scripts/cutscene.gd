extends Node3D
## City 2 City Wrestling - STORY MODE cutscene engine (mid-2000s skate-game story scenes).
##
## Usage (story flow):
##   var cs: Node = preload("res://cutscene.tscn").instantiate()
##   add_child(cs)
##   cs.finished.connect(_on_cutscene_done)            # finished(skipped: bool)
##   cs.show_title_card("CHAPTER 1", "Rent Is Due", "teaser")   # optional; play() waits for it
##   cs.play(StoryData.CHAPTERS[0]["intro"], StoryData.CAST)
## Launched directly (F6 / as the main scene) it plays scripts/story_data.gd's chapter 1 intro
## when that file exists, else a built-in two-scene demo, and loops.
##
## Everything is built in code: eight cheap, readable sets (kitchen, bedroom, backyard, street,
## store_lot, porch, car, rooftop) lit for day / dusk / night and run through the same warm
## grade + bloom post pass as the match; the cast are real wrestler.gd models (cutscene_actor.gd)
## with an emote pose layer; a shot-based camera (wide / two_shot / close / over_shoulder /
## low_hero / insert) that cuts between lines and drifts; letterbox UI with a typewriter
## dialogue box, text-message bubbles, narrator captions, "+$N" cash pops and chapter cards.
## Sets and character models are built lazily (one heavy step per frame behind a fade) and
## cached for the whole cutscene. The 3D world lives in its own SubViewport World3D, so the
## cutscene can be instanced on top of any other scene.

signal finished(skipped: bool)
signal title_card_done

const Actor := preload("res://scripts/cutscene_actor.gd")
const Wrestler := preload("res://scripts/wrestler.gd")
const Roster := preload("res://scripts/roster.gd")
const Audio := preload("res://scripts/audio.gd")
const Music := preload("res://scripts/music.gd")
const StoryText := preload("res://scripts/story_text.gd")
const STORY_DATA_PATH := "res://scripts/story_data.gd"

## Play every set once (day/dusk/night) instead of the demo when launched directly.
@export var tour := false
## Standalone: which story_data chapter intro to play (0 = chapter 1). On the web the page URL
## can override it for testing: ?ch=6 (1-based), ?tour=1, ?auto=1.
@export var chapter := 0
## Advance lines by themselves after a pause (off by default; the player taps / presses).
@export var auto_advance := false

const SKIP_HOLD := 0.8          # seconds to hold SKIP
const TYPE_CPS := 46.0          # typewriter characters per second
const FADE_TIME := 0.28

const MARKS := {
	"left": Vector3(-0.9, 0.0, 0.15), "right": Vector3(0.9, 0.0, 0.15), "center": Vector3(0.0, 0.0, 0.4),
	"back_left": Vector3(-1.75, 0.0, -0.85), "back_right": Vector3(1.75, 0.0, -0.85),
}
const CAR_MARKS := {
	"left": Vector3(-0.4, 0.0, 0.0), "right": Vector3(0.4, 0.0, 0.0), "center": Vector3(0.0, 0.0, -0.95),
	"back_left": Vector3(-0.4, 0.0, -0.95), "back_right": Vector3(0.4, 0.0, -0.95),
}

# ---------------------------------------------------------------- built-in demo

const DEMO_CAST := {
	"tank": {"name": "TANK", "roster_id": "tank"},
	"peligro": {"name": "LIL PELIGRO", "roster_id": "peligro"},
	"mom": {"name": "MOM", "anim_style": "diva", "look": {
		"gear": Color(0.95, 0.55, 0.2), "skin": Color(0.4, 0.27, 0.19), "face": "kid",
		"hair": "curls", "hair_color": Color(0.12, 0.08, 0.07),
		"top": "hoodie", "top_color": Color(0.62, 0.32, 0.5), "top_accent": Color(0.95, 0.85, 0.7),
		"graphic": "none", "hood": false, "sleeves": "long",
		"bottom_color": Color(0.22, 0.22, 0.3), "bottom_fade": Color(0.4, 0.4, 0.5),
		"shoe_color": Color(0.9, 0.88, 0.85), "shoe_accent": Color(0.6, 0.3, 0.5),
		"bracelet": true, "bulk": 0.84, "body": "female"}},
}

const DEMO := [
	{"set": "kitchen", "time": "day", "music": "chill", "cast": {"tank": "left", "mom": "right"},
	 "lines": [
		{"who": "narrator", "text": "Tuesday. 11:40 AM. Tank Magruder is awake. Technically."},
		{"who": "mom", "text": "Tanklin Magruder. Why is there a folding table in my bathtub?", "emote": "cross_arms"},
		{"who": "tank", "text": "Okay so. That's a training table. It's for the craft, Ma.", "emote": "shrug"},
		{"who": "mom", "text": "The craft. The rent is due Friday and you're out here doing CRAFTS.", "emote": "angry", "action": "slam_table", "sfx": "thud"},
		{"who": "phone", "text": "PELIGRO: yo backyard show tonight. crowd is CRAZY. u in?? $$$"},
		{"who": "tank", "text": "...Ma. What if I told you the craft pays cash?", "emote": "think", "shot": "close"},
	]},
	{"set": "backyard", "time": "night", "music": "hype", "cast": {"tank": "left", "peligro": "offscreen"},
	 "lines": [
		{"who": "peligro", "text": "AYYY the big man showed up! Thought you were scared of my trampoline!", "emote": "point", "action": "enter_right"},
		{"who": "tank", "text": "Scared? Kid, I eat trampolines for breakfast.", "emote": "flex", "shot": "low_hero", "sfx": "cheer_small"},
		{"who": "peligro", "text": "Crowd threw tips just for you walking out. Here, your cut.", "emote": "laugh", "cash": 40},
		{"who": "tank", "text": "Forty bucks. Ma's gonna cry. Let's GO.", "emote": "cheer", "shot": "two_shot"},
	]},
]

## Every set once, for screenshots and look-dev (export var `tour`).
const TOUR := [
	{"set": "kitchen", "time": "day", "cast": {"tank": "left", "mom": "right"}, "lines": [
		{"who": "mom", "text": "Kitchen, day. Bills on the fridge, sunlight through the window.", "emote": "point", "shot": "wide"},
		{"who": "tank", "text": "Over the shoulder. I'm listening, Ma. Mostly.", "emote": "sit", "shot": "over_shoulder"}]},
	{"set": "bedroom", "time": "night", "cast": {"tank": "center"}, "lines": [
		{"who": "tank", "text": "Bedroom, night. Posters, trophies, laundry mountain.", "emote": "shrug", "shot": "wide"},
		{"who": "tv", "text": "...AND THAT'S A WRAP ON TONIGHT'S EPISODE OF DRAMA COURT!", "shot": "insert"}]},
	{"set": "backyard", "time": "night", "cast": {"tank": "left", "peligro": "right"}, "lines": [
		{"who": "peligro", "text": "Backyard, night. String lights and the floodlight.", "emote": "cheer", "shot": "wide"},
		{"who": "tank", "text": "Low hero shot. Look at me. LOOK AT ME.", "emote": "flex", "shot": "low_hero"}]},
	{"set": "street", "time": "dusk", "cast": {"tank": "left", "peligro": "right"}, "lines": [
		{"who": "tank", "text": "Street at dusk. Curb, houses, streetlight coming on.", "emote": "talk", "shot": "wide"},
		{"who": "peligro", "text": "Close up. You owe me five bucks.", "emote": "point", "shot": "close"}]},
	{"set": "store_lot", "time": "night", "cast": {"tank": "left", "peligro": "right"}, "lines": [
		{"who": "narrator", "text": "Corner store lot, night. Neon sign, dumpster, parking lines.", "shot": "wide"},
		{"who": "tank", "text": "Two shot. Gimme a slushie, I'll give you a suplex.", "emote": "laugh", "shot": "two_shot", "cash": 25}]},
	{"set": "porch", "time": "night", "cast": {"tank": "left", "mom": "right"}, "lines": [
		{"who": "mom", "text": "Porch, night. Porch light, railing, steps.", "emote": "cross_arms", "shot": "wide"},
		{"who": "tank", "text": "Knock knock. It's me. I live here.", "emote": "sad", "action": "door_knock"}]},
	{"set": "car", "time": "night", "cast": {"tank": "left", "mom": "right"}, "lines": [
		{"who": "mom", "text": "Inside the car at night. Dashboard glow, streetlights passing.", "emote": "talk", "shot": "two_shot"},
		{"who": "phone", "text": "BOOKER: heard u got moves. prove it. saturday. my block."}]},
	{"set": "rooftop", "time": "dusk", "cast": {"tank": "left", "peligro": "right"}, "lines": [
		{"who": "peligro", "text": "Rooftop at dusk. The whole city's out there, man.", "emote": "think", "shot": "wide"},
		{"who": "tank", "text": "And one day they're all gonna know my name.", "emote": "idle", "shot": "close"}]},
]

# ---------------------------------------------------------------- lighting presets

const TIMES := {
	"day": {"top": Color(0.32, 0.52, 0.85), "hor": Color(0.86, 0.82, 0.7), "gnd": Color(0.35, 0.3, 0.25),
		"stars": 0.0, "sun_dir": Vector3(0.45, 0.75, 0.5), "sun_col": Color(1.0, 0.93, 0.8), "sun_e": 1.25,
		"amb": Color(0.6, 0.66, 0.78), "amb_e": 0.55, "fog": Color(0.75, 0.75, 0.72), "fog_d": 0.006,
		"practical": 0.25, "key_e": 0.9, "key_col": Color(1.0, 0.92, 0.8), "win": Color(0.85, 0.92, 1.0), "win_e": 1.4},
	"dusk": {"top": Color(0.2, 0.18, 0.42), "hor": Color(1.0, 0.5, 0.24), "gnd": Color(0.2, 0.12, 0.1),
		"stars": 0.15, "sun_dir": Vector3(-0.7, 0.18, -0.6), "sun_col": Color(1.0, 0.55, 0.28), "sun_e": 0.95,
		"amb": Color(0.6, 0.45, 0.55), "amb_e": 0.42, "fog": Color(0.5, 0.3, 0.28), "fog_d": 0.012,
		"practical": 0.75, "key_e": 1.5, "key_col": Color(1.0, 0.75, 0.52), "win": Color(1.0, 0.6, 0.35), "win_e": 1.1},
	"night": {"top": Color(0.012, 0.018, 0.06), "hor": Color(0.1, 0.08, 0.16), "gnd": Color(0.03, 0.03, 0.05),
		"stars": 1.0, "sun_dir": Vector3(0.4, 0.55, 0.75), "sun_col": Color(0.58, 0.68, 1.0), "sun_e": 0.4,
		"amb": Color(0.36, 0.42, 0.66), "amb_e": 0.3, "fog": Color(0.07, 0.08, 0.15), "fog_d": 0.02,
		"practical": 1.0, "key_e": 1.9, "key_col": Color(1.0, 0.8, 0.58), "win": Color(0.15, 0.2, 0.38), "win_e": 0.6},
}

const SKY_SHADER := """
shader_type sky;

uniform vec3 top_col = vec3(0.1, 0.1, 0.3);
uniform vec3 hor_col = vec3(0.5, 0.4, 0.3);
uniform vec3 gnd_col = vec3(0.1, 0.1, 0.1);
uniform float stars = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.5, -1.0);
uniform vec3 sun_col = vec3(1.0, 0.8, 0.6);

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(hor_col, top_col, smoothstep(0.0, 0.5, h));
	col = mix(col, gnd_col, smoothstep(0.0, -0.12, h));
	vec3 cell = floor(d * 260.0);
	float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	col += vec3(0.9, 0.9, 1.0) * step(0.993, r) * smoothstep(0.05, 0.25, h) * stars * (0.4 + 0.6 * fract(r * 91.7));
	float m = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_col * (pow(m, 10.0) * 0.35 + smoothstep(0.9994, 0.9997, m) * 1.5);
	COLOR = col;
}
"""

# Same grade as main.gd / title.gd (sharpen, cheap bloom, contrast/saturation, warm highlights
# / cool shadows split toning, vignette), with a touch more warmth for the story sepia.
const POST_SHADER := """
shader_type canvas_item;

uniform float contrast = 1.12;
uniform float saturation = 1.1;
uniform float sharpen = 0.14;
uniform float bloom_threshold = 0.66;
uniform float bloom_strength = 0.75;
uniform float bloom_radius = 5.0;
uniform vec3 shadow_tint = vec3(0.92, 0.96, 1.08);
uniform vec3 highlight_tint = vec3(1.1, 1.0, 0.84);
uniform float vignette = 0.42;

vec3 bright(vec3 c) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return c * smoothstep(bloom_threshold, 0.95, l);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 c = texture(TEXTURE, UV).rgb;
	vec3 nb = texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb
		+ texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).rgb
		+ texture(TEXTURE, UV - vec2(0.0, px.y)).rgb;
	c = max(c + (c - nb * 0.25) * sharpen, vec3(0.0));
	vec3 bl = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472;
		vec2 d = vec2(cos(a), sin(a)) * px * bloom_radius;
		vec2 d2 = vec2(cos(a + 0.5236), sin(a + 0.5236)) * px * bloom_radius * 2.3;
		bl += bright(texture(TEXTURE, UV + d).rgb) * 0.6;
		bl += bright(texture(TEXTURE, UV + d2).rgb) * 0.4;
	}
	c += bl / 6.0 * bloom_strength;
	c = (c - 0.5) * contrast + 0.5;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);
	l = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
	vec3 tint = mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.75, l));
	c *= mix(vec3(1.0), tint, 0.85);
	vec2 v = (UV - 0.5) * vec2(1.0, 0.85) * 1.414;
	c *= 1.0 - vignette * smoothstep(0.3, 1.0, dot(v, v));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

enum Phase { IDLE, CARD, LOADING, LINE, DONE }

var phase: int = Phase.IDLE
var headless := false
var standalone := false
var scenes: Array = []
var cast_def: Dictionary = {}
var scene_i := -1
var line_i := -1
var cur_scene: Dictionary = {}
var cur_set := ""
var cur_time := ""
var clock := 0.0
var _started := false
var _pending_play := false

# 3D
var view: SubViewport
var view_rect: TextureRect
var post_mat: ShaderMaterial
var world: Node3D
var camera: Camera3D
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var key_light: SpotLight3D
var rim_light: SpotLight3D
var sets := {}                  # name -> {"root", "interior", "anchors", "lights", "emis", "anim"}
var _build: Node3D              # parent for the set being built
var _build_info: Dictionary = {}
var actors := {}                # cast id -> Actor
var chairs := {}                # cast id -> chair Node3D
var _tex_cache := {}
var _mat_cache := {}

# camera
var shot := "wide"
var shot_subject: Node3D = null
var shot_other: Node3D = null
var shot_t := 0.0
var shot_seed := 0.0
var shake := 0.0
var _shot_count := 0

# line state
var speaker_id := ""
var type_label: Label = null
var type_total := 0
var type_shown := 0.0
var line_done_t := 0.0
var _blips := 0
var _blip_pitch := 1.0
var input_lock := 0.0

# loading queue: callables run one per frame behind the fade
var _queue: Array[Callable] = []
var fade_a := 1.0
var fade_target := 1.0

# skip
var skip_keys := false
var skip_touch := false
var skip_t := 0.0
var _use_touch := true

# audio
var audio: Node = null
var music: Node = null
var music_mood := ""
var _blip_players: Array[AudioStreamPlayer] = []
var _blip_i := 0
var _blip_stream: AudioStreamWAV = null

# UI
var ui_layer: CanvasLayer
var ui: Control
var fade_rect: ColorRect
var bar_top: ColorRect
var bar_bot: ColorRect
var box: PanelContainer
var box_style: StyleBoxFlat
var name_plate: PanelContainer
var name_style: StyleBoxFlat
var name_label: Label
var portrait: PanelContainer
var portrait_style: StyleBoxFlat
var portrait_label: Label
var text_label: Label
var next_arrow: Label
var caption: PanelContainer
var caption_label: Label
var phone: PanelContainer
var phone_head: Label
var phone_label: Label
var cash_label: Label
var skip_box: PanelContainer
var skip_label: Label
var skip_fill: ColorRect
var card: Control
var card_bg: ColorRect
var card_title: Label
var card_name: Label
var card_teaser: Label
var card_hint: Label
var card_t := 0.0
var card_active := false
var loading_label: Label
var font_b: FontVariation
var font_i: FontVariation
var ui_scale := 1.0


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	if headless:
		auto_advance = true
	_use_touch = bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))
	font_b = FontVariation.new()
	font_b.base_font = ThemeDB.fallback_font
	font_b.variation_embolden = 1.0
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.2
	font_i.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)
	_build_view()
	_build_world()
	_build_ui()
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	_maybe_standalone.call_deferred()


# ================================================================ public API

## Play a list of SCENE dicts (see story_schema.md) with the story CAST. Emits finished(skipped).
func play(p_scenes: Array, p_cast: Dictionary = {}) -> void:
	_started = true
	# The protagonist ("tank" slot) is the created wrestler when there is one; story text tokens
	# ({NAME}, {his}...) resolve here so every caption / phone / TV / cash line shows them right.
	scenes = StoryText.resolve_deep(p_scenes)
	cast_def = StoryText.hero_cast(p_cast)
	scene_i = -1
	line_i = -1
	if audio == null:
		audio = Audio.new()
		add_child(audio)
	if music == null:
		music = Music.new()
		add_child(music)
		_setup_music_bus()
	if card_active:
		_pending_play = true   # starts when the chapter card is dismissed
		return
	_next_scene()


## Chapter card ("CHAPTER 1" / "Rent Is Due" / teaser). Tap or ~4 s dismisses it; emits
## title_card_done. play() called while a card is up waits for it.
func show_title_card(title: String, chapter_name: String, teaser := "") -> void:
	card_title.text = StoryText.resolve(title).to_upper()
	card_name.text = StoryText.resolve(chapter_name).to_upper()
	card_teaser.text = StoryText.resolve(teaser)
	card.visible = true
	card.modulate.a = 0.0
	card_active = true
	card_t = 0.0
	input_lock = 0.5
	box.visible = false
	caption.visible = false
	phone.visible = false
	_snd("big_thud", -6.0)


## Skip the whole cutscene right now (same as holding SKIP).
func skip() -> void:
	_finish(true)


func set_auto_advance(on: bool) -> void:
	auto_advance = on


# ================================================================ flow

func _maybe_standalone() -> void:
	if _started or get_tree().current_scene != self:
		return
	standalone = true
	_play_standalone()


func _play_standalone() -> void:
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.call("eval", "window.location.search", true))
		for kv in q.trim_prefix("?").split("&", false):
			var p := kv.split("=")
			if p.size() == 2 and p[0] == "ch":
				chapter = maxi(0, int(p[1]) - 1)
			elif p.size() == 2 and p[0] == "tour":
				tour = p[1] == "1"
			elif p.size() == 2 and p[0] == "auto":
				auto_advance = p[1] == "1"
	if tour:
		play(TOUR, DEMO_CAST)
		return
	if ResourceLoader.exists(STORY_DATA_PATH):
		var sd: Script = load(STORY_DATA_PATH)
		if sd != null:
			var consts: Dictionary = sd.get_script_constant_map()
			var chapters: Array = consts.get("CHAPTERS", [])
			var cast: Dictionary = consts.get("CAST", {})
			if not chapters.is_empty():
				var ch: Dictionary = chapters[clampi(chapter, 0, chapters.size() - 1)]
				var intro: Array = ch.get("intro", [])
				if not intro.is_empty():
					show_title_card(str(ch.get("title", "CHAPTER 1")), str(ch.get("name", "")), str(ch.get("teaser", "")))
					play(intro, cast)
					return
	show_title_card("CHAPTER 0", "The Craft", "A backyard legend needs rent money by Friday.")
	play(DEMO, DEMO_CAST)


func _next_scene() -> void:
	scene_i += 1
	if scene_i >= scenes.size():
		_finish(false)
		return
	cur_scene = scenes[scene_i]
	phase = Phase.LOADING
	fade_target = 1.0
	_hide_line_ui()
	var set_name := str(cur_scene.get("set", "backyard"))
	var time := str(cur_scene.get("time", "night"))
	if not TIMES.has(time):
		time = "night"
	_queue.clear()
	if not sets.has(set_name):
		_queue.append(_build_set.bind(set_name))
	var sc: Dictionary = cur_scene.get("cast", {})
	for id in sc:
		if not actors.has(str(id)):
			_queue.append(_spawn_actor.bind(str(id)))
	_queue.append(_stage_scene.bind(set_name, time))


func _finish(skipped: bool) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	_queue.clear()
	_hide_line_ui()
	card.visible = false
	card_active = false
	if music != null:
		music.fade_out(0.6)
	fade_target = 1.0
	skip_t = 0.0
	finished.emit(skipped)
	if standalone:
		if headless:
			print("cutscene (headless): finished, skipped=%s" % skipped)
			return
		get_tree().create_timer(1.5).timeout.connect(func():
			_started = false
			phase = Phase.IDLE
			_play_standalone())


func _stage_scene(set_name: String, time: String) -> void:
	for k in sets:
		var s: Dictionary = sets[k]
		var r: Node3D = s["root"]
		r.visible = k == set_name
	cur_set = set_name
	cur_time = time
	_apply_lighting(set_name, time)
	var in_car := set_name == "car"
	var marks: Dictionary = CAR_MARKS if in_car else MARKS
	# who enters later in this scene starts hidden
	var enters := {}
	var lines: Array = cur_scene.get("lines", [])
	for ln: Dictionary in lines:
		var a := str(ln.get("action", ""))
		var who := str(ln.get("who", ""))
		if a.begins_with("enter_") and not enters.has(who):
			enters[who] = a
	for id in actors:
		var act: Actor = actors[id]
		act.visible = false
		act.sitting = false
		act.talking = false
		act.action = ""
		act.walk_target = Vector3.INF
		act.emote = "idle"
		act.state = Wrestler.S.IDLE
		act.state_time = 0.0
		act.calm = str(cur_scene.get("music", "")) != "hype"
		(chairs[id] as Node3D).visible = false
	var sc: Dictionary = cur_scene.get("cast", {})
	for id in sc:
		var sid := str(id)
		if not actors.has(sid):
			continue
		var act: Actor = actors[sid]
		var mark := str(sc[id])
		if mark == "offscreen" or enters.has(sid):
			act.visible = false
			act.position = Vector3(-6.0, 0.0, 0.0)
			continue
		act.visible = true
		act.position = marks.get(mark, marks["center"])
		act.sitting = in_car
	_restage_yaws(true)
	shot = "wide"
	_shot_count = 0
	shot_subject = null
	shot_other = null
	shot_t = 0.0
	_set_music(str(cur_scene.get("music", "chill")))
	line_i = -1
	fade_target = 0.0
	phase = Phase.LINE
	_next_line()


func _next_line() -> void:
	line_i += 1
	var lines: Array = cur_scene.get("lines", [])
	if line_i >= lines.size():
		_next_scene()
		return
	_begin_line(lines[line_i])


func _advance() -> void:
	if input_lock > 0.0:
		return
	input_lock = 0.14
	if card_active:
		if card_t > 0.5:
			_dismiss_card()
		return
	if phase != Phase.LINE:
		return
	if type_label != null and type_shown < type_total:
		type_shown = type_total
		type_label.visible_characters = -1
		return
	_snd("whoosh", -16.0, 0.1)
	_next_line()


func _dismiss_card() -> void:
	card_active = false
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): card.visible = false)
	title_card_done.emit()
	if _pending_play:
		_pending_play = false
		_next_scene()


# ================================================================ lines

func _begin_line(ln: Dictionary) -> void:
	var who := str(ln.get("who", "narrator"))
	var text := str(ln.get("text", ""))
	var emote := str(ln.get("emote", ""))
	var action := str(ln.get("action", ""))
	speaker_id = who
	line_done_t = 0.0
	_blips = 0
	var act: Actor = _visible_actor(who)
	# phone / narrator / tv: the emote goes to whoever is holding the phone (Tank first)
	var holder: Actor = act
	if holder == null and (who == "phone" or who == "narrator" or who == "tv"):
		holder = _visible_actor("tank")
		if holder == null:
			for id in actors:
				var a2: Actor = actors[id]
				if a2.visible:
					holder = a2
					break
	if who == "phone" and holder != null and emote == "":
		emote = "phone"
	if holder != null and emote != "":
		holder.set_emote(emote)
	if action != "":
		_do_action(who, action)
		act = _visible_actor(who)
	for id in actors:
		var a3: Actor = actors[id]
		a3.talking = false
	if act != null:
		act.talking = true
	# camera
	var subj: Actor = act if act != null else holder
	_choose_shot(str(ln.get("shot", "")), subj, who)
	# sound / cash
	var sfx := str(ln.get("sfx", ""))
	if sfx != "":
		_snd(sfx, -4.0)
	var cash := int(ln.get("cash", 0))
	if cash != 0:
		_cash_pop(cash)
	# UI
	_hide_line_ui()
	match who:
		"narrator":
			caption.visible = true
			caption_label.text = text
			_start_type(caption_label, 1.0)
			_pop_in(caption)
		"phone":
			phone.visible = true
			var parts := text.split(":", false, 1)
			if parts.size() == 2 and parts[0].length() <= 18 and parts[0].strip_edges().to_upper() == parts[0].strip_edges():
				phone_head.text = "NEW MESSAGE  -  " + parts[0].strip_edges()
				phone_label.text = parts[1].strip_edges()
			else:
				phone_head.text = "NEW MESSAGE"
				phone_label.text = text
			_start_type(phone_label, 1.25)
			_snd("trick", -6.0, 0.0)
			_pop_in(phone)
		_:
			box.visible = true
			var nm := _display_name(who)
			var col := _color_of(who)
			name_label.text = nm
			name_style.bg_color = col
			box_style.border_color = col
			portrait_style.bg_color = col.darkened(0.35)
			portrait_style.border_color = col.lightened(0.3)
			portrait_label.text = _initials(nm)
			name_label.add_theme_color_override("font_color", Color(0.06, 0.04, 0.03) if col.get_luminance() > 0.5 else Color(1, 1, 1))
			text_label.text = text
			_start_type(text_label, 0.85 + 0.35 * fposmod(float(who.hash() % 100) / 100.0, 1.0))
			_pop_in(box)


func _start_type(lbl: Label, pitch: float) -> void:
	type_label = lbl
	type_total = lbl.text.length()
	type_shown = 0.0
	lbl.visible_characters = 0
	_blip_pitch = pitch
	next_arrow.visible = false


func _hide_line_ui() -> void:
	box.visible = false
	caption.visible = false
	phone.visible = false
	next_arrow.visible = false
	type_label = null


func _pop_in(c: Control) -> void:
	c.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.12)


func _visible_actor(id: String) -> Actor:
	if actors.has(id):
		var a: Actor = actors[id]
		if a.visible:
			return a
	return null


func _cast_entry(id: String) -> Dictionary:
	if cast_def.has(id):
		return cast_def[id]
	if DEMO_CAST.has(id):
		return DEMO_CAST[id]
	if Roster.index_of(id) >= 0:
		return {"name": str(Roster.find(id)["short_name"]), "roster_id": id}
	return {}


func _display_name(id: String) -> String:
	if id == "tv":
		return "TV"
	var e := _cast_entry(id)
	if e.has("name"):
		return str(e["name"])
	return id.to_upper()


func _look_of(id: String) -> Dictionary:
	var e := _cast_entry(id)
	var look: Dictionary = {}
	if e.has("look"):
		var l0: Dictionary = e["look"]
		look = l0.duplicate(true)
	elif e.has("roster_id") or Roster.index_of(id) >= 0:
		var rid := str(e.get("roster_id", id))
		var l1: Dictionary = Roster.find(rid)["look"]
		look = l1.duplicate(true)
	else:
		look = {"gear": _hash_color(id), "face": "kid", "hair": "curls", "top": "hoodie",
			"top_color": _hash_color(id).darkened(0.4), "graphic": "none", "bulk": 0.9}
	if e.has("anim_style") and not look.has("anim_style"):
		look["anim_style"] = e["anim_style"]
	return look


func _color_of(id: String) -> Color:
	if id == "tv":
		return Color(0.45, 0.75, 1.0)
	var e := _cast_entry(id)
	if e.has("color"):
		return e["color"]
	var look := _look_of(id)
	if look.has("gear"):
		return look["gear"]
	return _hash_color(id)


func _hash_color(id: String) -> Color:
	return Color.from_hsv(fposmod(float(id.hash() % 1000) / 1000.0, 1.0), 0.6, 0.9)


func _initials(nm: String) -> String:
	var parts := nm.split(" ", false)
	if parts.is_empty():
		return "?"
	if parts.size() == 1:
		return parts[0].substr(0, 2)
	return parts[0].substr(0, 1) + parts[parts.size() - 1].substr(0, 1)


# ================================================================ actions & staging

func _partner_of(a: Actor) -> Actor:
	var best: Actor = null
	var bd := 1e9
	for id in actors:
		var o: Actor = actors[id]
		if o == a or not o.visible:
			continue
		var d := o.position.distance_to(a.position)
		if d < bd:
			bd = d
			best = o
	return best


func _do_action(who: String, action: String) -> void:
	if not actors.has(who):
		return
	var a: Actor = actors[who]
	var in_car := cur_set == "car"
	var sc: Dictionary = cur_scene.get("cast", {})
	var marks: Dictionary = CAR_MARKS if in_car else MARKS
	var mark: Vector3 = marks.get(str(sc.get(who, "center")), marks["center"])
	if mark == Vector3.ZERO and str(sc.get(who, "")) == "offscreen":
		mark = marks["center"]
	if str(sc.get(who, "")) == "offscreen":
		mark = marks["right"] if action == "enter_right" else (marks["left"] if action == "enter_left" else marks["center"])
	match action:
		"enter_left", "enter_right":
			a.visible = true
			if in_car:
				a.position = mark
				a.sitting = true
				return
			a.position = Vector3(-4.8 if action == "enter_left" else 4.8, 0.0, mark.z)
			a.move_to(mark)
			a.yaw_target = atan2(mark.x - a.position.x, 0.0)
			a.snap_yaw()
		"exit_left", "exit_right":
			if in_car:
				a.visible = false
				return
			a.move_to(Vector3(-5.0 if action == "exit_left" else 5.0, 0.0, a.position.z + 0.3), "hide")
		"slam_table":
			var info: Dictionary = sets[cur_set]
			var anc: Dictionary = info["anchors"]
			if anc.has("table") and not a.sitting:
				var tp: Vector3 = anc["table"]
				var d := a.position - tp
				d.y = 0.0
				d.z = maxf(d.z, 0.2)
				var stand := tp + d.normalized() * 0.95
				a.act_target = tp
				a.move_to(stand, "slam")
			else:
				a.start_action("slam")
		"door_knock":
			var info2: Dictionary = sets[cur_set]
			var anc2: Dictionary = info2["anchors"]
			if anc2.has("door"):
				var dp: Vector3 = anc2["door"]
				a.act_target = dp
				a.move_to(dp + Vector3(0.0, 0.0, 0.55), "knock")
			else:
				a.start_action("knock")
		"hug", "shake_hands":
			var o := _partner_of(a)
			if o == null:
				return
			var mid := (a.position + o.position) * 0.5
			var dir := (a.position - o.position)
			dir.y = 0.0
			if dir.length() < 0.01:
				dir = Vector3.RIGHT
			dir = dir.normalized()
			var gap := 0.27 if action == "hug" else 0.42
			var kind := "hug" if action == "hug" else "shake"
			a.look_at_node = o
			o.look_at_node = a
			if a.sitting or in_car:
				a.start_action(kind)
				o.start_action(kind)
			else:
				a.move_to(mid + dir * gap, kind)
				o.move_to(mid - dir * gap, kind)
		_:
			if action.begins_with("walk_to:"):
				var tgt := action.substr(8)
				if marks.has(tgt) and not in_car:
					a.visible = true
					a.move_to(marks[tgt])


func _restage_yaws(snap: bool) -> void:
	for id in actors:
		var a: Actor = actors[id]
		if not a.visible:
			continue
		var sp: Actor = _visible_actor(speaker_id)
		var partner := _partner_of(a)
		if a.action == "hug" or a.action == "shake":
			pass
		elif sp != null and sp != a:
			a.look_at_node = sp
		else:
			a.look_at_node = partner
		if a.is_walking():
			continue
		if cur_set == "car" or a.sitting and cur_set != "kitchen":
			a.yaw_target = 0.0
		elif (a.action == "slam" or a.action == "knock") and a.act_target != Vector3.INF:
			a.face_point(a.act_target)
		elif a.action == "hug" or a.action == "shake":
			if a.look_at_node != null:
				a.face_point(a.look_at_node.position)
		elif partner != null:
			# toward the partner, opened up toward the camera (stage blocking)
			var d := partner.position - a.position
			d.y = 0.0
			var y_partner := atan2(d.x, d.z)
			a.yaw_target = lerp_angle(y_partner, 0.0, 0.32)
		else:
			a.yaw_target = 0.0
		if snap:
			a.snap_yaw()


func _on_impact(a: Actor, kind: String) -> void:
	match kind:
		"slam":
			_snd("big_thud", -2.0)
			shake = maxf(shake, 0.7)
			var info: Dictionary = sets.get(cur_set, {})
			if info.has("anim"):
				var an: Dictionary = info["anim"]
				if an.has("table_node"):
					var tn: Node3D = an["table_node"]
					var tw := create_tween()
					tw.tween_property(tn, "position:y", 0.04, 0.05)
					tw.tween_property(tn, "position:y", 0.0, 0.12)
		"knock":
			_snd("wood", -3.0, 0.1)
			shake = maxf(shake, 0.12)
	if a != null:
		pass


# ================================================================ camera

func _choose_shot(hint: String, subj: Actor, who: String) -> void:
	var s := hint
	var other: Actor = null
	if subj != null:
		other = _partner_of(subj)
	if s == "":
		if line_i == 0:
			s = "wide"
		elif subj == null or who == "narrator":
			s = shot
		elif who == "phone":
			s = "close"
		elif subj != shot_subject:
			s = "over_shoulder" if (_shot_count % 2 == 0 and other != null) else "close"
		else:
			s = "two_shot" if other != null else "close"
	if who == "tv" and hint == "":
		s = "insert"
	if (s == "over_shoulder" or s == "two_shot") and other == null:
		s = "close"
	if subj == null and s != "insert":
		s = "wide"
	var cut := s != shot or subj != shot_subject or line_i == 0
	shot = s
	shot_subject = subj
	shot_other = other
	if cut:
		shot_t = 0.0
		shot_seed = randf() * 10.0
		_shot_count += 1


func _face_of(a: Node3D) -> Vector3:
	var h: Node3D = a.get("head")
	if h == null:
		return a.global_position + Vector3(0, 1.65, 0)
	return h.global_position + Vector3(0, 0.06, 0)


func _cast_center() -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for id in actors:
		var a: Actor = actors[id]
		if a.visible and absf(a.position.x) < 4.0:
			c += a.position
			n += 1
	if n == 0:
		return Vector3(0, 0, 0)
	return c / n


func _update_camera(dt: float) -> void:
	shot_t += dt
	var pos := Vector3(0, 1.5, 5.5)
	var tgt := Vector3(0, 1.0, 0)
	var fov := 50.0
	var subj: Node3D = shot_subject if shot_subject != null and shot_subject.visible else null
	var oth: Node3D = shot_other if shot_other != null and shot_other.visible else null
	var info: Dictionary = sets.get(cur_set, {})
	var anc: Dictionary = info.get("anchors", {})
	var s := shot
	if cur_set == "car":
		_car_camera(s, subj, oth, anc)
		return
	match s:
		"two_shot":
			if subj != null and oth != null:
				var mid := (subj.global_position + oth.global_position) * 0.5
				var side := -signf(subj.global_position.x - oth.global_position.x)
				var yaw := 0.28 * side
				var dist := 2.6 + 0.55 * subj.global_position.distance_to(oth.global_position)
				pos = mid + Vector3(sin(yaw) * dist, 1.45, cos(yaw) * dist)
				tgt = mid + Vector3(0, 1.25, 0)
				fov = 42.0
		"close":
			if subj != null:
				var f := _face_of(subj)
				var fwd: Vector3 = subj.global_basis.z
				fwd.y = 0.0
				var dir := fwd.normalized() + Vector3(0, 0, 1.0)
				if dir.length() < 0.6:
					# facing away from the camera (knocking on a door): shoot from the side
					dir = Vector3(signf(subj.global_position.x + 0.01) * 1.0, 0.0, 0.45)
				dir = dir.normalized()
				pos = f + dir * 1.45 + Vector3(0, 0.02, 0)
				tgt = f - Vector3(0, 0.06, 0)
				fov = 34.0
		"over_shoulder":
			if subj != null and oth != null:
				var f2 := _face_of(subj)
				var lh := _face_of(oth)
				var back := (lh - f2)
				back.y = 0.0
				back = back.normalized()
				var side2 := Vector3(back.z, 0.0, -back.x)
				if side2.z < 0.0:
					side2 = -side2
				pos = lh + back * 1.15 + side2 * 0.62 + Vector3(0, 0.14, 0)
				tgt = f2 - Vector3(0, 0.1, 0)
				fov = 38.0
		"low_hero":
			if subj != null:
				var fwd2: Vector3 = subj.global_basis.z
				fwd2.y = 0.0
				var dir2 := fwd2.normalized() + Vector3(0, 0, 1.3)
				if dir2.length() < 0.6:
					dir2 = Vector3(1.0, 0.0, 0.5)
				dir2 = dir2.normalized()
				pos = subj.global_position + dir2 * 2.3 + Vector3(0, 0.42, 0)
				tgt = subj.global_position + Vector3(0, 1.4, 0)
				fov = 46.0
		"insert":
			var ip: Vector3 = anc.get("insert", Vector3(0, 1.0, 0))
			if speaker_id == "tv" and anc.has("tv"):
				ip = anc["tv"]
			elif subj != null and subj.get("emote") in ["phone", "eat"]:
				ip = _face_of(subj) - Vector3(0, 0.05, 0)
			var ioff: Vector3 = anc.get("insert_off", Vector3(0.2, 0.15, 1.0))
			pos = ip + ioff
			tgt = ip
			fov = 36.0
		_:
			var c := _cast_center()
			var wy: float = info.get("wide_yaw", 0.1)
			var wd: float = info.get("wide_dist", 5.4)
			pos = c + Vector3(sin(wy) * wd, 1.6, cos(wy) * wd)
			tgt = c + Vector3(0, 1.05, 0)
			fov = 48.0
	# gentle drift + a slow push in
	var tt := shot_t + shot_seed
	var right := (tgt - pos).cross(Vector3.UP).normalized()
	pos += right * (0.07 * sin(tt * 0.31)) + Vector3(0, 0.03 * sin(tt * 0.23), 0)
	pos = pos.lerp(tgt, minf(shot_t * 0.012, 0.08))
	_place_camera(pos, tgt, fov)


func _car_camera(s: String, subj: Node3D, oth: Node3D, anc: Dictionary) -> void:
	var pos := Vector3(0.0, 1.28, 1.72)
	var tgt := Vector3(0.0, 1.12, 0.0)
	var fov := 50.0
	match s:
		"close", "over_shoulder", "low_hero":
			if subj != null:
				var f := _face_of(subj)
				var sx := signf(subj.global_position.x)
				if s == "over_shoulder":
					sx = -sx
				pos = Vector3(f.x * 0.4 - sx * 0.3, f.y + (-0.25 if s == "low_hero" else 0.02), 1.5)
				tgt = f - Vector3(0, 0.1, 0)
				fov = 40.0
		"insert":
			var ip: Vector3 = anc.get("insert", Vector3(-0.2, 0.95, 0.65))
			pos = ip + Vector3(0.25, 0.25, -0.5)
			tgt = ip
			fov = 40.0
		_:
			if subj != null and oth == null:
				tgt = _face_of(subj) - Vector3(0, 0.25, 0)
	var tt := shot_t + shot_seed
	pos += Vector3(0.015 * sin(tt * 1.7), 0.012 * sin(tt * 2.3) + 0.006 * sin(tt * 11.0), 0.0)  # road rumble
	_place_camera(pos, tgt, fov)


func _place_camera(pos: Vector3, tgt: Vector3, fov: float) -> void:
	var s := shake * shake
	pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.04 * s
	camera.position = pos
	if pos.distance_to(tgt) > 0.01:
		camera.look_at(tgt, Vector3.UP)
	camera.fov = fov
	# key light from camera-left, aimed at what we're looking at; rim from behind
	var right := camera.global_basis.x
	var kp := pos - right * 1.4 + Vector3(0, 1.1, 0)
	key_light.position = kp
	if kp.distance_to(tgt) > 0.01:
		key_light.look_at(tgt, Vector3.UP)
	var rp := tgt + Vector3(0.6, 1.6, -2.4)
	rim_light.position = rp
	rim_light.look_at(tgt, Vector3.UP)


# ================================================================ per frame

func _process(delta: float) -> void:
	var dt := clampf(delta, 0.0, 0.1)
	clock += dt
	input_lock = maxf(0.0, input_lock - delta)
	shake = maxf(0.0, shake - dt * 2.5)

	# fades: the loading queue only runs while the screen is black
	var fspeed := dt / FADE_TIME
	fade_a = move_toward(fade_a, fade_target, fspeed)
	fade_rect.color.a = fade_a
	fade_rect.visible = fade_a > 0.001
	if phase == Phase.LOADING and fade_a >= 0.999 and not card_active:
		if not _queue.is_empty():
			var job: Callable = _queue.pop_front()
			job.call()
	loading_label.visible = phase == Phase.LOADING and fade_a > 0.99 and not card_active and clock > 0.5
	if loading_label.visible:
		loading_label.modulate.a = 0.5 + 0.3 * sin(clock * 6.0)

	# chapter card
	if card_active or card.visible:
		card_t += dt
		if card_active:
			card.modulate.a = minf(1.0, card_t / 0.35)
			var k := _ease_out(card_t / 0.45)
			card_name.scale = Vector2.ONE * lerpf(1.6, 1.0, k)
			card_hint.visible = card_t > 1.0
			card_hint.modulate.a = 0.5 + 0.5 * sin(card_t * 5.0)
			if card_t > (0.8 if headless else 4.2):
				_dismiss_card()

	# typewriter
	if type_label != null and phase == Phase.LINE:
		if type_shown < type_total:
			var before := int(type_shown)
			type_shown = minf(float(type_total), type_shown + dt * (TYPE_CPS * (8.0 if headless else 1.0)))
			var now := int(type_shown)
			type_label.visible_characters = now
			for i in range(before, now):
				var ch := type_label.text.substr(i, 1)
				if ch != " " and i % 2 == 0:
					_blip()
		else:
			line_done_t += dt
			next_arrow.visible = box.visible and fmod(clock, 0.8) < 0.55
			for id in actors:
				var a0: Actor = actors[id]
				a0.talking = false
			if auto_advance and line_done_t > (0.15 if headless else 1.1 + type_total * 0.025):
				_next_line()

	# skip hold
	if phase == Phase.LINE or phase == Phase.LOADING:
		if skip_keys or skip_touch:
			skip_t += dt
			if skip_t >= SKIP_HOLD:
				_finish(true)
		else:
			skip_t = maxf(0.0, skip_t - dt * 3.0)
	skip_box.visible = phase == Phase.LINE or phase == Phase.LOADING
	skip_fill.visible = skip_box.visible and skip_t > 0.0
	skip_fill.position = skip_box.position
	skip_fill.size = Vector2(skip_box.size.x * clampf(skip_t / SKIP_HOLD, 0.0, 1.0), skip_box.size.y)
	name_plate.visible = box.visible
	name_plate.modulate.a = box.modulate.a
	skip_box.modulate.a = 0.55 + 0.45 * clampf(skip_t * 4.0, 0.0, 1.0)

	# world
	if phase == Phase.LINE:
		_restage_yaws(false)
		for id in actors:
			var a: Actor = actors[id]
			if a.visible:
				a.cs_update(dt)
				_place_chair(str(id), a)
		_animate_set(dt)
		_update_camera(dt)


func _ease_out(x: float) -> float:
	var c := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - c * c * c


func _place_chair(id: String, a: Actor) -> void:
	var ch: Node3D = chairs[id]
	var want := a.sitting and cur_set != "car" and not a.is_walking()
	ch.visible = want
	if want:
		ch.position = a.position - a.global_basis.z * 0.06
		ch.rotation.y = a.rotation.y


func _animate_set(dt: float) -> void:
	var info: Dictionary = sets.get(cur_set, {})
	if not info.has("anim"):
		return
	var an: Dictionary = info["anim"]
	if an.has("tv_mat"):
		var m: StandardMaterial3D = an["tv_mat"]
		var fl := 0.8 + 0.25 * sin(clock * 13.0) * sin(clock * 3.7) + 0.15 * sin(clock * 29.0)
		m.emission_energy_multiplier = 0.6 * fl
		if an.has("tv_light"):
			var tl: OmniLight3D = an["tv_light"]
			tl.light_energy = 0.9 * fl
	if an.has("pass_light"):
		var pl: OmniLight3D = an["pass_light"]
		var u := fmod(clock * 0.55, 1.0)
		pl.position = Vector3(1.4, 2.0, lerpf(4.0, -4.0, u))
		pl.light_energy = 2.2 * sin(u * PI) * float(an.get("pass_e", 1.0))
	if an.has("blink"):
		var bm: StandardMaterial3D = an["blink"]
		bm.emission_energy_multiplier = 3.0 if fmod(clock, 1.6) < 0.5 else 0.2
	if an.has("neon"):
		var nl: Label3D = an["neon"]
		var flick := 1.0
		var ph := fmod(clock, 7.0)
		if ph > 5.0 and ph < 5.25 and fmod(clock * 20.0, 2.0) < 1.0:
			flick = 0.35
		nl.modulate.a = flick


# ================================================================ input

func _input(event: InputEvent) -> void:
	if phase == Phase.IDLE and not card_active:
		return
	if phase == Phase.DONE and not card_active:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := k.physical_keycode
		if code in [KEY_ESCAPE, KEY_K, KEY_X, KEY_BACKSPACE]:
			skip_keys = k.pressed
			get_viewport().set_input_as_handled()
			return
		if k.pressed and not k.echo and code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J, KEY_Z]:
			get_viewport().set_input_as_handled()
			_advance()
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_B or jb.button_index == JOY_BUTTON_START:
			skip_keys = jb.pressed
			get_viewport().set_input_as_handled()
		elif jb.pressed and jb.button_index == JOY_BUTTON_A:
			get_viewport().set_input_as_handled()
			_advance()
	elif event is InputEventScreenTouch:
		if not _use_touch:
			return
		var st := event as InputEventScreenTouch
		_pointer(st.pressed, st.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if _use_touch:
			return
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_pointer(mb.pressed, mb.position)
		get_viewport().set_input_as_handled()


func _pointer(pressed: bool, p: Vector2) -> void:
	var r := Rect2(skip_box.global_position, skip_box.size).grow(14.0)
	if pressed and skip_box.visible and r.has_point(p):
		skip_touch = true
		return
	if not pressed:
		skip_touch = false
		return
	_advance()


# ================================================================ audio

func _snd(n: String, db := 0.0, var_amt := 0.05) -> void:
	if audio == null:
		return
	var clips: Dictionary = audio.get("clips")
	if clips.has(n):
		audio.play(n, db, var_amt)


func _blip() -> void:
	if headless:
		return
	if _blip_stream == null:
		_blip_stream = _make_blip()
		for i in 3:
			var p := AudioStreamPlayer.new()
			p.stream = _blip_stream
			p.volume_db = -19.0
			add_child(p)
			_blip_players.append(p)
	var pl := _blip_players[_blip_i % _blip_players.size()]
	_blip_i += 1
	pl.pitch_scale = _blip_pitch * randf_range(0.94, 1.06)
	pl.play()


func _make_blip() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.045)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env_v := exp(-t * 70.0) * minf(1.0, t * 2000.0)
		var v := sin(TAU * 720.0 * t) * 0.7 + (1.0 if fmod(t * 1440.0, 1.0) < 0.5 else -1.0) * 0.12
		var s := int(clampf(v * env_v, -1.0, 1.0) * 26000.0)
		data.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _setup_music_bus() -> void:
	var idx := AudioServer.get_bus_index("CutsceneMusic")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "CutsceneMusic")
		AudioServer.set_bus_send(idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(idx, lp)
	var p: AudioStreamPlayer = music.get("_player")
	if p != null:
		p.bus = "CutsceneMusic"


## chill / hype / sad / tense: the menu beat re-pitched and filtered; "none" fades it out.
func _set_music(mood: String) -> void:
	if music == null or mood == music_mood:
		return
	music_mood = mood
	if mood == "none":
		music.fade_out(0.8)
		return
	var p: AudioStreamPlayer = music.get("_player")
	var pitch := 1.0
	var cutoff := 20000.0
	match mood:
		"chill":
			pitch = 0.93
			cutoff = 3200.0
		"hype":
			pitch = 1.08
		"sad":
			pitch = 0.8
			cutoff = 1100.0
		"tense":
			pitch = 0.88
			cutoff = 700.0
	if p != null:
		p.pitch_scale = pitch
	var idx := AudioServer.get_bus_index("CutsceneMusic")
	if idx >= 0 and AudioServer.get_bus_effect_count(idx) > 0:
		var lp: AudioEffectLowPassFilter = AudioServer.get_bus_effect(idx, 0)
		lp.cutoff_hz = cutoff
	music.start()


func _cash_pop(n: int) -> void:
	cash_label.text = "+$%d" % n
	cash_label.visible = true
	cash_label.modulate.a = 1.0
	cash_label.pivot_offset = cash_label.size * 0.5
	cash_label.scale = Vector2.ONE * 1.8
	var base_y := ui.size.y * 0.3
	cash_label.position.y = base_y
	var tw := create_tween()
	tw.tween_property(cash_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_property(cash_label, "position:y", base_y - 60.0, 0.6)
	tw.parallel().tween_property(cash_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): cash_label.visible = false)
	_snd("combo_bank", -3.0, 0.0)


# ================================================================ 3D view, world, lights

func _build_view() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	view = SubViewport.new()
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.handle_input_locally = false
	view.gui_disable_input = true
	view.physics_object_picking = false
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layer.add_child(view)
	view_rect = TextureRect.new()
	view_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = POST_SHADER
	post_mat.shader = sh
	view_rect.material = post_mat
	view_rect.texture = view.get_texture()
	layer.add_child(view_rect)
	world = Node3D.new()
	view.add_child(world)
	camera = Camera3D.new()
	camera.fov = 48.0
	camera.near = 0.05
	camera.far = 120.0
	view.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 1.5, 5.5)


func _update_view_size() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		win = get_viewport().get_visible_rect().size
	var h := win.y
	if h > 600.0:
		h = clampf(h * 0.6, 540.0, 720.0)
	var w := h * win.x / maxf(win.y, 1.0)
	view.size = Vector2i(maxi(16, roundi(w)), maxi(16, roundi(h)))


func _build_world() -> void:
	sky_mat = ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = SKY_SHADER
	sky_mat.shader = ssh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = false
	world.add_child(sun)
	key_light = SpotLight3D.new()
	key_light.spot_angle = 30.0
	key_light.spot_angle_attenuation = 0.9
	key_light.spot_range = 9.0
	world.add_child(key_light)
	rim_light = SpotLight3D.new()
	rim_light.spot_angle = 34.0
	rim_light.spot_range = 7.0
	world.add_child(rim_light)


func _apply_lighting(set_name: String, time: String) -> void:
	var p: Dictionary = TIMES[time]
	var info: Dictionary = sets[set_name]
	var interior: bool = info["interior"]
	var hor: Color = p["hor"]
	if set_name == "rooftop" and time == "night":
		hor = Color(0.42, 0.22, 0.14)   # city glow
	sky_mat.set_shader_parameter("top_col", p["top"])
	sky_mat.set_shader_parameter("hor_col", hor)
	sky_mat.set_shader_parameter("gnd_col", p["gnd"])
	sky_mat.set_shader_parameter("stars", p["stars"])
	var sd: Vector3 = p["sun_dir"]
	sky_mat.set_shader_parameter("sun_dir", sd)
	var sc: Color = p["sun_col"]
	sky_mat.set_shader_parameter("sun_col", sc * (0.0 if time == "night" else 1.0))
	sun.transform = Transform3D(Basis.looking_at(-sd.normalized()), Vector3(0, 10, 0))
	sun.light_color = sc
	sun.light_energy = float(p["sun_e"]) * (0.45 if interior else 1.0)
	var amb: Color = p["amb"]
	var amb_e: float = p["amb_e"]
	if interior:
		amb = amb.lerp(Color(1.0, 0.82, 0.62), 0.5)
		amb_e = maxf(amb_e, 0.42) * (1.15 if time == "day" else 1.0)
	env.ambient_light_color = amb
	env.ambient_light_energy = amb_e
	env.fog_light_color = p["fog"]
	env.fog_density = float(p["fog_d"]) * (0.3 if interior else 1.0)
	key_light.light_color = p["key_col"]
	key_light.light_energy = p["key_e"]
	rim_light.light_color = Color(1.0, 0.78, 0.5) if time != "day" else Color(1.0, 0.95, 0.85)
	rim_light.light_energy = 2.2 if time == "night" else 1.3
	var prac: float = p["practical"]
	if interior:
		prac = maxf(prac, 0.55)
	for e: Array in info["lights"]:
		var l: Light3D = e[0]
		l.light_energy = float(e[1]) * (prac if bool(e[2]) else 1.0)
		l.visible = l.light_energy > 0.02
	for e: Array in info["emis"]:
		var m: StandardMaterial3D = e[0]
		var mode := str(e[2])
		if mode == "window":
			var wc: Color = p["win"]
			m.albedo_color = wc
			m.emission = wc
			m.emission_energy_multiplier = float(p["win_e"]) * float(e[1])
		elif mode == "night":
			m.emission_energy_multiplier = float(e[1]) * (0.15 if time == "day" else (0.7 if time == "dusk" else 1.0))
		else:
			m.emission_energy_multiplier = float(e[1])
	if info.has("anim"):
		var an: Dictionary = info["anim"]
		an["pass_e"] = 1.0 if time != "day" else 0.0


# ================================================================ actors

func _spawn_actor(id: String) -> void:
	var a: Actor = Actor.new()
	world.add_child(a)
	a.cs_spawn(_display_name(id), _look_of(id))
	a.visible = false
	a.impact_cb = _on_impact
	actors[id] = a
	var ch := _make_chair()
	world.add_child(ch)
	ch.visible = false
	chairs[id] = ch


func _make_chair() -> Node3D:
	var root := Node3D.new()
	var wood := _mat(Color(0.42, 0.28, 0.17))
	var seat := _mesh_box(Vector3(0.46, 0.05, 0.44), Vector3(0, 0.45, -0.05), wood)
	root.add_child(seat)
	root.add_child(_mesh_box(Vector3(0.46, 0.5, 0.05), Vector3(0, 0.72, -0.26), wood))
	for sx in [-0.2, 0.2]:
		for sz in [-0.24, 0.14]:
			root.add_child(_mesh_box(Vector3(0.04, 0.45, 0.04), Vector3(sx, 0.225, sz), wood))
	return root


# ================================================================ set building helpers

func _mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


func _emis(c: Color, energy := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


func _tmat(tex: Texture2D, tint := Color.WHITE, uv := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.9
	m.uv1_scale = uv
	return m


func _mesh_box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _box(size: Vector3, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := _mesh_box(size, pos, m)
	mi.rotation.y = yaw
	_build.add_child(mi)
	return mi


func _quad(size: Vector2, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = yaw
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build.add_child(mi)
	return mi


func _floor(size: Vector2, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := _quad(size, pos, m)
	mi.rotation.x = -PI / 2
	return mi


func _cyl(r_top: float, r_bot: float, h: float, pos: Vector3, m: Material, segs := 14) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	mi.mesh = c
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build.add_child(mi)
	return mi


func _sphere(r: float, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	mi.mesh = s
	mi.position = pos
	mi.scale = scl
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build.add_child(mi)
	return mi


func _label(text: String, pos: Vector3, size: int, col: Color, outline := Color(0, 0, 0, 0), yaw := 0.0,
		px := 0.004, shaded := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font_i
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_modulate = outline
	l.outline_size = 8 if outline.a > 0.0 else 0
	l.position = pos
	l.rotation.y = yaw
	l.shaded = shaded
	l.double_sided = false
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build.add_child(l)
	return l


func _omni(pos: Vector3, col: Color, energy: float, rng: float, night_only := true) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = col
	o.light_energy = energy
	o.omni_range = rng
	o.omni_attenuation = 1.2
	_build.add_child(o)
	(_build_info["lights"] as Array).append([o, energy, night_only])
	return o


func _spot(pos: Vector3, at: Vector3, col: Color, energy: float, rng: float, angle: float, night_only := true) -> SpotLight3D:
	var s := SpotLight3D.new()
	s.transform = Transform3D(Basis.looking_at(at - pos), pos)
	s.light_color = col
	s.light_energy = energy
	s.spot_range = rng
	s.spot_angle = angle
	s.spot_angle_attenuation = 0.8
	_build.add_child(s)
	(_build_info["lights"] as Array).append([s, energy, night_only])
	return s


## Emissive material registered with the time-of-day pass ("window" = sky colour,
## "night" = brighter after dark, "fixed").
func _lit(c: Color, energy: float, mode := "night") -> StandardMaterial3D:
	var m := _emis(c, energy)
	(_build_info["emis"] as Array).append([m, energy, mode])
	return m


var _halo: ImageTexture = null


func _glow(pos: Vector3, size: float, col: Color) -> MeshInstance3D:
	if _halo == null:
		var n := 48
		var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.2)))
		img.generate_mipmaps()
		_halo = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _halo
	m.albedo_color = col
	return _quad(Vector2(size, size), pos, m)


# ---------------------------------------------------------------- procedural textures

func _noise_img(w: int, h: int, freq: float, octaves := 3, seed_v := 1) -> Image:
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = octaves
	return fn.get_seamless_image(w, h)


func _ctex(key: String, fn: Callable) -> ImageTexture:
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img: Image = fn.call()
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


## Generic grungy surface: base colour with noise mottling and darker grime.
func _grunge_img(base: Color, amt: float, n := 64, seed_v := 1) -> Image:
	var nz := _noise_img(n, n, 0.07, 3, seed_v)
	var fine := _noise_img(n, n, 0.45, 2, seed_v + 7)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := (nz.get_pixel(x, y).r - 0.5) * amt + (fine.get_pixel(x, y).r - 0.5) * amt * 0.6
			var c := base * (1.0 + v)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


func _tile_img() -> Image:
	# Kitchen linoleum: worn cream / brick-red checker with grout and scuffs.
	var n := 64
	var nz := _noise_img(n, n, 0.09, 2, 3)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var cx := int(x / 32.0)
			var cy := int(y / 32.0)
			var c := Color(0.82, 0.76, 0.62) if (cx + cy) % 2 == 0 else Color(0.55, 0.22, 0.16)
			var v := nz.get_pixel(x, y).r
			c *= 0.85 + 0.25 * v
			if x % 32 < 1 or y % 32 < 1:
				c *= 0.6
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


func _plank_img(base: Color, boards: int) -> Image:
	var n := 64
	var nz := _noise_img(n, n, 0.12, 2, 5)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var bw := float(n) / boards
	for y in n:
		for x in n:
			var bi := int(x / bw)
			var g := 0.8 + 0.08 * sin(y * 0.9 + nz.get_pixel(x, y).r * 8.0 + bi * 2.0) + (nz.get_pixel(x, y).r - 0.5) * 0.25 + 0.06 * sin(bi * 12.9)
			if fmod(x, bw) < 1.0:
				g *= 0.4
			var c := base * g
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


func _siding_img(base: Color) -> Image:
	var n := 64
	var nz := _noise_img(n, n, 0.08, 2, 9)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var row := fmod(y, 16.0)
			var g := 0.78 + 0.18 * (row / 16.0) + (nz.get_pixel(x, y).r - 0.5) * 0.14
			if row < 1.5:
				g *= 0.5
			var c := base * g
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


func _brick_img() -> Image:
	var n := 64
	var nz := _noise_img(n, n, 0.2, 2, 11)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var row := int(y / 8.0)
			var off := 8 if row % 2 == 1 else 0
			var bx := (x + off) % 16
			var by := y % 8
			var bid := row * 7 + int((x + off) / 16.0)
			var c := Color(0.55, 0.25, 0.17) * (0.8 + 0.25 * sin(bid * 4.7) * 0.5 + (nz.get_pixel(x, y).r - 0.5) * 0.4)
			if bx < 1 or by < 1:
				c = Color(0.5, 0.47, 0.42) * (0.8 + 0.2 * nz.get_pixel(x, y).r)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


func _grass_img() -> Image:
	var n := 96
	var clump := _noise_img(n, n, 0.05, 3, 13)
	var fine := _noise_img(n, n, 0.4, 2, 14)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c0 := clump.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var g := 0.5 + (c0 - 0.5) * 0.5 + (f - 0.5) * 0.45
			var dry := smoothstep(0.62, 0.8, c0)
			var col := Color(0.22, 0.36, 0.12).lerp(Color(0.42, 0.4, 0.2), dry) * (0.6 + g * 0.8)
			col.a = 1.0
			img.set_pixel(x, y, col)
	return img


func _asphalt_img() -> Image:
	var n := 96
	var nz := _noise_img(n, n, 0.05, 3, 17)
	var fine := _noise_img(n, n, 0.6, 1, 18)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := nz.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var g := 0.2 + (f - 0.5) * 0.12 + (v - 0.5) * 0.08
			var oil := smoothstep(0.7, 0.8, v) * 0.5
			var c := Color(g * 1.02, g, g * 0.97) * (1.0 - oil * 0.6)
			c.a = 1.0
			img.set_pixel(x, y, c)
	# a few cracks
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 5:
		var p := Vector2(rng.randf() * n, rng.randf() * n)
		var a := rng.randf() * TAU
		for s in 40:
			a += rng.randf_range(-0.4, 0.4)
			p += Vector2(cos(a), sin(a))
			img.set_pixel(int(fposmod(p.x, n)), int(fposmod(p.y, n)), Color(0.06, 0.06, 0.06))
	return img


func _city_img() -> Image:
	# Building facade: grid of windows, some lit warm, some cool, most dark.
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	img.fill(Color(0.0, 0.0, 0.0))
	for wy in 16:
		for wx in 16:
			var r := rng.randf()
			var c := Color(0.02, 0.02, 0.03)
			if r < 0.22:
				c = Color(1.0, 0.75, 0.42) * rng.randf_range(0.6, 1.0)
			elif r < 0.3:
				c = Color(0.6, 0.75, 1.0) * rng.randf_range(0.5, 0.9)
			for y in range(wy * 4 + 1, wy * 4 + 3):
				for x in range(wx * 4 + 1, wx * 4 + 3):
					img.set_pixel(x, y, c)
	return img


# ---------------------------------------------------------------- sets

func _build_set(set_name: String) -> void:
	_build = Node3D.new()
	_build.name = "Set_" + set_name
	world.add_child(_build)
	_build_info = {"root": _build, "interior": false, "anchors": {}, "lights": [], "emis": [], "anim": {},
		"wide_yaw": 0.1, "wide_dist": 5.4}
	match set_name:
		"kitchen":
			_set_kitchen()
		"bedroom":
			_set_bedroom()
		"street":
			_set_street()
		"store_lot":
			_set_store_lot()
		"porch":
			_set_porch()
		"car":
			_set_car()
		"rooftop":
			_set_rooftop()
		_:
			_set_backyard()
	sets[set_name] = _build_info


func _room_shell(floor_m: Material, wall_m: Material, w := 8.0, back := -2.6) -> void:
	_floor(Vector2(w + 1.0, 12.0), Vector3(0, 0, back + 6.0), floor_m)
	_quad(Vector2(w, 2.8), Vector3(0, 1.4, back), wall_m)
	_quad(Vector2(9.0, 2.8), Vector3(-w * 0.5, 1.4, back + 4.5), wall_m, PI / 2)
	_quad(Vector2(9.0, 2.8), Vector3(w * 0.5, 1.4, back + 4.5), wall_m, -PI / 2)
	var ceil_m := _mat(Color(0.5, 0.47, 0.42))
	var c := _quad(Vector2(w, 9.0), Vector3(0, 2.8, back + 4.5), ceil_m)
	c.rotation.x = PI / 2
	# baseboards
	var bb := _mat(Color(0.85, 0.82, 0.75))
	_box(Vector3(w, 0.1, 0.03), Vector3(0, 0.05, back + 0.015), bb)


func _window(pos: Vector3, size: Vector2, frame_c: Color, yaw := 0.0) -> void:
	var glass := _lit(Color(0.8, 0.9, 1.0), 1.0, "window")
	var g := _quad(size, pos, glass, yaw)
	g.position += Vector3(sin(yaw), 0, cos(yaw)) * 0.005
	var fm := _mat(frame_c)
	var b := Basis(Vector3.UP, yaw)
	var r := b * Vector3.RIGHT
	_box(Vector3(size.x + 0.12, 0.07, 0.08), pos + Vector3(0, size.y * 0.5, 0), fm, yaw)
	_box(Vector3(size.x + 0.2, 0.07, 0.16), pos - Vector3(0, size.y * 0.5, 0), fm, yaw)
	_box(Vector3(0.06, size.y, 0.08), pos + r * (size.x * 0.5), fm, yaw)
	_box(Vector3(0.06, size.y, 0.08), pos - r * (size.x * 0.5), fm, yaw)
	_box(Vector3(0.04, size.y, 0.05), pos, fm, yaw)
	_box(Vector3(size.x, 0.04, 0.05), pos, fm, yaw)


func _set_kitchen() -> void:
	_build_info["interior"] = true
	var floor_m := _tmat(_ctex("tile", _tile_img), Color.WHITE, Vector3(9, 12, 1))
	var wall_m := _tmat(_ctex("wall_y", _grunge_img.bind(Color(0.86, 0.76, 0.52), 0.18, 64, 2)), Color.WHITE, Vector3(3, 1, 1))
	_room_shell(floor_m, wall_m)
	var back := -2.6
	# fridge (left) with the bills
	var white := _mat(Color(0.88, 0.87, 0.82), 0.4)
	_box(Vector3(0.82, 1.8, 0.7), Vector3(-2.75, 0.9, back + 0.37), white)
	_box(Vector3(0.8, 0.015, 0.02), Vector3(-2.75, 1.22, back + 0.73), _mat(Color(0.5, 0.5, 0.48)))
	_box(Vector3(0.04, 0.4, 0.04), Vector3(-2.42, 1.45, back + 0.75), _mat(Color(0.7, 0.7, 0.7), 0.3))
	_box(Vector3(0.04, 0.3, 0.04), Vector3(-2.42, 0.85, back + 0.75), _mat(Color(0.7, 0.7, 0.7), 0.3))
	var paper := _mat(Color(0.95, 0.94, 0.88))
	var bills := [[Vector3(-2.95, 1.5, 0), 0.08, "PAST DUE", Color(0.85, 0.1, 0.08)],
		[Vector3(-2.68, 1.62, 0), -0.12, "FINAL\nNOTICE", Color(0.85, 0.1, 0.08)],
		[Vector3(-2.82, 1.0, 0), 0.05, "RENT\n$900", Color(0.1, 0.1, 0.1)],
		[Vector3(-2.55, 1.05, 0), -0.06, "A+\n" + StoryText.hero_short_name() + "\n(1998)", Color(0.15, 0.3, 0.8)]]
	for b: Array in bills:
		var bp: Vector3 = b[0]
		bp.z = back + 0.73
		var q := _quad(Vector2(0.2, 0.26), bp, paper)
		q.rotation.z = float(b[1])
		var lbl := _label(str(b[2]), bp + Vector3(0, 0.02, 0.006), 30, b[3], Color(0, 0, 0, 0), 0.0, 0.0022, true)
		lbl.rotation.z = float(b[1])
		_sphere(0.018, bp + Vector3(0, 0.12, 0.01), _mat(Color(0.9, 0.2, 0.2), 0.3))
	_build_info["anchors"]["insert"] = Vector3(-2.75, 1.32, back + 0.75)
	_build_info["anchors"]["insert_off"] = Vector3(0.45, 0.1, 0.95)
	# counters + upper cabinets
	var cab := _tmat(_ctex("plank_cab", _plank_img.bind(Color(0.55, 0.38, 0.24), 3)), Color.WHITE, Vector3(3, 1, 1))
	var top := _mat(Color(0.75, 0.72, 0.66), 0.5)
	_box(Vector3(3.3, 0.88, 0.62), Vector3(-0.5, 0.44, back + 0.32), cab)
	_box(Vector3(3.4, 0.05, 0.66), Vector3(-0.5, 0.905, back + 0.33), top)
	_box(Vector3(1.0, 0.7, 0.35), Vector3(-1.65, 1.95, back + 0.18), cab)
	_box(Vector3(1.0, 0.7, 0.35), Vector3(0.85, 1.95, back + 0.18), cab)
	# window over the sink
	_window(Vector3(-0.4, 1.6, back + 0.01), Vector2(1.2, 0.85), Color(0.9, 0.88, 0.82))
	_box(Vector3(0.6, 0.06, 0.4), Vector3(-0.4, 0.92, back + 0.32), _mat(Color(0.6, 0.62, 0.64), 0.3))
	# stove (right)
	var stove_m := _mat(Color(0.82, 0.8, 0.76), 0.45)
	_box(Vector3(0.78, 0.9, 0.66), Vector3(1.7, 0.45, back + 0.34), stove_m)
	_box(Vector3(0.6, 0.45, 0.02), Vector3(1.7, 0.42, back + 0.68), _mat(Color(0.12, 0.12, 0.12), 0.3))
	for bx in [-0.18, 0.18]:
		for bz in [-0.15, 0.15]:
			_cyl(0.09, 0.09, 0.02, Vector3(1.7 + bx, 0.91, back + 0.34 + bz), _mat(Color(0.1, 0.1, 0.1)))
	_cyl(0.13, 0.12, 0.18, Vector3(1.52, 1.0, back + 0.25), _mat(Color(0.35, 0.36, 0.4), 0.3))
	_box(Vector3(0.82, 0.12, 0.1), Vector3(1.7, 0.97, back + 0.05), stove_m)
	_box(Vector3(0.9, 0.12, 0.5), Vector3(1.7, 2.05, back + 0.25), _mat(Color(0.7, 0.7, 0.68), 0.4))
	# doorway to the right and a calendar
	_box(Vector3(0.95, 2.1, 0.04), Vector3(3.05, 1.05, back + 0.01), _mat(Color(0.12, 0.09, 0.07)))
	_quad(Vector2(0.4, 0.55), Vector3(2.35, 1.6, back + 0.01), paper)
	_label("FRIDAY\nRENT!!", Vector3(2.35, 1.55, back + 0.02), 34, Color(0.85, 0.1, 0.1), Color(0, 0, 0, 0), 0.0, 0.0024, true)
	# table + chairs + stuff
	var table_root := Node3D.new()
	_build.add_child(table_root)
	var tm := _tmat(_ctex("plank_tab", _plank_img.bind(Color(0.62, 0.45, 0.3), 4)))
	var tt := _mesh_box(Vector3(1.4, 0.05, 0.85), Vector3(0, 0.76, -0.95), tm)
	table_root.add_child(tt)
	for lx in [-0.62, 0.62]:
		for lz in [-0.35, 0.35]:
			table_root.add_child(_mesh_box(Vector3(0.05, 0.74, 0.05), Vector3(lx, 0.37, -0.95 + lz), _mat(Color(0.35, 0.24, 0.16))))
	var mug := _mesh_box(Vector3(0.08, 0.1, 0.08), Vector3(0.3, 0.84, -0.85), _mat(Color(0.9, 0.3, 0.2), 0.4))
	table_root.add_child(mug)
	var box_c := _mesh_box(Vector3(0.2, 0.3, 0.07), Vector3(-0.25, 0.94, -1.1), _mat(Color(0.95, 0.75, 0.15)))
	table_root.add_child(box_c)
	var bowl := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.14
	bm.height = 0.14
	bm.is_hemisphere = true
	bowl.mesh = bm
	bowl.rotation.x = PI
	bowl.position = Vector3(0.0, 0.92, -0.9)
	bowl.material_override = _mat(Color(0.3, 0.5, 0.7), 0.4)
	table_root.add_child(bowl)
	_build_info["anim"]["table_node"] = table_root
	_build_info["anchors"]["table"] = Vector3(0, 0, -0.95)
	var wood := _mat(Color(0.42, 0.28, 0.17))
	for side in [-1.0, 1.0]:
		_box(Vector3(0.44, 0.05, 0.42), Vector3(0.95 * side, 0.45, -1.15), wood)
		_box(Vector3(0.44, 0.55, 0.05), Vector3(0.95 * side, 0.74, -1.38), wood)
		for sx in [-0.19, 0.19]:
			for sz in [-0.18, 0.18]:
				_box(Vector3(0.04, 0.45, 0.04), Vector3(0.95 * side + sx, 0.225, -1.15 + sz), wood)
	# hanging lamp over the table
	_cyl(0.005, 0.005, 0.6, Vector3(0, 2.5, -0.95), _mat(Color(0.1, 0.1, 0.1)))
	_cyl(0.08, 0.28, 0.2, Vector3(0, 2.12, -0.95), _mat(Color(0.25, 0.42, 0.3), 0.5))
	_sphere(0.06, Vector3(0, 2.02, -0.95), _lit(Color(1.0, 0.85, 0.6), 2.5))
	_omni(Vector3(0, 1.95, -0.6), Color(1.0, 0.78, 0.52), 1.6, 6.0)
	_omni(Vector3(-0.4, 1.7, back + 0.6), Color(0.9, 0.95, 1.0), 0.7, 4.0, false)   # window bounce
	_build_info["wide_yaw"] = 0.08


func _set_bedroom() -> void:
	_build_info["interior"] = true
	var carpet := _tmat(_ctex("carpet", _grunge_img.bind(Color(0.32, 0.3, 0.36), 0.35, 64, 4)), Color.WHITE, Vector3(10, 12, 1))
	var wall_m := _tmat(_ctex("wall_b", _grunge_img.bind(Color(0.42, 0.5, 0.58), 0.2, 64, 6)), Color.WHITE, Vector3(3, 1, 1))
	_room_shell(carpet, wall_m)
	var back := -2.6
	# bed (left)
	_box(Vector3(1.15, 0.32, 2.05), Vector3(-2.65, 0.16, back + 1.05), _mat(Color(0.3, 0.2, 0.13)))
	_box(Vector3(1.1, 0.22, 1.98), Vector3(-2.65, 0.42, back + 1.05), _mat(Color(0.9, 0.88, 0.84)))
	var blanket := _box(Vector3(1.2, 0.12, 1.3), Vector3(-2.62, 0.56, back + 1.35), _mat(Color(0.65, 0.12, 0.12)))
	blanket.rotation = Vector3(0.05, 0.12, -0.06)
	_box(Vector3(0.6, 0.14, 0.35), Vector3(-2.75, 0.6, back + 0.28), _mat(Color(0.95, 0.95, 0.92)), 0.2)
	_box(Vector3(1.15, 0.9, 0.08), Vector3(-2.65, 0.55, back + 0.04), _mat(Color(0.28, 0.18, 0.12)))
	# posters (original text)
	var posters := [[Vector3(-1.2, 1.75, 0), Vector2(0.75, 1.0), Color(0.82, 0.12, 0.1), "BACKYARD\nKINGS\nVOL. 3", Color(1.0, 0.85, 0.2)],
		[Vector3(-0.15, 1.85, 0), Vector2(0.6, 0.8), Color(0.12, 0.22, 0.55), "SLAM\nCITY", Color(1, 1, 1)],
		[Vector3(1.0, 1.7, 0), Vector2(0.85, 0.62), Color(0.08, 0.08, 0.08), "FRIDGE\nDROP!", Color(1.0, 0.3, 0.15)],
		[Vector3(-2.0, 1.95, 0), Vector2(0.5, 0.36), Color(0.95, 0.8, 0.15), "C2C", Color(0.1, 0.1, 0.1)]]
	for p: Array in posters:
		var pp: Vector3 = p[0]
		pp.z = back + 0.01
		_quad(p[1], pp, _mat(p[2]))
		_label(str(p[3]), pp + Vector3(0, 0, 0.006), 56, p[4], Color(0, 0, 0, 0.8), 0.0, 0.0028, true)
	# trophy shelf
	_box(Vector3(1.1, 0.04, 0.22), Vector3(2.4, 1.55, back + 0.11), _mat(Color(0.45, 0.3, 0.18)))
	var gold := _mat(Color(0.95, 0.72, 0.2), 0.25)
	gold.metallic = 0.7
	for i in 4:
		var x := 2.0 + i * 0.27
		var hgt := 0.16 + 0.06 * (i % 2)
		_box(Vector3(0.08, 0.04, 0.08), Vector3(x, 1.59, back + 0.12), _mat(Color(0.2, 0.15, 0.1)))
		_cyl(0.035, 0.01, hgt, Vector3(x, 1.61 + hgt * 0.5, back + 0.12), gold, 8)
		_sphere(0.035, Vector3(x, 1.63 + hgt, back + 0.12), gold)
	# dresser + CRT TV (right)
	_box(Vector3(1.2, 0.8, 0.5), Vector3(2.5, 0.4, back + 0.6), _mat(Color(0.4, 0.27, 0.17)))
	_box(Vector3(0.72, 0.56, 0.5), Vector3(2.4, 1.08, back + 0.62), _mat(Color(0.12, 0.12, 0.13), 0.5))
	var scr := _emis(Color(0.3, 0.5, 0.8), 0.6)
	var s := _quad(Vector2(0.56, 0.42), Vector3(2.4, 1.09, back + 0.875), scr)
	s.rotation.y = 0.0
	_box(Vector3(0.32, 0.06, 0.24), Vector3(2.95, 0.83, back + 0.62), _mat(Color(0.2, 0.2, 0.22)))
	var tvl := OmniLight3D.new()
	tvl.position = Vector3(2.3, 1.1, back + 1.6)
	tvl.light_color = Color(0.5, 0.7, 1.0)
	tvl.omni_range = 4.0
	_build.add_child(tvl)
	_build_info["anim"]["tv_mat"] = scr
	_build_info["anim"]["tv_light"] = tvl
	_build_info["anchors"]["tv"] = Vector3(2.4, 1.09, back + 0.88)
	_build_info["anchors"]["insert"] = Vector3(2.4, 1.6, back + 0.15)
	_build_info["anchors"]["insert_off"] = Vector3(-0.3, 0.05, 1.0)
	# laundry mountains
	var cols := [Color(0.2, 0.3, 0.6), Color(0.85, 0.85, 0.82), Color(0.15, 0.15, 0.15), Color(0.6, 0.15, 0.15), Color(0.3, 0.5, 0.3)]
	var piles := [Vector3(1.4, 0, -1.4), Vector3(-1.4, 0, -2.1), Vector3(3.1, 0, 0.4), Vector3(-3.2, 0, 1.0)]
	var k := 0
	for pp2: Vector3 in piles:
		for j in 4:
			k += 1
			_sphere(0.22, pp2 + Vector3(sin(k * 2.1) * 0.18, 0.06 + j * 0.05, cos(k * 1.7) * 0.15), _mat(cols[k % cols.size()]),
				Vector3(1.2, 0.35, 1.0))
	# window + desk lamp
	_window(Vector3(-4.0 + 0.01, 1.6, -0.3), Vector2(1.0, 0.9), Color(0.85, 0.85, 0.82), PI / 2)
	_omni(Vector3(1.6, 2.3, 0.4), Color(1.0, 0.78, 0.52), 1.2, 6.5)
	_omni(Vector3(-3.4, 1.6, -0.3), Color(0.85, 0.92, 1.0), 0.6, 4.0, false)
	_build_info["wide_yaw"] = 0.0


func _set_backyard() -> void:
	var grass := _tmat(_ctex("grass", _grass_img), Color.WHITE, Vector3(24, 24, 1))
	_floor(Vector2(40, 40), Vector3(0, 0, 0), grass)
	var fence := _tmat(_ctex("fence", _plank_img.bind(Color(0.62, 0.5, 0.38), 7)), Color.WHITE, Vector3(14, 1, 1))
	_quad(Vector2(14, 1.9), Vector3(-1.0, 0.95, -3.6), fence)
	var fence2 := _tmat(_ctex("fence", _plank_img.bind(Color(0.62, 0.5, 0.38), 7)), Color(0.9, 0.9, 0.9), Vector3(10, 1, 1))
	_quad(Vector2(10, 1.9), Vector3(6.0, 0.95, 1.4), fence2, -PI / 2)
	var post_m := _mat(Color(0.3, 0.24, 0.18))
	for i in 8:
		_box(Vector3(0.12, 2.0, 0.12), Vector3(-8.0 + i * 2.0, 1.0, -3.52), post_m)
	_box(Vector3(14, 0.09, 0.05), Vector3(-1.0, 1.6, -3.55), post_m)
	var siding := _tmat(_ctex("siding_g", _siding_img.bind(Color(0.72, 0.76, 0.74))), Color.WHITE, Vector3(6, 6, 1))
	_quad(Vector2(7.0, 4.2), Vector3(-5.2, 2.1, -0.1), siding, PI / 2)
	_box(Vector3(0.1, 2.1, 1.0), Vector3(-5.15, 1.05, -1.4), _mat(Color(0.22, 0.17, 0.13)))
	var win := _quad(Vector2(0.9, 0.7), Vector3(-5.14, 1.7, 0.8), _lit(Color(0.85, 0.55, 0.28), 0.8), PI / 2)
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(0.16, 0.22, 0.16), Vector3(-5.06, 2.45, -2.1), _lit(Color(1.0, 0.85, 0.55), 3.0))
	_glow(Vector3(-4.95, 2.45, -2.1), 1.3, Color(1.0, 0.7, 0.4, 0.5))
	_omni(Vector3(-4.7, 2.4, -2.1), Color(1.0, 0.72, 0.42), 1.8, 6.5)
	# props: trash can, folded table, lawn chair, kiddie pool "ring"
	var can_m := _mat(Color(0.42, 0.44, 0.46), 0.45)
	can_m.metallic = 0.6
	_cyl(0.3, 0.26, 0.85, Vector3(2.6, 0.425, -2.9), can_m)
	var lid := _box(Vector3(0.66, 0.06, 0.66), Vector3(2.6, 0.88, -2.9), can_m)
	lid.rotation.z = 0.12
	var table := _box(Vector3(1.8, 0.75, 0.05), Vector3(-1.9, 0.9, -3.35), _mat(Color(0.45, 0.44, 0.42)))
	table.rotation.x = -0.25
	var chair_m := _mat(Color(0.2, 0.42, 0.55))
	_box(Vector3(0.55, 0.06, 0.5), Vector3(3.6, 0.42, -1.4), chair_m, 0.5)
	var bk := _box(Vector3(0.55, 0.6, 0.05), Vector3(3.72, 0.7, -1.62), chair_m, 0.5)
	bk.rotation.x = -0.25
	# string lights (one MultiMesh of bulbs)
	var strands := [[Vector3(-5.1, 3.4, -3.4), Vector3(4.6, 3.1, -3.3)], [Vector3(-5.1, 3.6, 1.5), Vector3(4.6, 3.1, -3.3)]]
	var cols := [Color(1.0, 0.75, 0.42), Color(0.85, 0.3, 0.2), Color(0.45, 0.7, 0.4), Color(0.45, 0.55, 0.95), Color(1.0, 0.55, 0.2)]
	var xf: Array[Transform3D] = []
	var bc: Array[Color] = []
	var wire_m := _mat(Color(0.04, 0.04, 0.04))
	for s: Array in strands:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var prev := a
		for k in range(1, 11):
			var u := float(k) / 10.0
			var p := a.lerp(b, u) - Vector3(0, 2.0 * u * (1.0 - u), 0)
			var mid := (prev + p) * 0.5
			var wire := _box(Vector3(0.02, 0.02, prev.distance_to(p)), mid, wire_m)
			wire.look_at_from_position(mid, p, Vector3.UP)
			prev = p
		var nb := int(a.distance_to(b) / 0.6)
		for k in nb:
			var u2 := (k + 0.5) / nb
			xf.append(Transform3D(Basis(), a.lerp(b, u2) - Vector3(0, 2.0 * u2 * (1.0 - u2) + 0.06, 0)))
			bc.append(cols[k % cols.size()])
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, bc[i] * 1.6)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	bm.vertex_color_is_srgb = true
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bm
	_build.add_child(mmi)
	_omni(Vector3(-1.0, 3.0, -2.4), Color(1.0, 0.78, 0.5), 0.7, 5.0)
	_omni(Vector3(1.6, 2.9, -1.0), Color(1.0, 0.78, 0.5), 0.6, 5.0)
	# floodlight on the back fence
	var fpos := Vector3(4.6, 3.6, -3.4)
	_spot(fpos, Vector3(0.0, 0.8, 0.0), Color(1.0, 0.9, 0.75), 3.6, 11.0, 38.0)
	_box(Vector3(0.1, 3.7, 0.1), Vector3(4.6, 1.85, -3.5), _mat(Color(0.1, 0.1, 0.11)))
	_box(Vector3(0.5, 0.34, 0.2), fpos + Vector3(0, 0, 0.05), _lit(Color(1.0, 0.94, 0.8), 3.0))
	_glow(fpos + Vector3(-0.2, -0.1, 0.3), 2.2, Color(1.0, 0.85, 0.6, 0.55))
	_build_info["anchors"]["insert"] = Vector3(2.6, 0.9, -2.9)
	_build_info["wide_yaw"] = 0.18


func _set_street() -> void:
	var asphalt := _tmat(_ctex("asphalt", _asphalt_img), Color.WHITE, Vector3(16, 6, 1))
	_floor(Vector2(40, 14), Vector3(0, -0.14, 8.2), asphalt)
	var concrete := _tmat(_ctex("concrete", _grunge_img.bind(Color(0.6, 0.58, 0.55), 0.3, 64, 8)), Color.WHITE, Vector3(20, 2, 1))
	_floor(Vector2(40, 2.6), Vector3(0, 0, -0.1), concrete)
	for i in 21:   # sidewalk joints
		_box(Vector3(0.02, 0.005, 2.6), Vector3(-20.0 + i * 2.0, 0.003, -0.1), _mat(Color(0.25, 0.24, 0.23)))
	_box(Vector3(40, 0.16, 0.18), Vector3(0, -0.06, 1.24), _mat(Color(0.66, 0.64, 0.6)))
	for i in 10:
		_box(Vector3(1.2, 0.005, 0.12), Vector3(-18.0 + i * 4.0, -0.135, 5.0), _mat(Color(0.85, 0.7, 0.2)))
	var grass := _tmat(_ctex("grass", _grass_img), Color.WHITE, Vector3(24, 6, 1))
	_floor(Vector2(40, 12), Vector3(0, -0.01, -7.4), grass)
	# houses
	var house_cols := [Color(0.72, 0.62, 0.48), Color(0.55, 0.62, 0.7), Color(0.75, 0.7, 0.62), Color(0.6, 0.5, 0.45)]
	var roof_m := _mat(Color(0.2, 0.17, 0.16))
	for i in 4:
		var hx := -10.5 + i * 7.0
		var hz := -8.0 - 0.8 * (i % 2)
		var sid := _tmat(_ctex("siding_%d" % i, _siding_img.bind(house_cols[i])), Color.WHITE, Vector3(6, 4, 1))
		_box(Vector3(5.6, 3.2, 4.0), Vector3(hx, 1.6, hz), sid)
		var roof := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(6.2, 1.5, 4.4)
		roof.mesh = pm
		roof.position = Vector3(hx, 3.95, hz)
		roof.material_override = roof_m
		_build.add_child(roof)
		for wx in [-1.6, 1.4]:
			_quad(Vector2(1.0, 0.9), Vector3(hx + wx, 1.7, hz + 2.01), _lit(Color(1.0, 0.72, 0.4), 1.2))
		_box(Vector3(0.9, 2.0, 0.05), Vector3(hx - 0.1, 1.0, hz + 2.02), _mat(Color(0.3, 0.16, 0.12)))
		# path to the door
		_floor(Vector2(0.9, 5.0), Vector3(hx - 0.1, 0.0, hz + 4.5), concrete)
	# trees
	var trunk := _mat(Color(0.25, 0.18, 0.12))
	var leaf := _mat(Color(0.18, 0.3, 0.14))
	for tx in [-5.5, 6.5]:
		_cyl(0.12, 0.16, 2.6, Vector3(tx, 1.3, -2.2), trunk)
		_sphere(1.3, Vector3(tx, 3.2, -2.2), leaf, Vector3(1.0, 0.85, 1.0))
	# streetlight
	var pole := _mat(Color(0.25, 0.26, 0.28), 0.5)
	_cyl(0.07, 0.09, 5.2, Vector3(2.8, 2.6, 0.9), pole)
	_box(Vector3(0.08, 0.08, 1.4), Vector3(2.8, 5.15, 0.3), pole)
	_box(Vector3(0.35, 0.12, 0.55), Vector3(2.8, 5.08, -0.35), _lit(Color(1.0, 0.75, 0.42), 3.0))
	_glow(Vector3(2.8, 4.95, -0.35), 2.0, Color(1.0, 0.7, 0.35, 0.6))
	_spot(Vector3(2.8, 5.0, -0.35), Vector3(1.6, 0.0, 0.2), Color(1.0, 0.72, 0.42), 4.5, 9.0, 45.0)
	# hydrant, mailbox, parked car
	var red := _mat(Color(0.75, 0.12, 0.08), 0.5)
	_cyl(0.1, 0.12, 0.6, Vector3(-2.4, 0.3, 0.9), red)
	_sphere(0.1, Vector3(-2.4, 0.62, 0.9), red)
	_cyl(0.03, 0.03, 1.1, Vector3(3.8, 0.55, -1.2), _mat(Color(0.2, 0.2, 0.2)))
	_box(Vector3(0.22, 0.25, 0.45), Vector3(3.8, 1.2, -1.2), _mat(Color(0.25, 0.35, 0.6), 0.4))
	var car_m := _mat(Color(0.45, 0.12, 0.1), 0.35)
	_box(Vector3(4.2, 0.65, 1.8), Vector3(-5.5, 0.32, 2.4), car_m)
	_box(Vector3(2.2, 0.55, 1.6), Vector3(-5.7, 0.9, 2.4), car_m)
	_box(Vector3(2.1, 0.45, 1.62), Vector3(-5.7, 0.92, 2.4), _lit(Color(0.12, 0.15, 0.2), 0.3, "fixed"))
	_build_info["anchors"]["insert"] = Vector3(-2.4, 0.5, 0.9)
	_build_info["wide_yaw"] = -0.12


func _set_store_lot() -> void:
	var asphalt := _tmat(_ctex("asphalt", _asphalt_img), Color.WHITE, Vector3(14, 10, 1))
	_floor(Vector2(30, 20), Vector3(0, 0, 4.0), asphalt)
	var line_m := _mat(Color(0.85, 0.85, 0.8))
	for i in 7:
		_box(Vector3(0.1, 0.005, 3.0), Vector3(-6.0 + i * 2.6, 0.004, 1.2), line_m)
	_box(Vector3(14, 0.15, 1.4), Vector3(0, 0.075, -2.75), _mat(Color(0.62, 0.6, 0.56)))   # store sidewalk
	# store building
	var back := -3.5
	var brick := _tmat(_ctex("brick", _brick_img), Color.WHITE, Vector3(10, 3, 1))
	_quad(Vector2(5.0, 4.4), Vector3(-5.0, 2.2, back), brick)
	_quad(Vector2(3.6, 4.4), Vector3(5.8, 2.2, back), brick)
	_quad(Vector2(16.0, 1.4), Vector3(0, 3.7, back + 0.001), brick)
	var interior := _lit(Color(0.75, 0.85, 0.9), 0.45, "fixed")
	_quad(Vector2(5.4, 3.0), Vector3(0.0, 1.5, back - 0.6), interior)
	for i in 4:   # shelves silhouettes
		_box(Vector3(1.2, 1.5, 0.3), Vector3(-1.9 + i * 1.3, 0.75, back - 0.4), _mat(Color(0.2, 0.22, 0.25)))
		for j in 3:
			_box(Vector3(1.1, 0.12, 0.05), Vector3(-1.9 + i * 1.3, 0.4 + j * 0.42, back - 0.24),
				_mat(Color.from_hsv(fmod(i * 0.21 + j * 0.37, 1.0), 0.6, 0.8)))
	var frame := _mat(Color(0.15, 0.15, 0.16), 0.4)
	_box(Vector3(5.6, 0.12, 0.12), Vector3(-0.1, 3.0, back), frame)
	_box(Vector3(5.6, 0.4, 0.14), Vector3(-0.1, 0.2, back), frame)
	for fx in [-2.55, -0.9, 0.9, 2.55]:
		_box(Vector3(0.08, 2.9, 0.1), Vector3(fx, 1.5, back), frame)
	_box(Vector3(1.8, 0.12, 0.12), Vector3(3.95, 2.5, back), frame)
	_box(Vector3(0.08, 2.5, 0.1), Vector3(3.1, 1.25, back), frame)
	_box(Vector3(0.08, 2.5, 0.1), Vector3(4.8, 1.25, back), frame)
	_quad(Vector2(1.6, 2.4), Vector3(3.95, 1.2, back - 0.05), interior)
	# awning + neon
	_box(Vector3(9.0, 0.12, 1.1), Vector3(0.4, 3.15, back + 0.55), _mat(Color(0.12, 0.3, 0.22)))
	var neon := _label("CORNER MART", Vector3(0.0, 3.75, back + 0.08), 160, Color(1.0, 0.35, 0.65), Color(0.6, 0.0, 0.25, 0.9), 0.0, 0.005)
	neon.outline_size = 22
	_build_info["anim"]["neon"] = neon
	_glow(Vector3(0.0, 3.75, back + 0.3), 4.5, Color(1.0, 0.3, 0.6, 0.35))
	_label("OPEN 24 HRS", Vector3(-1.75, 2.45, back + 0.02), 60, Color(0.3, 1.0, 0.9), Color(0.0, 0.4, 0.4, 0.9), 0.0, 0.004)
	_label("ICE COLD\nSLUSHIES", Vector3(1.75, 2.35, back + 0.02), 44, Color(1.0, 0.85, 0.2), Color(0.4, 0.2, 0.0, 0.9), 0.0, 0.004)
	_omni(Vector3(0.0, 2.9, back + 1.0), Color(0.85, 0.95, 1.0), 2.2, 7.0)
	_omni(Vector3(0.0, 3.7, back + 0.9), Color(1.0, 0.35, 0.6), 1.2, 6.0)
	# dumpster + ice chest + pole light
	var green := _mat(Color(0.15, 0.32, 0.2), 0.6)
	_box(Vector3(2.0, 1.2, 1.1), Vector3(5.0, 0.6, -2.2), green)
	var lid := _box(Vector3(2.05, 0.08, 1.15), Vector3(5.0, 1.24, -2.2), _mat(Color(0.1, 0.1, 0.1)))
	lid.rotation.x = -0.1
	_box(Vector3(1.0, 1.1, 0.7), Vector3(-3.4, 0.7, -2.85), _mat(Color(0.85, 0.88, 0.92), 0.4))
	_label("ICE", Vector3(-3.4, 0.95, -2.49), 80, Color(0.2, 0.45, 0.9), Color(0, 0, 0, 0), 0.0, 0.004, true)
	var pole := _mat(Color(0.25, 0.26, 0.28), 0.5)
	_cyl(0.08, 0.1, 6.0, Vector3(-4.8, 3.0, 2.5), pole)
	_box(Vector3(0.6, 0.15, 0.4), Vector3(-4.8, 6.0, 2.3), _lit(Color(1.0, 0.85, 0.6), 3.0))
	_glow(Vector3(-4.8, 5.9, 2.3), 2.2, Color(1.0, 0.8, 0.5, 0.5))
	_spot(Vector3(-4.8, 5.9, 2.3), Vector3(-1.5, 0.0, 0.5), Color(1.0, 0.82, 0.55), 5.0, 12.0, 45.0)
	_build_info["anchors"]["insert"] = Vector3(0.0, 3.75, back + 0.1)
	_build_info["anchors"]["insert_off"] = Vector3(0.6, -0.6, 3.2)
	_build_info["wide_yaw"] = 0.15
	_build_info["wide_dist"] = 5.8


func _set_porch() -> void:
	var back := -2.0
	var deck := _tmat(_ctex("plank_deck", _plank_img.bind(Color(0.55, 0.44, 0.33), 6)), Color.WHITE, Vector3(1, 6, 1))
	var d := _floor(Vector2(7.6, 3.4), Vector3(0, 0, back + 1.7), deck)
	d.rotation.y = 0.0
	_box(Vector3(7.6, 0.6, 0.1), Vector3(0, -0.3, back + 3.4), _mat(Color(0.4, 0.32, 0.25)))
	for i in 3:   # steps down to the yard
		_box(Vector3(1.6, 0.2, 0.32), Vector3(0, -0.1 - 0.2 * i, back + 3.55 + 0.32 * i), deck)
	var grass := _tmat(_ctex("grass", _grass_img), Color.WHITE, Vector3(20, 10, 1))
	_floor(Vector2(30, 16), Vector3(0, -0.62, back + 11.0), grass)
	var siding := _tmat(_ctex("siding_p", _siding_img.bind(Color(0.82, 0.78, 0.68))), Color.WHITE, Vector3(8, 4, 1))
	_quad(Vector2(12.0, 3.4), Vector3(0, 1.7, back), siding)
	# door + frame + knob + porch light
	_box(Vector3(1.05, 2.15, 0.06), Vector3(0, 1.075, back + 0.03), _mat(Color(0.45, 0.14, 0.1), 0.5))
	_box(Vector3(1.25, 0.1, 0.1), Vector3(0, 2.2, back + 0.05), _mat(Color(0.9, 0.88, 0.82)))
	_box(Vector3(0.1, 2.2, 0.1), Vector3(-0.6, 1.1, back + 0.05), _mat(Color(0.9, 0.88, 0.82)))
	_box(Vector3(0.1, 2.2, 0.1), Vector3(0.6, 1.1, back + 0.05), _mat(Color(0.9, 0.88, 0.82)))
	var brass := _mat(Color(0.85, 0.65, 0.25), 0.3)
	brass.metallic = 0.7
	_sphere(0.035, Vector3(0.38, 1.0, back + 0.08), brass)
	_box(Vector3(0.18, 0.28, 0.14), Vector3(0.85, 2.0, back + 0.08), _lit(Color(1.0, 0.85, 0.5), 3.0))
	_glow(Vector3(0.85, 2.0, back + 0.25), 1.4, Color(1.0, 0.75, 0.4, 0.6))
	_omni(Vector3(0.85, 2.0, back + 0.5), Color(1.0, 0.75, 0.45), 2.0, 6.5)
	_window(Vector3(-2.3, 1.5, back + 0.01), Vector2(1.2, 1.0), Color(0.9, 0.88, 0.82))
	_quad(Vector2(1.18, 0.98), Vector3(-2.3, 1.5, back + 0.008), _lit(Color(1.0, 0.7, 0.4), 0.9))
	_window(Vector3(2.4, 1.5, back + 0.01), Vector2(1.2, 1.0), Color(0.9, 0.88, 0.82))
	_quad(Vector2(1.18, 0.98), Vector3(2.4, 1.5, back + 0.008), _lit(Color(1.0, 0.7, 0.4), 0.6))
	_box(Vector3(0.9, 0.02, 0.55), Vector3(0, 0.01, back + 0.45), _mat(Color(0.4, 0.28, 0.16)))
	# roof overhang, posts, railings
	var white := _mat(Color(0.88, 0.86, 0.8))
	_box(Vector3(7.8, 0.15, 3.6), Vector3(0, 2.9, back + 1.7), _mat(Color(0.3, 0.27, 0.25)))
	for px in [-3.7, -0.95, 0.95, 3.7]:
		_box(Vector3(0.14, 2.85, 0.14), Vector3(px, 1.43, back + 3.3), white)
	for seg: Array in [[-3.7, -0.95], [0.95, 3.7]]:
		var x0: float = seg[0]
		var x1: float = seg[1]
		_box(Vector3(x1 - x0, 0.07, 0.08), Vector3((x0 + x1) * 0.5, 0.9, back + 3.3), white)
		var n := int((x1 - x0) / 0.18)
		for i in n:
			_box(Vector3(0.04, 0.85, 0.04), Vector3(x0 + (i + 0.5) * (x1 - x0) / n, 0.45, back + 3.3), white)
	for sx in [-3.7, 3.7]:
		_box(Vector3(0.08, 0.07, 3.3), Vector3(sx, 0.9, back + 1.65), white)
	# chair + plant
	var chair_m := _mat(Color(0.25, 0.3, 0.22))
	_box(Vector3(0.6, 0.08, 0.55), Vector3(-2.8, 0.45, back + 0.6), chair_m, 0.3)
	_box(Vector3(0.6, 0.7, 0.08), Vector3(-2.88, 0.8, back + 0.35), chair_m, 0.3)
	_cyl(0.2, 0.15, 0.35, Vector3(1.6, 0.175, back + 0.4), _mat(Color(0.6, 0.3, 0.18)))
	_sphere(0.3, Vector3(1.6, 0.55, back + 0.4), _mat(Color(0.2, 0.4, 0.16)), Vector3(1.0, 0.8, 1.0))
	_build_info["anchors"]["door"] = Vector3(0, 0, back + 0.1)
	_build_info["anchors"]["insert"] = Vector3(0.38, 1.0, back + 0.1)
	_build_info["anchors"]["insert_off"] = Vector3(0.35, 0.15, 0.9)
	_build_info["wide_yaw"] = 0.1
	_build_info["wide_dist"] = 5.0


func _set_car() -> void:
	_build_info["interior"] = true
	# outside: dark road rushing by (just a floor far below) and window "glass"
	var seat_m := _tmat(_ctex("seat", _grunge_img.bind(Color(0.25, 0.2, 0.18), 0.35, 64, 23)))
	var dark := _mat(Color(0.09, 0.085, 0.09), 0.7)
	_floor(Vector2(4, 4), Vector3(0, 0.2, 0), _mat(Color(0.12, 0.11, 0.1)))
	for sx in [-0.4, 0.4]:
		for sz in [0.0, -0.95]:
			_box(Vector3(0.56, 0.16, 0.55), Vector3(sx, 0.42, sz - 0.05), seat_m)
			var back := _box(Vector3(0.56, 0.78, 0.14), Vector3(sx, 0.86, sz - 0.36), seat_m)
			back.rotation.x = -0.12
			_box(Vector3(0.28, 0.2, 0.12), Vector3(sx, 1.38, sz - 0.42), seat_m)
	# dashboard + gauges + wheel
	_box(Vector3(1.9, 0.28, 0.5), Vector3(0, 0.82, 0.78), dark)
	var glow_c := _lit(Color(0.2, 0.85, 0.8), 2.2, "fixed")
	for gx in [-0.5, -0.3]:
		_quad(Vector2(0.14, 0.1), Vector3(gx, 0.98, 0.56), glow_c, PI)
	_quad(Vector2(0.24, 0.07), Vector3(0.05, 0.9, 0.52), _lit(Color(1.0, 0.55, 0.15), 2.0, "fixed"), PI)
	var wheel := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.15
	tm.outer_radius = 0.19
	tm.rings = 16
	tm.ring_segments = 6
	wheel.mesh = tm
	wheel.position = Vector3(-0.4, 1.02, 0.42)
	wheel.rotation.x = PI / 2 - 0.45
	wheel.material_override = _mat(Color(0.05, 0.05, 0.05))
	_build.add_child(wheel)
	var dash_l := OmniLight3D.new()
	dash_l.position = Vector3(0, 0.95, 0.5)
	dash_l.light_color = Color(0.3, 0.9, 0.85)
	dash_l.light_energy = 0.8
	dash_l.omni_range = 1.6
	_build.add_child(dash_l)
	# roof, pillars, doors, windows
	_box(Vector3(1.9, 0.08, 2.6), Vector3(0, 1.72, -0.4), _mat(Color(0.3, 0.28, 0.26)))
	for sx2 in [-0.92, 0.92]:
		var pil := _box(Vector3(0.08, 0.85, 0.1), Vector3(sx2, 1.3, 0.85), dark)
		pil.rotation.x = -0.5
		_box(Vector3(0.06, 0.62, 2.4), Vector3(sx2 * 1.03, 0.65, -0.4), dark)
		var glass := _lit(Color(0.12, 0.15, 0.28), 1.0, "window")
		_quad(Vector2(2.2, 0.62), Vector3(sx2 * 1.04, 1.32, -0.4), glass, -signf(sx2) * PI / 2)
		_box(Vector3(0.08, 0.7, 0.08), Vector3(sx2, 1.32, -0.55), dark)
	var rear := _lit(Color(0.15, 0.18, 0.3), 1.0, "window")
	_quad(Vector2(1.7, 0.5), Vector3(0, 1.38, -1.65), rear)
	_box(Vector3(1.9, 0.9, 0.08), Vector3(0, 0.6, -1.7), dark)
	var mirror := _box(Vector3(0.24, 0.07, 0.03), Vector3(0, 1.6, 0.7), _mat(Color(0.5, 0.55, 0.6), 0.2))
	mirror.rotation.x = 0.2
	# little air freshener (original)
	_box(Vector3(0.06, 0.09, 0.005), Vector3(0.02, 1.47, 0.7), _mat(Color(0.95, 0.8, 0.1)))
	var pl := OmniLight3D.new()
	pl.light_color = Color(1.0, 0.7, 0.38)
	pl.omni_range = 3.5
	_build.add_child(pl)
	_build_info["anim"]["pass_light"] = pl
	_build_info["anim"]["pass_e"] = 1.0
	_omni(Vector3(0, 1.6, -0.2), Color(1.0, 0.8, 0.6), 0.35, 2.5, false)
	_build_info["anchors"]["insert"] = Vector3(-0.4, 0.98, 0.56)


func _set_rooftop() -> void:
	var gravel := _tmat(_ctex("gravel", _grunge_img.bind(Color(0.42, 0.4, 0.38), 0.6, 64, 31)), Color.WHITE, Vector3(16, 16, 1))
	_floor(Vector2(16, 14), Vector3(0, 0, 3.0), gravel)
	var concrete := _tmat(_ctex("concrete", _grunge_img.bind(Color(0.6, 0.58, 0.55), 0.3, 64, 8)), Color.WHITE, Vector3(8, 1, 1))
	_box(Vector3(16, 0.95, 0.3), Vector3(0, 0.475, -2.4), concrete)
	_box(Vector3(16.2, 0.08, 0.42), Vector3(0, 0.99, -2.4), _mat(Color(0.5, 0.48, 0.45)))
	_box(Vector3(0.3, 0.95, 8), Vector3(-6.0, 0.475, 1.6), concrete)
	# skyline
	var city := _ctex("city", _city_img)
	var city_m := StandardMaterial3D.new()
	city_m.albedo_color = Color(0.06, 0.065, 0.09)
	city_m.emission_enabled = true
	city_m.emission_texture = city
	city_m.emission = Color(1, 1, 1)
	city_m.emission_energy_multiplier = 0.7
	city_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	city_m.uv1_scale = Vector3(3, 5, 1)
	city_m.uv1_triplanar = true
	city_m.uv1_world_triplanar = true
	city_m.uv1_scale = Vector3(0.06, 0.06, 0.06)
	(_build_info["emis"] as Array).append([city_m, 0.7, "night"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 18:
		var w := rng.randf_range(4.0, 9.0)
		var h := rng.randf_range(8.0, 30.0)
		var x := -60.0 + i * 7.0 + rng.randf_range(-2, 2)
		var z := -35.0 - rng.randf_range(0.0, 25.0)
		var b := _box(Vector3(w, h, w), Vector3(x, h * 0.5 - 12.0, z), city_m)
		b.scale = Vector3.ONE
	var blink := _lit(Color(1.0, 0.1, 0.1), 3.0, "fixed")
	_build_info["anim"]["blink"] = blink
	_cyl(0.03, 0.05, 4.0, Vector3(4.6, 2.0, -1.6), _mat(Color(0.3, 0.3, 0.3)))
	_sphere(0.07, Vector3(4.6, 4.05, -1.6), blink)
	# AC unit, vents, water tower, bare bulb
	var metal := _mat(Color(0.6, 0.62, 0.64), 0.4)
	metal.metallic = 0.5
	_box(Vector3(1.4, 0.9, 1.0), Vector3(3.2, 0.45, -0.9), metal)
	_cyl(0.38, 0.38, 0.05, Vector3(3.2, 0.92, -0.9), _mat(Color(0.15, 0.15, 0.15)))
	_cyl(0.12, 0.12, 1.4, Vector3(-3.2, 0.7, -1.4), metal)
	_cyl(0.17, 0.12, 0.2, Vector3(-3.2, 1.45, -1.4), metal)
	var wood := _mat(Color(0.35, 0.24, 0.16))
	_cyl(1.0, 1.0, 1.6, Vector3(-5.0, 3.4, -4.0), wood)
	var cone := _cyl(0.05, 1.1, 0.7, Vector3(-5.0, 4.55, -4.0), _mat(Color(0.2, 0.18, 0.16)))
	cone.scale = Vector3.ONE
	for lx in [-0.7, 0.7]:
		for lz in [-0.7, 0.7]:
			_box(Vector3(0.08, 2.6, 0.08), Vector3(-5.0 + lx, 1.3, -4.0 + lz), wood)
	_cyl(0.005, 0.005, 1.0, Vector3(-1.5, 2.6, -1.0), _mat(Color(0.05, 0.05, 0.05)))
	_sphere(0.06, Vector3(-1.5, 2.08, -1.0), _lit(Color(1.0, 0.85, 0.55), 3.0))
	_glow(Vector3(-1.5, 2.08, -1.0), 1.2, Color(1.0, 0.75, 0.4, 0.6))
	_omni(Vector3(-1.5, 2.0, -0.8), Color(1.0, 0.75, 0.45), 1.6, 6.0)
	_omni(Vector3(0.0, 1.0, -6.0), Color(1.0, 0.55, 0.3), 1.0, 8.0)   # city glow from below
	_build_info["anchors"]["insert"] = Vector3(0.0, 2.0, -20.0)
	_build_info["anchors"]["insert_off"] = Vector3(0.0, 0.0, 22.0)
	_build_info["wide_yaw"] = -0.15


# ================================================================ UI

func _style(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _lbl(font: Font, size: int, col: Color, outline := 0) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 19
	add_child(ui_layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.02, 0.015, 0.02, 1.0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(fade_rect)

	bar_top = ColorRect.new()
	bar_top.color = Color(0, 0, 0)
	bar_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar_top)
	bar_bot = ColorRect.new()
	bar_bot.color = Color(0, 0, 0)
	bar_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar_bot)

	loading_label = _lbl(font_i, 28, Color(0.95, 0.85, 0.55), 6)
	loading_label.text = "LOADING..."
	ui.add_child(loading_label)

	# dialogue box: portrait card + typewriter text, name plate on top
	box = PanelContainer.new()
	box_style = _style(Color(0.04, 0.035, 0.03, 0.86), Color(0.8, 0.2, 0.1), 0, 4)
	box_style.border_width_left = 6
	box_style.border_width_top = 2
	box_style.content_margin_left = 16
	box_style.content_margin_top = 16
	box_style.shadow_color = Color(0, 0, 0, 0.5)
	box_style.shadow_size = 8
	box.add_theme_stylebox_override("panel", box_style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(box)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hb)
	portrait = PanelContainer.new()
	portrait_style = _style(Color(0.5, 0.1, 0.1), Color(1, 1, 1), 3, 4)
	portrait.add_theme_stylebox_override("panel", portrait_style)
	portrait.custom_minimum_size = Vector2(92, 92)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(portrait)
	portrait_label = _lbl(font_i, 40, Color(1, 1, 1), 8)
	portrait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_child(portrait_label)
	text_label = _lbl(font_b, 28, Color(0.97, 0.95, 0.9), 4)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hb.add_child(text_label)
	name_plate = PanelContainer.new()
	name_style = _style(Color(0.8, 0.2, 0.1), Color(0, 0, 0, 0), 0, 3)
	name_style.content_margin_top = 4
	name_style.content_margin_bottom = 4
	name_style.content_margin_left = 18
	name_style.content_margin_right = 22
	name_style.skew = Vector2(0.25, 0.0)
	name_plate.add_theme_stylebox_override("panel", name_style)
	name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(name_plate)
	name_label = _lbl(font_i, 26, Color(1, 1, 1), 0)
	name_plate.add_child(name_label)
	next_arrow = _lbl(font_b, 26, Color(1.0, 0.85, 0.3), 5)
	next_arrow.text = "v"
	ui.add_child(next_arrow)

	# narrator caption (top-left, under the bar)
	caption = PanelContainer.new()
	var cst := _style(Color(0.95, 0.82, 0.35, 0.94), Color(0.1, 0.07, 0.03), 3, 2)
	caption.add_theme_stylebox_override("panel", cst)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(caption)
	caption_label = _lbl(font_i, 26, Color(0.1, 0.07, 0.04), 0)
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_child(caption_label)

	# text message bubble
	phone = PanelContainer.new()
	var pst := _style(Color(0.08, 0.09, 0.1, 0.94), Color(0.35, 0.95, 0.5), 3, 18)
	pst.content_margin_left = 18
	pst.content_margin_right = 18
	phone.add_theme_stylebox_override("panel", pst)
	phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(phone)
	var pv := VBoxContainer.new()
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone.add_child(pv)
	phone_head = _lbl(font_i, 20, Color(0.35, 0.95, 0.5), 0)
	pv.add_child(phone_head)
	var bubble := PanelContainer.new()
	var bst := _style(Color(0.3, 0.85, 0.45), Color(0, 0, 0, 0), 0, 16)
	bubble.add_theme_stylebox_override("panel", bst)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pv.add_child(bubble)
	phone_label = _lbl(font_b, 26, Color(0.03, 0.08, 0.04), 0)
	phone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(phone_label)

	# cash pop
	cash_label = _lbl(font_i, 84, Color(0.45, 1.0, 0.4), 14)
	cash_label.visible = false
	ui.add_child(cash_label)

	# skip (hold)
	skip_box = PanelContainer.new()
	var sk := _style(Color(0.1, 0.1, 0.1, 0.7), Color(0.9, 0.9, 0.9, 0.6), 2, 4)
	sk.content_margin_top = 4
	sk.content_margin_bottom = 4
	skip_box.add_theme_stylebox_override("panel", sk)
	skip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skip_box.clip_contents = true
	skip_fill = ColorRect.new()
	skip_fill.color = Color(1.0, 0.75, 0.2, 0.6)
	skip_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(skip_fill)
	ui.add_child(skip_box)
	skip_label = _lbl(font_i, 20, Color(1, 1, 1), 4)
	skip_label.text = "HOLD TO SKIP  >>"
	skip_box.add_child(skip_label)

	# chapter title card
	card = Control.new()
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	ui.add_child(card)
	card_bg = ColorRect.new()
	card_bg.color = Color(0.05, 0.03, 0.03, 0.97)
	card_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(card_bg)
	card_title = _lbl(font_i, 34, Color(1.0, 0.82, 0.12), 6)
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(card_title)
	card_name = _lbl(font_i, 92, Color(0.95, 0.25, 0.12), 18)
	card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(card_name)
	card_teaser = _lbl(font_i, 30, Color(0.95, 0.92, 0.85), 4)
	card_teaser.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(card_teaser)
	card_hint = _lbl(font_b, 22, Color(0.8, 0.78, 0.7), 4)
	card_hint.text = "TAP / PRESS A TO CONTINUE"
	card_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(card_hint)

	box.visible = false
	caption.visible = false
	phone.visible = false
	next_arrow.visible = false
	skip_box.visible = false
	name_plate.visible = false


func _relayout() -> void:
	if ui == null:
		return
	_update_view_size()
	var vs := get_viewport().get_visible_rect().size
	var s := clampf(minf(vs.x / 1280.0, vs.y / 720.0), 0.75, 1.5)
	ui_scale = s
	var m := 16.0 * s + 8.0
	var bar_h := roundf(vs.y * 0.1)
	bar_top.position = Vector2.ZERO
	bar_top.size = Vector2(vs.x, bar_h)
	bar_bot.position = Vector2(0, vs.y - bar_h)
	bar_bot.size = Vector2(vs.x, bar_h)
	# dialogue box across the bottom (overlapping the lower bar)
	var bw := minf(vs.x - 2.0 * m, 1040.0 * s)
	var fs := int(28 * s)
	text_label.add_theme_font_size_override("font_size", fs)
	name_label.add_theme_font_size_override("font_size", int(26 * s))
	portrait.custom_minimum_size = Vector2(92, 92) * s
	portrait_label.add_theme_font_size_override("font_size", int(40 * s))
	var bh := 150.0 * s
	box.size = Vector2(bw, bh)
	box.custom_minimum_size = Vector2(bw, bh)
	box.position = Vector2((vs.x - bw) * 0.5, vs.y - bh - m * 0.6)
	name_plate.position = box.position + Vector2(-4.0, -38.0 * s)
	name_plate.size = Vector2.ZERO
	next_arrow.add_theme_font_size_override("font_size", int(26 * s))
	next_arrow.position = box.position + Vector2(bw - 34.0 * s, bh - 40.0 * s)
	# caption top-left
	caption_label.add_theme_font_size_override("font_size", int(26 * s))
	caption.custom_minimum_size = Vector2(minf(vs.x - 2.0 * m, 720.0 * s), 0)
	caption.size = Vector2(minf(vs.x - 2.0 * m, 720.0 * s), 0)
	caption.position = Vector2(m, bar_h + m * 0.5)
	# phone bubble right side
	phone_label.add_theme_font_size_override("font_size", int(26 * s))
	phone_head.add_theme_font_size_override("font_size", int(20 * s))
	var pw := minf(vs.x - 2.0 * m, 520.0 * s)
	phone.custom_minimum_size = Vector2(pw, 0)
	phone.size = Vector2(pw, 0)
	phone.position = Vector2(vs.x - pw - m, bar_h + m)
	# cash
	cash_label.add_theme_font_size_override("font_size", int(84 * s))
	cash_label.position = Vector2(vs.x * 0.62, vs.y * 0.3)
	# skip in the top bar (right) - big enough for a thumb
	skip_label.add_theme_font_size_override("font_size", int(20 * s))
	skip_box.size = Vector2(0, 0)
	skip_box.custom_minimum_size = Vector2(190 * s, maxf(bar_h - 16.0, 34.0))
	skip_box.position = Vector2(vs.x - 190 * s - m, maxf(8.0, (bar_h - maxf(bar_h - 16.0, 34.0)) * 0.5))
	loading_label.add_theme_font_size_override("font_size", int(28 * s))
	loading_label.position = Vector2(vs.x - 220.0 * s, vs.y - bar_h - 60.0 * s)
	# card
	var cw := minf(vs.x - 2.0 * m, 1100.0 * s)
	card_title.add_theme_font_size_override("font_size", int(34 * s))
	card_name.add_theme_font_size_override("font_size", int(92 * s * clampf(vs.x / 1280.0, 0.6, 1.0)))
	card_teaser.add_theme_font_size_override("font_size", int(30 * s))
	card_hint.add_theme_font_size_override("font_size", int(22 * s))
	card_title.position = Vector2((vs.x - cw) * 0.5, vs.y * 0.26)
	card_title.size = Vector2(cw, 40 * s)
	card_name.position = Vector2((vs.x - cw) * 0.5, vs.y * 0.33)
	card_name.size = Vector2(cw, 120 * s)
	card_name.pivot_offset = card_name.size * 0.5
	card_teaser.position = Vector2((vs.x - cw * 0.8) * 0.5, vs.y * 0.56)
	card_teaser.size = Vector2(cw * 0.8, 80 * s)
	card_hint.position = Vector2((vs.x - cw) * 0.5, vs.y * 0.82)
	card_hint.size = Vector2(cw, 30 * s)

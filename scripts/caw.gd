extends Node3D
## City 2 City Wrestling - CREATE A WRESTLER (caw.tscn), a PS2 skate-game-era creation screen.
##
## Left: category tabs (BODY HEAD TOP BOTTOM SHOES EXTRAS STYLE STATS NAME) over a list of
## option rows (< value >). Right: the wrestler on a turntable, rebuilt (debounced) whenever a
## look value changes; wrestler.gd caches every painted texture, so going back to a value is cheap.
## Bottom bar: BASED ON <roster fighter> (start from any roster look), RANDOMIZE, SAVE, BACK.
## Colour rows open a palette grid, text rows an on-screen keyboard (touch, typing or gamepad).
## Only values wrestler.gd renders are offered; looks are kept in wrestler.gd's canonical keys
## (roster aliases such as hair_style / top_style / stripe_color are folded in on load).
##
## Controls: arrows/WASD move + change, Enter/Space/J select, Esc/K back, Q/E (L1/R1) tabs,
## gamepad d-pad/stick + A/B, Start = save, Y = randomize; touch everything, drag the model.
## Saves through Game.save_caw() (scripts/game_state.gd, caw_contract.md).
## Headless (CI smoke test): randomizes, saves and goes on to the character select.

const Wrestler := preload("res://scripts/wrestler.gd")
const Roster := preload("res://scripts/roster.gd")
const Select := preload("res://scripts/select.gd")   # shares its sky / post-grade shaders
const Audio := preload("res://scripts/audio.gd")
const Music := preload("res://scripts/music.gd")
const TITLE_SCENE := "res://title.tscn"
const SELECT_SCENE := "res://select.tscn"

const GOLD := Color(1.0, 0.82, 0.12)
const RED := Color(0.86, 0.12, 0.08)
const INK := Color(0.06, 0.04, 0.02)
const PAPER := Color(0.95, 0.93, 0.88)
const PANEL_W := 580.0
const ROW_H := 40.0
const PLAT_H := 0.2
const REBUILD_DELAY := 0.3        # seconds of no changes before the model is rebuilt

const TABS := ["BODY", "HEAD", "TOP", "BOTTOM", "SHOES", "EXTRAS", "STYLE", "STATS", "NAME"]
const BAR := ["PRESET", "RANDOMIZE", "SAVE", "BACK"]

# ---- palettes: [name, colour]
const SKIN := [
	["PORCELAIN", Color(0.95, 0.8, 0.69)], ["FAIR", Color(0.9, 0.71, 0.58)], ["LIGHT", Color(0.86, 0.64, 0.48)],
	["BEIGE", Color(0.8, 0.6, 0.47)], ["TAN", Color(0.74, 0.52, 0.38)], ["OLIVE", Color(0.62, 0.43, 0.3)],
	["BROWN", Color(0.5, 0.33, 0.23)], ["CHESTNUT", Color(0.42, 0.28, 0.2)], ["DEEP BROWN", Color(0.3, 0.2, 0.14)],
	["EBONY", Color(0.22, 0.14, 0.1)],
]
const HAIR := [
	["JET BLACK", Color(0.04, 0.03, 0.03)], ["ESPRESSO", Color(0.1, 0.065, 0.045)], ["BROWN", Color(0.3, 0.18, 0.1)],
	["AUBURN", Color(0.45, 0.16, 0.08)], ["GINGER", Color(0.75, 0.36, 0.12)], ["BLONDE", Color(0.92, 0.8, 0.52)],
	["PLATINUM", Color(0.95, 0.93, 0.86)], ["SILVER", Color(0.62, 0.62, 0.64)], ["FIRE RED", Color(0.85, 0.1, 0.08)],
	["TOXIC GREEN", Color(0.42, 0.9, 0.1)], ["ELECTRIC BLUE", Color(0.15, 0.4, 1.0)], ["HOT PINK", Color(1.0, 0.3, 0.7)],
	["PURPLE", Color(0.5, 0.25, 0.85)], ["GOLD", Color(0.95, 0.75, 0.3)],
]
const CLOTH := [
	["BLACK", Color(0.06, 0.06, 0.07)], ["CHARCOAL", Color(0.18, 0.18, 0.2)], ["GREY", Color(0.46, 0.47, 0.49)],
	["WHITE", Color(0.94, 0.94, 0.92)], ["RED", Color(0.82, 0.12, 0.1)], ["MAROON", Color(0.5, 0.11, 0.12)],
	["ORANGE", Color(0.95, 0.5, 0.12)], ["GOLD", Color(1.0, 0.8, 0.2)], ["LIME", Color(0.65, 0.95, 0.15)],
	["GREEN", Color(0.12, 0.6, 0.26)], ["TEAL", Color(0.1, 0.62, 0.6)], ["SKY", Color(0.45, 0.72, 0.95)],
	["ROYAL", Color(0.15, 0.3, 0.85)], ["NAVY", Color(0.1, 0.13, 0.3)], ["PURPLE", Color(0.45, 0.24, 0.72)],
	["PINK", Color(1.0, 0.4, 0.72)], ["BROWN", Color(0.36, 0.22, 0.12)], ["TAN", Color(0.8, 0.7, 0.52)],
	["DENIM", Color(0.3, 0.42, 0.6)], ["LIGHT WASH", Color(0.62, 0.7, 0.82)], ["CREAM", Color(0.9, 0.85, 0.72)],
]
const LIPS := [
	["BERRY", Color(0.78, 0.12, 0.38)], ["HOT PINK", Color(0.84, 0.14, 0.44)], ["RED", Color(0.75, 0.06, 0.08)],
	["NUDE", Color(0.66, 0.4, 0.34)], ["PLUM", Color(0.42, 0.1, 0.24)], ["BLACK", Color(0.08, 0.05, 0.06)],
	["CORAL", Color(0.95, 0.42, 0.36)],
]

const FINISHERS := ["BACKYARD BOMB", "CURBSIDE CRUSHER", "BLOCK PARTY", "LAST CALL", "PORCH LIGHT SPECIAL",
	"GARAGE DOOR DROP", "SPRINKLER SPLASH", "CLOTHESLINE CITY", "MIXTAPE MELTDOWN", "LAWN DART"]
const BIOS := [
	"Homemade brawler from the block. Built from scratch, tested on the trampoline.",
	"Learned every move from late-night tapes and a very patient cousin.",
	"Undefeated in the cul-de-sac. The neighbours have stopped calling the cops.",
	"Mows lawns by day, slams fools by night. The grass never stood a chance.",
	"Came for the barbecue, stayed for the chaos. Never leaves without a belt.",
	"Self-made legend in the making. Mom says to be home before the streetlights.",
]
const RING_NAMES := ["BIG DEE", "KID CHAOS", "RUMBLE JONES", "NITRO NIKKI", "MAD MAXX", "LIL HAVOC", "DJ SUPLEX",
	"ROXY RIOT", "SLAMMIN SAM", "BLITZ BAILEY", "JUNKYARD JO", "TORNADO TY"]
const FIRST_NAMES := ["THEODORE", "DESTINY", "MARCUS", "JASMINE", "ALEXIS", "DWAYNE", "TIFFANY", "JORDAN", "BERNARD",
	"KEISHA", "SAMANTHA", "TYRONE"]

const DEFAULT_LOOK := {
	"gear": Color(0.95, 0.5, 0.12), "skin": Color(0.42, 0.28, 0.2), "body": "male", "face": "kid",
	"hair": "short", "hair_color": Color(0.04, 0.03, 0.03),
	"top": "tee", "top_color": Color(0.18, 0.18, 0.2), "top_accent": Color(1.0, 0.5, 0.12), "graphic": "skull_bolt",
	"bottom": "baggy", "bottom_color": Color(0.3, 0.42, 0.6), "bottom_fade": Color(0.62, 0.7, 0.82),
	"shoes": "sneakers", "shoe_color": Color(0.94, 0.94, 0.92), "shoe_accent": Color(0.82, 0.12, 0.1),
	"hat": "none", "makeup": "none", "accessories": [], "metal": "gold", "bulk": 1.0,
	"anim_style": "swagger", "signature_set": "tank",
}

# Keys the editor keeps (everything here is rendered by wrestler.gd); anything else is dropped.
const KEEP_KEYS := ["gear", "skin", "body", "face", "hair", "hair_color", "hair_tip", "top", "top_color", "top_accent",
	"outer_color", "graphic", "undershirt", "sleeves", "hood", "bottom", "bottom_color", "bottom_fade", "bottom_accent",
	"shoes", "shoe_color", "shoe_accent", "hat", "hat_color", "hat_band", "mask", "mask_base", "mask_paint", "makeup",
	"lip_color", "shadow_color", "chain", "chain_color", "bracelet", "tattoos", "wristband_color", "accessories", "metal",
	"bandana_color", "belt_color", "buckle_color", "bulk", "anim_style", "signature_set"]

enum Ov { NONE, OSK, PAL, CONFIRM, PRESET }

var t := 0.0
var start_ms := 0
var frames := 0
var headless := false
var game: Node = null
var lock_until_ms := 0
var leaving := false
var load_step := 0

# ---- the wrestler being edited
var look := {}
var info := {"ring_name": "ROOKIE", "short_name": "ROOKIE", "first_name": "THEODORE", "pronouns": "he",
	"signature": "BACKYARD BOMB", "bio": BIOS[0]}
var stats := {"POWER": 7, "AIR": 5, "FLOW": 6, "GRIT": 7}
var short_auto := true            # short name follows the ring name's first word until edited
var dirty := false

# ---- navigation
var tab := 0
var rows: Array = []              # visible row specs of the current tab
var row_sel := 0
var zone := "rows"                # "rows" | "bar"
var bar_sel := 2
var preset_idx := 0
var stick_x_armed := true
var stick_y_armed := true

# ---- overlay (on-screen keyboard / palette grid / confirm)
var ov: int = Ov.NONE
var ov_rows: Array = []           # Array of Array of item indices
var ov_items: Array = []          # {"text", "span", "color"(opt), "value"}
var ov_btns: Array[Button] = []
var ov_sel := 0
var ov_row_spec := {}             # the row the overlay edits
var ov_field := ""
var ov_text := ""
var ov_max := 14
var ov_before := ""

# ---- 3D
var world: Node3D
var camera: Camera3D
var view: SubViewport
var view_rect: TextureRect
var post_mat: ShaderMaterial
var turntable: Node3D
var dummy_opp: Node3D
var model: Node3D = null
var rebuild_at := -1.0
var anim_changed := false
var spin := 0.5
var spin_vel := 0.45
var drag_idle := 99.0
var dragging := false
var fade_3d := 0.0
var set_t := -1.0
var cam_zoom := 0.0               # 0 = full body, 1 = head close-up (HEAD tab)
var pose_left := 3.0
var pose_taunt := false
var bulbs: MultiMesh

var audio: Node = null
var music: Node = null

# ---- UI
var ui: Control
var font_i: FontVariation
var font_b: FontVariation
var head_label: Label
var tab_btns: Array[Button] = []
var tab_hint_l: Label
var tab_hint_r: Label
var panel: PanelContainer
var scroll: ScrollContainer
var row_box: VBoxContainer
var row_ctrls: Array = []         # per visible row: {"panel", "value", "swatch", "segs", "name"}
var desc_label: Label
var bar_box: HBoxContainer
var bar_btns: Array[Button] = []
var hint_label: Label
var tag_box: VBoxContainer
var tag_name: Label
var tag_sub: Label
var drag_hint: Label
var ov_dim: ColorRect
var ov_panel: PanelContainer
var ov_title: Label
var ov_textl: Label
var ov_grid: VBoxContainer
var ov_foot: Label
var flash_label: Label
var fade_rect: ColorRect
var margin := Vector4(60, 30, 60, 30)


func _ready() -> void:
	Engine.time_scale = 1.0
	randomize()
	start_ms = Time.get_ticks_msec()
	headless = DisplayServer.get_name() == "headless"
	game = get_node_or_null("/root/Game")
	_lock(0.45)   # the title's confirm press must not also hit a row
	font_b = FontVariation.new()
	font_b.base_font = ThemeDB.fallback_font
	font_b.variation_embolden = 1.1
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.2
	font_i.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.24, 1), Vector2.ZERO)
	_load_start()
	_build_view()
	_build_ui()
	_rebuild_rows()
	_relayout()
	get_viewport().size_changed.connect(_relayout)


func _load_start() -> void:
	look = _canon(DEFAULT_LOOK)
	if game != null and game.has_method("caw_exists") and bool(game.call("caw_exists")):
		var d: Dictionary = game.call("caw_data")
		var lv: Dictionary = d.get("look", {})
		look = _canon(lv)
		for k: String in ["ring_name", "short_name", "first_name", "pronouns", "signature", "bio"]:
			if d.has(k):
				info[k] = str(d[k])
		var sd: Dictionary = d.get("stats", {})
		for k: String in Roster.STATS:
			stats[k] = clampi(int(sd.get(k, 6)), 1, 10)
		short_auto = str(info["short_name"]) == _first_word(str(info["ring_name"]))
		look["anim_style"] = str(d.get("anim_style", look.get("anim_style", "swagger")))
		look["signature_set"] = str(d.get("signature_set", look.get("signature_set", "tank")))
	_fix_stats()


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	frames += 1
	var prev_t := t
	t = float(Time.get_ticks_msec() - start_ms) / 1000.0
	var dt := clampf(t - prev_t, 0.0, 0.1)

	if headless:
		_headless_step()
		return

	_staged_load()
	if rebuild_at >= 0.0 and t >= rebuild_at and turntable != null:
		rebuild_at = -1.0
		_rebuild_model()
	_animate_model(dt)
	_animate_camera(dt)

	var f := 0.0
	if set_t >= 0.0:
		f = clampf((t - set_t) / 0.4, 0.0, 1.0)
	fade_3d = maxf(fade_3d, f * f * (3.0 - 2.0 * f))
	if leaving:
		fade_3d = maxf(0.0, fade_3d - dt * 2.5)
	post_mat.set_shader_parameter("fade", fade_3d)
	if flash_label.visible:
		flash_label.modulate.a = clampf(flash_label.modulate.a - delta * 0.6, 0.0, 1.0)
	if bulbs != null:
		for i in bulbs.instance_count:
			var on := int(t * 6.0 + float(i)) % 4 != 0
			bulbs.set_instance_color(i, GOLD * (2.2 if on else 0.6))


func _headless_step() -> void:
	# CI smoke test: build the screen, the model and a random wrestler, save it, move on.
	if frames == 2:
		_build_set()
		_rebuild_model()
	elif frames == 20:
		_randomize(true)
		_rebuild_model()
		_rebuild_rows()
	elif frames == 40 and not leaving:
		leaving = true
		_save_data()
		print("caw (headless): saved %s, on to the character select" % str(info["ring_name"]))
		get_tree().change_scene_to_file(SELECT_SCENE)


func _staged_load() -> void:
	if frames < 2:
		return
	match load_step:
		0:
			_build_set()
			set_t = t
		1:
			_rebuild_model()
		2:
			audio = Audio.new()
			add_child(audio)
		3:
			music = Music.new()
			add_child(music)
			music.call("start")
		_:
			return
	load_step += 1


func _lock(secs: float) -> void:
	lock_until_ms = Time.get_ticks_msec() + int(secs * 1000.0)


func _locked() -> bool:
	return Time.get_ticks_msec() < lock_until_ms


func _snd(n: String, db := 0.0, var_amt := 0.05) -> void:
	if audio != null:
		var clips: Dictionary = audio.get("clips")
		if clips.has(n):
			audio.call("play", n, db, var_amt)


# ---------------------------------------------------------------- look helpers

func _first_word(s: String) -> String:
	var parts := s.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	return parts[0].left(10)


## A look in wrestler.gd's canonical keys (mirrors wrestler.gd _norm_look: roster aliases folded
## in), keeping only keys the editor knows.
func _canon(src: Dictionary) -> Dictionary:
	var o := src.duplicate(true)
	var al: Dictionary = Wrestler.LOOK_ALIASES
	for pair in [["hair_style", "hair"], ["top_style", "top"], ["bottom_style", "bottom"]]:
		var from: String = pair[0]
		var to: String = pair[1]
		if o.has(from):
			var v := str(o[from])
			var amap: Dictionary = al[to]
			o[to] = amap.get(v, v)
	if str(o.get("hair", "")) == "buzz":
		o["hair"] = "short"
	if o.has("shoes"):
		var sm: Dictionary = al["shoes"]
		o["shoes"] = sm.get(str(o["shoes"]), str(o["shoes"]))
	if o.has("hair_tips"):
		o["hair_tip"] = o["hair_tips"]
	if o.has("vest_color"):
		o["outer_color"] = o["vest_color"]
	if o.has("stripe_color"):
		o["top_accent"] = o["stripe_color"]
		o["bottom_accent"] = o["stripe_color"]
	var acc_in: Array = o.get("accessories", [])
	var am: Dictionary = al["acc"]
	var acc_out: Array = []
	for a in acc_in:
		var s := str(am.get(str(a), str(a)))
		if not (s in acc_out):
			acc_out.append(s)
	match str(o.get("chain_style", "")):
		"rope", "rope_thick":
			if not ("rope_chain" in acc_out):
				acc_out.append("rope_chain")
			o["chain"] = false
		"layered":
			if not ("layered_chains" in acc_out):
				acc_out.append("layered_chains")
			o["chain"] = false
	o["accessories"] = acc_out
	if not o.has("top"):
		o["top"] = "tee"
	if not o.has("bottom"):
		o["bottom"] = "baggy"
	if not o.has("hair") or str(o["hair"]) == "none":
		o["hair"] = "short"
	if not o.has("face") or not (str(o["face"]) in ["tank", "kid", "country", "oldschool", "punk"]):
		o["face"] = "kid" if str(o.get("face", "")) in ["popstar", "newschool"] else "tank"
	var out := {}
	for k: String in KEEP_KEYS:
		if o.has(k):
			out[k] = o[k]
	if not out.has("anim_style"):
		out["anim_style"] = "swagger"
	if not out.has("signature_set"):
		out["signature_set"] = "tank"
	return out


func _accs() -> Array:
	if not look.has("accessories"):
		look["accessories"] = []
	var a: Array = look["accessories"]
	return a


func _has_acc(a: String) -> bool:
	return a in _accs()


func _set_acc(a: String, on: bool) -> void:
	var arr := _accs()
	if on and not (a in arr):
		arr.append(a)
	elif not on and a in arr:
		arr.erase(a)


func _chain_mode() -> String:
	if _has_acc("layered_chains"):
		return "layered"
	if _has_acc("rope_chain"):
		return "rope"
	if bool(look.get("chain", false)):
		return "chain"
	return "none"


func _set_chain_mode(m: String) -> void:
	look["chain"] = m == "chain"
	_set_acc("rope_chain", m == "rope")
	_set_acc("layered_chains", m == "layered")


func _stat_total() -> int:
	var n := 0
	for k: String in Roster.STATS:
		n += int(stats[k])
	return n


## Keeps every stat 1..10 and the total at exactly 25.
func _fix_stats() -> void:
	for k: String in Roster.STATS:
		stats[k] = clampi(int(stats[k]), 1, 10)
	var guard := 0
	while _stat_total() != 25 and guard < 100:
		guard += 1
		var k: String = Roster.STATS[randi() % 4]
		if _stat_total() > 25 and int(stats[k]) > 1:
			stats[k] = int(stats[k]) - 1
		elif _stat_total() < 25 and int(stats[k]) < 10:
			stats[k] = int(stats[k]) + 1


# ---------------------------------------------------------------- rows

func _o(v: String, label: String) -> Array:
	return [v, label]


## Row specs for a tab, unfiltered. t: "opt" (look key), "color", "slider", "bool", "acc",
## "chain", "stat", "points", "text" (info field), "dopt" (info field options).
func _tab_rows(i: int) -> Array:
	match TABS[i]:
		"BODY":
			return [
				{"t": "opt", "label": "BODY", "key": "body", "def": "male", "opts": [_o("male", "MALE"), _o("female", "FEMALE")]},
				{"t": "slider", "label": "BUILD", "key": "bulk", "def": 1.0, "min": 0.8, "max": 1.15, "step": 0.05},
				{"t": "color", "label": "SKIN TONE", "key": "skin", "pal": SKIN, "def": SKIN[5][1]},
			]
		"HEAD":
			return [
				{"t": "opt", "label": "HAIR", "key": "hair", "def": "short", "opts": [_o("short", "BUZZ CUT"), _o("locs", "LOCS"),
					_o("curls", "CURLS"), _o("twists", "TWISTS"), _o("spikes", "LIBERTY SPIKES"), _o("ponytail", "PONYTAIL")]},
				{"t": "color", "label": "HAIR COLOR", "key": "hair_color", "pal": HAIR, "def": HAIR[0][1]},
				{"t": "color", "label": "DYED TIPS", "key": "hair_tip", "pal": HAIR, "none": "NONE", "if": "tips"},
				{"t": "opt", "label": "FACE", "key": "face", "def": "tank", "opts": [_o("tank", "GOATEE"), _o("kid", "CLEAN SHAVEN"),
					_o("country", "STUBBLE + HORSESHOE"), _o("oldschool", "PENCIL MOUSTACHE"), _o("punk", "BROW RING")]},
				{"t": "opt", "label": "MAKEUP", "key": "makeup", "def": "none", "opts": [_o("none", "NONE"), _o("glam", "GLAM"),
					_o("eyeliner", "EYELINER")]},
				{"t": "color", "label": "LIPSTICK", "key": "lip_color", "pal": LIPS, "def": LIPS[0][1], "if": "glam"},
				{"t": "color", "label": "EYESHADOW", "key": "shadow_color", "pal": CLOTH, "def": CLOTH[14][1], "if": "glam"},
				{"t": "opt", "label": "HAT", "key": "hat", "def": "none", "opts": [_o("none", "NONE"), _o("cowboy", "COWBOY HAT"),
					_o("fedora", "FEDORA"), _o("bucket", "BUCKET HAT")]},
				{"t": "color", "label": "HAT COLOR", "key": "hat_color", "pal": CLOTH, "def": CLOTH[0][1], "if": "hat"},
				{"t": "color", "label": "HAT BAND", "key": "hat_band", "pal": CLOTH, "def": CLOTH[16][1], "if": "hat"},
				{"t": "bool", "label": "SKULL MASK", "key": "mask", "def": false},
				{"t": "color", "label": "MASK BASE", "key": "mask_base", "pal": CLOTH, "def": CLOTH[20][1], "if": "mask"},
				{"t": "color", "label": "MASK PAINT", "key": "mask_paint", "pal": CLOTH, "def": CLOTH[4][1], "if": "mask"},
			]
		"TOP":
			return [
				{"t": "opt", "label": "STYLE", "key": "top", "def": "tee", "opts": [_o("tee", "BAGGY TEE"), _o("hoodie", "HOODIE"),
					_o("tracksuit", "TRACK JACKET"), _o("puffer", "PUFFER JACKET"), _o("western", "WESTERN SHIRT"),
					_o("studded_vest", "STUDDED VEST"), _o("stage_top", "STAGE TOP + JACKET")]},
				{"t": "color", "label": "MAIN COLOR", "key": "top_color", "pal": CLOTH, "def": CLOTH[0][1]},
				{"t": "color", "label": "ACCENT", "key": "top_accent", "pal": CLOTH, "def": CLOTH[7][1]},
				{"t": "color", "label": "JACKET / VEST", "key": "outer_color", "pal": CLOTH, "def": CLOTH[0][1], "if": "outer"},
				{"t": "opt", "label": "GRAPHIC", "key": "graphic", "def": "none", "if": "graphic", "opts": [_o("none", "NONE"),
					_o("skull_bolt", "SKULL BOLT"), _o("peligro", "WARNING SIGN"), _o("vermin", "VERMIN BAND LOGO"),
					_o("drip_heart", "DRIP HEART")]},
				{"t": "opt", "label": "SLEEVES", "key": "sleeves", "def": "short", "if": "tee", "opts": [_o("short", "SHORT"),
					_o("long", "LONG"), _o("none", "CUT OFF")]},
				{"t": "bool", "label": "HOOD", "key": "hood", "def": true, "if": "hoodie"},
				{"t": "bool", "label": "UNDERSHIRT", "key": "undershirt", "def": false, "if": "undershirt"},
			]
		"BOTTOM":
			return [
				{"t": "opt", "label": "STYLE", "key": "bottom", "def": "baggy", "opts": [_o("baggy", "BAGGY JEANS"),
					_o("stacked", "STACKED JEANS"), _o("skinny_ripped", "RIPPED SKINNY"), _o("bootcut", "BOOTCUT"),
					_o("track_pants", "TRACK PANTS"), _o("high_shorts", "HIGH SHORTS"), _o("leggings", "LEGGINGS")]},
				{"t": "color", "label": "MAIN COLOR", "key": "bottom_color", "pal": CLOTH, "def": CLOTH[18][1]},
				{"t": "color", "label": "WASH / FADE", "key": "bottom_fade", "pal": CLOTH, "def": CLOTH[19][1], "if": "denim"},
				{"t": "color", "label": "STRIPES / TRIM", "key": "bottom_accent", "pal": CLOTH, "def": CLOTH[3][1], "if": "trim"},
			]
		"SHOES":
			return [
				{"t": "opt", "label": "STYLE", "key": "shoes", "def": "sneakers", "opts": [_o("sneakers", "SKATE SNEAKERS"),
					_o("hightops", "HIGH-TOPS"), _o("shelltoes", "SHELL TOES"), _o("combat_boots", "COMBAT BOOTS"),
					_o("cowboy_boots", "COWBOY BOOTS"), _o("platforms", "PLATFORMS")]},
				{"t": "color", "label": "MAIN COLOR", "key": "shoe_color", "pal": CLOTH, "def": CLOTH[3][1]},
				{"t": "color", "label": "ACCENT", "key": "shoe_accent", "pal": CLOTH, "def": CLOTH[4][1]},
			]
		"EXTRAS":
			return [
				{"t": "chain", "label": "NECK CHAIN", "opts": [_o("none", "NONE"), _o("chain", "CHAIN"), _o("rope", "ROPE CHAIN"),
					_o("layered", "LAYERED CHAINS")]},
				{"t": "opt", "label": "METAL", "key": "metal", "def": "gold", "opts": [_o("gold", "GOLD"), _o("silver", "SILVER")]},
				{"t": "bool", "label": "BRACELET", "key": "bracelet", "def": false},
				{"t": "color", "label": "WRISTBAND", "key": "wristband_color", "pal": CLOTH, "none": "NONE"},
				{"t": "bool", "label": "ARM TATTOOS", "key": "tattoos", "def": false},
				{"t": "acc", "label": "FACE TATTOOS", "acc": "face_tattoos"},
				{"t": "acc", "label": "SHADES", "acc": "glasses"},
				{"t": "acc", "label": "HEADSET MIC", "acc": "headset"},
				{"t": "acc", "label": "HOOP EARRINGS", "acc": "hoops"},
				{"t": "acc", "label": "BANDANA", "acc": "bandana"},
				{"t": "color", "label": "BANDANA COLOR", "key": "bandana_color", "pal": CLOTH, "def": CLOTH[4][1], "if": "bandana"},
				{"t": "acc", "label": "STUDDED BELT", "acc": "studded_belt"},
				{"t": "acc", "label": "BIG BUCKLE", "acc": "buckle"},
				{"t": "color", "label": "BELT COLOR", "key": "belt_color", "pal": CLOTH, "def": CLOTH[0][1], "if": "belt"},
			]
		"STYLE":
			return [
				{"t": "color", "label": "SIGNATURE COLOR", "key": "gear", "pal": CLOTH, "def": CLOTH[6][1]},
				{"t": "opt", "label": "ATTITUDE", "key": "anim_style", "def": "swagger", "opts": [_o("swagger", "SWAGGER"),
					_o("hyper", "HYPER"), _o("diva", "DIVA"), _o("punk", "PUNK"), _o("cowboy", "COWBOY"),
					_o("oldschool", "OLD SCHOOL"), _o("newschool", "NEW SCHOOL")]},
				{"t": "opt", "label": "MOVE SET", "key": "signature_set", "def": "tank", "opts": [_o("tank", "POWERHOUSE"),
					_o("peligro", "HIGH FLYER")]},
				{"t": "dopt", "label": "FINISHER", "field": "signature", "opts": FINISHERS},
				{"t": "dopt", "label": "BIO", "field": "bio", "opts": BIOS},
			]
		"STATS":
			var out: Array = []
			for k: String in Roster.STATS:
				out.append({"t": "stat", "label": k, "stat": k})
			out.append({"t": "points", "label": "POINTS LEFT"})
			return out
		"NAME":
			return [
				{"t": "text", "label": "RING NAME", "field": "ring_name", "max": 14},
				{"t": "text", "label": "SHORT NAME", "field": "short_name", "max": 10},
				{"t": "text", "label": "FIRST NAME", "field": "first_name", "max": 12},
				{"t": "dopt", "label": "PRONOUNS", "field": "pronouns", "opts": ["he", "she", "they"],
					"names": ["HE / HIM", "SHE / HER", "THEY / THEM"]},
			]
	return []


func _row_visible(r: Dictionary) -> bool:
	var top := str(look.get("top", "tee"))
	var bottom := str(look.get("bottom", "baggy"))
	match str(r.get("if", "")):
		"":
			return true
		"tips":
			return str(look.get("hair", "")) in ["ponytail", "spikes", "twists"]
		"glam":
			return str(look.get("makeup", "none")) == "glam"
		"hat":
			return str(look.get("hat", "none")) != "none"
		"mask":
			return bool(look.get("mask", false))
		"outer":
			return top in ["stage_top", "studded_vest"]
		"graphic":
			return top in ["tee", "hoodie", "studded_vest", "puffer"]
		"tee":
			return top == "tee"
		"hoodie":
			return top == "hoodie"
		"undershirt":
			return top == "tee" and bottom == "baggy"
		"denim":
			return bottom in ["baggy", "stacked", "skinny_ripped", "bootcut"]
		"trim":
			return bottom in ["track_pants", "high_shorts"]
		"bandana":
			return _has_acc("bandana")
		"belt":
			return _has_acc("buckle") or _has_acc("studded_belt")
	return true


func _rebuild_rows() -> void:
	var keep := ""
	if row_sel >= 0 and row_sel < rows.size():
		keep = str((rows[row_sel] as Dictionary).get("label", ""))
	rows.clear()
	for r: Dictionary in _tab_rows(tab):
		if _row_visible(r):
			rows.append(r)
	var ns := 0
	for i in rows.size():
		if str((rows[i] as Dictionary)["label"]) == keep:
			ns = i
	row_sel = clampi(ns if keep != "" else row_sel, 0, maxi(0, rows.size() - 1))
	if row_box == null:
		return
	for c in row_box.get_children():
		c.queue_free()
	row_ctrls.clear()
	for i in rows.size():
		_build_row(i)
	_refresh_all()


func _build_row(i: int) -> void:
	var r: Dictionary = rows[i]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(PANEL_W - 40.0, ROW_H)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(h)
	var nl := _label(str(r["label"]), font_i, 19, GOLD, 5)
	nl.custom_minimum_size = Vector2(190, 0)
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(nl)
	var st := str(r["t"])
	var has_arrows := st != "points" and st != "text"
	var la: Button = null
	if has_arrows:
		la = _arrow("<")
		la.pressed.connect(func(): _tap_arrow(i, -1))
		h.add_child(la)
	var mid := HBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(mid)
	var sw: ColorRect = null
	var segs: Array = []
	if st == "color":
		sw = ColorRect.new()
		sw.custom_minimum_size = Vector2(30, 22)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(sw)
	if st == "stat" or st == "slider":
		var n := 10 if st == "stat" else 8
		for k in n:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(18 if st == "stat" else 22, 16)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mid.add_child(seg)
			segs.append(seg)
	var vl := _label("", font_b, 19, PAPER, 4)
	vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vl.clip_text = true
	vl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if st != "stat" and st != "slider":
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		vl.custom_minimum_size = Vector2(40, 0)
	mid.add_child(vl)
	if has_arrows:
		var ra := _arrow(">")
		ra.pressed.connect(func(): _tap_arrow(i, 1))
		h.add_child(ra)
	elif st == "text":
		var eb := _arrow("EDIT")
		eb.custom_minimum_size = Vector2(76, 34)
		eb.pressed.connect(func():
			_select_row(i)
			_activate_row())
		h.add_child(eb)
	p.gui_input.connect(func(ev: InputEvent): _row_gui(i, ev))
	row_box.add_child(p)
	row_ctrls.append({"panel": p, "value": vl, "swatch": sw, "segs": segs, "name": nl})


func _arrow(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 34)
	b.add_theme_font_override("font", font_i)
	b.add_theme_font_size_override("font_size", 20)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(c, PAPER)
	b.add_theme_color_override("font_pressed_color", INK)
	var n := _box_style(Color(0.1, 0.09, 0.1, 0.9), Color(0.3, 0.3, 0.32), 0, 0.15)
	n.content_margin_left = 6
	n.content_margin_right = 6
	var pr := _box_style(GOLD, INK, 0, 0.15)
	pr.content_margin_left = 6
	pr.content_margin_right = 6
	for s in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, n)
	b.add_theme_stylebox_override("pressed", pr)
	return b


func _row_gui(i: int, ev: InputEvent) -> void:
	if ov != Ov.NONE or leaving:
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
		# on release (a drag that scrolled the list should not count: ScrollContainer eats it)
		if zone == "rows" and row_sel == i:
			_activate_row()
		else:
			_select_row(i)


func _tap_arrow(i: int, dir: int) -> void:
	if ov != Ov.NONE or leaving:
		return
	_select_row(i)
	_change(dir)


func _select_row(i: int) -> void:
	zone = "rows"
	if i != row_sel:
		_snd("trick", -14.0, 0.0)
	row_sel = clampi(i, 0, maxi(0, rows.size() - 1))
	_refresh_all()
	_scroll_to_sel()


func _scroll_to_sel() -> void:
	if row_sel < row_ctrls.size():
		var p: Control = (row_ctrls[row_sel] as Dictionary)["panel"]
		scroll.call_deferred("ensure_control_visible", p)


# ---------------------------------------------------------------- changing values

func _idx_of_color(pal: Array, c: Color) -> int:
	for i in pal.size():
		var pc: Color = (pal[i] as Array)[1]
		if pc.is_equal_approx(c):
			return i
	return -1


func _opt_index(r: Dictionary) -> int:
	var opts: Array = r["opts"]
	var cur := str(look.get(str(r["key"]), r.get("def", "")))
	for i in opts.size():
		if str((opts[i] as Array)[0]) == cur:
			return i
	return 0


## Steps the selected row's value by dir (-1 / +1).
func _change(dir: int) -> void:
	if rows.is_empty():
		return
	var r: Dictionary = rows[row_sel]
	var st := str(r["t"])
	var key := str(r.get("key", ""))
	var relayout := false
	var look_changed := true
	match st:
		"opt":
			var opts: Array = r["opts"]
			var ni := posmod(_opt_index(r) + dir, opts.size())
			look[key] = str((opts[ni] as Array)[0])
			relayout = true
			if key == "anim_style":
				anim_changed = true
		"color":
			# states 0..n-1 = the palette, state n = none (rows that allow it)
			var pal: Array = r["pal"]
			var n := pal.size()
			var states := n + (1 if r.has("none") else 0)
			var cur := -1
			if look.has(key):
				var c: Color = look[key]
				cur = _idx_of_color(pal, c)
			elif r.has("none"):
				cur = n
			else:
				cur = _idx_of_color(pal, r.get("def", Color.WHITE))
			var ns := 0
			if cur < 0:
				ns = 0 if dir > 0 else n - 1
			else:
				ns = posmod(cur + dir, states)
			if ns >= n:
				look.erase(key)
			else:
				look[key] = (pal[ns] as Array)[1]
		"slider":
			var v := float(look.get(key, r["def"]))
			v = clampf(snappedf(v + float(dir) * float(r["step"]), 0.01), float(r["min"]), float(r["max"]))
			look[key] = v
		"bool":
			look[key] = not bool(look.get(key, r["def"]))
			relayout = true
		"acc":
			_set_acc(str(r["acc"]), not _has_acc(str(r["acc"])))
			relayout = true
		"chain":
			var opts: Array = r["opts"]
			var cm := _chain_mode()
			var ci := 0
			for i in opts.size():
				if str((opts[i] as Array)[0]) == cm:
					ci = i
			_set_chain_mode(str((opts[posmod(ci + dir, opts.size())] as Array)[0]))
			look.erase("chain_color")   # the METAL row picks the colour
		"stat":
			look_changed = false
			var k := str(r["stat"])
			var v := int(stats[k])
			if dir > 0 and v < 10 and _stat_total() < 25:
				stats[k] = v + 1
			elif dir < 0 and v > 1:
				stats[k] = v - 1
			else:
				_snd("whoosh", -14.0)
				return
		"dopt":
			look_changed = false
			var opts: Array = r["opts"]
			var f := str(r["field"])
			var ci := maxi(0, opts.find(str(info[f])))
			info[f] = str(opts[posmod(ci + dir, opts.size())])
		"points", "text":
			return
	if key == "metal":
		look.erase("chain_color")
	dirty = true
	_snd("trick", -10.0, 0.06)
	if look_changed:
		rebuild_at = t + REBUILD_DELAY
	if relayout:
		var before := rows.size()
		var keep := row_sel
		_rebuild_rows()
		if rows.size() != before:
			row_sel = clampi(keep, 0, rows.size() - 1)
			_refresh_all()
	else:
		_refresh_all()


## Enter / tap on the selected row.
func _activate_row() -> void:
	if rows.is_empty():
		return
	var r: Dictionary = rows[row_sel]
	match str(r["t"]):
		"text":
			_open_osk(r)
		"color":
			_open_palette(r)
		"points":
			pass
		"stat":
			_change(1)
		_:
			_change(1)


func _value_text(r: Dictionary) -> String:
	match str(r["t"]):
		"opt":
			var opts: Array = r["opts"]
			return str((opts[_opt_index(r)] as Array)[1])
		"color":
			var key := str(r["key"])
			if not look.has(key):
				if r.has("none"):
					return str(r["none"])
				var dc: Color = r.get("def", Color.WHITE)
				var di := _idx_of_color(r["pal"], dc)
				return str(((r["pal"] as Array)[di] as Array)[0]) if di >= 0 else "CUSTOM"
			var c: Color = look[key]
			var ci := _idx_of_color(r["pal"], c)
			return str(((r["pal"] as Array)[ci] as Array)[0]) if ci >= 0 else "CUSTOM"
		"slider":
			var v := float(look.get(str(r["key"]), r["def"]))
			return "%d" % roundi(v * 100.0)
		"bool":
			return "ON" if bool(look.get(str(r["key"]), r["def"])) else "OFF"
		"acc":
			return "ON" if _has_acc(str(r["acc"])) else "OFF"
		"chain":
			var opts: Array = r["opts"]
			for o: Array in opts:
				if str(o[0]) == _chain_mode():
					return str(o[1])
			return "NONE"
		"stat":
			return str(int(stats[str(r["stat"])]))
		"points":
			return "%d" % (25 - _stat_total())
		"text":
			return str(info[str(r["field"])])
		"dopt":
			var f := str(r["field"])
			if r.has("names"):
				var opts: Array = r["opts"]
				var names: Array = r["names"]
				var i := maxi(0, opts.find(str(info[f])))
				return str(names[i])
			return str(info[f])
	return ""


func _refresh_all() -> void:
	for i in row_ctrls.size():
		if i >= rows.size():
			break
		var r: Dictionary = rows[i]
		var c: Dictionary = row_ctrls[i]
		var on := zone == "rows" and i == row_sel and ov == Ov.NONE
		var p: PanelContainer = c["panel"]
		p.add_theme_stylebox_override("panel", _row_style(on, i == row_sel))
		var vl: Label = c["value"]
		vl.text = _value_text(r)
		vl.add_theme_color_override("font_color", INK if on else PAPER.darkened(0.06))
		vl.add_theme_constant_override("outline_size", 0 if on else 4)
		vl.add_theme_constant_override("shadow_offset_x", 0 if on else 3)
		vl.add_theme_constant_override("shadow_offset_y", 0 if on else 3)
		var nl: Label = c["name"]
		nl.add_theme_color_override("font_color", INK if on else GOLD)
		nl.add_theme_constant_override("outline_size", 0 if on else 5)
		nl.add_theme_constant_override("shadow_offset_x", 0 if on else 3)
		nl.add_theme_constant_override("shadow_offset_y", 0 if on else 3)
		var sw: ColorRect = c["swatch"]
		if sw != null:
			var key := str(r["key"])
			sw.visible = look.has(key) or not r.has("none")
			var col: Color = look.get(key, r.get("def", Color.WHITE))
			sw.color = col
		var segs: Array = c["segs"]
		if not segs.is_empty():
			var filled := 0
			var col_on := GOLD
			if str(r["t"]) == "stat":
				filled = int(stats[str(r["stat"])])
				var sc: Color = Select.STAT_COLS[Roster.STATS.find(str(r["stat"]))]
				col_on = sc
			else:
				var v := float(look.get(str(r["key"]), r["def"]))
				filled = roundi((v - float(r["min"])) / float(r["step"])) + 1
			for k in segs.size():
				var seg: ColorRect = segs[k]
				seg.color = col_on if k < filled else Color(0.16, 0.16, 0.18, 0.9)
	for i in tab_btns.size():
		var b := tab_btns[i]
		var on := i == tab
		_style_button(b, _box_style(GOLD if on else Color(0.05, 0.045, 0.05, 0.86), INK if on else RED, 6, 0.22))
		for cn in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(cn, INK if on else PAPER)
		b.add_theme_constant_override("outline_size", 0 if on else 4)
	for i in bar_btns.size():
		var b := bar_btns[i]
		var on := zone == "bar" and i == bar_sel and ov == Ov.NONE
		var base := Color(0.05, 0.045, 0.05, 0.88)
		if BAR[i] == "SAVE":
			base = Color(0.12, 0.3, 0.1, 0.92)
		_style_button(b, _box_style(GOLD if on else base, INK if on else RED, 8, 0.2))
		for cn in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(cn, INK if on else PAPER)
		b.add_theme_constant_override("outline_size", 0 if on else 5)
		if BAR[i] == "PRESET":
			var e: Dictionary = Roster.ROSTER[preset_idx]
			b.text = "BASED ON: %s" % str(e["short_name"])
	desc_label.text = _desc_text()
	tag_name.text = str(info["ring_name"])
	tag_sub.text = "%s   POW %d  AIR %d  FLO %d  GRT %d" % [_value_for_pronouns(), int(stats["POWER"]), int(stats["AIR"]),
		int(stats["FLOW"]), int(stats["GRIT"])]
	_relayout_tag()


func _value_for_pronouns() -> String:
	match str(info["pronouns"]):
		"she":
			return "SHE / HER"
		"they":
			return "THEY / THEM"
	return "HE / HIM"


func _desc_text() -> String:
	if zone == "bar":
		match BAR[bar_sel]:
			"PRESET":
				return "Start from any roster fighter's look"
			"RANDOMIZE":
				return "Roll a random look, attitude and stats"
			"SAVE":
				return "Save your wrestler (story mode stars them)"
			"BACK":
				return "Leave the editor"
	if rows.is_empty():
		return ""
	var r: Dictionary = rows[row_sel]
	match str(r["t"]):
		"text":
			return "ENTER / tap EDIT to type"
		"color":
			return "< > cycle colours   ENTER: palette"
		"stat", "points":
			return "25 points across 4 stats, each 1-10   (%d left)" % (25 - _stat_total())
	return "< > change"


func _row_style(on: bool, sel: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.skew = Vector2(0.12, 0.0)
	sb.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.96) if on else (Color(0.13, 0.11, 0.1, 0.9) if sel else Color(0.04, 0.035, 0.04, 0.78))
	sb.border_color = Color(0.02, 0.02, 0.02) if on else Color(0.5, 0.1, 0.07)
	sb.border_width_left = 10 if on else 3
	sb.border_width_bottom = 3 if on else 2
	sb.content_margin_left = 14
	sb.content_margin_right = 10
	if on:
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(5, 5)
	return sb


# ---------------------------------------------------------------- tabs / bar actions

func _set_tab(i: int) -> void:
	var nt := posmod(i, TABS.size())
	if nt == tab:
		return
	tab = nt
	row_sel = 0
	zone = "rows"
	rows.clear()
	_rebuild_rows()
	scroll.scroll_vertical = 0
	_snd("whoosh", -10.0)


func _bar_press(i: int) -> void:
	if ov != Ov.NONE or leaving:
		return
	zone = "bar"
	bar_sel = i
	match BAR[i]:
		"PRESET":
			_open_presets()
		"RANDOMIZE":
			_randomize(false)
		"SAVE":
			_save()
		"BACK":
			_back()
	_refresh_all()


func _apply_preset() -> void:
	var e: Dictionary = Roster.ROSTER[preset_idx]
	var lv: Dictionary = e["look"]
	look = _canon(lv)
	look["anim_style"] = str(e.get("anim_style", look.get("anim_style", "swagger")))
	look["signature_set"] = str(e.get("signature_set", look.get("signature_set", "tank")))
	dirty = true
	anim_changed = true
	rebuild_at = t + 0.05
	_rebuild_rows()
	_flash("BASED ON " + str(e["short_name"]))
	_snd("punch", -6.0)


func _pick(a: Array) -> Variant:
	return a[randi() % a.size()]


func _pick_col(pal: Array) -> Color:
	var e: Array = _pick(pal)
	var c: Color = e[1]
	return c


func _randomize(names_too: bool) -> void:
	var fem := randf() < 0.45
	var l := {}
	l["body"] = "female" if fem else "male"
	l["bulk"] = snappedf(randf_range(0.8, 1.15), 0.05)
	l["skin"] = _pick_col(SKIN)
	l["hair"] = str(_pick(["short", "locs", "curls", "twists", "spikes", "ponytail"] if fem else
		["short", "short", "locs", "curls", "twists", "spikes", "ponytail"]))
	l["hair_color"] = _pick_col(HAIR.slice(0, 8)) if randf() < 0.7 else _pick_col(HAIR)
	if str(l["hair"]) in ["ponytail", "spikes", "twists"] and randf() < 0.45:
		l["hair_tip"] = _pick_col(HAIR)
	l["face"] = "kid" if fem else str(_pick(["tank", "kid", "country", "oldschool", "punk"]))
	l["makeup"] = str(_pick(["glam", "eyeliner", "none"])) if fem else ("eyeliner" if randf() < 0.12 else "none")
	if str(l["makeup"]) == "glam":
		l["lip_color"] = _pick_col(LIPS)
		l["shadow_color"] = _pick_col(CLOTH)
	if randf() < 0.28:
		l["hat"] = str(_pick(["cowboy", "fedora", "bucket"]))
		l["hat_color"] = _pick_col(CLOTH)
		l["hat_band"] = _pick_col(CLOTH)
	else:
		l["hat"] = "none"
	if randf() < 0.12:
		l["mask"] = true
		l["mask_base"] = _pick_col(CLOTH)
		l["mask_paint"] = _pick_col(CLOTH)
	var top := str(_pick(["tee", "hoodie", "tracksuit", "puffer", "western", "studded_vest", "stage_top"]))
	l["top"] = top
	l["top_color"] = _pick_col(CLOTH)
	l["top_accent"] = _pick_col(CLOTH)
	if top in ["stage_top", "studded_vest"]:
		l["outer_color"] = _pick_col(CLOTH)
	if top in ["tee", "hoodie", "studded_vest", "puffer"]:
		l["graphic"] = str(_pick(["none", "skull_bolt", "peligro", "vermin", "drip_heart"]))
	if top == "tee":
		l["sleeves"] = str(_pick(["short", "short", "long", "none"]))
	var bottom := str(_pick(["baggy", "stacked", "skinny_ripped", "bootcut", "track_pants", "high_shorts", "leggings"]))
	l["bottom"] = bottom
	l["bottom_color"] = _pick_col(CLOTH)
	l["bottom_fade"] = _pick_col(CLOTH)
	l["bottom_accent"] = _pick_col(CLOTH)
	if top == "tee" and bottom == "baggy" and randf() < 0.5:
		l["undershirt"] = true
	l["shoes"] = str(_pick(["sneakers", "hightops", "shelltoes", "combat_boots", "cowboy_boots", "platforms"]))
	l["shoe_color"] = _pick_col(CLOTH)
	l["shoe_accent"] = _pick_col(CLOTH)
	l["metal"] = str(_pick(["gold", "silver"]))
	var acc: Array = []
	for a: String in ["face_tattoos", "glasses", "headset", "hoops", "bandana", "studded_belt", "buckle"]:
		if randf() < 0.16:
			acc.append(a)
	l["accessories"] = acc
	if "bandana" in acc:
		l["bandana_color"] = _pick_col(CLOTH)
	if "buckle" in acc or "studded_belt" in acc:
		l["belt_color"] = _pick_col(CLOTH)
	look = l
	_set_chain_mode(str(_pick(["none", "none", "chain", "rope", "layered"])))
	l["bracelet"] = randf() < 0.3
	l["tattoos"] = randf() < 0.3
	if randf() < 0.25:
		l["wristband_color"] = _pick_col(CLOTH)
	l["gear"] = _pick_col(CLOTH.slice(4, 16))
	l["anim_style"] = str(_pick(["swagger", "hyper", "diva", "punk", "cowboy", "oldschool", "newschool"]))
	l["signature_set"] = str(_pick(["tank", "peligro"]))
	info["signature"] = str(_pick(FINISHERS))
	for k: String in Roster.STATS:
		stats[k] = 1 + randi() % 10
	_fix_stats()
	if names_too:
		info["ring_name"] = str(_pick(RING_NAMES))
		info["short_name"] = _first_word(str(info["ring_name"]))
		info["first_name"] = str(_pick(FIRST_NAMES))
		info["pronouns"] = "she" if fem else str(_pick(["he", "he", "they"]))
		info["bio"] = str(_pick(BIOS))
	dirty = true
	anim_changed = true
	rebuild_at = t + 0.05
	if not headless:
		_rebuild_rows()
		_flash("RANDOMIZED!")
		_snd("punch", -6.0)


func _save_data() -> void:
	look["anim_style"] = str(look.get("anim_style", "swagger"))
	look["signature_set"] = str(look.get("signature_set", "tank"))
	var d := {
		"ring_name": str(info["ring_name"]), "short_name": str(info["short_name"]), "first_name": str(info["first_name"]),
		"pronouns": str(info["pronouns"]), "look": look.duplicate(true), "stats": stats.duplicate(),
		"anim_style": look["anim_style"], "signature_set": look["signature_set"], "signature": str(info["signature"]),
		"genre": "CUSTOM", "bio": str(info["bio"]),
	}
	if game != null and game.has_method("save_caw"):
		game.call("save_caw", d)


func _save() -> void:
	if _stat_total() != 25:
		_flash("SPEND ALL 25 STAT POINTS")
		_set_tab(TABS.find("STATS"))
		_snd("whoosh", -6.0)
		return
	if str(info["ring_name"]).strip_edges().is_empty():
		_flash("NAME YOUR WRESTLER")
		_set_tab(TABS.find("NAME"))
		return
	_save_data()
	dirty = false
	_flash("WRESTLER SAVED!")
	_snd("cheer_small", -6.0)
	_snd("big_thud", -6.0)
	if model != null:
		_pose(Wrestler.S.WIN, 2.6)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(func(): _leave(_return_scene()))


func _back() -> void:
	if dirty:
		_open_confirm()
	else:
		_leave(_return_scene())


## Where SAVE / BACK go: Game's "caw_return" meta (set by whoever opened the editor, e.g. story
## mode) when present -- consumed here -- else the title.
func _return_scene() -> String:
	if game != null and game.has_meta("caw_return"):
		var p := str(game.get_meta("caw_return"))
		game.remove_meta("caw_return")
		if not p.is_empty():
			return p
	return TITLE_SCENE


func _leave(scene: String) -> void:
	if leaving:
		return
	leaving = true
	if music != null:
		music.call("fade_out", 0.4)
	fade_rect.visible = true
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.4)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene))


func _flash(s: String) -> void:
	flash_label.text = s
	flash_label.visible = true
	flash_label.modulate.a = 1.6
	flash_label.reset_size()
	_relayout_flash()


# ---------------------------------------------------------------- overlays

func _ov_button(item: Dictionary, idx: int) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = str(item.get("text", ""))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = float(item.get("span", 1))
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_override("font", font_i)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func(): _ov_press(idx))
	return b


func _open_overlay(mode: int, title: String, items: Array, layout: Array, sel_i: int, foot: String) -> void:
	ov = mode
	ov_items = items
	ov_rows = layout
	ov_sel = clampi(sel_i, 0, items.size() - 1)
	ov_title.text = title
	ov_foot.text = foot
	for c in ov_grid.get_children():
		ov_grid.remove_child(c)   # now, so the panel's minimum size forgets the old grid
		c.queue_free()
	ov_btns.clear()
	for i in items.size():
		ov_btns.append(_ov_button(items[i], i))
	for rw: Array in layout:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		for idx: int in rw:
			h.add_child(ov_btns[idx])
		ov_grid.add_child(h)
	ov_textl.visible = mode == Ov.OSK
	ov_dim.visible = true
	ov_panel.visible = true
	_lock(0.15)
	_refresh_overlay()
	_refresh_all()
	_relayout()
	call_deferred("_relayout")


func _close_overlay() -> void:
	ov = Ov.NONE
	ov_dim.visible = false
	ov_panel.visible = false
	_lock(0.12)
	_refresh_all()


func _refresh_overlay() -> void:
	for i in ov_btns.size():
		var b := ov_btns[i]
		var it: Dictionary = ov_items[i]
		var on := i == ov_sel
		if it.has("color"):
			var c: Color = it["color"]
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.border_color = GOLD if on else Color(0.02, 0.02, 0.02)
			var bw := 5 if on else 2
			sb.border_width_left = bw
			sb.border_width_right = bw
			sb.border_width_top = bw
			sb.border_width_bottom = bw
			sb.corner_radius_top_left = 3
			sb.corner_radius_bottom_right = 3
			if on:
				sb.shadow_color = Color(1.0, 0.82, 0.12, 0.5)
				sb.shadow_size = 4
			_style_button(b, sb)
			b.custom_minimum_size = Vector2(0, 52)
		else:
			_style_button(b, _box_style(GOLD if on else Color(0.1, 0.09, 0.1, 0.95), INK if on else Color(0.4, 0.1, 0.08), 4, 0.12))
			for cn in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
				b.add_theme_color_override(cn, INK if on else PAPER)
	if ov == Ov.OSK:
		ov_textl.text = ov_text + "_"
	elif ov == Ov.PAL and ov_sel < ov_items.size():
		ov_foot.text = str((ov_items[ov_sel] as Dictionary).get("name", "")) + "      ENTER pick   ESC close"


func _ov_nav(dx: int, dy: int) -> void:
	# find the item's row / position
	var ri := 0
	var pi := 0
	for r in ov_rows.size():
		var rw: Array = ov_rows[r]
		var f := rw.find(ov_sel)
		if f >= 0:
			ri = r
			pi = f
	var rw0: Array = ov_rows[ri]
	if dx != 0:
		ov_sel = int(rw0[posmod(pi + dx, rw0.size())])
	elif dy != 0:
		var cx := _ov_center(ri, pi)
		var nr := posmod(ri + dy, ov_rows.size())
		var rw1: Array = ov_rows[nr]
		var best := 0
		var bd := 99.0
		for j in rw1.size():
			var d := absf(_ov_center(nr, j) - cx)
			if d < bd:
				bd = d
				best = j
		ov_sel = int(rw1[best])
	_snd("trick", -14.0, 0.0)
	_refresh_overlay()


func _ov_center(r: int, j: int) -> float:
	var rw: Array = ov_rows[r]
	var tot := 0.0
	for idx: int in rw:
		tot += float((ov_items[idx] as Dictionary).get("span", 1))
	var acc := 0.0
	for k in j:
		acc += float((ov_items[int(rw[k])] as Dictionary).get("span", 1))
	return (acc + 0.5 * float((ov_items[int(rw[j])] as Dictionary).get("span", 1))) / maxf(tot, 1.0)


func _ov_press(idx: int) -> void:
	if ov == Ov.NONE:
		return
	ov_sel = idx
	var it: Dictionary = ov_items[idx]
	var v := str(it.get("value", ""))
	match ov:
		Ov.OSK:
			match v:
				"SPACE":
					_osk_type(" ")
				"DEL":
					ov_text = ov_text.left(maxi(0, ov_text.length() - 1))
				"CLEAR":
					ov_text = ""
				"DONE":
					_osk_done()
					return
				_:
					_osk_type(v)
			_snd("trick", -12.0, 0.0)
		Ov.PAL:
			var key := str(ov_row_spec["key"])
			if v == "NONE":
				look.erase(key)
			else:
				var c: Color = it["color"]
				look[key] = c
			dirty = true
			rebuild_at = t + 0.05
			_snd("punch", -10.0)
			_close_overlay()
			return
		Ov.CONFIRM:
			_close_overlay()
			if v == "YES":
				_leave(_return_scene())
			return
		Ov.PRESET:
			_close_overlay()
			preset_idx = clampi(int(v), 0, Roster.count() - 1)
			_apply_preset()
			_refresh_all()
			return
	_refresh_overlay()


func _open_osk(r: Dictionary) -> void:
	ov_row_spec = r
	ov_field = str(r["field"])
	ov_text = str(info[ov_field])
	ov_before = ov_text
	ov_max = int(r.get("max", 14))
	var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.'!"
	var items: Array = []
	var layout: Array = []
	for i in chars.length():
		items.append({"text": chars[i], "value": chars[i], "span": 1})
	for rr in 4:
		var rw: Array = []
		for c in 10:
			rw.append(rr * 10 + c)
		layout.append(rw)
	var base := items.size()
	items.append({"text": "SPACE", "value": "SPACE", "span": 3})
	items.append({"text": "DEL", "value": "DEL", "span": 2})
	items.append({"text": "CLEAR", "value": "CLEAR", "span": 2})
	items.append({"text": "DONE", "value": "DONE", "span": 3})
	layout.append([base, base + 1, base + 2, base + 3])
	_open_overlay(Ov.OSK, str(r["label"]) + "  (max %d)" % ov_max, items, layout, 0,
		"TYPE or pick letters    ENTER key    ESC / START done")


func _osk_type(ch: String) -> void:
	if ov_text.length() >= ov_max:
		_snd("whoosh", -14.0)
		return
	if ch == " " and (ov_text.is_empty() or ov_text.ends_with(" ")):
		return
	ov_text += ch


func _osk_done() -> void:
	var v := ov_text.strip_edges().to_upper()
	if v.is_empty():
		v = ov_before
	var old := str(info[ov_field])
	info[ov_field] = v
	if ov_field == "ring_name" and short_auto:
		info["short_name"] = _first_word(v)
	if ov_field == "short_name":
		short_auto = v == _first_word(str(info["ring_name"]))
	if v != old:
		dirty = true
		if ov_field == "ring_name" and model != null:
			model.set("display_name", v)
	_snd("punch", -8.0)
	_close_overlay()


func _open_palette(r: Dictionary) -> void:
	ov_row_spec = r
	var pal: Array = r["pal"]
	var items: Array = []
	var layout: Array = []
	var cols := 7
	var key := str(r["key"])
	var cur := -1
	if look.has(key):
		var c: Color = look[key]
		cur = _idx_of_color(pal, c)
	for i in pal.size():
		var e: Array = pal[i]
		items.append({"text": "", "value": str(i), "color": e[1], "name": str(e[0]), "span": 1})
	var rw: Array = []
	for i in pal.size():
		rw.append(i)
		if rw.size() == cols:
			layout.append(rw)
			rw = []
	if not rw.is_empty():
		layout.append(rw)
	if r.has("none"):
		items.append({"text": str(r["none"]), "value": "NONE", "span": 1, "name": str(r["none"])})
		layout.append([items.size() - 1])
		if cur < 0 and not look.has(key):
			cur = items.size() - 1
	_open_overlay(Ov.PAL, str(r["label"]), items, layout, maxi(cur, 0), "")


func _open_presets() -> void:
	var items: Array = []
	var layout: Array = []
	var rw: Array = []
	for i in Roster.count():
		var e: Dictionary = Roster.ROSTER[i]
		items.append({"text": str(e["short_name"]), "value": str(i), "span": 1})
		rw.append(i)
		if rw.size() == 3:
			layout.append(rw)
			rw = []
	if not rw.is_empty():
		layout.append(rw)
	_open_overlay(Ov.PRESET, "START FROM A LOOK", items, layout, preset_idx,
		"Copies their whole look + attitude (name and stats stay yours)      ESC close")


func _open_confirm() -> void:
	var items: Array = [{"text": "DISCARD", "value": "YES", "span": 1}, {"text": "KEEP EDITING", "value": "NO", "span": 1}]
	_open_overlay(Ov.CONFIRM, "DISCARD CHANGES?", items, [[0, 1]], 1, "Your wrestler is not saved")


func _ov_back() -> void:
	match ov:
		Ov.OSK:
			_osk_done()
		_:
			_close_overlay()


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if leaving or headless:
		return
	if event is InputEventKey:
		_key_input(event as InputEventKey)
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_pad_button(jb.button_index)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_X:
			if absf(jm.axis_value) < 0.3:
				stick_x_armed = true
			elif absf(jm.axis_value) > 0.6 and stick_x_armed:
				stick_x_armed = false
				_nav(1 if jm.axis_value > 0.0 else -1, 0)
		elif jm.axis == JOY_AXIS_LEFT_Y:
			if absf(jm.axis_value) < 0.3:
				stick_y_armed = true
			elif absf(jm.axis_value) > 0.6 and stick_y_armed:
				stick_y_armed = false
				_nav(0, 1 if jm.axis_value > 0.0 else -1)


func _key_input(k: InputEventKey) -> void:
	if not k.pressed:
		return
	var code := k.physical_keycode
	if ov == Ov.OSK:
		get_viewport().set_input_as_handled()
		match code:
			KEY_LEFT:
				_ov_nav(-1, 0)
			KEY_RIGHT:
				_ov_nav(1, 0)
			KEY_UP:
				_ov_nav(0, -1)
			KEY_DOWN:
				_ov_nav(0, 1)
			KEY_ENTER, KEY_KP_ENTER:
				if not k.echo:
					_ov_press(ov_sel)
			KEY_ESCAPE:
				if not k.echo:
					_osk_done()
			KEY_BACKSPACE:
				ov_text = ov_text.left(maxi(0, ov_text.length() - 1))
				_refresh_overlay()
			_:
				var u := k.unicode
				if u > 0:
					var ch := char(u).to_upper()
					if ch == " " or "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.'!".contains(ch):
						_osk_type(ch)
						# typed on the keyboard: Enter should finish, so park the cursor on DONE
						ov_sel = ov_items.size() - 1
						_refresh_overlay()
		return
	var dx := 0
	var dy := 0
	var confirm := false
	var back := false
	match code:
		KEY_LEFT, KEY_A:
			dx = -1
		KEY_RIGHT, KEY_D:
			dx = 1
		KEY_UP, KEY_W:
			dy = -1
		KEY_DOWN, KEY_S:
			dy = 1
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J, KEY_Z:
			confirm = true
		KEY_ESCAPE, KEY_BACKSPACE, KEY_K, KEY_X:
			back = true
		KEY_Q, KEY_PAGEUP:
			if not k.echo and ov == Ov.NONE:
				_set_tab(tab - 1)
			get_viewport().set_input_as_handled()
			return
		KEY_E, KEY_PAGEDOWN, KEY_TAB:
			if not k.echo and ov == Ov.NONE:
				_set_tab(tab + 1)
			get_viewport().set_input_as_handled()
			return
		KEY_R:
			if not k.echo and ov == Ov.NONE:
				_randomize(false)
			return
		_:
			return
	get_viewport().set_input_as_handled()
	if (confirm or back) and (k.echo or _locked()):
		return
	if dx != 0 or dy != 0:
		_nav(dx, dy)
	elif confirm:
		_confirm()
	elif back:
		_cancel()


func _pad_button(b: int) -> void:
	match b:
		JOY_BUTTON_DPAD_LEFT:
			_nav(-1, 0)
		JOY_BUTTON_DPAD_RIGHT:
			_nav(1, 0)
		JOY_BUTTON_DPAD_UP:
			_nav(0, -1)
		JOY_BUTTON_DPAD_DOWN:
			_nav(0, 1)
		JOY_BUTTON_A:
			if not _locked():
				_confirm()
		JOY_BUTTON_B:
			if _locked():
				return
			if ov == Ov.OSK:
				ov_text = ov_text.left(maxi(0, ov_text.length() - 1))
				_refresh_overlay()
			else:
				_cancel()
		JOY_BUTTON_LEFT_SHOULDER:
			if ov == Ov.NONE:
				_set_tab(tab - 1)
		JOY_BUTTON_RIGHT_SHOULDER:
			if ov == Ov.NONE:
				_set_tab(tab + 1)
		JOY_BUTTON_Y:
			if ov == Ov.NONE:
				_randomize(false)
		JOY_BUTTON_START:
			if ov == Ov.OSK:
				_osk_done()
			elif ov == Ov.NONE:
				_save()
		JOY_BUTTON_BACK:
			if ov == Ov.NONE:
				_back()


func _nav(dx: int, dy: int) -> void:
	if ov != Ov.NONE:
		_ov_nav(dx, dy)
		return
	if zone == "rows":
		if dy != 0:
			var n := row_sel + dy
			if n >= rows.size():
				zone = "bar"
				bar_sel = clampi(bar_sel, 0, BAR.size() - 1)
			elif n < 0:
				zone = "bar"
			else:
				row_sel = n
			_snd("trick", -14.0, 0.0)
			_refresh_all()
			_scroll_to_sel()
		elif dx != 0:
			_change(dx)
	else:
		if dy != 0:
			zone = "rows"
			row_sel = 0 if dy > 0 else rows.size() - 1
			_snd("trick", -14.0, 0.0)
			_refresh_all()
			_scroll_to_sel()
		elif dx != 0:
			bar_sel = posmod(bar_sel + dx, BAR.size())
			_snd("trick", -14.0, 0.0)
			_refresh_all()


func _confirm() -> void:
	if ov != Ov.NONE:
		_ov_press(ov_sel)
		return
	if zone == "rows":
		_activate_row()
	else:
		_bar_press(bar_sel)


func _cancel() -> void:
	if ov != Ov.NONE:
		_ov_back()
		return
	_back()


func _unhandled_input(event: InputEvent) -> void:
	# Drag on the model side spins the turntable (touch, or mouse via touch emulation).
	if leaving or ov != Ov.NONE:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		dragging = st.pressed and st.position.x > panel.position.x + panel.size.x + 20.0 \
			and st.position.y > panel.position.y and st.position.y < bar_box.position.y
		if dragging:
			drag_idle = 0.0
	elif event is InputEventScreenDrag and dragging:
		var sd := event as InputEventScreenDrag
		spin += sd.relative.x * 0.012
		drag_idle = 0.0


# ---------------------------------------------------------------- model

func _rebuild_model() -> void:
	if turntable == null:
		return
	if model != null:
		model.queue_free()
		model = null
	var w: Node3D = Wrestler.new()
	turntable.add_child(w)
	w.setup(str(info["ring_name"]), look.duplicate(true), false)
	w.set("facing", Vector3(0, 0, 1))
	w.set("opponent", dummy_opp)
	model = w
	if anim_changed:
		anim_changed = false
		_pose(Wrestler.S.TAUNT, Wrestler.TAUNT_TIME)
	else:
		_pose(Wrestler.S.IDLE, 3.5)
	var g: Color = look.get("gear", GOLD)
	_tint_rims(g)


func _pose(s: int, secs: float) -> void:
	if model == null:
		return
	model.set("state", s)
	model.set("state_time", 0.0)
	pose_left = secs
	pose_taunt = s != Wrestler.S.IDLE


func _animate_model(dt: float) -> void:
	if turntable == null:
		return
	drag_idle += dt
	if drag_idle > 2.0:
		spin += dt * spin_vel
	turntable.rotation.y = spin
	if model == null:
		return
	pose_left -= dt
	if pose_left <= 0.0:
		if pose_taunt:
			_pose(Wrestler.S.IDLE, randf_range(4.0, 6.0))
		else:
			_pose(Wrestler.S.TAUNT, Wrestler.TAUNT_TIME)
	model.set("state_time", float(model.get("state_time")) + dt)
	model.set("anim_clock", float(model.get("anim_clock")) + dt)
	if model.has_method("_update_pose"):
		model.call("_update_pose", dt)


var rim_l: SpotLight3D
var rim_r: SpotLight3D


func _tint_rims(c: Color) -> void:
	if rim_l == null:
		return
	rim_l.light_color = c.lerp(Color.WHITE, 0.25)
	rim_r.light_color = c.lerp(Color.WHITE, 0.4)


# ---------------------------------------------------------------- 3D view + set

func _build_view() -> void:
	world = Node3D.new()
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 34.0
	camera.near = 0.1
	camera.far = 60.0
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	view = SubViewport.new()
	view.own_world_3d = false
	view.msaa_3d = Viewport.MSAA_2X
	view.handle_input_locally = false
	view.gui_disable_input = true
	view.physics_object_picking = false
	view.positional_shadow_atlas_size = 1024
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
	sh.code = Select.POST_SHADER
	post_mat.shader = sh
	view_rect.material = post_mat
	view_rect.texture = view.get_texture()
	layer.add_child(view_rect)
	view.add_child(camera)
	camera.current = true
	_animate_camera(0.0)


func _update_view_size() -> void:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		win = get_viewport().get_visible_rect().size
	var h := win.y
	if h > 600.0:
		h = clampf(h * 0.6, 540.0, 720.0)
	var w := h * win.x / maxf(win.y, 1.0)
	view.size = Vector2i(maxi(16, roundi(w)), maxi(16, roundi(h)))


func _animate_camera(dt: float) -> void:
	if camera == null:
		return
	var want := 1.0 if TABS[tab] == "HEAD" else 0.0
	cam_zoom = move_toward(cam_zoom, want, dt * 2.5)
	var z := cam_zoom * cam_zoom * (3.0 - 2.0 * cam_zoom)
	var dist := lerpf(5.4, 2.3, z)
	var ty := lerpf(1.0, 1.62, z) + PLAT_H
	var sway := 0.05 * sin(t * 0.21)
	camera.position = Vector3(sway * 3.0, ty + lerpf(0.28, 0.04, z), dist)
	camera.look_at(Vector3(sway, ty, 0.0))
	# Put the fighter in the middle of the space right of the option panel.
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_w := dist * tan(deg_to_rad(camera.fov * 0.5)) * aspect
	var panel_r := (margin.x + PANEL_W) / maxf(vp.x, 1.0)       # 0..1 of the screen
	var centre := (panel_r + 1.0) * 0.5                          # screen fraction for the model
	camera.h_offset = -(centre * 2.0 - 1.0) * half_w


func _mat(c: Color, emissive := false, energy := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


func _add(mesh: Mesh, pos: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	(parent if parent != null else world).add_child(mi)
	return mi


func _floor_tex() -> ImageTexture:
	# Painted garage concrete: mottled grey with oil stains and expansion joints.
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.03
	n.fractal_octaves = 4
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0.2, 0.19, 0.2).lerp(Color(0.32, 0.31, 0.3), v)
			if x % 64 == 0 or y % 64 == 0:
				c = c.darkened(0.45)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_set() -> void:
	var sky_mat := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = Select.SKY_SHADER
	sky_mat.shader = ssh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.42, 0.6)
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.06, 0.1)
	env.fog_density = 0.045
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	# Floor + a back wall of corrugated garage door with a painted stencil stripe.
	var fl := QuadMesh.new()
	fl.size = Vector2(30, 30)
	var fm := _mat(Color.WHITE)
	fm.albedo_texture = _floor_tex()
	fm.uv1_scale = Vector3(10, 10, 1)
	var floor_mi := _add(fl, Vector3.ZERO, fm)
	floor_mi.rotation.x = -PI / 2
	var wall := BoxMesh.new()
	wall.size = Vector3(14, 4.2, 0.2)
	_add(wall, Vector3(0, 2.1, -3.6), _mat(Color(0.14, 0.14, 0.16)))
	for i in 14:
		var rib := BoxMesh.new()
		rib.size = Vector3(14, 0.05, 0.06)
		_add(rib, Vector3(0, 0.3 * float(i) + 0.15, -3.48), _mat(Color(0.2, 0.2, 0.22)))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(14, 0.34, 0.02)
	_add(stripe, Vector3(0, 2.75, -3.44), _mat(Color(0.45, 0.07, 0.05)))
	var sign3 := Label3D.new()
	sign3.text = "CREATE-A-WRESTLER"
	sign3.font = font_i
	sign3.font_size = 96
	sign3.pixel_size = 0.0028
	sign3.modulate = Color(0.75, 0.62, 0.2)
	sign3.outline_size = 0
	sign3.position = Vector3(0.6, 2.75, -3.42)
	world.add_child(sign3)

	# Turntable: a steel disc with marquee bulbs round the rim.
	var disc := CylinderMesh.new()
	disc.top_radius = 1.05
	disc.bottom_radius = 1.12
	disc.height = PLAT_H
	disc.radial_segments = 40
	var dm := _mat(Color(0.2, 0.2, 0.22))
	dm.metallic = 0.6
	dm.roughness = 0.4
	var dmi := _add(disc, Vector3(0, PLAT_H * 0.5, 0), dm)
	dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var top := CylinderMesh.new()
	top.top_radius = 0.98
	top.bottom_radius = 0.98
	top.height = 0.01
	top.radial_segments = 40
	_add(top, Vector3(0, PLAT_H + 0.003, 0), _mat(Color(0.08, 0.08, 0.09)))
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 6
	sm.rings = 3
	bulbs = MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	bulbs.use_colors = true
	bulbs.mesh = sm
	bulbs.instance_count = 30
	for i in 30:
		var a := TAU * float(i) / 30.0
		bulbs.set_instance_transform(i, Transform3D(Basis(), Vector3(cos(a) * 1.085, PLAT_H * 0.55, sin(a) * 1.085)))
		bulbs.set_instance_color(i, GOLD * 2.0)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bulbs
	bmi.material_override = bm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(bmi)

	# Lights: key with shadows, warm fill, two coloured rims (tinted to the signature colour).
	var key := SpotLight3D.new()
	var kpos := Vector3(1.4, 4.6, 3.2)
	key.transform = Transform3D(Basis.looking_at(Vector3(0, 1.0, 0) - kpos), kpos)
	key.spot_angle = 28.0
	key.spot_range = 10.0
	key.light_energy = 4.5
	key.light_color = Color(1.0, 0.95, 0.88)
	key.shadow_enabled = not headless
	key.shadow_bias = 0.04
	key.shadow_normal_bias = 1.0
	key.shadow_blur = 1.5
	world.add_child(key)
	var fill := SpotLight3D.new()
	var fpos := Vector3(-2.0, 2.2, 4.2)
	fill.transform = Transform3D(Basis.looking_at(Vector3(0, 1.2, 0) - fpos), fpos)
	fill.spot_angle = 24.0
	fill.spot_range = 9.0
	fill.light_energy = 1.8
	fill.light_color = Color(1.0, 0.82, 0.62)
	world.add_child(fill)
	rim_l = SpotLight3D.new()
	var lpos := Vector3(-2.4, 3.0, -2.4)
	rim_l.transform = Transform3D(Basis.looking_at(Vector3(0, 1.3, 0) - lpos), lpos)
	rim_l.spot_angle = 26.0
	rim_l.spot_range = 8.0
	rim_l.light_energy = 3.6
	world.add_child(rim_l)
	rim_r = SpotLight3D.new()
	var rpos := Vector3(2.4, 3.2, -2.2)
	rim_r.transform = Transform3D(Basis.looking_at(Vector3(0, 1.3, 0) - rpos), rpos)
	rim_r.spot_angle = 26.0
	rim_r.spot_range = 8.0
	rim_r.light_energy = 3.0
	world.add_child(rim_r)

	# Haze cone under the key light.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = 1.3
	cone.height = 4.6
	cone.radial_segments = 24
	cone.cap_top = false
	cone.cap_bottom = false
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.albedo_color = Color(1.0, 0.85, 0.6, 0.04)
	var haze := _add(cone, Vector3(0, 2.4, 0), hm)
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	turntable = Node3D.new()
	turntable.position = Vector3(0, PLAT_H, 0)
	world.add_child(turntable)
	dummy_opp = Node3D.new()
	dummy_opp.position = Vector3(0, PLAT_H, 3.0)
	world.add_child(dummy_opp)
	_tint_rims(look.get("gear", GOLD))


# ---------------------------------------------------------------- UI

func _label(text: String, font: Font, size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


func _box_style(bg: Color, border: Color, left: int, skew := 0.2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.skew = Vector2(skew, 0.0)
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = left
	sb.border_width_bottom = 3
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _style_button(b: Button, sb: StyleBox) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)


func _text_button(txt: String, size: int) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_i)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	return b


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	head_label = _label("CREATE A WRESTLER", font_i, 40, GOLD, 10)
	ui.add_child(head_label)

	tab_hint_l = _label("L1 / Q", font_b, 15, Color(0.8, 0.8, 0.82), 4)
	ui.add_child(tab_hint_l)
	tab_hint_r = _label("R1 / E", font_b, 15, Color(0.8, 0.8, 0.82), 4)
	ui.add_child(tab_hint_r)
	for i in TABS.size():
		var b := _text_button(TABS[i], 18)
		b.custom_minimum_size = Vector2(0, 36)
		var idx := i
		b.pressed.connect(func():
			if ov == Ov.NONE and not leaving:
				_set_tab(idx)
				_refresh_all())
		ui.add_child(b)
		tab_btns.append(b)

	panel = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.02, 0.02, 0.03, 0.72)
	psb.border_color = RED
	psb.border_width_left = 6
	psb.border_width_bottom = 3
	psb.content_margin_left = 12
	psb.content_margin_right = 8
	psb.content_margin_top = 8
	psb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", psb)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = false
	col.add_child(scroll)
	row_box = VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 4)
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row_box)
	desc_label = _label("", font_b, 16, Color(0.78, 0.78, 0.8), 4)
	col.add_child(desc_label)

	bar_box = HBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 10)
	ui.add_child(bar_box)
	for i in BAR.size():
		var b := _text_button(BAR[i], 22)
		b.custom_minimum_size = Vector2(0, 48)
		var idx := i
		if BAR[i] == "PRESET":
			b.custom_minimum_size = Vector2(300, 48)
		b.pressed.connect(func(): _bar_press(idx))
		bar_box.add_child(b)
		bar_btns.append(b)

	hint_label = _label("ARROWS / WASD  move + change     ENTER / J  select     Q / E  tabs     R  randomize     ESC / K  back",
		font_b, 15, Color(0.72, 0.72, 0.75), 4)
	ui.add_child(hint_label)

	tag_box = VBoxContainer.new()
	tag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag_box.add_theme_constant_override("separation", 0)
	ui.add_child(tag_box)
	tag_name = _label("", font_i, 44, PAPER, 11)
	tag_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag_box.add_child(tag_name)
	tag_sub = _label("", font_b, 17, GOLD, 5)
	tag_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tag_box.add_child(tag_sub)
	drag_hint = _label("DRAG TO SPIN", font_b, 14, Color(0.7, 0.7, 0.74, 0.8), 4)
	ui.add_child(drag_hint)

	flash_label = _label("", font_i, 46, GOLD, 12)
	flash_label.visible = false
	ui.add_child(flash_label)

	# overlay
	ov_dim = ColorRect.new()
	ov_dim.color = Color(0, 0, 0.02, 0.55)
	ov_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ov_dim.visible = false
	ov_dim.gui_input.connect(func(ev: InputEvent):
		var mb := ev as InputEventMouseButton
		if mb != null and mb.pressed and ov == Ov.PAL:
			_close_overlay())
	ui.add_child(ov_dim)
	ov_panel = PanelContainer.new()
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0.03, 0.03, 0.04, 0.96)
	osb.border_color = GOLD
	osb.border_width_left = 8
	osb.border_width_top = 3
	osb.border_width_right = 3
	osb.border_width_bottom = 3
	osb.content_margin_left = 22
	osb.content_margin_right = 22
	osb.content_margin_top = 14
	osb.content_margin_bottom = 14
	ov_panel.add_theme_stylebox_override("panel", osb)
	ov_panel.visible = false
	ui.add_child(ov_panel)
	var ocol := VBoxContainer.new()
	ocol.add_theme_constant_override("separation", 8)
	ov_panel.add_child(ocol)
	ov_title = _label("", font_i, 30, GOLD, 8)
	ocol.add_child(ov_title)
	ov_textl = _label("", font_i, 40, PAPER, 9)
	ov_textl.custom_minimum_size = Vector2(0, 52)
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	tsb.border_color = RED
	tsb.border_width_bottom = 3
	tsb.content_margin_left = 12
	ov_textl.add_theme_stylebox_override("normal", tsb)
	ocol.add_child(ov_textl)
	ov_grid = VBoxContainer.new()
	ov_grid.add_theme_constant_override("separation", 6)
	ov_grid.custom_minimum_size = Vector2(560, 0)
	ocol.add_child(ov_grid)
	ov_foot = _label("", font_b, 16, Color(0.75, 0.75, 0.78), 4)
	ocol.add_child(ov_foot)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	ui.add_child(fade_rect)


func _safe_margins() -> Vector4:
	var vp := get_viewport().get_visible_rect().size
	var l := 0.0
	var tp := 0.0
	var r := 0.0
	var b := 0.0
	if OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android"):
		var win := Vector2(DisplayServer.window_get_size())
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		if win.x > 0.0 and win.y > 0.0 and safe.size.x > 0 and safe.size.y > 0:
			var k := vp / win
			l = float(safe.position.x) * k.x
			tp = float(safe.position.y) * k.y
			r = (win.x - float(safe.position.x + safe.size.x)) * k.x
			b = (win.y - float(safe.position.y + safe.size.y)) * k.y
	var side := maxf(maxf(l, r), 40.0)
	return Vector4(side, maxf(tp, 14.0), side, maxf(b, 12.0))


func _relayout() -> void:
	if view != null:
		_update_view_size()
	var vp := get_viewport().get_visible_rect().size
	margin = _safe_margins()
	var m := margin
	head_label.reset_size()
	head_label.position = Vector2(m.x, m.y)

	# tabs row
	var x := m.x
	var ty := m.y + 54.0
	tab_hint_l.reset_size()
	tab_hint_l.position = Vector2(x, ty + 9.0)
	x += tab_hint_l.size.x + 8.0
	for b in tab_btns:
		b.reset_size()
		b.size = Vector2(b.get_combined_minimum_size().x, 36)
		b.position = Vector2(x, ty)
		x += b.size.x + 4.0
	tab_hint_r.reset_size()
	tab_hint_r.position = Vector2(x + 4.0, ty + 9.0)

	# bottom bar + hint
	hint_label.reset_size()
	hint_label.position = Vector2(m.x, vp.y - m.w - hint_label.size.y)
	bar_box.reset_size()
	var bs := bar_box.get_combined_minimum_size()
	bar_box.size = bs
	bar_box.position = Vector2(m.x, hint_label.position.y - bs.y - 6.0)

	var top := ty + 46.0
	panel.position = Vector2(m.x, top)
	panel.size = Vector2(PANEL_W, maxf(140.0, bar_box.position.y - 10.0 - top))

	_relayout_tag()
	drag_hint.reset_size()
	drag_hint.position = Vector2(vp.x - m.z - drag_hint.size.x, top)

	if ov_panel.visible:
		ov_panel.reset_size()
		var osz := ov_panel.get_combined_minimum_size()
		ov_panel.size = osz
		ov_panel.position = Vector2(maxf(m.x, (m.x + PANEL_W + 20.0) * 0.5 - osz.x * 0.5 + 40.0), (vp.y - osz.y) * 0.5)
		ov_panel.position.x = clampf(ov_panel.position.x, m.x, vp.x - m.z - osz.x)
	_relayout_flash()


func _relayout_tag() -> void:
	if tag_box == null or bar_box == null:
		return
	var vp := get_viewport().get_visible_rect().size
	tag_box.reset_size()
	var tsz := tag_box.get_combined_minimum_size()
	tag_box.size = Vector2(maxf(tsz.x, 300.0), tsz.y)
	tag_box.position = Vector2(vp.x - margin.z - tag_box.size.x, bar_box.position.y + bar_box.size.y - tsz.y)


func _relayout_flash() -> void:
	if flash_label == null:
		return
	var vp := get_viewport().get_visible_rect().size
	flash_label.reset_size()
	var fs := flash_label.get_combined_minimum_size()
	var cx := (margin.x + PANEL_W + vp.x) * 0.5
	flash_label.position = Vector2(cx - fs.x * 0.5, vp.y * 0.3)

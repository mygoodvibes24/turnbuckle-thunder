extends Node3D
## City 2 City Wrestling - Backyard Brawl: CHARACTER SELECT.
##
## title.tscn -> START BRAWL -> select.tscn -> main.tscn. Built in code like the title: a small
## spotlit stage (an old cable-spool platform with marquee bulbs, speaker stacks, string lights)
## in the backyard at night, rendered through the same grade/bloom post pass, with the
## highlighted fighter's 3D model on a slow turntable. Over it: portrait cards (+ RANDOM),
## name / genre / bio, POWER-AIR-FLOW-GRIT bars, BACK and a big CONFIRM.
## Step 1: PLAYER 1 picks. Step 2: the CPU OPPONENT (or RANDOM). Step 3: the STAGE (a level from
## scripts/levels/catalog.gd, or RANDOM; Game.level_id). Then a VS splash and the match.
## The picks go to the "Game" autoload (scripts/game_state.gd), so REMATCH keeps them.
## Keyboard (arrows/WASD, Enter/Space/J confirm, Esc/K back), gamepad (d-pad/stick, A/B) and
## touch (tap a card to highlight it, tap it again or CONFIRM to pick).
## Models are built lazily (the highlighted one first, then the rest one per frame in the
## background) and cached, so switching is instant after the first pass. Only one is visible.

const Wrestler := preload("res://scripts/wrestler.gd")
const Roster := preload("res://scripts/roster.gd")
const Audio := preload("res://scripts/audio.gd")
const Music := preload("res://scripts/music.gd")
const Catalog := preload("res://scripts/levels/catalog.gd")
const MATCH_SCENE := "res://main.tscn"
const TITLE_SCENE := "res://title.tscn"

enum Phase { PICK_P1, PICK_CPU, PICK_STAGE, READY, LEAVING }

const GOLD := Color(1.0, 0.82, 0.12)
const RED := Color(0.86, 0.12, 0.08)
const CPU_BLUE := Color(0.2, 0.55, 1.0)
const STAT_COLS := [Color(0.95, 0.22, 0.12), Color(0.2, 0.8, 1.0), Color(1.0, 0.8, 0.15), Color(1.0, 0.5, 0.12)]
const CARD_W := 96.0
const CARD_H := 132.0
const CARD_GAP := 8.0
const PLAT_H := 0.24          # platform top: the fighter stands on it

var phase: int = Phase.PICK_P1
var t := 0.0
var start_ms := 0
var frames := 0
var headless := false
var lock_until_ms := 0      # wall clock: confirm/back ignored until then (also eats duplicate key events)
var stick_armed := true
var sel := 0                  # highlighted card (Roster.count() = RANDOM)
var p1_idx := 0
var p2_idx := 1
var shown_idx := -1           # whose model is on the turntable (-1: none)
var fade_3d := 0.0
var set_t := -1.0
var shake := 0.0
var load_step := 0
var ready_t := 0.0
var game: Node = null

# 3D
var world: Node3D
var camera: Camera3D
var view: SubViewport
var view_rect: TextureRect
var post_mat: ShaderMaterial
var turntable: Node3D
var dummy_opp: Node3D
var models := {}              # id -> wrestler Node3D (cached, hidden when not shown)
var plan := {"seq": [], "i": 0, "left": 0.0}
var model_pop := 1.0
var rim_l: SpotLight3D
var rim_r: SpotLight3D
var bulbs: MultiMesh
var bulb_n := 0
var question: Label3D

# audio
var audio: Node = null
var music: Node = null

# UI
var ui: Control
var font_i: FontVariation
var font_b: FontVariation
var head_label: Label
var step_label: Label
var step_box: PanelContainer
var info_box: VBoxContainer
var name_label: Label
var genre_label: Label
var genre_box: PanelContainer
var bio_label: Label
var sig_label: Label
var stat_segs: Array = []     # per stat: Array of 10 ColorRects
var stat_vals: Array[Label] = []
var stat_disp: Array[float] = [0.0, 0.0, 0.0, 0.0]
var stat_target: Array[float] = [0.0, 0.0, 0.0, 0.0]
var card_row: Control
var cards: Array[Button] = []
var card_p1_tags: Array[Label] = []
var card_cpu_tags: Array[Label] = []
var confirm_btn: Button
var back_btn: Button
var hint_label: Label
var vs_band: Control
var vs_label: Label
var fade_rect: ColorRect
var loading_label: Label
var margin := Vector4(60, 36, 60, 36)

const SKY_SHADER := """
shader_type sky;

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -0.2, 1.0);
	vec3 col = mix(vec3(0.13, 0.08, 0.2), vec3(0.015, 0.02, 0.07), smoothstep(0.0, 0.5, h));
	vec3 cell = floor(d * 260.0);
	float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float star = step(0.992, r) * smoothstep(0.03, 0.2, d.y);
	col += vec3(0.9, 0.9, 1.0) * star * (0.4 + 0.6 * fract(r * 91.7));
	COLOR = col;
}
"""

# Same grade as title.gd (bilinear upscale, sharpen, cheap bloom, contrast/saturation, split
# toning, vignette) with a fade from a dark backdrop.
const POST_SHADER := """
shader_type canvas_item;

uniform float contrast = 1.12;
uniform float saturation = 1.15;
uniform float sharpen = 0.14;
uniform float bloom_threshold = 0.66;
uniform float bloom_strength = 0.7;
uniform float bloom_radius = 5.0;
uniform vec3 shadow_tint = vec3(0.90, 0.97, 1.10);
uniform vec3 highlight_tint = vec3(1.08, 1.01, 0.88);
uniform float vignette = 0.42;
uniform float fade = 0.0;

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
	float vig = 1.0 - vignette * smoothstep(0.3, 1.0, dot(v, v));
	vec3 back = mix(vec3(0.05, 0.035, 0.06), vec3(0.012, 0.012, 0.025), length(v));
	COLOR = vec4(clamp(mix(back, c * vig, fade), 0.0, 1.0), 1.0);
}
"""


func _ready() -> void:
	Engine.time_scale = 1.0
	randomize()
	start_ms = Time.get_ticks_msec()
	headless = DisplayServer.get_name() == "headless"
	game = get_node_or_null("/root/Game")
	if game != null:
		p1_idx = maxi(0, Roster.index_of(str(game.get("p1_id"))))
		p2_idx = maxi(0, Roster.index_of(str(game.get("p2_id"))))
	if p2_idx == p1_idx:
		p2_idx = (p1_idx + 1) % Roster.count()
	sel = p1_idx
	_lock(0.5)   # the title's confirm press must not also pick a fighter
	font_b = FontVariation.new()
	font_b.base_font = ThemeDB.fallback_font
	font_b.variation_embolden = 1.1
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.2
	font_i.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.24, 1), Vector2.ZERO)
	_build_view()
	_build_ui()
	_relayout()
	_refresh_info(true)
	_refresh_cards()
	get_viewport().size_changed.connect(_relayout)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	frames += 1
	var prev_t := t
	t = float(Time.get_ticks_msec() - start_ms) / 1000.0
	var dt := clampf(t - prev_t, 0.0, 0.1)

	# Headless (CI smoke test): exercise the screen (models get built) and the stage step, then
	# pick two of the new fighters and go on to the match so main.gd's roster path is exercised too.
	if headless and frames == 60 and phase != Phase.LEAVING:
		_enter_stage()
	if headless and frames == 90 and phase != Phase.LEAVING:
		phase = Phase.LEAVING
		if game != null:
			game.set("p1_id", "booker")
			game.set("p2_id", "starla")
			game.set("level_id", "backyard")
		print("select (headless): %d models built, on to the match" % models.size())
		get_tree().change_scene_to_file(MATCH_SCENE)
		return

	_staged_load()
	_animate_camera(dt)
	_animate_model(dt)
	_animate_stage(dt)
	_animate_ui(dt)

	var f := 0.0
	if set_t >= 0.0:
		f = _smooth((t - set_t) / 0.45)
	fade_3d = maxf(fade_3d, f)
	if phase == Phase.LEAVING:
		fade_3d = maxf(0.0, fade_3d - dt * 2.0)
	post_mat.set_shader_parameter("fade", fade_3d)

	if phase == Phase.READY and t - ready_t > 1.5:
		_leave(MATCH_SCENE)

	shake = maxf(0.0, shake - dt * 3.0)
	var s := shake * shake
	ui.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 10.0 * s


func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _staged_load() -> void:
	# Frame 1 shows the UI; then one heavy step per frame: the set, the highlighted model,
	# sound, then the remaining models one per frame in the background.
	if frames < 2:
		return
	match load_step:
		0:
			_build_set()
			set_t = t
		1:
			_show_model(sel)
		2:
			audio = Audio.new()      # clips are cached from the title: cheap here
			add_child(audio)
		3:
			music = Music.new()
			add_child(music)
			if not headless:
				music.call("start")
		_:
			# Background prebuild, nearest cards first.
			var n := Roster.count()
			for k in n:
				var i: int = posmod(sel + (k + 1) / 2 * (1 if k % 2 == 1 else -1), n)
				var e: Dictionary = Roster.ROSTER[i]
				if not models.has(str(e["id"])):
					_model_for(i)
					break
	load_step += 1


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if headless or phase == Phase.READY or phase == Phase.LEAVING:
		return
	var confirm := false
	var back := false
	var dir := 0
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed:
			return
		var code := k.physical_keycode
		if k.echo:
			dir = _key_dir(code)
			if dir != 0 and not _locked():
				_move_sel(dir)
				get_viewport().set_input_as_handled()
			return
		if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J, KEY_Z]:
			confirm = true
		elif code in [KEY_ESCAPE, KEY_BACKSPACE, KEY_K, KEY_X]:
			back = true
		else:
			dir = _key_dir(code)
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_A, JOY_BUTTON_START:
				confirm = true
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				back = true
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP:
				dir = -1
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN:
				dir = 1
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_X:
			if absf(jm.axis_value) < 0.3:
				stick_armed = true
			elif absf(jm.axis_value) > 0.6 and stick_armed:
				stick_armed = false
				dir = 1 if jm.axis_value > 0.0 else -1
	else:
		return   # mouse / touch: the cards and buttons handle those
	if _locked():
		return
	if dir != 0:
		_move_sel(dir)
		_lock(0.1)
		get_viewport().set_input_as_handled()
	elif confirm:
		get_viewport().set_input_as_handled()
		_confirm()
	elif back:
		get_viewport().set_input_as_handled()
		_back()


func _lock(secs: float) -> void:
	lock_until_ms = Time.get_ticks_msec() + int(secs * 1000.0)


func _locked() -> bool:
	return Time.get_ticks_msec() < lock_until_ms or frames < 3


func _key_dir(code: int) -> int:
	if code in [KEY_LEFT, KEY_A, KEY_UP, KEY_W]:
		return -1
	if code in [KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S]:
		return 1
	return 0


func _snd(n: String, db := 0.0, var_amt := 0.05) -> void:
	if audio != null:
		var clips: Dictionary = audio.get("clips")
		if clips.has(n):
			audio.call("play", n, db, var_amt)


func _move_sel(dir: int) -> void:
	if phase == Phase.PICK_STAGE:
		_set_stage(posmod(stage_sel + dir, stages.size() + 1))
		return
	_set_sel(posmod(sel + dir, Roster.count() + 1))


func _set_sel(i: int) -> void:
	if i == sel:
		return
	sel = i
	_snd("trick", -12.0, 0.0)
	_show_model(sel)
	_refresh_info(false)
	_refresh_cards()


func _on_card(i: int) -> void:
	if headless or _locked() or not (phase == Phase.PICK_P1 or phase == Phase.PICK_CPU):
		return
	if i == sel:
		_confirm()
	else:
		_set_sel(i)


func _on_confirm_btn() -> void:
	if headless or _locked() or not (phase == Phase.PICK_P1 or phase == Phase.PICK_CPU or phase == Phase.PICK_STAGE):
		return
	_confirm()


func _on_back_btn() -> void:
	if headless or _locked() or not (phase == Phase.PICK_P1 or phase == Phase.PICK_CPU or phase == Phase.PICK_STAGE):
		return
	_back()


func _confirm() -> void:
	if phase == Phase.PICK_STAGE:
		_confirm_stage()
		return
	var n := Roster.count()
	var pick := sel
	if phase == Phase.PICK_P1:
		if pick >= n:
			pick = randi() % n
		p1_idx = pick
		if game != null:
			game.set("p1_id", str(Roster.ROSTER[p1_idx]["id"]))
		phase = Phase.PICK_CPU
		_lock(0.35)
		shake = maxf(shake, 0.5)
		_snd("big_thud", -6.0)
		_snd("cheer_small", -12.0)
		if p2_idx == p1_idx:
			p2_idx = (p1_idx + 1) % n
		sel = p2_idx
		_show_model(sel)
		_refresh_info(false)
		_refresh_cards()
		_relayout()
	elif phase == Phase.PICK_CPU:
		if pick >= n:
			pick = (p1_idx + 1 + randi() % (n - 1)) % n
		elif pick == p1_idx:
			# No mirror matches: shake the card and stay.
			shake = maxf(shake, 0.35)
			_snd("whoosh", -8.0)
			return
		p2_idx = pick
		if game != null:
			game.set("p2_id", str(Roster.ROSTER[p2_idx]["id"]))
		sel = p2_idx
		_show_model(sel)
		_refresh_cards()
		_snd("big_thud", -8.0)
		_enter_stage()   # step 3: where the fight happens


func _back() -> void:
	if phase == Phase.PICK_STAGE:
		phase = Phase.PICK_CPU
		_lock(0.35)
		_leave_stage()
		sel = p2_idx
		_snd("whoosh", -8.0)
		_show_model(sel)
		_refresh_info(false)
		_refresh_cards()
		_relayout()
	elif phase == Phase.PICK_CPU:
		phase = Phase.PICK_P1
		_lock(0.35)
		sel = p1_idx
		_snd("whoosh", -8.0)
		_show_model(sel)
		_refresh_info(false)
		_refresh_cards()
		_relayout()
	elif phase == Phase.PICK_P1:
		_snd("whoosh", -6.0)
		_leave(TITLE_SCENE)


func _go_ready() -> void:
	phase = Phase.READY
	ready_t = t
	shake = maxf(shake, 0.8)
	_snd("punch", -2.0)
	if audio != null:
		audio.call("ring_bell", 2)
	var a: Dictionary = Roster.ROSTER[p1_idx]
	var b: Dictionary = Roster.ROSTER[p2_idx]
	vs_label.text = "%s   VS   %s" % [a["display_name"], b["display_name"]]
	vs_band.visible = true
	vs_band.modulate.a = 0.0
	vs_band.scale = Vector2(1.0, 0.2)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(vs_band, "modulate:a", 1.0, 0.15)
	tw.tween_property(vs_band, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var w := _shown_model()
	if w != null:
		_start_state(w, Wrestler.S.WIN)
		plan = {"seq": [[Wrestler.S.WIN, 9.0]], "i": 0, "left": 9.0}
	_relayout()


func _leave(scene: String) -> void:
	if phase == Phase.LEAVING:
		return
	phase = Phase.LEAVING
	if music != null:
		music.call("fade_out", 0.4)
	fade_rect.visible = true
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.4)
	if scene == MATCH_SCENE:
		tw.tween_callback(func(): loading_label.visible = true)
		tw.tween_interval(0.12)   # let "LOADING" reach the screen before the blocking build
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene))


# ---------------------------------------------------------------- the model on the turntable

func _model_for(i: int) -> Node3D:
	var e: Dictionary = Roster.ROSTER[i]
	var id := str(e["id"])
	if models.has(id):
		return models[id]
	var w: Node3D = Wrestler.new()
	w.visible = false
	turntable.add_child(w)
	var look: Dictionary = e["look"]
	w.setup(str(e["display_name"]), look.duplicate(true), false)
	w.set("facing", Vector3(0, 0, 1))
	w.set("opponent", dummy_opp)   # harmless: a few pose helpers read the opponent's position
	models[id] = w
	return w


func _shown_model() -> Node3D:
	if shown_idx < 0:
		return null
	var e: Dictionary = Roster.ROSTER[shown_idx]
	var id := str(e["id"])
	if models.has(id):
		return models[id]
	return null


func _show_model(i: int) -> void:
	if turntable == null:
		return   # the set isn't built yet; _staged_load shows it
	var old := _shown_model()
	if old != null:
		old.visible = false
	question.visible = i >= Roster.count()
	if i >= Roster.count():
		shown_idx = -1
		_tint_rims(GOLD)
		return
	shown_idx = i
	var w := _model_for(i)
	w.visible = true
	turntable.rotation.y = 0.5
	model_pop = 0.0
	_start_state(w, Wrestler.S.TAUNT)
	plan = {"seq": [[Wrestler.S.TAUNT, Wrestler.TAUNT_TIME], [Wrestler.S.IDLE, 3.2],
		[Wrestler.S.TAUNT, Wrestler.TAUNT_TIME], [Wrestler.S.IDLE, 4.0]], "i": 0, "left": Wrestler.TAUNT_TIME}
	var e: Dictionary = Roster.ROSTER[i]
	var look: Dictionary = e["look"]
	_tint_rims(look.get("gear", GOLD))


func _start_state(w: Node3D, s: int) -> void:
	w.set("state", s)
	w.set("state_time", 0.0)


func _animate_model(dt: float) -> void:
	if turntable == null:
		return
	turntable.rotation.y += dt * 0.45
	model_pop = minf(1.0, model_pop + dt * 5.0)
	var k := 1.0 - pow(1.0 - model_pop, 3.0)
	turntable.scale = Vector3.ONE * lerpf(0.9, 1.0, k)
	if question != null and question.visible:
		question.position.y = 1.25 + 0.06 * sin(t * 3.0)
	var w := _shown_model()
	if w == null:
		return
	var left: float = float(plan["left"]) - dt
	if left <= 0.0:
		var seq: Array = plan["seq"]
		var ni: int = (int(plan["i"]) + 1) % seq.size()
		plan["i"] = ni
		var step: Array = seq[ni]
		left = float(step[1])
		_start_state(w, int(step[0]))
	plan["left"] = left
	w.set("state_time", float(w.get("state_time")) + dt)
	w.set("anim_clock", float(w.get("anim_clock")) + dt)
	if w.has_method("_update_pose"):
		w.call("_update_pose", dt)


func _tint_rims(c: Color) -> void:
	if rim_l == null:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(rim_l, "light_color", c.lerp(Color.WHITE, 0.2), 0.25)
	tw.tween_property(rim_r, "light_color", c.lerp(Color.WHITE, 0.35), 0.25)


# ---------------------------------------------------------------- 3D view + set

func _build_view() -> void:
	world = Node3D.new()
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 36.0
	camera.near = 0.1
	camera.far = 60.0
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	view = SubViewport.new()
	view.own_world_3d = false
	view.msaa_3d = Viewport.MSAA_2X
	view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	view.handle_input_locally = false
	view.gui_disable_input = true
	view.physics_object_picking = false
	view.audio_listener_enable_3d = true
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
	sh.code = POST_SHADER
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


func _animate_camera(_dt: float) -> void:
	if camera == null:
		return
	var sway := 0.06 * sin(t * 0.21)
	camera.position = Vector3(sway * 4.0, 1.28 + 0.04 * sin(t * 0.17), 5.2)
	camera.look_at(Vector3(sway, 0.98, 0.0))
	# Put the fighter on the right ~2/3 of the screen (the info column is on the left).
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var half_w := 5.2 * tan(deg_to_rad(camera.fov * 0.5)) * aspect
	camera.h_offset = -0.36 * half_w
	var s := shake * shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.04 * s


func _mat(c: Color, emissive := false, energy := 1.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	return m


func _tex_mat(tex: Texture2D, tint := Color.WHITE, uv := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.92
	m.uv1_scale = uv
	return m


func _add(mesh: Mesh, pos: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = m
	if parent == null:
		parent = world
	parent.add_child(mi)
	return mi


func _box(size: Vector3, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var mi := _add(b, pos, m)
	mi.rotation.y = yaw
	return mi


func _quad(size: Vector2, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := _add(q, pos, m)
	mi.rotation.y = yaw
	return mi


var _halo: ImageTexture = null


func _halo_tex() -> ImageTexture:
	if _halo != null:
		return _halo
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.2)))
	img.generate_mipmaps()
	_halo = ImageTexture.create_from_image(img)
	return _halo


func _glow(pos: Vector3, size: float, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _halo_tex()
	m.albedo_color = col
	var mi := _quad(Vector2(size, size), pos, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _noise_img(w: int, h: int, freq: float, octaves := 3) -> Image:
	var fn := FastNoiseLite.new()
	fn.seed = randi()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = octaves
	return fn.get_seamless_image(w, h)


func _grass_tex() -> ImageTexture:
	var n := 128
	var clump := _noise_img(n, n, 0.05, 3)
	var fine := _noise_img(n, n, 0.4, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := clump.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var g := 0.5 + (c - 0.5) * 0.5 + (f - 0.5) * 0.45
			var dry := smoothstep(0.62, 0.8, c)
			var col := Color(0.22, 0.36, 0.12).lerp(Color(0.42, 0.4, 0.2), dry) * (0.6 + g * 0.8)
			col.a = 1.0
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _fence_tex() -> ImageTexture:
	var n := 128
	var nz := _noise_img(n, n, 0.06, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var board := n / 7.0
	for y in n:
		for x in n:
			var w := nz.get_pixel(x, y).r
			var bi := int(x / board)
			var bx := fmod(x, board)
			var g := 0.74 + 0.06 * sin(x * 1.7 + w * 9.0 + bi * 3.0) + (w - 0.5) * 0.16 + 0.05 * sin(bi * 12.9)
			g -= 0.18 * smoothstep(0.6, 1.0, float(y) / n)
			if bx < 1.2:
				g *= 0.25
			elif bx < 2.2:
				g *= 0.75
			img.set_pixel(x, y, Color(g * 0.62, g * 0.5, g * 0.38))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _plank_tex() -> ImageTexture:
	# Cable-spool top: weathered plywood rings with grain, scuffs and old paint.
	var n := 128
	var nz := _noise_img(n, n, 0.09, 3)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := nz.get_pixel(x, y).r
			var r := Vector2(x - n * 0.5, y - n * 0.5).length()
			var g := 0.62 + 0.08 * sin(r * 0.9 + v * 6.0) + (v - 0.5) * 0.3
			if fmod(float(y), 32.0) < 1.2:
				g *= 0.4   # plank seams
			var c := Color(0.5 * g, 0.36 * g, 0.24 * g)
			if r > n * 0.47:
				c = c.darkened(0.5)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _speaker_tex() -> ImageTexture:
	# Front of a beat-up speaker cabinet: black felt, two cones, a woofer and a tweeter.
	var w := 64
	var h := 96
	var nz := _noise_img(w, h, 0.3, 2)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var cones := [[Vector2(32, 64), 22.0], [Vector2(32, 22), 12.0]]
	for y in h:
		for x in w:
			var g := 0.07 + (nz.get_pixel(x, y).r - 0.5) * 0.04
			var c := Color(g, g, g * 1.05)
			for cone: Array in cones:
				var ctr: Vector2 = cone[0]
				var rad: float = cone[1]
				var d := Vector2(x, y).distance_to(ctr) / rad
				if d < 1.0:
					var ring := 0.16 if d > 0.86 else (0.05 + 0.12 * (1.0 - d))
					if d < 0.25:
						ring = 0.22
					c = Color(ring, ring, ring * 1.05)
			if x < 3 or x > w - 4 or y < 3 or y > h - 4:
				c = Color(0.18, 0.18, 0.19)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_set() -> void:
	var sky_mat := ShaderMaterial.new()
	var ssh := Shader.new()
	ssh.code = SKY_SHADER
	sky_mat.shader = ssh
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.66)
	env.ambient_light_energy = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.08, 0.15)
	env.fog_density = 0.03
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.transform = Transform3D(Basis.looking_at(Vector3(0.4, -0.55, 0.75)), Vector3(0, 10, 0))
	moon.light_color = Color(0.58, 0.68, 1.0)
	moon.light_energy = 0.4
	world.add_child(moon)

	# Lawn, back fence with posts, a house wall with a porch light off to the left.
	var lawn := _quad(Vector2(40, 40), Vector3.ZERO, _tex_mat(_grass_tex(), Color(0.9, 0.95, 0.9), Vector3(26, 26, 1)))
	lawn.rotation.x = -PI / 2
	var fh := 1.9
	var back_z := -3.4
	_quad(Vector2(16, fh), Vector3(0.0, fh * 0.5, back_z), _tex_mat(_fence_tex(), Color(0.85, 0.85, 0.85), Vector3(16, 1, 1)))
	var post_m := _mat(Color(0.3, 0.24, 0.18))
	for i in 9:
		_box(Vector3(0.12, fh + 0.12, 0.12), Vector3(-8.0 + i * 2.0, (fh + 0.12) * 0.5, back_z + 0.08), post_m)
	_box(Vector3(16, 0.09, 0.05), Vector3(0.0, fh - 0.3, back_z + 0.05), post_m)
	_box(Vector3(0.16, 0.22, 0.16), Vector3(-4.6, 2.3, back_z + 0.12), _mat(Color(1.0, 0.85, 0.55), true, 3.0))
	_glow(Vector3(-4.6, 2.3, back_z + 0.3), 1.4, Color(1.0, 0.7, 0.4, 0.55))
	var porch := OmniLight3D.new()
	porch.position = Vector3(-4.4, 2.2, back_z + 0.5)
	porch.omni_range = 5.5
	porch.light_energy = 1.4
	porch.light_color = Color(1.0, 0.72, 0.42)
	world.add_child(porch)

	# The platform: an old cable spool lying flat, marquee bulbs round its rim.
	var spool := CylinderMesh.new()
	spool.top_radius = 1.25
	spool.bottom_radius = 1.25
	spool.height = PLAT_H
	spool.radial_segments = 36
	var plat := _add(spool, Vector3(0, PLAT_H * 0.5, 0), _tex_mat(_plank_tex()))
	plat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var rim_band := CylinderMesh.new()
	rim_band.top_radius = 1.27
	rim_band.bottom_radius = 1.27
	rim_band.height = 0.07
	rim_band.radial_segments = 36
	rim_band.cap_top = false
	rim_band.cap_bottom = false
	var band_m := _mat(Color(0.12, 0.1, 0.09))
	band_m.metallic = 0.5
	_add(rim_band, Vector3(0, PLAT_H * 0.5, 0), band_m)
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	sm.radial_segments = 6
	sm.rings = 3
	bulbs = MultiMesh.new()
	bulbs.transform_format = MultiMesh.TRANSFORM_3D
	bulbs.use_colors = true
	bulbs.mesh = sm
	bulb_n = 28
	bulbs.instance_count = bulb_n
	for i in bulb_n:
		var a := TAU * float(i) / float(bulb_n)
		bulbs.set_instance_transform(i, Transform3D(Basis(), Vector3(sin(a) * 1.3, PLAT_H * 0.5, cos(a) * 1.3)))
		bulbs.set_instance_color(i, Color(1.0, 0.8, 0.4))
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	bm.vertex_color_is_srgb = true
	var bmi := MultiMeshInstance3D.new()
	bmi.multimesh = bulbs
	bmi.material_override = bm
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(bmi)

	# Speaker stacks either side, a lawn chair and a cooler for the backyard feel.
	var spk := _tex_mat(_speaker_tex())
	var cab := _mat(Color(0.06, 0.06, 0.065))
	for sx in [-1.0, 1.0]:
		var x: float = sx * 2.35
		for k in 2:
			var y := 0.5 + k * 1.0
			var yaw: float = -sx * 0.35
			_box(Vector3(0.66, 0.98, 0.5), Vector3(x, y, -1.3), cab, yaw)
			var front := _quad(Vector2(0.62, 0.94), Vector3(x, y, -1.3) + Vector3(sin(yaw), 0, cos(yaw)) * 0.252, spk, yaw)
			front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cooler := _box(Vector3(0.6, 0.4, 0.38), Vector3(-1.6, 0.2, 1.1), _mat(Color(0.75, 0.12, 0.1)), 0.4)
	cooler.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(0.62, 0.06, 0.4), Vector3(-1.6, 0.43, 1.1), _mat(Color(0.92, 0.92, 0.9)), 0.4)

	# Lights: a hard overhead spot on the platform (the only shadow), a warm front fill and two
	# coloured rim spots that take the highlighted fighter's signature colour.
	var key := SpotLight3D.new()
	var kpos := Vector3(0.6, 5.6, 2.2)
	key.transform = Transform3D(Basis.looking_at(Vector3(0, 0.8, 0) - kpos), kpos)
	key.spot_angle = 22.0
	key.spot_angle_attenuation = 0.7
	key.spot_range = 12.0
	key.light_energy = 7.0
	key.light_color = Color(1.0, 0.88, 0.7)
	key.shadow_enabled = true
	key.shadow_bias = 0.06
	key.shadow_normal_bias = 1.0
	key.shadow_blur = 1.5
	key.shadow_opacity = 0.75
	world.add_child(key)
	var fill := SpotLight3D.new()
	var fpos := Vector3(-1.8, 2.4, 4.4)
	fill.transform = Transform3D(Basis.looking_at(Vector3(0, 1.2, 0) - fpos), fpos)
	fill.spot_angle = 22.0
	fill.spot_range = 9.0
	fill.light_energy = 1.8
	fill.light_color = Color(1.0, 0.82, 0.62)
	world.add_child(fill)
	rim_l = SpotLight3D.new()
	var lpos := Vector3(-2.4, 3.0, -2.6)
	rim_l.transform = Transform3D(Basis.looking_at(Vector3(0, 1.3, 0) - lpos), lpos)
	rim_l.spot_angle = 26.0
	rim_l.spot_range = 8.0
	rim_l.light_energy = 4.0
	world.add_child(rim_l)
	rim_r = SpotLight3D.new()
	var rpos := Vector3(2.4, 3.2, -2.4)
	rim_r.transform = Transform3D(Basis.looking_at(Vector3(0, 1.3, 0) - rpos), rpos)
	rim_r.spot_angle = 26.0
	rim_r.spot_range = 8.0
	rim_r.light_energy = 3.2
	world.add_child(rim_r)
	for p: Vector3 in [lpos, rpos]:
		_glow(p, 1.2, Color(1.0, 0.9, 0.75, 0.5))
		_box(Vector3(0.3, 0.22, 0.2), p + Vector3(0, 0.05, -0.1), _mat(Color(0.1, 0.1, 0.11)))

	# Haze cone under the key light.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = 1.45
	cone.height = 5.0
	cone.radial_segments = 24
	cone.cap_top = false
	cone.cap_bottom = false
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.albedo_color = Color(1.0, 0.85, 0.6, 0.045)
	var haze := _add(cone, Vector3(0, 2.6, 0), hm)
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow(Vector3(0.0, 5.2, 0.4), 1.6, Color(1.0, 0.9, 0.7, 0.6))

	# String lights along the fence top.
	var cols: Array[Color] = [Color(1.0, 0.75, 0.42), Color(0.85, 0.3, 0.2), Color(0.45, 0.7, 0.4),
		Color(0.45, 0.55, 0.95), Color(1.0, 0.55, 0.2)]
	var lm := MultiMesh.new()
	lm.transform_format = MultiMesh.TRANSFORM_3D
	lm.use_colors = true
	lm.mesh = sm
	lm.instance_count = 26
	for i in 26:
		var u := float(i) / 25.0
		var x := lerpf(-7.0, 7.0, u)
		var y := 2.9 - 0.5 * sin(fmod(u * 4.0, 1.0) * PI)
		lm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 1.4), Vector3(x, y, back_z + 0.3)))
		lm.set_instance_color(i, cols[i % cols.size()] * 1.6)
	var lmi := MultiMeshInstance3D.new()
	lmi.multimesh = lm
	lmi.material_override = bm
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(lmi)

	turntable = Node3D.new()
	turntable.position = Vector3(0, PLAT_H, 0)
	world.add_child(turntable)
	dummy_opp = Node3D.new()
	dummy_opp.position = Vector3(0, PLAT_H, 3.0)
	world.add_child(dummy_opp)

	# The RANDOM card's stand-in: a big spinning "?".
	question = Label3D.new()
	question.text = "?"
	question.font = font_i
	question.font_size = 220
	question.pixel_size = 0.006
	question.modulate = GOLD
	question.outline_modulate = Color(0.1, 0.05, 0.0)
	question.outline_size = 28
	question.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	question.position = Vector3(0, 1.25, 0)
	question.visible = false
	world.add_child(question)
	_tint_rims(GOLD)


func _animate_stage(_dt: float) -> void:
	if bulbs == null:
		return
	# Marquee chase: faster and gold once a pick is locked in.
	var speed := 9.0 if phase == Phase.READY else 4.0
	var head := int(t * speed)
	for i in bulb_n:
		var on := (i + head) % 4 == 0
		var c := Color(1.0, 0.85, 0.45) * (2.2 if on else 0.55)
		bulbs.set_instance_color(i, c)


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
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


func _style_button(b: Button, sb: StyleBoxFlat) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	head_label = _label("SELECT YOUR BRAWLER", font_i, 46, GOLD, 10)
	ui.add_child(head_label)
	step_box = PanelContainer.new()
	step_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(step_box)
	step_label = _label("PLAYER 1", font_i, 22, Color(1, 1, 1), 5)
	step_box.add_child(step_label)

	info_box = VBoxContainer.new()
	info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_theme_constant_override("separation", 4)
	ui.add_child(info_box)
	name_label = _label("", font_i, 56, Color(0.97, 0.95, 0.9), 12)
	info_box.add_child(name_label)
	genre_box = PanelContainer.new()
	genre_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	genre_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_box.add_child(genre_box)
	genre_label = _label("", font_i, 22, Color(0.04, 0.03, 0.03), 0)
	genre_label.add_theme_constant_override("shadow_offset_x", 0)
	genre_label.add_theme_constant_override("shadow_offset_y", 0)
	genre_box.add_child(genre_label)
	bio_label = _label("", font_b, 20, Color(0.92, 0.91, 0.88), 5)
	bio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio_label.custom_minimum_size = Vector2(520, 56)
	info_box.add_child(bio_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_box.add_child(gap)
	for si in Roster.STATS.size():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 4)
		var nl := _label(str(Roster.STATS[si]), font_i, 22, GOLD, 5)
		nl.custom_minimum_size = Vector2(96, 0)
		row.add_child(nl)
		var segs: Array = []
		for k in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(24, 18)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(seg)
			segs.append(seg)
		stat_segs.append(segs)
		var vl := _label("0", font_i, 22, Color(1, 1, 1), 5)
		vl.custom_minimum_size = Vector2(40, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		stat_vals.append(vl)
		info_box.add_child(row)
	sig_label = _label("", font_b, 19, Color(0.85, 0.85, 0.88), 4)
	info_box.add_child(sig_label)

	card_row = Control.new()
	card_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(card_row)
	for i in Roster.count() + 1:
		_build_card(i)

	confirm_btn = Button.new()
	confirm_btn.text = "CONFIRM"
	confirm_btn.focus_mode = Control.FOCUS_NONE
	confirm_btn.add_theme_font_override("font", font_i)
	confirm_btn.add_theme_font_size_override("font_size", 40)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		confirm_btn.add_theme_color_override(c, Color(0.06, 0.04, 0.02))
	_style_button(confirm_btn, _box_style(GOLD, Color(0.02, 0.02, 0.02), 10))
	confirm_btn.pressed.connect(_on_confirm_btn)
	ui.add_child(confirm_btn)

	back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_override("font", font_i)
	back_btn.add_theme_font_size_override("font_size", 24)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		back_btn.add_theme_color_override(c, Color(0.95, 0.93, 0.88))
	back_btn.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	back_btn.add_theme_constant_override("outline_size", 5)
	_style_button(back_btn, _box_style(Color(0.04, 0.035, 0.04, 0.85), RED, 8))
	back_btn.pressed.connect(_on_back_btn)
	ui.add_child(back_btn)

	hint_label = _label("< >  CHOOSE     ENTER / J  CONFIRM     ESC / K  BACK", font_b, 16, Color(0.75, 0.75, 0.78), 4)
	ui.add_child(hint_label)

	vs_band = Control.new()
	vs_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vs_band.visible = false
	ui.add_child(vs_band)
	var band := ColorRect.new()
	band.color = Color(0.02, 0.02, 0.03, 0.88)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.name = "Band"
	vs_band.add_child(band)
	var stripe := ColorRect.new()
	stripe.color = RED
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.name = "Stripe"
	vs_band.add_child(stripe)
	vs_label = _label("", font_i, 58, GOLD, 12)
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs_band.add_child(vs_label)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	ui.add_child(fade_rect)
	loading_label = _label("LOADING...", font_i, 34, GOLD, 8)
	loading_label.visible = false
	ui.add_child(loading_label)


func _build_card(i: int) -> void:
	var n := Roster.count()
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(CARD_W, CARD_H)
	b.pivot_offset = Vector2(CARD_W, CARD_H) * 0.5
	b.pressed.connect(_on_card.bind(i))
	card_row.add_child(b)
	cards.append(b)
	var short := "RANDOM"
	var genre := "???"
	if i < n:
		var e: Dictionary = Roster.ROSTER[i]
		short = str(e["short_name"])
		genre = str(e["genre"])
	var pic := TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.position = Vector2(5, 5)
	pic.size = Vector2(CARD_W - 10, CARD_H - 38)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pic.texture = _portrait(i)
	b.add_child(pic)
	if i >= n:
		var q := _label("?", font_i, 64, GOLD, 10)
		q.position = Vector2(0, 8)
		q.size = Vector2(CARD_W, CARD_H - 44)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(q)
	var strip := ColorRect.new()
	strip.color = Color(0.02, 0.02, 0.03, 0.92)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = Vector2(5, CARD_H - 36)
	strip.size = Vector2(CARD_W - 10, 31)
	b.add_child(strip)
	var nl := _label(short, font_i, 15 if short.length() > 6 else 17, Color(0.97, 0.95, 0.9), 3)
	nl.position = Vector2(4, CARD_H - 37)
	nl.size = Vector2(CARD_W - 8, 20)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.add_theme_constant_override("shadow_offset_x", 1)
	nl.add_theme_constant_override("shadow_offset_y", 1)
	b.add_child(nl)
	var gl := _label(genre, font_b, 10, GOLD, 0)
	gl.position = Vector2(4, CARD_H - 19)
	gl.size = Vector2(CARD_W - 8, 12)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.clip_text = true
	gl.add_theme_constant_override("shadow_offset_x", 0)
	gl.add_theme_constant_override("shadow_offset_y", 0)
	b.add_child(gl)
	var p1t := _tag("P1", RED)
	p1t.position = Vector2(-6, -12)
	b.add_child(p1t)
	card_p1_tags.append(p1t)
	var cpt := _tag("CPU", CPU_BLUE)
	cpt.position = Vector2(CARD_W - 40, -12)
	b.add_child(cpt)
	card_cpu_tags.append(cpt)


func _tag(text: String, col: Color) -> Label:
	var l := _label(text, font_i, 17, Color(1, 1, 1), 4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.skew = Vector2(0.2, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	l.add_theme_stylebox_override("normal", sb)
	l.visible = false
	return l


## A little painted portrait (head and shoulders in the fighter's palette over a speed-line
## card in their signature colour): readable at a glance, no render needed.
func _portrait(i: int) -> ImageTexture:
	var w := 86
	var h := 94
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var n := Roster.count()
	var gear := GOLD
	var look: Dictionary = {}
	if i < n:
		var e: Dictionary = Roster.ROSTER[i]
		look = e["look"]
		gear = look.get("gear", GOLD)
	var skin: Color = look.get("skin", Color(0.5, 0.36, 0.28))
	var top_c: Color = look.get("top_color", Color(0.1, 0.1, 0.1))
	var top_a: Color = look.get("top_accent", gear)
	var hair_c: Color = look.get("hair_color", Color(0.05, 0.04, 0.03))
	var hair: String = look.get("hair_style", look.get("hair", "none"))
	var hat: String = look.get("hat", "none")
	var hat_c: Color = look.get("hat_color", Color(0.1, 0.1, 0.1))
	var mask: bool = look.get("mask", false)
	var mask_c: Color = look.get("mask_color", gear)
	var hood: bool = str(look.get("top", "tee")) == "hoodie"
	var chain: bool = look.get("chain", false)
	var chain_c: Color = look.get("chain_color", Color(0.9, 0.9, 0.92))
	var hx := w * 0.5
	var hy := 40.0
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var bgc := gear.darkened(0.7).lerp(gear.darkened(0.25), clampf(1.0 - v + u * 0.3, 0.0, 1.0))
			if fmod(x * 0.7 + y, 11.0) < 1.6:
				bgc = bgc.lightened(0.12)
			var c := bgc
			if i < n:
				# shoulders / torso
				var sd := Vector2((x - hx) / 40.0, (y - (h + 8.0)) / 36.0).length()
				if sd < 1.0:
					var shade := 0.75 + 0.35 * clampf(1.0 - (x - hx + 18.0) / 50.0, 0.0, 1.0)
					c = top_c * shade
					c.a = 1.0
					if hood and absf(x - hx) < 20.0 and y < h - 26 and y > h - 40:
						c = top_c.darkened(0.25)
					if absf(absf(x - hx) - 30.0) < 2.0 and str(look.get("top_style", "")) == "tracksuit":
						c = top_a
				# neck
				if absf(x - hx) < 7.0 and y > hy + 12 and y < h - 24:
					c = skin.darkened(0.2)
				# head
				var hd := Vector2((x - hx) / 15.0, (y - hy) / 19.0).length()
				if hd < 1.0:
					var lit := clampf(0.85 + 0.3 * (1.0 - (x - hx + 8.0) / 22.0), 0.6, 1.15)
					c = skin * lit
					c.a = 1.0
					if absf(y - (hy - 1.0)) < 1.5 and absf(absf(x - hx) - 6.0) < 2.5:
						c = Color(0.06, 0.05, 0.05)   # eyes
					if mask and y < hy + 10.0:
						c = mask_c * lit
						c.a = 1.0
						if absf(y - (hy - 1.0)) < 3.0 and absf(absf(x - hx) - 6.0) < 4.0:
							c = Color(0.95, 0.95, 0.9)
					# hair on top
					var top_line := hy - 6.0
					if hair == "locs" or hair == "twists" or hair == "curls" or hair == "spikes" or hair == "ponytail":
						if y < top_line - absf(x - hx) * 0.1:
							c = hair_c * (0.85 + 0.25 * sin(x * 1.3))
							c.a = 1.0
				# hair outside the head
				if hair == "locs" or hair == "twists":
					if hd >= 1.0 and hd < 1.35 and y < hy + 14.0 and fmod(x, 4.0) < 2.6:
						c = hair_c
				elif hair == "spikes":
					var sx := fmod(x - hx + 40.0, 8.0)
					if y < hy - 15.0 and y > hy - 32.0 and absf(x - hx) < 14.0 and (hy - 15.0 - y) < (4.0 - absf(sx - 4.0)) * 4.5:
						c = hair_c
				elif hair == "curls":
					if hd >= 1.0 and hd < 1.18 and y < hy - 2.0:
						c = hair_c
				elif hair == "ponytail":
					if Vector2((x - hx - 12.0) / 6.0, (y - (hy - 22.0)) / 9.0).length() < 1.0:
						c = hair_c
					if hd >= 1.0 and hd < 1.1 and y < hy - 4.0:
						c = hair_c
				# hats
				if hat == "cowboy":
					if absf(y - (hy - 15.0)) < 2.5 and absf(x - hx) < 30.0 - absf(y - (hy - 15.0)) * 2.0:
						c = hat_c.darkened(0.15)
					elif y < hy - 15.0 and y > hy - 30.0 and absf(x - hx) < 14.0 - (hy - 15.0 - y) * 0.2:
						c = hat_c
						if absf(y - (hy - 19.0)) < 1.5:
							c = Color(0.3, 0.18, 0.1)
				elif hat == "fedora":
					if absf(y - (hy - 15.0)) < 2.0 and absf(x - hx) < 22.0:
						c = hat_c.lightened(0.08)
					elif y < hy - 15.0 and y > hy - 28.0 and absf(x - hx) < 14.0:
						c = hat_c
						if absf(y - (hy - 18.0)) < 1.5:
							c = Color(0.35, 0.05, 0.05)
				elif hat == "bucket":
					if y < hy - 10.0 and y > hy - 28.0 and absf(x - hx) < 15.0 + (y - (hy - 28.0)) * 0.3:
						c = hat_c
				# chain
				if chain and absf(Vector2((x - hx) / 16.0, (y - (h - 26.0)) / 12.0).length() - 1.0) < 0.12 and y > h - 26:
					c = chain_c
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _refresh_info(instant: bool) -> void:
	var n := Roster.count()
	if sel >= n:
		name_label.text = "RANDOM"
		genre_label.text = "  ANYONE  "
		genre_box.add_theme_stylebox_override("panel", _box_style(GOLD, Color(0.02, 0.02, 0.02), 6, 0.25))
		bio_label.text = "Feeling lucky? The yard picks your fighter."
		sig_label.text = ""
		for si in 4:
			stat_target[si] = 0.0
	else:
		var e: Dictionary = Roster.ROSTER[sel]
		var look: Dictionary = e["look"]
		var gear: Color = look.get("gear", GOLD)
		name_label.text = str(e["display_name"])
		genre_label.text = "  " + str(e["genre"]) + "  "
		genre_box.add_theme_stylebox_override("panel", _box_style(gear.lerp(Color.WHITE, 0.15), Color(0.02, 0.02, 0.02), 6, 0.25))
		bio_label.text = str(e["bio"])
		sig_label.text = "SIGNATURE:  " + str(e.get("signature", ""))
		var stats: Dictionary = e["stats"]
		for si in 4:
			stat_target[si] = float(stats.get(Roster.STATS[si], 5))
	if instant:
		for si in 4:
			stat_disp[si] = stat_target[si]
	name_label.scale = Vector2(1.12, 1.12)
	name_label.pivot_offset = Vector2(0, 30)
	var tw := create_tween()
	tw.tween_property(name_label, "scale", Vector2.ONE, 0.14)
	if phase == Phase.PICK_P1:
		head_label.text = "SELECT YOUR BRAWLER"
		step_label.text = "PLAYER 1"
		step_box.add_theme_stylebox_override("panel", _box_style(RED, Color(0.02, 0.02, 0.02), 6))
	elif phase == Phase.PICK_STAGE:
		var a: Dictionary = Roster.ROSTER[p1_idx]
		var b: Dictionary = Roster.ROSTER[p2_idx]
		head_label.text = "PICK THE SPOT"
		step_label.text = "STAGE      %s  VS  %s" % [a["short_name"], b["short_name"]]
		step_box.add_theme_stylebox_override("panel", _box_style(GOLD.darkened(0.25), Color(0.02, 0.02, 0.02), 6))
	else:
		var p1e: Dictionary = Roster.ROSTER[p1_idx]
		head_label.text = "CHOOSE YOUR OPPONENT"
		step_label.text = "CPU OPPONENT      P1: " + str(p1e["display_name"])
		step_box.add_theme_stylebox_override("panel", _box_style(CPU_BLUE, Color(0.02, 0.02, 0.02), 6))


func _refresh_cards() -> void:
	var n := Roster.count()
	for i in cards.size():
		var b := cards[i]
		var on := i == sel
		var gear := GOLD
		if i < n:
			var e: Dictionary = Roster.ROSTER[i]
			var look: Dictionary = e["look"]
			gear = look.get("gear", GOLD)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.03, 0.04, 0.92)
		sb.border_color = GOLD if on else gear.darkened(0.35)
		var bw := 5 if on else 2
		sb.border_width_left = bw
		sb.border_width_right = bw
		sb.border_width_top = bw
		sb.border_width_bottom = bw
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 6 if on else 2
		sb.shadow_offset = Vector2(4, 4)
		_style_button(b, sb)
		var locked_p1 := phase != Phase.PICK_P1 and i == p1_idx
		card_p1_tags[i].visible = locked_p1
		card_cpu_tags[i].visible = phase == Phase.READY and i == p2_idx
		b.modulate = Color(1, 1, 1) if (on or not locked_p1 or phase == Phase.PICK_P1) else Color(0.6, 0.6, 0.65)
	_layout_cards()


func _layout_cards() -> void:
	for i in cards.size():
		var b := cards[i]
		var on := i == sel
		b.position = Vector2(i * (CARD_W + CARD_GAP), -12.0 if on else 0.0)
		b.scale = Vector2(1.08, 1.08) if on else Vector2.ONE
		b.z_index = 1 if on else 0


func _animate_ui(dt: float) -> void:
	for si in 4:
		stat_disp[si] = move_toward(stat_disp[si], stat_target[si], dt * 30.0)
		var col: Color = STAT_COLS[si]
		var segs: Array = stat_segs[si]
		for k in 10:
			var seg: ColorRect = segs[k]
			var fill := clampf(stat_disp[si] - k, 0.0, 1.0)
			var lit := col.lightened(0.15 * (1.0 - k / 10.0))
			seg.color = Color(0.1, 0.1, 0.12, 0.85).lerp(lit, fill)
		stat_vals[si].text = "-" if stat_target[si] <= 0.0 else str(int(round(stat_disp[si])))
	if confirm_btn != null:
		var pulse := 1.0 + 0.04 * sin(t * 6.0)
		confirm_btn.scale = Vector2(pulse, pulse)
	if loading_label.visible:
		loading_label.modulate.a = 0.6 + 0.4 * sin(t * 6.0)


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
	var side := maxf(maxf(l, r), 56.0)
	return Vector4(side, maxf(tp, 30.0), side, maxf(b, 30.0))


func _relayout() -> void:
	if view != null:
		_update_view_size()
	var vp := get_viewport().get_visible_rect().size
	margin = _safe_margins()
	var ml := margin.x
	var mt := margin.y
	var mr := margin.z
	var mb := margin.w

	head_label.reset_size()
	head_label.position = Vector2(ml, mt - 6.0)
	step_box.reset_size()
	step_box.position = Vector2(ml + 8.0, mt + 52.0)

	back_btn.custom_minimum_size = Vector2(150, 54)
	back_btn.reset_size()
	back_btn.position = Vector2(vp.x - mr - back_btn.size.x, mt)

	confirm_btn.custom_minimum_size = Vector2(260, 86)
	confirm_btn.reset_size()
	confirm_btn.position = Vector2(vp.x - mr - confirm_btn.size.x, vp.y - mb - confirm_btn.size.y)
	confirm_btn.pivot_offset = confirm_btn.size * 0.5

	var row_w := (Roster.count() + 1) * (CARD_W + CARD_GAP) - CARD_GAP
	var free_w := confirm_btn.position.x - 24.0 - ml
	var k := clampf(free_w / row_w, 0.6, 1.25)
	card_row.scale = Vector2(k, k)
	card_row.position = Vector2(ml + 4.0, vp.y - mb - CARD_H * k)

	_relayout_stage(vp)
	hint_label.reset_size()
	hint_label.position = Vector2(ml, card_row.position.y - 40.0)
	if phase == Phase.PICK_STAGE and stage_row != null:
		hint_label.position = Vector2(ml, stage_row.position.y - 40.0)

	info_box.reset_size()
	info_box.position = Vector2(ml, mt + 100.0)

	vs_band.position = Vector2.ZERO
	vs_band.size = vp
	vs_band.pivot_offset = Vector2(vp.x * 0.5, vp.y * 0.42)
	var band: ColorRect = vs_band.get_node("Band")
	band.position = Vector2(0, vp.y * 0.42 - 60.0)
	band.size = Vector2(vp.x, 120)
	var stripe: ColorRect = vs_band.get_node("Stripe")
	stripe.position = Vector2(0, vp.y * 0.42 + 56.0)
	stripe.size = Vector2(vp.x, 8)
	vs_label.position = band.position
	vs_label.size = band.size

	loading_label.reset_size()
	loading_label.position = Vector2(vp.x - mr - loading_label.size.x, vp.y - mb - loading_label.size.y)
	_layout_cards()


# ---------------------------------------------------------------- STAGE SELECT
# Step 3 (after the CPU pick): where the fight happens. A card per level in
# scripts/levels/catalog.gd (+ RANDOM); a level whose script is not there yet shows COMING SOON
# and cannot be picked. The pick goes to Game.level_id (main.gd builds that level).

const STAGE_W := 156.0
const STAGE_H := 122.0
const STAGE_GAP := 10.0
const TIME_COLS := {"day": Color(0.98, 0.78, 0.25), "dusk": Color(0.98, 0.5, 0.22), "night": Color(0.35, 0.5, 1.0)}

var stages: Array = []            # {"id", "name", "time", "desc", "color", "ok", "thumb"}
var stage_sel := 0                # highlighted stage card (stages.size() = RANDOM)
var stage_ui: Control
var stage_dim: ColorRect
var stage_row: Control
var stage_cards: Array[Button] = []
var stage_panel: VBoxContainer
var stage_pic: TextureRect
var stage_pic_frame: PanelContainer
var stage_soon: Label
var stage_name: Label
var stage_time_box: PanelContainer
var stage_time: Label
var stage_desc: Label
var random_thumb: ImageTexture


## The stage list: catalog entries, overridden by each existing level script's own fields.
func _load_stages() -> void:
	stages.clear()
	for e: Dictionary in Catalog.LEVELS:
		var st := {"id": str(e["id"]), "name": str(e["name"]), "time": str(e["time"]),
			"desc": str(e["desc"]), "color": e["color"], "ok": Catalog.available(str(e["id"]))}
		if st["ok"]:
			var scr = load(Catalog.script_path(str(e["id"])))
			var lv = scr.new() if scr != null else null
			if lv is Node:
				for k: String in ["display_name", "description", "time_of_day", "preview_color"]:
					var v: Variant = lv.get(k)
					if v == null or (v is String and v == ""):
						continue
					match k:
						"display_name":
							if str(v) != "LEVEL":
								st["name"] = str(v)
						"description":
							st["desc"] = str(v)
						"time_of_day":
							st["time"] = str(v)
						"preview_color":
							st["color"] = v
				(lv as Node).free()
			else:
				st["ok"] = scr != null
		st["thumb"] = _stage_thumb(st)
		stages.append(st)
	random_thumb = _stage_thumb({"id": "random", "time": "dusk", "color": Color(0.3, 0.3, 0.32)})
	var cur := "backyard"
	if game != null and "level_id" in game:
		cur = str(game.get("level_id"))
	stage_sel = 0
	for i in stages.size():
		if stages[i]["id"] == cur and stages[i]["ok"]:
			stage_sel = i


## A tiny painted postcard of the level: sky by time of day, a skyline / house silhouette row,
## the ground in the level's preview colour (no render needed).
func _stage_thumb(st: Dictionary) -> ImageTexture:
	var w := 192
	var h := 108
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var tod := str(st.get("time", "night"))
	var ground: Color = st.get("color", Color(0.3, 0.4, 0.2))
	var top := Color(0.03, 0.04, 0.1)
	var hor := Color(0.16, 0.1, 0.22)
	if tod == "day":
		top = Color(0.36, 0.58, 0.86)
		hor = Color(0.86, 0.86, 0.8)
	elif tod == "dusk":
		top = Color(0.28, 0.17, 0.36)
		hor = Color(0.98, 0.56, 0.26)
	var horizon := int(h * 0.6)
	for y in horizon:
		img.fill_rect(Rect2i(0, y, w, 1), top.lerp(hor, pow(float(y) / horizon, 1.6)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(st.get("id", "")))
	if tod == "night":
		for k in 26:
			img.set_pixel(rng.randi_range(0, w - 1), rng.randi_range(0, horizon - 20), Color(0.9, 0.9, 1.0).darkened(rng.randf_range(0.0, 0.6)))
	# Silhouettes along the horizon: tall blocks for the city levels, roofs for the house ones.
	var sil := hor.lerp(Color(0.02, 0.02, 0.03), 0.82 if tod != "day" else 0.55)
	var city := str(st.get("id", "")) in ["rooftop", "store_lot", "random"]
	var x := -rng.randi_range(0, 12)
	while x < w:
		var bw := rng.randi_range(14, 34) if city else rng.randi_range(26, 46)
		var bh := rng.randi_range(18, 52) if city else rng.randi_range(12, 26)
		img.fill_rect(Rect2i(x, horizon - bh, bw, bh), sil)
		if not city:   # gable roof
			for r in bw / 2:
				img.fill_rect(Rect2i(x + r, horizon - bh - (bw / 2 - r) / 2, bw - 2 * r, 1), sil)
		if tod != "day":
			for k in rng.randi_range(1, 5):
				var wx := x + rng.randi_range(3, maxi(4, bw - 6))
				var wy := horizon - bh + rng.randi_range(4, maxi(5, bh - 6))
				img.fill_rect(Rect2i(wx, wy, 3, 3), Color(1.0, 0.8, 0.4) if rng.randf() < 0.8 else Color(0.5, 0.65, 1.0))
		x += bw + rng.randi_range(0, 6)
	# Ground: the level's colour, lit in a warm pool toward the middle, darker at the edges.
	var lit := 1.0 if tod == "day" else 0.75
	for y in range(horizon, h):
		var f := float(y - horizon) / float(h - horizon)
		for xx in w:
			var dx := absf(float(xx) / w - 0.5) * 2.0
			var pool := clampf(1.0 - dx * dx * 0.9, 0.0, 1.0) * (0.55 + 0.45 * f)
			var c := ground.darkened(0.45).lerp(ground.lightened(0.12), pool * lit)
			var n := rng.randf_range(-0.035, 0.035)
			img.set_pixel(xx, y, Color(c.r + n, c.g + n, c.b + n))
	return ImageTexture.create_from_image(img)


func _build_stage_ui() -> void:
	stage_ui = Control.new()
	stage_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_ui.visible = false
	ui.add_child(stage_ui)
	ui.move_child(stage_ui, 0)   # under the header, buttons, VS band and fade
	stage_dim = ColorRect.new()
	stage_dim.color = Color(0.02, 0.015, 0.03, 0.62)
	stage_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_ui.add_child(stage_dim)

	stage_panel = VBoxContainer.new()
	stage_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_panel.add_theme_constant_override("separation", 6)
	stage_ui.add_child(stage_panel)
	stage_name = _label("", font_i, 52, Color(0.97, 0.95, 0.9), 12)
	stage_panel.add_child(stage_name)
	stage_time_box = PanelContainer.new()
	stage_time_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_time_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stage_panel.add_child(stage_time_box)
	stage_time = _label("", font_i, 22, Color(0.04, 0.03, 0.03), 0)
	stage_time.add_theme_constant_override("shadow_offset_x", 0)
	stage_time.add_theme_constant_override("shadow_offset_y", 0)
	stage_time_box.add_child(stage_time)
	stage_pic_frame = PanelContainer.new()
	stage_pic_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_pic_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.02, 0.02, 0.03)
	fsb.border_color = GOLD
	fsb.set_border_width_all(4)
	fsb.shadow_color = Color(0, 0, 0, 0.6)
	fsb.shadow_size = 8
	fsb.shadow_offset = Vector2(6, 6)
	fsb.set_content_margin_all(4)
	stage_pic_frame.add_theme_stylebox_override("panel", fsb)
	stage_panel.add_child(stage_pic_frame)
	stage_pic = TextureRect.new()
	stage_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_pic.custom_minimum_size = Vector2(384, 216)
	stage_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stage_pic.stretch_mode = TextureRect.STRETCH_SCALE
	stage_pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	stage_pic_frame.add_child(stage_pic)
	stage_soon = _label("COMING SOON", font_i, 40, GOLD, 10)
	stage_soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage_soon.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_soon.rotation = -0.12
	stage_pic.add_child(stage_soon)
	stage_desc = _label("", font_b, 20, Color(0.92, 0.91, 0.88), 5)
	stage_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stage_desc.custom_minimum_size = Vector2(520, 56)
	stage_panel.add_child(stage_desc)

	stage_row = Control.new()
	stage_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_ui.add_child(stage_row)
	stage_cards.clear()
	for i in stages.size() + 1:
		_build_stage_card(i)


func _build_stage_card(i: int) -> void:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(STAGE_W, STAGE_H)
	b.pivot_offset = Vector2(STAGE_W, STAGE_H) * 0.5
	b.pressed.connect(_on_stage_card.bind(i))
	stage_row.add_child(b)
	stage_cards.append(b)
	var is_random := i >= stages.size()
	var st: Dictionary = {} if is_random else stages[i]
	var pic := TextureRect.new()
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.position = Vector2(5, 5)
	pic.size = Vector2(STAGE_W - 10, STAGE_H - 36)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pic.texture = random_thumb if is_random else st["thumb"]
	b.add_child(pic)
	if is_random:
		var q := _label("?", font_i, 60, GOLD, 10)
		q.position = Vector2(0, 4)
		q.size = Vector2(STAGE_W, STAGE_H - 40)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(q)
	elif not st["ok"]:
		pic.modulate = Color(0.45, 0.45, 0.5)
		var soon := _label("COMING\nSOON", font_i, 18, GOLD, 5)
		soon.position = Vector2(0, 6)
		soon.size = Vector2(STAGE_W, STAGE_H - 44)
		soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		soon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		soon.rotation = -0.1
		b.add_child(soon)
	var strip := ColorRect.new()
	strip.color = Color(0.02, 0.02, 0.03, 0.92)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = Vector2(5, STAGE_H - 32)
	strip.size = Vector2(STAGE_W - 10, 27)
	b.add_child(strip)
	var title := "RANDOM" if is_random else str(st["name"])
	var nl := _label(title, font_i, 14 if title.length() > 14 else 16, Color(0.97, 0.95, 0.9), 3)
	nl.position = Vector2(4, STAGE_H - 32)
	nl.size = Vector2(STAGE_W - 8, 26)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nl.clip_text = true
	nl.add_theme_constant_override("shadow_offset_x", 1)
	nl.add_theme_constant_override("shadow_offset_y", 1)
	b.add_child(nl)


func _stage_ok(i: int) -> bool:
	return i >= stages.size() or bool(stages[i]["ok"])


func _enter_stage() -> void:
	phase = Phase.PICK_STAGE
	_lock(0.35)
	if stages.is_empty():
		_load_stages()
	if stage_ui == null:
		_build_stage_ui()
	stage_ui.visible = true
	info_box.visible = false
	card_row.visible = false
	_refresh_info(false)
	_refresh_stage(true)
	_relayout()


func _leave_stage() -> void:
	if stage_ui != null:
		stage_ui.visible = false
	info_box.visible = true
	card_row.visible = true


func _on_stage_card(i: int) -> void:
	if headless or _locked() or phase != Phase.PICK_STAGE:
		return
	if i == stage_sel:
		_confirm()
	else:
		_set_stage(i)


func _set_stage(i: int) -> void:
	if i == stage_sel:
		return
	stage_sel = i
	_snd("trick", -12.0, 0.0)
	_refresh_stage(false)


func _confirm_stage() -> void:
	var pick := stage_sel
	if pick >= stages.size():
		var ok: Array[int] = []
		for i in stages.size():
			if stages[i]["ok"]:
				ok.append(i)
		pick = ok[randi() % ok.size()] if not ok.is_empty() else -1
	elif not stages[pick]["ok"]:
		shake = maxf(shake, 0.35)   # COMING SOON: shake and stay
		_snd("whoosh", -8.0)
		return
	var id := "backyard" if pick < 0 else str(stages[pick]["id"])
	if game != null:
		game.set("level_id", id)
	if pick >= 0 and pick != stage_sel:
		stage_sel = pick       # RANDOM: show what it landed on
		_refresh_stage(false)
	_snd("big_thud", -6.0)
	_leave_stage()
	_refresh_cards()
	_go_ready()
	step_label.text = "STAGE:  " + ("THE BACKYARD" if pick < 0 else str(stages[pick]["name"]))
	_relayout()


func _refresh_stage(instant: bool) -> void:
	if stage_ui == null:
		return
	var is_random := stage_sel >= stages.size()
	var st: Dictionary = {} if is_random else stages[stage_sel]
	if is_random:
		stage_name.text = "RANDOM"
		stage_time.text = "  ANYWHERE  "
		stage_time_box.add_theme_stylebox_override("panel", _box_style(GOLD, Color(0.02, 0.02, 0.02), 6, 0.25))
		stage_desc.text = "Can't decide? Let the block pick the spot."
		stage_pic.texture = random_thumb
		stage_soon.visible = false
		stage_pic.modulate = Color(1, 1, 1)
	else:
		var tod := str(st["time"])
		stage_name.text = str(st["name"])
		stage_time.text = "  " + tod.to_upper() + "  "
		var tc: Color = TIME_COLS.get(tod, GOLD)
		stage_time_box.add_theme_stylebox_override("panel", _box_style(tc, Color(0.02, 0.02, 0.02), 6, 0.25))
		stage_desc.text = str(st["desc"])
		stage_pic.texture = st["thumb"]
		stage_soon.visible = not st["ok"]
		stage_pic.modulate = Color(1, 1, 1) if st["ok"] else Color(0.5, 0.5, 0.55)
	if not instant:
		stage_name.scale = Vector2(1.12, 1.12)
		stage_name.pivot_offset = Vector2(0, 30)
		var tw := create_tween()
		tw.tween_property(stage_name, "scale", Vector2.ONE, 0.14)
	for i in stage_cards.size():
		var b := stage_cards[i]
		var on := i == stage_sel
		var col: Color = GOLD if i >= stages.size() else stages[i]["color"]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.03, 0.03, 0.04, 0.92)
		sb.border_color = GOLD if on else col.lightened(0.1)
		sb.set_border_width_all(5 if on else 2)
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_size = 6 if on else 2
		sb.shadow_offset = Vector2(4, 4)
		_style_button(b, sb)
		b.modulate = Color(1, 1, 1) if (on or _stage_ok(i)) else Color(0.7, 0.7, 0.75)
	_layout_stage_cards()


func _layout_stage_cards() -> void:
	for i in stage_cards.size():
		var b := stage_cards[i]
		var on := i == stage_sel
		b.position = Vector2(i * (STAGE_W + STAGE_GAP), -12.0 if on else 0.0)
		b.scale = Vector2(1.08, 1.08) if on else Vector2.ONE
		b.z_index = 1 if on else 0


func _relayout_stage(vp: Vector2) -> void:
	if stage_ui == null:
		return
	var ml := margin.x
	var mt := margin.y
	var mb := margin.w
	var row_w := stage_cards.size() * (STAGE_W + STAGE_GAP) - STAGE_GAP
	var free_w := confirm_btn.position.x - 24.0 - ml
	var k := clampf(free_w / row_w, 0.5, 1.2)
	stage_row.scale = Vector2(k, k)
	stage_row.position = Vector2(ml + 4.0, vp.y - mb - STAGE_H * k)
	# Preview: as big as fits between the header and the card row.
	# name (~64) + time tag (~34) + description (2 lines ~56) + gaps / frame (~40) above the hint row
	var room := stage_row.position.y - 44.0 - (mt + 92.0) - 200.0
	var ph := clampf(room, 90.0, 250.0)
	stage_pic.custom_minimum_size = Vector2(ph * 16.0 / 9.0, ph)
	stage_desc.custom_minimum_size = Vector2(minf(620.0, vp.x - ml - 340.0), 0)
	stage_panel.reset_size()
	stage_panel.position = Vector2(ml, mt + 92.0)
	_layout_stage_cards()

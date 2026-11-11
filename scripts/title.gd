extends Node3D
## City 2 City Wrestling - Backyard Brawl: start / title screen.
##
## Everything is built in code: a small night-backyard corner (grass, fence, porch light,
## string lights, a floodlight) with both wrestlers posing, a slow camera orbit through the
## same warm grade/bloom post pass as the match, a spray-paint stencil logo that slams in,
## "PRESS START", then a thumb-friendly menu (STORY MODE / QUICK BRAWL / HOW TO PLAY / CREDITS).
## Keyboard (arrows/WASD + Enter/Space/J, Esc/K back), gamepad (d-pad/stick + A/B) and touch.
##
## Loading is staged so the logo shows on the very first frame: the 3D set is built on the
## next frame and fades straight in to ~60%, the two wrestlers (their textures are painted on
## build) follow one per frame and bring it to full brightness, and only then are the sound
## clips and the music synthesised. All intro timing runs on the wall clock
## (Time.get_ticks_msec), so slow frames / loading hitches never stretch the intro.

const Wrestler := preload("res://scripts/wrestler.gd")
const Audio := preload("res://scripts/audio.gd")
const Music := preload("res://scripts/music.gd")
const MATCH_SCENE := "res://main.tscn"
const SELECT_SCENE := "res://select.tscn"   # QUICK BRAWL -> character select -> match
const STORY_SCENE := "res://story.tscn"     # STORY MODE -> story hub (scripts/story.gd)
# The menu opens on QUICK BRAWL so "Enter, Enter" still reaches the character select
# (screenshot scripts rely on it); STORY MODE sits above it.
const MENU_DEFAULT := 1

enum Phase { INTRO, PRESS, MENU, PANEL, LEAVING }

var phase: int = Phase.INTRO
var t := 0.0                     # title clock: real seconds since _ready (+ skip offset)
var start_ms := 0
var t_skip := 0.0                # added to the clock when the intro is skipped
var load_step := 0
var loaded := false              # set + wrestlers + audio + music all built
var set_t := -1.0                # clock time the set became visible (-1: not yet)
var cast_t := -1.0               # clock time the wrestlers were added
var fade_3d := 0.0
var shake := 0.0
var input_lock := 0.0            # seconds left during which confirm/back are ignored
var sel := 0
var stick_armed := true
var headless := false
var frames := 0

# 3D
var world: Node3D
var camera: Camera3D
var view: SubViewport
var view_rect: TextureRect
var post_mat: ShaderMaterial
var flood: SpotLight3D
var wrestlers: Array[Node3D] = []
var pose_plan: Array = []        # per wrestler: {"seq": [[state, secs], ...], "i": int, "left": float}

# audio
var audio: Node = null
var music: Node = null
var audio_on := false

# UI
var ui_layer: CanvasLayer
var ui: Control
var logo: Control
var logo_parts: Array = []       # [Control, start_time, kind, rest_position, rest_rotation]
var press_label: Label
var vs_label: Label
var menu_box: VBoxContainer
var menu_buttons: Array[Button] = []
var hint_label: Label
var dim: ColorRect
var panels := {}
var open_panel := ""
var fade_rect: ColorRect
var loading_label: Label
var font_i: FontVariation
var font_b: FontVariation
var grunge_tex: ImageTexture
var logo_rest_pos := Vector2.ZERO
var logo_scale_target := 1.0
var logo_pos_target := Vector2.ZERO
var margin := 60.0

const MENU_ITEMS := ["STORY MODE", "QUICK BRAWL", "HOW TO PLAY", "CREDITS"]
const GOLD := Color(1.0, 0.82, 0.12)
const RED := Color(0.86, 0.12, 0.08)

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
	vec3 md = normalize(vec3(-0.35, 0.32, -0.88));
	float mm = dot(d, md);
	col += vec3(0.25, 0.25, 0.4) * pow(max(mm, 0.0), 300.0);
	col = mix(col, vec3(1.0, 0.97, 0.82), smoothstep(0.99955, 0.9997, mm));
	COLOR = col;
}
"""

# Same grade as main.gd's GRADE_POST_SHADER (bilinear upscale, sharpen, cheap bloom,
# contrast/saturation, split toning, vignette), plus a fade from a dark backdrop.
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
uniform float vignette = 0.38;
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

# Spray-paint stencil text: vertical colour gradient (black outlines stay black), paint
# tone variation and worn-off speckles / scratches from a tiling grunge texture.
const LOGO_SHADER := """
shader_type canvas_item;

uniform sampler2D grunge : repeat_enable, filter_linear;
uniform vec3 top_col = vec3(1.0, 0.92, 0.35);
uniform vec3 bot_col = vec3(1.0, 0.42, 0.06);
uniform float y0 = 0.0;
uniform float height = 120.0;
uniform float wear = 0.6;
uniform vec2 seed = vec2(0.0);
varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = clamp((lp.y - y0) / height, 0.0, 1.0);
	vec4 g = texture(grunge, lp / 180.0 + seed);
	COLOR.rgb *= mix(top_col, bot_col, t) * mix(0.8, 1.06, g.g);
	COLOR.a *= mix(1.0, g.r, wear);
}
"""


func _ready() -> void:
	Engine.time_scale = 1.0
	start_ms = Time.get_ticks_msec()
	headless = DisplayServer.get_name() == "headless"
	grunge_tex = _make_grunge()
	font_b = FontVariation.new()
	font_b.base_font = ThemeDB.fallback_font
	font_b.variation_embolden = 1.1
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.2
	font_i.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.24, 1), Vector2.ZERO)
	# Back on the title: whatever story run was going on is over (QUICK BRAWL must not inherit it).
	var game: Node = get_node_or_null("/root/Game")
	if game != null and game.has_method("reset_story"):
		game.call("reset_story")
	_build_view()
	_build_ui()
	_relayout()
	get_viewport().size_changed.connect(_relayout)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	frames += 1
	# Wall-clock driven: the logo and fades finish on time even at a few fps. Only the
	# per-frame integrators (wrestler poses, camera easing) get a clamped step.
	var prev_t := t
	t = _now()
	var dt := clampf(t - prev_t, 0.0, 0.1)
	input_lock = maxf(0.0, input_lock - delta)  # real time: slow frames must not eat inputs

	# Headless (CI smoke test): run through the title, then the character select (which
	# auto-advances into the match), so all three keep getting exercised by "Check for script errors".
	if headless and frames == 150 and phase != Phase.LEAVING:
		phase = Phase.LEAVING
		get_tree().change_scene_to_file(STORY_SCENE)  # TEMP CI probe
		return

	_staged_load()
	_animate_logo(dt)
	_animate_camera(dt)
	_animate_wrestlers(dt)

	# Set visible: quick fade to 60%. Wrestlers in: on up to full over ~0.6 s.
	var f := 0.0
	if set_t >= 0.0:
		f = 0.6 * _smooth((t - set_t) / 0.35)
	if cast_t >= 0.0:
		f = lerpf(f, 1.0, _smooth((t - cast_t) / 0.6))
	fade_3d = maxf(fade_3d, f)
	post_mat.set_shader_parameter("fade", fade_3d)

	if phase == Phase.INTRO and t > 1.2:
		phase = Phase.PRESS
	press_label.visible = phase == Phase.PRESS
	if phase == Phase.PRESS:
		press_label.modulate.a = 1.0 if fmod(t, 1.0) < 0.62 else 0.15
	vs_label.modulate.a = clampf((fade_3d - 0.5) * 2.0, 0.0, 1.0)
	loading_label.visible = phase != Phase.LEAVING and cast_t < 0.0 and t > 1.0
	if loading_label.visible:
		loading_label.modulate.a = 0.4 + 0.3 * sin(t * 6.0)

	# shake (UI + 3D camera)
	shake = maxf(0.0, shake - dt * 2.8)
	var s := shake * shake
	ui.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 14.0 * s


func _now() -> float:
	return float(Time.get_ticks_msec() - start_ms) / 1000.0 + t_skip


func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _staged_load() -> void:
	# Frame 1 shows the logo alone; then one heavy step per frame. Picture first
	# (set, then the wrestlers), sound last: the audio/music synthesis is the slowest part
	# and the intro must not wait for it.
	if loaded or frames < 2:
		return
	match load_step:
		0:
			_build_set()
			set_t = _now()  # after the build, so its hitch doesn't eat the fade
		1:
			_spawn_wrestlers_a()
		2:
			_spawn_wrestlers_b()
			cast_t = _now()
		3:
			# Give the faded-in picture a few frames on screen before the synthesis hitch.
			if t - cast_t < 0.6 and not headless:
				return
			audio = Audio.new()
			add_child(audio)
		4:
			music = Music.new()
			add_child(music)
			loaded = true
			if audio_on:
				_start_ambience()
	load_step += 1


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if phase == Phase.LEAVING or headless:
		return
	var confirm := false
	var back := false
	var dir := 0
	var tap := false
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			if k.pressed and k.echo and (phase == Phase.MENU):
				dir = _key_dir(k.physical_keycode)
				if dir != 0:
					_move_sel(dir)
					get_viewport().set_input_as_handled()
			return
		var code := k.physical_keycode
		if code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J, KEY_Z]:
			confirm = true
		elif code in [KEY_ESCAPE, KEY_BACKSPACE, KEY_K, KEY_X]:
			back = true
		else:
			dir = _key_dir(code)
		if phase == Phase.PRESS or phase == Phase.INTRO:
			confirm = confirm or (dir == 0 and not back)
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_A, JOY_BUTTON_START:
				confirm = true
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				back = true
			JOY_BUTTON_DPAD_UP:
				dir = -1
			JOY_BUTTON_DPAD_DOWN:
				dir = 1
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_Y:
			if absf(jm.axis_value) < 0.3:
				stick_armed = true
			elif absf(jm.axis_value) > 0.6 and stick_armed:
				stick_armed = false
				dir = 1 if jm.axis_value > 0.0 else -1
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		tap = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tap = (event as InputEventScreenTouch).pressed
	else:
		return

	match phase:
		Phase.INTRO, Phase.PRESS:
			if confirm or tap:
				get_viewport().set_input_as_handled()
				_press_start()
		Phase.MENU:
			if input_lock > 0.0:
				return
			if dir != 0:
				_move_sel(dir)
				get_viewport().set_input_as_handled()
			elif confirm:
				get_viewport().set_input_as_handled()
				_activate(sel)
			elif back:
				get_viewport().set_input_as_handled()
				_back_to_press()
		Phase.PANEL:
			if input_lock > 0.0:
				return
			if confirm or back or tap:
				get_viewport().set_input_as_handled()
				_close_panel()


func _key_dir(code: int) -> int:
	if code in [KEY_UP, KEY_W]:
		return -1
	if code in [KEY_DOWN, KEY_S]:
		return 1
	return 0


func _snd(n: String, db := 0.0, var_amt := 0.05) -> void:
	if audio != null and audio_on:
		var clips: Dictionary = audio.get("clips")
		if clips.has(n):
			audio.play(n, db, var_amt)


func _start_ambience() -> void:
	if audio != null:
		audio.start_crowd()
		audio.set_crowd_intensity(0.0)
	if music != null:
		music.start()


func _press_start() -> void:
	# The first input is the user gesture browsers need before audio can play.
	audio_on = true
	if loaded:
		_start_ambience()
	if phase == Phase.INTRO:
		_finish_logo_intro()
	phase = Phase.MENU
	input_lock = 0.2
	shake = maxf(shake, 0.6)
	_snd("big_thud", -4.0)
	_snd("cheer_small", -10.0)
	logo_scale_target = 0.8
	menu_box.visible = true
	hint_label.visible = true
	for i in menu_buttons.size():
		var b := menu_buttons[i]
		b.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(0.06 * i)
		tw.tween_property(b, "modulate:a", 1.0, 0.18)
	sel = MENU_DEFAULT
	_update_sel()
	_relayout()


func _back_to_press() -> void:
	phase = Phase.PRESS
	logo_scale_target = 1.0
	menu_box.visible = false
	hint_label.visible = false
	_snd("whoosh", -6.0)
	_relayout()


func _move_sel(dir: int) -> void:
	sel = posmod(sel + dir, menu_buttons.size())
	_update_sel()
	_snd("trick", -12.0, 0.0)


func _update_sel() -> void:
	for i in menu_buttons.size():
		var b := menu_buttons[i]
		var on := i == sel
		b.add_theme_stylebox_override("normal", _btn_box(on))
		b.add_theme_stylebox_override("hover", _btn_box(on))
		b.add_theme_color_override("font_color", Color(0.06, 0.04, 0.02) if on else Color(0.95, 0.93, 0.88))
		b.add_theme_color_override("font_hover_color", Color(0.06, 0.04, 0.02) if on else Color(0.95, 0.93, 0.88))
		b.add_theme_constant_override("outline_size", 0 if on else 6)
		b.text = ("> " + MENU_ITEMS[i]) if on else MENU_ITEMS[i]


func _activate(i: int) -> void:
	if phase != Phase.MENU or input_lock > 0.0:
		return
	sel = i
	_update_sel()
	match i:
		0:
			_start_match(STORY_SCENE)
		1:
			_start_match(SELECT_SCENE)
		2:
			_open_panel("how")
		3:
			_open_panel("credits")


func _start_match(scene := SELECT_SCENE) -> void:
	phase = Phase.LEAVING
	shake = maxf(shake, 0.8)
	_snd("punch", -2.0)
	if audio != null and audio_on:
		audio.ring_bell(3)
		audio.stop_crowd()
	if music != null:
		music.fade_out(0.5)
	fade_rect.visible = true
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.55)
	tw.tween_callback(_show_loading)
	# Let the "LOADING" frame reach the screen before the (blocking) match build.
	tw.tween_interval(0.12)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene))


func _show_loading() -> void:
	loading_label.visible = true
	loading_label.modulate.a = 1.0


func _open_panel(key: String) -> void:
	phase = Phase.PANEL
	open_panel = key
	input_lock = 0.15
	dim.visible = true
	dim.modulate.a = 0.0
	for k: String in panels:
		var p: Control = panels[k]
		p.visible = k == key
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.15)
	shake = maxf(shake, 0.25)
	_snd("punch", -8.0)
	_relayout()


func _close_panel() -> void:
	phase = Phase.MENU
	open_panel = ""
	input_lock = 0.12
	dim.visible = false
	_snd("whoosh", -8.0)


# ---------------------------------------------------------------- 3D view + post

func _build_view() -> void:
	world = Node3D.new()
	add_child(world)
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.1
	camera.far = 80.0
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


func _animate_camera(dt: float) -> void:
	if camera == null:
		return
	var c := Vector3(0.05, 1.0, -0.05)
	var yaw := 0.2 + 0.32 * sin(t * 0.11)
	var dist := 5.1 + 0.45 * sin(t * 0.07 + 1.0)
	var hgt := 1.15 + 0.25 * sin(t * 0.09 + 0.4)
	# A slow dolly in while the logo lands.
	dist += 2.5 * (1.0 - _smooth(t / 4.0))
	camera.position = c + Vector3(sin(yaw) * dist, hgt - 1.0 + 0.35, cos(yaw) * dist)
	camera.look_at(c + Vector3(0, 0.12, 0))
	# Push the wrestlers to the right half of the screen (the logo / menu is on the left).
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	camera.h_offset = -1.3 * clampf(aspect / 1.7778, 0.8, 1.4) * (dist / 5.1)
	var s := shake * shake
	camera.v_offset = randf_range(-1.0, 1.0) * 0.05 * s
	camera.h_offset += randf_range(-1.0, 1.0) * 0.05 * s
	if flood != null:
		flood.light_energy = 6.5 + 0.25 * sin(t * 13.0) * sin(t * 3.1)  # old floodlight buzz


# ---------------------------------------------------------------- the backyard set

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


func _box(size: Vector3, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation.y = yaw
	mi.material_override = m
	world.add_child(mi)
	return mi


func _quad(size: Vector2, pos: Vector3, m: Material, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.position = pos
	mi.rotation.y = yaw
	mi.material_override = m
	world.add_child(mi)
	return mi


func _glow(pos: Vector3, size: float, col: Color) -> void:
	# Additive billboard halo around a light source (PS2-style lens glow).
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _halo_tex()
	m.albedo_color = col
	m.no_depth_test = false
	var mi := _quad(Vector2(size, size), pos, m)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


var _halo: ImageTexture = null


func _halo_tex() -> ImageTexture:
	if _halo != null:
		return _halo
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_halo = ImageTexture.create_from_image(img)
	return _halo


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
	for i in 700:
		var bx := randf() * n
		var by := randf() * n
		var ln := randf_range(2.0, 5.0)
		var lit := randf() < 0.5
		var col := Color(0.55, 0.66, 0.32) if lit else Color(0.07, 0.11, 0.05)
		for s in int(ln * 2.0):
			var u := s / (ln * 2.0)
			var px := int(fposmod(bx + 0.4 * u * ln, n))
			var py := int(fposmod(by - u * ln, n))
			img.set_pixel(px, py, img.get_pixel(px, py).lerp(col, 0.4))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _fence_tex() -> ImageTexture:
	# One metre of weathered privacy fence: 7 vertical boards with dark gaps, grain, water
	# streaks along the bottom, knots, nail heads and a little faded graffiti.
	var n := 128
	var nz := _noise_img(n, n, 0.06, 2)
	var streak := _noise_img(n, n, 0.15, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var board := n / 7.0
	for y in n:
		for x in n:
			var w := nz.get_pixel(x, y).r
			var bi := int(x / board)
			var bx := fmod(x, board)
			var g := 0.74 + 0.06 * sin(x * 1.7 + w * 9.0 + bi * 3.0) + (w - 0.5) * 0.16 + 0.05 * sin(bi * 12.9)
			g -= smoothstep(0.55, 0.85, streak.get_pixel(x, (y / 6) % n).r) * 0.14
			g -= 0.18 * smoothstep(0.6, 1.0, float(y) / n)
			if bx < 1.2:
				g *= 0.25
			elif bx < 2.2:
				g *= 0.75
			img.set_pixel(x, y, Color(g * 0.62, g * 0.5, g * 0.38))
	for i in 7:
		for yy in [10, 74]:
			var px := int((i + 0.5) * board)
			img.set_pixel(px, yy, Color(0.12, 0.11, 0.1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _siding_tex() -> ImageTexture:
	var n := 64
	var nz := _noise_img(n, n, 0.08, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var row := fmod(y, 16.0)
			var g := 0.7 + 0.15 * (row / 16.0) + (nz.get_pixel(x, y).r - 0.5) * 0.12
			if row < 1.5:
				g *= 0.45
			img.set_pixel(x, y, Color(g * 0.72, g * 0.76, g * 0.74))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _dirt_tex() -> ImageTexture:
	# Worn, trampled patch where they brawl: soft radial dirt with noisy edges.
	var n := 96
	var nz := _noise_img(n, n, 0.08, 3)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, (y - n * 0.5) * 1.3).length() / (n * 0.5)
			var v := nz.get_pixel(x, y).r
			var a := clampf(1.0 - smoothstep(0.35, 0.95, d + (v - 0.5) * 0.6), 0.0, 1.0) * 0.85
			var g := 0.8 + (v - 0.5) * 0.5
			img.set_pixel(x, y, Color(0.3 * g, 0.24 * g, 0.16 * g, a))
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
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.08, 0.15)
	env.fog_density = 0.02
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.transform = Transform3D(Basis.looking_at(Vector3(0.4, -0.55, 0.75)), Vector3(0, 10, 0))
	moon.light_color = Color(0.58, 0.68, 1.0)
	moon.light_energy = 0.45
	moon.shadow_enabled = false
	world.add_child(moon)

	# Ground: lawn + the worn dirt patch under them.
	var lawn := _quad(Vector2(40, 40), Vector3(0, 0, 0), _tex_mat(_grass_tex(), Color(1, 1, 1), Vector3(26, 26, 1)))
	lawn.rotation.x = -PI / 2
	var dm := _tex_mat(_dirt_tex())
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dirt := _quad(Vector2(4.6, 3.4), Vector3(0.0, 0.01, -0.1), dm)
	dirt.rotation.x = -PI / 2
	dirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Privacy fence behind them and down the right side, posts and rails.
	var ftex := _fence_tex()
	var fh := 1.9
	var back_z := -3.6
	_quad(Vector2(14, fh), Vector3(-1.0, fh * 0.5, back_z), _tex_mat(ftex, Color(1, 1, 1), Vector3(14, 1, 1)))
	_quad(Vector2(10, fh), Vector3(6.0, fh * 0.5, 1.4), _tex_mat(ftex, Color(0.9, 0.9, 0.9), Vector3(10, 1, 1)), -PI / 2)
	var post_m := _mat(Color(0.3, 0.24, 0.18))
	for i in 8:
		_box(Vector3(0.12, fh + 0.12, 0.12), Vector3(-8.0 + i * 2.0, (fh + 0.12) * 0.5, back_z + 0.08), post_m)
	_box(Vector3(14, 0.09, 0.05), Vector3(-1.0, 0.35, back_z + 0.05), post_m)
	_box(Vector3(14, 0.09, 0.05), Vector3(-1.0, fh - 0.3, back_z + 0.05), post_m)

	# House corner on the left with the porch light by the back door.
	var siding := _tex_mat(_siding_tex(), Color(0.85, 0.85, 0.9), Vector3(6, 6, 1))
	_quad(Vector2(6.0, 4.2), Vector3(-5.2, 2.1, -0.6), siding, PI / 2)
	_box(Vector3(0.1, 2.1, 1.0), Vector3(-5.15, 1.05, -1.4), _mat(Color(0.22, 0.17, 0.13)))   # back door
	var win := _quad(Vector2(0.9, 0.7), Vector3(-5.14, 1.7, 0.6), _mat(Color(0.8, 0.5, 0.25), true, 0.45), PI / 2)
	win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(0.16, 0.22, 0.16), Vector3(-5.06, 2.45, -2.1), _mat(Color(1.0, 0.85, 0.55), true, 3.0))
	_glow(Vector3(-4.95, 2.45, -2.1), 1.3, Color(1.0, 0.7, 0.4, 0.55))
	var porch := OmniLight3D.new()
	porch.position = Vector3(-4.7, 2.4, -2.1)
	porch.omni_range = 6.5
	porch.light_energy = 1.8
	porch.light_color = Color(1.0, 0.72, 0.42)
	porch.omni_attenuation = 1.3
	world.add_child(porch)

	# Props against the fence: trash can, a folded table, a lawn chair.
	var can_m := _mat(Color(0.42, 0.44, 0.46))
	can_m.metallic = 0.6
	can_m.roughness = 0.45
	var can := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.3
	cy.bottom_radius = 0.26
	cy.height = 0.85
	cy.radial_segments = 14
	can.mesh = cy
	can.material_override = can_m
	can.position = Vector3(2.6, 0.425, -2.9)
	world.add_child(can)
	var lid := _box(Vector3(0.66, 0.06, 0.66), Vector3(2.6, 0.88, -2.9), can_m)
	lid.rotation.z = 0.12
	var table := _box(Vector3(1.8, 0.75, 0.05), Vector3(-1.9, 0.9, -3.35), _mat(Color(0.45, 0.44, 0.42)))
	table.rotation.x = -0.25
	var chair_m := _mat(Color(0.2, 0.42, 0.55))
	_box(Vector3(0.55, 0.06, 0.5), Vector3(3.6, 0.42, -1.4), chair_m, 0.5)
	var back := _box(Vector3(0.55, 0.6, 0.05), Vector3(3.72, 0.7, -1.62), chair_m, 0.5)
	back.rotation.x = -0.25

	# Floodlight: a pole at the front right, aimed at the two of them. Casts the only shadow.
	flood = SpotLight3D.new()
	var fpos := Vector3(3.8, 5.6, 4.2)
	flood.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.6, -0.3) - fpos), fpos)
	flood.spot_angle = 30.0
	flood.spot_angle_attenuation = 0.8
	flood.spot_range = 14.0
	flood.light_energy = 6.5
	flood.light_color = Color(1.0, 0.84, 0.62)
	flood.shadow_enabled = true
	flood.shadow_bias = 0.06
	flood.shadow_normal_bias = 1.0
	flood.shadow_blur = 1.5
	flood.shadow_opacity = 0.75
	world.add_child(flood)
	# A second, visible floodlight on the back fence (rim light + lens flare in shot).
	var rim := SpotLight3D.new()
	var rpos := Vector3(4.6, 3.6, -3.4)
	rim.transform = Transform3D(Basis.looking_at(Vector3(0.0, 1.0, 0.0) - rpos), rpos)
	rim.spot_angle = 38.0
	rim.spot_range = 10.0
	rim.light_energy = 3.2
	rim.light_color = Color(1.0, 0.9, 0.75)
	world.add_child(rim)
	_box(Vector3(0.1, 3.7, 0.1), Vector3(4.6, 1.85, -3.5), _mat(Color(0.1, 0.1, 0.11)))
	var head := _box(Vector3(0.5, 0.34, 0.24), Vector3.ZERO, _mat(Color(0.15, 0.15, 0.16)))
	head.transform = rim.transform
	var lens := _box(Vector3(0.42, 0.27, 0.04), Vector3.ZERO, _mat(Color(1.0, 0.94, 0.8), true, 4.0))
	lens.transform = rim.transform * Transform3D(Basis(), Vector3(0, 0, -0.13))
	_glow(rpos + (Vector3(0.0, 1.0, 0.0) - rpos).normalized() * 0.3, 2.4, Color(1.0, 0.85, 0.6, 0.6))

	# Character lights: a warm key from the camera side so faces and gear read (no
	# silhouettes against the fence) and a warm rim from behind-left to cut them out of
	# the dark background. No shadows: the floodlight casts the only one.
	var key := SpotLight3D.new()
	var kpos := Vector3(-2.4, 2.7, 3.6)
	key.transform = Transform3D(Basis.looking_at(Vector3(0.05, 1.05, -0.05) - kpos), kpos)
	key.spot_angle = 26.0
	key.spot_angle_attenuation = 0.9
	key.spot_range = 9.0
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.8, 0.58)
	world.add_child(key)
	var back_rim := SpotLight3D.new()
	var bpos := Vector3(-2.0, 2.9, -2.9)
	back_rim.transform = Transform3D(Basis.looking_at(Vector3(0.05, 1.2, 0.0) - bpos), bpos)
	back_rim.spot_angle = 30.0
	back_rim.spot_range = 7.0
	back_rim.light_energy = 3.0
	back_rim.light_color = Color(1.0, 0.7, 0.42)
	world.add_child(back_rim)

	_build_string_lights()


func _hang(a: Vector3, b: Vector3, sag: float, u: float) -> Vector3:
	return a.lerp(b, u) - Vector3(0, sag * 4.0 * u * (1.0 - u), 0)


func _build_string_lights() -> void:
	var strands: Array = [[Vector3(-5.1, 3.6, -3.4), Vector3(4.6, 3.3, -3.3)],
		[Vector3(-5.1, 3.8, 1.5), Vector3(4.6, 3.3, -3.3)],
		[Vector3(-5.1, 3.6, -3.4), Vector3(6.0, 3.0, 2.0)]]
	var cols: Array[Color] = [Color(1.0, 0.75, 0.42), Color(0.95, 0.68, 0.38), Color(1.0, 0.75, 0.42),
		Color(0.85, 0.3, 0.2), Color(0.45, 0.7, 0.4), Color(0.45, 0.55, 0.95), Color(1.0, 0.55, 0.2)]
	var wire_m := _mat(Color(0.04, 0.04, 0.04))
	var xforms: Array[Transform3D] = []
	var bcols: Array[Color] = []
	for s: Array in strands:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var segs := 10
		var prev := a
		for k in range(1, segs + 1):
			var p := _hang(a, b, 0.5, float(k) / segs)
			var mid := (prev + p) * 0.5
			var wire := _box(Vector3(0.02, 0.02, prev.distance_to(p)), mid, wire_m)
			wire.look_at_from_position(mid, p, Vector3.UP)
			wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			prev = p
		var nb := int(a.distance_to(b) / 0.6)
		for k in nb:
			var bp := _hang(a, b, 0.5, (k + 0.5) / nb) - Vector3(0, 0.06, 0)
			xforms.append(Transform3D(Basis(), bp))
			bcols.append(cols[randi() % cols.size()])
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	sm.radial_segments = 6
	sm.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, bcols[i] * 1.6)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	bm.vertex_color_is_srgb = true
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mmi)
	# Soft halos on every other bulb (one multimesh of additive billboards).
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.albedo_texture = _halo_tex()
	hm.vertex_color_use_as_albedo = true
	hm.vertex_color_is_srgb = true
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var hmm := MultiMesh.new()
	hmm.transform_format = MultiMesh.TRANSFORM_3D
	hmm.use_colors = true
	hmm.mesh = qm
	var nh := (xforms.size() + 1) / 2
	hmm.instance_count = nh
	for i in nh:
		hmm.set_instance_transform(i, xforms[i * 2])
		var c := bcols[i * 2]
		hmm.set_instance_color(i, Color(c.r, c.g, c.b, 0.35))
	var hmi := MultiMeshInstance3D.new()
	hmi.multimesh = hmm
	hmi.material_override = hm
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(hmi)
	for p: Vector3 in [Vector3(-1.5, 3.1, -2.6), Vector3(1.5, 3.0, -1.0)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 5.0
		o.light_energy = 0.5
		o.light_color = Color(1.0, 0.78, 0.5)
		world.add_child(o)


# ---------------------------------------------------------------- the wrestlers
# Same looks as main.gd. They never tick() (no AI, physics or input): the title just sets
# a pose state, advances the animation clocks and runs the procedural pose solver.

func _look_tank() -> Dictionary:
	return {
		"gear": Color(0.8, 0.14, 0.1), "skin": Color(0.42, 0.28, 0.2), "face": "tank",
		"hair": "locs", "hair_color": Color(0.05, 0.036, 0.03),
		"top": "tee", "top_color": Color(0.075, 0.072, 0.078), "graphic": "skull_bolt", "undershirt": true,
		"bottom_color": Color(0.13, 0.13, 0.16), "bottom_fade": Color(0.33, 0.3, 0.28),
		"shoe_color": Color(0.06, 0.06, 0.065), "shoe_accent": Color(0.92, 0.92, 0.9),
		"chain": true, "bracelet": true, "tattoos": true, "bulk": 1.0,
	}


func _look_kid() -> Dictionary:
	return {
		"gear": Color(0.15, 0.75, 0.3), "skin": Color(0.62, 0.43, 0.3), "face": "kid",
		"mask": true, "mask_color": Color(0.12, 0.7, 0.28), "mask_trim": Color(1.0, 0.82, 0.1),
		"hair": "curls", "hair_color": Color(0.07, 0.055, 0.045),
		"top": "hoodie", "top_color": Color(0.46, 0.47, 0.49), "top_accent": Color(0.12, 0.62, 0.26),
		"graphic": "peligro",
		"bottom_color": Color(0.36, 0.47, 0.62), "bottom_fade": Color(0.7, 0.76, 0.84),
		"shoe_color": Color(0.9, 0.9, 0.88), "shoe_accent": Color(0.13, 0.55, 0.26),
		"wristband_color": Color(0.1, 0.1, 0.1), "bulk": 0.86,
	}


func _spawn(n: String, look: Dictionary, pos: Vector3, yaw: float) -> Node3D:
	var w: Node3D = Wrestler.new()
	world.add_child(w)
	w.setup(n, look, false)
	w.position = pos
	w.rotation.y = yaw
	w.set("facing", Vector3(sin(yaw), 0.0, cos(yaw)))
	wrestlers.append(w)
	return w


func _spawn_wrestlers_a() -> void:
	var tank := _spawn("TANK MAGRUDER", _look_tank(), Vector3(-0.72, 0.0, 0.12), 0.42)
	pose_plan.append({"seq": [[Wrestler.S.IDLE, 2.6], [Wrestler.S.TAUNT, Wrestler.TAUNT_TIME],
		[Wrestler.S.IDLE, 3.4], [Wrestler.S.WIN, 4.6]], "i": 0, "left": 1.4})
	_start_state(tank, Wrestler.S.IDLE)


func _spawn_wrestlers_b() -> void:
	var kid := _spawn("LIL PELIGRO", _look_kid(), Vector3(0.82, 0.0, -0.22), -0.5)
	pose_plan.append({"seq": [[Wrestler.S.IDLE, 3.3], [Wrestler.S.TAUNT, Wrestler.TAUNT_TIME],
		[Wrestler.S.TAUNT, Wrestler.TAUNT_TIME], [Wrestler.S.IDLE, 2.8], [Wrestler.S.WIN, 3.1]], "i": 0, "left": 2.4})
	_start_state(kid, Wrestler.S.IDLE)
	# A harmless opponent link: some pose helpers look at the other wrestler.
	wrestlers[0].set("opponent", wrestlers[1])
	wrestlers[1].set("opponent", wrestlers[0])


func _start_state(w: Node3D, s: int) -> void:
	w.set("state", s)
	w.set("state_time", 0.0)


func _animate_wrestlers(dt: float) -> void:
	for i in wrestlers.size():
		var w := wrestlers[i]
		var plan: Dictionary = pose_plan[i]
		var left: float = plan["left"] - dt
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


# ---------------------------------------------------------------- UI

func _make_grunge() -> ImageTexture:
	# R: paint coverage (1 = paint, low = worn off), G: paint tone. Tiles seamlessly.
	var n := 128
	var big := _noise_img(n, n, 0.05, 3)
	var fine := _noise_img(n, n, 0.5, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var b := big.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var cover := 1.0 - smoothstep(0.62, 0.8, f) * smoothstep(0.45, 0.7, b)
			cover = minf(cover, 1.0 - 0.6 * smoothstep(0.7, 0.85, b) * smoothstep(0.5, 0.65, f))
			img.set_pixel(x, y, Color(cover, 0.35 + b * 0.5 + (f - 0.5) * 0.3, 0.0, 1.0))
	# Scratches: thin worn lines.
	for i in 12:
		var p := Vector2(randf() * n, randf() * n)
		var a := randf_range(-0.6, 0.6) + (PI if randf() < 0.5 else 0.0)
		var ln := randf_range(18.0, 70.0)
		for s in int(ln):
			a += randf_range(-0.05, 0.05)
			p += Vector2(cos(a), sin(a))
			var px := int(fposmod(p.x, n))
			var py := int(fposmod(p.y, n))
			var c := img.get_pixel(px, py)
			c.r = 0.15
			img.set_pixel(px, py, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _spray_stroke(w: int, h: int, col: Color, drips: int, seed_v: int) -> ImageTexture:
	# A wide spray-can stroke: soft overspray, ragged edges, a few drips running down.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = 0.04
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var mid := h * 0.42
	var half := h * 0.3
	for y in h:
		for x in w:
			var u := float(x) / w
			var wob := fn.get_noise_2d(x * 0.5, 0.0) * h * 0.08
			var taper := smoothstep(0.0, 0.08, u) * smoothstep(1.0, 0.9, u)
			var d := absf(y - mid - wob) / maxf(half * (0.75 + 0.25 * taper), 1.0)
			var edge := fn.get_noise_2d(x * 2.5, y * 2.5) * 0.25
			var a := (1.0 - smoothstep(0.75, 1.05, d + edge)) * (0.3 + 0.7 * taper)
			# overspray halo
			a = maxf(a, (1.0 - smoothstep(0.9, 1.6, d)) * 0.22 * taper)
			if rng.randf() < 0.025 * (1.0 - smoothstep(1.0, 1.8, d)):
				a = maxf(a, 0.6)
			var tone := 0.85 + 0.15 * fn.get_noise_2d(x * 1.3, y * 1.3)
			img.set_pixel(x, y, Color(col.r * tone, col.g * tone, col.b * tone, clampf(a, 0.0, 1.0)))
	for i in drips:
		var dx := int(rng.randf_range(0.1, 0.9) * w)
		var dl := rng.randf_range(h * 0.2, h * 0.55)
		var y0 := int(mid + half * 0.8)
		var dw := rng.randf_range(1.5, 3.5)
		for y in range(y0, mini(h, y0 + int(dl))):
			var k := float(y - y0) / dl
			var ww := dw * (1.0 - 0.4 * k)
			for xx in range(-4, 5):
				var px := dx + xx
				if px < 0 or px >= w:
					continue
				var a := clampf(ww - absf(xx), 0.0, 1.0)
				if k > 0.92:
					a *= 1.0 + 0.6 * sin(k * 30.0)  # blob at the end
				var c := img.get_pixel(px, y)
				c.r = col.r
				c.g = col.g
				c.b = col.b
				c.a = maxf(c.a, clampf(a, 0.0, 1.0))
				img.set_pixel(px, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _tape_tex(w: int, h: int) -> ImageTexture:
	# Black gaffer tape strip with torn ends and a slight sheen.
	var fn := FastNoiseLite.new()
	fn.seed = 77
	fn.frequency = 0.15
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var tear := 6.0 + fn.get_noise_2d(0.0, y * 1.0) * 6.0
			var tear2 := 6.0 + fn.get_noise_2d(500.0, y * 1.0) * 6.0
			var a := 1.0
			if x < tear or x > w - tear2:
				a = 0.0
			var v := float(y) / h
			var g := 0.07 + 0.05 * (1.0 - absf(v - 0.3) * 2.0) + fn.get_noise_2d(x * 0.3, y * 3.0) * 0.02
			img.set_pixel(x, y, Color(g, g, g * 1.1, a * 0.94))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _logo_mat(top: Color, bot: Color, h: float, wear: float, seed_v: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LOGO_SHADER
	m.shader = sh
	m.set_shader_parameter("grunge", grunge_tex)
	m.set_shader_parameter("top_col", Vector3(top.r, top.g, top.b))
	m.set_shader_parameter("bot_col", Vector3(bot.r, bot.g, bot.b))
	m.set_shader_parameter("y0", h * 0.12)
	m.set_shader_parameter("height", h * 0.8)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("seed", seed_v)
	return m


func _label(text: String, font: Font, size: int, col: Color, outline: int, outline_col := Color(0.02, 0.02, 0.02)) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline_col)
	l.add_theme_constant_override("outline_size", outline)
	return l


func _shadow(l: Label, off: float, a := 0.6) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, a))
	l.add_theme_constant_override("shadow_offset_x", int(off))
	l.add_theme_constant_override("shadow_offset_y", int(off))
	l.add_theme_constant_override("shadow_outline_size", l.get_theme_constant("outline_size") + 2)


func _center_in(c: Control, parent: Control, center: Vector2) -> void:
	parent.add_child(c)
	c.reset_size()
	var sz := c.get_combined_minimum_size()
	c.size = sz
	c.position = center - sz * 0.5
	c.pivot_offset = sz * 0.5


func _add_part(c: Control, start: float, kind: String) -> void:
	logo_parts.append([c, start, kind, c.position, c.rotation])
	c.modulate.a = 0.0


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 1
	add_child(ui_layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui)

	# ---- logo (720 x 330 box, origin top-left; positioned by _relayout)
	logo = Control.new()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.size = Vector2(720, 330)
	logo.pivot_offset = Vector2(360, 165)
	logo.rotation = deg_to_rad(-4.0)
	ui.add_child(logo)

	var city := _label("CITY 2 CITY", font_i, 104, Color.WHITE, 26)
	_shadow(city, 10.0, 0.7)
	var splat := TextureRect.new()
	splat.texture = _spray_stroke(320, 96, RED, 7, 4242)
	splat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splat.stretch_mode = TextureRect.STRETCH_SCALE
	splat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_child(splat)
	_center_in(city, logo, Vector2(360, 100))
	# The red spray stroke sits behind the words, a bit wider than them.
	splat.size = Vector2(city.size.x * 0.88 + 90.0, city.size.y * 1.35)
	splat.position = Vector2(360.0 - splat.size.x * 0.5, 100.0 - splat.size.y * 0.45)
	splat.rotation = deg_to_rad(1.5)
	_add_part(splat, 0.05, "spray")
	city.material = _logo_mat(Color(1.0, 0.95, 0.45), Color(1.0, 0.5, 0.08), city.size.y, 0.65, Vector2(0.13, 0.4))
	_add_part(city, 0.15, "slam")

	var tape := TextureRect.new()
	tape.texture = _tape_tex(256, 48)
	tape.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tape.stretch_mode = TextureRect.STRETCH_SCALE
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tape.size = Vector2(560, 84)
	tape.position = Vector2(80, 178)
	tape.pivot_offset = tape.size * 0.5
	tape.rotation = deg_to_rad(2.5)
	logo.add_child(tape)
	_add_part(tape, 0.5, "slide")
	var wf := FontVariation.new()
	wf.base_font = ThemeDB.fallback_font
	wf.variation_embolden = 1.3
	wf.spacing_glyph = 10
	var wrest := _label("WRESTLING", wf, 64, Color.WHITE, 8)
	_center_in(wrest, logo, Vector2(362, 220))
	wrest.rotation = deg_to_rad(2.5)
	wrest.material = _logo_mat(Color(1, 1, 1), Color(0.86, 0.86, 0.84), wrest.size.y, 0.5, Vector2(0.55, 0.1))
	_add_part(wrest, 0.58, "slide")

	var brawl := _label("BACKYARD BRAWL", font_i, 46, GOLD, 12)
	_shadow(brawl, 6.0, 0.75)
	_center_in(brawl, logo, Vector2(420, 292))
	brawl.rotation = deg_to_rad(-3.0)
	brawl.material = _logo_mat(Color(1.0, 0.92, 0.4), Color(1.0, 0.72, 0.1), brawl.size.y, 0.45, Vector2(0.3, 0.77))
	_add_part(brawl, 0.85, "stamp")

	# ---- press start
	press_label = _label("PRESS START", font_i, 40, Color(1, 1, 1), 10)
	_shadow(press_label, 4.0, 0.7)
	ui.add_child(press_label)
	press_label.visible = false

	# ---- versus tag, bottom right
	vs_label = _label("TANK MAGRUDER  vs  LIL PELIGRO", font_i, 26, Color(0.95, 0.93, 0.88), 8)
	ui.add_child(vs_label)
	vs_label.modulate.a = 0.0

	loading_label = _label("LOADING...", font_i, 26, GOLD, 8)
	ui.add_child(loading_label)
	loading_label.visible = false

	# ---- menu
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 10)
	menu_box.visible = false
	ui.add_child(menu_box)
	for i in MENU_ITEMS.size():
		var b := Button.new()
		b.text = MENU_ITEMS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(440, 62)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", font_i)
		b.add_theme_font_size_override("font_size", 36)
		b.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
		b.add_theme_color_override("font_pressed_color", Color(0.06, 0.04, 0.02))
		b.add_theme_stylebox_override("pressed", _btn_box(true))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var idx := i
		b.pressed.connect(func(): _activate(idx))
		b.mouse_entered.connect(func():
			if phase == Phase.MENU and sel != idx:
				sel = idx
				_update_sel()
				_snd("trick", -14.0, 0.0))
		menu_box.add_child(b)
		menu_buttons.append(b)
	_update_sel()
	hint_label = _label("UP / DOWN  select     ENTER / J  confirm     ESC  back", font_b, 18, Color(0.85, 0.85, 0.85), 5)
	hint_label.visible = false
	ui.add_child(hint_label)

	# ---- panels
	dim = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	dim.gui_input.connect(_on_dim_input)
	ui.add_child(dim)
	panels["how"] = _build_how_panel()
	panels["credits"] = _build_credits_panel()

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	ui.add_child(fade_rect)
	ui.move_child(loading_label, -1)


func _on_dim_input(event: InputEvent) -> void:
	if phase != Phase.PANEL or input_lock > 0.0:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_close_panel()
		get_viewport().set_input_as_handled()


func _btn_box(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.skew = Vector2(0.22, 0.0)
	sb.bg_color = GOLD if on else Color(0.04, 0.035, 0.04, 0.82)
	sb.border_color = Color(0.02, 0.02, 0.02) if on else RED
	sb.border_width_left = 10
	sb.border_width_bottom = 4 if on else 2
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.content_margin_left = 34
	sb.content_margin_right = 24
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(6, 6)
	if on:
		sb.shadow_size = 1
	return sb


func _panel_shell(title: String) -> Array:
	# Returns [panel, content VBox].
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.94)
	sb.border_color = GOLD
	sb.border_width_left = 8
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_right = 3
	sb.skew = Vector2(0.06, 0.0)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 20
	sb.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var head := _label(title, font_i, 40, GOLD, 10)
	col.add_child(head)
	var rule := ColorRect.new()
	rule.color = RED
	rule.custom_minimum_size = Vector2(0, 4)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	dim.add_child(panel)
	return [panel, col]


func _row(col: VBoxContainer, key: String, what: String) -> void:
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 18)
	var k := _label(key, font_i, 23, GOLD, 5)
	k.custom_minimum_size = Vector2(250, 0)
	h.add_child(k)
	h.add_child(_label(what, font_b, 22, Color(0.95, 0.94, 0.9), 4))
	col.add_child(h)


func _build_how_panel() -> Control:
	var shell := _panel_shell("HOW TO PLAY")
	var col: VBoxContainer = shell[1]
	_row(col, "STICK / WASD", "Move")
	_row(col, "STRIKE  J", "Tap again for strings  (stick changes the next hit)")
	_row(col, "GRAB  K", "Lock-up  (HOLD = strong)  then J / K / stick for slams")
	_row(col, "", "GRAB again mid-throw to chain into the next move")
	_row(col, "RUN  L", "Run  ·  double-tap = dodge roll  ·  in a lock-up = whip")
	_row(col, "PIN / TAUNT  Space", "Cover a downed foe (3 wins)  ·  else taunt")
	_row(col, "CLIMB", "RUN into yard props  ·  STRIKE to dive  ·  air tricks!")
	_row(col, "WEAPONS", "GRAB chairs, cans, 2x4s  ·  STRIKE swings  ·  tables break")
	_row(col, "B-R-A-W-L", "Style fills the letters  ·  all 5 = BRAWL MODE")
	_row(col, "REVERSE!", "Press GRAB or STRIKE when it flashes")
	var foot := _label("Touch: stick on the left, buttons on the right      tap / ESC to close", font_b, 17, Color(0.7, 0.7, 0.72), 4)
	col.add_child(foot)
	return shell[0]


func _build_credits_panel() -> Control:
	var shell := _panel_shell("CREDITS")
	var col: VBoxContainer = shell[1]
	col.add_child(_label("CITY 2 CITY WRESTLING — BACKYARD BRAWL", font_i, 28, Color(0.95, 0.94, 0.9), 6))
	col.add_child(_label("Made with Godot / Xogot", font_b, 26, GOLD, 5))
	col.add_child(_label("Wrestlers, yard, textures, sound and beat: all generated in code", font_b, 21, Color(0.9, 0.9, 0.88), 4))
	col.add_child(_label("TANK MAGRUDER  vs  LIL PELIGRO", font_i, 24, RED.lightened(0.25), 6))
	col.add_child(_label("No ropes. No refs. No rules. Just bad decisions.", font_b, 20, Color(0.75, 0.75, 0.78), 4))
	var foot := _label("tap / ESC to close", font_b, 17, Color(0.7, 0.7, 0.72), 4)
	col.add_child(foot)
	return shell[0]


func _safe_margins() -> Vector4:
	# left, top, right, bottom in logical pixels: at least 60, more for a notch.
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
	var side := maxf(maxf(l, r), 60.0)
	return Vector4(side, maxf(tp, 36.0), side, maxf(b, 36.0))


func _relayout() -> void:
	if view != null:
		_update_view_size()
	var vp := get_viewport().get_visible_rect().size
	var m := _safe_margins()
	margin = m.x
	var menu_mode := phase == Phase.MENU or phase == Phase.PANEL or phase == Phase.LEAVING
	var sc := 0.8 if menu_mode else 1.0
	logo_scale_target = sc
	# Logo box is 720 x 330 around its centre; keep it inside the left safe edge.
	var cx := m.x + 360.0 * sc - 10.0
	var cy := (m.y + 165.0 * sc + 6.0) if menu_mode else vp.y * 0.4
	logo_pos_target = Vector2(cx - 360.0, cy - 165.0)
	if phase == Phase.INTRO and t < 0.01:
		logo.position = logo_pos_target
		logo.scale = Vector2.ONE * sc

	press_label.reset_size()
	var ps := press_label.get_combined_minimum_size()
	press_label.size = ps
	press_label.position = Vector2(cx - ps.x * 0.5, minf(vp.y * 0.4 + 165.0 + 70.0, vp.y - m.w - ps.y - 30.0))

	vs_label.reset_size()
	var vs := vs_label.get_combined_minimum_size()
	vs_label.size = vs
	vs_label.position = Vector2(vp.x - m.z - vs.x, vp.y - m.w - vs.y)

	loading_label.reset_size()
	var ls := loading_label.get_combined_minimum_size()
	loading_label.position = Vector2(vp.x - m.z - ls.x, m.y)

	menu_box.reset_size()
	var mh := menu_box.get_combined_minimum_size()
	menu_box.size = mh
	var logo_bottom := m.y + 330.0 * 0.8 + 10.0
	var my := clampf(logo_bottom + 12.0, logo_bottom, vp.y - m.w - mh.y - 34.0)
	menu_box.position = Vector2(m.x + 10.0, my)

	hint_label.reset_size()
	var hs := hint_label.get_combined_minimum_size()
	hint_label.position = Vector2(m.x + 14.0, vp.y - m.w - hs.y + 6.0)

	for k: String in panels:
		var p: Control = panels[k]
		p.reset_size()
		var sz := p.get_combined_minimum_size()
		p.size = sz
		p.position = (vp - sz) * 0.5


func _finish_logo_intro() -> void:
	t_skip += maxf(0.0, 1.3 - t)
	t = maxf(t, 1.3)


func _animate_logo(dt: float) -> void:
	for part: Array in logo_parts:
		var c: Control = part[0]
		var start: float = part[1]
		var kind: String = part[2]
		var rest_pos: Vector2 = part[3]
		var rest_rot: float = part[4]
		var u := (t - start)
		if u < 0.0:
			c.modulate.a = 0.0
			continue
		match kind:
			"spray":
				# Sprayed on left to right: grow from the left edge.
				var k := _smooth(u / 0.35)
				c.modulate.a = minf(1.0, u / 0.12)
				c.scale = Vector2(maxf(k, 0.02), 1.0)
				c.pivot_offset = Vector2(0.0, c.size.y * 0.5)
			"slam":
				# Drops in from just above its spot, slightly enlarged (stays on-screen).
				var d := 0.22
				if u < d:
					var k := u / d
					c.scale = Vector2.ONE * lerpf(1.35, 1.0, k * k)
					c.position = rest_pos + Vector2(0.0, -70.0 * (1.0 - k * k))
					c.modulate.a = minf(1.0, k * 1.6)
				else:
					var b := u - d
					c.scale = Vector2.ONE * (1.0 + 0.07 * exp(-b * 9.0) * cos(b * 30.0))
					c.position = rest_pos
					c.modulate.a = 1.0
					if part.size() < 6:
						part.append(true)
						shake = maxf(shake, 0.9)
						_snd("big_thud", -2.0)
			"slide":
				var k := _smooth(minf(u / 0.25, 1.0))
				c.position = rest_pos + Vector2(-60.0 * (1.0 - k), 0.0)  # short slide, never off-screen
				c.modulate.a = k
				c.rotation = rest_rot - 0.15 * (1.0 - k)
			"stamp":
				var d := 0.14
				if u < d:
					var k := u / d
					c.scale = Vector2.ONE * lerpf(1.9, 1.0, k)
					c.modulate.a = k
				else:
					c.scale = Vector2.ONE
					c.modulate.a = 1.0
					if part.size() < 6:
						part.append(true)
						shake = maxf(shake, 0.45)
	# Whole logo: ease toward its target (menu shrinks it), gentle idle bob.
	var kk := 1.0 - exp(-8.0 * dt)
	logo.position = logo.position.lerp(logo_pos_target + Vector2(0.0, 3.0 * sin(t * 1.3)), kk)
	var sc := lerpf(logo.scale.x, logo_scale_target, kk)
	logo.scale = Vector2(sc, sc)

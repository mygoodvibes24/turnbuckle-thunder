extends Node3D
## Builds the arena, spawns both wrestlers, runs the camera, HUD and match flow.
## Everything is generated in code so the project has no imported assets.

const Wrestler := preload("res://scripts/wrestler.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const RING_TOP := 1.0

var p1: Node3D
var p2: Node3D
var ring_root: Node3D
var camera: Camera3D
var cam_target := Vector3.ZERO
var cam_shake := 0.0
var touch: Control
var match_over := false

# Feel / FX (see "# ---- feel / FX")
const Audio := preload("res://scripts/audio.gd")
const Fx := preload("res://scripts/fx.gd")
const SLOWMO_SCALE := 0.35
const SLOWMO_HOLD := 0.6          # real seconds at SLOWMO_SCALE
const SLOWMO_EASE := 0.3          # real seconds easing back to 1.0
const ROPE_BOUNCE_TIME := 0.45
var audio: Node
var fx: Node3D
var hitstop_until_ms := 0         # wrestlers' tick is frozen until this Time.get_ticks_msec()
var slowmo_start_ms := -1         # -1 = no slow motion running
var buf_strike := false           # button presses buffered during hit-stop
var buf_grapple := false
var buf_run := false
var buf_pin := false
var feel_last_count := 0          # highest pin count of the current cover (for near-falls)
var rope_rest := {}               # rope Node3D -> rest position (captured on first bounce)
var rope_bounce_t := PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])  # per side; < 0 = idle
var rope_bounce_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var rope_bounce_dir: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

# HUD
var hud: CanvasLayer
var bars := {}
var announce_label: Label
var announce_timer := 0.0
var count_label: Label
var count_timer := 0.0
var hint_label: Label
var win_panel: Control
var win_label: Label


func _ready() -> void:
	randomize()
	Engine.time_scale = 1.0
	_setup_input()
	audio = Audio.new()
	add_child(audio)
	_build_environment()
	_build_arena()
	_build_crowd()

	ring_root = Node3D.new()
	ring_root.position.y = RING_TOP
	add_child(ring_root)
	# Each look: street clothes + style switches used by wrestler.gd's model.
	# "gear" is the wrestler's signature colour (HUD, win banner).
	var tank := {
		"gear": Color(0.8, 0.14, 0.1), "skin": Color(0.87, 0.64, 0.47),
		"hair": "flattop", "hair_color": Color(0.3, 0.18, 0.08), "stubble": true, "facial": "goatee",
		"top": "flannel", "top_color": Color(0.72, 0.12, 0.1), "top_pattern": "plaid",
		"top_accent": Color(0.08, 0.06, 0.06),
		"bottom": "cargo_shorts", "bottom_color": Color(0.6, 0.53, 0.38),
		"shoes": "hightops", "shoe_color": Color(0.1, 0.1, 0.12), "shoe_accent": Color(0.85, 0.15, 0.12),
		"sock_l": Color(0.95, 0.95, 0.92), "sock_accent": Color(0.8, 0.14, 0.1),
		"hat": "cap_back", "hat_color": Color(0.14, 0.2, 0.42), "wristband_color": Color(0.95, 0.95, 0.92),
		"knee_brace": "left", "bulk": 1.15, "gut": 0.035,
	}
	var kid := {
		"gear": Color(0.15, 0.75, 0.3), "skin": Color(0.66, 0.46, 0.32),
		"mask": true, "mask_color": Color(0.12, 0.7, 0.28), "mask_trim": Color(1.0, 0.82, 0.1),
		"hair_color": Color.BLACK,
		"top": "hoodie", "top_color": Color(0.52, 0.52, 0.55), "top_pattern": "logo",
		"top_accent": Color(0.12, 0.6, 0.25), "sleeves": "long",
		"bottom": "basketball_shorts", "bottom_color": Color(0.14, 0.26, 0.75),
		"bottom_accent": Color(0.95, 0.95, 0.95),
		"shoes": "skate", "shoe_color": Color(0.12, 0.12, 0.14), "shoe_accent": Color(0.95, 0.95, 0.92),
		"sock_l": Color(0.95, 0.85, 0.15), "sock_r": Color(0.92, 0.92, 0.9), "sock_accent": Color(0.85, 0.15, 0.6),
		"bulk": 0.85,
	}
	p1 = _spawn("TANK MAGRUDER", tank, false, Vector3(-1.8, 0, 0.3))
	p2 = _spawn("LIL PELIGRO", kid, true, Vector3(1.8, 0, -0.3))
	p1.opponent = p2
	p2.opponent = p1
	p1._snap_face_opponent()
	p2._snap_face_opponent()

	fx = Fx.new()
	add_child(fx)

	_build_hud()
	_announce("FIGHT!", 1.5)
	audio.ring_bell(1)
	audio.start_crowd()
	audio.set_crowd_intensity(0.3)


# ---------------------------------------------------------------- input

func _add_action(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		return  # already registered (e.g. after a rematch reload)
	InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)


func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("strike", [KEY_J, KEY_Z])
	_add_action("grapple", [KEY_K, KEY_X])
	_add_action("run", [KEY_L, KEY_C])
	_add_action("pin", [KEY_SPACE, KEY_V])
	_add_action("restart", [KEY_R, KEY_ENTER])


# ---------------------------------------------------------------- world building

# Hooks for other systems (impacts, crowd reactions, rope physics):
var cam_fov_kick := 0.0          # degrees added to the 40 deg broadcast FOV; decays back to 0
var crowd_hype := 0.0            # 0..1, crowd excitement; drifts back down slowly on its own
var rope_nodes: Array[Node3D] = []  # 12 ropes: for each height (bottom, middle, top): +z, -z, +x, -x
var ring_spot: SpotLight3D       # the work light on a stand: key light over the ring
var crowd_mat: ShaderMaterial    # the friends-in-the-yard billboard material
var crowd_hype_shown := 0.0
var crowd_spots := PackedVector3Array()
var flash_nodes: Array[MeshInstance3D] = []
var flash_timers := PackedFloat32Array()

# Static scenery is merged per material into a handful of meshes (few draw calls on mobile).
var _batches := {}               # batch key -> SurfaceTool
var _bulb_xforms: Array[Transform3D] = []
var _bulb_cols: Array[Color] = []
# Spectators collected while building, turned into one MultiMesh in _build_crowd.
var _fan_xforms: Array[Transform3D] = []
var _fan_custom: Array[Color] = []

const BOX_NORMALS: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
# Fan atlas variants (8 cells of 16x32 px).
const FAN_HOODIE := 0
const FAN_CAP := 1
const FAN_CHEER := 2
const FAN_PHONE := 3
const FAN_CUP := 4
const FAN_SIT := 5
const FAN_SIT_CUP := 6
const FAN_HAIR := 7

const CROWD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_linear;
uniform float hype = 0.0;
uniform float brightness = 1.0;

varying vec3 shirt;
varying float lit;

float h1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	// INSTANCE_CUSTOM: x = atlas variant / 8, y = bob scale, z = light level, w = 1 if may switch to cheering.
	float id = float(INSTANCE_ID);
	float ph = h1(id) * 6.2831;
	float spd = mix(2.0, 9.5, hype) * (0.8 + 0.4 * h1(id + 3.1));
	float amp = mix(0.02, 0.24, hype) * (0.5 + h1(id + 7.7)) * INSTANCE_CUSTOM.y;
	float top = 1.0 - UV.y;
	float wave = sin(TIME * spd + ph);
	VERTEX.y += max(0.0, wave) * amp;
	VERTEX.x += sin(TIME * 1.3 + ph) * 0.05 * top;
	shirt = COLOR.rgb;
	lit = INSTANCE_CUSTOM.z;
	float variant = floor(INSTANCE_CUSTOM.x * 8.0 + 0.5);
	if (INSTANCE_CUSTOM.w > 0.5 && hype > 0.45 && wave > 0.6 - hype) {
		variant = 2.0;
	}
	UV.x = (UV.x + variant) * 0.125;
}

void fragment() {
	vec4 t = texture(tex, UV);
	float m = smoothstep(0.8, 0.97, min(t.r, min(t.g, t.b)));
	float scr = step(0.85, t.g) * step(0.85, t.b) * step(t.r, 0.2);
	vec3 c = mix(t.rgb, t.rgb * shirt, m) * (lit + hype * 0.25) * brightness;
	ALBEDO = mix(c, vec3(0.75, 0.92, 1.0) * 1.5, scr);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
"""

const SKY_SHADER := """
shader_type sky;

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -0.2, 1.0);
	vec3 col = mix(vec3(0.12, 0.08, 0.22), vec3(0.015, 0.02, 0.07), smoothstep(0.0, 0.5, h));
	vec3 cell = floor(d * 260.0);
	float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float star = step(0.992, r) * smoothstep(0.03, 0.2, d.y);
	col += vec3(0.9, 0.9, 1.0) * star * (0.4 + 0.6 * fract(r * 91.7));
	vec3 md = normalize(vec3(0.47, 0.11, -0.88));
	float mm = dot(d, md);
	col += vec3(0.25, 0.25, 0.4) * pow(max(mm, 0.0), 300.0);
	col = mix(col, vec3(1.0, 0.97, 0.82), smoothstep(0.99955, 0.9997, mm));
	COLOR = col;
}
"""


func _mat(c: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	return m


func _box(size: Vector3, pos: Vector3, color: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(color, emissive)
	add_child(mi)
	return mi


func _plane(size: Vector2, pos: Vector3, m: Material) -> MeshInstance3D:
	# Flat, upward-facing quad with 0..1 UVs (BoxMesh UVs are an atlas, so textures go here).
	var mi := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = size
	mi.mesh = p
	mi.position = pos
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _tex_mat(tex: Texture2D, scissor := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.roughness = 0.9
	if scissor:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	return m


func _px_rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)


# ---- merged-geometry helpers (all scenery goes through these)

func _st(key: String) -> SurfaceTool:
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	return _batches[key]


func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, a: Vector3, b: Vector3, col: Color, uvs: float) -> void:
	# Godot front faces wind clockwise; callers pass corners in that order.
	for p: Vector3 in [p0, p1, p2]:
		st.set_color(col)
		st.set_normal(n)
		st.set_uv(Vector2(p.dot(a), -p.dot(b)) * uvs)
		st.add_vertex(p)


func _quad(st: SurfaceTool, bl: Vector3, tl: Vector3, tr: Vector3, br: Vector3, n: Vector3, a: Vector3, b: Vector3, col: Color, uvs: float) -> void:
	_tri(st, bl, tl, tr, n, a, b, col, uvs)
	_tri(st, bl, tr, br, n, a, b, col, uvs)


func _sbox(key: String, size: Vector3, xf: Transform3D, col: Color, uvs := 1.0) -> void:
	var st := _st(key)
	var h := size * 0.5
	for n0 in BOX_NORMALS:
		var b0 := Vector3.UP
		if absf(n0.y) > 0.5:
			b0 = Vector3.FORWARD if n0.y > 0.0 else Vector3.BACK
		var a0 := b0.cross(n0)
		var c := n0 * n0.abs().dot(h)
		var ea := a0 * a0.abs().dot(h)
		var eb := b0 * b0.abs().dot(h)
		var n := (xf.basis * n0).normalized()
		var a := (xf.basis * a0).normalized()
		var b := (xf.basis * b0).normalized()
		_quad(st, xf * (c - ea - eb), xf * (c - ea + eb), xf * (c + ea + eb), xf * (c + ea - eb), n, a, b, col, uvs)


func _bx(key: String, size: Vector3, pos: Vector3, col: Color, yaw := 0.0, uvs := 1.0) -> void:
	_sbox(key, size, Transform3D(Basis(Vector3.UP, yaw), pos), col, uvs)


func _scyl(key: String, rb: float, rt: float, height: float, xf: Transform3D, col: Color, segs := 8) -> void:
	var st := _st(key)
	var hh := height * 0.5
	var up := (xf.basis * Vector3.UP).normalized()
	var top_c := xf * Vector3(0, hh, 0)
	var bot_c := xf * Vector3(0, -hh, 0)
	for i in segs:
		var t0 := TAU * i / segs
		var t1 := TAU * (i + 1) / segs
		var tm := (t0 + t1) * 0.5
		var d0 := Vector3(cos(t0), 0, sin(t0))
		var d1 := Vector3(cos(t1), 0, sin(t1))
		var b0 := xf * (d0 * rb + Vector3(0, -hh, 0))
		var b1 := xf * (d1 * rb + Vector3(0, -hh, 0))
		var p0 := xf * (d0 * rt + Vector3(0, hh, 0))
		var p1 := xf * (d1 * rt + Vector3(0, hh, 0))
		var n := (xf.basis * Vector3(cos(tm), (rb - rt) / height, sin(tm))).normalized()
		var a := (xf.basis * Vector3(-sin(tm), 0, cos(tm))).normalized()
		_quad(st, b1, p1, p0, b0, n, a, up, col, 1.0)
		if rt > 0.001:
			_tri(st, top_c, p0, p1, up, Vector3.RIGHT, Vector3.FORWARD, col, 1.0)
		if rb > 0.001:
			_tri(st, bot_c, b1, b0, -up, Vector3.RIGHT, Vector3.BACK, col, 1.0)


func _cy(key: String, rb: float, rt: float, height: float, pos: Vector3, col: Color, segs := 8) -> void:
	_scyl(key, rb, rt, height, Transform3D(Basis(), pos), col, segs)


func _beam(key: String, from: Vector3, to: Vector3, thick: float, col: Color) -> void:
	# A thin box stretched between two points (wires, ladder rails, tripod legs).
	var d := to - from
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var xf := Transform3D(Basis.looking_at(d, up), (from + to) * 0.5)
	_sbox(key, Vector3(thick, thick, d.length()), xf, col)


func _batch_mat(key: String) -> Material:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	match key:
		"glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"wood":
			m.albedo_texture = _make_wood_texture()
		"siding":
			m.albedo_texture = _make_siding_texture()
		"shingle":
			m.albedo_texture = _make_shingle_texture()
		"metal":
			m.metallic = 0.6
			m.roughness = 0.45
	return m


func _flush_batches() -> void:
	for key: String in _batches:
		var st: SurfaceTool = _batches[key]
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _batch_mat(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batches.clear()


# ---- generated textures (tiny, blurry, N64-style)

func _make_grass_texture() -> ImageTexture:
	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var j := randf_range(-0.05, 0.05)
			var c := Color(0.17 + j, 0.33 + j * 1.6, 0.12 + j)
			if randf() < 0.12:
				c = Color(0.25, 0.45, 0.16)  # bright blade
			elif randf() < 0.08:
				c = Color(0.11, 0.22, 0.08)  # dark clump
			img.set_pixel(x, y, c)
	for i in 3:  # dry patches
		var cx := randi() % n
		var cy := randi() % n
		for y in range(-2, 3):
			for x in range(-3, 4):
				if randf() < 0.6:
					img.set_pixel((cx + x + n) % n, (cy + y + n) % n, Color(0.32, 0.36, 0.16))
	return ImageTexture.create_from_image(img)


func _make_wood_texture() -> ImageTexture:
	# Greyscale-ish grain (tinted per vertex): stripes along u with a wobble and a knot or two.
	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var g := 0.84 + 0.09 * sin(y * 1.7 + sin(x * 0.35) * 1.6) + randf_range(-0.04, 0.04)
			if (y + int(sin(x * 0.2) * 2.0)) % 11 == 0:
				g -= 0.18
			img.set_pixel(x, y, Color(g, g * 0.97, g * 0.92))
	for k in 2:
		var kx := randi() % n
		var ky := randi() % n
		for y in range(-1, 2):
			for x in range(-2, 3):
				img.set_pixel((kx + x + n) % n, (ky + y + n) % n, Color(0.5, 0.45, 0.4))
	return ImageTexture.create_from_image(img)


func _make_siding_texture() -> ImageTexture:
	# Horizontal lap siding: a dark shadow line every 4 px.
	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := y % 4
			var g := [0.55, 0.98, 0.93, 0.88][r] as float
			g += randf_range(-0.025, 0.025)
			img.set_pixel(x, y, Color(g, g, g))
	return ImageTexture.create_from_image(img)


func _make_shingle_texture() -> ImageTexture:
	var n := 32
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var row := y / 4
		for x in n:
			var tab := (x + (row % 2) * 3) / 6
			var g := 0.7 + 0.25 * fposmod(sin(float(tab * 7 + row * 13)) * 43.7, 1.0)
			if y % 4 == 3 or (x + (row % 2) * 3) % 6 == 0:
				g *= 0.55
			g += randf_range(-0.04, 0.04)
			img.set_pixel(x, y, Color(g, g, g))
	return ImageTexture.create_from_image(img)


func _make_tarp_texture() -> ImageTexture:
	# Stained blue tarp: hemmed edge with grommets, fold creases, dirt blotches, duct-tape patches.
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var w := 0.04 * sin(x * 0.21 + y * 0.07) + 0.03 * sin(y * 0.33 - x * 0.12)
			var c := Color(0.13 + w, 0.32 + w, 0.7 + w * 1.5)
			if x == 21 or x == 42 or y == 32:
				c = c.lightened(0.12)  # fold creases
			var edge: int = mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			if edge < 2:
				c = c.darkened(0.25)
			var j := randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(c.r + j, c.g + j, c.b + j))
	for i in range(4, n - 2, 8):  # grommets
		for p: Vector2i in [Vector2i(i, 0), Vector2i(i, n - 1), Vector2i(0, i), Vector2i(n - 1, i)]:
			img.set_pixel(p.x, p.y, Color(0.8, 0.8, 0.75))
	var stains: Array[Vector3] = [Vector3(12, 14, 4), Vector3(50, 20, 3), Vector3(16, 50, 5), Vector3(44, 46, 3), Vector3(34, 9, 2), Vector3(7, 34, 3)]
	for s in stains:
		for y in range(int(s.y - s.z) - 1, int(s.y + s.z) + 2):
			for x in range(int(s.x - s.z) - 1, int(s.x + s.z) + 2):
				if x < 0 or y < 0 or x >= n or y >= n:
					continue
				if Vector2(x, y).distance_to(Vector2(s.x, s.y)) < s.z + randf_range(-1.0, 1.0):
					var o := img.get_pixel(x, y)
					img.set_pixel(x, y, Color(o.r * 0.75 + 0.06, o.g * 0.72 + 0.03, o.b * 0.6))
	var tape := Color(0.66, 0.66, 0.63)
	_px_rect(img, 6, 6, 9, 3, tape)
	_px_rect(img, 49, 52, 3, 8, tape)
	_px_rect(img, 46, 55, 9, 3, tape)
	_px_rect(img, 52, 8, 7, 2, tape)
	_px_rect(img, 8, 55, 10, 3, tape)
	for k in 7:  # an X patch
		img.set_pixel(54 + k - 3, 30 + k - 3, tape)
		img.set_pixel(54 + k - 3, 30 - k + 3, tape)
		img.set_pixel(54 + k - 2, 30 + k - 3, tape)
		img.set_pixel(54 + k - 2, 30 - k + 3, tape)
	return ImageTexture.create_from_image(img)


const PIXEL_FONT := {
	"C": ["011", "100", "100", "100", "011"], "E": ["111", "100", "110", "100", "111"],
	"G": ["011", "100", "101", "101", "011"], "I": ["111", "010", "010", "010", "111"],
	"L": ["100", "100", "100", "100", "111"], "N": ["101", "111", "111", "101", "101"],
	"R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
	"T": ["111", "010", "010", "010", "010"], "W": ["101", "101", "101", "111", "101"],
	"Y": ["101", "101", "010", "010", "010"], "2": ["110", "001", "010", "100", "111"],
}


func _px_text(img: Image, text: String, x0: int, y0: int, sc: int, col: Color) -> void:
	var x := x0
	for ch in text:
		if PIXEL_FONT.has(ch):
			var rows: Array = PIXEL_FONT[ch]
			for ry in 5:
				var row: String = rows[ry]
				for rx in 3:
					if row[rx] == "1":
						_px_rect(img, x + rx * sc, y0 + ry * sc, sc, sc, col)
		x += 4 * sc


func _px_text_w(text: String, sc: int) -> int:
	return text.length() * 4 * sc - sc


func _make_logo_texture() -> ImageTexture:
	# Spray-painted "C2C / CITY 2 CITY / WRESTLING" with lightning bolts, a black outline and drips.
	var n := 96
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var yellow := Color(1.0, 0.86, 0.12)
	var red := Color(0.92, 0.14, 0.1)
	for side: float in [-1.0, 1.0]:  # little bolts flanking the big letters
		var cx := 48.0 + side * 40.0
		var bolt := PackedVector2Array([Vector2(cx + 1, 8), Vector2(cx - 5, 21), Vector2(cx - 1, 21), Vector2(cx - 4, 33),
			Vector2(cx + 5, 17), Vector2(cx + 1, 17), Vector2(cx + 4, 8)])
		for y in range(6, 36):
			for x in range(int(cx) - 7, int(cx) + 8):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), bolt):
					img.set_pixel(x, y, yellow)
	_px_text(img, "C2C", (n - _px_text_w("C2C", 5)) / 2, 8, 5, red)
	_px_text(img, "CITY 2 CITY", (n - _px_text_w("CITY 2 CITY", 2)) / 2, 44, 2, Color(0.95, 0.95, 0.9))
	_px_text(img, "WRESTLING", (n - _px_text_w("WRESTLING", 2)) / 2, 60, 2, yellow)
	# drips: pull paint down below the bottom of random letter columns
	for i in 14:
		var dx := randi_range(4, n - 5)
		for y0: int in [32, 53, 69]:
			if img.get_pixel(dx, y0).a > 0.5 and randf() < 0.6:
				for k in randi_range(1, 5):
					if y0 + k < n:
						img.set_pixel(dx, y0 + k, img.get_pixel(dx, y0))
	# black outline / overspray
	var src := img.duplicate() as Image
	for y in n:
		for x in n:
			if src.get_pixel(x, y).a > 0.5:
				continue
			var near := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var xx := x + ox
					var yy := y + oy
					if xx >= 0 and yy >= 0 and xx < n and yy < n and src.get_pixel(xx, yy).a > 0.5:
						near = true
			if near:
				img.set_pixel(x, y, Color(0.06, 0.05, 0.08))
			elif randf() < 0.008:
				img.set_pixel(x, y, Color(0.9, 0.2, 0.15))  # stray speckle
	return ImageTexture.create_from_image(img)


func _fan_head(img: Image, ox: int, y: int, skin: Color, hair: Color) -> void:
	_px_rect(img, ox + 5, y, 6, 7, skin)
	_px_rect(img, ox + 5, y - 1, 6, 2, hair)
	_px_rect(img, ox + 5, y + 1, 1, 2, hair)
	_px_rect(img, ox + 10, y + 1, 1, 2, hair)
	img.set_pixel(ox + 6, y + 3, Color(0.08, 0.05, 0.05))
	img.set_pixel(ox + 9, y + 3, Color(0.08, 0.05, 0.05))
	_px_rect(img, ox + 7, y + 5, 2, 1, skin.darkened(0.45))


func _make_crowd_texture() -> ImageTexture:
	# 128x32 atlas: eight 16x32 friends. Pure-white pixels are the shirt/hoodie (tinted per instance),
	# pure cyan is a glowing phone screen.
	var img := Image.create_empty(128, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0))
	var white := Color(1, 1, 1)
	var screen := Color(0, 1, 1)
	var skins: Array[Color] = [Color(0.93, 0.74, 0.58), Color(0.55, 0.36, 0.24), Color(0.8, 0.6, 0.45), Color(0.38, 0.25, 0.17),
		Color(0.85, 0.66, 0.5), Color(0.62, 0.42, 0.3), Color(0.92, 0.72, 0.56), Color(0.45, 0.3, 0.2)]
	var hairs: Array[Color] = [Color(0.25, 0.16, 0.08), Color(0.05, 0.05, 0.05), Color(0.75, 0.6, 0.2), Color(0.1, 0.07, 0.05),
		Color(0.4, 0.22, 0.1), Color(0.08, 0.06, 0.05), Color(0.6, 0.3, 0.12), Color(0.1, 0.08, 0.06)]
	var jeans := Color(0.2, 0.27, 0.48)
	var dark := Color(0.13, 0.13, 0.15)
	var cup := Color(0.85, 0.1, 0.12)
	for v in 8:
		var ox := v * 16
		var skin: Color = skins[v]
		var hair: Color = hairs[v]
		var pants: Color = jeans if v % 2 == 0 else dark
		if v == FAN_SIT or v == FAN_SIT_CUP:
			# Sitting: lower head, short torso, knees toward the viewer, shins down.
			_fan_head(img, ox, 10, skin, hair)
			_px_rect(img, ox + 7, 17, 2, 1, skin)
			_px_rect(img, ox + 4, 18, 8, 6, white)
			_px_rect(img, ox + 3, 24, 10, 3, pants)
			_px_rect(img, ox + 4, 27, 3, 4, pants)
			_px_rect(img, ox + 9, 27, 3, 4, pants)
			_px_rect(img, ox + 4, 31, 3, 1, dark)
			_px_rect(img, ox + 9, 31, 3, 1, dark)
			_px_rect(img, ox + 2, 18, 2, 3, white)
			_px_rect(img, ox + 12, 18, 2, 3, white)
			_px_rect(img, ox + 2, 21, 2, 3, skin)
			_px_rect(img, ox + 12, 21, 2, 3, skin)
			if v == FAN_SIT:
				_px_rect(img, ox + 5, 9, 6, 2, white)  # hood
				_px_rect(img, ox + 4, 10, 1, 6, white)
				_px_rect(img, ox + 11, 10, 1, 6, white)
			else:
				_px_rect(img, ox + 12, 19, 2, 3, cup)
				_px_rect(img, ox + 4, 8, 8, 2, Color(0.15, 0.2, 0.55))  # beanie
			continue
		# Standing body
		_fan_head(img, ox, 3, skin, hair)
		_px_rect(img, ox + 7, 10, 2, 1, skin)
		_px_rect(img, ox + 4, 11, 8, 10, white)
		_px_rect(img, ox + 4, 21, 8, 2, pants)
		_px_rect(img, ox + 4, 23, 3, 8, pants)
		_px_rect(img, ox + 9, 23, 3, 8, pants)
		_px_rect(img, ox + 4, 31, 3, 1, dark)
		_px_rect(img, ox + 9, 31, 3, 1, dark)
		var left_down := true
		var right_down := true
		match v:
			FAN_HOODIE:
				_px_rect(img, ox + 5, 1, 6, 2, white)
				_px_rect(img, ox + 4, 2, 1, 8, white)
				_px_rect(img, ox + 11, 2, 1, 8, white)
				_px_rect(img, ox + 6, 13, 4, 3, Color(0.85, 0.85, 0.85))  # pocket
				_px_rect(img, ox + 7, 11, 1, 3, dark)  # drawstrings
				_px_rect(img, ox + 9, 11, 1, 3, dark)
			FAN_CAP:
				_px_rect(img, ox + 4, 1, 8, 2, Color(0.12, 0.12, 0.14))
				_px_rect(img, ox + 2, 2, 3, 1, Color(0.12, 0.12, 0.14))  # backwards brim
				_px_rect(img, ox + 6, 14, 4, 3, Color(0.85, 0.2, 0.2))  # tee print
			FAN_CHEER:
				_px_rect(img, ox + 2, 1, 2, 9, skin)
				_px_rect(img, ox + 12, 1, 2, 9, skin)
				_px_rect(img, ox + 2, 10, 2, 2, white)
				_px_rect(img, ox + 12, 10, 2, 2, white)
				_px_rect(img, ox + 7, 8, 2, 2, Color(0.25, 0.05, 0.05))  # yelling
				left_down = false
				right_down = false
			FAN_PHONE:
				_px_rect(img, ox + 2, 5, 2, 6, skin)
				_px_rect(img, ox + 2, 11, 2, 2, white)
				_px_rect(img, ox + 1, 0, 4, 6, dark)
				_px_rect(img, ox + 2, 1, 2, 4, screen)
				left_down = false
			FAN_CUP:
				_px_rect(img, ox + 4, 1, 8, 3, Color(0.85, 0.5, 0.1))  # beanie
				_px_rect(img, ox + 12, 11, 2, 3, white)
				_px_rect(img, ox + 12, 14, 2, 3, skin)
				_px_rect(img, ox + 12, 15, 3, 4, cup)
				right_down = false
			_:  # long hair, flannel-ish stripes
				_px_rect(img, ox + 4, 2, 1, 9, hair)
				_px_rect(img, ox + 11, 2, 1, 9, hair)
				for yy in range(12, 21, 3):
					_px_rect(img, ox + 4, yy, 8, 1, Color(0.8, 0.8, 0.8))
		if left_down:
			_px_rect(img, ox + 2, 11, 2, 3, white)
			_px_rect(img, ox + 2, 14, 2, 6, skin)
		if right_down:
			_px_rect(img, ox + 12, 11, 2, 3, white)
			_px_rect(img, ox + 12, 14, 2, 6, skin)
	return ImageTexture.create_from_image(img)


func _make_flash_texture() -> ImageTexture:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x, y).distance_to(Vector2(7.5, 7.5)) / 7.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


# ---- lights, sky, camera

func _build_environment() -> void:
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
	env.ambient_light_color = Color(0.42, 0.42, 0.78)
	env.ambient_light_energy = 0.42
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.09, 0.2)
	env.fog_light_energy = 1.0
	env.fog_density = 0.016
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Cool moonlight fill from the camera side so faces never go black; no shadows (cheap).
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40, 20, 0)
	moon.light_energy = 0.35
	moon.light_color = Color(0.6, 0.66, 1.0)
	add_child(moon)

	# Work light on a tripod at the front-left: the key light over the ring.
	var wl_pos := Vector3(-6.4, 6.0, 2.6)
	ring_spot = SpotLight3D.new()
	ring_spot.transform = Transform3D(Basis.looking_at(Vector3(0.6, 1.0, -0.6) - wl_pos), wl_pos)
	ring_spot.spot_angle = 40.0
	ring_spot.spot_angle_attenuation = 0.9
	ring_spot.spot_range = 20.0
	ring_spot.spot_attenuation = 0.6
	ring_spot.light_energy = 5.5
	ring_spot.light_color = Color(1.0, 0.95, 0.84)
	ring_spot.shadow_enabled = true
	add_child(ring_spot)

	# Warm porch light by the sliding door.
	var porch := OmniLight3D.new()
	porch.position = Vector3(-0.9, 2.4, -14.3)
	porch.omni_range = 7.5
	porch.light_energy = 2.2
	porch.light_color = Color(1.0, 0.68, 0.32)
	add_child(porch)

	# Glow from the string lights hanging over the ring.
	for p: Vector3 in [Vector3(0, 4.4, -7.0), Vector3(0, 4.4, -1.0)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 8.0
		o.light_energy = 0.9
		o.light_color = Color(1.0, 0.78, 0.5)
		add_child(o)

	camera = Camera3D.new()
	camera.fov = 40
	camera.position = Vector3(0, 4.3, 7.5)
	add_child(camera)
	camera.look_at(Vector3(0, RING_TOP + 1.6, 0))


# ---- the yard and the homemade ring

func _build_arena() -> void:
	_plane(Vector2(70, 70), Vector3(0, 0, 0), _grass_mat())
	_build_ring()
	_build_house()
	_build_fence()
	_build_props()
	_build_car()
	_build_string_lights()
	_flush_batches()


func _grass_mat() -> StandardMaterial3D:
	var m := _tex_mat(_make_grass_texture())
	m.uv1_scale = Vector3(28, 28, 1)
	return m


func _build_ring() -> void:
	var gap := Color(0.03, 0.025, 0.02)
	var cinder := Color(0.5, 0.5, 0.48)
	var ply := Color(0.8, 0.64, 0.42)
	var h := 4.15
	# Shadowy underside, cinder blocks at the corners + side midpoints, plywood skirt and apron.
	_bx("flat", Vector3(8.2, 0.4, 8.2), Vector3(0, 0.2, 0), gap)
	for gx: float in [-1.0, 0.0, 1.0]:
		for gz: float in [-1.0, 0.0, 1.0]:
			if gx == 0.0 and gz == 0.0:
				continue
			var bp := Vector3(gx * 4.1, 0, gz * 4.1)
			for k in 2:
				var yaw := 0.0 if k == 0 else PI * 0.5
				_bx("flat", Vector3(0.4, 0.2, 0.2), bp + Vector3(0, 0.1 + k * 0.2, 0), cinder.darkened(randf() * 0.15), yaw)
				for sgn: float in [-1.0, 1.0]:
					var along := Basis(Vector3.UP, yaw) * Vector3(sgn * 0.1, 0, 0)
					_bx("flat", Vector3(0.12, 0.11, 0.205), bp + Vector3(0, 0.1 + k * 0.2, 0) + along, gap, yaw)
	_bx("wood", Vector3(8.8, 0.56, 8.8), Vector3(0, 0.66, 0), ply)                   # plywood skirt
	_bx("wood", Vector3(8.7, 0.1, 8.7), Vector3(0, 0.94, 0), ply.lightened(0.08))   # apron edge, top 0.99
	_bx("flat", Vector3(8.84, 0.06, 0.04), Vector3(0, 0.55, 4.41), Color(0.62, 0.62, 0.6))  # duct tape seam
	# Tarp canvas + spray-painted logo
	_plane(Vector2(8.3, 8.3), Vector3(0, RING_TOP, 0), _tex_mat(_make_tarp_texture()))
	_plane(Vector2(4.0, 4.0), Vector3(0, RING_TOP + 0.01, 0), _tex_mat(_make_logo_texture(), true))

	# Wooden 4x4 posts with taped-pillow turnbuckle pads
	var corners: Array[Vector2] = [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]
	var pillow_cols: Array[Color] = [Color(0.86, 0.82, 0.74), Color(0.9, 0.62, 0.68), Color(0.55, 0.7, 0.9), Color(0.75, 0.25, 0.22)]
	var tape := Color(0.6, 0.6, 0.58)
	for ci in corners.size():
		var cpos: Vector2 = corners[ci]
		_bx("wood", Vector3(0.2, 2.1, 0.2), Vector3(cpos.x, 1.45, cpos.y), Color(0.62, 0.48, 0.32), 0.0, 2.0)
		var inward := Vector3(-signf(cpos.x), 0, -signf(cpos.y)).normalized()
		var b := Basis.looking_at(inward)
		var pc := Vector3(cpos.x, RING_TOP + 1.05, cpos.y) + inward * 0.16
		_sbox("flat", Vector3(0.44, 0.6, 0.2), Transform3D(b, pc), pillow_cols[ci])
		for s: float in [-0.17, 0.17]:
			_sbox("flat", Vector3(0.46, 0.06, 0.22), Transform3D(b, pc + Vector3(0, s, 0)), tape)
		_sbox("flat", Vector3(0.3, 0.22, 0.22), Transform3D(b, Vector3(cpos.x, RING_TOP + 0.45, cpos.y) + inward * 0.14), Color(0.95, 0.85, 0.3))
		_sbox("flat", Vector3(0.32, 0.05, 0.24), Transform3D(b, Vector3(cpos.x, RING_TOP + 0.45, cpos.y) + inward * 0.14), tape)

	# Ropes: garden hose (bottom), yellow rope (middle), orange extension cord (top).
	var heights: Array[float] = [0.45, 0.85, 1.25]
	var rope_cols: Array[Color] = [Color(0.12, 0.55, 0.2), Color(0.95, 0.8, 0.18), Color(1.0, 0.45, 0.06)]
	var rope_mesh := CylinderMesh.new()
	rope_mesh.top_radius = 0.04
	rope_mesh.bottom_radius = 0.04
	rope_mesh.height = 2 * h
	rope_mesh.radial_segments = 6
	rope_mesh.rings = 1
	rope_nodes.clear()
	for i in 3:
		var y: float = RING_TOP + heights[i]
		var rm := _mat(rope_cols[i])
		rm.roughness = 0.5
		var spots: Array[Vector3] = [Vector3(0, y, h), Vector3(0, y, -h), Vector3(h, y, 0), Vector3(-h, y, 0)]
		for si in 4:
			var r := MeshInstance3D.new()
			r.mesh = rope_mesh
			r.material_override = rm
			r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			r.position = spots[si]
			if si < 2:
				r.rotation_degrees = Vector3(0, 0, 90)   # along x
			else:
				r.rotation_degrees = Vector3(90, 0, 0)   # along z
			add_child(r)
			rope_nodes.append(r)


func _build_house() -> void:
	# Back of a two-story house at -z: the backdrop of the broadcast shot.
	var wall_z := -15.0
	var depth := 8.0
	var w := 9.0
	var top := 6.2
	var ridge := 8.4
	var siding := Color(0.72, 0.78, 0.86)
	var trim := Color(0.92, 0.92, 0.9)
	_bx("siding", Vector3(2 * w, top, 0.3), Vector3(0, top * 0.5, wall_z - 0.15), siding, 0.0, 0.6)
	_bx("siding", Vector3(0.3, top, depth), Vector3(-w, top * 0.5, wall_z - depth * 0.5), siding, 0.0, 0.6)
	_bx("siding", Vector3(0.3, top, depth), Vector3(w, top * 0.5, wall_z - depth * 0.5), siding, 0.0, 0.6)
	_bx("flat", Vector3(2 * w + 0.3, 0.5, 0.35), Vector3(0, 0.25, wall_z - 0.12), Color(0.45, 0.42, 0.4))  # foundation
	# Gable ends (triangles) on both sides
	var st := _st("siding")
	for s: float in [-1.0, 1.0]:
		var x := s * (w + 0.15)
		var p0 := Vector3(x, top, wall_z)
		var p1 := Vector3(x, ridge, wall_z - depth * 0.5)
		var p2 := Vector3(x, top, wall_z - depth)
		var n := Vector3(s, 0, 0)
		if s > 0.0:
			_tri(st, p0, p1, p2, n, Vector3.FORWARD, Vector3.UP, siding, 0.6)
		else:
			_tri(st, p2, p1, p0, n, Vector3.BACK, Vector3.UP, siding, 0.6)
	# Roof: two slabs meeting at the ridge, overhanging the walls
	var run := depth * 0.5 + 0.6
	var rise := (ridge - top) * run / (depth * 0.5)
	var slope := atan2(rise, run)
	var slab_len := sqrt(run * run + rise * rise)
	var roof_col := Color(0.38, 0.33, 0.34)
	for s: float in [1.0, -1.0]:
		var zc := wall_z - depth * 0.5 + s * run * 0.5
		var yc := ridge + 0.1 - rise * 0.5
		var b := Basis(Vector3.RIGHT, slope * s)
		_sbox("shingle", Vector3(2 * w + 1.0, 0.16, slab_len), Transform3D(b, Vector3(0, yc, zc)), roof_col, 0.7)
	_bx("flat", Vector3(2 * w + 1.0, 0.14, 0.14), Vector3(0, top - 0.32, wall_z + 0.62), trim)  # gutter
	_bx("flat", Vector3(1.0, 2.6, 1.0), Vector3(5.5, ridge + 0.4, wall_z - 2.8), Color(0.5, 0.25, 0.2))  # chimney

	# Windows: upstairs (some lit warm, one TV-blue, one dark), kitchen window downstairs.
	var wf := wall_z + 0.02
	var ups: Array[float] = [-6.5, -2.4, 2.0, 6.2]
	var up_cols: Array[Color] = [Color(1.0, 0.82, 0.45), Color(0.08, 0.08, 0.12), Color(0.45, 0.6, 1.0), Color(1.0, 0.75, 0.4)]
	for i in ups.size():
		_bx("flat", Vector3(1.5, 1.4, 0.06), Vector3(ups[i], 4.55, wf), trim)
		_bx("glow", Vector3(1.3, 1.2, 0.06), Vector3(ups[i], 4.55, wf + 0.03), up_cols[i])
		_bx("flat", Vector3(0.06, 1.2, 0.07), Vector3(ups[i], 4.55, wf + 0.04), trim)
		_bx("flat", Vector3(1.3, 0.06, 0.07), Vector3(ups[i], 4.55, wf + 0.04), trim)
		_bx("flat", Vector3(0.3, 1.4, 0.06), Vector3(ups[i] - 0.92, 4.55, wf), Color(0.2, 0.28, 0.35))  # shutters
		_bx("flat", Vector3(0.3, 1.4, 0.06), Vector3(ups[i] + 0.92, 4.55, wf), Color(0.2, 0.28, 0.35))
	_bx("flat", Vector3(1.6, 1.2, 0.06), Vector3(4.2, 1.9, wf), trim)
	_bx("glow", Vector3(1.4, 1.0, 0.06), Vector3(4.2, 1.9, wf + 0.03), Color(1.0, 0.9, 0.62))
	_bx("flat", Vector3(1.4, 0.3, 0.07), Vector3(4.2, 2.25, wf + 0.04), Color(0.75, 0.3, 0.25))  # valance
	# Sliding glass door + porch light
	_bx("flat", Vector3(2.6, 2.3, 0.06), Vector3(-2.6, 1.6, wf), Color(0.75, 0.75, 0.78))
	_bx("glow", Vector3(2.4, 2.1, 0.06), Vector3(-2.6, 1.6, wf + 0.03), Color(0.62, 0.5, 0.34))
	_bx("flat", Vector3(0.08, 2.1, 0.08), Vector3(-2.6, 1.6, wf + 0.05), Color(0.75, 0.75, 0.78))
	_bx("flat", Vector3(0.7, 2.0, 0.07), Vector3(-3.45, 1.6, wf + 0.05), Color(0.55, 0.45, 0.3))  # half-drawn curtain
	_bx("glow", Vector3(0.2, 0.3, 0.16), Vector3(-0.9, 2.45, wf + 0.08), Color(1.0, 0.8, 0.45))

	# Back porch: wooden deck, steps, posts, railing and a low flat roof friends climb onto.
	var deck_y := 0.45
	var wood := Color(0.6, 0.45, 0.3)
	_bx("wood", Vector3(8.4, deck_y, 3.2), Vector3(-3.0, deck_y * 0.5, wall_z + 1.6), wood)
	_bx("wood", Vector3(1.6, 0.22, 0.4), Vector3(0.0, 0.11, wall_z + 3.4), wood.darkened(0.1))
	var roof_y := 3.05
	for px: float in [-7.0, -3.0, 1.0]:
		_bx("wood", Vector3(0.16, roof_y - deck_y, 0.16), Vector3(px, deck_y + (roof_y - deck_y) * 0.5, wall_z + 3.05), wood.lightened(0.15))
	_bx("wood", Vector3(4.0, 0.08, 0.08), Vector3(-5.0, deck_y + 0.85, wall_z + 3.05), wood.lightened(0.15))
	_bx("wood", Vector3(0.08, 0.08, 3.0), Vector3(-7.0, deck_y + 0.85, wall_z + 1.55), wood.lightened(0.15))
	for k in 9:
		_bx("wood", Vector3(0.05, 0.85, 0.05), Vector3(-6.6 + k * 0.42, deck_y + 0.42, wall_z + 3.05), wood.lightened(0.15))
	_bx("shingle", Vector3(8.8, 0.18, 3.6), Vector3(-3.0, roof_y + 0.09, wall_z + 1.75), Color(0.42, 0.38, 0.38), 0.0, 0.7)
	_bx("flat", Vector3(8.8, 0.22, 0.06), Vector3(-3.0, roof_y + 0.05, wall_z + 3.57), trim)
	# Hand-painted bedsheet banner hanging off the porch roof
	var sheet_z := wall_z + 3.62
	_bx("flat", Vector3(5.4, 0.9, 0.03), Vector3(-3.4, roof_y - 0.42, sheet_z), Color(0.9, 0.88, 0.8))
	_bx("flat", Vector3(5.4, 0.04, 0.035), Vector3(-3.4, roof_y - 0.1, sheet_z), Color(0.75, 0.72, 0.65))
	var lines: Array[String] = ["CITY 2 CITY WRESTLING", "BACKYARD BRAWL"]
	var line_cols: Array[Color] = [Color(0.75, 0.08, 0.08), Color(0.08, 0.12, 0.45)]
	for li in 2:
		var lab := Label3D.new()
		lab.text = lines[li]
		lab.font_size = 52 if li == 0 else 44
		lab.outline_size = 0
		lab.modulate = line_cols[li]
		lab.shaded = true
		lab.position = Vector3(-3.4, roof_y - 0.28 - li * 0.3, sheet_z + 0.025)
		lab.rotation_degrees = Vector3(0, 0, -1.5 + li * 2.5)  # wonky hand lettering
		add_child(lab)
	# Ladder up to the porch roof
	var lb := Vector3(1.6, 0, wall_z + 3.9)
	var lt := Vector3(1.6, roof_y + 0.6, wall_z + 3.3)
	for s: float in [-0.25, 0.25]:
		_beam("wood", lb + Vector3(s, 0, 0), lt + Vector3(s, 0, 0), 0.07, Color(0.75, 0.6, 0.35))
	for k in 8:
		var t := (k + 0.6) / 8.6
		_bx("wood", Vector3(0.5, 0.05, 0.05), lb.lerp(lt, t), Color(0.75, 0.6, 0.35))

	# Neighbour's house beyond the left fence + a dark tree line.
	var nb := Vector3(-23.0, 0, -15.0)
	_bx("siding", Vector3(9.0, 5.6, 7.0), nb + Vector3(0, 2.8, 0), Color(0.82, 0.72, 0.55), PI * 0.5, 0.6)
	for s: float in [-1.0, 1.0]:
		_sbox("shingle", Vector3(4.2, 0.2, 9.6), Transform3D(Basis(Vector3.BACK, -0.5 * s), nb + Vector3(1.85 * s, 6.6, 0)), Color(0.3, 0.26, 0.26), 0.7)
	_bx("glow", Vector3(0.06, 1.0, 1.2), nb + Vector3(3.52, 3.8, 1.8), Color(1.0, 0.85, 0.5))
	_bx("glow", Vector3(0.06, 1.0, 1.2), nb + Vector3(3.52, 1.6, -2.0), Color(0.5, 0.65, 1.0))
	var trees: Array[Vector3] = [Vector3(-14.0, 0, -21.0), Vector3(-17.5, 0, -6.0), Vector3(13.0, 0, -21.0), Vector3(17.0, 0, -16.0), Vector3(19.0, 0, -6.0), Vector3(-11.5, 0, -24.0)]
	for t in trees:
		var th := randf_range(6.0, 9.0)
		_cy("flat", 0.25, 0.2, 1.6, t + Vector3(0, 0.8, 0), Color(0.15, 0.1, 0.07), 6)
		_cy("flat", 2.4, 0.0, th * 0.6, t + Vector3(0, 1.4 + th * 0.3, 0), Color(0.05, 0.11, 0.08), 7)
		_cy("flat", 1.8, 0.0, th * 0.5, t + Vector3(0, 1.4 + th * 0.65, 0), Color(0.06, 0.13, 0.09), 7)


func _build_fence() -> void:
	# Wooden privacy fence: side runs at x = +/-14, back runs beside the house.
	var fh := 1.9
	var runs: Array = [
		[Vector3(-14, 0, -15), Vector3(-14, 0, 10)],
		[Vector3(14, 0, -15), Vector3(14, 0, 10)],
		[Vector3(-14, 0, -15), Vector3(-9.15, 0, -15)],
		[Vector3(9.15, 0, -15), Vector3(14, 0, -15)],
	]
	for r: Array in runs:
		var a: Vector3 = r[0]
		var b: Vector3 = r[1]
		var d := b - a
		var run_len := d.length()
		var dir := d / run_len
		var yaw := atan2(-dir.z, dir.x)
		var count := int(run_len / 0.32)
		for k in count:
			var p := a + dir * ((k + 0.5) * run_len / count)
			var tint := randf_range(-0.06, 0.06)
			var bh := fh + (0.08 if k % 2 == 0 else 0.0)
			_bx("wood", Vector3(run_len / count - 0.02, bh, 0.04), p + Vector3(0, bh * 0.5, 0), Color(0.52 + tint, 0.4 + tint, 0.28 + tint), yaw)
		var posts := int(run_len / 2.4)
		for k in posts + 1:
			var pp := a + dir * (k * run_len / posts)
			_bx("wood", Vector3(0.12, fh + 0.1, 0.12), pp + Vector3(0, (fh + 0.1) * 0.5, 0), Color(0.42, 0.32, 0.22), yaw)
		_bx("wood", Vector3(run_len, 0.08, 0.1), (a + b) * 0.5 + Vector3(0, fh - 0.25, 0), Color(0.45, 0.34, 0.23), yaw)


func _lawn_chair(pos: Vector3, face: Vector3, col: Color) -> void:
	var b := Basis.looking_at(face)
	var frame := Color(0.75, 0.76, 0.8)
	var xf := Transform3D(b, pos)
	_sbox("flat", Vector3(0.52, 0.04, 0.46), xf * Transform3D(Basis(), Vector3(0, 0.42, 0)), col)
	_sbox("flat", Vector3(0.52, 0.55, 0.04), xf * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.72, 0.25)), col)
	for sx: float in [-0.26, 0.26]:
		_beam("flat", xf * Vector3(sx, 0, -0.22), xf * Vector3(sx, 0.42, 0.18), 0.03, frame)
		_beam("flat", xf * Vector3(sx, 0, 0.22), xf * Vector3(sx, 0.42, -0.18), 0.03, frame)
		_beam("flat", xf * Vector3(sx, 0.62, -0.2), xf * Vector3(sx, 0.62, 0.2), 0.03, frame)


func _build_props() -> void:
	# Work light tripod (ring_spot sits in its lamp head)
	var wl := Vector3(-6.4, 0, 2.6)
	var black := Color(0.08, 0.08, 0.09)
	for k in 3:
		var a := TAU * k / 3.0
		_beam("flat", wl + Vector3(cos(a) * 0.7, 0, sin(a) * 0.7), wl + Vector3(0, 1.4, 0), 0.05, black)
	_beam("flat", wl + Vector3(0, 1.3, 0), wl + Vector3(0, 5.8, 0), 0.06, Color(0.85, 0.7, 0.1))
	var head_xf := Transform3D(Basis.looking_at(Vector3(0.6, 1.0, -0.6) - Vector3(-6.4, 6.0, 2.6)), Vector3(-6.4, 6.0, 2.6))
	_sbox("flat", Vector3(0.6, 0.45, 0.25), head_xf, Color(0.95, 0.75, 0.1))
	_sbox("glow", Vector3(0.5, 0.36, 0.05), head_xf * Transform3D(Basis(), Vector3(0, 0, -0.14)), Color(1.0, 0.97, 0.85))
	_beam("flat", wl + Vector3(0, 0.05, 0), Vector3(-5.2, 0.03, 4.8), 0.03, Color(1.0, 0.45, 0.06))  # extension cord

	# Trampoline (left)
	var tp := Vector3(-9.6, 0, -8.0)
	_cy("flat", 2.0, 2.0, 0.1, tp + Vector3(0, 0.88, 0), Color(0.15, 0.35, 0.8), 12)
	_cy("flat", 1.75, 1.75, 0.04, tp + Vector3(0, 0.94, 0), Color(0.04, 0.04, 0.05), 12)
	for k in 6:
		var a2 := TAU * k / 6.0
		var lp := tp + Vector3(cos(a2) * 1.9, 0, sin(a2) * 1.9)
		_beam("metal", lp, lp + Vector3(0, 0.86, 0), 0.06, Color(0.6, 0.62, 0.65))

	# Kiddie pool (right)
	var kp := Vector3(7.4, 0, -7.2)
	_cy("flat", 1.15, 1.2, 0.3, kp + Vector3(0, 0.15, 0), Color(0.3, 0.6, 0.95), 12)
	_cy("glow", 1.02, 1.02, 0.02, kp + Vector3(0, 0.25, 0), Color(0.22, 0.42, 0.55), 12)
	_bx("flat", Vector3(0.5, 0.06, 0.25), kp + Vector3(0.3, 0.27, 0.2), Color(1.0, 0.85, 0.2), 0.6)  # floatie
	# Grill by the porch, coals glowing
	var gp := Vector3(3.3, 0, -11.8)
	_cy("flat", 0.32, 0.42, 0.35, gp + Vector3(0, 0.95, 0), black, 8)
	_cy("flat", 0.42, 0.25, 0.25, gp + Vector3(0, 1.25, 0), Color(0.12, 0.12, 0.13), 8)
	_cy("glow", 0.33, 0.33, 0.02, gp + Vector3(0, 1.12, 0), Color(1.0, 0.35, 0.08), 8)
	for k in 3:
		var a3 := TAU * k / 3.0 + 0.3
		_beam("flat", gp + Vector3(cos(a3) * 0.35, 0, sin(a3) * 0.35), gp + Vector3(0, 0.85, 0), 0.04, black)
	# Beat-up couch on the porch
	var cp := Vector3(-4.6, 0.45, -13.9)
	var couch := Color(0.42, 0.38, 0.2)
	_bx("flat", Vector3(2.4, 0.45, 0.95), cp + Vector3(0, 0.22, 0), couch)
	_bx("flat", Vector3(2.4, 0.6, 0.28), cp + Vector3(0, 0.6, -0.36), couch.darkened(0.1))
	for s: float in [-1.0, 1.0]:
		_bx("flat", Vector3(0.26, 0.62, 0.95), cp + Vector3(s * 1.2, 0.31, 0), couch.darkened(0.15))
	_bx("flat", Vector3(0.7, 0.12, 0.6), cp + Vector3(-0.4, 0.5, 0.05), Color(0.55, 0.5, 0.3))  # mismatched cushion
	_bx("flat", Vector3(0.3, 0.06, 0.2), cp + Vector3(0.65, 0.48, 0.1), Color(0.6, 0.6, 0.58), 0.4)  # tape patch
	# Shed (right) with a flat-ish roof people sit on, and a ladder
	var sp := Vector3(10.6, 0, -11.0)
	var shed := Color(0.46, 0.55, 0.45)
	_bx("wood", Vector3(3.2, 2.5, 2.6), sp + Vector3(0, 1.25, 0), shed)
	_bx("shingle", Vector3(3.6, 0.15, 3.0), sp + Vector3(0, 2.58, 0), Color(0.32, 0.3, 0.3), 0.0, 0.7)
	_bx("wood", Vector3(1.2, 2.0, 0.05), sp + Vector3(-0.5, 1.0, 1.32), shed.darkened(0.25))
	_bx("flat", Vector3(0.6, 0.5, 0.05), sp + Vector3(0.9, 1.6, 1.32), Color(0.1, 0.12, 0.16))  # window
	var slb := sp + Vector3(-1.9, 0, 1.0)
	var slt := sp + Vector3(-1.65, 2.9, 0.6)
	for s: float in [-0.22, 0.22]:
		_beam("metal", slb + Vector3(0, 0, s), slt + Vector3(0, 0, s), 0.06, Color(0.7, 0.72, 0.75))
	for k in 7:
		_bx("metal", Vector3(0.05, 0.04, 0.44), slb.lerp(slt, (k + 0.7) / 7.6), Color(0.7, 0.72, 0.75))
	# Trash cans by the house corner
	for tc: Vector3 in [Vector3(7.6, 0, -14.4), Vector3(8.4, 0, -14.2)]:
		_cy("metal", 0.3, 0.33, 0.85, tc + Vector3(0, 0.425, 0), Color(0.6, 0.62, 0.62), 8)
		_cy("metal", 0.36, 0.3, 0.08, tc + Vector3(0, 0.89, 0), Color(0.65, 0.67, 0.67), 8)
	_bx("flat", Vector3(0.6, 1.0, 0.65), Vector3(6.7, 0.5, -14.4), Color(0.15, 0.3, 0.7))  # recycling bin
	# Garden gnomes
	var gnomes: Array[Vector3] = [Vector3(-12.8, 0, -3.0), Vector3(-8.0, 0, -12.6), Vector3(6.0, 0, -8.3), Vector3(12.6, 0, -6.0), Vector3(-12.4, 0, -10.5), Vector3(0.9, 0, -12.5)]
	var gnome_cols: Array[Color] = [Color(0.2, 0.35, 0.8), Color(0.2, 0.6, 0.3)]
	for i in gnomes.size():
		var g: Vector3 = gnomes[i]
		_cy("flat", 0.13, 0.09, 0.22, g + Vector3(0, 0.11, 0), gnome_cols[i % 2], 6)
		_bx("flat", Vector3(0.13, 0.12, 0.13), g + Vector3(0, 0.28, 0), Color(0.9, 0.72, 0.6))
		_bx("flat", Vector3(0.14, 0.1, 0.06), g + Vector3(0, 0.22, 0.07), Color(0.95, 0.95, 0.95))
		_cy("flat", 0.09, 0.0, 0.22, g + Vector3(0, 0.45, 0), Color(0.85, 0.12, 0.1), 6)
	# Lawn chairs
	_lawn_chair(Vector3(-6.9, 0, -1.4), Vector3(1, 0, 0.1), Color(0.2, 0.55, 0.35))
	_lawn_chair(Vector3(-7.1, 0, 0.9), Vector3(1, 0, -0.1), Color(0.85, 0.3, 0.25))
	_lawn_chair(Vector3(6.9, 0, -0.9), Vector3(-1, 0, 0.1), Color(0.25, 0.4, 0.85))
	_lawn_chair(Vector3(6.7, 0, 1.4), Vector3(-1, 0, -0.1), Color(0.9, 0.75, 0.2))
	_lawn_chair(Vector3(-2.6, 0, -7.9), Vector3(0.2, 0, 1), Color(0.2, 0.55, 0.35))
	_lawn_chair(Vector3(2.5, 0, -8.1), Vector3(-0.2, 0, 1), Color(0.85, 0.3, 0.25))
	# A cooler
	_bx("flat", Vector3(0.7, 0.42, 0.42), Vector3(-5.8, 0.21, -6.6), Color(0.85, 0.2, 0.15), 0.3)
	_bx("flat", Vector3(0.72, 0.08, 0.44), Vector3(-5.8, 0.44, -6.6), Color(0.95, 0.95, 0.95), 0.3)


func _build_car() -> void:
	# Beat-up sedan pulled onto the lawn at the front-right, headlights on the ring.
	var pos := Vector3(9.0, 0, 6.4)
	var face := Vector3(-pos.x, 0, -pos.z).normalized()
	var xf := Transform3D(Basis.looking_at(face), pos)
	var body := Color(0.45, 0.12, 0.12)
	var glass := Color(0.07, 0.09, 0.13)
	_sbox("flat", Vector3(1.8, 0.65, 4.4), xf * Transform3D(Basis(), Vector3(0, 0.62, 0)), body)
	_sbox("flat", Vector3(1.6, 0.55, 2.2), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), body.darkened(0.1))
	_sbox("flat", Vector3(1.64, 0.4, 2.0), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), glass)
	_sbox("flat", Vector3(1.4, 0.42, 2.24), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), glass)
	_sbox("flat", Vector3(1.0, 0.3, 0.9), xf * Transform3D(Basis(), Vector3(0.2, 0.95, -1.5)), Color(0.55, 0.55, 0.5))  # primer hood patch
	_sbox("flat", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.38, -2.22)), Color(0.6, 0.6, 0.62))  # bumper
	_sbox("flat", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.38, 2.22)), Color(0.6, 0.6, 0.62))
	for sx: float in [-0.65, 0.65]:
		_sbox("glow", Vector3(0.36, 0.2, 0.06), xf * Transform3D(Basis(), Vector3(sx, 0.72, -2.21)), Color(1.0, 0.97, 0.85))
		_sbox("glow", Vector3(0.3, 0.16, 0.06), xf * Transform3D(Basis(), Vector3(sx, 0.75, 2.21)), Color(0.8, 0.08, 0.06))
		for sz: float in [-1.35, 1.35]:
			_scyl("flat", 0.33, 0.33, 0.24, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.38, 0.33, sz)), Color(0.05, 0.05, 0.05), 8)
	# One spot for both headlamps (cheaper than two)
	var hp := xf * Vector3(0, 0.8, -2.3)
	var head := SpotLight3D.new()
	head.transform = Transform3D(Basis.looking_at(Vector3(0, 1.7, 0) - hp), hp)
	head.spot_angle = 26.0
	head.spot_angle_attenuation = 1.2
	head.spot_range = 20.0
	head.spot_attenuation = 0.4
	head.light_energy = 3.2
	head.light_color = Color(1.0, 0.96, 0.82)
	add_child(head)


func _hang(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)


func _build_string_lights() -> void:
	# Two zig-zag strands from the house eaves over the ring to poles at the sides.
	var poles: Array[Vector3] = [Vector3(-7.4, 0, -9.5), Vector3(7.4, 0, -9.5), Vector3(-7.4, 0, -4.0), Vector3(7.4, 0, -4.0),
		Vector3(-7.6, 0, 1.6), Vector3(7.6, 0, 1.6), Vector3(-7.6, 0, 4.4), Vector3(7.6, 0, 4.4)]
	for p in poles:
		_bx("wood", Vector3(0.12, 5.0, 0.12), p + Vector3(0, 2.5, 0), Color(0.55, 0.42, 0.3), 0.0, 2.0)
	var strand_a: Array[Vector3] = [Vector3(-7.0, 5.9, -14.9), Vector3(7.4, 4.95, -9.5), Vector3(-7.4, 4.95, -4.0), Vector3(7.6, 4.95, 1.6), Vector3(-7.6, 4.95, 4.4)]
	var strand_b: Array[Vector3] = [Vector3(7.0, 5.9, -14.9), Vector3(-7.4, 4.95, -9.5), Vector3(7.4, 4.95, -4.0), Vector3(-7.6, 4.95, 1.6), Vector3(7.6, 4.95, 4.4)]
	var cols: Array[Color] = [Color(1.0, 0.85, 0.5), Color(1.0, 0.85, 0.5), Color(1.0, 0.3, 0.2), Color(0.3, 1.0, 0.4), Color(0.35, 0.55, 1.0), Color(1.0, 0.65, 0.15)]
	var wire := Color(0.05, 0.05, 0.05)
	for strand: Array in [strand_a, strand_b]:
		for i in strand.size() - 1:
			var a: Vector3 = strand[i]
			var b: Vector3 = strand[i + 1]
			var sag := 0.55
			var segs := 8
			var prev := a
			for k in range(1, segs + 1):
				var p := _hang(a, b, sag, float(k) / segs)
				_beam("flat", prev, p, 0.025, wire)
				prev = p
			var nb := int(a.distance_to(b) / 0.75)
			for k in nb:
				var bp := _hang(a, b, sag, (k + 0.5) / nb) - Vector3(0, 0.07, 0)
				_bulb_xforms.append(Transform3D(Basis(), bp))
				_bulb_cols.append(cols[randi() % cols.size()])
	var sm := SphereMesh.new()
	sm.radius = 0.065
	sm.height = 0.13
	sm.radial_segments = 6
	sm.rings = 3
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = _bulb_xforms.size()
	for i in _bulb_xforms.size():
		mm.set_instance_transform(i, _bulb_xforms[i])
		mm.set_instance_color(i, _bulb_cols[i])
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	bm.vertex_color_is_srgb = true
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---- the friends watching

func _add_fan(p: Vector3, variant: int, lit := 0.5, bob := 1.0) -> void:
	# p = feet position. The quad's +Z (its front) faces the broadcast camera side.
	var s := randf_range(0.92, 1.06)
	var c := p + Vector3(0, 0.85 * s, 0)
	var focus := Vector3(0, c.y, 9.0)
	var away := c - focus
	away.y = 0.0
	var tr := Transform3D(Basis(), c).looking_at(c + away, Vector3.UP)
	tr.basis = tr.basis.scaled(Vector3(s, s, s))
	_fan_xforms.append(tr)
	var sitting := variant == FAN_SIT or variant == FAN_SIT_CUP
	var cheer := 0.0 if sitting or randf() < 0.4 else 1.0
	_fan_custom.append(Color(variant / 8.0, bob * (0.5 if sitting else 1.0), lit, cheer))
	if variant == FAN_PHONE or randf() < 0.25:
		crowd_spots.append(c + Vector3(0, 0.55 * s, 0))


func _stand_variant() -> int:
	var standing: Array[int] = [FAN_HOODIE, FAN_CAP, FAN_CHEER, FAN_PHONE, FAN_PHONE, FAN_CUP, FAN_CUP, FAN_HAIR]
	return standing[randi() % standing.size()]


func _build_crowd() -> void:
	# ~45 friends hanging around the yard: one MultiMesh of camera-facing pixel quads.
	_fan_xforms.clear()
	_fan_custom.clear()
	crowd_spots = PackedVector3Array()
	# Standing behind the far side of the ring (gaps left so the porch stays visible)
	var x := -7.2
	while x < 7.2:
		if absf(x) > 1.2 or randf() < 0.3:
			_add_fan(Vector3(x, 0, randf_range(-6.0, -7.4)), _stand_variant(), 0.55)
		x += randf_range(0.75, 1.1)
	# Along the side fences
	for z: float in [-2.5, -4.0, -5.6, -10.5, -12.2]:
		_add_fan(Vector3(-12.6 + randf_range(-0.3, 0.3), 0, z), _stand_variant(), 0.38)
	for z: float in [-2.0, -3.6, -5.0, -13.2]:
		_add_fan(Vector3(12.4 + randf_range(-0.3, 0.3), 0, z), _stand_variant(), 0.38)
	# Lawn chairs (sitting, slightly in front of each chair)
	for c: Vector3 in [Vector3(-6.8, 0, -1.25), Vector3(-7.0, 0, 1.05), Vector3(6.8, 0, -0.75), Vector3(6.6, 0, 1.55), Vector3(-2.55, 0, -7.75), Vector3(2.45, 0, -7.95)]:
		_add_fan(c, FAN_SIT if randf() < 0.5 else FAN_SIT_CUP, 0.55)
	# Porch: couch sitters + friends at the railing
	for cx: float in [-5.3, -4.6, -3.9]:
		_add_fan(Vector3(cx, 0.45, -13.7), FAN_SIT if randf() < 0.5 else FAN_SIT_CUP, 0.62)
	for rx: float in [-6.5, -2.0, -1.2, 0.2]:
		_add_fan(Vector3(rx, 0.45, -12.4), _stand_variant(), 0.65)
	# Up on the porch roof
	for rx: float in [-6.2, -4.6, -3.2, -1.4, 0.3]:
		var v := FAN_SIT if rx < -4.0 else _stand_variant()
		_add_fan(Vector3(rx, 3.14, -11.7), v, 0.5, 1.4)
	# On the shed roof
	for sx: float in [9.8, 10.8, 11.6]:
		_add_fan(Vector3(sx, 2.66, -10.2), FAN_SIT if sx > 11.0 else _stand_variant(), 0.45, 1.4)
	# Bouncing on the trampoline
	_add_fan(Vector3(-10.1, 0.96, -7.6), FAN_CHEER, 0.45, 3.0)
	_add_fan(Vector3(-9.0, 0.96, -8.3), FAN_PHONE, 0.45, 3.0)
	# Grill master + a friend at the pool + two by the camera-side corners
	_add_fan(Vector3(3.3, 0, -11.1), FAN_CUP, 0.6)
	_add_fan(Vector3(8.6, 0, -6.6), FAN_CUP, 0.45)
	_add_fan(Vector3(-5.6, 0, 4.4), FAN_PHONE, 0.6)
	_add_fan(Vector3(5.8, 0, 4.0), FAN_HOODIE, 0.55)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 1.7)
	var sh := Shader.new()
	sh.code = CROWD_SHADER
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = sh
	crowd_mat.set_shader_parameter("tex", _make_crowd_texture())
	crowd_mat.set_shader_parameter("hype", 0.0)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = _fan_xforms.size()
	var palette: Array[Color] = [Color(0.95, 0.2, 0.2), Color(0.2, 0.45, 1.0), Color(1.0, 0.9, 0.2), Color(0.95, 0.95, 0.95),
		Color(0.2, 0.8, 0.35), Color(0.55, 0.3, 0.85), Color(0.25, 0.25, 0.28), Color(1.0, 0.55, 0.15), Color(0.5, 0.5, 0.55),
		Color(0.35, 0.25, 0.18), Color(0.15, 0.3, 0.2)]
	for i in _fan_xforms.size():
		mm.set_instance_transform(i, _fan_xforms[i])
		mm.set_instance_color(i, palette[randi() % palette.size()])
		mm.set_instance_custom_data(i, _fan_custom[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = crowd_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	# Phone-camera flash pops: tiny additive billboards that blink at random friends.
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = _make_flash_texture()
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	fm.albedo_color = Color(1.0, 1.0, 0.95)
	var fq := QuadMesh.new()
	fq.size = Vector2(0.5, 0.5)
	flash_nodes.clear()
	flash_timers = PackedFloat32Array()
	for i in 6:
		var f := MeshInstance3D.new()
		f.mesh = fq
		f.material_override = fm
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		add_child(f)
		flash_nodes.append(f)
		flash_timers.append(randf_range(0.1, 2.5))


func _update_crowd(delta: float) -> void:
	crowd_hype = clampf(crowd_hype - delta * 0.06, 0.0, 1.0)
	crowd_hype_shown = lerpf(crowd_hype_shown, crowd_hype, clampf(delta * 3.0, 0.0, 1.0))
	if crowd_mat != null:
		crowd_mat.set_shader_parameter("hype", crowd_hype_shown)
	if crowd_spots.is_empty():
		return
	for i in flash_nodes.size():
		var f: MeshInstance3D = flash_nodes[i]
		flash_timers[i] = flash_timers[i] - delta
		if flash_timers[i] > 0.0:
			continue
		if f.visible:
			f.visible = false
			flash_timers[i] = randf_range(0.6, 4.0) / (1.0 + crowd_hype_shown * 4.0)
		else:
			f.position = crowd_spots[randi() % crowd_spots.size()] + Vector3(0, 0, 0.15)
			f.scale = Vector3.ONE * randf_range(0.7, 1.3)
			f.visible = true
			flash_timers[i] = randf_range(0.04, 0.09)


func _spawn(n: String, look: Dictionary, cpu: bool, pos: Vector3) -> Node3D:
	var w: Node3D = Wrestler.new()
	ring_root.add_child(w)
	w.setup(n, look, cpu)
	w.position = pos
	w.announce.connect(func(text): _announce(text, 1.2))
	w.impact.connect(func(s): cam_shake = max(cam_shake, s))
	w.pin_count.connect(_on_pin_count)
	w.won.connect(func(): _on_win(w))
	w.sfx.connect(func(kind: String, s: float, where: Vector3): _on_sfx(w, kind, s, where))
	w.pin_count.connect(func(c: int): _on_feel_count(w, c))
	w.won.connect(func(): _on_feel_win(w))
	return w


# ---- feel / FX
# Audio wiring, hit-stop, slow motion, camera kicks, sparks/dust/flash, rope bounce,
# haptics and crowd reactions. Driven by the wrestlers' sfx / pin_count / won signals.

func _snd(sound: String, db := 0.0, pitch_var := 0.08) -> void:
	if audio == null:
		return
	var clips: Dictionary = audio.get("clips")
	if clips.has(sound):
		audio.play(sound, db, pitch_var)


func _hitstop(secs: float) -> void:
	hitstop_until_ms = maxi(hitstop_until_ms, Time.get_ticks_msec() + int(secs * 1000.0))


func _slowmo() -> void:
	slowmo_start_ms = Time.get_ticks_msec()
	Engine.time_scale = SLOWMO_SCALE


func _update_slowmo(now: int) -> void:
	if slowmo_start_ms < 0:
		return
	var el: float = float(now - slowmo_start_ms) / 1000.0
	if el < SLOWMO_HOLD:
		Engine.time_scale = SLOWMO_SCALE
	elif el < SLOWMO_HOLD + SLOWMO_EASE:
		var k: float = smoothstep(0.0, 1.0, (el - SLOWMO_HOLD) / SLOWMO_EASE)
		Engine.time_scale = lerpf(SLOWMO_SCALE, 1.0, k)
	else:
		Engine.time_scale = 1.0
		slowmo_start_ms = -1


func _kick_cam(fov: float, shake: float) -> void:
	cam_fov_kick = minf(cam_fov_kick, fov)
	cam_shake = max(cam_shake, shake)


func _buzz(ms: int) -> void:
	if DisplayServer.is_touchscreen_available():
		Input.vibrate_handheld(ms)


func _hype(amount: float) -> void:
	crowd_hype = clampf(crowd_hype + amount, 0.0, 1.0)


func _fx_spark(where: Vector3, s: float) -> void:
	if fx != null:
		fx.spark(where, s)


func _fx_dust(where: Vector3, s: float) -> void:
	if fx != null:
		fx.dust(Vector3(where.x, RING_TOP + 0.03, where.z), s)


func _fx_flash(s: float) -> void:
	if fx != null:
		fx.flash(s)


func _fx_splinters(where: Vector3, s: float) -> void:
	if fx != null:
		fx.splinters(where, s)


func _fx_debris(where: Vector3, s: float, c: Color) -> void:
	if fx != null:
		fx.debris(where, s, c)


func _on_sfx(w: Node3D, kind: String, s: float, where: Vector3) -> void:
	var st: float = clampf(s, 0.0, 1.5)
	match kind:
		"punch":
			_snd("punch", -3.0 + 3.0 * st)
			_hitstop(0.05 + 0.02 * clampf(st, 0.0, 1.0))
			_fx_spark(where, st)
			_kick_cam(-2.0, st * 0.6)
			_buzz(20)
			_hype(0.03)
		"kick":
			_snd("kick", -1.0 + 2.0 * st)
			_hitstop(0.06 + 0.01 * clampf(st, 0.0, 1.0))
			_fx_spark(where, st)
			_kick_cam(-2.0, st * 0.6)
			_buzz(20)
			_hype(0.05)
		"thud":
			_snd("thud", -1.0 + 2.0 * st, 0.05)
			_hitstop(0.1)
			_fx_dust(where, st)
			_fx_spark(where + Vector3(0, 0.2, 0), st * 0.6)
			_kick_cam(-4.0, st)
			_buzz(45)
			_hype(0.15)
		"big_thud":
			_snd("big_thud", 2.0, 0.03)
			_snd("ooh", -6.0, 0.05)
			_hitstop(0.14)
			_fx_dust(where, maxf(st, 1.0))
			_fx_spark(where + Vector3(0, 0.2, 0), 0.9)
			_kick_cam(-4.0, maxf(st, 0.8))
			_buzz(45)
			_hype(0.15)
		"finisher":
			_snd("whoosh", 0.0, 0.03)
			_snd("cheer_small", -1.0, 0.03)
			_hitstop(0.14)
			_slowmo()
			_fx_flash(1.0)
			_fx_spark(where, 1.2)
			_kick_cam(-7.0, 0.6)
			_buzz(80)
			_hype(0.4)
		"rope":
			_snd("rope", -3.0 + 2.0 * st)
			_rope_bounce(where, st)
			_kick_cam(0.0, st * 0.3)
		"whoosh":
			_snd("whoosh", -4.0 + 3.0 * st)
		"count":
			_snd("count", 0.0, 0.03)
			_fx_dust(where, 0.15)
		"kickout":
			_snd("whoosh", -3.0)
			_fx_spark(where, 0.6)
			_kick_cam(-3.0, 0.3)
			_buzz(45)
			if feel_last_count >= 2:
				_snd("ooh", 1.0, 0.04)   # near-fall!
				_hype(0.4)
			else:
				_snd("cheer_small", -8.0)
				_hype(0.15)
			feel_last_count = 0
		"reversal":
			_snd("whoosh", -2.0)
			_snd("cheer_small", -9.0)
			_hitstop(0.06)
			_fx_spark(where, st)
			_kick_cam(-2.0, 0.3)
			_buzz(20)
			_hype(0.2)
		"taunt":
			var cpu: bool = w.is_cpu
			_snd("boo" if cpu else "cheer_small", -5.0)
			_hype(0.1)
		"grab":
			_snd("punch", -9.0, 0.15)
			_kick_cam(-1.0, 0.0)
		# ---- backyard / hardcore
		"chair_hit":
			_snd("chair", -1.0 + 2.0 * st, 0.06)
			_hitstop(0.09)
			_fx_spark(where, maxf(st, 0.7))
			_kick_cam(-3.0, maxf(st, 0.5) * 0.7)
			_buzz(45)
			_hype(0.2)
		"metal_hit":
			_snd("metal", -1.0 + 2.0 * st, 0.06)
			_hitstop(0.08)
			_fx_spark(where, maxf(st, 0.6))
			_kick_cam(-3.0, maxf(st, 0.5) * 0.7)
			_buzz(45)
			_hype(0.15)
		"wood_hit":
			_snd("wood", -1.0 + 2.0 * st, 0.08)
			_hitstop(0.07)
			_fx_splinters(where, 0.2 + 0.3 * clampf(st, 0.0, 1.0))
			_kick_cam(-2.0, st * 0.6)
			_buzz(30)
			_hype(0.12)
		"table_break":
			_snd("crack", 3.0, 0.03)
			_snd("whoa", 0.0, 0.04)
			_hitstop(0.16)
			_slowmo()
			_fx_flash(0.8)
			_fx_splinters(where, 1.5)
			_fx_splinters(where + Vector3(0, 0.15, 0), 1.0)
			if where.y >= RING_TOP - 0.2:
				_fx_dust(where, 1.2)   # dust sits on the mat; skip it for floor-level tables
			_kick_cam(-7.0, 0.8)
			_buzz(90)
			_hype(0.6)
		"dive":
			_snd("dive_whoosh", -1.0, 0.04)
			_hype(0.15)
		"climb":
			_snd("climb", -4.0, 0.1)
			_snd("whoa", -12.0, 0.06)
			_hype(0.1)
		"whoa":
			_snd("whoa", -3.0 + 2.0 * clampf(st, 0.0, 1.0), 0.05)
		"pickup_item":
			_snd("metal", -16.0, 0.12)
		_:
			# Unknown kinds (added later): play a clip of the same name if one exists.
			_snd(kind, -3.0)


func _on_feel_count(_w: Node3D, c: int) -> void:
	feel_last_count = c
	if c >= 3:
		_slowmo()
		_kick_cam(-4.0, 0.4)
		_buzz(45)
	else:
		_kick_cam(-1.0, 0.0)
		_hype(0.05 * float(c))


func _on_feel_win(_w: Node3D) -> void:
	feel_last_count = 0
	_hype(0.6)
	_snd("pop", 2.0, 0.03)
	_fx_flash(0.6)
	_buzz(80)
	_win_bells()


func _win_bells() -> void:
	# Ding-ding-ding on real time (ignore_time_scale) so slow motion doesn't drag it out.
	for i in 3:
		_snd("bell", 0.0, 0.0)
		if i < 2:
			await get_tree().create_timer(0.35, true, false, true).timeout
			if not is_inside_tree():
				return


func _rope_bounce(where: Vector3, s: float) -> void:
	if rope_nodes.size() < 12:
		return
	# Bottom-row ropes (indices 0..3) sit at the side midpoints: the nearest one is the side hit.
	var side := -1
	var best := INF
	for i in 4:
		var r: Node3D = rope_nodes[i]
		if not is_instance_valid(r):
			continue
		var rp: Vector3 = r.global_position
		var d: float = Vector2(rp.x - where.x, rp.z - where.z).length()
		if d < best:
			best = d
			side = i
	if side < 0:
		return
	for h in 3:
		var rope: Node3D = rope_nodes[h * 4 + side]
		if is_instance_valid(rope) and not rope_rest.has(rope):
			rope_rest[rope] = rope.position
	var rest0: Vector3 = rope_rest.get(rope_nodes[side], Vector3.ZERO)
	var out := Vector3(rest0.x, 0.0, rest0.z)
	rope_bounce_dir[side] = out.normalized() if out.length() > 0.01 else Vector3.ZERO
	rope_bounce_amp[side] = clampf(0.07 + 0.12 * s, 0.0, 0.15)
	rope_bounce_t[side] = 0.0


func _update_ropes(delta: float) -> void:
	if rope_nodes.size() < 12:
		return
	var height_k: Array[float] = [0.7, 1.0, 0.85]
	for side in 4:
		var t: float = rope_bounce_t[side]
		if t < 0.0:
			continue
		t += delta
		var done: bool = t >= ROPE_BOUNCE_TIME
		rope_bounce_t[side] = -1.0 if done else t
		# Damped spring: snaps outward (peak ~0.05 s), then wobbles back to rest.
		var off: float = 0.0
		if not done:
			off = rope_bounce_amp[side] * sin(t * 28.0) * exp(-t * 8.0) / 0.665
		for h in 3:
			var rope: Node3D = rope_nodes[h * 4 + side]
			if not is_instance_valid(rope) or not rope_rest.has(rope):
				continue
			var rest: Vector3 = rope_rest[rope]
			rope.position = rest + rope_bounce_dir[side] * off * height_k[h]


func _update_feel(delta: float) -> void:
	_update_ropes(delta)
	if audio != null:
		var sp1: float = p1.spirit
		var sp2: float = p2.spirit
		var ci: float = 0.2 + 0.35 * maxf(sp1, sp2) / 100.0 + 0.55 * crowd_hype
		audio.set_crowd_intensity(clampf(ci, 0.0, 1.0))


# ---------------------------------------------------------------- HUD

const HUD_GOLD := Color(1.0, 0.82, 0.18)
const HUD_HP_HIGH := Color(0.25, 0.9, 0.3)
const HUD_HP_MID := Color(1.0, 0.75, 0.1)
const HUD_HP_LOW := Color(0.95, 0.18, 0.12)
const HUD_SLANT := 12.0
const HUD_BADGE := 62.0

var hud_font: FontVariation
var hud_font_italic: FontVariation
var bar_canvas: Control
var hint_panel: PanelContainer
var hint_style: StyleBoxFlat
var hint_max_w := 760.0  # widest the hint text may get (set by _layout_hud)
const HINT_FONT := 24
const REVERSE_MIN_WINDOW := 0.25  # shorter reversal windows get no "REVERSE!" prompt
var help_button: Button
var help_panel: PanelContainer
var win_banner: Panel
var win_header: Label
var win_button: Button
var announce_tween: Tween
var count_tween: Tween
var hud_clock := 0.0


func _make_bar(w: Node3D, right: bool) -> Dictionary:
	# Per-wrestler bar state. "hp" is the displayed value, "chip" the white lag bar that
	# shows recent damage and drains after a short delay.
	var hp: float = w.health
	return {"right": right, "hp": hp, "chip": hp, "chip_delay": 0.0, "last": hp, "sp": 0.0, "flash": 0.0}


func _player_panel(w: Node3D, right: bool) -> void:
	bars[w] = _make_bar(w, right)


func _place(c: Control, anchor_x: float, anchor_y: float, rect: Rect2) -> void:
	# Anchor a control to a point of the screen, with rect offsets relative to that point.
	c.anchor_left = anchor_x
	c.anchor_right = anchor_x
	c.anchor_top = anchor_y
	c.anchor_bottom = anchor_y
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.position.x + rect.size.x
	c.offset_bottom = rect.position.y + rect.size.y


func _big_label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", hud_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _hud_box(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


func _hud_button(text: String, font_size: int, color: Color, radius: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_override("font", hud_font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 0.8))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", Color.BLACK)
	btn.add_theme_constant_override("outline_size", 6)
	var normal := _hud_box(color, Color(1, 1, 1, 0.9), radius, 4)
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 4)
	var pressed := _hud_box(color.darkened(0.3), HUD_GOLD, radius, 4)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


func _hud_safe_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if touch != null:
		l = touch.safe_left
		t = touch.safe_top
		r = touch.safe_right
		b = touch.safe_bottom
	return Rect2(l, t, vp.x - l - r, vp.y - t - b)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	hud_font = FontVariation.new()
	hud_font.base_font = ThemeDB.fallback_font
	hud_font.variation_embolden = 0.9
	hud_font_italic = FontVariation.new()
	hud_font_italic.base_font = ThemeDB.fallback_font
	hud_font_italic.variation_embolden = 1.0
	hud_font_italic.variation_transform = Transform2D(Vector2(1, 0.22), Vector2(0, 1), Vector2.ZERO)

	touch = TouchControls.new()
	hud.add_child(touch)

	# Health / spirit bars are custom-drawn on one full-screen canvas.
	_player_panel(p1, false)
	_player_panel(p2, true)
	bar_canvas = Control.new()
	bar_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_canvas.draw.connect(_draw_hud_bars)
	hud.add_child(bar_canvas)

	announce_label = _big_label(66)
	announce_label.add_theme_font_override("font", hud_font_italic)
	announce_label.add_theme_color_override("font_color", HUD_GOLD)
	announce_label.add_theme_color_override("font_outline_color", Color(0.45, 0.02, 0.05))
	announce_label.add_theme_constant_override("outline_size", 16)
	hud.add_child(announce_label)

	count_label = _big_label(200)
	count_label.add_theme_font_override("font", hud_font_italic)
	count_label.add_theme_constant_override("outline_size", 22)
	_place(count_label, 0.5, 0.5, Rect2(-260, -200, 520, 290))
	hud.add_child(count_label)

	# Context hint: dark rounded panel at the bottom center, between stick and buttons.
	hint_panel = PanelContainer.new()
	hint_style = _hud_box(Color(0.03, 0.03, 0.08, 0.8), Color(HUD_GOLD.r, HUD_GOLD.g, HUD_GOLD.b, 0.9), 16, 3)
	hint_style.content_margin_left = 22
	hint_style.content_margin_right = 22
	hint_style.content_margin_top = 8
	hint_style.content_margin_bottom = 10
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.visible = false
	hud.add_child(hint_panel)
	hint_label = _big_label(HINT_FONT)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_constant_override("outline_size", 5)
	hint_label.add_theme_constant_override("line_spacing", 2)
	hint_panel.add_child(hint_label)

	# "?" button toggles the HOW TO PLAY panel (the match keeps running).
	help_button = _hud_button("?", 34, Color(0.1, 0.1, 0.18, 0.85), 30)
	help_button.pressed.connect(_toggle_help)
	hud.add_child(help_button)
	help_panel = _build_help_panel()
	hud.add_child(help_panel)

	_build_win_panel()

	touch.connect("layout_changed", _layout_hud)
	_layout_hud()


func _build_help_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := _hud_box(Color(0.02, 0.02, 0.06, 0.92), HUD_GOLD, 20, 3)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_place(panel, 0.5, 0.5, Rect2(0, 0, 0, 0))
	panel.visible = false
	panel.gui_input.connect(_on_help_panel_input)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var title := _big_label(32)
	title.text = "HOW TO PLAY"
	title.add_theme_font_override("font", hud_font_italic)
	title.add_theme_color_override("font_color", HUD_GOLD)
	title.add_theme_constant_override("outline_size", 8)
	col.add_child(title)

	# Two columns of sections: [header, rows, first_row_is_column_header].
	# STRIKE is the red PUNCH button; STICK+ means "hold a direction while pressing".
	var left: Array = [
		["CONTROLS", [
			["STICK", "Move  (also aims whips and moves)"],
			["PUNCH", "Strike  (3 in a row knocks down)"],
			["GRAB", "Tap: lock-up   Hold: STRONG lock-up"],
			["RUN", "Hit the ropes   +STRIKE: Clothesline"],
			["PIN", "Cover a downed foe, else TAUNT"],
		], false],
		["LOCK-UP MOVES", [
			["", "TAP GRAB", "HOLD GRAB"],
			["STRIKE", "Knee Lift", "Thunder Tombstone"],
			["STICK+STRIKE", "Suplex", "Storm Powerbomb"],
			["GRAB", "Body Slam", "Spinebuster"],
			["STICK+GRAB", "DDT", "Swinging Neckbreaker"],
			["RUN", "Irish Whip", "Irish Whip"],
			["SPECIAL", "STICK+GRAB:", "THUNDER DRIVER!!"],
		], true],
		["IRISH WHIP  (as he rebounds)", [
			["STRIKE", "Clothesline"],
			["GRAB", "Back Body Drop"],
			["STICK+GRAB", "Running Powerslam"],
		], false],
	]
	var right: Array = [
		["FOE ON THE MAT", [
			["STRIKE", "Stomp"],
			["GRAB", "Pick him up (free lock-up)"],
			["RUN+STRIKE", "Flying Elbow Drop"],
			["RUN+GRAB", "Running Knee Drop  (miss = ouch)"],
		], false],
		["REVERSALS", [
			["REVERSE!", "Press GRAB or STRIKE right then"],
			["", "Counters lock-ups, whips, lariats"],
			["", "Arm Drag / Hip Toss / Back Body Drop"],
			["TOO EARLY", "Mashing just before locks you out"],
		], false],
		["PINS", [
			["PIN", "3-count wins; big moves are harder"],
			["PINNED", "MASH any button to kick out!"],
		], false],
		["SPIRIT", [
			["METER", "Fills with hits, taunts, near falls"],
			["TAUNT", "+Spirit (more if he's down), 6s wait"],
			["SPECIAL", "Full meter = 15s to hit the finisher"],
		], false],
	]
	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 36)
	col.add_child(columns)
	for side in [left, right]:
		var sections: Array = side
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_theme_constant_override("separation", 2)
		columns.add_child(vbox)
		for sec in sections:
			var header_text: String = sec[0]
			var rows: Array = sec[1]
			var has_col_header: bool = sec[2]
			var head := Label.new()
			head.text = header_text
			head.add_theme_font_override("font", hud_font_italic)
			head.add_theme_font_size_override("font_size", 22)
			head.add_theme_color_override("font_color", Color(0.45, 0.8, 1.0))
			head.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(head)
			var first: Array = rows[0]
			var grid := GridContainer.new()
			grid.columns = first.size()
			grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_theme_constant_override("h_separation", 16)
			grid.add_theme_constant_override("v_separation", -2)
			vbox.add_child(grid)
			for r in rows.size():
				var row: Array = rows[r]
				for c in row.size():
					var cell := Label.new()
					var txt: String = row[c]
					cell.text = txt
					cell.add_theme_font_override("font", hud_font)
					cell.add_theme_font_size_override("font_size", 22)
					cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
					if c == 0:
						cell.custom_minimum_size = Vector2(150, 0)
						cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
						cell.add_theme_color_override("font_color", HUD_GOLD)
					elif has_col_header and r == 0:
						cell.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
					grid.add_child(cell)
	var foot := _big_label(20)
	foot.text = "Tap here or ? to close"
	foot.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	foot.add_theme_constant_override("outline_size", 4)
	col.add_child(foot)

	# Shrink the whole panel if it would not fit the screen (small or narrow devices).
	var fit := func() -> void:
		if not panel.is_inside_tree():
			return
		var need: Vector2 = panel.get_combined_minimum_size()
		if need.x <= 0.0 or need.y <= 0.0:
			return
		var avail: Vector2 = panel.get_viewport_rect().size * 0.96
		var s: float = minf(1.0, minf(avail.x / need.x, avail.y / need.y))
		panel.pivot_offset = need * 0.5
		panel.scale = Vector2(s, s)
	panel.visibility_changed.connect(fit)
	return panel


func _build_win_panel() -> void:
	win_panel = Control.new()
	win_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.visible = false
	hud.add_child(win_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.add_child(dim)

	# Full-width slanted banner across the middle of the screen.
	win_banner = Panel.new()
	win_banner.anchor_left = 0.0
	win_banner.anchor_right = 1.0
	win_banner.anchor_top = 0.5
	win_banner.anchor_bottom = 0.5
	win_banner.offset_left = -80
	win_banner.offset_right = 80
	win_banner.offset_top = -190
	win_banner.offset_bottom = 10
	win_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _hud_box(Color(0.5, 0.05, 0.08, 0.95), HUD_GOLD, 0, 0)
	sb.border_width_top = 7
	sb.border_width_bottom = 7
	sb.skew = Vector2(0.25, 0.0)
	win_banner.add_theme_stylebox_override("panel", sb)
	win_panel.add_child(win_banner)

	win_header = _big_label(36)
	win_header.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_header.offset_top = 10
	win_header.offset_bottom = -120
	win_header.add_theme_color_override("font_color", Color.WHITE)
	win_header.add_theme_constant_override("outline_size", 8)
	win_banner.add_child(win_header)

	win_label = _big_label(84)
	win_label.add_theme_font_override("font", hud_font_italic)
	win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_label.offset_top = 50
	win_label.offset_bottom = -6
	win_label.add_theme_constant_override("outline_size", 16)
	win_banner.add_child(win_label)

	win_button = _hud_button("REMATCH", 46, Color(0.85, 0.12, 0.14), 22)
	_place(win_button, 0.5, 0.5, Rect2(-180, 50, 360, 104))
	win_button.pressed.connect(_restart)
	win_panel.add_child(win_button)


func _layout_hud() -> void:
	var sr := _hud_safe_rect()
	# Announcer sits just below the bars; hint panel at the bottom center above the
	# safe-area bottom; "?" button at the top center between the two bars.
	_place(announce_label, 0.5, 0.0, Rect2(-520, sr.position.y + 108, 1040, 120))
	# The hint is centered in the free band between the stick and the button cluster
	# and wraps (see _fit_hint) so it never sits under either.
	var band := Vector2(sr.position.x + 220.0, sr.end.x - 260.0)
	if touch != null:
		band = touch.free_band()
	hint_max_w = maxf(320.0, band.y - band.x) - hint_style.content_margin_left - hint_style.content_margin_right
	var hint_y := -(get_viewport().get_visible_rect().size.y - sr.end.y) - 14
	_place(hint_panel, 0.0, 1.0, Rect2((band.x + band.y) * 0.5, hint_y, 0, 0))
	_fit_hint()
	_place(help_button, 0.5, 0.0, Rect2(-30, sr.position.y + 12, 60, 60))
	if bar_canvas != null:
		bar_canvas.queue_redraw()


func _toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func _on_help_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			help_panel.visible = false
			help_panel.accept_event()


## Sizes the hint label to its natural width, capped at hint_max_w (then it word-wraps).
func _fit_hint() -> void:
	var w := 0.0
	for line in hint_label.text.split("\n"):
		w = maxf(w, hud_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT).x + 12.0)
	hint_label.custom_minimum_size = Vector2(minf(w, hint_max_w), 0)


func _pop(c: Control, from_scale: float, from_rot: float, secs: float) -> Tween:
	# Before the first layout pass size is still zero; fall back to the placed rect so
	# the pop pivots around the center, not the top-left corner.
	var sz := c.size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = Vector2(c.offset_right - c.offset_left, c.offset_bottom - c.offset_top).max(c.get_combined_minimum_size())
	c.pivot_offset = sz * 0.5
	c.scale = Vector2(from_scale, from_scale)
	c.rotation = from_rot
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, secs).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", from_rot * 0.25, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


func _announce(text: String, secs: float) -> void:
	if match_over and text != "":
		return
	announce_label.text = text
	announce_timer = secs
	if text == "":
		return
	var up := text.to_upper()
	var col := HUD_GOLD
	var outline := Color(0.45, 0.02, 0.05)
	if up.contains("REVERSAL") or up.contains("KICK"):
		col = Color(0.45, 0.95, 1.0)
		outline = Color(0.02, 0.1, 0.4)
	elif up.contains("!!") or up.contains("FIGHT"):
		col = Color(1.0, 0.55, 0.15)
		outline = Color(0.3, 0.0, 0.0)
	announce_label.add_theme_color_override("font_color", col)
	announce_label.add_theme_color_override("font_outline_color", outline)
	announce_label.modulate.a = 1.0
	if announce_tween != null and announce_tween.is_valid():
		announce_tween.kill()
	var tilt := -0.12 if randf() < 0.5 else 0.12
	announce_tween = _pop(announce_label, 1.6, tilt, 0.28)


func _on_pin_count(c: int) -> void:
	count_label.text = str(c) + ("!" if c >= 3 else "")
	count_label.add_theme_color_override("font_color", Color(1, 0.25, 0.15) if c >= 3 else Color.WHITE)
	count_label.add_theme_color_override("font_outline_color", Color(0.35, 0.0, 0.0) if c >= 3 else Color(0.05, 0.1, 0.45))
	count_label.modulate.a = 1.0
	count_timer = 0.7 if c < 3 else 2.5
	cam_shake = max(cam_shake, 0.25)
	# Slam in: drop from huge to slightly small, then settle.
	if count_tween != null and count_tween.is_valid():
		count_tween.kill()
	count_label.pivot_offset = count_label.size * 0.5
	count_label.scale = Vector2(3.0, 3.0)
	count_label.rotation = randf_range(-0.2, 0.2)
	count_tween = create_tween()
	count_tween.set_parallel(true)
	count_tween.tween_property(count_label, "scale", Vector2(0.88, 0.88), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	count_tween.tween_property(count_label, "rotation", 0.0, 0.12)
	count_tween.chain().tween_property(count_label, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_win(w: Node3D) -> void:
	match_over = true
	announce_label.text = ""
	var nm: String = w.display_name
	var cpu: bool = w.is_cpu
	var gear: Color = w.gear_color
	win_label.text = "%s WINS!" % nm
	win_label.add_theme_color_override("font_color", gear.lightened(0.45))
	win_header.text = "DEFEAT..." if cpu else "WINNER!"
	var sb := win_banner.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		var bg := gear.darkened(0.55)
		sb.bg_color = Color(bg.r, bg.g, bg.b, 0.95)
	help_panel.visible = false
	get_tree().create_timer(1.2).timeout.connect(_show_win)


func _show_win() -> void:
	win_panel.visible = true
	touch.visible = false
	hint_panel.visible = false
	help_button.visible = false
	win_banner.pivot_offset = win_banner.size * 0.5
	win_banner.scale = Vector2(1.0, 0.0)
	var tw := create_tween()
	tw.tween_property(win_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop(win_label, 1.8, -0.1, 0.4)
	win_button.pivot_offset = win_button.size * 0.5
	win_button.scale = Vector2.ZERO
	var tb := create_tween()
	tb.tween_interval(0.35)
	tb.tween_property(win_button, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---- console-style bars (drawn on bar_canvas)

func _para(x0: float, dir: float, u0: float, u1: float, y: float, h: float, s_top: float, s_bot: float) -> PackedVector2Array:
	# Slanted quad measured along "u" from the outer screen edge x0 (dir = +1 left side, -1 right).
	var pts := PackedVector2Array()
	pts.append(Vector2(x0 + dir * (u0 + s_top), y))
	pts.append(Vector2(x0 + dir * (u1 + s_top), y))
	pts.append(Vector2(x0 + dir * (u1 + s_bot), y + h))
	pts.append(Vector2(x0 + dir * (u0 + s_bot), y + h))
	return pts


func _fill_para(x0: float, dir: float, u0: float, u1: float, y: float, h: float, slant: float, top: Color, bottom: Color) -> void:
	if u1 - u0 < 1.0:
		return
	var pts := _para(x0, dir, u0, u1, y, h, slant, 0.0)
	bar_canvas.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _text_u(x0: float, dir: float, u: float, width: float, y: float, text: String, size: int, col: Color, font: Font, outline: int) -> void:
	# Draw text starting at distance u from the outer edge (left- or right-aligned to match).
	var pos := Vector2(x0 + u, y) if dir > 0.0 else Vector2(x0 - u - width, y)
	var align := HORIZONTAL_ALIGNMENT_LEFT if dir > 0.0 else HORIZONTAL_ALIGNMENT_RIGHT
	if outline > 0:
		bar_canvas.draw_string_outline(font, pos, text, align, width, size, outline, Color(0, 0, 0, 0.9))
	bar_canvas.draw_string(font, pos, text, align, width, size, col)


func _initials(n: String) -> String:
	var out := ""
	for part in n.split(" ", false):
		if part == "THE" or out.length() >= 2:
			continue
		out += part.substr(0, 1)
	if out.length() < 2:
		var words := n.split(" ", false)
		var last: String = words[words.size() - 1] if words.size() > 0 else n
		out = last.substr(0, 2)
	return out


func _draw_hud_bars() -> void:
	var sr := _hud_safe_rect()
	var gap := 110.0  # room for the "?" button
	var side_w: float = clampf((sr.size.x - gap) * 0.5 - 10.0, 300.0, 540.0)
	for w in [p1, p2]:
		var d: Dictionary = bars[w]
		_draw_player_bar(w, d, sr, side_w)


func _draw_player_bar(w: Node3D, d: Dictionary, sr: Rect2, side_w: float) -> void:
	var right: bool = d["right"]
	var dir := -1.0 if right else 1.0
	var x0 := (sr.end.x - 8.0) if right else (sr.position.x + 8.0)
	var top := sr.position.y + 10.0
	var gear: Color = w.gear_color
	var nm: String = w.display_name
	var cpu: bool = w.is_cpu
	var hp: float = d["hp"]
	var chip: float = d["chip"]
	var sp: float = d["sp"]
	var flash: float = d["flash"]
	var special: bool = w.is_special_ready()
	var blink := int(hud_clock * 7.0) % 2 == 0

	# Portrait badge with initials.
	var bx := x0 if not right else x0 - HUD_BADGE
	var badge := _hud_box(gear.darkened(0.25), Color.WHITE if flash < 0.5 else HUD_HP_LOW, 10, 4)
	badge.shadow_color = Color(0, 0, 0, 0.5)
	badge.shadow_size = 4
	bar_canvas.draw_style_box(badge, Rect2(bx, top, HUD_BADGE, HUD_BADGE))
	var shine := gear.lightened(0.35)
	bar_canvas.draw_rect(Rect2(bx + 6, top + 6, HUD_BADGE - 12, 10), Color(shine.r, shine.g, shine.b, 0.5))
	bar_canvas.draw_string_outline(hud_font_italic, Vector2(bx, top + 44), _initials(nm), HORIZONTAL_ALIGNMENT_CENTER, HUD_BADGE, 30, 6, Color.BLACK)
	bar_canvas.draw_string(hud_font_italic, Vector2(bx, top + 44), _initials(nm), HORIZONTAL_ALIGNMENT_CENTER, HUD_BADGE, 30, Color.WHITE)

	var u0 := HUD_BADGE + 8.0
	var u1 := side_w
	var plate_w := u1 - u0
	# Name plate.
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1 - 30.0, top, 26.0, HUD_SLANT, 0.0), Color(0, 0, 0, 0.7))
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1 - 30.0, top + 23.0, 3.0, HUD_SLANT * 0.12, 0.0), gear.lightened(0.2))
	_text_u(x0, dir, u0 + 12.0, plate_w - 110.0, top + 21.0, nm, 22, gear.lightened(0.5), hud_font_italic, 5)
	var tag := "CPU" if cpu else "1P"
	var tag_w := 50.0
	var tag_u := u1 - 30.0 - tag_w - 6.0
	var tag_x := (x0 + tag_u) if not right else (x0 - tag_u - tag_w)
	bar_canvas.draw_style_box(_hud_box(gear if not cpu else Color(0.35, 0.35, 0.4), Color.WHITE, 6, 2), Rect2(tag_x, top + 3, tag_w, 20))
	bar_canvas.draw_string(hud_font, Vector2(tag_x, top + 19), tag, HORIZONTAL_ALIGNMENT_CENTER, tag_w, 16, Color.WHITE)

	# Health bar: black frame, dark well, white damage chip, gradient fill, gloss, ticks.
	var hy := top + 30.0
	var hh := 24.0
	var blen := u1 - u0
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0 - 4.0, u1 + 4.0, hy - 4.0, hh + 8.0, HUD_SLANT + 1.0, -1.0), Color(0, 0, 0, 0.85))
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1, hy, hh, HUD_SLANT, 0.0), Color(0.16, 0.04, 0.05, 0.9))
	var chip_col := Color(1, 1, 1) if blink else Color(1, 0.85, 0.5)
	_fill_para(x0, dir, u0, u0 + blen * clampf(chip / 100.0, 0.0, 1.0), hy, hh, HUD_SLANT, chip_col, chip_col.darkened(0.2))
	var hcol := HUD_HP_HIGH
	if hp < 30.0:
		hcol = HUD_HP_LOW
		if hp < 20.0 and blink:
			hcol = hcol.lightened(0.3)
	elif hp < 60.0:
		hcol = HUD_HP_MID
	var hp_u := u0 + blen * clampf(hp / 100.0, 0.0, 1.0)
	_fill_para(x0, dir, u0, hp_u, hy, hh, HUD_SLANT, hcol.lightened(0.35), hcol.darkened(0.35))
	if hp_u - u0 > 2.0:
		var gloss := _para(x0, dir, u0, hp_u, hy + 2.0, hh * 0.3, HUD_SLANT * 0.92, HUD_SLANT * 0.62)
		bar_canvas.draw_colored_polygon(gloss, Color(1, 1, 1, 0.35))
	for k in range(1, 10):
		var tu := u0 + blen * float(k) / 10.0
		bar_canvas.draw_line(Vector2(x0 + dir * (tu + HUD_SLANT), hy), Vector2(x0 + dir * tu, hy + hh), Color(0, 0, 0, 0.3), 2.0)
	if flash > 0.0:
		bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1, hy, hh, HUD_SLANT, 0.0), Color(1, 1, 1, 0.35 * flash))

	# Spirit bar + SPECIAL! badge.
	var sy := hy + hh + 8.0
	var sh := 12.0
	var s_len := blen * 0.72
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0 - 3.0, u0 + s_len + 3.0, sy - 3.0, sh + 6.0, 7.0, -1.0), Color(0, 0, 0, 0.85))
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u0 + s_len, sy, sh, 6.0, 0.0), Color(0.1, 0.08, 0.2, 0.9))
	var scol := Color(0.3, 0.75, 1.0)
	if special:
		scol = Color(1, 1, 1) if blink else HUD_GOLD
	_fill_para(x0, dir, u0, u0 + s_len * clampf(sp / 100.0, 0.0, 1.0), sy, sh, 6.0, scol.lightened(0.3), scol.darkened(0.3))
	if special:
		var bw := 130.0
		var bu := u0 + s_len + 14.0
		var bxx := (x0 + bu) if not right else (x0 - bu - bw)
		var pulse := 1.0 + 0.08 * sin(hud_clock * 12.0)
		var rect := Rect2(bxx, sy - 9.0, bw, 30.0)
		rect = rect.grow((pulse - 1.0) * 40.0)
		var badge_sp := _hud_box(Color(0.85, 0.1, 0.1) if blink else Color(0.95, 0.5, 0.05), Color.WHITE, 8, 3)
		badge_sp.skew = Vector2(-0.2 * dir, 0.0)
		bar_canvas.draw_style_box(badge_sp, rect)
		bar_canvas.draw_string_outline(hud_font_italic, Vector2(rect.position.x, rect.position.y + 23.0), "SPECIAL!", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, 5, Color.BLACK)
		bar_canvas.draw_string(hud_font_italic, Vector2(rect.position.x, rect.position.y + 23.0), "SPECIAL!", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color(1, 1, 0.6))


func _restart() -> void:
	Engine.time_scale = 1.0
	slowmo_start_ms = -1
	hitstop_until_ms = 0
	get_tree().reload_current_scene()


## True while a reversal window the player can actually react to is open on p1
## (total length >= REVERSE_MIN_WINDOW; window + age stays equal to its full length).
func _show_reverse() -> bool:
	var rev: float = p1.reversal_window
	var age: float = p1.reversal_age
	return rev > 0.0 and rev + age >= REVERSE_MIN_WINDOW


func _hint_text() -> String:
	var st: int = p1.state
	var opp: int = p2.state
	var special: bool = p1.is_special_ready()
	var lockout: float = p1.reversal_lockout
	var a: Vector3 = p1.position
	var b: Vector3 = p2.position
	var near := Vector2(a.x - b.x, a.z - b.z).length() < 1.7
	if _show_reverse():
		return "REVERSE!  Tap GRAB or STRIKE NOW!"
	if st == Wrestler.S.TIEUP_ATK:
		var strong: bool = p1.tie_strong
		if strong:
			var fin_s := "THUNDER DRIVER!" if special else "Neckbreaker"
			return "STRONG LOCK-UP!   RUN: Irish Whip\nSTRIKE: Tombstone   STICK+STRIKE: Powerbomb\nGRAB: Spinebuster   STICK+GRAB: " + fin_s
		var fin := "THUNDER DRIVER!" if special else "DDT"
		return "LOCK-UP!   RUN: Irish Whip\nSTRIKE: Knee   STICK+STRIKE: Suplex\nGRAB: Slam   STICK+GRAB: " + fin
	if st == Wrestler.S.TIEUP_DEF:
		if lockout > 0.0:
			return "TOO EARLY!  Wait for the move..."
		return "CAUGHT!  Tap GRAB or STRIKE when the \"!\" appears to reverse"
	if st == Wrestler.S.PINNED:
		return "MASH ANY BUTTON TO KICK OUT!"
	if st == Wrestler.S.GRAB_WINDUP:
		return "Keep holding GRAB for a STRONG lock-up..."
	if st == Wrestler.S.WHIPPING:
		return "Here he comes!  STRIKE: Clothesline\nGRAB: Back Body Drop   STICK+GRAB: Powerslam"
	if st == Wrestler.S.RUN:
		if opp == Wrestler.S.DOWN:
			return "STRIKE: Elbow Drop      GRAB: Knee Drop"
		return "STRIKE: Clothesline      RUN: Stop"
	if opp == Wrestler.S.DOWN:
		if near:
			return "STRIKE: Stomp   GRAB: Pick up   PIN: Cover"
		return "He's down!  Get close and PIN, or TAUNT from afar"
	if special:
		var secs: float = p1.special_timer
		return "SPECIAL READY! (%ds)  Lock up, then STICK + GRAB" % int(ceil(secs))
	if hud_clock < 6.0:
		return "Tap GRAB to lock up  -  HOLD GRAB for a strong lock-up"
	return ""


func _update_touch_labels() -> void:
	# Context-sensitive captions on the touch buttons.
	if touch == null:
		return
	var st: int = p1.state
	var opp: int = p2.state
	var special: bool = p1.is_special_ready()
	var mv: Vector2 = p1.in_move
	var dir_held := mv.length() > 0.5
	var a: Vector3 = p1.position
	var b: Vector3 = p2.position
	var near := Vector2(a.x - b.x, a.z - b.z).length() < 1.7
	var glow := "grapple" if special else ""
	if match_over:
		touch.set_labels("", "", "", "")
		glow = ""
	elif _show_reverse():
		touch.set_labels("REVERSE!", "REVERSE!", "", "")
		glow = "all"
	elif st == Wrestler.S.PINNED:
		touch.set_labels("MASH!", "MASH!", "MASH!", "MASH!")
		glow = "all"
	elif st == Wrestler.S.TIEUP_ATK:
		var strong: bool = p1.tie_strong
		var grab_move: String
		var strike_move: String
		if strong:
			grab_move = ("FINISH!" if special else "NECKBRKR") if dir_held else "SPINEBSTR"
			strike_move = "P.BOMB" if dir_held else "TOMBSTONE"
		else:
			grab_move = ("FINISH!" if special else "DDT") if dir_held else "SLAM"
			strike_move = "SUPLEX" if dir_held else "KNEE"
		touch.set_labels(strike_move, grab_move, "WHIP", "")
		if not (special and dir_held):
			glow = ""
	elif st == Wrestler.S.TIEUP_DEF:
		touch.set_labels("WAIT...", "WAIT...", "", "")
		glow = ""
	elif st == Wrestler.S.GRAB_WINDUP:
		touch.set_labels("", "HOLD!", "", "")
		glow = "grapple"
	elif st == Wrestler.S.WHIPPING:
		touch.set_labels("LARIAT", "P.SLAM" if dir_held else "BACKDROP", "", "")
		glow = ""
	elif st == Wrestler.S.RUN:
		if opp == Wrestler.S.DOWN:
			touch.set_labels("ELBOW", "KNEE", "STOP", "")
		else:
			touch.set_labels("LARIAT", "STOP", "STOP", "")
	elif opp == Wrestler.S.DOWN and near:
		touch.set_labels("STOMP", "LIFT", "RUN", "PIN")
		if not special:
			glow = "pin"
	else:
		var cd: float = p1.taunt_cooldown
		var pin_lbl := "PIN" if opp == Wrestler.S.DOWN else ("TAUNT" if cd <= 0.0 else "")
		touch.set_labels("PUNCH", "GRAB", "RUN", pin_lbl)
		if opp == Wrestler.S.DOWN and not special:
			glow = "pin"
	touch.set_highlight(glow)


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	_update_slowmo(now)
	var frozen: bool = now < hitstop_until_ms
	if not match_over:
		var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if touch.joy_vector.length() > mv.length():
			mv = touch.joy_vector
		p1.in_move = mv
		var js: bool = Input.is_action_just_pressed("strike")
		var jg: bool = Input.is_action_just_pressed("grapple")
		var jr: bool = Input.is_action_just_pressed("run")
		var jp: bool = Input.is_action_just_pressed("pin")
		if frozen:
			# Hit-stop: hold presses and hand them over on the first unfrozen tick.
			buf_strike = buf_strike or js
			buf_grapple = buf_grapple or jg
			buf_run = buf_run or jr
			buf_pin = buf_pin or jp
		else:
			p1.in_strike = js or buf_strike
			p1.in_grapple = jg or buf_grapple
			p1.in_grapple_held = Input.is_action_pressed("grapple")
			p1.in_run = jr or buf_run
			p1.in_pin = jp or buf_pin
			p1.any_pressed = p1.in_strike or p1.in_grapple or p1.in_run or p1.in_pin
			buf_strike = false
			buf_grapple = false
			buf_run = false
			buf_pin = false
	else:
		p1.in_move = Vector2.ZERO
		if Input.is_action_just_pressed("restart"):
			_restart()
			return
	if not frozen:
		p1.tick(delta)
		p2.tick(delta)

	_update_feel(delta)
	_update_camera(delta)
	_update_hud(delta)


func _update_camera(delta: float) -> void:
	_update_crowd(delta)
	var a: Vector3 = p1.global_position
	var b: Vector3 = p2.global_position
	var mid := (a + b) * 0.5
	var spread := a.distance_to(b)
	cam_target = cam_target.lerp(mid, clampf(delta * 4.0, 0.0, 1.0))
	# Tight broadcast framing: a wrestler fills ~40% of screen height. The look target is
	# biased upward so the bottom-corner touch buttons sit over the mat, not the wrestlers.
	var want := cam_target + Vector3(0, 2.4 + spread * 0.25, 5.2 + spread * 0.55)
	camera.position = camera.position.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
	camera.look_at(cam_target + Vector3(0, 1.2 + 0.4, 0))
	cam_fov_kick = lerpf(cam_fov_kick, 0.0, clampf(delta * 5.0, 0.0, 1.0))
	if absf(cam_fov_kick) < 0.01:
		cam_fov_kick = 0.0
	camera.fov = clampf(40.0 + cam_fov_kick, 15.0, 90.0)
	if cam_shake > 0.0:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * cam_shake * 0.25
		cam_shake = max(0.0, cam_shake - delta * 2.5)


func _update_hud(delta: float) -> void:
	hud_clock += delta
	for w in [p1, p2]:
		var d: Dictionary = bars[w]
		var hp_now: float = w.health
		var last: float = d["last"]
		if hp_now < last - 0.01:
			d["chip_delay"] = 0.6
			d["flash"] = 1.0
		d["last"] = hp_now
		var shown: float = d["hp"]
		shown = lerpf(shown, hp_now, clampf(delta * 12.0, 0.0, 1.0))
		d["hp"] = shown
		var chip: float = d["chip"]
		var chip_delay: float = d["chip_delay"]
		if chip <= shown:
			chip = shown
		elif chip_delay > 0.0:
			chip_delay -= delta
		else:
			chip = maxf(shown, chip - delta * 40.0)
		d["chip"] = chip
		d["chip_delay"] = chip_delay
		var sp_now: float = w.spirit
		var sp_shown: float = d["sp"]
		d["sp"] = lerpf(sp_shown, sp_now, clampf(delta * 10.0, 0.0, 1.0))
		var flash: float = d["flash"]
		d["flash"] = maxf(0.0, flash - delta * 4.0)
	bar_canvas.queue_redraw()

	if announce_timer > 0.0:
		announce_timer -= delta
		announce_label.modulate.a = clamp(announce_timer * 3.0, 0.0, 1.0)
	if count_timer > 0.0:
		count_timer -= delta
		count_label.modulate.a = clamp(count_timer * 3.0, 0.0, 1.0)
	else:
		count_label.text = ""

	var hint := "" if match_over else _hint_text()
	if hint != hint_label.text:
		hint_label.text = hint
		_fit_hint()
		hint_panel.visible = hint != ""
		# The panel re-sizes around the text by itself (zero offsets + grow); give it a pop.
		if hint != "":
			hint_panel.pivot_offset = Vector2(hint_panel.size.x * 0.5, hint_panel.size.y)
			hint_panel.scale = Vector2(1.12, 1.12)
			create_tween().tween_property(hint_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hint_panel.visible:
		var st: int = p1.state
		var bc := HUD_GOLD
		if st == Wrestler.S.PINNED or st == Wrestler.S.TIEUP_DEF:
			bc = HUD_HP_LOW if int(hud_clock * 8.0) % 2 == 0 else Color.WHITE
		hint_style.border_color = bc
	_update_touch_labels()

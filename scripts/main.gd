extends Node3D
## Builds the arena, spawns both wrestlers, runs the camera, HUD and match flow.
## Everything is generated in code so the project has no imported assets.

const Wrestler := preload("res://scripts/wrestler.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const RING_TOP := 0.0  # no ring any more: the yard ground is y 0 (yard_contract.md)

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
const StyleSys := preload("res://scripts/style.gd")
const StyleHud := preload("res://scripts/style_hud.gd")
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
	_build_low_res_view()
	_build_arena()
	_build_crowd()

	ring_root = Node3D.new()
	ring_root.position.y = 0.0   # ground level: they fight on the grass and the patio
	add_child(ring_root)
	# Each look: street clothes + style switches used by wrestler.gd's model.
	# "gear" is the wrestler's signature colour (HUD, win banner).
	var tank := {
		"gear": Color(0.8, 0.14, 0.1), "skin": Color(0.36, 0.22, 0.14),
		"hair": "dreads", "hair_color": Color(0.09, 0.06, 0.045), "stubble": true, "facial": "goatee",
		"top": "flannel", "top_color": Color(0.72, 0.12, 0.1), "top_pattern": "plaid",
		"top_accent": Color(0.08, 0.06, 0.06),
		"bottom": "cargo_shorts", "bottom_color": Color(0.6, 0.53, 0.38),
		"shoes": "hightops", "shoe_color": Color(0.1, 0.1, 0.12), "shoe_accent": Color(0.85, 0.15, 0.12),
		"sock_l": Color(0.95, 0.95, 0.92), "sock_accent": Color(0.8, 0.14, 0.1),
		"hat": "none", "wristband_color": Color(0.95, 0.95, 0.92),
		"knee_brace": "left", "bulk": 1.15, "gut": 0.035,
	}
	var kid := {
		"gear": Color(0.15, 0.75, 0.3), "skin": Color(0.66, 0.46, 0.32),
		"mask": true, "mask_color": Color(0.12, 0.7, 0.28), "mask_trim": Color(1.0, 0.82, 0.1),
		"hair": "messy", "hair_color": Color(0.09, 0.07, 0.06),
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

	# Hardcore weapons (scripts/weapons.gd). Respawned fresh on every scene (re)load.
	var item_mgr: Node3D = load("res://scripts/weapons.gd").new()
	ring_root.add_child(item_mgr)
	p1.items = item_mgr
	p2.items = item_mgr
	item_mgr.broke.connect(func(kind: String, where: Vector3):
		if kind == "table":
			pass  # table splinters come from the "table_break" sfx in _on_sfx
		elif kind == "plank":
			if fx.has_method("splinters"):
				fx.call("splinters", where, 0.5)
		elif fx.has_method("debris"):
			fx.call("debris", where, 0.7, Color(0.6, 0.62, 0.65)))

	_build_hud()
	# STYLE system: per-wrestler combo / hype / B-R-A-W-L logic + its own HUD overlay (layer 2).
	for w in [p1, p2]:
		w.add_child(StyleSys.new())
	var style_hud: CanvasLayer = StyleHud.new()
	add_child(style_hud)
	style_hud.setup(self, [p1, p2])
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
var cam_fov_kick := 0.0          # degrees added to the 45 deg broadcast FOV; decays back to 0
var crowd_hype := 0.0            # 0..1, crowd excitement; drifts back down slowly on its own
var rope_nodes: Array[Node3D] = []  # 12 ropes: for each height (bottom, middle, top): +z, -z, +x, -x
var ring_spot: SpotLight3D       # the front floodlight: key light over the yard
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

uniform sampler2D tex : source_color, filter_linear_mipmap;
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
	c *= mix(1.08, 0.72, UV.y);  // soft top-lit gradient down each friend
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, 0.8);  // ~20% desaturated
	ALBEDO = mix(c, vec3(0.6, 0.72, 0.8), scr);
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


func _tex_mat(tex: Texture2D, scissor := false, blend := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.9
	if scissor:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	elif blend:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# ---- merged-geometry helpers (all scenery goes through these)

func _st(key: String) -> SurfaceTool:
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = st
	return _batches[key]


func _tri(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, a: Vector3, b: Vector3, col: Color, uvs: float) -> void:
	# Godot front faces wind clockwise; callers pass corners in that order.
	# All scenery is pulled ~15% toward grey (AKI palette: slightly desaturated surroundings).
	var lum := col.r * 0.299 + col.g * 0.587 + col.b * 0.114
	var dc := Color(lum, lum, lum, col.a).lerp(col, 0.85)
	for p: Vector3 in [p0, p1, p2]:
		st.set_color(dc)
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
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	match key:
		"glow":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"wood":
			m.albedo_texture = _make_wood_texture()
		"siding":
			m.albedo_texture = _make_siding_texture()
		"shingle":
			m.albedo_texture = _make_shingle_texture()
		"brick":
			m.albedo_texture = _make_brick_texture()
		"block":
			m.albedo_texture = _make_concrete_texture(128, false, 0)
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


# ---- generated textures (tiny, soft, painted: AKI-era N64 look)
# Every texture is painted at 2x with gradients and grain, bilinear-downsampled, and mipmapped.

func _soft_tex(img: Image, w: int, h: int) -> ImageTexture:
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _noise_img(w: int, h: int, freq: float, octaves := 3, seamless := true) -> Image:
	# Greyscale fractal noise (r = 0..1), tileable unless seamless is false.
	var fn := FastNoiseLite.new()
	fn.seed = randi()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = octaves
	if seamless:
		return fn.get_seamless_image(w, h)
	return fn.get_image(w, h)


func _blend_px(img: Image, x: int, y: int, col: Color, k: float) -> void:
	# Paint col over the pixel with coverage k (proper "over" compositing, so transparent canvases work).
	if k <= 0.0 or x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var o := img.get_pixel(x, y)
	var a := k + o.a * (1.0 - k)
	if a <= 0.0001:
		return
	var wo := o.a * (1.0 - k)
	img.set_pixel(x, y, Color((col.r * k + o.r * wo) / a, (col.g * k + o.g * wo) / a, (col.b * k + o.b * wo) / a, a))


func _soft_rect(img: Image, x0: float, y0: float, w: float, h: float, col: Color, a := 1.0, feather := 1.0) -> void:
	for y in range(int(floorf(y0 - feather)), int(ceilf(y0 + h + feather))):
		for x in range(int(floorf(x0 - feather)), int(ceilf(x0 + w + feather))):
			var dx := minf(x + 0.5 - x0, x0 + w - (x + 0.5))
			var dy := minf(y + 0.5 - y0, y0 + h - (y + 0.5))
			_blend_px(img, x, y, col, clampf(minf(dx, dy) / feather + 0.5, 0.0, 1.0) * a)


func _soft_dot(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color, a := 1.0, feather := 1.0) -> void:
	# Filled ellipse with a soft rim (feather in pixels).
	for y in range(int(floorf(cy - ry - feather)), int(ceilf(cy + ry + feather))):
		for x in range(int(floorf(cx - rx - feather)), int(ceilf(cx + rx + feather))):
			var d := Vector2((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry).length()
			var edge := (1.0 - d) * minf(rx, ry)
			_blend_px(img, x, y, col, clampf(edge / feather + 0.5, 0.0, 1.0) * a)


func _sharp_tex(img: Image) -> ImageTexture:
	# Full-res (PS2-era detail), still mipmapped and bilinear filtered.
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _line_px(img: Image, a: Vector2, b: Vector2, col: Color, k: float) -> void:
	# Anti-aliased-ish 1 px stroke (cracks, seams): stamps the coverage along the segment.
	var steps := maxi(1, int(a.distance_to(b) * 1.5))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var fx := p.x - floorf(p.x)
		var fy := p.y - floorf(p.y)
		var x0 := int(floorf(p.x))
		var y0 := int(floorf(p.y))
		_blend_px(img, x0, y0, col, k * (1.0 - fx) * (1.0 - fy) * 0.9)
		_blend_px(img, x0 + 1, y0, col, k * fx * (1.0 - fy) * 0.9)
		_blend_px(img, x0, y0 + 1, col, k * (1.0 - fx) * fy * 0.9)
		_blend_px(img, x0 + 1, y0 + 1, col, k * fx * fy * 0.9)


func _crack(img: Image, start: Vector2, ang: float, segs: int, seg_len: float, dark: Color) -> void:
	# Wandering hairline crack with a faint lit lip, sometimes forking.
	var p := start
	for i in segs:
		ang += randf_range(-0.55, 0.55)
		var q := p + Vector2(cos(ang), sin(ang)) * seg_len * randf_range(0.6, 1.3)
		_line_px(img, p + Vector2(0.8, 0.8), q + Vector2(0.8, 0.8), Color(0.75, 0.74, 0.7), 0.12)
		_line_px(img, p, q, dark, 0.75 - 0.4 * float(i) / segs)
		if randf() < 0.12 and segs > 6:
			_crack(img, q, ang + randf_range(-1.2, 1.2), segs / 3, seg_len * 0.8, dark)
		p = q


func _make_grass_detail() -> ImageTexture:
	# 128 px tileable grey grass detail (averages ~0.5): clumps, blade tips, dark gaps. The lawn
	# shader multiplies it (x2) over the painted lawn map; it is also the far ground's texture.
	var n := 128
	var clump := _noise_img(n, n, 0.06, 3)
	var fine := _noise_img(n, n, 0.35, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := clump.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var g := 0.5 + (c - 0.5) * 0.32 + (f - 0.5) * 0.4
			img.set_pixel(x, y, Color(g * 0.98, g, g * 0.94))
	# Blades: short slanted strokes, lit tips and shadowed roots (wrapped, so it still tiles).
	for i in 900:
		var bx := randf() * n
		var by := randf() * n
		var ln := randf_range(2.0, 5.0)
		var lean := randf_range(-0.6, 0.6)
		var lit := randf() < 0.55
		var col := Color(0.72, 0.76, 0.58) if lit else Color(0.24, 0.26, 0.22)
		for s in int(ln * 2.0):
			var t := s / (ln * 2.0)
			var px := int(fposmod(bx + lean * t * ln, n))
			var py := int(fposmod(by - t * ln, n))
			_blend_px(img, px, py, col, 0.35 * (0.4 + t * 0.6) if lit else 0.35 * (1.0 - t * 0.6))
	return _sharp_tex(img)


func _make_grass_texture() -> ImageTexture:
	return _make_grass_detail()


const LAWN_RECT := Rect2(-7.6, -8.6, 15.2, 15.2)  # painted lawn quad: x -7.6..7.6, z -8.6..6.6


func _lawn_px(x: float, z: float, n: int) -> Vector2:
	return Vector2((x - LAWN_RECT.position.x) / LAWN_RECT.size.x * n, (z - LAWN_RECT.position.y) / LAWN_RECT.size.y * n)


func _lawn_dot(img: Image, x: float, z: float, rx: float, rz: float, col: Color, a: float) -> void:
	# A soft blotch in yard metres on the lawn map.
	var n := img.get_width()
	var p := _lawn_px(x, z, n)
	var s := n / LAWN_RECT.size.x
	_soft_dot(img, p.x, p.y, rx * s, rz * s, col, a, maxf(rx, rz) * s * 0.7)


func _make_lawn_map() -> ImageTexture:
	# The whole yard's grass in one painted map (painted 256, used at 128 under the detail tile):
	# mowing stripes, dry patches, a trampled dirt arena where they always fight, bald spots at the
	# foot of every perch, tyre ruts to the driveway and a dead ring under the trampoline.
	var n := 256
	var big := _noise_img(n, n, 0.018, 3, false)
	var mid := _noise_img(n, n, 0.07, 2, false)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var dark := Color(0.1, 0.2, 0.055)
	var lush := Color(0.2, 0.34, 0.085)
	var dry := Color(0.33, 0.31, 0.13)
	var dirt := Color(0.3, 0.21, 0.13)
	var ppm := n / LAWN_RECT.size.x
	var wc := _lawn_px(0.0, -0.3, n)
	for y in n:
		var wz := LAWN_RECT.position.y + (y + 0.5) / ppm
		for x in n:
			var wx := LAWN_RECT.position.x + (x + 0.5) / ppm
			var b := big.get_pixel(x, y).r
			var m := mid.get_pixel(x, y).r
			var band := sin((wx + sin(wz * 0.6) * 0.12) / 1.2 * PI)
			var stripe := smoothstep(-0.3, 0.3, band)
			var c := dark.lerp(lush, clampf(0.3 + stripe * 0.45 + (m - 0.5) * 0.4, 0.0, 1.0))
			c = c.lerp(dry, smoothstep(0.6, 0.9, b) * 0.5)
			var d := Vector2((x - wc.x) / (ppm * 4.6), (y - wc.y) / (ppm * 3.2)).length()
			var wear := (1.0 - smoothstep(0.25, 1.05, d)) * (0.6 + (m - 0.5) * 0.9)
			c = c.lerp(dry.lerp(dirt, 0.4), clampf(wear * 0.7, 0.0, 0.8))
			c = c.lerp(dirt, smoothstep(0.5, 0.8, wear + (b - 0.5) * 0.5) * 0.85)
			# Fence-line shade and longer, darker grass along the edges.
			var edge := minf(minf(wx + 7.5, 7.5 - wx), wz + 8.6)
			c = c.darkened((1.0 - smoothstep(0.0, 0.9, edge)) * 0.35)
			img.set_pixel(x, y, c)
	# Dead circle under the trampoline, bald spots in front of the perches, random patches.
	_lawn_dot(img, 5.0, -2.6, 1.5, 1.5, dry, 0.5)
	_lawn_dot(img, 5.0, -2.6, 1.0, 1.0, dirt, 0.25)
	for p: Vector2 in [Vector2(-4.4, -2.3), Vector2(1.6, -4.4), Vector2(3.5, -2.0), Vector2(4.2, 2.6),
			Vector2(-5.7, 0.4), Vector2(-4.9, 3.4)]:
		_lawn_dot(img, p.x, p.y, randf_range(0.6, 0.9), randf_range(0.45, 0.7), dirt, 0.7)
		_lawn_dot(img, p.x + randf_range(-0.3, 0.3), p.y + randf_range(-0.3, 0.3), 0.3, 0.25, dirt.darkened(0.25), 0.5)
	for i in 10:
		_lawn_dot(img, randf_range(-6.5, 6.5), randf_range(-4.5, 5.5), randf_range(0.2, 0.55), randf_range(0.2, 0.45), dirt if randf() < 0.5 else dry, 0.55)
	# Tyre ruts across the lawn into the driveway.
	for rz: float in [1.9, 3.4]:
		var x := 7.5
		while x > 1.0:
			_lawn_dot(img, x, rz + sin(x * 0.7) * 0.15, 0.4, 0.14, dirt.darkened(0.15), 0.35 * smoothstep(1.0, 4.0, x))
			x -= 0.25
	return _soft_tex(img, 128, 128)


func _make_concrete_texture(n: int, joints: bool, stains: int) -> ImageTexture:
	# Grungy poured concrete: mottled grey with aggregate specks, tooled expansion joints,
	# hairline cracks, oil stains, rust drips and dirt creeping in from the edges.
	var mot := _noise_img(n, n, 0.035, 3, false)
	var grit := _noise_img(n, n, 0.6, 1, false)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var base := Color(0.5, 0.49, 0.46)
	for y in n:
		for x in n:
			var m := mot.get_pixel(x, y).r
			var g := grit.get_pixel(x, y).r
			var c := base.darkened((m - 0.5) * 0.4 + (g - 0.5) * 0.18)
			if randf() < 0.03:
				c = c.lightened(0.15) if randf() < 0.5 else c.darkened(0.2)
			var e := float(mini(mini(x, y), mini(n - 1 - x, n - 1 - y))) / n
			c = c.lerp(Color(0.24, 0.22, 0.17), (1.0 - smoothstep(0.0, 0.06, e)) * 0.6)
			img.set_pixel(x, y, c)
	var dark := Color(0.1, 0.1, 0.1)
	if joints:
		var step := n / 4
		for k in range(step, n, step):
			for t in n:
				_blend_px(img, k, t, dark, 0.6)
				_blend_px(img, k + 1, t, Color(0.78, 0.77, 0.72), 0.15)
				_blend_px(img, t, k, dark, 0.6)
				_blend_px(img, t, k + 1, Color(0.78, 0.77, 0.72), 0.15)
	for i in maxi(3, n / 40):
		_crack(img, Vector2(randf() * n, randf() * n), randf() * TAU, randi_range(8, 22), n / 40.0, dark)
	for i in stains:
		var c := Vector2(randf_range(0.1, 0.9) * n, randf_range(0.1, 0.9) * n)
		var r := randf_range(0.035, 0.09) * n
		for k in 5:
			_soft_dot(img, c.x + randf_range(-r, r) * 0.5, c.y + randf_range(-r, r) * 0.5, r * randf_range(0.5, 1.0), r * randf_range(0.4, 0.9),
				Color(0.06, 0.06, 0.07), randf_range(0.18, 0.32), r * 0.5)
		_soft_dot(img, c.x, c.y, r * 0.35, r * 0.3, Color(0.03, 0.03, 0.04), 0.4, r * 0.25)
	for i in 3:
		var c := Vector2(randf() * n, randf() * n)
		_soft_dot(img, c.x, c.y, n * 0.02, n * 0.05, Color(0.4, 0.22, 0.1), 0.2, n * 0.02)  # rust
	return _sharp_tex(img)


func _make_spray_texture() -> ImageTexture:
	# Spray-painted "C2C" on the patio: hard core, fuzzy overspray halo, spatter, worn by feet.
	var w := 256
	var h := 128
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var paint := Color(0.86, 0.14, 0.1)
	var sc := 19.0
	var x0 := (w - _text_w("C2C", sc)) * 0.5
	var y0 := 14.0
	var x := x0
	for ch in "C2C":
		var rows: Array = PIXEL_FONT[ch]
		for ry in 5:
			var row: String = rows[ry]
			for rx in 3:
				if row[rx] == "1":
					var cx := x + (rx + 0.5) * sc
					var cy := y0 + (ry + 0.5) * sc
					_soft_dot(img, cx, cy, sc * 0.95, sc * 0.95, paint, 0.16, sc * 0.6)
		x += 4.0 * sc
	_soft_text(img, "C2C", x0, y0, sc, paint, 0.95)
	_soft_rect(img, x0 - 4.0, y0 + 5.0 * sc + 8.0, _text_w("C2C", sc) + 8.0, 5.0, paint, 0.8, 2.0)  # underline swoosh
	for i in 140:
		var a := randf() * TAU
		var r := randf_range(0.3, 1.0) * 120.0
		_soft_dot(img, w * 0.5 + cos(a) * r, h * 0.5 + sin(a) * r * 0.5, 1.0, 1.0, paint, randf_range(0.3, 0.8), 0.8)
	var nz := _noise_img(w, h, 0.06, 3, false)
	for yy in h:
		for xx in w:
			var c := img.get_pixel(xx, yy)
			if c.a > 0.0:
				c.a *= clampf(0.5 + nz.get_pixel(xx, yy).r * 0.75, 0.0, 0.92)
				img.set_pixel(xx, yy, c)
	return _sharp_tex(img)


func _make_wood_texture() -> ImageTexture:
	# Weathered fence wood, 128 px per metre (tinted per vertex): vertical grain, grey sun-bleaching,
	# dark water streaks, knots and nail heads.
	var n := 128
	var nz := _noise_img(n, n, 0.05, 2)
	var streak := _noise_img(n, n, 0.12, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var w := nz.get_pixel(x, y).r
			var s := streak.get_pixel(x, (y / 8) % n).r
			var g := 0.78 + 0.07 * sin(x * TAU * 11.0 / n + sin(y * TAU / n) * 2.0 + w * 6.0) + (w - 0.5) * 0.12
			g -= smoothstep(0.55, 0.85, s) * 0.16
			img.set_pixel(x, y, Color(g, g * 0.96, g * 0.9))
	for i in 3:
		var k := Vector2(randf() * n, randf() * n)
		_soft_dot(img, k.x, k.y, 3.0, 4.5, Color(0.32, 0.26, 0.2), 0.7, 1.5)
		_soft_dot(img, k.x, k.y, 1.2, 1.8, Color(0.15, 0.12, 0.1), 0.8, 0.8)
	for i in 6:
		_soft_dot(img, randf() * n, randf() * n, 1.1, 1.1, Color(0.2, 0.18, 0.17), 0.8, 0.6)
	return _sharp_tex(img)


func _make_siding_texture() -> ImageTexture:
	# Vinyl lap siding, 128 px: board shading from overlap shadow to lit lip, mildew streaks, grime.
	var n := 128
	var streak := _noise_img(n, n, 0.05, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var r := float(y % 16) / 15.0
		for x in n:
			var g := 0.66 + 0.26 * sqrt(r)
			if y % 16 == 15:
				g *= 0.55
			var s := streak.get_pixel(x, (y / 6) % n).r
			g *= 0.86 + 0.14 * s
			img.set_pixel(x, y, Color(g, g, g * 0.97))
	return _sharp_tex(img)


func _make_brick_texture() -> ImageTexture:
	# Red brick, running bond: 16 courses of 8 px with mortar lines and per-brick tone (128 px / metre).
	var n := 128
	var grit := _noise_img(n, n, 0.4, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var tones: Array[Color] = [Color(0.55, 0.24, 0.16), Color(0.48, 0.2, 0.14), Color(0.6, 0.3, 0.2), Color(0.42, 0.19, 0.15)]
	for y in n:
		var row := y / 8
		for x in n:
			var sx := (x + (row % 2) * 10) % n
			var col := sx / 21
			var c: Color = tones[(row * 7 + col * 3) % tones.size()]
			var gv := grit.get_pixel(x, y).r
			c = c.darkened((gv - 0.5) * 0.35)
			if y % 8 == 7 or sx % 21 == 20:
				c = Color(0.42, 0.4, 0.36).darkened((gv - 0.5) * 0.3)
			img.set_pixel(x, y, c)
	return _sharp_tex(img)


func _make_shingle_texture() -> ImageTexture:
	var n := 128
	var grain := _noise_img(n, n, 0.3, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		var row := y / 16
		for x in n:
			var sx := (x + (row % 2) * 16) % n
			var tab := sx / 32
			var g := 0.7 + 0.16 * fposmod(sin(float(tab * 7 + row * 13)) * 43.7, 1.0)
			var ry := float(y % 16) / 15.0
			g *= 1.0 - 0.3 * smoothstep(0.65, 1.0, ry)
			var ex := absf(float(sx % 32) - 15.5) / 15.5
			g *= 1.0 - 0.2 * smoothstep(0.85, 1.0, ex)
			g += (grain.get_pixel(x, y).r - 0.5) * 0.14
			img.set_pixel(x, y, Color(g, g, g))
	return _sharp_tex(img)


const PIXEL_FONT := {
	"C": ["011", "100", "100", "100", "011"], "E": ["111", "100", "110", "100", "111"],
	"G": ["011", "100", "101", "101", "011"], "I": ["111", "010", "010", "010", "111"],
	"L": ["100", "100", "100", "100", "111"], "N": ["101", "111", "111", "101", "101"],
	"R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
	"T": ["111", "010", "010", "010", "010"], "W": ["101", "101", "101", "111", "101"],
	"Y": ["101", "101", "010", "010", "010"], "2": ["110", "001", "010", "100", "111"],
}


func _soft_text(img: Image, text: String, x0: float, y0: float, sc: float, col: Color, a := 1.0) -> void:
	# Glyph cells painted as overlapping feathered blobs, so strokes come out rounded and anti-aliased.
	var x := x0
	for ch in text:
		if PIXEL_FONT.has(ch):
			var rows: Array = PIXEL_FONT[ch]
			for ry in 5:
				var row: String = rows[ry]
				for rx in 3:
					if row[rx] == "1":
						_soft_rect(img, x + rx * sc - sc * 0.08, y0 + ry * sc - sc * 0.08, sc * 1.16, sc * 1.16, col, a, maxf(1.0, sc * 0.18))
		x += 4.0 * sc


func _text_w(text: String, sc: float) -> float:
	return text.length() * 4.0 * sc - sc


func _fr(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	# A crowd-atlas rect in 1x cell coordinates, painted soft at 2x.
	_soft_rect(img, x * 2.0, y * 2.0, w * 2.0, h * 2.0, c, 1.0, 0.8)


func _fan_head(img: Image, ox: int, y: int, skin: Color, hair: Color) -> void:
	_soft_dot(img, (ox + 8) * 2.0, (y + 3.5) * 2.0, 6.2, 7.2, skin, 1.0, 1.0)
	_soft_dot(img, (ox + 8) * 2.0, (y + 0.6) * 2.0, 6.4, 3.6, hair, 1.0, 1.0)
	_fr(img, ox + 5, y + 1, 1, 2, hair)
	_fr(img, ox + 10, y + 1, 1, 2, hair)
	_soft_dot(img, (ox + 6.5) * 2.0, (y + 3.5) * 2.0, 0.9, 0.9, skin.darkened(0.6), 1.0, 0.8)
	_soft_dot(img, (ox + 9.5) * 2.0, (y + 3.5) * 2.0, 0.9, 0.9, skin.darkened(0.6), 1.0, 0.8)
	_fr(img, ox + 7, y + 5, 2, 1, skin.darkened(0.3))


func _make_crowd_texture() -> ImageTexture:
	# 128x32 atlas (painted at 256x64): eight 16x32 friends. Pure-white areas are the shirt/hoodie
	# (tinted per instance), pure cyan is a glowing phone screen.
	var img := Image.create_empty(256, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.08, 0.09, 0))
	var white := Color(1, 1, 1)
	var screen := Color(0, 1, 1)
	var skins: Array[Color] = [Color(0.86, 0.68, 0.54), Color(0.52, 0.36, 0.25), Color(0.76, 0.58, 0.45), Color(0.38, 0.26, 0.18),
		Color(0.8, 0.63, 0.5), Color(0.6, 0.42, 0.31), Color(0.84, 0.66, 0.53), Color(0.45, 0.31, 0.22)]
	var hairs: Array[Color] = [Color(0.24, 0.16, 0.09), Color(0.06, 0.06, 0.06), Color(0.6, 0.5, 0.25), Color(0.1, 0.07, 0.05),
		Color(0.36, 0.22, 0.12), Color(0.08, 0.06, 0.05), Color(0.5, 0.3, 0.15), Color(0.1, 0.08, 0.06)]
	var jeans := Color(0.2, 0.25, 0.38)
	var dark := Color(0.12, 0.12, 0.13)
	var cup := Color(0.65, 0.18, 0.16)
	for v in 8:
		var ox := v * 16
		var skin: Color = skins[v]
		var hair: Color = hairs[v]
		var pants: Color = jeans if v % 2 == 0 else dark
		if v == FAN_SIT or v == FAN_SIT_CUP:
			# Sitting: lower head, short torso, knees toward the viewer, shins down.
			_fr(img, ox + 7, 17, 2, 1, skin)
			_fr(img, ox + 4, 18, 8, 6, white)
			_fr(img, ox + 3, 24, 10, 3, pants)
			_fr(img, ox + 4, 27, 3, 4, pants)
			_fr(img, ox + 9, 27, 3, 4, pants)
			_fr(img, ox + 4, 31, 3, 1, dark)
			_fr(img, ox + 9, 31, 3, 1, dark)
			_fr(img, ox + 2, 18, 2, 3, white)
			_fr(img, ox + 12, 18, 2, 3, white)
			_fr(img, ox + 2, 21, 2, 3, skin)
			_fr(img, ox + 12, 21, 2, 3, skin)
			if v == FAN_SIT:
				_fr(img, ox + 4, 10, 1, 6, white)
				_fr(img, ox + 11, 10, 1, 6, white)
				_fan_head(img, ox, 10, skin, hair)
				_fr(img, ox + 5, 9, 6, 2, white)  # hood
			else:
				_fan_head(img, ox, 10, skin, hair)
				_fr(img, ox + 12, 19, 2, 3, cup)
				_fr(img, ox + 4, 8, 8, 2, Color(0.2, 0.24, 0.42))  # beanie
			continue
		# Standing body
		_fr(img, ox + 7, 10, 2, 1, skin)
		_fr(img, ox + 4, 11, 8, 10, white)
		_fr(img, ox + 4, 21, 8, 2, pants)
		_fr(img, ox + 4, 23, 3, 8, pants)
		_fr(img, ox + 9, 23, 3, 8, pants)
		_fr(img, ox + 4, 31, 3, 1, dark)
		_fr(img, ox + 9, 31, 3, 1, dark)
		_fan_head(img, ox, 3, skin, hair)
		var left_down := true
		var right_down := true
		match v:
			FAN_HOODIE:
				_fr(img, ox + 5, 1, 6, 2, white)
				_fr(img, ox + 4, 2, 1, 8, white)
				_fr(img, ox + 11, 2, 1, 8, white)
				_fr(img, ox + 6, 13, 4, 3, Color(0.88, 0.88, 0.88))  # pocket
				_fr(img, ox + 7, 11, 1, 3, dark)  # drawstrings
				_fr(img, ox + 9, 11, 1, 3, dark)
			FAN_CAP:
				_fr(img, ox + 4, 1, 8, 2, Color(0.12, 0.12, 0.14))
				_fr(img, ox + 2, 2, 3, 1, Color(0.12, 0.12, 0.14))  # backwards brim
				_fr(img, ox + 6, 14, 4, 3, Color(0.6, 0.25, 0.22))  # tee print
			FAN_CHEER:
				_fr(img, ox + 2, 1, 2, 9, skin)
				_fr(img, ox + 12, 1, 2, 9, skin)
				_fr(img, ox + 2, 10, 2, 2, white)
				_fr(img, ox + 12, 10, 2, 2, white)
				_fr(img, ox + 7, 8, 2, 1.5, Color(0.25, 0.08, 0.07))  # yelling
				left_down = false
				right_down = false
			FAN_PHONE:
				_fr(img, ox + 2, 5, 2, 6, skin)
				_fr(img, ox + 2, 11, 2, 2, white)
				_fr(img, ox + 1, 0, 4, 6, dark)
				_fr(img, ox + 2, 1, 2, 4, screen)
				left_down = false
			FAN_CUP:
				_fr(img, ox + 4, 1, 8, 3, Color(0.55, 0.38, 0.16))  # beanie
				_fr(img, ox + 12, 11, 2, 3, white)
				_fr(img, ox + 12, 14, 2, 3, skin)
				_fr(img, ox + 12, 15, 3, 4, cup)
				right_down = false
			_:  # long hair, flannel-ish stripes
				_fr(img, ox + 4, 2, 1, 9, hair)
				_fr(img, ox + 11, 2, 1, 9, hair)
				for yy in range(12, 21, 3):
					_fr(img, ox + 4, yy, 8, 1, Color(0.8, 0.8, 0.8))
		if left_down:
			_fr(img, ox + 2, 11, 2, 3, white)
			_fr(img, ox + 2, 14, 2, 6, skin)
		if right_down:
			_fr(img, ox + 12, 11, 2, 3, white)
			_fr(img, ox + 12, 14, 2, 6, skin)
	return _soft_tex(img, 128, 32)


func _make_flash_texture() -> ImageTexture:
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)) / 16.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return _soft_tex(img, 16, 16)


# ---- lights, sky, camera, post (PS2-era night look)

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
	# Night: a cool, slightly lifted ambient so the yard stays dark but readable;
	# the floodlight pools on the lawn and patio are the brightest thing on screen.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.66)
	env.ambient_light_energy = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false  # bloom is done cheaply in the post shader instead
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.08, 0.15)
	env.fog_light_energy = 1.0
	env.fog_density = 0.011
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Moonlight from behind the yard (where the moon sits in the sky): a weak cool
	# directional that rims shoulders and heads so silhouettes read against the dark.
	var moon := DirectionalLight3D.new()
	moon.transform = Transform3D(Basis.looking_at(Vector3(-0.42, -0.62, 0.66)), Vector3(0, 10, 0))
	moon.light_color = Color(0.58, 0.68, 1.0)
	moon.light_energy = 0.42
	moon.light_specular = 0.6
	moon.shadow_enabled = false
	add_child(moon)

	# Two warm floodlights on tall poles at opposite corners of the yard, each aimed at
	# its own half so the whole fighting area (x -7..7, z -5..5) sits in overlapping
	# pools: bright in the middle, falling off quickly toward the fences and the house.
	# Only the front one (ring_spot) casts a real shadow map.
	var floods: Array[SpotLight3D] = []
	var rigs: Array = [[Vector3(-6.9, 7.2, 5.9), Vector3(-0.8, 0.0, -0.6)],
		[Vector3(6.9, 7.2, -6.2), Vector3(0.6, 0.0, 0.2)]]
	for rig: Array in rigs:
		var corner: Vector3 = rig[0]
		var aim: Vector3 = rig[1]
		var fl := SpotLight3D.new()
		fl.transform = Transform3D(Basis.looking_at(aim - corner), corner)
		fl.spot_angle = 40.0
		fl.spot_angle_attenuation = 0.7
		fl.spot_range = 19.0
		fl.spot_attenuation = 1.1
		fl.light_energy = 7.5
		fl.light_specular = 0.7
		fl.light_color = Color(1.0, 0.84, 0.62)
		fl.shadow_enabled = false
		add_child(fl)
		floods.append(fl)
		# The pole and lamp head itself.
		var pole_base := Vector3(corner.x * 1.03, 0, corner.z * 1.03)
		_box(Vector3(0.12, corner.y + 0.2, 0.12), pole_base + Vector3(0, (corner.y + 0.2) * 0.5, 0), Color(0.1, 0.1, 0.11))
		var head := _box(Vector3(0.7, 0.45, 0.3), Vector3.ZERO, Color(0.16, 0.16, 0.17))
		head.transform = fl.transform
		var lens := _box(Vector3(0.6, 0.36, 0.04), Vector3.ZERO, Color(1.0, 0.92, 0.75), true)
		lens.transform = fl.transform * Transform3D(Basis(), Vector3(0, 0, -0.17))
	ring_spot = floods[0]
	ring_spot.shadow_enabled = USE_KEY_SHADOW
	ring_spot.shadow_bias = 0.06
	ring_spot.shadow_normal_bias = 1.0
	ring_spot.shadow_blur = 1.5
	ring_spot.shadow_opacity = 0.75

	# The porch / patio lamp pools by the sliding door live in _build_yard_lights().

	# Faint warm glow from the string lights hanging over the yard.
	for p: Vector3 in [Vector3(0, 4.4, -7.0), Vector3(0, 4.4, -1.0)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 7.0
		o.light_energy = 0.45
		o.light_color = Color(1.0, 0.78, 0.5)
		add_child(o)

	camera = Camera3D.new()
	camera.fov = 45
	camera.position = Vector3(0, RING_TOP + 3.3, 6.8)
	add_child(camera)
	camera.look_at(Vector3(0, RING_TOP + 0.9, 0))


# Real shadow map on the front floodlight (Compatibility renderer spot shadow, one light).
const USE_KEY_SHADOW := true

const GRADE_POST_SHADER := """
shader_type canvas_item;

// Mid-2000s console look: smooth bilinear upscale of a ~540p frame (texture filter),
// a touch of sharpening, cheap single-pass bloom on bright areas, then an "urban" grade:
// contrast, saturation, warm highlights / cool shadows, and a soft vignette.
uniform float contrast = 1.12;
uniform float saturation = 1.15;
uniform float sharpen = 0.14;
uniform float bloom_threshold = 0.68;
uniform float bloom_strength = 0.6;
uniform float bloom_radius = 5.0;
uniform vec3 shadow_tint = vec3(0.90, 0.97, 1.10);
uniform vec3 highlight_tint = vec3(1.08, 1.01, 0.88);
uniform float vignette = 0.25;

vec3 bright(vec3 c) {
	// Luminance threshold, so saturated mid-tones (the blue canvas) don't haze over.
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return c * smoothstep(bloom_threshold, 0.95, l);
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 c = texture(TEXTURE, UV).rgb;
	// 4-tap cross unsharp mask to crisp up the upscale.
	vec3 nb = texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb
		+ texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).rgb
		+ texture(TEXTURE, UV - vec2(0.0, px.y)).rgb;
	c = max(c + (c - nb * 0.25) * sharpen, vec3(0.0));
	// Bloom: two rings of 6 taps (bilinear-filtered, so each tap averages 4 texels).
	vec3 bl = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float a = float(i) * 1.0472;
		vec2 d = vec2(cos(a), sin(a)) * px * bloom_radius;
		vec2 d2 = vec2(cos(a + 0.5236), sin(a + 0.5236)) * px * bloom_radius * 2.3;
		bl += bright(texture(TEXTURE, UV + d).rgb) * 0.6;
		bl += bright(texture(TEXTURE, UV + d2).rgb) * 0.4;
	}
	c += bl / 6.0 * bloom_strength;
	// Contrast around mid-grey, then saturation.
	c = (c - 0.5) * contrast + 0.5;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(l), c, saturation);
	// Split toning: cool shadows, warm highlights.
	l = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
	vec3 tint = mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.75, l));
	c *= mix(vec3(1.0), tint, 0.85);
	// Vignette (~25% darker in the corners).
	vec2 v = (UV - 0.5) * vec2(1.0, 0.85) * 1.414;
	c *= 1.0 - vignette * smoothstep(0.35, 1.0, dot(v, v));
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
"""

var low_res_rect: TextureRect
var low_res_view: SubViewport


func _build_low_res_view() -> void:
	# Render the 3D world into a SubViewport that shares this World3D (so the
	# WorldEnvironment still applies) at ~540 lines, then draw it full-screen with
	# bilinear upscale through the grade/bloom post shader. A TextureRect (instead of a
	# SubViewportContainer) allows non-integer scale factors. It sits on a canvas layer
	# below the HUD and never eats input.
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	low_res_view = SubViewport.new()
	low_res_view.own_world_3d = false
	low_res_view.msaa_3d = Viewport.MSAA_2X  # light AA, cheap on tile GPUs
	low_res_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	low_res_view.handle_input_locally = false
	low_res_view.gui_disable_input = true
	low_res_view.physics_object_picking = false
	low_res_view.audio_listener_enable_3d = true
	low_res_view.positional_shadow_atlas_size = 1024
	low_res_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	layer.add_child(low_res_view)
	low_res_rect = TextureRect.new()
	low_res_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	low_res_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	low_res_rect.stretch_mode = TextureRect.STRETCH_SCALE
	low_res_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	low_res_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low_res_rect.focus_mode = Control.FOCUS_NONE
	var post := ShaderMaterial.new()
	var psh := Shader.new()
	psh.code = GRADE_POST_SHADER
	post.shader = psh
	low_res_rect.material = post
	low_res_rect.texture = low_res_view.get_texture()
	layer.add_child(low_res_rect)
	var keep := camera.global_transform
	camera.get_parent().remove_child(camera)
	low_res_view.add_child(camera)
	camera.global_transform = keep
	camera.current = true
	_update_low_res_shrink()
	get_viewport().size_changed.connect(_update_low_res_shrink)


func _update_low_res_shrink() -> void:
	if low_res_view == null:
		return
	# Size from the real window pixels (canvas_items stretch hides them): full res up
	# to ~600 lines (small phones), otherwise ~60% of the height, 540..720 lines.
	var win := Vector2(DisplayServer.window_get_size())
	if win.x < 1.0 or win.y < 1.0:
		win = get_viewport().get_visible_rect().size
	var h := win.y
	if h > 600.0:
		h = clampf(h * 0.6, 540.0, 720.0)
	var w := h * win.x / maxf(win.y, 1.0)
	low_res_view.size = Vector2i(maxi(16, roundi(w)), maxi(16, roundi(h)))


# ---- the backyard (no ring: they fight on the lawn and the concrete patio)
# Everything is in ring_root-local == world coordinates (ring_root sits at the origin), ground y 0.
# See yard_contract.md: fighting area x -7..7, z -5..5; house at -z, camera on +z.

var yard_bounds := Rect2(-7.0, -5.0, 14.0, 10.0)   # x, z, width, depth of the fighting area
const PATIO_RECT := Rect2(-7.5, -8.6, 7.0, 7.1)     # concrete slab: x -7.5..-0.5, z -8.6..-1.5
const DRIVE_RECT := Rect2(4.3, 1.2, 9.5, 2.9)       # driveway strip under the car: x 4.3..13.8, z 1.2..4.1
const HOUSE_Z := -8.6                               # back wall of the house
const FENCE_X := 7.5                                # side privacy fences
const FENCE_Z := 5.6                                # low picket fence on the camera side
const FENCE_H := 1.9
# Perches (replace the turnbuckles). Each: {"pos", "approach", "height", "kind", "name"}.
var perches: Array = []

const LAWN_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D map : source_color, filter_linear_mipmap;
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 10.0;

void fragment() {
	vec3 m = texture(map, UV).rgb;
	vec3 d = texture(detail, UV * detail_scale).rgb;
	ALBEDO = m * d * 2.0;
	ROUGHNESS = 0.95;
}
"""


func surface_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	if PATIO_RECT.has_point(q) or DRIVE_RECT.has_point(q):
		return "concrete"
	return "grass"


func _add_perch(perch_name: String, kind: String, pos: Vector3, approach: Vector3) -> void:
	perches.append({"pos": pos, "approach": approach, "height": pos.y, "kind": kind, "name": perch_name})


func _ground_quad(center: Vector3, size: Vector2, m: Material, yaw := 0.0, uv_scale := Vector2.ONE) -> MeshInstance3D:
	# Flat upward quad with explicit UVs: u along +x, v along +z (image top = far side from the camera).
	var b := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var pts: Array[Vector3] = [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(uv_scale.x, 0), uv_scale, Vector2(0, uv_scale.y)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[i])
		st.add_vertex(center + b * pts[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_arena() -> void:
	perches.clear()
	rope_nodes.clear()   # no ring, no ropes: the rope FX no-ops
	var far := _tex_mat(_make_grass_detail())
	far.albedo_color = Color(0.2, 0.32, 0.1)
	far.uv1_scale = Vector3(60, 60, 1)
	far.cull_mode = BaseMaterial3D.CULL_DISABLED
	_plane(Vector2(90, 90), Vector3(0, -0.01, 0), far)
	_build_lawn()
	_build_house()
	_build_fence()
	_build_props()
	_build_perches()
	_build_car()
	_build_string_lights()
	_build_yard_lights()
	_flush_batches()


func _build_lawn() -> void:
	var sh := Shader.new()
	sh.code = LAWN_SHADER
	var lm := ShaderMaterial.new()
	lm.shader = sh
	lm.set_shader_parameter("map", _make_lawn_map())
	lm.set_shader_parameter("detail", _make_grass_detail())
	lm.set_shader_parameter("detail_scale", 10.0)
	_ground_quad(Vector3(LAWN_RECT.get_center().x, 0.0, LAWN_RECT.get_center().y), LAWN_RECT.size, lm)
	# Concrete patio slab by the house (+ a thin raised edge) and the driveway strip.
	var pm := _tex_mat(_make_concrete_texture(256, true, 5))
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground_quad(Vector3(PATIO_RECT.get_center().x, 0.015, PATIO_RECT.get_center().y), PATIO_RECT.size, pm)
	var edge := Color(0.42, 0.41, 0.38)
	_bx("block", Vector3(PATIO_RECT.size.x, 0.03, 0.08), Vector3(PATIO_RECT.get_center().x, 0.012, PATIO_RECT.end.y), edge)
	_bx("block", Vector3(0.08, 0.03, PATIO_RECT.size.y), Vector3(PATIO_RECT.end.x, 0.012, PATIO_RECT.get_center().y), edge)
	var dm := _tex_mat(_make_concrete_texture(128, true, 4))
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground_quad(Vector3(DRIVE_RECT.get_center().x, 0.015, DRIVE_RECT.get_center().y), DRIVE_RECT.size, dm, 0.0, Vector2(3.0, 1.0))
	# Spray-painted "C2C" on the patio: the backyard federation's "logo".
	var spray := _tex_mat(_make_spray_texture(), false, true)
	spray.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground_quad(Vector3(-2.4, 0.025, -2.9), Vector2(3.2, 1.6), spray, 0.08)


func _build_house() -> void:
	# Back of a two-story house at -z: the backdrop of the broadcast shot.
	var wall_z := HOUSE_Z
	var depth := 8.0
	var w := 9.0
	var top := 6.2
	var ridge := 8.4
	var siding := Color(0.62, 0.6, 0.52)
	var trim := Color(0.82, 0.8, 0.74)
	_bx("siding", Vector3(2 * w, top, 0.3), Vector3(0, top * 0.5, wall_z - 0.15), siding, 0.0, 0.6)
	_bx("siding", Vector3(0.3, top, depth), Vector3(-w, top * 0.5, wall_z - depth * 0.5), siding, 0.0, 0.6)
	_bx("siding", Vector3(0.3, top, depth), Vector3(w, top * 0.5, wall_z - depth * 0.5), siding, 0.0, 0.6)
	_bx("brick", Vector3(2 * w + 0.3, 0.6, 0.36), Vector3(0, 0.3, wall_z - 0.12), Color(1, 1, 1))  # brick foundation
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
	var run := depth * 0.5 + 0.6
	var rise := (ridge - top) * run / (depth * 0.5)
	var slope := atan2(rise, run)
	var slab_len := sqrt(run * run + rise * rise)
	var roof_col := Color(0.3, 0.27, 0.27)
	for s: float in [1.0, -1.0]:
		var zc := wall_z - depth * 0.5 + s * run * 0.5
		var yc := ridge + 0.1 - rise * 0.5
		var b := Basis(Vector3.RIGHT, slope * s)
		_sbox("shingle", Vector3(2 * w + 1.0, 0.16, slab_len), Transform3D(b, Vector3(0, yc, zc)), roof_col, 0.7)
	_bx("flat", Vector3(2 * w + 1.0, 0.14, 0.14), Vector3(0, top - 0.32, wall_z + 0.62), trim)  # gutter
	_bx("flat", Vector3(0.1, top - 0.4, 0.1), Vector3(-8.7, (top - 0.4) * 0.5, wall_z + 0.1), trim.darkened(0.2))  # downspout
	_bx("brick", Vector3(1.0, 2.6, 1.0), Vector3(5.5, ridge + 0.4, wall_z - 2.8), Color(0.9, 0.85, 0.85))  # chimney

	# Upstairs windows (lit warm, TV-blue, dark), kitchen window over the patio.
	var wf := wall_z + 0.02
	var ups: Array[float] = [-6.5, -2.4, 2.0, 6.2]
	var up_cols: Array[Color] = [Color(0.95, 0.7, 0.36), Color(0.05, 0.05, 0.07), Color(0.35, 0.48, 0.85), Color(0.9, 0.62, 0.3)]
	for i in ups.size():
		_bx("flat", Vector3(1.5, 1.4, 0.06), Vector3(ups[i], 4.55, wf), trim)
		_bx("glow", Vector3(1.3, 1.2, 0.06), Vector3(ups[i], 4.55, wf + 0.03), up_cols[i])
		_bx("flat", Vector3(0.06, 1.2, 0.07), Vector3(ups[i], 4.55, wf + 0.04), trim)
		_bx("flat", Vector3(1.3, 0.06, 0.07), Vector3(ups[i], 4.55, wf + 0.04), trim)
		_bx("flat", Vector3(0.3, 1.4, 0.06), Vector3(ups[i] - 0.92, 4.55, wf), Color(0.14, 0.2, 0.26))  # shutters
		_bx("flat", Vector3(0.3, 1.4, 0.06), Vector3(ups[i] + 0.92, 4.55, wf), Color(0.14, 0.2, 0.26))
	_bx("flat", Vector3(1.6, 1.2, 0.06), Vector3(-6.3, 1.9, wf), trim)
	_bx("glow", Vector3(1.4, 1.0, 0.06), Vector3(-6.3, 1.9, wf + 0.03), Color(0.92, 0.75, 0.46))
	_bx("flat", Vector3(1.4, 0.3, 0.07), Vector3(-6.3, 2.25, wf + 0.04), Color(0.55, 0.2, 0.16))  # valance
	# Sliding glass door onto the patio, with a lamp over it.
	_bx("flat", Vector3(2.6, 2.3, 0.06), Vector3(-3.4, 1.2, wf), Color(0.5, 0.5, 0.52))
	_bx("glow", Vector3(2.4, 2.1, 0.06), Vector3(-3.4, 1.2, wf + 0.03), Color(0.46, 0.36, 0.24))
	_bx("flat", Vector3(0.08, 2.1, 0.08), Vector3(-3.4, 1.2, wf + 0.05), Color(0.5, 0.5, 0.52))
	_bx("flat", Vector3(0.7, 2.0, 0.07), Vector3(-4.25, 1.2, wf + 0.05), Color(0.36, 0.28, 0.2))  # half-drawn curtain
	_bx("glow", Vector3(0.2, 0.3, 0.16), Vector3(-1.8, 2.6, wf + 0.08), Color(1.0, 0.82, 0.5))
	# Back door up on the porch, its light.
	_bx("flat", Vector3(1.1, 2.15, 0.06), Vector3(3.2, 1.0 + 1.07, wf), trim)
	_bx("flat", Vector3(0.95, 2.05, 0.07), Vector3(3.2, 1.0 + 1.03, wf + 0.01), Color(0.32, 0.12, 0.1))
	_bx("glow", Vector3(0.5, 0.6, 0.08), Vector3(3.2, 2.45, wf + 0.04), Color(0.95, 0.75, 0.45))  # door window
	_bx("glow", Vector3(0.2, 0.3, 0.16), Vector3(4.2, 2.9, wf + 0.08), Color(1.0, 0.82, 0.5))
	# AC unit and a coiled hose on the patio by the wall.
	_bx("metal", Vector3(0.8, 0.75, 0.8), Vector3(-0.95, 0.4, wall_z + 0.55), Color(0.62, 0.62, 0.6))
	_bx("flat", Vector3(0.7, 0.03, 0.7), Vector3(-0.95, 0.79, wall_z + 0.55), Color(0.12, 0.12, 0.12))
	_cy("flat", 0.3, 0.3, 0.12, Vector3(-7.0, 0.07, wall_z + 0.5), Color(0.15, 0.4, 0.18), 10)

	# Raised wooden porch (x 0..6, top y 1.0) with steps down to the yard, railing, roof.
	var deck_y := 1.0
	var wood := Color(0.5, 0.4, 0.3)
	var px0 := 0.0
	var px1 := 6.0
	var front := -5.7
	var dz := front - wall_z
	_bx("wood", Vector3(px1 - px0, 0.1, dz), Vector3((px0 + px1) * 0.5, deck_y - 0.05, (wall_z + front) * 0.5), wood)
	_bx("flat", Vector3(px1 - px0, deck_y - 0.1, 0.04), Vector3((px0 + px1) * 0.5, (deck_y - 0.1) * 0.5, front + 0.05), Color(0.12, 0.1, 0.08))  # dark lattice skirt
	for k in 15:
		_bx("wood", Vector3(0.03, 0.03, 1.2), Vector3(px0 + 0.2 + k * 0.4, 0.45, front + 0.02), wood, PI * 0.25)
	for sx: float in [px0, px1]:
		_bx("flat", Vector3(0.04, deck_y - 0.1, dz), Vector3(sx, (deck_y - 0.1) * 0.5, (wall_z + front) * 0.5), Color(0.12, 0.1, 0.08))
	# Steps (three 0.25 m risers) centred on x 1.6
	var sx0 := 1.6
	for k in 3:
		var h := deck_y - 0.25 * (k + 1)
		var z0 := front + 0.3 * k
		_bx("wood", Vector3(1.4, h, 0.32), Vector3(sx0, h * 0.5, z0 + 0.15), wood.lightened(0.05 * k))
	# Railing (top y deck+0.95) with balusters, gap for the steps.
	var rail := wood.lightened(0.12)
	var rail_top := deck_y + 0.95
	var segs: Array = [[Vector3(px0, 0, front), Vector3(sx0 - 0.75, 0, front)], [Vector3(sx0 + 0.75, 0, front), Vector3(px1, 0, front)],
		[Vector3(px1, 0, front), Vector3(px1, 0, wall_z)], [Vector3(px0, 0, front), Vector3(px0, 0, wall_z)]]
	for sg: Array in segs:
		var a: Vector3 = sg[0]
		var b2: Vector3 = sg[1]
		var d := b2 - a
		var yaw := atan2(-d.z, d.x)
		var l := d.length()
		_bx("wood", Vector3(l, 0.07, 0.12), (a + b2) * 0.5 + Vector3(0, rail_top, 0), rail, yaw)
		_bx("wood", Vector3(l, 0.05, 0.05), (a + b2) * 0.5 + Vector3(0, deck_y + 0.12, 0), rail, yaw)
		var nb := int(l / 0.16)
		for k in nb:
			_bx("wood", Vector3(0.04, 0.8, 0.04), a + d * ((k + 0.5) / nb) + Vector3(0, deck_y + 0.52, 0), rail, yaw)
	for k in 2:
		var hx := sx0 + (0.72 if k == 0 else -0.72)
		_beam("wood", Vector3(hx, rail_top, front), Vector3(hx, 0.95, front + 0.95), 0.06, rail)  # step handrails
		_bx("wood", Vector3(0.1, 1.0, 0.1), Vector3(hx, 0.5, front + 0.92), rail)
	var roof_y := 3.4
	for ppx: float in [px0 + 0.1, 3.0, px1 - 0.1]:
		_bx("wood", Vector3(0.16, roof_y - deck_y, 0.16), Vector3(ppx, deck_y + (roof_y - deck_y) * 0.5, front + 0.1), rail)
	_bx("shingle", Vector3(px1 - px0 + 0.6, 0.18, dz + 0.6), Vector3((px0 + px1) * 0.5, roof_y + 0.09, (wall_z + front) * 0.5 + 0.3), Color(0.3, 0.27, 0.27), 0.0, 0.7)
	_bx("flat", Vector3(px1 - px0 + 0.6, 0.22, 0.06), Vector3((px0 + px1) * 0.5, roof_y + 0.05, front + 0.6), trim)
	# Hand-painted bedsheet banner hanging off the porch roof
	var sheet_z := front + 0.66
	_bx("flat", Vector3(4.6, 0.9, 0.03), Vector3(3.6, roof_y - 0.42, sheet_z), Color(0.86, 0.84, 0.78))
	_bx("flat", Vector3(4.6, 0.04, 0.035), Vector3(3.6, roof_y - 0.1, sheet_z), Color(0.5, 0.48, 0.44))
	var lines: Array[String] = ["CITY 2 CITY WRESTLING", "BACKYARD BRAWL"]
	var line_cols: Array[Color] = [Color(0.7, 0.1, 0.08), Color(0.1, 0.16, 0.45)]
	for li in 2:
		var lab := Label3D.new()
		lab.text = lines[li]
		lab.font_size = 46 if li == 0 else 40
		lab.outline_size = 0
		lab.modulate = line_cols[li]
		lab.shaded = true
		lab.position = Vector3(3.6, roof_y - 0.28 - li * 0.3, sheet_z + 0.025)
		lab.rotation_degrees = Vector3(0, 0, -1.5 + li * 2.5)
		add_child(lab)
	# Couch + grill on the porch
	var cp := Vector3(4.5, deck_y, wall_z + 0.75)
	var couch := Color(0.36, 0.33, 0.2)
	_bx("flat", Vector3(2.2, 0.45, 0.95), cp + Vector3(0, 0.22, 0), couch)
	_bx("flat", Vector3(2.2, 0.6, 0.28), cp + Vector3(0, 0.6, -0.36), couch.darkened(0.1))
	for s: float in [-1.0, 1.0]:
		_bx("flat", Vector3(0.26, 0.62, 0.95), cp + Vector3(s * 1.1, 0.31, 0), couch.darkened(0.15))
	_bx("flat", Vector3(0.7, 0.12, 0.6), cp + Vector3(-0.4, 0.5, 0.05), Color(0.5, 0.42, 0.26))
	var gp := Vector3(0.8, deck_y, wall_z + 0.9)
	_cy("flat", 0.3, 0.4, 0.35, gp + Vector3(0, 0.95, 0), Color(0.07, 0.07, 0.08), 10)
	_cy("flat", 0.4, 0.24, 0.25, gp + Vector3(0, 1.25, 0), Color(0.08, 0.08, 0.09), 10)
	_cy("glow", 0.31, 0.31, 0.02, gp + Vector3(0, 1.12, 0), Color(1.0, 0.4, 0.1), 10)
	for k in 3:
		var a3 := TAU * k / 3.0 + 0.3
		_beam("flat", gp + Vector3(cos(a3) * 0.35, 0, sin(a3) * 0.35), gp + Vector3(0, 0.85, 0), 0.04, Color(0.07, 0.07, 0.08))

	# Neighbours' houses beyond the side fences + a dark tree line.
	for nb: Vector3 in [Vector3(-17.5, 0, -6.0), Vector3(17.5, 0, -9.0)]:
		_bx("siding", Vector3(9.0, 5.6, 7.0), nb + Vector3(0, 2.8, 0), Color(0.5, 0.46, 0.38) if nb.x < 0.0 else Color(0.4, 0.45, 0.5), PI * 0.5, 0.6)
		for s: float in [-1.0, 1.0]:
			_sbox("shingle", Vector3(4.2, 0.2, 9.6), Transform3D(Basis(Vector3.BACK, -0.5 * s), nb + Vector3(1.85 * s, 6.6, 0)), Color(0.22, 0.2, 0.2), 0.7)
		var face := -signf(nb.x) * 3.52
		_bx("glow", Vector3(0.06, 1.0, 1.2), nb + Vector3(face, 3.8, 1.8), Color(0.85, 0.62, 0.34))
		_bx("glow", Vector3(0.06, 1.0, 1.2), nb + Vector3(face, 1.6, -2.0), Color(0.3, 0.4, 0.65))
	var trees: Array[Vector3] = [Vector3(-11.0, 0, -12.5), Vector3(-12.0, 0, 2.5), Vector3(11.0, 0, -14.0), Vector3(12.5, 0, -2.5),
		Vector3(12.0, 0, 9.0), Vector3(-11.5, 0, 9.5), Vector3(-3.0, 0, -19.0), Vector3(6.0, 0, -19.5)]
	for t in trees:
		var th := randf_range(6.0, 9.0)
		_cy("flat", 0.25, 0.2, 1.6, t + Vector3(0, 0.8, 0), Color(0.12, 0.09, 0.06), 6)
		_cy("flat", 2.4, 0.0, th * 0.6, t + Vector3(0, 1.4 + th * 0.3, 0), Color(0.04, 0.08, 0.05), 8)
		_cy("flat", 1.8, 0.0, th * 0.5, t + Vector3(0, 1.4 + th * 0.65, 0), Color(0.05, 0.1, 0.06), 8)


func _fence_run(a: Vector3, b: Vector3, fh: float, picket := false) -> void:
	# Weathered board-on-board privacy fence (or a low picket fence) from a to b.
	var d := b - a
	var run_len := d.length()
	if run_len < 0.1:
		return
	var dir := d / run_len
	var yaw := atan2(-dir.z, dir.x)
	var step := 0.16 if picket else 0.3
	var count := maxi(1, int(run_len / step))
	for k in count:
		var p := a + dir * ((k + 0.5) * run_len / count)
		var tint := randf_range(-0.05, 0.05)
		var bh := fh + (0.06 if k % 2 == 0 else 0.0) + randf_range(-0.03, 0.03)
		var bw := run_len / count - (0.07 if picket else 0.015)
		var lean := randf_range(-0.02, 0.02)
		_sbox("wood", Vector3(bw, bh, 0.035), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean), p + Vector3(0, bh * 0.5, 0)), Color(0.66 + tint, 0.58 + tint, 0.48 + tint))
	var posts := maxi(1, int(run_len / 2.4))
	for k in posts + 1:
		var pp := a + dir * (k * run_len / posts)
		_bx("wood", Vector3(0.11, fh + 0.12, 0.11), pp + Vector3(0, (fh + 0.12) * 0.5, 0), Color(0.42, 0.36, 0.3), yaw)
	for ry: float in ([fh * 0.75, fh * 0.25] if picket else [fh - 0.3, 0.3]):
		_bx("wood", Vector3(run_len, 0.08, 0.05), (a + b) * 0.5 + Vector3(0, ry, 0) - Vector3(dir.z, 0, -dir.x) * 0.04, Color(0.45, 0.38, 0.3), yaw)


func _build_fence() -> void:
	# Side runs just outside the fighting area; -x has a gap filled by the shed, +x a gate for the driveway.
	var fz := FENCE_Z
	_fence_run(Vector3(-FENCE_X, 0, HOUSE_Z), Vector3(-FENCE_X, 0, -1.0), FENCE_H)
	_fence_run(Vector3(-FENCE_X, 0, 1.8), Vector3(-FENCE_X, 0, fz), FENCE_H)
	_fence_run(Vector3(FENCE_X, 0, HOUSE_Z), Vector3(FENCE_X, 0, 1.2), FENCE_H)
	_fence_run(Vector3(FENCE_X, 0, 4.1), Vector3(FENCE_X, 0, fz), FENCE_H)
	# The gate swung open outward against the car's side of the driveway.
	_fence_run(Vector3(FENCE_X, 0, 4.1), Vector3(FENCE_X + 1.9, 0, 4.9), FENCE_H)
	# Camera side: low picket fence at the corners; the middle panels lie knocked flat on the grass.
	_fence_run(Vector3(-FENCE_X, 0, fz), Vector3(-2.6, 0, fz), 0.65, true)
	_fence_run(Vector3(2.6, 0, fz), Vector3(FENCE_X, 0, fz), 0.65, true)
	for k in 2:
		var cx := -1.3 + k * 2.6
		_bx("wood", Vector3(2.5, 0.05, 0.85), Vector3(cx, 0.04, fz + 0.55 + k * 0.1), Color(0.6, 0.53, 0.44), randf_range(-0.12, 0.12))
		_bx("wood", Vector3(2.5, 0.08, 0.06), Vector3(cx, 0.09, fz + 0.4 + k * 0.1), Color(0.45, 0.38, 0.3))


func _lawn_chair(pos: Vector3, face: Vector3, col: Color) -> void:
	var b := Basis.looking_at(face)
	var frame := Color(0.6, 0.61, 0.63)
	var xf := Transform3D(b, pos)
	_sbox("flat", Vector3(0.52, 0.04, 0.46), xf * Transform3D(Basis(), Vector3(0, 0.42, 0)), col)
	_sbox("flat", Vector3(0.52, 0.55, 0.04), xf * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.72, 0.25)), col)
	for sx: float in [-0.26, 0.26]:
		_beam("flat", xf * Vector3(sx, 0, -0.22), xf * Vector3(sx, 0.42, 0.18), 0.03, frame)
		_beam("flat", xf * Vector3(sx, 0, 0.22), xf * Vector3(sx, 0.42, -0.18), 0.03, frame)
		_beam("flat", xf * Vector3(sx, 0.62, -0.2), xf * Vector3(sx, 0.62, 0.2), 0.03, frame)


func _build_props() -> void:
	# Decoration outside the fighting area (the perches are in _build_perches).
	# Lawn chairs at the back of the patio
	_lawn_chair(Vector3(-6.4, 0.015, -6.2), Vector3(0.3, 0, 1), Color(0.2, 0.45, 0.3))
	_lawn_chair(Vector3(-5.6, 0.015, -6.5), Vector3(0.1, 0, 1), Color(0.65, 0.25, 0.2))
	_lawn_chair(Vector3(-1.6, 0.015, -6.6), Vector3(-0.2, 0, 1), Color(0.22, 0.32, 0.62))
	# Coolers
	_bx("flat", Vector3(0.7, 0.42, 0.42), Vector3(-4.6, 0.225, -6.9), Color(0.65, 0.18, 0.14), 0.3)
	_bx("flat", Vector3(0.72, 0.08, 0.44), Vector3(-4.6, 0.46, -6.9), Color(0.85, 0.85, 0.82), 0.3)
	_bx("flat", Vector3(0.6, 0.38, 0.38), Vector3(8.6, 0.2, 4.6), Color(0.15, 0.3, 0.6), -0.4)
	# Garbage cans + recycling bin in the back corner by the porch
	for tc: Vector3 in [Vector3(6.75, 0, -7.9), Vector3(6.85, 0, -7.2)]:
		_cy("metal", 0.3, 0.33, 0.85, tc + Vector3(0, 0.425, 0), Color(0.5, 0.51, 0.5), 10)
		_cy("metal", 0.36, 0.3, 0.08, tc + Vector3(0, 0.89, 0), Color(0.55, 0.56, 0.55), 10)
	_bx("flat", Vector3(0.6, 1.0, 0.65), Vector3(6.8, 0.5, -6.4), Color(0.12, 0.25, 0.55))
	# Garden gnomes (outside the fighting area)
	var gnomes: Array[Vector3] = [Vector3(-0.9, 0, -7.6), Vector3(6.6, 0, -5.4), Vector3(-3.6, 0, 6.1), Vector3(3.4, 0, 6.0), Vector3(-7.0, 0, -5.6)]
	for i in gnomes.size():
		var g: Vector3 = gnomes[i]
		_cy("flat", 0.13, 0.09, 0.22, g + Vector3(0, 0.11, 0), [Color(0.17, 0.3, 0.6), Color(0.18, 0.48, 0.25)][i % 2], 8)
		_bx("flat", Vector3(0.13, 0.12, 0.13), g + Vector3(0, 0.28, 0), Color(0.8, 0.62, 0.5))
		_bx("flat", Vector3(0.14, 0.1, 0.06), g + Vector3(0, 0.22, 0.07), Color(0.85, 0.85, 0.85))
		_cy("flat", 0.09, 0.0, 0.22, g + Vector3(0, 0.45, 0), Color(0.7, 0.12, 0.1), 8)
	# Kiddie pool outside the picket fence, camera-left corner
	var kp := Vector3(-5.6, 0, 7.4)
	_cy("flat", 1.0, 1.05, 0.3, kp + Vector3(0, 0.15, 0), Color(0.3, 0.5, 0.75), 14)
	_cy("glow", 0.9, 0.9, 0.02, kp + Vector3(0, 0.25, 0), Color(0.12, 0.25, 0.32), 14)


func _build_perches() -> void:
	# Six things to climb, spread around the edge of the yard; the middle stays open.
	var wood := Color(0.55, 0.45, 0.33)
	var metal := Color(0.55, 0.56, 0.58)

	# 1) Picnic table on the patio (top 0.75)
	var pt := Vector3(-4.4, 0.015, -3.5)
	_bx("wood", Vector3(1.9, 0.06, 0.8), pt + Vector3(0, 0.72, 0), wood)
	for s: float in [-1.0, 1.0]:
		_bx("wood", Vector3(1.9, 0.05, 0.28), pt + Vector3(0, 0.43, s * 0.62), wood.darkened(0.08))
		for lx: float in [-0.7, 0.7]:
			_beam("wood", pt + Vector3(lx, 0, s * 0.78), pt + Vector3(lx, 0.7, s * 0.12), 0.08, wood.darkened(0.15))
	for lx: float in [-0.7, 0.7]:
		_bx("wood", Vector3(0.08, 0.06, 1.6), pt + Vector3(lx, 0.38, 0), wood.darkened(0.15))
	_cy("flat", 0.04, 0.04, 0.12, pt + Vector3(0.5, 0.81, 0.1), Color(0.65, 0.12, 0.1), 8)  # red cup
	_add_perch("picnic table", "table", Vector3(-4.4, 0.75, -3.5), Vector3(-4.4, 0.0, -2.3))

	# 2) Stacked pallets on cinder blocks (top 1.2) by the left fence, camera side
	var pp := Vector3(-6.0, 0, 3.6)
	var block := Color(0.75, 0.74, 0.7)
	for cx: float in [-0.4, 0.4]:
		for cz: float in [-0.3, 0.3]:
			for k in 2:
				_bx("block", Vector3(0.4, 0.2, 0.2), pp + Vector3(cx, 0.1 + k * 0.2, cz), block.darkened(randf() * 0.15), PI * 0.5 * k)
	for k in 5:
		var y0 := 0.4 + k * 0.16
		var jit := Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05))
		var pyaw := randf_range(-0.06, 0.06)
		var pal := wood.darkened(randf_range(0.0, 0.2))
		for bz: float in [-0.45, 0.0, 0.45]:
			_bx("wood", Vector3(1.2, 0.02, 0.1), pp + jit + Vector3(0, y0 + 0.01, bz), pal, pyaw)
			_bx("wood", Vector3(1.2, 0.11, 0.08), pp + jit + Vector3(0, y0 + 0.075, bz), pal.darkened(0.1), pyaw)
		for sx in 7:
			_bx("wood", Vector3(0.12, 0.025, 1.0), pp + jit + Vector3(-0.54 + sx * 0.18, y0 + 0.1475, 0), pal.lightened(0.05), pyaw)
	for k in 2:
		_bx("block", Vector3(0.4, 0.2, 0.2), Vector3(-5.2, 0.1 + k * 0.2, 3.6), block, PI * 0.5)  # step block
	_add_perch("pallet stack", "pallets", Vector3(-6.0, 1.2, 3.6), Vector3(-4.8, 0.0, 3.5))

	# 3) Porch steps / railing (deck top 1.0), built with the house
	_add_perch("porch steps", "porch", Vector3(1.6, 1.0, -5.95), Vector3(1.6, 0.0, -4.3))

	# 4) Car hood: in _build_car
	# 5) Trampoline (mat 0.9): extra air
	var tp := Vector3(5.0, 0, -2.6)
	_cy("flat", 1.45, 1.45, 0.07, tp + Vector3(0, 0.865, 0), Color(0.12, 0.3, 0.7), 16)
	_cy("flat", 1.22, 1.22, 0.02, tp + Vector3(0, 0.9, 0), Color(0.03, 0.03, 0.035), 16)
	for k in 8:
		var a2 := TAU * k / 8.0 + 0.2
		var lp := tp + Vector3(cos(a2) * 1.38, 0, sin(a2) * 1.38)
		_beam("metal", lp + Vector3(0, 0.05, 0), lp + Vector3(0, 0.83, 0), 0.05, metal)
		if k % 2 == 0:
			var a3 := a2 + TAU / 8.0
			_beam("metal", lp + Vector3(0, 0.03, 0), tp + Vector3(cos(a3) * 1.38, 0.03, sin(a3) * 1.38), 0.05, metal)
	_add_perch("trampoline", "trampoline", Vector3(5.0, 0.9, -2.6), Vector3(3.4, 0.0, -2.0))

	# 6) Shed in the left fence line, ladder up to its flat roof (2.4): the biggest dive
	var shed := Color(0.42, 0.5, 0.42)
	var sx0 := -8.1
	var sw := 2.6
	var sz := 0.4
	var sd := 2.8
	_bx("wood", Vector3(sw, 2.25, sd), Vector3(sx0, 1.125, sz), shed)
	_bx("shingle", Vector3(sw + 0.4, 0.15, sd + 0.4), Vector3(sx0, 2.325, sz), Color(0.26, 0.25, 0.25), 0.0, 0.7)
	_bx("flat", Vector3(0.04, 0.1, sd + 0.4), Vector3(sx0 + sw * 0.5 + 0.2, 2.3, sz), Color(0.75, 0.75, 0.7))  # drip edge
	var fxw := sx0 + sw * 0.5 + 0.01
	_bx("flat", Vector3(0.05, 1.9, 1.3), Vector3(fxw, 0.95, sz - 0.65), shed.darkened(0.3))  # doors
	_bx("flat", Vector3(0.06, 1.9, 0.04), Vector3(fxw + 0.01, 0.95, sz - 0.65), Color(0.1, 0.1, 0.1))
	_bx("flat", Vector3(0.06, 0.4, 1.4), Vector3(fxw + 0.01, 0.95, sz - 0.65), Color(0.55, 0.55, 0.5))  # X brace hint
	_bx("glow", Vector3(0.05, 0.45, 0.5), Vector3(fxw, 1.55, sz + 1.05), Color(0.25, 0.2, 0.12))  # dim window
	var lb := Vector3(-5.95, 0, 0.9)
	var lt := Vector3(fxw + 0.1, 2.75, 0.9)
	for s: float in [-0.22, 0.22]:
		_beam("metal", lb + Vector3(0, 0, s), lt + Vector3(0, 0, s), 0.06, Color(0.75, 0.72, 0.5))
	for k in 8:
		_bx("metal", Vector3(0.05, 0.04, 0.44), lb.lerp(lt, (k + 0.6) / 8.6), Color(0.75, 0.72, 0.5))
	_add_perch("shed roof", "roof", Vector3(-7.0, 2.4, 0.9), Vector3(-5.6, 0.0, 0.9))


func _build_car() -> void:
	# Beat-up sedan on the driveway strip, nose poking through the open gate, headlights on the lawn.
	var pos := Vector3(6.9, 0, 2.65)
	var face := Vector3(-1, 0, 0)
	var xf := Transform3D(Basis.looking_at(face), pos)
	var body := Color(0.45, 0.1, 0.09)
	var glass := Color(0.05, 0.06, 0.08)
	_sbox("flat", Vector3(1.8, 0.65, 4.4), xf * Transform3D(Basis(), Vector3(0, 0.62, 0)), body)
	_sbox("flat", Vector3(1.6, 0.55, 2.2), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), body.darkened(0.1))
	_sbox("flat", Vector3(1.64, 0.4, 2.0), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), glass)
	_sbox("flat", Vector3(1.4, 0.42, 2.24), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), glass)
	_sbox("flat", Vector3(1.0, 0.02, 0.9), xf * Transform3D(Basis(), Vector3(0.2, 0.955, -1.5)), Color(0.5, 0.5, 0.48))  # primer hood patch
	_sbox("metal", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.38, -2.22)), Color(0.6, 0.6, 0.62))
	_sbox("metal", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.38, 2.22)), Color(0.6, 0.6, 0.62))
	for sx: float in [-0.65, 0.65]:
		_sbox("glow", Vector3(0.36, 0.2, 0.06), xf * Transform3D(Basis(), Vector3(sx, 0.72, -2.21)), Color(1.0, 0.97, 0.85))
		_sbox("glow", Vector3(0.3, 0.16, 0.06), xf * Transform3D(Basis(), Vector3(sx, 0.75, 2.21)), Color(0.9, 0.08, 0.06))
		for sz: float in [-1.35, 1.35]:
			_scyl("flat", 0.33, 0.33, 0.24, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.38, 0.33, sz)), Color(0.03, 0.03, 0.03), 10)
			_scyl("metal", 0.17, 0.17, 0.26, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.38, 0.33, sz)), Color(0.5, 0.5, 0.52), 8)
	var hp := xf * Vector3(0, 0.8, -2.3)
	var head := SpotLight3D.new()
	head.transform = Transform3D(Basis.looking_at(Vector3(-2.0, 0.0, 0.6) - hp), hp)
	head.spot_angle = 30.0
	head.spot_angle_attenuation = 1.1
	head.spot_range = 13.0
	head.spot_attenuation = 0.6
	head.light_energy = 3.0
	head.light_color = Color(1.0, 0.95, 0.8)
	add_child(head)
	_add_perch("car hood", "car", Vector3(5.4, 0.95, 2.65), Vector3(4.15, 0.0, 2.65))


func _build_yard_lights() -> void:
	# Warm pools from the house: the patio lamp and the porch light (the floodlights are in _build_environment).
	var lamps: Array = [[Vector3(-1.8, 2.5, HOUSE_Z + 0.5), 7.5, 1.6, Color(1.0, 0.78, 0.5)],
		[Vector3(4.2, 2.8, HOUSE_Z + 0.5), 6.5, 1.3, Color(1.0, 0.8, 0.55)],
		[Vector3(-6.8, 2.2, 3.0), 5.5, 0.6, Color(0.7, 0.8, 1.0)]]
	for l: Array in lamps:
		var o := OmniLight3D.new()
		o.position = l[0]
		o.omni_range = l[1]
		o.light_energy = l[2]
		o.light_color = l[3]
		o.omni_attenuation = 1.4
		add_child(o)


func _hang(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)


func _build_string_lights() -> void:
	# Two zig-zag strands from the house eaves over the yard to poles just outside the side fences.
	var poles: Array[Vector3] = [Vector3(-7.85, 0, -5.0), Vector3(7.85, 0, -5.0), Vector3(-7.85, 0, -1.6), Vector3(7.85, 0, -1.6),
		Vector3(-7.85, 0, 2.6), Vector3(7.85, 0, 0.6)]
	for p in poles:
		_bx("wood", Vector3(0.12, 5.0, 0.12), p + Vector3(0, 2.5, 0), Color(0.42, 0.35, 0.28), 0.0, 2.0)
	var strand_a: Array[Vector3] = [Vector3(-6.5, 5.9, HOUSE_Z + 0.3), Vector3(7.85, 4.95, -5.0), Vector3(-7.85, 4.95, -1.6), Vector3(7.85, 4.95, 0.6)]
	var strand_b: Array[Vector3] = [Vector3(6.5, 5.9, HOUSE_Z + 0.3), Vector3(-7.85, 4.95, -5.0), Vector3(7.85, 4.95, -1.6), Vector3(-7.85, 4.95, 2.6)]
	# Mostly warm incandescent bulbs, a few muted old coloured ones.
	var cols: Array[Color] = [Color(0.95, 0.72, 0.42), Color(0.9, 0.66, 0.38), Color(0.95, 0.72, 0.42), Color(0.85, 0.6, 0.3),
		Color(0.75, 0.32, 0.22), Color(0.45, 0.62, 0.38), Color(0.42, 0.5, 0.72), Color(0.9, 0.55, 0.22)]
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
	sm.radius = 0.045
	sm.height = 0.09
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
	var s := randf_range(0.92, 1.06) * 0.85
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
	# Nobody stands in the fighting area (x -7..7, z -5..5): friends crowd the back of the patio,
	# the porch and its roof, peek over the side fences and hang out by the car.
	var x := -7.0
	while x < -0.8:
		if absf(x + 3.4) > 1.1 or randf() < 0.3:   # keep the sliding door visible
			_add_fan(Vector3(x, 0.015, randf_range(-5.7, -6.4)), _stand_variant(), 0.6)
		x += randf_range(0.7, 1.0)
	# Lawn chairs at the back of the patio (sitting, slightly in front of each chair)
	for c: Vector3 in [Vector3(-6.35, 0.015, -6.05), Vector3(-5.58, 0.015, -6.35), Vector3(-1.63, 0.015, -6.45)]:
		_add_fan(c, FAN_SIT if randf() < 0.5 else FAN_SIT_CUP, 0.6)
	# Porch: railing leaners (clear of the steps at x ~1.6) and couch sitters
	for rx: float in [2.9, 3.7, 4.6, 5.5, 0.4]:
		_add_fan(Vector3(rx, 1.0, -6.05), _stand_variant(), 0.65)
	for cx: float in [3.9, 4.6, 5.2]:
		_add_fan(Vector3(cx, 1.0, HOUSE_Z + 0.95), FAN_SIT if randf() < 0.5 else FAN_SIT_CUP, 0.55)
	# Up on the porch roof
	for rx: float in [0.6, 1.9, 3.3, 4.6, 5.6]:
		var v := FAN_SIT if rx > 4.0 else _stand_variant()
		_add_fan(Vector3(rx, 3.58, -6.4), v, 0.5, 1.4)
	# Peeking over the side fences (standing on buckets) and two sitting on the fence tops
	for z: float in [-7.4, -6.0, -3.9, -2.6, 2.4, 3.8]:
		_add_fan(Vector3(-FENCE_X - 0.45, 0.85, z + randf_range(-0.2, 0.2)), _stand_variant(), 0.42)
	for z: float in [-6.6, -4.6, -3.2, -0.6]:
		_add_fan(Vector3(FENCE_X + 0.45, 0.85, z + randf_range(-0.2, 0.2)), _stand_variant(), 0.42)
	_add_fan(Vector3(-FENCE_X, 1.6, -4.9), FAN_SIT, 0.45, 1.6)
	_add_fan(Vector3(FENCE_X, 1.6, -1.8), FAN_SIT_CUP, 0.45, 1.6)
	# By the car on the driveway, and two in the camera-side corners beyond the picket fence
	_add_fan(Vector3(8.3, 0.015, 4.7), FAN_CUP, 0.55)
	_add_fan(Vector3(9.4, 0.015, 0.7), FAN_PHONE, 0.5)
	_add_fan(Vector3(-8.6, 0, 6.6), FAN_PHONE, 0.6)
	_add_fan(Vector3(9.4, 0.015, 3.0), FAN_HOODIE, 0.55)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 1.7)
	var sh := Shader.new()
	sh.code = CROWD_SHADER
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = sh
	crowd_mat.set_shader_parameter("tex", _make_crowd_texture())
	crowd_mat.set_shader_parameter("hype", 0.0)
	crowd_mat.set_shader_parameter("brightness", 0.6)  # lit ~0.5 -> ~0.3: the yard stays dark, the ring reads brightest

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = _fan_xforms.size()
	var palette: Array[Color] = [Color(0.7, 0.24, 0.22), Color(0.26, 0.36, 0.66), Color(0.75, 0.66, 0.3), Color(0.78, 0.78, 0.75),
		Color(0.28, 0.52, 0.32), Color(0.45, 0.3, 0.6), Color(0.22, 0.22, 0.24), Color(0.72, 0.45, 0.2), Color(0.45, 0.45, 0.48),
		Color(0.33, 0.25, 0.19), Color(0.16, 0.26, 0.2)]
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
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	w.set("arena", self)   # yard bounds / perches / surface_at (yard_contract.md); null-safe on the wrestler side
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


## Ground impact: surface-coloured dust plus grass clumps (lawn) or grey grit (patio / drive).
func _fx_ground(where: Vector3, s: float) -> void:
	if fx == null:
		return
	var surf: String = surface_at(where)
	if where.y < 0.8:
		fx.ground_hit(where, s, surf)
	else:
		_fx_dust(where, s)   # high contact (fence, perch): plain dust, no flying clumps


## The wrestler a hit at `where` landed on: whichever is closest to the impact point.
func _fx_victim(where: Vector3) -> Node3D:
	if p1 == null or p2 == null:
		return null
	var d1: float = p1.global_position.distance_squared_to(where)
	var d2: float = p2.global_position.distance_squared_to(where)
	return p1 if d1 <= d2 else p2


## White body flash on the victim; a big hit on the player also pulses the red vignette.
func _fx_hit_body(where: Vector3, s: float) -> void:
	if fx == null:
		return
	var v: Node3D = _fx_victim(where)
	if v == null:
		return
	fx.body_flash(v)
	if s >= 0.6 and not v.is_cpu:
		fx.hurt(clampf(s, 0.6, 1.2))


func _on_sfx(w: Node3D, kind: String, s: float, where: Vector3) -> void:
	var st: float = clampf(s, 0.0, 1.5)
	if kind in ["punch", "kick", "thud", "thud_concrete", "big_thud", "chair_hit", "metal_hit", "wood_hit", "table_break"]:
		_fx_hit_body(where, st)
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
			# Launchers pop the victim into JUGGLED as this sfx fires: punch the FOV in.
			var launched: bool = int(w.get("state")) == Wrestler.S.JUGGLED
			_kick_cam(-4.0 if launched else -2.0, st * 0.6)
			_buzz(20)
			_hype(0.05)
		"thud":
			_snd("thud", -1.0 + 2.0 * st, 0.05)
			_hitstop(0.1)
			_fx_ground(where, st)
			_fx_spark(where + Vector3(0, 0.2, 0), st * 0.6)
			_kick_cam(-4.0, st)
			_buzz(45)
			_hype(0.15)
		"thud_concrete":
			# Slammed on the patio / driveway: harsher, louder, bigger reaction than the lawn.
			_snd("thud_concrete", 1.0 + 2.0 * clampf(st, 0.0, 1.0), 0.04)
			_snd("ooh", -9.0, 0.05)
			_hitstop(0.13)
			_fx_ground(where, maxf(st, 0.8))
			_fx_spark(where + Vector3(0, 0.15, 0), maxf(st, 0.7))
			_kick_cam(-5.0, maxf(st, 0.9))
			_buzz(60)
			_hype(0.2)
		"big_thud":
			_snd("big_thud", 2.0, 0.03)
			_snd("ooh", -6.0, 0.05)
			_hitstop(0.14)
			_fx_ground(where, maxf(st, 1.0))
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
		# ---- style system (scripts/style.gd)
		"trick":
			_snd("trick", -14.0 + 8.0 * clampf(st, 0.0, 1.0), 0.03)
		"combo_bank":
			_snd("combo_bank", -6.0 + 4.0 * clampf(st, 0.0, 1.0), 0.02)
			_hype(0.1 * st)
		"letter":
			_snd("letter", -3.0, 0.0)
			_kick_cam(-2.0, 0.1)
			_hype(0.2)
		"brawl_mode":
			_snd("brawl_mode", 1.0, 0.0)
			_hitstop(0.12)
			_slowmo()
			_fx_flash(1.0)
			_kick_cam(-8.0, 0.6)
			_buzz(90)
			_hype(0.7)
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

# AKI-era palette: flat, slightly muted console colors.
const HUD_GOLD := Color(1.0, 0.84, 0.25)
const HUD_INK := Color(0.04, 0.03, 0.06, 0.95)   # outlines and strokes
const HUD_HP_HIGH := Color(0.36, 0.82, 0.32)
const HUD_HP_MID := Color(0.95, 0.74, 0.18)
const HUD_HP_LOW := Color(0.9, 0.22, 0.16)
const HUD_SPIRIT := Color(0.32, 0.62, 0.95)
const HUD_PLATE_W := 300.0       # max width of one name plate
const HUD_NAME_FONT := 18
const HUD_HP_H := 9.0
const HUD_SP_H := 7.0
const HUD_ANNOUNCE_FONT := 34
const HUD_ANNOUNCE_SECS := 0.9

var hud_font: FontVariation
var hud_font_italic: FontVariation
var bar_canvas: Control
var hint_panel: PanelContainer
var hint_style: StyleBoxFlat
var hint_max_w := 760.0  # widest the hint text may get (set by _layout_hud)
const HINT_FONT := 21
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
	l.add_theme_color_override("font_outline_color", HUD_INK)
	l.add_theme_constant_override("outline_size", 8)
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
	sb.anti_aliasing = radius > 0
	return sb


func _hud_button(text: String, font_size: int, color: Color, radius: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_override("font", hud_font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 0.8))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", HUD_INK)
	btn.add_theme_constant_override("outline_size", 4)
	# Flat console button: solid face, 2 px dark outline, no shadow or gloss.
	var normal := _hud_box(color, HUD_INK, radius, 2)
	var pressed := _hud_box(color.lightened(0.2), HUD_INK, radius, 2)
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

	# Move-name callouts: bold italic console text with a 4 px dark outline.
	announce_label = _big_label(HUD_ANNOUNCE_FONT)
	announce_label.add_theme_font_override("font", hud_font_italic)
	announce_label.add_theme_color_override("font_color", HUD_GOLD)
	announce_label.add_theme_color_override("font_outline_color", HUD_INK)
	announce_label.add_theme_constant_override("outline_size", 8)
	hud.add_child(announce_label)

	# Pin count: big, flat white numeral with a dark outline.
	count_label = _big_label(150)
	count_label.add_theme_font_override("font", hud_font_italic)
	count_label.add_theme_constant_override("outline_size", 14)
	_place(count_label, 0.5, 0.5, Rect2(-220, -170, 440, 230))
	hud.add_child(count_label)

	# Context hint: flat translucent strip at the bottom center, between stick and buttons.
	hint_panel = PanelContainer.new()
	hint_style = _hud_box(Color(0.0, 0.0, 0.0, 0.5), HUD_INK, 0, 0)
	hint_style.content_margin_left = 16
	hint_style.content_margin_right = 16
	hint_style.content_margin_top = 3
	hint_style.content_margin_bottom = 5
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.visible = false
	hud.add_child(hint_panel)
	hint_label = _big_label(HINT_FONT)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_constant_override("outline_size", 4)
	hint_label.add_theme_constant_override("line_spacing", 0)
	hint_panel.add_child(hint_label)

	# "?" button toggles the HOW TO PLAY panel (the match keeps running).
	help_button = _hud_button("?", 26, Color(0.12, 0.12, 0.16, 0.6), 4)
	help_button.pressed.connect(_toggle_help)
	hud.add_child(help_button)
	help_panel = _build_help_panel()
	hud.add_child(help_panel)

	_build_win_panel()

	touch.connect("layout_changed", _layout_hud)
	_layout_hud()


func _build_help_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := _hud_box(Color(0.03, 0.03, 0.06, 0.9), Color(0.55, 0.55, 0.6), 2, 2)
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
	var title := _big_label(28)
	title.text = "CITY 2 CITY WRESTLING — HOW TO PLAY"
	title.add_theme_font_override("font", hud_font_italic)
	title.add_theme_color_override("font_color", HUD_GOLD)
	title.add_theme_constant_override("outline_size", 6)
	col.add_child(title)

	# Three columns of sections: [header, rows, first_row_is_column_header].
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
	var third: Array = [
		["WEAPONS & TABLES", [
			["GRAB", "Pick up a chair, can or 2x4"],
			["HOLDING", "STRIKE: Swing  PIN: Throw  GRAB: Drop"],
			["RUN+STRIKE", "Running swing"],
			["TABLE", "GRAB by the folded table: set it up"],
			["", "GRAB a downed foe by it: lay him on"],
			["", "STRIKE: send him THROUGH it!"],
		], false],
		["HIGH FLYING", [
			["RUN", "At a corner: climb the turnbuckle"],
			["ON TOP", "STRIKE: Dive  GRAB: Hop  RUN: Down"],
			["FOE DOWN", "Backyard Splash  (STICK toward)"],
			["", "STICK away: Moonsault"],
			["", "STICK sideways: Flying Elbow"],
			["FOE UP", "Crossbody  /  STICK: Missile Dropkick"],
			["SPECIAL", "Gutter Star Press (foe down)"],
			["ROPES", "STRIKE off a bounce: Springboard"],
			["CORNER", "Whip him in, RUN+STRIKE: Splash"],
			["", "or GRAB: Super Drop"],
		], false],
	]
	var columns := HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_theme_constant_override("separation", 28)
	col.add_child(columns)
	for side in [left, right, third]:
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
			head.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95))
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
	dim.color = Color(0, 0, 0, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.add_child(dim)

	# Classic flat banner: a straight full-width strip with thin rules top and bottom.
	win_banner = Panel.new()
	win_banner.anchor_left = 0.0
	win_banner.anchor_right = 1.0
	win_banner.anchor_top = 0.5
	win_banner.anchor_bottom = 0.5
	win_banner.offset_left = 0
	win_banner.offset_right = 0
	win_banner.offset_top = -150
	win_banner.offset_bottom = -10
	win_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _hud_box(Color(0.06, 0.06, 0.1, 0.88), Color(0.85, 0.85, 0.9, 0.9), 0, 0)
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	win_banner.add_theme_stylebox_override("panel", sb)
	win_panel.add_child(win_banner)

	win_header = _big_label(26)
	win_header.add_theme_font_override("font", hud_font_italic)
	win_header.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_header.offset_top = 12
	win_header.offset_bottom = -94
	win_header.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	win_header.add_theme_constant_override("outline_size", 6)
	win_banner.add_child(win_header)

	win_label = _big_label(64)
	win_label.add_theme_font_override("font", hud_font_italic)
	win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_label.offset_top = 40
	win_label.offset_bottom = -8
	win_label.add_theme_constant_override("outline_size", 10)
	win_banner.add_child(win_label)

	win_button = _hud_button("REMATCH", 36, Color(0.72, 0.14, 0.14), 4)
	_place(win_button, 0.5, 0.5, Rect2(-150, 40, 300, 80))
	win_button.pressed.connect(_restart)
	win_panel.add_child(win_button)


func _layout_hud() -> void:
	var sr := _hud_safe_rect()
	# Announcer sits just below the bars; hint panel at the bottom center above the
	# safe-area bottom; "?" button at the top center between the two bars.
	# Move names pop up at ~22% of the screen height, well clear of the name plates.
	var ann_y := maxf(sr.position.y + 80.0, get_viewport().get_visible_rect().size.y * 0.22)
	_place(announce_label, 0.5, 0.0, Rect2(-520, ann_y - 30.0, 1040, 60))
	# The hint is centered in the free band between the stick and the button cluster
	# and wraps (see _fit_hint) so it never sits under either.
	var band := Vector2(sr.position.x + 220.0, sr.end.x - 260.0)
	if touch != null:
		band = touch.free_band()
	hint_max_w = maxf(320.0, band.y - band.x) - hint_style.content_margin_left - hint_style.content_margin_right
	var hint_y := -(get_viewport().get_visible_rect().size.y - sr.end.y) - 12
	_place(hint_panel, 0.0, 1.0, Rect2((band.x + band.y) * 0.5, hint_y, 0, 0))
	_fit_hint()
	_place(help_button, 0.5, 0.0, Rect2(-22, sr.position.y + 12, 44, 44))
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
	# Simple console-style pop: a quick ease-out, no overshoot.
	tw.tween_property(c, "scale", Vector2.ONE, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", 0.0, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


func _announce(text: String, secs: float) -> void:
	if match_over and text != "":
		return
	announce_label.text = text
	# Move names flash by quickly; longer calls (e.g. "FIGHT!") keep their own time.
	announce_timer = secs if secs > 1.3 else HUD_ANNOUNCE_SECS
	if text == "":
		return
	var up := text.to_upper()
	var col := Color(1.0, 0.92, 0.45)
	if up.contains("REVERSAL") or up.contains("KICK"):
		col = Color(0.6, 0.9, 1.0)
	elif up.contains("!!") or up.contains("FIGHT"):
		col = Color(1.0, 0.62, 0.25)
	announce_label.add_theme_color_override("font_color", col)
	announce_label.add_theme_color_override("font_outline_color", HUD_INK)
	announce_label.modulate.a = 1.0
	if announce_tween != null and announce_tween.is_valid():
		announce_tween.kill()
	announce_tween = _pop(announce_label, 1.25, 0.0, 0.12)


func _on_pin_count(c: int) -> void:
	count_label.text = str(c) + ("!" if c >= 3 else "")
	# Flat white numeral with a dark outline (the winning "3!" in gold).
	count_label.add_theme_color_override("font_color", HUD_GOLD if c >= 3 else Color.WHITE)
	count_label.add_theme_color_override("font_outline_color", HUD_INK)
	count_label.modulate.a = 1.0
	count_timer = 0.7 if c < 3 else 2.5
	cam_shake = max(cam_shake, 0.25)
	# Quick, simple scale-in.
	if count_tween != null and count_tween.is_valid():
		count_tween.kill()
	count_label.rotation = 0.0
	count_tween = _pop(count_label, 1.5, 0.0, 0.1)


func _on_win(w: Node3D) -> void:
	match_over = true
	announce_label.text = ""
	var nm: String = w.display_name
	var cpu: bool = w.is_cpu
	var gear: Color = w.gear_color
	win_label.text = "%s WINS!" % nm
	win_label.add_theme_color_override("font_color", gear.lightened(0.5))
	win_header.text = "DEFEAT..." if cpu else "WINNER"
	var sb := win_banner.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		var bg := gear.darkened(0.7).lerp(Color(0.06, 0.06, 0.08), 0.5)
		sb.bg_color = Color(bg.r, bg.g, bg.b, 0.9)
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
	tw.tween_property(win_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop(win_label, 1.3, 0.0, 0.2)
	win_button.modulate.a = 0.0
	var tb := create_tween()
	tb.tween_interval(0.35)
	tb.tween_property(win_button, "modulate:a", 1.0, 0.2)


# ---- AKI-era name plates (drawn on bar_canvas): small italic name, thin flat meters

func _flat_strip(x0: float, dir: float, u0: float, u1: float, y: float, h: float, col: Color) -> void:
	# Flat rectangle measured along "u" from the outer screen edge x0 (dir = +1 left side, -1 right).
	if u1 - u0 < 0.5:
		return
	var x := (x0 + u0) if dir > 0.0 else (x0 - u1)
	bar_canvas.draw_rect(Rect2(x, y, u1 - u0, h), col)


func _text_u(x0: float, dir: float, u: float, width: float, y: float, text: String, size: int, col: Color, font: Font, outline: int) -> void:
	# Draw text starting at distance u from the outer edge (left- or right-aligned to match).
	var pos := Vector2(x0 + u, y) if dir > 0.0 else Vector2(x0 - u - width, y)
	var align := HORIZONTAL_ALIGNMENT_LEFT if dir > 0.0 else HORIZONTAL_ALIGNMENT_RIGHT
	if outline > 0:
		bar_canvas.draw_string_outline(font, pos, text, align, width, size, outline, HUD_INK)
	bar_canvas.draw_string(font, pos, text, align, width, size, col)


## Largest font size <= size (down to 12) at which text fits in width.
func _fit_font_size(font: Font, text: String, size: int, width: float) -> int:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w <= width or w <= 0.0:
		return size
	return maxi(12, int(floor(float(size) * width / w)))


func _draw_hud_bars() -> void:
	var sr := _hud_safe_rect()
	var gap := 90.0  # room for the "?" button
	var side_w: float = clampf((sr.size.x - gap) * 0.5 - 20.0, 180.0, HUD_PLATE_W)
	for w in [p1, p2]:
		var d: Dictionary = bars[w]
		_draw_player_bar(w, d, sr, side_w)


func _draw_player_bar(w: Node3D, d: Dictionary, sr: Rect2, side_w: float) -> void:
	var right: bool = d["right"]
	var dir := -1.0 if right else 1.0
	var x0 := (sr.end.x - 16.0) if right else (sr.position.x + 16.0)
	var top := sr.position.y + 12.0
	var gear: Color = w.gear_color
	var nm: String = w.display_name
	var cpu: bool = w.is_cpu
	var hp: float = d["hp"]
	var chip: float = d["chip"]
	var sp: float = d["sp"]
	var flash: float = d["flash"]
	var special: bool = w.is_special_ready()
	var blink := int(hud_clock * 4.0) % 2 == 0

	# Name line: small italic name (gear tint), tiny 1P/CPU tag at the inner end.
	var tag := "CPU" if cpu else "1P"
	var tag_w: float = hud_font_italic.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4.0
	var name_w := side_w - tag_w - 10.0
	var name_col := gear.lightened(0.55)
	_text_u(x0, dir, 0.0, name_w, top + 17.0, nm, _fit_font_size(hud_font_italic, nm, HUD_NAME_FONT, name_w), name_col, hud_font_italic, 4)
	_text_u(x0, dir, side_w - tag_w, tag_w, top + 16.0, tag, 14, Color(0.82, 0.82, 0.86) if cpu else HUD_GOLD, hud_font_italic, 4)

	# Health strip: 2 px dark outline, flat dark well, subtle damage chip, flat fill.
	var hy := top + 24.0
	var hh := HUD_HP_H
	_flat_strip(x0, dir, -2.0, side_w + 2.0, hy - 2.0, hh + 4.0, HUD_INK)
	_flat_strip(x0, dir, 0.0, side_w, hy, hh, Color(0.13, 0.1, 0.12, 0.92))
	var chip_u := side_w * clampf(chip / 100.0, 0.0, 1.0)
	_flat_strip(x0, dir, 0.0, chip_u, hy, hh, Color(0.85, 0.72, 0.62, 0.55))
	var hcol := HUD_HP_HIGH
	if hp < 30.0:
		hcol = HUD_HP_LOW
		if hp < 20.0 and blink:
			hcol = hcol.lightened(0.25)
	elif hp < 60.0:
		hcol = HUD_HP_MID
	var hp_u := side_w * clampf(hp / 100.0, 0.0, 1.0)
	_flat_strip(x0, dir, 0.0, hp_u, hy, hh, hcol)
	if flash > 0.0:
		_flat_strip(x0, dir, 0.0, side_w, hy, hh, Color(1, 1, 1, 0.22 * flash))

	# Spirit meter: same flat style, a touch thinner.
	var sy := hy + hh + 4.0
	var sh := HUD_SP_H
	_flat_strip(x0, dir, -2.0, side_w + 2.0, sy - 2.0, sh + 4.0, HUD_INK)
	_flat_strip(x0, dir, 0.0, side_w, sy, sh, Color(0.08, 0.09, 0.14, 0.92))
	var scol := HUD_SPIRIT
	if special:
		scol = HUD_GOLD if blink else Color(1.0, 0.97, 0.85)
	_flat_strip(x0, dir, 0.0, side_w * clampf(sp / 100.0, 0.0, 1.0), sy, sh, scol)

	# Full meter: flashing "SPECIAL" tag under the meter.
	if special and blink:
		_text_u(x0, dir, 0.0, side_w, sy + sh + 18.0, "SPECIAL", 17, HUD_GOLD, hud_font_italic, 4)


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


# ---- context helpers for hints and button labels (weapons / tables / high flying)
# These mirror the checks in wrestler.gd ("# ---- weapons", "# ---- high flying").

const HUD_CORNER_POST := 4.15     # corner posts at local (±4.15, ±4.15)
const HUD_CLIMB_RANGE := 1.1      # wrestler.gd HF_CLIMB_RANGE
const HUD_SPRING_WINDOW := 0.35   # wrestler.gd HF_SPRING_WINDOW


func _p_dist() -> float:
	var a: Vector3 = p1.position
	var b: Vector3 = p2.position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _hud_holding() -> bool:
	var it = p1.held_item
	return it != null and is_instance_valid(it)


func _hud_item_name(kind: String) -> String:
	match kind:
		"chair":
			return "the steel chair"
		"trash_can":
			return "the trash can"
		"plank":
			return "the 2x4"
	return "it"


## What GRAB would do with the props for p1 right now (IDLE / WALK, empty-handed):
## "on_table" (put the downed opponent on a standing table), "pick_up:<kind>",
## "table" (set up the folded table) or "".
func _hud_item_context() -> String:
	var mgr = p1.items
	if mgr == null or not is_instance_valid(mgr) or _hud_holding():
		return ""
	var opp: int = p2.state
	var dist := _p_dist()
	var a: Vector3 = p1.position
	var b: Vector3 = p2.position
	if opp == Wrestler.S.DOWN and dist < 1.8:
		var t: Node3D = mgr.table_under(b, 2.6)
		if t != null:
			return "on_table"
	var opp_up: bool = p2.is_standing()
	if opp_up and dist < 1.5:
		return ""  # GRAB means a lock-up here
	var it: Node3D = mgr.nearest_item(a, 1.3)
	if it != null:
		var ip: Vector3 = it.position
		var idist := Vector2(ip.x - a.x, ip.z - a.z).length()
		if not (opp == Wrestler.S.DOWN and dist < 1.6 and dist < idist):
			var k: String = it.get("kind")
			return "pick_up:" + k
	if mgr.has_method("nearest_folded_table"):
		var ft: Node3D = mgr.nearest_folded_table(a, 1.5)
		if ft != null:
			return "table"
	return ""


## True when RUN would climb the nearest turnbuckle (within range, opponent not in that corner).
func _hud_can_climb() -> bool:
	var a: Vector3 = p1.position
	var sx := -1.0 if a.x < 0.0 else 1.0
	var sz := -1.0 if a.z < 0.0 else 1.0
	var post := Vector2(sx * HUD_CORNER_POST, sz * HUD_CORNER_POST)
	if post.distance_to(Vector2(a.x, a.z)) > HUD_CLIMB_RANGE:
		return false
	var b: Vector3 = p2.position
	return post.distance_to(Vector2(b.x, b.z)) >= 1.2


## True inside the springboard window right after p1 bounces off the ropes.
func _hud_spring_ready() -> bool:
	var whipped: bool = p1.whipped
	var clock: float = p1.anim_clock
	var rope_at: float = p1.hf_rope_at
	return not whipped and clock - rope_at <= HUD_SPRING_WINDOW and p2.state != Wrestler.S.DOWN


func _hint_text() -> String:
	var st: int = p1.state
	var opp: int = p2.state
	var special: bool = p1.is_special_ready()
	var lockout: float = p1.reversal_lockout
	var dist := _p_dist()
	var near := dist < 1.7
	if _show_reverse():
		return "REVERSE!  Tap GRAB or STRIKE NOW!"
	if st == Wrestler.S.TIEUP_ATK:
		var strong: bool = p1.tie_strong
		if strong:
			var fin_s := "THUNDER DRIVER!" if special else "Neckbreaker"
			return "STRONG LOCK-UP!   RUN: Irish Whip (aim at a corner!)\nSTRIKE: Tombstone   STICK+STRIKE: Powerbomb\nGRAB: Spinebuster   STICK+GRAB: " + fin_s
		var fin := "THUNDER DRIVER!" if special else "DDT"
		return "LOCK-UP!   RUN: Irish Whip (aim at a corner!)\nSTRIKE: Knee   STICK+STRIKE: Suplex\nGRAB: Slam   STICK+GRAB: " + fin
	if st == Wrestler.S.TIEUP_DEF:
		if lockout > 0.0:
			return "TOO EARLY!  Wait for the move..."
		return "CAUGHT!  Tap GRAB or STRIKE when the \"!\" appears to reverse"
	if st == Wrestler.S.PINNED:
		return "MASH ANY BUTTON TO KICK OUT!"
	if st == Wrestler.S.PERCHED:
		if opp == Wrestler.S.DOWN or opp == Wrestler.S.ON_TABLE:
			if special:
				return "DIVE!  SPECIAL: GUTTER STAR PRESS!!!"
			return "DIVE!  Stick picks the move\nToward: Splash   Away: Moonsault   Side: Elbow"
		return "DIVE!  STRIKE: Crossbody   STICK+STRIKE: Missile Dropkick\nGRAB: Hop down   RUN: Climb down"
	if st == Wrestler.S.CLIMB:
		return "Climbing the turnbuckle..."
	if st == Wrestler.S.ON_TABLE:
		return "Uh oh... you're laid out on the table!"
	if st == Wrestler.S.CORNER_STUN:
		return "Stuck in the corner!"
	if st == Wrestler.S.GRAB_WINDUP:
		return "Keep holding GRAB for a STRONG lock-up..."
	if st == Wrestler.S.WHIPPING:
		return "Here he comes!  STRIKE: Clothesline\nGRAB: Back Body Drop   STICK+GRAB: Powerslam"
	if st == Wrestler.S.RUN:
		if _hud_holding():
			return "STRIKE: Running swing!      RUN: Stop"
		if opp == Wrestler.S.ON_TABLE:
			return "STRIKE: Leap through the table!"
		if opp == Wrestler.S.CORNER_STUN:
			return "STRIKE: Corner Splash!"
		if opp == Wrestler.S.DOWN:
			return "STRIKE: Elbow Drop      GRAB: Knee Drop"
		return "STRIKE: Clothesline   (right off the ropes: Springboard!)"
	var free := st == Wrestler.S.IDLE or st == Wrestler.S.WALK
	if free and _hud_holding():
		if opp == Wrestler.S.DOWN and dist < 2.0:
			return "STRIKE: Swing at him   PIN: Cover   GRAB: Drop"
		return "STRIKE: Swing   PIN: Throw it   GRAB: Drop\nRUN, then STRIKE: Running swing"
	if free and opp == Wrestler.S.ON_TABLE and dist < 2.2:
		return "SMASH them through it!  Press STRIKE"
	if free and opp == Wrestler.S.CORNER_STUN:
		return "He's stuck in the corner!\nRUN, then STRIKE: Corner Splash   GRAB (close): SUPER DROP"
	var ctx := _hud_item_context() if free else ""
	if ctx == "on_table":
		return "Table's set!  GRAB: Put him on it   PIN: Cover"
	if opp == Wrestler.S.DOWN:
		if free and _hud_can_climb():
			return "He's down!  RUN: Climb the turnbuckle and fly!"
		if near:
			return "STRIKE: Stomp   GRAB: Pick up   PIN: Cover"
		return "He's down!  Get close and PIN, climb a corner, or TAUNT"
	if ctx.begins_with("pick_up:"):
		return "GRAB: Pick up %s" % _hud_item_name(ctx.substr(8))
	if ctx == "table":
		return "GRAB: Set up the table"
	if free and _hud_can_climb():
		return "RUN: Climb the turnbuckle"
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
	var dist := _p_dist()
	var near := dist < 1.7
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
	elif st == Wrestler.S.PERCHED:
		touch.set_labels("DIVE!", "HOP", "DOWN", "")
		glow = "strike"
	elif st == Wrestler.S.CLIMB or st == Wrestler.S.DIVING or st == Wrestler.S.PERCH_FALL \
			or st == Wrestler.S.ON_TABLE or st == Wrestler.S.CORNER_STUN:
		touch.set_labels("", "", "", "")
		glow = ""
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
		if _hud_holding():
			touch.set_labels("SWING", "STOP", "STOP", "")
		elif opp == Wrestler.S.ON_TABLE and dist < 2.6:
			touch.set_labels("SMASH!", "KNEE", "STOP", "")
			glow = "strike"
		elif opp == Wrestler.S.CORNER_STUN and dist < 3.4:
			touch.set_labels("SPLASH", "STOP", "STOP", "")
			glow = "strike"
		elif _hud_spring_ready():
			touch.set_labels("SPRING", "STOP", "STOP", "")
			glow = "strike"
		elif opp == Wrestler.S.DOWN:
			touch.set_labels("ELBOW", "KNEE", "STOP", "")
		else:
			touch.set_labels("LARIAT", "STOP", "STOP", "")
	else:
		var free := st == Wrestler.S.IDLE or st == Wrestler.S.WALK
		var cd: float = p1.taunt_cooldown
		var s_lbl := "PUNCH"
		var g_lbl := "GRAB"
		var r_lbl := "RUN"
		var p_lbl := "PIN" if opp == Wrestler.S.DOWN else ("TAUNT" if cd <= 0.0 else "")
		if opp == Wrestler.S.DOWN and not special:
			glow = "pin"
		if opp == Wrestler.S.DOWN and near:
			s_lbl = "STOMP"
			g_lbl = "LIFT"
		if free and _hud_can_climb():
			r_lbl = "CLIMB"
		if free and _hud_holding():
			s_lbl = "SWING"
			g_lbl = "DROP"
			p_lbl = "PIN" if (opp == Wrestler.S.DOWN and dist < 2.0) else "THROW"
		elif free and opp == Wrestler.S.ON_TABLE and dist < 2.2:
			s_lbl = "SMASH!"
			glow = "strike"
		elif free and opp == Wrestler.S.CORNER_STUN:
			r_lbl = "SPLASH"
			if dist < 1.6:
				g_lbl = "SUPER"
				glow = "grapple"
		elif free:
			var ctx := _hud_item_context()
			if ctx == "on_table":
				g_lbl = "ON TABLE"
				glow = "grapple"
			elif ctx.begins_with("pick_up:"):
				g_lbl = "PICK UP"
			elif ctx == "table":
				g_lbl = "TABLE"
		touch.set_labels(s_lbl, g_lbl, r_lbl, p_lbl)
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
	# Keep the shot inside the yard: the target never drifts toward the house or past the fences,
	# and stays low enough that the perches (up to the 2.4 m shed roof) remain in frame.
	mid.x = clampf(mid.x, yard_bounds.position.x + 2.0, yard_bounds.end.x - 2.0)
	mid.z = clampf(mid.z, yard_bounds.position.y + 1.0, yard_bounds.end.y - 1.5)
	mid.y = clampf(mid.y, 0.0, 1.3)
	cam_target = cam_target.lerp(mid, clampf(delta * 4.0, 0.0, 1.0))
	# AKI-style framing: higher and further back (~30 deg pitch), wrestlers ~1/3 of screen height.
	var want := cam_target + Vector3(0, 3.3 + spread * 0.3, 6.8 + spread * 0.6)
	camera.position = camera.position.lerp(want, clampf(delta * 3.0, 0.0, 1.0))
	camera.look_at(cam_target + Vector3(0, 0.9, 0))
	cam_fov_kick = lerpf(cam_fov_kick, 0.0, clampf(delta * 5.0, 0.0, 1.0))
	if absf(cam_fov_kick) < 0.01:
		cam_fov_kick = 0.0
	camera.fov = clampf(45.0 + cam_fov_kick, 15.0, 90.0)
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
		announce_label.modulate.a = clamp(announce_timer * 6.0, 0.0, 1.0)
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
		# The strip re-sizes around the text by itself (zero offsets + grow); a quick fade-in.
		if hint != "":
			hint_panel.modulate.a = 0.0
			create_tween().tween_property(hint_panel, "modulate:a", 1.0, 0.12)
	if hint_panel.visible:
		# Flat strip; it flashes dark red while the player must mash / wait.
		var st: int = p1.state
		var bg := Color(0.0, 0.0, 0.0, 0.5)
		if (st == Wrestler.S.PINNED or st == Wrestler.S.TIEUP_DEF) and int(hud_clock * 8.0) % 2 == 0:
			bg = Color(0.45, 0.04, 0.04, 0.6)
		hint_style.bg_color = bg
	_update_touch_labels()

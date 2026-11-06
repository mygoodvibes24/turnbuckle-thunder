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
	# Each look: colors + style switches used by wrestler.gd's N64-style model.
	var brick := {
		"gear": Color(0.85, 0.12, 0.12), "trunks": Color(0.08, 0.08, 0.1), "boot_color": Color(0.1, 0.1, 0.12),
		"skin": Color(0.87, 0.64, 0.47), "hair": "flattop", "hair_color": Color(0.18, 0.12, 0.08),
		"trunk_pattern": "bricks", "initials": "BM", "stubble": true, "boot_trim": Color(0.85, 0.12, 0.12),
		"elbow_pads": false, "wrist_tape": true,
	}
	var volcano := {
		"gear": Color(1.0, 0.5, 0.1), "trunks": Color(0.12, 0.3, 0.85), "boot_color": Color(0.12, 0.3, 0.85),
		"skin": Color(0.6, 0.42, 0.3), "tights": true, "mask": true,
		"mask_color": Color(0.12, 0.3, 0.85), "mask_trim": Color(1.0, 0.55, 0.1), "hair_color": Color.BLACK,
		"trunk_pattern": "flames", "tights_pattern": "flames", "boot_trim": Color(1.0, 0.5, 0.1),
		"elbow_pads": true, "wrist_tape": true,
	}
	p1 = _spawn("BRICK MASON", brick, false, Vector3(-1.8, 0, 0.3))
	p2 = _spawn("THE VOLCANO", volcano, true, Vector3(1.8, 0, -0.3))
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
var ring_spot: SpotLight3D
var crowd_mat: ShaderMaterial
var crowd_hype_shown := 0.0
var crowd_spots := PackedVector3Array()
var flash_nodes: Array[MeshInstance3D] = []
var flash_timers := PackedFloat32Array()

const CROWD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_linear;
uniform float hype = 0.0;
uniform float brightness = 0.5;

varying vec3 shirt;

float h1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float ph = h1(id) * 6.2831;
	float spd = mix(2.5, 10.0, hype) * (0.8 + 0.4 * h1(id + 3.1));
	float amp = mix(0.025, 0.3, hype) * (0.5 + h1(id + 7.7));
	float top = 1.0 - UV.y;
	VERTEX.y += max(0.0, sin(TIME * spd + ph)) * amp;
	VERTEX.x += sin(TIME * 1.7 + ph) * 0.04 * top;
	shirt = COLOR.rgb;
	float variant = floor(h1(id + 1.7) * 3.999);
	UV.x = (UV.x + variant) * 0.25;
}

void fragment() {
	vec4 t = texture(tex, UV);
	float m = smoothstep(0.8, 0.97, min(t.r, min(t.g, t.b)));
	vec3 c = mix(t.rgb, t.rgb * shirt, m);
	ALBEDO = c * (brightness + hype * 0.3);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
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


func _cyl(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 8
	mi.mesh = c
	mi.position = pos
	mi.material_override = _mat(color)
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


func _make_canvas_texture() -> ImageTexture:
	# Light grey-blue canvas with a darker border band and a little blotchy wear.
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var base := Color(0.74, 0.79, 0.88)
	var band := Color(0.16, 0.24, 0.62)
	for y in n:
		for x in n:
			var edge: int = mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var c := base
			if edge < 5:
				c = band
			elif edge == 6:
				c = Color(0.92, 0.94, 1.0)
			var j := randf_range(-0.035, 0.035)
			img.set_pixel(x, y, Color(c.r + j, c.g + j, c.b + j))
	return ImageTexture.create_from_image(img)


func _make_logo_texture() -> ImageTexture:
	# 32x32 center-ring logo: yellow disc, red rim, red lightning bolt.
	var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0.8, 0.2, 0))
	var ctr := Vector2(15.5, 15.5)
	for y in 32:
		for x in 32:
			var d := Vector2(x, y).distance_to(ctr)
			if d > 15.5:
				continue
			var c := Color(1.0, 0.82, 0.15)
			if d > 13.0:
				c = Color(0.85, 0.1, 0.1)
			elif d > 12.0:
				c = Color(0.1, 0.08, 0.15)
			img.set_pixel(x, y, c)
	var bolt := Color(0.85, 0.1, 0.12)
	for y in range(5, 17):
		var cx := int(19.0 - (y - 5) * 0.55)
		_px_rect(img, cx - 2, y, 4, 1, bolt)
	_px_rect(img, 10, 15, 11, 2, bolt)
	for y in range(17, 28):
		var cx2 := int(18.0 - (y - 17) * 0.55)
		_px_rect(img, cx2 - 2, y, 4, 1, bolt)
	return ImageTexture.create_from_image(img)


func _make_crowd_texture() -> ImageTexture:
	# 64x32 atlas: four 16x32 pixel fans. Pure-white pixels are the shirt, tinted per instance.
	var img := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 0.5, 0))
	var white := Color(1, 1, 1)
	var skins: Array[Color] = [Color(0.93, 0.74, 0.58), Color(0.55, 0.36, 0.24), Color(0.8, 0.6, 0.45), Color(0.38, 0.25, 0.17)]
	var hairs: Array[Color] = [Color(0.25, 0.16, 0.08), Color(0.05, 0.05, 0.05), Color(0.75, 0.6, 0.2), Color(0.1, 0.07, 0.05)]
	var pants: Array[Color] = [Color(0.15, 0.2, 0.45), Color(0.12, 0.12, 0.14), Color(0.3, 0.25, 0.2), Color(0.2, 0.3, 0.55)]
	for v in 4:
		var ox := v * 16
		var skin: Color = skins[v]
		var hair: Color = hairs[v]
		# legs + hips
		_px_rect(img, ox + 4, 23, 8, 2, pants[v])
		_px_rect(img, ox + 4, 25, 3, 7, pants[v])
		_px_rect(img, ox + 9, 25, 3, 7, pants[v])
		# shirt
		_px_rect(img, ox + 3, 11, 10, 12, white)
		# neck + head
		_px_rect(img, ox + 7, 10, 2, 1, skin)
		_px_rect(img, ox + 5, 3, 6, 7, skin)
		_px_rect(img, ox + 5, 2, 6, 2, hair)
		_px_rect(img, ox + 5, 4, 1, 2, hair)
		_px_rect(img, ox + 10, 4, 1, 2, hair)
		img.set_pixel(ox + 6, 6, Color(0.08, 0.05, 0.05))
		img.set_pixel(ox + 9, 6, Color(0.08, 0.05, 0.05))
		_px_rect(img, ox + 7, 8, 2, 1, skin.darkened(0.45))
		match v:
			0:  # arms down
				_px_rect(img, ox + 1, 12, 2, 3, white)
				_px_rect(img, ox + 1, 15, 2, 6, skin)
				_px_rect(img, ox + 13, 12, 2, 3, white)
				_px_rect(img, ox + 13, 15, 2, 6, skin)
			1:  # both arms up, cheering
				_px_rect(img, ox + 1, 1, 2, 10, skin)
				_px_rect(img, ox + 13, 1, 2, 10, skin)
				_px_rect(img, ox + 1, 10, 2, 2, white)
				_px_rect(img, ox + 13, 10, 2, 2, white)
			2:  # one fist up, holding a little sign
				_px_rect(img, ox + 0, 0, 6, 3, Color(1.0, 0.95, 0.55))
				_px_rect(img, ox + 1, 1, 4, 1, Color(0.8, 0.1, 0.1))
				_px_rect(img, ox + 2, 3, 2, 8, skin)
				_px_rect(img, ox + 13, 12, 2, 3, white)
				_px_rect(img, ox + 13, 15, 2, 6, skin)
			_:  # ball cap, arms down
				_px_rect(img, ox + 4, 1, 8, 2, Color(0.85, 0.15, 0.15))
				_px_rect(img, ox + 9, 3, 4, 1, Color(0.6, 0.08, 0.08))
				_px_rect(img, ox + 1, 12, 2, 3, white)
				_px_rect(img, ox + 1, 15, 2, 6, skin)
				_px_rect(img, ox + 13, 12, 2, 3, white)
				_px_rect(img, ox + 13, 15, 2, 6, skin)
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


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.015, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.75)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.13, 0.06, 0.2)
	env.fog_light_energy = 1.0
	env.fog_density = 0.03
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Soft cool key from the camera side so faces read; no shadows (cheap).
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38, 8, 0)
	fill.light_energy = 0.5
	fill.light_color = Color(0.75, 0.8, 1.0)
	add_child(fill)

	# The big warm spotlight over the ring: makes the canvas the brightest thing on screen.
	ring_spot = SpotLight3D.new()
	ring_spot.position = Vector3(0, 9.0, 0)
	ring_spot.rotation_degrees = Vector3(-90, 0, 0)
	ring_spot.spot_angle = 35.0
	ring_spot.spot_angle_attenuation = 0.8
	ring_spot.spot_range = 16.0
	ring_spot.spot_attenuation = 0.5
	ring_spot.light_energy = 4.0
	ring_spot.light_color = Color(1.0, 0.92, 0.78)
	ring_spot.shadow_enabled = true
	add_child(ring_spot)

	# Colored rim lights from behind the far corners.
	var rims: Array[Vector3] = [Vector3(-5.5, 4.5, -5.5), Vector3(5.5, 4.5, -5.5)]
	var rim_cols: Array[Color] = [Color(1.0, 0.25, 0.8), Color(0.2, 0.8, 1.0)]
	for i in rims.size():
		var o := OmniLight3D.new()
		o.position = rims[i]
		o.omni_range = 10.0
		o.light_energy = 2.0
		o.light_color = rim_cols[i]
		add_child(o)

	camera = Camera3D.new()
	camera.fov = 40
	camera.position = Vector3(0, 4.3, 7.5)
	add_child(camera)
	camera.look_at(Vector3(0, RING_TOP + 1.6, 0))


func _build_arena() -> void:
	# Arena floor + padded mats around the ring
	_box(Vector3(80, 0.1, 80), Vector3(0, -0.05, 0), Color(0.07, 0.05, 0.1))
	_box(Vector3(14.2, 0.03, 14.2), Vector3(0, 0.015, 0), Color(0.12, 0.13, 0.3))

	# ---- Ring
	_box(Vector3(8.8, 0.89, 8.8), Vector3(0, 0.445, 0), Color(0.05, 0.05, 0.08))   # skirt
	_box(Vector3(8.82, 0.08, 8.82), Vector3(0, 0.2, 0), Color(0.85, 0.12, 0.15))     # skirt stripe
	_box(Vector3(8.7, 0.1, 8.7), Vector3(0, 0.94, 0), Color(0.9, 0.9, 0.95))        # apron edge, top 0.99
	_plane(Vector2(7.9, 7.9), Vector3(0, RING_TOP, 0), _tex_mat(_make_canvas_texture()))  # canvas, top 1.00
	_plane(Vector2(2.4, 2.4), Vector3(0, RING_TOP + 0.01, 0), _tex_mat(_make_logo_texture(), true))  # logo

	var h := 4.15
	var heights: Array[float] = [0.45, 0.85, 1.25]
	var corners: Array[Vector2] = [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]
	var pad_cols: Array[Color] = [Color(0.9, 0.12, 0.12), Color(0.95, 0.85, 0.15), Color(0.95, 0.85, 0.15), Color(0.15, 0.3, 0.95)]
	for ci in corners.size():
		var cpos: Vector2 = corners[ci]
		_cyl(0.11, 1.65, Vector3(cpos.x, 0.9 + 0.825, cpos.y), Color(0.75, 0.75, 0.8))
		var inward := Vector3(-signf(cpos.x), 0, -signf(cpos.y)) * 0.12
		for hh in heights:
			var pad := _box(Vector3(0.26, 0.24, 0.26), Vector3(cpos.x, RING_TOP + hh, cpos.y) + inward, pad_cols[ci])
			pad.rotation.y = PI / 4.0
	var rope_colors: Array[Color] = [Color(0.9, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.95)]
	rope_nodes.clear()
	for i in 3:
		var y: float = RING_TOP + heights[i]
		var c: Color = rope_colors[i]
		rope_nodes.append(_box(Vector3(2 * h, 0.07, 0.07), Vector3(0, y, h), c))
		rope_nodes.append(_box(Vector3(2 * h, 0.07, 0.07), Vector3(0, y, -h), c))
		rope_nodes.append(_box(Vector3(0.07, 0.07, 2 * h), Vector3(h, y, 0), c))
		rope_nodes.append(_box(Vector3(0.07, 0.07, 2 * h), Vector3(-h, y, 0), c))

	# Steel steps at the far-left corner
	var steel := Color(0.55, 0.57, 0.62)
	_box(Vector3(1.3, 0.3, 0.55), Vector3(-3.2, 0.15, -5.95), steel)
	_box(Vector3(1.3, 0.6, 0.55), Vector3(-3.2, 0.3, -5.4), steel)
	_box(Vector3(1.3, 0.9, 0.55), Vector3(-3.2, 0.45, -4.85), steel)

	# Timekeeper / announce table with the bell
	_box(Vector3(2.4, 0.08, 0.8), Vector3(2.2, 0.76, -6.0), Color(0.5, 0.32, 0.18))
	_box(Vector3(2.3, 0.7, 0.05), Vector3(2.2, 0.38, -5.62), Color(0.15, 0.2, 0.6))
	_cyl(0.13, 0.12, Vector3(2.8, 0.86, -6.0), Color(0.95, 0.75, 0.2))
	_box(Vector3(0.35, 0.25, 0.25), Vector3(1.6, 0.92, -6.1), Color(0.1, 0.1, 0.1))  # monitor

	# Barricade (black with a blue padded top rail), gap on +x for the entrance aisle
	var bar_c := Color(0.08, 0.08, 0.1)
	var rail_c := Color(0.15, 0.35, 0.95)
	var e := 7.2
	_box(Vector3(2 * e, 0.9, 0.2), Vector3(0, 0.45, -e), bar_c)
	_box(Vector3(2 * e, 0.12, 0.3), Vector3(0, 0.96, -e), rail_c)
	_box(Vector3(2 * e, 0.9, 0.2), Vector3(0, 0.45, e + 0.3), bar_c)
	_box(Vector3(0.2, 0.9, 2 * e), Vector3(-e, 0.45, 0), bar_c)
	_box(Vector3(0.3, 0.12, 2 * e), Vector3(-e, 0.96, 0), rail_c)
	for s in [-1.0, 1.0]:
		var zc: float = s * (e + 1.3) * 0.5
		_box(Vector3(0.2, 0.9, e - 1.3), Vector3(e, 0.45, zc), bar_c)
		_box(Vector3(0.3, 0.12, e - 1.3), Vector3(e, 0.96, zc), rail_c)

	# ---- Entrance aisle + stage on the +x side
	_box(Vector3(9.5, 0.3, 2.0), Vector3(11.6, 0.15, 0), Color(0.2, 0.2, 0.28))
	for s in [-1.0, 1.0]:
		_box(Vector3(9.5, 0.06, 0.08), Vector3(11.6, 0.32, s * 1.0), Color(1.0, 0.3, 0.8), true)
	_box(Vector3(4.0, 1.2, 10.0), Vector3(18.4, 0.6, 0), Color(0.12, 0.1, 0.18))
	_box(Vector3(0.4, 7.0, 12.0), Vector3(20.6, 3.5, 0), Color(0.06, 0.04, 0.12))
	var stripe_cols: Array[Color] = [Color(1.0, 0.8, 0.2), Color(1.0, 0.25, 0.7), Color(0.2, 0.75, 1.0)]
	for i in 3:
		_box(Vector3(0.05, 0.25, 11.0), Vector3(20.38, 1.8 + i * 0.6, 0), stripe_cols[i], true)
	var stage_sign := Label3D.new()
	stage_sign.text = "THUNDER"
	stage_sign.font_size = 200
	stage_sign.outline_size = 28
	stage_sign.modulate = Color(1.0, 0.82, 0.2)
	stage_sign.position = Vector3(20.3, 4.6, 0)
	stage_sign.rotation_degrees = Vector3(0, -90, 0)
	add_child(stage_sign)

	# ---- Video wall above the far (-z) crowd: the backdrop the camera always sees
	var wall_z := -16.9
	_box(Vector3(46, 9.0, 0.4), Vector3(0, 4.5, wall_z - 0.4), Color(0.05, 0.03, 0.09))
	_box(Vector3(17.0, 3.6, 0.3), Vector3(0, 5.9, wall_z), Color(0.12, 0.12, 0.16))
	_box(Vector3(16.2, 2.9, 0.1), Vector3(0, 5.9, wall_z + 0.17), Color(0.06, 0.08, 0.3), true)
	_box(Vector3(16.2, 0.12, 0.1), Vector3(0, 7.45, wall_z + 0.2), Color(1.0, 0.3, 0.8), true)
	_box(Vector3(16.2, 0.12, 0.1), Vector3(0, 4.45, wall_z + 0.2), Color(0.2, 0.8, 1.0), true)
	var sign3d := Label3D.new()
	sign3d.text = "TURNBUCKLE THUNDER"
	sign3d.font_size = 150
	sign3d.outline_size = 24
	sign3d.modulate = Color(1.0, 0.82, 0.2)
	sign3d.position = Vector3(0, 6.3, wall_z + 0.3)
	add_child(sign3d)
	var sub := Label3D.new()
	sub.text = "made with Xogot"
	sub.font_size = 64
	sub.outline_size = 12
	sub.modulate = Color(0.6, 0.85, 1.0)
	sub.position = Vector3(0, 5.25, wall_z + 0.3)
	add_child(sub)


func _build_crowd() -> void:
	# Bleachers on the far (-z) side and the two flanks, filled with billboard pixel fans.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.48, 0.96)
	var sh := Shader.new()
	sh.code = CROWD_SHADER
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = sh
	crowd_mat.set_shader_parameter("tex", _make_crowd_texture())
	crowd_mat.set_shader_parameter("hype", 0.0)

	var xforms: Array[Transform3D] = []
	var seat_cols: Array[Color] = [Color(0.12, 0.09, 0.18), Color(0.17, 0.12, 0.24)]
	var step := 0.75
	var rows := 9
	for row in rows:
		var dist := 9.5 + row * step
		var top := 0.3 + row * 0.38
		var seat: Color = seat_cols[row % 2]
		var half := step * 0.5
		# far side (-z): spans x inside the flank steps so step tops never overlap
		_box(Vector3(2.0 * (dist - half), top, step), Vector3(0, top * 0.5, -dist), seat)
		# left flank (-x), full length to just past the ring
		var lz0 := -dist - half
		var lz1 := 2.0
		_box(Vector3(step, top, lz1 - lz0), Vector3(-dist, top * 0.5, (lz0 + lz1) * 0.5), seat)
		# right flank (+x), stops before the entrance aisle
		var rz1 := -3.0
		_box(Vector3(step, top, rz1 - lz0), Vector3(dist, top * 0.5, (lz0 + rz1) * 0.5), seat)

		var y := top + 0.48
		var x := -dist + randf() * 0.3
		while x < dist:
			_add_fan(xforms, Vector3(x, y, -dist + randf_range(-0.12, 0.12)))
			x += randf_range(0.42, 0.56)
		var z := -dist + 0.5 + randf() * 0.3
		while z < lz1:
			_add_fan(xforms, Vector3(-dist + randf_range(-0.12, 0.12), y, z))
			if z < rz1:
				_add_fan(xforms, Vector3(dist + randf_range(-0.12, 0.12), y, z + randf_range(-0.1, 0.1)))
			z += randf_range(0.42, 0.56)

	# LED ribbon board along the front of the far bleachers
	_box(Vector3(2.0 * 9.1, 0.3, 0.05), Vector3(0, 0.2, -9.5 + step * 0.5 + 0.03), Color(1.0, 0.25, 0.7), true)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = xforms.size()
	var palette: Array[Color] = [Color(0.95, 0.2, 0.2), Color(0.2, 0.45, 1.0), Color(1.0, 0.9, 0.2), Color(0.95, 0.95, 0.95),
		Color(0.2, 0.8, 0.35), Color(0.65, 0.3, 0.9), Color(0.2, 0.2, 0.22), Color(1.0, 0.55, 0.15), Color(1.0, 0.4, 0.75)]
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, palette[randi() % palette.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = crowd_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

	# Camera-flash pops: tiny additive billboards that blink at random spots in the crowd.
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_texture = _make_flash_texture()
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	fm.albedo_color = Color(1.0, 1.0, 0.95)
	var fq := QuadMesh.new()
	fq.size = Vector2(0.7, 0.7)
	flash_nodes.clear()
	flash_timers = PackedFloat32Array()
	for i in 10:
		var f := MeshInstance3D.new()
		f.mesh = fq
		f.material_override = fm
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		add_child(f)
		flash_nodes.append(f)
		flash_timers.append(randf_range(0.1, 2.5))


func _add_fan(xforms: Array[Transform3D], p: Vector3) -> void:
	if randf() < 0.06:
		return  # empty seat
	# Quad's +Z (its front) faces the ring / broadcast camera side.
	var focus := Vector3(0, p.y, 2.0)
	var away := p - focus
	away.y = 0.0
	var tr := Transform3D(Basis(), p).looking_at(p + away, Vector3.UP)
	var s := randf_range(0.9, 1.1)
	tr.basis = tr.basis.scaled(Vector3(s, s, s))
	xforms.append(tr)
	crowd_spots.append(p + Vector3(0, 0.3, 0))


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
			flash_timers[i] = randf_range(0.4, 3.5) / (1.0 + crowd_hype_shown * 4.0)
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
			_snd("pop", -1.0, 0.03)
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
				_snd("pop", -8.0)
				_hype(0.15)
			feel_last_count = 0
		"reversal":
			_snd("whoosh", -2.0)
			_snd("pop", -9.0)
			_hitstop(0.06)
			_fx_spark(where, st)
			_kick_cam(-2.0, 0.3)
			_buzz(20)
			_hype(0.2)
		"taunt":
			var cpu: bool = w.is_cpu
			_snd("boo" if cpu else "pop", -5.0)
			_hype(0.1)
		"grab":
			_snd("punch", -9.0, 0.15)
			_kick_cam(-1.0, 0.0)
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
	hint_label = _big_label(30)
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
			["", "Counters lock-ups, whips, punches"],
			["", "Arm Drag / Hip Toss / Back Body Drop"],
			["TOO EARLY", "Early presses lock you out"],
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
	_place(hint_panel, 0.5, 1.0, Rect2(0, -(get_viewport().get_visible_rect().size.y - sr.end.y) - 14, 0, 0))
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


func _pop(c: Control, from_scale: float, from_rot: float, secs: float) -> Tween:
	c.pivot_offset = c.size * 0.5
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


func _hint_text() -> String:
	var st: int = p1.state
	var opp: int = p2.state
	var special: bool = p1.is_special_ready()
	var rev: float = p1.reversal_window
	var lockout: float = p1.reversal_lockout
	var a: Vector3 = p1.position
	var b: Vector3 = p2.position
	var near := Vector2(a.x - b.x, a.z - b.z).length() < 1.7
	if rev > 0.0:
		return "REVERSE!  Tap GRAB or STRIKE NOW!"
	if st == Wrestler.S.TIEUP_ATK:
		var strong: bool = p1.tie_strong
		if strong:
			var fin_s := "THUNDER DRIVER!" if special else "Neckbreaker"
			return "STRONG LOCK-UP   STRIKE: Tombstone   STICK+STRIKE: Powerbomb\nGRAB: Spinebuster   STICK+GRAB: " + fin_s + "   RUN: Irish Whip"
		var fin := "THUNDER DRIVER!" if special else "DDT"
		return "STRIKE: Knee   STICK+STRIKE: Suplex\nGRAB: Slam   STICK+GRAB: " + fin + "   RUN: Irish Whip"
	if st == Wrestler.S.TIEUP_DEF:
		if lockout > 0.0:
			return "TOO EARLY!  Wait for the move..."
		return "CAUGHT!  Tap GRAB or STRIKE the moment he moves to reverse"
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
	var rev: float = p1.reversal_window
	var mv: Vector2 = p1.in_move
	var dir_held := mv.length() > 0.5
	var a: Vector3 = p1.position
	var b: Vector3 = p2.position
	var near := Vector2(a.x - b.x, a.z - b.z).length() < 1.7
	var glow := "grapple" if special else ""
	if match_over:
		touch.set_labels("", "", "", "")
		glow = ""
	elif rev > 0.0:
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

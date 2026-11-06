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
	_setup_input()
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
	}
	var volcano := {
		"gear": Color(1.0, 0.5, 0.1), "trunks": Color(0.12, 0.3, 0.85), "boot_color": Color(0.12, 0.3, 0.85),
		"skin": Color(0.6, 0.42, 0.3), "tights": true, "mask": true,
		"mask_color": Color(0.12, 0.3, 0.85), "mask_trim": Color(1.0, 0.55, 0.1), "hair_color": Color.BLACK,
	}
	p1 = _spawn("BRICK MASON", brick, false, Vector3(-1.8, 0, 0.3))
	p2 = _spawn("THE VOLCANO", volcano, true, Vector3(1.8, 0, -0.3))
	p1.opponent = p2
	p2.opponent = p1
	p1._snap_face_opponent()
	p2._snap_face_opponent()

	_build_hud()
	_announce("FIGHT!", 1.5)


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
	return w


# ---------------------------------------------------------------- HUD

func _make_bar(color: Color, height: float) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 100
	pb.value = 100
	pb.custom_minimum_size = Vector2(380, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_border_width_all(2)
	bg.border_color = Color(1, 1, 1, 0.8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	pb.set_meta("fill", fill)
	return pb


func _player_panel(w: Node3D, right: bool) -> Control:
	var box := VBoxContainer.new()
	var name_label := Label.new()
	name_label.text = w.display_name + (" (CPU)" if w.is_cpu else " (YOU)")
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.add_theme_color_override("font_color", w.gear_color.lightened(0.3))
	if right:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(name_label)
	var hp := _make_bar(Color(0.2, 0.85, 0.3), 22)
	box.add_child(hp)
	var sp := _make_bar(Color(1.0, 0.75, 0.1), 10)
	sp.value = 0
	box.add_child(sp)
	if right:
		hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		sp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	bars[w] = {"hp": hp, "sp": sp, "fill": hp.get_meta("fill"), "spfill": sp.get_meta("fill")}
	return box


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
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	touch = TouchControls.new()
	hud.add_child(touch)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for s in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + s, 24)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	row.add_child(_player_panel(p1, false))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_player_panel(p2, true))

	announce_label = _big_label(54)
	_place(announce_label, 0.5, 0.0, Rect2(-400, 120, 800, 90))
	announce_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	hud.add_child(announce_label)

	count_label = _big_label(140)
	_place(count_label, 0.5, 0.5, Rect2(-200, -140, 400, 200))
	hud.add_child(count_label)

	hint_label = _big_label(20)
	_place(hint_label, 0.5, 1.0, Rect2(-290, -90, 580, 80))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(hint_label)

	win_panel = Control.new()
	win_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_panel.visible = false
	hud.add_child(win_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.add_child(dim)
	win_label = _big_label(64)
	win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_label.offset_bottom = -120
	win_panel.add_child(win_label)
	var btn := Button.new()
	btn.text = "  REMATCH  "
	btn.add_theme_font_size_override("font_size", 40)
	_place(btn, 0.5, 0.5, Rect2(-140, 40, 280, 80))
	btn.pressed.connect(_restart)
	win_panel.add_child(btn)


func _announce(text: String, secs: float) -> void:
	if match_over and text != "":
		return
	announce_label.text = text
	announce_timer = secs


func _on_pin_count(c: int) -> void:
	count_label.text = str(c) + ("!" if c >= 3 else "")
	count_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2) if c >= 3 else Color.WHITE)
	count_timer = 0.7 if c < 3 else 2.5
	cam_shake = max(cam_shake, 0.25)


func _on_win(w: Node3D) -> void:
	match_over = true
	announce_label.text = ""
	win_label.text = "%s WINS!" % w.display_name
	win_label.add_theme_color_override("font_color", w.gear_color.lightened(0.35))
	get_tree().create_timer(1.2).timeout.connect(func(): win_panel.visible = true)


func _restart() -> void:
	get_tree().reload_current_scene()


func _hint_text() -> String:
	var st: int = p1.state
	if st == Wrestler.S.TIEUP_ATK:
		var fin := "Dir+GRAB: THUNDER DRIVER (SPECIAL!)" if p1.is_special_ready() else "Dir+GRAB: DDT"
		return "LOCK-UP!  STRIKE: Knee Lift   Dir+STRIKE: Suplex\nGRAB: Body Slam   " + fin
	if st == Wrestler.S.TIEUP_DEF:
		return "You're caught! Tap GRAB or STRIKE to try a REVERSAL"
	if st == Wrestler.S.PINNED:
		return "MASH ANY BUTTON TO KICK OUT!"
	if st == Wrestler.S.RUN:
		return "Running! STRIKE: Clothesline   RUN: stop"
	if p2.state == Wrestler.S.DOWN:
		return "Opponent is down! Get close and press PIN"
	if p1.is_special_ready():
		return "SPECIAL! Grab, then Direction + GRAB for your finisher"
	return ""


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if not match_over:
		var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if touch.joy_vector.length() > mv.length():
			mv = touch.joy_vector
		p1.in_move = mv
		p1.in_strike = Input.is_action_just_pressed("strike")
		p1.in_grapple = Input.is_action_just_pressed("grapple")
		p1.in_run = Input.is_action_just_pressed("run")
		p1.in_pin = Input.is_action_just_pressed("pin")
		p1.any_pressed = p1.in_strike or p1.in_grapple or p1.in_run or p1.in_pin
	else:
		p1.in_move = Vector2.ZERO
		if Input.is_action_just_pressed("restart"):
			_restart()
			return
	p1.tick(delta)
	p2.tick(delta)

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
	for w in [p1, p2]:
		var d: Dictionary = bars[w]
		d["hp"].value = lerp(float(d["hp"].value), w.health, clamp(delta * 8.0, 0.0, 1.0))
		d["sp"].value = w.spirit
		var hcol := Color(0.2, 0.85, 0.3)
		if w.health < 30:
			hcol = Color(0.95, 0.2, 0.15)
		elif w.health < 60:
			hcol = Color(0.95, 0.7, 0.1)
		d["fill"].bg_color = hcol
		var flash: bool = w.is_special_ready() and int(Time.get_ticks_msec() / 150) % 2 == 0
		d["spfill"].bg_color = Color(1, 1, 1) if flash else Color(1.0, 0.75, 0.1)

	if announce_timer > 0.0:
		announce_timer -= delta
		announce_label.modulate.a = clamp(announce_timer * 3.0, 0.0, 1.0)
	if count_timer > 0.0:
		count_timer -= delta
		count_label.modulate.a = clamp(count_timer * 3.0, 0.0, 1.0)
	else:
		count_label.text = ""
	hint_label.text = "" if match_over else _hint_text()

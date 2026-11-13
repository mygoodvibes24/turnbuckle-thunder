extends "res://scripts/levels/level_base.gd"
## THE BLOCK (level id "street"): Hydrangea Street at dusk, the cul-de-sac out front, block party in
## full swing (story ch8 finale). They fight in the middle of the closed-off street: worn asphalt with
## faded double-yellow lines, two manholes and a chalk "ring" the kids drew for the main event.
## Fighting area x -7..7, z -5..5 (the road between the two gutters); ground y 0, curbs 0.15.
##   -z (backdrop): curb + sidewalk with the bus stop, snack table, basketball hoop, DJ booth and
##                  speaker stack, then front lawns, porches full of neighbours and the house fronts.
##   -x: a parked sedan (roof perch).  +x: Dusty-style pickup, tailgate down (bed perch).
##   +z (camera side): only the low curb, sidewalk, trash-day bins at the far corners.
## Perches: snack table 0.75, pickup bed 0.95, car roof 1.46, speaker stack 1.8, bus stop roof 2.5.
## Helpers: see the header of scripts/levels/backyard.gd. Two extra batch keys of our own
## ("street_paint" glossy car paint, "street_cloth" gingham tablecloth) are committed in _flush_custom().

const ROAD_Z0 := -5.2        # back curb face
const ROAD_Z1 := 5.4         # front curb face
const GUTTER := 0.45         # concrete gutter pan along each curb
const CURB_H := 0.15
const WALK_W := 1.65
const LAWN_Y := 0.12
const ROAD_X := 30.0         # road runs x -30..30

const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx, cull_disabled;

uniform sampler2D map : source_color, filter_linear_mipmap;
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 detail_scale = vec2(10.0, 10.0);
uniform float rough = 0.92;

void fragment() {
	vec3 mp = texture(map, UV).rgb;
	vec3 d = texture(detail, UV * detail_scale).rgb;
	ALBEDO = mp * d * 2.0;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint = vec3(1.0, 0.9, 0.7);
uniform float strength = 0.07;

void fragment() {
	float along = 1.0 - UV.y;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint * strength * along * along * facing;
}
"""

const SKY_SHADER := """
shader_type sky;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -0.2, 1.0);
	// Dusk: hot orange horizon, dusty rose band, deepening violet-blue overhead.
	vec3 hor = vec3(1.0, 0.5, 0.24);
	vec3 mid = vec3(0.6, 0.3, 0.36);
	vec3 top = vec3(0.11, 0.11, 0.29);
	vec3 col = mix(hor, mid, smoothstep(0.0, 0.16, h));
	col = mix(col, top, smoothstep(0.12, 0.62, h));
	col = mix(col, vec3(0.32, 0.17, 0.14), 1.0 - smoothstep(-0.12, 0.0, h));
	// The sun just went down behind the houses (-z, a little left).
	vec3 sd = normalize(vec3(-0.4, 0.03, -1.0));
	float s = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.42, 0.12) * pow(s, 6.0) * 0.55 * (1.0 - smoothstep(0.0, 0.45, h));
	col += vec3(1.0, 0.85, 0.55) * pow(s, 80.0) * 0.6;
	// Long streaky clouds lit from below.
	vec2 cp = d.xz / max(d.y + 0.12, 0.05);
	float c = vnoise(cp * vec2(0.9, 3.5)) * 0.6 + vnoise(cp * vec2(2.2, 7.0)) * 0.4;
	float band = smoothstep(0.02, 0.08, h) * (1.0 - smoothstep(0.25, 0.5, h));
	vec3 ccol = mix(vec3(0.98, 0.52, 0.36), vec3(0.34, 0.21, 0.33), smoothstep(0.05, 0.3, h));
	col = mix(col, ccol, smoothstep(0.5, 0.8, c) * band * 0.75);
	// The first stars, high up.
	vec3 cell = floor(d * 260.0);
	float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	col += vec3(0.9, 0.9, 1.0) * step(0.996, r) * smoothstep(0.45, 0.8, d.y) * 0.5;
	COLOR = col;
}
"""

var m = null   # main.gd (helpers)
var _bulb_xforms: Array[Transform3D] = []
var _bulb_cols: Array[Color] = []


func _init() -> void:
	display_name = "THE BLOCK"
	description = "The cul-de-sac out front: asphalt, parked cars, trash day and the whole block outside."
	time_of_day = "dusk"
	preview_color = Color(0.36, 0.36, 0.4)
	yard_bounds = Rect2(-7.0, -5.0, 14.0, 10.0)
	cam_clamp = Rect2(-5.0, -4.0, 10.0, 7.5)
	cam_height = 2.9
	cam_back = 5.6
	default_surface = "asphalt"
	surfaces = [
		{"rect": Rect2(-ROAD_X, ROAD_Z0, 2.0 * ROAD_X, GUTTER), "kind": "concrete"},
		{"rect": Rect2(-ROAD_X, ROAD_Z1 - GUTTER, 2.0 * ROAD_X, GUTTER), "kind": "concrete"},
	]
	spawn_p1 = Vector3(-1.8, 0.0, 0.6)
	spawn_p2 = Vector3(1.8, 0.0, -0.2)


func build(main_node: Node) -> void:
	super(main_node)
	m = main_node
	perches.clear()
	obstacles.clear()
	crowd_spots = []
	_build_lights()
	_build_ground()
	_build_road_marks()
	_build_houses()
	_build_trees()
	_build_street_furniture()
	_build_bus_stop()
	_build_hoop()
	_build_party()
	_build_sedan()
	_build_pickup()
	_build_minivan()
	_build_string_lights()
	_build_grime()
	_flush_custom()
	m._flush_batches()
	_build_crowd_spots()
	# Weapons lying around the street: folding chairs from the party, two trash cans out for trash
	# day, a 2x4 off the road-closed barricade, a folding table leaning on the pickup.
	item_spawns = [
		{"kind": "chair", "pos": Vector3(-3.6, 0.0, -3.1), "yaw": PI * 0.25},
		{"kind": "chair", "pos": Vector3(4.3, 0.0, 3.4), "yaw": -PI * 0.3},
		{"kind": "trash_can", "pos": Vector3(-6.4, 0.0, 4.4), "yaw": 0.0},
		{"kind": "trash_can", "pos": Vector3(3.9, 0.0, -4.4), "yaw": 0.0},
		{"kind": "plank", "pos": Vector3(-1.2, 0.0, 4.3), "yaw": 0.2},
		{"kind": "table", "pos": Vector3(6.95, 0.0, -1.5), "yaw": -PI * 0.5},   # top faces -x (into the street)
	]


# ---- environment: dusk

func setup_environment(env: Environment) -> void:
	if main == null:
		return
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var sm: ShaderMaterial = main.sky_mat
	if sm != null:
		sm.shader = sh
	env.ambient_light_color = Color(0.64, 0.53, 0.6)   # warm-violet dusk fill
	env.ambient_light_energy = 0.52
	env.fog_light_color = Color(0.34, 0.21, 0.22)
	env.fog_density = 0.012
	env.tonemap_exposure = 1.15
	var sun: DirectionalLight3D = main.moon
	if sun != null:
		# The last of the sunset from behind the houses: a low warm rim on heads and shoulders.
		sun.transform = Transform3D(Basis.looking_at(Vector3(0.35, -0.32, 1.0)), Vector3(0, 10, 0))
		sun.light_color = Color(1.0, 0.6, 0.38)
		sun.light_energy = 0.62
	var pm: ShaderMaterial = main.post_mat
	if pm != null:
		pm.set_shader_parameter("highlight_tint", Vector3(1.12, 0.98, 0.8))
		pm.set_shader_parameter("shadow_tint", Vector3(0.94, 0.95, 1.06))


func _build_lights() -> void:
	# Key: the front-left streetlight (sodium-warm cobra head, tilted into the street).
	var kp := Vector3(-9.3, 6.7, 5.4)
	key_light = m.make_spot(kp, Vector3(-0.6, 0.0, -0.6), 50.0, 24.0, 3.8, Color(1.0, 0.8, 0.55))
	key_light.spot_angle_attenuation = 1.2
	# Back-right streetlight over the DJ end of the street.
	var bp := Vector3(9.3, 6.7, -5.4)
	var back: SpotLight3D = m.make_spot(bp, Vector3(2.6, 0.0, 0.6), 46.0, 20.0, 2.6, Color(1.0, 0.72, 0.42))
	back.spot_angle_attenuation = 1.3
	# Starla's stage light on its tripod by the speakers: a pink wash over the middle of the street.
	var sp := Vector3(7.4, 2.95, -6.15)
	var aim := Vector3(-0.5, 0.0, 0.4)
	var par: SpotLight3D = m.make_spot(sp, aim, 26.0, 16.0, 2.2, Color(1.0, 0.45, 0.72))
	par.spot_angle_attenuation = 0.9
	_beam_cone(sp, aim, 9.0, 17.0, Vector3(1.0, 0.45, 0.75), 0.06)
	# Warm glow from the string lights over the street, the DJ booth, and a porch light.
	m.make_omni(Vector3(0.0, 4.0, -0.5), 10.0, 0.45, Color(1.0, 0.78, 0.5))
	m.make_omni(Vector3(4.0, 1.3, -5.6), 3.6, 0.9, Color(0.5, 0.42, 1.0))
	m.make_omni(Vector3(8.2, 2.7, -10.7), 6.5, 1.1, Color(1.0, 0.78, 0.5))


func _beam_cone(from: Vector3, aim: Vector3, beam_len: float, half_angle: float, tint: Vector3, strength: float) -> void:
	# A faint additive cone so the light shaft reads in the hazy (fog machine) dusk air.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = tan(deg_to_rad(half_angle)) * beam_len
	cone.height = beam_len
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var csh := Shader.new()
	csh.code = BEAM_SHADER
	var cmat := ShaderMaterial.new()
	cmat.shader = csh
	cmat.set_shader_parameter("tint", tint)
	cmat.set_shader_parameter("strength", strength)
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = cmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bdir := (aim - from).normalized()
	beam.transform = Transform3D(Basis(Quaternion(Vector3.DOWN, bdir)), from + bdir * beam_len * 0.5)
	add_child(beam)


# ---- ground: asphalt, gutters, curbs, sidewalks, lawns, driveways

func _ground_mat(map: Texture2D, detail: Texture2D, scale: Vector2, rough := 0.92) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	var gm := ShaderMaterial.new()
	gm.shader = sh
	gm.set_shader_parameter("map", map)
	gm.set_shader_parameter("detail", detail)
	gm.set_shader_parameter("detail_scale", scale)
	gm.set_shader_parameter("rough", rough)
	return gm


func _build_ground() -> void:
	var far: StandardMaterial3D = m._tex_mat(m._make_grass_detail())
	far.albedo_color = Color(0.22, 0.3, 0.12)
	far.uv1_scale = Vector3(60, 60, 1)
	far.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._plane(Vector2(120, 120), Vector3(0, -0.01, 0), far)

	# Asphalt between the gutters: a painted wear map (wheel paths, oil drips, patches, sealed
	# cracks, leaves in the gutters) times a tiling grain texture.
	var a0 := ROAD_Z0 + GUTTER
	var a1 := ROAD_Z1 - GUTTER
	var rw := 48.0
	var road := _ground_mat(_make_road_map(a0, a1), _make_asphalt_detail(), Vector2(rw / 4.0, (a1 - a0) / 4.0), 0.85)
	m._ground_quad(Vector3(0, 0.0, (a0 + a1) * 0.5), Vector2(rw, a1 - a0), road)
	var dark: StandardMaterial3D = m._tex_mat(_make_asphalt_detail())
	dark.albedo_color = Color(0.5, 0.49, 0.48)
	for s: float in [-1.0, 1.0]:   # the road beyond the painted part
		m._ground_quad(Vector3(s * (rw * 0.5 + 6.0), -0.002, (a0 + a1) * 0.5), Vector2(12.0, a1 - a0), dark, 0.0, Vector2(4.0, 3.0))

	# Concrete gutter pans + curbs.
	var gm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(128, true, 1))
	gm.albedo_color = Color(0.86, 0.84, 0.8)
	var gl := 2.0 * ROAD_X
	m._ground_quad(Vector3(0, 0.004, ROAD_Z0 + GUTTER * 0.5), Vector2(gl, GUTTER), gm, 0.0, Vector2(gl / 6.0, GUTTER / 6.0))
	m._ground_quad(Vector3(0, 0.004, ROAD_Z1 - GUTTER * 0.5), Vector2(gl, GUTTER), gm, 0.0, Vector2(gl / 6.0, GUTTER / 6.0))
	var curb := Color(0.74, 0.72, 0.68)
	m._bx("block", Vector3(gl, CURB_H, 0.18), Vector3(0, CURB_H * 0.5, ROAD_Z0 - 0.09), curb)
	m._bx("block", Vector3(gl, CURB_H, 0.18), Vector3(0, CURB_H * 0.5, ROAD_Z1 + 0.09), curb)

	# Sidewalks (slabs every ~1.5 m) on top of the curbs.
	var wm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 3))
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var bz := ROAD_Z0 - 0.18 - WALK_W * 0.5
	var fz := ROAD_Z1 + 0.18 + WALK_W * 0.5
	m._ground_quad(Vector3(0, CURB_H, bz), Vector2(gl, WALK_W), wm, 0.0, Vector2(gl / 6.0, WALK_W / 6.0))
	m._ground_quad(Vector3(0, CURB_H, fz), Vector2(gl, WALK_W), wm, 0.0, Vector2(gl / 6.0, WALK_W / 6.0))
	m._bx("block", Vector3(gl, CURB_H, 0.1), Vector3(0, CURB_H * 0.5 - 0.01, bz - WALK_W * 0.5 - 0.05), curb.darkened(0.15))

	# Front lawns (painted variation x tiling grass blades), both sides of the street.
	var detail: ImageTexture = m._make_grass_detail()
	var bl0 := bz - WALK_W * 0.5 - 0.1
	var bl1 := -14.0
	var lawn_b := _ground_mat(_make_lawn_map(512, 64), detail, Vector2(gl / 2.5, (bl0 - bl1) / 2.5))
	m._ground_quad(Vector3(0, LAWN_Y, (bl0 + bl1) * 0.5), Vector2(gl, bl0 - bl1), lawn_b)
	var fl0 := fz + WALK_W * 0.5 + 0.02
	var lawn_f := _ground_mat(_make_lawn_map(256, 32), detail, Vector2(gl / 2.5, 8.0 / 2.5))
	m._ground_quad(Vector3(0, LAWN_Y, fl0 + 4.0), Vector2(gl, 8.0), lawn_f)

	# Driveways: the hoop driveway up to house B's garage, and house C's (with tire tracks).
	var dm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 4, true))
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for d: Vector3 in [Vector3(1.55, -11.0, 2.8), Vector3(12.6, -11.6, 2.6), Vector3(-17.9, -12.0, 2.6)]:
		var dl := (bl0 + 0.05) - d.y
		m._ground_quad(Vector3(d.x, LAWN_Y + 0.012, d.y + dl * 0.5), Vector2(dl, d.z), dm, PI * 0.5, Vector2(dl / 3.0, 1.0))
	# Front walks from the sidewalk to the porches.
	var walk_m: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(128, true, 1))
	for wk: Vector3 in [Vector3(-13.0, -12.0, 1.1), Vector3(-3.0, -11.0, 1.0), Vector3(8.4, -11.6, 1.1)]:
		var wl := (bl0 + 0.05) - wk.y
		m._ground_quad(Vector3(wk.x, LAWN_Y + 0.01, wk.y + wl * 0.5), Vector2(wk.z, wl), walk_m, 0.0, Vector2(wk.z / 2.0, wl / 2.0))


func _make_asphalt_detail() -> ImageTexture:
	# 256 px tileable asphalt grain (averages ~0.5): binder, light aggregate stones, dark pits,
	# black tar crack-seal snakes and hairline cracks.
	var n := 256
	var mot: Image = m._noise_img(n, n, 0.03, 3)
	var grit: Image = m._noise_img(n, n, 0.7, 1)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var g := 0.5 + (mot.get_pixel(x, y).r - 0.5) * 0.22 + (grit.get_pixel(x, y).r - 0.5) * 0.34
			var c := Color(g, g * 0.99, g * 0.965)
			var r := randf()
			if r < 0.06:
				c = c.lightened(randf_range(0.15, 0.35))
			elif r < 0.1:
				c = c.darkened(0.32)
			img.set_pixel(x, y, c)
	var tar := Color(0.12, 0.115, 0.11)
	for i in 3:
		var p := Vector2(randf() * n, randf() * n)
		var ang := randf() * TAU
		for k in 14:
			ang += randf_range(-0.5, 0.5)
			var q := p + Vector2(cos(ang), sin(ang)) * randf_range(8.0, 16.0)
			for o: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
				m._line_px(img, p + o, q + o, tar, 0.7)
			p = q
	for i in 4:
		m._crack(img, Vector2(randf() * n, randf() * n), randf() * TAU, randi_range(6, 14), 7.0, Color(0.15, 0.15, 0.15))
	return m._sharp_tex(img)


func _make_road_map(z0: float, z1: float) -> ImageTexture:
	# Non-tiling colour/wear map for the 48 m of road in view (u = x, v = z from back to front).
	var w := 512
	var h := 96
	var mot: Image = m._noise_img(w, h, 0.02, 3, false)
	var fine: Image = m._noise_img(w, h, 0.12, 2, false)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var base := Color(0.27, 0.262, 0.255)
	for y in h:
		var z := lerpf(z0, z1, float(y) / (h - 1))
		var track := 0.0
		for c: float in [-3.6, -1.9, 1.9, 3.6]:
			track = maxf(track, 1.0 - smoothstep(0.12, 0.5, absf(z - c)))
		var drip := 1.0 - smoothstep(0.0, 0.32, minf(absf(z + 2.75), absf(z - 2.75)))
		var edge := 1.0 - smoothstep(0.0, 0.8, minf(z - z0, z1 - z))
		for x in w:
			var mo := mot.get_pixel(x, y).r
			var fi := fine.get_pixel(x, y).r
			var c := base.darkened((mo - 0.5) * 0.4 + (fi - 0.5) * 0.16)
			c = c.lightened(track * 0.09 * (0.5 + mo))          # wheel paths: worn, aggregate showing
			c = c.darkened(drip * 0.22 * (0.4 + fi))             # oil drips down the middle of each lane
			c = c.lerp(Color(0.2, 0.17, 0.13), edge * 0.5)       # grit and dirt washing into the gutters
			img.set_pixel(x, y, c)
	# Repair patches: fresher, blacker asphalt with a lighter seam.
	for i in 7:
		var pw := randf_range(28.0, 80.0)
		var ph := randf_range(10.0, 30.0)
		var px := randf_range(0.0, w - pw)
		var py := randf_range(6.0, h - ph - 6.0)
		m._soft_rect(img, px, py, pw, ph, Color(0.13, 0.13, 0.135), 0.6, 1.0)
		for e: Array in [[Vector2(px, py), Vector2(px + pw, py)], [Vector2(px, py + ph), Vector2(px + pw, py + ph)],
				[Vector2(px, py), Vector2(px, py + ph)], [Vector2(px + pw, py), Vector2(px + pw, py + ph)]]:
			m._line_px(img, e[0], e[1], Color(0.08, 0.08, 0.08), 0.5)
	# Long crack-seal lines snaking across the lanes.
	for i in 9:
		var p := Vector2(randf() * w, randf() * h)
		var ang := randf() * TAU
		for k in 18:
			ang += randf_range(-0.45, 0.45)
			var q := p + Vector2(cos(ang), sin(ang)) * randf_range(4.0, 9.0)
			m._line_px(img, p, q, Color(0.07, 0.07, 0.07), 0.55)
			p = q
	# Oil stains where cars park along the curbs.
	for i in 16:
		var cy := (randf_range(0.08, 0.22) if randf() < 0.5 else randf_range(0.78, 0.92)) * h
		var cx := randf() * w
		for k in 4:
			m._soft_dot(img, cx + randf_range(-5.0, 5.0), cy + randf_range(-2.0, 2.0), randf_range(3.0, 8.0), randf_range(2.0, 4.0),
				Color(0.05, 0.05, 0.06), randf_range(0.15, 0.3), 3.0)
	# Leaves and litter in the gutters.
	for i in 320:
		var ly := randf_range(0.0, 5.0) if randf() < 0.5 else randf_range(h - 5.0, h - 1.0)
		var lc := [Color(0.55, 0.3, 0.1), Color(0.45, 0.38, 0.15), Color(0.32, 0.2, 0.1), Color(0.7, 0.45, 0.15)][randi() % 4] as Color
		m._soft_dot(img, randf() * w, ly, 1.2, 0.8, lc, randf_range(0.4, 0.8), 0.6)
	return m._sharp_tex(img)


func _make_lawn_map(w: int, h: int) -> ImageTexture:
	# Uneven suburban lawns: greener watered patches, dry straw-coloured spots, darker under trees.
	var big: Image = m._noise_img(w, h, 0.03, 3, false)
	var spot: Image = m._noise_img(w, h, 0.09, 2, false)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var b := big.get_pixel(x, y).r
			var s := spot.get_pixel(x, y).r
			var c := Color(0.27, 0.36, 0.15).lerp(Color(0.2, 0.31, 0.12), b)
			c = c.lerp(Color(0.45, 0.42, 0.24), smoothstep(0.62, 0.8, s) * 0.7)   # dry patches
			c = c.darkened((b - 0.5) * 0.2)
			img.set_pixel(x, y, c)
	return m._sharp_tex(img)


# ---- road markings: faded double yellow, stop bar, manholes, the chalk ring

func _build_road_marks() -> void:
	var line_m: StandardMaterial3D = m._tex_mat(_make_line_texture(), false, true)
	m._ground_quad(Vector3(0, 0.006, 0.0), Vector2(48.0, 0.42), line_m, 0.0, Vector2(12.0, 1.0))
	# White stop bar + STOP at the open end of the street (-x).
	var bar_m: StandardMaterial3D = m._tex_mat(_make_line_texture(true), false, true)
	m._ground_quad(Vector3(-12.6, 0.006, -2.5), Vector2(4.6, 0.45), bar_m, PI * 0.5, Vector2(1.0, 1.0))
	var stop := Label3D.new()
	stop.text = "STOP"
	stop.font_size = 200
	stop.pixel_size = 0.006
	stop.outline_size = 0
	stop.modulate = Color(0.85, 0.84, 0.78, 0.55)
	stop.shaded = true
	stop.position = Vector3(-14.2, 0.01, -2.6)
	stop.rotation_degrees = Vector3(-90, 90, 0)
	add_child(stop)
	# Two manhole covers.
	var mh: StandardMaterial3D = m._tex_mat(_make_manhole_texture(), false, true)
	m._ground_quad(Vector3(-3.2, 0.007, 2.3), Vector2(0.85, 0.85), mh, 0.4)
	m._ground_quad(Vector3(4.6, 0.007, -2.0), Vector2(0.85, 0.85), mh, 1.3)
	# The kids chalked a "ring" in the middle of the street for the main event.
	var chalk: StandardMaterial3D = m._tex_mat(_make_chalk_texture(), false, true)
	m._ground_quad(Vector3(0.2, 0.009, 0.1), Vector2(7.2, 6.4), chalk, 0.03)
	# A sprayed C2C on the asphalt near the speakers.
	var spray: StandardMaterial3D = m._tex_mat(m._make_spray_texture(), false, true)
	m._ground_quad(Vector3(4.8, 0.011, -3.6), Vector2(2.2, 1.1), spray, -0.12)


func _make_line_texture(white := false) -> ImageTexture:
	# Worn traffic paint: double yellow (or one white bar), chipped by tires, dirt in the gaps.
	var w := 128
	var h := 32
	var nz: Image = m._noise_img(w, h, 0.08, 3)
	var chip: Image = m._noise_img(w, h, 0.35, 1)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var col := Color(0.86, 0.85, 0.78) if white else Color(0.86, 0.64, 0.18)
	for y in h:
		var stripe := 0.0
		if white:
			stripe = 1.0 if y >= 3 and y <= 28 else 0.0
		else:
			stripe = 1.0 if (y >= 5 and y <= 12) or (y >= 19 and y <= 26) else 0.0
		for x in w:
			if stripe <= 0.0:
				img.set_pixel(x, y, Color(col.r, col.g, col.b, 0.0))
				continue
			var a := clampf(0.2 + nz.get_pixel(x, y).r * 0.9, 0.0, 0.8)
			if chip.get_pixel(x, y).r > 0.68:
				a *= 0.25
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a).darkened(randf() * 0.12))
	return m._sharp_tex(img)


func _make_manhole_texture() -> ImageTexture:
	var n := 128
	var nz: Image = m._noise_img(n, n, 0.08, 3, false)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(n * 0.5, n * 0.5)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) - ctr
			var d := p.length() / (n * 0.5)
			if d > 0.98:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var nv := nz.get_pixel(x, y).r
			var c := Color(0.2, 0.19, 0.18).darkened((nv - 0.5) * 0.4)
			if d > 0.84:
				c = Color(0.3, 0.29, 0.27).darkened((nv - 0.5) * 0.3)          # the frame ring
			elif d > 0.78:
				c = Color(0.06, 0.06, 0.06)                                    # gap
			elif (int(p.x + 64.0) / 7 + int(p.y + 64.0) / 7) % 2 == 0:
				c = c.lightened(0.09)                                          # raised waffle pattern
			if absf(d - 0.42) < 0.03:
				c = c.lightened(0.12)
			c = c.lerp(Color(0.38, 0.2, 0.1), smoothstep(0.6, 0.85, nv) * 0.45)  # rust
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0 - smoothstep(0.93, 0.98, d)))
	for k in 2:   # pick holes
		var hx := ctr.x + (k * 2 - 1) * n * 0.3
		m._soft_dot(img, hx, ctr.y, 2.5, 2.0, Color(0.02, 0.02, 0.02), 0.9, 1.0)
	return m._sharp_tex(img)


func _make_chalk_texture() -> ImageTexture:
	# Wobbly sidewalk-chalk "ring": a square with corner posts, a centre "C2C", smudged by sneakers.
	var n := 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var chalk := Color(0.92, 0.9, 0.86)
	var corners: Array[Vector2] = [Vector2(22, 24), Vector2(234, 20), Vector2(236, 232), Vector2(20, 236)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		for pass_i in 2:
			var prev := a
			for s in range(1, 13):
				var q := a.lerp(b, s / 12.0) + Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
				for o: Vector2 in [Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)]:
					m._line_px(img, prev + o + Vector2(pass_i, pass_i), q + o + Vector2(pass_i, pass_i), chalk, 0.55)
				prev = q
	for c: Vector2 in corners:
		m._soft_dot(img, c.x, c.y, 9.0, 9.0, Color(0.9, 0.35, 0.45), 0.7, 3.0)   # pink chalk turnbuckles
	m._soft_text(img, "C2C", 101.0, 113.0, 5.0, Color(0.5, 0.72, 0.95), 0.6)
	var nz: Image = m._noise_img(n, n, 0.06, 3, false)
	for y in n:
		for x in n:
			var c := img.get_pixel(x, y)
			if c.a > 0.0:
				c.a *= clampf(0.15 + nz.get_pixel(x, y).r * 0.85, 0.0, 0.7)
				img.set_pixel(x, y, c)
	return m._sharp_tex(img)


# ---- the houses across the street (backdrop)

func _window(x: float, y: float, wz: float, w: float, h: float, glow: Color, shutters := Color(0, 0, 0, 0)) -> void:
	var trim := Color(0.85, 0.83, 0.77)
	var f := wz + 0.02
	m._bx("flat", Vector3(w + 0.2, h + 0.2, 0.06), Vector3(x, y, f), trim)
	m._bx("glow", Vector3(w, h, 0.06), Vector3(x, y, f + 0.03), glow)
	m._bx("flat", Vector3(0.06, h, 0.07), Vector3(x, y, f + 0.04), trim)
	m._bx("flat", Vector3(w, 0.06, 0.07), Vector3(x, y + h * 0.1, f + 0.04), trim)
	m._bx("flat", Vector3(w + 0.3, 0.07, 0.14), Vector3(x, y - h * 0.5 - 0.1, f + 0.05), trim)   # sill
	if shutters.a > 0.0:
		for s: float in [-1.0, 1.0]:
			m._bx("flat", Vector3(0.3, h + 0.15, 0.05), Vector3(x + s * (w * 0.5 + 0.27), y, f), shutters)


func _door(x: float, y0: float, wz: float, col: Color) -> void:
	var trim := Color(0.85, 0.83, 0.77)
	m._bx("flat", Vector3(1.15, 2.2, 0.06), Vector3(x, y0 + 1.1, wz + 0.02), trim)
	m._bx("flat", Vector3(0.95, 2.08, 0.07), Vector3(x, y0 + 1.04, wz + 0.03), col)
	m._bx("glow", Vector3(0.5, 0.5, 0.075), Vector3(x, y0 + 1.6, wz + 0.035), Color(0.95, 0.74, 0.42))
	m._bx("metal", Vector3(0.05, 0.05, 0.1), Vector3(x + 0.35, y0 + 1.0, wz + 0.08), Color(0.8, 0.7, 0.4))
	m._bx("glow", Vector3(0.16, 0.26, 0.14), Vector3(x + 0.8, y0 + 1.9, wz + 0.08), Color(1.0, 0.82, 0.5))   # porch lamp


func _porch(x0: float, x1: float, wz: float, deck_y: float, roof_y: float, wood: Color, stairs_x: float) -> void:
	var d := 2.2
	var front := wz + d
	var cx := (x0 + x1) * 0.5
	m._bx("wood", Vector3(x1 - x0, deck_y - LAWN_Y, d), Vector3(cx, (deck_y + LAWN_Y) * 0.5, wz + d * 0.5), wood)
	m._bx("flat", Vector3(x1 - x0, deck_y - LAWN_Y - 0.06, 0.03), Vector3(cx, (deck_y + LAWN_Y) * 0.5 - 0.03, front + 0.01), Color(0.13, 0.11, 0.09))
	for k in 2:
		var h := deck_y - LAWN_Y - 0.17 * (k + 1)
		if h > 0.02:
			m._bx("wood", Vector3(1.4, h, 0.3), Vector3(stairs_x, LAWN_Y + h * 0.5, front + 0.15 + 0.3 * k), wood.lightened(0.05 * (k + 1)))
	var rail := wood.lightened(0.15)
	for seg: Vector2 in [Vector2(x0, stairs_x - 0.75), Vector2(stairs_x + 0.75, x1)]:
		var l := seg.y - seg.x
		if l < 0.2:
			continue
		var sc := (seg.x + seg.y) * 0.5
		m._bx("wood", Vector3(l, 0.07, 0.1), Vector3(sc, deck_y + 0.9, front - 0.05), rail)
		var nb := int(l / 0.18)
		for k in nb:
			m._bx("wood", Vector3(0.045, 0.85, 0.045), Vector3(seg.x + (k + 0.5) * l / nb, deck_y + 0.45, front - 0.05), rail)
	for px: float in [x0 + 0.1, stairs_x - 0.75, stairs_x + 0.75, x1 - 0.1]:
		m._bx("wood", Vector3(0.15, roof_y - deck_y, 0.15), Vector3(px, (roof_y + deck_y) * 0.5, front - 0.08), rail)
	m._bx("shingle", Vector3(x1 - x0 + 0.5, 0.16, d + 0.5), Vector3(cx, roof_y + 0.08, wz + d * 0.5 + 0.2), Color(0.3, 0.27, 0.26), 0.0, 0.7)
	m._bx("flat", Vector3(x1 - x0 + 0.5, 0.2, 0.05), Vector3(cx, roof_y + 0.05, front + 0.45), Color(0.85, 0.83, 0.77))


func _house_shell(x0: float, x1: float, wz: float, top: float, wall_key: String, wall: Color, roof: Color, gable_front: bool) -> void:
	var depth := 8.0
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	var y0 := LAWN_Y - 0.05
	m._bx(wall_key, Vector3(w, top - y0, depth), Vector3(cx, (top + y0) * 0.5, wz - depth * 0.5), wall, 0.0, 0.6)
	m._bx("block", Vector3(w + 0.06, 0.45, 0.1), Vector3(cx, y0 + 0.22, wz + 0.02), Color(0.62, 0.6, 0.56))   # foundation
	var trim := Color(0.85, 0.83, 0.77)
	for sx: float in [x0 + 0.06, x1 - 0.06]:
		m._bx("flat", Vector3(0.14, top - y0, 0.14), Vector3(sx, (top + y0) * 0.5, wz + 0.03), trim)   # corner boards
	var st: SurfaceTool = m._st(wall_key)
	if gable_front:
		var rise := w * 0.34
		m._tri(st, Vector3(x0, top, wz), Vector3(cx, top + rise, wz), Vector3(x1, top, wz), Vector3.BACK, Vector3.RIGHT, Vector3.UP, wall, 0.6)
		var run := w * 0.5 + 0.45
		var rt := rise * run / (w * 0.5)
		var slope := atan2(rise, w * 0.5)
		var slab := sqrt(run * run + rt * rt)
		for s: float in [-1.0, 1.0]:
			var b := Basis(Vector3.BACK, -slope * s)
			m._sbox("shingle", Vector3(slab, 0.16, depth + 0.8), Transform3D(b, Vector3(cx + s * run * 0.5, top + rise + 0.08 - rt * 0.5, wz - depth * 0.5 + 0.2)), roof, 0.7)
		m._bx("flat", Vector3(0.12, 0.12, 0.08), Vector3(cx, top + rise - 0.05, wz + 0.42), trim)
	else:
		var ridge := top + 2.0
		var run := depth * 0.5 + 0.5
		var rise := (ridge - top) * run / (depth * 0.5)
		var slope := atan2(rise, run)
		var slab := sqrt(run * run + rise * rise)
		for s: float in [1.0, -1.0]:
			var b := Basis(Vector3.RIGHT, slope * s)
			m._sbox("shingle", Vector3(w + 0.8, 0.16, slab), Transform3D(b, Vector3(cx, ridge + 0.1 - rise * 0.5, wz - depth * 0.5 + s * run * 0.5)), roof, 0.7)
		for s: float in [-1.0, 1.0]:
			var x := cx + s * w * 0.5
			var p0 := Vector3(x, top, wz)
			var p1 := Vector3(x, ridge, wz - depth * 0.5)
			var p2 := Vector3(x, top, wz - depth)
			if s > 0.0:
				m._tri(st, p0, p1, p2, Vector3.RIGHT, Vector3.FORWARD, Vector3.UP, wall, 0.6)
			else:
				m._tri(st, p2, p1, p0, Vector3.LEFT, Vector3.BACK, Vector3.UP, wall, 0.6)
		m._bx("flat", Vector3(w + 0.8, 0.13, 0.13), Vector3(cx, top - 0.2, wz + 0.5), trim)   # gutter


func _bush(p: Vector3, r: float, flower: Color) -> void:
	var leaf := Color(0.14, 0.24, 0.1)
	m._cy("flat", r * 0.8, r, r * 0.6, p + Vector3(0, r * 0.3, 0), leaf, 8)
	m._cy("flat", r, r * 0.45, r * 0.55, p + Vector3(0, r * 0.88, 0), leaf.lightened(0.05), 8)
	for k in 9:   # hydrangea heads
		var a := randf() * TAU
		var rr := randf_range(0.3, 0.85) * r
		var hp := p + Vector3(cos(a) * rr, r * randf_range(0.75, 1.15), sin(a) * rr)
		m._bx("flat", Vector3(0.16, 0.13, 0.16), hp, flower.lightened(randf_range(-0.1, 0.15)), randf() * PI)


func _lawn_chair(pos: Vector3, face: Vector3, col: Color) -> void:
	var xf := Transform3D(Basis.looking_at(face), pos)
	var frame := Color(0.6, 0.61, 0.63)
	m._sbox("flat", Vector3(0.52, 0.04, 0.46), xf * Transform3D(Basis(), Vector3(0, 0.42, 0)), col)
	m._sbox("flat", Vector3(0.52, 0.55, 0.04), xf * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.72, 0.25)), col)
	for sx: float in [-0.26, 0.26]:
		m._beam("flat", xf * Vector3(sx, 0, -0.22), xf * Vector3(sx, 0.42, 0.18), 0.03, frame)
		m._beam("flat", xf * Vector3(sx, 0, 0.22), xf * Vector3(sx, 0.42, -0.18), 0.03, frame)


func _build_houses() -> void:
	var warm := Color(0.95, 0.7, 0.38)
	var warm2 := Color(0.9, 0.6, 0.3)
	var tv := Color(0.36, 0.48, 0.85)
	var dark := Color(0.06, 0.06, 0.08)
	# House A: two-storey blue-grey, gable to the street, full front porch.
	var az := -12.0
	_house_shell(-17.0, -9.0, az, 5.7, "siding", Color(0.44, 0.5, 0.56), Color(0.24, 0.22, 0.23), true)
	_window(-15.6, 4.3, az, 1.1, 1.3, warm, Color(0.12, 0.16, 0.22))
	_window(-10.4, 4.3, az, 1.1, 1.3, tv, Color(0.12, 0.16, 0.22))
	_window(-13.0, 6.75, az, 0.7, 0.7, dark)
	_window(-15.5, 1.55, az, 1.3, 1.3, warm2)
	_window(-10.5, 1.55, az, 1.3, 1.3, warm)
	_door(-13.0, 0.62, az, Color(0.45, 0.12, 0.1))
	_porch(-16.4, -9.6, az, 0.62, 3.1, Color(0.52, 0.44, 0.34), -13.0)
	_bush(Vector3(-16.6, LAWN_Y, -9.4), 0.55, Color(0.45, 0.52, 0.88))
	_bush(Vector3(-9.6, LAWN_Y, -9.5), 0.5, Color(0.82, 0.5, 0.72))
	# House B: brick ranch, garage on the right (the hoop driveway), little stoop, the party banner.
	var bz := -11.0
	_house_shell(-7.6, 3.4, bz, 3.15, "brick", Color(0.95, 0.82, 0.76), Color(0.27, 0.25, 0.24), false)
	_window(-6.0, 1.7, bz, 1.6, 1.15, warm, Color(0.16, 0.2, 0.15))
	_window(-1.2, 1.7, bz, 1.9, 1.2, warm2, Color(0.16, 0.2, 0.15))
	_door(-3.0, 0.42, bz, Color(0.16, 0.24, 0.2))
	m._bx("block", Vector3(1.8, 0.3, 1.2), Vector3(-3.0, 0.27, bz + 0.6), Color(0.7, 0.68, 0.64))   # stoop
	m._bx("siding", Vector3(2.6, 2.2, 0.08), Vector3(1.55, LAWN_Y + 1.08, bz + 0.04), Color(0.86, 0.85, 0.8), 0.0, 1.4)   # garage door
	m._bx("flat", Vector3(2.8, 0.12, 0.1), Vector3(1.55, LAWN_Y + 2.25, bz + 0.05), Color(0.85, 0.83, 0.77))
	_bush(Vector3(-6.4, LAWN_Y, -10.3), 0.5, Color(0.45, 0.5, 0.88))
	_bush(Vector3(-5.0, LAWN_Y, -10.35), 0.45, Color(0.5, 0.56, 0.9))
	_bush(Vector3(-0.6, LAWN_Y, -10.3), 0.42, Color(0.84, 0.48, 0.7))
	# The bedsheet banner over the garage door.
	var sheet_z := bz + 0.12
	m._bx("flat", Vector3(3.0, 1.0, 0.03), Vector3(1.55, 2.75, sheet_z), Color(0.9, 0.88, 0.82))
	var lines: Array[String] = ["HYDRANGEA ST.", "BLOCK PARTY"]
	var line_cols: Array[Color] = [Color(0.12, 0.2, 0.5), Color(0.72, 0.12, 0.1)]
	for li in 2:
		var lab := Label3D.new()
		lab.text = lines[li]
		lab.font_size = 52
		lab.outline_size = 0
		lab.modulate = line_cols[li]
		lab.shaded = true
		lab.position = Vector3(1.55, 2.98 - li * 0.42, sheet_z + 0.025)
		lab.rotation_degrees = Vector3(0, 0, 1.5 - li * 2.5)
		add_child(lab)
	# House C: two-storey beige, wide porch (porch light omni in _build_lights), driveway on the right.
	var cz := -11.6
	_house_shell(5.0, 14.0, cz, 5.7, "siding", Color(0.74, 0.66, 0.52), Color(0.3, 0.24, 0.22), false)
	_window(6.4, 4.3, cz, 1.1, 1.3, warm, Color(0.32, 0.18, 0.14))
	_window(9.4, 4.3, cz, 1.1, 1.3, dark, Color(0.32, 0.18, 0.14))
	_window(12.4, 4.3, cz, 1.1, 1.3, warm2, Color(0.32, 0.18, 0.14))
	_window(6.3, 1.6, cz, 1.3, 1.3, warm)
	_window(10.4, 1.6, cz, 1.3, 1.3, tv)
	_door(8.3, 0.62, cz, Color(0.18, 0.2, 0.32))
	_porch(5.4, 11.4, cz, 0.62, 3.2, Color(0.5, 0.42, 0.32), 8.3)
	m._bx("siding", Vector3(2.4, 2.2, 0.08), Vector3(12.6, LAWN_Y + 1.08, cz + 0.04), Color(0.82, 0.8, 0.74), 0.0, 1.4)
	_bush(Vector3(5.2, LAWN_Y, -9.0), 0.48, Color(0.86, 0.5, 0.7))
	# House D (far right) and E (far left), partly in shot.
	var dz := -12.6
	_house_shell(15.5, 23.0, dz, 5.5, "siding", Color(0.46, 0.52, 0.42), Color(0.22, 0.2, 0.2), true)
	_window(17.4, 1.6, dz, 1.2, 1.2, warm)
	_window(21.0, 1.6, dz, 1.2, 1.2, dark)
	_window(19.2, 4.2, dz, 1.0, 1.2, warm2)
	_door(19.2 - 1.6, 0.4, dz, Color(0.4, 0.3, 0.18))
	var ez := -12.4
	_house_shell(-27.0, -19.5, ez, 3.1, "siding", Color(0.78, 0.76, 0.7), Color(0.26, 0.24, 0.24), false)
	_window(-21.0, 1.7, ez, 1.5, 1.1, warm)
	_window(-25.6, 1.7, ez, 1.2, 1.1, tv)
	# Chain-link and board fences in the gaps between the houses.
	for g: Vector2 in [Vector2(-19.4, -17.1), Vector2(-8.9, -7.7), Vector2(3.5, 4.9), Vector2(14.1, 15.4)]:
		var fz := -12.6
		m._bx("wood", Vector3(g.y - g.x, 1.6, 0.05), Vector3((g.x + g.y) * 0.5, LAWN_Y + 0.8, fz), Color(0.5, 0.43, 0.34))
	# Lawn chairs out front (people sit in them, see the crowd).
	_lawn_chair(Vector3(-11.6, LAWN_Y, -8.3), Vector3(0.2, 0, 1), Color(0.2, 0.45, 0.3))
	_lawn_chair(Vector3(-10.5, LAWN_Y, -8.6), Vector3(0.0, 0, 1), Color(0.65, 0.25, 0.2))
	_lawn_chair(Vector3(-4.6, LAWN_Y, -8.3), Vector3(0.1, 0, 1), Color(0.22, 0.32, 0.62))
	_lawn_chair(Vector3(6.4, LAWN_Y, -8.4), Vector3(-0.2, 0, 1), Color(0.75, 0.55, 0.15))
	_lawn_chair(Vector3(10.6, LAWN_Y, -8.2), Vector3(-0.3, 0, 1), Color(0.2, 0.45, 0.3))
	# Coolers on the lawns.
	m._bx("flat", Vector3(0.7, 0.42, 0.42), Vector3(-9.6, LAWN_Y + 0.21, -7.9), Color(0.65, 0.18, 0.14), 0.3)
	m._bx("flat", Vector3(0.72, 0.08, 0.44), Vector3(-9.6, LAWN_Y + 0.44, -7.9), Color(0.85, 0.85, 0.82), 0.3)
	m._bx("flat", Vector3(0.62, 0.38, 0.4), Vector3(7.6, LAWN_Y + 0.19, -8.0), Color(0.15, 0.3, 0.6), -0.4)


func _tree(p: Vector3, h: float) -> void:
	m._cy("flat", 0.2, 0.15, h * 0.45, p + Vector3(0, h * 0.225, 0), Color(0.16, 0.12, 0.09), 7)
	var leaf := Color(0.12, 0.2, 0.09)
	for k in 4:
		var o := Vector3(randf_range(-0.9, 0.9), h * randf_range(0.55, 0.85), randf_range(-0.7, 0.7))
		var r := randf_range(1.2, 1.8)
		m._cy("flat", r * 0.55, r, r * 0.7, p + o, leaf.lightened(randf_range(-0.04, 0.08)), 9)
		m._cy("flat", r, r * 0.35, r * 0.8, p + o + Vector3(0, r * 0.75, 0), leaf.lightened(randf_range(0.0, 0.1)), 9)


func _build_trees() -> void:
	_tree(Vector3(-8.3, LAWN_Y, -9.6), 6.5)
	_tree(Vector3(4.3, LAWN_Y, -9.4), 6.0)
	_tree(Vector3(14.8, LAWN_Y, -9.3), 6.8)
	_tree(Vector3(-18.6, LAWN_Y, -9.2), 6.2)
	# Dark tree line beyond the houses, silhouetted against the dusk sky.
	for t: Vector3 in [Vector3(-22.0, 0, -24.0), Vector3(-13.0, 0, -23.0), Vector3(-5.0, 0, -25.0), Vector3(2.5, 0, -23.5),
			Vector3(9.5, 0, -24.5), Vector3(17.0, 0, -23.0), Vector3(25.0, 0, -24.0)]:
		var th := randf_range(8.0, 11.0)
		m._cy("flat", 0.3, 0.25, 2.0, t + Vector3(0, 1.0, 0), Color(0.1, 0.08, 0.06), 6)
		m._cy("flat", 3.2, 0.0, th * 0.65, t + Vector3(0, 1.6 + th * 0.32, 0), Color(0.05, 0.08, 0.06), 8)
		m._cy("flat", 2.4, 0.0, th * 0.5, t + Vector3(0, 1.6 + th * 0.68, 0), Color(0.06, 0.09, 0.07), 8)


# ---- street furniture: streetlights, hydrant, bins, mailboxes, road-closed barricade

func _streetlight(base: Vector3, out_z: float) -> void:
	var pole := Color(0.42, 0.42, 0.4)
	m._cy("metal", 0.1, 0.07, 7.0, base + Vector3(0, 3.5, 0), pole, 8)
	m._cy("metal", 0.17, 0.17, 0.35, base + Vector3(0, 0.17, 0), pole.darkened(0.2), 8)
	var top := base + Vector3(0, 6.85, 0)
	var head := base + Vector3(0.0, 6.7, out_z * 1.3)
	m._beam("metal", top, head, 0.08, pole)
	m._bx("metal", Vector3(0.4, 0.18, 0.75), head + Vector3(0, 0.02, out_z * 0.25), Color(0.5, 0.5, 0.48))
	m._bx("glow", Vector3(0.3, 0.04, 0.55), head + Vector3(0, -0.08, out_z * 0.25), Color(1.0, 0.78, 0.45))


func _bin(p: Vector3, col: Color, yaw: float) -> void:
	# Wheeled trash-day toter: tapered body, lid, wheels.
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	m._scyl("flat", 0.3, 0.36, 0.98, xf * Transform3D(Basis(), Vector3(0, 0.5, 0)), col, 4)
	m._sbox("flat", Vector3(0.62, 0.06, 0.72), xf * Transform3D(Basis(Vector3.RIGHT, -0.06), Vector3(0, 1.02, 0.02)), col.darkened(0.15))
	for s: float in [-0.25, 0.25]:
		m._scyl("flat", 0.1, 0.1, 0.06, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s, 0.1, -0.3)), Color(0.05, 0.05, 0.05), 8)


func _bag(p: Vector3, r: float) -> void:
	m._cy("flat", r, r * 0.7, r * 1.1, p + Vector3(0, r * 0.55, 0), Color(0.06, 0.06, 0.07), 7)
	m._cy("flat", r * 0.7, 0.05, r * 0.5, p + Vector3(0, r * 1.35, 0), Color(0.07, 0.07, 0.08), 7)


func _build_street_furniture() -> void:
	_streetlight(Vector3(-10.2, CURB_H, -6.3), 1.0)
	_streetlight(Vector3(10.2, CURB_H, -6.3), 1.0)
	_streetlight(Vector3(-10.0, CURB_H, 6.4), -1.0)
	_streetlight(Vector3(10.0, CURB_H, 6.4), -1.0)
	# Fire hydrant on the back sidewalk.
	var hp := Vector3(-8.5, CURB_H, -5.8)
	var red := Color(0.72, 0.16, 0.1)
	m._cy("flat", 0.16, 0.16, 0.08, hp + Vector3(0, 0.04, 0), red.darkened(0.2), 10)
	m._cy("flat", 0.12, 0.12, 0.5, hp + Vector3(0, 0.33, 0), red, 10)
	m._cy("flat", 0.14, 0.06, 0.14, hp + Vector3(0, 0.64, 0), red.lightened(0.1), 10)
	for s: float in [-1.0, 1.0]:
		m._scyl("flat", 0.05, 0.05, 0.12, Transform3D(Basis(Vector3.BACK, PI * 0.5), hp + Vector3(s * 0.16, 0.4, 0)), Color(0.8, 0.75, 0.6), 8)
	# Trash day: toters and bags at the curbs (the camera-side ones out at the corners only).
	_bin(Vector3(8.7, CURB_H, -6.0), Color(0.14, 0.32, 0.18), 0.1)
	_bin(Vector3(9.4, CURB_H, -6.1), Color(0.14, 0.24, 0.5), -0.15)
	_bag(Vector3(9.0, CURB_H, -6.75), 0.3)
	_bin(Vector3(-8.1, CURB_H, 6.15), Color(0.12, 0.12, 0.13), PI + 0.1)
	_bin(Vector3(-7.4, CURB_H, 6.2), Color(0.14, 0.24, 0.5), PI - 0.08)
	_bag(Vector3(-8.8, CURB_H, 6.0), 0.32)
	_bag(Vector3(-8.6, CURB_H, 6.5), 0.26)
	# Cluster mailbox on the front-right corner.
	var mb := Vector3(8.5, CURB_H, 6.45)
	m._bx("metal", Vector3(0.12, 0.6, 0.12), mb + Vector3(0, 0.3, 0), Color(0.3, 0.3, 0.3))
	m._bx("metal", Vector3(0.9, 0.9, 0.45), mb + Vector3(0, 1.05, 0), Color(0.55, 0.57, 0.58))
	m._bx("flat", Vector3(0.95, 0.06, 0.5), mb + Vector3(0, 1.52, 0), Color(0.4, 0.42, 0.43))
	for k in 6:
		m._bx("flat", Vector3(0.26, 0.24, 0.02), mb + Vector3(-0.29 + (k % 3) * 0.29, 0.86 + (k / 3) * 0.3, -0.235), Color(0.45, 0.47, 0.48))
	# ROAD CLOSED barricade across the open end of the street (-x).
	var bx := -16.0
	for z: float in [-2.2, 1.6]:
		for s: float in [-1.0, 1.0]:
			for e: float in [-0.7, 0.7]:
				m._beam("wood", Vector3(bx + s * 0.35, 0, z + e), Vector3(bx, 1.0, z + e * 0.9), 0.07, Color(0.6, 0.55, 0.45))
		for k in 6:   # orange / white striped board
			var col := Color(0.9, 0.42, 0.1) if k % 2 == 0 else Color(0.9, 0.88, 0.82)
			m._bx("flat", Vector3(0.05, 0.26, 0.3), Vector3(bx + 0.05, 0.9, z - 0.75 + k * 0.3), col)
	m._bx("flat", Vector3(0.04, 0.7, 1.5), Vector3(bx + 0.12, 1.45, -0.3), Color(0.72, 0.6, 0.42))   # cardboard sign
	var sign_lines: Array[String] = ["ROAD CLOSED", "BLOCK PARTY!"]
	for li in 2:
		var lab := Label3D.new()
		lab.text = sign_lines[li]
		lab.font_size = 40
		lab.outline_size = 0
		lab.modulate = Color(0.12, 0.1, 0.1) if li == 0 else Color(0.7, 0.1, 0.08)
		lab.shaded = true
		lab.position = Vector3(bx + 0.15, 1.6 - li * 0.3, -0.3)
		lab.rotation_degrees = Vector3(0, 90, -2.0 + li * 3.0)
		add_child(lab)


# ---- perches

func _build_bus_stop() -> void:
	# Bus-stop shelter on the back sidewalk; someone left the stepladder from hanging the lights
	# leaning on its front edge. Roof top 2.5: the biggest dive on the block.
	var c := Vector3(-5.0, CURB_H, -6.15)
	var w := 3.0
	var d := 1.3
	var post := Color(0.3, 0.32, 0.33)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			m._bx("metal", Vector3(0.08, 2.3, 0.08), c + Vector3(sx * w * 0.5, 1.15, sz * d * 0.5), post)
	m._bx("metal", Vector3(w + 0.2, 0.1, d + 0.2), c + Vector3(0, 2.3, 0), Color(0.36, 0.38, 0.4))
	m._bx("flat", Vector3(w + 0.24, 0.14, 0.04), c + Vector3(0, 2.32, d * 0.5 + 0.12), Color(0.2, 0.22, 0.24))
	m._bx("flat", Vector3(w - 0.1, 1.85, 0.03), c + Vector3(0, 1.2, -d * 0.5), Color(0.2, 0.26, 0.3))   # scuffed plexi back
	m._bx("flat", Vector3(w - 0.1, 0.06, 0.05), c + Vector3(0, 0.3, -d * 0.5), post)
	# Bench.
	m._bx("metal", Vector3(2.2, 0.05, 0.38), c + Vector3(0.1, 0.45, -0.35), Color(0.45, 0.47, 0.48))
	for sx: float in [-0.95, 1.15]:
		m._bx("metal", Vector3(0.05, 0.45, 0.3), c + Vector3(sx, 0.22, -0.35), post)
	# Backlit ad panel on the left end (an original poster: C2C wrestling).
	var ap := c + Vector3(-w * 0.5 + 0.02, 1.25, 0.0)
	m._bx("flat", Vector3(0.1, 1.75, 1.15), ap, Color(0.22, 0.23, 0.25))
	m._bx("glow", Vector3(0.11, 1.55, 0.95), ap, Color(0.86, 0.66, 0.42))
	var ad_lines: Array[String] = ["CITY 2 CITY", "WRESTLING", "LIVE TONITE"]
	for li in 3:
		var lab := Label3D.new()
		lab.text = ad_lines[li]
		lab.font_size = 34 if li < 2 else 26
		lab.outline_size = 6
		lab.outline_modulate = Color(0.1, 0.05, 0.03)
		lab.modulate = Color(0.75, 0.12, 0.08) if li != 1 else Color(0.12, 0.12, 0.35)
		lab.shaded = false
		lab.position = ap + Vector3(0.07, 0.45 - li * 0.32, 0)
		lab.rotation_degrees = Vector3(0, 90, 0)
		add_child(lab)
	m._wall_decal(m._make_tag_texture("C2C", Color(0.86, 0.84, 0.78), Color(0.1, 0.16, 0.42), Color(1.0, 1.0, 1.0)),
		c + Vector3(0.8, 0.85, -d * 0.5 + 0.02), Vector2(1.0, 0.5), Vector3.BACK)
	# Bus stop sign.
	var sp := Vector3(-3.15, CURB_H, -5.55)
	m._bx("metal", Vector3(0.06, 2.6, 0.06), sp + Vector3(0, 1.3, 0), post)
	m._bx("flat", Vector3(0.5, 0.55, 0.03), sp + Vector3(0, 2.4, 0.04), Color(0.18, 0.35, 0.65))
	var bus := Label3D.new()
	bus.text = "BUS\nSTOP"
	bus.font_size = 30
	bus.outline_size = 0
	bus.modulate = Color(0.95, 0.95, 0.92)
	bus.shaded = true
	bus.position = sp + Vector3(0, 2.4, 0.06)
	add_child(bus)
	# The stepladder: feet on the road, top against the roof edge.
	var lb := Vector3(-4.2, 0.0, -4.85)
	var lt := Vector3(-4.2, 2.42, -5.42)
	for s: float in [-0.22, 0.22]:
		m._beam("metal", lb + Vector3(s, 0, 0), lt + Vector3(s, 0, 0), 0.06, Color(0.75, 0.72, 0.5))
	for k in 8:
		m._bx("metal", Vector3(0.44, 0.04, 0.05), lb.lerp(lt, (k + 0.6) / 8.6), Color(0.75, 0.72, 0.5))
	add_perch("bus stop roof", "shelter", Vector3(-4.6, 2.5, -6.0), Vector3(-4.2, 0.0, -4.35),
		footprint(Vector2(c.x, c.z), Vector2(w * 0.5 + 0.1, d * 0.5 + 0.1), "THE BUS STOP", "Bus Stop Crash", 250, "metal_hit"))


func _build_hoop() -> void:
	# Portable basketball hoop at the end of house B's driveway; kids play out in the street.
	var b := Vector3(2.55, CURB_H, -6.5)
	m._bx("flat", Vector3(1.0, 0.45, 0.7), b + Vector3(0, 0.225, 0), Color(0.12, 0.12, 0.13))
	m._bx("flat", Vector3(0.7, 0.1, 0.5), b + Vector3(0, 0.5, 0), Color(0.18, 0.18, 0.2))
	var pole_top := b + Vector3(0, 3.1, 0.35)
	m._beam("metal", b + Vector3(0, 0.4, 0), pole_top, 0.12, Color(0.25, 0.26, 0.28))
	var board := Vector3(2.55, 3.3, -5.4)
	m._beam("metal", pole_top, board + Vector3(0, -0.1, -0.05), 0.07, Color(0.25, 0.26, 0.28))
	m._bx("flat", Vector3(1.12, 0.74, 0.05), board, Color(0.92, 0.92, 0.9))
	m._bx("flat", Vector3(1.18, 0.8, 0.03), board + Vector3(0, 0, -0.03), Color(0.1, 0.1, 0.1))
	var sq := Color(0.85, 0.3, 0.1)
	var fz := board.z + 0.03
	m._bx("flat", Vector3(0.46, 0.035, 0.01), Vector3(board.x, 3.38, fz), sq)
	m._bx("flat", Vector3(0.46, 0.035, 0.01), Vector3(board.x, 3.06, fz), sq)
	for s: float in [-1.0, 1.0]:
		m._bx("flat", Vector3(0.035, 0.32, 0.01), Vector3(board.x + s * 0.215, 3.22, fz), sq)
	var rim_c := Vector3(board.x, 3.05, board.z + 0.28)
	var pts: Array[Vector3] = []
	for k in 12:
		var a := TAU * k / 12.0
		pts.append(rim_c + Vector3(cos(a) * 0.23, 0, sin(a) * 0.23))
	for k in 12:
		m._beam("metal", pts[k], pts[(k + 1) % 12], 0.025, Color(0.9, 0.35, 0.1))
		var lo := rim_c + Vector3(cos(TAU * (k + 0.5) / 12.0) * 0.13, -0.38, sin(TAU * (k + 0.5) / 12.0) * 0.13)
		m._beam("flat", pts[k], lo, 0.012, Color(0.85, 0.85, 0.82))
	m._beam("metal", rim_c + Vector3(0, 0, -0.23), Vector3(board.x, 3.0, fz), 0.04, Color(0.9, 0.35, 0.1))
	# A ball parked on the sidewalk.
	m._cy("flat", 0.12, 0.12, 0.2, b + Vector3(0.75, 0.1, 0.3), Color(0.75, 0.35, 0.12), 10)
	obstacles.append(footprint(Vector2(b.x, b.z), Vector2(0.52, 0.36), "THE HOOP", "Hoop Crash", 200, "metal_hit"))


func _table(p: Vector3, w: float, d: float, cloth_col: Color, gingham: bool) -> void:
	# Folding table (top 0.74 above p.y) with a tablecloth hanging down the sides.
	var top_y := p.y + 0.74
	var key := "street_cloth" if gingham else "flat"
	m._bx(key, Vector3(w + 0.04, 0.03, d + 0.04), Vector3(p.x, top_y, p.z), cloth_col, 0.0, 2.0)
	m._bx(key, Vector3(w + 0.05, 0.28, 0.02), Vector3(p.x, top_y - 0.14, p.z + d * 0.5 + 0.02), cloth_col.darkened(0.08), 0.0, 2.0)
	m._bx(key, Vector3(w + 0.05, 0.28, 0.02), Vector3(p.x, top_y - 0.14, p.z - d * 0.5 - 0.02), cloth_col.darkened(0.12), 0.0, 2.0)
	for s: float in [-1.0, 1.0]:
		m._bx(key, Vector3(0.02, 0.28, d + 0.05), Vector3(p.x + s * (w * 0.5 + 0.02), top_y - 0.14, p.z), cloth_col.darkened(0.1), 0.0, 2.0)
		for e: float in [-1.0, 1.0]:
			m._beam("metal", Vector3(p.x + s * (w * 0.5 - 0.12), p.y, p.z + e * (d * 0.5 - 0.06)),
				Vector3(p.x + s * (w * 0.5 - 0.12), top_y - 0.02, p.z + e * (d * 0.5 - 0.06)), 0.03, Color(0.3, 0.3, 0.31))


func _build_party() -> void:
	# 1) Snack table out in the street by the curb (perch, top 0.75): Grandma's pie, chips, soda.
	var st := Vector3(-1.8, 0.0, -4.2)
	_table(st, 1.8, 0.74, Color(1, 1, 1), true)
	var ty := 0.775
	m._cy("flat", 0.15, 0.15, 0.05, st + Vector3(-0.5, ty + 0.025, 0.05), Color(0.78, 0.6, 0.34), 12)   # the pie
	m._cy("flat", 0.12, 0.12, 0.015, st + Vector3(-0.5, ty + 0.055, 0.05), Color(0.48, 0.18, 0.18), 12)
	for k in 3:
		m._bx("flat", Vector3(0.26, 0.012, 0.02), st + Vector3(-0.5, ty + 0.065, -0.06 + k * 0.06), Color(0.82, 0.64, 0.36))
	m._cy("flat", 0.16, 0.2, 0.08, st + Vector3(0.05, ty + 0.04, -0.05), Color(0.82, 0.22, 0.12), 10)   # chip bowl
	m._cy("flat", 0.15, 0.15, 0.02, st + Vector3(0.05, ty + 0.085, -0.05), Color(0.9, 0.72, 0.3), 10)
	for k in 3:
		var bc: Color = [Color(0.15, 0.4, 0.15), Color(0.6, 0.25, 0.08), Color(0.25, 0.1, 0.06)][k]
		m._cy("flat", 0.055, 0.055, 0.3, st + Vector3(0.45 + k * 0.13, ty + 0.15, 0.15), bc, 8)
		m._cy("flat", 0.025, 0.025, 0.04, st + Vector3(0.45 + k * 0.13, ty + 0.32, 0.15), Color(0.85, 0.85, 0.85), 6)
	m._cy("flat", 0.045, 0.04, 0.22, st + Vector3(0.6, ty + 0.11, -0.18), Color(0.75, 0.12, 0.1), 8)   # red cups
	m._cy("flat", 0.12, 0.12, 0.05, st + Vector3(-0.2, ty + 0.025, -0.22), Color(0.92, 0.9, 0.86), 10)   # paper plates
	add_perch("snack table", "table", Vector3(-1.8, 0.75, -4.2), Vector3(-1.8, 0.0, -3.15),
		footprint(Vector2(st.x, st.z), Vector2(0.93, 0.4), "THE SNACK TABLE", "Snack Table Crash", 200, "wood_hit"))

	# Food table and grill on the sidewalk behind it.
	var ft := Vector3(-1.4, CURB_H, -6.25)
	_table(ft, 2.0, 0.76, Color(0.85, 0.82, 0.74), false)
	for k in 3:
		m._bx("metal", Vector3(0.45, 0.08, 0.3), ft + Vector3(-0.6 + k * 0.55, 0.81, 0.0), Color(0.75, 0.75, 0.78))
	m._cy("flat", 0.17, 0.17, 0.4, ft + Vector3(0.75, 0.97, -0.15), Color(0.9, 0.45, 0.1), 10)   # orange drink cooler
	m._cy("flat", 0.18, 0.18, 0.06, ft + Vector3(0.75, 1.2, -0.15), Color(0.92, 0.9, 0.86), 10)
	var gp := Vector3(0.15, CURB_H, -6.35)
	m._cy("flat", 0.3, 0.38, 0.32, gp + Vector3(0, 0.85, 0), Color(0.07, 0.07, 0.08), 10)
	m._cy("flat", 0.38, 0.22, 0.24, gp + Vector3(0, 1.15, 0), Color(0.08, 0.08, 0.09), 10)
	m._cy("glow", 0.3, 0.3, 0.02, gp + Vector3(0, 1.02, 0), Color(1.0, 0.4, 0.1), 10)
	for k in 3:
		var a3 := TAU * k / 3.0 + 0.3
		m._beam("flat", gp + Vector3(cos(a3) * 0.35, 0, sin(a3) * 0.35), gp + Vector3(0, 0.75, 0), 0.04, Color(0.07, 0.07, 0.08))

	# 2) DJ booth: table with black cloth, decks, mixer, laptop, crate of records.
	var dj := Vector3(4.0, CURB_H, -6.0)
	m._bx("flat", Vector3(1.7, 0.74, 0.75), dj + Vector3(0, 0.37, 0), Color(0.06, 0.06, 0.07))
	m._bx("flat", Vector3(1.72, 0.03, 0.77), dj + Vector3(0, 0.755, 0), Color(0.1, 0.1, 0.11))
	for s: float in [-1.0, 1.0]:
		m._bx("flat", Vector3(0.48, 0.08, 0.38), dj + Vector3(s * 0.55, 0.81, 0), Color(0.18, 0.18, 0.2))
		m._cy("flat", 0.16, 0.16, 0.02, dj + Vector3(s * 0.55, 0.86, 0), Color(0.04, 0.04, 0.04), 12)
		m._cy("glow", 0.025, 0.025, 0.025, dj + Vector3(s * 0.55, 0.875, 0), Color(0.9, 0.2, 0.15), 6)
	m._bx("flat", Vector3(0.3, 0.07, 0.36), dj + Vector3(0, 0.81, 0), Color(0.22, 0.22, 0.24))
	for k in 4:
		m._bx("glow", Vector3(0.025, 0.012, 0.025), dj + Vector3(-0.09 + k * 0.06, 0.85, 0.12), [Color(0.2, 1.0, 0.3), Color(0.2, 1.0, 0.3), Color(1.0, 0.8, 0.1), Color(1.0, 0.2, 0.1)][k])
	m._sbox("flat", Vector3(0.38, 0.26, 0.015), Transform3D(Basis(Vector3.RIGHT, 0.3), dj + Vector3(0.0, 0.97, -0.22)), Color(0.55, 0.56, 0.58))   # laptop lid (screen faces the DJ)
	m._sbox("glow", Vector3(0.05, 0.05, 0.005), Transform3D(Basis(Vector3.RIGHT, 0.3), dj + Vector3(0.0, 0.98, -0.21)), Color(0.85, 0.85, 0.95))
	m._bx("wood", Vector3(0.4, 0.32, 0.4), dj + Vector3(1.1, 0.16, 0.25), Color(0.6, 0.48, 0.3))   # record crate
	for k in 6:
		m._bx("flat", Vector3(0.32, 0.31, 0.012), dj + Vector3(1.1, 0.3, 0.12 + k * 0.05), Color(0.1 + randf() * 0.5, 0.1 + randf() * 0.3, 0.1 + randf() * 0.3))
	m._beam("metal", dj + Vector3(-1.05, 0, 0.2), dj + Vector3(-1.05, 1.45, 0.3), 0.025, Color(0.15, 0.15, 0.16))   # mic stand
	m._cy("flat", 0.03, 0.04, 0.12, dj + Vector3(-1.05, 1.5, 0.32), Color(0.2, 0.2, 0.22), 8)
	m._cy("flat", 0.2, 0.2, 0.02, dj + Vector3(-1.05, 0.01, 0.2), Color(0.12, 0.12, 0.13), 10)
	# Speaker on a pole stand to the left of the booth, and the stage light tripod on the right.
	var ps := Vector3(5.4, CURB_H, -6.35)
	for k in 3:
		var a := TAU * k / 3.0 + 0.5
		m._beam("metal", ps + Vector3(cos(a) * 0.45, 0, sin(a) * 0.45), ps + Vector3(0, 0.9, 0), 0.03, Color(0.15, 0.15, 0.16))
	m._beam("metal", ps + Vector3(0, 0.8, 0), ps + Vector3(0, 1.9, 0), 0.04, Color(0.15, 0.15, 0.16))
	_speaker_box(ps + Vector3(0, 2.25, 0), Vector3(0.5, 0.72, 0.42), 0.17)
	var tp := Vector3(7.4, CURB_H, -6.15)
	for k in 3:
		var a := TAU * k / 3.0 + 0.2
		m._beam("metal", tp + Vector3(cos(a) * 0.5, 0, sin(a) * 0.5), tp + Vector3(0, 1.2, 0), 0.03, Color(0.15, 0.15, 0.16))
	m._beam("metal", tp + Vector3(0, 1.1, 0), tp + Vector3(0, 2.65, 0), 0.04, Color(0.15, 0.15, 0.16))
	var lamp_xf := Transform3D(Basis.looking_at(Vector3(-0.5, 0.0, 0.4) - Vector3(7.4, 2.95, -6.15)), Vector3(7.4, 2.95, -6.15))
	m._scyl("flat", 0.16, 0.16, 0.36, lamp_xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO), Color(0.08, 0.08, 0.09), 10)
	m._scyl("glow", 0.13, 0.13, 0.02, lamp_xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, -0.19)), Color(1.0, 0.6, 0.85), 10)
	# A fog machine puffing at the curb.
	m._bx("flat", Vector3(0.45, 0.25, 0.3), Vector3(6.6, CURB_H + 0.13, -5.75), Color(0.1, 0.1, 0.11))

	# 3) The speaker stack in the gutter (perch, top 1.8): sub, mid cabinet, horn on top.
	var sk := Vector3(5.9, 0.0, -4.75)
	_speaker_box(sk + Vector3(0, 0.4, 0), Vector3(1.0, 0.8, 0.75), 0.3)
	_speaker_box(sk + Vector3(0, 1.15, 0.02), Vector3(0.92, 0.7, 0.68), 0.22)
	m._bx("flat", Vector3(0.72, 0.3, 0.56), sk + Vector3(0, 1.65, 0.03), Color(0.07, 0.07, 0.08))
	m._bx("flat", Vector3(0.5, 0.17, 0.02), sk + Vector3(0, 1.65, 0.32), Color(0.16, 0.16, 0.17))
	m._wall_decal(m._make_tag_texture("C2C", Color(0.78, 0.16, 0.1), Color(0.06, 0.05, 0.05), Color(0.98, 0.78, 0.5)),
		sk + Vector3(-0.51, 0.45, 0.0), Vector2(0.7, 0.35), Vector3.LEFT)
	add_perch("speaker stack", "speakers", Vector3(5.9, 1.8, -4.75), Vector3(5.9, 0.0, -3.6),
		footprint(Vector2(sk.x, sk.z), Vector2(0.52, 0.4), "THE SPEAKERS", "Speaker Stack Crash", 250, "metal_hit"))


func _speaker_box(c: Vector3, size: Vector3, cone_r: float) -> void:
	var cab := Color(0.07, 0.07, 0.08)
	m._bx("flat", size, c, cab)
	var fz := c.z + size.z * 0.5
	m._bx("flat", Vector3(size.x - 0.06, size.y - 0.06, 0.01), Vector3(c.x, c.y, fz + 0.003), Color(0.13, 0.13, 0.14))   # grille cloth
	var cone_xf := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(c.x, c.y - size.y * 0.08, fz + 0.012))
	m._scyl("flat", cone_r, cone_r, 0.015, cone_xf, Color(0.2, 0.2, 0.21), 14)
	m._scyl("flat", cone_r * 0.75, cone_r * 0.75, 0.02, cone_xf, Color(0.04, 0.04, 0.045), 14)
	m._scyl("metal", cone_r * 0.22, cone_r * 0.22, 0.03, cone_xf, Color(0.4, 0.4, 0.42), 10)
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			m._bx("metal", Vector3(0.07, 0.07, 0.07), c + Vector3(sx * (size.x * 0.5 - 0.02), sy * (size.y * 0.5 - 0.02), size.z * 0.5 - 0.02), Color(0.5, 0.5, 0.52))


func _wheel(xf: Transform3D, p: Vector3, r: float, w: float) -> void:
	var rot := Basis(Vector3.BACK, PI * 0.5)
	m._scyl("flat", r, r, w, xf * Transform3D(rot, p), Color(0.04, 0.04, 0.04), 12)
	m._scyl("metal", r * 0.55, r * 0.55, w + 0.02, xf * Transform3D(rot, p), Color(0.55, 0.55, 0.57), 10)
	m._scyl("flat", r * 0.2, r * 0.2, w + 0.04, xf * Transform3D(rot, p), Color(0.2, 0.2, 0.2), 8)


func _build_sedan() -> void:
	# Faded teal 90s sedan parked on the left edge of the street, nose to the camera; roof perch 1.46.
	var pos := Vector3(-8.25, 0.0, 1.0)
	var xf := Transform3D(Basis(), pos)
	var paint := Color(0.2, 0.4, 0.42)
	var glass := Color(0.06, 0.08, 0.1)
	var chrome := Color(0.62, 0.62, 0.64)
	var L := func(v: Vector3) -> Transform3D: return xf * Transform3D(Basis(), v)
	m._sbox("street_paint", Vector3(1.8, 0.56, 4.5), L.call(Vector3(0, 0.62, 0)), paint)
	m._sbox("street_paint", Vector3(1.74, 0.06, 1.3), L.call(Vector3(0, 0.92, 1.55)), paint.lightened(0.04))    # hood
	m._sbox("street_paint", Vector3(1.74, 0.06, 0.9), L.call(Vector3(0, 0.92, -1.75)), paint.lightened(0.04))   # trunk
	m._sbox("flat", Vector3(1.62, 0.42, 1.5), L.call(Vector3(0, 1.13, -0.2)), glass)                          # side glass
	m._sbox("street_paint", Vector3(1.56, 0.07, 1.45), L.call(Vector3(0, 1.425, -0.2)), paint.darkened(0.05))  # roof
	m._sbox("flat", Vector3(1.56, 0.03, 0.78), xf * Transform3D(Basis(Vector3.RIGHT, 0.64), Vector3(0, 1.16, 0.83)), glass)    # windshield
	m._sbox("flat", Vector3(1.56, 0.03, 0.7), xf * Transform3D(Basis(Vector3.RIGHT, -0.78), Vector3(0, 1.16, -1.18)), glass)   # rear glass
	for sx: float in [-1.0, 1.0]:
		m._sbox("street_paint", Vector3(0.06, 0.44, 0.07), L.call(Vector3(sx * 0.79, 1.13, 0.52)), paint.darkened(0.1))   # pillars
		m._sbox("street_paint", Vector3(0.06, 0.44, 0.07), L.call(Vector3(sx * 0.79, 1.13, -0.92)), paint.darkened(0.1))
		m._sbox("flat", Vector3(0.03, 0.05, 4.3), L.call(Vector3(sx * 0.905, 0.62, 0)), Color(0.12, 0.12, 0.12))           # rub strip
		m._sbox("flat", Vector3(0.02, 0.5, 0.02), L.call(Vector3(sx * 0.905, 0.65, 0.12)), Color(0.08, 0.1, 0.1))         # door seam
		m._sbox("flat", Vector3(0.02, 0.5, 0.02), L.call(Vector3(sx * 0.905, 0.65, -1.0)), Color(0.08, 0.1, 0.1))
		m._sbox("metal", Vector3(0.04, 0.04, 0.16), L.call(Vector3(sx * 0.91, 0.82, -0.05)), chrome)                   # handles
		m._sbox("flat", Vector3(0.12, 0.1, 0.16), L.call(Vector3(sx * 0.95, 1.0, 0.55)), paint.darkened(0.2))           # mirrors
		m._sbox("flat", Vector3(0.36, 0.16, 0.05), L.call(Vector3(sx * 0.6, 0.72, 2.23)), Color(0.85, 0.85, 0.78))      # headlights
		m._sbox("flat", Vector3(0.34, 0.14, 0.05), L.call(Vector3(sx * 0.6, 0.74, -2.23)), Color(0.55, 0.06, 0.05))     # taillights
		for sz: float in [-1.4, 1.4]:
			m._sbox("flat", Vector3(0.04, 0.36, 0.86), L.call(Vector3(sx * 0.902, 0.42, sz)), Color(0.03, 0.03, 0.03))     # wheel arch
			_wheel(xf, Vector3(sx * 0.8, 0.31, sz), 0.31, 0.22)
	m._sbox("flat", Vector3(0.012, 0.5, 1.05), L.call(Vector3(-0.906, 0.65, 0.65)), Color(0.48, 0.47, 0.44))    # primer door
	m._sbox("metal", Vector3(1.86, 0.16, 0.12), L.call(Vector3(0, 0.4, 2.27)), chrome)
	m._sbox("metal", Vector3(1.86, 0.16, 0.12), L.call(Vector3(0, 0.4, -2.27)), chrome)
	m._sbox("flat", Vector3(0.9, 0.18, 0.03), L.call(Vector3(0, 0.66, 2.255)), Color(0.08, 0.08, 0.08))       # grille
	m._sbox("flat", Vector3(0.32, 0.16, 0.02), L.call(Vector3(0, 0.6, -2.26)), Color(0.9, 0.9, 0.86))         # plate
	add_perch("car roof", "car", Vector3(-8.25, 1.46, 0.8), Vector3(-6.45, 0.0, 0.8),
		footprint(Vector2(pos.x, pos.z), Vector2(0.95, 2.3), "THE CAR", "Car Door Crash", 250, "metal_hit"))


func _build_pickup() -> void:
	# Two-tone farm pickup (Dusty drove in from the country) on the right edge, nose to the back,
	# tailgate dropped toward the camera. Bed perch 0.95; neighbours sit on the tailgate.
	var pos := Vector3(8.3, 0.0, 0.0)
	var xf := Transform3D(Basis(Vector3.UP, PI), pos)   # local +z (the nose) points to world -z
	var body := Color(0.5, 0.15, 0.1)
	var cream := Color(0.82, 0.78, 0.66)
	var glass := Color(0.06, 0.08, 0.1)
	var chrome := Color(0.62, 0.62, 0.64)
	var L := func(v: Vector3) -> Transform3D: return xf * Transform3D(Basis(), v)
	m._sbox("street_paint", Vector3(1.95, 0.55, 5.3), L.call(Vector3(0, 0.66, 0.0)), body)                 # lower body
	m._sbox("street_paint", Vector3(1.9, 0.16, 1.35), L.call(Vector3(0, 1.0, 1.95)), body.lightened(0.04))   # hood
	m._sbox("street_paint", Vector3(1.85, 0.5, 1.55), L.call(Vector3(0, 1.17, 0.5)), body)                 # cab lower
	m._sbox("flat", Vector3(1.82, 0.42, 1.4), L.call(Vector3(0, 1.62, 0.45)), glass)                      # cab glass
	m._sbox("street_paint", Vector3(1.8, 0.1, 1.45), L.call(Vector3(0, 1.88, 0.42)), cream)                 # cab roof
	m._sbox("flat", Vector3(1.75, 0.03, 0.55), xf * Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0, 1.6, 1.25)), glass)
	for sx: float in [-1.0, 1.0]:
		m._sbox("street_paint", Vector3(0.07, 0.45, 0.08), L.call(Vector3(sx * 0.89, 1.62, 1.12)), cream)    # pillars
		m._sbox("street_paint", Vector3(0.07, 0.45, 0.1), L.call(Vector3(sx * 0.89, 1.62, -0.25)), cream)
		m._sbox("street_paint", Vector3(0.05, 0.12, 5.2), L.call(Vector3(sx * 0.985, 0.82, 0.0)), cream)       # two-tone stripe
		m._sbox("flat", Vector3(0.12, 0.12, 0.18), L.call(Vector3(sx * 1.02, 1.5, 1.15)), chrome)              # mirrors
		m._sbox("flat", Vector3(0.3, 0.2, 0.05), L.call(Vector3(sx * 0.68, 0.82, 2.66)), Color(0.85, 0.85, 0.78))
		m._sbox("flat", Vector3(0.1, 0.3, 0.05), L.call(Vector3(sx * 0.9, 0.95, -2.62)), Color(0.55, 0.06, 0.05))
		m._sbox("street_paint", Vector3(0.1, 0.45, 2.3), L.call(Vector3(sx * 0.925, 1.17, -1.45)), body)        # bed sides
		m._sbox("metal", Vector3(0.14, 0.04, 2.3), L.call(Vector3(sx * 0.925, 1.41, -1.45)), chrome.darkened(0.2))
		m._beam("metal", L.call(Vector3(sx * 0.88, 1.36, -2.55)).origin, L.call(Vector3(sx * 0.82, 0.97, -3.05)).origin, 0.025, chrome)   # tailgate chains
		for sz: float in [-1.7, 1.75]:
			m._sbox("flat", Vector3(0.04, 0.44, 1.0), L.call(Vector3(sx * 0.98, 0.5, sz)), Color(0.03, 0.03, 0.03))
			_wheel(xf, Vector3(sx * 0.86, 0.38, sz), 0.38, 0.26)
	m._sbox("flat", Vector3(1.75, 0.04, 2.3), L.call(Vector3(0, 0.95, -1.45)), Color(0.12, 0.11, 0.1))        # bed floor
	m._sbox("street_paint", Vector3(1.95, 0.45, 0.1), L.call(Vector3(0, 1.17, -0.32)), body)                    # bed front wall
	m._sbox("street_paint", Vector3(1.75, 0.07, 0.48), L.call(Vector3(0, 0.93, -2.84)), body.darkened(0.1))      # tailgate (down)
	m._sbox("flat", Vector3(0.4, 0.015, 0.2), L.call(Vector3(-0.5, 0.97, -2.84)), Color(0.45, 0.25, 0.12))      # rust patch
	m._sbox("metal", Vector3(1.6, 0.36, 0.06), L.call(Vector3(0, 0.75, 2.64)), chrome)                          # grille
	m._sbox("metal", Vector3(2.0, 0.18, 0.14), L.call(Vector3(0, 0.42, 2.7)), chrome)
	m._sbox("metal", Vector3(2.0, 0.14, 0.14), L.call(Vector3(0, 0.38, -2.68)), chrome.darkened(0.25))
	m._sbox("flat", Vector3(0.5, 0.3, 0.32), L.call(Vector3(0.4, 1.12, -0.65)), Color(0.15, 0.3, 0.6))         # cooler in the bed
	m._sbox("flat", Vector3(0.52, 0.05, 0.34), L.call(Vector3(0.4, 1.29, -0.65)), Color(0.9, 0.9, 0.86))
	add_perch("pickup bed", "truck", Vector3(8.3, 0.95, 1.55), Vector3(6.5, 0.0, 1.55),
		footprint(Vector2(pos.x, 0.2), Vector2(1.0, 2.9), "THE PICKUP", "Pickup Truck Crash", 250, "metal_hit"))


func _build_minivan() -> void:
	# Somebody's minivan parallel-parked along the back curb past the sedan (out of the fight).
	var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-13.6, 0.0, -4.05))
	var paint := Color(0.55, 0.57, 0.6)
	var glass := Color(0.06, 0.08, 0.1)
	var L := func(v: Vector3) -> Transform3D: return xf * Transform3D(Basis(), v)
	m._sbox("street_paint", Vector3(1.9, 0.8, 4.9), L.call(Vector3(0, 0.75, 0)), paint)
	m._sbox("flat", Vector3(1.86, 0.55, 3.6), L.call(Vector3(0, 1.42, -0.4)), glass)
	m._sbox("street_paint", Vector3(1.8, 0.1, 3.6), L.call(Vector3(0, 1.74, -0.4)), paint.darkened(0.05))
	m._sbox("flat", Vector3(1.8, 0.03, 0.8), xf * Transform3D(Basis(Vector3.RIGHT, 0.75), Vector3(0, 1.4, 1.65)), glass)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.55, 1.55]:
			_wheel(xf, Vector3(sx * 0.85, 0.33, sz), 0.33, 0.22)


# ---- string lights between the streetlights

func _hang(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)


func _build_string_lights() -> void:
	var bl := Vector3(-10.2, 4.3, -6.3)
	var br := Vector3(10.2, 4.3, -6.3)
	var fl := Vector3(-10.0, 4.7, 6.4)
	var fr := Vector3(10.0, 4.7, 6.4)
	var strands: Array = [[bl, br, 0.75], [bl, fr, 1.0], [br, fl, 1.0], [bl, fl, 0.6], [br, fr, 0.6],
		[Vector3(-13.0, 3.0, -9.8), bl, 0.4], [Vector3(8.3, 3.2, -9.4), br, 0.45]]
	var cols: Array[Color] = [Color(0.95, 0.72, 0.42), Color(0.9, 0.66, 0.38), Color(0.95, 0.72, 0.42), Color(0.85, 0.6, 0.3),
		Color(0.8, 0.3, 0.22), Color(0.45, 0.65, 0.38), Color(0.42, 0.5, 0.78), Color(0.9, 0.55, 0.22), Color(0.85, 0.4, 0.6)]
	var wire := Color(0.05, 0.05, 0.05)
	for sd: Array in strands:
		var a: Vector3 = sd[0]
		var b: Vector3 = sd[1]
		var sag: float = sd[2]
		var segs := 10
		var prev := a
		for k in range(1, segs + 1):
			var p := _hang(a, b, sag, float(k) / segs)
			m._beam("flat", prev, p, 0.022, wire)
			prev = p
		var nb := int(a.distance_to(b) / 0.7)
		for k in nb:
			var bp := _hang(a, b, sag, (k + 0.5) / nb) - Vector3(0, 0.07, 0)
			_bulb_xforms.append(Transform3D(Basis(), bp))
			_bulb_cols.append(cols[randi() % cols.size()])
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
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


# ---- grime, custom batches

func _build_grime() -> void:
	var x := ROAD_X
	# Dirt in the gutters along both curbs, and where the sidewalk meets the lawn.
	m._grime_wall(Vector3(-x, 0, ROAD_Z0), Vector3(x, 0, ROAD_Z0), Vector3.BACK, CURB_H, 0.5, 0.5, 0.45)
	m._grime_wall(Vector3(-x, 0, ROAD_Z1), Vector3(x, 0, ROAD_Z1), Vector3.FORWARD, CURB_H, 0.5, 0.5, 0.45)
	# House fronts.
	for hw: Vector3 in [Vector3(-17.0, -9.0, -12.0), Vector3(-7.6, 3.4, -11.0), Vector3(5.0, 14.0, -11.6), Vector3(15.5, 23.0, -12.6)]:
		m._grime_wall(Vector3(hw.x, LAWN_Y, hw.z), Vector3(hw.y, LAWN_Y, hw.z), Vector3.BACK, 0.7, 0.4, 0.45, 0.35)
	# Contact shadows under the cars and props in the street.
	m._grime_wall(Vector3(-7.33, 0, -1.3), Vector3(-7.33, 0, 3.3), Vector3.RIGHT, 0.3, 0.45, 0.3, 0.5)
	m._grime_wall(Vector3(7.3, 0, -2.7), Vector3(7.3, 0, 2.7), Vector3.LEFT, 0.3, 0.45, 0.3, 0.5)
	m._grime_wall(Vector3(5.38, 0, -4.36), Vector3(6.42, 0, -4.36), Vector3.BACK, 0.4, 0.4, 0.4, 0.45)
	m._grime_wall(Vector3(-6.4, CURB_H, -6.8), Vector3(-3.6, CURB_H, -6.8), Vector3.BACK, 0.5, 0.5, 0.35, 0.3)
	m._flush_grime()


func _flush_custom() -> void:
	# Our own batch keys get their own materials (main's _batch_mat only knows its built-in keys).
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.roughness = 0.32
	paint.metallic_specular = 0.8
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.vertex_color_is_srgb = true
	cloth.roughness = 1.0
	cloth.albedo_texture = _make_gingham_texture()
	cloth.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mats := {"street_paint": paint, "street_cloth": cloth}
	var batches: Dictionary = m._batches
	for key: String in mats:
		if not batches.has(key):
			continue
		var st: SurfaceTool = batches[key]
		batches.erase(key)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mats[key]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _make_gingham_texture() -> ImageTexture:
	# Red-and-white picnic gingham with a little weave.
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var red := Color(0.72, 0.1, 0.1)
	var white := Color(0.93, 0.91, 0.87)
	for y in n:
		for x in n:
			var a := (x / 8) % 2 == 0
			var b := (y / 8) % 2 == 0
			var c := white
			if a and b:
				c = red
			elif a or b:
				c = red.lerp(white, 0.45)
			if (x + y) % 2 == 0:
				c = c.darkened(0.05)
			img.set_pixel(x, y, c)
	return m._sharp_tex(img)


# ---- the neighbours watching (main.build_crowd turns these into the billboard crowd)

func _fan(p: Vector3, person: String, lit := 0.55, bob := 1.0) -> void:
	crowd_spots.append({"pos": p, "person": person, "lit": lit, "bob": bob})


func _build_crowd_spots() -> void:
	# ~40 neighbours. Nobody in the street between the cars (x -7..7, z -5..5) or on a perch top.
	# Seated: pos = where the dangling feet end (~0.53 below the seat).
	var w := CURB_H + 0.015
	# Back sidewalk, between the props.
	for spot: Vector3 in [Vector3(-9.3, w, -5.9), Vector3(-7.4, w, -5.75), Vector3(-6.9, w, -6.6), Vector3(-2.7, w, -5.65),
			Vector3(-0.6, w, -5.65), Vector3(0.6, w, -5.7), Vector3(1.4, w, -5.6), Vector3(6.2, w, -5.65), Vector3(8.2, w, -5.65),
			Vector3(9.9, w, -5.7), Vector3(-11.5, w, -5.8), Vector3(11.6, w, -5.9)]:
		_fan(spot + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), "stand", 0.62)
	_fan(Vector3(4.0, w, -6.75), "filmer", 0.75, 1.6)        # the DJ behind the decks
	_fan(Vector3(-5.6, 0.1, -6.5), "sit_cup", 0.55)            # on the bus stop bench (seat 0.62)
	_fan(Vector3(-4.6, 0.1, -6.5), "sit", 0.55)
	# Out on the lawns (some in lawn chairs).
	for c: Vector3 in [Vector3(-11.6, LAWN_Y, -8.25), Vector3(-10.5, LAWN_Y, -8.55), Vector3(-4.6, LAWN_Y, -8.25),
			Vector3(6.4, LAWN_Y, -8.35), Vector3(10.6, LAWN_Y, -8.15)]:
		_fan(c + Vector3(0, 0.42 - 0.53 + 0.02, 0.05), "sit" if randf() < 0.5 else "sit_cup", 0.5)
	for spot: Vector3 in [Vector3(-14.5, LAWN_Y, -8.4), Vector3(-7.0, LAWN_Y, -8.0), Vector3(-2.5, LAWN_Y, -7.9), Vector3(-0.8, LAWN_Y, -8.6),
			Vector3(3.2, LAWN_Y, -8.1), Vector3(8.6, LAWN_Y, -7.8), Vector3(12.5, LAWN_Y, -8.6), Vector3(17.0, LAWN_Y, -8.0)]:
		_fan(spot, "stand", 0.5)
	# On the porches.
	for spot: Vector3 in [Vector3(-15.2, 0.62, -10.6), Vector3(-11.0, 0.62, -10.9), Vector3(-10.1, 0.62, -10.3)]:
		_fan(spot, "stand", 0.55)
	for spot: Vector3 in [Vector3(6.2, 0.62, -10.4), Vector3(7.1, 0.62, -10.9), Vector3(10.2, 0.62, -10.2), Vector3(10.9, 0.62, -11.0)]:
		_fan(spot, "stand", 0.6)
	_fan(Vector3(-3.5, 0.42, -10.35), "stand", 0.55)           # on house B's stoop
	_fan(Vector3(9.4, 3.36, -10.2), "filmer", 0.5, 1.4)        # up on house C's porch roof, filming
	# Leaning on the cars: on the sedan's hood and trunk, on the pickup's tailgate.
	_fan(Vector3(-8.25, 0.42, 3.45), "sit_cup", 0.6)
	_fan(Vector3(-8.5, 0.38, -1.45), "sit", 0.55)
	_fan(Vector3(7.95, 0.42, 3.05), "sit", 0.6)
	_fan(Vector3(8.7, 0.42, 3.1), "sit_cup", 0.6)
	# Standing in the street past the cars, and at the far camera-side corners.
	for spot: Vector3 in [Vector3(-9.8, 0, -0.3), Vector3(-10.4, 0, 2.2), Vector3(-11.5, 0, 0.6), Vector3(-9.6, 0, 4.6),
			Vector3(9.9, 0, -1.8), Vector3(10.4, 0, 0.9), Vector3(10.0, 0, 4.2), Vector3(11.2, 0, -0.4)]:
		_fan(spot + Vector3(randf_range(-0.15, 0.15), 0.015, randf_range(-0.15, 0.15)), "stand", 0.55)
	for spot: Vector3 in [Vector3(-9.2, w, 6.3), Vector3(9.3, w, 6.2)]:
		_fan(spot, "stand", 0.5)

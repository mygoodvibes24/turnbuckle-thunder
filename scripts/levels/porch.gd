extends "res://scripts/levels/level_base.gd"
## THE FRONT PORCH (level id "porch"): Mom's front yard on a warm afternoon (story ch2 "Noise
## Complaint"). They fight on the front lawn, the concrete walkway and the sidewalk edge; the house
## with its wide wooden porch (steps, railing, swing, screen door) is the backdrop along -z, the
## driveway with Mom's parked wagon and the garage on +x, Mr. Hollis's white picket fence and prize
## hydrangeas on -x (his house beyond), sidewalk, curb and street on the camera side (+z, kept low).
## Fighting area x -7..6.8, z -5..5; ground y 0; everything level-local (= ring_root = world).
## Helpers on main: see the header of scripts/levels/backyard.gd.

const HOUSE_Z := -8.6                               # front wall of Mom's house
const DECK_Y := 0.85                                # porch deck top
const PORCH_X0 := -6.0
const PORCH_X1 := 1.8
const PORCH_FRONT := -5.7
const STEP_X := -2.0                                # porch steps centre (walkway runs from here to the sidewalk)
const ROOF_Y := 3.1                                 # porch roof underside
const FENCE_X := -7.5                               # Mr. Hollis's picket fence
const HEDGE_X := 7.7                                # hedge between the driveway and the right neighbour
const WALK_RECT := Rect2(-2.7, -4.8, 1.4, 9.2)      # walkway: steps -> sidewalk
const DRIVE_RECT := Rect2(3.7, -8.6, 3.6, 14.4)     # driveway: garage -> street
const SIDEWALK_RECT := Rect2(-40.0, 4.4, 80.0, 1.4) # sidewalk z 4.4..5.8, curb at 5.8
const STEPS_RECT := Rect2(-2.75, -5.8, 1.5, 1.05)
const LAWN_RECT := Rect2(-13.0, -8.6, 26.0, 13.0)   # painted lawn quad: x -13..13, z -8.6..4.4
const CAR_POS := Vector3(5.3, 0.0, -2.0)

const LAWN_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform sampler2D map : source_color, filter_linear_mipmap;
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 detail_scale = vec2(26.0, 13.0);

void fragment() {
	vec3 m = texture(map, UV).rgb;
	vec3 d = texture(detail, UV * detail_scale).rgb;
	ALBEDO = m * d * 2.0;
	ROUGHNESS = 0.95;
}
"""

const DAY_SKY_SHADER := """
shader_type sky;

uniform vec3 sun_dir = vec3(0.45, 0.62, 0.64);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -0.3, 1.0);
	// Warm hazy afternoon: pale gold at the horizon, soft blue overhead.
	vec3 top = vec3(0.27, 0.45, 0.76);
	vec3 hor = vec3(0.9, 0.82, 0.66);
	vec3 col = mix(hor, top, pow(smoothstep(0.0, 0.65, h), 0.65));
	col = mix(col, vec3(0.62, 0.58, 0.5), smoothstep(0.0, -0.15, h));
	// Soft fair-weather clouds.
	if (d.y > 0.02) {
		vec2 uv = d.xz / (d.y + 0.15) * 1.6;
		float c = vnoise(uv) * 0.55 + vnoise(uv * 2.3 + 4.1) * 0.3 + vnoise(uv * 5.1 + 9.7) * 0.15;
		c = smoothstep(0.52, 0.8, c) * smoothstep(0.02, 0.2, d.y);
		col = mix(col, vec3(1.0, 0.96, 0.9), c * 0.75);
	}
	// Sun glow (the sun itself sits behind the camera, over the street).
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += vec3(1.0, 0.75, 0.45) * pow(s, 6.0) * 0.35;
	col = mix(col, vec3(1.0, 0.97, 0.88), smoothstep(0.9993, 0.9996, s));
	COLOR = col;
}
"""

## Direction the afternoon sunlight travels (from the sun, high over the street behind the camera,
## toward the house): faces are lit and shadows fall back-left onto the lawn and the porch.
const SUN_TRAVEL := Vector3(-0.45, -0.62, -0.64)

var m = null   # main.gd (helpers)


func _init() -> void:
	display_name = "THE FRONT PORCH"
	description = "Mom's front yard and porch steps. Mr. Hollis is watching his hydrangeas. Closely."
	time_of_day = "day"
	preview_color = Color(0.5, 0.42, 0.3)
	yard_bounds = Rect2(-7.0, -5.0, 13.8, 10.0)
	cam_clamp = Rect2(-5.0, -4.0, 9.8, 7.3)
	cam_height = 3.0
	cam_back = 5.7
	default_surface = "grass"
	surfaces = [{"rect": STEPS_RECT, "kind": "wood"}, {"rect": WALK_RECT, "kind": "concrete"},
		{"rect": DRIVE_RECT, "kind": "concrete"}, {"rect": SIDEWALK_RECT, "kind": "concrete"}]
	spawn_p1 = Vector3(-1.4, 0.0, 0.6)
	spawn_p2 = Vector3(2.0, 0.0, 0.0)


func build(main_node: Node) -> void:
	super(main_node)
	m = main_node
	perches.clear()
	obstacles.clear()
	_build_lights()
	_build_ground()
	_build_house()
	_build_porch()
	_build_garage()
	_build_hollis()
	_build_neighbors()
	_build_yard_props()
	_build_perches()
	_build_car()
	_build_grime()
	_build_crowd_spots()   # (also builds the kids' bikes, so before the flush)
	m._flush_batches()
	# Weapons: two folding lawn chairs set out on the grass, trash day (the can by the curb), a 2x4
	# by Hollis's fence and Mom's old folding table leaning on the porch skirt.
	item_spawns = [
		{"kind": "chair", "pos": Vector3(-4.3, 0.0, -3.4), "yaw": PI * 0.25},
		{"kind": "chair", "pos": Vector3(1.5, 0.0, 3.3), "yaw": -PI * 0.35},
		{"kind": "trash_can", "pos": Vector3(6.4, 0.0, 3.9), "yaw": 0.0},
		{"kind": "plank", "pos": Vector3(-6.4, 0.0, -1.2), "yaw": 0.2},
		{"kind": "table", "pos": Vector3(-4.6, 0.0, -4.9), "yaw": 0.0},   # top faces +z (into the yard)
	]


# ---- small geometry helpers

## A rough sphere (stacked cylinder rings) in the merged batch: bushes, tree canopies, flower heads.
func _blob(key: String, c: Vector3, r: float, col: Color, rings := 4, segs := 8, squash := 1.0) -> void:
	for i in rings:
		var a0 := -PI * 0.5 + PI * i / rings
		var a1 := -PI * 0.5 + PI * (i + 1) / rings
		var r0 := cos(a0) * r
		var r1 := cos(a1) * r
		var y0 := sin(a0) * r * squash
		var y1 := sin(a1) * r * squash
		var shade := lerpf(0.72, 1.08, float(i) / maxf(1.0, rings - 1.0))
		m._cy(key, r0, r1, y1 - y0, c + Vector3(0, (y0 + y1) * 0.5, 0), Color(col.r * shade, col.g * shade, col.b * shade), segs)


func _gable(cx: float, hw: float, wall_z: float, depth: float, top: float, ridge: float, wall_col: Color, roof_col: Color) -> void:
	# Walls (front at wall_z, running back toward -z) and a gable roof with its ridge along x.
	m._bx("siding", Vector3(2 * hw, top, 0.3), Vector3(cx, top * 0.5, wall_z - 0.15), wall_col, 0.0, 0.6)
	for s: float in [-1.0, 1.0]:
		m._bx("siding", Vector3(0.3, top, depth), Vector3(cx + s * hw, top * 0.5, wall_z - depth * 0.5), wall_col, 0.0, 0.6)
	var st: SurfaceTool = m._st("siding")
	for s: float in [-1.0, 1.0]:
		var x := cx + s * (hw + 0.15)
		var p0 := Vector3(x, top, wall_z)
		var p1 := Vector3(x, ridge, wall_z - depth * 0.5)
		var p2 := Vector3(x, top, wall_z - depth)
		if s > 0.0:
			m._tri(st, p0, p1, p2, Vector3(1, 0, 0), Vector3.FORWARD, Vector3.UP, wall_col, 0.6)
		else:
			m._tri(st, p2, p1, p0, Vector3(-1, 0, 0), Vector3.BACK, Vector3.UP, wall_col, 0.6)
	var run := depth * 0.5 + 0.6
	var rise := (ridge - top) * run / (depth * 0.5)
	var slope := atan2(rise, run)
	var slab_len := sqrt(run * run + rise * rise)
	for s: float in [1.0, -1.0]:
		var zc := wall_z - depth * 0.5 + s * run * 0.5
		var yc := ridge + 0.1 - rise * 0.5
		m._sbox("shingle", Vector3(2 * hw + 1.0, 0.16, slab_len), Transform3D(Basis(Vector3.RIGHT, slope * s), Vector3(cx, yc, zc)), roof_col, 0.7)


func _window(cx: float, cy: float, wz: float, w: float, h: float, trim: Color, shutters: Color, curtain := Color(0.0, 0.0, 0.0, 0.0)) -> void:
	# Daytime window: trim, dark sky-reflecting glass with a pale diagonal glint, muntins, shutters.
	m._bx("flat", Vector3(w + 0.2, h + 0.2, 0.06), Vector3(cx, cy, wz), trim)
	m._bx("flat", Vector3(w, h, 0.06), Vector3(cx, cy, wz + 0.02), Color(0.13, 0.17, 0.22))
	if curtain.a > 0.0:
		m._bx("flat", Vector3(w * 0.3, h * 0.92, 0.04), Vector3(cx - w * 0.33, cy, wz + 0.035), curtain)
		m._bx("flat", Vector3(w * 0.3, h * 0.92, 0.04), Vector3(cx + w * 0.33, cy, wz + 0.035), curtain)
	m._sbox("flat", Vector3(w * 0.22, h * 1.05, 0.02), Transform3D(Basis(Vector3.BACK, -0.5), Vector3(cx + w * 0.12, cy, wz + 0.05)), Color(0.42, 0.5, 0.58))
	m._bx("flat", Vector3(0.05, h, 0.07), Vector3(cx, cy, wz + 0.06), trim)
	m._bx("flat", Vector3(w, 0.05, 0.07), Vector3(cx, cy, wz + 0.06), trim)
	m._bx("flat", Vector3(w + 0.3, 0.07, 0.14), Vector3(cx, cy - h * 0.5 - 0.12, wz + 0.06), trim)  # sill
	if shutters.a > 0.0:
		for s: float in [-1.0, 1.0]:
			m._bx("flat", Vector3(0.32, h + 0.15, 0.05), Vector3(cx + s * (w * 0.5 + 0.28), cy, wz), shutters)


func _picket_run(a: Vector3, b: Vector3, fh: float, col: Color) -> void:
	# Painted white picket fence (pointed pickets, two rails, posts).
	var d := b - a
	var run_len := d.length()
	if run_len < 0.1:
		return
	var dir := d / run_len
	var yaw := atan2(-dir.z, dir.x)
	var count := maxi(1, int(run_len / 0.15))
	for k in count:
		var p := a + dir * ((k + 0.5) * run_len / count)
		var tint := randf_range(-0.04, 0.03)
		var c := Color(col.r + tint, col.g + tint, col.b + tint)
		var lean := randf_range(-0.015, 0.015)
		var bas := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean)
		m._sbox("wood", Vector3(0.085, fh, 0.025), Transform3D(bas, p + Vector3(0, fh * 0.5, 0)), c)
		m._sbox("wood", Vector3(0.06, 0.06, 0.024), Transform3D(bas * Basis(Vector3.BACK, PI * 0.25), p + Vector3(0, fh, 0)), c)
	var posts := maxi(1, int(run_len / 2.0))
	for k in posts + 1:
		var pp := a + dir * (k * run_len / posts)
		m._bx("wood", Vector3(0.1, fh + 0.1, 0.1), pp + Vector3(0, (fh + 0.1) * 0.5, 0), col.darkened(0.06), yaw)
		m._bx("wood", Vector3(0.14, 0.05, 0.14), pp + Vector3(0, fh + 0.12, 0), col, yaw)
	var side := Vector3(dir.z, 0, -dir.x)
	for ry: float in [fh * 0.78, fh * 0.25]:
		m._bx("wood", Vector3(run_len, 0.07, 0.04), (a + b) * 0.5 + Vector3(0, ry, 0) + side * 0.03, col.darkened(0.1), yaw)


func _hydrangea(c: Vector3, r: float, bloom: Color) -> void:
	# Big mophead hydrangea: a dark leafy mound studded with round flower heads.
	_blob("flat", c + Vector3(0, r * 0.75, 0), r, Color(0.13, 0.27, 0.1), 4, 9, 0.8)
	for i in 13:
		var a := randf() * TAU
		var e := randf_range(0.15, 1.2)
		var hp := c + Vector3(0, r * 0.75, 0) + Vector3(cos(a) * cos(e) * r, sin(e) * r * 0.8 + 0.04, sin(a) * cos(e) * r)
		var bc := bloom.lerp(Color(bloom.b, bloom.g, bloom.r), randf_range(0.0, 0.25)).lightened(randf_range(-0.05, 0.15))
		_blob("flat", hp, randf_range(0.12, 0.17), bc, 3, 6)


func _bike(base: Vector3, yaw: float, col: Color, lying := false) -> void:
	# A kid's BMX bike: standing upright (yaw = heading) or dropped flat on the grass.
	var b := Basis(Vector3.UP, yaw)
	if lying:
		b = b * Basis(Vector3.FORWARD, PI * 0.5 - 0.08)
	var xf := Transform3D(b, base + (Vector3(0, 0.05, 0) if lying else Vector3(0, 0.27, 0)))
	var tyre := Color(0.05, 0.05, 0.05)
	for wz: float in [-0.45, 0.45]:
		m._scyl("flat", 0.27, 0.27, 0.05, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0, wz)), tyre, 12)
		m._scyl("metal", 0.2, 0.2, 0.06, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0, 0, wz)), Color(0.7, 0.7, 0.72), 10)
	var fr: Array = [[Vector3(0, 0, -0.45), Vector3(0, 0.3, -0.25)], [Vector3(0, 0.3, -0.25), Vector3(0, 0.33, 0.25)],
		[Vector3(0, 0, -0.45), Vector3(0, 0.0, 0.05)], [Vector3(0, 0.0, 0.05), Vector3(0, 0.33, 0.25)],
		[Vector3(0, 0.0, 0.05), Vector3(0, 0.38, -0.12)], [Vector3(0, 0.33, 0.25), Vector3(0, 0, 0.45)]]
	for f: Array in fr:
		var p0: Vector3 = f[0]
		var p1: Vector3 = f[1]
		m._beam("flat", xf * p0, xf * p1, 0.035, col)
	m._beam("metal", xf * Vector3(-0.28, 0.5, 0.25), xf * Vector3(0.28, 0.5, 0.25), 0.03, Color(0.65, 0.65, 0.68))  # bars
	m._beam("metal", xf * Vector3(0, 0.33, 0.25), xf * Vector3(0, 0.5, 0.25), 0.03, Color(0.65, 0.65, 0.68))
	m._sbox("flat", Vector3(0.1, 0.05, 0.22), xf * Transform3D(Basis(), Vector3(0, 0.42, -0.12)), Color(0.08, 0.08, 0.08))  # seat


# ---- lights / environment

func _build_lights() -> void:
	# The sun's real shadow: a narrow, far-away key spot along the sun direction (main gives it
	# the one shadow map), pooling a touch of extra warm light over the fighting area. The
	# general sunlight is main.moon turned into a warm sun in setup_environment().
	var aim := Vector3(0.0, 0.0, -0.5)
	var pos := aim - SUN_TRAVEL.normalized() * 30.0
	var key := SpotLight3D.new()
	key.transform = Transform3D(Basis.looking_at(aim - pos), pos)
	key.spot_angle = 22.0
	key.spot_angle_attenuation = 0.6
	key.spot_range = 50.0
	key.spot_attenuation = 0.0
	key.light_energy = 1.25
	key.light_specular = 0.5
	key.light_color = Color(1.0, 0.9, 0.74)
	key.shadow_enabled = false
	add_child(key)
	key_light = key
	# Warm bounce light under the porch roof so the deck and the crowd on it aren't a black hole.
	var porch := OmniLight3D.new()
	porch.position = Vector3(-2.0, 2.5, -7.0)
	porch.omni_range = 6.0
	porch.light_energy = 0.7
	porch.light_color = Color(1.0, 0.86, 0.66)
	porch.omni_attenuation = 1.2
	add_child(porch)
	# Soft cool sky fill from the camera side (keeps the shadow side of faces from going muddy).
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.0, 6.0, 9.0)
	fill.omni_range = 18.0
	fill.light_energy = 0.45
	fill.light_color = Color(0.72, 0.8, 1.0)
	fill.omni_attenuation = 0.8
	add_child(fill)


func setup_environment(env: Environment) -> void:
	# Warm afternoon: blue-gold sky, bright neutral ambient, light haze, the moon becomes the sun.
	if m != null and m.sky_mat != null:
		var sh := Shader.new()
		sh.code = DAY_SKY_SHADER
		m.sky_mat.shader = sh
		m.sky_mat.set_shader_parameter("sun_dir", -SUN_TRAVEL.normalized())
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.68, 0.74)
	env.ambient_light_energy = 0.62
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.74, 0.66)
	env.fog_light_energy = 1.0
	env.fog_density = 0.007
	env.fog_sky_affect = 0.0
	if m != null and m.moon != null:
		var sun: DirectionalLight3D = m.moon
		sun.transform = Transform3D(Basis.looking_at(SUN_TRAVEL), Vector3(0, 10, 0))
		sun.light_color = Color(1.0, 0.9, 0.74)
		sun.light_energy = 1.15
		sun.light_specular = 0.6
		sun.shadow_enabled = false
	if m != null and m.post_mat != null:
		var pm: ShaderMaterial = m.post_mat
		pm.set_shader_parameter("sepia", 0.2)
		pm.set_shader_parameter("contrast", 1.12)
		pm.set_shader_parameter("saturation", 0.95)
		pm.set_shader_parameter("green_desat", 0.35)
		pm.set_shader_parameter("bloom_threshold", 0.82)
		pm.set_shader_parameter("bloom_strength", 0.28)
		pm.set_shader_parameter("vignette", 0.18)


# ---- ground

func _make_front_lawn_map() -> ImageTexture:
	# Painted map of both front lawns (x -13..13, z -8.6..4.4): Hollis's side (x < -7.5) is a
	# crisp, striped, golf-green carpet; Mom's is patchy, sun-dried, worn bare where they always
	# fight, with bald spots at the foot of the perches and a dark wet ring round the sprinkler.
	var w := 256
	var h := 128
	var big: Image = m._noise_img(w, h, 0.02, 3, false)
	var mid: Image = m._noise_img(w, h, 0.08, 2, false)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var dark := Color(0.15, 0.26, 0.07)
	var lush := Color(0.25, 0.39, 0.1)
	var dry := Color(0.42, 0.38, 0.18)
	var dirt := Color(0.37, 0.28, 0.17)
	var ppm := w / LAWN_RECT.size.x
	for y in h:
		var wz := LAWN_RECT.position.y + (y + 0.5) / ppm
		for x in w:
			var wx := LAWN_RECT.position.x + (x + 0.5) / ppm
			var b: float = big.get_pixel(x, y).r
			var md: float = mid.get_pixel(x, y).r
			var c: Color
			if wx < FENCE_X:
				# Hollis: perfect diagonal mowing stripes, no weeds, no mercy.
				var band := sin((wx + wz) / 0.9 * PI)
				c = dark.lerp(lush, 0.45 + smoothstep(-0.2, 0.2, band) * 0.4 + (md - 0.5) * 0.15)
				c = c.lightened(0.04)
			else:
				var band2 := sin((wz + sin(wx * 0.5) * 0.2) / 1.3 * PI)
				c = dark.lerp(lush, clampf(0.3 + smoothstep(-0.3, 0.3, band2) * 0.3 + (md - 0.5) * 0.5, 0.0, 1.0))
				c = c.lerp(dry, smoothstep(0.5, 0.85, b) * 0.65)
				var d := Vector2((wx - 0.0) / 4.8, (wz - 0.0) / 3.3).length()
				var wear := (1.0 - smoothstep(0.25, 1.05, d)) * (0.55 + (md - 0.5) * 0.9)
				c = c.lerp(dry.lerp(dirt, 0.4), clampf(wear * 0.65, 0.0, 0.75))
				c = c.lerp(dirt, smoothstep(0.55, 0.85, wear + (b - 0.5) * 0.5) * 0.8)
			# Shade along the house foundation and under the porch edge.
			c = c.darkened((1.0 - smoothstep(0.0, 1.2, wz - HOUSE_Z)) * 0.3)
			c = c.darkened((1.0 - smoothstep(0.0, 0.5, absf(wx - FENCE_X))) * 0.25)
			img.set_pixel(x, y, c)
	var to_px := func(px: float, pz: float) -> Vector2:
		return Vector2((px - LAWN_RECT.position.x) * ppm, (pz - LAWN_RECT.position.y) * ppm)
	# Bald spots at the perch approaches and the steps, random patches, a wet ring round the sprinkler.
	for p: Vector2 in [Vector2(-2.0, -4.6), Vector2(0.0, -4.4), Vector2(2.35, -4.5), Vector2(-4.0, 2.9), Vector2(3.9, -2.3)]:
		var q: Vector2 = to_px.call(p.x, p.y)
		m._soft_dot(img, q.x, q.y, randf_range(6.0, 9.0), randf_range(4.0, 6.0), dirt, 0.7, 4.0)
	for i in 12:
		var q2: Vector2 = to_px.call(randf_range(-7.0, 3.5), randf_range(-5.0, 4.0))
		m._soft_dot(img, q2.x, q2.y, randf_range(2.0, 5.0), randf_range(2.0, 4.0), dirt if randf() < 0.5 else dry, 0.5, 2.0)
	var sp: Vector2 = to_px.call(-4.2, 1.0)
	m._soft_dot(img, sp.x, sp.y, 26.0, 22.0, Color(0.08, 0.18, 0.06), 0.45, 12.0)
	m._soft_dot(img, sp.x, sp.y, 4.0, 3.0, Color(0.2, 0.15, 0.1), 0.5, 2.0)
	# The bike's flattened-grass trail toward the driveway.
	var x0 := 3.6
	while x0 > 1.0:
		var q3: Vector2 = to_px.call(x0, 2.3 + sin(x0 * 1.3) * 0.15)
		m._soft_dot(img, q3.x, q3.y, 1.6, 0.9, dry, 0.35, 1.0)
		x0 -= 0.12
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _make_asphalt_texture() -> ImageTexture:
	# Sun-baked street asphalt: speckled aggregate, tar-snake crack seals, oil drips.
	var n := 128
	var mot: Image = m._noise_img(n, n, 0.05, 3)
	var grit: Image = m._noise_img(n, n, 0.7, 1)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var g := 0.3 + (mot.get_pixel(x, y).r - 0.5) * 0.12 + (grit.get_pixel(x, y).r - 0.5) * 0.18
			if randf() < 0.06:
				g += randf_range(0.08, 0.2)
			img.set_pixel(x, y, Color(g * 1.02, g, g * 0.95))
	for i in 4:
		m._crack(img, Vector2(randf() * n, randf() * n), randf() * TAU, randi_range(8, 16), 4.0, Color(0.06, 0.06, 0.06))
	for i in 3:
		m._soft_dot(img, randf() * n, randf() * n, randf_range(4.0, 9.0), randf_range(3.0, 7.0), Color(0.08, 0.08, 0.09), 0.35, 3.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_ground() -> void:
	var far: StandardMaterial3D = m._tex_mat(m._make_grass_detail())
	far.albedo_color = Color(0.3, 0.42, 0.16)
	far.uv1_scale = Vector3(60, 60, 1)
	far.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._plane(Vector2(120, 120), Vector3(0, -0.13, 0), far)
	# Both front lawns in one painted quad.
	var sh := Shader.new()
	sh.code = LAWN_SHADER
	var lm := ShaderMaterial.new()
	lm.shader = sh
	lm.set_shader_parameter("map", _make_front_lawn_map())
	lm.set_shader_parameter("detail", m._make_grass_detail())
	lm.set_shader_parameter("detail_scale", Vector2(26.0, 13.0))
	m._ground_quad(Vector3(LAWN_RECT.get_center().x, 0.0, LAWN_RECT.get_center().y), LAWN_RECT.size, lm)
	# Walkway, driveway (tyre tracks along the car's axis), sidewalk.
	var wm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 1))
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(WALK_RECT.get_center().x, 0.016, WALK_RECT.get_center().y), WALK_RECT.size, wm, 0.0, Vector2(0.47, 3.1))
	var dm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 4, true))
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(DRIVE_RECT.get_center().x, 0.018, DRIVE_RECT.get_center().y), Vector2(DRIVE_RECT.size.y, DRIVE_RECT.size.x), dm, PI * 0.5, Vector2(2.4, 0.6))
	var sm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 2))
	sm.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(SIDEWALK_RECT.get_center().x, 0.014, SIDEWALK_RECT.get_center().y), SIDEWALK_RECT.size, sm, 0.0, Vector2(13.3, 0.233))
	# Curb, gutter and the street (a step down).
	var curb := Color(0.7, 0.68, 0.63)
	m._bx("block", Vector3(80.0, 0.24, 0.2), Vector3(0, -0.1, SIDEWALK_RECT.end.y + 0.1), curb, 0.0, 0.5)
	var am: StandardMaterial3D = m._tex_mat(_make_asphalt_texture())
	am.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(0, -0.11, 12.0), Vector2(80.0, 12.0), am, 0.0, Vector2(24.0, 3.6))
	m._bx("flat", Vector3(80.0, 0.01, 0.12), Vector3(0, -0.1, 12.0), Color(0.85, 0.7, 0.2))  # faded centre line
	# Lawn edging: little scalloped brick border along the walkway.
	for s: float in [-1.0, 1.0]:
		var ex := WALK_RECT.get_center().x + s * (WALK_RECT.size.x * 0.5 + 0.06)
		var z := WALK_RECT.position.y + 0.1
		while z < WALK_RECT.end.y - 0.1:
			m._bx("brick", Vector3(0.1, 0.07, 0.22), Vector3(ex, 0.035, z + 0.11), Color(0.85, 0.7, 0.62))
			z += 0.25


# ---- Mom's house

func _build_house() -> void:
	var wall_z := HOUSE_Z
	var siding := Color(0.6, 0.64, 0.52)      # faded sage
	var trim := Color(0.88, 0.86, 0.8)
	var shutter := Color(0.25, 0.32, 0.26)
	_gable(-2.8, 5.4, wall_z, 7.4, 5.6, 7.9, siding, Color(0.32, 0.28, 0.26))
	m._bx("brick", Vector3(11.1, 0.55, 0.36), Vector3(-2.8, 0.27, wall_z - 0.12), Color(1, 1, 1))  # foundation
	m._bx("flat", Vector3(11.8, 0.14, 0.16), Vector3(-2.8, 5.3, wall_z + 0.62), trim)              # gutter
	m._bx("flat", Vector3(0.1, 5.2, 0.1), Vector3(-8.05, 2.6, wall_z + 0.1), trim.darkened(0.15))  # downspout
	m._bx("brick", Vector3(0.9, 2.6, 0.9), Vector3(-6.4, 7.6, wall_z - 2.6), Color(0.9, 0.82, 0.8))  # chimney
	# Upstairs windows (one with a box fan, one with Tank's flag as a curtain).
	var wf := wall_z + 0.02
	for ux: float in [-6.4, -4.0, -0.4, 1.6]:
		_window(ux, 4.3, wf, 1.1, 1.2, trim, shutter)
	m._bx("flat", Vector3(0.9, 0.5, 0.06), Vector3(-0.4, 3.95, wf + 0.07), Color(0.75, 0.74, 0.7))  # box fan in the sash
	m._cy("flat", 0.2, 0.2, 0.04, Vector3(-0.4, 3.95, wf + 0.1), Color(0.2, 0.2, 0.22), 10)
	m._bx("flat", Vector3(0.95, 1.05, 0.04), Vector3(1.6, 4.3, wf + 0.04), Color(0.6, 0.12, 0.1))   # flag curtain
	m._bx("flat", Vector3(0.95, 0.12, 0.045), Vector3(1.6, 4.4, wf + 0.05), Color(0.9, 0.85, 0.7))
	# Downstairs: picture window left of the door, kitchen window right, both behind the porch.
	_window(-4.6, 2.05, wf, 1.8, 1.25, trim, shutter, Color(0.75, 0.62, 0.42))
	_window(0.4, 2.05, wf, 1.2, 1.1, trim, shutter, Color(0.85, 0.82, 0.74))
	# Front door (red) behind the screen door, with the porch light and house numbers.
	var dx := STEP_X
	m._bx("flat", Vector3(1.15, 2.2, 0.06), Vector3(dx, DECK_Y + 1.1, wf), trim)
	m._bx("flat", Vector3(0.95, 2.05, 0.07), Vector3(dx, DECK_Y + 1.03, wf + 0.01), Color(0.55, 0.14, 0.1))
	m._bx("flat", Vector3(0.35, 0.45, 0.075), Vector3(dx, DECK_Y + 1.6, wf + 0.02), Color(0.2, 0.24, 0.3))  # door window
	# Screen door: aluminium frame, mesh, kick plate, the spring.
	var sz := wf + 0.1
	var alu := Color(0.72, 0.72, 0.7)
	for sx: float in [-0.46, 0.46]:
		m._bx("metal", Vector3(0.05, 2.05, 0.04), Vector3(dx + sx, DECK_Y + 1.03, sz), alu)
	for sy: float in [0.03, 1.0, 2.04]:
		m._bx("metal", Vector3(0.96, 0.05, 0.04), Vector3(dx, DECK_Y + sy, sz), alu)
	m._bx("flat", Vector3(0.88, 1.85, 0.01), Vector3(dx, DECK_Y + 1.05, sz - 0.005), Color(0.18, 0.19, 0.2, 1.0))
	m._bx("metal", Vector3(0.88, 0.32, 0.02), Vector3(dx, DECK_Y + 0.2, sz + 0.01), Color(0.6, 0.6, 0.58))
	m._bx("flat", Vector3(0.12, 0.2, 0.08), Vector3(dx + 0.82, DECK_Y + 1.9, wf + 0.06), Color(0.16, 0.14, 0.1))  # porch light
	m._bx("glow", Vector3(0.08, 0.12, 0.08), Vector3(dx + 0.82, DECK_Y + 1.86, wf + 0.1), Color(0.85, 0.8, 0.62))
	for i in 3:
		m._bx("flat", Vector3(0.1, 0.16, 0.02), Vector3(dx - 0.85 + i * 0.13, DECK_Y + 1.85, wf + 0.04), Color(0.1, 0.1, 0.1))
	# Black mailbox on the wall by the door? No: Mom's is the post box at the curb (_build_yard_props).


func _build_porch() -> void:
	var wall_z := HOUSE_Z
	var wood := Color(0.56, 0.44, 0.32)
	var paint := Color(0.86, 0.84, 0.78)     # white-painted rails and posts, chipped by the wood grain
	var front := PORCH_FRONT
	var dz := front - wall_z
	var cx := (PORCH_X0 + PORCH_X1) * 0.5
	var pw := PORCH_X1 - PORCH_X0
	# Deck, fascia, lattice skirt.
	m._bx("wood", Vector3(pw, 0.1, dz), Vector3(cx, DECK_Y - 0.05, (wall_z + front) * 0.5), wood)
	m._bx("wood", Vector3(pw + 0.06, 0.18, 0.05), Vector3(cx, DECK_Y - 0.1, front + 0.02), paint)
	m._bx("flat", Vector3(pw, DECK_Y - 0.15, 0.04), Vector3(cx, (DECK_Y - 0.15) * 0.5, front + 0.04), Color(0.1, 0.09, 0.07))
	for k in 20:
		var lx := PORCH_X0 + 0.2 + k * 0.4
		if absf(lx - STEP_X) < 0.8:
			continue
		m._bx("wood", Vector3(0.03, 0.03, 1.0), Vector3(lx, 0.36, front + 0.07), paint.darkened(0.1), PI * 0.25)
		m._bx("wood", Vector3(0.03, 0.03, 1.0), Vector3(lx, 0.36, front + 0.07), paint.darkened(0.1), -PI * 0.25)
	for sx: float in [PORCH_X0, PORCH_X1]:
		m._bx("flat", Vector3(0.04, DECK_Y - 0.15, dz), Vector3(sx, (DECK_Y - 0.15) * 0.5, (wall_z + front) * 0.5), Color(0.1, 0.09, 0.07))
	# Steps: three risers down to the walkway.
	var rise := DECK_Y / 3.0
	for k in 3:
		var hh := DECK_Y - rise * (k + 1)
		var z0 := front + 0.32 * k
		m._bx("wood", Vector3(1.4, hh + 0.03, 0.34), Vector3(STEP_X, (hh + 0.03) * 0.5, z0 + 0.17), wood.lightened(0.04 * k))
		m._bx("wood", Vector3(1.42, 0.03, 0.05), Vector3(STEP_X, hh + 0.02, z0 + 0.33), paint.darkened(0.2))  # nosing
	# Railing (top DECK_Y + 0.9) with balusters and a gap for the steps.
	var rail_top := DECK_Y + 0.9
	var segs: Array = [[Vector3(PORCH_X0, 0, front), Vector3(STEP_X - 0.75, 0, front)],
		[Vector3(STEP_X + 0.75, 0, front), Vector3(PORCH_X1, 0, front)],
		[Vector3(PORCH_X1, 0, front), Vector3(PORCH_X1, 0, wall_z)], [Vector3(PORCH_X0, 0, front), Vector3(PORCH_X0, 0, wall_z)]]
	for sg: Array in segs:
		var a: Vector3 = sg[0]
		var b: Vector3 = sg[1]
		var d := b - a
		var yaw := atan2(-d.z, d.x)
		var l := d.length()
		m._bx("wood", Vector3(l, 0.07, 0.14), (a + b) * 0.5 + Vector3(0, rail_top, 0), paint, yaw)
		m._bx("wood", Vector3(l, 0.05, 0.06), (a + b) * 0.5 + Vector3(0, DECK_Y + 0.1, 0), paint.darkened(0.08), yaw)
		var nb := int(l / 0.15)
		for k in nb:
			m._bx("wood", Vector3(0.045, 0.78, 0.045), a + d * ((k + 0.5) / nb) + Vector3(0, DECK_Y + 0.5, 0), paint.darkened(randf() * 0.08), yaw)
	for k in 2:
		var hx := STEP_X + (0.72 if k == 0 else -0.72)
		m._beam("wood", Vector3(hx, rail_top, front), Vector3(hx, 0.9, front + 0.98), 0.06, paint)
		m._bx("wood", Vector3(0.11, 0.95, 0.11), Vector3(hx, 0.47, front + 0.95), paint)
	# Roof posts, roof (a low shingled shed roof), fascia, gutter.
	for ppx: float in [PORCH_X0 + 0.08, STEP_X - 0.75, STEP_X + 0.75, PORCH_X1 - 0.08]:
		m._bx("wood", Vector3(0.18, ROOF_Y - DECK_Y, 0.18), Vector3(ppx, DECK_Y + (ROOF_Y - DECK_Y) * 0.5, front + 0.08), paint)
		m._bx("wood", Vector3(0.26, 0.12, 0.26), Vector3(ppx, DECK_Y + 0.06, front + 0.08), paint.darkened(0.1))
	var rx0 := PORCH_X0 - 0.3
	var rx1 := PORCH_X1 + 0.95     # runs over the trellis at the right end
	var rz0 := wall_z
	var rz1 := front + 0.5
	m._bx("wood", Vector3(rx1 - rx0, 0.14, rz1 - rz0), Vector3((rx0 + rx1) * 0.5, ROOF_Y + 0.07, (rz0 + rz1) * 0.5), paint.darkened(0.15))
	var slope := 0.12
	m._sbox("shingle", Vector3(rx1 - rx0 + 0.1, 0.1, rz1 - rz0 + 0.1), Transform3D(Basis(Vector3.RIGHT, slope), Vector3((rx0 + rx1) * 0.5, ROOF_Y + 0.33, (rz0 + rz1) * 0.5)), Color(0.32, 0.28, 0.26), 0.7)
	m._bx("flat", Vector3(rx1 - rx0 + 0.1, 0.26, 0.06), Vector3((rx0 + rx1) * 0.5, ROOF_Y + 0.12, rz1 + 0.02), paint)
	m._bx("metal", Vector3(rx1 - rx0 + 0.1, 0.1, 0.12), Vector3((rx0 + rx1) * 0.5, ROOF_Y + 0.2, rz1 + 0.1), Color(0.75, 0.74, 0.7))
	# Porch swing hanging on chains at the left end.
	var swp := Vector3(-4.5, DECK_Y, wall_z + 1.0)
	m._bx("wood", Vector3(1.5, 0.07, 0.5), swp + Vector3(0, 0.48, 0), wood.lightened(0.08))
	for k in 6:
		m._bx("wood", Vector3(0.2, 0.5, 0.03), swp + Vector3(-0.62 + k * 0.25, 0.78, -0.24), wood.lightened(0.08), 0.0)
	m._bx("wood", Vector3(1.55, 0.06, 0.06), swp + Vector3(0, 1.05, -0.24), wood)
	for s: float in [-1.0, 1.0]:
		m._bx("wood", Vector3(0.06, 0.3, 0.5), swp + Vector3(s * 0.75, 0.62, 0), wood)
		m._beam("metal", swp + Vector3(s * 0.74, 0.62, 0.15), Vector3(swp.x + s * 0.74, ROOF_Y, swp.z), 0.025, Color(0.45, 0.45, 0.45))
		m._beam("metal", swp + Vector3(s * 0.74, 1.05, -0.24), Vector3(swp.x + s * 0.74, ROOF_Y, swp.z), 0.025, Color(0.45, 0.45, 0.45))
	m._bx("flat", Vector3(0.45, 0.14, 0.35), swp + Vector3(0.35, 0.58, 0), Color(0.3, 0.45, 0.6))  # cushion
	# Mom's chair, a side table with her coffee mug, a potted fern, the doormat.
	var mc := Vector3(0.2, DECK_Y, wall_z + 0.9)
	m._bx("wood", Vector3(0.65, 0.06, 0.6), mc + Vector3(0, 0.42, 0), Color(0.8, 0.78, 0.72))
	m._sbox("wood", Vector3(0.65, 0.6, 0.06), Transform3D(Basis(Vector3.RIGHT, 0.25), mc + Vector3(0, 0.75, -0.3)), Color(0.8, 0.78, 0.72))
	for lx: float in [-0.28, 0.28]:
		for lz: float in [-0.25, 0.25]:
			m._bx("wood", Vector3(0.05, 0.42, 0.05), mc + Vector3(lx, 0.21, lz), Color(0.75, 0.73, 0.68))
	m._cy("wood", 0.22, 0.22, 0.04, mc + Vector3(0.65, 0.5, 0.1), Color(0.6, 0.48, 0.34), 10)
	m._cy("flat", 0.03, 0.03, 0.48, mc + Vector3(0.65, 0.24, 0.1), Color(0.3, 0.25, 0.2), 6)
	m._cy("flat", 0.04, 0.04, 0.1, mc + Vector3(0.6, 0.57, 0.1), Color(0.85, 0.82, 0.75), 8)
	m._bx("flat", Vector3(0.9, 0.02, 0.55), Vector3(STEP_X, DECK_Y + 0.01, wall_z + 0.55), Color(0.4, 0.3, 0.18))
	for fp: Vector3 in [Vector3(PORCH_X0 + 0.45, DECK_Y, front - 0.4), Vector3(PORCH_X1 - 0.4, DECK_Y, front - 0.4)]:
		m._cy("flat", 0.2, 0.15, 0.36, fp + Vector3(0, 0.18, 0), Color(0.6, 0.32, 0.2), 10)
		_blob("flat", fp + Vector3(0, 0.5, 0), 0.32, Color(0.2, 0.36, 0.12), 3, 8, 0.7)
	# Shrubs along the porch skirt (either side of the steps).
	for bx: float in [-5.4, -4.5, -3.6, -0.3, 0.6, 1.4]:
		_blob("flat", Vector3(bx + randf_range(-0.1, 0.1), 0.0, front + 0.35), randf_range(0.36, 0.44), Color(0.14, 0.27, 0.1).lightened(randf() * 0.08), 4, 8, 0.85)
	# Wooden trellis at the right end, overgrown with a climbing vine: the way up onto the porch roof.
	var tx0 := PORCH_X1 + 0.15
	var tx1 := PORCH_X1 + 0.85
	var tz := front + 0.32
	for tx: float in [tx0, tx1]:
		m._bx("wood", Vector3(0.07, ROOF_Y + 0.05, 0.07), Vector3(tx, (ROOF_Y + 0.05) * 0.5, tz), paint)
	var y := 0.25
	while y < ROOF_Y:
		m._bx("wood", Vector3(tx1 - tx0, 0.04, 0.04), Vector3((tx0 + tx1) * 0.5, y, tz), paint.darkened(0.05))
		y += 0.3
	for k in 3:
		var vx := tx0 + (tx1 - tx0) * (k + 1) / 4.0
		m._bx("wood", Vector3(0.03, ROOF_Y, 0.03), Vector3(vx, ROOF_Y * 0.5, tz - 0.02), paint.darkened(0.05))
	for i in 22:
		var vy := randf_range(0.2, ROOF_Y)
		_blob("flat", Vector3(randf_range(tx0, tx1), vy, tz + randf_range(-0.03, 0.08)), randf_range(0.1, 0.18),
			Color(0.16, 0.32, 0.11).lightened(randf() * 0.1), 3, 6, 0.8)
		if randf() < 0.35:
			_blob("flat", Vector3(randf_range(tx0, tx1), vy + 0.1, tz + 0.12), 0.05, Color(0.95, 0.85, 0.9), 2, 5)


func _build_garage() -> void:
	var siding := Color(0.6, 0.64, 0.52)
	var trim := Color(0.88, 0.86, 0.8)
	var wall_z := HOUSE_Z
	_gable(5.5, 2.95, wall_z, 6.4, 3.1, 4.3, siding, Color(0.32, 0.28, 0.26))
	m._bx("brick", Vector3(6.0, 0.3, 0.36), Vector3(5.5, 0.15, wall_z - 0.12), Color(1, 1, 1))
	# Sectional garage door, a bit dented, with a window row.
	var gx := 5.5
	m._bx("flat", Vector3(3.8, 2.5, 0.06), Vector3(gx, 1.25, wall_z + 0.02), trim)
	m._bx("flat", Vector3(3.5, 2.3, 0.07), Vector3(gx, 1.15, wall_z + 0.03), Color(0.84, 0.82, 0.76))
	for k in 4:
		m._bx("flat", Vector3(3.5, 0.03, 0.08), Vector3(gx, 0.0 + 0.575 * (k + 1), wall_z + 0.04), Color(0.55, 0.54, 0.5))
	for k in 4:
		m._bx("flat", Vector3(0.6, 0.3, 0.08), Vector3(gx - 1.2 + k * 0.8, 2.0, wall_z + 0.045), Color(0.15, 0.18, 0.22))
	m._bx("flat", Vector3(0.6, 0.35, 0.09), Vector3(gx + 0.9, 0.7, wall_z + 0.04), Color(0.7, 0.68, 0.62))  # the dent (patched)
	# Basketball hoop over the garage door: backboard, orange rim, ragged net.
	var hb := Vector3(gx, 3.75, wall_z + 0.35)
	m._bx("metal", Vector3(0.12, 0.12, 0.5), Vector3(gx, 3.6, wall_z + 0.15), Color(0.3, 0.3, 0.3))
	m._bx("flat", Vector3(1.3, 0.85, 0.05), hb, Color(0.92, 0.92, 0.9))
	m._bx("flat", Vector3(0.5, 0.36, 0.055), hb + Vector3(0, -0.12, 0.003), Color(0.75, 0.2, 0.12))
	m._bx("flat", Vector3(0.42, 0.28, 0.06), hb + Vector3(0, -0.12, 0.004), Color(0.92, 0.92, 0.9))
	var rim_c := hb + Vector3(0, -0.36, 0.3)
	for k in 10:
		var a0 := TAU * k / 10.0
		var a1 := TAU * (k + 1) / 10.0
		m._beam("flat", rim_c + Vector3(cos(a0), 0, sin(a0)) * 0.23, rim_c + Vector3(cos(a1), 0, sin(a1)) * 0.23, 0.025, Color(0.85, 0.32, 0.08))
		if k % 2 == 0:
			m._beam("flat", rim_c + Vector3(cos(a0), 0, sin(a0)) * 0.23, rim_c + Vector3(cos(a0) * 0.13, -0.38, sin(a0) * 0.13), 0.012, Color(0.9, 0.9, 0.88))
	# Garbage + recycling cans beside the garage.
	for tc: Vector3 in [Vector3(7.95, 0, -7.9), Vector3(7.95, 0, -7.2)]:
		m._cy("flat", 0.3, 0.34, 0.95, tc + Vector3(0, 0.475, 0), Color(0.16, 0.3, 0.18), 10)
		m._cy("flat", 0.37, 0.36, 0.07, tc + Vector3(0, 0.98, 0), Color(0.13, 0.25, 0.15), 10)
	m._bx("flat", Vector3(0.6, 1.0, 0.65), Vector3(7.95, 0.5, -6.45), Color(0.15, 0.3, 0.6))
	# Hedge along the right side of the driveway (the neighbour's line).
	var z := HOUSE_Z + 0.6
	while z < 3.6:
		_blob("flat", Vector3(HEDGE_X + randf_range(-0.06, 0.06), 0.0, z), randf_range(0.55, 0.65), Color(0.13, 0.26, 0.1).lightened(randf() * 0.07), 4, 8, 1.15)
		z += 0.55


# ---- next door: Mr. Hollis (left) and the other neighbours

func _build_hollis() -> void:
	# His white picket fence along the property line, prize hydrangeas pressed up against it,
	# his tidy white house with green shutters, a rocking chair, a flag, a little sign.
	var white := Color(0.93, 0.92, 0.88)
	_picket_run(Vector3(FENCE_X, 0, HOUSE_Z + 0.2), Vector3(FENCE_X, 0, SIDEWALK_RECT.position.y - 0.15), 1.05, white)
	_picket_run(Vector3(FENCE_X, 0, SIDEWALK_RECT.position.y - 0.15), Vector3(-14.0, 0, SIDEWALK_RECT.position.y - 0.15), 0.9, white)
	var blooms: Array[Color] = [Color(0.3, 0.42, 0.9), Color(0.58, 0.36, 0.85), Color(0.85, 0.45, 0.72), Color(0.35, 0.5, 0.95),
		Color(0.62, 0.38, 0.88), Color(0.3, 0.45, 0.88), Color(0.82, 0.48, 0.75)]
	var hz: Array[float] = [-7.3, -5.8, -4.3, -2.7, -1.1, 0.5, 2.1, 3.5]
	for i in hz.size():
		_hydrangea(Vector3(FENCE_X - 0.75 + randf_range(-0.1, 0.1), 0.0, hz[i]), randf_range(0.55, 0.68), blooms[i % blooms.size()])
	# Mulch bed under them (darker strip on his side).
	m._bx("flat", Vector3(1.5, 0.03, 12.0), Vector3(FENCE_X - 0.8, 0.012, -2.0), Color(0.24, 0.15, 0.1))
	m._bx("brick", Vector3(0.1, 0.12, 12.0), Vector3(FENCE_X - 1.58, 0.06, -2.0), Color(0.82, 0.62, 0.55))
	# "KEEP OFF THE HYDRANGEAS" sign stuck in the bed, facing the yard.
	var sp := Vector3(FENCE_X - 0.2, 0, -3.5)
	m._bx("wood", Vector3(0.05, 1.45, 0.05), sp + Vector3(0, 0.72, 0), Color(0.5, 0.4, 0.3))
	m._bx("wood", Vector3(0.04, 0.4, 0.75), sp + Vector3(0.04, 1.4, 0), Color(0.92, 0.9, 0.82))
	var lab := Label3D.new()
	lab.text = "KEEP OFF\nTHE HYDRANGEAS"
	lab.font_size = 34
	lab.outline_size = 0
	lab.modulate = Color(0.65, 0.1, 0.08)
	lab.shaded = true
	lab.pixel_size = 0.004
	lab.position = sp + Vector3(0.07, 1.4, 0)
	lab.rotation_degrees = Vector3(0, 90, 2)
	add_child(lab)
	# His house: one-and-a-half story, white siding, green shutters, front porch facing the street.
	var hw := 4.6
	var hcx := -16.5
	var hfront := -6.2
	_gable(hcx, hw, hfront, 7.6, 3.4, 6.2, Color(0.88, 0.87, 0.82), Color(0.22, 0.26, 0.22))
	m._bx("brick", Vector3(hw * 2 + 0.3, 0.5, 0.36), Vector3(hcx, 0.25, hfront - 0.12), Color(1, 1, 1))
	var ht := Color(0.95, 0.95, 0.92)
	var hs := Color(0.14, 0.3, 0.2)
	_window(hcx + 2.6, 1.8, hfront + 0.02, 1.2, 1.2, ht, hs, Color(0.9, 0.88, 0.8))
	_window(hcx - 2.6, 1.8, hfront + 0.02, 1.2, 1.2, ht, hs, Color(0.9, 0.88, 0.8))
	# Side windows facing Mom's yard (x = hcx + hw).
	for wz: float in [-8.0, -11.0]:
		m._bx("flat", Vector3(0.06, 1.3, 1.2), Vector3(hcx + hw + 0.17, 1.8, wz), ht)
		m._bx("flat", Vector3(0.07, 1.1, 1.0), Vector3(hcx + hw + 0.19, 1.8, wz), Color(0.13, 0.17, 0.22))
	m._bx("flat", Vector3(1.0, 2.1, 0.07), Vector3(hcx, 1.05 + 0.4, hfront + 0.03), Color(0.14, 0.3, 0.2))   # door
	m._bx("wood", Vector3(3.6, 0.4, 1.8), Vector3(hcx, 0.2, hfront + 0.9), Color(0.6, 0.58, 0.55))           # stoop
	for px: float in [hcx - 1.7, hcx + 1.7]:
		m._bx("wood", Vector3(0.14, 2.6, 0.14), Vector3(px, 1.7, hfront + 1.7), ht)
	m._bx("shingle", Vector3(4.0, 0.12, 2.0), Vector3(hcx, 3.05, hfront + 0.95), Color(0.22, 0.26, 0.22), 0.0, 0.7)
	# Rocking chair on his stoop, flag on the post.
	var rc := Vector3(hcx + 1.0, 0.4, hfront + 1.0)
	m._bx("wood", Vector3(0.55, 0.05, 0.5), rc + Vector3(0, 0.42, 0), Color(0.45, 0.32, 0.2))
	m._bx("wood", Vector3(0.55, 0.7, 0.05), rc + Vector3(0, 0.8, -0.24), Color(0.45, 0.32, 0.2))
	m._beam("wood", rc + Vector3(-0.28, 0.02, -0.4), rc + Vector3(-0.28, 0.02, 0.4), 0.05, Color(0.4, 0.28, 0.18))
	m._beam("wood", rc + Vector3(0.28, 0.02, -0.4), rc + Vector3(0.28, 0.02, 0.4), 0.05, Color(0.4, 0.28, 0.18))
	m._beam("metal", Vector3(hcx - 1.7, 2.4, hfront + 1.75), Vector3(hcx - 0.9, 2.9, hfront + 2.3), 0.03, Color(0.7, 0.7, 0.7))
	m._sbox("flat", Vector3(0.9, 0.55, 0.02), Transform3D(Basis(Vector3.UP, -0.6), Vector3(hcx - 0.85, 2.65, hfront + 2.3)), Color(0.75, 0.2, 0.16))
	# His walkway (edged, of course).
	m._bx("block", Vector3(1.2, 0.03, 8.8), Vector3(hcx, 0.012, 0.0), Color(0.72, 0.7, 0.66))


func _build_neighbors() -> void:
	# House on the right, beyond the hedge, and a big shade tree on each side behind the houses.
	var ncx := 14.5
	_gable(ncx, 4.5, -8.0, 7.5, 5.2, 7.2, Color(0.55, 0.62, 0.68), Color(0.25, 0.24, 0.26))
	m._bx("brick", Vector3(9.3, 0.5, 0.36), Vector3(ncx, 0.25, -8.12), Color(1, 1, 1))
	_window(ncx - 2.0, 1.8, -7.98, 1.3, 1.2, Color(0.92, 0.92, 0.9), Color(0.2, 0.22, 0.3))
	_window(ncx + 2.0, 1.8, -7.98, 1.3, 1.2, Color(0.92, 0.92, 0.9), Color(0.2, 0.22, 0.3))
	_window(ncx - 2.0, 4.0, -7.98, 1.1, 1.1, Color(0.92, 0.92, 0.9), Color(0.2, 0.22, 0.3))
	_window(ncx + 2.0, 4.0, -7.98, 1.1, 1.1, Color(0.92, 0.92, 0.9), Color(0.2, 0.22, 0.3))
	m._bx("flat", Vector3(1.0, 2.1, 0.07), Vector3(ncx, 1.05 + 0.3, -7.95), Color(0.75, 0.6, 0.2))
	m._bx("wood", Vector3(2.6, 0.3, 1.4), Vector3(ncx, 0.15, -7.2), Color(0.62, 0.6, 0.56))
	for t: Vector3 in [Vector3(-9.8, 0, -12.0), Vector3(9.6, 0, -12.5), Vector3(-24.0, 0, -4.0), Vector3(22.0, 0, -3.0), Vector3(-2.0, 0, -19.0)]:
		var th := randf_range(3.0, 4.0)
		m._cy("flat", 0.3, 0.22, th, t + Vector3(0, th * 0.5, 0), Color(0.3, 0.24, 0.18), 7)
		var cr := randf_range(2.6, 3.4)
		for k in 4:
			var off := Vector3(randf_range(-1.2, 1.2), randf_range(0.0, 1.4), randf_range(-1.0, 1.0))
			_blob("flat", t + Vector3(0, th + cr * 0.6, 0) + off, cr * randf_range(0.7, 0.9), Color(0.18, 0.3, 0.12).lightened(randf() * 0.08), 4, 9)
	# Telephone pole and a sagging line across the far back.
	m._cy("wood", 0.14, 0.12, 9.0, Vector3(-11.5, 4.5, -15.0), Color(0.42, 0.34, 0.26), 7)
	m._bx("wood", Vector3(1.8, 0.1, 0.1), Vector3(-11.5, 8.6, -15.0), Color(0.42, 0.34, 0.26))
	m._cy("wood", 0.14, 0.12, 9.0, Vector3(12.5, 4.5, -15.5), Color(0.42, 0.34, 0.26), 7)
	m._bx("wood", Vector3(1.8, 0.1, 0.1), Vector3(12.5, 8.6, -15.5), Color(0.42, 0.34, 0.26))
	for s: float in [-0.75, 0.75]:
		var a := Vector3(-11.5 + s, 8.65, -15.0)
		var b := Vector3(12.5 + s, 8.65, -15.5)
		var prev := a
		for k in range(1, 13):
			var t2 := float(k) / 12.0
			var p := a.lerp(b, t2) - Vector3(0, 1.1 * 4.0 * t2 * (1.0 - t2), 0)
			m._beam("flat", prev, p, 0.025, Color(0.06, 0.06, 0.06))
			prev = p


# ---- yard props (decoration; the perches are in _build_perches)

func _build_yard_props() -> void:
	# Mailbox on its post at the curb end of the driveway (red flag up: Mom's rent notice is in there).
	var mb := Vector3(3.25, 0, 4.85)
	m._bx("wood", Vector3(0.1, 1.05, 0.1), mb + Vector3(0, 0.52, 0), Color(0.5, 0.4, 0.3))
	m._bx("wood", Vector3(0.2, 0.05, 0.5), mb + Vector3(0, 1.05, 0), Color(0.45, 0.36, 0.28))
	m._bx("metal", Vector3(0.24, 0.22, 0.5), mb + Vector3(0, 1.18, 0), Color(0.12, 0.12, 0.13))
	m._scyl("metal", 0.12, 0.12, 0.5, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), mb + Vector3(0, 1.29, 0)), Color(0.12, 0.12, 0.13), 10)
	m._bx("flat", Vector3(0.02, 0.2, 0.04), mb + Vector3(0.13, 1.35, -0.12), Color(0.8, 0.12, 0.08))
	m._bx("flat", Vector3(0.02, 0.06, 0.12), mb + Vector3(0.13, 1.43, -0.07), Color(0.8, 0.12, 0.08))
	for i in 3:
		m._bx("flat", Vector3(0.005, 0.07, 0.05), mb + Vector3(-0.125, 1.2, -0.08 + i * 0.07), Color(0.9, 0.85, 0.6))
	obstacles.append(footprint(Vector2(mb.x, mb.z), Vector2(0.15, 0.28), "THE MAILBOX", "Mailbox Crash", 150, "metal_hit"))
	# Garden hose: reel by the house corner, hose snaking out across the lawn to the sprinkler.
	var reel := Vector3(-6.75, 0, -6.0)
	m._bx("metal", Vector3(0.5, 0.06, 0.4), reel + Vector3(0, 0.03, 0), Color(0.3, 0.3, 0.3))
	m._scyl("flat", 0.3, 0.3, 0.28, Transform3D(Basis(Vector3.BACK, PI * 0.5), reel + Vector3(0, 0.38, 0)), Color(0.14, 0.42, 0.18), 12)
	m._scyl("metal", 0.33, 0.33, 0.02, Transform3D(Basis(Vector3.BACK, PI * 0.5), reel + Vector3(0.16, 0.38, 0)), Color(0.5, 0.5, 0.5), 12)
	m._scyl("metal", 0.33, 0.33, 0.02, Transform3D(Basis(Vector3.BACK, PI * 0.5), reel + Vector3(-0.16, 0.38, 0)), Color(0.5, 0.5, 0.5), 12)
	var spr := Vector3(-4.2, 0, 1.0)
	var pts: Array[Vector3] = [reel + Vector3(0.1, 0.03, 0.3), Vector3(-6.3, 0.03, -4.4), Vector3(-5.2, 0.03, -3.3), Vector3(-6.1, 0.03, -1.9),
		Vector3(-5.6, 0.03, -0.4), Vector3(-4.7, 0.03, 0.2), spr + Vector3(-0.2, 0.03, 0.0)]
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var mid := (a + b) * 0.5 + Vector3((b.z - a.z) * 0.18, 0, -(b.x - a.x) * 0.18)
		m._beam("flat", a, mid, 0.035, Color(0.14, 0.44, 0.18))
		m._beam("flat", mid, b, 0.035, Color(0.14, 0.44, 0.18))
	# Oscillating sprinkler (off, for now).
	m._bx("metal", Vector3(0.45, 0.05, 0.16), spr + Vector3(0, 0.03, 0), Color(0.6, 0.6, 0.62))
	m._scyl("flat", 0.03, 0.03, 0.4, Transform3D(Basis(Vector3.BACK, PI * 0.5), spr + Vector3(0, 0.1, 0)), Color(0.85, 0.75, 0.2), 8)
	# Kid's bike dropped on the lawn by the driveway.
	_bike(Vector3(3.0, 0, 2.2), 1.2, Color(0.15, 0.35, 0.8), true)
	# Plastic flamingos and a garden gnome by the planter, another gnome by the steps.
	for fl: Vector3 in [Vector3(-6.7, 0, 1.3), Vector3(-6.35, 0, 1.8)]:
		m._beam("metal", fl, fl + Vector3(0, 0.55, 0), 0.015, Color(0.2, 0.2, 0.2))
		m._sbox("flat", Vector3(0.12, 0.16, 0.3), Transform3D(Basis(Vector3.RIGHT, 0.3), fl + Vector3(0, 0.62, 0)), Color(0.95, 0.38, 0.55))
		m._beam("flat", fl + Vector3(0, 0.66, -0.12), fl + Vector3(0, 0.9, -0.08), 0.035, Color(0.95, 0.38, 0.55))
		m._bx("flat", Vector3(0.05, 0.06, 0.1), fl + Vector3(0, 0.92, -0.02), Color(0.95, 0.4, 0.58))
		m._bx("flat", Vector3(0.03, 0.03, 0.06), fl + Vector3(0, 0.9, 0.05), Color(0.1, 0.1, 0.1))
	for g: Vector3 in [Vector3(-6.8, 0, 3.6), Vector3(-0.9, 0, -5.25)]:
		m._cy("flat", 0.13, 0.09, 0.22, g + Vector3(0, 0.11, 0), Color(0.17, 0.3, 0.6), 8)
		m._bx("flat", Vector3(0.13, 0.12, 0.13), g + Vector3(0, 0.28, 0), Color(0.85, 0.66, 0.54))
		m._bx("flat", Vector3(0.14, 0.1, 0.06), g + Vector3(0, 0.22, 0.07), Color(0.92, 0.92, 0.9))
		m._cy("flat", 0.09, 0.0, 0.22, g + Vector3(0, 0.45, 0), Color(0.75, 0.12, 0.1), 8)
	# Chalk hopscotch on the sidewalk (kids) and a skateboard by the curb.
	for i in 6:
		var hx := -5.6 + i * 0.5
		m._bx("flat", Vector3(0.44, 0.005, 0.02), Vector3(hx, 0.02, 4.75), Color(0.95, 0.75, 0.85))
		m._bx("flat", Vector3(0.02, 0.005, 0.5), Vector3(hx - 0.22, 0.02, 5.0), Color(0.95, 0.75, 0.85))
	m._bx("flat", Vector3(0.8, 0.03, 0.22), Vector3(-8.6, 0.09, 5.2), Color(0.55, 0.15, 0.12), 0.3)


func _build_perches() -> void:
	# Five things to climb at different heights, around the edges; the middle stays open.
	# 1) Brick planter wall with Mom's marigolds (top 0.62), front-left
	var pc := Vector3(-5.6, 0, 2.9)
	var pw := 2.0
	var pd := 0.9
	m._bx("brick", Vector3(pw, 0.56, pd), pc + Vector3(0, 0.28, 0), Color(0.95, 0.85, 0.8))
	m._bx("block", Vector3(pw + 0.1, 0.06, pd + 0.1), pc + Vector3(0, 0.59, 0), Color(0.75, 0.73, 0.68))
	m._bx("flat", Vector3(pw - 0.2, 0.02, pd - 0.2), pc + Vector3(0, 0.6, 0), Color(0.22, 0.15, 0.1))
	for i in 9:
		var fpos := pc + Vector3(-0.8 + (i % 5) * 0.4 + randf_range(-0.05, 0.05), 0.68, -0.2 + (i / 5) * 0.38)
		_blob("flat", fpos, 0.13, Color(0.2, 0.35, 0.12), 3, 6, 0.8)
		_blob("flat", fpos + Vector3(0, 0.1, 0), 0.07, Color(0.98, 0.58, 0.1) if i % 2 == 0 else Color(0.95, 0.8, 0.15), 2, 6)
	add_perch("planter wall", "planter", Vector3(-5.6, 0.62, 2.9), Vector3(-4.1, 0.0, 2.9),
		footprint(Vector2(pc.x, pc.z), Vector2(pw * 0.5 + 0.05, pd * 0.5 + 0.05), "THE PLANTER", "Planter Crash", 200, "thud"))
	# 2) Porch steps (deck top 0.85), built with the porch: steps x -2.7..-1.3, z -5.7..-4.74
	add_perch("porch steps", "porch", Vector3(STEP_X, DECK_Y, PORCH_FRONT - 0.25), Vector3(STEP_X, 0.0, -4.25),
		footprint(Vector2(STEP_X, -5.22), Vector2(0.78, 0.5), "THE PORCH STEPS", "Porch Step Crash", 200, "wood_hit"))
	# 3) Porch railing (top 1.75), right of the steps
	add_perch("porch railing", "railing", Vector3(0.1, DECK_Y + 0.94, PORCH_FRONT), Vector3(0.1, 0.0, -4.4),
		footprint(Vector2(0.1, PORCH_FRONT), Vector2(1.6, 0.15), "THE RAILING", "Railing Crash", 200, "wood_hit"))
	obstacles.append(footprint(Vector2((PORCH_X0 + PORCH_X1) * 0.5, (HOUSE_Z + PORCH_FRONT) * 0.5 + 0.1), Vector2((PORCH_X1 - PORCH_X0) * 0.5, 1.55),
		"THE PORCH", "Porch Crash", 200, "wood_hit"))
	# 4) Car roof (1.48): in _build_car
	# 5) Porch roof via the vine trellis (3.25): the biggest dive
	add_perch("porch roof", "roof", Vector3(PORCH_X1 + 0.1, ROOF_Y + 0.24, PORCH_FRONT + 0.1), Vector3(PORCH_X1 + 0.55, 0.0, -4.45),
		footprint(Vector2(PORCH_X1 + 0.5, PORCH_FRONT + 0.32), Vector2(0.42, 0.12), "THE TRELLIS", "Trellis Crash", 250, "wood_hit"))
	# Shrubs at the porch skirt (z ~-5.35) sit behind the yard's back edge (z -5).


func _build_car() -> void:
	# Mom's faded station wagon on the driveway, nose to the street.
	var pos := CAR_POS
	var xf := Transform3D(Basis.looking_at(Vector3(0, 0, 1)), pos)
	var body := Color(0.32, 0.45, 0.5)
	var glass := Color(0.1, 0.13, 0.17)
	var chrome := Color(0.65, 0.65, 0.66)
	m._sbox("flat", Vector3(1.8, 0.62, 4.6), xf * Transform3D(Basis(), Vector3(0, 0.6, 0)), body)
	m._sbox("flat", Vector3(1.66, 0.55, 2.9), xf * Transform3D(Basis(), Vector3(0, 1.18, 0.55)), body.darkened(0.08))  # long wagon cabin
	m._sbox("flat", Vector3(1.7, 0.4, 2.7), xf * Transform3D(Basis(), Vector3(0, 1.18, 0.55)), glass)
	m._sbox("flat", Vector3(1.45, 0.42, 2.94), xf * Transform3D(Basis(), Vector3(0, 1.18, 0.55)), glass)
	m._sbox("flat", Vector3(1.0, 0.43, 0.06), xf * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.2, 1.2, -0.92)), Color(0.4, 0.5, 0.58))  # windshield glint
	# Wood-grain side panels (of course), roof rack, bumpers, lights.
	for sx: float in [-0.91, 0.91]:
		m._sbox("wood", Vector3(0.02, 0.3, 3.6), xf * Transform3D(Basis(), Vector3(sx, 0.62, 0.2)), Color(0.55, 0.38, 0.22))
		m._sbox("metal", Vector3(0.05, 0.05, 2.6), xf * Transform3D(Basis(), Vector3(sx * 0.72, 1.5, 0.55)), chrome)
	for rz: float in [-0.3, 1.4]:
		m._sbox("metal", Vector3(1.5, 0.04, 0.05), xf * Transform3D(Basis(), Vector3(0, 1.52, rz)), chrome)
	m._sbox("metal", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.36, -2.32)), chrome)
	m._sbox("metal", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.36, 2.32)), chrome)
	for sx: float in [-0.62, 0.62]:
		m._sbox("flat", Vector3(0.38, 0.18, 0.05), xf * Transform3D(Basis(), Vector3(sx, 0.7, -2.31)), Color(0.9, 0.9, 0.85))
		m._sbox("flat", Vector3(0.3, 0.2, 0.05), xf * Transform3D(Basis(), Vector3(sx, 0.72, 2.31)), Color(0.7, 0.1, 0.08))
		for sz: float in [-1.45, 1.45]:
			m._scyl("flat", 0.33, 0.33, 0.24, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.4, 0.33, sz)), Color(0.04, 0.04, 0.04), 10)
			m._scyl("metal", 0.17, 0.17, 0.26, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.4, 0.33, sz)), Color(0.6, 0.6, 0.62), 8)
	m._sbox("flat", Vector3(0.5, 0.1, 0.02), xf * Transform3D(Basis(), Vector3(0, 0.5, -2.39)), Color(0.9, 0.85, 0.3))  # plate
	m._sbox("flat", Vector3(0.5, 0.1, 0.02), xf * Transform3D(Basis(), Vector3(0, 0.5, 2.39)), Color(0.9, 0.85, 0.3))
	# Oil drip under the engine.
	m._cy("flat", 0.5, 0.5, 0.005, pos + Vector3(0, 0.022, 1.5), Color(0.08, 0.08, 0.09), 10)
	# wagon cabin roof top 1.455 + rack: roof perch; body 4.6 x 1.8 (bumpers to z +-2.38), wheels out to x +-1.02
	add_perch("car roof", "car", Vector3(pos.x, 1.5, pos.z - 0.55), Vector3(pos.x - 1.45, 0.0, pos.z - 0.55),
		footprint(Vector2(pos.x, pos.z), Vector2(1.02, 2.38), "THE STATION WAGON", "Wagon Crash", 250, "metal_hit"))


func _build_grime() -> void:
	var hz := HOUSE_Z + 0.06
	m._grime_wall(Vector3(-8.2, 0, hz), Vector3(PORCH_X0, 0, hz), Vector3.BACK, 0.7, 0.4)
	m._grime_wall(Vector3(PORCH_X1, 0, hz), Vector3(8.4, 0, hz), Vector3.BACK, 0.7, 0.45)
	m._grime_wall(Vector3(PORCH_X0, 0, PORCH_FRONT + 0.07), Vector3(PORCH_X1, 0, PORCH_FRONT + 0.07), Vector3.BACK, 0.5, 0.45)
	m._grime_wall(Vector3(FENCE_X + 0.03, 0, HOUSE_Z), Vector3(FENCE_X + 0.03, 0, 4.2), Vector3.RIGHT, 0.3, 0.3, 0.35, 0.3)
	m._grime_wall(Vector3(-6.6, 0, 3.36), Vector3(-4.6, 0, 3.36), Vector3.BACK, 0.4, 0.3, 0.4, 0.35)  # planter front
	m._flush_grime()
	# A chalked "C2C" on the garage door (the kids are fans).
	m._wall_decal(m._make_tag_texture("C2C", Color(0.95, 0.6, 0.75), Color(0.95, 0.95, 0.95), Color(1.0, 1.0, 1.0)),
		Vector3(5.5, 1.55, HOUSE_Z + 0.08), Vector2(1.0, 0.5), Vector3.BACK)


# ---- the neighbours watching (main.build_crowd turns these into the billboard crowd)

func _fan(p: Vector3, person: String, lit := 0.9, bob := 1.0) -> void:
	crowd_spots.append({"pos": p, "person": person, "lit": lit, "bob": bob})


func _kid_on_bike(p: Vector3, yaw: float, col: Color, person: String) -> void:
	_bike(p, yaw, col)
	_fan(p + Vector3(0.0, 0.25, 0.0), person, 0.88, 0.6)


func _build_crowd_spots() -> void:
	# The block came out to watch. Nobody stands inside the fighting area or on a perch top.
	# Seated people: the feet end 0.53 below the seat.
	crowd_spots = []
	# Mr. Hollis behind his hydrangeas (arms crossed, presumably), and his side of the fence.
	_fan(Vector3(-9.1, 0, -2.0), "flannel", 0.9, 0.3)
	_fan(Vector3(-9.6, 0, 0.9), "jacket", 0.9)
	_fan(Vector3(-10.3, 0, 2.8), "girl", 0.9)
	_fan(Vector3(-9.9, 0, -5.4), "stand", 0.88)
	# Mom's porch: behind the railing, on the swing, at the ends of the steps.
	for spot: Vector3 in [Vector3(-5.2, DECK_Y, -6.2), Vector3(-3.3, DECK_Y, -6.05), Vector3(-0.7, DECK_Y, -6.1), Vector3(1.2, DECK_Y, -6.5)]:
		_fan(spot, "stand", 0.75)
	_fan(Vector3(-4.3, DECK_Y - 0.03, -7.35), "sit_cup", 0.7, 0.5)
	_fan(Vector3(-2.6, 0.04, -5.15), "sit", 0.85)
	_fan(Vector3(-1.4, 0.04, -5.15), "sit_cup", 0.85)
	# Driveway side, beyond the hedge on the neighbour's lawn, one on the garage roof edge.
	for spot: Vector3 in [Vector3(8.7, 0, -3.5), Vector3(9.2, 0, -1.0), Vector3(8.9, 0, 1.6), Vector3(9.8, 0, 3.4), Vector3(10.6, 0, -5.6)]:
		_fan(spot, "stand", 0.88)
	_fan(Vector3(7.2, 3.15, -8.2), "filmer", 0.85, 1.3)
	# Neighbour by the garage cans, between the driveway and the hedge (outside the fight area).
	_fan(Vector3(7.25, 0.02, -6.0), "stand", 0.88)
	# Kids on bikes on the sidewalk at both corners (out of the camera's way).
	_kid_on_bike(Vector3(-8.6, 0.02, 4.9), PI * 0.5, Color(0.8, 0.15, 0.1), "hoodie")
	_kid_on_bike(Vector3(-10.0, 0.02, 5.2), PI * 0.4, Color(0.15, 0.6, 0.3), "cheer")
	_kid_on_bike(Vector3(8.8, 0.02, 5.0), -PI * 0.5, Color(0.9, 0.75, 0.1), "hoodie")
	_fan(Vector3(10.0, 0.02, 4.9), "girl", 0.88)

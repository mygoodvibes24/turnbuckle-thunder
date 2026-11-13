extends "res://scripts/levels/level_base.gd"
## THE ROOFTOP (level id "rooftop"): a downtown rooftop at night (story ch3: Starla Volt's
## "Heartbreak Suplex" music-video shoot; ch5: Preston Vale's rooftop party + contract signing).
## Gravel-over-tar-paper roof walled in by brick parapets (the rebound / launch edges); the
## stairwell bulkhead, the water tower on its steel stand and a rooftop billboard make the -z
## backdrop with the city skyline beyond; a music-video truss + light stand light the fight.
## Fighting area x -7..7, z -5..5; ground (the roof deck) y 0; everything local to ring_root.
##
## Perches: crate stack (1.1), AC unit (1.3), stairwell bulkhead roof (2.8), water tower
## platform (3.8, kind "roof" = the biggest dive).
## Uses main's helpers (see scripts/levels/backyard.gd header); the gravel / window textures,
## the facade material and the night sky are made here.

const ROOF_X := 7.55            # side parapets (inner face ~7.4)
const FRONT_Z := 5.65           # low front parapet on the camera side
const BACK_Z := -11.0           # back parapet behind the bulkhead / water tower
const PARAPET_H := 1.0
const FRONT_H := 0.6
const WALK_RECT := Rect2(-4.75, -5.3, 1.3, 4.0)   # concrete paver walkway from the stairwell door

const BULK_C := Vector3(-3.2, 0.0, -6.7)           # stairwell bulkhead, 3.6 x 2.8, walls 2.7
const BULK_HALF := Vector2(1.8, 1.4)
const BULK_H := 2.7
const TOWER_C := Vector3(4.4, 0.0, -7.6)           # water tower stand
const TOWER_DECK := 3.8
const AC_C := Vector3(-6.2, 0.0, 1.6)
const CRATE_C := Vector3(6.15, 0.0, 2.9)

const ROOF_SKY_SHADER := """
shader_type sky;

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, -0.3, 1.0);
	vec3 col = mix(vec3(0.15, 0.085, 0.19), vec3(0.012, 0.016, 0.055), smoothstep(-0.02, 0.55, h));
	col += vec3(0.34, 0.16, 0.06) * (1.0 - smoothstep(-0.08, 0.2, h));   // sodium city glow
	col += vec3(0.07, 0.02, 0.09) * (1.0 - smoothstep(0.0, 0.4, h));     // neon haze
	col = mix(col, vec3(0.11, 0.065, 0.075), smoothstep(0.0, -0.12, d.y)); // below the horizon: haze
	vec3 cell = floor(d * 260.0);
	float r = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float star = step(0.994, r) * smoothstep(0.1, 0.32, d.y);
	col += vec3(0.9, 0.9, 1.0) * star * (0.3 + 0.6 * fract(r * 91.7));
	vec3 md = normalize(vec3(0.47, 0.16, -0.86));
	float mm = dot(d, md);
	col += vec3(0.25, 0.24, 0.38) * pow(max(mm, 0.0), 260.0);
	col = mix(col, vec3(1.0, 0.96, 0.84), smoothstep(0.99955, 0.9997, mm));
	COLOR = col;
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint = vec3(1.0, 0.9, 0.7);
uniform float strength = 0.06;

void fragment() {
	float along = 1.0 - UV.y;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint * strength * along * along * facing;
}
"""

var m = null   # main.gd (helpers)
var _facade_st: SurfaceTool
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	display_name = "THE ROOFTOP"
	description = "A city rooftop at night: AC units, a water tower ladder and the skyline behind you."
	time_of_day = "night"
	preview_color = Color(0.22, 0.24, 0.34)
	yard_bounds = Rect2(-7.0, -5.0, 14.0, 10.0)
	cam_clamp = Rect2(-5.0, -4.0, 10.0, 7.5)
	cam_height = 2.6
	cam_back = 6.0
	default_surface = "gravel"
	surfaces = [{"rect": WALK_RECT, "kind": "concrete"}]
	spawn_p1 = Vector3(-1.8, 0.0, 0.3)
	spawn_p2 = Vector3(1.8, 0.0, -0.3)


func build(main_node: Node) -> void:
	super(main_node)
	m = main_node
	_rng.seed = 30331
	perches.clear()
	obstacles.clear()
	_facade_st = SurfaceTool.new()
	_facade_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build_deck()
	_build_parapets()
	_build_bulkhead()
	_build_water_tower()
	_build_billboard()
	_build_perches()
	_build_roof_props()
	_build_stage_rig()
	_build_string_lights()
	_build_neighbors()
	_build_skyline()
	_build_grime()
	m._flush_batches()
	_flush_facades()
	_build_crowd_spots()
	item_spawns = [
		{"kind": "chair", "pos": Vector3(-2.7, 0.0, 3.3), "yaw": PI * 0.2},
		{"kind": "chair", "pos": Vector3(3.0, 0.0, 3.7), "yaw": -PI * 0.3},
		{"kind": "trash_can", "pos": Vector3(-6.75, 0.0, -1.9), "yaw": 0.0},
		{"kind": "plank", "pos": Vector3(4.4, 0.0, 0.9), "yaw": 0.35},
		{"kind": "table", "pos": Vector3(7.1, 0.0, -1.2), "yaw": -PI * 0.5},   # leaning on the right parapet
	]


func setup_environment(env: Environment) -> void:
	# Downtown night: a sodium-orange / neon-purple glow on the horizon, darker zenith, a thin
	# city haze (light enough that the skyline windows still read).
	if m != null and m.sky_mat != null:
		var sh := Shader.new()
		sh.code = ROOF_SKY_SHADER
		m.sky_mat.shader = sh
	env.ambient_light_color = Color(0.46, 0.45, 0.58)
	env.ambient_light_energy = 0.38
	env.fog_enabled = true
	env.fog_light_color = Color(0.13, 0.08, 0.1)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	if m != null and m.moon != null:
		m.moon.light_color = Color(0.55, 0.62, 1.0)
		m.moon.light_energy = 0.45
	if m != null and m.post_mat != null:
		m.post_mat.set_shader_parameter("saturation", 0.98)
		m.post_mat.set_shader_parameter("sepia", 0.22)


# ---- textures

func _make_gravel_texture() -> ImageTexture:
	# Ballast gravel over tar paper (tiles): mottled grey-brown pebbles, dark tar showing between
	# them, a few bare tar patches, water stains and scattered bright chips.
	var n := 256
	var mot: Image = m._noise_img(n, n, 0.03, 3, true)
	var peb: Image = m._noise_img(n, n, 0.32, 1, true)
	var peb2: Image = m._noise_img(n, n, 0.55, 1, true)
	var blot: Image = m._noise_img(n, n, 0.018, 2, true)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var base := Color(0.3, 0.285, 0.27)
	var tar := Color(0.075, 0.07, 0.068)
	for y in n:
		for x in n:
			var mv := mot.get_pixel(x, y).r
			var p := peb.get_pixel(x, y).r
			var q := peb2.get_pixel(x, y).r
			var bl := blot.get_pixel(x, y).r
			var c := base.darkened((mv - 0.5) * 0.5)
			var stone := Color(0.58, 0.54, 0.47).lerp(Color(0.4, 0.39, 0.4), q)
			c = c.lerp(stone, smoothstep(0.56, 0.72, p) * 0.75)
			c = c.lerp(tar, smoothstep(0.4, 0.22, p) * 0.5)
			c = c.lerp(tar, smoothstep(0.72, 0.86, bl) * 0.28)                 # bare tar patches
			c = c.lerp(Color(0.24, 0.22, 0.2), smoothstep(0.35, 0.15, bl) * 0.3) # dusty stains
			var r := randf()
			if r < 0.07:
				c = c.lightened(0.2)
			elif r < 0.15:
				c = c.darkened(0.3)
			img.set_pixel(x, y, c)
	for i in 4:
		var cx := randf_range(0.2, 0.8) * n
		var cy := randf_range(0.2, 0.8) * n
		m._soft_dot(img, cx, cy, randf_range(14.0, 30.0), randf_range(10.0, 22.0), Color(0.05, 0.05, 0.06), 0.12, 12.0)
	return m._sharp_tex(img)


func _make_window_texture() -> ImageTexture:
	# Night office / apartment facade: 8 x 8 bays (3 m each), dark glass with sky reflections,
	# warm, fluorescent and TV-blue lit windows, some with blinds, some whole floors lit.
	var n := 256
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var nz: Image = m._noise_img(n, n, 0.05, 2, true)
	for y in n:
		for x in n:
			var v := nz.get_pixel(x, y).r
			img.set_pixel(x, y, Color(0.085, 0.078, 0.085).darkened((v - 0.5) * 0.4))
	var lits: Array[Color] = [Color(1.0, 0.78, 0.45), Color(0.98, 0.72, 0.38), Color(0.78, 0.86, 0.95),
		Color(0.45, 0.55, 0.95), Color(1.0, 0.85, 0.6)]
	for row in 8:
		var floor_lit := randf() < 0.18
		var floor_col: Color = lits[randi() % 3]
		for col in 8:
			var lit := floor_lit or randf() < 0.3
			var lc: Color = floor_col if floor_lit else lits[randi() % lits.size()]
			var blinds := randf() < 0.35
			var x0 := col * 32 + 5
			var y0 := row * 32 + 7
			for yy in 18:
				for xx in 22:
					var c: Color
					if lit:
						c = lc.darkened(0.25 * float(yy) / 18.0 + randf() * 0.05)
						if blinds and yy % 3 == 0:
							c = c.darkened(0.35)
					else:
						c = Color(0.035, 0.045, 0.065).lerp(Color(0.12, 0.13, 0.18), clampf(float(xx - yy) / 30.0 + 0.3, 0.0, 1.0) * 0.6)
					if xx == 11:
						c = c.darkened(0.6)
					img.set_pixel(x0 + xx, y0 + yy, c)
	return m._sharp_tex(img)


# ---- facades (lit-window buildings: one merged mesh, unshaded window texture)

func _facade_box(size: Vector3, center: Vector3, tint: Color, top_col := Color(0.12, 0.11, 0.12)) -> void:
	var h := size * 0.5
	for n: Vector3 in [Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
		var a := Vector3.UP.cross(n)
		var c := center + n * absf(n.dot(h))
		var ea := a * absf(a.dot(h))
		var eb := Vector3(0, h.y, 0)
		m._quad(_facade_st, c - ea - eb, c - ea + eb, c + ea + eb, c + ea - eb, n, a, Vector3.UP, tint, 1.0 / 24.0)
	m._bx("flat", Vector3(size.x, 0.2, size.z), center + Vector3(0, h.y + 0.1, 0), top_col)


func _flush_facades() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _make_window_texture()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mi := MeshInstance3D.new()
	mi.mesh = _facade_st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---- the roof itself

func _build_deck() -> void:
	var gm: StandardMaterial3D = m._tex_mat(_make_gravel_texture())
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var w := ROOF_X * 2.0
	var d := FRONT_Z - BACK_Z
	m._ground_quad(Vector3(0, 0.0, (FRONT_Z + BACK_Z) * 0.5), Vector2(w, d), gm, 0.0, Vector2(w / 2.5, d / 2.5))
	# Concrete pavers from the stairwell door out toward the middle of the roof.
	var pm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(128, true, 2))
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(WALK_RECT.get_center().x, 0.02, WALK_RECT.get_center().y), WALK_RECT.size, pm, 0.0, Vector2(1.0, 3.0))
	# Tar-paper flashing patches and seams (darker, slightly glossy strips).
	for sz: float in [-2.6, 1.9]:
		m._bx("flat", Vector3(w - 0.4, 0.012, 0.08), Vector3(0, 0.006, sz), Color(0.16, 0.15, 0.14))
	m._bx("flat", Vector3(2.2, 0.012, 1.4), Vector3(2.8, 0.006, 1.2), Color(0.1, 0.095, 0.09), 0.2)
	m._bx("flat", Vector3(1.3, 0.012, 0.9), Vector3(-3.6, 0.006, -2.4), Color(0.09, 0.085, 0.08), -0.3)
	# Spray-painted C2C on the gravel? No - a taped "X" mark for the music video (hero mark).
	for s: float in [-1.0, 1.0]:
		m._bx("glow", Vector3(0.9, 0.012, 0.07), Vector3(0, 0.014, 0.0), Color(0.55, 0.5, 0.2), s * PI * 0.25)
	# The street, far below (mostly lost in the haze).
	var below := StandardMaterial3D.new()
	below.albedo_color = Color(0.06, 0.055, 0.06)
	below.roughness = 1.0
	m._plane(Vector2(500, 500), Vector3(0, -50.0, 0), below)


func _parapet(a: Vector3, b: Vector3, h: float) -> void:
	var d := b - a
	var l := d.length()
	var yaw := atan2(-d.z, d.x)
	var mid := (a + b) * 0.5
	m._bx("brick", Vector3(l, h, 0.32), mid + Vector3(0, h * 0.5, 0), Color(0.78, 0.66, 0.6), yaw)
	m._bx("block", Vector3(l + 0.1, 0.08, 0.42), mid + Vector3(0, h + 0.04, 0), Color(0.62, 0.6, 0.56), yaw)  # coping
	m._bx("flat", Vector3(l, 0.26, 0.36), mid + Vector3(0, 0.13, 0), Color(0.08, 0.075, 0.075), yaw)  # tar flashing


func _build_parapets() -> void:
	_parapet(Vector3(-ROOF_X, 0, BACK_Z), Vector3(-ROOF_X, 0, FRONT_Z), PARAPET_H)
	_parapet(Vector3(ROOF_X, 0, BACK_Z), Vector3(ROOF_X, 0, FRONT_Z), PARAPET_H)
	_parapet(Vector3(-ROOF_X, 0, BACK_Z), Vector3(ROOF_X, 0, BACK_Z), PARAPET_H)
	_parapet(Vector3(-ROOF_X, 0, FRONT_Z), Vector3(ROOF_X, 0, FRONT_Z), FRONT_H)  # low: never hides legs
	# The building's outer walls dropping away below the parapets (brick, with lit windows lower down).
	var body := Vector3(ROOF_X * 2.0 + 0.3, 50.0, FRONT_Z - BACK_Z + 0.3)
	_facade_box(Vector3(body.x, 46.0, body.z), Vector3(0, -27.0, (FRONT_Z + BACK_Z) * 0.5), Color(0.8, 0.72, 0.68))
	for s: float in [-1.0, 1.0]:
		m._bx("brick", Vector3(0.3, 4.0, body.z), Vector3(s * (ROOF_X + 0.01), -2.0, (FRONT_Z + BACK_Z) * 0.5), Color(0.6, 0.5, 0.46))
	m._bx("brick", Vector3(body.x, 4.0, 0.3), Vector3(0, -2.0, FRONT_Z + 0.01), Color(0.6, 0.5, 0.46))
	# Roof drain scuppers + a rusty fire-escape gooseneck over the right parapet.
	for z: float in [-8.0, 3.5]:
		m._bx("metal", Vector3(0.12, 0.2, 0.3), Vector3(-ROOF_X + 0.2, 0.1, z), Color(0.35, 0.25, 0.18))
	for s: float in [-0.3, 0.3]:
		m._beam("metal", Vector3(ROOF_X - 0.15, 0, 4.4 + s), Vector3(ROOF_X - 0.15, 1.5, 4.4 + s), 0.05, Color(0.3, 0.2, 0.14))
		m._beam("metal", Vector3(ROOF_X - 0.15, 1.5, 4.4 + s), Vector3(ROOF_X + 0.5, 1.2, 4.4 + s), 0.05, Color(0.3, 0.2, 0.14))


func _build_bulkhead() -> void:
	# Brick stairwell bulkhead behind the left of the fight area: steel door with a caged bulb,
	# a fixed steel ladder up its front to the flat tar roof (perch).
	var c := BULK_C
	var w := BULK_HALF.x * 2.0
	var d := BULK_HALF.y * 2.0
	m._bx("brick", Vector3(w, BULK_H, d), c + Vector3(0, BULK_H * 0.5, 0), Color(0.72, 0.6, 0.55))
	m._bx("flat", Vector3(w + 0.2, 0.12, d + 0.2), c + Vector3(0, BULK_H + 0.06, 0), Color(0.12, 0.11, 0.11))
	m._bx("block", Vector3(w + 0.26, 0.1, 0.12), c + Vector3(0, BULK_H + 0.12, d * 0.5 + 0.08), Color(0.6, 0.58, 0.55))
	m._bx("block", Vector3(w + 0.26, 0.1, 0.12), c + Vector3(0, BULK_H + 0.12, -d * 0.5 - 0.08), Color(0.6, 0.58, 0.55))
	var fz := c.z + d * 0.5
	var dx := c.x - 0.9
	m._bx("metal", Vector3(1.1, 2.2, 0.06), Vector3(dx, 1.1, fz + 0.02), Color(0.5, 0.52, 0.5))     # frame
	m._bx("flat", Vector3(0.95, 2.1, 0.07), Vector3(dx, 1.05, fz + 0.03), Color(0.24, 0.3, 0.27))    # painted steel door
	m._bx("metal", Vector3(0.7, 0.05, 0.06), Vector3(dx, 1.0, fz + 0.08), Color(0.7, 0.7, 0.68))     # push bar
	m._bx("flat", Vector3(0.6, 0.3, 0.075), Vector3(dx, 1.6, fz + 0.035), Color(0.8, 0.12, 0.08))   # "ROOF ACCESS" plate
	var lab := Label3D.new()
	lab.text = "ROOF ACCESS\nKEEP CLOSED"
	lab.font_size = 22
	lab.pixel_size = 0.004
	lab.outline_size = 0
	lab.modulate = Color(0.95, 0.92, 0.85)
	lab.shaded = true
	lab.position = Vector3(dx, 1.6, fz + 0.08)
	add_child(lab)
	m._bx("glow", Vector3(0.16, 0.2, 0.16), Vector3(dx, 2.4, fz + 0.12), Color(1.0, 0.78, 0.42))     # caged bulb
	for k in 3:
		m._bx("metal", Vector3(0.2, 0.02, 0.2), Vector3(dx, 2.32 + k * 0.08, fz + 0.12), Color(0.2, 0.2, 0.2))
	m._bx("flat", Vector3(0.14, 0.1, 0.12), Vector3(dx, 2.55, fz + 0.06), Color(0.15, 0.15, 0.15))
	# Fixed ladder at x -2.0, rails 0.44 apart, goosenecks over the roof edge.
	var lx := -2.0
	for s: float in [-0.22, 0.22]:
		m._beam("metal", Vector3(lx + s, 0, fz + 0.18), Vector3(lx + s, BULK_H + 0.9, fz + 0.18), 0.05, Color(0.62, 0.55, 0.3))
		m._beam("metal", Vector3(lx + s, BULK_H + 0.9, fz + 0.18), Vector3(lx + s, BULK_H + 0.9, fz - 0.4), 0.05, Color(0.62, 0.55, 0.3))
		m._beam("metal", Vector3(lx + s, BULK_H + 0.9, fz - 0.4), Vector3(lx + s, BULK_H + 0.12, fz - 0.4), 0.05, Color(0.62, 0.55, 0.3))
		m._bx("metal", Vector3(0.05, 0.05, 0.18), Vector3(lx + s, 1.0, fz + 0.09), Color(0.4, 0.38, 0.3))
		m._bx("metal", Vector3(0.05, 0.05, 0.18), Vector3(lx + s, 2.2, fz + 0.09), Color(0.4, 0.38, 0.3))
	for k in 9:
		m._bx("metal", Vector3(0.44, 0.035, 0.035), Vector3(lx, 0.3 + k * 0.3, fz + 0.18), Color(0.62, 0.55, 0.3))
	# On its roof: a turbine vent and an exhaust fan box.
	var top := BULK_H + 0.12
	m._cy("metal", 0.12, 0.12, 0.4, Vector3(-2.6, top + 0.2, -7.6), Color(0.6, 0.6, 0.6), 8)
	m._cy("metal", 0.26, 0.2, 0.3, Vector3(-2.6, top + 0.55, -7.6), Color(0.66, 0.66, 0.64), 10)
	m._bx("metal", Vector3(0.7, 0.45, 0.7), Vector3(-4.4, top + 0.22, -7.5), Color(0.55, 0.56, 0.55))
	# A wheat-pasted gig poster and a spray tag on the front wall.
	m._wall_decal(m._make_tag_texture("C2C", Color(0.82, 0.18, 0.12), Color(0.06, 0.05, 0.05), Color(1.0, 0.8, 0.5)),
		Vector3(-3.05, 1.2, fz + 0.01), Vector2(1.1, 0.55), Vector3.BACK)
	m._wall_decal(m._make_tag_texture("VOLT", Color(0.95, 0.85, 0.2), Color(0.25, 0.05, 0.3), Color(1.0, 1.0, 0.85)),
		Vector3(c.x - BULK_HALF.x - 0.01, 1.4, c.z), Vector2(1.6, 0.8), Vector3.LEFT)
	add_perch("stairwell roof", "bulkhead", Vector3(lx, BULK_H + 0.12, fz - 0.45), Vector3(lx, 0.0, -4.4),
		footprint(Vector2(c.x, c.z), BULK_HALF + Vector2(0.02, 0.2), "THE STAIRWELL", "Stairwell Door Crash", 250, "metal_hit"))


func _build_water_tower() -> void:
	# Wooden-stave water tank on a riveted steel stand (deck 3.8 m): the tallest perch, ladder in front.
	var t := TOWER_C
	var steel := Color(0.3, 0.28, 0.27)
	var legs: Array[Vector3] = []
	for sx: float in [-1.25, 1.25]:
		for sz: float in [-1.25, 1.25]:
			legs.append(t + Vector3(sx, 0, sz))
	for lp: Vector3 in legs:
		m._bx("metal", Vector3(0.2, TOWER_DECK, 0.2), lp + Vector3(0, TOWER_DECK * 0.5, 0), steel)
		m._bx("block", Vector3(0.45, 0.2, 0.45), lp + Vector3(0, 0.1, 0), Color(0.55, 0.53, 0.5))
	var sides: Array = [[legs[0], legs[1]], [legs[2], legs[3]], [legs[0], legs[2]], [legs[1], legs[3]]]
	for sd: Array in sides:
		var a: Vector3 = sd[0]
		var b: Vector3 = sd[1]
		m._beam("metal", a + Vector3(0, 0.4, 0), b + Vector3(0, TOWER_DECK - 0.3, 0), 0.06, steel)
		m._beam("metal", b + Vector3(0, 0.4, 0), a + Vector3(0, TOWER_DECK - 0.3, 0), 0.06, steel)
		m._beam("metal", a + Vector3(0, 1.9, 0), b + Vector3(0, 1.9, 0), 0.08, steel)
	# Deck: steel grating disc + joists, railing around the back half.
	m._cy("metal", 2.0, 2.0, 0.1, t + Vector3(0, TOWER_DECK - 0.05, 0), Color(0.34, 0.32, 0.3), 16)
	m._bx("metal", Vector3(3.0, 0.16, 0.16), t + Vector3(0, TOWER_DECK - 0.18, 1.25), steel)
	m._bx("metal", Vector3(3.0, 0.16, 0.16), t + Vector3(0, TOWER_DECK - 0.18, -1.25), steel)
	for k in 7:
		var a0 := PI + PI * k / 6.0
		var p0 := t + Vector3(cos(a0) * 1.95, TOWER_DECK, sin(a0) * 1.95)
		m._beam("metal", p0, p0 + Vector3(0, 1.0, 0), 0.04, steel)
		if k < 6:
			var a1 := PI + PI * (k + 1) / 6.0
			var p1 := t + Vector3(cos(a1) * 1.95, TOWER_DECK, sin(a1) * 1.95)
			m._beam("metal", p0 + Vector3(0, 1.0, 0), p1 + Vector3(0, 1.0, 0), 0.04, steel)
	# The tank: weathered cedar staves, steel hoops, conical roof with a finial and a red beacon.
	var tank_h := 3.4
	var tc := t + Vector3(0, TOWER_DECK + tank_h * 0.5, 0)
	m._cy("wood", 1.6, 1.6, tank_h, tc, Color(0.48, 0.36, 0.28), 18)
	for k in 5:
		m._cy("metal", 1.63, 1.63, 0.05, t + Vector3(0, TOWER_DECK + 0.3 + k * 0.7, 0), Color(0.22, 0.2, 0.2), 18)
	m._cy("metal", 1.8, 0.05, 1.3, t + Vector3(0, TOWER_DECK + tank_h + 0.65, 0), Color(0.24, 0.23, 0.24), 18)
	m._cy("metal", 0.05, 0.05, 0.6, t + Vector3(0, TOWER_DECK + tank_h + 1.5, 0), steel, 6)
	m._bx("glow", Vector3(0.14, 0.14, 0.14), t + Vector3(0, TOWER_DECK + tank_h + 1.85, 0), Color(1.0, 0.12, 0.08))
	# Painted name on the tank, faded.
	var lab := Label3D.new()
	lab.text = "MAGNOLIA\nBLDG."
	lab.font_size = 64
	lab.pixel_size = 0.008
	lab.outline_size = 0
	lab.modulate = Color(0.85, 0.82, 0.7, 0.55)
	lab.shaded = true
	lab.position = t + Vector3(0, TOWER_DECK + 1.9, 1.62)
	add_child(lab)
	# Ladder from the roof to the front edge of the deck (with a few safety-cage hoops).
	var lb := Vector3(t.x, 0, -5.3)
	var lt := Vector3(t.x, TOWER_DECK + 1.0, -5.62)
	var rail := Color(0.62, 0.55, 0.3)
	for s: float in [-0.22, 0.22]:
		m._beam("metal", lb + Vector3(s, 0, 0), lt + Vector3(s, 0, 0), 0.05, rail)
	for k in 15:
		m._bx("metal", Vector3(0.44, 0.035, 0.035), lb.lerp(lt, (k + 0.7) / 16.0), rail)
	for k in 3:
		var y := 2.2 + k * 0.8
		var zc := lerpf(lb.z, lt.z, y / lt.y)
		var prev := Vector3(t.x - 0.3, y, zc)
		for j in range(1, 7):
			var ang := PI * j / 6.0
			var p := Vector3(t.x - 0.3 * cos(ang), y, zc + 0.45 * sin(ang))
			m._beam("metal", prev, p, 0.03, rail)
			prev = p
	add_perch("water tower", "roof", Vector3(t.x, TOWER_DECK, -5.75), Vector3(t.x, 0.0, -4.4),
		footprint(Vector2(t.x, t.z), Vector2(1.38, 1.38), "THE WATER TOWER", "Water Tower Crash", 300, "metal_hit"))
	obstacles.append(footprint(Vector2(t.x, -5.35), Vector2(0.28, 0.1), "THE LADDER", "Ladder Crash", 250, "metal_hit"))


func _build_billboard() -> void:
	# Rooftop billboard behind the bulkhead, facing the camera: steel I-beam frame, catwalk, three
	# lamp arms; the panel is Starla Volt's new single (ch3) - lit, so it reads at night.
	var z := -10.2
	var x0 := -7.0
	var x1 := -0.6
	var y0 := 3.7
	var y1 := 7.0
	var cx := (x0 + x1) * 0.5
	var steel := Color(0.26, 0.25, 0.26)
	for px: float in [x0 + 0.5, cx, x1 - 0.5]:
		m._bx("metal", Vector3(0.22, y1, 0.22), Vector3(px, y1 * 0.5, z - 0.35), steel)
		m._beam("metal", Vector3(px, 0, z + 1.0), Vector3(px, y0, z - 0.3), 0.12, steel)   # kicker brace
	m._bx("metal", Vector3(x1 - x0 + 0.3, 0.16, 0.16), Vector3(cx, y0 - 0.1, z - 0.2), steel)
	m._bx("metal", Vector3(x1 - x0 + 0.3, 0.16, 0.16), Vector3(cx, y1 + 0.05, z - 0.2), steel)
	m._bx("glow", Vector3(x1 - x0, y1 - y0, 0.06), Vector3(cx, (y0 + y1) * 0.5, z), Color(0.52, 0.16, 0.34))
	m._bx("glow", Vector3(x1 - x0, 0.9, 0.065), Vector3(cx, y0 + 0.45, z + 0.005), Color(0.1, 0.05, 0.12))
	m._bx("glow", Vector3(1.6, y1 - y0 - 0.4, 0.065), Vector3(x1 - 1.1, (y0 + y1) * 0.5, z + 0.004), Color(0.75, 0.45, 0.2))  # "photo" block
	# Catwalk + lamp arms
	m._bx("metal", Vector3(x1 - x0, 0.06, 0.7), Vector3(cx, y0 - 0.25, z + 0.35), Color(0.3, 0.3, 0.3))
	for k in 3:
		var lx := lerpf(x0 + 1.0, x1 - 1.0, k / 2.0)
		m._beam("metal", Vector3(lx, y0 - 0.2, z + 0.65), Vector3(lx, y0 + 0.2, z + 1.2), 0.05, steel)
		m._bx("flat", Vector3(0.45, 0.16, 0.25), Vector3(lx, y0 + 0.25, z + 1.25), Color(0.15, 0.15, 0.16))
		m._bx("glow", Vector3(0.4, 0.04, 0.2), Vector3(lx, y0 + 0.17, z + 1.25), Color(1.0, 0.9, 0.7))
	var lines: Array[String] = ["STARLA VOLT", "HEARTBREAK SUPLEX", "THE NEW SINGLE - OUT NOW"]
	var sizes: Array[int] = [100, 60, 30]
	var cols: Array[Color] = [Color(1.0, 0.96, 0.9), Color(1.0, 0.85, 0.2), Color(0.9, 0.85, 0.95)]
	var ys: Array[float] = [6.15, 5.25, 4.1]
	for i in 3:
		var lab := Label3D.new()
		lab.text = lines[i]
		lab.font_size = sizes[i]
		lab.pixel_size = 0.006
		lab.outline_size = 10 if i < 2 else 0
		lab.outline_modulate = Color(0.2, 0.03, 0.12)
		lab.modulate = cols[i]
		lab.position = Vector3(cx - 0.9, ys[i], z + 0.06)
		lab.rotation_degrees = Vector3(0, 0, 3.0 if i == 1 else 0.0)
		add_child(lab)
	var bo: OmniLight3D = m.make_omni(Vector3(cx, y0 + 0.8, z + 2.2), 6.0, 0.9, Color(1.0, 0.75, 0.8))
	bo.omni_attenuation = 1.6


func _build_perches() -> void:
	# AC unit by the left parapet (top 1.3): curb, louvred sides, fan grille on top.
	var a := AC_C
	var ac := Color(0.64, 0.63, 0.58)
	m._bx("block", Vector3(1.6, 0.15, 2.3), a + Vector3(0, 0.075, 0), Color(0.5, 0.49, 0.46))
	m._bx("metal", Vector3(1.5, 1.15, 2.2), a + Vector3(0, 0.15 + 0.575, 0), ac)
	for k in 7:
		m._bx("flat", Vector3(0.02, 0.05, 1.8), a + Vector3(0.755, 0.35 + k * 0.1, 0), Color(0.18, 0.18, 0.17))
	m._cy("flat", 0.5, 0.5, 0.03, a + Vector3(0, 1.31, 0.45), Color(0.08, 0.08, 0.08), 14)
	for k in 4:
		m._bx("metal", Vector3(1.0, 0.02, 0.03), a + Vector3(0, 1.33, 0.45), Color(0.4, 0.4, 0.4), PI * k / 4.0)
	m._bx("flat", Vector3(0.5, 0.25, 0.02), a + Vector3(0.755, 1.0, -0.6), Color(0.85, 0.82, 0.7))   # data plate
	m._bx("metal", Vector3(0.8, 0.6, 0.6), a + Vector3(-0.3, 0.45, -1.4), ac.darkened(0.1))          # duct to the roof
	m._bx("flat", Vector3(1.6, 0.04, 0.04), a + Vector3(0, 0.9, 1.11), Color(0.5, 0.38, 0.2))        # rust streak
	add_perch("AC unit", "ac_unit", a + Vector3(0, 1.3, 0), Vector3(a.x + 1.35, 0.0, a.z),
		footprint(Vector2(a.x, a.z - 0.15), Vector2(0.8, 1.3), "THE AC UNIT", "AC Unit Crash", 200, "metal_hit"))

	# Crate stack by the right parapet (top 1.1): a black road case under a wooden crate + a step crate.
	var c := CRATE_C
	var wood := Color(0.6, 0.48, 0.34)
	m._bx("flat", Vector3(1.2, 0.6, 0.95), c + Vector3(0, 0.3, 0), Color(0.08, 0.08, 0.09))
	for sy: float in [0.02, 0.58]:
		m._bx("metal", Vector3(1.22, 0.04, 0.97), c + Vector3(0, sy, 0), Color(0.6, 0.6, 0.62))
	for sx: float in [-0.6, 0.6]:
		m._bx("metal", Vector3(0.04, 0.6, 0.97), c + Vector3(sx, 0.3, 0), Color(0.6, 0.6, 0.62))
	m._bx("flat", Vector3(0.5, 0.15, 0.02), c + Vector3(0.1, 0.35, 0.48), Color(0.9, 0.88, 0.8))      # stencil tag
	m._bx("wood", Vector3(1.0, 0.5, 0.9), c + Vector3(0.05, 0.85, 0.0), wood, 0.06)
	for k in 3:
		m._bx("wood", Vector3(1.02, 0.07, 0.92), c + Vector3(0.05, 0.64 + k * 0.2, 0.0), wood.darkened(0.15), 0.06)
	m._bx("wood", Vector3(0.6, 0.5, 0.6), c + Vector3(-0.85, 0.25, 0.1), wood.darkened(0.05), -0.2)
	add_perch("crate stack", "crates", c + Vector3(0, 1.1, 0), Vector3(c.x - 1.4, 0.0, c.z),
		footprint(Vector2(c.x - 0.15, c.z), Vector2(0.78, 0.5), "THE CRATES", "Crate Crash", 200, "wood_hit"))

	# The stairwell bulkhead and the water tower are perches too (their own builders).


func _build_roof_props() -> void:
	var steel := Color(0.55, 0.56, 0.55)
	# Vent stacks (one each side), with rain caps.
	for v: Vector3 in [Vector3(-6.75, 0, -3.4), Vector3(6.8, 0, 0.8)]:
		m._cy("metal", 0.17, 0.17, 1.2, v + Vector3(0, 0.6, 0), steel, 10)
		m._cy("metal", 0.32, 0.05, 0.22, v + Vector3(0, 1.32, 0), steel.darkened(0.1), 10)
		m._cy("flat", 0.28, 0.28, 0.1, v + Vector3(0, 0.05, 0), Color(0.08, 0.08, 0.08), 10)  # tar boot
		obstacles.append(footprint(Vector2(v.x, v.z), Vector2(0.2, 0.2), "THE VENT STACK", "Vent Stack Crash", 150, "metal_hit", 0.2))
	# A few more stacks / mushroom vents outside the fight area.
	for v: Vector3 in [Vector3(0.6, 0, -9.6), Vector3(-6.6, 0, -9.8), Vector3(6.7, 0, -9.9)]:
		m._cy("metal", 0.12, 0.12, 0.8, v + Vector3(0, 0.4, 0), steel, 8)
		m._cy("metal", 0.25, 0.04, 0.16, v + Vector3(0, 0.88, 0), steel, 8)
	# Skylights: wired-glass hip roofs on curbs, glowing from the hallway lights below.
	for sk: Array in [[Vector3(1.6, 0, -4.15), Vector2(0.75, 0.45)], [Vector3(-0.4, 0, -9.3), Vector2(0.9, 0.6)], [Vector3(2.4, 0, -9.6), Vector2(0.9, 0.6)]]:
		var p: Vector3 = sk[0]
		var hh: Vector2 = sk[1]
		m._bx("block", Vector3(hh.x * 2.0, 0.28, hh.y * 2.0), p + Vector3(0, 0.14, 0), Color(0.55, 0.53, 0.5))
		m._bx("glow", Vector3(hh.x * 2.0 - 0.1, 0.02, hh.y * 2.0 - 0.1), p + Vector3(0, 0.3, 0), Color(0.42, 0.4, 0.3))
		var st: SurfaceTool = m._st("glow")
		var g := Color(0.2, 0.26, 0.25)
		var y0 := 0.29
		var top := p + Vector3(0, 0.5, 0)
		var c0 := p + Vector3(-hh.x, y0, -hh.y)
		var c1 := p + Vector3(hh.x, y0, -hh.y)
		var c2 := p + Vector3(hh.x, y0, hh.y)
		var c3 := p + Vector3(-hh.x, y0, hh.y)
		var r0 := top + Vector3(-hh.x * 0.5, 0, 0)
		var r1 := top + Vector3(hh.x * 0.5, 0, 0)
		m._quad(st, c3, r0, r1, c2, Vector3(0, 0.8, 0.6), Vector3.RIGHT, Vector3.UP, g, 1.0)
		m._quad(st, c1, r1, r0, c0, Vector3(0, 0.8, -0.6), Vector3.LEFT, Vector3.UP, g.darkened(0.2), 1.0)
		m._tri(st, c0, r0, c3, Vector3(-0.7, 0.7, 0), Vector3.BACK, Vector3.UP, g.darkened(0.1), 1.0)
		m._tri(st, c2, r1, c1, Vector3(0.7, 0.7, 0), Vector3.FORWARD, Vector3.UP, g.darkened(0.1), 1.0)
		m._beam("metal", r0, r1, 0.04, steel)
		for corner: Vector3 in [c0, c1, c2, c3]:
			m._beam("metal", corner, r0 if corner.x < p.x else r1, 0.03, steel)
		if p.z > -5.0 - hh.y - 0.1:
			obstacles.append(footprint(Vector2(p.x, p.z), hh, "THE SKYLIGHT", "Skylight Crash", 200, "metal_hit"))
	# Satellite dish on a ballast mount by the right parapet, aimed up at the southern sky.
	var sd := Vector3(7.0, 0, -3.3)
	m._bx("block", Vector3(0.7, 0.14, 0.7), sd + Vector3(0, 0.07, 0), Color(0.5, 0.48, 0.45))
	m._beam("metal", sd + Vector3(0, 0.14, 0), sd + Vector3(0, 1.15, 0), 0.06, steel)
	var dish_xf := Transform3D(Basis(Vector3.RIGHT, -0.75) * Basis(Vector3.FORWARD, 0.3), sd + Vector3(-0.05, 1.3, -0.05))
	m._scyl("metal", 0.08, 0.55, 0.16, dish_xf, Color(0.78, 0.78, 0.76), 14)
	var lnb := dish_xf * Vector3(0, 0.6, 0)
	m._beam("metal", dish_xf * Vector3(0, 0.05, 0.4), lnb, 0.03, steel)
	m._bx("flat", Vector3(0.09, 0.09, 0.12), lnb, Color(0.2, 0.2, 0.2))
	obstacles.append(footprint(Vector2(sd.x, sd.z), Vector2(0.38, 0.38), "THE SATELLITE DISH", "Satellite Dish Crash", 200, "metal_hit"))
	# Low conduit run along the back edge of the fight area (on little sleeper blocks).
	for py: float in [0.18, 0.3]:
		m._beam("metal", Vector3(-1.2, py, -5.3), Vector3(2.9, py, -5.3), 0.07, Color(0.45, 0.42, 0.38))
	for k in 5:
		m._bx("block", Vector3(0.18, 0.12, 0.3), Vector3(-1.0 + k * 0.95, 0.06, -5.3), Color(0.5, 0.48, 0.45))
	# Small condenser units out back, coolant lines.
	for cc: Vector3 in [Vector3(-0.5, 0, -10.4), Vector3(1.3, 0, -10.4)]:
		m._bx("metal", Vector3(1.0, 0.85, 0.7), cc + Vector3(0, 0.43, 0), Color(0.62, 0.62, 0.6))
		m._cy("flat", 0.3, 0.3, 0.02, cc + Vector3(0, 0.87, 0), Color(0.08, 0.08, 0.08), 12)


func _make_beam_cone(from: Vector3, aim: Vector3, length: float, half_angle_deg: float, tint: Color, strength: float) -> void:
	# A faint additive cone so a stage light's beam reads in the night haze.
	var cone := CylinderMesh.new()
	cone.top_radius = 0.12
	cone.bottom_radius = tan(deg_to_rad(half_angle_deg)) * length
	cone.height = length
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	mat.set_shader_parameter("strength", strength)
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := (aim - from).normalized()
	beam.transform = Transform3D(Basis(Quaternion(Vector3.DOWN, dir)), from + dir * length * 0.5)
	add_child(beam)


func _fixture(light: SpotLight3D, lens: Color) -> void:
	# Par can / fresnel head drawn at the light (box + lit lens + yoke).
	m._sbox("flat", Vector3(0.32, 0.32, 0.42), light.transform, Color(0.07, 0.07, 0.08))
	m._sbox("glow", Vector3(0.26, 0.26, 0.04), light.transform * Transform3D(Basis(), Vector3(0, 0, -0.22)), lens)
	m._beam("metal", light.position, light.position + Vector3(0, 0.35, 0), 0.04, Color(0.2, 0.2, 0.2))


func _truss(a: Vector3, b: Vector3) -> void:
	# Box truss (4 chords + zig-zag lacing) from a to b.
	var d := b - a
	var l := d.length()
	var dir := d / l
	var up := Vector3.UP if absf(dir.y) < 0.9 else Vector3.BACK
	var s1 := dir.cross(up).normalized() * 0.15
	var s2 := dir.cross(s1).normalized() * 0.15
	var col := Color(0.72, 0.72, 0.74)
	var offs: Array[Vector3] = [s1 + s2, s1 - s2, -s1 - s2, -s1 + s2]
	for o: Vector3 in offs:
		m._beam("metal", a + o, b + o, 0.035, col)
	var n := int(l / 0.5)
	for k in n:
		var p0 := a + dir * (k * l / n)
		var p1 := a + dir * ((k + 1) * l / n)
		for i in 4:
			var oa: Vector3 = offs[i]
			var ob: Vector3 = offs[(i + 1) % 4]
			m._beam("metal", p0 + oa, p1 + ob, 0.02, col)


func _build_stage_rig() -> void:
	# The music-video lighting: a goalpost truss over the camera side carries the warm key and a
	# cyan wash; a tripod light stand at the back right throws a magenta rim; road gear around.
	var ty := 6.2
	var tz := 5.3
	for sx: float in [-7.15, 7.15]:
		_truss(Vector3(sx, 0.0, tz), Vector3(sx, ty, tz))
		m._bx("metal", Vector3(0.7, 0.04, 0.7), Vector3(sx, 0.02, tz), Color(0.3, 0.3, 0.3))
		obstacles.append(footprint(Vector2(sx, tz), Vector2(0.22, 0.22), "THE TRUSS", "Truss Crash", 200, "metal_hit"))
	_truss(Vector3(-7.15, ty, tz), Vector3(7.15, ty, tz))
	# Key light (warm white fresnel), its shadow is the scene's one shadow map.
	var key: SpotLight3D = m.make_spot(Vector3(-2.6, ty - 0.45, tz), Vector3(0.4, 0.0, -0.8), 52.0, 22.0, 4.4, Color(1.0, 0.88, 0.72))
	key.spot_angle_attenuation = 1.2
	_fixture(key, Color(1.0, 0.92, 0.75))
	key_light = key
	# Cool cyan wash from the right of the truss.
	var cy: SpotLight3D = m.make_spot(Vector3(3.6, ty - 0.45, tz), Vector3(-0.6, 0.0, -2.0), 42.0, 18.0, 2.4, Color(0.4, 0.75, 1.0))
	_fixture(cy, Color(0.55, 0.85, 1.0))
	# Magenta rim from a tripod stand at the back right.
	var stand := Vector3(6.55, 0.0, -4.45)
	var head := stand + Vector3(0, 2.7, 0)
	var mg: SpotLight3D = m.make_spot(head, Vector3(-0.5, 0.0, 0.8), 48.0, 14.0, 3.2, Color(1.0, 0.25, 0.7))
	mg.spot_angle_attenuation = 1.0
	_fixture(mg, Color(1.0, 0.45, 0.8))
	var dark := Color(0.1, 0.1, 0.11)
	m._beam("flat", stand + Vector3(0, 0.9, 0), head, 0.05, dark)
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		m._beam("flat", stand + Vector3(cos(a) * 0.55, 0, sin(a) * 0.55), stand + Vector3(0, 0.95, 0), 0.035, dark)
	m._bx("flat", Vector3(0.25, 0.25, 0.25), stand + Vector3(0.0, 0.12, 0.45), Color(0.65, 0.12, 0.1))   # sandbag
	obstacles.append(footprint(Vector2(stand.x, stand.z), Vector2(0.4, 0.4), "THE LIGHT STAND", "Light Stand Crash", 200, "metal_hit", 0.4))
	# Haze in the beams.
	_make_beam_cone(key.position, Vector3(0.4, 0.0, -0.8), 7.5, 22.0, Color(1.0, 0.9, 0.72), 0.05)
	_make_beam_cone(cy.position, Vector3(-0.6, 0.0, -2.0), 7.0, 18.0, Color(0.4, 0.75, 1.0), 0.05)
	_make_beam_cone(head, Vector3(-0.5, 0.0, 0.8), 6.5, 20.0, Color(1.0, 0.3, 0.75), 0.06)
	# Speaker stack (playback) at the front left corner, cables snaking off.
	var sp := Vector3(-6.3, 0.0, 5.2)
	m._bx("flat", Vector3(0.75, 0.9, 0.55), sp + Vector3(0, 0.45, 0), Color(0.07, 0.07, 0.08), 0.25)
	m._bx("flat", Vector3(0.65, 0.6, 0.5), sp + Vector3(0, 1.2, 0), Color(0.08, 0.08, 0.09), 0.2)
	m._scyl("flat", 0.24, 0.24, 0.02, Transform3D(Basis(Vector3.UP, 0.25) * Basis(Vector3.RIGHT, PI * 0.5), sp + Vector3(0.06, 0.45, 0.27)), Color(0.15, 0.15, 0.16), 12)
	obstacles.append(footprint(Vector2(sp.x, sp.z), Vector2(0.42, 0.32), "THE SPEAKERS", "Speaker Stack Crash", 200, "thud"))
	var cable := Color(0.03, 0.03, 0.03)
	var pts: Array[Vector3] = [Vector3(-7.0, 0.02, 5.2), Vector3(-6.0, 0.02, 4.6), Vector3(-6.4, 0.02, 3.2), Vector3(-7.2, 0.02, 2.9)]
	for i in pts.size() - 1:
		m._beam("flat", pts[i], pts[i + 1], 0.03, cable)
	var pts2: Array[Vector3] = [Vector3(6.4, 0.02, -4.2), Vector3(5.2, 0.02, -4.9), Vector3(3.0, 0.02, -5.15), Vector3(1.2, 0.02, -5.6), Vector3(0.6, 0.02, -6.6)]
	for i in pts2.size() - 1:
		m._beam("flat", pts2[i], pts2[i + 1], 0.03, cable)
	# Video village between the bulkhead and the tower: monitor on a C-stand, a road case seat,
	# a haze machine, the director's chair.
	var mon := Vector3(1.9, 0.0, -6.5)
	m._beam("flat", mon, mon + Vector3(0, 1.4, 0), 0.04, dark)
	m._bx("flat", Vector3(0.62, 0.4, 0.06), mon + Vector3(0, 1.55, 0), dark, 0.25)
	m._bx("glow", Vector3(0.54, 0.32, 0.065), mon + Vector3(0, 1.55, 0.01), Color(0.45, 0.55, 0.7), 0.25)
	m._bx("flat", Vector3(1.0, 0.52, 0.6), Vector3(0.5, 0.26, -6.75), Color(0.08, 0.08, 0.09))
	m._bx("metal", Vector3(1.02, 0.03, 0.62), Vector3(0.5, 0.52, -6.75), Color(0.6, 0.6, 0.62))
	m._bx("flat", Vector3(0.45, 0.3, 0.6), Vector3(-0.9, 0.15, -5.75), Color(0.12, 0.12, 0.14))
	m._bx("glow", Vector3(0.1, 0.06, 0.02), Vector3(-0.8, 0.22, -5.44), Color(0.2, 1.0, 0.3))
	var dc := Vector3(-0.3, 0.0, -7.6)
	m._bx("flat", Vector3(0.55, 0.05, 0.45), dc + Vector3(0, 0.62, 0), Color(0.12, 0.12, 0.12))
	m._bx("flat", Vector3(0.55, 0.35, 0.04), dc + Vector3(0, 1.0, -0.22), Color(0.12, 0.12, 0.12))
	for sx: float in [-0.27, 0.27]:
		m._beam("wood", dc + Vector3(sx, 0, -0.2), dc + Vector3(sx, 0.62, 0.2), 0.04, Color(0.55, 0.42, 0.28))
		m._beam("wood", dc + Vector3(sx, 0, 0.2), dc + Vector3(sx, 0.62, -0.2), 0.04, Color(0.55, 0.42, 0.28))
		m._beam("wood", dc + Vector3(sx, 0.62, -0.22), dc + Vector3(sx, 1.2, -0.22), 0.04, Color(0.55, 0.42, 0.28))
	# The bulkhead's caged bulb (warm practical).
	m.make_omni(Vector3(BULK_C.x - 0.9, 2.4, BULK_C.z + BULK_HALF.y + 0.45), 5.0, 1.1, Color(1.0, 0.72, 0.4))


func _hang(a: Vector3, b: Vector3, sag: float, t: float) -> Vector3:
	return a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)


func _build_string_lights() -> void:
	# Party bistro lights (ch5's rooftop party) from the bulkhead over the crew area to the tower.
	var strands: Array = [[Vector3(-1.4, 2.95, -5.35), Vector3(3.15, 3.2, -6.35)], [Vector3(-1.4, 2.95, -8.05), Vector3(3.15, 3.2, -8.85)],
		[Vector3(-1.4, 2.95, -5.35), Vector3(3.15, 3.2, -8.85)], [Vector3(-5.0, 2.95, -5.35), Vector3(-ROOF_X, 1.9, -3.0)]]
	m._bx("wood", Vector3(0.1, 2.0, 0.1), Vector3(-ROOF_X + 0.1, 1.0, -3.0), Color(0.4, 0.33, 0.27))  # strand pole
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var bulb := [Color(1.0, 0.78, 0.45), Color(0.98, 0.7, 0.38), Color(1.0, 0.82, 0.5)]
	for s: Array in strands:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var prev := a
		for k in range(1, 9):
			var p := _hang(a, b, 0.5, k / 8.0)
			m._beam("flat", prev, p, 0.02, Color(0.04, 0.04, 0.04))
			prev = p
		var nb := int(a.distance_to(b) / 0.6)
		for k in nb:
			xforms.append(Transform3D(Basis(), _hang(a, b, 0.5, (k + 0.5) / nb) - Vector3(0, 0.07, 0)))
			cols.append(bulb[k % 3])
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
		mm.set_instance_color(i, cols[i])
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.vertex_color_use_as_albedo = true
	bm.vertex_color_is_srgb = true
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	m.make_omni(Vector3(0.9, 2.5, -6.8), 6.0, 0.9, Color(1.0, 0.76, 0.45))


func _build_neighbors() -> void:
	# Right: a taller apartment block right across a light well, its lit windows facing us.
	_facade_box(Vector3(22.0, 62.0, 44.0), Vector3(20.5, -21.0, -10.0), Color(0.9, 0.86, 0.85))
	m._bx("brick", Vector3(0.4, 1.0, 44.0), Vector3(9.7, 10.5, -10.0), Color(0.6, 0.5, 0.46))
	m._bx("glow", Vector3(0.1, 0.12, 0.12), Vector3(9.45, 10.9, -2.0), Color(1.0, 0.15, 0.1))
	# Left: a lower building (roof ~4 m down) with its own water tank and a lit stair door.
	_facade_box(Vector3(20.0, 46.0, 40.0), Vector3(-19.5, -27.0, -8.0), Color(0.75, 0.72, 0.75), Color(0.2, 0.19, 0.18))
	var lt := Vector3(-16.0, -3.9, -14.0)
	for sx: float in [-0.9, 0.9]:
		for sz: float in [-0.9, 0.9]:
			m._bx("metal", Vector3(0.15, 3.0, 0.15), lt + Vector3(sx, 1.5, sz), Color(0.12, 0.12, 0.12))
	m._cy("wood", 1.2, 1.2, 2.6, lt + Vector3(0, 4.3, 0), Color(0.3, 0.24, 0.2), 12)
	m._cy("flat", 1.3, 0.05, 1.0, lt + Vector3(0, 6.1, 0), Color(0.12, 0.12, 0.13), 12)
	m._bx("brick", Vector3(2.4, 2.4, 2.4), Vector3(-13.0, -2.7, -2.0), Color(0.5, 0.42, 0.4))
	m._bx("glow", Vector3(0.9, 1.8, 0.05), Vector3(-13.0, -3.0, -0.78), Color(0.7, 0.55, 0.3))


func _build_skyline() -> void:
	# Downtown behind the -z backdrop: two arcs of towers with lit windows, red beacons on the
	# tall ones, a couple of antenna masts. Bases far below the roof so the haze swallows them.
	var tints: Array[Color] = [Color(1, 1, 1), Color(0.85, 0.9, 1.0), Color(1.0, 0.92, 0.82), Color(0.75, 0.75, 0.8)]
	for ring in 2:
		var count := 18 if ring == 0 else 22
		for i in count:
			var ang := lerpf(-1.35, 1.35, (i + _rng.randf_range(0.1, 0.9)) / count)
			var dist := (_rng.randf_range(50.0, 80.0) if ring == 0 else _rng.randf_range(105.0, 160.0))
			var p := Vector3(sin(ang) * dist, 0.0, -cos(ang) * dist - 8.0)
			if p.x > 4.0 and p.x < 44.0 and p.z > -42.0:
				continue  # behind the right-hand neighbor
			var w := _rng.randf_range(10.0, 22.0)
			var dd := _rng.randf_range(10.0, 20.0)
			var centrality := 1.0 - absf(ang) / 1.35
			var top := _rng.randf_range(-6.0, 18.0) + centrality * (22.0 if ring == 0 else 45.0)
			var base := -60.0
			var h := top - base
			var tint: Color = tints[_rng.randi() % tints.size()]
			_facade_box(Vector3(w, h, dd), Vector3(p.x, base + h * 0.5, p.z), tint.darkened(0.1 if ring == 0 else 0.3))
			if top > 22.0:
				m._bx("glow", Vector3(0.6, 0.6, 0.6), Vector3(p.x, top + 0.6, p.z), Color(1.0, 0.12, 0.08))
			if top > 40.0 and _rng.randf() < 0.5:
				m._beam("metal", Vector3(p.x, top, p.z), Vector3(p.x, top + 14.0, p.z), 0.5, Color(0.15, 0.15, 0.16))
				m._bx("glow", Vector3(0.7, 0.7, 0.7), Vector3(p.x, top + 14.3, p.z), Color(1.0, 0.15, 0.1))
			elif _rng.randf() < 0.3:
				# a lit crown band
				m._bx("glow", Vector3(w + 0.2, 1.0, dd + 0.2), Vector3(p.x, top - 1.5, p.z), Color(0.9, 0.75, 0.5) if _rng.randf() < 0.6 else Color(0.4, 0.6, 0.9))


func _build_grime() -> void:
	var ix := ROOF_X - 0.17
	m._grime_wall(Vector3(-ix, 0, BACK_Z + 0.2), Vector3(-ix, 0, FRONT_Z - 0.2), Vector3.RIGHT, 0.7, 0.5)
	m._grime_wall(Vector3(ix, 0, FRONT_Z - 0.2), Vector3(ix, 0, BACK_Z + 0.2), Vector3.LEFT, 0.7, 0.5)
	m._grime_wall(Vector3(-ix, 0, FRONT_Z - 0.17), Vector3(ix, 0, FRONT_Z - 0.17), Vector3.FORWARD, 0.4, 0.4)
	var fz := BULK_C.z + BULK_HALF.y + 0.01
	m._grime_wall(Vector3(BULK_C.x - BULK_HALF.x, 0, fz), Vector3(BULK_C.x + BULK_HALF.x, 0, fz), Vector3.BACK, 0.8, 0.5)
	m._grime_wall(Vector3(AC_C.x + 0.76, 0, AC_C.z - 1.1), Vector3(AC_C.x + 0.76, 0, AC_C.z + 1.1), Vector3.RIGHT, 0.5, 0.4)
	m._flush_grime()


# ---- the crew and friends watching (main.build_crowd)

func _fan(p: Vector3, person: String, lit := 0.55, bob := 1.0) -> void:
	crowd_spots.append({"pos": p, "person": person, "lit": lit, "bob": bob})


func _build_crowd_spots() -> void:
	# The music-video crew + party friends; nobody inside the fight area or on a perch top.
	crowd_spots = []
	# Left of the bulkhead (by the door side)
	for spot: Vector3 in [Vector3(-5.7, 0, -5.6), Vector3(-6.5, 0, -6.4), Vector3(-5.6, 0, -7.3), Vector3(-6.7, 0, -8.4)]:
		_fan(spot + Vector3(randf_range(-0.1, 0.1), 0.0, randf_range(-0.1, 0.1)), "stand", 0.55)
	_fan(Vector3(-6.2, 0, -5.4), "girl", 0.6)
	# Video village between the bulkhead and the water tower
	_fan(Vector3(-0.6, 0, -5.6), "filmer", 0.6, 1.3)
	_fan(Vector3(2.6, 0, -5.65), "filmer", 0.55, 1.3)
	_fan(Vector3(0.5, 0.0, -6.75), "sit", 0.55)        # on the road case (seat 0.53)
	_fan(Vector3(-0.3, 0.09, -7.55), "sit_cup", 0.5)    # the director's chair
	_fan(Vector3(1.2, 0, -5.8), "cheer", 0.6)
	_fan(Vector3(1.0, 0, -7.9), "jacket", 0.5)
	_fan(Vector3(-1.0, 0, -8.6), "hoodie", 0.5)
	_fan(Vector3(2.4, 0, -8.2), "girl", 0.5)
	# Up on the bulkhead roof (behind the perch spot): a high-angle camera op + a friend
	_fan(Vector3(-4.3, BULK_H + 0.12, -6.3), "filmer", 0.5, 1.2)
	_fan(Vector3(-3.4, BULK_H + 0.12, -7.6), "stand", 0.45)
	# Around the water tower legs
	for spot: Vector3 in [Vector3(6.4, 0, -5.8), Vector3(6.9, 0, -7.1), Vector3(6.3, 0, -8.6), Vector3(3.6, 0, -9.6)]:
		_fan(spot, "stand", 0.5)
	# Sitting on the side parapets (coping 1.08)
	_fan(Vector3(-ROOF_X - 0.05, PARAPET_H + 0.08 - 0.53, -1.0), "sit", 0.5)
	_fan(Vector3(-ROOF_X - 0.05, PARAPET_H + 0.08 - 0.53, 4.2), "sit_cup", 0.55)
	_fan(Vector3(ROOF_X + 0.05, PARAPET_H + 0.08 - 0.53, -0.2), "sit", 0.5)
	_fan(Vector3(ROOF_X + 0.05, PARAPET_H + 0.08 - 0.53, 1.9), "sit_cup", 0.5)

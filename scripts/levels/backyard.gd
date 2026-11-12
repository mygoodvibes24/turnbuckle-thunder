extends "res://scripts/levels/level_base.gd"
## THE BACKYARD (level id "backyard"): Tank's mom's backyard at night. The original yard, moved
## out of main.gd unchanged (yard_contract.md): they fight on the lawn and the concrete patio,
## house + porch along -z, privacy fences along +-x, a low picket fence on the camera side (+z).
## Fighting area x -7..7, z -5..5; ground y 0; everything local to ring_root (= world).
##
## Helpers used on main (m) - any level can call them:
##   merged static geometry (one mesh per material key; flushed by m._flush_batches()):
##     m._bx(key, size, pos, col, yaw := 0.0, uvs := 1.0)        box
##     m._sbox(key, size, xform, col, uvs := 1.0)                 box with a full Transform3D
##     m._cy(key, r_bottom, r_top, h, pos, col, segs := 8)       cylinder / cone (centre pos)
##     m._scyl(key, r_bottom, r_top, h, xform, col, segs := 8)
##     m._beam(key, from, to, thick, col)                         thin box between two points
##     m._tri(m._st(key), p0, p1, p2, normal, u_axis, v_axis, col, uvs) / m._quad(...)
##     keys: "flat", "glow" (unshaded), "wood", "siding", "shingle", "brick", "block", "metal"
##   single nodes (added under main): m._box(size, pos, col, emissive := false) -> MeshInstance3D,
##     m._plane(size2, pos, material) -> MeshInstance3D, m._ground_quad(center, size2, material,
##     yaw := 0.0, uv_scale := Vector2.ONE) -> MeshInstance3D
##   materials / textures: m._mat(col, emissive), m._tex_mat(tex, scissor, blend),
##     m._make_concrete_texture(n, joints, stains, tires := false), m._make_grass_texture(),
##     m._make_grass_detail(), m._make_wood_texture(), m._make_siding_texture(),
##     m._make_brick_texture(), m._make_shingle_texture(), m._make_tag_texture(text, fill, outline,
##     shine), m._make_spray_texture(), m._make_lawn_map(), m._noise_img(w, h, freq, octaves)
##   grime / decals: m._grime_wall(a, b, out, h, reach, wall_a, floor_a), m._flush_grime(),
##     m._wall_decal(tex, center, size2, out)

const PATIO_RECT := Rect2(-7.5, -8.6, 7.0, 7.1)     # concrete slab: x -7.5..-0.5, z -8.6..-1.5
const DRIVE_RECT := Rect2(4.3, 1.2, 9.5, 2.9)       # driveway strip under the car: x 4.3..13.8, z 1.2..4.1
const LAWN_RECT := Rect2(-7.6, -8.6, 15.2, 15.2)    # painted lawn quad (main.gd _make_lawn_map)
const HOUSE_Z := -8.6                               # back wall of the house
const FENCE_X := 7.5                                # side privacy fences
const FENCE_Z := 5.6                                # low picket fence on the camera side
const FENCE_H := 1.9

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

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

void fragment() {
	// UV.y runs 0 at the lamp to 1 at the far end; fade along the beam and toward the silhouette edges.
	float along = 1.0 - UV.y;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = vec3(1.0, 0.9, 0.7) * 0.07 * along * along * facing;
}
"""

var m = null   # main.gd (helpers)


func _init() -> void:
	display_name = "THE BACKYARD"
	description = "Mom's backyard after dark: lawn, patio, the shed roof, a trampoline and the neighbors watching."
	time_of_day = "night"
	preview_color = Color(0.24, 0.4, 0.18)
	yard_bounds = Rect2(-7.0, -5.0, 14.0, 10.0)
	cam_clamp = Rect2(-5.0, -4.0, 10.0, 7.5)   # yard_bounds inset 2 m on x, 1 m behind, 1.5 m in front
	default_surface = "grass"
	surfaces = [{"rect": PATIO_RECT, "kind": "concrete"}, {"rect": DRIVE_RECT, "kind": "concrete"}]
	spawn_p1 = Vector3(-1.8, 0.0, 0.3)
	spawn_p2 = Vector3(1.8, 0.0, -0.3)


func build(main_node: Node) -> void:
	super(main_node)
	m = main_node
	perches.clear()
	obstacles.clear()
	_build_floods()
	var far: StandardMaterial3D = m._tex_mat(m._make_grass_detail())
	far.albedo_color = Color(0.2, 0.32, 0.1)
	far.uv1_scale = Vector3(60, 60, 1)
	far.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._plane(Vector2(90, 90), Vector3(0, -0.01, 0), far)
	_build_lawn()
	_build_house()
	_build_fence()
	_build_props()
	_build_perches()
	_build_car()
	_build_string_lights()
	_build_yard_lights()
	_build_grime()
	m._flush_batches()
	_build_crowd_spots()
	# Weapons around the yard (yard_contract.md): two chairs near the patio, the trash can by the
	# right fence, the 2x4 by the shed, the folded table leaning on the right fence.
	item_spawns = [
		{"kind": "chair", "pos": Vector3(-0.7, 0.0, -3.6), "yaw": PI * 0.3},  # well clear of the fight-start spots
		{"kind": "chair", "pos": Vector3(-3.3, 0.0, -1.7), "yaw": -PI * 0.2},
		{"kind": "trash_can", "pos": Vector3(6.75, 0.0, -0.6), "yaw": 0.0},
		{"kind": "plank", "pos": Vector3(-6.3, 0.0, 1.9), "yaw": 0.15},
		{"kind": "table", "pos": Vector3(7.1, 0.0, 0.5), "yaw": -PI * 0.5},   # top faces -x (into the yard)
	]


func _build_floods() -> void:
	# Two warm floodlights on tall poles at opposite corners of the yard, each aimed at
	# its own half so the whole fighting area (x -7..7, z -5..5) sits in overlapping
	# pools: bright in the middle, falling off quickly toward the fences and the house.
	# Only the front one (key_light / main.ring_spot) casts a real shadow map.
	var floods: Array[SpotLight3D] = []
	var rigs: Array = [[Vector3(-6.9, 7.2, 5.9), Vector3(-0.4, 0.0, -0.3)],
		[Vector3(6.9, 7.2, -6.2), Vector3(0.4, 0.0, 0.2)]]
	for rig: Array in rigs:
		var corner: Vector3 = rig[0]
		var aim: Vector3 = rig[1]
		var fl := SpotLight3D.new()
		fl.transform = Transform3D(Basis.looking_at(aim - corner), corner)
		fl.spot_angle = 45.0
		fl.spot_angle_attenuation = 1.3  # visible warm pool on the fighting area, soft rim
		fl.spot_range = 20.0
		fl.spot_attenuation = 0.5
		fl.light_energy = 4.0
		fl.light_specular = 0.7
		fl.light_color = Color(1.0, 0.9, 0.75)
		fl.shadow_enabled = false
		add_child(fl)
		floods.append(fl)
		# The pole and lamp head itself.
		var pole_base := Vector3(corner.x * 1.03, 0, corner.z * 1.03)
		m._box(Vector3(0.12, corner.y + 0.2, 0.12), pole_base + Vector3(0, (corner.y + 0.2) * 0.5, 0), Color(0.1, 0.1, 0.11))
		var head: MeshInstance3D = m._box(Vector3(0.7, 0.45, 0.3), Vector3.ZERO, Color(0.16, 0.16, 0.17))
		head.transform = fl.transform
		var lens: MeshInstance3D = m._box(Vector3(0.6, 0.36, 0.04), Vector3.ZERO, Color(1.0, 0.92, 0.75), true)
		lens.transform = fl.transform * Transform3D(Basis(), Vector3(0, 0, -0.17))
	key_light = floods[0]   # main.gd turns its shadow map on (key_light / main.ring_spot)

	# The porch / patio lamp pools by the sliding door live in _build_yard_lights().

	# Faint warm glow from the string lights hanging over the yard (one omni; it used to be two).
	var sl := OmniLight3D.new()
	sl.position = Vector3(0, 4.6, -4.0)
	sl.omni_range = 9.0
	sl.light_energy = 0.5
	sl.light_color = Color(1.0, 0.78, 0.5)
	add_child(sl)

	# Second stage: a warm clamp flood on the right fence's string-light pole, aimed down at the grass half
	# (front-right), so both halves of the yard have a lit pool, not just the patio.
	var gp := Vector3(7.7, 4.6, 0.6)
	var gaim := Vector3(2.2, 0.0, 2.3)
	var gf := SpotLight3D.new()
	gf.transform = Transform3D(Basis.looking_at(gaim - gp), gp)
	gf.spot_angle = 38.0
	gf.spot_angle_attenuation = 1.2
	gf.spot_range = 14.0
	gf.spot_attenuation = 0.5
	gf.light_energy = 3.4
	gf.light_specular = 0.6
	gf.light_color = Color(1.0, 0.86, 0.64)
	add_child(gf)
	var ghead: MeshInstance3D = m._box(Vector3(0.4, 0.3, 0.26), Vector3.ZERO, Color(0.16, 0.16, 0.17))
	ghead.transform = gf.transform
	var glens: MeshInstance3D = m._box(Vector3(0.32, 0.22, 0.04), Vector3.ZERO, Color(1.0, 0.9, 0.7), true)
	glens.transform = gf.transform * Transform3D(Basis(), Vector3(0, 0, -0.14))


func _build_grime() -> void:
	var hz := HOUSE_Z
	m._grime_wall(Vector3(-9.0, 0, hz + 0.06), Vector3(9.0, 0, hz + 0.06), Vector3.BACK, 0.9, 0.5)
	m._grime_wall(Vector3(0.0, 0, -5.63), Vector3(6.0, 0, -5.63), Vector3.BACK, 0.55, 0.45)  # porch skirt
	var runs: Array = [[-1.0, HOUSE_Z, -1.0], [-1.0, 1.8, FENCE_Z], [1.0, HOUSE_Z, 1.2], [1.0, 4.1, FENCE_Z]]
	for r: Array in runs:
		var fx: float = r[0] * FENCE_X
		for side: float in [-1.0, 1.0]:
			var off := Vector3(side * 0.03, 0, 0)
			m._grime_wall(Vector3(fx, 0, r[1]) + off, Vector3(fx, 0, r[2]) + off, Vector3(side, 0, 0), 0.6, 0.35, 0.5, 0.35)
	# Shed: front (faces the yard) and both ends.
	m._grime_wall(Vector3(-6.79, 0, -1.0), Vector3(-6.79, 0, 1.8), Vector3.RIGHT, 0.7, 0.45)
	m._grime_wall(Vector3(-9.4, 0, 1.81), Vector3(-6.8, 0, 1.81), Vector3.BACK, 0.7, 0.4)
	m._grime_wall(Vector3(-9.4, 0, -1.01), Vector3(-6.8, 0, -1.01), Vector3.FORWARD, 0.7, 0.4)
	for fx: float in [-FENCE_X, 2.6]:  # low pickets on the camera side
		m._grime_wall(Vector3(fx, 0, FENCE_Z - 0.03), Vector3(fx + 4.9, 0, FENCE_Z - 0.03), Vector3.FORWARD, 0.22, 0.25, 0.4, 0.3)
	m._flush_grime()
	# A couple of small, weathered spray tags on the shed's yard-facing wall.
	m._wall_decal(m._make_tag_texture("C2C", Color(0.78, 0.16, 0.1), Color(0.06, 0.05, 0.05), Color(0.98, 0.78, 0.5)),
		Vector3(-6.75, 1.05, -0.3), Vector2(1.5, 0.75), Vector3.RIGHT)
	m._wall_decal(m._make_tag_texture("CREW", Color(0.86, 0.84, 0.78), Color(0.1, 0.16, 0.42), Color(1.0, 1.0, 1.0)),
		Vector3(-6.77, 0.62, 1.3), Vector2(0.8, 0.4), Vector3.RIGHT)


func _build_lawn() -> void:
	var sh := Shader.new()
	sh.code = LAWN_SHADER
	var lm := ShaderMaterial.new()
	lm.shader = sh
	lm.set_shader_parameter("map", m._make_lawn_map())
	lm.set_shader_parameter("detail", m._make_grass_detail())
	lm.set_shader_parameter("detail_scale", 10.0)
	m._ground_quad(Vector3(LAWN_RECT.get_center().x, 0.0, LAWN_RECT.get_center().y), LAWN_RECT.size, lm)
	# Concrete patio slab by the house (+ a thin raised edge) and the driveway strip.
	var pm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 5))
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(PATIO_RECT.get_center().x, 0.015, PATIO_RECT.get_center().y), PATIO_RECT.size, pm)
	var edge := Color(0.42, 0.41, 0.38)
	m._bx("block", Vector3(PATIO_RECT.size.x, 0.03, 0.08), Vector3(PATIO_RECT.get_center().x, 0.012, PATIO_RECT.end.y), edge)
	m._bx("block", Vector3(0.08, 0.03, PATIO_RECT.size.y), Vector3(PATIO_RECT.end.x, 0.012, PATIO_RECT.get_center().y), edge)
	var dm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 4, true))
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(DRIVE_RECT.get_center().x, 0.015, DRIVE_RECT.get_center().y), DRIVE_RECT.size, dm, 0.0, Vector2(3.0, 1.0))
	# Spray-painted "C2C" on the patio: the backyard federation's "logo".
	var spray: StandardMaterial3D = m._tex_mat(m._make_spray_texture(), false, true)
	spray.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(-2.4, 0.025, -2.9), Vector2(3.2, 1.6), spray, 0.08)


func _build_house() -> void:
	# Back of a two-story house at -z: the backdrop of the broadcast shot.
	var wall_z := HOUSE_Z
	var depth := 8.0
	var w := 9.0
	var top := 6.2
	var ridge := 8.4
	var siding := Color(0.62, 0.6, 0.52)
	var trim := Color(0.82, 0.8, 0.74)
	m._bx("siding", Vector3(2 * w, top, 0.3), Vector3(0, top * 0.5, wall_z - 0.15), siding, 0.0, 0.6)
	m._bx("siding", Vector3(0.3, top, depth), Vector3(-w, top * 0.5, wall_z - depth * 0.5), siding, 0.0, 0.6)
	m._bx("siding", Vector3(0.3, top, depth), Vector3(w, top * 0.5, wall_z - depth * 0.5), siding, 0.0, 0.6)
	m._bx("brick", Vector3(2 * w + 0.3, 0.6, 0.36), Vector3(0, 0.3, wall_z - 0.12), Color(1, 1, 1))  # brick foundation
	var st: SurfaceTool = m._st("siding")
	for s: float in [-1.0, 1.0]:
		var x := s * (w + 0.15)
		var p0 := Vector3(x, top, wall_z)
		var p1 := Vector3(x, ridge, wall_z - depth * 0.5)
		var p2 := Vector3(x, top, wall_z - depth)
		var n := Vector3(s, 0, 0)
		if s > 0.0:
			m._tri(st, p0, p1, p2, n, Vector3.FORWARD, Vector3.UP, siding, 0.6)
		else:
			m._tri(st, p2, p1, p0, n, Vector3.BACK, Vector3.UP, siding, 0.6)
	var run := depth * 0.5 + 0.6
	var rise := (ridge - top) * run / (depth * 0.5)
	var slope := atan2(rise, run)
	var slab_len := sqrt(run * run + rise * rise)
	var roof_col := Color(0.3, 0.27, 0.27)
	for s: float in [1.0, -1.0]:
		var zc := wall_z - depth * 0.5 + s * run * 0.5
		var yc := ridge + 0.1 - rise * 0.5
		var b := Basis(Vector3.RIGHT, slope * s)
		m._sbox("shingle", Vector3(2 * w + 1.0, 0.16, slab_len), Transform3D(b, Vector3(0, yc, zc)), roof_col, 0.7)
	m._bx("flat", Vector3(2 * w + 1.0, 0.14, 0.14), Vector3(0, top - 0.32, wall_z + 0.62), trim)  # gutter
	m._bx("flat", Vector3(0.1, top - 0.4, 0.1), Vector3(-8.7, (top - 0.4) * 0.5, wall_z + 0.1), trim.darkened(0.2))  # downspout
	m._bx("brick", Vector3(1.0, 2.6, 1.0), Vector3(5.5, ridge + 0.4, wall_z - 2.8), Color(0.9, 0.85, 0.85))  # chimney

	# Upstairs windows (lit warm, TV-blue, dark), kitchen window over the patio.
	var wf := wall_z + 0.02
	var ups: Array[float] = [-6.5, -2.4, 2.0, 6.2]
	var up_cols: Array[Color] = [Color(0.95, 0.7, 0.36), Color(0.05, 0.05, 0.07), Color(0.35, 0.48, 0.85), Color(0.9, 0.62, 0.3)]
	for i in ups.size():
		m._bx("flat", Vector3(1.5, 1.4, 0.06), Vector3(ups[i], 4.55, wf), trim)
		m._bx("glow", Vector3(1.3, 1.2, 0.06), Vector3(ups[i], 4.55, wf + 0.03), up_cols[i])
		m._bx("flat", Vector3(0.06, 1.2, 0.07), Vector3(ups[i], 4.55, wf + 0.04), trim)
		m._bx("flat", Vector3(1.3, 0.06, 0.07), Vector3(ups[i], 4.55, wf + 0.04), trim)
		m._bx("flat", Vector3(0.3, 1.4, 0.06), Vector3(ups[i] - 0.92, 4.55, wf), Color(0.14, 0.2, 0.26))  # shutters
		m._bx("flat", Vector3(0.3, 1.4, 0.06), Vector3(ups[i] + 0.92, 4.55, wf), Color(0.14, 0.2, 0.26))
	m._bx("flat", Vector3(1.6, 1.2, 0.06), Vector3(-6.3, 1.9, wf), trim)
	m._bx("glow", Vector3(1.4, 1.0, 0.06), Vector3(-6.3, 1.9, wf + 0.03), Color(0.92, 0.75, 0.46))
	m._bx("flat", Vector3(1.4, 0.3, 0.07), Vector3(-6.3, 2.25, wf + 0.04), Color(0.55, 0.2, 0.16))  # valance
	# Sliding glass door onto the patio, with a lamp over it.
	m._bx("flat", Vector3(2.6, 2.3, 0.06), Vector3(-3.4, 1.2, wf), Color(0.5, 0.5, 0.52))
	m._bx("glow", Vector3(2.4, 2.1, 0.06), Vector3(-3.4, 1.2, wf + 0.03), Color(0.46, 0.36, 0.24))
	m._bx("flat", Vector3(0.08, 2.1, 0.08), Vector3(-3.4, 1.2, wf + 0.05), Color(0.5, 0.5, 0.52))
	m._bx("flat", Vector3(0.7, 2.0, 0.07), Vector3(-4.25, 1.2, wf + 0.05), Color(0.36, 0.28, 0.2))  # half-drawn curtain
	m._bx("glow", Vector3(0.2, 0.3, 0.16), Vector3(-1.8, 2.6, wf + 0.08), Color(1.0, 0.82, 0.5))
	# Back door up on the porch, its light.
	m._bx("flat", Vector3(1.1, 2.15, 0.06), Vector3(3.2, 1.0 + 1.07, wf), trim)
	m._bx("flat", Vector3(0.95, 2.05, 0.07), Vector3(3.2, 1.0 + 1.03, wf + 0.01), Color(0.32, 0.12, 0.1))
	m._bx("glow", Vector3(0.5, 0.6, 0.08), Vector3(3.2, 2.45, wf + 0.04), Color(0.95, 0.75, 0.45))  # door window
	m._bx("glow", Vector3(0.2, 0.3, 0.16), Vector3(4.2, 2.9, wf + 0.08), Color(1.0, 0.82, 0.5))
	# AC unit and a coiled hose on the patio by the wall.
	m._bx("metal", Vector3(0.8, 0.75, 0.8), Vector3(-0.95, 0.4, wall_z + 0.55), Color(0.62, 0.62, 0.6))
	m._bx("flat", Vector3(0.7, 0.03, 0.7), Vector3(-0.95, 0.79, wall_z + 0.55), Color(0.12, 0.12, 0.12))
	m._cy("flat", 0.3, 0.3, 0.12, Vector3(-7.0, 0.07, wall_z + 0.5), Color(0.15, 0.4, 0.18), 10)

	# Raised wooden porch (x 0..6, top y 1.0) with steps down to the yard, railing, roof.
	var deck_y := 1.0
	var wood := Color(0.5, 0.4, 0.3)
	var px0 := 0.0
	var px1 := 6.0
	var front := -5.7
	var dz := front - wall_z
	m._bx("wood", Vector3(px1 - px0, 0.1, dz), Vector3((px0 + px1) * 0.5, deck_y - 0.05, (wall_z + front) * 0.5), wood)
	m._bx("flat", Vector3(px1 - px0, deck_y - 0.1, 0.04), Vector3((px0 + px1) * 0.5, (deck_y - 0.1) * 0.5, front + 0.05), Color(0.12, 0.1, 0.08))  # dark lattice skirt
	for k in 15:
		m._bx("wood", Vector3(0.03, 0.03, 1.2), Vector3(px0 + 0.2 + k * 0.4, 0.45, front + 0.02), wood, PI * 0.25)
	for sx: float in [px0, px1]:
		m._bx("flat", Vector3(0.04, deck_y - 0.1, dz), Vector3(sx, (deck_y - 0.1) * 0.5, (wall_z + front) * 0.5), Color(0.12, 0.1, 0.08))
	# Steps (three 0.25 m risers) centred on x 1.6
	var sx0 := 1.6
	for k in 3:
		var h := deck_y - 0.25 * (k + 1)
		var z0 := front + 0.3 * k
		m._bx("wood", Vector3(1.4, h, 0.32), Vector3(sx0, h * 0.5, z0 + 0.15), wood.lightened(0.05 * k))
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
		m._bx("wood", Vector3(l, 0.07, 0.12), (a + b2) * 0.5 + Vector3(0, rail_top, 0), rail, yaw)
		m._bx("wood", Vector3(l, 0.05, 0.05), (a + b2) * 0.5 + Vector3(0, deck_y + 0.12, 0), rail, yaw)
		var nb := int(l / 0.16)
		for k in nb:
			m._bx("wood", Vector3(0.04, 0.8, 0.04), a + d * ((k + 0.5) / nb) + Vector3(0, deck_y + 0.52, 0), rail, yaw)
	for k in 2:
		var hx := sx0 + (0.72 if k == 0 else -0.72)
		m._beam("wood", Vector3(hx, rail_top, front), Vector3(hx, 0.95, front + 0.95), 0.06, rail)  # step handrails
		m._bx("wood", Vector3(0.1, 1.0, 0.1), Vector3(hx, 0.5, front + 0.92), rail)
	var roof_y := 3.4
	for ppx: float in [px0 + 0.1, 3.0, px1 - 0.1]:
		m._bx("wood", Vector3(0.16, roof_y - deck_y, 0.16), Vector3(ppx, deck_y + (roof_y - deck_y) * 0.5, front + 0.1), rail)
	m._bx("shingle", Vector3(px1 - px0 + 0.6, 0.18, dz + 0.6), Vector3((px0 + px1) * 0.5, roof_y + 0.09, (wall_z + front) * 0.5 + 0.3), Color(0.3, 0.27, 0.27), 0.0, 0.7)
	m._bx("flat", Vector3(px1 - px0 + 0.6, 0.22, 0.06), Vector3((px0 + px1) * 0.5, roof_y + 0.05, front + 0.6), trim)
	# Hand-painted bedsheet banner hanging off the porch roof
	var sheet_z := front + 0.66
	m._bx("flat", Vector3(4.6, 0.9, 0.03), Vector3(3.6, roof_y - 0.42, sheet_z), Color(0.86, 0.84, 0.78))
	m._bx("flat", Vector3(4.6, 0.04, 0.035), Vector3(3.6, roof_y - 0.1, sheet_z), Color(0.5, 0.48, 0.44))
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
	m._bx("flat", Vector3(2.2, 0.45, 0.95), cp + Vector3(0, 0.22, 0), couch)
	m._bx("flat", Vector3(2.2, 0.6, 0.28), cp + Vector3(0, 0.6, -0.36), couch.darkened(0.1))
	for s: float in [-1.0, 1.0]:
		m._bx("flat", Vector3(0.26, 0.62, 0.95), cp + Vector3(s * 1.1, 0.31, 0), couch.darkened(0.15))
	m._bx("flat", Vector3(0.7, 0.12, 0.6), cp + Vector3(-0.4, 0.5, 0.05), Color(0.5, 0.42, 0.26))
	var gp := Vector3(0.8, deck_y, wall_z + 0.9)
	m._cy("flat", 0.3, 0.4, 0.35, gp + Vector3(0, 0.95, 0), Color(0.07, 0.07, 0.08), 10)
	m._cy("flat", 0.4, 0.24, 0.25, gp + Vector3(0, 1.25, 0), Color(0.08, 0.08, 0.09), 10)
	m._cy("glow", 0.31, 0.31, 0.02, gp + Vector3(0, 1.12, 0), Color(1.0, 0.4, 0.1), 10)
	for k in 3:
		var a3 := TAU * k / 3.0 + 0.3
		m._beam("flat", gp + Vector3(cos(a3) * 0.35, 0, sin(a3) * 0.35), gp + Vector3(0, 0.85, 0), 0.04, Color(0.07, 0.07, 0.08))

	# Neighbours' houses beyond the side fences + a dark tree line.
	for nb: Vector3 in [Vector3(-17.5, 0, -6.0), Vector3(17.5, 0, -9.0)]:
		m._bx("siding", Vector3(9.0, 5.6, 7.0), nb + Vector3(0, 2.8, 0), Color(0.5, 0.46, 0.38) if nb.x < 0.0 else Color(0.4, 0.45, 0.5), PI * 0.5, 0.6)
		for s: float in [-1.0, 1.0]:
			m._sbox("shingle", Vector3(4.2, 0.2, 9.6), Transform3D(Basis(Vector3.BACK, -0.5 * s), nb + Vector3(1.85 * s, 6.6, 0)), Color(0.22, 0.2, 0.2), 0.7)
		var face := -signf(nb.x) * 3.52
		m._bx("glow", Vector3(0.06, 1.0, 1.2), nb + Vector3(face, 3.8, 1.8), Color(0.85, 0.62, 0.34))
		m._bx("glow", Vector3(0.06, 1.0, 1.2), nb + Vector3(face, 1.6, -2.0), Color(0.3, 0.4, 0.65))
	var trees: Array[Vector3] = [Vector3(-11.0, 0, -12.5), Vector3(-12.0, 0, 2.5), Vector3(11.0, 0, -14.0), Vector3(12.5, 0, -2.5),
		Vector3(12.0, 0, 9.0), Vector3(-11.5, 0, 9.5), Vector3(-3.0, 0, -19.0), Vector3(6.0, 0, -19.5)]
	for t in trees:
		var th := randf_range(6.0, 9.0)
		m._cy("flat", 0.25, 0.2, 1.6, t + Vector3(0, 0.8, 0), Color(0.12, 0.09, 0.06), 6)
		m._cy("flat", 2.4, 0.0, th * 0.6, t + Vector3(0, 1.4 + th * 0.3, 0), Color(0.04, 0.08, 0.05), 8)
		m._cy("flat", 1.8, 0.0, th * 0.5, t + Vector3(0, 1.4 + th * 0.65, 0), Color(0.05, 0.1, 0.06), 8)


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
		m._sbox("wood", Vector3(bw, bh, 0.035), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean), p + Vector3(0, bh * 0.5, 0)), Color(0.66 + tint, 0.58 + tint, 0.48 + tint))
	var posts := maxi(1, int(run_len / 2.4))
	for k in posts + 1:
		var pp := a + dir * (k * run_len / posts)
		m._bx("wood", Vector3(0.11, fh + 0.12, 0.11), pp + Vector3(0, (fh + 0.12) * 0.5, 0), Color(0.42, 0.36, 0.3), yaw)
	for ry: float in ([fh * 0.75, fh * 0.25] if picket else [fh - 0.3, 0.3]):
		m._bx("wood", Vector3(run_len, 0.08, 0.05), (a + b) * 0.5 + Vector3(0, ry, 0) - Vector3(dir.z, 0, -dir.x) * 0.04, Color(0.45, 0.38, 0.3), yaw)


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
	# Kept at 0.45 m so it never hides the wrestlers' legs from the broadcast camera.
	_fence_run(Vector3(-FENCE_X, 0, fz), Vector3(-2.6, 0, fz), 0.45, true)
	_fence_run(Vector3(2.6, 0, fz), Vector3(FENCE_X, 0, fz), 0.45, true)
	for k in 2:
		var cx := -1.3 + k * 2.6
		m._bx("wood", Vector3(2.5, 0.05, 0.85), Vector3(cx, 0.04, fz + 0.55 + k * 0.1), Color(0.6, 0.53, 0.44), randf_range(-0.12, 0.12))
		m._bx("wood", Vector3(2.5, 0.08, 0.06), Vector3(cx, 0.09, fz + 0.4 + k * 0.1), Color(0.45, 0.38, 0.3))


func _lawn_chair(pos: Vector3, face: Vector3, col: Color) -> void:
	var b := Basis.looking_at(face)
	var frame := Color(0.6, 0.61, 0.63)
	var xf := Transform3D(b, pos)
	m._sbox("flat", Vector3(0.52, 0.04, 0.46), xf * Transform3D(Basis(), Vector3(0, 0.42, 0)), col)
	m._sbox("flat", Vector3(0.52, 0.55, 0.04), xf * Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, 0.72, 0.25)), col)
	for sx: float in [-0.26, 0.26]:
		m._beam("flat", xf * Vector3(sx, 0, -0.22), xf * Vector3(sx, 0.42, 0.18), 0.03, frame)
		m._beam("flat", xf * Vector3(sx, 0, 0.22), xf * Vector3(sx, 0.42, -0.18), 0.03, frame)
		m._beam("flat", xf * Vector3(sx, 0.62, -0.2), xf * Vector3(sx, 0.62, 0.2), 0.03, frame)


func _build_props() -> void:
	# Decoration outside the fighting area (the perches are in _build_perches).
	# Lawn chairs at the back of the patio
	_lawn_chair(Vector3(-6.4, 0.015, -6.2), Vector3(0.3, 0, 1), Color(0.2, 0.45, 0.3))
	_lawn_chair(Vector3(-5.6, 0.015, -6.5), Vector3(0.1, 0, 1), Color(0.65, 0.25, 0.2))
	_lawn_chair(Vector3(-1.6, 0.015, -6.6), Vector3(-0.2, 0, 1), Color(0.22, 0.32, 0.62))
	# Coolers
	m._bx("flat", Vector3(0.7, 0.42, 0.42), Vector3(-4.6, 0.225, -6.9), Color(0.65, 0.18, 0.14), 0.3)
	m._bx("flat", Vector3(0.72, 0.08, 0.44), Vector3(-4.6, 0.46, -6.9), Color(0.85, 0.85, 0.82), 0.3)
	m._bx("flat", Vector3(0.6, 0.38, 0.38), Vector3(8.6, 0.2, 4.6), Color(0.15, 0.3, 0.6), -0.4)
	# Garbage cans + recycling bin in the back corner by the porch
	for tc: Vector3 in [Vector3(6.75, 0, -7.9), Vector3(6.85, 0, -7.2)]:
		m._cy("metal", 0.3, 0.33, 0.85, tc + Vector3(0, 0.425, 0), Color(0.5, 0.51, 0.5), 10)
		m._cy("metal", 0.36, 0.3, 0.08, tc + Vector3(0, 0.89, 0), Color(0.55, 0.56, 0.55), 10)
	m._bx("flat", Vector3(0.6, 1.0, 0.65), Vector3(6.8, 0.5, -6.4), Color(0.12, 0.25, 0.55))
	# Garden gnomes (outside the fighting area)
	var gnomes: Array[Vector3] = [Vector3(-0.9, 0, -7.6), Vector3(6.6, 0, -5.4), Vector3(-3.6, 0, 6.1), Vector3(3.4, 0, 6.0), Vector3(-7.0, 0, -5.6)]
	for i in gnomes.size():
		var g: Vector3 = gnomes[i]
		m._cy("flat", 0.13, 0.09, 0.22, g + Vector3(0, 0.11, 0), [Color(0.17, 0.3, 0.6), Color(0.18, 0.48, 0.25)][i % 2], 8)
		m._bx("flat", Vector3(0.13, 0.12, 0.13), g + Vector3(0, 0.28, 0), Color(0.8, 0.62, 0.5))
		m._bx("flat", Vector3(0.14, 0.1, 0.06), g + Vector3(0, 0.22, 0.07), Color(0.85, 0.85, 0.85))
		m._cy("flat", 0.09, 0.0, 0.22, g + Vector3(0, 0.45, 0), Color(0.7, 0.12, 0.1), 8)
	# Kiddie pool in the neighbour's strip behind the left fence
	var kp := Vector3(-10.2, 0, 4.4)  # out of the broadcast shot (was a hard blue shape under the joystick)
	m._cy("flat", 1.0, 1.05, 0.3, kp + Vector3(0, 0.15, 0), Color(0.3, 0.5, 0.75), 14)
	m._cy("glow", 0.9, 0.9, 0.02, kp + Vector3(0, 0.25, 0), Color(0.12, 0.25, 0.32), 14)


func _build_perches() -> void:
	# Six things to climb, spread around the edge of the yard; the middle stays open.
	var wood := Color(0.55, 0.45, 0.33)
	var metal := Color(0.55, 0.56, 0.58)

	# 1) Picnic table on the patio (top 0.75)
	var pt := Vector3(-4.4, 0.015, -3.5)
	m._bx("wood", Vector3(1.9, 0.06, 0.8), pt + Vector3(0, 0.72, 0), wood)
	for s: float in [-1.0, 1.0]:
		m._bx("wood", Vector3(1.9, 0.05, 0.28), pt + Vector3(0, 0.43, s * 0.62), wood.darkened(0.08))
		for lx: float in [-0.7, 0.7]:
			m._beam("wood", pt + Vector3(lx, 0, s * 0.78), pt + Vector3(lx, 0.7, s * 0.12), 0.08, wood.darkened(0.15))
	for lx: float in [-0.7, 0.7]:
		m._bx("wood", Vector3(0.08, 0.06, 1.6), pt + Vector3(lx, 0.38, 0), wood.darkened(0.15))
	m._cy("flat", 0.04, 0.04, 0.12, pt + Vector3(0.5, 0.81, 0.1), Color(0.65, 0.12, 0.1), 8)  # red cup
	add_perch("picnic table", "table", Vector3(-4.4, 0.75, -3.5), Vector3(-4.4, 0.0, -2.3),
		footprint(Vector2(-4.4, -3.5), Vector2(0.97, 0.82), "THE PICNIC TABLE", "Picnic Table Crash", 200, "wood_hit"))

	# 2) Stacked pallets on cinder blocks (top 1.2) by the left fence, camera side
	var pp := Vector3(-6.0, 0, 3.6)
	var block := Color(0.75, 0.74, 0.7)
	for cx: float in [-0.4, 0.4]:
		for cz: float in [-0.3, 0.3]:
			for k in 2:
				m._bx("block", Vector3(0.4, 0.2, 0.2), pp + Vector3(cx, 0.1 + k * 0.2, cz), block.darkened(randf() * 0.15), PI * 0.5 * k)
	for k in 5:
		var y0 := 0.4 + k * 0.16
		var jit := Vector3(randf_range(-0.05, 0.05), 0, randf_range(-0.05, 0.05))
		var pyaw := randf_range(-0.06, 0.06)
		var pal := wood.darkened(randf_range(0.0, 0.2))
		for bz: float in [-0.45, 0.0, 0.45]:
			m._bx("wood", Vector3(1.2, 0.02, 0.1), pp + jit + Vector3(0, y0 + 0.01, bz), pal, pyaw)
			m._bx("wood", Vector3(1.2, 0.11, 0.08), pp + jit + Vector3(0, y0 + 0.075, bz), pal.darkened(0.1), pyaw)
		for sx in 7:
			m._bx("wood", Vector3(0.12, 0.025, 1.0), pp + jit + Vector3(-0.54 + sx * 0.18, y0 + 0.1475, 0), pal.lightened(0.05), pyaw)
	for k in 2:
		m._bx("block", Vector3(0.4, 0.2, 0.2), Vector3(-5.2, 0.1 + k * 0.2, 3.6), block, PI * 0.5)  # step block
	add_perch("pallet stack", "pallets", Vector3(-6.0, 1.2, 3.6), Vector3(-4.8, 0.0, 3.5),
		footprint(Vector2(-5.88, 3.6), Vector2(0.78, 0.56), "THE PALLETS", "Pallet Crash", 200, "wood_hit"))  # + the step block at x -5.2

	# 3) Porch steps / railing (deck top 1.0), built with the house
	# steps x 0.9..2.3 (handrail posts to +-0.77), z -5.7..-4.78; the deck itself is behind the yard's edge
	add_perch("porch steps", "porch", Vector3(1.6, 1.0, -5.95), Vector3(1.6, 0.0, -4.3),
		footprint(Vector2(1.6, -5.24), Vector2(0.77, 0.47), "THE PORCH STEPS", "Porch Step Crash", 200, "wood_hit"))
	obstacles.append(footprint(Vector2(3.0, -7.15), Vector2(3.0, 1.45), "THE PORCH", "Porch Crash", 200, "wood_hit"))

	# 4) Car hood: in _build_car
	# 5) Trampoline (mat 0.9): extra air
	var tp := Vector3(5.0, 0, -2.6)
	m._cy("flat", 1.45, 1.45, 0.07, tp + Vector3(0, 0.865, 0), Color(0.12, 0.3, 0.7), 16)
	m._cy("flat", 1.22, 1.22, 0.02, tp + Vector3(0, 0.9, 0), Color(0.03, 0.03, 0.035), 16)
	for k in 8:
		var a2 := TAU * k / 8.0 + 0.2
		var lp := tp + Vector3(cos(a2) * 1.38, 0, sin(a2) * 1.38)
		m._beam("metal", lp + Vector3(0, 0.05, 0), lp + Vector3(0, 0.83, 0), 0.05, metal)
		if k % 2 == 0:
			var a3 := a2 + TAU / 8.0
			m._beam("metal", lp + Vector3(0, 0.03, 0), tp + Vector3(cos(a3) * 1.38, 0.03, sin(a3) * 1.38), 0.05, metal)
	add_perch("trampoline", "trampoline", Vector3(5.0, 0.9, -2.6), Vector3(3.4, 0.0, -2.0),
		footprint(Vector2(5.0, -2.6), Vector2(1.4, 1.4), "THE TRAMPOLINE", "Trampoline Crash", 200, "metal_hit", 1.4))

	# 6) Shed in the left fence line, ladder up to its flat roof (2.4): the biggest dive
	var shed := Color(0.42, 0.5, 0.42)
	var sx0 := -8.1
	var sw := 2.6
	var sz := 0.4
	var sd := 2.8
	m._bx("wood", Vector3(sw, 2.25, sd), Vector3(sx0, 1.125, sz), shed)
	m._bx("shingle", Vector3(sw + 0.4, 0.15, sd + 0.4), Vector3(sx0, 2.325, sz), Color(0.26, 0.25, 0.25), 0.0, 0.7)
	m._bx("flat", Vector3(0.04, 0.1, sd + 0.4), Vector3(sx0 + sw * 0.5 + 0.2, 2.3, sz), Color(0.75, 0.75, 0.7))  # drip edge
	var fxw := sx0 + sw * 0.5 + 0.01
	m._bx("flat", Vector3(0.05, 1.9, 1.3), Vector3(fxw, 0.95, sz - 0.65), shed.darkened(0.3))  # doors
	m._bx("flat", Vector3(0.06, 1.9, 0.04), Vector3(fxw + 0.01, 0.95, sz - 0.65), Color(0.1, 0.1, 0.1))
	m._bx("flat", Vector3(0.06, 0.4, 1.4), Vector3(fxw + 0.01, 0.95, sz - 0.65), Color(0.55, 0.55, 0.5))  # X brace hint
	m._bx("glow", Vector3(0.05, 0.45, 0.5), Vector3(fxw, 1.55, sz + 1.05), Color(0.25, 0.2, 0.12))  # dim window
	var lb := Vector3(-5.95, 0, 0.9)
	var lt := Vector3(fxw + 0.1, 2.75, 0.9)
	for s: float in [-0.22, 0.22]:
		m._beam("metal", lb + Vector3(0, 0, s), lt + Vector3(0, 0, s), 0.06, Color(0.75, 0.72, 0.5))
	for k in 8:
		m._bx("metal", Vector3(0.05, 0.04, 0.44), lb.lerp(lt, (k + 0.6) / 8.6), Color(0.75, 0.72, 0.5))
	add_perch("shed roof", "roof", Vector3(-7.0, 2.4, 0.9), Vector3(-5.6, 0.0, 0.9),
		footprint(Vector2(sx0, sz), Vector2(sw * 0.5 + 0.02, sd * 0.5), "THE SHED", "Shed Crash", 250, "wood_hit"))
	# the ladder leaning on the shed: foot at x -5.95, rails z 0.68..1.12
	obstacles.append(footprint(Vector2(-6.36, 0.9), Vector2(0.42, 0.25), "THE LADDER", "Ladder Crash", 250, "metal_hit"))


func _build_car() -> void:
	# Beat-up sedan on the driveway strip, nose poking through the open gate, headlights on the lawn.
	var pos := Vector3(6.9, 0, 2.65)
	var face := Vector3(-1, 0, 0)
	var xf := Transform3D(Basis.looking_at(face), pos)
	var body := Color(0.45, 0.1, 0.09)
	var glass := Color(0.05, 0.06, 0.08)
	m._sbox("flat", Vector3(1.8, 0.65, 4.4), xf * Transform3D(Basis(), Vector3(0, 0.62, 0)), body)
	m._sbox("flat", Vector3(1.6, 0.55, 2.2), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), body.darkened(0.1))
	m._sbox("flat", Vector3(1.64, 0.4, 2.0), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), glass)
	m._sbox("flat", Vector3(1.4, 0.42, 2.24), xf * Transform3D(Basis(), Vector3(0, 1.2, 0.3)), glass)
	m._sbox("flat", Vector3(1.0, 0.02, 0.9), xf * Transform3D(Basis(), Vector3(0.2, 0.955, -1.5)), Color(0.5, 0.5, 0.48))  # primer hood patch
	m._sbox("metal", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.38, -2.22)), Color(0.6, 0.6, 0.62))
	m._sbox("metal", Vector3(1.9, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.38, 2.22)), Color(0.6, 0.6, 0.62))
	for sx: float in [-0.65, 0.65]:
		m._sbox("glow", Vector3(0.36, 0.2, 0.06), xf * Transform3D(Basis(), Vector3(sx, 0.72, -2.21)), Color(1.0, 0.97, 0.85))
		m._sbox("glow", Vector3(0.3, 0.16, 0.06), xf * Transform3D(Basis(), Vector3(sx, 0.75, 2.21)), Color(0.9, 0.08, 0.06))
		for sz: float in [-1.35, 1.35]:
			m._scyl("flat", 0.33, 0.33, 0.24, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.38, 0.33, sz)), Color(0.03, 0.03, 0.03), 10)
			m._scyl("metal", 0.17, 0.17, 0.26, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.38, 0.33, sz)), Color(0.5, 0.5, 0.52), 8)
	# Headlight beam raking low across the grass half of the yard (one spot for both lamps).
	var hp := xf * Vector3(0, 0.75, -2.3)
	var aim := Vector3(-4.5, 0.0, 1.4)
	var head := SpotLight3D.new()
	head.transform = Transform3D(Basis.looking_at(aim - hp), hp)
	head.spot_angle = 25.0
	head.spot_angle_attenuation = 0.9
	head.spot_range = 16.0
	head.spot_attenuation = 0.45
	head.light_energy = 3.0
	head.light_specular = 0.6
	head.light_color = Color(1.0, 0.95, 0.82)
	add_child(head)
	# A faint additive cone so the beam itself reads in the night air.
	var cone := CylinderMesh.new()
	var beam_len := 9.0
	cone.top_radius = 0.18
	cone.bottom_radius = tan(deg_to_rad(18.0)) * beam_len
	cone.height = beam_len
	cone.radial_segments = 16
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var csh := Shader.new()
	csh.code = BEAM_SHADER
	var cmat := ShaderMaterial.new()
	cmat.shader = csh
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = cmat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bdir := (aim - hp).normalized()
	# The cylinder runs along +Y with its narrow end on top: point -Y down the beam.
	var bb := Basis(Quaternion(Vector3.DOWN, bdir))
	beam.transform = Transform3D(bb, hp + bdir * beam_len * 0.5)
	add_child(beam)
	# body 4.4 x 1.8 along x (bumpers to x 4.6), wheels out to z +-1.02
	add_perch("car hood", "car", Vector3(5.4, 0.95, 2.65), Vector3(4.15, 0.0, 2.65),
		footprint(Vector2(pos.x, pos.z), Vector2(2.3, 1.0), "THE CAR DOOR", "Car Door Crash", 250, "metal_hit"))


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
	var _bulb_xforms: Array[Transform3D] = []
	var _bulb_cols: Array[Color] = []
	# Two zig-zag strands from the house eaves over the yard to poles just outside the side fences.
	var poles: Array[Vector3] = [Vector3(-7.85, 0, -5.0), Vector3(7.85, 0, -5.0), Vector3(-7.85, 0, -1.6), Vector3(7.85, 0, -1.6),
		Vector3(-7.85, 0, 2.6), Vector3(7.85, 0, 0.6)]
	for p in poles:
		m._bx("wood", Vector3(0.12, 5.0, 0.12), p + Vector3(0, 2.5, 0), Color(0.42, 0.35, 0.28), 0.0, 2.0)
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
				m._beam("flat", prev, p, 0.025, wire)
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


# ---- the friends watching (main.build_crowd turns these into the billboard crowd)

func _fan(p: Vector3, person: String, lit := 0.55, bob := 1.0) -> void:
	crowd_spots.append({"pos": p, "person": person, "lit": lit, "bob": bob})


func _build_crowd_spots() -> void:
	# ~30 friends hanging around the yard. Nobody stands in the fighting area (x -7..7, z -5..5) or
	# on a perch top. Seated friends: feet 0.53 below the seat.
	crowd_spots = []
	# Back of the patio (two in the lawn chairs); the sliding door (x -4.7..-2.1) mostly stays clear.
	_fan(Vector3(-6.4, 0.015, -6.15), "sit", 0.6)
	_fan(Vector3(-1.6, 0.015, -6.55), "sit_cup", 0.6)
	for spot: Vector3 in [Vector3(-6.95, 0, -5.75), Vector3(-5.1, 0, -6.0), Vector3(-5.8, 0, -7.25), Vector3(-2.15, 0, -5.95),
			Vector3(-1.0, 0, -5.85), Vector3(-0.35, 0, -6.7), Vector3(-4.4, 0, -7.7)]:
		_fan(spot + Vector3(randf_range(-0.1, 0.1), 0.015, randf_range(-0.1, 0.1)), "stand", 0.6)
	# Porch deck (top 1.0) behind the railing; one on the couch (seat ~1.45)
	for spot: Vector3 in [Vector3(3.3, 1.0, -6.05), Vector3(5.0, 1.0, -6.1), Vector3(4.1, 1.0, -6.75), Vector3(0.5, 1.0, -6.3)]:
		_fan(spot, "stand", 0.62)
	_fan(Vector3(4.3, 0.93, -7.6), "sit", 0.5)
	# Sitting on the porch steps (second step, 0.5), at the ends so the climb up the middle stays free
	_fan(Vector3(0.98, 0.0, -5.22), "sit_cup", 0.6)
	_fan(Vector3(2.22, 0.0, -5.22), "sit", 0.6)
	# Up on the porch roof (3.58): one standing, one sitting on the front edge
	_fan(Vector3(1.9, 3.58, -6.4), "filmer", 0.5, 1.4)
	_fan(Vector3(4.6, 3.05, -5.35), "sit", 0.5, 1.2)
	# Peeking over the side fences (standing on buckets); the shed blocks the left fence around z -1..1.8
	for z: float in [-4.8, -3.0, 3.0, 4.6]:
		_fan(Vector3(-FENCE_X - 0.45, 0.6, z + randf_range(-0.2, 0.2)), "stand", 0.45)
	for z: float in [-4.4, -1.2]:
		_fan(Vector3(FENCE_X + 0.45, 0.6, z + randf_range(-0.2, 0.2)), "stand", 0.45)
	# The car (the hood is a perch): one on the trunk (0.95), one on the back edge of the roof (1.48)
	_fan(Vector3(8.75, 0.42, 2.25), "sit_cup", 0.55)
	_fan(Vector3(8.05, 0.95, 3.05), "sit", 0.55)
	# Standing around the driveway outside the gate
	for spot: Vector3 in [Vector3(9.4, 0, 0.7), Vector3(10.2, 0, 1.7), Vector3(9.7, 0, 4.2), Vector3(8.2, 0, 5.0)]:
		_fan(spot + Vector3(0, 0.015, 0), "stand", 0.55)

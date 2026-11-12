extends "res://scripts/levels/level_base.gd"
## CORNER STORE LOT (level id "store_lot"): the STAR-BRITE MART parking lot at night, where Rudy
## Two-Times runs his Tuesday fights (story chapter 4). They fight on the cracked asphalt of the
## lot (faded parking lines, oil stains, tar snakes, a puddle by the storm drain); the store front
## is the backdrop at -z (brick, bright windows full of posters, a buzzing neon sign over a flat
## metal awning, Rudy's ice machine, a pay phone), a parked sedan + cart corral along -x, the
## dumpster + a station wagon along +x, and the open street side (bench, light pole) toward the
## camera at +z. Fighting area x -7..7, z -5..5; ground y 0 (the sidewalks are raised 0.14).
## Helpers on main (m) are listed in scripts/levels/backyard.gd's header.
##
## Perches: car roof (1.48, -x), dumpster lid (1.35, +x back), station wagon hood (0.95, +x front),
## Rudy's ice machine (1.78, store front left), the store awning (2.75, kind "roof": biggest dive).

const WALL_Z := -6.6                                # store front face
const CURB_Z := -5.15                               # store sidewalk curb (yard edge is z -5)
const FRONT_CURB_Z := 6.0                           # street-side curb (camera side)
const WALK_Y := 0.14                                # sidewalk height
const LOT_RECT := Rect2(-10.0, -5.15, 20.0, 11.15)  # painted asphalt map: x -10..10, z -5.15..6
const MAP_W := 512
const MAP_H := 286
const CARDBOARD_RECT := Rect2(5.25, -4.75, 1.65, 1.9)  # flattened boxes by the dumpster ("wood": softer thud)

const ASPHALT_SHADER := """
shader_type spatial;
render_mode diffuse_lambert, cull_disabled;

uniform sampler2D map : source_color, filter_linear_mipmap;
uniform sampler2D detail : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 detail_scale = vec2(16.0, 9.0);

void fragment() {
	vec4 m = texture(map, UV);
	vec3 d = texture(detail, UV * detail_scale).rgb;
	float wet = 1.0 - m.a;   // alpha = dry: puddles, tar snakes and oil read glossy under the lights
	ALBEDO = m.rgb * d * 2.0 * (1.0 - wet * 0.3);
	ROUGHNESS = mix(0.93, 0.12, wet);
	SPECULAR = mix(0.25, 0.7, wet);
}
"""

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint = vec3(1.0, 0.8, 0.55);
uniform float strength = 0.06;

void fragment() {
	// UV.y runs 0 at the lamp to 1 at the far end; fade along the beam and toward the silhouette edges.
	float along = 1.0 - UV.y;
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	ALBEDO = tint * strength * along * along * facing;
}
"""

var m = null   # main.gd (helpers)
var _mart_label: Label3D = null
var _neon_light: OmniLight3D = null
var _neon_energy := 1.4
var _neon_wait := 2.0
var _neon_flick := 0.0


func _init() -> void:
	display_name = "CORNER STORE LOT"
	description = "The corner store parking lot: buzzing sign, shopping carts, a dumpster and Rudy's ice machine."
	time_of_day = "night"
	preview_color = Color(0.3, 0.32, 0.36)
	yard_bounds = Rect2(-7.0, -5.0, 14.0, 10.0)
	cam_clamp = Rect2(-5.0, -4.0, 10.0, 7.5)
	cam_height = 3.0
	cam_back = 5.8
	default_surface = "asphalt"
	surfaces = [{"rect": CARDBOARD_RECT, "kind": "wood"},
		{"rect": Rect2(-14.0, -12.0, 28.0, 12.0 + CURB_Z), "kind": "concrete"},
		{"rect": Rect2(-14.0, FRONT_CURB_Z, 28.0, 3.0), "kind": "concrete"}]
	spawn_p1 = Vector3(-1.8, 0.0, 0.3)
	spawn_p2 = Vector3(1.8, 0.0, -0.3)


func build(main_node: Node) -> void:
	super(main_node)
	m = main_node
	perches.clear()
	obstacles.clear()
	_build_ground()
	_build_store()
	_build_interior()
	_build_sign_and_awning()
	_build_storefront_props()
	_build_ice_machine()
	_build_dumpster()
	_build_corral()
	_car(Vector3(-7.95, 0, 0.6), Vector3(0, 0, 1), Color(0.2, 0.34, 0.38), false)
	add_perch("car roof", "car", Vector3(-7.95, 1.48, 0.85), Vector3(-6.35, 0.0, 0.85),
		footprint(Vector2(-7.95, 0.6), Vector2(0.92, 2.3), "THE CAR", "Car Door Crash", 250, "metal_hit"))
	_car(Vector3(7.95, 0, 1.3), Vector3(0, 0, 1), Color(0.4, 0.12, 0.1), true)
	add_perch("station wagon hood", "car", Vector3(7.75, 0.95, 2.75), Vector3(6.4, 0.0, 2.75),
		footprint(Vector2(7.95, 1.3), Vector2(0.92, 2.3), "THE STATION WAGON", "Station Wagon Crash", 250, "metal_hit"))
	_build_lot_props()
	_build_surroundings()
	_build_lights()
	_build_grime()
	m._flush_batches()
	_build_crowd_spots()
	item_spawns = [
		{"kind": "chair", "pos": Vector3(-2.4, 0.0, -4.2), "yaw": PI * 0.15},
		{"kind": "chair", "pos": Vector3(3.9, 0.0, -3.9), "yaw": -PI * 0.3},
		{"kind": "trash_can", "pos": Vector3(-0.75, 0.0, -4.62), "yaw": 0.0},
		{"kind": "trash_can", "pos": Vector3(5.6, 0.0, 4.55), "yaw": 0.0},
		{"kind": "plank", "pos": Vector3(5.4, 0.0, -1.5), "yaw": 0.35},
		{"kind": "table", "pos": Vector3(-6.9, 0.0, -3.7), "yaw": PI * 0.5},   # leaning on the cart corral, top faces +x
	]


# ---------------------------------------------------------------- textures

func _w2p(x: float, z: float) -> Vector2:
	return Vector2((x - LOT_RECT.position.x) / LOT_RECT.size.x * MAP_W, (z - LOT_RECT.position.y) / LOT_RECT.size.y * MAP_H)


func _ppm() -> float:
	return MAP_W / LOT_RECT.size.x


## Faded paint stripe (world XZ a..b, width in metres) with chipped, worn coverage.
func _stripe(img: Image, wear: Image, a: Vector2, b: Vector2, width: float, col: Color, alpha: float) -> void:
	var pa := _w2p(a.x, a.y)
	var pb := _w2p(b.x, b.y)
	var hw := width * _ppm() * 0.5
	var x0 := maxi(0, int(minf(pa.x, pb.x) - hw - 2.0))
	var x1 := mini(MAP_W - 1, int(maxf(pa.x, pb.x) + hw + 2.0))
	var y0 := maxi(0, int(minf(pa.y, pb.y) - hw - 2.0))
	var y1 := mini(MAP_H - 1, int(maxf(pa.y, pb.y) + hw + 2.0))
	var ab := pb - pa
	var l2 := maxf(ab.length_squared(), 0.001)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var t := clampf((p - pa).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(pa + ab * t)
			var cov := clampf(hw - d + 0.5, 0.0, 1.0)
			if cov <= 0.0:
				continue
			var w := wear.get_pixel(x, y).r
			var k := cov * alpha * smoothstep(0.3, 0.6, w) * (0.75 + randf() * 0.25)
			m._blend_px(img, x, y, col, k)


func _make_asphalt_map() -> ImageTexture:
	# Old parking-lot asphalt: warm dark grey with aggregate, sun-bleached worn lanes, darker
	# repair patches, tar-snake crack sealant, cracks (alligator cracking in one corner), faded
	# white / yellow parking lines, a hatched no-parking zone at the door, oil stains where the
	# engines sit, tire smears, cigarette butts and gum by the store, a puddle round the drain.
	var w := MAP_W
	var h := MAP_H
	var mot: Image = m._noise_img(w, h, 0.018, 3, false)
	var fine: Image = m._noise_img(w, h, 0.22, 2, false)
	var wear: Image = m._noise_img(w, h, 0.06, 3, false)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var wet := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	wet.fill(Color(0, 0, 0, 1))
	for y in h:
		for x in w:
			var a := mot.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var c := Color(0.25, 0.24, 0.235).darkened((a - 0.5) * 0.5 + (f - 0.5) * 0.25)
			c = c.lerp(Color(0.37, 0.355, 0.33), smoothstep(0.6, 0.85, a) * 0.55)   # sun-bleached, worn grey
			var r := randf()
			if r < 0.07:
				c = c.lightened(randf_range(0.12, 0.3))   # aggregate stones
			elif r < 0.11:
				c = c.darkened(0.3)
			img.set_pixel(x, y, c)
	var ppm := _ppm()
	# Repair patches: newer, blacker asphalt with a sealed seam round the edge.
	for pr: Rect2 in [Rect2(-5.6, 1.2, 2.6, 1.8), Rect2(2.2, -2.6, 3.4, 1.4), Rect2(-9.6, -4.6, 2.4, 3.2), Rect2(4.6, 3.4, 2.2, 1.6)]:
		var p0 := _w2p(pr.position.x, pr.position.y)
		var sz := pr.size * ppm
		m._soft_rect(img, p0.x, p0.y, sz.x, sz.y, Color(0.12, 0.12, 0.125), 0.75, 2.0)
		for e: Array in [[p0, p0 + Vector2(sz.x, 0)], [p0 + Vector2(sz.x, 0), p0 + sz], [p0 + sz, p0 + Vector2(0, sz.y)], [p0 + Vector2(0, sz.y), p0]]:
			var ea: Vector2 = e[0]
			var eb: Vector2 = e[1]
			m._line_px(img, ea, eb, Color(0.05, 0.05, 0.055), 0.9)
			m._line_px(wet, ea, eb, Color(1, 1, 1), 0.7)
	# Cracks + their tar-snake sealant (glossy black squiggles).
	var dark := Color(0.06, 0.06, 0.06)
	for i in 14:
		m._crack(img, Vector2(randf() * w, randf() * h), randf() * TAU, randi_range(10, 26), ppm * 0.35, dark)
	for i in 9:
		var p := Vector2(randf() * w, randf() * h)
		var ang := randf() * TAU
		for k in randi_range(14, 30):
			ang += randf_range(-0.6, 0.6)
			var q := p + Vector2(cos(ang), sin(ang)) * ppm * randf_range(0.15, 0.35)
			m._line_px(img, p, q, Color(0.04, 0.04, 0.045), 0.85)
			m._line_px(img, p + Vector2(0, 1), q + Vector2(0, 1), Color(0.05, 0.05, 0.055), 0.6)
			m._line_px(wet, p, q, Color(1, 1, 1), 0.8)
			p = q
	# Alligator cracking in the front-left of the lot.
	var ac := _w2p(-4.0, 3.6)
	for i in 40:
		var s := ac + Vector2(randf_range(-2.2, 2.2), randf_range(-1.2, 1.2)) * ppm
		m._crack(img, s, randf() * TAU, randi_range(2, 4), ppm * 0.2, dark)
	# Parking lines: the store row (nose-in), the front row, the side lane edges.
	var white := Color(0.86, 0.85, 0.78)
	var yellow := Color(0.86, 0.68, 0.22)
	for sx: float in [-6.75, -4.05, -1.35, 1.35, 4.05, 6.75]:
		_stripe(img, wear, Vector2(sx, CURB_Z), Vector2(sx, -0.3), 0.11, white, 0.62)
	for sx: float in [-4.05, -1.35, 1.35, 4.05]:
		_stripe(img, wear, Vector2(sx, FRONT_CURB_Z), Vector2(sx, 1.6), 0.11, white, 0.45)
	for sx: float in [-6.9, 6.9]:
		_stripe(img, wear, Vector2(sx, -2.2), Vector2(sx, 5.0), 0.1, white, 0.5)
	for t: Array in [[-6.9, -1.85, -10.0], [-6.9, 3.05, -10.0], [6.9, -1.15, 10.0], [6.9, 3.75, 10.0]]:
		_stripe(img, wear, Vector2(t[0], t[1]), Vector2(t[2], t[1]), 0.1, white, 0.5)
	# Hatched no-parking zone in front of the door (yellow box + diagonals).
	var hz := Rect2(-1.35, CURB_Z, 2.7, 1.9)
	for e: Array in [[hz.position, Vector2(hz.end.x, hz.position.y)], [Vector2(hz.end.x, hz.position.y), hz.end], [hz.end, Vector2(hz.position.x, hz.end.y)], [Vector2(hz.position.x, hz.end.y), hz.position]]:
		_stripe(img, wear, e[0], e[1], 0.1, yellow, 0.6)
	for k in 6:
		var x0 := hz.position.x - 1.2 + k * 0.6
		var a2 := Vector2(maxf(x0, hz.position.x), hz.position.y + maxf(0.0, hz.position.x - x0))
		var b2 := Vector2(minf(x0 + hz.size.y, hz.end.x), hz.end.y - maxf(0.0, x0 + hz.size.y - hz.end.x))
		if b2.x > a2.x + 0.1:
			_stripe(img, wear, a2, b2, 0.09, yellow, 0.5)
	# Red fire-lane paint flaking along the store curb.
	_stripe(img, wear, Vector2(-10.0, CURB_Z + 0.06), Vector2(10.0, CURB_Z + 0.06), 0.1, Color(0.6, 0.14, 0.1), 0.35)
	# Oil stains: where engines sit in the store row and the front row, under the parked cars.
	var oil_spots: Array[Vector2] = []
	for cx: float in [-5.4, -2.7, 2.7, 5.4]:
		oil_spots.append(Vector2(cx + randf_range(-0.3, 0.3), -3.9 + randf_range(-0.3, 0.3)))
	for cx: float in [-2.7, 0.0, 2.7]:
		oil_spots.append(Vector2(cx + randf_range(-0.3, 0.3), 2.6 + randf_range(-0.3, 0.3)))
	oil_spots.append(Vector2(-0.4, -0.8))
	oil_spots.append(Vector2(1.6, 1.0))
	for sp in oil_spots:
		var c := _w2p(sp.x, sp.y)
		var rr := ppm * randf_range(0.35, 0.6)
		for k in 6:
			var o := Vector2(randf_range(-rr, rr), randf_range(-rr, rr)) * 0.5
			m._soft_dot(img, c.x + o.x, c.y + o.y, rr * randf_range(0.4, 0.9), rr * randf_range(0.35, 0.8), Color(0.03, 0.03, 0.035), randf_range(0.2, 0.36), rr * 0.4)
		m._soft_dot(img, c.x, c.y, rr * 0.4, rr * 0.32, Color(0.02, 0.02, 0.025), 0.5, rr * 0.2)
		m._soft_dot(img, c.x + rr * 0.3, c.y, rr * 0.5, rr * 0.25, Color(0.3, 0.2, 0.4), 0.06, rr * 0.3)   # rainbow sheen
		m._soft_dot(wet, c.x, c.y, rr * 0.6, rr * 0.5, Color(1, 1, 1), 0.5, rr * 0.4)
		for k in 4:   # drips
			m._soft_dot(img, c.x + randf_range(-rr, rr) * 1.6, c.y + randf_range(-rr, rr) * 1.6, 1.6, 1.4, Color(0.03, 0.03, 0.03), 0.45, 1.0)
	# Tire smears: soft dark arcs where cars swing in and out of the spaces.
	for i in 7:
		var c0 := Vector2(randf() * w, randf_range(0.25, 0.75) * h)
		var rad := ppm * randf_range(3.0, 6.0)
		var a0 := randf() * TAU
		var span := randf_range(0.4, 0.9)
		for side: float in [0.0, ppm * 1.5]:
			var prev := c0 + Vector2(cos(a0), sin(a0)) * (rad + side)
			for k in 16:
				var ang2 := a0 + span * (k + 1) / 16.0
				var q := c0 + Vector2(cos(ang2), sin(ang2)) * (rad + side)
				for dd in 4:
					m._line_px(img, prev + Vector2(0, dd), q + Vector2(0, dd), Color(0.05, 0.05, 0.05), 0.07)
				prev = q
	# Cigarette butts, gum and grit near the store; dirt banked along the curbs.
	for i in 90:
		var p := _w2p(randf_range(-6.0, 6.0), CURB_Z + absf(randfn(0.0, 0.9)))
		if randf() < 0.5:
			m._soft_dot(img, p.x, p.y, 0.9, 0.6, Color(0.85, 0.8, 0.68), 0.7, 0.5)
		else:
			m._soft_dot(img, p.x, p.y, 1.4, 1.3, Color(0.42, 0.41, 0.4), 0.5, 0.7)
	# The puddle round the storm drain (front-left), and a shallow one in a worn dip.
	for pd: Array in [[Vector2(-3.0, 4.15), 1.0, 0.55], [Vector2(3.4, 0.9), 0.7, 0.4]]:
		var pc: Vector2 = pd[0]
		var c := _w2p(pc.x, pc.y)
		var rx: float = pd[1]
		var rz: float = pd[2]
		for k in 5:
			var o := Vector2(randf_range(-0.4, 0.4) * rx, randf_range(-0.4, 0.4) * rz) * ppm
			m._soft_dot(wet, c.x + o.x, c.y + o.y, rx * ppm * randf_range(0.5, 0.8), rz * ppm * randf_range(0.5, 0.8), Color(1, 1, 1), 0.9, ppm * 0.15)
			m._soft_dot(img, c.x + o.x, c.y + o.y, rx * ppm * 0.7, rz * ppm * 0.7, Color(0.08, 0.08, 0.09), 0.2, ppm * 0.2)
	# Dirt banked against the curbs and side walls; pack the wet mask into alpha (alpha = dry).
	var dirt := Color(0.16, 0.13, 0.1)
	for y in h:
		var z := LOT_RECT.position.y + (y + 0.5) / h * LOT_RECT.size.y
		var ez := maxf(1.0 - smoothstep(0.0, 0.5, z - CURB_Z), 1.0 - smoothstep(0.0, 0.5, FRONT_CURB_Z - z))
		for x in w:
			var c := img.get_pixel(x, y)
			var xx := LOT_RECT.position.x + (x + 0.5) / w * LOT_RECT.size.x
			var edge := maxf(ez, 1.0 - smoothstep(0.0, 0.6, 10.0 - absf(xx)))
			if edge > 0.0:
				var ca := c.a
				c = c.lerp(dirt, edge * 0.5 * (0.6 + wear.get_pixel(x, y).r * 0.6))
				c.a = ca
			c.a = 1.0 - wet.get_pixel(x, y).r * 0.92
			img.set_pixel(x, y, c)
	return m._sharp_tex(img)


func _make_asphalt_detail() -> ImageTexture:
	# Tileable close-up grain (grey around 0.5): binder, stones, pits.
	var n := 128
	var nz: Image = m._noise_img(n, n, 0.16, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var g := 0.5 + (nz.get_pixel(x, y).r - 0.5) * 0.3
			var r := randf()
			if r < 0.1:
				g += randf_range(0.08, 0.22)
			elif r < 0.18:
				g -= randf_range(0.08, 0.18)
			img.set_pixel(x, y, Color(g, g, g * 0.98))
	return m._sharp_tex(img)


func _make_chainlink_texture() -> ImageTexture:
	# Galvanised chain-link diamonds on transparent (alpha scissor).
	var n := 64
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var u := (x + y) % 32
			var v := (x - y + 64) % 32
			if u < 3 or v < 3:
				var g := 0.62 + 0.15 * float((x + y) % 7) / 7.0
				img.set_pixel(x, y, Color(g, g, g * 0.97, 1.0))
	return m._sharp_tex(img)


# ---------------------------------------------------------------- small helpers

func _lab(text: String, pos: Vector3, size: int, col: Color, yaw := 0.0, shaded := false, outline := Color(0, 0, 0, 0), outline_size := 0, px := 0.005) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = col
	l.outline_size = outline_size
	l.outline_modulate = outline
	l.shaded = shaded
	l.position = pos
	l.rotation = Vector3(0, yaw, 0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l


func _vquad(mat: Material, a: Vector3, b: Vector3, h: float, rep: Vector2) -> void:
	# Vertical textured quad standing on the a..b line, h tall.
	var n := (b - a).cross(Vector3.UP).normalized()
	var up := Vector3(0, h, 0)
	var pts: Array[Vector3] = [a + up, b + up, b, a]
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(rep.x, 0), rep, Vector2(0, rep.y)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _beam_cone(from: Vector3, aim: Vector3, length: float, half_angle_deg: float, tint: Color, strength: float) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
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
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := (aim - from).normalized()
	mi.transform = Transform3D(Basis(Quaternion(Vector3.DOWN, dir)), from + dir * length * 0.5)
	add_child(mi)


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	# Far ground: dark asphalt everywhere (street, side lots).
	var far: StandardMaterial3D = m._tex_mat(_make_asphalt_detail())
	far.albedo_color = Color(0.2, 0.195, 0.19)
	far.uv1_scale = Vector3(70, 70, 1)
	far.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._plane(Vector2(90, 90), Vector3(0, -0.01, 0), far)
	# The lot itself: one painted map + tiled grain.
	var sh := Shader.new()
	sh.code = ASPHALT_SHADER
	var am := ShaderMaterial.new()
	am.shader = sh
	am.set_shader_parameter("map", _make_asphalt_map())
	am.set_shader_parameter("detail", _make_asphalt_detail())
	am.set_shader_parameter("detail_scale", Vector2(LOT_RECT.size.x / 1.3, LOT_RECT.size.y / 1.3))
	m._ground_quad(Vector3(LOT_RECT.get_center().x, 0.0, LOT_RECT.get_center().y), LOT_RECT.size, am)
	# Raised concrete sidewalks: the store's (z WALL_Z..CURB_Z) and the street side (z 6..8).
	var cm: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 3))
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sd := CURB_Z - WALL_Z
	m._ground_quad(Vector3(0, WALK_Y, (WALL_Z + CURB_Z) * 0.5), Vector2(24.0, sd), cm, 0.0, Vector2(24.0 / 6.0, sd / 6.0))
	var cm2: StandardMaterial3D = m._tex_mat(m._make_concrete_texture(256, true, 2))
	cm2.cull_mode = BaseMaterial3D.CULL_DISABLED
	m._ground_quad(Vector3(0, WALK_Y, FRONT_CURB_Z + 1.0), Vector2(30.0, 2.0), cm2, 0.0, Vector2(5.0, 0.33))
	var curb := Color(0.62, 0.6, 0.55)
	m._bx("block", Vector3(24.0, WALK_Y, 0.16), Vector3(0, WALK_Y * 0.5, CURB_Z - 0.08), curb)
	m._bx("flat", Vector3(24.0, 0.02, 0.17), Vector3(0, WALK_Y - 0.005, CURB_Z - 0.08), Color(0.58, 0.2, 0.15))  # faded red curb paint
	m._bx("block", Vector3(30.0, WALK_Y, 0.16), Vector3(0, WALK_Y * 0.5, FRONT_CURB_Z + 0.08), curb)
	# Street beyond the front sidewalk: a worn yellow centre line.
	for k in 8:
		m._bx("flat", Vector3(2.2, 0.01, 0.12), Vector3(-14.0 + k * 4.0, 0.0, 12.5), Color(0.55, 0.45, 0.18))
	# Curb stops (wheel stops) in the store row; one knocked crooked.
	var stop := Color(0.66, 0.64, 0.6)
	m._bx("block", Vector3(1.7, 0.13, 0.22), Vector3(-2.7, 0.065, -4.72), stop)
	m._bx("block", Vector3(1.7, 0.13, 0.22), Vector3(5.4, 0.065, -4.7), stop, 0.18)
	m._bx("flat", Vector3(1.7, 0.02, 0.06), Vector3(-2.7, 0.13, -4.72), Color(0.78, 0.66, 0.22))
	m._bx("block", Vector3(1.7, 0.13, 0.22), Vector3(-9.6, 0.065, 0.6), stop, PI * 0.5)
	m._bx("block", Vector3(1.7, 0.13, 0.22), Vector3(9.6, 0.065, 1.3), stop, PI * 0.5)
	# Storm drain grate in the puddle.
	m._bx("metal", Vector3(0.9, 0.02, 0.5), Vector3(-3.0, 0.005, 4.15), Color(0.16, 0.15, 0.14))
	for k in 6:
		m._bx("flat", Vector3(0.05, 0.022, 0.42), Vector3(-3.32 + k * 0.13, 0.006, 4.15), Color(0.02, 0.02, 0.02))
	# Flattened cardboard boxes by the dumpster.
	var cb := Color(0.55, 0.42, 0.28)
	m._bx("flat", Vector3(1.2, 0.02, 0.9), Vector3(5.85, 0.01, -4.15), cb, 0.2)
	m._bx("flat", Vector3(1.0, 0.025, 0.8), Vector3(6.25, 0.02, -3.35), cb.darkened(0.12), -0.35)
	m._bx("flat", Vector3(0.8, 0.03, 0.7), Vector3(5.7, 0.03, -3.25), cb.lightened(0.06), 0.9)


# ---------------------------------------------------------------- the store

func _build_store() -> void:
	var brick := Color(0.92, 0.86, 0.82)
	var wz := WALL_Z - 0.15
	var top := 4.6
	# Front wall pieces around the openings (window A x -3.5..-0.5, door x -0.1..1.0, window B x 1.4..4.4).
	m._bx("brick", Vector3(6.5, top, 0.3), Vector3(-6.75, top * 0.5, wz), brick, 0.0, 0.85)
	m._bx("brick", Vector3(5.6, top, 0.3), Vector3(7.2, top * 0.5, wz), brick, 0.0, 0.85)
	m._bx("brick", Vector3(7.9, top - 2.35, 0.3), Vector3(0.45, 2.35 + (top - 2.35) * 0.5, wz), brick, 0.0, 0.85)
	m._bx("brick", Vector3(0.4, 2.35, 0.3), Vector3(-0.3, 1.175, wz), brick, 0.0, 0.85)
	m._bx("brick", Vector3(0.4, 2.35, 0.3), Vector3(1.2, 1.175, wz), brick, 0.0, 0.85)
	m._bx("brick", Vector3(1.1, 0.15, 0.3), Vector3(0.45, 2.275, wz), brick, 0.0, 0.85)
	var kick := Color(0.36, 0.2, 0.17)
	m._bx("block", Vector3(3.0, 0.75, 0.3), Vector3(-2.0, 0.375, wz), kick)
	m._bx("block", Vector3(3.0, 0.75, 0.3), Vector3(2.9, 0.375, wz), kick)
	# Side walls and the flat roof with a parapet cap.
	for s: float in [-1.0, 1.0]:
		m._bx("brick", Vector3(0.3, top, 10.0), Vector3(s * 9.85, top * 0.5, WALL_Z - 5.0), brick.darkened(0.15), 0.0, 0.85)
	m._bx("block", Vector3(20.3, 0.16, 0.42), Vector3(0, top + 0.08, WALL_Z - 0.12), Color(0.62, 0.6, 0.56))
	m._bx("flat", Vector3(19.4, 0.1, 10.0), Vector3(0, top - 0.08, WALL_Z - 5.2), Color(0.16, 0.16, 0.17))
	# Rooftop units peeking over the parapet.
	m._bx("metal", Vector3(1.6, 1.0, 1.2), Vector3(-5.2, top + 0.4, WALL_Z - 3.0), Color(0.55, 0.56, 0.55))
	m._bx("metal", Vector3(1.0, 0.7, 1.0), Vector3(6.4, top + 0.25, WALL_Z - 2.4), Color(0.5, 0.5, 0.5))
	m._cy("metal", 0.12, 0.12, 1.4, Vector3(-3.6, top + 0.5, WALL_Z - 2.0), Color(0.45, 0.45, 0.45), 8)
	# Aluminium frames round the openings + window mullions.
	var al := Color(0.72, 0.72, 0.7)
	var fz := WALL_Z + 0.03
	for wx: float in [-2.0, 2.9]:
		m._bx("metal", Vector3(3.04, 0.07, 0.1), Vector3(wx, 0.78, fz), al)
		m._bx("metal", Vector3(3.04, 0.07, 0.1), Vector3(wx, 2.33, fz), al)
		m._bx("metal", Vector3(3.04, 0.05, 0.1), Vector3(wx, 2.0, fz), al)   # transom bar
		for k in 3:
			m._bx("metal", Vector3(0.07, 1.6, 0.1), Vector3(wx - 1.5 + k * 1.5, 1.55, fz), al)
	m._bx("metal", Vector3(0.07, 2.2, 0.1), Vector3(-0.1, 1.1, fz), al)
	m._bx("metal", Vector3(0.07, 2.2, 0.1), Vector3(1.0, 1.1, fz), al)
	m._bx("metal", Vector3(1.17, 0.08, 0.1), Vector3(0.45, 2.18, fz), al)
	# The door: glass with a frame, push bar, kick plate.
	m._bx("metal", Vector3(0.06, 2.05, 0.06), Vector3(0.05, 1.04, WALL_Z - 0.02), al.darkened(0.1))
	m._bx("metal", Vector3(0.06, 2.05, 0.06), Vector3(0.85, 1.04, WALL_Z - 0.02), al.darkened(0.1))
	m._bx("metal", Vector3(0.86, 0.3, 0.05), Vector3(0.45, 0.17, WALL_Z - 0.02), al.darkened(0.15))
	m._bx("metal", Vector3(0.7, 0.05, 0.07), Vector3(0.45, 1.05, WALL_Z + 0.01), Color(0.8, 0.8, 0.78))
	# Wall packs (security lights) on the piers, a camera over the door.
	for lx: float in [-8.2, 8.4]:
		m._bx("metal", Vector3(0.36, 0.28, 0.22), Vector3(lx, 3.7, WALL_Z + 0.11), Color(0.2, 0.2, 0.21))
		m._bx("glow", Vector3(0.28, 0.08, 0.2), Vector3(lx, 3.55, WALL_Z + 0.13), Color(1.0, 0.86, 0.6))
	m._bx("flat", Vector3(0.16, 0.12, 0.28), Vector3(1.25, 2.55, WALL_Z + 0.16), Color(0.85, 0.85, 0.82))
	m._bx("glow", Vector3(0.03, 0.03, 0.02), Vector3(1.3, 2.55, WALL_Z + 0.31), Color(1.0, 0.1, 0.05))
	# Painted wall ad on the right pier and a NO LOITERING plate on the left one.
	_lab("GROCERIES  BEER  WINE", Vector3(7.1, 3.75, WALL_Z + 0.02), 64, Color(0.92, 0.88, 0.76, 0.5), 0.0, true, Color(0, 0, 0, 0), 0, 0.006)
	_lab("CHECKS CASHED", Vector3(7.1, 3.3, WALL_Z + 0.02), 52, Color(0.92, 0.88, 0.76, 0.42), 0.0, true, Color(0, 0, 0, 0), 0, 0.006)
	m._bx("flat", Vector3(0.7, 0.42, 0.02), Vector3(-8.9, 2.0, WALL_Z + 0.02), Color(0.86, 0.85, 0.8))
	_lab("NO\nLOITERING", Vector3(-8.9, 2.0, WALL_Z + 0.04), 28, Color(0.7, 0.08, 0.06), 0.0, true, Color(0, 0, 0, 0), 0, 0.004)


func _build_interior() -> void:
	# Fluorescent-lit shop behind the glass (all unshaded "glow": it is lit from inside).
	var z0 := WALL_Z - 0.3
	var z1 := WALL_Z - 4.2
	var x0 := -3.6
	var x1 := 4.5
	var cz := (z0 + z1) * 0.5
	var dz := z0 - z1
	m._bx("glow", Vector3(x1 - x0, 0.05, dz), Vector3((x0 + x1) * 0.5, 0.02, cz), Color(0.5, 0.5, 0.46))     # floor tile
	m._bx("glow", Vector3(x1 - x0, 0.05, dz), Vector3((x0 + x1) * 0.5, 2.95, cz), Color(0.55, 0.56, 0.52))   # ceiling
	m._bx("glow", Vector3(x1 - x0, 3.0, 0.05), Vector3((x0 + x1) * 0.5, 1.5, z1), Color(0.66, 0.7, 0.64))     # back wall
	for sx: float in [x0, x1]:
		m._bx("glow", Vector3(0.05, 3.0, dz), Vector3(sx, 1.5, cz), Color(0.58, 0.6, 0.56))
	for k in 3:   # fluorescent tubes
		m._bx("glow", Vector3(x1 - x0 - 0.6, 0.06, 0.18), Vector3((x0 + x1) * 0.5, 2.9, z0 - 0.6 - k * 1.2), Color(1.0, 1.0, 0.95))
	# Beer coolers on the back wall.
	for k in 7:
		var cx := x0 + 0.65 + k * 1.1
		m._bx("glow", Vector3(1.0, 2.0, 0.05), Vector3(cx, 1.15, z1 + 0.04), Color(0.72, 0.85, 0.92))
		m._bx("glow", Vector3(0.06, 2.0, 0.06), Vector3(cx + 0.53, 1.15, z1 + 0.06), Color(0.16, 0.16, 0.17))
		for r in 4:
			for c in 5:
				var pc: Color = [Color(0.75, 0.2, 0.15), Color(0.85, 0.7, 0.2), Color(0.2, 0.35, 0.7), Color(0.2, 0.55, 0.3), Color(0.9, 0.9, 0.85)][(k + r * 2 + c) % 5]
				m._bx("glow", Vector3(0.13, 0.26, 0.04), Vector3(cx - 0.36 + c * 0.18, 0.45 + r * 0.45, z1 + 0.07), pc.darkened(0.2))
	# Gondola shelves with end caps facing the windows, products in rows.
	var prod: Array[Color] = [Color(0.85, 0.25, 0.18), Color(0.95, 0.75, 0.2), Color(0.25, 0.45, 0.8), Color(0.95, 0.5, 0.15),
		Color(0.3, 0.65, 0.35), Color(0.85, 0.85, 0.8), Color(0.6, 0.25, 0.55)]
	for gx: float in [-2.6, -1.1, 3.6]:
		var gz := WALL_Z - 1.6
		m._bx("glow", Vector3(0.9, 1.5, 2.2), Vector3(gx, 0.75, gz - 0.9), Color(0.32, 0.33, 0.33))
		for r in 4:
			var sy := 0.25 + r * 0.36
			m._bx("glow", Vector3(0.95, 0.03, 0.1), Vector3(gx, sy, gz + 0.22), Color(0.75, 0.75, 0.72))
			for c in 5:
				m._bx("glow", Vector3(0.15, 0.26, 0.06), Vector3(gx - 0.36 + c * 0.18, sy + 0.15, gz + 0.22), prod[posmod(r * 3 + c + int(gx * 2.0), prod.size())].darkened(randf_range(0.0, 0.25)))
	# Counter by the door (window B), lottery display and the cigarette rack behind it.
	m._bx("glow", Vector3(2.0, 1.0, 0.6), Vector3(2.3, 0.5, WALL_Z - 1.0), Color(0.42, 0.3, 0.22))
	m._bx("glow", Vector3(1.9, 0.05, 0.65), Vector3(2.3, 1.02, WALL_Z - 1.0), Color(0.62, 0.6, 0.55))
	m._bx("glow", Vector3(0.5, 0.35, 0.3), Vector3(1.7, 1.2, WALL_Z - 1.0), Color(0.15, 0.15, 0.16))   # register
	m._bx("glow", Vector3(1.8, 1.0, 0.25), Vector3(2.5, 1.9, WALL_Z - 2.0), Color(0.3, 0.26, 0.22))
	for c in 9:
		for r in 3:
			m._bx("glow", Vector3(0.14, 0.2, 0.04), Vector3(1.75 + c * 0.19, 1.6 + r * 0.28, WALL_Z - 1.86), prod[(c + r) % prod.size()].darkened(0.3))


func _poster(pos: Vector3, size: Vector2, bg: Color, text: String, ink: Color, font: int) -> void:
	# Taped to the inside of the glass, backlit by the shop.
	m._bx("glow", Vector3(size.x, size.y, 0.02), pos, bg)
	_lab(text, pos + Vector3(0, 0, 0.02), font, ink, 0.0, false, Color(0, 0, 0, 0), 0, 0.0035)


func _build_sign_and_awning() -> void:
	# Flat metal canopy over the windows (top y 2.75): the highest perch, the big dive.
	var ax0 := -3.8
	var ax1 := 4.8
	var acx := (ax0 + ax1) * 0.5
	var aw := ax1 - ax0
	var front := CURB_Z + 0.05
	var depth := front - WALL_Z
	m._bx("metal", Vector3(aw, 0.16, depth), Vector3(acx, 2.67, (WALL_Z + front) * 0.5), Color(0.62, 0.6, 0.57))
	m._bx("flat", Vector3(aw, 0.02, depth), Vector3(acx, 2.755, (WALL_Z + front) * 0.5), Color(0.3, 0.29, 0.28))   # tar-paper top
	var n := 20
	for k in n:
		var col := Color(0.62, 0.12, 0.1) if k % 2 == 0 else Color(0.86, 0.8, 0.66)
		m._bx("flat", Vector3(aw / n, 0.42, 0.04), Vector3(ax0 + (k + 0.5) * aw / n, 2.5, front + 0.02), col)
	m._bx("metal", Vector3(aw + 0.04, 0.05, 0.07), Vector3(acx, 2.73, front + 0.03), Color(0.7, 0.7, 0.68))
	m._bx("metal", Vector3(aw + 0.04, 0.04, 0.06), Vector3(acx, 2.29, front + 0.03), Color(0.5, 0.5, 0.48))
	for k in 3:   # downlights under the canopy
		m._bx("glow", Vector3(0.5, 0.03, 0.2), Vector3(-2.3 + k * 2.8, 2.58, WALL_Z + 0.75), Color(1.0, 0.96, 0.86))
	for rx: float in [-3.4, 0.5, 4.4]:   # tie rods to the wall
		m._beam("metal", Vector3(rx, 2.74, front - 0.1), Vector3(rx, 4.25, WALL_Z + 0.02), 0.035, Color(0.3, 0.3, 0.3))
	# A stack of milk crates under the canopy (how you get up there).
	var crate_cols: Array[Color] = [Color(0.65, 0.12, 0.1), Color(0.15, 0.3, 0.65), Color(0.65, 0.12, 0.1), Color(0.75, 0.6, 0.15)]
	for k in 4:
		m._bx("flat", Vector3(0.36, 0.28, 0.36), Vector3(1.45 + (k % 2) * 0.03, WALK_Y + 0.14 + k * 0.29, CURB_Z - 0.32), crate_cols[k], 0.1 * (k % 3))
	m._bx("flat", Vector3(0.36, 0.28, 0.36), Vector3(2.0, WALK_Y + 0.14, CURB_Z - 0.3), crate_cols[1], -0.2)
	add_perch("store awning", "roof", Vector3(1.8, 2.75, -6.0), Vector3(1.8, 0.0, -4.35),
		footprint(Vector2(acx, (WALL_Z + front) * 0.5), Vector2(aw * 0.5, depth * 0.5), "THE STOREFRONT", "Storefront Crash", 250, "metal_hit"))

	# The neon sign: dark raceway box above the canopy, pink STAR-BRITE + blue (buzzing) MART.
	var sz := WALL_Z + 0.16
	m._bx("flat", Vector3(7.8, 1.0, 0.28), Vector3(0.5, 3.45, sz), Color(0.07, 0.07, 0.11))
	m._bx("metal", Vector3(7.9, 0.06, 0.3), Vector3(0.5, 3.97, sz), Color(0.35, 0.35, 0.36))
	m._bx("metal", Vector3(7.9, 0.06, 0.3), Vector3(0.5, 2.93, sz), Color(0.35, 0.35, 0.36))
	var tube := Color(1.0, 0.45, 0.62)
	var fzn := sz + 0.15
	m._beam("glow", Vector3(-3.25, 3.03, fzn), Vector3(4.25, 3.03, fzn), 0.03, tube)
	m._beam("glow", Vector3(-3.25, 3.87, fzn), Vector3(4.25, 3.87, fzn), 0.03, tube)
	m._beam("glow", Vector3(-3.25, 3.03, fzn), Vector3(-3.25, 3.87, fzn), 0.03, tube)
	m._beam("glow", Vector3(4.25, 3.03, fzn), Vector3(4.25, 3.87, fzn), 0.03, tube)
	_lab("STAR-BRITE", Vector3(-0.55, 3.56, fzn + 0.01), 104, Color(1.0, 0.78, 0.88), 0.0, false, Color(1.0, 0.16, 0.45, 0.55), 22)
	_mart_label = _lab("MART", Vector3(3.15, 3.56, fzn + 0.01), 104, Color(0.82, 0.96, 1.0), 0.0, false, Color(0.1, 0.55, 1.0, 0.55), 22)
	_lab("BEER  *  ICE  *  LOTTO  *  ATM", Vector3(0.5, 3.16, fzn + 0.01), 40, Color(1.0, 0.9, 0.6), 0.0, false, Color(1.0, 0.5, 0.1, 0.45), 12)
	# Little OPEN neon in window B and the posters on the glass.
	var gz := WALL_Z - 0.05
	_lab("OPEN", Vector3(3.9, 2.18, gz + 0.03), 56, Color(1.0, 0.55, 0.5), 0.0, false, Color(1.0, 0.1, 0.1, 0.6), 14, 0.004)
	m._beam("glow", Vector3(3.55, 2.06, gz), Vector3(4.25, 2.06, gz), 0.02, Color(0.4, 0.6, 1.0))
	m._beam("glow", Vector3(3.55, 2.3, gz), Vector3(4.25, 2.3, gz), 0.02, Color(0.4, 0.6, 1.0))
	_poster(Vector3(-3.0, 1.55, gz), Vector2(0.75, 0.62), Color(0.92, 0.78, 0.2), "ICE COLD\nBEER", Color(0.7, 0.08, 0.05), 40)
	_poster(Vector3(-2.05, 1.4, gz), Vector2(0.6, 0.5), Color(0.15, 0.5, 0.25), "LOTTO\nHERE", Color(0.95, 0.95, 0.9), 40)
	_poster(Vector3(-1.05, 1.6, gz), Vector2(0.72, 0.55), Color(0.92, 0.9, 0.84), "HOT COFFEE\n99c", Color(0.35, 0.18, 0.1), 34)
	_poster(Vector3(-2.6, 1.0, gz), Vector2(0.62, 0.32), Color(0.9, 0.88, 0.82), "BAGGED ICE $2", Color(0.1, 0.25, 0.65), 26)
	_poster(Vector3(2.1, 1.55, gz), Vector2(0.7, 0.55), Color(0.95, 0.5, 0.12), "2 FOR $5", Color(0.08, 0.06, 0.05), 44)
	_poster(Vector3(3.0, 1.15, gz), Vector2(0.75, 0.45), Color(0.2, 0.35, 0.7), "PHONE\nCARDS", Color(0.95, 0.92, 0.8), 36)
	_poster(Vector3(0.45, 1.55, gz + 0.02), Vector2(0.42, 0.42), Color(0.9, 0.9, 0.86), "NO SHIRT\nNO SHOES\nNO SERVICE", Color(0.1, 0.1, 0.1), 20)


func _build_storefront_props() -> void:
	# Pay phone on the right pier: box, hood, blue PHONE header, handset dangling off the hook.
	var px := 5.7
	var pz := WALL_Z + 0.15
	m._bx("metal", Vector3(0.66, 1.05, 0.06), Vector3(px, 1.55, WALL_Z + 0.03), Color(0.55, 0.56, 0.57))
	m._bx("metal", Vector3(0.42, 0.7, 0.22), Vector3(px, 1.5, pz), Color(0.6, 0.6, 0.62))
	m._bx("flat", Vector3(0.3, 0.12, 0.02), Vector3(px, 1.72, pz + 0.12), Color(0.08, 0.08, 0.08))
	m._bx("metal", Vector3(0.72, 0.06, 0.42), Vector3(px, 2.1, WALL_Z + 0.22), Color(0.5, 0.5, 0.52))
	m._bx("glow", Vector3(0.66, 0.2, 0.04), Vector3(px, 2.25, WALL_Z + 0.1), Color(0.3, 0.5, 0.9))
	_lab("PHONE", Vector3(px, 2.25, WALL_Z + 0.13), 40, Color(0.95, 0.97, 1.0), 0.0, false, Color(0, 0, 0, 0), 0, 0.004)
	m._bx("metal", Vector3(0.5, 0.04, 0.3), Vector3(px, 1.08, pz + 0.05), Color(0.45, 0.45, 0.46))   # shelf
	m._bx("flat", Vector3(0.34, 0.06, 0.24), Vector3(px, 1.13, pz + 0.05), Color(0.75, 0.68, 0.3))   # phone book
	var cord_top := Vector3(px - 0.15, 1.3, pz + 0.12)
	var hand := Vector3(px - 0.2, 0.75, pz + 0.18)
	m._beam("flat", cord_top, hand + Vector3(0, 0.1, 0), 0.02, Color(0.6, 0.6, 0.62))
	m._bx("flat", Vector3(0.06, 0.22, 0.07), hand, Color(0.06, 0.06, 0.06))
	# Newspaper boxes on the sidewalk, left of the ice machine.
	var np_cols: Array[Color] = [Color(0.15, 0.3, 0.6), Color(0.7, 0.15, 0.12), Color(0.85, 0.7, 0.2)]
	for k in 3:
		var bp := Vector3(-8.6 + k * 0.62, WALK_Y, -6.15)
		for lx: float in [-0.2, 0.2]:
			m._bx("metal", Vector3(0.04, 0.4, 0.04), bp + Vector3(lx, 0.2, 0.0), Color(0.25, 0.25, 0.25))
		m._bx("flat", Vector3(0.5, 0.62, 0.45), bp + Vector3(0, 0.71, 0), np_cols[k], randf_range(-0.05, 0.05))
		m._bx("flat", Vector3(0.36, 0.26, 0.02), bp + Vector3(0, 0.8, 0.23), Color(0.6, 0.58, 0.52))
		m._bx("flat", Vector3(0.52, 0.04, 0.47), bp + Vector3(0, 1.03, 0), np_cols[k].darkened(0.3))
	# Tags on the brick (C2C right of the windows, TWINS over the newspaper boxes).
	m._wall_decal(m._make_tag_texture("C2C", Color(0.78, 0.16, 0.1), Color(0.06, 0.05, 0.05), Color(0.98, 0.78, 0.5)),
		Vector3(8.3, 1.25, WALL_Z), Vector2(1.6, 0.8), Vector3.BACK)
	m._wall_decal(m._make_tag_texture("TWINS", Color(0.86, 0.84, 0.78), Color(0.1, 0.16, 0.42), Color(1.0, 1.0, 1.0)),
		Vector3(-7.4, 1.75, WALL_Z), Vector2(1.5, 0.75), Vector3.BACK)


func _build_ice_machine() -> void:
	# Rudy's ice machine: white merchandiser on the sidewalk with a backlit ICE header (top 1.78).
	var c := Vector3(-4.7, WALK_Y, -6.1)
	var body := Color(0.82, 0.84, 0.86)
	m._bx("metal", Vector3(1.3, 0.1, 0.8), c + Vector3(0, 0.05, 0), Color(0.3, 0.3, 0.3))
	m._bx("flat", Vector3(1.3, 1.54, 0.85), c + Vector3(0, 0.87, 0), body)
	m._bx("metal", Vector3(1.34, 0.06, 0.89), c + Vector3(0, 1.62, 0), Color(0.7, 0.72, 0.74))
	var fz := c.z + 0.43
	m._bx("glow", Vector3(1.16, 0.32, 0.03), Vector3(c.x, c.y + 1.38, fz), Color(0.55, 0.78, 1.0))
	_lab("ICE", Vector3(c.x, c.y + 1.38, fz + 0.025), 72, Color(0.08, 0.28, 0.78), 0.0, false, Color(1, 1, 1, 0.9), 8, 0.004)
	m._bx("flat", Vector3(0.52, 0.95, 0.03), Vector3(c.x - 0.3, c.y + 0.67, fz), Color(0.7, 0.74, 0.78))   # doors
	m._bx("flat", Vector3(0.52, 0.95, 0.03), Vector3(c.x + 0.3, c.y + 0.67, fz), Color(0.7, 0.74, 0.78))
	m._bx("metal", Vector3(0.04, 0.4, 0.05), Vector3(c.x - 0.08, c.y + 0.75, fz + 0.03), Color(0.85, 0.85, 0.85))
	m._bx("metal", Vector3(0.04, 0.4, 0.05), Vector3(c.x + 0.08, c.y + 0.75, fz + 0.03), Color(0.85, 0.85, 0.85))
	m._bx("flat", Vector3(1.2, 0.18, 0.03), Vector3(c.x, c.y + 0.2, fz), Color(0.35, 0.4, 0.45))   # kick grille
	m._bx("flat", Vector3(0.2, 0.05, 0.035), Vector3(c.x, c.y + 0.92, fz), Color(0.2, 0.2, 0.2))   # padlock
	# Rudy's note taped on the door (he says everything twice, so does the note).
	m._bx("flat", Vector3(0.36, 0.26, 0.01), Vector3(c.x + 0.3, c.y + 0.98, fz + 0.025), Color(0.95, 0.93, 0.82), 0.04)
	_lab("PROPERTY OF RUDY\nPROPERTY OF RUDY", Vector3(c.x + 0.3, c.y + 0.98, fz + 0.035), 18, Color(0.15, 0.12, 0.35), 0.0, true, Color(0, 0, 0, 0), 0, 0.003)
	add_perch("Rudy's ice machine", "ice_machine", Vector3(c.x, c.y + 1.64, c.z), Vector3(c.x, 0.0, -4.4),
		footprint(Vector2(c.x, c.z), Vector2(0.68, 0.45), "RUDY'S ICE MACHINE", "Ice Machine Crash", 250, "metal_hit"))


func _build_dumpster() -> void:
	# Green steel dumpster against the right side of the lot, black plastic lids (top 1.35).
	var c := Vector3(7.65, 0, -3.4)
	var green := Color(0.17, 0.3, 0.19)
	m._bx("flat", Vector3(1.12, 1.12, 1.92), c + Vector3(0, 0.68, 0), green)
	m._bx("flat", Vector3(1.18, 0.1, 1.98), c + Vector3(0, 1.2, 0), green.darkened(0.15))   # rim
	m._bx("flat", Vector3(1.16, 0.06, 0.95), c + Vector3(0.0, 1.29, -0.49), Color(0.05, 0.05, 0.06))
	m._sbox("flat", Vector3(1.16, 0.06, 0.95), Transform3D(Basis(Vector3.BACK, 0.12), c + Vector3(-0.04, 1.31, 0.49)), Color(0.06, 0.06, 0.07))
	m._cy("flat", 0.28, 0.22, 0.3, c + Vector3(-0.42, 1.3, 0.55), Color(0.05, 0.05, 0.05), 7)   # bag poking out
	for sz: float in [-0.75, 0.75]:   # fork pockets
		m._bx("flat", Vector3(1.22, 0.16, 0.22), c + Vector3(0, 0.95, sz), green.darkened(0.2))
	for p: Vector3 in [Vector3(-0.45, 0, -0.8), Vector3(0.45, 0, -0.8), Vector3(-0.45, 0, 0.8), Vector3(0.45, 0, 0.8)]:
		m._cy("flat", 0.06, 0.06, 0.12, c + p + Vector3(0, 0.06, 0), Color(0.05, 0.05, 0.05), 6)
	for k in 5:   # rust + dents
		m._bx("flat", Vector3(0.02, randf_range(0.1, 0.3), randf_range(0.1, 0.4)), c + Vector3(-0.565, randf_range(0.3, 1.0), randf_range(-0.8, 0.8)), Color(0.36, 0.18, 0.08))
	_lab("NO DUMPING", Vector3(c.x - 0.575, 0.85, c.z), 40, Color(0.9, 0.9, 0.85, 0.85), -PI * 0.5, true, Color(0, 0, 0, 0), 0, 0.005)
	# Trash bags heaped behind it.
	for bp: Vector3 in [Vector3(8.6, 0, -4.1), Vector3(8.75, 0, -3.3), Vector3(8.5, 0, -2.6), Vector3(8.9, 0.35, -3.7)]:
		m._cy("flat", 0.34, 0.22, 0.55, bp + Vector3(0, 0.27, 0), Color(0.05, 0.05, 0.06), 7)
	add_perch("dumpster lid", "dumpster", Vector3(7.6, 1.35, -3.4), Vector3(6.4, 0.0, -3.4),
		footprint(Vector2(c.x, c.z), Vector2(0.62, 1.0), "THE DUMPSTER", "Dumpster Crash", 250, "metal_hit"))


func _cart(pos: Vector3, yaw: float, tipped := false) -> void:
	# Wire shopping cart: basket, handle with a red grip, bottom rack, casters. Local -z = front.
	var b := Basis(Vector3.UP, yaw)
	var p := pos
	if tipped:
		b = b * Basis(Vector3.BACK, PI * 0.5)
		p += Vector3(0, 0.27, 0)
	var xf := Transform3D(b, p)
	var wire := Color(0.7, 0.71, 0.72)
	var bot: Array[Vector3] = [Vector3(-0.21, 0.42, -0.42), Vector3(0.21, 0.42, -0.42), Vector3(0.26, 0.44, 0.42), Vector3(-0.26, 0.44, 0.42)]
	var top: Array[Vector3] = [Vector3(-0.23, 0.9, -0.48), Vector3(0.23, 0.9, -0.48), Vector3(0.27, 0.95, 0.45), Vector3(-0.27, 0.95, 0.45)]
	for i in 4:
		var j := (i + 1) % 4
		m._beam("metal", xf * bot[i], xf * bot[j], 0.02, wire)
		m._beam("metal", xf * top[i], xf * top[j], 0.02, wire)
		m._beam("metal", xf * bot[i], xf * top[i], 0.02, wire)
	for k in 4:   # side wires
		var t := (k + 1) / 5.0
		for s in 2:
			var a0: Vector3 = bot[0].lerp(bot[3], t) if s == 0 else bot[1].lerp(bot[2], t)
			var a1: Vector3 = top[0].lerp(top[3], t) if s == 0 else top[1].lerp(top[2], t)
			m._beam("metal", xf * a0, xf * a1, 0.012, wire)
	for k in 3:   # mid rail all round
		var t2 := 0.5
		m._beam("metal", xf * bot[k].lerp(top[k], t2), xf * bot[k + 1].lerp(top[k + 1], t2), 0.012, wire)
	m._beam("metal", xf * Vector3(-0.27, 0.95, 0.45), xf * Vector3(-0.27, 1.02, 0.55), 0.025, wire)
	m._beam("metal", xf * Vector3(0.27, 0.95, 0.45), xf * Vector3(0.27, 1.02, 0.55), 0.025, wire)
	m._sbox("flat", Vector3(0.56, 0.05, 0.05), xf * Transform3D(Basis(), Vector3(0, 1.02, 0.55)), Color(0.7, 0.1, 0.08))
	for s: float in [-1.0, 1.0]:   # legs + bottom rack
		m._beam("metal", xf * Vector3(0.2 * s, 0.42, -0.4), xf * Vector3(0.18 * s, 0.08, -0.38), 0.025, wire)
		m._beam("metal", xf * Vector3(0.25 * s, 0.44, 0.4), xf * Vector3(0.24 * s, 0.08, 0.4), 0.025, wire)
		m._beam("metal", xf * Vector3(0.19 * s, 0.12, -0.38), xf * Vector3(0.24 * s, 0.12, 0.4), 0.02, wire)
	m._sbox("metal", Vector3(0.42, 0.015, 0.7), xf * Transform3D(Basis(), Vector3(0, 0.13, 0.0)), wire.darkened(0.2))
	for wp: Vector3 in [Vector3(-0.18, 0.05, -0.38), Vector3(0.18, 0.05, -0.38), Vector3(-0.24, 0.05, 0.4), Vector3(0.24, 0.05, 0.4)]:
		m._scyl("flat", 0.05, 0.05, 0.035, xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), wp), Color(0.06, 0.06, 0.06), 6)


func _build_corral() -> void:
	# Cart corral at the back-left: pipe rails on posts, closed at the store end, carts nested inside.
	var x0 := -8.3
	var x1 := -7.15
	var z0 := -4.9
	var z1 := -2.5
	var rail := Color(0.62, 0.62, 0.6)
	for x: float in [x0, x1]:
		for ry: float in [0.5, 0.92]:
			m._beam("metal", Vector3(x, ry, z0), Vector3(x, ry, z1), 0.06, rail)
		for pz: float in [z0, (z0 + z1) * 0.5, z1]:
			m._cy("metal", 0.035, 0.035, 0.95, Vector3(x, 0.475, pz), rail, 6)
	for ry: float in [0.5, 0.92]:
		m._beam("metal", Vector3(x0, ry, z0), Vector3(x1, ry, z0), 0.06, rail)
	m._bx("glow", Vector3(0.6, 0.3, 0.03), Vector3((x0 + x1) * 0.5, 1.1, z0 + 0.02), Color(0.25, 0.42, 0.75))
	_lab("CARTS", Vector3((x0 + x1) * 0.5, 1.1, z0 + 0.04), 28, Color(0.95, 0.95, 0.9), 0.0, false, Color(0, 0, 0, 0), 0, 0.004)
	for k in 3:
		_cart(Vector3((x0 + x1) * 0.5, 0.0, -4.35 + k * 0.42), 0.0)
	obstacles.append(footprint(Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5), Vector2((x1 - x0) * 0.5 + 0.04, (z1 - z0) * 0.5), "THE CART CORRAL", "Cart Corral Crash", 200, "metal_hit"))


func _car(pos: Vector3, face: Vector3, body: Color, wagon: bool) -> void:
	# Parked 80s/90s car; local -z = the nose. The sedan's roof and the wagon's hood are perches.
	var xf := Transform3D(Basis.looking_at(face), pos)
	var glass := Color(0.06, 0.07, 0.09)
	var dark := Color(0.04, 0.04, 0.045)
	m._sbox("flat", Vector3(1.78, 0.6, 4.5), xf * Transform3D(Basis(), Vector3(0, 0.62, 0)), body)
	m._sbox("flat", Vector3(1.7, 0.04, 1.3), xf * Transform3D(Basis(), Vector3(0, 0.935, -1.55)), body.lightened(0.06))   # hood
	if wagon:
		m._sbox("flat", Vector3(1.0, 0.045, 0.8), xf * Transform3D(Basis(), Vector3(0.25, 0.94, -1.6)), Color(0.48, 0.47, 0.44))   # primer hood patch
		m._sbox("flat", Vector3(0.03, 0.4, 1.0), xf * Transform3D(Basis(), Vector3(0.9, 0.62, -1.6)), Color(0.5, 0.48, 0.45))      # primer fender
		m._sbox("flat", Vector3(1.56, 0.5, 2.5), xf * Transform3D(Basis(), Vector3(0, 1.18, 0.75)), glass)
		m._sbox("flat", Vector3(1.52, 0.06, 2.55), xf * Transform3D(Basis(), Vector3(0, 1.455, 0.72)), body.darkened(0.08))
		for rz: float in [0.0, 1.0, 1.95]:   # pillars
			m._sbox("flat", Vector3(1.6, 0.48, 0.08), xf * Transform3D(Basis(), Vector3(0, 1.18, rz)), body.darkened(0.1))
		m._sbox("flat", Vector3(1.6, 0.48, 0.06), xf * Transform3D(Basis(), Vector3(0, 1.18, 2.0)), glass)
		for s: float in [-0.62, 0.62]:
			m._beam("metal", xf * Vector3(s, 1.5, -0.3), xf * Vector3(s, 1.5, 1.9), 0.035, Color(0.6, 0.6, 0.6))   # roof rack
		m._sbox("flat", Vector3(1.5, 0.04, 0.72), Transform3D(xf.basis * Basis(Vector3.RIGHT, -PI * 0.25), xf * Vector3(0, 1.2, -0.75)), glass)
	else:
		m._sbox("flat", Vector3(1.7, 0.04, 0.9), xf * Transform3D(Basis(), Vector3(0, 0.935, 1.75)), body.lightened(0.04))   # trunk
		m._sbox("flat", Vector3(1.56, 0.5, 1.5), xf * Transform3D(Basis(), Vector3(0, 1.18, 0.25)), glass)
		m._sbox("flat", Vector3(1.52, 0.06, 1.5), xf * Transform3D(Basis(), Vector3(0, 1.455, 0.25)), body.darkened(0.08))
		m._sbox("flat", Vector3(1.6, 0.48, 0.08), xf * Transform3D(Basis(), Vector3(0, 1.18, 0.25)), body.darkened(0.1))   # B pillar
		m._sbox("flat", Vector3(1.5, 0.04, 0.72), Transform3D(xf.basis * Basis(Vector3.RIGHT, -PI * 0.25), xf * Vector3(0, 1.18, -0.75)), glass)
		m._sbox("flat", Vector3(1.5, 0.04, 0.72), Transform3D(xf.basis * Basis(Vector3.RIGHT, PI * 0.25), xf * Vector3(0, 1.18, 1.25)), glass)
		m._sbox("flat", Vector3(0.9, 0.025, 0.05), xf * Transform3D(Basis(), Vector3(0, 1.0, 2.24)), Color(0.75, 0.75, 0.72))   # trunk chrome
	# Neon reflection streak on the windshield.
	m._sbox("glow", Vector3(1.0, 0.012, 0.12), Transform3D(xf.basis * Basis(Vector3.RIGHT, -PI * 0.25), xf * Vector3(0.15, 1.22, -0.72)), Color(0.22, 0.12, 0.17))
	# Bumpers, grille, lamps (off), plates, door seams, mirrors, wheels.
	for bz: float in [-2.27, 2.27]:
		m._sbox("flat", Vector3(1.84, 0.18, 0.12), xf * Transform3D(Basis(), Vector3(0, 0.42, bz)), Color(0.2, 0.2, 0.2))
		m._sbox("flat", Vector3(0.32, 0.16, 0.02), xf * Transform3D(Basis(), Vector3(0, 0.6, bz + signf(bz) * 0.02)), Color(0.85, 0.83, 0.75))
	m._sbox("flat", Vector3(0.9, 0.2, 0.04), xf * Transform3D(Basis(), Vector3(0, 0.72, -2.25)), dark)
	for sx: float in [-0.66, 0.66]:
		m._sbox("flat", Vector3(0.34, 0.18, 0.04), xf * Transform3D(Basis(), Vector3(sx, 0.74, -2.25)), Color(0.72, 0.72, 0.68))
		m._sbox("flat", Vector3(0.34, 0.15, 0.04), xf * Transform3D(Basis(), Vector3(sx, 0.76, 2.25)), Color(0.45, 0.05, 0.04))
		m._sbox("flat", Vector3(0.012, 0.5, 0.012), xf * Transform3D(Basis(), Vector3(sx * 1.36, 0.66, 0.0)), dark)
		m._sbox("flat", Vector3(0.012, 0.5, 0.012), xf * Transform3D(Basis(), Vector3(sx * 1.36, 0.66, -0.9)), dark)
		m._sbox("flat", Vector3(0.1, 0.08, 0.14), xf * Transform3D(Basis(), Vector3(sx * 1.32, 1.02, -0.55)), body.darkened(0.2))
		for wz: float in [-1.4, 1.4]:
			var wxf := xf * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(sx * 1.2, 0.32, wz))
			m._scyl("flat", 0.32, 0.32, 0.24, wxf, Color(0.03, 0.03, 0.03), 12)
			m._scyl("metal", 0.17, 0.17, 0.26, wxf, Color(0.55, 0.55, 0.56), 8)
	m._sbox("flat", Vector3(1.8, 0.03, 4.4), xf * Transform3D(Basis(), Vector3(0, 0.33, 0)), dark)   # rocker shadow line


func _build_lot_props() -> void:
	# Loose carts: one rolled off by the dumpster, one tipped over at the front-left of the lot.
	_cart(Vector3(7.75, 0, -1.75), 2.2)
	obstacles.append(footprint(Vector2(7.75, -1.75), Vector2(0.42, 0.42), "THE SHOPPING CART", "Shopping Cart Crash", 200, "metal_hit"))
	_cart(Vector3(-5.6, 0, 4.45), 0.9, true)
	obstacles.append(footprint(Vector2(-5.6, 4.45), Vector2(0.45, 0.45), "THE SHOPPING CART", "Shopping Cart Crash", 200, "metal_hit"))
	# Bench on the street-side sidewalk (camera side, low).
	var bp := Vector3(3.6, WALK_Y, 6.95)
	for s: float in [-0.7, 0.7]:
		m._bx("block", Vector3(0.14, 0.44, 0.45), bp + Vector3(s, 0.22, 0), Color(0.6, 0.58, 0.54))
	for k in 3:
		m._bx("wood", Vector3(1.7, 0.04, 0.12), bp + Vector3(0, 0.46, -0.15 + k * 0.14), Color(0.55, 0.42, 0.3))
	for k in 2:
		m._bx("wood", Vector3(1.7, 0.1, 0.035), bp + Vector3(0, 0.62 + k * 0.15, 0.24), Color(0.5, 0.38, 0.28))
	# Front-left parking lot light pole (the key light) and the back-right one (sodium).
	for pole: Array in [[Vector3(-7.7, WALK_Y, 6.3), Vector3(-6.85, 7.4, 5.85)], [Vector3(8.9, WALK_Y, -5.6), Vector3(8.05, 7.0, -5.0)]]:
		var base: Vector3 = pole[0]
		var head: Vector3 = pole[1]
		var ph := head.y + 0.2
		m._cy("block", 0.32, 0.28, 0.6, base + Vector3(0, 0.3, 0), Color(0.6, 0.58, 0.54), 10)
		m._cy("metal", 0.1, 0.08, ph, base + Vector3(0, ph * 0.5, 0), Color(0.36, 0.36, 0.35), 8)
		m._beam("metal", Vector3(base.x, head.y + 0.15, base.z), head + Vector3(0, 0.15, 0), 0.08, Color(0.36, 0.36, 0.35))
		m._bx("metal", Vector3(0.42, 0.22, 0.7), head + Vector3(0, 0.05, 0), Color(0.22, 0.22, 0.23), atan2(head.x - base.x, head.z - base.z))
		m._bx("glow", Vector3(0.32, 0.03, 0.58), head - Vector3(0, 0.07, 0), Color(1.0, 0.86, 0.6), atan2(head.x - base.x, head.z - base.z))


func _build_surroundings() -> void:
	# Low block walls along the lot's sides with chain-link on top; buildings across the side street
	# (left) and beyond the alley (right).
	var block := Color(0.6, 0.58, 0.54)
	for s: float in [-1.0, 1.0]:
		m._bx("block", Vector3(0.25, 0.8, 12.4), Vector3(s * 10.3, 0.4, -0.2), block)
		m._bx("block", Vector3(0.32, 0.06, 12.45), Vector3(s * 10.3, 0.83, -0.2), block.lightened(0.1))
	var cl: StandardMaterial3D = m._tex_mat(_make_chainlink_texture(), true)
	cl.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vquad(cl, Vector3(-10.3, 0.86, -6.4), Vector3(-10.3, 0.86, 6.0), 1.1, Vector2(12.4 / 0.3, 1.1 / 0.3))
	_vquad(cl, Vector3(10.3, 0.86, -6.4), Vector3(10.3, 0.86, 6.0), 1.1, Vector2(12.4 / 0.3, 1.1 / 0.3))
	_vquad(cl, Vector3(10.0, 0.0, -6.6), Vector3(13.5, 0.0, -6.6), 2.2, Vector2(3.5 / 0.3, 2.2 / 0.3))   # alley gate
	for s: float in [-1.0, 1.0]:
		for z: float in [-6.4, -2.3, 1.8, 6.0]:
			m._cy("metal", 0.03, 0.03, 1.2, Vector3(s * 10.3, 1.44, z), Color(0.5, 0.5, 0.5), 6)
	# Left: a two-storey apartment block across the side street, some windows lit.
	var ap := Vector3(-17.0, 0, -6.0)
	m._bx("brick", Vector3(8.0, 7.2, 12.0), ap + Vector3(0, 3.6, 0), Color(0.6, 0.55, 0.55), 0.0, 0.85)
	m._bx("block", Vector3(8.3, 0.2, 12.3), ap + Vector3(0, 7.3, 0), Color(0.4, 0.38, 0.36))
	var lit: Array[Color] = [Color(0.92, 0.68, 0.36), Color(0.05, 0.05, 0.07), Color(0.4, 0.5, 0.85), Color(0.05, 0.05, 0.07), Color(0.85, 0.6, 0.3), Color(0.06, 0.06, 0.08)]
	var i := 0
	for fy: float in [2.0, 5.2]:
		for wz: float in [-4.0, -1.5, 1.0, 3.5]:
			m._bx("glow", Vector3(0.05, 1.1, 0.9), Vector3(ap.x + 4.02, fy, ap.z + wz), lit[i % lit.size()])
			i += 1
	# Right: a low laundromat beyond the alley with a dim teal sign.
	var lp := Vector3(17.5, 0, -9.0)
	m._bx("siding", Vector3(7.0, 4.0, 8.0), lp + Vector3(0, 2.0, 0), Color(0.5, 0.52, 0.5), 0.0, 0.6)
	m._bx("glow", Vector3(0.05, 1.4, 3.0), Vector3(lp.x - 3.52, 1.4, lp.z + 1.5), Color(0.45, 0.6, 0.58))
	m._bx("glow", Vector3(0.05, 0.5, 3.4), Vector3(lp.x - 3.52, 3.2, lp.z + 1.5), Color(0.1, 0.55, 0.5))
	# Dark tree line / far buildings behind everything.
	for t: Vector3 in [Vector3(-12.5, 0, -15.0), Vector3(-4.0, 0, -18.5), Vector3(5.5, 0, -19.0), Vector3(13.0, 0, -16.0), Vector3(-13.5, 0, 9.0), Vector3(14.0, 0, 8.0)]:
		var th := randf_range(6.0, 9.0)
		m._cy("flat", 0.25, 0.2, 1.6, t + Vector3(0, 0.8, 0), Color(0.12, 0.09, 0.06), 6)
		m._cy("flat", 2.4, 0.0, th * 0.6, t + Vector3(0, 1.4 + th * 0.3, 0), Color(0.04, 0.07, 0.05), 8)
		m._cy("flat", 1.8, 0.0, th * 0.5, t + Vector3(0, 1.4 + th * 0.65, 0), Color(0.05, 0.08, 0.06), 8)
	for b: Array in [[Vector3(-2.0, 0, -22.0), Vector3(10.0, 9.0, 4.0)], [Vector3(10.0, 0, -24.0), Vector3(8.0, 12.0, 4.0)], [Vector3(-12.0, 0, -24.0), Vector3(8.0, 7.0, 4.0)]]:
		var bpos: Vector3 = b[0]
		var bsz: Vector3 = b[1]
		m._bx("flat", bsz, bpos + Vector3(0, bsz.y * 0.5, 0), Color(0.09, 0.09, 0.11))
		for k in 5:
			m._bx("glow", Vector3(0.7, 0.9, 0.05), bpos + Vector3(randf_range(-bsz.x * 0.4, bsz.x * 0.4), randf_range(2.0, bsz.y - 1.0), bsz.z * 0.5 + 0.03), [Color(0.7, 0.52, 0.3), Color(0.3, 0.38, 0.6)][k % 2])


# ---------------------------------------------------------------- lights

func _build_lights() -> void:
	# Key: the front-left lot light (warm white, real shadow via main), aimed into the middle of the lot.
	var kp := Vector3(-6.85, 7.25, 5.85)
	var kaim := Vector3(-0.6, 0.0, -0.6)
	var key := SpotLight3D.new()
	key.transform = Transform3D(Basis.looking_at(kaim - kp), kp)
	key.spot_angle = 48.0
	key.spot_angle_attenuation = 1.3
	key.spot_range = 22.0
	key.spot_attenuation = 0.5
	key.light_energy = 4.3
	key.light_specular = 0.8
	key.light_color = Color(1.0, 0.88, 0.7)
	key.shadow_enabled = false
	add_child(key)
	key_light = key
	_beam_cone(kp - Vector3(0, 0.1, 0), kaim, 8.5, 22.0, Color(1.0, 0.9, 0.72), 0.035)
	# Back-right sodium lot light: orange pool over the dumpster half; its cone reads against the brick.
	var bp := Vector3(8.05, 6.85, -5.0)
	var baim := Vector3(2.2, 0.0, -0.4)
	var back := SpotLight3D.new()
	back.transform = Transform3D(Basis.looking_at(baim - bp), bp)
	back.spot_angle = 46.0
	back.spot_angle_attenuation = 1.2
	back.spot_range = 17.0
	back.spot_attenuation = 0.5
	back.light_energy = 3.3
	back.light_specular = 0.7
	back.light_color = Color(1.0, 0.7, 0.4)
	add_child(back)
	_beam_cone(bp - Vector3(0, 0.1, 0), baim, 8.0, 24.0, Color(1.0, 0.68, 0.38), 0.06)
	# Neon pink spill from the sign (it flickers with MART), fluorescent spill out of the windows,
	# the ice machine's cold glow, and a dim warm lamp over the bench side.
	_neon_light = OmniLight3D.new()
	_neon_light.position = Vector3(0.5, 3.4, -5.4)
	_neon_light.omni_range = 7.0
	_neon_light.light_energy = _neon_energy
	_neon_light.light_color = Color(1.0, 0.35, 0.58)
	_neon_light.omni_attenuation = 1.4
	add_child(_neon_light)
	var win := OmniLight3D.new()
	win.position = Vector3(0.5, 1.7, -5.3)
	win.omni_range = 7.5
	win.light_energy = 1.25
	win.light_color = Color(0.82, 0.95, 1.0)
	win.omni_attenuation = 1.3
	add_child(win)
	var ice := OmniLight3D.new()
	ice.position = Vector3(-4.7, 1.9, -5.3)
	ice.omni_range = 3.2
	ice.light_energy = 0.6
	ice.light_color = Color(0.6, 0.8, 1.0)
	ice.omni_attenuation = 1.5
	add_child(ice)
	var street := OmniLight3D.new()
	street.position = Vector3(5.5, 3.0, 7.0)
	street.omni_range = 6.5
	street.light_energy = 0.55
	street.light_color = Color(1.0, 0.78, 0.5)
	street.omni_attenuation = 1.4
	add_child(street)


func _build_grime() -> void:
	m._grime_wall(Vector3(-9.8, WALK_Y, WALL_Z + 0.01), Vector3(9.8, WALK_Y, WALL_Z + 0.01), Vector3.BACK, 0.9, 0.5)
	m._grime_wall(Vector3(-10.0, 0.0, CURB_Z), Vector3(10.0, 0.0, CURB_Z), Vector3.BACK, 0.14, 0.45, 0.4, 0.4)
	m._grime_wall(Vector3(7.08, 0.0, -4.35), Vector3(7.08, 0.0, -2.45), Vector3.LEFT, 0.6, 0.4)   # dumpster front
	for s: float in [-1.0, 1.0]:
		m._grime_wall(Vector3(s * 10.17, 0.0, -6.4), Vector3(s * 10.17, 0.0, 6.0), Vector3(-s, 0, 0), 0.5, 0.4, 0.5, 0.35)
	m._grime_wall(Vector3(-4.05, WALK_Y, -5.66), Vector3(-5.35, WALK_Y, -5.66), Vector3.BACK, 0.3, 0.3)   # ice machine foot
	m._flush_grime()


func setup_environment(env: Environment) -> void:
	# Sodium-orange haze over the lot, a touch more ambient so the edges of the lot stay readable.
	env.ambient_light_color = Color(0.5, 0.46, 0.52)
	env.ambient_light_energy = 0.38
	env.fog_light_color = Color(0.13, 0.09, 0.08)
	env.fog_density = 0.012
	if main != null and main.moon != null:
		main.moon.light_energy = 0.42


# ---------------------------------------------------------------- the buzzing sign

func _process(delta: float) -> void:
	if _mart_label == null or _neon_light == null:
		return
	if _neon_flick > 0.0:
		_neon_flick -= delta
		var on := randf() < 0.4 or _neon_flick <= 0.0
		_mart_label.modulate = Color(0.82, 0.96, 1.0, 1.0 if on else 0.15)
		_mart_label.outline_modulate = Color(0.1, 0.55, 1.0, 0.55 if on else 0.05)
		_neon_light.light_energy = _neon_energy * (1.0 if on else 0.75)
		return
	_neon_wait -= delta
	if _neon_wait <= 0.0:
		_neon_flick = randf_range(0.2, 0.7)
		_neon_wait = randf_range(1.5, 5.0)


# ---------------------------------------------------------------- the crowd

func _fan(p: Vector3, person: String, lit := 0.55, bob := 1.0) -> void:
	crowd_spots.append({"pos": p, "person": person, "lit": lit, "bob": bob})


func _build_crowd_spots() -> void:
	# ~34 regulars hanging around Rudy's fight night. Nobody in the fighting area (x -7..7, z -5..5),
	# on a perch top or in a perch's climb path (ice machine x -5.4..-4.0, awning crates x 1.0..2.6).
	crowd_spots = []
	var y := WALK_Y
	# Store sidewalk: in front of the newspaper boxes, the windows and by the pay phone.
	_fan(Vector3(-9.4, y, -5.7), "stand", 0.5)
	_fan(Vector3(-8.0, y, -5.6), "hoodie", 0.5)
	_fan(Vector3(-6.6, y, -5.7), "jacket", 0.55)
	_fan(Vector3(-5.8, y, -6.25), "girl", 0.6)
	_fan(Vector3(-3.25, y, -5.6), "flannel", 0.65)
	_fan(Vector3(-2.25, y, -5.95), "stand", 0.65)
	_fan(Vector3(-1.15, y, -5.6), "cheer", 0.65)
	_fan(Vector3(-0.35, y, -6.25), "stand", 0.6)
	_fan(Vector3(3.0, y, -5.65), "hoodie", 0.65)
	_fan(Vector3(4.15, y, -6.05), "girl", 0.62)
	_fan(Vector3(5.75, y, -6.2), "stand", 0.55)    # on the pay phone
	_fan(Vector3(6.8, y, -5.7), "filmer", 0.55)
	_fan(Vector3(8.1, y, -5.85), "stand", 0.5)
	# Up on the awning: two sitting on its front edge, one standing at the far end.
	_fan(Vector3(-2.9, 2.22, -5.02), "sit", 0.6, 1.2)
	_fan(Vector3(-1.75, 2.22, -5.02), "sit_cup", 0.6, 1.2)
	_fan(Vector3(3.95, 2.75, -6.15), "cheer", 0.6, 1.3)
	# On the store roof, filming.
	_fan(Vector3(-6.4, 4.57, -7.1), "filmer", 0.4, 1.4)
	# The sedan (roof = perch): one on the hood, one on the trunk.
	_fan(Vector3(-7.05, 0.42, 2.25), "sit_cup", 0.55)
	_fan(Vector3(-7.05, 0.42, -0.95), "sit", 0.55)
	# The station wagon (hood = perch): one on the tailgate, one standing on the roof.
	_fan(Vector3(7.1, 0.42, -0.5), "sit", 0.55)
	_fan(Vector3(8.1, 1.48, 0.55), "cheer", 0.55, 1.3)
	# Sitting on the cart corral rail, leaning by the dumpster.
	_fan(Vector3(-8.35, 0.39, -3.1), "sit", 0.5)
	_fan(Vector3(9.05, 0.0, -2.2), "stand", 0.5)
	# Behind the parked cars, along the side walls.
	_fan(Vector3(-9.5, 0.0, -0.6), "stand", 0.45)
	_fan(Vector3(-9.6, 0.0, 2.4), "hoodie", 0.45)
	_fan(Vector3(9.5, 0.0, 0.2), "stand", 0.45)
	_fan(Vector3(9.6, 0.0, 3.4), "girl", 0.45)
	# Street side (camera side): two on the bench, a few standing at the corners (kept out of the shot).
	_fan(Vector3(3.2, y + 0.0, 6.78), "sit", 0.55)
	_fan(Vector3(4.05, y + 0.0, 6.78), "sit_cup", 0.55)
	_fan(Vector3(-6.4, y, 6.6), "stand", 0.5)
	_fan(Vector3(-5.3, y, 7.2), "flannel", 0.5)
	_fan(Vector3(6.4, y, 6.5), "jacket", 0.5)
	_fan(Vector3(7.5, y, 6.95), "stand", 0.5)

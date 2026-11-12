extends "res://scripts/levels/level_base.gd"
## MOM'S KITCHEN (level id "kitchen"): the Magruder kitchen + the open living room by day, built
## like a TV sitcom set: walls on three sides (back wall at -z, side walls at +-x), the camera side
## (+z) open, no ceiling. Kitchen on the left (tile floor), living room on the right (wood floor).
## Story ch6 "Page Nine": the bills on the fridge (PAST DUE), the dent the shape of a grown man,
## chili in the blue dish, the cereal-box KITCHEN CHAMPIONSHIP belt nine-year-old Theodore made.
## Fighting area x -5.5..5.5, z -4..4 (tight indoor brawl); ground y 0; everything local to ring_root.
##
## Perches: the kitchen table (0.78), the couch arm (0.74), the counter (0.92), the fridge top
## (1.8, kind "roof": the biggest dive in the house).
## Uses main's merged-geometry helpers (see backyard.gd's header) plus a few batches of its own
## with level-made textures (tile, oak, wallpaper, subway tile, plaid), flushed by _flush_custom().

const WALL_X := 6.4          # inner faces of the side walls
const WALL_Z := -5.0         # inner face of the back wall
const WALL_H := 3.4
const SPLIT_X := -0.3        # kitchen tile | living-room wood
const FRONT_Z := 5.6         # front lip of the set floor
const FRIDGE := Vector3(-5.9, 0.0, -4.62)   # fridge centre (floor), 0.84 x 1.8 x 0.74
const COUNTER_X0 := -5.4
const COUNTER_X1 := -1.6
const COUNTER_TOP := 0.92
const TABLE_C := Vector3(-3.3, 0.0, 0.3)
const COUCH_C := Vector3(2.0, 0.0, 4.55)
const STAIR_X0 := 3.9        # opening in the back wall to the stair hall
const STAIR_X1 := 5.1

var m = null   # main.gd (helpers)
var _custom: Dictionary = {}   # batch key -> material (level-made textures)
var _oak_tex: ImageTexture
var _tile_tex: ImageTexture


func _init() -> void:
	display_name = "MOM'S KITCHEN"
	description = "Indoors, tight and breakable: the kitchen table, the fridge, the couch. Mom will find out."
	time_of_day = "day"
	preview_color = Color(0.62, 0.5, 0.34)
	yard_bounds = Rect2(-5.5, -4.0, 11.0, 8.0)
	cam_clamp = Rect2(-3.6, -3.0, 7.2, 5.6)
	cam_height = 2.7
	cam_back = 5.3
	default_surface = "wood"
	surfaces = [{"rect": Rect2(-8.0, -9.0, SPLIT_X + 8.0, 18.0), "kind": "tile"}]
	spawn_p1 = Vector3(-1.4, 0.0, 0.9)
	spawn_p2 = Vector3(1.6, 0.0, 0.1)


func build(main_node: Node) -> void:
	super(main_node)
	m = main_node
	perches.clear()
	obstacles.clear()
	_make_custom_mats()
	_build_floor()
	_build_walls()
	_build_kitchen()
	_build_fridge()
	_build_table()
	_build_living_room()
	_build_stairs()
	_build_decor()
	_build_lights()
	_build_grime()
	for key: String in _custom:
		_flush_custom(key)
	m._flush_batches()
	_build_labels()
	_build_crowd_spots()
	item_spawns = [
		{"kind": "chair", "pos": Vector3(-1.1, 0.0, 2.7), "yaw": 0.5},
		{"kind": "chair", "pos": Vector3(4.4, 0.0, -3.3), "yaw": -0.6},
		{"kind": "table", "pos": Vector3(-5.3, 0.0, 2.6), "yaw": PI * 0.5},   # folded against the left wall, top facing +x
		{"kind": "trash_can", "pos": Vector3(-1.2, 0.0, -3.6), "yaw": 0.0},  # the kitchen bin at the end of the counter
		{"kind": "plank", "pos": Vector3(5.0, 0.0, 0.9), "yaw": 1.3},       # the curtain-rod board that came down
	]


# ---- level-made textures + their batches

func _make_custom_mats() -> void:
	var oak := _tex_oak()
	_custom = {
		"k_tile": _batch_tex_mat(_tex_tile(), 0.6),
		"k_oak": _batch_tex_mat(oak, 0.65),
		"k_paper": _batch_tex_mat(_tex_wallpaper(), 0.95),
		"k_subway": _batch_tex_mat(_tex_subway(), 0.4),
		"k_plaid": _batch_tex_mat(_tex_plaid(), 1.0),
	}
	_oak_tex = oak



func _batch_tex_mat(tex: Texture2D, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.roughness = rough
	return mat


func _flush_custom(key: String) -> void:
	if not m._batches.has(key):
		return
	var st: SurfaceTool = m._batches[key]
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _custom[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	m._batches.erase(key)


func _tex_tile() -> ImageTexture:
	# Old kitchen linoleum: 25 cm cream / brick-red checker (4 x 4 per metre), mottled, scuffed,
	# grey grout lines with grime in them, a few chips and a coffee ring.
	var n := 256
	var mot: Image = m._noise_img(n, n, 0.03, 3)
	var grit: Image = m._noise_img(n, n, 0.45, 1)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var cream := Color(0.74, 0.7, 0.6)
	var red := Color(0.5, 0.3, 0.24)
	for y in n:
		for x in n:
			var t := 64
			var chk := ((x / t) + (y / t)) % 2
			var mo := mot.get_pixel(x, y).r
			var g := grit.get_pixel(x, y).r
			var c := cream if chk == 0 else red
			c = c.darkened((mo - 0.5) * 0.3 + (g - 0.5) * 0.12)
			var lx := x % t
			var ly := y % t
			var d := mini(mini(lx, ly), mini(t - 1 - lx, t - 1 - ly))
			if d < 2:
				c = Color(0.34, 0.31, 0.26).darkened((mo - 0.5) * 0.4)
			elif d < 4:
				c = c.darkened(0.06)
			if randf() < 0.03:
				c = c.darkened(0.12)
			img.set_pixel(x, y, c)
	for i in 26:  # shoe scuffs
		var a := Vector2(randf() * n, randf() * n)
		var ang := randf() * TAU
		m._line_px(img, a, a + Vector2(cos(ang), sin(ang)) * randf_range(5.0, 20.0), Color(0.1, 0.09, 0.08), randf_range(0.15, 0.35))
	for i in 5:  # chips
		m._soft_dot(img, randf() * n, randf() * n, randf_range(1.5, 3.0), randf_range(1.0, 2.5), Color(0.2, 0.18, 0.15), 0.6, 1.0)
	var cr := Vector2(n * 0.62, n * 0.3)
	for k in 40:  # coffee ring
		var a2 := TAU * k / 40.0
		m._soft_dot(img, cr.x + cos(a2) * 9.0, cr.y + sin(a2) * 9.0, 1.4, 1.4, Color(0.3, 0.18, 0.08), 0.25, 1.0)
	_tile_tex = m._sharp_tex(img)
	return _tile_tex


func _tex_oak() -> ImageTexture:
	# Honey-oak boards, 256 px per metre: eight planks per metre running along u, each with its
	# own tone, staggered end joints, flowing grain, worn varnish and scuffs.
	var n := 256
	var warp: Image = m._noise_img(n, n, 0.02, 3)
	var fine: Image = m._noise_img(n, n, 0.35, 1)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var tones: Array[float] = []
	var joints: Array[int] = []
	for r in 8:
		tones.append(randf_range(-0.09, 0.09))
		joints.append(randi() % n)
	for y in n:
		var row := y / 32
		var ly := y % 32
		for x in n:
			var w := warp.get_pixel(x, y).r
			var f := fine.get_pixel((x / 5) % n, y).r
			var ph := (y + w * 26.0) * 0.9
			var grain := 0.5 + 0.5 * sin(ph) + (f - 0.5) * 0.5
			var c := Color(0.56, 0.41, 0.28).darkened(grain * 0.16 - 0.04 + tones[row])
			c = c.lerp(Color(0.48, 0.3, 0.16), smoothstep(0.62, 0.85, w) * 0.4)
			if ly == 0 or ly == 31:
				c = c.darkened(0.45)
			elif ly == 1:
				c = c.lightened(0.06)
			var jx := absi(x - joints[row])
			if jx < 1 or jx > n - 1:
				c = c.darkened(0.4)
			img.set_pixel(x, y, c)
	for i in 30:
		var a := Vector2(randf() * n, randf() * n)
		m._line_px(img, a, a + Vector2(randf_range(6.0, 22.0), randf_range(-2.0, 2.0)), Color(0.2, 0.13, 0.08), randf_range(0.12, 0.3))
	for i in 3:
		var k := Vector2(randf() * n, randf() * n)
		m._soft_dot(img, k.x, k.y, 5.0, 2.5, Color(0.3, 0.18, 0.1), 0.5, 2.0)
	return m._sharp_tex(img)


func _tex_wallpaper() -> ImageTexture:
	# Faded 70s wallpaper, 256 px per metre: cream with soft vertical stripes and little rose sprigs,
	# yellowed in blotches, darker toward the floor (tinted per wall: paler in the kitchen).
	var n := 256
	var blot: Image = m._noise_img(n, n, 0.015, 3)
	var fine: Image = m._noise_img(n, n, 0.4, 1)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var b := blot.get_pixel(x, y).r
			var f := fine.get_pixel(x, y).r
			var c := Color(0.86, 0.8, 0.64)
			var sx := x % 64
			if sx < 3 or (sx > 28 and sx < 36):
				c = c.darkened(0.07)
			c = c.darkened((f - 0.5) * 0.05)
			c = c.lerp(Color(0.66, 0.55, 0.36), smoothstep(0.58, 0.85, b) * 0.35)
			img.set_pixel(x, y, c)
	for gy in 4:
		for gx in 4:
			var cx := gx * 64 + 16.0 + (32.0 if gy % 2 == 1 else 0.0)
			var cy := gy * 64 + 32.0
			cx = fmod(cx, float(n))
			m._soft_dot(img, cx - 3.0, cy + 4.0, 3.0, 1.6, Color(0.42, 0.52, 0.34), 0.7, 1.0)
			m._soft_dot(img, cx + 3.0, cy + 5.0, 3.0, 1.6, Color(0.42, 0.52, 0.34), 0.7, 1.0)
			m._soft_dot(img, cx, cy, 4.0, 3.6, Color(0.72, 0.44, 0.42), 0.8, 1.0)
			m._soft_dot(img, cx - 0.6, cy - 0.6, 1.8, 1.6, Color(0.55, 0.28, 0.28), 0.8, 1.0)
	return m._sharp_tex(img)


func _tex_subway() -> ImageTexture:
	# Glazed backsplash tile (128 px per metre): 4 x 8 offset bricks, per-tile tone, grout.
	var n := 128
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var tones: Array[float] = []
	for i in 64:
		tones.append(randf_range(-0.05, 0.04))
	for y in n:
		var row := y / 16
		var ly := y % 16
		for x in n:
			var xo := (x + (16 if row % 2 == 1 else 0)) % n
			var col := xo / 32
			var lx := xo % 32
			var c := Color(0.86, 0.85, 0.78).darkened(tones[(row * 4 + col) % 64])
			if ly < 1 or lx < 1:
				c = Color(0.55, 0.52, 0.46)
			elif ly < 3:
				c = c.lightened(0.08)
			elif ly > 13:
				c = c.darkened(0.06)
			img.set_pixel(x, y, c)
	return m._sharp_tex(img)


func _tex_plaid() -> ImageTexture:
	# Worn brown/orange plaid upholstery (128 px per metre) with a fabric weave.
	var n := 128
	var nz: Image = m._noise_img(n, n, 0.08, 2)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := Color(0.52, 0.38, 0.25)
			var bx := x % 32
			var by := y % 32
			if bx < 8:
				c = c.lerp(Color(0.72, 0.48, 0.22), 0.55)
			if by < 8:
				c = c.lerp(Color(0.72, 0.48, 0.22), 0.55)
			if bx == 14 or by == 14:
				c = c.lerp(Color(0.85, 0.78, 0.6), 0.6)
			if (bx > 20 and bx < 26) or (by > 20 and by < 26):
				c = c.darkened(0.25)
			c = c.darkened(0.05 * float((x + y) % 2) + (nz.get_pixel(x, y).r - 0.5) * 0.18)
			img.set_pixel(x, y, c)
	return m._sharp_tex(img)


# ---- floor, walls

func _build_floor() -> void:
	var tm: StandardMaterial3D = m._tex_mat(_tile_tex)
	tm.roughness = 0.55
	var tw := SPLIT_X + WALL_X
	var depth := FRONT_Z - WALL_Z
	m._ground_quad(Vector3(-WALL_X + tw * 0.5, 0.0, (WALL_Z + FRONT_Z) * 0.5), Vector2(tw, depth), tm, 0.0, Vector2(tw, depth))
	var wm: StandardMaterial3D = m._tex_mat(_oak_tex)
	wm.roughness = 0.6
	var ww := WALL_X - SPLIT_X
	m._ground_quad(Vector3(SPLIT_X + ww * 0.5, 0.0, (WALL_Z + FRONT_Z) * 0.5), Vector2(ww, depth), wm, 0.0, Vector2(ww, depth))
	# Brass threshold strip between tile and wood, and the dark front lip of the set.
	m._bx("metal", Vector3(0.05, 0.012, depth), Vector3(SPLIT_X, 0.006, (WALL_Z + FRONT_Z) * 0.5), Color(0.6, 0.5, 0.3))
	m._bx("flat", Vector3(2 * WALL_X + 0.4, 0.3, 0.2), Vector3(0, -0.14, FRONT_Z + 0.1), Color(0.12, 0.1, 0.08))
	# Dark studio floor beyond the set so the edges never show the void.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.06, 0.05, 0.045)
	dark.roughness = 1.0
	m._plane(Vector2(60, 60), Vector3(0, -0.3, 0), dark)
	# Braided oval-ish rug in front of the couch (a flat rounded slab).
	m._scyl("k_plaid", 1.35, 1.35, 0.012, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.72)), Vector3(2.3, 0.008, 2.75)), Color(0.75, 0.5, 0.45), 20)
	m._scyl("flat", 1.2, 1.2, 0.014, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.7)), Vector3(2.3, 0.009, 2.75)), Color(0.38, 0.24, 0.2), 20)
	m._scyl("k_plaid", 1.0, 1.0, 0.016, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.68)), Vector3(2.3, 0.01, 2.75)), Color(0.85, 0.7, 0.55), 20)


func _wall(key: String, x0: float, x1: float, y0: float, y1: float, col: Color) -> void:
	# A slab of the back wall (inner face at WALL_Z).
	m._bx(key, Vector3(x1 - x0, y1 - y0, 0.16), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, WALL_Z - 0.08), col)


func _side_wall(key: String, sx: float, z0: float, z1: float, y0: float, y1: float, col: Color) -> void:
	m._bx(key, Vector3(0.16, y1 - y0, z1 - z0), Vector3(sx * (WALL_X + 0.08), (y0 + y1) * 0.5, (z0 + z1) * 0.5), col)


func _build_walls() -> void:
	var kpaint := Color(0.86, 0.84, 0.74)     # kitchen: pale buttery wallpaper
	var lpaper := Color(0.8, 0.74, 0.68)    # living room: the rose wallpaper
	var trim := Color(0.95, 0.9, 0.82)
	# Back wall: kitchen window x -3.2..-2.0 (y 1.45..2.2), stair opening x 3.9..5.1 (y 0..2.25).
	_wall("k_paper", -WALL_X - 0.16, -3.2, 0.0, WALL_H, kpaint)
	_wall("k_paper", -3.2, -2.0, 0.0, 1.45, kpaint)
	_wall("k_paper", -3.2, -2.0, 2.2, WALL_H, kpaint)
	_wall("k_paper", -2.0, SPLIT_X, 0.0, WALL_H, kpaint)
	_wall("k_paper", SPLIT_X, STAIR_X0, 0.0, WALL_H, lpaper)
	_wall("k_paper", STAIR_X0, STAIR_X1, 2.25, WALL_H, lpaper)
	_wall("k_paper", STAIR_X1, WALL_X + 0.16, 0.0, WALL_H, lpaper)
	# Left wall (kitchen) with the back-hall doorway z 0.4..1.4; right wall with the big window z -2.9..-0.9.
	var zf := 5.0
	_side_wall("k_paper", -1.0, WALL_Z - 0.16, 0.4, 0.0, WALL_H, kpaint)
	_side_wall("k_paper", -1.0, 0.4, 1.4, 2.1, WALL_H, kpaint)
	_side_wall("k_paper", -1.0, 1.4, zf, 0.0, WALL_H, kpaint)
	_side_wall("k_paper", 1.0, WALL_Z - 0.16, -2.9, 0.0, WALL_H, lpaper)
	_side_wall("k_paper", 1.0, -2.9, -0.9, 0.0, 0.85, lpaper)
	_side_wall("k_paper", 1.0, -2.9, -0.9, 2.35, WALL_H, lpaper)
	_side_wall("k_paper", 1.0, -0.9, zf, 0.0, WALL_H, lpaper)
	# Cut edges of the set walls (cutaway) + the top cap: raw dark plywood.
	var raw := Color(0.16, 0.13, 0.1)
	for sx: float in [-1.0, 1.0]:
		m._bx("flat", Vector3(0.18, WALL_H, 0.02), Vector3(sx * (WALL_X + 0.08), WALL_H * 0.5, zf + 0.01), raw)
		m._bx("flat", Vector3(0.18, 0.04, zf - WALL_Z + 0.2), Vector3(sx * (WALL_X + 0.08), WALL_H + 0.02, (zf + WALL_Z) * 0.5 - 0.08), raw)
	m._bx("flat", Vector3(2 * WALL_X + 0.36, 0.04, 0.18), Vector3(0, WALL_H + 0.02, WALL_Z - 0.08), raw)
	# Living room: oak wainscot + chair rail; everywhere: baseboards and crown molding.
	m._bx("k_oak", Vector3(STAIR_X0 - SPLIT_X, 0.9, 0.025), Vector3((SPLIT_X + STAIR_X0) * 0.5, 0.45, WALL_Z + 0.012), Color(0.85, 0.72, 0.6))
	m._bx("k_oak", Vector3(WALL_X - STAIR_X1, 0.9, 0.025), Vector3((STAIR_X1 + WALL_X) * 0.5, 0.45, WALL_Z + 0.012), Color(0.85, 0.72, 0.6))
	for seg: Array in [[WALL_Z, -2.9], [-0.9, zf]]:
		var z0: float = seg[0]
		var z1: float = seg[1]
		m._bx("k_oak", Vector3(0.025, 0.9, z1 - z0), Vector3(WALL_X - 0.012, 0.45, (z0 + z1) * 0.5), Color(0.85, 0.72, 0.6))
		m._bx("k_oak", Vector3(0.05, 0.06, z1 - z0), Vector3(WALL_X - 0.03, 0.92, (z0 + z1) * 0.5), trim.darkened(0.25))
	for seg2: Array in [[SPLIT_X, STAIR_X0], [STAIR_X1, WALL_X]]:
		var x0: float = seg2[0]
		var x1: float = seg2[1]
		m._bx("k_oak", Vector3(x1 - x0, 0.06, 0.05), Vector3((x0 + x1) * 0.5, 0.92, WALL_Z + 0.03), trim.darkened(0.25))
	# Baseboards
	m._bx("flat", Vector3(2 * WALL_X, 0.12, 0.03), Vector3(0, 0.06, WALL_Z + 0.015), trim)
	for sx2: float in [-1.0, 1.0]:
		m._bx("flat", Vector3(0.03, 0.12, zf - WALL_Z), Vector3(sx2 * (WALL_X - 0.015), 0.06, (zf + WALL_Z) * 0.5), trim)
		m._bx("flat", Vector3(0.08, 0.12, zf - WALL_Z), Vector3(sx2 * (WALL_X - 0.04), WALL_H - 0.08, (zf + WALL_Z) * 0.5), trim)
	m._bx("flat", Vector3(2 * WALL_X, 0.12, 0.08), Vector3(0, WALL_H - 0.08, WALL_Z + 0.04), trim)
	# Pilaster where the kitchen wall paper meets the living room paper.
	m._bx("flat", Vector3(0.14, WALL_H, 0.06), Vector3(SPLIT_X, WALL_H * 0.5, WALL_Z + 0.03), trim.darkened(0.08))

	# Back-hall doorway (left wall): casing, the dim laundry hall behind, back door with a sunny window.
	var hx := -WALL_X - 0.16
	for z: float in [0.4, 1.4]:
		m._bx("flat", Vector3(0.2, 2.1, 0.08), Vector3(-WALL_X - 0.08, 1.05, z), trim)
	m._bx("flat", Vector3(0.2, 0.1, 1.16), Vector3(-WALL_X - 0.08, 2.15, 0.9), trim)
	m._bx("flat", Vector3(1.6, 0.02, 1.4), Vector3(hx - 0.8, 0.0, 0.9), Color(0.4, 0.36, 0.3))
	m._bx("k_paper", Vector3(1.6, WALL_H, 0.12), Vector3(hx - 0.8, WALL_H * 0.5, 0.2 - 0.06), Color(0.7, 0.66, 0.56))
	m._bx("k_paper", Vector3(1.6, WALL_H, 0.12), Vector3(hx - 0.8, WALL_H * 0.5, 1.6 + 0.06), Color(0.7, 0.66, 0.56))
	m._bx("flat", Vector3(0.1, WALL_H, 1.6), Vector3(hx - 1.6, WALL_H * 0.5, 0.9), Color(0.55, 0.5, 0.42))
	m._bx("flat", Vector3(0.05, 2.0, 0.85), Vector3(hx - 1.54, 1.0, 0.9), Color(0.42, 0.26, 0.18))     # back door
	m._bx("glow", Vector3(0.05, 0.6, 0.55), Vector3(hx - 1.5, 1.5, 0.9), Color(0.95, 0.93, 0.82))     # its sunny window
	m._bx("metal", Vector3(0.6, 0.85, 0.6), Vector3(hx - 0.5, 0.43, 0.55), Color(0.85, 0.85, 0.82))     # washer
	m._cy("flat", 0.2, 0.2, 0.02, Vector3(hx - 0.5, 0.86, 0.55), Color(0.3, 0.3, 0.32), 12)
	# Mom's white work clogs by the door.
	for k in 2:
		m._bx("flat", Vector3(0.1, 0.08, 0.26), Vector3(-WALL_X + 0.25 + k * 0.13, 0.04, 1.75), Color(0.92, 0.92, 0.9), 0.15 * k)

	# Kitchen window over the sink: frame, sky + hedge + neighbour's siding outside, gingham valance.
	var wz := WALL_Z
	m._bx("flat", Vector3(1.36, 0.9, 0.2), Vector3(-2.6, 1.825, wz - 0.12), trim)
	m._bx("glow", Vector3(1.2, 0.48, 0.04), Vector3(-2.6, 1.95, wz - 0.12), Color(0.82, 0.9, 0.98))
	m._bx("glow", Vector3(1.2, 0.18, 0.04), Vector3(-2.6, 1.62, wz - 0.12), Color(0.5, 0.6, 0.36))
	m._bx("glow", Vector3(1.2, 0.08, 0.04), Vector3(-2.6, 1.5, wz - 0.12), Color(0.66, 0.62, 0.5))
	m._bx("flat", Vector3(0.04, 0.75, 0.05), Vector3(-2.6, 1.825, wz - 0.08), trim)
	m._bx("flat", Vector3(1.2, 0.04, 0.05), Vector3(-2.6, 1.85, wz - 0.08), trim)
	m._bx("flat", Vector3(1.5, 0.05, 0.16), Vector3(-2.6, 1.43, wz + 0.06), trim)     # sill
	m._bx("flat", Vector3(1.45, 0.22, 0.04), Vector3(-2.6, 2.12, wz + 0.05), Color(0.75, 0.22, 0.2))  # valance
	for k in 8:
		m._bx("flat", Vector3(0.09, 0.22, 0.045), Vector3(-3.25 + k * 0.185, 2.12, wz + 0.052), Color(0.92, 0.88, 0.82))
	m._cy("flat", 0.07, 0.05, 0.1, Vector3(-2.15, 1.51, wz + 0.07), Color(0.6, 0.32, 0.2), 8)   # potted herb
	m._cy("flat", 0.1, 0.02, 0.16, Vector3(-2.15, 1.64, wz + 0.07), Color(0.24, 0.42, 0.18), 7)

	# Living-room window (right wall): sky, the neighbour's tree, mullions, heavy curtains, sill.
	var rx := WALL_X + 0.1
	m._bx("flat", Vector3(0.22, 1.6, 2.16), Vector3(rx, 1.6, -1.9), trim)
	m._bx("glow", Vector3(0.04, 1.0, 2.0), Vector3(rx, 1.82, -1.9), Color(0.86, 0.92, 0.98))
	m._bx("glow", Vector3(0.04, 0.5, 2.0), Vector3(rx, 1.1, -1.9), Color(0.55, 0.65, 0.4))
	m._bx("glow", Vector3(0.035, 0.5, 0.7), Vector3(rx - 0.005, 1.65, -2.3), Color(0.4, 0.52, 0.3))   # the tree
	m._bx("flat", Vector3(0.05, 1.5, 0.05), Vector3(rx - 0.06, 1.6, -1.9), trim)
	m._bx("flat", Vector3(0.05, 0.05, 2.0), Vector3(rx - 0.06, 1.6, -1.9), trim)
	m._bx("flat", Vector3(0.18, 0.05, 2.3), Vector3(WALL_X - 0.05, 0.84, -1.9), trim)
	for z2: float in [-3.15, -0.65]:
		m._bx("k_plaid", Vector3(0.1, 1.9, 0.5), Vector3(WALL_X - 0.08, 1.5, z2), Color(0.85, 0.42, 0.36))
	m._bx("metal", Vector3(0.04, 0.04, 3.1), Vector3(WALL_X - 0.1, 2.48, -1.9), Color(0.6, 0.5, 0.3))   # curtain rod


func _build_kitchen() -> void:
	var cab := Color(0.82, 0.66, 0.52)
	var top := Color(0.86, 0.8, 0.62)
	var enamel := Color(0.9, 0.88, 0.82)
	var dark := Color(0.1, 0.09, 0.08)
	var ct := COUNTER_TOP
	var stove_x0 := -4.68
	var stove_x1 := -3.92
	var cz := WALL_Z + 0.3    # cabinet centre (depth 0.6)
	# Base cabinets (left of the stove, right of it), toe kick, laminate top with a chrome edge.
	for seg: Array in [[COUNTER_X0, stove_x0], [stove_x1, COUNTER_X1]]:
		var x0: float = seg[0]
		var x1: float = seg[1]
		m._bx("k_oak", Vector3(x1 - x0, ct - 0.12, 0.58), Vector3((x0 + x1) * 0.5, 0.1 + (ct - 0.12) * 0.5, cz), cab)
		m._bx("flat", Vector3(x1 - x0, 0.1, 0.52), Vector3((x0 + x1) * 0.5, 0.05, cz - 0.03), dark)
		var nd := maxi(1, int(round((x1 - x0) / 0.5)))
		for k in nd:
			var dx := x0 + (k + 0.5) * (x1 - x0) / nd
			var dw := (x1 - x0) / nd - 0.05
			m._bx("k_oak", Vector3(dw, 0.52, 0.03), Vector3(dx, 0.4, cz + 0.3), cab.lightened(0.06))
			m._bx("k_oak", Vector3(dw, 0.14, 0.03), Vector3(dx, 0.76, cz + 0.3), cab.lightened(0.06))
			m._bx("metal", Vector3(0.1, 0.02, 0.03), Vector3(dx, 0.76, cz + 0.33), Color(0.7, 0.62, 0.4))
			m._cy("metal", 0.015, 0.015, 0.03, Vector3(dx + dw * 0.35, 0.58, cz + 0.33), Color(0.7, 0.62, 0.4), 6)
		m._bx("flat", Vector3(x1 - x0 + 0.02, 0.04, 0.64), Vector3((x0 + x1) * 0.5, ct - 0.02, cz + 0.02), top)
		m._bx("metal", Vector3(x1 - x0 + 0.02, 0.04, 0.015), Vector3((x0 + x1) * 0.5, ct - 0.02, cz + 0.34), Color(0.75, 0.75, 0.74))
	# Backsplash (glazed tile) along the whole counter run.
	m._bx("k_subway", Vector3(COUNTER_X1 - COUNTER_X0, 0.52, 0.02), Vector3((COUNTER_X0 + COUNTER_X1) * 0.5, ct + 0.26, WALL_Z + 0.01), Color(1.0, 0.97, 0.9))

	# Stove: enamel body, oven door + dark window, back guard with knobs, four burners.
	var sx := (stove_x0 + stove_x1) * 0.5
	m._bx("flat", Vector3(stove_x1 - stove_x0, ct, 0.62), Vector3(sx, ct * 0.5, cz), enamel)
	m._bx("flat", Vector3(0.66, 0.5, 0.02), Vector3(sx, 0.42, cz + 0.315), enamel.darkened(0.06))
	m._bx("glow", Vector3(0.42, 0.22, 0.02), Vector3(sx, 0.47, cz + 0.322), Color(0.07, 0.06, 0.05))
	m._bx("metal", Vector3(0.5, 0.025, 0.03), Vector3(sx, 0.7, cz + 0.34), Color(0.75, 0.75, 0.74))
	m._bx("flat", Vector3(stove_x1 - stove_x0, 0.2, 0.06), Vector3(sx, ct + 0.1, WALL_Z + 0.04), enamel)
	m._bx("glow", Vector3(0.14, 0.06, 0.005), Vector3(sx, ct + 0.12, WALL_Z + 0.072), Color(0.2, 0.5, 0.3))   # clock 7:02
	for k in 4:
		m._cy("flat", 0.022, 0.022, 0.03, Vector3(stove_x0 + 0.1 + k * 0.08 + (0.3 if k > 1 else 0.0), ct + 0.1, WALL_Z + 0.08), dark, 8)
	for bx: float in [-0.18, 0.18]:
		for bz: float in [-0.14, 0.14]:
			m._cy("flat", 0.1, 0.1, 0.012, Vector3(sx + bx, ct + 0.006, cz + bz), Color(0.12, 0.12, 0.12), 12)
	# The blue dish (the chili lives there) on the front-left burner + the kettle at the back.
	m._cy("flat", 0.16, 0.14, 0.11, Vector3(sx - 0.18, ct + 0.065, cz + 0.14), Color(0.2, 0.36, 0.7), 14)
	m._cy("flat", 0.165, 0.165, 0.02, Vector3(sx - 0.18, ct + 0.13, cz + 0.14), Color(0.25, 0.42, 0.78), 14)
	m._bx("flat", Vector3(0.08, 0.03, 0.04), Vector3(sx - 0.18, ct + 0.15, cz + 0.14), Color(0.25, 0.42, 0.78))
	m._cy("metal", 0.1, 0.07, 0.16, Vector3(sx + 0.18, ct + 0.09, cz - 0.14), Color(0.75, 0.2, 0.16), 12)
	# Range hood
	m._bx("metal", Vector3(0.8, 0.18, 0.46), Vector3(sx, 1.68, WALL_Z + 0.23), Color(0.62, 0.6, 0.56))
	m._bx("flat", Vector3(0.76, 0.02, 0.4), Vector3(sx, 1.585, WALL_Z + 0.22), Color(0.25, 0.24, 0.22))
	# Upper cabinets (left of the hood, between hood and window, right of the window).
	for seg2: Array in [[COUNTER_X0, stove_x0 - 0.02], [stove_x1 + 0.02, -3.25], [-1.95, -1.0]]:
		var ux0: float = seg2[0]
		var ux1: float = seg2[1]
		m._bx("k_oak", Vector3(ux1 - ux0, 0.8, 0.34), Vector3((ux0 + ux1) * 0.5, 1.95, WALL_Z + 0.17), cab)
		var nu := maxi(1, int(round((ux1 - ux0) / 0.45)))
		for k in nu:
			var dx2 := ux0 + (k + 0.5) * (ux1 - ux0) / nu
			m._bx("k_oak", Vector3((ux1 - ux0) / nu - 0.05, 0.72, 0.03), Vector3(dx2, 1.95, WALL_Z + 0.35), cab.lightened(0.06))
			m._cy("metal", 0.015, 0.015, 0.03, Vector3(dx2 + 0.12, 1.66, WALL_Z + 0.38), Color(0.7, 0.62, 0.4), 6)
	# Sink under the window, faucet, dish rack.
	m._bx("metal", Vector3(0.66, 0.012, 0.44), Vector3(-2.6, ct + 0.004, cz + 0.02), Color(0.7, 0.7, 0.7))
	m._bx("flat", Vector3(0.56, 0.012, 0.36), Vector3(-2.6, ct + 0.008, cz + 0.02), Color(0.22, 0.22, 0.23))
	m._beam("metal", Vector3(-2.6, ct, WALL_Z + 0.08), Vector3(-2.6, ct + 0.3, WALL_Z + 0.08), 0.03, Color(0.8, 0.8, 0.8))
	m._beam("metal", Vector3(-2.6, ct + 0.3, WALL_Z + 0.08), Vector3(-2.6, ct + 0.26, WALL_Z + 0.26), 0.025, Color(0.8, 0.8, 0.8))
	m._bx("metal", Vector3(0.4, 0.14, 0.3), Vector3(-2.05, ct + 0.07, cz), Color(0.75, 0.75, 0.74))
	for k in 4:
		m._bx("flat", Vector3(0.02, 0.22, 0.2), Vector3(-2.18 + k * 0.08, ct + 0.15, cz), [Color(0.92, 0.92, 0.88), Color(0.85, 0.75, 0.4)][k % 2])
	# Microwave, toaster, paper towels, and the cereal boxes (the belt's raw material).
	m._bx("flat", Vector3(0.52, 0.3, 0.38), Vector3(-5.05, ct + 0.15, WALL_Z + 0.24), Color(0.2, 0.19, 0.18))
	m._bx("glow", Vector3(0.3, 0.2, 0.01), Vector3(-5.12, ct + 0.15, WALL_Z + 0.435), Color(0.08, 0.08, 0.07))
	m._bx("glow", Vector3(0.06, 0.03, 0.01), Vector3(-4.88, ct + 0.24, WALL_Z + 0.435), Color(0.3, 0.9, 0.4))
	m._cy("flat", 0.06, 0.06, 0.28, Vector3(-1.75, ct + 0.14, WALL_Z + 0.4), Color(0.95, 0.95, 0.92), 10)
	var cereal: Array[Color] = [Color(0.85, 0.2, 0.15), Color(0.95, 0.75, 0.15), Color(0.2, 0.45, 0.8)]
	for k in 3:
		m._bx("flat", Vector3(0.2, 0.3, 0.07), Vector3(-1.95 + k * 0.08, ct + 0.15, WALL_Z + 0.1 + k * 0.09), cereal[k], 0.1 * (k - 1))

	# The counter is a perch: the clear stretch between the stove and the sink.
	add_perch("kitchen counter", "counter", Vector3(-3.4, ct, -4.66), Vector3(-3.4, 0.0, -3.75),
		footprint(Vector2((COUNTER_X0 + COUNTER_X1) * 0.5, WALL_Z + 0.33), Vector2((COUNTER_X1 - COUNTER_X0) * 0.5, 0.34),
			"THE COUNTER", "Countertop Crash", 200, "wood_hit"))


func _build_fridge() -> void:
	# Old almond fridge in the back-left corner, freezer on top. Its top (1.8) is the highest perch.
	var f := FRIDGE
	var almond := Color(0.86, 0.82, 0.7)
	var fz := f.z + 0.37    # front face
	m._bx("flat", Vector3(0.84, 1.78, 0.74), f + Vector3(0, 0.91, 0), almond)
	m._bx("flat", Vector3(0.8, 0.06, 0.7), f + Vector3(0, 0.03, 0), Color(0.15, 0.14, 0.12))   # kick grille
	m._bx("flat", Vector3(0.82, 0.02, 0.02), Vector3(f.x, 1.22, fz + 0.005), Color(0.3, 0.28, 0.24))  # freezer seam
	for hy: Array in [[1.3, 1.6], [0.7, 1.12]]:
		var y0: float = hy[0]
		var y1: float = hy[1]
		m._bx("metal", Vector3(0.04, y1 - y0, 0.05), Vector3(f.x + 0.33, (y0 + y1) * 0.5, fz + 0.04), Color(0.75, 0.73, 0.68))
	# The dent "the exact shape of a grown man": a shallow darker body-shaped dip on the lower door.
	var dent := almond.darkened(0.12)
	var dz := fz + 0.004
	m._scyl("flat", 0.07, 0.07, 0.004, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(f.x - 0.08, 1.02, dz)), dent, 12)
	m._scyl("flat", 0.15, 0.15, 0.004, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.0, 1.6)), Vector3(f.x - 0.08, 0.72, dz)), dent, 12)
	m._beam("flat", Vector3(f.x - 0.2, 0.84, dz), Vector3(f.x - 0.3, 0.6, dz), 0.05, dent)
	m._beam("flat", Vector3(f.x + 0.04, 0.84, dz), Vector3(f.x + 0.13, 0.62, dz), 0.05, dent)
	# Bills, a school photo, a crayon drawing and magnets (the PAST DUE notice is a Label3D, _build_labels).
	var papers: Array = [[Vector3(-0.2, 1.42, 0), Vector2(0.22, 0.28), Color(0.95, 0.94, 0.9), 0.06],
		[Vector3(0.08, 1.45, 0), Vector2(0.2, 0.26), Color(0.98, 0.96, 0.86), -0.05],
		[Vector3(-0.14, 0.98, 0), Vector2(0.24, 0.3), Color(0.96, 0.95, 0.92), -0.04],
		[Vector3(0.12, 0.92, 0), Vector2(0.18, 0.22), Color(0.9, 0.85, 0.7), 0.08],
		[Vector3(-0.22, 1.72, 0), Vector2(0.16, 0.1), Color(0.95, 0.92, 0.8), 0.0]]
	for i in papers.size():
		var pp: Array = papers[i]
		var off: Vector3 = pp[0]
		var sz: Vector2 = pp[1]
		var xf := Transform3D(Basis(Vector3.BACK, pp[3]), Vector3(f.x + off.x, off.y, fz + 0.006 + i * 0.002))
		m._sbox("flat", Vector3(sz.x, sz.y, 0.004), xf, pp[2])
		m._sbox("flat", Vector3(sz.x * 0.7, 0.012, 0.004), xf * Transform3D(Basis(), Vector3(0, sz.y * 0.3, 0.002)), Color(0.35, 0.35, 0.4))
		m._sbox("flat", Vector3(sz.x * 0.6, 0.008, 0.004), xf * Transform3D(Basis(), Vector3(0, sz.y * 0.1, 0.002)), Color(0.55, 0.55, 0.58))
		m._sbox("flat", Vector3(sz.x * 0.6, 0.008, 0.004), xf * Transform3D(Basis(), Vector3(0, -sz.y * 0.05, 0.002)), Color(0.55, 0.55, 0.58))
	# The PAST DUE notice: a bigger pink sheet on the freezer door, stamped (text in _build_labels).
	var nxf := Transform3D(Basis(Vector3.BACK, 0.05), Vector3(f.x - 0.06, 1.5, fz + 0.02))
	m._sbox("flat", Vector3(0.36, 0.26, 0.004), nxf, Color(0.98, 0.84, 0.84))
	m._sbox("flat", Vector3(0.33, 0.012, 0.004), nxf * Transform3D(Basis(), Vector3(0, -0.08, 0.002)), Color(0.45, 0.4, 0.42))
	m._sbox("flat", Vector3(0.25, 0.008, 0.004), nxf * Transform3D(Basis(), Vector3(-0.03, -0.1, 0.002)), Color(0.55, 0.5, 0.52))
	# Crayon drawing: a big man, a house, a sun.
	var dxf := Transform3D(Basis(Vector3.BACK, 0.1), Vector3(f.x + 0.12, 0.92, fz + 0.02))
	m._sbox("glow", Vector3(0.07, 0.07, 0.003), dxf * Transform3D(Basis(), Vector3(0.05, 0.07, 0)), Color(0.95, 0.75, 0.2))
	m._sbox("flat", Vector3(0.05, 0.1, 0.003), dxf * Transform3D(Basis(), Vector3(-0.04, -0.02, 0)), Color(0.55, 0.3, 0.2))
	m._sbox("flat", Vector3(0.07, 0.06, 0.003), dxf * Transform3D(Basis(), Vector3(0.04, -0.05, 0)), Color(0.8, 0.2, 0.2))
	var mags: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.15), Color(0.3, 0.7, 0.3), Color(0.9, 0.4, 0.7), Color(0.95, 0.55, 0.1)]
	var mpos: Array[Vector2] = [Vector2(-0.2, 1.55), Vector2(0.08, 1.57), Vector2(-0.14, 1.12), Vector2(0.12, 1.02), Vector2(-0.22, 1.76), Vector2(0.2, 1.3)]
	for i in mpos.size():
		m._bx("flat", Vector3(0.04, 0.04, 0.02), Vector3(f.x + mpos[i].x, mpos[i].y, fz + 0.025), mags[i])
	# On top, at the back edge: a dusty bread box (the front stays clear to stand on).
	m._bx("flat", Vector3(0.4, 0.16, 0.2), Vector3(f.x - 0.1, 1.88, f.z - 0.22), Color(0.6, 0.18, 0.14))
	add_perch("the fridge", "roof", Vector3(f.x + 0.05, 1.8, f.z + 0.12), Vector3(f.x + 0.75, 0.0, -3.75),
		footprint(Vector2(f.x, f.z), Vector2(0.44, 0.39), "THE FRIDGE", "Fridge Door Crash", 250, "metal_hit"))


func _kchair(pos: Vector3, face: Vector3) -> void:
	# Chrome-and-vinyl kitchen chair.
	var xf := Transform3D(Basis.looking_at(face), pos)
	var vinyl := Color(0.62, 0.22, 0.18)
	var chrome := Color(0.78, 0.78, 0.8)
	m._sbox("flat", Vector3(0.44, 0.07, 0.42), xf * Transform3D(Basis(), Vector3(0, 0.46, 0)), vinyl)
	m._sbox("flat", Vector3(0.42, 0.26, 0.06), xf * Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0, 0.82, 0.2)), vinyl)
	for sx: float in [-0.19, 0.19]:
		for sz: float in [-0.17, 0.17]:
			m._beam("metal", xf * Vector3(sx, 0.0, sz), xf * Vector3(sx, 0.43, sz), 0.025, chrome)
		m._beam("metal", xf * Vector3(sx, 0.46, 0.19), xf * Vector3(sx, 0.95, 0.24), 0.022, chrome)


func _build_table() -> void:
	# Formica-and-chrome kitchen table (top 0.78) with the bills spread on it: a perch.
	var c := TABLE_C
	var chrome := Color(0.78, 0.78, 0.8)
	m._bx("flat", Vector3(1.5, 0.04, 0.95), c + Vector3(0, 0.76, 0), Color(0.78, 0.82, 0.72))
	m._bx("metal", Vector3(1.52, 0.04, 0.97), c + Vector3(0, 0.72, 0), chrome)
	for lx: float in [-0.66, 0.66]:
		for lz: float in [-0.38, 0.38]:
			m._beam("metal", c + Vector3(lx, 0.0, lz), c + Vector3(lx, 0.72, lz), 0.04, chrome)
	# Envelopes, the eleven-page contract (page nine on top), a napkin holder, salt and pepper.
	var env_cols: Array[Color] = [Color(0.95, 0.94, 0.9), Color(0.92, 0.88, 0.72), Color(0.95, 0.94, 0.9), Color(0.85, 0.8, 0.62)]
	for k in 4:
		m._bx("flat", Vector3(0.24, 0.006, 0.12), c + Vector3(-0.4 + k * 0.08, 0.783 + k * 0.004, -0.15 + k * 0.05), env_cols[k], randf_range(-0.6, 0.6))
	for k in 3:
		m._bx("flat", Vector3(0.22, 0.004, 0.29), c + Vector3(0.28 + k * 0.01, 0.782 + k * 0.004, 0.1 - k * 0.01), Color(0.97, 0.97, 0.95), 0.2 + k * 0.08)
	m._bx("metal", Vector3(0.14, 0.12, 0.06), c + Vector3(0.0, 0.84, -0.3), chrome)
	m._bx("flat", Vector3(0.12, 0.1, 0.03), c + Vector3(0.0, 0.85, -0.3), Color(0.95, 0.95, 0.95))
	m._cy("flat", 0.02, 0.02, 0.07, c + Vector3(0.12, 0.815, -0.3), Color(0.95, 0.95, 0.95), 6)
	m._cy("flat", 0.02, 0.02, 0.07, c + Vector3(0.17, 0.815, -0.3), Color(0.15, 0.15, 0.15), 6)
	# Two chairs tucked in at the far side and the left end (the others are weapons now).
	_kchair(c + Vector3(-0.15, 0.0, -0.62), Vector3(0, 0, 1))
	_kchair(c + Vector3(-0.92, 0.0, 0.05), Vector3(1, 0, 0))
	add_perch("kitchen table", "table", c + Vector3(0, 0.78, 0), c + Vector3(1.15, 0.0, 0.1),
		footprint(Vector2(c.x - 0.1, c.z - 0.05), Vector2(0.88, 0.62), "THE KITCHEN TABLE", "Kitchen Table Crash", 200, "wood_hit"))


func _build_living_room() -> void:
	# --- TV stand + old wood-grain CRT with rabbit ears, VCR blinking 12:00
	var tv := Vector3(1.6, 0.0, WALL_Z + 0.28)
	m._bx("k_oak", Vector3(1.5, 0.55, 0.5), tv + Vector3(0, 0.275, 0), Color(0.62, 0.46, 0.36))
	m._bx("flat", Vector3(1.4, 0.2, 0.02), tv + Vector3(0, 0.2, 0.25), Color(0.08, 0.07, 0.06))
	m._bx("flat", Vector3(0.42, 0.08, 0.3), tv + Vector3(-0.35, 0.2, 0.08), Color(0.12, 0.12, 0.13))  # VCR
	m._bx("glow", Vector3(0.08, 0.025, 0.01), tv + Vector3(-0.25, 0.21, 0.235), Color(0.3, 0.95, 0.5))
	m._bx("k_oak", Vector3(0.82, 0.64, 0.52), tv + Vector3(0.05, 0.87, -0.02), Color(0.5, 0.36, 0.26))
	m._bx("flat", Vector3(0.62, 0.5, 0.02), tv + Vector3(-0.02, 0.88, 0.245), Color(0.1, 0.1, 0.11))
	m._bx("glow", Vector3(0.54, 0.42, 0.02), tv + Vector3(-0.02, 0.88, 0.255), Color(0.38, 0.5, 0.62))
	m._bx("flat", Vector3(0.12, 0.5, 0.02), tv + Vector3(0.36, 0.88, 0.245), Color(0.18, 0.17, 0.16))
	for k in 3:
		m._cy("flat", 0.02, 0.02, 0.02, tv + Vector3(0.36, 1.0 - k * 0.1, 0.26), Color(0.7, 0.7, 0.68), 6)
	m._beam("metal", tv + Vector3(0.05, 1.19, -0.05), tv + Vector3(-0.25, 1.62, -0.12), 0.012, Color(0.75, 0.75, 0.75))
	m._beam("metal", tv + Vector3(0.05, 1.19, -0.05), tv + Vector3(0.38, 1.58, -0.1), 0.012, Color(0.75, 0.75, 0.75))
	m._bx("flat", Vector3(0.12, 0.04, 0.08), tv + Vector3(0.05, 1.2, -0.05), Color(0.1, 0.1, 0.1))
	obstacles.append(footprint(Vector2(tv.x, tv.z), Vector2(0.76, 0.27), "THE TV", "TV Stand Crash", 200, "wood_hit"))

	# --- Couch (back to the camera, facing the TV), afghan over the back; its arm is a perch
	var cc := COUCH_C
	var clen := 2.3
	var plaid := Color(1.0, 1.0, 1.0)
	m._bx("k_plaid", Vector3(clen - 0.4, 0.3, 0.8), cc + Vector3(0, 0.25, -0.05), plaid)            # base
	for k in 3:
		var cx := cc.x - (clen - 0.4) * 0.5 + (k + 0.5) * (clen - 0.4) / 3.0
		m._bx("k_plaid", Vector3((clen - 0.4) / 3.0 - 0.03, 0.12, 0.72), Vector3(cx, 0.46, cc.z - 0.07), plaid.darkened(0.04))
		m._bx("k_plaid", Vector3((clen - 0.4) / 3.0 - 0.03, 0.42, 0.18), Vector3(cx, 0.68, cc.z + 0.24), plaid.darkened(0.08))
	m._bx("k_plaid", Vector3(clen, 0.95, 0.2), cc + Vector3(0, 0.475, 0.35), plaid.darkened(0.15))   # back (top 0.95)
	for s: float in [-1.0, 1.0]:
		m._bx("k_plaid", Vector3(0.22, 0.62, 0.9), cc + Vector3(s * (clen * 0.5 - 0.11), 0.31, 0), plaid.darkened(0.1))
		m._cy("k_plaid", 0.12, 0.12, 0.88, Vector3(cc.x + s * (clen * 0.5 - 0.11), 0.62, cc.z), plaid.darkened(0.1), 8)
	m._sbox("flat", Vector3(0.9, 0.1, 0.5), Transform3D(Basis(Vector3.UP, 0.08), cc + Vector3(-0.3, 0.95, 0.3)), Color(0.75, 0.55, 0.3))   # afghan
	for k in 5:
		m._bx("flat", Vector3(0.9, 0.02, 0.06), cc + Vector3(-0.3, 1.0, 0.1 + k * 0.09), [Color(0.85, 0.3, 0.2), Color(0.3, 0.55, 0.35), Color(0.9, 0.75, 0.3)][k % 3], 0.08)
	m._bx("flat", Vector3(0.4, 0.14, 0.32), cc + Vector3(0.7, 0.6, -0.05), Color(0.55, 0.62, 0.4), 0.3)   # throw pillow
	add_perch("couch arm", "couch", Vector3(cc.x - clen * 0.5 + 0.11, 0.74, cc.z - 0.05), Vector3(cc.x - clen * 0.5 + 0.1, 0.0, 3.7),
		footprint(Vector2(cc.x, cc.z), Vector2(clen * 0.5, 0.46), "THE COUCH", "Couch Crash", 200, "thud"))

	# --- Coffee table with the remote, a mug and TV Guide
	var ctb := Vector3(2.3, 0.0, 2.8)
	m._bx("k_oak", Vector3(1.1, 0.06, 0.56), ctb + Vector3(0, 0.4, 0), Color(0.62, 0.44, 0.32))
	m._bx("k_oak", Vector3(1.0, 0.04, 0.46), ctb + Vector3(0, 0.12, 0), Color(0.55, 0.4, 0.3))
	for lx: float in [-0.5, 0.5]:
		for lz: float in [-0.23, 0.23]:
			m._bx("k_oak", Vector3(0.06, 0.4, 0.06), ctb + Vector3(lx, 0.2, lz), Color(0.5, 0.36, 0.26))
	m._bx("flat", Vector3(0.05, 0.02, 0.17), ctb + Vector3(-0.2, 0.44, 0.05), Color(0.12, 0.12, 0.12), 0.4)
	m._cy("flat", 0.04, 0.04, 0.09, ctb + Vector3(0.3, 0.475, -0.08), Color(0.9, 0.88, 0.8), 8)
	m._bx("flat", Vector3(0.14, 0.01, 0.2), ctb + Vector3(0.05, 0.435, -0.05), Color(0.85, 0.3, 0.2), -0.3)
	obstacles.append(footprint(Vector2(ctb.x, ctb.z), Vector2(0.56, 0.29), "THE COFFEE TABLE", "Coffee Table Crash", 150, "wood_hit"))

	# --- Recliner (Mom's chair) angled at the TV, side table + reading lamp + the hospital lanyard
	var rp := Vector3(4.95, 0.0, 2.55)
	var face := Vector3(1.6 - rp.x, 0, WALL_Z - rp.z).normalized()
	var rxf := Transform3D(Basis.looking_at(face), rp)
	var brown := Color(0.6, 0.72, 0.56)   # olive-tinted plaid
	m._sbox("k_plaid", Vector3(0.8, 0.42, 0.78), rxf * Transform3D(Basis(), Vector3(0, 0.25, 0)), brown)
	m._sbox("k_plaid", Vector3(0.6, 0.14, 0.62), rxf * Transform3D(Basis(), Vector3(0, 0.5, -0.04)), brown.lightened(0.05))
	m._sbox("k_plaid", Vector3(0.78, 0.9, 0.24), rxf * Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, 0.78, 0.36)), brown.darkened(0.06))
	m._sbox("k_plaid", Vector3(0.6, 0.18, 0.2), rxf * Transform3D(Basis(), Vector3(0, 1.18, 0.42)), brown.lightened(0.04))
	for s2: float in [-1.0, 1.0]:
		m._sbox("k_plaid", Vector3(0.16, 0.62, 0.8), rxf * Transform3D(Basis(), Vector3(s2 * 0.42, 0.31, 0.0)), brown.darkened(0.12))
	m._sbox("flat", Vector3(0.6, 0.06, 0.06), rxf * Transform3D(Basis(), Vector3(0, 0.08, -0.4)), Color(0.15, 0.12, 0.1))
	obstacles.append(footprint(Vector2(rp.x, rp.z), Vector2(0.5, 0.5), "THE RECLINER", "Recliner Crash", 150, "thud"))
	var st := Vector3(5.85, 0.0, 3.55)
	m._bx("k_oak", Vector3(0.45, 0.55, 0.45), st + Vector3(0, 0.275, 0), Color(0.6, 0.44, 0.32))
	m._cy("flat", 0.07, 0.09, 0.3, st + Vector3(0.05, 0.7, 0.05), Color(0.7, 0.55, 0.35), 10)
	m._cy("glow", 0.12, 0.17, 0.2, st + Vector3(0.05, 0.95, 0.05), Color(0.98, 0.9, 0.72), 12)
	m._bx("flat", Vector3(0.1, 0.02, 0.14), st + Vector3(-0.12, 0.56, -0.08), Color(0.25, 0.6, 0.62))   # the badge
	m._beam("flat", st + Vector3(-0.12, 0.56, -0.02), st + Vector3(-0.2, 0.56, 0.12), 0.015, Color(0.25, 0.6, 0.62))

	# --- Floor lamp in the back-right corner
	var lp := Vector3(5.9, 0.0, -4.45)
	m._cy("metal", 0.18, 0.2, 0.04, lp + Vector3(0, 0.02, 0), Color(0.6, 0.5, 0.3), 12)
	m._cy("metal", 0.015, 0.015, 1.5, lp + Vector3(0, 0.77, 0), Color(0.65, 0.55, 0.32), 6)
	m._cy("glow", 0.26, 0.17, 0.32, lp + Vector3(0, 1.58, 0), Color(0.98, 0.86, 0.62), 14)
	obstacles.append(footprint(Vector2(lp.x, lp.z), Vector2(0.2, 0.2), "THE LAMP", "Lamp Crash", 100, "metal_hit", 0.22))
	# A potted fern by the window (Gerald has one; Mom bought a bigger one).
	var fp := Vector3(5.95, 0.0, 0.0)
	m._cy("flat", 0.2, 0.15, 0.32, fp + Vector3(0, 0.16, 0), Color(0.62, 0.3, 0.2), 10)
	for k in 7:
		var a := TAU * k / 7.0
		m._beam("flat", fp + Vector3(0, 0.3, 0), fp + Vector3(cos(a) * 0.38, 0.62 + randf() * 0.2, sin(a) * 0.38), 0.07, Color(0.22, 0.42, 0.18))
	m._cy("flat", 0.14, 0.0, 0.5, fp + Vector3(0, 0.6, 0), Color(0.26, 0.48, 0.2), 8)


func _build_stairs() -> void:
	# Stair hall behind the opening in the back wall: stairs climb away from the camera.
	var x0 := STAIR_X0
	var x1 := STAIR_X1
	var back := -8.6
	var trim := Color(0.95, 0.9, 0.82)
	m._bx("k_oak", Vector3(x1 - x0, 0.02, -back + WALL_Z), Vector3((x0 + x1) * 0.5, 0.0, (WALL_Z + back) * 0.5), Color(0.8, 0.7, 0.6))
	for sx: float in [x0 - 0.06, x1 + 0.06]:
		m._bx("k_paper", Vector3(0.12, WALL_H, -back + WALL_Z), Vector3(sx, WALL_H * 0.5, (WALL_Z + back) * 0.5), Color(0.78, 0.72, 0.64))
	m._bx("k_paper", Vector3(x1 - x0 + 0.24, WALL_H, 0.12), Vector3((x0 + x1) * 0.5, WALL_H * 0.5, back - 0.06), Color(0.72, 0.66, 0.58))
	for k in 10:
		var top := 0.19 * (k + 1)
		var zf := WALL_Z - 0.55 - 0.3 * k
		m._bx("k_oak", Vector3(x1 - x0, top, 0.3), Vector3((x0 + x1) * 0.5, top * 0.5, zf - 0.15), Color(0.75, 0.6, 0.48))
		m._bx("flat", Vector3(x1 - x0 - 0.3, 0.012, 0.28), Vector3((x0 + x1) * 0.5, top + 0.006, zf - 0.15), Color(0.5, 0.22, 0.2))  # runner
	# Casing around the opening + a handrail.
	for x: float in [x0, x1]:
		m._bx("flat", Vector3(0.08, 2.25, 0.2), Vector3(x, 1.125, WALL_Z - 0.08), trim)
	m._bx("flat", Vector3(x1 - x0 + 0.16, 0.1, 0.2), Vector3((x0 + x1) * 0.5, 2.3, WALL_Z - 0.08), trim)
	m._beam("k_oak", Vector3(x1 - 0.06, 0.95, WALL_Z - 0.5), Vector3(x1 - 0.06, 2.85, back + 0.1), 0.06, Color(0.6, 0.42, 0.3))


func _photo(pos: Vector3, size: Vector2, tint: Color, out := Vector3.BACK) -> void:
	# Framed family photo on a wall (frame, mat, a soft two-tone "snapshot").
	var yaw := atan2(out.x, out.z)
	var b := Basis(Vector3.UP, yaw)
	var xf := Transform3D(b, pos)
	m._sbox("k_oak", Vector3(size.x, size.y, 0.03), xf, Color(0.45, 0.3, 0.2))
	m._sbox("flat", Vector3(size.x - 0.05, size.y - 0.05, 0.03), xf * Transform3D(Basis(), Vector3(0, 0, 0.005)), Color(0.92, 0.9, 0.84))
	m._sbox("flat", Vector3(size.x - 0.1, size.y - 0.1, 0.03), xf * Transform3D(Basis(), Vector3(0, 0, 0.01)), tint)
	m._sbox("flat", Vector3((size.x - 0.1) * 0.4, (size.y - 0.1) * 0.55, 0.03), xf * Transform3D(Basis(), Vector3(0, -(size.y - 0.1) * 0.2, 0.014)), Color(0.42, 0.28, 0.2))
	m._sbox("flat", Vector3((size.x - 0.1) * 0.22, (size.y - 0.1) * 0.22, 0.03), xf * Transform3D(Basis(), Vector3(0, (size.y - 0.1) * 0.18, 0.016)), Color(0.5, 0.34, 0.24))


func _build_decor() -> void:
	var wz := WALL_Z + 0.02
	# The cereal-box KITCHEN CHAMPIONSHIP belt, taped above the TV (label in _build_labels).
	var bc := Vector3(1.6, 1.86, wz + 0.01)
	m._bx("flat", Vector3(1.05, 0.13, 0.012), bc, Color(0.85, 0.22, 0.16))
	m._bx("flat", Vector3(1.05, 0.025, 0.014), bc + Vector3(0, 0.05, 0), Color(0.95, 0.78, 0.2))
	m._bx("flat", Vector3(1.05, 0.025, 0.014), bc + Vector3(0, -0.05, 0), Color(0.95, 0.78, 0.2))
	m._scyl("flat", 0.2, 0.2, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.25, 1.0, 1.0)), bc + Vector3(0, 0, 0.012)), Color(0.9, 0.72, 0.2), 16)
	m._scyl("flat", 0.16, 0.16, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.25, 1.0, 1.0)), bc + Vector3(0, 0, 0.02)), Color(0.98, 0.86, 0.3), 16)
	for s: float in [-1.0, 1.0]:
		m._scyl("flat", 0.08, 0.08, 0.02, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), bc + Vector3(s * 0.35, 0, 0.014)), Color(0.2, 0.45, 0.8), 10)
		m._bx("flat", Vector3(0.12, 0.04, 0.005), bc + Vector3(s * 0.52, 0.06, 0.02), Color(0.85, 0.8, 0.6), 0.0)   # tape
	# Family photos around it (graduation, baby Theodore, Mom in scrubs, a church picnic).
	_photo(Vector3(0.45, 1.62, wz), Vector2(0.34, 0.44), Color(0.45, 0.55, 0.7))
	_photo(Vector3(0.5, 2.18, wz), Vector2(0.4, 0.3), Color(0.7, 0.62, 0.4))
	_photo(Vector3(2.75, 1.7, wz), Vector2(0.36, 0.46), Color(0.3, 0.6, 0.58))
	_photo(Vector3(2.7, 2.25, wz), Vector2(0.3, 0.3), Color(0.55, 0.65, 0.45))
	_photo(Vector3(1.6, 2.4, wz), Vector2(0.62, 0.36), Color(0.62, 0.55, 0.62))
	_photo(Vector3(3.45, 1.95, wz), Vector2(0.26, 0.34), Color(0.75, 0.55, 0.45))
	# Right wall, by the window: two more.
	_photo(Vector3(WALL_X - 0.02, 1.7, 0.4), Vector2(0.36, 0.46), Color(0.5, 0.48, 0.6), Vector3.LEFT)
	_photo(Vector3(WALL_X - 0.02, 1.6, 1.2), Vector2(0.3, 0.38), Color(0.65, 0.5, 0.4), Vector3.LEFT)
	# Kitchen: wall phone with a long curly cord, calendar, clock (left wall), hanging pot holders.
	var lx := -WALL_X + 0.02
	m._bx("flat", Vector3(0.06, 0.24, 0.12), Vector3(lx + 0.03, 1.5, -0.4), Color(0.92, 0.78, 0.3))
	m._bx("flat", Vector3(0.05, 0.2, 0.06), Vector3(lx + 0.07, 1.5, -0.38), Color(0.9, 0.75, 0.28))
	for k in 10:
		var t := float(k) / 9.0
		m._bx("flat", Vector3(0.025, 0.03, 0.025), Vector3(lx + 0.06 + sin(t * 9.0) * 0.012, 1.38 - t * 0.55, -0.4 + t * 0.12), Color(0.9, 0.75, 0.28))
	m._bx("flat", Vector3(0.01, 0.42, 0.32), Vector3(lx, 1.55, -1.6), Color(0.95, 0.94, 0.9))
	m._bx("flat", Vector3(0.012, 0.18, 0.3), Vector3(lx + 0.002, 1.66, -1.6), Color(0.35, 0.55, 0.7))
	for r in 3:
		for c in 5:
			m._bx("flat", Vector3(0.014, 0.025, 0.04), Vector3(lx + 0.003, 1.48 - r * 0.05, -1.72 + c * 0.06), Color(0.55, 0.55, 0.55) if (r + c) % 4 != 0 else Color(0.8, 0.15, 0.12))
	m._scyl("flat", 0.15, 0.15, 0.04, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(lx + 0.02, 2.35, -2.8)), Color(0.95, 0.94, 0.88), 16)
	m._scyl("flat", 0.17, 0.17, 0.03, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(lx + 0.01, 2.35, -2.8)), Color(0.6, 0.2, 0.15), 16)
	m._beam("flat", Vector3(lx + 0.045, 2.35, -2.8), Vector3(lx + 0.045, 2.44, -2.8), 0.012, Color(0.1, 0.1, 0.1))
	m._beam("flat", Vector3(lx + 0.045, 2.35, -2.8), Vector3(lx + 0.045, 2.35, -2.73), 0.012, Color(0.1, 0.1, 0.1))
	# Coat hooks + a hoodie on the left wall near the front, a shoe pile under it.
	m._bx("k_oak", Vector3(0.04, 0.1, 0.8), Vector3(lx + 0.02, 1.7, 3.2), Color(0.6, 0.45, 0.32))
	m._bx("flat", Vector3(0.12, 0.6, 0.4), Vector3(lx + 0.08, 1.35, 3.0), Color(0.3, 0.32, 0.36))
	m._bx("flat", Vector3(0.1, 0.5, 0.34), Vector3(lx + 0.07, 1.4, 3.45), Color(0.55, 0.2, 0.16))


func _build_lights() -> void:
	# Key: a big soft daylight "set light" high over the open camera side (the one shadow map).
	var kp := Vector3(-1.2, 6.8, 5.2)
	var key := SpotLight3D.new()
	key.transform = Transform3D(Basis.looking_at(Vector3(0.2, 0.0, -0.8) - kp), kp)
	key.spot_angle = 52.0
	key.spot_angle_attenuation = 1.1
	key.spot_range = 20.0
	key.spot_attenuation = 0.4
	key.light_energy = 2.0
	key.light_specular = 0.5
	key.light_color = Color(1.0, 0.95, 0.86)
	add_child(key)
	key_light = key
	# Sunlight through the living-room window: a warm slanted pool on the wood floor.
	var sp := Vector3(10.5, 5.0, -2.2)
	var sun := SpotLight3D.new()
	sun.transform = Transform3D(Basis.looking_at(Vector3(2.4, 0.0, -1.2) - sp), sp)
	sun.spot_angle = 17.0
	sun.spot_angle_attenuation = 0.6
	sun.spot_range = 16.0
	sun.spot_attenuation = 0.3
	sun.light_energy = 4.0
	sun.light_specular = 0.4
	sun.light_color = Color(1.0, 0.86, 0.62)
	add_child(sun)
	# Practicals: kitchen ceiling fixture (off-screen above), window fill over the sink, the
	# floor lamp, the TV's blue flicker, the stair hall.
	var omnis: Array = [[Vector3(-3.3, 2.9, -0.6), 7.5, 0.7, Color(1.0, 0.9, 0.72)],
		[Vector3(-2.6, 1.9, -4.0), 3.5, 0.4, Color(0.85, 0.92, 1.0)],
		[Vector3(5.9, 1.55, -4.3), 4.5, 1.0, Color(1.0, 0.76, 0.46)],
		[Vector3(1.6, 0.9, -4.0), 3.0, 0.5, Color(0.55, 0.7, 1.0)],
		[Vector3(4.5, 2.4, -6.4), 4.0, 0.7, Color(1.0, 0.82, 0.58)]]
	for o: Array in omnis:
		m.make_omni(o[0], o[1], o[2], o[3])


func _build_grime() -> void:
	var zf := 5.0
	m._grime_wall(Vector3(-WALL_X, 0, WALL_Z + 0.04), Vector3(WALL_X, 0, WALL_Z + 0.04), Vector3.BACK, 0.4, 0.35, 0.3, 0.25)
	m._grime_wall(Vector3(-WALL_X + 0.04, 0, WALL_Z), Vector3(-WALL_X + 0.04, 0, zf), Vector3.RIGHT, 0.4, 0.35, 0.3, 0.25)
	m._grime_wall(Vector3(WALL_X - 0.04, 0, WALL_Z), Vector3(WALL_X - 0.04, 0, zf), Vector3.LEFT, 0.4, 0.35, 0.3, 0.25)
	m._grime_wall(Vector3(COUNTER_X0, 0, WALL_Z + 0.63), Vector3(COUNTER_X1, 0, WALL_Z + 0.63), Vector3.BACK, 0.12, 0.3, 0.3, 0.3)
	m._flush_grime()


func _label(text: String, pos: Vector3, size: int, col: Color, roll := 0.0, yaw := 0.0) -> void:
	var lab := Label3D.new()
	lab.text = text
	lab.font_size = size
	lab.outline_size = 0
	lab.modulate = col
	lab.shaded = true
	lab.position = pos
	lab.rotation = Vector3(0, yaw, roll)
	add_child(lab)


func _build_labels() -> void:
	var fz := FRIDGE.z + 0.37
	# The PAST DUE notice on the fridge (red stamp over a bill) + the electric bill.
	_label("PAST DUE", Vector3(FRIDGE.x - 0.06, 1.53, fz + 0.028), 14, Color(0.82, 0.06, 0.05), 0.12)
	_label("FINAL\nNOTICE", Vector3(FRIDGE.x - 0.14, 1.0, fz + 0.03), 11, Color(0.75, 0.1, 0.08), -0.04)
	# The belt.
	_label("KITCHEN\nCHAMP", Vector3(1.6, 1.86, WALL_Z + 0.07), 13, Color(0.55, 0.12, 0.08))
	# Calendar month.
	_label("MAY", Vector3(-WALL_X + 0.03, 1.69, -1.6), 12, Color(0.95, 0.95, 0.95), 0.0, PI * 0.5)


# ---- environment: indoors by day, no sky, no fog

func setup_environment(env: Environment) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.06, 0.05)   # the dark studio above the set walls
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.62, 0.54)
	env.ambient_light_energy = 0.36
	env.fog_enabled = false
	env.tonemap_exposure = 1.0
	# main's "moon" becomes soft daylight coming in from the living-room window side (+x).
	var sun: DirectionalLight3D = m.moon
	if sun != null:
		sun.transform = Transform3D(Basis.looking_at(Vector3(-0.7, -0.55, -0.3)), Vector3(0, 10, 0))
		sun.light_color = Color(1.0, 0.9, 0.76)
		sun.light_energy = 0.25
		sun.light_specular = 0.3
	var post: ShaderMaterial = m.post_mat
	if post != null:
		post.set_shader_parameter("sepia", 0.24)
		post.set_shader_parameter("bloom_threshold", 0.8)
		post.set_shader_parameter("bloom_strength", 0.3)
		post.set_shader_parameter("vignette", 0.24)


# ---- the people watching (main.build_crowd turns these into the billboard crowd)

func _fan(p: Vector3, person: String, lit := 0.6, bob := 1.0) -> void:
	crowd_spots.append({"pos": p, "person": person, "lit": lit, "bob": bob})


func _build_crowd_spots() -> void:
	# A small house crowd: Pickles filming from the front-left corner, a friend in the back-hall
	# doorway, two on the stairs, one cheering by the recliner. Nobody inside the fighting area.
	crowd_spots = []
	_fan(Vector3(-5.85, 0.0, 4.7), "filmer", 0.65, 1.3)
	_fan(Vector3(-6.85, 0.0, 0.95), "hoodie", 0.5)
	_fan(Vector3(4.25, 0.57 - 0.53, WALL_Z - 1.0), "sit_cup", 0.5)
	_fan(Vector3(4.8, 0.38, WALL_Z - 0.75), "girl", 0.5)
	_fan(Vector3(5.95, 0.0, 4.65), "cheer", 0.6, 1.4)

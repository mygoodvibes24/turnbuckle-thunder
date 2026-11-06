extends Node3D
## A single wrestler: procedural body, state machine, grapple system and CPU AI.
## The match (main.gd) fills the in_* input fields each physics frame and calls tick().

signal announce(text: String)
signal impact(strength: float)
signal pin_count(count: int)
signal won()
## Generic feedback event for audio/FX. kind is one of: "punch", "kick", "thud", "big_thud",
## "rope", "whoosh", "count", "kickout", "finisher", "reversal", "taunt", "grab".
## strength is 0..1+, where is the world-space contact point.
signal sfx(kind: String, strength: float, where: Vector3)

enum S { IDLE, WALK, RUN, PUNCH, RUN_ATTACK, STUNNED, TIEUP_ATK, TIEUP_DEF, THROWING, THROWN,
	DOWN, GETTING_UP, PINNING, PINNED, TAUNT, WIN, LOSE,
	# --- appended states (keep the order above: the HUD refers to states by name) ---
	WHIFF,        # missed grab: short off-balance recovery (not the "got hit" stagger)
	GRAB_WINDUP,  # GRAB pressed, reaching out: release = weak lock-up, hold 0.3 s = strong
	WHIPPING,     # just Irish-whipped the opponent, waiting for them to come off the ropes
	STOMP,        # stomping a downed opponent
	GROUND_DROP,  # running elbow / knee drop onto a downed opponent (then lies DOWN briefly)
	PICKUP,       # hauling a downed opponent back to their feet
	LIFTED }      # being hauled up (ends dazed and STUNNED in front of the attacker)

const RING_HALF := 3.5        # throws always land inside this
const ROPE_BOUNCE := 3.75     # runners rebound here (the ropes are at 4.15)
const RING_CLAMP := 3.8       # hard limit for any wrestler position
const WALK_SPEED := 2.7
const RUN_SPEED := 6.2
const PIN_COUNT_TIME := 0.85
const PIN_ESCAPE_NEEDED := 6.0
const LOCKUP_DIST := 1.05     # pelvis-to-pelvis spacing in a lock-up (no head clipping)
const STRONG_GRAB_HOLD := 0.3 # hold GRAB this long for a strong lock-up
const REVERSAL_WINDOW := 0.25 # defender's timing window after a weak-grapple commit
const STRONG_REVERSAL_WINDOW := 0.35  # strong grapples are slower, so easier to read
const REVERSAL_LOCKOUT := 0.5 # pressing too early locks reversals out for this long
const PUNCH_HIT := 0.18       # punch contact time (also its reversal window)
const PUNCH_END := 0.42
const TAUNT_TIME := 1.1
const TAUNT_COOLDOWN := 6.0
const SPECIAL_TIME := 15.0    # full spirit lasts this long before draining
const SPECIAL_DRAIN_TO := 80.0
const NEAR_FALL_CALLS := ["TWO AND A HALF!", "SO CLOSE!", "NEAR FALL!", "KICKED OUT AT 2.9!"]

# Grapple move list. "land" = landing distance along the thrower's facing (negative = behind).
# "tier" feeds pin kick-out difficulty: weak / strong / finisher / reversal / ground / strike.
const MOVES := {
	# weak lock-up (tap GRAB)
	"knee": {"name": "Knee Lift", "dmg": 6.0, "kind": "strike", "tier": "weak"},
	"slam": {"name": "Body Slam", "dmg": 10.0, "kind": "throw", "tier": "weak", "time": 1.0, "height": 1.6, "land": 1.3, "flip": false},
	"suplex": {"name": "Suplex!", "dmg": 13.0, "kind": "throw", "tier": "weak", "time": 1.1, "height": 2.1, "land": -1.2, "flip": true},
	"ddt": {"name": "DDT!", "dmg": 14.0, "kind": "throw", "tier": "weak", "time": 0.7, "height": 0.5, "land": 0.7, "flip": false},
	# strong lock-up (hold GRAB)
	"piledriver": {"name": "THUNDER TOMBSTONE!", "dmg": 18.0, "kind": "throw", "tier": "strong", "time": 1.2, "height": 1.3, "land": 0.8, "flip": true},
	"powerbomb": {"name": "Storm Powerbomb!", "dmg": 17.0, "kind": "throw", "tier": "strong", "time": 1.3, "height": 2.4, "land": 1.1, "flip": false},
	"spinebuster": {"name": "Spinebuster!", "dmg": 15.0, "kind": "throw", "tier": "strong", "time": 0.8, "height": 0.9, "land": 1.2, "flip": false},
	"neckbreaker": {"name": "Swinging Neckbreaker!", "dmg": 13.0, "kind": "throw", "tier": "strong", "time": 0.8, "height": 0.6, "land": -0.6, "flip": false},
	# special (full spirit, STICK + GRAB in either lock-up)
	"finisher": {"name": "THUNDER DRIVER!!", "dmg": 26.0, "kind": "throw", "tier": "finisher", "time": 1.4, "height": 2.6, "land": 0.9, "flip": true},
	# Irish-whip follow-ups
	"clothesline": {"name": "Clothesline!", "dmg": 12.0, "kind": "strike", "tier": "strike"},
	"backdrop": {"name": "Back Body Drop!", "dmg": 12.0, "kind": "throw", "tier": "weak", "time": 1.0, "height": 2.2, "land": -1.4, "flip": true},
	"powerslam": {"name": "Running Powerslam!", "dmg": 14.0, "kind": "throw", "tier": "strong", "time": 0.8, "height": 1.0, "land": 1.0, "flip": false},
	# reversals
	"armdrag": {"name": "REVERSAL! Arm Drag", "dmg": 7.0, "kind": "throw", "tier": "reversal", "time": 0.8, "height": 1.1, "land": 1.5, "flip": true},
	"hiptoss": {"name": "REVERSAL! Hip Toss", "dmg": 9.0, "kind": "throw", "tier": "reversal", "time": 0.8, "height": 1.3, "land": 1.4, "flip": true},
	"rev_backdrop": {"name": "REVERSAL! Back Body Drop", "dmg": 10.0, "kind": "throw", "tier": "reversal", "time": 1.0, "height": 2.0, "land": -1.4, "flip": true},
	# ground attacks
	"stomp": {"name": "Stomp", "dmg": 4.0, "kind": "ground", "tier": "ground"},
	"elbow_drop": {"name": "Flying Elbow Drop!", "dmg": 10.0, "kind": "ground", "tier": "ground"},
	"knee_drop": {"name": "Running Knee Drop!", "dmg": 9.0, "kind": "ground", "tier": "ground"},
}

var display_name := "Wrestler"
var gear_color := Color.RED
var trunk_color := Color.BLACK
var skin_color := Color(0.86, 0.64, 0.48)
var is_cpu := false
var opponent: Node3D

var health := 100.0
var spirit := 0.0
var state: int = S.IDLE
var state_time := 0.0
var anim_clock := 0.0
var facing := Vector3(0, 0, 1)
var run_dir := Vector3.ZERO
var rope_bounces := 0
var hit_landed := false
var combo_hits := 0
var combo_timer := 0.0
var stun_time := 0.35
var down_duration := 2.0
var throw_from := Vector3.ZERO
var throw_to := Vector3.ZERO
var throw_time := 1.0
var throw_height := 1.5
var throw_end_angle := -PI / 2
var pending_damage := 0.0
var pin_escape := 0.0
var pin_count_value := 0

# Gameplay detail (readable by HUD / FX / animation)
var current_move_key := ""     # what the current state is doing: "punch", "knee", "clothesline",
                               # "stomp", "elbow_drop", a MOVES key while throwing/thrown, ...
var last_hit_tier := ""        # tier of the last big hit taken (pin kick-out difficulty)
var tie_strong := false        # current lock-up is a strong one (both wrestlers know)
var tie_free := false          # lock-up on a dazed opponent: no reversal window
var committed_move := ""       # lock-up move chosen, executes when commit_timer runs out
var commit_timer := 0.0
var commit_dir := Vector3.ZERO # Irish whip direction
var whipped := false           # running because we were whipped: the game steers, not us
var dazed := false             # STUNNED after being picked up: free lock-up for the attacker
var whiff_time := 0.45
var ground_hits := 0           # hits taken in the current DOWN (caps the down-time extension)
var drop_from := Vector3.ZERO
var drop_to := Vector3.ZERO
var taunt_cooldown := 0.0
var taunt_bonus := false
var special_timer := 0.0       # > 0 while SPECIAL (full spirit) is lit; drains to 80 at 0
var reversal_window := 0.0     # > 0 while a timed-reversal window is open on us (HUD: "REVERSE!")
var reversal_kind := ""        # "grapple", "strong", "whip", "punch" or "lariat"
var reversal_age := 0.0
var reversal_lockout := 0.0    # > 0 after pressing too early (anti-mash)
var since_press := 10.0        # seconds since we last pressed STRIKE/GRAB

# Controller inputs (one-shot buttons are cleared after every tick; in_grapple_held is a level).
var in_move := Vector2.ZERO
var in_strike := false
var in_grapple := false
var in_grapple_held := false
var in_run := false
var in_pin := false
var any_pressed := false

# AI
var ai_skill := 0.5            # 0..1: reaction speed, reversal rate, pin kick-out strength
var ai_timer := 0.0
var ai_backoff := 0.0
var ai_tie_delay := 0.5
var ai_react := 0.0
var ai_seen_state := -1
var ai_strong_grab := false
var ai_rev_decided := false
var ai_rev_go := false
var ai_rev_at := 0.0
var ai_strafe_time := 0.0
var ai_strafe_dir := 1.0
var ai_whip_roll := 2.0
var ai_whip_trigger := 1.5

# Body parts
var pose_root: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var look := {}


func setup(p_name: String, p_look: Dictionary, p_cpu: bool) -> void:
	display_name = p_name
	look = p_look
	gear_color = look.get("gear", Color.RED)
	trunk_color = look.get("trunks", Color.BLACK)
	skin_color = look.get("skin", Color(0.86, 0.64, 0.48))
	is_cpu = p_cpu
	_build_body()


# ---------------------------------------------------------------- body building
# N64-style look: chunky 8-sided low-poly parts built with SurfaceTool (smooth
# per-vertex normals for that Gouraud shading), matte per-vertex lit materials and
# tiny painted textures with bilinear filtering (the soft N64 blur).
#
# Pivot layout: pose_root sits at the pelvis (STAND_Y above the feet when standing)
# and hips is at pose_root's origin, so falls and throws rotate the body around
# the pelvis. Standing straight, the boot soles touch y = 0.
# Loft UVs: u wraps around the part (front/+z at u = 0.5, -x side at 0.25,
# +x side at 0.75, back seam at 0/1), v runs from the top ring (0) to the bottom (1).

const STAND_Y := 0.95  # pelvis height when standing
const LIE_Y := 0.21    # pelvis height when lying on the back (rotation.x = -PI/2)
const PIN_Y := 0.55    # pelvis height when lying across a downed opponent

const FONT_3X5 := {
	"B": "110101110101110", "M": "101111111101101", "T": "111010010010010",
	"V": "101101101101010", "R": "110101110101101", "K": "101101110101101",
}


func _sat(c: Color, amt := 1.15) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * amt, 0.0, 1.0), c.v, c.a)


func _mat(c: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.texture_repeat = true
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(parent, b, pos, mat)


func _ball(parent: Node3D, r: float, pos: Vector3, mat: Material, scl := Vector3.ONE, segs := 8, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r if hemi else r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = segs
	s.rings = 4
	return _add_mesh(parent, s, pos, mat, scl)


func _prism(parent: Node3D, top_r: float, bottom_r: float, h: float, pos: Vector3, mat: Material, scl := Vector3.ONE, segs := 8) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return _add_mesh(parent, c, pos, mat, scl)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


# --- SurfaceTool lofts -------------------------------------------------------------

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	# Godot treats clockwise triangles as front faces, i.e. (b - a) x (c - a) points
	# away from the outward normal. Swap two corners when the winding disagrees.
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var tp := b
		b = c
		c = tp
		var tn := nb
		nb = nc
		nc = tn
		var tu := ub
		ub = uc
		uc = tu
	st.set_normal(na)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_uv(uc)
	st.add_vertex(c)


func _cap(st: SurfaceTool, ring: PackedVector3Array, uvs: PackedVector2Array, center: Vector3, n: Vector3, v: float) -> void:
	var cu := Vector2(0.5, v)
	for i in ring.size() - 1:
		_tri(st, center, ring[i], ring[i + 1], n, n, n, cu, Vector2(uvs[i].x, v), Vector2(uvs[i + 1].x, v))


## Builds a tapered 8-sided tube. rings: Array of Vector4(y, radius_x, radius_z, z_offset),
## ordered top to bottom. Vertices sit half a segment off the axes so a flat face points
## forward (+z) and to each side.
func _loft_mesh(rings: Array, cap_top: bool, cap_bottom: bool, segs := 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_r := rings.size()
	var first: Vector4 = rings[0]
	var last: Vector4 = rings[n_r - 1]
	var span: float = maxf(0.001, first.x - last.x)
	var step: float = TAU / float(segs)
	var ring_p: Array = []
	var ring_n: Array = []
	var ring_u: Array = []
	for j in n_r:
		var r: Vector4 = rings[j]
		var rp: Vector4 = rings[maxi(j - 1, 0)]
		var rn: Vector4 = rings[mini(j + 1, n_r - 1)]
		var dy: float = rp.x - rn.x
		var slope := 0.0
		if dy > 0.0001:
			slope = ((rn.y + rn.z) - (rp.y + rp.z)) * 0.5 / dy
		# keep v half a texel away from the edges so repeat-wrap doesn't bleed top<->bottom
		var v: float = 0.03 + 0.94 * (first.x - r.x) / span
		var pr := PackedVector3Array()
		var nr := PackedVector3Array()
		var ur := PackedVector2Array()
		for i in segs + 1:
			var a: float = -PI + (float(i) + 0.5) * step
			var sa := sin(a)
			var ca := cos(a)
			pr.append(Vector3(sa * r.y, r.x, ca * r.z + r.w))
			var hn := Vector3(sa / maxf(r.y, 0.001), 0.0, ca / maxf(r.z, 0.001)).normalized()
			nr.append(Vector3(hn.x, slope, hn.z).normalized())
			ur.append(Vector2((a + PI) / TAU, v))
		ring_p.append(pr)
		ring_n.append(nr)
		ring_u.append(ur)
	for j in n_r - 1:
		var p0: PackedVector3Array = ring_p[j]
		var p1: PackedVector3Array = ring_p[j + 1]
		var n0: PackedVector3Array = ring_n[j]
		var n1: PackedVector3Array = ring_n[j + 1]
		var u0: PackedVector2Array = ring_u[j]
		var u1: PackedVector2Array = ring_u[j + 1]
		for i in segs:
			_tri(st, p0[i], p0[i + 1], p1[i + 1], n0[i], n0[i + 1], n1[i + 1], u0[i], u0[i + 1], u1[i + 1])
			_tri(st, p0[i], p1[i + 1], p1[i], n0[i], n1[i + 1], n1[i], u0[i], u1[i + 1], u1[i])
	if cap_top:
		_cap(st, ring_p[0], ring_u[0], Vector3(0, first.x, first.w), Vector3.UP, 0.03)
	if cap_bottom:
		_cap(st, ring_p[n_r - 1], ring_u[n_r - 1], Vector3(0, last.x, last.w), Vector3.DOWN, 0.97)
	return st.commit()


func _loft(parent: Node3D, rings: Array, mat: Material, cap_top := true, cap_bottom := true, pos := Vector3.ZERO) -> MeshInstance3D:
	return _add_mesh(parent, _loft_mesh(rings, cap_top, cap_bottom), pos, mat)


# --- tiny painted textures -----------------------------------------------------------
# All are drawn so that texture column w/2 is the front centre (u = 0.5); pairs are
# mirrored with x -> (w - 1 - x).

func _px(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


func _new_img(w: int, h: int, c: Color) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _paint_flames(img: Image, base_y: int, max_h: int, outer: Color, inner: Color) -> void:
	# Repeating flame tongues rising from row base_y (tileable for widths divisible by 8).
	for x in img.get_width():
		var ph := x % 8
		var tri: float = absf(float(ph) - 3.5) / 3.5
		var hgt := int(round(lerpf(float(max_h), float(max_h) * 0.3, tri)))
		if int(x / 8.0) % 2 == 1:
			hgt -= 2
		hgt = maxi(hgt, 1)
		_px(img, x, base_y - hgt + 1, 1, hgt, outer)
		var ih := maxi(int(hgt * 0.5), 1)
		_px(img, x, base_y - ih + 1, 1, ih, inner)


func _paint_text(img: Image, text: String, center_x: int, y: int, c: Color) -> void:
	var n := text.length()
	if n == 0:
		return
	var total := n * 5 - 2
	var x0 := int(center_x - total / 2.0)
	for k in n:
		var key := text.substr(k, 1)
		if not FONT_3X5.has(key):
			continue
		var bits: String = FONT_3X5[key]
		for r in 5:
			for col in 3:
				if bits.substr(r * 3 + col, 1) == "1":
					_px(img, x0 + k * 5 + col, y + r, 1, 1, c)


func _torso_texture(skin: Color) -> ImageTexture:
	# 32x32 painted muscle shading: pecs, sternum, ab grid, darker lats and back.
	var img := _new_img(32, 32, skin)
	var dk := skin.darkened(0.14)
	var dk2 := skin.darkened(0.26)
	var lt := skin.lightened(0.08)
	var back := skin.darkened(0.06)
	_px(img, 0, 0, 6, 32, back)
	_px(img, 26, 0, 6, 32, back)
	_px(img, 0, 6, 1, 26, dk)           # spine (back seam)
	_px(img, 31, 6, 1, 26, dk)
	_px(img, 1, 9, 4, 1, dk)            # shoulder blades
	_px(img, 27, 9, 4, 1, dk)
	_px(img, 2, 10, 3, 3, dk.lerp(back, 0.5))
	_px(img, 27, 10, 3, 3, dk.lerp(back, 0.5))
	_px(img, 6, 8, 4, 24, dk)           # lats / flanks under the arms
	_px(img, 22, 8, 4, 24, dk)
	_px(img, 7, 18, 2, 14, dk2)
	_px(img, 23, 18, 2, 14, dk2)
	_px(img, 11, 6, 4, 1, dk)           # collarbones
	_px(img, 17, 6, 4, 1, dk)
	# pecs
	_px(img, 10, 9, 6, 7, lt)
	_px(img, 16, 9, 6, 7, lt)
	_px(img, 10, 16, 6, 2, dk2)
	_px(img, 16, 16, 6, 2, dk2)
	_px(img, 10, 15, 1, 1, dk2)
	_px(img, 21, 15, 1, 1, dk2)
	_px(img, 15, 8, 2, 10, dk)          # sternum
	# abs
	_px(img, 12, 18, 8, 13, lt)
	_px(img, 11, 18, 1, 13, dk)
	_px(img, 20, 18, 1, 13, dk)
	_px(img, 15, 18, 2, 13, dk)
	_px(img, 12, 21, 8, 1, dk)
	_px(img, 12, 25, 8, 1, dk)
	_px(img, 15, 29, 2, 1, dk2)         # navel
	return ImageTexture.create_from_image(img)


func _trunks_texture(trunk: Color, gear: Color, pattern: String, initials: String) -> ImageTexture:
	# 32x16: waistband, leg trim, side stripes or brick panels, initials on the front.
	var img := _new_img(32, 16, trunk)
	match pattern:
		"bricks":
			var mortar := Color(0.72, 0.7, 0.64)
			for x0 in [3, 20]:
				var xs: int = x0
				_px(img, xs, 3, 9, 11, gear)
				var course := 0
				var y := 3
				while y <= 13:
					_px(img, xs, y, 9, 1, mortar)
					var off := (course % 2) * 2
					for x in range(xs, xs + 9):
						if (x + off) % 4 == 0:
							_px(img, x, y + 1, 1, 2, mortar)
					y += 3
					course += 1
		"flames":
			_paint_flames(img, 13, 7, gear, gear.lerp(Color(1.0, 0.95, 0.4), 0.6))
		_:
			_px(img, 7, 3, 2, 11, gear)
			_px(img, 23, 3, 2, 11, gear)
	_px(img, 0, 0, 32, 3, gear)                  # waistband
	_px(img, 0, 1, 32, 1, gear.lightened(0.15))
	_px(img, 0, 14, 32, 2, gear.darkened(0.2))   # leg trim
	_paint_text(img, initials, 16, 5, gear.lightened(0.1))
	return ImageTexture.create_from_image(img)


func _tights_texture(base: Color, flame: Color) -> ImageTexture:
	# 32x16 tights with flames licking up from the bottom (knee / boot) of each part.
	var img := _new_img(32, 16, base)
	_paint_flames(img, 15, 11, flame, flame.lerp(Color(1.0, 0.95, 0.4), 0.6))
	return ImageTexture.create_from_image(img)


func _boot_texture(boot: Color, trim: Color) -> ImageTexture:
	# 16x16 boot shaft: top trim band, side stripes, lace panel with criss-cross laces.
	var img := _new_img(16, 16, boot)
	var lace := Color(0.95, 0.95, 0.9)
	_px(img, 0, 0, 16, 2, trim)
	_px(img, 0, 2, 16, 1, boot.darkened(0.3))
	_px(img, 3, 3, 2, 13, trim)                   # side stripes (u = 0.25 / 0.75)
	_px(img, 11, 3, 2, 13, trim)
	_px(img, 6, 3, 4, 13, boot.darkened(0.3))     # lace panel (front)
	for r in range(3, 16):
		if r % 2 == 1:
			_px(img, 6, r, 1, 1, lace)
			_px(img, 9, r, 1, 1, lace)
		else:
			_px(img, 7, r, 2, 1, lace)
	_px(img, 0, 15, 16, 1, boot.darkened(0.2))
	return ImageTexture.create_from_image(img)


func _head_texture(skin: Color, hair_c: Color, style: String) -> ImageTexture:
	# 64x32 wrap-around head texture: face on the front (columns ~22..41), ears at the
	# sides (u 0.25 / 0.75), hair or mask laces at the back seam.
	var dark := Color(0.12, 0.07, 0.05)
	var shade := skin.darkened(0.22)
	if look.get("mask", false):
		var mask_src: Color = look.get("mask_color", Color(0.12, 0.3, 0.85))
		var trim_src: Color = look.get("mask_trim", Color(1.0, 0.55, 0.1))
		var mask := _sat(mask_src)
		var trim := _sat(trim_src)
		var hot := trim.lerp(Color(1.0, 0.95, 0.4), 0.55)
		var mimg := _new_img(64, 32, mask)
		# crest stripe from the forehead over the crown to the back
		_px(mimg, 30, 0, 4, 12, trim)
		_px(mimg, 0, 0, 2, 9, trim)
		_px(mimg, 62, 0, 2, 9, trim)
		# flame-shaped trim around the eyes, tongues licking up the forehead
		_px(mimg, 25, 12, 14, 8, trim)
		_px(mimg, 26, 9, 2, 3, trim)
		_px(mimg, 36, 9, 2, 3, trim)
		_px(mimg, 28, 6, 1, 6, trim)
		_px(mimg, 35, 6, 1, 6, trim)
		_px(mimg, 24, 14, 1, 4, trim)
		_px(mimg, 39, 14, 1, 4, trim)
		_px(mimg, 31, 10, 2, 9, hot)
		# eye holes
		_px(mimg, 27, 14, 4, 3, Color.WHITE)
		_px(mimg, 33, 14, 4, 3, Color.WHITE)
		_px(mimg, 28, 14, 2, 3, dark)
		_px(mimg, 34, 14, 2, 3, dark)
		# mouth hole
		_px(mimg, 29, 24, 6, 3, skin)
		_px(mimg, 30, 25, 4, 1, dark)
		# flames on both sides (seen from the camera)
		var hts := [2, 4, 7, 5, 10, 10, 5, 7, 4, 2]
		for cx in [16, 48]:
			var c0: int = cx
			for k in 10:
				var hh: int = hts[k]
				_px(mimg, c0 - 5 + k, 27 - hh, 1, hh + 1, trim)
				_px(mimg, c0 - 5 + k, 27 - int(hh * 0.5), 1, int(hh * 0.5) + 1, hot)
		# back lacing over the seam
		var lace := Color(0.95, 0.95, 0.9)
		_px(mimg, 63, 11, 1, 19, mask.darkened(0.45))
		_px(mimg, 0, 11, 1, 19, mask.darkened(0.45))
		for r in range(11, 30):
			match r % 4:
				0:
					_px(mimg, 61, r, 1, 1, lace)
					_px(mimg, 2, r, 1, 1, lace)
				2:
					_px(mimg, 63, r, 1, 1, lace)
					_px(mimg, 0, r, 1, 1, lace)
				_:
					_px(mimg, 62, r, 1, 1, lace)
					_px(mimg, 1, r, 1, 1, lace)
		_px(mimg, 0, 30, 64, 2, trim)  # bottom hem
		return ImageTexture.create_from_image(mimg)

	var img := _new_img(64, 32, skin)
	_px(img, 0, 28, 64, 4, skin.darkened(0.12))   # under the jaw
	_px(img, 22, 17, 4, 10, skin.darkened(0.07))  # cheek shading
	_px(img, 38, 17, 4, 10, skin.darkened(0.07))
	if look.get("stubble", false):
		_px(img, 25, 22, 14, 7, shade.lerp(hair_c, 0.35))
	# brows, eyes, nose shading, stern mouth
	_px(img, 26, 12, 5, 2, hair_c)
	_px(img, 33, 12, 5, 2, hair_c)
	_px(img, 27, 14, 4, 2, Color.WHITE)
	_px(img, 33, 14, 4, 2, Color.WHITE)
	_px(img, 28, 14, 2, 2, dark)
	_px(img, 34, 14, 2, 2, dark)
	_px(img, 27, 16, 4, 1, shade)
	_px(img, 33, 16, 4, 1, shade)
	_px(img, 30, 19, 1, 3, shade)
	_px(img, 33, 19, 1, 3, shade)
	_px(img, 29, 25, 6, 1, dark)
	_px(img, 30, 26, 4, 1, shade)
	var stubble_tone := skin.lerp(hair_c, 0.3)
	match style:
		"flattop":
			_px(img, 0, 0, 64, 8, hair_c)
			_px(img, 0, 0, 20, 18, hair_c)      # back half
			_px(img, 44, 0, 20, 18, hair_c)
			_px(img, 20, 0, 3, 19, hair_c)      # sideburns
			_px(img, 41, 0, 3, 19, hair_c)
			_px(img, 23, 7, 18, 1, hair_c.lightened(0.15))
		"long":
			_px(img, 0, 0, 64, 9, hair_c)
			_px(img, 0, 0, 22, 32, hair_c)
			_px(img, 42, 0, 22, 32, hair_c)
			_px(img, 22, 0, 2, 27, hair_c)
			_px(img, 40, 0, 2, 27, hair_c)
		"mohawk":
			_px(img, 0, 0, 64, 11, stubble_tone)
			_px(img, 29, 0, 6, 11, hair_c)
			_px(img, 0, 0, 3, 15, hair_c)
			_px(img, 61, 0, 3, 15, hair_c)
	return ImageTexture.create_from_image(img)


# --- the model ------------------------------------------------------------------

func _build_body() -> void:
	var skin_c := _sat(skin_color, 1.12)
	var gear_c := _sat(gear_color)
	var trunk_c := _sat(trunk_color)
	var boot_src: Color = look.get("boot_color", gear_color)
	var boot_c := _sat(boot_src)
	var trim_src: Color = look.get("boot_trim", gear_color)
	var trim_c := _sat(trim_src)
	var hair_c: Color = look.get("hair_color", Color(0.15, 0.1, 0.07))
	var hair_style: String = look.get("hair", "none")
	var is_mask: bool = look.get("mask", false)
	var tights: bool = look.get("tights", false)
	var tights_pattern: String = look.get("tights_pattern", "")
	var trunk_pattern: String = look.get("trunk_pattern", "stripe")
	var initials: String = look.get("initials", "")
	var elbow_pads: bool = look.get("elbow_pads", false)
	var wrist_tape: bool = look.get("wrist_tape", true)

	var skin := _mat(skin_c)
	var skin_dark := _mat(skin_c.darkened(0.12))
	var gear := _mat(gear_c)
	var tape := _mat(Color(0.93, 0.93, 0.88))
	var hair := _mat(hair_c)
	var boots_plain := _mat(boot_c)
	var sole := _mat(boot_c.darkened(0.5))
	var torso_mat := _mat(Color.WHITE, _torso_texture(skin_c))
	var trunks_mat := _mat(Color.WHITE, _trunks_texture(trunk_c, gear_c, trunk_pattern, initials))
	var boot_mat := _mat(Color.WHITE, _boot_texture(boot_c, trim_c))
	var head_mat := _mat(Color.WHITE, _head_texture(skin_c, hair_c, hair_style))
	var head_solid := skin
	if is_mask:
		var mask_src: Color = look.get("mask_color", trunk_color)
		head_solid = _mat(_sat(mask_src))
	var legs_mat := skin
	if tights:
		if tights_pattern == "flames":
			legs_mat = _mat(Color.WHITE, _tights_texture(trunk_c, gear_c))
		else:
			legs_mat = _mat(trunk_c)
	var pad_mat := gear

	# Blob shadow (stays flat on the mat)
	var sh := CylinderMesh.new()
	sh.top_radius = 0.6
	sh.bottom_radius = 0.6
	sh.height = 0.01
	sh.radial_segments = 10
	var sh_mat := StandardMaterial3D.new()
	sh_mat.albedo_color = Color(0, 0, 0, 0.5)
	sh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_mesh(self, sh, Vector3(0, 0.03, 0), sh_mat)

	# pose_root = pelvis. Everything rotates around it.
	pose_root = _pivot(self, Vector3(0, STAND_Y, 0))
	hips = _pivot(pose_root, Vector3.ZERO)

	# Pelvis / trunks (back of the trunks is 0.195 behind the pelvis)
	_loft(hips, [
		Vector4(0.17, 0.285, 0.19, 0.0), Vector4(0.12, 0.29, 0.195, 0.0), Vector4(0.0, 0.28, 0.195, 0.0),
		Vector4(-0.1, 0.25, 0.18, 0.0), Vector4(-0.17, 0.16, 0.13, 0.0)], trunks_mat)

	# Torso: waist -> lats/ribs -> pecs -> shoulders -> traps (back reaches 0.205 behind)
	torso = _pivot(hips, Vector3(0, 0.12, 0))
	_loft(torso, [
		Vector4(0.64, 0.11, 0.09, -0.01), Vector4(0.58, 0.27, 0.15, -0.02), Vector4(0.48, 0.37, 0.2, 0.0),
		Vector4(0.34, 0.355, 0.215, 0.01), Vector4(0.2, 0.3, 0.19, 0.0), Vector4(0.0, 0.26, 0.17, 0.0)], torso_mat)

	# Neck + head (head ~0.33 wide x 0.36 tall x 0.35 deep, top ~2.03 m when standing)
	_loft(torso, [Vector4(0.72, 0.095, 0.095, 0.02), Vector4(0.52, 0.115, 0.11, 0.0)], skin, false, false)
	head = _pivot(torso, Vector3(0, 0.6, 0.02))
	_loft(head, [
		Vector4(0.36, 0.075, 0.085, -0.01), Vector4(0.32, 0.15, 0.16, -0.005), Vector4(0.22, 0.165, 0.175, 0.0),
		Vector4(0.12, 0.16, 0.172, 0.005), Vector4(0.05, 0.13, 0.15, 0.012), Vector4(0.0, 0.085, 0.1, 0.005)], head_mat)
	_box(head, Vector3(0.05, 0.065, 0.05), Vector3(0, 0.145, 0.172), head_solid)       # nose
	if hair_style != "long":
		_box(head, Vector3(0.04, 0.08, 0.06), Vector3(-0.168, 0.17, -0.01), head_solid)  # ears
		_box(head, Vector3(0.04, 0.08, 0.06), Vector3(0.168, 0.17, -0.01), head_solid)
	if not is_mask:
		match hair_style:
			"flattop":
				_box(head, Vector3(0.3, 0.09, 0.32), Vector3(0, 0.345, -0.005), hair)
			"long":
				_box(head, Vector3(0.3, 0.34, 0.07), Vector3(0, 0.13, -0.165), hair)
				_box(head, Vector3(0.34, 0.06, 0.3), Vector3(0, 0.33, -0.02), hair)
			"mohawk":
				_box(head, Vector3(0.06, 0.1, 0.32), Vector3(0, 0.36, -0.01), hair)

	# Arms: shoulder -> elbow -> fist
	var e_pad: Material = null
	if elbow_pads:
		e_pad = pad_mat
	var t_mat: Material = null
	if wrist_tape:
		t_mat = tape
	arm_l = _build_arm(-1, skin, skin_dark, t_mat, e_pad)
	arm_r = _build_arm(1, skin, skin_dark, t_mat, e_pad)

	# Legs: hip -> knee -> boot
	leg_l = _build_leg(-1, legs_mat, pad_mat, boot_mat, boots_plain, sole)
	leg_r = _build_leg(1, legs_mat, pad_mat, boot_mat, boots_plain, sole)


func _build_arm(side: int, skin: Material, skin_dark: Material, tape: Material, pad: Material) -> Node3D:
	var sh := _pivot(torso, Vector3(0.42 * side, 0.47, 0))
	_ball(sh, 0.13, Vector3(0.01 * side, -0.01, 0), skin)                                 # deltoid
	_loft(sh, [Vector4(0.03, 0.105, 0.105, 0.0), Vector4(-0.12, 0.115, 0.12, 0.01),
		Vector4(-0.34, 0.08, 0.085, 0.0)], skin)                                            # upper arm
	var el := _pivot(sh, Vector3(0, -0.32, 0))
	if side < 0:
		elbow_l = el
	else:
		elbow_r = el
	if pad != null:
		_loft(el, [Vector4(0.05, 0.1, 0.105, -0.005), Vector4(-0.05, 0.1, 0.105, -0.005)], pad)  # elbow pad
	_loft(el, [Vector4(0.02, 0.085, 0.085, 0.0), Vector4(-0.09, 0.095, 0.09, 0.005),
		Vector4(-0.27, 0.065, 0.065, 0.0)], skin)                                           # forearm
	if tape != null:
		_loft(el, [Vector4(-0.2, 0.08, 0.08, 0.0), Vector4(-0.28, 0.075, 0.075, 0.0)], tape)  # wrist tape
	_box(el, Vector3(0.13, 0.12, 0.14), Vector3(0, -0.33, 0.005), skin)                   # fist
	_box(el, Vector3(0.115, 0.035, 0.02), Vector3(0, -0.36, 0.08), skin_dark)            # knuckles
	return sh


func _build_leg(side: int, legs_mat: Material, pad: Material, boots: Material, boots_plain: Material, sole: Material) -> Node3D:
	# hip pivot at 0.89 m, knee at 0.46 m, sole at 0.0 m when standing straight
	var hp := _pivot(hips, Vector3(0.14 * side, -0.06, 0))
	_loft(hp, [Vector4(0.07, 0.135, 0.14, 0.0), Vector4(-0.12, 0.14, 0.15, 0.005),
		Vector4(-0.3, 0.115, 0.125, 0.005), Vector4(-0.45, 0.095, 0.1, 0.0)], legs_mat)    # thigh
	var kn := _pivot(hp, Vector3(0, -0.43, 0))
	if side < 0:
		knee_l = kn
	else:
		knee_r = kn
	_loft(kn, [Vector4(0.06, 0.112, 0.118, 0.012), Vector4(0.0, 0.122, 0.128, 0.016),
		Vector4(-0.07, 0.108, 0.115, 0.012)], pad)                                         # knee pad
	_loft(kn, [Vector4(0.0, 0.095, 0.1, 0.0), Vector4(-0.1, 0.1, 0.11, -0.01),
		Vector4(-0.3, 0.075, 0.08, 0.0)], legs_mat)                                        # shin
	_loft(kn, [Vector4(-0.16, 0.115, 0.122, 0.0), Vector4(-0.3, 0.102, 0.112, 0.0),
		Vector4(-0.4, 0.104, 0.118, 0.01)], boots, true, false)                            # boot shaft
	_box(kn, Vector3(0.17, 0.09, 0.27), Vector3(0, -0.405, 0.055), boots_plain)           # boot foot
	_box(kn, Vector3(0.18, 0.02, 0.285), Vector3(0, -0.45, 0.055), sole)                  # sole (bottom -0.46)
	return hp


# ---------------------------------------------------------------- helpers

func set_state(s: int) -> void:
	state = s
	state_time = 0.0
	hit_landed = false
	current_move_key = ""
	# Leaving the "free" states closes any reversal window that was open on us.
	if s != S.IDLE and s != S.WALK:
		reversal_window = 0.0
	if s != S.RUN:
		whipped = false
	if s != S.STUNNED:
		dazed = false
	if s != S.TIEUP_ATK:
		committed_move = ""
	if s == S.DOWN:
		ground_hits = 0
	if s == S.TIEUP_ATK or s == S.TIEUP_DEF:
		ai_tie_delay = randf_range(0.35, 0.85) * (1.5 - ai_skill)


func is_standing() -> bool:
	return state in [S.IDLE, S.WALK, S.RUN, S.PUNCH, S.RUN_ATTACK, S.STUNNED, S.TAUNT,
		S.WHIFF, S.GRAB_WINDUP, S.WHIPPING, S.STOMP]


func is_special_ready() -> bool:
	return spirit >= 100.0


func _flat_to_opponent() -> Vector3:
	var d := opponent.position - position
	d.y = 0
	return d


func _in_front(max_dist: float) -> bool:
	var d := _flat_to_opponent()
	var dist := d.length()
	if dist > max_dist:
		return false
	if dist < 0.01:
		return true
	return facing.dot(d / dist) > 0.25


func _opp_state() -> int:
	var os: int = opponent.state
	return os


## True when the opponent is in a neutral stance and can time a counter to our strike.
func _opp_can_counter() -> bool:
	var os := _opp_state()
	return os == S.IDLE or os == S.WALK


func _set_facing_angle(a: float) -> void:
	rotation.y = a
	facing = Vector3(sin(a), 0, cos(a))


func _face_opponent(delta: float) -> void:
	var d := _flat_to_opponent()
	if d.length() < 0.01:
		return
	_set_facing_angle(lerp_angle(rotation.y, atan2(d.x, d.z), clamp(delta * 10.0, 0.0, 1.0)))


func _snap_face_opponent() -> void:
	var d := _flat_to_opponent()
	if d.length() > 0.01:
		_set_facing_angle(atan2(d.x, d.z))


func _chest() -> Vector3:
	return global_position + Vector3(0, 1.4, 0)


func gain_spirit(v: float) -> void:
	spirit = clamp(spirit + v, 0.0, 100.0)


func take_damage(d: float) -> void:
	health = max(0.0, health - d)
	spirit = max(0.0, spirit - d * 0.4)


func _down_time() -> float:
	return 1.3 + (1.0 - health / 100.0) * 2.4


func _clamp_ring() -> void:
	position.x = clamp(position.x, -RING_CLAMP, RING_CLAMP)
	position.z = clamp(position.z, -RING_CLAMP, RING_CLAMP)
	position.y = 0.0


func _separate() -> void:
	if not is_standing() or not opponent.is_standing():
		return
	var d := position - opponent.position
	d.y = 0
	var dist := d.length()
	if dist < 0.85 and dist > 0.001:
		var push := d / dist * (0.85 - dist) * 0.5
		position += push
		opponent.position -= push


## Full spirit lights SPECIAL for SPECIAL_TIME seconds; unused, it drains back to 80.
func _update_special(delta: float) -> void:
	if spirit < 100.0:
		special_timer = 0.0
		return
	if special_timer <= 0.0:
		special_timer = SPECIAL_TIME
		announce.emit("%s is SUPERCHARGED!" % display_name)
		sfx.emit("taunt", 0.8, _chest())
	special_timer -= delta
	if special_timer <= 0.0:
		special_timer = 0.0
		spirit = SPECIAL_DRAIN_TO


# ---------------------------------------------------------------- main update

func tick(delta: float) -> void:
	state_time += delta
	anim_clock += delta
	if combo_timer > 0.0:
		combo_timer -= delta
	else:
		combo_hits = 0
	taunt_cooldown = maxf(0.0, taunt_cooldown - delta)
	reversal_lockout = maxf(0.0, reversal_lockout - delta)
	since_press += delta
	_update_special(delta)

	if is_cpu:
		_ai(delta)

	_handle_reversal_input(delta)

	match state:
		S.IDLE, S.WALK:
			_free_move(delta)
		S.RUN:
			_run(delta)
		S.PUNCH:
			_punch()
		S.RUN_ATTACK:
			_run_attack(delta)
		S.STUNNED:
			if state_time > stun_time:
				set_state(S.IDLE)
		S.WHIFF:
			if state_time > whiff_time:
				set_state(S.IDLE)
		S.GRAB_WINDUP:
			_grab_windup(delta)
		S.TIEUP_ATK:
			_tieup_attacker(delta)
		S.TIEUP_DEF:
			# Safety net: the attacker left the hold without taking us with them.
			if _opp_state() != S.TIEUP_ATK and state_time > 0.05:
				set_state(S.IDLE)
		S.WHIPPING:
			_whipping(delta)
		S.THROWING:
			if state_time >= throw_time + 0.15:
				set_state(S.IDLE)
		S.THROWN:
			_thrown()
		S.DOWN:
			if state_time > down_duration:
				set_state(S.GETTING_UP)
				last_hit_tier = ""  # back up: the last move no longer affects pins
		S.GETTING_UP:
			if state_time > 0.7:
				set_state(S.IDLE)
		S.STOMP:
			_stomp()
		S.GROUND_DROP:
			_ground_drop()
		S.PICKUP:
			_pickup()
		S.LIFTED:
			if state_time > 1.5:
				set_state(S.IDLE)  # safety: the lifter got interrupted
		S.PINNING:
			_pinning()
		S.PINNED:
			_pinned(delta)
		S.TAUNT:
			_taunt()

	_separate()
	_clamp_ring()
	_update_pose(delta)

	in_strike = false
	in_grapple = false
	in_run = false
	in_pin = false
	any_pressed = false


# ---------------------------------------------------------------- timed reversals
# An attacker that commits to a lock-up move, a punch or a running lariat opens a short
# window on the defender (open_reversal_window). Pressing GRAB/STRIKE inside it reverses
# (near-certain); pressing in a lock-up before it opens, or mashing right before it opens,
# locks reversals out for REVERSAL_LOCKOUT seconds.

func open_reversal_window(dur: float, kind: String) -> void:
	reversal_window = dur
	reversal_kind = kind
	reversal_age = 0.0
	ai_rev_decided = false
	if since_press < 0.2:
		reversal_lockout = maxf(reversal_lockout, REVERSAL_LOCKOUT)  # caught mashing


func _handle_reversal_input(delta: float) -> void:
	var pressed := in_grapple or in_strike
	if reversal_window > 0.0:
		reversal_age += delta
		if pressed:
			_attempt_timed_reversal()
			in_grapple = false
			in_strike = false
		else:
			reversal_window = maxf(0.0, reversal_window - delta)
	elif state == S.TIEUP_DEF and pressed:
		# Too early: the attacker hasn't committed to anything yet.
		reversal_lockout = REVERSAL_LOCKOUT
		in_grapple = false
		in_strike = false
	if pressed:
		since_press = 0.0


func _attempt_timed_reversal() -> void:
	var kind := reversal_kind
	reversal_window = 0.0
	if reversal_lockout > 0.0:
		return  # still locked out from mashing: the press is wasted
	var opp_hp: float = opponent.health
	var chance := 0.9
	match kind:
		"strong":
			chance = 0.97
		"whip":
			chance = 0.88
		"punch":
			chance = 0.85
		"lariat":
			chance = 0.8
	chance += (health - opp_hp) / 600.0
	if randf() >= chance:
		reversal_lockout = REVERSAL_LOCKOUT
		if not is_cpu:
			announce.emit("Reversal failed!")
		return
	var os := _opp_state()
	var dist := _flat_to_opponent().length()
	match kind:
		"grapple", "strong":
			if state == S.TIEUP_DEF and os == S.TIEUP_ATK:
				_snap_face_opponent()
				_do_move("hiptoss" if kind == "strong" else "armdrag")
		"whip":
			if state == S.TIEUP_DEF and os == S.TIEUP_ATK:
				_snap_face_opponent()
				sfx.emit("reversal", 0.6, _chest())
				_start_whip(facing, "REVERSAL! Whip reversed")
		"punch":
			if os == S.PUNCH and dist < 1.9:
				_snap_face_opponent()
				_do_move("armdrag")
		"lariat":
			if os == S.RUN_ATTACK and dist < 2.6:
				_snap_face_opponent()
				_do_move("rev_backdrop")


# ---------------------------------------------------------------- standing / running

func _free_move(delta: float) -> void:
	var dir := Vector3(in_move.x, 0, in_move.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	if dir.length() > 0.15:
		position += dir * WALK_SPEED * delta
		if state != S.WALK:
			set_state(S.WALK)
	elif state == S.WALK:
		set_state(S.IDLE)
	_face_opponent(delta)

	var opp_down := _opp_state() == S.DOWN
	var opp_dist := _flat_to_opponent().length()
	if in_run:
		run_dir = dir.normalized() if dir.length() > 0.3 else facing
		rope_bounces = 0
		set_state(S.RUN)
	elif in_strike:
		if opp_down and opp_dist < 1.7:
			_start_stomp()
		else:
			_start_punch()
	elif in_grapple:
		if opp_down and opp_dist < 1.6:
			_start_pickup()
		else:
			set_state(S.GRAB_WINDUP)  # tap vs hold decides weak / strong
	elif in_pin:
		_try_pin_or_taunt()


func _run(delta: float) -> void:
	if not whipped and in_move.length() > 0.3:
		var want := Vector3(in_move.x, 0, in_move.y).normalized()
		run_dir = run_dir.lerp(want, clamp(delta * 2.5, 0.0, 1.0)).normalized()
	elif whipped and rope_bounces >= 1:
		# Coming off the ropes after a whip: run back at whoever whipped us.
		var back := _flat_to_opponent()
		if back.length() > 0.6:
			var nd := run_dir.lerp(back.normalized(), clampf(delta * 6.0, 0.0, 1.0))
			if nd.length() > 0.1:
				run_dir = nd.normalized()
	position += run_dir * RUN_SPEED * delta
	_set_facing_angle(atan2(run_dir.x, run_dir.z))

	# Rebound off the ropes (visually touching them; the clamp stops us at RING_CLAMP).
	var bounced := false
	if absf(position.x) >= ROPE_BOUNCE and signf(position.x) == signf(run_dir.x):
		run_dir.x = -run_dir.x
		bounced = true
	if absf(position.z) >= ROPE_BOUNCE and signf(position.z) == signf(run_dir.z):
		run_dir.z = -run_dir.z
		bounced = true
	if bounced:
		rope_bounces += 1
		impact.emit(0.15)
		sfx.emit("rope", 0.5, global_position + Vector3(0, 1.2, 0))
		if rope_bounces > (1 if whipped else 2):
			set_state(S.IDLE)
			return

	if whipped:
		# Game-controlled run: no inputs. If nobody meets us, we bump into the whipper.
		if rope_bounces >= 1 and _flat_to_opponent().length() < 0.95:
			_whip_bump()
		elif state_time > 4.0:
			set_state(S.IDLE)
		return

	var opp_down := _opp_state() == S.DOWN
	var dist := _flat_to_opponent().length()
	if in_strike:
		if opp_down and dist < 2.6:
			_start_ground_drop("elbow_drop")
		else:
			_start_run_attack()
	elif in_grapple and opp_down and dist < 2.6:
		_start_ground_drop("knee_drop")
	elif in_run or in_grapple or state_time > 4.0:
		set_state(S.IDLE)


func _start_punch() -> void:
	set_state(S.PUNCH)
	current_move_key = "punch"
	if _opp_can_counter() and _in_front(1.6):
		opponent.open_reversal_window(PUNCH_HIT, "punch")


func _punch() -> void:
	if state_time >= PUNCH_HIT and not hit_landed:
		hit_landed = true
		if _in_front(1.35):
			combo_hits += 1
			combo_timer = 1.0
			var knock := combo_hits >= 3
			if opponent.receive_strike(self, 8.0 if knock else 4.0, knock) and knock:
				announce.emit("3-Hit Combo!")
				combo_hits = 0
	if state_time >= PUNCH_END:
		set_state(S.IDLE)


func _start_run_attack() -> void:
	set_state(S.RUN_ATTACK)
	current_move_key = "lariat"
	if _opp_can_counter() and _in_front(2.6):
		opponent.open_reversal_window(0.14, "lariat")


func _run_attack(delta: float) -> void:
	var speed: float = lerp(RUN_SPEED, 0.0, clamp(state_time / 0.45, 0.0, 1.0))
	position += run_dir * speed * delta
	if not hit_landed and state_time > 0.12 and state_time < 0.35:
		var d := _flat_to_opponent()
		if d.length() < 1.45 and (d.length() < 0.01 or facing.dot(d.normalized()) > 0.0):
			hit_landed = true
			if opponent.receive_strike(self, 11.0, true):
				announce.emit("Running Clothesline!")
	if state_time >= 0.55:
		set_state(S.IDLE)


## Called on the defender. Returns true if the strike connected.
func receive_strike(attacker: Node3D, dmg: float, knockdown: bool) -> bool:
	if not is_standing():
		return false
	var was_taunting := state == S.TAUNT
	take_damage(dmg)
	attacker.gain_spirit(dmg * 1.5)
	var away := position - attacker.position
	away.y = 0
	if away.length() > 0.01:
		position += away.normalized() * (0.6 if knockdown else 0.2)
	if knockdown:
		set_state(S.DOWN)
		down_duration = _down_time()
		last_hit_tier = "strike"
		impact.emit(0.5)
		sfx.emit("kick", 0.7, global_position + Vector3(0, 1.4, 0))
	else:
		set_state(S.STUNNED)
		stun_time = 0.35
		impact.emit(0.1)
		sfx.emit("punch", 0.35, global_position + Vector3(0, 1.5, 0))
	if was_taunting:
		announce.emit("Taunt cut short!")
	return true


# ---------------------------------------------------------------- ground attacks

func _start_stomp() -> void:
	set_state(S.STOMP)
	current_move_key = "stomp"
	_snap_face_opponent()


func _stomp() -> void:
	if state_time >= 0.22 and not hit_landed:
		hit_landed = true
		if _opp_state() == S.DOWN and _flat_to_opponent().length() < 1.9:
			var m: Dictionary = MOVES["stomp"]
			var dmg: float = m["dmg"]
			opponent.receive_ground_hit(self, dmg, "stomp")
	if state_time >= 0.5:
		set_state(S.IDLE)


func _start_ground_drop(key: String) -> void:
	set_state(S.GROUND_DROP)
	current_move_key = key
	drop_from = position
	var to := _flat_to_opponent()
	var target: Vector3 = opponent.position
	if to.length() > 0.4:
		target -= to.normalized() * 0.35
	drop_to = Vector3(target.x, 0.0, target.z)
	_snap_face_opponent()
	sfx.emit("whoosh", 0.45, _chest())


func _ground_drop() -> void:
	var t := clampf(state_time / 0.5, 0.0, 1.0)
	position = drop_from.lerp(drop_to, t)
	if t < 1.0:
		return
	var key := current_move_key
	var m: Dictionary = MOVES.get(key, MOVES["elbow_drop"])
	var dmg: float = m["dmg"]
	var landed := _opp_state() == S.DOWN and _flat_to_opponent().length() < 1.3
	if landed:
		opponent.receive_ground_hit(self, dmg, key)
		announce.emit(m["name"])
	else:
		take_damage(3.0)
		announce.emit("Missed!")
		impact.emit(0.2)
		sfx.emit("thud", 0.5, global_position + Vector3(0, 0.3, 0))
	# The dropper ends up on their own back for a moment either way.
	set_state(S.DOWN)
	last_hit_tier = ""
	down_duration = 0.6 if landed else 1.0


## Called on a downed defender by stomps / drops. Returns true if it connected.
func receive_ground_hit(attacker: Node3D, dmg: float, key: String) -> bool:
	if state != S.DOWN:
		return false
	take_damage(dmg)
	attacker.gain_spirit(dmg * 1.5)
	last_hit_tier = "ground"
	current_move_key = key  # what just hit us, so the body can jolt
	if ground_hits < 3:
		ground_hits += 1
		down_duration = maxf(down_duration, state_time + 0.8)
	var big := dmg >= 8.0
	impact.emit(0.4 if big else 0.15)
	sfx.emit("big_thud" if big else "thud", 0.9 if big else 0.45, global_position + Vector3(0, 0.3, 0))
	return true


func _start_pickup() -> void:
	set_state(S.PICKUP)
	current_move_key = "pickup"
	_snap_face_opponent()
	# Stand at lock-up distance so the lifted wrestler rises right in front of us.
	var op: Vector3 = opponent.position
	position = op - facing * LOCKUP_DIST
	opponent.set_state(S.LIFTED)
	sfx.emit("grab", 0.4, _chest())


func _pickup() -> void:
	if _opp_state() != S.LIFTED:
		set_state(S.IDLE)
		return
	if state_time >= 0.6:
		opponent.position = position + facing * LOCKUP_DIST
		opponent.set_state(S.STUNNED)
		opponent.stun_time = 1.2
		opponent.dazed = true
		opponent._snap_face_opponent()
		set_state(S.IDLE)


# ---------------------------------------------------------------- grapples

func _grab_windup(delta: float) -> void:
	_face_opponent(delta)
	if in_grapple_held:
		if state_time >= STRONG_GRAB_HOLD:
			_try_grapple(true)
	elif state_time >= 0.06:
		_try_grapple(false)


func _try_grapple(strong: bool) -> void:
	var os := _opp_state()
	var grabbable: bool = os in [S.IDLE, S.WALK, S.STUNNED, S.PUNCH, S.TAUNT, S.WHIFF, S.GRAB_WINDUP, S.STOMP]
	if _in_front(1.5) and grabbable:
		var free_lock: bool = opponent.dazed
		set_state(S.TIEUP_ATK)
		tie_strong = strong
		tie_free = free_lock
		current_move_key = "lockup_strong" if strong else "lockup"
		opponent.position = position + facing * LOCKUP_DIST
		opponent.set_state(S.TIEUP_DEF)
		opponent.tie_strong = strong
		opponent._snap_face_opponent()
		sfx.emit("grab", 0.7 if strong else 0.45, _chest())
	else:
		# Whiffed grab: off balance for a moment (longer for a committed strong grab).
		set_state(S.WHIFF)
		whiff_time = 0.6 if strong else 0.42
		current_move_key = "whiff_strong" if strong else "whiff"
		sfx.emit("whoosh", 0.25, _chest())


func _tieup_attacker(delta: float) -> void:
	if _opp_state() != S.TIEUP_DEF:
		set_state(S.IDLE)
		return
	if committed_move != "":
		# Move chosen: the defender's reversal window is running; then it happens.
		commit_timer -= delta
		if commit_timer <= 0.0:
			var k := committed_move
			committed_move = ""
			if k == "whip":
				_start_whip(commit_dir, "Irish Whip!")
			else:
				_do_move(k)
		return
	if state_time < (0.45 if tie_strong else 0.3):
		return  # collar-and-elbow struggle
	var dir_held := in_move.length() > 0.5
	var move := ""
	if in_run:
		move = "whip"
		commit_dir = Vector3(in_move.x, 0, in_move.y).normalized() if dir_held else facing
	elif in_grapple:
		if dir_held:
			if is_special_ready():
				move = "finisher"
			else:
				move = "neckbreaker" if tie_strong else "ddt"
		else:
			move = "spinebuster" if tie_strong else "slam"
	elif in_strike:
		if dir_held:
			move = "powerbomb" if tie_strong else "suplex"
		else:
			move = "piledriver" if tie_strong else "knee"
	if move != "":
		_commit(move)
	elif state_time > 2.4:
		# nobody committed: break the hold
		set_state(S.IDLE)
		opponent.set_state(S.IDLE)
		opponent.position += facing * 0.4


func _commit(move: String) -> void:
	committed_move = move
	commit_timer = STRONG_REVERSAL_WINDOW if tie_strong else REVERSAL_WINDOW
	current_move_key = move
	if not tie_free:
		var kind := "whip" if move == "whip" else ("strong" if tie_strong else "grapple")
		opponent.open_reversal_window(commit_timer, kind)


func _do_move(key: String) -> void:
	var m: Dictionary = MOVES[key]
	var tier: String = m.get("tier", "weak")
	var kind: String = m["kind"]
	var dmg: float = m["dmg"]
	announce.emit(m["name"])
	if key == "finisher":
		sfx.emit("finisher", 1.0, _chest())
	elif tier == "reversal":
		sfx.emit("reversal", 0.6, _chest())
	elif kind == "throw":
		sfx.emit("whoosh", 0.5, _chest())
	if key == "finisher":
		spirit = 0.0
		special_timer = 0.0
	gain_spirit(dmg * 1.5)
	opponent.reversal_window = 0.0
	if kind == "strike":
		# Knee lift: a lock-up strike (PUNCH state, current_move_key tells the animation).
		opponent.take_damage(dmg)
		opponent.set_state(S.STUNNED)
		opponent.stun_time = 0.7
		opponent.position += facing * 0.4
		impact.emit(0.25)
		sfx.emit("kick", 0.5, opponent.global_position + Vector3(0, 1.2, 0))
		set_state(S.PUNCH)
		current_move_key = key
		hit_landed = true
		return
	set_state(S.THROWING)
	current_move_key = key
	throw_time = m["time"]
	opponent.start_thrown(position + facing * float(m["land"]), m, key)


func start_thrown(land_pos: Vector3, m: Dictionary, key := "") -> void:
	set_state(S.THROWN)
	current_move_key = key
	last_hit_tier = m.get("tier", "weak")
	throw_from = position
	throw_to = Vector3(clamp(land_pos.x, -RING_HALF, RING_HALF), 0, clamp(land_pos.z, -RING_HALF, RING_HALF))
	throw_time = m["time"]
	throw_height = m["height"]
	throw_end_angle = -PI / 2 - (TAU if m["flip"] else 0.0)
	pending_damage = m["dmg"]


func _thrown() -> void:
	var t: float = clamp(state_time / throw_time, 0.0, 1.0)
	position = throw_from.lerp(throw_to, t)
	if t >= 1.0:
		var key := current_move_key
		take_damage(pending_damage)
		set_state(S.DOWN)
		current_move_key = key  # landed from this move (animation may vary the bump)
		down_duration = _down_time()
		pose_root.rotation.x = -PI / 2
		impact.emit(clamp(pending_damage / 20.0, 0.3, 1.2))
		sfx.emit("big_thud" if pending_damage >= 20.0 else "thud", clamp(pending_damage / 20.0, 0.3, 1.3), global_position + Vector3(0, 0.3, 0))


# ---------------------------------------------------------------- Irish whip

## Sends the opponent running toward the ropes in `dir`; we wait in WHIPPING for the rebound.
func _start_whip(dir: Vector3, label: String) -> void:
	set_state(S.WHIPPING)
	current_move_key = "whip"
	ai_whip_roll = randf()
	ai_whip_trigger = randf_range(1.2, 1.75)
	opponent.start_whipped(dir)
	announce.emit(label)
	sfx.emit("whoosh", 0.5, _chest())


func start_whipped(dir: Vector3) -> void:
	set_state(S.RUN)
	whipped = true
	rope_bounces = 0
	var d := Vector3(dir.x, 0, dir.z)
	run_dir = d.normalized() if d.length() > 0.01 else facing
	_set_facing_angle(atan2(run_dir.x, run_dir.z))


func _whipping(delta: float) -> void:
	var ws: bool = opponent.whipped
	if _opp_state() != S.RUN or not ws:
		set_state(S.IDLE)
		return
	_face_opponent(delta)
	var dist := _flat_to_opponent().length()
	var rb: int = opponent.rope_bounces
	var coming := rb >= 1
	if in_strike or in_grapple:
		if coming and dist < 2.2:
			if in_strike:
				_whip_clothesline()
			else:
				_do_move("powerslam" if in_move.length() > 0.5 else "backdrop")
		elif in_strike:
			_start_punch()  # swung too early
		else:
			set_state(S.WHIFF)
			whiff_time = 0.42
			current_move_key = "whiff"
	elif state_time > 4.5:
		set_state(S.IDLE)


func _whip_clothesline() -> void:
	var m: Dictionary = MOVES["clothesline"]
	var dmg: float = m["dmg"]
	set_state(S.PUNCH)
	current_move_key = "clothesline"
	hit_landed = true
	if opponent.receive_strike(self, dmg, true):
		announce.emit(m["name"])


## A whipped runner met nobody's move: both wrestlers stagger.
func _whip_bump() -> void:
	var other_up: bool = opponent.is_standing()
	set_state(S.STUNNED)
	stun_time = 0.5
	if other_up:
		opponent.take_damage(2.0)
		opponent.set_state(S.STUNNED)
		opponent.stun_time = 0.35
		var d := _flat_to_opponent()
		if d.length() > 0.01:
			opponent.position += d.normalized() * 0.3
	impact.emit(0.2)
	var op: Vector3 = opponent.global_position
	sfx.emit("thud", 0.5, (global_position + op) * 0.5 + Vector3(0, 1.2, 0))
	announce.emit("Collision!")


# ---------------------------------------------------------------- pins & taunts

func _try_pin_or_taunt() -> void:
	var os := _opp_state()
	if os == S.DOWN and _flat_to_opponent().length() < 2.0:
		set_state(S.PINNING)
		current_move_key = "cover"
		position = opponent.position
		_set_facing_angle(opponent.rotation.y + PI / 2)
		pin_count_value = 0
		opponent.set_state(S.PINNED)
		opponent.pin_escape = 0.0
		announce.emit("COVER!")
	elif taunt_cooldown <= 0.0:
		taunt_bonus = os == S.DOWN or os == S.GETTING_UP
		set_state(S.TAUNT)
		current_move_key = "taunt"
		taunt_cooldown = TAUNT_COOLDOWN
		sfx.emit("taunt", 0.6, _chest())


func _taunt() -> void:
	if state_time > TAUNT_TIME:
		gain_spirit(30.0 if taunt_bonus else 20.0)
		announce.emit("%s is fired up!" % display_name)
		set_state(S.IDLE)


func _pinning() -> void:
	if _opp_state() != S.PINNED:
		set_state(S.IDLE)  # safety: the cover was broken some other way
		return
	var c := int(state_time / PIN_COUNT_TIME)
	if c > pin_count_value:
		pin_count_value = c
		pin_count.emit(c)
		sfx.emit("count", 0.6, global_position + Vector3(0, 0.2, 0))
		if c >= 3:
			set_state(S.WIN)
			opponent.set_state(S.LOSE)
			won.emit()


## How much escape effort a kick-out takes: more when hurt, much more after a finisher.
func _pin_escape_needed() -> float:
	var need := PIN_ESCAPE_NEEDED * (1.0 + (1.0 - health / 100.0) * 0.8)
	match last_hit_tier:
		"finisher":
			need += PIN_ESCAPE_NEEDED * 1.3
		"strong":
			need += PIN_ESCAPE_NEEDED * 0.35
		"ground", "strike":
			need += PIN_ESCAPE_NEEDED * 0.1
	return need


func _pinned(delta: float) -> void:
	if is_cpu:
		pin_escape += delta * (health / 100.0) * 10.0 * randf_range(0.5, 1.5) * (0.8 + 0.4 * ai_skill)
	elif any_pressed:
		pin_escape += 0.3 + 0.9 * (health / 100.0)
	if pin_escape >= _pin_escape_needed() and _opp_state() == S.PINNING:
		var count: int = opponent.pin_count_value
		var near_fall := count >= 2
		if near_fall:
			announce.emit(NEAR_FALL_CALLS[randi() % NEAR_FALL_CALLS.size()])
			gain_spirit(8.0)  # the crowd rallies behind a near fall
		else:
			announce.emit("KICK OUT!")
		last_hit_tier = ""  # that move's effect is spent
		opponent.set_state(S.STUNNED)
		opponent.stun_time = 0.7
		opponent.position += opponent.facing * 1.0
		set_state(S.DOWN)
		down_duration = 0.4
		impact.emit(0.35 if near_fall else 0.2)
		sfx.emit("kickout", 1.0 if near_fall else 0.6, global_position + Vector3(0, 0.6, 0))


# ---------------------------------------------------------------- CPU AI
# The CPU fills the same in_* fields a human would. ai_skill (0..1) scales reaction delay,
# reversal rate and pin kick-out strength. Decisions are paced by ai_timer and ai_react so
# the CPU never mashes.

func _ai(delta: float) -> void:
	ai_timer -= delta
	ai_backoff -= delta
	ai_react -= delta
	ai_strafe_time -= delta
	in_move = Vector2.ZERO
	in_grapple_held = false
	var d := _flat_to_opponent()
	var dist := d.length()
	var toward := Vector2(d.x, d.z).normalized() if dist > 0.01 else Vector2.ZERO
	var os := _opp_state()
	var opp_hp: float = opponent.health
	var opp_standing: bool = opponent.is_standing()

	# Human-like reaction delay whenever the opponent's situation changes
	# (0 = on their feet, 1 = down, 2 = anything else; walking/punching don't count).
	var situation := 1 if os == S.DOWN else (0 if opp_standing else 2)
	if situation != ai_seen_state:
		ai_seen_state = situation
		ai_react = randf_range(0.12, 0.4) * (1.6 - ai_skill)

	# Timed reversal: decide once per window, then press at a random moment inside it.
	if reversal_window > 0.0:
		if not ai_rev_decided:
			ai_rev_decided = true
			ai_rev_go = randf() < _ai_reversal_chance()
			ai_rev_at = randf_range(0.03, maxf(0.04, reversal_window - 0.05))
		if ai_rev_go and reversal_age >= ai_rev_at:
			ai_rev_go = false
			in_grapple = true
		return

	match state:
		S.TIEUP_DEF, S.PINNED, S.LIFTED, S.PINNING:
			return
		S.GRAB_WINDUP:
			in_grapple_held = ai_strong_grab
			return
		S.TIEUP_ATK:
			if committed_move == "" and state_time > ai_tie_delay:
				_ai_lockup_move(toward)
			return
		S.WHIPPING:
			var rb: int = opponent.rope_bounces
			if ai_whip_roll <= 1.0 and rb >= 1 and dist < ai_whip_trigger:
				if ai_whip_roll < 0.45:
					in_strike = true
				elif ai_whip_roll < 0.85:
					in_grapple = true
					if randf() < 0.5:
						in_move = toward
				ai_whip_roll = 2.0  # decided (>= 0.85: just wait for the collision)
			return
		S.RUN:
			if whipped:
				return
			if os == S.DOWN:
				if dist < 2.3:
					if randf() < 0.4:
						in_grapple = true  # knee drop
					else:
						in_strike = true   # elbow drop
				else:
					in_move = toward
			elif dist < 1.9 and opp_standing:
				in_strike = true
			elif rope_bounces >= 1:
				in_move = toward  # off the ropes: home in
			return

	if state != S.IDLE and state != S.WALK:
		return
	var can_act := ai_react <= 0.0 and ai_timer <= 0.0

	if os == S.DOWN:
		_ai_vs_downed(dist, toward, opp_hp, can_act)
		return
	if not opp_standing:
		# Getting up, flying through the air, ...: line up, press nothing.
		if dist > 1.8:
			in_move = toward
		return
	if ai_backoff > 0.0:
		in_move = -toward
		return
	if dist > 1.3:
		_ai_approach(dist, toward, can_act)
		return
	if can_act:
		ai_timer = randf_range(0.45, 1.0) * (1.4 - 0.6 * ai_skill)
		var r := randf()
		if r < 0.28:
			in_grapple = true
			ai_strong_grab = false
		elif r < 0.46:
			in_grapple = true
			ai_strong_grab = true
		elif r < 0.8:
			in_strike = true
		elif r < 0.9:
			ai_backoff = 0.45
		else:
			_ai_start_strafe()


func _ai_approach(dist: float, toward: Vector2, can_act: bool) -> void:
	if ai_strafe_time > 0.0 and dist < 3.4:
		# Circle the opponent instead of beelining.
		var perp := Vector2(-toward.y, toward.x) * ai_strafe_dir
		in_move = (toward * 0.3 + perp).normalized() * 0.85
	else:
		in_move = toward
	if not can_act:
		return
	ai_timer = randf_range(0.5, 1.1)
	var r := randf()
	if dist > 3.6 and r < 0.25:
		in_run = true  # charge in for a lariat
		in_move = toward
	elif dist > 1.6 and dist < 3.4 and r < 0.4:
		_ai_start_strafe()
	elif dist > 1.6 and dist < 3.0 and r < 0.5:
		in_run = true  # hit the ropes behind us and come back
		in_move = -toward


func _ai_start_strafe() -> void:
	ai_strafe_time = randf_range(0.6, 1.3)
	ai_strafe_dir = -1.0 if randf() < 0.5 else 1.0


func _ai_vs_downed(dist: float, toward: Vector2, opp_hp: float, can_act: bool) -> void:
	var tier: String = opponent.last_hit_tier
	var pin_worthy := opp_hp < 55.0 or tier == "finisher"
	if pin_worthy:
		if dist > 1.6:
			in_move = toward
		elif can_act:
			ai_timer = 0.4
			if randf() < 0.55 + 0.4 * ai_skill:
				in_pin = true
			else:
				in_strike = true  # one more stomp first
		return
	if dist > 3.0:
		if can_act:
			ai_timer = randf_range(0.6, 1.0)
			var r := randf()
			if r < 0.4 and taunt_cooldown <= 0.0:
				in_pin = true  # far away: taunt to the crowd
			elif r < 0.65:
				in_run = true  # charge in for an elbow / knee drop
				in_move = toward
			else:
				in_move = toward
		else:
			in_move = toward * 0.7
		return
	if dist > 1.5:
		in_move = toward
		return
	if can_act:
		ai_timer = randf_range(0.45, 0.85)
		var r := randf()
		if r < 0.45:
			in_strike = true   # stomp
		elif r < 0.75:
			in_grapple = true  # pick them up for more punishment
		elif r < 0.85:
			in_pin = true      # cheeky early cover


func _ai_lockup_move(toward: Vector2) -> void:
	var r := randf()
	if is_special_ready() and r < 0.75:
		in_grapple = true
		in_move = toward  # finisher
		return
	if r < 0.2:
		in_run = true  # Irish whip
	elif r < 0.5:
		in_grapple = true
		if randf() < 0.5:
			in_move = toward
	else:
		in_strike = true
		if randf() < 0.5:
			in_move = toward


func _ai_reversal_chance() -> float:
	var c := 0.1 + 0.5 * ai_skill
	if reversal_kind == "strong":
		c += 0.1
	return clampf(c, 0.0, 0.95)


# ---------------------------------------------------------------- procedural animation

func _update_pose(delta: float) -> void:
	var t := state_time
	var al := Vector3(-0.35, 0, -0.15)
	var ar := Vector3(-0.35, 0, 0.15)
	var ll := Vector3.ZERO
	var lr := Vector3.ZERO
	var hip := Vector3.ZERO
	var el_l := Vector3(-0.6, 0, 0)  # elbows: -x bends the forearm forward/up
	var el_r := Vector3(-0.6, 0, 0)
	var kn_l := 0.12  # knees: +x bends the shin back
	var kn_r := 0.12
	var root_x := 0.0
	var root_y := STAND_Y  # pelvis height (pose_root sits at the pelvis)
	var direct := false

	match state:
		S.IDLE:
			var b := sin(anim_clock * 3.0)
			al.x = -0.4 + b * 0.06
			ar.x = -0.4 - b * 0.06
			el_l.x = -1.25
			el_r.x = -1.25
			hip.x = 0.14
			ll.x = -0.15
			lr.x = -0.35
			kn_l = 0.35
			kn_r = 0.45
		S.WALK:
			var s := sin(anim_clock * 9.0)
			ll.x = s * 0.6
			lr.x = -s * 0.6
			al.x = -0.4 - s * 0.45
			ar.x = -0.4 + s * 0.45
			el_l.x = -1.0
			el_r.x = -1.0
			kn_l = 0.1 + max(0.0, s) * 0.8
			kn_r = 0.1 + max(0.0, -s) * 0.8
		S.RUN:
			var s := sin(anim_clock * 15.0)
			ll.x = s * 1.0
			lr.x = -s * 1.0
			al.x = -0.4 - s * 0.9
			ar.x = -0.4 + s * 0.9
			el_l.x = -1.5
			el_r.x = -1.5
			kn_l = 0.2 + max(0.0, s) * 1.4
			kn_r = 0.2 + max(0.0, -s) * 1.4
			hip.x = 0.3
		S.PUNCH:
			var p: float = clamp(t / PUNCH_HIT, 0.0, 1.0) if t < PUNCH_HIT else clamp(1.0 - (t - PUNCH_HIT) / (PUNCH_END - PUNCH_HIT), 0.0, 1.0)
			ar.x = lerp(-0.6, -1.65, p)
			al.x = -0.6
			el_r.x = lerp(-1.4, -0.05, p)
			el_l.x = -1.4
			kn_l = 0.3
			kn_r = 0.3
			hip.y = 0.45 * p
			hip.x = 0.15 * p
		S.RUN_ATTACK:
			al.z = -1.5
			ar.z = 1.5
			el_l.x = 0.0
			el_r.x = 0.0
			hip.x = 0.3
			ll.x = 0.5
			lr.x = -0.4
			kn_r = 0.6
		S.STUNNED:
			hip.x = -0.35
			al.x = 0.4
			ar.x = 0.3
			el_l.x = -0.3
			el_r.x = -0.3
			kn_l = 0.35
			kn_r = 0.35
		S.TIEUP_ATK, S.TIEUP_DEF:
			al = Vector3(-1.35, 0, 0.3)
			ar = Vector3(-1.35, 0, -0.3)
			hip.x = 0.4
			hip.z = sin(anim_clock * 18.0) * 0.05
			ll.x = 0.35
			lr.x = -0.35
			el_l.x = -0.75
			el_r.x = -0.75
			kn_l = 0.5
			kn_r = 0.3
		S.THROWING:
			var p: float = sin(clamp(t / throw_time, 0.0, 1.0) * PI)
			al.x = lerp(-1.4, -3.0, p)
			ar.x = lerp(-1.4, -3.0, p)
			hip.x = lerp(0.3, -0.45, p)
			el_l.x = -0.4
			el_r.x = -0.4
			kn_l = 0.3
			kn_r = 0.3
		S.THROWN:
			var p: float = clamp(t / throw_time, 0.0, 1.0)
			root_x = lerp(0.0, throw_end_angle, p)
			root_y = lerpf(STAND_Y, LIE_Y, p) + sin(p * PI) * throw_height
			al.z = -1.3
			ar.z = 1.3
			el_l.x = -0.3
			el_r.x = -0.3
			kn_l = 0.7
			kn_r = 0.3
			direct = true
		S.DOWN, S.PINNED, S.LOSE:
			root_x = -PI / 2
			root_y = LIE_Y
			al = Vector3(0, 0, -0.7)
			ar = Vector3(0, 0, 0.7)
			ll.z = -0.2
			lr.z = 0.2
			ll.x = -0.6
			kn_l = 1.1
			el_l.x = -0.2
			el_r.x = -0.2
			if state == S.PINNED:
				al.x = sin(anim_clock * 12.0) * 0.4
				ar.x = -sin(anim_clock * 12.0) * 0.4
		S.GETTING_UP:
			var p: float = clamp(t / 0.7, 0.0, 1.0)
			root_x = lerp(-PI / 2, 0.0, p * p)
			root_y = lerpf(LIE_Y, STAND_Y, p)
			al.x = -0.8
			ar.x = -0.8
			ll.x = lerp(-1.2, 0.0, p)
			lr.x = lerp(-0.4, 0.0, p)
			kn_l = lerp(1.6, 0.1, p)
			kn_r = lerp(1.0, 0.1, p)
			direct = true
		S.PINNING:
			root_x = PI / 2 * 0.95
			root_y = PIN_Y
			al.x = -0.6
			ar.x = -0.6
			el_l.x = -0.9
			el_r.x = -0.9
			kn_l = 0.9
			kn_r = 0.9
		S.TAUNT, S.WIN:
			# double-bicep flex
			al = Vector3(0, 0, -1.45)
			ar = Vector3(0, 0, 1.45)
			el_l = Vector3(0, 0, -1.6)
			el_r = Vector3(0, 0, 1.6)
			kn_l = 0.25
			kn_r = 0.25
			root_y = STAND_Y + abs(sin(t * 6.0)) * 0.15
			hip.y = sin(t * 3.0) * 0.3
		# ---- minimal poses for the gameplay states added later (animation pass will refine)
		S.GRAB_WINDUP:
			# reaching forward for the collar-and-elbow
			al = Vector3(-1.3, 0, 0.2)
			ar = Vector3(-1.3, 0, -0.2)
			el_l.x = -0.5
			el_r.x = -0.5
			hip.x = 0.3
			ll.x = 0.3
			lr.x = -0.3
			kn_l = 0.45
			kn_r = 0.35
		S.WHIFF:
			# lunged at nothing: stumbling forward
			hip.x = 0.6
			al = Vector3(-1.0, 0, -0.3)
			ar = Vector3(-1.0, 0, 0.3)
			el_l.x = -0.1
			el_r.x = -0.1
			ll.x = 0.5
			lr.x = -0.2
			kn_l = 0.6
			kn_r = 0.3
		S.WHIPPING:
			# right arm extended after flinging the opponent away
			ar = Vector3(-1.4, 0, 0.2)
			el_r.x = 0.0
			al.x = -0.5
			el_l.x = -1.0
			hip.x = 0.15
			kn_l = 0.35
			kn_r = 0.35
		S.STOMP:
			var p: float = sin(clamp(t / 0.4, 0.0, 1.0) * PI)
			lr.x = -1.2 * p
			kn_r = 0.2 + 1.3 * p
			kn_l = 0.3
			al.z = -0.4
			ar.z = 0.4
			hip.x = 0.25
		S.GROUND_DROP:
			# leap and come down across the opponent, elbow / knee first
			var p: float = clamp(t / 0.5, 0.0, 1.0)
			root_x = lerp(0.0, -PI / 2 * 0.8, p)
			root_y = lerpf(STAND_Y, LIE_Y + 0.15, p) + sin(p * PI) * 0.6
			ar = Vector3(0, 0, 1.6)
			el_r = Vector3(-2.0, 0, 0)
			al = Vector3(-0.6, 0, -0.5)
			ll.x = -0.6
			kn_l = 1.2
			kn_r = 0.4
			direct = true
		S.PICKUP:
			# bent over grabbing the head, then straightening up
			var p: float = clamp(t / 0.6, 0.0, 1.0)
			hip.x = lerp(0.9, 0.2, p)
			al.x = lerp(-1.5, -1.2, p)
			ar.x = lerp(-1.5, -1.2, p)
			el_l.x = -0.6
			el_r.x = -0.6
			kn_l = lerp(0.8, 0.3, p)
			kn_r = lerp(0.8, 0.3, p)
		S.LIFTED:
			# hauled from the mat to a limp standing position
			var p: float = clamp(t / 0.6, 0.0, 1.0)
			root_x = lerp(-PI / 2, 0.0, p * p)
			root_y = lerpf(LIE_Y, STAND_Y - 0.05, p)
			al = Vector3(0.2, 0, -0.3)
			ar = Vector3(0.2, 0, 0.3)
			el_l.x = -0.2
			el_r.x = -0.2
			hip.x = 0.35
			kn_l = lerp(1.2, 0.4, p)
			kn_r = lerp(1.0, 0.4, p)
			direct = true

	var k: float = clamp(delta * 14.0, 0.0, 1.0)
	arm_l.rotation = arm_l.rotation.lerp(al, k)
	arm_r.rotation = arm_r.rotation.lerp(ar, k)
	leg_l.rotation = leg_l.rotation.lerp(ll, k)
	leg_r.rotation = leg_r.rotation.lerp(lr, k)
	hips.rotation = hips.rotation.lerp(hip, k)
	elbow_l.rotation = elbow_l.rotation.lerp(el_l, k)
	elbow_r.rotation = elbow_r.rotation.lerp(el_r, k)
	knee_l.rotation.x = lerp(knee_l.rotation.x, kn_l, k)
	knee_r.rotation.x = lerp(knee_r.rotation.x, kn_r, k)
	if direct:
		pose_root.rotation.x = root_x
		pose_root.position.y = root_y
	else:
		pose_root.rotation.x = lerp(pose_root.rotation.x, root_x, k)
		pose_root.position.y = lerp(pose_root.position.y, root_y, k)

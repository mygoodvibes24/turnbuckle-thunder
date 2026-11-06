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
const REVERSAL_WINDOW := 0.4  # defender's timing window after a weak-grapple commit
const STRONG_REVERSAL_WINDOW := 0.5  # strong grapples are slower, so easier to read
const REVERSAL_LOCKOUT := 0.5 # pressing too early locks reversals out for this long
const PUNCH_HIT := 0.18       # punch contact time (also its reversal window, CPU defenders only)
const LARIAT_REVERSAL_WINDOW := 0.35  # human defender's window against a running lariat
const REVERSAL_EARLY := 0.15  # a press this soon before a window opens counts as mashing
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
var rev_tell: Label3D  # "!" over our head while a reversal window is open on us


func setup(p_name: String, p_look: Dictionary, p_cpu: bool) -> void:
	display_name = p_name
	look = p_look
	gear_color = look.get("gear", Color.RED)
	trunk_color = look.get("trunks", Color.BLACK)
	skin_color = look.get("skin", Color(0.86, 0.64, 0.48))
	is_cpu = p_cpu
	_build_body()
	_build_rev_tell()


## The visible tell for timed reversals: a bold yellow "!" ~0.6 m above the head.
func _build_rev_tell() -> void:
	rev_tell = Label3D.new()
	rev_tell.text = "!"
	var bold := FontVariation.new()
	bold.variation_embolden = 1.2
	rev_tell.font = bold
	rev_tell.font_size = 96
	rev_tell.pixel_size = 0.006
	rev_tell.modulate = Color(1.0, 0.9, 0.1)
	rev_tell.outline_modulate = Color(0.1, 0.05, 0.0)
	rev_tell.outline_size = 18
	rev_tell.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	rev_tell.no_depth_test = true
	rev_tell.position = Vector3(0, 2.65, 0)
	rev_tell.visible = false
	add_child(rev_tell)


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
	var trunks_mi := _loft(hips, [
		Vector4(0.17, 0.285, 0.19, 0.0), Vector4(0.12, 0.29, 0.195, 0.0), Vector4(0.0, 0.28, 0.195, 0.0),
		Vector4(-0.1, 0.25, 0.18, 0.0), Vector4(-0.17, 0.16, 0.13, 0.0)], trunks_mat)
	trunks_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Torso: waist -> lats/ribs -> pecs -> shoulders -> traps (back reaches 0.205 behind)
	torso = _pivot(hips, Vector3(0, 0.12, 0))
	var torso_mi := _loft(torso, [
		Vector4(0.64, 0.11, 0.09, -0.01), Vector4(0.58, 0.27, 0.15, -0.02), Vector4(0.48, 0.37, 0.2, 0.0),
		Vector4(0.34, 0.355, 0.215, 0.01), Vector4(0.2, 0.3, 0.19, 0.0), Vector4(0.0, 0.26, 0.17, 0.0)], torso_mat)
	torso_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
	var thigh := _loft(hp, [Vector4(0.07, 0.135, 0.14, 0.0), Vector4(-0.12, 0.14, 0.15, 0.005),
		Vector4(-0.3, 0.115, 0.125, 0.005), Vector4(-0.45, 0.095, 0.1, 0.0)], legs_mat)    # thigh
	thigh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var kn := _pivot(hp, Vector3(0, -0.43, 0))
	if side < 0:
		knee_l = kn
	else:
		knee_r = kn
	_loft(kn, [Vector4(0.06, 0.112, 0.118, 0.012), Vector4(0.0, 0.122, 0.128, 0.016),
		Vector4(-0.07, 0.108, 0.115, 0.012)], pad)                                         # knee pad
	var shin := _loft(kn, [Vector4(0.0, 0.095, 0.1, 0.0), Vector4(-0.1, 0.1, 0.11, -0.01),
		Vector4(-0.3, 0.075, 0.08, 0.0)], legs_mat)                                        # shin
	shin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	# Punch windows are CPU-only and too short to read, so they get no tell.
	rev_tell.visible = reversal_window > 0.0 and reversal_kind != "punch"

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
# (near-certain); pressing within REVERSAL_EARLY before it opens (mashing) locks
# reversals out for REVERSAL_LOCKOUT seconds.

func open_reversal_window(dur: float, kind: String) -> void:
	reversal_window = dur
	reversal_kind = kind
	reversal_age = 0.0
	ai_rev_decided = false
	if since_press < REVERSAL_EARLY:
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
		# Too early: the attacker hasn't committed yet. The press is wasted; it only
		# locks reversals out if it lands within REVERSAL_EARLY of the commit.
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
	# Only a CPU defender gets a punch-reversal window: for a human it is below
	# reaction time and just flickers "REVERSE!" on every jab.
	if opponent.is_cpu and _opp_can_counter() and _in_front(1.6):
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
		opponent.open_reversal_window(0.14 if opponent.is_cpu else LARIAT_REVERSAL_WINDOW, "lariat")


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
	# Visual throw path: keyframed in the thrower's frame (see _throw_keys).
	var tp: Vector3 = opponent.position
	var ty: float = opponent.rotation.y
	throw_origin = Vector3(tp.x, 0.0, tp.z)
	throw_yaw0 = ty
	throw_yaw_start = wrapf(rotation.y - ty, -PI, PI)


func _thrown() -> void:
	var t: float = clamp(state_time / throw_time, 0.0, 1.0)
	_throw_sample(t)  # keyframed path: sets position (ends exactly at throw_to)
	if t >= 1.0:
		var key := current_move_key
		position = throw_to
		take_damage(pending_damage)
		set_state(S.DOWN)
		current_move_key = key  # landed from this move (animation may vary the bump)
		down_duration = _down_time()
		# Lying on the back, oriented as the throw left us (DOWN keeps this facing).
		_set_facing_angle(throw_yaw0 + throw_land_yaw)
		pose_root.rotation = Vector3(-PI / 2, 0.0, 0.0)
		pose_root.position = Vector3(0.0, LIE_Y, 0.0)
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
		# Lie across the opponent: chest over their chest, perpendicular, from our side.
		var oyaw: float = opponent.rotation.y
		var ofwd := Vector3(sin(oyaw), 0.0, cos(oyaw))  # their head lies toward -ofwd
		var opos: Vector3 = opponent.position
		var chest := opos - ofwd * 0.42
		var perp := Vector3(ofwd.z, 0.0, -ofwd.x)
		if perp.dot(chest - position) < 0.0:
			perp = -perp
		_set_facing_angle(atan2(perp.x, perp.z))
		position = chest - perp * 0.42
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
			# Stand up beside the loser, not inside their torso.
			position -= Vector3(facing.x, 0.0, facing.z) * 0.8
			_clamp_ring()
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

	if state == S.GRAB_WINDUP:
		in_grapple_held = ai_strong_grab  # set before any early return, or strong grabs turn weak

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
	elif reversal_kind == "punch":
		c = 0.05 + 0.15 * ai_skill
	return clampf(c, 0.0, 0.95)


# ---------------------------------------------------------------- procedural animation
# Every frame a per-state _pose_* function fills the pose targets (pt_*), which the body
# then eases toward with per-group rates: fast for strikes, loose for bumps so the limbs
# flop and follow through. Standing poses derive the pelvis height from the leg angles
# (_leg_drop) so the soles stay on the mat; crouches and kneels plant the feet with
# _plant_knee; hands that hold something use the two-bone reach (_reach).
#
# Throws are keyframed in the THROWER's frame (f = forward, s = sideways, y = pelvis
# height) with an orientation quaternion per key, so the victim can tumble around any
# axis; the last key always lies on the back at throw_to, matching the DOWN pose.

const EASE_SMOOTH := 0
const EASE_IN := 1
const EASE_OUT := 2

# pose targets
var pt_al := Vector3.ZERO
var pt_ar := Vector3.ZERO
var pt_el_l := Vector3.ZERO
var pt_el_r := Vector3.ZERO
var pt_ll := Vector3.ZERO
var pt_lr := Vector3.ZERO
var pt_kn_l := 0.0
var pt_kn_r := 0.0
var pt_tor := Vector3.ZERO
var pt_hd := Vector3.ZERO
var pt_hip := Vector3.ZERO
var pt_root_rot := Vector3.ZERO
var pt_root_pos := Vector3(0, STAND_Y, 0)
var pt_root_dy := 0.0
var pt_auto_height := false
var pt_root_direct := false
var pt_hip_y_direct := false
var pt_use_basis := false
var pt_breath := 0.0
var r_body := 12.0
var r_limb := 14.0
var r_root := 12.0

# animation bookkeeping (never read by gameplay)
var _gait := 0.0
var _walk_f := 0.0
var _walk_s := 0.0
var _style := -1
var _pose_prev_state := -1
var _entry_state := -1
var _entry_root_x := 0.0
var _entry_root_y := STAND_Y
var _seen_health := 100.0
var _hit_clock := -10.0

# throw path (set in start_thrown, sampled in _thrown)
var throw_origin := Vector3.ZERO   # thrower position
var throw_yaw0 := 0.0              # thrower facing angle: the frame the keys live in
var throw_yaw_start := PI          # our yaw relative to that frame when the throw began
var throw_land_yaw := 0.0          # our relative yaw once lying on the back
var throw_pose_y := STAND_Y
var throw_pose_q := Quaternion.IDENTITY


# --- small math helpers ---------------------------------------------------------------

func _ease_in(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c


func _ease_out(x: float) -> float:
	var c := 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - c * c


func _smooth(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


func _seg(x: float, a: float, b: float) -> float:
	return clampf((x - a) / maxf(b - a, 0.0001), 0.0, 1.0)


## 0 -> 1 -> 0 over [a, b].
func _hump(x: float, a: float, b: float) -> float:
	return sin(_seg(x, a, b) * PI)


## Pelvis-to-sole height of a leg swung forward by a (= -rotation.x), knee bent back by b.
func _leg_drop(a: float, b: float, z := 0.0) -> float:
	return 0.06 + (0.43 * cos(a) + 0.46 * cos(a - b)) * cos(z)


## Knee bend that puts the sole on the mat, for a pelvis at height y, body pitch rp
## (pose_root.rotation.x) and thigh swing lx (leg rotation.x).
func _plant_knee(y: float, rp: float, lx: float) -> float:
	var a := -(lx + rp)  # absolute thigh angle, forward of straight down
	var knee_y := y - 0.06 * cos(rp) - 0.43 * cos(a)
	if knee_y >= 0.46:
		return clampf(a, 0.0, 2.7)
	return clampf(a + acos(clampf(knee_y / 0.46, 0.0, 1.0)), 0.0, 2.7)


func _qe(yaw: float, pitch: float, roll := 0.0) -> Quaternion:
	return Quaternion(Basis.from_euler(Vector3(pitch, yaw, roll)))


## Wrestling stance; c = crouch 0..1. Left foot leads, feet apart, pelvis from the legs.
func _stance(c: float) -> void:
	pt_ll = Vector3(-(0.25 + 0.2 * c), 0.0, -0.12)
	pt_lr = Vector3(-(0.05 + 0.15 * c), 0.0, 0.12)
	pt_kn_l = 0.5 + 0.5 * c
	pt_kn_r = 0.35 + 0.45 * c
	pt_auto_height = true


## Explicit pelvis height / pitch with both feet planted.
func _legs_for(y: float, rp: float, lx_l: float, lx_r: float) -> void:
	pt_auto_height = false
	pt_root_pos.y = y
	pt_root_rot.x = rp
	pt_ll.x = lx_l
	pt_lr.x = lx_r
	pt_kn_l = _plant_knee(y, rp, lx_l)
	pt_kn_r = _plant_knee(y, rp, lx_r)


## Stance(c) blended by w toward a planted pose at pelvis height y / pitch rp.
func _legs_blend(c: float, y: float, rp: float, lx_l: float, lx_r: float, w: float) -> void:
	_stance(c)
	if w <= 0.001:
		return
	var sy := maxf(_leg_drop(-pt_ll.x, pt_kn_l, pt_ll.z), _leg_drop(-pt_lr.x, pt_kn_r, pt_lr.z))
	_legs_for(lerpf(sy, y, w), rp * w, lerpf(pt_ll.x, lx_l, w), lerpf(pt_lr.x, lx_r, w))


## Two-bone reach: aims an arm so the fist lands on a world-space point (or points at it
## when out of reach). w blends from the current targets.
func _reach(left: bool, target: Vector3, w := 1.0) -> void:
	var arm: Node3D = arm_l if left else arm_r
	var v := torso.to_local(target) - arm.position
	var dist := v.length()
	if dist < 0.05:
		return
	var d := v / dist
	var b := asin(clampf(d.x, -1.0, 1.0))
	var a := atan2(-d.z, -d.y)
	if a > 1.6:
		a -= TAU
	var r := clampf(dist, 0.25, 0.64)
	var bend := PI - acos(clampf((0.2113 - r * r) / 0.2112, -1.0, 1.0))
	var off := acos(clampf((0.1024 + r * r - 0.1089) / (0.64 * r), -1.0, 1.0))
	var sh := Vector3(a + off, 0.0, b)
	var el := Vector3(-bend, 0.0, 0.0)
	if left:
		pt_al = pt_al.lerp(sh, w)
		pt_el_l = pt_el_l.lerp(el, w)
	else:
		pt_ar = pt_ar.lerp(sh, w)
		pt_el_r = pt_el_r.lerp(el, w)


## Both hands onto two points, each hand taking the nearer one (no crossed arms).
func _reach_pair(p1: Vector3, p2: Vector3, w := 1.0) -> void:
	var sl := arm_l.global_position
	if sl.distance_squared_to(p1) + arm_r.global_position.distance_squared_to(p2) <= \
			sl.distance_squared_to(p2) + arm_r.global_position.distance_squared_to(p1):
		_reach(true, p1, w)
		_reach(false, p2, w)
	else:
		_reach(true, p2, w)
		_reach(false, p1, w)


## Arms hanging straight down in world space, given the body's total forward pitch.
func _hang_arms(pitch: float, spread: float) -> void:
	pt_al = Vector3(-pitch, 0.0, -spread)
	pt_ar = Vector3(-pitch, 0.0, spread)
	pt_el_l = Vector3(-0.2, 0.0, 0.0)
	pt_el_r = Vector3(-0.2, 0.0, 0.0)


func _opp_node(n: String) -> Node3D:
	var o: Node3D = opponent.get(n)
	return o


# --- main --------------------------------------------------------------------------

func _pose_reset() -> void:
	pt_al = Vector3(-0.6, 0.0, -0.2)
	pt_ar = Vector3(-0.6, 0.0, 0.2)
	pt_el_l = Vector3(-1.2, 0.0, 0.0)
	pt_el_r = Vector3(-1.2, 0.0, 0.0)
	pt_ll = Vector3.ZERO
	pt_lr = Vector3.ZERO
	pt_kn_l = 0.12
	pt_kn_r = 0.12
	pt_tor = Vector3.ZERO
	pt_hd = Vector3.ZERO
	pt_hip = Vector3.ZERO
	pt_root_rot = Vector3.ZERO
	pt_root_pos = Vector3(0.0, STAND_Y, 0.0)
	pt_root_dy = 0.0
	pt_auto_height = false
	pt_root_direct = false
	pt_hip_y_direct = false
	pt_use_basis = false
	pt_breath = 0.0
	r_body = 12.0
	r_limb = 14.0
	r_root = 12.0


func _pose_state_changed() -> void:
	_entry_state = _pose_prev_state
	_pose_prev_state = state
	_entry_root_x = pose_root.rotation.x
	_entry_root_y = pose_root.position.y
	# An elbow drop lands turned sideways: fold that visual yaw into our facing.
	if _entry_state == S.GROUND_DROP and absf(pose_root.rotation.y) > 0.01:
		var ry := pose_root.rotation.y
		_set_facing_angle(rotation.y + ry)
		pose_root.rotation.y = 0.0
	if state == S.DOWN:
		_seen_health = health
		_hit_clock = -10.0


func _update_pose(delta: float) -> void:
	if _style < 0:
		_style = absi(display_name.hash()) % 3
	if state != _pose_prev_state:
		_pose_state_changed()
	_pose_reset()

	match state:
		S.IDLE:
			_pose_idle()
		S.WALK:
			_pose_walk(delta)
		S.RUN:
			_pose_run(delta)
		S.PUNCH:
			_pose_punch()
		S.RUN_ATTACK:
			_pose_run_attack(delta)
		S.STUNNED:
			_pose_stunned()
		S.WHIFF:
			_pose_whiff()
		S.GRAB_WINDUP:
			_pose_grab_windup()
		S.TIEUP_ATK, S.TIEUP_DEF:
			_pose_tieup()
		S.WHIPPING:
			_pose_whipping()
		S.THROWING:
			_pose_throwing()
		S.THROWN:
			_pose_thrown()
		S.DOWN:
			_pose_down()
		S.LOSE:
			_pose_lying_limp()
		S.PINNED:
			_pose_pinned()
		S.GETTING_UP:
			_pose_getting_up()
		S.PINNING:
			_pose_pinning()
		S.TAUNT:
			_pose_taunt()
		S.WIN:
			_pose_win()
		S.STOMP:
			_pose_stomp()
		S.GROUND_DROP:
			_pose_ground_drop()
		S.PICKUP:
			_pose_pickup()
		S.LIFTED:
			_pose_lifted(delta)
	_apply_pose(delta)


func _apply_pose(delta: float) -> void:
	if pt_auto_height:
		pt_root_pos.y = maxf(_leg_drop(-pt_ll.x, pt_kn_l, pt_ll.z), _leg_drop(-pt_lr.x, pt_kn_r, pt_lr.z))
	pt_root_pos.y += pt_root_dy
	var kb := 1.0 - exp(-r_body * delta)
	var kl := 1.0 - exp(-r_limb * delta)
	var kr := 1.0 - exp(-r_root * delta)
	arm_l.rotation = arm_l.rotation.lerp(pt_al, kl)
	arm_r.rotation = arm_r.rotation.lerp(pt_ar, kl)
	elbow_l.rotation = elbow_l.rotation.lerp(pt_el_l, kl)
	elbow_r.rotation = elbow_r.rotation.lerp(pt_el_r, kl)
	leg_l.rotation = leg_l.rotation.lerp(pt_ll, kl)
	leg_r.rotation = leg_r.rotation.lerp(pt_lr, kl)
	knee_l.rotation.x = lerpf(knee_l.rotation.x, pt_kn_l, kl)
	knee_r.rotation.x = lerpf(knee_r.rotation.x, pt_kn_r, kl)
	torso.rotation = torso.rotation.lerp(pt_tor, kb)
	head.rotation = head.rotation.lerp(pt_hd, kb)
	var b := pt_breath
	torso.scale = torso.scale.lerp(Vector3(1.0 + 0.012 * b, 1.0 + 0.008 * b, 1.0 + 0.02 * b), kb)
	hips.rotation.x = lerpf(hips.rotation.x, pt_hip.x, kb)
	hips.rotation.z = lerpf(hips.rotation.z, pt_hip.z, kb)
	if pt_hip_y_direct:
		hips.rotation.y = pt_hip.y
	else:
		hips.rotation.y = lerp_angle(wrapf(hips.rotation.y, -PI, PI), pt_hip.y, kb)
	if pt_use_basis:
		pose_root.basis = Basis(throw_pose_q)
		pose_root.position = Vector3(0.0, throw_pose_y, 0.0)
	elif pt_root_direct:
		pose_root.rotation = pt_root_rot
		pose_root.position = pt_root_pos
	else:
		var rr := pose_root.rotation
		pose_root.rotation = Vector3(lerpf(rr.x, pt_root_rot.x, kr),
			lerp_angle(rr.y, pt_root_rot.y, kr), lerpf(rr.z, pt_root_rot.z, kr))
		pose_root.position = pose_root.position.lerp(pt_root_pos, kr)


# --- standing ------------------------------------------------------------------------

## Getting back to the feet from a throw / sit-out: ease up instead of popping up.
func _recovering() -> void:
	if state_time < 0.45 and _entry_root_y < 0.75:
		r_root = 7.0
		r_limb = 9.0
		r_body = 8.0


## Arms up and chin down when a strike is about to land on us (reversal window open).
func _brace_guard() -> void:
	if reversal_window > 0.0:
		pt_al = Vector3(-1.25, 0.0, -0.15)
		pt_ar = Vector3(-1.25, 0.0, 0.15)
		pt_el_l = Vector3(-2.1, 0.0, 0.0)
		pt_el_r = Vector3(-2.1, 0.0, 0.0)
		pt_tor.x -= 0.08
		pt_hd.x += 0.2
		r_limb = 24.0


func _pose_idle() -> void:
	var b := sin(anim_clock * 2.3)   # breathing
	var w := sin(anim_clock * 1.15)  # weight shifting foot to foot
	pt_breath = b
	_stance(0.55 + 0.06 * w)
	pt_kn_l += 0.06 * w
	pt_kn_r -= 0.06 * w
	pt_tor = Vector3(0.22 + 0.025 * b, -0.05 * w, 0.035 * w)
	pt_hd = Vector3(-0.14 - 0.02 * b, 0.04 * w, -0.03 * w)
	var lean := pt_tor.x
	pt_al = Vector3(-0.55 - lean - 0.03 * b, 0.0, -0.3)
	pt_ar = Vector3(-0.5 - lean + 0.03 * b, 0.0, 0.3)
	pt_el_l = Vector3(-1.5, 0.0, 0.0)
	pt_el_r = Vector3(-1.4, 0.0, 0.0)
	_brace_guard()
	_recovering()


func _pose_walk(delta: float) -> void:
	# Project the stick onto our forward / right vectors: walk forward/back swings the legs
	# on x, sideways strafing swings them on z (a side-step shuffle).
	var mv := Vector3(in_move.x, 0.0, in_move.y)
	var mag := clampf(mv.length(), 0.0, 1.0)
	var right := Vector3(facing.z, 0.0, -facing.x)
	var wf := 0.0
	var ws := 0.0
	if mag > 0.05:
		wf = mv.dot(facing) / mv.length()
		ws = mv.dot(right) / mv.length()
	var kw := 1.0 - exp(-10.0 * delta)
	_walk_f = lerpf(_walk_f, wf, kw)
	_walk_s = lerpf(_walk_s, ws, kw)
	_gait += delta * (6.0 + 4.0 * mag)
	var s := sin(_gait)
	var c := cos(_gait)
	var amp := 0.2 + 0.25 * mag
	var f := _walk_f
	var sd := _walk_s
	var lift_l := maxf(0.0, c)  # left foot travels (lifted) while c > 0
	var lift_r := maxf(0.0, -c)
	pt_ll = Vector3(-0.28 - s * amp * f - 0.2 * lift_l, 0.0, -0.1 + s * amp * 0.55 * sd)
	pt_lr = Vector3(-0.28 + s * amp * f - 0.2 * lift_r, 0.0, 0.1 - s * amp * 0.55 * sd)
	pt_kn_l = 0.55 + 0.75 * lift_l
	pt_kn_r = 0.55 + 0.75 * lift_r
	pt_auto_height = true
	# no extra bob: the leg geometry already dips the hips ~0.05 at full stride
	pt_tor = Vector3(0.2 + 0.06 * f, -s * 0.12 * f, 0.06 * sd * s)
	pt_hd = Vector3(-0.15, s * 0.06 * f, -0.04 * sd * s)
	var lean := pt_tor.x
	pt_al = Vector3(-0.5 - lean + s * 0.32 * f, 0.0, -0.3 - 0.12 * absf(sd))
	pt_ar = Vector3(-0.5 - lean - s * 0.32 * f, 0.0, 0.3 + 0.12 * absf(sd))
	pt_el_l = Vector3(-1.35, 0.0, 0.0)
	pt_el_r = Vector3(-1.35, 0.0, 0.0)
	r_limb = 20.0
	r_root = 20.0
	_brace_guard()
	_recovering()


func _pose_run(delta: float) -> void:
	_gait += delta * 15.0
	var s := sin(_gait)
	var c := cos(_gait)
	pt_ll = Vector3(-0.35 - s * 0.85, 0.0, -0.06)
	pt_lr = Vector3(-0.35 + s * 0.85, 0.0, 0.06)
	pt_kn_l = 0.3 + maxf(0.0, c) * 1.5 + maxf(0.0, -c) * 0.25
	pt_kn_r = 0.3 + maxf(0.0, -c) * 1.5 + maxf(0.0, c) * 0.25
	pt_auto_height = true
	pt_root_dy = 0.04 * absf(s)  # small flight phase
	pt_tor = Vector3(0.4, s * 0.18, 0.0)
	pt_hd = Vector3(-0.3, -s * 0.1, 0.0)
	pt_al = Vector3(-0.85 + s * 0.9, 0.0, -0.15)
	pt_ar = Vector3(-0.85 - s * 0.9, 0.0, 0.15)
	pt_el_l = Vector3(-1.7, 0.0, 0.0)
	pt_el_r = Vector3(-1.7, 0.0, 0.0)
	r_limb = 24.0
	r_root = 22.0
	if whipped:
		# flung into the ropes: yanked off balance, arms windmilling
		var yank := 1.0 - _smooth(_seg(state_time, 0.0, 0.5))
		var fl := anim_clock * 13.0
		pt_tor = Vector3(lerpf(0.25, -0.2, yank), 0.15 * sin(fl * 0.5), 0.1 * sin(fl * 0.7))
		pt_hd = Vector3(-0.35 + 0.15 * sin(fl * 0.9), 0.0, 0.15 * sin(fl * 0.6))
		pt_al = Vector3(-1.5 + 0.9 * sin(fl), 0.0, -0.9 - 0.4 * sin(fl * 0.7))
		pt_ar = Vector3(-1.5 + 0.9 * sin(fl + 2.0), 0.0, 0.9 + 0.4 * sin(fl * 0.8))
		pt_el_l = Vector3(-0.4, 0.0, 0.0)
		pt_el_r = Vector3(-0.4, 0.0, 0.0)


# --- strikes -------------------------------------------------------------------------

func _pose_punch() -> void:
	match current_move_key:
		"knee":
			_pose_knee_lift()
		"clothesline":
			_pose_clothesline()
		_:
			_pose_jab()


func _pose_jab() -> void:
	# 0.08 s wind-up (shoulder back, fist cocked) -> snap out to PUNCH_HIT -> recoil.
	var t := state_time
	var wind := _smooth(_seg(t, 0.0, 0.08))
	var snap := _ease_in(_seg(t, 0.08, PUNCH_HIT))
	var back := _smooth(_seg(t, PUNCH_HIT + 0.06, PUNCH_END))
	var cock := wind * (1.0 - snap)
	var ext := snap * (1.0 - back)
	r_limb = 34.0
	r_body = 24.0
	_stance(0.55 + 0.15 * ext)
	pt_ll.x -= 0.2 * ext  # step into it
	pt_tor = Vector3(0.18 + 0.14 * ext, 0.3 * cock - 0.4 * ext, 0.0)
	pt_hd = Vector3(-0.12, -0.2 * cock + 0.25 * ext, 0.0)
	var lean := pt_tor.x
	pt_ar = Vector3(-0.55 - lean + 0.35 * cock - 1.3 * ext, 0.0, 0.3 - 0.36 * ext)
	pt_el_r = Vector3(-1.5 - 0.6 * cock + 1.42 * ext, 0.0, 0.0)
	pt_al = Vector3(-0.75 - lean, 0.0, -0.3)
	pt_el_l = Vector3(-1.9, 0.0, 0.0)
	pt_root_pos.z = 0.1 * ext


func _pose_knee_lift() -> void:
	# Grab the head, pull it down, drive the right knee up into the gut.
	var t := state_time
	var cock := _smooth(_seg(t, 0.0, 0.08))
	var up := _ease_out(_seg(t, 0.08, 0.18))
	var down := _smooth(_seg(t, 0.28, PUNCH_END))
	var e := up * (1.0 - down)
	r_limb = 30.0
	r_body = 22.0
	_stance(0.45)
	pt_ll = Vector3(-0.15, 0.0, -0.1)
	pt_kn_l = 0.35 + 0.1 * cock
	pt_lr = Vector3(-0.2 + 0.25 * cock * (1.0 - up) - 1.5 * e, 0.0, 0.04)
	pt_kn_r = 0.4 + 0.4 * cock * (1.0 - up) + 1.25 * e
	pt_root_pos.z = 0.42 * e
	pt_tor = Vector3(0.3 + 0.15 * cock * (1.0 - e) + 0.25 * e, 0.0, 0.0)
	pt_hd = Vector3(0.25, 0.0, 0.0)
	var oh := _opp_node("head")
	var hp := oh.global_position + Vector3(0.0, 0.1, 0.0)
	var side := Vector3(facing.z, 0.0, -facing.x) * 0.12
	_reach_pair(hp - side, hp + side)


func _pose_clothesline() -> void:
	# Arm cocked back, then swung out sideways through the runner's chest.
	var t := state_time
	var cock := _smooth(_seg(t, 0.0, 0.06))
	var swing := _ease_in(_seg(t, 0.06, 0.16))
	var back := _smooth(_seg(t, 0.26, PUNCH_END))
	r_limb = 32.0
	r_body = 22.0
	_stance(0.6)
	pt_lr.x += 0.15
	var ax := lerpf(lerpf(-0.4, 0.55, cock), -0.6, swing)
	var az := lerpf(lerpf(0.4, 1.2, cock), 1.5, swing)
	pt_ar = Vector3(lerpf(ax, -0.7, back), 0.0, lerpf(az, 0.35, back))
	pt_el_r = Vector3(lerpf(-0.15, -1.3, back), 0.0, 0.0)
	pt_tor = Vector3(0.15, lerpf(lerpf(0.0, 0.4, cock), -0.45, swing) * (1.0 - back), 0.0)
	pt_al = Vector3(0.1, 0.0, -0.45)
	pt_el_l = Vector3(-0.9, 0.0, 0.0)
	pt_hd = Vector3(-0.1, 0.2 * swing * (1.0 - back), 0.0)


func _pose_run_attack(delta: float) -> void:
	# Running lariat: stride carries in, arm cocked behind then whipped out sideways.
	var t := state_time
	var stride := _smooth(_seg(t, 0.0, 0.18))
	var cock := _smooth(_seg(t, 0.0, 0.08))
	var swing := _ease_in(_seg(t, 0.08, 0.2))
	var back := _smooth(_seg(t, 0.38, 0.55))
	_gait += delta * 15.0 * (1.0 - stride)
	var s := sin(_gait)
	r_limb = 30.0
	r_body = 20.0
	r_root = 20.0
	pt_ll = Vector3(lerpf(-0.35 - s * 0.85, -0.8, stride), 0.0, -0.08)
	pt_lr = Vector3(lerpf(-0.35 + s * 0.85, 0.45, stride), 0.0, 0.08)
	pt_kn_l = lerpf(0.6, 0.7, stride)
	pt_kn_r = lerpf(0.6, 0.85, stride)
	pt_auto_height = true
	pt_tor = Vector3(0.35 - 0.1 * back, (lerpf(0.4 * cock, -0.55, swing)) * (1.0 - back), 0.0)
	pt_hd = Vector3(-0.25, 0.15 * swing, 0.0)
	var ax := lerpf(lerpf(-0.6, 0.6, cock), -0.7, swing)
	var az := lerpf(lerpf(0.3, 1.2, cock), 1.45, swing)
	pt_ar = Vector3(lerpf(ax, -1.3, back), 0.0, lerpf(az, 0.5, back))
	pt_el_r = Vector3(lerpf(-0.1, -1.0, back), 0.0, 0.0)
	pt_al = Vector3(0.35, 0.0, -0.5)
	pt_el_l = Vector3(-1.0, 0.0, 0.0)


func _pose_stunned() -> void:
	var t := state_time
	var os := _opp_state()
	var ok: String = opponent.current_move_key
	if dazed:
		# Picked up and out on their feet: wobbling, arms limp, knees buckling.
		var ph := anim_clock * 3.4
		_stance(0.55 + 0.15 * sin(ph * 0.8))
		pt_kn_l += 0.15 * maxf(0.0, sin(ph))
		pt_kn_r += 0.15 * maxf(0.0, -sin(ph))
		pt_tor = Vector3(0.38 + 0.1 * sin(ph * 0.7), 0.12 * sin(ph * 0.5), 0.17 * sin(ph))
		pt_hd = Vector3(0.35 + 0.15 * sin(ph * 1.3), 0.2 * sin(ph * 0.6), 0.25 * sin(ph + 1.0))
		pt_hip.y = 0.12 * sin(ph * 0.45)
		_hang_arms(pt_tor.x, 0.15 + 0.1 * sin(ph))
		r_body = 6.0
		r_limb = 8.0
		return
	if os == S.PUNCH and ok == "knee":
		# Knee to the gut: yanked in, folding over, clutching the stomach.
		var fold := _smooth(_seg(t, 0.0, 0.1)) * (1.0 - _smooth(_seg(t, 0.4, 0.7)))
		_stance(0.5 + 0.3 * fold)
		pt_root_pos.z = 0.3 * (1.0 - _smooth(_seg(t, 0.12, 0.35)))
		pt_tor = Vector3(0.2 + 0.7 * fold, 0.0, 0.0)
		pt_hd = Vector3(0.1 + 0.35 * fold, 0.0, 0.0)
		pt_al = Vector3(-0.9 - 0.4 * fold, 0.0, 0.35)
		pt_ar = Vector3(-0.9 - 0.4 * fold, 0.0, -0.35)
		pt_el_l = Vector3(-1.5, 0.0, 0.0)
		pt_el_r = Vector3(-1.5, 0.0, 0.0)
		r_body = 22.0
		return
	# Generic hit: head snaps back, arms fling, stagger a step, then recover.
	var e := (t / 0.05) if t < 0.05 else exp(-(t - 0.05) * 7.0)
	_stance(0.5)
	pt_lr.x += 0.3 * e
	pt_kn_l += 0.15 * e
	pt_tor = Vector3(0.2 - 0.6 * e, 0.0, 0.08 * e)
	pt_hd = Vector3(-0.1 - 0.55 * e, 0.0, 0.12 * e)
	pt_al = Vector3(-0.3 + 0.35 * e, 0.0, -0.35 - 0.45 * e)
	pt_ar = Vector3(-0.3 + 0.3 * e, 0.0, 0.35 + 0.5 * e)
	pt_el_l = Vector3(-0.9 + 0.6 * e, 0.0, 0.0)
	pt_el_r = Vector3(-0.9 + 0.6 * e, 0.0, 0.0)
	r_body = 26.0
	r_limb = 22.0
	_recovering()


func _pose_whiff() -> void:
	# Lunged at nothing: stumble forward, arms grasping, then catch the balance.
	var u := state_time / maxf(whiff_time, 0.1)
	var lunge := _ease_out(_seg(u, 0.0, 0.35))
	var rec := _smooth(_seg(u, 0.5, 1.0))
	var e := lunge * (1.0 - rec)
	var strong := current_move_key == "whiff_strong"
	_stance(0.5 + 0.3 * e)
	pt_ll.x -= 0.5 * e
	pt_kn_l += 0.3 * e
	pt_lr.x += 0.45 * e
	pt_root_pos.z = 0.15 * e
	pt_tor = Vector3(0.25 + 0.5 * e, 0.0, 0.1 * e * sin(state_time * 9.0))
	pt_hd = Vector3(-0.3 * e, 0.0, 0.0)
	var lean := pt_tor.x
	var wave := sin(state_time * 16.0) * 0.6 * e if strong else 0.0
	pt_al = Vector3(-1.4 - lean * 0.5 + wave, 0.0, -0.3 - 0.3 * e)
	pt_ar = Vector3(-1.4 - lean * 0.5 - wave, 0.0, 0.3 + 0.3 * e)
	pt_el_l = Vector3(-0.3, 0.0, 0.0)
	pt_el_r = Vector3(-0.3, 0.0, 0.0)
	r_body = 16.0
	r_limb = 20.0


func _pose_grab_windup() -> void:
	# Reaching for the collar-and-elbow; holding GRAB sinks lower and spreads wider.
	var g := _smooth(_seg(state_time, 0.0, STRONG_GRAB_HOLD))
	var reach := _ease_out(_seg(state_time, 0.0, 0.08))
	_stance(0.6 + 0.3 * g)
	pt_ll.x -= 0.15 * reach
	pt_tor = Vector3(0.3 + 0.12 * g, 0.0, 0.0)
	pt_hd = Vector3(-0.2, 0.0, 0.0)
	var lean := pt_tor.x
	pt_al = Vector3(-1.35 - lean * 0.6, 0.0, -0.3 - 0.25 * g)
	pt_ar = Vector3(-1.35 - lean * 0.6, 0.0, 0.3 + 0.25 * g)
	pt_el_l = Vector3(-0.45, 0.0, 0.0)
	pt_el_r = Vector3(-0.45, 0.0, 0.0)
	pt_root_pos.z = 0.06 * reach
	r_limb = 26.0


# --- lock-up -------------------------------------------------------------------------

func _pose_tieup() -> void:
	var atk := state == S.TIEUP_ATK
	var t := state_time
	# Push-pull: both pelvises drift the same way in world space (opposite local signs).
	var sway := sin(t * 3.2) * 0.045 + sin(t * 17.0) * 0.008
	pt_root_pos.z = sway if atk else -sway
	var oh := _opp_node("head")
	var ot := _opp_node("torso")
	var opr := _opp_node("pose_root")
	var oc: String = opponent.committed_move
	var bracing := (not atk) and (reversal_window > 0.0 or oc != "")
	var setting := atk and committed_move != ""
	r_limb = 16.0
	if not tie_strong:
		# Collar-and-elbow: left hand on the neck, right hand on their elbow, heads side
		# by side (each leans its head to its own right, i.e. local +x).
		_stance(0.7)
		pt_ll.z = -0.18
		pt_lr.z = 0.18
		pt_tor = Vector3(0.38, 0.0, -0.14)
		pt_hd = Vector3(-0.12, 0.0, -0.14)
		var oel := _opp_node("elbow_l")
		_reach(true, oh.global_position - Vector3(0.0, 0.03, 0.0))
		_reach(false, oel.global_position)
	elif atk:
		# Strong: arm hooked around the bent-over opponent's head, other hand on the back.
		_stance(0.65)
		pt_tor = Vector3(0.3, 0.12, 0.08)
		pt_hd = Vector3(0.05, 0.0, 0.1)
		_reach(false, oh.to_global(Vector3(0.0, 0.16, -0.12)))
		_reach(true, ot.to_global(Vector3(0.0, 0.4, -0.18)))
		pt_el_r.z = -0.5
	else:
		# Strong (defending): bent over with the head tucked under their arm, hands on
		# their waist.
		_stance(0.85)
		pt_tor = Vector3(0.75, 0.0, 0.28)
		pt_hd = Vector3(0.3, 0.0, 0.2)
		_reach_pair(opr.to_global(Vector3(-0.3, 0.12, 0.0)), opr.to_global(Vector3(0.3, 0.12, 0.0)))
	if bracing:
		# Reading the move: sink, lean in, tense up.
		_stance(0.95)
		if not tie_strong:
			pt_ll.z = -0.2
			pt_lr.z = 0.2
		pt_tor.x += 0.1
		pt_tor.z += sin(anim_clock * 31.0) * 0.025
		pt_hd.x += 0.15
		pt_el_l.x -= 0.2
		pt_el_r.x -= 0.2
	elif setting:
		# Committed: dip the hips to load the move.
		_stance(0.85)
		pt_tor.x += 0.08
		pt_root_pos.z += 0.05


func _pose_whipping() -> void:
	var t := state_time
	var fling := 1.0 - _smooth(_seg(t, 0.25, 0.6))
	var rb: int = opponent.rope_bounces
	var coming := rb >= 1
	_stance(0.8 if coming else 0.5)
	pt_tor = Vector3(0.3 + (0.15 if coming else 0.0), -0.35 * fling, 0.0)
	pt_hd = Vector3(-0.2, 0.2 * fling, 0.0)
	var lean := pt_tor.x
	pt_al = Vector3(-0.9 - lean * 0.5, 0.0, -0.35)
	pt_ar = Vector3(-0.9 - lean * 0.5, 0.0, 0.35)
	pt_el_l = Vector3(-1.0, 0.0, 0.0)
	pt_el_r = Vector3(-1.0, 0.0, 0.0)
	if fling > 0.0:
		# throwing arm stays extended toward the runner, other arm swung back
		var ot := _opp_node("torso")
		_reach(false, ot.global_position + Vector3(0.0, 0.3, 0.0), fling)
		pt_el_r.x = lerpf(pt_el_r.x, -0.05, fling)
		pt_al = pt_al.lerp(Vector3(0.35, 0.0, -0.45), fling)
	r_limb = 22.0
	_recovering()


# --- throws: the thrower ----------------------------------------------------------------

func _pose_throwing() -> void:
	var t := state_time
	var p := clampf(t / maxf(throw_time, 0.01), 0.0, 1.0)
	r_limb = 18.0
	r_body = 16.0
	r_root = 18.0
	var vh := _opp_node("hips")
	var vt := _opp_node("torso")
	var vhd := _opp_node("head")
	var pelvis := vh.global_position
	var chest := vt.to_global(Vector3(0.0, 0.35, 0.0))
	var vhead := vhd.to_global(Vector3(0.0, 0.15, 0.0))
	var hip_a := vh.to_global(Vector3(-0.26, 0.05, 0.0))
	var hip_b := vh.to_global(Vector3(0.26, 0.05, 0.0))
	match current_move_key:
		"slam", "powerslam":
			var dip := _hump(p, 0.0, 0.22)
			var lift := _smooth(_seg(p, 0.05, 0.4))
			var slam := _ease_in(_seg(p, 0.5, 1.0))
			if current_move_key == "powerslam":
				# fall forward onto the victim, landing on the knees
				_legs_blend(0.4 + 0.5 * dip, 0.6, 0.7, -0.3 - 0.7, -0.1 - 0.7, slam)
				pt_tor = Vector3(0.3 * (1.0 - lift) - 0.12 * lift + 0.45 * slam, 0.0, 0.0)
			else:
				_stance(0.4 + 0.5 * dip + 0.45 * slam)
				pt_tor = Vector3(0.35 * (1.0 - lift) - 0.15 * lift * (1.0 - slam) + 0.55 * slam, 0.0, 0.0)
			pt_hd = Vector3(-0.35 * lift * (1.0 - slam) + 0.2 * slam, 0.0, 0.0)
			_reach(false, pelvis)
			_reach(true, chest)
		"suplex":
			var dip := _hump(p, 0.0, 0.2)
			var lift := _smooth(_seg(p, 0.05, 0.45))
			var fall := _smooth(_seg(p, 0.55, 0.95))
			# fall back into a kneeling arch while the victim goes over the top
			_legs_blend(0.4 + 0.5 * dip, 0.5, -0.55, -0.6 + 0.55, -0.4 + 0.55, fall)
			pt_tor = Vector3(0.2 * (1.0 - lift) - 0.15 * lift - 0.4 * fall, 0.0, -0.1 * lift)
			pt_hd = Vector3(-0.3 * lift - 0.3 * fall, 0.0, 0.0)
			_reach(true, chest)
			_reach(false, pelvis)
		"ddt":
			var lock := _smooth(_seg(p, 0.0, 0.25))
			var fall := _ease_in(_seg(p, 0.3, 0.62))
			var lie := _smooth(_seg(p, 0.62, 1.0))
			# step to the side so the victim's head goes down beside us, then sit back hard
			pt_root_pos.x = -0.35 * lock
			var rp := -1.0 - 0.2 * lie
			_legs_blend(0.6, 0.3, rp, -1.3 - rp, -1.2 - rp, fall)
			pt_tor = Vector3(0.45 * lock * (1.0 - fall) - 0.1 * fall, 0.0, 0.1 * lock)
			pt_hd = Vector3(0.2 * lock - 0.2 * fall, 0.0, 0.0)
			_reach(false, vhead)
			_reach(true, chest)
		"piledriver":
			var dip := _hump(p, 0.0, 0.2)
			var lift := _smooth(_seg(p, 0.05, 0.4))
			var kneel := _ease_in(_seg(p, 0.6, 0.75))
			var sit := _smooth(_seg(p, 0.8, 1.0))
			_legs_blend(0.35 + 0.5 * dip, 0.55 - 0.08 * sit, -0.15 * sit, -0.25 * sit, -0.25 * sit, kneel)
			pt_root_dy = 0.06 * _hump(p, 0.48, 0.6)  # little hop before the drop
			pt_root_pos.z = -0.2 * sit
			pt_tor = Vector3(0.3 * dip - 0.12 * lift * (1.0 - kneel) + 0.15 * kneel, 0.0, 0.0)
			pt_hd = Vector3(-0.15 * lift + 0.3 * kneel, 0.0, 0.0)
			_reach_pair(hip_a, hip_b)
		"powerbomb":
			var bend := _smooth(_seg(p, 0.0, 0.16)) * (1.0 - _smooth(_seg(p, 0.2, 0.45)))
			var hold := _smooth(_seg(p, 0.3, 0.46))
			var slam := _ease_in(_seg(p, 0.62, 1.0))
			_stance(0.45 + 0.5 * bend + 0.6 * slam)
			pt_root_pos.z = -0.15 * bend  # sit the hips back so the head fits between the legs
			pt_tor = Vector3(0.15 + 0.8 * bend - 0.12 * hold * (1.0 - slam) + 0.6 * slam, 0.0, 0.0)
			pt_hd = Vector3(0.2 * bend - 0.3 * hold * (1.0 - slam) + 0.25 * slam, 0.0, 0.0)
			_reach_pair(hip_a, hip_b)
		"spinebuster":
			var grab := _smooth(_seg(p, 0.0, 0.15))
			var spin := _seg(p, 0.15, 0.55)
			var drop := _ease_in(_seg(p, 0.55, 1.0))
			pt_hip.y = TAU * _smooth(spin)
			pt_hip_y_direct = true
			_legs_blend(0.5 + 0.2 * grab, 0.58, 0.55, -0.2 - 0.55, -0.05 - 0.55, drop)
			pt_tor = Vector3(0.3 * grab * (1.0 - spin) - 0.1 * spin * (1.0 - drop) + 0.5 * drop, 0.0, 0.0)
			pt_hd = Vector3(0.1 + 0.2 * drop, 0.0, 0.0)
			_reach_pair(hip_a, hip_b)
		"neckbreaker":
			var swing := _smooth(_seg(p, 0.0, 0.45))
			var drop := _ease_in(_seg(p, 0.4, 0.85))
			pt_hip.y = 0.7 * swing * (1.0 - 0.6 * drop)
			# drop to a seat, legs out in front
			_legs_blend(0.55, 0.24, -0.15, -1.4 + 0.15, -1.3 + 0.15, drop)
			pt_kn_l = lerpf(pt_kn_l, 0.3, drop)
			pt_kn_r = lerpf(pt_kn_r, 0.25, drop)
			pt_tor = Vector3(0.25 * (1.0 - drop) + 0.15 * drop, 0.0, 0.15 * drop)
			pt_hd = Vector3(0.1, 0.0, 0.0)
			_reach(false, vhead)
			_reach(true, chest)
		"backdrop", "rev_backdrop":
			var duck := _smooth(_seg(p, 0.0, 0.12)) * (1.0 - _smooth(_seg(p, 0.15, 0.42)))
			var push := _smooth(_seg(p, 0.15, 0.45))
			_stance(0.35 + 0.75 * duck)
			pt_tor = Vector3(0.2 + 0.9 * duck - 0.3 * push, 0.0, 0.0)
			pt_hd = Vector3(0.2 * duck - 0.45 * push, 0.0, 0.0)
			if push > 0.0:
				var k1 := _opp_node("knee_l")
				var k2 := _opp_node("knee_r")
				_reach_pair(k1.global_position, k2.global_position)
			else:
				pt_al = Vector3(0.3, 0.0, -0.4)
				pt_ar = Vector3(0.3, 0.0, 0.4)
				pt_el_l = Vector3(-0.8, 0.0, 0.0)
				pt_el_r = Vector3(-0.8, 0.0, 0.0)
		"hiptoss", "armdrag":
			var turn := _hump(p, 0.0, 0.85)
			if current_move_key == "armdrag":
				# drop to a knee, dragging the arm down and across
				var kneel := _smooth(_seg(p, 0.1, 0.45)) * (1.0 - _smooth(_seg(p, 0.8, 1.0)))
				_legs_blend(0.5, 0.6, 0.0, 0.0, -1.25, kneel)
				pt_tor = Vector3(0.25 + 0.3 * kneel, -0.4 * turn, 0.0)
			else:
				pt_hip.y = 0.8 * turn
				_stance(0.6 + 0.2 * turn)
				pt_tor = Vector3(0.2 + 0.45 * _smooth(_seg(p, 0.2, 0.7)), 0.0, 0.0)
			pt_hd = Vector3(0.1, 0.0, 0.0)
			_reach(true, chest)
			_reach(false, pelvis)
		"finisher":
			var dip := _hump(p, 0.0, 0.14)
			var lift := _smooth(_seg(p, 0.06, 0.4))
			var sit := _ease_in(_seg(p, 0.6, 0.78))
			var after := _smooth(_seg(p, 0.8, 1.0))
			# hoist overhead, hold it high, then jump into a sit-out and drive it down
			_legs_blend(0.3 + 0.6 * dip, 0.24, -0.2 - 0.25 * after, -1.35 + 0.2, -1.35 + 0.2, sit)
			if sit > 0.0:
				pt_ll.z = lerpf(pt_ll.z, -0.55, sit)
				pt_lr.z = lerpf(pt_lr.z, 0.55, sit)
				pt_kn_l = lerpf(pt_kn_l, 0.3, sit)
				pt_kn_r = lerpf(pt_kn_r, 0.3, sit)
			pt_root_dy = 0.05 * _hump(p, 0.45, 0.58) * (1.0 - sit)
			pt_tor = Vector3(0.3 * dip - 0.18 * lift * (1.0 - sit) + 0.3 * sit, 0.0, 0.0)
			pt_hd = Vector3(-0.45 * lift * (1.0 - sit) + 0.2 * sit, 0.0, 0.0)
			_reach_pair(hip_a, hip_b)
		_:
			_stance(0.5 + 0.4 * _hump(p, 0.0, 1.0))
			pt_tor = Vector3(0.2, 0.0, 0.0)
			_reach_pair(hip_a, hip_b)


# --- throws: the victim -------------------------------------------------------------------

func _key(p: float, f: float, s: float, y: float, q: Quaternion, ek := EASE_SMOOTH) -> Array:
	return [p, Vector3(f, s, y), q, ek]


## Victim keyframes for a move, in the thrower's frame. Sets throw_land_yaw.
func _throw_keys(key: String) -> Array:
	var fwd := Vector3(sin(throw_yaw0), 0.0, cos(throw_yaw0))
	var rgt := Vector3(cos(throw_yaw0), 0.0, -sin(throw_yaw0))
	var d0 := throw_from - throw_origin
	var d1 := throw_to - throw_origin
	var f0 := d0.dot(fwd)
	var s0 := d0.dot(rgt)
	var fl := d1.dot(fwd)
	var sl := d1.dot(rgt)
	var k: Array = [_key(0.0, f0, s0, STAND_Y, _qe(throw_yaw_start, 0.0))]
	var land_ease := EASE_IN
	match key:
		"suplex":
			# head dives under the thrower's arm, legs swing up and over, lands behind
			throw_land_yaw = PI
			k.append(_key(0.12, 0.75, 0.5, 1.2, _qe(PI, 0.25 * PI)))
			k.append(_key(0.25, 0.45, 0.5, 1.55, _qe(PI, 0.55 * PI)))
			k.append(_key(0.45, 0.2, 0.5, 2.05, _qe(PI, 0.98 * PI), EASE_OUT))
			k.append(_key(0.55, 0.15, 0.5, 2.1, _qe(PI, 1.02 * PI)))
		"ddt":
			# bent over in a front facelock, spiked head-first, then flops onto the back
			throw_land_yaw = 0.0
			k.append(_key(0.3, 1.0, 0.25, 1.05, _qe(PI, 0.35 * PI)))
			k.append(_key(0.6, 0.8, 0.25, 0.5, _qe(PI, 0.62 * PI), EASE_IN))
			k.append(_key(0.78, 0.8, 0.15, 0.4, _qe(PI, 0.55 * PI) * Quaternion(Vector3.UP, 0.5 * PI)))
			land_ease = EASE_SMOOTH
		"piledriver":
			# cartwheeled upside down chest-to-chest, dropped onto the head, topples over
			throw_land_yaw = 0.0
			k.append(_key(0.2, 0.6, 0.0, 1.25, _qe(PI, 0.0, 0.5 * PI)))
			k.append(_key(0.4, 0.4, 0.0, 1.55, _qe(PI, 0.0, 0.98 * PI), EASE_OUT))
			k.append(_key(0.6, 0.4, 0.0, 1.6, _qe(PI, 0.0, PI)))
			k.append(_key(0.75, 0.38, 0.0, 1.13, _qe(PI, 0.0, PI), EASE_IN))
			k.append(_key(0.87, 0.9, 0.0, 0.8, _qe(0.0, 1.25 * PI)))  # pivots over the planted head
			land_ease = EASE_SMOOTH
		"powerbomb":
			# head between the legs, swung up onto the shoulders, slammed down forward
			throw_land_yaw = PI
			k.append(_key(0.08, 1.2, 0.0, 0.92, _qe(PI, 0.3 * PI)))
			k.append(_key(0.18, 1.25, 0.0, 0.95, _qe(PI, 0.58 * PI)))
			k.append(_key(0.26, 1.45, 0.0, 1.15, _qe(PI, 0.42 * PI)))
			k.append(_key(0.34, 1.15, 0.0, 1.6, _qe(PI, 0.22 * PI)))
			k.append(_key(0.46, 0.4, 0.0, 1.85, _qe(PI, -0.05), EASE_OUT))
			k.append(_key(0.62, 0.38, 0.0, 1.92, _qe(PI, -0.12)))
		"spinebuster":
			# bear-hugged, carried around a full turn, driven down onto the back
			throw_land_yaw = PI
			k.append(_key(0.15, 0.6, 0.0, 1.2, _qe(PI, 0.25)))
			for i in range(1, 9):
				var u := float(i) / 8.0
				var ph := TAU * _smooth(u)
				k.append(_key(0.15 + 0.4 * u, 0.6 * cos(ph), 0.6 * sin(ph), 1.2 + 0.08 * sin(u * PI),
					_qe(PI + ph, 0.25), 3))
		"neckbreaker":
			# swung around by the head to the side, both fall back
			throw_land_yaw = 0.5 * PI
			k.append(_key(0.3, 0.45, 0.75, 1.0, _qe(0.75 * PI, 0.0)))
			k.append(_key(0.45, -0.4, 0.45, 1.05, _qe(0.5 * PI, -0.15)))
		"backdrop", "rev_backdrop":
			# folded over the ducking thrower's back, flipped up and over, lands behind
			throw_land_yaw = PI
			k.append(_key(0.15, 0.55, 0.0, 1.35, _qe(PI, 0.4 * PI)))
			k.append(_key(0.45, -0.15, 0.0, 2.45, _qe(PI, 0.8 * PI), EASE_OUT))
			k.append(_key(0.55, -0.35, 0.0, 2.5, _qe(PI, 0.95 * PI)))
		"powerslam":
			# scooped across the chest, the thrower falls forward on top
			throw_land_yaw = -0.5 * PI
			k.append(_key(0.3, 0.45, 0.0, 1.6, _qe(PI, 0.0, 0.5 * PI), EASE_OUT))
			k.append(_key(0.45, 0.5, 0.0, 1.65, _qe(PI, 0.0, 0.5 * PI)))
		"armdrag", "hiptoss":
			# quick front flip over the hip
			throw_land_yaw = PI
			var apex := STAND_Y + throw_height * 0.72
			k.append(_key(0.25, 1.0, 0.45, 1.45, _qe(PI, 0.35 * PI)))
			k.append(_key(0.5, 0.85, 0.45, apex, _qe(PI, PI)))
			k.append(_key(0.75, 1.15, 0.25, 1.1, _qe(PI, 1.3 * PI), EASE_IN))
			land_ease = EASE_SMOOTH
		"finisher":
			# hoisted highest of all, upside down, driven into the mat from a sit-out
			throw_land_yaw = 0.0
			k.append(_key(0.18, 0.6, 0.0, 1.4, _qe(PI, 0.0, 0.5 * PI)))
			k.append(_key(0.4, 0.42, 0.0, 2.6, _qe(PI, 0.0, PI), EASE_OUT))
			k.append(_key(0.6, 0.42, 0.0, 2.72, _qe(PI, 0.0, PI)))
			k.append(_key(0.78, 0.45, 0.0, 1.08, _qe(PI, 0.0, PI), EASE_IN))
			k.append(_key(0.89, 0.95, 0.0, 0.78, _qe(0.0, 1.25 * PI)))
			land_ease = EASE_SMOOTH
		_:
			# body slam: scooped and turned upside down across the chest, slammed forward
			throw_land_yaw = -0.5 * PI
			k.append(_key(0.2, 0.5, 0.0, 1.35, _qe(PI, 0.0, 0.45 * PI)))
			k.append(_key(0.4, 0.55, 0.0, 1.85, _qe(PI, 0.1, 0.9 * PI), EASE_OUT))
			k.append(_key(0.55, 0.55, 0.0, 1.92, _qe(PI, 0.1, 0.92 * PI)))
	k.append(_key(1.0, fl, sl, LIE_Y, _qe(throw_land_yaw, -PI / 2), land_ease))
	return k


## Samples the victim's throw path at p: sets our ring position and the pelvis pose.
func _throw_sample(p: float) -> void:
	var k := _throw_keys(current_move_key)
	var i := 0
	while i < k.size() - 2:
		var nxt: Array = k[i + 1]
		var np: float = nxt[0]
		if p < np:
			break
		i += 1
	var a: Array = k[i]
	var b: Array = k[i + 1]
	var pa: float = a[0]
	var pb: float = b[0]
	var ek: int = b[3]
	var u := _seg(p, pa, pb)
	match ek:
		EASE_SMOOTH:
			u = _smooth(u)
		EASE_IN:
			u = _ease_in(u)
		EASE_OUT:
			u = _ease_out(u)
	var va: Vector3 = a[1]
	var vb: Vector3 = b[1]
	var qa: Quaternion = a[2]
	var qb: Quaternion = b[2]
	var v := va.lerp(vb, u)
	throw_pose_q = qa.slerp(qb, u).normalized()
	throw_pose_y = v.z
	var fwd := Vector3(sin(throw_yaw0), 0.0, cos(throw_yaw0))
	var rgt := Vector3(cos(throw_yaw0), 0.0, -sin(throw_yaw0))
	position = throw_origin + fwd * v.x + rgt * v.y
	_set_facing_angle(throw_yaw0)


func _pose_thrown() -> void:
	var p := clampf(state_time / maxf(throw_time, 0.01), 0.0, 1.0)
	pt_use_basis = true
	r_limb = 16.0
	r_body = 14.0
	var fl := sin(anim_clock * 13.0)
	var fl2 := sin(anim_clock * 10.0 + 1.3)
	pt_al = Vector3(-0.6 + 0.35 * fl, 0.0, -1.0 - 0.25 * fl2)
	pt_ar = Vector3(-0.6 - 0.35 * fl2, 0.0, 1.0 + 0.25 * fl)
	pt_el_l = Vector3(-0.5, 0.0, 0.0)
	pt_el_r = Vector3(-0.5, 0.0, 0.0)
	pt_ll = Vector3(-0.35 + 0.2 * fl, 0.0, -0.1)
	pt_lr = Vector3(-0.15 - 0.2 * fl2, 0.0, 0.1)
	pt_kn_l = 0.6 + 0.2 * fl2
	pt_kn_r = 0.4 + 0.2 * fl
	pt_hd = Vector3(-0.2 + 0.1 * fl2, 0.0, 0.0)
	match current_move_key:
		"powerbomb":
			if p < 0.28:
				# bent over, arms hanging
				pt_tor = Vector3(0.45, 0.0, 0.0)
				_hang_arms(1.4, 0.2)
				pt_ll = Vector3(-0.1, 0.0, -0.1)
				pt_lr = Vector3(-0.1, 0.0, 0.1)
				pt_kn_l = 0.3
				pt_kn_r = 0.3
			else:
				# sitting on the shoulders: thighs over them, shins down the thrower's back
				pt_ll = Vector3(-1.45, 0.0, -0.4)
				pt_lr = Vector3(-1.45, 0.0, 0.4)
				pt_kn_l = 1.45
				pt_kn_r = 1.45
				pt_tor = Vector3(-0.1, 0.0, 0.0)
		"suplex", "piledriver", "finisher":
			if p > 0.18:
				# upside down: legs straight up together, arms dangling toward the mat
				pt_ll = Vector3(0.05, 0.0, -0.03)
				pt_lr = Vector3(0.05, 0.0, 0.03)
				pt_kn_l = 0.15 + 0.1 * fl
				pt_kn_r = 0.15 + 0.1 * fl2
				pt_al = Vector3(-2.6 + 0.15 * fl, 0.0, -0.35)
				pt_ar = Vector3(-2.6 + 0.15 * fl2, 0.0, 0.35)
				pt_el_l = Vector3(-0.3, 0.0, 0.0)
				pt_el_r = Vector3(-0.3, 0.0, 0.0)
		"ddt":
			pt_tor = Vector3(0.45 * (1.0 - _seg(p, 0.65, 1.0)), 0.0, 0.0)
			pt_al = Vector3(-1.4, 0.0, -0.3)
			pt_ar = Vector3(-1.4, 0.0, 0.3)
			pt_el_l = Vector3(-0.2, 0.0, 0.0)
			pt_el_r = Vector3(-0.2, 0.0, 0.0)
		"spinebuster":
			# legs fly out with the spin
			pt_ll = Vector3(0.2, 0.0, -0.35)
			pt_lr = Vector3(0.2, 0.0, 0.35)
			pt_tor = Vector3(0.2, 0.0, 0.0)
		"backdrop", "rev_backdrop":
			pt_ll = Vector3(-0.3 + 0.3 * fl, 0.0, -0.25)
			pt_lr = Vector3(-0.3 - 0.3 * fl, 0.0, 0.25)
	# brace for impact just before landing
	var brace := _seg(p, 0.85, 1.0)
	pt_hd.x = lerpf(pt_hd.x, 0.4, brace)


# --- on the mat -----------------------------------------------------------------------

## Relaxed lying-on-the-back pose: one knee up, head lifted, arms out on the mat.
func _down_relaxed() -> void:
	var ac := anim_clock
	pt_breath = sin(ac * 3.0)
	pt_root_rot = Vector3(-PI / 2, 0.0, 0.0)
	pt_root_pos = Vector3(0.0, LIE_Y, 0.0)
	pt_al = Vector3(0.0, 0.0, -1.15 - 0.05 * sin(ac * 1.3))
	pt_ar = Vector3(0.0, 0.0, 0.95 + 0.05 * sin(ac * 1.1))
	pt_el_l = Vector3(0.0, 0.0, -0.5)
	pt_el_r = Vector3(0.0, 0.0, 0.3)
	pt_ll = Vector3(-0.85, 0.0, -0.12 + 0.08 * sin(ac * 0.9))
	pt_kn_l = 1.85
	pt_lr = Vector3(0.0, 0.0, 0.14)
	pt_kn_r = 0.12
	pt_tor = Vector3(0.1 + 0.02 * pt_breath, 0.0, 0.0)
	pt_hd = Vector3(0.38, 0.0, 0.12 * sin(ac * 0.7))


func _pose_down() -> void:
	var t := state_time
	pt_root_direct = true
	r_limb = 7.0
	r_body = 9.0
	_down_relaxed()
	var from_up := _entry_root_x > -1.0
	var fall_t := 0.34
	if from_up and t < fall_t:
		# knocked off our feet: knees buckle, butt hits, then the back slaps the mat
		var u := t / fall_t
		var s1 := _smooth(_seg(u, 0.0, 0.45))
		var s2 := _ease_in(_seg(u, 0.4, 1.0))
		var rp := lerpf(lerpf(_entry_root_x, -0.5, s1), -PI / 2, s2)
		var y := lerpf(lerpf(_entry_root_y, 0.5, s1), LIE_Y, s2)
		pt_root_rot = Vector3(rp, 0.0, 0.0)
		pt_root_pos = Vector3(0.0, y, 0.0)
		var lx := lerpf(-0.7, -0.5, s2)
		pt_ll = Vector3(lx, 0.0, -0.12)
		pt_lr = Vector3(lx + 0.1, 0.0, 0.12)
		pt_kn_l = lerpf(_plant_knee(y, rp, lx), 0.9, s2)
		pt_kn_r = lerpf(_plant_knee(y, rp, lx + 0.1), 0.7, s2)
		pt_al = Vector3(-1.3, 0.0, -0.5)
		pt_ar = Vector3(-1.2, 0.0, 0.5)
		pt_el_l = Vector3(-0.4, 0.0, 0.0)
		pt_el_r = Vector3(-0.4, 0.0, 0.0)
		pt_tor = Vector3(0.3, 0.0, 0.0)
		pt_hd = Vector3(0.45, 0.0, 0.0)
		r_limb = 20.0
		r_body = 20.0
		return
	# Landing bump: the pelvis bounces up 0.08 and settles, limbs fling up then flop.
	var land := t - (fall_t if from_up else 0.0)
	var bounce := 0.08 * _hump(land, 0.0, 0.2) + 0.02 * _hump(land, 0.2, 0.32)
	var fling := _hump(land, 0.0, 0.25)
	pt_root_pos.y += bounce
	pt_root_rot.x += 0.15 * bounce / 0.08 * 0.5
	pt_al.x -= 0.8 * fling
	pt_ar.x -= 0.7 * fling
	pt_ll.x -= 0.35 * fling
	pt_lr.x -= 0.5 * fling
	pt_hd.x -= 0.5 * fling  # head whips back into the mat
	pt_tor.x -= 0.1 * fling
	if land < 0.3:
		r_limb = 12.0
	# Stomped / dropped on: the body jolts and curls.
	if health < _seen_health - 0.01:
		_hit_clock = anim_clock
	_seen_health = health
	var jolt := exp(-(anim_clock - _hit_clock) * 7.0)
	if jolt > 0.01:
		pt_tor.x += 0.4 * jolt
		pt_hd.x += 0.3 * jolt
		pt_ll.x -= 0.4 * jolt
		pt_lr.x -= 0.6 * jolt
		pt_kn_r += 0.8 * jolt
		pt_al.x -= 0.6 * jolt
		pt_ar.x -= 0.6 * jolt
		pt_root_pos.y += 0.05 * jolt
		r_limb = 18.0
		r_body = 18.0


func _pose_lying_limp() -> void:
	pt_root_direct = true
	r_limb = 5.0
	r_body = 5.0
	_down_relaxed()
	pt_breath *= 0.5
	pt_ll = Vector3(-0.2, 0.0, -0.2)
	pt_kn_l = 0.4
	pt_lr = Vector3(0.0, 0.0, 0.2)
	pt_al = Vector3(0.0, 0.0, -1.35)
	pt_ar = Vector3(0.0, 0.0, 1.3)
	pt_hd = Vector3(0.05, 0.0, 0.35)


func _pose_pinned() -> void:
	# Shoulders struggle: torso rocks, pelvis bucks, the free leg kicks, the arms flail.
	# The leg nearer the pinner is hooked up by their arm. Effort grows with the escape bar.
	pt_root_direct = true
	_down_relaxed()
	var ac := anim_clock
	var effort := clampf(pin_escape / maxf(_pin_escape_needed(), 0.1), 0.0, 1.0)
	var amp := 0.6 + 0.6 * effort
	var right := Vector3(facing.z, 0.0, -facing.x)
	var pin_side: float = (opponent.position - position).dot(right)
	var kick := maxf(0.0, sin(ac * 9.0)) * amp
	if pin_side < 0.0:
		pt_ll = Vector3(-1.05, 0.0, -0.1)
		pt_kn_l = 0.9
		pt_lr = Vector3(-0.2 - 0.4 * kick, 0.0, 0.15)
		pt_kn_r = 0.2 + 0.9 * maxf(0.0, sin(ac * 9.0 + 1.2)) * amp
	else:
		pt_lr = Vector3(-1.05, 0.0, 0.1)
		pt_kn_r = 0.9
		pt_ll = Vector3(-0.2 - 0.4 * kick, 0.0, -0.15)
		pt_kn_l = 0.2 + 0.9 * maxf(0.0, sin(ac * 9.0 + 1.2)) * amp
	pt_tor = Vector3(0.12 + 0.08 * maxf(0.0, sin(ac * 5.0)) * amp, 0.22 * sin(ac * 6.5) * amp, 0.0)
	pt_hd = Vector3(0.3 + 0.15 * sin(ac * 7.0), 0.2 * sin(ac * 4.0), 0.0)
	pt_al = Vector3(-0.4 * maxf(0.0, sin(ac * 8.0)) * amp, 0.0, -0.9)
	pt_ar = Vector3(-0.4 * maxf(0.0, sin(ac * 8.0 + 1.5)) * amp, 0.0, 0.9)
	pt_root_pos.y = LIE_Y + 0.04 * maxf(0.0, sin(ac * 6.0)) * amp
	r_limb = 16.0
	r_body = 14.0


func _pose_getting_up() -> void:
	# Three stages over 0.7 s: lying -> sit up -> one knee -> stand.
	var u := clampf(state_time / 0.7, 0.0, 1.0)
	var a := _smooth(_seg(u, 0.0, 0.36))
	var b := _smooth(_seg(u, 0.3, 0.66))
	var c := _smooth(_seg(u, 0.62, 1.0))
	pt_root_direct = true
	r_limb = 20.0
	r_body = 18.0
	var rp := lerpf(lerpf(lerpf(-PI / 2, -0.25, a), 0.05, b), 0.0, c)
	var y := lerpf(lerpf(lerpf(LIE_Y, 0.22, a), 0.55, b), 0.9, c)
	pt_root_rot = Vector3(rp, 0.0, 0.0)
	pt_root_pos = Vector3(0.0, y, 0.0)
	# left: knee up -> foot drawn in -> kneeling on it -> stance
	pt_ll = Vector3(lerpf(lerpf(lerpf(-0.85, -0.75, a), 0.0, b), -0.35, c), 0.0, -0.12)
	pt_kn_l = lerpf(lerpf(lerpf(1.85, 2.2, a), 1.45, b), 0.7, c)
	# right: straight -> out in front -> foot planted ahead -> stance
	pt_lr = Vector3(lerpf(lerpf(lerpf(0.0, -1.25, a), -1.25, b), -0.12, c), 0.0, 0.12)
	pt_kn_r = lerpf(lerpf(lerpf(0.12, 0.2, a), 1.95, b), 0.6, c)
	pt_tor = Vector3(lerpf(lerpf(lerpf(0.1, 0.45, a), 0.35, b), 0.22, c), 0.0, 0.0)
	pt_hd = Vector3(lerpf(lerpf(lerpf(0.38, 0.1, a), -0.1, b), -0.14, c), 0.0, 0.0)
	# hands: out on the mat -> pushing off behind -> on the knee -> guard
	pt_al = Vector3(0.0, 0.0, -1.15).lerp(Vector3(0.55, 0.0, -0.35), a).lerp(Vector3(-0.7, 0.0, -0.1), b) \
		.lerp(Vector3(-0.77, 0.0, -0.3), c)
	pt_ar = Vector3(0.0, 0.0, 0.95).lerp(Vector3(0.55, 0.0, 0.35), a).lerp(Vector3(-0.9, 0.0, 0.2), b) \
		.lerp(Vector3(-0.72, 0.0, 0.3), c)
	pt_el_l = Vector3(0.0, 0.0, -0.5).lerp(Vector3(-0.2, 0.0, 0.0), a).lerp(Vector3(-0.6, 0.0, 0.0), b) \
		.lerp(Vector3(-1.5, 0.0, 0.0), c)
	pt_el_r = Vector3(0.0, 0.0, 0.3).lerp(Vector3(-0.2, 0.0, 0.0), a).lerp(Vector3(-0.6, 0.0, 0.0), b) \
		.lerp(Vector3(-1.4, 0.0, 0.0), c)


func _pose_pinning() -> void:
	# Chest across the opponent's chest, perpendicular, face down, knees on the mat,
	# one arm hooking the near leg and the other hand braced past the far side.
	r_root = 16.0
	r_limb = 14.0
	pt_root_rot = Vector3(1.35, 0.0, 0.0)
	pt_root_pos = Vector3(0.0, PIN_Y + 0.01 * sin(anim_clock * 8.0), 0.0)
	pt_ll = Vector3(-1.25, 0.0, -0.15)
	pt_lr = Vector3(-1.25, 0.0, 0.15)
	pt_kn_l = 1.45
	pt_kn_r = 1.45
	pt_tor = Vector3(0.08, 0.0, 0.0)
	pt_hd = Vector3(-0.55, 0.0, 0.0)
	var k1 := _opp_node("knee_l")
	var k2 := _opp_node("knee_r")
	var kn: Node3D = k1 if k1.global_position.distance_squared_to(global_position) < \
		k2.global_position.distance_squared_to(global_position) else k2
	var knee_p := kn.global_position
	var ot := _opp_node("torso")
	var brace := ot.to_global(Vector3(0.0, 0.4, 0.0)) + facing * 0.45
	brace.y = 0.12
	var left_to_knee := arm_l.global_position.distance_squared_to(knee_p) < \
		arm_r.global_position.distance_squared_to(knee_p)
	_reach(left_to_knee, knee_p)
	_reach(not left_to_knee, brace)


# --- taunts & celebrations ------------------------------------------------------------

func _pose_taunt() -> void:
	var u := state_time
	var pre := _smooth(_seg(u, 0.0, 0.15))
	var on := _smooth(_seg(u, 0.12, 0.3)) * (1.0 - _smooth(_seg(u, TAUNT_TIME - 0.2, TAUNT_TIME)))
	r_limb = 16.0
	_stance(0.3 + 0.45 * pre * (1.0 - on))
	pt_tor = Vector3(0.25 * pre * (1.0 - on), 0.0, 0.0)
	match _style:
		0:
			# double bicep flex with a pelvis bounce
			var bounce := absf(sin(u * 7.0)) * on
			_stance(0.25 + 0.35 * bounce + 0.45 * pre * (1.0 - on))
			pt_al = Vector3(-0.6, 0.0, -0.2).lerp(Vector3(0.0, 0.0, -1.45), on)
			pt_ar = Vector3(-0.6, 0.0, 0.2).lerp(Vector3(0.0, 0.0, 1.45), on)
			pt_el_l = Vector3(-1.2, 0.0, 0.0).lerp(Vector3(0.0, 0.0, -1.75 - 0.15 * bounce), on)
			pt_el_r = Vector3(-1.2, 0.0, 0.0).lerp(Vector3(0.0, 0.0, 1.75 + 0.15 * bounce), on)
			pt_tor = Vector3(lerpf(pt_tor.x, -0.12, on), 0.15 * sin(u * 3.0) * on, 0.0)
			pt_hd = Vector3(-0.3 * on, 0.0, 0.0)
			pt_breath = on
		1:
			# fist pumped to the rafters, other hand on the hip
			var pump := maxf(0.0, sin(u * 9.0)) * on
			pt_ar = Vector3(-0.6, 0.0, 0.2).lerp(Vector3(-2.85 + 0.3 * pump, 0.0, 0.25), on)
			pt_el_r = Vector3(-1.2, 0.0, 0.0).lerp(Vector3(-0.2 - 0.6 * pump, 0.0, 0.0), on)
			pt_al = Vector3(-0.6, 0.0, -0.2).lerp(Vector3(0.15, 0.0, -0.6), on)
			pt_el_l = Vector3(-1.2, 0.0, 0.0).lerp(Vector3(0.0, 0.0, 1.3), on)
			pt_tor = Vector3(lerpf(pt_tor.x, -0.1, on), 0.3 * sin(u * 2.5) * on, -0.08 * on)
			pt_hd = Vector3(-0.35 * on, 0.0, 0.0)
			pt_kn_l += 0.15 * pump
			pt_kn_r += 0.15 * pump
		_:
			# beating the chest and roaring
			var bl := maxf(0.0, sin(u * 10.0)) * on
			var br := maxf(0.0, -sin(u * 10.0)) * on
			pt_al = Vector3(-0.6, 0.0, -0.2).lerp(Vector3(-1.1 + 0.35 * bl, 0.0, 0.15), on)
			pt_ar = Vector3(-0.6, 0.0, 0.2).lerp(Vector3(-1.1 + 0.35 * br, 0.0, -0.15), on)
			pt_el_l = Vector3(-1.2, 0.0, 0.0).lerp(Vector3(-2.2, 0.0, 0.0), on)
			pt_el_r = Vector3(-1.2, 0.0, 0.0).lerp(Vector3(-2.2, 0.0, 0.0), on)
			pt_tor = Vector3(lerpf(pt_tor.x, -0.18 + 0.06 * (bl + br), on), 0.08 * (bl - br), 0.0)
			pt_hd = Vector3(-0.45 * on, 0.0, 0.0)
			r_limb = 26.0


func _pose_win() -> void:
	var ac := anim_clock
	var bounce := absf(sin(ac * 5.0))
	_stance(0.3 + 0.3 * bounce)
	r_limb = 12.0
	if fmod(ac, 5.0) < 3.2:
		# arm raised high, the other pointing out at the crowd
		pt_ar = Vector3(-2.95 + 0.15 * sin(ac * 6.0), 0.0, 0.3)
		pt_el_r = Vector3(-0.15, 0.0, 0.0)
		pt_al = Vector3(-1.5, 0.0, -0.4)
		pt_el_l = Vector3(-0.05, 0.0, 0.0)
		pt_tor = Vector3(-0.08, 0.35 * sin(ac * 0.8), 0.0)
		pt_hd = Vector3(-0.2, 0.15 * sin(ac * 0.8), 0.0)
	else:
		# double bicep flex
		pt_al = Vector3(0.0, 0.0, -1.45)
		pt_ar = Vector3(0.0, 0.0, 1.45)
		pt_el_l = Vector3(0.0, 0.0, -1.8)
		pt_el_r = Vector3(0.0, 0.0, 1.8)
		pt_tor = Vector3(-0.12, 0.0, 0.0)
		pt_hd = Vector3(-0.3, 0.0, 0.0)
		pt_breath = 1.0


# --- ground attacks -----------------------------------------------------------------

func _pose_stomp() -> void:
	# Right foot raised high, then driven down onto the downed opponent.
	var u := state_time
	var lift := _smooth(_seg(u, 0.0, 0.14))
	var stomp := _ease_in(_seg(u, 0.14, 0.22))
	var rec := _smooth(_seg(u, 0.3, 0.5))
	r_limb = 30.0
	r_body = 20.0
	_stance(0.45)
	pt_ll = Vector3(-0.2, 0.0, -0.12)
	pt_kn_l = 0.45 + 0.25 * stomp * (1.0 - rec)
	var lx := lerpf(lerpf(-0.1, -1.35, lift), -1.0, stomp)
	var kn := lerpf(lerpf(0.35, 1.75, lift), 0.9, stomp)
	pt_lr = Vector3(lerpf(lx, -0.1, rec), 0.0, 0.08)
	pt_kn_r = lerpf(kn, 0.4, rec)
	pt_tor = Vector3(0.15 - 0.08 * lift + 0.35 * stomp * (1.0 - rec), 0.0, 0.0)
	pt_hd = Vector3(0.3, 0.0, 0.0)
	var bal := lift * (1.0 - stomp)
	pt_al = Vector3(-0.3 + 0.4 * stomp, 0.0, -0.3 - 0.4 * bal)
	pt_ar = Vector3(-0.3 + 0.4 * stomp, 0.0, 0.3 + 0.4 * bal)
	pt_el_l = Vector3(-1.2, 0.0, 0.0)
	pt_el_r = Vector3(-1.2, 0.0, 0.0)


func _pose_ground_drop() -> void:
	# Crouch, leap (pelvis up ~0.5), come down elbow- or knee-first on the opponent.
	var u := clampf(state_time / 0.5, 0.0, 1.0)
	var crouch := _hump(u, 0.0, 0.25)
	var v := _seg(u, 0.18, 1.0)
	pt_root_direct = true
	r_limb = 20.0
	r_body = 18.0
	if current_move_key == "knee_drop":
		var y := lerpf(0.88, 0.86, v) + 0.58 * sin(PI * v) - 0.12 * crouch
		pt_root_pos = Vector3(0.0, y, 0.0)
		pt_ll = Vector3(lerpf(-0.4, 0.35, v), 0.0, -0.1)
		pt_lr = Vector3(lerpf(-0.2, lerpf(-1.5, -0.4, _ease_in(v)), _smooth(_seg(v, 0.0, 0.3))), 0.0, 0.05)
		if v <= 0.0:
			pt_kn_l = _plant_knee(y, 0.0, pt_ll.x)
			pt_kn_r = _plant_knee(y, 0.0, pt_lr.x)
		else:
			pt_kn_l = 1.4
			pt_kn_r = lerpf(2.2, 2.0, v)
		var hit_k := _seg(v, 0.85, 1.0)
		pt_tor = Vector3(0.3 * crouch - 0.1 * v + 0.55 * hit_k, 0.0, 0.0)
		pt_hd = Vector3(0.2 + 0.2 * hit_k, 0.0, 0.0)
		pt_al = Vector3(lerpf(0.4 * crouch - 0.6, -2.5, _smooth(_seg(v, 0.0, 0.4))) + 1.8 * hit_k, 0.0, -0.4)
		pt_ar = Vector3(pt_al.x, 0.0, 0.4)
		pt_el_l = Vector3(-0.4, 0.0, 0.0)
		pt_el_r = Vector3(-0.4, 0.0, 0.0)
		return
	# elbow drop: turn sideways in the air, fall back, left side (and elbow) first
	var y2 := lerpf(0.88, 0.27, v * v) + 0.62 * sin(PI * v) - 0.12 * crouch
	var rp := -PI / 2 * _ease_in(_seg(v, 0.25, 1.0))
	pt_root_rot = Vector3(rp, 0.5 * PI * _smooth(_seg(v, 0.1, 0.7)), 0.0)
	pt_root_pos = Vector3(0.0, y2, 0.0)
	pt_hip.y = -0.6 * _smooth(_seg(v, 0.3, 0.9))
	if v <= 0.0:
		_legs_for(y2, 0.0, -0.4, -0.15)
	else:
		pt_ll = Vector3(-0.6, 0.0, -0.1)
		pt_lr = Vector3(-0.3, 0.0, 0.1)
		pt_kn_l = 1.0
		pt_kn_r = 0.6
	var cockw := _smooth(_seg(v, 0.0, 0.35))
	pt_al = Vector3(0.4 * crouch - 0.4, 0.0, -0.3).lerp(Vector3(0.0, 0.0, -1.45), cockw)
	pt_el_l = Vector3(-1.0, 0.0, 0.0).lerp(Vector3(-1.9, 0.0, 0.0), cockw)
	pt_ar = Vector3(0.4 * crouch - 0.4, 0.0, 0.3).lerp(Vector3(-2.4, 0.0, 0.5), cockw)
	pt_el_r = Vector3(-0.3, 0.0, 0.0)
	pt_tor = Vector3(0.3 * crouch + 0.1 * v, 0.0, 0.0)
	pt_hd = Vector3(0.35 * v, 0.0, 0.0)


func _pose_pickup() -> void:
	# Bend over, grab the head, haul them up while straightening.
	var u := clampf(state_time / 0.6, 0.0, 1.0)
	var bend := _smooth(_seg(u, 0.0, 0.3)) * (1.0 - _smooth(_seg(u, 0.45, 1.0)))
	_stance(0.5 + 0.6 * bend)
	pt_tor = Vector3(0.2 + 1.0 * bend, 0.0, 0.0)
	pt_hd = Vector3(0.3 * bend - 0.1, 0.0, 0.0)
	var vhd := _opp_node("head")
	var hp := vhd.global_position + Vector3(0.0, 0.1, 0.0)
	var side := Vector3(facing.z, 0.0, -facing.x) * 0.13
	_reach_pair(hp - side, hp + side)
	r_limb = 18.0


func _pose_lifted(delta: float) -> void:
	# Hauled limply from the mat to the feet by the head, turned to face the lifter.
	var u := clampf(state_time / 0.6, 0.0, 1.0)
	var a := _smooth(_seg(u, 0.0, 0.45))
	var c := _smooth(_seg(u, 0.35, 1.0))
	_face_opponent(delta * 0.5)
	pt_root_direct = true
	var rp := lerpf(lerpf(-PI / 2, -0.5, a), 0.0, c)
	var y := lerpf(lerpf(LIE_Y, 0.3, a), 0.88, c)
	pt_root_rot = Vector3(rp, 0.0, 0.0)
	pt_root_pos = Vector3(0.0, y, 0.0)
	var lx := lerpf(lerpf(0.0, -1.0, a), -0.2, c)
	pt_ll = Vector3(lx, 0.0, -0.12)
	pt_lr = Vector3(lx + 0.1, 0.0, 0.12)
	pt_kn_l = lerpf(lerpf(0.1, 0.3, a), 0.55, c)
	pt_kn_r = lerpf(lerpf(0.1, 0.3, a), 0.45, c)
	pt_tor = Vector3(lerpf(0.1, 0.45, a), 0.0, 0.1 * sin(anim_clock * 4.0))
	pt_hd = Vector3(lerpf(-0.2, 0.5, a) + 0.1 * sin(anim_clock * 5.0), 0.0, 0.2 * sin(anim_clock * 3.0))
	_hang_arms(rp + pt_tor.x, 0.25)
	r_limb = 8.0
	r_body = 10.0

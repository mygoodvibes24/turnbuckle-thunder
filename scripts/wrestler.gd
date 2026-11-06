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
## Style points: every landed move / trick (kind "strike", "grapple", "aerial", "air_trick",
## "weapon", "movement", "super"); kind "break" (no name, 0 points) = we got hit or whiffed.
signal trick(name: String, points: int, kind: String)

enum S { IDLE, WALK, RUN, PUNCH, RUN_ATTACK, STUNNED, TIEUP_ATK, TIEUP_DEF, THROWING, THROWN,
	DOWN, GETTING_UP, PINNING, PINNED, TAUNT, WIN, LOSE,
	# --- appended states (keep the order above: the HUD refers to states by name) ---
	WHIFF,        # missed grab: short off-balance recovery (not the "got hit" stagger)
	GRAB_WINDUP,  # GRAB pressed, reaching out: release = weak lock-up, hold 0.3 s = strong
	WHIPPING,     # just Irish-whipped the opponent, waiting for them to come off the ropes
	STOMP,        # stomping a downed opponent
	GROUND_DROP,  # running elbow / knee drop onto a downed opponent (then lies DOWN briefly)
	PICKUP,       # hauling a downed opponent back to their feet
	LIFTED,       # being hauled up (ends dazed and STUNNED in front of the attacker)
	# --- weapons (see "# ---- weapons") ---
	PICKUP_ITEM,  # bending down to grab a chair / trash can / 2x4
	SWING,        # swinging the held item (standing, running or onto a downed opponent)
	THROW_ITEM,   # hurling the held item at the opponent
	ON_TABLE,     # lying on top of a set-up table, waiting to be put through it
	SET_TABLE,    # unfolding a table / dragging the downed opponent onto one
	# --- high flying (appended; see "# ---- high flying") ---
	CLIMB,        # climbing up / down a turnbuckle, or hopping down off it
	PERCHED,      # crouched on the top turnbuckle, waiting to fly
	DIVING,       # airborne: dives off the top, springboards, corner splash
	PERCH_FALL,   # knocked off the top: crotched on the turnbuckle or dumped to the mat
	CORNER_STUN,  # whipped into the turnbuckle: slumped in the corner
	# --- strike strings (appended; see "# ---- strike strings & grapple chains") ---
	JUGGLED }     # popped up by a launcher: airborne, can be juggled, caught or lariated

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
	# high flying ("time" = base flight time, "height" = arc apex above the straight line)
	"backyard_splash": {"name": "BACKYARD SPLASH!", "dmg": 16.0, "kind": "dive", "tier": "strong", "time": 0.8, "height": 1.0},
	"moonsault": {"name": "MOONSAULT!", "dmg": 17.0, "kind": "dive", "tier": "strong", "time": 0.9, "height": 1.2},
	"flying_elbow": {"name": "Flying Elbow off the top!", "dmg": 14.0, "kind": "dive", "tier": "ground", "time": 0.75, "height": 0.9},
	"gutter_star": {"name": "GUTTER STAR PRESS!!!", "dmg": 26.0, "kind": "dive", "tier": "finisher", "time": 1.0, "height": 1.5},
	"missile_dropkick": {"name": "Missile Dropkick!", "dmg": 14.0, "kind": "dive", "tier": "strike", "time": 0.6, "height": 0.6},
	"crossbody": {"name": "Flying Crossbody!", "dmg": 12.0, "kind": "dive", "tier": "strike", "time": 0.65, "height": 0.5},
	"springboard_forearm": {"name": "Springboard Forearm!", "dmg": 11.0, "kind": "dive", "tier": "strike", "time": 0.55, "height": 1.0},
	"springboard_moonsault": {"name": "SPRINGBOARD MOONSAULT!", "dmg": 14.0, "kind": "dive", "tier": "strike", "time": 0.8, "height": 1.3},
	"corner_splash": {"name": "Corner Splash!", "dmg": 10.0, "kind": "dive", "tier": "strike", "time": 0.3, "height": 0.3},
	"super_drop": {"name": "SUPER DROP!!", "dmg": 20.0, "kind": "throw", "tier": "strong", "time": 1.2, "height": 2.4, "land": -1.3, "flip": true},
	# --- grapple chains (see "# ---- strike strings & grapple chains"). "anim" = the thrower /
	# victim poses to reuse, "keys" = the victim path to reuse (defaults to anim), "pts" = style.
	"suplex_2": {"name": "Double-Down Suplex!", "anim": "suplex", "dmg": 9.0, "kind": "throw", "tier": "weak", "time": 1.0, "height": 2.1, "land": -1.2, "flip": true, "pts": 400},
	"triple_suplex": {"name": "TRIPLE THREAT SUPLEX!!!", "anim": "suplex", "keys": "triple_suplex", "dmg": 12.0, "kind": "throw", "tier": "strong", "time": 1.3, "height": 2.7, "land": -1.3, "flip": true, "pts": 900},
	"slam_2": {"name": "Back-to-Back Slam!", "anim": "slam", "dmg": 8.0, "kind": "throw", "tier": "weak", "time": 0.95, "height": 1.7, "land": 1.3, "flip": false, "pts": 350},
	"slam_bomb": {"name": "SLAM-BAM POWERBOMB!!", "anim": "powerbomb", "dmg": 14.0, "kind": "throw", "tier": "strong", "time": 1.25, "height": 2.4, "land": 1.1, "flip": false, "pts": 800},
	"ddt_2": {"name": "Double-Tap DDT!", "anim": "ddt", "dmg": 10.0, "kind": "throw", "tier": "weak", "time": 0.7, "height": 0.5, "land": 0.7, "flip": false, "pts": 450},
	"chain_neckbreaker": {"name": "Neckbreaker Encore!!", "anim": "neckbreaker", "dmg": 11.0, "kind": "throw", "tier": "strong", "time": 0.8, "height": 0.6, "land": -0.6, "flip": false, "pts": 650},
	"chain_elbow": {"name": "...and the ELBOW!", "dmg": 7.0, "kind": "ground", "tier": "ground", "pts": 300},
	"chain_stomp": {"name": "...and a STOMP!", "dmg": 5.0, "kind": "ground", "tier": "ground", "pts": 200},
	# launcher follow-up: caught out of the air
	"catch_slam": {"name": "CATCH & SLAM!", "anim": "powerslam", "keys": "catch_slam", "dmg": 12.0, "kind": "throw", "tier": "strong", "time": 0.75, "height": 1.0, "land": 1.0, "flip": false, "pts": 500},
	# --- BRAWL MODE supers (brawl_mode): same moves, higher, spinning, harder. "lift" = extra
	# height (m) through the air, "spin" = extra full pirouettes of the victim.
	"super_knee": {"name": "MEGATON KNEE!!", "anim": "knee", "dmg": 10.0, "kind": "strike", "tier": "weak", "pts": 700},
	"super_slam": {"name": "SKYSCRAPER SLAM!!", "anim": "slam", "dmg": 16.0, "kind": "throw", "tier": "strong", "time": 1.35, "height": 2.4, "land": 1.4, "flip": false, "pts": 1200, "lift": 1.0, "spin": 1},
	"super_suplex": {"name": "STRATOSPHERE SUPLEX!!", "anim": "suplex", "dmg": 19.0, "kind": "throw", "tier": "strong", "time": 1.45, "height": 3.0, "land": -1.3, "flip": true, "pts": 1300, "lift": 1.1, "spin": 1},
	"super_ddt": {"name": "DRILL BIT DDT!!", "anim": "ddt", "dmg": 19.0, "kind": "throw", "tier": "strong", "time": 1.05, "height": 1.4, "land": 0.8, "flip": false, "pts": 1200, "lift": 0.9, "spin": 2},
	"super_piledriver": {"name": "TECTONIC TOMBSTONE!!", "anim": "piledriver", "dmg": 24.0, "kind": "throw", "tier": "strong", "time": 1.55, "height": 2.3, "land": 0.8, "flip": true, "pts": 1500, "lift": 1.0, "spin": 1},
	"super_powerbomb": {"name": "THUNDERHEAD POWERBOMB!!", "anim": "powerbomb", "dmg": 23.0, "kind": "throw", "tier": "strong", "time": 1.6, "height": 3.2, "land": 1.2, "flip": false, "pts": 1500, "lift": 1.2, "spin": 1},
	"super_spinebuster": {"name": "CYCLONE SPINEBUSTER!!", "anim": "spinebuster", "dmg": 20.0, "kind": "throw", "tier": "strong", "time": 1.15, "height": 1.6, "land": 1.3, "flip": false, "pts": 1300, "lift": 0.7, "spin": 1},
	"super_neckbreaker": {"name": "WHIRLYBIRD NECKBREAKER!!", "anim": "neckbreaker", "dmg": 18.0, "kind": "throw", "tier": "strong", "time": 1.15, "height": 1.5, "land": -0.7, "flip": false, "pts": 1200, "lift": 0.9, "spin": 2},
	"super_finisher": {"name": "THUNDER DRIVER MAXIMUM!!!", "anim": "finisher", "dmg": 34.0, "kind": "throw", "tier": "finisher", "time": 1.75, "height": 3.4, "land": 0.9, "flip": true, "pts": 2500, "lift": 1.0, "spin": 1},
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
# N64-style backyard wrestlers in street clothes: chunky 8-sided low-poly parts built with SurfaceTool (smooth
# per-vertex normals for that Gouraud shading), matte per-vertex lit materials and
# tiny painted textures with bilinear filtering (the soft N64 blur).
#
# Pivot layout: pose_root sits at the pelvis (STAND_Y above the feet when standing)
# and hips is at pose_root's origin, so falls and throws rotate the body around
# the pelvis. Standing straight, the sneaker soles touch y = 0.
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
# All are drawn so that texture column w/2 is the front centre (u = 0.5); -x side at
# w/4, +x side at 3w/4, back seam at the edges.

func _px(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


func _new_img(w: int, h: int, c: Color) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


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


## Fills the image with a pattern: "plaid" (crossing bands, tiles every 8 px), "stripe"
## (horizontal bands every 6 px) or nothing.
func _paint_pattern(img: Image, pattern: String, base: Color, accent: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	match pattern:
		"plaid":
			var band := base.lerp(accent, 0.6)
			var cross := band.lerp(accent, 0.6)
			var thread := base.lightened(0.25)
			for y in h:
				for x in w:
					var hx := x % 8 < 3
					var hy := y % 8 < 3
					if hx and hy:
						img.set_pixel(x, y, cross)
					elif hx or hy:
						img.set_pixel(x, y, band)
					elif x % 8 == 5 or y % 8 == 5:
						img.set_pixel(x, y, thread)
		"stripe":
			var y0 := 1
			while y0 < h:
				_px(img, 0, y0, w, 2, accent)
				y0 += 6


func _torso_texture(skin: Color) -> ImageTexture:
	# 32x32 shirtless torso: soft pecs, belly line, darker flanks and back.
	var img := _new_img(32, 32, skin)
	var dk := skin.darkened(0.14)
	var lt := skin.lightened(0.07)
	_px(img, 0, 0, 6, 32, skin.darkened(0.06))
	_px(img, 26, 0, 6, 32, skin.darkened(0.06))
	_px(img, 0, 6, 1, 26, dk)
	_px(img, 31, 6, 1, 26, dk)
	_px(img, 6, 8, 3, 24, dk)
	_px(img, 23, 8, 3, 24, dk)
	_px(img, 10, 9, 12, 7, lt)
	_px(img, 10, 16, 5, 1, dk)
	_px(img, 17, 16, 5, 1, dk)
	_px(img, 15, 8, 2, 9, dk)
	_px(img, 15, 25, 2, 1, dk)          # navel
	return ImageTexture.create_from_image(img)


func _top_texture(top: String, base: Color, pattern: String, accent: Color, skin: Color) -> ImageTexture:
	# 32x32 shirt body. Rows ~0..8 are the shoulders/armpits, ~29..31 the hem.
	var img := _new_img(32, 32, base)
	var dk := base.darkened(0.22)
	var lt := base.lightened(0.15)
	_paint_pattern(img, pattern, base, accent)
	if pattern == "logo":
		# generic garage-band print on the chest: a ring, a jagged bolt, blocky letters
		for y in range(6, 19):
			for x in range(10, 23):
				var d := Vector2(x + 0.5 - 16.0, y + 0.5 - 12.5).length()
				if d < 5.8 and d > 4.3:
					img.set_pixel(x, y, accent)
		var bolt := lt.lerp(Color(1.0, 0.95, 0.6), 0.6)
		_px(img, 16, 9, 2, 2, bolt)
		_px(img, 15, 11, 2, 1, bolt)
		_px(img, 15, 12, 4, 1, bolt)
		_px(img, 16, 13, 2, 2, bolt)
		_px(img, 15, 15, 1, 1, bolt)
		_paint_text(img, "TRV", 16, 20, accent)
		_px(img, 2, 8, 3, 6, accent)      # small print on the back
		_px(img, 27, 8, 3, 6, accent)
	# wrinkles: armpit folds and creases bunching at the waist
	var fold := base.darkened(0.12)
	for k in 3:
		img.set_pixel(7 + k, 22 + k * 2, fold)
		img.set_pixel(8 + k, 23 + k * 2, fold)
		img.set_pixel(24 - k, 22 + k * 2, fold)
		img.set_pixel(23 - k, 23 + k * 2, fold)
		img.set_pixel(12 + k * 3, 27, fold)
	img.set_pixel(9, 9, fold)
	img.set_pixel(22, 9, fold)
	match top:
		"tank":
			_px(img, 5, 0, 6, 9, skin)          # arm holes
			_px(img, 21, 0, 6, 9, skin)
			_px(img, 12, 0, 8, 4, skin)         # scoop neck
			_px(img, 13, 4, 6, 1, skin)
			_px(img, 0, 0, 3, 2, skin)
			_px(img, 29, 0, 3, 2, skin)
			_px(img, 4, 0, 1, 9, dk)
			_px(img, 11, 0, 1, 9, dk)
			_px(img, 20, 0, 1, 9, dk)
			_px(img, 27, 0, 1, 9, dk)
			_px(img, 5, 9, 6, 1, dk)
			_px(img, 21, 9, 6, 1, dk)
		"flannel":
			# sleeves torn off: ragged arm holes with loose white threads
			var thread := Color(0.92, 0.9, 0.84)
			_px(img, 6, 1, 4, 8, skin)
			_px(img, 22, 1, 4, 8, skin)
			for r in range(1, 9, 2):
				img.set_pixel(5, r, thread)
				img.set_pixel(10, r + 1, thread)
				img.set_pixel(21, r + 1, thread)
				img.set_pixel(26, r, thread)
			# button placket + buttons, chest pockets
			_px(img, 15, 2, 2, 30, dk)
			for by in [6, 11, 16, 21, 26]:
				var yy: int = by
				_px(img, 15, yy, 1, 1, thread)
			_px(img, 10, 9, 4, 5, dk)
			_px(img, 11, 10, 2, 3, base)
			_px(img, 18, 9, 4, 5, dk)
			_px(img, 19, 10, 2, 3, base)
		"hoodie":
			# kangaroo pocket, centre seam, ribbed hem
			_px(img, 9, 19, 14, 8, dk)
			_px(img, 10, 20, 12, 6, base.darkened(0.06))
			_px(img, 9, 19, 2, 8, base.darkened(0.3))
			_px(img, 21, 19, 2, 8, base.darkened(0.3))
			_px(img, 0, 27, 32, 5, dk)
			for x in range(0, 32, 2):
				_px(img, x, 27, 1, 5, base.darkened(0.3))
		_:
			_px(img, 11, 0, 10, 2, dk)          # tee neckline ribbing
	if top != "hoodie":
		_px(img, 0, 30, 32, 2, dk)              # hem
	return ImageTexture.create_from_image(img)


func _sleeve_texture(base: Color, pattern: String, accent: Color, cuff: bool) -> ImageTexture:
	# 16x16 sleeve: pattern, a crease, and a hem (or ribbed cuff) at the bottom.
	var img := _new_img(16, 16, base)
	_paint_pattern(img, pattern, base, accent)
	var dk := base.darkened(0.22)
	img.set_pixel(7, 6, base.darkened(0.12))
	img.set_pixel(8, 7, base.darkened(0.12))
	img.set_pixel(9, 8, base.darkened(0.12))
	if cuff:
		_px(img, 0, 12, 16, 4, dk)
		for x in range(0, 16, 2):
			_px(img, x, 12, 1, 4, base.darkened(0.32))
	else:
		_px(img, 0, 14, 16, 2, dk)
	return ImageTexture.create_from_image(img)


func _bottoms_texture(kind: String, base: Color, accent: Color) -> ImageTexture:
	# 32x16 pelvis piece: waistband/belt, fly, pockets.
	var img := _new_img(32, 16, base)
	var dk := base.darkened(0.25)
	var lt := base.lightened(0.14)
	var white := Color(0.94, 0.94, 0.9)
	match kind:
		"basketball_shorts":
			_px(img, 0, 0, 32, 3, accent)
			_px(img, 0, 1, 32, 1, accent.lightened(0.2))
			_px(img, 6, 3, 3, 13, accent)       # side stripes
			_px(img, 23, 3, 3, 13, accent)
			_px(img, 7, 3, 1, 13, white)
			_px(img, 24, 3, 1, 13, white)
			_px(img, 15, 3, 1, 4, white)        # drawstring
			_px(img, 17, 3, 1, 4, white)
		"sweatpants":
			_px(img, 0, 0, 32, 3, dk)
			for x in range(0, 32, 2):
				_px(img, x, 0, 1, 3, base.darkened(0.12))
			_px(img, 15, 3, 1, 5, white)
			_px(img, 17, 3, 1, 5, white)
			_px(img, 7, 3, 1, 13, accent)
			_px(img, 24, 3, 1, 13, accent)
		_:
			# jeans / cargo shorts: belt + buckle, loops, fly, front and back pockets
			var belt := Color(0.22, 0.14, 0.08)
			_px(img, 0, 0, 32, 2, belt)
			_px(img, 14, 0, 4, 2, Color(0.78, 0.72, 0.5))
			_px(img, 15, 0, 2, 1, belt)
			for lx in [4, 10, 21, 27]:
				var xx: int = lx
				_px(img, xx, 0, 1, 3, dk)
			_px(img, 16, 2, 1, 8, dk)
			_px(img, 17, 8, 1, 2, dk)
			_px(img, 10, 2, 1, 3, dk)
			_px(img, 11, 5, 2, 1, dk)
			_px(img, 21, 2, 1, 3, dk)
			_px(img, 19, 5, 2, 1, dk)
			_px(img, 1, 4, 6, 6, dk)            # back pockets
			_px(img, 2, 5, 4, 4, base.darkened(0.08))
			_px(img, 25, 4, 6, 6, dk)
			_px(img, 26, 5, 4, 4, base.darkened(0.08))
			if kind == "jeans":
				_px(img, 12, 3, 3, 1, lt)       # whiskers
				_px(img, 18, 3, 3, 1, lt)
				_px(img, 13, 5, 2, 1, lt)
				_px(img, 18, 5, 2, 1, lt)
	return ImageTexture.create_from_image(img)


func _legwear_texture(kind: String, part: String, base: Color, accent: Color, side: int, skin: Color) -> ImageTexture:
	# 32x16 for a thigh ("thigh", also used by the shorts shell) or a shin ("shin").
	# The outer side of a left leg is u = 0.25 (x 8), of a right leg u = 0.75 (x 24).
	var img := _new_img(32, 16, base)
	var dk := base.darkened(0.25)
	var lt := base.lightened(0.12)
	var ox := 8 if side < 0 else 24
	match kind:
		"jeans":
			_px(img, 11, 0, 10, 16, base.lightened(0.06))    # stone-washed front
			_px(img, ox, 0, 1, 16, dk)                       # outseam
			_px(img, 32 - ox, 0, 1, 16, dk)
			if part == "thigh":
				for k in 3:
					_px(img, 12 + k, 2 + k * 2, 3, 1, lt)    # whiskers
					_px(img, 18 - k, 2 + k * 2, 3, 1, lt)
				if side > 0:
					# ripped knee: skin showing through with frayed white threads
					_px(img, 12, 11, 8, 4, skin)
					_px(img, 12, 12, 8, 1, Color(0.92, 0.9, 0.85))
					_px(img, 13, 14, 6, 1, Color(0.92, 0.9, 0.85))
			else:
				for r in [10, 12, 14]:
					var yy: int = r
					_px(img, 10 + (yy % 3), yy, 5, 1, dk)    # stacked creases at the ankle
					_px(img, 18 - (yy % 3), yy, 5, 1, dk)
		"cargo_shorts":
			_px(img, 16, 0, 1, 16, dk)                       # front crease
			_px(img, ox - 3, 5, 7, 9, dk)                    # big side cargo pocket
			_px(img, ox - 2, 7, 5, 6, base.darkened(0.08))
			_px(img, ox - 3, 5, 7, 2, base.darkened(0.15))   # flap
			_px(img, ox, 6, 1, 1, Color(0.2, 0.18, 0.15))    # snap
			_px(img, 0, 14, 32, 2, dk)                       # hem
			img.set_pixel(13, 9, dk)
			img.set_pixel(19, 10, dk)
		"basketball_shorts":
			_px(img, ox - 1, 0, 3, 16, accent)               # side panel
			_px(img, ox, 0, 1, 16, Color(0.94, 0.94, 0.9))
			_px(img, 0, 13, 32, 3, accent)                   # hem band
			for x in range(0, 32, 3):
				img.set_pixel(x, 6, base.darkened(0.1))      # mesh speckle
				img.set_pixel(x + 1, 9, base.darkened(0.1))
		"sweatpants":
			_px(img, ox, 0, 1, 16, accent)
			if part == "shin":
				_px(img, 0, 12, 32, 4, dk)                   # elastic cuff
			else:
				img.set_pixel(14, 5, dk)
				img.set_pixel(18, 8, dk)
	return ImageTexture.create_from_image(img)


func _sock_texture(base: Color, accent: Color) -> ImageTexture:
	# 16x8 tube sock: two stripes at the top, ribbing.
	var img := _new_img(16, 8, base)
	_px(img, 0, 1, 16, 1, accent)
	_px(img, 0, 3, 16, 1, accent)
	for x in range(0, 16, 2):
		_px(img, x, 4, 1, 4, base.darkened(0.07))
	return ImageTexture.create_from_image(img)


func _shoe_texture(base: Color, accent: Color) -> ImageTexture:
	# 16x16 sneaker upper: padded collar, a generic swoop stripe down each side,
	# lace panel with criss-cross white laces at the front, heel tab at the back.
	var img := _new_img(16, 16, base)
	var lace := Color(0.96, 0.96, 0.93)
	_px(img, 0, 0, 16, 3, base.darkened(0.3))
	_px(img, 0, 1, 16, 1, base.darkened(0.15))
	for k in 8:
		_px(img, 2 + int(k / 3.0), 4 + k, 3, 1, accent)       # -x side swoop
		_px(img, 11 - int(k / 3.0), 4 + k, 3, 1, accent)      # +x side swoop
	_px(img, 6, 2, 4, 14, base.darkened(0.2))
	for r in range(3, 16):
		if r % 2 == 1:
			_px(img, 6, r, 1, 1, lace)
			_px(img, 9, r, 1, 1, lace)
		else:
			_px(img, 7, r, 2, 1, lace)
	_px(img, 0, 0, 1, 16, accent)
	_px(img, 15, 0, 1, 16, accent)
	return ImageTexture.create_from_image(img)


func _brace_texture() -> ImageTexture:
	# 16x8 knee brace: black neoprene, grey patella ring at the front, velcro straps.
	var img := _new_img(16, 8, Color(0.08, 0.08, 0.09))
	var grey := Color(0.45, 0.45, 0.48)
	_px(img, 0, 0, 16, 1, grey)
	_px(img, 0, 7, 16, 1, grey)
	_px(img, 6, 2, 4, 4, grey)
	_px(img, 7, 3, 2, 2, Color(0.08, 0.08, 0.09))
	_px(img, 2, 1, 1, 6, Color(0.2, 0.2, 0.22))
	_px(img, 13, 1, 1, 6, Color(0.2, 0.2, 0.22))
	return ImageTexture.create_from_image(img)


func _cap_texture(base: Color) -> ImageTexture:
	# 16x8 ball-cap crown: panel seams, button on top, eyelets.
	var img := _new_img(16, 8, base)
	var dk := base.darkened(0.25)
	for x in [0, 4, 8, 12]:
		var xx: int = x
		_px(img, xx, 0, 1, 8, dk)
	_px(img, 0, 0, 16, 1, dk)
	img.set_pixel(2, 3, dk)
	img.set_pixel(6, 3, dk)
	img.set_pixel(10, 3, dk)
	img.set_pixel(14, 3, dk)
	return ImageTexture.create_from_image(img)


func _head_texture(skin: Color, hair_c: Color, style: String) -> ImageTexture:
	# 64x32 wrap-around head texture: face on the front (columns ~22..41), ears at the
	# sides (u 0.25 / 0.75), hair or mask seams at the back.
	var dark := Color(0.12, 0.07, 0.05)
	var shade := skin.darkened(0.22)
	if look.get("mask", false):
		var mask_src: Color = look.get("mask_color", Color(0.12, 0.3, 0.85))
		var trim_src: Color = look.get("mask_trim", Color(1.0, 0.55, 0.1))
		var mask := _sat(mask_src)
		var trim := _sat(trim_src)
		var hot := trim.lerp(Color(1.0, 1.0, 1.0), 0.45)
		var mimg := _new_img(64, 32, mask)
		# cheap party-store luchador mask: pointed eye surrounds, forehead diamond,
		# zigzag side trim, visible stitched seams and an elastic strap at the back.
		for r in range(9, 22):
			var hw := 6 - absi(r - 15)
			if hw > 0:
				_px(mimg, 29 - hw, r, hw * 2, 1, trim)
				_px(mimg, 35 - hw, r, hw * 2, 1, trim)
		for r in range(2, 10):
			var dw := 3 - absi(r - 6)
			if dw > 0:
				_px(mimg, 32 - dw, r, dw * 2, 1, hot)
		_px(mimg, 31, 0, 2, 2, trim)
		_px(mimg, 27, 14, 4, 3, Color.WHITE)       # eye holes
		_px(mimg, 33, 14, 4, 3, Color.WHITE)
		_px(mimg, 28, 14, 2, 3, dark)
		_px(mimg, 34, 14, 2, 3, dark)
		_px(mimg, 28, 23, 8, 4, skin)              # mouth hole
		_px(mimg, 29, 24, 6, 1, dark)
		_px(mimg, 30, 25, 4, 1, shade)
		for x in range(2, 62):
			if x > 21 and x < 43:
				continue
			_px(mimg, x, 19 + (1 if x % 4 < 2 else 0), 1, 2, trim)
		var seam := mask.darkened(0.3)
		_px(mimg, 16, 0, 1, 18, seam)
		_px(mimg, 48, 0, 1, 18, seam)
		_px(mimg, 0, 12, 1, 18, seam)
		_px(mimg, 63, 12, 1, 18, seam)
		_px(mimg, 0, 24, 6, 2, Color(0.1, 0.1, 0.1))   # elastic strap
		_px(mimg, 58, 24, 6, 2, Color(0.1, 0.1, 0.1))
		_px(mimg, 0, 30, 64, 2, trim)               # bottom hem
		return ImageTexture.create_from_image(mimg)

	var img := _new_img(64, 32, skin)
	_px(img, 0, 28, 64, 4, skin.darkened(0.12))   # under the jaw
	_px(img, 22, 17, 4, 10, skin.darkened(0.07))  # cheek shading
	_px(img, 38, 17, 4, 10, skin.darkened(0.07))
	if look.get("stubble", false):
		_px(img, 23, 21, 18, 8, shade.lerp(hair_c, 0.3))
	var facial: String = look.get("facial", "none")
	if facial == "goatee":
		_px(img, 28, 23, 8, 2, hair_c)        # moustache
		_px(img, 27, 24, 1, 4, hair_c)
		_px(img, 36, 24, 1, 4, hair_c)
		_px(img, 28, 27, 8, 4, hair_c)        # chin beard
	# brows, eyes, nose shading, smirk
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
	_px(img, 34, 24, 1, 1, dark)
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
# Backyard street clothes: the clothes are lofted shells a little larger than the body
# parts they cover (shirt over the torso, sleeves over the upper arms, shorts flaring
# over the thighs, jeans legs, chunky sneakers). look keys (all optional):
#   top: "tshirt" | "tank" | "flannel" | "hoodie" | "shirtless"; top_color, top_accent,
#   top_pattern: "plaid" | "stripe" | "logo" | "none"; sleeves (hoodie): "long" | "cut"
#   bottom: "jeans" | "cargo_shorts" | "basketball_shorts" | "sweatpants"; bottom_color,
#   bottom_accent; shoes: "hightops" | "skate"; shoe_color, shoe_accent; sock_l, sock_r,
#   sock_accent; hat: "cap_back" | "beanie" | "none"; hat_color; wristband_color;
#   knee_brace: "left" | "right" | "both" | "none"; facial: "goatee" | "none"; stubble;
#   hair, hair_color, mask, mask_color, mask_trim; bulk (0.8..1.25, torso width and
#   limb thickness; pivots never move); gut (0..0.06, belly push).

var hand_r: Node3D  # right fist attach point (child of elbow_r): held items go here
var hand_l: Node3D


## Scales the radii of loft rings (x by kx, z and the z offset by kz) and adds a margin.
func _bulked(rings: Array, kx: float, kz: float, add := 0.0) -> Array:
	var out: Array = []
	for r in rings:
		var v: Vector4 = r
		out.append(Vector4(v.x, v.y * kx + add, v.z * kz + add, v.w * kz))
	return out


func _build_body() -> void:
	var skin_c := _sat(skin_color, 1.12)
	var hair_c: Color = look.get("hair_color", Color(0.15, 0.1, 0.07))
	var hair_style: String = look.get("hair", "none")
	var is_mask: bool = look.get("mask", false)
	var top: String = look.get("top", "tshirt")
	var top_src: Color = look.get("top_color", gear_color)
	var top_c := _sat(top_src)
	var top_pattern: String = look.get("top_pattern", "none")
	var top_acc_src: Color = look.get("top_accent", top_src.darkened(0.5))
	var top_acc := _sat(top_acc_src)
	var sleeves: String = look.get("sleeves", "long")
	var bottom: String = look.get("bottom", "jeans")
	var bot_src: Color = look.get("bottom_color", Color(0.24, 0.34, 0.58))
	var bot_c := _sat(bot_src, 1.0)
	var bot_acc_src: Color = look.get("bottom_accent", gear_color)
	var bot_acc := _sat(bot_acc_src)
	var shoes: String = look.get("shoes", "hightops")
	var shoe_src: Color = look.get("shoe_color", gear_color)
	var shoe_acc_src: Color = look.get("shoe_accent", Color(0.95, 0.95, 0.95))
	var sock_l_src: Color = look.get("sock_l", Color(0.95, 0.95, 0.92))
	var sock_r_src: Color = look.get("sock_r", sock_l_src)
	var sock_acc_src: Color = look.get("sock_accent", gear_color)
	var hat: String = look.get("hat", "none")
	var hat_src: Color = look.get("hat_color", gear_color)
	var brace: String = look.get("knee_brace", "none")
	var facial: String = look.get("facial", "none")
	var bulk_v: float = look.get("bulk", 1.0)
	var bulk := clampf(bulk_v, 0.8, 1.25)
	var gut_v: float = look.get("gut", 0.0)
	var gut := clampf(gut_v, 0.0, 0.06)
	var kx := bulk
	var kz := lerpf(1.0, bulk, 0.4)   # depth grows less, so lying poses stay on the mat

	var skin := _mat(skin_c)
	var skin_dark := _mat(skin_c.darkened(0.12))
	var hair := _mat(hair_c)
	var white := _mat(Color(0.95, 0.95, 0.92))
	var top_solid := _mat(top_c)
	var top_dark := _mat(top_c.darkened(0.25))
	var torso_mat: Material
	if top == "shirtless":
		torso_mat = _mat(Color.WHITE, _torso_texture(skin_c))
	else:
		torso_mat = _mat(Color.WHITE, _top_texture(top, top_c, top_pattern, top_acc, skin_c))
	var head_mat := _mat(Color.WHITE, _head_texture(skin_c, hair_c, hair_style))
	var head_solid := skin
	if is_mask:
		var mask_src: Color = look.get("mask_color", gear_color)
		head_solid = _mat(_sat(mask_src))

	var m := {
		"skin": skin, "skin_dark": skin_dark, "white": white, "top_solid": top_solid,
		"top_dark": top_dark,
		"sleeve": _mat(Color.WHITE, _sleeve_texture(top_c, top_pattern, top_acc, top == "hoodie")),
		"bottom_dark": _mat(bot_c.darkened(0.2)),
		"thigh_l": _mat(Color.WHITE, _legwear_texture(bottom, "thigh", bot_c, bot_acc, -1, skin_c)),
		"thigh_r": _mat(Color.WHITE, _legwear_texture(bottom, "thigh", bot_c, bot_acc, 1, skin_c)),
		"shin_l": _mat(Color.WHITE, _legwear_texture(bottom, "shin", bot_c, bot_acc, -1, skin_c)),
		"shin_r": _mat(Color.WHITE, _legwear_texture(bottom, "shin", bot_c, bot_acc, 1, skin_c)),
		"sock_l": _mat(Color.WHITE, _sock_texture(_sat(sock_l_src, 1.0), _sat(sock_acc_src))),
		"sock_r": _mat(Color.WHITE, _sock_texture(_sat(sock_r_src, 1.0), _sat(sock_acc_src))),
		"shoe": _mat(Color.WHITE, _shoe_texture(_sat(shoe_src), _sat(shoe_acc_src))),
		"shoe_plain": _mat(_sat(shoe_src)),
		"shoe_accent": _mat(_sat(shoe_acc_src)),
		"brace": _mat(Color.WHITE, _brace_texture()),
		"wristband": null,
	}
	if look.has("wristband_color"):
		var wb_src: Color = look.get("wristband_color", Color.WHITE)
		m["wristband"] = _mat(_sat(wb_src))

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

	# Pelvis: the waist of the shorts / jeans (belt, fly and pockets painted on)
	var bot_add := 0.02 if bottom == "basketball_shorts" else 0.008
	var pelvis_mi := _loft(hips, _bulked([
		Vector4(0.17, 0.285, 0.19, 0.0), Vector4(0.12, 0.29, 0.195, 0.0), Vector4(0.0, 0.28, 0.195, 0.0),
		Vector4(-0.1, 0.25, 0.18, 0.0), Vector4(-0.17, 0.16, 0.13, 0.0)], kx, kz, bot_add),
		_mat(Color.WHITE, _bottoms_texture(bottom, bot_c, bot_acc)))
	pelvis_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Torso: bare chest, or an untucked shirt whose hem hangs over the waistband
	torso = _pivot(hips, Vector3(0, 0.12, 0))
	var torso_rings: Array
	if top == "shirtless":
		torso_rings = _bulked([
			Vector4(0.64, 0.11, 0.09, -0.01), Vector4(0.58, 0.27, 0.15, -0.02), Vector4(0.48, 0.37, 0.2, 0.0),
			Vector4(0.34, 0.355, 0.215 + gut * 0.4, 0.01 + gut * 0.3),
			Vector4(0.2, 0.3, 0.19 + gut, gut * 0.7), Vector4(0.0, 0.26, 0.17 + gut * 0.7, gut * 0.5)], kx, kz)
	else:
		var lx := 0.035 if top == "hoodie" else 0.012
		var lz := 0.018 if top == "hoodie" else 0.01
		var hem_y := -0.12 if top == "hoodie" else -0.1
		torso_rings = [
			Vector4(0.66, 0.11, 0.095, -0.01),
			Vector4(0.6, 0.28 * kx + lx, 0.16 * kz + lz, -0.02),
			Vector4(0.48, 0.38 * kx + lx, 0.21 * kz + lz, 0.0),
			Vector4(0.34, 0.365 * kx + lx, 0.225 * kz + lz + gut * 0.4, 0.01 + gut * 0.3),
			Vector4(0.18, 0.315 * kx + lx, 0.205 * kz + lz + gut, gut * 0.7),
			Vector4(0.0, 0.3 * kx + lx, 0.205 * kz + lz + gut * 0.8, gut * 0.5),
			Vector4(hem_y, 0.315 * kx + lx, 0.212 * kz + lz + gut * 0.5, gut * 0.3)]
		if top == "hoodie":
			torso_rings.append(Vector4(hem_y - 0.04, 0.295 * kx + lx, 0.2 * kz + lz, gut * 0.2))  # ribbed hem
	var torso_mi := _add_mesh(torso, _loft_mesh(torso_rings, true, true), Vector3.ZERO, torso_mat)
	torso_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Collars and the hoodie's hood bunched up on the back
	match top:
		"tshirt":
			_loft(torso, [Vector4(0.67, 0.112, 0.102, -0.008), Vector4(0.62, 0.13, 0.118, -0.004)], top_dark, false, false)
		"flannel":
			_loft(torso, [Vector4(0.7, 0.122, 0.11, -0.012), Vector4(0.61, 0.16, 0.14, -0.004)], top_dark, false, false)
		"hoodie":
			_loft(torso, [Vector4(0.69, 0.135, 0.125, -0.025), Vector4(0.6, 0.175, 0.155, -0.035)], top_solid, false, false)
			_ball(torso, 0.15, Vector3(0, 0.6, -0.14), top_solid, Vector3(1.15 * kx, 0.55, 0.45))  # hood lump
			var fz := (0.21 * kz + 0.018) * 0.93 + 0.01
			for sx in [-0.045, 0.045]:
				var dx: float = sx
				_box(torso, Vector3(0.012, 0.13, 0.012), Vector3(dx, 0.52, fz), white)      # drawstrings
				_box(torso, Vector3(0.018, 0.025, 0.018), Vector3(dx, 0.445, fz), top_dark)  # aglets

	# Neck + head (head ~0.33 wide x 0.36 tall x 0.35 deep, top ~2.03 m when standing)
	var kn := lerpf(1.0, bulk, 0.6)
	_loft(torso, _bulked([Vector4(0.72, 0.095, 0.095, 0.02), Vector4(0.52, 0.115, 0.11, 0.0)], kn, kn), skin, false, false)
	head = _pivot(torso, Vector3(0, 0.6, 0.02))
	_loft(head, [
		Vector4(0.36, 0.075, 0.085, -0.01), Vector4(0.32, 0.15, 0.16, -0.005), Vector4(0.22, 0.165, 0.175, 0.0),
		Vector4(0.12, 0.16, 0.172, 0.005), Vector4(0.05, 0.13, 0.15, 0.012), Vector4(0.0, 0.085, 0.1, 0.005)], head_mat)
	_box(head, Vector3(0.05, 0.065, 0.05), Vector3(0, 0.145, 0.172), head_solid)       # nose
	if hair_style != "long" or hat != "none":
		_box(head, Vector3(0.04, 0.08, 0.06), Vector3(-0.168, 0.17, -0.01), head_solid)  # ears
		_box(head, Vector3(0.04, 0.08, 0.06), Vector3(0.168, 0.17, -0.01), head_solid)
	if facial == "goatee" and not is_mask:
		_box(head, Vector3(0.06, 0.05, 0.03), Vector3(0, 0.035, 0.145), hair)             # chin tuft
	if not is_mask and hat == "none":
		match hair_style:
			"flattop":
				_box(head, Vector3(0.3, 0.09, 0.32), Vector3(0, 0.345, -0.005), hair)
			"long":
				_box(head, Vector3(0.3, 0.34, 0.07), Vector3(0, 0.13, -0.165), hair)
				_box(head, Vector3(0.34, 0.06, 0.3), Vector3(0, 0.33, -0.02), hair)
			"mohawk":
				_box(head, Vector3(0.06, 0.1, 0.32), Vector3(0, 0.36, -0.01), hair)
	var hat_c := _sat(hat_src)
	match hat:
		"cap_back":
			var cap_mat := _mat(Color.WHITE, _cap_texture(hat_c))
			_loft(head, [Vector4(0.395, 0.035, 0.035, 0.0), Vector4(0.37, 0.125, 0.135, -0.005),
				Vector4(0.31, 0.172, 0.182, -0.005), Vector4(0.24, 0.18, 0.19, 0.0)], cap_mat, true, false)
			var brim := _box(head, Vector3(0.2, 0.018, 0.13), Vector3(0, 0.265, -0.21), _mat(hat_c.darkened(0.15)))
			brim.rotation.x = 0.6                                                        # bill tipped up at the back
			_box(head, Vector3(0.07, 0.035, 0.012), Vector3(0, 0.265, 0.172), skin)       # strap gap at the forehead
			_box(head, Vector3(0.08, 0.008, 0.014), Vector3(0, 0.282, 0.173), _mat(hat_c.darkened(0.35)))
		"beanie":
			var bn := _mat(hat_c)
			_loft(head, [Vector4(0.42, 0.04, 0.04, 0.0), Vector4(0.39, 0.13, 0.14, -0.01),
				Vector4(0.32, 0.172, 0.182, -0.005), Vector4(0.25, 0.18, 0.19, 0.0)], bn, true, false)
			_loft(head, [Vector4(0.27, 0.186, 0.196, 0.0), Vector4(0.2, 0.184, 0.194, 0.0)], _mat(hat_c.darkened(0.2)), false, false)

	# Arms: shoulder -> elbow -> fist
	arm_l = _build_arm(-1, m, top, sleeves, bulk)
	arm_r = _build_arm(1, m, top, sleeves, bulk)

	# Legs: hip -> knee -> sneaker
	leg_l = _build_leg(-1, m, bottom, shoes, bulk, brace == "left" or brace == "both")
	leg_r = _build_leg(1, m, bottom, shoes, bulk, brace == "right" or brace == "both")


func _build_arm(side: int, m: Dictionary, top: String, sleeves: String, bulk: float) -> Node3D:
	var skin: Material = m["skin"]
	var skin_dark: Material = m["skin_dark"]
	var sleeve: Material = m["sleeve"]
	var top_solid: Material = m["top_solid"]
	var top_dark: Material = m["top_dark"]
	var k := bulk
	var sh := _pivot(torso, Vector3(0.42 * side, 0.47, 0))
	_ball(sh, 0.13 * k, Vector3(0.01 * side, -0.01, 0), skin)                             # deltoid
	_loft(sh, _bulked([Vector4(0.03, 0.105, 0.105, 0.0), Vector4(-0.12, 0.115, 0.12, 0.01),
		Vector4(-0.34, 0.08, 0.085, 0.0)], k, k), skin)                                    # upper arm
	var hoodie_sleeves := top == "hoodie" and sleeves != "cut"
	if top == "tshirt" or hoodie_sleeves:
		var a := 0.03 if top == "hoodie" else 0.016
		_ball(sh, 0.13 * k + a, Vector3(0.01 * side, -0.005, 0), top_solid)                # shirt shoulder
	if top == "tshirt":
		_loft(sh, _bulked([Vector4(0.02, 0.12, 0.12, 0.0), Vector4(-0.17, 0.122, 0.128, 0.01)], k, k, 0.022),
			sleeve, false, false)                                                           # short sleeve
	elif hoodie_sleeves:
		_loft(sh, _bulked([Vector4(0.03, 0.12, 0.12, 0.0), Vector4(-0.15, 0.125, 0.13, 0.01),
			Vector4(-0.36, 0.1, 0.105, 0.0)], k, k, 0.032), top_solid, false, false)        # baggy upper sleeve
	var el := _pivot(sh, Vector3(0, -0.32, 0))
	if side < 0:
		elbow_l = el
	else:
		elbow_r = el
	_loft(el, _bulked([Vector4(0.02, 0.085, 0.085, 0.0), Vector4(-0.09, 0.095, 0.09, 0.005),
		Vector4(-0.27, 0.065, 0.065, 0.0)], k, k), skin)                                    # forearm
	if hoodie_sleeves:
		_loft(el, _bulked([Vector4(0.05, 0.1, 0.1, 0.0), Vector4(-0.1, 0.1, 0.098, 0.005),
			Vector4(-0.2, 0.085, 0.085, 0.0)], k, k, 0.028), sleeve, false, false)          # lower sleeve + cuff
		_loft(el, _bulked([Vector4(-0.19, 0.075, 0.075, 0.0), Vector4(-0.24, 0.07, 0.07, 0.0)], k, k, 0.018),
			top_dark, false, false)
	var band: Material = m["wristband"]
	if band != null:
		_loft(el, _bulked([Vector4(-0.18, 0.078, 0.078, 0.0), Vector4(-0.27, 0.072, 0.072, 0.0)], k, k, 0.01),
			band)                                                                           # sweatband
	var kf := lerpf(1.0, bulk, 0.5)
	_box(el, Vector3(0.13, 0.12, 0.14) * kf, Vector3(0, -0.33, 0.005), skin)              # fist
	_box(el, Vector3(0.115 * kf, 0.035, 0.02), Vector3(0, -0.36, 0.005 + 0.075 * kf), skin_dark)  # knuckles
	var hand := _pivot(el, Vector3(0, -0.33, 0.005))
	if side < 0:
		hand_l = hand
	else:
		hand_r = hand
	return sh


func _build_leg(side: int, m: Dictionary, bottom: String, shoes: String, bulk: float, brace: bool) -> Node3D:
	# hip pivot at 0.89 m, knee at 0.46 m, sole at 0.0 m when standing straight
	var skin: Material = m["skin"]
	var thigh_tex: Material = m["thigh_l"] if side < 0 else m["thigh_r"]
	var shin_tex: Material = m["shin_l"] if side < 0 else m["shin_r"]
	var sock: Material = m["sock_l"] if side < 0 else m["sock_r"]
	var k := bulk
	var long_pants := bottom == "jeans" or bottom == "sweatpants"
	var hp := _pivot(hips, Vector3(0.14 * side, -0.06, 0))
	var thigh_rings := [Vector4(0.07, 0.135, 0.14, 0.0), Vector4(-0.12, 0.14, 0.15, 0.005),
		Vector4(-0.3, 0.115, 0.125, 0.005), Vector4(-0.45, 0.095, 0.1, 0.0)]
	var thigh: MeshInstance3D
	if long_pants:
		thigh = _loft(hp, _bulked(thigh_rings, k, k, 0.016), thigh_tex)                    # pant leg
	else:
		thigh = _loft(hp, _bulked(thigh_rings, k, k), skin)                                # bare thigh
		var flare := 0.055 if bottom == "basketball_shorts" else 0.04
		var low := -0.44 if bottom == "basketball_shorts" else -0.37
		var shorts := _add_mesh(hp, _loft_mesh([Vector4(0.08, 0.15 * k + 0.02, 0.155 * k + 0.02, 0.0),
			Vector4(-0.1, 0.155 * k + 0.026, 0.165 * k + 0.026, 0.005),
			Vector4(low, 0.14 * k + flare, 0.145 * k + flare, 0.01)], false, false), Vector3.ZERO, thigh_tex)  # shorts leg
		shorts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if bottom == "cargo_shorts":
			var pocket: Material = m["bottom_dark"]
			var px := (0.15 * k + 0.033) * 0.93 + 0.012
			_box(hp, Vector3(0.026, 0.12, 0.11), Vector3(px * side, -0.24, 0.0), pocket)     # cargo pocket
			_box(hp, Vector3(0.03, 0.03, 0.115), Vector3((px + 0.004) * side, -0.18, 0.0), pocket)  # flap
	thigh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var kn := _pivot(hp, Vector3(0, -0.43, 0))
	if side < 0:
		knee_l = kn
	else:
		knee_r = kn
	var knee_rings := [Vector4(0.06, 0.106, 0.112, 0.01), Vector4(0.0, 0.114, 0.12, 0.014),
		Vector4(-0.07, 0.1, 0.108, 0.01)]
	if brace:
		var brace_mat: Material = m["brace"]
		_loft(kn, _bulked([Vector4(0.1, 0.11, 0.116, 0.008), Vector4(0.0, 0.118, 0.124, 0.014),
			Vector4(-0.1, 0.104, 0.112, 0.008)], k, k, 0.014), brace_mat)                 # knee brace
	elif long_pants:
		_loft(kn, _bulked(knee_rings, k, k, 0.016), thigh_tex)                             # pants over the knee
	else:
		_loft(kn, _bulked(knee_rings, k, k), skin)                                         # bare knee
	var shin_rings := [Vector4(0.0, 0.095, 0.1, 0.0), Vector4(-0.1, 0.1, 0.11, -0.01), Vector4(-0.3, 0.075, 0.08, 0.0)]
	var shin: MeshInstance3D
	match bottom:
		"jeans":
			shin = _loft(kn, _bulked([Vector4(0.04, 0.105, 0.11, 0.008), Vector4(-0.12, 0.1, 0.108, 0.0),
				Vector4(-0.32, 0.105, 0.113, 0.006)], k, k, 0.018), shin_tex, true, false)     # straight jeans leg
		"sweatpants":
			shin = _loft(kn, _bulked([Vector4(0.04, 0.105, 0.11, 0.008), Vector4(-0.12, 0.1, 0.108, 0.0),
				Vector4(-0.26, 0.08, 0.085, 0.0), Vector4(-0.32, 0.075, 0.08, 0.0)], k, k, 0.016), shin_tex, true, false)
		_:
			shin = _loft(kn, _bulked(shin_rings, k, k), skin)                              # bare shin
			_loft(kn, _bulked([Vector4(-0.15, 0.1, 0.11, -0.01), Vector4(-0.34, 0.078, 0.084, 0.0)], k, k, 0.008),
				sock, false, false)                                                         # tube sock
	shin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_build_shoe(kn, m, shoes)
	return hp


func _build_shoe(kn: Node3D, m: Dictionary, shoes: String) -> void:
	# Chunky sneaker; the sole's bottom sits at knee-local -0.46 (= the floor).
	var upper: Material = m["shoe"]
	var plain: Material = m["shoe_plain"]
	var accent: Material = m["shoe_accent"]
	var white: Material = m["white"]
	if shoes == "skate":
		_loft(kn, [Vector4(-0.31, 0.098, 0.108, 0.0), Vector4(-0.4, 0.112, 0.125, 0.012)], upper, false, false)
		_ball(kn, 0.06, Vector3(0, -0.31, -0.01), plain, Vector3(1.6, 0.5, 1.7))           # padded collar
		_box(kn, Vector3(0.185, 0.095, 0.29), Vector3(0, -0.39, 0.06), plain)              # puffy upper
		_box(kn, Vector3(0.195, 0.05, 0.31), Vector3(0, -0.435, 0.06), white)              # thick cupsole
		_box(kn, Vector3(0.198, 0.008, 0.314), Vector3(0, -0.425, 0.06), _mat(Color(0.25, 0.25, 0.27)))
		for sx in [-1.0, 1.0]:
			var s: float = sx
			var st := _box(kn, Vector3(0.006, 0.026, 0.15), Vector3(0.0935 * s, -0.385, 0.05), accent)  # side stripe
			st.rotation.x = 0.25
		var lc := _box(kn, Vector3(0.08, 0.012, 0.12), Vector3(0, -0.343, 0.11), white)    # laces
		lc.rotation.x = 0.18
	else:
		_loft(kn, [Vector4(-0.2, 0.108, 0.115, 0.0), Vector4(-0.3, 0.1, 0.11, 0.0),
			Vector4(-0.4, 0.105, 0.12, 0.01)], upper, true, false)                         # high-top shaft
		_box(kn, Vector3(0.165, 0.085, 0.27), Vector3(0, -0.395, 0.06), plain)             # foot
		_box(kn, Vector3(0.16, 0.055, 0.075), Vector3(0, -0.41, 0.17), white)              # toe cap
		_box(kn, Vector3(0.178, 0.04, 0.295), Vector3(0, -0.44, 0.06), white)              # sole
		for sx in [-1.0, 1.0]:
			var s: float = sx
			var st := _box(kn, Vector3(0.006, 0.028, 0.15), Vector3(0.0835 * s, -0.39, 0.045), accent)  # side stripe
			st.rotation.x = 0.3
		var lc := _box(kn, Vector3(0.07, 0.012, 0.1), Vector3(0, -0.348, 0.115), white)    # laces
		lc.rotation.x = 0.2


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
	_weapons_on_state(s)  # weapons hook: drops the held item when hit / grappled


func is_standing() -> bool:
	return state in [S.IDLE, S.WALK, S.RUN, S.PUNCH, S.RUN_ATTACK, S.STUNNED, S.TAUNT,
		S.WHIFF, S.GRAB_WINDUP, S.WHIPPING, S.STOMP,
		S.PICKUP_ITEM, S.SWING, S.THROW_ITEM, S.SET_TABLE]  # weapons states


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
	if d > 0.0:
		trick.emit("", 0, "break")  # getting hurt breaks our style combo


func _down_time() -> float:
	return 1.3 + (1.0 - health / 100.0) * 2.4


func _clamp_ring() -> void:
	if _hf_clamp():  # high flying hook: corners / height allowed while climbing, perched, diving
		return
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
	_weapons_tick(delta)  # weapons hook: thrown-item hits, broken items
	# Punch windows are CPU-only and too short to read, so they get no tell.
	rev_tell.visible = reversal_window > 0.0 and reversal_kind != "punch"

	match state:
		S.IDLE, S.WALK:
			_free_move(delta)
		S.RUN:
			_run(delta)
		S.PUNCH:
			_punch(delta)
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
			_throwing()  # grapple chains: may chain into the next move
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
		S.PICKUP_ITEM, S.SWING, S.THROW_ITEM, S.ON_TABLE, S.SET_TABLE:
			_weapons_state(delta)  # weapons hook
		S.CLIMB, S.PERCHED, S.DIVING, S.PERCH_FALL, S.CORNER_STUN:
			_hf_tick(delta)  # high flying hook
		S.JUGGLED:
			_juggled(delta)  # strike strings: popped up by a launcher

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
		"ender", "chain":
			chance = 0.85
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
		"ender":
			# Read the big finishing blow of a strike string: duck it and drag them over.
			if os == S.PUNCH and dist < 2.4:
				_snap_face_opponent()
				_do_move("armdrag")
		"chain":
			if state == S.THROWN and os == S.THROWING:
				_chain_break()


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

	if _weapons_free_input():
		return  # weapons hook: swing / drop / throw / pick up / tables
	if _hf_free_move_hook(dir):  # high flying hook: corner climb, corner-stun follow-ups
		return
	if _combo_free_hook():  # strike strings hook: juggle follow-ups on a launched opponent
		return
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
	if whipped and _hf_check_corner_crash():  # high flying hook: whipped into a corner
		return

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
		_hf_on_rope_bounce()  # high flying hook: opens the springboard window
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

	if held_item != null and in_strike:
		_start_swing(true)  # weapons hook: running swing
		return
	if in_strike and _hf_run_strike():  # high flying hook: springboard / corner splash
		return
	var opp_down := _opp_state() == S.DOWN or _opp_state() == S.ON_TABLE  # weapons: table counts
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


## First strike of a string (a jab). See "# ---- strike strings & grapple chains".
func _start_punch() -> void:
	string_step = 0
	_start_strike("jab")


## Lock-up knee / whip clothesline: PUNCH states with fixed timing (strings use STRIKES).
func _punch(delta: float) -> void:
	if STRIKES.has(current_move_key):
		_strike(delta)
		return
	# Knee lift out of a lock-up: STRIKE again while they are doubled over = grapple-to-strike
	# transition straight into the string (hook, uppercut, ender).
	if _strip_super(current_move_key) == "knee" and in_strike and state_time >= 0.16 \
			and _opp_state() == S.STUNNED and _in_front(1.6):
		string_step = 1
		_start_strike(_string_pick(1, _stick_rel()))
		return
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
			var juggled := _opp_state() == S.JUGGLED
			if opponent.receive_strike(self, 11.0, true):
				if juggled:
					announce.emit("EXPRESS LARIAT!!")
					trick.emit("Express Lariat", 600, "super" if brawl_mode else "strike")
				else:
					announce.emit("Running Clothesline!")
					trick.emit("Running Clothesline", 200, "strike")
			else:
				trick.emit("", 0, "break")
	if state_time >= 0.55:
		set_state(S.IDLE)


## Called on the defender. Returns true if the strike connected.
func receive_strike(attacker: Node3D, dmg: float, knockdown: bool) -> bool:
	if state == S.JUGGLED:
		return _juggle_struck(attacker, dmg, knockdown)  # strike strings: hit in mid-air
	var hf := _hf_receive_strike(attacker, dmg, knockdown)  # high flying hook: perched/airborne/cornered
	if hf >= 0:
		return hf == 1
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
			var m: Dictionary = MOVES.get(current_move_key, MOVES["stomp"])  # "chain_stomp" too
			var dmg: float = m["dmg"]
			if opponent.receive_ground_hit(self, dmg, "stomp") and current_move_key == "stomp":
				trick.emit("Stomp", 40, "strike")
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
	var landed := (_opp_state() == S.DOWN or _opp_state() == S.ON_TABLE) and _flat_to_opponent().length() < 1.3  # weapons: table
	if landed:
		opponent.receive_ground_hit(self, dmg, key)
		announce.emit(m["name"])
		if not key.begins_with("chain_"):  # chain links are scored when they start
			trick.emit(m["name"], int(m.get("pts", 250)), "strike")
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
	if state == S.ON_TABLE:
		return _weapons_ground_hit_on_table(attacker, dmg, key)  # weapons hook
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
		trick.emit("", 0, "break")


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


func _do_move(base_key: String, chained := false) -> void:
	var key := base_key
	if brawl_mode and MOVES.has("super_" + key):
		key = "super_" + key  # BRAWL MODE: the flashy super version
	var m: Dictionary = MOVES[key]
	var tier: String = m.get("tier", "weak")
	var kind: String = m["kind"]
	var dmg: float = m["dmg"]
	announce.emit(m["name"])
	throw_chained = chained
	ai_string_plan = ""
	if not chained:
		chain_link = 0
		chain_buf = ""
		trick.emit(_trick_name(m), _move_points(key), "super" if key.begins_with("super_") else "grapple")
	if key.begins_with("super_"):
		sfx.emit("finisher", 0.8, _chest())
	if key == "finisher" or key == "super_finisher":
		sfx.emit("finisher", 1.0, _chest())
	elif tier == "reversal":
		sfx.emit("reversal", 0.6, _chest())
	elif kind == "throw":
		sfx.emit("whoosh", 0.5, _chest())
	if key == "finisher" or key == "super_finisher":
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
	throw_time = float(m["time"]) + (CHAIN_YANK if chained else 0.0)
	opponent.start_thrown(position + facing * float(m["land"]), m, key, chained)


## chained: hauled straight back up off the mat into this move (grapple chains).
func start_thrown(land_pos: Vector3, m: Dictionary, key := "", chained := false) -> void:
	# Caught out of a launcher juggle: the throw starts from where we hang in the air.
	throw_start_y = STAND_Y + (juggle_h if state == S.JUGGLED else 0.0)
	throw_start_pitch = pose_root.rotation.x if state == S.JUGGLED else 0.0
	set_state(S.THROWN)
	throw_chained = chained
	current_move_key = key
	last_hit_tier = m.get("tier", "weak")
	throw_from = position
	throw_to = Vector3(clamp(land_pos.x, -RING_HALF, RING_HALF), 0, clamp(land_pos.z, -RING_HALF, RING_HALF))
	throw_time = float(m["time"]) + (CHAIN_YANK if chained else 0.0)
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
		_weapons_check_table_landing()  # weapons hook: thrown through a table?


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
	run_dir = _hf_corner_whip_dir(run_dir)  # high flying hook: whips aimed at a corner
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
			trick.emit("", 0, "break")
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
		trick.emit("Clothesline", 250, "strike")


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


# ---- strike strings & grapple chains
# STRIKE STRINGS: STRIKE again while a strike plays (from STRING_BUFFER on) chains into the next
# one the moment the hit lands: Jab -> Hook -> Uppercut -> ender. The stick, relative to the
# opponent, picks the ender: neutral = Haymaker (4th hit), toward = Spin Kick (3rd hit) or
# Superkick (4th hit), away = Launcher (2nd hit on), which pops the opponent up (JUGGLED):
# then STRIKE = Air Mail Knee juggle (re-pops, JUGGLE_MAX per launch), GRAB = Catch & Slam,
# RUN = Express Lariat dash. GRAB mid-string locks up the staggered opponent. Enders are slower
# and open a timed reversal ("ender") on the defender, so the big blow can be read and countered.
# A late press lets the victim's stagger run out first: the timing window is real.
# GRAPPLE CHAINS: while a chainable throw plays (from CHAIN_OPEN of it on), GRAB or STRIKE
# queues the next move of CHAINS, which starts the moment the victim lands without letting go
# (they are hauled straight back up, CHAIN_YANK). Up to CHAIN_MAX links, each scoring more; the
# victim gets a short "chain" reversal window to break free. Reversals chain too (counter-to-combo).
# BRAWL MODE (brawl_mode, set by the style system): any move with a "super_" twin in MOVES /
# STRIKES uses it: higher lifts, extra spins, more damage. current_move_key carries the prefix.
# Nothing here depends on the ring: positions are relative to the two wrestlers only.

const STRING_BUFFER := 0.06   # presses earlier than this into a strike are ignored (no mashing through)
const ENDER_REVERSAL_WINDOW := 0.22
const CHAIN_OPEN := 0.45      # fraction of a throw after which GRAB / STRIKE queues a chain link
const CHAIN_GRACE := 0.2      # the thrower's recovery after the landing (the queue is honoured in it)
const CHAIN_MAX := 2          # chain links after the opening move (three moves in all)
const CHAIN_YANK := 0.28      # seconds to haul the victim back up off the ground into a chain link
const CHAIN_BREAK_WINDOW := 0.25
const JUGGLE_G := 12.0
const JUGGLE_VY := 3.8        # juggle hit re-pop (~0.6 m)
const JUGGLE_MAX := 2         # juggle hits per launch

## "hit" = contact time, "end" = recovery end (a whiff adds 0.16), "pts" = style points.
const STRIKES := {
	"jab": {"name": "Jab", "dmg": 3.0, "hit": 0.11, "end": 0.27, "reach": 1.35, "pts": 50},
	"hook": {"name": "Hook", "dmg": 4.0, "hit": 0.12, "end": 0.29, "reach": 1.35, "pts": 75},
	"uppercut": {"name": "Uppercut", "dmg": 5.0, "hit": 0.13, "end": 0.31, "reach": 1.3, "pts": 100},
	"haymaker": {"name": "Porch Light Haymaker!", "dmg": 9.0, "hit": 0.22, "end": 0.48, "reach": 1.45, "pts": 300, "ender": true, "knock": true},
	"spin_kick": {"name": "Lawn Dart Spin Kick!", "dmg": 8.0, "hit": 0.24, "end": 0.5, "reach": 1.6, "pts": 250, "ender": true, "knock": true},
	"superkick": {"name": "Screen Door Superkick!", "dmg": 11.0, "hit": 0.22, "end": 0.5, "reach": 1.7, "pts": 400, "ender": true, "knock": true},
	"launcher": {"name": "Bottle Rocket Launcher!", "dmg": 7.0, "hit": 0.2, "end": 0.42, "reach": 1.4, "pts": 300, "ender": true, "launch": true, "vy": 6.0},
	"juggle_knee": {"name": "Air Mail Knee!", "dmg": 5.0, "hit": 0.15, "end": 0.38, "reach": 1.9, "pts": 250, "juggle": true},
	# BRAWL MODE supers
	"super_haymaker": {"name": "SUPERNOVA HAYMAKER!!", "anim": "haymaker", "dmg": 15.0, "hit": 0.24, "end": 0.55, "reach": 1.5, "pts": 900, "ender": true, "knock": true},
	"super_spin_kick": {"name": "TORNADO ALLEY KICK!!", "anim": "spin_kick", "dmg": 13.0, "hit": 0.3, "end": 0.6, "reach": 1.7, "pts": 800, "ender": true, "knock": true},
	"super_superkick": {"name": "SONIC BOOM SUPERKICK!!", "anim": "superkick", "dmg": 17.0, "hit": 0.24, "end": 0.56, "reach": 1.8, "pts": 1100, "ender": true, "knock": true},
	"super_launcher": {"name": "ORBITAL LAUNCHER!!", "anim": "launcher", "dmg": 11.0, "hit": 0.22, "end": 0.5, "reach": 1.5, "pts": 900, "ender": true, "launch": true, "vy": 7.5},
	"super_juggle_knee": {"name": "AIRSTRIKE KNEE!!", "anim": "juggle_knee", "dmg": 8.0, "hit": 0.16, "end": 0.42, "reach": 2.0, "pts": 600, "juggle": true},
}
const STRING_KEYS := ["jab", "hook", "uppercut", "haymaker"]

## Grapple chains: move just landed -> {"grab": next move, "strike": next move}.
const CHAINS := {
	"slam": {"grab": "slam_2", "strike": "chain_elbow"},
	"slam_2": {"grab": "slam_bomb", "strike": "chain_elbow"},
	"suplex": {"grab": "suplex_2", "strike": "chain_stomp"},
	"suplex_2": {"grab": "triple_suplex", "strike": "chain_elbow"},
	"ddt": {"grab": "ddt_2", "strike": "chain_stomp"},
	"ddt_2": {"grab": "chain_neckbreaker", "strike": "chain_elbow"},
	"spinebuster": {"grab": "slam_bomb", "strike": "chain_elbow"},
	"neckbreaker": {"grab": "ddt_2", "strike": "chain_stomp"},
	"powerbomb": {"grab": "slam_bomb", "strike": "chain_elbow"},
	"piledriver": {"strike": "chain_stomp"},
	"backdrop": {"grab": "suplex_2", "strike": "chain_elbow"},
	"powerslam": {"grab": "slam_2", "strike": "chain_elbow"},
	"catch_slam": {"grab": "slam_bomb", "strike": "chain_elbow"},
	# counter-to-combo: a reversal flows straight into offence
	"armdrag": {"grab": "ddt_2", "strike": "chain_stomp"},
	"hiptoss": {"grab": "slam_2", "strike": "chain_elbow"},
	"rev_backdrop": {"strike": "chain_elbow"},
}

var brawl_mode := false        # BRAWL MODE (style system): moves become their super versions
var string_step := 0           # hits so far in the current strike string (0 = opening jab)
var strike_buf := ""           # "strike" / "grab" / "run" queued during the current strike
var strike_buf_dir := 0        # stick at that press: 1 toward, -1 away, 0 neutral / sideways
var strike_hit := false        # the current strike connected
var chain_link := 0            # chain links done in the current grapple chain
var chain_buf := ""            # "grab" / "strike" queued during the current throw
var throw_chained := false     # this throw is a chain link (victim hauled up off the ground first)
var throw_start_y := STAND_Y   # victim: pelvis height the throw starts from (caught mid-air)
var throw_start_pitch := 0.0
var juggle_h := 0.0            # JUGGLED: pelvis height above standing
var juggle_vy := 0.0
var juggle_vel := Vector3.ZERO
var juggle_hits := 0
var ai_string_plan := ""       # CPU: decided what to do in the current strike / throw


func _strip_super(k: String) -> String:
	return k.substr(6) if k.begins_with("super_") else k


## The animation a move / strike key reuses ("anim"), e.g. "super_suplex" -> "suplex".
func _anim_key(k: String) -> String:
	if MOVES.has(k):
		var m: Dictionary = MOVES[k]
		var a: String = m.get("anim", k)
		return a
	if STRIKES.has(k):
		var st: Dictionary = STRIKES[k]
		var a2: String = st.get("anim", k)
		return a2
	return k


func _trick_name(m: Dictionary) -> String:
	var n: String = m["name"]
	return n.replace("REVERSAL! ", "Reversal ").rstrip("!")


func _move_points(key: String) -> int:
	var m: Dictionary = MOVES[key]
	if m.has("pts"):
		return int(m["pts"])
	var dmg: float = m["dmg"]
	var mult := 25.0
	match str(m.get("tier", "weak")):
		"strong":
			mult = 30.0
		"finisher":
			mult = 75.0
		"reversal":
			mult = 40.0
	return int(dmg * mult)


## Stick relative to the opponent: 1 = toward, -1 = away, 0 = neutral / sideways.
func _stick_rel() -> int:
	if in_move.length() < 0.5:
		return 0
	var d := _flat_to_opponent()
	if d.length() < 0.01:
		return 0
	var dt := Vector2(d.x, d.z).normalized().dot(in_move.normalized())
	if dt > 0.5:
		return 1
	if dt < -0.5:
		return -1
	return 0


## The strike for hit number step + 1 of a string (step 0 = the opening jab).
func _string_pick(step: int, dir: int) -> String:
	if dir < 0 and step >= 1:
		return "launcher"
	if dir > 0 and step >= 2:
		return "superkick" if step >= 3 else "spin_kick"
	var k: String = STRING_KEYS[mini(step, STRING_KEYS.size() - 1)]
	return k


func _strike_times() -> Vector2:
	if STRIKES.has(current_move_key):
		var st: Dictionary = STRIKES[current_move_key]
		return Vector2(float(st["hit"]), float(st["end"]))
	return Vector2(PUNCH_HIT, PUNCH_END)


func _start_strike(key: String) -> void:
	var sk := key
	if brawl_mode and STRIKES.has("super_" + key):
		sk = "super_" + key
	set_state(S.PUNCH)
	current_move_key = sk
	strike_buf = ""
	strike_buf_dir = 0
	strike_hit = false
	ai_string_plan = ""
	var st: Dictionary = STRIKES[sk]
	if string_step > 0:
		_snap_face_opponent()
	if st.get("ender", false):
		sfx.emit("whoosh", 0.45, _chest())
		if _in_front(2.2) and opponent.is_standing():
			opponent.open_reversal_window(ENDER_REVERSAL_WINDOW, "ender")
	elif string_step == 0 and opponent.is_cpu and _opp_can_counter() and _in_front(1.6):
		# Only a CPU defender gets a jab-reversal window: for a human it is below reaction
		# time and would just flicker "REVERSE!" on every jab.
		opponent.open_reversal_window(float(st["hit"]), "punch")


## PUNCH state for a STRIKES key: step in, hit, then chain on a queued press.
func _strike(delta: float) -> void:
	var st: Dictionary = STRIKES[current_move_key]
	var hit_t: float = st["hit"]
	var end_t: float = st["end"]
	var juggle: bool = st.get("juggle", false)
	if state_time < hit_t:
		# Step in so the string keeps reaching a victim the last hit knocked back.
		var d := _flat_to_opponent()
		var dist := d.length()
		var want := 0.85 if juggle else 0.95
		if (string_step > 0 or juggle) and dist > want and dist < 2.8:
			position += d / dist * minf((6.0 if juggle else 3.0) * delta, dist - want)
		_face_opponent(delta)
	if (in_strike or in_grapple or in_run) and state_time >= STRING_BUFFER:
		strike_buf = "strike" if in_strike else ("grab" if in_grapple else "run")
		strike_buf_dir = _stick_rel()
	if state_time >= hit_t and not hit_landed:
		hit_landed = true
		strike_hit = _strike_connect(st)
	if strike_hit and strike_buf != "" and state_time >= hit_t + 0.03:
		if _string_continue():
			return
	if state_time >= end_t + (0.0 if strike_hit else 0.16):
		string_step = 0
		set_state(S.IDLE)


func _strike_connect(st: Dictionary) -> bool:
	var k := current_move_key
	var dmg: float = st["dmg"]
	var reach: float = st.get("reach", 1.35)
	var ok := false
	if st.get("juggle", false):
		if _opp_state() == S.JUGGLED and _flat_to_opponent().length() < reach:
			ok = opponent.receive_juggle_hit(self, dmg)
	elif _in_front(reach):
		if st.get("launch", false):
			ok = opponent.receive_launch(self, dmg, float(st.get("vy", 6.0)))
		else:
			ok = opponent.receive_strike(self, dmg, bool(st.get("knock", false)))
	if not ok:
		trick.emit("", 0, "break")  # whiffed
		sfx.emit("whoosh", 0.3, _chest())
		return false
	var nm: String = st["name"]
	var pts := int(st["pts"])
	var big: bool = st.get("ender", false) or st.get("juggle", false)
	if big:
		announce.emit(nm)
		impact.emit(0.6 if st.get("knock", false) else 0.35)
		pts = int(pts * (1.0 + 0.25 * string_step))  # longer strings pay more
		if string_step >= 3:
			nm = "%d-Hit %s" % [string_step + 1, nm]
	trick.emit(nm.rstrip("!"), pts, "super" if k.begins_with("super_") else "strike")
	return true


## A press queued during a strike that connected: the next hit, a lock-up or a juggle follow-up.
func _string_continue() -> bool:
	var buf := strike_buf
	var dir := strike_buf_dir
	strike_buf = ""
	if _opp_state() == S.JUGGLED:
		return _juggle_follow(buf)
	var st: Dictionary = STRIKES[current_move_key]
	if buf == "grab" and not st.get("ender", false):
		# strike-to-grapple: lock up the staggered opponent mid-string
		string_step = 0
		set_state(S.GRAB_WINDUP)
		return true
	if buf != "strike" or st.get("ender", false) or st.get("juggle", false):
		return false
	string_step += 1
	_start_strike(_string_pick(string_step, dir))
	return true


## Opponent popped up by a launcher: STRIKE = juggle knee, GRAB = catch slam, RUN = dash lariat.
func _juggle_follow(buf: String) -> bool:
	var dist := _flat_to_opponent().length()
	var jh: int = opponent.juggle_hits
	match buf:
		"strike":
			if jh < JUGGLE_MAX and dist < 3.0:
				string_step += 1
				_start_strike("juggle_knee")
				return true
		"grab":
			if dist < 2.0:
				_snap_face_opponent()
				_do_move("catch_slam")
				return true
		"run":
			if dist < 3.2:
				_snap_face_opponent()
				run_dir = facing
				_start_run_attack()
				return true
	return false


## _free_move hook: follow-ups on a juggled opponent from a standing start.
func _combo_free_hook() -> bool:
	if _opp_state() != S.JUGGLED:
		return false
	var buf := "strike" if in_strike else ("grab" if in_grapple else ("run" if in_run else ""))
	if buf == "":
		return false
	return _juggle_follow(buf)


# --- being launched ---------------------------------------------------------------------

## Called on the defender by a launcher. Returns true if it connected.
func receive_launch(attacker: Node3D, dmg: float, vy: float) -> bool:
	if state != S.JUGGLED and not is_standing():
		return false
	take_damage(dmg)
	attacker.gain_spirit(dmg * 1.5)
	if state != S.JUGGLED:
		juggle_h = 0.0
		juggle_hits = 0
		set_state(S.JUGGLED)
	juggle_vy = vy
	var away := position - attacker.position
	away.y = 0.0
	juggle_vel = away.normalized() * 1.3 if away.length() > 0.01 else -facing * 1.3
	last_hit_tier = "strike"
	impact.emit(0.5)
	sfx.emit("kick", 0.85, global_position + Vector3(0, 1.4, 0))
	return true


## A juggle hit while JUGGLED: hurts and pops us up again.
func receive_juggle_hit(attacker: Node3D, dmg: float) -> bool:
	if state != S.JUGGLED:
		return false
	take_damage(dmg)
	attacker.gain_spirit(dmg * 1.5)
	juggle_hits += 1
	juggle_vy = maxf(juggle_vy, JUGGLE_VY)
	var away := position - attacker.position
	away.y = 0.0
	if away.length() > 0.01:
		juggle_vel = away.normalized() * 1.0
	impact.emit(0.3)
	sfx.emit("punch", 0.7, global_position + Vector3(0, 1.4 + juggle_h, 0))
	return true


## receive_strike while JUGGLED: a knockdown blow spikes us out of the air.
func _juggle_struck(attacker: Node3D, dmg: float, knockdown: bool) -> bool:
	if not knockdown:
		return receive_juggle_hit(attacker, dmg)
	take_damage(dmg)
	attacker.gain_spirit(dmg * 1.5)
	var away := position - attacker.position
	away.y = 0.0
	if away.length() > 0.01:
		position += away.normalized() * 0.5
	_juggle_land(1.0)
	return true


func _juggled(delta: float) -> void:
	juggle_vy -= JUGGLE_G * delta
	juggle_h += juggle_vy * delta
	position += juggle_vel * delta
	juggle_vel = juggle_vel.lerp(Vector3.ZERO, clampf(delta * 1.5, 0.0, 1.0))
	if (juggle_h <= 0.0 and juggle_vy < 0.0) or state_time > 3.0:
		_juggle_land(0.55)


func _juggle_land(strength: float) -> void:
	juggle_h = 0.0
	juggle_vy = 0.0
	set_state(S.DOWN)
	down_duration = _down_time()
	last_hit_tier = "strike"
	impact.emit(strength)
	sfx.emit("big_thud" if strength >= 1.0 else "thud", strength, global_position + Vector3(0, 0.3, 0))


# --- grapple chains ----------------------------------------------------------------------

## THROWING: GRAB / STRIKE late in a chainable move queues the next link; it fires on landing.
func _throwing() -> void:
	var nexts: Dictionary = CHAINS.get(_strip_super(current_move_key), {})
	if not nexts.is_empty() and chain_link < CHAIN_MAX and state_time >= throw_time * CHAIN_OPEN:
		if in_grapple and nexts.has("grab"):
			chain_buf = "grab"
		elif in_strike and nexts.has("strike"):
			chain_buf = "strike"
	if chain_buf != "" and state_time >= throw_time and _opp_state() == S.DOWN:
		var nk: String = nexts.get(chain_buf, "")
		chain_buf = ""
		if nk != "" and _flat_to_opponent().length() < 3.0:
			_do_chain(nk)
			return
	if state_time >= throw_time + CHAIN_GRACE:
		chain_buf = ""
		set_state(S.IDLE)


func _do_chain(nk: String) -> void:
	var m: Dictionary = MOVES[nk]
	chain_link += 1
	var pts := int(m.get("pts", 300)) + 150 * chain_link
	var kind := "super" if brawl_mode else "grapple"
	trick.emit(_trick_name(m), pts, kind)
	if str(m["kind"]) == "ground":
		if nk == "chain_stomp":
			_start_stomp()
			current_move_key = nk
			announce.emit(m["name"])
		else:
			_start_ground_drop(nk)
		return
	_snap_face_opponent()
	_do_move(nk, true)
	if chain_link >= CHAIN_MAX:
		announce.emit("%s  -  %d-MOVE CHAIN!" % [m["name"], chain_link + 1])
	opponent.open_reversal_window(CHAIN_BREAK_WINDOW, "chain")


## Victim's timed reversal of a chain link: slip out while being hauled back up.
func _chain_break() -> void:
	_set_facing_angle(throw_yaw0 + throw_yaw_start)  # keep lying the way we landed
	set_state(S.DOWN)
	down_duration = 0.35
	opponent.set_state(S.STUNNED)
	opponent.stun_time = 0.6
	opponent.emit_signal("trick", "", 0, "break")
	announce.emit("CHAIN BROKEN!")
	sfx.emit("reversal", 0.6, _chest())
	trick.emit("Chain Breaker", 250, "grapple")


## Victim path of a chain link: from lying on the ground, hauled up face to face (LOCKUP_DIST in
## front of the thrower), then the move's own keys squeezed into the rest of the throw.
func _chain_keys(k: Array, f0: float, s0: float) -> Array:
	var cy := clampf(CHAIN_YANK / maxf(throw_time, 0.01), 0.05, 0.5)
	var out: Array = [_key(0.0, f0, s0, LIE_Y, _qe(throw_yaw_start, -PI / 2)),
		_key(cy, LOCKUP_DIST, 0.0, STAND_Y, _qe(PI, 0.0))]
	for i in range(1, k.size()):
		var e: Array = k[i]
		var np: float = e[0]
		out.append([cy + np * (1.0 - cy), e[1], e[2], e[3]])
	return out


## Super path: the base path resampled, lifted higher through the air and spun around the
## vertical `spin` extra times (dense keys so every slerp step stays under half a turn).
func _super_keys(k: Array, lift: float, spin: float) -> Array:
	var n := 24
	var out: Array = []
	for i in range(n):
		var p := float(i) / float(n)
		var sm := _keys_at(k, p)
		var v: Vector3 = sm[0]
		var q: Quaternion = sm[1]
		if i > 0:
			v.z += lift * sin(PI * _seg(p, 0.05, 0.85))
			var a := spin * TAU * _smooth(_seg(p, 0.12, 0.8))
			q = (Quaternion(Vector3.UP, a) * q).normalized()
		out.append([p, v, q, 3])
	out.append(k[k.size() - 1])
	return out


## Interpolated [Vector3(forward, side, pelvis y), orientation] of a key list at p.
func _keys_at(k: Array, p: float) -> Array:
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
	return [va.lerp(vb, u), qa.slerp(qb, u).normalized()]


# --- CPU ---------------------------------------------------------------------------------

## PUNCH: once a strike connects, maybe keep the string going (and pick the ender).
func _ai_string(toward: Vector2) -> void:
	if not STRIKES.has(current_move_key) or not strike_hit or ai_string_plan != "":
		return
	ai_string_plan = "decided"
	if _opp_state() == S.JUGGLED:
		var r := randf()
		if r < 0.45:
			in_strike = true
		elif r < 0.75:
			in_grapple = true
		elif r < 0.9:
			in_run = true
		return
	var st: Dictionary = STRIKES[current_move_key]
	if st.get("ender", false) or st.get("juggle", false):
		return
	if randf() > 0.4 + 0.45 * ai_skill:
		return  # stop the string here
	if randf() < 0.12:
		in_grapple = true  # strike-to-grapple
		return
	in_strike = true
	var r2 := randf()
	if string_step >= 1 and r2 < 0.22:
		in_move = -toward  # launcher
	elif string_step >= 2 and r2 < 0.55:
		in_move = toward   # spin kick / superkick


## THROWING: maybe chain the next move.
func _ai_chain() -> void:
	if ai_string_plan != "" or chain_link >= CHAIN_MAX or state_time < throw_time * CHAIN_OPEN:
		return
	var nexts: Dictionary = CHAINS.get(_strip_super(current_move_key), {})
	if nexts.is_empty():
		return
	ai_string_plan = "decided"
	if randf() < 0.25 + 0.35 * ai_skill - 0.1 * chain_link:
		if nexts.has("grab") and (randf() < 0.65 or not nexts.has("strike")):
			in_grapple = true
		else:
			in_strike = true


## IDLE / WALK with the opponent juggled: go get them.
func _ai_juggle(dist: float, toward: Vector2, can_act: bool) -> void:
	if dist > 1.6:
		in_move = toward
	if not can_act:
		return
	ai_timer = 0.3
	var r := randf()
	if dist < 1.9 and r < 0.5:
		in_strike = true
	elif dist < 1.9 and r < 0.8:
		in_grapple = true
	elif r < 0.95:
		in_run = true


# --- poses -------------------------------------------------------------------------------

## Left hook: elbow up at shoulder height, the whole torso whips it around.
func _pose_hook() -> void:
	var tm := _strike_times()
	var t := state_time
	var cock := _smooth(_seg(t, 0.0, tm.x * 0.5))
	var swing := _ease_in(_seg(t, tm.x * 0.5, tm.x))
	var back := _smooth(_seg(t, tm.x + 0.05, tm.y))
	var c := cock * (1.0 - swing)
	var s := swing * (1.0 - back)
	r_limb = 34.0
	r_body = 26.0
	_stance(0.6 + 0.1 * s)
	pt_ll.x -= 0.12 * s
	pt_tor = Vector3(0.22 + 0.08 * s, -0.35 * c + 0.6 * s, 0.08 * s)
	pt_hd = Vector3(-0.1, 0.2 * c - 0.3 * s, 0.0)
	var lean := pt_tor.x
	pt_al = Vector3(-0.75 - lean, 0.0, -0.3).lerp(Vector3(-0.5, 0.0, -0.95), c).lerp(Vector3(-1.1 - lean * 0.5, 0.0, -1.3), s)
	pt_el_l = Vector3(lerpf(-1.9, -1.5, s), 0.0, 0.0)
	pt_ar = Vector3(-0.8 - lean, 0.0, 0.3)
	pt_el_r = Vector3(-2.0, 0.0, 0.0)
	pt_root_pos.z = 0.08 * s


## Uppercut (and the launcher: deeper dip, full-extension rise, both feet leave the ground).
func _pose_uppercut() -> void:
	var tm := _strike_times()
	var t := state_time
	var launch := _anim_key(current_move_key) == "launcher"
	var big := 1.4 if launch else 1.0
	var dip := _smooth(_seg(t, 0.0, tm.x * 0.55))
	var rise := _ease_out(_seg(t, tm.x * 0.5, tm.x))
	var back := _smooth(_seg(t, tm.x + 0.06, tm.y))
	var d := dip * (1.0 - rise)
	var s := rise * (1.0 - back)
	r_limb = 32.0
	r_body = 24.0
	_stance(0.6 + 0.35 * big * d - 0.2 * s)
	pt_tor = Vector3(0.3 + 0.2 * big * d - 0.35 * s, 0.3 * d - 0.25 * s, 0.0)
	pt_hd = Vector3(0.1 * d - 0.25 * s, 0.0, 0.0)
	var lean := pt_tor.x
	var top := -2.9 if launch else -2.4
	pt_ar = Vector3(lerpf(-0.25, top, s) - lean * 0.5, 0.0, 0.22)
	pt_el_r = Vector3(lerpf(-1.7, -0.3 if launch else -1.1, s), 0.0, 0.0)
	pt_al = Vector3(-0.8 - lean, 0.0, -0.3)
	pt_el_l = Vector3(-2.0, 0.0, 0.0)
	if launch:
		pt_root_dy = 0.28 * _hump(t, tm.x * 0.7, tm.y) * (1.6 if current_move_key.begins_with("super_") else 1.0)
		pt_lr.x += 0.5 * s  # trailing leg kicks back off the ground


## Overhand haymaker: wound up behind, swung over the top with the whole body.
func _pose_haymaker() -> void:
	var tm := _strike_times()
	var t := state_time
	var sup := current_move_key.begins_with("super_")
	var wind := _smooth(_seg(t, 0.0, tm.x * 0.65))
	var swing := _ease_in(_seg(t, tm.x * 0.65, tm.x))
	var back := _smooth(_seg(t, tm.x + 0.08, tm.y))
	var c := wind * (1.0 - swing)
	var s := swing * (1.0 - back)
	r_limb = 30.0
	r_body = 22.0
	_stance(0.5 + 0.25 * s)
	pt_ll.x -= 0.3 * s
	pt_tor = Vector3(0.1 - 0.15 * c + 0.45 * s, 0.7 * c - 0.55 * s, 0.0)
	pt_hd = Vector3(-0.1 - 0.15 * c + 0.1 * s, -0.4 * c + 0.3 * s, 0.0)
	var lean := pt_tor.x
	pt_ar = Vector3(-0.6, 0.0, 0.3).lerp(Vector3(0.55, 0.0, 0.9), c).lerp(Vector3(-1.9 - lean * 0.5, 0.0, 0.25), s)
	pt_el_r = Vector3(lerpf(lerpf(-1.4, -1.0, c), -0.25, s), 0.0, 0.0)
	pt_al = Vector3(-1.0 - lean + 0.6 * c, 0.0, -0.45)
	pt_el_l = Vector3(-1.6, 0.0, 0.0)
	pt_root_pos.z = 0.15 * s
	if sup:
		pt_root_dy = 0.3 * _hump(t, tm.x * 0.3, tm.x + 0.1)  # leaping haymaker


## Superkick: chamber the right knee, snap the sole up to the chin, lean back for reach.
func _pose_superkick() -> void:
	var tm := _strike_times()
	var t := state_time
	var sup := current_move_key.begins_with("super_")
	var cham := _smooth(_seg(t, 0.0, tm.x * 0.6))
	var snap := _ease_out(_seg(t, tm.x * 0.6, tm.x))
	var back := _smooth(_seg(t, tm.x + 0.1, tm.y))
	var c := cham * (1.0 - snap)
	var s := snap * (1.0 - back)
	r_limb = 32.0
	r_body = 22.0
	_stance(0.4)
	pt_ll = Vector3(-0.1 + 0.15 * s, 0.0, -0.1)
	pt_kn_l = 0.35 + 0.15 * c
	pt_lr = Vector3(lerpf(lerpf(-0.05, -1.35, c), -1.75, s), 0.0, 0.06)
	pt_kn_r = lerpf(lerpf(0.3, 2.1, c), 0.1, s)
	pt_tor = Vector3(0.15 - 0.45 * s, 0.25 * c - 0.1 * s, 0.0)
	pt_hd = Vector3(0.1 + 0.25 * s, 0.0, 0.0)
	pt_al = Vector3(-0.4 + 0.5 * s, 0.0, -0.5 - 0.4 * s)
	pt_ar = Vector3(-0.4 + 0.6 * s, 0.0, 0.5 + 0.4 * s)
	pt_el_l = Vector3(-1.0, 0.0, 0.0)
	pt_el_r = Vector3(-1.0, 0.0, 0.0)
	pt_root_pos.z = -0.1 * s
	if sup:
		pt_root_dy = 0.35 * _hump(t, tm.x * 0.4, tm.x + 0.15)  # leaping superkick


## Spinning back kick: a full turn on the lead foot (two in BRAWL MODE), leg lashing out.
func _pose_spin_kick() -> void:
	var tm := _strike_times()
	var t := state_time
	var turns := 2.0 if current_move_key.begins_with("super_") else 1.0
	var spin := _smooth(_seg(t, 0.0, tm.x + 0.08))
	var ext := _hump(t, tm.x * 0.45, tm.x + 0.14)
	r_limb = 34.0
	r_body = 26.0
	pt_hip.y = TAU * turns * spin
	pt_hip_y_direct = true
	_stance(0.45)
	pt_ll = Vector3(-0.05, 0.0, -0.08)
	pt_kn_l = 0.35
	pt_lr = Vector3(-0.2 - 0.6 * ext, 0.0, 0.15 + 1.15 * ext)
	pt_kn_r = lerpf(0.9, 0.12, ext)
	pt_tor = Vector3(0.15 - 0.1 * ext, 0.0, -0.35 * ext)
	pt_hd = Vector3(-0.05, 0.0, 0.2 * ext)
	pt_al = Vector3(-0.5, 0.0, -0.9 * ext - 0.3)
	pt_ar = Vector3(-0.5, 0.0, 0.3 + 0.6 * ext)
	pt_el_l = Vector3(-1.2, 0.0, 0.0)
	pt_el_r = Vector3(-1.2, 0.0, 0.0)
	if turns > 1.0:
		pt_root_dy = 0.3 * _hump(t, 0.0, tm.x + 0.12)  # airborne tornado


## Jumping knee into the airborne opponent.
func _pose_juggle_knee() -> void:
	var tm := _strike_times()
	var t := state_time
	var air := _hump(t, 0.0, tm.y * 0.9)
	var k := _ease_out(_seg(t, 0.0, tm.x)) * (1.0 - _smooth(_seg(t, tm.x + 0.08, tm.y)))
	r_limb = 30.0
	r_body = 22.0
	pt_root_direct = true
	pt_root_pos = Vector3(0.0, STAND_Y - 0.05 + 0.55 * air, 0.1 * k)
	pt_ll = Vector3(0.3 * k, 0.0, -0.1)
	pt_kn_l = 0.6 + 0.6 * k
	pt_lr = Vector3(-0.3 - 1.4 * k, 0.0, 0.06)
	pt_kn_r = 0.4 + 1.8 * k
	pt_tor = Vector3(0.1 - 0.2 * k, 0.0, 0.0)
	pt_hd = Vector3(0.05, 0.0, 0.0)
	pt_al = Vector3(-0.4 - 1.6 * k, 0.0, -0.5)
	pt_ar = Vector3(-0.4 - 1.6 * k, 0.0, 0.5)
	pt_el_l = Vector3(-0.5, 0.0, 0.0)
	pt_el_r = Vector3(-0.5, 0.0, 0.0)


## Chain link, first beat: bend down, grab the downed opponent by the head, haul them up.
func _pose_chain_yank(u: float) -> void:
	var bend := 1.0 - _smooth(_seg(u, 0.35, 1.0))
	_stance(0.5 + 0.5 * bend)
	pt_tor = Vector3(0.25 + 0.9 * bend, 0.0, 0.0)
	pt_hd = Vector3(0.3 * bend - 0.1, 0.0, 0.0)
	var vhd := _opp_node("head")
	var hp := vhd.global_position + Vector3(0.0, 0.1, 0.0)
	var side := Vector3(facing.z, 0.0, -facing.x) * 0.13
	_reach_pair(hp - side, hp + side)
	r_limb = 24.0
	r_body = 20.0
	r_root = 20.0


## Popped up by a launcher: tipping over backwards in the air, arms and legs flung out.
func _pose_juggled() -> void:
	pt_root_direct = true
	var f := _smooth(clampf(state_time / 0.85, 0.0, 1.0))
	pt_root_rot = Vector3(-PI / 2 * f, 0.0, 0.0)
	pt_root_pos = Vector3(0.0, lerpf(STAND_Y, LIE_Y + 0.1, f) + juggle_h, 0.0)
	var fl := sin(anim_clock * 14.0)
	var fl2 := sin(anim_clock * 11.0 + 1.3)
	pt_al = Vector3(-2.2 + 0.3 * fl, 0.0, -0.7 - 0.2 * fl2)
	pt_ar = Vector3(-2.2 - 0.3 * fl2, 0.0, 0.7 + 0.2 * fl)
	pt_el_l = Vector3(-0.4, 0.0, 0.0)
	pt_el_r = Vector3(-0.4, 0.0, 0.0)
	pt_ll = Vector3(-0.6 + 0.25 * fl, 0.0, -0.15)
	pt_lr = Vector3(-0.3 - 0.25 * fl2, 0.0, 0.15)
	pt_kn_l = 0.7
	pt_kn_r = 0.4
	pt_tor = Vector3(-0.25, 0.0, 0.08 * fl)
	pt_hd = Vector3(-0.45, 0.0, 0.0)
	r_limb = 16.0
	r_body = 14.0


# ---- weapons
# Hardcore weapons. The props live in scripts/weapons.gd (`items` = the ItemManager, set by
# main.gd; may be null). Controls (documented for the help panel):
#   GRAB   near a free item (opponent not standing in grab range)  -> pick it up
#   GRAB   near the folded table                                   -> set it up in front of you
#   GRAB   next to a downed opponent near a standing table         -> drag them onto the table
#   GRAB   while holding                                           -> drop it
#   STRIKE while holding                                           -> swing (downed / on a table: ground shot)
#   RUN, then STRIKE while holding                                 -> running swing
#   PIN    while holding                                           -> throw it at the opponent (hits if they
#                                                                     stand in front within 6 m); if they are
#                                                                     down right next to you: drop it and cover
#   STRIKE next to an opponent lying on a table                    -> leap onto them: THROUGH THE TABLE!
# Any throw that lands within 0.8 m of a standing table also goes through it. Getting hit
# or grappled while holding something drops it.

const SWING_HIT := 0.3
const SWING_END := 0.68
const SWING_REACH := 1.6
const ITEM_PICK_DIST := 1.3
const TABLE_PLACE_DIST := 2.6   # a downed opponent this close to a standing table can be put on it
const TABLE_BREAK_DMG := 12.0
const TABLE_DOWN_TIME := 4.0
const TABLE_TOP_Y := 0.79       # weapons.gd TABLE_HEIGHT: lying ON_TABLE raises the body this much
const HOLD_OK_STATES := [S.IDLE, S.WALK, S.RUN, S.PICKUP_ITEM, S.SWING, S.THROW_ITEM, S.TAUNT, S.WIN]

var items = null                    # the ItemManager (weapons.gd), or null
var held_item: Node3D = null        # the item in our right hand
var on_table: Node3D = null         # the table we lie on (ON_TABLE)
var weapon_target: Node3D = null    # item / table the current PICKUP_ITEM / SET_TABLE is about
var swing_running := false
var item_flight := -1.0             # > 0: our thrown item is in the air; it arrives at 0
var item_flight_to := Vector3.ZERO
var item_flight_obj: Node3D = null
var ai_item_goal: Node3D = null     # CPU: the item / folded table it is walking to
var ai_item_goal_until := 0.0
var ai_down_roll := -1.0            # CPU: one roll per knockdown for table plans


func _item_ok(it) -> bool:
	return is_instance_valid(it)


func _item_kind(it) -> String:
	if not _item_ok(it):
		return ""
	var k: String = it.get("kind")
	return k


func _item_mode(it) -> String:
	if not _item_ok(it):
		return "broken"
	var m: String = it.get("mode")
	return m


func _item_sfx(kind: String) -> String:
	match kind:
		"chair":
			return "chair_hit"
		"trash_can":
			return "metal_hit"
	return "wood_hit"


func _item_call(kind: String, how: String) -> String:
	var n := "STEEL CHAIR"
	match kind:
		"trash_can":
			n = "TRASH CAN"
		"plank":
			n = "2x4"
	match how:
		"run":
			return "Running %s shot!" % n
		"ground":
			return "%s to the downed man!" % n
		"throw":
			return "%s thrown at the head!" % n
	return "%s SHOT!" % n


## set_state hook: anything but the free / weapon states drops what we hold.
func _weapons_on_state(s: int) -> void:
	if s != S.ON_TABLE:
		on_table = null
	if held_item != null and not (s in HOLD_OK_STATES):
		_drop_held()


func _drop_held() -> void:
	var it := held_item
	held_item = null
	if not _item_ok(it) or items == null:
		return
	items.drop(it, position + facing * 0.45)


## tick hook: forget broken items, resolve thrown items reaching their target.
func _weapons_tick(delta: float) -> void:
	# Items are queue_free()d when they break: forget any freed reference before use.
	if not is_instance_valid(held_item):
		held_item = null
	if not is_instance_valid(on_table):
		on_table = null
	if not is_instance_valid(weapon_target):
		weapon_target = null
	if not is_instance_valid(item_flight_obj):
		item_flight_obj = null
	if not is_instance_valid(ai_item_goal):
		ai_item_goal = null
	if item_flight > 0.0:
		item_flight -= delta
		if item_flight <= 0.0:
			_thrown_item_arrives()


## _free_move hook (IDLE / WALK). Returns true when a weapon action used the input.
func _weapons_free_input() -> bool:
	if not (in_strike or in_grapple or in_pin):
		return false
	var os := _opp_state()
	var dist := _flat_to_opponent().length()
	if held_item != null:
		if in_strike:
			_start_swing(false)
		elif in_grapple:
			_drop_held()
			sfx.emit("pickup_item", 0.3, global_position + Vector3(0, 0.5, 0))
		elif in_pin:
			if os == S.DOWN and dist < 2.0:
				_drop_held()
				return false  # the normal cover happens this same frame
			_start_throw_item()
		return true
	if items == null:
		return false
	if in_strike and os == S.ON_TABLE and dist < 2.2:
		_start_ground_drop("elbow_drop")  # leap onto the table (breaks it on landing)
		return true
	if not in_grapple:
		return false
	if os == S.DOWN and dist < 1.8:
		var t: Node3D = items.table_under(opponent.position, TABLE_PLACE_DIST)
		if t != null:
			_start_place_on_table(t)
			return true
	var opp_up: bool = opponent.is_standing()
	if opp_up and _in_front(1.5):
		return false  # opponent in grab range: normal lock-up
	var it: Node3D = items.nearest_item(position, ITEM_PICK_DIST)
	if it != null:
		var ip: Vector3 = it.position
		var idist := Vector2(ip.x - position.x, ip.z - position.z).length()
		if not (os == S.DOWN and dist < 1.6 and dist < idist):
			_start_pickup_item(it)
			return true
	var ft: Node3D = items.nearest_folded_table(position, 1.5)
	if ft != null:
		_start_set_table(ft)
		return true
	return false


## tick hook for the weapon states.
func _weapons_state(delta: float) -> void:
	match state:
		S.PICKUP_ITEM:
			if not hit_landed and state_time >= 0.2:
				hit_landed = true
				var it := weapon_target
				weapon_target = null
				var holder: Node = it.get("held_by") if _item_ok(it) else null
				if items != null and _item_mode(it) == "floor" and holder == null:
					held_item = it
					items.pick_up(it, self)
					sfx.emit("pickup_item", 0.6, _chest())
					var k := _item_kind(it)
					var label := "a steel chair" if k == "chair" else ("the trash can" if k == "trash_can" else "a 2x4")
					announce.emit("%s grabs %s!" % [display_name, label])
			if state_time >= 0.42:
				set_state(S.IDLE)
		S.SWING:
			_swing(delta)
		S.THROW_ITEM:
			_throw_item_state()
		S.ON_TABLE:
			_on_table_state()
		S.SET_TABLE:
			_set_table_state()


func _start_pickup_item(it: Node3D) -> void:
	set_state(S.PICKUP_ITEM)
	current_move_key = "pickup_item"
	weapon_target = it
	var ip: Vector3 = it.position
	var d := ip - position
	if Vector2(d.x, d.z).length() > 0.05:
		_set_facing_angle(atan2(d.x, d.z))


func _start_swing(running: bool) -> void:
	set_state(S.SWING)
	swing_running = running
	current_move_key = "swing_run" if running else "swing"
	if not running:
		var os := _opp_state()
		var dist := _flat_to_opponent().length()
		if (os == S.DOWN or os == S.ON_TABLE) and dist < 2.2:
			current_move_key = "swing_ground"
		if dist < 3.0:
			_snap_face_opponent()
	sfx.emit("whoosh", 0.55, _chest())


func _swing(delta: float) -> void:
	var hit_at := 0.18 if swing_running else SWING_HIT
	var end_at := 0.55 if swing_running else SWING_END
	if swing_running:
		var speed: float = lerpf(RUN_SPEED, 0.0, clampf(state_time / 0.45, 0.0, 1.0))
		position += run_dir * speed * delta
	if not hit_landed and state_time >= hit_at:
		hit_landed = true
		_swing_connect()
	if state_time >= end_at:
		set_state(S.IDLE)


func _swing_connect() -> void:
	var it := held_item
	if not _item_ok(it):
		return
	var kind := _item_kind(it)
	var dmg: float = it.get("damage")
	var os := _opp_state()
	var dist := _flat_to_opponent().length()
	var hit := false
	if (os == S.DOWN or os == S.ON_TABLE) and dist < 1.9:
		var on_tbl := os == S.ON_TABLE
		hit = opponent.receive_ground_hit(self, dmg * 0.8, "weapon")
		if hit and not on_tbl:
			announce.emit(_item_call(kind, "ground"))
	else:
		var opp_up: bool = opponent.is_standing()
		if opp_up and _in_front(1.9 if swing_running else SWING_REACH):
			hit = opponent.receive_strike(self, dmg, true)
			if hit:
				announce.emit(_item_call(kind, "run" if swing_running else "hit"))
	if not hit:
		return
	var op: Vector3 = opponent.global_position
	sfx.emit(_item_sfx(kind), 1.0, op + Vector3(0, 1.2, 0))
	if items != null:
		var gone: bool = items.damage_item(it, 1)
		if gone:
			held_item = null
			announce.emit("It's destroyed!")


func _start_throw_item() -> void:
	set_state(S.THROW_ITEM)
	current_move_key = "throw_item"
	if _flat_to_opponent().length() < 6.0:
		_snap_face_opponent()


func _throw_item_state() -> void:
	if not hit_landed and state_time >= 0.22:
		hit_landed = true
		var it := held_item
		held_item = null  # before anything can set_state and "drop" it
		if _item_ok(it) and items != null:
			var opp_up: bool = opponent.is_standing()
			var target_ok := opp_up and _in_front(6.0)
			var op: Vector3 = opponent.position
			var to: Vector3 = op if target_ok else position + facing * 3.5
			items.throw_item(it, position + facing * 0.4 + Vector3(0, 1.5, 0), to)
			sfx.emit("whoosh", 0.7, _chest())
			if target_ok:
				var ft: float = items.last_flight_time
				item_flight = maxf(ft, 0.01)
				item_flight_to = to
				item_flight_obj = it
	if state_time >= 0.5:
		set_state(S.IDLE)


func _thrown_item_arrives() -> void:
	var it := item_flight_obj
	item_flight_obj = null
	var opp_up: bool = opponent.is_standing()
	if not opp_up:
		return
	var op: Vector3 = opponent.position
	if Vector2(op.x - item_flight_to.x, op.z - item_flight_to.z).length() > 1.0:
		return  # they moved: it clatters onto the mat
	var kind := "chair"
	var dmg := 10.0
	if _item_ok(it):
		kind = _item_kind(it)
		var d: float = it.get("damage")
		dmg = d
	if opponent.receive_strike(self, dmg, true):
		announce.emit(_item_call(kind, "throw"))
		var og: Vector3 = opponent.global_position
		sfx.emit(_item_sfx(kind), 0.9, og + Vector3(0, 1.5, 0))
		if _item_ok(it) and items != null:
			items.damage_item(it, 1)


# --- tables ---------------------------------------------------------------------------

func _start_set_table(t: Node3D) -> void:
	set_state(S.SET_TABLE)
	current_move_key = "set_table"
	weapon_target = t


func _start_place_on_table(t: Node3D) -> void:
	set_state(S.SET_TABLE)
	current_move_key = "place_table"
	weapon_target = t
	_snap_face_opponent()
	sfx.emit("grab", 0.5, _chest())


func _set_table_state() -> void:
	var t := weapon_target
	if not hit_landed and state_time >= 0.35:
		hit_landed = true
		if _item_ok(t) and items != null:
			if current_move_key == "place_table":
				if _opp_state() == S.DOWN and _item_mode(t) == "standing":
					opponent.lie_on_table(t)
					# Step up beside the table, facing the body on it.
					var tp: Vector3 = t.position
					var op: Vector3 = opponent.position
					var ax: Vector3 = t.basis.x
					var across := Vector3(ax.z, 0.0, -ax.x).normalized()
					if across.dot(position - tp) < 0.0:
						across = -across
					position = Vector3(op.x, 0.0, op.z) + across * 0.85
					_snap_face_opponent()
					announce.emit("%s lays him out on the table!" % display_name)
					sfx.emit("whoa", 0.6, _chest())
			elif _item_mode(t) == "folded":
				items.set_up_table(t, position + facing * 1.3, rotation.y)
				announce.emit("%s sets up a TABLE!" % display_name)
				sfx.emit("metal_hit", 0.35, global_position + facing * 1.3 + Vector3(0, 0.8, 0))
				sfx.emit("whoa", 0.5, _chest())
	if state_time >= 0.7:
		weapon_target = null
		set_state(S.IDLE)


## Puts us flat on our back on top of a standing table (state ON_TABLE). Public: a diving
## opponent checks `state == S.ON_TABLE` and lands on us (receive_ground_hit / crash_through_table).
## The body is raised visually (pose_root, TABLE_TOP_Y); position.y stays 0.
func lie_on_table(table: Node3D) -> void:
	if not _item_ok(table):
		return
	set_state(S.ON_TABLE)
	on_table = table
	var ax: Vector3 = table.basis.x
	ax.y = 0.0
	ax = ax.normalized() if ax.length() > 0.01 else Vector3.RIGHT
	if ax.dot(facing) < 0.0:
		ax = -ax
	_set_facing_angle(atan2(ax.x, ax.z))
	var tp: Vector3 = table.position
	position = Vector3(tp.x, 0.0, tp.z) + ax * 0.2  # pelvis just past the middle, head on the table
	down_duration = maxf(3.2, _down_time() + 1.2)
	last_hit_tier = "ground"


## Smashes the table we lie on (if it still stands) and drops us through it. Public.
func crash_through_table(attacker: Node3D, dmg: float, emit_sfx := true) -> void:
	var t := on_table
	on_table = null
	if items != null and _item_ok(t) and _item_mode(t) != "broken":
		items.break_table(t)
	take_damage(dmg + TABLE_BREAK_DMG)
	if attacker != null:
		attacker.gain_spirit((dmg + TABLE_BREAK_DMG) * 1.5)
	set_state(S.DOWN)
	down_duration = TABLE_DOWN_TIME + (1.0 - health / 100.0) * 1.5
	last_hit_tier = "strong"
	current_move_key = "table_crash"
	impact.emit(1.1)
	if emit_sfx:
		sfx.emit("table_break", 1.2, global_position + Vector3(0, 0.6, 0))
		sfx.emit("big_thud", 1.0, global_position + Vector3(0, 0.3, 0))
	announce.emit("THROUGH THE TABLE!")


func _on_table_state() -> void:
	if _item_mode(on_table) != "standing":
		# Someone broke the table from under us (e.g. a dive that called break_table).
		crash_through_table(null, 0.0, false)
		return
	if state_time > down_duration:
		# Roll off the side and get up.
		position += Vector3(facing.z, 0.0, -facing.x) * 0.75
		set_state(S.GETTING_UP)


## receive_ground_hit hook while ON_TABLE: stomps just hurt, anything bigger (drops,
## weapon shots, dives) puts us through the table.
func _weapons_ground_hit_on_table(attacker: Node3D, dmg: float, key: String) -> bool:
	if key == "stomp":
		take_damage(dmg)
		attacker.gain_spirit(dmg * 1.5)
		current_move_key = key
		sfx.emit("thud", 0.45, global_position + Vector3(0, TABLE_TOP_Y + 0.3, 0))
		return true
	crash_through_table(attacker, dmg)
	return true


## _thrown hook (just landed, already DOWN): a throw onto a standing table breaks it.
func _weapons_check_table_landing() -> void:
	if items == null:
		return
	var t: Node3D = items.table_under(throw_to, 0.8)
	if t == null:
		return
	items.break_table(t)
	take_damage(TABLE_BREAK_DMG)
	opponent.gain_spirit(15.0)
	down_duration = maxf(down_duration, TABLE_DOWN_TIME)
	if last_hit_tier != "finisher":
		last_hit_tier = "strong"
	impact.emit(1.1)
	sfx.emit("table_break", 1.2, global_position + Vector3(0, 0.6, 0))
	announce.emit("THROUGH THE TABLE!")


# --- CPU ------------------------------------------------------------------------------

## _ai hook (we are IDLE / WALK). Returns true when it took over this frame's inputs.
func _ai_weapons(dist: float, toward: Vector2, os: int, can_act: bool) -> bool:
	if items == null:
		return false
	if os != S.DOWN:
		ai_down_roll = -1.0
	elif ai_down_roll < 0.0:
		ai_down_roll = randf()
	var opp_up: bool = opponent.is_standing()
	# Holding something: use it.
	if held_item != null:
		if os == S.DOWN or os == S.ON_TABLE:
			var opp_hp: float = opponent.health
			var tier: String = opponent.last_hit_tier
			if os == S.DOWN and (opp_hp < 45.0 or tier == "finisher" or tier == "strong"):
				if can_act:
					in_grapple = true  # drop it; the next decision goes for the cover
					ai_timer = 0.25
				return true
			if dist > 1.5:
				in_move = toward
			elif can_act:
				ai_timer = randf_range(0.5, 0.9)
				in_strike = true
			return true
		if not opp_up:
			return false
		if dist > 1.45:
			in_move = toward
			if can_act:
				ai_timer = randf_range(0.5, 0.9)
				var r := randf()
				if dist > 3.0 and dist < 6.0 and r < 0.12:
					in_pin = true   # throw it
				elif dist > 3.2 and r < 0.3:
					in_run = true   # running swing (the RUN branch presses STRIKE)
			return true
		if can_act:
			ai_timer = randf_range(0.5, 1.0) * (1.4 - 0.6 * ai_skill)
			in_strike = true
		return true
	# Opponent lying on a table: put them through it.
	if os == S.ON_TABLE:
		if dist > 1.6:
			in_move = toward
		elif can_act:
			ai_timer = 0.6
			in_strike = true
		return true
	# Walking to a weapon / folded table chosen earlier.
	if ai_item_goal != null:
		var gm := _item_mode(ai_item_goal)
		var holder: Node = ai_item_goal.get("held_by") if _item_ok(ai_item_goal) else null
		if (gm != "floor" and gm != "folded") or holder != null or anim_clock > ai_item_goal_until \
				or (opp_up and dist < 1.3):
			ai_item_goal = null
		else:
			var gp: Vector3 = ai_item_goal.position
			var d := gp - position
			d.y = 0.0
			if d.length() > 1.0:
				in_move = Vector2(d.x, d.z).normalized()
			else:
				in_grapple = true
				ai_item_goal = null
				ai_timer = 0.4
			return true
	if not can_act:
		return false
	if os == S.DOWN:
		var tier2: String = opponent.last_hit_tier
		var opp_hp2: float = opponent.health
		var pin_worthy := opp_hp2 < 55.0 or tier2 == "finisher"
		var t: Node3D = items.table_under(opponent.position, TABLE_PLACE_DIST)
		if t != null and ai_down_roll < 0.7 and not pin_worthy:
			if dist > 1.5:
				in_move = toward
			else:
				ai_timer = 0.5
				in_grapple = true
			return true
		var od: float = opponent.down_duration
		var ot: float = opponent.state_time
		if ai_down_roll < 0.35 and not pin_worthy and od - ot > 1.5:
			var ft: Node3D = items.nearest_folded_table(position, 12.0)
			if ft != null:
				ai_item_goal = ft
				ai_item_goal_until = anim_clock + 3.0
				return true
	var near: Node3D = items.nearest_item(position, 2.0)
	if near != null and not (opp_up and dist < 1.6):
		ai_timer = randf_range(0.3, 0.6)
		if randf() < 0.25:
			ai_item_goal = near
			ai_item_goal_until = anim_clock + 2.0
			return true
	return false


# --- poses ------------------------------------------------------------------------------
# Every held item is posed two-handed. The right fist (which carries the prop, see
# weapons.gd pick_up) is placed on an arc around the shoulder line by an arc key
# hk = (yaw, elevation, radius) in the torso frame; the prop's long axis (model +Y) is aimed
# independently through the wrist (ik = (yaw, elevation), torso frame; applied to hand_r in
# _apply_item_wrist), and the left hand grabs a point on the prop itself, so it stays glued
# to it. Swings blend four keys: carry -> wind-up (smooth) -> impact (ease-in: the snap)
# -> follow-through (ease-out) -> back to carry. Angles in the key tables are in degrees.

const W_RIGHT := Vector3(1.0, 0.0, 0.0)
const W_UP := Vector3(0.0, 1.0, 0.0)


## Arc centre (x) of the right fist for an item kind: half the gap between the two hands.
func _w_x0(kind: String) -> float:
	match kind:
		"chair":
			return 0.2
		"trash_can":
			return 0.29
	return 0.04


## World point of the right fist for arc key hk (degrees, degrees, metres); mirror = left hand.
func _w_hand_pt(kind: String, hk: Vector3, mirror := false) -> Vector3:
	var yw := deg_to_rad(hk.x)
	var el := deg_to_rad(hk.y)
	var ce := cos(el)
	var x := _w_x0(kind) + hk.z * ce * sin(yw)
	if mirror:
		x = -x
	return torso.to_global(Vector3(x, 0.47 + hk.z * sin(el), hk.z * ce * cos(yw)))


## Left hand onto the held prop (the other chair leg, the far side of the rim, the knob of
## the 2x4); with nothing in hand it mirrors the right fist's arc instead.
func _w_grip_left(kind: String, hk: Vector3, w := 1.0) -> void:
	if not _item_ok(held_item):
		_reach(true, _w_hand_pt(kind, hk, true), w)
		return
	var mdl: Node3D = held_item.get("model")
	if mdl == null:
		return
	var g := Vector3(0.0, 0.02, 0.0)
	match kind:
		"chair":
			g = Vector3(-0.2, 0.15, 0.0)
		"trash_can":
			g = Vector3(-0.3, 0.6, 0.0)
	_reach(true, mdl.global_transform * g, w)


## Both hands on the item: right fist at arc key hk, item long axis along ik (yaw, elevation;
## degrees, torso frame), xh = preferred direction of the item's side axis (model +X).
func _w_hold(kind: String, hk: Vector3, ik: Vector3, xh: Vector3, w := 1.0) -> void:
	_reach(false, _w_hand_pt(kind, hk), w)
	var yw := deg_to_rad(ik.x)
	var el := deg_to_rad(ik.y)
	pt_item_on = held_item != null
	pt_item_y = Vector3(sin(yw) * cos(el), sin(el), cos(yw) * cos(el))
	pt_item_x = xh
	_w_grip_left(kind, hk, w)


## Picks key i -> i+1 of a four-key loop (carry, wind-up, impact, follow-through).
func _w_mix(i: int, u: float, k0: Vector3, k1: Vector3, k2: Vector3, k3: Vector3) -> Vector3:
	match i:
		0:
			return k0.lerp(k1, u)
		1:
			return k1.lerp(k2, u)
		2:
			return k2.lerp(k3, u)
	return k3.lerp(k0, u)


## Phase of a swing / heave: x = segment (0 wind-up, 1 snap, 2 follow-through, 3 recover),
## y = eased progress inside it. Between fol_end and rec_start the follow-through holds.
func _w_phase(t: float, cock_end: float, hit_at: float, fol_end: float, rec_start: float, end_at: float) -> Vector2:
	if t < cock_end:
		return Vector2(0.0, _smooth(t / cock_end))
	if t < hit_at:
		return Vector2(1.0, _ease_in(_seg(t, cock_end, hit_at)))
	if t < fol_end:
		return Vector2(2.0, _ease_out(_seg(t, hit_at, fol_end)))
	return Vector2(3.0, _smooth(_seg(t, rec_start, end_at)))


## Carry key for an item kind: [hand arc key, item key, side-axis hint]. overhead = the 2x4 is
## about to be chopped down (same direction, expressed over the top so it blends forward).
func _w_carry(kind: String, overhead := false) -> Array:
	match kind:
		"chair":
			# folded chair up in front of the face with both hands on the legs, ready to come down
			return [Vector3(0.0, 15.0, 0.45), Vector3(0.0, 90.0, 0.0), W_RIGHT]
		"trash_can":
			# carried in front of the belly by the rim, both hands
			return [Vector3(0.0, -8.0, 0.56), Vector3(0.0, 90.0, 0.0), W_RIGHT]
	# the 2x4 rests over the right shoulder like a bat
	if overhead:
		return [Vector3(4.0, -9.5, 0.36), Vector3(-23.0, 142.0, 0.0), W_RIGHT]
	return [Vector3(4.0, -9.5, 0.36), Vector3(157.0, 38.0, 0.0), W_UP]


## Swing keys [hk wind-up, ik wind-up, hk impact, ik impact, hk follow, ik follow].
func _w_swing_keys(kind: String, ground: bool, horizontal: bool) -> Array:
	if horizontal:
		# 2x4 baseball swing: loaded behind the right shoulder, whipped flat across the front
		return [Vector3(79.0, 17.0, 0.3), Vector3(170.0, 25.0, 0.0),
			Vector3(0.0, -3.0, 0.45), Vector3(-10.0, 8.0, 0.0),
			Vector3(-54.0, -3.0, 0.42), Vector3(-110.0, 15.0, 0.0)]
	match kind:
		"trash_can":
			# hoisted overhead upside down, then slammed bottom-first
			if ground:
				return [Vector3(0.0, 79.0, 0.62), Vector3(0.0, 260.0, 0.0),
					Vector3(0.0, -10.0, 0.6), Vector3(0.0, 172.0, 0.0),
					Vector3(0.0, -18.0, 0.6), Vector3(0.0, 165.0, 0.0)]
			return [Vector3(0.0, 79.0, 0.62), Vector3(0.0, 260.0, 0.0),
				Vector3(0.0, 30.0, 0.6), Vector3(0.0, 210.0, 0.0),
				Vector3(0.0, -20.0, 0.6), Vector3(0.0, 160.0, 0.0)]
		"chair":
			# wound up behind the head (chair hanging down the back), then brought down flat
			if ground:
				return [Vector3(0.0, 102.0, 0.59), Vector3(0.0, 210.0, 0.0),
					Vector3(0.0, -30.0, 0.6), Vector3(0.0, 26.0, 0.0),
					Vector3(0.0, -38.0, 0.6), Vector3(0.0, 12.0, 0.0)]
			return [Vector3(0.0, 102.0, 0.59), Vector3(0.0, 210.0, 0.0),
				Vector3(0.0, 8.0, 0.56), Vector3(0.0, 57.0, 0.0),
				Vector3(0.0, -35.0, 0.6), Vector3(0.0, -10.0, 0.0)]
	# 2x4 chopped down onto a downed opponent
	return [Vector3(0.0, 100.0, 0.55), Vector3(0.0, 200.0, 0.0),
		Vector3(0.0, -30.0, 0.6), Vector3(0.0, 20.0, 0.0),
		Vector3(0.0, -40.0, 0.6), Vector3(0.0, 5.0, 0.0)]


func _pose_weapons(delta: float) -> void:
	match state:
		S.PICKUP_ITEM:
			_pose_pickup_item()
		S.SWING:
			_pose_swing(delta)
		S.THROW_ITEM:
			_pose_throw_item()
		S.ON_TABLE:
			_pose_on_table()
		S.SET_TABLE:
			if current_move_key == "place_table":
				_pose_place_on_table()
			else:
				_pose_set_table()


## Squat (rear knee nearly down), lunge in, grab it off the mat at 0.2 s, stand up with it.
func _pose_pickup_item() -> void:
	var t := state_time
	if _item_ok(weapon_target):
		# Where the hands go: the near edge of the prop, cached in our own frame because the
		# target is handed to the hands (and forgotten) at 0.2 s.
		var ip: Vector3 = weapon_target.position
		var rel := ip - position
		rel.y = 0.0
		var ik := _item_kind(weapon_target)
		var gp := Vector3(0.0, 0.12, 0.0)
		if ik == "trash_can":
			gp = Vector3(0.0, 0.6, 0.0) - rel.normalized() * 0.18
		_pick_pt = to_local(weapon_target.global_position + gp)
		_pick_lunge = clampf(rel.length() - 0.55, 0.0, 0.65)
	var kind := _item_kind(held_item)
	var down := _smooth(_seg(t, 0.0, 0.17))
	var up := _smooth(_seg(t, 0.22, 0.42))
	var b := down * (1.0 - up)
	r_limb = 20.0
	r_root = 18.0
	r_body = 16.0
	# lead foot steps in, rear knee drops toward the mat, hips back and the back bent over
	_legs_blend(0.5, 0.6, 0.6, -1.6, 0.2, b)
	pt_root_pos.z = _pick_lunge * b
	pt_tor = Vector3(0.15 + 0.85 * b, 0.0, 0.0)
	pt_hd = Vector3(-0.15 - 0.25 * b, 0.0, 0.0)
	var low := to_global(_pick_pt)
	var side := global_basis.x * 0.15
	if kind == "":
		# reaching down for it
		pt_al = Vector3(-0.6, 0.0, -0.3)
		pt_ar = Vector3(-0.6, 0.0, 0.3)
		pt_el_l = Vector3(-0.6, 0.0, 0.0)
		pt_el_r = Vector3(-0.6, 0.0, 0.0)
		_reach(false, low + side, down)
		_reach(true, low - side, down)
		return
	# got it: haul it up into the carry
	var c: Array = _w_carry(kind)
	var hk: Vector3 = c[0]
	var ikc: Vector3 = c[1]
	var xh: Vector3 = c[2]
	var carry_pt := _w_hand_pt(kind, hk)
	_reach(false, (low + side).lerp(carry_pt, up))
	pt_item_on = true
	var yw := deg_to_rad(ikc.x)
	var el := deg_to_rad(ikc.y)
	pt_item_y = Vector3(sin(yw) * cos(el), sin(el), cos(yw) * cos(el))
	pt_item_x = xh
	r_item = 14.0
	_w_grip_left(kind, hk)


func _pose_swing(delta: float) -> void:
	var t := state_time
	var kind := _item_kind(held_item)
	if kind == "":
		kind = _swing_kind  # the prop broke on impact: finish the motion empty-handed
	else:
		_swing_kind = kind
	var run := swing_running
	var ground := current_move_key == "swing_ground"
	var horizontal := kind == "plank" and not ground
	var ph: Vector2
	if run:
		ph = _w_phase(t, 0.08, 0.18, 0.27, 0.32, 0.55)
	elif ground:
		ph = _w_phase(t, 0.15, SWING_HIT, 0.36, 0.48, SWING_END)
	else:
		ph = _w_phase(t, 0.15, SWING_HIT, 0.4, 0.46, SWING_END)
	var i := int(ph.x)
	var u := ph.y
	var c: Array = _w_carry(kind, kind == "plank" and ground)
	var k: Array = _w_swing_keys(kind, ground, horizontal)
	var hk := _w_mix(i, u, c[0], k[0], k[2], k[4])
	var ik := _w_mix(i, u, c[1], k[1], k[3], k[5])
	var xh: Vector3 = c[2]
	if horizontal and i == 3:
		hk.z += 0.15 * sin(PI * u)  # bring the bat back around out in front, clear of the chest
	# body keys: (lean, crouch, pelvis forward) and (twist, lead-foot step, 0)
	var b0 := Vector3(0.12, 0.5, 0.0)
	var b1 := Vector3(-0.28, 0.35, -0.06)
	var b2 := Vector3(0.35, 0.85, 0.12)
	var b3 := Vector3(0.5, 0.95, 0.15)
	var tw1 := Vector3(0.0, 0.1, 0.0)
	var tw2 := Vector3(0.0, -0.35, 0.0)
	var tw3 := Vector3(0.0, -0.35, 0.0)
	if ground:
		b2 = Vector3(0.85, 1.05, 0.15)
		b3 = Vector3(0.95, 1.1, 0.17)
	if horizontal:
		b1 = Vector3(0.1, 0.6, -0.04)
		b2 = Vector3(0.2, 0.75, 0.1)
		b3 = Vector3(0.25, 0.7, 0.1)
		tw1 = Vector3(0.75, 0.25, 0.0)
		tw2 = Vector3(-0.1, -0.35, 0.0)
		tw3 = Vector3(-0.85, -0.35, 0.0)
	var bd := _w_mix(i, u, b0, b1, b2, b3)
	var tw := _w_mix(i, u, Vector3.ZERO, tw1, tw2, tw3)
	var coil := _w_coil(i, u)
	r_limb = 34.0 if i == 1 or i == 2 else 22.0
	r_body = 26.0 if i == 1 or i == 2 else 16.0
	r_item = 40.0 if i == 1 or i == 2 else 22.0
	if run:
		# still carried by the run: the stride freezes into a long lunge at the hit
		var stride := _smooth(_seg(t, 0.0, 0.18))
		_gait += delta * 15.0 * (1.0 - stride)
		var s := sin(_gait)
		pt_ll = Vector3(lerpf(-0.35 - s * 0.85, -0.85, stride), 0.0, -0.08)
		pt_lr = Vector3(lerpf(-0.35 + s * 0.85, 0.45, stride), 0.0, 0.08)
		pt_kn_l = lerpf(0.6, 0.75, stride)
		pt_kn_r = lerpf(0.6, 0.9, stride)
		pt_auto_height = true
		bd.x += 0.12
	else:
		_stance(bd.y)
		pt_ll.x += tw.y        # the lead foot lifts on the wind-up, plants long on the hit
		pt_kn_l += 0.35 * coil
		pt_root_pos.z = bd.z
	pt_tor = Vector3(bd.x, tw.x, 0.0)
	pt_hd = Vector3(-0.6 * bd.x - 0.1, -0.5 * tw.x, 0.0)
	_w_hold(kind, hk, ik, xh)


## 1 while loaded on the wind-up (lifts the lead knee), 0 once the swing is under way.
func _w_coil(i: int, u: float) -> float:
	if i == 0:
		return u
	if i == 1:
		return 1.0 - u
	return 0.0


## Wind-up behind the head, two-handed heave (released at 0.22 s), follow-through.
func _pose_throw_item() -> void:
	var t := state_time
	var kind := _item_kind(held_item)
	if kind == "":
		kind = _swing_kind
	else:
		_swing_kind = kind
	var ph := _w_phase(t, 0.15, 0.22, 0.32, 0.36, 0.5)
	var i := int(ph.x)
	var u := ph.y
	var c: Array = _w_carry(kind, true)
	var hk1 := Vector3(0.0, 112.0, 0.6)
	var ik1 := Vector3(0.0, 215.0, 0.0)
	var ik2 := Vector3(0.0, 120.0, 0.0)
	if kind == "trash_can":
		hk1 = Vector3(0.0, 92.0, 0.62)  # the can is wide: kept higher, clear of the head
		ik1 = Vector3(0.0, 255.0, 0.0)
		ik2 = Vector3(0.0, 225.0, 0.0)
	elif kind == "plank":
		ik1 = Vector3(0.0, 205.0, 0.0)
		ik2 = Vector3(0.0, 110.0, 0.0)
	var hk := _w_mix(i, u, c[0], hk1, Vector3(0.0, 50.0, 0.62), Vector3(0.0, -10.0, 0.6))
	var ik := _w_mix(i, u, c[1], ik1, ik2, ik2)
	var bd := _w_mix(i, u, Vector3(0.12, 0.5, 0.0), Vector3(-0.35, 0.4, -0.08), Vector3(0.2, 0.7, 0.1),
		Vector3(0.55, 0.8, 0.15))
	r_limb = 32.0 if i == 1 or i == 2 else 20.0
	r_body = 24.0 if i == 1 or i == 2 else 14.0
	r_item = 36.0
	_stance(bd.y)
	var e := 1.0 if i == 2 else (u if i == 1 else (1.0 - u if i == 3 else 0.0))
	pt_ll.x -= 0.35 * e          # step into the heave
	pt_lr.x += 0.35 * e * e      # trailing leg kicks up behind
	pt_kn_r += 0.6 * e * e
	pt_root_pos.z = bd.z
	pt_tor = Vector3(bd.x, 0.0, 0.0)
	pt_hd = Vector3(-0.6 * bd.x - 0.1, 0.0, 0.0)
	if held_item != null:
		_w_hold(kind, hk, ik, c[2])
	else:
		_reach(false, _w_hand_pt(kind, hk))
		_reach(true, _w_hand_pt(kind, hk, true))


## Flat on the back on top of the table (the pose is raised by the table height): arms
## dangling off the sides, both knees up with the feet on the table top.
func _pose_on_table() -> void:
	var ac := anim_clock
	pt_root_direct = true
	r_limb = 8.0
	r_body = 9.0
	_down_relaxed()
	pt_root_pos.y += TABLE_TOP_Y
	pt_al = Vector3(1.15 + 0.05 * sin(ac * 1.3), 0.0, -0.55)
	pt_ar = Vector3(1.05 + 0.05 * sin(ac * 1.1), 0.0, 0.6)
	pt_el_l = Vector3(-0.45, 0.0, 0.0)
	pt_el_r = Vector3(-0.35, 0.0, 0.0)
	pt_ll = Vector3(-0.85, 0.0, -0.14 + 0.06 * sin(ac * 0.9))
	pt_kn_l = 1.85
	pt_lr = Vector3(-0.95, 0.0, 0.16)
	pt_kn_r = 2.0
	pt_hd.z = 0.18 * sin(ac * 0.6)  # groggy head roll


## Unfolding the table: bend and grab, rip the legs open with the arms spread wide, then slam
## it down onto its feet in front of us (it appears 1.3 m ahead at 0.35 s).
func _pose_set_table() -> void:
	var t := state_time
	var grab := _smooth(_seg(t, 0.0, 0.12))
	var pull := _smooth(_seg(t, 0.1, 0.27))
	var slam := _ease_in(_seg(t, 0.27, 0.36))
	var rec := _smooth(_seg(t, 0.45, 0.7))
	var press := slam * (1.0 - rec)
	r_limb = 22.0
	r_body = 18.0
	_stance(0.5 + 0.35 * grab * (1.0 - pull) + 0.25 * pull * (1.0 - slam) + 0.4 * press)
	pt_tor = Vector3(0.15 + 0.4 * grab * (1.0 - pull) - 0.25 * pull * (1.0 - slam) + 0.6 * press, 0.0, 0.0)
	pt_hd = Vector3(-0.2 - 0.3 * pull * (1.0 - slam), 0.0, 0.0)
	pt_root_pos.z = 0.22 * press - 0.08 * pull * (1.0 - slam)
	# grab low in front -> arms wrenched wide apart, elbows locked -> palms down on the top
	var wide := pull * (1.0 - slam)
	pt_al = Vector3(lerpf(-1.1, -1.25, wide), 0.0, lerpf(-0.15, -1.35, wide))
	pt_ar = Vector3(lerpf(-1.1, -1.25, wide), 0.0, lerpf(0.15, 1.35, wide))
	pt_el_l = Vector3(lerpf(-0.5, -0.15, wide), 0.0, 0.0)
	pt_el_r = Vector3(lerpf(-0.5, -0.15, wide), 0.0, 0.0)
	if slam > 0.0:
		var w := slam * (1.0 - rec)
		_reach(true, to_global(Vector3(-0.5, 0.84, 0.95)), w)
		_reach(false, to_global(Vector3(0.5, 0.84, 0.95)), w)


## Dragging the downed opponent onto the table: bend over, grab under the shoulders, haul
## (legs drive, back straightens) and shove them up onto it (they land on it at 0.35 s).
func _pose_place_on_table() -> void:
	var t := state_time
	var bend := _smooth(_seg(t, 0.0, 0.15))
	var haul := _smooth(_seg(t, 0.15, 0.35))
	var rec := _smooth(_seg(t, 0.45, 0.7))
	var on := 1.0 - rec
	r_limb = 20.0
	r_body = 16.0
	_stance(0.5 + 0.55 * bend * on - 0.2 * haul * on)
	pt_tor = Vector3(0.15 + 0.85 * bend * on - 0.45 * haul * on, 0.0, 0.0)
	pt_hd = Vector3(-0.1 - 0.2 * haul, 0.0, 0.0)
	pt_root_pos.z = -0.1 * haul * on
	var ot := _opp_node("torso")
	var p1 := ot.to_global(Vector3(-0.22, 0.35, 0.0))
	var p2 := ot.to_global(Vector3(0.22, 0.35, 0.0))
	if t < 0.35:
		# pulled toward us and up while hauling
		var pull := (global_position + Vector3(0.0, 1.2, 0.0) - (p1 + p2) * 0.5) * 0.25 * haul
		p1 += pull
		p2 += pull
	_reach_pair(p1, p2, on * bend)


## Carry pose while walking around with an item (IDLE / WALK / RUN), or hoisting it to the
## crowd (TAUNT / WIN). Called after the state's own pose: replaces the arms only.
func _pose_hold_item() -> void:
	var kind := _item_kind(held_item)
	if kind == "":
		return
	var c: Array = _w_carry(kind)
	var hk: Vector3 = c[0]
	var ik: Vector3 = c[1]
	var xh: Vector3 = c[2]
	match state:
		S.IDLE, S.WALK, S.RUN:
			if state != S.IDLE:
				hk.y += 4.0 * sin(_gait * 2.0)  # the prop bounces with the steps
			else:
				hk.y += 1.5 * sin(anim_clock * 2.3)
			if state == S.RUN:
				hk.z -= 0.04
			_w_hold(kind, hk, ik, xh)
		S.TAUNT, S.WIN:
			# hoisted overhead and shaken at the crowd
			var on := 1.0
			if state == S.TAUNT:
				on = _smooth(_seg(state_time, 0.05, 0.3)) * (1.0 - _smooth(_seg(state_time, TAUNT_TIME - 0.2, TAUNT_TIME)))
			var shake := sin(anim_clock * 11.0) * on
			var up_hk := Vector3(4.0 * shake, 66.0 + 6.0 * shake, 0.62)
			var up_ik := Vector3(0.0, 98.0 + 8.0 * shake, 0.0)
			if kind == "trash_can":
				up_ik = Vector3(0.0, 262.0 + 8.0 * shake, 0.0)  # upside down over the head
			elif kind == "plank":
				ik = Vector3(-23.0, 142.0, 0.0)  # same direction, blends over the top
			_w_hold(kind, hk.lerp(up_hk, on), ik.lerp(up_ik, on), W_RIGHT)
			pt_tor.x = lerpf(pt_tor.x, -0.12, on)
			pt_hd.x = lerpf(pt_hd.x, -0.35, on)


## Wrist: turns hand_r (which carries the held prop) so the prop's long axis follows
## pt_item_y (torso frame); eases back to straight when nothing is posed.
func _apply_item_wrist(delta: float) -> void:
	if hand_r == null:
		return
	var target := Quaternion.IDENTITY
	if pt_item_on and _item_ok(held_item) and held_item.get_parent() == hand_r:
		var mdl: Node3D = held_item.get("model")
		if mdl != null:
			var hb: Basis = mdl.get_meta("base_basis", Basis.IDENTITY)
			var y := pt_item_y.normalized()
			var xh := pt_item_x
			if absf(xh.dot(y)) > 0.92:
				xh = W_UP if absf(y.y) < 0.7 else Vector3(0.0, 0.0, -1.0)
			var z := xh.cross(y).normalized()
			var x := y.cross(z)
			var want := torso.global_basis.orthonormalized() * Basis(x, y, z)
			var par := elbow_r.global_basis.orthonormalized()
			target = (par.inverse() * want * hb.inverse()).orthonormalized().get_rotation_quaternion()
	var k := 1.0 - exp(-r_item * delta)
	hand_r.quaternion = hand_r.quaternion.slerp(target, k).normalized()


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

	if _hf_ai(dist, toward, os):  # high flying hook: climbs, dives, springboards, corner spots
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
		S.PUNCH:
			_ai_string(toward)  # strike strings
			return
		S.THROWING:
			_ai_chain()  # grapple chains
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
	if _ai_weapons(dist, toward, os, can_act):
		return  # weapons hook

	if os == S.DOWN:
		_ai_vs_downed(dist, toward, opp_hp, can_act)
		return
	if os == S.JUGGLED:
		_ai_juggle(dist, toward, can_act)  # strike strings: launcher follow-ups
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
	elif reversal_kind == "ender":
		c = 0.08 + 0.3 * ai_skill
	elif reversal_kind == "chain":
		c = 0.05 + 0.25 * ai_skill
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
var pt_item_on := false            # aim the held prop through the wrist (hand_r)
var pt_item_y := Vector3.UP        # held prop's long axis (model +Y), torso frame
var pt_item_x := Vector3.RIGHT     # preferred direction of the prop's side axis (model +X)
var r_item := 22.0
var pt_basis_off := Vector3.ZERO   # extra pelvis offset in the basis-posed (throw_pose_q) mode

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
var _pick_pt := Vector3.ZERO       # PICKUP_ITEM: where the hands grab, in our own frame
var _pick_lunge := 0.0             # PICKUP_ITEM: how far the pelvis lunges in to reach it
var _swing_kind := "chair"         # SWING / THROW_ITEM: the prop kind, kept if it breaks mid-swing
var _bump_big := false             # DOWN: flattened by a weapon shot (stiff flat-back bump)
var _bump_off := Vector3.ZERO      # DOWN: where we stood before the knockback shove (own frame)
var _prev_item_flight := -1.0
var anim_item_hit_clock := -10.0   # anim_clock when our thrown item reached its target

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
	pt_item_on = false
	r_item = 22.0
	pt_basis_off = Vector3.ZERO


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
		_bump_big = _entry_root_x > -1.0 and _weapon_knockdown()
		if _bump_big:
			# receive_strike shoved us 0.6 m away from the attacker: start the fall from where
			# we stood, so the bump carries us back instead of popping.
			var away: Vector3 = position - opponent.position
			away.y = 0.0
			_bump_off = Vector3.ZERO
			if away.length() > 0.01:
				_bump_off = basis.inverse() * (-away.normalized() * 0.6)
				_bump_off.y = 0.0


## Did a weapon just knock us down (a swing in progress, or a thrown prop arriving)?
func _weapon_knockdown() -> bool:
	if opponent == null:
		return false
	if _opp_state() == S.SWING:
		return true
	var oc: float = opponent.anim_clock
	var oa: float = opponent.anim_item_hit_clock
	return oc - oa < 0.12


func _update_pose(delta: float) -> void:
	if _style < 0:
		_style = absi(display_name.hash()) % 3
	if _prev_item_flight > 0.0 and item_flight <= 0.0:
		anim_item_hit_clock = anim_clock
	_prev_item_flight = item_flight
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
		S.PICKUP_ITEM, S.SWING, S.THROW_ITEM, S.ON_TABLE, S.SET_TABLE:
			_pose_weapons(delta)  # weapons hook
		# high flying (see "# ---- high flying")
		S.CLIMB:
			_pose_hf_climb()
		S.PERCHED:
			_pose_hf_perched()
		S.DIVING:
			_pose_hf_diving()
		S.PERCH_FALL:
			_pose_hf_perch_fall()
		S.CORNER_STUN:
			_pose_hf_corner_stun()
		S.JUGGLED:
			_pose_juggled()  # strike strings
	if held_item != null:
		_pose_hold_item()  # weapons hook: carry / hoist the item with both hands
	_apply_pose(delta)
	_apply_item_wrist(delta)


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
		pose_root.position = Vector3(0.0, throw_pose_y, 0.0) + pt_basis_off
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
	match _anim_key(current_move_key):
		"knee":
			_pose_knee_lift()
		"clothesline":
			_pose_clothesline()
		"hook":
			_pose_hook()
		"uppercut", "launcher":
			_pose_uppercut()
		"haymaker":
			_pose_haymaker()
		"superkick":
			_pose_superkick()
		"spin_kick":
			_pose_spin_kick()
		"juggle_knee":
			_pose_juggle_knee()
		_:
			_pose_jab()


func _pose_jab() -> void:
	# Short wind-up (shoulder back, fist cocked) -> snap out to the hit -> recoil.
	var t := state_time
	var tm := _strike_times()
	var wind := _smooth(_seg(t, 0.0, tm.x * 0.45))
	var snap := _ease_in(_seg(t, tm.x * 0.45, tm.x))
	var back := _smooth(_seg(t, tm.x + 0.05, tm.y))
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
	if os == S.PUNCH and _strip_super(ok) == "knee":
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
	var mk := _anim_key(current_move_key)
	if throw_chained:
		# grapple chain: haul the victim back up first, then the move plays in the rest
		var cy := clampf(CHAIN_YANK / maxf(throw_time, 0.01), 0.05, 0.5)
		if p < cy:
			_pose_chain_yank(p / cy)
			return
		p = _seg(p, cy, 1.0)
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
	match mk:
		"slam", "powerslam":
			var dip := _hump(p, 0.0, 0.22)
			var lift := _smooth(_seg(p, 0.05, 0.4))
			var slam := _ease_in(_seg(p, 0.5, 1.0))
			if mk == "powerslam":
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
			if mk == "armdrag":
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
	if current_move_key.begins_with("super_"):
		pt_root_dy += 0.3 * _hump(p, 0.15, 0.6)  # BRAWL MODE: leap with it


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
	var k: Array = [_key(0.0, f0, s0, throw_start_y, _qe(throw_yaw_start, throw_start_pitch))]
	var land_ease := EASE_IN
	var mv: Dictionary = MOVES.get(key, {})
	var kk: String = mv.get("keys", mv.get("anim", key))
	match kk:
		"triple_suplex":
			# up and over like the suplex, but held upside down at the very top first
			throw_land_yaw = PI
			k.append(_key(0.1, 0.75, 0.5, 1.3, _qe(PI, 0.25 * PI)))
			k.append(_key(0.22, 0.5, 0.5, 1.95, _qe(PI, 0.55 * PI)))
			k.append(_key(0.38, 0.3, 0.5, 2.6, _qe(PI, 0.88 * PI), EASE_OUT))
			k.append(_key(0.55, 0.2, 0.5, 2.75, _qe(PI, 1.0 * PI)))
			k.append(_key(0.65, 0.1, 0.5, 2.5, _qe(PI, 1.08 * PI)))
		"catch_slam":
			# caught in mid-air across the chest and slammed straight down
			throw_land_yaw = -0.5 * PI
			k.append(_key(0.3, 0.5, 0.0, 1.7, _qe(PI, 0.0, 0.5 * PI), EASE_OUT))
			k.append(_key(0.45, 0.5, 0.0, 1.75, _qe(PI, 0.0, 0.5 * PI)))
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
	if key.begins_with("super_"):
		k = _super_keys(k, float(mv.get("lift", 0.9)), float(mv.get("spin", 1)))
	if throw_chained:
		k = _chain_keys(k, f0, s0)
	return k


## Samples the victim's throw path at p: sets our ring position and the pelvis pose.
func _throw_sample(p: float) -> void:
	var sm := _keys_at(_throw_keys(current_move_key), p)
	var v: Vector3 = sm[0]
	throw_pose_q = sm[1]
	throw_pose_y = v.z
	var fwd := Vector3(sin(throw_yaw0), 0.0, cos(throw_yaw0))
	var rgt := Vector3(cos(throw_yaw0), 0.0, -sin(throw_yaw0))
	position = throw_origin + fwd * v.x + rgt * v.y
	_set_facing_angle(throw_yaw0)


func _pose_thrown() -> void:
	var p := clampf(state_time / maxf(throw_time, 0.01), 0.0, 1.0)
	if throw_chained:
		p = _seg(p, clampf(CHAIN_YANK / maxf(throw_time, 0.01), 0.05, 0.5), 1.0)
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
	match _anim_key(current_move_key):
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
	var fall_t := 0.42 if _bump_big else 0.34
	if from_up and t < fall_t and _bump_big:
		_pose_flat_bump(t / fall_t)
		return
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
	if _bump_big and from_up:
		# flat-back bump: the whole back slaps down, everything bounces higher
		bounce *= 1.6
		fling *= 1.4
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


## Weapon knockdown: stiff from the shot, the body topples flat like a cut tree (pivoting on
## the heels, which slide out), arms flung up then wide, chin tucked, and the whole back
## slaps the mat at once. u = 0..1 over the fall; ends exactly in the lying DOWN pose.
func _pose_flat_bump(u: float) -> void:
	var recoil := _smooth(_seg(u, 0.0, 0.18))
	var fall := _ease_in(_seg(u, 0.1, 1.0))
	var th := lerpf(-0.18 * recoil, -PI / 2, fall)
	var foot := _bump_off.lerp(Vector3(0.0, 0.0, 0.95), _smooth(_seg(u, 0.05, 1.0)))
	var ct := cos(th)
	var y := 0.95 * ct + LIE_Y * (1.0 - ct) + 0.07 * _hump(u, 0.0, 0.35)
	pt_root_rot = Vector3(th, 0.0, 0.0)
	pt_root_pos = Vector3(foot.x, y, foot.z + 0.95 * sin(th))
	# legs locked straight: the fall is all one piece
	pt_ll = Vector3(-0.05, 0.0, -0.08)
	pt_lr = Vector3(0.0, 0.0, 0.08)
	pt_kn_l = 0.08
	pt_kn_r = 0.05
	var wide := _smooth(_seg(u, 0.3, 0.7))
	var slap := _smooth(_seg(u, 0.8, 1.0))
	pt_al = Vector3(-0.6, 0.0, -0.3).lerp(Vector3(-2.5, 0.0, -0.6), recoil).lerp(Vector3(-1.3, 0.0, -1.35), wide) \
		.lerp(Vector3(0.05, 0.0, -1.25), slap)
	pt_ar = Vector3(-0.6, 0.0, 0.3).lerp(Vector3(-2.4, 0.0, 0.65), recoil).lerp(Vector3(-1.2, 0.0, 1.35), wide) \
		.lerp(Vector3(0.05, 0.0, 1.2), slap)
	pt_el_l = Vector3(-0.3, 0.0, 0.0)
	pt_el_r = Vector3(-0.3, 0.0, 0.0)
	var tuck := _smooth(_seg(u, 0.35, 0.75))
	pt_tor = Vector3(lerpf(-0.3 * recoil, 0.08, tuck), 0.0, 0.0)
	pt_hd = Vector3(lerpf(-0.6 * recoil, 0.45, tuck), 0.0, 0.0)
	r_limb = 22.0
	r_body = 24.0


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


# ---- high flying
# Turnbuckle climbs, dives off the top, springboards off the ropes and corner spots.
# Corner posts sit at local (±4.15, ±4.15); a perched wrestler stands on the top turnbuckle at
# (±3.75, 1.35, ±3.75). While climbing / perched / diving / falling off, position.y may be > 0
# (_hf_clamp keeps _clamp_ring from flattening it). Airborne wrestlers can't be pinned, grabbed
# or struck (receive_strike returns false), except that a strike within 1.4 m knocks a
# climbing / perched wrestler off the top.

const HF_CORNER_POST := 4.15
const HF_PERCH_XZ := 3.75
const HF_PERCH_Y := 1.35
const HF_CLAMP := 3.9            # xz limit in the high-flying states (corners are reachable)
const HF_CLIMB_RANGE := 1.1      # distance from a corner post that allows a climb
const HF_SPRING_WINDOW := 0.35   # STRIKE this soon after a rope bounce = springboard
const HF_MAX_DIVE := 5.0         # nobody flies further than this off the top
const HF_GROUND_DIVES := ["backyard_splash", "moonsault", "flying_elbow", "gutter_star"]

var hf_move := ""                # DIVING: MOVES key of the dive / springboard / splash
var hf_mode := ""                # CLIMB: "up" / "down" / "jump"; PERCH_FALL: "crotch" / "fall"
var hf_corner := Vector3.ZERO    # sign vector of the corner we're using, e.g. (1, 0, -1)
var hf_from := Vector3.ZERO
var hf_to := Vector3.ZERO
var hf_time := 0.7               # flight / climb duration
var hf_height := 1.0             # arc apex
var hf_land_time := 0.3          # DIVING: settle time after touching down
var hf_landed := false
var hf_result := ""              # "hit" / "crash" once landed
var hf_end_yaw := 0.0            # visual yaw (rel. to facing) of the final lying pose
var hf_stun_time := 1.5          # CORNER_STUN duration
var hf_corner_whip := false      # current whip was aimed at a corner
var hf_rope_at := -10.0          # anim_clock of the last rope bounce
var hf_fall_hit := false         # PERCH_FALL one-shot (crotch impact)
# AI
var hf_ai_wait := 0.5
var hf_ai_climb_plan := -1       # -1 undecided, 0 no, 1 heading for a corner to climb
var hf_ai_spring_roll := 2.0
var hf_ai_tie_rolled := false
var hf_ai_dodge := -1


func is_airborne() -> bool:
	return state == S.CLIMB or state == S.PERCHED or state == S.DIVING or state == S.PERCH_FALL


func _hf_clamp() -> bool:
	if state in [S.CLIMB, S.PERCHED, S.DIVING, S.PERCH_FALL, S.CORNER_STUN]:
		position.x = clampf(position.x, -HF_CLAMP, HF_CLAMP)
		position.z = clampf(position.z, -HF_CLAMP, HF_CLAMP)
		position.y = 0.0 if state == S.CORNER_STUN else clampf(position.y, 0.0, 3.5)
		return true
	return false


func _hf_sign(v: float) -> float:
	return -1.0 if v < 0.0 else 1.0


## Sign vector of the corner we're within HF_CLIMB_RANGE of, or ZERO.
func _hf_near_corner() -> Vector3:
	var c := Vector3(_hf_sign(position.x), 0.0, _hf_sign(position.z))
	var d := Vector3(c.x * HF_CORNER_POST - position.x, 0.0, c.z * HF_CORNER_POST - position.z)
	return c if d.length() <= HF_CLIMB_RANGE else Vector3.ZERO


func _hf_nearest_corner_point(p: Vector3, inset: float) -> Vector3:
	return Vector3(_hf_sign(p.x) * inset, 0.0, _hf_sign(p.z) * inset)


func _hf_face_center() -> void:
	var c := hf_corner if hf_corner != Vector3.ZERO else Vector3(_hf_sign(position.x), 0.0, _hf_sign(position.z))
	_set_facing_angle(atan2(-c.x, -c.z))


func _hf_tick(delta: float) -> void:
	match state:
		S.CLIMB:
			_hf_climb()
		S.PERCHED:
			_hf_perched(delta)
		S.DIVING:
			_hf_diving()
		S.PERCH_FALL:
			_hf_perch_fall()
		S.CORNER_STUN:
			if state_time > hf_stun_time:
				set_state(S.IDLE)


# --- hooks called from the core state machine ----------------------------------------

## _free_move: RUN near a corner climbs it; GRAB on a cornered opponent = Super Drop.
func _hf_free_move_hook(dir: Vector3) -> bool:
	var os := _opp_state()
	if os == S.CORNER_STUN and in_grapple and _flat_to_opponent().length() < 1.6:
		_hf_super_drop()
		return true
	if not in_run:
		return false
	var c := _hf_near_corner()
	if c == Vector3.ZERO:
		return false
	var post := Vector3(c.x * HF_CORNER_POST, 0.0, c.z * HF_CORNER_POST)
	var to_post := post - position
	to_post.y = 0.0
	var aimed := dir.length() < 0.3 or dir.normalized().dot(to_post.normalized()) > 0.5
	var op: Vector3 = opponent.position
	var opp_in_corner := Vector3(post.x - op.x, 0.0, post.z - op.z).length() < 1.2
	if not aimed or opp_in_corner:
		return false
	hf_corner = c
	_hf_start_climb("up")
	return true


## _run (non-whipped, STRIKE pressed): corner splash or springboard. True if handled.
func _hf_run_strike() -> bool:
	var os := _opp_state()
	var to := _flat_to_opponent()
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else facing
	var op: Vector3 = opponent.position
	var opf := Vector3(op.x, 0.0, op.z)
	if os == S.CORNER_STUN and dist < 3.4:
		_hf_launch("corner_splash", opf - dir * 0.7)
		return true
	if anim_clock - hf_rope_at > HF_SPRING_WINDOW or os == S.DOWN:
		return false
	var opp_up: bool = opponent.is_standing() or os == S.CORNER_STUN
	var key := "springboard_moonsault" if opp_up and dist > 1.6 and dist < 3.0 else "springboard_forearm"
	var target := position + run_dir * 2.4
	if dist < 3.6:
		target = opf - dir * (0.35 if key == "springboard_moonsault" else 0.75)
	_hf_launch(key, target)
	return true


func _hf_on_rope_bounce() -> void:
	hf_rope_at = anim_clock
	hf_ai_spring_roll = randf()


## start_whipped: a whip aimed roughly at a corner is steered straight into it.
func _hf_corner_whip_dir(d: Vector3) -> Vector3:
	hf_corner_whip = false
	if absf(d.x) < 0.2 or absf(d.z) < 0.2:
		return d
	var c := Vector3(_hf_sign(d.x) * 3.6, 0.0, _hf_sign(d.z) * 3.6)
	var to_c := c - position
	to_c.y = 0.0
	if to_c.length() < 1.5 or d.normalized().dot(to_c.normalized()) < 0.88:
		return d
	hf_corner_whip = true
	return to_c.normalized()


## _run (whipped): reaching the corner = crash into the turnbuckle.
func _hf_check_corner_crash() -> bool:
	if not hf_corner_whip or rope_bounces > 0:
		return false
	if absf(position.x) < 3.3 or absf(position.z) < 3.3:
		return false
	hf_corner = Vector3(_hf_sign(position.x), 0.0, _hf_sign(position.z))
	set_state(S.CORNER_STUN)
	hf_corner_whip = false
	hf_stun_time = 1.5
	position = Vector3(hf_corner.x * 3.55, 0.0, hf_corner.z * 3.55)
	_hf_face_center()
	take_damage(5.0)
	impact.emit(0.35)
	sfx.emit("thud", 0.7, global_position + Vector3(0, 1.2, 0))
	sfx.emit("rope", 0.8, global_position + Vector3(0, 1.2, 0))
	announce.emit("Into the turnbuckle!")
	return true


## receive_strike: 1 = connected, 0 = no effect, -1 = not ours (normal handling).
func _hf_receive_strike(attacker: Node3D, dmg: float, knockdown: bool) -> int:
	match state:
		S.PERCHED, S.CLIMB:
			var ap: Vector3 = attacker.position
			if Vector3(ap.x - position.x, 0.0, ap.z - position.z).length() > 1.4:
				return 0
			take_damage(dmg)
			attacker.gain_spirit(dmg * 1.5 + 5.0)
			_hf_knock_off()
			return 1
		S.DIVING, S.PERCH_FALL:
			return 0
		S.CORNER_STUN:
			take_damage(dmg)
			attacker.gain_spirit(dmg * 1.5)
			if knockdown:
				set_state(S.DOWN)
				position -= Vector3(hf_corner.x, 0.0, hf_corner.z).normalized() * 0.6
				down_duration = _down_time()
				last_hit_tier = "strike"
				impact.emit(0.5)
				sfx.emit("kick", 0.7, global_position + Vector3(0, 1.4, 0))
			else:
				hf_stun_time = minf(maxf(hf_stun_time, state_time + 0.6), 3.0)
				impact.emit(0.1)
				sfx.emit("punch", 0.4, global_position + Vector3(0, 1.5, 0))
			return 1
	return -1


# --- climbing & the perch ------------------------------------------------------------

func _hf_start_climb(mode: String) -> void:
	if hf_corner == Vector3.ZERO:
		hf_corner = Vector3(_hf_sign(position.x), 0.0, _hf_sign(position.z))
	var c := hf_corner
	set_state(S.CLIMB)
	current_move_key = "climb_" + mode
	hf_mode = mode
	hf_from = position
	match mode:
		"up":
			hf_to = Vector3(c.x * HF_PERCH_XZ, HF_PERCH_Y, c.z * HF_PERCH_XZ)
			hf_time = 0.7
			sfx.emit("climb", 0.6, global_position + Vector3(0, 1.0, 0))
			announce.emit("%s is going up top!" % display_name)
		"down":
			hf_to = Vector3(c.x * 3.35, 0.0, c.z * 3.35)
			hf_time = 0.6
			sfx.emit("climb", 0.4, global_position + Vector3(0, 1.0, 0))
		_:
			hf_to = Vector3(c.x * 2.9, 0.0, c.z * 2.9)
			hf_time = 0.5
			sfx.emit("whoosh", 0.3, _chest())
	_hf_face_center()


func _hf_climb() -> void:
	var p := clampf(state_time / maxf(hf_time, 0.01), 0.0, 1.0)
	var flat := hf_from.lerp(hf_to, _smooth(p))
	var y := 0.0
	if hf_mode == "jump":
		flat = hf_from.lerp(hf_to, p)
		y = lerpf(hf_from.y, hf_to.y, p) + 1.6 * p * (1.0 - p)
	else:
		# three rung-like steps
		var s := p * 3.0
		var k := floorf(minf(s, 2.999))
		var step := (k + _smooth(_seg(s - k, 0.25, 0.85))) / 3.0
		y = lerpf(hf_from.y, hf_to.y, step)
	position = Vector3(flat.x, y, flat.z)
	if p < 1.0:
		return
	position = hf_to
	if hf_mode == "up":
		set_state(S.PERCHED)
		current_move_key = "perched"
		hf_ai_wait = randf_range(0.3, 0.9) * (1.5 - ai_skill)
	else:
		position.y = 0.0
		set_state(S.IDLE)
		if hf_mode == "jump":
			sfx.emit("thud", 0.3, global_position + Vector3(0, 0.2, 0))


func _hf_perched(delta: float) -> void:
	position = Vector3(hf_corner.x * HF_PERCH_XZ, HF_PERCH_Y, hf_corner.z * HF_PERCH_XZ)
	_face_opponent(delta)
	if in_strike:
		_hf_start_dive()
	elif in_grapple:
		_hf_start_climb("jump")
	elif in_run or state_time > 8.0:
		_hf_start_climb("down")  # (8 s safety timeout)


func _hf_knock_off() -> void:
	if hf_corner == Vector3.ZERO:
		hf_corner = Vector3(_hf_sign(position.x), 0.0, _hf_sign(position.z))
	var crotch := position.y > 0.9 and randf() < 0.5
	set_state(S.PERCH_FALL)
	hf_mode = "crotch" if crotch else "fall"
	current_move_key = "perch_" + hf_mode
	hf_fall_hit = false
	hf_from = position
	hf_to = Vector3(hf_corner.x * 2.7, 0.0, hf_corner.z * 2.7)
	_hf_face_center()
	impact.emit(0.35)
	sfx.emit("whoa", 0.8, _chest())
	announce.emit("Crotched on the turnbuckle! OOF!" if crotch else "Knocked off the top!")


func _hf_perch_fall() -> void:
	if hf_mode == "crotch":
		if state_time < 1.1:
			var d := _smooth(_seg(state_time, 0.0, 0.2))
			position = Vector3(hf_from.x, lerpf(hf_from.y, 0.32, d), hf_from.z)
			if d >= 1.0 and not hf_fall_hit:
				hf_fall_hit = true
				take_damage(4.0)
				impact.emit(0.3)
				sfx.emit("thud", 0.6, global_position + Vector3(0, 1.2, 0))
			return
		var u := _seg(state_time, 1.1, 1.6)
		var flat := Vector3(hf_from.x, 0.0, hf_from.z).lerp(hf_to, u)
		position = Vector3(flat.x, lerpf(0.32, 0.0, _ease_in(u)), flat.z)
		if u >= 1.0:
			_hf_fall_land()
		return
	var p := _seg(state_time, 0.0, 0.55)
	var f2 := hf_from.lerp(hf_to, p)
	position = Vector3(f2.x, lerpf(hf_from.y, 0.0, p) + 1.2 * p * (1.0 - p), f2.z)
	if p >= 1.0:
		take_damage(6.0)
		_hf_fall_land()


func _hf_fall_land() -> void:
	impact.emit(0.5)
	sfx.emit("big_thud", 0.8, global_position + Vector3(0, 0.3, 0))
	_hf_go_down(PI, _down_time())
	last_hit_tier = "strike"


## Lands lying on the back, keeping the visual orientation the last pose had (yaw_add is the
## visual yaw of that pose relative to our facing; it is folded into the facing).
func _hf_go_down(yaw_add: float, dur: float) -> void:
	position.y = 0.0
	_set_facing_angle(rotation.y + yaw_add)
	set_state(S.DOWN)
	last_hit_tier = ""
	down_duration = dur
	pose_root.rotation = Vector3(-PI / 2, 0.0, 0.0)
	pose_root.position = Vector3(0.0, LIE_Y, 0.0)


# --- dives ---------------------------------------------------------------------------

## The weapons code may add an ON_TABLE state; look it up by name so this works either way.
func _hf_on_table_state() -> int:
	var k := "ON_TABLE"
	if S.has(k):
		var v: int = S[k]
		return v
	return -1


## A wrestler lying on a table is in S.ON_TABLE (weapons code); treated like DOWN for dives.
func _hf_opp_on_table() -> bool:
	var ot := _hf_on_table_state()
	return ot >= 0 and _opp_state() == ot


func _hf_start_dive() -> void:
	var os := _opp_state()
	var to := _flat_to_opponent()
	var dir := to.normalized() if to.length() > 0.01 else facing
	var mv := Vector3(in_move.x, 0.0, in_move.y)
	var held := mv.length() > 0.4
	var fwd := mv.normalized().dot(dir) if held else 1.0
	var ground := os == S.DOWN or _hf_opp_on_table()
	var key := ""
	if ground:
		if is_special_ready():
			key = "gutter_star"
		elif fwd > 0.5:
			key = "backyard_splash"   # no stick / stick toward them
		elif fwd < -0.5:
			key = "moonsault"         # stick away
		else:
			key = "flying_elbow"      # stick sideways
	else:
		key = "missile_dropkick" if held else "crossbody"
	var off := 0.3 if ground else (0.9 if key == "missile_dropkick" else 0.55)
	var op: Vector3 = opponent.position
	var target := Vector3(op.x, 0.0, op.z) - dir * off
	var flat_from := Vector3(position.x, 0.0, position.z)
	if target.distance_to(flat_from) > HF_MAX_DIVE:
		target = flat_from + dir * HF_MAX_DIVE  # too far: this one's going to hurt
	_hf_launch(key, target)


func _hf_launch(key: String, target: Vector3) -> void:
	var m: Dictionary = MOVES[key]
	var from_perch := state == S.PERCHED
	var base_t: float = m["time"]
	var h: float = m["height"]
	var name_txt: String = m["name"]
	set_state(S.DIVING)
	current_move_key = key
	hf_move = key
	hf_from = position
	hf_to = Vector3(clampf(target.x, -RING_HALF, RING_HALF), 0.0, clampf(target.z, -RING_HALF, RING_HALF))
	var d := Vector3(hf_to.x - position.x, 0.0, hf_to.z - position.z)
	hf_time = base_t * clampf(d.length() / 3.0, 0.8, 1.35)
	hf_height = h
	hf_landed = false
	hf_result = ""
	hf_land_time = 0.3
	match key:
		"backyard_splash", "gutter_star":
			hf_end_yaw = PI
		"flying_elbow":
			hf_end_yaw = 0.5 * PI
		_:
			hf_end_yaw = 0.0
	if d.length() > 0.05:
		_set_facing_angle(atan2(d.x, d.z))
	if key == "corner_splash":
		sfx.emit("whoosh", 0.5, _chest())
	else:
		sfx.emit("dive", 0.8 if from_perch else 0.5, _chest())
	if from_perch:
		sfx.emit("whoa", 0.7, _chest())
	if key == "gutter_star":
		spirit = 0.0
		special_timer = 0.0
		sfx.emit("finisher", 1.0, _chest())
	if key == "gutter_star":
		announce.emit(name_txt)  # finisher: called on takeoff (other moves on impact)


func _hf_diving() -> void:
	var p := clampf(state_time / maxf(hf_time, 0.01), 0.0, 1.0)
	if not hf_landed:
		var flat := hf_from.lerp(hf_to, p)
		position = Vector3(flat.x, lerpf(hf_from.y, hf_to.y, p) + 4.0 * hf_height * p * (1.0 - p), flat.z)
		if p >= 1.0:
			hf_landed = true
			position = hf_to
			_hf_land()
		return
	if state_time >= hf_time + hf_land_time:
		_hf_finish_dive()


## Touchdown: did the target stay put? Applies the hit or the crash.
func _hf_land() -> void:
	var key := hf_move
	var m: Dictionary = MOVES[key]
	var dmg: float = m["dmg"]
	var tier: String = m["tier"]
	var name_txt: String = m["name"]
	var os := _opp_state()
	var op: Vector3 = opponent.position
	var miss_by := Vector3(op.x - hf_to.x, 0.0, op.z - hf_to.z).length()
	var contact := global_position + Vector3(0, 0.4, 0)
	hf_result = "crash"
	if key == "corner_splash":
		hf_land_time = 0.2
		if os == S.CORNER_STUN and miss_by <= 1.3:
			hf_result = "hit"
			opponent.take_damage(dmg)
			gain_spirit(dmg * 1.5)
			opponent.set_state(S.STUNNED)
			opponent.stun_time = 1.1
			opponent.dazed = true  # stumbles out of the corner: free lock-up
			opponent.position = op - Vector3(_hf_sign(op.x), 0.0, _hf_sign(op.z)).normalized() * 0.4
			announce.emit(name_txt)
			impact.emit(0.45)
			sfx.emit("big_thud", 0.8, contact + Vector3(0, 0.8, 0))
		else:
			take_damage(5.0)
			announce.emit("Ate the turnbuckle!")
			impact.emit(0.3)
			sfx.emit("thud", 0.6, contact + Vector3(0, 0.8, 0))
		return
	if key in HF_GROUND_DIVES:
		hf_land_time = 0.6
		var on_table := _hf_opp_on_table()
		if (os == S.DOWN or on_table) and miss_by <= 1.2:
			hf_result = "hit"
			if on_table:
				# receive_ground_hit on an ON_TABLE wrestler breaks the table itself
				# (table_break sfx + "THROUGH THE TABLE!"), so no items.break_table here.
				opponent.receive_ground_hit(self, dmg + 8.0, "dive")
				sfx.emit("whoa", 1.0, contact + Vector3(0, 1.0, 0))
			else:
				opponent.receive_ground_hit(self, dmg, key)
			if key != "gutter_star":
				announce.emit(name_txt)
			opponent.last_hit_tier = tier
			var ost: float = opponent.state_time
			var odd: float = opponent.down_duration
			opponent.down_duration = maxf(odd, ost + 2.0)
			gain_spirit(6.0)
			impact.emit(clampf(dmg / 16.0, 0.6, 1.3))
			sfx.emit("big_thud", clampf(dmg / 18.0, 0.8, 1.4), contact)
			return
	else:
		match key:
			"springboard_moonsault":
				hf_land_time = 0.5
			"crossbody":
				hf_land_time = 0.35
			"springboard_forearm":
				hf_land_time = 0.2
			_:
				hf_land_time = 0.25
		if os == S.GETTING_UP and miss_by <= 1.3:
			opponent.set_state(S.STUNNED)  # caught on the way up
		var hittable: bool = opponent.is_standing() or _opp_state() == S.CORNER_STUN
		if hittable and miss_by <= 1.3:
			if opponent.receive_strike(self, dmg, true):
				hf_result = "hit"
				opponent.last_hit_tier = tier
				gain_spirit(4.0)
				announce.emit(name_txt)
				impact.emit(clampf(dmg / 16.0, 0.5, 1.0))
				sfx.emit("big_thud" if key != "springboard_forearm" else "thud", 0.8, contact + Vector3(0, 0.6, 0))
				return
		elif key == "springboard_moonsault" and _opp_state() == S.DOWN and miss_by <= 1.2:
			hf_result = "hit"
			opponent.receive_ground_hit(self, dmg, key)
			announce.emit(name_txt)
			impact.emit(0.6)
			return
	# the target moved: crash and burn
	if key == "springboard_forearm":
		announce.emit("Missed!")
		sfx.emit("thud", 0.4, contact)
		return
	hf_land_time = maxf(hf_land_time, 0.45)
	take_damage(10.0 if key in HF_GROUND_DIVES else 7.0)
	announce.emit("CRASH AND BURN!")
	impact.emit(0.7)
	sfx.emit("big_thud", 1.0, contact)
	sfx.emit("whoa", 0.9, contact + Vector3(0, 1.0, 0))


func _hf_finish_dive() -> void:
	var hit := hf_result == "hit"
	match hf_move:
		"springboard_forearm":
			position.y = 0.0
			if hit:
				set_state(S.IDLE)
			else:
				set_state(S.WHIFF)
				whiff_time = 0.5
				current_move_key = "whiff"
			return
		"corner_splash":
			position.y = 0.0
			if hit:
				set_state(S.IDLE)
			else:
				set_state(S.STUNNED)
				stun_time = 0.8
			return
		"crossbody":
			if hit and _opp_state() == S.DOWN and _flat_to_opponent().length() < 2.0:
				position.y = 0.0
				set_state(S.IDLE)
				_try_pin_or_taunt()  # the crossbody rolls straight into a cover
				if state == S.PINNING:
					return
	_hf_go_down(hf_end_yaw, 0.7 if hit else _down_time() + 0.6)


func _hf_super_drop() -> void:
	var m: Dictionary = MOVES["super_drop"]
	var dmg: float = m["dmg"]
	var name_txt: String = m["name"]
	var land: float = m["land"]
	_snap_face_opponent()
	announce.emit(name_txt)
	sfx.emit("whoosh", 0.7, _chest())
	sfx.emit("whoa", 0.8, _chest())
	gain_spirit(dmg * 1.5)
	set_state(S.THROWING)
	current_move_key = "suplex"  # reuses the suplex animation, hauled out of the corner
	throw_time = m["time"]
	opponent.start_thrown(position + facing * land, m, "suplex")


# --- AI --------------------------------------------------------------------------------

func _hf_ai(dist: float, toward: Vector2, os: int) -> bool:
	if state != S.TIEUP_ATK:
		hf_ai_tie_rolled = false
	if os != S.DIVING:
		hf_ai_dodge = -1
	match state:
		S.CLIMB, S.DIVING, S.PERCH_FALL, S.CORNER_STUN:
			return true
		S.PERCHED:
			_hf_ai_perched(dist, toward, os)
			return true
		S.TIEUP_ATK:
			if not hf_ai_tie_rolled and committed_move == "" and state_time > ai_tie_delay:
				hf_ai_tie_rolled = true
				if randf() < 0.12:
					# Irish whip into the nearest corner
					var cp := _hf_nearest_corner_point(position, 3.6)
					var dc := cp - position
					in_run = true
					in_move = Vector2(dc.x, dc.z).normalized()
					return true
			return false
		S.RUN:
			if whipped:
				return false
			if os == S.CORNER_STUN:
				if dist < 3.0:
					in_strike = true
				else:
					in_move = toward
				return true
			if anim_clock - hf_rope_at < 0.3 and hf_ai_spring_roll < 0.3 and os != S.DOWN \
					and dist > 1.2 and dist < 3.8:
				hf_ai_spring_roll = 2.0
				in_strike = true
				return true
			return false
	if state != S.IDLE and state != S.WALK:
		return false
	var can_act := ai_react <= 0.0 and ai_timer <= 0.0
	# knock a climbing / perched opponent off the top
	if os == S.PERCHED or os == S.CLIMB:
		if dist > 1.2:
			in_move = toward
		elif can_act:
			ai_timer = randf_range(0.3, 0.7) * (1.4 - 0.6 * ai_skill)
			if randf() < 0.7:
				in_strike = true
		return true
	# punish a cornered opponent
	if os == S.CORNER_STUN:
		if can_act:
			ai_timer = randf_range(0.25, 0.5)
			if dist < 1.4:
				if randf() < 0.55:
					in_grapple = true  # Super Drop
				else:
					in_strike = true
			elif dist < 3.4:
				in_run = true
				in_move = toward  # charge in for a corner splash
			else:
				in_move = toward
		elif dist > 1.4:
			in_move = toward
		return true
	# see a standing-target dive coming: sometimes sidestep it
	if os == S.DIVING:
		var om: String = opponent.hf_move
		if dist < 4.0 and not (om in HF_GROUND_DIVES):
			if hf_ai_dodge < 0:
				hf_ai_dodge = 1 if randf() < 0.15 + 0.3 * ai_skill else 0
			if hf_ai_dodge == 1:
				in_move = Vector2(-toward.y, toward.x)
		return true
	# opponent down and a corner close by: sometimes go up top
	if os != S.DOWN:
		hf_ai_climb_plan = -1
		return false
	if hf_ai_climb_plan < 0:
		var cp := _hf_nearest_corner_point(position, HF_PERCH_XZ)
		var ost: float = opponent.state_time
		var odd: float = opponent.down_duration
		var near := Vector3(cp.x - position.x, 0.0, cp.z - position.z).length() < 3.0
		hf_ai_climb_plan = 1 if near and odd - ost > 1.6 and randf() < 0.25 else 0
	if hf_ai_climb_plan == 1:
		var cp2 := _hf_nearest_corner_point(position, HF_PERCH_XZ)
		var dc2 := Vector3(cp2.x - position.x, 0.0, cp2.z - position.z)
		in_move = Vector2(dc2.x, dc2.z).normalized()
		if _hf_near_corner() != Vector3.ZERO and ai_react <= 0.0:
			in_move = Vector2.ZERO  # RUN standing still next to a corner = climb
			in_run = true
			hf_ai_climb_plan = 0
		return true
	return false


func _hf_ai_perched(dist: float, toward: Vector2, os: int) -> void:
	if state_time < hf_ai_wait:
		return
	var opp_up: bool = opponent.is_standing()
	if os == S.DOWN or _hf_opp_on_table():
		in_strike = true
		var r := randf()
		if r < 0.3:
			in_move = -toward                       # moonsault
		elif r < 0.5:
			in_move = Vector2(-toward.y, toward.x)  # flying elbow
	elif opp_up:
		if dist < 1.5 and randf() < 0.5:
			in_grapple = true                       # hop down before getting knocked off
		else:
			in_strike = true
			if randf() < 0.5:
				in_move = toward                    # missile dropkick (else crossbody)
	elif state_time > 2.5:
		in_run = true                               # nothing to dive at: climb down


# --- poses -------------------------------------------------------------------------------

func _pose_hf_climb() -> void:
	var p := clampf(state_time / maxf(hf_time, 0.01), 0.0, 1.0)
	r_limb = 18.0
	r_root = 18.0
	r_body = 14.0
	if hf_mode == "jump":
		var crouch := _hump(p, 0.0, 0.25)
		var air := _hump(p, 0.15, 0.9)
		var land := _hump(p, 0.8, 1.0)
		_stance(0.5 + 0.5 * crouch + 0.6 * land)
		pt_ll.x -= 0.7 * air
		pt_lr.x -= 0.5 * air
		pt_kn_l += 0.9 * air
		pt_kn_r += 1.0 * air
		pt_tor = Vector3(0.25 + 0.2 * crouch + 0.25 * land, 0.0, 0.0)
		pt_hd = Vector3(-0.2, 0.0, 0.0)
		pt_al = Vector3(lerpf(0.4, -1.8, air), 0.0, -0.6)
		pt_ar = Vector3(lerpf(0.4, -1.8, air), 0.0, 0.6)
		pt_el_l = Vector3(-0.4, 0.0, 0.0)
		pt_el_r = Vector3(-0.4, 0.0, 0.0)
		return
	# Backing up the turnbuckle facing the ring: the feet step up the ropes behind (one rung
	# per step, which matches the three rope heights), the hands go hand over hand along the
	# two top ropes, and let go for the last step to come up into the crouch.
	var s := p * 3.0
	var k := int(minf(s, 2.999))
	var lift := _hump(s - float(k), 0.0, 0.7)
	var left_steps := k % 2 == 0
	var side := 1.0 if left_steps else -1.0
	# standing leg's sole sits on the rope behind (local z -0.25), like the perch
	pt_root_pos = Vector3(0.0, 0.8 - 0.05 * lift, -0.05)
	pt_ll = Vector3(-0.15, 0.0, -0.2)
	pt_lr = Vector3(-0.15, 0.0, 0.2)
	pt_kn_l = 0.9
	pt_kn_r = 0.9
	if left_steps:
		pt_ll.x -= 1.0 * lift
		pt_kn_l += 1.2 * lift
	else:
		pt_lr.x -= 1.0 * lift
		pt_kn_r += 1.2 * lift
	pt_tor = Vector3(0.18 + 0.12 * lift, 0.1 * side * lift, 0.04 * side * lift)
	pt_hd = Vector3(-0.25, -0.05 * side * lift, 0.0)
	# balance arms (used for the top step)
	pt_al = Vector3(-0.7, 0.0, -0.95)
	pt_ar = Vector3(-0.7, 0.0, 0.95)
	pt_el_l = Vector3(-0.5, 0.0, 0.0)
	pt_el_r = Vector3(-0.5, 0.0, 0.0)
	var grip := 1.0 - _smooth(_seg(p, 0.6, 0.85))
	if hf_mode == "down":
		grip = _smooth(_seg(p, 0.1, 0.35))
	var rr := get_parent() as Node3D
	if grip > 0.0 and rr != null and hf_corner != Vector3.ZERO:
		var c := hf_corner
		var top := HF_PERCH_Y - 0.1  # top rope height (ring local)
		var lift_a := 0.15 * lift if left_steps else 0.0
		var lift_b := 0.0 if left_steps else 0.15 * lift
		var pa := Vector3(c.x * HF_CORNER_POST, top + lift_a, clampf(position.z + c.z * 0.12, -HF_CORNER_POST, HF_CORNER_POST))
		var pb := Vector3(clampf(position.x + c.x * 0.12, -HF_CORNER_POST, HF_CORNER_POST), top + lift_b, c.z * HF_CORNER_POST)
		_reach_pair(rr.to_global(pa), rr.to_global(pb), grip)


func _pose_hf_perched() -> void:
	# Crouched on the top turnbuckle with the balls of the feet on the two top ropes behind
	# (local (+-0.28, -0.05, -0.25) when facing the ring), arms out for balance; every few
	# seconds he rises up and throws both arms in the air to hype the crowd.
	var ac := anim_clock
	var b := sin(ac * 2.6)
	var sway := sin(ac * 1.7)
	var cyc := fmod(state_time, 2.6)
	var hype := _smooth(_seg(cyc, 0.35, 0.6)) * (1.0 - _smooth(_seg(cyc, 1.7, 2.0)))
	var pump := maxf(0.0, sin(ac * 9.0)) * hype
	pt_breath = b
	pt_root_pos = Vector3(0.0, lerpf(0.66, 0.8, hype) - 0.025 * pump, -0.05)
	var lx := lerpf(-0.45, -0.15, hype)
	var lz := lerpf(0.3, 0.2, hype)
	pt_ll = Vector3(lx, 0.0, -lz)
	pt_lr = Vector3(lx, 0.0, lz)
	pt_kn_l = lerpf(1.5, 0.9, hype) + 0.07 * pump
	pt_kn_r = pt_kn_l
	pt_tor = Vector3(lerpf(0.55, 0.05, hype) + 0.03 * b, 0.0, 0.05 * sway)
	pt_hd = Vector3(lerpf(-0.45, -0.3, hype), 0.45 * sin(ac * 0.9) * hype, -0.04 * sway)
	pt_al = Vector3(-0.5, 0.0, -0.9 - 0.1 * sway).lerp(Vector3(-2.75 + 0.25 * pump, 0.0, -0.45), hype)
	pt_ar = Vector3(-0.5, 0.0, 0.9 + 0.1 * sway).lerp(Vector3(-2.75 + 0.25 * pump, 0.0, 0.45), hype)
	pt_el_l = Vector3(-0.6, 0.0, 0.0).lerp(Vector3(-0.15 - 0.45 * pump, 0.0, 0.0), hype)
	pt_el_r = pt_el_l
	if is_special_ready():
		# SPECIAL lit: one arm thrown up to the crowd the whole time
		pt_ar = Vector3(-2.8 + 0.15 * sin(ac * 6.0), 0.0, 0.3)
		pt_el_r = Vector3(-0.2, 0.0, 0.0)
	r_limb = 12.0 + 6.0 * hype
	r_root = 14.0


func _pose_hf_corner_stun() -> void:
	# Slammed back into the turnbuckle, then slumped with the arms hooked over the ropes.
	var t := state_time
	var e := (t / 0.06) if t < 0.06 else exp(-(t - 0.06) * 6.0)
	# Standing 0.85 m in from the post, the two top ropes run past the shoulders in a V
	# behind: the upper arms are hooked back over them (elbows just outside, ~1.35 high) and
	# the forearms hang down outside the ropes; back resting on the pad, knees sagging.
	var ph := anim_clock * 2.8
	var sag := _smooth(_seg(t, 0.15, 0.6))
	_stance(0.4 + 0.12 * sag + 0.06 * sin(ph * 0.7))
	pt_ll.z = -0.24
	pt_lr.z = 0.24
	pt_tor = Vector3(lerpf(-0.3, -0.5, e) + 0.04 * sin(ph * 0.5), 0.08 * sin(ph * 0.5), 0.08 * sin(ph))
	pt_hd = Vector3(lerpf(0.35 + 0.1 * sag, -0.55, e) + 0.12 * sin(ph * 1.3), 0.15 * sin(ph * 0.6),
		0.22 * sin(ph + 1.0))
	pt_al = Vector3(-0.33 + 0.35 * e, 0.0, -1.1 - 0.2 * e)
	pt_ar = Vector3(-0.33 + 0.35 * e, 0.0, 1.1 + 0.2 * e)
	pt_el_l = Vector3(0.6 * (1.0 - e), 0.0, 0.4 * (1.0 - e))
	pt_el_r = Vector3(0.6 * (1.0 - e), 0.0, -0.4 * (1.0 - e))
	pt_root_pos.z = -0.15 - 0.08 * e
	r_body = 10.0 if t > 0.1 else 28.0
	r_limb = 12.0 if t > 0.1 else 24.0


## Upright -> half-twisting forward fall -> lying on the back (head toward the pose's +z).
func _hf_fall_q(u: float) -> Quaternion:
	var mid := _qe(PI * 0.5, -PI * 0.25)
	if u < 0.5:
		return Quaternion.IDENTITY.slerp(mid, _seg(u, 0.0, 0.5)).normalized()
	return mid.slerp(_qe(PI, -PI / 2), _seg(u, 0.5, 1.0)).normalized()


func _pose_hf_flail() -> void:
	var fl := sin(anim_clock * 13.0)
	var fl2 := sin(anim_clock * 10.0 + 1.3)
	pt_al = Vector3(-1.2 + 0.5 * fl, 0.0, -1.0 - 0.3 * fl2)
	pt_ar = Vector3(-1.2 - 0.5 * fl2, 0.0, 1.0 + 0.3 * fl)
	pt_el_l = Vector3(-0.5, 0.0, 0.0)
	pt_el_r = Vector3(-0.5, 0.0, 0.0)
	pt_ll = Vector3(-0.4 + 0.25 * fl, 0.0, -0.15)
	pt_lr = Vector3(-0.2 - 0.25 * fl2, 0.0, 0.15)
	pt_kn_l = 0.6 + 0.3 * fl2
	pt_kn_r = 0.4 + 0.3 * fl
	pt_tor = Vector3(0.1, 0.0, 0.0)
	pt_hd = Vector3(0.2, 0.0, 0.0)


func _pose_hf_perch_fall() -> void:
	pt_use_basis = true
	r_limb = 14.0
	r_body = 12.0
	var t := state_time
	var ac := anim_clock
	if hf_mode == "crotch" and t < 1.1:
		# Dropped straddling the corner: the pelvis slides back into the V where the two top
		# ropes meet and lands on them / the pad (crotch ~1.3 ring-local), thighs hooked over
		# the ropes, shins dangling outside. Doubled over, hands at the belt, knees knocking.
		var d := _smooth(_seg(t, 0.0, 0.2))
		var jolt := _hump(t, 0.17, 0.45)
		var sell := _smooth(_seg(t, 0.3, 0.6))
		throw_pose_q = _qe(0.0, 0.12 * d)
		throw_pose_y = lerpf(0.7, 1.13, d) - 0.06 * jolt
		pt_basis_off = Vector3(0.0, 0.0, -0.35 * d)
		var knock := 0.18 * maxf(0.0, sin(ac * 6.0)) * sell
		pt_ll = Vector3(-0.35, 0.0, -1.2 + knock)
		pt_lr = Vector3(-0.35, 0.0, 1.2 - knock)
		pt_kn_l = 0.7 + 0.15 * sin(ac * 5.0) * sell
		pt_kn_r = 0.7 + 0.15 * sin(ac * 5.0 + 1.5) * sell
		pt_tor = Vector3(0.2 + 0.45 * jolt + 0.5 * sell + 0.06 * sin(ac * 9.0) * sell, 0.0, 0.06 * sin(ac * 7.0))
		pt_hd = Vector3(-0.5 * jolt + 0.5 * sell, 0.0, 0.12 * sin(ac * 5.0))
		pt_al = Vector3(-1.6, 0.0, -0.9).lerp(Vector3(-0.35, 0.0, 0.3), sell)
		pt_ar = Vector3(-1.6, 0.0, 0.9).lerp(Vector3(-0.35, 0.0, -0.3), sell)
		pt_el_l = Vector3(-0.3, 0.0, 0.0).lerp(Vector3(-1.0, 0.0, 0.0), sell)
		pt_el_r = pt_el_l
		r_body = 22.0 if t < 0.4 else 12.0
		return
	var u := _seg(t, 1.1, 1.6) if hf_mode == "crotch" else _seg(t, 0.0, 0.55)
	throw_pose_q = _hf_fall_q(u)
	if hf_mode == "crotch":
		# slumps off the corner forward into the ring
		throw_pose_y = lerpf(1.13, LIE_Y, _ease_in(u))
		pt_basis_off = Vector3(0.0, 0.0, -0.35 * (1.0 - _smooth(u)))
	else:
		throw_pose_y = lerpf(0.88, LIE_Y, _ease_in(u))
	_pose_hf_flail()


## Flight keys [p, pelvis_y, orientation] for the dives that tumble (basis-posed).
func _hf_dive_keys(key: String) -> Array:
	match key:
		"backyard_splash":
			# springs up arched, then lays out flat face-down for most of the flight
			return [[0.0, 0.72, _qe(0.0, 0.35)], [0.2, 0.95, _qe(0.0, -0.2)], [0.45, 0.95, _qe(0.0, 1.05)],
				[0.75, 0.75, _qe(0.0, 1.4)], [1.0, 0.42, _qe(0.0, PI / 2)]]
		"moonsault", "springboard_moonsault":
			# turn the back to the target, then a 3/4 backflip onto the chest
			return [[0.0, 0.72, _qe(0.0, 0.3)], [0.12, 0.82, _qe(PI * 0.5, 0.15)], [0.25, 0.95, _qe(PI, -0.1)],
				[0.5, 0.9, _qe(PI, -0.6 * PI)], [0.75, 0.75, _qe(PI, -1.15 * PI)], [1.0, 0.42, _qe(PI, -1.5 * PI)]]
		"gutter_star":
			# leap forward, then a backward 3/4 flip onto the chest
			return [[0.0, 0.72, _qe(0.0, 0.35)], [0.2, 0.95, _qe(0.0, -0.2)], [0.45, 0.95, _qe(0.0, -0.75 * PI)],
				[0.7, 0.8, _qe(0.0, -1.25 * PI)], [1.0, 0.42, _qe(0.0, -1.5 * PI)]]
		"flying_elbow":
			# rolls onto the left side in the air (head toward local -x), so the bent left arm's
			# upper arm points straight down: elbow first. Settles onto the back on landing.
			return [[0.0, 0.72, _qe(0.0, 0.35)], [0.25, 0.95, _qe(0.0, -0.1)], [0.6, 0.85, _qe(0.0, 0.1, 0.38 * PI)],
				[1.0, 0.55, _qe(0.0, 0.0, PI / 2)]]
		"missile_dropkick":
			return [[0.0, 0.72, _qe(0.0, 0.35)], [0.25, 0.95, _qe(0.0, -0.3)], [0.55, 0.9, _qe(0.0, -1.35)],
				[1.0, LIE_Y + 0.03, _qe(0.0, -PI / 2)]]
		"crossbody":
			return [[0.0, 0.72, _qe(0.0, 0.35)], [0.3, 0.95, _qe(0.0, 0.5, 0.6)], [0.7, 1.0, _qe(0.0, 0.3, PI / 2)],
				[1.0, 1.0, _qe(0.0, 0.2, PI / 2)]]
	return [[0.0, STAND_Y, Quaternion.IDENTITY], [1.0, STAND_Y, Quaternion.IDENTITY]]


func _hf_sample(keys: Array, p: float) -> void:
	var i := 0
	while i < keys.size() - 2:
		var nk: Array = keys[i + 1]
		var np: float = nk[0]
		if p < np:
			break
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var pa: float = a[0]
	var pb: float = b[0]
	var u := _seg(p, pa, pb)
	if i == 0:
		u = _smooth(u)
	var ya: float = a[1]
	var yb: float = b[1]
	var qa: Quaternion = a[2]
	var qb: Quaternion = b[2]
	throw_pose_y = lerpf(ya, yb, u)
	throw_pose_q = qa.slerp(qb, u).normalized()


func _pose_hf_diving() -> void:
	if hf_move == "springboard_forearm" or hf_move == "corner_splash":
		_pose_hf_hop()
		return
	pt_use_basis = true
	r_limb = 16.0
	r_body = 14.0
	var keys := _hf_dive_keys(hf_move)
	var p := clampf(state_time / maxf(hf_time, 0.01), 0.0, 1.0)
	if not hf_landed:
		_hf_sample(keys, p)
		_hf_dive_limbs(p)
		return
	# Touched down: hold the impact, then settle / roll onto the back (or into the cover).
	var last: Array = keys[keys.size() - 1]
	var q0: Quaternion = last[2]
	var y0: float = last[1]
	var u := clampf((state_time - hf_time) / maxf(hf_land_time, 0.01), 0.0, 1.0)
	var q1 := _qe(hf_end_yaw, -PI / 2)
	var y1 := LIE_Y
	var w := _smooth(_seg(u, 0.35, 1.0))
	var wy := w
	if hf_move == "crossbody":
		w = _ease_in(_seg(u, 0.0, 0.8))
		wy = w
		if hf_result == "hit":
			q1 = _qe(0.0, 1.35)
			y1 = PIN_Y
	elif hf_result == "crash":
		wy = _smooth(_seg(u, 0.0, 0.2))  # nobody to land on: straight to the mat
	throw_pose_q = q0.slerp(q1, w).normalized()
	throw_pose_y = lerpf(y0, y1, wy)
	var fling := _hump(u, 0.0, 0.3)
	pt_al = Vector3(-0.4 - 0.6 * fling, 0.0, -1.3)
	pt_ar = Vector3(-0.4 - 0.6 * fling, 0.0, 1.3)
	pt_el_l = Vector3(-0.3, 0.0, 0.0)
	pt_el_r = Vector3(-0.3, 0.0, 0.0)
	pt_ll = Vector3(-0.3 * fling, 0.0, -0.25)
	pt_lr = Vector3(-0.5 * fling, 0.0, 0.25)
	pt_kn_l = 0.2 + 0.4 * fling
	pt_kn_r = 0.15 + 0.5 * fling
	pt_tor = Vector3(0.1, 0.0, 0.0)
	pt_hd = Vector3(0.3 * fling, 0.0, 0.0)
	r_limb = 12.0


## Limbs while flying (body orientation comes from the keys).
func _hf_dive_limbs(p: float) -> void:
	var launch := 1.0 - _smooth(_seg(p, 0.0, 0.18))  # still crouched on the turnbuckle
	pt_ll = Vector3(-1.1 * launch, 0.0, -0.1)
	pt_lr = Vector3(-1.0 * launch, 0.0, 0.1)
	pt_kn_l = 0.2 + 1.6 * launch
	pt_kn_r = 0.2 + 1.5 * launch
	pt_al = Vector3(lerpf(-2.6, 0.6, launch), 0.0, -0.5)
	pt_ar = Vector3(lerpf(-2.6, 0.6, launch), 0.0, 0.5)
	pt_el_l = Vector3(-0.2, 0.0, 0.0)
	pt_el_r = Vector3(-0.2, 0.0, 0.0)
	pt_tor = Vector3(0.3 * launch, 0.0, 0.0)
	pt_hd = Vector3(-0.3, 0.0, 0.0)
	match hf_move:
		"backyard_splash":
			# spread-eagle: arms straight out to the sides, legs straight and apart, flat
			var spread := _smooth(_seg(p, 0.25, 0.5))
			var sz := 1.5 + 0.08 * sin(anim_clock * 14.0) * spread  # arms flutter in the wind
			pt_al = pt_al.lerp(Vector3(-0.2, 0.0, -sz), spread)
			pt_ar = pt_ar.lerp(Vector3(-0.2, 0.0, sz), spread)
			pt_el_l.x = lerpf(-0.2, -0.05, spread)
			pt_el_r.x = pt_el_l.x
			pt_ll = pt_ll.lerp(Vector3(0.05, 0.0, -0.42), spread)
			pt_lr = pt_lr.lerp(Vector3(0.05, 0.0, 0.42), spread)
			pt_kn_l = lerpf(pt_kn_l, 0.12, spread)
			pt_kn_r = pt_kn_l
			pt_tor.x = lerpf(pt_tor.x, -0.1, spread)  # slight arch: chest leads
			pt_hd.x = lerpf(-0.3, -0.65, spread)
		"moonsault", "springboard_moonsault", "gutter_star":
			var tuck := _hump(p, 0.3, 0.85)
			var open := _smooth(_seg(p, 0.2, 0.4))
			var flat2 := _smooth(_seg(p, 0.85, 1.0))
			pt_ll.x -= 0.6 * tuck
			pt_lr.x -= 0.6 * tuck
			pt_kn_l += 1.0 * tuck
			pt_kn_r += 1.0 * tuck
			pt_al = pt_al.lerp(Vector3(-1.6, 0.0, -1.2), open).lerp(Vector3(-0.6, 0.0, -1.3), flat2)
			pt_ar = pt_ar.lerp(Vector3(-1.6, 0.0, 1.2), open).lerp(Vector3(-0.6, 0.0, 1.3), flat2)
			pt_hd.x = -0.4 * tuck
		"flying_elbow":
			# left upper arm out of the side (= straight down once rolled), forearm folded
			# across: the point of the elbow leads; the right arm reaches for the sky
			var cock := _smooth(_seg(p, 0.2, 0.5))
			var tuck := _smooth(_seg(p, 0.82, 1.0))  # folds in under the side as it drives in
			pt_al = pt_al.lerp(Vector3(0.0, 0.0, -1.5), cock).lerp(Vector3(-0.2, 0.0, -0.5), tuck)
			pt_el_l = pt_el_l.lerp(Vector3(-2.0, 0.0, 0.0), cock)
			pt_ar = pt_ar.lerp(Vector3(-0.3, 0.0, 1.55), cock)
			pt_el_r = pt_el_r.lerp(Vector3(-0.1, 0.0, 0.0), cock)
			pt_ll = pt_ll.lerp(Vector3(-0.6, 0.0, -0.1), cock)
			pt_lr = pt_lr.lerp(Vector3(-0.3, 0.0, 0.1), cock)
			pt_kn_l = lerpf(pt_kn_l, 1.0, cock)
			pt_kn_r = lerpf(pt_kn_r, 0.6, cock)
			pt_hd.x = lerpf(-0.3, 0.35, cock)
		"missile_dropkick":
			# both boots out together toward the target, arms flung back
			var kick := _smooth(_seg(p, 0.3, 0.55))
			pt_ll = pt_ll.lerp(Vector3(-0.35, 0.0, -0.05), kick)
			pt_lr = pt_lr.lerp(Vector3(-0.35, 0.0, 0.05), kick)
			pt_kn_l = lerpf(pt_kn_l, 0.05, kick)
			pt_kn_r = lerpf(pt_kn_r, 0.05, kick)
			pt_al = pt_al.lerp(Vector3(0.6, 0.0, -0.8), kick)
			pt_ar = pt_ar.lerp(Vector3(0.6, 0.0, 0.8), kick)
			pt_hd.x = lerpf(-0.3, 0.4, kick)
		"crossbody":
			var spread := _smooth(_seg(p, 0.2, 0.5))
			pt_al = pt_al.lerp(Vector3(-1.4, 0.0, -0.9), spread)
			pt_ar = pt_ar.lerp(Vector3(-1.4, 0.0, 0.9), spread)
			pt_ll = pt_ll.lerp(Vector3(-0.2, 0.0, -0.2), spread)
			pt_lr = pt_lr.lerp(Vector3(0.1, 0.0, 0.2), spread)
			pt_kn_l = lerpf(pt_kn_l, 0.4, spread)
			pt_kn_r = lerpf(pt_kn_r, 0.2, spread)


## Springboard forearm / corner splash: upright hops, feet under the body.
func _pose_hf_hop() -> void:
	var p := clampf(state_time / maxf(hf_time, 0.01), 0.0, 1.0)
	var lu := 0.0
	if hf_landed:
		lu = clampf((state_time - hf_time) / maxf(hf_land_time, 0.01), 0.0, 1.0)
	r_limb = 22.0
	r_body = 18.0
	r_root = 18.0
	if hf_move == "corner_splash":
		# chest-first leap into the corner, arms wide
		var lean := _smooth(_seg(p, 0.0, 0.4)) * (1.0 - _smooth(lu))
		_stance(0.4)
		pt_ll.x += 0.4 * lean
		pt_lr.x += 0.2 * lean
		pt_root_rot.x = 0.4 * lean
		pt_tor = Vector3(0.15 - 0.3 * _hump(lu, 0.0, 0.6), 0.0, 0.0)
		pt_hd = Vector3(-0.3, 0.0, 0.0)
		pt_al = Vector3(-1.3, 0.0, -1.25)
		pt_ar = Vector3(-1.3, 0.0, 1.25)
		pt_el_l = Vector3(-0.3, 0.0, 0.0)
		pt_el_r = Vector3(-0.3, 0.0, 0.0)
		return
	# springboard forearm: off the rope, knees tucked, forearm driven across
	var tuck := _smooth(_seg(p, 0.05, 0.3)) * (1.0 - _smooth(_seg(p, 0.75, 1.0)))
	_stance(0.6 + 0.4 * _hump(p, 0.0, 0.12) + 0.4 * _hump(lu, 0.0, 1.0))
	pt_ll.x -= 0.9 * tuck
	pt_lr.x -= 0.5 * tuck
	pt_kn_l += 1.2 * tuck
	pt_kn_r += 1.4 * tuck
	var strike := _smooth(_seg(p, 0.45, 0.8)) * (1.0 - _smooth(lu))
	pt_ar = Vector3(lerpf(-0.6, -1.55, strike), 0.0, lerpf(0.3, -0.2, strike))
	pt_el_r = Vector3(lerpf(-1.4, -1.75, strike), 0.0, 0.0)
	pt_al = Vector3(-0.8, 0.0, -0.6)
	pt_el_l = Vector3(-0.6, 0.0, 0.0)
	pt_tor = Vector3(0.25 + 0.15 * strike, -0.3 * strike, 0.0)
	pt_hd = Vector3(-0.2, 0.0, 0.0)

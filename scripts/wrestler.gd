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
	JUGGLED,      # popped up by a launcher: airborne, can be juggled, caught or lariated
	# --- movement (appended; see "# ---- movement & air tricks") ---
	ROLL }        # dodge roll (double-tap RUN): brief invulnerability

const RING_HALF := 3.5        # throws always land inside this
const ROPE_BOUNCE := 3.75     # runners rebound here (the ropes are at 4.15)
const RING_CLAMP := 3.8       # hard limit for any wrestler position
const WALK_SPEED := 3.0
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
# STYLE (driven by scripts/style.gd, a child Node; hype mirrors spirit)
var style_letters := 0         # 0..5 letters of B-R-A-W-L earned
var hype := 0.0                # 0..100 style meter (== spirit)
var combo_mult := 1            # current combo multiplier (x1..x8)
var combo_points := 0          # running (unbanked) combo points
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
var ai_skill := 0.3            # 0..1: reaction speed, reversal rate, pin kick-out strength
# Difficulty ramp: the CPU starts at CPU_SKILL_START and gets CPU_SKILL_STEP better per player
# win, up to CPU_SKILL_MAX. A static var (plus an Engine meta mirror), so it survives the
# scene reload between matches.
const CPU_SKILL_START := 0.3
const CPU_SKILL_STEP := 0.1
const CPU_SKILL_MAX := 0.8
const CPU_GRACE_TIME := 6.0      # CPU: strikes only (no grapples / whips / climbs / runs) this long
const CPU_PIN_HP := 45.0         # CPU only covers a human below this health
const COMBO_HIT_GAP := 1.6       # hits taken less than this apart count as one combo (damage scaling)
static var cpu_skill_level := CPU_SKILL_START
var ai_match_time := 0.0         # CPU: seconds of this match it has been thinking
var ai_streak := 0               # CPU: hits landed in its current flurry (backs off after 3)
var ai_streak_at := -10.0
var pin_freebie_left := true     # human: the first pin of the match auto-kicks out at 2
var pin_freebie_now := false     # human: the current pin is that first one
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
	if is_cpu:
		ai_skill = cpu_skill_for_match()  # difficulty ramp
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
# PS2-era (THUG2-style) street-clothes wrestlers: realistic ~7.5-head proportions built from
# SurfaceTool lofts (14-16 sided torsos/limbs, smooth per-vertex normals for Gouraud shading),
# loose cloth shells with geometric folds, and photo-like painted textures (128-512 px per
# part, mipmapped, LINEAR_WITH_MIPMAPS). Every texture is cached in a static var, so a
# rematch (or a second wrestler with the same look) never repaints.
#
# Pivot layout: pose_root sits at the pelvis (STAND_Y above the feet when standing)
# and hips is at pose_root's origin, so falls and throws rotate the body around
# the pelvis. Standing straight, the sneaker soles touch y = 0.
# Loft UVs: u wraps around the part (front/+z at u = 0.5, -x side at 0.25,
# +x side at 0.75, back seam at 0/1), v runs from the top ring (0) to the bottom (1).

const STAND_Y := 0.95  # pelvis height when standing
const LIE_Y := 0.21    # pelvis height when lying on the back (rotation.x = -PI/2)
const PIN_Y := 0.55    # pelvis height when lying across a downed opponent

static var _tex_cache := {}               # painted textures by look key (survive rematches)
static var _nz := PackedFloat32Array()    # 256x256 white-noise table for fabric grain


func _sat(c: Color, amt := 1.0) -> Color:
	return Color.from_hsv(c.h, clampf(c.s * amt, 0.0, 1.0), c.v, c.a)


## Per-vertex lit material; spec > 0 adds a soft per-vertex specular (skin, hair, chain, mask).
func _mat(c: Color, tex: Texture2D = null, spec := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if spec > 0.0:
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		m.roughness = rough
		m.metallic_specular = spec
	else:
		m.roughness = 1.0
		m.metallic_specular = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if tex != null:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.texture_repeat = true
	return m


## Fake sheen for skin and hair (works in Compatibility): an additive pass over the same
## mesh that brightens grazing edges (rim), more on upward-facing ones (sky / floodlight),
## plus a soft top-light glint. tint = sheen colour * strength.
const SHEEN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
uniform vec3 tint = vec3(0.08, 0.06, 0.045);
uniform float rim_pow = 2.6;
uniform float glint = 0.5;
void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, VIEW), 0.0, 1.0);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float up = 0.35 + 0.65 * clamp(nw.y * 0.5 + 0.5, 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_pow) * up;
	vec3 lv = normalize((VIEW_MATRIX * vec4(normalize(vec3(0.3, 1.0, 0.45)), 0.0)).xyz);
	float g = pow(clamp(dot(reflect(-VIEW, n), lv), 0.0, 1.0), 12.0) * glint;
	ALBEDO = tint * (rim + g);
}
"""
static var _sheen_shader: Shader


func _sheen(m: StandardMaterial3D, tint: Color, rim_pow := 2.6, glint := 0.5) -> StandardMaterial3D:
	if _sheen_shader == null:
		_sheen_shader = Shader.new()
		_sheen_shader.code = SHEEN_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _sheen_shader
	sm.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	sm.set_shader_parameter("rim_pow", rim_pow)
	sm.set_shader_parameter("glint", glint)
	m.next_pass = sm
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


func _ball(parent: Node3D, r: float, pos: Vector3, mat: Material, scl := Vector3.ONE, segs := 16) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = 8
	return _add_mesh(parent, s, pos, mat, scl)


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


## Builds a tapered tube. rings: Array of Vector4(y, radius_x, radius_z, z_offset), ordered top
## to bottom. Vertices sit half a segment off the axes so a face points forward (+z) and to
## each side. xo (optional, one per ring) shifts rings along x (slanted upper arms); fold > 0
## ripples the radius (cloth folds, stronger toward the bottom), seed varies the ripple.
func _loft_mesh(rings: Array, cap_top: bool, cap_bottom: bool, segs := 14, xo := PackedFloat32Array(),
		fold := 0.0, seed := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_r := rings.size()
	var first: Vector4 = rings[0]
	var last: Vector4 = rings[n_r - 1]
	var span: float = maxf(0.001, first.x - last.x)
	var step: float = TAU / float(segs)
	var has_x := xo.size() == n_r
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
		var t: float = (first.x - r.x) / span
		# keep v half a texel away from the edges so repeat-wrap doesn't bleed top<->bottom
		var v: float = 0.03 + 0.94 * t
		var ox: float = xo[j] if has_x else 0.0
		var fw: float = fold * smoothstep(0.2, 1.0, t)
		var pr := PackedVector3Array()
		var nr := PackedVector3Array()
		var ur := PackedVector2Array()
		for i in segs + 1:
			var a: float = -PI + (float(i) + 0.5) * step
			var sa := sin(a)
			var ca := cos(a)
			var f := 1.0
			var df := 0.0
			if fw > 0.0:
				var p1: float = 3.0 * a + seed + t * 2.1
				var p2: float = 5.0 * a + seed * 1.7 - t * 3.3
				f = 1.0 + fw * (0.6 * sin(p1) + 0.4 * sin(p2))
				df = fw * (1.8 * cos(p1) + 2.0 * cos(p2))
			pr.append(Vector3(sa * r.y * f + ox, r.x, ca * r.z * f + r.w))
			var hn := Vector3(sa / maxf(r.y, 0.001), 0.0, ca / maxf(r.z, 0.001)).normalized()
			if df != 0.0:
				var tg := Vector3(ca * r.y, 0.0, -sa * r.z).normalized()
				hn = (hn - tg * (df / f) * 0.8).normalized()
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
	var ox0: float = xo[0] if has_x else 0.0
	var ox1: float = xo[n_r - 1] if has_x else 0.0
	if cap_top:
		_cap(st, ring_p[0], ring_u[0], Vector3(ox0, first.x, first.w), Vector3.UP, 0.03)
	if cap_bottom:
		_cap(st, ring_p[n_r - 1], ring_u[n_r - 1], Vector3(ox1, last.x, last.w), Vector3.DOWN, 0.97)
	return st.commit()


func _loft(parent: Node3D, rings: Array, mat: Material, cap_top := true, cap_bottom := true, pos := Vector3.ZERO,
		segs := 14, xo := PackedFloat32Array(), fold := 0.0, seed := 0.0) -> MeshInstance3D:
	return _add_mesh(parent, _loft_mesh(rings, cap_top, cap_bottom, segs, xo, fold, seed), pos, mat)


## A rounded block (pillowy box) of roughly `size`, centred on pos: palms, fingers, pendant.
func _block(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var hx := size.x * 0.56
	var hz := size.z * 0.56
	var hy := size.y * 0.5
	var rings := [Vector4(hy, hx * 0.6, hz * 0.7, 0.0), Vector4(hy * 0.55, hx, hz, 0.0),
		Vector4(-hy * 0.55, hx, hz, 0.0), Vector4(-hy, hx * 0.6, hz * 0.7, 0.0)]
	return _add_mesh(parent, _loft_mesh(rings, true, true, 8), pos, mat)


## Scales the radii of loft rings (x by kx, z and the z offset by kz) and adds a margin.
func _bulked(rings: Array, kx: float, kz: float, add := 0.0) -> Array:
	var out: Array = []
	for r in rings:
		var v: Vector4 = r
		out.append(Vector4(v.x, v.y * kx + add, v.z * kz + add, v.w * kz))
	return out


## The loft ring (y, rx, rz, z offset) of `rings` at height y, interpolated.
func _ring_at(rings: Array, y: float) -> Vector4:
	for j in rings.size() - 1:
		var a: Vector4 = rings[j]
		var b: Vector4 = rings[j + 1]
		if y <= a.x and y >= b.x:
			return a.lerp(b, (a.x - y) / maxf(0.0001, a.x - b.x))
	var first: Vector4 = rings[0]
	var last: Vector4 = rings[rings.size() - 1]
	return first if y > first.x else last


## Appends a tube along pts (one radius per point, `sides`-sided, parallel-transported frame)
## to st; v runs v0 -> v1 along it, u around it.
func _tube_into(st: SurfaceTool, pts: PackedVector3Array, radii: PackedFloat32Array, sides: int, v0: float, v1: float) -> void:
	var n := pts.size()
	var acc := PackedFloat32Array([0.0])
	var total := 0.0
	for i in range(1, n):
		total += pts[i].distance_to(pts[i - 1])
		acc.append(total)
	var t0 := (pts[1] - pts[0]).normalized()
	var ref := Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT
	var nrm := t0.cross(ref).normalized()
	var prev_r := PackedVector3Array()
	var prev_n := PackedVector3Array()
	var prev_u := PackedVector2Array()
	for i in n:
		var tg: Vector3
		if i == 0:
			tg = pts[1] - pts[0]
		elif i == n - 1:
			tg = pts[i] - pts[i - 1]
		else:
			tg = pts[i + 1] - pts[i - 1]
		tg = tg.normalized()
		nrm = (nrm - tg * nrm.dot(tg)).normalized()
		var bn := tg.cross(nrm)
		var v := lerpf(v0, v1, acc[i] / maxf(total, 0.0001))
		var rr := PackedVector3Array()
		var rn := PackedVector3Array()
		var ru := PackedVector2Array()
		for k in sides + 1:
			var a := TAU * float(k) / float(sides)
			var d := nrm * cos(a) + bn * sin(a)
			rr.append(pts[i] + d * radii[i])
			rn.append(d)
			ru.append(Vector2(float(k) / float(sides), v))
		if i > 0:
			for k in sides:
				_tri(st, prev_r[k], prev_r[k + 1], rr[k + 1], prev_n[k], prev_n[k + 1], rn[k + 1], prev_u[k], prev_u[k + 1], ru[k + 1])
				_tri(st, prev_r[k], rr[k + 1], rr[k], prev_n[k], rn[k + 1], rn[k], prev_u[k], ru[k + 1], ru[k])
		prev_r = rr
		prev_n = rn
		prev_u = ru


## A curved patch on a loft surface (not a full ring): angle a0..a1 around it (0 = front) maps
## to u, y_top..y_bot to v; it sits `gap` outside the rings. bump > 0 moulds a nose (masks).
func _patch_mesh(rings: Array, a0: float, a1: float, y_top: float, y_bot: float, gap: float,
		cols := 14, rows := 12, bump := 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	var nrs: Array = []
	var uvs: Array = []
	for j in rows + 1:
		var v := float(j) / float(rows)
		var y := lerpf(y_top, y_bot, v)
		var rg := _ring_at(rings, y)
		var prow := PackedVector3Array()
		var nrow := PackedVector3Array()
		var urow := PackedVector2Array()
		for i in cols + 1:
			var u := float(i) / float(cols)
			var a := lerpf(a0, a1, u)
			var rx := rg.y + gap
			var rz := rg.z + gap
			var p := Vector3(sin(a) * rx, y, cos(a) * rz + rg.w)
			if bump > 0.0:
				p.z += bump * exp(-pow(a / 0.24, 2.0) - pow((y - 0.093) / 0.026, 2.0))   # nose
				p.z += bump * 0.3 * exp(-pow(a / 0.6, 2.0) - pow((y - 0.142) / 0.02, 2.0))  # brow
				for sg in [-1.0, 1.0]:
					var ea: float = sg
					var brow := 0.6 * exp(-pow((a - 0.4 * ea) / 0.26, 2.0) - pow((y - 0.152) / 0.016, 2.0))
					var cheek := 0.55 * exp(-pow((a - 0.62 * ea) / 0.26, 2.0) - pow((y - 0.082) / 0.024, 2.0))
					var bulge := (brow + cheek) * bump
					p.x += sin(a) * bulge
					p.z += cos(a) * bulge
				p.z += bump * 0.4 * exp(-pow(a / 0.35, 2.0) - pow((y - 0.028) / 0.02, 2.0))   # chin
			prow.append(p)
			nrow.append(Vector3(sin(a) / rx, 0.0, cos(a) / rz).normalized())
			urow.append(Vector2(u, 0.02 + 0.96 * v))
		pts.append(prow)
		nrs.append(nrow)
		uvs.append(urow)
	if bump > 0.0:
		# moulded: shade the bulges with normals taken from the displaced grid
		for j in rows + 1:
			var nrow: PackedVector3Array = nrs[j]
			var pc: PackedVector3Array = pts[j]
			var pu: PackedVector3Array = pts[maxi(j - 1, 0)]
			var pd: PackedVector3Array = pts[mini(j + 1, rows)]
			for i in cols + 1:
				var du: Vector3 = pc[mini(i + 1, cols)] - pc[maxi(i - 1, 0)]
				var dv: Vector3 = pd[i] - pu[i]
				var n := dv.cross(du).normalized()
				if n.dot(nrow[i]) < 0.0:
					n = -n
				nrow[i] = n
			nrs[j] = nrow
	for j in rows:
		var p0: PackedVector3Array = pts[j]
		var p1: PackedVector3Array = pts[j + 1]
		var n0: PackedVector3Array = nrs[j]
		var n1: PackedVector3Array = nrs[j + 1]
		var u0: PackedVector2Array = uvs[j]
		var u1: PackedVector2Array = uvs[j + 1]
		for i in cols:
			_tri(st, p0[i], p0[i + 1], p1[i + 1], n0[i], n0[i + 1], n1[i + 1], u0[i], u0[i + 1], u1[i + 1])
			_tri(st, p0[i], p1[i + 1], p1[i], n0[i], n1[i + 1], n1[i], u0[i], u1[i + 1], u1[i])
	return st.commit()


# --- painted textures ------------------------------------------------------------------
# Wrap textures: column w/2 is the front centre (u = 0.5); -x side at w/4, +x side at 3w/4,
# back seam at the edges. Parts are painted once at their final size (soft dabs, strokes,
# polygons), then _cloth_pass multiplies broad ambient / fold shading and a fabric grain in
# one pass over the raw bytes, and _done mipmaps the result.

func _tex(key: String, fn: Callable) -> Texture2D:
	if _tex_cache.has(key):
		var t: Texture2D = _tex_cache[key]
		return t
	var made: Texture2D = fn.call()
	_tex_cache[key] = made
	return made


func _nz_init() -> void:
	if _nz.size() > 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 7331
	_nz.resize(65536)
	for i in 65536:
		_nz[i] = rng.randf()


func _hash01(k: float) -> float:
	var v := sin(k * 12.9898 + 4.1414) * 43758.5453
	return v - floor(v)


func _new_img(w: int, h: int, c: Color) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _done(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Soft elliptical dab in pixels; the outer `soft` fraction of the radius feathers out.
func _dab(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color, a: float, soft := 0.6) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := maxi(0, int(floor(cx - rx)))
	var x1 := mini(w - 1, int(ceil(cx + rx)))
	var y0 := maxi(0, int(floor(cy - ry)))
	var y1 := mini(h - 1, int(ceil(cy + ry)))
	for y in range(y0, y1 + 1):
		var dy := (float(y) + 0.5 - cy) / ry
		for x in range(x0, x1 + 1):
			var dx := (float(x) + 0.5 - cx) / rx
			var d := sqrt(dx * dx + dy * dy)
			if d >= 1.0:
				continue
			var k := a * (1.0 - smoothstep(1.0 - soft, 1.0, d))
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, k))


## Soft polyline of radius r (pixels).
func _lines(img: Image, pts: PackedVector2Array, r: float, c: Color, a: float, soft := 0.5) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var lx := pts[0].x
	var ly := pts[0].y
	var hx := lx
	var hy := ly
	for p in pts:
		lx = minf(lx, p.x)
		ly = minf(ly, p.y)
		hx = maxf(hx, p.x)
		hy = maxf(hy, p.y)
	var ns := pts.size()
	for y in range(maxi(0, int(floor(ly - r))), mini(h - 1, int(ceil(hy + r))) + 1):
		for x in range(maxi(0, int(floor(lx - r))), mini(w - 1, int(ceil(hx + r))) + 1):
			var q := Vector2(float(x) + 0.5, float(y) + 0.5)
			var dmin := 1e9
			if ns == 1:
				dmin = q.distance_to(pts[0])
			for i in ns - 1:
				var p0 := pts[i]
				var ab := pts[i + 1] - p0
				var t := clampf((q - p0).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
				dmin = minf(dmin, q.distance_to(p0 + ab * t))
			if dmin >= r:
				continue
			var k := a * (1.0 - smoothstep(r * (1.0 - soft), r, dmin))
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, k))


func _inside(pts: PackedVector2Array, q: Vector2) -> bool:
	var inside := false
	var n := pts.size()
	var j := n - 1
	for i in n:
		var pi := pts[i]
		var pj := pts[j]
		if (pi.y > q.y) != (pj.y > q.y):
			var xc := pj.x + (q.y - pj.y) / (pi.y - pj.y) * (pj.x - pi.x)
			if q.x < xc:
				inside = not inside
		j = i
	return inside


## Filled polygon (even-odd), 2x2 supersampled edges.
func _poly(img: Image, pts: PackedVector2Array, c: Color, a: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var lx := pts[0].x
	var ly := pts[0].y
	var hx := lx
	var hy := ly
	for p in pts:
		lx = minf(lx, p.x)
		ly = minf(ly, p.y)
		hx = maxf(hx, p.x)
		hy = maxf(hy, p.y)
	for y in range(maxi(0, int(floor(ly))), mini(h - 1, int(ceil(hy))) + 1):
		for x in range(maxi(0, int(floor(lx))), mini(w - 1, int(ceil(hx))) + 1):
			var cov := 0.0
			for sy in 2:
				for sx in 2:
					if _inside(pts, Vector2(float(x) + 0.25 + 0.5 * sx, float(y) + 0.25 + 0.5 * sy)):
						cov += 0.25
			if cov > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, a * cov))


## A cloth fold: a soft dark crease along p0 -> p1 with a lit ridge beside it.
func _fold(img: Image, p0: Vector2, p1: Vector2, wd: float, dark: Color, light: Color, a: float) -> void:
	var dir := (p1 - p0).normalized()
	var perp := Vector2(-dir.y, dir.x) * wd * 1.1
	_lines(img, PackedVector2Array([p0 + perp, p1 + perp]), wd * 0.8, light, a * 0.55, 0.9)
	_lines(img, PackedVector2Array([p0, p1]), wd, dark, a, 0.9)


func _arc_pts(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := deg_to_rad(lerpf(a0, a1, float(i) / float(n)))
		out.append(Vector2(cx + rx * cos(t), cy + ry * sin(t)))
	return out


## Stroke-font glyphs in a unit box (y down): Array of polylines.
func _glyph(ch: String) -> Array:
	match ch:
		"C":
			return [_arc_pts(0.55, 0.5, 0.47, 0.5, 40.0, 320.0, 12)]
		"2":
			var p := _arc_pts(0.5, 0.3, 0.42, 0.3, 200.0, 380.0, 9)
			p.append(Vector2(0.06, 1.0))
			p.append(Vector2(0.96, 1.0))
			return [p]
		"P", "R":
			var p := PackedVector2Array([Vector2(0.1, 1.0), Vector2(0.1, 0.0), Vector2(0.5, 0.0)])
			p.append_array(_arc_pts(0.5, 0.27, 0.42, 0.27, 270.0, 450.0, 8))
			p.append(Vector2(0.1, 0.54))
			if ch == "R":
				return [p, PackedVector2Array([Vector2(0.45, 0.54), Vector2(0.92, 1.0)])]
			return [p]
		"E":
			return [PackedVector2Array([Vector2(0.9, 0.0), Vector2(0.1, 0.0), Vector2(0.1, 1.0), Vector2(0.9, 1.0)]),
				PackedVector2Array([Vector2(0.1, 0.5), Vector2(0.72, 0.5)])]
		"L":
			return [PackedVector2Array([Vector2(0.12, 0.0), Vector2(0.12, 1.0), Vector2(0.9, 1.0)])]
		"I":
			return [PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 1.0)]),
				PackedVector2Array([Vector2(0.22, 0.0), Vector2(0.78, 0.0)]),
				PackedVector2Array([Vector2(0.22, 1.0), Vector2(0.78, 1.0)])]
		"G":
			var p := _arc_pts(0.52, 0.5, 0.46, 0.5, 315.0, 30.0, 12)
			p.append(Vector2(0.92, 0.56))
			p.append(Vector2(0.58, 0.56))
			return [p]
		"O":
			return [_arc_pts(0.5, 0.5, 0.45, 0.5, 0.0, 360.0, 16)]
		"!":
			return [PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 0.6)]),
				PackedVector2Array([Vector2(0.5, 0.92), Vector2(0.5, 0.93)])]
	return []


## Stroke text centred on cx, top at `top`, letters `hgt` px tall; a dark outline first.
func _text(img: Image, s: String, cx: float, top: float, hgt: float, r: float, ink: Color, outline: Color) -> void:
	var gw := hgt * 0.7
	var sp := hgt * 0.24
	var n := s.length()
	var x0 := cx - (n * gw + (n - 1) * sp) * 0.5
	for pass_i in 2:
		for k in n:
			for pl in _glyph(s.substr(k, 1)):
				var src: PackedVector2Array = pl
				var pts := PackedVector2Array()
				for q in src:
					pts.append(Vector2(x0 + k * (gw + sp) + q.x * gw, top + q.y * hgt))
				if pass_i == 0:
					_lines(img, pts, r + 2.2, outline, 1.0, 0.25)
				else:
					_lines(img, pts, r, ink, 1.0, 0.3)


## One pass over the raw bytes: broad ambient / fold shading (mode) times a fabric grain.
## mode: "torso" | "limb" | "skirt" | "head" | "foot" | "plain" | "none".
## grain: "cotton" | "denim" (twill, slubs, fades) | "fleece" | "skin" | "hair" | "none".
## add = additive speckle in 0..255 units (heathered black cotton).
func _cloth_pass(img: Image, mode: String, grain: String, add := 0.0, seed := 0) -> void:
	_nz_init()
	var w := img.get_width()
	var h := img.get_height()
	var side := PackedFloat32Array()
	side.resize(w)
	var colk := PackedFloat32Array()
	colk.resize(w)
	for x in w:
		var u := (float(x) + 0.5) / float(w)
		var sd := 1.0 - absf(cos(TAU * u))
		side[x] = sd
		var ck := 1.0 - 0.1 * sd * sd
		match mode:
			"head":
				ck = 1.0 - 0.1 * smoothstep(0.2, 0.42, absf(u - 0.5))
			"foot":
				ck = 1.0 - 0.32 * (1.0 - smoothstep(0.05, 0.2, minf(u, 1.0 - u)))
			"none":
				ck = 1.0
		colk[x] = ck
	var rowk := PackedFloat32Array()
	rowk.resize(h)
	var pitk := PackedFloat32Array()
	pitk.resize(h)
	for y in h:
		var v := (float(y) + 0.5) / float(h)
		var rk := 1.0
		var pk := 0.0
		match mode:
			"torso":
				rk = 1.0 + 0.1 * (1.0 - smoothstep(0.02, 0.24, v)) - 0.06 * smoothstep(0.85, 1.0, v)
				pk = 0.28 * smoothstep(0.1, 0.2, v) * (1.0 - smoothstep(0.28, 0.5, v))
			"limb":
				rk = 1.0 - 0.14 * smoothstep(0.82, 1.0, v) - 0.1 * (1.0 - smoothstep(0.0, 0.15, v))
			"skirt":
				rk = 1.0 - 0.16 * smoothstep(0.5, 1.0, v)
			"head":
				rk = 1.0 - 0.32 * smoothstep(0.86, 0.985, v)
		rowk[y] = rk
		pitk[y] = pk
	var g := 0
	match grain:
		"cotton":
			g = 1
		"denim":
			g = 2
		"fleece":
			g = 3
		"skin":
			g = 4
		"hair":
			g = 5
	var bl := Image.create_empty(16, 16, false, Image.FORMAT_L8)
	for by in 16:
		for bx in 16:
			var nv: float = _nz[((by + seed * 3) & 255) * 256 + ((bx * 5 + seed * 17) & 255)]
			bl.set_pixel(bx, by, Color(nv, nv, nv))
	bl.resize(w, h, Image.INTERPOLATE_CUBIC)
	var bd := bl.get_data()
	var d := img.get_data()
	var i := 0
	for y in h:
		var rk: float = rowk[y]
		var pk: float = pitk[y]
		var ny := ((y + seed * 31) & 255) << 8
		for x in w:
			var f: float = rk * colk[x] * (1.0 - pk * side[x])
			var n: float = _nz[ny | ((x + seed * 7) & 255)] - 0.5
			var b: float = float(bd[y * w + x]) / 255.0 - 0.5
			var ad: float = n * add
			match g:
				1:
					f *= 1.0 + n * 0.08 + 0.025 * float((x & 1) * 2 - 1)
				2:
					var tw := 0.06 if ((x + y) & 3) < 2 else -0.06
					f *= 1.0 + n * 0.07 + tw + 0.2 * b + 0.08 * (_nz[(x * 13 + seed) & 65535] - 0.5)
					ad += b * add * 2.0
				3:
					f *= 1.0 + n * 0.06 + 0.1 * b
				4:
					f *= 1.0 + n * 0.035 + 0.08 * b
				5:
					f *= 1.0 + n * 0.12
			d[i] = clampi(int(d[i] * f + ad), 0, 255)
			d[i + 1] = clampi(int(d[i + 1] * f + ad), 0, 255)
			d[i + 2] = clampi(int(d[i + 2] * f + ad), 0, 255)
			i += 4
	img.set_data(w, h, false, Image.FORMAT_RGBA8, d)


## Warm skin shadow / highlight (deep browns on dark skin, never grey).
func _skin_shade(skin: Color, amt: float) -> Color:
	return Color(skin.r * (1.0 - amt * 1.0), skin.g * (1.0 - amt * 1.18), skin.b * (1.0 - amt * 1.3))


func _skin_light(skin: Color, amt: float) -> Color:
	return skin.lerp(Color(1.0, 0.8, 0.62), amt)


# --- cloth & body shapes (metres) ------------------------------------------------------
# Oversized tee / hoodie shells (torso space, before bulk): boxy, hanging straight from a
# dropped shoulder line. A short "skirt" piece on the hips carries the lower hem, so the
# torso can lean without the hem lifting off the jeans.
const TEE := [
	Vector4(0.578, 0.07, 0.068, -0.01), Vector4(0.57, 0.1, 0.09, -0.012), Vector4(0.552, 0.16, 0.115, -0.012),
	Vector4(0.525, 0.212, 0.138, -0.01), Vector4(0.49, 0.236, 0.15, -0.005), Vector4(0.42, 0.242, 0.158, 0.004),
	Vector4(0.32, 0.236, 0.158, 0.008), Vector4(0.2, 0.23, 0.154, 0.006), Vector4(0.1, 0.228, 0.152, 0.004),
	Vector4(0.04, 0.226, 0.15, 0.002)]
const HOODIE := [
	Vector4(0.585, 0.075, 0.075, -0.012), Vector4(0.572, 0.11, 0.1, -0.014), Vector4(0.552, 0.17, 0.125, -0.014),
	Vector4(0.525, 0.218, 0.145, -0.01), Vector4(0.49, 0.238, 0.156, -0.004), Vector4(0.42, 0.244, 0.164, 0.004),
	Vector4(0.32, 0.238, 0.164, 0.008), Vector4(0.2, 0.232, 0.16, 0.008), Vector4(0.1, 0.23, 0.158, 0.006),
	Vector4(0.04, 0.228, 0.156, 0.004)]
# Jeans waist (hips space): hidden under the tee down to the belt, then the seat and crotch.
const WAIST := [
	Vector4(0.11, 0.185, 0.125, 0.0), Vector4(0.0, 0.2, 0.135, 0.0), Vector4(-0.035, 0.205, 0.138, 0.0),
	Vector4(-0.08, 0.212, 0.142, 0.0), Vector4(-0.14, 0.2, 0.136, -0.004), Vector4(-0.2, 0.15, 0.112, -0.004),
	Vector4(-0.235, 0.08, 0.07, -0.004)]
# Head (head-geometry space, metres): chin bottom at y 0, crown at 0.245; ~0.16 wide.
const HEAD_TOP := 0.245
const HEAD := [
	Vector4(0.245, 0.018, 0.022, -0.012), Vector4(0.238, 0.05, 0.06, -0.012), Vector4(0.222, 0.068, 0.085, -0.01),
	Vector4(0.195, 0.077, 0.098, -0.008), Vector4(0.165, 0.08, 0.102, -0.005), Vector4(0.142, 0.08, 0.103, -0.003),
	Vector4(0.125, 0.078, 0.099, -0.002), Vector4(0.105, 0.076, 0.099, 0.0), Vector4(0.08, 0.071, 0.096, 0.002),
	Vector4(0.055, 0.064, 0.092, 0.004), Vector4(0.032, 0.054, 0.083, 0.008), Vector4(0.012, 0.04, 0.065, 0.016),
	Vector4(0.0, 0.022, 0.04, 0.022)]
# Hair cap over the scalp: the ellipses slide back as they go down, so the front edge stays
# at the hairline (inside the forehead below it) while the back covers the head to the nape.
const HAIR_CAP := [
	Vector4(0.255, 0.018, 0.022, -0.012), Vector4(0.248, 0.053, 0.063, -0.012), Vector4(0.232, 0.073, 0.089, -0.013),
	Vector4(0.205, 0.085, 0.105, -0.016), Vector4(0.175, 0.089, 0.109, -0.024), Vector4(0.14, 0.088, 0.107, -0.032),
	Vector4(0.1, 0.084, 0.101, -0.036), Vector4(0.06, 0.073, 0.089, -0.036), Vector4(0.035, 0.06, 0.075, -0.034)]


func _trow(y: float, top: float, bot: float, h: int) -> float:
	return (0.03 + 0.94 * (top - y) / (top - bot)) * float(h)


# --- tee -----------------------------------------------------------------------------

func _tee_tex(base: Color) -> ImageTexture:
	# 256x256 wrap over TEE (y 0.578 .. 0.04): collar rib, seams, drape folds, hem bunching.
	var img := _new_img(256, 256, base)
	var dk := base.darkened(0.7)
	var lt := base.lightened(0.16)
	var rc := int(_trow(0.566, 0.578, 0.04, 256))
	# broad soft fold shading first: lit chest and shoulder blades, sagging shade under them,
	# dark armpits and a darker, heavier hem
	var sl := base.lightened(0.22)
	var sd := base.darkened(0.6)
	_dab(img, 128, 66, 72, 46, sl, 0.55, 1.0)
	_dab(img, 0, 60, 56, 40, sl, 0.45, 1.0)
	_dab(img, 256, 60, 56, 40, sl, 0.45, 1.0)
	_dab(img, 128 - 30, 150, 34, 70, sl, 0.25, 1.0)
	_dab(img, 128 + 34, 170, 30, 60, sd, 0.35, 1.0)
	for sx in [64.0, 192.0]:
		var c: float = sx
		_dab(img, c, 78, 22, 34, sd, 0.75, 1.0)          # armpits
		_dab(img, c, 170, 18, 80, sd, 0.3, 1.0)          # sides
	img.fill_rect(Rect2i(0, 0, 256, rc), base.darkened(0.25))
	for x in range(0, 256, 2):
		img.fill_rect(Rect2i(x, 0, 1, rc), base.lightened(0.04))
	_lines(img, PackedVector2Array([Vector2(0, rc + 1.5), Vector2(256, rc + 1.5)]), 0.9, lt, 0.5)
	for sx in [64.0, 192.0]:
		var c: float = sx
		_lines(img, PackedVector2Array([Vector2(c, 30), Vector2(c + 1.0, 256)]), 1.0, dk, 0.55)
	for sg in [-1.0, 1.0]:
		var s: float = sg
		# shoulder -> armpit drape, front and back
		_fold(img, Vector2(128 + 36 * s, 16), Vector2(128 + 60 * s, 66), 3.0, dk, lt, 0.55)
		_fold(img, Vector2(128 + 50 * s, 22), Vector2(128 + 63 * s, 50), 2.5, dk, lt, 0.45)
		var bx := 0.0 if s < 0.0 else 256.0
		_fold(img, Vector2(bx - 34 * s, 16), Vector2(bx - 60 * s, 66), 3.0, dk, lt, 0.5)
		# armpit radial folds
		_fold(img, Vector2(128 + 64 * s, 68), Vector2(128 + 40 * s, 96), 2.5, dk, lt, 0.5)
		_fold(img, Vector2(128 + 64 * s, 74), Vector2(128 + 46 * s, 116), 2.5, dk, lt, 0.45)
		_fold(img, Vector2(bx - 64 * s, 70), Vector2(bx - 42 * s, 100), 2.5, dk, lt, 0.45)
	# long vertical drape folds down to the hem
	var offs := [-56.0, -30.0, -8.0, 16.0, 38.0, 58.0]
	for k in offs.size():
		var o: float = offs[k]
		_fold(img, Vector2(128 + o, 118 + 22 * _hash01(k * 1.7)), Vector2(128 + o + 5.0 * (_hash01(k * 2.3) - 0.5), 256), 3.4, dk, lt, 0.42)
	for bxo in [16.0, 42.0, 214.0, 240.0]:
		var c: float = bxo
		_fold(img, Vector2(c, 110), Vector2(c + 3.0, 256), 3.0, dk, lt, 0.4)
	for k in 9:
		var x := 10.0 + k * 28.0
		_fold(img, Vector2(x, 238), Vector2(x + 16, 231), 2.0, dk, lt, 0.35)
	_cloth_pass(img, "torso", "cotton", 9.0, 1)
	return _done(img)


func _skirt_tex(base: Color, hoodie: bool) -> ImageTexture:
	# 256x64: the hem piece on the hips (y 0.17 .. 0.0, hoodie .. -0.045 with a ribbed band).
	var img := _new_img(256, 64, base)
	var dk := base.darkened(0.7) if not hoodie else base.darkened(0.35)
	var lt := base.lightened(0.16) if not hoodie else base.lightened(0.12)
	var offs := [-56.0, -30.0, -8.0, 16.0, 38.0, 58.0]
	for k in offs.size():
		var o: float = offs[k]
		_fold(img, Vector2(128 + o, 0), Vector2(128 + o + 3.0, 50), 3.0, dk, lt, 0.4)
	for bxo in [16.0, 42.0, 214.0, 240.0]:
		var c: float = bxo
		_fold(img, Vector2(c, 0), Vector2(c + 2.0, 50), 3.0, dk, lt, 0.38)
	if hoodie:
		var rb := int(_trow(0.0, 0.17, -0.045, 64))
		img.fill_rect(Rect2i(0, rb, 256, 64 - rb), base.darkened(0.12))
		for x in range(0, 256, 3):
			img.fill_rect(Rect2i(x, rb, 1, 64 - rb), base.darkened(0.28))
		for k in 10:
			var x := 6.0 + k * 25.0
			_fold(img, Vector2(x, rb - 9), Vector2(x + 12, rb - 3), 2.0, dk, lt, 0.45)   # blousing over the band
	else:
		for y in range(20, 64):
			var k := 0.4 * smoothstep(20.0, 60.0, float(y))
			for x in 256:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(base.darkened(0.6), k))
		img.fill_rect(Rect2i(0, 55, 256, 9), base.darkened(0.3))
		_lines(img, PackedVector2Array([Vector2(0, 54), Vector2(256, 54)]), 0.7, lt, 0.45)
		for k in 9:
			var x := 4.0 + k * 28.0
			_fold(img, Vector2(x, 44), Vector2(x + 14, 38), 2.0, dk, lt, 0.35)
	_cloth_pass(img, "skirt", "fleece" if hoodie else "cotton", 4.0 if hoodie else 9.0, 2)
	return _done(img)


func _sleeve_tex(base: Color, kind: String) -> ImageTexture:
	# 128x64 sleeve: "tee" (short, hemmed), "hood_up" (upper, elbow bunching), "hood_lo"
	# (forearm, ribbed cuff), "hood_fore" (forearm without the cuff), "cuff" (ribbed cuff).
	var img := _new_img(128, 64, base)
	var hood := kind != "tee"
	var dk := base.darkened(0.35) if hood else base.darkened(0.7)
	var lt := base.lightened(0.12) if hood else base.lightened(0.16)
	match kind:
		"tee":
			_fold(img, Vector2(40, 6), Vector2(54, 44), 2.6, dk, lt, 0.5)
			_fold(img, Vector2(82, 4), Vector2(72, 40), 2.6, dk, lt, 0.5)
			_fold(img, Vector2(104, 14), Vector2(114, 46), 2.4, dk, lt, 0.45)
			_fold(img, Vector2(12, 12), Vector2(22, 46), 2.4, dk, lt, 0.45)
			img.fill_rect(Rect2i(0, 52, 128, 12), base.darkened(0.22))
			_lines(img, PackedVector2Array([Vector2(0, 51), Vector2(128, 51)]), 0.7, lt, 0.45)
		"hood_up":
			for k in 4:
				var x := 10.0 + k * 31.0
				_fold(img, Vector2(x, 4), Vector2(x + 6, 40), 2.6, dk, lt, 0.4)
			for k in 6:
				var x := 4.0 + k * 21.0
				_fold(img, Vector2(x, 54), Vector2(x + 14, 47), 2.2, dk, lt, 0.5)
		"hood_lo":
			for k in 6:
				var x := 4.0 + k * 21.0
				_fold(img, Vector2(x, 8), Vector2(x + 13, 15), 2.2, dk, lt, 0.5)
			_fold(img, Vector2(60, 16), Vector2(66, 44), 2.4, dk, lt, 0.4)
			img.fill_rect(Rect2i(0, 49, 128, 15), base.darkened(0.12))
			for x in range(0, 128, 3):
				img.fill_rect(Rect2i(x, 49, 1, 15), base.darkened(0.3))
		"hood_fore":
			for k in 6:
				var x := 4.0 + k * 21.0
				_fold(img, Vector2(x, 6), Vector2(x + 13, 14), 2.2, dk, lt, 0.5)        # bunching out of the elbow
			_fold(img, Vector2(60, 16), Vector2(66, 44), 2.4, dk, lt, 0.4)
			_fold(img, Vector2(20, 20), Vector2(24, 46), 2.2, dk, lt, 0.35)
			for k in 7:
				var x := 2.0 + k * 18.0
				_fold(img, Vector2(x, 58), Vector2(x + 6, 46), 2.0, dk, lt, 0.45)        # blousing over the cuff
		"cuff":
			for x in range(0, 128, 3):
				img.fill_rect(Rect2i(x, 0, 1, 64), base.darkened(0.22))
			img.fill_rect(Rect2i(0, 56, 128, 8), base.darkened(0.3))
	_cloth_pass(img, "limb", "fleece" if hood else "cotton", 4.0 if hood else 9.0, 3)
	return _done(img)


func _undershirt_tex() -> ImageTexture:
	# 128x32 over the hem ring (y 0.03 .. -0.016): hidden under the tee down to v ~0.6,
	# a shadow from the tee hem, rib texture, a stitched hem and a soft fold or two.
	var c := Color(0.84, 0.83, 0.8)
	var img := _new_img(128, 32, c)
	for x in range(0, 128, 2):
		img.fill_rect(Rect2i(x, 0, 1, 32), c.darkened(0.06))
	for y in 20:
		img.fill_rect(Rect2i(0, y, 128, 1), c.darkened(0.55 * (1.0 - smoothstep(10.0, 21.0, float(y)))))
	img.fill_rect(Rect2i(0, 28, 128, 4), c.darkened(0.16))
	_lines(img, PackedVector2Array([Vector2(0, 27), Vector2(128, 27)]), 0.5, c.darkened(0.25), 0.6)
	for k in 6:
		var x := 8.0 + k * 21.0 + 6.0 * _hash01(k * 1.3)
		_lines(img, PackedVector2Array([Vector2(x, 18), Vector2(x + 3, 32)]), 1.2, c.darkened(0.2), 0.5, 0.9)
	_cloth_pass(img, "plain", "cotton", 0.0, 4)
	return _done(img)


## Original chest prints on a transparent 128x128 decal: "skull_bolt" (a distressed C2C
## lightning-skull badge) or "peligro" (warning sign + PELIGRO lettering).
func _print_tex(kind: String, ink: Color, acc: Color, bg: Color) -> ImageTexture:
	_nz_init()
	var img := _new_img(128, 128, Color(bg.r, bg.g, bg.b, 0.0))
	var blk := Color(bg.r, bg.g, bg.b, 1.0).darkened(0.3)
	if kind == "skull_bolt":
		var circ := _arc_pts(64, 54, 47, 47, 0.0, 360.0, 48)
		_lines(img, circ, 4.2, blk, 1.0, 0.2)
		_lines(img, circ, 2.4, ink, 1.0, 0.3)
		for k in 12:
			var t := TAU * float(k) / 12.0
			_dab(img, 64 + 53 * cos(t), 54 + 53 * sin(t), 1.6, 1.6, ink, 1.0, 0.4)   # rivets
		var bolt := PackedVector2Array([Vector2(86, 0), Vector2(56, 50), Vector2(70, 50), Vector2(36, 104),
			Vector2(98, 42), Vector2(80, 42), Vector2(106, 0)])
		var rim := bolt.duplicate()
		rim.append(bolt[0])
		_lines(img, rim, 3.6, blk, 1.0, 0.2)
		_poly(img, bolt, ink, 1.0)
		# skull: dark outline, then the white shapes, then the dark details
		_dab(img, 64, 50, 29.5, 28.5, blk, 1.0, 0.08)
		_dab(img, 64, 74, 20.5, 13.5, blk, 1.0, 0.1)
		_dab(img, 64, 50, 26, 25, ink, 1.0, 0.06)
		_dab(img, 64, 73, 17, 11, ink, 1.0, 0.08)
		for sg in [-1.0, 1.0]:
			var e: float = sg
			var ex := 64.0 + 11.0 * e
			_dab(img, ex, 56, 9.0, 8.0, blk, 1.0, 0.12)                     # eye sockets
			_poly(img, PackedVector2Array([Vector2(64 + 1 * e, 43), Vector2(64 + 1 * e, 53.5), Vector2(64 + 20 * e, 44)]), ink, 1.0)  # scowl
			_dab(img, 64 + 17 * e, 74, 3.6, 6.0, blk, 1.0, 0.2)             # cheek hollows
		_poly(img, PackedVector2Array([Vector2(64, 61), Vector2(59.5, 69), Vector2(68.5, 69)]), blk, 1.0)   # nose
		_lines(img, PackedVector2Array([Vector2(49, 76), Vector2(79, 76)]), 1.0, blk, 1.0, 0.3)            # teeth
		for tx in [53.0, 58.0, 64.0, 70.0, 75.0]:
			var x: float = tx
			_lines(img, PackedVector2Array([Vector2(x, 70), Vector2(x, 82)]), 0.8, blk, 1.0, 0.3)
		_lines(img, PackedVector2Array([Vector2(76, 30), Vector2(80, 36), Vector2(77, 41)]), 0.8, blk, 1.0, 0.3)  # crack
		_text(img, "C2C", 64, 104, 20, 3.0, ink, blk)
	else:
		var tri := PackedVector2Array([Vector2(64, 6), Vector2(100, 66), Vector2(28, 66)])
		var rim := tri.duplicate()
		rim.append(tri[0])
		_lines(img, rim, 5.0, blk, 1.0, 0.2)
		_poly(img, tri, acc, 1.0)
		_lines(img, rim, 2.2, ink, 1.0, 0.3)
		_text(img, "!", 64, 24, 34, 3.6, blk, acc)
		_text(img, "PELIGRO", 64, 80, 20, 2.6, ink, blk)
	# distressed print: cracks and worn spots let the shirt through
	var w := 128
	for y in w:
		for x in w:
			var n: float = _nz[((y * 3) & 255) * 256 + ((x * 3 + 41) & 255)]
			var n2: float = _nz[((y >> 2) & 255) * 256 + ((x >> 2) + 99 & 255)]
			if n > 0.96 or (n2 > 0.9 and n > 0.75):
				var c := img.get_pixel(x, y)
				if c.a > 0.01:
					img.set_pixel(x, y, c.lerp(blk, 0.85))
	return _done(img)


# --- hoodie --------------------------------------------------------------------------

func _hoodie_tex(base: Color) -> ImageTexture:
	# 256x256 over HOODIE (y 0.585 .. 0.04): eyelets, kangaroo pocket, folds, side seams.
	var img := _new_img(256, 256, base)
	var dk := base.darkened(0.35)
	var lt := base.lightened(0.13)
	for sx in [64.0, 192.0]:
		var c: float = sx
		_lines(img, PackedVector2Array([Vector2(c, 30), Vector2(c + 1.0, 256)]), 1.0, dk, 0.5)
	for sg in [-1.0, 1.0]:
		var s: float = sg
		_dab(img, 128 + 11 * s, 20, 2.6, 2.6, Color(0.75, 0.75, 0.72), 1.0, 0.3)   # eyelets
		_dab(img, 128 + 11 * s, 20, 1.3, 1.3, Color(0.08, 0.08, 0.08), 1.0, 0.3)
		_fold(img, Vector2(128 + 40 * s, 22), Vector2(128 + 62 * s, 66), 3.2, dk, lt, 0.5)
		_fold(img, Vector2(128 + 64 * s, 70), Vector2(128 + 42 * s, 100), 3.0, dk, lt, 0.5)
		var bx := 0.0 if s < 0.0 else 256.0
		_fold(img, Vector2(bx - 36 * s, 18), Vector2(bx - 60 * s, 66), 3.2, dk, lt, 0.45)
		_fold(img, Vector2(128 + 60 * s, 150), Vector2(128 + 66 * s, 240), 3.0, dk, lt, 0.4)
	var top := _trow(0.2, 0.585, 0.04, 256)
	var bot := _trow(0.05, 0.585, 0.04, 256)
	var pocket := PackedVector2Array([Vector2(94, top), Vector2(162, top), Vector2(178, top + 30), Vector2(178, bot),
		Vector2(78, bot), Vector2(78, top + 30)])
	_poly(img, pocket, base.darkened(0.07), 1.0)
	var outline := pocket.duplicate()
	outline.append(pocket[0])
	_lines(img, outline, 1.2, dk, 0.7, 0.4)
	for sg in [-1.0, 1.0]:
		var s: float = sg
		_lines(img, PackedVector2Array([Vector2(128 + 34 * s, top + 1), Vector2(128 + 50 * s, top + 30)]), 2.6, dk.darkened(0.3), 0.8, 0.6)  # opening shadow
		_lines(img, PackedVector2Array([Vector2(128 + 31 * s, top + 3), Vector2(128 + 46 * s, top + 31)]), 1.4, lt, 0.5, 0.6)
	_fold(img, Vector2(106, top + 12), Vector2(112, bot - 4), 2.4, dk, lt, 0.35)
	_fold(img, Vector2(148, top + 10), Vector2(142, bot - 6), 2.4, dk, lt, 0.35)
	for k in 9:
		var x := 6.0 + k * 28.0
		_fold(img, Vector2(x, 244), Vector2(x + 16, 236), 2.4, dk, lt, 0.4)
	_cloth_pass(img, "torso", "fleece", 4.0, 5)
	return _done(img)


# --- denim ---------------------------------------------------------------------------
# Dark-wash baggy jeans, 256 px wraps: fades are painted as lerps toward `fade` (the worn
# colour), seams as a dark fell line with twin lighter stitch lines beside it.

func _seam(img: Image, x: float, y0: float, y1: float, dk: Color, st: Color, a := 1.0) -> void:
	_lines(img, PackedVector2Array([Vector2(x, y0), Vector2(x, y1)]), 1.8, dk, 0.85 * a)
	for o in [-3.5, 3.5]:
		var ox: float = o
		_lines(img, PackedVector2Array([Vector2(x + ox, y0), Vector2(x + ox, y1)]), 0.8, st, 0.75 * a, 0.4)


## Whiskers: short light streaks with a dark crease under each, fanning from (x0, y0) by dir.
func _whiskers(img: Image, x0: float, y0: float, dir: float, n: int, ln: float, lt: Color, dk: Color, a: float) -> void:
	for k in n:
		var y := y0 + float(k) * 6.5
		var l := ln * (1.0 - 0.12 * float(k)) * (0.85 + 0.3 * _hash01(k * 3.1 + x0))
		var p0 := Vector2(x0, y)
		var p1 := Vector2(x0 + dir * l, y - 9.0 + float(k) * 1.5)
		var pm := (p0 + p1) * 0.5 + Vector2(0, 2.5)
		_lines(img, PackedVector2Array([p0 + Vector2(0, 2.2), pm + Vector2(0, 2.2), p1 + Vector2(0, 2.2)]), 1.2, dk, a * 0.45, 0.9)
		_lines(img, PackedVector2Array([p0, pm, p1]), 1.6, lt, a * (1.0 - 0.1 * float(k)), 0.9)


func _waist_tex(base: Color, fade: Color) -> ImageTexture:
	# 256x128 over WAIST (y 0.11 .. -0.235): belt + buckle, loops, fly with J-stitch, front
	# pockets with whiskering, back yoke and patch pockets, seat fade.
	var img := _new_img(256, 128, base)
	var dk := base.darkened(0.5)
	var st := fade.lightened(0.12)
	var r0 := _trow(-0.045, 0.11, -0.235, 128)
	var r1 := _trow(-0.074, 0.11, -0.235, 128)
	var rw := _trow(-0.09, 0.11, -0.235, 128)
	_dab(img, 128, 108, 70, 34, base.lerp(fade, 0.45), 0.85, 1.0)      # faded front / crotch
	_dab(img, 22, 104, 46, 30, base.lerp(fade, 0.38), 0.7, 1.0)        # faded seat
	_dab(img, 234, 104, 46, 30, base.lerp(fade, 0.38), 0.7, 1.0)
	img.fill_rect(Rect2i(0, int(r0) - 5, 256, int(rw - r0) + 5), base.darkened(0.1))   # waistband
	_lines(img, PackedVector2Array([Vector2(0, rw), Vector2(256, rw)]), 0.6, st, 0.6, 0.4)
	var belt := Color(0.05, 0.045, 0.04)
	img.fill_rect(Rect2i(0, int(r0), 256, int(r1 - r0)), belt)
	_lines(img, PackedVector2Array([Vector2(0, r0 + 1), Vector2(256, r0 + 1)]), 0.6, Color(0.24, 0.21, 0.19), 0.6)
	for lx in [86.0, 167.0, 48.0, 205.0, 12.0, 241.0, 0.0]:
		var x: float = lx
		img.fill_rect(Rect2i(int(x), int(r0) - 5, 4, int(rw - r0) + 6), base.lerp(fade, 0.32))   # loops
		_lines(img, PackedVector2Array([Vector2(x, r0 - 4), Vector2(x + 4, r0 - 4)]), 0.5, st, 0.6, 0.3)
	img.fill_rect(Rect2i(118, int(r0) - 2, 20, int(r1 - r0) + 4), Color(0.8, 0.8, 0.82))    # buckle
	img.fill_rect(Rect2i(121, int(r0) + 1, 14, int(r1 - r0) - 2), belt)
	_lines(img, PackedVector2Array([Vector2(128, rw), Vector2(128, 124)]), 1.3, dk, 0.85)    # fly
	_lines(img, PackedVector2Array([Vector2(137, rw), Vector2(137, 108), Vector2(131, 116)]), 0.6, st, 0.65, 0.4)
	for sg in [-1.0, 1.0]:
		var s: float = sg
		# front pocket opening (curved scoop) with stitching, coin pocket on the right
		var pk := PackedVector2Array([Vector2(128 + 22 * s, rw), Vector2(128 + 28 * s, rw + 12), Vector2(128 + 38 * s, rw + 19),
			Vector2(128 + 52 * s, rw + 21)])
		_lines(img, pk, 1.5, dk, 0.85)
		var pks := PackedVector2Array()
		for q in pk:
			pks.append(q + Vector2(3.0 * s, -3.0))
		_lines(img, pks, 0.55, st, 0.6, 0.4)
		_dab(img, 128 + 34 * s, rw + 9, 10, 7, base.lerp(fade, 0.45), 0.5, 1.0)   # worn pocket edge
		_whiskers(img, 128 + 8 * s, rw + 34, s, 5, 34.0, fade.lightened(0.05), dk, 0.75)
		# back: yoke, centre-back seam, patch pocket
		var bx := 0.0 if s < 0.0 else 256.0
		_lines(img, PackedVector2Array([Vector2(bx, rw + 13), Vector2(bx - 46 * s, rw + 5)]), 1.2, dk, 0.7)
		_lines(img, PackedVector2Array([Vector2(bx, rw + 10), Vector2(bx - 46 * s, rw + 2)]), 0.55, st, 0.55, 0.4)
		var bp := PackedVector2Array([Vector2(bx - 10 * s, rw + 16), Vector2(bx - 42 * s, rw + 12), Vector2(bx - 41 * s, rw + 40),
			Vector2(bx - 26 * s, rw + 46), Vector2(bx - 12 * s, rw + 41), Vector2(bx - 10 * s, rw + 16)])
		_poly(img, bp, base.lerp(fade, 0.12), 0.8)
		_lines(img, bp, 1.3, dk, 0.55)
		var bpi := PackedVector2Array()
		for q in bp:
			bpi.append(Vector2(lerpf(q.x, bx - 26 * s, 0.1), lerpf(q.y, rw + 28, 0.1)))
		_lines(img, bpi, 0.55, st, 0.5, 0.4)
	_seam(img, 1.0, rw, 128, dk, st, 0.8)
	_cloth_pass(img, "plain", "denim", 5.0, 6)
	return _done(img)


func _thigh_tex(base: Color, fade: Color, side: int) -> ImageTexture:
	# 256x256 wrap of a baggy pant leg from the hip (v 0) to just under the knee (v 1): faded
	# thigh front and knee, whiskers at the hip, seat fade at the back, out / inseams, drape.
	var img := _new_img(256, 256, base)
	var dk := base.darkened(0.55)
	var st := fade.lightened(0.12)
	var out_c := 64.0 if side < 0 else 192.0
	var in_c := 256.0 - out_c
	var idir := signf(in_c - 128.0)
	_dab(img, 128 - idir * 8, 120, 74, 120, base.lerp(fade, 0.42), 0.9, 1.0)   # thigh front fade
	_dab(img, 128 - idir * 4, 96, 34, 74, base.lerp(fade, 0.75), 0.65, 1.0)    # top-of-thigh wear
	_dab(img, 128, 238, 48, 30, base.lerp(fade, 0.7), 0.75, 1.0)               # knee
	_dab(img, 0, 30, 44, 36, base.lerp(fade, 0.3), 0.6, 1.0)                    # under the seat
	_dab(img, 256, 30, 44, 36, base.lerp(fade, 0.3), 0.6, 1.0)
	_whiskers(img, 128 + idir * 30, 18, -idir, 6, 54.0, fade.lightened(0.1), dk, 0.8)
	# drape: long soft folds, a couple of diagonal pulls from the crotch
	for c in [104.0, 158.0, 30.0, 228.0]:
		var x: float = c
		_fold(img, Vector2(x, 30), Vector2(x + 5, 256), 5.0, dk, base.lerp(fade, 0.35), 0.42)
	_fold(img, Vector2(128 + idir * 44, 10), Vector2(128 - idir * 10, 90), 4.0, dk, base.lerp(fade, 0.4), 0.35)
	_fold(img, Vector2(128 + idir * 52, 40), Vector2(128 + idir * 6, 140), 4.0, dk, base.lerp(fade, 0.4), 0.3)
	# back of the knee: a few soft horizontal creases
	var bk := 0.0 if idir > 0.0 else 256.0
	for k in 3:
		_fold(img, Vector2(bk - 30, 206 + k * 12), Vector2(bk + 30, 210 + k * 12), 2.6, dk, base.lerp(fade, 0.35), 0.45)
	_seam(img, out_c, 0, 256, dk, st)
	_seam(img, in_c, 0, 256, dk, st, 0.7)
	_cloth_pass(img, "limb", "denim", 5.0, 7 + side)
	return _done(img)


func _shin_tex(base: Color, fade: Color, side: int) -> ImageTexture:
	# 256x256 lower pant leg, knee (v 0) to the hem (v 1): knee fade, honeycombs behind the
	# knee, then the stacked accordion creases of a long leg piling on the sneaker.
	var img := _new_img(256, 256, base)
	var dk := base.darkened(0.6)
	var lt := base.lerp(fade, 0.55)
	var st := fade.lightened(0.12)
	var out_c := 64.0 if side < 0 else 192.0
	var in_c := 256.0 - out_c
	_dab(img, 128, 26, 52, 40, base.lerp(fade, 0.7), 0.75, 1.0)                 # knee fade
	_dab(img, 128, 110, 40, 60, base.lerp(fade, 0.3), 0.7, 1.0)
	for k in 3:
		for sg in [-1.0, 1.0]:
			var s: float = sg
			var bx := 0.0 if s < 0.0 else 256.0
			_fold(img, Vector2(bx - 4 * s, 22 + k * 13), Vector2(bx - 42 * s, 27 + k * 13), 3.2, dk, lt, 0.5)   # honeycombs
	for c in [92.0, 168.0]:
		var x: float = c
		_fold(img, Vector2(x, 54), Vector2(x - 6, 150), 5.0, dk, lt, 0.38)
	# stacks: wavy accordion creases, each lit on top and shaded below, plus fade on the ridges
	for k in 8:
		var y := 148.0 + k * 13.0
		var zz := PackedVector2Array()
		var zl := PackedVector2Array()
		var ph := _hash01(k * 2.9) * 6.0
		for i in 17:
			var x := float(i) * 256.0 / 16.0
			var yy := y + 5.0 * sin(float(i) * 1.7 + ph) + 2.0 * sin(float(i) * 3.3 + ph * 2.0)
			zz.append(Vector2(x, yy))
			zl.append(Vector2(x, yy - 5.0))
		_lines(img, zl, 3.4, base.lerp(fade, 0.6 + 0.04 * k), 0.7, 0.95)
		_lines(img, zz, 3.6, dk, 0.75, 0.9)
	img.fill_rect(Rect2i(0, 243, 256, 13), base.darkened(0.18))                # hem
	_lines(img, PackedVector2Array([Vector2(0, 242), Vector2(256, 242)]), 0.9, base.lerp(fade, 0.85), 0.55, 0.4)
	_lines(img, PackedVector2Array([Vector2(0, 250), Vector2(256, 250)]), 0.6, st, 0.5, 0.4)
	_seam(img, out_c, 0, 243, dk, st)
	_seam(img, in_c, 0, 243, dk, st, 0.7)
	_cloth_pass(img, "limb", "denim", 5.0, 9 + side)
	return _done(img)


# --- shoes ---------------------------------------------------------------------------

func _shoe_tex(base: Color, acc: Color) -> ImageTexture:
	# 256x128 chunky low-top upper (u 0.5 = laces, 0.25 / 0.75 the sides; v heel -> toe):
	# black leather, white toe box and side panels, white laces, black overlays, a bolt logo.
	var img := _new_img(256, 128, base)
	var stitch := base.lerp(Color(0.6, 0.6, 0.6), 0.5)
	_poly(img, PackedVector2Array([Vector2(26, 90), Vector2(230, 90), Vector2(230, 128), Vector2(26, 128)]), acc, 1.0)   # toe box
	for sg in [-1.0, 1.0]:
		var s: float = sg
		var cx := 128.0 + 64.0 * s
		var panel := PackedVector2Array([Vector2(cx - 34, 30), Vector2(cx + 34, 30), Vector2(cx + 36, 86),
			Vector2(cx - 36, 86)])
		_poly(img, panel, acc, 1.0)
		var bolt := PackedVector2Array([Vector2(cx + 6 * s, 38), Vector2(cx - 8 * s, 58), Vector2(cx + 1 * s, 58),
			Vector2(cx - 10 * s, 80), Vector2(cx + 12 * s, 54), Vector2(cx + 3 * s, 54), Vector2(cx + 14 * s, 38)])
		_poly(img, bolt, base, 1.0)
		var outl := panel.duplicate()
		outl.append(panel[0])
		_lines(img, outl, 0.6, stitch, 0.6)
		for k in 3:
			_dab(img, 128 + (16 + k * 10) * s, 104, 1.2, 1.2, stitch, 0.8, 0.4)   # perforations
			_dab(img, 128 + (20 + k * 10) * s, 114, 1.2, 1.2, stitch, 0.8, 0.4)
	_poly(img, PackedVector2Array([Vector2(108, 20), Vector2(148, 20), Vector2(152, 92), Vector2(104, 92)]), base, 1.0)  # eyestay
	img.fill_rect(Rect2i(114, 22, 28, 66), base.lightened(0.06))                  # tongue
	var lace := Color(0.93, 0.93, 0.9)
	for k in 8:
		var y := 26.0 + k * 8.0
		_lines(img, PackedVector2Array([Vector2(110, y), Vector2(146, y + 5)]), 1.6, lace, 1.0, 0.4)
		_lines(img, PackedVector2Array([Vector2(146, y), Vector2(110, y + 5)]), 1.6, lace.darkened(0.12), 1.0, 0.4)
	img.fill_rect(Rect2i(0, 0, 256, 10), base.lightened(0.05))                   # padded collar
	for k in 4:
		_lines(img, PackedVector2Array([Vector2(60, 98 + k * 2), Vector2(196, 98 + k * 2)]), 0.6, acc.darkened(0.25), 0.25, 0.9)  # flex creases
	_cloth_pass(img, "foot", "none", 0.0, 12)
	return _done(img)


func _sole_tex() -> ImageTexture:
	var c := Color(0.92, 0.91, 0.88)
	var img := _new_img(128, 32, c)
	for sx in [32.0, 96.0]:
		var x: float = sx
		_lines(img, PackedVector2Array([Vector2(x, 0), Vector2(x, 32)]), 1.2, c.darkened(0.25), 0.8)
	img.fill_rect(Rect2i(0, 0, 14, 32), c.darkened(0.45))
	img.fill_rect(Rect2i(114, 0, 14, 32), c.darkened(0.45))
	_cloth_pass(img, "plain", "skin", 0.0, 13)
	return _done(img)


# --- skin ----------------------------------------------------------------------------

func _arm_tex(skin: Color, part: String, side: int, tattoos: bool) -> ImageTexture:
	# "upper" 64x64 / "fore" 128x128 skin wrap: lit front, shaded back, warm mid-tones;
	# soft dark-ink tattoos on the outer forearm.
	var sz := 64 if part == "upper" else 128
	var img := _new_img(sz, sz, skin)
	var c := float(sz) * 0.5
	_dab(img, c, c, sz * 0.13, sz * 0.7, _skin_light(skin, 0.16), 0.55, 1.0)
	_dab(img, 0, c, sz * 0.14, sz * 0.7, _skin_shade(skin, 0.22), 0.5, 1.0)
	_dab(img, sz, c, sz * 0.14, sz * 0.7, _skin_shade(skin, 0.22), 0.5, 1.0)
	if part == "fore" and tattoos:
		var ink := Color(0.05, 0.035, 0.05)
		var oc := 34.0 if side < 0 else 94.0       # outer / top of the forearm
		if side < 0:
			for wd in 3:
				var pts := PackedVector2Array()
				for i in 40:
					var t := float(i) / 39.0
					pts.append(Vector2(oc + 18 + 4.0 * sin(t * TAU * 6.0) + wd * 9.0,
						24 + t * 70.0 + 2.5 * cos(t * TAU * 6.0)))
				_lines(img, pts, 0.9, ink, 0.6, 0.6)
			var star := PackedVector2Array()
			for k in 11:
				var t := -PI / 2 + TAU * float(k) / 10.0
				var rr := 9.0 if k % 2 == 0 else 4.0
				star.append(Vector2(oc + 28 + rr * cos(t), 108 + rr * sin(t)))
			_lines(img, star, 0.9, ink, 0.65, 0.5)
		else:
			for k in 4:
				_lines(img, _arc_pts(oc - 10, 44, 4.0 + k * 3.2, 4.0 + k * 2.8, 20.0 * k, 300.0 + 20.0 * k, 12), 0.9, ink, 0.6, 0.6)  # rose
			_dab(img, oc - 22, 60, 5, 2.5, ink, 0.45, 0.7)
			_dab(img, oc + 2, 62, 5, 2.5, ink, 0.45, 0.7)
			_lines(img, PackedVector2Array([Vector2(oc - 30, 80), Vector2(oc - 18, 76), Vector2(oc - 2, 80), Vector2(oc + 10, 76)]), 2.2, ink, 0.4, 0.8)  # banner
			for k in 16:
				_dab(img, k * 8.0 + 2, 116, 1.1, 1.1, ink, 0.55, 0.5)   # dotted band at the wrist
	_cloth_pass(img, "limb", "skin", 0.0, 15 + side)
	return _done(img)


# --- head ----------------------------------------------------------------------------
# The head wrap is 512x256 over HEAD: about 1 px per mm on the face. Features are placed in
# millimetres on the face (x right of centre, y up from the chin) and mapped onto the loft.

func _hp(img: Image, x_mm: float, y_mm: float) -> Vector2:
	var y := y_mm / 1000.0
	var r := _ring_at(HEAD, y)
	var a := asin(clampf(x_mm / 1000.0 / r.y, -1.0, 1.0))
	return Vector2((a + PI) / TAU * img.get_width(), _trow(y, HEAD_TOP, 0.0, img.get_height()))


## Face dab: centre and radii in mm.
func _fd(img: Image, x: float, y: float, rx: float, ry: float, c: Color, a: float, soft := 0.7) -> void:
	var p := _hp(img, x, y)
	var sx := absf(_hp(img, x + 1.0, y).x - _hp(img, x - 1.0, y).x) * 0.5
	var sy := 0.94 * img.get_height() / (HEAD_TOP * 1000.0)
	_dab(img, p.x, p.y, maxf(rx * sx, 0.7), maxf(ry * sy, 0.7), c, a, soft)


## Face polyline: points in mm, width in mm.
func _fl(img: Image, pts_mm: Array, w_mm: float, c: Color, a: float, soft := 0.6) -> void:
	var pts := PackedVector2Array()
	for q in pts_mm:
		var v: Vector2 = q
		pts.append(_hp(img, v.x, v.y))
	_lines(img, pts, w_mm * 0.94 * img.get_height() / (HEAD_TOP * 1000.0), c, a, soft)


## Almond eye arc: points along the top (sgn 1) or bottom (sgn -1) of an eye in mm.
func _eye_arc(ex: float, ey: float, hw: float, hh: float, sgn: float) -> Array:
	var out: Array = []
	for i in 9:
		var t := -1.0 + 2.0 * float(i) / 8.0
		out.append(Vector2(ex + hw * t, ey + sgn * hh * sqrt(maxf(0.0, 1.0 - t * t))))
	return out


func _head_tex(skin: Color, hair_c: Color, kind: String) -> ImageTexture:
	var img := _new_img(512, 256, skin)
	var lt := _skin_light(skin, 0.2)
	_fd(img, 0, 178, 42, 20, _skin_light(skin, 0.24), 0.7, 1.0)        # forehead
	_fd(img, -8, 184, 20, 9, _skin_light(skin, 0.36), 0.45, 1.0)       # forehead shine
	_fd(img, 0, 118, 5.5, 17, _skin_light(skin, 0.34), 0.7, 0.8)       # nose bridge
	_fd(img, 0, 88, 7, 6, _skin_light(skin, 0.3), 0.6, 0.9)            # nose tip
	_fd(img, 0, 74, 16, 4.0, _skin_shade(skin, 0.45), 0.55)           # under the nose
	_fd(img, 0, 66, 5, 5, _skin_shade(skin, 0.15), 0.3)               # philtrum
	_fd(img, 0, 24, 18, 10, _skin_light(skin, 0.16), 0.45, 1.0)        # chin
	_fd(img, 0, 43, 14, 3.5, _skin_shade(skin, 0.3), 0.45)            # under the lower lip
	for sg in [-1.0, 1.0]:
		var e: float = sg
		_fd(img, 62 * e, 150, 14, 26, _skin_shade(skin, 0.28), 0.5, 1.0)   # temples
		_fd(img, 26 * e, 149, 22, 6, _skin_light(skin, 0.26), 0.55)       # brow ridge
		_fd(img, 29 * e, 137, 19, 5, _skin_shade(skin, 0.5), 0.55, 0.9)    # shade under the brow
		_fd(img, 31 * e, 129, 17, 10, _skin_shade(skin, 0.4), 0.75, 0.9)   # eye sockets
		_fd(img, 31 * e, 117, 13, 4, _skin_shade(skin, 0.2), 0.4)          # under the eyes
		_fd(img, 43 * e, 106, 15, 10, _skin_light(skin, 0.3), 0.75, 1.0)   # cheekbones
		_fd(img, 40 * e, 110, 8, 4, _skin_light(skin, 0.36), 0.3, 1.0)     # cheek shine
		_fd(img, 12 * e, 104, 5, 14, _skin_shade(skin, 0.3), 0.45)         # nose sides
		_fd(img, 13 * e, 82, 6, 5, _skin_shade(skin, 0.45), 0.6)           # nostril wings
		_fl(img, [Vector2(17 * e, 86), Vector2(23 * e, 70), Vector2(27 * e, 56)], 2.4, _skin_shade(skin, 0.4), 0.45, 0.9)
		_fd(img, 54 * e, 40, 13, 26, _skin_shade(skin, 0.3), 0.45, 1.0)    # jaw sides
	if kind == "tank":
		var beard := hair_c.lerp(skin, 0.4)
		_fd(img, 0, 30, 21, 21, beard, 0.5, 1.0)                          # goatee, fading out
		_fd(img, 0, 22, 13, 10, hair_c, 0.6, 0.9)
		for sg in [-1.0, 1.0]:
			var e: float = sg
			_fl(img, [Vector2(25 * e, 62), Vector2(23 * e, 46), Vector2(13 * e, 34)], 2.2, beard, 0.45, 0.9)
		_fl(img, [Vector2(-25, 63), Vector2(-10, 68.5), Vector2(0, 68), Vector2(10, 68.5), Vector2(25, 63)], 2.7, hair_c, 0.85, 0.6)  # moustache
	var lip := skin.lerp(Color(0.34, 0.15, 0.15), 0.45)
	_fd(img, 0, 59.5, 24, 5.0, lip.darkened(0.35), 0.95, 0.55)          # upper lip
	_fd(img, 0, 50.5, 22, 6.2, lip, 0.95, 0.6)                          # lower lip
	_fd(img, 0, 50.0, 11, 2.4, _skin_light(lip, 0.45), 0.6)             # lower-lip sheen
	_fl(img, [Vector2(-23, 56), Vector2(-8, 55), Vector2(0, 55.6), Vector2(8, 55), Vector2(23, 56)], 1.2, Color(0.07, 0.035, 0.03), 0.9)
	var brow_c := hair_c.darkened(0.2)
	for sg in [-1.0, 1.0]:
		var e: float = sg
		var ex := 31.0 * e
		# slightly oversized eyes so they still read at gameplay distance
		_fl(img, _eye_arc(ex, 129.5, 14.5, 7.5, 1.0), 1.1, _skin_shade(skin, 0.6), 0.55, 0.8)    # lid crease
		_fd(img, ex, 127, 13.5, 5.4, Color(0.94, 0.91, 0.85), 1.0, 0.35)                       # white
		_fd(img, ex - 0.6 * e, 127, 5.8, 5.4, Color(0.24, 0.13, 0.06), 1.0, 0.3)              # iris
		_fd(img, ex - 0.6 * e, 127, 2.6, 2.6, Color(0.02, 0.01, 0.01), 1.0, 0.3)              # pupil
		_fd(img, ex + 1.6, 128.8, 1.3, 1.3, Color(1, 1, 1), 0.9, 0.4)                       # catchlight
		_fl(img, _eye_arc(ex, 127.0, 14.3, 5.7, 1.0), 1.8, Color(0.03, 0.02, 0.015), 0.95, 0.5)  # lash line
		_fl(img, _eye_arc(ex, 127.0, 13.0, 4.8, -1.0), 0.9, _skin_shade(skin, 0.6), 0.6, 0.6)
		_fl(img, [Vector2(10 * e, 143.5), Vector2(26 * e, 148), Vector2(45 * e, 145)], 3.8, brow_c, 0.95, 0.5)  # brows
	for ec in [128.0, 384.0]:
		var col: float = ec
		var row := _trow(0.112, HEAD_TOP, 0.0, 256)
		_dab(img, col, row, 10, 24, _skin_shade(skin, 0.3), 0.5, 0.9)      # ears
		_dab(img, col, row, 5, 13, _skin_shade(skin, 0.5), 0.5, 0.8)
	_paint_scalp(img, hair_c, kind)
	_cloth_pass(img, "head", "skin", 0.0, 16)
	return _done(img)


## Hair painted on the head wrap above the hairline (forehead, temples, sideburns, nape).
func _paint_scalp(img: Image, hair_c: Color, kind: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for x in w:
		var a := (float(x) + 0.5) / float(w) * TAU - PI
		var d := absf(a)
		var ly: float
		if d < 0.6:
			ly = 0.19 + 0.006 * d / 0.6
		elif d < 1.05:
			ly = lerpf(0.196, 0.168, (d - 0.6) / 0.45)
		elif d < 1.32:
			ly = 0.098 if kind == "tank" else 0.125      # sideburns
		elif d < 1.9:
			ly = 0.15                                   # over the ears
		else:
			ly = 0.03                                   # nape
		var row := _trow(ly, HEAD_TOP, 0.0, h)
		var full := int(row) - 3
		if full > 0:
			img.fill_rect(Rect2i(x, 0, 1, full), hair_c)
		for y in range(maxi(full, 0), mini(int(row) + 4, h)):
			var k := 1.0 - smoothstep(row - 3.0, row + 3.0, float(y) + 0.5)
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(hair_c, k * 0.95))


func _loc_tex(hair_c: Color) -> ImageTexture:
	# 32x128 twisted loc (u around, v root -> tip): diagonal twist bands, browner tips.
	var img := _new_img(32, 128, hair_c)
	var tip := hair_c.lerp(Color(0.24, 0.15, 0.09), 0.35)
	for y in 128:
		var v := (float(y) + 0.5) / 128.0
		for x in 32:
			var u := (float(x) + 0.5) / 32.0
			var tw := 0.5 + 0.5 * sin((u * 2.0 + v * 16.0) * TAU)
			var f := (0.6 + 0.75 * tw * tw) * (0.75 + 0.25 * smoothstep(0.0, 0.15, v))
			var c := hair_c.lerp(tip, smoothstep(0.7, 1.0, v))
			img.set_pixel(x, y, Color(c.r * f, c.g * f, c.b * f))
	_cloth_pass(img, "none", "hair", 0.0, 17)
	return _done(img)


func _cap_tex(hair_c: Color) -> ImageTexture:
	# 128x64 scalp under the locs: sections (parts) and bumpy roots.
	var img := _new_img(128, 64, hair_c)
	for k in 90:
		var x := _hash01(k * 1.37) * 128.0
		var y := _hash01(k * 2.71) * 64.0
		_dab(img, x, y, 4.5, 3.5, hair_c.lightened(0.16), 0.6, 0.8)
		_dab(img, x + 1.0, y + 1.5, 2.5, 1.5, hair_c.darkened(0.4), 0.5, 0.8)
	for x in range(0, 128, 13):
		_lines(img, PackedVector2Array([Vector2(x, 0), Vector2(x + 4, 64)]), 0.8, hair_c.darkened(0.5), 0.5)
	_cloth_pass(img, "none", "hair", 0.0, 18)
	return _done(img)


func _chain_tex() -> ImageTexture:
	# 16x64: four rope-chain links along v (repeats along the chain), a bright ridge in u.
	var img := _new_img(16, 64, Color(0.9, 0.9, 0.92))
	for y in 64:
		var m := float(y % 16) / 16.0
		for x in 16:
			var u := (float(x) + 0.5) / 16.0
			var f := 0.5 + 0.5 * sin(PI * m) + 0.25 * sin(PI * u)
			if m < 0.1:
				f = 0.25
			img.set_pixel(x, y, Color(0.9 * f, 0.9 * f, 0.93 * f))
	return _done(img)


# --- the costume mask ----------------------------------------------------------------
const MASK_A := 1.25          # the mask patch spans -MASK_A .. MASK_A around the head
const MASK_TOP := 0.205
const MASK_BOT := 0.004


func _mp(x_mm: float, y_mm: float) -> Vector2:
	var y := y_mm / 1000.0
	var r := _ring_at(HEAD, y)
	var a := asin(clampf(x_mm / 1000.0 / (r.y + 0.012), -1.0, 1.0))
	return Vector2((a + MASK_A) / (2.0 * MASK_A) * 256.0, (0.02 + 0.96 * (MASK_TOP - y) / (MASK_TOP - MASK_BOT)) * 256.0)


func _md(img: Image, x: float, y: float, rx: float, ry: float, c: Color, a: float, soft := 0.4) -> void:
	var p := _mp(x, y)
	var sx := absf(_mp(x + 1.0, y).x - _mp(x - 1.0, y).x) * 0.5
	var sy := 0.96 * 256.0 / ((MASK_TOP - MASK_BOT) * 1000.0)
	_dab(img, p.x, p.y, maxf(rx * sx, 0.7), maxf(ry * sy, 0.7), c, a, soft)


func _mpoly(pts_mm: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts_mm:
		var v: Vector2 = q
		out.append(_mp(v.x, v.y))
	return out


## Cheap Halloween-store skull mask (256x256 over the moulded patch): a pale bone-white
## vacuum-formed shell with crudely sprayed black / red features -- big black eye holes with
## a sloppy red rim, a black nose cavity, a stitched-teeth grin, a forehead crack, red drips,
## grey cheek hollows and a glossy plastic highlight stripe; transparent outside the face
## outline (alpha scissor).
func _mask_tex(base: Color, paint: Color) -> ImageTexture:
	var img := _new_img(256, 256, base)
	var blk := Color(0.015, 0.015, 0.02)
	var hollow := base.darkened(0.55)
	for y in 256:
		for x in 256:
			var dx := (float(x) + 0.5 - 128.0) / 124.0
			var dy := (float(y) + 0.5 - 124.0) / 126.0
			if dy > 0.0:
				dx *= 1.0 + 0.45 * dy
			var d := sqrt(dx * dx + dy * dy)
			if d >= 1.0:
				img.set_pixel(x, y, Color(base.r, base.g, base.b, 0.0))
				continue
			var f := 1.1 - 0.26 * d * d - 0.2 * smoothstep(0.88, 1.0, d)
			img.set_pixel(x, y, Color(base.r * f, base.g * f * 0.995, base.b * f * 0.97))
	# sprayed grey hollows: temples, under the cheekbones, round the jaw
	for sg in [-1.0, 1.0]:
		var e: float = sg
		_md(img, 52 * e, 150, 13, 22, hollow, 0.4, 1.0)
		_md(img, 40 * e, 70, 15, 16, hollow, 0.5, 1.0)
		_md(img, 26 * e, 30, 12, 10, hollow, 0.3, 1.0)
	# forehead crack (black)
	_lines(img, _mpoly([Vector2(8, 205), Vector2(14, 190), Vector2(5, 180), Vector2(12, 166), Vector2(6, 156)]), 1.6, blk, 0.95, 0.3)
	_lines(img, _mpoly([Vector2(14, 190), Vector2(24, 184)]), 1.2, blk, 0.9, 0.3)
	_lines(img, _mpoly([Vector2(-30, 200), Vector2(-24, 188), Vector2(-32, 176)]), 1.2, blk, 0.8, 0.3)
	for sg in [-1.0, 1.0]:
		var e: float = sg
		var ex := 30.0 * e
		_md(img, ex, 127, 29, 22, paint, 1.0, 0.35)                     # sloppy red rim
		_md(img, ex + 3.0 * e, 128, 25, 18, blk, 1.0, 0.12)              # big eye hole
		_md(img, ex - 2.0 * e, 125, 7.5, 3.6, Color(0.55, 0.5, 0.45), 0.5, 0.6)   # the eye in the dark
		_md(img, ex - 2.0 * e, 125, 3.0, 3.0, blk, 0.95, 0.4)
		# red drips running down from the sockets
		var dx0 := ex + 14.0 * e
		_lines(img, _mpoly([Vector2(dx0, 108), Vector2(dx0 + 1.0, 88)]), 1.7, paint, 1.0, 0.3)
		_md(img, dx0 + 1.0, 87, 2.6, 3.6, paint, 1.0, 0.3)
		_lines(img, _mpoly([Vector2(ex - 4.0 * e, 106), Vector2(ex - 4.0 * e, 98)]), 1.5, paint, 1.0, 0.3)
		_md(img, ex - 4.0 * e, 97, 2.2, 3.0, paint, 1.0, 0.3)
		# nose cavity: two black slanted triangles
		_poly(img, _mpoly([Vector2(2.0 * e, 101), Vector2(15.0 * e, 76), Vector2(2.0 * e, 80)]), blk, 1.0)
	# stitched-teeth grin: a wide black slit crossed by tooth lines, red gums above
	_lines(img, _mpoly([Vector2(-34, 60), Vector2(-17, 54), Vector2(0, 53), Vector2(17, 54), Vector2(34, 60)]), 2.0, paint, 0.9, 0.4)
	_lines(img, _mpoly([Vector2(-32, 55), Vector2(-16, 50), Vector2(0, 49), Vector2(16, 50), Vector2(32, 55)]), 1.8, blk, 1.0, 0.25)
	for i in 9:
		var tx := -28.0 + i * 7.0
		var lift := 4.0 * pow(absf(tx) / 30.0, 2.0)
		_lines(img, _mpoly([Vector2(tx, 62 + lift), Vector2(tx, 38 + lift)]), 1.1, blk, 1.0, 0.3)
	_md(img, 0, 49, 9, 2.4, blk, 1.0, 0.3)                              # mouth slit (air hole)
	# glossy vacuum-formed plastic: a hard white highlight stripe down the forehead and cheek
	_lines(img, _mpoly([Vector2(-20, 196), Vector2(-27, 170), Vector2(-50, 152)]), 3.2, Color(1, 1, 1), 0.75, 0.6)
	_lines(img, _mpoly([Vector2(-55, 104), Vector2(-50, 74), Vector2(-40, 54)]), 2.6, Color(1, 1, 1), 0.6, 0.7)
	_md(img, -4, 92, 3.0, 9.0, Color(1, 1, 1), 0.55, 0.8)               # nose ridge glint
	_lines(img, PackedVector2Array([Vector2(128, 6), Vector2(128, 250)]), 0.8, base.lightened(0.35), 0.3)   # mould seam
	_cloth_pass(img, "none", "skin", 0.0, 19)
	return _done(img)


# --- the model ------------------------------------------------------------------
# Realistic slim-athletic adult (~1.95 m, head ~0.25 m incl. hair: ~7.5 heads). The shoulder
# pivots sit wide (x 0.42) for the animation rig, so the upper arms are slanted lofts that start
# at a natural shoulder ~0.3 from the centre and reach the elbow pivot; oversized clothes are
# loose shells kept close to the body so lying poses stay on the mat. look keys (all optional):
#   skin, face: "tank" | "kid"; hair: "locs" | "curls" | "none"; hair_color
#   top: "tee" | "hoodie"; top_color, top_accent, graphic: "skull_bolt" | "peligro" | "none";
#   undershirt (bool); bottom_color, bottom_fade (baggy jeans wash and its fades)
#   shoe_color, shoe_accent; chain, bracelet, tattoos (bool); wristband_color
#   sleeves: "long" (continuous sleeve + cuff, default for hoodies) | "short" (tee) | "none";
#   hood (bool, hoodies; default true); mask (bool, the skull costume mask), mask_base, mask_paint;
#   bulk (0.8..1.15: limb thickness; pivots never move)

var hand_r: Node3D  # right hand attach point (child of elbow_r): held items go here
var hand_l: Node3D
var finger_curl := 1.6        # fingers: 1.6 = fist ... 0.3 = open hand (see _apply_hands)
var _hand_parts: Array = []   # per hand: [side, finger knuckle pivot, finger tip pivot, thumb pivot]


func _build_body() -> void:
	var skin_c := skin_color
	var hair_c: Color = look.get("hair_color", Color(0.05, 0.035, 0.03))
	var hair: String = look.get("hair", "none")
	var face: String = look.get("face", "tank")
	var top: String = look.get("top", "tee")
	var top_c: Color = look.get("top_color", Color(0.075, 0.072, 0.078))
	var top_acc: Color = look.get("top_accent", gear_color)
	var graphic: String = look.get("graphic", "none")
	var bot_c: Color = look.get("bottom_color", Color(0.12, 0.115, 0.125))
	var bot_f: Color = look.get("bottom_fade", Color(0.33, 0.3, 0.28))
	var shoe_c: Color = look.get("shoe_color", Color(0.06, 0.06, 0.065))
	var shoe_a: Color = look.get("shoe_accent", Color(0.92, 0.92, 0.9))
	var tattoos: bool = look.get("tattoos", false)
	var bulk_v: float = look.get("bulk", 1.0)
	var bulk := clampf(bulk_v, 0.8, 1.15)
	var kt := lerpf(1.0, bulk, 0.5)
	var hoodie := top == "hoodie"
	var ks := str(skin_c)
	var kc := str(top_c)
	var kb := str(bot_c) + str(bot_f)
	var white := Color.WHITE

	var skin := _mat(skin_c, null, 0.25, 0.55)
	var sheen_c := Color(0.1, 0.075, 0.05)     # warm skin sheen (additive rim / glint pass)
	var m := {
		"skin": skin,
		"upper": _sheen(_mat(white, _tex("arm_u" + ks, _arm_tex.bind(skin_c, "upper", 0, false)), 0.25, 0.55), sheen_c),
		"fore_l": _sheen(_mat(white, _tex("arm_f-" + ks + str(tattoos), _arm_tex.bind(skin_c, "fore", -1, tattoos)), 0.25, 0.55), sheen_c),
		"fore_r": _sheen(_mat(white, _tex("arm_f+" + ks + str(tattoos), _arm_tex.bind(skin_c, "fore", 1, tattoos)), 0.25, 0.55), sheen_c),
		"thigh_l": _mat(white, _tex("thigh-" + kb, _thigh_tex.bind(bot_c, bot_f, -1))),
		"thigh_r": _mat(white, _tex("thigh+" + kb, _thigh_tex.bind(bot_c, bot_f, 1))),
		"foot": _mat(white, _tex("shoe" + str(shoe_c) + str(shoe_a), _shoe_tex.bind(shoe_c, shoe_a))),
		"sole": _mat(white, _tex("sole", _sole_tex)),
		"chain": _mat(Color(0.95, 0.95, 0.97), _tex("chain", _chain_tex), 0.9, 0.25),
	}
	if hoodie or look.get("sleeves", "") == "long":
		m["sleeve_up"] = _mat(white, _tex("hsu" + kc, _sleeve_tex.bind(top_c, "hood_up")))
		m["sleeve_lo"] = _mat(white, _tex("hsl" + kc, _sleeve_tex.bind(top_c, "hood_lo")))
		m["sleeve_fore"] = _mat(white, _tex("hsf" + kc, _sleeve_tex.bind(top_c, "hood_fore")))
		m["cuff"] = _mat(white, _tex("hsc" + kc, _sleeve_tex.bind(top_c, "cuff")))
	if not hoodie:
		m["sleeve"] = _mat(white, _tex("tsl" + kc, _sleeve_tex.bind(top_c, "tee")))
	m["shin_l"] = _mat(white, _tex("shin-" + kb, _shin_tex.bind(bot_c, bot_f, -1)))
	m["shin_r"] = _mat(white, _tex("shin+" + kb, _shin_tex.bind(bot_c, bot_f, 1)))
	if look.get("bracelet", false):
		m["bracelet"] = m["chain"]
	if look.has("wristband_color"):
		var wb: Color = look.get("wristband_color", Color.WHITE)
		m["wristband"] = _mat(wb)

	# Blob shadow (stays flat on the mat)
	var sh := CylinderMesh.new()
	sh.top_radius = 0.55
	sh.bottom_radius = 0.55
	sh.height = 0.01
	sh.radial_segments = 16
	var sh_mat := StandardMaterial3D.new()
	sh_mat.albedo_color = Color(0, 0, 0, 0.5)
	sh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_mesh(self, sh, Vector3(0, 0.03, 0), sh_mat)

	# pose_root = pelvis. Everything rotates around it.
	pose_root = _pivot(self, Vector3(0, STAND_Y, 0))
	hips = _pivot(pose_root, Vector3.ZERO)

	# Jeans waist (belt, fly, pockets painted on), the undershirt hem, and the shirt's hem piece
	var waist := _loft(hips, _bulked(WAIST, kt, kt), _mat(white, _tex("waist" + kb, _waist_tex.bind(bot_c, bot_f))),
		true, true, Vector3.ZERO, 16)
	waist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if look.get("undershirt", false):
		# thin undershirt hem hugging the jeans waistband, only a sliver shows under the tee
		var u_rings: Array = []
		for uy in [0.03, 0.004, -0.016]:
			var wr := _ring_at(WAIST, uy)
			u_rings.append(Vector4(uy, wr.y * kt + 0.004, wr.z * kt + 0.004, wr.w * kt))
		_loft(hips, u_rings, _mat(white, _tex("under", _undershirt_tex)), false, false, Vector3.ZERO, 16)
	var sk_rings: Array
	if hoodie:
		sk_rings = [Vector4(0.17, 0.238, 0.166, 0.006), Vector4(0.08, 0.242, 0.17, 0.007), Vector4(0.006, 0.24, 0.168, 0.006),
			Vector4(-0.012, 0.226, 0.158, 0.004), Vector4(-0.045, 0.216, 0.15, 0.003)]
	else:
		sk_rings = [Vector4(0.17, 0.236, 0.16, 0.003), Vector4(0.08, 0.24, 0.163, 0.004), Vector4(0.0, 0.244, 0.166, 0.005)]
	var skirt := _loft(hips, _bulked(sk_rings, kt, kt), _mat(white, _tex("skirt" + kc + str(hoodie), _skirt_tex.bind(top_c, hoodie))),
		false, false, Vector3.ZERO, 16, PackedFloat32Array(), 0.025, 2.0)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Torso: the oversized tee / hoodie shell (the body under it is never seen)
	torso = _pivot(hips, Vector3(0, 0.12, 0))
	var shell: Array = _bulked(HOODIE if hoodie else TEE, kt, kt)
	var shell_tex: Texture2D
	if hoodie:
		shell_tex = _tex("hood" + kc, _hoodie_tex.bind(top_c))
	else:
		shell_tex = _tex("tee" + kc, _tee_tex.bind(top_c))
	var tmi := _loft(torso, shell, _mat(white, shell_tex), false, false, Vector3.ZERO, 16, PackedFloat32Array(), 0.02, 1.3)
	tmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if graphic != "none":
		var ink := Color(0.9, 0.89, 0.85) if graphic == "skull_bolt" else top_acc
		var pm := _mat(white, _tex("print" + graphic + kc + str(top_acc), _print_tex.bind(graphic, ink, Color(1.0, 0.8, 0.1), top_c)))
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		pm.alpha_scissor_threshold = 0.5
		var gy0 := 0.485 if not hoodie else 0.47
		var gy1 := 0.215 if not hoodie else 0.255
		var ga := 0.62 if not hoodie else 0.52
		_add_mesh(torso, _patch_mesh(shell, -ga, ga, gy0, gy1, 0.007, 10, 10), Vector3.ZERO, pm)

	# Neck
	_loft(torso, [Vector4(0.665, 0.05, 0.054, 0.004), Vector4(0.6, 0.054, 0.058, -0.004),
		Vector4(0.53, 0.062, 0.064, -0.01)], m["upper"], false, false, Vector3.ZERO, 12)
	if hoodie:
		var hood_m: Material = m["sleeve_up"]
		_loft(torso, [Vector4(0.66, 0.1, 0.112, -0.03), Vector4(0.6, 0.142, 0.14, -0.026),
			Vector4(0.545, 0.19, 0.145, -0.018)], hood_m, false, false, Vector3.ZERO, 16)          # hood round the neck
		if look.get("hood", true):
			var hood := _loft(torso, [Vector4(0.645, 0.07, 0.026, -0.108), Vector4(0.615, 0.125, 0.045, -0.13),
				Vector4(0.56, 0.148, 0.055, -0.158), Vector4(0.5, 0.14, 0.05, -0.164), Vector4(0.445, 0.11, 0.042, -0.168),
				Vector4(0.405, 0.06, 0.028, -0.163)], hood_m, true, true, Vector3.ZERO, 16, PackedFloat32Array(), 0.07, 3.3)
			hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON                       # hood down, bunched on the back
			var rim := PackedVector3Array()
			var rim_r := PackedFloat32Array()
			for i in 13:
				var t := lerpf(-1.25, 1.25, float(i) / 12.0)
				rim.append(Vector3(sin(t) * 0.135, 0.636 - 0.03 * t * t, -0.072 - 0.106 * cos(t)))
				rim_r.append(0.017 + 0.004 * sin(float(i) * 1.7))
			var rst := SurfaceTool.new()
			rst.begin(Mesh.PRIMITIVE_TRIANGLES)
			_tube_into(rst, rim, rim_r, 8, 0.0, 2.0)
			_add_mesh(torso, rst.commit(), Vector3.ZERO, hood_m)                                      # rolled hood opening
		var lace := _mat(Color(0.92, 0.92, 0.9))
		var fz: float = _ring_at(shell, 0.5).z + _ring_at(shell, 0.5).w + 0.004
		for sx in [-0.026, 0.026]:
			var dx: float = sx
			_loft(torso, [Vector4(0.555, 0.005, 0.005, fz - 0.01), Vector4(0.44, 0.005, 0.005, fz + 0.004)],
				lace, false, false, Vector3(dx, 0, 0), 6)                                              # drawstrings
	else:
		_loft(torso, [Vector4(0.588, 0.062, 0.06, -0.006), Vector4(0.574, 0.074, 0.072, -0.01)],
			_mat(top_c.darkened(0.1)), false, false, Vector3.ZERO, 16)                                 # collar rib
	if look.get("chain", false):
		var chain_m: Material = m["chain"]
		_build_chain(shell, chain_m)

	# Head: a natural ~0.16 m wide skull on its own geometry node; the head pivot (nods,
	# looks) never moves.
	head = _pivot(torso, Vector3(0, 0.6, 0.02))
	var hg := _pivot(head, Vector3(0, 0.015, 0.012))
	_loft(hg, HEAD, _sheen(_mat(white, _tex("head" + face + ks + str(hair_c), _head_tex.bind(skin_c, hair_c, face)), 0.25, 0.5),
		sheen_c, 2.4, 0.7), true, true, Vector3.ZERO, 16)
	# nose: a slim bridge, a rounded tip and two flared nostril wings (no wedge)
	var nose_m := _sheen(_mat(_skin_light(skin_c, 0.06), null, 0.12, 0.6), sheen_c, 2.2, 0.9)
	_loft(hg, [Vector4(0.126, 0.006, 0.004, 0.094), Vector4(0.112, 0.0075, 0.0065, 0.096), Vector4(0.098, 0.009, 0.0085, 0.097),
		Vector4(0.088, 0.011, 0.009, 0.0975), Vector4(0.079, 0.0115, 0.0065, 0.096)], nose_m, true, true, Vector3.ZERO, 8)
	_ball(hg, 0.0095, Vector3(0, 0.0855, 0.0995), nose_m, Vector3(1.0, 0.8, 0.85), 10)      # tip
	for ns in [-1.0, 1.0]:
		var nx: float = ns
		_ball(hg, 0.0075, Vector3(0.0115 * nx, 0.0805, 0.0915), nose_m, Vector3(1.0, 0.8, 0.95), 8)   # nostril wings
	var ear := _mat(_skin_shade(skin_c, 0.1), null, 0.2, 0.6)
	for es in [-1.0, 1.0]:
		var ex: float = es
		_ball(hg, 0.024, Vector3(0.079 * ex, 0.112, -0.008), ear, Vector3(0.4, 1.25, 0.8), 8)      # ears
	if hair == "locs":
		_loft(hg, HAIR_CAP, _mat(white, _tex("hcap" + str(hair_c), _cap_tex.bind(hair_c)), 0.1, 0.7), true, false, Vector3.ZERO, 16)
		_build_locs(hg, _sheen(_mat(white, _tex("locs" + str(hair_c), _loc_tex.bind(hair_c)), 0.18, 0.6),
			Color(0.06, 0.058, 0.065), 3.0, 0.9), 38)
	elif hair == "curls":
		_loft(hg, HAIR_CAP, _mat(white, _tex("hcap" + str(hair_c), _cap_tex.bind(hair_c)), 0.1, 0.7), true, false, Vector3.ZERO, 16)
		_build_curls(hg, _mat(white, _tex("locs" + str(hair_c), _loc_tex.bind(hair_c)), 0.15, 0.6), 34)
	if look.get("mask", false):
		_build_costume_mask(hg)

	# Arms: shoulder -> elbow -> hand
	arm_l = _build_arm(-1, m, top, bulk)
	arm_r = _build_arm(1, m, top, bulk)

	# Legs: hip -> knee -> sneaker
	leg_l = _build_leg(-1, m, bulk)
	leg_r = _build_leg(1, m, bulk)


## Pushes p outside the shell (loft rings) by margin, checking its ring and the one just below.
func _push_out(rings: Array, p: Vector3, margin: float) -> Vector3:
	var out := p
	for dy in [0.0, -0.012]:
		var ddy: float = dy
		var r := _ring_at(rings, out.y + ddy)
		var q := Vector2(out.x / r.y, (out.z - r.w) / r.z)
		var need := 1.0 + margin / minf(r.y, r.z)
		var l := q.length()
		if l < need and l > 0.0001:
			q = q / l * need
			out = Vector3(q.x * r.y, out.y, q.y * r.z + r.w)
	return out


## Thick white rope chain lying on the shirt round the neck, hanging to a pendant mid-chest.
func _build_chain(shell: Array, chain_m: Material) -> void:
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	var low := Vector3.ZERO
	var n := 48
	for i in n + 1:
		var t := TAU * float(i) / float(n)
		var c := cos(t)
		var drop := pow(maxf(0.0, c), 1.5)
		var p := Vector3(sin(t) * 0.098 * (1.0 - 0.5 * drop), 0.578 - 0.22 * drop, c * 0.095 - 0.012)
		p = _push_out(shell, p, 0.012)
		pts.append(p)
		rad.append(0.0075)
		if i == 0:
			low = p
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube_into(st, pts, rad, 6, 0.0, 30.0)
	_add_mesh(torso, st.commit(), Vector3.ZERO, chain_m)
	var pd := _pivot(torso, low + Vector3(0, -0.036, 0.008))
	_ball(pd, 0.009, Vector3(0, 0.03, -0.002), chain_m, Vector3(1.0, 1.0, 0.6), 8)       # bail
	_block(pd, Vector3(0.05, 0.058, 0.014), Vector3.ZERO, chain_m)
	_block(pd, Vector3(0.024, 0.03, 0.01), Vector3(0, -0.002, 0.006), _mat(Color(0.12, 0.12, 0.14), null, 0.9, 0.2))
	_block(pd, Vector3(0.012, 0.016, 0.008), Vector3(0, -0.002, 0.009), chain_m)


## Medium locs (n chunky 6-sided tapered tubes, one mesh) rooted on the scalp: they drape over
## the skull to its widest line and hang with gravity to jaw / neck length; a short fringe lies
## over the forehead and the temple ones swing out to frame the face.
func _build_locs(hg: Node3D, mat: Material, n: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0.0, 0.15, -0.008)
	var rad := Vector3(0.084, 0.1, 0.106)
	for k in n:
		var z := (float(k) + 0.5) / float(n)
		var phi := acos(1.0 - z * (1.0 - cos(1.5)))
		var th := wrapf(float(k) * 2.39996 + 0.3 * (_hash01(k * 1.3) - 0.5), -PI, PI)
		var aft := absf(th)
		if aft < PI * 0.5:
			phi = minf(phi, lerpf(1.5, 0.82, cos(th)))      # roots stay behind the hairline
		var end_y: float
		var swing := th
		if aft < 0.5:
			end_y = lerpf(0.152, 0.17, _hash01(k * 2.1))     # fringe over the forehead (brows at 0.145)
		elif aft < 1.1:
			end_y = lerpf(0.03, 0.07, _hash01(k * 2.7))
			swing = signf(th) * 1.15                          # swing out beside the face
		elif aft < 2.2:
			end_y = lerpf(-0.005, 0.04, _hash01(k * 3.1))
		else:
			end_y = lerpf(-0.035, 0.0, _hash01(k * 3.7))
		var rr := lerpf(0.0085, 0.0115, _hash01(k * 5.3))
		var lay := 0.003 + 0.012 * _hash01(k * 7.7) + rr
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		pts.append(c + Vector3(sin(phi) * sin(th) * rad.x, cos(phi) * rad.y, sin(phi) * cos(th) * rad.z) * 0.95)
		radii.append(rr * 0.8)
		var ph_end := PI * 0.5
		if end_y > c.y:
			ph_end = acos(clampf((end_y - c.y) / (rad.y + lay), -1.0, 1.0))
		ph_end = maxf(ph_end, phi + 0.05)
		for i in range(1, 5):
			var t := float(i) / 4.0
			var ph := lerpf(phi, ph_end, t)
			var sw := lerp_angle(th, swing, t)
			pts.append(c + Vector3(sin(ph) * sin(sw) * (rad.x + lay), cos(ph) * (rad.y + lay), sin(ph) * cos(sw) * (rad.z + lay)))
			radii.append(rr)
		var top := pts[pts.size() - 1]
		var hang := top.y - end_y
		if hang > 0.01:
			var outd := Vector3(top.x - c.x, 0.0, top.z - c.z).normalized()
			var sway := (_hash01(k * 9.1) - 0.5) * 0.02
			for i in range(1, 4):
				var t := float(i) / 3.0
				pts.append(Vector3(top.x, top.y - hang * t, top.z) + outd * (0.012 * t) + Vector3(sway * t, 0, 0))
				radii.append(rr * lerpf(1.0, 0.8, t))
		var last := pts[pts.size() - 1]
		var prev := pts[pts.size() - 2]
		pts.append(last + (last - prev).normalized() * rr * 0.8)
		radii.append(rr * 0.35)
		_tube_into(st, pts, radii, 6, 0.0, 1.0)
	_add_mesh(hg, st.commit(), Vector3.ZERO, mat)


## Short messy curls (n small 5-sided tufts, one mesh) springing from the scalp, kept off the face.
func _build_curls(hg: Node3D, mat: Material, n: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector3(0.0, 0.15, -0.008)
	var rad := Vector3(0.088, 0.104, 0.11)
	for k in n:
		var z := (float(k) + 0.5) / float(n)
		var phi := acos(1.0 - z * (1.0 - cos(1.45)))
		var th := wrapf(float(k) * 2.39996 + 0.4 * (_hash01(k * 1.9) - 0.5), -PI, PI)
		if absf(th) < PI * 0.5:
			phi = minf(phi, lerpf(1.45, 0.8, cos(th)))
		var out := Vector3(sin(phi) * sin(th), cos(phi), sin(phi) * cos(th))
		var root := c + out * rad * 0.97
		var side := Vector3(cos(th), 0.0, -sin(th))
		var ln := lerpf(0.028, 0.048, _hash01(k * 3.3))
		var rr := lerpf(0.011, 0.015, _hash01(k * 4.1))
		var curl := 1.0 if _hash01(k * 6.7) > 0.5 else -1.0
		var pts := PackedVector3Array([root])
		var radii := PackedFloat32Array([rr])
		for i in range(1, 5):
			var t := float(i) / 4.0
			var a := t * 2.4 * curl
			var d := (out * cos(a) + side * sin(a) * 0.8 + Vector3(0, -0.5 * t * phi, 0)).normalized()
			pts.append(pts[i - 1] + d * ln * 0.25)
			radii.append(rr * lerpf(1.0, 0.35, t))
		_tube_into(st, pts, radii, 5, 0.0, 0.6)
	_add_mesh(hg, st.commit(), Vector3.ZERO, mat)


## The costume mask: a glossy vacuum-formed skull shell standing off the face (moulded brow,
## cheekbones, nose and chin), a bit crooked, held on by a pale elastic band round the back of
## the head, stapled to the mask at the temples.
func _build_costume_mask(hg: Node3D) -> void:
	var bone: Color = look.get("mask_base", Color(0.93, 0.9, 0.8))
	var paint: Color = look.get("mask_paint", Color(0.8, 0.06, 0.05))
	var mm := _mat(Color.WHITE, _tex("mask" + str(bone) + str(paint), _mask_tex.bind(bone, paint)), 1.0, 0.12)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mm.alpha_scissor_threshold = 0.5
	var mk := _pivot(hg, Vector3(0.003, -0.004, 0.0))
	mk.rotation = Vector3(0.03, 0.04, -0.06)                      # slapped on crooked
	_add_mesh(mk, _patch_mesh(HEAD, -MASK_A, MASK_A, MASK_TOP, MASK_BOT, 0.012, 18, 18, 0.021), Vector3.ZERO, mm)
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := 20
	for i in n + 1:
		var t := lerpf(0.98, TAU - 0.98, float(i) / float(n))
		var y := 0.13 + 0.018 * (1.0 - cos(t)) * 0.5
		var r := _ring_at(HAIR_CAP, y)
		pts.append(Vector3(sin(t) * (r.y + 0.005), y, cos(t) * (r.z + 0.005) + r.w))
		radii.append(0.0034)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tube_into(st, pts, radii, 6, 0.0, 1.0)
	_add_mesh(hg, st.commit(), Vector3.ZERO, _mat(Color(0.74, 0.72, 0.67)))         # elastic band
	var staple := _mat(Color(0.7, 0.72, 0.75), null, 0.9, 0.3)
	for sg in [-1.0, 1.0]:
		var e: float = sg
		_block(mk, Vector3(0.004, 0.012, 0.007), Vector3(0.088 * e, 0.131, 0.031), staple)


func _build_arm(side: int, m: Dictionary, top: String, bulk: float) -> Node3D:
	var sleeves: String = look.get("sleeves", "long" if top == "hoodie" else "short")
	if sleeves == "long":
		return _build_long_sleeve_arm(side, m, bulk)
	var s := float(side)
	var k := bulk
	var upper: Material = m["upper"]
	var skin: Material = m["skin"]
	var fore: Material = m["fore_l"] if side < 0 else m["fore_r"]
	var sh := _pivot(torso, Vector3(0.42 * s, 0.47, 0))
	# slim upper arm slanting from a natural shoulder (inboard of the pivot) to the elbow
	_ball(sh, 0.056 * k, Vector3(-0.112 * s, -0.014, 0.0), upper, Vector3(1.0, 1.05, 1.08), 12)    # deltoid
	_loft(sh, [Vector4(0.03, 0.052 * k, 0.055 * k, 0.0), Vector4(-0.06, 0.053 * k, 0.056 * k, 0.004),
		Vector4(-0.16, 0.048 * k, 0.051 * k, 0.006), Vector4(-0.26, 0.043 * k, 0.046 * k, 0.003),
		Vector4(-0.345, 0.04 * k, 0.042 * k, 0.0)], upper, true, true, Vector3.ZERO, 12,
		PackedFloat32Array([-0.118 * s, -0.096 * s, -0.064 * s, -0.028 * s, 0.0]))
	if top == "hoodie":
		var su: Material = m["sleeve_up"]
		_ball(sh, 0.082, Vector3(-0.106 * s, -0.01, 0.0), su, Vector3(1.0, 0.86, 1.05), 14)     # shoulder
		_loft(sh, [Vector4(0.03, 0.074, 0.078, 0.0), Vector4(-0.12, 0.08, 0.082, 0.006),
			Vector4(-0.26, 0.077, 0.078, 0.006), Vector4(-0.38, 0.072, 0.074, 0.004)], su, false, false, Vector3.ZERO, 14,
			PackedFloat32Array([-0.115 * s, -0.07 * s, -0.03 * s, 0.0]), 0.04, 5.0 + s)        # baggy upper sleeve
	elif sleeves != "none":
		var sl: Material = m["sleeve"]
		_ball(sh, 0.086, Vector3(-0.108 * s, -0.008, 0.0), sl, Vector3(1.0, 0.8, 1.06), 14)      # dropped shoulder
		_loft(sh, [Vector4(0.02, 0.086, 0.092, 0.0), Vector4(-0.08, 0.097, 0.1, 0.004),
			Vector4(-0.19, 0.103, 0.106, 0.008)], sl, false, false, Vector3.ZERO, 14,
			PackedFloat32Array([-0.112 * s, -0.086 * s, -0.056 * s]), 0.05, 3.0 + s)            # wide short sleeve
	var el := _pivot(sh, Vector3(0, -0.32, 0))
	if side < 0:
		elbow_l = el
	else:
		elbow_r = el
	_ball(el, 0.041 * k, Vector3(0, 0.0, -0.004), upper, Vector3.ONE, 10)                        # elbow
	_loft(el, [Vector4(0.02, 0.042 * k, 0.042 * k, 0.0), Vector4(-0.06, 0.047 * k, 0.044 * k, 0.004),
		Vector4(-0.17, 0.039 * k, 0.036 * k, 0.002), Vector4(-0.27, 0.031 * k, 0.027 * k, 0.0),
		Vector4(-0.3, 0.03 * k, 0.026 * k, 0.0)], fore, true, true, Vector3.ZERO, 12)               # forearm, slim wrist
	if top == "hoodie":
		var sd: Material = m["sleeve_lo"]
		_loft(el, [Vector4(0.06, 0.07, 0.072, 0.0), Vector4(-0.1, 0.068, 0.068, 0.004), Vector4(-0.2, 0.058, 0.058, 0.002),
			Vector4(-0.215, 0.047, 0.045, 0.0), Vector4(-0.27, 0.044, 0.042, 0.0)], sd, false, false, Vector3.ZERO, 14,
			PackedFloat32Array(), 0.04, 7.0 + s)                                                   # lower sleeve + cuff
	if side < 0 and m.has("bracelet"):
		var bm: Material = m["bracelet"]
		var pts := PackedVector3Array()
		var radii := PackedFloat32Array()
		for i in 17:
			var a := TAU * float(i) / 16.0
			pts.append(Vector3(cos(a) * 0.039 * k, -0.25 + 0.005 * sin(a), sin(a) * 0.035 * k))
			radii.append(0.0085)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tube_into(st, pts, radii, 6, 0.0, 6.0)
		_add_mesh(el, st.commit(), Vector3.ZERO, bm)                                                # iced bracelet
	if side > 0 and m.has("wristband"):
		var wb: Material = m["wristband"]
		_loft(el, [Vector4(-0.19, 0.046 * k, 0.043 * k, 0.0), Vector4(-0.265, 0.041 * k, 0.038 * k, 0.0)], wb, true, true,
			Vector3.ZERO, 12)
	var hand := _build_hand(el, side, lerpf(1.0, bulk, 0.5), skin)
	if side < 0:
		hand_l = hand
	else:
		hand_r = hand
	return sh


## Long-sleeve arm (look "sleeves": "long", the default for hoodies) as one continuous 12-sided sleeve: the upper sleeve loft slants from
## the shoulder past the elbow pivot into a full elbow cap (a ball on the pivot as wide as the
## sleeve there), and the forearm sleeve starts inside that cap, so the sleeve stays closed at
## every bend the poses use; it blouses over a ribbed cuff, then the wrist (wristband) and a
## real hand. Same rig as _build_arm: shoulder pivot, elbow pivot 0.32 below, hand 0.33 below.
func _build_long_sleeve_arm(side: int, m: Dictionary, bulk: float) -> Node3D:
	var s := float(side)
	var k := bulk
	var su: Material = m["sleeve_up"]
	var sf: Material = m["sleeve_fore"]
	var skin: Material = m["skin"]
	var sh := _pivot(torso, Vector3(0.42 * s, 0.47, 0))
	_ball(sh, 0.082, Vector3(-0.106 * s, -0.01, 0.0), su, Vector3(1.0, 0.86, 1.05), 12)        # dropped shoulder
	_loft(sh, [Vector4(0.03, 0.074, 0.078, 0.0), Vector4(-0.06, 0.08, 0.082, 0.005), Vector4(-0.16, 0.079, 0.08, 0.006),
		Vector4(-0.25, 0.074, 0.075, 0.004), Vector4(-0.3, 0.069, 0.07, 0.0), Vector4(-0.338, 0.058, 0.059, 0.0)],
		su, false, true, Vector3.ZERO, 12, PackedFloat32Array([-0.115 * s, -0.088 * s, -0.058 * s, -0.025 * s, -0.006 * s, 0.0]),
		0.03, 5.0 + s)                                                                           # upper sleeve, into the elbow
	var el := _pivot(sh, Vector3(0, -0.32, 0))
	if side < 0:
		elbow_l = el
	else:
		elbow_r = el
	_ball(el, 0.073, Vector3(0, 0.0, -0.002), su, Vector3(1.0, 1.0, 1.03), 12)                  # elbow cap
	_loft(el, [Vector4(0.016, 0.058, 0.059, 0.0), Vector4(-0.02, 0.069, 0.07, 0.002), Vector4(-0.1, 0.067, 0.066, 0.004),
		Vector4(-0.17, 0.06, 0.058, 0.003), Vector4(-0.205, 0.057, 0.055, 0.002), Vector4(-0.218, 0.05, 0.049, 0.0)],
		sf, true, false, Vector3.ZERO, 12, PackedFloat32Array(), 0.035, 7.0 + s)                # forearm sleeve
	_loft(el, [Vector4(-0.2, 0.049, 0.047, 0.0), Vector4(-0.212, 0.05, 0.048, 0.0), Vector4(-0.248, 0.046, 0.044, 0.0),
		Vector4(-0.254, 0.043, 0.041, 0.0)], m["cuff"], false, false, Vector3.ZERO, 12)            # ribbed cuff
	_loft(el, [Vector4(-0.235, 0.033 * k / 0.86, 0.03 * k / 0.86, 0.0), Vector4(-0.3, 0.028 * k / 0.86, 0.025 * k / 0.86, 0.0)],
		skin, true, true, Vector3.ZERO, 10)                                                      # wrist
	if side > 0 and m.has("wristband"):
		var wb: Material = m["wristband"]
		_loft(el, [Vector4(-0.244, 0.037, 0.034, 0.0), Vector4(-0.25, 0.038, 0.035, 0.0), Vector4(-0.28, 0.036, 0.033, 0.0),
			Vector4(-0.285, 0.034, 0.031, 0.0)], wb, false, false, Vector3.ZERO, 12)
	var hand := _build_hand(el, side, lerpf(1.0, bulk, 0.5), skin)
	if side < 0:
		hand_l = hand
	else:
		hand_r = hand
	return sh


## Hand: a palm, a two-joint finger block (fingers in two groups) curled by finger_curl, and
## a thumb. The returned pivot is the attach point for held items.
## The palm faces the body (-x on the right hand); fingers curl toward it around z.
func _build_hand(el: Node3D, side: int, kf: float, skin: Material) -> Node3D:
	var s := float(side)
	var hand := _pivot(el, Vector3(0, -0.33, 0.005))
	var t := 0.034 * kf        # palm thickness (x)
	var w := 0.084 * kf        # palm width (z)
	var ph := 0.094 * kf       # palm height (y)
	var py := 0.01             # palm centre
	_block(hand, Vector3(t, ph, w), Vector3(0, py, 0), skin)
	var ft := 0.03 * kf        # finger thickness
	var fw := 0.082 * kf       # finger block width
	var l1 := 0.046 * kf
	var l2 := 0.04 * kf
	var knuckle := _pivot(hand, Vector3(-s * t * 0.5, py - ph * 0.5 + 0.006, 0.0))
	var tip := _pivot(knuckle, Vector3(0.0, -l1, 0.0))
	for g in [-1.0, 1.0]:
		var gz: float = g * fw * 0.26
		var gl: float = 1.0 if g > 0.0 else 0.88
		_block(knuckle, Vector3(ft, l1 + 0.01, fw * 0.48), Vector3(s * ft * 0.5, -l1 * 0.5, gz), skin)
		_block(tip, Vector3(ft * 0.9, l2 * gl + 0.008, fw * 0.45), Vector3(s * ft * 0.48, -l2 * gl * 0.5, gz), skin)
	var thumb := _pivot(hand, Vector3(-s * t * 0.2, py + ph * 0.18, w * 0.42))
	_block(thumb, Vector3(0.026, 0.056, 0.026) * kf, Vector3(0.0, -0.028 * kf, 0.0), skin)
	_hand_parts.append([s, knuckle, tip, thumb])
	_pose_hand(s, knuckle, tip, thumb, finger_curl)
	return hand


func _pose_hand(s: float, knuckle: Node3D, tip: Node3D, thumb: Node3D, curl: float) -> void:
	knuckle.rotation = Vector3(0.0, 0.0, -s * curl)
	tip.rotation = Vector3(0.0, 0.0, -s * curl * 0.9)
	var c := clampf((curl - 0.3) / 1.3, 0.0, 1.0)
	thumb.rotation = Vector3(-0.6 + 0.25 * c, 0.0, -s * (0.15 + 0.55 * c))


const OPEN_HAND_STATES := [S.GRAB_WINDUP, S.TIEUP_ATK, S.TIEUP_DEF, S.THROWING, S.PICKUP, S.TAUNT,
	S.CLIMB, S.PERCHED]


## Pose hook: open hands while reaching / grappling / hauling / taunting / climbing,
## fists otherwise (and always around a held item); eased.
func _apply_hands(delta: float) -> void:
	var want := 1.6
	if held_item == null:
		if state in OPEN_HAND_STATES and not (state == S.TAUNT and _style == 1):
			want = 0.3
		elif state == S.PICKUP_ITEM and state_time < 0.2:
			want = 0.3
	finger_curl = lerpf(finger_curl, want, 1.0 - exp(-14.0 * delta))
	for hp in _hand_parts:
		var s: float = hp[0]
		var kn: Node3D = hp[1]
		var tp: Node3D = hp[2]
		var th: Node3D = hp[3]
		_pose_hand(s, kn, tp, th, finger_curl)


func _build_leg(side: int, m: Dictionary, bulk: float) -> Node3D:
	# hip pivot at 0.89 m, knee at 0.46 m, sole at 0.0 m when standing straight
	var s := float(side)
	var k := lerpf(1.0, bulk, 0.4)             # baggy pants barely follow the build
	var thigh_m: Material = m["thigh_l"] if side < 0 else m["thigh_r"]
	var hp := _pivot(hips, Vector3(0.14 * s, -0.06, 0))
	var thigh := _loft(hp, _bulked([Vector4(0.1, 0.124, 0.13, 0.004), Vector4(0.0, 0.128, 0.133, 0.008),
		Vector4(-0.2, 0.124, 0.128, 0.008), Vector4(-0.4, 0.12, 0.124, 0.006), Vector4(-0.47, 0.118, 0.122, 0.006)], k, k),
		thigh_m, false, false, Vector3.ZERO, 16, PackedFloat32Array(), 0.045, 4.0 + s * 1.7)     # wide straight leg
	thigh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var kn := _pivot(hp, Vector3(0, -0.43, 0))
	if side < 0:
		knee_l = kn
	else:
		knee_r = kn
	var shin_m: Material = m["shin_l"] if side < 0 else m["shin_r"]
	var shin := _loft(kn, _bulked([Vector4(0.07, 0.118, 0.122, 0.006), Vector4(-0.05, 0.12, 0.124, 0.006),
		Vector4(-0.2, 0.12, 0.124, 0.004), Vector4(-0.29, 0.124, 0.128, 0.004), Vector4(-0.33, 0.116, 0.12, 0.006),
		Vector4(-0.36, 0.13, 0.133, 0.008), Vector4(-0.39, 0.121, 0.125, 0.01), Vector4(-0.425, 0.132, 0.136, 0.014)], k, k),
		shin_m, false, false, Vector3.ZERO, 16, PackedFloat32Array(), 0.06, 8.0 + s * 2.3)    # stacked at the ankle
	shin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_build_shoe(kn, m)
	return hp


func _build_shoe(kn: Node3D, m: Dictionary) -> void:
	# Chunky low-top sneaker (~0.33 m long) lofted heel -> toe: the loft runs along its local y,
	# the mesh is turned -90 deg about x so local y points backward and local z up. The cupsole
	# bottom sits at knee-local -0.46 (= the floor).
	var f := _loft(kn, [Vector4(0.1, 0.064, 0.038, 0.0), Vector4(0.085, 0.088, 0.058, 0.005), Vector4(0.03, 0.095, 0.066, 0.008),
		Vector4(-0.05, 0.1, 0.058, 0.0), Vector4(-0.13, 0.1, 0.046, -0.012), Vector4(-0.19, 0.09, 0.034, -0.02),
		Vector4(-0.222, 0.052, 0.02, -0.024)], m["foot"], true, true, Vector3(0, -0.398, 0), 16)
	f.rotation.x = -PI / 2
	var sole := _loft(kn, [Vector4(0.114, 0.078, 0.024, 0.0), Vector4(0.092, 0.102, 0.026, 0.0), Vector4(0.0, 0.105, 0.026, 0.0),
		Vector4(-0.12, 0.105, 0.025, 0.0), Vector4(-0.2, 0.097, 0.023, 0.002), Vector4(-0.236, 0.064, 0.018, 0.004)],
		m["sole"], true, true, Vector3(0, -0.437, 0), 16)
	sole.rotation.x = -PI / 2
	sole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ---------------------------------------------------------------- helpers

func set_state(s: int) -> void:
	_flow_on_state(s)  # flow & boost hook: tweak bonus, boost off (before the state changes)
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
		ai_tie_delay = randf_range(0.45, 0.95) * (1.6 - ai_skill)
	if s == S.PINNED:
		pin_freebie_now = pin_freebie_left and not is_cpu  # fair pins: the first one is free
		if not is_cpu:
			pin_freebie_left = false
	_weapons_on_state(s)  # weapons hook: drops the held item when hit / grappled


func is_standing() -> bool:
	return state in [S.IDLE, S.WALK, S.RUN, S.PUNCH, S.RUN_ATTACK, S.STUNNED, S.TAUNT,
		S.WHIFF, S.GRAB_WINDUP, S.WHIPPING, S.STOMP,
		S.PICKUP_ITEM, S.SWING, S.THROW_ITEM, S.SET_TABLE]  # weapons states


func is_special_ready() -> bool:
	return spirit >= 100.0 or brawl_mode


## STYLE: trick points for a MOVES entry, scaled by tier.
func _trick_pts(m: Dictionary) -> int:
	var dmg: float = m.get("dmg", 8.0)
	var tier: String = m.get("tier", "weak")
	var kind: String = m.get("kind", "throw")
	if tier == "finisher":
		return 2000
	if kind == "dive":
		return clampi(int(400.0 + dmg * 50.0), 500, 1500)
	if tier == "reversal":
		return 300
	if tier == "strong":
		return clampi(int(300.0 + dmg * 18.0), 300, 600)
	if kind == "strike" or kind == "ground" or tier == "strike" or tier == "ground":
		return clampi(int(30.0 + dmg * 10.0), 50, 150)
	return clampi(int(150.0 + dmg * 18.0), 200, 450)


## STYLE: trick kind for a MOVES entry.
func _trick_kind(m: Dictionary) -> String:
	if m.get("tier", "") == "finisher":
		return "super"
	var kind: String = m.get("kind", "throw")
	match kind:
		"dive":
			return "aerial"
		"strike", "ground":
			return "strike"
	return "grapple"


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
	if opponent != null and opponent.brawl_mode: d *= 1.15  # style hook: BRAWL MODE hits a bit harder (supers already scale up)
	if d > 0.0:
		# Combo damage scaling: hits taken less than COMBO_HIT_GAP apart are one combo;
		# the 4th hit on does x0.7, the 7th on x0.5 (no 10-second deaths).
		combo_hits = combo_hits + 1 if combo_timer > 0.0 else 1
		combo_timer = COMBO_HIT_GAP
		if combo_hits >= 7:
			d *= 0.5
		elif combo_hits >= 4:
			d *= 0.7
		if opponent != null and opponent.is_cpu and not is_cpu:
			var cpu_skill: float = opponent.ai_skill
			d *= 0.7 + 0.4 * cpu_skill   # an easy CPU hits softer (x0.82 at 0.3, x1.02 at 0.8)
			opponent._ai_note_hit(d)
	health = max(0.0, health - d)
	spirit = max(0.0, spirit - d * 0.4)
	if d > 0.0:
		trick.emit("", 0, "break")  # getting hurt breaks our style combo


func _down_time() -> float:
	return 1.3 + (1.0 - health / 100.0) * 2.4


func _clamp_ring() -> void:
	if _hf_clamp():  # high flying hook: corners / height allowed while climbing, perched, diving
		if state == S.CORNER_STUN:
			_col_push_out()  # yard collision: slumped next to a prop, not inside it
		return
	var yr := _yard_rect()  # movement hook: the yard (arena.yard_bounds) replaces the ring
	position.x = clampf(position.x, yr.position.x, yr.end.x)
	position.z = clampf(position.z, yr.position.y, yr.end.y)
	position.y = 0.0
	_col_push_out()  # yard collision: out of the props' footprints


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
	_flow_pre(delta)  # flow & boost hook: flow-window cancels, tweaks (PIN held), CPU flow

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
		S.ROLL:
			_mv_roll(delta)  # movement hook: dodge roll
	_flow_post()  # flow & boost hook: +FLOW for a cancel / in-window follow-up

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
		_mv_start_run()  # movement hook: momentum sprint starts slow
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
	if not whipped and _mv_run_input(delta):
		return  # movement hook: dodge roll (double-tap RUN)
	if not whipped and in_move.length() > 0.3:
		var want := Vector3(in_move.x, 0, in_move.y).normalized()
		_mv_turn_bleed(want, delta)  # movement hook: hard turns bleed momentum
		run_dir = run_dir.lerp(want, clamp(delta * 2.5, 0.0, 1.0)).normalized()
	elif whipped and rope_bounces >= 1:
		# Coming off the ropes after a whip: run back at whoever whipped us.
		var back := _flat_to_opponent()
		if back.length() > 0.6:
			var nd := run_dir.lerp(back.normalized(), clampf(delta * 6.0, 0.0, 1.0))
			if nd.length() > 0.1:
				run_dir = nd.normalized()
	position += run_dir * (RUN_SPEED if whipped else _mv_run_speed(delta)) * delta
	_set_facing_angle(atan2(run_dir.x, run_dir.z))
	if _col_run_hit():  # yard collision: whipped / full steam into a prop = prop crash
		return
	if whipped and _hf_check_corner_crash():  # high flying hook: whipped into a corner
		return

	# Rebound off the fence / house wall (movement hook: arena.yard_bounds).
	var bounced := _mv_fence_bounce()
	if bounced:
		rope_bounces += 1
		_hf_on_rope_bounce()  # high flying hook: opens the springboard window
		impact.emit(0.15)
		sfx.emit("thud", 0.35, global_position + Vector3(0, 1.2, 0))  # off the fence
		if not whipped: trick.emit("Rebound", 50, "movement")  # style hook
		if not whipped and _hf_rope_buffered_launch():
			return  # high flying hook: rope launch pressed just before the ropes
		if rope_bounces > (1 if whipped else 3):
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
	if in_grapple and _hf_run_grab():  # high flying hook: slingshot off the ropes
		return
	if (in_strike or in_grapple) and _hf_buffer_rope_launch():
		return  # high flying hook: about to hit the ropes: launch on the rebound
	var opp_down := _opp_state() == S.DOWN or _opp_state() == S.ON_TABLE  # weapons: table counts
	var dist := _flat_to_opponent().length()
	if in_strike:
		if opp_down and dist < 2.6:
			_start_ground_drop("elbow_drop")
		else:
			_start_run_attack()
	elif in_grapple and opp_down and dist < 2.6:
		_start_ground_drop("knee_drop")
	elif in_run or in_grapple or state_time > 5.0:
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
	throw_to = _col_nudge_pt(_yard_clamp_pt(Vector3(land_pos.x, 0, land_pos.z), 0.5), 0.5)  # inside the yard, off the props
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
	trick.emit(label, 300 if label.begins_with("REVERSAL") else 100, "grapple")  # style hook


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
	# Fair pins: a CPU only covers a human who is properly worn down.
	var cover_ok: bool = not is_cpu or opponent.is_cpu or opponent.health < CPU_PIN_HP
	if os == S.DOWN and _flat_to_opponent().length() < 2.0 and cover_ok:
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
		trick.emit("Showboat" if taunt_bonus else "Crowd Pleaser", 250 if taunt_bonus else 150, "movement")  # style hook
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
			if not is_cpu and opponent.is_cpu:
				bump_cpu_skill()  # difficulty ramp: the next CPU is a bit tougher
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
		# Per press: 0.45 + 1.1 * health (mid health ~1.0, so ~3.5 presses/s escapes in time).
		pin_escape += 0.45 + 1.1 * (health / 100.0)
	var freebie: bool = pin_freebie_now and opponent.pin_count_value >= 2
	if (freebie or pin_escape >= _pin_escape_needed()) and _opp_state() == S.PINNING:
		pin_freebie_now = false
		var count: int = opponent.pin_count_value
		var near_fall := count >= 2
		if freebie:
			announce.emit("KICKED OUT AT 2!")
			gain_spirit(8.0)
		elif near_fall:
			announce.emit(NEAR_FALL_CALLS[randi() % NEAR_FALL_CALLS.size()])
			gain_spirit(8.0)  # the crowd rallies behind a near fall
		else:
			announce.emit("KICK OUT!")
		last_hit_tier = ""  # that move's effect is spent
		trick.emit("Near-Fall Kick Out" if near_fall else "Kick Out", 500 if near_fall else 200, "movement")  # style hook
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
	if ai_backoff > 0.0 or string_step >= 1 + int(ai_skill * 3.0):
		return  # 3 hits in: back off (and a low-skill CPU strings fewer hits)
	if randf() > 0.25 + 0.5 * ai_skill:
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
	if ai_skill < 0.45 and chain_link >= 1:
		return  # a low-skill CPU chains at most two moves
	if randf() < 0.1 + 0.4 * ai_skill - 0.1 * chain_link:
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
	trick.emit(_item_call(kind, "run" if swing_running else "hit"), 300, "weapon")  # style hook
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
		trick.emit(_item_call(kind, "throw"), 300, "weapon")  # style hook
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
		attacker.trick.emit("Through The Table", 800, "weapon")  # style hook
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
	opponent.trick.emit("Through The Table", 800, "weapon")  # style hook
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

## Difficulty ramp (static, survives scene reloads; mirrored in Engine meta to be safe).
static func cpu_skill_for_match() -> float:
	if Engine.has_meta("c2c_cpu_skill"):
		var v: float = Engine.get_meta("c2c_cpu_skill")
		cpu_skill_level = maxf(cpu_skill_level, v)
	return clampf(cpu_skill_level, 0.0, CPU_SKILL_MAX)


static func bump_cpu_skill() -> void:
	cpu_skill_level = minf(CPU_SKILL_MAX, cpu_skill_for_match() + CPU_SKILL_STEP)
	Engine.set_meta("c2c_cpu_skill", cpu_skill_level)


## take_damage hook: our hit on a human landed. 3 hits in a flurry or one big move -> back off.
func _ai_note_hit(d: float) -> void:
	if anim_clock - ai_streak_at > 1.5:
		ai_streak = 0
	ai_streak += 1
	ai_streak_at = anim_clock
	if ai_streak >= 3 or d >= 8.0:
		ai_streak = 0
		ai_backoff = maxf(ai_backoff, randf_range(0.9, 1.4) * (1.3 - 0.4 * ai_skill))


func _ai_grace() -> bool:
	return ai_match_time < CPU_GRACE_TIME


# Idle-human pacing: when the human has not touched the controls for CPU_IDLE_AFTER seconds,
# the CPU still engages (never just stands there), but at a slow cadence: one engagement
# (a strike, a lock-up, a run-in, a stomp / cover, a dive) every CPU_IDLE_GAP seconds, and
# it circles or plays to the crowd in between. Tuned so an idle player lasts ~60-90 s.
const CPU_IDLE_AFTER := 2.5
const CPU_IDLE_GAP := Vector2(4.0, 6.0)
var ai_opp_idle := 0.0     # seconds the human opponent has sent no input
var ai_engage_cd := 0.0    # idle pacing: seconds until the next engagement is allowed


func _ai_opp_is_idle() -> bool:
	if opponent.is_cpu or ai_opp_idle < CPU_IDLE_AFTER or _ai_grace():
		return false
	# A pin-worthy knockdown is followed up (cover) as part of the same engagement: the
	# opponent is down for less than the gap, so pacing it would make an idle player unpinnable.
	var oh: float = opponent.health
	return not (_opp_state() == S.DOWN and oh < CPU_PIN_HP)


func _ai_track_idle(delta: float) -> void:
	if opponent.is_cpu:
		ai_opp_idle = 0.0
		return
	var om: Vector2 = opponent.in_move
	var osp: float = opponent.since_press
	if om.length() > 0.2 or osp < 0.25 or opponent.in_run or opponent.in_pin:
		ai_opp_idle = 0.0
		ai_engage_cd = 0.0  # back to normal play the moment they act
	else:
		ai_opp_idle += delta
	ai_engage_cd = maxf(0.0, ai_engage_cd - delta)


## Idle pacing, between engagements: circle at mid range, sometimes taunt. Never stand still.
func _ai_idle_circle(dist: float, toward: Vector2) -> void:
	if ai_strafe_time <= 0.0:
		_ai_start_strafe()
		ai_strafe_time = randf_range(1.2, 2.2)
	var perp := Vector2(-toward.y, toward.x) * ai_strafe_dir
	if dist < 1.9:
		in_move = (-toward * 0.8 + perp * 0.5).normalized() * 0.8
	elif dist > 3.2:
		in_move = (toward * 0.7 + perp * 0.5).normalized() * 0.8
	else:
		in_move = perp * 0.7
	if ai_timer <= 0.0:
		ai_timer = randf_range(1.2, 2.0)
		if dist > 2.3 and taunt_cooldown <= 0.0 and randf() < 0.25:
			in_pin = true  # taunt (far from the opponent, so never a cover)


func _ai(delta: float) -> void:
	ai_match_time += delta
	_ai_track_idle(delta)
	var was_free := state == S.IDLE or state == S.WALK
	_ai_think(delta)
	# Post-filter the inputs the decision code chose (reversal presses are never touched).
	if reversal_window > 0.0:
		return
	if _ai_opp_is_idle():
		var cover := in_pin and _opp_state() == S.DOWN and _flat_to_opponent().length() < 2.2
		var attacking := in_strike or in_grapple or in_run or cover
		if was_free and attacking:
			if ai_engage_cd > 0.0:
				in_strike = false
				in_grapple = false
				in_run = false
				if cover:
					in_pin = false
			else:
				ai_engage_cd = randf_range(CPU_IDLE_GAP.x, CPU_IDLE_GAP.y)
		elif state == S.PUNCH or state == S.THROWING:
			in_strike = false  # one move per engagement: no strings / chains on an idle player
			in_grapple = false
		elif state == S.CLIMB and ai_engage_cd <= 0.0:
			ai_engage_cd = randf_range(CPU_IDLE_GAP.x, CPU_IDLE_GAP.y) + 1.5  # the dive is this engagement
	if _ai_grace():
		# Opening grace period: strikes only, and slower.
		in_grapple = false
		in_run = false
		if was_free and in_strike:
			ai_timer = maxf(ai_timer, randf_range(1.1, 1.7))
		if state == S.PUNCH and string_step >= 1:
			in_strike = false  # at most two-hit strings
	if in_pin and not opponent.is_cpu and _opp_state() == S.DOWN and opponent.health >= CPU_PIN_HP \
			and _flat_to_opponent().length() < 2.2:
		in_pin = false  # fair pins: no covers on a healthy human


func _ai_think(delta: float) -> void:
	ai_timer -= delta
	if state == S.IDLE or state == S.WALK:
		ai_backoff -= delta  # only counts down while free (chains / strings finish first)
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
		# Reaction delay scales with (1 - ai_skill): 0.5-0.9 s at 0.3, ~0.15-0.25 s at 0.8.
		ai_react = maxf(0.1, randf_range(0.5, 0.9) * (1.0 - ai_skill) / 0.7)

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

	var free_now := state == S.IDLE or state == S.WALK
	if free_now and ai_engage_cd > 0.0 and _ai_opp_is_idle() and _opp_state() != S.PINNED:
		_ai_idle_circle(dist, toward)  # idle pacing: wait out the gap, but keep moving
		return
	if free_now and ai_backoff > 0.0:
		_ai_back_off(dist, toward, os)  # after a flurry / big move: walk away, maybe taunt
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
	if dist > 1.3:
		_ai_approach(dist, toward, can_act)
		return
	if can_act:
		# Slower, more hesitant decisions at low skill (~1.2 s apart at 0.3, ~0.6 s at 0.8).
		ai_timer = randf_range(0.6, 1.2) * (1.6 - 0.8 * ai_skill)
		var g := 0.18 + 0.3 * ai_skill   # grapple share: 0.27 at 0.3, 0.42 at 0.8
		var r := randf()
		if r < g * 0.6:
			in_grapple = true
			ai_strong_grab = false
		elif r < g:
			in_grapple = true
			ai_strong_grab = true
		elif r < g + 0.36:
			in_strike = true
		elif r < g + 0.5:
			ai_backoff = 0.45
		else:
			_ai_start_strafe()


## Backing off: walk away, sometimes play to the crowd.
func _ai_back_off(dist: float, toward: Vector2, os: int) -> void:
	if dist < 3.2:
		in_move = -toward * 0.8
	if ai_timer <= 0.0 and dist > 2.3 and taunt_cooldown <= 0.0 and os != S.PINNED:
		ai_timer = 0.5
		if randf() < 0.3:
			in_pin = true  # taunt (far from the opponent, so never a cover)


func _ai_approach(dist: float, toward: Vector2, can_act: bool) -> void:
	if ai_strafe_time > 0.0 and dist < 3.4:
		# Circle the opponent instead of beelining.
		var perp := Vector2(-toward.y, toward.x) * ai_strafe_dir
		in_move = (toward * 0.3 + perp).normalized() * 0.85
	else:
		in_move = toward
	if not can_act:
		return
	ai_timer = randf_range(0.5, 1.1) * (1.4 - 0.6 * ai_skill)
	var r := randf()
	if dist < 2.1 and randf() < 0.3 * (1.0 - ai_skill):
		in_strike = true  # low skill: swings from too far out and whiffs
		return
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
	var pin_cap: float = CPU_PIN_HP if not opponent.is_cpu else 55.0
	var pin_worthy := opp_hp < pin_cap or (tier == "finisher" and opp_hp < pin_cap + 10.0)
	if not opponent.is_cpu and opp_hp >= CPU_PIN_HP:
		pin_worthy = false  # fair pins
	# A low-skill CPU only gets a hit or two in on a downed opponent before backing off.
	var ground_cap := 1 + int(ai_skill * 3.0)
	var oground: int = opponent.ground_hits
	if not pin_worthy and oground >= ground_cap:
		ai_backoff = maxf(ai_backoff, randf_range(0.9, 1.4))
		return
	if pin_worthy:
		if dist > 1.6:
			in_move = toward
		elif can_act:
			ai_timer = 0.4 + 0.4 * (1.0 - ai_skill)
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
		elif r < 0.45 + 0.15 + 0.3 * ai_skill:
			in_grapple = true  # pick them up for more punishment
		elif r < 0.85:
			ai_backoff = randf_range(0.9, 1.4)  # let them up


func _ai_lockup_move(toward: Vector2) -> void:
	var r := randf()
	if is_special_ready() and r < 0.35 + 0.5 * ai_skill:
		in_grapple = true
		in_move = toward  # finisher
		return
	if r < 0.1 + 0.2 * ai_skill:
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
	var c := 0.08 + 0.3 * ai_skill   # 0.17 at 0.3, 0.32 at 0.8
	if reversal_kind == "strong":
		c += 0.06
	elif reversal_kind == "punch":
		c = 0.04 + 0.12 * ai_skill
	elif reversal_kind == "ender":
		c = 0.06 + 0.26 * ai_skill
	elif reversal_kind == "chain":
		c = 0.04 + 0.22 * ai_skill
	if reversal_kind in ["grapple", "strong", "whip"] and not opponent.is_cpu:
		# The human's own lock-ups: a fair clinch. Capped at 25% at match-1 skill (0.3),
		# rising to ~40% at the top of the ramp; the success roll comes on top of this.
		c = minf(c, lerpf(0.25, 0.4, clampf((ai_skill - 0.3) / 0.5, 0.0, 1.0)))
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
		S.ROLL:
			_pose_mv_roll()  # movement: dodge roll
	if held_item != null:
		_pose_hold_item()  # weapons hook: carry / hoist the item with both hands
	_apply_pose(delta)
	_apply_item_wrist(delta)
	_apply_hands(delta)  # mitt hands: open for grabs, fists otherwise


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
# Perch climbs, dives off the top, springboards off the fence / house wall and fence spots.
# The yard (main.gd, see yard_contract) provides `arena.perches`: Dictionaries {pos, approach,
# height, kind, name}. RUN near a perch's approach point climbs it; PERCHED stands at its pos; dives
# arc from there to the target (higher perch = more hang time, more points; a "trampoline" launches
# extra high, the "roof" is the biggest dive). Without an arena, the four old turnbuckles are used.
# While climbing / perched / diving / falling off, position.y may be > 0 (_hf_clamp keeps
# _clamp_ring from flattening it). Airborne wrestlers can't be pinned, grabbed or struck
# (receive_strike returns false), except that a strike within 1.4 m knocks a climbing / perched
# wrestler off the top. CORNER_STUN = whipped (diagonally) into the fence / wall, slumped against it.

const HF_CLIMB_RANGE := 1.1      # distance from a perch's approach point that allows a climb
const HF_SPRING_WINDOW := 0.45   # STRIKE / GRAB this soon after a fence rebound = fence launch
const HF_MAX_DIVE := 4.5         # nobody flies further than this (+1.5 m per metre of perch height)
const HF_GROUND_DIVES := ["backyard_splash", "moonsault", "flying_elbow", "gutter_star",
	"springboard_splash", "slingshot_senton"]
# fence / wall launches (STRIKE = springboard, GRAB = slingshot); those aimed at a standing target
# land on their feet when it moves
const HF_ROPE_LAUNCHES := ["springboard_forearm", "springboard_moonsault", "springboard_splash",
	"slingshot_senton", "slingshot_crossbody"]
const HF_FEET_LAUNCHES := ["springboard_forearm", "springboard_moonsault", "slingshot_crossbody"]
const HF_SPRING_REACH := 4.2
const HF_SLING_REACH := 5.5
const HF_ROPE_BUFFER_DIST := 0.9  # STRIKE / GRAB this close to the fence while running at it = launch on the rebound
# extra launch moves ("time" = base flight time, "height" = arc apex above the straight line)
const HF_EXTRA_MOVES := {
	"springboard_splash": {"name": "Springboard Splash!", "dmg": 13.0, "kind": "dive", "tier": "strong", "time": 0.85, "height": 1.3},
	"slingshot_senton": {"name": "SLINGSHOT SENTON!", "dmg": 14.0, "kind": "dive", "tier": "strong", "time": 0.95, "height": 1.5},
	"slingshot_crossbody": {"name": "Slingshot Crossbody!", "dmg": 12.0, "kind": "dive", "tier": "strike", "time": 0.9, "height": 1.4},
}
# BRAWL MODE: every dive becomes its super version (higher, longer, harder, named)
const HF_SUPER_NAMES := {
	"backyard_splash": "SATELLITE DISH SPLASH!!",
	"moonsault": "HARVEST MOONSAULT!!",
	"flying_elbow": "SUNDAY-BEST ELBOW!!",
	"gutter_star": "GUTTER SUPERNOVA!!!",
	"missile_dropkick": "SURFACE-TO-AIR DROPKICK!!",
	"crossbody": "WRECKING BALL CROSSBODY!!",
	"springboard_forearm": "TRAMPOLINE FOREARM!!",
	"springboard_moonsault": "SPRINGBOARD SUPERMOON!!",
	"springboard_splash": "BOUNCE HOUSE SPLASH!!",
	"slingshot_senton": "SLINGSHOT SKYSCRAPER SENTON!!",
	"slingshot_crossbody": "CATAPULT CROSSBODY!!",
}
# air tricks (see "# --- air tricks")
const AT_SPIN_RATE := 13.96      # rad/s (800 deg/s): each STRIKE adds 180
const AT_FLIP_RATE := 12.57      # rad/s (720 deg/s): each GRAB is a full 360 flip
const AT_POSE_TIME := 0.55       # PIN pose tricks: in, hold, out
const AT_START := 0.08           # tricks start once we've left the launch point
const AT_LAND_SLOP := 0.35       # rad of rotation still left at touchdown that still counts as landed
const AT_SPIN_POINTS := [0, 150, 300, 650, 1200, 1800, 2600]
const AT_POSE_POINTS := {"Spread Eagle": 250, "Porch Light": 300, "Lawn Chair": 400,
	"Air Guitar": 450, "Kiddie Pool Cannonball": 350}
const AT_CLEAN_CALLS := ["NAILED IT!", "STUCK THE LANDING!", "BUTTERED IT!", "CLEAN AS A WHISTLE!",
	"BACKYARD LEGEND!"]
const AT_BOTCH_CALLS := ["BOTCHED IT!", "EATS THE GRASS!", "BACKYARD BLOOPER!", "WIPEOUT!"]

var hf_move := ""                # DIVING: move key of the dive / launch / splash
var hf_mode := ""                # CLIMB: "up" / "down" / "jump"; PERCH_FALL: "crotch" / "fall"
var hf_perch: Dictionary = {}    # the perch we're climbing / standing on / just dove off
var hf_fence_n := Vector3.ZERO   # CORNER_STUN: outward normal of the fence / wall we're slumped on
var hf_from := Vector3.ZERO
var hf_to := Vector3.ZERO
var hf_time := 0.7               # flight / climb duration
var hf_height := 1.0             # arc apex
var hf_land_time := 0.3          # DIVING: settle time after touching down
var hf_landed := false
var hf_result := ""              # "hit" / "crash" / "feet" / "botch" once landed
var hf_end_yaw := 0.0            # visual yaw (rel. to facing) of the final lying pose
var hf_stun_time := 1.5          # CORNER_STUN duration
var hf_corner_whip := false      # current whip is a diagonal one: slams into the fence
var hf_rope_at := -10.0          # anim_clock of the last fence rebound (main.gd HUD reads it)
var hf_bounce_n := Vector3.ZERO  # outward normal of the last fence / wall rebound
var hf_fall_hit := false         # PERCH_FALL one-shot (crotch impact)
var hf_crotch_y := 0.32          # PERCH_FALL crotch: body height straddling the perch edge
var hf_super := false            # this dive is a BRAWL MODE super
var hf_dmg_mult := 1.0
var hf_pts_mult := 1.0           # bigger perch = more points
var hf_rope_buf := ""            # "strike" / "grab" pressed just before a fence rebound
var hf_rope_buf_at := -10.0
var hf_fallback_perches: Array = []
# air tricks
var at_queue: Array = []         # queued tricks (Dictionaries: kind, target, sign, front / name)
var at_cur: Dictionary = {}      # the trick being performed
var at_prog := 0.0               # its progress (rad for spins / flips, s for poses)
var at_spin := 0.0               # spin so far this air (rad, about the vertical)
var at_flip := 0.0               # current flip angle (rad, about the hips' side axis)
var at_parts := PackedStringArray()  # finished trick names, for the stacked combo name
var at_points := 0
var at_count := 0
var at_used := false
# AI
var hf_ai_wait := 0.5
var hf_ai_climb_plan := -1       # -1 undecided, 0 no, 1 heading for a perch, 2 fence launch run
var hf_ai_perch := -1
var hf_ai_spring_roll := 2.0
var hf_ai_tie_rolled := false
var hf_ai_dodge := -1
var hf_ai_plan: Array = []       # air-trick button presses [time, button, stick]
var hf_ai_rope_run := false


func is_airborne() -> bool:
	return state == S.CLIMB or state == S.PERCHED or state == S.DIVING or state == S.PERCH_FALL


func _hf_clamp() -> bool:
	if state in [S.CLIMB, S.PERCHED, S.DIVING, S.PERCH_FALL, S.CORNER_STUN]:
		var r := _yard_rect()
		var g := 0.0 if state == S.CORNER_STUN else 0.8  # perches may sit on the yard's edge
		position.x = clampf(position.x, r.position.x - g, r.end.x + g)
		position.z = clampf(position.z, r.position.y - g, r.end.y + g)
		position.y = 0.0 if state == S.CORNER_STUN else clampf(position.y, 0.0, 4.5)
		return true
	return false


func _hf_sign(v: float) -> float:
	return -1.0 if v < 0.0 else 1.0


# --- perches -------------------------------------------------------------------------------

func _hf_perches() -> Array:
	if arena != null and "perches" in arena:
		var ps: Array = arena.perches
		if not ps.is_empty():
			return ps
	if hf_fallback_perches.is_empty():
		for c in [Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)]:
			hf_fallback_perches.append({"pos": Vector3(c.x * 3.75, 1.35, c.z * 3.75),
				"approach": Vector3(c.x * 3.35, 0.0, c.z * 3.35), "height": 1.35,
				"kind": "turnbuckle", "name": "top turnbuckle"})
	return hf_fallback_perches


func _perch_pos(pr: Dictionary) -> Vector3:
	var v: Vector3 = pr.get("pos", Vector3(0.0, 1.0, 0.0))
	return v


func _perch_approach(pr: Dictionary) -> Vector3:
	var v: Vector3 = pr.get("approach", _perch_pos(pr))
	return Vector3(v.x, 0.0, v.z)


func _perch_height(pr: Dictionary) -> float:
	var h: float = pr.get("height", _perch_pos(pr).y)
	return h


func _perch_kind(pr: Dictionary) -> String:
	var k: String = pr.get("kind", "")
	return k


func _perch_name(pr: Dictionary) -> String:
	var n: String = pr.get("name", "top")
	return n


## Index of the perch whose approach point is within HF_CLIMB_RANGE (the nearest), or -1.
func _hf_near_perch(range_m := HF_CLIMB_RANGE) -> int:
	var best := -1
	var best_d := range_m
	var ps := _hf_perches()
	for i in ps.size():
		var pr: Dictionary = ps[i]
		var ap := _perch_approach(pr)
		var d := Vector3(ap.x - position.x, 0.0, ap.z - position.z).length()
		if d <= best_d:
			best_d = d
			best = i
	return best


## Index of the nearest perch (any distance), or -1 if there are none.
func _hf_nearest_perch() -> int:
	return _hf_near_perch(1000.0)


## Ground point to land on when knocked off / hopping down: out from the perch's base.
func _hf_off_point(pr: Dictionary, dist: float) -> Vector3:
	var pp := _perch_pos(pr)
	var ap := _perch_approach(pr)
	var out := Vector3(ap.x - pp.x, 0.0, ap.z - pp.z)
	if out.length() < 0.05:
		out = -Vector3(pp.x, 0.0, pp.z)
	if out.length() < 0.05:
		out = Vector3(0.0, 0.0, 1.0)
	return _col_nudge_pt(_yard_clamp_pt(ap + out.normalized() * dist, 0.4), 0.4)


func _hf_face_opp_or_center() -> void:
	var d := _flat_to_opponent()
	if d.length() < 0.05:
		d = -Vector3(position.x, 0.0, position.z)
	if d.length() > 0.01:
		_set_facing_angle(atan2(d.x, d.z))


## Takeoff call for a dive off a perch: "Off the picnic table!", "From the SHED ROOF!" ...
func _hf_perch_call(pr: Dictionary) -> String:
	match _perch_kind(pr):
		"roof":
			return "From the SHED ROOF!"
		"trampoline":
			return "Off the TRAMPOLINE!"
	return "Off the %s!" % _perch_name(pr)


## "fence" or "wall" (the house is along -z).
func _hf_edge_name(n: Vector3) -> String:
	return "wall" if n.z < -0.5 else "fence"


func _hf_tick(delta: float) -> void:
	match state:
		S.CLIMB:
			_hf_climb()
		S.PERCHED:
			_hf_perched(delta)
		S.DIVING:
			_hf_diving(delta)
		S.PERCH_FALL:
			_hf_perch_fall()
		S.CORNER_STUN:
			if state_time > hf_stun_time:
				set_state(S.IDLE)


# --- hooks called from the core state machine ----------------------------------------

## _free_move: RUN near a perch climbs it; GRAB on an opponent slumped on the fence = Super Drop.
func _hf_free_move_hook(dir: Vector3) -> bool:
	var os := _opp_state()
	if os == S.CORNER_STUN and in_grapple and _flat_to_opponent().length() < 1.6:
		_hf_super_drop()
		return true
	if not in_run:
		return false
	var i := _hf_near_perch()
	if i < 0:
		return false
	var pr: Dictionary = _hf_perches()[i]
	var pp := _perch_pos(pr)
	var to_p := Vector3(pp.x - position.x, 0.0, pp.z - position.z)
	var aimed := dir.length() < 0.3 or to_p.length() < 0.2 or dir.normalized().dot(to_p.normalized()) > 0.5
	var op: Vector3 = opponent.position
	var opp_on := Vector3(pp.x - op.x, 0.0, pp.z - op.z).length() < 1.0
	if not aimed or opp_on:
		return false
	hf_perch = pr
	_hf_start_climb("up")
	return true


## _run (non-whipped, STRIKE pressed): fence splash on a slumped opponent, or a springboard off
## the fence right after a rebound. True if handled.
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
	if anim_clock - hf_rope_at > HF_SPRING_WINDOW:
		return false
	_hf_rope_launch(false)
	return true


## _run (non-whipped, GRAB pressed) right off the fence: slingshot launch. True if handled.
func _hf_run_grab() -> bool:
	if anim_clock - hf_rope_at > HF_SPRING_WINDOW:
		return false
	_hf_rope_launch(true)
	return true


## _run: STRIKE / GRAB pressed while about to hit the fence (heading into it, close, nobody to
## lariat): remembered and launched on the rebound.
func _hf_buffer_rope_launch() -> bool:
	if _flat_to_opponent().length() < 2.8:
		return false
	var r := _yard_rect()
	var m := 0.35 + HF_ROPE_BUFFER_DIST
	var near := (position.x > r.end.x - m and run_dir.x > 0.2) or (position.x < r.position.x + m and run_dir.x < -0.2) \
		or (position.z > r.end.y - m and run_dir.z > 0.2) or (position.z < r.position.y + m and run_dir.z < -0.2)
	if not near:
		return false
	hf_rope_buf = "grab" if in_grapple else "strike"
	hf_rope_buf_at = anim_clock
	return true


## _run rebound hook: a buffered fence launch fires now.
func _hf_rope_buffered_launch() -> bool:
	if hf_rope_buf == "" or anim_clock - hf_rope_buf_at > 0.45:
		hf_rope_buf = ""
		return false
	var sling := hf_rope_buf == "grab"
	hf_rope_buf = ""
	_hf_rope_launch(sling)
	return true


## Off the fence / wall at the opponent, standing or down: STRIKE = springboard, GRAB = slingshot
## (higher, further, more hang time). Out of reach it still launches toward them and comes up short.
func _hf_rope_launch(sling: bool) -> void:
	var os := _opp_state()
	var to := _flat_to_opponent()
	var dist := to.length()
	var dir := to / dist if dist > 0.01 else facing
	var op: Vector3 = opponent.position
	var opf := Vector3(op.x, 0.0, op.z)
	var reach := HF_SLING_REACH if sling else HF_SPRING_REACH
	var ground := os == S.DOWN or _hf_opp_on_table()
	var key := ""
	var off := 0.75
	if ground and dist <= reach:
		key = "slingshot_senton" if sling else "springboard_splash"
		off = 0.3
	elif sling:
		key = "slingshot_crossbody"
		off = 0.55
	else:
		var opp_up: bool = opponent.is_standing() or os == S.CORNER_STUN
		key = "springboard_moonsault" if opp_up and dist > 1.6 and dist < 3.4 else "springboard_forearm"
		off = 0.35 if key == "springboard_moonsault" else 0.75
	var target := position + dir * minf(maxf(dist - off, 1.0), reach)
	if dist <= reach:
		target = opf - dir * off
	announce.emit("%s %s off the %s!" % [display_name, "slingshots" if sling else "springboards",
		_hf_edge_name(hf_bounce_n)])
	trick.emit("Off the %s" % _hf_edge_name(hf_bounce_n).capitalize(), 100, "movement")
	_hf_launch(key, target)


func _hf_on_rope_bounce() -> void:
	hf_rope_at = anim_clock
	hf_ai_spring_roll = randf()
	run_speed = minf(run_speed + RUN_ROPE_BOOST, RUN_TOP_SPEED)  # the fence springs us back faster


## start_whipped: a diagonal whip slams the runner into the fence / wall instead of rebounding.
func _hf_corner_whip_dir(d: Vector3) -> Vector3:
	hf_corner_whip = absf(d.x) > 0.4 and absf(d.z) > 0.4
	return d


## _run (whipped): reaching the fence on a diagonal whip = slam into it and slump.
func _hf_check_corner_crash() -> bool:
	if not hf_corner_whip or rope_bounces > 0:
		return false
	var n := _yard_hit_normal(0.5)
	if n == Vector3.ZERO:
		return false
	set_state(S.CORNER_STUN)
	hf_corner_whip = false
	hf_stun_time = 1.5
	hf_fence_n = n
	position = _col_nudge_pt(_yard_clamp_pt(position, 0.45), COL_BODY_R)
	_set_facing_angle(atan2(-n.x, -n.z))
	var concrete := _surface_here() == "concrete"
	take_damage(6.0 if concrete else 5.0)
	impact.emit(0.35)
	sfx.emit("thud_concrete" if concrete else "thud", 0.8, global_position + Vector3(0, 1.2, 0))
	sfx.emit("big_thud", 0.5, global_position + Vector3(0, 1.2, 0))
	announce.emit("Slammed into the %s!" % _hf_edge_name(n))
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
				position -= hf_fence_n * 0.6
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
	if hf_perch.is_empty():
		var i := _hf_nearest_perch()
		if i < 0:
			set_state(S.IDLE)
			return
		hf_perch = _hf_perches()[i]
	var pp := _perch_pos(hf_perch)
	var h := maxf(pp.y, 0.3)
	set_state(S.CLIMB)
	current_move_key = "climb_" + mode
	hf_mode = mode
	hf_from = position
	match mode:
		"up":
			hf_to = pp
			hf_time = 0.35 + 0.28 * h
			sfx.emit("climb", 0.6, global_position + Vector3(0, 1.0, 0))
			if _perch_kind(hf_perch) == "roof":
				announce.emit("%s is climbing onto the SHED ROOF!" % display_name)
			else:
				announce.emit("%s is going up on the %s!" % [display_name, _perch_name(hf_perch)])
			trick.emit("Going Up Top", 100, "movement")  # style hook
		"down":
			hf_to = _perch_approach(hf_perch)
			hf_time = 0.3 + 0.22 * h
			sfx.emit("climb", 0.4, global_position + Vector3(0, 1.0, 0))
		_:
			var d := _flat_to_opponent()
			var dir := d.normalized() if d.length() > 0.05 else (_perch_approach(hf_perch) - Vector3(pp.x, 0.0, pp.z)).normalized()
			hf_to = _col_nudge_pt(_yard_clamp_pt(Vector3(pp.x, 0.0, pp.z) + dir * 1.2, 0.4), 0.4)
			hf_time = 0.45 + 0.1 * h
			sfx.emit("whoosh", 0.3, _chest())
	_hf_face_opp_or_center()


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
			sfx.emit(_hf_thud("thud"), 0.3, global_position + Vector3(0, 0.2, 0))


func _hf_perched(delta: float) -> void:
	if hf_perch.is_empty():
		set_state(S.IDLE)  # safety: nothing to stand on
		position.y = 0.0
		return
	position = _perch_pos(hf_perch)
	_face_opponent(delta)
	if in_strike:
		_hf_start_dive()
	elif in_grapple:
		_hf_start_climb("jump")
	elif in_run or state_time > 8.0:
		_hf_start_climb("down")  # (8 s safety timeout)


func _hf_knock_off() -> void:
	if hf_perch.is_empty():
		var i := _hf_nearest_perch()
		if i >= 0:
			hf_perch = _hf_perches()[i]
	var kind := _perch_kind(hf_perch)
	var crotch := position.y > 0.98 and kind != "trampoline" and kind != "roof" and randf() < 0.5
	hf_crotch_y = maxf(0.0, position.y - 1.03)
	set_state(S.PERCH_FALL)
	hf_mode = "crotch" if crotch else "fall"
	current_move_key = "perch_" + hf_mode
	hf_fall_hit = false
	hf_from = position
	hf_to = _hf_off_point(hf_perch, 0.7) if not hf_perch.is_empty() else Vector3(position.x, 0.0, position.z)
	var d := Vector3(hf_to.x - position.x, 0.0, hf_to.z - position.z)
	if d.length() > 0.05:
		_set_facing_angle(atan2(d.x, d.z))
	impact.emit(0.35)
	sfx.emit("whoa", 0.8, _chest())
	if crotch:
		announce.emit("Crotched on the %s! OOF!" % _perch_name(hf_perch))
	else:
		announce.emit("Knocked off the %s!" % _perch_name(hf_perch))


func _hf_perch_fall() -> void:
	if hf_mode == "crotch":
		if state_time < 1.1:
			var d := _smooth(_seg(state_time, 0.0, 0.2))
			position = Vector3(hf_from.x, lerpf(hf_from.y, hf_crotch_y, d), hf_from.z)
			if d >= 1.0 and not hf_fall_hit:
				hf_fall_hit = true
				take_damage(4.0)
				impact.emit(0.3)
				sfx.emit("thud", 0.6, global_position + Vector3(0, 1.2, 0))
			return
		var u := _seg(state_time, 1.1, 1.6)
		var flat := Vector3(hf_from.x, 0.0, hf_from.z).lerp(hf_to, u)
		position = Vector3(flat.x, lerpf(hf_crotch_y, 0.0, _ease_in(u)), flat.z)
		if u >= 1.0:
			_hf_fall_land()
		return
	var p := _seg(state_time, 0.0, 0.55)
	var f2 := hf_from.lerp(hf_to, p)
	position = Vector3(f2.x, lerpf(hf_from.y, 0.0, p) + 1.2 * p * (1.0 - p), f2.z)
	if p >= 1.0:
		take_damage(6.0 * _surface_mult())
		_hf_fall_land()


func _hf_fall_land() -> void:
	impact.emit(0.5)
	sfx.emit(_hf_thud("big_thud"), 0.8, global_position + Vector3(0, 0.3, 0))
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


## Hard landings on the patio hurt more and sound harsher.
func _surface_mult(p := Vector3.INF) -> float:
	return 1.2 if _surface_here(p) == "concrete" else 1.0


func _hf_thud(kind: String, p := Vector3.INF) -> String:
	return "thud_concrete" if _surface_here(p) == "concrete" else kind


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


func _hf_m(key: String) -> Dictionary:
	if HF_EXTRA_MOVES.has(key):
		var e: Dictionary = HF_EXTRA_MOVES[key]
		return e
	var m: Dictionary = MOVES[key]
	return m


func _hf_name(key: String) -> String:
	if hf_super and HF_SUPER_NAMES.has(key):
		var sn: String = HF_SUPER_NAMES[key]
		return sn
	var m := _hf_m(key)
	var nm: String = m["name"]
	return nm


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
	var max_d := HF_MAX_DIVE + 1.5 * maxf(position.y, 0.0)
	if _perch_kind(hf_perch) == "trampoline":
		max_d += 1.5
	if target.distance_to(flat_from) > max_d:
		target = flat_from + dir * max_d  # too far: this one's going to hurt
	_hf_launch(key, target)


func _hf_launch(key: String, target: Vector3) -> void:
	var m := _hf_m(key)
	var from_perch := state == S.PERCHED
	var rope := key in HF_ROPE_LAUNCHES
	var base_t: float = m["time"]
	var h: float = m["height"]
	var mom := clampf((run_speed - RUN_START_SPEED) / (RUN_TOP_SPEED - RUN_START_SPEED), 0.0, 1.0)
	var perch_h := position.y
	var kind := _perch_kind(hf_perch) if from_perch else ""
	set_state(S.DIVING)
	current_move_key = key
	hf_move = key
	hf_from = position
	hf_to = _col_nudge_pt(_yard_clamp_pt(Vector3(target.x, 0.0, target.z), 0.4), 0.4)  # not inside a prop
	var d := Vector3(hf_to.x - position.x, 0.0, hf_to.z - position.z)
	var span := clampf(d.length() / 3.0, 0.85, 1.25)
	hf_super = brawl_mode and key != "corner_splash"
	hf_dmg_mult = 1.0
	hf_pts_mult = 1.0
	if from_perch:
		# big hang time off the top (~0.9-1.2 s; more off the higher perches, the roof most)
		var hk := clampf((perch_h - 0.75) / 1.65, 0.0, 1.0)
		hf_time = clampf(base_t * 1.3 * span, 0.9, 1.2) * lerpf(0.92, 1.3, hk)
		hf_height = h * lerpf(1.25, 1.6, hk)
		hf_pts_mult = clampf(0.6 + 0.5 * perch_h, 0.9, 1.8)
		hf_dmg_mult = lerpf(0.9, 1.25, hk)
		if kind == "trampoline":
			hf_time *= 1.25   # the trampoline launches extra high
			hf_height *= 1.8
			hf_pts_mult = 1.5
		announce.emit(_hf_perch_call(hf_perch))
	elif rope:
		# faster run-up = more air off the fence
		hf_time = base_t * lerpf(1.0, 1.2, mom) * span
		hf_height = h * lerpf(1.1, 1.35, mom)
	else:
		hf_time = base_t * clampf(d.length() / 3.0, 0.8, 1.35)
		hf_height = h
	if hf_super:
		hf_time *= 1.2
		hf_height *= 1.4
		hf_dmg_mult *= 1.35
	hf_landed = false
	hf_result = ""
	hf_land_time = 0.3
	_at_reset()
	match key:
		"backyard_splash", "gutter_star", "springboard_splash":
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
		sfx.emit("dive", 0.8 if from_perch or hf_super else 0.5, _chest())
	if from_perch or rope:
		sfx.emit("whoa", 0.7, _chest())
	# a downed target stays down for the (longer) flight
	if _opp_state() == S.DOWN:
		var ost: float = opponent.state_time
		var odd: float = opponent.down_duration
		opponent.down_duration = maxf(odd, ost + hf_time + 0.35)
	if key == "gutter_star":
		spirit = 0.0
		special_timer = 0.0
		sfx.emit("finisher", 1.0, _chest())
		announce.emit(_hf_name(key))  # finisher: called on takeoff (other moves on impact)
	elif hf_super:
		sfx.emit("finisher", 0.8, _chest())
		announce.emit(_hf_name(key))
	if is_cpu:
		_hf_ai_plan_tricks()


func _hf_diving(delta: float) -> void:
	var p := clampf(state_time / maxf(hf_time, 0.01), 0.0, 1.0)
	if not hf_landed:
		_at_input()
		_at_update(delta)
		var flat := hf_from.lerp(hf_to, p)
		position = Vector3(flat.x, lerpf(hf_from.y, hf_to.y, p) + 4.0 * hf_height * p * (1.0 - p), flat.z)
		if p >= 1.0:
			hf_landed = true
			position = hf_to
			_hf_land()
		return
	if state_time >= hf_time + hf_land_time or state_time > hf_time + 3.0:
		_hf_finish_dive()


## Touchdown: a trick cut short = botch; else did the target stay put? Hit, crash or feet.
func _hf_land() -> void:
	if _at_touchdown():
		_hf_botch()
		return
	_hf_land_resolve()
	if hf_result == "hit":
		var m := _hf_m(hf_move)
		var dmg: float = m["dmg"]
		var pts := int(dmg * 30.0 * hf_pts_mult * (2.0 if hf_super else 1.0))
		trick.emit(_hf_name(hf_move), pts, "super" if hf_super else "aerial")
	if hf_result == "hit" or hf_result == "feet":
		_at_clean_landing()
	else:
		trick.emit("", 0, "break")  # crash and burn: the combo is gone


## Touched down mid-trick: under-rotated onto the grass / patio.
func _hf_botch() -> void:
	hf_result = "botch"
	hf_land_time = 0.55
	at_cur = {}
	take_damage(8.0 * _surface_mult())
	var line: String = AT_BOTCH_CALLS[randi() % AT_BOTCH_CALLS.size()]
	if _surface_here() == "concrete":
		line = "EATS THE PATIO!"
	announce.emit(line)
	trick.emit("", 0, "break")
	impact.emit(0.7)
	var contact := global_position + Vector3(0, 0.4, 0)
	sfx.emit(_hf_thud("big_thud"), 1.0, contact)
	sfx.emit("whoa", 0.9, contact + Vector3(0, 1.0, 0))


func _hf_land_resolve() -> void:
	var key := hf_move
	var m := _hf_m(key)
	var dmg: float = m["dmg"]
	dmg *= hf_dmg_mult * _surface_mult()
	var tier: String = m["tier"]
	var name_txt := _hf_name(key)
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
			var on: Vector3 = opponent.hf_fence_n
			opponent.set_state(S.STUNNED)
			opponent.stun_time = 1.1
			opponent.dazed = true  # stumbles off the fence: free lock-up
			opponent.position = op - on * 0.4
			announce.emit(name_txt)
			impact.emit(0.45)
			sfx.emit("big_thud", 0.8, contact + Vector3(0, 0.8, 0))
		else:
			take_damage(5.0)
			announce.emit("Ate the %s!" % _hf_edge_name(_yard_hit_normal(1.0)))
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
			trick.emit(name_txt, _trick_pts(m), _trick_kind(m))  # style hook
			opponent.last_hit_tier = tier
			var ost: float = opponent.state_time
			var odd: float = opponent.down_duration
			opponent.down_duration = maxf(odd, ost + 2.0)
			gain_spirit(6.0)
			impact.emit(clampf(dmg / 16.0, 0.6, 1.3))
			sfx.emit(_hf_thud("big_thud"), clampf(dmg / 18.0, 0.8, 1.4), contact)
			return
	else:
		match key:
			"springboard_moonsault":
				hf_land_time = 0.5
			"crossbody", "slingshot_crossbody":
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
				sfx.emit("big_thud" if key != "springboard_forearm" else _hf_thud("thud"), 0.8, contact + Vector3(0, 0.6, 0))
				return
		elif key == "springboard_moonsault" and _opp_state() == S.DOWN and miss_by <= 1.2:
			hf_result = "hit"
			opponent.receive_ground_hit(self, dmg, key)
			announce.emit(name_txt)
			impact.emit(0.6)
			return
	# the target moved: fence launches at a standing target land on their feet ...
	if key in HF_FEET_LAUNCHES:
		hf_result = "feet"
		hf_land_time = 0.35
		if at_count == 0:
			announce.emit("Missed! Lands on the feet.")
		sfx.emit(_hf_thud("thud"), 0.4, contact)
		return
	# ... everything else crashes and burns
	hf_land_time = maxf(hf_land_time, 0.45)
	take_damage((10.0 if key in HF_GROUND_DIVES else 7.0) * _surface_mult())
	announce.emit("CRASH AND BURN!" if _surface_here() != "concrete" else "CRASH AND BURN ON THE PATIO!")
	impact.emit(0.7)
	sfx.emit(_hf_thud("big_thud"), 1.0, contact)
	sfx.emit("whoa", 0.9, contact + Vector3(0, 1.0, 0))


func _hf_finish_dive() -> void:
	var hit := hf_result == "hit"
	if hf_result == "botch":
		_hf_go_down(hf_end_yaw, _down_time() + 0.4)
		last_hit_tier = "strike"
		return
	if hf_result == "feet":
		position.y = 0.0
		set_state(S.IDLE)
		return
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
	trick.emit(name_txt, _trick_pts(m), "grapple")  # style hook
	set_state(S.THROWING)
	current_move_key = "suplex"  # reuses the suplex animation, hauled off the fence
	throw_time = m["time"]
	opponent.start_thrown(position + facing * land, m, "suplex")


# --- air tricks ----------------------------------------------------------------------
# While airborne (any dive / springboard / slingshot): STRIKE = spin (each press +180, stick
# left / right picks the direction), GRAB = flip (stick up = frontflip, else backflip; pressing it
# again during a flip the same way makes it a double, triple ...), PIN = a pose trick picked by the
# stick (none: Spread Eagle, up: Porch Light, down: Lawn Chair, left: Air Guitar, right: Kiddie
# Pool Cannonball). Tricks play one after another; each finished one scores
# trick(name, points, "air_trick"): later tricks in the same air are worth more, bigger perches
# more, BRAWL MODE double. Touching down with a spin / flip / pose still going = botch.

func _at_reset() -> void:
	at_queue.clear()
	at_cur = {}
	at_prog = 0.0
	at_spin = 0.0
	at_flip = 0.0
	at_parts = PackedStringArray()
	at_points = 0
	at_count = 0
	at_used = false


## The most recently queued trick (or the one being performed), {} if none.
func _at_last() -> Dictionary:
	if not at_queue.is_empty():
		var q: Dictionary = at_queue[at_queue.size() - 1]
		return q
	return at_cur


func _at_input() -> void:
	if hf_move == "corner_splash":
		return
	if in_strike:
		_at_press("spin")
	if in_grapple:
		_at_press("flip")
	if in_pin:
		_at_press("pose")


func _at_press(kind: String) -> void:
	at_used = true
	var last := _at_last()
	var lk: String = last.get("kind", "")
	match kind:
		"spin":
			if lk == "spin":
				var t0: float = last["target"]
				last["target"] = t0 + PI  # stack another 180
				return
			var sg := -1.0 if in_move.x > 0.3 else 1.0
			_at_enqueue({"kind": "spin", "target": PI, "sign": sg})
		"flip":
			var front := in_move.y < -0.4
			if lk == "flip":
				var lf: bool = last["front"]
				if lf == front:
					var t1: float = last["target"]
					last["target"] = t1 + TAU  # double, triple ...
					return
			_at_enqueue({"kind": "flip", "target": TAU, "front": front, "sign": 1.0 if front else -1.0})
		_:
			_at_enqueue({"kind": "pose", "name": _at_pose_name(in_move), "target": AT_POSE_TIME, "sign": 1.0})


func _at_enqueue(t: Dictionary) -> void:
	if at_queue.size() < 6:
		at_queue.append(t)


func _at_pose_name(mv: Vector2) -> String:
	if mv.length() < 0.4:
		return "Spread Eagle"
	if absf(mv.x) > absf(mv.y):
		return "Air Guitar" if mv.x < 0.0 else "Kiddie Pool Cannonball"
	return "Porch Light" if mv.y < 0.0 else "Lawn Chair"


func _at_update(delta: float) -> void:
	if state_time < AT_START:
		return
	if at_cur.is_empty():
		if at_queue.is_empty():
			return
		at_cur = at_queue.pop_front()
		at_prog = 0.0
		sfx.emit("whoosh", 0.35, _chest())
	var kind: String = at_cur["kind"]
	var target: float = at_cur["target"]
	var sg: float = at_cur["sign"]
	match kind:
		"spin":
			var step := minf(AT_SPIN_RATE * delta, target - at_prog)
			at_prog += step
			at_spin += sg * step
		"flip":
			at_prog = minf(at_prog + AT_FLIP_RATE * delta, target)
			at_flip = sg * at_prog
		_:
			at_prog = minf(at_prog + delta, target)
	if at_prog >= target - 0.0001:
		_at_complete()


func _at_complete() -> void:
	var kind: String = at_cur["kind"]
	var target: float = at_cur["target"]
	var nm := ""
	var base := 0
	match kind:
		"spin":
			var halves := int(round(target / PI))
			var deg := halves * 180
			nm = str(deg) if deg < 360 else "%d Spin" % deg
			if halves < AT_SPIN_POINTS.size():
				base = AT_SPIN_POINTS[halves]
			else:
				base = 2600 + 900 * (halves - 6)
			at_parts.append(str(deg))
		"flip":
			var n := int(round(target / TAU))
			var front: bool = at_cur["front"]
			nm = "Frontflip" if front else "Backflip"
			if n == 2:
				nm = "Double " + nm
			elif n == 3:
				nm = "Triple " + nm
			elif n > 3:
				nm = "%dx %s" % [n, nm]
			var fm := 1.0 if n <= 1 else (2.5 if n == 2 else (5.0 if n == 3 else 2.0 * n))
			base = int((550.0 if front else 600.0) * fm)
			at_flip = 0.0
			at_parts.append(nm)
		_:
			nm = at_cur["name"]
			base = AT_POSE_POINTS.get(nm, 300)
			at_parts.append(nm)
	var pts := int(float(base) * (1.0 + 0.25 * at_count) * hf_pts_mult * (2.0 if brawl_mode else 1.0))
	at_count += 1
	at_points += pts
	at_cur = {}
	at_prog = 0.0
	trick.emit(nm, pts, "air_trick")
	sfx.emit("trick", 0.6, _chest())


## Touchdown: a trick that's nearly done is finished; one cut short = botch (returns true).
## The spin so far is folded into our facing, so the landing pose carries on from it.
func _at_touchdown() -> bool:
	var botch := false
	if not at_cur.is_empty():
		var kind: String = at_cur["kind"]
		var target: float = at_cur["target"]
		var left := target - at_prog
		if left <= (0.15 if kind == "pose" else AT_LAND_SLOP):
			if kind == "spin":
				var sg: float = at_cur["sign"]
				at_spin += sg * left
			if kind == "flip":
				at_flip = 0.0
			at_prog = target
			_at_complete()
		else:
			botch = true
	at_queue.clear()
	if absf(at_spin) > 0.0001:
		_set_facing_angle(rotation.y + at_spin)
		at_spin = 0.0
	return botch


func _at_clean_landing() -> void:
	if at_count == 0:
		return
	var line: String = AT_CLEAN_CALLS[randi() % AT_CLEAN_CALLS.size()]
	var bonus := maxi(150, int(float(at_points) * 0.3))
	if at_count >= 2:
		var combo := " ".join(at_parts) + "!"
		announce.emit(combo)
		trick.emit(combo + " " + line, bonus, "air_trick")
	else:
		announce.emit(line)
		trick.emit(line, bonus, "air_trick")
	sfx.emit("trick", 1.0, _chest())


# --- AI --------------------------------------------------------------------------------

func _hf_ai(dist: float, toward: Vector2, os: int) -> bool:
	if state != S.TIEUP_ATK:
		hf_ai_tie_rolled = false
	if os != S.DIVING:
		hf_ai_dodge = -1
	if state != S.RUN and state != S.IDLE and state != S.WALK:
		hf_ai_rope_run = false
	match state:
		S.CLIMB, S.PERCH_FALL, S.CORNER_STUN, S.ROLL:
			return true
		S.DIVING:
			_hf_ai_air_tricks()  # air tricks on the way down
			return true
		S.PERCHED:
			_hf_ai_perched(dist, toward, os)
			return true
		S.TIEUP_ATK:
			if not hf_ai_tie_rolled and committed_move == "" and state_time > ai_tie_delay:
				hf_ai_tie_rolled = true
				if randf() < 0.12:
					# diagonal Irish whip: slams them into the fence
					in_run = true
					in_move = Vector2(_hf_sign(position.x), _hf_sign(position.z)).normalized()
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
			var fresh := anim_clock - hf_rope_at < 0.3
			var target_ok: bool = opponent.is_standing() or os == S.DOWN or _hf_opp_on_table()
			if fresh and (hf_ai_rope_run or hf_ai_spring_roll < 0.4) and dist > 1.2 and dist < 5.5 and target_ok:
				hf_ai_spring_roll = 2.0
				hf_ai_rope_run = false
				if randf() < 0.5:
					in_grapple = true  # slingshot
				else:
					in_strike = true   # springboard
				return true
			if hf_ai_rope_run:
				if rope_bounces == 0 and state_time < 2.5:
					return true  # straight into the fence
				hf_ai_rope_run = false
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
	# a running lariat coming: sometimes dodge-roll out of the way
	if os == S.RUN_ATTACK:
		if not mv_ai_roll_seen and dist < 3.0:
			mv_ai_roll_seen = true
			if randf() < 0.12 + 0.25 * ai_skill:
				var side := 1.0 if randf() < 0.5 else -1.0
				_mv_start_roll(Vector3(-toward.y, 0.0, toward.x) * side)
				return true
	else:
		mv_ai_roll_seen = false
	# punish an opponent slumped on the fence
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
				in_move = toward  # charge in for a splash
			else:
				in_move = toward
		elif dist > 1.4:
			in_move = toward
		return true
	# see a standing-target dive coming: sometimes sidestep or roll out of it
	if os == S.DIVING:
		var om: String = opponent.hf_move
		if dist < 4.0 and not (om in HF_GROUND_DIVES):
			if hf_ai_dodge < 0:
				hf_ai_dodge = 1 if randf() < 0.15 + 0.3 * ai_skill else 0
				if hf_ai_dodge == 1 and randf() < 0.5:
					hf_ai_dodge = 2
			if hf_ai_dodge == 2 and dist < 2.6:
				hf_ai_dodge = 1
				_mv_start_roll(Vector3(-toward.y, 0.0, toward.x))
				return true
			if hf_ai_dodge == 1:
				in_move = Vector2(-toward.y, toward.x)
		return true
	# opponent down: sometimes go up on a perch, or hit the fence for a launch
	if os != S.DOWN:
		hf_ai_climb_plan = -1
		return false
	if hf_ai_climb_plan < 0:
		var ost: float = opponent.state_time
		var odd: float = opponent.down_duration
		var left := odd - ost
		hf_ai_perch = _hf_near_perch(3.5)
		hf_ai_climb_plan = 1 if hf_ai_perch >= 0 and left > 1.6 and randf() < 0.28 else 0
		if hf_ai_climb_plan == 0 and left > 1.8 and dist < 4.5 and randf() < 0.22:
			hf_ai_climb_plan = 2
	if hf_ai_climb_plan == 1:
		var ps := _hf_perches()
		if hf_ai_perch < 0 or hf_ai_perch >= ps.size():
			hf_ai_climb_plan = 0
			return false
		var pr: Dictionary = ps[hf_ai_perch]
		var ap := _perch_approach(pr)
		var dc2 := Vector3(ap.x - position.x, 0.0, ap.z - position.z)
		if dc2.length() > 0.05:
			in_move = Vector2(dc2.x, dc2.z).normalized()
		if dc2.length() < HF_CLIMB_RANGE * 0.8 and ai_react <= 0.0:
			in_move = Vector2.ZERO  # RUN standing still at a perch = climb
			in_run = true
			hf_ai_climb_plan = 0
		return true
	if hf_ai_climb_plan == 2:
		if ai_react <= 0.0:
			hf_ai_climb_plan = 0
			hf_ai_rope_run = true
			in_run = true
			in_move = -toward  # hit the fence behind us, launch off it
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


## On takeoff: maybe plan a few air tricks that fit the hang time (the less skilled sometimes
## reach for one too many and botch).
func _hf_ai_plan_tricks() -> void:
	hf_ai_plan.clear()
	if hf_move == "corner_splash":
		return
	var chance := 0.85 if brawl_mode else 0.3 + 0.35 * ai_skill
	if randf() >= chance:
		return
	var budget := hf_time - lerpf(0.2, 0.06, ai_skill)
	var greedy := randf() < 0.3 - 0.2 * ai_skill
	var t := AT_START
	var prev := ""
	for i in range(3):
		var kind := "pose"
		var r := randf()
		if r < 0.45 and prev != "spin":
			kind = "spin"
		elif r < 0.75 and prev != "flip":
			kind = "flip"
		var halves := 2 + randi() % 3
		var dur := AT_POSE_TIME
		if kind == "spin":
			dur = float(halves) * PI / AT_SPIN_RATE
		elif kind == "flip":
			dur = TAU / AT_FLIP_RATE
		var over := t + dur > budget
		if over and not greedy:
			if kind == "spin" and t + 2.0 * PI / AT_SPIN_RATE <= budget:
				halves = 2
				dur = 2.0 * PI / AT_SPIN_RATE
				over = false
			else:
				break
		match kind:
			"spin":
				var sx := -1.0 if randf() < 0.5 else 1.0
				for k in range(halves):
					hf_ai_plan.append([t + 0.07 * k, "strike", Vector2(sx, 0.0)])
			"flip":
				hf_ai_plan.append([t, "grab", Vector2(0.0, -1.0 if randf() < 0.4 else 1.0)])
			_:
				var dirs := [Vector2.ZERO, Vector2(0.0, -1.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0), Vector2(1.0, 0.0)]
				hf_ai_plan.append([t, "pin", dirs[randi() % dirs.size()]])
		t += dur + 0.03
		prev = kind
		if over:
			break


func _hf_ai_air_tricks() -> void:
	if hf_ai_plan.is_empty() or hf_landed:
		return
	var e: Array = hf_ai_plan[0]
	var t0: float = e[0]
	if t0 > state_time:
		return
	hf_ai_plan.pop_front()
	var btn: String = e[1]
	var mv: Vector2 = e[2]
	in_move = mv
	match btn:
		"strike":
			in_strike = true
		"grab":
			in_grapple = true
		_:
			in_pin = true



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
		"slingshot_senton":
			# slung up, then a forward 3/4 flip onto the back
			return [[0.0, 0.72, _qe(0.0, 0.3)], [0.25, 0.95, _qe(0.0, 0.5 * PI)], [0.5, 0.95, _qe(0.0, PI)],
				[0.75, 0.8, _qe(0.0, 1.25 * PI)], [1.0, 0.42, _qe(0.0, 1.5 * PI)]]
		"backyard_splash", "springboard_splash":
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
		"crossbody", "slingshot_crossbody":
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
	_pose_hf_dive_body()
	_pose_at_overlay()


func _pose_hf_dive_body() -> void:
	var hop := hf_move == "springboard_forearm" or hf_move == "corner_splash"
	if hop and hf_result != "botch":
		_pose_hf_hop()
		if at_used:
			_at_hop_to_basis()  # so air tricks can turn the body
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
	q0 = (Quaternion(Vector3.RIGHT, at_flip) * q0).normalized()  # a botched flip lands where it got to
	var y0: float = last[1]
	var u := clampf((state_time - hf_time) / maxf(hf_land_time, 0.01), 0.0, 1.0)
	var q1 := _qe(hf_end_yaw, -PI / 2)
	var y1 := LIE_Y
	var w := _smooth(_seg(u, 0.35, 1.0))
	var wy := w
	if hf_result == "feet":
		# missed: tuck it and come down on the feet in a crouch
		q1 = Quaternion.IDENTITY
		y1 = 0.8
		w = _smooth(_seg(u, 0.0, 0.6))
		wy = w
	elif hf_move == "crossbody":
		w = _ease_in(_seg(u, 0.0, 0.8))
		wy = w
		if hf_result == "hit":
			q1 = _qe(0.0, 1.35)
			y1 = PIN_Y
	elif hf_result == "crash" or hf_result == "botch":
		wy = _smooth(_seg(u, 0.0, 0.2))  # nobody to land on: straight to the ground
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
	if hf_result == "feet":
		pt_ll = Vector3(-0.55, 0.0, -0.18)
		pt_lr = Vector3(-0.35, 0.0, 0.18)
		pt_kn_l = 1.1
		pt_kn_r = 0.9
		pt_al = Vector3(-1.2, 0.0, -1.1)
		pt_ar = Vector3(-1.2, 0.0, 1.1)
		pt_tor = Vector3(0.35, 0.0, 0.0)
		pt_hd = Vector3(-0.3, 0.0, 0.0)
		r_limb = 18.0


## Springboard forearm with tricks: express the hop pose as a pelvis basis (spins / flips go on it).
func _at_hop_to_basis() -> void:
	var y := pt_root_pos.y
	if pt_auto_height:
		y = maxf(_leg_drop(-pt_ll.x, pt_kn_l, pt_ll.z), _leg_drop(-pt_lr.x, pt_kn_r, pt_lr.z))
	y += pt_root_dy
	pt_use_basis = true
	throw_pose_q = Quaternion(Basis.from_euler(pt_root_rot))
	throw_pose_y = y
	pt_basis_off = Vector3(pt_root_pos.x, 0.0, pt_root_pos.z)


## Air tricks on top of the dive's own keys: the spin about the vertical, the flip about the hips'
## side axis, and the limbs of whatever trick is going (keyframed in / hold / out).
func _pose_at_overlay() -> void:
	if not pt_use_basis or hf_landed:
		return
	if not at_cur.is_empty():
		var kind: String = at_cur["kind"]
		var tgt: float = at_cur["target"]
		match kind:
			"spin":
				# arms wrapped across the chest, legs together: a tight, fast spin
				var w := _smooth(_seg(at_prog, 0.0, 0.5)) * (1.0 - _smooth(_seg(at_prog, tgt - 0.5, tgt)))
				pt_al = pt_al.lerp(Vector3(-1.2, 0.0, 0.35), w)
				pt_ar = pt_ar.lerp(Vector3(-1.2, 0.0, -0.35), w)
				pt_el_l = pt_el_l.lerp(Vector3(-1.9, 0.0, 0.0), w)
				pt_el_r = pt_el_r.lerp(Vector3(-1.9, 0.0, 0.0), w)
				pt_ll = pt_ll.lerp(Vector3(-0.15, 0.0, 0.03), w)
				pt_lr = pt_lr.lerp(Vector3(-0.15, 0.0, -0.03), w)
				pt_kn_l = lerpf(pt_kn_l, 0.35, w)
				pt_kn_r = lerpf(pt_kn_r, 0.35, w)
				pt_hd.x = lerpf(pt_hd.x, -0.2, w)
				r_limb = 24.0
			"flip":
				# tuck tight through the flip, open out to finish it
				var w := _smooth(_seg(at_prog, 0.0, 0.6)) * (1.0 - _smooth(_seg(at_prog, tgt - 0.9, tgt)))
				pt_ll = pt_ll.lerp(Vector3(-2.0, 0.0, -0.1), w)
				pt_lr = pt_lr.lerp(Vector3(-2.0, 0.0, 0.1), w)
				pt_kn_l = lerpf(pt_kn_l, 2.2, w)
				pt_kn_r = lerpf(pt_kn_r, 2.2, w)
				pt_al = pt_al.lerp(Vector3(-1.3, 0.0, -0.3), w)
				pt_ar = pt_ar.lerp(Vector3(-1.3, 0.0, 0.3), w)
				pt_el_l = pt_el_l.lerp(Vector3(-1.2, 0.0, 0.0), w)
				pt_el_r = pt_el_r.lerp(Vector3(-1.2, 0.0, 0.0), w)
				pt_tor.x = lerpf(pt_tor.x, 0.5, w)
				pt_hd.x = lerpf(pt_hd.x, 0.4, w)
				r_limb = 26.0
			_:
				var nm: String = at_cur["name"]
				_pose_at_trick(nm)
	var q := Quaternion(Vector3.UP, at_spin) * Quaternion(Vector3.RIGHT, at_flip)
	throw_pose_q = (q * throw_pose_q).normalized()


## The PIN pose tricks (limbs + the body attitude each reads best in), blended in / out.
func _pose_at_trick(nm: String) -> void:
	var t := at_prog
	var w := _smooth(_seg(t, 0.0, 0.12)) * (1.0 - _smooth(_seg(t, AT_POSE_TIME - 0.12, AT_POSE_TIME)))
	var ac := anim_clock
	var al := pt_al
	var ar := pt_ar
	var el_l := pt_el_l
	var el_r := pt_el_r
	var ll := pt_ll
	var lr := pt_lr
	var kl := pt_kn_l
	var kr := pt_kn_r
	var tor := pt_tor
	var hd := pt_hd
	var pref := throw_pose_q
	var pw := 0.0
	match nm:
		"Spread Eagle":
			# a big X: arms and legs straight out, chest arched
			al = Vector3(-0.25, 0.0, -1.55)
			ar = Vector3(-0.25, 0.0, 1.55)
			el_l = Vector3(-0.05, 0.0, 0.0)
			el_r = el_l
			ll = Vector3(0.05, 0.0, -0.55)
			lr = Vector3(0.05, 0.0, 0.55)
			kl = 0.08
			kr = 0.08
			tor = Vector3(-0.2, 0.0, 0.0)
			hd = Vector3(-0.5, 0.0, 0.0)
		"Porch Light":
			# upright, right arm reaching straight for the sky, left hand on the hip, one knee up
			ar = Vector3(-3.05, 0.0, 0.12)
			el_r = Vector3(-0.05, 0.0, 0.0)
			al = Vector3(0.15, 0.0, -0.4)
			el_l = Vector3(-1.7, 0.0, 0.0)
			ll = Vector3(-0.1, 0.0, -0.05)
			kl = 0.1
			lr = Vector3(-1.0, 0.0, 0.1)
			kr = 1.7
			tor = Vector3(-0.1, 0.0, 0.0)
			hd = Vector3(-0.6, 0.0, 0.0)
			pref = _qe(0.0, -0.1)
			pw = 0.85
		"Lawn Chair":
			# kicked back in mid-air: seated, legs crossed, hands behind the head
			ll = Vector3(-1.55, 0.0, 0.14)
			lr = Vector3(-1.4, 0.0, -0.05)
			kl = 1.45
			kr = 1.35
			al = Vector3(-2.7, 0.0, -0.8)
			ar = Vector3(-2.7, 0.0, 0.8)
			el_l = Vector3(-2.4, 0.0, 0.0)
			el_r = el_l
			tor = Vector3(-0.15, 0.0, 0.05 * sin(ac * 6.0))
			hd = Vector3(0.15, 0.0, 0.0)
			pref = _qe(0.0, -0.5)
			pw = 0.85
		"Air Guitar":
			# knees bent, left hand up the neck, right hand strumming, head banging
			ll = Vector3(-0.7, 0.0, -0.3)
			kl = 1.3
			lr = Vector3(-0.2, 0.0, 0.25)
			kr = 0.6
			al = Vector3(-1.35, 0.0, -0.7)
			el_l = Vector3(-0.35, 0.0, 0.0)
			ar = Vector3(-0.6 + 0.3 * sin(ac * 28.0), 0.0, 0.3)
			el_r = Vector3(-1.5, 0.0, 0.0)
			tor = Vector3(0.3, 0.25, 0.0)
			hd = Vector3(0.25 + 0.35 * sin(ac * 14.0), 0.0, 0.0)
			pref = _qe(0.0, -0.05)
			pw = 0.85
		_:
			# "Kiddie Pool Cannonball": balled up, hugging the shins
			ll = Vector3(-2.3, 0.0, -0.12)
			lr = Vector3(-2.3, 0.0, 0.12)
			kl = 2.4
			kr = 2.4
			al = Vector3(-1.0, 0.0, 0.2)
			ar = Vector3(-1.0, 0.0, -0.2)
			el_l = Vector3(-1.9, 0.0, 0.0)
			el_r = el_l
			tor = Vector3(0.7, 0.0, 0.0)
			hd = Vector3(0.5, 0.0, 0.0)
			pref = _qe(0.0, 0.3)
			pw = 0.85
	pt_al = pt_al.lerp(al, w)
	pt_ar = pt_ar.lerp(ar, w)
	pt_el_l = pt_el_l.lerp(el_l, w)
	pt_el_r = pt_el_r.lerp(el_r, w)
	pt_ll = pt_ll.lerp(ll, w)
	pt_lr = pt_lr.lerp(lr, w)
	pt_kn_l = lerpf(pt_kn_l, kl, w)
	pt_kn_r = lerpf(pt_kn_r, kr, w)
	pt_tor = pt_tor.lerp(tor, w)
	pt_hd = pt_hd.lerp(hd, w)
	throw_pose_q = throw_pose_q.slerp(pref, w * pw).normalized()
	r_limb = 26.0
	r_body = 22.0


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
		"backyard_splash", "springboard_splash":
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
		"moonsault", "springboard_moonsault", "gutter_star", "slingshot_senton":
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
		"crossbody", "slingshot_crossbody":
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


# ---- movement & air tricks
# (The air tricks themselves live in "# --- air tricks" of the high-flying section.)
# Momentum sprint: a run starts at RUN_START_SPEED and builds to RUN_TOP_SPEED over ~1 s ("Full
# Steam"); a fence rebound adds RUN_ROPE_BOOST, hard turns bleed speed. Whipped runs keep RUN_SPEED.
# Dodge roll: double-tap RUN (the second press within ROLL_DOUBLE_TAP of starting the run) rolls
# toward the stick (no stick = backward, away from the opponent). A roll isn't "standing", so
# strikes, grabs and dives pass through it; slipping an attack mid-roll = "Close Shave!".
# The yard: `arena.yard_bounds` (Rect2 over x / z) replaces the ring: the clamp, and the fence /
# house-wall rebounds (_mv_fence_bounce). `arena.surface_at(p)` = "grass" / "concrete".

const RUN_START_SPEED := 4.6
const RUN_TOP_SPEED := 8.6
const RUN_ACCEL := 4.2           # ~1 s from a standing start to full steam
const RUN_ROPE_BOOST := 0.6
const ROLL_TIME := 0.5
const ROLL_DIST := 2.4
const ROLL_DOUBLE_TAP := 0.3
const YARD_BOUNCE_MARGIN := 0.35 # runners rebound this far inside the yard's edge

var arena = null                 # the match (main.gd): yard_bounds, perches, surface_at(); may be null
var run_speed := RUN_START_SPEED
var mv_full_steam := false
var mv_roll_dir := Vector3.ZERO
var mv_roll_shave := false
var mv_ai_roll_seen := false


func _yard_rect() -> Rect2:
	if arena != null and "yard_bounds" in arena:
		var r: Rect2 = arena.yard_bounds
		if r.size.x > 1.0 and r.size.y > 1.0:
			return r
	return Rect2(-RING_CLAMP, -RING_CLAMP, 2.0 * RING_CLAMP, 2.0 * RING_CLAMP)


func _yard_clamp_pt(p: Vector3, inset: float) -> Vector3:
	var r := _yard_rect()
	return Vector3(clampf(p.x, r.position.x + inset, r.end.x - inset), p.y,
		clampf(p.z, r.position.y + inset, r.end.y - inset))


## Outward normal of the yard edge we're within `margin` of and running into (run_dir), or ZERO.
func _yard_hit_normal(margin: float) -> Vector3:
	var r := _yard_rect()
	var n := Vector3.ZERO
	if position.x >= r.end.x - margin and run_dir.x > 0.0:
		n.x = 1.0
	elif position.x <= r.position.x + margin and run_dir.x < 0.0:
		n.x = -1.0
	if position.z >= r.end.y - margin and run_dir.z > 0.0:
		n.z = 1.0
	elif position.z <= r.position.y + margin and run_dir.z < 0.0:
		n.z = -1.0
	return n.normalized() if n != Vector3.ZERO else n


func _surface_here(p := Vector3.INF) -> String:
	var q := position if not p.is_finite() else p
	if arena != null and arena.has_method("surface_at"):
		var s: String = arena.surface_at(q)
		return s
	return "grass"


## _run: rebound off the fence / house wall. Returns true if we bounced this frame.
func _mv_fence_bounce() -> bool:
	var n := _yard_hit_normal(YARD_BOUNCE_MARGIN)
	if n == Vector3.ZERO:
		return false
	if n.x != 0.0:
		run_dir.x = -run_dir.x
	if n.z != 0.0:
		run_dir.z = -run_dir.z
	hf_bounce_n = n
	return true


func _mv_start_run() -> void:
	run_speed = RUN_START_SPEED
	mv_full_steam = false
	hf_rope_buf = ""
	flow_ai_boost = is_cpu and randf() < ai_skill * 0.5  # flow & boost: CPU boosts some runs


func _mv_run_speed(delta: float) -> float:
	var boost := _flow_boost(delta)  # flow & boost hook: RUN held + hype = boost sprint
	var top := RUN_TOP_SPEED * boost
	if run_speed > top:
		run_speed = maxf(top, run_speed - BOOST_DECEL * delta)  # boost over: ease back down
	else:
		var acc := RUN_ACCEL * (BOOST_ACCEL if boost > 1.0 else 1.0)
		run_speed = clampf(run_speed + acc * delta, RUN_START_SPEED * 0.8, top)
	if not mv_full_steam and run_speed >= RUN_TOP_SPEED - 0.01:
		mv_full_steam = true
		trick.emit("Full Steam", 100, "movement")
	if boosting and not _boost_top and run_speed >= top - 0.01:
		_boost_top = true
		trick.emit("Afterburner", 150, "movement")
	return run_speed


## Hard turns while running bleed momentum.
func _mv_turn_bleed(want: Vector3, delta: float) -> void:
	var d := run_dir.dot(want)
	if d < 0.3:
		run_speed = maxf(RUN_START_SPEED, run_speed - (0.3 - d) * 7.0 * delta)


## _run: RUN pressed again right after starting the run = dodge roll. True if handled.
func _mv_run_input(_delta: float) -> bool:
	if not (in_run and state_time < ROLL_DOUBLE_TAP):
		return false
	var dir := Vector3(in_move.x, 0.0, in_move.y)
	if dir.length() < 0.3:
		dir = -_flat_to_opponent()
	_mv_start_roll(dir)
	return true


func _mv_start_roll(dir: Vector3) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length() < 0.1:
		d = -facing
	mv_roll_dir = d.normalized()
	set_state(S.ROLL)
	current_move_key = "roll"
	mv_roll_shave = false
	sfx.emit("whoosh", 0.4, _chest())


func _mv_roll(delta: float) -> void:
	var u := clampf(state_time / ROLL_TIME, 0.0, 1.0)
	# fast out of the gate, easing off: covers ROLL_DIST in ROLL_TIME
	position += mv_roll_dir * (2.0 * ROLL_DIST / ROLL_TIME) * (1.0 - u) * delta
	if not mv_roll_shave and _flat_to_opponent().length() < 2.2 \
			and _opp_state() in [S.PUNCH, S.RUN_ATTACK, S.DIVING, S.SWING, S.GRAB_WINDUP, S.GROUND_DROP]:
		mv_roll_shave = true
		trick.emit("Close Shave!", 250, "movement")
		announce.emit("CLOSE SHAVE!")
	if state_time >= ROLL_TIME:
		set_state(S.IDLE)


## Tucked shoulder roll toward mv_roll_dir: the body turns into the roll (or rolls backward when
## going away from where it faces), pivoting about the middle of the ball, then pops back up.
func _pose_mv_roll() -> void:
	var t := state_time
	var ld := basis.inverse() * mv_roll_dir
	ld.y = 0.0
	var back := ld.z < -0.3
	var yaw := atan2(-ld.x, -ld.z) if back else atan2(ld.x, ld.z)
	var turn := _smooth(_seg(t, 0.0, 0.08)) * (1.0 - _smooth(_seg(t, ROLL_TIME - 0.1, ROLL_TIME)))
	var a := TAU * _smooth(_seg(t, 0.04, ROLL_TIME - 0.08))
	var tk := _smooth(_seg(t, 0.0, 0.1)) * (1.0 - _smooth(_seg(t, ROLL_TIME - 0.12, ROLL_TIME)))
	var q := (Quaternion(Vector3.UP, yaw * turn) * Quaternion(Vector3.RIGHT, -a if back else a)).normalized()
	pt_use_basis = true
	throw_pose_q = q
	var c_local := Vector3(0.0, 0.25, 0.12) * tk
	throw_pose_y = lerpf(STAND_Y, 0.62, tk)
	pt_basis_off = -(q * c_local)
	_stance(0.6)
	pt_ll = pt_ll.lerp(Vector3(-2.1, 0.0, -0.1), tk)
	pt_lr = pt_lr.lerp(Vector3(-2.0, 0.0, 0.1), tk)
	pt_kn_l = lerpf(pt_kn_l, 2.3, tk)
	pt_kn_r = lerpf(pt_kn_r, 2.3, tk)
	pt_al = Vector3(-0.6, 0.0, -0.3).lerp(Vector3(-1.1, 0.0, -0.2), tk)
	pt_ar = Vector3(-0.6, 0.0, 0.3).lerp(Vector3(-1.1, 0.0, 0.2), tk)
	pt_el_l = Vector3(-1.4, 0.0, 0.0).lerp(Vector3(-1.8, 0.0, 0.0), tk)
	pt_el_r = pt_el_l
	pt_tor = Vector3(0.7 * tk, 0.0, 0.0)
	pt_hd = Vector3(0.6 * tk, 0.0, 0.0)
	r_limb = 30.0
	r_body = 26.0


# ---- flow & boost (G1)
# The arcade loop: style -> hype -> BOOST -> bigger tricks.
# BOOST: HOLD RUN while running with hype in the tank = boost sprint: top speed x BOOST_MULT, faster
#   acceleration, burns BOOST_BURN hype (spirit) per second (free in BRAWL MODE). Needs BOOST_MIN
#   hype to light. Emits sfx "boost_start" once and "boost" every BOOST_SFX_EVERY s (trail / audio
#   hooks); hitting boost top speed scores "Afterburner". The 5 s run timeout is held while boosting.
# CANCEL FLOW: every move that lands (a trick with points, not "movement") opens a FLOW_WINDOW s
#   flow window (a throw opens it again when it lands). Pressing STRIKE / GRAB / RUN in it cancels
#   the recovery into the next move (strike->grab, throw->run / stomp / pick-up, dive landing->run
#   or climb), scoring "+FLOW" (a quick run of cancels scores "+FLOW 2", "+FLOW 3" ... more each
#   time), which also keeps the style combo alive. Strike strings and grapple chains keep their own
#   presses (no cancel), but a late, in-window string-to-grab counts as a flow cancel too.
#   A flow-cancelled run starts near full steam.
# TWEAK: HOLD PIN during a strike / running attack / throw / dive or air trick = "tweaked": the move
#   plays at TWEAK_SPEED (the throw victim too) and, if it landed, scores a "Tweak" bonus on top.
# COMBO COAST (style.gd): flow_moving_fast() holds the combo timer for up to 1.5 s extra.
# CPU: rolls (by ai_skill) to boost a run, flow-cancel into a stomp / run, and tweak moves.
# HUD reads: boosting, flow_window, tweaking (and flow_chain, boost_time).

const BOOST_MULT := 1.35         # boost top speed vs RUN_TOP_SPEED
const BOOST_ACCEL := 2.4         # x RUN_ACCEL while boosting
const BOOST_DECEL := 5.0         # m/s^2 back down to normal top speed once the boost stops
const BOOST_BURN := 9.0          # hype per second
const BOOST_MIN := 6.0           # hype needed to light the boost
const BOOST_CPU_MIN := 25.0      # CPU keeps some hype for finishers
const BOOST_SFX_EVERY := 0.35
const FLOW_WINDOW := 0.25
const FLOW_POINTS := 120
const FLOW_CHAIN_POINTS := 60    # per earlier cancel in a quick run of them (up to 5)
const FLOW_CHAIN_GAP := 2.5      # cancels further apart than this start a new run
const TWEAK_SPEED := 0.82        # tweaked moves play at this speed
const TWEAK_MIN := 0.12          # PIN held at least this long in the move
const TWEAK_BONUS := 0.4         # x the move's points
const TWEAK_STATES := [S.PUNCH, S.RUN_ATTACK, S.THROWING, S.DIVING]
const FLOW_FROM := [S.IDLE, S.WALK, S.PUNCH, S.RUN_ATTACK, S.THROWING, S.STOMP, S.DIVING]
const FLOW_NOT_MOVES := [S.IDLE, S.WALK, S.STUNNED, S.WHIFF, S.DOWN, S.TAUNT, S.PINNING]

var in_run_held := false         # human: RUN held (main.gd)
var in_pin_held := false         # human: PIN held (main.gd)
var boosting := false            # HUD / FX: boost sprint on
var boost_time := 0.0            # seconds into the current boost
var flow_window := 0.0           # HUD: > 0 while a flow cancel is possible
var flow_chain := 0              # flow cancels in the current quick run
var tweaking := false            # HUD: the current move is being tweaked (PIN held)
var flow_ai_boost := false       # CPU: boost this run
var _boost_sfx_t := 0.0
var _boost_top := false
var _flow_hooked := false
var _flow_last_at := -10.0
var _flow_cancelled := false
var _flow_ai_rolled := false
var _flow_ai_tweak := false
var _fl_prev := -1
var _fl_chain := 0
var _fl_press := false
var _fl_throw_open := false
var _tw_time := 0.0              # PIN held in the current move
var _tw_real := 0.0              # real seconds in the current state
var _tw_pts := 0                 # last landed trick (for the Tweak bonus)
var _tw_kind := "strike"
var _tw_at := -10.0


## style.gd: moving fast keeps the combo timer from running out (combo coasting).
func flow_moving_fast() -> bool:
	if boosting or state == S.ROLL:
		return true
	if state == S.RUN and not whipped:
		return run_speed >= RUN_TOP_SPEED - 1.5
	return state == S.DIVING and not hf_landed


## tick, before the state machine: timers, tweak, CPU flow, and the flow cancel itself.
func _flow_pre(delta: float) -> void:
	if not _flow_hooked:
		_flow_hooked = true
		trick.connect(_flow_on_trick)
	_tw_real += delta
	flow_window = maxf(0.0, flow_window - delta)
	_fl_prev = state
	_fl_chain = chain_link
	_flow_cancelled = false
	if state == S.THROWING and not _fl_throw_open and state_time >= throw_time:
		_fl_throw_open = true  # the throw just landed: a fresh window to cancel its recovery
		flow_window = FLOW_WINDOW
		_flow_ai_rolled = false
	_flow_tweak_tick(delta)
	if is_cpu:
		_flow_ai()
	_fl_press = in_strike or in_grapple or in_run
	if flow_window <= 0.0 or not _fl_press:
		return
	var btn := "run" if in_run else ("strike" if in_strike else "grab")  # _free_move's priority
	if _flow_cancel_ok(btn):
		if state == S.DIVING:
			position.y = 0.0
		chain_buf = ""
		string_step = 0
		set_state(S.IDLE)  # _free_move now starts the next move from this very press
		_flow_cancelled = true


## tick, after the state machine: a press in the window that started a new move = +FLOW.
func _flow_post() -> void:
	var started := _flow_cancelled or (state != _fl_prev and _fl_prev in FLOW_FROM)
	if not (_fl_press and flow_window > 0.0 and started):
		return
	if chain_link != _fl_chain or state in FLOW_NOT_MOVES:
		return  # grapple chains score themselves
	if anim_clock - _flow_last_at > FLOW_CHAIN_GAP:
		flow_chain = 0
	flow_chain += 1
	_flow_last_at = anim_clock
	flow_window = 0.0
	var pts := FLOW_POINTS + FLOW_CHAIN_POINTS * mini(flow_chain - 1, 5)
	trick.emit("+FLOW" if flow_chain == 1 else "+FLOW %d" % mini(flow_chain, 6), pts, "movement")
	sfx.emit("flow", 0.6, _chest())
	if state == S.RUN:
		run_speed = maxf(run_speed, RUN_TOP_SPEED - 0.6)  # cancelled into a run: keep the momentum


## Can a press of btn ("strike" / "grab" / "run") cancel the current recovery?
func _flow_cancel_ok(btn: String) -> bool:
	if opponent == null or _opp_state() == S.JUGGLED:
		return false  # juggle follow-ups own those presses
	match state:
		S.PUNCH:
			if not STRIKES.has(current_move_key) or not strike_hit:
				return false
			var st: Dictionary = STRIKES[current_move_key]
			if state_time < float(st["hit"]) + 0.03:
				return false
			if btn == "run":
				return true
			return bool(st.get("ender", false))  # mid-string presses belong to the string
		S.RUN_ATTACK:
			return hit_landed and state_time >= 0.3
		S.THROWING:
			if state_time < throw_time:
				return false
			if btn == "run":
				return true
			var nexts: Dictionary = CHAINS.get(_strip_super(current_move_key), {})
			return not (chain_link < CHAIN_MAX and nexts.has(btn))  # chain links win
		S.STOMP:
			return hit_landed and state_time >= 0.3 and btn != "strike"  # no stomp-cancel loops
		S.DIVING:
			if not hf_landed:
				return false
			return hf_result == "feet" or (hf_result == "hit" and hf_move in ["springboard_forearm", "corner_splash"])
	return false


## trick signal (our own): landed moves open the flow window and remember points for a Tweak.
func _flow_on_trick(_trick_name_s: String, points: int, kind: String) -> void:
	if kind == "break":
		flow_window = 0.0
		flow_chain = 0
		_tw_pts = 0
		return
	if points <= 0 or kind == "movement" or _trick_name_s == "Tweak":
		return
	flow_window = FLOW_WINDOW
	_flow_ai_rolled = false
	_tw_pts = points
	_tw_kind = kind
	_tw_at = anim_clock


## set_state hook (called before the state changes): finish a tweak, reset per-move flow state.
func _flow_on_state(new_s: int) -> void:
	if new_s != S.RUN:
		boosting = false
	if state in TWEAK_STATES and _tw_time >= TWEAK_MIN and _tw_pts > 0 \
			and anim_clock - _tw_at <= _tw_real + 0.05:
		var bonus := clampi(int(float(_tw_pts) * TWEAK_BONUS), 50, 600)
		var kind := _tw_kind
		_tw_pts = 0
		_tw_time = 0.0
		trick.emit("Tweak", bonus, kind)
	_tw_time = 0.0
	_tw_real = 0.0
	tweaking = false
	_fl_throw_open = false
	_flow_ai_tweak = is_cpu and new_s in TWEAK_STATES and randf() < ai_skill * 0.35


## Held PIN (CPU: rolled per move) during a tweakable move: slow it a touch.
func _flow_tweak_tick(delta: float) -> void:
	var held := _flow_ai_tweak if is_cpu else in_pin_held
	tweaking = held and state in TWEAK_STATES and not (state == S.DIVING and hf_landed)
	if not tweaking:
		return
	_tw_time += delta
	var slow := delta * (1.0 - TWEAK_SPEED)
	state_time -= slow
	if state == S.THROWING and opponent != null and _opp_state() == S.THROWN:
		opponent.state_time -= slow  # the victim's flight stays in sync with our throw


## _mv_run_speed: boost sprint. Returns the top-speed multiplier.
func _flow_boost(delta: float) -> float:
	var want := flow_ai_boost if is_cpu else in_run_held
	var need := 0.0 if boosting else (BOOST_CPU_MIN if is_cpu else BOOST_MIN)
	var fuel := brawl_mode or spirit > need
	var was := boosting
	boosting = want and fuel and state == S.RUN and not whipped
	if not boosting:
		return 1.0
	if not was:
		boost_time = 0.0
		_boost_top = false
		_boost_sfx_t = BOOST_SFX_EVERY
		sfx.emit("boost_start", 0.8, _chest())
	boost_time += delta
	if not brawl_mode:
		spirit = maxf(0.0, spirit - BOOST_BURN * delta)
	_boost_sfx_t -= delta
	if _boost_sfx_t <= 0.0:
		_boost_sfx_t = BOOST_SFX_EVERY
		sfx.emit("boost", 0.5, global_position + Vector3(0, 0.8, 0))
	state_time = minf(state_time, 4.5)  # the run doesn't time out while boosting
	return BOOST_MULT


## CPU: once per flow window, maybe cancel into a stomp (close) or a run at the downed opponent.
func _flow_ai() -> void:
	if flow_window <= 0.0 or _flow_ai_rolled or not (state in FLOW_FROM) or state in [S.IDLE, S.WALK]:
		return
	var od := _opp_state() == S.DOWN
	var dist := _flat_to_opponent().length()
	var btn := ""
	if od and dist < 1.7 and _flow_cancel_ok("strike"):
		btn = "strike"
	elif od and dist < 5.0 and not _ai_grace() and _flow_cancel_ok("run"):
		btn = "run"
	if btn == "":
		return
	_flow_ai_rolled = true
	if randf() >= ai_skill * 0.6:
		return
	if btn == "strike":
		in_strike = true
	else:
		in_run = true
		var d := _flat_to_opponent().normalized()
		in_move = Vector2(d.x, d.z)


# ---- yard collision (prop footprints) ------------------------------------------------------
# main.gd gives each perch a "footprint" and lists the other big props in `arena.obstacles`:
# {"center": Vector2(x, z), "half": Vector2(hx, hz), "radius" (> 0 = round), "label", "trick",
# "points", "sfx"}. Bodies on the ground are pushed out of them every tick (minimum translation);
# climbing / perched / diving / falling-off-the-perch bodies are not (they stand on them).
# Running into one head-on: whipped (or at full steam) = prop crash, slumped against it like the
# fence crash (CORNER_STUN, hf_fence_n points into the prop); slower = bounce off it.
# Throw landings, dive targets and hop-down points are nudged out of footprints.

const COL_BODY_R := 0.28          # body radius against prop footprints
const COL_CRASH_R := 0.32         # a runner this close to a footprint, heading into it, hits it
const COL_FULL_STEAM := RUN_TOP_SPEED - 1.2  # non-whipped runs this fast crash instead of bouncing

var col_fps: Array = []           # cached footprints (perches' + obstacles)
var col_fps_ready := false


func _col_footprints() -> Array:
	if col_fps_ready or arena == null:
		return col_fps
	col_fps_ready = true
	if "perches" in arena:
		for pr in arena.perches:
			if not (pr is Dictionary):
				continue
			var fp = pr.get("footprint", {})
			if fp is Dictionary and fp.has("center") and fp.has("half"):
				col_fps.append(fp)
	if "obstacles" in arena:
		for fp in arena.obstacles:
			if fp is Dictionary and fp.has("center") and fp.has("half"):
				col_fps.append(fp)
	return col_fps


## Minimum translation that moves point p (radius r) out of footprint fp; ZERO if not overlapping.
func _col_pen(fp: Dictionary, p: Vector2, r: float) -> Vector2:
	var c: Vector2 = fp["center"]
	var rad: float = fp.get("radius", 0.0)
	var d := p - c
	if rad > 0.0:
		var lim := rad + r
		var l := d.length()
		if l >= lim:
			return Vector2.ZERO
		var dir := d / l if l > 0.001 else -c.normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0.0, 1.0)
		return dir * (lim - l)
	var half: Vector2 = fp["half"]
	var ex := half.x + r
	var ez := half.y + r
	if absf(d.x) >= ex or absf(d.y) >= ez:
		return Vector2.ZERO
	# the four ways out, shortest first; prefer one that stays inside the yard
	var yr := _yard_rect()
	var opts: Array[Vector2] = [Vector2(ex - d.x, 0.0), Vector2(-ex - d.x, 0.0), Vector2(0.0, ez - d.y), Vector2(0.0, -ez - d.y)]
	opts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length() < b.length())
	for o: Vector2 in opts:
		var q: Vector2 = p + o
		if q.x >= yr.position.x - 0.01 and q.x <= yr.end.x + 0.01 and q.y >= yr.position.y - 0.01 and q.y <= yr.end.y + 0.01:
			return o
	return opts[0]


## Point p moved out of every footprint (keeping `r` clear), then back inside the yard.
func _col_nudge_pt(p: Vector3, r := 0.5) -> Vector3:
	var fps := _col_footprints()
	if fps.is_empty():
		return p
	var q := Vector2(p.x, p.z)
	for _it in 3:
		var moved := false
		for fp: Dictionary in fps:
			var o := _col_pen(fp, q, r)
			if o != Vector2.ZERO:
				q += o
				moved = true
		if not moved:
			break
	var yr := _yard_rect()
	q.x = clampf(q.x, yr.position.x + 0.3, yr.end.x - 0.3)
	q.y = clampf(q.y, yr.position.y + 0.3, yr.end.y - 0.3)
	return Vector3(q.x, p.y, q.y)


## _clamp_ring: push a grounded body out of the prop footprints (not while it is up on / coming
## off a perch, being carried, or locked up with the opponent).
func _col_push_out() -> void:
	if state in [S.CLIMB, S.PERCHED, S.DIVING, S.PERCH_FALL, S.THROWN, S.LIFTED, S.JUGGLED,
			S.TIEUP_ATK, S.TIEUP_DEF, S.PINNING, S.PINNED, S.ON_TABLE]:
		return
	var fps := _col_footprints()
	if fps.is_empty():
		return
	var q := Vector2(position.x, position.z)
	for _it in 2:
		var moved := false
		for fp: Dictionary in fps:
			var o := _col_pen(fp, q, COL_BODY_R)
			if o != Vector2.ZERO:
				q += o
				moved = true
		if not moved:
			break
	position.x = q.x
	position.z = q.y


## _run: heading into a footprint. Whipped / full steam = prop crash (true: the run ended);
## slower = bounce off it and keep running.
func _col_run_hit() -> bool:
	var q := Vector2(position.x, position.z)
	for fp: Dictionary in _col_footprints():
		var o := _col_pen(fp, q, COL_CRASH_R)
		if o == Vector2.ZERO:
			continue
		var n := Vector3(o.x, 0.0, o.y).normalized()  # out of the prop
		if run_dir.dot(n) > -0.35:
			continue  # glancing: the push-out slides us along it
		if whipped or run_speed >= COL_FULL_STEAM:
			_col_prop_crash(fp, n, whipped)
			return true
		# bump off it
		run_dir = (run_dir - 2.0 * run_dir.dot(n) * n).normalized()
		position += Vector3(o.x, 0.0, o.y)
		run_speed = maxf(RUN_START_SPEED * 0.8, run_speed - 1.5)
		_set_facing_angle(atan2(run_dir.x, run_dir.z))
		impact.emit(0.12)
		var snd: String = fp.get("sfx", "thud")
		sfx.emit(snd, 0.3, global_position + Vector3(0, 1.0, 0) - n * 0.3)
		return false
	return false


## Slammed into a prop: slump against it (CORNER_STUN, like the fence crash). by_whip = the
## opponent whipped us into it and scores the trick.
func _col_prop_crash(fp: Dictionary, n: Vector3, by_whip: bool) -> void:
	var label: String = fp.get("label", "THE PROP")
	var snd: String = fp.get("sfx", "thud")
	set_state(S.CORNER_STUN)
	hf_corner_whip = false
	hf_stun_time = 1.5 if by_whip else 1.0
	hf_fence_n = -n   # "outward" = into the prop: a knockdown / corner splash knocks us off it
	var q := Vector2(position.x, position.z)
	var o := _col_pen(fp, q, COL_BODY_R + 0.1)
	position = Vector3(q.x + o.x, 0.0, q.y + o.y)
	_set_facing_angle(atan2(n.x, n.z))   # back against the prop
	var concrete := _surface_here() == "concrete"
	if by_whip:
		take_damage(6.0 if snd == "metal_hit" or concrete else 5.0)
	else:
		take_damage(3.0)
	impact.emit(0.4 if by_whip else 0.25)
	var hit_at := global_position + Vector3(0, 1.1, 0) - n * 0.35
	sfx.emit(snd, 1.0 if by_whip else 0.6, hit_at)
	sfx.emit("big_thud", 0.5 if by_whip else 0.3, hit_at)
	if by_whip:
		announce.emit("%s CRASHES INTO %s!" % [display_name, label])
		var tn: String = fp.get("trick", "Prop Crash")
		var pts: int = fp.get("points", 200)
		if opponent != null:
			opponent.emit_signal("trick", tn, pts, "grapple")  # style hook: the whipper scores it
	else:
		announce.emit("%s runs right into %s!" % [display_name, label.to_lower()])

extends Node3D
## A single wrestler: procedural body, state machine, grapple system and CPU AI.
## The match (main.gd) fills the in_* input fields each physics frame and calls tick().

signal announce(text: String)
signal impact(strength: float)
signal pin_count(count: int)
signal won()

enum S { IDLE, WALK, RUN, PUNCH, RUN_ATTACK, STUNNED, TIEUP_ATK, TIEUP_DEF, THROWING, THROWN,
	DOWN, GETTING_UP, PINNING, PINNED, TAUNT, WIN, LOSE }

const RING_HALF := 3.5
const WALK_SPEED := 2.7
const RUN_SPEED := 6.2
const PIN_COUNT_TIME := 0.85
const PIN_ESCAPE_NEEDED := 6.0

# Grapple move list. "land" = landing distance along the thrower's facing (negative = behind).
const MOVES := {
	"knee": {"name": "Knee Lift", "dmg": 6.0, "kind": "strike"},
	"slam": {"name": "Body Slam", "dmg": 10.0, "kind": "throw", "time": 1.0, "height": 1.6, "land": 1.3, "flip": false},
	"suplex": {"name": "Suplex!", "dmg": 13.0, "kind": "throw", "time": 1.1, "height": 2.1, "land": -1.2, "flip": true},
	"ddt": {"name": "DDT!", "dmg": 14.0, "kind": "throw", "time": 0.7, "height": 0.5, "land": 0.7, "flip": false},
	"finisher": {"name": "THUNDER DRIVER!!", "dmg": 26.0, "kind": "throw", "time": 1.4, "height": 2.6, "land": 0.9, "flip": true},
	"armdrag": {"name": "REVERSAL! Arm Drag", "dmg": 7.0, "kind": "throw", "time": 0.8, "height": 1.1, "land": 1.5, "flip": true},
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
var reversal_tried := false
var pin_escape := 0.0
var pin_count_value := 0

# Controller inputs (one-shot buttons are cleared after every tick).
var in_move := Vector2.ZERO
var in_strike := false
var in_grapple := false
var in_run := false
var in_pin := false
var any_pressed := false

# AI
var ai_timer := 0.0
var ai_backoff := 0.0
var ai_tie_delay := 0.5

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
# N64-style look: chunky low-poly parts (6-8 sided), matte materials, and tiny
# pixel textures for faces/masks with bilinear filtering (that soft N64 blur).

func _mat(c: Color, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.15
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if tex:
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
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


func _ball(parent: Node3D, r: float, pos: Vector3, mat: Material, scl := Vector3.ONE, segs := 7, hemi := false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.is_hemisphere = hemi
	s.radial_segments = segs
	s.rings = 4
	return _add_mesh(parent, s, pos, mat, scl)


func _prism(parent: Node3D, top_r: float, bottom_r: float, h: float, pos: Vector3, mat: Material, scl := Vector3.ONE, segs := 6) -> MeshInstance3D:
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


# --- tiny pixel textures -----------------------------------------------------

func _px(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


func _face_texture() -> ImageTexture:
	# 16x16 face drawn on a transparent card in front of the head.
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dark := Color(0.12, 0.07, 0.05)
	var shade := skin_color.darkened(0.25)
	if look.get("mask", false):
		var mask: Color = look["mask_color"]
		var trim: Color = look["mask_trim"]
		img.fill(mask)
		# flame-shaped trim around the eyes
		_px(img, 1, 4, 6, 4, trim)
		_px(img, 9, 4, 6, 4, trim)
		_px(img, 2, 3, 2, 1, trim)
		_px(img, 12, 3, 2, 1, trim)
		_px(img, 7, 1, 2, 4, trim)
		# eye holes
		_px(img, 2, 5, 4, 2, Color.WHITE)
		_px(img, 10, 5, 4, 2, Color.WHITE)
		_px(img, 4, 5, 2, 2, dark)
		_px(img, 10, 5, 2, 2, dark)
		# mouth hole
		_px(img, 5, 11, 6, 3, skin_color)
		_px(img, 6, 12, 4, 1, dark)
	else:
		# brows, eyes, nose shading, stern mouth, stubble
		_px(img, 2, 4, 5, 1, look["hair_color"])
		_px(img, 9, 4, 5, 1, look["hair_color"])
		_px(img, 3, 6, 3, 2, Color.WHITE)
		_px(img, 10, 6, 3, 2, Color.WHITE)
		_px(img, 4, 6, 2, 2, dark)
		_px(img, 10, 6, 2, 2, dark)
		_px(img, 7, 7, 2, 3, shade)
		_px(img, 5, 12, 6, 1, dark)
		_px(img, 4, 13, 8, 2, shade.lerp(look["hair_color"], 0.35))
	return ImageTexture.create_from_image(img)


# --- the model ------------------------------------------------------------------

func _build_body() -> void:
	var skin := _mat(skin_color)
	var skin_dark := _mat(skin_color.darkened(0.15))
	var gear := _mat(gear_color)
	var trunks := _mat(trunk_color)
	var boots := _mat(look.get("boot_color", gear_color))
	var tape := _mat(Color(0.92, 0.92, 0.88))
	var legs_mat := trunks if look.get("tights", false) else skin
	var hair := _mat(look.get("hair_color", Color.BLACK))

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

	pose_root = _pivot(self, Vector3.ZERO)
	hips = _pivot(pose_root, Vector3(0, 0.95, 0))

	# Pelvis / trunks
	_prism(hips, 0.27, 0.24, 0.3, Vector3(0, 0.0, 0), trunks, Vector3(1, 1, 0.72))
	_prism(hips, 0.285, 0.285, 0.06, Vector3(0, 0.16, 0), gear, Vector3(1, 1, 0.74))  # waistband

	# Torso: V-shaped, wide lats and chest, big traps
	torso = _pivot(hips, Vector3(0, 0.15, 0))
	_prism(torso, 0.31, 0.26, 0.3, Vector3(0, 0.15, 0), skin, Vector3(1, 1, 0.7))         # abs
	_prism(torso, 0.44, 0.31, 0.4, Vector3(0, 0.49, 0), skin, Vector3(1, 1, 0.6))         # chest/lats
	_ball(torso, 0.14, Vector3(-0.13, 0.55, 0.19), skin_dark, Vector3(1.05, 0.7, 0.45), 6) # pecs
	_ball(torso, 0.14, Vector3(0.13, 0.55, 0.19), skin_dark, Vector3(1.05, 0.7, 0.45), 6)
	_box(torso, Vector3(0.05, 0.22, 0.04), Vector3(0, 0.2, 0.19), skin_dark)              # ab line
	_ball(torso, 0.17, Vector3(-0.2, 0.7, -0.03), skin, Vector3(1.15, 0.6, 0.9), 6)       # traps
	_ball(torso, 0.17, Vector3(0.2, 0.7, -0.03), skin, Vector3(1.15, 0.6, 0.9), 6)

	# Neck + head
	_prism(torso, 0.1, 0.12, 0.16, Vector3(0, 0.76, 0), skin, Vector3.ONE, 6)
	head = _pivot(torso, Vector3(0, 0.8, 0.0))
	var head_mat := skin
	if look.get("mask", false):
		head_mat = _mat(look["mask_color"])
	_ball(head, 0.17, Vector3(0, 0.15, 0), head_mat, Vector3(0.92, 1.12, 1.0), 8)
	_ball(head, 0.05, Vector3(-0.155, 0.14, 0), head_mat, Vector3(0.6, 1.0, 0.8), 5)     # ears
	_ball(head, 0.05, Vector3(0.155, 0.14, 0), head_mat, Vector3(0.6, 1.0, 0.8), 5)
	var face := QuadMesh.new()
	face.size = Vector2(0.27, 0.29)
	_add_mesh(head, face, Vector3(0, 0.14, 0.182), _mat(Color.WHITE, _face_texture()))
	_box(head, Vector3(0.06, 0.07, 0.06), Vector3(0, 0.12, 0.185), head_mat)              # nose
	match look.get("hair", "none"):
		"flattop":
			_box(head, Vector3(0.31, 0.13, 0.33), Vector3(0, 0.31, -0.01), hair)
			_box(head, Vector3(0.33, 0.12, 0.2), Vector3(0, 0.22, -0.08), hair)
		"long":
			_ball(head, 0.185, Vector3(0, 0.2, -0.01), hair, Vector3(1, 1, 1), 8, true)
			_box(head, Vector3(0.34, 0.38, 0.12), Vector3(0, 0.02, -0.13), hair)
		"mohawk":
			_box(head, Vector3(0.07, 0.14, 0.34), Vector3(0, 0.33, -0.01), hair)

	# Arms: shoulder -> elbow -> fist
	arm_l = _build_arm(-1, skin, skin_dark, tape)
	arm_r = _build_arm(1, skin, skin_dark, tape)

	# Legs: hip -> knee -> boot
	leg_l = _build_leg(-1, legs_mat, gear, boots)
	leg_r = _build_leg(1, legs_mat, gear, boots)


func _build_arm(side: int, skin: Material, skin_dark: Material, tape: Material) -> Node3D:
	var sh := _pivot(torso, Vector3(0.47 * side, 0.63, 0))
	_ball(sh, 0.15, Vector3(0, -0.02, 0), skin, Vector3(1.0, 0.95, 1.0), 6)               # deltoid
	_prism(sh, 0.115, 0.09, 0.36, Vector3(0, -0.2, 0), skin)                             # upper arm
	_ball(sh, 0.085, Vector3(0, -0.2, 0.06), skin_dark, Vector3(0.9, 1.4, 0.8), 5)        # bicep
	var el := _pivot(sh, Vector3(0, -0.37, 0))
	if side < 0:
		elbow_l = el
	else:
		elbow_r = el
	_prism(el, 0.09, 0.075, 0.32, Vector3(0, -0.15, 0), skin)                            # forearm
	_prism(el, 0.082, 0.082, 0.08, Vector3(0, -0.29, 0), tape)                           # wrist tape
	_box(el, Vector3(0.15, 0.15, 0.16), Vector3(0, -0.39, 0.01), skin)                   # fist
	return sh


func _build_leg(side: int, legs_mat: Material, gear: Material, boots: Material) -> Node3D:
	var hp := _pivot(hips, Vector3(0.15 * side, -0.05, 0))
	_prism(hp, 0.145, 0.11, 0.44, Vector3(0, -0.21, 0), legs_mat)                        # thigh
	var kn := _pivot(hp, Vector3(0, -0.44, 0))
	if side < 0:
		knee_l = kn
	else:
		knee_r = kn
	_box(kn, Vector3(0.21, 0.15, 0.2), Vector3(0, -0.01, 0.03), gear)                    # kneepad
	_prism(kn, 0.105, 0.085, 0.3, Vector3(0, -0.17, 0), legs_mat)                        # shin
	_prism(kn, 0.11, 0.115, 0.17, Vector3(0, -0.33, 0), boots)                           # boot top
	_box(kn, Vector3(0.19, 0.12, 0.3), Vector3(0, -0.44, 0.05), boots)                   # boot foot
	_box(kn, Vector3(0.2, 0.03, 0.31), Vector3(0, -0.36, 0.05), gear)  # boot trim
	return hp


# ---------------------------------------------------------------- helpers

func set_state(s: int) -> void:
	state = s
	state_time = 0.0
	hit_landed = false
	if s == S.TIEUP_ATK or s == S.TIEUP_DEF:
		reversal_tried = false
		ai_tie_delay = randf_range(0.35, 0.85)


func is_standing() -> bool:
	return state in [S.IDLE, S.WALK, S.RUN, S.PUNCH, S.RUN_ATTACK, S.STUNNED, S.TAUNT]


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


func gain_spirit(v: float) -> void:
	spirit = clamp(spirit + v, 0.0, 100.0)


func take_damage(d: float) -> void:
	health = max(0.0, health - d)
	spirit = max(0.0, spirit - d * 0.4)


func _down_time() -> float:
	return 1.3 + (1.0 - health / 100.0) * 2.4


func _clamp_ring() -> void:
	position.x = clamp(position.x, -RING_HALF, RING_HALF)
	position.z = clamp(position.z, -RING_HALF, RING_HALF)
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


# ---------------------------------------------------------------- main update

func tick(delta: float) -> void:
	state_time += delta
	anim_clock += delta
	if combo_timer > 0.0:
		combo_timer -= delta
	else:
		combo_hits = 0

	if is_cpu:
		_ai(delta)

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
		S.TIEUP_ATK:
			_tieup_attacker()
		S.TIEUP_DEF:
			if (in_grapple or in_strike) and not reversal_tried:
				_attempt_reversal()
		S.THROWING:
			if state_time >= throw_time + 0.15:
				set_state(S.IDLE)
		S.THROWN:
			_thrown()
		S.DOWN:
			if state_time > down_duration:
				set_state(S.GETTING_UP)
		S.GETTING_UP:
			if state_time > 0.7:
				set_state(S.IDLE)
		S.PINNING:
			_pinning()
		S.PINNED:
			_pinned(delta)
		S.TAUNT:
			if state_time > 1.1:
				gain_spirit(22.0)
				announce.emit("%s is fired up!" % display_name)
				set_state(S.IDLE)

	_separate()
	_clamp_ring()
	_update_pose(delta)

	in_strike = false
	in_grapple = false
	in_run = false
	in_pin = false
	any_pressed = false


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

	if in_run:
		run_dir = dir.normalized() if dir.length() > 0.3 else facing
		rope_bounces = 0
		set_state(S.RUN)
	elif in_strike:
		set_state(S.PUNCH)
	elif in_grapple:
		_try_grapple()
	elif in_pin:
		_try_pin_or_taunt()


func _run(delta: float) -> void:
	if in_move.length() > 0.3:
		var want := Vector3(in_move.x, 0, in_move.y).normalized()
		run_dir = run_dir.lerp(want, clamp(delta * 2.5, 0.0, 1.0)).normalized()
	position += run_dir * RUN_SPEED * delta
	_set_facing_angle(atan2(run_dir.x, run_dir.z))

	var bounced := false
	if abs(position.x) >= RING_HALF - 0.02 and sign(position.x) == sign(run_dir.x):
		run_dir.x = -run_dir.x
		bounced = true
	if abs(position.z) >= RING_HALF - 0.02 and sign(position.z) == sign(run_dir.z):
		run_dir.z = -run_dir.z
		bounced = true
	if bounced:
		rope_bounces += 1
		impact.emit(0.15)
		if rope_bounces > 2:
			set_state(S.IDLE)
			return

	if in_strike:
		set_state(S.RUN_ATTACK)
	elif in_run or in_grapple or state_time > 4.0:
		set_state(S.IDLE)


func _punch() -> void:
	if state_time >= 0.14 and not hit_landed:
		hit_landed = true
		if _in_front(1.35):
			combo_hits += 1
			combo_timer = 1.0
			var knock := combo_hits >= 3
			if opponent.receive_strike(self, 8.0 if knock else 4.0, knock) and knock:
				announce.emit("3-Hit Combo!")
				combo_hits = 0
	if state_time >= 0.38:
		set_state(S.IDLE)


func _run_attack(delta: float) -> void:
	var speed: float = lerp(RUN_SPEED, 0.0, clamp(state_time / 0.45, 0.0, 1.0))
	position += run_dir * speed * delta
	if not hit_landed and state_time > 0.05 and state_time < 0.35:
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
	take_damage(dmg)
	attacker.gain_spirit(dmg * 1.5)
	var away := position - attacker.position
	away.y = 0
	if away.length() > 0.01:
		position += away.normalized() * (0.6 if knockdown else 0.2)
	if knockdown:
		set_state(S.DOWN)
		down_duration = _down_time()
		impact.emit(0.5)
	else:
		set_state(S.STUNNED)
		stun_time = 0.35
		impact.emit(0.1)
	return true


func _try_grapple() -> void:
	if _in_front(1.45) and opponent.state in [S.IDLE, S.WALK, S.STUNNED, S.PUNCH, S.TAUNT]:
		set_state(S.TIEUP_ATK)
		opponent.position = position + facing * 0.95
		opponent.set_state(S.TIEUP_DEF)
		opponent._snap_face_opponent()
	else:
		set_state(S.STUNNED)  # whiffed grab: brief recovery
		stun_time = 0.3


func _tieup_attacker() -> void:
	if opponent.state != S.TIEUP_DEF:
		if state == S.TIEUP_ATK:
			set_state(S.IDLE)
		return
	if state_time < 0.3:
		return  # collar-and-elbow struggle
	var dir_held := in_move.length() > 0.5
	var move := ""
	if in_grapple:
		if dir_held:
			move = "finisher" if is_special_ready() else "ddt"
		else:
			move = "slam"
	elif in_strike:
		move = "suplex" if dir_held else "knee"
	if move != "":
		_do_move(move)
	elif state_time > 2.4:
		# nobody committed: break the hold
		set_state(S.IDLE)
		opponent.set_state(S.IDLE)
		opponent.position += facing * 0.4


func _attempt_reversal() -> void:
	reversal_tried = true
	var chance: float = 0.38 + (health - opponent.health) / 300.0
	if randf() < chance:
		_do_move("armdrag")
	elif not is_cpu:
		announce.emit("Reversal failed!")


func _do_move(key: String) -> void:
	var m: Dictionary = MOVES[key]
	announce.emit(m["name"])
	if key == "finisher":
		spirit = 0.0
	gain_spirit(float(m["dmg"]) * 1.5)
	if m["kind"] == "strike":
		opponent.take_damage(m["dmg"])
		opponent.set_state(S.STUNNED)
		opponent.stun_time = 0.7
		opponent.position += facing * 0.4
		impact.emit(0.25)
		set_state(S.PUNCH)
		hit_landed = true
		return
	set_state(S.THROWING)
	throw_time = m["time"]
	opponent.start_thrown(position + facing * float(m["land"]), m)


func start_thrown(land_pos: Vector3, m: Dictionary) -> void:
	set_state(S.THROWN)
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
		take_damage(pending_damage)
		set_state(S.DOWN)
		down_duration = _down_time()
		pose_root.rotation.x = -PI / 2
		impact.emit(clamp(pending_damage / 20.0, 0.3, 1.2))


func _try_pin_or_taunt() -> void:
	if opponent.state == S.DOWN and _flat_to_opponent().length() < 2.0:
		set_state(S.PINNING)
		position = opponent.position
		_set_facing_angle(opponent.rotation.y + PI / 2)
		pin_count_value = 0
		opponent.set_state(S.PINNED)
		opponent.pin_escape = 0.0
		announce.emit("COVER!")
	else:
		set_state(S.TAUNT)


func _pinning() -> void:
	if opponent.state != S.PINNED:
		return
	var c := int(state_time / PIN_COUNT_TIME)
	if c > pin_count_value:
		pin_count_value = c
		pin_count.emit(c)
		if c >= 3:
			set_state(S.WIN)
			opponent.set_state(S.LOSE)
			won.emit()


func _pinned(delta: float) -> void:
	if is_cpu:
		pin_escape += delta * (health / 100.0) * 10.0 * randf_range(0.5, 1.5)
	elif any_pressed:
		pin_escape += 0.3 + 0.9 * (health / 100.0)
	if pin_escape >= PIN_ESCAPE_NEEDED and opponent.state == S.PINNING:
		announce.emit("KICK OUT!")
		opponent.set_state(S.STUNNED)
		opponent.stun_time = 0.7
		opponent.position += opponent.facing * 1.0
		set_state(S.DOWN)
		down_duration = 0.4
		impact.emit(0.2)


# ---------------------------------------------------------------- CPU AI

func _ai(delta: float) -> void:
	ai_timer -= delta
	ai_backoff -= delta
	in_move = Vector2.ZERO
	var d := _flat_to_opponent()
	var dist := d.length()
	var toward := Vector2(d.x, d.z).normalized() if dist > 0.01 else Vector2.ZERO

	match state:
		S.TIEUP_DEF:
			if not reversal_tried and state_time > 0.12:
				reversal_tried = true
				if randf() < 0.3:
					_attempt_reversal()
			return
		S.TIEUP_ATK:
			if state_time > ai_tie_delay:
				var r := randf()
				if is_special_ready() or r < 0.25:
					in_grapple = true
					in_move = toward
				elif r < 0.5:
					in_grapple = true
				elif r < 0.75:
					in_strike = true
					in_move = toward
				else:
					in_strike = true
			return
		S.RUN:
			if dist < 1.9 and opponent.is_standing():
				in_strike = true
			return

	if state != S.IDLE and state != S.WALK:
		return

	if opponent.state == S.DOWN:
		if opponent.health < 60.0 and dist > 1.5:
			in_move = toward
		elif ai_timer <= 0.0:
			ai_timer = 0.5
			if dist < 1.9 and opponent.health < 60.0 and randf() < 0.75:
				in_pin = true
			elif dist > 2.2 and randf() < 0.35:
				in_pin = true  # far away -> taunt
		return
	if not opponent.is_standing() and opponent.state != S.TIEUP_DEF:
		return

	if ai_backoff > 0.0:
		in_move = -toward
		return

	if dist > 1.25:
		in_move = toward
		if dist > 4.0 and ai_timer <= 0.0:
			ai_timer = 1.0
			if randf() < 0.3:
				in_run = true
	elif ai_timer <= 0.0:
		ai_timer = randf_range(0.35, 0.9)
		var r := randf()
		if r < 0.45:
			in_grapple = true
		elif r < 0.82:
			in_strike = true
		else:
			ai_backoff = 0.45


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
	var root_y := 0.0
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
			var p: float = clamp(t / 0.14, 0.0, 1.0) if t < 0.14 else clamp(1.0 - (t - 0.14) / 0.24, 0.0, 1.0)
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
			root_y = sin(p * PI) * throw_height + 0.25 * p
			al.z = -1.3
			ar.z = 1.3
			el_l.x = -0.3
			el_r.x = -0.3
			kn_l = 0.7
			kn_r = 0.3
			direct = true
		S.DOWN, S.PINNED, S.LOSE:
			root_x = -PI / 2
			root_y = 0.25
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
			root_y = lerp(0.25, 0.0, p)
			al.x = -0.8
			ar.x = -0.8
			ll.x = lerp(-1.2, 0.0, p)
			lr.x = lerp(-0.4, 0.0, p)
			kn_l = lerp(1.6, 0.1, p)
			kn_r = lerp(1.0, 0.1, p)
			direct = true
		S.PINNING:
			root_x = PI / 2 * 0.95
			root_y = 0.55
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
			root_y = abs(sin(t * 6.0)) * 0.15
			hip.y = sin(t * 3.0) * 0.3

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

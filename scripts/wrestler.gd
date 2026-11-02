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


func setup(p_name: String, p_gear: Color, p_trunks: Color, p_skin: Color, p_cpu: bool) -> void:
	display_name = p_name
	gear_color = p_gear
	trunk_color = p_trunks
	skin_color = p_skin
	is_cpu = p_cpu
	_build_body()


# ---------------------------------------------------------------- body building

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add_mesh(parent, b, pos, mat)


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _add_mesh(parent, s, pos, mat)


func _limb(parent: Node3D, pivot_pos: Vector3, radius: float, length: float, mat: Material, end_mat: Material, end_is_boot: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	parent.add_child(pivot)
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = length
	c.radial_segments = 10
	c.rings = 4
	_add_mesh(pivot, c, Vector3(0, -length * 0.5, 0), mat)
	if end_is_boot:
		_box(pivot, Vector3(radius * 2.3, radius * 2.6, radius * 3.2), Vector3(0, -length + radius * 1.1, radius * 0.4), end_mat)
	else:
		_sphere(pivot, radius * 1.35, Vector3(0, -length + radius * 0.6, 0), end_mat)
	return pivot


func _build_body() -> void:
	var skin := _mat(skin_color)
	var gear := _mat(gear_color)
	var trunks := _mat(trunk_color)

	# Blob shadow (does not follow the pose, stays on the mat)
	var sh := CylinderMesh.new()
	sh.top_radius = 0.55
	sh.bottom_radius = 0.55
	sh.height = 0.01
	var sh_mat := StandardMaterial3D.new()
	sh_mat.albedo_color = Color(0, 0, 0, 0.45)
	sh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_add_mesh(self, sh, Vector3(0, 0.03, 0), sh_mat)

	pose_root = Node3D.new()
	add_child(pose_root)

	hips = Node3D.new()
	hips.position = Vector3(0, 0.95, 0)
	pose_root.add_child(hips)

	torso = Node3D.new()
	hips.add_child(torso)
	_box(torso, Vector3(0.66, 0.6, 0.38), Vector3(0, 0.44, 0), skin)       # chest
	_box(torso, Vector3(0.54, 0.26, 0.34), Vector3(0, 0.07, 0), trunks)    # trunks
	_box(torso, Vector3(0.56, 0.07, 0.36), Vector3(0, 0.2, 0), gear)       # belt

	head = Node3D.new()
	head.position = Vector3(0, 0.82, 0)
	torso.add_child(head)
	_sphere(head, 0.2, Vector3(0, 0.12, 0), skin)
	_box(head, Vector3(0.42, 0.07, 0.42), Vector3(0, 0.2, 0), gear)       # headband
	_box(head, Vector3(0.05, 0.04, 0.02), Vector3(-0.08, 0.14, 0.19), _mat(Color.BLACK))
	_box(head, Vector3(0.05, 0.04, 0.02), Vector3(0.08, 0.14, 0.19), _mat(Color.BLACK))

	arm_l = _limb(torso, Vector3(-0.43, 0.66, 0), 0.1, 0.7, skin, gear, false)
	arm_r = _limb(torso, Vector3(0.43, 0.66, 0), 0.1, 0.7, skin, gear, false)
	leg_l = _limb(hips, Vector3(-0.16, 0.0, 0), 0.12, 0.9, trunks, gear, true)
	leg_r = _limb(hips, Vector3(0.16, 0.0, 0), 0.12, 0.9, trunks, gear, true)


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
	var root_x := 0.0
	var root_y := 0.0
	var direct := false

	match state:
		S.IDLE:
			var b := sin(anim_clock * 3.0)
			al.x = -0.55 + b * 0.06
			ar.x = -0.55 - b * 0.06
			hip.x = 0.08
			ll.x = 0.15
			lr.x = -0.15
		S.WALK:
			var s := sin(anim_clock * 9.0)
			ll.x = s * 0.6
			lr.x = -s * 0.6
			al.x = -0.4 - s * 0.45
			ar.x = -0.4 + s * 0.45
		S.RUN:
			var s := sin(anim_clock * 15.0)
			ll.x = s * 1.0
			lr.x = -s * 1.0
			al.x = -0.4 - s * 0.9
			ar.x = -0.4 + s * 0.9
			hip.x = 0.3
		S.PUNCH:
			var p: float = clamp(t / 0.14, 0.0, 1.0) if t < 0.14 else clamp(1.0 - (t - 0.14) / 0.24, 0.0, 1.0)
			ar.x = lerp(-0.6, -1.65, p)
			al.x = -0.9
			hip.y = 0.45 * p
			hip.x = 0.15 * p
		S.RUN_ATTACK:
			al.z = -1.5
			ar.z = 1.5
			hip.x = 0.3
			ll.x = 0.5
			lr.x = -0.4
		S.STUNNED:
			hip.x = -0.35
			al.x = 0.4
			ar.x = 0.3
		S.TIEUP_ATK, S.TIEUP_DEF:
			al = Vector3(-1.35, 0, 0.3)
			ar = Vector3(-1.35, 0, -0.3)
			hip.x = 0.4
			hip.z = sin(anim_clock * 18.0) * 0.05
			ll.x = 0.35
			lr.x = -0.35
		S.THROWING:
			var p: float = sin(clamp(t / throw_time, 0.0, 1.0) * PI)
			al.x = lerp(-1.4, -3.0, p)
			ar.x = lerp(-1.4, -3.0, p)
			hip.x = lerp(0.3, -0.45, p)
		S.THROWN:
			var p: float = clamp(t / throw_time, 0.0, 1.0)
			root_x = lerp(0.0, throw_end_angle, p)
			root_y = sin(p * PI) * throw_height + 0.25 * p
			al.z = -1.3
			ar.z = 1.3
			direct = true
		S.DOWN, S.PINNED, S.LOSE:
			root_x = -PI / 2
			root_y = 0.25
			al = Vector3(0, 0, -0.7)
			ar = Vector3(0, 0, 0.7)
			ll.z = -0.2
			lr.z = 0.2
			if state == S.PINNED:
				al.x = sin(anim_clock * 12.0) * 0.4
				ar.x = -sin(anim_clock * 12.0) * 0.4
		S.GETTING_UP:
			var p: float = clamp(t / 0.7, 0.0, 1.0)
			root_x = lerp(-PI / 2, 0.0, p * p)
			root_y = lerp(0.25, 0.0, p)
			al.x = -0.8
			ar.x = -0.8
			direct = true
		S.PINNING:
			root_x = PI / 2 * 0.95
			root_y = 0.55
			al.x = -0.6
			ar.x = -0.6
		S.TAUNT, S.WIN:
			al.z = -2.6
			ar.z = 2.6
			root_y = abs(sin(t * 6.0)) * 0.15
			hip.y = sin(t * 3.0) * 0.3

	var k: float = clamp(delta * 14.0, 0.0, 1.0)
	arm_l.rotation = arm_l.rotation.lerp(al, k)
	arm_r.rotation = arm_r.rotation.lerp(ar, k)
	leg_l.rotation = leg_l.rotation.lerp(ll, k)
	leg_r.rotation = leg_r.rotation.lerp(lr, k)
	hips.rotation = hips.rotation.lerp(hip, k)
	if direct:
		pose_root.rotation.x = root_x
		pose_root.position.y = root_y
	else:
		pose_root.rotation.x = lerp(pose_root.rotation.x, root_x, k)
		pose_root.position.y = lerp(pose_root.position.y, root_y, k)

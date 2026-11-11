extends "res://scripts/wrestler.gd"
## City 2 City Wrestling - a wrestler model driven by the story cutscenes (cutscene.gd).
##
## Never ticks gameplay (no AI, input, physics or opponent): cs_update() advances the clocks,
## runs the wrestler's own state poses (calm idle / WALK / TAUNT / WIN), then layers an emote
## pose (arms / torso / head), a scripted action (slam a table, knock, hug, shake hands), a
## subtle "talk" gesture and a head turn toward whoever it is looking at, and finally the
## wrestler's normal easing / exaggeration / hand passes. Being a subclass it can set the pose
## targets (pt_*) directly.

const WALK_SPEED_CS := 1.7

var emote := "idle"
var emote_t := 0.0
var action := ""            # "slam" | "knock" | "hug" | "shake" | "" (playing in place)
var action_t := 0.0
var sitting := false
var talking := false
var calm := true            # conversation idle instead of the swagger loop
var look_at_node: Node3D = null
var look_at_point := Vector3.INF
var yaw_target := 0.0
var walk_target := Vector3.INF
var act_target := Vector3.INF  # what a slam / knock is aimed at
var after_walk := ""        # action to start on arrival ("hide" hides the model)
var arrived := false
## Called by the cutscene: an action's "impact" moment (slam, knock) for sound / shake.
var impact_cb: Callable = Callable()
var _impacts_done := 0
var _shock_hop := 0.0


func cs_spawn(n: String, p_look: Dictionary) -> void:
	setup(n, p_look, false)
	set_state(S.IDLE)
	anim_clock = randf() * 10.0


func set_emote(e: String) -> void:
	if e == "":
		return
	if e == "sit":
		sitting = true
		e = "idle"
	if e == emote and e != "shock" and e != "flex" and e != "cheer":
		return
	emote = e
	emote_t = 0.0
	if e == "shock":
		_shock_hop = 1.0
	if (e == "flex" or e == "cheer") and not sitting:
		state = S.TAUNT
		state_time = 0.0
	elif state == S.TAUNT or state == S.WIN:
		state = S.IDLE
		state_time = 0.0


func start_action(a: String) -> void:
	action = a
	action_t = 0.0
	_impacts_done = 0


func move_to(p: Vector3, then := "") -> void:
	walk_target = Vector3(p.x, 0.0, p.z)
	after_walk = then
	arrived = false
	sitting = false
	action = ""


func is_walking() -> bool:
	return walk_target != Vector3.INF


func face_point(p: Vector3) -> void:
	var d := p - position
	d.y = 0.0
	if d.length() > 0.05:
		yaw_target = atan2(d.x, d.z)


func snap_yaw() -> void:
	rotation.y = yaw_target
	facing = Vector3(sin(yaw_target), 0.0, cos(yaw_target))


# ---------------------------------------------------------------- per frame

func cs_update(dt: float) -> void:
	state_time += dt
	anim_clock += dt
	emote_t += dt
	action_t += dt
	_shock_hop = maxf(0.0, _shock_hop - dt * 3.0)
	if _style < 0:
		_style = absi(display_name.hash()) % 3
	_cs_move(dt)
	if state == S.TAUNT and state_time >= TAUNT_TIME:
		state = S.WIN if emote == "cheer" else S.IDLE
		state_time = 0.0
	if state != _pose_prev_state:
		_pose_state_changed()
	_pose_reset()
	match state:
		S.WALK:
			_pose_walk(dt)
		S.TAUNT:
			_pose_taunt()
		S.WIN:
			_pose_win()
		_:
			if calm or sitting:
				_cs_idle()
			else:
				_pose_idle()
	var hands := 1.6
	if state != S.WALK:
		if sitting:
			_cs_sit()
		hands = _cs_emote()
		var ah := _cs_action()
		if ah >= 0.0:
			hands = ah
		if talking and action == "" and emote in ["idle", "talk", "angry", "sad", "laugh", "sit"]:
			_cs_talk()
	_cs_look()
	_pose_exaggerate()
	_apply_pose(dt)
	if state == S.TAUNT:
		hands = 0.3
	finger_curl = lerpf(finger_curl, hands, 1.0 - exp(-14.0 * dt))
	for hp in _hand_parts:
		_pose_hand(float(hp[0]), hp[1], hp[2], hp[3], finger_curl)


func _cs_move(dt: float) -> void:
	if walk_target != Vector3.INF:
		var d := walk_target - position
		d.y = 0.0
		var dist := d.length()
		if dist < 0.06:
			position = walk_target
			walk_target = Vector3.INF
			in_move = Vector2.ZERO
			state = S.IDLE
			state_time = 0.0
			arrived = true
			var then := after_walk
			after_walk = ""
			if then == "hide":
				visible = false
			elif then != "":
				start_action(then)
		else:
			var dir := d / dist
			position += dir * minf(dist, WALK_SPEED_CS * dt)
			yaw_target = atan2(dir.x, dir.z)
			in_move = Vector2(dir.x, dir.z) * 0.55
			if state != S.WALK:
				state = S.WALK
				state_time = 0.0
	var k := 1.0 - exp(-(9.0 if state == S.WALK else 5.0) * dt)
	rotation.y = lerp_angle(rotation.y, yaw_target, k)
	facing = Vector3(sin(rotation.y), 0.0, cos(rotation.y))


## Relaxed conversational stance: breathing and a slow weight shift, hands loose.
func _cs_idle() -> void:
	var b := sin(anim_clock * 2.1)
	var w := sin(anim_clock * 0.8)
	pt_breath = b
	_stance(0.18 + 0.05 * w)
	pt_ll.x *= 0.6
	pt_lr.x *= 0.6
	pt_kn_l += 0.07 * w
	pt_kn_r -= 0.07 * w
	pt_hip.z = 0.035 * w
	pt_tor = Vector3(0.06 + 0.015 * b, -0.04 * w, -0.03 * w)
	pt_hd = Vector3(-0.04 - 0.015 * b, 0.05 * w, 0.02 * w)
	pt_al = Vector3(-0.12 - 0.02 * b, 0.0, -0.16)
	pt_ar = Vector3(-0.1 + 0.02 * b, 0.0, 0.16)
	pt_el_l = Vector3(-0.42, 0.0, 0.0)
	pt_el_r = Vector3(-0.38, 0.0, 0.0)
	r_limb = 10.0
	r_body = 9.0


func _cs_sit() -> void:
	pt_auto_height = false
	pt_root_pos = Vector3(0.0, 0.53, 0.0)
	pt_root_rot = Vector3.ZERO
	pt_ll = Vector3(-1.48, 0.0, -0.1)
	pt_lr = Vector3(-1.42, 0.0, 0.12)
	pt_kn_l = 1.5
	pt_kn_r = 1.4
	pt_hip = Vector3.ZERO
	pt_tor.x = 0.12 + 0.015 * sin(anim_clock * 2.1)
	if emote == "idle" or emote == "talk":
		pt_al = Vector3(-0.75, 0.0, -0.12)
		pt_ar = Vector3(-0.75, 0.0, 0.12)
		pt_el_l = Vector3(-0.75, 0.0, 0.0)
		pt_el_r = Vector3(-0.75, 0.0, 0.0)


func _face_pt() -> Vector3:
	return head.global_position + global_basis.z * 0.12 + Vector3(0, 0.08, 0)


## Arm / torso / head layer for the line's emote. Returns the finger curl it wants.
func _cs_emote() -> float:
	var t := emote_t
	var on := _smooth(_seg(t, 0.0, 0.25))
	var lean := 0.0 if sitting else 1.0
	match emote:
		"talk":
			pass
		"laugh":
			var j := absf(sin(t * 15.0))
			pt_tor = Vector3(-0.14 * lean - 0.05 * j, 0.06 * sin(t * 3.0), 0.0)
			pt_hd = Vector3(-0.38 + 0.12 * j, 0.0, 0.05 * sin(t * 4.0))
			pt_al = Vector3(-0.55, 0.0, 0.05)
			pt_ar = Vector3(-0.55, 0.0, -0.05)
			pt_el_l = Vector3(-1.85 + 0.15 * j, 0.0, 0.0)
			pt_el_r = Vector3(-1.85 + 0.15 * j, 0.0, 0.0)
			pt_breath = j
			return 0.6
		"angry":
			var tr := 0.025 * sin(t * 40.0)
			pt_tor = Vector3(0.28 * on * lean + 0.05, tr, 0.0)
			pt_hd = Vector3(-0.22 * on + 0.08, 0.0, tr)
			pt_al = Vector3(-0.35 - pt_tor.x, 0.0, -0.32)
			pt_ar = Vector3(-0.35 - pt_tor.x, 0.0, 0.32)
			pt_el_l = Vector3(-1.85 + tr * 4.0, 0.0, 0.0)
			pt_el_r = Vector3(-1.85 - tr * 4.0, 0.0, 0.0)
			if not sitting:
				_stance(0.45)
			return 1.7
		"sad":
			pt_tor = Vector3(0.3 * lean + 0.12, 0.0, 0.0)
			pt_hd = Vector3(0.42 * on, 0.06 * sin(t * 0.7), 0.0)
			if not sitting:
				_hang_arms(pt_tor.x, 0.07)
				pt_el_l = Vector3(-0.15, 0.0, 0.0)
				pt_el_r = Vector3(-0.15, 0.0, 0.0)
			else:
				pt_al = Vector3(-1.0, 0.0, -0.05)
				pt_ar = Vector3(-1.0, 0.0, 0.05)
				pt_el_l = Vector3(-0.9, 0.0, 0.0)
				pt_el_r = Vector3(-0.9, 0.0, 0.0)
			r_body = 5.0
			return 1.0
		"shrug":
			var up := _hump(fmod(t, 2.4), 0.0, 1.2)
			pt_al = Vector3(-0.25, 0.0, -0.45 - 0.2 * up)
			pt_ar = Vector3(-0.25, 0.0, 0.45 + 0.2 * up)
			pt_el_l = Vector3(-1.45, 0.0, -0.25 * up)
			pt_el_r = Vector3(-1.45, 0.0, 0.25 * up)
			pt_hd = Vector3(-0.08, 0.0, 0.2 * on)
			pt_tor.z = -0.05 * on
			return 0.3
		"point":
			pt_ar = Vector3(-1.5, 0.0, 0.08)
			pt_el_r = Vector3(-0.08, 0.0, 0.0)
			pt_al = Vector3(-0.2, 0.0, -0.25)
			pt_el_l = Vector3(-0.9, 0.0, 0.0)
			pt_tor = Vector3(0.12 * lean, -0.22 * on, 0.0)
			pt_hd = Vector3(-0.05, 0.18 * on, 0.0)
			return 1.2
		"cross_arms":
			pt_al = Vector3(-0.78, 0.0, 0.32)
			pt_ar = Vector3(-0.72, 0.0, -0.32)
			pt_el_l = Vector3(-2.15, 0.0, 0.0)
			pt_el_r = Vector3(-2.2, 0.0, 0.0)
			pt_tor = Vector3(-0.06 * lean, 0.0, 0.0)
			pt_hd = Vector3(-0.16, 0.0, 0.05)
			return 1.4
		"facepalm":
			pt_tor = Vector3(0.18 * lean + 0.05, 0.0, 0.0)
			pt_hd = Vector3(0.3 * on, 0.0, 0.1 * sin(t * 2.0))
			_reach(false, _face_pt() + global_basis.z * 0.02, on)
			pt_al = Vector3(-0.15, 0.0, -0.2)
			pt_el_l = Vector3(-0.5, 0.0, 0.0)
			return 0.3
		"flex":
			# after the TAUNT flourish: hold a bouncing double bicep
			var bo := absf(sin(t * 6.0))
			pt_al = Vector3(0.0, 0.0, -1.45 - 0.08 * bo)
			pt_ar = Vector3(0.0, 0.0, 1.45 + 0.08 * bo)
			pt_el_l = Vector3(0.0, 0.0, -1.8 - 0.12 * bo)
			pt_el_r = Vector3(0.0, 0.0, 1.8 + 0.12 * bo)
			pt_tor = Vector3(-0.12, 0.0, 0.0)
			pt_hd = Vector3(-0.28, 0.0, 0.0)
			pt_breath = 1.0
			return 1.7
		"cheer":
			if state != S.IDLE:
				return 1.6
			var pump := maxf(0.0, sin(t * 8.0))
			pt_al = Vector3(-2.8 + 0.25 * pump, 0.0, -0.3)
			pt_ar = Vector3(-2.8 + 0.25 * pump, 0.0, 0.3)
			pt_el_l = Vector3(-0.3 - 0.4 * pump, 0.0, 0.0)
			pt_el_r = Vector3(-0.3 - 0.4 * pump, 0.0, 0.0)
			pt_hd = Vector3(-0.3, 0.0, 0.0)
			return 1.7
		"think":
			pt_al = Vector3(-0.7, 0.0, 0.3)
			pt_el_l = Vector3(-2.0, 0.0, 0.0)
			_reach(false, _face_pt() - Vector3(0, 0.14, 0) + global_basis.z * 0.02, on)
			pt_hd = Vector3(-0.15, 0.3 * on, 0.14 * on)
			pt_tor.y = -0.05
			return 1.2
		"shock":
			var hop := _shock_hop
			pt_root_dy = 0.06 * hop * lean
			pt_tor = Vector3(-0.22 * lean, 0.0, 0.0)
			pt_hd = Vector3(-0.15, 0.0, 0.0)
			pt_al = Vector3(-1.25, 0.0, -0.55)
			pt_ar = Vector3(-1.25, 0.0, 0.55)
			pt_el_l = Vector3(-1.55, 0.0, 0.0)
			pt_el_r = Vector3(-1.55, 0.0, 0.0)
			r_limb = 24.0
			return 0.3
		"eat":
			var bite := _hump(fmod(t, 2.2), 0.4, 1.3)
			var hand_p := global_position + global_basis.z * 0.35 + Vector3(0, 1.15 if not sitting else 0.8, 0)
			_reach(false, hand_p.lerp(_face_pt() - Vector3(0, 0.1, 0), bite))
			pt_al = Vector3(-0.85, 0.0, -0.1)
			pt_el_l = Vector3(-1.4, 0.0, 0.0)
			pt_hd.x += 0.1 * bite
			return 1.0
		"phone":
			_reach(false, head.global_position + global_basis.x * 0.11 + Vector3(0, 0.05, 0), on)
			pt_hd = Vector3(0.05, 0.12, -0.18 * on)
			pt_al = Vector3(-0.55, 0.0, 0.25)
			pt_el_l = Vector3(-1.9, 0.0, 0.0)
			return 1.0
	return 1.6


## Scripted actions; returns a finger curl (or -1 for "no opinion").
func _cs_action() -> float:
	var t := action_t
	match action:
		"slam":
			# both fists up, then down on the table with an impact at 0.42 s
			var up := _smooth(_seg(t, 0.0, 0.3))
			var down := _smooth(_seg(t, 0.32, 0.42))
			pt_tor = Vector3(lerpf(-0.15 * up, 0.55, down), 0.0, 0.0)
			pt_hd = Vector3(lerpf(-0.3 * up, -0.25, down), 0.0, 0.0)
			var a := lerpf(lerpf(-0.3, -2.7, up), -1.2, down)
			pt_al = Vector3(a, 0.0, -0.2)
			pt_ar = Vector3(a, 0.0, 0.2)
			pt_el_l = Vector3(lerpf(-1.4, -0.4, down), 0.0, 0.0)
			pt_el_r = Vector3(lerpf(-1.4, -0.4, down), 0.0, 0.0)
			_stance(0.4 + 0.3 * down)
			r_limb = 26.0
			if t > 0.42 and _impacts_done == 0:
				_impacts_done = 1
				_impact("slam")
			if t > 1.6:
				action = ""
			return 1.8
		"knock":
			var k := fmod(t, 0.32) / 0.32
			var hit := _hump(k, 0.0, 1.0)
			pt_ar = Vector3(-1.55 - 0.25 * hit, 0.0, 0.05)
			pt_el_r = Vector3(-1.5 + 0.5 * hit, 0.0, 0.0)
			pt_tor.x = 0.12
			var n := int(t / 0.32)
			if n < 3 and n >= _impacts_done:
				_impacts_done = n + 1
				_impact("knock")
			if t > 1.3:
				action = ""
			return 1.7
		"hug":
			if look_at_node == null:
				action = ""
				return -1.0
			var w := _smooth(_seg(t, 0.0, 0.35))
			var o: Node3D = look_at_node
			var back := o.global_position - (global_position - o.global_position).normalized() * 0.12
			var sideways := global_basis.x * 0.18
			_reach(true, back + Vector3(0, 1.3, 0) - sideways, w)
			_reach(false, back + Vector3(0, 1.15, 0) + sideways, w)
			pt_tor.x = 0.12 * w
			pt_hd = Vector3(0.1, 0.35 * w, 0.1 * w)
			pt_root_dy = 0.0
			return 0.3
		"shake":
			if look_at_node == null:
				action = ""
				return -1.0
			var w2 := _smooth(_seg(t, 0.0, 0.3))
			var pump := sin(t * 14.0) * _seg(t, 0.3, 0.5) * (1.0 - _seg(t, 1.6, 1.9))
			var mid := (global_position + look_at_node.global_position) * 0.5
			_reach(false, mid + Vector3(0, 1.0 + 0.05 * pump, 0), w2)
			if t > 2.4:
				action = ""
			return 0.6
	return -1.0


func _impact(kind: String) -> void:
	if impact_cb.is_valid():
		impact_cb.call(self, kind)


## Subtle speaking gesture: head beats and a forearm that rises and falls with the words.
func _cs_talk() -> void:
	var t := anim_clock
	var beat := sin(t * 7.3) * 0.5 + sin(t * 11.1) * 0.5
	pt_hd.x += 0.05 * beat
	pt_hd.y += 0.04 * sin(t * 2.7)
	if emote == "idle" or emote == "talk":
		var g := 0.5 + 0.5 * sin(t * 2.3)
		pt_ar = Vector3(-0.55 - 0.25 * g, 0.0, 0.22)
		pt_el_r = Vector3(-1.2 - 0.25 * beat, 0.0, 0.0)
		if emote == "talk":
			pt_al = Vector3(-0.5 - 0.2 * (1.0 - g), 0.0, -0.25)
			pt_el_l = Vector3(-1.25 + 0.2 * beat, 0.0, 0.0)


func _cs_look() -> void:
	var p := look_at_point
	if look_at_node != null and is_instance_valid(look_at_node) and look_at_node.visible:
		var h: Node3D = look_at_node.get("head")
		p = h.global_position if h != null else look_at_node.global_position + Vector3(0, 1.7, 0)
	if p == Vector3.INF or action == "hug" or emote == "sad" or emote == "facepalm":
		return
	var l := to_local(p)
	var yaw := clampf(atan2(l.x, l.z), -0.75, 0.75)
	var hd := head.global_position
	var pitch := clampf(atan2(hd.y - p.y, Vector2(l.x, l.z).length()), -0.35, 0.35)
	pt_hd.y += yaw * 0.7
	pt_tor.y += yaw * 0.25
	pt_hd.x += pitch * 0.6

extends Node3D
## Builds the arena, spawns both wrestlers, runs the camera, HUD and match flow.
## Everything is generated in code so the project has no imported assets.

const Wrestler := preload("res://scripts/wrestler.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")
const RING_TOP := 1.0

var p1: Node3D
var p2: Node3D
var ring_root: Node3D
var camera: Camera3D
var cam_target := Vector3.ZERO
var cam_shake := 0.0
var touch: Control
var match_over := false

# HUD
var hud: CanvasLayer
var bars := {}
var announce_label: Label
var announce_timer := 0.0
var count_label: Label
var count_timer := 0.0
var hint_label: Label
var win_panel: Control
var win_label: Label


func _ready() -> void:
	randomize()
	_setup_input()
	_build_environment()
	_build_arena()
	_build_crowd()

	ring_root = Node3D.new()
	ring_root.position.y = RING_TOP
	add_child(ring_root)
	# Each look: colors + style switches used by wrestler.gd's N64-style model.
	var brick := {
		"gear": Color(0.85, 0.12, 0.12), "trunks": Color(0.08, 0.08, 0.1), "boot_color": Color(0.1, 0.1, 0.12),
		"skin": Color(0.87, 0.64, 0.47), "hair": "flattop", "hair_color": Color(0.18, 0.12, 0.08),
		"trunk_pattern": "bricks", "initials": "BM", "stubble": true, "boot_trim": Color(0.85, 0.12, 0.12),
		"elbow_pads": false, "wrist_tape": true,
	}
	var volcano := {
		"gear": Color(1.0, 0.5, 0.1), "trunks": Color(0.12, 0.3, 0.85), "boot_color": Color(0.12, 0.3, 0.85),
		"skin": Color(0.6, 0.42, 0.3), "tights": true, "mask": true,
		"mask_color": Color(0.12, 0.3, 0.85), "mask_trim": Color(1.0, 0.55, 0.1), "hair_color": Color.BLACK,
		"trunk_pattern": "flames", "tights_pattern": "flames", "boot_trim": Color(1.0, 0.5, 0.1),
		"elbow_pads": true, "wrist_tape": true,
	}
	p1 = _spawn("BRICK MASON", brick, false, Vector3(-1.8, 0, 0.3))
	p2 = _spawn("THE VOLCANO", volcano, true, Vector3(1.8, 0, -0.3))
	p1.opponent = p2
	p2.opponent = p1
	p1._snap_face_opponent()
	p2._snap_face_opponent()

	_build_hud()
	_announce("FIGHT!", 1.5)


# ---------------------------------------------------------------- input

func _add_action(action_name: String, keys: Array) -> void:
	if InputMap.has_action(action_name):
		return  # already registered (e.g. after a rematch reload)
	InputMap.add_action(action_name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action_name, ev)


func _setup_input() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("strike", [KEY_J, KEY_Z])
	_add_action("grapple", [KEY_K, KEY_X])
	_add_action("run", [KEY_L, KEY_C])
	_add_action("pin", [KEY_SPACE, KEY_V])
	_add_action("restart", [KEY_R, KEY_ENTER])


# ---------------------------------------------------------------- world building

func _mat(c: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	return m


func _box(size: Vector3, pos: Vector3, color: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.material_override = _mat(color, emissive)
	add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	mi.mesh = c
	mi.position = pos
	mi.material_override = _mat(color)
	add_child(mi)
	return mi


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.7)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 25, 0)
	sun.light_energy = 0.9
	add_child(sun)

	for p in [Vector3(-3, 8, -3), Vector3(3, 8, 3), Vector3(-3, 8, 3), Vector3(3, 8, -3)]:
		var o := OmniLight3D.new()
		o.position = p
		o.omni_range = 14.0
		o.light_energy = 1.2
		o.light_color = Color(1.0, 0.95, 0.85)
		add_child(o)

	camera = Camera3D.new()
	camera.fov = 55
	camera.position = Vector3(0, 7, 10)
	add_child(camera)
	camera.look_at(Vector3(0, RING_TOP + 1, 0))


func _build_arena() -> void:
	# Arena floor and entrance stage
	_box(Vector3(60, 0.1, 60), Vector3(0, -0.05, 0), Color(0.12, 0.1, 0.14))
	_box(Vector3(5, 0.25, 9), Vector3(0, 0.125, -10), Color(0.2, 0.2, 0.25))
	_box(Vector3(12, 5, 0.4), Vector3(0, 2.5, -15), Color(0.08, 0.05, 0.15))
	var sign3d := Label3D.new()
	sign3d.text = "TURNBUCKLE THUNDER"
	sign3d.font_size = 160
	sign3d.outline_size = 24
	sign3d.modulate = Color(1.0, 0.82, 0.2)
	sign3d.position = Vector3(0, 3.2, -14.7)
	add_child(sign3d)
	var sub := Label3D.new()
	sub.text = "made with Xogot"
	sub.font_size = 70
	sub.modulate = Color(0.6, 0.8, 1.0)
	sub.position = Vector3(0, 2.0, -14.7)
	add_child(sub)

	# Ring
	_box(Vector3(8.8, 0.95, 8.8), Vector3(0, 0.475, 0), Color(0.06, 0.06, 0.08))  # skirt
	_box(Vector3(8.6, 0.12, 8.6), Vector3(0, 0.95, 0), Color(0.82, 0.82, 0.86))    # apron edge
	_box(Vector3(7.6, 0.02, 7.6), Vector3(0, 1.0, 0), Color(0.25, 0.4, 0.85))      # canvas
	_box(Vector3(2.4, 0.021, 2.4), Vector3(0, 1.001, 0), Color(0.95, 0.8, 0.2))    # center logo
	var h := 4.15
	for cx in [-h, h]:
		for cz in [-h, h]:
			_cyl(0.11, 1.75, Vector3(cx, RING_TOP + 0.85, cz), Color(0.75, 0.75, 0.78))
			_box(Vector3(0.3, 1.0, 0.3), Vector3(cx * 0.985, RING_TOP + 0.85, cz * 0.985), Color(0.85, 0.15, 0.15))
	var rope_colors := [Color(0.9, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.15, 0.3, 0.95)]
	var heights := [0.45, 0.85, 1.25]
	for i in 3:
		var y: float = RING_TOP + heights[i]
		var c: Color = rope_colors[i]
		_box(Vector3(2 * h, 0.06, 0.06), Vector3(0, y, h), c)
		_box(Vector3(2 * h, 0.06, 0.06), Vector3(0, y, -h), c)
		_box(Vector3(0.06, 0.06, 2 * h), Vector3(h, y, 0), c)
		_box(Vector3(0.06, 0.06, 2 * h), Vector3(-h, y, 0), c)

	# Barricade
	for side in [-1, 1]:
		_box(Vector3(16, 0.9, 0.2), Vector3(0, 0.45, side * 7.5), Color(0.15, 0.15, 0.18))
		_box(Vector3(0.2, 0.9, 15), Vector3(side * 8.0, 0.45, 0), Color(0.15, 0.15, 0.18))


func _build_crowd() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 0.8, 0.35)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mesh.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var xforms: Array[Transform3D] = []
	for row in 6:
		var dist := 9.0 + row * 1.0
		var y := 0.4 + row * 0.55
		# three sides (leave the entrance side at -z open)
		for side in 3:
			var n := int(dist * 2.6)
			for i in n:
				var t := (i + randf() * 0.3) / float(n) * 2.0 - 1.0
				var p := Vector3.ZERO
				match side:
					0: p = Vector3(t * dist, y, dist)
					1: p = Vector3(dist, y, t * dist)
					2: p = Vector3(-dist, y, t * dist)
				var tr := Transform3D(Basis(), p)
				tr = tr.looking_at(Vector3(0, y, 0), Vector3.UP)
				xforms.append(tr)
		# bleacher step
		_box(Vector3(2 * dist + 2, 0.55, 1.0), Vector3(0, y - 0.55, dist), Color(0.1, 0.1, 0.13))
		_box(Vector3(1.0, 0.55, 2 * dist + 2), Vector3(dist, y - 0.55, 0), Color(0.1, 0.1, 0.13))
		_box(Vector3(1.0, 0.55, 2 * dist + 2), Vector3(-dist, y - 0.55, 0), Color(0.1, 0.1, 0.13))
	mm.instance_count = xforms.size()
	var palette := [Color(0.9, 0.2, 0.2), Color(0.2, 0.4, 0.9), Color(0.95, 0.85, 0.2), Color(0.9, 0.9, 0.9),
		Color(0.2, 0.7, 0.3), Color(0.6, 0.3, 0.8), Color(0.15, 0.15, 0.15), Color(0.9, 0.5, 0.2)]
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, palette[randi() % palette.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


func _spawn(n: String, look: Dictionary, cpu: bool, pos: Vector3) -> Node3D:
	var w: Node3D = Wrestler.new()
	ring_root.add_child(w)
	w.setup(n, look, cpu)
	w.position = pos
	w.announce.connect(func(text): _announce(text, 1.2))
	w.impact.connect(func(s): cam_shake = max(cam_shake, s))
	w.pin_count.connect(_on_pin_count)
	w.won.connect(func(): _on_win(w))
	return w


# ---------------------------------------------------------------- HUD

func _make_bar(color: Color, height: float) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 100
	pb.value = 100
	pb.custom_minimum_size = Vector2(380, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_border_width_all(2)
	bg.border_color = Color(1, 1, 1, 0.8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fill)
	pb.set_meta("fill", fill)
	return pb


func _player_panel(w: Node3D, right: bool) -> Control:
	var box := VBoxContainer.new()
	var name_label := Label.new()
	name_label.text = w.display_name + (" (CPU)" if w.is_cpu else " (YOU)")
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.add_theme_color_override("font_color", w.gear_color.lightened(0.3))
	if right:
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(name_label)
	var hp := _make_bar(Color(0.2, 0.85, 0.3), 22)
	box.add_child(hp)
	var sp := _make_bar(Color(1.0, 0.75, 0.1), 10)
	sp.value = 0
	box.add_child(sp)
	if right:
		hp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
		sp.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	bars[w] = {"hp": hp, "sp": sp, "fill": hp.get_meta("fill"), "spfill": sp.get_meta("fill")}
	return box


func _place(c: Control, anchor_x: float, anchor_y: float, rect: Rect2) -> void:
	# Anchor a control to a point of the screen, with rect offsets relative to that point.
	c.anchor_left = anchor_x
	c.anchor_right = anchor_x
	c.anchor_top = anchor_y
	c.anchor_bottom = anchor_y
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.position.x + rect.size.x
	c.offset_bottom = rect.position.y + rect.size.y


func _big_label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	touch = TouchControls.new()
	hud.add_child(touch)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for s in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + s, 24)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	row.add_child(_player_panel(p1, false))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_player_panel(p2, true))

	announce_label = _big_label(54)
	_place(announce_label, 0.5, 0.0, Rect2(-400, 120, 800, 90))
	announce_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	hud.add_child(announce_label)

	count_label = _big_label(140)
	_place(count_label, 0.5, 0.5, Rect2(-200, -140, 400, 200))
	hud.add_child(count_label)

	hint_label = _big_label(20)
	_place(hint_label, 0.5, 1.0, Rect2(-290, -90, 580, 80))
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(hint_label)

	win_panel = Control.new()
	win_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_panel.visible = false
	hud.add_child(win_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.add_child(dim)
	win_label = _big_label(64)
	win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_label.offset_bottom = -120
	win_panel.add_child(win_label)
	var btn := Button.new()
	btn.text = "  REMATCH  "
	btn.add_theme_font_size_override("font_size", 40)
	_place(btn, 0.5, 0.5, Rect2(-140, 40, 280, 80))
	btn.pressed.connect(_restart)
	win_panel.add_child(btn)


func _announce(text: String, secs: float) -> void:
	if match_over and text != "":
		return
	announce_label.text = text
	announce_timer = secs


func _on_pin_count(c: int) -> void:
	count_label.text = str(c) + ("!" if c >= 3 else "")
	count_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2) if c >= 3 else Color.WHITE)
	count_timer = 0.7 if c < 3 else 2.5
	cam_shake = max(cam_shake, 0.25)


func _on_win(w: Node3D) -> void:
	match_over = true
	announce_label.text = ""
	win_label.text = "%s WINS!" % w.display_name
	win_label.add_theme_color_override("font_color", w.gear_color.lightened(0.35))
	get_tree().create_timer(1.2).timeout.connect(func(): win_panel.visible = true)


func _restart() -> void:
	get_tree().reload_current_scene()


func _hint_text() -> String:
	var st: int = p1.state
	if st == Wrestler.S.TIEUP_ATK:
		var fin := "Dir+GRAB: THUNDER DRIVER (SPECIAL!)" if p1.is_special_ready() else "Dir+GRAB: DDT"
		return "LOCK-UP!  STRIKE: Knee Lift   Dir+STRIKE: Suplex\nGRAB: Body Slam   " + fin
	if st == Wrestler.S.TIEUP_DEF:
		return "You're caught! Tap GRAB or STRIKE to try a REVERSAL"
	if st == Wrestler.S.PINNED:
		return "MASH ANY BUTTON TO KICK OUT!"
	if st == Wrestler.S.RUN:
		return "Running! STRIKE: Clothesline   RUN: stop"
	if p2.state == Wrestler.S.DOWN:
		return "Opponent is down! Get close and press PIN"
	if p1.is_special_ready():
		return "SPECIAL! Grab, then Direction + GRAB for your finisher"
	return ""


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if not match_over:
		var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if touch.joy_vector.length() > mv.length():
			mv = touch.joy_vector
		p1.in_move = mv
		p1.in_strike = Input.is_action_just_pressed("strike")
		p1.in_grapple = Input.is_action_just_pressed("grapple")
		p1.in_run = Input.is_action_just_pressed("run")
		p1.in_pin = Input.is_action_just_pressed("pin")
		p1.any_pressed = p1.in_strike or p1.in_grapple or p1.in_run or p1.in_pin
	else:
		p1.in_move = Vector2.ZERO
		if Input.is_action_just_pressed("restart"):
			_restart()
			return
	p1.tick(delta)
	p2.tick(delta)

	_update_camera(delta)
	_update_hud(delta)


func _update_camera(delta: float) -> void:
	var a: Vector3 = p1.global_position
	var b: Vector3 = p2.global_position
	var mid := (a + b) * 0.5
	var spread := a.distance_to(b)
	cam_target = cam_target.lerp(mid, clamp(delta * 4.0, 0.0, 1.0))
	var want := cam_target + Vector3(0, 5.0 + spread * 0.35, 7.5 + spread * 0.7)
	camera.position = camera.position.lerp(want, clamp(delta * 3.0, 0.0, 1.0))
	camera.look_at(cam_target + Vector3(0, 0.9, 0))
	if cam_shake > 0.0:
		camera.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * cam_shake * 0.25
		cam_shake = max(0.0, cam_shake - delta * 2.5)


func _update_hud(delta: float) -> void:
	for w in [p1, p2]:
		var d: Dictionary = bars[w]
		d["hp"].value = lerp(float(d["hp"].value), w.health, clamp(delta * 8.0, 0.0, 1.0))
		d["sp"].value = w.spirit
		var hcol := Color(0.2, 0.85, 0.3)
		if w.health < 30:
			hcol = Color(0.95, 0.2, 0.15)
		elif w.health < 60:
			hcol = Color(0.95, 0.7, 0.1)
		d["fill"].bg_color = hcol
		var flash: bool = w.is_special_ready() and int(Time.get_ticks_msec() / 150) % 2 == 0
		d["spfill"].bg_color = Color(1, 1, 1) if flash else Color(1.0, 0.75, 0.1)

	if announce_timer > 0.0:
		announce_timer -= delta
		announce_label.modulate.a = clamp(announce_timer * 3.0, 0.0, 1.0)
	if count_timer > 0.0:
		count_timer -= delta
		count_label.modulate.a = clamp(count_timer * 3.0, 0.0, 1.0)
	else:
		count_label.text = ""
	hint_label.text = "" if match_over else _hint_text()

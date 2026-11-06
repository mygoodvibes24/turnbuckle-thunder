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
	}
	var volcano := {
		"gear": Color(1.0, 0.5, 0.1), "trunks": Color(0.12, 0.3, 0.85), "boot_color": Color(0.12, 0.3, 0.85),
		"skin": Color(0.6, 0.42, 0.3), "tights": true, "mask": true,
		"mask_color": Color(0.12, 0.3, 0.85), "mask_trim": Color(1.0, 0.55, 0.1), "hair_color": Color.BLACK,
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

const HUD_GOLD := Color(1.0, 0.82, 0.18)
const HUD_HP_HIGH := Color(0.25, 0.9, 0.3)
const HUD_HP_MID := Color(1.0, 0.75, 0.1)
const HUD_HP_LOW := Color(0.95, 0.18, 0.12)
const HUD_SLANT := 12.0
const HUD_BADGE := 62.0

var hud_font: FontVariation
var hud_font_italic: FontVariation
var bar_canvas: Control
var hint_panel: PanelContainer
var hint_style: StyleBoxFlat
var help_button: Button
var help_panel: PanelContainer
var win_banner: Panel
var win_header: Label
var win_button: Button
var announce_tween: Tween
var count_tween: Tween
var hud_clock := 0.0


func _make_bar(w: Node3D, right: bool) -> Dictionary:
	# Per-wrestler bar state. "hp" is the displayed value, "chip" the white lag bar that
	# shows recent damage and drains after a short delay.
	var hp: float = w.health
	return {"right": right, "hp": hp, "chip": hp, "chip_delay": 0.0, "last": hp, "sp": 0.0, "flash": 0.0}


func _player_panel(w: Node3D, right: bool) -> void:
	bars[w] = _make_bar(w, right)


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
	l.add_theme_font_override("font", hud_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 12)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _hud_box(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	return sb


func _hud_button(text: String, font_size: int, color: Color, radius: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_override("font", hud_font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 0.8))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", Color.BLACK)
	btn.add_theme_constant_override("outline_size", 6)
	var normal := _hud_box(color, Color(1, 1, 1, 0.9), radius, 4)
	normal.shadow_color = Color(0, 0, 0, 0.5)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 4)
	var pressed := _hud_box(color.darkened(0.3), HUD_GOLD, radius, 4)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", normal)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


func _hud_safe_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if touch != null:
		l = touch.safe_left
		t = touch.safe_top
		r = touch.safe_right
		b = touch.safe_bottom
	return Rect2(l, t, vp.x - l - r, vp.y - t - b)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	hud_font = FontVariation.new()
	hud_font.base_font = ThemeDB.fallback_font
	hud_font.variation_embolden = 0.9
	hud_font_italic = FontVariation.new()
	hud_font_italic.base_font = ThemeDB.fallback_font
	hud_font_italic.variation_embolden = 1.0
	hud_font_italic.variation_transform = Transform2D(Vector2(1, 0.22), Vector2(0, 1), Vector2.ZERO)

	touch = TouchControls.new()
	hud.add_child(touch)

	# Health / spirit bars are custom-drawn on one full-screen canvas.
	_player_panel(p1, false)
	_player_panel(p2, true)
	bar_canvas = Control.new()
	bar_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_canvas.draw.connect(_draw_hud_bars)
	hud.add_child(bar_canvas)

	announce_label = _big_label(66)
	announce_label.add_theme_font_override("font", hud_font_italic)
	announce_label.add_theme_color_override("font_color", HUD_GOLD)
	announce_label.add_theme_color_override("font_outline_color", Color(0.45, 0.02, 0.05))
	announce_label.add_theme_constant_override("outline_size", 16)
	hud.add_child(announce_label)

	count_label = _big_label(200)
	count_label.add_theme_font_override("font", hud_font_italic)
	count_label.add_theme_constant_override("outline_size", 22)
	_place(count_label, 0.5, 0.5, Rect2(-260, -200, 520, 290))
	hud.add_child(count_label)

	# Context hint: dark rounded panel at the bottom center, between stick and buttons.
	hint_panel = PanelContainer.new()
	hint_style = _hud_box(Color(0.03, 0.03, 0.08, 0.8), Color(HUD_GOLD.r, HUD_GOLD.g, HUD_GOLD.b, 0.9), 16, 3)
	hint_style.content_margin_left = 22
	hint_style.content_margin_right = 22
	hint_style.content_margin_top = 8
	hint_style.content_margin_bottom = 10
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_panel.visible = false
	hud.add_child(hint_panel)
	hint_label = _big_label(30)
	hint_label.add_theme_constant_override("outline_size", 5)
	hint_label.add_theme_constant_override("line_spacing", 2)
	hint_panel.add_child(hint_label)

	# "?" button toggles the HOW TO PLAY panel (the match keeps running).
	help_button = _hud_button("?", 34, Color(0.1, 0.1, 0.18, 0.85), 30)
	help_button.pressed.connect(_toggle_help)
	hud.add_child(help_button)
	help_panel = _build_help_panel()
	hud.add_child(help_panel)

	_build_win_panel()

	touch.connect("layout_changed", _layout_hud)
	_layout_hud()


func _build_help_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := _hud_box(Color(0.02, 0.02, 0.06, 0.9), HUD_GOLD, 20, 3)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_place(panel, 0.5, 0.5, Rect2(0, 0, 0, 0))
	panel.visible = false
	panel.gui_input.connect(_on_help_panel_input)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := _big_label(36)
	title.text = "HOW TO PLAY"
	title.add_theme_font_override("font", hud_font_italic)
	title.add_theme_color_override("font_color", HUD_GOLD)
	title.add_theme_constant_override("outline_size", 8)
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	var rows: Array[PackedStringArray] = [
		PackedStringArray(["STICK", "Move around the ring"]),
		PackedStringArray(["STRIKE", "Punch  (3 in a row = combo)"]),
		PackedStringArray(["GRAB", "Lock up when close"]),
		PackedStringArray(["RUN", "Hit the ropes, STRIKE = Clothesline"]),
		PackedStringArray(["PIN", "Cover a downed foe (far: Taunt)"]),
		PackedStringArray(["LOCK-UP", "STRIKE Knee  /  STICK+STRIKE Suplex"]),
		PackedStringArray(["", "GRAB Slam  /  STICK+GRAB DDT"]),
		PackedStringArray(["SPECIAL", "Full spirit: lock up + STICK+GRAB"]),
		PackedStringArray(["CAUGHT", "Tap GRAB or STRIKE to reverse"]),
		PackedStringArray(["PINNED", "Mash any button to kick out!"]),
	]
	for row in rows:
		var key := Label.new()
		key.text = row[0]
		key.add_theme_font_override("font", hud_font)
		key.add_theme_font_size_override("font_size", 24)
		key.add_theme_color_override("font_color", HUD_GOLD)
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(key)
		var desc := Label.new()
		desc.text = row[1]
		desc.add_theme_font_override("font", hud_font)
		desc.add_theme_font_size_override("font_size", 24)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(desc)
	var foot := _big_label(20)
	foot.text = "Tap here or ? to close"
	foot.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	foot.add_theme_constant_override("outline_size", 4)
	col.add_child(foot)
	return panel


func _build_win_panel() -> void:
	win_panel = Control.new()
	win_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.visible = false
	hud.add_child(win_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_panel.add_child(dim)

	# Full-width slanted banner across the middle of the screen.
	win_banner = Panel.new()
	win_banner.anchor_left = 0.0
	win_banner.anchor_right = 1.0
	win_banner.anchor_top = 0.5
	win_banner.anchor_bottom = 0.5
	win_banner.offset_left = -80
	win_banner.offset_right = 80
	win_banner.offset_top = -190
	win_banner.offset_bottom = 10
	win_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := _hud_box(Color(0.5, 0.05, 0.08, 0.95), HUD_GOLD, 0, 0)
	sb.border_width_top = 7
	sb.border_width_bottom = 7
	sb.skew = Vector2(0.25, 0.0)
	win_banner.add_theme_stylebox_override("panel", sb)
	win_panel.add_child(win_banner)

	win_header = _big_label(36)
	win_header.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_header.offset_top = 10
	win_header.offset_bottom = -120
	win_header.add_theme_color_override("font_color", Color.WHITE)
	win_header.add_theme_constant_override("outline_size", 8)
	win_banner.add_child(win_header)

	win_label = _big_label(84)
	win_label.add_theme_font_override("font", hud_font_italic)
	win_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_label.offset_top = 50
	win_label.offset_bottom = -6
	win_label.add_theme_constant_override("outline_size", 16)
	win_banner.add_child(win_label)

	win_button = _hud_button("REMATCH", 46, Color(0.85, 0.12, 0.14), 22)
	_place(win_button, 0.5, 0.5, Rect2(-180, 50, 360, 104))
	win_button.pressed.connect(_restart)
	win_panel.add_child(win_button)


func _layout_hud() -> void:
	var sr := _hud_safe_rect()
	# Announcer sits just below the bars; hint panel at the bottom center above the
	# safe-area bottom; "?" button at the top center between the two bars.
	_place(announce_label, 0.5, 0.0, Rect2(-520, sr.position.y + 108, 1040, 120))
	_place(hint_panel, 0.5, 1.0, Rect2(0, -(get_viewport().get_visible_rect().size.y - sr.end.y) - 14, 0, 0))
	_place(help_button, 0.5, 0.0, Rect2(-30, sr.position.y + 12, 60, 60))
	if bar_canvas != null:
		bar_canvas.queue_redraw()


func _toggle_help() -> void:
	help_panel.visible = not help_panel.visible


func _on_help_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			help_panel.visible = false
			help_panel.accept_event()


func _pop(c: Control, from_scale: float, from_rot: float, secs: float) -> Tween:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(from_scale, from_scale)
	c.rotation = from_rot
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, secs).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", from_rot * 0.25, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tw


func _announce(text: String, secs: float) -> void:
	if match_over and text != "":
		return
	announce_label.text = text
	announce_timer = secs
	if text == "":
		return
	var up := text.to_upper()
	var col := HUD_GOLD
	var outline := Color(0.45, 0.02, 0.05)
	if up.contains("REVERSAL") or up.contains("KICK"):
		col = Color(0.45, 0.95, 1.0)
		outline = Color(0.02, 0.1, 0.4)
	elif up.contains("!!") or up.contains("FIGHT"):
		col = Color(1.0, 0.55, 0.15)
		outline = Color(0.3, 0.0, 0.0)
	announce_label.add_theme_color_override("font_color", col)
	announce_label.add_theme_color_override("font_outline_color", outline)
	announce_label.modulate.a = 1.0
	if announce_tween != null and announce_tween.is_valid():
		announce_tween.kill()
	var tilt := -0.12 if randf() < 0.5 else 0.12
	announce_tween = _pop(announce_label, 1.6, tilt, 0.28)


func _on_pin_count(c: int) -> void:
	count_label.text = str(c) + ("!" if c >= 3 else "")
	count_label.add_theme_color_override("font_color", Color(1, 0.25, 0.15) if c >= 3 else Color.WHITE)
	count_label.add_theme_color_override("font_outline_color", Color(0.35, 0.0, 0.0) if c >= 3 else Color(0.05, 0.1, 0.45))
	count_label.modulate.a = 1.0
	count_timer = 0.7 if c < 3 else 2.5
	cam_shake = max(cam_shake, 0.25)
	# Slam in: drop from huge to slightly small, then settle.
	if count_tween != null and count_tween.is_valid():
		count_tween.kill()
	count_label.pivot_offset = count_label.size * 0.5
	count_label.scale = Vector2(3.0, 3.0)
	count_label.rotation = randf_range(-0.2, 0.2)
	count_tween = create_tween()
	count_tween.set_parallel(true)
	count_tween.tween_property(count_label, "scale", Vector2(0.88, 0.88), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	count_tween.tween_property(count_label, "rotation", 0.0, 0.12)
	count_tween.chain().tween_property(count_label, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_win(w: Node3D) -> void:
	match_over = true
	announce_label.text = ""
	var nm: String = w.display_name
	var cpu: bool = w.is_cpu
	var gear: Color = w.gear_color
	win_label.text = "%s WINS!" % nm
	win_label.add_theme_color_override("font_color", gear.lightened(0.45))
	win_header.text = "DEFEAT..." if cpu else "WINNER!"
	var sb := win_banner.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		var bg := gear.darkened(0.55)
		sb.bg_color = Color(bg.r, bg.g, bg.b, 0.95)
	help_panel.visible = false
	get_tree().create_timer(1.2).timeout.connect(_show_win)


func _show_win() -> void:
	win_panel.visible = true
	touch.visible = false
	hint_panel.visible = false
	help_button.visible = false
	win_banner.pivot_offset = win_banner.size * 0.5
	win_banner.scale = Vector2(1.0, 0.0)
	var tw := create_tween()
	tw.tween_property(win_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop(win_label, 1.8, -0.1, 0.4)
	win_button.pivot_offset = win_button.size * 0.5
	win_button.scale = Vector2.ZERO
	var tb := create_tween()
	tb.tween_interval(0.35)
	tb.tween_property(win_button, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---- console-style bars (drawn on bar_canvas)

func _para(x0: float, dir: float, u0: float, u1: float, y: float, h: float, s_top: float, s_bot: float) -> PackedVector2Array:
	# Slanted quad measured along "u" from the outer screen edge x0 (dir = +1 left side, -1 right).
	var pts := PackedVector2Array()
	pts.append(Vector2(x0 + dir * (u0 + s_top), y))
	pts.append(Vector2(x0 + dir * (u1 + s_top), y))
	pts.append(Vector2(x0 + dir * (u1 + s_bot), y + h))
	pts.append(Vector2(x0 + dir * (u0 + s_bot), y + h))
	return pts


func _fill_para(x0: float, dir: float, u0: float, u1: float, y: float, h: float, slant: float, top: Color, bottom: Color) -> void:
	if u1 - u0 < 1.0:
		return
	var pts := _para(x0, dir, u0, u1, y, h, slant, 0.0)
	bar_canvas.draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _text_u(x0: float, dir: float, u: float, width: float, y: float, text: String, size: int, col: Color, font: Font, outline: int) -> void:
	# Draw text starting at distance u from the outer edge (left- or right-aligned to match).
	var pos := Vector2(x0 + u, y) if dir > 0.0 else Vector2(x0 - u - width, y)
	var align := HORIZONTAL_ALIGNMENT_LEFT if dir > 0.0 else HORIZONTAL_ALIGNMENT_RIGHT
	if outline > 0:
		bar_canvas.draw_string_outline(font, pos, text, align, width, size, outline, Color(0, 0, 0, 0.9))
	bar_canvas.draw_string(font, pos, text, align, width, size, col)


func _initials(n: String) -> String:
	var out := ""
	for part in n.split(" ", false):
		if part == "THE" or out.length() >= 2:
			continue
		out += part.substr(0, 1)
	if out.length() < 2:
		var words := n.split(" ", false)
		var last: String = words[words.size() - 1] if words.size() > 0 else n
		out = last.substr(0, 2)
	return out


func _draw_hud_bars() -> void:
	var sr := _hud_safe_rect()
	var gap := 110.0  # room for the "?" button
	var side_w: float = clampf((sr.size.x - gap) * 0.5 - 10.0, 300.0, 540.0)
	for w in [p1, p2]:
		var d: Dictionary = bars[w]
		_draw_player_bar(w, d, sr, side_w)


func _draw_player_bar(w: Node3D, d: Dictionary, sr: Rect2, side_w: float) -> void:
	var right: bool = d["right"]
	var dir := -1.0 if right else 1.0
	var x0 := (sr.end.x - 8.0) if right else (sr.position.x + 8.0)
	var top := sr.position.y + 10.0
	var gear: Color = w.gear_color
	var nm: String = w.display_name
	var cpu: bool = w.is_cpu
	var hp: float = d["hp"]
	var chip: float = d["chip"]
	var sp: float = d["sp"]
	var flash: float = d["flash"]
	var special: bool = w.is_special_ready()
	var blink := int(hud_clock * 7.0) % 2 == 0

	# Portrait badge with initials.
	var bx := x0 if not right else x0 - HUD_BADGE
	var badge := _hud_box(gear.darkened(0.25), Color.WHITE if flash < 0.5 else HUD_HP_LOW, 10, 4)
	badge.shadow_color = Color(0, 0, 0, 0.5)
	badge.shadow_size = 4
	bar_canvas.draw_style_box(badge, Rect2(bx, top, HUD_BADGE, HUD_BADGE))
	var shine := gear.lightened(0.35)
	bar_canvas.draw_rect(Rect2(bx + 6, top + 6, HUD_BADGE - 12, 10), Color(shine.r, shine.g, shine.b, 0.5))
	bar_canvas.draw_string_outline(hud_font_italic, Vector2(bx, top + 44), _initials(nm), HORIZONTAL_ALIGNMENT_CENTER, HUD_BADGE, 30, 6, Color.BLACK)
	bar_canvas.draw_string(hud_font_italic, Vector2(bx, top + 44), _initials(nm), HORIZONTAL_ALIGNMENT_CENTER, HUD_BADGE, 30, Color.WHITE)

	var u0 := HUD_BADGE + 8.0
	var u1 := side_w
	var plate_w := u1 - u0
	# Name plate.
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1 - 30.0, top, 26.0, HUD_SLANT, 0.0), Color(0, 0, 0, 0.7))
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1 - 30.0, top + 23.0, 3.0, HUD_SLANT * 0.12, 0.0), gear.lightened(0.2))
	_text_u(x0, dir, u0 + 12.0, plate_w - 110.0, top + 21.0, nm, 22, gear.lightened(0.5), hud_font_italic, 5)
	var tag := "CPU" if cpu else "1P"
	var tag_w := 50.0
	var tag_u := u1 - 30.0 - tag_w - 6.0
	var tag_x := (x0 + tag_u) if not right else (x0 - tag_u - tag_w)
	bar_canvas.draw_style_box(_hud_box(gear if not cpu else Color(0.35, 0.35, 0.4), Color.WHITE, 6, 2), Rect2(tag_x, top + 3, tag_w, 20))
	bar_canvas.draw_string(hud_font, Vector2(tag_x, top + 19), tag, HORIZONTAL_ALIGNMENT_CENTER, tag_w, 16, Color.WHITE)

	# Health bar: black frame, dark well, white damage chip, gradient fill, gloss, ticks.
	var hy := top + 30.0
	var hh := 24.0
	var blen := u1 - u0
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0 - 4.0, u1 + 4.0, hy - 4.0, hh + 8.0, HUD_SLANT + 1.0, -1.0), Color(0, 0, 0, 0.85))
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1, hy, hh, HUD_SLANT, 0.0), Color(0.16, 0.04, 0.05, 0.9))
	var chip_col := Color(1, 1, 1) if blink else Color(1, 0.85, 0.5)
	_fill_para(x0, dir, u0, u0 + blen * clampf(chip / 100.0, 0.0, 1.0), hy, hh, HUD_SLANT, chip_col, chip_col.darkened(0.2))
	var hcol := HUD_HP_HIGH
	if hp < 30.0:
		hcol = HUD_HP_LOW
		if hp < 20.0 and blink:
			hcol = hcol.lightened(0.3)
	elif hp < 60.0:
		hcol = HUD_HP_MID
	var hp_u := u0 + blen * clampf(hp / 100.0, 0.0, 1.0)
	_fill_para(x0, dir, u0, hp_u, hy, hh, HUD_SLANT, hcol.lightened(0.35), hcol.darkened(0.35))
	if hp_u - u0 > 2.0:
		var gloss := _para(x0, dir, u0, hp_u, hy + 2.0, hh * 0.3, HUD_SLANT * 0.92, HUD_SLANT * 0.62)
		bar_canvas.draw_colored_polygon(gloss, Color(1, 1, 1, 0.35))
	for k in range(1, 10):
		var tu := u0 + blen * float(k) / 10.0
		bar_canvas.draw_line(Vector2(x0 + dir * (tu + HUD_SLANT), hy), Vector2(x0 + dir * tu, hy + hh), Color(0, 0, 0, 0.3), 2.0)
	if flash > 0.0:
		bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u1, hy, hh, HUD_SLANT, 0.0), Color(1, 1, 1, 0.35 * flash))

	# Spirit bar + SPECIAL! badge.
	var sy := hy + hh + 8.0
	var sh := 12.0
	var s_len := blen * 0.72
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0 - 3.0, u0 + s_len + 3.0, sy - 3.0, sh + 6.0, 7.0, -1.0), Color(0, 0, 0, 0.85))
	bar_canvas.draw_colored_polygon(_para(x0, dir, u0, u0 + s_len, sy, sh, 6.0, 0.0), Color(0.1, 0.08, 0.2, 0.9))
	var scol := Color(0.3, 0.75, 1.0)
	if special:
		scol = Color(1, 1, 1) if blink else HUD_GOLD
	_fill_para(x0, dir, u0, u0 + s_len * clampf(sp / 100.0, 0.0, 1.0), sy, sh, 6.0, scol.lightened(0.3), scol.darkened(0.3))
	if special:
		var bw := 130.0
		var bu := u0 + s_len + 14.0
		var bxx := (x0 + bu) if not right else (x0 - bu - bw)
		var pulse := 1.0 + 0.08 * sin(hud_clock * 12.0)
		var rect := Rect2(bxx, sy - 9.0, bw, 30.0)
		rect = rect.grow((pulse - 1.0) * 40.0)
		var badge_sp := _hud_box(Color(0.85, 0.1, 0.1) if blink else Color(0.95, 0.5, 0.05), Color.WHITE, 8, 3)
		badge_sp.skew = Vector2(-0.2 * dir, 0.0)
		bar_canvas.draw_style_box(badge_sp, rect)
		bar_canvas.draw_string_outline(hud_font_italic, Vector2(rect.position.x, rect.position.y + 23.0), "SPECIAL!", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, 5, Color.BLACK)
		bar_canvas.draw_string(hud_font_italic, Vector2(rect.position.x, rect.position.y + 23.0), "SPECIAL!", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 22, Color(1, 1, 0.6))


func _restart() -> void:
	get_tree().reload_current_scene()


func _hint_text() -> String:
	var st: int = p1.state
	if st == Wrestler.S.TIEUP_ATK:
		var fin := "THUNDER DRIVER!" if p1.is_special_ready() else "DDT"
		return "STRIKE: Knee      STICK + STRIKE: Suplex\nGRAB: Slam      STICK + GRAB: " + fin
	if st == Wrestler.S.TIEUP_DEF:
		return "CAUGHT!  Tap GRAB or STRIKE to reverse"
	if st == Wrestler.S.PINNED:
		return "MASH ANY BUTTON TO KICK OUT!"
	if st == Wrestler.S.RUN:
		return "STRIKE: Clothesline      RUN: Stop"
	if p2.state == Wrestler.S.DOWN:
		return "He's down!  Get close and PIN"
	if p1.is_special_ready():
		return "SPECIAL READY!  Lock up, then STICK + GRAB"
	if hud_clock < 6.0:
		return "Walk up and GRAB to lock up!"
	return ""


func _update_touch_labels() -> void:
	# Context-sensitive captions on the touch buttons.
	if touch == null:
		return
	var st: int = p1.state
	var opp: int = p2.state
	var special: bool = p1.is_special_ready()
	var mv: Vector2 = p1.in_move
	var dir_held := mv.length() > 0.5
	var glow := "grapple" if special else ""
	if match_over:
		touch.set_labels("", "", "", "")
		glow = ""
	elif st == Wrestler.S.PINNED:
		touch.set_labels("MASH!", "MASH!", "MASH!", "MASH!")
		glow = "all"
	elif st == Wrestler.S.TIEUP_ATK:
		var grab_move := ("FINISH!" if special else "DDT") if dir_held else "SLAM"
		touch.set_labels("SUPLEX" if dir_held else "KNEE", grab_move, "", "")
		if not (special and dir_held):
			glow = ""
	elif st == Wrestler.S.TIEUP_DEF:
		touch.set_labels("REVERSE", "REVERSE", "", "")
		glow = "all"
	elif st == Wrestler.S.RUN:
		touch.set_labels("LARIAT", "STOP", "STOP", "")
	else:
		touch.set_labels("PUNCH", "GRAB", "RUN", "PIN" if opp == Wrestler.S.DOWN else "TAUNT")
		if opp == Wrestler.S.DOWN and not special:
			glow = "pin"
	touch.set_highlight(glow)


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
	hud_clock += delta
	for w in [p1, p2]:
		var d: Dictionary = bars[w]
		var hp_now: float = w.health
		var last: float = d["last"]
		if hp_now < last - 0.01:
			d["chip_delay"] = 0.6
			d["flash"] = 1.0
		d["last"] = hp_now
		var shown: float = d["hp"]
		shown = lerpf(shown, hp_now, clampf(delta * 12.0, 0.0, 1.0))
		d["hp"] = shown
		var chip: float = d["chip"]
		var chip_delay: float = d["chip_delay"]
		if chip <= shown:
			chip = shown
		elif chip_delay > 0.0:
			chip_delay -= delta
		else:
			chip = maxf(shown, chip - delta * 40.0)
		d["chip"] = chip
		d["chip_delay"] = chip_delay
		var sp_now: float = w.spirit
		var sp_shown: float = d["sp"]
		d["sp"] = lerpf(sp_shown, sp_now, clampf(delta * 10.0, 0.0, 1.0))
		var flash: float = d["flash"]
		d["flash"] = maxf(0.0, flash - delta * 4.0)
	bar_canvas.queue_redraw()

	if announce_timer > 0.0:
		announce_timer -= delta
		announce_label.modulate.a = clamp(announce_timer * 3.0, 0.0, 1.0)
	if count_timer > 0.0:
		count_timer -= delta
		count_label.modulate.a = clamp(count_timer * 3.0, 0.0, 1.0)
	else:
		count_label.text = ""

	var hint := "" if match_over else _hint_text()
	if hint != hint_label.text:
		hint_label.text = hint
		hint_panel.visible = hint != ""
		# The panel re-sizes around the text by itself (zero offsets + grow); give it a pop.
		if hint != "":
			hint_panel.pivot_offset = Vector2(hint_panel.size.x * 0.5, hint_panel.size.y)
			hint_panel.scale = Vector2(1.12, 1.12)
			create_tween().tween_property(hint_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if hint_panel.visible:
		var st: int = p1.state
		var bc := HUD_GOLD
		if st == Wrestler.S.PINNED or st == Wrestler.S.TIEUP_DEF:
			bc = HUD_HP_LOW if int(hud_clock * 8.0) % 2 == 0 else Color.WHITE
		hint_style.border_color = bc
	_update_touch_labels()

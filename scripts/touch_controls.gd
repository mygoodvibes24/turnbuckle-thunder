extends Control
## On-screen controls for iPad / iPhone (Xogot): a floating joystick on the left half
## of the screen and four action buttons on the right. Buttons are TouchScreenButtons
## bound to input actions, so they support multitouch alongside the joystick.

const JOY_RADIUS := 90.0
const BTN_RADIUS := 62.0
const BUTTONS := [
	{"action": "run", "label": "RUN", "color": Color(0.25, 0.75, 0.35)},
	{"action": "pin", "label": "PIN /\nTAUNT", "color": Color(0.95, 0.75, 0.15)},
	{"action": "grapple", "label": "GRAB", "color": Color(0.25, 0.5, 0.95)},
	{"action": "strike", "label": "STRIKE", "color": Color(0.9, 0.25, 0.25)},
]

var joy_vector := Vector2.ZERO
var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _buttons: Array[TouchScreenButton] = []
var _btn_centers: Array[Vector2] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in BUTTONS:
		var tsb := TouchScreenButton.new()
		var shape := CircleShape2D.new()
		shape.radius = BTN_RADIUS
		tsb.shape = shape
		tsb.shape_centered = true
		tsb.action = b["action"]
		tsb.passby_press = false
		add_child(tsb)
		_buttons.append(tsb)
		_btn_centers.append(Vector2.ZERO)


func _layout() -> Array[Vector2]:
	var s := get_viewport_rect().size
	var out: Array[Vector2] = [
		Vector2(s.x - 255, s.y - 270),  # RUN
		Vector2(s.x - 105, s.y - 270),  # PIN
		Vector2(s.x - 255, s.y - 120),  # GRAB
		Vector2(s.x - 105, s.y - 120),  # STRIKE
	]
	return out


func _joy_home() -> Vector2:
	return Vector2(170, get_viewport_rect().size.y - 170)


func _process(_delta: float) -> void:
	var pos := _layout()
	for i in _buttons.size():
		_buttons[i].position = pos[i]
		_btn_centers[i] = pos[i]
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var half := get_viewport_rect().size.x * 0.45
		if event.pressed and _joy_index == -1 and event.position.x < half:
			_joy_index = event.index
			_joy_center = event.position
			_joy_pos = event.position
			_update_joy()
		elif not event.pressed and event.index == _joy_index:
			_joy_index = -1
			joy_vector = Vector2.ZERO
	elif event is InputEventScreenDrag and event.index == _joy_index:
		_joy_pos = event.position
		_update_joy()


func _update_joy() -> void:
	var v := (_joy_pos - _joy_center) / JOY_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	joy_vector = v if v.length() > 0.12 else Vector2.ZERO


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Joystick
	var c := _joy_center if _joy_index != -1 else _joy_home()
	draw_circle(c, JOY_RADIUS, Color(1, 1, 1, 0.12))
	draw_arc(c, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
	draw_circle(c + joy_vector * JOY_RADIUS, 38, Color(1, 1, 1, 0.55))
	# Buttons
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		var p := _btn_centers[i]
		var pressed := Input.is_action_pressed(b["action"])
		var col: Color = b["color"]
		col.a = 0.85 if pressed else 0.5
		draw_circle(p, BTN_RADIUS * (0.92 if pressed else 1.0), col)
		draw_arc(p, BTN_RADIUS, 0, TAU, 40, Color(1, 1, 1, 0.7), 3.0)
		var lines: PackedStringArray = String(b["label"]).split("\n")
		var fs := 20
		var y0 := p.y - (lines.size() - 1) * fs * 0.5 + fs * 0.35
		for li in lines.size():
			draw_string(font, Vector2(p.x - BTN_RADIUS, y0 + li * fs), lines[li],
				HORIZONTAL_ALIGNMENT_CENTER, BTN_RADIUS * 2, fs, Color.WHITE)

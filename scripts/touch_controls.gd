extends Control
## On-screen controls for iPhone / iPad (Xogot): a floating N64-style analog stick on the
## left side of the screen and a compact arc of four colored action buttons hugging the
## bottom-right corner. Buttons are TouchScreenButtons bound to input actions, so they
## support multitouch alongside the stick. Everything is laid out inside the display
## safe area (notch / home indicator) and recomputed when the viewport size changes.
##
## Public API used by main.gd:
##   joy_vector                      -> current stick direction (Vector2, length 0..1)
##   safe_left/top/right/bottom      -> safe-area insets in viewport (logical) pixels
##   layout_changed                  -> emitted after the safe area / layout is recomputed
##   set_labels(strike, grapple, run, pin) -> context-sensitive button captions ("" = idle)
##   set_highlight(action)           -> make one button glow ("all" pulses every button)

signal layout_changed

const JOY_RADIUS := 78.0
const KNOB_RADIUS := 33.0
const BTN_MAIN_R := 54.0
const BTN_R := 45.0
const ARC_R := 126.0
const EDGE_PAD := 18.0
const FALLBACK_SIDE := 60.0
const JOY_ZONE := 0.45  # fraction of the screen width (from the left) that grabs the stick

# The big STRIKE button sits in the corner; the other three form an arc around it.
# angle is in degrees, screen space (180 = left, 270 = up).
const BUTTONS := [
	{"action": "strike", "label": "PUNCH", "color": Color(0.88, 0.14, 0.16), "angle": 0.0, "main": true},
	{"action": "grapple", "label": "GRAB", "color": Color(0.14, 0.4, 0.95), "angle": 180.0, "main": false},
	{"action": "run", "label": "RUN", "color": Color(0.12, 0.7, 0.28), "angle": 225.0, "main": false},
	{"action": "pin", "label": "TAUNT", "color": Color(0.98, 0.74, 0.08), "angle": 270.0, "main": false},
]

var joy_vector := Vector2.ZERO
var safe_left := 0.0
var safe_top := 0.0
var safe_right := 0.0
var safe_bottom := 0.0

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _buttons: Array[TouchScreenButton] = []
var _btn_centers: Array[Vector2] = []
var _labels: Array[String] = []
var _press_flash: Array[float] = []
var _highlight := ""
var _clock := 0.0
var _font: FontVariation


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.9
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		var is_main: bool = b["main"]
		var action: String = b["action"]
		var label: String = b["label"]
		var tsb := TouchScreenButton.new()
		var shape := CircleShape2D.new()
		shape.radius = (BTN_MAIN_R + 4.0) if is_main else (BTN_R + 2.0)
		tsb.shape = shape
		tsb.shape_centered = true
		tsb.action = action
		tsb.passby_press = false
		tsb.pressed.connect(_on_button_pressed.bind(i))
		add_child(tsb)
		_buttons.append(tsb)
		_btn_centers.append(Vector2.ZERO)
		_labels.append(label)
		_press_flash.append(0.0)
	get_viewport().size_changed.connect(_relayout)
	_relayout()


# ---------------------------------------------------------------- public API

func set_labels(strike: String, grapple: String, run: String, pin: String) -> void:
	# Order matches BUTTONS: strike, grapple, run, pin.
	_labels[0] = strike
	_labels[1] = grapple
	_labels[2] = run
	_labels[3] = pin


func set_highlight(action: String) -> void:
	_highlight = action


func safe_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(safe_left, safe_top, vp.x - safe_left - safe_right, vp.y - safe_top - safe_bottom)


# ---------------------------------------------------------------- layout

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android")


func _compute_safe_insets() -> void:
	var vp := get_viewport_rect().size
	var l := 0.0
	var t := 0.0
	var r := 0.0
	var b := 0.0
	if _is_mobile():
		var win := Vector2(DisplayServer.window_get_size())
		var safe: Rect2i = DisplayServer.get_display_safe_area()
		if win.x > 0.0 and win.y > 0.0 and vp.x > 0.0 and vp.y > 0.0 and safe.size.x > 0 and safe.size.y > 0:
			# Safe area is in physical screen pixels; convert to logical viewport pixels.
			var k := vp / win
			l = float(safe.position.x) * k.x
			t = float(safe.position.y) * k.y
			r = (win.x - float(safe.position.x + safe.size.x)) * k.x
			b = (win.y - float(safe.position.y + safe.size.y)) * k.y
		else:
			l = FALLBACK_SIDE
			r = FALLBACK_SIDE
		l = clampf(l, 0.0, vp.x * 0.2)
		r = clampf(r, 0.0, vp.x * 0.2)
		t = clampf(t, 0.0, vp.y * 0.2)
		b = clampf(b, 0.0, vp.y * 0.2)
		# The notch can be on either side in landscape (and flips without a resize), so
		# protect both sides equally, with a little minimum for thumbs on rounded corners.
		var side := maxf(maxf(l, r), 20.0)
		l = side
		r = side
	safe_left = l
	safe_top = t
	safe_right = r
	safe_bottom = b


func _relayout() -> void:
	_compute_safe_insets()
	var vp := get_viewport_rect().size
	var corner := Vector2(vp.x - safe_right - EDGE_PAD - BTN_MAIN_R, vp.y - safe_bottom - EDGE_PAD - BTN_MAIN_R)
	for i in BUTTONS.size():
		var b: Dictionary = BUTTONS[i]
		var is_main: bool = b["main"]
		var p := corner
		if not is_main:
			var ang: float = deg_to_rad(float(b["angle"]))
			p = corner + Vector2(cos(ang), sin(ang)) * ARC_R
		_btn_centers[i] = p
		_buttons[i].position = p
	if _joy_index == -1:
		_joy_center = _joy_home()
	layout_changed.emit()
	queue_redraw()


func _joy_home() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(safe_left + EDGE_PAD + 24.0 + JOY_RADIUS, vp.y - safe_bottom - EDGE_PAD - 14.0 - JOY_RADIUS)


# ---------------------------------------------------------------- input

func _on_button_pressed(i: int) -> void:
	_press_flash[i] = 1.0
	if _is_mobile():
		Input.vibrate_handheld(15)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var zone := get_viewport_rect().size.x * JOY_ZONE
		if st.pressed and _joy_index == -1 and st.position.x < zone:
			_joy_index = st.index
			_joy_center = st.position
			_joy_pos = st.position
			_update_joy()
		elif not st.pressed and st.index == _joy_index:
			_joy_index = -1
			joy_vector = Vector2.ZERO
			_joy_center = _joy_home()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _joy_index:
			_joy_pos = sd.position
			_update_joy()


func _update_joy() -> void:
	var off := _joy_pos - _joy_center
	# If the thumb slides far past the rim, drag the base along so the stick never "sticks".
	var max_off := JOY_RADIUS * 1.3
	if off.length() > max_off:
		_joy_center = _joy_pos - off.normalized() * max_off
		off = _joy_pos - _joy_center
	var v := off / JOY_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	joy_vector = v if v.length() > 0.12 else Vector2.ZERO


func _process(delta: float) -> void:
	_clock += delta
	for i in _press_flash.size():
		_press_flash[i] = maxf(0.0, _press_flash[i] - delta * 5.0)
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	_draw_stick()
	for i in BUTTONS.size():
		_draw_button(i)


func _draw_stick() -> void:
	var active := _joy_index != -1
	var c := _joy_center if active else _joy_home()
	var a := 0.95 if active else 0.6
	var housing := JOY_RADIUS + 12.0
	# Housing: drop shadow, grey plastic body, rim highlight.
	draw_circle(c + Vector2(0, 6), housing, Color(0, 0, 0, 0.35 * a))
	draw_circle(c, housing, Color(0.2, 0.2, 0.24, 0.8 * a))
	draw_arc(c, housing, 0.0, TAU, 56, Color(1, 1, 1, 0.22 * a), 2.5, true)
	# Octagonal gate, like the N64 controller.
	var gate := PackedVector2Array()
	for k in 9:
		var ang := TAU * float(k % 8) / 8.0
		gate.append(c + Vector2(cos(ang), sin(ang)) * JOY_RADIUS)
	var gate_fill := gate.duplicate()
	gate_fill.remove_at(8)
	draw_colored_polygon(gate_fill, Color(0.06, 0.06, 0.08, 0.85 * a))
	draw_polyline(gate, Color(0.62, 0.62, 0.68, 0.75 * a), 2.5, true)
	for k in 8:
		var ang := TAU * float(k) / 8.0
		draw_circle(c + Vector2(cos(ang), sin(ang)) * (JOY_RADIUS - 9.0), 2.5, Color(1, 1, 1, 0.25 * a))
	# Stick shaft + knob.
	var kp := c + joy_vector * (JOY_RADIUS - KNOB_RADIUS * 0.45)
	draw_line(c, kp, Color(0.32, 0.32, 0.36, a), 20.0, true)
	draw_circle(c, 10.0, Color(0.32, 0.32, 0.36, a))
	draw_circle(kp + Vector2(0, 6), KNOB_RADIUS, Color(0, 0, 0, 0.4 * a))
	draw_circle(kp, KNOB_RADIUS, Color(0.42, 0.42, 0.46, a))
	draw_circle(kp + Vector2(0, -2), KNOB_RADIUS - 5.0, Color(0.7, 0.7, 0.74, a))
	draw_arc(kp + Vector2(0, -2), KNOB_RADIUS * 0.55, 0.0, TAU, 32, Color(0.52, 0.52, 0.56, a), 2.0, true)
	draw_arc(kp + Vector2(0, -2), KNOB_RADIUS * 0.3, 0.0, TAU, 24, Color(0.52, 0.52, 0.56, a), 2.0, true)
	draw_circle(kp + Vector2(-KNOB_RADIUS * 0.32, -KNOB_RADIUS * 0.42), KNOB_RADIUS * 0.2, Color(1, 1, 1, 0.4 * a))


func _draw_button(i: int) -> void:
	var b: Dictionary = BUTTONS[i]
	var col: Color = b["color"]
	var is_main: bool = b["main"]
	var action: String = b["action"]
	var text: String = _labels[i]
	var p: Vector2 = _btn_centers[i]
	var r: float = BTN_MAIN_R if is_main else BTN_R
	var down := Input.is_action_pressed(action)
	var idle := text == ""
	var glow := (_highlight == action or _highlight == "all") and not idle
	var pulse := 0.5 + 0.5 * sin(_clock * 9.0)
	var a := 0.45 if idle else 0.92
	var rr := r * (0.9 if down else 1.0)
	var lift := 0.0 if down else 3.0

	if glow:
		var gc := col.lightened(0.55)
		draw_circle(p, rr + 9.0 + 6.0 * pulse, Color(gc.r, gc.g, gc.b, 0.25 + 0.3 * pulse))
	# Drop shadow, dark bevel ring, face, specular highlight, rim.
	draw_circle(p + Vector2(0, 5), rr + 3.0, Color(0, 0, 0, 0.45 * a))
	var ring := col.darkened(0.6)
	draw_circle(p, rr + 3.0, Color(ring.r, ring.g, ring.b, a))
	var lower := col.darkened(0.3)
	draw_circle(p, rr - 1.0, Color(lower.r, lower.g, lower.b, a))
	var face := col
	if down or _press_flash[i] > 0.0:
		face = col.lightened(0.3 * maxf(_press_flash[i], 1.0 if down else 0.0))
	draw_circle(p + Vector2(0, -lift), rr - 6.0, Color(face.r, face.g, face.b, a))
	draw_circle(p + Vector2(-rr * 0.3, -rr * 0.38 - lift), rr * 0.26, Color(1, 1, 1, 0.38 * a))
	draw_arc(p, rr + 3.0, 0.0, TAU, 48, Color(1, 1, 1, 0.5 * a), 2.0, true)

	if idle:
		return
	# Bold caption, shrunk to fit inside the button.
	var fs := 24 if is_main else 20
	var max_w := rr * 1.7
	while fs > 12 and _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
		fs -= 1
	var box_w := rr * 2.0
	var base_y := p.y - lift + (_font.get_ascent(fs) - _font.get_descent(fs)) * 0.5
	var pos := Vector2(p.x - rr, base_y)
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, box_w, fs, 6, Color(0, 0, 0, 0.85))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, box_w, fs, Color.WHITE)

extends Node
## STORY MODE in-match helper. main.gd creates one (only when Game.story_active) and calls
## setup(); quick brawl never instantiates it, so its behaviour is untouched.
##
##  - applies Game.story_cpu_skill to the CPU (wrestler.gd ai_skill)
##  - shows the chapter / objective / bonus card at the bell and a small objective tracker
##  - tracks the bonus objective (story_schema.md types):
##      "air_tricks"  count p1 trick signals of kind "air_trick" (clean-landing calls excluded)
##      "table_break" the CPU emits the "table_break" sfx, or p1 scores "Through The Table"
##      "style_score" p1's banked STYLE score (scripts/style.gd score) reaches count
##      "signature"   p1 signature_started, or a p1 trick of kind "super"
##      "perch_dive"  p1 dives off a perch (PERCHED -> DIVING) and the dive lands ("hit"/"feet")
##  - at the end: the win panel's REMATCH becomes CONTINUE (button, Enter / START / A / J),
##    which writes Game.story_result and returns to res://story.tscn.

const Wrestler := preload("res://scripts/wrestler.gd")
const StyleSys := preload("res://scripts/style.gd")
const STORY_SCENE := "res://story.tscn"
const GOLD := Color(1.0, 0.82, 0.12)
const INK := Color(0.02, 0.02, 0.03)

var main: Node3D
var p1: Node3D
var p2: Node3D
var game: Node
var bonus: Dictionary = {}
var bonus_type := "none"
var bonus_need := 1
var bonus_have := 0
var bonus_done := false
var ended := false
var won := false
var leaving := false
var perch_armed := false
var prev_state := -1
var style_node: Node = null
var last_sig_ms := -100000

var layer: CanvasLayer
var card: PanelContainer
var tracker: PanelContainer
var obj_label: Label
var bonus_label: Label
var font_i: FontVariation
var font_b: FontVariation


func setup(p_main: Node3D, p_p1: Node3D, p_p2: Node3D) -> void:
	main = p_main
	p1 = p_p1
	p2 = p_p2
	game = get_node_or_null("/root/Game")
	process_mode = Node.PROCESS_MODE_ALWAYS
	var skill := 0.3
	var objective := "Win the match"
	if game != null:
		skill = float(game.get("story_cpu_skill"))
		var o: String = str(game.get("story_objective"))
		if o != "":
			objective = o
		var b: Variant = game.get("story_bonus")
		if b is Dictionary:
			bonus = b
	p2.set("ai_skill", clampf(skill, 0.0, 1.0))
	bonus_type = str(bonus.get("type", "none"))
	if bonus.is_empty() or bonus_type == "":
		bonus_type = "none"
	bonus_need = maxi(1, int(bonus.get("count", 1)))
	for c in p1.get_children():
		if c.get_script() == StyleSys:
			style_node = c
	p1.connect("trick", _on_p1_trick)
	p2.connect("sfx", _on_p2_sfx)
	if p1.has_signal("signature_started"):
		p1.connect("signature_started", func(_nm): _on_signature())
	_build_ui(objective)
	# Test hook for the browser screenshot scripts: ?story_autowin in the page URL wins the
	# match (with the bonus) after a few seconds, so the CONTINUE / payout flow can be checked.
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("window.location.search", true)
		if str(q).contains("story_autowin"):
			get_tree().create_timer(9.0).timeout.connect(_test_autowin)
	# The objective call follows the "FIGHT!" call.
	get_tree().create_timer(1.7).timeout.connect(func():
		if not ended and main.has_method("_announce"):
			main.call("_announce", objective.to_upper(), 2.2))


# ---------------------------------------------------------------- bonus tracking

func _on_p1_trick(trick_name: String, _points: int, kind: String) -> void:
	if ended:
		return
	match bonus_type:
		"air_tricks":
			if kind == "air_trick" and trick_name != "" and not _is_clean_call(trick_name):
				_progress(1)
		"signature":
			# Fallback when the wrestler has no signature_started signal: count supers.
			if kind == "super" and not p1.has_signal("signature_started"):
				_on_signature()
		"table_break":
			if trick_name.to_upper().contains("TABLE"):
				_progress(bonus_need)


func _is_clean_call(nm: String) -> bool:
	for c in Wrestler.AT_CLEAN_CALLS:
		if nm.contains(str(c)):
			return true
	return false


func _on_p2_sfx(kind: String, _s: float, _where: Vector3) -> void:
	if not ended and bonus_type == "table_break" and kind == "table_break":
		_progress(bonus_need)


func _on_signature() -> void:
	# One signature = one count (debounced: a move may report itself more than once).
	var now := Time.get_ticks_msec()
	if not ended and bonus_type == "signature" and now - last_sig_ms > 2500:
		last_sig_ms = now
		_progress(1)


func _progress(n: int) -> void:
	if bonus_done:
		return
	bonus_have = mini(bonus_need, bonus_have + n)
	if bonus_have >= bonus_need:
		bonus_done = true
		if main.has_method("_announce"):
			main.call("_announce", "BONUS COMPLETE!", 2.0)
		if main.has_method("_snd"):
			main.call("_snd", "cheer_small", -2.0)
	_update_tracker(true)


func _physics_process(_delta: float) -> void:
	if p1 == null or ended:
		return
	var st: int = int(p1.get("state"))
	if bonus_type == "perch_dive":
		if st == Wrestler.S.DIVING and prev_state == Wrestler.S.PERCHED:
			perch_armed = true
		elif perch_armed and st != Wrestler.S.DIVING:
			perch_armed = false
			var res: String = str(p1.get("hf_result"))
			if res == "hit" or res == "feet":
				_progress(bonus_need)
	elif bonus_type == "style_score" and style_node != null:
		var sc: int = int(style_node.get("score"))
		if sc != bonus_have and not bonus_done:
			bonus_have = mini(sc, bonus_need)
			if sc >= bonus_need:
				_progress(bonus_need)
			else:
				_update_tracker(false)
	prev_state = st


func _test_autowin() -> void:
	if ended:
		return
	_progress(bonus_need)
	p1.call("set_state", Wrestler.S.WIN)
	p2.call("set_state", Wrestler.S.LOSE)
	main.call("_on_win", p1)


# ---------------------------------------------------------------- match end

## main.gd _on_win hook.
func on_match_end(winner: Node3D) -> void:
	if ended:
		return
	ended = true
	won = winner == p1
	var wb: Button = main.get("win_button")
	if wb != null:
		wb.text = "CONTINUE"
		for con in wb.pressed.get_connections():
			wb.pressed.disconnect(con["callable"])
		wb.pressed.connect(continue_story)
	var wh: Label = main.get("win_header")
	if wh != null:
		var tag := "  -  BONUS COMPLETE" if bonus_done and won else ""
		wh.text = ("CHAPTER CLEARED" if won else "CHAPTER FAILED") + tag
	if tracker != null:
		var tw := create_tween()
		tw.tween_property(tracker, "modulate:a", 0.0, 0.4)


## True once the win banner is up (main.gd shows it ~1.2 s after the pin).
func can_continue() -> bool:
	var wp: Control = main.get("win_panel")
	return ended and not leaving and wp != null and wp.visible


func _unhandled_input(event: InputEvent) -> void:
	if not can_continue():
		return
	var go := false
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		go = jb.pressed and (jb.button_index == JOY_BUTTON_A or jb.button_index == JOY_BUTTON_START)
	elif event is InputEventKey:
		var k := event as InputEventKey
		go = k.pressed and not k.echo and k.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J]
	if go:
		get_viewport().set_input_as_handled()
		continue_story()


func continue_story() -> void:
	if not can_continue():
		return
	leaving = true
	var style := 0
	if style_node != null:
		style = int(style_node.get("score"))
	if game != null:
		game.set("story_result", {"won": won, "style": style, "bonus_done": bonus_done and won})
		game.set("story_return", "result")
	Engine.time_scale = 1.0
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(fade)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func(): get_tree().change_scene_to_file(STORY_SCENE))


# ---------------------------------------------------------------- UI

func _bonus_text() -> String:
	if bonus_type == "none":
		return ""
	var t: String = str(bonus.get("text", "Bonus"))
	var cash := int(bonus.get("cash", 0))
	if cash > 0:
		t += "  (+$%d)" % cash
	return t


func _box(bg: Color, border: Color, left: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = left
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.skew = Vector2(0.18, 0.0)
	sb.content_margin_left = 22 + left
	sb.content_margin_right = 26
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _lbl(text: String, font: Font, size: int, col: Color, outline := 6) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	return l


func _build_ui(objective: String) -> void:
	font_b = FontVariation.new()
	font_b.base_font = ThemeDB.fallback_font
	font_b.variation_embolden = 1.1
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.2
	font_i.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.24, 1), Vector2.ZERO)
	layer = CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var chapter := ""
	if game != null:
		var ci: int = int(game.get("story_chapter"))
		chapter = "STORY MODE  -  CHAPTER %d" % (ci + 1) if ci >= 0 else "STORY MODE"

	# Big intro card (centre), shown for ~3.4 s.
	card = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.05, 0.9), GOLD, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	card.add_child(v)
	v.add_child(_lbl(chapter, font_b, 18, Color(0.8, 0.8, 0.85), 4))
	v.add_child(_lbl("OBJECTIVE:  " + objective.to_upper(), font_i, 34, Color.WHITE, 8))
	if bonus_type != "none":
		v.add_child(_lbl("BONUS:  " + _bonus_text().to_upper(), font_i, 26, GOLD, 7))
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.27
	card.anchor_bottom = 0.27
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(card)
	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(card, "modulate:a", 1.0, 0.2)
	tw.tween_interval(3.4)
	tw.tween_property(card, "modulate:a", 0.0, 0.35)
	tw.tween_callback(card.queue_free)

	# Small tracker, top centre under the name plates.
	tracker = PanelContainer.new()
	tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.05, 0.72), Color(0.86, 0.12, 0.08), 6))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tracker.add_child(tv)
	obj_label = _lbl(objective.to_upper(), font_i, 17, Color.WHITE, 4)
	tv.add_child(obj_label)
	bonus_label = _lbl("", font_i, 16, GOLD, 4)
	tv.add_child(bonus_label)
	bonus_label.visible = bonus_type != "none"
	tracker.anchor_left = 0.5
	tracker.anchor_right = 0.5
	tracker.anchor_top = 0.0
	tracker.anchor_bottom = 0.0
	tracker.offset_top = 96
	tracker.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(tracker)
	tracker.modulate.a = 0.0
	var tt := create_tween()
	tt.tween_interval(3.9)
	tt.tween_property(tracker, "modulate:a", 1.0, 0.3)
	_update_tracker(false)


func _update_tracker(pop: bool) -> void:
	if bonus_label == null or bonus_type == "none":
		return
	var t: String = "BONUS: " + str(bonus.get("text", "")).to_upper()
	if bonus_done:
		t = "[DONE]  " + t
		bonus_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.45))
	elif bonus_type in ["air_tricks", "style_score", "signature"] and bonus_need > 1:
		t += "  %d / %d" % [bonus_have, bonus_need]
	bonus_label.text = t
	if pop and tracker != null:
		tracker.pivot_offset = tracker.size * 0.5
		tracker.scale = Vector2(1.15, 1.15)
		var tw := create_tween()
		tw.tween_property(tracker, "scale", Vector2.ONE, 0.18)

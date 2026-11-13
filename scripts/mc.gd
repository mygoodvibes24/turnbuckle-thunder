extends CanvasLayer
## MC LAWN DART: the backyard's hype MC. Short punchy one-line callouts on big moments
## (big air, shed-roof dives, tables, 5x+ combos, BRAWL MODE, near falls, signature moves),
## shown top-left under the player's name plate / style column, clear of the announcer
## (top center), the trick popups (they stay below y+212) and the touch controls (bottom).
## Rate-limited: one line at a time, a global gap between lines, a per-category cooldown, and
## low-priority calls are dropped while anything else was said recently.
## Created by main.gd (_setup_presentation): setup(main); main calls say(category, wrestler).

const StoryText := preload("res://scripts/story_text.gd")
const MC_NAME := "MC LAWN DART"
const TOP_Y := 142.0          # under main.gd's name plate (~60) and style_hud's letters / HYPE bar (~124)
const EDGE := 16.0
const MAX_W := 430.0
const LINE_FONT := 24
const TAG_FONT := 13
const SHOW_SECS := 2.1        # real seconds a line stays up
const MIN_GAP := 2.6          # real seconds before another line of the same or lower priority
const LOW_PRIO_GAP := 4.5     # priority <= 2 lines also wait this long after any line
const CAT_COOLDOWN := 8.0     # the same category is not repeated within this many seconds
const GOLD := Color(1.0, 0.84, 0.2)
const INK := Color(0.04, 0.03, 0.06, 0.95)

## category -> [priority, lines...]; {N} = the wrestler's short name, {S} = the move name,
## {HIS} = HIS / HER / THEIR (a created wrestler's pronouns, else the model's body).
const LINES := {
	"signature": [5, "{N}'S SIGNATURE! HERE IT COMES!", "OH IT'S THE {S}!", "{N} SAVED THAT ONE FOR TV!"],
	"brawl": [5, "BRAWL MODE! LOCK THE GATE!", "{N} IS FULLY CHARGED!", "SOMEBODY CALL {HIS} MAMA!"],
	"roof": [4, "{N}'S OFF THE ROOF!", "FROM UP THERE?! NO FEAR!", "THAT'S A TWO-STORY DECISION!"],
	"table": [4, "TABLE'S IN PIECES!", "THAT TABLE HAD A FAMILY!", "SPLINTER CITY, BABY!"],
	"near_fall": [4, "NOOO! STILL ALIVE!", "SO CLOSE! SO CLOSE!", "HOW IS {N} UP?!"],
	"combo_max": [3, "x8! I CAN'T EVEN!", "MAXED OUT! MAXED OUT!", "{N} BROKE THE METER!"],
	"combo": [2, "{N} IS ON FIRE!", "KEEP IT ROLLING!", "THE CHAIN WON'T QUIT!", "TOO SMOOTH!"],
	"super": [2, "SUPERSIZED!", "THAT'S ILLEGAL IN THREE STATES!", "EXTRA LARGE!"],
	"big_air": [2, "{N} GOT WINGS!", "LOOK AT THAT HANG TIME!", "AIR MAIL!", "SKY'S THE LIMIT!"],
	"stomp": [1, "STUCK IT!", "BUTTER! PURE BUTTER!", "CLEAN AS A WHISTLE!"],
	"botch": [1, "YARD SALE!", "FACE FULL OF LAWN!", "OOF. THAT'S GONNA BRUISE."],
}

var main: Node
var root: Control
var box: PanelContainer
var tag: Label
var line: Label
var font_i: FontVariation
var _show_left := 0.0
var _cur_prio := 0
var _last_ms := -100000
var _cat_ms := {}
var _last_pick := {}
var _tween: Tween


func setup(p_main: Node) -> void:
	main = p_main
	layer = 2
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.0
	font_i.variation_transform = Transform2D(Vector2(1, 0.22), Vector2(0, 1), Vector2.ZERO)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	box = PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.06, 0.62)
	sb.border_color = GOLD
	sb.border_width_left = 4
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	sb.skew = Vector2(0.18, 0.0)
	box.add_theme_stylebox_override("panel", sb)
	box.visible = false
	root.add_child(box)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", -4)
	box.add_child(vb)
	tag = _label(TAG_FONT, GOLD, 3)
	tag.text = MC_NAME + " :"
	vb.add_child(tag)
	line = _label(LINE_FONT, Color.WHITE, 6)
	vb.add_child(line)


func _label(size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font_i)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func short_name(w: Node) -> String:
	if w == null:
		return "THIS GUY"
	var nm: String = str(w.get("display_name")).to_upper()
	if _is_caw(w):
		return StoryText.hero_short_name()
	var parts := nm.split(" ", false)
	if parts.is_empty():
		return "THIS GUY"
	if parts.size() > 1 and parts[0] in ["LIL", "BIG", "EL", "THE", "DJ", "MC", "KID"]:
		return parts[parts.size() - 1]
	return parts[0]


## The player's created wrestler (its HUD name is the CAW ring name)?
static func _is_caw(w: Node) -> bool:
	return w != null and StoryText.caw_active() and str(w.get("display_name")).to_upper() == StoryText.hero_full_name()


static func his(w: Node) -> String:
	if w == null:
		return "HIS"
	if _is_caw(w):
		return StoryText.resolve("{HIS}")
	var lk: Variant = w.get("look")
	if lk is Dictionary and str((lk as Dictionary).get("body", "male")) == "female":
		return "HER"
	return "HIS"


## Ask the MC to call something. Returns true if the line was shown.
func say(cat: String, who: Node = null, move_name := "") -> bool:
	if line == null or not LINES.has(cat):
		return false
	if main != null and bool(main.get("match_over")):
		return false
	var entry: Array = LINES[cat]
	var prio: int = entry[0]
	var now := Time.get_ticks_msec()
	var since := float(now - _last_ms) / 1000.0
	var cat_last: int = _cat_ms.get(cat, -100000)
	if float(now - cat_last) / 1000.0 < CAT_COOLDOWN and prio < 5:
		return false
	if _show_left > 0.0 and prio <= _cur_prio and since < MIN_GAP:
		return false
	if prio <= 2 and since < LOW_PRIO_GAP:
		return false
	# Pick a line (never the same one twice in a row for a category).
	var n := entry.size() - 1
	var pick := 1 + randi() % n
	if n > 1 and _last_pick.get(cat, -1) == pick:
		pick = 1 + (pick % n)
	_last_pick[cat] = pick
	var txt: String = entry[pick]
	if txt.contains("{S}") and move_name == "":
		txt = entry[1] if entry[1] != txt else "{N}! {N}! {N}!"
	txt = txt.replace("{N}", short_name(who)).replace("{S}", move_name.to_upper()).replace("{HIS}", his(who))
	_last_ms = now
	_cat_ms[cat] = now
	_cur_prio = prio
	_show(txt, prio)
	return true


func _show(txt: String, prio: int) -> void:
	line.text = txt
	var size := LINE_FONT + (4 if prio >= 4 else 0)
	while size > 14 and font_i.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > MAX_W:
		size -= 1
	line.add_theme_font_size_override("font_size", size)
	line.add_theme_color_override("font_color", GOLD if prio >= 5 else Color.WHITE)
	box.reset_size()
	box.visible = true
	_show_left = SHOW_SECS + (0.4 if prio >= 4 else 0.0)
	_place()
	# Slam in from the left with a little overshoot.
	var rest := box.position
	box.position = rest - Vector2(60.0, 0.0)
	box.modulate = Color(1, 1, 1, 0)
	box.pivot_offset = Vector2(0, box.size.y * 0.5)
	box.scale = Vector2(1.25, 1.25)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_ignore_time_scale(true)
	_tween.tween_property(box, "position", rest, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(box, "modulate:a", 1.0, 0.08)
	_tween.tween_property(box, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _safe_rect() -> Rect2:
	if main != null and main.has_method("_hud_safe_rect"):
		return main.call("_hud_safe_rect")
	return Rect2(Vector2.ZERO, root.get_viewport_rect().size)


func _place() -> void:
	var sr := _safe_rect()
	box.position = Vector2(sr.position.x + EDGE, sr.position.y + TOP_Y)


func _process(delta: float) -> void:
	if box == null:
		return
	var help = main.get("help_panel") if main != null else null
	visible = not (help is Control and (help as Control).visible)
	if _show_left <= 0.0:
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	_show_left -= real_dt
	if _show_left <= 0.0:
		_show_left = 0.0
		_cur_prio = 0
		box.visible = false
		return
	if _show_left < 0.3:
		box.modulate.a = _show_left / 0.3
	# A tiny "on air" jitter while the line is fresh.
	if _show_left > SHOW_SECS - 0.35 and (_tween == null or not _tween.is_valid()):
		var sr := _safe_rect()
		box.position = Vector2(sr.position.x + EDGE, sr.position.y + TOP_Y) + Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))
	elif _tween == null or not _tween.is_valid():
		_place()

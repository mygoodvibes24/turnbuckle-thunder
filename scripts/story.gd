extends Node3D
## City 2 City Wrestling - STORY MODE hub (story.tscn).
##
## title.tscn -> STORY MODE -> here. A PS2-era menu over a painted night backyard:
##   - chapter list (locked / unlocked / cleared with a check / cleared + bonus with a medal)
##   - "BACKYARD BANK: $N" money counter
##   - the current chapter card (title, name, teaser, opponent, purse, bonus, best style)
##   - CONTINUE / CHAPTER SELECT / BACK
## Chapter flow: title card -> intro cutscene (res://cutscene.tscn when it exists, else the
## built-in placeholder dialogue player below) -> Game story fields -> main.tscn -> main.gd's
## story hook (scripts/story_match.gd) writes Game.story_result and comes back here ->
## win / lose scene -> payout + save -> next chapter / retry.
##
## Data: scripts/story_data.gd (story_schema.md: CAST + CHAPTERS consts).
## Save: ConfigFile at user://story.cfg, section "progress": unlocked (index), completed (ids),
## bonus (ids whose bonus cash was paid), cash, best_style {id: score}.
## Keyboard (arrows/WASD, Enter/Space/J, Esc/K), gamepad (d-pad/stick, A/B/START) and touch.

const Wrestler := preload("res://scripts/wrestler.gd")
const Audio := preload("res://scripts/audio.gd")
const Music := preload("res://scripts/music.gd")
const DATA_PATH := "res://scripts/story_data.gd"
const CUTSCENE_SCENE := "res://cutscene.tscn"
const MATCH_SCENE := "res://main.tscn"
const TITLE_SCENE := "res://title.tscn"
const SAVE_PATH := "user://story.cfg"

const GOLD := Color(1.0, 0.82, 0.12)
const RED := Color(0.86, 0.12, 0.08)
const INK := Color(0.02, 0.02, 0.025)
const CREAM := Color(0.95, 0.93, 0.88)
const GREEN := Color(0.4, 0.95, 0.4)

const SET_NAMES := {
	"kitchen": "MOM'S KITCHEN", "bedroom": "TANK'S ROOM", "backyard": "THE BACKYARD",
	"street": "THE BLOCK", "store_lot": "CORNER STORE LOT", "porch": "FRONT PORCH",
	"car": "MOM'S CAR", "rooftop": "THE ROOFTOP",
}

enum Phase { HUB, CHAPTERS, CARD, CUTSCENE, RESULT, LEAVING }

var phase: int = Phase.HUB
var headless := false
var frames := 0
var t := 0.0
var input_lock := 0.0
var stick_armed := true

# data + save
var chapters: Array = []
var cast: Dictionary = {}
var unlocked := 0
var completed: Array = []
var bonus_got: Array = []
var cash := 0
var best_style: Dictionary = {}
var cash_shown := 0.0

var cur := 0                      # chapter shown on the card / being played
var after_scenes := Callable()    # what runs when the cutscene / placeholder finishes

# generic button navigation
var btns: Array[Button] = []
var btn_actions: Array[Callable] = []
var btn_sel := 0
var list_first := 0

# audio
var audio: Node = null
var music: Node = null
var load_step := 0

# 3D: Tank + the card chapter's opponent
var view: SubViewport
var view_rect: TextureRect
var world: Node3D
var camera: Camera3D
var fighters: Array[Node3D] = []
var fighter_ids: Array[String] = ["", ""]
var pose_left := [1.0, 2.0]
var pose_i := [0, 0]
var want_opp := ""
var opp_timer := 0.0

# UI
var bg: Control
var bg_time := "night"
var stars: Array[Vector3] = []
var ui_layer: CanvasLayer
var ui: Control
var font_i: FontVariation
var font_b: FontVariation
var header: Control
var bank_panel: PanelContainer
var bank_label: Label
var menu_box: VBoxContainer
var list_box: VBoxContainer
var list_title: Label
var card: PanelContainer
var card_kicker: Label
var card_name: Label
var card_teaser: Label
var card_info: Label
var card_status: Label
var name_l: Label
var name_r: Label
var hint: Label
var over_layer: CanvasLayer
var over: Control
var fade_rect: ColorRect
var loading_label: Label

# title card
var tc: Control

# placeholder dialogue player
var dlg: Control
var dlg_scenes: Array = []
var dlg_scene_i := 0
var dlg_line_i := 0
var dlg_t := 0.0
var dlg_full := 0
var dlg_place: Label
var dlg_cast: Label
var dlg_box: PanelContainer
var dlg_name: Label
var dlg_text: Label
var dlg_emote: Label
var dlg_caption: PanelContainer
var dlg_caption_text: Label
var dlg_phone: PanelContainer
var dlg_phone_text: Label
var dlg_more: Label

# result
var res_panel: PanelContainer
var res_cash_label: Label


func _ready() -> void:
	Engine.time_scale = 1.0
	headless = DisplayServer.get_name() == "headless"
	_load_data()
	_load_save()
	cash_shown = float(cash)
	font_b = FontVariation.new()
	font_b.base_font = ThemeDB.fallback_font
	font_b.variation_embolden = 1.1
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.2
	font_i.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.24, 1), Vector2.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	for i in 90:
		stars.append(Vector3(rng.randf(), rng.randf() * 0.5, rng.randf() * TAU))
	_build_bg()
	_build_view()
	_build_ui()
	_build_overlay()
	get_viewport().size_changed.connect(_relayout)
	_relayout()

	var game := _game()
	if game != null and str(game.get("story_return")) == "result" and chapters.size() > 0:
		game.set("story_return", "")
		_begin_result()
	else:
		cur = _continue_index()
		_show_hub()


func _game() -> Node:
	return get_node_or_null("/root/Game")


# ---------------------------------------------------------------- data + save

func _load_data() -> void:
	if not ResourceLoader.exists(DATA_PATH):
		return
	var scr: Script = load(DATA_PATH) as Script
	if scr == null:
		return
	var consts: Dictionary = scr.get_script_constant_map()
	var ch: Variant = consts.get("CHAPTERS", [])
	if ch is Array:
		chapters = ch
	var ca: Variant = consts.get("CAST", {})
	if ca is Dictionary:
		cast = ca


func _load_save() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		unlocked = int(cf.get_value("progress", "unlocked", 0))
		cash = int(cf.get_value("progress", "cash", 0))
		var c: Variant = cf.get_value("progress", "completed", [])
		if c is Array:
			completed = (c as Array).duplicate()
		var b: Variant = cf.get_value("progress", "bonus", [])
		if b is Array:
			bonus_got = (b as Array).duplicate()
		var s: Variant = cf.get_value("progress", "best_style", {})
		if s is Dictionary:
			best_style = (s as Dictionary).duplicate()
	unlocked = clampi(unlocked, 0, maxi(chapters.size() - 1, 0))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("progress", "unlocked", unlocked)
	cf.set_value("progress", "completed", completed)
	cf.set_value("progress", "bonus", bonus_got)
	cf.set_value("progress", "cash", cash)
	cf.set_value("progress", "best_style", best_style)
	cf.save(SAVE_PATH)


func _ch(i: int) -> Dictionary:
	if i < 0 or i >= chapters.size():
		return {}
	var d: Dictionary = chapters[i]
	return d


func _ch_id(i: int) -> String:
	return str(_ch(i).get("id", "ch%d" % (i + 1)))


func _match_of(i: int) -> Dictionary:
	var m: Variant = _ch(i).get("match", {})
	if m is Dictionary:
		return m
	return {}


func _bonus_of(i: int) -> Dictionary:
	var b: Variant = _match_of(i).get("bonus", {})
	if b is Dictionary:
		return b
	return {}


func _scenes_of(i: int, key: String) -> Array:
	var s: Variant = _ch(i).get(key, [])
	if s is Array:
		return s
	return []


func _is_done(i: int) -> bool:
	return completed.has(_ch_id(i))


func _has_medal(i: int) -> bool:
	return bonus_got.has(_ch_id(i))


func _is_locked(i: int) -> bool:
	return i > unlocked


## First unlocked chapter not cleared yet; the last unlocked one when all are cleared.
func _continue_index() -> int:
	for i in mini(unlocked + 1, chapters.size()):
		if not _is_done(i):
			return i
	return clampi(unlocked, 0, maxi(chapters.size() - 1, 0))


func _opp_id(i: int) -> String:
	return str(_match_of(i).get("opponent", "peligro"))


func _opp_name(i: int) -> String:
	var game := _game()
	if game != null:
		var e: Dictionary = game.call("entry", _opp_id(i))
		return str(e.get("display_name", _opp_id(i).to_upper()))
	return _opp_id(i).to_upper()


func _cast_name(who: String) -> String:
	match who:
		"narrator":
			return ""
		"phone":
			return "TEXT MESSAGE"
		"tv":
			return "TV"
	var c: Variant = cast.get(who, {})
	if c is Dictionary:
		var cd: Dictionary = c
		if cd.has("name"):
			return str(cd["name"])
	return who.to_upper()


func _cast_color(who: String) -> Color:
	var c: Variant = cast.get(who, {})
	if c is Dictionary:
		var cd: Dictionary = c
		var look: Variant = cd.get("look", null)
		if look is Dictionary and (look as Dictionary).has("gear"):
			return (look as Dictionary)["gear"]
		var game := _game()
		if cd.has("roster_id") and game != null:
			var e: Dictionary = game.call("entry", str(cd["roster_id"]))
			var lk: Dictionary = e.get("look", {})
			if lk.has("gear"):
				return lk["gear"]
	return Color(0.45, 0.45, 0.5)


static func _fmt(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	frames += 1
	t += delta
	input_lock = maxf(0.0, input_lock - delta)
	_staged_audio()
	if bg != null:
		bg.queue_redraw()
	# bank counter rolls up
	if absf(cash_shown - float(cash)) > 0.5:
		cash_shown = move_toward(cash_shown, float(cash), maxf(60.0, absf(float(cash) - cash_shown) * 3.0) * delta)
	else:
		cash_shown = float(cash)
	var txt := "$" + _fmt(int(round(cash_shown)))
	if bank_label.text != txt:
		bank_label.text = txt
	if res_cash_label != null and is_instance_valid(res_cash_label):
		res_cash_label.text = txt
	_animate_fighters(minf(delta, 0.1))
	if want_opp != "" and want_opp != fighter_ids[1]:
		opp_timer -= delta
		if opp_timer <= 0.0:
			_spawn_fighter(1, want_opp)
	if dlg != null and dlg.visible:
		_dlg_tick(delta)
	# Headless (launched directly): run the flow through to the match by itself.
	if headless:
		if frames == 20 and phase == Phase.HUB:
			print("story (headless): %d chapters, starting chapter %d" % [chapters.size(), cur + 1])
			_start_chapter(cur)
		elif dlg != null and dlg.visible and frames % 2 == 0:
			_dlg_advance(true)


func _staged_audio() -> void:
	# One heavy synthesis step per frame, after the picture is up.
	if load_step > 3 or frames < 3:
		return
	match load_step:
		0:
			_spawn_fighter(0, "tank")
		1:
			if want_opp != "" and want_opp != fighter_ids[1]:
				_spawn_fighter(1, want_opp)
		2:
			if not headless:
				audio = Audio.new()
				add_child(audio)
		3:
			if not headless:
				music = Music.new()
				add_child(music)
				music.call("start")
	load_step += 1


func _snd(n: String, db := 0.0, var_amt := 0.05) -> void:
	if audio != null:
		var clips: Dictionary = audio.get("clips")
		if clips.has(n):
			audio.call("play", n, db, var_amt)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if headless or phase == Phase.LEAVING or phase == Phase.CUTSCENE and dlg != null and not dlg.visible:
		return
	var confirm := false
	var back := false
	var dir := Vector2i.ZERO
	var tap := false
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed:
			return
		var code := k.physical_keycode
		if k.echo:
			if code in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
				dir.y = -1 if code in [KEY_UP, KEY_W] else 1
			else:
				return
		elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_J, KEY_Z]:
			confirm = true
		elif code in [KEY_ESCAPE, KEY_BACKSPACE, KEY_K, KEY_X]:
			back = true
		elif code in [KEY_UP, KEY_W]:
			dir.y = -1
		elif code in [KEY_DOWN, KEY_S]:
			dir.y = 1
		elif code in [KEY_LEFT, KEY_A]:
			dir.x = -1
		elif code in [KEY_RIGHT, KEY_D]:
			dir.x = 1
		else:
			return
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if not jb.pressed:
			return
		match jb.button_index:
			JOY_BUTTON_A, JOY_BUTTON_START:
				confirm = true
			JOY_BUTTON_B, JOY_BUTTON_BACK:
				back = true
			JOY_BUTTON_DPAD_UP:
				dir.y = -1
			JOY_BUTTON_DPAD_DOWN:
				dir.y = 1
			JOY_BUTTON_DPAD_LEFT:
				dir.x = -1
			JOY_BUTTON_DPAD_RIGHT:
				dir.x = 1
			_:
				return
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis != JOY_AXIS_LEFT_Y:
			return
		if absf(jm.axis_value) < 0.3:
			stick_armed = true
			return
		if absf(jm.axis_value) > 0.6 and stick_armed:
			stick_armed = false
			dir.y = 1 if jm.axis_value > 0.0 else -1
		else:
			return
	elif event is InputEventScreenTouch:
		tap = (event as InputEventScreenTouch).pressed
		if not tap:
			return
	else:
		return

	match phase:
		Phase.HUB, Phase.CHAPTERS, Phase.RESULT:
			if dlg != null and dlg.visible:
				_dlg_input(confirm, back, tap)
				return
			if tap or input_lock > 0.0:
				return   # buttons handle taps themselves
			var mv: int = dir.y if dir.y != 0 else dir.x
			if mv != 0:
				_move_sel(mv)
				get_viewport().set_input_as_handled()
			elif confirm:
				get_viewport().set_input_as_handled()
				_activate(btn_sel)
			elif back:
				get_viewport().set_input_as_handled()
				_on_back()
		Phase.CARD:
			if confirm or back or tap:
				get_viewport().set_input_as_handled()
				_card_done()
		Phase.CUTSCENE:
			_dlg_input(confirm, back, tap)


func _on_back() -> void:
	match phase:
		Phase.HUB:
			_go(TITLE_SCENE)
		Phase.CHAPTERS:
			_show_hub()
		Phase.RESULT:
			if res_panel != null and res_panel.visible:
				_show_hub()


func _move_sel(dir: int) -> void:
	if btns.is_empty():
		return
	btn_sel = posmod(btn_sel + dir, btns.size())
	_update_btns()
	_snd("trick", -12.0, 0.0)
	if phase == Phase.CHAPTERS:
		_set_card(btn_sel)


func _activate(i: int) -> void:
	if i < 0 or i >= btn_actions.size() or input_lock > 0.0:
		return
	btn_sel = i
	_update_btns()
	var a: Callable = btn_actions[i]
	a.call()


func _set_buttons(list: Array[Button], actions: Array[Callable], sel: int) -> void:
	btns = list
	btn_actions = actions
	btn_sel = clampi(sel, 0, maxi(list.size() - 1, 0))
	for i in btns.size():
		var b := btns[i]
		var idx := i
		if not b.has_meta("wired"):
			b.set_meta("wired", true)
			b.pressed.connect(func(): _activate(idx))
			b.mouse_entered.connect(func():
				if btns.has(b) and btn_sel != btns.find(b):
					btn_sel = btns.find(b)
					_update_btns()
					if phase == Phase.CHAPTERS:
						_set_card(btn_sel))
	_update_btns()
	input_lock = 0.15


func _update_btns() -> void:
	for i in btns.size():
		var b := btns[i]
		var on := i == btn_sel
		var big: bool = b.get_meta("big", true)
		b.add_theme_stylebox_override("normal", _btn_box(on, big))
		b.add_theme_stylebox_override("hover", _btn_box(on, big))
		b.add_theme_stylebox_override("pressed", _btn_box(true, big))
		var dim: bool = b.get_meta("dim", false)
		var fc := INK if on else (Color(0.55, 0.55, 0.58) if dim else CREAM)
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", fc)
		b.add_theme_color_override("font_pressed_color", INK)
		b.add_theme_constant_override("outline_size", 0 if on else 6)
		var base: String = b.get_meta("label", b.text)
		b.text = ("> " + base) if on and big else base
	if phase == Phase.CHAPTERS:
		_scroll_list()


# ---------------------------------------------------------------- hub / chapter select

func _show_hub() -> void:
	phase = Phase.HUB
	ui.visible = true
	view_rect.visible = true
	bg_time = "night"
	if res_panel != null:
		res_panel.visible = false
	_fade_in()
	name_l.visible = true
	if music != null and load_step > 3:
		music.call("start")
	list_box.visible = false
	list_title.visible = false
	menu_box.visible = true
	card.visible = true
	cur = _continue_index()
	_set_card(cur)
	var items: Array[Button] = []
	for c in menu_box.get_children():
		items.append(c as Button)
	var first: String = "START STORY" if completed.is_empty() and cash == 0 else "CONTINUE"
	items[0].set_meta("label", "%s  -  CH %d" % [first, cur + 1])
	var acts: Array[Callable] = [func(): _start_chapter(_continue_index()), _show_chapters, func(): _go(TITLE_SCENE)]
	_set_buttons(items, acts, 0)
	hint.text = "UP / DOWN  select     ENTER / J  confirm     ESC  back to title"
	_relayout()


func _show_chapters() -> void:
	phase = Phase.CHAPTERS
	menu_box.visible = false
	list_box.visible = true
	list_title.visible = true
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	var rows: Array[Button] = []
	var acts: Array[Callable] = []
	for i in chapters.size():
		var ch := _ch(i)
		var locked := _is_locked(i)
		var b := _make_button("", false)
		var label := "CH %d   %s" % [i + 1, "? ? ?" if locked else str(ch.get("name", "")).to_upper()]
		b.set_meta("label", label)
		b.set_meta("dim", locked)
		b.text = label
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(40, 40)
		icon.anchor_left = 1.0
		icon.anchor_right = 1.0
		icon.anchor_top = 0.5
		icon.anchor_bottom = 0.5
		icon.offset_left = -56
		icon.offset_right = -16
		icon.offset_top = -20
		icon.offset_bottom = 20
		var kind: String = "lock" if locked else ("medal" if _has_medal(i) else ("check" if _is_done(i) else "new"))
		icon.draw.connect(func(): _draw_icon(icon, kind))
		b.add_child(icon)
		list_box.add_child(b)
		rows.append(b)
		var idx := i
		acts.append(func(): _pick_chapter(idx))
	list_first = 0
	_set_buttons(rows, acts, cur)
	_set_card(btn_sel)
	hint.text = "UP / DOWN  chapter     ENTER / J  play     ESC  back"
	_relayout()


func _pick_chapter(i: int) -> void:
	if _is_locked(i):
		_snd("boo", -10.0)
		card.pivot_offset = card.size * 0.5
		var tw := create_tween()
		tw.tween_property(card, "position:x", card.position.x + 10.0, 0.05)
		tw.tween_property(card, "position:x", card.position.x - 10.0, 0.08)
		tw.tween_property(card, "position:x", card.position.x, 0.05)
		return
	_start_chapter(i)


func _scroll_list() -> void:
	# Show a window of rows that fits the column; keep the selection inside it.
	var rows := list_box.get_child_count()
	if rows == 0:
		return
	var vp := get_viewport().get_visible_rect().size
	var room := vp.y - 200.0 - 70.0
	var fit := maxi(3, int(room / 58.0))
	if btn_sel < list_first:
		list_first = btn_sel
	elif btn_sel >= list_first + fit:
		list_first = btn_sel - fit + 1
	list_first = clampi(list_first, 0, maxi(0, rows - fit))
	for i in rows:
		var c := list_box.get_child(i) as Control
		c.visible = i >= list_first and i < list_first + fit


func _set_card(i: int) -> void:
	cur = clampi(i, 0, maxi(chapters.size() - 1, 0))
	var ch := _ch(cur)
	if ch.is_empty():
		card_kicker.text = "NO CHAPTERS"
		card_name.text = ""
		card_teaser.text = ""
		card_info.text = ""
		card_status.text = ""
		return
	var locked := _is_locked(cur)
	card_kicker.text = str(ch.get("title", "CHAPTER %d" % (cur + 1))).to_upper()
	if locked:
		card_name.text = "LOCKED"
		card_teaser.text = "Win the previous chapter to unlock this one."
		card_info.text = ""
		card_status.text = ""
		_want_opponent("")
		name_r.text = "???"
		name_r.visible = false
		return
	card_name.text = str(ch.get("name", "")).to_upper()
	card_teaser.text = str(ch.get("teaser", ""))
	var b := _bonus_of(cur)
	var info := "VS  %s     PURSE  $%d" % [_opp_name(cur), int(ch.get("payout", 0))]
	var btype := str(b.get("type", "none"))
	if not b.is_empty() and btype != "none":
		info += "\nBONUS  %s  (+$%d)" % [str(b.get("text", "")), int(b.get("cash", 0))]
	card_info.text = info
	var id := _ch_id(cur)
	var st := ""
	if _has_medal(cur):
		st = "CLEARED  +  BONUS MEDAL"
	elif _is_done(cur):
		st = "CLEARED"
	else:
		st = "NEW"
	if best_style.has(id):
		st += "     BEST STYLE  " + _fmt(int(best_style[id]))
	card_status.text = st
	card_status.add_theme_color_override("font_color", GREEN if _is_done(cur) else GOLD)
	_want_opponent(_opp_id(cur))
	name_r.text = _opp_name(cur)
	name_r.visible = true
	name_r.reset_size()
	if view_rect != null:
		name_r.position.x = view_rect.position.x + view_rect.size.x * 0.78 - name_r.size.x * 0.5


# ---------------------------------------------------------------- chapter flow

func _start_chapter(i: int) -> void:
	if chapters.is_empty():
		return
	cur = clampi(i, 0, chapters.size() - 1)
	_snd("punch", -2.0)
	if not headless and ResourceLoader.exists(CUTSCENE_SCENE):
		# The cutscene engine shows the chapter card itself, then plays the intro.
		_play_scenes(_scenes_of(cur, "intro"), func(): _launch_match(cur), true)
		return
	phase = Phase.CARD
	_snd("big_thud", -6.0)
	_show_title_card()


func _show_title_card() -> void:
	ui.visible = false
	view_rect.visible = false
	for c in tc.get_children():
		c.queue_free()
	tc.visible = true
	tc.modulate.a = 1.0
	var ch := _ch(cur)
	var vp := get_viewport().get_visible_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(dim)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 1)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.size = Vector2(vp.x, vp.y * 0.13)
		bar.position = Vector2(0, -bar.size.y if top else vp.y)
		tc.add_child(bar)
		var tw := create_tween()
		tw.tween_property(bar, "position:y", 0.0 if top else vp.y - bar.size.y, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var stripe := ColorRect.new()
	stripe.color = RED
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.size = Vector2(vp.x * 1.2, 120)
	stripe.position = Vector2(-vp.x * 0.1, vp.y * 0.5 - 70)
	stripe.rotation = deg_to_rad(-3.0)
	stripe.pivot_offset = stripe.size * 0.5
	stripe.scale = Vector2(0.0, 1.0)
	tc.add_child(stripe)
	var tw2 := create_tween()
	tw2.tween_property(stripe, "scale:x", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var kicker := _label(str(ch.get("title", "CHAPTER %d" % (cur + 1))).to_upper(), font_b, 30, CREAM, 6)
	tc.add_child(kicker)
	kicker.reset_size()
	kicker.position = Vector2(vp.x * 0.5 - kicker.size.x * 0.5, vp.y * 0.5 - 118)
	var nm := _label(str(ch.get("name", "")).to_upper(), font_i, 72, GOLD, 14)
	_shadow(nm, 6.0)
	tc.add_child(nm)
	nm.reset_size()
	nm.position = Vector2(vp.x * 0.5 - nm.size.x * 0.5, vp.y * 0.5 - 62)
	nm.pivot_offset = nm.size * 0.5
	nm.rotation = deg_to_rad(-3.0)
	nm.scale = Vector2(2.2, 2.2)
	nm.modulate.a = 0.0
	var tw3 := create_tween()
	tw3.tween_interval(0.18)
	tw3.tween_property(nm, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw3.parallel().tween_property(nm, "modulate:a", 1.0, 0.1)
	tw3.tween_callback(func(): _snd("big_thud", -4.0))
	var vs := _label("TANK MAGRUDER  vs  " + _opp_name(cur), font_i, 28, CREAM, 8)
	tc.add_child(vs)
	vs.reset_size()
	vs.position = Vector2(vp.x * 0.5 - vs.size.x * 0.5, vp.y * 0.5 + 66)
	var skip := _label("ENTER  skip", font_b, 18, Color(0.8, 0.8, 0.8), 4)
	tc.add_child(skip)
	skip.reset_size()
	skip.position = Vector2(vp.x - skip.size.x - 40, vp.y - 54)
	var tw4 := create_tween()
	tw4.tween_interval(0.05 if headless else 2.4)
	tw4.tween_callback(func():
		if phase == Phase.CARD:
			_card_done())


func _card_done() -> void:
	if phase != Phase.CARD:
		return
	tc.visible = false
	_play_scenes(_scenes_of(cur, "intro"), func(): _launch_match(cur))


func _launch_match(i: int) -> void:
	var m := _match_of(i)
	var game := _game()
	if game != null:
		game.set("story_active", true)
		game.set("story_chapter", i)
		game.set("p1_id", "tank")
		game.set("p2_id", _opp_id(i))
		game.set("story_cpu_skill", float(m.get("cpu_skill", 0.3)))
		game.set("story_objective", str(m.get("objective", "Win the match")))
		game.set("story_bonus", _bonus_of(i).duplicate())
		game.set("story_result", {})
	_go(MATCH_SCENE)


func _go(scene: String) -> void:
	if phase == Phase.LEAVING:
		return
	phase = Phase.LEAVING
	if music != null:
		music.call("fade_out", 0.4)
	_snd("whoosh", -6.0)
	fade_rect.visible = true
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 0.4)
	if scene == MATCH_SCENE:
		tw.tween_callback(func():
			loading_label.visible = true)
		tw.tween_interval(0.12)   # let "LOADING..." reach the screen before the blocking build
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene))


# ---------------------------------------------------------------- result

func _begin_result() -> void:
	var game := _game()
	var res: Dictionary = {}
	if game != null:
		var r: Variant = game.get("story_result")
		if r is Dictionary:
			res = r
		cur = clampi(int(game.get("story_chapter")), 0, chapters.size() - 1)
		game.set("story_active", false)
	var won: bool = bool(res.get("won", false))
	var lines := _apply_result(cur, res)
	phase = Phase.RESULT
	ui.visible = false
	view_rect.visible = false
	_set_card(cur)
	_play_scenes(_scenes_of(cur, "win" if won else "lose"), func(): _show_result(won, lines, res))


## Pays out, unlocks and saves right away. Returns the payout lines [[text, amount, color], ...].
func _apply_result(i: int, res: Dictionary) -> Array:
	var lines: Array = []
	var won: bool = bool(res.get("won", false))
	var style: int = int(res.get("style", 0))
	var id := _ch_id(i)
	var ch := _ch(i)
	if won:
		var purse := int(ch.get("payout", 100))
		if not completed.has(id):
			lines.append(["PURSE", purse, GOLD])
			completed.append(id)
		else:
			lines.append(["ENCORE TIPS", maxi(10, purse / 4), GOLD])
		var b := _bonus_of(i)
		if bool(res.get("bonus_done", false)) and not b.is_empty():
			if not bonus_got.has(id):
				lines.append(["BONUS: " + str(b.get("text", "")).to_upper(), int(b.get("cash", 0)), GREEN])
				bonus_got.append(id)
			else:
				lines.append(["BONUS (ALREADY PAID)", 0, Color(0.6, 0.6, 0.6)])
		if i + 1 < chapters.size():
			unlocked = maxi(unlocked, i + 1)
	var best := int(best_style.get(id, 0))
	if style > best:
		best_style[id] = style
		lines.append(["STYLE  %s   NEW BEST!" % _fmt(style), 0, Color(0.55, 0.85, 1.0)])
	elif style > 0:
		lines.append(["STYLE  %s   (BEST %s)" % [_fmt(style), _fmt(best)], 0, Color(0.75, 0.75, 0.8)])
	for l: Array in lines:
		cash += int(l[1])
	_save()
	return lines


func _show_result(won: bool, lines: Array, _res: Dictionary) -> void:
	phase = Phase.RESULT
	ui.visible = true
	view_rect.visible = true
	menu_box.visible = false
	list_box.visible = false
	list_title.visible = false
	card.visible = false
	name_l.visible = false
	name_r.visible = false
	if res_panel != null:
		res_panel.queue_free()
	_fade_in()
	if music != null:
		music.call("start")
	res_panel = PanelContainer.new()
	res_panel.add_theme_stylebox_override("panel", _panel_box(GOLD if won else RED))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	res_panel.add_child(v)
	var ch := _ch(cur)
	v.add_child(_label(str(ch.get("title", "")).to_upper() + "  -  " + str(ch.get("name", "")).to_upper(), font_b, 20, Color(0.8, 0.8, 0.85), 4))
	var head := _label("CHAPTER CLEARED!" if won else "KNOCKED OUT...", font_i, 56, GOLD if won else Color(1.0, 0.45, 0.4), 12)
	_shadow(head, 5.0)
	v.add_child(head)
	if not won:
		v.add_child(_label("No payday tonight. Shake it off and run it back.", font_b, 22, CREAM, 4))
	var delay := 0.5
	var rows: Array[Control] = []
	for l: Array in lines:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 24)
		var a := _label(str(l[0]), font_i, 26, l[2], 6)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(a)
		var amt := int(l[1])
		if amt > 0:
			h.add_child(_label("+$%d" % amt, font_i, 30, GREEN, 7))
		v.add_child(h)
		rows.append(h)
		h.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_property(h, "modulate:a", 1.0, 0.15)
		if amt > 0:
			tw.tween_callback(func():
				_snd("combo_bank", -4.0)
				_snd("cheer_small", -8.0))
		delay += 0.45
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.25)
	sep.custom_minimum_size = Vector2(0, 2)
	v.add_child(sep)
	var bank := HBoxContainer.new()
	bank.add_child(_label("BACKYARD BANK", font_i, 28, CREAM, 6))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank.add_child(sp)
	res_cash_label = _label("$" + _fmt(int(cash_shown)), font_i, 36, GOLD, 8)
	bank.add_child(res_cash_label)
	v.add_child(bank)
	var unlocked_next := won and cur + 1 < chapters.size()
	if unlocked_next:
		var un := _label("UNLOCKED:  " + str(_ch(cur + 1).get("title", "")).to_upper() + "  -  " + str(_ch(cur + 1).get("name", "")).to_upper(), font_b, 20, GREEN, 4)
		v.add_child(un)
	elif won:
		v.add_child(_label("THAT'S THE WHOLE STORY... FOR NOW.", font_b, 20, GREEN, 4))
	var bl: Array[Button] = []
	var acts: Array[Callable] = []
	if won and unlocked_next:
		bl.append(_make_button("NEXT CHAPTER", true))
		var nxt := cur + 1
		acts.append(func(): _start_chapter(nxt))
	elif not won:
		bl.append(_make_button("RETRY MATCH", true))
		var again := cur
		acts.append(func():
			phase = Phase.CARD
			_launch_match(again))
	bl.append(_make_button("STORY HUB", true))
	acts.append(_show_hub)
	for b in bl:
		v.add_child(b)
	ui.add_child(res_panel)
	# Money arrives while the lines pop in (the counter rolls up in _process).
	cash_shown = float(cash) - _sum_lines(lines)
	_set_buttons(bl, acts, 0)
	input_lock = delay
	hint.text = "UP / DOWN  select     ENTER / J  confirm"
	_relayout()
	res_panel.pivot_offset = res_panel.size * 0.5
	res_panel.scale = Vector2(1.0, 0.0)
	var tp := create_tween()
	tp.tween_property(res_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if won:
		_snd("cheer_small", -2.0)
		_spawn_pose_win()


func _sum_lines(lines: Array) -> float:
	var s := 0
	for l: Array in lines:
		s += int(l[1])
	return float(s)


# ---------------------------------------------------------------- cutscenes

## Plays a SCENE list (story_schema.md) with the cutscene engine (res://cutscene.tscn), or the
## built-in placeholder player when it cannot be loaded (and when headless, to keep CI quick).
## card = also show the engine's chapter card first (play() waits for it).
func _play_scenes(scenes: Array, done: Callable, card := false) -> void:
	after_scenes = done
	if phase != Phase.RESULT:
		phase = Phase.CUTSCENE
	var cs := _new_cutscene()
	if cs != null:
		ui.visible = false
		view_rect.visible = false
		bg.visible = false
		if music != null:
			music.call("fade_out", 0.4)
		add_child(cs)
		cs.connect("finished", func(_skipped: bool): _on_cutscene_finished(cs), CONNECT_ONE_SHOT)
		if card and cs.has_method("show_title_card"):
			var ch := _ch(cur)
			cs.call("show_title_card", str(ch.get("title", "CHAPTER %d" % (cur + 1))), str(ch.get("name", "")), str(ch.get("teaser", "")))
		cs.call("play", scenes, cast)
		return
	if scenes.is_empty():
		_scenes_finished()
		return
	_dlg_start(scenes)


func _new_cutscene() -> Node:
	if headless or not ResourceLoader.exists(CUTSCENE_SCENE):
		return null
	var ps := load(CUTSCENE_SCENE) as PackedScene
	if ps == null:
		return null
	var cs: Node = ps.instantiate()
	if cs == null:
		return null
	if not cs.has_method("play") or not cs.has_signal("finished"):
		cs.free()
		return null
	return cs


func _on_cutscene_finished(cs: Node) -> void:
	# The engine ends on black and stays alive: free it, keep the screen black behind it and
	# let whatever comes next (match load / result panel) take over from there.
	fade_rect.visible = true
	fade_rect.color.a = 1.0
	if is_instance_valid(cs):
		cs.queue_free()
	bg.visible = true
	_scenes_finished()


func _fade_in() -> void:
	if fade_rect.visible and phase != Phase.LEAVING:
		var tw := create_tween()
		tw.tween_property(fade_rect, "color:a", 0.0, 0.35)
		tw.tween_callback(func():
			if phase != Phase.LEAVING:
				fade_rect.visible = false)


func _scenes_finished() -> void:
	bg_time = "night"
	var d := after_scenes
	after_scenes = Callable()
	if d.is_valid():
		d.call()


# ---- placeholder dialogue player (until res://cutscene.tscn exists)

func _dlg_start(scenes: Array) -> void:
	dlg_scenes = scenes
	dlg_scene_i = 0
	dlg_line_i = 0
	ui.visible = false
	view_rect.visible = false
	dlg.visible = true
	_dlg_show()


func _dlg_scene() -> Dictionary:
	if dlg_scene_i >= dlg_scenes.size():
		return {}
	var s: Variant = dlg_scenes[dlg_scene_i]
	if s is Dictionary:
		return s
	return {}


func _dlg_lines() -> Array:
	var l: Variant = _dlg_scene().get("lines", [])
	if l is Array:
		return l
	return []


func _dlg_show() -> void:
	var sc := _dlg_scene()
	var lines := _dlg_lines()
	if dlg_line_i >= lines.size():
		dlg_scene_i += 1
		dlg_line_i = 0
		if dlg_scene_i >= dlg_scenes.size():
			_dlg_end()
			return
		_dlg_show()
		return
	bg_time = str(sc.get("time", "night"))
	var set_id := str(sc.get("set", "backyard"))
	dlg_place.text = "%s  -  %s" % [str(SET_NAMES.get(set_id, set_id.to_upper())), bg_time.to_upper()]
	var who_list: Array[String] = []
	var cs: Variant = sc.get("cast", {})
	if cs is Dictionary:
		for k in (cs as Dictionary).keys():
			if str((cs as Dictionary)[k]) != "offscreen":
				who_list.append(_cast_name(str(k)))
	dlg_cast.text = "  /  ".join(who_list)
	var ln: Dictionary = {}
	var lv: Variant = lines[dlg_line_i]
	if lv is Dictionary:
		ln = lv
	var who := str(ln.get("who", "narrator"))
	var text := str(ln.get("text", ""))
	dlg_box.visible = who != "narrator" and who != "phone"
	dlg_caption.visible = who == "narrator"
	dlg_phone.visible = who == "phone"
	var target: Label = dlg_text
	if who == "narrator":
		target = dlg_caption_text
	elif who == "phone":
		target = dlg_phone_text
	else:
		dlg_name.text = _cast_name(who)
		var sb := StyleBoxFlat.new()
		sb.bg_color = _cast_color(who).darkened(0.15)
		sb.skew = Vector2(0.25, 0.0)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		dlg_name.add_theme_stylebox_override("normal", sb)
		var emote := str(ln.get("emote", ""))
		var act := str(ln.get("action", ""))
		var dir_txt := ""
		if emote != "" and emote != "idle" and emote != "talk":
			dir_txt = emote.replace("_", " ")
		if act != "":
			dir_txt += ("  /  " if dir_txt != "" else "") + act.replace("_", " ").replace(":", " ")
		dlg_emote.text = ("(" + dir_txt + ")") if dir_txt != "" else ""
	target.text = text
	target.visible_characters = 0
	dlg_full = text.length()
	dlg_t = 0.0
	var sfx := str(ln.get("sfx", ""))
	if sfx != "":
		_snd(sfx, -4.0)
	var c := int(ln.get("cash", 0))
	if c > 0:
		_cash_pop(c)
	dlg_more.visible = false
	_dlg_layout()


func _dlg_target() -> Label:
	if dlg_caption.visible:
		return dlg_caption_text
	if dlg_phone.visible:
		return dlg_phone_text
	return dlg_text


func _dlg_tick(delta: float) -> void:
	dlg_t += delta
	var lbl := _dlg_target()
	var n := mini(dlg_full, int(dlg_t * 50.0))
	if lbl.visible_characters != n and lbl.visible_characters >= 0:
		lbl.visible_characters = n
	if n >= dlg_full:
		lbl.visible_characters = -1
		dlg_more.visible = true
		dlg_more.modulate.a = 0.5 + 0.5 * sin(t * 6.0)


func _dlg_input(confirm: bool, back: bool, tap: bool) -> void:
	if dlg == null or not dlg.visible:
		return
	get_viewport().set_input_as_handled()
	if back:
		_dlg_end()
	elif confirm or tap:
		_dlg_advance(false)


func _dlg_advance(force: bool) -> void:
	var lbl := _dlg_target()
	if not force and lbl.visible_characters >= 0 and lbl.visible_characters < dlg_full:
		lbl.visible_characters = -1
		dlg_t = 999.0
		return
	_snd("pop", -14.0, 0.1)
	dlg_line_i += 1
	_dlg_show()


func _dlg_end() -> void:
	dlg.visible = false
	_scenes_finished()


func _cash_pop(amount: int) -> void:
	var l := _label("+$%d" % amount, font_i, 46, GREEN, 10)
	over.add_child(l)
	var vp := get_viewport().get_visible_rect().size
	l.reset_size()
	l.position = Vector2(vp.x * 0.5 - l.size.x * 0.5, vp.y * 0.42)
	_snd("combo_bank", -6.0)
	var tw := create_tween()
	tw.tween_property(l, "position:y", vp.y * 0.3, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2).set_delay(0.5)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------- 3D fighters

func _build_view() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	view = SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	view.msaa_3d = Viewport.MSAA_2X
	view.gui_disable_input = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.size = Vector2i(720, 540)
	layer.add_child(view)
	world = Node3D.new()
	view.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.45, 0.6)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.62, 0.7, 1.0)
	moon.light_energy = 0.55
	moon.rotation_degrees = Vector3(-35, 30, 0)
	world.add_child(moon)
	var porch := OmniLight3D.new()
	porch.light_color = Color(1.0, 0.72, 0.4)
	porch.light_energy = 2.2
	porch.omni_range = 9.0
	porch.position = Vector3(-2.6, 2.4, 2.0)
	world.add_child(porch)
	var rim := OmniLight3D.new()
	rim.light_color = Color(0.55, 0.65, 1.0)
	rim.light_energy = 2.5
	rim.omni_range = 7.0
	rim.position = Vector3(1.8, 2.6, -2.4)
	world.add_child(rim)
	var fill := SpotLight3D.new()
	fill.light_color = Color(1.0, 0.95, 0.9)
	fill.light_energy = 1.6
	fill.spot_range = 12.0
	fill.spot_angle = 35.0
	fill.position = Vector3(0.5, 3.5, 5.0)
	world.add_child(fill)
	fill.look_at(Vector3(0, 1.0, 0))
	camera = Camera3D.new()
	camera.fov = 34.0
	camera.position = Vector3(0.05, 1.05, 3.9)
	world.add_child(camera)
	camera.look_at(Vector3(0.05, 0.92, 0.0))
	camera.current = true
	# soft blob shadows
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.6))
	grad.set_color(1, Color(0, 0, 0, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = gt
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for x in [-0.8, 0.85]:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.3, 0.8)
		q.mesh = qm
		q.material_override = sm
		q.rotation_degrees = Vector3(-90, 0, 0)
		q.position = Vector3(x, 0.01, 0.0)
		world.add_child(q)
	view_rect = TextureRect.new()
	view_rect.texture = view.get_texture()
	view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(view_rect)


func _want_opponent(id: String) -> void:
	want_opp = id
	opp_timer = 0.35
	if id == "" and fighters.size() > 1 and fighters[1] != null:
		fighters[1].visible = false
	elif fighters.size() > 1 and fighters[1] != null and id == fighter_ids[1]:
		fighters[1].visible = true


func _spawn_fighter(slot: int, id: String) -> void:
	if headless or id == "":
		return
	while fighters.size() <= slot:
		fighters.append(null)
	if fighters[slot] != null:
		fighters[slot].queue_free()
		fighters[slot] = null
	var game := _game()
	var look: Dictionary = {}
	var nm := id.to_upper()
	if game != null:
		look = game.call("look_of", id)
		var e: Dictionary = game.call("entry", id)
		nm = str(e.get("display_name", nm))
	var w: Node3D = Wrestler.new()
	world.add_child(w)
	w.call("setup", nm, look, false)
	var pos: Vector3 = Vector3(-0.8, 0.0, 0.05) if slot == 0 else Vector3(0.85, 0.0, -0.1)
	var yaw: float = 0.5 if slot == 0 else -0.55
	w.position = pos
	w.rotation.y = yaw
	w.set("facing", Vector3(sin(yaw), 0.0, cos(yaw)))
	fighters[slot] = w
	fighter_ids[slot] = id
	pose_i[slot] = 0
	pose_left[slot] = 1.0 + slot
	w.set("state", Wrestler.S.IDLE)
	w.set("state_time", 0.0)
	_link_fighters()


func _link_fighters() -> void:
	if fighters.size() < 2 or fighters[0] == null or fighters[1] == null:
		if fighters.size() > 0 and fighters[0] != null:
			fighters[0].set("opponent", null)
		return
	fighters[0].set("opponent", fighters[1])
	fighters[1].set("opponent", fighters[0])


func _spawn_pose_win() -> void:
	if fighters.size() > 0 and fighters[0] != null:
		pose_i[0] = 2
		pose_left[0] = 3.0
		fighters[0].set("state", Wrestler.S.WIN)
		fighters[0].set("state_time", 0.0)


func _animate_fighters(dt: float) -> void:
	var seq := [[Wrestler.S.IDLE, 3.0], [Wrestler.S.TAUNT, Wrestler.TAUNT_TIME], [Wrestler.S.IDLE, 2.6], [Wrestler.S.WIN, 3.2]]
	for i in fighters.size():
		var w: Node3D = fighters[i]
		if w == null or not w.visible:
			continue
		var left: float = float(pose_left[i]) - dt
		if left <= 0.0:
			var ni: int = (int(pose_i[i]) + 1) % seq.size()
			pose_i[i] = ni
			var step: Array = seq[ni]
			left = float(step[1])
			w.set("state", int(step[0]))
			w.set("state_time", 0.0)
		pose_left[i] = left
		w.set("state_time", float(w.get("state_time")) + dt)
		w.set("anim_clock", float(w.get("anim_clock")) + dt)
		if w.has_method("_update_pose"):
			w.call("_update_pose", dt)


# ---------------------------------------------------------------- backdrop (painted night yard)

func _build_bg() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	bg = Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_bg)
	layer.add_child(bg)


func _sky_cols() -> Array:
	match bg_time:
		"day":
			return [Color(0.36, 0.6, 0.9), Color(0.75, 0.86, 0.95), 0.0]
		"dusk":
			return [Color(0.2, 0.14, 0.36), Color(0.95, 0.5, 0.3), 0.35]
	return [Color(0.015, 0.02, 0.07), Color(0.16, 0.09, 0.22), 1.0]


func _glow(c: Vector2, r: float, col: Color) -> void:
	for i in 6:
		var k := 1.0 - float(i) / 6.0
		bg.draw_circle(c, r * k, Color(col.r, col.g, col.b, col.a * 0.16))


func _draw_bg() -> void:
	var sz := bg.size
	var w := sz.x
	var h := sz.y
	var sky: Array = _sky_cols()
	var top: Color = sky[0]
	var bot: Color = sky[1]
	var night: float = sky[2]
	var horizon := h * 0.6
	var bands := 28
	for i in bands:
		var y0 := horizon * float(i) / bands
		bg.draw_rect(Rect2(0, y0, w, horizon / bands + 1.0), top.lerp(bot, float(i) / (bands - 1)))
	# stars + moon
	if night > 0.2:
		for s in stars:
			var tw := 0.55 + 0.45 * sin(t * 1.7 + s.z)
			bg.draw_rect(Rect2(s.x * w, s.y * h, 2, 2), Color(0.9, 0.9, 1.0, 0.8 * tw * night))
		var mc := Vector2(w * 0.72, h * 0.14)
		_glow(mc, 90.0, Color(0.6, 0.65, 1.0, 0.5 * night))
		bg.draw_circle(mc, 26.0, Color(1.0, 0.97, 0.85, night))
		bg.draw_circle(mc + Vector2(8, -5), 24.0, top.lerp(bot, 0.25))
	else:
		_glow(Vector2(w * 0.8, h * 0.2), 120.0, Color(1.0, 0.85, 0.5, 0.6))
		bg.draw_circle(Vector2(w * 0.8, h * 0.2), 34.0, Color(1.0, 0.92, 0.7))
	# far city skyline
	var city_col := Color(0.05, 0.05, 0.1).lerp(Color(0.35, 0.4, 0.5), 1.0 - night)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var x := 0.0
	while x < w:
		var bw := rng.randf_range(40.0, 110.0)
		var bh := rng.randf_range(30.0, 150.0)
		bg.draw_rect(Rect2(x, horizon - bh, bw - 4.0, bh + 2.0), city_col)
		if night > 0.2:
			for j in int(bh / 16.0):
				for k in int(bw / 18.0):
					if rng.randf() < 0.22:
						bg.draw_rect(Rect2(x + 6 + k * 18, horizon - bh + 8 + j * 16, 6, 7), Color(1.0, 0.8, 0.45, 0.55 * night))
		x += bw
	# lawn
	var g0 := Color(0.05, 0.09, 0.04).lerp(Color(0.25, 0.45, 0.18), 1.0 - night)
	var g1 := Color(0.015, 0.03, 0.015).lerp(Color(0.14, 0.3, 0.1), 1.0 - night)
	for i in 12:
		var y0 := horizon + (h - horizon) * float(i) / 12.0
		bg.draw_rect(Rect2(0, y0, w, (h - horizon) / 12.0 + 1.0), g0.lerp(g1, float(i) / 11.0))
	# fence
	var fence_top := horizon - h * 0.07
	var fc := Color(0.2, 0.15, 0.11).lerp(Color(0.55, 0.42, 0.3), 1.0 - night)
	bg.draw_rect(Rect2(0, fence_top, w, horizon - fence_top + h * 0.05), fc)
	var px := 0.0
	while px < w:
		bg.draw_rect(Rect2(px, fence_top - 6.0, 3.0, horizon - fence_top + h * 0.05 + 6.0), fc.darkened(0.35))
		bg.draw_colored_polygon(PackedVector2Array([Vector2(px + 3, fence_top - 6), Vector2(px + 17, fence_top - 14), Vector2(px + 31, fence_top - 6)]), fc)
		px += 34.0
	# house (left)
	var hx := w * 0.0
	var hw := w * 0.26
	var hy := horizon - h * 0.32
	var wall := Color(0.12, 0.12, 0.16).lerp(Color(0.7, 0.68, 0.62), 1.0 - night)
	bg.draw_rect(Rect2(hx, hy, hw, horizon - hy + h * 0.08), wall)
	bg.draw_colored_polygon(PackedVector2Array([Vector2(hx - 20, hy + 2), Vector2(hx + hw * 0.5, hy - h * 0.13), Vector2(hx + hw + 20, hy + 2)]), wall.darkened(0.45))
	var lit := Color(1.0, 0.72, 0.36)
	var win_r := Rect2(hx + hw * 0.55, hy + h * 0.07, hw * 0.28, h * 0.09)
	if night > 0.2:
		_glow(win_r.get_center(), 70.0, Color(lit.r, lit.g, lit.b, 0.6))
	bg.draw_rect(win_r, lit if night > 0.2 else Color(0.5, 0.65, 0.8))
	bg.draw_rect(Rect2(win_r.position.x + win_r.size.x * 0.48, win_r.position.y, 3, win_r.size.y), wall.darkened(0.5))
	# porch light
	var pl := Vector2(hx + hw * 0.25, hy + h * 0.1)
	if night > 0.2:
		_glow(pl, 110.0, Color(1.0, 0.75, 0.4, 0.7))
	bg.draw_circle(pl, 5.0, Color(1.0, 0.92, 0.7))
	# string lights: house corner -> right pole
	var a := Vector2(hx + hw, hy + 10.0)
	var b := Vector2(w * 0.98, hy - h * 0.02)
	bg.draw_rect(Rect2(b.x - 3, b.y, 6, horizon - b.y + h * 0.06), fc.darkened(0.5))
	var prev := a
	var bulbs := 18
	for i in bulbs + 1:
		var u := float(i) / bulbs
		var p := a.lerp(b, u) + Vector2(0, sin(u * PI) * h * 0.07)
		bg.draw_line(prev, p, Color(0.05, 0.05, 0.05), 2.0)
		prev = p
		if i > 0 and i < bulbs:
			var cols := [Color(1.0, 0.35, 0.25), Color(1.0, 0.82, 0.3), Color(0.35, 0.85, 1.0), Color(0.5, 1.0, 0.45)]
			var c: Color = cols[i % 4]
			var on := 0.65 + 0.35 * sin(t * 2.3 + i * 1.7)
			if night > 0.2:
				_glow(p + Vector2(0, 6), 18.0, Color(c.r, c.g, c.b, 0.55 * on))
			bg.draw_circle(p + Vector2(0, 6), 4.0, c.lerp(Color.WHITE, 0.3 * on))
	# yard props: kiddie pool, trampoline, folding table
	var pool_c := Vector2(w * 0.38, h * 0.82)
	bg.draw_set_transform(pool_c, 0.0, Vector2(1.0, 0.32))
	bg.draw_circle(Vector2.ZERO, 90.0, Color(0.1, 0.25, 0.45).lerp(Color(0.3, 0.6, 0.9), 1.0 - night))
	bg.draw_circle(Vector2.ZERO, 74.0, Color(0.15, 0.4, 0.6).lerp(Color(0.5, 0.8, 1.0), 1.0 - night))
	bg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tr_c := Vector2(w * 0.86, horizon + h * 0.05)
	bg.draw_set_transform(tr_c, 0.0, Vector2(1.0, 0.25))
	bg.draw_circle(Vector2.ZERO, 120.0, Color(0.03, 0.03, 0.04))
	bg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for k in [-1.0, 1.0]:
		bg.draw_line(tr_c + Vector2(100.0 * k, 0), tr_c + Vector2(100.0 * k, 40), Color(0.03, 0.03, 0.04), 4.0)
	# vignette + bottom fade for the UI
	for i in 8:
		var k := float(i) / 8.0
		bg.draw_rect(Rect2(0, h * (0.82 + k * 0.18), w, h * 0.03), Color(0, 0, 0, 0.08 + 0.05 * i))
	for i in 10:
		bg.draw_rect(Rect2(0, 0, w * (0.5 - 0.04 * i), h), Color(0, 0, 0, 0.045))


# ---------------------------------------------------------------- icons

func _draw_icon(c: Control, kind: String) -> void:
	var s := c.size
	var m := s * 0.5
	match kind:
		"medal":
			c.draw_line(m + Vector2(-8, -18), m + Vector2(-3, -4), RED, 6.0)
			c.draw_line(m + Vector2(8, -18), m + Vector2(3, -4), Color(0.2, 0.4, 0.9), 6.0)
			c.draw_circle(m + Vector2(0, 4), 13.0, INK)
			c.draw_circle(m + Vector2(0, 4), 11.0, GOLD)
			c.draw_circle(m + Vector2(0, 4), 7.0, GOLD.lightened(0.35))
			var pts := PackedVector2Array()
			for i in 10:
				var r := 7.0 if i % 2 == 0 else 3.0
				var a := -PI / 2 + i * PI / 5
				pts.append(m + Vector2(0, 4) + Vector2(cos(a), sin(a)) * r)
			c.draw_colored_polygon(pts, Color(0.75, 0.5, 0.05))
		"check":
			var pts2 := PackedVector2Array([m + Vector2(-12, 0), m + Vector2(-4, 9), m + Vector2(13, -11)])
			c.draw_polyline(pts2, INK, 9.0)
			c.draw_polyline(pts2, GREEN, 5.0)
		"lock":
			c.draw_arc(m + Vector2(0, -4), 8.0, PI, TAU, 12, Color(0.6, 0.6, 0.62), 4.0)
			c.draw_rect(Rect2(m + Vector2(-11, -4), Vector2(22, 17)), Color(0.6, 0.6, 0.62))
			c.draw_rect(Rect2(m + Vector2(-2, 2), Vector2(4, 6)), INK)
		"new":
			c.draw_rect(Rect2(m + Vector2(-20, -10), Vector2(40, 20)), RED)
			c.draw_string(font_b, m + Vector2(-17, 6), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, CREAM)


# ---------------------------------------------------------------- UI build

func _label(text: String, font: Font, size: int, col: Color, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	return l


func _shadow(l: Label, off: float) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", int(off))
	l.add_theme_constant_override("shadow_offset_y", int(off))


func _btn_box(on: bool, big: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.skew = Vector2(0.22, 0.0)
	sb.bg_color = GOLD if on else Color(0.04, 0.035, 0.04, 0.82)
	sb.border_color = INK if on else RED
	sb.border_width_left = 10 if big else 7
	sb.border_width_bottom = 4 if on else 2
	sb.content_margin_left = 30 if big else 24
	sb.content_margin_right = 64 if not big else 24
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 1 if on else 0
	sb.shadow_offset = Vector2(6, 6)
	return sb


func _panel_box(border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.9)
	sb.border_color = border
	sb.border_width_left = 8
	sb.border_width_top = 3
	sb.border_width_bottom = 3
	sb.border_width_right = 3
	sb.skew = Vector2(0.05, 0.0)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 16
	sb.content_margin_bottom = 18
	return sb


func _make_button(text: String, big: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.set_meta("label", text)
	b.set_meta("big", big)
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(440, 60) if big else Vector2(480, 50)
	b.add_theme_font_override("font", font_i)
	b.add_theme_font_size_override("font_size", 32 if big else 24)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("normal", _btn_box(false, big))
	b.clip_text = true
	return b


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 1
	add_child(ui_layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui)

	# header: STORY MODE stamp + subtitle
	header = Control.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(header)
	var tape := ColorRect.new()
	tape.color = RED
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tape.size = Vector2(420, 70)
	tape.position = Vector2(-10, 6)
	tape.rotation = deg_to_rad(-2.0)
	header.add_child(tape)
	var title := _label("STORY MODE", font_i, 64, Color.WHITE, 14)
	_shadow(title, 6.0)
	title.position = Vector2(10, -6)
	title.rotation = deg_to_rad(-2.0)
	header.add_child(title)
	var sub := _label("THE TANK MAGRUDER STORY", font_b, 20, GOLD, 6)
	sub.position = Vector2(18, 84)
	header.add_child(sub)

	# bank counter
	bank_panel = PanelContainer.new()
	var bsb := _panel_box(GOLD)
	bsb.content_margin_top = 6
	bsb.content_margin_bottom = 6
	bsb.skew = Vector2(0.2, 0.0)
	bank_panel.add_theme_stylebox_override("panel", bsb)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 16)
	bank_panel.add_child(bh)
	bh.add_child(_label("BACKYARD BANK:", font_i, 24, CREAM, 6))
	bank_label = _label("$0", font_i, 34, GOLD, 8)
	bh.add_child(bank_label)
	ui.add_child(bank_panel)

	# hub menu
	menu_box = VBoxContainer.new()
	menu_box.add_theme_constant_override("separation", 12)
	ui.add_child(menu_box)
	for txt in ["CONTINUE", "CHAPTER SELECT", "BACK"]:
		menu_box.add_child(_make_button(txt, true))

	# chapter list
	list_title = _label("CHAPTER SELECT", font_i, 30, CREAM, 8)
	ui.add_child(list_title)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 8)
	ui.add_child(list_box)

	# fighter name tags under the 3D view
	name_l = _label("TANK MAGRUDER", font_i, 24, Color(1.0, 0.5, 0.42), 7)
	ui.add_child(name_l)
	name_r = _label("", font_i, 24, CREAM, 7)
	ui.add_child(name_r)

	# chapter card
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_box(GOLD))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	card.add_child(cv)
	card_kicker = _label("CHAPTER 1", font_b, 20, Color(1.0, 0.5, 0.42), 4)
	cv.add_child(card_kicker)
	card_name = _label("", font_i, 44, GOLD, 10)
	_shadow(card_name, 4.0)
	cv.add_child(card_name)
	card_teaser = _label("", font_b, 20, CREAM, 4)
	card_teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_teaser.custom_minimum_size = Vector2(560, 0)
	cv.add_child(card_teaser)
	card_info = _label("", font_i, 19, Color(0.8, 0.85, 0.95), 4)
	cv.add_child(card_info)
	card_status = _label("", font_i, 19, GOLD, 4)
	cv.add_child(card_status)
	ui.add_child(card)

	hint = _label("", font_b, 18, Color(0.85, 0.85, 0.85), 5)
	ui.add_child(hint)


func _build_overlay() -> void:
	over_layer = CanvasLayer.new()
	over_layer.layer = 5
	add_child(over_layer)
	over = Control.new()
	over.set_anchors_preset(Control.PRESET_FULL_RECT)
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over_layer.add_child(over)
	tc = Control.new()
	tc.set_anchors_preset(Control.PRESET_FULL_RECT)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.visible = false
	over.add_child(tc)

	# placeholder dialogue player
	dlg = Control.new()
	dlg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.visible = false
	over.add_child(dlg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg.add_child(shade)
	dlg_place = _label("", font_i, 30, GOLD, 8)
	dlg.add_child(dlg_place)
	dlg_cast = _label("", font_b, 18, CREAM, 5)
	dlg.add_child(dlg_cast)
	var skip := _label("ESC / B  skip", font_b, 18, Color(0.8, 0.8, 0.8), 4)
	skip.name = "Skip"
	dlg.add_child(skip)

	dlg_box = PanelContainer.new()
	dlg_box.add_theme_stylebox_override("panel", _panel_box(CREAM))
	dlg_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	dlg_box.add_child(dv)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 14)
	dv.add_child(nh)
	dlg_name = _label("", font_i, 26, Color.WHITE, 6)
	nh.add_child(dlg_name)
	dlg_emote = _label("", font_i, 18, Color(0.7, 0.7, 0.75), 4)
	dlg_emote.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nh.add_child(dlg_emote)
	dlg_text = _label("", font_b, 28, CREAM, 5)
	dlg_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(dlg_text)
	dlg.add_child(dlg_box)

	dlg_caption = PanelContainer.new()
	var csb := _panel_box(GOLD)
	csb.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	dlg_caption.add_theme_stylebox_override("panel", csb)
	dlg_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_caption_text = _label("", font_i, 28, Color(1.0, 0.95, 0.8), 5)
	dlg_caption_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg_caption_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dlg_caption.add_child(dlg_caption_text)
	dlg.add_child(dlg_caption)

	dlg_phone = PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.2, 0.55, 1.0, 0.95)
	psb.set_corner_radius_all(22)
	psb.content_margin_left = 24
	psb.content_margin_right = 24
	psb.content_margin_top = 14
	psb.content_margin_bottom = 14
	psb.border_color = Color.WHITE
	psb.set_border_width_all(3)
	dlg_phone.add_theme_stylebox_override("panel", psb)
	dlg_phone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlg_phone_text = _label("", font_b, 26, Color.WHITE, 4)
	dlg_phone_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg_phone.add_child(dlg_phone_text)
	dlg.add_child(dlg_phone)

	dlg_more = _label("ENTER  >>", font_i, 20, GOLD, 5)
	dlg.add_child(dlg_more)

	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	over.add_child(fade_rect)
	loading_label = _label("LOADING...", font_i, 30, GOLD, 8)
	loading_label.visible = false
	over.add_child(loading_label)


func _relayout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var mx := clampf(vp.x * 0.035, 24.0, 64.0)
	var my := clampf(vp.y * 0.04, 18.0, 40.0)
	header.position = Vector2(mx, my)
	bank_panel.reset_size()
	var bs := bank_panel.get_combined_minimum_size()
	bank_panel.size = bs
	bank_panel.position = Vector2(vp.x - mx - bs.x, my + 10.0)

	var col_y := my + 130.0
	menu_box.reset_size()
	menu_box.size = menu_box.get_combined_minimum_size()
	menu_box.position = Vector2(mx + 8.0, col_y + 20.0)
	list_title.reset_size()
	list_title.position = Vector2(mx + 8.0, col_y - 6.0)
	list_box.reset_size()
	list_box.size = list_box.get_combined_minimum_size()
	list_box.position = Vector2(mx + 8.0, col_y + 36.0)

	# right side: fighters above, chapter card below
	var right_x := maxf(mx + 520.0, vp.x * 0.44)
	var card_w := vp.x - mx - right_x
	card_teaser.custom_minimum_size = Vector2(maxf(300.0, card_w - 70.0), 0)
	card.reset_size()
	var cs := card.get_combined_minimum_size()
	card.size = Vector2(maxf(cs.x, card_w), cs.y)
	card.position = Vector2(vp.x - mx - card.size.x, vp.y - my - 30.0 - cs.y)
	var view_top := my + 60.0
	var view_bot := card.position.y + 30.0
	var vw := vp.x - right_x + mx * 0.5
	var vh := maxf(200.0, view_bot - view_top)
	view_rect.position = Vector2(right_x - mx * 0.5, view_top)
	view_rect.size = Vector2(vw, vh)
	var vs := Vector2i(int(vw), int(vh))
	if view.size != vs:
		view.size = vs
	name_l.reset_size()
	name_r.reset_size()
	var tag_y := card.position.y - 40.0
	name_l.position = Vector2(view_rect.position.x + vw * 0.22 - name_l.size.x * 0.5, tag_y)
	name_r.position = Vector2(view_rect.position.x + vw * 0.78 - name_r.size.x * 0.5, tag_y)
	name_r.visible = name_r.text != "???" and name_l.visible

	hint.reset_size()
	hint.position = Vector2(mx + 10.0, vp.y - my - hint.size.y + 8.0)

	if res_panel != null and is_instance_valid(res_panel):
		res_panel.reset_size()
		var rs := res_panel.get_combined_minimum_size()
		res_panel.size = Vector2(maxf(rs.x, 620.0), rs.y)
		res_panel.position = Vector2(mx + 8.0, maxf(my + 120.0, (vp.y - rs.y) * 0.5 + 30.0))
		res_panel.pivot_offset = res_panel.size * 0.5

	loading_label.reset_size()
	loading_label.position = Vector2(vp.x - mx - loading_label.size.x, vp.y - my - loading_label.size.y)
	_dlg_layout()


func _dlg_layout() -> void:
	if dlg == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var mx := clampf(vp.x * 0.05, 24.0, 80.0)
	dlg_place.reset_size()
	dlg_place.position = Vector2(mx, 30.0)
	dlg_cast.reset_size()
	dlg_cast.position = Vector2(mx + 4.0, 72.0)
	var skip := dlg.get_node("Skip") as Label
	skip.reset_size()
	skip.position = Vector2(vp.x - mx - skip.size.x, 36.0)
	var bw := minf(vp.x - mx * 2.0, 1100.0)
	dlg_text.custom_minimum_size = Vector2(bw - 70.0, 0)
	dlg_box.reset_size()
	var bs := dlg_box.get_combined_minimum_size()
	dlg_box.size = Vector2(bw, maxf(bs.y, 150.0))
	dlg_box.position = Vector2((vp.x - bw) * 0.5, vp.y - dlg_box.size.y - 36.0)
	dlg_caption_text.custom_minimum_size = Vector2(minf(bw, 900.0) - 70.0, 0)
	dlg_caption.reset_size()
	var cs := dlg_caption.get_combined_minimum_size()
	dlg_caption.size = cs
	dlg_caption.position = Vector2((vp.x - cs.x) * 0.5, vp.y * 0.38 - cs.y * 0.5)
	dlg_phone_text.custom_minimum_size = Vector2(minf(460.0, vp.x - 120.0), 0)
	dlg_phone.reset_size()
	var ps := dlg_phone.get_combined_minimum_size()
	dlg_phone.size = ps
	dlg_phone.position = Vector2(vp.x - mx - ps.x - 40.0, vp.y * 0.42 - ps.y * 0.5)
	dlg_more.reset_size()
	dlg_more.position = Vector2(vp.x - mx - dlg_more.size.x - 10.0, vp.y - 30.0 - dlg_more.size.y)

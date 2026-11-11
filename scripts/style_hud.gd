extends CanvasLayer
## STYLE overlay (its own CanvasLayer, layer 2, above the main HUD).
##   - Trick popups spawn at the wrestler's on-screen head (3D head -> SubViewport -> screen):
##     big bold italic outlined name (color per kind) with the points under it, rise ~60 px and
##     fade; quick chains stack upward. The player's are big, the CPU's smaller.
##   - Player combo tally centered under the name plates: "x5   3,420" + draining combo-gap bar,
##     then a gold "BANKED +3,420" slam or a red shaking "COMBO BROKEN". (CPU: small, on its side.)
##   - Per wrestler, under its name plate: B R A W L slots (a big letter flies in from screen
##     center when one is earned), a labeled STYLE score and a slim labeled HYPE bar that fills
##     toward the next letter; in BRAWL MODE the bar flashes gold and counts down.
## Fed by the signals of scripts/style.gd (one per wrestler). Created by main.gd: setup(main, [p1, p2]).
## Sounds are emitted by style.gd / wrestler.gd ("trick", "letter", ...); this file plays none.

const EDGE := 16.0             # gap to the safe-area edge (matches main.gd's name plates)
const LETTER_Y := 84.0         # below the main HUD's name plates and its "SPECIAL" tag
const SLOT := 26.0             # letter slot size
const SLOT_PITCH := 29.0
const HYPE_Y := 116.0
const HYPE_LABEL_W := 46.0
const HYPE_BAR_W := 150.0
const HYPE_BAR_H := 8.0
const CPU_COMBO_Y := 134.0     # the CPU's small combo counter, on its side
const TALLY_Y := 60.0          # the player's combo tally (top center, under the "?" button)
const TALLY_W := 520.0
const TALLY_BAR_W := 240.0
const POP_RISE := 60.0
const POP_RISE_T := 0.8
const POP_LIFE := 1.15
const MAX_POPS := 4
const GOLD := Color(1.0, 0.84, 0.2)
const INK := Color(0.04, 0.03, 0.06, 0.95)
const KIND_COLORS := {
	"strike": Color(1.0, 0.62, 0.22),
	"grapple": Color(0.4, 0.9, 1.0),
	"aerial": Color(1.0, 0.45, 0.92),
	"air_trick": Color(0.6, 1.0, 0.3),
	"weapon": Color(1.0, 0.32, 0.22),
	"movement": Color(1.0, 0.95, 0.45),
	"super": Color(1.0, 0.84, 0.2),
}
const LETTERS := ["B", "R", "A", "W", "L"]

var main: Node
var root: Control
var font_i: FontVariation       # bold italic arcade face
var cols: Array = []            # one Dictionary per wrestler
var clock := 0.0


func setup(p_main: Node, wrestlers: Array) -> void:
	main = p_main
	layer = 2
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	font_i = FontVariation.new()
	font_i.base_font = ThemeDB.fallback_font
	font_i.variation_embolden = 1.1
	font_i.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.24, 1), Vector2.ZERO)
	for i in wrestlers.size():
		var w: Node3D = wrestlers[i]
		var st: Node = null
		for c in w.get_children():
			if c.has_signal("popped"):
				st = c
		if st == null or st.get_parent() != w:
			push_error("style_hud: wrestler %d (%s) has no StyleSys child; its STYLE column is off" % [i, w.name])
			continue
		cols.append(_build_col(w, st, i == 1))


func _label(size: int, col: Color, outline: Color, outline_px: int, parent: Node = null) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", font_i)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_px)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	(parent if parent != null else root).add_child(l)
	return l


func _rect(col: Color) -> ColorRect:
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = col
	root.add_child(r)
	return r


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(2)
	b.set_corner_radius_all(3)
	b.skew = Vector2(0.25, 0.0)
	return b


func _text_w(text: String, size: int) -> float:
	return font_i.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


func _build_col(w: Node3D, st: Node, right: bool) -> Dictionary:
	var cpu: bool = w.is_cpu
	var d := {"w": w, "st": st, "right": right, "cpu": cpu, "pops": [], "flyers": [],
		"in_flight": [false, false, false, false, false], "msg_t": 0.0, "msg_kind": "",
		"letters": [], "letter_pop": PackedFloat32Array([0, 0, 0, 0, 0]), "brawl": false}
	for i in LETTERS.size():
		var l := _label(19, Color(1, 1, 1, 0.35), Color(0, 0, 0, 0.8), 4)
		l.text = LETTERS[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(SLOT, SLOT)
		l.pivot_offset = Vector2(SLOT, SLOT) * 0.5
		l.add_theme_stylebox_override("normal", _box(Color(0.04, 0.04, 0.1, 0.65), Color(1, 1, 1, 0.25)))
		d["letters"].append(l)
	var score := _label(16, Color(1, 1, 1, 0.9), INK, 4)
	score.size = Vector2(130, SLOT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	d["score"] = score
	var banner := _label(22, GOLD, Color(0.5, 0.0, 0.05), 6)
	banner.text = "BRAWL MODE!"
	banner.size = Vector2(5 * SLOT_PITCH + 40.0, SLOT + 4.0)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.pivot_offset = banner.size * 0.5
	banner.add_theme_stylebox_override("normal", _box(Color(0.6, 0.02, 0.08, 0.85), GOLD))
	banner.visible = false
	d["banner"] = banner
	# HYPE bar: "HYPE" tag, ink frame, dark well, fill, next-letter / countdown tag.
	var htag := _label(15, Color(0.75, 0.9, 1.0), INK, 4)
	htag.size = Vector2(HYPE_LABEL_W, 16)
	htag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	d["htag"] = htag
	d["hframe"] = _rect(INK)
	d["hwell"] = _rect(Color(0.08, 0.09, 0.14, 0.92))
	d["hfill"] = _rect(Color(0.32, 0.62, 0.95))
	var hnext := _label(15, Color(1, 1, 1, 0.8), INK, 4)
	hnext.size = Vector2(60, 16)
	hnext.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	d["hnext"] = hnext
	# Combo tally. The player's sits top center (big); the CPU's on its own side (small).
	var tw := TALLY_W if not cpu else 300.0
	var combo := _label(40 if not cpu else 24, Color.WHITE, Color(0.05, 0.05, 0.3), 9 if not cpu else 6)
	combo.size = Vector2(tw, 48 if not cpu else 30)
	combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if not cpu else (HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT)
	combo.pivot_offset = Vector2(tw * 0.5 if not cpu else (tw if right else 0.0), combo.size.y * 0.5)
	combo.visible = false
	d["combo"] = combo
	var sub := _label(22 if not cpu else 16, Color.WHITE, INK, 5)
	sub.size = Vector2(tw, 26 if not cpu else 18)
	sub.horizontal_alignment = combo.horizontal_alignment
	sub.visible = false
	d["sub"] = sub
	d["cframe"] = _rect(INK)
	d["cbar"] = _rect(Color(0.4, 0.9, 1.0, 0.95))
	(d["cframe"] as ColorRect).visible = false
	(d["cbar"] as ColorRect).visible = false
	st.connect("popped", _on_popped.bind(d))
	st.connect("banked", _on_banked.bind(d))
	st.connect("broke", _on_broke.bind(d))
	st.connect("letter", _on_letter.bind(d))
	st.connect("brawl_changed", _on_brawl.bind(d))
	return d


func _safe_rect() -> Rect2:
	if main != null and main.has_method("_hud_safe_rect"):
		var r: Rect2 = main.call("_hud_safe_rect")
		return r
	return root.get_viewport_rect()


## Outer x of a wrestler's column (left edge for the left side, right edge for the right side).
func _col_edge(d: Dictionary, sr: Rect2) -> float:
	var right: bool = d["right"]
	return (sr.end.x - EDGE) if right else (sr.position.x + EDGE)


## Screen position of letter slot i (top-left of the box).
func _slot_pos(d: Dictionary, sr: Rect2, i: int) -> Vector2:
	var right: bool = d["right"]
	var x0 := _col_edge(d, sr)
	var x := (x0 - (5.0 - float(i)) * SLOT_PITCH + (SLOT_PITCH - SLOT)) if right else (x0 + float(i) * SLOT_PITCH)
	return Vector2(x, sr.position.y + LETTER_Y)


## The wrestler's head, projected from the 3D view (rendered in main.low_res_view, a SubViewport
## drawn full-screen by main.low_res_rect) into this overlay's coordinates.
func _head_screen(w: Node3D) -> Vector2:
	var vp_size := root.get_viewport_rect().size
	var fallback := Vector2(vp_size.x * 0.5, vp_size.y * 0.4)
	if main == null:
		return fallback
	var cam: Camera3D = main.get("camera")
	if cam == null or not cam.is_inside_tree():
		return fallback
	var hd: Node3D = w.get("head")
	var p3 := w.global_position + Vector3(0, 2.1, 0)
	if hd != null and hd.is_inside_tree():
		p3 = hd.global_position + Vector3(0, 0.42, 0)
	if cam.is_position_behind(p3):
		return fallback
	var p := cam.unproject_position(p3)
	var sv: SubViewport = main.get("low_res_view")
	var rect: TextureRect = main.get("low_res_rect")
	if sv != null and rect != null and sv.size.x > 0 and sv.size.y > 0:
		var r := rect.get_global_rect()
		return r.position + p / Vector2(sv.size) * r.size
	return p


# ---------------------------------------------------------------- events

func _on_popped(text: String, points: int, kind: String, mult: int, d: Dictionary) -> void:
	var cpu: bool = d["cpu"]
	var sr := _safe_rect()
	var pops: Array = d["pops"]
	var kc: Color = KIND_COLORS.get(kind, Color.WHITE)
	var big := points >= 1000 or kind == "super"
	var size := (52 if big else 44) if not cpu else (30 if big else 26)
	var max_w := minf(620.0 if not cpu else 380.0, sr.size.x * (0.6 if not cpu else 0.4))
	var tw := _text_w(text, size)
	while tw > max_w - 24.0 and size > (30 if not cpu else 18):
		size -= 2
		tw = _text_w(text, size)
	var hw := minf(max_w, tw + 40.0)
	var name_h := float(size) + 6.0
	var pt_size := 30 if not cpu else 20
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(hw, name_h + float(pt_size) + 4.0)
	holder.pivot_offset = holder.size * 0.5
	root.add_child(holder)
	var nm := _label(size, kc, Color(0.06, 0.02, 0.12), (10 if big else 9) if not cpu else 6, holder)
	nm.text = text
	nm.clip_text = true
	nm.size = Vector2(hw, name_h)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pt := _label(pt_size, GOLD, Color(0.3, 0.1, 0.0), 7 if not cpu else 5, holder)
	pt.text = "+%s" % _fmt(points) + ("" if mult < 2 else "   x%d" % mult)
	pt.size = Vector2(hw, float(pt_size) + 4.0)
	pt.position = Vector2(0, name_h - 4.0)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Anchor: centered over the head, kept clear of the top HUD and the bottom touch controls.
	var head := _head_screen(d["w"])
	var lift := 16.0 if not cpu else 10.0
	var ax := clampf(head.x, sr.position.x + hw * 0.5 + 8.0, sr.end.x - hw * 0.5 - 8.0)
	var ay := clampf(head.y - lift - holder.size.y, sr.position.y + 212.0, sr.end.y - 290.0 - holder.size.y * 0.5)
	# Several in quick succession: shove the young ones up so the new one lands under them.
	var step := holder.size.y + 4.0
	for o in pops:
		var oh: Control = o
		if float(oh.get_meta("age")) < POP_LIFE - 0.2:
			oh.set_meta("push_to", float(oh.get_meta("push_to")) + step)
	holder.set_meta("anchor", Vector2(ax - hw * 0.5 + randf_range(-14.0, 14.0), ay))
	holder.set_meta("age", 0.0)
	holder.set_meta("push", 0.0)
	holder.set_meta("push_to", 0.0)
	holder.set_meta("super", big)
	pops.push_front(holder)
	while pops.size() > MAX_POPS:
		var old: Control = pops.pop_back()
		old.queue_free()
	holder.scale = Vector2(1.6, 1.6)
	holder.modulate.a = 0.0
	var t := holder.create_tween().set_parallel(true)
	t.tween_property(holder, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(holder, "modulate:a", 1.0, 0.08)


func _show_msg(d: Dictionary, main_txt: String, sub_txt: String, col: Color, outline: Color, secs: float, kind: String) -> void:
	var c: Label = d["combo"]
	var s: Label = d["sub"]
	c.text = main_txt
	c.add_theme_color_override("font_color", col)
	c.add_theme_color_override("font_outline_color", outline)
	s.text = sub_txt
	s.add_theme_color_override("font_color", col.lightened(0.3))
	d["msg_t"] = secs
	d["msg_kind"] = kind
	c.visible = true
	s.visible = sub_txt != ""
	c.modulate.a = 1.0
	s.modulate.a = 1.0
	(d["cbar"] as ColorRect).visible = false
	(d["cframe"] as ColorRect).visible = false


func _on_banked(total: int, mult: int, d: Dictionary) -> void:
	var cpu: bool = d["cpu"]
	_show_msg(d, "BANKED +%s" % _fmt(total), "x%d COMBO" % mult, GOLD, Color(0.4, 0.14, 0.0), 1.4, "bank")
	var c: Label = d["combo"]
	if not cpu:
		c.add_theme_font_size_override("font_size", 50)
	c.scale = Vector2(2.3, 2.3) if not cpu else Vector2(1.5, 1.5)
	c.rotation = -0.08
	var t := c.create_tween().set_parallel(true)
	t.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "rotation", 0.0, 0.28)


func _on_broke(lost: int, d: Dictionary) -> void:
	var cpu: bool = d["cpu"]
	_show_msg(d, "COMBO BROKEN", "-%s" % _fmt(lost), Color(1.0, 0.24, 0.2), Color(0.18, 0.0, 0.0), 1.1, "break")
	var c: Label = d["combo"]
	if not cpu:
		c.add_theme_font_size_override("font_size", 46)
	c.scale = Vector2(1.25, 1.25)
	c.rotation = 0.0
	c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.15)


func _on_letter(n: int, d: Dictionary) -> void:
	if n < 1 or n > LETTERS.size():
		return
	var cpu: bool = d["cpu"]
	var vp := root.get_viewport_rect().size
	var size := 150 if not cpu else 104
	var l := _label(size, GOLD, Color(0.45, 0.05, 0.02), 14 if not cpu else 10)
	l.text = LETTERS[n - 1]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(size, size) * 1.2
	l.pivot_offset = l.size * 0.5
	var center := Vector2(vp.x * 0.5, vp.y * 0.36)
	if cpu:
		center.x += (vp.x * 0.18) * (1.0 if bool(d["right"]) else -1.0)
	l.position = center - l.size * 0.5
	l.scale = Vector2(0.3, 0.3)
	l.rotation = -0.4
	var inf: Array = d["in_flight"]
	inf[n - 1] = true
	var flyers: Array = d["flyers"]
	flyers.append({"l": l, "t": 0.0, "i": n - 1, "from": center})


func _on_brawl(on: bool, d: Dictionary) -> void:
	d["brawl"] = on
	var b: Label = d["banner"]
	if on:
		b.scale = Vector2(2.2, 2.2)
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	clock += delta
	if cols.is_empty():
		return
	var over: bool = main != null and main.get("match_over") == true
	root.visible = not over  # the win banner owns the screen
	if over:
		return
	var sr := _safe_rect()
	for d in cols:
		_update_col(d, sr, delta)


func _update_col(d: Dictionary, sr: Rect2, delta: float) -> void:
	var w: Node3D = d["w"]
	var st: Node = d["st"]
	var right: bool = d["right"]
	var cpu: bool = d["cpu"]
	var x0 := _col_edge(d, sr)
	var top := sr.position.y
	var gear: Color = w.gear_color
	var brawl: bool = w.brawl_mode
	var blink := int(clock * 9.0) % 2 == 0

	# --- flying letters: pop at center, hang, then fly into the slot
	var flyers: Array = d["flyers"]
	var inf: Array = d["in_flight"]
	var lp: PackedFloat32Array = d["letter_pop"]
	var keep_f: Array = []
	for f in flyers:
		var fd: Dictionary = f
		var l: Label = fd["l"]
		var t: float = fd["t"] + delta
		fd["t"] = t
		var i: int = fd["i"]
		var from: Vector2 = fd["from"]
		var to := _slot_pos(d, sr, i) + Vector2(SLOT, SLOT) * 0.5
		var end_scale := SLOT / l.size.x
		if t < 0.16:
			var k := t / 0.16
			l.scale = Vector2.ONE * lerpf(0.3, 1.25, k)
			l.rotation = lerpf(-0.4, 0.05, k)
			l.position = from - l.size * 0.5
		elif t < 0.42:
			var k := (t - 0.16) / 0.26
			l.scale = Vector2.ONE * lerpf(1.25, 1.0, minf(1.0, k * 2.0))
			l.rotation = 0.05 * (1.0 - k)
			l.position = from - l.size * 0.5
			l.modulate = Color(1.6, 1.5, 1.2) if blink else Color.WHITE
		elif t < 0.72:
			var k := (t - 0.42) / 0.30
			var e := k * k
			var p := from.lerp(to, e) + Vector2(0, -50.0 * sin(k * PI))
			l.position = p - l.size * 0.5
			l.scale = Vector2.ONE * lerpf(1.0, end_scale * 1.3, e)
			l.rotation = -0.3 * sin(k * PI)
			l.modulate = Color.WHITE
		else:
			l.queue_free()
			inf[i] = false
			lp[i] = 1.0
			continue
		keep_f.append(fd)
	d["flyers"] = keep_f

	# --- letters / BRAWL MODE banner
	var letters: Array = d["letters"]
	var lit: int = w.style_letters
	var show_banner := brawl and keep_f.is_empty()
	for i in letters.size():
		var l: Label = letters[i]
		l.visible = not show_banner
		l.position = _slot_pos(d, sr, i)
		var on := i < lit and not bool(inf[i])
		if brawl:
			on = not bool(inf[i])
		var sb: StyleBoxFlat = l.get_theme_stylebox("normal")
		if on:
			sb.bg_color = gear.darkened(0.15)
			sb.border_color = GOLD
			l.add_theme_color_override("font_color", GOLD if not (lit == 4 and blink) else Color.WHITE)
		else:
			sb.bg_color = Color(0.04, 0.04, 0.1, 0.65)
			sb.border_color = Color(1, 1, 1, 0.25)
			l.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
		var p: float = lp[i]
		if p > 0.0:
			p = maxf(0.0, p - delta * 3.0)
			lp[i] = p
		l.scale = Vector2.ONE * (1.0 + 0.9 * p * p)
		l.modulate = Color(1, 1, 1, 1).lerp(Color(3, 3, 3, 1), p)
	d["letter_pop"] = lp
	var score: Label = d["score"]
	var sc: int = st.get("score")
	score.text = "STYLE %s" % _fmt(sc)
	score.visible = not show_banner
	score.position = Vector2((x0 - 5.0 * SLOT_PITCH - 8.0 - score.size.x) if right else (x0 + 5.0 * SLOT_PITCH + 8.0), top + LETTER_Y)
	var banner: Label = d["banner"]
	banner.visible = show_banner
	if show_banner:
		banner.position = Vector2((x0 - banner.size.x) if right else x0, top + LETTER_Y - 2.0)
		var phase := int(clock * 8.0) % 3
		var fc := [GOLD, Color.WHITE, Color(1.0, 0.45, 0.2)][phase] as Color
		banner.add_theme_color_override("font_color", fc)
		var bsb: StyleBoxFlat = banner.get_theme_stylebox("normal")
		bsb.bg_color = Color(0.6, 0.02, 0.08, 0.85) if blink else gear.darkened(0.3)
		bsb.border_color = fc
		banner.rotation = sin(clock * 14.0) * 0.03

	# --- HYPE bar (fills toward the next letter; BRAWL countdown while in BRAWL MODE)
	var hy := top + HYPE_Y
	var htag: Label = d["htag"]
	var hframe: ColorRect = d["hframe"]
	var hwell: ColorRect = d["hwell"]
	var hfill: ColorRect = d["hfill"]
	var hnext: Label = d["hnext"]
	var bar_u0 := HYPE_LABEL_W + 4.0
	var frac := 0.0
	var fill_col := Color(0.32, 0.62, 0.95)
	if brawl:
		frac = float(st.call("brawl_fraction"))
		fill_col = GOLD if blink else Color(1.0, 0.45, 0.2)
		htag.text = "BRAWL"
		htag.add_theme_color_override("font_color", GOLD if blink else Color.WHITE)
		var left: float = st.get("brawl_left")
		hnext.text = "%.1f" % maxf(0.0, left)
		hnext.add_theme_color_override("font_color", GOLD)
	else:
		var hype: float = w.spirit
		frac = clampf(hype / 100.0, 0.0, 1.0)
		htag.text = "HYPE"
		htag.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
		if frac >= 1.0:
			fill_col = GOLD if blink else Color(1.0, 0.97, 0.85)
		hnext.text = ("> " + LETTERS[lit]) if lit < LETTERS.size() else ""
		hnext.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	htag.position = Vector2((x0 - HYPE_LABEL_W) if right else x0, hy - 4.0)
	var bx := (x0 - bar_u0 - HYPE_BAR_W) if right else (x0 + bar_u0)
	hframe.position = Vector2(bx - 2.0, hy - 2.0)
	hframe.size = Vector2(HYPE_BAR_W + 4.0, HYPE_BAR_H + 4.0)
	hwell.position = Vector2(bx, hy)
	hwell.size = Vector2(HYPE_BAR_W, HYPE_BAR_H)
	var fw := HYPE_BAR_W * frac
	hfill.position = Vector2((bx + HYPE_BAR_W - fw) if right else bx, hy)
	hfill.size = Vector2(fw, HYPE_BAR_H)
	hfill.color = fill_col
	hnext.position = Vector2((bx - 6.0 - hnext.size.x) if right else (bx + HYPE_BAR_W + 6.0), hy - 4.0)

	# --- combo tally
	var combo: Label = d["combo"]
	var sub: Label = d["sub"]
	var cbar: ColorRect = d["cbar"]
	var cframe: ColorRect = d["cframe"]
	var cy := (top + TALLY_Y) if not cpu else (top + CPU_COMBO_Y)
	var cx := (sr.position.x + sr.size.x * 0.5 - combo.size.x * 0.5) if not cpu else ((x0 - combo.size.x) if right else x0)
	combo.position = Vector2(cx, cy)
	sub.position = Vector2(cx, cy + combo.size.y - 2.0)
	var msg_t: float = d["msg_t"]
	var mult: int = w.combo_mult
	var cpts: int = w.combo_points
	var count: int = st.get("combo_count")
	var min_count := 1 if not cpu else 2  # the player's tally shows from the first trick
	if msg_t > 0.0:
		msg_t -= delta
		d["msg_t"] = msg_t
		var a := clampf(msg_t * 3.5, 0.0, 1.0)
		combo.modulate.a = a
		sub.modulate.a = a
		if d["msg_kind"] == "break":
			var sh := 9.0 * clampf(msg_t - 0.4, 0.0, 1.0)
			combo.position += Vector2(sin(clock * 75.0) * sh, cos(clock * 61.0) * sh * 0.4)
		if count >= min_count:
			msg_t = 0.0  # a new combo is already running: show it instead
			d["msg_t"] = 0.0
	if msg_t <= 0.0:
		sub.visible = false
		if count >= min_count:
			var txt := "x%d   %s" % [mult, _fmt(cpts)]
			if combo.text != txt:
				combo.text = txt
				combo.scale = Vector2(1.3, 1.3)
				combo.rotation = 0.0
				combo.add_theme_font_size_override("font_size", 40 if not cpu else 24)
			combo.scale = combo.scale.lerp(Vector2.ONE, clampf(delta * 12.0, 0.0, 1.0))
			var hot := mult >= 5
			combo.add_theme_color_override("font_color", Color.WHITE if not hot else (GOLD if blink else Color.WHITE))
			combo.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.3) if not hot else Color(0.45, 0.02, 0.05))
			combo.visible = true
			combo.modulate.a = 1.0
			var gf: float = st.call("combo_gap_fraction")
			var bw := TALLY_BAR_W if not cpu else 140.0
			var bh := 6.0 if not cpu else 4.0
			var by := cy + combo.size.y + 1.0
			var bx0 := (sr.position.x + sr.size.x * 0.5 - bw * 0.5) if not cpu else ((x0 - bw) if right else x0)
			cframe.visible = true
			cframe.position = Vector2(bx0 - 2.0, by - 2.0)
			cframe.size = Vector2(bw + 4.0, bh + 4.0)
			var gw := bw * gf
			cbar.visible = true
			cbar.size = Vector2(gw, bh)
			# The player's bar drains toward its center; the CPU's toward its outer edge.
			if not cpu:
				cbar.position = Vector2(bx0 + (bw - gw) * 0.5, by)
			else:
				cbar.position = Vector2((x0 - gw) if right else x0, by)
			cbar.color = Color(0.4, 0.9, 1.0, 0.95) if gf > 0.3 or blink else Color(1.0, 0.3, 0.2, 0.95)
		else:
			combo.visible = false
			cbar.visible = false
			cframe.visible = false

	# --- trick popups at the head: rise ~60 px over 0.8 s, then fade; young ones stack upward
	var pops: Array = d["pops"]
	var keep: Array = []
	var min_y := top + 150.0
	for i in pops.size():
		var h: Control = pops[i]
		var age: float = h.get_meta("age")
		age += delta
		h.set_meta("age", age)
		if age >= POP_LIFE:
			h.queue_free()
			continue
		var push: float = h.get_meta("push")
		push = lerpf(push, float(h.get_meta("push_to")), clampf(delta * 16.0, 0.0, 1.0))
		h.set_meta("push", push)
		var rk := clampf(age / POP_RISE_T, 0.0, 1.0)
		var rise := POP_RISE * (1.0 - (1.0 - rk) * (1.0 - rk))
		var anchor: Vector2 = h.get_meta("anchor")
		h.position = anchor - Vector2(0, rise + push)
		var a := 1.0
		if age > 0.08:
			a = 1.0 - clampf((age - (POP_LIFE - 0.32)) / 0.32, 0.0, 1.0)
			a *= clampf((h.position.y - (min_y - 40.0)) / 40.0, 0.0, 1.0)  # fade out under the top HUD
			h.modulate.a = a
		var sup: bool = h.get_meta("super")
		if sup:
			h.modulate = Color(1, 1, 1, h.modulate.a) if blink else Color(1.6, 1.4, 1.0, h.modulate.a)
		keep.append(h)
	d["pops"] = keep


static func _fmt(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

extends CanvasLayer
## STYLE overlay (its own CanvasLayer, layer 2, above the main HUD): per-wrestler column hugging
## its side of the screen, under that wrestler's health bar and clear of the touch controls:
##   B R A W L letters (+ banked style score)  -> flashing BRAWL MODE banner + timer while active
##   combo counter "x3  4,250" with a draining combo-gap bar; "+12,750 BANKED!" / "COMBO BROKEN"
##   trick popups: italic outlined name + points, newest on top, older ones slide down and fade.
## Fed by the signals of scripts/style.gd (one per wrestler). Created by main.gd: setup(main, [p1, p2]).

const COL_W := 380.0           # column width
const EDGE := 16.0             # gap to the safe-area edge
const LETTER_Y := 94.0         # below the main HUD's name plates / bars
const COMBO_Y := 134.0
const POPS_Y := 238.0          # below the main announcer line
const POP_H := 54.0
const POP_LIFE := 1.7
const MAX_POPS := 4
const GOLD := Color(1.0, 0.84, 0.2)
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
		if st == null:
			continue
		cols.append(_build_col(w, st, i == 1))


func _label(size: int, col: Color, outline: Color, outline_px: int) -> Label:
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
	root.add_child(l)
	return l


func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(2)
	b.set_corner_radius_all(4)
	b.skew = Vector2(0.25, 0.0)
	return b


func _build_col(w: Node3D, st: Node, right: bool) -> Dictionary:
	var d := {"w": w, "st": st, "right": right, "pops": [], "msg_t": 0.0, "msg_kind": "",
		"letters": [], "letter_pop": PackedFloat32Array([0, 0, 0, 0, 0]), "brawl": false}
	for i in LETTERS.size():
		var l := _label(26, Color(1, 1, 1, 0.35), Color(0, 0, 0, 0.8), 4)
		l.text = LETTERS[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(36, 36)
		l.pivot_offset = Vector2(18, 18)
		l.add_theme_stylebox_override("normal", _box(Color(0.04, 0.04, 0.1, 0.65), Color(1, 1, 1, 0.25)))
		d["letters"].append(l)
	var score := _label(22, Color(1, 1, 1, 0.9), Color(0, 0, 0, 0.9), 5)
	score.size = Vector2(COL_W - 5 * 40.0 - 8.0, 36)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	d["score"] = score
	var banner := _label(30, GOLD, Color(0.5, 0.0, 0.05), 8)
	banner.text = "BRAWL MODE!"
	banner.size = Vector2(240, 40)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.pivot_offset = Vector2(120, 20)
	banner.add_theme_stylebox_override("normal", _box(Color(0.6, 0.02, 0.08, 0.85), GOLD))
	banner.visible = false
	d["banner"] = banner
	var bbar := ColorRect.new()
	bbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bbar.color = GOLD
	bbar.visible = false
	root.add_child(bbar)
	d["bbar"] = bbar
	var combo := _label(34, Color.WHITE, Color(0.05, 0.05, 0.3), 9)
	combo.size = Vector2(COL_W, 46)
	combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	combo.pivot_offset = Vector2(COL_W if right else 0.0, 23)
	combo.visible = false
	d["combo"] = combo
	var cbar := ColorRect.new()
	cbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbar.color = Color(0.4, 0.9, 1.0, 0.9)
	cbar.visible = false
	root.add_child(cbar)
	d["cbar"] = cbar
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


func _col_x(d: Dictionary, sr: Rect2) -> float:
	var right: bool = d["right"]
	return (sr.end.x - EDGE - COL_W) if right else (sr.position.x + EDGE)


# ---------------------------------------------------------------- events

func _on_popped(text: String, points: int, kind: String, mult: int, d: Dictionary) -> void:
	var right: bool = d["right"]
	var pops: Array = d["pops"]
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(COL_W, POP_H)
	holder.pivot_offset = Vector2(COL_W if right else 0.0, POP_H * 0.5)
	root.add_child(holder)
	var kc: Color = KIND_COLORS.get(kind, Color.WHITE)
	var big := points >= 1000 or kind == "super"
	var nm := _label(36 if big else 30, kc, Color(0.06, 0.02, 0.12), 9 if big else 7)
	nm.reparent(holder)
	nm.text = text
	nm.clip_text = true
	nm.size = Vector2(COL_W, 34)
	nm.position = Vector2.ZERO
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	var pt := _label(22, GOLD, Color(0.3, 0.1, 0.0), 6)
	pt.reparent(holder)
	pt.text = "+%s" % _fmt(points) + ("" if mult < 2 else "   x%d" % mult)
	pt.size = Vector2(COL_W, 22)
	pt.position = Vector2(0, 32)
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	holder.set_meta("age", 0.0)
	holder.set_meta("slot", 0.0)
	holder.set_meta("super", big)
	pops.push_front(holder)
	while pops.size() > MAX_POPS:
		var old: Control = pops.pop_back()
		old.queue_free()
	# slam in from the screen edge
	holder.scale = Vector2(1.5, 1.5)
	holder.modulate.a = 0.0
	var tw := holder.create_tween().set_parallel(true)
	tw.tween_property(holder, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "modulate:a", 1.0, 0.1)


func _on_banked(total: int, mult: int, d: Dictionary) -> void:
	var c: Label = d["combo"]
	c.text = "+%s BANKED!" % _fmt(total) if mult < 2 else "x%d  +%s BANKED!" % [mult, _fmt(total)]
	c.add_theme_color_override("font_color", GOLD)
	c.add_theme_color_override("font_outline_color", Color(0.35, 0.12, 0.0))
	d["msg_t"] = 1.2
	d["msg_kind"] = "bank"
	c.visible = true
	c.modulate.a = 1.0
	c.scale = Vector2(1.45, 1.45)
	c.create_tween().tween_property(c, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_broke(lost: int, d: Dictionary) -> void:
	var c: Label = d["combo"]
	c.text = "COMBO BROKEN  -%s" % _fmt(lost)
	c.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
	c.add_theme_color_override("font_outline_color", Color(0.15, 0.0, 0.0))
	d["msg_t"] = 1.0
	d["msg_kind"] = "break"
	c.visible = true
	c.modulate.a = 1.0
	c.scale = Vector2.ONE


func _on_letter(n: int, d: Dictionary) -> void:
	var lp: PackedFloat32Array = d["letter_pop"]
	if n >= 1 and n <= LETTERS.size():
		lp[n - 1] = 1.0
		d["letter_pop"] = lp


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
	var sr := _safe_rect()
	for d in cols:
		_update_col(d, sr, delta)


func _update_col(d: Dictionary, sr: Rect2, delta: float) -> void:
	var w: Node3D = d["w"]
	var st: Node = d["st"]
	var right: bool = d["right"]
	var x0 := _col_x(d, sr)
	var top := sr.position.y
	var gear: Color = w.gear_color
	var brawl: bool = w.brawl_mode
	var blink := int(clock * 9.0) % 2 == 0

	# --- letters / BRAWL MODE banner
	var letters: Array = d["letters"]
	var lit: int = w.style_letters
	var lp: PackedFloat32Array = d["letter_pop"]
	for i in letters.size():
		var l: Label = letters[i]
		l.visible = not brawl
		var lx := (x0 + COL_W - (5 - i) * 40.0) if right else (x0 + i * 40.0)
		l.position = Vector2(lx, top + LETTER_Y)
		var on := i < lit
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
			p = maxf(0.0, p - delta * 2.5)
			lp[i] = p
		l.scale = Vector2.ONE * (1.0 + 1.2 * p * p)
		l.rotation = -0.5 * p * p
		l.modulate = Color(1, 1, 1, 1).lerp(Color(3, 3, 3, 1), p)
	d["letter_pop"] = lp
	var score: Label = d["score"]
	var sc: int = st.get("score")
	score.text = _fmt(sc) if sc > 0 else ""
	score.visible = not brawl
	score.position = Vector2(x0 if right else x0 + 5 * 40.0 + 8.0, top + LETTER_Y)
	var banner: Label = d["banner"]
	var bbar: ColorRect = d["bbar"]
	banner.visible = brawl
	bbar.visible = brawl
	if brawl:
		var bx := (x0 + COL_W - banner.size.x) if right else x0
		banner.position = Vector2(bx, top + LETTER_Y - 2)
		var phase := int(clock * 8.0) % 3
		var fc := [GOLD, Color.WHITE, Color(1.0, 0.45, 0.2)][phase] as Color
		banner.add_theme_color_override("font_color", fc)
		var bsb: StyleBoxFlat = banner.get_theme_stylebox("normal")
		bsb.bg_color = Color(0.6, 0.02, 0.08, 0.85) if blink else gear.darkened(0.3)
		bsb.border_color = fc
		banner.rotation = sin(clock * 14.0) * 0.03
		var frac: float = st.call("brawl_fraction")
		var bw := banner.size.x * frac
		bbar.size = Vector2(bw, 5)
		bbar.position = Vector2((bx + banner.size.x - bw) if right else bx, top + LETTER_Y + 41)
		bbar.color = fc

	# --- combo counter
	var combo: Label = d["combo"]
	var cbar: ColorRect = d["cbar"]
	combo.position = Vector2(x0, top + COMBO_Y)
	var msg_t: float = d["msg_t"]
	var mult: int = w.combo_mult
	var cpts: int = w.combo_points
	var count: int = st.get("combo_count")
	if msg_t > 0.0:
		msg_t -= delta
		d["msg_t"] = msg_t
		combo.visible = true
		combo.modulate.a = clampf(msg_t * 3.0, 0.0, 1.0)
		if d["msg_kind"] == "break":
			combo.position.x += sin(clock * 70.0) * 6.0 * clampf(msg_t - 0.5, 0.0, 1.0)
		cbar.visible = false
		if count >= 2:
			msg_t = 0.0  # a new combo is already running: show it instead
			d["msg_t"] = 0.0
	if msg_t <= 0.0:
		if count >= 2:
			var txt := "x%d  %s" % [mult, _fmt(cpts)]
			if combo.text != txt:
				combo.text = txt
				combo.scale = Vector2(1.25, 1.25)
			combo.scale = combo.scale.lerp(Vector2.ONE, clampf(delta * 12.0, 0.0, 1.0))
			combo.add_theme_color_override("font_color", Color.WHITE if mult < 5 else (GOLD if blink else Color.WHITE))
			combo.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.3) if mult < 5 else Color(0.45, 0.02, 0.05))
			combo.visible = true
			combo.modulate.a = 1.0
			var gf: float = st.call("combo_gap_fraction")
			var gw := 200.0 * gf
			cbar.visible = true
			cbar.size = Vector2(gw, 4)
			cbar.position = Vector2((x0 + COL_W - gw) if right else x0, top + COMBO_Y + 46)
			cbar.color = Color(0.4, 0.9, 1.0, 0.9) if gf > 0.3 or blink else Color(1.0, 0.3, 0.2, 0.9)
		else:
			combo.visible = false
			cbar.visible = false

	# --- trick popups: newest on top, older slide down and fade
	var pops: Array = d["pops"]
	var keep: Array = []
	for i in pops.size():
		var h: Control = pops[i]
		var age: float = h.get_meta("age")
		age += delta
		h.set_meta("age", age)
		var slot: float = h.get_meta("slot")
		slot = lerpf(slot, float(i), clampf(delta * 14.0, 0.0, 1.0))
		h.set_meta("slot", slot)
		var slide := 0.0
		if age > POP_LIFE:
			var k := clampf((age - POP_LIFE) / 0.3, 0.0, 1.0)
			h.modulate.a = 1.0 - k
			slide = k * 60.0
			if k >= 1.0:
				h.queue_free()
				continue
		elif age > 0.1:
			h.modulate.a = 1.0 - 0.18 * slot
		var sup: bool = h.get_meta("super")
		if sup:
			h.modulate = Color(1, 1, 1, h.modulate.a) if blink else Color(1.6, 1.4, 1.0, h.modulate.a)
		h.position = Vector2(x0 + (slide if right else -slide), top + POPS_Y + slot * POP_H)
		keep.append(h)
	d["pops"] = keep


static func _fmt(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

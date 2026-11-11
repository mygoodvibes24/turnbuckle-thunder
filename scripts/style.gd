extends Node
## STYLE system for one wrestler (added as a child Node by main.gd).
##
## Every move / trick that lands makes the wrestler emit trick(name, points, kind).
## - COMBO: tricks less than COMBO_GAP seconds apart chain; the multiplier is the chain length
##   (x1 .. x8). COMBO_GAP seconds without a trick BANKS the combo (points x multiplier go to the
##   score). Getting hurt (a "break" that comes with a health drop, or being stunned by a
##   reversal) BREAKS a 2+ trick combo and its unbanked points are lost; a lone trick has no
##   multiplier at stake, so it is banked instead. A plain whiff (a "break" with no damage) does
##   not wipe the combo, it just cuts the gap so the chain banks a moment later.
##   Repeating the same trick inside one combo scores less each time.
## - HYPE: style points fill the hype meter, which is the wrestler's spirit (so SPECIAL /
##   finishers keep working). Every time it fills you earn the next letter of B-R-A-W-L.
## - BRAWL MODE: all five letters -> BRAWL_TIME seconds with the meter locked full, double trick
##   points, x1.4 damage (wrestler.take_damage) and is_special_ready() always true.
##   CPU wrestlers run the same logic.
## The HUD (scripts/style_hud.gd) listens to the signals below.

signal popped(text: String, points: int, kind: String, mult: int)  # a trick scored
signal banked(total: int, mult: int)    # a combo of 2+ tricks was cashed in
signal broke(lost: int)                 # a combo of 2+ tricks was lost
signal letter(count: int)               # earned a B-R-A-W-L letter (1..5)
signal brawl_changed(on: bool)

const Wrestler := preload("res://scripts/wrestler.gd")
const COMBO_GAP := 2.5
const MULT_CAP := 8
const BRAWL_TIME := 12.0
const BRAWL_RESET_HYPE := 45.0  # hype left once BRAWL MODE runs out
const HYPE_PER_POINT := 0.012   # hype (spirit) per style point, before the combo bonus
const HYPE_TRICK_CAP := 25.0
const HYPE_PER_BANKED := 0.0025 # bonus hype per banked combo point
const HYPE_BANK_CAP := 20.0
const LETTERS := ["B", "R", "A", "W", "L"]
const HANG_SCALE := 0.6         # "apex hang": brief slow-mo when the player lands a 540+ spin
const HANG_SECS := 0.12         # real seconds
# FLOW (G1): moving fast (boosting / full-speed run / roll / airborne, wrestler.flow_moving_fast())
# holds the combo timer once it is down to COAST_AT, for up to COAST_MAX extra seconds per gap.
const COAST_AT := 1.0
const COAST_MAX := 1.5
# A letter re-arms once hype has dipped to LETTER_REARM (boost burns it, SPECIAL drains to 80):
# hovering at 100 with tiny boosts / nicks doesn't farm letters.
const LETTER_REARM := 90.0
const WHIFF_GAP := 0.6          # a whiff leaves at most this much combo gap

var w: Node3D                  # the wrestler we belong to
var score := 0                 # banked style score this match
var combo_count := 0           # tricks in the current chain
var combo_gap := 0.0           # seconds left before the chain banks
var brawl_left := 0.0          # seconds of BRAWL MODE left
var best_combo := 0
var _repeats := {}             # trick name -> times used in this combo
var _prev_spirit := 0.0
var _prev_health := 0.0        # health at the end of the last tick: tells "hurt" from "whiffed"
var _done := false             # match over: freeze
var coast := 0.0               # FLOW: extra seconds the current gap has been held by moving fast
var coasting := false          # HUD: the combo timer is being held by speed
var _letter_armed := true


func _ready() -> void:
	w = get_parent() as Node3D
	if w == null or not w.has_signal("trick"):
		set_physics_process(false)
		return
	w.connect("trick", _on_trick)
	_prev_spirit = w.spirit
	_prev_health = w.health


func brawl_fraction() -> float:
	return clampf(brawl_left / BRAWL_TIME, 0.0, 1.0)


func combo_gap_fraction() -> float:
	return clampf(combo_gap / COMBO_GAP, 0.0, 1.0)


## "REVERSAL! Arm Drag" -> "REVERSAL ARM DRAG"
static func clean_name(n: String) -> String:
	var t := n.replace("!", " ").strip_edges().to_upper()
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t


func _on_trick(trick_name: String, points: int, kind: String) -> void:
	if _done:
		return
	if kind == "break":
		if _was_hurt():
			_break()
		elif combo_count > 0:
			combo_gap = minf(combo_gap, WHIFF_GAP)  # whiffed: the chain banks shortly
			coast = COAST_MAX  # FLOW: no coasting after a whiff
		return
	if points <= 0:
		return
	var nm := clean_name(trick_name)
	var pts := points
	if w.brawl_mode:
		pts *= 2
		if kind != "super" and not nm.contains("SUPER"):
			nm = "SUPER " + nm
	# Spamming the same move inside one combo is worth less each time.
	var used: int = _repeats.get(nm, 0)
	_repeats[nm] = used + 1
	if used > 0:
		pts = maxi(10, int(float(pts) / pow(2.0, float(mini(used, 3)))))
	combo_count += 1
	combo_gap = COMBO_GAP
	coast = 0.0
	var mult := mini(combo_count, _mult_cap())
	w.combo_mult = mult
	w.combo_points = w.combo_points + pts
	var hype_gain := minf(HYPE_TRICK_CAP, float(pts) * HYPE_PER_POINT * (1.0 + 0.15 * float(mult - 1)))
	w.gain_spirit(hype_gain)
	popped.emit(nm, pts, kind, mult)
	if kind == "air_trick":
		# wrestler.gd plays its own "trick" sting for air tricks; don't double it.
		if not w.is_cpu and _is_big_spin(nm):
			_apex_hang()
		return
	var loud := clampf(float(pts) / 1500.0, 0.15, 1.0)
	w.sfx.emit("trick", loud, w.global_position + Vector3(0, 1.6, 0))


## "540 SPIN" / "SUPER 720 SPIN" (an in-air spin just completed, not the landing call).
static func _is_big_spin(nm: String) -> bool:
	var parts := nm.trim_prefix("SUPER ").split(" ")
	return parts.size() == 2 and parts[1] == "SPIN" and parts[0].is_valid_int() and parts[0].to_int() >= 540


## Tiny hang at the top of a big spin. Only when no other slow-mo / time warp is running, and it
## only restores time_scale if nobody else changed it meanwhile.
func _apex_hang() -> void:
	if not is_equal_approx(Engine.time_scale, 1.0) or not is_inside_tree():
		return
	Engine.time_scale = HANG_SCALE
	var t := get_tree().create_timer(HANG_SECS, true, false, true)
	t.timeout.connect(_end_hang)


func _end_hang() -> void:
	if is_equal_approx(Engine.time_scale, HANG_SCALE):
		Engine.time_scale = 1.0


func _bank() -> void:
	if combo_count <= 0:
		return
	var mult := mini(combo_count, _mult_cap())
	var total: int = w.combo_points * mult
	score += total
	best_combo = maxi(best_combo, total)
	if combo_count >= 2:
		banked.emit(total, mult)
		w.gain_spirit(minf(HYPE_BANK_CAP, float(total) * HYPE_PER_BANKED))
		w.sfx.emit("combo_bank", clampf(float(total) / 5000.0, 0.3, 1.2), w.global_position + Vector3(0, 1.6, 0))
		if total >= 10000:
			w.announce.emit("%s x%d COMBO!" % [_fmt(total), mult])
	_reset_combo()


## A "break" signal is a real combo breaker when we just lost health (wrestler.take_damage
## emits it right after lowering health) or got stunned (a reversed chain link).
func _was_hurt() -> bool:
	var hp: float = w.health
	var st: int = w.state
	return hp < _prev_health - 0.001 or st == Wrestler.S.STUNNED


func _break() -> void:
	_prev_health = w.health
	if combo_count == 1:
		_bank()  # nothing multiplied yet: a landed lone trick still counts
		return
	if combo_count >= 2:
		broke.emit(w.combo_points * mini(combo_count, _mult_cap()))
	_reset_combo()


## A low-skill CPU tops out at x4 (less hype, so fewer CPU finishers / BRAWL MODEs).
func _mult_cap() -> int:
	if w.is_cpu:
		var sk: float = w.ai_skill
		if sk < 0.55:
			return 4
		if sk < 0.75:
			return 6
	return MULT_CAP


func _reset_combo() -> void:
	combo_count = 0
	combo_gap = 0.0
	_repeats.clear()
	coast = 0.0
	coasting = false
	w.combo_mult = 1
	w.combo_points = 0


func _earn_letter() -> void:
	if w.style_letters >= LETTERS.size():
		return
	w.style_letters = w.style_letters + 1
	var n: int = w.style_letters
	letter.emit(n)
	w.sfx.emit("letter", 0.4 + 0.15 * float(n), w.global_position + Vector3(0, 1.6, 0))
	if n >= LETTERS.size():
		_start_brawl()


func _start_brawl() -> void:
	w.brawl_mode = true
	brawl_left = BRAWL_TIME
	w.spirit = 100.0
	w.announce.emit("BRAWL MODE!")
	w.sfx.emit("brawl_mode", 1.0, w.global_position + Vector3(0, 1.4, 0))
	brawl_changed.emit(true)


func _end_brawl() -> void:
	w.brawl_mode = false
	brawl_left = 0.0
	w.style_letters = 0
	w.spirit = minf(w.spirit, BRAWL_RESET_HYPE)
	w.special_timer = 0.0
	brawl_changed.emit(false)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var st: int = w.state
	if st == Wrestler.S.WIN or st == Wrestler.S.LOSE:
		_bank()
		if w.brawl_mode:
			_end_brawl()
		_done = true
		return
	if combo_count > 0:
		coasting = combo_gap <= COAST_AT and coast < COAST_MAX and w.has_method("flow_moving_fast") \
			and bool(w.flow_moving_fast())
		if coasting:
			coast += delta  # FLOW: still moving fast: the combo stays alive
		else:
			combo_gap -= delta
		if combo_gap <= 0.0:
			_bank()
	if w.brawl_mode:
		brawl_left -= delta
		w.spirit = 100.0
		# Keep SPECIAL lit without re-announcing "SUPERCHARGED" after every finisher.
		w.special_timer = maxf(w.special_timer, 1.0)
		if brawl_left <= 0.0:
			_end_brawl()
	else:
		var sp: float = w.spirit
		if sp <= LETTER_REARM:
			_letter_armed = true
		if _letter_armed and _prev_spirit < 100.0 and sp >= 100.0:
			_letter_armed = false
			_earn_letter()
	_prev_spirit = w.spirit
	_prev_health = w.health
	w.hype = w.spirit


static func _fmt(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

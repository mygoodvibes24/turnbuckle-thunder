extends Node
## Global game state, registered as the autoload "Game" (project.godot [autoload]).
## Holds who is fighting: the select screen writes p1_id / p2_id, main.gd reads them in
## _ready, and they survive REMATCH (reload_current_scene) because autoloads persist.
## Defaults keep main.tscn working when it is launched directly.

const Roster := preload("res://scripts/roster.gd")

var p1_id := "tank"
var p2_id := "peligro"   # the CPU opponent
# Where the match is fought: scripts/levels/<level_id>.gd (levels_contract.md). The select
# screen's STAGE step (versus) or the story chapter's match "location" sets it; main.gd falls
# back to the backyard when that level's script does not exist (yet).
var level_id := "backyard"

# ---- STORY MODE (scripts/story.gd writes these before a story match; main.gd reads them).
# story_active is false for QUICK BRAWL, so main.gd behaves exactly as before.
var story_active := false
var story_chapter := -1          # index into StoryData.CHAPTERS of the match being played
var story_cpu_skill := 0.3       # CPU ai_skill for the story match (0..1)
var story_objective := ""        # main objective text shown at the bell
var story_bonus := {}            # {"text", "type", "count", "cash"} (story_schema.md); {} = none
var story_result := {}           # main.gd -> story.gd: {"won": bool, "style": int, "bonus_done": bool}
var story_return := ""           # story.gd: what to show when the hub loads ("result" after a match)


## Called by the title screen: leaving to the title ends any story run.
func reset_story() -> void:
	story_active = false
	story_chapter = -1
	story_cpu_skill = 0.3
	story_objective = ""
	story_bonus = {}
	story_result = {}
	story_return = ""


func roster() -> Array:
	return Roster.ROSTER


func entry(id: String) -> Dictionary:
	if id == CAW_ID and caw_exists():
		return caw_entry()
	return Roster.find(id)


func p1_entry() -> Dictionary:
	return entry(p1_id)


func p2_entry() -> Dictionary:
	return entry(p2_id)


## A writable deep copy of a fighter's look (the roster data is const / read-only).
func look_of(id: String) -> Dictionary:
	var look: Dictionary = entry(id)["look"]
	return look.duplicate(true)


## Display name / short name of any fighter id ("caw" included; Tank's when no CAW is saved).
func name_of(id: String) -> String:
	return str(entry(id)["display_name"])


func short_name_of(id: String) -> String:
	var e := entry(id)
	return str(e.get("short_name", e["display_name"]))


func p1_look() -> Dictionary:
	return look_of(p1_id)


func p2_look() -> Dictionary:
	return look_of(p2_id)


func p1_name() -> String:
	return str(p1_entry()["display_name"])


func p2_name() -> String:
	return str(p2_entry()["display_name"])


## A random fighter id, never `exclude` (when there is anyone else).
func random_id(exclude := "") -> String:
	var ids: Array[String] = []
	for e: Dictionary in Roster.ROSTER:
		if str(e["id"]) != exclude:
			ids.append(str(e["id"]))
	if ids.is_empty():
		return exclude
	return ids[randi() % ids.size()]


# ---------------------------------------------------------------- CREATE-A-WRESTLER (caw_contract.md)
# One created wrestler, saved in user://caw.cfg section "wrestler" (scripts/caw.gd edits it).
# entry("caw") / look_of("caw") / name_of("caw") return it once it is saved.

const CAW_ID := "caw"
const CAW_PATH := "user://caw.cfg"
const CAW_SECTION := "wrestler"
const CAW_FIELDS := ["ring_name", "short_name", "first_name", "pronouns", "look", "stats", "anim_style",
	"signature_set", "signature", "genre", "bio"]
const CAW_DEFAULT_BIO := "Homemade brawler from the block. Built from scratch, tested on the trampoline."

var _caw_loaded := false
var _caw := {}


func _caw_load() -> void:
	if _caw_loaded:
		return
	_caw_loaded = true
	_caw = {}
	var cf := ConfigFile.new()
	if cf.load(CAW_PATH) != OK or not cf.has_section(CAW_SECTION):
		return
	var d := {}
	for k: String in CAW_FIELDS:
		if cf.has_section_key(CAW_SECTION, k):
			d[k] = cf.get_value(CAW_SECTION, k)
	var look_v: Variant = d.get("look", "")
	if look_v is String:
		look_v = str_to_var(str(look_v))
	if not (look_v is Dictionary):
		return   # unreadable save: treat as none
	d["look"] = look_v
	_caw = _caw_clean(d)


## Fills defaults and clamps a CAW record to the contract (names uppercase, stats 1..10).
func _caw_clean(src: Dictionary) -> Dictionary:
	var d := {}
	var ring := str(src.get("ring_name", "")).strip_edges().to_upper().left(14)
	if ring.is_empty():
		ring = "ROOKIE"
	d["ring_name"] = ring
	var short := str(src.get("short_name", "")).strip_edges().to_upper().left(10)
	if short.is_empty():
		short = ring.split(" ", false)[0].left(10)
	d["short_name"] = short
	var first := str(src.get("first_name", "")).strip_edges().to_upper().left(12)
	if first.is_empty():
		first = "THEODORE"
	d["first_name"] = first
	var pro := str(src.get("pronouns", "he"))
	d["pronouns"] = pro if pro in ["he", "she", "they"] else "they"
	var look := {}
	var lv: Variant = src.get("look", {})
	if lv is Dictionary:
		look = (lv as Dictionary).duplicate(true)
	var stats := {}
	var sv: Variant = src.get("stats", {})
	var sd: Dictionary = sv if sv is Dictionary else {}
	for k: String in Roster.STATS:
		stats[k] = clampi(int(sd.get(k, 6)), 1, 10)
	d["stats"] = stats
	d["anim_style"] = str(src.get("anim_style", look.get("anim_style", "swagger")))
	d["signature_set"] = str(src.get("signature_set", look.get("signature_set", "tank")))
	look["anim_style"] = d["anim_style"]
	look["signature_set"] = d["signature_set"]
	d["look"] = look
	d["signature"] = str(src.get("signature", "BACKYARD BOMB"))
	d["genre"] = "CUSTOM"
	d["bio"] = str(src.get("bio", CAW_DEFAULT_BIO))
	return d


func caw_exists() -> bool:
	_caw_load()
	return not _caw.is_empty()


## The saved CAW fields (caw_contract.md), a copy; {} when none is saved.
func caw_data() -> Dictionary:
	_caw_load()
	return _caw.duplicate(true)


## A roster.gd-style entry for the created wrestler (id "caw"); Tank's entry when none is saved.
## Extra keys beyond a roster entry: first_name, pronouns.
func caw_entry() -> Dictionary:
	_caw_load()
	if _caw.is_empty():
		return Roster.find("tank")
	var d := _caw
	var look: Dictionary = d["look"]
	var stats: Dictionary = d["stats"]
	return {
		"id": CAW_ID,
		"display_name": d["ring_name"],
		"short_name": d["short_name"],
		"first_name": d["first_name"],
		"pronouns": d["pronouns"],
		"genre": d["genre"],
		"bio": d["bio"],
		"stats": stats.duplicate(),
		"anim_style": d["anim_style"],
		"signature_set": d["signature_set"],
		"signature": d["signature"],
		"look": look.duplicate(true),
	}


## Saves the created wrestler (fields per caw_contract.md) to user://caw.cfg.
func save_caw(d: Dictionary) -> void:
	var c := _caw_clean(d)
	var cf := ConfigFile.new()
	for k: String in CAW_FIELDS:
		if k == "look":
			cf.set_value(CAW_SECTION, k, var_to_str(c["look"]))
		else:
			cf.set_value(CAW_SECTION, k, c[k])
	var err := cf.save(CAW_PATH)
	if err != OK:
		push_warning("save_caw: could not write %s (error %d)" % [CAW_PATH, err])
	_caw = c
	_caw_loaded = true

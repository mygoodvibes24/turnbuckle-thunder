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
	if id == "caw":
		return caw_entry()
	return Roster.find(id)


# ---- THROWAWAY TEST STUB (never merged): a fake created wrestler for screenshots.
const TEST_LOOK := {
	"anim_style": "swagger", "signature_set": "tank", "body": "female", "face": "punk",
	"gear": Color(0.1, 0.85, 0.95), "skin": Color(0.55, 0.38, 0.27),
	"hair_style": "spikes", "hair_color": Color(0.95, 0.2, 0.55),
	"top_style": "studded_vest", "top_color": Color(0.08, 0.08, 0.1), "vest_color": Color(0.1, 0.8, 0.9),
	"bottom_style": "skinny_ripped", "bottom_color": Color(0.15, 0.15, 0.2),
	"shoes": "combat_boots", "shoe_color": Color(0.1, 0.1, 0.1), "shoe_accent": Color(0.1, 0.85, 0.95),
	"chain": true, "bulk": 1.0,
}


func caw_exists() -> bool:
	return true


func caw_data() -> Dictionary:
	return {"ring_name": "ROXY RUMBLE", "short_name": "ROXY", "first_name": "ROXANNE", "pronouns": "she",
		"look": TEST_LOOK, "stats": {"POWER": 7, "AIR": 5, "FLOW": 6, "GRIT": 7}, "anim_style": "swagger",
		"signature_set": "tank", "genre": "CUSTOM", "bio": "Made in the editor. Hits like rent day."}


func caw_entry() -> Dictionary:
	var d := caw_data()
	return {"id": "caw", "display_name": d["ring_name"], "short_name": d["short_name"], "genre": "CUSTOM",
		"bio": d["bio"], "stats": d["stats"], "anim_style": "swagger", "signature_set": "tank",
		"signature": "RENT DAY DRIVER", "look": TEST_LOOK}


func _ready() -> void:
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true))
		for kv in q.trim_prefix("?").split("&", false):
			var kp := kv.split("=")
			if kp.size() == 2 and kp[0] == "go":
				var target := "res://" + kp[1] + ".tscn"
				get_tree().change_scene_to_file.call_deferred(target)


func p1_entry() -> Dictionary:
	return entry(p1_id)


func p2_entry() -> Dictionary:
	return entry(p2_id)


## A writable deep copy of a fighter's look (the roster data is const / read-only).
func look_of(id: String) -> Dictionary:
	var look: Dictionary = entry(id)["look"]
	return look.duplicate(true)


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

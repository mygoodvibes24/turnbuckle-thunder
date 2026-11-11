extends Node
## Global game state, registered as the autoload "Game" (project.godot [autoload]).
## Holds who is fighting: the select screen writes p1_id / p2_id, main.gd reads them in
## _ready, and they survive REMATCH (reload_current_scene) because autoloads persist.
## Defaults keep main.tscn working when it is launched directly.

const Roster := preload("res://scripts/roster.gd")

var p1_id := "tank"
var p2_id := "peligro"   # the CPU opponent

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
	return Roster.find(id)


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

extends Node
## Global game state, registered as the autoload "Game" (project.godot [autoload]).
## Holds who is fighting: the select screen writes p1_id / p2_id, main.gd reads them in
## _ready, and they survive REMATCH (reload_current_scene) because autoloads persist.
## Defaults keep main.tscn working when it is launched directly.

const Roster := preload("res://scripts/roster.gd")

var p1_id := "tank"
var p2_id := "peligro"   # the CPU opponent


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

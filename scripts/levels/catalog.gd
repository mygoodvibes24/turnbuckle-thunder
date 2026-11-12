extends RefCounted
## Every fight level (levels_contract.md), in stage-select order. The select screen shows a card
## for each; a level whose script (scripts/levels/<id>.gd) does not exist yet shows "COMING SOON".
## When the script exists, its own display_name / description / time_of_day / preview_color
## (set in its _init or as var defaults) win over the fallbacks here.

const LEVELS := [
	{"id": "backyard", "name": "THE BACKYARD", "time": "night", "color": Color(0.24, 0.4, 0.18),
		"desc": "Mom's backyard after dark: lawn, patio, the shed roof, a trampoline and the neighbors watching."},
	{"id": "porch", "name": "THE FRONT PORCH", "time": "day", "color": Color(0.5, 0.42, 0.3),
		"desc": "Mom's front yard and porch steps. Mr. Hollis is watching his hydrangeas. Closely."},
	{"id": "street", "name": "THE BLOCK", "time": "dusk", "color": Color(0.36, 0.36, 0.4),
		"desc": "The cul-de-sac out front: asphalt, parked cars, trash day and the whole block outside."},
	{"id": "store_lot", "name": "CORNER STORE LOT", "time": "night", "color": Color(0.3, 0.32, 0.36),
		"desc": "The corner store parking lot: buzzing sign, shopping carts, a dumpster and Rudy's ice machine."},
	{"id": "rooftop", "name": "THE ROOFTOP", "time": "night", "color": Color(0.22, 0.24, 0.34),
		"desc": "A city rooftop at night: AC units, a water tower ladder and the skyline behind you."},
	{"id": "kitchen", "name": "MOM'S KITCHEN", "time": "day", "color": Color(0.62, 0.5, 0.34),
		"desc": "Indoors, tight and breakable: the kitchen table, the fridge, the couch. Mom will find out."},
]


## The catalog entry for id ({} if unknown).
static func find(id: String) -> Dictionary:
	for e: Dictionary in LEVELS:
		if str(e["id"]) == id:
			return e
	return {}


static func script_path(id: String) -> String:
	return "res://scripts/levels/" + id + ".gd"


static func available(id: String) -> bool:
	return ResourceLoader.exists(script_path(id))

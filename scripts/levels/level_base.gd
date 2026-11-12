extends Node3D
## Base class for a fight level (levels_contract.md). One file per level in scripts/levels/<id>.gd:
##     extends "res://scripts/levels/level_base.gd"
## main.gd instantiates the level (script .new()), adds it as its child at the origin (so level-local
## == ring_root-local == world, ground y 0), then calls build(main) ONCE, copies the fields below
## into its own members (yard_bounds, perches, obstacles, ...) and finally calls
## setup_environment(main.env). The select screen also instantiates levels (WITHOUT build) to read
## display_name / description / time_of_day / preview_color, so set those as var defaults or in
## _init(), never in build(), and keep _init() cheap.
##
## Scenery: use main's merged-geometry helpers (main._bx / _sbox / _cy / _scyl / _beam / _tri on
## main._st(key)) and call main._flush_batches() once at the end of build(); see the helper list in
## scripts/levels/backyard.gd's header. Nodes you create yourself (lights, Label3D, MultiMesh)
## go under the level: add_child(node).

# ---- shown on the stage-select card (read without build())
var display_name := "LEVEL"
var description := ""
var time_of_day := "night"          # "day" / "dusk" / "night"
var preview_color := Color(0.3, 0.42, 0.22)

# ---- gameplay (fill these in build())
## Fighting area in ring_root-local XZ: Rect2(x, z, width, depth). Wrestlers are clamped to it,
## running into its edge = rebound "off the fence / wall"; items stay inside it.
var yard_bounds := Rect2(-7.0, -5.0, 14.0, 10.0)
## Climbable perches: {"pos": Vector3 (top, where the wrestler stands), "approach": Vector3 (ground
## point to climb from), "height": float, "kind": String ("table", "pallets", "porch", "car",
## "trampoline" = extra air, "roof" = biggest dive, ...), "name": String, "footprint": Dictionary}.
## Use add_perch().
var perches: Array = []
## Solid footprints of the other big props (bodies are pushed out, whips into them = prop crash).
## Use footprint(): {"center": Vector2(x, z), "half": Vector2(hx, hz), "radius" (> 0 = round),
## "label", "trick", "points", "sfx" ("wood_hit" / "metal_hit" / "thud")}.
var obstacles: Array = []
## Ground kinds: [{"rect": Rect2(x, z, w, d), "kind": "concrete" | "grass" | "asphalt" | "wood" |
## "tile" | "gravel"}], first match wins, else default_surface. Hard kinds (concrete / asphalt /
## tile / gravel) slam with the harsh "thud_concrete" sound and grey grit.
var surfaces: Array = []
var default_surface := "grass"
## Clamp for the broadcast camera's target point (XZ), plus the camera offset from that point.
var cam_clamp := Rect2(-5.0, -4.0, 10.0, 7.5)
var cam_height := 2.9               # camera sits this high above the target ...
var cam_back := 5.6                 # ... and this far toward +z (the camera side)
var spawn_p1 := Vector3(-1.8, 0.0, 0.3)
var spawn_p2 := Vector3(1.8, 0.0, -0.3)
## Weapons lying around: {"kind": "chair" | "trash_can" | "plank" | "table", "pos": Vector3,
## "yaw": float}. A table leans folded against something by default (yaw = the direction its top
## faces, atan2(x, z)); add "standing": true to set it up on its legs instead.
var item_spawns: Array = []
## Spectators (main.build_crowd builds one MultiMesh of painted billboards from these):
## Vector3 feet positions, or {"pos": Vector3, "person": "stand" | "sit" | "sit_cup" | "filmer" |
## "flannel" | "hoodie" | "jacket" | "girl" | "cheer", "lit": 0..1 (default 0.55), "bob": float}.
## A seated person's "pos" is where the dangling feet end (~0.53 below the seat).
var crowd_spots: Array = []
## The key light (a SpotLight3D you created): main makes it main.ring_spot and gives it the one
## real shadow map. Leave null and main adds a default overhead key light.
var key_light: SpotLight3D = null

var main = null                     # main.gd, set by build()


## Build the whole level (scenery, lights, perches, items, crowd spots). Call super(m) first.
func build(m: Node) -> void:
	main = m


## Sky / fog / ambient tweaks for this level. env is main's Environment (night yard defaults);
## main.sky_mat (sky ShaderMaterial), main.moon (DirectionalLight3D) and main.post_mat (grade
## shader: contrast, saturation, sepia, bloom_*, vignette...) can be tweaked here as well.
func setup_environment(_env: Environment) -> void:
	pass


## Raw ground kind under p (ring_root-local).
func surface_kind_at(p: Vector3) -> String:
	var q := Vector2(p.x, p.z)
	for s in surfaces:
		var r: Rect2 = s["rect"]
		if r.has_point(q):
			return str(s["kind"])
	return default_surface


func add_perch(perch_name: String, kind: String, pos: Vector3, approach: Vector3, fp := {}) -> void:
	perches.append({"pos": pos, "approach": approach, "height": pos.y, "kind": kind, "name": perch_name,
		"footprint": fp})


func footprint(center: Vector2, half: Vector2, label: String, trick_name: String, points: int, snd: String, radius := 0.0) -> Dictionary:
	return {"center": center, "half": half, "radius": radius, "label": label, "trick": trick_name,
		"points": points, "sfx": snd}

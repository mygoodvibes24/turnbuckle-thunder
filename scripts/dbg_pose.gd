extends Node3D
## THROWAWAY debug scene (never merged): every roster fighter + Mom in a frozen pose.
## Keys: 1 idle, 2 punch, 3 lock-up, 4 taunt, 5 down; Q group A / W group B;
## Z/X/C/V state time 0.1/0.3/0.7/1.6; E camera front / 3-4 / back / close.
const Wrestler := preload("res://scripts/wrestler.gd")
const Roster := preload("res://scripts/roster.gd")
const StoryData := preload("res://scripts/story_data.gd")

var fighters: Array = []
var partners: Array = []
var cam: Camera3D
var pose := 1
var group := 0
var st := 0.3
var view := 0
var focus := -1
var label: Label


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.36, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var floor_m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_m.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.27, 0.25)
	floor_m.material_override = fm
	add_child(floor_m)
	var looks: Array = []
	for r in Roster.ROSTER:
		looks.append([str(r["display_name"]), r["look"]])
	var mom: Dictionary = StoryData.CAST["mom"]
	looks.append(["MOM", mom["look"]])
	var plook: Dictionary = Roster.ROSTER[0]["look"]
	for i in looks.size():
		var w: Node3D = Wrestler.new()
		add_child(w)
		var lk: Dictionary = looks[i][1]
		w.setup(str(looks[i][0]), lk.duplicate(true), false)
		fighters.append(w)
		var p: Node3D = Wrestler.new()
		add_child(p)
		p.setup("PARTNER", plook.duplicate(true), false)
		partners.append(p)
		w.set("opponent", p)
		p.set("opponent", w)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	add_child(cl)
	label = Label.new()
	label.position = Vector2(10, 10)
	label.add_theme_font_size_override("font_size", 28)
	cl.add_child(label)


func _input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_1: pose = 1
			KEY_2: pose = 2
			KEY_3: pose = 3
			KEY_4: pose = 4
			KEY_5: pose = 5
			KEY_Q: group = 0
			KEY_W: group = 1
			KEY_Z: st = 0.1
			KEY_X: st = 0.3
			KEY_C: st = 0.7
			KEY_V: st = 1.6
			KEY_E: view = (view + 1) % 4
			KEY_N: focus = (focus + 2) % 9 - 1


func _process(_dt: float) -> void:
	var names := ["", "IDLE", "PUNCH", "LOCK-UP", "TAUNT", "DOWN"]
	label.text = "%s  t=%.1f  group %d  view %d" % [names[pose], st, group, view]
	var spacing := 2.6 if pose == 3 else 1.4
	for i in fighters.size():
		var w: Node3D = fighters[i]
		var p: Node3D = partners[i]
		var on := int(i / 4) == group
		w.visible = on
		p.visible = on and pose == 3
		var x := (float(i % 4) - 1.5) * spacing
		var fwd := Vector3(0, 0, 1)
		if pose == 3:
			fwd = Vector3(1, 0, 0)
			w.position = Vector3(x - 0.45, 0, 0)
			p.position = Vector3(x + 0.45, 0, 0)
		else:
			w.position = Vector3(x, 0, 0)
			p.position = Vector3(x, 0, 30)
		w.set("facing", fwd)
		w.rotation.y = atan2(fwd.x, fwd.z)
		if pose == 3:
			p.set("facing", -fwd)
			p.rotation.y = atan2(-fwd.x, -fwd.z)
		else:
			p.set("facing", Vector3(0, 0, -1))
			p.rotation.y = PI
		var s: int = Wrestler.S.IDLE
		match pose:
			2: s = Wrestler.S.PUNCH
			3: s = Wrestler.S.TIEUP_ATK
			4: s = Wrestler.S.TAUNT
			5: s = Wrestler.S.DOWN
		w.set("state", s)
		w.set("state_time", st)
		w.call("_update_pose", 0.05)
		if pose == 3:
			p.set("state", Wrestler.S.TIEUP_DEF)
			p.set("state_time", st)
			p.call("_update_pose", 0.05)
	if focus >= 0:
		group = int(focus / 4)
		var f: Node3D = fighters[focus]
		var c := f.position + (Vector3(0.45, 0, 0) if pose == 3 else Vector3.ZERO)
		if pose == 5:
			cam.position = c + Vector3(0.9, 2.2, 1.6)
			cam.look_at(c + Vector3(0, 0.2, 0))
		elif view == 2:
			cam.position = c + Vector3(-0.6, 1.6, -2.3)
			cam.look_at(c + Vector3(0, 1.2, 0))
		else:
			cam.position = c + Vector3(1.0, 1.6, 2.3)
			cam.look_at(c + Vector3(0, 1.15, 0))
		return
	var span := spacing * 4.0
	var d := span * 0.95 + 1.0
	match view:
		0:
			cam.position = Vector3(0, 1.3, d)
			cam.look_at(Vector3(0, 1.0, 0))
		1:
			cam.position = Vector3(d * 0.6, 1.6, d * 0.8)
			cam.look_at(Vector3(0, 0.9, 0))
		2:
			cam.position = Vector3(0, 1.5, -d)
			cam.look_at(Vector3(0, 1.0, 0))
		3:
			if pose == 5:
				cam.position = Vector3(0, 4.5, d * 0.55)
				cam.look_at(Vector3(0, 0.3, 0))
			else:
				cam.position = Vector3(0, 1.4, d * 0.55)
				cam.look_at(Vector3(0, 1.2, 0))

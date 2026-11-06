extends Node3D
## ItemManager: the hardcore weapons lying around the backyard ring (steel folding chairs,
## a metal trash can, a 2x4 and a folding table). Created by main.gd under ring_root, so
## every position here is local to the ring (mat = local y 0). Built entirely in code with
## low-poly meshes and tiny generated textures. A rematch reloads the scene, so the items
## simply respawn in _ready.
##
## Every item is an `Item` Node3D with `kind`, `damage`, `durability` and `held_by`.
## Wrestlers drive the gameplay (wrestler.gd "# ---- weapons"); this node owns the props:
## where they lie, who holds them, flight arcs, dents and breakage.

## Emitted whenever an item breaks (kind = "chair", "trash_can", "plank" or "table";
## where = world position) so main.gd can throw splinters / debris.
signal broke(kind: String, where: Vector3)

const ITEM_CLAMP := 3.5        # floor items stay inside this (ring clamp is 3.8)
const TABLE_CLAMP := 2.7       # a set-up table (1.8 m long) stays fully inside the ropes
const TABLE_HEIGHT := 0.79     # top surface of a standing table (local y)
const TABLE_LEAN := 0.38       # folded table leaning against the post (radians from vertical)
const FIST_ELBOW := Vector3(0.0, -0.33, 0.02)  # fist position in the elbow_r frame
const FIST_HAND := Vector3(0.0, 0.0, 0.015)     # hand_r sits at the fist (child of elbow_r)


class Item extends Node3D:
	var kind := ""
	var damage := 0.0
	var durability := 1
	var max_durability := 1
	var held_by: Node = null
	## "floor", "held", "flying", "folded" (table leaning), "standing" (table), "broken"
	var mode := "floor"
	var model: Node3D
	var grip_y := 0.0          # model-space height of the hand grip (long axis = model +Y)
	var center_y := 0.0        # model-space height of the middle of the item
	var half_thick := 0.04     # half thickness when lying flat
	var held_pitch := PI / 2 + 0.3
	var lies_flat := true      # false: stands upright on the mat (trash can)
	var dent := Vector3.ONE    # accumulated dent scale
	var dent_roll := 0.0
	var yaw := 0.0
	# flight
	var fly_from := Vector3.ZERO
	var fly_to := Vector3.ZERO
	var fly_t := 0.0
	var fly_time := 0.5
	var fly_height := 1.0
	var fly_spin := 8.0
	var settle_t := -1.0
	# table parts
	var legs: Node3D
	var folded_legs: Node3D
	var lid: Node3D


var items: Array = []
var debris_root: Node3D
var last_flight_time := 0.5    # flight time of the most recent throw_item (for hit timing)

var _mats := {}


func _ready() -> void:
	debris_root = Node3D.new()
	add_child(debris_root)
	_spawn_all()


# ---------------------------------------------------------------- public API

## A free item (not held, not flying, not a table) within max_dist of local_pos, or null.
func nearest_item(local_pos: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for it: Item in items:
		if not is_instance_valid(it) or it.kind == "table" or it.mode != "floor" or it.held_by != null:
			continue
		var d := _flat_dist(it.position, local_pos)
		if d <= best_d:
			best_d = d
			best = it
	return best


## A folded (leaning) table within max_dist of local_pos, or null.
func nearest_folded_table(local_pos: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for it: Item in items:
		if not is_instance_valid(it) or it.kind != "table" or it.mode != "folded":
			continue
		var d := _flat_dist(it.position, local_pos)
		if d <= best_d:
			best_d = d
			best = it
	return best


## A set-up (standing) table near local_pos, or null. Distance is measured to the table's
## long centre line (not just its middle), so anywhere along a 1.8 m table counts.
func table_under(local_pos: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for it: Item in items:
		if not is_instance_valid(it) or it.kind != "table" or it.mode != "standing":
			continue
		var ax := it.basis.x
		ax.y = 0.0
		ax = ax.normalized()
		var rel := local_pos - it.position
		rel.y = 0.0
		var along := clampf(rel.dot(ax), -0.6, 0.6)
		var d := (rel - ax * along).length()
		if d <= best_d:
			best_d = d
			best = it
	return best


## Attaches the item to the holder's right hand (holder.hand_r if it exists, else elbow_r).
func pick_up(item: Node3D, holder: Node3D) -> void:
	var it := item as Item
	if it == null or not is_instance_valid(it) or it.kind == "table":
		return
	var hand: Node3D = null
	var fist := FIST_ELBOW
	if "hand_r" in holder:
		var h: Node3D = holder.get("hand_r")
		if h != null:
			hand = h
			fist = FIST_HAND
	if hand == null:
		var e: Node3D = holder.get("elbow_r")
		hand = e
	if hand == null:
		return
	it.reparent(hand, false)
	it.held_by = holder
	it.mode = "held"
	it.settle_t = -1.0
	it.transform = Transform3D.IDENTITY
	var hb := Basis(Vector3.RIGHT, it.held_pitch)
	# Where the right fist holds it (model space). The wrestler aims the prop through the
	# wrist and puts the left hand on the mirrored point (wrestler.gd _w_grip_left).
	var grip := Vector3(0.0, it.grip_y, 0.0)
	match it.kind:
		"chair":
			grip = Vector3(0.2, 0.15, 0.0)   # one back leg; the left hand takes the other
		"trash_can":
			grip = Vector3(0.3, 0.6, 0.0)    # by the rim; the left hand on the far side
	_set_model(it, hb, fist - hb * grip)


## Drops the item on the mat at local_pos (lying flat, a little random yaw).
func drop(item: Node3D, local_pos: Vector3) -> void:
	var it := item as Item
	if it == null or not is_instance_valid(it):
		return
	if it.get_parent() != self:
		var keep_yaw := it.global_basis.get_euler().y - global_basis.get_euler().y
		it.reparent(self, false)
		it.yaw = keep_yaw
	it.held_by = null
	_lay_on_floor(it, local_pos, it.yaw + randf_range(-0.6, 0.6))
	it.settle_t = 0.0


## Throws the item from `from` to `to` (both ring-local) along a spinning arc; it lands
## and settles on the mat. Emits nothing: the thrower decides whether it hit someone
## (last_flight_time says when it arrives).
func throw_item(item: Node3D, from: Vector3, to: Vector3) -> void:
	var it := item as Item
	if it == null or not is_instance_valid(it):
		return
	if it.get_parent() != self:
		it.reparent(self, false)
	it.held_by = null
	it.mode = "flying"
	var dest := Vector3(clampf(to.x, -ITEM_CLAMP, ITEM_CLAMP), 0.0, clampf(to.z, -ITEM_CLAMP, ITEM_CLAMP))
	var dist := _flat_dist(from, dest)
	it.fly_from = from
	it.fly_to = dest
	it.fly_t = 0.0
	it.fly_time = clampf(dist / 9.0, 0.25, 0.8)
	it.fly_height = 0.5 + dist * 0.12
	it.fly_spin = randf_range(7.0, 11.0) * (1.0 if randf() < 0.5 else -1.0)
	var d := dest - from
	it.yaw = atan2(d.x, d.z) if Vector2(d.x, d.z).length() > 0.01 else randf() * TAU
	last_flight_time = it.fly_time
	# Spin around the middle of the item while flying.
	_set_model(it, _floor_basis(it), -(_floor_basis(it) * Vector3(0.0, it.center_y, 0.0)))
	it.transform = Transform3D(Basis(Vector3.UP, it.yaw), from)


## One hit's worth of wear. Returns true if the item broke (it is then gone: the holder
## must forget it). Chairs and trash cans dent, everything breaks at 0 durability.
func damage_item(item: Node3D, amount := 1) -> bool:
	var it := item as Item
	if it == null or not is_instance_valid(it) or it.mode == "broken":
		return false
	it.durability -= amount
	if it.durability <= 0:
		_break_item(it)
		return true
	if it.kind == "chair" or it.kind == "trash_can":
		it.dent *= Vector3(randf_range(1.03, 1.08), randf_range(0.9, 0.96), randf_range(0.95, 1.02))
		it.dent_roll += randf_range(-0.07, 0.07)
		_refresh_model(it)
	return false


## Unfolds a folded table and stands it in the ring at local_pos (long side across `yaw`).
func set_up_table(table: Node3D, local_pos: Vector3, yaw: float) -> void:
	var it := table as Item
	if it == null or not is_instance_valid(it) or it.kind != "table" or it.mode == "broken":
		return
	it.mode = "standing"
	it.yaw = yaw
	it.position = Vector3(clampf(local_pos.x, -TABLE_CLAMP, TABLE_CLAMP), 0.0,
		clampf(local_pos.z, -TABLE_CLAMP, TABLE_CLAMP))
	it.rotation = Vector3(0.0, yaw, 0.0)
	it.legs.visible = true
	it.folded_legs.visible = false
	_set_model(it, Basis.IDENTITY, Vector3(0.0, TABLE_HEIGHT - 0.025, 0.0))
	# Little unfold pop.
	it.model.scale = Vector3(1.0, 0.2, 1.0)
	var tw := create_tween()
	tw.tween_property(it.model, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Smashes a table (standing or folded) into 2-4 tilted plank pieces and emits broke().
func break_table(table: Node3D) -> void:
	var it := table as Item
	if it == null or not is_instance_valid(it) or it.kind != "table" or it.mode == "broken":
		return
	var c := it.position
	var ax := it.basis.x
	ax.y = 0.0
	ax = ax.normalized() if ax.length() > 0.01 else Vector3.RIGHT
	var across := Vector3(ax.z, 0.0, -ax.x)
	var n := randi_range(2, 4)
	var wood: Material = _mat("table_top")
	var metal: Material = _mat("metal")
	for i in n:
		var piece := Node3D.new()
		debris_root.add_child(piece)
		var u := (float(i) + 0.5) / float(n) - 0.5
		var p := c + ax * (u * 1.6 + randf_range(-0.15, 0.15)) + across * randf_range(-0.45, 0.45)
		piece.position = _clamp_floor(p, ITEM_CLAMP)
		piece.rotation = Vector3(randf_range(-0.35, 0.35), it.yaw + randf_range(-0.7, 0.7), randf_range(-0.35, 0.35))
		var length := 1.8 / float(n) * randf_range(0.8, 1.2)
		_box(piece, Vector3(length, 0.05, randf_range(0.3, 0.7)), Vector3(0.0, 0.06, 0.0), wood)
	# The bent legs end up on the mat too.
	for i in 2:
		var leg := Node3D.new()
		debris_root.add_child(leg)
		leg.position = _clamp_floor(c + ax * (0.7 if i == 0 else -0.7) + across * randf_range(-0.3, 0.3), ITEM_CLAMP)
		leg.rotation = Vector3(PI / 2 + randf_range(-0.2, 0.2), randf() * TAU, 0.0)
		_box(leg, Vector3(0.6, 0.03, 0.03), Vector3(0.0, 0.0, -0.03), metal)
	it.mode = "broken"
	it.visible = false
	broke.emit("table", to_global(c + Vector3(0.0, TABLE_HEIGHT, 0.0)))
	items.erase(it)
	it.queue_free()


# ---------------------------------------------------------------- per-frame

func _process(delta: float) -> void:
	for it: Item in items:
		if not is_instance_valid(it):
			continue
		if it.mode == "flying":
			it.fly_t += delta
			var t := clampf(it.fly_t / it.fly_time, 0.0, 1.0)
			var p := it.fly_from.lerp(it.fly_to, t)
			p.y = lerpf(it.fly_from.y, 0.0, t) + it.fly_height * 4.0 * t * (1.0 - t)
			it.position = p
			it.basis = Basis(Vector3.UP, it.yaw) * Basis(Vector3.RIGHT, it.fly_spin * it.fly_t)
			if t >= 1.0:
				_lay_on_floor(it, it.fly_to, it.yaw + randf_range(-0.5, 0.5))
				it.settle_t = 0.0
		elif it.mode == "floor" and it.settle_t >= 0.0:
			# Small bounce as it settles on the mat.
			it.settle_t += delta
			var s := it.settle_t / 0.28
			if s >= 1.0:
				it.settle_t = -1.0
				it.position.y = 0.0
			else:
				it.position.y = 0.1 * sin(PI * s) * (1.0 - s)


# ---------------------------------------------------------------- internals

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clamp_floor(p: Vector3, lim: float) -> Vector3:
	return Vector3(clampf(p.x, -lim, lim), 0.0, clampf(p.z, -lim, lim))


func _floor_basis(it: Item) -> Basis:
	if it.lies_flat:
		return Basis(Vector3.RIGHT, -PI / 2)  # long axis (+Y) along -Z, thin axis up
	return Basis.IDENTITY


func _set_model(it: Item, b: Basis, p: Vector3) -> void:
	it.model.set_meta("base_basis", b)
	it.model.set_meta("base_pos", p)
	_refresh_model(it)


func _refresh_model(it: Item) -> void:
	var b: Basis = it.model.get_meta("base_basis", Basis.IDENTITY)
	var p: Vector3 = it.model.get_meta("base_pos", Vector3.ZERO)
	var dented := b * Basis(Vector3.FORWARD, it.dent_roll) * Basis.from_scale(it.dent)
	it.model.transform = Transform3D(dented, p)


func _lay_on_floor(it: Item, local_pos: Vector3, yaw: float) -> void:
	it.mode = "floor"
	it.yaw = yaw
	it.transform = Transform3D(Basis(Vector3.UP, yaw), _clamp_floor(local_pos, ITEM_CLAMP))
	var fb := _floor_basis(it)
	if it.lies_flat:
		_set_model(it, fb, -(fb * Vector3(0.0, it.center_y, 0.0)) + Vector3(0.0, it.half_thick, 0.0))
	else:
		_set_model(it, fb, Vector3.ZERO)


func _break_item(it: Item) -> void:
	var where := it.model.global_position
	var lp := to_local(where)
	lp.y = 0.0
	var at := _clamp_floor(lp, ITEM_CLAMP)
	match it.kind:
		"chair":
			var metal: Material = _mat("metal")
			for i in 4:
				var bar := Node3D.new()
				debris_root.add_child(bar)
				bar.position = _clamp_floor(at + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)), ITEM_CLAMP)
				bar.rotation = Vector3(0.0, randf() * TAU, randf_range(-0.15, 0.15))
				if i < 2:
					_box(bar, Vector3(0.4, 0.02, 0.3), Vector3(0.0, 0.02, 0.0), metal)   # bent panel
				else:
					_box(bar, Vector3(0.03, 0.03, 0.7), Vector3(0.0, 0.02, 0.0), metal)  # bent tube
		"plank":
			var wood: Material = _mat("wood")
			for i in 2:
				var half := Node3D.new()
				debris_root.add_child(half)
				half.position = _clamp_floor(at + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4)), ITEM_CLAMP)
				half.rotation = Vector3(0.0, randf() * TAU, 0.0)
				_box(half, Vector3(0.09, 0.045, 0.6), Vector3(0.0, 0.025, 0.0), wood)
		"trash_can":
			# Crushed flat, lid rolled away.
			var can := Node3D.new()
			debris_root.add_child(can)
			can.position = at
			can.rotation = Vector3(PI / 2, randf() * TAU, 0.0)
			_cyl(can, 0.26, 0.22, 0.6, Vector3(0.0, 0.0, -0.12), _mat("can"), 10, Vector3(1.0, 1.0, 0.45))
			var lid := Node3D.new()
			debris_root.add_child(lid)
			lid.position = _clamp_floor(at + Vector3(randf_range(-0.8, 0.8), 0.0, randf_range(-0.8, 0.8)), ITEM_CLAMP)
			lid.rotation = Vector3(randf_range(-0.2, 0.2), randf() * TAU, 0.0)
			_cyl(lid, 0.265, 0.265, 0.04, Vector3(0.0, 0.02, 0.0), _mat("can"), 10)
	it.mode = "broken"
	it.held_by = null
	broke.emit(it.kind, where)
	items.erase(it)
	it.queue_free()


# ---------------------------------------------------------------- spawning

func _spawn_all() -> void:
	# Two chairs, the trash can and the 2x4 in the other corners / just inside the apron,
	# the folded table leaning against the (+x, +z) ring post.
	_place_floor(_make_chair(), Vector3(-3.3, 0.0, -3.3), PI * 0.25)
	_place_floor(_make_chair(), Vector3(3.3, 0.0, -3.2), -PI * 0.2)
	_place_floor(_make_trash_can(), Vector3(-3.3, 0.0, 3.3), 0.0)
	_place_floor(_make_plank(), Vector3(0.6, 0.0, 3.45), PI / 2)
	var table := _make_table()
	var corner := Vector3(3.62, 0.0, 3.62)
	var to_center := (-corner).normalized()
	table.yaw = atan2(to_center.x, to_center.z)
	table.position = corner
	table.rotation = Vector3(0.0, table.yaw, 0.0)
	table.mode = "folded"
	table.legs.visible = false
	table.folded_legs.visible = true
	# Long axis (model X) up, top face (model +Y) toward the ring centre, leaning back
	# against the post by TABLE_LEAN.
	var upright := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	var lean := Basis(Vector3.RIGHT, -TABLE_LEAN) * upright
	_set_model(table, lean, Vector3(0.0, 0.9 * cos(TABLE_LEAN) + 0.02, -0.9 * sin(TABLE_LEAN)))


func _place_floor(it: Item, pos: Vector3, yaw: float) -> void:
	_lay_on_floor(it, pos, yaw + randf_range(-0.35, 0.35))


func _new_item(kind: String, dmg: float, dur: int) -> Item:
	var it := Item.new()
	it.name = kind.capitalize().replace(" ", "")
	it.kind = kind
	it.damage = dmg
	it.durability = dur
	it.max_durability = dur
	it.model = Node3D.new()
	it.add_child(it.model)
	add_child(it)
	items.append(it)
	return it


## Steel folding chair, folded flat: long axis model +Y (feet at 0), thin along Z.
func _make_chair() -> Item:
	var it := _new_item("chair", 12.0, 4)
	it.grip_y = 0.1
	it.center_y = 0.43
	it.half_thick = 0.05
	var m := it.model
	var metal: Material = _mat("metal")
	var dark: Material = _mat("dark_metal")
	var rubber: Material = _mat("rubber")
	for sx: float in [-0.2, 0.2]:
		_box(m, Vector3(0.03, 0.86, 0.03), Vector3(sx, 0.43, 0.0), dark)            # back legs / frame
		_box(m, Vector3(0.028, 0.56, 0.028), Vector3(sx * 0.9, 0.28, 0.04), dark)   # folded front legs
		_box(m, Vector3(0.035, 0.03, 0.035), Vector3(sx, 0.015, 0.0), rubber)       # feet
		_box(m, Vector3(0.033, 0.03, 0.033), Vector3(sx * 0.9, 0.015, 0.04), rubber)
	_box(m, Vector3(0.42, 0.22, 0.022), Vector3(0.0, 0.72, 0.0), metal)            # backrest
	_box(m, Vector3(0.36, 0.36, 0.022), Vector3(0.0, 0.4, 0.055), metal)           # seat folded up
	_box(m, Vector3(0.4, 0.022, 0.022), Vector3(0.0, 0.12, 0.0), dark)             # cross bar
	return it


## Galvanised trash can with lid, standing upright on the mat.
func _make_trash_can() -> Item:
	var it := _new_item("trash_can", 10.0, 6)
	it.lies_flat = false
	it.grip_y = 0.62
	it.center_y = 0.31
	it.held_pitch = -PI / 2 + 0.3  # held by the rim, the can hangs out in front
	var m := it.model
	var can: Material = _mat("can")
	var dark: Material = _mat("dark_metal")
	_cyl(m, 0.24, 0.21, 0.6, Vector3(0.0, 0.3, 0.0), can, 10)
	_cyl(m, 0.255, 0.255, 0.03, Vector3(0.0, 0.59, 0.0), dark, 10)                 # rim
	_cyl(m, 0.225, 0.225, 0.03, Vector3(0.0, 0.2, 0.0), dark, 10)                  # ribs
	_cyl(m, 0.215, 0.215, 0.03, Vector3(0.0, 0.08, 0.0), dark, 10)
	it.lid = Node3D.new()
	m.add_child(it.lid)
	_cyl(it.lid, 0.265, 0.265, 0.04, Vector3(0.0, 0.625, 0.0), can, 10)
	_box(it.lid, Vector3(0.14, 0.03, 0.03), Vector3(0.0, 0.665, 0.0), dark)       # handle
	for sx: float in [-0.25, 0.25]:
		_box(m, Vector3(0.03, 0.05, 0.08), Vector3(sx, 0.5, 0.0), dark)            # side handles
	return it


## A 2x4: 1.3 m of rough pine.
func _make_plank() -> Item:
	var it := _new_item("plank", 11.0, 3)
	it.grip_y = 0.15
	it.center_y = 0.65
	it.half_thick = 0.0225
	_box(it.model, Vector3(0.09, 1.3, 0.045), Vector3(0.0, 0.65, 0.0), _mat("wood"))
	return it


## Folding table: brown wood top 1.8 x 0.75 centred on the model origin, metal legs below.
func _make_table() -> Item:
	var it := _new_item("table", 12.0, 1)
	var m := it.model
	var top: Material = _mat("table_top")
	var metal: Material = _mat("dark_metal")
	_box(m, Vector3(1.8, 0.05, 0.75), Vector3.ZERO, top)
	_box(m, Vector3(1.8, 0.04, 0.03), Vector3(0.0, -0.04, 0.36), metal)   # apron rails
	_box(m, Vector3(1.8, 0.04, 0.03), Vector3(0.0, -0.04, -0.36), metal)
	it.legs = Node3D.new()
	m.add_child(it.legs)
	for sx: float in [-0.78, 0.78]:
		for sz: float in [-0.3, 0.3]:
			_box(it.legs, Vector3(0.035, 0.74, 0.035), Vector3(sx, -0.39, sz), metal)
		_box(it.legs, Vector3(0.03, 0.03, 0.6), Vector3(sx, -0.62, 0.0), metal)  # foot bar
	it.folded_legs = Node3D.new()
	m.add_child(it.folded_legs)
	for sx: float in [-0.55, 0.55]:
		_box(it.folded_legs, Vector3(0.6, 0.03, 0.6), Vector3(sx, -0.06, 0.0), metal)
	return it


# ---------------------------------------------------------------- meshes & textures

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _add(parent, b, pos, mat)


func _cyl(parent: Node3D, top_r: float, bottom_r: float, h: float, pos: Vector3, mat: Material,
		segs := 10, scl := Vector3.ONE) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	var mi := _add(parent, c, pos, mat)
	mi.scale = scl
	return mi


func _add(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _mat(key: String) -> Material:
	if _mats.has(key):
		var cached: Material = _mats[key]
		return cached
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.roughness = 1.0
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.texture_repeat = true
	match key:
		"metal":
			m.albedo_texture = _noise_tex(16, 16, Color(0.6, 0.62, 0.65), 0.06, Color(0.4, 0.41, 0.43))
		"dark_metal":
			m.albedo_texture = _noise_tex(8, 8, Color(0.36, 0.37, 0.4), 0.05, Color(0.25, 0.25, 0.27))
		"rubber":
			m.albedo_color = Color(0.08, 0.08, 0.08)
		"can":
			m.albedo_texture = _stripe_tex(32, 16, Color(0.66, 0.68, 0.66), Color(0.48, 0.5, 0.49), true)
		"wood":
			m.albedo_texture = _stripe_tex(8, 32, Color(0.78, 0.6, 0.38), Color(0.62, 0.45, 0.26), false)
		"table_top":
			m.albedo_texture = _stripe_tex(32, 16, Color(0.5, 0.33, 0.18), Color(0.4, 0.25, 0.13), false)
	_mats[key] = m
	return m


## Speckled metal with a couple of scuffs.
func _noise_tex(w: int, h: int, base: Color, amt: float, scuff: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v := randf_range(-amt, amt)
			img.set_pixel(x, y, Color(base.r + v, base.g + v, base.b + v))
	for i in 2:
		var sx := randi() % w
		var sy := randi() % h
		for k in 4:
			img.set_pixel((sx + k) % w, (sy + (k >> 1)) % h, scuff)
	return ImageTexture.create_from_image(img)


## Grain stripes (wood) or corrugation (vertical = true, trash can ribs).
func _stripe_tex(w: int, h: int, a: Color, b: Color, vertical: bool) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var phase := randf() * TAU
	for y in h:
		for x in w:
			var c: Color
			if vertical:
				c = a if ((x >> 1) & 1) == 0 else b
			else:
				var g := 0.5 + 0.5 * sin(float(x) * 0.9 + sin(float(y) * 0.4 + phase) * 1.5)
				c = a.lerp(b, g * 0.8 + randf() * 0.15)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

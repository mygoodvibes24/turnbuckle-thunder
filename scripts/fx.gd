extends Node3D
## Cheap pooled hit FX for phones: additive starburst sparks, ground dust puffs and a
## white screen flash. Everything is generated in code; no per-hit allocations.
##
## API (positions are world space):
##   spark(pos, strength)   # starburst that scale-pops and fades (~0.2 s)
##   dust(pos, strength)    # ring of grey puffs drifting outward along the ground
##   flash(strength)        # full-screen white flash (finishers)
##   splinters(pos, strength)      # 10-20 brown wood shards fly out, spin, bounce once, fade
##   debris(pos, strength, color)  # chunkier generic bits (chairs: grey, trash cans, ...)
##   ground_hit(pos, strength, surface)  # "grass": green-brown clumps + dirt puff; "concrete": grey dust
##   body_flash(node)       # ~2-frame additive white overlay on every mesh under node (hit victim)
##   hurt(strength)         # subtle red screen-edge vignette pulse (player took a big hit)
##   trail(node, tint)      # call every frame while a wrestler boosts / flies: pooled additive
##                          # afterimages of its biggest body parts + two hand ribbons
##   speed_lines(amount)    # 0..1 radial streak overlay (player boosting); call every frame

const SPARK_POOL := 12
const SHARD_POOL := 48            # shared by splinters and debris (ring buffer)
const SHARD_LIFE := 1.1
const SHARD_GRAVITY := 14.0
const MAT_Y := 0.0                # world y of the ground (no ring: everything lands on the yard)
const RING_EDGE := 4.4            # beyond this |x| or |z| there is no mat under a shard
var _splinter_colors: Array[Color] = [Color(0.55, 0.38, 0.2), Color(0.68, 0.5, 0.3), Color(0.42, 0.28, 0.15)]
const SPARK_LIFE := 0.2
const SPARK_SCALE := 1.4          # night yard: sparks read bigger than in a lit arena
const BODY_FLASH_TIME := 0.06
const BODY_FLASH_SLOTS := 2       # one per wrestler
const HURT_TIME := 0.32
const HURT_ALPHA := 0.42
var _grass_colors: Array[Color] = [Color(0.22, 0.42, 0.14), Color(0.3, 0.5, 0.18), Color(0.36, 0.26, 0.15), Color(0.28, 0.2, 0.12)]
var _concrete_colors: Array[Color] = [Color(0.62, 0.62, 0.6), Color(0.5, 0.5, 0.49), Color(0.72, 0.71, 0.68)]
const DUST_GREY := Color(0.72, 0.7, 0.68)
const DUST_DIRT := Color(0.42, 0.33, 0.22)
const DUST_CONCRETE := Color(0.8, 0.79, 0.76)
const DUST_SETS := 3
const DUST_PER_SET := 6
const DUST_LIFE := 0.45
const FLASH_TIME := 0.12
const FLASH_ALPHA := 0.35

var _tints: Array[Color] = [Color(1.0, 0.95, 0.75), Color(1.0, 0.8, 0.35), Color(1.0, 1.0, 1.0)]

var _sparks: Array[MeshInstance3D] = []
var _spark_mats: Array[StandardMaterial3D] = []
var _spark_life := PackedFloat32Array()   # remaining seconds; <= 0 means free
var _spark_dur := PackedFloat32Array()
var _spark_size := PackedFloat32Array()
var _spark_tint: Array[Color] = []
var _next_spark := 0

var _dust: Array[MeshInstance3D] = []
var _dust_mats: Array[StandardMaterial3D] = []
var _dust_life := PackedFloat32Array()
var _dust_dur := PackedFloat32Array()
var _dust_size := PackedFloat32Array()
var _dust_vel := PackedVector3Array()
var _dust_col: Array[Color] = []
var _next_dust_set := 0

var _shards: Array[MeshInstance3D] = []
var _shard_mats: Array[StandardMaterial3D] = []
var _shard_life := PackedFloat32Array()
var _shard_dur := PackedFloat32Array()
var _shard_vel := PackedVector3Array()
var _shard_spin := PackedVector3Array()    # axis * radians/s
var _shard_floor := PackedFloat32Array()   # world y it bounces on
var _shard_bounced := PackedByteArray()
var _shard_scale := PackedVector3Array()
var _shard_color: Array[Color] = []
var _next_shard := 0
var _splinter_mesh: BoxMesh
var _chunk_mesh: BoxMesh
var _clump_mesh: BoxMesh

# Body flash: a shared additive overlay set on the victim's meshes for a couple of frames.
var _body_mat: StandardMaterial3D
var _body_node: Array[Node] = []                 # slot -> flashed node (null = free)
var _body_meshes: Array = []                     # slot -> Array[MeshInstance3D] currently overlaid
var _body_life := PackedFloat32Array()
var _mesh_cache := {}                            # node instance id -> Array[MeshInstance3D]

var _hurt_rect: TextureRect
var _hurt_life := 0.0
var _hurt_peak := 0.0

var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_life := 0.0
var _flash_peak := 0.0

# ---- trails (afterimages + hand ribbons) and speed lines
const GHOST_SETS := 8             # pooled afterimages (shared by both wrestlers)
const GHOST_PARTS := 14           # biggest meshes of a wrestler copied into one afterimage
const GHOST_LIFE := 0.26
const GHOST_EVERY := 0.055        # game seconds between afterimages of one wrestler
const GHOST_ALPHA := 0.38
const RIBBON_PTS := 12            # samples per hand ribbon
const RIBBON_EVERY := 0.025
const RIBBON_WIDTH := 0.11
const SPEED_LINES := 26
var _ghost_parts: Array = []      # set -> Array[MeshInstance3D]
var _ghost_mats: Array[StandardMaterial3D] = []
var _ghost_life := PackedFloat32Array()
var _ghost_tint: Array[Color] = []
var _next_ghost := 0
var _part_cache := {}             # node id -> Array[MeshInstance3D] (biggest parts first)
var _trails := {}                 # node id -> trail state (see trail())
var _ribbon_mesh: ImmediateMesh
var _ribbon_mi: MeshInstance3D
var _ribbon_mat: StandardMaterial3D
var _clock := 0.0
var _lines_layer: CanvasLayer
var _lines_ctl: Control
var _lines_amount := 0.0          # requested this frame (reset after each update)
var _lines_shown := 0.0
var _lines_seed := PackedFloat32Array()   # per streak: angle, length, phase


func _ready() -> void:
	var star := _make_star_texture()
	var puff := _make_puff_texture()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)

	for i in SPARK_POOL:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.no_depth_test = true
		m.albedo_texture = star
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.render_priority = 2
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_sparks.append(mi)
		_spark_mats.append(m)
		_spark_life.append(0.0)
		_spark_dur.append(SPARK_LIFE)
		_spark_size.append(0.5)
		_spark_tint.append(Color.WHITE)

	for i in DUST_SETS * DUST_PER_SET:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_texture = puff
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.render_priority = 1
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_dust.append(mi)
		_dust_mats.append(m)
		_dust_life.append(0.0)
		_dust_dur.append(DUST_LIFE)
		_dust_size.append(0.4)
		_dust_vel.append(Vector3.ZERO)
		_dust_col.append(DUST_GREY)

	_splinter_mesh = BoxMesh.new()
	_splinter_mesh.size = Vector3(0.035, 0.025, 0.2)
	_chunk_mesh = BoxMesh.new()
	_chunk_mesh.size = Vector3(0.09, 0.05, 0.12)
	_clump_mesh = BoxMesh.new()
	_clump_mesh.size = Vector3(0.06, 0.04, 0.06)
	for i in SHARD_POOL:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.9
		var mi := MeshInstance3D.new()
		mi.mesh = _splinter_mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_shards.append(mi)
		_shard_mats.append(m)
		_shard_life.append(0.0)
		_shard_dur.append(SHARD_LIFE)
		_shard_vel.append(Vector3.ZERO)
		_shard_spin.append(Vector3.ZERO)
		_shard_floor.append(0.0)
		_shard_bounced.append(0)
		_shard_scale.append(Vector3.ONE)
		_shard_color.append(Color.WHITE)

	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 5
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.visible = false
	_flash_layer.add_child(_flash_rect)

	_build_trails()

	_body_mat = StandardMaterial3D.new()
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_body_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_body_mat.albedo_color = Color(1, 1, 1, 0.6)
	for i in BODY_FLASH_SLOTS:
		_body_node.append(null)
		_body_meshes.append([])
		_body_life.append(0.0)

	# Damage vignette: below the HUD (layer 1) but above the low-res 3D view (layer -1).
	var hurt_layer := CanvasLayer.new()
	hurt_layer.layer = 0
	add_child(hurt_layer)
	_hurt_rect = TextureRect.new()
	_hurt_rect.texture = _make_vignette_texture()
	_hurt_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hurt_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt_rect.modulate = Color(1, 1, 1, 0)
	_hurt_rect.visible = false
	hurt_layer.add_child(_hurt_rect)


# ---------------------------------------------------------------- public API

func spark(pos: Vector3, strength: float) -> void:
	var s: float = clampf(strength, 0.1, 1.5)
	var i: int = _next_spark
	_next_spark = (_next_spark + 1) % SPARK_POOL
	var mi: MeshInstance3D = _sparks[i]
	mi.global_position = pos
	_spark_dur[i] = SPARK_LIFE + 0.05 * s
	_spark_life[i] = _spark_dur[i]
	_spark_size[i] = (0.35 + 0.55 * s) * SPARK_SCALE
	_spark_tint[i] = _tints[randi() % _tints.size()]
	mi.scale = Vector3.ONE * (_spark_size[i] * 0.4)
	_spark_mats[i].albedo_color = _spark_tint[i]
	mi.visible = true
	# Big hits get a second, smaller offset burst for a crunchier look.
	if s >= 0.6:
		var j: int = _next_spark
		_next_spark = (_next_spark + 1) % SPARK_POOL
		var mj: MeshInstance3D = _sparks[j]
		mj.global_position = pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.14, 0.2), randf_range(-0.14, 0.14))
		_spark_dur[j] = SPARK_LIFE * 0.8
		_spark_life[j] = _spark_dur[j]
		_spark_size[j] = _spark_size[i] * 0.55
		_spark_tint[j] = Color(1.0, 1.0, 1.0)
		mj.scale = Vector3.ONE * (_spark_size[j] * 0.4)
		_spark_mats[j].albedo_color = _spark_tint[j]
		mj.visible = true


func dust(pos: Vector3, strength: float, color := DUST_GREY) -> void:
	var s: float = clampf(strength, 0.1, 1.5)
	var base: int = _next_dust_set * DUST_PER_SET
	_next_dust_set = (_next_dust_set + 1) % DUST_SETS
	var a0: float = randf() * TAU
	for k in DUST_PER_SET:
		var i: int = base + k
		var ang: float = a0 + TAU * float(k) / float(DUST_PER_SET) + randf_range(-0.3, 0.3)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var mi: MeshInstance3D = _dust[i]
		mi.global_position = pos + dir * 0.2 + Vector3(0, 0.12, 0)
		_dust_vel[i] = dir * (0.8 + 1.3 * s) * randf_range(0.8, 1.2) + Vector3(0, 0.25 + 0.3 * s, 0)
		_dust_dur[i] = DUST_LIFE * (0.8 + 0.4 * s) * randf_range(0.85, 1.15)
		_dust_life[i] = _dust_dur[i]
		_dust_size[i] = (0.3 + 0.35 * s) * randf_range(0.8, 1.2)
		mi.scale = Vector3.ONE * (_dust_size[i] * 0.6)
		_dust_col[i] = color
		_dust_mats[i].albedo_color = Color(color.r, color.g, color.b, 0.0)
		mi.visible = true


func splinters(pos: Vector3, strength: float) -> void:
	var s: float = clampf(strength, 0.1, 1.5)
	var count: int = clampi(int(10.0 + 7.0 * s), 10, 20)
	for k in count:
		var c: Color = _splinter_colors[randi() % _splinter_colors.size()]
		var sc := Vector3(randf_range(0.6, 1.3), randf_range(0.7, 1.2), randf_range(0.5, 1.6))
		_spawn_shard(pos, s, c, _splinter_mesh, sc, 1.0)


func debris(pos: Vector3, strength: float, color: Color) -> void:
	var s: float = clampf(strength, 0.1, 1.5)
	var count: int = clampi(int(5.0 + 6.0 * s), 5, 14)
	for k in count:
		var v: float = randf_range(0.8, 1.15)
		var c := Color(color.r * v, color.g * v, color.b * v, 1.0)
		var sc := Vector3(randf_range(0.5, 1.4), randf_range(0.5, 1.2), randf_range(0.5, 1.4))
		_spawn_shard(pos, s, c, _chunk_mesh, sc, 0.8)


func ground_hit(pos: Vector3, strength: float, surface: String) -> void:
	var s: float = clampf(strength, 0.1, 1.5)
	var p := Vector3(pos.x, MAT_Y + 0.02, pos.z)
	if surface == "concrete":
		dust(p, maxf(s, 0.6), DUST_CONCRETE)
		var n: int = clampi(int(3.0 + 5.0 * s), 3, 9)
		for k in n:
			var c: Color = _concrete_colors[randi() % _concrete_colors.size()]
			_spawn_shard(p, s, c, _clump_mesh, Vector3.ONE * randf_range(0.4, 0.9), 0.55)
	else:
		dust(p, s * 0.8, DUST_DIRT)
		var n: int = clampi(int(6.0 + 8.0 * s), 6, 16)
		for k in n:
			var c: Color = _grass_colors[randi() % _grass_colors.size()]
			var sc := Vector3(randf_range(0.6, 1.3), randf_range(0.6, 1.6), randf_range(0.6, 1.3))
			_spawn_shard(p, s, c, _clump_mesh, sc, 0.65)


func body_flash(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var slot := -1
	for i in BODY_FLASH_SLOTS:
		if _body_node[i] == node:
			slot = i   # already flashing: just restart the timer
			break
	if slot < 0:
		for i in BODY_FLASH_SLOTS:
			if _body_life[i] <= 0.0:
				slot = i
				break
	if slot < 0:
		slot = 0
		_end_body_flash(0)
	_body_life[slot] = BODY_FLASH_TIME
	if _body_node[slot] == node:
		return
	var meshes: Array = _meshes_of(node)
	for mi in meshes:
		if is_instance_valid(mi) and mi.material_overlay == null:
			mi.material_overlay = _body_mat
	_body_node[slot] = node
	_body_meshes[slot] = meshes


func hurt(strength: float) -> void:
	var peak: float = clampf(HURT_ALPHA * strength, 0.0, 0.55)
	if peak <= 0.0:
		return
	_hurt_peak = maxf(peak, _hurt_peak if _hurt_life > 0.0 else 0.0)
	_hurt_life = HURT_TIME
	_hurt_rect.modulate = Color(1, 1, 1, _hurt_peak)
	_hurt_rect.visible = true


func _meshes_of(node: Node) -> Array:
	var id: int = node.get_instance_id()
	var cached: Array = _mesh_cache.get(id, [])
	var ok: bool = not cached.is_empty()
	for mi in cached:
		if not is_instance_valid(mi) or not mi.is_inside_tree():
			ok = false
			break
	if ok:
		return cached
	var out: Array = []
	_collect_meshes(node, out)
	_mesh_cache[id] = out
	return out


func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var cm: Mesh = (c as MeshInstance3D).mesh
			# skip the flat blob shadow on the ground
			if not (cm is CylinderMesh and (cm as CylinderMesh).height <= 0.02):
				out.append(c)
		_collect_meshes(c, out)


func _end_body_flash(slot: int) -> void:
	for mi in _body_meshes[slot]:
		if is_instance_valid(mi) and mi.material_overlay == _body_mat:
			mi.material_overlay = null
	_body_node[slot] = null
	_body_meshes[slot] = []
	_body_life[slot] = 0.0


func _spawn_shard(pos: Vector3, s: float, c: Color, mesh: Mesh, sc: Vector3, speed_k: float) -> void:
	var i: int = _next_shard
	_next_shard = (_next_shard + 1) % SHARD_POOL
	var mi: MeshInstance3D = _shards[i]
	mi.mesh = mesh
	var ang: float = randf() * TAU
	var out: float = (1.5 + 2.5 * s) * randf_range(0.5, 1.2) * speed_k
	var p: Vector3 = pos + Vector3(randf_range(-0.15, 0.15), randf_range(0.0, 0.1), randf_range(-0.15, 0.15))
	mi.global_position = p
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	_shard_vel[i] = Vector3(cos(ang) * out, (2.0 + 3.0 * s) * randf_range(0.6, 1.2) * speed_k, sin(ang) * out)
	var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	if axis.length_squared() < 0.01:
		axis = Vector3.UP
	_shard_spin[i] = axis.normalized() * randf_range(8.0, 20.0)
	_shard_floor[i] = MAT_Y if p.y >= MAT_Y else 0.0
	_shard_bounced[i] = 0
	_shard_dur[i] = SHARD_LIFE * randf_range(0.8, 1.2)
	_shard_life[i] = _shard_dur[i]
	_shard_scale[i] = sc
	_shard_color[i] = c
	mi.scale = sc
	_shard_mats[i].albedo_color = c
	mi.visible = true


func flash(strength: float) -> void:
	var peak: float = clampf(FLASH_ALPHA * strength, 0.0, 0.6)
	if peak <= 0.0:
		return
	_flash_peak = maxf(peak, _flash_peak if _flash_life > 0.0 else 0.0)
	_flash_life = FLASH_TIME
	_flash_rect.color = Color(1, 1, 1, _flash_peak)
	_flash_rect.visible = true


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	for i in SPARK_POOL:
		var life: float = _spark_life[i]
		if life <= 0.0:
			continue
		life -= delta
		_spark_life[i] = life
		var mi: MeshInstance3D = _sparks[i]
		if life <= 0.0:
			mi.visible = false
			continue
		var k: float = 1.0 - life / _spark_dur[i]           # 0 -> 1 over the lifetime
		var grow: float = 1.0 - pow(1.0 - minf(k * 4.0, 1.0), 3.0)  # fast ease-out pop
		var sc: float = _spark_size[i] * (0.4 + 0.9 * grow) * (1.0 - 0.35 * k)
		mi.scale = Vector3(sc, sc, sc)
		var a: float = (1.0 - k) * (1.0 - k)
		var t: Color = _spark_tint[i]
		_spark_mats[i].albedo_color = Color(t.r, t.g, t.b, a)

	for i in _dust.size():
		var life: float = _dust_life[i]
		if life <= 0.0:
			continue
		life -= delta
		_dust_life[i] = life
		var mi: MeshInstance3D = _dust[i]
		if life <= 0.0:
			mi.visible = false
			continue
		var k: float = 1.0 - life / _dust_dur[i]
		var v: Vector3 = _dust_vel[i]
		mi.global_position += v * delta
		_dust_vel[i] = v * maxf(0.0, 1.0 - delta * 5.0)
		var sc: float = _dust_size[i] * (0.6 + 0.9 * k)
		mi.scale = Vector3(sc, sc, sc)
		var a: float = 0.55 * minf(k * 6.0, 1.0) * (1.0 - k)
		var dc: Color = _dust_col[i]
		_dust_mats[i].albedo_color = Color(dc.r, dc.g, dc.b, a)

	for i in SHARD_POOL:
		var life: float = _shard_life[i]
		if life <= 0.0:
			continue
		life -= delta
		_shard_life[i] = life
		var mi: MeshInstance3D = _shards[i]
		if life <= 0.0:
			mi.visible = false
			continue
		var v: Vector3 = _shard_vel[i]
		v.y -= SHARD_GRAVITY * delta
		var p: Vector3 = mi.global_position + v * delta
		var fl: float = _shard_floor[i]
		if fl > 0.0 and (absf(p.x) > RING_EDGE or absf(p.z) > RING_EDGE):
			fl = 0.0 # flew off the ring: fall to the yard
			_shard_floor[i] = 0.0
		var rest_y: float = fl + 0.015
		if p.y < rest_y:
			p.y = rest_y
			if _shard_bounced[i] == 0 and v.y < -1.0:
				_shard_bounced[i] = 1
				v = Vector3(v.x * 0.45, -v.y * 0.3, v.z * 0.45)
				_shard_spin[i] = _shard_spin[i] * 0.5
			else:
				# settled: slide to a stop, stop spinning
				v = Vector3(v.x * maxf(0.0, 1.0 - delta * 8.0), 0.0, v.z * maxf(0.0, 1.0 - delta * 8.0))
				_shard_spin[i] = _shard_spin[i] * maxf(0.0, 1.0 - delta * 10.0)
		_shard_vel[i] = v
		mi.global_position = p
		var spin: Vector3 = _shard_spin[i]
		var sl: float = spin.length()
		if sl > 0.01:
			mi.rotate(spin / sl, sl * delta)
		var k: float = life / _shard_dur[i]   # 1 -> 0
		var a: float = clampf(k / 0.35, 0.0, 1.0)  # fade over the last 35%
		var c: Color = _shard_color[i]
		_shard_mats[i].albedo_color = Color(c.r, c.g, c.b, a)
		mi.scale = _shard_scale[i] * (0.6 + 0.4 * a)

	if _flash_life > 0.0 or _hurt_life > 0.0 or _body_life[0] > 0.0 or _body_life[1] > 0.0:
		_update_screen_fx(delta / maxf(Engine.time_scale, 0.05))
	_update_trails(delta)
	_update_speed_lines(delta / maxf(Engine.time_scale, 0.05))


func _update_screen_fx(real_dt: float) -> void:
	# Body flash and vignette run on real time too: during hit-stop / slow-mo they must stay snappy.
	for i in BODY_FLASH_SLOTS:
		if _body_life[i] > 0.0:
			_body_life[i] -= real_dt
			if _body_life[i] <= 0.0:
				_end_body_flash(i)
	if _hurt_life > 0.0:
		_hurt_life -= real_dt
		if _hurt_life <= 0.0:
			_hurt_life = 0.0
			_hurt_peak = 0.0
			_hurt_rect.visible = false
		else:
			var hk: float = _hurt_life / HURT_TIME
			_hurt_rect.modulate = Color(1, 1, 1, _hurt_peak * hk * hk)
	if _flash_life > 0.0:
		# The flash runs on real time so slow motion doesn't stretch it into a fade-out.
		_flash_life -= real_dt
		if _flash_life <= 0.0:
			_flash_life = 0.0
			_flash_peak = 0.0
			_flash_rect.visible = false
		else:
			_flash_rect.color = Color(1, 1, 1, _flash_peak * (_flash_life / FLASH_TIME))


# ---------------------------------------------------------------- trails & speed lines

func _build_trails() -> void:
	for i in GHOST_SETS:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_BACK
		m.albedo_color = Color(1, 1, 1, 0)
		m.render_priority = 1
		var parts: Array = []
		for j in GHOST_PARTS:
			var mi := MeshInstance3D.new()
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			add_child(mi)
			parts.append(mi)
		_ghost_parts.append(parts)
		_ghost_mats.append(m)
		_ghost_life.append(0.0)
		_ghost_tint.append(Color.WHITE)
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon_mat = StandardMaterial3D.new()
	_ribbon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ribbon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ribbon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ribbon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ribbon_mat.vertex_color_use_as_albedo = true
	_ribbon_mat.render_priority = 1
	_ribbon_mi = MeshInstance3D.new()
	_ribbon_mi.mesh = _ribbon_mesh
	_ribbon_mi.material_override = _ribbon_mat
	_ribbon_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ribbon_mi.extra_cull_margin = 16384.0   # vertices are world space and move every frame
	add_child(_ribbon_mi)
	# Speed lines: own layer under the HUD (1), above the 3D view (-1) and the hurt vignette.
	_lines_layer = CanvasLayer.new()
	_lines_layer.layer = 0
	add_child(_lines_layer)
	_lines_ctl = Control.new()
	_lines_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines_ctl.visible = false
	_lines_ctl.draw.connect(_draw_speed_lines)
	_lines_layer.add_child(_lines_ctl)
	for i in SPEED_LINES:
		_lines_seed.append(randf() * TAU)
		_lines_seed.append(randf_range(0.18, 0.4))
		_lines_seed.append(randf())


## Keeps a wrestler's trail alive this frame (call every frame while it should show).
func trail(node: Node3D, tint: Color) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id: int = node.get_instance_id()
	var t: Dictionary = _trails.get(id, {})
	if t.is_empty():
		t = {"node": node, "tint": tint, "last_ghost": -1.0, "last_pt": -1.0,
			"pts_l": PackedVector3Array(), "pts_r": PackedVector3Array(), "ages": PackedFloat32Array(), "on": true}
		_trails[id] = t
	t["tint"] = tint
	t["on"] = true


func speed_lines(amount: float) -> void:
	_lines_amount = maxf(_lines_amount, clampf(amount, 0.0, 1.0))


## The node's biggest body meshes (by AABB volume), cached.
func _parts_of(node: Node3D) -> Array:
	var id: int = node.get_instance_id()
	var cached: Array = _part_cache.get(id, [])
	var ok: bool = not cached.is_empty()
	for mi in cached:
		if not is_instance_valid(mi) or not mi.is_inside_tree():
			ok = false
			break
	if ok:
		return cached
	var all: Array = _meshes_of(node)
	var scored: Array = []
	for mi in all:
		var m: MeshInstance3D = mi
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var bb: AABB = m.mesh.get_aabb()
		var sc: Vector3 = m.global_transform.basis.get_scale()
		var vol: float = absf(bb.size.x * sc.x * bb.size.y * sc.y * bb.size.z * sc.z)
		scored.append([vol, m])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for e in scored:
		if out.size() >= GHOST_PARTS:
			break
		out.append(e[1])
	_part_cache[id] = out
	return out


func _spawn_ghost(node: Node3D, tint: Color) -> void:
	var parts: Array = _parts_of(node)
	if parts.is_empty():
		return
	var gi := _next_ghost
	_next_ghost = (_next_ghost + 1) % GHOST_SETS
	var ghost: Array = _ghost_parts[gi]
	for j in GHOST_PARTS:
		var g: MeshInstance3D = ghost[j]
		if j < parts.size() and is_instance_valid(parts[j]):
			var src: MeshInstance3D = parts[j]
			g.mesh = src.mesh
			g.global_transform = src.global_transform
			g.visible = true
		else:
			g.visible = false
	_ghost_life[gi] = GHOST_LIFE
	_ghost_tint[gi] = tint
	_ghost_mats[gi].albedo_color = Color(tint.r, tint.g, tint.b, GHOST_ALPHA)


func _hand_pos(node: Node3D, prop: String, fallback: Vector3) -> Vector3:
	var h = node.get(prop)
	if h is Node3D and is_instance_valid(h) and (h as Node3D).is_inside_tree():
		return (h as Node3D).global_position
	return node.global_position + fallback


func _update_trails(delta: float) -> void:
	_clock += delta
	for i in GHOST_SETS:
		var life: float = _ghost_life[i]
		if life <= 0.0:
			continue
		life -= delta
		_ghost_life[i] = life
		if life <= 0.0:
			for g in _ghost_parts[i]:
				(g as MeshInstance3D).visible = false
			continue
		var k: float = life / GHOST_LIFE
		var c: Color = _ghost_tint[i]
		_ghost_mats[i].albedo_color = Color(c.r, c.g, c.b, GHOST_ALPHA * k * k)
	_ribbon_mesh.clear_surfaces()
	if _trails.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var drop: Array = []
	var any := false
	var max_age: float = RIBBON_EVERY * float(RIBBON_PTS)
	for id in _trails:
		var t: Dictionary = _trails[id]
		var node: Node3D = t["node"]
		if not is_instance_valid(node) or not node.is_inside_tree():
			drop.append(id)
			continue
		var on: bool = t["on"]
		t["on"] = false   # must be renewed by trail() next frame
		var tint: Color = t["tint"]
		var pts_l: PackedVector3Array = t["pts_l"]
		var pts_r: PackedVector3Array = t["pts_r"]
		var ages: PackedFloat32Array = t["ages"]
		for a in ages.size():
			ages[a] += delta
		if on:
			var lg: float = t["last_ghost"]
			if lg < 0.0 or _clock - lg >= GHOST_EVERY:
				t["last_ghost"] = _clock
				_spawn_ghost(node, tint)
			var lp: float = t["last_pt"]
			var hl := _hand_pos(node, "hand_l", Vector3(-0.3, 1.1, 0))
			var hr := _hand_pos(node, "hand_r", Vector3(0.3, 1.1, 0))
			if lp < 0.0 or _clock - lp >= RIBBON_EVERY:
				t["last_pt"] = _clock
				pts_l.insert(0, hl)
				pts_r.insert(0, hr)
				ages.insert(0, 0.0)
			elif pts_l.size() > 0:
				pts_l[0] = hl
				pts_r[0] = hr
		# age out samples (this also drains the ribbon once the trail stops)
		while ages.size() > 0 and (ages.size() > RIBBON_PTS or ages[ages.size() - 1] > max_age):
			ages.resize(ages.size() - 1)
			pts_l.resize(ages.size())
			pts_r.resize(ages.size())
		t["pts_l"] = pts_l
		t["pts_r"] = pts_r
		t["ages"] = ages
		if ages.size() >= 2 and cam != null:
			if not any:
				_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
				any = true
			_ribbon_strip(pts_l, ages, max_age, tint, cam)
			_ribbon_strip(pts_r, ages, max_age, tint, cam)
		elif ages.is_empty() and not on:
			drop.append(id)
	if any:
		_ribbon_mesh.surface_end()
	for id in drop:
		_trails.erase(id)


func _ribbon_strip(pts: PackedVector3Array, ages: PackedFloat32Array, max_age: float, tint: Color, cam: Camera3D) -> void:
	var eye: Vector3 = cam.global_position
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	var prev_c := Color()
	for i in pts.size():
		var p: Vector3 = pts[i]
		var dir: Vector3
		if i + 1 < pts.size():
			dir = pts[i + 1] - p
		else:
			dir = p - pts[i - 1]
		var side: Vector3 = dir.cross(eye - p)
		if side.length_squared() < 0.000001:
			side = Vector3.UP
		var k: float = 1.0 - clampf(ages[i] / max_age, 0.0, 1.0)
		side = side.normalized() * (RIBBON_WIDTH * (0.25 + 0.75 * k) * 0.5)
		var a := p + side
		var b := p - side
		var c := Color(tint.r, tint.g, tint.b, 0.55 * k * k)
		if i > 0:
			_ribbon_mesh.surface_set_color(prev_c)
			_ribbon_mesh.surface_add_vertex(prev_a)
			_ribbon_mesh.surface_add_vertex(prev_b)
			_ribbon_mesh.surface_set_color(c)
			_ribbon_mesh.surface_add_vertex(a)
			_ribbon_mesh.surface_add_vertex(a)
			_ribbon_mesh.surface_set_color(prev_c)
			_ribbon_mesh.surface_add_vertex(prev_b)
			_ribbon_mesh.surface_set_color(c)
			_ribbon_mesh.surface_add_vertex(b)
		prev_a = a
		prev_b = b
		prev_c = c


func _update_speed_lines(real_dt: float) -> void:
	var want: float = _lines_amount
	_lines_amount = 0.0
	_lines_shown = lerpf(_lines_shown, want, clampf(real_dt * (10.0 if want > _lines_shown else 5.0), 0.0, 1.0))
	if _lines_shown < 0.02 and want <= 0.0:
		_lines_shown = 0.0
		if _lines_ctl.visible:
			_lines_ctl.visible = false
		return
	_lines_ctl.visible = true
	# Each streak rushes outward and respawns at a fresh angle (manga-style speed lines).
	for i in SPEED_LINES:
		var ph: float = _lines_seed[i * 3 + 2] + real_dt * 3.2
		if ph >= 1.0:
			ph -= 1.0
			_lines_seed[i * 3] = randf() * TAU
			_lines_seed[i * 3 + 1] = randf_range(0.18, 0.4)
		_lines_seed[i * 3 + 2] = ph
	_lines_ctl.queue_redraw()


func _draw_speed_lines() -> void:
	var sz: Vector2 = _lines_ctl.size
	var c: Vector2 = sz * 0.5
	var rad: float = sz.length() * 0.5
	for i in SPEED_LINES:
		var ang: float = _lines_seed[i * 3]
		var ln: float = _lines_seed[i * 3 + 1]
		var ph: float = _lines_seed[i * 3 + 2]
		var d := Vector2(cos(ang), sin(ang) * 0.8).normalized()
		var r0: float = rad * (0.5 + 0.5 * ph)
		var r1: float = r0 + rad * ln
		var hw: float = lerpf(1.5, 5.0, ph)
		var n := Vector2(-d.y, d.x)
		var a: float = 0.42 * _lines_shown * sin(ph * PI)
		var col := Color(1.0, 1.0, 0.95, a)
		var tip := Color(1.0, 1.0, 0.95, 0.0)
		var pts := PackedVector2Array([c + d * r0, c + d * r1 + n * hw, c + d * r1 - n * hw])
		_lines_ctl.draw_polygon(pts, PackedColorArray([tip, col, col]))


# ---------------------------------------------------------------- textures

func _make_star_texture() -> ImageTexture:
	# 16x16 starburst: bright core plus four long and four short rays.
	var n := 16
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(7.5, 7.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y) - c
			var r: float = d.length() / 7.5
			var ang: float = d.angle()
			var long_rays: float = pow(absf(cos(ang * 2.0)), 10.0) * clampf(1.0 - r, 0.0, 1.0)
			var short_rays: float = pow(absf(sin(ang * 2.0)), 10.0) * clampf(1.0 - r * 1.6, 0.0, 1.0)
			var core: float = clampf(1.0 - r * 2.0, 0.0, 1.0)   # wider, hotter core
			var a: float = clampf(core * 2.2 + long_rays * 1.15 + short_rays * 0.9, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_vignette_texture() -> ImageTexture:
	# 64x36 red edge glow, transparent centre; stretched over the screen (linear filtered).
	var w := 64
	var h := 36
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u: float = (float(x) + 0.5) / float(w) * 2.0 - 1.0
			var v: float = (float(y) + 0.5) / float(h) * 2.0 - 1.0
			var d: float = Vector2(u, v).length() / 1.4142
			var a: float = clampf((d - 0.45) / 0.55, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(0.85, 0.04, 0.02, a))
	return ImageTexture.create_from_image(img)


func _make_puff_texture() -> ImageTexture:
	# 16x16 soft lumpy blob for dust.
	var n := 16
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(7.5, 7.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y) - c
			var lump: float = 1.0 + 0.12 * sin(d.angle() * 5.0)
			var r: float = d.length() / (7.5 * lump)
			var a: float = clampf(1.0 - r, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

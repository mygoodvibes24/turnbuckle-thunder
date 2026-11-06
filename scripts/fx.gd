extends Node3D
## Cheap pooled hit FX for phones: additive starburst sparks, mat dust puffs and a
## white screen flash. Everything is generated in code; no per-hit allocations.
##
## API (positions are world space):
##   spark(pos, strength)   # starburst that scale-pops and fades (~0.2 s)
##   dust(pos, strength)    # ring of grey puffs drifting outward along the mat
##   flash(strength)        # full-screen white flash (finishers)
##   splinters(pos, strength)      # 10-20 brown wood shards fly out, spin, bounce once, fade
##   debris(pos, strength, color)  # chunkier generic bits (chairs: grey, trash cans, ...)

const SPARK_POOL := 12
const SHARD_POOL := 48            # shared by splinters and debris (ring buffer)
const SHARD_LIFE := 1.1
const SHARD_GRAVITY := 14.0
const MAT_Y := 1.0                # world y of the mat top
const RING_EDGE := 4.4            # beyond this |x| or |z| there is no mat under a shard
var _splinter_colors: Array[Color] = [Color(0.55, 0.38, 0.2), Color(0.68, 0.5, 0.3), Color(0.42, 0.28, 0.15)]
const SPARK_LIFE := 0.2
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

var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_life := 0.0
var _flash_peak := 0.0


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

	_splinter_mesh = BoxMesh.new()
	_splinter_mesh.size = Vector3(0.035, 0.025, 0.2)
	_chunk_mesh = BoxMesh.new()
	_chunk_mesh.size = Vector3(0.09, 0.05, 0.12)
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


# ---------------------------------------------------------------- public API

func spark(pos: Vector3, strength: float) -> void:
	var s: float = clampf(strength, 0.1, 1.5)
	var i: int = _next_spark
	_next_spark = (_next_spark + 1) % SPARK_POOL
	var mi: MeshInstance3D = _sparks[i]
	mi.global_position = pos
	_spark_dur[i] = SPARK_LIFE + 0.05 * s
	_spark_life[i] = _spark_dur[i]
	_spark_size[i] = 0.35 + 0.55 * s
	_spark_tint[i] = _tints[randi() % _tints.size()]
	mi.scale = Vector3.ONE * (_spark_size[i] * 0.4)
	_spark_mats[i].albedo_color = _spark_tint[i]
	mi.visible = true
	# Big hits get a second, smaller offset burst for a crunchier look.
	if s >= 0.6:
		var j: int = _next_spark
		_next_spark = (_next_spark + 1) % SPARK_POOL
		var mj: MeshInstance3D = _sparks[j]
		mj.global_position = pos + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.15), randf_range(-0.1, 0.1))
		_spark_dur[j] = SPARK_LIFE * 0.8
		_spark_life[j] = _spark_dur[j]
		_spark_size[j] = _spark_size[i] * 0.55
		_spark_tint[j] = Color(1.0, 1.0, 1.0)
		mj.scale = Vector3.ONE * (_spark_size[j] * 0.4)
		_spark_mats[j].albedo_color = _spark_tint[j]
		mj.visible = true


func dust(pos: Vector3, strength: float) -> void:
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
		_dust_mats[i].albedo_color = Color(0.72, 0.7, 0.68, 0.0)
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
		_dust_mats[i].albedo_color = Color(0.72, 0.7, 0.68, a)

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

	if _flash_life > 0.0:
		# The flash runs on real time so slow motion doesn't stretch it into a fade-out.
		var real_dt: float = delta / maxf(Engine.time_scale, 0.05)
		_flash_life -= real_dt
		if _flash_life <= 0.0:
			_flash_life = 0.0
			_flash_peak = 0.0
			_flash_rect.visible = false
		else:
			_flash_rect.color = Color(1, 1, 1, _flash_peak * (_flash_life / FLASH_TIME))


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
			var core: float = clampf(1.0 - r * 2.4, 0.0, 1.0)
			var a: float = clampf(core * 1.5 + long_rays + short_rays * 0.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
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

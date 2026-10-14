class_name Weapon
extends Node3D
## 武器系统：命中判定走射线，视觉走枪口火光 + 可见弹丸 + 命中火花。
##
## 枪是 Arisu.glb 自带的轨道枪（蒙在 Bip001_Weapon 骨上，跟着动作走）。
##
## 弹道起点为什么不用枪口骨：
##   枪口在腰侧（实测距右手骨 0.6 m、高度约 0.45 m），相机在眼睛高度（约 1.5 m）。
##   用「枪口 → 准星远点」会擦着目标过去，表现为「准星压在靶子上却打不中」。
##   所以弹道起点 = 相机位置 + muzzle_offset，落在准星那条线上，保证指哪打哪。
##   枪口火光与弹丸仍从真实枪口骨出来，观感不受影响。

signal ammo_changed(current: int, maximum: int)
signal fired(shot_index: int)
signal reload_started()
signal reload_finished()
signal hit_confirmed(collider: Object, position: Vector3)

# --- 数值 ---
@export var damage := 18.0
@export var fire_interval := 0.075      # 连发间隔（约 13 发/秒）
@export var auto_fire := true
@export var magazine_size := 60
@export var reserve_ammo := 9999
@export var reload_time := 1.05
## 换弹结束到能再次开火的间隔（秒）。留一点余量让收招动作播完，
## 不然松开换弹瞬间就吐子弹，看着像动作被腰斩。
@export var post_reload_delay := 0.12
@export var range_meters := 300.0
@export var spread_hip := 0.014
@export var spread_aim := 0.002
@export var recoil_pitch := 0.008
@export var recoil_yaw := 0.003

@export var skeleton_path: NodePath
## 弹道起点相对相机的偏移，保证起点落在准星线上
@export var muzzle_offset := Vector3(0.24, -0.1, -0.35)

# --- 弹丸视觉 ---
@export var tracer_speed := 260.0       # 弹丸飞行速度（米/秒）
const TRACER_LEN := 0.55

var current_ammo: int
var _cooldown := 0.0
var _reloading := false
var _reload_timer := 0.0
var _trigger := false
var _shot_index := 0
var _debug_raycast := false
## 正处在「转身对准准星」的过程中（此时扳机按着也不开火）
var _turning := false
## 正在飞的弹丸：[MeshInstance3D, 总距离, 终点, 已飞距离, 视觉倍率]
var _in_flight: Array = []

var skeleton: Skeleton3D
var _muzzle_bone := -1
var _fx_root: Node = null
var _tracer_mesh: Mesh
var _tracer_mat: StandardMaterial3D

@onready var muzzle: Marker3D = $Muzzle
@onready var _player: Player = get_parent() as Player
@onready var _driver: AnimDriver = get_node_or_null("../Arisu/Model/AnimDriver") as AnimDriver


func _ready() -> void:
	current_ammo = magazine_size
	_fx_root = get_tree().root if get_tree() else self
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton == null and get_tree():
		skeleton = _find_first(get_tree().root, "Skeleton3D") as Skeleton3D
	if skeleton:
		_muzzle_bone = skeleton.find_bone("bone_Railgun_Muzzle_03")
		if _muzzle_bone < 0:
			_muzzle_bone = skeleton.find_bone("bone_Railgun_Muzzle_01")

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = TRACER_LEN
	cyl.radial_segments = 6
	cyl.rings = 0
	_tracer_mesh = cyl
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.albedo_color = Color(0.8, 0.95, 1.0, 0.95)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(0.6, 0.88, 1.0)
	_tracer_mat.emission_energy_multiplier = 2.2

	ammo_changed.emit(current_ammo, magazine_size)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_follow_muzzle_bone()
	_advance_tracers(delta)

	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
		return

	# 按住不放就一直打；打空后 shoot() 会自己触发换弹，
	# _trigger 全程保持 true，所以换完弹会自动续射 —— 不用再点一次鼠标。
	if _trigger and auto_fire and _cooldown <= 0.0:
		shoot()


func _follow_muzzle_bone() -> void:
	if skeleton == null or _muzzle_bone < 0:
		return
	muzzle.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_muzzle_bone)


func set_debug_raycast(on: bool) -> void:
	_debug_raycast = on


# --- 扳机 ---

func trigger_down() -> void:
	_trigger = true
	if not auto_fire:
		shoot()


func trigger_up() -> void:
	_trigger = false


func shoot() -> bool:
	if _reloading or _cooldown > 0.0:
		return false
	# 角色还没转向准星方向就先不开火（符合常理：不能背对着靶子把子弹打出去）。
	# 扳机保持按住，转到位后这一句自然就放行了。
	if _player and not _player.is_aim_aligned():
		_turning = true
		return false
	_turning = false
	if current_ammo <= 0:
		try_reload()
		return false

	_cooldown = maxf(fire_interval, 0.0)
	current_ammo -= 1
	ammo_changed.emit(current_ammo, magazine_size)
	_shot_index += 1

	if _driver:
		_driver.request_fire()

	_fire_raycast()

	if _player:
		var sign_x := 1.0 if randf() < 0.5 else -1.0
		_player.add_recoil(recoil_pitch, recoil_yaw * sign_x * randf_range(0.4, 1.0))

	fired.emit(_shot_index)
	return true


func _fire_raycast() -> void:
	var space := get_world_3d().direct_space_state
	if _player == null:
		return

	var cam_dir := _player.camera_forward()
	var origin := _player.cam.global_position \
		+ _player.cam.global_transform.basis * muzzle_offset

	var spread := spread_aim if _player.aiming else spread_hip
	var dir := _apply_spread(cam_dir, spread)
	var end := origin + dir * range_meters

	var q := PhysicsRayQueryParameters3D.create(origin, end)
	q.collide_with_areas = false
	# 全部层，唯独屏蔽「同伴层」，让子弹从同伴身上穿过去。
	# ⚠️ create() 的默认 mask 是全部层；同伴跟得又近，不屏蔽的话
	#    玩家会一直打在自己人背上（这一段是加同伴时补的）。
	q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)

	var impact := end
	var normal := -dir
	var collider: Object = null
	if hit:
		impact = hit.position
		normal = hit.normal
		collider = hit.collider

	if _debug_raycast:
		print("  [raycast] origin=%s dir=%s hit=%s collider=%s" % [
			str(origin.snappedf(0.01)), str(dir.snappedf(0.01)), str(hit != null), str(collider)])

	var muzzle_pos := muzzle.global_position
	_spawn_tracer(muzzle_pos, impact)

	if collider and collider.has_method("take_damage"):
		collider.take_damage(damage, impact, -dir)
		hit_confirmed.emit(collider, impact)
	elif collider is Node and collider.get_parent() and collider.get_parent().has_method("take_damage"):
		collider.get_parent().take_damage(damage, impact, -dir)
		hit_confirmed.emit(collider.get_parent(), impact)

	_muzzle_flash()
	_schedule_impact(impact, normal, muzzle_pos.distance_to(impact) / maxf(tracer_speed, 1.0))


func _apply_spread(dir: Vector3, amount: float) -> Vector3:
	if amount <= 0.0:
		return dir
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	var a := randf() * TAU
	var r := sqrt(randf()) * amount
	return (dir + right * (cos(a) * r) + up * (sin(a) * r)).normalized()


# --- 换弹 ---

func try_reload() -> void:
	if _reloading or current_ammo >= magazine_size:
		return
	_reloading = true
	_reload_timer = reload_time
	# ⚠️ 这里**不要**清 _trigger！
	# 清了的话，按住左键打空 → 自动换弹 → 换完必须重新点一次鼠标才能射击。
	# 保持 _trigger 不动，换完弹 _process 里那句 shoot() 就会自动接上。
	reload_started.emit()
	if _driver:
		_driver.request_reload()


func _finish_reload() -> void:
	_reloading = false
	_reload_timer = 0.0
	var need := magazine_size - current_ammo
	var take := mini(need, reserve_ammo)
	current_ammo += take
	reserve_ammo -= take
	ammo_changed.emit(current_ammo, magazine_size)
	# 收招余量：换完弹先空一拍再允许开火，避免动作被立刻吐出的子弹腰斩。
	# 注意不要动 _trigger —— 它保持 true，所以按住不放会自动续射。
	_cooldown = maxf(_cooldown, post_reload_delay)
	reload_finished.emit()


func is_reloading() -> bool:
	return _reloading


## 是否正卡在「转身对准准星」的阶段（HUD 可以拿它显示「转向中」）
func is_turning() -> bool:
	return _turning


func reload_progress() -> float:
	if not _reloading:
		return 1.0
	return 1.0 - clampf(_reload_timer / reload_time, 0.0, 1.0)


# --- 弹丸 ---

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var total := from.distance_to(to)
	if total < 0.05:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mat
	_fx_root.add_child(mi)
	mi.global_position = from
	var dir := (to - from).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	mi.look_at(to, up)
	mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var visual_scale := clampf(total / TRACER_LEN, 1.0, 8.0)
	mi.scale = Vector3(1.0, visual_scale, 1.0)
	_in_flight.append([mi, total, to, 0.0, visual_scale])


func _advance_tracers(delta: float) -> void:
	if _in_flight.is_empty():
		return
	var step := tracer_speed * delta
	var done: Array = []
	for i in _in_flight.size():
		var item: Array = _in_flight[i]
		var mi: MeshInstance3D = item[0]
		if not is_instance_valid(mi):
			done.append(i)
			continue
		item[3] = float(item[3]) + step
		var total: float = item[1]
		var travel: float = item[3]
		if travel >= total:
			mi.queue_free()
			done.append(i)
			continue
		# 光弹沿弹道往前滑，尾部跟着收，看起来就是一颗在飞的弹
		var frac := clampf(travel / total, 0.0, 1.0)
		var tail := maxf(1.0 - frac, 0.05)
		mi.scale.y = maxf(float(item[4]) * tail, 0.05)
		mi.global_position = mi.global_position.lerp(item[2], clampf(step / maxf(total - travel + step, 0.001), 0.0, 1.0))
	done.reverse()
	for i in done:
		_in_flight.remove_at(i)


func _schedule_impact(pos: Vector3, normal: Vector3, delay: float) -> void:
	if not is_inside_tree():
		return
	var timer := get_tree().create_timer(maxf(delay, 0.01))
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			_spawn_impact(pos, normal))


# --- 特效 ---

func _muzzle_flash() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.55)
	light.light_energy = 3.5
	light.omni_range = 3.0
	muzzle.add_child(light)

	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.22, 0.22)
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.9, 0.6, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 1.6
	qm.material = mat
	quad.rotation.z = randf() * TAU
	_fx_root.add_child(quad)
	quad.global_position = muzzle.global_position

	var tw := quad.create_tween()
	tw.set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.05)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.05)
	tw.chain().tween_callback(quad.queue_free)
	tw.chain().tween_callback(light.queue_free)


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var holder := Node3D.new()
	_fx_root.add_child(holder)
	holder.global_position = pos

	for i in 6:
		var spark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.036
		sm.radial_segments = 4
		sm.rings = 2
		spark.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.5)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.3)
		mat.emission_energy_multiplier = 2.0
		sm.material = mat
		holder.add_child(spark)
		spark.global_position = pos
		var dir := (normal + Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)) * 0.8).normalized()
		var tw := spark.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "global_position", pos + dir * randf_range(0.12, 0.4), 0.18)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
		tw.chain().tween_callback(holder.queue_free)


func _find_first(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r:
			return r
	return null

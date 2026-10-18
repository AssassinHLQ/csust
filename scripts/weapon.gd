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
## 光弹 / 枪口火光的**视觉**起点：true = 把枪口骨投影到弹道那条线上（推荐）。
## 为什么需要：这个模型的枪**不在手上**（README §1.9），枪口骨在腰侧，
## 实测离弹道 **1.3 m**、高度只有 0.25 m。直接拿枪口当起点，光弹会从角色身侧
## 斜着飞出去，看起来就是「子弹不是从枪口出来的」。投影到弹道上之后，
## 光弹沿着准星方向从角色身体里飞出去，观感才对。
@export var fx_on_aim_line := false
## 视觉起点沿射线最多向前偏移多少米；默认保持在枪口附近
@export var fx_forward := 0.0

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
	# ⚠️ 必须比 `AnimDriver`（`process_priority = 100`，它每帧还会把枪骨掰向准星）
	#    更晚跑：枪口标记是照着**枪骨当前姿势**摆的，早一步同步就跟不上那一下掰枪，
	#    弹道起点会落在「掰之前」的旧位置 —— 用户 2026-10-18 报的
	#    「跑打子弹发射的点不在枪口上，偏右了」就是这个一帧的滞后（摆臂 42° 时
	#    枪口能被甩出 0.3 m 以上）。
	process_priority = 110
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
	if _driver:
		_driver.set_trigger(true)
	if not auto_fire:
		shoot()


func trigger_up() -> void:
	_trigger = false
	# 松开扳机 → 让动画知道「这一发打完了」。
	# ⚠️ 不通知的话，整身跑打动作要一直播到片子结束：`RunFire_Ing` 2.667 s、
	#    走路时倍速 0.46 ⇒ **点一下鼠标，攻击姿势演 5.8 秒**，人还在往前走 ——
	#    用户报的「攻击一下后再开始走路会变成右转螃蟹平移」就是这个
	#    （实测见 `anim_driver.gd` 的 `FIRE_RELEASE_GRACE`）。
	if _driver:
		_driver.set_trigger(false)
		_driver.cancel_fire()


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
		# 空仓：干响一声。`_trigger` 全程保持 true，所以这一句在换弹开始前
		# 每帧都会被走到 —— 靠 `Sfx` 里 "empty" 的 gap_ms=150 节流，
		# 不然会变成一串「咔咔咔咔」。
		Sfx.play("empty")
		try_reload()
		return false

	_cooldown = maxf(fire_interval, 0.0)
	current_ammo -= 1
	ammo_changed.emit(current_ammo, magazine_size)
	_shot_index += 1

	if _driver:
		_driver.request_fire()

	_fire_raycast()
	# 枪声走**非定位**（2D）：玩家自己的枪永远「在耳边」，用 3D 定位会随镜头左右漂。
	Sfx.play("fire")

	if _player:
		var sign_x := 1.0 if randf() < 0.5 else -1.0
		_player.add_recoil(recoil_pitch, recoil_yaw * sign_x * randf_range(0.4, 1.0))

	fired.emit(_shot_index)
	return true


func _fire_raycast() -> void:
	var space := get_world_3d().direct_space_state
	if _player == null:
		return
	# ⚠️ 开枪前**当场**再同步一次枪口：`_process` 里那一次可能早于 `AnimDriver`
	#    掰枪骨（见 `_ready()` 里的说明）。这里同步之后，弹道起点就是**这一帧**
	#    视觉枪口的真实位置。
	_follow_muzzle_bone()

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
	# 视觉起点默认就在**真实枪口**（fx_on_aim_line = false）。
	# 打开时把枪口挪到瞄准射线上：沿射向投影，且最多落在射线起点之后 0.25 m。
	# ⚠️ 老版本是「投影到相机前方、再往前推」，表现就是「子弹从角色前面冒出来」
	#    —— 用户报的「位置太靠前」正是这个，所以默认改成了 false。
	var fx_from := muzzle_pos
	if fx_on_aim_line:
		fx_from = origin + dir * clampf((muzzle_pos - origin).dot(dir), 0.0, 0.25) \
			+ dir * fx_forward
	_spawn_tracer(fx_from, impact)

	if collider and collider.has_method("take_damage"):
		collider.take_damage(damage, impact, -dir)
		hit_confirmed.emit(collider, impact)
	elif collider is Node and collider.get_parent() and collider.get_parent().has_method("take_damage"):
		collider.get_parent().take_damage(damage, impact, -dir)
		hit_confirmed.emit(collider.get_parent(), impact)

	_muzzle_flash(fx_from)
	_schedule_impact(impact, normal, fx_from.distance_to(impact) / maxf(tracer_speed, 1.0))


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
	Sfx.play("reload_out")
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
	Sfx.play("reload_in")
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
	var dir := (to - from).normalized()
	# 光弹长度：目标越远越长（封顶 3 倍），但不超过整条弹道
	var len0 := minf(TRACER_LEN * clampf(total / TRACER_LEN, 1.0, 3.0), total)
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mat
	_fx_root.add_child(mi)
	_orient_tracer(mi, dir)
	mi.scale = Vector3(1.0, maxf(len0, 0.02) / TRACER_LEN, 1.0)
	# ⚠️ 光柱是**以节点为原点居中**的圆柱，所以节点要放在这一段的**中间**。
	#    老版本把节点放在枪口，于是圆柱有一半伸到**身后**去（最长 4.4 m 时
	#    身后 2.2 m），玩家看到的就是「子弹从背后飞出来」—— 用户报的就是这个。
	mi.global_position = from + dir * (len0 * 0.5)
	_in_flight.append([mi, total, to, 0.0, len0, dir, from])


## 让圆柱的**轴向（局部 +Y）**对准飞行方向。
## ⚠️ 别用 `look_at()` + `rotate_object_local(RIGHT, PI/2)` 那一对：
##    它们合起来会把轴向转到**反方向**去（老版本的另一半 bug）。
func _orient_tracer(mi: MeshInstance3D, dir: Vector3) -> void:
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(dir)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(dir).normalized()
	mi.basis = Basis(x, dir, z)


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
		var total: float = item[1]
		var travel: float = float(item[3]) + step
		item[3] = travel
		var len0: float = item[4]
		var dir: Vector3 = item[5]
		var from: Vector3 = item[6]
		if travel >= total:
			mi.queue_free()
			done.append(i)
			continue
		# 光弹 = 跟在弹头后面的一段短光柱：弹头在 travel，尾巴在 travel − len0。
		# 起段从起点往外长，长到 len0 之后就整体往前滑 —— **永远不会伸到身后**。
		var tail := maxf(travel - len0, 0.0)
		var seg := maxf(travel - tail, 0.02)
		mi.scale.y = seg / TRACER_LEN
		mi.global_position = from + dir * ((travel + tail) * 0.5)
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

func _muzzle_flash(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.55)
	light.light_energy = 3.5
	light.omni_range = 3.0
	_fx_root.add_child(light)
	light.global_position = at

	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.065
	flash_mesh.height = 0.13
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	flash.mesh = flash_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.6, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 1.6
	flash.material_override = mat
	_fx_root.add_child(flash)
	flash.global_position = at

	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.05)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.05)
	tw.chain().tween_callback(flash.queue_free)
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

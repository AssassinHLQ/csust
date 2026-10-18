extends SceneTree
## 探针：**同一帧相位**下，把「只走」和「走着 + 开火叠加层」逐骨对比。
##
## 用户（本轮目标）：「先开火一次，在走路就变成这样子右侧身子螃蟹平移」。
##
## 已经量到的事实（`_probe_fire_then_walk.gd`）：
##   站着点一下 → 立刻走，第 22 帧肩线 **+9.4°**、第 37 帧 **+13.5°**（正常走路 −0.6°），
##   而且此时叠加层已经在 `UpperBodyMove` 上（migr=1）—— 说明**移动层里还有骨在动**。
##
## 「移动层里还剩哪些骨」光看关键字猜不出来（Alice 有 170 根骨，名字五花八门），
## 所以这里直接把两边的姿势抓下来逐骨相减：
##   ① 只走：`Cafe_Walk` 停在同一个相位（`speed_scale = 0` + `seek`）
##   ② 走着 + 开火：基础层同样停在那个相位，叠加层 `UpperBodyMove` 停在固定相位
## 两边**脚在同一个位置**，差值就只剩「叠加层掰了谁」。
##
## 用法：
##   godot --path <工程> --headless --script res://scripts/_probe_walk_attack_diff.gd -- --splat=off

const SPOT := Vector3(-14.0, 0.1, -12.0)
const PHASE := 0.30

var _p: Player
var _anim: AnimDriver
var _sk: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 14:
		await process_frame
	paused = false
	_p = game.get_node_or_null("Player") as Player
	_anim = _p.anim as AnimDriver
	_sk = _anim.skeleton
	_p.set_physics_process(false)
	_p.global_position = SPOT
	await _frames(8)
	print("[diff] 移动层滤掉的轨道：下半身 %d / 躯干 %d / 手臂武器 %d / 根骨 %d"
		% [_anim.lower_tracks_removed, _anim.trunk_tracks_removed,
		_anim.arm_tracks_removed, _anim.root_tracks_removed])

	# ① 只走，冻在 PHASE
	_anim.reset_state()
	for _i in 40:
		_anim.set_locomotion(2.4, true, 0.0)
		await process_frame
	var base := await _freeze_and_snap(PHASE)
	print("[diff] 只走：clip=%s 骨 %d 根" % [_anim.current_clip(), base.size()])

	# ② 站着开火 → 走着开火（叠加层搬到 UpperBodyMove）
	_anim.reset_state()
	for _i in 20:
		_anim.set_locomotion(0.0, true, 0.0)
		await process_frame
	_anim.request_fire()
	await _frames(6)
	print("[diff] 开火后：base=%s upper=%s" % [_anim.current_clip(), _anim.upper_clip()])
	for _i in 40:
		_anim.set_locomotion(2.4, true, 0.0)
		await process_frame
	var lyr := _anim.active_upper_layer()
	print("[diff] 走起来之后：base=%s 叠加层=%s" % [_anim.current_clip(),
		"无" if lyr == null else String(lyr.name)])
	var moved := await _freeze_and_snap(PHASE)

	# ③ 逐骨相减
	var rows := []
	for i in _sk.get_bone_count():
		if not base.has(i) or not moved.has(i):
			continue
		var d: float = rad_to_deg((base[i] as Quaternion).angle_to(moved[i] as Quaternion))
		rows.append([d, i])
	rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	print("\n[diff] 相对「只走」变化最大的 15 根骨（同相位对比）：")
	for r in rows.slice(0, 15):
		var i := int(r[1])
		print("   %6.1f°  %-26s parent=%s" % [float(r[0]), _sk.get_bone_name(i),
			_sk.get_bone_name(_sk.get_bone_parent(i)) if _sk.get_bone_parent(i) >= 0 else "—"])
	quit(0)


## 冻住所有播放器、把基础层 seek 到 PHASE、抓全骨架姿势
func _freeze_and_snap(phase: float) -> Dictionary:
	_anim.player.speed_scale = 0.0
	_anim.player.seek(phase, true)
	var lyr := _anim.active_upper_layer()
	if lyr != null and lyr.is_inside_tree():
		lyr.speed_scale = 0.0
		lyr.seek(0.40, true)
	# seek 之后要等一帧，姿势才会写进骨架
	for _i in 3:
		await process_frame
	var snap := {}
	for i in _sk.get_bone_count():
		snap[i] = _sk.get_bone_global_pose(i).basis.get_rotation_quaternion()
	return snap


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

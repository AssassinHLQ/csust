extends SceneTree
## 验「霸王龙的碰撞盒贴不贴得住身体」。
##
## 为什么需要这条：2026-11-08 用户报「瞄准中间那只龙，打到的是右下角那只」
## 「打得到但人飞不过去」。量出来三只龙的碰撞盒是 218×96×99 m 的隐形大盒子，
## 中心离身体 39~54 m —— 玩家从出生点就被挡在外面，射线在离相机几米处就撞上。
##
## 根因：`boss.gd::_build_box_parts_collision()` 用 `MeshInstance3D.get_aabb()`
## 量蒙皮模型，而这个 FBX 的网格顶点在绑定空间（跨度是骨架的 ~298 倍），
## 每块网格的节点缩放又各是 3.01 / 0.307 / 0.024 —— 三者一乘什么都不是。
## 改成按骨骼切片建盒之后，盒子贴合到亚米级。
##
## 这条自检盯的就是「盒子 vs 骨骼」的偏差：一旦有人把 BOX_PARTS 改回量网格 AABB，
## 立刻红。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_verify_trex_hitbox.gd -- --no-capture

const LEVEL := "res://scenes/next_level.tscn"
const NAMES := ["TrexBossA", "TrexBossB", "TrexBossC"]

## 盒子中心离骨骼中心最多允许多少「身长」。0.25 = 四分之一个身长。
const MAX_CENTER_DRIFT := 0.25
## 盒子 AABB 每一维最多能是骨骼 AABB 的几倍（骨点是骨架中心线，盒子必须略大）。
const MAX_SIZE_RATIO := 1.6
## 反过来也不能小太多，否则打不中（骨点离表皮有距离）。
const MIN_SIZE_RATIO := 0.75

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[Verify] 加载不了 %s" % LEVEL)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame

	# 出生点离它们 137 m，BootGate 是 60 m / 20 s 才建 —— 这里直接催建
	for nm in NAMES:
		var b := level.get_node_or_null(nm)
		if b != null and not bool(b.get("_booted")):
			b.call("_boot")
	for i in 50:
		await process_frame

	print("")
	print("========== 霸王龙碰撞盒贴合度 ==========")
	for nm in NAMES:
		var boss := level.get_node_or_null(nm)
		if boss == null:
			_check(false, "%s 存在" % nm)
			continue
		var boxes: Array = boss.get("_collisions")
		_check(boxes != null and not boxes.is_empty(), "%s 建出了碰撞体（%d 个）" % [
			nm, 0 if boxes == null else boxes.size()])
		if boxes == null or boxes.is_empty():
			continue
		var box_aabb := _collision_aabb(boxes)
		var bone_aabb := _bone_aabb(boss)
		if bone_aabb.size == Vector3.ZERO:
			_check(false, "%s 取得到骨骼（蒙皮模型必须走骨骼）" % nm)
			continue

		var drift := box_aabb.get_center().distance_to(bone_aabb.get_center())
		var body_len := maxf(maxf(bone_aabb.size.x, bone_aabb.size.z), 0.5)
		var ratio := Vector3(
			box_aabb.size.x / maxf(bone_aabb.size.x, 0.01),
			box_aabb.size.y / maxf(bone_aabb.size.y, 0.01),
			box_aabb.size.z / maxf(bone_aabb.size.z, 0.01))
		print("        %s：盒子 %s ｜ 骨骼 %s" % [
			nm, str(box_aabb.size.snappedf(0.01)), str(bone_aabb.size.snappedf(0.01))])
		print("              中心偏移 %.2f m ｜ 尺寸比 %.2f × %.2f × %.2f" % [
			drift, ratio.x, ratio.y, ratio.z])
		_check(drift <= body_len * MAX_CENTER_DRIFT,
			"%s 盒子中心贴着身体（偏移 %.2f m ≤ 身长 %.1f m 的 25%%）" % [nm, drift, body_len])
		_check(ratio.x <= MAX_SIZE_RATIO and ratio.y <= MAX_SIZE_RATIO and ratio.z <= MAX_SIZE_RATIO,
			"%s 盒子没有大得离谱（每维 ≤ %.1f 倍）" % [nm, MAX_SIZE_RATIO])
		_check(ratio.x >= MIN_SIZE_RATIO and ratio.y >= MIN_SIZE_RATIO and ratio.z >= MIN_SIZE_RATIO,
			"%s 盒子也没有小得打不中（每维 ≥ %.1f 倍）" % [nm, MIN_SIZE_RATIO])
		# 关键回归项：盒子不能把玩家整个罩住
		_check(box_aabb.size.length() < bone_aabb.size.length() * 2.5,
			"%s 盒子整体不是「隐形大罩子」（%.1f m < %.1f m）" % [
				nm, box_aabb.size.length(), bone_aabb.size.length() * 2.5])

	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


func _collision_aabb(boxes: Array) -> AABB:
	var out := AABB()
	var first := true
	for cs in boxes:
		var c := cs as CollisionShape3D
		if c == null or c.shape == null:
			continue
		var bb: AABB = c.shape.get_debug_mesh().get_aabb()
		var world := c.global_transform * bb
		out = world if first else out.merge(world)
		first = false
	return out


func _bone_aabb(boss: Node) -> AABB:
	var skel := _find_skeleton(boss)
	if skel == null:
		return AABB()
	var xf := skel.global_transform
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p: Vector3 = xf * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		return AABB()
	return AABB(lo, hi - lo)


func _find_skeleton(n: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Skeleton3D:
			var s := c as Skeleton3D
			if best == null or s.get_bone_count() > best.get_bone_count():
				best = s
		for ch in c.get_children():
			stack.append(ch)
	return best

extends SceneTree
## 诊断：第二关三只霸王龙的**每一个**碰撞盒，在 idle 与五段技能各自的 impact 时刻
## 分别离身体有多远；以及盒子到底有没有跟着动作移动。
##
## 背景（2026-11-11 用户报）：「霸王龙优香碰撞错了，而且碰撞没有随着霸王龙放技能改变」。
## `boss.gd::_build_bone_cluster_collision()` 只在 `_boot()` 时按**当时那一个姿态**
## 切一次骨骼、建几个静态盒子，之后再也不动 —— 技能一播，网格甩出去十几米，
## 盒子还钉在原地。这条探针就是量这个。
##
##   bash _tools/run_probe.sh res://scripts/_probe_trex_boxes.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const NAMES := ["TrexBossA", "TrexBossB", "TrexBossC"]
## 抄 `trex_yuuka_boss.gd::ATTACKS`
const CLIPS := ["bite", "tail_sweep", "stomp", "charge", "roar"]
const IMPACTS := [0.50, 0.83, 0.92, 1.08, 0.58]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[Probe] 加载不了 %s" % LEVEL)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	for nm in NAMES:
		var b := level.get_node_or_null(nm)
		if b != null and not bool(b.get("_booted")):
			b.call("_boot")
	for i in 40:
		await process_frame

	for nm in NAMES:
		_dump_boss(nm, level.get_node_or_null(nm))

	print("")
	print("========== 盒子有没有跟着动作走 ==========")
	print("  （idle 记下每个盒子中心，再逐段播技能，看盒子位移 vs 身体位移）")
	for nm in NAMES:
		var boss := level.get_node_or_null(nm)
		if boss == null:
			continue
		var skel: Skeleton3D = boss.call("_best_skeleton", boss.get("model"))
		var anim := boss.get("_anim") as AnimationPlayer
		if skel == null or anim == null:
			print("  !! %s 取不到骨架/动画" % nm)
			continue
		anim.play("idle")
		await process_frame
		var idle_body := _bone_aabb(skel)
		var idle_boxes := _box_centers(boss)
		for i in CLIPS.size():
			anim.play(CLIPS[i])
			anim.seek(IMPACTS[i], true)
			await process_frame
			var body := _bone_aabb(skel)
			var body_moved := body.get_center().distance_to(idle_body.get_center())
			var boxes := _box_centers(boss)
			var box_moved := 0.0
			for k in mini(boxes.size(), idle_boxes.size()):
				box_moved = maxf(box_moved, boxes[k].distance_to(idle_boxes[k]))
			var worst := 0.0
			var far := 0
			for cs in boss.get("_collisions"):
				var d := _dist_to_box(_box_aabb(cs), body)
				worst = maxf(worst, d)
				if d > 2.0:
					far += 1
			print("  %s %-11s 身体移动 %5.2f m ｜ 盒子最大移动 %5.2f m ｜ 最远盒面离身体 %5.2f m ｜ %d/%d 个盒子偏出 2 m" % [
				nm, CLIPS[i], body_moved, box_moved, worst, far,
				(boss.get("_collisions") as Array).size()])
		anim.play("idle")

	print("")
	quit(0)


func _dump_boss(nm: String, boss: Node) -> void:
	if boss == null:
		print("!! %s 不存在" % nm)
		return
	var boxes: Array = boss.get("_collisions")
	print("")
	print("── %s：%d 个盒子 ──" % [nm, 0 if boxes == null else boxes.size()])
	if boxes == null:
		return
	for i in boxes.size():
		var cs := boxes[i] as CollisionShape3D
		if cs == null or cs.shape == null:
			print("   #%d 不是可用的 CollisionShape3D" % i)
			continue
		var w := _box_aabb(cs)
		var par := "null"
		if cs.get_parent() != null:
			par = "boss" if cs.get_parent() == boss else str(cs.get_parent().name)
		print("   #%d %-12s size %-24s 中心 %-28s 父 %s" % [
			i, cs.name, str(w.size.snappedf(0.01)),
			str(w.get_center().snappedf(0.01)), par])


func _box_centers(boss: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for cs in boss.get("_collisions"):
		out.append(_box_aabb(cs).get_center())
	return out


## 盒子在世界空间的 AABB
func _box_aabb(cs: CollisionShape3D) -> AABB:
	if cs == null or cs.shape == null:
		return AABB()
	return cs.global_transform * cs.shape.get_debug_mesh().get_aabb()


## 两个 AABB 之间的最近距离（相交时 0）
func _dist_to_box(box: AABB, body: AABB) -> float:
	var d := 0.0
	for ax in 3:
		var gap := maxf(0.0,
			maxf(box.position[ax] - (body.position[ax] + body.size[ax]),
				body.position[ax] - (box.position[ax] + box.size[ax])))
		d += gap * gap
	return sqrt(d)


func _bone_aabb(skel: Skeleton3D) -> AABB:
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

extends SceneTree
## 验「霸王龙的碰撞盒贴不贴得住身体」——**静止姿态 + 五段技能动画中**都要贴。
##
## ── 为什么需要这条 ──
## 2026-11-08 用户报「瞄准中间那只龙，打到的是右下角那只」「打得到但人飞不过去」。
## 量出来三只龙的碰撞盒是 218×96×99 m 的隐形大盒子，中心离身体 39~54 m。
## 根因：`boss.gd::_build_box_parts_collision()` 用 `MeshInstance3D.get_aabb()`
## 量蒙皮模型，而这个 FBX 的网格顶点在绑定空间（跨度是骨架的 ~298 倍）。
## 改成按骨骼切片建盒之后，盒子贴合到亚米级。
##
## 2026-11-11 用户又报：「霸王龙优香碰撞错了，而且**碰撞没有随着霸王龙放技能改变**」。
## 量出来（`_probe_trex_boxes.gd`）：五段技能各播到 impact 时刻，盒子位移全是
## **0.00 m** —— 盒子是 `_boot()` 那一刻建好就钉死的静态件。现在改成
## 「盒子挂在代表骨骼上、`_physics_process` 里按骨骼当前姿态重算」（`boss.gd::_followers`），
## 这条自检盯的就是它：**每段动作里盒子必须真的动、而且仍然贴着身体**。
##
## 判据是**双向**的，缺一不可：
##   · 盒子中心 → 最近骨点（盒子没被甩到身体外面去）
##   · 骨点被某个盒子盖住的比例（身体没从盒子缝里漏出去）
## 只看其中一边都能被「一个巨大的罩子」骗过去。
##
##   bash _tools/run_probe.sh res://scripts/_verify_trex_hitbox.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const NAMES := ["TrexBossA", "TrexBossB", "TrexBossC"]
## 抄 `trex_yuuka_boss.gd::ATTACKS`
const CLIPS := ["bite", "tail_sweep", "stomp", "charge", "roar"]
const IMPACTS := [0.50, 0.83, 0.92, 1.08, 0.58]

## 盒子中心离骨骼中心最多允许多少「身长」。0.25 = 四分之一个身长。
const MAX_CENTER_DRIFT := 0.25
## 盒子 AABB 每一维最多能是骨骼 AABB 的几倍（骨点是骨架中心线，盒子必须略大）。
const MAX_SIZE_RATIO := 1.6
## 反过来也不能小太多，否则打不中（骨点离表皮有距离）。
const MIN_SIZE_RATIO := 0.75

## ── 动画中的判据 ──
## 每段技能里，盒子最大位移至少要有这么多（证明它跟着骨骼动了）。
## 实测最小的一段（roar）也有 1.6 m；给一半余量。
const MIN_BOX_TRAVEL := 0.8
## 盒子中心到最近骨点的距离上限（m）。片子是骨点做 AABB 再 pad，中心必然靠里。
const MAX_BOX_TO_BONE := 3.5
## 骨点必须被某个盒子盖住的比例（留余量给「pad 之外的边角骨」）。
##
## ⚠️ 这条只当**粗筛**用，阈值故意放得比实测值低：AABB 重算偶尔会因为
## 「不建到地平面以下」那条 clamp 削掉一点。真正咬精度的是下面那条软覆盖。
const MIN_BONE_COVER := 0.85
## 骨点离盒面的**容差**，超过这个才算「漏出去」。
const COVER_TOL := 0.35
## ── 软覆盖（硬指标）──
## 任何一个骨点，离「最近那个盒子的表面」都不能超过这么多米。
##
## 为什么不设成 0：重算 AABB 之后，正常姿势下**本来就是 0.00**（骨头都在自己的
## 包围盒里，这是恒等式）。唯一会漏的是 `boss.gd::_sync_bone_collisions()` 里
## 「盒子不探到地平面以下」那条 clamp —— 冲锋时身体沉下去，地下的那截骨头
## 被有意排除在碰撞之外。实测残留就是这个：charge 0.47~0.66 m，其余四段全是 0.00。
## 所以这条阈值真正抓的是「有没有哪一截身体整段跑出盒子」，1 m 以内都算正常。
const MAX_BONE_OUTSIDE := 1.0
## 每帧跟随更新的耗时上限（μs / 每次调用）。3 只一起跑也不能吃掉 1% 的一帧。
const MAX_SYNC_US := 200.0

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


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

	_check_idle(level)
	await _check_animated(level)
	_check_sync_cost(level)

	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


## ── ① 静止姿态：盒子贴不贴合 ──
func _check_idle(level: Node) -> void:
	print("")
	print("========== ① 静止姿态贴合度 ==========")
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


## ── ② 技能动画中：盒子必须跟着走，而且仍然贴着身体 ──
func _check_animated(level: Node) -> void:
	print("")
	print("========== ② 五段技能动画中的跟随 ==========")
	for nm in NAMES:
		var boss := level.get_node_or_null(nm)
		if boss == null:
			_check(false, "%s 存在（动画段）" % nm)
			continue
		var anim := boss.get("_anim") as AnimationPlayer
		if anim == null:
			_check(false, "%s 有 AnimationPlayer（没动作就没得跟）" % nm)
			continue
		anim.play("idle")
		await _settle()
		var idle_centers := _box_centers(boss)

		for i in CLIPS.size():
			var clip: String = CLIPS[i]
			anim.play(clip)
			anim.seek(IMPACTS[i], true)
			await _settle()

			var centers := _box_centers(boss)
			var travel := 0.0
			for k in mini(centers.size(), idle_centers.size()):
				travel = maxf(travel, centers[k].distance_to(idle_centers[k]))
			var bones := _bone_points(boss)
			var box_to_bone := 0.0
			for c in centers:
				var nearest := INF
				for p in bones:
					nearest = minf(nearest, c.distance_to(p))
				box_to_bone = maxf(box_to_bone, nearest)
			var covered := 0
			for p in bones:
				if _covered(boss.get("_collisions"), p):
					covered += 1
			var cover := float(covered) / float(maxi(bones.size(), 1))
			# 软覆盖：最「出格」的那根骨点离最近盒面多远
			var outside := 0.0
			for p in bones:
				outside = maxf(outside, _outside_distance(boss.get("_collisions"), p))
			print("        %s %-11s 盒子最大位移 %5.2f m ｜ 盒子→最近骨点 %4.2f m ｜ 硬盖住 %d%% ｜ 最远骨点出格 %4.2f m" % [
				nm, clip, travel, box_to_bone, roundi(cover * 100.0), outside])
			_check(travel >= MIN_BOX_TRAVEL,
				"%s %s：盒子跟着技能动了（%0.2f m ≥ %.1f m）" % [nm, clip, travel, MIN_BOX_TRAVEL])
			_check(box_to_bone <= MAX_BOX_TO_BONE,
				"%s %s：盒子没被甩出身体（%0.2f m ≤ %.1f m）" % [nm, clip, box_to_bone, MAX_BOX_TO_BONE])
			_check(cover >= MIN_BONE_COVER,
				"%s %s：身体大面上没从盒子缝里漏出去（盖住 %d%% ≥ %d%%）" % [
					nm, clip, roundi(cover * 100.0), roundi(MIN_BONE_COVER * 100.0)])
			_check(outside <= MAX_BONE_OUTSIDE,
				"%s %s：没有骨头戳出盒子 %.2f m 以外（%0.2f m ≤ %.2f m）" % [
					nm, clip, MAX_BONE_OUTSIDE, outside, MAX_BONE_OUTSIDE])
		anim.play("idle")
		await _settle()


## ── ③ 每帧跟随的开销 ──
func _check_sync_cost(level: Node) -> void:
	print("")
	print("========== ③ 跟随更新的开销 ==========")
	var total_us := 0.0
	var counted := 0
	for nm in NAMES:
		var boss := level.get_node_or_null(nm)
		if boss == null or not boss.has_method("_sync_bone_collisions"):
			continue
		var n := 300
		# 先空转几次让编译器/JIT 稳定
		for i in 5:
			boss.call("_sync_bone_collisions")
		var t0 := Time.get_ticks_usec()
		for i in n:
			boss.call("_sync_bone_collisions")
		var us := float(Time.get_ticks_usec() - t0) / float(n)
		total_us += us
		counted += 1
		print("        %s：%.1f μs / 帧（%d 个盒子）" % [
			nm, us, (boss.get("_collisions") as Array).size()])
	if counted == 0:
		_check(false, "三只都在跑跟随更新")
		return
	var avg := total_us / float(counted)
	print("        三只合计约 %.1f μs / 帧（一帧 16.7 ms 的 %.2f%%）" % [
		total_us, total_us / 16700.0 * 100.0])
	_check(avg <= MAX_SYNC_US,
		"单只跟随开销 %.1f μs ≤ %.0f μs" % [avg, MAX_SYNC_US])
	_check(total_us / 16700.0 < 0.01,
		"三只合计吃掉不到一帧的 1%%（%.2f%%）" % [total_us / 16700.0 * 100.0])


## 等「骨骼已刷 + 物理已经跑过一帧」：跟随更新在 `_physics_process` 里
func _settle() -> void:
	await process_frame
	await physics_frame
	await process_frame


func _box_centers(boss: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for cs in boss.get("_collisions"):
		out.append(_box_world_aabb(cs).get_center())
	return out


## 盒子世界包围盒：按 8 个角点变换后取 AABB（盒子现在是**带旋转**的，不能直接乘 AABB）
func _box_world_aabb(cs: CollisionShape3D) -> AABB:
	if cs == null or not (cs.shape is BoxShape3D):
		return AABB()
	var xf := cs.global_transform
	var h: Vector3 = (cs.shape as BoxShape3D).size * 0.5
	var out := AABB(xf * Vector3(-h.x, -h.y, -h.z), Vector3.ZERO)
	for i in 8:
		var p := xf * Vector3(
			h.x if (i & 1) != 0 else -h.x,
			h.y if (i & 2) != 0 else -h.y,
			h.z if (i & 4) != 0 else -h.z)
		out = out.expand(p)
	return out


func _collision_aabb(boxes: Array) -> AABB:
	var out := AABB()
	var first := true
	for cs in boxes:
		var c := cs as CollisionShape3D
		if c == null or c.shape == null:
			continue
		var w := _box_world_aabb(c)
		out = w if first else out.merge(w)
		first = false
	return out


## 骨点是否被某个盒子盖住（盒子带旋转，得转到盒子局部空间里比）
func _covered(boxes: Array, p: Vector3) -> bool:
	for cs in boxes:
		var c := cs as CollisionShape3D
		if c == null or not (c.shape is BoxShape3D):
			continue
		var local: Vector3 = c.global_transform.affine_inverse() * p
		var h: Vector3 = (c.shape as BoxShape3D).size * 0.5
		if absf(local.x) <= h.x + COVER_TOL \
				and absf(local.y) <= h.y + COVER_TOL \
				and absf(local.z) <= h.z + COVER_TOL:
			return true
	return false


## 骨点离「最近那个盒子表面」还有多远（在里面就是 0）。
## 用各轴超出量的最大值当距离 —— 盒子是轴对齐的局部空间，这个口径比欧氏距离更严。
func _outside_distance(boxes: Array, p: Vector3) -> float:
	var best := INF
	for cs in boxes:
		var c := cs as CollisionShape3D
		if c == null or not (c.shape is BoxShape3D):
			continue
		var local: Vector3 = c.global_transform.affine_inverse() * p
		var h: Vector3 = (c.shape as BoxShape3D).size * 0.5
		var over := maxf(maxf(absf(local.x) - h.x, absf(local.y) - h.y), absf(local.z) - h.z)
		best = minf(best, maxf(over, 0.0))
	if best == INF:
		return 0.0
	return best


func _bone_points(boss: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var skel := _find_skeleton(boss)
	if skel == null:
		return out
	var xf := skel.global_transform
	for i in skel.get_bone_count():
		out.append(xf * skel.get_bone_global_pose(i).origin)
	return out


func _bone_aabb(boss: Node) -> AABB:
	var pts := _bone_points(boss)
	if pts.is_empty():
		return AABB()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
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

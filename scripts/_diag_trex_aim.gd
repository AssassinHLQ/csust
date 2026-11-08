extends SceneTree
## 诊断：机甲瞄「屏幕上中间那只」霸王龙，射线到底打中了谁。
##
## 用户 2026-11-08：「我瞄准中间的龙，为什么打到的是右下角龙？」
##   · 三只霸王龙在 next_level.tscn 里的坐标是 (-95,-96) / (-120,-115) / (-135,-140)，
##     身高 9.0 / 7.5 / 10.5 —— 又高又大，站位还大致在一条斜线上。
##   · 它们的碰撞是 `collision_mode = BOX_PARTS`：载入时按**绑定姿势**的 AABB
##     建一批静态盒子（`boss.gd::_build_box_parts_collision`）。
##   · 但它们有 6 段动作（撕咬 / 尾扫 / 跺地 / 冲锋 / 嚎叫），身体会大幅位移 ——
##     盒子**不跟着动作走**。所以「看得见的身体」和「打得中的盒子」可能差好几米。
##
## 本探针量三件事，全部打印出来，不猜：
##   ① 每只龙「盒子包出来的世界包围盒」 vs 「骨骼当前姿势的世界包围盒」差多少；
##   ② 相机对准 B 的头时，A / B / C 分别落在屏幕的哪个归一化坐标（谁是「中间那只」）；
##   ③ 从那个机位沿视线打一条射线，`intersect_ray` 命中的是哪个节点、几个盒子。
##
## 跑法（只读，不改仓库里任何东西）：
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_trex_aim.gd -- --no-capture

const LEVEL := "res://scenes/next_level.tscn"
const NAMES := ["TrexBossA", "TrexBossB", "TrexBossC"]


func _initialize() -> void:
	_run()


func _run() -> void:
	if not ResourceLoader.exists(LEVEL):
		push_error("[Diag] 没有 %s" % LEVEL)
		quit(1)
		return
	var scene := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(scene)
	for i in 4:
		await process_frame

	var level := root.get_node_or_null("NextLevel")
	if level == null:
		push_error("[Diag] 场景根不叫 NextLevel")
		quit(1)
		return
	var player := level.get_node_or_null("Player") as Player
	if player == null:
		push_error("[Diag] 没有 Player")
		quit(1)
		return

	# ── 强制建模型 + 碰撞（BootGate 是 60 m / 20 s 才建，出生点离它们 137 m）──
	var bossens: Array = []
	for nm in NAMES:
		var b := level.get_node_or_null(nm)
		if b == null:
			push_warning("[Diag] 找不到 %s" % nm)
			continue
		if not bool(b.get("_booted")):
			b.call("_boot")
		bossens.append(b)
	for i in 6:
		await process_frame
	# 让动作跑一段，身体离开绑定姿势
	for i in 40:
		await process_frame

	print("")
	print("========== ① 出生点到每只龙的距离 ==========")
	var spawn := player.global_position
	for b in bossens:
		var d := spawn.distance_to((b as Node3D).global_position)
		print("  %s  pos=%s  离出生点 %.1f m  height=%.1f" % [
			(b as Node).name, str((b as Node3D).global_position.snappedf(0.1)), d,
			float(b.get("height"))])

	print("")
	print("========== ② 碰撞盒 vs 骨骼当前姿势 ==========")
	for b in bossens:
		var boxes: Array = b.get("_collisions")
		if boxes == null or boxes.is_empty():
			print("  %s：没有碰撞盒" % (b as Node).name)
			continue
		var box_aabb := AABB()
		var first := true
		for cs in boxes:
			var c := cs as CollisionShape3D
			if c == null or c.shape == null:
				continue
			var bb := c.shape.get_debug_mesh().get_aabb() if c.shape.has_method("get_debug_mesh") else AABB()
			var world := c.global_transform * bb
			if first:
				box_aabb = world
				first = false
			else:
				box_aabb = box_aabb.merge(world)
		var bone_aabb := _bone_aabb(b)
		print("  %s：" % (b as Node).name)
		for cs in boxes:
			var c2 := cs as CollisionShape3D
			if c2 == null or c2.shape == null:
				continue
			if c2.shape is BoxShape3D:
				print("     盒 %s size=%s  cs.scale=%s  世界原点=%s" % [
					c2.name, str((c2.shape as BoxShape3D).size.snappedf(0.01)),
					str(c2.transform.basis.get_scale().snappedf(0.001)),
					str(c2.global_position.snappedf(0.01))])
		print("    盒子 %d 个  AABB pos=%s size=%s" % [
			boxes.size(), str(box_aabb.position.snappedf(0.01)),
			str(box_aabb.size.snappedf(0.01))])
		if bone_aabb.size == Vector3.ZERO:
			print("    骨骼：取不到（没有 Skeleton3D？）")
		else:
			print("    骨骼 AABB pos=%s size=%s" % [
				str(bone_aabb.position.snappedf(0.01)),
				str(bone_aabb.size.snappedf(0.01))])
			print("    盒子中心与骨骼中心相差 %.2f m" % (
				box_aabb.get_center().distance_to(bone_aabb.get_center())))

	# ── ③ 站到三只龙的**侧向**，让它们在屏幕上明显分开，再一次一只地瞄 ──
	#
	# ⚠️ 不能站「B 往回 30 m」：三只龙和出生点几乎共线，那样是贴着 A 站。
	# ⚠️ 也不能把相机往后退 4.2 m：出生点在门厅里，退一步就退进墙里，
	#    射线 0.1 m 就打在墙上。真实游戏里 `SpringArm3D` 会自动缩短，这里直接
	#    从**眼睛位置**发射，等价于「没被墙挡住的理想机位」。
	var a_node := level.get_node_or_null("TrexBossA") as Node3D
	var c_node := level.get_node_or_null("TrexBossC") as Node3D
	var b_mid := level.get_node_or_null("TrexBossB") as Node3D
	if a_node == null or c_node == null or b_mid == null:
		quit(0)
		return
	var along := c_node.global_position - a_node.global_position
	along.y = 0.0
	var side := Vector3(-along.z, 0.0, along.x).normalized()
	player.global_position = b_mid.global_position + side * 45.0 + Vector3(0, 0.6, 0)
	player.velocity = Vector3.ZERO
	await process_frame
	var eye_origin := player.global_position + Vector3(0, 1.62, 0)

	var space := player.get_world_3d().direct_space_state
	print("")
	print("========== ③ 站在侧向 45 m：瞄谁打谁？ ==========")
	print("  机位=%s" % str(eye_origin.snappedf(0.1)))
	for target in bossens:
		var tn := target as Node3D
		print("  —— 准星压在 %s 头上 ——" % tn.name)
		var aim_dir := (_head_pos(target) - eye_origin).normalized()
		# 其余两只偏离准星多少度（越小越接近屏幕正中）
		for other in bossens:
			if other == target:
				continue
			var d2 := (_head_pos(other) - eye_origin).normalized()
			print("     %s 偏离准星 %.2f°" % [
				(other as Node).name, rad_to_deg(aim_dir.angle_to(d2))])
		var q := PhysicsRayQueryParameters3D.create(eye_origin, eye_origin + aim_dir * 300.0)
		q.collide_with_areas = false
		q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("     ⇒ 射线：没打中")
			continue
		var col: Object = hit.get("collider")
		var nm := str(col)
		if col is Node:
			var n2 := col as Node
			while n2 != null:
				if String(n2.name).begins_with("Trex"):
					nm = String(n2.name)
					break
				n2 = n2.get_parent()
		var ok := "✓ 打对了" if nm == tn.name else "✗ 打错了"
		print("     ⇒ 射线命中 %s，距离 %.1f m   %s" % [
			nm, eye_origin.distance_to(hit.get("position")), ok])

	print("")
	print("[Diag] 完")
	quit(0)


## 一只 Boss 的骨骼**当前姿势**在世界空间的包围盒（贪心取所有骨头原点）。
func _bone_aabb(boss: Node) -> AABB:
	var skel := _find_skeleton(boss)
	if skel == null:
		return AABB()
	var pts := PackedVector3Array()
	var xf := skel.global_transform
	for i in skel.get_bone_count():
		pts.append(xf * skel.get_bone_global_pose(i).origin)
	if pts.is_empty():
		return AABB()
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## 头骨位置（拿不到就退回节点原点 + 半个身高）。
func _head_pos(boss: Node) -> Vector3:
	var skel := _find_skeleton(boss)
	if skel != null:
		for nm in ["head", "Bip001_Head", "bone_head", "Head"]:
			var i := skel.find_bone(nm)
			if i >= 0:
				return skel.global_transform * skel.get_bone_global_pose(i).origin
	return (boss as Node3D).global_position + Vector3(0, float(boss.get("height")) * 0.8, 0)


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

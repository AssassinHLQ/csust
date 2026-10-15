extends SceneTree
## 快检：直接读 scenes/game.tscn 里 Room609/RoomCollision 的 5 个盒
## （按世界坐标算每个盒的 AABB，并判断门洞还在不在）。
##
## 为什么要它：手摆的碰撞**不经过 splat_scene.gd 的生成算法**，所以改坏了
## `_verify_room.gd` 要跑好几分钟（它要真渲染 + 真跑物理）才能发现。这个探针
## 不解码泼溅、不渲染，2 秒内把「盒在哪、多大、有没有转、门还开不开」打出来。
##
## 用法：
##   godot --headless --path . --script res://scripts/_probe_check_collision.gd

const SCENE := "res://scenes/game.tscn"
const ROOM := "Room609"
const BODY := "Room609/RoomCollision"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		push_error("[col] 载入不了 %s" % SCENE)
		quit(1)
		return
	var root_node: Node = ps.instantiate()
	var room: Node3D = root_node.get_node_or_null(ROOM)
	if room == null:
		push_error("[col] 找不到 %s" % ROOM)
		quit(1)
		return
	var col: StaticBody3D = room.get_node_or_null("RoomCollision")
	print("[col] %s 的全局变换 = %s" % [ROOM, str(room.transform)])
	print("[col] build_box_collision = %s（Room609 上的导出）" % str(room.get("build_box_collision")))
	if col == null:
		print("[col] **没有 RoomCollision**")
		quit(1)
		return

	var boxes: Array = []
	for ch in col.get_children():
		var cs := ch as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var bs := cs.shape as BoxShape3D
		# ⚠️ 用 room.transform * cs.transform 而不是 cs.global_transform：
		#    节点没进树时 global_transform 会报 "!is_inside_tree()" 并返回单位变换，
		#    于是旋转被丢掉、中心也丢了（第一版就栽在这里，量出来一片假数据）。
		#    Room609 本身是单位变换，所以这就是世界变换。
		var xf: Transform3D = room.transform * cs.transform
		var waabb: AABB = xf * AABB(-bs.size * 0.5, bs.size)
		boxes.append({"name": String(ch.name), "local": cs.position, "size": bs.size,
			"basis": cs.transform.basis, "aabb": waabb})

	print("[col] 盒 %d 个" % boxes.size())
	print("[col] 名字            局部中心                      shape.size                 世界 AABB 尺寸")
	for b in boxes:
		var p: Vector3 = b["local"]
		var s: Vector3 = b["size"]
		var w: Vector3 = (b["aabb"] as AABB).size
		print("[col] %-14s (%8.3f,%8.3f,%8.3f)  (%8.3f,%7.3f,%8.3f)  (%8.3f,%7.3f,%8.3f)%s" % [
			b["name"], p.x, p.y, p.z, s.x, s.y, s.z, w.x, w.y, w.z,
			"  ← 被旋转了" if not (b["basis"] as Basis).is_equal_approx(Basis.IDENTITY) else ""])

	# 门洞：找 z− 那面（世界 AABB 的 z 最小、且厚度在 z）的段，按 x 排序看缝
	var z_lo := INF
	for b in boxes:
		z_lo = minf(z_lo, (b["aabb"] as AABB).position.z)
	var segs: Array = []
	for b in boxes:
		var w: AABB = b["aabb"]
		if absf(w.position.z - z_lo) < 0.05 and w.size.z < 1.0:
			segs.append(w)
	segs.sort_custom(func(a, c): return a.position.x < c.position.x)
	print("[col] z− 面（世界 z 最小 %.3f）上厚度 < 1 m 的段：%d 个" % [z_lo, segs.size()])
	if segs.size() == 2:
		var gap_lo: float = segs[0].position.x + segs[0].size.x
		var gap_hi: float = segs[1].position.x
		print("[col] 门洞 x %.3f ~ %.3f → 宽 %.3f（期望 %.2f），中心 %.3f（期望 %.2f）" % [
			gap_lo, gap_hi, gap_hi - gap_lo,
			float(room.get("box_door_width")), (gap_lo + gap_hi) * 0.5,
			float(room.get("box_door_center"))])
		if gap_hi - gap_lo < 0.1:
			print("[col] ⚠️ 两段之间没有缝 —— **门被堵死了**")
	elif segs.size() == 1:
		print("[col] ⚠️ 只有 1 段 —— 那一面是**整堵墙**（要么门没了，要么有一段被转了 90° 所以不算「厚度在 z」）")
	quit(0)

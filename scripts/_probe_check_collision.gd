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

	# ── 按「薄的那一轴」分组，报每个方向的覆盖区间与开口 ──
	#
	# ⚠️ 不能再用「哪一段的 z 等于房间包围盒的 z 最小」那种判法：手摆的墙
	#    **不一定贴在内容包围盒上**（画室609 的 1‰/99.9‰ 分位盒两端有离群点，
	#    真实墙面在它里侧 2 m 左右）。这里改成纯几何判据：
	#    厚度在 x 的盒 = 挡 x 方向（span 取它的 z 范围）；厚度在 z 的 = 挡 z 方向。
	#    被旋转过的盒会被世界 AABB 正确还原，所以照样能归类。
	var center: Vector3 = (room.call("content_world_aabb") as AABB).get_center()
	var groups := {"x_neg": [], "x_pos": [], "z_neg": [], "z_pos": []}
	for b in boxes:
		var w: AABB = b["aabb"]
		var thin_x := w.size.x <= 0.6
		var thin_z := w.size.z <= 0.6
		if thin_x and not thin_z:
			var gx := "x_neg" if w.get_center().x < center.x else "x_pos"
			groups[gx].append(Vector2(w.position.z, w.position.z + w.size.z))
		elif thin_z and not thin_x:
			var gz := "z_neg" if w.get_center().z < center.z else "z_pos"
			groups[gz].append(Vector2(w.position.x, w.position.x + w.size.x))
		else:
			print("[col]   ⚠️ %s 两轴都不薄（%.2f × %.2f），归不了类" % [
				b["name"], w.size.x, w.size.z])
	print("[col] 房间内容包围盒中心 x=%.2f z=%.2f（用来分「哪一侧」）" % [center.x, center.z])
	print("[col] ── 四个方向的覆盖与开口（只报 > 0.5 m 的缺口）──")
	for key in ["x_neg", "x_pos", "z_neg", "z_pos"]:
		var spans: Array = groups[key]
		spans.sort_custom(func(a, c): return a.x < c.x)
		var merged: Array = []
		for s in spans:
			if not merged.is_empty() and s.x <= merged[-1].y + 0.01:
				merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, s.y))
			else:
				merged.append(s)
		var txt := ""
		for i in merged.size():
			txt += "[%.2f, %.2f] " % [merged[i].x, merged[i].y]
			if i + 1 < merged.size():
				var gap: float = merged[i + 1].x - merged[i].y
				if gap > 0.5:
					txt += "← 开口 %.2f m → " % gap
		print("[col]   %-6s 段 %d：%s" % [key, merged.size(), txt])
	quit(0)

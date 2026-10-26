extends SceneTree
## 把画室 609 扫成**高度图**，找出所有该加碰撞的家具（桌子/椅子/画架/讲台…）。
##   godot --path . --headless --script res://scripts/_probe_room_scan.gd
##   （⚠️ 不要 `--headless` 里加 `--splat=off`；本探针不打图，纯射线，headless 就够）
##
## 做法：从 y = 3.2 往下打射线，记录命中高度。地面 ≈ 0.03，家具 0.4~0.9，
## 黑板/墙 3 m 以上（跳过）。每一格用字符表示高度档位，直接看成 ASCII 平面图。
## 房间矩形：x −5.55 ~ 4.56、z −6.48 ~ 13.56（`Room609/RoomCollision` 五面墙量出来的）。
## 输出：① ASCII 高度图 ② 每件家具的包围盒候选（按连通块聚）③ 可直接粘进 .tscn 的盒子

const STEP := 0.25
## 命中高度分档（米）：' ' 地面 / '.' 低矮(0.05~0.25) / 'o' 椅子凳(0.25~0.55)
## / 'O' 桌子台面(0.55~1.05) / '#' 高柜(1.05~3.0) / '@' 墙或天花板(>3.0) / '?' 打空
func _initialize() -> void:
	_run.call_deferred()


## 按占地面积从大到小（`AABB` 没有 `get_area()`，得自己乘）
func _by_area(a: AABB, b: AABB) -> bool:
	return a.size.x * a.size.z > b.size.x * b.size.z


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	var space := (root.get_world_3d() as World3D).direct_space_state
	var body := game.get_node_or_null("Room609/RoomCollision") as Node3D
	if body == null:
		print("[错误] 没有 Room609/RoomCollision")
		quit(1)
		return

	# 房间内框：从五面墙反推
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		# 只取墙（细长条）：厚度 ≤ 0.35
		if minf(minf(s.x, s.y), s.z) > 0.35:
			continue
		var b: AABB = cs.global_transform * AABB(-s * 0.5, s)
		lo = lo.min(b.position)
		hi = hi.max(b.position + b.size)
	lo.x += 0.15
	lo.z += 0.15
	hi.x -= 0.15
	hi.z -= 0.15
	print("房间内框：x %.2f ~ %.2f、z %.2f ~ %.2f" % [lo.x, hi.x, lo.z, hi.z])

	# 网格扫描
	var nx := int(ceil((hi.x - lo.x) / STEP))
	var nz := int(ceil((hi.z - lo.z) / STEP))
	print("扫描 %d × %d 格（每格 %.2f m）\n" % [nx, nz, STEP])
	var heights := []
	for j in nz:
		var row := PackedFloat32Array()
		var z := lo.z + (float(j) + 0.5) * STEP
		for i in nx:
			var x := lo.x + (float(i) + 0.5) * STEP
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, 3.2, z), Vector3(x, -0.6, z))
			var h := space.intersect_ray(q)
			if h.is_empty():
				row.append(-1.0)
			else:
				row.append((h["position"] as Vector3).y)
		heights.append(row)

	# ASCII 图（z 从上到下 = 北到南；x 从左到右 = 西到东）
	print("    " + "".join(range(nx).map(func(i): return "" if i % 4 else "%d" % (i % 10))))
	var head := "     "
	for i in nx:
		head += "|" if i % 4 == 0 else " "
	print(head + "   ← 每 1 m 一个 |")
	var chars := PackedStringArray()
	for j in nz:
		var line := "%+6.2f " % (lo.z + (float(j) + 0.5) * STEP)
		var crow := PackedStringArray()
		for i in nx:
			var y: float = heights[j][i]
			var ch := "?"
			if y < 0.0:
				ch = "?"
			elif y < 0.25:
				ch = " "
			elif y < 0.55:
				ch = "."
			elif y < 1.05:
				ch = "o"
			elif y < 3.0:
				ch = "#"
			else:
				ch = "@"
			line += ch
			crow.append(ch)
		print(line)
		chars.append("".join(crow))
	print("（空格=地面  .=矮  o=0.25~0.55  O→o  #=1.05~3.0  @=墙/天花板  ?=打空）")

	# ── 连通块聚成包围盒 ──
	# 「障碍」= 高度 > 0.25 且 < 3.0（家具），地面和墙都排除
	var seen := {}
	var boxes: Array[AABB] = []
	for j in nz:
		for i in nx:
			var key := Vector2i(i, j)
			if seen.has(key):
				continue
			var y: float = heights[j][i]
			if not (y > 0.25 and y < 3.0):
				continue
			# BFS
			var q: Array[Vector2i] = [key]
			seen[key] = true
			var mn := Vector2i(i, j)
			var mx := Vector2i(i, j)
			var top := 0.0
			var cnt := 0
			while not q.is_empty():
				var cur: Vector2i = q.pop_back()
				var yy: float = heights[cur.y][cur.x]
				top = maxf(top, yy)
				cnt += 1
				mn = Vector2i(mini(mn.x, cur.x), mini(mn.y, cur.y))
				mx = Vector2i(maxi(mx.x, cur.x), maxi(mx.y, cur.y))
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb: Vector2i = cur + (d as Vector2i)
					if nb.x < 0 or nb.x >= nx or nb.y < 0 or nb.y >= nz:
						continue
					if seen.has(nb):
						continue
					var y2: float = heights[nb.y][nb.x]
					if not (y2 > 0.25 and y2 < 3.0):
						continue
					seen[nb] = true
					q.append(nb)
			if cnt < 4:
				continue
			var b := AABB(
				Vector3(lo.x + float(mn.x) * STEP, 0.0, lo.z + float(mn.y) * STEP),
				Vector3(float(mx.x - mn.x + 1) * STEP, top, float(mx.y - mn.y + 1) * STEP))
			boxes.append(b)
	boxes.sort_custom(_by_area)
	print("\n家具候选 %d 件（按占地面积排序，已排除地面/墙）：" % boxes.size())
	for k in boxes.size():
		var b: AABB = boxes[k]
		print("  #%02d 中心 (%.2f, %.3f, %.2f)  尺寸 %.2f × %.2f × %.2f  [x %.2f~%.2f  z %.2f~%.2f]"
			% [k, b.get_center().x, b.get_center().y, b.get_center().z,
				b.size.x, b.size.y, b.size.z,
				b.position.x, b.end.x, b.position.z, b.end.z])
	quit(0)

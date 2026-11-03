extends SceneTree
## 把部室碰撞从「一块 21,892 面的凹面 trimesh」换成**命名盒子**
## （编辑器里每块都能拖、能改 size —— 用户 2026-10-26：「碰撞需要在 godot 编辑器
##  也看得见，因为这样子我好微调」）。
##
##   _tools/run_probe.sh res://scripts/_build_gamedev_collision.gd            # 写入
##   _tools/run_probe.sh res://scripts/_build_gamedev_collision.gd -- --dry   # 只打印
##
## 直接改写 `scenes/gamedev_room.tscn` 里 `Model/Collision` 下的节点，并删掉旧 trimesh
## 的 ext_resource（`assets/collision/gamedev_room_trimesh.res` 留在盘上做回退）。
##
## ── 判据（按模型 31 个材质面的局部 AABB 分类）──
##   · 占地 ≥ 60% 整屋且高 ≥ 1.5 m → 结构墙；外墙一律按**整屋 AABB** 重排成 6 块，
##     门洞那面拆成「左垛 + 右垛 + 门楣」
##   · 扁（高 < 0.5 m）且贴在墙面上、高 ≥ 2 m → 门框：**它的横向范围就是门洞**
##   · 扁且在顶部 → 天花板；扁且在最底 → 地板（都取自整屋 AABB）
##   · 其余扁的（地毯 / 坐垫 / 屏幕贴面 / 窗玻璃）→ 不生成碰撞（能走上去）
##   · 任一轴 < 0.6 m 的小件 → 不生成（免得一堆碎盒子挡路）
##   · 剩下的每件一个包围盒，名字取材质名，方便在编辑器里认
##
## ⚠️ 家具用 AABB 会**略多吃空间**（斜放的沙发/熊）。这是刻意的：宁可挡多一点，
##    也别让人穿模；嫌胖就在编辑器里把那块 `size` 改小。

const GLB := "res://models/gamedev_room/gamedev_room.glb"
const SCENE := "res://scenes/gamedev_room.tscn"
const WALL_THICK := 0.30
## 家具盒比 AABB 每边收 1 cm：贴墙的架子/柜子不会和墙盒叠在一起抖
const FURNITURE_SHRINK := 0.01
## 小件阈值（任一轴小于它就当装饰，不生成碰撞）
const MIN_EXTENT := 0.50

var boxes: Array = []


func _initialize() -> void:
	var dry := OS.get_cmdline_user_args().has("--dry")
	var ps := load(GLB) as PackedScene
	if ps == null:
		print("[col] 载入 GLB 失败")
		quit(1)
		return
	var holder := ps.instantiate()
	var mis := holder.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty() and holder is MeshInstance3D:
		mis = [holder]

	var surfs: Array = []
	var total := AABB()
	var first := true
	for node in mis:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var a := AABB(xf * verts[0], Vector3.ZERO)
			for v in verts:
				a = a.expand(xf * v)
			var mat := mi.mesh.surface_get_material(s)
			var nm := "surface%d" % s
			if mat != null and String(mat.resource_name) != "":
				nm = String(mat.resource_name)
			surfs.append({"name": _clean(nm), "aabb": a})
			total = a if first else total.merge(a)
			first = false
	if surfs.is_empty():
		print("[col] 模型里没有可用的面")
		quit(1)
		return

	var room_xz := total.size.x * total.size.z
	var door_lo := INF          # 门洞在局部 x 上的范围
	var door_hi := -INF
	var door_top := 0.0
	for s in surfs:
		var a: AABB = s["aabb"]
		var nm := String(s["name"])
		var foot := a.size.x * a.size.z
		var flat_y := a.size.y < 0.5
		var on_wall := absf(a.get_center().z - total.position.z) < 0.35 \
				or absf(a.get_center().z - (total.position.z + total.size.z)) < 0.35 \
				or absf(a.get_center().x - total.position.x) < 0.35 \
				or absf(a.get_center().x - (total.position.x + total.size.x)) < 0.35
		if foot >= room_xz * 0.60 and a.size.y >= 1.5:
			continue                                   # 结构墙，统一按整屋重排
		if flat_y and a.get_center().y > total.position.y + total.size.y * 0.8:
			continue                                   # 天花板
		if flat_y and a.get_center().y < total.position.y + total.size.y * 0.25:
			continue                                   # 地板/地毯
		if on_wall and a.size.y >= 2.0 and (a.size.x < 0.5 or a.size.z < 0.5):
			door_lo = a.position.x
			door_hi = a.position.x + a.size.x
			door_top = a.position.y + a.size.y
			print("[col] 认出门口：%s 横向 %.2f~%.2f，门楣底 %.2f" % [
				nm, door_lo, door_hi, door_top])
			continue                                   # 门框本身不做碰撞
		if flat_y:
			continue                                   # 地板层以上的扁片
		# 铺地/薄片（地毯 0.53 m 厚但短边 4.89 m）—— 生成盒子会变成一道台阶
		var ratio := a.size.y / maxf(minf(a.size.x, a.size.z), 0.001)
		if ratio < 0.25 and a.position.y + a.size.y < total.position.y + 1.2:
			continue
		if a.size.x < MIN_EXTENT or a.size.y < MIN_EXTENT or a.size.z < MIN_EXTENT:
			continue                                   # 小件
		boxes.append({
			"name": "Col_" + nm, "kind": "家具",
			"size": a.size - Vector3.ONE * FURNITURE_SHRINK * 2.0,
			"center": a.get_center(),
		})

	# ── 外壳：一律按整屋 AABB 重排 ──
	var lo := total.position
	var hi := total.position + total.size
	var mid := total.get_center()
	boxes.append({"name": "Col_Floor", "kind": "地板",
		"size": Vector3(total.size.x, 0.4, total.size.z),
		"center": Vector3(mid.x, lo.y + 0.2, mid.z)})
	boxes.append({"name": "Col_Ceiling", "kind": "天花板",
		"size": Vector3(total.size.x, WALL_THICK, total.size.z),
		"center": Vector3(mid.x, hi.y - WALL_THICK * 0.5, mid.z)})
	boxes.append({"name": "Col_WallXNeg", "kind": "墙",
		"size": Vector3(WALL_THICK, total.size.y, total.size.z),
		"center": Vector3(lo.x + WALL_THICK * 0.5, mid.y, mid.z)})
	boxes.append({"name": "Col_WallXPos", "kind": "墙",
		"size": Vector3(WALL_THICK, total.size.y, total.size.z),
		"center": Vector3(hi.x - WALL_THICK * 0.5, mid.y, mid.z)})
	boxes.append({"name": "Col_WallZPos", "kind": "墙",
		"size": Vector3(total.size.x, total.size.y, WALL_THICK),
		"center": Vector3(mid.x, mid.y, hi.z - WALL_THICK * 0.5)})
	if door_hi > door_lo:
		# 门洞那面（局部 z 最小）拆成左垛 / 右垛 / 门楣
		var dl := door_lo
		var dr := door_hi
		if dl > lo.x + 0.02:
			boxes.append({"name": "Col_DoorJambA", "kind": "墙(门左)",
				"size": Vector3(dl - lo.x, total.size.y, WALL_THICK),
				"center": Vector3((lo.x + dl) * 0.5, mid.y, lo.z + WALL_THICK * 0.5)})
		if hi.x - dr > 0.02:
			boxes.append({"name": "Col_DoorJambB", "kind": "墙(门右)",
				"size": Vector3(hi.x - dr, total.size.y, WALL_THICK),
				"center": Vector3((dr + hi.x) * 0.5, mid.y, lo.z + WALL_THICK * 0.5)})
		boxes.append({"name": "Col_DoorLintel", "kind": "墙(门楣)",
			"size": Vector3(dr - dl, hi.y - door_top, WALL_THICK),
			"center": Vector3((dl + dr) * 0.5, (door_top + hi.y) * 0.5, lo.z + WALL_THICK * 0.5)})
	else:
		boxes.append({"name": "Col_WallZNeg", "kind": "墙",
			"size": Vector3(total.size.x, total.size.y, WALL_THICK),
			"center": Vector3(mid.x, mid.y, lo.z + WALL_THICK * 0.5)})
		print("[col] ⚠️ 没认出门口，z 最小那面按整墙生成")

	print("[col] 整屋 AABB %s ~ %s（%.2f × %.2f × %.2f）" % [
		str(lo.snappedf(0.01)), str(hi.snappedf(0.01)),
		total.size.x, total.size.y, total.size.z])
	print("[col] 生成 %d 个盒子：" % boxes.size())
	for b in boxes:
		print("[col]   %-22s %-10s size=%s center=%s" % [
			String(b["name"]), String(b["kind"]),
			str((b["size"] as Vector3).snappedf(0.001)),
			str((b["center"] as Vector3).snappedf(0.001))])

	if dry:
		print("[col] --dry：没有改写场景")
		quit(0)
		return

	# ── 改写场景：删旧 trimesh 引用、换掉 Collision/Mesh 节点、补 sub_resource ──
	var text := FileAccess.get_file_as_string(SCENE)
	if text == "":
		print("[col] 读不到 %s" % SCENE)
		quit(1)
		return
	var lines := text.split("\n")
	var out: Array[String] = []
	var sub_blocks: Array[String] = []
	var node_blocks: Array[String] = []
	var skipped_mesh := false
	var i := 0
	while i < lines.size():
		var line := lines[i]
		# 幂等：先删掉本脚本上次生成的盒子，重跑不会叠第二套
		if line.begins_with("[node name=\"Col_\"") or line.begins_with("[sub_resource type=\"BoxShape3D\" id=\"Shape_Col_"):
			i += 1
			while i < lines.size() and lines[i] != "" and not lines[i].begins_with("["):
				i += 1
			continue
		if line.begins_with("[ext_resource type=\"ConcavePolygonShape3D\""):
			i += 1
			continue
		if line.begins_with("[node name=\"Mesh\" type=\"CollisionShape3D\" parent=\"Model/Collision\"]"):
			skipped_mesh = true
			i += 1
			if i < lines.size() and lines[i].begins_with("shape = ExtResource"):
				i += 1
			continue
		if line.begins_with("[node name=\"GameDevRoom\""):
			pass                                       # sub_resource 在下一轮统一插入
		out.append(line)
		i += 1
	for b in boxes:
		var nm := String(b["name"])
		var size: Vector3 = b["size"]
		var c: Vector3 = b["center"]
		sub_blocks.append("[sub_resource type=\"BoxShape3D\" id=\"Shape_%s\"]\nsize = Vector3(%s, %s, %s)\n" % [
			nm, _f(size.x), _f(size.y), _f(size.z)])
		node_blocks.append("[node name=\"%s\" type=\"CollisionShape3D\" parent=\"Model/Collision\"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\nshape = SubResource(\"Shape_%s\")\n" % [
			nm, _f(c.x), _f(c.y), _f(c.z), nm])
	# sub_resource 必须在第一个 [node 之前；把新块插在 GameDevRoom 之前
	var final: Array[String] = []
	for line in out:
		if line.begins_with("[node name=\"GameDevRoom\""):
			final.append_array(sub_blocks)
		final.append(line)
	# 旧的 Mesh 节点位置：把新节点插在 [node name="Collision" 之后（它下面原本就是 Mesh）
	var final2: Array[String] = []
	var inserted := false
	for line in final:
		final2.append(line)
		if not inserted and line.begins_with("[node name=\"Collision\" type=\"StaticBody3D\""):
			# 下一行起就是原 Mesh 的位置，直接塞进去
			final2.append_array(node_blocks)
			inserted = true
	if not inserted:
		print("[col] ⚠️ 场景里没有 Collision 节点，未改写")
		quit(1)
		return
	var result := "\n".join(final2)
	result = _fix_load_steps(result)
	var f := FileAccess.open(SCENE, FileAccess.WRITE)
	f.store_string(result)
	f.close()
	print("[col] 已改写 %s（旧 Mesh 节点跳过=%s）" % [SCENE, str(skipped_mesh)])
	print("[col] 回退：git checkout scenes/gamedev_room.tscn")
	quit(0)


func _clean(n: String) -> String:
	var s := n.strip_edges()
	s = s.replace("my_gamedevdept_01_", "").replace("OL_", "").replace(".", "_")
	for junk in ["_0Mat", "_1Mat", "_2Mat"]:
		s = s.replace(junk, "")
	var keep := ""
	for i in s.length():
		var ch := s[i]
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") \
				or (ch >= "0" and ch <= "9") or ch == "_":
			keep += ch
	while keep.contains("__"):
		keep = keep.replace("__", "_")
	keep = keep.trim_prefix("_").trim_suffix("_")
	return keep if keep != "" else "part"


func _f(v: float) -> String:
	var s := "%.4f" % v
	while s.contains(".") and (s.ends_with("0") or s.ends_with(".")):
		s = s.substr(0, s.length() - 1)
	return s if s != "" and s != "-" else "0"


func _fix_load_steps(text: String) -> String:
	var ext := 0
	var sub := 0
	for line in text.split("\n"):
		if line.begins_with("[ext_resource "):
			ext += 1
		elif line.begins_with("[sub_resource "):
			sub += 1
	var re := RegEx.new()
	re.compile("load_steps=(\\d+)")
	return re.sub(text, "load_steps=%d" % (ext + sub + 1), true)
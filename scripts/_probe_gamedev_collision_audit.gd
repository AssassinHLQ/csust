extends SceneTree
## 探针：把「游戏开发部（GameDevRoom）」的碰撞**实测**一遍，给一份能拿去对照的数字。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_gamedev_collision_audit.gd
##
## 和 `_probe_gamedev_collision.gd` 的分工：那份是**改造当时的验证 + 盒子/trimesh
## 物理开销对比**（提交 0930f27）；本份是**事后体检**，只描述现状、不改任何东西。
##
## 量什么：
##   ① 场景里到底有几个碰撞盒、各多大、在哪儿、在哪一层
##   ② 室内净空（世界坐标）：能不能站直、天花板多高
##   ③ 地板有没有洞（0.5 m 网格射线扫一遍）
##   ④ 四壁有没有缝（从室内中心 36 个方向 × 5 个高度往外打）
##   ⑤ 门洞到底多宽多高、人（胶囊 r=0.3 / h=1.5）能不能过去
##   ⑥ 16 件家具的碰撞盒：对得上网格吗、悬空吗、有没有堵门口
##   ⑦ 隐藏时碰撞还在不在（`visible=false` 不影响物理）
##   ⑧ 旧的 trimesh 回退件还在不在、和现在的盒子差多少
##
## ⚠️ 所有 `intersect_ray` / `intersect_shape` 都必须在 `_physics_process` 里调，
##    `_process` 里 `direct_space_state` 是拿不到的（踩过：查询全返回空，
##    看起来像「地板上没有东西」，其实是查询根本没跑）。

const ROOM := "res://scenes/gamedev_room.tscn"
const TRIMESH := "res://assets/collision/gamedev_room_trimesh.res"
## `game.tscn` 里这个实例的 transform（见该文件 `[node name="GameDevRoom"]`）
const AT := Vector3(52.0, 0.01, 0.0)
## 玩家胶囊（`scenes/player.tscn` 的 `Cap_player`）
const CAP_R := 0.3
const CAP_H := 1.5

var _room: Node3D
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(ROOM)
	if ps == null:
		print("[gd] FAIL 载不动 %s" % ROOM)
		quit(1)
		return
	_room = ps.instantiate() as Node3D
	_room.global_position = AT
	root.add_child(_room)


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false
	_audit()
	quit(0)
	return true


func _audit() -> void:
	var body := _room.get_node_or_null("Model/Collision") as StaticBody3D
	if body == null:
		print("[gd] FAIL 找不到 Model/Collision")
		return
	print("========== 游戏开发部碰撞实测 ==========")
	print("[gd] 实例位置 = %s（game.tscn 里 visible = false，成交后才露出来）" % str(AT))
	print("[gd] Model 局部旋转 = %s（绕 Y 90°：局部 (x,y,z) → 世界 (z, y, −x)）" % str(
		_room.get_node("Model").rotation_degrees.snappedf(0.1)))
	print("[gd] StaticBody3D  layer = %d  mask = %d" % [body.collision_layer, body.collision_mask])

	# ── ① 全部碰撞盒 ──
	var shapes := body.find_children("*", "CollisionShape3D", true, false)
	print("\n---------- 1. 碰撞盒清单（共 %d 个）----------" % shapes.size())
	var shell := ["Col_Floor", "Col_Ceiling", "Col_WallXNeg", "Col_WallXPos",
		"Col_WallZPos", "Col_DoorJambA", "Col_DoorJambB", "Col_DoorLintel"]
	var n_shell := 0
	var n_prop := 0
	var wall_boxes: Array[AABB] = []
	var prop_rows: Array = []
	for n in shapes:
		var cs := n as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var name := String(cs.name)
		var is_shell := name in shell
		if is_shell:
			n_shell += 1
		else:
			n_prop += 1
		var lsize := _shape_size(cs.shape)
		var wab := _world_aabb(cs)
		# 局部坐标（相对 Model）—— 判断结构面时用它更直观
		var lpos := cs.transform.origin
		if is_shell:
			wall_boxes.append(wab)
			print("  %-18s 局部 pos=(%6.2f,%6.2f,%6.2f) size=(%5.2f,%5.2f,%5.2f)"
				% [name, lpos.x, lpos.y, lpos.z, lsize.x, lsize.y, lsize.z])
		else:
			prop_rows.append([name, wab, _shape_size(cs.shape)])
	print("[gd] 结构（地/顶/墙/门框）= %d 个，家具 = %d 个" % [n_shell, n_prop])

	# ── ② 室内净空 ──
	# 结构盒按局部坐标推：X 墙内表面之间 = 横向，Z 墙内表面之间 = 纵深
	var inner := _interior()
	print("\n---------- 2. 室内净空（世界坐标）----------")
	print("[gd] x %.2f ~ %.2f（%.2f m）" % [inner.position.x, inner.end.x, inner.size.x])
	print("[gd] z %.2f ~ %.2f（%.2f m）" % [inner.position.z, inner.end.z, inner.size.z])
	print("[gd] 地面 y %.3f，天花板底 y %.2f（净高 %.2f m）"
		% [inner.position.y, inner.end.y, inner.size.y])

	var ss := _room.get_world_3d().direct_space_state

	# ── ③ 地板有没有洞 ──
	print("\n---------- 3. 地板扫描（0.5 m 网格，从上往下打）----------")
	var holes := 0
	var total := 0
	var bad: Array[String] = []
	# ⚠️ 只统计打在 `Col_Floor` 上的射线：不加过滤的话，落到桌子/储物柜顶上的
	#    射线也算进来，「地面高度区间」就会出现 0.01~2.36 这种假象
	#    （2.36 = 储物柜顶面）。地板本身必须是平的。
	var floor_hits := 0
	var not_floor := 0
	var y_min := INF
	var y_max := -INF
	var x := inner.position.x + 0.3
	while x < inner.end.x - 0.3:
		var z := inner.position.z + 0.3
		while z < inner.end.z - 0.3:
			total += 1
			var hit := _ray(ss, Vector3(x, inner.position.y + 6.2, z),
				Vector3(x, inner.position.y - 3.0, z))
			if hit.is_empty():
				holes += 1
				if bad.size() < 8:
					bad.append("(%.1f, %.1f)" % [x, z])
			else:
				var nm := _collider_name(hit)
				if nm == "Col_Floor":
					floor_hits += 1
					var hy: float = hit["position"].y
					y_min = minf(y_min, hy)
					y_max = maxf(y_max, hy)
				else:
					not_floor += 1
			z += 0.5
		x += 0.5
	print("[gd] 采样 %d 点：打到地板 %d，被家具挡住 %d，空洞 %d" % [
		total, floor_hits, not_floor, holes])
	if holes > 0:
		print("[gd]   空洞样例：%s" % ", ".join(bad))
	if floor_hits > 0:
		print("[gd] 地板顶面高度 y %.3f ~ %.3f（平不平看这个区间；家具顶面不算）"
			% [y_min, y_max])

	# ── ④ 四壁有没有缝 ──
	print("\n---------- 4. 围壁密封性（36 方向 × 5 高度，从室内中心往外打 25 m）----------")
	var c := Vector3((inner.position.x + inner.end.x) * 0.5,
		inner.position.y + 1.2, (inner.position.z + inner.end.z) * 0.5)
	var escape := {}
	var escaped := 0
	var rays := 0
	var esc_rows: Array[String] = []
	for h in [0.35, 1.20, 2.50, 4.00, 5.80]:
		for i in 36:
			var a := TAU * float(i) / 36.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			var from := Vector3(c.x, inner.position.y + float(h), c.z)
			rays += 1
			if _ray(ss, from, from + dir * 25.0).is_empty():
				escaped += 1
				var key := "%.0f°" % rad_to_deg(a)
				escape[key] = true
				esc_rows.append("%.0f° @ y+%.2f" % [rad_to_deg(a), float(h)])
	print("[gd] %d 条射线里 %d 条漏出去" % [rays, escaped])
	if escaped == 0:
		print("[gd]   四壁 + 天花板完全密封")
	else:
		print("[gd]   漏出去的位置：%s" % ", ".join(esc_rows))
		print("[gd]   （门洞在世界 x≈45.32、z 2.39~4.58、高 2.774 —— 对得上就是门，对不上就是缝）")

	# ── ⑤ 门洞 ──
	print("\n---------- 5. 门洞 ----------")
	# -Z 墙上的缺口：由两个门垛 + 过梁夹出来
	var jamb_a := _shape_box("Col_DoorJambA")
	var jamb_b := _shape_box("Col_DoorJambB")
	var lintel := _shape_box("Col_DoorLintel")
	if not jamb_a.is_empty() and not jamb_b.is_empty() and not lintel.is_empty():
		# 局部 X 轴上：A 在 −X 侧、B 在 +X 侧，缺口在两者之间
		var gap_lo: float = jamb_a["pos"].x + jamb_a["size"].x * 0.5
		var gap_hi: float = jamb_b["pos"].x - jamb_b["size"].x * 0.5
		var lintel_bottom: float = lintel["pos"].y - lintel["size"].y * 0.5
		var wall_z: float = jamb_a["pos"].z
		print("[gd] 局部：缺口 x %.3f ~ %.3f → 宽 %.3f m；过梁底 y %.3f；墙在 z %.3f"
			% [gap_lo, gap_hi, gap_hi - gap_lo, lintel_bottom, wall_z])
		# 转世界：world_x = 52 + local_z，world_z = −local_x
		print("[gd] 世界：门在 x = %.3f 这堵墙上，缺口 z %.3f ~ %.3f，门高 %.3f m"
			% [AT.x + wall_z, -gap_hi, -gap_lo, lintel_bottom])
		# 胶囊能不能穿过去
		var door_z := (-gap_hi + -gap_lo) * 0.5
		var pass_from := Vector3(inner.position.x + 1.2, inner.position.y + 0.8, door_z)
		var pass_to := pass_from + Vector3(-4.0, 0.0, 0.0)
		var ok := _capsule_can_pass(ss, pass_from, pass_to)
		print("[gd] 胶囊（r=%.2f / h=%.2f）从室内往外穿门：%s"
			% [CAP_R, CAP_H, "能过去" if ok else "过不去（被挡）"])
		# 门里有没有家具挡路（门外 2 m 到门内 2 m 这段通道）
		var corridor := AABB(Vector3(pass_to.x - 2.0, inner.position.y,
			door_z - CAP_R * 2.0), Vector3(8.0, 2.0, CAP_R * 4.0))
		var blockers: Array[String] = []
		for row in prop_rows:
			var b: AABB = row[1]
			var hit := b.intersects(corridor)
			if hit:
				blockers.append(String(row[0]))
		print("[gd] 门口通道（宽 %.1f m）里的家具碰撞盒：%s"
			% [CAP_R * 4.0, "无" if blockers.is_empty() else ", ".join(blockers)])

	# ── ⑥ 家具碰撞盒 ──
	print("\n---------- 6. 家具碰撞盒（%d 个）----------" % prop_rows.size())
	print("  （pos/size 都是**世界轴对齐包围盒**。注意 `Model` 转 90°，箱子局部 x ↔ 世界 z）")
	var floating := 0
	var outside := 0
	for row in prop_rows:
		var nm := String(row[0])
		var b: AABB = row[1]
		var above := b.position.y - inner.position.y
		var within := inner.grow(0.05).encloses(b)
		if above > 0.05:
			floating += 1
		if not within:
			outside += 1
		# 越界量：正数 = 越出多少
		var over := Vector3(
			maxf(inner.position.x - b.position.x, b.end.x - inner.end.x),
			maxf(inner.position.y - b.position.y, b.end.y - inner.end.y),
			maxf(inner.position.z - b.position.z, b.end.z - inner.end.z))
		var tag := ""
		if not within:
			tag = "  ← 越界 %s" % str(over.snappedf(0.01))
		print("  %-16s pos=(%6.2f,%5.2f,%6.2f) size=(%5.2f,%5.2f,%5.2f) 离地 %+.2f%s"
			% [nm, b.position.x, b.position.y, b.position.z,
				b.size.x, b.size.y, b.size.z, above, tag])
	print("[gd] 悬空（底面高于地板 5 cm 以上）= %d 个；越出净空 = %d 个" % [floating, outside])

	# ── ⑦ 隐藏时碰撞还在吗 ──
	print("\n---------- 7. visible = false 时碰撞还在不在 ----------")
	var probe_from := Vector3(inner.position.x - 3.0, 1.0,
		(inner.position.z + inner.end.z) * 0.5)
	var probe_to := probe_from + Vector3(8.0, 0.0, 0.0)
	_room.visible = true
	var vis_hit := not _ray(ss, probe_from, probe_to).is_empty()
	_room.visible = false
	var inv_hit := not _ray(ss, probe_from, probe_to).is_empty()
	_room.visible = true
	print("[gd] visible=true  从室外往屋里打 → %s" % ("命中（挡人）" if vis_hit else "穿过去了"))
	print("[gd] visible=false 同一根射线      → %s" % ("命中（挡人）" if inv_hit else "穿过去了"))
	if vis_hit and inv_hit:
		print("[gd] ⚠️ 结论：碰撞**不看可见性** —— 成交前这栋房子看不见，但走路照样会撞上")

	# ── ⑧ 旧 trimesh 回退件 ──
	print("\n---------- 8. 旧 trimesh 回退件 ----------")
	var st := ResourceLoader.exists(TRIMESH)
	if st:
		var sh := load(TRIMESH)
		if sh is ConcavePolygonShape3D:
			var faces := (sh as ConcavePolygonShape3D).get_faces().size()
			print("[gd] %s 在盘上：三角 %d 个（= %d 面），当前场景**没有**引用它"
				% [TRIMESH, faces, faces / 3])
		else:
			print("[gd] %s 类型是 %s" % [TRIMESH, sh.get_class()])
	else:
		print("[gd] %s 不在盘上" % TRIMESH)

	# ── ⑨ 网格 vs 碰撞 覆盖 ──
	print("\n---------- 9. 可见网格 vs 碰撞盒 ----------")
	var mesh_box := _mesh_aabb(_room.get_node_or_null("Model"))
	if mesh_box.size.length() > 0.001:
		print("[gd] 房间网格世界包围盒 pos=%s size=%s"
			% [str(mesh_box.position.snappedf(0.01)), str(mesh_box.size.snappedf(0.01))])
		var col_all := AABB()
		var first := true
		for b in wall_boxes:
			col_all = b if first else col_all.merge(b)
			first = false
		for row in prop_rows:
			var b: AABB = row[1]
			col_all = col_all.merge(b)
		print("[gd] 碰撞总包围盒     pos=%s size=%s"
			% [str(col_all.position.snappedf(0.01)), str(col_all.size.snappedf(0.01))])
		print("[gd] 差：pos %s / size %s"
			% [str((col_all.position - mesh_box.position).snappedf(0.01)),
				str((col_all.size - mesh_box.size).snappedf(0.01))])
	else:
		print("[gd] 没有网格（模型不在）—— 只有碰撞盒")


# ── 小工具 ────────────────────────────────────────────────────────────

func _shape_size(sh: Shape3D) -> Vector3:
	if sh is BoxShape3D:
		return (sh as BoxShape3D).size
	if sh is CapsuleShape3D:
		return Vector3(sh.radius * 2.0, sh.height, sh.radius * 2.0)
	return Vector3.ZERO


## 局部（相对 Model）的 pos/size
func _shape_box(nm: String) -> Dictionary:
	var cs := _room.get_node_or_null("Model/Collision/" + nm) as CollisionShape3D
	if cs == null or cs.shape == null:
		return {}
	return {"pos": cs.transform.origin, "size": _shape_size(cs.shape)}


func _world_aabb(cs: CollisionShape3D) -> AABB:
	var s := _shape_size(cs.shape)
	var xf := cs.global_transform
	var out := AABB(xf * Vector3(-s.x * 0.5, -s.y * 0.5, -s.z * 0.5), Vector3.ZERO)
	for i in 8:
		var p := Vector3(
			s.x * 0.5 if (i & 1) else -s.x * 0.5,
			s.y * 0.5 if (i & 2) else -s.y * 0.5,
			s.z * 0.5 if (i & 4) else -s.z * 0.5)
		var w := xf * p
		out = out.expand(w)
	return out


## 室内净空（世界 AABB）：用四面墙的内表面 + 地板顶面 + 天花板底面
func _interior() -> AABB:
	var f := _shape_box("Col_Floor")
	var cl := _shape_box("Col_Ceiling")
	var xn := _shape_box("Col_WallXNeg")
	var xp := _shape_box("Col_WallXPos")
	var zp := _shape_box("Col_WallZPos")
	var ja := _shape_box("Col_DoorJambA")
	var floor_top: float = AT.y + f["pos"].y + f["size"].y * 0.5
	var ceil_bot: float = AT.y + cl["pos"].y - cl["size"].y * 0.5
	# 局部 x 的内表面
	var lx_lo: float = xn["pos"].x + xn["size"].x * 0.5
	var lx_hi: float = xp["pos"].x - xp["size"].x * 0.5
	# 局部 z：-Z 墙（门垛所在的墙）与 +Z 墙的内表面
	var lz_lo: float = ja["pos"].z + ja["size"].z * 0.5
	var lz_hi: float = zp["pos"].z - zp["size"].z * 0.5
	# world_x = AT.x + local_z ；world_z = AT.z − local_x
	return AABB(
		Vector3(AT.x + lz_lo, floor_top, AT.z - lx_hi),
		Vector3(lz_hi - lz_lo, ceil_bot - floor_top, lx_hi - lx_lo))


func _ray(ss: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	return ss.intersect_ray(q)


func _capsule_can_pass(ss: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_R
	cap.height = CAP_H
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = 0xFFFFFFFF
	var r := ss.cast_motion(q)
	# cast_motion 返回 [安全比例, 不安全比例]；第一个 ≈ 1.0 表示整段畅通
	return r.size() >= 1 and float(r[0]) > 0.98


## 只统计 **MeshInstance3D**：`Model` 下还挂着 OmniLight3D 和 Label3D，
## 它们也是 `VisualInstance3D`，`get_aabb()` 给的是灯的范围球/文字方块，
## 混进来会把包围盒撑到 25 m（房间本体只有 13.7 m）。
func _mesh_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	if node == null:
		return out
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var b := mi.get_aabb()
				if b.size.length() > 0.0001:
					var wb := mi.global_transform * b
					out = wb if first else out.merge(wb)
					first = false
		for ch in n.get_children():
			stack.append(ch)
	return out


## 射线到底打中了哪个**形状**。
##
## ⚠️ 不能只看 `hit["collider"]`：这里 24 个形状全挂在**同一个** `StaticBody3D`
##    下面，`hit["collider"]` 永远是那个 body。真正的形状索引在 `hit["shape"]`，
##    要经 `shape_find_owner()` 反查回 `CollisionShape3D` 节点。
##    （踩过：直接取第一个子节点，结果 525 条射线全被记成 `Col_shelf_03`）
func _collider_name(hit: Dictionary) -> String:
	var body := hit.get("collider") as CollisionObject3D
	if body == null:
		return "?"
	var idx: int = int(hit.get("shape", -1))
	if idx < 0:
		return String(body.name)
	var owner_id := body.shape_find_owner(idx)
	if owner_id < 0:
		return String(body.name)
	var node := body.shape_owner_get_owner(owner_id)
	return String(node.name) if node != null else String(body.name)

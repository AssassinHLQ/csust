extends SceneTree
## 验「网格小屋」`scenes/mesh_hut.tscn`（记忆平台上的第三块场地）：
##   1. 场景与结构：节点都在、CSG 的布尔顺序对、整份场景只用了一个网格资源
##   2. 网格纪律：所有位置与尺寸都落在 GRID 网格上（这是「网格化搭建」的可执行定义）
##   3. **门洞能走、墙能挡** —— 用真玩家的胶囊做 shape cast，并带一条反向对照
##   4. 不与既有东西打架：画室609 的**真旋转矩形**、两位 Boss、柱子、靶子、自检弹道
##   5. 子弹挡得住、门是通的；两盏灯都没开阴影
##
## 用法：
##   godot --path <工程> --script res://scripts/_verify_mesh_hut.gd
##
## ⚠️ **不要加 `--splat=off`**（和别的套件相反）：第 4 节要画室609 的**真实**
##    footprint，那是 `content_min/max` 算出来的 —— 不加载泼溅就是零，整节变成空跑。
##    代价是首次解码 277 万点（约 21 s，有缓存约 2 s）。
##
## ⚠️ shape cast 用的是**抬起来 5 cm 的胶囊**：真玩家的胶囊底面正好贴在地面 y = 0 上，
##    一放上去就和地板接触，`cast_motion()` 会立刻返回 0，什么都验不出来。
##    抬 5 cm 就能只量「水平方向有没有东西挡路」。第 3 节的反向对照（放一个 10 cm
##    的坎）证明这个量法真的测得出来。

const HUT_SCENE := "res://scenes/mesh_hut.tscn"
const HUT_NAME := "MeshHut"
## 期望的落点。改位置必须同时改这里 + `game.tscn` + 重跑 `_probe_platform_free.gd`
const EXPECT_POS := Vector3(14, 0, -15.5)
## 「网格化搭建」的网格边长
const GRID := 0.05
## 与既有障碍物之间至少要留的净距
const CLEAR := 1.0
## 平台半边长
const HALF := 20.0
## 玩家胶囊（抄 scenes/player.tscn 的 Cap_player：radius 0.3 / height 1.5）
const CAP_RADIUS := 0.3
const CAP_HEIGHT := 1.5
## 走道：门洞中心线左右各这么宽要空着（家具不许摆进去）
const LANE_HALF := 0.9

var _fail := 0
var _pass := 0
var _space: PhysicsDirectSpaceState3D
var _exclude: Array[RID] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	_space = root.world_3d.direct_space_state
	for n in ["Player", "CompanionMika", "CompanionYuuka", "CompanionNoa",
			"CompanionMomoi", "CompanionMidori", "CompanionYuzu", "CompanionKei"]:
		var c := game.get_node_or_null(n) as CollisionObject3D
		if c != null:
			_exclude.append(c.get_rid())

	# 画室的真实占位要等泼溅解码完
	var room: SplatScene = game.get_node_or_null("Room609") as SplatScene
	var guard := 0
	while guard < 60000 and (room == null or not room.is_ready()):
		await process_frame
		guard += 1

	var hut: Node3D = game.get_node_or_null(HUT_NAME) as Node3D
	_test_structure(game, hut)
	_test_grid(hut)
	# ⚠️ 一定要 await：`_test_walkway` 里有 await（等物理帧），
	#    不 await 的话它是个协程 —— 跑到第一个 await 就把控制权交回来，
	#    后面三条检查会**永远轮不到**（本喵第一版就是这样，白丢三条）。
	await _test_walkway(hut)
	_test_no_clash(game, hut, room)
	_test_bullets_and_lights(hut)
	await _wait(2)

	print("\n================ 结果 ================")
	print("通过 %d 项" % _pass)
	_quit()


# --- 1. 场景与结构 -----------------------------------------------------------

func _test_structure(game: Node, hut: Node3D) -> void:
	print("========== 1. 场景与结构 ==========")
	_check(FileAccess.file_exists(HUT_SCENE), "场景文件在 %s" % HUT_SCENE)
	_check(hut != null, "game.tscn 里有 %s" % HUT_NAME)
	if hut == null:
		return
	_check(hut.global_position.distance_to(EXPECT_POS) < 1e-3,
		"落点 = %s（实测 %s）" % [str(EXPECT_POS), str(hut.global_position.snappedf(0.01))])

	var csg := hut.get_node_or_null("Hut") as CSGCombiner3D
	_check(csg != null, "屋壳 Hut 是 CSGCombiner3D")
	if csg == null:
		return
	# ⚠️ CSG 的碰撞默认是**关**的，忘了开就等于房子能穿墙
	_check(csg.use_collision, "屋壳开了 use_collision（CSG 的碰撞默认是关的）")

	var kinds := {}
	var subs := 0
	for c in csg.get_children():
		var op := int((c as CSGShape3D).operation)
		kinds[op] = int(kinds.get(op, 0)) + 1
		if op == CSGShape3D.OPERATION_SUBTRACTION:
			subs += 1
	_check(csg.get_child_count() == 7, "屋壳 7 个子节点（实测 %d）" % csg.get_child_count())
	_check(subs == 4, "其中 4 个是 SUBTRACTION：掏空 + 门 + 两窗（实测 %d）" % subs)
	_check(int(kinds.get(CSGShape3D.OPERATION_UNION, 0)) == 3,
		"3 个 UNION：外壳 + 屋顶 + 雨篷")

	# 布尔顺序：**掏空必须排在屋顶/雨篷之前**。顺序错了不会崩、模型也还在，
	# 只是屋顶中间会多一个和屋子一样大的洞（在编辑器里相当不显眼），所以两头都验：
	# 先看子节点下标，再用一条**垂直射线**看屋顶到底通不通。
	var idx := {}
	for i in csg.get_child_count():
		idx[String(csg.get_child(i).name)] = i
	_check(int(idx.get("Cavity", 99)) < int(idx.get("Roof", -1)) \
		and int(idx.get("Cavity", 99)) < int(idx.get("Canopy", -1)),
		"掏空排在屋顶/雨篷之前（子节点下标 %d < %d / %d）"
		% [int(idx.get("Cavity", 99)), int(idx.get("Roof", -1)), int(idx.get("Canopy", -1))])
	_check(int(idx.get("Door", -1)) > int(idx.get("Walls", 99)) \
		and int(idx.get("WindowA", -1)) > int(idx.get("Walls", 99)) \
		and int(idx.get("WindowB", -1)) > int(idx.get("Walls", 99)),
		"门与两窗排在外壳之后（挖了才有用）")

	var roof := csg.get_node_or_null("Roof") as CSGBox3D
	var want_y := hut.global_position.y + roof.position.y + roof.size.y * 0.5
	var down := _ray(hut.global_position + Vector3(0, 6, 0), hut.global_position)
	var roof_y := Vector3(down["position"]).y if not down.is_empty() else -99.0
	_check(absf(roof_y - want_y) < 0.05,
		"从正上方垂直往下打，先被屋顶挡住（命中 y = %.2f，屋顶顶面 y = %.2f）→ 屋顶没有洞"
		% [roof_y, want_y])

	# 整份场景只有一个箱体网格资源 —— 「网格化搭建」的另一半定义
	var meshes := {}
	var cylinders := 0
	for n in _all(hut, "MeshInstance3D"):
		var m := (n as MeshInstance3D).mesh
		if m is CylinderMesh:
			cylinders += 1
			continue
		meshes[m.get_rid()] = true
	_check(meshes.size() == 1, "所有方块共用同一个 BoxMesh（实测 %d 种）" % meshes.size())
	_check(cylinders == 1, "只有灯柱用了圆柱（实测 %d 个）" % cylinders)

	var door := csg.get_node_or_null("Door") as CSGBox3D
	_check(door != null and door.size.z >= 1.1 and door.size.y >= 2.1,
		"门洞 ≥ 1.1 宽 × 2.1 高（实测 %.2f × %.2f）"
		% [door.size.z if door else 0.0, door.size.y if door else 0.0])

	# 屋壳**不许有地板**：抬高的地板就是台阶，CharacterBody3D 不会自己上台阶
	var cavity := csg.get_node_or_null("Cavity") as CSGBox3D
	var walls := csg.get_node_or_null("Walls") as CSGBox3D
	var floor_y := cavity.position.y - cavity.size.y * 0.5
	_check(cavity != null and walls != null and floor_y < walls.position.y - walls.size.y * 0.5,
		"掏空捅穿了外壳底面（掏空底 y = %.2f < 外壳底 y = %.2f）→ 没有地板、也就没有台阶"
		% [floor_y, walls.position.y - walls.size.y * 0.5 if walls else 0.0])


# --- 2. 网格纪律 -------------------------------------------------------------

## 「网格化搭建」的可执行定义：**每个位置、每个尺寸都落在 GRID 上**。
## 这条不是为了好看 —— 手工改这个 .tscn 时，它能把「1.5234 这种手滑」当场抓出来。
func _test_grid(hut: Node3D) -> void:
	print("\n========== 2. 网格纪律（%.2f m）==========" % GRID)
	if hut == null:
		return
	var bad_pos: Array[String] = []
	var bad_size: Array[String] = []
	var nodes := 0
	var sizes := 0
	for n in _all(hut, "Node3D"):
		nodes += 1
		if not _on_grid((n as Node3D).position):
			bad_pos.append("%s %s" % [n.name, str((n as Node3D).position)])
		var v := _box_size(n)
		if v != Vector3.INF:
			sizes += 1
			if not _on_grid(v):
				bad_size.append("%s %s" % [n.name, str(v)])
	_check(bad_pos.is_empty(), "%d 个节点的 position 都在网格上%s"
		% [nodes, "" if bad_pos.is_empty() else "（越界：%s）" % str(bad_pos)])
	_check(bad_size.is_empty(), "%d 个箱体尺寸都在网格上%s"
		% [sizes, "" if bad_size.is_empty() else "（越界：%s）" % str(bad_size)])


# --- 3. 门能走、墙能挡 -------------------------------------------------------

func _test_walkway(hut: Node3D) -> void:
	print("\n========== 3. 门洞能走、墙能挡（真胶囊 shape cast）==========")
	if hut == null:
		return
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_RADIUS
	cap.height = CAP_HEIGHT
	var y := CAP_HEIGHT * 0.5 + 0.05          # 抬 5 cm，别让地板参与
	var out_x := hut.global_position.x - 6.0
	var in_x := hut.global_position.x - 1.0
	var z := hut.global_position.z

	var f := _cast_fraction(cap, Vector3(out_x, y, z), Vector3(in_x - out_x, 0, 0))
	_check(is_equal_approx(f, 1.0),
		"从门外 (%.1f, %.1f) 直着走进屋，一路无阻（safe = %.3f）" % [out_x, z, f])

	# 反向对照：临时在门口放一道 10 cm 的坎，同一条路必须**走不通**。
	# 没有这一条，上面那条「走过去是通的」可能只是「什么都没量到」。
	var lip := StaticBody3D.new()
	var lip_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.1, 1.6)
	lip_shape.shape = box
	lip.add_child(lip_shape)
	root.add_child(lip)
	lip.global_position = Vector3(hut.global_position.x - 3.3, 0.05, z)
	await _wait(3)
	var f2 := _cast_fraction(cap, Vector3(out_x, y, z), Vector3(in_x - out_x, 0, 0))
	_check(f2 < 1.0, "反向对照：门口放一道 10 cm 的坎 → 走不进去了（safe = %.3f）" % f2)
	lip.free()
	await _wait(3)

	# 朝实墙走：+Z 墙的 x = 局部 +2.00 处（避开窗洞）
	var wx := hut.global_position.x + 2.0
	var wz := hut.global_position.z + 6.0
	var f3 := _cast_fraction(cap, Vector3(wx, y, wz), Vector3(0, 0, -4.0))
	_check(f3 < 1.0, "朝 +Z 实墙走（x = %.1f，避开了窗）→ 被挡住（safe = %.3f）" % [wx, f3])

	# 走道里不许有家具：门洞中心线左右各 LANE_HALF 的带状区内，不许有家具碰撞盒
	var lane := AABB(Vector3(-3.1, 0.0, -LANE_HALF), Vector3(6.2, 3.0, LANE_HALF * 2.0))
	var hit: Array[String] = []
	for n in _all(hut.get_node_or_null("FurnitureBody"), "CollisionShape3D"):
		var b := _world_aabb(n as Node3D)
		if b.intersects(lane):
			hit.append(String(n.name))
	for n in _all(hut.get_node_or_null("Crates"), "CollisionShape3D"):
		var b := _world_aabb(n as Node3D)
		if b.intersects(lane):
			hit.append(String(n.name))
	_check(hit.is_empty(),
		"门正对着的走道（局部 z ∈ [−%.1f, %.1f]）里没有家具%s"
		% [LANE_HALF, LANE_HALF, "" if hit.is_empty() else "（挡路的：%s）" % str(hit)])


# --- 4. 不和既有东西打架 -----------------------------------------------------

func _test_no_clash(game: Node, hut: Node3D, room: SplatScene) -> void:
	print("\n========== 4. 不和既有东西打架 ==========")
	if hut == null:
		return
	var mine := _hut_aabb(hut)
	print("  小屋世界 AABB：x [%.2f, %.2f]  z [%.2f, %.2f]  y [%.2f, %.2f]" % [
		mine.position.x, mine.position.x + mine.size.x,
		mine.position.z, mine.position.z + mine.size.z,
		mine.position.y, mine.position.y + mine.size.y])

	# 画室609：用**真旋转矩形**判交（不是包围盒 —— 包围盒比房间自己大一圈）
	var poly := _room_poly(room)
	if poly.size() == 4:
		var mn := Vector2(mine.position.x, mine.position.z)
		var mx := mn + Vector2(mine.size.x, mine.size.z)
		_check(_separated(mn, mx, poly), "与画室609 的真旋转矩形不相交（净距 %.2f m）"
			% _gap_box_poly(mn, mx, poly))
	else:
		_check(false, "拿不到画室609 的 footprint（泼溅没加载？本套件不能加 --splat=off）")

	# Boss / 柱子 / 靶子：净距 ≥ CLEAR
	var worst := INF
	var who := ""
	for path in ["Boss", "BossPig", "Pillar1", "Pillar2", "Pillar3",
			"Target1", "Target2", "Target3", "Target4", "Target5"]:
		var col := game.get_node_or_null("%s/Collision" % path) as Node3D
		if col == null:
			continue
		var g := _gap_aabb(mine, _world_aabb(col))
		if g < worst:
			worst = g
			who = path
	_check(worst >= CLEAR, "与 Boss / 柱子 / 靶子的最小净距 %.2f m ≥ %.1f（最近的是 %s）"
		% [worst, CLEAR, who])

	# 那条自检弹道（§7.3 的教训：猪猪当初摆在 x = 9 就吃掉了它）
	var shot := AABB(Vector3(5.4, 0.0, -10.6), Vector3(1.2, 2.0, 7.2))
	_check(not mine.intersects(shot), "没有挡住自检弹道「玩家(6,−4) → 靶1(6,−10)」")

	# 全部落在平台里，别挂在半空
	var inside := mine.position.x > -HALF and mine.position.x + mine.size.x < HALF \
		and mine.position.z > -HALF and mine.position.z + mine.size.z < HALF
	_check(inside, "整块都在 40 × 40 的平台内（x [%.2f, %.2f]、z [%.2f, %.2f]）" % [
		mine.position.x, mine.position.x + mine.size.x,
		mine.position.z, mine.position.z + mine.size.z])
	# 下界放到 −0.05：室内地面那块薄板（无碰撞）中心在 y = 0、厚 0.05，
	# 底边自然落在 −0.025，是**故意**的（见 mesh_hut.tscn 里那段注释）。
	_check(mine.position.y >= -0.05 and mine.position.y + mine.size.y < 4.0,
		"站在地面上、不埋进地板也不超高（y [%.2f, %.2f]）"
		% [mine.position.y, mine.position.y + mine.size.y])


# --- 5. 子弹与灯 -------------------------------------------------------------

func _test_bullets_and_lights(hut: Node3D) -> void:
	print("\n========== 5. 子弹挡得住、门是通的 ==========")
	if hut == null:
		return
	var p := hut.global_position

	# ① 朝墙打：必须命中 MeshHut 的东西
	var hit := _ray(Vector3(p.x + 2.0, 1.0, p.z + 6.0), Vector3(p.x + 2.0, 1.0, p.z + 2.0))
	_check(not hit.is_empty(), "朝 +Z 墙开枪 → 打中了东西")
	if not hit.is_empty():
		var col: Object = hit["collider"]
		var ok := col is Node and hut.is_ancestor_of(col as Node)
		_check(ok, "打中的确实是小屋（collider = %s）"
			% ((col as Node).get_path() if col is Node else str(col)))

	# ② 沿门洞中心线（y = 1.0）从门外往里打：应该**穿过门**、打到屋子里面的后墙
	var h2 := _ray(Vector3(p.x - 8.0, 1.0, p.z), Vector3(p.x + 4.0, 1.0, p.z))
	var deep := not h2.is_empty() and Vector3(h2["position"]).x > p.x + 1.0
	_check(deep, "沿门洞中心线打进去 → 穿过了门（命中点 x = %.2f > %.2f）"
		% [Vector3(h2["position"]).x if not h2.is_empty() else 0.0, p.x + 1.0])

	# ③ 同一方向、抬到门楣高度（y = 2.6）：必须打在墙上
	var h3 := _ray(Vector3(p.x - 8.0, 2.6, p.z), Vector3(p.x + 4.0, 2.6, p.z))
	var early := not h3.is_empty() and Vector3(h3["position"]).x < p.x - 2.0
	_check(early, "抬到门楣高度（y = 2.6）再打 → 打在墙上（命中点 x = %.2f）"
		% [Vector3(h3["position"]).x if not h3.is_empty() else 0.0])

	var lights := 0
	var shadowed := 0
	for n in _all(hut, "OmniLight3D"):
		lights += 1
		if (n as OmniLight3D).shadow_enabled:
			shadowed += 1
	_check(lights == 2 and shadowed == 0,
		"%d 盏灯、%d 盏开了阴影（本项目对功耗敏感，都关着）" % [lights, shadowed])


# --- 几何工具 -----------------------------------------------------------------

## 节点位置是不是落在网格上
func _on_grid(v: Vector3) -> bool:
	for x in [v.x, v.y, v.z]:
		if absf(float(x) / GRID - roundf(float(x) / GRID)) > 1e-3:
			return false
	return true


## 取节点的「箱体尺寸」；不是方块就返回 INF（圆柱不在网格检查范围内）
func _box_size(n: Node) -> Vector3:
	if n is CSGBox3D:
		return (n as CSGBox3D).size
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh is BoxMesh:
			return mi.scale * (mi.mesh as BoxMesh).size
		return Vector3.INF
	if n is CollisionShape3D and (n as CollisionShape3D).shape is BoxShape3D:
		return (n as CollisionShape3D).shape.size
	return Vector3.INF


## 小屋整体的世界 AABB。
##
## ⚠️ 只收**几何**（MeshInstance3D / CSGCombiner3D / CollisionShape3D）：
##   · **不收 `CSGBox3D`** —— 那些是布尔运算的原料（掏空盒比屋子还大、还捅到地下
##     0.2 m），不是看得见的几何。结果盒由根 `CSGCombiner3D` 一个节点代表。
##   · **不收 `Light3D`** —— 它是 `VisualInstance3D`，`get_aabb()` 返回的是
##     **光照影响范围**（omni_range 14 → 28 m 的立方体）。本喵第一版收进来了，
##     于是小屋的包围盒变成 x ∈ [−4.2, 23.8]、y ∈ [−10.8, 17.2]，后面四条断言
##     集体假红。
func _hut_aabb(hut: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in _all(hut, "Node3D"):
		if n is CSGBox3D or n is Light3D:
			continue
		if not (n is MeshInstance3D or n is CSGCombiner3D or n is CollisionShape3D):
			continue
		var b := _world_aabb(n)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


func _world_aabb(n: Node3D) -> AABB:
	if n is GeometryInstance3D:
		return (n as GeometryInstance3D).global_transform * (n as GeometryInstance3D).get_aabb()
	if n is CollisionShape3D:
		var cs := n as CollisionShape3D
		var s := cs.shape
		if s is BoxShape3D:
			var sz := (s as BoxShape3D).size
			return cs.global_transform * AABB(-sz * 0.5, sz)
		if s is CylinderShape3D:
			var c := s as CylinderShape3D
			var r := maxf(c.top_radius, c.bottom_radius)
			return cs.global_transform * AABB(Vector3(-r, -c.height * 0.5, -r),
				Vector3(r * 2, c.height, r * 2))
	return AABB()


func _gap_aabb(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - (b.position.x + b.size.x),
		b.position.x - (a.position.x + a.size.x)))
	var dz := maxf(0.0, maxf(a.position.z - (b.position.z + b.size.z),
		b.position.z - (a.position.z + a.size.z)))
	return sqrt(dx * dx + dz * dz)


## 画室地板在世界空间的 4 个角（真旋转矩形）。算法与 game.gd 的挖洞同源。
func _room_poly(room: SplatScene) -> PackedVector2Array:
	var out := PackedVector2Array()
	if room == null or room.splat_node == null:
		return out
	var xf := room.global_transform * room.splat_node.transform
	var a := room.content_min
	var b := room.content_max
	for c in [Vector2(a.x, a.z), Vector2(b.x, a.z), Vector2(b.x, b.z), Vector2(a.x, b.z)]:
		var w: Vector3 = xf * Vector3(c.x, 0.0, c.y)
		out.append(Vector2(w.x, w.z))
	return out


## 分离轴：轴对齐矩形与凸多边形是否分离（探针 `_probe_platform_free.gd` 同一套算法）
func _separated(mn: Vector2, mx: Vector2, poly: PackedVector2Array) -> bool:
	var axes: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1)]
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		var n := Vector2(-e.y, e.x)
		if n.length_squared() > 1e-12:
			axes.append(n.normalized())
	var mine := [mn, Vector2(mx.x, mn.y), mx, Vector2(mn.x, mx.y)]
	for ax in axes:
		var a0 := INF
		var a1 := -INF
		for p in mine:
			var v: float = p.dot(ax)
			a0 = minf(a0, v)
			a1 = maxf(a1, v)
		var b0 := INF
		var b1 := -INF
		for p in poly:
			var v: float = p.dot(ax)
			b0 = minf(b0, v)
			b1 = maxf(b1, v)
		if a1 < b0 or b1 < a0:
			return true
	return false


func _gap_box_poly(mn: Vector2, mx: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for p in [mn, Vector2(mx.x, mn.y), mx, Vector2(mn.x, mx.y)]:
		best = minf(best, _dist_point_poly(p, poly))
	for p in poly:
		best = minf(best, p.distance_to(
			Vector2(clampf(p.x, mn.x, mx.x), clampf(p.y, mn.y, mx.y))))
	return best


func _dist_point_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, _dist_point_seg(p, poly[i], poly[(i + 1) % poly.size()]))
	return best


func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


# --- 物理查询 -----------------------------------------------------------------

## 胶囊沿 motion 平移，返回**安全比例**（1.0 = 一路无阻）。
## `cast_motion` 返回 [safe, unsafe]：safe 是第一个「撞上且滑不过去」的位置比例。
func _cast_fraction(shape: Shape3D, from: Vector3, motion: Vector3) -> float:
	var p := PhysicsShapeQueryParameters3D.new()
	p.shape = shape
	p.transform = Transform3D(Basis.IDENTITY, from)
	p.motion = motion
	p.collision_mask = 1
	p.exclude = _exclude
	var r := _space.cast_motion(p)
	return float(r[0]) if r.size() > 0 else 1.0


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var p := PhysicsRayQueryParameters3D.create(from, to)
	p.collision_mask = 1
	p.exclude = _exclude
	return _space.intersect_ray(p)


# --- 工具 ---------------------------------------------------------------------

## 递归收某类型的后代（不含自己）
func _all(root_node: Node, cls: String) -> Array:
	var out: Array = []
	if root_node == null:
		return out
	for c in root_node.get_children():
		if c.is_class(cls):
			out.append(c)
		out.append_array(_all(c, cls))
	return out


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if cond:
		_pass += 1
	else:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

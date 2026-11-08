extends SceneTree
## 探针：用户问「为什么墙没了」——先定位**是哪一间房**，再判断墙到底存不存在。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_which_room.gd
##
## 思路：截图 HUD 上写着 `位置 (1.14, 1.18, 2.59)`，那就是玩家胶囊中心。
##   ① 把 game.tscn 里**所有** MeshInstance3D 的全局 AABB 算出来，
##      看哪些盒子把玩家包在里面 —— 那个子树就是「玩家所在的房间」。
##   ② 把该子树的网格逐个列出来（名字 + 全局 AABB + 可见性 + 材质），
##      四堵墙缺哪堵、还是被隐藏/透明，一眼能看出来。
##   ③ 顺便把所有顶层子节点的位置打一遍，方便对照用户截图里的广场。
##
## ⚠️ `@tool` 脚本与 `_ready` 里的运行时加载（gamedev_room.gd 挂 glb）都要等几帧。

const GAME := "res://scenes/game.tscn"
## 用户截图的 HUD：位置 (1.14, 1.18, 2.59)
const P := Vector3(1.14, 1.18, 2.59)

var _frames := 0
var _root: Node3D


func _initialize() -> void:
	var ps: PackedScene = load(GAME)
	if ps == null:
		print("[room] FAIL 载不动 %s" % GAME)
		quit(1)
		return
	_root = ps.instantiate() as Node3D
	root.add_child(_root)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 6:
		return false

	print("\n========== 0. 顶层子节点（名字 / 全局位置 / 子树网格 AABB）==========")
	for c in _root.get_children():
		if not (c is Node3D):
			print("  %-24s  (非 Node3D: %s)" % [c.name, c.get_class()])
			continue
		var n3 := c as Node3D
		var bb := _walk(n3, n3.global_transform)
		print("  %-24s pos=%-28s meshAABB=%s" % [
			c.name, _v(n3.global_position), _aabb(bb)])

	print("\n========== 1. 谁把玩家包住了（全局 AABB 含点 %s）==========" % _v(P))
	var hits: Array = []
	_containers(_root, hits)
	if hits.is_empty():
		print("  （没有网格包住这个点 —— 玩家站在空地上，或模型没加载）")
	for path in hits:
		print("  ✔ %s" % path)

	print("\n========== 2. 玩家所在子树逐网格 ==========")
	if not hits.is_empty():
		var first: String = hits[0]
		var owner_path := first.split("/")[0]
		var node := _root.get_node_or_null(owner_path)
		if node != null:
			_dump_meshes(node)

	quit(0)
	return true


## 递归求子树网格包围盒（纯世界空间）
func _walk(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.visible:
			out = xf * mi.get_aabb()
			first = false
	for ch in n.get_children():
		var cxf := xf
		if ch is Node3D:
			cxf = (ch as Node3D).global_transform
		var cb := _walk(ch, cxf)
		if cb.size == Vector3.ZERO:
			continue
		out = cb if first else out.merge(cb)
		first = false
	return out


## 找出包含 P 的所有 MeshInstance3D（打完整路径）
func _containers(n: Node, hits: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var bb: AABB = mi.global_transform * mi.get_aabb()
			if bb.has_point(P):
				hits.append(str(_root.get_path_to(mi)))
	for ch in n.get_children():
		_containers(ch, hits)


## 列出一个子树的全部网格
func _dump_meshes(n: Node) -> void:
	var cnt := 0
	var hidden := 0
	var rows := []
	_collect(n, rows, [0])
	for r in rows:
		var mi: MeshInstance3D = r[0]
		cnt += 1
		if not mi.visible:
			hidden += 1
		if cnt <= 90:
			var bb: AABB = mi.global_transform * mi.get_aabb()
			print("  %-46s vis=%-5s AABB=%s" % [
				r[1], str(mi.visible), _aabb(bb)])
			for s in range(mi.mesh.get_surface_count()):
				var m: Material = mi.get_active_material(s)
				var extra := ""
				if m is BaseMaterial3D:
					var b := m as BaseMaterial3D
					extra = " alpha=%.2f transp=%d cull=%d" % [
						b.albedo_color.a, b.transparency, b.cull_mode]
				elif m == null:
					extra = " (无材质)"
				print("        surf%d %s%s" % [s, m.get_class() if m else "null", extra])
	print("  —— 合计 %d 个网格，其中 visible=false %d 个" % [cnt, hidden])


func _collect(n: Node, rows: Array, _d: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		rows.append([n, str(_root.get_path_to(n))])
	for ch in n.get_children():
		_collect(ch, rows, _d)


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _aabb(b: AABB) -> String:
	if b.size == Vector3.ZERO:
		return "空"
	return "x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f" % [
		b.position.x, b.position.x + b.size.x,
		b.position.y, b.position.y + b.size.y,
		b.position.z, b.position.z + b.size.z]

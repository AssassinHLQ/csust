class_name RenderDistance
extends Node
## 渲染距离（Minecraft 式）：远处的物体**不渲染、不进视锥**，近的照常。
##
## ── 用户的原话（2026-10-22 计划第 2 条）──
##   「设置渲染距离，参考 Minecraft。渲染距离以外的物体、生物不加载
##    （假如该物体或生物一部分包含在渲染距离内也需加载）。」
##   参数本身在 `game_settings.gd` 的 `render_distance` / `render_distance()`。
##
## ── 这套实现怎么判「在不在里面」──
##   每个「簇」预存 **包围球**（球心 + 半径）。判据是
##       dist(摄像机, 球心) − 半径  >  渲染距离        → 裁掉
##   即**球的最近点**比渲染距离还远才裁 —— 正好是用户要的「一部分包含在内也需加载」。
##   用球不用盒子：球一定套住盒子（偏保守，宁可多显示一点），但算起来只有一个减法。
##
## ── 为什么要「切簇」而不是逐个网格 ──
##   1. 逐个网格切会把**蒙皮模型切碎**（同伴的头发/裙子是十几个独立网格，
##      各自 `visible` 会在边缘闪）；
##   2. 但整棵 `Parkour`（600 m 长）当一个簇又永远不会被裁。
##   所以用「**递归切到对角 ≤ 60 m 为止**」：小屋/商店/一只角色各是一个簇，
##   600 m 的跑酷路线被自动切成沿路几十个小簇。阈值见 `CLUSTER_DIAGONAL`。
##
## ── 「不加载」到什么程度（诚实版）──
##   本节点做的是 **不渲染**（`visible = false`）：网格不进渲染、不投阴影。
##   但节点**还在树里**，内存和显存不会掉。真正的「不加载」需要把
##   `scenes/parkour.tscn` 这类子树在运行时 `queue_free()` 再按需实例化，
##   那是下一期的事（`Game/Parkour` 本来就是 `parkour.tscn` 的实例，
##   所以不用改 `game.tscn` 也能做，但会重置跑酷进度，得先跟用户确认）。
##
## ── 只碰「我们自己藏起来的」（`_hidden`）──
##   跑酷的移动平台/发射台会自己改 `visible`；房间代理/泼溅更是**每帧**被
##   `game.gd::_update_room_swap()` 改。所以本节点**绝不主动把东西设成可见**：
##      · 想显示 → 只把 `_hidden` 里记着的放回去，没藏过的一律不碰
##      · 想裁掉 → 记下它当时的 `visible` 再设 `false`
##
##   ⚠️ 2026-10-22 的教训（用户：「初始房间的画室高斯泼溅呢」）：第一版是
##      「每个簇记一次 `_authored`，之后每 tick 恢复那个值」—— 于是
##      `RoomProxy` 在开机剧本里被记成 `true`，`RenderDistance._process` 又排在
##      `game._process` **后面**（父节点先跑），每 0.1 s 把
##      `_update_room_swap()` 刚藏掉的方盒房间代理写回 `true`，
##      玩家站在屋里看到的永远是那个米色盒子、泼溅被它整块挡住。
##      「恢复原值」和「每帧都写」凑在一起就是这个结果，所以改成只恢复自己藏的。

## 一个簇的包围盒对角线上限（m）。60 m ≈ 跑酷路线里两个检查点之间，
## 也远大于商店（对角 ≈ 15 m）和任何一只角色（≈ 2 m），所以它们各自成簇。
const CLUSTER_DIAGONAL := 60.0
## 递归深度上限：防止病态的深层链把栈吃穿
const MAX_DEPTH := 16
## 判据刷新频率（10 Hz）。每帧算也行，但人走路时 0.1 s 的滞后完全看不出来，
## 而 `_apply()` 在簇多的时候是纯 GDScript 循环，10 Hz 更省。
const TICK := 0.1

var clusters: Array = []
var root: Node3D
## 上次算出来的统计（探针/日志用）：{clusters, meshes, visible_clusters, visible_meshes, distance}
var stats := {}

var _acc := 0.0
## 我们**压下去的**簇：id → 压之前它自己的 `visible`（可能是 `false`，见文件头）
var _hidden := {}
var _last_key := ""


## 挂到 `game` 上并切好簇。**调用时机要在场景基本建完之后**
## （商店是 `_build_shop()` 里代码建的，所以 `game.gd` 在商店建好后会再 `rebuild()` 一次）。
func watch(game: Node3D) -> void:
	root = game
	set_process(true)
	rebuild()


func rebuild() -> void:
	# 重建之前先把藏起来的放回去，否则那些簇会永远停在 `visible = false`
	if not _hidden.is_empty():
		_restore_hidden()
	clusters.clear()
	if root != null:
		_collect(root, 0)
	var meshes := 0
	for c in clusters:
		meshes += int(c["meshes"])
	print("[距离] 裁切簇 %d 个，覆盖网格 %d 个（每簇对角 ≤ %.0f m）"
		% [clusters.size(), meshes, CLUSTER_DIAGONAL])
	_apply(0.0, true)


## 立刻按当前渲染距离重算一次（设置一改就调，别等下一个 tick）
func refresh() -> void:
	if root == null:
		rebuild()
		return
	_apply(0.0, true)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	_apply(_acc, false)
	_acc = 0.0


func _apply(_dt: float, force: bool) -> void:
	var cam := _camera()
	if cam == null or clusters.is_empty():
		return
	var far := GameSettings.render_distance()
	var cam_pos := cam.global_position
	var visible_clusters := 0
	var visible_meshes := 0
	for c in clusters:
		var node: Node3D = c["node"]
		if not is_instance_valid(node):
			continue
		var radius: float = c["radius"]
		# 现算世界盒子（节点可能是会动的角色），球心取盒子中心
		var world_aabb: AABB = node.global_transform * (c["local_aabb"] as AABB)
		var center := world_aabb.get_center()
		# 球的最近点到摄像机的距离；负值（摄像机在球内）直接算 0
		var d := maxf(0.0, center.distance_to(cam_pos) - radius)
		var show := d <= far
		if show:
			visible_clusters += 1
			visible_meshes += int(c["meshes"])
		var id := node.get_instance_id()
		if show:
			# 只放回**我们自己藏的**；没藏过的簇一概不碰（它有可能是游戏自己在管）
			if _hidden.has(id):
				var authored: bool = bool(_hidden[id])
				_hidden.erase(id)
				if node.visible != authored:
					node.visible = authored
		else:
			if not _hidden.has(id):
				_hidden[id] = node.visible
			if node.visible:
				node.visible = false
	stats = {
		"clusters": clusters.size(),
		"meshes": _total_meshes(),
		"visible_clusters": visible_clusters,
		"visible_meshes": visible_meshes,
		"distance": far,
	}
	# 只在「渲染距离变了」或首次时打日志，别每 0.1 s 刷屏
	var key := "%d/%.0f/%d" % [visible_clusters, far, visible_meshes]
	if force or key != _last_key:
		_last_key = key
		print("[距离] %.0f m：可见 %d/%d 簇、%d/%d 网格"
			% [far, visible_clusters, clusters.size(),
				visible_meshes, int(stats["meshes"])])


## 把 `_hidden` 里的簇全部放回它们被压之前的样子。
func _restore_hidden() -> void:
	for id in _hidden.keys():
		var n := instance_from_id(id) as Node3D
		if is_instance_valid(n):
			n.visible = bool(_hidden[id])
	_hidden.clear()


func _camera() -> Camera3D:
	if is_inside_tree():
		var c := get_viewport().get_camera_3d()
		if c != null:
			return c
	return null


func _total_meshes() -> int:
	var n := 0
	for c in clusters:
		n += int(c["meshes"])
	return n


# ── 切簇 ──────────────────────────────────────────────────────────────────────

## 返回「这个子树里有没有切出至少一个簇」（用来兜底：切不动就当自己一簇）。
func _collect(n: Node3D, depth: int) -> bool:
	var r := _subtree_aabb(n)
	if not r["ok"]:
		return false
	var a: AABB = r["aabb"]
	var diag := a.size.length()
	if diag <= CLUSTER_DIAGONAL or depth >= MAX_DEPTH:
		clusters.append(_make_cluster(n, a, diag))
		return true
	var any := false
	for c in n.get_children():
		if c is Node3D and _collect(c as Node3D, depth + 1):
			any = true
	if not any:
		# 一整块、却切不出小块（典型：泼溅，一个节点罩住几百米）。
		# 半径按它的包围盒给，于是「球心距离 − 半径」恒小于渲染距离 → 等价于不裁。
		clusters.append(_make_cluster(n, a, diag))
	return true


## 簇的包围盒**存成节点局部坐标**，不是世界坐标。
##
## ⚠️ 2026-10-22 用户：「渲染距离调到 400，跑到内存条那里突然看不见自己人了」。
##    原因是第一版把世界 AABB 的**球心**缓存下来了：玩家/同伴/Boss 是**会动**的，
##    簇心永远停在开机时的位置（出生点附近）。人跑到 480 m 外的内存条市场，
##    「簇心到摄像机」= 480 m > 400 m → 判成裁掉 → **玩家自己的模型消失**。
##    改成存局部 AABB：每 tick 现算 `node.global_transform * local_aabb`，
##    动的节点跟着动，不动的节点算出来和原来一样。
##    半径仍然用**局部对角线的一半**：球在任意旋转下都能罩住盒子，所以不用重算。
func _make_cluster(n: Node3D, a: AABB, diag: float) -> Dictionary:
	return {
		"node": n,
		"local_aabb": n.global_transform.affine_inverse() * a,
		"radius": diag * 0.5,
		"meshes": _count_meshes(n),
	}


## 子树里所有可见几何的合并 AABB（世界坐标）。
##
## ⚠️ **不能拿 `GeometryInstance3D.geometry` 当通用接口**：`Label3D` / `GPUParticles3D`
##    也是 `GeometryInstance3D`，但它们**没有 `mesh` 属性**（探针第一次跑就炸在这：
##    `Invalid access to property or key 'mesh' on a base object of type 'Label3D'`，
##    整个切簇直接失败、簇数 0）。所以这里只认两种真有尺寸的：
##    `MeshInstance3D`（普通网格）和 `MultiMeshInstance3D`（泼溅就是它）。
## ⚠️ 蒙皮网格的 `mesh.get_aabb()` 是**绑定姿态**的盒子，手抬起来会比实际小一点；
##    对「要不要裁」这种粗判足够，别拿它量精确尺寸。
func _subtree_aabb(n: Node) -> Dictionary:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		var a := AABB()
		var has := false
		if x is MeshInstance3D:
			var mi := x as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				a = mi.global_transform * mi.mesh.get_aabb()
				has = true
		elif x is MultiMeshInstance3D:
			var mmi := x as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.is_visible_in_tree():
				a = mmi.global_transform * mmi.multimesh.get_aabb()
				has = true
		if has:
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
		for c in x.get_children():
			stack.append(c)
	return {"ok": not first, "aabb": out}


func _count_meshes(n: Node) -> int:
	var k := 0
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is GeometryInstance3D:
			k += 1
		for c in x.get_children():
			stack.append(c)
	return k

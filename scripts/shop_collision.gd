extends Node3D
## 电脑城（Shop）的屋壳碰撞：按 GLB 网格建 **trimesh** 碰撞。
##
## 使用者 2026-11-09：「现在把电脑城的墙壁、柜台加上碰撞」。
##
## ── 为什么不用盒子（对比 `esports_collision.gd`）──
## 电竞房那个用 AABB 盒子，是因为它的网格**逐件分得开**（59 个网格各是一件家具）。
## 电脑城这个不是：`shop_baked.tscn` 的屋壳换成了 Sketchfab「Shop」，
## 导出时**按材质合并**，于是墙 / 柜台 / 货架 / 隔断全挤进同一个网格：
##
##   PLASTIK_W_PLASTIK_W_0   872 面   x 20.71~33.89  y 0.02~5.82  z -23.43~-12.74
##   glass_01 - Default_0    432 面   （玻璃隔断，同样横跨整个房间）
##   Rectangle009__0          10 面   （地板）
##   Object002_PLASTIK_W_0    24 面   （天花板）
##   LIGHT_light_0           216 面   （灯带）
##   black_met__0             72 面   （踢脚线）
##   Object056_01            30 面
##
## 对这种「一个网格横跨整个房间」的情况，AABB 盒子会把整个房间填成实心，
## 玩家直接被封在里面 —— 所以只能走 trimesh。
##
## ── trimesh 在这里为什么没问题 ──
## 整个屋壳**合计只有 1656 个三角面**（上面那 7 个网格加起来），
## 而且房子是**静态**的（不动、不缩放）。Godot 对静态 trimesh 的查询开销
## 与三角形数成正比，1656 面完全无所谓 —— 对比电竞房 105 万面那个才不敢用。
##
## ── 已有的盒子碰撞保留 ──
## `shop_baked.tscn` 里 `Body` 下已有 4 面外墙 + 招牌的盒子（`ShellWall*Shape`），
## 那是烘焙时按 GLB 外壳尺寸算出来的，性能更好，**保留不动**。
## 本脚本只在它们之外**补**上柜台 / 货架 / 玻璃这些原先缺的部分。
## （盒子挡住外墙，trimesh 挡住内部物件，两者不冲突。）

## 挂在屋壳实例的那个父节点（`shop_baked.tscn` 里叫 `Shell`）
const SHELL_PATH := ^"../Shell"

## 小于这个体积的网格不做碰撞（纯装饰件：灯带碎片、贴图片）
const MIN_VOLUME := 0.001

## ── 只跟网格走，不凭空补 ──
## 使用者 2026-11-09：「为什么上面没有网格，空的地方也搞碰撞？去掉！我只要网格做的碰撞。」
## 所以这里**不再**给天花板补盒子 —— 一切碰撞都严格来自 GLB 网格的三角面。
## （GLB 的天花板 `Object002_PLASTIK_W_0` 本身是空心的方框，中间没有网格；
##   既然网格没有，碰撞也不该有。上空开放，跳出去也没东西挡。）

var _built := false


func _ready() -> void:
	# 等一帧，确保 GLB 实例和 transform 都就位
	await get_tree().process_frame
	build_collision()


## 对外入口（探针也会直接调）。**幂等**：重复调用先清掉旧的。
func build_collision() -> void:
	if _built:
		return
	_built = true

	for c in get_children():
		if c is StaticBody3D and c.name.begins_with("ShellTrimesh"):
			remove_child(c)
			c.queue_free()

	var shell := get_node_or_null(SHELL_PATH) as Node3D
	if shell == null:
		push_warning("[ShopCol] 没找到 Shell 节点，跳过")
		return

	var body := StaticBody3D.new()
	body.name = "ShellTrimesh"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)

	var n_face := 0
	var n_shape := 0
	var skipped := 0
	for n in shell.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var am := mi.mesh as ArrayMesh

		# 太小的装饰件跳过（灯带碎片、贴图片）
		var wb: AABB = mi.global_transform * am.get_aabb()
		if wb.size.x * wb.size.y * wb.size.z < MIN_VOLUME:
			skipped += 1
			continue

		# 把网格的**所有 surface** 合成一个三角形列表。
		# ⚠️ 必须转到**本节点坐标系**：`body` 是挂在 EsportsRoom 下的子节点，
		#    而网格的世界变换可能带缩放（Shell 是 ×2.076）。
		#    `ConcavePolygonShape3D.set_faces()` 用**局部**坐标，
		#    所以每个顶点要先 `to_local()`（= 世界坐标 → 本节点局部）。
		var faces := PackedVector3Array()
		for si in am.get_surface_count():
			var arrays := am.surface_get_arrays(si)
			if arrays.size() <= Mesh.ARRAY_VERTEX:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var idx: PackedInt32Array = PackedInt32Array()
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			# 有索引就按索引取三角，没有就按顺序每 3 个一组
			var tri_n := (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
			for t in tri_n:
				var a: Vector3
				var b: Vector3
				var c: Vector3
				if idx.size() > 0:
					a = verts[idx[t * 3]]
					b = verts[idx[t * 3 + 1]]
					c = verts[idx[t * 3 + 2]]
				else:
					a = verts[t * 3]
					b = verts[t * 3 + 1]
					c = verts[t * 3 + 2]
				# 顶点 → 世界 → 本节点局部
				faces.append(to_local(mi.global_transform * a))
				faces.append(to_local(mi.global_transform * b))
				faces.append(to_local(mi.global_transform * c))
			n_face += tri_n

		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.name = "Tri_%s" % mi.name
		cs.shape = shape
		body.add_child(cs)
		n_shape += 1

	print("[ShopCol] 屋壳 trimesh：%d 个网格 → %d 个碰撞形状（%d 三角面；跳过 %d 个装饰件）"
		% [n_shape, n_shape, n_face, skipped])

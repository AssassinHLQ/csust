extends Node3D
## 电竞房的自动碰撞：按 GLB 里每个网格的 AABB 建盒子碰撞体。
##
## 为什么不用 trimesh：
##   59 个网格 / 105 万面，trimesh 碰撞体在 Godot 里构建慢、查询也慢，
##   而这间房只需要「人走得进去、但穿不过墙」，盒子足够。
##
## 为什么外壳要手工拆：
##   房间外壳 `M_材质_3` 的 AABB 是整个 10.4×3.3×16.8 —— 直接给它建一个盒子，
##   玩家就被关在实心盒子里了。所以外壳拆成「地板 + 天花板 + 四面墙」共 6 个盒子，
##   其余网格（家具、隔断、柜子）各自用一个 AABB 盒。
##
## 用法：挂在 `EsportsRoom` 节点上（见 `esports_room.tscn`）。

## 房间外壳的网格名片段（按材质名命名的那个大网格）
const SHELL_HINT := "材质_3"
## 墙厚 / 地板天花板厚
const WALL_T := 0.22
## 门洞宽 / 高（本地 +Z 那一头是门；实测那侧墙面只有 3.0 m²，-Z 侧 66.5 m²）
const DOOR_WIDTH := 2.4
const DOOR_HEIGHT := 2.4
## 碰撞层：1 = 世界层，玩家与同伴都在这一层
const LAYER := 1
## 小于这个体积的网格不做碰撞（装饰件）
const MIN_BOX_VOLUME := 0.002
## 三边之和小于这个的网格不做碰撞（细杆、贴片）
const MIN_BOX_EXTENT := 0.15


## 防止 `_ready` 被重复触发（场景重载、节点重入树）时把碰撞建两遍。
var _built := false


func _ready() -> void:
	# 等一帧，确保 GLB 实例和 transform 都就位
	await get_tree().process_frame
	if _built:
		return
	_do_build()


## 对外入口（探针直接调）：**强制重建**，先清掉旧的。
func build_collision() -> void:
	_do_build()


## 真正干活的部分。`_built` 在这里置位。
func _do_build() -> void:
	_built = true
	# 彻底清掉之前建过的（按名字，不管挂在哪一层）
	for c in get_children():
		if c is StaticBody3D and c.name.begins_with("AutoCol"):
			remove_child(c)
			c.queue_free()

	var meshes: Array[MeshInstance3D] = []
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			meshes.append(mi)
	if meshes.is_empty():
		push_warning("[EsportsCol] 没找到网格，跳过")
		return

	var body := StaticBody3D.new()
	body.name = "AutoCol"
	body.collision_layer = LAYER
	body.collision_mask = 0
	add_child(body)

	var n_added := 0
	var shell := _find_shell(meshes)

	# 房间整体尺寸（给下面「包住整间房的盒子一律跳过」那道保险用）
	var room_size := Vector3(10.4, 3.6, 16.84)
	if shell != null:
		room_size = (shell.global_transform * shell.mesh.get_aabb()).size

	# ── ① 外壳：地板 / 天花板 / 四面墙 ──
	if shell != null:
		var sa: AABB = shell.global_transform * shell.mesh.get_aabb()
		n_added += _add_room_boxes(body, sa)
		print("[EsportsCol] 外壳 %s aabb=%s" % [shell.name, _fmt(sa)])

	# ── ② 其余网格：各一个 AABB 盒 ──
	# ⚠️ 必须跳过**所有**名字含 SHELL_HINT 的网格，不只 `shell` 那一个 ——
	#    合并后可能有多个网格带这个材质名，漏掉任何一个都会变成一个
	#    「包住整间房的实心大盒子」，门洞直接被封死。
	#    （2026-11-08 实测：漏了 3 个 10.4×3.3×16.84 的实心盒，门洞堵死。）
	for mi in meshes:
		if SHELL_HINT in mi.name:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		# 再加一道保险：AABB 几乎等于整间房的，一定是外壳类网格，不做实心盒
		if a.size.x >= room_size.x * 0.95 and a.size.z >= room_size.z * 0.95:
			continue
		if a.size.x * a.size.y * a.size.z < MIN_BOX_VOLUME:
			continue
		if a.size.x + a.size.y + a.size.z < MIN_BOX_EXTENT:
			continue
		_add_box(body, a.get_center(), a.size)
		n_added += 1

	print("[EsportsCol] 共建 %d 个盒子碰撞" % n_added)


## 挑体积最大的那个「外壳」网格。
func _find_shell(meshes: Array[MeshInstance3D]) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_vol := 0.0
	for mi in meshes:
		if not (SHELL_HINT in mi.name):
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		var v := a.size.x * a.size.y * a.size.z
		if v > best_vol:
			best_vol = v
			best = mi
	return best


## 把一个房间外壳的 AABB 拆成 6 个盒子（地板、天花板、四面墙）。
##
## ⚠️ 本地 +Z 那一头是**门口**（实测那一侧墙面只有 3.0 m²，而 -Z 侧有 66.5 m²），
##    所以 +Z 那面墙不能铺满，得按门洞宽度拆成「左墙墩 + 门楣 + 右墙墩」。
##    门洞参数见 DOOR_*。
func _add_room_boxes(body: StaticBody3D, a: AABB) -> int:
	var c := a.get_center()
	var s := a.size
	var t := WALL_T
	var y0 := a.position.y
	var y1 := a.position.y + s.y
	var n := 0

	# 地板 / 天花板（铺满整个水平投影）
	_add_box(body, Vector3(c.x, y0 + t * 0.5, c.z), Vector3(s.x, t, s.z))
	_add_box(body, Vector3(c.x, y1 - t * 0.5, c.z), Vector3(s.x, t, s.z))
	n += 2

	# 两面 X 向的墙（长边那两侧，法线沿 X）—— 铺满
	_add_box(body, Vector3(a.position.x + t * 0.5, c.y, c.z), Vector3(t, s.y, s.z))
	_add_box(body, Vector3(a.position.x + s.x - t * 0.5, c.y, c.z), Vector3(t, s.y, s.z))
	n += 2

	# -Z 那面墙（实墙）—— 铺满
	var z_wall_far := a.position.z
	_add_box(body, Vector3(c.x, c.y, z_wall_far + t * 0.5), Vector3(s.x, s.y, t))
	n += 1

	# +Z 那面墙 = **门口那面**：左墩 + 门楣 + 右墩，中间留空给人走
	var z_wall_near := a.position.z + s.z
	var door_x := c.x                       # 门洞横向中心（房间正中）
	var door_w := DOOR_WIDTH
	var door_h := DOOR_HEIGHT
	var lx0 := a.position.x
	var lx1 := door_x - door_w * 0.5
	var rx0 := door_x + door_w * 0.5
	var rx1 := a.position.x + s.x
	# 左墩
	if lx1 - lx0 > 0.02:
		_add_box(body, Vector3((lx0 + lx1) * 0.5, c.y, z_wall_near - t * 0.5),
			Vector3(lx1 - lx0, s.y, t))
		n += 1
	# 右墩
	if rx1 - rx0 > 0.02:
		_add_box(body, Vector3((rx0 + rx1) * 0.5, c.y, z_wall_near - t * 0.5),
			Vector3(rx1 - rx0, s.y, t))
		n += 1
	# 门楣（门洞上方的墙）
	var lintel_h := s.y - door_h
	if lintel_h > 0.02:
		_add_box(body, Vector3(door_x, y0 + door_h + lintel_h * 0.5, z_wall_near - t * 0.5),
			Vector3(door_w, lintel_h, t))
		n += 1

	return n


func _add_box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	# 防零尺寸：Godot 的 BoxShape3D 三边必须 > 0
	shape.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# ⚠️ 必须用 global_position：`center` 是从 `global_transform * aabb` 算出来的
	#    **世界坐标**，写进 `cs.position`（相对父节点）会被再叠加一次父节点偏移。
	#    实测：EsportsRoom 在 (52, 0.01, 13)，写成 position 后盒子跑到 x≈98.8。
	cs.global_position = center


func _fmt(a: AABB) -> String:
	return "pos(%.2f,%.2f,%.2f) size(%.2f,%.2f,%.2f)" % [
		a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z]

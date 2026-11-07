extends SceneTree
## 探针：查「回程火箭为什么落不到传送门那一块」。
##
## 用户 2026-11-07：「火箭落地不是传送门那一块，是因为有东西挡住吧，那就删除」。
## 本探针把跑道口传送门周围 10 m 内的**所有实体**（网格 + 碰撞盒）列出来，
## 并对几个候选落点向下打射线量地面高度，看是哪一件东西把这个位置占了。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_rocket_land.gd

const SCENE := "res://scenes/parkour.tscn"
## 和 parkour.gd 保持一致的常量（探针不依赖 class_name）
const PORTAL_OFFSET := Vector3(0.0, 0.0, 4.5)
const RETURN_PARK_OFFSET := Vector3(0.0, 0.0, -3.0)
const HOME_LAND_OFFSET := Vector3(4.0, 0.0, 4.5)
const ISLAND_LAND_OFFSET := Vector3(5.0, 0.0, 3.0)

var _inst: Node
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[land] FAIL 载不动 %s" % SCENE)
		quit()
		return
	_inst = ps.instantiate()
	root.add_child(_inst)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false

	var launch := _inst.get_node_or_null("Launch") as Node3D
	var pad := _inst.get_node_or_null("Island/Props/ReturnPad") as Node3D
	var shed := _inst.get_node_or_null("Island/Props/Shed") as Node3D
	if launch == null:
		print("[land] FAIL 找不到 Launch")
		quit()
		return true
	print("[land] Launch = %s" % str(launch.global_position.snappedf(0.01)))
	if pad != null:
		print("[land] ReturnPad = %s" % str(pad.global_position.snappedf(0.01)))
	if shed != null:
		print("[land] Shed = %s" % str(shed.global_position.snappedf(0.01)))

	# 传送门（和 _spawn_finish_portal 同一个公式）
	var portal := launch.global_position + PORTAL_OFFSET
	var old_home := launch.global_position + HOME_LAND_OFFSET
	print("[land] ── 跑道口这一头 ──")
	print("[land]   传送门（去程落点/门框）= %s" % str(portal.snappedf(0.01)))
	print("[land]   现在回程落点（+4 m）= %s" % str(old_home.snappedf(0.01)))

	# ── 候选落点向下打射线：地面在哪儿、有没有东西顶着 ──
	print("[land] ── 向下射线（从 y+60 打，找地面/顶棚）──")
	var cands := {
		"传送门正下方": portal,
		"现在回程落点": old_home,
		"传送门 -X 4 m": portal + Vector3(-4.0, 0.0, 0.0),
		"传送门 +Z 4 m": portal + Vector3(0.0, 0.0, 4.0),
	}
	for k in cands:
		var p: Vector3 = cands[k]
		var hit := _ray(p)
		print("[land]   %-16s xz=%s → %s" % [k,
			str(Vector2(p.x, p.z).snappedf(0.01)), hit])

	print("[land] ── 传送门周围 10 m 内的实体 ──")
	_list_near(portal, 10.0)

	if pad != null:
		print("[land] ── 岛上传送台周围 10 m 内的实体 ──")
		_list_near(pad.global_position + RETURN_PARK_OFFSET, 10.0)
		if shed != null:
			var out_land: Vector3 = shed.global_position + ISLAND_LAND_OFFSET
			print("[land] ── 去程落点 %s 周围 10 m ──" % str(out_land.snappedf(0.01)))
			_list_near(out_land, 10.0)

	_inst.queue_free()
	quit()
	return true


## 从 p 上方 60 m 垂直向下打 200 m，返回碰到的东西
func _ray(p: Vector3) -> String:
	var space := _root_world()
	if space == null:
		return "无物理空间"
	var q := PhysicsRayQueryParameters3D.create(
		p + Vector3(0.0, 60.0, 0.0), p + Vector3(0.0, -140.0, 0.0))
	var ss := space.direct_space_state
	if ss == null:
		return "无物理状态"
	var r: Dictionary = ss.intersect_ray(q)
	if r.is_empty():
		return "打空（没有地面/没有碰撞）"
	var c := r["collider"] as Node
	return "y=%.2f  ← %s" % [float(r["position"].y), _path_of(c)]


func _root_world() -> World3D:
	var n := _inst as Node3D
	return n.get_world_3d() if n != null else null


func _path_of(n: Node) -> String:
	if n == null:
		return "?"
	var parts: Array[String] = []
	var cur := n
	while cur != null and cur != _inst:
		parts.push_front(String(cur.name))
		cur = cur.get_parent()
	return "/".join(parts)


## 列出中心 c 半径 r 内、世界包围盒与球相交的网格与碰撞体
func _list_near(c: Vector3, r: float) -> void:
	var found: Array = []
	for n in _inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var ab := mi.global_transform * mi.get_aabb()
		var d := ab.get_center().distance_to(c) - ab.size.length() * 0.5
		if d <= r:
			found.append([d, "网格", _path_of(mi), ab])
	for n in _inst.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var ab := cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		var d := ab.get_center().distance_to(c) - ab.size.length() * 0.5
		if d <= r:
			found.append([d, "碰撞", _path_of(cs), ab])
	found.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	if found.is_empty():
		print("[land]     （空的，半径 %.0f m 内什么都没有）" % r)
		return
	for row in found:
		var ab: AABB = row[3]
		print("[land]     d=%5.1f m  %s  %-46s  pos=%s size=%s" % [
			float(row[0]), row[1], row[2],
			str(ab.position.snappedf(0.1)), str(ab.size.snappedf(0.1))])

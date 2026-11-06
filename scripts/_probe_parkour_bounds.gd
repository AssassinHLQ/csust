extends SceneTree
## 量跑酷区（准备区 + 赛道）的整体包围盒 —— 给「进跑酷区才显示招牌」定门控范围用。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_parkour_bounds.gd

const SCENE := "res://scenes/parkour.tscn"
const ROOM_CENTER := Vector3(-0.5, 1.5, 3.54)
const ROOM_SIZE := Vector3(10.71, 8.3, 20.64)

var _inst: Node
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[bounds] FAIL: 载不动 %s" % SCENE)
		quit()
		return
	_inst = ps.instantiate()
	root.add_child(_inst)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	# 1) 整个 parkour 场景挂的所有 MeshInstance3D 的合并包围盒
	var box := AABB()
	var first := true
	var n_mesh := 0
	for n in _inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		n_mesh += 1
		var b := mi.global_transform * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	print("[bounds] MeshInstance3D %d 个，合并包围盒 pos=%s size=%s" % [
		n_mesh, str(box.position), str(box.size)])

	# 2) 所有招牌的包围盒
	var lbox := AABB()
	var lfirst := true
	var n_lab := 0
	for n in _inst.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l == null or l.text.strip_edges() == "":
			continue
		n_lab += 1
		var p := l.global_position
		var b := AABB(p - Vector3(1, 1, 1), Vector3(2, 2, 2))
		if lfirst:
			lbox = b
			lfirst = false
		else:
			lbox = lbox.merge(b)
	print("[bounds] 有字招牌 %d 个，包围盒 pos=%s size=%s" % [
		n_lab, str(lbox.position), str(lbox.size)])

	# 3) 命名分组（准备区 / 起点区）单独量
	for nm in ["ReadyZone", "SignPost", "Route"]:
		var node := _inst.get_node_or_null(nm)
		if node is Node3D:
			print("[bounds] %s 原点 = %s" % [nm, str((node as Node3D).global_position)])

	# 4) 房间到跑酷包围盒的距离
	print("[bounds] 画室盒子 → 跑酷包围盒 最近距离 = %.1f m" % _box_to_box(
		ROOM_CENTER, ROOM_SIZE * 0.5, box.get_center(), box.size * 0.5))

	_inst.queue_free()
	quit()
	return true


func _box_to_box(c1: Vector3, h1: Vector3, c2: Vector3, h2: Vector3) -> float:
	var d := Vector3(
		maxf(absf(c1.x - c2.x) - (h1.x + h2.x), 0.0),
		maxf(absf(c1.y - c2.y) - (h1.y + h2.y), 0.0),
		maxf(absf(c1.z - c2.z) - (h1.z + h2.z), 0.0))
	return d.length()

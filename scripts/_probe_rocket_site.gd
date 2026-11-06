extends SceneTree
## 探针：量跑酷场景里「火箭要摆的两头」——跑道口 Launch、结算屋 Shed、回程传送台 ReturnPad，
## 以及整条赛道的实际尺寸。用来决定火箭缩放（70 m 原尺寸会不会大得离谱）。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_rocket_site.gd

const SCENE := "res://scenes/parkour.tscn"
const ROCKET_GLB := "res://models/rocket_falcon9/falcon9.glb"

var _inst: Node
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[site] FAIL 载不动 %s" % SCENE)
		quit()
		return
	_inst = ps.instantiate()
	root.add_child(_inst)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false

	var keys := [
		"Launch",
		"Island/Props/Shed",
		"Island/Props/ReturnPad",
		"Island",
		"Route",
	]
	var pos := {}
	for k in keys:
		var n := _inst.get_node_or_null(k) as Node3D
		if n == null:
			print("[site] %-24s 不存在" % k)
			continue
		pos[k] = n.global_position
		print("[site] %-24s = %s" % [k, str(n.global_position.snappedf(0.01))])

	# ── 整条赛道的包围盒 ──
	var box := AABB()
	var first := true
	for n in _inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("[site] 赛道合并包围盒 pos=%s size=%s" % [
		str(box.position.snappedf(0.1)), str(box.size.snappedf(0.1))])

	# ── 关键距离 ──
	if pos.has("Launch") and pos.has("Island/Props/Shed"):
		var a: Vector3 = pos["Launch"]
		var b: Vector3 = pos["Island/Props/Shed"]
		var flat := Vector3(b.x - a.x, 0.0, b.z - a.z)
		print("[site] ── 跑道口 → 结算屋 ──")
		print("[site]   平面距离 = %.1f m，高差 = %.2f m，直线 = %.1f m" % [
			flat.length(), b.y - a.y, a.distance_to(b)])

	# ── 70 m 火箭相对赛道的比例 ──
	var span := maxf(box.size.x, maxf(box.size.y, box.size.z))
	print("[site] ── 尺度参考 ──")
	print("[site]   赛道最大跨度 = %.1f m" % span)
	print("[site]   70 m 火箭 = 跨度的 %.0f%%" % (70.0 / span * 100.0))
	for s in [1.0, 0.5, 0.35, 0.25]:
		print("[site]   缩放 %.2f -> 高 %.1f m = 跨度的 %.0f%%" % [
			s, 70.0 * s, 70.0 * s / span * 100.0])

	print("[site] 火箭 GLB 存在 = %s" % str(ResourceLoader.exists(ROCKET_GLB)))

	# ── 三个落点的实际体积（决定火箭落哪儿才不会插进建筑里）──
	print("[site] ── 落点 AABB（世界）──")
	for k in ["Launch", "Island/Props/Shed", "Island/Props/ReturnPad"]:
		var n := _inst.get_node_or_null(k) as Node3D
		if n == null:
			continue
		var ab := _world_aabb(n)
		print("[site]   %-24s pos=%s size=%s" % [
			k, str(ab.position.snappedf(0.1)), str(ab.size.snappedf(0.1))])

	_inst.queue_free()
	quit()
	return true


## 节点的世界包围盒：自己是网格就用它，否则找 Mesh 子节点，再否则用盒子碰撞，最后退回原点。
func _world_aabb(node: Node) -> AABB:
	var self_mesh := node as MeshInstance3D
	if self_mesh != null and self_mesh.mesh != null:
		return self_mesh.global_transform * self_mesh.get_aabb()
	for sub in node.find_children("*", "MeshInstance3D", true, false):
		var m := sub as MeshInstance3D
		if m != null and m.mesh != null:
			return m.global_transform * m.get_aabb()
	var col := node.get_node_or_null("Col") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		var s := (col.shape as BoxShape3D).size
		return col.global_transform * AABB(-s * 0.5, s)
	if node is Node3D:
		return AABB((node as Node3D).global_position, Vector3.ZERO)
	return AABB()

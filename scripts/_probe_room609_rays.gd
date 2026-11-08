extends SceneTree
## 探针：609 画室的**四面墙在人身高度上到底挡不挡人**。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_room609_rays.gd
##
## 为什么需要它：墙的碰撞盒一度被改成 y -2.65 ~ +0.60（高 3.2494），
## 也就是**站在地板上的人上半身完全没有墙**。代理网格照碰撞复制，所以
## 用户看到的是「墙没了」。光看包围盒能发现，但「人能不能走出去」才是
## 玩家真正感觉到的东西，所以这里直接打射线。
##
## 期望（修复后）：四个水平方向 × 五个高度，全部命中，且在房间矩形附近；
## 唯一允许漏的是 +X 那面墙的**门洞**（z ≈ -3.8 ~ -1.6，且只在 y < 2.6 处）。

const GAME := "res://scenes/game.tscn"
const CAP_R := 0.3
const CAP_H := 1.5
## 从房间中心往四面打
const HEIGHTS := [0.3, 0.9, 1.5, 2.5, 4.0]

var _frames := 0
var _game: Node3D


func _initialize() -> void:
	var ps: PackedScene = load(GAME)
	if ps == null:
		print("[rays] FAIL 载不动 %s" % GAME)
		quit(1)
		return
	_game = ps.instantiate() as Node3D
	root.add_child(_game)


func _process(_d: float) -> bool:
	_frames += 1
	# 射线要在物理帧里打，但 `_physics_process` 在 SceneTree 脚本里不是虚函数，
	# 所以这里退一步：头几帧只是等节点就位，真正打射线靠 `physics_frame` 信号。
	if _frames == 4:
		_do_rays.call_deferred()
		return false
	return false


func _do_rays() -> void:
	await physics_frame
	await physics_frame

	var box: AABB = _game.get("_room_box")
	if box.size == Vector3.ZERO:
		print("[rays] FAIL 没量到 _room_box")
		quit(1)
		return
	var c := box.position + box.size * 0.5
	print("[rays] 房间矩形 = x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f" % [
		box.position.x, box.end.x, box.position.y, box.end.y,
		box.position.z, box.end.z])

	var space := _game.get_world_3d().direct_space_state
	var dirs := {
		"西 (-X)": Vector3(-1, 0, 0),
		"东 (+X)": Vector3(1, 0, 0),
		"北 (-Z)": Vector3(0, 0, -1),
		"南 (+Z)": Vector3(0, 0, 1),
	}
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var hit_n := 0
	var miss_n := 0
	print("")
	for nm in dirs.keys():
		var d: Vector3 = dirs[nm]
		var line := "  %s：" % nm
		for h in HEIGHTS:
			var from := Vector3(c.x, h, c.z)
			# 起点若已经在墙里/门外，就跳过（不太可能）
			q.from = from
			q.to = from + d * 30.0
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				line += "  y%.1f 打空✗" % h
				miss_n += 1
			else:
				var dist: float = (hit["position"] as Vector3).distance_to(from)
				line += "  y%.1f %.2fm" % [h, dist]
				hit_n += 1
		print(line)

	print("\n  命中 %d / 打空 %d（打空只有在门洞那一段才算正常）" % [hit_n, miss_n])

	# 门洞验一下：站在门口正对着 +X 方向，y=1.0 应该能穿出去（门就在那儿）
	q.from = Vector3(c.x, 1.0, -2.706)
	q.to = q.from + Vector3(20, 0, 0)
	var door_hit := space.intersect_ray(q)
	if door_hit.is_empty():
		print("  ✔ 门洞 y=1.0 处确实通（可以走出去）")
	else:
		print("  ⚠ 门洞被挡住了：%.2f m 处命中 %s" % [
			(door_hit["position"] as Vector3).distance_to(q.from),
			door_hit["collider"].name])

	# 门楣以上应该挡住 —— 但要避开**门洞本身**。
	# 门洞是全高开的（WallXPos 覆盖 z -1.65~13.72、WallZNegB 覆盖 z -6.75~-3.76，
	# 中间 -3.76~-1.65 就是洞口，碰撞上整条都是空的；`DoorLintel` 只是视觉网格、无碰撞）。
	# 所以这里在**实墙段** z = 5.0 处测，那才是门楣以上该有的那道墙。
	q.from = Vector3(c.x, 4.0, 5.0)
	q.to = q.from + Vector3(20, 0, 0)
	var above := space.intersect_ray(q)
	if above.is_empty():
		print("  ✗ 实墙段 y=4.0 也通了（墙又有洞）")
	else:
		print("  ✔ 实墙段 y=4.0 被挡住（%.2f m）" % [
			(above["position"] as Vector3).distance_to(q.from)])

	quit(0)

extends SceneTree
## 单独验证**烘好的碰撞场景**（不经过 game.tscn / game.gd）。
##
## 为什么单独跑：2026-11-09 项目里 `scripts/weapon.gd` 有别人未提交的语法错误
## （`Constant "BEAM_CORE" has the same name as a previously declared constant`），
## 连带 `game.gd` 起不来。这个探针只 load 碰撞场景 + 屋壳场景，绕开那条链。
##
##   godot --headless --script res://scripts/_verify_baked_collision.gd -- --no-capture

const BAKED := "res://scenes/esports_collision_baked.tscn"
const ROOM := "res://scenes/esports_room.tscn"

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[bc] OK   %s" % what)
	else:
		_fails += 1
		print("[bc] FAIL %s" % what)


func _run() -> void:
	await _wait(2)

	# ── ① 烘好的碰撞场景单独加载 ──
	var baked: Node3D = load(BAKED).instantiate()
	root.add_child(baked)
	await _wait(4)

	var body := baked.find_child("AutoCol", true, false) as StaticBody3D
	_check(body != null, "BakedCollision 里有 AutoCol")
	if body == null:
		quit(1)
		return

	var shapes: Array[CollisionShape3D] = []
	var aabb := AABB()
	var first := true
	var dup_shape := 0
	var seen := {}
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		shapes.append(cs)
		# 同一份 shape 资源被几个节点引用？
		var rid := cs.shape.get_instance_id()
		if seen.has(rid):
			dup_shape += 1
		else:
			seen[rid] = true
		var bs := cs.shape as BoxShape3D
		var a := AABB(cs.global_position - bs.size * 0.5, bs.size)
		aabb = a if first else aabb.merge(a)
		first = false

	print("[bc] 形状 %d 个，其中共享同一份 shape 资源的 %d 个" % [shapes.size(), dup_shape])
	print("[bc] 总范围 pos(%.2f,%.2f,%.2f) size(%.2f,%.2f,%.2f)" % [
		aabb.position.x, aabb.position.y, aabb.position.z,
		aabb.size.x, aabb.size.y, aabb.size.z])

	_check(shapes.size() > 300, "形状数够（%d 个，旧版是 152，烘好的应该有几百）" % shapes.size())
	_check(dup_shape == 0, "每个形状都是**独立资源**（共享的 %d 个）—— 编辑器里改一个不会连累另一个" % dup_shape)

	# 包围盒应该贴着房间（10.4 × 3.6 × 16.8）
	_check(absf(aabb.size.x - 10.4) < 1.0, "X 方向贴合房间（%.2f ≈ 10.4）" % aabb.size.x)
	_check(absf(aabb.size.z - 16.84) < 1.0, "Z 方向贴合房间（%.2f ≈ 16.84）" % aabb.size.z)

	# ── ② 射线：四面墙 + 地板 ──
	var space := baked.get_world_3d().direct_space_state
	var c := aabb.get_center()
	var mid := Vector3(c.x, aabb.position.y + 1.7, c.z)
	for k in ["+X", "-X", "+Z", "-Z"]:
		var d := {
			"+X": Vector3(8, 0, 0), "-X": Vector3(-8, 0, 0),
			"+Z": Vector3(0, 0, 11), "-Z": Vector3(0, 0, -11),
		}[k] as Vector3
		var h := _ray(space, mid, mid + d)
		_check(h.size() > 0, "朝 %s 打：有碰撞" % k)
	var hd := _ray(space, mid, mid + Vector3(0, -3, 0))
	_check(hd.size() > 0, "朝下打：有地板")

	# ── ③ 门洞（本地 +Z 那一头正中）应该能过 ──
	var z_wall := aabb.position.z + aabb.size.z
	var hz := _ray(space, Vector3(c.x, aabb.position.y + 1.7, z_wall + 3.0), Vector3(c.x, aabb.position.y + 1.7, c.z))
	if hz.is_empty():
		_check(true, "门洞通畅（射线一路打到房间中心）")
	else:
		var pz: float = (hz["position"] as Vector3).z
		print("[bc] 门洞射线停在 z=%.2f（墙在 z=%.2f）" % [pz, z_wall])
		_check(absf(pz - z_wall) > 0.5, "门洞没被墙封死")

	print("[bc] ---------- 结果：%s（%d 项不合格）----------"
		% ["全过" if _fails == 0 else "有失败", _fails])
	print("[bc] 提示：改碰撞请打开 %s 或 %s（BakedCollision 开「可编辑子节点」）" % [BAKED, ROOM])
	quit(0 if _fails == 0 else 1)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.collide_with_areas = false
	return space.intersect_ray(q)

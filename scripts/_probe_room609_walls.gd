extends SceneTree
## 探针：609 画室「墙没了」——量 `Room609/RoomCollision` 的真身，和烘焙代理对账。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_room609_walls.gd
##
## 已从 `scenes/room609_proxy_baked.tscn` 拿到的证词（Y 全部是错的）：
##   Wall0~4  y 中心 -1.0247、高 3.2494  → 跨度 -2.65 ~ +0.60   ← 埋进地下
##   DoorPanel y 1.30 / 高 2.6           → 跨度  0.00 ~ +2.60   ← 正常
##   DoorLintel 顶到 +5.65、Roof 5.33~5.78                       ← 正常
## 也就是说：门、门楣、屋顶都对，**只有墙的 Y 错了**，而且错的数字正好等于
## `[Game] 房间矩形 ... 中心 (-0.5, -1.02, 3.54)` 里的那个 -1.02。
## 所以怀疑 `_room_box`（Room609/RoomCollision 的世界 AABB）Y 量错了。
##
## 本探针把两边都打出来对账：碰撞体真身 vs 代理网格。

const GAME := "res://scenes/game.tscn"

var _frames := 0
var _root: Node3D


func _initialize() -> void:
	var ps: PackedScene = load(GAME)
	if ps == null:
		print("[609] FAIL 载不动 %s" % GAME)
		quit(1)
		return
	_root = ps.instantiate() as Node3D
	root.add_child(_root)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 8:
		return false

	print("\n========== 1. Room609 自己 ==========")
	var r609 := _root.get_node_or_null("Room609") as Node3D
	if r609 == null:
		print("  FAIL 没有 Room609")
	else:
		print("  Room609 transform = %s" % r609.transform)
		for c in r609.get_children():
			var extra := ""
			if c is Node3D:
				extra = "  pos=%s  vis=%s" % [_v((c as Node3D).global_position), str(c.visible)]
			print("    - %-22s (%s)%s" % [c.name, c.get_class(), extra])

	print("\n========== 2. Room609/RoomCollision 每个碰撞盒（世界坐标）==========")
	var col := _root.get_node_or_null("Room609/RoomCollision")
	var merged := AABB()
	var first := true
	if col == null:
		print("  FAIL 没有 Room609/RoomCollision")
	else:
		if col is Node3D:
			print("  RoomCollision transform = %s" % (col as Node3D).transform)
		for c in col.get_children():
			if not (c is CollisionShape3D):
				print("    - %-24s (%s) 跳过" % [c.name, c.get_class()])
				continue
			var cs := c as CollisionShape3D
			var bb := _shape_box(cs)
			print("    - %-24s 中心=%-26s AABB y %.3f ~ %.3f   %s" % [
				cs.name, _v(cs.global_position),
				bb.position.y, bb.position.y + bb.size.y, _aabb(bb)])
			if bb.size != Vector3.ZERO:
				merged = bb if first else merged.merge(bb)
				first = false
		print("  >>> 合并 = %s" % _aabb(merged))

	print("\n========== 3. game.gd 自己算的 _room_box ==========")
	var rb = _root.get("_room_box")
	if rb is AABB:
		var b := rb as AABB
		print("  _room_box = %s" % _aabb(b))
		print("  与上面合并%s" % ("" if _same(b, merged) else "**不一致**！"))
	else:
		print("  读不到 _room_box（%s）" % str(typeof(rb)))

	print("\n========== 4. 代理网格 RoomProxy 的 Y 跨度 vs 碰撞体 ==========")
	var proxy := _root.get_node_or_null("RoomProxy") as Node3D
	if proxy == null:
		print("  FAIL 没有 RoomProxy")
	else:
		print("  RoomProxy.visible = %s" % str(proxy.visible))
		for c in proxy.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var bb: AABB = mi.global_transform * mi.get_aabb()
			print("    - %-14s y %7.3f ~ %7.3f   %s" % [
				mi.name, bb.position.y, bb.position.y + bb.size.y, _aabb(bb)])

	print("\n========== 5. 玩家现在在室内还是室外 ==========")
	var pl := _root.get_node_or_null("Player") as Node3D
	if pl != null and rb is AABB:
		var p := pl.global_position
		print("  玩家 %s  has_point(_room_box) = %s" % [_v(p), str((rb as AABB).has_point(p))])
		print("  （玩家的 y 与 _room_box 的 y 区间 %s 比一下就知道了）" % [
			"%.2f ~ %.2f" % [(rb as AABB).position.y, (rb as AABB).position.y + (rb as AABB).size.y]])

	quit(0)
	return true


func _shape_box(cs: CollisionShape3D) -> AABB:
	if cs.shape == null:
		return AABB()
	var gt := cs.global_transform
	if cs.shape is BoxShape3D:
		var hs := (cs.shape as BoxShape3D).size * 0.5
		# 8 个角点变换后求包围盒（碰撞盒可能是转过的）
		var out := AABB()
		var f := true
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var w: Vector3 = gt * Vector3(hs.x * sx, hs.y * sy, hs.z * sz)
					if f:
						out = AABB(w, Vector3.ZERO)
						f = false
					else:
						out = out.expand(w)
		return out
	return gt * cs.shape.get_debug_mesh().get_aabb()


func _same(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) < 0.05 and a.size.distance_to(b.size) < 0.05


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _aabb(b: AABB) -> String:
	if b.size == Vector3.ZERO:
		return "空"
	return "x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f" % [
		b.position.x, b.position.x + b.size.x,
		b.position.y, b.position.y + b.size.y,
		b.position.z, b.position.z + b.size.z]

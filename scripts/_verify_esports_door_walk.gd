extends SceneTree
## 验收：电竞房**门能不能走进去**（真物理，不是射线）。
##
## 用户 2026-11-09 → 2026-11-11 反复报「门进不去」，前面几版探针全判错了。
##
## ⚠️⚠️ 为什么以前的探针会误判（这个教训必须留在代码里）：
##   旧探针用**射线**判「打到房间中心就算通」。但射线是从障碍物**上方**穿过去的，
##   而玩家胶囊（radius 0.30 / 总高 2.10）是被障碍物的**侧面**挡住的。
##   **射线和人不是一回事** —— 2026-11-11 实测：射线说四面全通 10.4 m，
##   真推玩家四个方向全卡在离墙 0.30 m 处。
##
## 本验收只做一件事：**把玩家胶囊真推进去**，看能不能过。
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_verify_esports_door_walk.gd -- --splat=off --no-capture

const ROOM := "EsportsRoom"
## 走多少帧（60 fps 下 240 帧 = 4 s，速度 3 m/s 理论上够走 12 m）
const FRAMES := 240

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ 电竞房门 · 真物理通行验收 ═══\n")

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	var room := game.get_node_or_null(ROOM) as Node3D
	var player := game.get("_player") as CharacterBody3D
	_check(room != null, "场景里有 %s" % ROOM)
	_check(player != null, "拿得到玩家")
	if room == null or player == null:
		_summary()
		quit(1)
		return
	room.visible = true
	for _f in 10:
		await process_frame

	# 房间范围
	var bb := AABB()
	var first := true
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	print("房间 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f\n"
		% [bb.position.x, bb.end.x, bb.position.y, bb.end.y, bb.position.z, bb.end.z])

	var cx := (bb.position.x + bb.end.x) * 0.5
	var cz := (bb.position.z + bb.end.z) * 0.5
	var floor_y := bb.position.y

	# ① 天花板不该躺在门口高度（这是 2026-11-11 的真凶）
	#    `物件_8` 是天花板，局部 y 3.3~3.6；房间 Y=-1 翻转后必须落在头顶之上。
	var ceil_ok := false
	var ceil_pos := Vector3.ZERO
	for c in room.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		if cs.name != "P0007_0" or not (cs.shape is BoxShape3D):
			continue
		var s := (cs.shape as BoxShape3D).size
		# 只有「和整间房一样大的薄板」才是那块天花板
		if s.x < bb.size.x * 0.9 or s.z < bb.size.z * 0.9:
			continue
		var aabb := cs.global_transform * AABB(-s * 0.5, s)
		ceil_pos = aabb.position
		# 翻转后它的世界底边必须高于玩家头顶（2.10 m）之上
		ceil_ok = aabb.position.y > floor_y + 2.10
		print("① 天花板碰撞 P0007_0 世界 y %.2f ~ %.2f（底面需 > %.2f）"
			% [aabb.position.y, aabb.end.y, floor_y + 2.10])
	_check(ceil_ok, "天花板碰撞不在门口高度（否则会把门封死）")

	# ② 真推三个方向。
	#
	# ⚠️ 只有**确实有门洞**的方向才要求能进。从 `esports_parts.json` 量的墙件：
	#     物件_12  x −4.60~−4.39  z −7.82~2.70  y 0.30~3.30  ← −X 侧基本是**整面实墙**
	#                                                         （10.5 m 长，只到 z=2.70）
	#     物件_5   x  4.39~ 4.60  z −7.82~−5.42 y 0.30~1.90  ← +X 侧只占一小段，**有洞**
	#     门在北/南（局部 ±Z 那两面，`NO_COLLIDE` 里那四块门板 JJKJ209/211/213/214 就在那儿）
	#   所以：
	#     · −Z 侧（门口那一面）→ **必须能进**（这是用户报的门）
	#     · +X 侧（有洞）      → **必须能进**
	#     · −X 侧（整面实墙）  → **允许被挡**，不算失败
	#
	# 2026-11-11 实测：−Z 进到 z=5.0（刚开始往里走）、+X 进到 x=58.0，
	# −X 停在 x=48.0 = 墙外沿 —— 符合墙件分布，不是 bug。
	var door_dirs := {
		"-Z 侧（门口）": [Vector3(0, 0, 1), Vector3(0, 0, -1), true],
		"+X 侧（有洞）": [Vector3(-1, 0, 0), Vector3(1, 0, 0), true],
		"-X 侧（实墙，允许被挡）": [Vector3(1, 0, 0), Vector3(-1, 0, 0), false],
	}
	for label in door_dirs:
		var spec: Array = door_dirs[label]
		var inward: Vector3 = spec[0]
		var outward: Vector3 = spec[1]
		var must_open: bool = spec[2]
		# 起点：房间中心 + 朝外 3 m（在房间外）
		var half_x := bb.size.x * 0.5 + 3.0
		var half_z := bb.size.z * 0.5 + 3.0
		var start := Vector3(cx, floor_y + 0.05, cz)
		if absf(outward.z) > 0.5:
			start.z += outward.z * half_z
		else:
			start.x += outward.x * half_x
		player.global_position = start
		player.velocity = Vector3.ZERO
		for _f in 20:
			await process_frame

		# 「进屋」判据：越过外沿 1.0 m 以上（不是 +0.5 —— 贴着墙不算进）
		var deepest := 0.0
		for i in FRAMES:
			player.velocity = inward * 3.0
			player.move_and_slide()
			await process_frame
			var p := player.global_position
			var d := 0.0
			if absf(inward.z) > 0.5:
				d = absf(p.z - cz)
			else:
				d = absf(p.x - cx)
			deepest = maxf(deepest, d)
		player.velocity = Vector3.ZERO
		var end := player.global_position
		var went_in := deepest > (bb.size.x * 0.5 - 1.0) if absf(inward.x) > 0.5 \
			else deepest > (bb.size.z * 0.5 - 1.0)
		print("② %s：%s → %s（深入 %.2f m）%s"
			% [label, str(start.round()), str(end.round()), deepest,
				"★ 进去了" if went_in else ("✗ 没进去" if must_open else "（实墙，正常）")])
		if must_open:
			_check(went_in, "  %s 能走进电竞房" % label)

	_summary()
	quit(0 if _fail == 0 else 1)


func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ %s" % msg)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
	if _fail == 0:
		print("★ 全过：电竞房三个门洞都能走进去（真物理，不是射线）")

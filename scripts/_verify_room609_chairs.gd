extends SceneTree
## 验证：609 画室的凳子碰撞 **ArtChairB 原位复制成 10 份**（用户 2026-11-11：
## 「609画室,这一个小碰撞,同样位置复制10份」）。
##
##   godot --path . --headless --script res://scripts/_verify_room609_chairs.gd
##
## 判据（用户要的是「10 个一模一样的盒子叠在原位置，之后自己在编辑器里拖开」）：
##   ① `Room609/RoomCollision` 下有 **10** 个 `ArtChairB*`，名字从 ArtChairB 到 ArtChairB10；
##   ② 10 个都是 `BoxShape3D`、尺寸全等、且**完全重合**（世界位置差 < 1 mm）；
##   ③ 10 个共用同一个 `Shape_art_chair_b` 子资源（改一次 size 十个一起变）；
##   ④ **房间矩形没被带歪**：`_room_xz_from_walls()` 跟加椅子之前一致
##      （凳子 0.93 m 高 < 2.0 的墙阈值，不许参与 `_room_box` / 高度窗口）；
##   ⑤ 物理上真的挡人：从凳子上方竖着打射线，落在凳顶附近。
##
## ⚠️ 只在 headless 跑，不开窗口、不抢用户前台（AGENTS.md 硬要求）。

const ROOM := "Room609/RoomCollision"
const CHAIR := "ArtChairB"
const N_CHAIR := 10
## 凳子盒尺寸（`Shape_art_chair_b`），10 份必须完全一致
const CHAIR_SIZE := Vector3(0.42, 0.92842406, 0.31044433)
## 凳子盒世界位置（`ArtChairB` 的 transform.origin）
const CHAIR_POS := Vector3(0.5143056, 0.46421203, 1.0588816)
## 墙（y > 2.0）量出来的房间 AABB，加椅子之前 / 之后的**同一个**答案。
## 由 5 面墙算得：x −5.849~4.856、y −2.6497~5.6497、z −6.779~13.861
const WALL_LO := Vector3(-5.849, -2.6497, -6.779)
const WALL_HI := Vector3(4.856, 5.6497, 13.861)

var _pass := 0
var _fail := 0


func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s" % msg)
	else:
		_fail += 1
		print("  [FAIL] %s" % msg)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 20:
		await process_frame

	var body := game.get_node_or_null(ROOM) as Node3D
	if body == null:
		print("[FAIL] 没有 %s" % ROOM)
		quit(1)
		return

	# ── ① 数量 + 名字 ──
	print("\n=== ① 凳子盒数量 ===")
	var chairs: Array[CollisionShape3D] = []
	var all_names: Array[String] = []
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null:
			continue
		all_names.append(cs.name)
		if String(cs.name).begins_with(CHAIR):
			chairs.append(cs)
	print("  RoomCollision 下共 %d 个碰撞盒：%s" % [all_names.size(), ", ".join(all_names)])
	_check(chairs.size() == N_CHAIR,
		"%s* 共 %d 个（要 %d 个）" % [CHAIR, chairs.size(), N_CHAIR])
	var names: Array[String] = []
	for cs in chairs:
		names.append(String(cs.name))
	names.sort()
	var want_names: Array[String] = [CHAIR]
	for i in range(2, N_CHAIR + 1):
		want_names.append("%s%d" % [CHAIR, i])
	want_names.sort()
	_check(names == want_names, "名字正好是 %s" % ", ".join(want_names))

	# ── ② 尺寸 + 完全重合 ──
	print("\n=== ② 尺寸与位置 ===")
	var shared_shape: BoxShape3D = null
	var sharing := 0
	for cs in chairs:
		var b := cs.shape as BoxShape3D
		if b == null:
			_check(false, "%s 的 shape 不是 BoxShape3D" % cs.name)
			continue
		if shared_shape == null:
			shared_shape = b
		if b == shared_shape:
			sharing += 1
		var ds: Vector3 = b.size - CHAIR_SIZE
		var dp: Vector3 = cs.global_position - CHAIR_POS
		_check(ds.length() < 1e-4 and dp.length() < 1e-3,
			"%-12s 尺寸 %.4f×%.4f×%.4f  世界 %s（与基准差 %.4f m）"
			% [cs.name, b.size.x, b.size.y, b.size.z,
				str(cs.global_position.snappedf(0.001)), dp.length()])
	# ── ③ 共用资源 ──
	print("\n=== ③ 共用同一个 shape 子资源 ===")
	_check(sharing == N_CHAIR,
		"%d/%d 个盒子共用同一个 BoxShape3D（改一次 size 十个一起变）" % [sharing, N_CHAIR])

	# ── ④ 房间矩形没被带歪 ──
	print("\n=== ④ 房间矩形 / 高度窗口（只认 y > 2.0 的墙）===")
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var n_wall := 0
	var n_furn := 0
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		if s.y <= 2.0:
			n_furn += 1
			continue
		n_wall += 1
		var bb: AABB = cs.global_transform * AABB(-s * 0.5, s)
		lo = lo.min(bb.position)
		hi = hi.max(bb.position + bb.size)
	print("  墙 %d 个、家具/屋顶板 %d 个" % [n_wall, n_furn])
	_check(n_wall == 5, "墙仍然是 5 面（家具没被当成墙）")
	_check(n_furn == 2 + N_CHAIR, "家具/屋顶板 %d 个 = 桌子 1 + 屋顶板 1 + 凳子 %d"
		% [n_furn, N_CHAIR])
	var dlo: Vector3 = lo - WALL_LO
	var dhi: Vector3 = hi - WALL_HI
	print("  墙 AABB lo %s  hi %s" % [str(lo.snappedf(0.001)), str(hi.snappedf(0.001))])
	_check(dlo.length() < 1e-3 and dhi.length() < 1e-3,
		"墙 AABB 与加椅子之前一致（偏差 lo %.4f / hi %.4f m）"
		% [dlo.length(), dhi.length()])
	# 泼溅那边自己算的房间矩形（XZ 无条件并集，但 10 个盒子完全重合 ⇒ 不该变）
	var room609 := game.get_node_or_null("Room609")
	if room609 != null and room609.has_method("_room_xz_from_walls"):
		var r: Rect2 = room609.call("_room_xz_from_walls")
		print("  _room_xz_from_walls() = %s" % str(r))
		_check(r.size.x > 1.0 and r.size.y > 1.0,
			"泼溅的房间矩形还量得出来（%.2f × %.2f m）" % [r.size.x, r.size.y])
	else:
		_check(false, "Room609 上找不到 _room_xz_from_walls()")

	# ── ⑤ 物理挡人 ──
	print("\n=== ⑤ 射线：凳顶能被打到 ===")
	var space := game.get_world_3d().direct_space_state
	var from := CHAIR_POS + Vector3(0, 3.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -3.0, 0))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_check(false, "从凳子上方 3 m 往下打射线，什么都没打到")
	else:
		var y: float = (hit["position"] as Vector3).y
		var top := CHAIR_POS.y + CHAIR_SIZE.y * 0.5
		print("  命中 y = %.3f（凳顶 %.3f）" % [y, top])
		_check(absf(y - top) < 0.05, "射线落在凳顶 y = %.3f（±0.05）" % top)

	print("\n通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

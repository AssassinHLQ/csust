extends SceneTree
## 自检：电竞房**门洞能走进去**，而且墙别处还是实的。
##
## 用户 2026-11-09：「电竞房进不去门,挡住了」「优化电竞房碰撞」。
##
## 修法见 `scripts/_bake_esports_parts.gd::NO_COLLIDE`：门板 JJKJ209/211/213/214
## 与门槛 物件_6 不再生成碰撞盒。
##
## 本自检只信**射线实测**（不猜）：
##   ① 门洞范围（局部 x −2.55..1.00, y 0.60..2.20, z 穿过 2.6→3.05）→ 必须**穿过去**
##   ② 门洞同一面墙的左右两侧（x −4.3..−2.7 与 1.2..4.2）→ 必须**被挡住**
##   ③ 对面实墙（z=−7.7）→ 必须**被挡住**（防止「把所有碰撞都删了」这种假修好）
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_esports_door_pass.gd

const BAKED := "res://scenes/esports_collision_baked.tscn"

## 门洞（来自 `esports_parts.json` 实测）
const DOOR_X0 := -2.55
const DOOR_X1 := 1.00
const DOOR_Y0 := 0.60
const DOOR_Y1 := 2.20
const DOOR_Z := 2.805          # 墙中心
const RAY_OUT_Z := 4.0         # 门外
const RAY_IN_Z := 1.5          # 门内

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


## 从 (x, y, z0) 打到 (x, y, z1)，返回是否被挡住
func _blocked(x: float, y: float, z0: float, z1: float) -> bool:
	var space := root.world_3d.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, y, z0), Vector3(x, y, z1))
	q.collide_with_areas = false
	return not space.intersect_ray(q).is_empty()


func _run() -> void:
	print("========== 电竞房门洞通行自检 ==========")
	var ps := load(BAKED) as PackedScene
	if ps == null:
		push_error("[verify] 加载不了 %s" % BAKED)
		quit(1)
		return
	var col := ps.instantiate()
	root.add_child(col)
	await process_frame

	var n_shapes := col.find_children("*", "CollisionShape3D", true, false).size()
	print("碰撞形状数 = %d" % n_shapes)

	# ① 门洞：多组射点，全部都不该被挡
	var open_ok := 0
	var open_total := 0
	for xi in 7:
		var x := lerpf(DOOR_X0 + 0.25, DOOR_X1 - 0.25, float(xi) / 6.0)
		for yi in 4:
			var y := lerpf(DOOR_Y0 + 0.15, DOOR_Y1 - 0.15, float(yi) / 3.0)
			open_total += 1
			if not _blocked(x, y, RAY_IN_Z, RAY_OUT_Z):
				open_ok += 1
	print("\n门洞：%d/%d 条射线穿过" % [open_ok, open_total])
	_check(open_ok == open_total,
		"门洞整片都能走（%d/%d 通，x %.2f..%.2f / y %.2f..%.2f）" % [
			open_ok, open_total, DOOR_X0, DOOR_X1, DOOR_Y0, DOOR_Y1])
	_check(open_ok > 0, "至少有一条射线穿过门洞")

	# ② 同一面墙的左右两段必须还是实的
	var wall_blocked := 0
	var wall_total := 0
	for x in [-4.3, -3.8, -3.2, -2.8, 1.3, 2.0, 3.0, 4.0]:
		for y in [0.9, 1.6]:
			wall_total += 1
			if _blocked(float(x), float(y), RAY_IN_Z, RAY_OUT_Z):
				wall_blocked += 1
	print("前墙左右：%d/%d 条被挡住" % [wall_blocked, wall_total])
	_check(wall_blocked == wall_total,
		"门洞左右两侧的墙仍然是实的（%d/%d 挡住）" % [wall_blocked, wall_total])

	# ③ 对面实墙必须还挡（防止「全删了」这种假修好）
	var far_blocked := 0
	for x in [-3.0, 0.0, 3.0]:
		if _blocked(float(x), 1.4, -6.0, -9.0):
			far_blocked += 1
	print("对面实墙：%d/3 条被挡住" % far_blocked)
	_check(far_blocked == 3, "对面实墙仍然挡人（%d/3）" % far_blocked)

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 门通了，墙没塌" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)

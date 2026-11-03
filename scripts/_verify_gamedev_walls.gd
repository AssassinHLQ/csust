extends SceneTree
## 验「游戏开发部活动室」的四壁：从**屋里**往每个方向撞，看玩家会不会穿墙 / 卡进墙里。
##
##   _tools/run_probe.sh res://scripts/_verify_gamedev_walls.gd -- --splat=off
##
## 现有 `_verify_gamedev_room.gd` 只测了「门口能进」「西墙挡人」两条射线，
## 没测「从里面撞四壁」。用户 2026-11-03 报「碰撞不对，卡墙里面了」。
##
## 房间世界包围盒（实测）：x 45.11 ~ 58.83，z -5.64 ~ 5.64。
## 判据：撞完之后玩家必须还在包围盒内（留 0.6 m 余量给人形胶囊），
##       而且不该离墙超过 0.8 m（否则说明被弹开或穿过去了）。

const CENTER := Vector3(52.0, 0.35, 0.0)
const BOUND_X0 := 45.11
const BOUND_X1 := 58.83
const BOUND_Z0 := -5.64
const BOUND_Z1 := 5.64
const MARGIN := 0.6

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(12)

	var p := game.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		print("!! 没有 Player")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("[walls] 房间 x %.2f~%.2f  z %.2f~%.2f" % [BOUND_X0, BOUND_X1, BOUND_Z0, BOUND_Z1])

	var yaws := [0.0, PI * 0.25, PI * 0.5, PI * 0.75,
		PI, -PI * 0.75, -PI * 0.5, -PI * 0.25]
	for y in yaws:
		await _run_one(p, float(y))

	print("[walls] 结果：%s" % ("OK" if _fail == 0 else "FAIL %d" % _fail))
	quit(1 if _fail > 0 else 0)


func _run_one(p: CharacterBody3D, yaw: float) -> void:
	_release()
	p.velocity = Vector3.ZERO
	p.global_position = CENTER
	p.set("_yaw", yaw)
	await _wait(20)

	var start := p.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2200:
		await process_frame
	_release()
	await _wait(10)

	var end := p.global_position
	var dx := end.x - start.x
	var dz := end.z - start.z
	var dist := sqrt(dx * dx + dz * dz)
	var inside := end.x > BOUND_X0 + MARGIN and end.x < BOUND_X1 - MARGIN \
		and end.z > BOUND_Z0 + MARGIN and end.z < BOUND_Z1 - MARGIN

	# 离最近那面墙的距离（判「是不是贴住墙了」）
	var wall_gap := minf(minf(end.x - BOUND_X0, BOUND_X1 - end.x),
		minf(end.z - BOUND_Z0, BOUND_Z1 - end.z))

	print("[walls] yaw=%+.2f  走了 %5.2f m → (%.2f, %.2f, %.2f)  离最近墙 %.2f m  %s" % [
		yaw, dist, end.x, end.y, end.z, wall_gap, "在屋里" if inside else "★ 穿出去了"])

	if not inside:
		print("[walls] FAIL: 这个方向能走出房间（撞穿了墙）")
		_fail += 1
	elif wall_gap > 1.2:
		print("[walls] ⚠️ 走了 %.2f m 却离墙 %.2f m —— 可能被什么东西挡住了，不一定是 bug" % [
			dist, wall_gap])


func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(a)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

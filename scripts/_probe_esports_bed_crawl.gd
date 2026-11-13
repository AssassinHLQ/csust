extends SceneTree
## 验收：电竞房双层床下铺睡龛本身能容纳蹲伏胶囊（用户 2026-11-13「床为什么不能钻进去?要能进去的」；
## 2026-11-14 用户确认家具不挪、过道自己过得去，故只验睡龛容积，不验过道穿行）。
## 真物理：蹲伏落在床垫实测面 y≈0.556；龛内松 Ctrl 不站起（头顶净空 0.875 m）；
## 朝 +X 推被护栏挡住不穿模；站姿胶囊放不进睡龛（净空查询阻挡）。
##   _tools/run_probe.sh res://scripts/_probe_esports_bed_crawl.gd -- --splat=off --story=off

const MOUTH := Vector3(54.0, 0.7, 10.78)
const MATTRESS_Y := 0.556

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for _i in 3:
		await process_frame
	print("═══ 电竞房双层床 · 下铺睡龛容积验收 ═══\n")
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame
	var room := game.get_node_or_null("EsportsRoom") as Node3D
	var player := game.get("_player") as CharacterBody3D
	if room == null or player == null:
		print("!! 缺房间或玩家")
		quit(1)
		return
	room.visible = true
	for _f in 5:
		await process_frame
	var cap := (player.get_node("Collision") as CollisionShape3D).shape as CapsuleShape3D

	# ── ① 蹲伏落进睡龛：脚踩床垫实测面 ──
	player.global_position = MOUTH
	player.velocity = Vector3.ZERO
	Input.action_press("crouch")
	await _wait(30)
	var p := player.global_position
	var gap := p.y - MATTRESS_Y
	print("① 蹲伏落入  脚底 y=%.3f（床垫面 %.3f，悬浮 %.3f m）  胶囊高 %.2f  safe_margin=%.2f"
		% [p.y, MATTRESS_Y, gap, cap.height, player.safe_margin])
	# 容差按 safe_margin 实测：CharacterBody3D 停靠会留最多 safe_margin 的悬浮
	# （实测 0.031 m ≤ 0.04），不是陷床；下限 −0.01 挡住「脚陷进床垫」。
	_check(gap > -0.01 and gap <= player.safe_margin + 0.005,
		"蹲伏胶囊落在床垫实测面（不陷床，悬浮 ≤ safe_margin）")
	_check(is_equal_approx(cap.height, 0.8), "蹲伏胶囊 0.8 m < 净高 0.875 m")

	# ── ② 龛内松 Ctrl：头顶净空不足，应保持蹲姿 ──
	Input.action_release("crouch")
	for _f in 30:
		await physics_frame
	print("② 龛内松 Ctrl  胶囊高 %.2f（应仍 0.8）" % cap.height)
	_check(is_equal_approx(cap.height, 0.8), "龛内不强行站起（头不穿床板）")

	# ── ③ 蹲伏朝 +X 推：护栏挡住，不穿出床侧 ──
	# 相机 yaw 每帧被玩家脚本写回，改 rig 旋转没用；yaw=0 时 move_right 即 +X。
	Input.action_press("crouch")
	await _wait(6)
	Input.action_press("move_right")
	for _f in 90:
		await physics_frame
	Input.action_release("move_right")
	await _wait(6)
	p = player.global_position
	print("③ 龛内朝 +X 推  x=%.3f（护栏 x≈54.39，胶囊心应 ≤54.15）" % p.x)
	_check(p.x < 54.15, "护栏挡住，不穿出床侧")

	# ── ④ 站姿净空查询：睡龛里站不起来 ──
	player.global_position = Vector3(MOUTH.x, MATTRESS_Y, MOUTH.z)
	player.velocity = Vector3.ZERO
	await _wait(6)
	var blocked: bool = not player._stand_headroom_clear()
	print("④ 睡龛内站姿净空查询  阻挡=%s（应 true）" % str(blocked))
	_check(blocked, "睡龛净空不足以站起")

	# ── ⑤ 回到开阔地松 Ctrl：自动站起 ──
	Input.action_release("crouch")
	player.global_position = Vector3(53.3, 0.6, 11.42)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await physics_frame
	p = player.global_position
	print("⑤ 开阔地  胶囊高 %.2f（应 1.5）  脚底 y=%.3f" % [cap.height, p.y])
	_check(is_equal_approx(cap.height, 1.5), "出龛后自动站起")

	_summary()
	quit(0 if _fail == 0 else 1)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
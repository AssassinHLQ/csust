extends SceneTree
## 验证飞行尾迹粒子「高速时不断成串珠」（用户 2026-11-11）：
## 「飞行太快后面蓝色小粒子特效跟不上了」+ 截图里那条断续蓝点链。
##
## 量的是核心指标：**尾迹每米有多少颗粒子**。
## 尾迹长度 ≈ 速度 × 寿命；在场粒子数 = amount；所以
##     每米粒子数 = amount / (速度 × lifetime)
## 人眼要看不到断点，这个值大约要 ≥ 30（粒子直径 0.3~0.8 m）。
##
##   & <godot> --headless --path . --script res://scripts/_verify_carrier_trail.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [what, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [what, ("  " + detail) if detail != "" else ""])


func _run() -> void:
	print("========== 飞行尾迹粒子密度 ==========")
	MechState.set_carrier_for_test(true)
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	var cf = player.get_node_or_null("Arisu/CarrierForm")
	if cf == null or not cf.call("set_form", true):
		push_error("[trail] 变形失败")
		quit(1)
		return
	# 等预建/预热走完
	for _i in 40:
		await process_frame
	cf.set_process(false)
	cf.set_physics_process(false)

	var fx: Array = cf.get("_boost_fx")
	_check(fx.size() > 0, "拿到推进器特效组", "%d 组" % fx.size())
	if fx.is_empty():
		quit(1)
		return
	var gp := fx[0]["particles"] as GPUParticles3D
	var life: float = gp.lifetime
	print("  粒子寿命 %.2f s｜直径 0.30~0.80 m" % life)
	print("")
	print("  速度(m/s)   amount   尾迹长(m)   每米粒子数")
	var worst := 999.0
	for sp in [0.0, 3.0, 6.0, 12.0, 19.0, 25.0]:
		var amt: int = cf.call("_particle_amount_for_speed", sp)
		var tail: float = maxf(sp, 0.001) * life
		var per_m: float = float(amt) / maxf(tail, 0.001)
		if sp >= 6.0:
			worst = minf(worst, per_m)
		print("  %8.1f   %6d   %9.2f   %10.1f" % [sp, amt, tail, per_m])

	print("")
	_check(worst >= 30.0, "高速段每米粒子数 ≥ 30（不断成串珠）",
		"最差 %.1f 颗/米" % worst)
	# 低速不该被削到比原来还少
	var low: int = cf.call("_particle_amount_for_speed", 0.0)
	_check(low >= 96, "低速段不低于原来的 96", "%d" % low)
	# 上限别把粒子数顶爆（性能）。两组推进器 × 480 = 960 颗，可接受。
	var top: int = cf.call("_particle_amount_for_speed", 40.0)
	_check(top <= 480, "上限不超过 480（性能）", "%d" % top)

	print()
	print("========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

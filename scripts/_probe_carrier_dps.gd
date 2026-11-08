extends SceneTree
## 验「激光大炮的持续输出到底比机枪强还是弱」。
##
## 用户 2026-11-08：「怎么感觉机甲还没有机枪强」——**他是对的**。本喵当初只盯着
## 单发伤害（18 → 57.6，看着涨了 3 倍），没回头算**持续 DPS**：
##   机枪：18 / 0.075 s = 240 DPS
##   旧大炮：57.6 / 0.42 s = 137 DPS（只有机枪的 57%）
## 间隔拉长到 0.42 秒是为了「一发一发的炮感」，但那把总输出拉垮了。
##
## 这条自检不读常数、不看公式，而是**真开火、真打靶**：放一个会记账的靶子，
## 两种模式各打 4 秒，把「实际吃到的伤害 / 实际耗时」算出来。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_probe_carrier_dps.gd -- --no-capture

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
## 打多久（秒）。够长到能盖住两种模式的发射间隔差异。
const WINDOW := 4.0
## 大炮 DPS 至少要是机枪的几倍
const MIN_RATIO := 1.6
## 大炮 DPS 的绝对下限
const MIN_BEAM_DPS := 400.0

var _player: Player
var _wpn: Weapon
var _dummy: Dummy
var _pass := 0
var _fail := 0


## 记账靶子：只关心「一共吃了多少伤害、被打中几次」。
class Dummy extends StaticBody3D:
	var total := 0.0
	var hits := 0

	## ⚠️ 第三个参数是**击退方向（Vector3）**不是力度 —— `Weapon._apply_hit()` 传的是
	## `-dir`。写成 float 会直接报「Cannot convert argument 3 from Vector3 to float」。
	func take_damage(amount: float, _from := Vector3.ZERO, _knock_dir := Vector3.ZERO) -> void:
		total += amount
		hits += 1


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	MechState.set_carrier_for_test(true)
	var stage := Node3D.new()
	stage.name = "DpsStage"
	root.add_child(stage)

	_player = PlayerScene.instantiate() as Player
	stage.add_child(_player)
	await process_frame
	await process_frame

	_wpn = _player.get_node_or_null("Weapon") as Weapon
	if _wpn == null:
		push_error("[DPS] 没有 Weapon")
		quit(1)
		return

	# 不跑物理：这条自检只关心开火，不关心站立 / 掉落。
	# `set_flight_lock(true)` 让 `player.gd` 跳过重力与跳跃，位置就稳住了。
	_player.global_position = Vector3(0, 0.6, 0)
	_player.set("velocity", Vector3.ZERO)
	_player.call("set_flight_lock", true)

	# 记账靶子：摆正前方 8 m（角色朝向 −Z）
	_dummy = Dummy.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 4)
	col.shape = box
	_dummy.add_child(col)
	_dummy.position = Vector3(0, 1.2, -8)
	stage.add_child(_dummy)
	var dummy := _dummy

	# 让镜头盯住靶子，这样「相机中心射线」才真的压在靶子上
	_player.call("look_at_node", dummy, 999.0)
	for i in 120:
		await physics_frame
	_player.set("velocity", Vector3.ZERO)

	print("")
	print("========== 0. 先确认真的打得中 ==========")
	_wpn.current_ammo = _wpn.magazine_size
	var first_hit := _wpn.shoot()
	await physics_frame
	_check(first_hit, "开火成功（朝向已对准靶子）")
	_check(dummy.hits == 1, "第一发就打中了靶子（命中 %d 次）" % dummy.hits)
	if dummy.hits == 0:
		print("      ⚠️ 一发都没打中，下面的 DPS 数字没有意义，先修镜头")
		_done()
		return

	print("")
	print("========== 1. 本体机枪 ==========")
	_wpn.call("set_beam_mode", false)
	_wpn.call("set_carrier_muzzles", [] as Array[Vector3])
	dummy.total = 0.0
	dummy.hits = 0
	var rifle := await _measure(WINDOW)
	var rifle_dps: float = rifle["damage"] / maxf(float(rifle["secs"]), 0.01)
	print("       %.2f 秒 / %d 发 / 合计 %.0f 伤害 → **%.0f DPS**（单发 %.1f）" % [
		rifle["secs"], rifle["shots"], rifle["damage"], rifle_dps, rifle["damage"] / maxf(float(rifle["shots"]), 1.0)])
	_check(rifle["shots"] > 10, "机枪在这段时间里打出了足够多发的子弹（%d 发）" % rifle["shots"])

	print("")
	print("========== 2. 激光大炮 ==========")
	# 两门肩炮的炮口：只要非空 `use_beam()` 就成立（视觉位置这里不关心）
	var muzzles: Array[Vector3] = [Vector3(-0.4, 1.5, 0.0), Vector3(0.4, 1.5, 0.0)]
	_wpn.call("set_carrier_muzzles", muzzles)
	_wpn.call("set_beam_mode", true)
	_check(_wpn.call("use_beam"), "Weapon 切到了光束模式")
	dummy.total = 0.0
	dummy.hits = 0
	var beam := await _measure(WINDOW)
	var beam_dps: float = beam["damage"] / maxf(float(beam["secs"]), 0.01)
	var ratio := beam_dps / maxf(rifle_dps, 0.01)
	print("       %.2f 秒 / %d 发 / 合计 %.0f 伤害 → **%.0f DPS**（单发 %.1f）" % [
		beam["secs"], beam["shots"], beam["damage"], beam_dps, beam["damage"] / maxf(float(beam["shots"]), 1.0)])
	print("       大炮 / 机枪 = **%.2f 倍**" % ratio)

	print("")
	print("========== 3. 结论 ==========")
	_check(beam_dps >= MIN_BEAM_DPS, "大炮 DPS 达标（%.0f ≥ %.0f）" % [beam_dps, MIN_BEAM_DPS])
	_check(ratio >= MIN_RATIO, "大炮明显强过机枪（%.2f 倍 ≥ %.2f 倍）" % [ratio, MIN_RATIO])
	_check(beam["damage"] / maxf(float(beam["shots"]), 1.0) > rifle["damage"] / maxf(float(rifle["shots"]), 1.0),
		"大炮单发比机枪单发重（这是「炮」的基本体面）")

	_done()


## 真开火打 `WINDOW` 秒，返回实际耗时 / 发数 / 总伤害。
##
## ⚠️ 每帧把弹匣补满：这里量的是「武器本身的持续输出」，
##    不想让换弹（1.05 s）混进来把两种模式的差异糊掉。
func _measure(seconds: float) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var shots := 0
	var dmg0: float = _dummy.total
	while float(Time.get_ticks_msec() - t0) < seconds * 1000.0:
		_player.set("velocity", Vector3.ZERO)
		_wpn.current_ammo = _wpn.magazine_size
		_wpn.set("_reloading", false)
		if _wpn.shoot():
			shots += 1
		await physics_frame
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	return {"secs": secs, "shots": shots, "damage": _dummy.total - dmg0}


func _done() -> void:
	MechState.set_carrier_for_test(false)
	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

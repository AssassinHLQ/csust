extends SceneTree
## 验「飞猪优香的击败奖励直接进银行卡」。
##
## 用户 2026-11-09：「把飞猪优香的击败奖励从 1w 资产变成直接 1w 进银行卡」。
##
## 背景：`boss.gd::_die()` 原来把掉落塞进「本轮资产」（跑酷结算台再转卡），
## 因为用户 2026-11 报过「为什么我还没有结算就 40w 了」。
## 现在给 Boss 加了 `drop_to_bank` 开关，**只有飞猪优香**打开它。
##
## 本自检同时验两条：
##   ① 飞猪：银行卡 +10000，本轮资产不变
##   ② 霸王龙：银行卡不变，本轮资产 +drop（默认行为没被改坏）
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_verify_pig_drop.gd

const BankCard := preload("res://scripts/bank_card.gd")
const PigBoss := preload("res://scripts/pig_boss.gd")
const TrexBoss := preload("res://scripts/trex_yuuka_boss.gd")

var _pass := 0
var _fail := 0


## 记「本轮资产」的假结算台：只要 `add_loot` 被调用就记下来。
class FakeFutures extends Node:
	var loot := 0.0
	var calls := 0
	func add_loot(yuan: int, _why: String) -> void:
		loot += float(yuan)
		calls += 1


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
	var stage := Node3D.new()
	stage.name = "PigDropStage"
	root.add_child(stage)

	var fut := FakeFutures.new()
	fut.name = "FakeFutures"
	fut.add_to_group("futures")
	stage.add_child(fut)

	print("")
	print("========== 1. 飞猪优香：直接进银行卡 ==========")
	var bank0 := BankCard.balance()
	var pig: Boss = PigBoss.new()
	_check(bool(pig.get("drop_to_bank")), "飞猪的 drop_to_bank = true")
	_check(int(pig.get("drop_yuan")) == 10000, "掉落金额还是 10000")
	stage.add_child(pig)
	await process_frame
	pig.call("_die", 1.0)
	await process_frame
	var d_bank := BankCard.balance() - bank0
	print("       银行卡 %d → %d（+%d）｜ 本轮资产 +%.0f（%d 次）" % [
		bank0, BankCard.balance(), d_bank, fut.loot, fut.calls])
	_check(d_bank == 10000, "银行卡正好 +10000（实际 %+d）" % d_bank)
	_check(fut.calls == 0, "**没有**再走「本轮资产」那条路（实际调用 %d 次）" % fut.calls)
	pig.queue_free()
	await process_frame

	print("")
	print("========== 2. 霸王龙：默认行为没被改坏 ==========")
	var bank1 := BankCard.balance()
	var loot1 := fut.loot
	var trex: Boss = TrexBoss.new()
	_check(not bool(trex.get("drop_to_bank")), "霸王龙的 drop_to_bank 仍是 false（默认）")
	trex.set("drop_yuan", 5000)
	stage.add_child(trex)
	await process_frame
	trex.call("_die", 1.0)
	await process_frame
	var d_bank2 := BankCard.balance() - bank1
	print("       银行卡 %+d ｜ 本轮资产 +%.0f" % [d_bank2, fut.loot - loot1])
	_check(d_bank2 == 0, "霸王龙**不**直接给钱（银行卡 %+d）" % d_bank2)
	_check(fut.loot - loot1 == 5000.0, "霸王龙照旧进本轮资产（+%.0f）" % (fut.loot - loot1))
	trex.queue_free()

	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

extends SceneTree
## 验「每次重新打开游戏都是全新一局：机甲能力不保留」。
##
## 这条**必须跨进程**才能验：同一个进程里 `MechState._loaded` 会把第二次
## `_ensure()` 挡掉，所以「重新打开游戏」只能靠**真的起一个新的 Godot 进程**。
## 于是本自检分两步，第二个进程才是重点：
##
##   & <godot> --headless --path . --script res://scripts/_verify_mech_reset.gd -- --phase=1
##   & <godot> --headless --path . --script res://scripts/_verify_mech_reset.gd -- --phase=2
##
## 两条都要打印「全部 N 项通过」才算过。

const MechState := preload("res://scripts/mech_state.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _phase() -> int:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--phase="):
			return int(String(a).split("=")[1])
	return 0


## 直接读盘上那一行，绕开 `MechState` 的内存状态 —— 用来证明
## 「上一局写的 true 真的被覆写了」。
func _disk_value() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(MechState.PATH) != OK:
		return false
	return bool(cfg.get_value(MechState.SECTION, "carrier_unlocked", false))


func _run() -> void:
	var ph := _phase()
	if ph == 1:
		print("========== 第 1 局（这一局里找凯伊改装完成）==========")
		_check(not MechState.carrier_unlocked(), "开局还没解锁")
		MechState.unlock_carrier()
		_check(MechState.carrier_unlocked(), "本局内解锁成功")
		_check(_disk_value(), "落盘写成 true（调试时能打开 mech.cfg 查证）")
	elif ph == 2:
		print("========== 第 2 局（重新打开游戏）==========")
		# 顺序要紧：先问「解锁了吗」，`_ensure()` 才会跑。
		var unlocked := MechState.carrier_unlocked()
		_check(not unlocked, "新开一局回到「未解锁」（没有读旧存档）")
		_check(not _disk_value(), "盘上那行 true 已被 `_ensure()` 覆写成 false")
		# 本局内仍然能正常解锁 —— 别把功能一起砍了
		MechState.unlock_carrier()
		_check(MechState.carrier_unlocked(), "本局内照样能找凯伊解锁")
		# 收尾：把盘上留成 false，免得给下一次自检留一个 true 的疑点
		MechState.reset()
		_check(not MechState.carrier_unlocked(), "reset() 能清掉本局的解锁")
	else:
		push_error("[Verify] 要 --phase=1 或 --phase=2")
		quit(1)
		return

	print("")
	print("========== 结果（phase %d）==========" % ph)
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

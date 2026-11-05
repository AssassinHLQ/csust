extends RefCounted
## 阿比·埃舒（机甲 / 载具形态）的状态：**是否已经由凯伊改装完成**。
##
## 落盘 `user://mech.cfg`。和 `BankCard` / `SceneFlow` / `GameSettings` 一样走
## 「preload + 全静态」，不动 `project.godot` 的 autoload
## （用户不让改 autoload；而且 `--script` 自检模式下 autoload 名不是编译期可见的）。
##
## ⚠️ 和银行卡**故意不一样**：银行卡每局清零（用户要求），而改装是**剧情进度**，
##    跨启动保留 —— 不然每次开游戏都要重新掏一次改装费。
##
## 剧情出处（用户 2026-11-05 指出「不是买来的」）：
##   阿比·埃舒原本是**时（Toki）**的机体；被击毁后由**凯伊和爱丽丝合力**、
##   借「无名诸神」的力量重组到爱丽丝身上 —— 所以这里是「找凯伊改装」，
##   玩家出的是**材料 / 工时费**，不是买一台新机体。

const PATH := "user://mech.cfg"
const SECTION := "mech"

## 凯伊开价（元）。量级参考：柴关电脑城那台八卡 5090 整机是 ¥670,000，
## 一轮跑酷能挣 67 万上下 —— 所以这个价「得认真跑一趟，但一次够」。
const CARRIER_PRICE := 520000

static var _loaded := false
static var _carrier := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		_carrier = bool(cfg.get_value(SECTION, "carrier_unlocked", false))


## 载具（阿比·埃舒）是否已改装完成
static func carrier_unlocked() -> bool:
	_ensure()
	return _carrier


static func unlock_carrier() -> void:
	_ensure()
	if _carrier:
		return
	_carrier = true
	_save()
	print("[MechState] 阿比·埃舒改装完成（载具形态已解锁）")


## 调试 / 自检用：把进度清掉
static func reset() -> void:
	_ensure()
	_carrier = false
	_save()
	print("[MechState] 已重置：载具形态回到未解锁")


## 自检用：不写盘地摆一个状态
static func set_carrier_for_test(on: bool) -> void:
	_ensure()
	_carrier = on


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "carrier_unlocked", _carrier)
	cfg.save(PATH)

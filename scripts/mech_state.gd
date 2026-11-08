extends RefCounted
## 阿比·埃舒（机甲 / 载具形态）的状态：**本局是否已经由凯伊改装完成**。
##
## 落盘 `user://mech.cfg`。和 `BankCard` / `SceneFlow` / `GameSettings` 一样走
## 「preload + 全静态」，不动 `project.godot` 的 autoload
## （用户不让改 autoload；而且 `--script` 自检模式下 autoload 名不是编译期可见的）。
##
## ⚠️ **每次启动游戏都是全新的一局**（用户 2026-11-08：
##    「我每次重新打开游戏，就是全新的游戏，不要保留机甲能力」）。
##    做法和 `bank_card.gd` **完全一样**：`_ensure()` 不读旧存档，
##    直接把 `_carrier` 置回 false 并落盘。
##    所以凯伊那次改装、以及那笔「把整张卡刷光」的钱，**只在这一局里有效** ——
##    下次开游戏要重新走剧情、重新赚钱。用户给的理由是
##    「我的游戏整体流程是 20 分钟」：一局之内拿到机甲才算剧情节奏。
##
## 那为什么还要落盘：和银行卡同一个理由 —— **写，但下次不读**。
## 好处是调试时能直接打开 `user://mech.cfg` 看这一局到底解锁了没有，不用猜。
##
## 剧情出处（用户 2026-11-05 指出「不是买来的」）：
##   阿比·埃舒原本是**时（Toki）**的机体；被击毁后由**凯伊和爱丽丝合力**、
##   借「无名诸神」的力量重组到爱丽丝身上 —— 所以这里是「找凯伊改装」，
##   玩家出的是**材料 / 工时费**，不是买一台新机体。

const PATH := "user://mech.cfg"
const SECTION := "mech"

## 凯伊的**报价**（元）：用户 2026-11-05 的剧情里念的是「9178 万」。
##
## ⚠️ 这只是**台词里的数字**，没有参与任何余额判断 —— 用户定的成交方式原话是
##    「然后是扣除银行卡所有钱」：实际扣款 = 你卡上现有的全部。
##    所以这里保留它只为「别让报价散落在两个文件里」，真正的收费逻辑在
##    `kei_npc.gd::_on_dialogue_custom`。
const QUOTE_YUAN := 91780000

static var _loaded := false
static var _carrier := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	# 不读旧存档：新开一局就是一台还没改装的机体。
	# （旧值可能还留在文件里，但从这一行起不再使用 —— 见文件头。）
	_carrier = false
	_save()


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

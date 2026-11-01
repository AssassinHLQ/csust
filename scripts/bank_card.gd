extends RefCounted
## 银行卡余额（单位：元）。**全项目唯一**的钱包，落盘在 `user://bank_card.cfg`。
##
## 两处用它：
##   · 跑酷期货小游戏（`parkour_futures.gd`）：结算时把资产 + 保证金转进卡里，还债也从这里扣；
##   · 柴关电脑城（`shop_clerk.gd`）：买整机前查余额，够才让选，成交后扣款。
##
## 为什么不是 autoload：用户不让动 `project.godot`。和 `SceneFlow` / `UiSkin` 一样，
## 靠 `preload` + `static` 共享状态 —— 场景切换不影响，进程内只有一份。
##
## ⚠️ 默认 **0 元**（用户 2026-11：「从 0 开始」）—— 想买那台 67 万的整机，
##    得先去跑酷期货赚钱、打倭瓜优香拿掉落。调试时想看「买得起」的分支，
##    把 `user://bank_card.cfg` 里的 yuan 改大即可（或临时改这里）。

const PATH := "user://bank_card.cfg"
const DEFAULT_YUAN := 0

static var _loaded := false
static var _yuan := 0


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		_yuan = int(cf.get_value("card", "yuan", DEFAULT_YUAN))
	else:
		_yuan = DEFAULT_YUAN
		_save()


## 当前余额（元）
static func balance() -> int:
	_ensure()
	return _yuan


static func set_balance(yuan: int) -> void:
	_ensure()
	_yuan = maxi(0, yuan)
	_save()


static func add(yuan: int) -> void:
	if yuan > 0:
		set_balance(balance() + yuan)


static func can_afford(yuan: int) -> bool:
	return balance() >= yuan


## 够就扣并返回 true；不够**一分不扣**，返回 false。
static func spend(yuan: int) -> bool:
	if yuan <= 0:
		return true
	if not can_afford(yuan):
		return false
	set_balance(balance() - yuan)
	return true


static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("card", "yuan", _yuan)
	var err := cf.save(PATH)
	if err != OK:
		push_warning("[BankCard] 存档失败（%s）：%s" % [error_string(err), PATH])


## 「¥52.0 万」/「¥3,200」这种给人看的写法
static func format_yuan(yuan: int) -> String:
	if yuan >= 10000:
		return "¥%.1f 万" % (float(yuan) / 10000.0)
	return "¥%d" % yuan


## 自检用：把余额重置回默认值
static func reset_to_default() -> void:
	set_balance(DEFAULT_YUAN)

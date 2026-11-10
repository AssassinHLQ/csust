extends RefCounted
## 开发者模式开关（静态，**跨场景保留**）。
##
## 用户 2026-11-08：
##   「巡航者太慢了」                    → `carrier_form.gd` 的巡航倍率调大
##   「f3 点击后，除了开启帧率面板，还要开启开发者模式」
##   「f4 直接进入下一场景」
##   「f5 击败所有加载敌人」
##   「f6 提高角色速度三倍方便调试」
##
## 为什么单开一个静态脚本而不是塞进 `player.gd`：
##   `Player` 每个场景都会重建，开关状态会跟着丢。和 `SceneFlow` / `BankCard`
##   一样走「preload + 全静态」，不动 `project.godot` 的 autoload。
##
## ⚠️ F3 的**帧率面板**归 `game.gd`，本文件只管「开发者模式开没开」。
##
## ⚠️ 2026-11-10 修：「暂停时按 F3 没反应」
##
##   Player 是 `process_mode = PAUSABLE`，开 Esc 菜单 / 播剧情时它**收不到 `_input`**，
##   于是 F3 只能落到 `game.gd` —— 那边只开帧率浮层，**不会开开发者模式**。
##   结果就是「Esc 菜单开着的时候按 F3，面板出来了但 F4/F5/F6 不生效」。
##
##   修法：把「开关」做成 `GameSettings` 式的**一条设置项**，走 `listen()` 广播。
##   这样 `game.gd`（它是 ALWAYS）收到 F3 时写这个值，本文件的初值也跟着变。
##   **不用改动 `_input` 的注册方式**，也就不会破坏「F4/F5/F6 只在开发者模式下生效」
##   那条既有语义。
##
##   为什么走 `GameSettings` 而不是自己加一个 `static`：因为这个开关本来就是
##   「一个会话内的偏好」，`GameSettings` 已经有存档 + 变更广播 + 默认值，
##   再自己发明一套只会走散。

const KEY := "dev_mode"

## 监听者（用一次 `listen()` 就够了；本类是全静态，不需要实例）
static var _hooked := false


## 先把 `GameSettings` 的默认值注册进去（幂等，重复调没副作用）。
static func ensure_registered() -> void:
	if _hooked:
		return
	_hooked = true
	GameSettings.listen(_on_changed)


## 现在开没开。
static func is_on() -> bool:
	ensure_registered()
	return bool(GameSettings.value(KEY, false))


static func set_on(on: bool) -> void:
	ensure_registered()
	GameSettings.set_value(KEY, on)


## 切换，返回切换后的状态（F3 用）
static func toggle() -> bool:
	ensure_registered()
	var on := not bool(GameSettings.value(KEY, false))
	GameSettings.set_value(KEY, on)
	return on


## `GameSettings` 变更广播回来时什么都不用做 —— 状态就在它那儿。
static func _on_changed(_key: String, _value: Variant) -> void:
	pass

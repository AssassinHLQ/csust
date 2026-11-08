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
## ⚠️ F3 的**帧率面板**仍然归 `game.gd`（它自己监听 F3）。本文件只管
##    「开发者模式开没开」。两边各吃各的，不会互相顶掉。

static var _loaded := false
static var _on := false


static func is_on() -> bool:
	return _on


static func set_on(on: bool) -> void:
	_on = on


## 切换，返回切换后的状态（F3 用）
static func toggle() -> bool:
	_on = not _on
	return _on

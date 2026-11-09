extends SceneTree
## 公共启动器：**把窗口丢出屏幕、取消最大化、不抢鼠标**。
##
## 出图探针第一行调 `OffscreenWindow.apply(self)` 即可。
##
## ── 为什么需要它（2026-11-09 实测）──
## 用户：「你弹窗口测试不要抢占我的前台，你在后台弹窗口测试，不要影响我玩游戏」。
##
## 一开始以为给命令行加 `--position -4000,-4000 --resolution 1280x720 --windowed`
## 就够了 —— **不够**。实测窗口仍然开在 (0, 34)、2560×1334、还抢到了焦点。
##
## 真因：`project.godot` 里 `window/size/mode=2`（**最大化**）。
## 项目设置在启动时先于命令行生效，把 `--windowed` / `--position` 全顶掉了。
##
## 所以必须在**脚本运行时**再改一次窗口状态，那时代码已经跑起来了，
## 一定盖得住项目设置。

class_name OffscreenWindow


## 把当前窗口挪到屏幕外并缩到不碍事的小尺寸。
##
## `tree` 传 `self`（SceneTree）。改完之后等几帧，让 DisplayServer 真正应用。
static func apply(tree: SceneTree, size := Vector2i(960, 540)) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	# 等窗口管理器把变更吃进去（不等的话后面读回来的还是旧值）
	for _i in 3:
		await tree.process_frame


## 自检用：当前窗口是否已经在屏幕外、且没抢鼠标。
## 返回 [ok: bool, 说明: String]
static func is_safe() -> Array:
	var pos := DisplayServer.window_get_position()
	var mm := Input.mouse_mode
	var problems: Array[String] = []
	if pos.x > -1000 and pos.y > -1000:
		problems.append("窗口在屏幕内 %s" % str(pos))
	if mm == Input.MOUSE_MODE_CAPTURED:
		problems.append("抢走了鼠标（mouse_mode=CAPTURED）")
	if problems.is_empty():
		return [true, "窗口在屏幕外 %s，mouse_mode=%d" % [str(pos), mm]]
	return [false, "；".join(problems)]

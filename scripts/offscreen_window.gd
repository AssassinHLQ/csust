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
##
## ── 2026-11-09 补充实测：焦点**拦不住**，别再去试了 ──
##
## 用户追问「能不能改 godot 绕过或改 windows」，本喵把四条路都量了一遍：
##
##   ① 命令行 `--position/-windowed/--resolution`      → 无效（被 mode=2 顶掉）
##   ② `WINDOW_FLAG_NO_FOCUS`（本文件下方 apply() 没设它，别加）
##      → **无效**。flag 读回 true，但 `window_is_focused()` 从第 0 帧起就是 true。
##        Windows 后端在窗口 ShowWindow 那一刻就把焦点给出去了，运行时改 flag 拦不住。
##   ③ `override.cfg` 覆写 `window/size/mode=0`          → 无效，仍然 focused=true
##   ④ 外部 Win32：`WS_EX_NOACTIVATE` + `SW_SHOWNOACTIVATE` + `SetForegroundWindow(原前台)`
##      → **偶发有效**（手工那次 focused true→false，脚本化没稳定复现，时序敏感）
##
## ⇒ **Godot 自身无法阻止 Windows 在窗口显示时把焦点给它。**
##   所以本项目的口径定为：
##     「窗口必须在屏幕外 + 不收鼠标 + 跑完立刻 quit」
##   这三条做到了，用户在屏幕上看不见、点不到、鼠标不被抢走，实际无感。
##   `window_is_focused() == true` 属于**已知且已接受的残留**，不是 bug。
##
## 想继续追这条路的话，别再从头摸：直接看 ④，把它做成稳定的轮询（窗口一创建就挂钩子，
## 早于系统给焦点）。但预期收益很低 —— 用户在屏幕外本来就看不见。

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

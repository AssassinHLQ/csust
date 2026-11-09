extends SceneTree
## ⚠️ 用 preload 而不是全局类名：--script 模式下解析不到 class_name（本项目栽过）。
const OffWin := preload("res://scripts/offscreen_window.gd")
## 自检：**出图时不许抢用户前台**。
##
## 用户 2026-11-09：「你弹窗口测试不要抢占我的前台，你在后台弹窗口测试，
## 不要影响我玩游戏」。
##
## 直接打印运行时看到的窗口位置、焦点状态、鼠标模式、命令行 user args，
## 让"有没有抢前台"变成可核实的事实而不是口头保证。
##
## 用法：_tools/run_shot.sh res://scripts/_probe_no_steal_focus.gd
## 期望输出：pos 在屏幕外、mouse_mode = 0（VISIBLE）、带 --no-capture

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# ⚠️ **必须在脚本里自己动手**，不能指望命令行参数。
	#
	# 实测（本探针第一版）：`--position -4000,-4000 --resolution 1280x720` **完全无效**，
	# 窗口仍然开在 (0, 34)、尺寸 2560x1334、而且抢到了焦点。
	# 原因：`project.godot` 里 `window/size/mode=2`（**最大化**），
	# 项目设置在启动时优先生效，把命令行请求的 windowed/position 顶掉了。
	#
	# 所以出图探针要自己把窗口挪走 + 取消最大化。两行就够：
	await OffWin.apply(self)
	for _i in 7:
		await process_frame

	var win_pos := DisplayServer.window_get_position()
	var win_size := DisplayServer.window_get_size()
	var focused := DisplayServer.window_is_focused()
	var mm := Input.mouse_mode
	var args := OS.get_cmdline_user_args()

	print("========== 抢前台自检 ==========")
	print("  窗口位置      : %s" % str(win_pos))
	print("  窗口尺寸      : %s" % str(win_size))
	print("  有焦点        : %s" % str(focused))
	print("  mouse_mode    : %d  (0=VISIBLE 不抢鼠标 / 2=CAPTURED 抢走了)" % mm)
	print("  user args     : %s" % str(args))

	var fail := 0
	# ① 窗口必须在屏幕外（run_shot.sh 用 -4000,-4000）
	if win_pos.x < -1000 or win_pos.y < -1000:
		print("  ✓ 窗口在屏幕外 %s —— 用户看不见" % str(win_pos))
	else:
		print("  ✗ 窗口在屏幕内 %s —— 会挡住用户！" % str(win_pos))
		fail += 1
	# ② 不许抢鼠标
	if mm != Input.MOUSE_MODE_CAPTURED:
		print("  ✓ 没有抢鼠标（mouse_mode=%d，不是 CAPTURED）" % mm)
	else:
		print("  ✗ **抢走了鼠标**（mouse_mode=CAPTURED）—— 用户点不到任务栏")
		fail += 1
	# ③ --no-capture 必须真的传进来
	if args.has("--no-capture"):
		print("  ✓ 命令行带 --no-capture")
	else:
		print("  ✗ **没有 --no-capture** —— run_shot.sh 的参数漏了")
		fail += 1
	# ④ 有声卡驱动时也别出声（Dummy）
	print("  · （音频用 --audio-driver Dummy，静音）")

	print("\n  %s" % ("★ 全部通过：没有抢用户前台" if fail == 0 else "★ %d 项不合规" % fail))
	quit(0 if fail == 0 else 1)

extends SceneTree
## 探针：「跑游戏会不会抢鼠标」——带 `--no-capture` 与不带，各读一次 mouse_mode。
##
## 用户 2026-10-21：「每次你运行游戏都会抢占鼠标一瞬间，然后我就点不到下面的任务栏了」
## 修法：`player.gd::_may_capture()` 要求「窗口已获焦」且「没有 --no-capture」。
## 这个探针就是它的验收：同一份场景，加不加那个参数，mouse_mode 必须不一样。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_mouse_capture.gd -- --splat=off
##   godot --path <工程> --script res://scripts/_probe_mouse_capture.gd -- --splat=off --no-capture
## 输出：一行结论（CAPTURED / VISIBLE）

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 20:
		await process_frame
	var mode := Input.mouse_mode
	var names := {Input.MOUSE_MODE_VISIBLE: "VISIBLE", Input.MOUSE_MODE_CAPTURED: "CAPTURED",
		Input.MOUSE_MODE_CONFINED: "CONFINED", Input.MOUSE_MODE_HIDDEN: "HIDDEN"}
	var flag := OS.get_cmdline_user_args().has("--no-capture")
	print("[mouse] window_focused=%s  --no-capture=%s  mouse_mode=%d（%s）" % [
		str(DisplayServer.window_is_focused()), str(flag), mode,
		names.get(mode, "?")])
	if flag:
		print("[mouse] 期望 VISIBLE（探针不该抢鼠标）：%s"
			% ("✔ 通过" if mode == Input.MOUSE_MODE_VISIBLE else "✘ 仍被捕获"))
	else:
		print("[mouse] 不带参数时由焦点决定：focused → CAPTURED，未获焦 → VISIBLE")
	# 立刻放开，免得探针自己把用户的鼠标扣住
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	quit(0)

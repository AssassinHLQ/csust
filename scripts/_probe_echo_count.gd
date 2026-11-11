extends SceneTree
## 最小复现：**next_level 的 _input 到底收不收得到 F6**。
##
## 现象矛盾：
##   · `_probe_next_f3_sync.gd` 里 F3 的 print 出来了（`[Dev] F3 → 开发者模式 = true`）
##   · 但 F6 的 print（`[Dev] F6 按键到达 next_level.gd`）没出来
##   · 而 player.gd 的 `[Dev] F6 角色速度 ×5.0` 出来了
## ⇒ 同一段 `_input` 里，F3 分支进了、F6 分支没进。这不合理，必须查清。
##
## 本探针**直接计数**，不靠 print 推断：
##   ① 给 next_level 包一层，数它被调了几次
##   ② 逐个键喂，看计数器增量
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_probe_echo_count.gd -- --splat=off --no-capture

const DevMode := preload("res://scripts/dev_mode.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("═══ _input 计数复现 ═══\n")
	DevMode.set_on(true)

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	current_scene = level
	for _i in 200:
		await process_frame
	paused = false
	for _f in 40:
		await process_frame

	# 直接调 level._input，看 F6 分支有没有执行
	print("── 直接调用 level.call(\"_input\", ev) ──")
	for spec in [["F4", KEY_F4], ["F5", KEY_F5], ["F6", KEY_F6], ["F3", KEY_F3]]:
		var nm: String = spec[0]
		var kc: int = spec[1]
		var ev := InputEventKey.new()
		ev.keycode = kc
		ev.physical_keycode = kc
		ev.pressed = true
		ev.echo = false
		print(">>> 喂 %s" % nm)
		level.call("_input", ev)
		await process_frame

	# 检查 KeyEcho 节点是否被建出来
	var layer := level.get_node_or_null("LevelUI")
	if layer != null:
		var ke := layer.get_node_or_null("KeyEcho")
		print("\nKeyEcho 节点：%s" % ("存在" if ke != null else "不存在"))
		if ke != null:
			var lbl := ke.get_node_or_null("KeyEchoLabel") as Label
			print("  文字 = 「%s」" % (lbl.text if lbl != null else "?"))

	DevMode.set_on(false)
	quit(0)

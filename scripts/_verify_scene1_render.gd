extends SceneTree
## 场景 1（game.tscn）在把画面逻辑搬去 `RenderEnv` 之后有没有被弄坏。
##
## 为什么单独写一个：`_verify_settings.gd` 会渲图 + 等模型的动画驱动，跑一轮要好几分钟；
## 这个只验「重构有没有把主场景的画面链路打断」，30 秒内出结果。
##
## 用法：_tools/run_probe.sh res://scripts/_verify_scene1_render.gd -- --splat=off

const GameScene := "res://scenes/game.tscn"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load(GameScene) as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 40:
		await process_frame

	var vp := game.get_viewport()
	print("── ① 薄壳还在（有别的探针直接 `game.call(\"_apply_render\")`）──")
	for m in ["_apply_render", "_fit_render_scale", "_on_setting_changed"]:
		_check(game.has_method(m), "game.gd 有 %s()" % m)

	print("── ② 自动上限还存着 ──")
	var auto_scale := float(game.get("_auto_scale"))
	print("     _auto_scale = %.3f" % auto_scale)
	_check(auto_scale > 0.0 and auto_scale <= 1.0, "_auto_scale 在 (0, 1] 里")

	print("── ③ 设置一改，主场景真的动（走 listen，不手动调）──")
	GameSettings.set_value("resolution_scale", 0.6)
	await process_frame
	await process_frame
	print("     scaling_3d_scale = %.3f（期望 %.3f）" % [vp.scaling_3d_scale, auto_scale * 0.6])
	_check(absf(vp.scaling_3d_scale - auto_scale * 0.6) < 0.01, "3D 缩放生效")

	GameSettings.set_value("render_distance", 400.0)
	await process_frame
	var cams := game.find_children("*", "Camera3D", true, false)
	var fars: Array = []
	for c in cams:
		fars.append((c as Camera3D).far)
	print("     摄像机 far = %s（期望全 400）" % str(fars))
	_check(not cams.is_empty() and fars.all(func(f): return is_equal_approx(float(f), 400.0)),
		"渲染距离 → Camera3D.far 生效")

	print("── ④ RenderDistance 节点还认得出（代码里 new 出来的那个）──")
	var rd := game.get_node_or_null("RenderDistance")
	_check(rd != null, "场上找得到 RenderDistance 节点（%s）"
		% ("有" if rd != null else "没有"))

	GameSettings.reset_all()
	await process_frame
	print("── 收尾：reset_all()，scaling=%.3f" % vp.scaling_3d_scale)

	print("")
	print("结果：%s（失败 %d 项）" % ["PASS" if _fail == 0 else "FAIL", _fail])
	quit(0 if _fail == 0 else 1)

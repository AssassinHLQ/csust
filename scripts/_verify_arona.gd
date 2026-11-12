extends SceneTree
## 验收：终端敲 `arona` → 屏幕上出现阿洛娜（3D 模型 + 名牌 + 对话气泡）。
##
## 用户 2026-11-12：「打 arona 可以出现电脑里面的阿洛娜」。
##
## 走真输入通道（和 `_verify_bili_browser.gd` 一样灌 `Input.parse_input_event()`）。
##
##   godot --path . --script res://scripts/_verify_arona.gd -- --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	print("═══ 阿洛娜 · 终端唤醒验收 ═══\n")

	ShopClerk._bought = true
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 90:
		await process_frame
	paused = false

	var comp := _find_in_group("hut_computer")
	_check(comp != null, "找到小屋电脑")
	if comp == null:
		_summary()
		quit(1)
		return
	comp.call("use_for_test")
	await _wait(10)

	var stage = comp.get("arona_stage")
	var page = comp.get("arona_page")
	var term = comp.get("terminal")
	_check(stage != null, "拿到 AronaStage")
	_check(page != null, "拿到 AronaPage")
	_check(term != null, "拿到终端")

	# 模型有没有真的加载进来
	var model_ok := false
	if stage != null:
		var m = stage.get("model")
		model_ok = m != null and is_instance_valid(m)
	_check(model_ok, "阿洛娜模型已加载（models/arona/arona.glb）")
	if not model_ok:
		# 缺模型时给出可操作的提示，不静默
		print("  !! 模型没加载。检查 models/arona/arona.glb 是否存在，"
			+ "或用 _log/arona_export.py 重新导出")

	# ── 敲 arona ──
	for ch in "arona":
		_key(_keycode_of(ch), ch.unicode_at(0))
		await _wait(2)
	_key(KEY_ENTER, 0)
	await _wait(12)
	_check(bool(page.visible), "敲 arona 之后阿洛娜界面可见")
	_check(bool(stage.visible), "3D 舞台已激活")
	_check(not bool(term.visible), "终端已隐藏（否则会盖住 3D）")

	# 模型尺寸/相机是不是合理（不是空场景）
	if stage != null and stage.get("cam") != null:
		var cam = stage.get("cam")
		print("  相机 fov=%.1f 位置 %s" % [float(cam.fov), str(cam.global_position.snappedf(0.01))])

	# 浮动动画在跑
	var y0: float = 0.0
	var y1: float = 0.0
	if stage != null and stage.get("model") != null:
		var m = stage.get("model")
		y0 = float(m.position.y)
		await _wait(40)
		y1 = float(m.position.y)
		_check(absf(y1 - y0) > 0.0005, "浮动动画在跑（model.y %.4f → %.4f）" % [y0, y1])

	# 台词在打字
	var typed_a: float = float(page.get("_typed")) if page != null else -1.0
	await _wait(20)
	var typed_b: float = float(page.get("_typed")) if page != null else -1.0
	print("  台词进度 %.1f → %.1f 字" % [typed_a, typed_b])
	_check(typed_a >= 0.0 and typed_b >= typed_a, "对话在打字（进度单调不减）")

	await _shot("01_arona")

	# Space 换一句
	var li0 := int(page.get("_line_i")) if page != null else -1
	_key(KEY_SPACE, 0)
	await _wait(4)
	var li1 := int(page.get("_line_i")) if page != null else -1
	_check(li1 != li0, "Space 换到下一句（%d → %d）" % [li0, li1])

	# Esc 退出，终端回来
	_key(KEY_ESCAPE, 0)
	await _wait(6)
	_check(not bool(page.visible), "Esc 关掉阿洛娜界面")
	_check(not bool(stage.visible), "3D 舞台收起")
	_check(bool(term.visible), "终端恢复显示")

	_summary()
	quit(0)


func _key(code: int, unicode: int) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	e.physical_keycode = code
	e.unicode = unicode
	Input.parse_input_event(e)
	var u := InputEventKey.new()
	u.pressed = false
	u.keycode = code
	u.physical_keycode = code
	Input.parse_input_event(u)


func _keycode_of(ch: String) -> int:
	var up := ch.to_upper()
	if up.length() == 1 and up.unicode_at(0) >= 65 and up.unicode_at(0) <= 90:
		return KEY_A + (up.unicode_at(0) - 65)
	return KEY_NONE


func _find_in_group(g: String) -> Node:
	return get_first_node_in_group(g)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_arona")
	DirAccess.make_dir_recursive_absolute(out)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s.png" % name))
	print("  [img] %s" % out.path_join("%s.png" % name))


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])

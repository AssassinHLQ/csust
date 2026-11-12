extends SceneTree
## 验收：终端敲 `bilibili` → 打开假 B 站；方向键选、Enter 进播放页（有进度条 + 弹幕）。
##
## 用户 2026-11-12：「终端敲 bilibili → 打开游戏内的 B 站风格窗口：顶栏/搜索框/
## 视频封面网格/能点开一个「播放页」，有进度条、弹幕飘过」。
##
## 走的是真输入通道：`hut_computer._input()` 收键 → 转给终端 / 转给 B 站，
## 所以这里直接 `Input.parse_input_event()` 灌真键盘事件，不调内部函数作弊。
##
##   godot --path . --script res://scripts/_verify_bili_browser.gd -- --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	print("═══ 假 B 站 · 终端打开验收 ═══\n")

	ShopClerk._bought = true
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 90:
		await process_frame
	paused = false

	# ⚠️ 电脑不是固定节点名 —— 它由 `game.gd` 挂到 `MeshHut` 下并
	#    `add_to_group("hut_computer")`（见 `game.gd:1234`），所以按组找。
	var comp := _find_in_group("hut_computer")
	_check(comp != null, "场景里有 hut_computer（小屋电脑）")
	if comp == null:
		_summary()
		quit(1)
		return
	comp.call("use_for_test")
	await _wait(10)

	var term = comp.get("terminal")
	var bili = comp.get("bili")
	_check(term != null, "拿到终端")
	_check(bili != null, "拿到 BiliBrowser 节点")

	# ── ① 敲 bilibili ──
	for ch in "bilibili":
		_key(_keycode_of(ch), ch.unicode_at(0))
		await _wait(2)
	_key(KEY_ENTER, 0)
	await _wait(8)
	_check(bool(bili.visible), "敲 bilibili 之后 B 站窗口可见")
	_check(String(bili.call("page_name")) == "space", "打开的是 UP 主空间页")
	await _shot("01_space")

	# ── ② 方向键换选中 ──
	_key(KEY_RIGHT, 0)
	await _wait(2)
	_key(KEY_DOWN, 0)
	await _wait(4)
	_check(int(bili.get("_sel")) == 4, "方向键把选中移到第 5 个（_sel=%d）"
		% int(bili.get("_sel")))

	# ── ③ Enter 进播放页，等弹幕飘出来 ──
	_key(KEY_ENTER, 0)
	await _wait(6)
	_check(String(bili.call("page_name")) == "player", "Enter 进入播放页")
	await _wait(90)                    # 1.5 秒，攒几条弹幕
	var dm: Array = bili.get("_danmaku")
	_check(dm.size() >= 2, "弹幕已经飘起来了（%d 条）" % dm.size())
	var t0: float = float(bili.get("_t"))
	await _wait(30)
	var t1: float = float(bili.get("_t"))
	_check(t1 > t0, "进度条在走（%.2f s → %.2f s）" % [t0, t1])
	await _shot("02_player")

	# ── ④ Space 暂停 ──
	_key(KEY_SPACE, 0)
	await _wait(4)
	_check(not bool(bili.get("_playing")), "Space 暂停")
	var tp0: float = float(bili.get("_t"))
	await _wait(30)
	_check(absf(float(bili.get("_t")) - tp0) < 0.001, "暂停后进度不再增长")

	# ── ⑤ Esc 退回列表，再 Esc 退回终端 ──
	_key(KEY_ESCAPE, 0)
	await _wait(4)
	_check(String(bili.call("page_name")) == "space", "Esc 从播放页退回列表")
	_key(KEY_ESCAPE, 0)
	await _wait(4)
	_check(not bool(bili.visible), "再按 Esc 关掉 B 站、回到终端")

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
	if ch >= "0" and ch <= "9":
		return KEY_0 + ch.to_int()
	return KEY_NONE


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


## ⚠️ 不能把这个 helper 命名成 `get_first_node_in_group` —— 那是 `SceneTree` 的
## 内置方法（本脚本 `extends SceneTree`），同名会覆盖掉、然后在里面又调自己 → 无限递归。
func _find_in_group(g: String) -> Node:
	return get_first_node_in_group(g)


func _shot(name: String) -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_bili")
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

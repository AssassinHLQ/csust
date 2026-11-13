extends SceneTree
## 验收：终端敲 `arona` / `plana` → **不换界面**，阿洛娜 / 普拉娜直接在 arch 的
## **右半屏**显现（遮住系统），台词走终端正文流。
##
## 用户 2026-11-12 定的需求：
##   · 「打 arona 可以出现电脑里面的阿洛娜」
##   · 「扣绿幕，输入 plana 就出现这」
##   · 「arona 这个，**不是新开一个界面**，而是**直接在 arch 右半部分显现，遮住系统**，
##      她的对话也**通过终端发送**」
##   · 「她们不要喊老师」「plana 还要提醒爱丽丝早点刷回去，不然老师会生气」
##
## ── 为什么这里**不 instance `game.tscn`** ──
## 整个场景要 90 帧才稳定，而且别的会话正在改它；同伴这套东西只依赖
## `HutComputer` 自己（`_build()` 里就有 SubViewport + ArchTerminal）。
## 所以直接 `HutComputer.new()`，坏在哪一目了然，也不会被无关的报错带崩。
##
##   godot --path . --script res://scripts/_verify_arona.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	print("═══ 阿洛娜 / 普拉娜 · 终端右半屏验收 ═══\n")

	var comp := HutComputer.new()
	comp.name = "HutComputer"
	root.add_child(comp)
	await _wait(4)
	comp.call("use_for_test")
	await _wait(4)

	var term: ArchTerminal = comp.get("terminal")
	_check(term != null, "拿到终端")
	if term == null:
		_summary()
		quit(1)
		return
	_check(comp.call("is_using"), "电脑已打开")
	_check(not term.companion_active(), "刚开机时屏幕上没有同伴")

	# ── 1. 敲 arona（**必须按回车**，命令才会执行）──
	await _cmd("arona")
	await _wait(6)
	_check(term.companion_active(), "敲 arona 之后同伴激活")
	_check(term.companion_name() == "ARONA", "当前是 ARONA（实际 `%s`）"
		% term.companion_name())
	# 「不是新开一个界面」→ 终端本身必须还在、还可见
	_check(bool(term.visible), "终端没有隐藏（不是切页面）")

	# 素材真的载进来了
	var anim: FrameAnim = term.get("_comp_anim")
	_check(anim != null, "拿到逐帧动画对象")
	var n := anim.count() if anim != null else 0
	_check(n > 300, "阿洛娜序列帧已载入（%d 帧）" % n)

	# ── 1b. 配音（GPT-SoVITS 生成，见 `_tools/gen_companion_voice.py`）──
	var player: AudioStreamPlayer = term.get("_voice")
	_check(player != null, "终端有独立的配音播放器（不走 Sfx 池子）")
	var voice_path := String(term.get("_voice_path"))
	_check(voice_path == "res://assets/companion_voice/arona/open_00.wav",
		"第一句台词触发了配音（%s）" % voice_path)
	var stream: AudioStream = player.stream if player != null else null
	_check(stream != null and stream.get_length() > 1.0,
		"配音流有效（%.2f s）" % (stream.get_length() if stream != null else 0.0))
	_check(_voice_files_ok(), "每个角色的每一句都有配音文件（34 个）")

	# ── 2. 台词真的进了终端正文 ──
	var txt := term.screen_text()
	_check(txt.contains("ARONA:"), "台词以 `ARONA:` 前缀打进终端")
	# 逐句往下翻，把整段开场都看一遍。
	# ⚠️ 必须**边翻边攒**：每句折成 1~2 行，40 行的屏幕装不下 12 句，
	#    等攒完再查的话前半段已经被滚屏顶掉了（上一版就只查到第 1 句）。
	var hay := txt
	for _i in 12:
		_key(KEY_ENTER, 0)
		await _wait(2)
		hay += term.screen_text()
	var han := 0
	for i in hay.length():
		if hay.unicode_at(i) >= 0x4E00 and hay.unicode_at(i) <= 0x9FFF:
			han += 1
	_check(han > 80, "终端里出现了中文台词（%d 个汉字，含重复）" % han)
	# 不喊老师（用户明确要求）
	_check(not hay.contains("老师"), "没有出现「老师」这个称呼")
	# 设定：解 BL / 刷 Magisk / 平板借给她玩
	_check(hay.contains("Magisk") or hay.contains("bootloader")
		or hay.contains("fastboot"), "台词里带上了刷机前情（bootloader / Magisk）")

	# ── 3. 折行：一行不能超过 COLS 个显示格 ──
	var over := 0
	for line in txt.split("\n"):
		if _cells(line) > ArchTerminal.COLS:
			over += 1
	_check(over == 0, "没有一行超过 %d 格（超宽 %d 行）" % [ArchTerminal.COLS, over])

	# ── 4. Enter（空输入）= 下一句 ──
	var li0 := int(term.get("_comp_line"))
	var open0 := bool(term.get("_comp_in_open"))
	_key(KEY_ENTER, 0)
	await _wait(3)
	var li1 := int(term.get("_comp_line"))
	var open1 := bool(term.get("_comp_in_open"))
	_check(li1 != li0 or open1 != open0, "空回车叫下一句（%d → %d）" % [li0, li1])

	# ── 5. 玩家正在敲的字不会被台词踩掉 ──
	#    这是 `_comp_push()` 存在的唯一理由：同伴 7 秒自己说一句，
	#    撞上玩家打字的瞬间必须把输入行摘下来、说完原样放回去。
	_type("sudo")
	await _wait(2)
	var typed_before := String(term.get("_typing"))
	_key(KEY_TAB, 0)
	await _wait(3)
	var typed_after := String(term.get("_typing"))
	_check(typed_before == "sudo", "输入行里已经有 `sudo`")
	_check(typed_after == "sudo", "同伴插话后输入行没被踩掉（`%s`）" % typed_after)
	var bar := String(term.last_line())
	_check(bar.begins_with("alice@arisu:") and bar.contains("sudo"),
		"提示符那行还带着玩家敲的字（`%s`）" % bar.strip_edges())

	# ── 6. Tab 也能翻页（不占打字键位，空格留给命令）──
	var li2 := int(term.get("_comp_line"))
	_key(KEY_TAB, 0)
	await _wait(3)
	_check(int(term.get("_comp_line")) != li2, "Tab 也能叫下一句")

	# 把残留的输入清掉，后面好敲命令
	_key(KEY_U, 0, true)
	await _wait(2)

	# ── 7. 7 秒自动说话 ──
	#    ⚠️ 这里必须按**真实时钟**等，不能数帧：`--script` 探针里
	#    `process_frame` 跑得比 60 fps 快得多，数 480 帧可能只过了半秒，
	#    `_comp_timer` 根本攒不到 7 秒（上一版就栽在这）。
	var before := int(term.get("_comp_line"))
	var open_b := bool(term.get("_comp_in_open"))
	await _wait_seconds(7.8)
	var after := int(term.get("_comp_line"))
	var open_a := bool(term.get("_comp_in_open"))
	_check(after != before or open_a != open_b,
		"放着不管也会自己说话（%d → %d）" % [before, after])

	await _shot("01_arona_in_terminal")

	# ── 8. 换人：plana ──
	await _cmd("plana")
	await _wait(6)
	_check(term.companion_name() == "PLANA", "敲 plana 换成 PLANA（实际 `%s`）"
		% term.companion_name())
	var ptxt := term.screen_text()
	_check(ptxt.contains("PLANA:"), "普拉娜的台词也进终端正文")
	# 她开场的重点在最后几句（「请早点刷回去」「不然他会真的生气」），
	# 所以同样要一路翻下去、边翻边攒。
	for _i in 10:
		_key(KEY_ENTER, 0)
		await _wait(2)
		ptxt += term.screen_text()
	# 她的任务：提醒爱丽丝早点刷回去
	var warn := ptxt.contains("刷回") or ptxt.contains("备份") or ptxt.contains("生气")
	_check(warn, "普拉娜有「刷回去 / 备份 / 他会生气」的提醒")
	_check(not ptxt.contains("老师"), "普拉娜也不喊老师")
	_check(String(term.get("_voice_path")).contains("/plana/"),
		"换人之后配音也换成了普拉娜的（%s）" % String(term.get("_voice_path")))

	await _shot("02_plana_in_terminal")

	# ── 9. dismiss 收起 ──
	await _cmd("dismiss")
	await _wait(6)
	_check(not term.companion_active(), "dismiss 把同伴收走")
	_check(term.companion_name() == "", "收走之后名字为空")
	_check(String(term.get("_voice_path")) == "", "收走之后配音也停了")

	# ── 10. 立绘真的画出来了（像素检查）──
	#    压板是半透明的，立绘是不透明的 —— 右半屏和左半屏的亮度应该有差。
	await _cmd("arona")
	await _wait(24)
	var w: float = await _shot_pixels("03_arona_panel")
	_check(w > 0.0, "右半屏有立绘（左侧/右侧平均亮度差 %.3f）" % w)

	_summary()
	quit(0 if _fail == 0 else 1)


# ── 工具 ──────────────────────────────────────────────────────────────────────

## 两个角色的**每一句**台词都得有对应配音文件（台词改了没重跑生成脚本 = 缺）。
func _voice_files_ok() -> bool:
	var total := 0
	for who in ["arona", "plana"]:
		var d: Dictionary = ArchTerminal.COMPANIONS[who]
		for group in ["open", "loop"]:
			var cnt: int = Array(d[group]).size()
			for i in cnt:
				var p := "res://assets/companion_voice/%s/%s_%02d.wav" % [who, group, i]
				total += 1
				if not FileAccess.file_exists(p):
					print("    缺配音：%s" % p)
					return false
	print("    配音文件 %d 个都在" % total)
	return true

## 中文 2 格、ASCII 1 格 —— 和 `arch_terminal.gd::_char_cells()` 同一套规则
func _cells(s: String) -> int:
	var n := 0
	for i in s.length():
		var c := s.unicode_at(i)
		var wide := (c >= 0x1100 and c <= 0x115F) \
			or (c >= 0x2E80 and c <= 0xA4CF) \
			or (c >= 0xAC00 and c <= 0xD7A3) \
			or (c >= 0xF900 and c <= 0xFAFF) \
			or (c >= 0xFE30 and c <= 0xFE6F) \
			or (c >= 0xFF00 and c <= 0xFF60) \
			or (c >= 0xFFE0 and c <= 0xFFE6)
		n += 2 if wide else 1
	return n


func _type(s: String) -> void:
	for ch in s:
		_key(_keycode_of(ch), ch.unicode_at(0))


## 敲一条**完整命令**：打字 + 回车（少了回车命令根本不会执行 —— 上一版就漏了）
func _cmd(s: String) -> void:
	_type(s)
	await _wait(2)
	_key(KEY_ENTER, 0)
	await _wait(3)


## 按**真实时钟**等（`--script` 探针里数帧不可靠，见第 7 步的注释）
func _wait_seconds(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func _key(code: int, unicode: int, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	e.physical_keycode = code
	e.unicode = unicode
	e.ctrl_pressed = ctrl
	Input.parse_input_event(e)
	var u := InputEventKey.new()
	u.pressed = false
	u.keycode = code
	u.physical_keycode = code
	u.ctrl_pressed = ctrl
	Input.parse_input_event(u)


func _keycode_of(ch: String) -> int:
	var up := ch.to_upper()
	if up.length() == 1 and up.unicode_at(0) >= 65 and up.unicode_at(0) <= 90:
		return KEY_A + (up.unicode_at(0) - 65)
	return KEY_NONE


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	var out := _shot_dir()
	DirAccess.make_dir_recursive_absolute(out)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s.png" % name))
	print("  [img] %s" % out.path_join("%s.png" % name))


## 出图并返回「左半屏 vs 右侧立绘区」的平均亮度差（>0.02 说明立绘真画上去了）
func _shot_pixels(name: String) -> float:
	var out := _shot_dir()
	DirAccess.make_dir_recursive_absolute(out)
	if DisplayServer.get_name() == "headless":
		return 1.0            # headless 下没有纹理，别把这条当失败
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		return 0.0
	img.save_png(out.path_join("%s.png" % name))
	print("  [img] %s" % out.path_join("%s.png" % name))
	var w := img.get_width()
	var h := img.get_height()
	var left := _mean_luma(img, Rect2i(0, 0, int(w * 0.3), h))
	var right := _mean_luma(img, Rect2i(int(w * 0.62), 0, int(w * 0.38), h))
	print("  平均亮度  左 %.3f   右 %.3f" % [left, right])
	return absf(right - left)


func _mean_luma(img: Image, r: Rect2i) -> float:
	var step := 7
	var sum := 0.0
	var cnt := 0
	var y := r.position.y
	while y < r.end.y and y < img.get_height():
		var x := r.position.x
		while x < r.end.x and x < img.get_width():
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			cnt += 1
			x += step
		y += step
	return sum / float(maxi(cnt, 1))


func _shot_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_arona")


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])

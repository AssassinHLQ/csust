extends SceneTree
## 验「音效系统」（`scripts/sfx.gd` + `assets/sfx/`）：
##   1. 素材与库表：每个候选文件都在、都能加载成 AudioStream、时长正常
##   2. **调用点 ↔ 库表双向对账**：脚本里写的逻辑名都在表里，表里的名字也都有人用
##   3. 播放机制：真能响、多声不互相切、gap 节流、未知名字不崩、3D 定位、停止
##   4. 和设置系统的接线：播放器走 Master 总线、主音量拉 0 真的静音、暂停时照样响
##
## 用法：
##   godot --path <工程> --script res://scripts/_verify_sfx.gd
##
## ⚠️ 要真渲染、不要 `--headless`：headless 的音频驱动是空的，
##    「真的在播」这类断言测不出东西（渲染侧也一样，见 §1.11）。
## ⚠️ 第 4 节会临时把主音量设成 0 再改回来（它会落盘到 `user://settings.cfg`），
##    所以**必须先读原值、结束前恢复**，否则会悄悄改掉用户的音量。

const SFX_DIR := "res://assets/sfx/"
const SCRIPTS_DIR := "res://scripts/"
## 时长的合理区间（秒）：比这短多半是空文件，比这长多半拿错了素材。
## ⚠️ 下限取 5 ms：Kenney 的 `click_002.ogg` 只有 10 ms（就是个「嗒」），
##    本喵第一版写 20 ms，把它判成了坏文件。
const MIN_LEN := 0.005
const MAX_LEN := 1.5

var _fail := 0
var _pass := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _wait(5)
	_test_assets()
	_test_call_sites()
	await _test_playback()
	_test_settings_wiring()
	await _test_in_game()
	await _wait(2)

	print("\n================ 结果 ================")
	print("通过 %d 项" % _pass)
	_quit()


# --- 1. 素材与库表 -----------------------------------------------------------

func _test_assets() -> void:
	print("========== 1. 素材与库表 ==========")
	_check(DirAccess.dir_exists_absolute(SFX_DIR), "音效目录在 %s" % SFX_DIR)
	_check(Sfx.names().size() >= 9, "库表里 %d 个逻辑名：%s" % [Sfx.names().size(), str(Sfx.names())])

	var missing: Array[String] = []
	var short: Array[String] = []
	var total := 0
	var total_len := 0.0
	for name in Sfx.names():
		var list := Sfx.files(String(name))
		_check(not list.is_empty(), "「%s」有候选文件（%d 条）" % [name, list.size()])
		for path in list:
			total += 1
			if not ResourceLoader.exists(path):
				missing.append(path)
				continue
			var st := load(path) as AudioStream
			if st == null:
				missing.append(path + "（加载成 null）")
				continue
			var ln := st.get_length()
			total_len += ln
			if ln < MIN_LEN or ln > MAX_LEN:
				short.append("%s = %.3f s" % [path.get_file(), ln])
	# 归成一条：逐条打会刷 13 行
	_check(missing.is_empty(), "%d 个候选文件全部存在且能加载%s"
		% [total, "" if missing.is_empty() else "（坏的是：%s）" % str(missing)])
	_check(short.is_empty(), "时长都在 %.2f ~ %.1f s 之间%s"
		% [MIN_LEN, MAX_LEN, "" if short.is_empty() else "（异常的：%s）" % str(short)])
	_check(Sfx.missing_files().is_empty(), "运行期没有「加载失败」记录%s"
		% ("" if Sfx.missing_files().is_empty() else "（%s）" % str(Sfx.missing_files())))
	print("  ── 共 %d 个文件、合计 %.1f s ──" % [total, total_len])

	_check(not Sfx.has("不存在的音效"), "查一个不存在的名字：has() 返回 false")


# --- 2. 调用点 ↔ 库表 双向对账 ------------------------------------------------

## 这一节是整套自检里最值钱的：**声音加了没接、或者接的名字打错了**，
## 两种错都不会报错、也不会有声音，自己几乎发现不了。
## 做法和剧情那轮的「角色表」一个思路（见 §9.8）：拿源码当数据来对账。
func _test_call_sites() -> void:
	print("\n========== 2. 调用点 ↔ 库表 对账 ==========")
	var re := RegEx.new()
	# ⚠️ 只认 `Sfx.play("名字")` / `Sfx.play_at("名字", ...)` 里的**字面量**：
	#    带变量的调用（`Sfx.play(some_var)`）对不了账，也**不该**出现 —— 逻辑名是固定的。
	re.compile("Sfx\\.play(?:_at)?\\(\\s*\"([A-Za-z0-9_]+)\"")

	var used := {}
	var scanned := 0
	var files := _script_files()
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		scanned += 1
		for m in re.search_all(text):
			used[String(m.get_string(1))] = f.get_file()
	print("  扫了 %d 个产品脚本，找到 %d 个不同的逻辑名" % [scanned, used.size()])

	var unknown: Array[String] = []
	for n in used.keys():
		if not Sfx.has(String(n)):
			unknown.append("「%s」（%s）" % [n, used[n]])
	_check(unknown.is_empty(), "脚本里写的每个逻辑名都在库表里%s"
		% ("" if unknown.is_empty() else "（表里没有：%s）" % str(unknown)))

	var dead: Array[String] = []
	for n in Sfx.names():
		if not used.has(String(n)):
			dead.append(String(n))
	_check(dead.is_empty(), "库表里每个逻辑名都有调用点%s"
		% ("" if dead.is_empty() else "（没人用的：%s）" % str(dead)))

	_check(used.size() == Sfx.names().size(),
		"两边数量一致（调用点 %d 个、库表 %d 个）" % [used.size(), Sfx.names().size()])


# --- 3. 播放机制 --------------------------------------------------------------

func _test_playback() -> void:
	print("\n========== 3. 播放机制 ==========")
	# 这两条断言守的是**本工程踩过最阴的一个坑**，现场留在这里：
	#   `Script` / `GDScript` 自带一个原生方法叫 `reset_state`，而 `class_name`
	#   脚本的类名（`Sfx`）本身就是那个脚本对象 —— 于是 `Sfx.reset_state()`
	#   会解析到**原生方法**上：自己写的静态函数**一行都不执行、也不报错**。
	#   本喵当时连函数体第一行的 print 都看不到，白查了三轮才用 ClassDB 问出来。
	#   （所以库里的测试钩子叫 `reset_for_test()`；改成 `reset_state` 会静默失效。）
	_check(ClassDB.class_has_method("Script", "reset_state"),
		"记录在案：Script 有原生方法 reset_state（ClassDB 实测）→ 静态函数别用这个名字")
	_check(not ClassDB.class_has_method("Object", "reset_state"),
		"……但 Object 本身没有：是 Script / GDScript 这一层才有的")

	Sfx.stop_all()
	Sfx.reset_for_test()

	_check(Sfx.play("fire"), "play(\"fire\") 返回 true")
	_check(Sfx.active_count() >= 1, "确实有播放器在响（%d 个）" % Sfx.active_count())
	_check(not Sfx.play("完全不存在"), "未知名字：返回 false、不崩")

	var host := root.get_node_or_null("SfxHost")
	_check(host != null, "宿主节点 SfxHost 挂在 root 下（懒创建，不用 autoload）")
	if host != null:
		# ⚠️ 世界暂停时（设置菜单开着）UI 音效照样要响
		_check(host.process_mode == Node.PROCESS_MODE_ALWAYS,
			"宿主 process_mode = ALWAYS（暂停时也处理）")
		var buses := {}
		var players := 0
		for c in host.get_children():
			var b := ""
			if c is AudioStreamPlayer:
				b = String((c as AudioStreamPlayer).bus)
			elif c is AudioStreamPlayer3D:
				b = String((c as AudioStreamPlayer3D).bus)
			else:
				continue
			players += 1
			buses[b] = true
		# ⚠️ 键要转成 String 再比：`AudioStreamPlayer.bus` 是 **StringName**，
		#    `[&"Master"] == ["Master"]` 是 **false**（数组比较不放过类型差异），
		#    本喵第一版就栽在这儿。
		_check(players > 0 and buses.keys() == ["Master"],
			"%d 个播放器都走 Master 总线（设置里的主音量才管得到）%s" % [players, str(buses.keys())])

	# 多声不互相切：这是播放池存在的唯一理由
	Sfx.reset_for_test()
	Sfx.stop_all()
	Sfx.play("ui_open")
	Sfx.play("ui_close")
	_check(Sfx.active_count() >= 2, "两条不同的音效能同时在响（%d 个）" % Sfx.active_count())

	# gap 节流：同一个名字连着播，第二次要被吃掉
	Sfx.reset_for_test()
	Sfx.stop_all()
	var first := Sfx.play("ui_press")
	var second := Sfx.play("ui_press")
	_check(first and not second, "同一个名字连播两次：第二次被 gap 节流吃掉（%s / %s）"
		% [str(first), str(second)])
	Sfx.reset_for_test()
	var what_reset_said := Sfx.last_reason()
	# ⚠️ 必须**分开取**：把 `Sfx.play(...)` 和 `Sfx.last_reason()` 塞进同一个
	#    表达式里，读到的可能是**上一次**调用留下的 reason（实参求值顺序不能想当然），
	#    本喵第一版就是这样被一条假线索带偏的。
	var third := Sfx.play("ui_press")
	var why := Sfx.last_reason()
	var miss := Sfx.missing_files()
	_check(third, "reset_state() 之后又能播（节流不是永久的）｜ reset 说：%s ｜ play 说：%s ｜ miss=%s"
		% [what_reset_said, why, str(miss)])

	# 3D 定位
	Sfx.reset_for_test()
	Sfx.stop_all()
	var at := Vector3(3.0, 1.5, -5.0)
	_check(Sfx.play_at("ui_open", at), "play_at() 返回 true")
	var found := _playing_3d()
	_check(found != null and found.global_position.distance_to(at) < 0.01,
		"3D 播放器被摆到了指定位置（%s）"
		% (str(found.global_position.snappedf(0.01)) if found != null else "没找到 3D 播放器"))

	# 「真的在走时钟」：播放位置随真实时间前进。
	#
	# ⚠️ **必须按真实毫秒等，不能等帧数**（README §1.15 那条纪律）。
	#    这里原来写的是 `await _wait(20)`：60 fps 下 20 帧 = 0.33 s，而 `ui_open`
	#    这条 Kenney 音效只有 **0.25 s 左右** —— 它**播完了**，`playing` 变 false，
	#    于是这条断言时红时绿（2026-10 的全量回归里红过一次，而当时把
	#    game.tscn 换成带跑酷场景的那一版，谁看都像是新场景搞的鬼）。
	#    现在改成：**挑库表里最长的一条**，按它长度的 1/4 等真实毫秒。
	Sfx.reset_for_test()
	Sfx.stop_all()
	var clip := _longest_clip()
	var wait_ms := int(clampf(float(clip.get("len", 0.25)) * 0.25, 0.03, 0.4) * 1000.0)
	Sfx.play(String(clip.get("name", "ui_open")))
	await _wait_ms(wait_ms)
	var p := _playing_2d()
	var pos := p.get_playback_position() if p != null else -1.0
	_check(p != null and p.playing and pos > 0.005,
		"等了 %d ms（真实时间）之后还在播、时钟在走：位置 %.3f s / 总长 %.3f s"
		% [wait_ms, pos, float(clip.get("len", 0.0))])

	Sfx.stop_all()
	_check(Sfx.active_count() == 0, "stop_all() 之后一个都不响了")

	# 暂停时照样播（UI 音效的命根子）
	paused = true
	Sfx.reset_for_test()
	var ok := Sfx.play("ui_open")
	await _wait(3)
	_check(ok and Sfx.active_count() >= 1,
		"**世界暂停时照样响**（设置菜单开着时 UI 音效全靠这条）")
	paused = false
	Sfx.stop_all()


# --- 4. 和设置系统的接线 ------------------------------------------------------

func _test_settings_wiring() -> void:
	print("\n========== 4. 和设置系统的接线 ==========")
	var bus := AudioServer.get_bus_index("Master")
	_check(bus >= 0, "有 Master 总线（index %d）" % bus)
	var old := float(GameSettings.value("master_volume"))
	GameSettings.set_value("master_volume", 0.0)
	_check(AudioServer.is_bus_mute(bus), "主音量拉到 0 → Master 总线真的静音了")
	GameSettings.set_value("master_volume", old)
	_check(not AudioServer.is_bus_mute(bus) or old <= 0.001,
		"恢复成 %.2f 之后不再静音（没有偷偷改掉用户的音量）" % old)


# --- 5. 真场景里的接线 --------------------------------------------------------

## 前面几节验的是「库」和「调用点的名字」；这一节验**接线真的通** ——
## 即「真的按下去会响」。用户要的是能听见，光名字对上不算数。
##
## ⚠️ 本套件因此要加 `--splat=off`（会 instantiate `game.tscn`，不开就是 277 万点）。
func _test_in_game() -> void:
	print("\n========== 5. 真场景里的接线 ==========")
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)

	# ① 设置菜单：开 / 关各响一声。**重点是「世界暂停时也响」** ——
	#    菜单一开就 `paused = true`，而 UI 音效正是在那时最需要响。
	var menu: CanvasLayer = game.get_node_or_null("SettingsMenu") as CanvasLayer
	_check(menu != null, "场景里有 SettingsMenu")
	if menu != null:
		Sfx.reset_for_test()
		Sfx.stop_all()
		menu.call("open")
		_check(paused and Sfx.active_count() >= 1,
			"菜单打开：世界已暂停（%s），`ui_open` 照样响了（%d 个在播）"
			% [str(paused), Sfx.active_count()])
		Sfx.reset_for_test()
		Sfx.stop_all()
		menu.call("close")
		await _wait(2)
		_check(not paused and Sfx.active_count() >= 1,
			"菜单关闭：恢复运行（%s），`ui_close` 响了（%d 个在播）"
			% [str(not paused), Sfx.active_count()])

	# ② 武器：开一枪 + 走一次换弹（拔弹匣 / 推弹匣各一声）
	var weapon: Node = game.get_node_or_null("Player/Weapon")
	_check(weapon != null, "场景里有 Player/Weapon")
	if weapon == null:
		return
	await _wait(5)
	Sfx.reset_for_test()
	Sfx.stop_all()
	var fired: bool = weapon.call("shoot")
	_check(fired and Sfx.active_count() >= 1,
		"开一枪：shoot() = %s，`fire` 响了（%d 个在播）" % [str(fired), Sfx.active_count()])

	# 把弹药清空再换弹 —— `try_reload()` 在满弹时会直接 return
	weapon.set("current_ammo", 0)
	Sfx.reset_for_test()
	Sfx.stop_all()
	weapon.call("try_reload")
	_check(bool(weapon.call("is_reloading")) and Sfx.active_count() >= 1,
		"换弹开始：`reload_out` 响了（%d 个在播）" % Sfx.active_count())

	# 等它换完（reload_time = 1.05 s，按**真实时间**等，不按帧数）
	Sfx.reset_for_test()
	Sfx.stop_all()
	var t0 := Time.get_ticks_msec()
	while bool(weapon.call("is_reloading")) and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	_check(not bool(weapon.call("is_reloading")) and Sfx.active_count() >= 1,
		"换弹完成：`reload_in` 响了（%d 个在播，等了 %d ms）"
		% [Sfx.active_count(), Time.get_ticks_msec() - t0])

	Sfx.stop_all()
	game.queue_free()
	await _wait(3)


# --- 工具 ---------------------------------------------------------------------

## 产品脚本清单：`res://scripts/*.gd`，排除自检/探针（`_` 开头）与音效库自己
func _script_files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(SCRIPTS_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() != "gd":
			continue
		if f.begins_with("_") or f == "sfx.gd":
			continue
		out.append(SCRIPTS_DIR + f)
	out.sort()
	return out


## 库表里**最长**的那条音效（`{name, len}`）。用途见上面「等真实毫秒」那段：
## 想量「还在播」就不能挑一条比等待时间还短的音效。
func _longest_clip() -> Dictionary:
	var best := {}
	for name in Sfx.names():
		for f in Sfx.files(String(name)):
			if not ResourceLoader.exists(f):
				continue
			var st := load(f) as AudioStream
			if st == null:
				continue
			if best.is_empty() or st.get_length() > float(best["len"]):
				best = {"name": String(name), "len": st.get_length()}
	return best


func _playing_2d() -> AudioStreamPlayer:
	var host := root.get_node_or_null("SfxHost")
	if host == null:
		return null
	for c in host.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing:
			return c as AudioStreamPlayer
	return null


func _playing_3d() -> AudioStreamPlayer3D:
	var host := root.get_node_or_null("SfxHost")
	if host == null:
		return null
	for c in host.get_children():
		if c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).playing:
			return c as AudioStreamPlayer3D
	return null


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if cond:
		_pass += 1
	else:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


## 等**真实毫秒**（真窗口能跑到 1000+ fps，「等 60 帧」可能只有 16 ms）
func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame

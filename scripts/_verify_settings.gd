extends SceneTree
## 验「Esc 设置界面」：
##   1. Esc 能开、能关；开着时游戏确实暂停、鼠标确实被释放
##   2. 每一格设置都**真的作用到了对应系统上**（不是只存了个值）
##   3. 落盘 + 读回（重启后还在）
##   4. 「恢复默认」把整张表铺回去，并且各系统跟着回默认
##   5. 渲图：菜单长什么样（这条是给人眼看的 —— 像素皮肤和字体糊不糊）
##
## 用法：godot --path <工程> --script res://scripts/_verify_settings.gd -- --splat=off

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)

	var menu := game.get_node_or_null("SettingsMenu")
	var player: Player = game.get_node("Player")

	print("========== 1. 结构 ==========")
	_check(menu != null, "场景里有 SettingsMenu")
	_check(GameSettings.DEFAULTS.size() >= 5,
		"设置表里 %d 项" % GameSettings.DEFAULTS.size())
	if menu == null:
		print("\n没有菜单，后面没法验")
		_quit()
		return
	_check(not bool(menu.get("is_open")), "初始是关着的")
	_check(not paused, "初始没有暂停")

	print("\n========== 2. Esc 开 / 关 ==========")
	await _press_escape()
	_check(bool(menu.get("is_open")), "按 Esc 打开了设置")
	_check(paused, "打开时游戏被暂停")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "打开时鼠标被释放（能点 UI）")
	await _press_escape()
	_check(not bool(menu.get("is_open")), "再按 Esc 关掉了")
	_check(not paused, "关闭后游戏恢复运行")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "关闭后鼠标重新被捕获")

	print("\n========== 3. 设置真的作用到系统上了 ==========")
	GameSettings.set_value("mouse_sensitivity", 0.005)
	await _wait(2)
	_check(absf(player.mouse_sensitivity - 0.005) < 0.0001,
		"灵敏度同步到 player（实测 %.4f）" % player.mouse_sensitivity)

	GameSettings.set_value("fov", 80.0)
	await _wait(2)
	_check(absf(player.hip_fov - 80.0) < 0.01, "腰射 FOV 同步（实测 %.1f）" % player.hip_fov)
	_check(absf(player.aim_fov - 80.0 * Player.AIM_FOV_RATIO) < 0.01,
		"开镜 FOV 按比例跟着走（实测 %.1f）" % player.aim_fov)

	var bus := AudioServer.get_bus_index("Master")
	GameSettings.set_value("master_volume", 0.5)
	await _wait(2)
	var db := AudioServer.get_bus_volume_db(bus)
	_check(absf(db - linear_to_db(0.5)) < 0.05, "主音量作用到 Master 总线（实测 %.2f dB）" % db)
	GameSettings.set_value("master_volume", 0.0)
	await _wait(2)
	_check(AudioServer.is_bus_mute(bus), "音量拉到 0 时真的静音（而不是 -inf dB 污染总线）")
	GameSettings.set_value("master_volume", 1.0)
	await _wait(2)
	_check(not AudioServer.is_bus_mute(bus), "拉回来就取消静音")

	var guns := _guns(game)
	_check(guns.size() == 7, "找到 7 把同伴的枪（实测 %d）" % guns.size())
	GameSettings.set_value("companion_fire", false)
	await _wait(2)
	_check(_guns_idle(guns), "关掉后 %d 把枪全部停火" % guns.size())
	GameSettings.set_value("companion_fire", true)
	await _wait(2)
	_check(not _guns_idle(guns), "打开后恢复开火")

	var bosses := _bosses(game)
	# ⚠️ 场上有几位就断言几位：默认只有飞猪优香（1），`-- --bosses=all` 是 7。
	#    写死数字的话，每加一位 Boss 这条就假红一次 —— 本喵已经踩过两次。
	var want_bosses := 0
	for ch in game.get_children():
		if ch is Boss:
			want_bosses += 1
	_check(bosses.size() == want_bosses,
		"找到 %d 位 Boss（实测 %d）" % [want_bosses, bosses.size()])
	GameSettings.set_value("boss_attack", false)
	await _wait(2)
	_check(_boss_attack_off(bosses), "关掉后 %d 位 Boss 都不主动攻击" % bosses.size())
	GameSettings.set_value("boss_attack", true)
	await _wait(2)
	_check(not _boss_attack_off(bosses), "打开后恢复攻击")

	print("\n========== 4. 落盘 ==========")
	GameSettings.set_value("fov", 71.0)
	await _wait(2)
	var cfg := ConfigFile.new()
	var err := cfg.load("user://settings.cfg")
	_check(err == OK, "user://settings.cfg 能读出来（err=%d）" % err)
	if err == OK:
		_check(absf(float(cfg.get_value("settings", "fov", 0.0)) - 71.0) < 0.01,
			"fov 已落盘（实测 %.1f）" % float(cfg.get_value("settings", "fov", 0.0)))
		_check(cfg.has_section_key("settings", "companion_fire"), "开关型的项也落盘了")

	print("\n========== 5. 恢复默认 ==========")
	GameSettings.reset_all()
	await _wait(2)
	var all_default := true
	for key in GameSettings.DEFAULTS.keys():
		if GameSettings.value(key) != GameSettings.DEFAULTS[key]:
			all_default = false
			print("      %s = %s（期望 %s）" % [
				key, str(GameSettings.value(key)), str(GameSettings.DEFAULTS[key])])
	_check(all_default, "所有项回到默认值")
	_check(absf(player.mouse_sensitivity
			- float(GameSettings.DEFAULTS["mouse_sensitivity"])) < 0.0001,
		"玩家灵敏度也跟着回默认（实测 %.4f）" % player.mouse_sensitivity)
	_check(not _guns_idle(guns), "清掉「关火」后同伴恢复开火")

	print("\n========== 6. 渲图 ==========")
	menu.call("open")
	await _wait(20)
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_ui")
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("96_settings_menu.png"))
	print("  [img] %s" % out.path_join("96_settings_menu.png"))
	menu.call("close")
	await _wait(3)
	_check(not paused, "渲图完关掉菜单，暂停已恢复")

	print("\n================ 结果 ================")
	_quit()


# --- 工具 ---

func _guns(game: Node) -> Array:
	var out := []
	for child in game.get_children():
		if child is Companion:
			var g := child.get_node_or_null("Gun")
			if g != null:
				out.append(g)
	return out


func _guns_idle(guns: Array) -> bool:
	for g in guns:
		if g.call("_is_active"):
			return false
	return true


func _bosses(game: Node) -> Array:
	var out := []
	for child in game.get_children():
		if child is BossAttacker:
			out.append(child)
	return out


func _boss_attack_off(bosses: Array) -> bool:
	for b in bosses:
		if bool(b.get("_settings_enabled")):
			return false
	return true


## 走**真实输入路径**按一下 Esc（而不是直接调 menu.toggle()），
## 这样连「菜单能不能收到按键」一起验了。
func _press_escape() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(4)


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

extends SceneTree
## 只读探针：小屋电脑 + 假 Arch 终端。
##   godot --headless --path . --script res://scripts/_probe_computer.gd

const GAME := "res://scenes/game.tscn"

func _initialize() -> void:
	_run.call_deferred()


func _key(ch := "", code := KEY_NONE) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	if ch.length() > 0:
		e.unicode = ch.unicode_at(0)
	e.keycode = code
	return e


func _type(t: ArchTerminal, text: String) -> void:
	for i in text.length():
		t.feed(_key(text[i]))


func _enter(t: ArchTerminal) -> void:
	t.feed(_key("", KEY_ENTER))


func _run() -> void:
	var fails := 0
	var ps := load(GAME) as PackedScene
	if ps == null:
		print("[pc] 读不到 ", GAME)
		quit(1)
		return
	var game := ps.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var hut := game.get_node_or_null("MeshHut") as Node3D
	var pc := game.get_node_or_null("MeshHut/HutComputer") as HutComputer
	print("[pc] MeshHut %s   HutComputer %s"
		% ["有" if hut != null else "没有", "有" if pc != null else "没有"])
	if pc == null:
		print("[pc] ✗ 找不到电脑节点")
		quit(1)
		return

	# ① 建模
	var screen := pc.screen_mesh()
	var mat := screen.material_override as StandardMaterial3D if screen != null else null
	print("[pc] 屏幕网格 %s，PlaneMesh %s，贴图 %s，UNSHADED %s"
		% ["有" if screen != null else "没有",
			"有" if (screen != null and screen.mesh is PlaneMesh) else "没有",
			"有" if (mat != null and mat.albedo_texture != null) else "没有",
			str(mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)])
	if screen == null or mat == null or mat.albedo_texture == null:
		print("[pc] ✗ 屏幕没接上 SubViewport 贴图")
		fails += 1

	# ② 终端初始内容
	var t := pc.terminal
	print("[pc] 终端 %s，初始 %d 行" % ["有" if t != null else "没有", t.line_count() if t != null else -1])
	if t == null or t.line_count() < 20:
		print("[pc] ✗ 终端没铺出 neofetch（行数太少）")
		fails += 1
	else:
		var txt := t.screen_text()
		for probe in ["Arch Linux x86_64", "RTX 5090", "alice@arisu", "arch1-1"]:
			var ok := txt.contains(probe)
			print("[pc]   neofetch 含「%s」：%s" % [probe, "是" if ok else "否"])
			if not ok:
				fails += 1

	# ③ 打开
	pc.use_for_test()
	await process_frame
	print("[pc] 打开后 is_using=%s" % str(pc.is_using()))
	if not pc.is_using():
		print("[pc] ✗ use_for_test 没打开")
		fails += 1

	# ④ 敲 help
	_type(t, "help")
	_enter(t)
	var after_help := t.screen_text()
	var has_help := after_help.contains("commands (all fake")
	print("[pc] 敲 help → 输出含「commands (all fake」：%s（现在 %d 行）"
		% ["是" if has_help else "否", t.line_count()])
	if not has_help:
		fails += 1

	# ⑤b logo 各行的宽度（右边那列对齐靠 `LOGO_WIDTH=42` 的 rpad，行长不一致就歪）
	var maxw := 0
	for row in ArchTerminal.LOGO:
		maxw = maxi(maxw, String(row).length())
	print("[pc] logo 最长一行 %d 列（LOGO_WIDTH=%d）" % [maxw, ArchTerminal.LOGO_WIDTH])
	if maxw > ArchTerminal.LOGO_WIDTH:
		print("[pc] ✗ logo 有行超过 LOGO_WIDTH，右边那列会歪")
		fails += 1

	# ⑤ 敲一条不存在的
	_type(t, "xyzzy")
	_enter(t)
	var has_404 := t.screen_text().contains("command not found: xyzzy")
	print("[pc] 敲 xyzzy → 「command not found: xyzzy」：%s" % ["是" if has_404 else "否"])
	if not has_404:
		fails += 1

	# ⑥ 敲 exit 应该自己关掉
	_type(t, "exit")
	_enter(t)
	await process_frame
	print("[pc] 敲 exit → is_using=%s（应为 false）" % str(pc.is_using()))
	if pc.is_using():
		print("[pc] ✗ exit 没有关掉界面")
		fails += 1

	# ⑦ 关掉之后玩家的进程要恢复
	var p := game.get_node_or_null("Player") as Node3D
	if p != null:
		var ok := p.is_physics_processing() and p.is_processing() and p.is_processing_input()
		print("[pc] 玩家进程恢复：物理 %s / process %s / input %s"
			% [str(p.is_physics_processing()), str(p.is_processing()), str(p.is_processing_input())])
		if not ok:
			fails += 1

	print("[pc] %s（失败 %d 项）" % ["全部通过" if fails == 0 else "有失败", fails])
	quit(0 if fails == 0 else 1)

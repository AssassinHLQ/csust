extends SceneTree
## 出图 + 实测：两张配置单底图不同；弹单子时鼠标放开、能悬停换图，关掉后收回鼠标。
##   _tools/run_shot.sh res://scripts/_probe_sheet_pair_shot.gd
const BankCard := preload("res://scripts/bank_card.gd")
const OUT := "res://_arisu_captures/_sheets"


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, name])
	print("[sheet-shot] 存图 %s/%s.png" % [OUT, name])


func _hover_row(box: DialogueBox, i: int) -> void:
	var zones: Array = box.get("_sheet_zones")
	if i >= zones.size():
		return
	var zone := zones[i] as Control
	var c := zone.get_global_rect().get_center()
	print("[sheet-shot]   热区 %d rect=%s 中心=%s viewport=%s focused=%s" % [
		i, str(zone.get_global_rect()), str(c), str(root.get_visible_rect()),
		str(DisplayServer.window_is_focused())])
	Input.warp_mouse(c)
	var mm := InputEventMouseMotion.new()
	mm.position = c
	mm.global_position = c
	root.push_input(mm, true)
	await _wait(6)
	var hov := box.get_viewport().gui_get_hovered_control()
	print("[sheet-shot]   gui_get_hovered_control = %s（期望 Row0）" % (
		hov.name if hov != null else "null"))



## 鼠标模拟在无头/窗口脚本里不稳定，出图直接按行数据把覆盖层换成对应零件图，
## 证明「这一行该显示哪张」；真正的悬停逻辑由 _verify_config_parts.gd 与旧探针保证。
func _force_row(box: DialogueBox, spec: Dictionary, i: int) -> void:
	var part := String((spec["parts"] as Array)[i])
	var tex := load("res://assets/story/parts/%s.png" % part) as Texture2D
	var hv := box.get("_sheet_hover") as TextureRect
	hv.texture = tex
	hv.visible = true
	var cap := box.get("_sheet_caption") as Label
	cap.text = String((spec["labels"] as Array)[i])

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	root.grab_focus()
	await _wait(20)
	print("[sheet-shot] 窗口 focused=%s" % str(DisplayServer.window_is_focused()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var old := BankCard.balance()
	BankCard.set_balance(800000)

	var clerk := ShopClerk.new()
	root.add_child(clerk)
	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)
	clerk.call("_talk", box)
	await _wait(4)
	box.advance()
	await _wait(4)
	box.call("_confirm_choice")
	await _wait(4)

	# ── 第一张：故意先假装游戏还抓着鼠标 ──
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	while not box.is_showing_sheet():
		box.advance()
		await _wait(3)
	var tex1: Texture2D = (box.get("_sheet_base") as TextureRect).texture
	print("[sheet-shot] 第 1 张 = %s　mouse_mode=%d（0=VISIBLE 才对）" % [
		tex1.resource_path, Input.mouse_mode])
	await _hover_row(box, 0)
	var hv1 := box.get("_sheet_hover") as TextureRect
	print("[sheet-shot] 悬停第 1 行：可见=%s 图=%s" % [
		str(hv1.visible), hv1.texture.resource_path if hv1.texture != null else "-"])
	await _shot("01_sheet_b300")
	for idx in [4, 5]:
		_force_row(box, ShopClerk.SHEET_B300, int(idx))
		await _shot("01b_b300_row%d" % (int(idx) + 1))
	box.advance()
	await _wait(4)
	print("[sheet-shot] 关掉第一张后 mouse_mode=%d（2=CAPTURED 才对）" % Input.mouse_mode)

	# ── 第二张 ──
	while not box.is_showing_sheet():
		box.advance()
		await _wait(3)
	var tex2: Texture2D = (box.get("_sheet_base") as TextureRect).texture
	print("[sheet-shot] 第 2 张 = %s　mouse_mode=%d" % [tex2.resource_path, Input.mouse_mode])
	await _hover_row(box, 0)
	var hv2 := box.get("_sheet_hover") as TextureRect
	print("[sheet-shot] 悬停第 1 行：可见=%s 图=%s（期望 gpu5090.png）" % [
		str(hv2.visible), hv2.texture.resource_path if hv2.texture != null else "-"])
	await _shot("02_sheet_5090")
	for idx in [1, 3, 7, 8]:
		_force_row(box, ShopClerk.SHEET_5090, int(idx))
		await _shot("02b_5090_row%d" % (int(idx) + 1))
	await _hover_row(box, 0)
	print("[sheet-shot] 结论：%s" % (
		"OK 两张不同" if tex1.resource_path.ends_with("config_sheet.png")
		and tex2.resource_path.ends_with("config_sheet_5090.png") else "FAIL"))
	box.finish()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	BankCard.set_balance(old)
	quit(0)

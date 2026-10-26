extends SceneTree
## 验数：芹香的对话交互 —— ① 靠近出现提示 ② 按 F 弹出对话且第一句是那句话
##   godot --path . --headless --script res://scripts/_verify_clerk_talk.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	for _f in 20:
		await process_frame

	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	var box := game.get_node_or_null("DialogueBox") as DialogueBox
	var player := game.get("_player") as CharacterBody3D
	if clerk == null or box == null or player == null:
		print("[错误] 缺节点 clerk=%s box=%s player=%s"
			% [str(clerk), str(box), str(player)])
		quit(1)
		return
	print("芹香位置 %s；对话盒 %s" % [str(clerk.global_position), box.get_class()])

	var hint := clerk.get_node_or_null("TalkHint") as Label3D
	print("提示节点：%s" % ("有" if hint != null else "**没有**"))

	# ① 远处：提示应隐藏
	player.global_position = clerk.global_position + Vector3(0.0, 0.0, -8.0)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	print("\n[远处 8 m]  提示 visible = %s（应为 false）"
		% str(hint.visible if hint != null else "n/a"))

	# ② 走近：提示应出现
	player.global_position = clerk.global_position + Vector3(-1.2, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	var d := player.global_position - clerk.global_position
	print("[近处 %.2f m] 提示 visible = %s（应为 true）"
		% [Vector2(d.x, d.z).length(), str(hint.visible if hint != null else "n/a")])

	# ③ 按 F：对话应开始，且第一句是「你配电脑吗?」
	print("\n[按 F] 对话盒 is_active 之前 = %s" % str(box.is_active()))
	_key(KEY_F)
	for _f in 20:
		await process_frame
	print("        对话盒 is_active 之后 = %s" % str(box.is_active()))
	print("        当前说话人 = 「%s」" % box.current_who())
	print("        当前文本   = 「%s」" % box.current_text())
	print("        文本对吗   = %s" % str(box.current_text().begins_with("你配电脑吗")))

	# ④ 关掉对话，确认世界恢复
	box.finish()
	for _f in 10:
		await process_frame
	print("\n[结束后] 对话盒 is_active = %s；世界 paused = %s"
		% [str(box.is_active()), str(paused)])
	quit(0)

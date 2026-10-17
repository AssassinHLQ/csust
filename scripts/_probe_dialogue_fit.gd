extends SceneTree
## 探针：开场那句「2067 年……灾难。」在对话框里到底排了几行、有没有被裁掉。
##
## 用户报「最后两个字看不见」。怀疑是 `Body` 这个 Label 的 `clip_text = true`
## 加上宽度 / 行高不够，最后几个字被裁。这里把**实际布局**摊开：
##   · 窗口尺寸、Box 的位置与尺寸（是不是超出屏幕）
##   · Body 的位置与尺寸、`get_line_count()` vs `get_visible_line_count()`
##   · 整句用主题字体量出来的宽度（不换行时有多宽）
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_dialogue_fit.gd

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1401, 919)
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)

	var box := game.get_node_or_null("DialogueBox")
	if box == null:
		print("!! 场景里没有 DialogueBox")
		quit(1)
		return
	print("\n窗口 %s   可视区域 %s   拉伸模式 %d  缩放 %s" % [
		str(root.size), str(root.get_visible_rect().size),
		root.content_scale_mode, str(root.content_scale_size)])

	box.call("play_file", "res://story/开场.txt")
	# 等打字机把整句吐完（30 字/秒，最长那句 30 字 → 1 s 足够）
	await _wait(150)

	var controls := {}
	for path in ["Root", "Root/Box", "Root/Box/Body", "Root/Box/Hint"]:
		var n := game.get_node_or_null("DialogueBox/" + path)
		if n is Control:
			var c := n as Control
			controls[path] = c
			print("  %-16s 位置 %s  尺寸 %s  可见=%s" % [
				path, str(c.global_position.snappedf(0.1)),
				str(c.size.snappedf(0.1)), str(c.is_visible_in_tree())])
		else:
			print("  %-16s 找不到" % path)

	var body := controls.get("Root/Box/Body") as Label
	if body == null:
		print("!! 没有 Body")
		quit(1)
		return

	var font := body.get_theme_font("font")
	var fs := body.get_theme_font_size("font_size")
	var text := body.text
	print("\nBody 文本（%d 字）：%s" % [text.length(), text])
	print("  字体 %s  字号 %d  自动换行=%d  clip_text=%s" % [
		font.resource_path if font else "（无）", fs, body.autowrap_mode,
		str(body.clip_text)])
	print("  行数=%d  可见行数=%d  %s" % [
		body.get_line_count(), body.get_visible_line_count(),
		"← **被裁了**" if body.get_line_count() > body.get_visible_line_count() else "（没裁）"])
	if font != null:
		var one := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		print("  不换行时整句宽 %.1f px（Body 可用宽 %.1f px）→ %s" % [
			one.x, body.size.x,
			"放得下" if one.x <= body.size.x else "**放不下，得换行**"])
		var ch := font.get_string_size("灾", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		print("  单字宽 %.1f px  行高 %.1f px  Body 高 %.1f px（放得下 %.1f 行）" % [
			ch.x, font.get_height(fs), body.size.y, body.size.y / maxf(font.get_height(fs), 1.0)])
		# 逐字累加，看第几个字开始超出 Body 宽度
		var acc := 0.0
		for i in text.length():
			acc = font.get_string_size(text.substr(0, i + 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if acc > body.size.x:
				print("  第 %d 个字之后（x≈%.0f）就超出 Body 宽度了：后面是「%s」" % [
					i, acc, text.substr(i, 12)])
				break
	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

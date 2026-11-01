extends SceneTree
## 验第二张配置单（5090）：底图能载、9 行热区、和小桃那段串起来能播完。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var tex := load("res://assets/story/config_sheet_5090.png") as Texture2D
	print("[5090] 底图 = %s %s" % ["OK" if tex != null else "缺失",
		"%dx%d" % [tex.get_width(), tex.get_height()] if tex != null else ""])
	var g := load("res://assets/story/parts/gpu5090.png") as Texture2D
	print("[5090] 显卡图 = %s" % ("OK" if g != null else "缺失"))

	var parts := ["gpu5090", "", "", "ram", "ssd", "ssd", "psu", "", ""]
	var rows: Array = []
	for i in parts.size():
		var p := String(parts[i])
		rows.append({"top": 146.0 + i * 66.0, "bottom": 146.0 + (i + 1) * 66.0,
			"image": "" if p.is_empty() else "res://assets/story/parts/%s.png" % p,
			"label": "第 %d 行" % (i + 1)})
	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)
	box.play_steps([
		{"kind": "say", "who": "芹香", "text": "老板,看这套配置怎么样[TVT]"},
		{"kind": "config_sheet", "base": "res://assets/story/config_sheet_5090.png",
			"photo": {"x": 1064, "y": 146, "w": 492, "h": 560}, "rows": rows,
			"caption": "图上为八卡 5090 工作站"},
		{"kind": "say", "who": "芹香", "text": "八张 5090 加撕裂者，五十来万——这张才是真能装能跑的。"},
	], "check")
	for _i in 10:
		await process_frame
	box.advance()          # 跳过第一句，进配置单
	for _i in 10:
		await process_frame
	print("[5090] 弹单子=%s 热区=%d（期望 9）" % [str(box.is_showing_sheet()), box.sheet_zone_count()])
	box.advance()
	for _i in 10:
		await process_frame
	print("[5090] 关掉后正文=%s" % box.current_text())
	box.advance()
	for _i in 10:
		await process_frame
	print("[5090] 结尾 is_active=%s" % str(box.is_active()))
	quit(0)

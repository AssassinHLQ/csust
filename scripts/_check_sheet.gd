extends SceneTree
## 验可交互配置单：底图 + 9 个热区 + 每行零件图都能载入。
##   godot --path . --headless --script res://scripts/_check_sheet.gd

const PARTS := ["gpu", "server", "cpu", "ram", "ssd", "ssd", "nic", "cooling", "psu"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var rows: Array = []
	for i in PARTS.size():
		var p := "res://assets/story/parts/%s.png" % PARTS[i]
		var tex := load(p) as Texture2D
		if tex == null:
			print("[sheet] ✗ 零件图载入失败：%s" % p)
		rows.append({"top": 146.0 + i * 66.0, "bottom": 146.0 + (i + 1) * 66.0, "image": p})

	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.play_steps([{
		"kind": "config_sheet",
		"base": "res://assets/story/config_sheet.png",
		"photo": {"x": 1064, "y": 146, "w": 492, "h": 560},
		"rows": rows,
	}], "check")
	for _i in 8:
		await process_frame
	print("[sheet] 显示=%s  热区=%d（期望 9）" % [str(box.is_showing_sheet()), box.sheet_zone_count()])
	box.advance()
	for _i in 6:
		await process_frame
	print("[sheet] 关掉后 is_active=%s" % str(box.is_active()))
	quit(0)

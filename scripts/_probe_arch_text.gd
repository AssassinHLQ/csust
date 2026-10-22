extends SceneTree
## 只读探针：把 ArchTerminal 的每一行**原样**打出来（排查列对齐）。
##   godot --headless --path . --script res://scripts/_probe_arch_text.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t := ArchTerminal.new()
	root.add_child(t)
	await process_frame
	var lines := t.screen_text().split("\n")
	for i in lines.size():
		var s: String = lines[i]
		print("%02d|%s|" % [i, s.rstrip(" ")])
	print("[arch] 共 %d 行" % lines.size())
	quit(0)

extends SceneTree
## 探针：Esc 面板里那条「操作」只剩按键一行，且没有被裁。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_help_line.gd

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1401, 919)
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)
	var menu := game.get_node_or_null("SettingsMenu")
	if menu == null:
		print("!! 场景里没有 SettingsMenu")
		quit(1)
		return
	menu.call("open")
	await _wait(10)
	var help := _find(menu, "Help")
	if help == null:
		print("!! 找不到 Help")
		quit(1)
		return
	var l := help as Label
	print("\nHelp 文本：%s" % l.text)
	print("  行数 %d  可见行数 %d  尺寸 %s" % [
		l.get_line_count(), l.get_visible_line_count(), str(l.size.snappedf(0.1))])
	print("  文本里有「同伴」？%s  有「画室609」？%s" % [
		str(l.text.contains("同伴")), str(l.text.contains("画室609"))])
	quit(0)


func _find(n: Node, nm: String) -> Node:
	if String(n.name) == nm:
		return n
	for c in n.get_children():
		var r := _find(c, nm)
		if r != null:
			return r
	return null


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

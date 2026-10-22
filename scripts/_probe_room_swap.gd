extends SceneTree
## 探针：房间代理（方盒）为什么没被藏起来。
##   godot --path . --script res://scripts/_probe_room_swap.gd

func _initialize() -> void:
	_run.call_deferred()


func _p(game: Node3D, tag: String) -> void:
	var proxy: Node3D = game.get("_room_proxy")
	var player: Node3D = game.get("_player")
	var box: AABB = game.get("_room_box")
	var txt := "%-14s paused=%s  game.is_processing=%s  vis_proxy=%s  inside=%s  ready=%s  玩家=%s" % [
		tag, str(paused), str(game.is_processing()), str(proxy.visible),
		str(game.get("_room_inside")),
		str((game.get("_room_scene") as Object) != null and bool(game.get("_room_scene").call("is_ready"))),
		str(player.global_position.snappedf(0.01))]
	print(txt)
	print("               房间盒 pos=%s size=%s" % [str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 30:
		await process_frame
	_p(game, "30帧(剧情中)")
	paused = false
	for _i in 20:
		await process_frame
	_p(game, "解暂停+20帧")
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")
	for _i in 20:
		await process_frame
	_p(game, "跳过剧情")
	# 手动跑一次，看它自己算出什么
	game.call("_update_room_swap")
	_p(game, "手动调用后")
	quit(0)

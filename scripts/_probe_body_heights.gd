extends SceneTree
## 各角色「身体」有多高 —— 量的是**逐网格**包围盒，避免被枪/光环/裙摆带偏。
##   godot --path . --headless --script res://scripts/_probe_body_heights.gd -- --splat=off
##
## 起因：`_probe_clerk_anim_ground.gd` 发现芹香身上最低的网格是
## **`Serika_Original_Weapon2`（她的枪，绑姿垂到原点下方 0.271 m）**，
## 而 `Serika_Original_Body2`（身体）最低点在 **+0.295** —— 也就是说
## 「原点在脚上方 0.27 m」这个结论是把**枪**当成了鞋底，`CLERK_LIFT = 0.296`
## 是重复补偿：模型原点本来就在鞋底。这里把所有角色的「身体网格」摆到一起比。

func _initialize() -> void:
	_run.call_deferred()


func _report(tag: String, node: Node3D) -> void:
	print("\n── %s（%s）──" % [tag, node.get_path()])
	var rows: Array = []
	var all := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		all = a if first else all.merge(a)
		first = false
		rows.append({"n": String(m.name), "lo": a.position.y, "hi": a.end.y})
	rows.sort_custom(func(x, y): return (float(x["hi"]) - float(x["lo"])) > (float(y["hi"]) - float(y["lo"])))
	print("  网格 %d 个；整体包围盒 y %+.3f ~ %+.3f" % [rows.size(), all.position.y, all.end.y])
	for h in rows.slice(0, 5):
		print("  %-26s y %+.3f ~ %+.3f（高 %.3f）"
			% [h["n"], h["lo"], h["hi"], float(h["hi"]) - float(h["lo"])])
	# 最高的那个网格的顶 - 最低的顶？不猜，直接给「所有网格里最靠上的顶」
	var top := -999.0
	for h in rows:
		top = maxf(top, float(h["hi"]))
	print("  最高点 y = %+.3f" % top)


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var player := game.get_node_or_null("Player") as Node3D
	if player != null:
		_report("爱丽丝（玩家）", player)
		print("  玩家原点世界 y = %+.3f" % player.global_position.y)
	_report("芹香（店员）", game.get_node_or_null("Shop/ClerkSerika") as Node3D)
	for nm in ["CompanionMomoi", "CompanionYuuka"]:
		var c := game.get_node_or_null(nm) as Node3D
		if c != null:
			_report(nm, c)
			print("  节点原点世界 y = %+.3f" % c.global_position.y)
	quit(0)

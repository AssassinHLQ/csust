extends SceneTree
## 批量自检：招牌蓝底、门禁浮空字隐藏、柴关招牌碰撞、小屋改名、两盏灯。
##   _tools/run_probe.sh res://scripts/_verify_fix_batch.gd -- --splat=off --story=off

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, msg: String) -> void:
	print(("[ OK ] " if ok else "[FAIL] ") + msg)
	if not ok:
		_fails += 1


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(120)

	# 1) 小屋改名
	var hut := game.get_node_or_null("MeshHut")
	var hut_sign := hut.get_node_or_null("SignText") as Label3D if hut != null else null
	_check(hut_sign != null, "小屋门上有 SignText")
	if hut_sign != null:
		_check(hut_sign.text == "临时服务器据点", "小屋招牌文字 = %s" % hut_sign.text)
		_check(hut_sign.font != null, "小屋招牌字体已加载")
	var pads := get_nodes_in_group("summon_pads")
	_check(pads.size() > 0, "场景里有召唤台")
	if pads.size() > 0:
		_check(String(pads[0].call("title_text")) == "临时服务器据点",
			"召唤台标题 = %s" % String(pads[0].call("title_text")))

	# 2) 柴关电脑城发光招牌碰撞
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(27.3, 5.55, -9.0), Vector3(27.3, 5.55, -16.0))
	var hit := root.world_3d.direct_space_state.intersect_ray(q)
	_check(not hit.is_empty() and hit.position.z > -12.75 and hit.position.z < -12.5
		and absf(hit.position.y - 5.55) < 0.3,
		"柴关招牌射线命中 %s" % (str(hit.position.snappedf(0.01)) if not hit.is_empty() else "无"))

	# 3) 门禁浮空字全部隐藏
	var gates := get_nodes_in_group("scene_gates")
	_check(gates.size() > 0, "场景里有场景门（%d 个）" % gates.size())
	for g in gates:
		var t := g.get_node_or_null("Title") as Label3D
		var p := g.get_node_or_null("Prompt") as Label3D
		_check(t != null and not t.visible and p != null and not p.visible,
			"%s 的标题/提示都隐藏" % g.name)

	# 4) 游戏开发部：蓝底招牌 + 两盏实体灯
	var room := game.get_node_or_null("GameDevRoom")
	var board := room.get_node_or_null("Model/SignBoard") as MeshInstance3D if room != null else null
	var mat := board.material_override as StandardMaterial3D if board != null else null
	_check(mat != null, "游戏开发部招牌底板有材质")
	if mat != null:
		var c := mat.albedo_color
		_check(c.b > c.r + 0.2 and c.b > c.g + 0.15, "招牌是蓝色 (%.2f, %.2f, %.2f)" % [c.r, c.g, c.b])
	for n in ["Model/LampA_Glow", "Model/LampB_Glow", "Model/LampA_Stem", "Model/LampB_Stem"]:
		_check(room != null and room.get_node_or_null(n) != null, "存在 %s" % n)

	if _fails == 0:
		print("[batch] 结论：OK")
		quit(0)
	else:
		print("[batch] 结论：FAIL %d 项" % _fails)
		quit(1)

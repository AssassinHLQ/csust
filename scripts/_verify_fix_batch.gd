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

	# 2) 柴关电脑城发光招牌：碰撞盒必须真的**压在实墙上**
	# ⚠️ 2026-11-10 修：老版本写死射线 (27.3,5.55,-9.0)→(27.3,5.55,-16.0)、并断言命中 z≈-12.6。
	#    那是 Shop 还在 z=-15.5 时的坐标。后来：
	#      · Shop 在 game.tscn 里挪到 z=-11.37（前墙+招牌整体前移到 z≈-8.3）
	#      · 招牌又按 5beb651 对齐到 ShellFrontWallShape（世界 x 31.0 / z -8.31）
	#    于是老断言永远打不中 z≈-12.6，连续报 FAIL —— 但招牌本身是好的。
	#    射线法在这里本身就不可靠（5beb651 记过：起点落进碰撞体内部会返回空；
	#    往里打还会先撞到屋里的玻璃隔断）。所以改用 _probe_shop_sign2.gd 那套判据：
	#    招牌 x 区间 ⊂ 前墙碰撞体 x 区间，且招牌背面贴着前墙面。
	var shop := game.get_node_or_null("Shop") as Node3D
	var shop_sign := game.get_node_or_null("Shop/Body/SignBoard") as MeshInstance3D
	var front_col := game.get_node_or_null("Shop/Body/ShellFrontWallShape") as CollisionShape3D
	_check(shop_sign != null and front_col != null, "柴关招牌与实墙碰撞体都在")
	if shop_sign != null and front_col != null:
		var bb: AABB = shop_sign.global_transform * shop_sign.get_aabb()
		var fsz: Vector3 = (front_col.shape as BoxShape3D).size
		var fbb: AABB = front_col.global_transform * AABB(-fsz * 0.5, fsz)
		print("      招牌 x=[%.2f, %.2f] z=[%.2f, %.2f]  /  前墙 x=[%.2f, %.2f] z=[%.2f, %.2f]" % [
			bb.position.x, bb.position.x + bb.size.x, bb.position.z, bb.position.z + bb.size.z,
			fbb.position.x, fbb.position.x + fbb.size.x, fbb.position.z, fbb.position.z + fbb.size.z])
		var x_in: bool = bb.position.x >= fbb.position.x - 0.01 and bb.position.x + bb.size.x <= fbb.position.x + fbb.size.x + 0.01
		_check(x_in, "招牌横向落在实墙区间内")
		var seam: float = bb.position.z - (fbb.position.z + fbb.size.z)
		_check(absf(seam) <= 0.05, "招牌背面贴墙：缝 %.3f m（容差 0.05）" % seam)
		# 招牌碰撞盒也必须同样贴墙、且横向落在实墙内。
		# ⚠️ 不能用 AABB.intersects()：5beb651 刻意留了「背面缝 0.020 m」，
		#    擦边贴合时 intersects() 返回 false，会误判成浮空。判据用「缝 ≤ 容差」。
		var sign_cs := game.get_node_or_null("Shop/Body/SignBoardShape") as CollisionShape3D
		var cs_ok := false
		if sign_cs != null and sign_cs.shape is BoxShape3D:
			var ssz: Vector3 = (sign_cs.shape as BoxShape3D).size
			var sbb: AABB = sign_cs.global_transform * AABB(-ssz * 0.5, ssz)
			var cs_seam: float = sbb.position.z - (fbb.position.z + fbb.size.z)
			var cs_x_in: bool = sbb.position.x >= fbb.position.x - 0.01 \
				and sbb.position.x + sbb.size.x <= fbb.position.x + fbb.size.x + 0.01
			cs_ok = absf(cs_seam) <= 0.05 and cs_x_in
			print("      碰撞盒 z=[%.3f, %.3f] 缝 %.3f m" % [
				sbb.position.z, sbb.position.z + sbb.size.z, cs_seam])
		_check(cs_ok, "招牌碰撞盒同样贴墙且横向在墙内（不是浮空）")

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

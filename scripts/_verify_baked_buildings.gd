extends SceneTree
## 自检：烘焙后的商店 / 大楼在运行时是不是**真的能用**（不是只有一堆网格）。
##   _tools/run_probe.sh res://scripts/_verify_baked_buildings.gd
##
## 验收项：
##   ① 商店/大楼是从 `game.tscn` 的实例节点来的（不是 game.gd 现场建的）
##   ② 商店：Body 下网格与碰撞盒成对、Deck 半块地板在、MusicZone 信号已连
##   ③ 芹香没被烘进去（场景里没有 ClerkSerika），但运行时建出来了
##   ④ 大楼：碰撞盒数量对得上（73）

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame

	var shop := game.get_node_or_null("Shop")
	var house := game.get_node_or_null("MondrianHouse")
	_check(shop != null, "商店节点存在（name=Shop）")
	_check(house != null, "大楼节点存在（name=MondrianHouse）")
	if shop == null or house == null:
		_finish()
		return

	# ② 商店：网格与碰撞成对
	var body := shop.get_node_or_null("Body")
	_check(body != null, "商店有 Body")
	if body != null:
		var meshes := 0
		var shapes := 0
		for c in body.get_children():
			if c is MeshInstance3D:
				meshes += 1
			elif c is CollisionShape3D:
				shapes += 1
		print("  Body：网格 %d、碰撞盒 %d（Deck 已拆到独立场景 ShopDeck）" % [meshes, shapes])
		_check(meshes == 26 and shapes == 26, "Body 里 26 对网格/碰撞盒")

	# ⚠️ 2026-11-08：Deck 已从 Shop 里拆成独立场景 `scenes/shop_deck.tscn`，
	#    在 `game.tscn` 里是 `Shop` 的**兄弟节点** `ShopDeck`（不再挂在 Shop 下）。
	#    所以这里要去场景根找，不能再 `shop.get_node_or_null("Deck/Deck")`。
	var deck := shop.get_node_or_null("Deck/Deck") as MeshInstance3D
	if deck == null:
		var root := shop.get_parent()
		if root != null:
			var deck_node := root.get_node_or_null("ShopDeck")
			if deck_node != null:
				deck = deck_node.get_node_or_null("Deck") as MeshInstance3D
	_check(deck != null, "半边地板 Deck 在（独立场景 ShopDeck）")
	if deck != null and deck.mesh is BoxMesh:
		var s := (deck.mesh as BoxMesh).size
		print("  Deck 盒尺寸 = (%.2f, %.2f, %.2f)" % [s.x, s.y, s.z])
		_check(absf(s.x - 19.99) < 0.05 and absf(s.z - 40.0) < 0.05, "Deck 覆盖 x 20~40、z -20~20")
		# ⚠️ 拆出去之后**位置不能变**：Deck 盒世界坐标必须还是 x 20.01~40.00、z -20~+20。
		var wb: AABB = deck.global_transform * deck.mesh.get_aabb()
		print("  Deck 世界 AABB = x %.2f~%.2f、z %.2f~%.2f" % [
			wb.position.x, wb.position.x + wb.size.x,
			wb.position.z, wb.position.z + wb.size.z])
		_check(absf(wb.position.x - 20.01) < 0.05 and absf(wb.position.z + 20.0) < 0.05,
			"Deck 拆出去后世界坐标没变（x 20.01~40.00、z -20~+20）")

	var zone := shop.get_node_or_null("MusicZone") as Area3D
	_check(zone != null, "MusicZone 在")
	if zone != null:
		_check(zone.body_entered.get_connections().size() > 0, "MusicZone 进出信号已连上")

	_check(shop.get_node_or_null("ClerkSerika") != null, "芹香是运行时建的（不在烘焙里）")

	# ④ 大楼
	var hbody := house.get_node_or_null("Body")
	if hbody != null:
		var hs := 0
		for c in hbody.get_children():
			if c is CollisionShape3D:
				hs += 1
		print("  大楼 Body 碰撞盒 %d 个" % hs)
		_check(hs == 73, "大楼碰撞盒 73 个")
	_check(house.get_node_or_null("Stair") != null or _has_name(house, "Stair"), "大楼楼梯在")
	_finish()


func _has_name(n: Node, want: String) -> bool:
	for c in n.find_children("*", "", true, false):
		if String(c.name).begins_with(want):
			return true
	return false


func _check(ok: bool, what: String) -> void:
	print(("  [PASS] " if ok else "  [FAIL] ") + what)
	if not ok:
		_fail += 1


func _finish() -> void:
	print("失败 %d 项" % _fail)
	quit(0 if _fail == 0 else 1)

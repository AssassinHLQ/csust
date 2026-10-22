extends SceneTree
## 只读探针：量「开机到可玩」到底花在哪，以及场景树里有多少节点是**代码建的**。
## 用法：
##   godot --headless --path . --script res://scripts/_probe_boot_cost.gd

const GAME := "res://scenes/game.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _count(r: Node) -> Dictionary:
	var d := {"node": 0, "mesh": 0, "coll": 0, "anim": 0}
	var stack: Array[Node] = [r]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		d["node"] += 1
		if n is MeshInstance3D:
			d["mesh"] += 1
		if n is CollisionShape3D:
			d["coll"] += 1
		if n is AnimationPlayer:
			d["anim"] += 1
		for c in n.get_children():
			stack.append(c)
	return d

func _run() -> void:
	var t0 := Time.get_ticks_usec()
	var ps := load(GAME) as PackedScene
	var t1 := Time.get_ticks_usec()
	if ps == null:
		print("[boot] 读不到 ", GAME)
		quit(1)
		return

	var game := ps.instantiate()
	var t2 := Time.get_ticks_usec()
	root.add_child(game)
	var t3 := Time.get_ticks_usec()

	# 等房间泼溅解码完（Room609 的 is_ready）
	var room: Node = game.find_child("Room609", true, false)
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		if room != null and room.has_method("is_ready") and bool(room.call("is_ready")):
			break
		await process_frame
	var t4 := Time.get_ticks_usec()

	var all := _count(game)
	var shop: Node = game.get_node_or_null("Shop")
	if shop == null:
		for c in game.get_children():
			if String(c.get_script().resource_path if c.get_script() != null else "").ends_with("shop.gd"):
				shop = c
				break
	var sd := {"node": 0, "mesh": 0, "coll": 0, "anim": 0}
	if shop != null:
		sd = _count(shop)

	print("[boot] 读场景      %6.1f ms" % ((t1 - t0) / 1000.0))
	print("[boot] instantiate %6.1f ms" % ((t2 - t1) / 1000.0))
	print("[boot] _ready      %6.1f ms   ← 所有脚本的 _ready 全在这一段" % ((t3 - t2) / 1000.0))
	print("[boot] 到 ready    %6.1f ms   （含泼溅解码；游戏内还牵扯异步）" % ((t4 - t3) / 1000.0))
	print("[boot] 全树节点 %d（网格 %d，碰撞 %d，动画 %d）" % [all.node, all.mesh, all.coll, all.anim])
	if shop != null:
		print("[boot] 商店子树 节点 %d（网格 %d，碰撞 %d）占全树 %.1f%%"
			% [sd.node, sd.mesh, sd.coll, 100.0 * sd.node / maxf(1.0, all.node)])
		# 再建一份，直接量 build() 本身（材质会再克隆一次，代表最坏情况）
		var ps2 := load("res://scenes/shop.tscn") as PackedScene
		if ps2 != null:
			var s2 := ps2.instantiate()
			s2.set("auto_build", false)
			game.add_child(s2)
			var b0 := Time.get_ticks_usec()
			s2.call("build")
			var b1 := Time.get_ticks_usec()
			print("[boot] shop.build() 单独耗时 %6.2f ms（%d 节点、%d 网格）"
				% [(b1 - b0) / 1000.0, _count(s2).node, _count(s2).mesh])
			s2.queue_free()
	else:
		print("[boot] 没找到商店节点")
	quit(0)

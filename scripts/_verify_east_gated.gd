extends SceneTree
## 查：**开局**（没成交）时，游戏开发部和它的地面必须在，电竞房必须不在。
## 成交之后电竞房才出现。
##
## 使用者 2026-11-08 原话：
##   「游戏开发部及其地面一直都要在！！只有电竞房是买的」
##
##   & godot --script res://scripts/_verify_east_gated.gd -- --splat=off --story=off

const ShopClerkScript := preload("res://scripts/shop_clerk.gd")

var _fails := 0


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[gate] OK   %s" % what)
	else:
		_fails += 1
		print("[gate] FAIL %s" % what)


func _count_mesh(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for ch in n.get_children():
		c += _count_mesh(ch)
	return c


func _vis(game: Node, nm: String) -> bool:
	var n := game.get_node_or_null(nm)
	if n == null:
		return false
	return (n as Node3D).is_visible_in_tree()


func _run() -> void:
	await _wait(3)

	# ── 阶段一：开局，没成交 ──
	ShopClerkScript._bought = false
	print("======== 阶段一：开局（未成交）========")
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await _wait(50)

	for nm in ["LotEast", "GameDevRoom"]:
		var n := game.get_node_or_null(nm)
		_check(n != null, "%s 节点存在" % nm)
		if n == null:
			continue
		_check((n as Node3D).is_visible_in_tree(), "%s 开局就可见（常驻）" % nm)
		_check(_count_mesh(n) > 0, "%s 里面有网格（%d 个）" % [nm, _count_mesh(n)])
		print("[gate]      %s pos=%s visible=%s"
			% [nm, str((n as Node3D).global_position), str((n as Node3D).visible)])

	var esp := game.get_node_or_null("EsportsRoom")
	_check(esp != null, "EsportsRoom 节点存在")
	if esp != null:
		_check(not (esp as Node3D).is_visible_in_tree(), "EsportsRoom 开局**不可见**（要买）")
		print("[gate]      EsportsRoom pos=%s visible=%s"
			% [str((esp as Node3D).global_position), str((esp as Node3D).visible)])

	game.queue_free()
	await _wait(5)

	# ── 阶段二：成交之后 ──
	ShopClerkScript._bought = true
	print("======== 阶段二：成交之后 ========")
	var game2: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game2)
	await _wait(50)

	for nm in ["LotEast", "GameDevRoom", "EsportsRoom"]:
		_check(_vis(game2, nm), "成交后 %s 可见" % nm)

	_check(_vis(game2, "EsportsRoom"), "EsportsRoom 成交后现身")

	print("[gate] 结果：%s（%d 项不合格）" % ["全过" if _fails == 0 else "有失败", _fails])
	quit(0 if _fails == 0 else 1)

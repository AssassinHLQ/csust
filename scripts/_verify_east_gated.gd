extends SceneTree
## 验：东侧开发部三块（地块 / 部室 / 电竞房）**买之前不出现、买完才出现**。
##   _tools/run_probe.sh res://scripts/_verify_east_gated.gd -- --splat=off --story=off
##
## 三条：
##   ① 没成交 → `LotEast` / `GameDevRoom` / `EsportsRoom` 都是 `visible = false`，
##      而且**不进渲染簇**（`RenderDistance` 只收 `is_visible_in_tree()` 的网格）；
##   ② 打开 `ShopClerk._bought = true` 并跑几帧 → 三块都 `visible = true`；
##   ③ 露出来之后再切一次簇，电竞房的网格**回到**切簇表里（别再被永远压着）。
## 结束后把 `_bought` 还原，别污染后续用例。

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


var _fails := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[gate] OK   %s" % what)
	else:
		_fails += 1
		print("[gate] FAIL %s" % what)


func _vis(game: Node) -> Dictionary:
	var out := {}
	for nm in ["LotEast", "GameDevRoom", "EsportsRoom"]:
		var n := game.get_node_or_null(nm) as Node3D
		out[nm] = (n.visible if n != null else null)
	return out


## 某个节点有没有被收进渲染簇（按节点身份找，不按名字）
func _in_clusters(rd: Node, target: Node) -> bool:
	if rd == null:
		return false
	var clusters: Array = rd.get("clusters")
	for c in clusters:
		if c.get("node") == target:
			return true
	return false


func _run() -> void:
	ShopClerk._bought = false
	root.size = Vector2i(960, 540)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(60)

	print("[gate] ── ① 还没在芹香那儿买 ──")
	var v := _vis(game)
	print("[gate] visible = %s" % str(v))
	for nm in v.keys():
		_check(v[nm] == false, "未成交时 %s 不可见（实际 %s）" % [nm, str(v[nm])])
	var rd := game.get_node_or_null("RenderDistance")
	_check(rd != null, "RenderDistance 已建")
	for nm in ["LotEast", "GameDevRoom", "EsportsRoom"]:
		var n := game.get_node_or_null(nm)
		_check(not _in_clusters(rd, n), "未成交时 %s 不进切簇（藏着的网格不提交）" % nm)

	print("[gate] ── ② 成交 ──")
	ShopClerk._bought = true
	await _wait(6)
	var v2 := _vis(game)
	print("[gate] visible = %s" % str(v2))
	for nm in v2.keys():
		_check(v2[nm] == true, "成交后 %s 可见（实际 %s）" % [nm, str(v2[nm])])

	print("[gate] ── ③ 露出来后重切簇 ──")
	var rd2 := game.get_node_or_null("RenderDistance")
	for nm in ["LotEast", "GameDevRoom", "EsportsRoom"]:
		var n := game.get_node_or_null(nm)
		_check(_in_clusters(rd2, n), "成交后 %s 回到切簇表里" % nm)

	ShopClerk._bought = false
	print("[gate] 结果：%s（%d 项不合格）" % ["全过" if _fails == 0 else "有红项", _fails])
	quit(0 if _fails == 0 else 1)

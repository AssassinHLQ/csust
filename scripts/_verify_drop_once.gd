extends SceneTree
## 验证：落地动画**一局只播一次**，重进场景不再播。
##
## 使用者 2026-11-10：「为什么每次切回场景都要播放这个落地动画?」
##
## 做法：连开两次 game.tscn（模拟「进场景 → 离开 → 再进」），
##       每次报告 EsportsDrop 有没有被创建。
##
##   godot --headless --script res://scripts/_verify_drop_once.gd -- --splat=off --story=off --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const ShopClerkScript := preload("res://scripts/shop_clerk.gd")
const GAME := "res://scenes/game.tscn"

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[once] OK   %s" % what)
	else:
		_fails += 1
		print("[once] FAIL %s" % what)


func _open_and_wait() -> Node:
	var game: Node = load(GAME).instantiate()
	root.add_child(game)
	# 等 ready + 演出挂上（演出脚本在 _ready 里同步创建）
	for _i in 30:
		await process_frame
	return game


func _run() -> void:
	await OffWin.apply(self, Vector2i(640, 360))
	await _wait(2)

	# 先清掉上一局可能残留的 static 标记（探针之间互不影响）
	ShopClerkScript._bought = true

	print("[once] ============ 测试：连开两次 game.tscn ============")

	# ── 第一次：应该播 ──
	var g1 := await _open_and_wait()
	var d1 := g1.get_node_or_null("EsportsDrop")
	var r1 := g1.get_node_or_null("EsportsRoom") as Node3D
	print("[once] 第 1 次进场景：EsportsDrop=%s  EsportsRoom.visible=%s"
		% ["有" if d1 != null else "无", str(r1.visible) if r1 != null else "?"])
	_check(d1 != null, "第 1 次进场景**播放**了落地动画")
	_check(r1 != null and r1.visible, "第 1 次进场景电竞房现身")

	# 直接跑完演出（别留半截）
	if d1 != null:
		var guard := 0
		while not bool(d1.get("_done")) and guard < 3000:
			d1._process(root.get_process_delta_time())
			await process_frame
			guard += 1
		await _wait(5)

	g1.queue_free()
	await _wait(10)
	print("[once] 第 1 次场景已卸载")

	# ── 第二次：不该再播 ──
	var g2 := await _open_and_wait()
	var d2 := g2.get_node_or_null("EsportsDrop")
	var r2 := g2.get_node_or_null("EsportsRoom") as Node3D
	print("[once] 第 2 次进场景：EsportsDrop=%s  EsportsRoom.visible=%s"
		% ["有" if d2 != null else "无", str(r2.visible) if r2 != null else "?"])
	_check(d2 == null, "第 2 次进场景**没有**重播落地动画")
	_check(r2 != null and r2.visible, "第 2 次进场景电竞房已经直接现身")

	print("[once] ---------- 结果：%s（%d 项不合格）----------"
		% ["全过" if _fails == 0 else "有失败", _fails])
	quit(0 if _fails == 0 else 1)

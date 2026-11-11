extends SceneTree
## 复现：609「出去 → 进去 → 再出来 墙就没了」。
##
##   godot --path . --headless --script res://scripts/_probe_room609_wall_loss.gd
##
## 用户 2026-11-11：「为什么609出来,进去,再出来就失去了墙?」
##
## 假设：`_update_room_swap()` 靠 `_room_box.grow(±0.25).has_point(p)` 判内外。
## 如果 `_room_box` 退化成**空 AABB**，两个 `has_point` 都 false ⇒ `_room_inside`
## **卡在上一次的值**（出屋时卡在 true）⇒ `_room_proxy.visible = not true` = false
## ⇒ 外面的墙消失了，而泼溅（如果 ready）还亮着 —— 正是截图里的样子。
##
## 所以每步都把 `_room_box` / `_room_inside` / `visible` / `splat_node` 全打出来。

const ROOM609 := "Room609"
const PROXY := "RoomProxy"
const INSIDE := Vector3(-0.5, 1.0, 3.5)     # 屋里正中（墙框内）
const OUTSIDE := Vector3(-0.5, 1.0, -12.0)   # 门外远处（墙框外）

var _game: Node3D
var _player: Node3D
var _room: Node


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _state(tag: String) -> void:
	var box: AABB = _game.get("_room_box")
	var inside: bool = _game.get("_room_inside")
	var proxy := _game.get_node_or_null(PROXY) as Node3D
	var splat: Node = _room.get("splat_node")
	var unloaded: bool = _room.get("_unloaded_by_room_exit")
	var p := _player.global_position
	print("  [%s] 玩家 %s" % [tag, str(p.snappedf(0.01))])
	print("        _room_box   = pos %s  size %s" % [str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	print("        _room_inside= %s   unloaded=%s   卸载开关=%s" % [inside, unloaded, _room.get("unload_outside_room")])
	print("        _room_xz    = %s   屋内判据=%s" % [
		str(_room.get("_room_xz")), _room.call("_is_inside_room", p)])
	print("        内外连击    = 外 %s / 内 %s" % [_room.get("_outside_streak"), _room.get("_inside_streak")])
	print("        proxy       = %s  visible=%s  children=%d" % [
		"在" if proxy != null else "**没了**",
		str(proxy.visible) if proxy != null else "-",
		proxy.get_child_count() if proxy != null else -1])
	print("        splat_node  = %s  is_ready=%s  loading=%s" % [
		"在" if splat != null else "null", _room.call("is_ready") if _room != null else "-",
		str(_room.get("loading")) if _room != null else "-"])
	print("        → 看到的 = %s" % (
		"代理墙（米色盒子 + 黑顶）" if proxy != null and proxy.visible
		else ("泼溅（扫描画面）" if splat != null and (splat as Node3D).visible else "**什么都没有**")))


func _goto(pos: Vector3, frames: int, tag: String) -> void:
	_player.global_position = pos
	_player.velocity = Vector3.ZERO
	await _wait(frames)
	_state(tag)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_game)
	_player = _game.get_node_or_null("Player") as Node3D
	_room = _game.get_node_or_null(ROOM609)
	if _player == null or _room == null:
		print("[FAIL] 场景里没有 Player / Room609")
		quit(1)
		return

	# 开关 / 判据的现场值（先看清为什么没卸载）
	print("=== 开关与判据 ===")
	print("  unload_outside_room = %s" % _room.get("unload_outside_room"))
	print("  GameSettings.splat_unload_outside = %s" % GameSettings.value("splat_unload_outside"))
	print("  unload_delay=%s  reload_delay=%s" % [_room.get("unload_delay"), _room.get("reload_delay")])
	print("  _room_xz 初始 = %s" % str(_room.get("_room_xz")))
	# ⚠️ 探针环境里的 settings.cfg 这份是 false（上一轮调试留下的），
	#    用户真实存档里是 true。用户报的 bug 只会在 true 时出现（走「卸载 + 重载」），
	#    所以这里**强制打开**，跑用户真正走的那条路。
	_room.set("unload_outside_room", true)
	print("  → 探针强制把 unload_outside_room 置 true（复现用户真实路径）")

	# 等泼溅解码完成（缓存命中约 9 s，冷启动 ~115 s）
	print("=== 0. 等 609 泼溅就位 ===")
	var waited := 0
	while not _room.call("is_ready") and waited < 4000:
		await _wait(10)
		waited += 10
	print("  等了 %.1f s，is_ready=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, _room.call("is_ready")])
	await _wait(10)
	_state("初始（站在出生点）")

	# 循环：出 → 进 → 出（用户报的正是第二次出）
	print("\n=== 1. 第 1 次走出 609 ===")
	await _goto(OUTSIDE, 40, "出 1")
	print("\n=== 2. 第 1 次走回 609 ===")
	await _goto(INSIDE, 40, "进 1")
	# 等重载（如果被卸过）
	var w2 := 0
	while not _room.call("is_ready") and w2 < 3000:
		await _wait(10)
		w2 += 10
	if w2 > 0:
		print("  重载等了 %.1f s" % (w2 / 100.0))
		await _wait(10)
	print("\n=== 3. 第 2 次走出 609（用户报 bug 的一步）===")
	await _goto(OUTSIDE, 40, "出 2")

	print("\n=== 4. 再走回来 / 再出去各一次，看是不是永久坏 ===")
	await _goto(INSIDE, 30, "进 2")
	await _goto(OUTSIDE, 30, "出 3")

	print("\n=== 判据 ===")
	var box2: AABB = _game.get("_room_box")
	var proxy2 := _game.get_node_or_null(PROXY) as Node3D
	var ok_box := box2.size.length() > 1.0
	print("  %s _room_box 还有体积（%s）" % ["PASS" if ok_box else "FAIL", str(box2.size.snappedf(0.01))])
	var ok_proxy := proxy2 != null and is_instance_valid(proxy2)
	print("  %s RoomProxy 还在场景里（%d 个子节点）" % ["PASS" if ok_proxy else "FAIL",
		proxy2.get_child_count() if ok_proxy else -1])
	quit(0)

extends SceneTree
## 量出画室609 的世界包围盒（给「出房间就释放」用）。
##
## 为什么需要：`splat_scene.gd` 的 `content_world_aabb()` 是从**点云**算出来的，
## 而新功能要「把点云释放掉」—— 释放之后这个数就没了。所以必须在**加载之后、
## 释放之前**把它存下来，或者干脆写成一个常量。
##
## 用法（headless，不弹窗口）：
##   _tools/run_probe.sh res://scripts/_probe_room609_bounds.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)

	var room: Node = game.get_node_or_null("Room609")
	if room == null:
		print("[bounds] 找不到 Room609")
		quit(1)
		return

	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 180000:
		if room.get("splat_node") != null:
			break
		await process_frame
	if room.get("splat_node") == null:
		print("[bounds] 泼溅没加载出来")
		quit(1)
		return

	var aabb: AABB = room.call("content_world_aabb")
	print("[bounds] content_world_aabb = AABB(%s, %s)" % [
		str(aabb.position.snappedf(0.01)), str(aabb.size.snappedf(0.01))])
	print("[bounds] 中心 %s   顶面 y=%.2f" % [
		str(aabb.get_center().snappedf(0.01)), float(room.call("content_top_y"))])

	# 外扩一圈：门在 z- 侧（`box_door_side = "z-"`），进出都要留余量，
	# 免得站在门口时来回触发释放/重载（抖）。
	for pad in [0.0, 1.0, 2.0, 3.0]:
		var g: AABB = aabb.grow(pad)
		print("[bounds]   grow(%.1f) → pos %s  size %s" % [
			pad, str(g.position.snappedf(0.01)), str(g.size.snappedf(0.01))])

	# 玩家出生点 / 院子位置，用来确认这个盒子确实能把「里面」和「外面」分开
	var player: Node3D = game.get_node_or_null("Player") as Node3D
	if player != null:
		print("[bounds] 玩家出生点 %s，在盒内 = %s" % [
			str(player.global_position.snappedf(0.01)), str(aabb.has_point(player.global_position))])
	quit(0)

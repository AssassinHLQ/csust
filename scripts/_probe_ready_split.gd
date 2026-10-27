extends SceneTree
## 量：game.tscn 的 `_ready` 到底被谁吃掉（companions / boss / sensei / shop）。
##   _tools/run_probe.sh res://scripts/_probe_ready_split.gd -- --splat=off
##
## 做法：实例化之后、**加入场景树之前**把某些子树摘掉 —— 它们没进树就不会跑 `_ready`，
## 于是这一轮的 add_child 只包含剩下的节点。

const Companion := preload("res://scripts/companion.gd")

var _game: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _measure(tag: String, drop: Array[String]) -> void:
	var ps := load("res://scenes/game.tscn") as PackedScene
	var game := ps.instantiate()
	var removed := 0
	for child in game.get_children():
		var path := String(child.get_script().resource_path) if child.get_script() != null else ""
		var keep_drop := false
		for d in drop:
			if child.name == d or (d == "@companion" and child is Companion) \
					or (d == "@shop" and path.ends_with("shop.gd")):
				keep_drop = true
		if keep_drop:
			game.remove_child(child)
			child.free()
			removed += 1
	var t0 := Time.get_ticks_usec()
	root.add_child(game)
	var t1 := Time.get_ticks_usec()
	print("[ready] %-34s %7.1f ms（摘掉 %d 个）" % [tag, (t1 - t0) / 1000.0, removed])
	game.queue_free()
	await process_frame
	await process_frame


func _run() -> void:
	_measure("全量", [])
	await _measure("去掉 7 名同伴", ["@companion"])
	await _measure("再去掉 BossPig + Sensei", ["@companion", "BossPig", "Sensei"])
	await _measure("再去掉 Shop（含芹香）", ["@companion", "BossPig", "Sensei", "Shop", "@shop"])
	quit(0)

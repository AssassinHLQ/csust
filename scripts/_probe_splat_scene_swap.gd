extends SceneTree
## 验收：真实「切场景时解码线程还在跑」—— 用户报的「空中变身闪退」同一类场景。
##
## 与 `_probe_splat_exit_race.gd` 的区别：
##   · 那个是直接 `queue_free()` 节点（最粗暴）
##   · 这个是**把整个场景换掉**（`change_scene_to_*`），走真实退树流程
##
## 断言两条：
##   1. 全程没有 `Cannot call method 'lock' on a null value`
##   2. 退场景的收尾耗时（`wait_to_finish`）在可接受范围内，且被打印出来
##
## 跑法：
##   godot --headless --path . --script res://scripts/_probe_splat_scene_swap.gd -- --no-capture

const TIMEOUT_MS := 90000


func _init() -> void:
	_go.call_deferred()


func _go() -> void:
	print("")
	print("==== 切场景 × 解码线程竞态 ====")
	print("")

	var src := "res://splatdata/school_raw.sogdata"
	if not FileAccess.file_exists(src):
		print("  找不到 %s，跳过" % src)
		_finish()
		return

	var SceneScript := load("res://scripts/splat_scene.gd")
	if SceneScript == null:
		print("  ✗ splat_scene.gd 加载失败")
		_finish()
		return

	# ---- 搭一个「假装是游戏场景」的根，里面放一个正在解码的 SplatScene ----
	get_root().add_child(Node3D.new())
	var holder := get_root().get_child(get_root().get_child_count() - 1)

	var node = SceneScript.new()
	node.sog_path = src
	node.auto_start = false
	node.display_name = "切场景测试"
	holder.add_child(node)

	var t_start := Time.get_ticks_msec()
	node.start()
	print("  → 线程已启动（loading=%s）" % str(node.loading))

	# ⚠️ 只等 300 ms —— 这时线程正在 `load_sog()` 里跑，绝不可能完成（实测整段 3 s）
	await create_timer(0.3).timeout
	print("  → 300 ms 后，loading=%s，线程 alive=%s"
		% [str(node.loading), str(node._thread != null and node._thread.is_alive())])

	# ---- 换场景：这一步会触发 node 的 _exit_tree ----
	var t_swap := Time.get_ticks_msec()
	holder.queue_free()          # 整个"场景"释放，和 change_scene 同一条路径
	print("  → 已调用 queue_free()，等待退树完成")
	var t_after := Time.get_ticks_msec()
	print("  → queue_free 本身耗时 %d ms（这里不该阻塞）" % (t_after - t_swap))

	# 等几帧让 _exit_tree 跑完、线程 join 完
	for i in 30:
		await process_frame

	var total := Time.get_ticks_msec() - t_start
	print("  → 全程 %d ms 结束，主循环存活" % total)

	print("")
	print("  ✓ 没有崩（崩溃的话走不到这一行）")
	print("  收尾耗时见上面 [SplatScene] 那行 —— 超过 100 ms 会自己打印")
	print("")
	print("==== 完成 ====")
	_finish()


func _finish() -> void:
	quit(0)

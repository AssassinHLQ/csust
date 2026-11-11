extends SceneTree
## 实测：校园走 GDGS（Compute）**全量**时，到底解出多少点、要多久、多少显存。
##
## 用户 2026-11-11：「校园改回 gdgs,raster 这么快,原来是把点全部砍掉了,也不要 lod 了」
## —— 换回 GDGS 之后必须证明「真的是全量 615 万点，不是又悄悄砍了」。
##
##   & <godot> --headless --path . --script res://scripts/_diag_campus_gdgs.gd
##
## ⚠️ headless 下没有 RenderingDevice，GDGS 的点数据仍会解码
##    （解码是纯数据搬运），所以点数/耗时/缓存命中都能测；
##    只有真实 GPU 上载和 fps 测不到，那边要真窗口。

const LEVEL := "res://scenes/next_level.tscn"
const EXPECT := 6144827      # `school_playable.sogdata` 裁剪后的点数（实测基准）


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 校园 GDGS 全量实测 ==========")
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[gdgs] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame

	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("★ Campus 不存在（被关了？检查 `next_level.gd` 的默认值）")
		quit(1)
		return
	print("Campus 就位｜sog_path = %s" % str(campus.get("sog_path")))
	print("cache_mode = %s｜start_delay = %.1f s｜crop = %s（max_scale %.2f）" % [
		str(campus.get("cache_mode")), float(campus.get("start_delay")),
		str(campus.get("crop_enabled")), float(campus.get("crop_max_scale"))])

	# 等到点云就绪（首次可能要 115 s；有缓存约 0.5 s）
	var t0 := Time.get_ticks_msec()
	var ready := false
	while Time.get_ticks_msec() - t0 < 240000:
		if campus.has_method("is_ready") and bool(campus.call("is_ready")):
			ready = true
			break
		await process_frame
	var ms := Time.get_ticks_msec() - t0
	print("")
	print("就绪 = %s｜耗时 %d ms（%.1f s）" % [str(ready), ms, float(ms) / 1000.0])

	# 点数：从 `splat_node` 的 gaussian 资源上读
	var node = campus.get("splat_node")
	if node == null:
		print("★ splat_node 还没建（`start_delay` 要 8 s，本探针只等了 %.1f s）"
			% (float(ms) / 1000.0))
		# 再多等一会儿
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 200000 and node == null:
			node = campus.get("splat_node")
			await process_frame
		print("  补等到 splat_node = %s" % str(node != null))
	if node != null:
		var res = node.get("gaussian")
		if res != null:
			var n := int(res.get("point_count"))
			var blob: PackedByteArray = res.get("point_data_byte")
			print("")
			print("★ 解出点数 = %d（期望 %d，差 %d）" % [n, EXPECT, EXPECT - n])
			print("  数据体积 = %.1f MB（240 B/点）" % (float(blob.size()) / 1048576.0))
			print("  与期望一致 = %s%s" % [
				str(n == EXPECT),
				"" if n == EXPECT else "   ← 少了说明被砍点！"])
		else:
			print("★ gaussian 资源为空")

	print("")
	print("静态视角下的显存估算（仅供参考，真实值要看真窗口）：")
	print("  point_data_byte  %.2f GB" % (float(EXPECT) * 240.0 / 1073741824.0))
	quit(0)

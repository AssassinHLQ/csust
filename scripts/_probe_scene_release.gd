extends SceneTree
## 验：切换场景时，**上一场景的 GPU 缓冲有没有当帧还回去**（2026-11-07 用户：
## 「进入第二场景不释放第一场景的显存」）。
##
##   _tools/run_shot.sh res://scripts/_probe_scene_release.gd
##
## 走的是**真实路径**：`SceneFlow.switch_scene()`（不是自己手写 swap），因为它里面
## 多了两步 —— 旧场景 free 之后、新场景 load 之前，调
## `gaussian_backend_selector.release_gpu()`（GDGS）和
## `campus_ggs.release_gpu_for_scene_change()`（GGS）。
##
## 判据：
##   ① 「旧场景已释放」那一行的**缓冲**，要明显低于「切换前」那一行
##      （修之前：1306 → 1285，几乎不动；修之后应该掉掉几百 MB 以上）；
##   ② 到了第二场景，泼溅 / 校园还能正常显示（`is_ready()` 为真、GGS 有 rasterizer），
##      说明 `request_rearm()` 的整份重注入没把新场景弄坏；
##   ③ 全程没有 `Attempted to free invalid ID` / `is not a valid texture` 之类的 ERROR。

const FIRST := "res://scenes/game.tscn"
const SECOND := "res://scenes/next_level.tscn"


func _initialize() -> void:
	var t := create_timer(300.0, true)
	t.timeout.connect(func():
		print("[rel] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	# 真窗口才有显存数字；headless 下 Performance 这几个值恒为 0
	if DisplayServer.get_name() == "headless":
		print("[rel] headless：显存监测恒为 0，本探针需要真窗口")
		quit(2)
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	root.size = Vector2i(1280, 720)

	# ── 第一场景：等画室609 泼溅就位（缓存命中 2~4 s） ──
	var first := (load(FIRST) as PackedScene).instantiate()
	root.add_child(first)
	current_scene = first
	var room := first.get_node_or_null("Room609")
	for _i in 900:
		await process_frame
		if room != null and bool(room.call("is_ready")):
			break
	_report("① 第一场景（画室609 就位）")
	# 打印两份场景各自的节点，确认 GGS 属于谁
	print("[rel]   第一场景子树：%s" % _names(first))
	print("[rel]   autoload：%s" % _names(root))

	# ── 走真实切换路径 ──
	var flow := load("res://scripts/scene_flow.gd")
	flow.switch_scene(SECOND, "", "probe")

	# switch_scene 自己会打 SceneFlow 的日志，这里只等它跑完
	for _i in 1800:
		await process_frame
		if not bool(flow.switching):
			break
	_report("② 第二场景（切换完成）")
	print("[rel]   第二场景子树：%s" % _names(current_scene))
	print("[rel]   autoload：%s" % _names(root))

	# 第二场景的泼溅 / 校园是否还能显示
	var second := current_scene
	var campus := second.get_node_or_null("CampusGGS") if second != null else null
	var gdgs_campus := second.get_node_or_null("Campus") if second != null else null
	print("[rel]   第二场景：CampusGGS=%s（rasterizer=%s、粗层=%s）｜Campus( GDGS )=%s" % [
		"有" if campus != null else "没有",
		"-" if campus == null else str(campus.get("rasterizer") != null),
		"-" if campus == null else str(campus.get("coarse_rasterizer") != null),
		"有" if gdgs_campus != null else "没有"])
	if campus != null and campus.has_method("debug_state"):
		print("[rel]   campus_ggs 内部状态：%s" % str(campus.call("debug_state")))
	if campus != null:
		var ggs_ok: bool = campus.get("rasterizer") != null or campus.get("coarse_rasterizer") != null
		print("[rel]   校园 GGS 仍可用：%s" % str(ggs_ok))

	# ⚠️ 玩家出生在**楼里**（`Campus` 的 `hide_inside_aabb` = (-17,-3,-11) 33×19×25），
	#    而 `campus_ggs.gd::_process` 的第一条分支就是「在楼里 ⇒ 藏校园 + 释放光栅器」——
	#    这是**设计**，不是 bug。要验「切场景后校园能重建」，必须把玩家挪出楼。
	var body := second.get_node_or_null("Player") as Node3D
	if body != null:
		body.global_position = Vector3(0.0, 0.2, 18.0)
		print("[rel]   把玩家挪出楼：%s" % str(body.global_position))

	# 等校园那两块真正上传完，再看一次显存（确认没被 rearm 弄成「永远不上传」）
	for _i in 1200:
		await process_frame
		if campus == null:
			break
		var fine = campus.get("rasterizer")
		var coarse = campus.get("coarse_rasterizer")
		var fine_ok: bool = fine != null and bool(fine.get("is_loaded"))
		var coarse_ok: bool = coarse != null and bool(coarse.get("is_loaded"))
		if fine_ok or coarse_ok:
			break
	_report("③ 第二场景（校园上传完）")
	if campus != null and campus.has_method("debug_state"):
		print("[rel]   ③ 时的 campus_ggs 状态：%s" % str(campus.call("debug_state")))

	print("[rel] 判据：② 的「缓冲」应明显低于 ①；③ 应能画出来（rasterizer 已加载）。")
	quit(0)


func _report(tag: String) -> void:
	var vram := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	var tex := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0
	var buf := float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0
	print("[rel] %-24s 总 %7.0f｜纹理 %7.0f｜缓冲 %7.0f MiB" % [tag, vram, tex, buf])


## 子树里直接子节点的名字（只看一层，够判断「谁挂在谁下面」）
func _names(n: Node) -> String:
	if n == null:
		return "（空）"
	var out: Array[String] = []
	for c in n.get_children():
		out.append(String(c.name))
	return "、".join(out) if not out.is_empty() else "（无）"

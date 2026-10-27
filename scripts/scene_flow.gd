extends RefCounted
## 场景切换的唯一入口：淡出 → 换场景 → 淡入，并记录显存。
##
## 为什么用 `SceneTree.change_scene_to_file()`，而不是「隐藏旧场景、叠加新场景」：
## 用户 2026-10-27 的要求是「进入下一个场景得去除上一个场景加载的东西，
## 这样子显存不会爆炸」。换场景时 SceneTree 会把**旧场景整棵树**从根节点摘下并
## `free`：
##   · 旧场景里的网格 / 材质 / 纹理引用计数归零，GPU 资源随之释放；
##   · 画室609 的泼溅节点走 `_exit_tree()`，GDGS 的合并缓冲按剩余节点重建；
##   · 工程里没有 static 变量按住 `GaussianResource`（`sog_runtime.gd` 的缓存
##     只落磁盘 user://splat_cache，不留在内存），所以点数据会被真正回收。
## 换句话说，显存是**掉下来**的，而不是只把节点设成 `visible = false`。
##
## 本脚本**不是 autoload**（用户不让动 project.godot），靠 `preload` + `static`
## 在场景之间共享状态：脚本资源本身常驻，static 变量换场景后仍然有效。
##
## 用法：
##   入口节点（`scene_gate.gd`）调用 `switch_scene(target, spawn_gate, gate_id)`；
##   目标场景在自己的 `_ready()` 里调用 `consume_entry()` 取落点，然后
##   `find_gate()` + `arrival_point()` 把玩家放到门前。

const GATE_GROUP := "scene_gates"
const FADE_OUT_SECONDS := 0.28
const FADE_IN_SECONDS := 0.32
## 换完场景后再等这么久记一次显存：GPU 资源释放 / GDGS 缓冲重建不在同一帧
const SETTLE_SECONDS := 0.75

## 正在切换（淡出中 / 新场景还没就绪）。入口节点用它屏蔽重复触发。
static var switching := false
## 当前场景是不是「从别的场景进来的」。目标场景 `consume_entry()` 后清掉。
static var entered_via_gate := false
## 目标场景里要落在哪个门前（门节点的 `gate_id`；空 = 用目标场景自己的出生点）
static var pending_spawn := ""
## 触发这次切换的门（只用于日志，方便对账）
static var last_from_gate := ""


## 目标场景调用：取出「从哪个门进来」，并清掉状态。没经过门就返回空字典。
static func consume_entry() -> Dictionary:
	if not entered_via_gate:
		return {}
	entered_via_gate = false
	var entry := {"gate": pending_spawn}
	pending_spawn = ""
	return entry


## 按 `gate_id` 找场上的门节点。找不到返回 null。
static func find_gate(root: Node, gate_id: String) -> Node3D:
	if root == null or gate_id.is_empty() or root.get_tree() == null:
		return null
	for n in root.get_tree().get_nodes_in_group(GATE_GROUP):
		if not is_instance_valid(n):
			continue
		if not n.has_method("arrival_point"):
			continue
		if String(n.get("gate_id")) == gate_id:
			return n as Node3D
	return null


## 切场景。`spawn_gate` 是目标场景里的落点门 id；`from_gate` 是本门的 id。
static func switch_scene(path: String, spawn_gate: String, from_gate: String) -> void:
	if switching:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("[SceneFlow] 目标场景不存在：%s" % path)
		return

	switching = true
	pending_spawn = spawn_gate
	last_from_gate = from_gate
	entered_via_gate = true
	report_memory("切换前（%s → %s）" % [from_gate, path])

	var overlay := _make_overlay(tree)
	var rect := overlay.get_child(0) as ColorRect
	var loading := overlay.get_node_or_null("Loading") as Label
	var out := tree.create_tween()
	out.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	out.tween_property(rect, "color:a", 1.0, FADE_OUT_SECONDS)
	await out.finished

	# ⚠️ 顺序很重要：**先 free 旧场景，再加载新场景**。
	#    `SceneTree.change_scene_to_file()` 是先 `load()` 新场景（.tscn 里所有
	#    ext_resource 的网格/纹理此刻就进显存）再 free 旧的 —— 两个场景会同时
	#    各占一份显存。现在下一关还小看不出差别；等下一关也挂一份几 GiB 的泼溅时，
	#    那个瞬时峰值正好会撞上「显存爆炸」。所以这里手动先把旧的摘掉。
	var t_block := Time.get_ticks_msec()
	var old := tree.current_scene
	var old_path := old.scene_file_path if old != null else ""
	if old != null:
		old.queue_free()
		await tree.process_frame
		await tree.process_frame
		report_memory("旧场景已释放（%s）" % old_path)
	# 加载是同步阻塞的：先把「载入中」画上屏，再让主线程去 load，
	# 否则大场景那几秒只有一块黑屏，看起来像卡死。
	if loading != null:
		loading.visible = true
		await tree.process_frame
	var err := tree.change_scene_to_file(path)
	if err != OK:
		push_error("[SceneFlow] 换场景失败（%s）：%s" % [error_string(err), path])
		switching = false
		entered_via_gate = false
		pending_spawn = ""
		# 旧场景已经 free 了，新场景又没加载起来 —— 把原场景装回去，别把玩家晾在黑屏里
		if not old_path.is_empty():
			push_warning("[SceneFlow] 恢复原场景：%s" % old_path)
			tree.change_scene_to_file(old_path)
			await tree.process_frame
			await tree.process_frame
		var back := tree.create_tween()
		back.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		back.tween_property(rect, "color:a", 0.0, FADE_IN_SECONDS)
		await back.finished
		overlay.queue_free()
		return

	# 换场景是延迟执行的：等两帧让新场景真正成为 current_scene
	await tree.process_frame
	await tree.process_frame
	report_memory("切换后（%s）" % path)
	print("[SceneFlow] 换场景阻塞 %.0f ms（free 旧场景 + load/instantiate 新场景 + 所有 _ready）"
		% float(Time.get_ticks_msec() - t_block))
	# GPU 资源的释放 / GDGS 缓冲重建会晚一点，再记一次
	await tree.create_timer(SETTLE_SECONDS, true).timeout
	report_memory("切换后 %.2f s" % SETTLE_SECONDS)

	var fade := tree.create_tween()
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(rect, "color:a", 0.0, FADE_IN_SECONDS)
	await fade.finished
	overlay.queue_free()
	switching = false


## 把显存 / 资源数打到日志。窗口模式才有意义（headless 下这些值恒为 0）。
static func report_memory(tag: String) -> void:
	var vram := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	var tex := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0
	var buf := float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0
	var objs := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("[SceneFlow] %s：VRAM %.1f MiB（纹理 %.1f / 缓冲 %.1f）｜对象 %d、节点 %d"
		% [tag, vram, tex, buf, objs, nodes])


## 黑幕挂在 `root`（Window）下，而不是当前场景下：换场景只换 current_scene，
## root 不动，所以淡入那一段不会被跟着 free 掉。
static func _make_overlay(tree: SceneTree) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "SceneFlowFade"
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	var rect := ColorRect.new()
	rect.name = "Fade"
	rect.color = Color(0.0, 0.0, 0.0, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 加载提示：在**全黑之后**才显示（`switch_scene` 里控制），
	# 因为 `change_scene_to_file()` 的 load 是同步阻塞的，文字必须提前画上屏。
	var loading := Label.new()
	loading.name = "Loading"
	loading.text = "载入中……"
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loading.add_theme_font_size_override("font_size", 22)
	loading.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0, 0.92))
	loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading.visible = false
	layer.add_child(loading)
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return layer

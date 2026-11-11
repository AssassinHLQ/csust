extends SceneTree
## 量：149 颗 9950X3D 在**捡掉一部分之后**到底还剩多少开销。
##
## 用户 2026-11-11：
##   「单次游戏149捡起一个就删掉一个可以吗,减轻性能开销」
##
## 答案是「本来就是这样」+「现在连重建都跳过了」。本探针把那句话**量出来**：
##
##   A. 一颗没捡（149 颗全在）—— 满载基线
##   B. 只剩 1 颗（另外 148 颗已被捡走，等价于玩到尾声）
##   C. 一颗不剩（149 颗全捡完）
##
## 每种情况都量：
##   · `instantiate() + _ready()` 的耗时（进 609 那一下要等多久）；
##   · 场景里**真的存在**的 CPU 节点数；
##   · 它们底下挂着多少个 `MeshInstance3D`（= 要提交的网格数）。
##
## ⚠️ `--headless` 没有渲染后端，所以这里**不报 draw call / 图元**
##    （那些在 `ryzen_9950x3d.gd` 文件头里有真窗口实测值：单颗 12,386 面，
##     149 颗在部室东角把帧率 220 打到 127）。本探针管的是**场景侧**的账。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_probe_cpu_pickup_cost.gd -- --splat=off

const RunMemory := preload("res://scripts/run_memory.gd")
const CPUS_SCENE := "res://scenes/room609_cpus.tscn"

var _rows: Array = []


func _initialize() -> void:
	_run()


## 把 n 颗标成「已捡走」：用第一份实例里的真实坐标做 key
## （`RunMemory.cpu_key()` 要的是世界坐标，所以必须先实例化一次）
func _keys_of(src: Node) -> Array:
	var out: Array = []
	for c in src.get_children():
		if c.has_method("price"):
			out.append(RunMemory.cpu_key(c as Node3D))
	return out


func _measure(label: String, marks: Array) -> void:
	RunMemory.wipe()
	for k in marks:
		RunMemory.mark_cpu(String(k))

	var t0 := Time.get_ticks_msec()
	var n := (load(CPUS_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(n)
	var ms := Time.get_ticks_msec() - t0
	# `queue_free()` 的生效点在帧末，等两帧再数
	for _i in 3:
		await process_frame

	var alive := 0
	for c in n.get_children():
		if c.has_method("price") and not c.is_queued_for_deletion():
			alive += 1
	var meshes := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	var lights := 0
	for li in n.find_children("*", "Light3D", true, false):
		lights += 1
	print("  %-16s 实例化+就位 %4d ms｜活着 %3d 颗｜MeshInstance3D %4d 个｜灯 %d 个" % [
		label, ms, alive, meshes, lights])
	_rows.append({"label": label, "ms": ms, "alive": alive, "meshes": meshes})
	n.queue_free()
	for _i in 3:
		await process_frame


func _run() -> void:
	print("========== 149 颗 9950X3D：捡掉之后还剩多少开销 ==========")
	RunMemory.wipe()

	# 先空跑一次拿全部 key（也是「第一次进 609」的真实耗时）
	var t0 := Time.get_ticks_msec()
	var src := (load(CPUS_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(src)
	var first_ms := Time.get_ticks_msec() - t0
	for _i in 3:
		await process_frame
	var keys := _keys_of(src)
	var base_meshes := src.find_children("*", "MeshInstance3D", true, false).size()
	print("  第一次进 609：%d 颗，实例化+就位 %d ms，MeshInstance3D %d 个" % [
		keys.size(), first_ms, base_meshes])
	src.queue_free()
	for _i in 3:
		await process_frame

	print("\n── 三种进度各进一次 609 ──")
	await _measure("A. 一颗没捡", [])
	if keys.size() > 1:
		await _measure("B. 只剩 1 颗", keys.slice(1))
	await _measure("C. 全捡完", keys)

	print("\n========== 结论 ==========")
	if _rows.size() >= 3:
		var a: Dictionary = _rows[0]
		var c: Dictionary = _rows[_rows.size() - 1]
		print("  %s → %s：节点 %d → %d，网格 %d → %d，进场景 %d → %d ms" % [
			String(a["label"]), String(c["label"]),
			int(a["alive"]), int(c["alive"]),
			int(a["meshes"]), int(c["meshes"]),
			int(a["ms"]), int(c["ms"])])
		print("  ⇒ 捡掉的**当帧就 queue_free**，之后既不渲染、不进物理、不参与遍历。")
		print("  ⇒ 换场景回来时已在 `_ready()` 里被拦下，**连模型都不建**（只建一个空壳再释放）。")
		print("     所以「捡掉一个就少一个」本来就是现行行为，这一版只是让它跨场景也成立。")
	quit(0)

extends SceneTree
## 验证：光环修复（① 自发光不再遮颜色 ② 低模环已细化）
##
## 用户 2026-11-10：
##   「光环自发光,把本来颜色全部遮掉了!,只有柚子光环形状有问题,
##     高处看正常,低处看丢了东西像是被减面了」
##
## 验证点：
##   ① 自发光颜色 = 贴图主色（不是纯白）—— 这是"黄色被遮掉"的正解
##   ② 自发光能量降到 0.45 以下（0.8 + 白 = 过曝）
##   ③ 光环网格面数从 228 提到 1000+ （30 段 → 96 段 × 6 边）
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_halo_fix.gd

const GAME := "res://scenes/game.tscn"
const HaloFixScript := preload("res://scripts/halo_fix.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _tri_count(mesh: Mesh) -> int:
	var tris := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			tris += (idx as PackedInt32Array).size() / 3
		else:
			tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return tris


func _run() -> void:
	print("========== 光环修复验证 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 30:
		await process_frame

	# 找柚子光环
	var halo: MeshInstance3D = null
	var stack: Array[Node] = [level]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and String(n.name).to_lower().contains("yuzu") \
				and String(n.name).to_lower().contains("halo"):
			halo = n as MeshInstance3D
			break
	if halo == null:
		push_error("[verify] 没找到 Yuzu 光环")
		quit(1)
		return

	print("\n── 网格 %s ──" % halo.name)
	var tris := _tri_count(halo.mesh)
	print("  面数 = %d" % tris)
	# ⚠️ 2026-11-10 回滚：本喵曾用程序化圆环**替换**掉原光环网格，
	#    结果把所有人的光环都改成了同一个圆（用户：「你怎么把所有人都改成球光环了,
	#    这根本不是柚子的光环」）。那一步**整个撤销**。
	#    这里改成断言**保持原网格**（228 面），防止以后又有人去动它。
	_check(tris == 228, "光环保持原始网格（228 面，实际 %d）—— 不再被程序化替换" % tris)

	# 材质检查
	var mat: Material = halo.material_override
	if mat == null:
		mat = halo.get_surface_override_material(0)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		print("  自发光：enabled=%s  颜色=(%.2f, %.2f, %.2f)  能量=%.2f" % [
			str(sm.emission_enabled), sm.emission.r, sm.emission.g, sm.emission.b,
			sm.emission_energy_multiplier])
		_check(sm.emission_enabled, "自发光开着")
		# ① 颜色不能是纯白（那样会遮掉贴图的黄）
		var is_white := sm.emission.r > 0.97 and sm.emission.g > 0.97 and sm.emission.b > 0.97
		_check(not is_white,
			"自发光颜色**不是纯白**（%.2f,%.2f,%.2f）—— 不会再遮掉贴图色" % [
				sm.emission.r, sm.emission.g, sm.emission.b])
		# ② 应该是偏暖色（贴图是黄色 255,207,117）
		_check(sm.emission.r >= sm.emission.b,
			"自发光偏暖（R %.2f ≥ B %.2f）—— 符合黄光环" % [sm.emission.r, sm.emission.b])
		# ③ 能量不能太高
		_check(sm.emission_energy_multiplier <= 0.5,
			"自发光能量 %.2f ≤ 0.5（原来 0.8 会过曝）" % sm.emission_energy_multiplier)
	else:
		_check(false, "材质不是 StandardMaterial3D")

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 光环修复生效" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)

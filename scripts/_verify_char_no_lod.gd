extends SceneTree
## 验证「角色不再受 LOD 影响」这件事本身，以及改完之后模型还能不能正常加载。
##
##   & <godot> --headless --path . --script res://scripts/_verify_char_no_lod.gd
##
## 查两件事：
##   ① 19 个角色模型的 `.glb.import` 里 `meshes/generate_lods=false`
##      —— 这是**结构性保证**：没有 LOD1/LOD2 数据，引擎就没有东西可切，
##      不管全局 `mesh_lod_threshold`（存档里是 8.0）设多大都不受影响。
##   ② 每个模型仍能 load + 实例化 + 数出网格 —— 证明重新导入没把资源弄坏。
##
## 运行时的图元数证据在 `_probe_char_lod.gd`（要真窗口）：
##   柚子 dist=15：改前 px=1.0 → 6139 图元、px=8.0 → 1789；改后两者都是 10352。

## 角色模型清单（玩家各形态 / 同伴 / NPC / Boss 恐龙）
const CHARS := [
	"res://models/Arisu_Battle.glb",
	"res://models/Arisu_Battle_Carrier.glb",
	"res://models/Arisu_Battle_Scenario.glb",
	"res://models/Arisu_ext.glb",
	"res://models/Arisu_Maid.glb",
	"res://models/companions/Kei.glb",
	"res://models/companions/Kei_ext.glb",
	"res://models/companions/Koyuki.glb",
	"res://models/companions/Midori.glb",
	"res://models/companions/Mika.glb",
	"res://models/companions/Momoi.glb",
	"res://models/companions/Noa.glb",
	"res://models/companions/Yuuka.glb",
	"res://models/companions/Yuzu.glb",
	"res://models/npc/sensei.glb",
	"res://models/npc/serika/serika.glb",
	"res://models/npc/sora/sora.glb",
	"res://models/boss/trex_yuuka_rigged.glb",
]
## 本来就已经是 false 的（改造前就是），一并核对，别被改回去
const ALREADY := ["res://models/Arisu.glb"]
## 骨架专用：`RunFire.glb` 是 Blender 拼出来的一条整身跑打动作，**0 网格**
## （见 README 第 2728 行、`anim_driver.gd` 顶部说明）。它没有网格，
## 所以 LOD 对它本来就没意义 —— 这里显式断言「0 网格」，免得以后有人
## 以为漏了它。
const SKELETON_ONLY := ["res://models/RunFire.glb"]

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [what, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [what, ("  " + detail) if detail != "" else ""])


func _lod_flag(glb: String) -> String:
	var t := FileAccess.get_file_as_string(glb + ".import")
	if t.is_empty():
		return "(读不到)"
	var m := RegEx.new()
	m.compile("meshes/generate_lods=(\\w+)")
	var r := m.search(t)
	return r.get_string(1) if r != null else "(没有这一项)"


func _count_meshes(n: Node, acc: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		acc.append([mi.name, mi.mesh.get_surface_count() if mi.mesh != null else 0])
	for c in n.get_children():
		_count_meshes(c, acc)


func _run() -> void:
	print("========== 角色 LOD 关闭验证 ==========")
	print("[1] .import 里的 generate_lods（必须全是 false）")
	var bad: PackedStringArray = PackedStringArray()
	for g in CHARS + ALREADY + SKELETON_ONLY:
		var v := _lod_flag(String(g))
		if v != "false":
			bad.append("%s → %s" % [String(g).get_file(), v])
	_check(bad.is_empty(), "%d 个角色模型全部 generate_lods=false"
		% (CHARS.size() + ALREADY.size() + SKELETON_ONLY.size()),
		("异常：" + ", ".join(bad)) if not bad.is_empty() else "")

	print("[2] 模型还能不能正常加载（重新导入没弄坏）")
	for g in CHARS + ALREADY:
		var ps := load(String(g)) as PackedScene
		if ps == null:
			_check(false, "加载 %s" % String(g).get_file())
			continue
		var inst := ps.instantiate()
		var acc: Array = []
		_count_meshes(inst, acc)
		var surfaces := 0
		for a in acc:
			surfaces += int(a[1])
		_check(acc.size() > 0 and surfaces > 0,
			"%-26s 网格 %3d 个 / 面 %4d" % [String(g).get_file(), acc.size(), surfaces])
		inst.free()
	for g in SKELETON_ONLY:
		var ps2 := load(String(g)) as PackedScene
		if ps2 == null:
			_check(false, "加载 %s" % String(g).get_file())
			continue
		var inst2 := ps2.instantiate()
		var acc2: Array = []
		_count_meshes(inst2, acc2)
		_check(acc2.size() == 0,
			"%-26s 骨架专用，0 网格（网格 %d 个 —— 本来就该是 0）"
			% [String(g).get_file(), acc2.size()])
		inst2.free()

	print("[3] 存档里的全局 LOD 阈值（只再影响非角色模型了）")
	var path := "user://settings.cfg"
	if FileAccess.file_exists(path):
		var txt := FileAccess.get_file_as_string(path)
		var m := RegEx.new()
		m.compile("lod_threshold_px=([0-9.]+)")
		var r := m.search(txt)
		if r != null:
			print("     当前 lod_threshold_px = %s（默认 1.0，滑条上限 8.0）" % r.get_string(1))
		else:
			print("     存档里没有这一项（用默认 1.0）")
	else:
		print("     没有存档，用默认 1.0")

	print()
	print("========== %d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

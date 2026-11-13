extends SceneTree
## 自检：恐怖优香换眼贴图 —— 只动它，普通优香不变。
##
##   Godot --headless --script res://scripts/_probe_yuuka_horror_eye.gd
##
## 判据：
##   ① 恐怖 boss 的「Yuuka_Original_EyeMouth」表面 → `Yuuka_Horror_EyeMouth.png`
##   ② 恐怖 boss 的 7 张口型面 → 仍是 `Yuuka_Character_Mouth_*`（不能被误换）
##   ③ 直接实例化 Yuuka.glb（= 同伴/剧情版）→ 眼嘴仍是原图 `Yuuka_Yuuka_Original_EyeMouth.png`

const HORROR_TEX := "res://models/companions/Yuuka_Horror_EyeMouth.png"
const ORIG_TEX := "res://models/companions/Yuuka_Yuuka_Original_EyeMouth.png"
const BOSS_SCRIPT := "res://scripts/yuuka_horror_boss.gd"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# ── ③ 原始模型（同伴版）──
	var ps := load("res://models/companions/Yuuka.glb") as PackedScene
	var plain := ps.instantiate() as Node3D
	root.add_child(plain)
	await process_frame
	var plain_eye := _eye_tex_of(plain)
	print("[eye] 同伴优香 眼嘴贴图 = %s" % plain_eye)
	_check(plain_eye == ORIG_TEX, "同伴优香仍是原图")

	# ── ①② 恐怖 boss ──
	var bs := load(BOSS_SCRIPT) as GDScript
	if bs == null:
		print("[eye] ✗ 脚本解析失败（另一个会话可能还没写完）")
		quit(1)
		return
	var boss := bs.new() as Node3D
	root.add_child(boss)
	await process_frame
	var model := boss.get("model") as Node3D
	if model == null:
		print("[eye] ✗ boss 没有 model")
		quit(1)
		return
	var h_eye := _eye_tex_of(model)
	print("[eye] 恐怖 boss 眼嘴贴图 = %s" % h_eye)
	_check(h_eye == HORROR_TEX, "恐怖 boss 换成新眼贴图")

	var mouths := 0
	for n in model.find_children("Mouth_*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		var om := m.get_surface_override_material(0) as ShaderMaterial
		var t := om.get_shader_parameter("albedo_tex") as Texture2D if om != null else null
		var p := t.resource_path if t != null else "<无>"
		if p.contains("Yuuka_Character_Mouth"):
			mouths += 1
	_check(mouths == 7, "7 张口型贴图没被误换（实际 %d）" % mouths)

	# ── 眼睛自发光：只能有 1 个面开着 ──
	var lit := 0
	var lit_val := 0.0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var om := m.get_surface_override_material(s) as ShaderMaterial
			if om == null:
				continue
			var raw = om.get_shader_parameter("eye_emit")   # 没设过 → null
			var e := 0.0 if raw == null else float(raw)
			if e > 0.01:
				lit += 1
				lit_val = e
	_check(lit == 1, "只有 1 个表面开眼睛自发光（实际 %d 个）" % lit)
	_check(absf(lit_val - 2.6) < 0.01, "自发光强度 = %.2f（应 2.6）" % lit_val)

	print("\n[eye] %s（失败 %d 项）" % ["★ 全部通过" if _fail == 0 else "有失败", _fail])
	quit(0 if _fail == 0 else 2)


## 取「Yuuka_Original_EyeMouth」那一面现在的贴图路径（override 优先）。
func _eye_tex_of(n: Node3D) -> String:
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s) as StandardMaterial3D
			if src == null:
				continue
			if src.albedo_texture == null or not src.albedo_texture.resource_path.contains("EyeMouth"):
				continue
			if src.albedo_texture.resource_path.contains("Character_Mouth"):
				continue
			var om := m.get_surface_override_material(s) as ShaderMaterial
			if om != null:
				var t := om.get_shader_parameter("albedo_tex") as Texture2D
				return t.resource_path if t != null else "<无>"
			return src.albedo_texture.resource_path
	return "<未找到>"


func _check(ok: bool, label: String) -> void:
	print("  %s %s" % ["✔" if ok else "✘", label])
	if not ok:
		_fail += 1

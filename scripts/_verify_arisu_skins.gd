extends SceneTree
## headless 清点爱丽丝的 5 套模型：**不渲染、不开窗口**。
##
##   _tools/run_probe.sh res://scripts/_verify_arisu_skins.gd
##
## 查什么（决定能不能换皮肤）：
##   1. glb 能不能被 Godot 正常导入、实例化；
##   2. 网格根节点名（换皮肤要改 `root_node` / 面部修复那几处按名字找的地方）；
##   3. 关键骨在不在（手 `Bip001 L/R Hand`、头、眼）—— 挂武器、看朝向都靠它们；
##   4. 动作名（待机 / 走 / 跑 / 攻击）在不同皮肤里叫什么。

const SKINS := [
	{"key": "normal", "path": "res://models/Arisu.glb"},
	{"key": "maid", "path": "res://models/Arisu_Maid.glb"},
	{"key": "battle", "path": "res://models/Arisu_Battle.glb"},
	{"key": "battle_carrier", "path": "res://models/Arisu_Battle_Carrier.glb"},
	{"key": "battle_scenario", "path": "res://models/Arisu_Battle_Scenario.glb"},
]
const KEY_BONES := [
	"Bip001 L Hand", "Bip001 R Hand", "Bip001 Head", "Bip001 eye_L", "Bip001 eye_R",
	"Bip001 Pelvis", "Bip001 Spine",
]
## 游戏里实际会去点的动作（见 anim_driver.gd / player.gd）
const WANT_ANIMS := [
	"Normal_Idle", "Normal_Walk", "Normal_Run", "Normal_Attack_Ing",
	"Cafe_Idle", "Cafe_Walk", "Move_Ing", "Idle", "Walk", "Run",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[skin] 清点 %d 套模型" % SKINS.size())
	for s in SKINS:
		var skin: Dictionary = s
		var path := String(skin["path"])
		if not ResourceLoader.exists(path):
			print("[skin] %-16s !! 资源不存在：%s" % [String(skin["key"]), path])
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			print("[skin] %-16s !! 载入失败（导入有问题？）" % String(skin["key"]))
			continue
		var root := ps.instantiate()
		var meshes: Array[String] = []
		var skels: Array[String] = []
		var bones := {}
		var anims := {}
		_collect(root, meshes, skels, bones, anims)
		var missing: Array[String] = []
		for b in KEY_BONES:
			if not bones.has(b):
				missing.append(b)
		var have: Array[String] = []
		for a in WANT_ANIMS:
			if anims.has(a):
				have.append(a)
		print("[skin] ── %s（%s）" % [String(skin["key"]), path.get_file()])
		print("[skin]    网格根：%s" % str(meshes))
		print("[skin]    骨架 %d 个｜骨 %d 根｜动作 %d 条" % [
			skels.size(), bones.size(), anims.size()])
		print("[skin]    关键骨：%s" % ("全在" if missing.is_empty() else "缺 " + str(missing)))
		print("[skin]    命中动作：%s" % (str(have) if not have.is_empty() else "（一个都没有）"))
		var names := anims.keys()
		names.sort()
		print("[skin]    动作前 10：%s" % str(names.slice(0, 10)))
		root.free()
	quit(0)


func _collect(n: Node, meshes: Array[String], skels: Array[String],
		bones: Dictionary, anims: Dictionary) -> void:
	if n is MeshInstance3D and n.get_parent() is Node3D:
		# 只记「挂在 Skeleton3D 之外」的网格名（= 角色身上的件：身体/武器/光环）
		var p := n.get_parent()
		if not (p is Skeleton3D):
			meshes.append(n.name)
	if n is Skeleton3D:
		skels.append(n.name)
		for i in n.get_bone_count():
			bones[n.get_bone_name(i)] = true
	if n is AnimationPlayer:
		for a in n.get_animation_list():
			anims[a] = true
	for c in n.get_children():
		_collect(c, meshes, skels, bones, anims)

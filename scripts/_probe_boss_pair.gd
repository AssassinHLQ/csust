extends SceneTree
## 一次性探针：摸清「霍德」与「佩洛洛斯拉」两个 FBX 的结构 ——
## 材质名、网格名、骨架骨数、动画 clip 名、世界包围盒。
## 这些是 `hod_boss.gd` / `peroro_boss.gd` 里 `texture_map` 与 `height` 的依据。
##
## 用法：
##   godot --headless --path <repo> --script res://scripts/_probe_boss_pair.gd

const PATHS := [
	"res://models/boss_hod/HOD_Original.fbx",
	"res://models/boss_perorozilla/Perorozilla_Original.fbx",
]


func _initialize() -> void:
	for p in PATHS:
		_probe(p)
	quit(0)


func _probe(path: String) -> void:
	print("\n===== %s =====" % path)
	var res := load(path)
	print("  导入类型: %s" % (res.get_class() if res != null else "null"))
	if res == null:
		print("  ❌ 加载失败（还没 import？先跑 --headless --import）")
		return
	if not (res is PackedScene):
		print("  ⚠️ 不是 PackedScene：%s" % res.get_class())
		return
	var root := (res as PackedScene).instantiate()
	var meshes: Array[Node] = []
	var skels: Array[Node] = []
	var players: Array[Node] = []
	_collect(root, meshes, skels, players)

	print("  网格 %d 个 / 骨架 %d 副 / AnimationPlayer %d 个" % [
		meshes.size(), skels.size(), players.size()])
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var aabb := mi.get_aabb()
		var mats: Array[String] = []
		var am := mi.mesh as ArrayMesh
		if am != null:
			for s in am.get_surface_count():
				var mat := am.surface_get_material(s)
				if mat != null:
					mats.append("'%s'" % mat.resource_name)
				else:
					mats.append("(无材质)")
		print("    mesh '%s'  包围盒 size=%s  材质=%s" % [
			mi.name, str(aabb.size.snappedf(0.01)), ", ".join(mats)])
	for s in skels:
		var sk := s as Skeleton3D
		print("    skeleton '%s' 骨数=%d" % [sk.name, sk.get_bone_count()])
		var names: Array[String] = []
		for i in mini(sk.get_bone_count(), 12):
			names.append(sk.get_bone_name(i))
		print("      前几根: %s" % ", ".join(names))
	for p in players:
		var ap := p as AnimationPlayer
		var list := ap.get_animation_list()
		print("    anim '%s' clip=%d %s" % [ap.name, list.size(), str(list)])
		for n in list:
			var a := ap.get_animation(n)
			print("      · %s  时长 %.2fs  轨 %d 条" % [n, a.length, a.get_track_count()])

	# 世界包围盒（含蒙皮）
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.size.length() <= 0.0001:
			continue
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	print("  网格世界包围盒: size=%s  min=%s" % [
		str((hi - lo).snappedf(0.01)), str(lo.snappedf(0.01))])
	root.free()


func _collect(n: Node, meshes: Array[Node], skels: Array[Node],
		players: Array[Node]) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	elif n is Skeleton3D:
		skels.append(n)
	elif n is AnimationPlayer:
		players.append(n)
	for c in n.get_children():
		_collect(c, meshes, skels, players)

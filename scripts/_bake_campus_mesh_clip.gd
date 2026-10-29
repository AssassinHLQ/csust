extends SceneTree
## 把 collider-forge 的 Poisson 碰撞网格「剪掉贴地那一层」，只留 1 m 以上的墙/物体。
##   _tools/run_probe.sh res://scripts/_bake_campus_mesh_clip.gd -- --force
##
## 为什么：实测（_probe_campus_collision_fit.gd）这个网格的地面比点云地面
## 高/低 0.3~3 m 的柱子各占 28.8% / 37.5%，人走在路上会浮空或陷进去。
## 地面本来就有 CampusFloor 那块平板（校园拟合倾角只有 0.18°/0.05°，平的），
## 所以把网格里「最高顶点都不到 1 m」的三角形全删掉，留下沿墙往上走的那些，
## 既保住楼/树/围栏的碰撞，又让脚老老实实踩在平板上。
##
## 产物：scenes/campus_collision_mesh_upper.scn

const SRC := "res://scenes/campus_collision_mesh.scn"
const OUT := "res://scenes/campus_collision_mesh_upper.scn"
const CUT := 1.0     # 米：三角形最高顶点低于这个值就删

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var force := OS.get_cmdline_user_args().has("--force")
	if FileAccess.file_exists(OUT) and not force:
		print("[clip] %s 已存在；覆盖请加 -- --force" % OUT)
		quit(0)
		return
	var src := (load(SRC) as PackedScene).instantiate()
	var cs: CollisionShape3D = null
	for n in src.find_children("*", "CollisionShape3D", true, false):
		cs = n as CollisionShape3D
		break
	if cs == null or not (cs.shape is ConcavePolygonShape3D):
		print("[clip] 源场景里没有 ConcavePolygonShape3D")
		quit(1)
		return
	# 源场景的面已经是世界坐标，节点本身没有变换
	var xf := Transform3D.IDENTITY
	var faces: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
	var keep := PackedVector3Array()
	var dropped := 0
	var i := 0
	while i + 2 < faces.size():
		var a: Vector3 = xf * faces[i]
		var b: Vector3 = xf * faces[i + 1]
		var c: Vector3 = xf * faces[i + 2]
		var top := maxf(a.y, maxf(b.y, c.y))
		if top < CUT:
			dropped += 1
		else:
			keep.append(a); keep.append(b); keep.append(c)
		i += 3
	print("[clip] 原 %d 三角 → 留 %d，删地面 %d（%.1f%%）"
		% [faces.size() / 3, keep.size() / 3, dropped, 100.0 * dropped / maxi(faces.size() / 3, 1)])

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(keep)
	var body := StaticBody3D.new()
	body.name = "CampusCollisionMeshUpper"
	var ncs := CollisionShape3D.new()
	ncs.name = "Collision"
	ncs.shape = shape
	body.add_child(ncs)
	var root_node := Node3D.new()
	root_node.name = "CampusCollisionMeshUpper"
	root_node.add_child(body)
	_own(root_node, root_node)
	var ps := PackedScene.new()
	var err := ps.pack(root_node)
	if err != OK:
		print("[clip] pack 失败 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	print("[clip] %s ← %d 三角（%.1f KB）err=%d"
		% [OUT, keep.size() / 3,
			float(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(OUT)).size()) / 1024.0, err])
	quit(0)


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)

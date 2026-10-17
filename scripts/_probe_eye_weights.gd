extends SceneTree
## 探针：**眼周那一圈皮，蒙皮到哪根骨上**（按 bind 名字查，不用坐标猜）。
##
## 背景：骨骼 `eye_L_1/2`、`eye_R_1/2` 的旋转**幅度一样**，把左边按三种镜像公式
## 抄给右边，渲出来四格一模一样 —— 说明那块「半遮瞳孔的白皮」不归这俩骨管。
## 所以要查：**哪些顶点**带眼睛骨的权重、它们分别在什么位置、左右差多少。
##
## ⚠️ `ARRAY_BONES` 存的是 **skin 的 bind 下标**；这份 glb 上
##    `Skin.get_bind_bone()` 全部返回 -1（170 个 bind 没映射到骨），
##    所以必须改用 `get_bind_name()` 拿名字（这正是上一版探针查不出东西的原因）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_eye_weights.gd

const MODEL := "res://models/Arisu_ext.glb"
const BODY := "Aris_Original_Body_001"
const MIN_W := 0.2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	if sk == null:
		print("!! 没有 Skeleton3D")
		quit(1)
		return
	var body := _find_mesh(inst, BODY)
	if body == null:
		print("!! 没找到网格 %s" % BODY)
		quit(1)
		return
	print("[w] 网格 global = %s" % str(body.global_transform))
	print("[w] 骨架 global = %s" % str(sk.global_transform))
	print("[w] bind 数 = %d   bind0 名字 = %s   bind0 骨 = %d" % [
		body.skin.get_bind_count(), String(body.skin.get_bind_name(0)),
		body.skin.get_bind_bone(0)])

	# 每个骨名下挂的顶点（网格空间坐标）+ UV
	var per := {}
	var uvs := {}
	var m := body.mesh as ArrayMesh
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ts: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		if bs.is_empty() or ws.is_empty():
			continue
		var k_per := bs.size() / maxi(vs.size(), 1)
		for v in vs.size():
			for k in k_per:
				var idx := v * k_per + k
				if idx >= bs.size():
					break
				var w := ws[idx]
				if w < MIN_W:
					continue
				var bn := _bind_name(body.skin, bs[idx], sk)
				if not per.has(bn):
					per[bn] = []
					uvs[bn] = []
				per[bn].append(vs[v])
				if v < ts.size():
					uvs[bn].append(ts[v])

	print("\n[w] 带眼睛骨权重的顶点（网格空间，权重 ≥ %.1f）" % MIN_W)
	var names := per.keys()
	names.sort_custom(func(a, b): return _interesting(String(a)) and not _interesting(String(b)))
	for nm in names:
		if not _interesting(String(nm)):
			continue
		var pts: Array = per[nm]
		var box := AABB(pts[0], Vector3.ZERO)
		var c := Vector3.ZERO
		for p in pts:
			box = box.expand(p)
			c += p
		c /= float(pts.size())
		var q: Array = uvs.get(nm, [])
		var uc := Vector2.ZERO
		var ubox := Rect2(q[0], Vector2.ZERO) if not q.is_empty() else Rect2()
		for p in q:
			uc += p
			ubox = ubox.expand(p)
		uc /= float(maxi(q.size(), 1))
		print("  %-22s 顶点 %4d  质心 (%+.3f,%+.3f,%+.3f)  UV质心 (%.4f,%.4f)  UV矩形 %s" % [
			String(nm), pts.size(), c.x, c.y, c.z, uc.x, uc.y,
			str(ubox.size.snappedf(0.0001))])

	# 只看「左右成对」的质心差
	print("\n[w] 左右成对：质心差（右 − 左）")
	for nm in names:
		var s := String(nm)
		var other := _swap_lr(s)
		if other == s or not per.has(other):
			continue
		if not _interesting(s):
			continue
		var a := _centroid(per[s])
		var b := _centroid(per[other])
		if s.contains("_R") or s.contains("eyeR"):
			print("  %-22s vs %-22s  Δ=(%+.3f,%+.3f,%+.3f) m" % [
				s, other, a.x - b.x, a.y - b.y, a.z - b.z])
	quit(0)


func _interesting(n: String) -> bool:
	var l := n.to_lower()
	return l.contains("eye") or l.contains("lid")


func _swap_lr(s: String) -> String:
	if s.contains("_R"):
		return s.replace("_R", "_L")
	if s.contains("_L"):
		return s.replace("_L", "_R")
	if s.contains("eyeR"):
		return s.replace("eyeR", "eyeL")
	if s.contains("eyeL"):
		return s.replace("eyeL", "eyeR")
	return s


func _centroid(pts: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / float(maxi(pts.size(), 1))


## bind 下标 → 骨名。先试 `get_bind_name`，再退回 `get_bind_bone` + 骨名表。
func _bind_name(skin: Skin, bind: int, sk: Skeleton3D) -> String:
	var n := String(skin.get_bind_name(bind))
	if not n.is_empty():
		return n
	var b := skin.get_bind_bone(bind)
	if b >= 0 and b < sk.get_bone_count():
		return String(sk.get_bone_name(b))
	return "bind%d" % bind


func _find_mesh(n: Node, name_: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name) == name_:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh(c, name_)
		if r != null:
			return r
	return null


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null

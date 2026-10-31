extends SceneTree
## 第二关入口附近的一小片「解构主义」街区：4 栋、每栋 2 间房、每间一扇能推开的门。
##   _tools/run_probe.sh res://scripts/_bake_campus_deconstruct.gd            # 只打印
##   _tools/run_probe.sh res://scripts/_bake_campus_deconstruct.gd -- --write --force
##
## 和上一版（分散的小盒子）的区别：
##   · 集中在东门出来那一段主路两侧（z -95 ~ -150、x ±26），不是撒满校园；
##   · 形体是解构主义：上层体量互相错位、斜切、悬挑，斜向深色条带 + 红色强调；
##   · 一层是**真房间**：每栋 2 间、中间实墙隔开，每间在正面有自己的门洞；
##   · 每扇门挂 scripts/push_door.gd，玩家走近 2.3 m 就向外转开，走开自动关。
##
## 选址：在目标点附近按 2 m 找空地（1 m 高四周 0.6 m 无碰撞、地面平、门前 3 m 空）。

const LEVEL := "res://scenes/next_level.tscn"
const OUT := "res://scenes/campus_deconstruct.tscn"
const DOOR_SCRIPT := "res://scripts/push_door.gd"

## 门朝主路开：左侧 +90°（朝 +x），右侧 -90°（朝 -x）
const TARGETS := [
	[Vector3(-26, 0, -100), 90.0],
	[Vector3(26, 0, -104), -90.0],
	[Vector3(-30, 0, -142), 90.0],
	[Vector3(28, 0, -146), -90.0],
]

var _write := false
var _force := false

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--write":
			_write = true
		elif a == "--force":
			_force = true
	if _write and FileAccess.file_exists(OUT) and not _force:
		print("[dec] %s 已存在；覆盖请加 -- --force" % OUT)
		quit(0)
		return

	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var campus := level.get_node_or_null("Campus")
	if campus != null:
		campus.set("auto_start", false)
		campus.set_process(false)
	# 旧的 8 栋先摘掉，免得选址射线打到它们
	var old := level.get_node_or_null("CampusBuildings")
	if old != null:
		old.queue_free()
		await process_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state

	var spots: Array = []
	for t in TARGETS:
		var s := _find_clear(space, t[0], float(t[1]))
		if s.is_empty():
			print("[dec] %s 附近没找到空地，跳过" % str(t[0]))
		else:
			spots.append(s)
			print("[dec] %s → (%.0f, %.0f) 朝向 %.0f°"
				% [str(t[0]), s[0].x, s[0].z, s[2]])

	if not _write:
		level.free()
		quit(0)
		return

	var root_node := Node3D.new()
	root_node.name = "CampusDeconstruct"
	# 铺地：把这一片连成一个小广场（视觉，不挡路）
	_slab(root_node, Vector3(0, 0.02, -122), Vector3(74, 0.04, 84),
		_mat(Color(0.62, 0.60, 0.57), 0.85, 0.0), false)
	var i := 0
	for s in spots:
		i += 1
		root_node.add_child(_make_building(s[0], float(s[1]), float(s[2]), i))
	_own(root_node, root_node)
	var ps := PackedScene.new()
	var err := ps.pack(root_node)
	if err != OK:
		print("[dec] pack 失败 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	print("[dec] %s ← %d 栋，%d 节点，%.0f KB，err=%d"
		% [OUT, i, _count(root_node),
			float(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(OUT)).size()) / 1024.0, err])
	level.free()
	quit(0)


func _find_clear(space: PhysicsDirectSpaceState3D, around: Vector3, yaw: float) -> Array:
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	for r in [0.0, 3.0, 6.0, 9.0, 12.0, 15.0, 18.0, 22.0, 26.0, 30.0, 34.0, 38.0]:
		for k in 16:
			var ang := TAU * k / 16.0
			var c: Vector3 = around + Vector3(cos(ang), 0, sin(ang)) * r
			if absf(c.x) < 18.0:
				continue
			var g: float = _clear(space, q, c)
			if g > -900.0 and _doors_clear(space, q, Vector3(c.x, g, c.z), yaw):
				return [Vector3(c.x, g, c.z), g, yaw]
	return []


## 两个门洞外 3 m 到门里的直线必须通（否则门开在树里，进不去）
## 用和运行时完全一样的变换算门的位置，别手推矩阵（推错过一次）
func _doors_clear(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D,
		c: Vector3, yaw_deg: float) -> bool:
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), c)
	var out: Vector3 = xf.basis.z.normalized()
	for lx in [-3.5, 3.5]:
		var w: Vector3 = xf * Vector3(lx, 1.2, 4.0)
		q.from = w + out * 2.0
		q.to = w - out * 1.2
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func _clear(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D, c: Vector3) -> float:
	# 8.5 m 半径一圈 + 中心，1 m 高处不能有碰撞
	# 楼座里按 1.5 m 铺一遍点：树长在楼里也要筛掉（以前只查外圈，漏过）
	var pts := [Vector3.ZERO]
	for a in 8:
		var ang := TAU * a / 8.0
		pts.append(Vector3(cos(ang), 0, sin(ang)) * 7.0)
	var gx := -6.0
	while gx <= 6.0:
		var gz := -3.0
		while gz <= 3.0:
			pts.append(Vector3(gx, 0, gz))
			gz += 1.5
		gx += 1.5
	var hs: Array[float] = []
	for p in pts:
		for dir in [Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0, 0, 0.6), Vector3(0, 0, -0.6)]:
			q.from = Vector3(c.x + p.x, 1.0, c.z + p.z)
			q.to = q.from + dir
			if not space.intersect_ray(q).is_empty():
				return -999.0
		q.from = Vector3(c.x + p.x, 40.0, c.z + p.z)
		q.to = Vector3(c.x + p.x, -5.0, c.z + p.z)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			return -999.0
		hs.append((r["position"] as Vector3).y)
	var mn: float = hs[0]
	var mx: float = hs[0]
	for h in hs:
		mn = minf(mn, h)
		mx = maxf(mx, h)
	if mn < -0.6 or mx > 0.4 or (mx - mn) > 0.5:
		return -999.0
	return (mn + mx) * 0.5


# ───────────────────────── 造一栋 ─────────────────────────

func _make_building(pos: Vector3, ground: float, yaw_deg: float, idx: int) -> Node3D:
	var block := StaticBody3D.new()
	block.name = "Deconstruct%02d" % idx
	block.position = Vector3(pos.x, ground, pos.z)
	block.rotation_degrees.y = yaw_deg

	var concrete := _mat(Color(0.86, 0.84, 0.80), 0.92, 0.0)
	var dark := _mat(Color(0.10, 0.11, 0.12), 0.35, 0.55)
	var red := _mat(Color(0.52, 0.07, 0.05), 0.6, 0.0)

	var w := 14.0
	var d := 8.0
	var fh := 3.2
	var t := 0.25

	# 地坪 + 一层天花
	_slab(block, Vector3(0, 0.1, 0), Vector3(w + 0.4, 0.2, d + 0.4), concrete)
	_slab(block, Vector3(0, fh + 0.15, 0), Vector3(w, 0.3, d), concrete)

	# 后墙 / 两侧墙 / 中间隔墙（两间房各自独立）
	_slab(block, Vector3(0, fh * 0.5, -d * 0.5 + t * 0.5), Vector3(w, fh, t), concrete)
	_slab(block, Vector3(w * 0.5 - t * 0.5, fh * 0.5, 0), Vector3(t, fh, d), concrete)
	_slab(block, Vector3(-w * 0.5 + t * 0.5, fh * 0.5, 0), Vector3(t, fh, d), concrete)
	_slab(block, Vector3(0, fh * 0.5, 0), Vector3(t, fh, d), concrete)

	# 正面墙：两个 1.4×2.3 的门洞（x = ±3.5）
	var door_w := 1.4
	var door_h := 2.3
	var zf := d * 0.5 - t * 0.5
	var xs := [-3.5, 3.5]
	# 由左到右的实体段
	_seg(block, -w * 0.5, xs[0] - door_w * 0.5, zf, fh, t, concrete)
	_seg(block, xs[0] + door_w * 0.5, xs[1] - door_w * 0.5, zf, fh, t, concrete)
	_seg(block, xs[1] + door_w * 0.5, w * 0.5, zf, fh, t, concrete)
	# 门楣
	for dx in xs:
		_slab(block, Vector3(dx, door_h + (fh - door_h) * 0.5, zf),
			Vector3(door_w, fh - door_h, t), concrete)

	# 两扇推拉门
	for k in 2:
		var dx: float = xs[k]
		var hinge := Node3D.new()
		hinge.name = "Door%02d_%d" % [idx, k + 1]
		hinge.position = Vector3(dx - door_w * 0.5, 0, zf + 0.06)
		hinge.set_script(load(DOOR_SCRIPT))
		var body := StaticBody3D.new()
		body.name = "Panel"
		body.position = Vector3(door_w * 0.5, door_h * 0.5, 0)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(door_w, door_h, 0.08)
		cs.shape = sh
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(door_w, door_h, 0.08)
		mi.mesh = bm
		mi.material_override = dark
		body.add_child(mi)
		# 门把手
		var knob := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(0.08, 0.5, 0.08)
		knob.mesh = km
		knob.position = Vector3(door_w * 0.5 - 0.15, 0, 0.07)
		knob.material_override = red
		body.add_child(knob)
		hinge.add_child(body)
		block.add_child(hinge)

	# 门洞前的红色雨棚（解构主义那种斜插的板）
	_slab(block, Vector3(0, door_h + 0.35, zf + 0.85), Vector3(5.2, 0.16, 1.9), red, true,
		Vector3(-8, 0, 0))

	# 立面斜向深色条带
	_slab(block, Vector3(-5.0, 1.5, d * 0.5 + 0.04), Vector3(0.32, 4.4, 0.06), dark, false,
		Vector3(0, 0, 32))
	_slab(block, Vector3(5.6, 1.5, d * 0.5 + 0.04), Vector3(0.32, 4.4, 0.06), dark, false,
		Vector3(0, 0, -32))
	_slab(block, Vector3(w * 0.5 + 0.04, 1.7, -1.0), Vector3(0.06, 4.2, 0.3), dark, false,
		Vector3(26, 0, 0))

	# ── 上层解构体量：互相错位、斜切、悬挑 ──
	_slab(block, Vector3(1.2, 4.6, -0.6), Vector3(12, 2.1, 7), concrete, true, Vector3(0, 18, 0))
	_slab(block, Vector3(-2.4, 6.2, 1.2), Vector3(9, 1.5, 6), dark, true, Vector3(0, -26, 0))
	_slab(block, Vector3(0.6, 7.6, -1.0), Vector3(15, 0.35, 3.4), concrete, true,
		Vector3(0, 6, 22))
	# 两片竖着的「碎片」
	_slab(block, Vector3(5.6, 5.4, 2.4), Vector3(0.4, 5.6, 1.8), concrete, true, Vector3(0, 32, 0))
	_slab(block, Vector3(-5.4, 5.9, -2.2), Vector3(0.35, 4.6, 2.4), dark, true, Vector3(0, -38, 0))

	return block


func _seg(parent: Node, x0: float, x1: float, z: float, h: float, t: float, m: Material) -> void:
	if x1 - x0 < 0.02:
		return
	_slab(parent, Vector3((x0 + x1) * 0.5, h * 0.5, z), Vector3(x1 - x0, h, t), m)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## 一块板：Mesh + BoxShape。rot_deg 是欧拉角（度）。
func _slab(parent: Node, pos: Vector3, size: Vector3, mat: Material, solid := true,
		rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		cs.rotation_degrees = rot_deg
		parent.add_child(cs)


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

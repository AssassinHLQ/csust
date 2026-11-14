extends SceneTree
## 用 GDGS 自带的「泼溅 → 碰撞」管线，把校园点云**分块**烘成完整碰撞。
##
##   godot --headless --path . --script res://scripts/_bake_gs_collision.gd -- --trial --voxel=0.4
##   全量：  ... -- --voxel=1.0 --mesh=smooth --scene=outdoor --cutoff=0.05 ##               --tile=96 --install
##
## ⚠️ 全量产物**逐块**写进 `_log/gs_tiles/`，`--install` 会把它们拷到
##    `scenes/campus_gs/` 并生成包装场景 `scenes/campus_gs.tscn`（28 块、每块 4~5 MB）。
##    不要合成单个文件：GitHub 单文件上限 100 MB，整张 126 MB 推不上去。
##
## 数据来源：直接读场景里 Campus 节点的 splat_node（= 已经过裁剪/摆放的 GaussianResource），
## 用它自己的 global_transform 把点云变换到**世界坐标**，所以生成的网格天然和可见泼溅对齐。
##
## ⚠️ 体素管线的最小体素是 0.01（局部空间）；校园节点缩放 ≈75，所以**必须先把点云
##    变到世界空间再烘**，否则 0.01 体素 = 世界 0.75 m，细得毫无意义。
##
## ⚠️ 协方差按 `s²` 均匀缩放（校园的摆放旋转只有 1.16°/0.43°，忽略后 3σ 椭球的
##    朝向误差 < 2°，对碰撞体素化没有可见影响）。位置用完整变换，不平移/旋转近似。

const PIPELINE := preload("res://addons/gdgs/collision/pipeline/collision_pipeline.gd")
const FLOATS_PER_SPLAT := 60
const TILES_DIR := "res://_log/gs_tiles"
const INSTALL_DIR := "res://scenes/campus_gs"
const BYTES_PER_SPLAT := FLOATS_PER_SPLAT * 4

var _voxel := 0.4
var _cutoff := 0.1
var _mesh_mode := "smooth"
var _scene_mode := "object"
var _tile := 96.0
var _ymin := -8.0
var _ymax := 45.0
var _dilation := 1.6
var _trial := false
var _install := false
## 非空时额外合成一个单文件（**只用于本地预览**，不要提交：>100 MB）
var _out := ""
## 试跑地块（世界坐标）
var _trial_box := Rect2(-180.0, -280.0, 100.0, 100.0)


func _initialize() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--trial":
			_trial = true
		elif a.begins_with("--voxel="):
			_voxel = float(a.get_slice("=", 1))
		elif a.begins_with("--cutoff="):
			_cutoff = float(a.get_slice("=", 1))
		elif a.begins_with("--mesh="):
			_mesh_mode = a.get_slice("=", 1)
		elif a.begins_with("--scene="):
			_scene_mode = a.get_slice("=", 1)
		elif a.begins_with("--tile="):
			_tile = float(a.get_slice("=", 1))
		elif a.begins_with("--ymin="):
			_ymin = float(a.get_slice("=", 1))
		elif a.begins_with("--ymax="):
			_ymax = float(a.get_slice("=", 1))
		elif a.begins_with("--dilation="):
			_dilation = float(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a == "--install":
			_install = true


func _run() -> void:
	var lvl := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	for _i in 5:
		await process_frame
	# ⚠️ next_level 实例化时会把旧碰撞场景（100+ MB）一起读进来；
	#    烘焙只需要 Campus / CampusFloor，先放掉它省内存（实测全量第 25 块时崩过）。
	var old_col := lvl.get_node_or_null("CampusCollision")
	if old_col != null:
		old_col.free()
	var campus := lvl.get_node_or_null("Campus")
	if campus == null:
		print("[gsbake] 没有 Campus")
		quit(1)
		return
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.set("unload_outside_room", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	var node := campus.get("splat_node") as Node3D
	if node == null:
		print("[gsbake] splat_node 为空")
		quit(1)
		return
	var res: Resource = node.get("gaussian")
	var xf := node.global_transform
	var scale := xf.basis.get_scale().x
	var s2 := scale * scale
	var xyz: PackedVector3Array = res.get("xyz")
	var bytes: PackedByteArray = res.get("point_data_byte")
	var count := int(res.get("point_count"))
	print("[gsbake] 点 %d，体素 %.2f m，网格 %s，场景 %s，缩放 %.2f" % [
		count, _voxel, _mesh_mode, _scene_mode, scale])

	if _trial:
		var box := _trial_box
		var tr := Time.get_ticks_msec()
		var idx := PackedInt32Array()
		for i in count:
			var p := xf * xyz[i]
			if p.y < _ymin or p.y > _ymax:
				continue
			if p.x < box.position.x or p.x > box.position.x + box.size.x:
				continue
			if p.y < _ymin or p.y > _ymax:
				continue
			if p.z < box.position.y or p.z > box.position.y + box.size.y:
				continue
			idx.append(i)
		print("[gsbake] 试跑块 %s：%d 点（筛选用时 %.1f s）" % [
			str(box), idx.size(), (Time.get_ticks_msec() - tr) / 1000.0])
		var out_xyz := PackedVector3Array()
		out_xyz.resize(idx.size())
		var out_bytes := PackedByteArray()
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for k in idx.size():
			var i := idx[k]
			var p := xf * xyz[i]
			out_xyz[k] = p
			lo = lo.min(p)
			hi = hi.max(p)
			var o := i * BYTES_PER_SPLAT
			out_bytes.append_array(bytes.slice(o, o + BYTES_PER_SPLAT))
		print("[gsbake] 拷贝用时 %.1f s，字节 %.1f MB" % [
			(Time.get_ticks_msec() - tr) / 1000.0, out_bytes.size() / 1048576.0])
		var pd := out_bytes.to_float32_array()
		out_bytes = PackedByteArray()
		for k in idx.size():
			var b := k * FLOATS_PER_SPLAT
			for f in range(4, 10):
				pd[b + f] *= s2
		var snap := {
			"point_count": idx.size(),
			"xyz": out_xyz,
			"point_data_float": pd,
			"aabb": AABB(lo, hi - lo),
			"gpu_shader_source": "",
		}
		print("[gsbake] 点云世界盒 %s" % str(AABB(lo, hi - lo)))
		var baked := _bake_tile(snap, "Trial", 0, 0)
		if not baked.is_empty():
			_save_scene([{"name": "Trial", "shape": baked["shape"]}],
				"res://_log/gs_trial_%s_%.1f_%s.scn" % [_mesh_mode, _voxel, _scene_mode])
		quit(0)
		return

	_run_full(xf, xyz, bytes, count, s2)


## 全量：按 96 m 格子 + 2 m 重叠，逐块烘，最后合成一个 PackedScene。
##
## 网格对齐：管线把体素网格原点向下取整到「4 体素块」的整数倍；
## 只要体素是 1.0，块就是 4 m，任意包围盒的网格原点都落在 4 m 整数倍上 ——
## 相邻两块的世界格子天然重合。重叠 2 m 是为了让边界处的高斯密度不缺斤两。
func _run_full(xf: Transform3D, xyz: PackedVector3Array,
		bytes: PackedByteArray, count: int, s2: float) -> void:
	const APRON := 2.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TILES_DIR))
	for f in DirAccess.get_files_at(TILES_DIR):
		if f.ends_with(".scn"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TILES_DIR + "/" + f))
	var x0 := -288.0
	var z0 := -564.0
	var tiles_x := 6
	var tiles_z := 6
	# 单遍分桶：每点只做一次世界变换
	var buckets: Array[PackedInt32Array] = []
	buckets.resize(tiles_x * tiles_z)
	var t_assign := Time.get_ticks_msec()
	for i in count:
		var p := xf * xyz[i]
		if p.y < _ymin or p.y > _ymax:
			continue
		var fx := floorf((p.x + APRON - x0) / _tile)
		var fz := floorf((p.z + APRON - z0) / _tile)
		if fx < 0.0 or fz < 0.0:
			continue
		var ax := int(fx)
		var az := int(fz)
		if ax >= tiles_x or az >= tiles_z:
			continue
		buckets[az * tiles_x + ax].append(i)
	print("[gsbake] 分桶 %.1f s：%d 块，最大单块 %d 点" % [
		(Time.get_ticks_msec() - t_assign) / 1000.0, buckets.size(),
		_max_size(buckets)])

	var total_tris := 0
	var t_all := Time.get_ticks_msec()
	for iz in tiles_z:
		for ix in tiles_x:
			var idx := buckets[iz * tiles_x + ix]
			var name_ := "Tile_%d_%d" % [ix, iz]
			if idx.size() < 500:
				print("[gsbake] %s 跳过（%d 点）" % [name_, idx.size()])
				continue
			var snap := _tile_snapshot(idx, xyz, bytes, xf, s2)
			var baked := _bake_tile(snap, name_, ix, iz)
			if baked.is_empty():
				continue
			total_tris += int(baked.get("triangles", 0))
			_save_scene([{"name": name_, "shape": baked["shape"]}],
				"%s/%s.scn" % [TILES_DIR, name_])
			print("[gsbake]   内存 %.0f MB" % (OS.get_static_memory_usage() / 1048576.0))
	print("[gsbake] 全部烘完：%d 三角 / %.1f 分钟，逐块产物在 %s" % [
		total_tris, (Time.get_ticks_msec() - t_all) / 60000.0, TILES_DIR])
	if _install:
		_install_tiles()
	if not _out.is_empty():
		_merge_tiles(_out)
	quit(0)


## 把 `_log/gs_tiles/*.scn` 拷进 `scenes/campus_gs/`，并生成文本包装场景
func _install_tiles() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(INSTALL_DIR))
	var files: Array[String] = []
	for f in DirAccess.get_files_at(TILES_DIR):
		if f.ends_with(".scn"):
			files.append(f)
	files.sort()
	for f in files:
		var data := FileAccess.get_file_as_bytes(TILES_DIR + "/" + f)
		var out := FileAccess.open(INSTALL_DIR + "/" + f, FileAccess.WRITE)
		if out == null:
			push_error("[gsbake] 写不了 %s" % (INSTALL_DIR + "/" + f))
			continue
		out.store_buffer(data)
		out.close()
	var lines := PackedStringArray()
	lines.append("[gd_scene load_steps=%d format=3]" % (files.size() + 1))
	lines.append("")
	for i in files.size():
		lines.append('[ext_resource type="PackedScene" path="%s/%s" id="%d"]'
			% [INSTALL_DIR, files[i], i + 1])
	lines.append("")
	lines.append('[node name="CampusCollisionGS" type="Node3D"]')
	for i in files.size():
		lines.append('[node name="%s" parent="." instance=ExtResource("%d")]'
			% [files[i].get_basename(), i + 1])
	var w := FileAccess.open("res://scenes/campus_gs.tscn", FileAccess.WRITE)
	if w != null:
		w.store_string("
".join(lines) + "
")
		w.close()
	print("[gsbake] 安装 %d 块 → %s + campus_gs.tscn" % [files.size(), INSTALL_DIR])


func _max_size(buckets: Array[PackedInt32Array]) -> int:
	var m := 0
	for b in buckets:
		m = maxi(m, b.size())
	return m


## 把一块的点（世界坐标 + 协方差按 s² 缩放）整理成管线要的 snapshot
func _tile_snapshot(idx: PackedInt32Array, xyz: PackedVector3Array,
		bytes: PackedByteArray, xf: Transform3D, s2: float) -> Dictionary:
	var out_xyz := PackedVector3Array()
	out_xyz.resize(idx.size())
	var out_bytes := PackedByteArray()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for k in idx.size():
		var i := idx[k]
		var p := xf * xyz[i]
		out_xyz[k] = p
		lo = lo.min(p)
		hi = hi.max(p)
		var o := i * BYTES_PER_SPLAT
		out_bytes.append_array(bytes.slice(o, o + BYTES_PER_SPLAT))
	var pd := out_bytes.to_float32_array()
	out_bytes = PackedByteArray()
	for k in idx.size():
		var b := k * FLOATS_PER_SPLAT
		for f in range(4, 10):
			pd[b + f] *= s2
	return {
		"point_count": idx.size(),
		"xyz": out_xyz,
		"point_data_float": pd,
		"aabb": AABB(lo, hi - lo),
		"gpu_shader_source": "",
	}


## 把逐块落盘的 .scn 合成一个场景（每块单独读入，峰值只有一个块 + 已合并的节点）
func _merge_tiles(path: String) -> void:
	var root := Node3D.new()
	root.name = "CampusCollisionGS"
	var files: Array[String] = []
	for f in DirAccess.get_files_at(TILES_DIR):
		if f.ends_with(".scn"):
			files.append(f)
	files.sort()
	for f in files:
		var ps := load(TILES_DIR + "/" + f) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		inst.owner = root
		_own_all(inst, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	var serr := ResourceSaver.save(packed, path)
	var size_mb := 0.0
	if FileAccess.file_exists(path):
		size_mb = FileAccess.get_file_as_bytes(path).size() / 1048576.0
	print("[gsbake] 合并 %d 块 → %s：pack=%d save=%d，%.1f MB" % [
		files.size(), path, err, serr, size_mb])


func _own_all(n: Node, root: Node) -> void:
	for ch in n.get_children():
		ch.owner = root
		_own_all(ch, root)


func _save_scene(bodies: Array, path: String) -> void:
	var root := Node3D.new()
	root.name = String(bodies[0]["name"]) if bodies.size() == 1 else "CampusCollisionGS"
	for b in bodies:
		var body := StaticBody3D.new()
		body.name = String(b["name"])
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		cs.shape = b["shape"]
		body.add_child(cs)
		root.add_child(body)
		body.owner = root
		cs.owner = root
	var ps := PackedScene.new()
	var err := ps.pack(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var serr := ResourceSaver.save(ps, path)
	var size_mb := 0.0
	if FileAccess.file_exists(path):
		size_mb = FileAccess.get_file_as_bytes(path).size() / 1048576.0
	print("[gsbake] 保存 %s：pack=%d save=%d，%.1f MB" % [path, err, serr, size_mb])


func _bake_tile(snap: Dictionary, name_: String, ix: int, iz: int) -> Dictionary:
	var t := Time.get_ticks_msec()
	var settings := {
		"voxel_size": _voxel,
		"opacity_cutoff": _cutoff,
		"mesh_mode": _mesh_mode,
		"scene_mode": _scene_mode,
		"compute_backend": "cpu",
		"dilation": _dilation,
		"carve": false,
		"capsule_height": 1.6,
		"capsule_radius": 0.2,
		"seed": Vector3.ZERO,
		# ⚠️ 我们喂的是**世界坐标**（Y 朝上）：管线按「局部空间的 down 方向」判正负，
		#    世界空间里 down_local = (0,-1,0) ⇒ 必须 -1；写 +1 会把**天空**封死（实测
		#    地面射线全部变成 20~56 m，等于头顶多了一层天花板）。
		"floor_y_sign": -1.0,
		"keep_grid": false,
	}
	var result := PIPELINE.generate_from_snapshot_settings(snap, settings)
	if not bool(result.get("ok", false)):
		print("[gsbake] %s 失败：%s" % [name_, result.get("error", "")])
		return {}
	var fin := PIPELINE.finalize_result(result)
	if not bool(fin.get("ok", false)):
		print("[gsbake] %s finalize 失败：%s" % [name_, fin.get("error", "")])
		return {}
	var st: Dictionary = result["stats"]
	print("[gsbake] %s：%d 点 / 网格 %s / %d 体素 / %d 三角 / %d 顶点 / %.1f s（准备 %.1f 体素化 %.1f 清理 %.1f 建面 %.1f）" % [
		name_, int(st["valid_splats"]), str(st["output_grid_dimensions"]),
		int(st["occupied_voxels"]), int(st["triangles"]), int(st["vertices"]),
		(Time.get_ticks_msec() - t) / 1000.0,
		float(st["prepare_msec"]) / 1000.0, float(st["voxelize_msec"]) / 1000.0,
		float(st["cleanup_msec"]) / 1000.0, float(st["mesher_msec"]) / 1000.0])
	var shape := PIPELINE.create_collision_shape(fin["mesh"])
	if shape == null:
		print("[gsbake] %s 碰撞形状为空" % name_)
		return {}
	return {"mesh": fin["mesh"], "shape": shape, "triangles": int(st["triangles"])}
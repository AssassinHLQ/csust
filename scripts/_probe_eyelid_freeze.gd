extends SceneTree
## 探针：给「不要眨眼了」定冻结值。
##
## 用户 2026-10-17：「眼睛那里停止算了，不要眨眼的动画了」。
## 本探针只回答三个问题：
##   1. 眨眼到底是哪几根骨的哪几条轨道在动？（逐动作列出来）
##   2. 每只眼的**张开度**在动作里多大范围？rest 姿势排第几？
##       张开度 = dot(眼睑骨的 +Y 方向, 头的上方向)，上睑减下睑算成「开合量」。
##   3. 冻结成 rest 姿势 vs 冻结成「动作里最开的那一帧」，哪张脸好看？（出 A/B 图）
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_eyelid_freeze.gd
## 输出（`_arisu_captures/_eyelid/`）：
##   closed.png   动作里最闭的一帧（眨眼进行时）
##   rest.png     全部骨 reset 成 rest
##   open.png     动作里最开的一帧
##   frozen.png   用最开那一帧的局部旋转把眼睑轨道压成常量

const MODEL := "res://models/Arisu_ext.glb"
const OUT_DIR := "_arisu_captures/_eyelid"
const SAMPLES := 24          ## 每个动作均匀取多少个时刻来量张开度
const LID_BONES := ["Bip001 eye_L_1", "Bip001 eye_L_2", "Bip001 eye_R_1", "Bip001 eye_R_2"]

var _ap: AnimationPlayer
var _sk: Skeleton3D
var _lid := {}               ## 短名（eye_L_1…）→ 骨索引
var _up := Vector3.UP        ## 头的上方向（骨架空间）


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(720, 820)
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	for _i in 4:
		await process_frame
	_ap = _find_anim(inst)
	_sk = _find_skel(inst)
	if _ap == null or _sk == null:
		print("!! 模型里没有 AnimationPlayer / Skeleton3D")
		quit(1)
		return
	_resolve_bones()
	_lid_up()
	# 脸皮和眼睛共面 → 某些角度下整只眼睛被脸皮盖住（就是「眼睛不见了」那类图）。
	# 游戏里 `anim_driver` 会推开这一层，这里也得推开，否则 A/B 比的不是眨眼而是 z-fighting。
	var ff := FaceFix.separate_face_layers(inst)
	print("[lid] 脸部层推开 %d 个 surface / %d 顶点（跳过带形态键的 %d 个）"
		% [int(ff["surfaces"]), int(ff["verts"]), int(ff["skipped"])])

	# 亮背景 + 环境光，跟 `_probe_face_shot.gd` 一套，方便两张图直接对比
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.80, 0.82, 0.86)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.6
	env.environment = e
	root.add_child(env)

	var hl := _bone_world("eye_L_1")
	var hr := _bone_world("eye_R_1")
	var head := _bone_world("Head")
	var mid: Vector3 = (hl + hr) * 0.5
	var right: Vector3 = (hr - hl).normalized()
	var fwd: Vector3 = right.cross(Vector3.UP).normalized()
	if fwd.dot(mid - head) < 0.0:
		fwd = -fwd
	print("[lid] 眼距 %.3f m  脸法线 %s" % [hl.distance_to(hr), str(fwd.snappedf(0.01))])

	var key := DirectionalLight3D.new()
	key.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), mid + fwd * 2.0)
	key.light_energy = 1.15
	key.shadow_enabled = false
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	var side: Vector3 = right.cross(fwd).normalized()
	fill.global_transform = Transform3D(
		Basis.looking_at(-(fwd * 0.5 + side * 0.85).normalized(), Vector3.UP), mid + side)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	root.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 28.0
	cam.near = 0.01
	cam.far = 100.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# ── 1. rest 姿势的张开度 ──
	_sk.reset_bone_poses()
	await process_frame
	var rest := _aperture()
	print("[lid] rest 姿势：上睑 %+.4f  下睑 %+.4f  开合量 %+.4f（左）  "
		% [rest.x, rest.y, rest.x - rest.y])
	print("[lid]             上睑 %+.4f  下睑 %+.4f  开合量 %+.4f（右）"
		% [rest.z, rest.w, rest.z - rest.w])
	await _shoot_face(cam, 0.62, out.path_join("rest.png"))

	# 先把「脸上所有可能算眼睛的骨」都数一遍 —— 第一版只认 `Bip001 eye_*_1/2`，
	# 结果冻结后眼睑骨确实回 rest 了，可**睫毛/眼线**还在闭着的位置：说明那圈
	# 几何挂在另一组骨上（`bone_eye_D_*` 之类）。
	await _scan_face_bones()

	# ── 2. 逐动作扫：眨眼是哪几条轨道、张开度范围多大 ──
	var clips: Array = _ap.get_animation_list()
	clips.sort()
	var stats := {}       ## clip → {min_l, max_l, min_r, max_r, worst_t, best_t, moved}
	for clip in clips:
		var a := _ap.get_animation(String(clip))
		var moved := _lid_track_names(a)
		if moved.is_empty():
			continue
		print("[lid] 「%s」长度 %.2f s，眼睑相关轨道 %d 条：%s"
			% [clip, a.length, moved.size(), str(moved)])
		_ap.play(String(clip), -1.0, 0.0)      # speed 0，用 seek 定相位
		var st := {"min_l": 9.0, "max_l": -9.0, "min_r": 9.0, "max_r": -9.0,
			"worst_t": 0.0, "best_t": 0.0, "aperture": 9.0, "best": -9.0}
		for s in SAMPLES:
			var t := a.length * float(s) / float(SAMPLES)
			_ap.seek(t, true)
			await process_frame
			var ap2 := _aperture()
			st["min_l"] = minf(float(st["min_l"]), ap2.x)
			st["max_l"] = maxf(float(st["max_l"]), ap2.x)
			st["min_r"] = minf(float(st["min_r"]), ap2.z)
			st["max_r"] = maxf(float(st["max_r"]), ap2.z)
			var open := (ap2.x - ap2.y) + (ap2.z - ap2.w)
			if open < float(st["aperture"]):
				st["aperture"] = open
				st["worst_t"] = t
			if open > float(st["best"]):
				st["best"] = open
				st["best_t"] = t
		stats[String(clip)] = st
		print("[lid]   左睑 %+.4f ~ %+.4f（Δ%.4f）  右睑 %+.4f ~ %+.4f（Δ%.4f）"
			% [st["min_l"], st["max_l"], float(st["max_l"]) - float(st["min_l"]),
			st["min_r"], st["max_r"], float(st["max_r"]) - float(st["min_r"])])
		print("[lid]   最闭 t=%.2f（开合量 %+.4f）  最开 t=%.2f（%+.4f）"
			% [st["worst_t"], st["aperture"], st["best_t"], st["best"]])

	# ── 3. 找全动画里最闭 / 最开的那一帧，各拍一张 ──
	var g_worst := {"clip": "", "t": 0.0, "v": 9.0}
	var g_best := {"clip": "", "t": 0.0, "v": -9.0}
	for clip in stats:
		var st: Dictionary = stats[clip]
		if float(st["aperture"]) < float(g_worst["v"]):
			g_worst = {"clip": clip, "t": float(st["worst_t"]), "v": float(st["aperture"])}
		if float(st["best"]) > float(g_best["v"]):
			g_best = {"clip": clip, "t": float(st["best_t"]), "v": float(st["best"])}
	if g_worst["clip"] == "":
		print("[lid] 所有动作里都没有眼睑轨道 —— 本来就是静态的，没什么可冻")
		quit(0)
		return
	print("[lid] 全局最闭：%s @ %.2f s（开合量 %+.4f）" % [g_worst["clip"], g_worst["t"], g_worst["v"]])
	print("[lid] 全局最开：%s @ %.2f s（开合量 %+.4f）" % [g_best["clip"], g_best["t"], g_best["v"]])

	# ── 3. A/B：**同一个动作、同一时刻**，冻结前 vs 冻结后 ──
	# 用 Normal_Idle 而不是全局最闭的 Vital_Death：那张是死亡动作（本来就要闭眼），
	# 玩家平时看到的是待机时的眨眼。
	var idle := "Normal_Idle"
	var st_idle: Dictionary = stats[idle]
	var st_idle_length: float = _ap.get_animation(idle).length
	_pose_at(idle, float(st_idle["worst_t"]))
	await process_frame
	var before := _aperture()
	await _shoot_face(cam, 0.62, out.path_join("closed.png"))
	print("[lid] 冻结前 Normal_Idle @ %.2f s 张开度：左 %+.4f  右 %+.4f"
		% [st_idle["worst_t"], before.x - before.y, before.z - before.w])

	_pose_at(idle, float(st_idle["best_t"]))
	await process_frame
	var bopen := _aperture()
	await _shoot_face(cam, 0.62, out.path_join("open.png"))
	print("[lid] 冻结前 Normal_Idle @ %.2f s 张开度：左 %+.4f  右 %+.4f"
		% [st_idle["best_t"], bopen.x - bopen.y, bopen.z - bopen.w])

	# ── 4. 真正的修法：把眼睑轨道整条删掉，骨回到 rest，同一个时刻再拍一张 ──
	print("[lid] 最开那一帧的眼睑局部旋转：%s" % _fmt_q(_capture_lid_rotations()))
	var rep := PoseFix.freeze_eyelids(_sk, _ap)
	print("[lid] freeze_eyelids → applied=%s 删了 %d 条轨道，动过的动作 %d 个 %s，骨名对不上 %s"
		% [rep["applied"], rep["tracks"], (rep["clips"] as Array).size(),
		str(rep["clips"]), str(rep["missing"])])
	var n := 0
	for clip in _ap.get_animation_list():
		n += _lid_track_names(_ap.get_animation(String(clip))).size()
	print("[lid] 冻结后仍存在的眼睑轨道 %d 条（应为 0）" % n)

	# ⚠️ 删轨道**不会**把骨摆回 rest —— 骨会保留当前这一刻的姿势。
	# 游戏里启动时骨架是 rest，所以这里必须 `stop()` + `reset_bone_poses()`
	# 模拟「刚进游戏」的状态，否则拍到的还是删轨道之前那一帧的闭眼。
	_sk.reset_bone_poses()
	_ap.stop()
	_pose_at(idle, float(st_idle["worst_t"]))
	await process_frame
	var after := _aperture()
	await _shoot_face(cam, 0.62, out.path_join("frozen.png"))

	# 同一动作的「最开」帧，冻结后再拍一张：如果这张有瞳孔、frozen.png 没有，
	# 那「没瞳孔」不是冻结造成的，而是这一帧别的东西（眼睛朝向 / 头发挡）的事。
	_pose_at(idle, float(st_idle["best_t"]))
	await process_frame
	await _shoot_face(cam, 0.62, out.path_join("frozen_open.png"))
	print("[lid] 冻结后 Normal_Idle @ %.2f s 张开度：左 %+.4f  右 %+.4f（rest 是 左 %+.4f  右 %+.4f）"
		% [st_idle["worst_t"], after.x - after.y, after.z - after.w,
		rest.x - rest.y, rest.z - rest.w])

	# 整个动作扫一遍：冻结后张开度应当**全程恒定**
	var amin := 9.0
	var amax := -9.0
	for s in SAMPLES:
		_pose_at(idle, float(st_idle_length) * float(s) / float(SAMPLES))
		await process_frame
		var a2 := _aperture()
		amin = minf(amin, (a2.x - a2.y) + (a2.z - a2.w))
		amax = maxf(amax, (a2.x - a2.y) + (a2.z - a2.w))
	print("[lid] 冻结后 Normal_Idle 全程开合量 %+.4f ~ %+.4f（Δ%.5f，应为 0）"
		% [amin, amax, amax - amin])
	quit(0)


## 把名字里带 eye / lid / brow / mayu 的骨全列出来，量 `Normal_Idle` 里的转角范围。
## 目的：找出「眨眼到底动了哪几根骨」。只认 `Bip001 eye_*_1/2` 是不够的（见上面注释）。
func _scan_face_bones() -> void:
	var targets: Array = []
	for i in _sk.get_bone_count():
		var nm := String(_sk.get_bone_name(i))
		var low := nm.to_lower()
		if low.contains("eye") or low.contains("lid") or low.contains("brow") or low.contains("mayu"):
			targets.append({"i": i, "n": nm})
	print("[lid] 名字带 eye/lid/brow 的骨 %d 根" % targets.size())
	if targets.is_empty():
		return
	var a := _ap.get_animation("Normal_Idle")
	_ap.play("Normal_Idle", -1.0, 0.0)
	var rec := {}
	for s in 12:
		_ap.seek(a.length * float(s) / 12.0, true)
		await process_frame
		for e in targets:
			var q: Quaternion = _sk.get_bone_pose_rotation(int(e["i"]))
			var ang := rad_to_deg(q.get_angle())
			var k: String = e["n"]
			if not rec.has(k):
				rec[k] = {"min": ang, "max": ang}
			rec[k]["min"] = minf(float(rec[k]["min"]), ang)
			rec[k]["max"] = maxf(float(rec[k]["max"]), ang)
	var keys: Array = rec.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = rec[k]
		var delta := float(r["max"]) - float(r["min"])
		if delta >= 0.5:
			print("[lid]   %-30s 转角 %5.2f° ~ %5.2f°（Δ%5.2f）★在动"
				% [k, r["min"], r["max"], delta])
		else:
			print("[lid]   %-30s 转角 %5.2f° ~ %5.2f°（Δ%5.2f）"
				% [k, r["min"], r["max"], delta])


## 把眼睑骨的索引和短名对上
func _resolve_bones() -> void:
	for full in LID_BONES:
		var short := String(full).replace("Bip001 ", "")
		var i := _sk.find_bone(String(full))
		if i < 0:
			for b in _sk.get_bone_count():
				if String(_sk.get_bone_name(b)).ends_with(short):
					i = b
					break
		if i < 0:
			print("[lid] !! 找不到骨 %s" % full)
			continue
		_lid[short] = i
	print("[lid] 眼睑骨 %d/4：%s" % [_lid.size(), str(_lid.keys())])


## 头的上方向取头骨三个轴里最接近世界 UP 的那个（骨架节点是带旋转的）
func _lid_up() -> void:
	var hi := _sk.find_bone("Bip001 Head")
	if hi < 0:
		return
	var b := _sk.get_bone_global_pose(hi).basis.orthonormalized()
	var best := Vector3.UP
	var bestd := -2.0
	for a in [b.x, b.y, b.z, -b.x, -b.y, -b.z]:
		var d: float = (a as Vector3).dot(Vector3.UP)
		if d > bestd:
			bestd = d
			best = a
	_up = best
	print("[lid] 头的上方向 %s（与世界上方夹角 %.1f°）"
		% [str(_up.snappedf(0.01)), rad_to_deg(acos(clampf(_up.dot(Vector3.UP), -1.0, 1.0)))])


## 张开度：每根眼睑骨 +Y 方向在「头上方向」上的投影。
## 上睑越往上 / 下睑越往下 = 越开 → 返回 (上L, 下L, 上R, 下R)
func _aperture() -> Vector4:
	var v := Vector4.ZERO
	for short in ["eye_L_1", "eye_L_2", "eye_R_1", "eye_R_2"]:
		if not _lid.has(short):
			continue
		var i: int = _lid[short]
		var d := _sk.get_bone_global_pose(i).basis.orthonormalized().y
		var score := d.dot(_up)
		if short.ends_with("_1"):
			if short.contains("_L"):
				v.x = score
			else:
				v.z = score
		else:
			if short.contains("_L"):
				v.y = score
			else:
				v.w = score
	return v


## 这个动作里哪些轨道挂在眼睑骨上（返回骨短名列表）
func _lid_track_names(a: Animation) -> Array:
	var out: Array = []
	for t in a.get_track_count():
		var path := String(a.track_get_path(t))
		var bone := path.substr(path.rfind(":") + 1)
		for short in _lid:
			if bone.contains(String(short)) and not out.has(short):
				out.append(short)
	return out


func _pose_at(clip: String, t: float) -> void:
	_ap.play(clip, -1.0, 0.0)
	_ap.seek(t, true)


## 当前这一帧眼睑骨的局部旋转（冻结用）
func _capture_lid_rotations() -> Dictionary:
	var d := {}
	for short in _lid:
		d[short] = _sk.get_bone_pose_rotation(int(_lid[short]))
	return d


func _apply_frozen(d: Dictionary) -> void:
	for short in d:
		_sk.set_bone_pose_rotation(int(_lid[short]), d[short])


func _fmt_q(d: Dictionary) -> String:
	var parts: Array = []
	for k in d:
		var q: Quaternion = d[k]
		parts.append("%s=(%.4f, %.4f, %.4f, %.4f)" % [k, q.x, q.y, q.z, q.w])
	return "  ".join(parts)


## 每张图都**按当时的姿态**重新摆相机 —— 待机动作里她会转头，固定机位会拍到后脑勺
func _shoot_face(cam: Camera3D, dist: float, file: String) -> void:
	var hl := _bone_world("eye_L_1")
	var hr := _bone_world("eye_R_1")
	var head := _bone_world("Head")
	var mid: Vector3 = (hl + hr) * 0.5
	var right: Vector3 = (hr - hl).normalized()
	var fwd: Vector3 = right.cross(Vector3.UP).normalized()
	if fwd.dot(mid - head) < 0.0:
		fwd = -fwd
	await _shoot(cam, mid, fwd, dist, file)


func _shoot(cam: Camera3D, at: Vector3, fwd: Vector3, dist: float, file: String) -> void:
	cam.global_position = at + fwd * dist + Vector3.UP * 0.01
	cam.look_at(at, Vector3.UP)
	for _i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("  [img] %s" % file)


func _bone_world(bone: String) -> Vector3:
	var i := _sk.find_bone("Bip001 " + bone)
	if i < 0:
		i = _sk.find_bone(bone)
	return _sk.global_transform * _sk.get_bone_global_pose(i).origin


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null

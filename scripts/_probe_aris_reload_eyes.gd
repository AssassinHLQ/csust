extends SceneTree
## 量两件事（用户 2026-11-11）：
##   ① 「爱丽丝普通换弹动画最后一帧跳动幅度剧烈」——
##      **直接模拟一次换弹**，逐帧记全部骨骼，量出「停叠加层」那一瞬间跳了多少度。
##      不用代理指标（末帧 vs 待机帧的距离只是线索，不是用户看到的那个东西）。
##   ② 「为什么眼睛有时候右眼反光些」—— 左右眼共用一份材质，所以只能是
##      高光参数 / 贴图 / 灯位的问题，把材质参数全打出来。
##
##   & godot --script res://scripts/_probe_aris_reload_eyes.gd -- --splat=off --story=off

const OffWin := preload("res://scripts/offscreen_window.gd")
const RELOAD_CLIP := "Normal_Reload"
const RELOAD_SPEED := 1.9
const KEYWORDS_EYE := ["eye", "iris", "pupil", "sclera", "highlight", "catchlight"]

var _drv: Node
var _ap: AnimationPlayer
var _sk: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame

	_drv = game.find_child("AnimDriver", true, false)
	_ap = _drv.get("player") as AnimationPlayer if _drv != null else null
	_sk = _drv.get("skeleton") as Skeleton3D if _drv != null else null

	await _measure_transition()
	_analyze_eyes()

	game.queue_free()
	await process_frame
	quit()


# --- ① 真实过渡测量 -----------------------------------------------------------

func _measure_transition() -> void:
	print("\n================ ① 换弹收招时的真实跳变 ================")
	if _drv == null or _ap == null or _sk == null:
		print("  ❌ 拿不到 AnimDriver / AnimationPlayer / Skeleton3D")
		return
	print("  clip %s 长度 %.4f s / 1.9× = %.3f s；基础层当前动作「%s」"
		% [RELOAD_CLIP, _ap.get_animation(RELOAD_CLIP).length,
			_ap.get_animation(RELOAD_CLIP).length / RELOAD_SPEED, _ap.current_animation])

	var bones := _sk.get_bone_count()
	var reload_time := _ap.get_animation(RELOAD_CLIP).length / RELOAD_SPEED

	# ⚠️ 先查每一层实际还剩多少**头发**轨道 —— 否则「跳 43°」可能只是本喵的过滤没生效。
	print("  ── 各叠加层的头发轨道数 ──")
	for ln in ["upper", "upper_move", "arms"]:
		var lay = _drv.get(ln)
		if lay == null:
			print("    %-12s (null)" % ln)
			continue
		for clip in lay.get_animation_list():
			var a2: Animation = lay.get_animation(clip)
			var hair := 0
			for t2 in a2.get_track_count():
				if String(a2.track_get_path(t2)).to_lower().contains("hair"):
					hair += 1
			print("    %-12s / %-20s %4d 条轨道，其中 hair %d 条"
				% [ln, String(clip), a2.get_track_count(), hair])

	# ── 对照实验：**纯 idle 3 秒**（不换弹）的最大归一化跳变 ──
	# 用来区分「换弹收招导致的跳」和「idle 循环本身在跳」（后者与换弹无关）。
	print("  ── 对照：纯 idle 3 s ──")
	var prev0 := _snapshot()
	var t0 := Time.get_ticks_msec()
	var tp0 := 0.0
	var idle_worst := 0.0
	var idle_bone := ""
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		var tt := (Time.get_ticks_msec() - t0) / 1000.0
		var dt0 := maxf(tt - tp0, 0.0001)
		var cur0 := _snapshot()
		for i in _sk.get_bone_count():
			var d0 := rad_to_deg((prev0[i] as Quaternion).angle_to(cur0[i] as Quaternion))
			var r0 := d0 * (0.016667 / dt0)
			if r0 > idle_worst:
				idle_worst = r0
				idle_bone = _sk.get_bone_name(i)
		prev0 = cur0
		tp0 = tt
	print("    纯 idle 3 s 内最大归一化跳变：%.2°/帧@60fps（骨骼 %s）" % [idle_worst, idle_bone])

	# 先让基础层稳定几帧
	for _i in 10:
		await process_frame
	_drv.call("request_reload")
	var frames: Array = []      # 每帧 [{t, dt, deg, rate, bone}]
	var prev := _snapshot()
	var t_start := Time.get_ticks_msec()
	var t_prev := 0.0
	var last_t := 0.0
	var finished_at := -1.0
	while Time.get_ticks_msec() - t_start < 4000:
		await process_frame
		var t := (Time.get_ticks_msec() - t_start) / 1000.0
		var dt := maxf(t - t_prev, 0.0001)
		var cur := _snapshot()
		var worst_deg := 0.0
		var worst_bone := ""
		for i in bones:
			var qa: Quaternion = prev[i]
			var qb: Quaternion = cur[i]
			var d := rad_to_deg(qa.angle_to(qb))
			if d > worst_deg:
				worst_deg = d
				worst_bone = _sk.get_bone_name(i)
		# **按 60 fps 归一化**：卡一帧时 dt 变大，姿势差自然变大，那不是「跳」
		var rate := worst_deg * (0.016667 / dt)
		frames.append({"t": t, "dt": dt, "deg": worst_deg, "rate": rate, "bone": worst_bone,
			"playing": _playing_layers()})
		prev = cur
		t_prev = t
		last_t = t
		# 收招完成 = state 回到 LOCOMOTION
		if finished_at < 0.0 and int(_drv.get("state")) == 0 and t > 0.1:
			finished_at = t
	if finished_at < 0.0:
		print("  ⚠️ 4 s 内没看到收招（state 一直没回 LOCOMOTION）")
		print("     → 最后 t=%.3f s，state=%d" % [last_t, int(_drv.get("state"))])
	else:
		print("  收招时刻（state → LOCOMOTION）：t = %.3f s（理论 %.3f s）"
			% [finished_at, reload_time])

	# 打印峰值附近的逐帧曲线
	frames.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	var peak := {"rate": 0.0, "deg": 0.0, "t": 0.0, "bone": "", "dt": 0.0}
	for f in frames:
		if float(f["rate"]) > float(peak["rate"]):
			peak = f
	print("  全程**归一化**单帧最大跳变：%.2°/帧@60fps（原始 %.2°/%.1f ms，骨骼 %s，t=%.3f s）"
		% [float(peak["rate"]), float(peak["deg"]), float(peak["dt"]) * 1000.0,
			String(peak["bone"]), float(peak["t"])])
	print("\n  ── 最后 16 帧（deg / 归一化 / dt）──")
	var tail := frames.slice(maxi(frames.size() - 16, 0))
	for f in tail:
		var bar := "#".repeat(mini(int(float(f["rate"])), 60))
		print("    t=%6.3f  %6.2f°  归一%6.2f  dt=%5.1fms  %-26s %s"
			% [float(f["t"]), float(f["deg"]), float(f["rate"]),
				float(f["dt"]) * 1000.0, String(f["bone"]), bar])

	# 收招前后那几帧单独拎出来
	if finished_at > 0.0:
		print("\n  ── 收招点前后 ±3 帧（含每层在播什么）──")
		for f in frames:
			if absf(float(f["t"]) - finished_at) < 0.075:
				print("    t=%6.3f  %6.2f°  归一%6.2f  dt=%5.1fms  %-24s  层=%s"
					% [float(f["t"]), float(f["deg"]), float(f["rate"]),
						float(f["dt"]) * 1000.0, String(f["bone"]), String(f["playing"])])
		# 收招那一帧的**前 12 名**：用来区分「头发自己在跳」和「头/颈被释放带着发链转」
		print("\n  ── 收招那一帧跳变最大的 12 根骨 ──")
		await _report_top_at(finished_at)


## 现在哪几层在播、播的什么
func _playing_layers() -> String:
	var out: Array[String] = []
	var base_txt := "base:%s" % (String(_ap.current_animation) if _ap != null and _ap.is_playing() else "停")
	out.append(base_txt)
	for ln in ["upper", "upper_move", "arms"]:
		var lay = _drv.get(ln) as AnimationPlayer
		if lay == null:
			continue
		if lay.is_playing():
			out.append("%s:%s" % [ln, String(lay.current_animation)])
	return " ".join(out)


func _snapshot() -> Array:
	var out: Array = []
	for i in _sk.get_bone_count():
		out.append(_sk.get_bone_global_pose(i).basis.get_rotation_quaternion())
	return out


## 重播一次换弹，在「收招那一瞬间」抓一帧，把跳变最大的 12 根骨连同
## **它的父骨是谁**一起打出来 —— 用来区分「头发自己在跳」和「头/颈被释放带着发链转」。
func _report_top_at(prev_finished_at: float) -> void:
	for _i in 15:
		await process_frame
	_drv.call("request_reload")
	var prev := _snapshot()
	# 一直跑到 state 回 LOCOMOTION 的那一帧
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await process_frame
		var cur := _snapshot()
		if int(_drv.get("state")) == 0:
			var rows: Array = []
			for i in _sk.get_bone_count():
				var d := rad_to_deg((prev[i] as Quaternion).angle_to(cur[i] as Quaternion))
				if d > 0.5:
					rows.append([d, i])
			rows.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
			print("    共 %d 根骨动了 >0.5°" % rows.size())
			# 直方图：区分「全骨一起转」和「某几根单独跳」
			var bins := {"≥30°": 0, "10~30°": 0, "3~10°": 0, "0.5~3°": 0}
			for r in rows:
				var d := float(r[0])
				if d >= 30.0:
					bins["≥30°"] += 1
				elif d >= 10.0:
					bins["10~30°"] += 1
				elif d >= 3.0:
					bins["3~10°"] += 1
				else:
					bins["0.5~3°"] += 1
			print("    直方图：%s" % str(bins))
			# 指定几个关键骨：根骨 / 躯干 / 头 / 一根发根 / 一根腿骨
			var watch := ["Bip001", "Bip001 Pelvis", "Bip001 Spine", "Bip001 Head",
				"bone_hair_f_01", "bone_hair_l_06", "Bip001 L Thigh", "Bip001 L UpperArm"]
			var idx_of := {}
			for r in rows:
				idx_of[_sk.get_bone_name(int(r[1]))] = float(r[0])
			var wl := "    关注骨："
			for wn in watch:
				wl += "%s=%.1f° " % [wn, float(idx_of.get(wn, 0.0))]
			print(wl)
			# 场上**所有** AnimationPlayer 的状态（别只盯已知那三层）
			print("    所有 AnimationPlayer：")
			for ap2 in _all_anim_players(root):
				print("      %-34s playing=%-5s anim=%s"
					% [String(ap2.get_path()).substr(0, 34), str(ap2.is_playing()),
						String(ap2.current_animation)])
			for k in mini(8, rows.size()):
				var idx := int(rows[k][1])
				var par := _sk.get_bone_parent(idx)
				var pname := _sk.get_bone_name(par) if par >= 0 else "(无)"
				print("      %6.2f°  %-26s  父=%-24s" % [float(rows[k][0]),
					_sk.get_bone_name(idx), pname])
			return
		prev = cur


# --- ② 眼睛材质 ---------------------------------------------------------------

func _analyze_eyes() -> void:
	print("\n================ ② 眼睛 / 高光 ================")
	var rootn: Node = _drv.get_parent() if _drv != null else null
	if rootn == null:
		print("  ❌ 找不到玩家模型根")
		return
	var found := 0
	for n in _all_meshes(rootn):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat == null:
				continue
			var nm := String(mat.resource_name).to_lower()
			var hit := false
			for kw in KEYWORDS_EYE:
				if nm.contains(kw):
					hit = true
					break
			if not hit:
				continue
			found += 1
			print("\n  ▸ %s / surface %d → 「%s」"
				% [String(mi.name), s, String(mat.resource_name)])
			_dump(mat)
			# 顶点级：这个 surface 的包围盒能不能区分左右眼
			_report_surface_extent(mi, s)
	if found == 0:
		print("  ❌ 没有材质名命中眼睛关键字")


## 把材质参数全部打出来。**一律走 `get()`**：直接写属性名拼错会抛
## `Invalid access to property` 并中断这个函数（本喵第一版就栽在
## `metallic_specular_texture` 上，整个 dump 一条都没打出来）。
func _dump(mat: Material) -> void:
	var keys := ["metallic", "roughness", "metallic_specular", "specular_mode",
		"clearcoat", "clearcoat_roughness", "anisotropy", "anisotropy_flowmap",
		"rim", "rim_enabled", "rim_tint", "rim_amount",
		"emission_enabled", "emission", "emission_energy_multiplier",
		"albedo_color", "normal_scale", "transparency", "shading_mode",
		"backlight_enabled", "backlight", "ao_enabled", "ao_light_affect",
		"uv1_scale", "uv1_offset", "refraction_enabled", "subsurf_scatter_enabled"]
	var line := "    "
	for k in keys:
		var v = mat.get(k)
		if v != null:
			line += "%s=%s " % [k, str(v)]
	print(line)
	for tk in ["albedo_texture", "normal_texture", "metallic_texture",
			"roughness_texture", "emission_texture", "rim_texture",
			"ao_texture", "clearcoat_texture"]:
		var tex = mat.get(tk)
		if tex != null:
			print("    %s：%s" % [tk, String((tex as Texture2D).resource_path)])


## 眼睛 surface 的顶点包围盒 + 左右分组（判断两只眼是不是同一批顶点）
func _report_surface_extent(mi: MeshInstance3D, s: int) -> void:
	var arr := mi.mesh.surface_get_arrays(s)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return
	var lo := verts[0]
	var hi := verts[0]
	var left := 0
	var right := 0
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
		if v.x > 0.0:
			left += 1
		elif v.x < 0.0:
			right += 1
	print("    顶点 %d 个，包围盒 %s ~ %s（x>0 有 %d 个、x<0 有 %d 个）"
		% [verts.size(), str(lo.snappedf(0.001)), str(hi.snappedf(0.001)), left, right])


func _all_anim_players(n: Node) -> Array:
	var out: Array = []
	if n is AnimationPlayer:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_anim_players(c))
	return out


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out

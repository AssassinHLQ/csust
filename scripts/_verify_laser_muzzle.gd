extends SceneTree
## 自检：普通状态开火 = **一颗颗发光光点**（不是光柱、枪口/命中点都没有球）。
##
## ── 三轮用户意见（每次都是看了实机之后改的口径）────────────────────────
##   2026-11-10：「普通爱丽丝普通攻击不要出现那个圆球只要激光线就可以」
##              → 关掉**枪口**那颗（`_muzzle_flash_beam()`）。
##   2026-11-11 上午（附截图，准星上一个柔和蓝球）：
##              「之前说爱丽丝普通攻击不要这个命中特效圆球」
##              → 关掉**命中点**那颗（`_spawn_beam_impact()`），当时整条路只剩一条光柱。
##   2026-11-11 下午：「这个光柱还是不好看，改成光点吧，就是发光子弹那种，
##              现在不像激光机枪像激光炮，就是还是用以前的机枪，
##              只不过改成了激光子弹」
##              → **光柱也不要了**，回到飞行弹丸（`_spawn_laser_bolt()`），
##                弹丸是一个**软边光点**（方片 + 径向渐变 + 面向相机）。
##
##   所以本探针现在查的是：**普通攻击既没有光柱、也没有带灯的爆闪球，
##   只有一颗颗飞出去的光点**；而机甲那条炮的光柱**必须还在**。
##
## ── ⚠️ 为什么不能照着 `_fx_root` 数（第一版就是这么翻车的） ─────────────
##   `weapon.gd`：`_fx_root = get_tree().root`
##   —— 特效节点是直接挂到**场景树根**上的（特效走世界坐标，不跟关卡走）。
##   所以「遍历 `_fx_root` 数球」其实是在**遍历整个关卡**：
##     · 圆柱数会数到场景里所有 `CylinderMesh`，「≥ 3 层」永远白送；
##     · 球会数到场上任何一颗球，断言随时可能因为别的东西翻车；
##     · 更糟的是「清空 `_fx_root`」= **`queue_free()` 掉整个关卡**
##       （第一版真跑了，当场报 `Cannot call method on a previously freed instance`，
##        那还是它撞上第一个已释放节点就崩了才没把场景拆光）。
##
##   正确做法是**差分**：开火前拍一次全树快照，开火后拍一次，
##   **新增的那些**才是这次开火的特效。
##   光点的网格是 `QuadMesh`（不是球也不是柱），所以它按**材质**认
##   （`_bolt_mat` 是武器自己建的，只可能贴在光点上）。
##
## ── 四组 ────────────────────────────────────────────────────────────────
##   A0 阳性对照：直接 `_muzzle_flash()`（它自带一盏灯）→ 证明差分数得到球和灯
##   A1 直接 `_spawn_laser_bolt()` → 新增 **1 个光点**（落在 a→b 上）、0 球 0 柱 0 灯
##   B  真走一遍普通开火路径 → 新增 **0 柱**（没有光柱）、0 球 0 灯、1 个光点，
##      且 `_in_flight` 非空（走的确实是老机枪那条飞行弹丸路径）
##   C  机甲开火 → **光柱必须还在**（柱 > 0）+ 炮口闪光保留（球 > 0），且不产生光点
##
## 用法（`--splat=off` 能省掉几百万点的加载，本自检不看渲染）：
##   bash _tools/run_probe.sh res://scripts/_verify_laser_muzzle.gd -- --splat=off
##   ⚠️ 不带 `--splat=off` 时 headless 加载 `game.tscn` 实测要十几分钟
##      （同伴 glb + 动画库 + 泼溅），别当成卡死了。

const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0
var _hits := 0
var _hit_pos := Vector3.ZERO


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


## 全树快照：`instance_id` → {kind, pos}。
## 「点」= 材质等于 `_bolt_mat` 的那个（光点用的是 `QuadMesh`，不是球也不是柱）；
## 「球」/「柱」按网格类型认 —— 枪口闪光、命中爆闪都是球，光柱是柱。
func _snap(bolt_mat: Variant) -> Dictionary:
	var out := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var kind := ""
		if bolt_mat != null and mi.material_override == bolt_mat:
			kind = "点"
		elif mi.mesh is SphereMesh:
			kind = "球"
		elif mi.mesh is CylinderMesh:
			kind = "柱"
		else:
			continue
		out[mi.get_instance_id()] = {"kind": kind, "pos": mi.global_position}
	for n in root.find_children("*", "OmniLight3D", true, false):
		var li := n as OmniLight3D
		out[li.get_instance_id()] = {"kind": "灯", "pos": li.global_position}
	return out


## 差分：`after` 里比 `before` **新出现**的节点 = 这段时间新建的特效。
func _diff(before: Dictionary, after: Dictionary) -> Dictionary:
	var out := {"点": [], "球": [], "柱": [], "灯": []}
	for id in after:
		if before.has(id):
			continue
		var rec: Dictionary = after[id]
		(out[String(rec["kind"])] as Array).append(rec)
	return out


## 只等几帧，**不主动释放任何特效**。
##
## ⚠️ 第一版这里是「把差分出来的节点 queue_free 掉」，结果每帧刷一屏
##    `Trying to assign invalid previously freed instance` —— 因为弹丸还挂在
##    武器的 `_in_flight` 队列里，外部把它释放掉之后，`_advance_tracers()`
##    每帧都会去读那个已释放的引用。
##    **不释放反而更干净**：特效会自己过期（光点飞到头就回收、闪光靠 Tween 收），
##    而下一组的差分只认**新增**节点，残留的旧节点不会污染计数。
func _settle() -> void:
	for _i in 3:
		await process_frame


func _kn(newf: Dictionary) -> String:
	return "点 %d  球 %d  柱 %d  灯 %d" % [
		(newf["点"] as Array).size(), (newf["球"] as Array).size(),
		(newf["柱"] as Array).size(), (newf["灯"] as Array).size()]


func _run() -> void:
	print("========== 普通攻击 = 发光光点 自检 ==========")
	var t0 := Time.get_ticks_msec()
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 15:
		await process_frame
	print("  场景就位：%.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))

	var player := level.get_node_or_null("Player")
	var wpn := player.get_node_or_null("Weapon") if player else null
	if wpn == null:
		push_error("[verify] 没有 Weapon")
		quit(1)
		return
	var bolt_mat: Variant = wpn.get("_bolt_mat")
	if bolt_mat == null:
		_check(false, "武器建出了 `_bolt_mat`（没有它就没法认光点）")
		quit(1)
		return

	print("  laser_gun = %s   beam_mode = %s   光点网格 = %s" % [
		str(wpn.get("laser_gun")), str(wpn.get("beam_mode")),
		str((wpn.get("_bolt_mesh") as Mesh).get_class())])
	_check(bool(wpn.get("laser_gun")), "普通状态 laser_gun = true")
	_check(not bool(wpn.get("beam_mode")), "普通状态 beam_mode = false（确实是普通状态）")

	var muzzle := wpn.get_node_or_null("Muzzle") as Node3D
	var mpos := muzzle.global_position if muzzle != null else Vector3.ZERO
	print("  枪口世界位置 = %s" % str(mpos.snappedf(0.01)))

	var a := Vector3(0.0, 1.2, 0.0)
	var b := Vector3(0.0, 1.2, -8.0)

	# ── A0. 阳性对照：`_muzzle_flash()` 自带一盏灯 ──
	# 「数到 0」这种断言最容易假通过（差分函数坏了、`find_children` 参数写错、
	# 节点类型判断写反……都会得到 0）。所以先造一次**确定有球有灯**的，
	# 确认同一个 `_diff()` 数得出来，再去数「应该没有」的那几组。
	print("\n── A0. 阳性对照：`_muzzle_flash()`（枪口球 + 一盏灯）──")
	var s0 := _snap(bolt_mat)
	wpn.call("_muzzle_flash", a)
	await process_frame
	var ctl := _diff(s0, _snap(bolt_mat))
	print("  新增：%s" % _kn(ctl))
	_check((ctl["球"] as Array).size() >= 1, "★ 对照：差分数得到球")
	_check((ctl["灯"] as Array).size() >= 1, "★ 对照：差分数得到灯")
	await _settle()

	# ── A1. 直接调 `_spawn_laser_bolt()` ──
	# 用两个写死的世界点，不依赖这一关的几何 —— 这组要能单独回答
	# 「光点长什么样、有没有混进光柱」，不该因为「这一枪打空了」而失去意义。
	print("\n── A1. 直接调 `_spawn_laser_bolt()` ──")
	var s1 := _snap(bolt_mat)
	wpn.call("_spawn_laser_bolt", a, b)
	await process_frame
	var bolt := _diff(s1, _snap(bolt_mat))
	print("  新增：%s" % _kn(bolt))
	_check((bolt["点"] as Array).size() == 1, "就是**一个光点**")
	_check((bolt["柱"] as Array).is_empty(), "**没有光柱**（0 个圆柱）")
	_check((bolt["球"] as Array).is_empty(), "**没有球**（枪口/命中那种爆闪球都没有）")
	_check((bolt["灯"] as Array).is_empty(), "**没有额外的灯**（光点自己不带灯）")
	if (bolt["点"] as Array).size() == 1:
		var bp: Vector3 = (bolt["点"] as Array)[0]["pos"]
		var along := (bp - a).dot((b - a).normalized())
		print("  光点位置 %s（沿弹道 %.3f m，全长 %.1f m）" % [
			str(bp.snappedf(0.01)), along, a.distance_to(b)])
		_check(along > 0.02 and along < a.distance_to(b) - 0.02,
			"光点落在 a→b 这一段**中间**（不是压在某一端）")
	await _settle()

	# ── B. 真开一枪，走 `laser_gun` 那条路径 ──
	print("\n── B. 普通状态真开一枪 ──")
	# 把弹丸调慢，好在它还没飞到时拍到 —— 顺便也让「命中火花」的延迟长到不会
	# 混进这一帧的差分里（火花是 `_spawn_impact` 建的小球，它**没有灯**）。
	var speed := float(wpn.get("tracer_speed"))
	wpn.set("tracer_speed", 2.0)
	_hits = 0
	_hit_pos = Vector3.ZERO
	var cb := func(_c, p) -> void:
		_hits += 1
		_hit_pos = p
	wpn.hit_confirmed.connect(cb)

	var s2 := _snap(bolt_mat)
	var fired := false
	for _i in 12:
		if bool(wpn.call("shoot")):
			fired = true
			break
		await process_frame
	await process_frame
	var b1 := _diff(s2, _snap(bolt_mat))
	var flying := (wpn.get("_in_flight") as Array).size()
	_check(fired, "普通状态开得出枪（`shoot()` 返回 true）")
	print("  这一枪%s；新增：%s；在飞弹丸 %d 个" % [
		("打中了 %s" % str(_hit_pos.snappedf(0.01))) if _hits > 0 else "打空了",
		_kn(b1), flying])
	_check((b1["柱"] as Array).is_empty(),
		"★ **没有光柱**（新增圆柱 0 个）—— 用户否掉的就是这个")
	_check((b1["点"] as Array).size() == 1, "新增**一个发光光点**（弹丸）")
	_check((b1["球"] as Array).is_empty(), "没有爆闪球（枪口/命中那种）")
	_check((b1["灯"] as Array).is_empty(),
		"没有带灯的爆闪（枪口球 / 命中球都会带灯，这里 0 盏）")
	_check(flying >= 1, "走的是**飞行弹丸**那条老机枪路径（`_in_flight` 非空）")
	wpn.hit_confirmed.disconnect(cb)
	wpn.set("tracer_speed", speed)
	await _settle()

	# ── C. 机甲那条炮必须还是光柱 ──
	print("\n── C. 机甲状态开火（光柱 + 炮口闪光照旧）──")
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	var carrier := player.get_node_or_null("Arisu/CarrierForm")
	if carrier == null:
		_check(false, "找得到 CarrierForm（没法验机甲那一半）")
	else:
		carrier.call("set_form", true)
		for _i in 25:
			await process_frame
		var s3 := _snap(bolt_mat)
		var fired2 := false
		for _i in 12:
			if bool(wpn.call("shoot")):
				fired2 = true
				break
			await process_frame
		await process_frame
		var c1 := _diff(s3, _snap(bolt_mat))
		print("  新增：%s   beam_mode = %s" % [_kn(c1), str(wpn.get("beam_mode"))])
		_check(fired2, "机甲状态开得出炮")
		_check(bool(wpn.get("beam_mode")), "机甲状态下 beam_mode = true")
		_check(not (c1["柱"] as Array).is_empty(),
			"★ 机甲**还是光柱**（新增 %d 个圆柱 > 0）—— 别把炮也改成光点了"
				% (c1["柱"] as Array).size())
		_check(not (c1["球"] as Array).is_empty(),
			"机甲炮口闪光**保留**（新增 %d 个球 > 0）" % (c1["球"] as Array).size())
		_check((c1["点"] as Array).is_empty(), "机甲不产生光点（光点是普通攻击专属）")

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 普通攻击 = 一颗颗发光光点；机甲仍是光柱" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)

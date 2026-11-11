extends SceneTree
## 自检：普通状态开火**只有激光线，一颗球都没有**。
##
## ── 两轮用户意见 ─────────────────────────────────────────────────────────
##   2026-11-10：「普通爱丽丝普通攻击不要出现那个圆球只要激光线就可以」
##              → 关掉**枪口**那颗（`_muzzle_flash_beam()`）。
##   2026-11-11（附截图，准星上一个柔和蓝球）：「之前说爱丽丝普通攻击不要这个
##              命中特效圆球」→ 关掉**命中点**那颗（`_spawn_beam_impact()`）。
##
##   两次是同一句话指了两个不同的球，所以本探针**两头都查**。
##
## ── ⚠️ 为什么不能照着 `_fx_root` 数（第一版就是这么翻车的） ─────────────
##   `weapon.gd:104`：`_fx_root = get_tree().root`
##   —— 特效节点是直接挂到**场景树根**上的（特效走世界坐标，不跟关卡走）。
##   所以「遍历 `_fx_root` 数球」其实是在**遍历整个关卡**：
##     · 圆柱数会数到场景里所有 `CylinderMesh`，「≥ 3 层」永远白送；
##     · 球会数到场上任何一颗球，断言随时可能因为别的东西翻车；
##     · 更糟的是「清空 `_fx_root`」= **`queue_free()` 掉整个关卡**
##       （第一版真跑了，当场报 `Cannot call method on a previously freed instance`，
##        那还是它撞上第一个已释放节点就崩了才没把场景拆光）。
##
##   正确做法是**差分**：开火前拍一次全树快照，开火后拍一次，
##   **新增的那些**才是这次开火的特效。既不用猜 `_fx_root` 的语义，
##   也不会误伤场景；A 组还拿「新圆柱必须落在这条线段上」当第二道闸。
##
## ── 三组 ────────────────────────────────────────────────────────────────
##   A. 直接调 `_spawn_beam()` 正反对照：关 → 0 球 0 灯；开 → 球 ≥ 2、灯 ≥ 2
##      （而且球要**一颗在 a、一颗在 b**，证明两个开关各管一头）
##   B. 真走一遍 `laser_gun` 开火路径：0 球 0 灯、光柱 ≥ 3 层
##   C. 机甲状态开火：炮口闪光**仍然保留**（球 > 0）—— 那是炮，不是普通攻击
##
## 用法（`--splat=off` 能省掉几百万点的加载，本自检不看渲染）：
##   bash _tools/run_probe.sh res://scripts/_verify_laser_muzzle.gd -- --splat=off
##   ⚠️ headless 加载 `game.tscn` 很慢（同伴 glb + 动画库 + 泼溅），
##      机器上并行跑着十几个会话时实测要十几分钟。别当成卡死了。

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


## 全树快照：`instance_id` → {kind, pos}。只记三类「特效会长成的东西」。
func _snap() -> Dictionary:
	var out := {}
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var kind := ""
		if mi.mesh is SphereMesh:
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
	var out := {"球": [], "柱": [], "灯": [], "nodes": []}
	for id in after:
		if before.has(id):
			continue
		var rec: Dictionary = after[id]
		out["nodes"].append(instance_from_id(id))
		match String(rec["kind"]):
			"球":
				out["球"].append(rec)
			"柱":
				out["柱"].append(rec)
			"灯":
				out["灯"].append(rec)
	return out


## 只清掉**差分认出来的**那些节点。
## ⚠️ 绝不要图省事去遍历 `_fx_root`（= 场景树根）清 —— 那是拆关卡，见文件头。
func _drop(newf: Dictionary) -> void:
	for n in newf["nodes"]:
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
	for _i in 3:
		await process_frame


func _run() -> void:
	print("========== 激光「只有一条线」自检 ==========")
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

	print("  laser_gun = %s   beam_mode = %s" % [
		str(wpn.get("laser_gun")), str(wpn.get("beam_mode"))])
	_check(bool(wpn.get("laser_gun")), "普通状态 laser_gun = true")
	_check(not bool(wpn.get("beam_mode")), "普通状态 beam_mode = false（确实是普通状态）")

	var muzzle := wpn.get_node_or_null("Muzzle") as Node3D
	var mpos := muzzle.global_position if muzzle != null else Vector3.ZERO
	print("  枪口世界位置 = %s" % str(mpos.snappedf(0.01)))

	# ── A. 直接调 `_spawn_beam()`：正反对照 ──
	# 用两个写死的世界点，不依赖这一关的几何 —— 这条自检要能单独回答
	# 「两个开关到底管不管用」，不该因为「这一枪打空了」而失去意义。
	print("\n── A. 直接调 `_spawn_beam()`（不经过开火）──")
	var a := Vector3(0.0, 1.2, 0.0)
	var b := Vector3(0.0, 1.2, -8.0)
	var mid := (a + b) * 0.5

	var s0 := _snap()
	wpn.call("_spawn_beam", a, b, false, false)
	await process_frame
	var off := _diff(s0, _snap())
	print("  两个开关都关：球 %d  灯 %d  柱 %d" % [
		(off["球"] as Array).size(), (off["灯"] as Array).size(), (off["柱"] as Array).size()])
	_check((off["柱"] as Array).size() >= 3,
		"光柱还在（新增 %d 个圆柱）" % (off["柱"] as Array).size())
	# 第二道闸：这些圆柱必须落在 a→b 这一段上，否则数到的可能是别的东西
	var stray := 0
	for rec in off["柱"]:
		if (rec["pos"] as Vector3).distance_to(mid) > 5.0:
			stray += 1
	_check(stray == 0, "新增圆柱都落在这条线段上（跑偏 %d 个）" % stray)
	_check((off["球"] as Array).is_empty(), "枪口球 + 命中球**都没建**（0 个）")
	_check((off["灯"] as Array).is_empty(), "命中点那盏灯**也没建**（0 盏）")
	await _drop(off)

	var s1 := _snap()
	wpn.call("_spawn_beam", a, b, true, true)
	await process_frame
	var on := _diff(s1, _snap())
	print("  两个开关都开：球 %d  灯 %d  柱 %d" % [
		(on["球"] as Array).size(), (on["灯"] as Array).size(), (on["柱"] as Array).size()])
	# ★ 阳性对照：同一个 `_diff()` 必须数得出来，否则上面那两个 0 不算数
	_check((on["球"] as Array).size() >= 2,
		"★ 对照：开关打开时数得出球（%d 个 ≥ 2）" % (on["球"] as Array).size())
	var near_a := 0
	var near_b := 0
	for rec in on["球"]:
		var p: Vector3 = rec["pos"]
		if p.distance_to(a) < 0.5:
			near_a += 1
		if p.distance_to(b) < 0.6:
			near_b += 1
	_check(near_a >= 1, "★ 对照：有一颗在 a（枪口闪光，%d 颗）" % near_a)
	_check(near_b >= 1, "★ 对照：有一颗在 b（命中爆闪，%d 颗）" % near_b)
	_check((on["灯"] as Array).size() >= 2,
		"★ 对照：数得出灯（%d 盏 ≥ 2）" % (on["灯"] as Array).size())
	await _drop(on)

	# ── B. 真开一枪，走 `laser_gun` 那条路径 ──
	print("\n── B. 普通状态真开一枪 ──")
	_hits = 0
	_hit_pos = Vector3.ZERO
	var cb := func(_c, p) -> void:
		_hits += 1
		_hit_pos = p
	wpn.hit_confirmed.connect(cb)

	var s2 := _snap()
	var fired := false
	for _i in 12:
		if bool(wpn.call("shoot")):
			fired = true
			break
		await process_frame
	await process_frame
	await process_frame
	var b1 := _diff(s2, _snap())
	_check(fired, "普通状态开得出枪（`shoot()` 返回 true）")
	if _hits > 0:
		print("  这一枪打中了：落点 %s" % str(_hit_pos.snappedf(0.01)))
	else:
		print("  这一枪**打空了**（300 m 内没东西）—— 命中那半只能靠 A 组对照")
	print("  新增：球 %d  灯 %d  柱 %d" % [
		(b1["球"] as Array).size(), (b1["灯"] as Array).size(), (b1["柱"] as Array).size()])
	_check((b1["球"] as Array).is_empty(),
		"普通攻击一颗球都没有（整条弹道 0 个，枪口和命中点都没有）")
	_check((b1["灯"] as Array).is_empty(), "命中点那盏灯也没有（0 盏）")
	_check((b1["柱"] as Array).size() >= 3,
		"激光光柱**在**（新增 %d 个圆柱）" % (b1["柱"] as Array).size())
	wpn.hit_confirmed.disconnect(cb)
	await _drop(b1)

	# ── C. 机甲状态仍保留炮口闪光 ──
	print("\n── C. 机甲状态开火（炮口闪光应保留）──")
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	var carrier := player.get_node_or_null("Arisu/CarrierForm")
	if carrier == null:
		_check(false, "找得到 CarrierForm（没法验机甲那一半）")
	else:
		carrier.call("set_form", true)
		for _i in 25:
			await process_frame
		var s3 := _snap()
		var fired2 := false
		for _i in 12:
			if bool(wpn.call("shoot")):
				fired2 = true
				break
			await process_frame
		await process_frame
		await process_frame
		var c1 := _diff(s3, _snap())
		print("  新增：球 %d  灯 %d  柱 %d   beam_mode = %s" % [
			(c1["球"] as Array).size(), (c1["灯"] as Array).size(),
			(c1["柱"] as Array).size(), str(wpn.get("beam_mode"))])
		_check(fired2, "机甲状态开得出炮")
		_check(bool(wpn.get("beam_mode")), "机甲状态下 beam_mode = true")
		_check(not (c1["球"] as Array).is_empty(),
			"机甲炮口闪光**保留**（新增 %d 个球 > 0）" % (c1["球"] as Array).size())
		await _drop(c1)

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 普通攻击只有一条激光线" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)

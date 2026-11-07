extends SceneTree
## 自检：跑酷的「坐火箭」双向载具（`scripts/rocket_ride.gd`）。
##
## 覆盖：
##   ① Falcon 9 GLB 真的载进来了、尺寸对（70 m × 5.05 m、非占位）
##   ② 去程：通关 → 传送门 + 火箭一起立在跑道口 → 踩进去 → 起飞 → 落岛上停机位 → 出舱点对
##   ③ 骑乘锁：飞行中玩家 `is_riding()` 为真、被抬到空中；落地后解除
##   ④ 落地**就地停住**（不再瞬移回起点），另一枚空载摆渡到空出来的那头补位
##   ⑤ 回程：传送台旁一直有一枚在等（不再懒生成）→ 飞回跑道口 → **落在传送门脚下**
##   ⑥ 防重复触发：飞行途中再踩触发盒不会二次起飞
##   ⑦ 两枚火箭从头到尾都在两个停机位上，从不叠在一起
##
## 用法：_tools/run_probe.sh res://scripts/_verify_rocket.gd
##
## ⚠️ 时间基准一律用 `physics_frame`：headless 下进程帧跑得飞快，
##    按 `process_frame` 计数等不到真实物理时间（`_verify_economy` 那边同源注释）。

const RocketRideScript := preload("res://scripts/rocket_ride.gd")
const GLB_PATH := "res://models/rocket_falcon9/falcon9.glb"

var _fail := 0
var _pass := 0
var _lvl: Node3D
var _player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ %s" % msg)


func _run() -> void:
	print("========== 火箭载具自检 ==========")

	_lvl = (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_lvl)
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	for _i in 30:
		await physics_frame

	# ── ① 模型本体 ──
	print("\n---------- 1. Falcon 9 模型 ----------")
	_check(ResourceLoader.exists(GLB_PATH), "GLB 在位：%s" % GLB_PATH)
	var probe := RocketRideScript.new()
	root.add_child(probe)
	await physics_frame
	_check(not probe.is_placeholder(), "用的是真 GLB，不是程序化占位")
	_check(is_equal_approx(probe.height(), 70.0 * probe.rocket_scale),
		"缩放生效：rocket_scale=%.2f → 箭高 %.1f m" % [probe.rocket_scale, probe.height()])

	# ⚠️ 这条是**补洞**用的，不是重复：`height()` 只是 `70 × scale` 的算术值。
	#    曾经 `park_at()` 里 `_model.basis = Basis.IDENTITY` 把 scale 冲成 1.0，
	#    火箭实际是 70 m 高，而 `height()` 照样报 21.0 —— 上面那条断言完全看不出来。
	#    必须量**世界包围盒**才抓得到。`_pivot` 那层就是为此加的。
	probe.call("park_at", Vector3.ZERO)
	await physics_frame
	var wbox := _world_aabb(probe)
	_check(absf(wbox.size.y - probe.height()) < 1.0,
		"实际世界高度 %.1f m ≈ height() %.1f m（缩放没被 basis 冲掉）" % [
			wbox.size.y, probe.height()])
	# 模型挂在 `Pivot` 下面（旋转层与缩放层分开，见 rocket_ride.gd 里 `var _pivot`）
	var model := probe.get_node_or_null("Pivot/Model") as Node3D
	if model == null:
		model = probe.get_node_or_null("Model") as Node3D
	_check(model != null, "Model 子节点存在（Pivot/Model）")
	if model != null:
		var mi := model.find_children("*", "MeshInstance3D", true, false)
		_check(mi.size() > 0, "模型里有 MeshInstance3D（%d 个）" % mi.size())
		var tris := 0
		for n in mi:
			var m := (n as MeshInstance3D).mesh
			if m == null:
				continue
			for s in m.get_surface_count():
				var idx = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				tris += ((idx as PackedInt32Array).size() / 3) if (idx != null
					and (idx as PackedInt32Array).size() > 0) else 0
		_check(tris > 100000, "面数合理：%d 三角面" % tris)
	probe.queue_free()
	await physics_frame

	# ── ② 去程 ──
	print("\n---------- 2. 去程：跑道口 → 结算屋 ----------")
	var launch := _lvl.get_node_or_null("Launch") as Node3D
	var shed := _lvl.get_node_or_null("Island/Props/Shed") as Node3D
	_check(launch != null and shed != null, "Launch / Shed 都在")

	_lvl.call("_on_run_finished", 60.0, 55.0)
	for _i in 10:
		await physics_frame
	var portal := _lvl.get_node_or_null("FinishPortal") as Node3D
	var rocket := _lvl.get("_finish_rocket") as Node3D
	_check(portal != null, "通关后传送门立在跑道口")
	_check(rocket != null, "火箭随传送门一起就位")
	if rocket != null:
		_check(rocket.global_position.distance_to(portal.global_position) < 0.5,
			"火箭和门同格：火箭 %s / 门 %s" % [
				str(rocket.global_position.snappedf(0.1)),
				str(portal.global_position.snappedf(0.1))])

	if portal == null or rocket == null:
		_summary()
		return

	# 踩进触发盒
	_player.global_position = portal.global_position + Vector3(0.0, 1.0, 0.0)
	_player.velocity = Vector3.ZERO
	var g := 0
	while not bool(_lvl.get("_riding")) and g < 60:
		g += 1
		await physics_frame
	_check(bool(_lvl.get("_riding")), "踩门 → 起飞（`_riding` = true）")

	# ── ③ 骑乘锁 + 被抬到空中 ──
	print("\n---------- 3. 骑乘锁 ----------")
	_check(_player.has_method("is_riding") and bool(_player.call("is_riding")),
		"玩家被锁住（`is_riding()` = true，输入已被接管）")

	var peak_y := _player.global_position.y
	var ticks := 0
	var takeoff := rocket.global_position
	while bool(_lvl.get("_riding")) and ticks < 900:
		ticks += 1
		await physics_frame
		peak_y = maxf(peak_y, _player.global_position.y)
	_check(ticks > 0, "飞行持续 %d 物理帧（≈ %.2f s）" % [ticks, float(ticks) / 60.0])
	_check(peak_y > 20.0, "中途被抬到空中：最高 y = %.1f m（地面 y ≈ 0）" % peak_y)
	_check(not bool(_player.call("is_riding")), "落地后骑乘锁已解除")

	# ── ② 续：出舱点 ──
	var expect_exit := shed.global_position + Vector3(0.0, 0.1, 0.6)
	var d_exit := _player.global_position.distance_to(expect_exit)
	_check(d_exit < 0.5,
		"人落在结算屋出舱点：距 %.2f m（期望 < 0.5）" % d_exit)
	var d_shed := _player.global_position.distance_to(shed.global_position)
	_check(d_shed < 2.0, "人离结算屋 %.2f m（期望 < 2，和改前的断言同口径）" % d_shed)

	# ── ④ 就地停住 + 另一枚补位 ──
	print("\n---------- 4. 落地就地停住 + 另一枚补位 ----------")
	var island_spot: Vector3 = _lvl.call("_island_spot")
	var home_spot: Vector3 = _lvl.call("_home_spot")
	var d_land := rocket.global_position.distance_to(island_spot)
	_check(d_land < 0.5,
		"载人那枚落在岛上停机位 %s：偏差 %.2f m（< 0.5）" % [
			str(island_spot.snappedf(0.1)), d_land])
	var flew := rocket.global_position.distance_to(takeoff)
	_check(flew > 500.0,
		"确实飞过去了：起点 %s → 落点相距 %.0f m（> 500）" % [
			str(takeoff.snappedf(0.1)), flew])
	var other := _lvl.call("_other_rocket", rocket) as Node3D
	_check(other != null, "另一枚火箭存在（两枚常驻，不是懒生成）")
	if other != null:
		var d_ferry := other.global_position.distance_to(home_spot)
		_check(d_ferry < 0.5,
			"另一枚空载摆渡回了跑道口停机位 %s：偏差 %.2f m（< 0.5）" % [
				str(home_spot.snappedf(0.1)), d_ferry])
		var gap := other.global_position.distance_to(rocket.global_position)
		_check(gap > 5.0, "两枚没有叠在一起：相距 %.1f m（> 5）" % gap)
		_check(not bool(other.call("is_riding")),
			"摆渡那枚已经落地（没有半悬在空中）")

	# ── ⑥ 防重复触发 ──
	print("\n---------- 6. 防重复触发 ----------")
	# 先把人放回门内，让第一次骑乘重新开始
	_player.global_position = portal.global_position + Vector3(0.0, 1.0, 0.0)
	g = 0
	while not bool(_lvl.get("_riding")) and g < 60:
		g += 1
		await physics_frame
	var started := bool(_lvl.get("_riding"))
	# 飞到一半，再把人塞回触发盒一次
	var half := 0
	while bool(_lvl.get("_riding")) and half < 60:
		half += 1
		await physics_frame
	_player.global_position = portal.global_position + Vector3(0.0, 1.0, 0.0)
	for _i in 5:
		await physics_frame
	# 只应该还在飞同一趟，而不是重新计时回第一段
	_check(started and bool(_lvl.get("_riding")),
		"飞行中再踩触发盒：仍然只有一趟在飞，没有二次起飞")
	# 等它飞完，别把状态留给下一节
	var fin := 0
	while bool(_lvl.get("_riding")) and fin < 900:
		fin += 1
		await physics_frame

	# ── ⑤ 回程 ──
	print("\n---------- 5. 回程：岛上传送台 → 跑道口 ----------")
	var pad := _lvl.get_node_or_null("Island/Props/ReturnPad") as Node3D
	_check(pad != null, "Island/Props/ReturnPad 存在")
	# 用户 2026-11-07：「火箭是我站在传送台才出现的，不是一直在那儿等着的」
	var waiting := _lvl.call("_rocket_at", island_spot) as Node3D
	_check(waiting != null, "传送台旁**一直**有一枚火箭在等（开场就造好，不是踩上去才冒出来）")
	if pad != null and waiting != null:
		var near_pad := waiting.global_position.distance_to(pad.global_position)
		_check(near_pad < 6.0, "它离传送台 %.1f m（< 6，站上台就能看见它）" % near_pad)
		_player.global_position = pad.global_position + Vector3(0.0, 0.10, 0.0)
		_player.velocity = Vector3.ZERO
		var h := 0
		while not bool(_lvl.get("_riding")) and h < 60:
			h += 1
			await physics_frame
		_check(bool(_lvl.get("_riding")), "踩传送台 → 回程火箭起飞")
		var t2 := 0
		while bool(_lvl.get("_riding")) and t2 < 900:
			t2 += 1
			await physics_frame
		var target: Vector3 = _lvl.get("return_target")
		var d_back := _player.global_position.distance_to(target)
		_check(d_back < 0.5,
			"人落在 return_target：距 %.2f m（期望 < 0.5）" % d_back)
		# 用户 2026-11-07：「火箭落地不是传送门那一块」—— 现在必须正好落在门脚下
		var d_gate := waiting.global_position.distance_to(home_spot)
		_check(d_gate < 0.5,
			"回程落在传送门脚下 %s：偏差 %.2f m（< 0.5）" % [
				str(home_spot.snappedf(0.1)), d_gate])
		_check(_lvl.get("checkpoint") == -1 and not bool(_lvl.get("timer_running")),
			"回程后检查点/计时已清空（`reset_run()` 在骑乘结束后才调）")

	_summary()


func _summary() -> void:
	print("\n==========================================")
	print("火箭自检：通过 %d，失败 %d" % [_pass, _fail])
	print("==========================================")
	if _lvl != null and is_instance_valid(_lvl):
		_lvl.queue_free()
	quit(0 if _fail == 0 else 1)


## 节点下所有可见网格的世界包围盒（量真实尺寸用，别信算术值）
func _world_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is VisualInstance3D and (n as VisualInstance3D).is_visible_in_tree():
			var vi := n as VisualInstance3D
			var b := vi.get_aabb()
			if b.size.length() > 0.0001:
				var wb := vi.global_transform * b
				out = wb if first else out.merge(wb)
				first = false
		for c in n.get_children():
			stack.append(c)
	return out

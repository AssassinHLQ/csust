extends SceneTree
## 验七名同伴（未花 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊）：
##   1. 都在场、模型建好、骨架/动画绑定、都在「朋友层」
##   2. 子弹**穿透**同伴（不会挡自己的输出）—— 并做反向对照，证明屏蔽是必要的
##   3. 跟随：玩家跑开 14 m，同伴追上来并把站位收回来
##   4. 动画状态：走动时不是 Idle，站住后回到 Idle
##   5. 保险：被扔出平台会立刻拉回
##   6. 不挡镜头（不在画面中心区域，且两两在屏幕上分开）
##   7. **朝向**：脸朝「节点 +Z」（用世界坐标下的眼骨算）+ **接地**（脚骨世界 y）
##   8. 渲图
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_verify_companion.gd -- --splat=off

const COMPANIONS := [
	"CompanionKoyuki", "CompanionYuuka", "CompanionNoa",
	"CompanionMomoi", "CompanionMidori", "CompanionYuzu", "CompanionKei",
]

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _steps(30)

	var player: Player = game.get_node("Player")
	var list: Array[Companion] = []
	for n in COMPANIONS:
		list.append(game.get_node(n) as Companion)

	print("========== 1. 七名同伴就位 ==========")
	_check(list.size() == 7, "场景里有 7 名同伴")
	for c in list:
		var skel := _best_skeleton(c)
		var ap := _first_player(c)
		var h := _local_height(c)
		print("  %-4s 模型 %-12s 骨架 %3d 骨  动画 %2d 个  layer=%d mask=%d  身高 %.2f m" % [
			c.display_name, c.model_path.get_file(),
			skel.get_bone_count() if skel else 0,
			ap.get_animation_list().size() if ap else 0,
			c.collision_layer, c.collision_mask, h])
		_check(c.model != null, "%s：模型已实例化" % c.display_name)
		_check(skel != null and skel.get_bone_count() > 50,
			"%s：骨架找对了（%d 骨）" % [c.display_name, skel.get_bone_count() if skel else 0])
		# ⚠️ 这里查的必须是**本工程真的会播**的三条：驱动按速度在 `Normal_Idle` /
		#    `Cafe_Walk`（走路）/ `Move_Ing`（跑）之间切。
		#    `Cafe_Walk` 里武器骨被素材缩到 ≈0（走路不拿枪），但它是用户要的走路姿势，§1.17。
		_check(ap != null and ap.has_animation("Normal_Idle")
			and ap.has_animation("Cafe_Walk") and ap.has_animation("Move_Ing"),
			"%s：动画找到 Normal_Idle / Cafe_Walk / Move_Ing（待机 / 走 / 跑）"
			% c.display_name)
		_check(c.collision_layer == Companion.LAYER and c.collision_mask == 1,
			"%s：在朋友层（layer=%d mask=%d）" % [c.display_name, c.collision_layer, c.collision_mask])
		_check(h > 1.0 and h < 1.9, "%s：身高 %.2f m 在合理区间" % [c.display_name, h])

	print("\n========== 2. 子弹穿透同伴 ==========")
	# 把优香搬到「玩家 → Target1」的弹道正中间，从玩家眼高打一条射线过去
	var target: Target = game.get_node("Target1")
	var yuuka := game.get_node("CompanionYuuka") as Companion
	player.global_position = Vector3(6, 0.05, -4)
	yuuka.global_position = Vector3(6, 0.05, -7)
	await _steps(5)
	var from := Vector3(6, 1.2, -4)
	var to := Vector3(6, 1.2, -10)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	print("  射线 %s → %s（优香站在 z=−7 挡在中间）" % [str(from), str(to)])
	print("     屏蔽朋友层 → 命中 %s" % str(hit.get("collider")) if hit else "     屏蔽朋友层 → 空")
	_check(hit.size() > 0 and hit.get("collider") == target, "子弹穿过同伴命中 Target1")
	# 反向对照：不屏蔽朋友层的话确实会被同伴挡住 —— 说明这条屏蔽不是多余的
	var q2 := PhysicsRayQueryParameters3D.create(from, to)
	q2.collide_with_areas = false
	q2.exclude = [player.get_rid()]
	var hit2 := player.get_world_3d().direct_space_state.intersect_ray(q2)
	print("     不屏蔽     → 命中 %s" % (str(hit2.get("collider")) if hit2 else "空"))
	_check(hit2.size() > 0 and hit2.get("collider") == yuuka,
		"（反向对照）不屏蔽朋友层时确实被同伴挡住")

	print("\n========== 3. 跟随 ==========")
	# 玩家往前（−Z）跑 14 m，同伴应该追上来
	yuuka.global_position = Vector3(2, 0.05, 6.9)
	for c in list:
		c.global_position = c.slot_position()   # 先摆回各自站位，从零开始量
	await _steps(5)
	player.global_position = Vector3(0, 0.05, -8)

	var moving_clip := ""
	# ⚠️ 这里原本是 `for i in 200: await physics_frame` —— **固定物理帧数不可靠**：
	#    Godot 每个渲染帧最多推进 8 个物理步（`max_physics_steps_per_frame`），
	#    渲染帧率一旦掉到 7.5 fps 以下，物理时间就比真实时间**慢**，
	#    「200 物理帧」不再等于 3.33 秒。加了设置界面之后帧率略降，这条就随机红了。
	#    改成「等条件 + 超时兜底」：通常 3 秒内到位；真坏了超时后照样断言失败。
	var waited := 0
	while waited < 480:
		await physics_frame
		waited += 1
		if waited == 60:
			for c in list:
				var clip := _clip(c)
				if clip != "Normal_Idle":
					moving_clip = clip
					break
		if waited > 60 and _all_close(list, 2.5):
			break
	var dists: Array[float] = []
	for c in list:
		dists.append(c.slot_distance())
	print("  玩家瞬移到 (0, −8) 后等 200 物理帧：")
	for i in list.size():
		print("     %-4s 与站位差 %.2f m" % [list[i].display_name, dists[i]])
	var all_close := true
	for d in dists:
		if d >= 2.5:
			all_close = false
	_check(all_close, "七名同伴都跟上了（与各自站位差 < 2.5 m）")
	print("  追赶途中采样到的动作：%s" % ("（只采到 Idle）" if moving_clip.is_empty() else moving_clip))
	_check(not moving_clip.is_empty(), "追赶途中播的是移动动作，不是原地滑步")

	print("\n========== 4. 站住回到 Idle ==========")
	# 同理：等「都回到 Idle」，而不是等固定帧数
	await _wait_until(func() -> bool:
		for c in list:
			if _clip(c) != "Normal_Idle":
				return false
		return true, 8.0)
	for c in list:
		print("  %-4s 站定后动作 = %s（速度 %.2f m/s）" % [c.display_name, _clip(c), c.speed()])
		_check(_clip(c) == "Normal_Idle", "%s：站定后回到 Normal_Idle" % c.display_name)

	print("\n========== 5. 保险（掉出平台）==========")
	var noa := game.get_node("CompanionNoa") as Companion
	noa.global_position = Vector3(0, -200, 0)
	await _steps(5)
	print("  把诺亚扔到 y=−200 之后：y=%.1f，与站位差 %.2f m" % [
		noa.global_position.y, noa.slot_distance()])
	_check(noa.global_position.y > -10.0, "掉出平台后立刻被拉回")
	_check(noa.slot_distance() < 3.0, "拉回后回到站位附近")

	print("\n========== 6. 不挡镜头 ==========")
	# ⚠️ 先把玩家瞬移回出生点，**必须等同伴走回来**再量：
	#    本喵第一版忘了等，结果量到的是还在 14 m 外往回赶的三个小点，
	#    屏幕坐标全挤在画面中心，白白红了三条。移动类断言要等物理帧跑够。
	player.global_position = Vector3(0, 0.05, 6)
	player._yaw = 0.0
	player.rig.rotation.y = 0.0
	player._pitch = -0.04
	# ⚠️ 必须等到**真的站定**（同伴自己的 `stop_distance` 是 0.45 m）。
	#    下面两条屏幕位置断言对站位极敏感：只等到「差 < 1 m」的话，
	#    「柚子不在画面中央」和「七人互相分开」会随那 1 m 上下浮动（实测稳定红）。
	await _wait_until(func() -> bool: return _all_close(list, 0.5), 15.0)
	var back := true
	for c in list:
		if c.slot_distance() > 0.6:
			back = false
	_check(back, "七名同伴都走回站位（差 < 0.6 m）")

	# “挡镜头”真正要防的是两件事：**贴脸**（离相机太近）和**占屏太大**。
	# 一开始本喵用的是「不许进画面中心 50% 区域」——太糙了：
	# 水平 FOV 94°（fov 62° 是垂直、16:9 换算），中心 50% 宽对应 ±28°，
	# 侧后方站位本来就在 25° 左右，用那条判据会把正常站位也判红。
	var cam := player.cam
	var vp := Vector2(root.size)
	var xs: Array[float] = []
	for c in list:
		var head: Vector3 = c.global_position + Vector3.UP * 1.5
		var feet: Vector3 = c.global_position + Vector3.UP * 0.05
		var dist := cam.global_position.distance_to(c.global_position)
		var behind := cam.is_position_behind(c.global_position)
		var sp := cam.unproject_position(head)
		var px := absf(cam.unproject_position(head).y - cam.unproject_position(feet).y)
		xs.append(sp.x)
		print("  %-4s 距相机 %.2f m  屏幕 x=%.0f  屏幕高度 %.0f px（视口 %d×%d）" % [
			c.display_name, dist, sp.x, px, int(vp.x), int(vp.y)])
		_check(not behind, "%s 在相机前方（看得见）" % c.display_name)
		_check(dist > 2.5, "%s 离相机 %.2f m（> 2.5，不会糊脸）" % [c.display_name, dist])
		_check(px < vp.y * 0.6, "%s 屏幕高度 %.0f px < 视口高的 60%%" % [c.display_name, px])
		_check(absf(sp.x - vp.x * 0.5) > vp.x * 0.1,
			"%s 不在画面正中央 20%% 宽度内（偏离 %.0f px）" % [
				c.display_name, absf(sp.x - vp.x * 0.5)])

	# 站位是跟着**相机绕角**转的，所以「侧向 ÷ 纵深」比例相同的两人会**永远重叠**
	# （诺亚原来就是这么被未花挡掉的，屏幕 x 451 vs 463）。这条守着「三个人都看得见」。
	var min_gap := 1.0e9
	for i in xs.size():
		for j in range(i + 1, xs.size()):
			min_gap = minf(min_gap, absf(xs[i] - xs[j]))
	var xs_txt: Array[String] = []
	for x in xs:
		xs_txt.append("%.0f" % x)
	print("  三人屏幕 x = [%s]   两两最小间距 %.0f px" % [", ".join(xs_txt), min_gap])
	_check(min_gap > 60.0, "七人屏幕位置互相分开（最小间距 %.0f px > 60）" % min_gap)

	print("\n========== 7. 朝向 + 接地（2026-10-14 那个 bug 的回归锁）==========")
	# 背景：companion.gd 原来给 Rig 补了 180°，理由是「GLB 本体朝 −Z」。
	# 那条结论是量 Toe−Foot 时**漏乘 skeleton.global_transform**得出的（骨骼空间 ≠ 模型空间），
	# 于是七只同伴的脸全朝「节点 −Z」；而 _physics_process 又把节点 +Z 设成移动方向，
	# 结果它们**倒着走**（画面证据：scripts/_probe_companion_row.gd 的 row_front/row_back）。
	# 现在 Rig 不动，脸必须朝 +Z。
	#
	# ⚠️ 阈值只取 0.2（判「在哪半边」），不取 0.5：这些骨骼判据有**固有残差**
	#    —— 眼骨在头局部带横向偏移、腿部/肩部的绑定姿态也不是标准 T-pose，
	#    实测同一批模型在 0.35~1.00 之间浮动。但判反的那一版是 −0.35~−1.00，
	#    符号完全分开，0.2 这条线抓得住，而且不会被姿态噪声弄红。
	for c in list:
		var skel := _best_skeleton(c)
		var fwd := _rest_torso_forward(skel)
		var face := _rest_face(skel)
		var node_z := c.global_transform.basis.z
		node_z.y = 0.0
		node_z = node_z.normalized()
		var dot := fwd.dot(node_z)
		var dot_face := face.dot(node_z)
		var foot_y := _lowest_foot_y(skel)
		var pair := _rest_lr_pair(skel, ["thigh", "upleg"])
		var used := "%s / %s" % [pair.get("lname", "?"), pair.get("rname", "?")] if not pair.is_empty() else "（没找到腿骨）"
		print("  %-4s 躯干朝向·节点+Z = %+.2f（行进方向）  眼骨参考 %+.2f  脚骨世界 y = %+.3f  用骨：%s" % [
			c.display_name, dot, dot_face, foot_y, used])
		_check(dot > 0.2, "%s：躯干朝向朝行进方向（点积 %+.2f > 0.2，不是倒着走）" % [
			c.display_name, dot])
		_check(dot_face > 0.2, "%s：眼骨方向也在前半轴（参考判据 %+.2f > 0.2）" % [
			c.display_name, dot_face])
		_check(absf(foot_y) < 0.15, "%s：脚踩在地上（脚骨世界 y %+.3f）" % [
			c.display_name, foot_y])

	print("\n========== 8. 渲图 ==========")
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_companion")
	DirAccess.make_dir_recursive_absolute(out)
	await _shot(out.path_join("80_spawn_with_companions.png"))

	# 把镜头拉远抬高，让七名同伴同框（相机在玩家背后 9 m、俯角 20°）
	player.spring.spring_length = 9.0
	player._pitch = -0.35
	await _steps(40)
	await _shot(out.path_join("81_companions_group.png"))

	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


# --- 工具 ---

## 躯干朝向（世界坐标、绑定姿态）：**两腿连线 × 上方向**。
##
## 为什么用腿而不用肩或眼：
##   * 眼骨在头局部带横向偏移，实测与身体正前方差到 ~70°；
##   * 肩（UpperArm/Clavicle）受绑定姿态影响 —— 这批模型不是标准 T-pose，
##     手臂在绑定姿态里就带着角度，实测未花/诺亚用肩量只能得到 +0.35（≈69° 偏差）；
##   * **腿在绑定姿态里是并拢竖直的**，左右大腿连线几乎正好是横向量，量出来最干净。
##
## 约定：Godot 是右手系（+X 右、+Y 上），本项目里「模型本体朝 +Z」。
## 面朝 +Z 的人，**右手在 −X 侧**（右手系里 右 × 上 = −前），所以：
##   右向量 = 右腿位置 − 左腿位置 = −X
##   前 = 上 × 右 = Y × (−X) = +Z ✓
## ⚠️ 别写成 `右 × 上` —— 那样得到的是 −前，七只同伴会集体判成「反了」（本喵就这么错过一次）。
func _rest_torso_forward(skel: Skeleton3D) -> Vector3:
	if skel == null:
		return Vector3.ZERO
	var pair := _rest_lr_pair(skel, ["thigh", "upleg"])
	if pair.is_empty():
		pair = _rest_lr_pair(skel, ["upperarm", "clavicle", "shoulder"])
	if pair.is_empty():
		return Vector3.ZERO
	var right: Vector3 = pair["r"] - pair["l"]
	right.y = 0.0
	if right.length() < 0.0001:
		return Vector3.ZERO
	return Vector3.UP.cross(right.normalized()).normalized()


## 在绑定姿态下找一组「左 / 右」同名骨，返回它们的世界坐标
func _rest_lr_pair(skel: Skeleton3D, keys: Array) -> Dictionary:
	var l := -1
	var r := -1
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		var hit := false
		for k in keys:
			if low.contains(String(k)):
				hit = true
				break
		if not hit:
			continue
		if low.contains(" l ") or low.contains("left") or low.begins_with("l_"):
			if l < 0:
				l = i
		elif low.contains(" r ") or low.contains("right") or low.begins_with("r_"):
			if r < 0:
				r = i
	if l < 0 or r < 0:
		return {}
	var xf := skel.global_transform
	return {"l": xf * skel.get_bone_global_rest(l).origin,
			"r": xf * skel.get_bone_global_rest(r).origin,
			"lname": skel.get_bone_name(l), "rname": skel.get_bone_name(r)}


## 脸在**绑定姿态**下、世界坐标里的方向：两眼中点 − 头骨。**只当参考**，不做断言：
## 眼骨横向偏移可达 70°，但符号仍然能区分「正 / 反」。
##
## ⚠️ 必须乘 skeleton 的 global_transform —— 只算骨骼空间会因为 Skeleton3D 自带的
##    180° 得到**反的符号**（2026-10-14 的倒着走 bug 就是这么判出来的）。
func _rest_face(skel: Skeleton3D) -> Vector3:
	if skel == null:
		return Vector3.ZERO
	var eyes: Array[int] = []
	var head := -1
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if low.contains("eye"):
			eyes.append(i)
		if head < 0 and low.contains("head"):
			head = i
	if eyes.size() < 2 or head < 0:
		return Vector3.ZERO
	var xf := skel.global_transform
	var mid := Vector3.ZERO
	for e in eyes:
		mid += xf * skel.get_bone_global_rest(e).origin
	mid /= float(eyes.size())
	var h: Vector3 = xf * skel.get_bone_global_rest(head).origin
	var d := mid - h
	d.y = 0.0
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


## 最低的脚骨（Toe/Foot）在世界坐标下的 y —— 判断有没有浮空/埋地
func _lowest_foot_y(skel: Skeleton3D) -> float:
	if skel == null:
		return 0.0
	var xf := skel.global_transform
	var best := INF
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if low.contains("toe") or low.contains("foot") or low.contains("ankle"):
			best = minf(best, (xf * skel.get_bone_global_pose(i).origin).y)
	return 0.0 if best == INF else best


func _clip(c: Companion) -> String:
	if c.anim == null or not c.anim.has_method("current_clip"):
		return "?"
	return c.anim.current_clip()


## 同伴的视觉高度，量在同伴节点自己的局部空间里。
##
## ⚠️ 三个口径**取最大值**。真实尺寸不会小于其中任何一个，而「哪个口径在哪个文件上
## 恰好失灵」是不可预知的，单用哪一个都会误报：
##   1. 网格原始包围盒：`MeshInstance3D.get_aabb()` 是**未蒙皮**的盒，朝向随导出器
##      的节点规整而变。凯伊重导后（`Kei_ext.glb`，见 README §8.8）从 1.71 m 掉到
##      0.58 m，但屏幕上像素高度只从 185 变 179 —— 纯度量口径，不是外观回归。
##   2. 骨架 rest 骨头在**骨架局部空间**的跨度：与姿态无关，但依赖骨架自身朝向
##      （凯伊原文件 0.68 m、重导版 1.09 m）。
##   3. 骨架当前姿态在**世界空间**的跨度：会受当时动作影响（走路时腿是弯的）。
## 反例：米卡的骨架跨度只有 0.83~0.93 m，实际身高却是 1.39 m —— 所以也不能只用骨架。
func _local_height(node: Node3D) -> float:
	return maxf(_aabb_height(node), maxf(_rest_height(node), _skel_height(node)))


func _aabb_height(node: Node3D) -> float:
	var to_local := node.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for m in _all(node, "VisualInstance3D"):
		var vi := m as VisualInstance3D
		if not vi.visible:
			continue
		var b: AABB = to_local * (vi.global_transform * vi.get_aabb())
		if b.size.length() <= 0.0001:
			continue
		out = b if first else out.merge(b)
		first = false
	return out.size.y


## 骨架 rest 姿态、在骨架局部空间里的 Y 跨度（与当前姿势无关）
func _rest_height(node: Node3D) -> float:
	var sk := _best_skeleton(node)
	if sk == null or sk.get_bone_count() == 0:
		return 0.0
	var lo := 1e9
	var hi := -1e9
	for i in sk.get_bone_count():
		var p := sk.get_bone_rest(i).origin
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return hi - lo


## 骨架当前姿态在世界空间里的 Y 跨度
func _skel_height(node: Node3D) -> float:
	var sk := _best_skeleton(node)
	if sk == null or sk.get_bone_count() == 0:
		return 0.0
	var lo := 1e9
	var hi := -1e9
	for i in sk.get_bone_count():
		var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return hi - lo


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("  [img] %s" % path)


func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in _all(node, "Skeleton3D"):
		var sk := s as Skeleton3D
		if best == null or sk.get_bone_count() > best.get_bone_count():
			best = sk
	return best


## 七名同伴是否都已走到各自站位的 `limit` 米内 —— 给「等条件」用
func _all_close(list: Array, limit: float) -> bool:
	for c in list:
		if c.slot_distance() >= limit:
			return false
	return true


## 等条件成立，**最多等 `timeout_sec` 秒**。
## ⚠️ 超时后返回 false，调用方照常断言 —— 所以「等」只是消掉「时间不够」的假红，
##    不会把真问题盖掉（真坏了就等满超时、然后照样红）。
## ⚠️ 超时按**真实时间**判，不按帧数：`await physics_frame` 在低渲染帧率下会被
##    `max_physics_steps_per_frame` 限流，物理时间比真实时间慢。
func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout_sec * 1000.0):
		if cond.call():
			return true
		await physics_frame
	return cond.call()


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _first(node: Node, cls: String) -> Node:
	var r := _all(node, cls)
	return r[0] if not r.is_empty() else null


## 找**基础层**那个 `AnimationPlayer`（要认得出 `Normal_Idle`）。
##
## ⚠️ 不能再用「找到的第一个 AnimationPlayer」：§1.18 / §1.20 之后每个模型里都有**三个**
##    播放器 —— 基础层 + 两层叠加（`UpperBody` 静止 / `UpperBodyMove` 移动，它们只有
##    开火 / 换弹，没有 `Normal_Idle`）。`_all()` 是**栈式**遍历，返回顺序不保证，所以
##    「第一个」随时可能是叠加层 —— 加了叠加层之后这里 7 只同伴集体变红就是这么来的。
func _first_player(node: Node) -> AnimationPlayer:
	for n in _all(node, "AnimationPlayer"):
		var a := n as AnimationPlayer
		if a != null and a.has_animation("Normal_Idle"):
			return a
	return null


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_fail += 1


func _steps(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

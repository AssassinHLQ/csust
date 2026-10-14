extends SceneTree
## 验「画室609」这块新场地：场景结构、加载、摆放、floaters 裁剪、HUD 多行、
## 以及用户报告的「玩家 Arisu 模型朝向反了」是否真的修好了。
##
## 用法（要真渲染，不要 --headless）：
##   godot --path <工程> --script res://scripts/_verify_room.gd
## 首次会解码 277 万点（约 21 s）；有缓存时约 1 s。
##
## 为什么不用 --venue=room：命令行参数是给**玩家**用的开关，这里要在入树前
## 亲手摘掉校园那份，顺便把「场景里到底摆了哪几块场地」也当成一项断言。

var _fail := 0
var _pass := 0

const ROOM_NAME := "Room609"
const CAMPUS_NAME := "SplatScene"
## 量出来的期望值（splatdata/README.md 里同步记着），对不上就是有人改了场景
const EXPECT_POINTS := 2769851
const EXPECT_SCALE := 6.4
const EXPECT_YAW := 248.6
const FLOOR_Y := 0.03


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()

	print("========== 1. 场景结构（两块场地的标签）==========")
	var campus: SplatScene = game.get_node_or_null(CAMPUS_NAME) as SplatScene
	var room: SplatScene = game.get_node_or_null(ROOM_NAME) as SplatScene
	_check(campus != null, "场景里有校园 %s" % CAMPUS_NAME)
	_check(room != null, "场景里有画室609 %s" % ROOM_NAME)
	if room == null:
		print("\n画室609 节点不存在，后面没法验")
		_quit()
		return
	if campus != null:
		_check(campus.venue == "campus", "校园 venue = campus（实测 %s）" % campus.venue)
		_check(campus.display_name == "校园", "校园 display_name = 校园")
	_check(room.venue == "room", "画室609 venue = room（实测 %s）" % room.venue)
	_check(room.display_name == "画室609", "画室609 display_name = 画室609")
	_check(room.sog_path.ends_with("room609.sogdata"),
		"数据源 = room609.sogdata（实测 %s）" % room.sog_path)
	_check(is_equal_approx(room.world_scale, EXPECT_SCALE),
		"world_scale = %.1f（实测 %.2f）" % [EXPECT_SCALE, room.world_scale])
	_check(absf(room.yaw_degrees - EXPECT_YAW) < 0.05,
		"yaw = %.1f（实测 %.2f）" % [EXPECT_YAW, room.yaw_degrees])
	_check(not room.auto_place, "auto_place 关掉（房间不能居中下沉）")
	_check(room.use_anchor, "use_anchor 打开（地板对到平台地面）")
	_check(room.crop_enabled, "crop_enabled 打开（裁离群 floaters）")
	_check(is_equal_approx(room.crop_max_scale, 0.5), "crop_max_scale = 0.5")

	# 入树前摘掉校园：_ready() 是 add_child 时才跑的，此刻摘掉就不会开始解码
	if campus != null:
		campus.free()
	root.add_child(game)
	await _wait(10)

	var player: Player = game.get_node_or_null("Player")
	var hud: CanvasLayer = game.get_node_or_null("HUD")

	print("\n========== 2. 加载 ==========")
	var guard := 0
	while guard < 60000 and not room.is_ready():
		await process_frame
		guard += 1
	_check(room.is_ready(), "画室609 泼溅节点已建立")
	if not room.is_ready():
		_quit()
		return
	print("  点数 = %d   耗时 = %.1f s" % [room.point_count, room.elapsed_seconds])
	print("  裁剪 = %s" % str(room.crop_stats))
	_check(room.point_count == EXPECT_POINTS,
		"裁后点数 = %s（实测 %s）" % [_fmt(EXPECT_POINTS), _fmt(room.point_count)])
	_check(int(room.crop_stats.get("dropped", 0)) > 0,
		"确实裁掉了点（丢 %d 个）" % int(room.crop_stats.get("dropped", 0)))
	_check(int(room.crop_stats.get("scale_dropped", 0)) > 0,
		"确实按椭球尺度裁过（丢 %d 个）" % int(room.crop_stats.get("scale_dropped", 0)))
	_check(room.elapsed_seconds > 0.0, "记录了加载耗时 %.1f s" % room.elapsed_seconds)

	# 采一遍点：世界坐标 + 源索引（后面地板 / 主轴 / 椭球复检都用它）
	var cloud := _sample_world(room, 200000)
	_check(bool(cloud.get("ok", false)), "取到点云样本")
	if not bool(cloud.get("ok", false)):
		_quit()
		return
	var pts: PackedVector3Array = cloud["points"]
	print("  采样 %d 点（每 %d 点取 1）" % [pts.size(), int(cloud["step"])])

	print("\n========== 3. 摆放（地板对齐 y≈0、平台中央、轴对齐）==========")
	var aabb := room.content_world_aabb()
	var c := aabb.get_center()
	print("  内容世界包围盒 pos %s size %s" % [
		str(aabb.position.snappedf(0.1)), str(aabb.size.snappedf(0.1))])
	print("  顶面 y = %.2f   平台 40 × 40 m" % room.content_top_y())
	# ⚠️ 别写死哪个轴更长：yaw 248.6 把源数据的墙对转到和世界轴平行，
	#    量出来是 36.0（X）× 41.0（Z）—— 和上一版（歪 39.5° 时的 34.6 × 40.3）
	#    是同一个房间在不同朝向下的外接盒，别按记下来的数字硬判。
	var span_lo := maxf(aabb.size.x, aabb.size.z)
	var span_hi := minf(aabb.size.x, aabb.size.z)
	print("  XZ 占地 %.1f × %.1f m（平台 40 × 40）" % [aabb.size.x, aabb.size.z])
	_check(span_lo > 36.0 and span_lo < 44.0, "长边 %.1f m：铺满平台" % span_lo)
	_check(span_hi > 30.0, "短边 %.1f m：也接近满场" % span_hi)
	_check(aabb.size.y > 9.0 and aabb.size.y < 16.0, "世界高 %.1f m" % aabb.size.y)

	# 地板平面：竖向直方图峰值（**不能**用 content_min.y 代替 —— 裁剪盒外扩过，
	# 最低点可以比地板还低）
	var floor := _floor_plane(pts)
	print("  地板平面 y = %.3f（直方图峰值，样本 %d 点）  地板质心 = (%.2f, %.2f)" % [
		floor["y"], floor["count"], floor["cx"], floor["cz"]])
	_check(absf(floor["y"] - FLOOR_Y) < 0.2,
		"地板贴在平台地面 y ≈ %.2f（实测 %.3f）" % [FLOOR_Y, floor["y"]])
	_check(absf(floor["cx"]) < 2.0 and absf(float(floor["cz"])) < 2.0,
		"地板质心落在平台中央（%.2f, %.2f）" % [floor["cx"], floor["cz"]])
	# 地板以下几米是重建噪声（扫地机扫到楼板底面那种），反正被平台实体挡住看不见。
	# 要防的是「整块内容沉下去」，所以按**比例**判，不按最低点判。
	var below := 0
	for p in pts:
		if p.y < -1.0:
			below += 1
	var below_pct := 100.0 * float(below) / float(maxi(pts.size(), 1))
	print("  平台地面以下的点 = %d / %d（%.2f%%）" % [below, pts.size(), below_pct])
	_check(below_pct < 3.0, "地面以下只有零散重建噪声（%.2f%% < 3%%）" % below_pct)

	# 房间矩形轴对齐。⚠️ 三种「看起来合理」的量法在这间房上全都定不出角度：
	#   ① XZ 协方差主轴 —— 地板 4.87 × 5.40 源单位，**接近正方形**，两个方向的方差
	#      几乎相等，主轴数值不稳定（实测跳到 51°，把结果说成「歪 39°」）
	#   ② 最小面积外接矩形（整朵点云）—— 面积比只有 1.083，谷太浅
	#   ③ 最小面积外接矩形（地板层）—— 地板被桌椅挡掉一块，根本不是完整矩形
	# 改用**墙直方图的峰值集中度**：轴对齐时两道 x 墙会在 x 直方图里叠成尖峰，
	# 集中度 Σn²/N² 就大；歪了峰就摊平。这是对「近正方形房间」唯一稳健的量法。
	var sweep := _axis_sweep(pts)
	print("  墙直方图集中度（x 峰 + z 峰）：0° = %.4f，最优 = %.4f（在 %+.2f°）" % [
		sweep["at0"], sweep["best_value"], sweep["folded"]])
	print("    x 轴 %.5f → %.5f    z 轴 %.5f → %.5f（两轴都变尖才算真的矩形对齐）" % [
		sweep["x_at0"], sweep["x_best"], sweep["z_at0"], sweep["z_best"]])
	print("  角谱 %s" % sweep["profile"])
	print("  → 要轴对齐，yaw 还得再转 %+.2f°：%.1f → %.1f" % [
		sweep["folded"], room.yaw_degrees, room.yaw_degrees + float(sweep["folded"])])
	_check(sweep["ok"], "轴对齐扫描跑通")
	_check(sweep["best_value"] / maxf(sweep["at0"], 1e-9) < 1.05,
		"房间矩形轴对齐（集中度只比最优低 %.1f%%）" % [
			(1.0 - sweep["at0"] / maxf(sweep["best_value"], 1e-9)) * 100.0])
	_check(absf(float(sweep["folded"])) < 1.0,
		"最优朝向就在 0°（实测 %+.2f°）" % sweep["folded"])
	# 合成自检：人为把点云转 +23°，扫出来的角度应该正好少 23° —— 锁住符号方向。
	# 比之前先把两者折到同一支（mod 90）：矩形转 90° 还是同一个矩形，峰本来就重复。
	var synth := _axis_sweep(_rotate_xz(pts, 23.0))
	var want_deg: float = float(sweep["folded"]) - 23.0
	var diff: float = fposmod(float(synth["folded"]) - want_deg + 45.0, 90.0) - 45.0
	print("  合成自检：点云人为转 +23° 后扫出 %+.2f°（应比 %+.2f° 少 23°，即 %+.2f°；差 %+.2f°）" % [
		synth["folded"], sweep["folded"], want_deg, diff])
	_check(absf(diff) < 1.0, "扫描的符号方向对得上（合成自检）")

	print("\n========== 4. 离群 floaters 裁干净了 ==========")
	var worst := _worst_sigma(room, cloud["indices"])
	print("  裁后最大椭球尺度 = %.4f（阈值 %.2f）" % [worst, room.crop_max_scale])
	_check(worst <= room.crop_max_scale + 0.001,
		"裁后没有超标椭球（%.4f ≤ %.2f）" % [worst, room.crop_max_scale])
	var top_y := room.content_top_y()
	_check(top_y < 13.5, "房间顶面 %.2f m 正常（没把 floaters 算进去）" % top_y)
	# ⚠️ 不能断言「没有点高过 99.9‰ 顶面」—— 那是分位数，本来就有 0.1% 的点在上面
	#    （实测 213k 样本里有 107 个，纯属定义）。真正要防的是**裁之前**那种离群椭球：
	#    源坐标尺度能到 15.13，×6.4 就是 97 m 高的一团白。
	var highest := -INF
	for p in pts:
		highest = maxf(highest, p.y)
	print("  采样点最高 y = %.2f m（裁之前 floaters 会到约 97 m）" % highest)
	_check(highest < 15.0, "最高的点只到 %.2f m，没有飘在天上的白团" % highest)

	print("\n========== 5. HUD 一场一行 ==========")
	var row0: Label = hud.get_node_or_null("SplatStatus0") as Label
	_check(row0 != null, "HUD 有第 0 行泼溅状态")
	if row0 != null:
		_check(row0.text.contains("画室609"), "第 0 行写的是画室609（%s）" % row0.text)
	# 再塞一份假场地，验多行排版真的会往下排、信号真的按**行号**路由
	var dummy := SplatScene.new()
	dummy.display_name = "测试场地"
	hud.call("bind_splats", [room, dummy])
	var row1: Label = hud.get_node_or_null("SplatStatus1") as Label
	_check(row1 != null, "绑两份时出现第 1 行")
	# 直接发 loaded 信号：编号如果没绑对，这一行会拿到别处的文字
	dummy.loaded.emit({"point_count": 1234, "elapsed": 0.5, "from_cache": true})
	await _wait(2)
	if row0 != null and row1 != null:
		_check(absf(row1.position.y - row0.position.y - 20.0) < 0.01,
			"两行相差 20 px（实测 %.1f）" % (row1.position.y - row0.position.y))
		_check(row1.text.contains("测试场地") and row1.text.contains("1,234"),
			"第 1 行收到的是自己的进度（%s）" % row1.text)
		_check(row0.text.contains("画室609"),
			"重新绑定后第 0 行还是画室609（%s）" % row0.text)
	# 先重绑（会把假场地的信号摘掉）再 free，顺序反了会留下悬空连接
	hud.call("bind_splats", [room])
	dummy.free()

	print("\n========== 6. 玩家 Arisu 的朝向（用户报告的问题）==========")
	_check(player != null, "场景里有 Player")
	if player != null:
		await _wait(30)
		var real_fwd := -player.cam.global_transform.basis.z
		real_fwd.y = 0.0
		real_fwd = real_fwd.normalized()
		var want := Vector3(sin(player._facing_yaw), 0.0, cos(player._facing_yaw)).normalized()
		print("  相机视线 = %s   角色脸朝向 = %s" % [
			str(real_fwd.snappedf(0.01)), str(want.snappedf(0.01))])
		_check(player._facing_yaw == player._yaw + PI,
			"_facing_yaw = _yaw + PI（%.3f = %.3f + PI）" % [player._facing_yaw, player._yaw])
		_check(is_equal_approx(player.model_root.rotation.y, player._facing_yaw),
			"model_root.rotation.y 没被 player.tscn 的遗留 180° 盖掉")
		_check(want.dot(real_fwd) > 0.95,
			"角色脸朝向 = 相机视线（点积 %.3f > 0.95，反了会是 −1）" % want.dot(real_fwd))

		# 骨骼级复检：绑定姿态下的躯干前方，乘 skeleton.global_transform（见同伴自检注释）
		var skel := _best_skeleton(player.model_root)
		_check(skel != null, "找到 Arisu 的 Skeleton3D")
		if skel != null:
			# 先把「到底取了哪两根骨、在哪」打出来 —— 判朝向出错十次有九次是这里的锅
			var pair := _rest_lr_pair(skel, ["thigh", "upleg"])
			if pair.is_empty():
				print("  ⚠️ 没找到左右大腿骨对")
			else:
				print("  取的左右骨：L = %s @ %s   R = %s @ %s   （世界坐标）" % [
					pair["lname"], str((pair["l"] as Vector3).snappedf(0.01)),
					pair["rname"], str((pair["r"] as Vector3).snappedf(0.01))])
			print("  绑姿躯干前方（仅供参考，见下方注释）= %s   眼睛参考 = %s   最低脚骨 y = %.3f" % [
				str(_rest_torso_forward(skel).snappedf(0.01)),
				str(_rest_face(skel).snappedf(0.01)), _lowest_foot_y(skel)])
			_check(absf(_lowest_foot_y(skel)) < 0.25,
				"脚踩在平台上（y = %.3f）" % _lowest_foot_y(skel))

			# ⚠️ **不能**用大腿骨左右配对判 Arisu 的朝向：她这套骨架里
			#    `Bip001 L Thigh` 和 `Bip001 R Thigh` 的间距只有 1 cm
			#    （实测 L(−0.01, 0.26, 5.93) / R(0.00, 0.26, 6.07)，几乎全落在 Z 上），
			#    也就是「左/右」在这个绑定姿态里根本没有横向分离，配对本就是退化的；
			#    它给出的「前方」和渲染出来的脸差了 90°。同伴那七套 GLB 没这个问题，
			#    所以 `_verify_companion.gd` 的骨骼判据可以照用，这里不行。
			#    改用**几何事实**：嘴那几块网格（README §2.1：Mouth_401…Mouth_705）
			#    相对骨盆的水平方向，就是脸朝哪边。
			var mouth := _mouth_forward(player.model_root, skel)
			print("  嘴网格相对骨盆的方向 = %s" % str(mouth.snappedf(0.01)))
			_check(mouth != Vector3.ZERO, "找到嘴网格并量出方向")
			_check(mouth.dot(real_fwd) > 0.5,
				"嘴朝向 = 相机视线（点积 %.3f > 0.5，反了会是负数）" % mouth.dot(real_fwd))

	print("\n========== 7. 渲图 ==========")
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_room609")
	DirAccess.make_dir_recursive_absolute(out)

	if player != null:
		# ① 出生点默认视角（应看到黑板那一面 + 同伴后背）
		_pose(player, Vector3(0, 0.05, 6), 0.0, -0.04)
		await _wait(40)
		await _shot(out.path_join("70_spawn.png"))

		# ② 房间中央平视
		_pose(player, Vector3(0, 0.05, -2), 0.0, -0.10)
		await _wait(40)
		await _shot(out.path_join("71_inside.png"))

		# ③ 在中央低头看地板（验地板真的在脚下、纹理方向正）
		_pose(player, Vector3(0, 0.05, -2), 0.0, -0.75)
		await _wait(40)
		await _shot(out.path_join("72_lookdown.png"))

		# ④ 横着看整间房（**验轴对齐最直观的一张**：对面墙、天花板灯带、墙脚线
		#    都该是水平的）。⚠️ 站位只能在**中轴过道**上 —— 玩家相机在背后 3.5 m，
		#    站到靠墙的位置会把镜头塞进桌子里（本喵试过 −15 和 +16，糊成一片）。
		_pose(player, Vector3(0, 0.05, -2), -PI * 0.5, -0.05)
		await _wait(40)
		await _shot(out.path_join("73_along_wall.png"))

		# ⑤ 沿中轴从房间一端往另一端看
		_pose(player, Vector3(0, 0.05, 9), 0.0, -0.04)
		await _wait(40)
		await _shot(out.path_join("74_down_the_room.png"))

		# ⑥ 正面看 Arisu：玩家相机永远在背后，所以临时插一台相机到她**正前方**。
		#    这张和 ①（背后）是一对 —— 一张看到后脑，一张看到脸，朝向对不对一眼就知。
		_pose(player, Vector3(0, 0.05, 0), 0.0, -0.10)
		await _wait(30)
		await _shot_player_front(player, out.path_join("75_face_from_front.png"))

	# ⑦ 高看整个场地：房间有没有真铺满 40 × 40 平台、矩形有没有摆正
	var top := Camera3D.new()
	root.add_child(top)
	top.fov = 60.0
	top.global_position = Vector3(0, 34, 30)
	top.look_at(Vector3(0, 3, -2), Vector3.UP)
	top.make_current()
	await _wait(30)
	await _shot(out.path_join("76_room_overview.png"))
	top.queue_free()

	print("\n================ 结果 ================")
	print("成功 %d 项，失败 %d 项" % [_pass, _fail])
	_quit()


# --- 摆放测量 ---------------------------------------------------------------

## 地板平面 = 世界 y 直方图的峰值（0.05 m 一格），再用峰格 ±1 格的点求质心
func _floor_plane(pts: PackedVector3Array) -> Dictionary:
	const BIN := 0.05
	var lo := -6.0
	var bins := 500
	var hist := PackedInt32Array()
	hist.resize(bins)
	for p in pts:
		var k := int(floor((p.y - lo) / BIN))
		if k >= 0 and k < bins:
			hist[k] += 1
	var best := 0
	for k in bins:
		if hist[k] > hist[best]:
			best = k
	var peak_y := lo + (float(best) + 0.5) * BIN
	var sum := Vector3.ZERO
	var n := 0
	for p in pts:
		if absf(p.y - peak_y) < BIN * 1.5:
			sum += p
			n += 1
	if n == 0:
		return {"y": peak_y, "cx": 0.0, "cz": 0.0, "count": 0}
	var mean := sum / float(n)
	return {"y": mean.y, "cx": mean.x, "cz": mean.z, "count": n}


## 每 n 点取 1，把点云降到规模可控（扫角度是 O(点数 × 角度数)）
func _subsample(pts: PackedVector3Array, max_n: int) -> PackedVector3Array:
	var step := maxi(1, pts.size() / maxi(max_n, 1))
	var out := PackedVector3Array()
	var i := 0
	while i < pts.size():
		out.append(pts[i])
		i += step
	return out


## 取高度在 y0 ± half 之间的一层（地板层 / 天花板层）
func _slab(pts: PackedVector3Array, y0: float, half: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pts:
		if absf(p.y - y0) < half:
			out.append(p)
	return out


## 房间矩形有没有轴对齐：绕 Y 扫一圈，找 x 直方图「峰值集中度」最大的角度。
## 返回的 best_deg 含义：把当前世界点云再转这么多度就轴对齐了，
## 也就是 game.tscn 里 yaw_degrees 需要加上它。
## 范围取 −90…90：集中度对矩形是 **mod 90 重复**的（转 90° 墙还是墙），
## 只扫 ±45 会把另一个峰切在窗口外（合成自检就是被这个坑到的）。
func _axis_sweep(pts: PackedVector3Array) -> Dictionary:
	var sample := _subsample(pts, 6000)
	if sample.size() < 200:
		return {"ok": false}
	var at0 := _wall_peakiness(sample, 0.0)
	var best := at0
	var coarse := 0.0
	var profile := ""
	var d := -90.0
	while d <= 90.0:
		var v := _wall_peakiness(sample, d)
		if v > best:
			best = v
			coarse = d
		if absf(fposmod(d, 10.0)) < 0.01:
			profile += "%+.0f:%.4f " % [d, v]
		d += 1.0
	var fine := coarse
	var d2 := coarse - 1.0
	while d2 <= coarse + 1.0:
		var v2 := _wall_peakiness(sample, d2)
		if v2 > best:
			best = v2
			fine = d2
		d2 += 0.1
	return {
		"ok": true, "at0": at0, "best_value": best, "best_deg": fine, "profile": profile,
		# 峰对矩形是 mod 90° 重复的（转 90° 墙还是墙），所以折到 (−45, 45] 再报，
		# 免得「已经对齐了」却报成「还要转 +90°」。
		"folded": fposmod(fine + 45.0, 90.0) - 45.0,
		"x_at0": _wall_peakiness_axis(sample, 0.0, 0), "z_at0": _wall_peakiness_axis(sample, 0.0, 1),
		"x_best": _wall_peakiness_axis(sample, fine, 0), "z_best": _wall_peakiness_axis(sample, fine, 1),
	}


## 两轴之和：**只有真的矩形对齐时 x 峰和 z 峰才会同时变尖**。
## 只看一根轴的话，一排桌子、一条走道都能凑出一个假峰。
func _wall_peakiness(pts: PackedVector3Array, deg: float) -> float:
	return _wall_peakiness_axis(pts, deg, 0) + _wall_peakiness_axis(pts, deg, 1)


## 单轴峰值集中度 Σn²/N²：转 deg 度之后按该轴打 0.25 m 直方图。
## 两道墙落在同一格时集中度最大；歪一点峰就摊到相邻格里，集中度掉下来。
## ⚠️ 旋转用 Godot 的约定（+Z 转向 +X）：x' = x·cos + z·sin，z' = −x·sin + z·cos。
##    别写成 x' = x·cos − z·sin —— 那样扫出来的角度符号是反的（合成自检就是防这个）。
func _wall_peakiness_axis(pts: PackedVector3Array, deg: float, axis: int) -> float:
	var r := deg_to_rad(deg)
	var cs := cos(r)
	var sn := sin(r)
	var n := pts.size()
	var vs := PackedFloat32Array()
	vs.resize(n)
	var lo := INF
	var hi := -INF
	for i in n:
		var p: Vector3 = pts[i]
		var v := (p.x * cs + p.z * sn) if axis == 0 else (-p.x * sn + p.z * cs)
		vs[i] = v
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 0.001:
		return 0.0
	var nb := maxi(4, int((hi - lo) / 0.25) + 1)
	var scale := float(nb) / (hi - lo)
	var hist := PackedInt32Array()
	hist.resize(nb)
	for i in n:
		hist[clampi(int((vs[i] - lo) * scale), 0, nb - 1)] += 1
	var s := 0.0
	for c in hist:
		s += float(c) * float(c)
	return s / (float(n) * float(n))


## 把点云整体绕 Y 转 deg 度（Godot 约定），用来做轴对齐扫描的合成自检
func _rotate_xz(pts: PackedVector3Array, deg: float) -> PackedVector3Array:
	var r := deg_to_rad(deg)
	var cs := cos(r)
	var sn := sin(r)
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i in pts.size():
		var p: Vector3 = pts[i]
		out[i] = Vector3(p.x * cs + p.z * sn, p.y, -p.x * sn + p.z * cs)
	return out


## 取世界坐标样本 + 源索引（索引用来回 point_data_byte 复检椭球尺度）
func _sample_world(room: SplatScene, max_samples: int) -> Dictionary:
	var node := room.splat_node
	if node == null:
		return {"ok": false}
	var res: Resource = node.get("gaussian")
	if res == null:
		return {"ok": false}
	var count := int(res.get("point_count"))
	var xyz: PackedVector3Array = res.get("xyz")
	if xyz.size() != count:
		return {"ok": false, "message": "xyz %d ≠ 点数 %d" % [xyz.size(), count]}
	var xf: Transform3D = room.global_transform * node.transform
	var step := maxi(1, count / maxi(max_samples, 1))
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	var i := 0
	while i < count:
		pts.append(xf * xyz[i])
		idx.append(i)
		i += step
	return {"ok": true, "points": pts, "indices": idx, "step": step}


## 采样点上最大的椭球标准差（sqrt(协方差对角)），用来复检 floaters 真被裁了
func _worst_sigma(room: SplatScene, indices: PackedInt32Array) -> float:
	var res: Resource = room.splat_node.get("gaussian")
	var bytes: PackedByteArray = res.get("point_data_byte")
	var worst := 0.0
	for i in indices:
		var off := int(i) * 240
		if off + 40 > bytes.size():
			break
		for f in [4, 7, 9]:
			worst = maxf(worst, sqrt(maxf(bytes.decode_float(off + f * 4), 0.0)))
	return worst


# --- 朝向测量（和 _verify_companion.gd 同一套，别改符号）---------------------

## 约定：Godot 右手系，本项目模型本体朝 +Z。面朝 +Z 的人右手在 −X 侧，所以
## 右 = 右腿 − 左腿 = −X，前 = 上 × 右 = +Z。⚠️ 写成 `右 × 上` 会得到 −前。
func _rest_torso_forward(skel: Skeleton3D) -> Vector3:
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


## 眼睛中点 − 头骨（绑姿）。只当参考不断言：眼骨横向偏得多，但符号能分清正/反。
func _rest_face(skel: Skeleton3D) -> Vector3:
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
	var d := mid - (xf * skel.get_bone_global_rest(head).origin)
	d.y = 0.0
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


func _lowest_foot_y(skel: Skeleton3D) -> float:
	var xf := skel.global_transform
	var best := INF
	for i in skel.get_bone_count():
		var low := skel.get_bone_name(i).to_lower()
		if low.contains("toe") or low.contains("foot") or low.contains("ankle"):
			best = minf(best, (xf * skel.get_bone_global_pose(i).origin).y)
	return 0.0 if best == INF else best


## 脸朝向的**几何**量法：嘴网格的中心 减 骨盆骨的位置，取水平分量。
## 嘴长在脸前面、骨盆在身体中轴上，所以这个方向就是「前」。
## 用嘴网格而不是骨骼配对，是因为 Arisu 骨架的左右大腿几乎不分离（见 §6 注释）。
func _mouth_forward(model_root: Node, skel: Skeleton3D) -> Vector3:
	var pelvis := -1
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower().contains("pelvis"):
			pelvis = i
			break
	if pelvis < 0:
		return Vector3.ZERO
	var base: Vector3 = skel.global_transform * skel.get_bone_global_rest(pelvis).origin
	var sum := Vector3.ZERO
	var n := 0
	for item in _all(model_root, "MeshInstance3D"):
		var mi := item as MeshInstance3D
		if mi.mesh == null or not mi.name.to_lower().contains("mouth"):
			continue
		sum += mi.global_transform * mi.get_aabb().get_center()
		n += 1
	if n == 0:
		return Vector3.ZERO
	var d := (sum / float(n)) - base
	d.y = 0.0
	return d.normalized() if d.length() > 0.0001 else Vector3.ZERO


# --- 工具 -------------------------------------------------------------------

func _pose(player: Player, pos: Vector3, yaw: float, pitch: float) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player._yaw = yaw
	player._facing_yaw = yaw + PI
	player.model_root.rotation.y = player._facing_yaw
	player.rig.rotation.y = yaw
	player._pitch = pitch


## 临时把相机放到角色**正前方**回看（玩家相机永远在背后，看不到脸）
func _shot_player_front(player: Player, path: String) -> void:
	var face := Vector3(sin(player._facing_yaw), 0.0, cos(player._facing_yaw))
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 38.0
	cam.global_position = player.global_position + face * 2.6 + Vector3.UP * 1.30
	cam.look_at(player.global_position + Vector3.UP * 1.15, Vector3.UP)
	cam.make_current()
	await _wait(20)
	await _shot(path)
	cam.queue_free()
	player.cam.make_current()


func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in _all(node, "Skeleton3D"):
		var sk := s as Skeleton3D
		if best == null or sk.get_bone_count() > best.get_bone_count():
			best = sk
	return best


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.is_class(cls):
			out.append(n)
		for ch in n.get_children():
			stack.append(ch)
	return out


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("  [img] %s" % path)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
		_pass += 1
	else:
		print("  [FAIL] ", label)
		_fail += 1


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _fmt(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func _quit() -> void:
	quit(1 if _fail > 0 else 0)

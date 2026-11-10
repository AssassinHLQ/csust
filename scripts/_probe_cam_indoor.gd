extends SceneTree
## 复现 / 回归：**室内**相机疯狂抖动（用户 2026-11-10 第三轮）。
##
## 用户原话：「运镜空地正常，一进入建筑就疯狂抖动」。
##
## 假设：`_collide_camera_arm()` 每帧对 5 条射线取 min，得到一个"墙允许的最大臂长"。
##   空地上这个值恒为 INF（永不压缩）→ 臂长恒定 → 稳。
##   室内画面边缘的射线（水平半角最宽到 ±47°）会不停地在**门洞 / 墙角**上进进出出，
##   于是"允许的臂长"在 ~1.1 m 和 ~4.2 m 之间来回翻，阻尼跟着追 → 疯狂抖。
##
## 本探针自己搭一间带门洞的屋子（不依赖校园场景），量三个指标：
##   - `反向次数`：相邻帧位移的符号翻转次数。平滑跟随只有几次，翻来覆去会有几十上百次。
##   - `单帧最大位移`：一帧最多走了多少米。
##   - `穿墙帧数`：相机是否落到墙的后面（安全项，必须为 0）。
##
##   godot --headless --script res://scripts/_probe_cam_indoor.gd -- --splat=off --story=off --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const GAME := "res://scenes/game.tscn"

## 屋子中心：放到远离校园本体的地方，避免被别的碰撞体干扰。
const ROOM := Vector3(200.0, 0.0, 200.0)
const HALF := 4.0          # 半边长
const WALL_H := 3.0        # 墙高
const DOOR_HALF := 0.6     # +Z 墙上那道门洞的半宽
const WALL_T := 0.3        # 墙厚
## 判定"这一帧算不算一次跳变"
const JERK := 0.25

var _p: CharacterBody3D
var _spring: SpringArm3D
var _cam: Camera3D
var _space: PhysicsDirectSpaceState3D
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


## 造一块静态碰撞盒（当墙 / 地板 / 天花板）。
func _box(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	body.add_child(cs)
	_p.get_parent().add_child(body)
	body.global_position = pos


## 带门洞的屋子：地板 + 天花板 + 四面墙（+Z 那面留一个 1.2 m 宽的门洞）。
func _build_room() -> void:
	var c := ROOM
	_box(Vector3(HALF * 2 + WALL_T * 2, WALL_T, HALF * 2 + WALL_T * 2),
		c + Vector3(0, -WALL_T * 0.5, 0))                       # 地板
	_box(Vector3(HALF * 2 + WALL_T * 2, WALL_T, HALF * 2 + WALL_T * 2),
		c + Vector3(0, WALL_H + WALL_T * 0.5, 0))               # 天花板
	_box(Vector3(WALL_T, WALL_H, HALF * 2), c + Vector3(-HALF, WALL_H * 0.5, 0))  # -X
	_box(Vector3(WALL_T, WALL_H, HALF * 2), c + Vector3(HALF, WALL_H * 0.5, 0))   # +X
	_box(Vector3(HALF * 2, WALL_H, WALL_T), c + Vector3(0, WALL_H * 0.5, -HALF))  # -Z
	# +Z 墙：门洞两侧各一段 + 门楣
	var seg_w := (HALF * 2 - DOOR_HALF * 2.0) * 0.5
	var seg_x := DOOR_HALF + seg_w * 0.5
	_box(Vector3(seg_w, WALL_H, WALL_T), c + Vector3(-seg_x, WALL_H * 0.5, HALF))
	_box(Vector3(seg_w, WALL_H, WALL_T), c + Vector3(seg_x, WALL_H * 0.5, HALF))
	_box(Vector3(DOOR_HALF * 2.0, WALL_H - 2.1, WALL_T),
		c + Vector3(0, 2.1 + (WALL_H - 2.1) * 0.5, HALF))


## 相机有没有落到墙后面（穿墙）。地板 / 天花板不算。
## 顺便把命中的东西记到 `_clip_what` 里，方便打印。
var _clip_what := ""

func _clipped() -> bool:
	var origin := _spring.global_position
	var to := _cam.global_position
	var d := to - origin
	_clip_what = ""
	if d.length_squared() < 0.0001:
		return false
	var q := PhysicsRayQueryParameters3D.create(origin, to, 1, [_p.get_rid()])
	var h := _space.intersect_ray(q)
	if h.is_empty():
		return false
	var n: Vector3 = h.get("normal", Vector3.UP)
	if absf(n.y) > 0.85:
		return false
	var col: Object = h.get("collider")
	var cname := "?"
	if col is Node:
		cname = (col as Node).name
	_clip_what = "命中 %s  法线 %s  距离 %.2f（相机在 %.2f）  支点 %s 相机 %s" % [
		cname, str(n.snappedf(0.01)), origin.distance_to(h["position"]), d.length(),
		str(origin.snappedf(0.01)), str(to.snappedf(0.01))]
	return origin.distance_to(h["position"]) < d.length() - 0.05


## 统计一段序列。返回 {反向, 跳变帧, 单帧最大, 峰峰值}
func _analyze(seq: Array[float]) -> Dictionary:
	var reversals := 0
	var jerks := 0
	var max_step := 0.0
	var lo := INF
	var hi := -INF
	for v in seq:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var prev_sign := 0
	for i in range(1, seq.size()):
		var dd := seq[i] - seq[i - 1]
		max_step = maxf(max_step, absf(dd))
		if absf(dd) > JERK:
			jerks += 1
		if absf(dd) < 0.01:
			continue
		var s := 1 if dd > 0.0 else -1
		if prev_sign != 0 and s != prev_sign:
			reversals += 1
		prev_sign = s
	return {"reversals": reversals, "jerks": jerks, "max_step": max_step, "ppt": hi - lo}


func _report(tag: String, seq: Array[float], clips: int, rev_limit: int) -> void:
	var a := _analyze(seq)
	print("[ci] %s：区间宽 %.2f m  单帧最大 %.3f m  跳变帧 %d  反向 %d 次  穿墙 %d 帧"
		% [tag, a["ppt"], a["max_step"], a["jerks"], a["reversals"], clips])
	if clips > 0:
		print("[ci]   [FAIL] 相机穿墙 %d 帧" % clips)
		_fail += 1
	if int(a["reversals"]) > rev_limit:
		print("[ci]   [FAIL] 反向 %d 次 > 上限 %d —— 这就是「疯狂抖动」"
			% [int(a["reversals"]), rev_limit])
		_fail += 1
	else:
		print("[ci]   [PASS] 反向 %d 次 ≤ %d" % [int(a["reversals"]), rev_limit])


func _run() -> void:
	await OffWin.apply(self, Vector2i(640, 360))
	await _wait(2)
	get_root().get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[ci] !! 超时强制退出")
		quit(2))
	var game: Node = load(GAME).instantiate()
	root.add_child(game)
	await _wait(60)

	_p = game.get_node_or_null("Player") as CharacterBody3D
	if _p == null:
		print("[ci] !! 没找到 Player")
		quit(1)
		return
	_spring = _p.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	_cam = _p.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	if _spring == null or _cam == null:
		print("[ci] !! 相机节点缺失")
		quit(1)
		return
	_space = _p.get_world_3d().direct_space_state

	# ── ① 对照组：空地上原地转一圈（用户说"空地正常"）──
	print("[ci] ---- ① 空地：原地转 180° ----")
	_p.global_position = ROOM + Vector3(0, 0.3, 0)
	await _wait(30)
	var seq0: Array[float] = []
	var clips0 := 0
	for i in 180:
		_p.set("_yaw", deg_to_rad(float(i)))
		await physics_frame
		seq0.append(_spring.spring_length)
		if _clipped():
			clips0 += 1
			if clips0 <= 3:
				print("[ci]   [diag] 空地第 %d 帧穿墙：%s" % [i, _clip_what])
	_report("空地转圈", seq0, clips0, 12)

	# ── ② 室内：原地转 180°（"一进入建筑"）──
	print("[ci] ---- ② 室内：原地转 180° ----")
	_build_room()
	_p.global_position = ROOM + Vector3(0, 0.3, 0)
	await _wait(30)
	var seq1: Array[float] = []
	var clips1 := 0
	for i in 180:
		_p.set("_yaw", deg_to_rad(float(i)))
		await physics_frame
		seq1.append(_spring.spring_length)
		if _clipped():
			clips1 += 1
			if clips1 <= 3:
				print("[ci]   [diag] 室内转圈第 %d 帧穿墙：%s" % [i, _clip_what])
	_report("室内转圈", seq1, clips1, 12)

	# ── ③ 室内：朝门洞走过去，穿过门洞 ──
	print("[ci] ---- ③ 室内：朝 +Z 门洞走 4.5 m ----")
	_p.set("_yaw", PI)                       # 弹簧臂朝 +Z（探针实测）
	_p.global_position = ROOM + Vector3(0, 0.3, -2.5)
	await _wait(30)
	var seq2: Array[float] = []
	var clips2 := 0
	for i in 225:
		_p.global_position = ROOM + Vector3(0, 0.3, -2.5 + float(i) * 0.02)
		await physics_frame
		seq2.append(_spring.spring_length)
		if i == 0:
			# [diag] 直接照抄 `_collide_camera_arm()` 的射线参数，看它到底该不该命中
			var axis := -_spring.global_transform.basis.z.normalized()
			print("[ci]   [diag] axis=%s  pivot=%s  len=%.2f  _wall_mask=%s  cam_mask=%s"
				% [str(axis.snappedf(0.01)), str(_spring.global_position.snappedf(0.01)),
				   _spring.spring_length, str(_p.get("_wall_mask")),
				   str(_p.get("cam_wall_mask"))])
			var dirs_dbg: Array = _p.call("_camera_probe_dirs", axis, 4.0)
			for d: Vector3 in dirs_dbg:
				var qd := PhysicsRayQueryParameters3D.create(_spring.global_position,
					_spring.global_position + d * 5.0, 1, [_p.get_rid()])
				var hd := _space.intersect_ray(qd)
				print("[ci]   [diag]   dir %s → %s" % [str(d.snappedf(0.01)),
					"空" if hd.is_empty() else str(hd["position"])])
			print("[ci]   [diag] 直接调用 _collide_camera_arm(4.2) = %.3f"
				% float(_p.call("_collide_camera_arm", 4.2, 1.0 / 60.0)))
		if _clipped():
			clips2 += 1
			if clips2 <= 4:
				print("[ci]   [diag] 门洞第 %d 帧穿墙：%s" % [i, _clip_what])
	_report("穿门洞", seq2, clips2, 12)

	print("[ci] ==== %s（%d 项失败）====" % ["全部通过" if _fail == 0 else "有失败", _fail])
	quit(0 if _fail == 0 else 1)

extends SceneTree
## 探针：玩家胶囊能爬什么样的楼梯 —— 四种造法，各跑一遍真按键。
##   godot --path . --headless --script res://scripts/_probe_stair_forms.gd -- --splat=off
##
## 背景（`_probe_step_climb.gd` 已量）：纯竖直踢面的台阶，**连 0.10 m 都上不去**。
##   原因不是「太高」，而是胶囊底部是半径 0.3 的半球：撞竖直面时接触点在球心
##   下方 0.09 m 处，法线是 (0.954, −0.30) —— **朝下**。`move_and_slide` 沿这个
##   法线滑移只会把人往下压，永远产生不了向上的分量。
##
## 所以要做「踏步」，踢面必须有**向上的斜面**（法线朝上），才能被算成 floor
## （`floor_max_angle` 默认 45°）。本探针量四种：
##   A 纯竖直踢面（对照，预期上不去）
##   B 38° 倒角踢面（每级一个斜面）
##   C 40° 倒角踢面
##   D 纯 31° 斜坡（对照，预期轻松上去）
##
## 判定标准：跑完 4 秒后 y ≥ 3.9（接近 4.2 的目标层高）= 能上去。

## 楼梯几何（和 mondrian_house.gd 的意向一致）
const STEPS := 20
const RISE := 4.2 / 20.0      # 0.21
const RUN := 7.0 / 20.0       # 0.35
## 起点 z（第一级踢面所在位置），楼梯往 +Z 爬升
const Z0 := -8.4


func _initialize() -> void:
	_run.call_deferred()


## 加一个有碰撞的盒子；`basis` 不是单位阵时就是斜的
func _box(parent: Node3D, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)
	parent.add_child(body)


## A：纯竖直踢面 —— 21 级实心方块，每级顶面 y = RISE*i
func _build_plain(parent: Node3D) -> void:
	for i in range(1, STEPS + 1):
		var top := RISE * float(i)
		var z := Z0 + RUN * float(i - 1)
		_box(parent, Vector3(0.0, top * 0.5, z + RUN * 0.5), Vector3(6.0, top, RUN + 0.02))


## B/C：倒角踢面 —— 每级 = 一块实心踏步 + 一片斜的倒角板
##   斜面从 (z_riser − c, y_prev) 爬到 (z_riser, y_now)，坡度角 deg。
##   c = RISE / tan(deg) 是倒角在 z 上占的深度。
##   斜面必须吃掉一部分踏面深度（RUN），所以每级实际踏面 = RUN − c。
func _build_chamfer(parent: Node3D, deg: float) -> void:
	var ang := deg_to_rad(deg)
	var c := RISE / tan(ang)
	print("  倒角 %.0f°：斜面占 z 上 %.3f m，平踏面剩 %.3f m" % [deg, c, RUN - c])
	var nrm := Vector3(0.0, cos(ang), -sin(ang))     # 斜面法线（朝上偏 −z）
	var basis := Basis(Vector3(1.0, 0.0, 0.0), -ang)  # 绕 X 转 −ang：局部 +Z 指向爬升方向
	var slope_len := sqrt(c * c + RISE * RISE)
	for i in range(1, STEPS + 1):
		var top := RISE * float(i)
		var z_riser := Z0 + RUN * float(i - 1)
		# ① 这一级的实心踏步：z 从 z_riser 到 z_riser + RUN，顶面 top
		_box(parent, Vector3(0.0, top * 0.5, z_riser + RUN * 0.5),
			Vector3(6.0, top, RUN + 0.02))
		# ② 倒角板：顶面正好从 (z_riser−c, top−RISE) 到 (z_riser, top)
		#    中心取这条斜线的中点，再沿法线往下沉半个板厚
		var mid := Vector3(0.0, top - RISE * 0.5, z_riser - c * 0.5)
		_box(parent, mid - nrm * 0.15, Vector3(6.0, 0.30, slope_len), basis)


## D：纯斜坡（无台阶），坡面从 (Z0, 0) 到 (Z0 + STEPS*RUN, RISE*STEPS)
func _build_ramp(parent: Node3D) -> void:
	var ang := atan2(RISE, RUN)
	var nrm := Vector3(0.0, cos(ang), -sin(ang))
	var basis := Basis(Vector3(1.0, 0.0, 0.0), -ang)
	var len_z := RUN * float(STEPS)
	var slope_len := sqrt(len_z * len_z + RISE * RISE * float(STEPS) * float(STEPS))
	var mid := Vector3(0.0, RISE * float(STEPS) * 0.5, Z0 + len_z * 0.5)
	_box(parent, mid - nrm * 0.15, Vector3(6.0, 0.30, slope_len), basis)


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	for _f in 20:
		await process_frame

	var player := game.get("_player") as CharacterBody3D
	if player == null:
		print("[错误] 拿不到玩家")
		quit(1)
		return

	var holder := Node3D.new()
	holder.name = "StairLab"
	game.add_child(holder)

	print("\n目标：从 y=0 爬到 y=%.2f（%d 级 × 踢面 %.3f / 踏面 %.3f，31° 名义坡度）\n"
		% [RISE * float(STEPS), STEPS, RISE, RUN])
	print("%-22s  %-9s  %-9s  %-8s  %s" % ["形式", "起点y", "终点y", "到顶比例", "判定"])

	for spec in [["A 纯竖直踢面", 0.0], ["B 倒角 38°", 38.0], ["C 倒角 40°", 40.0],
			["D 纯斜坡 31°", -1.0]]:
		var label: String = spec[0]
		var deg: float = spec[1]
		for c in holder.get_children():
			c.queue_free()
		await process_frame
		if deg < 0.0:
			_build_ramp(holder)
		elif deg == 0.0:
			_build_plain(holder)
		else:
			_build_chamfer(holder, deg)
		await process_frame

		# 起点：楼梯正前方 1.2 m、地面上
		player.global_position = Vector3(0.0, 0.05, Z0 - 1.2)
		player.velocity = Vector3.ZERO
		player.rotation.y = 0.0
		for _f in 20:
			await process_frame
		var y0 := player.global_position.y

		# `move_forward` 走 −Z，所以先转向 180° 让前进方向变成 +Z
		player.rotation.y = PI
		for _f in 5:
			await process_frame
		Input.action_press("move_forward")
		# 4 秒 = 240 帧；31° 坡、7 m 长的水平段，2.4 m/s 走完约 3 s
		for _f in 260:
			await process_frame
		Input.action_release("move_forward")
		for _f in 15:
			await process_frame

		var pos := player.global_position
		var frac := pos.y / (RISE * float(STEPS))
		var verdict := "到顶" if pos.y >= 3.9 else ("爬了一部分" if pos.y > 0.3 else "完全上不去")
		print("%-22s  %-9.3f  %-9.3f  %-8.0f%%  %s   (z=%.2f)"
			% [label, y0, pos.y, frac * 100.0, verdict, pos.z])

	quit(0)

extends SceneTree
## 探针：**扫站位候选**，把每个 slot 投到屏幕上，看落在哪里。
##
## 为什么需要它：站位是跟着相机绕角转的，所以「屏幕上会不会互相重叠 / 会不会正好
## 挡在准星上」不能靠脑补三角函数 —— 相机的实际位置、SpringArm 的偏移、FOV 的
## keep_aspect 规则都会影响结果，本喵手算就错了两次。直接量最省事。
##
## 用法：godot --path <工程> --script res://scripts/_probe_slot.gd -- --splat=off

## 候选站位（玩家局部坐标；+X 右、+Z 是玩家背后/镜头那一侧）
##
## 前三行是**已经在场**的三人（未花 / 优香 / 诺亚），后面是给第 4~7 名同伴
## （小桃 / 小绿 / 柚子 / 凯伊）挑位置用的候选。判据见文件末尾：
## 不挡准星、不糊脸、互相在屏幕上分开。
const EXISTING: Array[Vector3] = [
	Vector3(-2.0, 0, 0.9),   # 未花
	Vector3(2.0, 0, 0.9),    # 优香
	Vector3(-3.0, 0, -3.2),  # 诺亚
]

const CANDIDATES: Array[Vector3] = [
	Vector3(3.0, 0, -3.2),
	Vector3(3.0, 0, -1.4),
	Vector3(-4.4, 0, -3.0),
	Vector3(4.4, 0, -3.0),
	Vector3(-2.4, 0, -4.6),
	Vector3(2.4, 0, -4.6),
	Vector3(-4.6, 0, 0.4),
	Vector3(4.6, 0, 0.4),
	Vector3(-3.4, 0, 1.9),
	Vector3(3.4, 0, 1.9),
	Vector3(-5.2, 0, -1.4),
	Vector3(5.2, 0, -1.4),
	Vector3(-1.4, 0, -4.6),
	Vector3(1.4, 0, -4.6),
	Vector3(0.0, 0, -5.2),
	Vector3(-5.2, 0, -3.6),
	Vector3(5.2, 0, -3.6),
	Vector3(-3.8, 0, -4.6),
	Vector3(3.8, 0, -4.6),
	Vector3(-1.2, 0, -2.6),
	Vector3(1.2, 0, -2.6),
	Vector3(-5.6, 0, -0.6),
	Vector3(5.6, 0, -0.6),
	Vector3(-2.2, 0, 2.4),
	Vector3(2.2, 0, 2.4),
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame

	var player: Player = game.get_node("Player")
	player.global_position = Vector3(0, 0.05, 6)
	player._yaw = 0.0
	player.rig.rotation.y = 0.0
	player._pitch = -0.04
	for _i in 60:
		await process_frame

	var cam := player.cam
	var vp := Vector2(root.size)
	print("视口 %s   相机 %s   玩家 %s" % [
		str(vp), str(cam.global_position.snappedf(0.01)),
		str(player.global_position.snappedf(0.01))])
	print("（相机在玩家背后 %.2f m、横向 %.2f m、高 %.2f m）" % [
		cam.global_position.z - player.global_position.z,
		cam.global_position.x - player.global_position.x,
		cam.global_position.y - player.global_position.y])
	print("")

	# 已经在场的三人：它们的屏幕 x 是「新同伴不许撞上去」的基准
	var existing_x: Array[float] = []
	for slot in EXISTING:
		var p := player.global_position + Vector3(slot.x, 0.0, slot.z)
		existing_x.append(cam.unproject_position(p + Vector3.UP * 1.5).x)
	var txt: Array[String] = []
	for x in existing_x:
		txt.append("%.0f" % x)
	print("已在场的三人屏幕 x = [%s]" % ", ".join(txt))
	print("")
	print("%-18s %-24s %8s %8s %9s %9s %9s" % [
		"slot(x, z)", "世界坐标", "屏幕x", "离已有", "离相机m", "离玩家m", "屏高px"])
	print("-".repeat(90))

	for slot in CANDIDATES:
		var p := player.global_position + Vector3(slot.x, 0.0, slot.z)
		var head := p + Vector3.UP * 1.5
		var feet := p + Vector3.UP * 0.05
		var sp := cam.unproject_position(head)
		var px := absf(cam.unproject_position(head).y - cam.unproject_position(feet).y)
		var d_cam := cam.global_position.distance_to(p)
		var d_player := player.global_position.distance_to(p)
		var gap := 1.0e9
		for x in existing_x:
			gap = minf(gap, absf(sp.x - x))
		var flags := ""
		if absf(sp.x - vp.x * 0.5) < vp.x * 0.1:
			flags += " 挡准星?"
		if d_cam < 2.5:
			flags += " 糊脸!"
		if cam.is_position_behind(p):
			flags += " 在相机后!"
		if gap < 60.0:
			flags += " 撞已有!"
		print("%-18s %-24s %8.0f %8.0f %9.2f %9.2f %9.0f%s" % [
			"(%+.1f, %+.1f)" % [slot.x, slot.z],
			str(p.snappedf(0.1)), sp.x, gap, d_cam, d_player, px, flags])

	print("\n判据：屏幕x 偏离中心 > 160 px（=1600 的 10%%，不挡准星）、离相机 > 2.5 m、")
	print("      与已在场三人的屏幕间距 > 60 px、离玩家 ≤ 5 m（看着才像同伴）")
	quit(0)

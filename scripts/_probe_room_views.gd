extends SceneTree
## 拍：**真实游戏画面**里电竞房长什么样 —— 从玩家会站的位置看。
##
## ⚠️ 2026-11-10 教训：本喵反复用「矩阵 / 包围盒」验证朝向，每次都说对，
##    但使用者一进游戏就看到反的。所以这次**先拍画面再说话**。
##
## 拍四个方向：
##   A 从平台正中央看电竞房
##   B 从门那侧正面看（应该能看到门/窗帘）
##   C 从背面看
##   D 从侧面看
##
##   godot --script res://scripts/_probe_room_views.gd -- --splat=off --story=off --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const ShopClerkScript := preload("res://scripts/shop_clerk.gd")
const GAME := "res://scenes/game.tscn"
const OUT := "res://_arisu_captures/_room_views"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, nm: String) -> void:
	await _wait(5)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, nm])
	print("[rv] 图 %s" % nm)


func _run() -> void:
	await OffWin.apply(self, Vector2i(960, 540))
	await _wait(2)
	ShopClerkScript._bought = true
	var game: Node = load(GAME).instantiate()
	root.add_child(game)
	# 等演出彻底跑完（含 3 秒后 queue_free）
	for _i in 400:
		await process_frame
	await _wait(30)

	# 演出残留物检查
	var drop := game.get_node_or_null("EsportsDrop")
	print("[rv] EsportsDrop 还在吗：%s" % ("在 **（应该已经释放）**" if drop != null else "已释放 ✓"))

	var room: Node3D = game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		quit(1)
		return

	# 房子真实包围盒（只用低模 Room）
	var low := room.get_node_or_null("Room") as Node3D
	var target: Node3D = low if low != null else room
	var box := AABB()
	var first := true
	for n in target.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	print("[rv] 房子包围盒 pos=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)"
		% [box.position.x, box.position.y, box.position.z,
		   box.size.x, box.size.y, box.size.z])
	var c := box.get_center()
	print("[rv] 房子中心 %s" % str(c.snappedf(0.01)))

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 500.0
	root.add_child(cam)
	cam.current = true
	var eye := 1.6

	# 门朝向（本地+Z）
	var zdir := room.global_basis.z.normalized()
	print("[rv] 本地+Z 映射到世界 %s" % str(zdir.snappedf(0.01)))

	var r := 18.0
	# A 正对「门那侧」
	var pA := c + zdir * r
	pA.y = eye
	cam.global_position = pA
	cam.look_at(Vector3(c.x, eye, c.z), Vector3.UP)
	await _shot(cam, "A_门那侧")

	# B 正对「背面」
	var pB := c - zdir * r
	pB.y = eye
	cam.global_position = pB
	cam.look_at(Vector3(c.x, eye, c.z), Vector3.UP)
	await _shot(cam, "B_背面")

	# C 侧面
	var side := Vector3.UP.cross(zdir).normalized()
	var pC := c + side * r
	pC.y = eye
	cam.global_position = pC
	cam.look_at(Vector3(c.x, eye, c.z), Vector3.UP)
	await _shot(cam, "C_侧面")

	# D 平台中央（玩家常站的位置）
	var pD := Vector3(c.x, eye, c.z) + side * 10.0 + zdir * 6.0
	cam.global_position = pD
	cam.look_at(Vector3(c.x, eye, c.z), Vector3.UP)
	await _shot(cam, "D_玩家视角")
	quit(0)

extends SceneTree
## 拍：电竞房在**各种 Y 轴朝向**下的样子，编号让你一眼挑。
##
## 使用者 2026-11-10：「不是门，是整个房子颠倒了的问题」
## 本喵用矩阵改来改去 5 次都被打回，所以改成**一次拍全**，让使用者直接挑。
##
## 每张图都从「同一个固定相机位」拍（平台西南侧、离地 2 米、朝房子），
## 这样唯一变量就是房子的朝向。
##
##   godot --script res://scripts/_probe_orient_sheet.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const ROOM := "res://scenes/esports_room.tscn"
const OUT := "res://_arisu_captures/_orient_sheet"

## 9 种候选：三种「Y 轴方向」× 三种「门朝向」
## 键 = 标签，值 = [门朝世界哪个方向, Y 轴是否朝上]
## 用 Basis 构造（GDScript 没有 12 参数 Transform3D，见之前踩的坑）
##
## Basis 三列 = [X轴, Y轴, Z轴]；本地 +Z 是门，所以 Z 列 = 门朝向
const CASES := {
	"1_门朝+Z_正立": [Vector3(0, 0, 1), Vector3(1, 0, 0)],   # Z=(0,0,1)，X=(1,0,0)
	"2_门朝-Z_正立": [Vector3(0, 0, -1), Vector3(-1, 0, 0)],
	"3_门朝+X_正立": [Vector3(1, 0, 0), Vector3(0, 0, -1)],
	"4_门朝-X_正立": [Vector3(-1, 0, 0), Vector3(0, 0, 1)],
	"5_门朝+Z_倒立": [Vector3(0, 0, 1), Vector3(1, 0, 0)],
	"6_门朝-Z_倒立": [Vector3(0, 0, -1), Vector3(-1, 0, 0)],
}


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _make_transform(z_col: Vector3, x_hint: Vector3, upside_down: bool) -> Basis:
	## 给定「门朝哪个世界方向」和「X 轴朝向」，造一个正交 Basis
	var z := z_col.normalized()
	var y := Vector3.DOWN if upside_down else Vector3.UP
	# x = y × z（保证右手系）
	var x := y.cross(z).normalized()
	# 若 x 和 hint 反向，翻一下 z 的符号不行（会改变门朝向），所以忽略 hint
	var yy := z.cross(x).normalized()
	return Basis(x, yy, z)


func _shot(cam: Camera3D, nm: String) -> void:
	await _wait(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, nm])
	print("[os] 图 %s" % nm)


func _run() -> void:
	await OffWin.apply(self, Vector2i(800, 450))
	await _wait(2)

	# 固定相机位：房子在 (53.27, 0.01, 13.26)，从西南侧、离地 2.2 米看
	var target := Vector3(53.27, 1.8, 13.26)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(41.0, 2.2, 1.0)
	cam.look_at(target, Vector3.UP)
	await _wait(4)

	for label in CASES.keys():
		var v: Array = CASES[label]
		var z_col: Vector3 = v[0]
		var upside := String(label).contains("倒立")
		var basis := _make_transform(z_col, v[1], upside)
		var room: Node3D = load(ROOM).instantiate()
		root.add_child(room)
		room.transform = Transform3D(basis, Vector3(53.26548, 0.01, 13.256798))
		await _wait(8)

		# 量一下 Y 轴到底朝哪
		var b := room.global_basis
		print("[os] %-14s Y轴=(%.2f,%.2f,%.2f)  Z轴(门)=(%.2f,%.2f,%.2f)"
			% [label, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z])
		await _shot(cam, String(label))
		room.queue_free()
		await _wait(4)
	quit(0)

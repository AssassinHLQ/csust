extends SceneTree
## 探针：给「网格小屋」（`scenes/mesh_hut.tscn`）出五个机位的对照图。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_hut_shot.gd -- --splat=off
##
## ⚠️ 建议加 `--splat=off`：这个探针只关心小屋，画室609 那 277 万点白白拖慢每一张。
##    代价是图里没有画室（平台地板是兜底方盒）—— 要看两者同框就别加。
##
## 输出：…/_arisu_captures/_hut/*.png（1600 × 900）
##   10_outside   西南侧看过去：门 + 雨篷 + 灯柱
##   11_door      站在门口往里看
##   12_top       高空斜俯视：屋顶、货架那面墙、木箱
##   13_inside    站在屋里：桌子、凳子、窗
##   14_window    从 +Z 侧看窗（那一面没有门）
##
## 顺手关掉 HUD / 设置 / 对话框，图里只有场景本身。

const OUT_SUB := "_hut"
const HUT := Vector3(14, 0, -15.5)

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)

	# 图里不要 UI。
	# ⚠️ 这里必须是 `CanvasLayer`，**不能写 `CanvasItem`** —— HUD / 设置 / 对话框
	#    三个都是 CanvasLayer（继承自 Node，不是 CanvasItem），用 `as CanvasItem`
	#    会得到 null，于是这一整段静默失效、HUD 照样出现在图里（本喵第一版就是）。
	for n in ["HUD", "SettingsMenu", "DialogueBox"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	# 玩家自己的相机让位给探针相机
	var p := game.get_node_or_null("Player")
	if p != null:
		p.set_process_input(false)

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.05
	_cam.far = 500.0
	root.add_child(_cam)
	_cam.make_current()

	# ① 西南侧：门 + 雨篷 + 灯柱
	await _shot("10_outside", HUT + Vector3(-6.5, 3.5, 5.0), HUT + Vector3(-1.0, 1.4, 0.0))
	# ② 站在门口往里看
	await _shot("11_door", HUT + Vector3(-4.3, 1.6, 0.0), HUT + Vector3(1.5, 1.2, -0.6))
	# ③ 高空斜俯视。⚠️ 机位从**北侧**过来：南边 (13, −8) 蹲着霸王龙，它模型有
	#    12.6 m 长，从南边俯拍的话前景全是它的爪子和影子（本喵第一版就是这样）。
	await _shot("12_top", HUT + Vector3(3.0, 11.0, -7.5), HUT + Vector3(0.0, 0.6, 0.5))
	# ④ 屋里：桌子 / 凳子 / 窗
	await _shot("13_inside", HUT + Vector3(-2.0, 1.6, 1.6), HUT + Vector3(-0.6, 0.7, -2.2))
	# ⑤ 从 +Z 侧看窗
	await _shot("14_window", HUT + Vector3(1.0, 2.2, 6.5), HUT + Vector3(0.3, 1.6, 1.0))

	print("\n出图目录：%s" % _out)
	quit(0)


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	# 多等几帧：让阴影、灯光、CSG 的网格都稳定下来再抓
	await _wait(8)
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[hut] %s  ← 相机 %s" % [name, str(pos.snappedf(0.1))])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

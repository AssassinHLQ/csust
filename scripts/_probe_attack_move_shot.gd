extends SceneTree
## 探针：**跑动开火**时腿的姿势对照图（用户要的「边跑边打腿还在跑」）。
##
## 出一张 2 × 2 拼图（本探针只负责出 4 张 png，拼图用 tools 里的 python 做）：
##   01_stand_fire   站定开火（上半身在演开火，腿不动）
##   02_run_a/b/c    跑动开火，同一个跑动周期的三个相位（腿在换步、上半身一直在开火）
##
## 为什么用「三个相位」而不是一张图：**「脚在动」是时间上的事**，单张图看不出来；
## 同一周期三个相位并排，一眼就能看出步子在换。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_attack_move_shot.gd -- --splat=off
## 输出：…/_arisu_captures/_attackmove/*.png

const OUT_SUB := "_attackmove"
const START := Vector3(0, 0.05, 12)
const PHASE_MS := 170

var _cam: Camera3D
var _out: String
var _p: Player


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	for n in ["HUD", "SettingsMenu", "DialogueBox"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	_p = game.get_node_or_null("Player") as Player
	if _p == null:
		print("!! 没有 Player")
		quit(1)
		return
	_p.set_process_input(false)

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.05
	_cam.far = 500.0
	root.add_child(_cam)
	_cam.make_current()

	# ① 站定开火
	await _place(false)
	_p.anim.request_fire()
	await _wait_ms(320)
	await _shot("01_stand_fire")

	# ② 跑动开火：跑起来 → 开火 → 同一周期三个相位
	await _place(true)
	_p.anim.request_fire()
	await _wait_ms(320)
	for i in 3:
		await _shot("0%d_run_%s" % [i + 2, "abc"[i]])
		await _wait_ms(PHASE_MS)

	print("\n出图目录：%s" % _out)
	quit(0)


## 把玩家摆好、镜头对准他。`running` = 要不要按住 W+Shift 跑起来。
func _place(running: bool) -> void:
	for a in ["move_forward", "move_left", "move_right", "sprint"]:
		Input.action_release(a)
	_p.velocity = Vector3.ZERO
	_p.global_position = START
	_p._yaw = 0.0
	_p._facing_yaw = PI                      # 朝 −Z，正对靶区
	_p.model_root.rotation.y = PI
	await _wait(4)
	if running:
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await _wait_ms(500)


func _shot(name: String) -> void:
	# 3/4 侧前机位：枪和腿都在画面里。每张都跟着人重摆（他一直在跑）
	var p := _p.global_position
	_cam.global_position = p + Vector3(-1.7, 1.45, -2.5)
	_cam.look_at(p + Vector3(0.0, 0.85, 0.0), Vector3.UP)
	await _wait(3)
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[attackmove] %s  ← 人 %s" % [name, str(p.snappedf(0.1))])


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

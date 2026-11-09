extends SceneTree
## 出图对照：**同一个机位**分别拍「爱丽丝本体」和「机甲」，用来看机甲到底转对没转对。
##
## 为什么要有「本体」那一组：本体模型的朝向是**已知铁证**（`player.gd` 里那段：
## `model_root.rotation.y = 0 → 脸朝世界 +Z`）。所以拿同一台相机拍两张，
## 本体出「正脸」而机甲出「后脑勺」，就说明机甲多转了 180°；反之亦然。
## 只拍机甲的话，看图的人（和本喵）永远在猜「这面到底是不是脸」。
##
## 跑法（**要窗口，不要 headless** —— 要读 `root.get_texture()`）：
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64.exe --path . \
##       --script res://scripts/_diag_carrier_face.gd -- --no-capture
##
## 出图目录：`_arisu_captures/_carrier_face/`（已被 .gitignore 排除）

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

const OUT_DIR := "res://_arisu_captures/_carrier_face/"

var _player: Player
var _cf: CarrierForm
var _cam: Camera3D


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	MechState.set_carrier_for_test(true)

	var stage := Node3D.new()
	root.add_child(stage)

	var floor_body := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	fm.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.30, 0.29, 0.28)
	fm.material_override = fmat
	floor_body.add_child(fm)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.4, 60)
	col.shape = box
	col.position.y = -0.2
	floor_body.add_child(col)
	stage.add_child(floor_body)

	_player = PlayerScene.instantiate() as Player
	stage.add_child(_player)
	await process_frame
	await process_frame

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -40, 0)
	sun.light_energy = 1.3
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.70)
	e.ambient_light_energy = 0.75
	env.environment = e
	stage.add_child(env)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	stage.add_child(_cam)
	_cam.current = true

	_cf = _player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if _cf == null:
		push_error("[Face] 没有 CarrierForm")
		quit(1)
		return

	# 玩家站在原点、朝向固定（`_ready()` 里已经写 `_facing_yaw = _yaw + PI`）。
	# 冻结物理，免得这一路掉下去 / 被移动逻辑改朝向。
	_player.global_position = Vector3(0, 0.6, 0)
	_player.set_physics_process(false)
	var yaw: float = float(_player.get("_facing_yaw"))
	print("[Face] player._facing_yaw = %.2f° （180° 表示脸朝 −Z）" % rad_to_deg(yaw))

	# ── 对照出图：+Z 侧和 −Z 侧各拍本体 / 机甲一张 ──
	# 判据：同一侧拍到的「本体」和「机甲」必须是**同一面**（都后背 或 都正脸）。
	await _shot("a_base_from_Z", 1.0)
	await _shot("c_base_from_negZ", -1.0)

	if not _cf.set_form(true):
		push_error("[Face] 变形失败")
		quit(1)
		return
	_cf.call("_sync_face")
	await process_frame
	var carrier := _cf.get("_carrier") as Node3D
	print("[Face] facing_yaw_deg = %.1f ｜ _carrier.rotation.y = %.1f° ｜ 世界 yaw ≈ %.1f°" % [
		float(_cf.get("facing_yaw_deg")), rad_to_deg(carrier.rotation.y),
		rad_to_deg(carrier.global_rotation.y)])
	await _shot("b_carrier_from_Z", 1.0)
	await _shot("d_carrier_from_negZ", -1.0)

	MechState.set_carrier_for_test(false)
	print("[Face] 出图完成 → %s" % OUT_DIR)
	quit(0)


func to_deg_rounded(rad: float) -> float:
	return rad_to_deg(rad)


## 相机摆在角色 **Z 侧**（`side = +1` 是 +Z，`-1` 是 −Z），平视拍一张。
func _shot(name_: String, side: float) -> void:
	var head := _player.global_position + Vector3(0, 1.05, 0)
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.fov = 24.0
	_cam.look_at_from_position(head + Vector3(0.0, 0.1, 3.1 * side), head, Vector3.UP)
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + name_ + ".png")
	var err := img.save_png(path)
	print("  %s → %s (%dx%d) err=%d" % [name_, path, img.get_width(), img.get_height(), err])

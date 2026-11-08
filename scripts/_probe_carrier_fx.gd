extends SceneTree
## 出图：机甲飞行时的**喷气特效**长什么样（用户 2026-11-08：「太粗糙两个三角形」）。
##
## 出 4 张，同一个机位、同一套动作，只改「推力档位」：
##   0_ground   地面（推力 ≈ 0，只剩一点余温）
##   1_hover    悬停
##   2_climb    上升（推力满）
##   3_cruise   巡航前进（推力高 + 速度前倾）
##
## 另出一张 **侧视图**（3_side）：看喷焰的长度与层次，正视图看不出长度。
##
## 跑法（**要窗口，不能 headless** —— `get_texture().get_image()` 在 headless 下拿不到内容）：
##   & <mono godot> --path . --position -4000,-4000 --resolution 1280x720 --windowed \
##       --audio-driver Dummy --script res://scripts/_probe_carrier_fx.gd
##
## 出图 → `_arisu_captures/_carrier_fx/`

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

const OUT_DIR := "res://_arisu_captures/_carrier_fx/"

var _player: Player
var _cf: CarrierForm
var _cam: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	MechState.set_carrier_for_test(true)

	var stage := Node3D.new()
	stage.name = "FxStage"
	root.add_child(stage)

	var floor_body := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	fm.mesh = plane
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.26, 0.26, 0.28)
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
	sun.light_energy = 1.2
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.56, 0.66)
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	e.glow_intensity = 0.8
	env.environment = e
	stage.add_child(env)

	_cam = Camera3D.new()
	_cam.fov = 42.0
	stage.add_child(_cam)
	_cam.current = true

	_cf = _player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if _cf == null or not _cf.set_form(true):
		push_error("[Fx] 变形失败")
		quit(1)
		return
	_player.set_physics_process(false)
	_player.call("set_flight_lock", true)
	# ⚠️ `_sync_face()` 在 `_tick_flight()` 里（physics 阶段）。本探针把物理关了，
	#    所以**模型不会自己转正** —— 第一版出图里机甲是横躺的（探针的锅，
	#    不是代码的锅）。这里手动调一次 `_sync_face()` + `_run_effects()`，
	#    让朝向和特效都对。
	_cf.call("_sync_face")
	_cf.call("_run_effects", 1.0 / 60.0)

	# ① 地面
	_player.global_position = Vector3(0, 0.6, 0)
	await _settle(40)
	await _shot("0_ground", Vector3(2.6, 1.9, 3.4), Vector3(0, 1.0, 0))

	# ② 悬停
	_cf.call("_take_off")
	_player.global_position.y = 3.0
	_cf.set("_hold_y", 3.0)
	_player.set("velocity", Vector3.ZERO)
	await _settle(40)
	await _shot("1_hover", Vector3(2.8, 3.9, 3.6), Vector3(0, 3.0, 0))

	# ③ 上升（推力满，焰最长）
	_cf.set("_vert_want", 1.0)
	_player.global_position.y = 3.4
	await _settle(30)
	await _shot("2_climb", Vector3(3.0, 4.3, 3.8), Vector3(0, 3.4, 0))

	# ④ 巡航前进（速度前倾 + 高推力）
	_cf.set("_vert_want", 0.0)
	_cf.set("_hold_y", 3.4)
	_player.set("velocity", Vector3(0, 0, -19.0))
	await _settle(30)
	await _shot("3_cruise", Vector3(3.4, 4.2, 3.4), Vector3(0, 3.4, 0))

	# ⑤ 侧视图：看喷焰长度
	_cf.set("_vert_want", 1.0)
	_player.global_position.y = 3.4
	await _settle(24)
	await _shot("4_side", Vector3(5.6, 3.6, 0.4), Vector3(0, 3.4, 0))

	MechState.set_carrier_for_test(false)
	print("[Fx] 出图完成 → %s" % OUT_DIR)
	quit(0)


func _settle(frames: int) -> void:
	for i in frames:
		# 物理被关了，effects 得手动推（推力 / 焰长都靠它）
		_cf.call("_sync_face")
		_cf.call("_run_effects", 1.0 / 60.0)
		await process_frame


func _shot(name_: String, from: Vector3, to: Vector3) -> void:
	_cam.look_at_from_position(from, to, Vector3.UP)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR + name_ + ".png")
	var err := img.save_png(path)
	print("  %s → %s (%dx%d) err=%d" % [name_, path, img.get_width(), img.get_height(), err])

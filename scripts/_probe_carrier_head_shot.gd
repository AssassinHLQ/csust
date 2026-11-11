extends SceneTree
## 出图：机甲站在地上（常态）时**头的姿态**——最小场景版，不加载关卡。
##
##   & <godot> --path . --position -4000,-4000 --resolution 1280x720 --windowed \
##       --audio-driver Dummy --script res://scripts/_probe_carrier_head_shot.gd -- \
##       --no-capture --out=C:/.../_log/_carrier_head.png
##
## 为什么不加载关卡：`next_level.tscn` 的出生点在厅里（拍不到角色），
## 挪到校园空地又会被泼溅糊住相机（本喵连着踩了两次）。
## 这里只放 `player.tscn` + 一盏灯 + 一台相机，画面干净、可重复。
##
## ⚠️ `_process` 必须开着 —— `_fix_head_face()` 就在那条路径里，
##    关掉的话量到的是动画裸姿势（29°），不是玩家看到的。

const OffWin := preload("res://scripts/offscreen_window.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")

var _out := "C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_carrier_head.png"
var _airborne := false
var _tag := "after"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[chd] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s == "--airborne":
			_airborne = true
		elif s.begins_with("--tag="):
			_tag = s.substr(6)
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self)
	MechState.set_carrier_for_test(true)

	var stage := Node3D.new()
	root.add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.22, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.ambient_light_energy = 1.0
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.75, 0.5, 0.0)
	sun.light_energy = 1.4
	stage.add_child(sun)

	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	var cf = player.get_node_or_null("Arisu/CarrierForm")
	if cf == null or not cf.call("set_form", true):
		push_error("[chd] 变形失败")
		quit(1)
		return
	cf.set("_airborne", _airborne)
	cf.set("_hold_y", 0.0)

	# 让它自己跑起来（`_update_lean` / `_fix_head_face` 都在这条路径里）
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.fov = 45.0
	cam.make_current()
	for _i in 150:
		if not _airborne:
			cf.set("_airborne", false)
		_frame_camera(cam, cf)
		await process_frame
	_frame_camera(cam, cf)

	var d := _head_report(cf)
	print("[chd] %s：头相对机体 脸偏 %+.2f°（对模型正面）｜上轴偏 %+.2f°（对世界上方）"
		% [_tag, d[0], d[1]])
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	print("[chd] 出图 → %s err=%d size=%s" % [_out, err, str(img.get_size())])
	quit(0 if err == OK else 1)


## 把相机架在机甲**头的斜前方**：这样头歪没歪一眼能看出来。
func _frame_camera(cam: Camera3D, cf: Node) -> void:
	var skel := cf.get("_skel") as Skeleton3D
	var carrier := cf.get("_carrier") as Node3D
	if skel == null or carrier == null:
		return
	var hi := skel.find_bone("Bip001 Head")
	if hi < 0:
		return
	var head_pos := (skel.global_transform * skel.get_bone_global_pose(hi)).origin
	var fwd := carrier.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := carrier.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	cam.global_position = head_pos + fwd * 2.4 + right * 1.5 + Vector3.UP * 0.55
	cam.look_at(head_pos, Vector3.UP)


## 头「脸/上」两轴相对**机体局部系**基准的偏角（度）：
## 模型正面 = 机体系 +Z（`Vector3.BACK`）｜上方 = `Vector3.UP`。
## ⚠️ 必须两边同系 —— 第一版拿世界系的 `carrier.basis.z` 去比机体系里的向量，
##    机身穿一转就虚报 178°。
func _head_report(cf: Node) -> Array:
	var skel := cf.get("_skel") as Skeleton3D
	var carrier := cf.get("_carrier") as Node3D
	if skel == null or carrier == null:
		return [999.0, 999.0]
	var hi := skel.find_bone("Bip001 Head")
	if hi < 0:
		return [999.0, 999.0]
	var inv := carrier.global_transform.basis.inverse()
	var b := (skel.global_transform * skel.get_bone_global_pose(hi)).basis.orthonormalized()
	var face := (inv * b.y).normalized()
	var up := (inv * b.x).normalized()
	return [rad_to_deg(face.angle_to(Vector3.BACK)), rad_to_deg(up.angle_to(Vector3.UP))]

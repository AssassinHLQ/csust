extends Node
## 一次性工具：从多个机位渲染指定动作，用来肉眼确认武器握持姿态。
## 用法：set ARISU_POSE=1 然后运行 main.tscn
## 输出：…/_arisu_captures/_pose/<动作名>_<机位>.png
##
## 机位定义（玩家根节点朝向 +Z，模型节点已绕 Y 转 180° 使其面朝 +Z）：
##   front = 站在角色正前方看向它（相机在 +Z 侧）

const OUT_SUB := "_pose"
const ANIMS := ["Normal_Idle", "Normal_Attack_Ing", "Normal_Callsign", "Exs_Cutin", "Normal_Reload"]
const CENTER_Y := 0.75
const DIST := 2.8
const VIEWS := {
	"front": Vector3(0, CENTER_Y, DIST),
	"back": Vector3(0, CENTER_Y, -DIST),
	"left": Vector3(-DIST, CENTER_Y, 0),
	"right": Vector3(DIST, CENTER_Y, 0),
	"top": Vector3(0.0, CENTER_Y + DIST, 0.02),
}


func _ready() -> void:
	if OS.get_environment("ARISU_POSE") != "1":
		return
	_run.call_deferred()


func _run() -> void:
	var dir := _out_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var main := get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	var ap: AnimationPlayer = main.get_node_or_null("Arisu/Model/AnimationPlayer")
	if ap == null:
		push_error("[pose] 找不到 AnimationPlayer")
		get_tree().quit(1)
		return

	main.get_node("HUD").visible = false
	# 固定角色朝向，机位才有确定含义
	main.set_physics_process(false)
	main.set_process(false)
	main.set("_yaw", 0.0)
	var arisu: Node3D = main.get_node("Arisu")
	arisu.rotation.y = 0.0
	main.get_node("CameraRig").rotation.y = 0.0

	# 不用场景里那套相机，直接在场景根挂一个临时相机，位置完全可控
	var cam := Camera3D.new()
	cam.name = "PoseCam"
	cam.fov = 45.0
	cam.near = 0.05
	cam.far = 100.0
	main.add_child(cam)
	var old_cam: Camera3D = main.get_node("CameraRig/SpringArm3D/Camera3D")
	old_cam.current = false
	cam.current = true
	cam.make_current()

	for anim_name in ANIMS:
		var anim: Animation = ap.get_animation(anim_name)
		ap.play(anim_name)
		ap.seek(anim.length * 0.35, true)
		for _f in 4:
			await get_tree().process_frame
		for view_name in VIEWS:
			var pos: Vector3 = VIEWS[view_name]
			var up := Vector3.UP if view_name != "top" else Vector3.FORWARD
			cam.look_at_from_position(pos, Vector3(0, CENTER_Y, 0), up)
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%s.png" % [dir, anim_name, view_name])
			print("  %s / %s  cam=%s" % [anim_name, view_name, str(cam.global_position.snappedf(0.01))])

	print("[pose] 完成")
	get_tree().quit(0)


func _out_dir() -> String:
	var project_dir := ProjectSettings.globalize_path("res://")
	return project_dir.path_join("..").simplify_path().path_join("_arisu_captures").path_join(OUT_SUB)

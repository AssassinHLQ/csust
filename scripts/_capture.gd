extends Node
## 可选工具：批量渲染所有动作的取样帧，用来肉眼验证导入是否正常。
##
## 用法（需真实渲染，不能用 --headless）：
##   set ARISU_CAPTURE=1
##   Godot_v4.7.1-stable_mono_win64.exe --path <工程> res://scenes/main.tscn
## 输出：<工程目录的上一级>/_arisu_captures/<序号>_<动作名>.png
## 故意放在工程目录外：这些取样帧只是产出的参考图，不该被 Godot 当素材导入。

const OUT_DIR_NAME := "_arisu_captures"


func _ready() -> void:
	if OS.get_environment("ARISU_CAPTURE") != "1":
		return
	_run.call_deferred()


func _run() -> void:
	if not DirAccess.dir_exists_absolute(_out_dir()):
		DirAccess.make_dir_recursive_absolute(_out_dir())

	var main := get_tree().current_scene
	await get_tree().process_frame
	await get_tree().process_frame

	var ap: AnimationPlayer = main.get_node_or_null("Arisu/Model/AnimationPlayer")
	var list: ItemList = main.get_node_or_null("HUD/Panel/Margin/VBox/AnimList")
	if ap == null or list == null:
		push_error("[capture] 找不到 AnimationPlayer 或 AnimList")
		get_tree().quit(1)
		return

	# 面板挡画面，截图时先藏起来
	main.get_node("HUD").visible = false

	var total := list.item_count
	print("[capture] 共 %d 条动作" % total)
	for i in total:
		var anim_name := list.get_item_text(i).split("  ")[0].strip_edges()
		var anim: Animation = ap.get_animation(anim_name)
		ap.play(anim_name)
		ap.seek(anim.length * 0.35, true)
		# CUBICSPLINE/骨骼求值需要几帧稳定
		for _f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%02d_%s.png" % [_out_dir(), i, anim_name]
		img.save_png(path)
		print("  [%02d/%d] %s" % [i + 1, total, path])

	main.get_node("HUD").visible = true
	print("[capture] 完成")
	get_tree().quit(0)


## 工程目录的上一级 + OUT_DIR_NAME，例如 …\GODOT\_arisu_captures
func _out_dir() -> String:
	var project_dir := ProjectSettings.globalize_path("res://")
	return project_dir.path_join("..").simplify_path().path_join(OUT_DIR_NAME)

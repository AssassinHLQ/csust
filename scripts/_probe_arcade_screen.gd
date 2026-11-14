extends SceneTree
## 单独查「柜子屏幕上画了什么」：把小游戏画布（SubViewport）直接导出成 PNG。
##
## ⚠️ 探针里凡是 `var x := obj.get("_field") as SomeType` 的写法，类型写错就会拿到 null，
##    接着一句 `x.visible` 直接脚本报错 ⇒ 协程中断 ⇒ `quit()` 再也不执行 ⇒ 进程永远挂着。
##    所以这里**每一步都先判 null**，出错也把话说清楚再 `quit(1)`。
##
##   godot --path . --script res://scripts/_probe_arcade_screen.gd -- --no-capture --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const OUT := "res://_tools/_tmp/arcade_screen"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var script := load("res://scripts/esports_arcade.gd") as Script
	var arcade := script.new() as Node3D
	root.add_child(arcade)
	await _wait(8)

	var vp := arcade.get("tank_viewport") as SubViewport
	if vp == null:
		print("[vp] ❌ 没有 tank_viewport")
		quit(1)
		return
	var att: Node = arcade.get("_attract") as Node
	print("[vp] viewport size=%s  update_mode=%d  子节点 %d 个"
		% [str(vp.size), vp.render_target_update_mode, vp.get_child_count()])
	if att == null:
		print("[vp] ❌ 没有 _attract")
		quit(1)
		return
	print("[vp] attract = %s  可见=%s  font=%s"
		% [att.name, str(att.visible), str(att.get("font"))])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var out := ProjectSettings.globalize_path(OUT)

	# 多等几帧让 UPDATE_ALWAYS 真正画过一帧
	for _i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	_dump(vp, out, "attract.png")

	# 打开小游戏（会实例化坦克动荡），看画布变了没
	arcade.call("open_for_test")
	for _i in 24:
		await process_frame
	await RenderingServer.frame_post_draw
	_dump(vp, out, "running.png")
	print("[vp] is_open=%s  tank=%s" % [str(arcade.call("is_open")), str(arcade.get("tank"))])
	quit(0)


func _dump(vp: SubViewport, dir: String, name: String) -> void:
	var img := vp.get_texture().get_image()
	if img == null:
		print("[vp] ❌ %s 拿不到画布内容" % name)
		return
	img.save_png(dir.path_join(name))
	print("[vp] 导出 %s（%d×%d）" % [name, img.get_width(), img.get_height()])
	var pts := [Vector2i(500, 300), Vector2i(500, 640), Vector2i(20, 20)]
	for p in pts:
		print("[vp]   像素 %s = %s" % [str(p), str(img.get_pixel(p.x, p.y))])

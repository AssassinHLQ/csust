extends SceneTree
## 把蒙德里安厅的室内烘成 baked 场景：
##   _tools/run_shot.sh res://scripts/_bake_mondrian_hall.gd -- --force
## 产物 scenes/mondrian_hall_interior_baked.tscn —— 和构成主义大厅一样，
## 烘完每一块都能在编辑器里拖；改了 mondrian_hall.gd 的常量再跑一次。

func _initialize() -> void:
	_run.call_deferred()


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)


func _count(n: Node) -> int:
	var k := 1
	for c in n.get_children():
		k += _count(c)
	return k


func _run() -> void:
	var out := "res://scenes/mondrian_hall_interior_baked.tscn"
	if FileAccess.file_exists(out) and not OS.get_cmdline_user_args().has("--force"):
		print("[bake] %s 已存在（会覆盖手改内容；要重烘请加 -- --force）" % out)
		quit(0)
		return
	var hall := (load("res://scenes/mondrian_hall_interior.tscn") as PackedScene).instantiate()
	root.add_child(hall)
	for _i in 10:
		await process_frame
	hall.set("auto_build", false)
	_own(hall, hall)
	var ps := PackedScene.new()
	var err := ps.pack(hall)
	if err != OK:
		print("[bake] pack 失败：%d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, out)
	if err != OK:
		print("[bake] save 失败：%d" % err)
		quit(1)
		return
	var size := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(out)).size()
	print("[bake] %s ← %s（%d 节点，%.1f KB）"
		% [out.get_file(), hall.name, _count(hall), float(size) / 1024.0])
	quit(0)

extends SceneTree
## 查：LOD 三档切换时，每一档的**实际世界包围盒**是否一致。
##
## 使用者 2026-11-10：「远看是对的，走进就变错了，又反了」「走近后房子上下颠倒了」
##
## 做法：造一个完整 EsportsRoom，手动把 HighModel / MidModel / Room 轮流单独显示，
##       每次量它们的**世界包围盒**（位置 + y 范围）。
##       如果某一档的 y 范围和别的差很远 → 就是它的问题。
##
##   godot --headless --script res://scripts/_probe_lod_switch.gd -- --no-capture

const ROOM := "res://scenes/esports_room.tscn"
const OffWin := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _world_box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		# 只用真正会被渲染的（is_visible_in_tree 太严，这里看 visible 链）
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _run() -> void:
	await OffWin.apply(self, Vector2i(640, 360))
	await _wait(2)

	var room: Node3D = load(ROOM).instantiate()
	root.add_child(room)
	# 和 game.tscn 里一致：门朝 -X，底面贴地
	# ⚠️ GDScript 的 Transform3D **没有 12 参数构造**（那只是 .tscn 文件格式），
	#    必须用 Transform3D(Basis, Vector3)。基向量按列给。
	room.transform = Transform3D(
		Basis(Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)),
		Vector3(53.26548, 0.61, 13.256798))
	await _wait(20)

	var low := room.get_node_or_null("Room") as Node3D
	var lod := room.get_node_or_null("Lod")
	var mid: Node3D = null
	var high: Node3D = null
	if lod != null:
		mid = lod.get_node_or_null("MidModel") as Node3D
		high = lod.get_node_or_null("HighModel") as Node3D

	print("[sw] low  = %s" % ("有" if low != null else "无"))
	print("[sw] mid  = %s" % ("有" if mid != null else "无（可能还在后台加载）"))
	print("[sw] high = %s" % ("有" if high != null else "无（可能还在后台加载）"))

	# 等后台加载完
	var waited := 0
	while waited < 400 and (mid == null or high == null):
		await process_frame
		waited += 1
		if lod != null:
			mid = lod.get_node_or_null("MidModel") as Node3D
			high = lod.get_node_or_null("HighModel") as Node3D
	print("[sw] 等了 %d 帧后：mid=%s high=%s"
		% [waited, "有" if mid != null else "无", "有" if high != null else "无"])

	print("[sw] ============ 每一档单独显示时的世界包围盒 ============")
	var cases := {}
	if low != null:
		cases["low  (远看用的)"] = low
	if mid != null:
		cases["mid  (中距)"] = mid
	if high != null:
		cases["high (走近用的)"] = high

	for label in cases.keys():
		var n: Node3D = cases[label]
		# 只显示这一档
		if low != null:
			low.visible = false
		if mid != null:
			mid.visible = false
		if high != null:
			high.visible = false
		n.visible = true
		await _wait(4)
		var b := _world_box(n)
		print("[sw] %-16s pos=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)  y范围[%.2f, %.2f]"
			% [label, b.position.x, b.position.y, b.position.z,
			   b.size.x, b.size.y, b.size.z, b.position.y, b.position.y + b.size.y])
		print("[sw]                  local_pos=%s  local_scale=%s  local_rot=%s"
			% [str(n.position.snappedf(0.01)), str(n.scale), str(n.rotation_degrees.snappedf(0.1))])
	quit(0)

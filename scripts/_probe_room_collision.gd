extends SceneTree
## 探针：把画室609 **运行时生成**的房间碰撞（`Room609/RoomCollision` 下的盒）
## 导出成可以直接粘进 `game.tscn` 的节点文本。
##
## 为什么需要它：生成算法用的是**内容包围盒**（1‰~99.9‰ 分位盒，受 `crop_*`
## 与 `anchor_*` 影响），那串数字是**量**出来的、不是算出来的 —— 凭记忆写必然错。
## 本探针用和 `scenes/game.tscn` 里 `Room609` **完全相同的参数**跑一遍生成，
## 所以导出来的盒与线上正在用的那个逐字节等价。
##
## 用法：
##   godot --headless --path . --script res://scripts/_probe_room_collision.gd
## 输出：stdout + ..\_arisu_captures\_collision\room609_room_collision.txt

const SplatSceneScript := preload("res://scripts/splat_scene.gd")

## 盒的命名与子资源 id —— 顺序不参与逻辑，`_verify_room.gd` 只认几何。
const NAMES := {
	"xneg": ["WallXNeg", "Shape_room_xneg"],
	"xpos": ["WallXPos", "Shape_room_xpos"],
	"znegA": ["WallZNegA", "Shape_room_zneg_a"],
	"znegB": ["WallZNegB", "Shape_room_zneg_b"],
	"zpos": ["WallZPos", "Shape_room_zpos"],
}
const ORDER := ["xneg", "xpos", "znegA", "znegB", "zpos"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	# ⚠️ 必须与 scenes/game.tscn 的 Room609 逐项一致，否则导出来的盒不是线上那个。
	var scene: Node3D = SplatSceneScript.new()
	scene.name = "Room609"
	scene.set("sog_path", "res://splatdata/room609.sogdata")
	scene.set("display_name", "画室609")
	scene.set("venue", "room")
	scene.set("world_scale", 4.25)
	scene.set("yaw_degrees", 248.6)
	scene.set("auto_place", false)
	scene.set("use_anchor", true)
	scene.set("anchor_source", Vector3(0.022, -0.333, -0.121))
	scene.set("anchor_world", Vector3(0, 0.03, 4.25))
	scene.set("crop_enabled", true)
	scene.set("crop_margin", 0.5)
	scene.set("crop_max_scale", 0.5)
	scene.set("build_collision", false)
	scene.set("build_box_collision", true)
	scene.set("box_wall_thickness", 0.3)
	scene.set("box_door_side", "z-")
	scene.set("box_door_width", 1.6)
	scene.set("box_door_center", 0.0)
	scene.set("cache_mode", "auto")
	scene.set("auto_start", false)
	root.add_child(scene)

	scene.call("load_now")
	if not scene.call("is_ready"):
		push_error("[collision] 泼溅没建立起来")
		quit(1)
		return
	await _frames(2)

	var col: StaticBody3D = scene.get_node_or_null("RoomCollision")
	if col == null:
		push_error("[collision] 没有生成 RoomCollision")
		quit(1)
		return
	print("[collision] Room609 的全局变换 = %s" % str(scene.global_transform))
	print("[collision] 墙厚 %.2f，门在 %s 面、宽 %.2f、中心 %.2f" % [
		float(scene.get("box_wall_thickness")), str(scene.get("box_door_side")),
		float(scene.get("box_door_width")), float(scene.get("box_door_center"))])

	var boxes: Array = []
	for ch in col.get_children():
		var cs := ch as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var bs := cs.shape as BoxShape3D
		boxes.append({"pos": cs.position, "size": bs.size})
	print("[collision] 盒 %d 个" % boxes.size())

	var t := float(scene.get("box_wall_thickness"))
	# 分类：x± 的厚度在 x，z± 的厚度在 z。z− 那一面被门切成两段，按 x 排序区分 A/B。
	var classified := {}
	var zneg: Array = []
	for b in boxes:
		var p: Vector3 = b["pos"]
		var s: Vector3 = b["size"]
		if absf(s.x - t) < 0.05:
			classified["xneg" if p.x < 0.0 else "xpos"] = b
		elif absf(s.z - t) < 0.05:
			if p.z < 0.0:
				zneg.append(b)
			else:
				classified["zpos"] = b
	zneg.sort_custom(func(a, c): return a["pos"].x < c["pos"].x)
	if zneg.size() == 2:
		classified["znegA"] = zneg[0]
		classified["znegB"] = zneg[1]
	print("[collision] 分类结果：%s" % str(classified.keys()))

	# --- 人看的表 ---
	print("")
	print("[collision] 盒中心 / 尺寸（本节点局部 = 世界，因为 Room609 是单位变换）")
	for k in ORDER:
		if not classified.has(k):
			print("  %-8s **缺失**" % k)
			continue
		var p: Vector3 = classified[k]["pos"]
		var s: Vector3 = classified[k]["size"]
		print("  %-8s pos (%9.4f, %9.4f, %9.4f)   size (%8.4f, %7.4f, %8.4f)" % [
			k, p.x, p.y, p.z, s.x, s.y, s.z])

	# --- 门洞自检（和 _verify_room.gd §5 同一套判据）---
	# 注意 _verify_room 里的 AABB 是「最小角 + 尺寸」，所以它的
	# gap_lo = position.x + size.x 就是这里的「中心 + 半宽」。
	if classified.has("znegA") and classified.has("znegB"):
		var a: Vector3 = classified["znegA"]["pos"]
		var asz: Vector3 = classified["znegA"]["size"]
		var b: Vector3 = classified["znegB"]["pos"]
		var bsz: Vector3 = classified["znegB"]["size"]
		var gap_lo := a.x + asz.x * 0.5
		var gap_hi := b.x - bsz.x * 0.5
		print("[collision] 门洞 x %.4f ~ %.4f（宽 %.4f，中心 %.4f）" % [
			gap_lo, gap_hi, gap_hi - gap_lo, (gap_lo + gap_hi) * 0.5])

	# --- 可以直接粘的 .tscn 文本 ---
	var lines: Array[String] = []
	for k in ORDER:
		if not classified.has(k):
			continue
		var s: Vector3 = classified[k]["size"]
		lines.append("[sub_resource type=\"BoxShape3D\" id=\"%s\"]" % NAMES[k][1])
		lines.append("size = Vector3(%.4f, %.4f, %.4f)" % [s.x, s.y, s.z])
	lines.append("")
	lines.append("[node name=\"RoomCollision\" type=\"StaticBody3D\" parent=\"Room609\"]")
	for k in ORDER:
		if not classified.has(k):
			continue
		var p: Vector3 = classified[k]["pos"]
		lines.append("")
		lines.append("[node name=\"%s\" type=\"CollisionShape3D\" parent=\"Room609/RoomCollision\"]" % NAMES[k][0])
		lines.append("transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %.4f, %.4f, %.4f)" % [p.x, p.y, p.z])
		lines.append("shape = SubResource(\"%s\")" % NAMES[k][1])

	print("")
	print("[collision] ===== 粘进 game.tscn 的文本（起）=====")
	for l in lines:
		print(l)
	print("[collision] ===== 粘进 game.tscn 的文本（止）=====")

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_collision")
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("room609_room_collision.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("[collision] 也写到 %s" % out.path_join("room609_room_collision.txt"))
	quit(0)


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

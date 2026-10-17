extends SceneTree
## 探针：场景里**每一副骨架**现在是不是立着的。
##
## 判据不依赖骨骼名：把所有骨骼的世界坐标收进一个 AABB，看
##   高（y 跨度）÷ 水平跨度
##   直立人形 ≈ 2.4~4（身高 1.6 m、肩宽 0.6 m，骨骼集中在上半身）
##   躺平      ≈ 0.3~1.0（高只剩下身体厚度）
## 同时打印每副骨架所属的角色路径，谁躺了一眼就能看出来。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_upright.gd -- --splat=off

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)

	var rows := []
	for n in _all(game, "Skeleton3D"):
		var sk := n as Skeleton3D
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for b in sk.get_bone_count():
			var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(b).origin
			mn = mn.min(p)
			mx = mx.max(p)
		var size := mx - mn
		var horiz := maxf(size.x, size.z)
		var ratio := size.y / maxf(horiz, 0.001)
		rows.append([_owner_path(sk), size, ratio])

	print("\n=== 每副骨架的世界包围盒 ===")
	print("%-52s %-26s %7s %s" % ["角色", "尺寸 (x,y,z)", "高/宽", "判定"])
	for r in rows:
		var size: Vector3 = r[1]
		var ratio: float = r[2]
		var verdict := "立着"
		if ratio < 1.2:
			verdict = "★ 躺着？"
		elif ratio < 1.8:
			verdict = "偏斜"
		print("%-52s %-26s %7.2f %s" % [
			r[0], str(size.snappedf(0.01)), ratio, verdict])

	print("\n共 %d 副骨架" % rows.size())
	quit(0)


func _owner_path(n: Node) -> String:
	var path := String(n.get_path())
	# 往上找到角色根（Player / Companion* / Boss* / Sensei）
	var cur := n
	while cur != null and cur.get_parent() != null:
		var nm := String(cur.name)
		if nm.begins_with("Player") or nm.begins_with("Companion") \
				or nm.begins_with("Boss") or nm.begins_with("Sensei"):
			path = String(cur.get_path())
			break
		cur = cur.get_parent()
	return path


func _all(n: Node, cls: String, out := []) -> Array:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_all(c, cls, out)
	return out


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

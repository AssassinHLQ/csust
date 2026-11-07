extends SceneTree
## 探针：把柴关电脑城新屋壳的**每个网格**的包围盒和材质打出来。
##
## 为什么不用出图判断：店内/门内那两张机位一直贴进几何里，白花花一片看不清。
## 直接问几何最省事 —— 哪块是实墙、哪块是玻璃、门洞开在哪，坐标一摆就明白。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_shop_parts.gd

const SHOP_SCENE := "res://scenes/shop_baked.tscn"

var _shop: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_shop = (load(SHOP_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_shop)
	for _i in 8:
		await process_frame

	var shell := _shop.get_node_or_null("Shell") as Node3D
	if shell == null:
		print("[parts] !! 没有 Shell 节点")
		quit(1)
		return

	# 以 Shop 节点自身为参照，把世界坐标换成「店内本地坐标」
	var inv := _shop.global_transform.affine_inverse()

	print("[parts] 布局基准：shop_len=%.2f shop_depth=%.2f，壳深=%.2f，层高=%.2f" % [
		float(_shop.get("shop_len")), float(_shop.get("shop_depth")),
		float(_shop.get("shell_depth")), float(_shop.get("shop_height"))])
	print("[parts] 店内本地坐标下：x ∈ [%.2f, %.2f]（东西），z ∈ [%.2f, %.2f]（前后，+Z 为正面）"
		% [-float(_shop.get("shop_len")) * 0.5, float(_shop.get("shop_len")) * 0.5,
			float(_shop.get("shop_depth")) * 0.5 - float(_shop.get("shell_depth")),
			float(_shop.get("shop_depth")) * 0.5])
	print("")

	print("[parts] ── GLB 的每个网格（店内本地坐标）──")
	var rows := []
	for n in shell.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		# 正确的本地包围盒：把**网格的 8 个角点**逐个变到 Shop 本地空间再取 AABB。
		# ⚠️ 不能拿 `mi.get_aabb()` 直接乘一个拼出来的 Transform3D —— AABB 是轴对齐的，
		#    必须逐角点变换（第一版就是那么写的，除地板外量出来的全是整栋的尺寸）。
		var xf := inv * mi.global_transform
		var src := mi.get_aabb()
		var lb := AABB()
		for i in 8:
			var p := xf * src.get_endpoint(i)
			if i == 0:
				lb = AABB(p, Vector3.ZERO)
			else:
				lb = lb.expand(p)
		var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var mname := "?" if mat == null else mat.resource_name
		var col := "?" if mat == null else str(mat.albedo_color)
		rows.append([lb.size.x * lb.size.y, mi.name, mname, col, lb])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		var lb: AABB = r[4]
		print("  %-30s 材质=%-16s 色=%s" % [String(r[1]), String(r[2]), String(r[3]).left(22)])
		print("      本地 pos=(%7.2f,%6.2f,%7.2f)  size=(%6.2f,%6.2f,%6.2f)  x[%6.2f,%6.2f] z[%7.2f,%7.2f]"
			% [lb.position.x, lb.position.y, lb.position.z,
				lb.size.x, lb.size.y, lb.size.z,
				lb.position.x, lb.position.x + lb.size.x,
				lb.position.z, lb.position.z + lb.size.z])

	print("")
	print("[parts] ── 本工程加的碰撞盒（店内本地坐标）──")
	for n in _shop.get_node("Body").get_children():
		var cs := n as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		if not String(cs.name).begins_with("Shell"):
			continue
		var bs := cs.shape as BoxShape3D
		var p := cs.position
		print("  %-20s 中心=(%7.2f,%6.2f,%7.2f)  size=(%6.2f,%6.2f,%6.2f)  x[%6.2f,%6.2f] z[%7.2f,%7.2f]"
			% [cs.name, p.x, p.y, p.z, bs.size.x, bs.size.y, bs.size.z,
				p.x - bs.size.x * 0.5, p.x + bs.size.x * 0.5,
				p.z - bs.size.z * 0.5, p.z + bs.size.z * 0.5])

	print("")
	print("[parts] ── 柜台 / 货架 / 芹香（店内本地坐标）──")
	for nm in ["Counter", "CounterTop", "Register", "WallShelf", "WallShelf3"]:
		var node := _shop.get_node_or_null("Body/" + nm) as Node3D
		if node == null:
			continue
		var lp := inv * node.global_position
		print("  %-12s 本地=(%7.2f,%6.2f,%7.2f)" % [nm, lp.x, lp.y, lp.z])
	var clerk := _shop.get_node_or_null("ClerkSerika") as Node3D
	if clerk != null:
		var lp := inv * clerk.global_position
		print("  芹香         本地=(%7.2f,%6.2f,%7.2f)" % [lp.x, lp.y, lp.z])

	quit(0)

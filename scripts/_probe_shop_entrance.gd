extends SceneTree
## 找电脑城新壳（Sketchfab「Shop」）玩家**实际能从哪儿进去**。
##
##   godot --path . --headless --script res://scripts/_probe_shop_entrance.gd
##
## 背景：新壳被 `shop.gd::_build_shell_from_glb()` 原样实例化，**没有挖门洞**。
## 旧探针 `_probe_shop.gd` 里「1.2 m 高的门洞是通的」那条断言是给**旧程序化壳**写的，
## 换壳之后大概率已经不成立。
##
## 做法：在南侧（z 最大那面）沿 x 扫一遍，逐点打射线，
## 记录**从外面能不能走进店里**，画出可通行的 x 区间。

const SCENE := "res://scenes/shop_baked.tscn"
const IN_Z1 := -12.70   # 南墙外沿（世界）
const IN_Z0 := -23.50


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shop := (load(SCENE) as PackedScene).instantiate()
	root.add_child(shop)
	current_scene = shop
	for _i in 20:
		await physics_frame

	var space := (shop as Node3D).get_world_3d().direct_space_state
	print("[entry] ── 南侧沿 x 扫描（从外 z=-10.5 朝里打到 z=-16）──")
	var open_x: Array[float] = []
	var x := 20.8
	while x <= 33.8:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(x, 1.2, IN_Z1 + 2.2), Vector3(x, 1.2, IN_Z1 - 3.3), 1))
		if hit.is_empty():
			open_x.append(x)
			print("[entry]   x=%5.2f  通 ✓" % x)
		x += 0.4
	print("[entry] 可通行的 x 点数 = %d / 总数 ≈ %d" % [open_x.size(), int((33.8 - 20.8) / 0.4) + 1])
	if open_x.is_empty():
		print("[entry] ⚠️ 南侧整面都挡着 —— 这个壳没有门洞")
	else:
		print("[entry] 可通行范围：x %.2f ~ %.2f" % [open_x[0], open_x[-1]])

	# 东西两侧也扫一下（万一入口在侧面）
	print("[entry] ── 东侧（x=33.9 外面朝里打）──")
	var east_open := 0
	var z := IN_Z0 + 0.5
	while z <= IN_Z1 - 0.5:
		var eh := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(35.5, 1.2, z), Vector3(32.5, 1.2, z), 1))
		if eh.is_empty():
			east_open += 1
		z += 0.5
	print("[entry]   东侧可通行点 %d 个" % east_open)

	print("[entry] 完成")
	quit(0)

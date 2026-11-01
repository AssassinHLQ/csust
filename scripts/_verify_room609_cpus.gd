extends SceneTree
## 验：609 桌上十颗 9950X3D —— 数量 / 尺寸 / 单价，以及按 F 收进本轮资产。
##   godot --path . --headless --script res://scripts/_verify_room609_cpus.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(pk)
	var cpus := (load("res://scenes/room609_cpus.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(cpus)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12.0, 0.5, 12.0)
	cs.shape = bs
	cs.position = Vector3(0.9, -0.25, 1.3)
	floor_body.add_child(cs)
	root.add_child(floor_body)

	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 40:
		await physics_frame

	var list: Array = cpus.get_children()
	var cpu0 := list[0] as Node3D
	print("[cpu] 609 桌上 %d 颗（期望 10）" % list.size())
	for c in list:
		var n := c as Node3D
		print("[cpu]   %-6s 世界位置 %s　单价 ¥%d" % [
			n.name, str(n.global_position.snappedf(0.01)), int(n.call("price"))])

	# 模型尺寸：12 cm 见方、厚度最薄的那一轴是 Y
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for mi in cpu0.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var bb := m.get_aabb()
		for i in 8:
			var w := m.global_transform * bb.get_endpoint(i)
			lo = lo.min(w)
			hi = hi.max(w)
	var sz := hi - lo
	print("[cpu] 单颗世界包围盒 %.3f × %.3f × %.3f m（期望 0.12 见方、最薄轴是 Y）" % [
		sz.x, sz.y, sz.z])

	# 站到桌子旁边按 F（脚踩在地上，桌面在 1.19 m）
	player.global_position = cpu0.global_position + Vector3(0.45, -1.14, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 20:
		await physics_frame
	var fut := pk.get_node_or_null("Futures")
	var a0 := int(fut.get("assets_yuan"))
	var c0 := int(fut.get("cpu_count"))
	print("[cpu] 站到桌旁：on_floor=%s　提示 owner=%s" % [
		str(player.is_on_floor()), str(fut.call("prompt_owner"))])
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.physical_keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	for _i in 8:
		await physics_frame
	print("[cpu] 按 F 后：资产 %d → %d（期望 +4599）、CPU 计数 %d → %d、这颗还在=%s" % [
		a0, int(fut.get("assets_yuan")), c0, int(fut.get("cpu_count")),
		str(is_instance_valid(cpu0))])
	print("[cpu] 结论：%s" % (
		"OK" if list.size() == 10 and int(fut.get("assets_yuan")) == a0 + 4599
		and int(fut.get("cpu_count")) == c0 + 1 and not is_instance_valid(cpu0) else "FAIL"))
	quit(0)

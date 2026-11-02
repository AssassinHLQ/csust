extends SceneTree
## 验：609 屋顶十五颗 9950X3D —— 数量 / 尺寸（×3）/ 单价，以及按 F **直接进银行卡**。
const BankCard := preload("res://scripts/bank_card.gd")
##   godot --path . --headless --script res://scripts/_verify_room609_cpus.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(pk)
	var cpus := (load("res://scenes/room609_cpus.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(cpus)

	# 屋顶台面（CPU 现在摆在 609 屋顶，y ≈ 5.65）
	var roof_top := 5.79
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12.0, 0.5, 12.0)
	cs.shape = bs
	cs.position = Vector3(-0.5, roof_top - 0.25, 3.54)
	floor_body.add_child(cs)
	root.add_child(floor_body)

	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 40:
		await physics_frame

	var list: Array = []
	for c in cpus.get_children():
		if c.has_method("price"):
			list.append(c)
	var cpu0 := list[0] as Node3D
	print("[cpu] 609 屋顶 %d 颗（期望 149）" % list.size())
	for i in [0, 1, list.size() - 2, list.size() - 1]:
		var n := list[i] as Node3D
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
	print("[cpu] 单颗世界包围盒 %.3f × %.3f × %.3f m（期望 0.36 见方、含光环 0.39）" % [
		sz.x, sz.y, sz.z])

	# 站到**中间某颗**旁边（149 颗挤在一起，验「提示归最近那颗」）
	var target := list[list.size() / 2] as Node3D
	player.global_position = target.global_position + Vector3(0.2, roof_top + 0.05 - target.global_position.y, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 20:
		await physics_frame
	var fut := pk.get_node_or_null("Futures")
	BankCard.set_balance(0)
	fut.set("bank_yuan", 0)
	var b0 := BankCard.balance()
	print("[cpu] 站在 %s 旁：on_floor=%s　提示 owner=%s（期望 = %s）" % [
		target.name, str(player.is_on_floor()), str(fut.call("prompt_owner")), target.name])
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.physical_keycode = KEY_F
	ev.pressed = true
	Input.parse_input_event(ev)
	for _i in 8:
		await physics_frame
	print("[cpu] 按 F 后：银行卡 %d → %d、HUD 银行卡 %d → %d、这颗还在=%s" % [
		b0, BankCard.balance(), 0, int(fut.get("bank_yuan")), str(is_instance_valid(target))])
	print("[cpu] 结论：%s" % (
		"OK" if list.size() == 149 and BankCard.balance() == b0 + 4599
		and int(fut.get("bank_yuan")) == 4599 and not is_instance_valid(target) else "FAIL"))
	quit(0)

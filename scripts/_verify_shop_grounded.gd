extends SceneTree
## 验：芹香只有在玩家**脚踩实地**时才亮「按 F 说话」；
## 半空中即使距离够也不会触发（避免对话暂停世界把人冻在天上）。
##   godot --path . --headless --script res://scripts/_verify_shop_grounded.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(10.0, 0.5, 10.0)
	cs.shape = bs
	cs.position = Vector3(0.0, -0.25, 0.0)
	floor_body.add_child(cs)
	root.add_child(floor_body)

	var clerk := ShopClerk.new()
	root.add_child(clerk)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 30:
		await physics_frame

	# ① 半空：水平 0.8 m、离地 1.5 m —— 距离够，但没落地
	player.global_position = clerk.global_position + Vector3(0.8, 1.5, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 10:
		await physics_frame
	print("[talk] 半空：on_floor=%s in_range=%s hint=%s（期望 false / false / false）" % [
		str(player.is_on_floor()), str(clerk.get("_in_range")),
		str((clerk.get("_hint") as Label3D).visible)])

	# ② 落地：同样水平距离
	player.global_position = clerk.global_position + Vector3(0.8, 0.6, 0.0)
	player.velocity = Vector3.ZERO
	for _i in 45:
		await physics_frame
	print("[talk] 落地：on_floor=%s in_range=%s hint=%s（期望 true / true / true）" % [
		str(player.is_on_floor()), str(clerk.get("_in_range")),
		str((clerk.get("_hint") as Label3D).visible)])
	quit(0)

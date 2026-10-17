extends SceneTree
## 探针：玩家是不是**被压扁/折起来**了 —— 直接量骨架的世界高度。
##
## 对照组：
##   ① `models/Arisu_ext.glb` 裸加载（没有任何 `pose_fix`）→ 播 `Move_Ing`
##   ② `scenes/player.tscn`（`AnimDriver` 会跑 `fix_run_lean` / `fix_head_roll`
##      / `fix_eyelid_sync` 三套修法）→ 同样的速度
## 两组都报「骨骼最高点 − 最低点」和「头 / 髋 / 脚」的世界 y。差得多就是修法弄坏的。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_pose_height.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n========== ① 裸 glb（无修法）==========")
	var raw: Node = (load("res://models/Arisu_ext.glb") as PackedScene).instantiate()
	root.add_child(raw)
	await _wait(4)
	var ap := _find(raw, "AnimationPlayer") as AnimationPlayer
	var sk := _find(raw, "Skeleton3D") as Skeleton3D
	print("  AnimationPlayer=%s  Skeleton3D=%s  动画数=%d" % [
		ap.name if ap else "无", sk.name if sk else "无",
		ap.get_animation_list().size() if ap else 0])
	if ap and sk:
		for clip in ["Normal_Idle", "Move_Ing", "Normal_Attack_Ing"]:
			if not ap.has_animation(clip):
				continue
			ap.play(clip)
			ap.seek(0.4, true)
			await _wait(3)
			_measure(sk, "裸 %s" % clip)
	raw.queue_free()
	await _wait(2)

	print("\n========== ② player.tscn（带三套修法）==========")
	var player: Node = (load("res://scenes/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	await _wait(4)
	var anim = player.get("anim")
	var sk2: Skeleton3D = anim.get("skeleton") if anim else null
	if sk2 == null:
		print("!! 取不到骨架")
		quit(1)
		return
	player.set_physics_process(false)
	for pair in [[0.0, "待机"], [6.8, "跑 6.8"]]:
		anim.call("set_locomotion", pair[0], true, 0.0)
		await _wait(24)
		_measure(sk2, "玩家 %s" % pair[1])
		anim.call("request_fire")
		await _wait(8)
		_measure(sk2, "玩家 %s + 开火" % pair[1])
	quit(0)


func _measure(sk: Skeleton3D, label: String) -> void:
	var lo := 1e9
	var hi := -1e9
	for b in sk.get_bone_count():
		var y: float = (sk.global_transform * sk.get_bone_global_pose(b).origin).y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var head := _bone_y(sk, "head")
	var pelvis := _bone_y(sk, "pelvis")
	var foot := _bone_y(sk, "foot")
	print("  %-20s 骨骼高度 %.3f m（最低 %.3f / 最高 %.3f）头 %.3f 髋 %.3f 脚 %.3f" % [
		label, hi - lo, lo, hi, head, pelvis, foot])


func _bone_y(sk: Skeleton3D, keyword: String) -> float:
	var k := keyword.to_lower()
	for b in sk.get_bone_count():
		if String(sk.get_bone_name(b)).to_lower().contains(k):
			return (sk.global_transform * sk.get_bone_global_pose(b).origin).y
	return -999.0


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

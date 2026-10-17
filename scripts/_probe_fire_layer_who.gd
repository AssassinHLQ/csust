extends SceneTree
## 探针：开火那一发**到底是哪一层在播**，以及各层的轨道数对不对。
##
## 速度扫描（`_probe_fire_speed_sweep.gd`）发现：
##   0.8 / 1.6 / 2.4 m/s 开火 → 躯干 up 从 0.999 掉到 0.94（**后仰 18°**）
##   3.2 m/s 以上开火      → up 几乎不动（0.894 → 0.899）
## 而 `active_upper_layer()` 在这两种速度下都返回 `UpperBodyMove`。
## 所以要么「实际播的不是这一层」，要么「这一层其实没滤干净」。
##
## 这里把每一层的真实状态摊开：在不在树里、在不在播、播的哪条、攻击动作还剩几条轨道、
## 剩下的是哪些骨。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_fire_layer_who.gd -- --splat=off

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)
	var p := game.get_node_or_null("Player")
	var anim = p.get("anim")
	p.set_physics_process(false)

	for v in [1.6, 6.8]:
		print("\n========== 速度 %.1f + 开火 ==========" % v)
		anim.call("set_locomotion", v, true, 0.0)
		await _wait(24)
		anim.call("request_fire")
		await _wait(8)

		var act = anim.call("active_upper_layer")
		print("active_upper_layer() = %s" % ("null" if act == null else String(act.name)))
		for lname in ["upper", "upper_move"]:
			var l = anim.get(lname)
			if l == null:
				print("  %-11s = null" % lname)
				continue
			var a: Animation = l.get_animation("Normal_Attack_Ing") \
				if l.has_animation("Normal_Attack_Ing") else null
			print("  %-11s 在树=%-5s 在播=%-5s 曲目=%-18s 攻击轨道=%d" % [
				lname, str(l.is_inside_tree()), str(l.is_playing()),
				l.current_animation, -1 if a == null else a.get_track_count()])
			if a != null:
				var bones := []
				for t in a.get_track_count():
					var bone := _bone_of(String(a.track_get_path(t)))
					if not bones.has(bone):
						bones.append(bone)
				print("      剩下的骨：%s" % ", ".join(bones))
		print("  基础层在播：%s  速度比例 %.2f" % [
			anim.get("player").current_animation, anim.get("player").speed_scale])
		_dump(anim, "开火中")
		# 收尾
		anim.call("set_locomotion", 0.0, true, 0.0)
		await _wait(80)
	quit(0)


func _dump(anim, label: String) -> void:
	var sk: Skeleton3D = anim.get("skeleton")
	for k in ["pelvis", "spine", "chest", "neck", "head", "clavicle", "shoulder"]:
		var idx := -1
		var kw: String = String(k).to_lower()
		for b in sk.get_bone_count():
			if String(sk.get_bone_name(b)).to_lower().contains(kw):
				idx = b
				break
		if idx < 0:
			continue
		var w: Vector3 = sk.global_transform * sk.get_bone_global_pose(idx).origin
		print("    %-10s %-20s 世界 y=%.3f  up=%s" % [
			k, String(sk.get_bone_name(idx)), w.y,
			str(sk.get_bone_global_pose(idx).basis.y.normalized().snappedf(0.01))])


func _bone_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

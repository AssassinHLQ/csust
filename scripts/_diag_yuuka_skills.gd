extends SceneTree
## 快速诊断：单独把优香-恐怖放进空场景，逐帧看"引力井 / 幻影"到底有没有推进。
##
##   godot --headless --path . --script res://scripts/_diag_yuuka_skills.gd
##
## 为什么不用 `_probe_final_phase.gd`：那个要加载整个第二关（4 分钟），
## 调一个技能的 tick 太慢。这里不加载场景、不渲染，几秒钟一轮。

const BossScript := preload("res://scripts/yuuka_horror_boss.gd")


class Dummy extends CharacterBody3D:
	var health := 250.0
	var max_health := 250.0

	func take_damage(amount: float, _pos := Vector3.ZERO, _knock := 0.0) -> void:
		health -= amount
		print("    玩家掉血 %.0f → %.0f" % [amount, health])


func _initialize() -> void:
	var root_node := Node3D.new()
	get_root().add_child(root_node)
	var p := Dummy.new()
	p.name = "Player"
	p.add_to_group("player")
	root_node.add_child(p)
	p.global_position = Vector3(0.0, 0.0, 18.0)
	var b := BossScript.new() as Node3D
	b.name = "YuukaHorror"
	root_node.add_child(b)
	b.global_position = Vector3.ZERO
	for _i in 3:
		await process_frame
	b.set("_t_skill", 9999.0)
	p.set_physics_process(false)

	for skill in ["gravity", "phantom", "homing", "sweep", "meteor", "spikes", "nova"]:
		p.global_position = Vector3(0.0, 0.0, 18.0)
		p.health = 250.0
		b.call("debug_reset")
		print("\n=== %s ===" % skill)
		b.call("debug_cast", skill)
		for i in 240:
			await physics_frame
			var st: Dictionary = b.call("status")
			if i % 20 == 0:
				print("  f%-3d wells=%d ph=%d sw=%d marks=%d orbs=%d busy=%s 玩家 %s hp=%.0f" % [
					i, int(st["wells"]), int(st["phantoms"]), int(st["sweeps"]),
					int(st["slam_marks"]), int(st["orbs"]), str(st["busy"]),
					str(p.global_position.snappedf(0.1)), p.health])
			if not bool(st["busy"]) and int(st["wells"]) == 0 and int(st["phantoms"]) == 0 \
					and int(st["sweeps"]) == 0 and int(st["slam_marks"]) == 0 \
					and int(st["orbs"]) == 0 and i > 30:
				break
		var st2: Dictionary = b.call("status")
		print("  → 结束：hits=%s 玩家 hp=%.0f" % [str(st2["hits"]), p.health])
	quit(0)

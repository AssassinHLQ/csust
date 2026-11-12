extends SceneTree
## 量电竞房门口那三级台阶：世界尺寸、每级**踏面高差（riser）**，并对比
## `StepClimb.DEFAULT_HEIGHT`（玩家能自动迈上去的最大高度）。
##
## 用户 2026-11-12：房间整体放大 1.5 倍之后问「最底下那三个台阶大了还是（小了）」。
## 台阶是 `EsportsRoom` 的子节点，所以会跟着房间一起 ×1.5 —— 但台阶是**给人走的**，
## 放大 1.5 倍之后第一级踏面可能超过玩家能迈的高度，那就不是「大一点」而是「上不去」。
##
##   godot --path . --script res://scripts/_probe_esports_steps.gd -- --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const StepClimbRef := preload("res://scripts/step_climb.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	var steps := room.get_node_or_null("BaseSteps") if room != null else null
	if steps == null:
		print("❌ 找不到 EsportsRoom/BaseSteps")
		quit(1)
		return

	print("\n======== 电竞房台阶实测 ========")
	print("  房间 scale = %s" % str(room.scale.snappedf(0.001)))
	print("  玩家能自动迈上的最大高度 StepClimb.DEFAULT_HEIGHT = %.3f m"
		% StepClimbRef.DEFAULT_HEIGHT)

	# 收集每级台阶（BoxShape3D）的世界 y 范围与水平尺寸
	var rows: Array = []
	for c in steps.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var sz: Vector3 = (cs.shape as BoxShape3D).size
		var half: Vector3 = cs.global_transform.basis.get_scale().abs() * sz * 0.5
		rows.append({
			"name": String(cs.name),
			"lo": cs.global_position.y - half.y,
			"hi": cs.global_position.y + half.y,
			"x": half.x * 2.0, "y": half.y * 2.0, "z": half.z * 2.0,
		})
	rows.sort_custom(func(a, b): return float(a["lo"]) < float(b["lo"]))

	# 按 (方向, 高度) 归并成「级」：同一级的 4 个边（N/S/W/E）尺寸一致
	var levels := {}
	for r in rows:
		var key := "%.3f" % float(r["hi"])
		if not levels.has(key):
			levels[key] = r
	var tops: Array = []
	for k in levels.keys():
		tops.append(float(k))
	tops.sort()

	print("\n  按踏面高度从低到高：")
	var prev := 0.0       # 地面
	for t in tops:
		var r: Dictionary = levels["%.3f" % t]
		var riser: float = t - prev
		var verdict := ""
		if riser > StepClimbRef.DEFAULT_HEIGHT + 0.001:
			verdict = "  ⚠️ 超过玩家可迈高度（得跳）"
		print("    踏面 y=%.3f  高差 %.3f m  厚度 %.3f  水平 %.2f×%.2f%s"
			% [t, riser, float(r["y"]), float(r["x"]), float(r["z"]), verdict])
		prev = t

	print("\n  共 %d 个碰撞盒 / %d 级踏面" % [rows.size(), tops.size()])
	quit(0)

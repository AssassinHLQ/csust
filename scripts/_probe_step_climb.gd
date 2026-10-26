extends SceneTree
## 探针（重做）：玩家胶囊到底能爬多高的**竖直**台阶 —— 在干净空地上量。
##   godot --path . --headless --script res://scripts/_probe_step_climb.gd -- --splat=off
##
## ⚠️ 上一版这个探针把试验台摆在 x=0、z=−8.4，而画室609 的南墙在世界 z=−6.63 ——
##    玩家从 z=−6 出发得先穿过那面墙，数据不可信。现在改到商店门前的空地
##    （世界 x=28、z −10~+18 已由 `_probe_mondrian_site.gd` 验证为纯平地无障碍）。
##
## 为什么要实测：`mesh_hut.tscn` 里写着「10 cm 的坎 cast_motion 的 safe 从 1.000 掉到
## 0.387，人就被挡在门外」。但 `cast_motion` 只说「会撞上」，没说 `move_and_slide`
## 爬不爬得上去 —— 胶囊底部是半球，撞竖向面时接触法线偏下，理论上滑不上去，
## 但这必须用真按键量，不能推。

const HEIGHTS := [0.05, 0.10, 0.15, 0.21, 0.30, 0.45]
## 试验台中心（世界坐标）。x=28 在商店门前的空地上。
const LAB_X := 28.0
## 玩家起点 z；`move_forward` 走 −Z，所以台阶放在更小的 z
const START_Z := 2.0
const STEP_Z := -1.4


func _initialize() -> void:
	_run.call_deferred()


func _make_step(parent: Node3D, h: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TestStep"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# ⚠️ 台面必须**足够长**（24 m，一直延伸到玩家走不完的地方）。
	#    第一版只做了 0.80 m 深，玩家爬上去后两步就走完了，再从另一侧掉下来 ——
	#    终点 y 又变成 0，看起来像「被挡住」，其实早就爬上去了（实测 0.05/0.15/
	#    0.21/0.30 四档都这样，z 冲到了 −4.2 才露馅）。判据必须让高度保持住。
	bs.size = Vector3(8.0, h, 24.0)
	cs.shape = bs
	cs.position = Vector3(LAB_X, h * 0.5, STEP_Z - 12.0 + 0.40)
	body.add_child(cs)
	# 可见版本，拍图时能对照
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.90, 0.40, 0.35)
	mi.material_override = m
	mi.position = cs.position
	body.add_child(mi)
	parent.add_child(body)
	return body


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	for _f in 20:
		await process_frame

	var player := game.get("_player") as CharacterBody3D
	if player == null:
		print("[错误] 拿不到玩家")
		quit(1)
		return

	var holder := Node3D.new()
	holder.name = "StepLab"
	game.add_child(holder)

	print("试验台：世界 x=%.1f、台阶面 z=%.1f（商店门前空地，已确认无障碍）" % [LAB_X, STEP_Z])
	print("玩家胶囊：半径 0.30、总高 1.50；起点 z=%.1f，前进方向 −Z\n" % START_Z)
	print("%-8s  %-10s  %-10s  %-10s  %-8s  %s" % [
		"台阶高", "起点y", "终点y", "升降", "终点z", "判定"])

	for h in HEIGHTS:
		var hh: float = h
		var step := _make_step(holder, hh)
		player.global_position = Vector3(LAB_X, 0.05, START_Z)
		player.velocity = Vector3.ZERO
		for _f in 20:
			await process_frame
		var y0 := player.global_position.y

		Input.action_press("move_forward")
		for _f in 150:
			await process_frame
		Input.action_release("move_forward")
		for _f in 12:
			await process_frame

		var pos := player.global_position
		var dy := pos.y - y0
		var verdict := ""
		if dy >= hh - 0.03:
			verdict = "✔ 上去了"
		elif dy > 0.03:
			verdict = "半爬（卡住）"
		else:
			verdict = "✘ 被挡"
		print("%-8.2f  %-10.3f  %-10.3f  %-10.3f  %-8.2f  %s" % [
			hh, y0, pos.y, dy, pos.z, verdict])

		step.queue_free()
		await process_frame
		player.global_position = Vector3(LAB_X, 0.05, START_Z)
		player.velocity = Vector3.ZERO
		for _f in 10:
			await process_frame

	quit(0)

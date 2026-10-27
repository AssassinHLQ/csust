extends SceneTree
## 量：每个角色模型**原生**（未摆动画、未额外缩放）有多高 —— 用来判断芹香是不是被放大了。
##   _tools/run_probe.sh res://scripts/_probe_model_heights.gd
##
## 直接 load glb、不播动画：此时 MeshInstance3D 的 AABB 就是模型真实几何（没有骨骼姿态干扰）。
## 分别给出：
##   · 全体高（含光环、武器）
##   · 身体高（排除名字里带 Halo / Weapon / FX / Mouth 的网格）

const MODELS := [
	["爱丽丝（玩家）", "res://models/Arisu_ext.glb", 1.0],
	["芹香（商店）", "res://models/npc/serika/serika.glb", 1.42],
	["小雪", "res://models/companions/Koyuki.glb", 1.0],
	["优香", "res://models/companions/Yuuka.glb", 1.0],
	["诺亚", "res://models/companions/Noa.glb", 1.0],
	["小桃", "res://models/companions/Momoi.glb", 1.0],
	["小绿", "res://models/companions/Midori.glb", 1.0],
	["柚子", "res://models/companions/Yuzu.glb", 1.0],
]

const SKIP := ["halo", "weapon", "fx", "mouth"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	print("%-16s %8s %8s %8s" % ["角色", "缩放", "身体高", "全体高"])
	for row in MODELS:
		var label: String = row[0]
		var path: String = row[1]
		var scale: float = row[2]
		if not ResourceLoader.exists(path):
			print("%-16s （缺文件 %s）" % [label, path])
			continue
		var n := (load(path) as PackedScene).instantiate() as Node3D
		holder.add_child(n)
		n.scale = Vector3.ONE * scale
		await process_frame
		var body_lo := INF
		var body_hi := -INF
		var all_lo := INF
		var all_hi := -INF
		for c in n.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			var w: AABB = mi.global_transform * mi.get_aabb()
			all_lo = minf(all_lo, w.position.y)
			all_hi = maxf(all_hi, w.position.y + w.size.y)
			var low := String(mi.name).to_lower()
			var skip := false
			for s in SKIP:
				if low.contains(s):
					skip = true
					break
			if not skip:
				body_lo = minf(body_lo, w.position.y)
				body_hi = maxf(body_hi, w.position.y + w.size.y)
		print("%-16s %8.2f %8.3f %8.3f" % [label, scale, body_hi - body_lo, all_hi - all_lo])
		n.queue_free()
		await process_frame
	quit(0)

extends SceneTree
## 探针：**同伴到底有哪些动画、手里拿的是什么**。
##
## 起因（用户报）：
##   「为什么小桃小绿行走动作是拿游戏机的，还有好多角色行走也没有拿枪了」
##
## 这两个现象指向同一处：同伴的「行走」播的是 `Cafe_Walk`（Blue Archive 的
## **咖啡厅**动作），而咖啡厅里角色不拿武器 —— 小桃/小绿那两个模型在咖啡厅动作下
## 手里是**游戏机**（她们的招牌道具）。所以先把这个假设量出来，而不是猜。
##
## 量四件事：
##   1. 每个模型的 AnimationPlayer 里**到底有哪些 clip**（名字 + 时长）——
##      以及 `anim_driver.gd` 写死的那三个名字在不在；
##   2. 三个循环 clip 各自**动了哪些带道具关键词的骨**（gun / weapon / prop /
##      console / game / item / hand）—— Blue Archive 的道具是**靠骨的 scale
##      缩到 0 来隐藏**的，所以「哪根骨的 scale 是不是 0」就是「手里拿的是什么」；
##   3. 对每根这样的骨，在 clip 里的 scale 关键帧**最小值**（≈0 = 藏起来了）；
##   4. 真场景里把同伴按 2.2 / 6.4 m/s 驱动一遍，打印 `current_clip()` ——
##      确认「走和跑**都**播 `Move_Ing`」（README §1.17 之后的现状；
##      在这之前是「行走 = Cafe_Walk、跑 = Move_Ing」，那份读数就是这次改动的依据）。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_companion_anim.gd -- --splat=off

const KEYWORDS := ["gun", "weapon", "prop", "console", "game", "item", "hand", "obj"]
const CLIPS := ["Normal_Idle", "Cafe_Walk", "Move_Ing", "Normal_Attack_Ing", "Normal_Reload"]
const MODELS := [
	{"who": "爱丽丝（主角）", "path": "res://models/Arisu_ext.glb"},
	{"who": "未花", "path": "res://models/companions/Mika.glb"},
	{"who": "优香", "path": "res://models/companions/Yuuka.glb"},
	{"who": "诺亚", "path": "res://models/companions/Noa.glb"},
	{"who": "小桃", "path": "res://models/companions/Momoi.glb"},
	{"who": "小绿", "path": "res://models/companions/Midori.glb"},
	{"who": "柚子", "path": "res://models/companions/Yuzu.glb"},
	{"who": "凯伊", "path": "res://models/companions/Kei_ext.glb"},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for m in MODELS:
		_dump(String(m["who"]), String(m["path"]))
	await _live_check()
	quit(0)


## 直接 load 模型（不进场景），把 clip 清单与道具骨打出来。
func _dump(who: String, path: String) -> void:
	print("\n========== %s（%s）==========" % [who, path.get_file()])
	if not ResourceLoader.exists(path):
		print("  !! 文件不在：%s" % path)
		return
	var scene := (load(path) as PackedScene).instantiate()
	var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
	var sk := _find(scene, "Skeleton3D") as Skeleton3D
	if ap == null:
		print("  !! 没有 AnimationPlayer")
		scene.free()
		return
	var names := ap.get_animation_list()
	print("  clip 共 %d 条：%s" % [names.size(), str(names)])
	var missing: Array[String] = []
	for c in CLIPS:
		if not ap.has_animation(c):
			missing.append(c)
	print("  anim_driver.gd 要用的 5 条里缺：%s" % ("（无）" if missing.is_empty() else str(missing)))
	for c in CLIPS:
		if ap.has_animation(c):
			print("    %-20s %6.3f s" % [c, ap.get_animation(c).length])
	# 道具骨：名字里带关键词的骨
	var props: Array[String] = []
	if sk != null:
		for i in sk.get_bone_count():
			var bn := sk.get_bone_name(i)
			if _is_prop(bn):
				props.append(bn)
	print("  道具味儿的骨 %d 根：%s" % [props.size(), str(props)])
	# 每条循环 clip 里，这些骨的 scale 最小值（≈0 = 被藏起来）
	for c in ["Normal_Idle", "Cafe_Walk", "Move_Ing"]:
		if not ap.has_animation(c):
			continue
		var anim := ap.get_animation(c)
		var lines: Array[String] = []
		for t in anim.get_track_count():
			var tp := String(anim.track_get_path(t))
			if not _is_prop(tp):
				continue
			if anim.track_get_type(t) != Animation.TYPE_SCALE_3D:
				lines.append("%s（%s）" % [tp.get_file(), _track_type_name(anim.track_get_type(t))])
				continue
			var lo := INF
			for k in anim.track_get_key_count(t):
				lo = minf(lo, anim.track_get_key_value(t, k).x)
			lines.append("%s scale.x 最小 %.3f%s" % [
				tp.get_file(), lo, "  ← 藏起来了" if lo < 0.2 else ""])
		if lines.is_empty():
			print("    %-12s 没有任何道具骨轨道 —— 道具是**静态长在模型里**的" % c)
		else:
			print("    %-12s %s" % [c, "\n                 ".join(PackedStringArray(lines))])
	scene.free()


## 真场景：把同伴按 walk_speed / run_speed 驱动，看它播的是哪条 clip。
## README §1.17 之后两条速度都应该是 `Move_Ing`（战斗动画 = 手上有枪）。
func _live_check() -> void:
	print("\n========== 真场景：同伴行走/跑动各播哪条 clip（都应为 Move_Ing）==========")
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	for child in game.get_children():
		if not (child is Companion):
			continue
		var comp := child as Companion
		var anim := comp.get_node_or_null("Rig") 
		var driver: AnimDriver = null
		for n in _all(comp):
			if n is AnimDriver:
				driver = n as AnimDriver
		if driver == null or driver.player == null:
			print("  %-6s 找不到 AnimDriver / AnimationPlayer" % comp.display_name)
			continue
		driver.set_locomotion(comp.walk_speed, true, 0.0)
		await _wait(2)
		var walk_clip := driver.current_clip()
		driver.set_locomotion(comp.run_speed, true, 0.0)
		await _wait(2)
		var run_clip := driver.current_clip()
		driver.set_locomotion(0.0, true, 0.0)
		await _wait(2)
		var idle_clip := driver.current_clip()
		print("  %-6s 走 %.1f → %-12s 跑 %.1f → %-12s 站 → %s" % [
			comp.display_name, comp.walk_speed, walk_clip,
			comp.run_speed, run_clip, idle_clip])
	quit(0)


func _is_prop(name: String) -> bool:
	var low := name.to_lower()
	for k in KEYWORDS:
		if low.contains(k):
			return true
	return false


func _track_type_name(t: int) -> String:
	match t:
		Animation.TYPE_VALUE:
			return "值"
		Animation.TYPE_POSITION_3D:
			return "位移"
		Animation.TYPE_ROTATION_3D:
			return "旋转"
		Animation.TYPE_SCALE_3D:
			return "缩放"
		Animation.TYPE_BLEND_SHAPE:
			return "形变"
		_:
			return "类型%d" % t


func _find(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame

extends SceneTree
## 探针：`models/RunFire.glb`（Blender 里拼出来的跑打动作）能不能被 Godot 吃进去，
## 以及它的骨骼名和场上角色的骨架**对不对得上**（对不上就得重定向，对得上直接搬）。
##
## 这个 glb 只有骨架 + 一条动作（0 网格），导出命令见 `_blender_arisu/seed_runfire.py`。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_runfire_glb.gd -- --splat=off

const GLB := "res://models/RunFire.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 360)
	if not ResourceLoader.exists(GLB):
		print("[rf] !! 没有 %s" % GLB)
		quit(1)
		return
	var ps := load(GLB) as PackedScene
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await _wait(3)

	var ap := _find_anim(inst)
	var sk := _find_skel(inst)
	print("[rf] 节点树：")
	_dump(inst, 0, 3)
	if ap == null:
		print("[rf] !! 没有 AnimationPlayer")
		quit(1)
		return
	print("[rf] 骨架 %s，骨 %d 根" % [sk.name if sk else "（无）", sk.get_bone_count() if sk else 0])
	for clip in ap.get_animation_list():
		var a := ap.get_animation(String(clip))
		print("[rf] 动作「%s」 长度 %.3f s 轨道 %d 条 循环=%s"
			% [clip, a.length, a.get_track_count(), a.loop_mode])
		var heads := {}
		var bones := {}
		for t in a.get_track_count():
			var p := String(a.track_get_path(t))
			var i := p.rfind(":")
			var head := p.substr(0, i) if i >= 0 else p
			heads[head] = true
			var bone := p.substr(i + 1)
			bones[bone] = String(a.track_get_path(t))
		print("[rf]   路径前缀 %s" % str(heads.keys()))
		print("[rf]   前 3 条：%s" % str(bones.values().slice(0, 3)))

	# 和场上角色比：骨名一致就不需要重定向
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	var p := game.get_node_or_null("Player") as Player
	if p == null or p.anim == null:
		print("[rf] !! 场上没有 Player/AnimDriver")
		quit(1)
		return
	var psk := (p.anim as AnimDriver).skeleton
	var ours := {}
	for b in psk.get_bone_count():
		ours[String(psk.get_bone_name(b))] = true
	var a0 := ap.get_animation(ap.get_animation_list()[0])
	var miss := 0
	var seen := {}
	for t in a0.get_track_count():
		var path := String(a0.track_get_path(t))
		var bone := path.substr(path.rfind(":") + 1)
		if seen.has(bone):
			continue
		seen[bone] = true
		if not ours.has(bone):
			miss += 1
			if miss <= 8:
				print("[rf]   glb 里的骨在角色身上找不到：%s" % bone)
	print("[rf] 骨名比对：glb %d 根 / 角色 %d 根 / 找不到 %d 根"
		% [seen.size(), psk.get_bone_count(), miss])
	var pap: AnimationPlayer = (p.anim as AnimDriver).player
	var head := ""
	for t in pap.get_animation("Normal_Idle").get_track_count():
		var path := String(pap.get_animation("Normal_Idle").track_get_path(t))
		head = path.substr(0, path.rfind(":"))
		break
	print("[rf] 角色自己的轨道前缀：%s" % head)
	print("[rf] 结论：%s" % ("骨名全对得上，可以直接搬动画库（只改路径前缀）" if miss == 0
		else "有 %d 根对不上，需要重定向" % miss))
	quit(0)


func _dump(n: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	print("[rf]   %s%s (%s)" % ["  ".repeat(depth), n.name, n.get_class()])
	for c in n.get_children():
		_dump(c, depth + 1, max_depth)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null

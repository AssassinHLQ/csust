class_name AnimExtra
## 把「只有骨架 + 一两动作」的 glb 里的动作搬到**现有的** `AnimationPlayer` 上。
##
## ── 为什么要这么绕 ──
## `models/Arisu_ext.glb` 里那 27 条动作是**手工在 Blender 里拼、再整包导出**的。
## 要做「单独一条跑打开火动作」时，最省事的做法不是往 Arisu_ext 里塞第 28 条
## （那要重新导入整个模型、贴图、10 块嘴的形态键），而是：
##   · Blender 里只导出**骨架 + 那一条新动作**（`models/RunFire.glb`，0 网格）；
##   · 游戏启动时把这条动作搬进角色自己的 `AnimationPlayer`。
##
## ⚠️ 路径前缀必须改：两个 glb 的根节点名不一样，
##    新 glb 是 `Bip001/Skeleton3D:Bip001 Pelvis`，
##    角色自己的是 `Aris_Original_Mesh/bone_root/Bip001/Skeleton3D:Bip001 Pelvis`。
##    不改前缀的话动作会「加载成功但一根骨都不动」（`AnimationPlayer` 静默找不到节点）。
##
## 骨名本身是同一套骨架导出来的，所以不需要重定向 —— 这一点由调用方传 `sk`
## 让我们核对（`missing` 字段），别指望它自己发现。


## 把 `path` 里第一条（或指定名的）动作搬成 `as_name`。
## 返回报告：ok / name / tracks / seconds / head_from / head_to / missing / error
static func merge_glb(player: AnimationPlayer, path: String, as_name: String,
		sk: Skeleton3D = null) -> Dictionary:
	var rep := {"ok": false, "name": as_name, "tracks": 0, "seconds": 0.0,
		"head_from": "", "head_to": "", "missing": [] as Array, "error": ""}
	if player == null:
		rep["error"] = "player 为空"
		return rep
	if not ResourceLoader.exists(path):
		rep["error"] = "没有 " + path
		return rep
	var ps := load(path) as PackedScene
	if ps == null:
		rep["error"] = "不是 PackedScene：" + path
		return rep
	var inst: Node = ps.instantiate()
	var src := _find_player(inst)
	if src == null or src.get_animation_list().is_empty():
		rep["error"] = "glb 里没有 AnimationPlayer / 没有动作"
		inst.free()
		return rep

	var anim: Animation = null
	var picked := ""
	for clip in src.get_animation_list():
		anim = src.get_animation(String(clip))
		picked = String(clip)
		break
	if anim == null:
		rep["error"] = "取不到动作"
		inst.free()
		return rep
	anim = anim.duplicate(true)

	# 新 glb 的根段（`Bip001/Skeleton3D`）→ 角色自己的根段
	rep["head_from"] = _head_of(String(anim.track_get_path(0))) if anim.get_track_count() > 0 else ""
	rep["head_to"] = _own_head(player, sk)
	if rep["head_from"] == "":
		rep["error"] = "源动作的轨道路径里没有 `:`，不像骨骼动作"
		inst.free()
		return rep
	if rep["head_to"] == "":
		rep["error"] = "推不出角色自己的轨道前缀（动作照搬了，但不会驱动骨骼）"
	if rep["head_from"] != rep["head_to"]:
		for t in anim.get_track_count():
			var p := String(anim.track_get_path(t))
			var i := p.rfind(":")
			if i > 0:
				anim.track_set_path(t, NodePath(String(rep["head_to"]) + p.substr(i)))

	anim.loop_mode = Animation.LOOP_NONE
	if player.has_animation(as_name):
		player.remove_animation(as_name)
	if not player.has_animation_library(&""):
		player.add_animation_library(&"", AnimationLibrary.new())
	player.get_animation_library(&"").add_animation(as_name, anim)

	# 骨名核对：动作里出现、但目标骨架上没有的骨（有就说明不是同一套骨架）
	if sk != null:
		var have := {}
		for b in sk.get_bone_count():
			have[String(sk.get_bone_name(b))] = true
		var seen := {}
		for t in anim.get_track_count():
			var bone := _bone_of(String(anim.track_get_path(t)))
			if bone.is_empty() or seen.has(bone):
				continue
			seen[bone] = true
			if not have.has(bone):
				rep["missing"].append(bone)
	rep["ok"] = true
	rep["picked"] = picked
	rep["tracks"] = anim.get_track_count()
	rep["seconds"] = anim.length
	rep["sk_name"] = sk.name if sk != null else ""
	rep["sk_bones"] = sk.get_bone_count() if sk != null else 0
	inst.free()
	return rep


## 角色自己动作的根段（`Aris_Original_Mesh/bone_root/Bip001/Skeleton3D`）
## ⚠️ 不能只看「第一条动作的第一条轨道」：导进 Godot 的动作列表里可能混着
##    `RESET` 之类没有骨骼轨迹的动作，取到它就是空字符串，前缀改不动 →
##    动作「加载成功但一根骨都不动」。所以这里扫**所有**动作，取第一条真正带 `:`
##    的轨道；一条都没有才退回按 `root_node` + 骨架相对路径拼。
static func _own_head(player: AnimationPlayer, sk: Skeleton3D = null) -> String:
	for clip in player.get_animation_list():
		var a := player.get_animation(String(clip))
		if a == null:
			continue
		for t in a.get_track_count():
			var h := _head_of(String(a.track_get_path(t)))
			if h != "":
				return h
	if sk == null:
		return ""
	var root := player.get_node_or_null(player.root_node)
	if root == null:
		return ""
	var rel := String(root.get_path_to(sk))          # `bone_root/Bip001/Skeleton3D`
	var base := String(player.root_node)            # `Aris_Original_Mesh`
	return base.path_join(rel) if base != "" and base != "." else rel


static func _head_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(0, i) if i > 0 else ""


static func _bone_of(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""


static func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null

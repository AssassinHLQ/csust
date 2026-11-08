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
		# ⚠️ `AnimationPlayer` 没有 `remove_animation()`；删除动作在动作库上。
		#    原来这行会报 "Nonexistent function 'remove_animation'"（同一进程里
		#    出现第二个玩家实例时才会走到，例如场景切换/探针）。
		var old_lib := player.get_animation_library(&"")
		if old_lib != null:
			old_lib.remove_animation(as_name)
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


## 「根骨」：精确匹配（不是关键字 —— 把 "Bip001" 当关键字会连 `Bip001 Spine1` 一起命中）。
## 这些骨**只搬旋转，不搬位移**（见 `merge_glb_multi()` 里那段）。
const ROOT_BONES := ["Bip001", "bone_root", "bone_CH_root"]


static func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null


# ── 批量合并：把一个 glb 里的**多条**动作一起搬过来 ───────────────────────────
#
# `merge_glb()` 上面只搬「第一条」（跑打那条就是这么用的）。机甲的场合不一样：
# `models/Arisu_Battle_Carrier.glb` 里只有 `Idle` / `Walk` 两条，而
# `models/Arisu_Battle.glb` 有 35 条战斗动作 —— 两者是**同一套骨架**
# （本喵拆 GLB 核过：都是 145 关节的 skin，Arisu Carrier 只多 3 个网格节点，
#  动作里唯一「缺」的 10 根是 `Mouth_*` 口型网格，不是骨骼），所以直接搬轨道就行。
#
# 为什么不用 Blender 重导出：那样要重新导入模型 + 贴图 + 10 块嘴的形态键，
# 而这里只要「把动作曲线换个前缀」，运行时几毫秒的事。
#
# ⚠️ 传 `only` 时只搬这些名字；不传就全搬。
# ⚠️ 源 glb 里同名动作（比如 `Recorded` 那三条）会被跳过 —— 它们在 BA 素材里是
#    录制用的空壳（13 条轨道 / 2 根骨命中），搬过来只会污染动作列表。
static func merge_glb_multi(player: AnimationPlayer, path: String, rename: Dictionary,
		sk: Skeleton3D = null, only: Array = []) -> Dictionary:
	var rep := {"ok": false, "merged": [] as Array, "skipped": [] as Array,
		"missing_bones": {} as Dictionary, "error": ""}
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

	var want := {}
	for n in only:
		want[String(n)] = true
	var have_bones := {}
	if sk != null:
		for b in sk.get_bone_count():
			have_bones[String(sk.get_bone_name(b))] = true

	var head_to := _own_head(player, sk)
	if head_to == "":
		rep["error"] = "推不出目标动作的轨道前缀（搬过去一根骨都不会动）"
		inst.free()
		return rep

	# 先把库备好（`add_animation_library` 在动作库不存在时会报错）
	if not player.has_animation_library(&""):
		player.add_animation_library(&"", AnimationLibrary.new())
	var lib := player.get_animation_library(&"")

	var seen_names := {}
	for clip in src.get_animation_list():
		var src_name := String(clip)
		if not want.is_empty() and not want.has(src_name):
			continue
		if seen_names.has(src_name):
			rep["skipped"].append(src_name + "（重名）")
			continue
		seen_names[src_name] = true
		var anim: Animation = src.get_animation(clip)
		if anim == null or anim.get_track_count() == 0:
			rep["skipped"].append(src_name + "（空动作）")
			continue
		anim = anim.duplicate(true)

		# 换前缀：`Bip001/Skeleton3D:Bip001 Pelvis` → `<目标根>:Bip001 Pelvis`
		# ⚠️ 只改带 `:` 的（骨骼轨道）；**节点轨道**（路径里没有 `:`，例如模型根
		#    的 position / rotation）必须丢掉 —— 机甲是另一个节点，带着它的根位移
		#    会把整台机甲按角色的位移拽走（`anim_driver.gd` 里踩过同一个坑）。
		#
		# ⚠️⚠️ **根骨的 position 轨道也要丢掉**（这一条是本喵 2026-11-08 踩的坑）：
		#    本体的 `Normal_Idle` 在 `Bip001` 上有 16 个 position 关键帧（type=1），
		#    而机甲的 `Bip001` 绑定姿势和本体不一样。搬过来之后一播待机，
		#    整台机甲就被按本体的骨盆高度摆位、**沉到地面以下** ——
		#    实测炮口从 y=+0.387 掉到 y=-0.158（`_probe_carrier_fire` 当场报红）。
		#    根骨的**旋转**（type=2）保留：那是朝向，两具骨架共用同一套轴约定。
		#    位移交给 `Idle` / `Walk`（载具自带的那两条）和 `carrier_form` 自己的对齐逻辑。
		for t in range(anim.get_track_count() - 1, -1, -1):
			var p := String(anim.track_get_path(t))
			var i := p.rfind(":")
			if i <= 0:
				anim.remove_track(t)
				continue
			var bone := p.substr(i + 1)
			# 根骨的位移轨道 → 删（见上面那段）
			if ROOT_BONES.has(bone) and anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
				anim.remove_track(t)
				continue
			# 目标骨架上没有的骨（`Mouth_*` 口型）→ 删掉这条轨道，别留着空转
			if not have_bones.is_empty() and not have_bones.has(bone):
				anim.remove_track(t)
				if not rep["missing_bones"].has(bone):
					rep["missing_bones"][bone] = 0
				rep["missing_bones"][bone] = int(rep["missing_bones"][bone]) + 1
				continue
			anim.track_set_path(t, NodePath(head_to + ":" + bone))

		var as_name := String(rename.get(src_name, src_name))
		anim.loop_mode = Animation.LOOP_NONE
		if lib.has_animation(as_name):
			lib.remove_animation(as_name)
		lib.add_animation(as_name, anim)
		rep["merged"].append({"from": src_name, "to": as_name,
			"tracks": anim.get_track_count(), "seconds": anim.length})

	rep["ok"] = not (rep["merged"] as Array).is_empty()
	rep["head_to"] = head_to
	inst.free()
	return rep

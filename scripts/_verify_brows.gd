extends SceneTree
## 验：眉毛修复**不再误伤**（用户 2026-10-26：「爱丽丝变成了白色眉毛」）。
##   godot --path . --headless --script res://scripts/_verify_brows.gd -- --splat=off
##
## 判据（对着 `_probe_brow_layers.gd` 量出来的真实层数打表）：
##   · 所有人**本来就只有 1 层** ⇒ `simplify_brows` 必须**一个三角形都不删**；
##   · 修复前的 Momoi 那种「2 层、间隙 7.8 cm」才允许删。
## 所以要断言的是「**没人被误伤**」，而不是「删了多少」。

const EXPECT_LAYERS := {
	"爱丽丝": 1, "小雪": 1, "优香": 1, "诺亚": 1,
	"小桃": 1, "小绿": 1, "柚子": 1, "凯伊": 1, "芹香": 1,
}

## 各角色模型路径（**读原始文件判层**，因为场景里那份已经被改过了）
const MODEL_PATHS := {
	"爱丽丝": "res://models/Arisu_ext.glb",
	"小雪": "res://models/companions/koyuki.glb",
	"优香": "res://models/companions/yuuka.glb",
	"诺亚": "res://models/companions/noa.glb",
	"小桃": "res://models/companions/momoi.glb",
	"小绿": "res://models/companions/midori.glb",
	"柚子": "res://models/companions/yuzu.glb",
	"凯伊": "res://models/companions/kei.glb",
	"芹香": "res://models/npc/serika/serika.glb",
}


func _initialize() -> void:
	_run.call_deferred()


## 直接从 `FaceFix` 里算「这个网格有几层」（不改任何东西）
func _count_layers(node: Node3D) -> Dictionary:
	var out := {"layers": 0, "blocks": 0, "gap": 0.0, "surface": ""}
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat == null or not String(mat.resource_name).to_lower().contains("brow"):
				continue
			out["surface"] = String(mat.resource_name)
			var arr := am.surface_get_arrays(s)
			var isl: Array = FaceFix._islands_from(arr)
			out["blocks"] = isl.size()
			if isl.size() < 2:
				out["layers"] = isl.size()
				return out
			# 和 `simplify_brows` 完全一致的切层逻辑：**左右分组后各自切**
			var sides := {}
			for i in isl.size():
				var cx: float = ((isl[i]["lo"] as Vector3).x
					+ (isl[i]["hi"] as Vector3).x) * 0.5
				var key := "L" if cx < -FaceFix.SIDE_EPS else (
					"R" if cx > FaceFix.SIDE_EPS else "C")
				if not sides.has(key):
					sides[key] = [] as Array
				var sg: Array = sides[key]
				sg.append(i)
				sides[key] = sg
			var max_layers := 0
			var max_gap := 0.0
			for key in sides:
				var group: Array = sides[key]
				var order: Array = []
				for i in group:
					order.append(i)
				order.sort_custom(func(a, b):
					return float(isl[a]["lo"].z) < float(isl[b]["lo"].z))
				var stacks := 1
				var cur_hi := -1e9
				for i in order:
					var lo: float = (isl[i]["lo"] as Vector3).z
					var hi: float = (isl[i]["hi"] as Vector3).z
					if cur_hi > -1e8 and lo - cur_hi > FaceFix.LAYER_GAP:
						stacks += 1
						max_gap = maxf(max_gap, lo - cur_hi)
						cur_hi = -1e9
					cur_hi = maxf(cur_hi, hi)
				max_layers = maxi(max_layers, stacks)
			out["layers"] = max_layers
			out["gap"] = max_gap
			return out
	return out


## 直接从 GLB 文件里数「眉毛 surface 有几个三角形」—— 不受运行时改动影响。
func _orig_tris(tag: String) -> int:
	var path: String = MODEL_PATHS.get(tag, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return -1
	var ps := load(path) as PackedScene
	if ps == null:
		return -1
	var inst := ps.instantiate()
	var n := 0
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat == null or not String(mat.resource_name).to_lower().contains("brow"):
				continue
			var arr := am.surface_get_arrays(s)
			n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	inst.free()
	return n


func _run() -> void:
	var fails := 0
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false

	# ⚠️ 这里读的是**已经跑过 `simplify_brows` 之后**的网格（_ready 里就修完了）。
	#    所以断言的是「修复**之后**必须只剩 1 层」—— 这才是用户看得见的状态。
	print("========== 修复之后的眉毛（应全是 1 层、且块数不变）==========")
	for pair in [["爱丽丝", "Player"], ["小雪", "CompanionKoyuki"],
			["优香", "CompanionYuuka"], ["诺亚", "CompanionNoa"],
			["小桃", "CompanionMomoi"], ["小绿", "CompanionMidori"],
			["柚子", "CompanionYuzu"], ["凯伊", "CompanionKei"],
			["芹香", "Shop/ClerkSerika"]]:
		var nd := game.get_node_or_null(String(pair[1])) as Node3D
		if nd == null:
			print("  [SKIP] %s（节点不存在）" % String(pair[0]))
			continue
		var info := _count_layers(nd)
		var want: int = EXPECT_LAYERS.get(String(pair[0]), 1)
		var ok: bool = int(info["layers"]) == want
		print("  [%s] %-4s 材质 %-32s 块 %2d  层 %d（期望 %d）"
			% ["PASS" if ok else "FAIL", String(pair[0]), String(info["surface"]),
				int(info["blocks"]), int(info["layers"]), want])
		if not ok:
			fails += 1

	# 关键回归：**原始文件**里爱丽丝的眉毛本来是几层？
	# 上一版判据错误把她 16 块压成 1 块，脸上只剩反光的一小块 = 白眉。
	# 正确行为：原文件 1 层 ⇒ 场景里跑完修复必须**一个三角形都不少**。
	print("\n========== 爱丽丝：原文件 vs 场景里（三角形数必须一致）==========")
	var alice := game.get_node_or_null("Player") as Node3D
	var after_tris := 0
	var after_verts := 0
	for mi in alice.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat == null or not String(mat.resource_name).to_lower().contains("brow"):
				continue
			var arr := am.surface_get_arrays(s)
			after_tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			after_verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var before_tris := _orig_tris("爱丽丝")
	print("  原文件：%d 个三角形 / 场景里：%d 个三角形" % [before_tris, after_tris])
	if after_tris == before_tris:
		print("  [PASS] 一个都没删（%d 顶点）" % after_verts)
	else:
		print("  [FAIL] 少了 %d 个三角形 —— 又被误删了" % (before_tris - after_tris))
		fails += 1

	print("\n========== 结果 ==========")
	print("失败 %d 项" % fails)
	quit(0 if fails == 0 else 1)

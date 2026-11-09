extends Node3D
## 电竞房碰撞（2026-11-09 v3）：用**离线烘好的**「一件物体一个盒子」。
##
## ── 使用者原话 ──
## 「你总是做大了碰撞，我体验不好，书本桌子本来是两个不同的碰撞，
##   结果你只做一个大的碰撞」
##
## ── 为什么旧版会「做成一坨」──
## 屋壳 GLB 是**按材质合并**的：`build_esports_room.py::merge_by_material()`
## 把 FBX 里 **738 个独立物件**合成 **59 个材质桶**（为省 draw call）。
## 于是「书」和「桌子」如果同材质就进了同一个网格 —— 只能给整个网格一个盒子，
## 碰撞自然变成一大坨，人也钻不过桌子底下。
##
## ── 现在怎么做 ──
## 分两步，**离线算好、运行时零开销**：
##   ① `tools/dump_esports_parts.py`（Blender）
##      从容**未合并**的 FBX 里逐件量世界 AABB → `models/esports_room/esports_parts.json`
##      实测：728 件物体（对比 GLB 只有 59 个）
##          小到 0.33×0.08×0.07 的书、0.42×0.26×0.08 的摆件，**各自独立**
##   ② `scripts/_bake_esports_parts.gd`（Godot）
##      把 JSON 烘成 `scenes/esports_collision_baked.tscn`
##      —— 一件一个 `BoxShape3D`，共 **335 个形状**
##
## 本脚本只负责**自检**：确认 `BakedCollision` 那个实例在。
## 真正干活的形状全在场景文件里，运行时不需要建任何东西
## （旧版运行时建 760 个盒子要 **575 ms**，现在 0 ms）。

## 烘好的碰撞场景（在 `esports_room.tscn` 里被实例化成 `BakedCollision`）
const BAKED_NODE := "BakedCollision"

var _reported := false


func _ready() -> void:
	await get_tree().process_frame
	build_collision()


## 对外入口（探针也调）。**幂等**：只报一次。
func build_collision() -> void:
	if _reported:
		return
	_reported = true
	var baked := get_node_or_null(BAKED_NODE)
	if baked == null:
		# ⚠️ 不要静默失败：没有碰撞玩家会直接掉出房间
		push_warning("[EsportsCol] 没找到 %s —— 碰撞场景丢了？"
			% BAKED_NODE
			+ " 重新生成：blender 跑 tools/dump_esports_parts.py，"
			+ "再 godot 跑 scripts/_bake_esports_parts.gd")
		print("[EsportsCol] !! 缺 %s，屋子没有碰撞" % BAKED_NODE)
		return
	var body := baked.get_node_or_null("AutoCol")
	var n := 0 if body == null else body.get_child_count()
	print("[EsportsCol] 用烘好的碰撞：%s，%d 个形状（一件物体一个盒子）" % [
		BAKED_NODE, n])

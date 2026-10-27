extends Node3D
## 校园泼溅分块管理：按「相机视锥 + 距离」逐块开关 `splat_node.visible`。
##
## 为什么有用：GDGS 的 Compute 后端每帧对**所有已注册的点**做投影 + 基数排序。
## 节点 `visible = false` 时，投影着色器在 `is_visible < 0.5` 那一步直接 return
## （`gsplat_projection.glsl:283`），于是那一块的点几乎不花时间 —— 显存里的
## 合并缓冲不变（点数据还在），只是每帧的处理量变小。
##
## 块由 `scripts/_split_sog.gd` 离线切好，生成本场景；每块共用同一个 offset，
## 拼起来与原校园完全重合。切块数为 nx × nz，越大剔得越细、但加载/注册的
## 次数也越多（GDGS 每注册一块都要重建合并缓冲）。

## 超过这个距离的块不渲染（站在广场边缘时，最远的那排校园块可以直接省掉）。
@export var max_distance := 140.0
@export var player_path := NodePath("../Player")
## 玩家在这个盒子里时全部隐藏（大厅内部；墙本来就把校园挡死了）。
@export var inside_bounds := AABB(Vector3(-15.0, -2.0, -10.5), Vector3(30.0, 12.0, 21.0))

var _chunks: Array[Node3D] = []
var _aabbs: Array[AABB] = []
var _seen: Array[bool] = []
var _shown := -1
var _cam: Camera3D
var _player: Node3D


func _ready() -> void:
	_player = get_node_or_null(player_path)
	for c in get_children():
		if c.has_method("force_start") and c.has_method("is_ready"):
			_chunks.append(c)
			_aabbs.append(AABB())
			_seen.append(false)
	print("[CampusChunks] %d 块，距离上限 %.0f m" % [_chunks.size(), max_distance])


func _process(_delta: float) -> void:
	if _player == null:
		return
	if _cam == null:
		_cam = _player.get("cam") as Camera3D
		if _cam == null:
			return
	var inside := inside_bounds.has_point(_player.global_position)
	var cam_pos := _cam.global_position
	var shown := 0
	for i in _chunks.size():
		var ch := _chunks[i]
		if not bool(ch.call("is_ready")):
			continue
		if not _seen[i]:
			_seen[i] = true
			_aabbs[i] = ch.call("content_world_aabb")
		var node := ch.get("splat_node") as Node3D
		if node == null:
			continue
		var want := false
		if not inside:
			var aabb := _aabbs[i]
			var near := aabb.get_center().distance_to(cam_pos) - aabb.size.length() * 0.5
			want = near <= max_distance and _aabb_visible(_cam, aabb)
		if node.visible != want:
			node.visible = want
		if want:
			shown += 1
	if shown != _shown:
		_shown = shown
		print("[CampusChunks] 可见 %d / %d 块" % [shown, _chunks.size()])


## AABB 与视锥相交？（中心或 8 个角任意一个在视锥里就算）
##
## ⚠️ 不用 `get_frustum()` 手动判平面：Godot 那几个平面的法线朝向约定容易搞反
##    （第一版就反了，结果 9 块全被剔掉、帧率飙到 293 fps 但画面里没有校园）。
##    `is_position_in_frustum()` 是引擎自己实现的，方向不会错。
func _aabb_visible(cam: Camera3D, aabb: AABB) -> bool:
	if cam.is_position_in_frustum(aabb.get_center()):
		return true
	for k in 8:
		var corner := Vector3(
			aabb.position.x + (aabb.size.x if (k & 1) else 0.0),
			aabb.position.y + (aabb.size.y if (k & 2) else 0.0),
			aabb.position.z + (aabb.size.z if (k & 4) else 0.0))
		if cam.is_position_in_frustum(corner):
			return true
	return false

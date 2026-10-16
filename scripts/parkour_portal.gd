class_name ParkourPortal
extends Area3D
## 传送门（一对）：**走进去就出现在对面那台**，用来跨过 ≥10 m 的大缺口（被动式）。
##
## ── 防「无限往返」的两道保险（缺一个就会变成乒乓球）──
##   1. **落点偏移**：`exit_offset` 是相对**目标门自己的局部坐标**（默认朝门的 +Z 前方、
##      抬高 0.10 m），要把它放在目标门触发盒**外面** —— 否则传送完那一帧，
##      玩家的胶囊还在目标门的盒子里，下一帧 `body_entered` 就把他送回来了。
##   2. **冷却 0.6 s**：`_ready_at` 在**两台门上一起**设，免得来回弹。
##
## ⚠️ 只把**竖直**速度清零、水平保留：不然穿过门之后人会「钉」在原地，手感断掉。
##
## ⚠️ 落点抬高 0.10 m（不是 0.05）：门常摆在台面边缘，抬高一点免得出生就嵌进地板。

signal teleported(from_name: String, to_name: String)

@export var target_path: NodePath
## 落点（目标门的局部坐标偏移）
@export var exit_offset := Vector3(0.0, 0.10, 1.2)
@export var cooldown := 0.6

var teleports := 0
var _ready_at := 0
var _target: ParkourPortal


func _ready() -> void:
	body_entered.connect(_on_body_entered)


## 对面那台（自检要量「是不是真的到了对岸」）
func target() -> ParkourPortal:
	if _target == null:
		_target = get_node_or_null(target_path) as ParkourPortal
	return _target


## 这台门的落点世界坐标（自检按它核对「传送距离」）
func exit_point() -> Vector3:
	var t := target()
	return t.global_transform * exit_offset if t != null else global_position


func _on_body_entered(body: Node3D) -> void:
	var p := body as Player
	if p == null or Time.get_ticks_msec() < _ready_at:
		return
	var t := target()
	if t == null:
		push_warning("[ParkourPortal] %s 的 target_path 指不到另一台门" % name)
		return
	p.global_position = t.global_transform * exit_offset
	p.velocity.y = 0.0
	teleports += 1
	var now := Time.get_ticks_msec()
	_ready_at = now + int(cooldown * 1000.0)
	t._ready_at = _ready_at
	teleported.emit(String(name), String(t.name))
	Sfx.play("ui_open")
	print("[Parkour] 传送门 %s → %s（落点 %s，第 %d 次）"
		% [name, t.name, str(p.global_position.snappedf(0.01)), teleports])

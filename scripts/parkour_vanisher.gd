class_name ParkourVanisher
extends StaticBody3D
## 消失方块：**踩上 `delay` 秒后塌掉、`respawn_delay` 秒后回来**（被动式）。
##
## ── 踩上去怎么知道的 ──
## `StaticBody3D` 收不到 `body_entered`，所以在它上面挂一个薄薄的 `Area3D` 子节点
## `Trigger`（在 .tscn 里），由它来「点火」。玩家一站上去就进入 ARMED，
## `delay` 秒后把 `collision_layer` 置 0（碰撞消失，人开始下落）+ `visible = false`。
##
## ⚠️ 关碰撞走 **`set_deferred("disabled", true)`**，不直接改 `disabled`：
##    物理回调里同步改形状状态会警告 + 丢帧。网格 `visible` 一起切。
##
## ⚠️ 恢复时人可能正站在方块里（2.5 s 足够掉走，但自检里会强行把人放回来）——
##    Godot 会把重叠的 `CharacterBody3D` 推开，不会卡死。

enum State { SOLID, ARMED, GONE }

@export var delay := 0.6
@export var respawn_delay := 2.5

var state := State.SOLID
var drops := 0
var _t := 0.0


func _ready() -> void:
	var trig := get_node_or_null("Trigger") as Area3D
	if trig == null:
		push_warning("[ParkourVanisher] %s 没有 Trigger 子节点，永远不会塌" % name)
		return
	trig.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player) or state != State.SOLID:
		return
	state = State.ARMED
	_t = 0.0


func _physics_process(delta: float) -> void:
	match state:
		State.ARMED:
			_t += delta
			if _t >= delay:
				_vanish()
		State.GONE:
			_t += delta
			if _t >= respawn_delay:
				restore_now()


func _vanish() -> void:
	state = State.GONE
	_t = 0.0
	drops += 1
	_set_solid(false)
	print("[Parkour] 消失方块 %s：塌了（第 %d 次）" % [name, drops])


## 恢复（自检也会直接调它，省得等 2.5 s）
func restore_now() -> void:
	state = State.SOLID
	_t = 0.0
	_set_solid(true)


func _set_solid(on: bool) -> void:
	var col := get_node_or_null("Col") as CollisionShape3D
	if col != null:
		col.set_deferred("disabled", not on)
	visible = on


func is_gone() -> bool:
	return state == State.GONE


func state_name() -> String:
	match state:
		State.ARMED:
			return "Armed"
		State.GONE:
			return "Gone"
		_:
			return "Solid"

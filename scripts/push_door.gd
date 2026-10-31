extends Node3D
## 可推动的门（挂在铰链 Node3D 上，门板是子节点，局部 x = +半宽）。
## 玩家走进 open_distance 米内，门向外转开；走开自动关。
## 用「离玩家距离」而不是 Area3D：烘出来 8 扇门也不贵，而且不依赖碰撞层。

@export var open_deg := -95.0
@export var open_distance := 2.3
@export var speed_deg := 260.0
## 门板在铰链局部里的朝向：0 = 绕 y 轴开
var _player: Node3D
var _panel: StaticBody3D

func _ready() -> void:
	add_to_group("push_door")
	_panel = get_node_or_null("Panel") as StaticBody3D

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	var d := _player.global_position.distance_to(global_position)
	var target := deg_to_rad(open_deg) if d <= open_distance else 0.0
	rotation.y = move_toward(rotation.y, target, deg_to_rad(speed_deg) * delta)
	# 门开大了就把门板的碰撞关掉：开着的时候不该挡人（关着照样挡）
	if _panel != null:
		var should_block := absf(rotation.y) < deg_to_rad(35.0)
		if _panel.get_collision_layer_value(1) != should_block:
			_panel.set_collision_layer_value(1, should_block)

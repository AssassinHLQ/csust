class_name PC5090Rig
extends Node3D
## 柴关电脑城买下的八卡 5090 整机：买完后出现在游戏开发部活动室南墙边。
## 靠近按 F 开机：风扇转、机箱灯亮、状态牌亮起。

@onready var body: StaticBody3D = $Body
@onready var shape: CollisionShape3D = $Body/Collision
@onready var hint: Label3D = $Hint
@onready var status: Label3D = $Status
@onready var fans: Node3D = $Fans
@onready var light: OmniLight3D = $Light

var _booted := false
var _near := false


func _ready() -> void:
	_set_active(ShopClerk.is_bought())
	set_process(true)


func _process(delta: float) -> void:
	if not visible and ShopClerk.is_bought():
		_set_active(true)
	if _booted:
		for f in fans.get_children():
			f.rotate_y(delta * 22.0)
	_update_near()


func _set_active(on: bool) -> void:
	visible = on
	body.collision_layer = 1 if on else 0
	body.collision_mask = 1 if on else 0
	for cs in body.get_children():
		if cs is CollisionShape3D:
			(cs as CollisionShape3D).disabled = not on
	hint.visible = false
	status.visible = _booted if on else false
	light.light_energy = 1.6 if (on and _booted) else 0.0


func _update_near() -> void:
	if not visible:
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	_near = p != null and global_position.distance_to(p.global_position) < 2.6
	hint.visible = _near and not _booted


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _booted or not _near:
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_F:
		return
	_booted = true
	hint.visible = false
	status.visible = true
	light.light_energy = 1.6
	get_viewport().set_input_as_handled()

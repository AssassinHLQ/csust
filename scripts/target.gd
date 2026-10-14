class_name Target
extends StaticBody3D
## 可击毁的靶子：吃伤害、闪一下、打光了就碎。
## 用法：挂在一个带 CollisionShape3D 和 MeshInstance3D 的场景上。

signal died(by_damage: float)

@export var max_health := 100.0
@export var respawn_time := 4.0
@export var score_value := 100

var health: float
var _dead := false

@onready var mesh: MeshInstance3D = get_node_or_null("Mesh")
@onready var _collision: CollisionShape3D = get_node_or_null("Collision")


func _ready() -> void:
	health = max_health


func take_damage(amount: float, _hit_pos := Vector3.ZERO, _hit_dir := Vector3.ZERO) -> void:
	if _dead:
		return
	health -= amount
	_flash()
	if health <= 0.0:
		_die(amount)


func _flash() -> void:
	if mesh == null:
		return
	var mat := mesh.get_active_material(0)
	if mat == null:
		return
	var base: Color = mat.albedo_color
	mat.albedo_color = Color(1, 1, 1)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", base, 0.12)


func _die(_by_damage: float) -> void:
	_dead = true
	died.emit(_by_damage)

	# 塌下去
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector3(1.15, 0.05, 1.15), 0.18)
	if _collision:
		_collision.set_deferred("disabled", true)
	tw.chain().tween_interval(respawn_time)
	tw.chain().tween_callback(_respawn)


func _respawn() -> void:
	_dead = false
	health = max_health
	if _collision:
		_collision.set_deferred("disabled", false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.25)


func health_ratio() -> float:
	return clampf(health / max_health, 0.0, 1.0)

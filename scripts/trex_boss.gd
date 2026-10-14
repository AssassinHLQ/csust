extends Boss
## 霸王龙优香的主动攻击：短暂地面预警后，朝玩家当前位置释放扇形冲击波。
## 飞猪仍使用 Boss 基类，不会获得攻击行为。

@export var attack_interval := 4.5
@export var windup_time := 0.9
## 发现玩家并起手的水平距离（m）
@export var attack_range := 18.0
@export_range(1.0, 90.0, 1.0) var attack_half_angle_degrees := 32.0
@export var attack_damage := 24.0
## 预警圈圆心离霸王龙的水平距离（m）
@export var attack_reach := 5.0
## 预警圈半径（m）。**这个值同时就是实际伤害半径** —— 两者必须一致，
## 否则玩家站在圈外仍被扣血，预警圈就变成骗人的了。
@export var attack_radius := 4.8
@export var knockback_force := 8.0

var _attack_cooldown := 2.0
var _attacking := false
var _telegraph: MeshInstance3D


func _ready() -> void:
	super._ready()
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "AttackTelegraph"
	var disk := CylinderMesh.new()
	disk.top_radius = 1.0
	disk.bottom_radius = 1.0
	disk.height = 0.025
	disk.radial_segments = 32
	_telegraph.mesh = disk
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.18, 0.06, 0.42)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.12, 0.02)
	mat.emission_energy_multiplier = 1.2
	_telegraph.material_override = mat
	_telegraph.visible = false
	add_child(_telegraph)


func _process(delta: float) -> void:
	if _dead or _attacking:
		return
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	var player := _find_player()
	if player == null:
		return
	var to_player := player.global_position - global_position
	var flat_to_player := Vector3(to_player.x, 0.0, to_player.z)
	if to_player.length() > attack_range or flat_to_player.length_squared() < 0.001:
		return
	if facing().dot(flat_to_player.normalized()) < cos(deg_to_rad(attack_half_angle_degrees)):
		return
	_attack(player)


func _attack(_player: Player) -> void:
	_attacking = true
	_attack_cooldown = attack_interval
	# 预警圈**就是**伤害区：圆心在正面 attack_reach 处、半径 attack_radius。
	# ⚠️ 判定用的区域必须和画出来的圈完全一致，见 attack_radius 的注释。
	var center := global_position + facing() * attack_reach
	_telegraph.global_position = Vector3(center.x, 0.08, center.z)
	_telegraph.scale = Vector3(attack_radius * 0.55, 1.0, attack_radius * 0.55)
	_telegraph.visible = true
	var tw := create_tween()
	tw.tween_property(_telegraph, "scale",
		Vector3(attack_radius, 1.0, attack_radius), windup_time)
	await tw.finished
	if not is_instance_valid(self) or _dead:
		_attacking = false
		return

	var now_player := _find_player()
	if now_player != null:
		var flat := Vector3(
			now_player.global_position.x - center.x, 0.0,
			now_player.global_position.z - center.z)
		if flat.length() <= attack_radius:
			now_player.take_damage(attack_damage, global_position, knockback_force)
	_telegraph.visible = false
	_attacking = false


func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Player
	return get_tree().root.find_child("Player", true, false) as Player

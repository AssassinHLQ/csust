extends Node3D
## 玩法场景总控：把 Player / Weapon / HUD / 高斯泼溅校园接起来，记账击杀。

## 掉到这个高度以下就判定「掉出悬浮平台」，送回出生点（护栏之外的保险）
const FALL_LIMIT := -60.0

var _player: Player
var _weapon: Weapon
var _hud: CanvasLayer
var _splat: SplatScene
var _boss: Boss
var _spawn := Vector3.ZERO
var _score := 0
var _shots := 0
var _hits := 0


func _ready() -> void:
	_player = $Player
	_weapon = $Player/Weapon
	_hud = $HUD
	_splat = get_node_or_null("SplatScene") as SplatScene
	_boss = get_node_or_null("Boss") as Boss
	_spawn = _player.global_position

	_hud.bind(_player, _weapon)
	if _splat and _hud.has_method("bind_splat"):
		_hud.bind_splat(_splat)
	if _boss and _hud.has_method("bind_boss"):
		_hud.bind_boss(_boss)
		_boss.died.connect(_on_target_died)
	_weapon.fired.connect(func(_i: int) -> void: _shots += 1)

	for target in get_tree().get_nodes_in_group("targets"):
		if target.has_signal("died"):
			target.died.connect(_on_target_died)
	# 场景里的靶子没进组也接一下
	for child in get_children():
		if child is Target and not child.is_in_group("targets"):
			child.died.connect(_on_target_died)


func _process(_delta: float) -> void:
	if _player and _player.global_position.y < FALL_LIMIT:
		_player.global_position = _spawn
		_player.velocity = Vector3.ZERO
		print("[game] 掉出平台，已送回出生点")


func _on_target_died(_by: float) -> void:
	_score += 1
	_hits += 1


func stats() -> Dictionary:
	return {
		"score": _score,
		"shots": _shots,
		"hits": _hits,
		"accuracy": 0.0 if _shots == 0 else float(_hits) / float(_shots),
	}

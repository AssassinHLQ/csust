extends Node3D
## 玩法场景总控：把 Player / Weapon / HUD / 高斯泼溅校园接起来，记账击杀。

## 掉到这个高度以下就判定「掉出悬浮平台」，送回出生点（护栏之外的保险）
const FALL_LIMIT := -60.0

var _player: Player
var _weapon: Weapon
var _hud: CanvasLayer
## 场上所有泼溅场地（现在是校园 + 画室609 两份；按类型收，不写死节点名）
var _splats: Array[SplatScene] = []
## 场上所有 Boss「木桩」（现在是霸王龙优香 + 飞猪优香两位）
var _bosses: Array[Boss] = []
var _companions: Array[Companion] = []
var _spawn := Vector3.ZERO
var _score := 0
var _shots := 0
var _hits := 0


func _ready() -> void:
	_player = $Player
	_weapon = $Player/Weapon
	_hud = $HUD
	_spawn = _player.global_position

	_hud.bind(_player, _weapon)

	# 泼溅场地也是一场一行：两份（校园 / 画室609）同时解码时，玩家得分清
	# 是哪一份在等。HUD 侧 bind_splats() 按传入顺序从上往下排。
	for child in get_children():
		if child is SplatScene:
			_splats.append(child as SplatScene)
	if not _splats.is_empty():
		if _hud.has_method("bind_splats"):
			_hud.bind_splats(_splats)
		elif _hud.has_method("bind_splat"):
			_hud.bind_splat(_splats[0])

	# Boss 与同伴都是场景里的直接子节点，按类型收一遍（不写死节点名，
	# 以后再加一位 Boss / 一名同伴只要往场景里摆就行）
	for child in get_children():
		if child is Boss:
			var boss := child as Boss
			_bosses.append(boss)
			boss.died.connect(_on_target_died)
		elif child is Companion:
			_companions.append(child as Companion)
	if not _bosses.is_empty() and _hud.has_method("bind_bosses"):
		_hud.bind_bosses(_bosses)
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

class_name DarkGate
extends Node3D
## 第 8 段「暗网黑市交易」的入口闸门：**玩家跑进黑市才把比纳喊出来**。
##
## 用户 2026-10-19：「比纳不能一开始就加载，得进入黑市才加载」——
## 比纳那份 FBX（44 骨）+ 凹包碰撞在开场加载要白等一次；
## 所以 `parkour.tscn` 里只摆这个**空节点**（没有网格、没有碰撞），
## 玩家跑到 `trigger_x` 以西时才 `instantiate` `scenes/dark_boss.tscn`。
##
## `game.gd` 按 `dark_gates` 组连线 `boss_spawned`：把它加进 `_bosses`、
## 接上 `died`、并让 HUD 补一条血条（`hud.gd::add_boss`）。

signal boss_spawned(boss: Boss)

const BOSS_SCENE := preload("res://scenes/dark_boss.tscn")

## 玩家 x ≤ 这个值就开打。生成器按「本段第一块板的东沿 +2 m」写进场景。
@export var trigger_x := -340.0
## 比纳出场位置（相对闸门）：往西 12 m、往上 10 m —— 吊在头顶，不贴脸。
@export var spawn_offset := Vector3(-12.0, 10.0, 0.0)

var _spawned := false
var _player: Player


func _ready() -> void:
	add_to_group("dark_gates")


func _physics_process(_delta: float) -> void:
	if _spawned:
		set_physics_process(false)
		return
	if _player == null:
		# 玩家可能还没进树（开场剧情前就有 _ready）——每帧找一次，找到就缓存
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	if _player.global_position.x > trigger_x:
		return
	spawn()


## 立刻喊人。自检 / 截图探针也走这个入口（免得等玩家跑 300 m）。
func spawn() -> Boss:
	if _spawned:
		return get_node_or_null("../DarkBoss") as Boss
	var boss := BOSS_SCENE.instantiate() as Boss
	if boss == null:
		push_error("[DarkGate] 比纳场景实例化失败")
		return null
	boss.name = "DarkBoss"
	get_parent().add_child(boss)          # 挂到 Route 下 → 路径仍是 Route/DarkBoss
	boss.global_position = global_position + spawn_offset
	_spawned = true
	set_physics_process(false)
	print("[DarkGate] 玩家进入黑市（x ≤ %.2f）→ 比纳加载：位置 %s"
		% [trigger_x, str(boss.global_position.snappedf(0.01))])
	boss_spawned.emit(boss)
	return boss


## 已经喊过了没有（自检用）
func spawned() -> bool:
	return _spawned

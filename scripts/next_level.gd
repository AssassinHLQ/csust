extends Node3D
## 「下一场景」总控（scenes/next_level.tscn）。
##
## 房间里没有上一关的东西：切进来时 SceneTree 已经把 game.tscn 整棵树 free 了，
## 所以这里只有本场景自己的玩家 / HUD / 两盏灯和一扇返回门。显存账在
## `scene_flow.gd` 里记（切换前 / 切换后 / 稳定后各一次）。

const SceneFlow := preload("res://scripts/scene_flow.gd")

@onready var _player: Node3D = $Player
@onready var _hud: CanvasLayer = $HUD


func _ready() -> void:
	# 从哪扇门进来就落在哪扇门前；没经过门（直接跑这个场景）就用 SpawnPoint
	var entry := SceneFlow.consume_entry()
	var gate := SceneFlow.find_gate(self, String(entry.get("gate", "")))
	var point: Vector3 = ($SpawnPoint as Node3D).global_position
	if gate != null:
		point = gate.call("arrival_point")
	_player.global_position = point
	_player.set("velocity", Vector3.ZERO)
	_hud.bind(_player, _player.get_node("Weapon"))
	print("[NextLevel] 门厅就绪：玩家落点 %s（来源门「%s」），节点 %d 个"
		% [str(point.snappedf(0.01)), String(entry.get("gate", "")),
			get_tree().get_node_count()])
	SceneFlow.report_memory("门厅就绪")

extends Node3D
## 游戏开发部活动室：模型改成运行时按路径加载，缺模型时只少这栋房子的网格。
##
## 为什么 —— 模型（Sketchfab 作者：起航扬帆了）授权未核实，`.gitignore` 第 93 行
## 把它挡在仓库外。如果写成 `.tscn` 的 `[ext_resource]`，缺模型时 Godot 直接：
##
##     ERROR: Parse Error: [ext_resource] referenced non-existent resource
##     ERROR: Failed loading resource: res://scenes/gamedev_room.tscn
##
## 整个场景加载失败，而 `game.tscn` 又引用了本场景 —— 所以真实后果不是
## 「少一栋房子」，是**游戏根本起不来**（提交 165389a 的说明写的是前者，实测是后者）。
##
## 改成运行时加载后，才真的兑现「缺模型时只少这栋房子」：
## 灯、招牌、碰撞都还在场景里，只是没有房间的网格。
##
## 场景结构（改之前 / 之后一致）：
##   GameDevRoom
##     Model(Node3D, 绕 Y 转 90°)   ← 本脚本把 glb 挂到这里
##       LightA / LightB / LampA_* / LampB_* / SignBoard / Sign / Collision
##   PC5090Rig
## 把 glb 挂在 Model 下面、而不是把 Model 整个换掉，是为了让所有子节点的
## transform 保持原样（它们本来就是相对那个旋转过的父节点摆的）。

const MODEL := "res://models/gamedev_room/gamedev_room.glb"

@onready var _model: Node3D = $Model


func _ready() -> void:
	if not ResourceLoader.exists(MODEL):
		# 按设计允许缺失：只警告，不报错。
		push_warning("[GameDevRoom] 模型不在（按设计允许），只少了房间网格：%s" % MODEL)
		return

	var ps := load(MODEL) as PackedScene
	if ps == null:
		push_warning("[GameDevRoom] 模型加载失败，只少了房间网格：%s" % MODEL)
		return

	var inst := ps.instantiate()
	if inst == null:
		push_warning("[GameDevRoom] 模型实例化失败，只少了房间网格：%s" % MODEL)
		return

	inst.name = "RoomMesh"
	_model.add_child(inst)

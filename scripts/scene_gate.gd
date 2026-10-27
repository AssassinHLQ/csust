extends Node3D
## 场景入口（门 / 传送门）：站在跟前按 F → 切到 `target_scene`。
##
## 交互方式与屋里的电脑（`hut_computer.gd`）、芹香（`shop_clerk.gd`）一致：
## 走近 → 提示牌亮起 → 按 F。判定半径用 `Trigger`（Area3D）的球体，改大小直接
## 拖 `Trigger/Shape` 的 `radius` 即可。
##
## 几何体全部写在 `scenes/scene_gate.tscn` 里（门框三块 + 发光门板 + 两块字），
## 编辑器里看得见、拖得动、缩放也行；这个脚本只负责交互和落点。
##
## 落点：玩家从目标场景回来时，落在本门**正面**（本地 +Z）`arrival_offset` 处。
## 所以摆门的时候要让 +Z 朝向房间里面 —— 贴北墙的门 rotation.y = 0，
## 贴南墙的门 rotation.y = PI（scene_gate.tscn 的门板也是朝 +Z 的）。

const SceneFlow := preload("res://scripts/scene_flow.gd")

@export_file("*.tscn") var target_scene := "res://scenes/next_level.tscn"
## 到了目标场景后落在哪个门前（那个门节点的 `gate_id`）；空 = 目标场景自己的出生点
@export var target_spawn := ""
## 本门的 id。别的场景返回时用它找位置，场上唯一即可。
@export var gate_id := ""
## 门上的标题与走近后的提示
@export var title := "下一场景"
@export var prompt := "按 F 进入"
@export var enabled := true
## 从别的场景回到本门时，玩家站在哪里（本节点局部坐标，+Z = 门的正面）
@export var arrival_offset := Vector3(0.0, 0.05, 1.30)

var _in_range := false

@onready var _trigger: Area3D = $Trigger
@onready var _title: Label3D = $Title
@onready var _prompt: Label3D = $Prompt


func _ready() -> void:
	add_to_group(SceneFlow.GATE_GROUP)
	_title.text = title
	_prompt.text = prompt
	_prompt.visible = false
	_trigger.body_entered.connect(_on_body_entered)
	_trigger.body_exited.connect(_on_body_exited)
	print("[SceneGate] 「%s」id=%s → %s（落点门「%s」），世界位置 %s"
		% [title, gate_id, target_scene, target_spawn,
			str(global_position.snappedf(0.01))])


func _process(_delta: float) -> void:
	var want := _in_range and enabled and not SceneFlow.switching
	if _prompt.visible != want:
		_prompt.visible = want


func _input(event: InputEvent) -> void:
	if not enabled or not _in_range or SceneFlow.switching:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and k.keycode == KEY_F:
		enter()


## 触发切换。公开出来方便探针直接调，不用模拟键盘。
func enter() -> void:
	if not enabled or SceneFlow.switching:
		return
	print("[SceneGate] 进入「%s」：%s" % [title, target_scene])
	SceneFlow.switch_scene(target_scene, target_spawn, gate_id)


## 从别的场景回来时玩家的落点（世界坐标）。
func arrival_point() -> Vector3:
	return global_transform * arrival_offset


func _on_body_entered(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_in_range = true


func _on_body_exited(body: Node3D) -> void:
	if body != null and body.is_in_group("player"):
		_in_range = false

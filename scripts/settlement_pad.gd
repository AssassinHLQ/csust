class_name SettlementPad
extends Node3D
## 结算区（最后平台的小屋里，2026-10-20）。
##
## 用户：「这个房子是结算区，可以将资产转银行卡里面，玩完了市场，保证金可以退回银行卡了，
## 转化完毕后，负债可以用银行卡里面扣钱抵押」。
##
## 站上来（水平 1.5 m、竖直 1.2 m 内）就自动结算一次，3 s 冷却 —— 不用按键，
## 免得和「按 F 拾取 5090」抢同一个键（`Futures.ask_prompt` 同一时刻只允许一个 owner）。
##
## 结算内容见 `ParkourFutures.settle_all()`：资产卖光 + 保证金退回 → 银行卡，
## 再用银行卡还债（不够就还到 0）。头顶一块 billboard 牌子写清楚规则。

const RADIUS := 1.5
const COOLDOWN := 3.0

var _cool := 0.0
var _inside := false


func _ready() -> void:
	add_to_group("settlement_pads")
	_build_sign()


func _build_sign() -> void:
	var lab := Label3D.new()
	lab.name = "Sign"
	lab.text = "结算区\n站上来：资产 → 银行卡\n保证金退回 · 自动还债"
	lab.font_size = 30
	lab.outline_size = 10
	lab.pixel_size = 0.008
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = false      # 让墙挡住，里面才看得到
	lab.modulate = Color(0.6, 1.0, 0.75)
	lab.position = Vector3(0.0, 1.75, 0.6)
	add_child(lab)


func _physics_process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var d := player.global_position - global_position
	var near := Vector2(d.x, d.z).length() <= RADIUS and absf(d.y) <= 1.2
	if not near:
		_inside = false
		return
	if _inside or _cool > 0.0:
		return
	_inside = true
	_cool = COOLDOWN
	var fut := get_tree().get_first_node_in_group("futures")
	if fut != null and fut.has_method("settle_all"):
		fut.call("settle_all")

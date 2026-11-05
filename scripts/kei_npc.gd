extends Companion
## 第二场景里的**凯伊**：站桩的整备工，负责把「阿比·埃舒」重组到爱丽丝身上。
##
## 用户 2026-11-05：「我要载具的……花钱找凯伊，现在不是第二场景就爱丽丝一个人吗，
## 把凯伊放进去」。所以她是**站在第二场景里的 NPC**，不是跟着跑的那七只同伴。
##
## ── 为什么继承 `Companion` 而不是另写一套 ──
## 她需要的东西 `companion.gd` 全都有且踩过坑：按 `model_path` 运行时建模型、
## `FaceFix` 脸皮分层、胯骨对中（凯伊的模型**本来就偏 1.325 m**，见那份文件头）、
## `AnimDriver` 接动作。所以继承过来，只改「站着不动」+「按 F 说话」两件事。
##
## ⚠️ **站桩是在 `_ready()` 里立刻 `set_standby(true)` 做的**，早于第一个物理帧，
##    所以她一步都不会往玩家那边走。standby 分支里重力照常生效，因此场景里
##    把 y 放高几个厘米也没事，她自己会落到地面。
## ⚠️ `player_path` 必须填（`../Player`）：留空会在 `_ready` 里打
##    「找不到玩家节点」的警告，而且 `_physics_process` 直接 return、连重力都不走。
##
## ── 剧情（为什么不是「商店卖皮肤」）──
## 临战形态的机体叫**阿比·埃舒**，原本是**时（Toki）**的；被击毁后由
## **凯伊和爱丽丝合力、借无名诸神的力量重组到爱丽丝身上**。
## 所以这里写成「凯伊动手改装、玩家出材料费」，不是货架上买一件。
## 参考：<https://bluearchive.hatenablog.com/entry/2026/02/08/234211>（临战衣装以时让渡的
## 阿比·埃舒为基础、由凯伊与爱丽丝精炼）、RekoWiki「蔚藍檔案學生介紹-千年」
## （装甲是阿比·舒被击毁后由 Kei 和爱丽丝合作施展無名諸神的力量重组到身上）。

const BankCard := preload("res://scripts/bank_card.gd")
const MechState := preload("res://scripts/mech_state.gd")

const SPEAKER := "凯伊"
## 能搭话的水平距离（米）与高度差上限：和芹香那边同一套判据
const TALK_RADIUS := 3.4
const TALK_DY_MAX := 2.2

## 首次见面：把来历交代清楚（也把「不是买的」写进台词）
const LINES_FIRST := [
	"……你来了。",
	"我把「阿比·埃舒」的残骸从废墟里拖回来了。骨架认得出——那是时（Toki）那台。",
	"被拆得很碎，核心却还在。只靠我一个人，装不回你身上。",
	"要一起动手：材料钱你出，焊我来。",
]
## 钱不够
const LINES_POOR := [
	"钱不够。材料费 %s，你卡上只有 %s。",
	"去挣。我不催你，残骸也不会自己跑掉。",
]
## 已经改装完
const LINES_DONE := [
	"阿比·埃舒已经在你身上了。",
	"别问我是怎么让它听话的——变形你自己按 G。",
]


var _hint: Label3D
var _in_range := false
## ⚠️ 名字不能叫 `_player` —— `companion.gd` 里已经有一个同名成员，
##    重名会让整份脚本 **Parse Error 加载失败**（本喵第一版就踩了，
##    表现是节点还在、脚本没挂上，按 F 毫无反应）。
var _talk_player: Node3D
var _busy := false


func _ready() -> void:
	super()
	# 早于第一个物理帧：站定，永不跟队、不被「掉出平台就拉回」的保险拽走
	set_standby(true)
	_make_hint()


func _make_hint() -> void:
	_hint = Label3D.new()
	_hint.name = "TalkHint"
	_hint.text = "按 F 找凯伊改装"
	_hint.font_size = 40
	_hint.pixel_size = 0.0032
	_hint.outline_size = 10
	_hint.outline_modulate = Color(0.05, 0.05, 0.06)
	_hint.modulate = Color(0.78, 0.92, 1.0)
	_hint.no_depth_test = true
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.shaded = false
	_hint.position = Vector3(0.0, 1.85, 0.0)
	_hint.visible = false
	add_child(_hint)


## 玩家节点走「`player` 组」而不是 `%Player`：`player.gd` 里
## `add_to_group("player")`，而且探针手工挂场景时 `current_scene` 可能是 null
## （芹香那边就是因此取不到玩家、提示不显示）。这条是抄 `shop_clerk.gd` 的。
func _player_node() -> Node3D:
	if _talk_player != null and is_instance_valid(_talk_player):
		return _talk_player
	_talk_player = get_tree().get_first_node_in_group("player") as Node3D
	return _talk_player


func _process(_delta: float) -> void:
	_update_talk_range()


func _update_talk_range() -> void:
	if _hint == null:
		return
	var p := _player_node()
	if p == null:
		return
	var d := p.global_position - global_position
	var flat := Vector2(d.x, d.z).length()
	# 必须站在地上才能搭话：对话会暂停世界，半空中按 F 会把人冻在天上
	var body := p as CharacterBody3D
	var grounded := body != null and body.is_on_floor()
	var near := grounded and flat <= TALK_RADIUS and absf(d.y) <= TALK_DY_MAX
	if near == _in_range:
		return
	_in_range = near
	_hint.visible = near


## 找场景里的 `DialogueBox`：从自己往上找，谁身上挂着就用谁的
## （第二场景原来没有对话框，是 2026-11-05 给凯伊加上的）。
func _dialogue() -> DialogueBox:
	var n: Node = self
	while n != null:
		var d := n.get_node_or_null("DialogueBox") as DialogueBox
		if d != null:
			return d
		n = n.get_parent()
	return null


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode != KEY_F or not _in_range or _busy:
		return
	var body := _player_node() as CharacterBody3D
	if body != null and not body.is_on_floor():
		return
	var d := _dialogue()
	if d == null or d.is_active():
		return
	_talk(d)
	get_viewport().set_input_as_handled()


func _talk(d: DialogueBox) -> void:
	_busy = true
	if not d.custom_step.is_connected(_on_dialogue_custom):
		d.custom_step.connect(_on_dialogue_custom)
	if not d.finished.is_connected(_on_dialogue_finished):
		d.finished.connect(_on_dialogue_finished)

	if MechState.carrier_unlocked():
		var done: Array = []
		for line in LINES_DONE:
			done.append({"kind": "say", "who": SPEAKER, "text": String(line)})
		d.play_steps(done, "kei_npc_done")
		return

	var bal := BankCard.balance()
	var price := MechState.CARRIER_PRICE
	var afford := bal >= price

	var steps: Array = []
	for line in LINES_FIRST:
		steps.append({"kind": "say", "who": SPEAKER, "text": String(line)})
	if not afford:
		for line in LINES_POOR:
			steps.append({"kind": "say", "who": SPEAKER,
				"text": String(line) % [BankCard.format_yuan(price), BankCard.format_yuan(bal)]})

	var pay_opt := {
		"text": "开工（%s）" % BankCard.format_yuan(price),
		"then": [
			{"kind": "custom", "name": "mech_pay",
				"data": {"amount": price, "label": "阿比·埃舒改装"}},
		],
	}
	if not afford:
		pay_opt["disabled"] = true
		pay_opt["disabled_hint"] = "还差 %s（卡上 %s）" % [
			BankCard.format_yuan(price - bal), BankCard.format_yuan(bal)]
	steps.append({"kind": "choice", "options": [
		pay_opt,
		{"text": "我再想想", "then": [
			{"kind": "say", "who": SPEAKER, "text": "……行。残骸我先收着。"},
		]},
	]})
	d.play_steps(steps, "kei_npc")
	print("[Kei] 开口：材料费 %s，卡上 %s%s" % [
		BankCard.format_yuan(price), BankCard.format_yuan(bal),
		"" if afford else "（不够，选项禁用）"])


## 播放器发来的业务回调：扣改装费 + 解锁载具形态
func _on_dialogue_custom(step_name: String, data: Dictionary) -> void:
	if step_name != "mech_pay":
		return
	var amount := int(data.get("amount", MechState.CARRIER_PRICE))
	var label := String(data.get("label", "阿比·埃舒改装"))
	# ⚠️ 和芹香那边一样：能走期货那套就走它（它会同步 `bank_yuan` 缓存和 HUD），
	#    第二场景里没有期货节点，`get_first_node_in_group` 返回 null → 直接扣卡。
	var fut := get_tree().get_first_node_in_group("futures")
	var paid := false
	if fut != null and fut.has_method("spend_bank"):
		paid = bool(fut.call("spend_bank", amount, label))
	else:
		paid = BankCard.spend(amount)
	if paid:
		MechState.unlock_carrier()
		print("[Kei] 改装完成：扣款 %s，卡上剩 %s" % [
			BankCard.format_yuan(amount), BankCard.format_yuan(BankCard.balance())])
	else:
		push_warning("[Kei] 扣款失败：卡上不够 %s" % BankCard.format_yuan(amount))


func _on_dialogue_finished() -> void:
	_busy = false


## 自检用：她是不是站桩、模型有没有就位
func is_ready_for_talk() -> bool:
	return is_standby() and model != null

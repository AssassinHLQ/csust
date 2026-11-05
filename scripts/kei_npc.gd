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
## 临战形态的机体叫**阿比·埃舒**（用户写作「阿比舒」），原本是**时（Toki）**的；
## 被击毁后由**凯伊和爱丽丝合力、借无名诸神的力量重组到爱丽丝身上**。
## 参考：<https://bluearchive.hatenablog.com/entry/2026/02/08/234211>（临战衣装以时让渡的
## 阿比·埃舒为基础、由凯伊与爱丽丝精炼）、RekoWiki「蔚藍檔案學生介紹-千年」
## （装甲是阿比·舒被击毁后由 Kei 和爱丽丝合作施展無名諸神的力量重组到身上）。
##
## 具体这场戏是**用户 2026-11-05 亲手写的**：
##   爱丽丝：我想要这个
##   凯伊：9178 万
##   爱丽丝：凯伊～便宜点～球球了 （づ￣3￣）づ╭♥～
##   凯伊：好...好吧
##   → 扣除银行卡**所有**钱，爱丽丝获得修复完好的阿比舒机甲。
## 台词逐字照抄，只把 `❤`(U+2764) 换成 `♥`(U+2665)：`assets/ui/font.ttf`
## 有 36558 个字形却**恰好没有 U+2764**，直接写会渲染成空白（本喵实测过 cmap）。
## 另外在刷卡前本喵加了一道「成交？/ 再想想」的确认 —— 不然按一下 F 就把卡刷光，
## 玩家连发生了什么都不清楚；台词本身没动。

const BankCard := preload("res://scripts/bank_card.gd")
const MechState := preload("res://scripts/mech_state.gd")

const SPEAKER := "凯伊"
## 玩家（主角）在对话框上的署名。项目里 `shop_clerk.gd` 用的就是「爱丽丝」。
const PLAYER_SPEAKER := "爱丽丝"
## 能搭话的水平距离（米）与高度差上限：和芹香那边同一套判据
const TALK_RADIUS := 3.4
const TALK_DY_MAX := 2.2

## 凯伊的**报价**（元）。用户 2026-11-05 给的剧情里是「9178 万」。
## ⚠️ 这个数**只用来念**，不参与任何余额比较 —— 用户的原话是
##    「然后是扣除银行卡所有钱」，所以成交价永远是「你卡上现有的全部」。
##    （`mech_state.gd` 里还留了一份 `QUOTE_YUAN`，只为别让报价散落两处。）
const QUOTE_TEXT := "9178万"

## ── 开场：用户 2026-11-05 亲手写的剧情 ──
## 台词逐字照抄（只有一处改动：`❤`(U+2764) 换成 `♥`(U+2665) ——
## `assets/ui/font.ttf` 有 36558 个字形，**恰好没有 U+2764**，
## 直接写会渲染成空白；`♥` 在字体里。详见文件头）。
const SCENE_HEAD := [
	{"who": PLAYER_SPEAKER, "text": "我想要这个"},
	{"who": SPEAKER, "text": "%s。" % QUOTE_TEXT},
	{"who": PLAYER_SPEAKER, "text": "凯伊～便宜点～球球了 （づ￣3￣）づ╭♥～"},
	{"who": SPEAKER, "text": "好...好吧"},
]
## 刷卡机那句旁白（提醒玩家「全额」这件事，别让他在不知情的情况下被刷光）
const LINE_SWIPE := "（凯伊把刷卡机推了过来。金额栏是空的，只贴了一张纸条：「全额」。）"
## 成交之后
const LINES_DONE_DEAL := [
	"修好了。它现在认得你。",
	"按下 G —— 让它站到你身上。",
]
## 已经改装完时说的话
const LINES_DONE := [
	"阿比·舒已经修好了，就在你身上。",
	"别问我是怎么让它听话的——变形你自己按 G。",
]
## 卡上一分钱都没有（不能白送：材料总得有个价）
const LINES_BROKE := [
	"……你卡上一分钱都没有。",
	"去挣。我不催你，残骸也不会自己跑掉。",
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
	var steps: Array = []
	for line in SCENE_HEAD:
		var st: Dictionary = (line as Dictionary).duplicate()
		st["kind"] = "say"
		steps.append(st)

	if bal <= 0:
		for line in LINES_BROKE:
			steps.append({"kind": "say", "who": SPEAKER, "text": String(line)})
		d.play_steps(steps, "kei_npc_broke")
		print("[Kei] 卡上 %s，不成交" % BankCard.format_yuan(bal))
		return

	# 成交前的最后一道确认：用户要的是「扣光卡上的钱」，得让他自己按下去
	steps.append({"kind": "narrate", "text": LINE_SWIPE})
	steps.append({"kind": "choice", "options": [
		{"text": "成交！（把卡刷光）", "then": [
			{"kind": "custom", "name": "mech_pay_all",
				"data": {"amount": bal, "label": "阿比·舒（修复完好的机甲）"}},
			{"kind": "narrate", "text": "银行卡 -%s，余额 %s。" % [
				BankCard.format_yuan(bal), BankCard.format_yuan(0)]},
			{"kind": "say", "who": SPEAKER, "text": LINES_DONE_DEAL[0]},
			{"kind": "say", "who": SPEAKER, "text": LINES_DONE_DEAL[1]},
		]},
		{"text": "等等，我再想想", "then": [
			{"kind": "say", "who": SPEAKER, "text": "……行。残骸我先收着。"},
		]},
	]})
	d.play_steps(steps, "kei_npc")
	print("[Kei] 报价 %s，成交价 = 卡上全部 %s" % [QUOTE_TEXT, BankCard.format_yuan(bal)])


## 播放器发来的业务回调：**把卡上的钱全部扣掉** + 解锁载具形态
func _on_dialogue_custom(step_name: String, data: Dictionary) -> void:
	if step_name != "mech_pay_all":
		return
	var label := String(data.get("label", "阿比·舒（修复完好的机甲）"))
	var bal := BankCard.balance()
	if bal <= 0:
		push_warning("[Kei] 卡上没有钱，不成交")
		return
	# ⚠️ 和芹香那边同一套：能走期货就走它（它会同步 bank_yuan 缓存与 HUD），
	#    第二场景里没有期货节点 → 直接清零银行卡。
	var fut := get_tree().get_first_node_in_group("futures")
	var paid := false
	if fut != null and fut.has_method("spend_bank"):
		paid = bool(fut.call("spend_bank", bal, label))
	else:
		BankCard.set_balance(0)
		paid = BankCard.balance() == 0
	if paid:
		MechState.unlock_carrier()
		print("[Kei] 成交：%s，刷掉 %s，卡上剩 %s" % [
			label, BankCard.format_yuan(bal), BankCard.format_yuan(BankCard.balance())])
	else:
		push_warning("[Kei] 扣款失败（卡上 %s）" % BankCard.format_yuan(bal))


func _on_dialogue_finished() -> void:
	_busy = false


## 自检用：她是不是站桩、模型有没有就位
func is_ready_for_talk() -> bool:
	return is_standby() and model != null

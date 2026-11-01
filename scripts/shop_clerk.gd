class_name ShopClerk
extends Node3D
## 柴关电脑城的店员：**黑见芹香（Serika）**，校服版。
##
## ── 店名（2026-10-26）──
## 这家店原来叫「天使24」（便利店），用户当天改成「**柴关电脑城**」：
## 「我突然发现芹香没有理由去天使24」。她这条「你配电脑吗?」的台词本来就是
## 电脑店的路子，改成电脑城之后人、店、台词三者才对得上（见 `shop.gd` 文件头）。
##
## ── 素材来源（署名，务必保留）──
##   模型：Blue Archive 模型包里的 `Serika.glb`（校服/默认版，4.0 MB）
##        原作 © NEXON Games / Yostar；**第三方素材，只在本地学习用**，
##        `/models/npc/**` 在 `.gitignore` 里，不随仓库分发。
##   放置：`models/npc/serika/serika.glb`（本喵 2026-10-22 从
##        `C:\Users\WY157\Downloads\BlueArchiveModels-main` 拷进来的）
##
## ── 为什么从小空换成芹香（2026-10-22 用户）──
##   「小空出差，芹香亲作为热血打工仔自愿工作很合理」
##   「不了不了，小空和我们角色模型画风不同，因为我们这个是卡通大头小人，
##     不是那种精致剧情立绘改的模型」
##   → 主题是**画风统一**：小空（338 骨 MMD 风）和爱丽丝/同伴那批卡通小人
##     差得太多，所以直接换掉，不做「可切换」。
##
## ── 和她的小设定 ──
##   待机动画用她自己带的 `Normal_Idle`（40 条动画里挑的），不再是程序化晃。
##   ⚠️ 小空那版的「转不动手臂」问题在这里不存在 —— 芹香是标准
##   `Bip001` 骨架 + 带 Idle，不需要摆姿势。
##
## ── 尺寸 ──
##   实测包围盒 0.67 × 1.39 × 0.50 m，**底在 y = −0.27**（原点在脚上方），
##   所以 `_ground()` 会把模型整体抬高 0.296 m（= 0.27 × 1.09）让脚踩到地板。
##   比爱丽丝（1.47 m）矮一点点，正好是芹香矮个子的设定，不缩放。
##   手骨高 0.45 + 0.27 = 0.72 m，柜台台面 0.88 m —— 手藏在柜台后面 ✓
##   （台面 2026-10-26 从 1.04 降到 0.88，见 `shop.gd::_build_counter()`。）
const MODEL := "res://models/npc/serika/serika.glb"
## 待机动画名候选。
##
## ⚠️ 顺序是有意的：**`Cafe_Idle` 排第一**。
##   用户 2026-10-22：「芹香怎么拿着枪，有没有不拿枪的版本」——
##   `Normal_Idle` 是战斗待机，她双手抱着那把步枪（实拍 `_clerk/clerk.png` 里看得见枪）。
##   而 `Cafe_*` 这套「咖啡厅模式」的素材本身**把武器骨的 scale 缩到 ≈0**（和
##   `anim_driver.gd` 里写的爱丽丝/小桃那批完全一样），播 `Cafe_Idle` 枪就没了 ——
##   正好是店员该有的样子，而且不用改模型、不用抠网格。
const IDLE_CLIPS := ["Cafe_Idle", "Normal_Idle", "Stand_Idle", "Idle"]
## 手骨名候选（`side` = "l" / "r"）。`Bip001` 那套是 Blue Archive 的骨架命名。
const HAND_BONES := {
	"l": ["Bip001 L Hand", "hand.l"],
	"r": ["Bip001 R Hand", "hand.r"],
}
## 尺寸与抬脚（米）。
##
## ⚠️ 2026-10-22 晚修正：这两个数原来是 `1.55` / `0.45`，实测**她变成 2.20 m 高**
##    （`_probe_three.gd`：世界 AABB 底 0.029、顶 2.226）—— 站在 1.04 m 的柜台后面
##    比爱丽丝（1.47 m）高出一大截，用户一眼看出「芹香站这么高」。
##    上一版以为「改 scale 几乎不改变世界高度」，是被**绑定姿态 AABB** 骗了；
##    实际渲染高度就是 `1.39 × scale`（`1.39` 是她自己的包围盒高度）。
##    现在按设定身高给：芹香 152 cm → `1.52 / 1.39 = 1.09`；
##    抬脚 = 模型原点那个 −0.27 的偏移 × 缩放 = 0.294（脚正好踩在 y = 0）
##    ⚠️ 2026-10-22 晚再修：本喵一度又加了 0.22 m 的「隐形垫脚箱」，用户从柜台侧面
##    一眼就看见**她的脚悬空 0.218 m**（`_probe_face_hut.gd` 量到 AABB 底 y=0.218）。
##    现在抬脚只留模型自己的原点偏移，**脚底 y = 0.000**，绝不悬空。
##    代价（实话实说）：柜台台面比她的下巴还高，从顾客那侧只露一个头。
##
## ⚠️⚠️ 2026-10-26 复盘：**上一版把「浮空」的锅甩错了对象，改坏了她的高度**。
##    事实链：
##      · 模型原点在脚上方：蒙皮网格的世界包围盒底 = 原点 − 0.296 m
##        （= GLB 里的 −0.27 × `MODEL_SCALE` 1.09），所以 `CLERK_LIFT = 0.296`
##        才能让鞋底落在 y = 0；
##      · 上一版误以为「用户说的浮空」是她，改用**脚骨高度**去对标玩家
##        （`Bip001 L/R Foot` 定到 +0.007），把抬脚改成 −0.043 ——
##        结果她**整个人埋进地板 0.339 m**（`_probe_clerk_height.gd` 实测：
##        网格包围盒 y −0.339 ~ 1.188，身高 1.527 量级对，但整个沉下去了）。
##      · 用户真正说的是**吊灯**浮空（小屋那段），与芹香无关。
##    教训：她的骨架里**没有 toe 骨**，`Bip001 L/R Foot` 到底在踝还是在脚掌、
##    离鞋底多少，和玩家那套骨架并不相同，**不能拿玩家的脚骨高度当尺子**。
##    她自己的定高依据只有一个：模型原点相对鞋底的偏移（−0.296 m）。
##
## ── 两个数 ──
##   `MODEL_SCALE`：等比缩放。
##   `CLERK_LIFT` ：模型根节点的 y 偏移（原点 = 鞋底，所以是 0）。
##
## ⚠️⚠️ 2026-10-26 第二次复盘：**「原点在脚上方」这个前提本身是错的**。
##
##     `_probe_clerk_anim_ground.gd` 把她身上每个网格的包围盒**逐个**打出来：
##
##       Serika_Original_Weapon2   y -0.000 ~ +0.622   ← 枪（绑姿垂到原点下方）
##       Serika_Original_Body2     y +0.295 ~ +1.420   ← **身体**
##       Serika_Halo               y +1.292 ~ +1.527
##
##     最低点 0.000 是**枪**、不是鞋 —— 也就是说「模型原点在脚上方 0.27 m」
##     是拿枪的绑姿垂坠量当成了脚底偏移。真相是：**模型原点本来就在鞋底**
##     （身体网格的最低顶点在模型空间 y ≈ 0.000）。
##     于是 `CLERK_LIFT = 0.296` 把整个人**又抬高了一遍**，她浮空 0.295 m。
##     用户 2026-10-26 的原话就是「芹香浮空了」，`_probe_clerk_anim_ground.gd`
##     那张带 5 cm 刻度尺的图（`_arisu_captures/_issues1026/clerk_ruler.png`）
##     量到她鞋底在 **0.28 m** 空中 —— 和 0.295 对得上。
##
##     ⚠️ 为什么会连着两次栽在同一个坑：
##       · 第一次用**脚骨**（`Bip001 L/R Foot`）对标，结论 -0.043 → 她埋进地板；
##       · 第二次用**整体包围盒**（全体网格 merge）→ 又被枪骗了一次。
##       教训：量一个角色的站姿，**必须逐网格看，并且认清哪个网格是身体**
##       （这些 Blue Archive 模型里枪/算盘/光环都是独立网格，绑姿能垂到脚下面去）。
##     她的身体网格也在 `_probe_body_heights.gd` 里和爱丽丝/同伴放在一起对照过。
## 缩放：**和其他 NPC 一档**。
##
## ⚠️ 原来写的是「包围盒 1.39 m × 1.09 = 1.52 m」—— 那个 1.39 是**整只模型的 AABB**，
##    里面含 0.271 m 的**枪**（绑姿垂在原点下方）和 0.109 m 的**光环**，
##    所以它既不是身高、也不能拿来定缩放。实测（`_probe_float_lamp_zfight.gd`）：
##
##      模型空间：身体（sole → 发顶）= **1.031 m**，光环顶 = 1.130 m，枪底 = −0.271 m
##
##    2026-10-26 那一版为了「头顶顶到胶囊顶」取了 1.42 → 身体 1.464 m，
##    但**全场只有她一个人被放大**（同伴实测 0.96~1.11、玩家 0.69），
##    用户 2026-10-27 站到店里一眼看出「芹香怎么这么大」。
##    现在改回 **1.00（原生 1.031 m）**，胶囊同步缩到 1.04 —— 和四个同伴同一档。
const MODEL_SCALE := 1.00
## 原点 = 鞋底，所以**不需要抬**（正数 = 往上抬，会浮空）。
const CLERK_LIFT := 0.0

## ── 对话（2026-10-26 用户：「芹香需要可以对话，交互后说 你配电脑吗?」）──
##
## 交互方式跟屋里的电脑（`hut_computer.gd`）一致：**站在她面前按 F**。
## 说话用场景里的 `DialogueBox`（`play_steps` 是它的「内联播放」入口），
## 这样打字的节奏、翻页、暂停世界全部沿用现成的那一套，不另起炉灶。
## 八卡 5090 整套的价格（元）。低于这个数就不能选第一项。
const DESK_PRICE := 500000
const BankCard := preload("res://scripts/bank_card.gd")

const TALK_RADIUS := 2.6
## 垂直方向也限定一下：站在二层或楼下远一点的地方按 F 不该触发
const TALK_DY_MAX := 2.0
## 对话内容。第一句是用户指定的原话。
const TALK_LINES := [
	"你配电脑吗?",
]
## 配置单内容：店员拿来「糊弄」爱丽丝的就是这套 —— 直接把数据中心机柜当家用机卖。
## 图还没做（`res://assets/story/config_sheet.png`），出图时按这份逐行排版。
## 价格都是 2026-11 的估算/渠道价，只求「离谱得真实」，不是采购报价。
const CONFIG_SHEET := [
	{"part": "显卡", "model": "NVIDIA B300（Blackwell Ultra）",
		"spec": "288GB HBM3E · NVLink 5 · 1400W", "qty": 8, "price": "¥40 万/张"},
	{"part": "整机", "model": "HGX B300 八卡基板 + 8U 机箱",
		"spec": "SXM 模块直插 · 冷板液冷", "qty": 1, "price": "¥60 万"},
	{"part": "处理器", "model": "Intel Xeon 6 6980P",
		"spec": "128 核 · 500W", "qty": 2, "price": "¥9 万/颗"},
	{"part": "内存", "model": "DDR5-6400 ECC RDIMM 64GB",
		"spec": "双路 24 通道 · 共 1.5TB", "qty": 24, "price": "¥0.7 万/条"},
	{"part": "系统盘", "model": "PCIe 5.0 NVMe 1.92TB",
		"spec": "RAID 1", "qty": 2, "price": "¥0.3 万"},
	{"part": "数据盘", "model": "PCIe 5.0 NVMe 7.68TB",
		"spec": "RAID 10", "qty": 8, "price": "¥1 万"},
	{"part": "网络", "model": "ConnectX-8 800G 网卡",
		"spec": "每卡一路 · InfiniBand", "qty": 8, "price": "¥4 万"},
	{"part": "液冷", "model": "机架式 CDU + 冷板",
		"spec": "≥ 60 kW", "qty": 1, "price": "¥50 万"},
	{"part": "配电", "model": "12kW 电源框",
		"spec": "2N 冗余 · 整节点 ≈ 12 kW", "qty": 1, "price": "¥20 万"},
	{"part": "合计", "model": "整套（不含机房改造）",
		"spec": "占地约 1 个 42U 机柜", "qty": 1, "price": "≈ ¥520 万"},
]
## 配置单里每一行对应的零件图（顺序 = 排版图里从上往下的九行）。
## 鼠标悬停在某一行，右侧那张照片就换成这一行对应零件的图。
## 两张配置单：店员先拿 B300 忽悠（¥520 万），小桃拆台后换成八卡 5090（¥51 万）。
## `parts` / `labels` 与排版图里从上往下的行一一对应；空串 = 这一行悬停不换图。
const SHEET_B300 := {
	"base": "res://assets/story/config_sheet.png",
	"caption": "图上为八卡计算托盘：8 颗 B300 + 24 条 ECC 内存（鼠标移到左边的部件名试试）",
	"parts": ["gpu", "server", "cpu", "ram", "ssd", "ssd", "nic", "cooling", "psu"],
	"labels": [
		"显卡 · NVIDIA B300 · 288GB HBM3E ×8",
		"整机 · HGX B300 八卡基板 + 8U 机箱",
		"处理器 · Intel Xeon 6 6980P ×2",
		"内存 · DDR5-6400 ECC RDIMM 64GB ×24 = 1.5TB",
		"系统盘 · PCIe 5.0 NVMe 1.92TB ×2（RAID 1）",
		"数据盘 · PCIe 5.0 NVMe 7.68TB ×8（RAID 10）",
		"网络 · ConnectX-8 800G ×8",
		"液冷 · 机架式 CDU + 冷板 ≥60 kW",
		"配电 · 12kW 电源框 · 2N 冗余",
	],
}
const SHEET_5090 := {
	"base": "res://assets/story/config_sheet_5090.png",
	"caption": "图上为八卡 5090 工作站：8 张显卡 + 8 条 ECC 内存（鼠标移到左边的部件名试试）",
	"parts": ["gpu5090", "", "", "ram", "ssd", "ssd", "psu", "", ""],
	"labels": [
		"显卡 · RTX 5090 · 32GB GDDR7 ×8",
		"整机 · WRX90 主板 + 开放式机架",
		"处理器 · Threadripper PRO 9995WX · 96 核 · 128 条 PCIe 5.0",
		"内存 · DDR5-5600 ECC 32GB ×8 = 256GB",
		"系统盘 · PCIe 5.0 NVMe 2TB ×2（RAID 1）",
		"数据盘 · PCIe 5.0 NVMe 8TB ×4（RAID 0）",
		"电源 · 2000W ATX 3.1 ×2 · 2N 冗余",
		"散热 · 开放式机架 + 工业扇",
		"显示器 · 27 英寸 4K 160Hz ×2",
	],
}
## 排版脚本（tools/make_config_sheet.py）里的行参数：首行 y=146、行高 66；
## 右侧照片区 x=1064 y=146 w=492 h=560
const SHEET_ROW_TOP := 146.0
const SHEET_ROW_H := 66.0
const SHEET_PHOTO := {"x": 1064, "y": 146, "w": 492, "h": 560}


## 把一张配置单的规格换成对话播放器要的步骤（热区按常量算，不手写行数据）
func _sheet_step(spec: Dictionary) -> Dictionary:
	var parts: Array = spec["parts"]
	var labels: Array = spec["labels"]
	var rows: Array = []
	for i in parts.size():
		var part := String(parts[i])
		rows.append({
			"top": SHEET_ROW_TOP + i * SHEET_ROW_H,
			"bottom": SHEET_ROW_TOP + (i + 1) * SHEET_ROW_H,
			"image": "" if part.is_empty() else "res://assets/story/parts/%s.png" % part,
			"label": String(labels[i]),
		})
	return {
		"kind": "config_sheet",
		"base": String(spec["base"]),
		"photo": SHEET_PHOTO,
		"caption": String(spec["caption"]),
		"rows": rows,
	}


## 主角的两个回答（用户 2026-11-01 给的原文，标点照抄）。
## `then` 是选中之后接着播的台词 —— 对话播放器会把它们插在后面。
const TALK_OPTIONS := [
	{
		"text": "商人啊!我正是为此而来!",
		"value": 1,
		"then": [
			{"kind": "say", "who": SPEAKER, "text": "老板,看这套配置怎么样[TVT]"},
			# 报价之后弹配置单：悬停行会换右侧照片，按空格/左键关掉再往下
			{"kind": "__sheet_b300__"},
			{"kind": "say", "who": SPEAKER,
				"text": "B300，288G 显存，八卡一柜——光卡就四十来万一张，整机五百二十万，适合给老师送礼,配您正合适,我也多赚钱[TVT]"},
			# 小桃拆台：服务器卡没技巧，5090 才是硬核
			{"kind": "say", "who": "小桃", "text": "我chovy,什么破卡."},
			{"kind": "say", "who": "小桃",
				"text": "要我说,5090的硬核才是王道,你那服务器卡根本就没技巧"},
			{"kind": "say", "who": SPEAKER, "text": "……行吧，那给您换一张单子。"},
			{"kind": "__sheet_5090__"},
			{"kind": "say", "who": SPEAKER,
				"text": "八张 5090 加撕裂者，五十来万——这套才是真适合给木的"},
			{"kind": "say", "who": "爱丽丝", "text": "邦邦卡邦!就这套了!"},
			# 成交：扣款由 shop_clerk 接 custom 步骤做，紧接着那句旁白报余额
			{"kind": "custom", "name": "pay", "data": {"amount": DESK_PRICE, "label": "八卡 5090 工作站"}},
			{"kind": "narrate", "text": "__BALANCE_AFTER__"},
		],
	},
	{
		"text": "观察了银行卡的余额,摇了摇头",
		"value": 2,
		"then": [{"kind": "say", "who": SPEAKER,
			"text": "……先看看也行，不着急买。"}],
	},
]
## 说话人名字（`DialogueBox` 名字牌上显示的那个）
const SPEAKER := "芹香"

## 整只模型左右轻晃的幅度（没有 Idle 动画时的退路；芹香有动画，默认不晃）
@export var idle_sway := false
@export var sway_deg := 1.1
@export var sway_hz := 0.16

var model: Node3D
var skeleton: Skeleton3D
var bone_count := 0
## 量出来的：两只手骨的世界高度（自检/探针用来对照台面高度）
var hand_y := {}
## 缩放/抬高（探针用）
var ground_lift := 0.0
var fit_scale := 1.0

var _t := 0.0
var _idle: AnimationPlayer
var _idle_name := ""

## 交互提示（「按 F 说话」）与范围标记
var _hint: Label3D
var _in_range := false
var _player: Node3D


func _ready() -> void:
	if not ResourceLoader.exists(MODEL):
		push_warning("[Clerk] 没有芹香的模型：%s（本地素材，不随仓库分发）" % MODEL)
		return
	var ps := load(MODEL) as PackedScene
	if ps == null:
		push_error("[Clerk] %s 不是有效的场景" % MODEL)
		return
	model = ps.instantiate() as Node3D
	add_child(model)
	_fit(model)
	skeleton = _best_skeleton(model)
	if skeleton != null:
		bone_count = skeleton.get_bone_count()
		for side in ["l", "r"]:
			var idx := _hand_bone(side)
			if idx >= 0:
				hand_y[side] = (skeleton.global_transform
					* skeleton.get_bone_global_pose(idx).origin).y
	# 光环抛光（和玩家/同伴那 8 顶一样的处理：受光 + 自发光 0.8 + 不投阴影）
	HaloFix.polish(model)
	# 脸皮分层：脸皮与「眼睛+嘴」那层几乎共面 → 双层线（z-fighting）。
	# ⚠️ 眉毛叠层（`simplify_brows`）**故意不调**，理由见 `face_fix.gd` 里那三版复盘。
	FaceFix.separate_face_layers(model)
	_apply_smile()
	_play_idle()
	_make_body()
	_make_hint()
	print("[Clerk] 芹香就位：%s（骨架 %d 骨，缩放 %.2f×，抬脚 %.2f m，手骨高度 L=%.2f R=%.2f m，动画 %s）" % [
		MODEL.get_file(), bone_count, fit_scale, ground_lift,
		float(hand_y.get("l", -1.0)), float(hand_y.get("r", -1.0)),
		String(_idle.current_animation) if _idle != null else "无（保持静止姿势）"])


## 定高：按 `MODEL_SCALE` 等比缩放。`CLERK_LIFT` 现在是 **0** ——
## 模型原点就在鞋底（见上面 2026-10-26 那段复盘），再抬就是浮空。
## 这个函数**不再用包围盒算**：整体包围盒会被枪的下垂量带偏，这正是上一版的坑。
func _fit(root: Node3D) -> void:
	fit_scale = MODEL_SCALE
	root.scale = Vector3.ONE * fit_scale
	ground_lift = CLERK_LIFT
	root.position.y = ground_lift


## 播待机动画，并且**让它真的循环**。
##
## ⚠️ 用户 2026-10-22：「为什么芹香站这么高**也不动**」。
##   实测（`_probe_three.gd`）：`Cafe_Idle` 播了，`is_playing() == true`，
##   长度 1.667 s、140 条轨道、89 条有 >1 个关键帧 —— 但 `loop_mode` 是
##   **0（LOOP_NONE）**，`current_animation_position` 停在 1.659 s：
##   她播完第一遍就定格在最后一帧，看起来就是一根不动的桩。
##   glb 里带来的动画默认不循环，`.play()` 也不会替你打开。
func _play_idle() -> void:
	for n in model.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		var list := ap.get_animation_list()
		for want in IDLE_CLIPS:
			if not list.has(want):
				continue
			var anim := ap.get_animation(want)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.play(want)
			ap.speed_scale = 1.0
			# 万一这条动画是只读资源（改不动 loop_mode），播完再自己续上
			if not ap.animation_finished.is_connected(_replay_idle):
				ap.animation_finished.connect(_replay_idle)
			_idle = ap
			_idle_name = want
			return


## 碰撞：玩家不能穿过她。
##
## 用户 2026-10-22：「芹香需要有碰撞」。
## 用胶囊（半径 0.26、总高 1.45、中心 y=0.75 → 脚 0.025、头顶 1.475），
## 挂在 `ShopClerk` 自己下面，所以柜台挪窝时她跟着走。
## 碰撞层用默认的 1（和商店的墙、柜台、货架一致）—— 玩家的 `CharacterBody3D`
## 的 mask 里本来就包含第 1 层，不用改任何工程设置。
func _make_body() -> void:
	var body := StaticBody3D.new()
	body.name = "ClerkBody"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	# 胶囊跟着模型走：身体 1.031 m → 胶囊总高 1.04、顶面 1.04、半径按 1.42 那一版等比缩
	cap.radius = 0.18
	cap.height = 1.04
	cs.shape = cap
	cs.position = Vector3(0.0, 0.52, 0.0)
	body.add_child(cs)
	add_child(body)


## 换成微笑。
##
## ⚠️ 芹香没有形态键式的表情系统：10 个 `Mouth_*` 网格**几何完全相同**（同一个四边形），
##    差别只在材质里的那张 128×128 嘴型贴图；当前生效的是 `Mouth_607`（白色大「o」，
##    惊讶脸，就是用户看到的那张）。
##    实测把这 10 个的形态键权重怎么改，屏幕上都是同一张嘴（嘴不是靠形变切出来的），
##    所以最稳的做法是——**把想要的那张嘴贴图，铺给全部 10 个材质**。
##    这样不管最后是哪一个网格在画，画出来都是微笑。
##
##    选 `Mouth_406`：那是一条很长的、两端上翘的细弧线（`_mouth_tex_sheet.png` 里
##    第 3 张），是这十张里唯一的「抿嘴微笑」；401 是平线、602 是「∧」、600/601/701/703
##    都是大张嘴，607 是惊讶。贴图不能选错，换之前先看那张对照表。
const SMILE_MOUTH := "Mouth_406"


func _apply_smile() -> void:
	var mouths := model.find_children("Mouth*", "MeshInstance3D", true, false)
	if mouths.is_empty():
		return
	var src: MeshInstance3D = null
	for m in mouths:
		if String(m.name) == SMILE_MOUTH:
			src = m as MeshInstance3D
			break
	if src == null:
		return
	var src_mat := src.get_active_material(0) as StandardMaterial3D
	if src_mat == null or src_mat.albedo_texture == null:
		return
	var tex := src_mat.albedo_texture
	var n := 0
	for m in mouths:
		var mat := (m as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_texture = tex
		n += 1
	print("[Clerk] 嘴型统一成 %s 的微笑贴图（%d 个嘴型网格）" % [SMILE_MOUTH, n])


func _replay_idle(anim_name: StringName) -> void:
	if _idle == null or anim_name != _idle_name:
		return
	_idle.play(anim_name)


# ══════════════════════════ 对话交互 ══════════════════════════

## 找场景里的 `DialogueBox`：从自己往上找，谁身上挂着就用谁的。
## 不写死 `/root/Game/DialogueBox`，因为商店以后可能单独摆进别的关卡。
func _dialogue() -> DialogueBox:
	var n: Node = self
	while n != null:
		var d := n.get_node_or_null("DialogueBox") as DialogueBox
		if d != null:
			return d
		n = n.get_parent()
	return null


## 玩家节点。走「`player` 组」而不是 `get_tree().current_scene.get_node("Player")`：
##   `player.gd` 第 151 行 `add_to_group("player")`，组跟场景怎么挂无关；
##   而 `current_scene` 在**探针/脚本手工挂场景**时是 null（实测就是这里没取到玩家，
##   提示一直不显示、按 F 也没反应），`hut_computer.gd` 用的也是组。
func _player_node() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


## 「按 F 说话」的小提示。挂在头顶上方，只有走进范围才显示。
func _make_hint() -> void:
	_hint = Label3D.new()
	_hint.name = "TalkHint"
	_hint.text = "按 F 说话"
	_hint.font_size = 40
	_hint.pixel_size = 0.0032
	_hint.outline_size = 10
	_hint.outline_modulate = Color(0.05, 0.05, 0.06)
	_hint.modulate = Color(1.0, 0.95, 0.75)
	_hint.no_depth_test = true
	_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hint.shaded = false
	# 高度 = 她头顶（1.031）再往上 0.20 m。
	_hint.position = Vector3(0.0, 1.23, 0.0)
	_hint.visible = false
	add_child(_hint)


func _process(delta: float) -> void:
	_update_talk_range()
	if _idle != null or not idle_sway or model == null:
		return
	_t += delta
	model.rotation.y = deg_to_rad(sway_deg) * sin(_t * TAU * sway_hz)


func _hand_bone(side: String) -> int:
	for want in HAND_BONES.get(side, []):
		var i := _find_bone(want)
		if i >= 0:
			return i
	return -1


func _find_bone(want: String) -> int:
	if skeleton == null:
		return -1
	return skeleton.find_bone(want)


func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in _skeletons(node):
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	return best


func _skeletons(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is Skeleton3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_skeletons(c))
	return out


## 每帧判一次「玩家在不在跟前」，只在状态变化时改一次 `visible`。
func _update_talk_range() -> void:
	if _hint == null:
		return
	var p := _player_node()
	if p == null:
		return
	var d := p.global_position - global_position
	var flat := Vector2(d.x, d.z).length()
	var near := flat <= TALK_RADIUS and absf(d.y) <= TALK_DY_MAX
	if near == _in_range:
		return
	_in_range = near
	_hint.visible = near


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode != KEY_F or not _in_range:
		return
	var d := _dialogue()
	if d == null or d.is_active():
		return
	_talk(d)
	get_viewport().set_input_as_handled()


## 播放对话。`play_steps` 会自己暂停世界、打字、等翻页，结束后恢复。
## 第一句问「你配电脑吗?」，然后给玩家两个选项（W/S 选、空格确认）。
## 播放器发来的业务回调（目前只有成交扣款）
func _on_dialogue_custom(step_name: String, data: Dictionary) -> void:
	if step_name != "pay":
		return
	var amount := int(data.get("amount", 0))
	var label := String(data.get("label", "整机"))
	if BankCard.spend(amount):
		print("[Clerk] 成交：%s，扣款 %s，余额 %s" % [
			label, BankCard.format_yuan(amount), BankCard.format_yuan(BankCard.balance())])
	else:
		push_warning("[Clerk] 扣款失败：卡上不够 %s" % BankCard.format_yuan(amount))


func _talk(d: DialogueBox) -> void:
	var steps: Array = []
	for line in TALK_LINES:
		steps.append({"kind": "say", "who": SPEAKER, "text": String(line)})
	# 选项里的 `__sheet__` 占位换成真正的配置单步骤（热区要按常量算，没法写进 const）
	var opts: Array = []
	for o in TALK_OPTIONS:
		var opt: Dictionary = (o as Dictionary).duplicate(true)
		# 买整机那一项：卡上钱不够就禁掉，选中会提示余额不足、不推进
		if int(opt.get("value", 0)) == 1:
			var bal := BankCard.balance()
			if bal < DESK_PRICE:
				opt["disabled"] = true
				opt["disabled_hint"] = "银行卡余额不足：还差 %s（卡上 %s）" % [
					BankCard.format_yuan(DESK_PRICE - bal), BankCard.format_yuan(bal)]
				print("[Clerk] 余额 %s < %s，第一项禁用" % [
					BankCard.format_yuan(bal), BankCard.format_yuan(DESK_PRICE)])
		var fixed: Array = []
		for st in opt.get("then", []):
			var kind := String((st as Dictionary).get("kind", ""))
			if kind == "__sheet_b300__":
				fixed.append(_sheet_step(SHEET_B300))
			elif kind == "__sheet_5090__":
				fixed.append(_sheet_step(SHEET_5090))
			elif kind == StoryScript.K_CUSTOM:
				fixed.append(st)
			elif String((st as Dictionary).get("text", "")) == "__BALANCE_AFTER__":
				var after := {
					"kind": "narrate",
					"text": "银行卡 -%s，余额 %s。" % [
						BankCard.format_yuan(DESK_PRICE),
						BankCard.format_yuan(maxi(0, BankCard.balance() - DESK_PRICE))],
				}
				fixed.append(after)
			else:
				fixed.append(st)
		if not fixed.is_empty():
			opt["then"] = fixed
		opts.append(opt)
	steps.append({"kind": "choice", "options": opts})
	if not d.custom_step.is_connected(_on_dialogue_custom):
		d.custom_step.connect(_on_dialogue_custom)
	d.play_steps(steps, "shop_clerk")
	print("[Clerk] 芹香开口：%d 句 + %d 个选项（%s）"
		% [TALK_LINES.size(), TALK_OPTIONS.size(), String(TALK_LINES[0])])

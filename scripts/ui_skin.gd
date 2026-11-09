class_name UiSkin
extends RefCounted
## 界面皮肤：一套「素材目录 + 配色 + 九宫格边距」，外加从它派生出来的控件样式。
##
## 原来这份数据只写在 `settings_menu.gd` 里。HUD 也要跟着换皮时，如果各自复制一份，
## 两边的配色迟早会走散（改了一边忘了另一边），所以抽到这里共用。
##
## 两套皮肤的文件名刻意保持一致（`panel.png` / `button*.png` / `font.ttf`），
## 所以「挑皮肤」只要看目录里有没有关键文件就够了。
##
## ⚠️ `font.ttf` 是 Sprout Lands 的像素字体（`pixelFont-7-8x14-sproutLands`），
##    **没有中文字形**。Godot 的 `FontFile.allow_system_fallback` 默认开着，中文会
##    回退到系统字体渲染 —— 数字/拉丁文用像素字体、中文用系统字体，混排能看但基线
##    会略有出入。所以这套字体只用在「纯数字/拉丁」的控件上（弹药数、HP 数字），
##    而且 HUD 那三处是**显式覆盖**进去的（`hud.gd` 里的 `hud_number_font()`）。
##
## ⚠️ Sprout 的 `panel.png` 是 106×122、圆角比 Kenney 的 32×32 大得多，两套的
##    九宫格边距必须分别给（`margin` 字段），不然小图会被拉伸成糊的。

# ── BA（蔚蓝档案）皮肤用的官方取色 ───────────────────────────────────────────
#
# 出处：社区还原项目 `ywhdzrb/BlueArchiveUI`（C++/Qt，**代码部分 MIT**）的
#      `include/blue_archive_ui/ba_style.h` —— 它的注释写着这些是「BA 官方 UI 取色」，
#      取色参考 BA-AD 解包素材与社区还原项目。**色值本身是规格，不是素材**，
#      所以可以直接用（原图/解包贴图不能进仓库，见 `README` §13.11）。
#
#   accent   #4EC3F5  青蓝高亮：滑块填充 / 图标 / 选中态
#   sky      #77DEFF  亮青：主按钮底色
#   deep     #003153  深藏蓝：标题 / 正文主色
#   yellow   #FFE433  装饰黄：标题底划线
#   light    #CDE8FD  浅蓝：侧栏 tab 背景
#   muted    #6B7F8D  灰蓝：次级文字
#   track    #DFE6EA  滑块轨道 / 进度条底
#   edge     #A9C6E4  信息卡边缘浅蓝描边
#   chip     #252F41  「数值消耗片」深蓝黑底
#   halflight #EDF3F9 卡片顶部浅蓝信息区（#FFFFFF → 这个）
const BA_ACCENT := Color("#4ec3f5")
const BA_SKY := Color("#77deff")
const BA_DEEP := Color("#003153")
const BA_YELLOW := Color("#ffe433")
const BA_LIGHT := Color("#cde8fd")
const BA_MUTED := Color("#6b7f8d")
const BA_TRACK := Color("#dfe6ea")
const BA_EDGE := Color("#a9c6e4")
const BA_CHIP := Color("#252f41")
const BA_HALFLIGHT := Color("#edf3f9")

## BA 面板圆角（`baButtonPath` 的 radius 默认 6、信息卡圆角写死 8）
const BA_PANEL_RADIUS := 8
const BA_BUTTON_RADIUS := 6

## BA 按钮的**左倾**斜量。
##
## ⚠️ `StyleBoxFlat.skew` 是 `Vector2`（Godot 4.7 实测 `ClassDB` 读出来的），
##    数值是**相对尺寸的比例**、不是像素：`skew.x = -0.3` 时顶端相对底端平移
##    `0.3 × 高度`。BA 那个平行四边形是 -10°，`tan(10°) ≈ 0.176` ——
##    但那个项目自己注释说「细长条上按 -16° 算出来的斜量只有几像素、看不清，
##    所以调用方按各层高度 × 0.42 放大斜量」。按钮高度不小，取 -0.22 就够看得出倾。
const BA_BUTTON_SKEW := -0.22

const SKINS := [
	# ── ① BA（蔚蓝档案）—— **程序化皮肤，不用任何贴图** ──────────────────────
	#
	# 面板 / 按钮全部由 `StyleBoxFlat` 现画（`"procedural": true`），所以它**永远可用**、
	# 不会像另外两套那样「素材没放进来就整块界面空白」。
	#
	# ⚠️ 为什么不像另外两套那样给一张 `panel.png`：
	#    官方《二创指引》「禁止的事项」第 1 条不许直接使用游戏原始素材（README §13.11），
	#    而**几何比例与配色是规格、不是素材**。所以这里只抄规格。
	#
	# 配色出处见上面那组 `BA_*` 常量（社区还原项目 `ba_style.h`）。
	{
		"label": "Blue Archive（蔚蓝档案）",
		"dir": "",                        # 没有素材目录 —— 全部代码画
		"procedural": true,
		"margin": 12.0,                   # 内容内缩，取另外两套里较大的那个，版式偏移最小
		"panel_tint": Color(1, 1, 1, 1),
		"button_tint": Color(1, 1, 1, 1),
		# 面板上的正文：BA 的深藏蓝
		"text": BA_DEEP,
		"subtext": BA_MUTED,
		"trough": BA_TRACK,
		"fill": BA_ACCENT,
		"grabber": Color(1, 1, 1, 1),
		# 弹窗背后的遮罩：深藏蓝加暗，比纯黑更「BA」
		"dim": Color(0.0, 0.09, 0.20, 0.66),
		# 量条：槽用 BA 的 progressTrackDark(#40454F→#23272E)，填充用 progressFill(#96DCFA)
		"bar_trough": Color("#23272e"),
		"bar_edge": Color("#40454f"),
		"bar_fill": Color("#96dcfa"),
		"bar_fill_low": Color("#ff5a4d"),   # ⚠️ 这个红是本喵配的（见 §13.12）
		# 说话人名字：压在斜切名牌上，白字
		"dialogue_name": Color(1, 1, 1, 1),
		# ── 程序化专用 ──
		"panel_bg": Color(1, 1, 1, 1),
		"panel_edge": BA_EDGE,
		"panel_radius": BA_PANEL_RADIUS,
		"btn_bg": BA_SKY,
		"btn_bg_hover": Color("#9fe7fb"),      # accentGradient 亮端
		"btn_bg_pressed": Color("#5fc6f2"),    # accentGradient 暗端
		"btn_edge": BA_ACCENT,
		"btn_text": BA_DEEP,
		"btn_radius": BA_BUTTON_RADIUS,
		"btn_skew": BA_BUTTON_SKEW,
		"flat_radius": 5,                 # 滑块/开关的圆角（BA 是圆角，不是像素块）
		"accent": BA_ACCENT,
		"yellow": BA_YELLOW,
		"chip_bg": BA_CHIP,
		"chip_text": Color(1, 1, 1, 1),
		# 剧情对话框：BA 那个是**深藏蓝半透明**，不是白面板
		"story_bg": Color(0.02, 0.13, 0.28, 0.88),
		"story_edge": Color(0.31, 0.76, 0.96, 0.55),
		"story_text": Color(1, 1, 1, 1),
		"story_subtext": Color(0.76, 0.86, 0.96, 1),
		"choice_dim": Color(0.82, 0.87, 0.94, 1),
		"choice_dim_disabled": Color(0.62, 0.68, 0.76, 1),
	},
	{
		"label": "Sprout Lands",
		"dir": "res://assets/ui_sprout/",
		"margin": 12.0,                   # 106×122 的面板，圆角比 Kenney 的大
		"panel_tint": Color(1, 1, 1, 1),  # 面板本身就是米色，不用再染
		"button_tint": Color(1, 1, 1, 1),
		"text": Color(0.34, 0.22, 0.12),  # 深棕字压在米色面板上
		"subtext": Color(0.46, 0.33, 0.20),
		"trough": Color(0.78, 0.66, 0.50),
		"fill": Color(0.53, 0.74, 0.42),  # 草绿，跟素材的农场色调一套
		"grabber": Color(0.99, 0.94, 0.83),
		"dim": Color(0.07, 0.06, 0.05, 0.55),
		# 血条（玩家 / Boss 共用）：红条 + 草绿描边那一套混搭配色
		"bar_trough": Color(0.35, 0.25, 0.16),
		"bar_edge": Color(0.53, 0.74, 0.42),
		"bar_fill": Color(0.86, 0.24, 0.18),
		"bar_fill_low": Color(1.0, 0.16, 0.12),
		# 剧情里的说话人名字。压在 `button.png` 那块浅色牌子上，要够沉才读得清。
		"dialogue_name": Color(0.72, 0.20, 0.14),
	},
	{
		"label": "Kenney（内置）",
		"dir": "res://assets/ui/",
		"margin": 8.0,                    # 32×32 的像素块，边框约 6 px
		"panel_tint": Color(0.17, 0.20, 0.26, 1.0),
		"button_tint": Color(0.42, 0.47, 0.56),
		"text": Color(0.93, 0.95, 1.0),
		"subtext": Color(0.68, 0.73, 0.83),
		"trough": Color(0.10, 0.12, 0.16),
		"fill": Color(0.52, 0.72, 0.95),
		"grabber": Color(0.95, 0.96, 1.0),
		"dim": Color(0.04, 0.05, 0.08, 0.62),
		"bar_trough": Color(0.10, 0.12, 0.16),
		"bar_edge": Color(0.52, 0.72, 0.95),
		"bar_fill": Color(0.90, 0.28, 0.22),
		"bar_fill_low": Color(1.0, 0.18, 0.14),
		# 深色面板上用暖琥珀色，比红色更「像名字」、也不跟血条的红打架
		"dialogue_name": Color(0.98, 0.78, 0.42),
	},
]

## ── 界面字体：整套 UI 共用一套（剧情正文 / HUD / Esc 设置界面）──
##
## 候选**按优先级排**，第一个存在的用它。这样「本地丢一套显示字体进来」不用改代码；
## 克隆仓库的人没有它时自动回退到仓库自带的 Fusion Pixel（OFL，可分发）。
##
## ⚠️ 实测（`tools/font/font_needed.py`：把游戏里**实际会显示**的 189 个字
##    对着 cmap 查一遍，剧情那一组直接读 `story/*.txt`）：
##      `assets/ui_font/Aa暗夜深渊.ttf`  3.86 MB  剧情 97 字 / 名字 18 字 /
##                                                HUD 30 字 / 设置 96 字 —— **一个不缺**
##      `assets/ui/font.ttf`             6.68 MB  汉字 19214/20992 = 91.5%，也一个不缺
##      `assets/ui_sprout/font.ttf`      0.11 MB  只覆盖 80 个拉丁字形，**缺 213 个汉字**
##    所以 Sprout 那套皮肤字体只够画数字，任何中文都得走这里。
##
## ⚠️ 丢进新字体之后必须**导入一次**，否则 `ResourceLoader.exists()` 认不出来：
##        & <godot> --headless --path . --import
const UI_FONT_CANDIDATES := [
	"res://assets/ui_font/Aa暗夜深渊.ttf",
	"res://assets/ui/font.ttf",
]

## 一个标签占多宽：实测**两套字体的字宽几乎完全一致**（16 px 下「鼠标灵敏度」
## 都是 80 px、24 px 下 28 个汉字都是 611~612 px），所以换字体**不需要动任何版式**，
## 对话框的「一行 44 个汉字」和设置面板的 620 宽都照旧。
const FONT_SIZE := 16

## HUD 上的**数字**（HP / 弹药）要不要跟着换成界面字体。
##
## ⚠️ 默认 **false**，是有意的：HUD 那一轮使用者明确要求「血量要醒目」，而
##    HUD 的数字原来走**像素字体**（`hud.gd` 里对 HP 标题 / 血量数字 / 弹药
##    三处显式 `add_theme_font_override`）。像素字体的方块感正是「醒目」的一部分，
##    换成清秀的显示字体笔画会细一圈。想要整套统一就把它改成 true。
const HUD_FOLLOWS_UI_FONT := true


## 当前用的界面字体。候选一个都没有就返回 null（调用方退回皮肤字体，
## 中文交给 Godot 的系统字体回退 —— 能看，但换台机器就换一副字）。
static func ui_font() -> FontFile:
	var p := ui_font_path()
	if p.is_empty():
		push_warning("[UiSkin] 候选界面字体一个都没找到，中文会退回系统字体：%s"
			% str(UI_FONT_CANDIDATES))
		return null
	return load(p) as FontFile


## 实际用的是哪一份（探针 / 自检打印用；没有就返回空串）。
static func ui_font_path() -> String:
	for p in UI_FONT_CANDIDATES:
		if ResourceLoader.exists(p):
			return p
	return ""


## HUD 数字用的字体：受 `HUD_FOLLOWS_UI_FONT` 控制。
static func hud_number_font(skin: Dictionary) -> FontFile:
	return ui_font() if HUD_FOLLOWS_UI_FONT else font(skin)

## 血条见底的比例。低于它换成更亮的红（玩家和 Boss 用同一个阈值，观感才一致）。
const BAR_LOW_RATIO := 0.25


## 选第一套**关键文件齐**的皮肤。判据只查面板与字体：有这两样就能画出完整界面；
## 按钮缺 `button_hover.png` 时会退回 normal + 提亮（见 `button_style`）。
static func pick() -> Dictionary:
	for skin in SKINS:
		# 程序化皮肤（BA）不依赖任何素材文件，所以**永远可用**、永远排在最前
		if skin.get("procedural", false):
			return skin
		var dir: String = skin["dir"]
		if ResourceLoader.exists(dir + "panel.png") \
				and ResourceLoader.exists(dir + "font.ttf"):
			return skin
	push_warning("[UiSkin] 两套皮肤的素材都没找到，界面会是空的")
	return SKINS[SKINS.size() - 1]


static func tex(skin: Dictionary, name: String) -> String:
	return String(skin["dir"]) + name


static func font(skin: Dictionary) -> FontFile:
	# 程序化皮肤没有素材目录，字体只能走界面字体；`ui_font()` 也是 null 时返回 null，
	# 交给 Godot 的系统字体回退（能看，但换台机器就换一副字）。
	if skin.get("procedural", false):
		return ui_font()
	return load(tex(skin, "font.ttf")) as FontFile


static func make_theme(skin: Dictionary) -> Theme:
	var theme := Theme.new()
	# ⚠️ 优先级：**界面字体 > 皮肤自带字体**。
	#    皮肤字体（Sprout 的 pixelFont）只有 80 个拉丁字形、0 个汉字，本来只够画数字；
	#    换上一套带汉字的显示字体之后整套 UI 应该跟着走，否则会出现「设置界面用显示
	#    字体、HUD 数字还是像素字体」这种两副字混排。
	#    想反过来（HUD 数字保持像素字体）看 `HUD_FOLLOWS_UI_FONT`。
	var f := ui_font()
	if f == null:
		f = font(skin)
	if f != null:
		theme.default_font = f
	theme.default_font_size = FONT_SIZE
	return theme


static func make_style(skin: Dictionary, tex_path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(tex_path)
	var m: float = skin["margin"]
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.modulate_color = tint
	return sb


# ── 程序化皮肤（BA）：面板 / 按钮 / 名牌全部用 `StyleBoxFlat` 现画 ────────────

## 是不是程序化皮肤（没有素材目录、靠代码画）
static func is_procedural(skin: Dictionary) -> bool:
	return bool(skin.get("procedural", false))


## 浅色圆角面板：BA 的菜单 / 信息卡都是「白底 + 浅蓝描边 + 圆角 8 + 一点点投影」。
## 为什么不用 `StyleBoxTexture` 做渐变：BA 那块是 `#FFFFFF → #EDF3F9` 的竖直微渐变，
## 而 `StyleBoxFlat` 只吃平色。本喵选了**平色白**——差异肉眼几乎看不出，
## 换来的是一张不用生成的贴图（见 §13.12「没做的」）。
static func flat_panel(skin: Dictionary, bg: Color, edge: Color, radius: int,
		pad: float = -1.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	sb.anti_aliasing = true
	if pad >= 0.0:
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		sb.content_margin_top = pad * 0.6
		sb.content_margin_bottom = pad * 0.6
	return sb


## 斜切按钮底：BA 的招牌形状（平行四边形）。`skew` 是**相对高度**的比例，不是像素。
static func flat_button(skin: Dictionary, bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(skin["btn_radius"]))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	sb.skew = Vector2(float(skin["btn_skew"]), 0.0)
	# 斜切会让两端「切掉一块」，左右各多留一点，字才不会顶到斜边
	sb.content_margin_left = 20.0
	sb.content_margin_right = 20.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb


static func panel_style(skin: Dictionary) -> StyleBox:
	if is_procedural(skin):
		var sb := flat_panel(skin, skin["panel_bg"], skin["panel_edge"],
			int(skin["panel_radius"]), float(skin["margin"]))
		# 一点点投影：白面板压在亮场景上也要看得出边界
		sb.shadow_color = Color(0.0, 0.19, 0.33, 0.22)
		sb.shadow_size = 6
		sb.shadow_offset = Vector2(0.0, 3.0)
		return sb
	return make_style(skin, tex(skin, "panel.png"), skin["panel_tint"])


## 剧情对话框：BA 那个是**深藏蓝半透明**，和菜单的白面板不是一套。
static func story_panel_style(skin: Dictionary) -> StyleBox:
	if is_procedural(skin):
		var sb := flat_panel(skin, skin["story_bg"], skin["story_edge"],
			int(skin["panel_radius"]), float(skin["margin"]))
		sb.shadow_color = Color(0.0, 0.05, 0.12, 0.45)
		sb.shadow_size = 8
		sb.shadow_offset = Vector2(0.0, 4.0)
		return sb
	return panel_style(skin)


## 说话人名牌：BA 那块是**斜切彩色小牌**，白字。
## ⚠️ 本喵这里统一用 accent 青蓝，没有按角色分色 —— 那个项目的 `roleColor()`
##    有六种角色色（Sky / Green / Purple / Yellow / Red / Deep），要分色得先有
##    「这个说话人属于哪个角色」的表。见 §13.12「没做的」。
static func name_tag_style(skin: Dictionary) -> StyleBox:
	if is_procedural(skin):
		var sb := flat_button(skin, skin["accent"], skin["accent"])
		sb.set_corner_radius_all(0)
		sb.corner_detail = 0
		sb.anti_aliasing = false
		sb.content_margin_left = 22.0
		sb.content_margin_right = 14.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		return sb
	return button_style(skin, "normal")


## 「数值片」：BA 里数值/消耗都用一块**深蓝黑底**压着（`chipBlack() = #252F41`）。
static func chip_style(skin: Dictionary) -> StyleBox:
	if is_procedural(skin):
		var sb := flat_panel(skin, skin["chip_bg"], skin["chip_bg"], 4, 10.0)
		sb.set_border_width_all(0)
		return sb
	return panel_style(skin)


## 剧情对话框上的**正文色**。
## ⚠️ 必须单独一个入口：BA 那个框是**深藏蓝底**，正文得是白的；
##    而 `skin["text"]` 是「浅色面板上的正文色」（BA 是深藏蓝）—— 直接复用会写成白底白字。
##    贴图那两套对话框是浅底，所以没有这个键，回退到 `text` 行为不变。
static func story_text(skin: Dictionary) -> Color:
	return skin.get("story_text", skin["text"])


static func story_subtext(skin: Dictionary) -> Color:
	return skin.get("story_subtext", skin["subtext"])


## 选项行**未选中**时的压暗色。
## ⚠️ 贴图那两套是**暖灰**（压在米色木板上正好）；BA 那套压在**亮青**按钮上，
##    暖灰一乘就变成浑褐色 —— 所以 BA 给一个偏冷的压暗值。
static func choice_dim(skin: Dictionary) -> Color:
	return skin.get("choice_dim", Color(0.80, 0.78, 0.75, 1.0))


static func choice_dim_disabled(skin: Dictionary) -> Color:
	return skin.get("choice_dim_disabled", Color(0.62, 0.60, 0.58, 1.0))


## 按钮三态。程序化皮肤走 BA 的「亮青底 + 深藏蓝字 + 斜切」。
static func button_style(skin: Dictionary, kind: String) -> StyleBox:
	if is_procedural(skin):
		var bg: Color = skin["btn_bg"]
		match kind:
			"hover":
				bg = skin["btn_bg_hover"]
			"pressed":
				bg = skin["btn_bg_pressed"]
		return flat_button(skin, bg, skin["btn_edge"])
	return _texture_button_style(skin, kind)


## 贴图皮肤的按钮三态。`button_hover.png` 是**可选**的：没有就用 normal 的图 + 提亮 tint，
## 这样换一套只给 normal/pressed 的皮肤（比如这里裁出来的 Sprout）也不用改代码。
##
## ⚠️ 2026-11-09：改名加了下划线 —— 对外的三态入口现在是上面的 `button_style()`，
##    它按皮肤分派（程序化走 BA 的斜切块、贴图皮肤走这里）。
static func _texture_button_style(skin: Dictionary, kind: String) -> StyleBoxTexture:
	var base: Color = skin["button_tint"]
	match kind:
		"hover":
			if ResourceLoader.exists(tex(skin, "button_hover.png")):
				return make_style(skin, tex(skin, "button_hover.png"), base)
			return make_style(skin, tex(skin, "button.png"), Color(
				minf(base.r * 1.25, 1.0), minf(base.g * 1.25, 1.0),
				minf(base.b * 1.25, 1.0), base.a))
		"pressed":
			if ResourceLoader.exists(tex(skin, "button_pressed.png")):
				return make_style(skin, tex(skin, "button_pressed.png"), base)
			return make_style(skin, tex(skin, "button.png"), Color(
				base.r * 0.8, base.g * 0.8, base.b * 0.8, base.a))
		_:
			return make_style(skin, tex(skin, "button.png"), base)


## 血条槽：深色底 + **草绿描边**。
##
## ⚠️ 这个东西**不能**当 `ProgressBar` 的 `background` 用 —— 白搭。
##    实测（`_probe_bar_margin.gd` + 逐像素量截图）：**`ProgressBar` 不会拿
##    `background` 样式盒的 `get_margin()` 去内缩 `fill`**，红条永远从条框最外沿
##    开始画。把 `content_margin` 设成 8、设成默认、换 `StyleBoxFlat` 还是九宫格，
##    结果一模一样（对照组里只有 `PanelContainer.panel` 的内缩真生效）。
##    所以：**外框和槽都由独立的 `Panel` 节点画，`ProgressBar` 自己用
##    `StyleBoxEmpty` 当背景、按算好的内缩矩形摆放。**
static func bar_trough(skin: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = skin["bar_trough"]
	sb.border_color = skin["bar_edge"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	return sb


static func bar_fill(skin: Dictionary, ratio: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = skin["bar_fill_low"] if ratio < BAR_LOW_RATIO else skin["bar_fill"]
	sb.set_corner_radius_all(1)
	return sb


## 纯色小方块纹理（给 grabber / 复选框用）。像素风不需要渐变和圆角。
static func solid_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


# ── 说话人名字牌的颜色 ─────────────────────────────────────────────────────
#
# ⚠️ 这是一张**「说话人 → 色号」表**，不是照抄原作的「角色 → 色号」表。
#    但**本喵手上没有「爱丽丝/优香/小桃… 各对应哪种色」的原始资料**，
#    所以下面这张表是**本喵按角色气质自己配的**，不许当成官方设定。
#    要改颜色只改这个字典，不用动别处。
#
# 键是剧情里 `who:` 后面写的名字（见 `story/设定.md` 的角色表）。
const SPEAKER_COLORS := {
	"爱丽丝": Color("#4ec3f5"),    # 主角：accent 青蓝（和标题/按钮同色）
	"优香": Color("#ff8fa3"),      # 粉
	"诺亚": Color("#a8b8d8"),      # 冷灰蓝（诺亚是白毛，压成偏冷的）
	"小雪": Color("#ffffff"),      # 白（底色会压暗，见 `_tag_text_color`）
	"小桃": Color("#ffc95c"),      # 橙黄（BA 的 orangeGradient 亮端）
	"小绿": Color("#7fd6a0"),      # 绿
	"柚子": Color("#ffd76e"),      # 暖黄
	"凯伊": Color("#9b8cff"),      # 紫
	"芹香": Color("#ff9f6b"),      # 橘
	"老师": Color("#e6eef8"),      # 近白
	"霸王龙优香": Color("#ff8fa3"),
	"飞猪优香": Color("#ff8fa3"),
	"倭瓜优香": Color("#ff8fa3"),
	"霍德": Color("#8fa0ff"),
	"佩洛洛斯拉": Color("#ffb3d9"),
	"比纳": Color("#a0e8e0"),
	"哥利亚": Color("#c9a0ff"),
}

## 名字牌默认色（表里没有的说话人用它：accent 青蓝）
static func speaker_color(skin: Dictionary, who: String) -> Color:
	if not is_procedural(skin):
		return skin["accent"] if skin.has("accent") else skin["fill"]
	return SPEAKER_COLORS.get(who, skin["accent"])


## 名牌上的字色：底够亮就写深藏蓝，底够暗就写白。
## 拿「相对亮度」判断，不用肉眼看 —— 白底（小雪）和近白底（老师）都得走深色字。
static func _tag_text_color(bg: Color) -> Color:
	var lum := 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
	return Color("#003153") if lum > 0.62 else Color(1, 1, 1, 1)


## 名牌样式（**按说话人换色**）。
##
## ⚠️ 为什么要有这个重载：名牌原来固定用 `accent` 一种颜色，所有角色长得一样，
##    在 BA 观感里差别很大 —— 那边每个人名有自己的颜色。
static func name_tag_style_for(skin: Dictionary, who: String) -> StyleBox:
	if not is_procedural(skin):
		return name_tag_style(skin)
	var c := speaker_color(skin, who)
	var sb := flat_button(skin, c, c)
	sb.set_corner_radius_all(0)
	sb.corner_detail = 0
	sb.anti_aliasing = false
	sb.content_margin_left = 22.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	return sb


## 名牌文字颜色（跟着 `name_tag_style_for` 的底色走）
static func name_tag_text(skin: Dictionary, who: String) -> Color:
	if not is_procedural(skin):
		return skin["dialogue_name"]
	return _tag_text_color(speaker_color(skin, who))


## 斜切量：名字牌比按钮矮，同样比例看不清，所以放大一点（BA 那个项目也是这么做的）
const NAME_TAG_SKEW_SCALE := 1.6


## 名字牌用的斜切样式的**几何**。`StyleBoxFlat` 的 `skew` 是相对高度的比例，
## 名字牌高度固定 46 px，这里乘一个放大系数。
static func name_tag_skew(skin: Dictionary) -> float:
	if not is_procedural(skin):
		return 0.0
	return float(skin["btn_skew"]) * NAME_TAG_SKEW_SCALE


## 圆角小方块纹理。逐像素判「四角圆」：把坐标夹到「内缩 r 的矩形」上，
## 夹出来的偏移超出半径就透明。
static func rounded_texture(size: int, radius: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := clampi(radius, 0, size / 2)
	var rr := float(r * r)
	for y in size:
		for x in size:
			var dx := float(x - clampi(x, r, size - 1 - r))
			var dy := float(y - clampi(y, r, size - 1 - r))
			if dx * dx + dy * dy <= rr:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


## 滑块抓手 / 开关指示块用的纹理。
## ⚠️ 贴图那两套是**像素风**，抓手指的是直角方块（保持观感）；
##    BA 是圆角 UI，直角方块抓手压在圆角滑槽上会显得毛刺 —— 所以分派。
static func knob_texture(skin: Dictionary, size: int, color: Color) -> ImageTexture:
	if is_procedural(skin):
		return rounded_texture(size, maxi(size / 3, 1), color)
	return solid_texture(size, color)


# ── Minecraft 风格的 Boss 血条 ────────────────────────────────────────────────
#
# 几何与配色取自 1.21.11 的官方客户端，两道工序：
#   1. `javap -c -constants net.minecraft.client.gui.components.BossHealthOverlay`
#      → 条宽 182、条高 5、名字画在条顶上方 9 px（白色，`drawString(..., -1)` 带阴影）、
#        一行步距 10 + font.lineHeight(9) = 19 px、首行 y = 12、x = 屏宽/2 - 91，
#        超出 屏高/3 就停。
#   2. 量 jar 里 `assets/minecraft/textures/gui/sprites/boss_bar/*.png`（都是 182×5）
#      → 反推出下面那两组五行比例。
#
# ⚠️ **只抄几何和比例，不搬 Mojang 的美术资源**：条贴图是这里按比例现算的，
#    仓库里不放任何 `boss_bar/*.png`。五行比例是「量出来照着做」的复刻，
#    不是原始素材；真要商用请自行确认授权。
#
# ⚠️ 1.21.11 起 MC 自己已经改成「按颜色分贴图」，颜色常量不在代码里了
#    （`BossBarColor` 只留一个 `ChatFormatting`），所以主色只能从贴图上量。
const MC_BAR_PX := Vector2i(182, 5)

## 五行相对「主色」的倍率。七套 `<color>_progress.png` 共用同一组，误差 ≤ 1/255。
## 语义是「暗边 / 高光 / 主色 / 暗部 / 暗边」。
const MC_PROGRESS_RATIO := [0.3135, 1.0, 0.784, 0.593, 0.3135]

## 槽（`<color>_background.png`）在同样五行位置上的比例。
const MC_BACKGROUND_RATIO := [0.161, 0.309, 0.242, 0.309, 0.161]

## MC 的七种 Boss 条主色 = 各自 `<color>_progress.png` 的高光行（y=1）。
const MC_COLORS := {
	"pink": Vector3i(236, 0, 184),
	"blue": Vector3i(0, 183, 236),
	"red": Vector3i(236, 53, 0),
	"green": Vector3i(29, 236, 0),
	"yellow": Vector3i(233, 236, 0),
	"purple": Vector3i(123, 0, 236),
	"white": Vector3i(236, 236, 236),
}

## 两端「像素圆角」的形状。
##
## ⚠️ 这是**本喵自己设计的**，不是照搬 Mojang 的位图 —— 只复刻观感，不复制像素。
##    量过 `pink_progress.png` 的实际形状：最外 1 列在**上下两行是透明的**（切角），
##    再往里还有 3 列由暗到亮的过渡，所以条的两头看着是圆的、中间是长方体。
##    `MC_CAP_INSET[y]` = 第 y 行左端要挖空几列；`MC_CAP_RATIO[i]` = 之后第 i 列相对
##    **该行自己的底色**要压暗多少。⚠️ 是相对该行、不是相对全局主色 —— 槽本来就暗，
##    按全局主色算会把槽的两头反而提亮（本喵第一版就是这么错的）。
const MC_CAP_INSET := [1, 0, 0, 0, 1]
const MC_CAP_RATIO := [0.22, 0.52, 0.80]

## 两端「像素圆角」一共占几列源像素：`MC_CAP_INSET` 挖掉的 1 列 + `MC_CAP_RATIO` 的 3 列。
const MC_CAP_COLS := 4


static func mc_color(name: String) -> Color:
	var v: Vector3i = MC_COLORS.get(name, MC_COLORS["white"])
	return Color8(v.x, v.y, v.z)


## 满血时条两端的帽宽（逻辑 px）。
##
## ⚠️ 这是「**条框宽度 / 182 × 4 源列**」，也就是满血时把 182 px 贴图拉伸到条框宽度后
##    帽自然呈现的宽度。设给九宫格时必须用它，否则满血的条会跟槽的圆角对不上。
##    （本工程的条框 546 ⇒ 12 px。）
static func mc_bar_cap_px(bar_width: float) -> float:
	return float(MC_CAP_COLS) / float(MC_BAR_PX.x) * bar_width


## 按 MC 的五行的比例现算一条贴图。`progress` 选高光那组还是槽那组。
##
## `hscale` 是**横向烘焙倍率**：每 1 列源像素烘成 `hscale` 列。
##
## ⚠️ 为什么需要它（用户报「血条有时候会回退到长方形没有圆边」）：
##    `ProgressBar` 把 `fill` 样式盒**整张拉伸**进「按血量缩短后的矩形」——
##    既不裁剪、也不给帽保留最小宽度。像素圆角是**烤在贴图两端**的，
##    于是帽宽 ∝ 血量比例：满血 182→546（3 倍）帽有 12 px，10% 血时帽不到 1 px。
##    给样式盒设**九宫格边距**能让帽不参与拉伸，但实测（`_probe_boss_bar_caps.gd`）
##    Godot 的九宫格边距是**按源像素 1:1** 画的：给 182 px 宽的贴图设 12，
##    屏幕上只有 4 px（= 真正有色的源列数）。所以先把贴图横向烘大 `hscale` 倍，
##    再让边距 = `MC_CAP_COLS * hscale`，帽宽就**恰好等于满血时的大小**，与血量无关。
static func mc_bar_texture(bright: Color, progress: bool, hscale := 1) -> ImageTexture:
	var ratios: Array = MC_PROGRESS_RATIO if progress else MC_BACKGROUND_RATIO
	var w := MC_BAR_PX.x * hscale
	var img := Image.create(w, MC_BAR_PX.y, false, Image.FORMAT_RGBA8)
	for y in MC_BAR_PX.y:
		var k: float = ratios[y]
		var row := Color(bright.r * k, bright.g * k, bright.b * k, 1.0)
		# 1) 先铺这一行的平色
		img.fill_rect(Rect2i(0, y, w, 1), row)
		# 2) 两端改成像素圆角：先挖掉最外 inset 列，再铺由暗到亮的过渡
		var inset: int = MC_CAP_INSET[y]
		for i in inset:
			var a := i * hscale
			img.fill_rect(Rect2i(a, y, hscale, 1), Color(0, 0, 0, 0))
			img.fill_rect(Rect2i(w - a - hscale, y, hscale, 1), Color(0, 0, 0, 0))
		for i in MC_CAP_RATIO.size():
			var t := float(MC_CAP_RATIO[i])
			var cap := Color(row.r * t, row.g * t, row.b * t, 1.0)
			var lx: int = (inset + i) * hscale
			img.fill_rect(Rect2i(lx, y, hscale, 1), cap)
			img.fill_rect(Rect2i(w - lx - hscale, y, hscale, 1), cap)
	return ImageTexture.create_from_image(img)


## 条用的样式盒。
##
## `STRETCH` 是有意的：整张贴图被拉到节点尺寸，五行等比放大；配上节点上的
## `TEXTURE_FILTER_NEAREST` 就是干净的整数倍像素放大（本工程的条正好 3 倍）。
## 这里**不需要**内容边距 —— 贴图本身就是整条，`ProgressBar` 那条「不吃
## background 边距」的坑（见 `bar_trough`）在这儿用不上。
##
## `cap_px > 0` 时开**九宫格**：贴图横向烘大 `cap_px / MC_CAP_COLS` 倍，
## 边距 = `MC_CAP_COLS * hscale` ⇒ 两端的帽**固定这么宽**，不再随血量缩水
## （用户报的「血条回退成长方形」）。`cap_px = 0` 保持老的整张拉伸行为。
##
## ⚠️ 边距只在**横向**开：竖向要是也开九宫格，5 行就变成「上下 1 行各占 1 逻辑 px、
##    中间 3 行挤在剩下的高度里」，五行的比例会散掉。竖向留 STRETCH，5 行等比放大。
static func mc_bar_style(bright: Color, progress: bool, cap_px := 0.0) -> StyleBoxTexture:
	var hscale := 1
	var margin := 0.0
	if cap_px > 0.0:
		hscale = maxi(roundi(cap_px / float(MC_CAP_COLS)), 1)
		margin = float(MC_CAP_COLS * hscale)
	var sb := StyleBoxTexture.new()
	sb.texture = mc_bar_texture(bright, progress, hscale)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	return sb

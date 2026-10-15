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
##    会略有出入。所以这套字体只用在「纯数字/拉丁」的控件上（弹药数、HP 数字）。
##    要大段中文（剧情正文）走下面的 `cjk_font()`。
##
## ⚠️ Sprout 的 `panel.png` 是 106×122、圆角比 Kenney 的 32×32 大得多，两套的
##    九宫格边距必须分别给（`margin` 字段），不然小图会被拉伸成糊的。

const SKINS := [
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

const FONT_SIZE := 16

## ── 剧情正文用的中文字体 ──
##
## ⚠️ **不能用皮肤字体**。实测（`..\_hud_preview\font_cmap_check.py`，直接解 TTF 的
##    cmap 表）：
##      `assets/ui/font.ttf`       6.68 MB  汉字 19214/20992 (91.5%)、中文标点 100%
##      `assets/ui_sprout/font.ttf` 0.11 MB  汉字 **0/20992**、中文标点 0
##    Sprout 那套只有 80 个拉丁字形。设置界面（纯数字/拉丁）靠它没事，
##    大段中文正文必须换字体 —— 否则靠 Godot 的 `allow_system_fallback` 回退到
##    系统字体，换一台机器就换一副字、也不是像素风。
##
## `assets/ui/font.ttf` 是 Fusion Pixel Font **12px**（作者 TakWolf），**SIL OFL 1.1**，
## 允许随软件分发。字号取 **12 的整数倍**（12/24/36）最锐利 —— 它是像素字体。
const CJK_FONT_PATH := "res://assets/ui/font.ttf"
const CJK_FONT_SIZE := 24


## 剧情正文的中文字体。拿不到就返回 null（调用方退回皮肤字体，中文交给系统回退）。
static func cjk_font() -> FontFile:
	if not ResourceLoader.exists(CJK_FONT_PATH):
		push_warning("[UiSkin] 找不到 %s，剧情正文会退回皮肤字体（中文靠系统回退）"
			% CJK_FONT_PATH)
		return null
	return load(CJK_FONT_PATH) as FontFile

## 血条见底的比例。低于它换成更亮的红（玩家和 Boss 用同一个阈值，观感才一致）。
const BAR_LOW_RATIO := 0.25


## 选第一套**关键文件齐**的皮肤。判据只查面板与字体：有这两样就能画出完整界面；
## 按钮缺 `button_hover.png` 时会退回 normal + 提亮（见 `button_style`）。
static func pick() -> Dictionary:
	for skin in SKINS:
		var dir: String = skin["dir"]
		if ResourceLoader.exists(dir + "panel.png") \
				and ResourceLoader.exists(dir + "font.ttf"):
			return skin
	push_warning("[UiSkin] 两套皮肤的素材都没找到，界面会是空的")
	return SKINS[SKINS.size() - 1]


static func tex(skin: Dictionary, name: String) -> String:
	return String(skin["dir"]) + name


static func font(skin: Dictionary) -> FontFile:
	return load(tex(skin, "font.ttf")) as FontFile


static func make_theme(skin: Dictionary) -> Theme:
	var theme := Theme.new()
	var f := font(skin)
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


static func panel_style(skin: Dictionary) -> StyleBoxTexture:
	return make_style(skin, tex(skin, "panel.png"), skin["panel_tint"])


## 按钮三态。`button_hover.png` 是**可选**的：没有就用 normal 的图 + 提亮 tint，
## 这样换一套只给 normal/pressed 的皮肤（比如这里裁出来的 Sprout）也不用改代码。
static func button_style(skin: Dictionary, kind: String) -> StyleBoxTexture:
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


static func mc_color(name: String) -> Color:
	var v: Vector3i = MC_COLORS.get(name, MC_COLORS["white"])
	return Color8(v.x, v.y, v.z)


## 按 MC 的五行的比例现算一条 182×5 的贴图。`progress` 选高光那组还是槽那组。
static func mc_bar_texture(bright: Color, progress: bool) -> ImageTexture:
	var ratios: Array = MC_PROGRESS_RATIO if progress else MC_BACKGROUND_RATIO
	var img := Image.create(MC_BAR_PX.x, MC_BAR_PX.y, false, Image.FORMAT_RGBA8)
	for y in MC_BAR_PX.y:
		var k: float = ratios[y]
		var row := Color(bright.r * k, bright.g * k, bright.b * k, 1.0)
		# 1) 先铺这一行的平色
		img.fill_rect(Rect2i(0, y, MC_BAR_PX.x, 1), row)
		# 2) 两端改成像素圆角：先挖掉最外 inset 列，再铺由暗到亮的过渡
		var inset: int = MC_CAP_INSET[y]
		for i in inset:
			img.set_pixel(i, y, Color(0, 0, 0, 0))
			img.set_pixel(MC_BAR_PX.x - 1 - i, y, Color(0, 0, 0, 0))
		for i in MC_CAP_RATIO.size():
			var t := float(MC_CAP_RATIO[i])
			var cap := Color(row.r * t, row.g * t, row.b * t, 1.0)
			var lx: int = inset + i
			img.set_pixel(lx, y, cap)
			img.set_pixel(MC_BAR_PX.x - 1 - lx, y, cap)
	return ImageTexture.create_from_image(img)


## 条用的样式盒。
##
## `STRETCH` 是有意的：整张 182×5 被拉到节点尺寸，五行等比放大；配上节点上的
## `TEXTURE_FILTER_NEAREST` 就是干净的整数倍像素放大（本工程的条正好 3 倍）。
## 这里**不需要**内容边距 —— 贴图本身就是整条，`ProgressBar` 那条「不吃
## background 边距」的坑（见 `bar_trough`）在这儿用不上。
static func mc_bar_style(bright: Color, progress: bool) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = mc_bar_texture(bright, progress)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return sb

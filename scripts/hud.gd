extends CanvasLayer
## HUD：玩家血量、Boss 血条、弹药、换弹进度条、泼溅加载状态、准星随瞄准/移动扩张。
##
## 皮肤走 `ui_skin.gd`：
##   玩家血量 / 弹药 走 Sprout 的九宫格米色木板 + 「红条 + 草绿描边」；
##   **Boss 血条走 Minecraft 风格**（细长五行渐变条 + 白字名字，无底板无外框），
##   几何与配色见 `ui_skin.gd` 的 `MC_BAR_PX` 那一段。
##
## 布局（逻辑单位；`canvas_items` 拉伸下再乘缩放）：
##   ┌ 左上  玩家血量面板（一整块 Sprout 面板，自己画）
##   ├ 顶部中 Boss 血条组（一位一行，见 bind_bosses）
##   ├ 左上   泼溅加载状态行（贴在血量面板下沿）
##   └ 右下  弹药 + 换弹条
##
## 定位一律用**绝对矩形**，不靠容器自动排版 —— 画布逻辑高度固定 900，位置算得准，
## 而且这一层要跟准星一样做物理像素对齐，自动排版那种「大概齐」反而添乱。
##
## ⚠️ 节点命名是**约定**，不是随手起的：自检按名字取（`_verify_boss_pig.gd` 取
##    `BossBar0/1`、`BossName0/1`，`_verify_room.gd` 取 `SplatStatus0/1`），
##    所以它们必须**保持是 HUD 的直接子节点**、且名字不能变。
##    （曾经靠遍历顺序取，结果深度遍历是倒序的，把「打霸王龙掉的是飞猪那条」
##     误判成了 bug —— 名字是唯一可靠的锚点。）

## 准星随瞄准/移动扩张。
##
## ── 尺寸一律按「**物理像素**」给，厚度必须取偶数 ──
##
## ⚠️ 为什么这么较真：`canvas_items` 拉伸的缩放是 **1.4822 这种非整数**。
##    原来中心点写 `offset = -1.5..1.5`（3 逻辑 px）、十字条 `-1..1`（2 逻辑 px），
##    换算到物理像素是 4.45 与 2.96 —— **两者被栅格化时取整方式不同**，中心点会
##    整体偏到十字右边约半个逻辑像素。放大截图一眼就能看出来（用户就是这么发现的）。
##
##    治法：把准星原点**吸附到整数物理像素**，所有厚度都按物理像素给**偶数**，
##    这样中心点与十字条共享同一个中心、左右边界严格镜像。
##    下面三个常量就是「想在 1440p 上画多少物理像素」，改它们即可，不用碰逻辑坐标。
const CROSS_DOT_PX := 4.0     ## 中心点边长（物理像素，必须偶数）
const CROSS_THICK_PX := 2.0   ## 十字条粗细（物理像素，必须偶数）
const CROSS_ARM_PX := 8.0     ## 十字条长度（物理像素；离中心多远由扩散量决定）

## 血条描边宽度（逻辑 px）。见 `_make_bar_stack()` 那段关于 `ProgressBar` 的注释。
const BAR_EDGE_PX := 2.0

@onready var crosshair: Control = $Crosshair
@onready var dot: ColorRect = $Crosshair/Dot
@onready var t: ColorRect = $Crosshair/T
@onready var b: ColorRect = $Crosshair/B
@onready var l: ColorRect = $Crosshair/L
@onready var r: ColorRect = $Crosshair/R
@onready var ammo: Label = $Panel/Margin/VBox/Ammo
@onready var reload_trough: Panel = $Panel/Margin/VBox/ReloadTrough
@onready var reload_bar: ProgressBar = $Panel/Margin/VBox/ReloadTrough/Reload

# --- 左上角玩家血量面板 ---
const HP_PANEL_POS := Vector2(24.0, 20.0)   ## 左上角留出的边距
const HP_PANEL_SIZE := Vector2(344.0, 92.0)
const HP_PAD := 16.0                        ## 面板内左右留白
const HP_ROW_TOP := 8.0                     ## 「HP」和数字那一行
const HP_ROW_H := 42.0
const HP_BAR_TOP := 54.0
const HP_BAR_HEIGHT := 22.0
const HP_FONT_SIZE := 34.0                  ## 血量数字：要够大才「醒目」
const HP_TITLE_FONT_SIZE := 18.0

# --- 右下角弹药面板 ---
const AMMO_FONT_SIZE := 34
const RELOAD_BAR_HEIGHT := 12.0

# --- 顶部 Boss 血条组（Minecraft 风格）---
## **一个 Boss 一行**，自上而下按索引排。
## 加同伴那一轮场上变成两位 Boss（霸王龙优香 / 飞猪优香），所以从单条改成一组。
##
## 宽 = MC 的 182 × 3；**高是单独给的，故意比 MC 的 5×3 薄** ——
## 用户反馈三倍高的条还是嫌挡视野，所以宽度保留 MC 的观感、厚度压到 12。
const BOSS_BAR_WIDTH := 546.0
const BOSS_BAR_HEIGHT := 12.0
## 全体 Boss 统一用 MC 的哪种条色。MC 里末影龙那条是 `pink`（粉紫），也是用户点名要的。
## 想换成凋灵那种偏蓝的紫就改 `"purple"`；想按 Boss 分别配色，把这里改成查表即可。
const BOSS_BAR_COLOR := "pink"
const BOSS_NAME_FONT_SIZE := 16
const BOSS_NAME_HEIGHT := 22.0
## 名字底边到条顶边的空隙（MC 是 2 px）
const BOSS_NAME_GAP := 6.0
## 一行的竖向步距（MC 是 19 px；这里按本工程更大的字模放大后的值）
const BOSS_ROW_HEIGHT := 46.0
## 第一条的 y。
## ⚠️ 必须 ≥ `BOSS_NAME_HEIGHT + BOSS_NAME_GAP`，否则**第一行的名字会被顶出画面**。
##    （MC 敢用 y = 12 是因为它的名字只有 9 px 高，本工程的字模更高。）
const BOSS_TOP := 30.0

# --- 左上角泼溅加载状态行 ---
## **一份场地一行**，贴在血量面板下沿（不挡住血量）。
const SPLAT_ROW_HEIGHT := 20.0
const SPLAT_ROW_TOP := 128.0

var _player: Player
var _weapon: Weapon
var _spread := 8.0
## 当前皮肤（`ui_skin.gd` 的 SKINS 里的一项）
var _skin: Dictionary = {}
var _health_bar: ProgressBar
var _health_text: Label
## 左上角泼溅状态行：**一份场地一行**，每行 {label: Label, title: String, done: bool}
var _splat_rows: Array[Dictionary] = []
## 顶部 Boss 血条组：一个 Boss 一行，每行 {name: Label, bar: ProgressBar, title: String}
var _boss_rows: Array[Dictionary] = []

## SogRuntime 的进度阶段 → 给人看的文案
const SPLAT_PHASE := {
	"textures": "解码 SOG 纹理",
	"center": "计算场景中心",
	"decode": "展开高斯点",
	"pack": "打包 GPU 数据",
	"cache": "写展开缓存",
}


func _ready() -> void:
	_skin = UiSkin.pick()
	_style_ammo_panel()
	_build_player_health()
	# 泼溅状态行不在这里建：见 bind_splats()，要按场上实际有几份场地来排行数。
	# （校园 615 万点首次要解码约 50 s，不给状态行玩家会以为卡死了。）
	# Boss 血条同理：见 bind_bosses()，要按场上实际有几位来排行数。
	print("[HUD] 皮肤 = %s（%s）" % [_skin["label"], _skin["dir"]])


# --- 摆放小工具 --------------------------------------------------------------

## 左上角定位（父节点是 CanvasLayer 或普通 Control，锚点 0）。
func _place(c: Control, pos: Vector2, size: Vector2) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + size.x
	c.offset_bottom = pos.y + size.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


## 水平居中定位（相对画布中线；父节点是 CanvasLayer 时 offset 就是绝对偏移）。
func _place_centered(c: Control, rect: Rect2) -> void:
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = rect.position.x
	c.offset_top = rect.position.y
	c.offset_right = rect.position.x + rect.size.x
	c.offset_bottom = rect.position.y + rect.size.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE


# --- 左上角：玩家血量 ---------------------------------------------------------

## 玩家血量面板。**自己画的一整块**（血量是最该一眼看到的信息，不能挤在角落里当小字）。
##
## ⚠️ 这里刻意**不用** `PanelContainer`/`VBoxContainer`：容器会把控件按最小尺寸摆，
##    而下面这些坐标是照着 344×92 的固定面板手算的，交给容器反而不好对。
func _build_player_health() -> void:
	var panel := Panel.new()
	panel.name = "PlayerHealth"
	panel.add_theme_stylebox_override("panel", UiSkin.panel_style(_skin))
	_place(panel, HP_PANEL_POS, HP_PANEL_SIZE)
	add_child(panel)

	var inner_w := HP_PANEL_SIZE.x - HP_PAD * 2.0

	var title := Label.new()
	title.text = "HP"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", UiSkin.hud_number_font(_skin))
	title.add_theme_font_size_override("font_size", int(HP_TITLE_FONT_SIZE))
	title.add_theme_color_override("font_color", _skin["subtext"])
	_place(title, Vector2(HP_PAD, HP_ROW_TOP), Vector2(70.0, HP_ROW_H))
	panel.add_child(title)

	_health_text = Label.new()
	_health_text.name = "HealthText"
	_health_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_health_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_text.add_theme_font_override("font", UiSkin.hud_number_font(_skin))
	_health_text.add_theme_font_size_override("font_size", int(HP_FONT_SIZE))
	_health_text.add_theme_color_override("font_color", _skin["text"])
	_place(_health_text, Vector2(HP_PAD, HP_ROW_TOP), Vector2(inner_w, HP_ROW_H))
	panel.add_child(_health_text)

	var stack := _make_bar_stack(
		Vector2(HP_PAD, HP_BAR_TOP), Vector2(inner_w, HP_BAR_HEIGHT),
		"HealthTrough")
	panel.add_child(stack["trough"])
	_health_bar = stack["bar"]
	_health_bar.value = 1.0


## 血条三层：**槽面板 → 填充条**。返回 {"trough": Panel, "bar": ProgressBar}。
##
## ⚠️ 为什么不是一个 `ProgressBar` 加两个样式盒就够了 —— 本喵踩过这个坑：
##    实测（`_probe_bar_margin.gd` + 逐像素量游戏截图）**`ProgressBar` 不会拿
##    `background` 样式盒的 `get_margin()` 去内缩 `fill`**，红条永远从条框最外沿
##    开始画。`content_margin` 设 8、设默认、换 `StyleBoxFlat` 还是九宫格，
##    结果一模一样（对照组里只有 `PanelContainer.panel` 的内缩真生效）。
##    表现就是：HP 条的草绿描边、Boss 条的木板外框**整个被红条盖住**，一点都看不见。
##    所以外框/槽交给独立的 `Panel`，填充条自己用 `StyleBoxEmpty` 当背景、
##    按算好的内缩矩形摆。
func _make_bar_stack(pos: Vector2, size: Vector2, trough_name: String) -> Dictionary:
	var trough := Panel.new()
	trough.name = trough_name
	trough.add_theme_stylebox_override("panel", UiSkin.bar_trough(_skin))
	_place(trough, pos, size)

	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override("fill", UiSkin.bar_fill(_skin, 1.0))
	_place(bar, Vector2(BAR_EDGE_PX, BAR_EDGE_PX),
		size - Vector2(BAR_EDGE_PX, BAR_EDGE_PX) * 2.0)
	trough.add_child(bar)

	return {"trough": trough, "bar": bar}


func _on_player_health(current: float, maximum: float) -> void:
	if _health_bar == null:
		return
	var ratio := 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	_health_bar.value = ratio
	_health_bar.add_theme_stylebox_override("fill", UiSkin.bar_fill(_skin, ratio))
	_health_text.text = "%d / %d" % [int(ceil(current)), int(maximum)]
	# 见底时数字也变红，比只变条更早被注意到
	_health_text.add_theme_color_override("font_color",
		_skin["bar_fill_low"] if ratio < UiSkin.BAR_LOW_RATIO else _skin["text"])


# --- 右下角：弹药 -------------------------------------------------------------

## 把 .tscn 里那个默认灰面板换成 Sprout 的九宫格米色板。
## 内容只有「弹药数 + 换弹条」两行 —— 「腰射 / 蹲行」和速度显示已经撤掉，
## 状态那点信息不值得常驻占一块画面。
func _style_ammo_panel() -> void:
	var panel := $Panel as PanelContainer
	panel.add_theme_stylebox_override("panel", UiSkin.panel_style(_skin))

	var margin := $Panel/Margin as MarginContainer
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)

	reload_trough.add_theme_stylebox_override("panel", UiSkin.bar_trough(_skin))

	ammo.add_theme_font_override("font", UiSkin.hud_number_font(_skin))
	ammo.add_theme_font_size_override("font_size", AMMO_FONT_SIZE)
	ammo.add_theme_color_override("font_color", _skin["text"])

	reload_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	reload_bar.add_theme_stylebox_override("fill", UiSkin.bar_fill(_skin, 1.0))


# --- 顶部：Boss 血条组 --------------------------------------------------------

func bind_bosses(bosses: Array) -> void:
	_boss_rows.clear()
	var index := 0
	for b in bosses:
		var boss := b as Boss
		if boss == null:
			continue
		_add_boss_row(index, boss.display_name)
		boss.health_changed.connect(_on_boss_health.bind(index))
		_on_boss_health(boss.health, boss.max_health, index)
		index += 1


## 只接一位 Boss 的旧写法（保留，自检里还在用）
func bind_boss(boss: Boss) -> void:
	bind_bosses([boss])


## 一行 = 名字 `Label` + 血条 `ProgressBar`，**都是 HUD 的直接子节点**（自检按名字取）。
##
## 样子照 Minecraft：一根细长的五行渐变条，白字名字带阴影压在正上方居中，
## **没有底板、没有外框** —— MC 就是不画（这一点本喵扒过字节码确认：
## `render()` 从头到尾只有 `blitSprite` 和 `drawString`，没有任何 `fill`）。
## 五行比例与七色主色见 `ui_skin.gd` 的 `MC_BAR_PX` 那一段。
func _add_boss_row(index: int, title: String) -> void:
	var top := BOSS_TOP + float(index) * BOSS_ROW_HEIGHT

	var label := Label.new()
	label.name = "BossName%d" % index
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", BOSS_NAME_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	_place_centered(label, Rect2(-BOSS_BAR_WIDTH * 0.5,
		top - BOSS_NAME_GAP - BOSS_NAME_HEIGHT,
		BOSS_BAR_WIDTH, BOSS_NAME_HEIGHT))
	add_child(label)

	var bright := UiSkin.mc_color(BOSS_BAR_COLOR)
	# 两端的帽固定成「满血时那么大」（4 源列 × 条框宽度 / 182 = 12 px）。
	# ⚠️ 不设它就回到「整张贴图被拉进缩短后的矩形」：帽宽跟着血量缩水，
	#    血量一低条就变成**长方形**（用户报的「回退到没有圆边」）。
	var cap := UiSkin.mc_bar_cap_px(BOSS_BAR_WIDTH)

	var bar := ProgressBar.new()
	bar.name = "BossBar%d" % index
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 1.0
	bar.show_percentage = false
	# ⚠️ 贴图是 182×5 的像素画，放大 3 倍必须 NEAREST，不然五行会被插值糊成一条渐变。
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bar.add_theme_stylebox_override("background", UiSkin.mc_bar_style(bright, false, cap))
	bar.add_theme_stylebox_override("fill", UiSkin.mc_bar_style(bright, true, cap))
	_place_centered(bar, Rect2(-BOSS_BAR_WIDTH * 0.5, top,
		BOSS_BAR_WIDTH, BOSS_BAR_HEIGHT))
	add_child(bar)

	_boss_rows.append({"name": label, "bar": bar, "title": title})


func _on_boss_health(current: float, maximum: float, index: int) -> void:
	if index < 0 or index >= _boss_rows.size():
		return
	var bar: ProgressBar = _boss_rows[index]["bar"]
	# MC 的名字行**只有名字、不带数字**（血量靠条的长度看），所以这里只动条。
	# ⚠️ 自检那边也相应改成直接对 Boss 的真实 `health` 比，不再从文本里抠数字。
	bar.value = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)


# --- 左上角：泼溅加载状态 -----------------------------------------------------

func bind_splat(splat: SplatScene) -> void:
	if splat == null:
		return
	bind_splats([splat])


## 左上角的泼溅状态组。**一份场地一行**，自上而下按传入顺序排。
## 加「画室609」那一轮场上变成两份泼溅（校园 615 万 + 画室 277 万），所以从
## 单行改成一组 —— 两份同时解码时能分清是哪一份在等、哪一份已经就绪。
func bind_splats(splats: Array) -> void:
	# 先把上一次的标签和连线都撤掉。
	# ⚠️ 不撤会报 "Signal 'progress' is already connected to given callable"：
	#    `.bind(0)` 两次得到的 Callable 是**相等**的，Godot 认为是同一个回调。
	#    （自检里先绑一份、再绑两份就会撞上；玩家侧虽然只绑一次，但接口得能重入。）
	for row in _splat_rows:
		var old: Label = row["label"]
		if is_instance_valid(old):
			old.queue_free()
		# ⚠️ 这里必须用 Variant 接：场地已经被 free 掉时，`var x: SplatScene = row["splat"]`
		#    这句本身就会报 "Trying to assign invalid previously freed instance"。
		var old_splat: Variant = row["splat"]
		if is_instance_valid(old_splat):
			_unbind_splat(old_splat as SplatScene, int(row["index"]))
	_splat_rows.clear()
	var index := 0
	for item in splats:
		var splat := item as SplatScene
		if splat == null:
			continue
		var label := Label.new()
		label.name = "SplatStatus%d" % index
		# ⚠️ 行距必须**正好**是 SPLAT_ROW_HEIGHT：`_verify_room.gd` 直接断言
		#    `row1.position.y - row0.position.y == 20.0`。
		label.position = Vector2(18, SPLAT_ROW_TOP + index * SPLAT_ROW_HEIGHT)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.86, 0.91, 1.0, 0.92))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.visible = false
		add_child(label)
		_splat_rows.append({
			"label": label,
			"splat": splat,
			"index": index,
			"title": "%s泼溅" % splat.display_name,
			"done": false,
		})
		# ⚠️ 信号参数是 (phase, done, total) / (info) / (message)，bind 是**追加**
		#    在最后，所以下面三个 handler 的**行号参数写在形参表末尾**。
		splat.progress.connect(_on_splat_progress.bind(index))
		splat.loaded.connect(_on_splat_loaded.bind(index))
		splat.failed.connect(_on_splat_failed.bind(index))
		index += 1


func _unbind_splat(splat: SplatScene, index: int) -> void:
	var pairs := [
		[splat.progress, _on_splat_progress.bind(index)],
		[splat.loaded, _on_splat_loaded.bind(index)],
		[splat.failed, _on_splat_failed.bind(index)],
	]
	for pair in pairs:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


## 取第 index 行；越界（场地被 --venue 跳过时信号不会来，但保险）返回空字典
func _splat_row(index: int) -> Dictionary:
	if index < 0 or index >= _splat_rows.size():
		return {}
	return _splat_rows[index]


func _on_splat_progress(phase: String, done: int, total: int, index: int) -> void:
	var row := _splat_row(index)
	if row.is_empty() or bool(row["done"]):
		return
	var label: Label = row["label"]
	if not is_instance_valid(label):
		return
	label.visible = true
	var ratio := 0.0 if total <= 0 else clampf(float(done) / float(total), 0.0, 1.0)
	label.text = "%s：%s… %d%%（%s / %s 点）" % [
		row["title"], SPLAT_PHASE.get(phase, phase), int(ratio * 100.0),
		_fmt_int(done), _fmt_int(total)]


func _on_splat_loaded(info: Dictionary, index: int) -> void:
	var row := _splat_row(index)
	if row.is_empty():
		return
	row["done"] = true
	var label: Label = row["label"]
	if not is_instance_valid(label):
		return
	label.visible = true
	label.text = "%s：就绪　%s 点　%.1f s（缓存 %s）" % [
		row["title"],
		_fmt_int(int(info.get("point_count", 0))),
		float(info.get("elapsed", 0.0)),
		"命中" if bool(info.get("from_cache", false)) else "首次解码"]
	# ⚠️ 闭包只捕获**行号**，不要捕获 Label 节点：重绑时旧标签会被 queue_free，
	#    8 秒后定时器触发会报 "Lambda capture at index 0 was freed"。
	#    （正常玩只绑一次，但自检会重绑，日志要干净。）
	get_tree().create_timer(8.0).timeout.connect(func() -> void:
		var row2 := _splat_row(index)
		if row2.is_empty():
			return
		var l2: Label = row2["label"]
		if is_instance_valid(l2):
			l2.visible = false)


func _on_splat_failed(message: String, index: int) -> void:
	var row := _splat_row(index)
	if row.is_empty():
		return
	row["done"] = true
	var label: Label = row["label"]
	if not is_instance_valid(label):
		return
	label.visible = true
	label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	label.text = "%s：失败　%s" % [row["title"], message]


static func _fmt_int(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func bind(player: Player, weapon: Weapon) -> void:
	_player = player
	_weapon = weapon
	weapon.ammo_changed.connect(_on_ammo)
	weapon.reload_started.connect(func() -> void: reload_trough.visible = true)
	weapon.reload_finished.connect(func() -> void: reload_trough.visible = false)
	_on_ammo(weapon.current_ammo, weapon.magazine_size)
	reload_trough.visible = false

	# 玩家的血量走信号，不在 _process 里每帧读 —— 血条只在掉血/回血时变。
	if not player.health_changed.is_connected(_on_player_health):
		player.health_changed.connect(_on_player_health)
	_on_player_health(player.health, player.max_health)


func _on_ammo(current: int, maximum: int) -> void:
	ammo.text = "%d / %d" % [current, maximum]
	ammo.modulate = Color(1, 0.45, 0.4) if current == 0 else Color.WHITE


## 把准星摆到「中心落在整数物理像素、厚度为偶数物理像素」的位置上。
##
## 见 CROSS_DOT_PX 上方那段注释。`_spread` 仍然按**逻辑单位**给（保持原来的手感），
## 只有厚度与臂长按物理像素换算。
func _layout_crosshair() -> void:
	var vp := get_viewport()
	if vp == null or crosshair == null:
		return
	var xf := vp.get_final_transform()
	var scale := maxf(xf.get_scale().x, 0.0001)
	var canvas := vp.get_visible_rect().size

	# 1) 准星原点吸附到整数物理像素 —— 对齐的关键就在这一步
	var center_px := (xf * (canvas * 0.5)).round()
	var d := xf.affine_inverse() * center_px - canvas * 0.5
	crosshair.offset_left = d.x
	crosshair.offset_right = d.x
	crosshair.offset_top = d.y
	crosshair.offset_bottom = d.y

	# 2) 厚度与中心点尺寸按物理像素给，÷scale 换算回逻辑坐标
	var hd := CROSS_DOT_PX * 0.5 / scale
	dot.offset_left = -hd
	dot.offset_right = hd
	dot.offset_top = -hd
	dot.offset_bottom = hd
	var ht := CROSS_THICK_PX * 0.5 / scale
	for c in [t, b]:
		c.offset_left = -ht
		c.offset_right = ht
	for c in [l, r]:
		c.offset_top = -ht
		c.offset_bottom = ht

	# 3) 扩散量仍是逻辑单位，臂长按物理像素
	var gap := _spread
	var arm := CROSS_ARM_PX / scale
	t.offset_top = -gap - arm
	t.offset_bottom = -gap
	b.offset_top = gap
	b.offset_bottom = gap + arm
	l.offset_left = -gap - arm
	l.offset_right = -gap
	r.offset_left = gap
	r.offset_right = gap + arm


## 当前「画布逻辑单位 → 物理像素」的缩放。探针/自检拿它判断对齐。
func crosshair_scale() -> float:
	var vp := get_viewport()
	return 1.0 if vp == null else maxf(vp.get_final_transform().get_scale().x, 0.0001)


## 每个准星元素**落在物理像素上的矩形** —— 供探针验证「中心点与十字条是否严格对称」。
func crosshair_physical_rects() -> Dictionary:
	var vp := get_viewport()
	if vp == null:
		return {}
	var xf := vp.get_final_transform()
	var out := {}
	for pair in [["Dot", dot], ["T", t], ["B", b], ["L", l], ["R", r]]:
		var c: Control = pair[1]
		if c == null:
			continue
		var gr := c.get_global_rect()
		var p0 := xf * gr.position
		var p1 := xf * (gr.position + gr.size)
		out[String(pair[0])] = Rect2(p0, p1 - p0)
	return out


func _process(_delta: float) -> void:
	if _player == null:
		return

	# 准星随瞄准收拢、随移动扩散（尺寸落地见 _layout_crosshair）
	var moving := Vector2(_player.velocity.x, _player.velocity.z).length()
	var target := 3.0 if _player.aiming else 7.5 + moving * 1.6
	_spread = lerpf(_spread, target, 0.18)
	_layout_crosshair()
	dot.modulate = Color(1, 1, 1, 0.95 if _player.aiming else 0.8)

	if _weapon:
		reload_bar.value = _weapon.reload_progress()

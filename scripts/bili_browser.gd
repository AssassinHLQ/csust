class_name BiliBrowser
extends Control
## 小屋电脑里的**假 B 站**（纯本地、零依赖、不联网、不执行任何东西）。
##
## 用户 2026-11-12：「终端敲 bilibili → 打开游戏内的 B 站风格窗口：顶栏 / 搜索框 /
## 视频封面网格 / 能点开一个「播放页」，有进度条、弹幕飘过。纯本地、零依赖，
## 跟「假 OS」的设定完全一致」，并给了参考页 `space.bilibili.com/492361356`
## （UP 主空间：头像 + 资料 + 分栏 + 投稿网格）。
##
## ── 为什么不真做浏览器 ──
## Godot 没有内置 webview；真要跑真 B 站得塞 CEF/WebView 原生插件 + 联网。
## 而这个屋子里的电脑本来就是「假 Arch」，终端开机横幅写着
## "commands are fake, nothing is executed" —— 这里沿着同一个设定做**假页面**。
##
## ── 页面结构 ──
##   ① `space`   UP 主空间：顶栏（logo＋搜索框）→ 横幅＋头像＋资料＋关注按钮
##              → 分栏（主页/视频/动态/收藏/追番）→ 投稿 6 格网格 → 底部操作提示
##   ② `player` 播放页：播放器（进度条/时间/暂停）＋ 弹幕从右往左飘 ＋ 标题/UP/三连
##              ＋ 推荐列表
##
## ── 为什么全部用键盘，不用鼠标 ──
## 这个界面渲染在 `SubViewport` 里（同时贴到桌上的显示器和全屏覆盖层两处，
## 见 `hut_computer.gd`），`handle_input_locally = false`，鼠标事件不往这里送。
## 键盘是现成的通道（`hut_computer._input()` 一直在把按键转给终端），
## 所以这里沿用：方向键选、Enter 打开、Esc 返回。**不用改输入架构**。
##
## ── 字体 ──
## 用 `assets/ui/font.ttf`（终端也是它），**支持中文** ——
## 终端那边是「8 px 字格逐字画」所以塞不下汉字（见 `arch_terminal.gd` 的说明），
## 但这里是正常排版，中文随便用。

## 用户按 Esc 退出到终端（由 `hut_computer.gd` 接）
signal close_requested

# ── 配色（B 站粉 + 蓝）─────────────────────────────────────────────────────
const C_BG := Color(0.071, 0.078, 0.094)
const C_BAR := Color(0.098, 0.106, 0.125)
const C_CARD := Color(0.129, 0.141, 0.165)
const C_CARD_SEL := Color(0.180, 0.196, 0.227)
const C_LINE := Color(0.20, 0.22, 0.26)
const C_TEXT := Color(0.90, 0.92, 0.95)
const C_DIM := Color(0.55, 0.58, 0.64)
const C_PINK := Color(0.98, 0.44, 0.62)
const C_BLUE := Color(0.27, 0.72, 0.94)

# ── 布局（SubViewport 是 832×664）───────────────────────────────────────────
const PAD := 24.0
const BAR_H := 46.0
const HEAD_H := 104.0
const TABS_H := 34.0
const COLS := 3
const GAP := 16.0
const FOOT_H := 26.0

## UP 主空间资料
const SPACE := {
	"name": "爱丽丝",
	"handle": "Arisu_Alice",
	"sign": "千禧年科技学院 · 游戏开发部｜「勇者」的日常记录",
	"uid": "492361356",
	"follow": "128.4万",
	"fans": "56.7万",
	"likes": "1123.9万",
	"level": "Lv6",
	"banner": [Color(0.36, 0.28, 0.62), Color(0.98, 0.44, 0.62)],
}

## 投稿（6 条）。`cover` 是封面的两个渐变色，`dur` 是时长角标。
const VIDEOS := [
	{"t": "【爱丽丝】第一次用RTX5090装机，结果……",
		"up": "爱丽丝", "play": "312.4万", "danmu": "4.2万",
		"dur": "12:34", "cover": [Color(0.20, 0.32, 0.62), Color(0.55, 0.75, 0.98)]},
	{"t": "勇者の日常：从千禧年跑到阿比多斯只用了一节课",
		"up": "爱丽丝", "play": "188.9万", "danmu": "2.1万",
		"dur": "08:07", "cover": [Color(0.62, 0.26, 0.42), Color(0.98, 0.62, 0.75)]},
	{"t": "【手搓】用一个假 Arch 终端骗过了全社团",
		"up": "爱丽丝", "play": "421.7万", "danmu": "6.8万",
		"dur": "15:52", "cover": [Color(0.10, 0.30, 0.30), Color(0.30, 0.85, 0.72)]},
	{"t": "光坂越野跑 150 米高处是什么景色？带你看",
		"up": "爱丽丝", "play": "96.3万", "danmu": "9123",
		"dur": "05:19", "cover": [Color(0.30, 0.20, 0.55), Color(0.72, 0.45, 0.95)]},
	{"t": "把游戏开发部装修成电竞房，预算三万够吗",
		"up": "爱丽丝", "play": "254.1万", "danmu": "3.5万",
		"dur": "18:41", "cover": [Color(0.50, 0.34, 0.12), Color(0.98, 0.78, 0.36)]},
	{"t": "【攻略】霸王龙优香 无伤打法（含机甲形态）",
		"up": "爱丽丝", "play": "533.6万", "danmu": "8.9万",
		"dur": "22:03", "cover": [Color(0.42, 0.16, 0.18), Color(0.92, 0.42, 0.36)]},
]

## 弹幕池（播放页从里面随机取）
const DANMAKU_POOL := [
	"前方高能", "awsl", "这也能赢？", "爱丽丝天下第一", "勇者大人！",
	"打卡", "笑死", "1.0x 循环", "妈妈我看到机甲了", "这显卡能借我玩玩吗",
	"千禧年最强战力", "UP 主好强", "第一次见这么干净的画质", "弹幕护体",
	"这波操作满分", "三连了", "终于等到更新", "看完心情很好",
]

const FONT_PATH := "res://assets/ui/font.ttf"
const FS := 14                       # 正文字号
const FS_SMALL := 12
const FS_TITLE := 16
const FS_BIG := 22

var _page := "space"                 # space / player
var _sel := 0                        # 当前选中的投稿下标
var _open_idx := 0                   # 播放页正在放的那条
var _playing := true
var _t := 0.0                        # 播放进度（秒）
var _danmaku: Array = []             # {text, x, lane, speed, color}
var _dan_spawn := 0.0
var _blink := 0.0

var _font: Font
var _sb_card: StyleBoxFlat
var _sb_card_sel: StyleBoxFlat
var _sb_bar_el: StyleBoxFlat
var _sb_search: StyleBoxFlat
var _sb_thumb: StyleBoxFlat
var _sb_prog_bg: StyleBoxFlat
var _sb_prog: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _pick_font()
	_build_styles()
	set_process(false)
	visible = false


func _pick_font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var f := load(FONT_PATH) as Font
		if f != null:
			return f
	return ThemeDB.fallback_font


## StyleBox 只建一次 —— 每帧 `_draw` 里新建会白白分配几百个对象
func _build_styles() -> void:
	_sb_card = StyleBoxFlat.new()
	_sb_card.bg_color = C_CARD
	_sb_card.set_corner_radius_all(8)

	_sb_card_sel = StyleBoxFlat.new()
	_sb_card_sel.bg_color = C_CARD_SEL
	_sb_card_sel.set_corner_radius_all(8)
	_sb_card_sel.set_border_width_all(2)
	_sb_card_sel.border_color = C_PINK

	_sb_bar_el = StyleBoxFlat.new()
	_sb_bar_el.bg_color = C_CARD
	_sb_bar_el.set_corner_radius_all(14)

	_sb_search = StyleBoxFlat.new()
	_sb_search.bg_color = Color(1, 1, 1, 0.10)
	_sb_search.set_corner_radius_all(14)

	_sb_thumb = StyleBoxFlat.new()
	_sb_thumb.set_corner_radius_all(6)

	_sb_prog_bg = StyleBoxFlat.new()
	_sb_prog_bg.bg_color = Color(1, 1, 1, 0.18)
	_sb_prog_bg.set_corner_radius_all(2)

	_sb_prog = StyleBoxFlat.new()
	_sb_prog.bg_color = C_PINK
	_sb_prog.set_corner_radius_all(2)


# ── 对外 ──────────────────────────────────────────────────────────────────────

func open() -> void:
	_page = "space"
	_sel = 0
	_danmaku.clear()
	visible = true
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)
	_danmaku.clear()


func page_name() -> String:
	return _page


func feed(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	match k.keycode:
		KEY_ESCAPE:
			if _page == "player":
				_page = "space"
				_danmaku.clear()
				queue_redraw()
			else:
				close_requested.emit()
			return true
		KEY_BACKSPACE:
			if _page == "player":
				_page = "space"
				_danmaku.clear()
				queue_redraw()
				return true
			return false
		KEY_ENTER, KEY_KP_ENTER:
			if _page == "space":
				_open_idx = _sel
				_page = "player"
				_t = 0.0
				_playing = true
				_danmaku.clear()
				queue_redraw()
			return true
		KEY_SPACE:
			if _page == "player":
				_playing = not _playing
				queue_redraw()
				return true
			return false
		KEY_LEFT:
			if _page == "space":
				_sel = maxi(_sel - 1, 0)
				queue_redraw()
			return true
		KEY_RIGHT:
			if _page == "space":
				_sel = mini(_sel + 1, VIDEOS.size() - 1)
				queue_redraw()
			return true
		KEY_UP:
			if _page == "space":
				_sel = maxi(_sel - COLS, 0)
				queue_redraw()
			return true
		KEY_DOWN:
			if _page == "space":
				_sel = mini(_sel + COLS, VIDEOS.size() - 1)
				queue_redraw()
			return true
	return true


# ── 每帧 ──────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_blink += delta
	if _page == "player":
		if _playing:
			_t += delta
			_dan_spawn -= delta
			if _dan_spawn <= 0.0:
				_dan_spawn = randf_range(0.35, 0.9)
				_spawn_danmaku()
		for d in _danmaku:
			d["x"] = float(d["x"]) - float(d["speed"]) * delta
		# 飘出播放器左边就回收（不是飘出整屏才回收）
		var left_edge := _player_rect().position.x - 260.0
		var keep: Array = []
		for d in _danmaku:
			if float(d["x"]) > left_edge:
				keep.append(d)
		_danmaku = keep
	queue_redraw()


func _spawn_danmaku() -> void:
	# 弹幕只在**播放器矩形**里飞。第一版用整屏 `size.x` 起手、也不裁，
	# 结果弹幕飞到播放器右边的黑边上了（出图能看到「勇者大人」飘在页面外）。
	var pr := _player_rect()
	var lanes_px := pr.size.y * 0.55
	var cols := [Color(1, 1, 1), Color(1, 0.85, 0.9), Color(0.8, 0.92, 1),
		Color(1, 0.95, 0.7)]
	_danmaku.append({
		"text": DANMAKU_POOL[randi() % DANMAKU_POOL.size()],
		"x": pr.end.x - 8.0,
		"y": pr.position.y + 38.0
			+ fmod(float(randi() % 10000) / 10000.0, 1.0) * lanes_px,
		"speed": randf_range(85.0, 165.0),
		"color": cols[randi() % cols.size()],
	})


## 播放器矩形（`_draw_player()` 和弹幕共用，别各算一份）
func _player_rect() -> Rect2:
	var pw := size.x - PAD * 2.0
	var ph := pw * 9.0 / 16.0
	if ph > size.y * 0.56:
		ph = size.y * 0.56
		pw = ph * 16.0 / 9.0
	return Rect2((size.x - pw) * 0.5, BAR_H + 8.0, pw, ph)


# ── 画 ────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	_draw_top_bar()
	if _page == "space":
		_draw_space()
	else:
		_draw_player()


func _text(pos: Vector2, s: String, fs: int, col: Color,
		width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(_font, pos, s, align, width, fs, col)


## 一行「文字 + 右边数字」的组合
func _draw_top_bar() -> void:
	draw_rect(Rect2(0, 0, size.x, BAR_H), C_BAR)
	draw_rect(Rect2(0, BAR_H - 1.0, size.x, 1.0), C_LINE)

	# logo：粉色圆角块 + 字
	var lb := Rect2(PAD, BAR_H * 0.5 - 11.0, 22.0, 22.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PINK
	sb.set_corner_radius_all(6)
	draw_style_box(sb, lb)
	_text(Vector2(lb.position.x + 5.0, lb.position.y + 16.0), "b", 17, Color.WHITE)
	_text(Vector2(lb.end.x + 8.0, BAR_H * 0.5 + 6.0), "bilibili", 18, C_PINK)

	# 搜索框
	var sx := 168.0
	var sw := 300.0
	var sr := Rect2(sx, BAR_H * 0.5 - 14.0, sw, 28.0)
	draw_style_box(_sb_search, sr)
	_text(Vector2(sr.position.x + 14.0, sr.position.y + 18.5), "搜索视频、UP主", FS_SMALL, C_DIM)
	var go := Rect2(sr.end.x - 58.0, sr.position.y + 3.0, 54.0, 22.0)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = C_BLUE
	sb2.set_corner_radius_all(12)
	draw_style_box(sb2, go)
	_text(Vector2(go.position.x + 15.0, go.position.y + 15.5), "搜索", FS_SMALL, Color.WHITE)

	# 右侧：头像 + 等级
	var av := Vector2(size.x - PAD - 16.0, BAR_H * 0.5)
	draw_circle(av, 13.0, Color(0.42, 0.36, 0.72))
	_text(Vector2(av.x - 6.0, av.y + 5.0), "爱", FS_SMALL, Color.WHITE)
	_text(Vector2(av.x - 96.0, av.y + 5.0), String(SPACE["level"]), FS_SMALL, C_PINK)


# ── ① UP 主空间 ───────────────────────────────────────────────────────────────

func _draw_space() -> void:
	var y := BAR_H

	# 横幅（渐变：用若干条竖线模拟）
	var bh := 64.0
	var c0: Color = SPACE["banner"][0]
	var c1: Color = SPACE["banner"][1]
	var steps := 32
	for i in steps:
		var f := float(i) / float(steps - 1)
		draw_rect(Rect2(PAD + (size.x - PAD * 2.0) * f, y + 8.0,
			(size.x - PAD * 2.0) / float(steps) + 1.0, bh), c0.lerp(c1, f))

	# 头像（压在横幅下沿）
	var ac := Vector2(PAD + 56.0, y + 8.0 + bh - 6.0)
	draw_circle(ac, 34.0, C_BG)
	draw_circle(ac, 31.0, Color(0.42, 0.36, 0.72))
	_text(Vector2(ac.x - 11.0, ac.y + 9.0), "爱", 22, Color.WHITE)

	# 名字 / 签名 / 数据
	var nx := ac.x + 52.0
	_text(Vector2(nx, y + 52.0), String(SPACE["name"]), FS_BIG, C_TEXT)
	_text(Vector2(nx + 74.0, y + 50.0), "UID " + String(SPACE["uid"]), FS_SMALL, C_DIM)
	_text(Vector2(nx, y + 74.0), String(SPACE["sign"]), FS_SMALL, C_DIM)

	var stx := size.x - PAD - 300.0
	_text(Vector2(stx, y + 52.0), "关注", FS_BIG - 4, C_TEXT)
	_text(Vector2(stx + 44.0, y + 52.0), String(SPACE["follow"]), FS_TITLE, C_TEXT)
	_text(Vector2(stx + 128.0, y + 52.0), "粉丝", FS_BIG - 4, C_DIM)
	_text(Vector2(stx + 172.0, y + 52.0), String(SPACE["fans"]), FS_TITLE, C_TEXT)

	# 关注按钮
	var fb := Rect2(size.x - PAD - 76.0, y + 62.0, 76.0, 26.0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PINK
	sb.set_corner_radius_all(13)
	draw_style_box(sb, fb)
	_text(Vector2(fb.position.x + 22.0, fb.position.y + 18.0), "已关注", FS_SMALL, Color.WHITE)

	y += HEAD_H

	# 分栏
	draw_rect(Rect2(0, y, size.x, TABS_H), C_BG)
	draw_rect(Rect2(0, y + TABS_H - 1.0, size.x, 1.0), C_LINE)
	var tabs := ["主页", "视频", "动态", "收藏", "追番"]
	var tx := PAD
	for i in tabs.size():
		var on := i == 1                       # 当前停在「视频」
		_text(Vector2(tx, y + 22.0), tabs[i], FS_TITLE, C_PINK if on else C_DIM)
		if on:
			draw_rect(Rect2(tx + 2.0, y + TABS_H - 3.0, 28.0, 3.0), C_PINK)
		tx += 74.0
	_text(Vector2(size.x - PAD - 150.0, y + 22.0), "共 6 个投稿", FS_SMALL, C_DIM)

	y += TABS_H + 12.0

	# 投稿网格
	#
	# ⚠️ 卡片高度**按剩余空间算**，不能写死。第一版写死 148，而封面是
	#    `cw × 9/16 ≈ 141` 高，加上内边距就已经超出卡片 —— 标题和播放量直接被画到
	#    卡片外面、压到下一行封面上（第一版出图就是一片糊）。
	var cw := (size.x - PAD * 2.0 - GAP * float(COLS - 1)) / float(COLS)
	var rows := int(ceil(float(VIDEOS.size()) / float(COLS)))
	var avail := size.y - FOOT_H - y - 8.0
	var ch := (avail - GAP * float(rows - 1)) / float(rows)
	ch = clampf(ch, 120.0, 220.0)
	for i in VIDEOS.size():
		var col := i % COLS
		var row := i / COLS
		var pos := Vector2(PAD + float(col) * (cw + GAP), y + float(row) * (ch + GAP))
		_draw_card(i, Rect2(pos, Vector2(cw, ch)), i == _sel)

	# 底部提示
	var fy := size.y - FOOT_H
	draw_rect(Rect2(0, fy, size.x, FOOT_H), C_BAR)
	_text(Vector2(PAD, fy + 17.0),
		"方向键选择 · Enter 打开 · Esc 退出浏览器", FS_SMALL, C_DIM)


func _draw_card(i: int, r: Rect2, sel: bool) -> void:
	draw_style_box(_sb_card_sel if sel else _sb_card, r)
	var v: Dictionary = VIDEOS[i]

	# 封面：16:9，但**不许吃掉标题的地盘**（底部留 62 px 给两行标题 + 一行数据）
	var th: float = minf(r.size.x * 9.0 / 16.0, r.size.y - 64.0)
	var tr := Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16.0, th))
	var c0: Color = v["cover"][0]
	var c1: Color = v["cover"][1]
	var steps := 20
	for s in steps:
		var f := float(s) / float(steps - 1)
		draw_rect(Rect2(tr.position.x, tr.position.y + tr.size.y * f,
			tr.size.x, tr.size.y / float(steps) + 1.0), c0.lerp(c1, f))
	# 装饰圆
	draw_circle(tr.position + tr.size * Vector2(0.72, 0.42), tr.size.y * 0.24,
		Color(1, 1, 1, 0.12))
	draw_circle(tr.position + tr.size * Vector2(0.30, 0.66), tr.size.y * 0.15,
		Color(1, 1, 1, 0.10))
	# 播放三角
	var pc := tr.get_center()
	var tri := PackedVector2Array([
		pc + Vector2(-7, -9), pc + Vector2(-7, 9), pc + Vector2(10, 0)])
	draw_colored_polygon(tri, Color(1, 1, 1, 0.82))
	# 时长角标
	var dw := 44.0
	var dr := Rect2(tr.end.x - dw - 6.0, tr.end.y - 20.0, dw, 16.0)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0, 0, 0, 0.62)
	dsb.set_corner_radius_all(3)
	draw_style_box(dsb, dr)
	_text(Vector2(dr.position.x + 7.0, dr.position.y + 12.5), String(v["dur"]),
		FS_SMALL - 1, Color.WHITE)

	# 标题（最多两行，超出用省略号）
	var ty := tr.end.y + 18.0
	var max_chars := maxi(int((r.size.x - 16.0) / float(FS)) + 1, 6)
	var title := String(v["t"])
	var line1 := title.substr(0, mini(max_chars, title.length()))
	_text(Vector2(r.position.x + 8.0, ty), line1, FS, C_TEXT)
	if title.length() > max_chars:
		var line2 := title.substr(max_chars)
		if line2.length() > max_chars:
			line2 = line2.substr(0, max_chars - 1) + "…"
		_text(Vector2(r.position.x + 8.0, ty + 17.0), line2, FS, C_TEXT)

	# 底部：左边 UP 名，右边播放量（**同一行两段右对齐**，不要各画一次整行，
	# 否则会像第一版那样「312.4万播放」压在时长角标上）
	var by := r.end.y - 9.0
	_text(Vector2(r.position.x + 8.0, by), "▸ " + String(v["up"]), FS_SMALL, C_DIM)
	_text(Vector2(r.position.x + 8.0, by), String(v["play"]) + "播放",
		FS_SMALL, C_DIM, r.size.x - 16.0, HORIZONTAL_ALIGNMENT_RIGHT)


# ── ② 播放页 ──────────────────────────────────────────────────────────────────

func _draw_player() -> void:
	var v: Dictionary = VIDEOS[_open_idx]
	var y := BAR_H

	# 播放器区域：占满宽度的大部分，16:9（矩形算法抽到 `_player_rect()`，弹幕共用）
	var pr := _player_rect()

	# 「画面」：封面渐变 + 缓慢移动的光带（假装在动）
	var c0: Color = v["cover"][0]
	var c1: Color = v["cover"][1]
	var steps := 24
	for s in steps:
		var f := float(s) / float(steps - 1)
		draw_rect(Rect2(pr.position.x, pr.position.y + pr.size.y * f,
			pr.size.x, pr.size.y / float(steps) + 1.0), c0.lerp(c1, f) * 0.62)
	# 光带
	var band := fmod(_t * 0.32, 1.4) - 0.2
	draw_rect(Rect2(pr.position.x + pr.size.x * band, pr.position.y,
		pr.size.x * 0.16, pr.size.y), Color(1, 1, 1, 0.06))

	# 左上角小标：明示「画面是假的」，别在中间压大字（会和弹幕打架、也和下方标题重复）
	_text(Vector2(pr.position.x + 12.0, pr.position.y + 20.0),
		"● REC  这是假播放器，画面是画的", FS_SMALL - 1, Color(1, 1, 1, 0.45))

	# 弹幕（只在播放器矩形里；越界的会在 `_process` 里回收）
	for d in _danmaku:
		var dx := float(d["x"])
		if dx + 160.0 < pr.position.x or dx > pr.end.x:
			continue
		_text(Vector2(dx, float(d["y"])), String(d["text"]), FS,
			(Color(d["color"]) as Color))

	# 进度条
	var bar_y := pr.end.y + 12.0
	var bar := Rect2(pr.position.x, bar_y, pr.size.x, 4.0)
	draw_style_box(_sb_prog_bg, bar)
	var total := 12.0 * 60.0 + 34.0                  # 12:34
	var frac: float = clampf(_t / total, 0.0, 1.0)
	draw_style_box(_sb_prog, Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)))
	draw_circle(Vector2(bar.position.x + bar.size.x * frac, bar_y + 2.0), 5.0, C_PINK)

	# 时间
	var cur := int(_t)
	var s1 := "%02d:%02d" % [cur / 60, cur % 60]
	_text(Vector2(pr.position.x, bar_y + 22.0), s1, FS_SMALL, C_TEXT)
	_text(Vector2(pr.position.x, bar_y + 22.0), String(v["dur"]),
		FS_SMALL, C_DIM, pr.size.x, HORIZONTAL_ALIGNMENT_RIGHT)
	# 播放 / 暂停标记
	_text(Vector2(pr.position.x, bar_y + 22.0), ("▶ 播放中" if _playing else "⏸ 已暂停"),
		FS_SMALL, C_PINK, pr.size.x, HORIZONTAL_ALIGNMENT_CENTER)

	# 标题 + 数据
	var iy := bar_y + 48.0
	_text(Vector2(PAD, iy), String(v["t"]), FS_TITLE, C_TEXT)
	var iy2 := iy + 22.0
	_text(Vector2(PAD, iy2), "%s播放 · %s弹幕 · 2026-11-12"
		% [String(v["play"]), String(v["danmu"])], FS_SMALL, C_DIM)

	# 三连按钮
	var bx := size.x - PAD - 240.0
	var labels := ["👍 点赞", "🪙 投币", "⭐ 收藏"]
	for i in labels.size():
		var r := Rect2(bx + float(i) * 82.0, iy2 - 15.0, 74.0, 24.0)
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_CARD
		sb.set_corner_radius_all(12)
		draw_style_box(sb, r)
		_text(Vector2(r.position.x + 10.0, r.position.y + 16.0), labels[i],
			FS_SMALL - 1, C_TEXT)

	# UP 主行
	var uy := iy2 + 34.0
	draw_circle(Vector2(PAD + 15.0, uy - 4.0), 14.0, Color(0.42, 0.36, 0.72))
	_text(Vector2(PAD + 9.0, uy + 1.0), "爱", FS_SMALL, Color.WHITE)
	_text(Vector2(PAD + 38.0, uy), String(SPACE["name"]), FS_TITLE, C_TEXT)
	_text(Vector2(PAD + 38.0, uy + 18.0), String(SPACE["fans"]) + "粉丝",
		FS_SMALL, C_DIM)

	# 弹幕输入框（假的）
	var inr := Rect2(PAD, uy + 30.0, size.x - PAD * 2.0, 26.0)
	draw_style_box(_sb_search, inr)
	_text(Vector2(inr.position.x + 14.0, inr.position.y + 17.5),
		"发个友善的弹幕吧……（这是假的，发不出去）", FS_SMALL, C_DIM)

	# 底部提示
	var fy := size.y - FOOT_H
	draw_rect(Rect2(0, fy, size.x, FOOT_H), C_BAR)
	_text(Vector2(PAD, fy + 17.0),
		"Space 暂停/继续 · Esc 返回列表 · F 退出电脑", FS_SMALL, C_DIM)

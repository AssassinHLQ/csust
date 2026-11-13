class_name ArchWeb
extends Control
## 小屋电脑里的**假浏览器**：地址栏 + archlinux.org 首页。
##
## 用户 2026-11-13：「https://archlinux.org/ 可以加浏览器吗，输入 ARCHLINUX
## 进入浏览器页面的这个网站」。
##
## ── 为什么不真加载 ──
## Godot 没有内置 webview；真要显示真网站得塞 CEF/WebView 原生插件 + 联网，而这个
## 屋子里的电脑本来就叫「假 Arch」（开机横幅写着 "all fake, nothing is executed"）。
## 所以这里和 `bili_browser.gd` 同一套路：**整页是画出来的**，地址栏、导航、新闻
## 都是硬编码的静态内容，一行网络请求都没有。
##
## ── 结构（和真站首页一个样子）──
##   ① 浏览器外壳：前进/后退/刷新按钮 + 地址栏（https://archlinux.org/）
##   ② 站点顶栏：#1793D1 一条，左边 wordmark，右边 Home / Packages / Forums /
##      Wiki / GitLab / Security / AUR
##   ③ hero：「Arch Linux」大字 + 一句话简介 + Download 按钮
##   ④ Latest News：几条带日期的标题
##   ⑤ 快捷入口 pill + 页脚（写明这是画的、没有加载任何东西）
##
## 键位：↑/↓ 或 PageUp/PageDown 滚页面、Esc 关掉回终端。

signal close_requested

# ── Arch 的配色（官方 brand 蓝 #1793D1）+ 浏览器外壳的深色 ──
const C_CHROME := Color(0.11, 0.12, 0.14)
const C_CHROME_LINE := Color(0.22, 0.24, 0.28)
const C_ADDR_BG := Color(0.20, 0.22, 0.26)
const C_PAGE_BG := Color(0.08, 0.085, 0.10)
const C_PAGE_CARD := Color(0.12, 0.13, 0.16)
const C_ARCH := Color(0.090, 0.576, 0.820)      # #1793D1
const C_ARCH_DIM := Color(0.055, 0.36, 0.52)
const C_TEXT := Color(0.90, 0.92, 0.96)
const C_DIM := Color(0.55, 0.60, 0.68)
const C_LINE := Color(0.20, 0.22, 0.26)

## 浏览器外壳高度
const CHROME_H := 46.0
## 页面顶栏（站点自己的导航）
const NAV_H := 52.0

const URL := "https://archlinux.org/"

## 站点导航（假的，点了也不会跳）
const NAV := ["Home", "Packages", "Forums", "Wiki", "GitLab", "Security", "AUR"]

## 首页新闻（措辞是照真站风格写的，日期是编的 —— 这页不联网）
const NEWS := [
	["2026-11-13", "Arch Linux 2026.11.01 image released"],
	["2026-11-08", "linux 6.11.5-arch1-1 is now in [core]"],
	["2026-10-30", "pacman 7.0.0-2: new package signature check defaults"],
	["2026-10-21", "Monthly ISO refresh: the November snapshot is up"],
]

## hero 右边那几个快捷入口
const QUICK := ["Documentation", "Installation guide", "Package search", "AUR"]

var _font: Font
var _cjk: Font
var _scroll := 0.0
var _max_scroll := 0.0
var _sb_addr: StyleBoxFlat
var _sb_card: StyleBoxFlat
var _sb_pill: StyleBoxFlat
var _sb_btn: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _pick_font()
	_cjk = _pick_cjk()
	_build_styles()
	set_process(false)
	visible = false


func _pick_font() -> Font:
	for p in ["res://assets/ui/mono.ttf", "res://assets/ui/LiberationMono-Regular.ttf"]:
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if f != null:
				return f
	if ResourceLoader.exists("res://assets/ui/font.ttf"):
		return load("res://assets/ui/font.ttf") as Font
	return ThemeDB.fallback_font


## 中文用像素字体（`draw_string` 走 shaping，找不到字形会退回系统字体，
## 但显式给一份 CJK 字体更稳、也更像这个项目里的其它界面）
func _pick_cjk() -> Font:
	if ResourceLoader.exists("res://assets/ui/font.ttf"):
		return load("res://assets/ui/font.ttf") as Font
	return _font


func _build_styles() -> void:
	_sb_addr = StyleBoxFlat.new()
	_sb_addr.bg_color = C_ADDR_BG
	_sb_addr.set_corner_radius_all(14)
	_sb_card = StyleBoxFlat.new()
	_sb_card.bg_color = C_PAGE_CARD
	_sb_card.set_corner_radius_all(8)
	_sb_pill = StyleBoxFlat.new()
	_sb_pill.bg_color = Color(1, 1, 1, 0.10)
	_sb_pill.set_corner_radius_all(13)
	_sb_btn = StyleBoxFlat.new()
	_sb_btn.bg_color = C_ARCH
	_sb_btn.set_corner_radius_all(16)


# ── 对外 ──────────────────────────────────────────────────────────────────────

func open() -> void:
	visible = true
	_scroll = 0.0
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)


## 探针用：页面名（这里只有一个页面）
func page_name() -> String:
	return "archlinux"


## 探针用：当前滚动位置
func scroll_offset() -> float:
	return _scroll


func feed(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_scroll_by(-60.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					_scroll_by(60.0)
		return true
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	match k.keycode:
		KEY_ESCAPE:
			close_requested.emit()
		KEY_UP:
			_scroll_by(-44.0)
		KEY_DOWN:
			_scroll_by(44.0)
		KEY_PAGEUP:
			_scroll_by(-(size.y - CHROME_H - 120.0))
		KEY_PAGEDOWN:
			_scroll_by(size.y - CHROME_H - 120.0)
	return true


func _scroll_by(dy: float) -> void:
	_scroll = clampf(_scroll + dy, 0.0, maxf(_max_scroll, 0.0))
	queue_redraw()


# ── 画 ────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_PAGE_BG)
	_draw_chrome()
	# 页面内容整体上下平移（用 canvas 变换比给每个元素加偏移干净）
	draw_set_transform(Vector2(0.0, CHROME_H - _scroll), 0.0, Vector2.ONE)
	var used := _draw_page()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_max_scroll = maxf(used + CHROME_H - size.y, 0.0)
	if _scroll > _max_scroll:
		_scroll = _max_scroll
	# 滚动条：内容超出时右侧画一条细的
	if _max_scroll > 0.0:
		var track_h := size.y - CHROME_H - 24.0
		var frac := track_h / (used + CHROME_H)
		var h := maxf(track_h * frac, 40.0)
		var y := CHROME_H + 12.0 + (track_h - h) * (_scroll / _max_scroll)
		draw_rect(Rect2(size.x - 8.0, y, 4.0, h), Color(C_ARCH, 0.55))


func _draw_chrome() -> void:
	draw_rect(Rect2(0, 0, size.x, CHROME_H), C_CHROME)
	draw_rect(Rect2(0, CHROME_H - 1.0, size.x, 1.0), C_CHROME_LINE)
	# 三个圆按钮：后退 / 前进 / 刷新（假的，点了没反应）
	var bx := 18.0
	for icon in ["<", ">", "R"]:
		draw_circle(Vector2(bx + 12.0, CHROME_H * 0.5), 12.0, Color(1, 1, 1, 0.07))
		_text(Vector2(bx + 7.0, CHROME_H * 0.5 + 5.0), icon, 15, C_TEXT)
		bx += 34.0
	# 地址栏
	var ax := bx + 12.0
	var aw := size.x - ax - 150.0
	var ar := Rect2(ax, CHROME_H * 0.5 - 14.0, aw, 28.0)
	draw_style_box(_sb_addr, ar)
	# 小锁：一个方块 + 一个弧（不画真图标，省得依赖字体）
	var lock_c := Vector2(ar.position.x + 18.0, ar.position.y + 14.0)
	draw_rect(Rect2(lock_c.x - 5.0, lock_c.y - 1.0, 10.0, 9.0), Color(0.55, 0.85, 0.60))
	draw_arc(lock_c + Vector2(0, -2.0), 4.0, PI, TAU, 10, Color(0.55, 0.85, 0.60), 1.5)
	_text(Vector2(ar.position.x + 34.0, ar.position.y + 19.0), URL, 14, C_TEXT)
	# 右侧：这是假浏览器
	_text(Vector2(size.x - 138.0, CHROME_H * 0.5 + 5.0), "offline / fake", 13, C_DIM)


## 画整页，返回**内容总高度**（用来算滚动范围）
func _draw_page() -> float:
	var y := 0.0
	var w := size.x
	# ① 站点顶栏
	draw_rect(Rect2(0, y, w, NAV_H), C_ARCH)
	_text(Vector2(28.0, y + 33.0), "Arch Linux", 22, Color.WHITE)
	var nx := 210.0
	for item in NAV:
		_text(Vector2(nx, y + 32.0), item, 15, Color(1, 1, 1, 0.92))
		nx += 22.0 + 9.0 * float(String(item).length())
	y += NAV_H + 54.0
	# ② hero
	_text(Vector2(56.0, y), "Arch Linux", 46, C_TEXT)
	_text(Vector2(56.0, y + 40.0),
		"A simple, lightweight Linux distribution.", 20, C_ARCH)
	_text(Vector2(56.0, y + 70.0),
		"Nothing here is loaded. This page is drawn by the game.", 15, C_DIM)
	# Download 按钮
	var btn := Rect2(56.0, y + 92.0, 168.0, 38.0)
	draw_style_box(_sb_btn, btn)
	_text(Vector2(btn.position.x + 34.0, btn.position.y + 24.0), "Download  ->", 15,
		Color.WHITE)
	# 右侧三个小卡片（真站首页那一排）
	var cx := w - 470.0
	for i in 3:
		var card := Rect2(cx + float(i) * 150.0, y - 20.0, 138.0, 92.0)
		draw_style_box(_sb_card, card)
		var cap: String = ["Installation", "Package DB", "Mailing lists"][i]
		_text(Vector2(card.position.x + 14.0, card.position.y + 26.0), cap, 14, C_TEXT)
		_text(Vector2(card.position.x + 14.0, card.position.y + 52.0), "--", 13, C_DIM)
		_text(Vector2(card.position.x + 14.0, card.position.y + 72.0), "offline", 12,
			C_ARCH_DIM)
	y += 168.0
	# ③ Latest News
	draw_line(Vector2(56.0, y), Vector2(w - 56.0, y), C_LINE, 1.0)
	_text(Vector2(56.0, y + 30.0), "Latest News", 22, C_TEXT)
	y += 52.0
	for row in NEWS:
		_text(Vector2(56.0, y), String(row[0]), 14, C_ARCH)
		_text(Vector2(160.0, y), String(row[1]), 16, C_TEXT)
		y += 30.0
	y += 16.0
	# ④ 快捷入口 pill
	_text(Vector2(56.0, y), "Quick links", 18, C_TEXT)
	y += 24.0
	var px := 56.0
	for item in QUICK:
		var pw := 22.0 + 9.5 * float(String(item).length())
		var pr := Rect2(px, y - 2.0, pw, 28.0)
		draw_style_box(_sb_pill, pr)
		_text(Vector2(pr.position.x + 11.0, pr.position.y + 19.0), item, 13, C_TEXT)
		px += pw + 10.0
	y += 52.0
	# ⑤ 热门包（真站首页也有 Packages 入口，这里补一段让页面"有东西可看"）
	draw_line(Vector2(56.0, y), Vector2(w - 56.0, y), C_LINE, 1.0)
	_text(Vector2(56.0, y + 30.0), "Packages", 22, C_TEXT)
	y += 52.0
	for row in [
			["pacman", "7.0.0-2", "package manager"],
			["systemd", "256.8-2", "system and service manager"],
			["linux", "6.11.5.arch1-1", "the Linux kernel and modules"],
			["firefox", "132.0.2-1", "standalone web browser"],
			["godot", "4.7.1-1", "multi-platform 2D and 3D game engine"]]:
		_text(Vector2(56.0, y), String(row[0]), 16, C_ARCH)
		_text(Vector2(190.0, y), String(row[1]), 14, C_DIM)
		_text(Vector2(360.0, y), String(row[2]), 14, C_TEXT)
		y += 28.0
	y += 20.0
	# ⑥ 页脚
	draw_line(Vector2(56.0, y), Vector2(w - 56.0, y), C_LINE, 1.0)
	_text(Vector2(56.0, y + 26.0),
		"archlinux.org -- a drawing. no network, nothing is really loaded.", 13, C_DIM)
	_text(Vector2(56.0, y + 48.0), "Esc 退出浏览器 · 方向键 / PgUp PgDn 滚页面", 13, C_DIM)
	return y + 64.0


## 画一行字。汉字走 `_cjk`，西文走 `_font`（等宽）
func _text(pos: Vector2, s: String, fs: int, col: Color) -> void:
	var has_cjk := false
	for i in s.length():
		if _is_cjk(s.unicode_at(i)):
			has_cjk = true
			break
	draw_string(_cjk if has_cjk else _font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _is_cjk(c: int) -> bool:
	return (c >= 0x2E80 and c <= 0xA4CF) or (c >= 0xAC00 and c <= 0xD7A3) \
		or (c >= 0xF900 and c <= 0xFAFF) or (c >= 0xFF00 and c <= 0xFF60)

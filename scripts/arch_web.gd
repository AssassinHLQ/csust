class_name ArchWeb
extends Control
## 小屋电脑里的**假浏览器**：一个能点开的 mini archlinux.org。
##
## 用户 2026-11-13：「https://archlinux.org/ 可以加浏览器吗，输入 ARCHLINUX
## 进入浏览器页面的这个网站」→ 之后追加：「可以滚动点开页面吗，像真正的网站一样」。
##
## ── 为什么不真加载 ──
## Godot 没有内置 webview；真要显示真网站得塞 CEF/WebView 原生插件 + 联网，而这个
## 屋子里的电脑本来就叫「假 Arch」（开机横幅写着 "all fake, nothing is executed"）。
## 所以和 `bili_browser.gd` 同一套路：**整站是画出来的**，一行网络请求都没有。
##
## ── 这一版让它「像真的网站」──
##   · 多页面：首页 / News / Packages / 包详情 / Wiki / 文章 / Download / 几个分区页；
##   · **链接可以点**：导航栏、新闻标题、包名、Quick links、Download 按钮、
##     「← back」都是真链接，鼠标悬停会变色 + 下划线；
##   · 前进 / 后退 / 刷新按钮**真的能用**（维护一条页面历史）；
##   · 地址栏跟着页面变（`https://archlinux.org/packages/` 这样）；
##   · 滚轮 / ↑↓ / PgUp PgDn 滚页面，换页时回到顶部。
##
## ── 鼠标怎么进来 ──
## 终端画面在一个 `SubViewport`（`handle_input_locally = false`）里，GUI 事件进不来，
## 所以由 `hut_computer._input()` 把窗口坐标**换算成画布坐标**（1280×720）后交给
## 本类的 `feed()`。`feed()` 自己维护链接表 + 命中测试，不依赖 Godot 的 GUI 管线。

signal close_requested

# ── 配色（Arch 官方 brand 蓝 #1793D1）+ 浏览器外壳深色 ──
const C_CHROME := Color(0.11, 0.12, 0.14)
const C_CHROME_LINE := Color(0.22, 0.24, 0.28)
const C_ADDR_BG := Color(0.20, 0.22, 0.26)
const C_PAGE_BG := Color(0.08, 0.085, 0.10)
const C_PAGE_CARD := Color(0.12, 0.13, 0.16)
const C_ARCH := Color(0.090, 0.576, 0.820)
const C_ARCH_DIM := Color(0.055, 0.36, 0.52)
const C_TEXT := Color(0.90, 0.92, 0.96)
const C_DIM := Color(0.55, 0.60, 0.68)
const C_LINE := Color(0.20, 0.22, 0.26)
const C_LINK := Color(0.36, 0.72, 0.95)
const C_LINK_HOVER := Color(1.0, 0.85, 0.45)

const CHROME_H := 46.0
const NAV_H := 52.0
const CONTENT_X := 56.0

## 页面 → 地址栏 URL（点进去的时候地址栏会变，像真浏览器）
const URLS := {
	"home": "https://archlinux.org/",
	"news": "https://archlinux.org/news/",
	"packages": "https://archlinux.org/packages/",
	"download": "https://archlinux.org/download/",
	"wiki": "https://wiki.archlinux.org/",
	"docs": "https://wiki.archlinux.org/title/Installation_guide",
	"forums": "https://bbs.archlinux.org/",
	"gitlab": "https://gitlab.archlinux.org/",
	"security": "https://security.archlinux.org/",
	"aur": "https://aur.archlinux.org/",
}

## 站点导航（target 就是页面 id）
const NAV := [
	["Home", "home"], ["Packages", "packages"], ["Forums", "forums"],
	["Wiki", "wiki"], ["GitLab", "gitlab"], ["Security", "security"], ["AUR", "aur"],
]

## 首页新闻：日期 + 标题 + 详情正文
const NEWS := [
	["2026-11-13", "Arch Linux 2026.11.01 image released",
		["The monthly installation image has been refreshed.",
		 "Kernel: 6.11.5, pacman: 7.0.0. Nothing on this page is real."]],
	["2026-11-08", "linux 6.11.5-arch1-1 is now in [core]",
		["A new kernel landed in core. Reboot when convenient.",
		 "(offline demo -- there is no kernel here.)"]],
	["2026-10-30", "pacman 7.0.0-2: new signature check defaults",
		["Package signature verification is stricter by default now.",
		 "Type `pacman -Syu` in the terminal to watch it pretend."]],
	["2026-10-21", "Monthly ISO refresh: the November snapshot is up",
		["The November ISO is out on the mirrors.",
		 "All mirrors are unreachable from this machine, of course."]],
]

## 首页 Quick links
const QUICK := [
	["Documentation", "docs"], ["Installation guide", "docs"],
	["Package search", "packages"], ["AUR", "aur"],
]

## Packages 页的包表：名字 / 版本 / 一句话 / 仓库
const PKGS := [
	["pacman", "7.0.0-2", "package manager", "core"],
	["systemd", "256.8-2", "system and service manager", "core"],
	["linux", "6.11.5.arch1-1", "the Linux kernel and modules", "core"],
	["firefox", "132.0.2-1", "standalone web browser", "extra"],
	["godot", "4.7.1-1", "multi-platform 2D and 3D game engine", "extra"],
	["blender", "4.3.1-2", "3D creation suite", "extra"],
]

## Wiki 首页的文章列表
const WIKI_ARTICLES := [
	["install", "Installation guide"],
	["pacman", "pacman"],
	["kernel", "Kernel"],
	["systemd", "systemd"],
]

var _font: Font
var _cjk: Font
var _page := "home"
var _hist: Array[String] = ["home"]
var _hist_idx := 0
var _scroll := 0.0
var _max_scroll := 0.0
## 命中区：内容坐标（会跟着滚动）与外壳坐标（固定）
var _links: Array = []
var _chrome_links: Array = []
var _hover := ""
var _sb_addr: StyleBoxFlat
var _sb_card: StyleBoxFlat
var _sb_pill: StyleBoxFlat
var _sb_btn: StyleBoxFlat


func _ready() -> void:
	# 鼠标事件由 `hut_computer._input()` 换算坐标后调 `feed()` 送进来，
	# 不依赖 Godot 的 GUI 管线（SubViewport 里根本送不到），所以这里仍然 IGNORE。
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
	_go("home", false)
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)


## 探针用：当前页面 id / 页面名（旧探针用的是 page_name）
func page_name() -> String:
	return _page


func scroll_offset() -> float:
	return _scroll


func can_back() -> bool:
	return _hist_idx > 0


func can_forward() -> bool:
	return _hist_idx < _hist.size() - 1


func address() -> String:
	return _url_for(_page)


## 点一个链接（探针也可以直接调它）
func go(target: String) -> void:
	_go(target, true)


## 输入：鼠标（位置是**画布坐标** 1280×720）+ 键盘
func feed(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed:
			match mb.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_scroll_by(-60.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					_scroll_by(60.0)
				MOUSE_BUTTON_LEFT:
					_click_at(mb.position)
		return true
	var mm := event as InputEventMouseMotion
	if mm != null:
		_hover_at(mm.position)
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
		KEY_BACKSPACE:
			_back()
		KEY_LEFT:
			_back()
		KEY_RIGHT:
			_forward()
	return true


# ── 导航 ──────────────────────────────────────────────────────────────────────

func _go(target: String, record := true) -> void:
	if target.is_empty():
		return
	_page = target
	_scroll = 0.0
	_hover = ""
	if record:
		# 从历史中间点新链接 → 砍掉原来后面的分支（和真浏览器一样）
		while _hist.size() > _hist_idx + 1:
			_hist.remove_at(_hist.size() - 1)
		_hist.append(target)
		_hist_idx = _hist.size() - 1
	queue_redraw()


func _back() -> void:
	if not can_back():
		return
	_hist_idx -= 1
	_page = _hist[_hist_idx]
	_scroll = 0.0
	_hover = ""
	queue_redraw()


func _forward() -> void:
	if not can_forward():
		return
	_hist_idx += 1
	_page = _hist[_hist_idx]
	_scroll = 0.0
	_hover = ""
	queue_redraw()


func _url_for(p: String) -> String:
	if URLS.has(p):
		return String(URLS[p])
	if p.begins_with("pkg:"):
		var n := p.substr(4)
		return "https://archlinux.org/packages/extra/x86_64/%s/" % n
	if p.begins_with("news:"):
		return "https://archlinux.org/news/%s/" % p.substr(5)
	if p.begins_with("art:"):
		return "https://wiki.archlinux.org/title/%s" % p.substr(4)
	return "https://archlinux.org/"


# ── 鼠标命中 ──────────────────────────────────────────────────────────────────

## 内容坐标 = 屏幕坐标去掉外壳、加回滚动量
func _content_pos(screen_pos: Vector2) -> Vector2:
	return screen_pos - Vector2(0.0, CHROME_H - _scroll)


func _click_at(pos: Vector2) -> void:
	# 先看浏览器外壳（后退 / 前进 / 刷新）
	if pos.y < CHROME_H:
		match _hit(_chrome_links, pos):
			"back":
				_back()
			"forward":
				_forward()
			"reload":
				_scroll = 0.0
				queue_redraw()
		return
	# 再点页面内容
	var target := _hit(_links, _content_pos(pos))
	if not target.is_empty():
		_go(target)


func _hover_at(pos: Vector2) -> void:
	var t := ""
	if pos.y < CHROME_H:
		t = _hit(_chrome_links, pos)
	else:
		t = _hit(_links, _content_pos(pos))
	if t != _hover:
		_hover = t
		queue_redraw()


func _hit(table: Array, pos: Vector2) -> String:
	for item in table:
		if (item["rect"] as Rect2).has_point(pos):
			return String(item["target"])
	return ""


# ── 画 ────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	_links.clear()
	_chrome_links.clear()
	draw_rect(Rect2(Vector2.ZERO, size), C_PAGE_BG)
	_draw_chrome()
	draw_set_transform(Vector2(0.0, CHROME_H - _scroll), 0.0, Vector2.ONE)
	var used := _draw_page()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_max_scroll = maxf(used + CHROME_H - size.y, 0.0)
	if _scroll > _max_scroll:
		_scroll = _max_scroll
	if _max_scroll > 0.0:
		var track_h := size.y - CHROME_H - 24.0
		var frac := track_h / (used + CHROME_H)
		var h := maxf(track_h * frac, 40.0)
		var y := CHROME_H + 12.0 + (track_h - h) * (_scroll / _max_scroll)
		draw_rect(Rect2(size.x - 8.0, y, 4.0, h), Color(C_ARCH, 0.55))


func _draw_chrome() -> void:
	draw_rect(Rect2(0, 0, size.x, CHROME_H), C_CHROME)
	draw_rect(Rect2(0, CHROME_H - 1.0, size.x, 1.0), C_CHROME_LINE)
	# 后退 / 前进 / 刷新：**真的能点**
	var bx := 18.0
	var icons := [["<", "back"], [">", "forward"], ["R", "reload"]]
	for item in icons:
		var r := Rect2(bx, CHROME_H * 0.5 - 13.0, 26.0, 26.0)
		var id := String(item[1])
		var enabled := true
		if id == "back":
			enabled = can_back()
		elif id == "forward":
			enabled = can_forward()
		var bg := Color(1, 1, 1, 0.07)
		if _hover == id and enabled:
			bg = Color(C_LINK, 0.35)
		draw_circle(r.get_center(), 13.0, bg)
		_text(Vector2(r.position.x + 8.0, r.position.y + 18.0), String(item[0]), 15,
			C_TEXT if enabled else Color(1, 1, 1, 0.28))
		_chrome_links.append({"rect": r, "target": id})
		bx += 34.0
	# 地址栏（点击 = 回首页，方便探针点）
	var ax := bx + 12.0
	var aw := size.x - ax - 150.0
	var ar := Rect2(ax, CHROME_H * 0.5 - 14.0, aw, 28.0)
	draw_style_box(_sb_addr, ar)
	var lock_c := Vector2(ar.position.x + 18.0, ar.position.y + 14.0)
	draw_rect(Rect2(lock_c.x - 5.0, lock_c.y - 1.0, 10.0, 9.0), Color(0.55, 0.85, 0.60))
	draw_arc(lock_c + Vector2(0, -2.0), 4.0, PI, TAU, 10, Color(0.55, 0.85, 0.60), 1.5)
	_text(Vector2(ar.position.x + 34.0, ar.position.y + 19.0), address(), 14, C_TEXT)
	_chrome_links.append({"rect": ar, "target": "reload"})
	_text(Vector2(size.x - 138.0, CHROME_H * 0.5 + 5.0), "offline / fake", 13, C_DIM)


func _draw_page() -> float:
	match _page:
		"home":
			return _draw_home()
		"news":
			return _draw_news()
		"packages":
			return _draw_packages()
		"download":
			return _draw_download()
		"wiki":
			return _draw_wiki()
		_:
			if _page.begins_with("pkg:"):
				return _draw_pkg(_page.substr(4))
			if _page.begins_with("news:"):
				return _draw_news_item(int(_page.substr(5)))
			if _page.begins_with("art:"):
				return _draw_article(_page.substr(4))
			return _draw_stub(_page)


func _draw_site_nav(y: float) -> float:
	draw_rect(Rect2(0, y, size.x, NAV_H), C_ARCH)
	_text(Vector2(28.0, y + 33.0), "Arch Linux", 22, Color.WHITE)
	var nx := 214.0
	for item in NAV:
		var label := String(item[0])
		var target := String(item[1])
		var w := _width(label, 15)
		var r := Rect2(nx, y + 12.0, w, NAV_H - 20.0)
		var col := Color.WHITE
		if _page == target:
			col = C_LINK_HOVER            # 当前分区高亮
		elif _hover == target:
			col = C_LINK_HOVER
		_text(Vector2(nx, y + 32.0), label, 15, col)
		_links.append({"rect": r, "target": target})
		if _page == target:
			draw_rect(Rect2(nx, y + 38.0, w, 2.0), C_LINK_HOVER)
		nx += w + 26.0
	return y + NAV_H


func _draw_home() -> float:
	var y := _draw_site_nav(0.0) + 54.0
	_text(Vector2(CONTENT_X, y), "Arch Linux", 46, C_TEXT)
	_text(Vector2(CONTENT_X, y + 40.0),
		"A simple, lightweight Linux distribution.", 20, C_ARCH)
	_text(Vector2(CONTENT_X, y + 70.0),
		"Nothing here is loaded. This page is drawn by the game.", 15, C_DIM)
	# Download 按钮（可点）
	var btn := Rect2(CONTENT_X, y + 92.0, 168.0, 38.0)
	draw_style_box(_sb_btn, btn)
	_text(Vector2(btn.position.x + 30.0, btn.position.y + 24.0), "Download  ->", 15,
		Color.WHITE)
	_links.append({"rect": btn, "target": "download"})
	# 右侧三张卡片（可点）
	var cx := size.x - 470.0
	var cards := [["Installation", "docs"], ["Package DB", "packages"],
		["Mailing lists", "forums"]]
	for i in cards.size():
		var card := Rect2(cx + float(i) * 150.0, y - 20.0, 138.0, 92.0)
		draw_style_box(_sb_card, card)
		_text(Vector2(card.position.x + 14.0, card.position.y + 26.0),
			String(cards[i][0]), 14, C_TEXT)
		_link_text(Vector2(card.position.x + 14.0, card.position.y + 56.0), "open ->", 13,
			String(cards[i][1]), Rect2(card.position, card.size))
	y += 168.0
	# Latest News（表头可点 → news 页；每条也点得开）
	draw_line(Vector2(CONTENT_X, y), Vector2(size.x - CONTENT_X, y), C_LINE, 1.0)
	var nw := _width("Latest News", 22)
	_link_text(Vector2(CONTENT_X, y + 30.0), "Latest News", 22, "news",
		Rect2(CONTENT_X, y + 8.0, nw, 30.0))
	_text(Vector2(CONTENT_X + nw + 16.0, y + 30.0), "all news ->", 13, C_DIM)
	y += 52.0
	for i in NEWS.size():
		var date := String(NEWS[i][0])
		var title := String(NEWS[i][1])
		draw_line(Vector2(CONTENT_X, y + 9.0), Vector2(size.x - CONTENT_X, y + 9.0),
			Color(C_LINE, 0.45), 1.0)
		_text(Vector2(CONTENT_X, y), date, 14, C_ARCH)
		var tw := _width(title, 16)
		_link_text(Vector2(160.0, y), title, 16, "news:%d" % i,
			Rect2(158.0, y - 16.0, tw, 24.0))
		y += 30.0
	y += 22.0
	# Quick links
	_text(Vector2(CONTENT_X, y), "Quick links", 18, C_TEXT)
	y += 24.0
	var px := CONTENT_X
	for item in QUICK:
		var label := String(item[0])
		var pw := 22.0 + _width(label, 13)
		var pr := Rect2(px, y - 2.0, pw, 28.0)
		draw_style_box(_sb_pill, pr)
		_link_text(Vector2(pr.position.x + 11.0, pr.position.y + 19.0), label, 13,
			String(item[1]), pr)
		px += pw + 10.0
	y += 56.0
	# Support / Community（真站首页也有这两块；顺便让首页**比一屏长**、能滚）
	draw_line(Vector2(CONTENT_X, y), Vector2(size.x - CONTENT_X, y), C_LINE, 1.0)
	_text(Vector2(CONTENT_X, y + 30.0), "Support Arch Linux", 22, C_TEXT)
	y += 58.0
	for line in ["Arch Linux survives on donations and on people who write docs.",
			"There is no donate button here, because this machine has no network."]:
		_text(Vector2(CONTENT_X, y), String(line), 15, C_DIM)
		y += 24.0
	y += 22.0
	_text(Vector2(CONTENT_X, y), "Community", 22, C_TEXT)
	y += 26.0
	var cx2 := CONTENT_X
	for item in [["Forums", "forums"], ["Wiki", "wiki"], ["GitLab", "gitlab"],
			["AUR", "aur"]]:
		var label := String(item[0])
		var pw2 := 22.0 + _width(label, 13)
		var pr2 := Rect2(cx2, y - 2.0, pw2, 28.0)
		draw_style_box(_sb_pill, pr2)
		_link_text(Vector2(pr2.position.x + 11.0, pr2.position.y + 19.0), label, 13,
			String(item[1]), pr2)
		cx2 += pw2 + 10.0
	y += 62.0
	return _draw_footer(y)


func _draw_news() -> float:
	var y := _draw_site_nav(0.0) + 48.0
	_text(Vector2(CONTENT_X, y), "News", 40, C_TEXT)
	_text(Vector2(CONTENT_X, y + 34.0), "archlinux.org/news/", 13, C_DIM)
	y += 82.0
	for i in NEWS.size():
		var title := String(NEWS[i][1])
		var tw := _width(title, 20)
		_text(Vector2(CONTENT_X, y), String(NEWS[i][0]), 14, C_ARCH)
		_link_text(Vector2(CONTENT_X + 110.0, y), title, 20, "news:%d" % i,
			Rect2(CONTENT_X + 108.0, y - 19.0, tw, 26.0))
		y += 34.0
		_text(Vector2(CONTENT_X + 110.0, y), String(NEWS[i][2][0]), 13, C_DIM)
		y += 40.0
	return _draw_footer(y + 10.0)


func _draw_news_item(i: int) -> float:
	if i < 0 or i >= NEWS.size():
		return _draw_stub("news")
	var y := _draw_site_nav(0.0) + 48.0
	_text(Vector2(CONTENT_X, y), String(NEWS[i][0]), 14, C_ARCH)
	y += 36.0
	_text(Vector2(CONTENT_X, y), String(NEWS[i][1]), 30, C_TEXT)
	y += 46.0
	for line in NEWS[i][2]:
		_text(Vector2(CONTENT_X, y), String(line), 16, C_TEXT)
		y += 26.0
	y += 24.0
	_link_text(Vector2(CONTENT_X, y), "<- back to news", 15, "news",
		Rect2(CONTENT_X, y - 16.0, _width("<- back to news", 15), 24.0))
	return _draw_footer(y + 60.0)


func _draw_packages() -> float:
	var y := _draw_site_nav(0.0) + 48.0
	_text(Vector2(CONTENT_X, y), "Package search", 34, C_TEXT)
	y += 40.0
	# 假的搜索框
	var sr := Rect2(CONTENT_X, y, size.x - CONTENT_X * 2.0, 36.0)
	draw_style_box(_sb_addr, sr)
	_text(Vector2(sr.position.x + 16.0, sr.position.y + 23.0),
		"search packages...   (fake box -- pick one below)", 14, C_DIM)
	y += 68.0
	_text(Vector2(CONTENT_X, y), "name", 13, C_DIM)
	_text(Vector2(CONTENT_X + 180.0, y), "version", 13, C_DIM)
	_text(Vector2(CONTENT_X + 350.0, y), "repo", 13, C_DIM)
	_text(Vector2(CONTENT_X + 430.0, y), "description", 13, C_DIM)
	y += 12.0
	for pkg in PKGS:
		var name := String(pkg[0])
		y += 30.0
		draw_line(Vector2(CONTENT_X, y - 20.0), Vector2(size.x - CONTENT_X, y - 20.0),
			Color(C_LINE, 0.5), 1.0)
		var nw := _width(name, 16)
		_link_text(Vector2(CONTENT_X, y), name, 16, "pkg:%s" % name,
			Rect2(CONTENT_X, y - 16.0, nw, 24.0))
		_text(Vector2(CONTENT_X + 180.0, y), String(pkg[1]), 14, C_TEXT)
		_text(Vector2(CONTENT_X + 350.0, y), String(pkg[3]), 14, C_DIM)
		_text(Vector2(CONTENT_X + 430.0, y), String(pkg[2]), 14, C_TEXT)
	y += 40.0
	return _draw_footer(y)


func _draw_pkg(name: String) -> float:
	var found: Array = []
	for pkg in PKGS:
		if String(pkg[0]) == name:
			found = pkg
	var y := _draw_site_nav(0.0) + 48.0
	if found.is_empty():
		return _draw_stub("pkg:" + name)
	_text(Vector2(CONTENT_X, y), String(found[0]), 34, C_TEXT)
	_text(Vector2(CONTENT_X, y + 26.0), String(found[1]) + "   " + String(found[3]),
		14, C_ARCH)
	y += 66.0
	_text(Vector2(CONTENT_X, y), String(found[2]), 17, C_TEXT)
	y += 34.0
	for line in ["Repository: " + String(found[3]), "Architecture: x86_64",
			"Installed size: 1.2 MiB", "Package file: this package is not really here."]:
		_text(Vector2(CONTENT_X, y), String(line), 15, C_DIM)
		y += 26.0
	y += 26.0
	_link_text(Vector2(CONTENT_X, y), "<- back to packages", 15, "packages",
		Rect2(CONTENT_X, y - 16.0, _width("<- back to packages", 15), 24.0))
	return _draw_footer(y + 60.0)


func _draw_wiki() -> float:
	var y := _draw_site_nav(0.0) + 48.0
	_text(Vector2(CONTENT_X, y), "ArchWiki", 40, C_TEXT)
	_text(Vector2(CONTENT_X, y + 34.0), "wiki.archlinux.org  (offline mirror, fake)",
		13, C_DIM)
	y += 82.0
	for item in WIKI_ARTICLES:
		var label := String(item[1])
		var w := _width(label, 18)
		_link_text(Vector2(CONTENT_X, y), label, 18, "art:" + String(item[0]),
			Rect2(CONTENT_X, y - 18.0, w, 26.0))
		y += 36.0
	return _draw_footer(y + 20.0)


func _draw_article(key: String) -> float:
	var titles := {"install": "Installation guide", "pacman": "pacman",
		"kernel": "Kernel", "systemd": "systemd"}
	var title := String(titles.get(key, key))
	var y := _draw_site_nav(0.0) + 48.0
	_text(Vector2(CONTENT_X, y), "ArchWiki", 14, C_DIM)
	y += 34.0
	_text(Vector2(CONTENT_X, y), title, 34, C_TEXT)
	y += 46.0
	for line in [
			"This article exists only in the game. There is no wiki here.",
			"On a real machine you would read the Installation guide before",
			"formatting a disk. Alice did not do that either."]:
		_text(Vector2(CONTENT_X, y), String(line), 16, C_TEXT)
		y += 26.0
	y += 24.0
	_link_text(Vector2(CONTENT_X, y), "<- back to wiki", 15, "wiki",
		Rect2(CONTENT_X, y - 16.0, _width("<- back to wiki", 15), 24.0))
	return _draw_footer(y + 60.0)


func _draw_download() -> float:
	var y := _draw_site_nav(0.0) + 48.0
	_text(Vector2(CONTENT_X, y), "Download", 40, C_TEXT)
	y += 40.0
	_text(Vector2(CONTENT_X, y), "archlinux-2026.11.01-x86_64.iso   ~1.2 GiB", 16, C_TEXT)
	y += 30.0
	var btn := Rect2(CONTENT_X, y, 220.0, 40.0)
	draw_style_box(_sb_btn, btn)
	_text(Vector2(btn.position.x + 26.0, btn.position.y + 25.0), "Download  ->", 16,
		Color.WHITE)
	y += 76.0
	_text(Vector2(CONTENT_X, y), "Mirrors", 24, C_TEXT)
	y += 32.0
	for m in ["https://mirror.rackspace.com/archlinux/iso/",
			"https://mirrors.kernel.org/archlinux/iso/",
			"https://mirror.0x.sg/archlinux/iso/"]:
		_text(Vector2(CONTENT_X, y), String(m), 15, C_DIM)
		_text(Vector2(size.x - 260.0, y), "unreachable", 13, Color(0.9, 0.45, 0.45))
		y += 28.0
	y += 20.0
	_text(Vector2(CONTENT_X, y), "(offline demo -- there is nothing to download)", 14,
		C_DIM)
	y += 40.0
	_link_text(Vector2(CONTENT_X, y), "<- back to home", 15, "home",
		Rect2(CONTENT_X, y - 16.0, _width("<- back to home", 15), 24.0))
	return _draw_footer(y + 60.0)


## 分区页（Forums / GitLab / Security / AUR…）：一句话 + 回首页链接
func _draw_stub(id: String) -> float:
	var titles := {"forums": "Arch Linux Forums", "gitlab": "Arch Linux GitLab",
		"security": "Arch Linux Security Tracker", "aur": "Arch User Repository",
		"docs": "Documentation"}
	var title := String(titles.get(id, id))
	var y := _draw_site_nav(0.0) + 48.0
	_text(Vector2(CONTENT_X, y), title, 34, C_TEXT)
	y += 46.0
	for line in ["This section is not mirrored on this machine.",
			"Nothing here is fetched -- the whole site is a drawing.",
			"Type `archlinux` in the terminal again to come back."]:
		_text(Vector2(CONTENT_X, y), String(line), 16, C_TEXT)
		y += 26.0
	y += 24.0
	_link_text(Vector2(CONTENT_X, y), "<- back to home", 15, "home",
		Rect2(CONTENT_X, y - 16.0, _width("<- back to home", 15), 24.0))
	y += 50.0
	return _draw_footer(y)


func _draw_footer(y: float) -> float:
	draw_line(Vector2(CONTENT_X, y), Vector2(size.x - CONTENT_X, y), C_LINE, 1.0)
	_text(Vector2(CONTENT_X, y + 26.0),
		"archlinux.org -- a drawing. no network, nothing is really loaded.", 13, C_DIM)
	_text(Vector2(CONTENT_X, y + 48.0),
		"Esc 退出浏览器 · 方向键/PgUp PgDn 滚动 · 点链接开新页", 13, C_DIM)
	return y + 64.0


# ── 文字 / 链接小工具 ─────────────────────────────────────────────────────────

func _text(pos: Vector2, s: String, fs: int, col: Color) -> void:
	draw_string(_font_of(s), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _font_of(s: String) -> Font:
	for i in s.length():
		if _is_cjk(s.unicode_at(i)):
			return _cjk
	return _font


func _width(s: String, fs: int) -> float:
	return _font_of(s).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


## 画一段**可点**的文字，并把 `rect` 记进命中表；返回宽度
func _link_text(pos: Vector2, s: String, fs: int, target: String, rect: Rect2) -> float:
	var hot := (_hover == target)
	var col := C_LINK_HOVER if hot else C_LINK
	_text(pos, s, fs, col)
	if hot:
		draw_line(Vector2(rect.position.x, pos.y + 3.0),
			Vector2(rect.position.x + _width(s, fs), pos.y + 3.0), C_LINK_HOVER, 1.0)
	var r := rect
	# 命中区至少给 26 px 高，别让玩家点不着
	if r.size.y < 26.0:
		r = Rect2(r.position.x, r.position.y - (26.0 - r.size.y) * 0.5, r.size.x, 26.0)
	_links.append({"rect": r, "target": target})
	return _width(s, fs)


func _scroll_by(dy: float) -> void:
	_scroll = clampf(_scroll + dy, 0.0, maxf(_max_scroll, 0.0))
	queue_redraw()


func _is_cjk(c: int) -> bool:
	return (c >= 0x2E80 and c <= 0xA4CF) or (c >= 0xAC00 and c <= 0xD7A3) \
		or (c >= 0xF900 and c <= 0xFAFF) or (c >= 0xFF00 and c <= 0xFF60)

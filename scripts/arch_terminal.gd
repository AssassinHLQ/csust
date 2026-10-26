class_name ArchTerminal
extends Control
## 小屋电脑里的**假 Arch Linux 终端**（游戏道具，不接真实 shell，不 fork 任何进程）。
##
## 用户 2026-10-22：「假终端，这样看还是不下插件了，自己做一个 ARCH LINUX 的界面，
## 虚拟的不需要有真实功能」。
##
## ── 为什么自己「逐字画」，而不是用一个 Label / RichTextLabel 排整行 ──
## 屏幕内容是 neofetch 那张 ASCII 图：Arch logo 19 行 + 右边 19 行信息，
## **列必须严格对齐**。`draw_string()` 把一整行交给字体排版，字宽由字体自己定 ——
## 项目 UI 用的是 `assets/ui/font.ttf`（CJK 字体，西文字宽不等宽），整行一画立刻歪。
## 所以这里按「字符格」画：每个字符的 x 都是 `col * CELL.x` 自己算的，跟字体无关，
## 换成任何字体都不会错位（代价是没法用富文本自动换行，但这个界面本来就不换行）。
##
## ── 上层怎么用（见 `hut_computer.gd`）──
##   · `feed(event)` 收键盘事件（不发 `gui_input`，由电脑自己转发过来）；
##   · `exit_requested` 信号：玩家敲 `exit` 时请求关掉界面；
##   · 同一份画面会被电脑渲染到桌上的显示器（`SubViewport`）和全屏覆盖层两处。

## 玩家敲 `exit` 时发出，由 `hut_computer.gd` 收起来
signal exit_requested
## 玩家第一次敲键（用来把光标切到「有焦点」状态）
signal first_input

const COLS := 100
const ROWS := 40
const CELL := Vector2(8.0, 16.0)
const FONT_SIZE := 13
const MARGIN := Vector2(14.0, 10.0)

const BG := Color(0.043, 0.055, 0.075)
const FG := Color(0.85, 0.88, 0.92)
const DIM := Color(0.45, 0.50, 0.58)
const ARCH_BLUE := Color(0.090, 0.576, 0.820)
const KEY_CYAN := Color(0.255, 0.678, 0.741)
const USER_CYAN := Color(0.400, 0.850, 0.880)
const GOLD := Color(0.950, 0.760, 0.300)
const RED := Color(0.930, 0.400, 0.400)
const GREEN := Color(0.500, 0.900, 0.550)
const CURSOR := Color(0.75, 0.92, 1.0, 0.9)

## neofetch 左边的 Arch logo（原作者 neofetch 的那一份，18 行）
const LOGO := [
	"                   -`                   ",
	"                  .o+`                  ",
	"                 `ooo/                  ",
	"                `+oooo:                 ",
	"               `+oooooo:                ",
	"               -+oooooo+:               ",
	"             `/:-:++oooo+:              ",
	"            `/++++/+++++++:             ",
	"           `/++++++++++++++:            ",
	"          `/+++ooooooooooooo/`          ",
	"         ./ooosssso++osssssso+`         ",
	"        .oossssso-````/ossssss+`        ",
	"       -osssssso.      :ssssssso.       ",
	"      :osssssss/        osssso+++.      ",
	"     /ossssssss/        +ssssooo/-      ",
	"   `/ossssso+/:-        -:/+osssso+-    ",
	"  `+sso+:-`                 `.-/+oso:   ",
	" `++:.                           `-/+/  ",
]

## 右边的 neofetch 信息：`[键, 值]`
## ⚠️ **全英文**。终端是「逐字格」画的：中文字形是 13 px 宽、格子只有 8 px，
##    一个汉字会压掉右边两个字符 —— 第一版打了中文，整段糊成一团（`欢迎使用` 变
##    `欢體用`）。中文提示放到覆盖层的普通 Label 里（那边是正常排版）。
##
## ── 这台机器的配置单（2026-10-26 用户：「这个 u 和内存配这个显卡不是狗骑吕布嘛」）──
## 原来写的是 **Intel i5-4210M + 2258MiB / 7844MiB**，配一张 RTX 5090 ——
## 平台侧把显卡按在地上摩擦。现在按用户点的配置换成**洋垃圾平台**：
##   CPU  = **E5-2698 v2**：12 核 24 线程 @ 2.40GHz（Ivy Bridge-EP，X79 平台）
##   RAM  = **64GiB DDR3-1600 ECC REG**（8 × 8GiB，四通道）
##
## ⚠️ 版本特意挑 **v2**：2698 的 v3 / v4 是 Haswell-EP / Broadwell-EP，**只吃 DDR4**，
##    和「DDR3-1600」凑不到一块儿；v2 这一代才正好是 DDR3 四通道 ECC。
##    （想改成不带版本的「E5-2698」也行 —— 改的就是下面这一行。）
## ⚠️ 顺手**删掉了原来那行 `GPU: Intel 4th Gen Core Processor`**：那是 i5-4210M 的核显，
##    换成至强之后机器上**根本没有核显**（E5 全系不带 iGPU）。留着是硬伤，不是梗。
##
## 这几行就是这台机器的「当前配置」，以后做「爱丽丝赚钱 → 找芹香买配件 → 升级」
## 那条线时改的就是这里：升级一档，neofetch 跟着变一行。
const INFO := [
	["OS", "Arch Linux x86_64"],
	["Host", "Arisu-PC (custom build)"],
	["Kernel", "6.11.5-arch1-1"],
	["Uptime", "9 hours, 11 mins"],
	["Packages", "1524 (pacman)"],
	["Shell", "zsh 5.8"],
	["Resolution", "1920x1080"],
	["DE", "Plasma 5.27.9"],
	["WM", "KWin"],
	["Theme", "Breeze [Plasma], Breeze [GTK2/3]"],
	["Icons", "breeze [Plasma], breeze [GTK2/3]"],
	["Terminal", "konsole"],
	["Terminal Font", "Hack 10"],
	["CPU", "Intel Xeon E5-2698 v2 (24) @ 2.400GHz"],
	["GPU", "NVIDIA GeForce RTX 5090"],
	["Memory", "7892MiB / 64GiB DDR3-1600 ECC"],
]

## logo 的固定列宽 —— ⚠️ `LOGO` 里各行的**尾部空格数不一致**，直接接右边那列会让
## 「CPU: / GPU: / Memory:」这几行整体左右乱跳（第一版就是这样）。统一 rpad 到 42。
const LOGO_WIDTH := 42

const USER := "alice"
const HOST := "arisu"

## 每行：纯文本 + 逐字符颜色
var _text: Array[String] = []
var _cols: Array[PackedColorArray] = []
var _cursor_row := 0
var _cursor_col := 0
## 当前输入行（提示符之后的部分）
var _typing := ""
var _blink := true
var _blink_t := 0.0
var _font: Font


func _ready() -> void:
	_font = _pick_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	reset()


func _pick_font() -> Font:
	for p in ["res://assets/ui/font.ttf", "res://assets/ui_sprout/font.ttf"]:
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if f != null:
				return f
	return ThemeDB.fallback_font


func _process(delta: float) -> void:
	_blink_t += delta
	if _blink_t >= 0.55:
		_blink_t = 0.0
		_blink = not _blink
		queue_redraw()


## 清屏并重新打印开机信息
func reset() -> void:
	_text.clear()
	_cols.clear()
	_typing = ""
	_banner()
	_prompt_line()


func _banner() -> void:
	_push_line([["ArisuOS", USER_CYAN], ["  ·  Arch Linux (fake, for show)", DIM]])
	_push_line([["[F] quit   type ", DIM], ["help", KEY_CYAN],
		["  : commands are fake, nothing is executed", DIM]])
	_push_line([])
	_neofetch()


func _neofetch() -> void:
	_push_line([[("%s@%s" % [USER, HOST]).rpad(28), USER_CYAN]])
	_push_line([["-".repeat(24), DIM]])
	for i in maxi(LOGO.size(), INFO.size()):
		var logo: String = (LOGO[i] if i < LOGO.size() else "").rpad(LOGO_WIDTH)
		var row: Array = [[logo, ARCH_BLUE]]
		if i < INFO.size():
			row.append(["  %-16s" % (String(INFO[i][0]) + ": "), KEY_CYAN])
			row.append([String(INFO[i][1]), FG])
		_push_line(row)
	# 底部那排色块（neofetch 的调色板）：用 `###` 而不是 `███` —— 方块字符是
	# 全角宽，8 px 的格子里放不下，会糊成一大条。
	var swatches := [RED, GREEN, GOLD, ARCH_BLUE, Color(0.6, 0.35, 0.85), KEY_CYAN]
	var bar: Array = [["  ", DIM]]
	for col in swatches:
		bar.append(["###", col])
	_push_line(bar)
	_push_line([])


## 铺一行：segments = [[文字, 颜色], …]
func _push_line(segments: Array) -> void:
	var s := ""
	var c := PackedColorArray()
	for seg in segments:
		var t := String(seg[0])
		var col: Color = seg[1]
		s += t
		for _i in t.length():
			c.append(col)
	# 右侧补空格（画的时候要用长度算光标位置，也顺手把颜色数组补齐）
	if s.length() < COLS:
		var pad := COLS - s.length()
		s += " ".repeat(pad)
		for _i in pad:
			c.append(DIM)
	_text.append(s)
	_cols.append(c)
	_cursor_row = _text.size() - 1
	_cursor_col = s.strip_edges(false, true).length()


func _prompt_line() -> void:
	_typing = ""
	_push_line([[("%s@%s" % [USER, HOST]), GREEN], [":", FG], ["~", ARCH_BLUE],
		["$ ", FG]])
	_cursor_row = _text.size() - 1
	_cursor_col = _text[_cursor_row].strip_edges(false, true).length()
	queue_redraw()


## 重画当前输入行（敲字/退格都走这里，不新开行）
func _rewrite_input() -> void:
	var head := _text.size() - 1
	var base: String = _text[head].substr(0, _cursor_col)
	var row := base + _typing
	if row.length() < COLS:
		row += " ".repeat(COLS - row.length())
	_text[head] = row
	var c := _cols[head]
	# 把输入部分涂成亮色
	for i in _typing.length():
		var at := _cursor_col + i
		if at < c.size():
			c[at] = FG
	_cols[head] = c
	queue_redraw()


# ── 键盘 ──────────────────────────────────────────────────────────────────────

func feed(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return false
	first_input.emit()
	_blink = true
	_blink_t = 0.0
	# Ctrl+U / Ctrl+C 先判 —— 否则 KEY_U 会被下面的 match 吃掉，「u」就打不出来了
	if k.ctrl_pressed and (k.keycode == KEY_U or k.keycode == KEY_C):
		_typing = ""
		_rewrite_input()
		return true
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_submit()
		KEY_BACKSPACE:
			if not _typing.is_empty():
				_typing = _typing.substr(0, _typing.length() - 1)
				_rewrite_input()
		KEY_ESCAPE:
			exit_requested.emit()
		_:
			var ch := String.chr(k.unicode) if k.unicode > 0 else ""
			if ch.length() == 1 and k.unicode >= 32 and k.unicode < 127:
				if _typing.length() < COLS - 12:
					_typing += ch
					_rewrite_input()
	return true


func _submit() -> void:
	var cmd := _typing.strip_edges()
	_rewrite_input()
	_push_line([])
	if not cmd.is_empty():
		_run(cmd)
	_prompt_line()


func _run(cmd: String) -> void:
	var parts := cmd.split(" ", false)
	var name := String(parts[0]).to_lower()
	var arg := cmd.substr(name.length()).strip_edges()
	match name:
		"help":
			_say("commands (all fake, for show only):")
			for k in ["help", "neofetch", "ls", "cat readme.txt", "uname -a",
					"whoami", "pacman -Syu", "df -h", "clear", "exit"]:
				_push_line([["  ", DIM], [k, KEY_CYAN]])
			_push_line([["  ", DIM], ["anything else: zsh: command not found", DIM]])
		"neofetch":
			_neofetch()
		"ls":
			_push_line([["Desktop  ", KEY_CYAN], ["Documents  ", KEY_CYAN],
				["Downloads  ", KEY_CYAN], ["Music  ", KEY_CYAN],
				["Pictures  ", KEY_CYAN], ["readme.txt", GREEN]])
			_push_line([["5090_build.log", DIM], ["  steam", DIM], ["  .zshrc", DIM]])
		"cat":
			if arg.begins_with("readme"):
				_push_line([["# alice's build log", GOLD]])
				_push_line([["the 5090 arrived. clerk said it was the last one.", FG]])
				_push_line([["someone on the parkour route is looking for it too...", FG]])
				_push_line([["-- all of the above is story. this machine is offline.", DIM]])
			else:
				_say("cat: %s: no such file" % arg)
		"uname":
			_push_line([["Linux %s 6.11.5-arch1-1 #1 SMP x86_64 GNU/Linux" % HOST, FG]])
		"whoami":
			_push_line([[USER, FG]])
		"df":
			_push_line([["Filesystem      Size  Used Avail Use% Mounted on", DIM]])
			_push_line([["/dev/nvme0n1p2  1.8T  641G  1.1T  37% /", FG]])
			_push_line([["/dev/nvme1n1p1  1.8T  1.2T  510G  71% /mnt/models", FG]])
		"pacman":
			if arg.contains("-Syu") or arg.contains("-S"):
				_push_line([[":: synchronising package databases...", KEY_CYAN]])
				for pkg in ["linux 6.11.5.arch1-1", "nvidia 565.57.01-1",
						"godot 4.7.1-1", "blender 4.3.1-2"]:
					_push_line([["  upgrading ", DIM], [pkg.rpad(32), FG],
						["[##########] 100%", GREEN]])
				_push_line([[":: all done. reboot to apply.", GREEN]])
			else:
				_say("pacman: invalid option (try pacman -Syu)")
		"sudo":
			if arg.contains("rm"):
				_push_line([["sudo: permission denied -- nice try.", RED]])
			else:
				_push_line([["%s is not in the sudoers file. This incident will be reported."
					% USER, RED]])
		"clear":
			reset()
		"exit", "logout":
			_push_line([["logout", DIM]])
			exit_requested.emit()
		_:
			_push_line([["zsh: command not found: ", RED], [name, FG]])


func _say(line: String) -> void:
	_push_line([[line, FG]])


# ── 画 ────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var f := _font
	var fs := FONT_SIZE
	for r in _text.size():
		var row := _text[r]
		var cols := _cols[r]
		var y := MARGIN.y + float(r + 1) * CELL.y - 4.0
		for c in row.length():
			var ch := row[c]
			if ch == " ":
				continue
			var col := cols[c] if c < cols.size() else FG
			draw_char(f, Vector2(MARGIN.x + float(c) * CELL.x, y), ch, fs, col)
	# 光标：在提示符那一行的输入末尾画一个方块
	if _blink:
		var cx := MARGIN.x + float(_cursor_col + _typing.length()) * CELL.x
		var cy := MARGIN.y + float(_cursor_row) * CELL.y
		draw_rect(Rect2(Vector2(cx, cy + 2.0), Vector2(CELL.x - 1.0, CELL.y - 3.0)),
			CURSOR)


## 探针/自检用：现在屏幕上有几行、最后一行是什么
func line_count() -> int:
	return _text.size()


func last_line() -> String:
	return _text[_text.size() - 1] if not _text.is_empty() else ""


func screen_text() -> String:
	return "\n".join(_text)

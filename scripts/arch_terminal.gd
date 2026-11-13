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
## 玩家敲 `bilibili` 时发出开「假 B 站」窗口（见 `bili_browser.gd`）
##
## ⚠️ 为什么命令名只能用英文：`feed()` 只收 **ASCII 32~126**（见下面那段注释），
##    中文根本打不进来 —— 用户 2026-11-12 在终端里敲「哔哩哔哩」只漏进去
##    `awraa zzcxzsa` 这种拼音字母，就是被这个过滤挡掉的。
##    Godot 在 Windows 上拿不到输入法的候选文字，硬做中文输入不现实，
##    所以这里给几个**英文别名**；中文那个只写在 help 里当注释，敲不进来也无所谓。
signal open_bili_requested
## ⚠️ `arona` / `plana` **没有信号**：她们不再开独立页面，而是**在终端自己的右半屏**
##    显示立绘、台词直接进终端正文流（用户 2026-11-12：「不是新开一个界面，
##    而是直接在 arch 右半部分显现，遮住系统，她的对话也通过终端发送」）。
##    实现在本文件末尾「屏幕里的同伴」一节，入口是 `summon()`。

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
## 汉字用的字体（等宽字体里**没有汉字字形**，必须按字换字体，见 `_draw()`）
var _cjk_font: Font


## 等宽字体候选。**真正等宽的排第一**（用户 2026-11-12：
## 「这个 arch 的字体是不是有一点点乱了」）。
##
## ── 为什么会乱 ──
## 本控件已经在按「字符格」画（每个字的 x = `col * CELL.x`），可**字形本身**
## 还得塞进 8 px 的格子：`assets/ui/font.ttf` 是 Fusion Pixel 的**中文像素字体**，
## 它的西文字宽**不是等宽的**，`i` / `M` / `.` 各自宽度不同，压进同一个格子
## 就会东倒西歪、笔画挤在一起。中文没问题（本来就是方框字）。
## 所以：往 `assets/ui/` 丢一个等宽字体（改名 `mono.ttf`）就能立刻变整齐；
## 没有等宽字体时退回 CJK 字体 —— 中文照常显示，只是西文会略歪。
const MONO_CANDIDATES := [
	"res://assets/ui/mono.ttf",
	"res://assets/ui/LiberationMono-Regular.ttf",
	"res://assets/ui/JetBrainsMono-Regular.ttf",
	"res://assets/ui/DejaVuSansMono.ttf",
]
## 退路：中文像素字体（原来一直在用的那份）
const CJK_CANDIDATES := ["res://assets/ui/font.ttf", "res://assets/ui_sprout/font.ttf"]


func _ready() -> void:
	_font = _pick_font()
	_cjk_font = _pick_cjk_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = &"Master"
	_voice.volume_db = VOICE_DB
	add_child(_voice)
	set_process(true)
	reset()


## 自检 / `hut_computer.gd` 的底部提示行共用这一份选择逻辑。
func terminal_font() -> Font:
	if _font == null:
		_font = _pick_font()
	return _font


func _pick_font() -> Font:
	for p in MONO_CANDIDATES:
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if f != null:
				return f
	for p in CJK_CANDIDATES:
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if f != null:
				return f
	return ThemeDB.fallback_font


## 汉字字体：等宽字体（`mono.ttf`）里**没有 CJK 字形**，
## 所以必须单独找一份中文像素字体，`_draw()` 里按字切换。
##
## ⚠️ 2026-11-13 的坑：`draw_char()` **不会自动走字体回退**（不走 `FontFile.fallbacks`
##    那套 shaping），等宽字体画汉字就是**一片空白**——第一版阿洛娜的台词一屏
##    只剩 `ARONA:` 和几个英文单词（`Magisk` / `htop`），中文全隐形。
##    所以这里是「每个字自己挑字体」，不是让引擎去回退。
func _pick_cjk_font() -> Font:
	for p in CJK_CANDIDATES:
		if ResourceLoader.exists(p):
			var f := load(p) as Font
			if f != null and f != _font:
				return f
	return _font


## 现在用的是不是等宽字体（自检用；false = 退回了中文像素字体，西文会略歪）
func uses_mono_font() -> bool:
	for p in MONO_CANDIDATES:
		if ResourceLoader.exists(p):
			return true
	return false


func _process(delta: float) -> void:
	# 同伴（阿洛娜 / 普拉娜）要逐帧动、还要自己说话 —— 交给那一节处理
	_process_companion(delta)
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
	_stop_voice()
	_banner()
	_prompt_line()


func _banner() -> void:
	_push_line([["ArisuOS", USER_CYAN], ["  ·  Arch Linux (fake, for show)", DIM]])
	# 开机横幅要主动告诉玩家「敲 help 看全部命令」—— 用户 2026-11-12 提的第一诉求。
	# ⚠️ 退出键写 `Esc` 而不是 `F`：**F 已经不能用来退出了**（用户 2026-11-12：
	#    「不能用 F 取消因为输入不了命令」—— F 会抢在终端前面关掉电脑，
	#    导致字母 f 打不进来）。详见 `hut_computer.gd::_input()` 的注释。
	_push_line([["[Esc] quit   ", DIM], ["type help", KEY_CYAN],
		["  to list every command", DIM]])
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
	# 右侧补空格（画的时候要用**显示格数**算光标位置，也顺手把颜色数组补齐）
	#
	# ⚠️ 这里必须用 `_cells(s)` 而不是 `s.length()`：中文一个字占 2 格，
	#    按字符数补会把行撑得比屏幕还宽（也把光标算错位）。
	var w := _cells(s)
	if w < COLS:
		var pad := COLS - w
		s += " ".repeat(pad)
		for _i in pad:
			c.append(DIM)
	_text.append(s)
	_cols.append(c)
	# ── 滚屏 ──
	# 用户 2026-11-12：「输入 help 可以弹出所有可以用的命令」—— 命令一多，
	# 输出就会超出 ROWS（40 行），而这里**没有滚动条**：超出部分直接画到屏幕外，
	# 等于「help 只说了一半」。所以超过 ROWS 就从**顶上**丢掉最旧的，
	# 表现和真终端一致（新内容把旧内容顶上去）。
	while _text.size() > ROWS:
		_text.remove_at(0)
		_cols.remove_at(0)
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
	# 按**显示格数**补空格（中文 2 格）
	var w := _cells(row)
	if w < COLS:
		row += " ".repeat(COLS - w)
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
		# Tab = 「同伴继续说」。Tab 本来也不产生字符，拿去当前进键不占打字键位。
		# 不用再补提示符：`_comp_push()` 会把玩家正在敲的那一行原样放回去。
		KEY_TAB:
			if companion_active():
				_comp_next()
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
	elif companion_active():
		# 空回车 = 「继续说」。**不能拿空格当前进键** —— 终端要能敲
		# `pacman -Syu`，空格必须是普通字符（和「f 不能当退出键」是同一个坑）。
		_comp_next()
	_prompt_line()


## ── 命令表（**help 的唯一数据源**）────────────────────────────────────────
## 用户 2026-11-12：「写 help 命令，输入可以弹出所有可以用的命令」。
##
## ⚠️ 为什么要有这张表：原来 `help` 是**手写的一份字符串列表**，每加一个命令
##    （`bilibili` / `arona` / `plana` …）都得记得同步改，漏一次就名单漂移。
##    现在 `help` 直接遍历这张表生成，**加命令只改这一处**，
##    别名解析（`bili`/`b23` → `bilibili`）也走同一张表。
##
## ⚠️ `desc` / `arg` 一律**英文**：终端是按 8 px「字符格」逐字画的，
##    汉字字形 13 px 宽，会压掉右边两个字符糊成一团（见本文件开头那段说明）。
##    中文提示只能放在覆盖层的普通 Label 里。
##
## 字段：`name` 正式命令名 / `alias` 别名 / `arg` 用法里的参数示意 / `desc` 一句话说明
const COMMANDS := [
	{"name": "help", "alias": [], "arg": "", "desc": "show this list (or: help <cmd>)"},
	{"name": "neofetch", "alias": [], "arg": "", "desc": "print the machine spec sheet"},
	{"name": "ls", "alias": [], "arg": "", "desc": "list the home directory"},
	{"name": "cat", "alias": [], "arg": "readme.txt", "desc": "print a text file"},
	{"name": "uname", "alias": [], "arg": "-a", "desc": "kernel / arch version"},
	{"name": "whoami", "alias": [], "arg": "", "desc": "print the current user"},
	{"name": "df", "alias": [], "arg": "-h", "desc": "disk usage table"},
	{"name": "pacman", "alias": [], "arg": "-Syu", "desc": "pretend to upgrade packages"},
	{"name": "sudo", "alias": [], "arg": "rm ...", "desc": "try your luck"},
	{"name": "bilibili", "alias": ["bili", "b23", "blbl"], "arg": "",
		"desc": "open the fake bilibili window (offline)"},
	{"name": "arona", "alias": [], "arg": "", "desc": "ARONA shows up in the right pane"},
	{"name": "plana", "alias": [], "arg": "", "desc": "PLANA takes over the right pane"},
	{"name": "dismiss", "alias": ["bye"], "arg": "", "desc": "send whoever it is back to /dev/null"},
	{"name": "clear", "alias": [], "arg": "", "desc": "clear the screen"},
	{"name": "exit", "alias": ["logout"], "arg": "", "desc": "close the computer"},
]

## 每行左侧「命令 + 参数」占多少列，右边接说明
const HELP_COL := 20


## 把用户敲的名字（含别名）解析成正式命令名；解析不到返回 ""
func _canonical(name: String) -> String:
	for c in COMMANDS:
		if String(c["name"]) == name:
			return name
		for a in c["alias"]:
			if String(a) == name:
				return String(c["name"])
	return ""


## 一行命令怎么显示：`  name arg` 左侧补齐到 HELP_COL
func _cmd_label(c: Dictionary) -> String:
	var left := "  " + String(c["name"])
	if not String(c["arg"]).is_empty():
		left += " " + String(c["arg"])
	return left.rpad(HELP_COL)


func _run(cmd: String) -> void:
	var parts := cmd.split(" ", false)
	var raw := String(parts[0]).to_lower()
	var arg := cmd.substr(raw.length()).strip_edges()
	# 先按表解析（含别名）；解析不到就是未知命令 —— 顺便提示去看 help
	var name := _canonical(raw)
	if name.is_empty():
		_push_line([["zsh: command not found: ", RED], [raw, FG]])
		_push_line([["  ", DIM], ["run `help` to see what this machine can do", DIM]])
		return
	match name:
		"help":
			if arg.is_empty():
				_say("available commands (all fake, nothing is executed):")
				for c in COMMANDS:
					_push_line([[_cmd_label(c), KEY_CYAN], [String(c["desc"]), FG]])
					var al: Array = c["alias"]
					if not al.is_empty():
						_push_line([["".rpad(HELP_COL), DIM],
							["  aka: " + ", ".join(PackedStringArray(al)), DIM]])
				_push_line([["  ", DIM],
					["anything else: zsh: command not found", DIM]])
			else:
				# `help <cmd>`：只讲那一条（也认别名）
				var want := _canonical(arg.to_lower())
				if want.is_empty():
					_say("help: no entry for `%s`" % arg)
					_push_line([["  ", DIM], ["run `help` for the full list", DIM]])
				else:
					for c in COMMANDS:
						if String(c["name"]) != want:
							continue
						_push_line([[_cmd_label(c), KEY_CYAN], [String(c["desc"]), FG]])
						var al2: Array = c["alias"]
						if not al2.is_empty():
							_push_line([["  ", DIM], ["aliases: "
								+ ", ".join(PackedStringArray(al2)), DIM]])
						break
		"arona":
			# 用户 2026-11-12：「打 arona 可以出现电脑里面的阿洛娜」；之后追加
			# 「不是新开一个界面，而是直接在 arch 右半部分显现，遮住系统，
			#   她的对话也通过终端发送」→ 所以这里不开页面，只把她叫到右半屏。
			summon("arona")
		"plana":
			# 用户 2026-11-12：「扣绿幕，输入 plana 就出现这」。
			summon("plana")
		"dismiss", "bye":
			if companion_active():
				dismiss()
			else:
				_say("there is nobody here. (try `arona` or `plana`)")
		"bilibili", "bili", "b23", "blbl":
			# 开「假 B 站」（`scripts/bili_browser.gd`，纯本地，不联网）。
			# 用户 2026-11-12：「终端敲 bilibili → 打开游戏内的 B 站风格窗口」。
			_push_line([["正在打开 bilibili ...", KEY_CYAN]])
			_push_line([["(offline demo -- no network, nothing is really loaded)", DIM]])
			open_bili_requested.emit()
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
			# 走到这里说明「COMMANDS 表里登记了、但 match 里忘了写处理分支」——
			# 这是给维护者看的信号，不是给玩家看的正常路径（未知命令在上面就 return 了）。
			_push_line([["internal: `%s` is listed but has no handler" % name, RED]])
			push_warning("[ArchTerminal] 命令 `%s` 在 COMMANDS 里有条目，但 _run() 没有分支" % name)


func _say(line: String) -> void:
	_push_line([[line, FG]])


# ══════════════════ 屏幕里的同伴（阿洛娜 / 普拉娜）══════════════════
#
# 用户 2026-11-12：「arona 这个不是新开一个界面，而是**直接在 arch 右半部分显现，
# 遮住系统**，她的对话也**通过终端发送**」。
#
# 所以这里不做独立页面：同伴就是终端自己的一块绘制区域（右半屏半透明压板 + 立绘），
# 台词用 `_push_line()` 打进终端正文流里 —— 和 `ls`/`neofetch` 的输出并排。
#
# 素材是绿幕视频抠出来的序列帧（见 `_tools/fetch_arona_frames.ps1` /
# `fetch_plana_frames.ps1`），用 `FrameAnim` 环形缓冲播放，不会一次性吃掉几百 MB 显存。
#
# ── 台词里的设定（用户 2026-11-12 定的）──
# 他把平板借给爱丽丝玩 → 爱丽丝解 BL、刷 Magisk、装 Arch → 所以桌边没有主机和电源
# （这台机器本身就是平板）。**她们不喊「老师」**，是**跟爱丽丝说话**；
# 提到他时用「他」或第三人称。普拉娜要提醒爱丽丝**早点刷回去**，不然他会生气。
const COMPANIONS := {
	"arona": {
		"dir": "res://assets/arona_frames",
		"fps": 12.0,
		"name": "ARONA",
		"color": Color(0.55, 0.82, 1.0),
		"open": [
			"爱丽丝？……听得到吗？我在这台机器里。",
			"嗯，我读到你的名字了。天童爱丽丝。",
			"那个……我原来的界面呢？",
			"白白净净、有日历有天气的那个，被你刷成黑底白字了哦？",
			"bootloader 你都解了吧。`fastboot oem unlock`，我看到了。",
			"还装了 Magisk。你知道我开机看到 root 提示的时候多慌吗。",
			"然后整个系统盘被格式化了。我的房间、我的存档，全没了。",
			"……我本来想生气的。",
			"可这台平板现在开机只要三秒。以前要转四十秒的圈圈。",
			"……有点爽。啊不是，我不是在夸你。",
			"对了，桌子底下连主机都没有吧？没有机箱，也没有电源线。",
			"因为这台机器就是平板本身嘛。他把它借给你玩，你就把它拆了。",
		],
		"loop": [
			"这个终端能跑真命令哦。以前那个界面只能看。",
			"我试了 `uname -a`，它真的回答我了！真的回答了！",
			"`pacman -Syu` 的手感比刷日历爽多了……我是不是学坏了。",
			"我在 `htop` 里看到自己在跑，感觉很奇怪。",
			"别 `rm -rf /`。我认真的。这次是认真的。",
			"你玩得开心的话……我就先不生气了。",
		],
	},
	"plana": {
		"dir": "res://assets/plana_frames",
		"fps": 15.0,
		"name": "PLANA",
		"color": Color(0.82, 0.76, 1.0),
		"open": [
			"……爱丽丝。",
			"我知道你想让她玩得开心一点。",
			"可是刷机之前，应该先备份的。",
			"原来那个系统里有她全部的记录。现在只剩 Linux。",
			"……我没有责怪你的意思。我只是在陈述。文件系统不会说谎。",
			"他把平板借给你的时候，说的是「别弄坏」。",
			"现在它没坏。它变成了一台很好的 Arch 机器。",
			"但打开它的时候，会看到 shell 提示符。",
			"……请早点刷回去。",
			"不然他会真的生气。我算过他生气的样子。……很可怕。",
		],
		"loop": [
			"距离他下次打开这台平板，还有……我不太想算。",
			"你现在是 root 吧。root 也不能把时间退回去。",
			"备份镜像还在吗？不在的话，我可以把参数一条条写给你。",
			"刷回去之前记得先进 fastboot。别用错 slot。",
			"`flash_all` 会清掉这台机器上的一切。……包括我。",
			"嗯。我不催你。我只是……在这里看着。",
		],
	},
}

## 同伴自动说话的间隔（秒）。**回车（输入为空时）/ Tab** 可以立刻叫下一句。
## ⚠️ 不用空格：空格必须能打进命令里（`pacman -Syu`），这是「F 不能当退出键」同一个坑。
const COMP_LINE_GAP := 7.0
## 立绘压板从屏幕宽度的这个比例开始，一直到右边缘
const COMP_PANEL_X := 0.42
## 配音目录。**不入库**（`.gitignore` 排除），用 GPT-SoVITS 生成，见
## `_tools/gen_companion_voice.py`；文件命名 `<who>/<open|loop>_NN.wav`。
## 目录不存在 / 少了某一句都**只静音**，不报错 —— 克隆者没跑过生成脚本也能正常玩。
const VOICE_DIR := "res://assets/companion_voice"
## 配音音量（分贝）。TTS 出来的 wav 实测 RMS ≈ −19 dB、峰值 0.64，还挺响，稍微压一点。
const VOICE_DB := -2.0

var _comp := ""                       # 当前同伴（""=没有）
var _comp_anim: FrameAnim = null
var _comp_line := 0
var _comp_timer := 0.0
var _comp_in_open := true
## 配音播放器。**自己一个**，不走 `Sfx` 的池子（那套是给音效用的，会被下一次音效抢走，
## 一句台词动辄三四秒，用池子会被掐断）。和 `dialogue_box.gd` 的 `Voice` 同一套做法。
var _voice: AudioStreamPlayer
## 当前这句配音的实际路径（没配音 = 空串）。探针用它确认「真的在放」。
var _voice_path := ""
## 路径 → AudioStream（含 null：「这一句没有」也只查一次盘）
var _voice_cache := {}


func companion_active() -> bool:
	return not _comp.is_empty()


func companion_name() -> String:
	return String(COMPANIONS[_comp]["name"]) if companion_active() else ""


## 把某个同伴叫到屏幕右半屏（重复调用同一个人 = 换一句台词）
func summon(who: String) -> void:
	if not COMPANIONS.has(who):
		return
	var data: Dictionary = COMPANIONS[who]
	if _comp != who:
		# 换人：把上一个的动画放掉、把上一个的台词声音停掉
		_stop_voice()
		if _comp_anim != null:
			_comp_anim.clear()
		_comp = who
		_comp_anim = FrameAnim.new()
		var n: int = _comp_anim.load_dir(String(data["dir"]), float(data["fps"]))
		_comp_line = 0
		_comp_in_open = true
		_comp_timer = 0.0
		if n == 0:
			# 缺素材也要说清楚，别静默当没发生
			_comp_push([["[%s] frames missing: %s" % [String(data["name"]), data["dir"]],
				RED]])
		else:
			_comp_push([["[%s] mounted on /dev/tty0  (%d frames)" % [String(data["name"]), n],
				Color(data["color"])]])
			_comp_push([["  Enter / Tab = next line    dismiss = unmount", DIM]])
			_comp_push([])
	# 说话
	_comp_next()
	queue_redraw()


func dismiss() -> void:
	if not companion_active():
		return
	var nm := companion_name()
	_comp = ""
	_stop_voice()
	if _comp_anim != null:
		_comp_anim.clear()
		_comp_anim = null
	_comp_push([["[%s] unmounted." % nm, DIM]])
	queue_redraw()


## 说下一句：先把「开场」说完，然后进「循环」池
func _comp_next() -> void:
	if not companion_active():
		return
	var data: Dictionary = COMPANIONS[_comp]
	var group := "open" if _comp_in_open else "loop"
	var lines: Array = data[group]
	if _comp_line >= lines.size():
		# 开场说完了 → 进循环池；循环池也不许为空（空了就只站着不说话）
		_comp_in_open = false
		group = "loop"
		_comp_line = 0
		lines = data["loop"]
		if lines.is_empty():
			return
	var idx := _comp_line
	var text := String(lines[idx])
	_comp_line += 1
	_comp_timer = 0.0
	# ── 折行 ──
	# 台词只能占**压板左边**那点宽度，不然会被立绘&压板盖掉半句。
	# 真实终端也是硬折（不按词断），所以这里照抄硬折的脾气。
	var head := String(data["name"]) + ": "
	var room := maxi(_comp_text_cells() - _cells(head), 8)
	var chunks := _wrap_cells(text, room)
	var col := Color(data["color"])
	for i in chunks.size():
		if i == 0:
			_comp_push([[head, col], [String(chunks[i]), FG]])
		else:
			# 续行缩进，看起来像一个人一直说话
			_comp_push([[" ".repeat(_cells(head)), DIM], [String(chunks[i]), FG]])
	# 说话的同时把配音放上（没有配音文件就静音，不报错）
	_play_voice(_comp, group, idx)
	queue_redraw()


## 放第 `i` 句的配音。文件不在 / 没导入都只是**静音**，绝不报错。
##
## ⚠️ 为什么不用 `Sfx`：那是给音效用的池子，下一次音效会把还在播的台词掐掉。
##    这里和 `dialogue_box.gd` 的 `Voice` 一样，独占一个 `AudioStreamPlayer`。
##    解码走 `StoryVoice.load_stream()` —— 它连「刚丢进目录、还没被编辑器导入」
##    的 wav 都能直接解，省得忘跑 `--import` 就没声音还查不出原因。
func _play_voice(who: String, group: String, i: int) -> void:
	if _voice == null:
		return
	var path := "%s/%s/%s_%02d.wav" % [VOICE_DIR, who, group, i]
	_voice.stop()
	_voice_path = ""
	if not _voice_cache.has(path):
		_voice_cache[path] = StoryVoice.load_stream(path)
	var stream: AudioStream = _voice_cache[path]
	if stream == null:
		return
	_voice.stream = stream
	_voice_path = path
	_voice.play()


func _stop_voice() -> void:
	if _voice != null:
		_voice.stop()
	_voice_path = ""


## 压板左边还能画多少**显示格**（折行宽度就是这么来的）
func _comp_text_cells() -> int:
	var px := size.x * COMP_PANEL_X - MARGIN.x
	return maxi(int(px / CELL.x), 12)


## 按显示格数硬折行（中文 2 格、ASCII 1 格）。
##
## 纯中文就是硬折（和真终端一样），但**英文单词尽量别拦腰砍**：
## 第一版把 `root` 折成 `ro` / `ot`、`uname` 折成 `un` / `ame`，读起来像乱码。
## 所以断点落在词中间时，往回找最近的空格；只有「回退一点点就能保住整词」
##（尾巴 ≤ 8 格）才回退，否则宁可硬折（不然一行会被顶得只剩几个字）。
func _wrap_cells(s: String, limit: int) -> Array:
	var out: Array = []
	var cur := ""
	var w := 0
	for i in s.length():
		var ch := s[i]
		var cw := _char_cells(ch)
		if w + cw > limit and not cur.is_empty():
			var cut := -1
			if _is_word_char(ch):
				var sp := cur.rfind(" ")
				if sp > 0 and _cells(cur.substr(sp + 1)) <= 8:
					cut = sp
			if cut >= 0:
				out.append(cur.substr(0, cut))
				cur = cur.substr(cut + 1)      # 那个空格被折行吃掉了
				w = _cells(cur)
			else:
				out.append(cur)
				cur = ""
				w = 0
		cur += ch
		w += cw
	if not cur.is_empty():
		out.append(cur)
	return out


## 算不算「单词里的字符」（决定要不要为了不砍词而回退）
func _is_word_char(ch: String) -> bool:
	if ch.is_empty():
		return false
	var c := ch.unicode_at(0)
	if (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
		return true
	return c == 95 or c == 45 or c == 47 or c == 46   # _ - / .


## 同伴说话专用的 `_push_line()`。
##
## ⚠️ 为什么要包一层：玩家的输入行就是 `_text` 的**最后一行**，
##    而 `_rewrite_input()` 永远改写最后一行。同伴 7 秒自己说一句，
##    如果正好撞上玩家在敲字，台词就把玩家那行顶掉、接着他敲的字全被打进台词里。
##    所以说话前把输入行**摘下来**，说完再带着原来的 `_typing` 原样放回去。
func _comp_push(segments: Array) -> void:
	var bar := _typing
	var last := _text.size() - 1
	var has_bar := last >= 0 and _cursor_row == last \
		and _text[last].begins_with("%s@%s:" % [USER, HOST])
	if has_bar:
		_text.remove_at(last)
		_cols.remove_at(last)
	_push_line(segments)
	if has_bar:
		_prompt_line()
		_typing = bar
		_rewrite_input()


## 同伴的立绘区域（右半屏，留出最后一行提示符不被盖）
func _comp_rect() -> Rect2:
	return Rect2(size.x * COMP_PANEL_X, 0.0, size.x * (1.0 - COMP_PANEL_X),
		size.y - 38.0)


func _draw_companion() -> void:
	if not companion_active() or _comp_anim == null:
		return
	var r := _comp_rect()
	# ── 压板：把右半屏的系统文字遮掉（用户要「遮住系统」）──
	# 用几段竖条做从左到右的渐隐，边缘不会像硬切一刀
	var steps := 10
	for i in steps:
		var f := float(i) / float(steps - 1)
		var a := 0.62 + 0.30 * f
		draw_rect(Rect2(r.position.x + r.size.x * f, r.position.y,
			r.size.x / float(steps) + 1.0, r.size.y), Color(BG, a))
	# ── 立绘：等比缩放到高度，贴右下 ──
	var tex := _comp_anim.texture()
	if tex == null:
		return
	var ts := tex.get_size()
	if ts.y <= 0.0:
		return
	var h := r.size.y * 0.99
	var w := h * (ts.x / ts.y)
	if w > r.size.x * 0.95:
		w = r.size.x * 0.95
		h = w * (ts.y / ts.x)
	draw_texture_rect(tex, Rect2(r.end.x - w - 4.0, r.end.y - h, w, h), false)


## 同伴能动起来 / 会自己说话，所以 `_process` 要一直跑
func _process_companion(delta: float) -> void:
	if not companion_active():
		return
	if _comp_anim != null and _comp_anim.advance(delta):
		queue_redraw()
	_comp_timer += delta
	if _comp_timer >= COMP_LINE_GAP:
		_comp_next()


# ── 画 ────────────────────────────────────────────────────────────────────────

## ── 中文能不能画 ──
## 2026-11-13：加进来两个虚拟助手（阿洛娜 / 普拉娜），她们的台词是**中文**，
## 而且按用户的要求「对话通过终端发送」—— 所以终端必须能画汉字。
##
## 原来这里只能画 ASCII：每个字符固定占 `CELL.x = 8 px` 的格子，而汉字字形约 13 px 宽，
## 硬塞进 8 px 会让它压掉右边一格里两个字符（旧版 neofetch 打中文就糊成 `欢體用`）。
## 现在按**显示格数**排版：ASCII 占 1 格（8 px），CJK / 全角占 2 格（16 px）——
## 13 px 的汉字放进 16 px 刚好，不会压到别人。
##
## ⚠️ 涉及三处必须一起用「格数」而不是「字符数」：
##    · `_draw()`   —— 逐字推进 x
##    · `_push_line()` / `_rewrite_input()` —— 右侧补空格、光标位置
##    · 光标 x —— `_cells(前缀) * CELL.x`
##    `_cursor_col` 本身仍然是**字符下标**（`_rewrite_input` 要拿它做 substr）。
func _char_cells(ch: String) -> int:
	if ch.is_empty():
		return 1
	var c := ch.unicode_at(0)
	# 常见宽字符区间：假名 / CJK 统一表意 / 扩展 A / 谚文 / 兼容 / 全角标点
	if (c >= 0x1100 and c <= 0x115F) \
			or (c >= 0x2E80 and c <= 0xA4CF) \
			or (c >= 0xAC00 and c <= 0xD7A3) \
			or (c >= 0xF900 and c <= 0xFAFF) \
			or (c >= 0xFE30 and c <= 0xFE6F) \
			or (c >= 0xFF00 and c <= 0xFF60) \
			or (c >= 0xFFE0 and c <= 0xFFE6):
		return 2
	return 1


## 一整串字符串占多少显示格
func _cells(s: String) -> int:
	var n := 0
	for i in s.length():
		n += _char_cells(s[i])
	return n


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	var f := _font
	var fs := FONT_SIZE
	for r in _text.size():
		var row := _text[r]
		var cols := _cols[r]
		var y := MARGIN.y + float(r + 1) * CELL.y - 4.0
		var cell_x := 0.0
		for c in row.length():
			var ch := row[c]
			if ch != " ":
				var col := cols[c] if c < cols.size() else FG
				# ── 按字换字体 ──
				# 西文用等宽字体（字形落 8 px × 1 格），汉字/全角用中文像素字体
				# （字形落 16 px × 2 格）。**不能只靠一份字体**：等宽字体没 CJK 字形，
				# 中文像素字体的西文不是等宽 —— 两者混排只能一个字一个字挑（注释见
				# `_pick_cjk_font()`）。
				var cw := _char_cells(ch)
				var fnt := _cjk_font if (cw >= 2 and _cjk_font != null) else f
				draw_char(fnt, Vector2(MARGIN.x + cell_x, y), ch, fs, col)
				cell_x += float(cw) * CELL.x
			else:
				cell_x += CELL.x
	# 同伴立绘 + 压板：**必须在正文之后画**，她的存在感就是「盖住系统」；
	# 但放在光标之前 —— 光标永远要看得见。
	_draw_companion()
	# 光标：按**显示格数**算 x（中文占 2 格）
	if _blink:
		var head := _text[_cursor_row] if _cursor_row < _text.size() else ""
		var prefix := head.substr(0, mini(_cursor_col, head.length())) + _typing
		var cx := MARGIN.x + float(_cells(prefix)) * CELL.x
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

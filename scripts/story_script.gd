class_name StoryScript
extends RefCounted
## 剧情脚本：**只做解析和校验**，不碰任何节点、不加载任何资源。
##
## ── 为什么是「纯静态类」，不是 autoload，也不是 Node ──
## 自检是用 `godot --script res://scripts/_verify_story.gd` 跑的，那种模式下
## autoload 的名字**不是编译期可见的全局标识符**（`game_settings.gd` 开头那段踩过）。
## 而且解析器本来就不需要场景树：改剧本格式时不用开窗口就能测。
##
## ── 剧本格式 ──
## 写在 `res://story/*.txt`，**必须是 UTF-8**（存成 GBK 会被认出来并告诉你怎么改）。
## 只认五种写法，其余一律报错，并且**报出是第几行、原行是什么**：
##
##     # 随便写的注释                      整行以 # 开头 → 不播
##     优香: 你终于来了。                  名字 + 冒号 + 正文 → 有名字的对话
##     优香：全角冒号也行。
##     * 夕阳把栏杆染成橙色。              以 * 开头 → 没有名字的旁白
##     @wait 1.2                          以 @ 开头 → 指令
##
## 五个指令（`StoryScript.COMMANDS` 是唯一真相来源，报错时直接列给用户看）：
##
##     @wait <秒>         停一拍（浮点，> 0）
##     @clear             清空对话框、停 `CLEAR_SECONDS` 秒
##     @speed <字/秒>     改之后的打字速度（> 0）
##     @voice <文件名>    给**下一句**配语音，例如 @voice 开场_01（见 `story_voice.gd`）
##     @end               到此为止，后面的内容不播
##
## `@voice` 是**折叠进下一句**的：解析完它就不见了，那一句的 step 多出一个
## `"voice"` 字段。理由见 `parse()` 里那一段注释。
##
## ── 四个刻意的取舍（都是「写剧本的人不该操心的事」） ──
## 1. **一行 = 一句**，不做 `\n` 转义。要换行就多写几行 —— 写剧本的人不该和
##    转义字符打交道。
## 2. **不支持行尾注释**：`优香: 你好 # 备注` 里的 `#` 是正文的一部分。
##    只有**整行**以 `#` 开头才算注释。否则正文里的 `#` 会被悄悄吃掉。
## 3. **台词只在第一个冒号处切开**：`优香: 他说：好` → 说话人「优香」、
##    正文「他说：好」。所以正文里想打几个冒号就打几个。
## 4. 正文**不能以 `*` 或 `@` 开头**（那是语法）。真要用就前面加一个全角空格。
##
## ── steps 里每一项的字段 ──
##     {"kind": "say",     "who": String, "text": String, "line": int,
##      "voice": String}                      ← voice 是可选的，没有配音就没有这个键
##     {"kind": "narrate", "text": String, "line": int, "voice": String?}
##     {"kind": "wait",    "seconds": float, "line": int}
##     {"kind": "clear",   "line": int}
##     {"kind": "speed",   "cps": float, "line": int}
##     {"kind": "end",     "line": int}
## 每一项都带 `line`（剧本里的**行号，从 1 开始**），报错和排版检查都靠它定位。

## 步骤种类。用常量而不是裸字符串：播放器那边 `match` 时打错字会静默失效。
const K_SAY := "say"
const K_NARRATE := "narrate"
const K_WAIT := "wait"
const K_CLEAR := "clear"
const K_SPEED := "speed"
const K_VOICE := "voice"
const K_END := "end"

## `@clear` 的空档时长（秒）。解析器只负责认这个词，时长归播放器用；
## 放在这里是为了「剧本语义」只有一处定义。
const CLEAR_SECONDS := 0.6

## 打字速度的合理上限（字/秒）。超过它只是提醒一句，不当错误 ——
## 自检会故意用天文数字把打字机关掉，那是正当用法。
const CPS_WARN_ABOVE := 240.0

## 已知指令 → 报错时列给人看的说明。**加一条新指令要动两处**：
## 这里 + `_parse_command()` 的 `match`。
const COMMANDS := {
	"wait": "@wait <秒>            停一拍，例如 @wait 1.2",
	"clear": "@clear                清空对话框，停一个空档（CLEAR_SECONDS）",
	"speed": "@speed <字/秒>        改打字速度，例如 @speed 45",
	"voice": "@voice <文件名>       给下一句配语音（story/voice/ 里，后缀可省）",
	"end": "@end                  到此为止，后面的内容不播",
}

## 剧本文件的后缀（`list_txt()` 用）
const EXT := "txt"

## ── 设定表（角色表 / 场景表） ──
##
## 写在 `res://story/设定.md`：**同一份文件，人看着写剧本，代码拿去校验**。
## 表格夹在两个 HTML 注释标记之间，**第一列就是剧本里能写的名字**：
##
##     <!-- CAST:BEGIN -->
##     | 名字 | 身份 | … |
##     |---|---|---|
##     | 优香 | 同伴 | … |
##     <!-- CAST:END -->
##
## 为什么让一份**给人看的**文档同时能被解析：角色表要是拆成「文档一份 +
## 代码里再列一遍」，两边迟早对不上；而对不上的时候，校验要么失效、
## 要么开始冤枉人（这正是「校验」最该避免的两种失败）。
##
## 标记只认前缀，所以 `<!-- CAST:BEGIN -->` 和 `<!-- CAST:BEGIN 说明 -->` 都行。
const BIBLE_PATH := "res://story/设定.md"
const CAST_BEGIN := "<!-- CAST:BEGIN"
const CAST_END := "<!-- CAST:END"
const SCENES_BEGIN := "<!-- SCENES:BEGIN"
const SCENES_END := "<!-- SCENES:END"

## 两张表的列名。**改了会让校验失效**，所以代码里显式点名要求它们。
##     COL_NAME     角色表第一列：剧本里的说话人怎么写
##     COL_SCENE    场景表第一列：场景代号
##     COL_NODE     两张表都用：节点路径（相对 game.tscn 根），自检拿它去对场景
##     COL_INSIDE   场景表：这个场地在不在 game.tscn 里（「在」/「不在」）
const COL_NAME := "名字"
const COL_SCENE := "代号"
const COL_NODE := "节点"
const COL_INSIDE := "在场景里吗"

## 名字打错时的建议阈值：编辑距离 ≤ 这个数才提示「是不是想写 X」。
## 取 2 是因为「凯依 → 凯伊」这种同音字距离就是 1~2；再大就成了瞎猜，比不猜更烦人。
const TYPO_DISTANCE := 2


## 解析一段剧本文本。**没有副作用、不读盘**，所以自检可以直接喂字符串。
##
## 返回：
##     ok        bool          —— 有没有 error（false 时播放器拒绝播放）
##     steps     Array         —— 见文件头
##     errors    Array[String] —— 每条都形如「第 12 行：…… ｜ 原行「…」」
##     warnings  Array[String]
##     lines     int           —— 原文行数
##     chars     int           —— 会显示的正文总字数（say + narrate），用来估时长
static func parse(text: String) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var steps: Array = []
	var chars := 0

	# 统一换行：CRLF（Windows）/ CR（老 Mac）都归一成 LF，否则行号会错。
	var body := text.replace("\r\n", "\n").replace("\r", "\n")
	# ⚠️ BOM：记事本和某些编辑器存 UTF-8 会带 \uFEFF。不剥掉的话**第一行的头一个
	#    字符就是 BOM**，`#` 注释和「优香:」都会认不出来，而且报错信息还看不出原因
	#    （打印出来像「第 1 行：认不出这一行」却看着完全正常）。
	if body.begins_with("\uFEFF"):
		body = body.substr(1)

	# ⚠️ 编码检测。Godot 的 `FileAccess.get_file_as_string()` **假定 UTF-8**，
	#    不认 GBK。中文 Windows 记事本的「ANSI」就是 GBK，存出来的文件到这里会变成
	#    一串 U+FFFD（65533）。不报的话用户只看到满屏问号，根本不知道是哪一步错的。
	#    这是本工程最可能踩的一个坑，所以给一条**带操作步骤**的报错。
	var bad := body.count("\uFFFD")
	if bad > 0:
		errors.append("第 1 行起：文件不是 UTF-8（有 %d 个字符解不出来，多半被存成了 GBK/ANSI）。"
			% bad + "记事本「另存为」时把编码选成 UTF-8；VS Code 点右下角编码切到 UTF-8 再存。")

	var lines := body.split("\n")
	# 剧本文件几乎都以换行结尾，`split` 会为此多切出一个空串。它对**行号没有影响**
	# （那个空串在最后，前面每行的下标都还是对的），但报「原文 N 行」时不该把它算进去。
	var line_total := lines.size()
	if line_total > 0 and String(lines[line_total - 1]).is_empty():
		line_total -= 1
	for i in lines.size():
		var n := i + 1
		var raw: String = lines[i]
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			continue

		if line.begins_with("@"):
			var stop := _parse_command(line, n, steps, errors, warnings)
			if stop:
				# @end 之后还有内容 → 提醒一句（多半是「先临时砍掉后半段」的草稿）
				var rest := _count_content_lines(lines, i + 1)
				if rest > 0:
					warnings.append("第 %d 行：@end 之后还有 %d 行内容，不会被播放"
						% [n, rest])
				break
			continue

		if line.begins_with("*"):
			var t := line.substr(1).strip_edges()
			if t.is_empty():
				errors.append(_at(n, raw, "旁白只有 `*`，后面没写内容"))
			else:
				steps.append({"kind": K_NARRATE, "text": t, "line": n})
				chars += t.length()
			continue

		var cut := _first_colon(line)
		if cut < 0:
			errors.append(_at(n, raw,
				"认不出这一行 —— 既不是 `名字: 台词`，也不是 `* 旁白`，也不是 `@指令`。"
				+ "想当旁白请写成 `* %s`" % line))
			continue
		var who := line.substr(0, cut).strip_edges()
		var what := line.substr(cut + 1).strip_edges()
		if who.is_empty():
			errors.append(_at(n, raw, "冒号前面没有名字。无名字的旁白请写成 `* 内容`"))
		elif what.is_empty():
			errors.append(_at(n, raw, "说话人「%s」后面没有正文" % who))
		else:
			steps.append({"kind": K_SAY, "who": who, "text": what, "line": n})
			chars += what.length()

	# ── 把 `@voice` 折叠到**下一句**台词上 ──
	# 折叠而不是留成一个步骤，是为了让播放器**不需要游标**：它显示一句话的时候
	# 顺手看一眼这句有没有配音，不用再维护「上一条 @voice 是什么、用掉了没有」。
	# 那两种状态（还没用掉 / 已经用掉）正是最容易写错、又最难在演出里看出来的东西。
	var pending := {}
	var folded: Array = []
	for s in steps:
		var kind := String(s.get("kind", ""))
		if kind == K_VOICE:
			if not pending.is_empty():
				warnings.append("第 %d 行：这一句配了两个 @voice，前一个「%s」被覆盖"
					% [int(s.get("line", 0)), String(pending.get("name", ""))])
			pending = s
			continue
		if not pending.is_empty() and (kind == K_SAY or kind == K_NARRATE):
			# `@wait` / `@clear` 夹在中间也算「下一句」—— 配音是对那句话说的，
			# 中间停多久不影响它属于哪一句。
			s["voice"] = String(pending.get("name", ""))
			pending = {}
		folded.append(s)
	if not pending.is_empty():
		warnings.append("第 %d 行：@voice「%s」后面没有台词，它没用上"
			% [int(pending.get("line", 0)), String(pending.get("name", ""))])
	steps = folded

	return {
		"ok": errors.is_empty(),
		"steps": steps,
		"errors": errors,
		"warnings": warnings,
		"lines": line_total,
		"chars": chars,
	}


## 读一个剧本文件并解析。路径用 `res://` 形式。
## 返回 `parse()` 的全部字段，外加 `source`（路径）；读不到就 `ok = false`。
##
## ⚠️ **导出成 exe 之后要记得放行 `.txt`**：Godot 只把「导入过的资源」和
##    `export_presets.cfg` 的 `include_filter` 里列的后缀打进包，`.txt` 两者都不是。
##    README §11.3 的发布检查表里有一条。本仓库现在还只有编辑器 / 源码运行。
static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"ok": false, "steps": [], "lines": 0, "chars": 0, "source": path,
			"warnings": [],
			"errors": ["找不到剧本文件：%s" % path],
		}
	var text := FileAccess.get_file_as_string(path)
	var res := parse(text)
	res["source"] = path
	return res


## 列出一个目录里的所有剧本（按路径排序，**顺序稳定**）。
##
## ⚠️ `DirAccess.get_files()` 的顺序是**文件系统给的**，同一个目录不同机器可能不同。
##    这里显式 `sort()`，所以「找不到指定文件就按顺序取第一个」是确定的行为。
static func list_in_dir(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension().to_lower() == EXT:
			out.append(dir_path.path_join(f))
	out.sort()
	return out


## 目录里的第一个剧本（排好序的），没有就返回空串。
static func first_in_dir(dir_path: String) -> String:
	var all := list_in_dir(dir_path)
	return "" if all.is_empty() else all[0]


## 给探针 / 自检打印用的一览。**不做判断、不改变结果**，只汇总。
static func summary(res: Dictionary) -> Dictionary:
	var kinds := {}
	var speakers := {}
	var voiced := 0
	for s in res.get("steps", []):
		var k := String(s.get("kind", "?"))
		kinds[k] = int(kinds.get(k, 0)) + 1
		if k == K_SAY:
			speakers[String(s.get("who", ""))] = true
		if not String(s.get("voice", "")).is_empty():
			voiced += 1
	var names := speakers.keys()
	names.sort()
	return {
		"lines": int(res.get("lines", 0)),
		"steps": res.get("steps", []).size(),
		"chars": int(res.get("chars", 0)),
		"kinds": kinds,
		"speakers": names,
		"voiced": voiced,
		"errors": res.get("errors", []).size(),
		"warnings": res.get("warnings", []).size(),
	}


## ── 设定表：读 + 校验 ──────────────────────────────────────────────────────


## 读设定表，把两个标记之间的 Markdown 表格变成数据。**没有副作用之外的写入**。
##
## 返回：
##     ok       bool          —— 有没有 error
##     cast     Dictionary    —— {"columns": Array[String], "rows": Array[Dictionary]}
##     scenes   Dictionary    —— 同上
##     errors   Array[String] —— 每条都带行号
##
## 数据行的每一格按**列名**存成字典，所以表里加一列不用改代码。
static func read_bible(path := BIBLE_PATH) -> Dictionary:
	var errors: Array = []
	if not FileAccess.file_exists(path):
		return {"ok": false, "cast": _empty_table(), "scenes": _empty_table(),
			"errors": ["找不到设定表：%s" % path]}
	var body := FileAccess.get_file_as_string(path)
	body = body.replace("\r\n", "\n").replace("\r", "\n")
	if body.begins_with("\uFEFF"):
		body = body.substr(1)
	# 和剧本同一个坑：Godot 假定 UTF-8，GBK 会变成一串 U+FFFD。
	var bad := body.count("\uFFFD")
	if bad > 0:
		errors.append("设定表不是 UTF-8（有 %d 个字符解不出来，多半被存成了 GBK/ANSI）。"
			% bad + "记事本「另存为」时把编码选成 UTF-8。")
	var lines := body.split("\n")
	var cast := _table(lines, CAST_BEGIN, CAST_END, "角色表", COL_NAME, errors)
	var scenes := _table(lines, SCENES_BEGIN, SCENES_END, "场景表", COL_SCENE, errors)
	return {"ok": errors.is_empty(), "cast": cast, "scenes": scenes, "errors": errors}


## 只取角色表的**名字**（= 表格第一列的每一行）。
##
## 读不到设定表（例如导出时忘了放行 `.md`）就返回**空数组** —— 调用方据此
## 「没有表就不校验」，而不是每句台词刷一条报警。
static func cast_names(path := BIBLE_PATH) -> Array[String]:
	var out: Array[String] = []
	for row in read_bible(path)["cast"]["rows"]:
		out.append(String(row.get(COL_NAME, "")))
	return out


## 只取场景表的行（每行是「列名 → 单元格」的字典）。
static func scene_rows(path := BIBLE_PATH) -> Array:
	return read_bible(path)["scenes"]["rows"]


## 校验剧本里的说话人**在不在角色表里**。
##
## 返回的是**提醒**而不是错误：名字打错的剧本照样能播（名字牌上会写一个游戏里
## 不存在的角色），所以不该拦着不让玩 —— 但这种错自己几乎发现不了
## （`凯依` / `凯伊`），报出来就是纯赚。`names` 为空（没有设定表）时返回空数组。
##
## 同一个错名字只报一次（按**首次出现**的行号），免得一句话写错就刷满控制台。
static func check_speakers(res: Dictionary, names: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if names.is_empty():
		return out
	var reported := {}
	for s in res.get("steps", []):
		if String(s.get("kind", "")) != K_SAY:
			continue
		var who := String(s.get("who", ""))
		if names.has(who) or reported.has(who):
			continue
		reported[who] = true
		var hint := ""
		var guess := _closest(who, names)
		if guess != "":
			hint = " —— 是不是想写「%s」？" % guess
		out.append("第 %d 行：说话人「%s」不在角色表里%s（表在 %s）"
			% [int(s.get("line", 0)), who, hint, BIBLE_PATH])
	return out


# --- 内部 -------------------------------------------------------------------


## 取出 `begin` / `end` 两个标记之间的 Markdown 表格。
##
## 只认最朴素的写法：表头一行 `| 甲 | 乙 |`、紧跟着一行分隔 `|---|---|`、
## 然后是数据行。标记之间出现**非空、又不以 `|` 开头**的行 → 报错（不静默跳过，
## 和剧本解析一个脾气）。
static func _table(lines: PackedStringArray, begin: String, end: String,
		what: String, first_col: String, errors: Array) -> Dictionary:
	var b := -1
	var e := -1
	for i in lines.size():
		var s := String(lines[i]).strip_edges()
		if b < 0 and s.begins_with(begin):
			b = i
		elif b >= 0 and s.begins_with(end):
			e = i
			break
	if b < 0 or e < 0:
		errors.append("%s 找不到标记 —— 需要 `%s` 和 `%s` 各占一行，把表格夹在中间"
			% [what, begin, end])
		return _empty_table()

	var columns: Array[String] = []
	var rows: Array = []
	var seen := {}
	var header_done := false
	var need_sep := false
	for i in range(b + 1, e):
		var n := i + 1
		var s := String(lines[i]).strip_edges()
		if s.is_empty():
			continue
		if not s.begins_with("|"):
			errors.append("第 %d 行：%s 的标记之间只能放表格行（`| … |`）｜ 原行「%s」"
				% [n, what, s])
			continue
		var cells := _cells(s)
		if not header_done:
			header_done = true
			need_sep = true
			columns = cells
			var got: String = "" if columns.is_empty() else columns[0]
			if got != first_col:
				errors.append("第 %d 行：%s 第一列的列名必须是「%s」（收到「%s」）"
					% [n, what, first_col, got])
			continue
		if need_sep:
			need_sep = false
			if not _is_separator(cells):
				errors.append("第 %d 行：%s 的表头下面少了一行分隔行（`|---|`）｜ 原行「%s」"
					% [n, what, s])
			continue
		if cells.size() != columns.size():
			errors.append("第 %d 行：%s 这一行有 %d 格、表头有 %d 格 ｜ 原行「%s」"
				% [n, what, cells.size(), columns.size(), s])
			continue
		var row := {}
		for c in columns.size():
			row[columns[c]] = cells[c]
		var key := cells[0]
		if seen.has(key):
			errors.append("第 %d 行：%s 里「%s」出现了两次（第一列要唯一）" % [n, what, key])
		seen[key] = true
		rows.append(row)

	if columns.is_empty():
		errors.append("%s 没有表头" % what)
	elif rows.is_empty():
		errors.append("%s 一行数据都没有" % what)
	return {"columns": columns, "rows": rows}


static func _empty_table() -> Dictionary:
	var cols: Array[String] = []
	return {"columns": cols, "rows": []}


## `| 甲 | 乙 |` → `["甲", "乙"]`。
##
## 单元格里用反引号包起来的**代码格式会被剥掉** —— 表格是给人看的（`Player`
## 比 Player 显眼），而代码要的是原值。只在**整格**被包住时才剥，
## 所以 `` `a.glb` ※说明 `` 这种不动。
static func _cells(line: String) -> Array[String]:
	var s := line.strip_edges()
	if s.begins_with("|"):
		s = s.substr(1)
	if s.ends_with("|"):
		s = s.substr(0, s.length() - 1)
	var out: Array[String] = []
	for c in s.split("|"):
		var cell := String(c).strip_edges()
		if cell.length() >= 2 and cell.begins_with("`") and cell.ends_with("`"):
			cell = cell.substr(1, cell.length() - 2)
		out.append(cell)
	return out


## `|---|---|` 或 `|:--:|` 这种分隔行。
static func _is_separator(cells: Array[String]) -> bool:
	if cells.is_empty():
		return false
	for c in cells:
		if not c.contains("-"):
			return false
		if not c.replace("-", "").replace(":", "").strip_edges().is_empty():
			return false
	return true


## 在 `names` 里找和 `who` 最像的那个（编辑距离最小）。差太远返回空串 ——
## 「随便猜一个」比不猜更烦人。
static func _closest(who: String, names: Array[String]) -> String:
	var best := ""
	var best_d := TYPO_DISTANCE + 1
	for n in names:
		var d := _distance(who, String(n))
		if d < best_d:
			best_d = d
			best = String(n)
	return "" if best_d > TYPO_DISTANCE else best


## 编辑距离（增/删/改各算 1）。
##
## ⚠️ `prev = cur` 之后**必须** `duplicate()`：GDScript 的数组是引用类型，
## 不复制的话下一轮 `cur.clear()` 会把 `prev` 一起清掉，结果恒为 0。
static func _distance(a: String, b: String) -> int:
	var la := a.length()
	var lb := b.length()
	if la == 0:
		return lb
	if lb == 0:
		return la
	var prev: Array[int] = []
	var cur: Array[int] = []
	for j in lb + 1:
		prev.append(j)
	for i in range(1, la + 1):
		cur.clear()
		cur.append(i)
		for j in range(1, lb + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur.append(mini(mini(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost))
		prev = cur.duplicate()
	return prev[lb]


## 第一个半角或全角冒号的位置；都没有返回 -1。
static func _first_colon(line: String) -> int:
	var a := line.find(":")
	var b := line.find("：")
	if a < 0:
		return b
	if b < 0:
		return a
	return mini(a, b)


## 报错前缀：行号 + 原行。原行原样带上，用户不用回去数行。
static func _at(n: int, raw: String, msg: String) -> String:
	return "第 %d 行：%s ｜ 原行「%s」" % [n, msg, raw.strip_edges()]


## 从 `from` 行开始数还有几行**有效内容**（非空、非注释）。
static func _count_content_lines(lines: PackedStringArray, from: int) -> int:
	var c := 0
	for i in range(from, lines.size()):
		var line: String = lines[i].strip_edges()
		if not line.is_empty() and not line.begins_with("#"):
			c += 1
	return c


## 解析一条 `@指令`。返回 true 表示「到此为止」（`@end`），外层要 break。
static func _parse_command(line: String, n: int, steps: Array,
		errors: Array, warnings: Array) -> bool:
	# 制表符也当分隔符：`@wait\t1.2` 在编辑器里看不出来，但会让人莫名其妙。
	var sp := line.replace("\t", " ").split(" ", false)
	var cmd := sp[0].substr(1).to_lower()
	var arg := " ".join(sp.slice(1))

	match cmd:
		"wait":
			if arg.is_empty() or not arg.is_valid_float():
				errors.append(_at(n, line,
					"@wait 要一个秒数，例如 `@wait 1.2`（收到「%s」）" % arg))
			elif arg.to_float() <= 0.0:
				errors.append(_at(n, line, "@wait 的秒数要 > 0（收到「%s」）" % arg))
			else:
				steps.append({"kind": K_WAIT, "seconds": arg.to_float(), "line": n})
		"clear":
			if not arg.is_empty():
				warnings.append(_at(n, line,
					"@clear 不吃参数，「%s」被忽略" % arg))
			steps.append({"kind": K_CLEAR, "line": n})
		"speed":
			if arg.is_empty() or not arg.is_valid_float():
				errors.append(_at(n, line,
					"@speed 要一个字/秒，例如 `@speed 45`（收到「%s」）" % arg))
			elif arg.to_float() <= 0.0:
				errors.append(_at(n, line, "@speed 要 > 0（收到「%s」）" % arg))
			else:
				var cps := arg.to_float()
				if cps > CPS_WARN_ABOVE:
					warnings.append(_at(n, line,
						"@speed %.0f 太快了（> %.0f），会变成整句瞬间出现"
						% [cps, CPS_WARN_ABOVE]))
				steps.append({"kind": K_SPEED, "cps": cps, "line": n})
		"voice":
			# 名字规则放在 `StoryVoice` 里：**一处定义**，播放器和报错都用它，
			# 免得「解析时放行、运行时不认」这种两边不一致。
			var bad := StoryVoice.name_error(arg)
			if bad.is_empty():
				steps.append({"kind": K_VOICE, "name": arg, "line": n})
			else:
				errors.append(_at(n, line, bad))
		"end":
			if not arg.is_empty():
				warnings.append(_at(n, line, "@end 不吃参数，「%s」被忽略" % arg))
			steps.append({"kind": K_END, "line": n})
			return true
		_:
			var known := ""
			for k in COMMANDS:
				known += "\n        " + String(COMMANDS[k])
			errors.append(_at(n, line,
				"不认识的指令 `@%s`。现在只有这 %d 个：%s" % [cmd, COMMANDS.size(), known]))
	return false

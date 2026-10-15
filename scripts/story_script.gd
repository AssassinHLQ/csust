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
## 四个指令（`StoryScript.COMMANDS` 是唯一真相来源，报错时直接列给用户看）：
##
##     @wait <秒>       停一拍（浮点，> 0）
##     @clear           清空对话框、停 `CLEAR_SECONDS` 秒
##     @speed <字/秒>   改之后的打字速度（> 0）
##     @end             到此为止，后面的内容不播
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
##     {"kind": "say",     "who": String, "text": String, "line": int}
##     {"kind": "narrate", "text": String, "line": int}
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
	"wait": "@wait <秒>        停一拍，例如 @wait 1.2",
	"clear": "@clear            清空对话框，停一个空档（CLEAR_SECONDS）",
	"speed": "@speed <字/秒>    改打字速度，例如 @speed 45",
	"end": "@end              到此为止，后面的内容不播",
}

## 剧本文件的后缀（`list_txt()` 用）
const EXT := "txt"


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
	for s in res.get("steps", []):
		var k := String(s.get("kind", "?"))
		kinds[k] = int(kinds.get(k, 0)) + 1
		if k == K_SAY:
			speakers[String(s.get("who", ""))] = true
	var names := speakers.keys()
	names.sort()
	return {
		"lines": int(res.get("lines", 0)),
		"steps": res.get("steps", []).size(),
		"chars": int(res.get("chars", 0)),
		"kinds": kinds,
		"speakers": names,
		"errors": res.get("errors", []).size(),
		"warnings": res.get("warnings", []).size(),
	}


# --- 内部 -------------------------------------------------------------------


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
				"不认识的指令 `@%s`。现在只有这四个：%s" % [cmd, known]))
	return false

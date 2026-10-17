class_name StoryVoice
extends RefCounted
## 剧情语音：**剧本里点名的名字 → 音频流**，并回答「这些文件到底在不在」。
##
## ── 怎么用（写剧本的人只需要看这一段） ──
##
##     1. 把音频文件丢进 `res://story/voice/`（ogg / wav / mp3 都行）；
##     2. 在剧本里那句台词的**上面**加一行 `@voice 名字`（不用写后缀）：
##
##            @voice 开场_01
##            * 2067 年。世界陷入一场前无古人、后无来者的毁灭性灾难。
##
##     3. 名字可以带子目录：`@voice 优香/01` → `story/voice/优香/01.ogg`。
##
## 后缀不写时按 `EXTS` 的顺序找，**先找到哪个用哪个**；写了后缀就只认那一个
## （改格式时忘了删旧文件的那种重名，不该被静默顶掉）。
##
## ── 三条刻意的取舍 ──
## 1. **找不到 = 静默**，只在控制台 push_warning 一次，绝不打断剧情。
##    配音是「锦上添花」，缺一句不该让整段演出放不出来。
## 2. **没导入过的文件也能放**。用户把 `xxx.wav` 丢进目录、又没打开过编辑器时，
##    没有 `.import`，`ResourceLoader.load()` 会直接失败（实测：`ResourceLoader.exists()`
##    返回 false，然后报 "No loader found for resource"）。这时退回
##    `AudioStream{WAV,OggVorbis,MP3}.load_from_file()` —— 那是**从原始文件解码**的
##    静态方法，不看导入系统。导出成 exe 之后走的是正常导入路径（`.ogg` 等是资源，
##    会被打进包），所以这条兜底只在「源码运行 + 刚丢进来的文件」时生效，
##    正好是最需要它的那一刻。
## 3. **名字只是名字，不是路径片段**：拒绝 `..`、`://`、`:`、`\` 之类，
##    免得一个写错的名字读到工程外面去。

## 语音文件目录。改这里要同时改 `story/voice/README.md`。
const DIR := "res://story/voice/"

## 认的后缀。**顺序就是「没写后缀时」的优先级**：ogg 排第一（体积最小、音质够）。
const EXTS: Array[String] = ["ogg", "wav", "mp3"]

## 本次运行里已经报过「找不到」的名字（同一个名字只报一次，免得刷屏）
static var _miss: Dictionary = {}


## 名字合不合法。合法返回空串，不合法返回**给人看的原因**。
##
## 这是 `story_script.gd` 在解析 `@voice` 时用的 —— 所以它**必须纯**：
## 不读盘、不加载，只是字符串规则。
static func name_error(name: String) -> String:
	if name.is_empty():
		return "@voice 要一个文件名（不用写后缀），例如 `@voice 开场_01`"
	if name.contains("://"):
		return "@voice 只写 `story/voice/` 里面的相对名字，不要写 `res://` 或 `user://`"
	if name.begins_with("/") or name.begins_with("\\"):
		return "@voice 的名字不能以斜杠开头"
	if name.contains(".."):
		return "@voice 的名字里不能有 `..`（它只认 `story/voice/` 里面的文件）"
	for ch in [":", "\\", "*", "?", "\"", "<", ">", "|"]:
		if name.contains(ch):
			return "@voice 的名字里不能有 `%s`" % ch
	if name.strip_edges().is_empty():
		return "@voice 的名字不能全是空格"
	return ""


## 这个名字对应的**真实文件路径**；找不到返回空串。
static func find(name: String) -> String:
	var n := name.strip_edges()
	if n.is_empty() or not name_error(n).is_empty():
		return ""
	# 写了后缀并且真的存在 → 只认它
	var ext := n.get_extension().to_lower()
	if EXTS.has(ext):
		var direct := DIR + n
		if FileAccess.file_exists(direct):
			return direct
	# 没写后缀（或写了个不认识的后缀）→ 按 EXTS 顺序试
	for e in EXTS:
		var p := DIR + n + "." + e
		if FileAccess.file_exists(p):
			return p
	return ""


## 名字 → 音频流。找不到 / 读不出来都返回 null（**不报错**，调用方决定怎么说）。
##
## 先走导入系统（编辑器里、导出包里的正常路径），失败再走原始文件解码。
static func load_stream(name_or_path: String) -> AudioStream:
	var path := name_or_path
	if not path.contains("://"):
		path = find(path)
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path)
		if res is AudioStream:
			return res as AudioStream
	if not FileAccess.file_exists(path):
		return null
	# ⚠️ 这个分支专门兜「刚丢进目录、还没被编辑器导入」的文件。
	#    别改成 ResourceLoader.load()：那条路对没有 .import 的音频一律失败。
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


## 这批名字里**一个文件都找不到**的那些（保持原顺序、去重）。
static func missing(names: Array) -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for n in names:
		var s := String(n)
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		if find(s).is_empty():
			out.append(s)
	return out


## 「这个名字找不到文件」的一句话说明（带**备选路径**，用户照着改名就行）。
static func missing_hint(name: String) -> String:
	return "找不到语音「%s」—— 应该是 %s%s.{ogg,wav,mp3} 里的一个" % [
		name, DIR, name]


## 这个名字报过「找不到」了吗？报过返回 false（调用方据此避免重复刷屏），
## 没报过会记下来并返回 true。
static func note_missing(name: String) -> bool:
	if _miss.has(name):
		return false
	_miss[name] = true
	return true


## 已报过「找不到」的名字（自检 / 探针用）
static func missing_reported() -> Array[String]:
	var out: Array[String] = []
	for k in _miss:
		out.append(String(k))
	out.sort()
	return out


## 清掉「报过了」的记录（自检每个用例之间要复位，否则第二条用例不报）
static func reset_reported() -> void:
	_miss.clear()

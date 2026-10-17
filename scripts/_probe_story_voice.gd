extends SceneTree
## 探针：开场那三句的配音真的接上了 —— 名字能解析、文件能解码、时长对得上、
## 而且剧本解析后每一步身上确实挂着对应的 `voice`。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_story_voice.gd

const STORY := "res://story/开场.txt"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("\n=== 开场配音 ===")
	var want := ["开场_01", "开场_02", "开场_03"]
	for n in want:
		var p := StoryVoice.find(n)
		if p.is_empty():
			print("  %-8s ✗ 找不到文件" % n)
			continue
		var s := StoryVoice.load_stream(n)
		var dur := s.get_length() if s != null else -1.0
		print("  %-8s → %s\n           %s  %.2f s" % [
			n, p, s.get_class() if s != null else "解码失败", dur])

	var res := StoryScript.load_file(STORY)
	if not res.get("ok", false):
		print("!! 剧本解析失败：%s" % str(res.get("errors", [])))
		quit(1)
		return
	print("\n=== 剧本里的每一步 ===")
	for i in res.get("steps", []).size():
		var s: Dictionary = res["steps"][i]
		var kind := String(s.get("kind", "?"))
		if kind == "end":
			print("  #%d  end" % i)
			continue
		var text := String(s.get("text", ""))
		if text.length() > 18:
			text = text.substr(0, 18) + "…"
		print("  #%d  %-8s voice=%-8s  %s" % [
			i, kind, String(s.get("voice", "")) if s.has("voice") else "—", text])
	print("\nsummary：%s" % str(StoryScript.summary(res)))
	quit(0)

extends SceneTree
## 验：商店 12 条配音都能被 StoryVoice 找到，并真的挂到对话上开播。
##   _tools/run_shot.sh res://scripts/_verify_shop_voice.gd -- --splat=off --story=off

const NAMES := [
	"shop/serika_01", "shop/serika_02", "shop/serika_03", "shop/serika_04",
	"shop/serika_05", "shop/serika_06", "shop/serika_07", "shop/serika_08",
	"shop/serika_09", "shop/momoi_01", "shop/momoi_02", "shop/aris_01",
]


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var missing := 0
	for n in NAMES:
		var p := StoryVoice.find(n)
		if p.is_empty():
			print("[voice] MISSING ", n)
			missing += 1
		else:
			print("[voice] OK ", n, " -> ", p)
	if missing > 0:
		quit(1)
		return

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(80)
	var d := game.get_node_or_null("DialogueBox") as DialogueBox
	if d == null:
		print("[voice] 没有 DialogueBox")
		quit(1)
		return
	d.play_steps([
		{"kind": "say", "who": "芹香", "text": "你配电脑吗?", "voice": "shop/serika_01"},
		{"kind": "say", "who": "小桃", "text": "我chovy,什么破卡.", "voice": "shop/momoi_01"},
		{"kind": "say", "who": "爱丽丝", "text": "邦邦卡邦!就这套了!", "voice": "shop/aris_01"},
	], "shop_voice_probe")
	await _wait(12)
	print("[voice] 当前路径 = ", d.current_voice_path())
	print("[voice] 正在播放 = ", d.is_voice_playing())
	quit(0 if not d.current_voice_path().is_empty() else 2)

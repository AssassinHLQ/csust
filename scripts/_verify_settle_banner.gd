extends SceneTree
## 验：四种结算板（稳定基金 / 体育彩票 / K 线 / 跳价牌）第一次踩上去都弹大字；
## 站在同一格不动不重复结算；回头再踩同一格提示「本格已结算」。
##   godot --path . --headless --script res://scripts/_verify_settle_banner.gd
var _player: CharacterBody3D
var _fut: Node3D
var _banner: Label


func _initialize() -> void:
	_run.call_deferred()


func _place(pl: Dictionary) -> void:
	var cx := (float(pl["x0"]) + float(pl["x1"])) * 0.5
	var cz := (float(pl["z0"]) + float(pl["z1"])) * 0.5
	_player.global_position = Vector3(cx, float(pl["top"]) + 0.05, cz)
	_player.velocity = Vector3.ZERO


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	for _i in 30:
		await physics_frame

	_fut = lvl.get_node_or_null("Futures")
	_banner = _fut.get("_banner") as Label
	var plates: Array = _fut.get("plates")
	var picks := {}
	for pl in plates:
		var nm := String(pl["name"])
		var kind := String(pl.get("kind", ""))
		if kind == "fund" and not picks.has("稳定基金"):
			picks["稳定基金"] = pl
		elif kind == "lottery" and not picks.has("体育彩票"):
			picks["体育彩票"] = pl
		elif kind == "" and nm.begins_with("K") and not picks.has("K 线"):
			picks["K 线"] = pl
		elif kind == "" and not nm.begins_with("K") and not picks.has("跳价牌"):
			picks["跳价牌"] = pl
	print("[banner] 结算板 %d 块，取样 %s" % [plates.size(), str(picks.keys())])

	for key in picks.keys():
		var pl: Dictionary = picks[key]
		_place(pl)
		for _i in 4:
			await physics_frame
		var n0 := int(_fut.get("settlements"))
		var txt := _banner.text
		print("[banner] %s（%s）大字 = 「%s」 含%%=%s" % [
			key, String(pl["name"]), txt, str(txt.contains("%"))])
		# 站住不动 30 帧：不能再结算
		for _i in 30:
			await physics_frame
		print("[banner]   站住不动 → 结算次数 %d → %d（期望不变）" % [
			n0, int(_fut.get("settlements"))])
		# 走开一帧再回来：提示「本格已结算」
		_player.global_position = Vector3(-300.0, 0.0, 0.0)
		await physics_frame
		_place(pl)
		for _i in 4:
			await physics_frame
		print("[banner]   回头再踩 → 「%s」（期望以「本格已结算」开头）" % _banner.text)

	quit(0)

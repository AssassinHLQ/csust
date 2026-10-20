extends SceneTree
## 探针：把 `game.gd` 里登记的**全部天空盒**真的 `load()` 一遍，打印尺寸/显存占用，
## 顺便验证「10 个 key 都能用、默认还是 pink」。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_skies.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var g = load("res://scripts/game.gd")
	var skies: Dictionary = g.SKIES
	var fogs: Dictionary = g.SKY_FOG
	var order := [
		"pink", "day", "night", "dusk",
		"overcast", "space", "cartoon", "coldnight", "coldsunset", "bluesunset",
	]
	print("PROBE 天空盒 %d 个（默认 %s）" % [skies.size(), g.SKY_DEFAULT])
	var ok := 0
	for key in order:
		if not skies.has(key):
			print("  %-11s ✗ 没登记" % key)
			continue
		var path: String = skies[key]
		var tex := load(path) as Texture2D
		if tex == null:
			print("  %-11s ✗ 加载失败 %s" % [key, path])
			continue
		ok += 1
		var fog: Color = fogs.get(key, Color.MAGENTA)
		print("  %-11s %s  %d×%d  %.0f KB  雾色 (%.2f, %.2f, %.2f)%s" % [
			key, path.get_file(), tex.get_width(), tex.get_height(),
			FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)).size() / 1024.0,
			fog.r, fog.g, fog.b,
			"" if fogs.has(key) else "  ⚠️ 缺雾色"])
	# 多出来的 key（登记了但不在上面清单里）
	for key in skies:
		if not (key in order):
			print("  %-11s ⚠️ 不在 order 清单里" % key)
	print("PROBE 结果：%d / %d 可用" % [ok, order.size()])
	quit(0 if ok == order.size() else 1)

extends SceneTree
## 只读检查（不加载 game.tscn，绕开 player.gd 的冲突）：
##   ① 四个曲目的文件都在、循环参数对不对
##   ② 画室609 的「前奏 + 循环体」数值
##   ③ 默认不淡化（Music.FADE_DEFAULT）
##   godot --headless --path . --script res://scripts/_verify_music_assets.gd

func _initialize() -> void:
	var fails: Array[String] = []
	print("=== 曲目表 ===")
	print("  %s" % str(Music.names()))
	print("  缺文件：%s（应为空）" % str(Music.missing_files()))
	if not Music.missing_files().is_empty():
		fails.append("有曲目文件缺失")

	print("\n=== 循环参数 ===")
	for n in ["shop", "gamedev", "esports", "room609", "finalboss"]:
		var info: Dictionary = Music.TRACKS[n]
		var path: String = Music.DIR + String(info.get("file", ""))
		var st := load(path) as AudioStreamOggVorbis
		if st == null:
			print("  %-8s !! 载不到 %s" % [n, path])
			fails.append("%s 载不到" % n)
			continue
		print("  %-8s loop=%-5s loop_offset=%7.3f s  长度=%8.3f s  音量 %.1f dB"
			% [n, str(st.loop), st.loop_offset, st.get_length(), float(info.get("db", 0.0))])
		if not st.loop:
			fails.append("%s 没开循环" % n)

	# 画室 609 的具体数值
	var r609 := load(Music.DIR + "art609_theme.ogg") as AudioStreamOggVorbis
	print("\n=== 画室609 结构 ===")
	if r609 == null:
		fails.append("画室609 载不到")
	else:
		print("  总长            %.4f s（应 151.9000）" % r609.get_length())
		print("  前奏（播一次）  0 ~ %.4f s（应约 76.40，= 1:16.40）" % r609.loop_offset)
		print("  循环体（反复）  %.4f ~ %.4f s，长 %.4f s（= %.2f → %.2f）"
			% [r609.loop_offset, r609.get_length(),
				r609.get_length() - r609.loop_offset, r609.loop_offset, r609.get_length()])
		if absf(r609.get_length() - 151.90) > 0.05:
			fails.append("画室609 总长不是 151.90（%.4f）" % r609.get_length())
		if r609.loop_offset < 75.5 or r609.loop_offset > 77.5:
			fails.append("画室609 loop_offset 不在 1:16 附近（%.3f）" % r609.loop_offset)

	print("\n=== 不淡化 ===")
	print("  Music.FADE_DEFAULT = %.1f（应 0）" % float(Music.FADE_DEFAULT))
	if float(Music.FADE_DEFAULT) > 0.0:
		fails.append("FADE_DEFAULT 不是 0")

	print("\n=== 判定 ===")
	if fails.is_empty():
		print("  全部通过 ✔")
		quit(0)
	else:
		for f in fails:
			print("  ✘ %s" % f)
		quit(1)

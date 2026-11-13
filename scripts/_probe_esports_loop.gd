extends SceneTree
## 只读自检：电竞房 BGM 的循环参数到底有没有进到运行时。
##
##   Godot --headless --script res://scripts/_probe_esports_loop.gd
##
## 判据：loop=true、loop_offset≈22.7656、时长≈111.77 s。

const PATH := "res://assets/music/esports_theme.ogg"


func _initialize() -> void:
	var s := load(PATH) as AudioStreamOggVorbis
	if s == null:
		print("[loop] ✗ 加载失败: %s" % PATH)
		quit(1)
		return
	print("[loop] 时长      : %.4f s" % s.get_length())
	print("[loop] loop      : %s" % str(s.loop))
	print("[loop] loop_offset: %.4f s" % s.loop_offset)
	var body := s.get_length() - s.loop_offset
	print("[loop] 循环段长  : %.4f s（%.0f 秒处回到 %.2f s）"
		% [body, s.get_length(), s.loop_offset])
	var ok := s.loop and absf(s.loop_offset - 22.7656) < 0.01
	print("[loop] ★ %s" % ("通过" if ok else "不符合预期"))
	quit(0 if ok else 2)

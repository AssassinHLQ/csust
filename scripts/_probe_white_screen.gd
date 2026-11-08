extends SceneTree
## 探针：第二场景（蒙德里安厅 + 校园泼溅）会不会**玩着玩着整屏变白**。
##
## 用法：_tools/run_shot.sh res://scripts/_probe_white_screen.gd
##
## 用户 2026-11-08：「第二场景高斯泼溅,一开始是正常的,突然变成这样子白屏!」
## 实测那张截图：**纯白 255/255/255**（均值 255.0、标准差 <2、190 万像素只有 34 色）
## —— 不是「看见天空」，是整帧被推爆成白。
##
## 本探针每秒采样一次帧缓冲（中间区域，避开 HUD）：
##   · 均值亮度 / 标准差 / 颜色种类
##   · 显存（纹理 / 缓冲 / 总计）
##   · 一旦均值 > 250 且标准差 < 6（判为白屏）→ 存图 + 打印当时的帧号与显存
##
## 同时用 `Input` 驱玩家在场上走动（用户是走出来的，不是站着），
## 顺带把「距离裁切 / 分簇加载」这些路径也踩一遍。

const LEVEL := "res://scenes/next_level.tscn"
const OUT_SUB := "_whitescreen"
## 跑多久（秒）
const SECONDS := 40.0
## 采样间隔（帧）
const SAMPLE_EVERY := 45

var _frames := 0
var _started := false
var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)

	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	# HUD 会干扰亮度统计 → 藏掉（这样整屏都是 3D）
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	paused = false
	for _i in 180:
		await process_frame

	var player := level.get("_player") as CharacterBody3D
	if player == null:
		print("[white] 拿不到玩家，只做静态观察")
	print("[white] 开始观察 %.0f s，每 %d 帧采样一次" % [SECONDS, SAMPLE_EVERY])

	var max_frames := int(SECONDS * 60.0)
	_frames = 0
	var worst := 0.0
	var white_at := -1
	Input.action_press("move_forward")
	while _frames < max_frames:
		await process_frame
		_frames += 1
		# 每 3 秒转身，让镜头扫过不同角度（更容易暴露）
		if _frames % 180 == 0:
			Input.action_release("move_forward")
			Input.action_press("move_back")
		elif _frames % 180 == 90:
			Input.action_release("move_back")
			Input.action_press("move_forward")

		if _frames % SAMPLE_EVERY != 0:
			continue

		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img == null:
			print("  [%5d] 取不到帧缓冲" % _frames)
			continue
		var st := _stats(img)
		var vram := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
		var tex := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0
		var buf := float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0
		worst = maxf(worst, st["mean"])
		print("  [%5d] 均值 %6.1f  标准差 %5.1f  颜色 %4d  VRAM %7.1f MiB（纹 %6.1f / 缓 %6.1f）%s" % [
			_frames, st["mean"], st["sd"], st["uniq"], vram, tex, buf,
			"   ← **白屏**" if st["white"] else ""])
		if st["white"] and white_at < 0:
			white_at = _frames
			img.save_png(_out.path_join("white_%05d.png" % _frames))
			print("  >>> 白屏复现！图存到 %s" % _out.path_join("white_%05d.png" % _frames))
			break
		if _frames % (SAMPLE_EVERY * 8) == 0:
			img.save_png(_out.path_join("sample_%05d.png" % _frames))

	Input.action_release("move_forward")
	Input.action_release("move_back")

	print("\n========== 结果 ==========")
	if white_at >= 0:
		print("  ✘ 白屏复现于第 %d 帧（%.1f s）" % [white_at, white_at / 60.0])
	else:
		print("  ✔ 观察 %.0f s 没有白屏（最亮一次均值 %.1f）" % [SECONDS, worst])
	quit(0)


## 只采样中间区域（避开四角），返回均值 / 标准差 / 颜色种类 / 是否判为白屏
func _stats(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(w * 0.12)
	var x1 := int(w * 0.88)
	var y0 := int(h * 0.12)
	var y1 := int(h * 0.88)
	var step_x: int = maxi(1, (x1 - x0) / 40)
	var step_y: int = maxi(1, (y1 - y0) / 30)
	var n := 0
	var s := 0.0
	var s2 := 0.0
	var kinds := {}
	for y in range(y0, y1, step_y):
		for x in range(x0, x1, step_x):
			var c := img.get_pixel(x, y)
			# 按感知亮度加权
			var l: float = (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * 255.0
			s += l
			s2 += l * l
			n += 1
			var key := int(c.r * 255.0) * 65536 + int(c.g * 255.0) * 256 + int(c.b * 255.0)
			kinds[key] = true
	var mean := s / float(n)
	var var_ := maxf(0.0, s2 / float(n) - mean * mean)
	var sd := sqrt(var_)
	return {
		"mean": mean, "sd": sd, "uniq": kinds.size(),
		"white": mean > 250.0 and sd < 6.0,
	}

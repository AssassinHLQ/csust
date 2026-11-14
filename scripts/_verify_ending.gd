extends SceneTree
## 无窗验收：署名覆盖、演出时序、独占音轨与状态恢复。
## 实际终局信号接线在 _probe_final_phase.gd 验收。
const Ending := preload("res://scripts/ending_pv.gd")
const CreditsData := preload("res://scripts/credits.gd")
const MusicLib := preload("res://scripts/music.gd")
var passed := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var sections := CreditsData.ending_sections()
	var rendered := ""
	var titles := {}
	for section in sections:
		for row in section["rows"]:
			rendered += row["author"] + row["platform"]
			for title in row["titles"]:
				titles[title] = true
	_check(sections[0]["rows"][0]["author"] == "Kenney", "Kenney 第一")
	_check(sections[0]["rows"][1]["author"] == "Cup Nooble", "Cup Nooble 第二")
	for entry in CreditsData.ENTRIES:
		_check(titles.has(entry["title"]), "片尾覆盖：" + entry["title"])
	for author in ["PlayCanvas", "知天下 AI", "雷月夜", "SLNeil", "一个睿智", "ArchWiki"]:
		_check(rendered.contains(author), "补充作者与社区：" + author)
	var world := Node.new()
	root.add_child(world)
	var hud := CanvasLayer.new()
	world.add_child(hud)
	var hidden_hud := CanvasLayer.new()
	world.add_child(hidden_hud)
	hidden_hud.hide()
	var ending := Ending.new()
	world.add_child(ending)
	ending.start(world)
	ending.set_process(false)
	for i in 8:
		await process_frame
	_check(paused and MusicLib.is_held(), "片尾暂停战斗并压住房间 BGM")
	_check(not hud.visible and not hidden_hud.visible, "隐藏 HUD，原本隐藏的层保持隐藏")
	_check(ending.phase == Ending.Phase.VICTORY, "先显示拯救长沙理工大学")
	_check(ending._music.stream != null and not ending._music.playing, "胜利提示期间不提前开音乐")
	_check(absf(ending._music.stream.get_length() - 185.301) < 0.1, "指定 P98 完整音轨时长")
	_check(not (ending._music.stream as AudioStreamOggVorbis).loop, "片尾音轨不循环")
	ending.start(world)
	_check(ending.phase == Ending.Phase.VICTORY, "重复 start 不重启演出")
	ending.return_to_campus()
	_check(ending.phase == Ending.Phase.VICTORY, "战斗按键不提前跳过胜利提示")
	ending._advance(Ending.VICTORY_SECONDS)
	_check(ending.phase == Ending.Phase.FADE, "胜利提示停留4秒后才淡出")
	ending._advance(Ending.FADE_SECONDS * 0.5)
	_check(ending._black.color.a > 0.25 and ending._black.color.a < 1.0, "中间帧有渐黑过渡")
	ending._advance(Ending.FADE_SECONDS * 0.5)
	_check(ending.phase == Ending.Phase.CREDITS and ending._black.color.a == 1.0, "全黑后开始滚动")
	_check(ending._music.playing, "滚动时钢琴曲在播放")
	_check(root.disable_3d, "黑底片尾停止校园3D绘制")
	MusicLib.play("mondrian")
	_check(MusicLib.current().is_empty(), "延迟天空还原不能抢回校园 BGM")
	var first_y := ending._roll.position.y
	ending._advance(10.0)
	_check(ending._roll.position.y < first_y, "署名从下向上移动")
	_check(ending._roll_distance > Ending.PAGE.y + 2500, "实际文字排版后的完整滚动路程")
	_check(ending._roll.size.x <= 1080.1, "长作者名与作品名自动换行，不撑出画面")
	var fit_before := ending._page.scale.x
	root.content_scale_size = Vector2i(900, 1600)
	root.size = Vector2i(900, 1600)
	for i in 3:
		await process_frame
	_check(ending._page.scale.x < fit_before and ending._page.position.y > 0.0,
		"竖屏或窄窗口按比例居中，保留完整署名宽度")
	var speed := ending._roll_distance / ending._roll_duration
	print("[EndingTest] %.0f px / %.2f s = %.2f px/s" % [ending._roll_distance, ending._roll_duration, speed])
	_check(speed < 65.0, "滚动速度可读（720p 下小于65px/s）")
	var before := ending._roll.position.y
	ending._advance(0.5)
	_check(absf(before - ending._roll.position.y - speed * 0.5) < 0.1, "按真实秒匀速滚动")
	_check(ending._skip.visible, "播放5秒后才提供明确的跳过按钮")
	ending._advance(ending._roll_duration)
	_check(ending.phase == Ending.Phase.COMPLETE, "全部署名滚出后显示感谢与返回按钮")
	_check(ending._roll.position.y + ending._roll.size.y <= 0.1, "最后一行没有提前消失")
	ending.return_to_campus()
	ending._advance(1.5)
	await process_frame
	_check(not paused and not MusicLib.is_held(), "返回校园恢复暂停与音乐权限")
	_check(not root.disable_3d, "返回校园恢复3D绘制")
	_check(hud.visible and not hidden_hud.visible, "返回时精确恢复原 HUD 可见性")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "无窗验收不收鼠标")
	_check(MusicLib.current() == "mondrian", "通关后恢复校园曲，不重放 Boss 曲")
	world.queue_free()
	await process_frame
	# 场景意外切换也必须释放音乐独占与暂停，不把下一个场景锁死。
	var interrupted := Ending.new()
	root.add_child(interrupted)
	interrupted.start(interrupted)
	for i in 3:
		await process_frame
	interrupted.queue_free()
	await process_frame
	_check(not paused and not MusicLib.is_held(), "中断片尾也恢复世界与音乐状态")
	MusicLib.stop()
	# 让音频混音线程处理 stop，再关闭测试进程。
	await create_timer(0.2).timeout
	print("[EndingTest] %d 通过 / %d 失败" % [passed, failed])
	quit(1 if failed else 0)


func _check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
		print("[PASS] " + message)
	else:
		failed += 1
		print("[FAIL] " + message)

extends CanvasLayer
## 最终胜利后的黑底滚动署名。世界暂停，片尾使用独立的真实时间与音轨。

signal completed
signal returned

const CreditsData := preload("res://scripts/credits.gd")
const MusicLib := preload("res://scripts/music.gd")
const UiSkinLib := preload("res://scripts/ui_skin.gd")
const AUDIO := "res://assets/music/ending_theme.ogg"
const VICTORY_TEXT := "你拯救了长沙理工大学。"
const VICTORY_SECONDS := 4.0
const FADE_SECONDS := 4.5
const END_HOLD := 6.0
const PAGE := Vector2(1280, 720)

enum Phase { IDLE, VICTORY, FADE, CREDITS, COMPLETE, RETURN }
var phase := Phase.IDLE
var _elapsed := 0.0
var _roll_duration := 179.3
var _roll_distance := 0.0
var _last_usec := 0
var _started := false
var _owns_state := false
var _previous_pause := false
var _previous_music_hold := false
var _previous_mouse := Input.MOUSE_MODE_VISIBLE
var _previous_disable_3d := false
var _previous_music := ""
var _root: Control
var _page: Control
var _black: ColorRect
var _victory: VBoxContainer
var _roll: VBoxContainer
var _end_card: VBoxContainer
var _skip: Button
var _music: AudioStreamPlayer
var _hidden_layers: Array[CanvasLayer] = []


func start(world: Node, resume_track: String = "mondrian") -> void:
	if _started:
		return
	_started = true
	name = "EndingPV"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_previous_pause = get_tree().paused
	_previous_mouse = Input.mouse_mode
	_previous_disable_3d = get_viewport().disable_3d
	_previous_music_hold = MusicLib.is_held()
	_previous_music = resume_track
	_owns_state = true
	MusicLib.hold(true)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 战斗 HUD、开发浮层和设置菜单都不应穿过黑底。
	for node in world.find_children("*", "CanvasLayer", true, false):
		var canvas := node as CanvasLayer
		if canvas != self and canvas.visible:
			_hidden_layers.append(canvas)
			canvas.hide()
	_build()
	phase = Phase.VICTORY
	_last_usec = Time.get_ticks_usec()
	print("[EndingPV] 最终胜利：" + VICTORY_TEXT)
	# 容器排版完成后再计算总路程，保证最后一条署名也完整滚出画面。
	await get_tree().process_frame
	await get_tree().process_frame
	_roll_distance = PAGE.y + _roll.size.y
	if _music.stream != null:
		_roll_duration = maxf(_music.stream.get_length() - END_HOLD, 1.0)
	print("[EndingPV] 署名 %d 条 / 路程 %.0f px / %.1f s / %.1f px/s" % [
		CreditsData.ENTRIES.size(), _roll_distance, _roll_duration,
		_roll_distance / _roll_duration])


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_black = ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0, 0, 0, 0.25)
	_root.add_child(_black)
	_page = Control.new()
	_page.size = PAGE
	_page.clip_contents = true
	_root.add_child(_page)
	var font := UiSkinLib.ui_font()
	if font != null:
		var theme := Theme.new()
		theme.default_font = font
		_page.theme = theme
	_victory = VBoxContainer.new()
	_victory.position = Vector2(100, 285)
	_victory.size.x = 1080
	_victory.add_theme_constant_override("separation", 24)
	_page.add_child(_victory)
	_label(_victory, VICTORY_TEXT, 40, Color.WHITE)
	_label(_victory, "这一次，大家都能平安回去了。", 23, Color(0.82, 0.86, 0.9))
	_roll = VBoxContainer.new()
	_roll.position = Vector2(100, PAGE.y)
	_roll.size.x = 1080
	_roll.add_theme_constant_override("separation", 18)
	_page.add_child(_roll)
	_label(_roll, "爱丽丝梦游长理", 42, Color.WHITE)
	_label(_roll, "署名与致谢", 24, Color(0.75, 0.8, 0.86))
	_gap(_roll, 70)
	for section in CreditsData.ending_sections():
		_label(_roll, section["group"], 30, Color(0.94, 0.86, 0.65))
		_gap(_roll, 14)
		for row in section["rows"]:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 40)
			_roll.add_child(line)
			var works := _label(line, "\n".join(row["titles"]), 20, Color(0.68, 0.72, 0.78))
			works.custom_minimum_size.x = 425
			works.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var names := VBoxContainer.new()
			names.custom_minimum_size.x = 615
			line.add_child(names)
			var author := _label(names, row["author"], 24, Color.WHITE)
			author.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not String(row["platform"]).is_empty():
				var platform := _label(names, row["platform"], 18, Color(0.7, 0.76, 0.82))
				platform.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_gap(_roll, 48)
	_label(_roll, "免责声明", 28, Color(0.94, 0.86, 0.65))
	_label(_roll, CreditsData.DISCLAIMER, 23, Color(0.8, 0.82, 0.86))
	_gap(_roll, 80)
	_label(_roll, "也谢谢你，老师。", 36, Color.WHITE)
	_label(_roll, "感谢游玩", 24, Color(0.75, 0.8, 0.86))
	_gap(_roll, 60)
	_end_card = VBoxContainer.new()
	_end_card.position = Vector2(240, 265)
	_end_card.size.x = 800
	_end_card.add_theme_constant_override("separation", 28)
	_end_card.hide()
	_page.add_child(_end_card)
	_label(_end_card, "谢谢你，老师。", 40, Color.WHITE)
	_label(_end_card, "长沙理工大学，恢复了往日的宁静。", 23, Color(0.75, 0.8, 0.86))
	var back := Button.new()
	back.text = "返回校园"
	back.custom_minimum_size.y = 52
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(return_to_campus)
	_end_card.add_child(back)
	_skip = Button.new()
	_skip.text = "跳过片尾"
	_skip.position = Vector2(1080, 657)
	_skip.size = Vector2(150, 40)
	_skip.modulate.a = 0.55
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.hide()
	_skip.pressed.connect(_finish_credits)
	_page.add_child(_skip)
	_music = AudioStreamPlayer.new()
	_music.bus = "Master"
	_music.volume_db = -7.0
	add_child(_music)
	if ResourceLoader.exists(AUDIO):
		# 独立副本，不能改变资源缓存中的循环参数。
		_music.stream = (load(AUDIO) as AudioStream).duplicate()
		if _music.stream is AudioStreamOggVorbis:
			(_music.stream as AudioStreamOggVorbis).loop = false
	_layout()
	get_viewport().size_changed.connect(_layout)


func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _gap(parent: Node, height: float) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = height
	parent.add_child(space)


func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var fit := minf(viewport.x / PAGE.x, viewport.y / PAGE.y)
	_page.scale = Vector2.ONE * fit
	_page.position = (viewport - PAGE * fit) * 0.5


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var seconds := float(now - _last_usec) / 1000000.0
	_last_usec = now
	_advance(seconds)


## 以真实秒推进；F6 游戏倍速和帧率不改变片尾节奏。
func _advance(seconds: float) -> void:
	if phase == Phase.IDLE or phase == Phase.COMPLETE:
		return
	_elapsed += seconds
	match phase:
		Phase.VICTORY:
			if _elapsed >= VICTORY_SECONDS:
				_elapsed -= VICTORY_SECONDS
				phase = Phase.FADE
		Phase.FADE:
			var ratio := clampf(_elapsed / FADE_SECONDS, 0.0, 1.0)
			_black.color.a = lerpf(0.25, 1.0, smoothstep(0.0, 1.0, ratio))
			_victory.modulate.a = 1.0 - smoothstep(0.25, 0.95, ratio)
			if _elapsed >= FADE_SECONDS:
				_elapsed = 0.0
				phase = Phase.CREDITS
				_roll_distance = PAGE.y + _roll.get_combined_minimum_size().y
				_victory.hide()
				_roll.show()
				# 黑底正片期间停掉校园的3D绘制，保留滚动署名与音频。
				get_viewport().disable_3d = true
				Sfx.stop_all()
				if _music.stream != null:
					_music.play()
		Phase.CREDITS:
			_roll.position.y = PAGE.y - _roll_distance * minf(_elapsed / _roll_duration, 1.0)
			_skip.visible = _elapsed >= 5.0
			if _elapsed >= _roll_duration:
				_finish_credits()
		Phase.RETURN:
			_root.modulate.a = 1.0 - clampf(_elapsed / 1.5, 0.0, 1.0)
			if _elapsed >= 1.5:
				_restore_state()
				returned.emit()
				queue_free()


func _input(event: InputEvent) -> void:
	# 不让击杀时还按着的开火/空格误跳片尾，也不让 Esc 打开隐藏菜单。
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if phase == Phase.COMPLETE and event.is_action_pressed("ui_accept"):
			return_to_campus()
		get_viewport().set_input_as_handled()


func _finish_credits() -> void:
	if phase != Phase.CREDITS:
		return
	phase = Phase.COMPLETE
	_roll.hide()
	_skip.hide()
	_end_card.show()
	completed.emit()


func return_to_campus() -> void:
	if phase != Phase.COMPLETE:
		return
	phase = Phase.RETURN
	_elapsed = 0.0
	_music.stop()
	_end_card.hide()
	get_viewport().disable_3d = _previous_disable_3d
	for canvas in _hidden_layers:
		if is_instance_valid(canvas):
			canvas.show()
	print("[EndingPV] 返回校园")


func _restore_state() -> void:
	if not _owns_state:
		return
	_owns_state = false
	get_tree().paused = _previous_pause
	get_viewport().disable_3d = _previous_disable_3d
	MusicLib.hold(_previous_music_hold)
	if not _previous_music_hold and not _previous_music.is_empty():
		MusicLib.play(_previous_music)
	for canvas in _hidden_layers:
		if is_instance_valid(canvas):
			canvas.show()
	Input.mouse_mode = _previous_mouse
	# 后台探针/未聚焦窗口永远不能捕获鼠标。
	if OS.get_cmdline_user_args().has("--no-capture") or not DisplayServer.window_is_focused():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	_restore_state()

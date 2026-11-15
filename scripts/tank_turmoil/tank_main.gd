extends Node2D
## 坦克动荡 · 电竞房内置版
##
## ── 从原工程搬来做过的改动（2026-11-14）──
## 原工程在 `D:\BaiduNetdiskDownload\tank-turmoil`（独立游戏，自家 `project.godot`
## 里带 `[input]` 动作 + 自带歌单）。嵌进《爱丽丝梦游长理》当电竞房小游戏后，
## 下面几件事必须改掉，改在哪一条都写在对应常量/函数上方：
##   ① **输入**：不再读 `p1_*` / `p2_*` 动作（主工程 InputMap 里根本没有），
##      改成自己维护键位表 + `is_down()` 轮询，由宿主 `esports_arcade`（电竞房街机柜）把事件喂进来。
##   ② **歌单**：42 首 ogg 全部不搬（省 37.9 MB），音乐统一由电竞房 BGM 负责，
##      本脚本 `_ready()` 里把自己那个 `AudioStreamPlayer` 停掉；设置页的
##      「音乐」滑条和「背景曲目」入口整块删掉。
##   ③ **模式**：五人个人战，爱丽丝 / 才羽绿 / 柚子 / 才羽桃井 / 凯伊各自作战，
##      桃井和凯伊难度较低，四台 AI 按帧共享避弹预算。
##   ④ **地图**：默认 19 × 9，菜单可调 13~21 × 7~9。
##   ⑤ **开场视频**：不搬 `startup.ogv`（3.2 MB），直接跳过。
##   ⑥ **存档**：改到 `user://tank_turmoil.cfg`，不跟主工程进度混在一起。
##
## 原版 `main.gd` 里那些画 UI / 画特效的函数本脚本**原样保留**（那是别人的手笔），
## 只在必要处加注释说明为什么改。

class StaticMapLayer extends Node2D:
	var viewport_size := Vector2.ZERO
	var map_offset := Vector2.ZERO
	var board_rect := Rect2()
	var map_walls: Array[Rect2] = []
	var background_color := Color.BLACK
	var surface_color := Color.WHITE
	var wall_color := Color.WHITE
	var title_color := Color.WHITE

	func update_map(size: Vector2, offset: Vector2, rect: Rect2, new_walls: Array[Rect2], background: Color, surface: Color, wall: Color, text_color: Color) -> void:
		viewport_size = size
		map_offset = offset
		board_rect = rect
		map_walls = new_walls.duplicate()
		background_color = background
		surface_color = surface
		wall_color = wall
		title_color = text_color
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), background_color)
		draw_rect(Rect2(board_rect.position + map_offset, board_rect.size), surface_color)
		for wall in map_walls:
			draw_rect(Rect2(wall.position + map_offset, wall.size), wall_color)
		draw_string(ThemeDB.fallback_font, map_offset + Vector2(26, 43), "TANK  TROUBLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 25, title_color)

const W := 1000.0
const H := 800.0
const HUD := 72.0
## 手机触控那套常量原样留着（主工程是桌游，用不到，但删了要连带删一大片代码，
## 不划算；`mobile` 恒为 false，这些分支永远不进）。
const TOUCH_CONTROL_SCALE := 2.0
const TOUCH_JOYSTICK_RADIUS := 76.0 * TOUCH_CONTROL_SCALE
const TOUCH_JOYSTICK_KNOB_RADIUS := 30.0 * TOUCH_CONTROL_SCALE
const TOUCH_JOYSTICK_KNOB_TRAVEL := 43.0 * TOUCH_CONTROL_SCALE
const TOUCH_JOYSTICK_RESPONSE_RADIUS := 70.0 * TOUCH_CONTROL_SCALE
const TOUCH_JOYSTICK_INPUT_RADIUS := 100.0 * TOUCH_CONTROL_SCALE
const TOUCH_FIRE_RADIUS := 64.0 * TOUCH_CONTROL_SCALE
const TOUCH_FIRE_INPUT_RADIUS := 84.0 * TOUCH_CONTROL_SCALE
const MAX_OWN_NORMAL_BULLETS := 5
const LASER_SEARCH_RAYS_PER_FRAME := 8
## AI 预测的子弹上限。原版 3 / 2，五台同时在场时会撞帧，降到 2 / 1（见 `_set_ai_tier()`）。
var ai_max_predicted_bullets := 3
var ai_max_predicted_minigun_bullets := 2

## ── 地图（2026-11-14 用户：「稍微修改为五人模式大地图版本」）──
## 原来 11 × 7 是单人挑战的尺寸；五台坦克塞进去一开局就贴脸。
##
## 逻辑高度固定 800，宽度由宿主按窗口宽高比扩展。菜单以 W/H 为基准居中，
## 地图使用新增的宽度等比例增大方格，整张地图始终完整可见。
var CELL := 48.9
## 默认 19 × 9：五台坦克有地方散开，小游戏那点面积也塞得下。
var COLS := 19
var ROWS := 9
## 菜单里能调的范围。下限 13 × 7 是为了「五台不致于一出生就挤在一起」；上限卡在 21 × 9，
## 再大 `CELL` 会掉到 44 px 以下，坦克 28 px 长、墙 6 px 厚，观感就开始糊了。
const MAP_COLS_MIN := 13
const MAP_COLS_MAX := 21
const MAP_ROWS_MIN := 7
const MAP_ROWS_MAX := 9
var OX := 115.0
var OY := 129.0
const TANK_R := 12.0
const TANK_WIDTH := 20.0
const TANK_LENGTH := 28.0
const MUZZLE_OFFSET := TANK_LENGTH / 2.0 + 2.0
const WALL_T := 6.0
const BULLET_R := 2.5
const PORTRAIT_YUZU: Texture2D = preload("res://assets/tank_turmoil/characters/yuzu.png")
const PORTRAIT_MIDORI: Texture2D = preload("res://assets/tank_turmoil/characters/midori.png")
const PORTRAIT_MOMOI: Texture2D = preload("res://assets/tank_turmoil/characters/momoi.png")
const PORTRAIT_ALICE: Texture2D = preload("res://assets/tank_turmoil/characters/alice.png")
const PORTRAIT_KEI: Texture2D = preload("res://assets/tank_turmoil/characters/kei.png")
const PORTRAIT_YUUKA: Texture2D = preload("res://assets/tank_turmoil/characters/yuuka.png")
const SOUND_MOMOI_DEFEAT: AudioStream = preload("res://assets/tank_turmoil/sfx/momoi_defeat.ogg")
const SOUND_ALICE_VICTORY: AudioStream = preload("res://assets/tank_turmoil/sfx/alice_victory.ogg")

## ── 音乐：不搬 ──
## 用户 2026-11-14：「为了减少体积，不并入音乐，全程同步电竞房音乐」。
## 原工程 42 首 ogg 共 37.87 MB，全部**没有**复制进主工程；这里留空数组 +
## 一个静态曲目名，纯粹是为了让下面那些原版函数还能编译（它们只在歌单 UI 用到，
## 而歌单 UI 已经整块删掉了）。**别再往这里加 res:// 音乐路径** ——
## 那等于把 37.9 MB 又塞回来，还会和电竞房 BGM 抢播放器。
const IMPORTED_MUSIC_PATHS := []
## 界面上显示「音乐由电竞房负责」时用的名字（主工程 `music.gd` 里的逻辑名）。
const ROOM_MUSIC_TRACK := "esports"

## ── 存档 ──
## 原来写 `user://progress.cfg`，会和主工程自己的存档挤在同一个目录里，
## 而且键名（`unlocks` / `audio` / `appearance`）非常容易和别的配置撞。
const SAVE_PATH := "user://tank_turmoil.cfg"

var walls: Array[Rect2] = []
var maze_links := {}
var prediction_mask := PackedByteArray()
const MASK_SCALE := 3.0
var mask_width := 334
var mask_height := 267
var mask_origin := Vector2.ZERO
var tanks: Array[Dictionary] = []
var bullets: Array[Dictionary] = []
var laser_beams: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var pickup_timer := 0.0
var scores := [0, 0, 0, 0, 0]
var mode := 0 # 0 菜单 / 1 对战（唯一玩法） / 2 单人调试 / 3 BOSS 调试
var round_over := false
var paused := false
var round_message := ""
var mobile := false
var touch_move := Vector2.ZERO
var move_touch_id := -1
var fire_touch_id := -1
var mouse_joystick_active := false
var next_round_timer := 0.0
var countdown := 0.0
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
## 电脑数量。**不再是菜单可调项**：五人个人战固定 4 台 AI。
## 保留这个变量是因为原版一片代码都在读它（`needed` / 结算文案 / 菜单文字），
## 留着它 = 少改十几处，而且以后想加「三人 / 六人」只要在 `START_SETUPS` 里加一行。
var ai_count := 4
## 五台坦克的固定编制（顺序 = `tanks` 下标 0..4）。
## 下标 0 永远是玩家（爱丽丝），1..4 是四台 AI。
## 角色下标对应 `character_data()`：0 才羽绿 / 1 柚子 / 2 才羽桃井 / 3 爱丽丝 / 4 凯伊。
const START_SETUPS := [
	{"player": 3, "enemies": [0, 1, 2, 4],
		"label": "五人个人战 · 最后存活者获胜"},
]
var squad_clock := 0.0
var squad_phase := 0
## 本帧轮到哪一组 AI 做完整危险预测（见 `_set_ai_tier()` 里「拆组」那段）
var frame_squad := 0
var sound_shoot: AudioStreamWAV
var sound_bounce: AudioStreamWAV
var sound_explode: AudioStreamWAV
var sound_pickup: AudioStreamWAV
var sound_click: AudioStreamWAV
var music_player: AudioStreamPlayer
var intro_player: VideoStreamPlayer
var intro_backdrop: ColorRect
var intro_playing := true
var energy_saver_enabled := false
## 优香那套算法的**基准值**（2026-11-14 用户：「他们都用优香的算法，强一点」）。
##
## 原版里这些数**写在 `if is_boss:` 里面**（0.075 秒一次危险预测、12 个方向、36 步），
## 现在提到外面当基准 —— 四台 AI 一律按优香的档位跑，再按人数分摊（见 `_set_ai_tier()`）。
## `energy_saver_enabled`（省电模式）仍然在 `_set_ai_tier()` 里再打一次折。
const BOSS_DANGER_INTERVAL := 0.075
const BOSS_EVADE_DIRECTIONS := 12
const BOSS_EVADE_STEPS := 36
## 优香的移动 / 开火数值（原版散落在 `update_ai()` / `move_tank_direct()` 里）。
const BOSS_SPEED_CHASE := 120.0
const BOSS_SPEED_EVADE := 142.0
const BOSS_SPEED_PATH := 124.0
const BOSS_FIRE_TOLERANCE := 0.022
## 优香的一小段「机关枪」连射节拍（原版 `t.cooldown = 0.08`）。
const BOSS_MINIGUN_COOLDOWN := 0.08

## ── 当前生效值（由 `_set_ai_tier()` 每次开场重算）──
var ai_danger_interval := BOSS_DANGER_INTERVAL
var ai_evade_directions := BOSS_EVADE_DIRECTIONS
var ai_evade_steps := BOSS_EVADE_STEPS
var ai_speed_chase := BOSS_SPEED_CHASE
var ai_speed_evade := BOSS_SPEED_EVADE
var ai_speed_path := BOSS_SPEED_PATH
var ai_fire_tolerance := BOSS_FIRE_TOLERANCE
var ai_minigun_cooldown := BOSS_MINIGUN_COOLDOWN
## 四台 AI 拆成几组错峰。1 = 不拆（每帧四台都跑满）。
var ai_squads := 1
## 每帧最多几次「完整危险预测」。拆组后 = `ai_squads`，拆组前是 1。
var ai_danger_budget := 1
var ai_bank_budget := 1
var p1_character := 3
var p2_character := 1
## 原版「打赢 BOSS 才解锁优香」的进度位。五人模式里玩家就是爱丽丝，
## 优香不再是可选角色，这个开关只留给 `character_data()` 兜底，不再改。
var boss_character_unlocked := false
var local_setup_open := false
var settings_open := false
var pause_settings_open := false
var dark_mode := false
## ── 音量 ──
## `music_volume` 不再控制任何东西（歌单不搬了），只是 `apply_audio_levels()`
## 的入参还留着；宿主 `esports_arcade` 负责压电竞房 BGM。
var master_volume := 1.0
var sfx_volume := 1.0
var music_volume := 0.35
var music_index := 0
## 曲目名保留成 `MUSIC_NAMES[music_index]` 的兜底，一处都不再绘制（歌单 UI 已删）。
const MUSIC_NAMES := ["电竞房 BGM"]
var touch_height_index := 1
var touch_spacing_index := 1
var p2_touch_move := Vector2.ZERO
var p2_move_touch_id := -1
var p2_fire_touch_id := -1
var settings_slider_drag := -1
var settings_slider_touch_id := -1
var suppress_space_fire := false
var static_map_layer: StaticMapLayer

func _ready() -> void:
	rng.randomize()
	mobile = OS.has_feature("mobile")
	load_progress()
	refresh_power_profile()
	sound_shoot = make_sound(155.0, 0.12, 0.30, true)
	sound_bounce = make_sound(620.0, 0.075, 0.13, false)
	sound_explode = make_sound(68.0, 0.34, 0.38, true)
	sound_pickup = make_sound(680.0, 0.16, 0.20, false)
	sound_click = make_sound(420.0, 0.080, 0.14, false)
	# ⚠️ 不建 `music_player`：用户 2026-11-14「全程同步电竞房音乐」，
	#    小游戏自己一首都不放。BGM 由电竞房的 `esports_collision.gd::MusicZone`
	#    负责，宿主 `esports_arcade` 在小游戏开着时把它压低（见那边的 `_open()`）。
	static_map_layer = StaticMapLayer.new()
	static_map_layer.z_index = -1
	static_map_layer.visible = false
	add_child(static_map_layer)
	# 竞技场逻辑尺寸写死 1000 × 800，`view_offset()` 靠这个 viewport 的尺寸来居中。
	# 在 `game.tscn` 里本节点挂在 SubViewport 下，尺寸已经对了；但在编辑器和探针里
	# 独立加载时是 0，这时**自己开一个 1000 × 800 的 SubViewport**（项目级根窗口会被
	# 直接撑大，绝不能在宿主里那样干 —— 这就是为什么必须是 SubViewport）。
	if get_viewport().size.x < 100.0 or get_viewport().size.y < 100.0:
		_open_own_viewport()
		return
	get_viewport().size_changed.connect(resize_arena)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	apply_audio_levels()
	set_process(true)
	start_intro()
	queue_redraw()


## 独立加载 / 探针下的兜底：自己开一个 1000 × 800 的 SubViewport 把自己挪进去。
##
## ⚠️ 只接 `CanvasItem`（`RenderTextureRect` 之类）的连接，**不做 `remove_child(self)`**：
##    子节点自己的 `_ready()` 里从父节点拔自己，会撞上 Godot 的
##    「Parent node is busy adding/removing children」—— 实测报错并把节点变孤儿。
##    正确的做法是**由父节点在外部接手**（探针加载时自己塞进自己的 SubViewport，
##    主工程里 `game.tscn` 已经把它放在 `TankViewport` 下面）。这里只补 `size_changed`，
##    保证 `view_offset()` 能算出正确的居中偏移；尺寸真不对时打一条明确警告。
func _open_own_viewport() -> void:
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(refresh_static_map)
	print("[坦克] 注意：挂在非 1000×800 的 viewport 下（当前 %s），"
		% str(vp.size if vp != null else Vector2i.ZERO)
		+ "画面会按 `view_offset()` 居中；要满屏请放进 1000×800 的 SubViewport。")
	apply_audio_levels()
	set_process(true)
	start_intro()
	queue_redraw()


func start_intro() -> void:
	# 用户 2026-11-14：开场视频**不搬**（`assets/intro/startup.ogv`，3.23 MB）。
	# 直接走 `finish_intro()` —— 它会清掉 `intro_playing`，菜单随即接管输入。
	# 想恢复开场片：把 ogv 放进 `assets/tank_turmoil/intro/`，再把下面那行
	# `finish_intro(); return` 换成原来的 VideoStreamPlayer 那一段即可（原版代码
	# 在 git 历史里，本函数上方也留了说明）。
	finish_intro()


## 原版开场视频的实现（暂时不用，留着备查）：
##   intro_backdrop = ColorRect.new() … intro_player.stream = load("…/startup.ogv")
##   intro_player.z_index = 1000；intro_player.finished.connect(finish_intro)；play()

func finish_intro() -> void:
	intro_playing = false
	if intro_player != null and is_instance_valid(intro_player): intro_player.queue_free()
	if intro_backdrop != null and is_instance_valid(intro_backdrop): intro_backdrop.queue_free()
	queue_redraw()

func load_progress() -> void:
	var save := ConfigFile.new()
	if save.load(SAVE_PATH) == OK:
		dark_mode = bool(save.get_value("appearance", "dark_mode", false))
		master_volume = clampf(float(save.get_value("audio", "master", 1.0)), 0.0, 1.0)
		sfx_volume = clampf(float(save.get_value("audio", "sfx", 1.0)), 0.0, 1.0)
		COLS = clampi(int(save.get_value("map", "cols", COLS)), MAP_COLS_MIN, MAP_COLS_MAX)
		ROWS = clampi(int(save.get_value("map", "rows", ROWS)), MAP_ROWS_MIN, MAP_ROWS_MAX)
		touch_height_index = clampi(int(save.get_value("touch", "height", 1)), 0, 2)
		touch_spacing_index = clampi(int(save.get_value("touch", "spacing", 1)), 0, 2)
		# 迁移旧版写入的 80% / 85% 初始值；其余自定义音量照常保留。
		if not save.has_section_key("audio", "defaults_version") and is_equal_approx(master_volume, 0.8) and is_equal_approx(sfx_volume, 0.85):
			master_volume = 1.0
			sfx_volume = 1.0
			save_progress()

func save_progress() -> void:
	var save := ConfigFile.new()
	save.set_value("appearance", "dark_mode", dark_mode)
	save.set_value("audio", "master", master_volume)
	save.set_value("audio", "sfx", sfx_volume)
	save.set_value("audio", "defaults_version", 2)
	save.set_value("map", "cols", COLS)
	save.set_value("map", "rows", ROWS)
	save.set_value("touch", "height", touch_height_index)
	save.set_value("touch", "spacing", touch_spacing_index)
	var _save_error := save.save(SAVE_PATH)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Keep Android Back inside the game and open the in-game settings panel.
		if intro_playing:
			finish_intro()
		elif settings_open:
			settings_open = false
			queue_redraw()
		elif mode > 0:
			paused = true
			pause_settings_open = true
			queue_redraw()
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()

func refresh_power_profile() -> void:
	var saver := OS.has_feature("mobile")
	energy_saver_enabled = saver
	# ⚠️ 这里**只记「省不省电」**，不再直接改 AI 档位。
	#    原来的 `ai_danger_interval = 0.15 if saver else 0.12` 会把四台 AI 都压到
	#    比优香弱一档，和用户 2026-11-14 要求的「都用优香的算法」冲突。
	#    真正的档位由 `_set_ai_tier()` 算（它自己也看 `energy_saver_enabled`）。
	_set_ai_tier()


func make_sound(frequency: float, duration: float, volume: float, noisy: bool) -> AudioStreamWAV:
	var rate := 22050
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var time := float(i) / float(rate)
		var progress := float(i) / float(count)
		var envelope := minf(1.0, progress * 45.0) * pow(1.0 - progress, 1.15)
		var wave := sin(TAU * frequency * time) * 0.78 + sin(TAU * frequency * 2.0 * time) * 0.14 + sin(TAU * frequency * 0.5 * time) * 0.08
		if noisy: wave = wave * 0.90 + rng.randf_range(-1.0, 1.0) * 0.10
		bytes.encode_s16(i * 2, int(clampf(wave * envelope * volume, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream

## 原版「实时合成 6 首」的旋律生成器。歌单不搬之后**没有任何调用点**了；
## 留着是因为删掉它会连带删掉一大段 `MUSIC_NAMES` / `get_music_track()` 的引用，
## 而那两个函数在设置页删掉之后同样是死代码。真要清就一起清，别只删一半。
func make_music(track := 0) -> AudioStreamWAV:
	var rate := 22050
	var melodies := [
		[261.63, 329.63, 392.0, 523.25, 440.0, 392.0, 329.63, 293.66, 349.23, 440.0, 523.25, 659.25, 523.25, 440.0, 392.0, 329.63],
		[220.0, 0.0, 261.63, 293.66, 329.63, 0.0, 293.66, 246.94, 196.0, 0.0, 220.0, 261.63, 246.94, 220.0, 196.0, 0.0],
		[329.63, 392.0, 493.88, 392.0, 587.33, 493.88, 392.0, 329.63, 349.23, 440.0, 523.25, 440.0, 659.25, 523.25, 440.0, 392.0],
		[146.83, 174.61, 146.83, 220.0, 138.59, 164.81, 207.65, 174.61, 130.81, 155.56, 130.81, 196.0, 123.47, 146.83, 185.0, 155.56],
		[392.0, 440.0, 523.25, 659.25, 587.33, 523.25, 440.0, 392.0, 493.88, 587.33, 698.46, 783.99, 698.46, 587.33, 523.25, 440.0],
		[261.63, 392.0, 329.63, 523.25, 440.0, 659.25, 523.25, 783.99, 659.25, 523.25, 440.0, 392.0, 349.23, 329.63, 293.66, 261.63]
	]
	var steps := [0.42, 0.58, 0.30, 0.48, 0.34, 0.40]
	var safe_track := clampi(track, 0, melodies.size() - 1)
	var notes: Array = melodies[safe_track]
	var step_duration: float = steps[safe_track]
	var duration := float(notes.size()) * step_duration
	var count := int(duration * rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var time := float(i) / float(rate)
		var note_index := mini(notes.size() - 1, int(time / step_duration))
		var note_time := fmod(time, step_duration)
		var envelope := minf(1.0, note_time * 15.0) * clampf((step_duration - note_time) * 4.5, 0.0, 1.0)
		var frequency := float(notes[note_index])
		var base_wave := sin(TAU * frequency * time)
		if safe_track == 1: base_wave = sin(TAU * frequency * time) * 0.78 + sin(TAU * frequency * 2.0 * time) * 0.12
		elif safe_track == 2: base_wave = signf(sin(TAU * frequency * time)) * 0.46 + sin(TAU * frequency * 2.0 * time) * 0.22
		elif safe_track == 3: base_wave = sin(TAU * frequency * time) * 0.68 + signf(sin(TAU * frequency * 0.5 * time)) * 0.18
		elif safe_track == 4: base_wave = sin(TAU * frequency * time) * 0.70 + sin(TAU * frequency * 1.5 * time) * 0.20
		elif safe_track == 5: base_wave = sin(TAU * frequency * time) * 0.74 + sin(TAU * frequency * 3.0 * time) * 0.12
		var melody := base_wave * (0.082 if safe_track == 3 else 0.095)
		var bass_root := frequency * (0.25 if safe_track == 3 else 0.5)
		var bass := sin(TAU * bass_root * time) * (0.07 if safe_track == 3 else 0.045)
		var beat_interval := 0.24 if safe_track in [2, 4] else 0.48
		var beat_time := fmod(time, beat_interval)
		var beat := sin(TAU * (62.0 - beat_time * 65.0) * beat_time) * exp(-beat_time * 20.0) * (0.030 if safe_track != 1 else 0.012)
		bytes.encode_s16(i * 2, int(clampf((melody + bass) * envelope + beat, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	return stream

func select_music(direction: int) -> void:
	music_index = posmod(music_index + direction, MUSIC_NAMES.size())
	apply_audio_levels()
	save_progress()

func get_music_track(index: int) -> AudioStream:
	if index < 6: return make_music(index)
	if IMPORTED_MUSIC_PATHS.is_empty(): return null
	var path_index := clampi(index - 6, 0, IMPORTED_MUSIC_PATHS.size() - 1)
	var stream := load(IMPORTED_MUSIC_PATHS[path_index]) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	return stream

func choose_music(index: int) -> void:
	music_index = clampi(index, 0, MUSIC_NAMES.size() - 1)
	apply_audio_levels()
	save_progress()

## 小游戏自己的 BGM 已经没有了（`music_player` 从不创建）。
## 留着这个空函数是因为暂停菜单 / 设置页还有几处调用，删干净反而要动更多地方。
func apply_audio_levels() -> void:
	pass

func play_sound(stream: AudioStream, pitch := 1.0, gain_multiplier := 1.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = linear_to_db(maxf(0.0001, master_volume * sfx_volume * gain_multiplier)) - 3.0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func tank(pos: Vector2, angle: float, color: Color, name: String, portrait: Texture2D = null) -> Dictionary:
	return {"pos": pos, "angle": angle, "color": color, "name": name,
		"alive": true, "cooldown": 0.0, "ai_path": [], "ai_timer": 0.0,
		"danger_timer": 0.0, "danger_velocity": Vector2.ZERO,
		"reposition_timer": 0.0, "reposition_direction": Vector2.ZERO,
		"attack_angle": NAN, "role": 0, "weapon": "normal", "ammo": 0,
		"burst_remaining": 0, "burst_timer": 0.0, "burst_is_skill": false,
		"laser_solver_timer": 0.0, "laser_search_target": -1,
		"laser_search_target_pos": Vector2.ZERO, "laser_search_origin": Vector2.ZERO,
		"laser_search_next_degree": 0,
		"kei_rage": false, "motion_sample_pos": pos, "measured_velocity": Vector2.ZERO,
		"portrait": portrait, "boss": false, "boss_unit": false, "hp": 1, "max_hp": 1,
		"squad": 0}

func character_data(index: int) -> Dictionary:
	var names := ["才羽绿", "柚子", "才羽桃井", "爱丽丝", "凯伊", "优香"]
	var colors := [Color("46e6a7"), Color("ef476f"), Color("f78c2b"), Color("3979f6"), Color("f4f4f4"), Color("8e44d6")]
	var portraits := [PORTRAIT_MIDORI, PORTRAIT_YUZU, PORTRAIT_MOMOI, PORTRAIT_ALICE, PORTRAIT_KEI, PORTRAIT_YUUKA]
	var safe_index := posmod(index, names.size())
	return {"name": names[safe_index], "color": colors[safe_index], "portrait": portraits[safe_index]}

## 单人调试用的角色表上限（本地双人选人页已删，只剩 `mode == 2` 的调试路径读它）。
func selectable_character_count() -> int:
	return 5

func start_game(new_mode: int) -> void:
	mode = new_mode
	scores = [0, 0, 0, 0, 0]
	apply_map_size()
	_set_ai_tier()
	new_round()

## 五人自由混战：危险预测分两组错峰，每帧最多执行一次完整预测。
## 五人局使用 8 个方向、20 步；桃井与凯伊另由 ai_skill() 降低反应和命中率。
## 不在实时更新中穷举反弹射击角度，避免四台 AI 同时搜索造成长帧。
const FIVE_PLAYER_EVADE_SQUADS := 2
const FIVE_PLAYER_FUTURE_STEPS := 20

func _set_ai_tier() -> void:
	var enemies := maxi(1, tanks_enemy_count())
	ai_danger_interval = 0.12
	ai_evade_directions = 8
	ai_speed_chase = BOSS_SPEED_CHASE
	ai_speed_evade = BOSS_SPEED_EVADE
	ai_speed_path = BOSS_SPEED_PATH
	ai_fire_tolerance = BOSS_FIRE_TOLERANCE
	ai_minigun_cooldown = BOSS_MINIGUN_COOLDOWN
	ai_max_predicted_bullets = 2
	ai_max_predicted_minigun_bullets = 1
	if enemies >= 3:
		# 三台以上才开始拆组（单人 / 双人时拆组毫无必要，直接给满）
		ai_squads = FIVE_PLAYER_EVADE_SQUADS
		ai_evade_steps = FIVE_PLAYER_FUTURE_STEPS
	else:
		ai_squads = 1
		ai_evade_steps = BOSS_EVADE_STEPS
	if energy_saver_enabled:
		# 省电模式：原版是把每台都调弱；这里**只减采样**，不动速度 / 瞄准 / 方向数
		ai_evade_steps = maxi(18, ai_evade_steps - 6)
		ai_danger_interval = 0.18
	print("[坦克] AI 档位：个人战 · %d 台 · 预测 %.3fs/次 · %d 方向 × %d 步 · 拆 %d 组%s"
		% [enemies, ai_danger_interval, ai_evade_directions, ai_evade_steps, ai_squads,
			"（省电模式）" if energy_saver_enabled else ""])


## 本局有几台电脑（不含玩家）。菜单 / 开场前 `tanks` 是空的，就按编制算。
func tanks_enemy_count() -> int:
	if tanks.size() > 1:
		return tanks.size() - 1
	return START_SETUPS[0]["enemies"].size()

func apply_map_size() -> void:
	# Stretch mode expands the logical viewport on wide screens. Use that extra
	# width for the maze instead of leaving the old fixed 900 px playfield centered.
	var visible_size := get_viewport_rect().size
	var available_width := maxf(900.0, visible_size.x - 70.0)
	CELL = minf(70.0, minf(available_width / float(COLS), (H - HUD - 78.0) / float(ROWS)))
	OX = (W - COLS * CELL) / 2.0
	OY = HUD + (H - HUD - ROWS * CELL) / 2.0

func refresh_static_map() -> void:
	if static_map_layer == null:
		return
	static_map_layer.visible = mode > 0
	if mode == 0:
		return
	static_map_layer.update_map(
		get_viewport_rect().size,
		view_offset(),
		Rect2(OX, OY, COLS * CELL, ROWS * CELL),
		walls,
		ui_background(),
		ui_surface(),
		Color("8892a8") if dark_mode else Color("3b4355"),
		ui_text()
	)

## 保留同一局的地形和存活状态，窗口变宽时等比例放大迷宫。
func resize_arena() -> void:
	var old_origin := Vector2(OX, OY)
	var old_cell := CELL
	apply_map_size()
	if mode > 0 and old_cell > 0.0:
		var ratio := CELL / old_cell
		var origin := Vector2(OX, OY)
		for i in walls.size():
			walls[i] = Rect2(origin + (walls[i].position - old_origin) * ratio, walls[i].size * ratio)
		for collection in [tanks, bullets, pickups, particles]:
			for item in collection:
				item.pos = origin + (Vector2(item.pos) - old_origin) * ratio
		for beam in laser_beams:
			for i in beam.points.size():
				beam.points[i] = origin + (Vector2(beam.points[i]) - old_origin) * ratio
		build_prediction_mask()
	refresh_static_map()
	queue_redraw()

func new_round() -> void:
	apply_map_size()
	generate_maze()
	refresh_static_map()
	var needed: int = ai_count + 1 if mode == 1 else 2
	var spawn_cells: Array[Vector2i] = []
	while spawn_cells.size() < needed:
		var candidate := Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, ROWS - 1))
		var separated := true
		for occupied in spawn_cells:
			if Vector2(candidate - occupied).length_squared() < 4.0:
				separated = false
				break
		if separated: spawn_cells.append(candidate)
	# ── 编队 ──
	# `mode == 1`（对战）固定按 `START_SETUPS[0]`：0 号 = 爱丽丝（玩家），
	# 1..4 = 才羽绿 / 柚子 / 才羽桃井 / 凯伊（四台 AI）。
	# `mode == 2` 是留着的单人调试路径（一台 AI，角色取 `p2_character`）；
	# `mode == 3` 是原版的 BOSS 调试路径，**普通玩家进不去**（菜单已经没有这个按钮），
	# 保留是为了以后想复刻「优香三管血」时有现成代码。
	var setup: Dictionary = START_SETUPS[0]
	var player_character := p1_character if mode != 1 else int(setup["player"])
	var player_data: Dictionary = character_data(player_character)
	tanks = [tank(cell_center(spawn_cells[0]), rng.randf_range(0.0, TAU), player_data.color, player_data.name, player_data.portrait)]
	var enemy_ids: Array = []
	if mode == 1:
		enemy_ids = setup["enemies"]
	for i in range(1, needed):
		var enemy_color: Color
		var enemy_name: String
		var enemy_portrait: Texture2D
		if mode == 2:
			var second_player: Dictionary = character_data(p2_character)
			enemy_color = second_player.color
			enemy_name = second_player.name
			enemy_portrait = second_player.portrait
		elif mode == 3:
			enemy_color = Color("8e44d6")
			enemy_name = "优香"
			enemy_portrait = PORTRAIT_YUUKA
		else:
			var enemy_data: Dictionary = character_data(int(enemy_ids[i - 1]))
			enemy_color = enemy_data.color
			enemy_name = enemy_data.name
			enemy_portrait = enemy_data.portrait
		var enemy := tank(cell_center(spawn_cells[i]), rng.randf_range(0.0, TAU), enemy_color, enemy_name, enemy_portrait)
		enemy.boss = mode == 3
		# 「按优香那套跑」但不给三管血：四台满血优香玩家没得玩（见 `_set_ai_tier()`）。
		# `boss_unit` 才是「优香本人」的标记，只管数值和耐久，不影响 AI 档位。
		enemy.boss_unit = mode == 3
		if mode == 3:
			enemy.hp = 3
			enemy.max_hp = 3
		enemy.ai_timer = rng.randf_range(0.0, 0.5)
		# Evenly stagger expensive predictions instead of letting every AI spike on
		# the same frame. 五人版再按 `ai_squads` 分组错峰（见 `_set_ai_tier()`）。
		enemy.danger_timer = float(i - 1) * ai_danger_interval / float(maxi(1, needed - 1))
		# 0 追击 / 1 绕侧 / 2 卡点 / 3 原地压制 / 4 诱饵后撤 —— 五台各占一个，避免行为雷同
		enemy.role = (i - 1) % 5
		enemy.squad = (i - 1) % maxi(1, ai_squads)
		tanks.append(enemy)
	bullets.clear()
	laser_beams.clear()
	pickups.clear()
	pickup_timer = 3.0
	round_over = false
	paused = false
	round_message = ""
	next_round_timer = 0.0
	countdown = 2.8
	particles.clear()
	touch_move = Vector2.ZERO
	p2_touch_move = Vector2.ZERO
	p2_move_touch_id = -1
	p2_fire_touch_id = -1
	queue_redraw()

func generate_maze() -> void:
	var visited := {Vector2i.ZERO: true}
	var stack: Array[Vector2i] = [Vector2i.ZERO]
	var passages := {}
	while not stack.is_empty():
		var p: Vector2i = stack.back()
		var choices: Array[Vector2i] = []
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var q: Vector2i = p + d
			if q.x >= 0 and q.x < COLS and q.y >= 0 and q.y < ROWS and not visited.has(q):
				choices.append(q)
		if choices.is_empty():
			stack.pop_back()
		else:
			var q: Vector2i = choices[rng.randi_range(0, choices.size() - 1)]
			passages[edge_key(p, q)] = true
			visited[q] = true
			stack.append(q)
	for i in 18:
		var p: Vector2i = Vector2i(rng.randi_range(0, COLS - 1), rng.randi_range(0, ROWS - 1))
		var extra_dirs: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN]
		var q: Vector2i = p + extra_dirs[rng.randi_range(0, 1)]
		if q.x < COLS and q.y < ROWS:
			passages[edge_key(p, q)] = true
	maze_links = passages
	walls = [
		Rect2(OX, OY, COLS * CELL, WALL_T), Rect2(OX, OY + ROWS * CELL - WALL_T, COLS * CELL, WALL_T),
		Rect2(OX, OY, WALL_T, ROWS * CELL), Rect2(OX + COLS * CELL - WALL_T, OY, WALL_T, ROWS * CELL)
	]
	for y in ROWS:
		for x in COLS:
			var p := Vector2i(x, y)
			if x < COLS - 1 and not passages.has(edge_key(p, p + Vector2i.RIGHT)):
				walls.append(Rect2(OX + (x + 1) * CELL - WALL_T / 2.0, OY + y * CELL, WALL_T, CELL + WALL_T / 2.0))
			if y < ROWS - 1 and not passages.has(edge_key(p, p + Vector2i.DOWN)):
				walls.append(Rect2(OX + x * CELL, OY + (y + 1) * CELL - WALL_T / 2.0, CELL + WALL_T / 2.0, WALL_T))
	build_prediction_mask()

func build_prediction_mask() -> void:
	mask_origin = -view_offset()
	var visible_size := get_viewport_rect().size
	mask_width = maxi(1, ceili(visible_size.x / MASK_SCALE))
	mask_height = maxi(1, ceili(visible_size.y / MASK_SCALE))
	prediction_mask.resize(mask_width * mask_height)
	prediction_mask.fill(0)
	for wall in walls:
		var x1 := clampi(floori((wall.position.x - BULLET_R - mask_origin.x) / MASK_SCALE), 0, mask_width - 1)
		var y1 := clampi(floori((wall.position.y - BULLET_R - mask_origin.y) / MASK_SCALE), 0, mask_height - 1)
		var x2 := clampi(ceili((wall.end.x + BULLET_R - mask_origin.x) / MASK_SCALE), 0, mask_width - 1)
		var y2 := clampi(ceili((wall.end.y + BULLET_R - mask_origin.y) / MASK_SCALE), 0, mask_height - 1)
		for my in range(y1, y2 + 1):
			for mx in range(x1, x2 + 1): prediction_mask[my * mask_width + mx] = 1

func fast_wall(p: Vector2) -> bool:
	var mx := floori((p.x - mask_origin.x) / MASK_SCALE)
	var my := floori((p.y - mask_origin.y) / MASK_SCALE)
	if mx < 0 or mx >= mask_width or my < 0 or my >= mask_height: return true
	return prediction_mask[my * mask_width + mx] != 0

func edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var t := a; a = b; b = t
	return "%d,%d-%d,%d" % [a.x, a.y, b.x, b.y]

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(OX + (c.x + 0.5) * CELL, OY + (c.y + 0.5) * CELL)

func point_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x - OX) / CELL), 0, COLS - 1), clampi(int((p.y - OY) / CELL), 0, ROWS - 1))

func _process(delta: float) -> void:
	if mode > 0 and not paused and not round_over and countdown <= 0.0:
		if delta > 0.0:
			for fighter in tanks:
				fighter.measured_velocity = (Vector2(fighter.pos) - Vector2(fighter.motion_sample_pos)) / delta
				fighter.motion_sample_pos = fighter.pos
		if mode == 1 or mode == 3:
			squad_clock -= delta
			if squad_clock <= 0.0:
				squad_clock = 3.5
				squad_phase = (squad_phase + 1) % 4
		update_human(0, delta)
		if mode == 1 or mode == 3:
			# GDScript gameplay runs mainly on the main thread. Limiting each kind of
			# expensive calculation to one AI per frame removes single-core spikes.
			#
			# 两组轮换候选资格，共享每帧一次的危险预测预算。
			ai_danger_budget = 1
			ai_bank_budget = 0
			frame_squad = (frame_squad + 1) % maxi(1, ai_squads)
			# Yuzu receives the first available danger prediction each frame.
			for ai_index in range(1, tanks.size()):
				if str(tanks[ai_index].name) == "柚子": update_ai(ai_index, delta)
			for ai_index in range(1, tanks.size()):
				if str(tanks[ai_index].name) != "柚子": update_ai(ai_index, delta)
		else:
			update_human(1, delta)
		update_weapon_bursts(delta)
		update_bullets(delta)
		update_pickups(delta)
	if countdown > 0.0 and not paused:
		countdown -= delta
	update_particles(delta)
	if round_over and next_round_timer > 0.0:
		next_round_timer -= delta
	_clear_frame_presses()
	if mode > 0:
		queue_redraw()

## ── 输入（2026-11-14 重写）──
##
## 原版靠 `project.godot` 里那 10 个 `p1_*` / `p2_*` 输入动作轮询 `Input.get_action_strength()`。
## 搬进主工程之后：
##   · 主工程的 InputMap 里**没有**这些动作（`InputMap.has_action()` 为 false，
##     `get_action_strength()` 会直接报错并打印一片红字）；
##   · 就算注册进去，也会和主工程的 WASD / 空格 / 回车撞车（那是主角移动 / 跳 / 交互）；
##   · 而且小游戏是在 `SubViewport` 里跑的，窗口焦点在主工程那边，得由宿主**喂事件**。
##
## 所以这里改成：自维护一张键位表 + `is_down()` 轮询。
## 宿主（`esports_arcade`）在 `_using` 分支里把键盘事件转给本节点的 `feed()`。
## ⚠️ 用 `physical_keycode` 而不是 `keycode`：中文输入法开着时 `keycode` 会变成 `0`，
##    原版的 `project.godot` 里也全是 `physical_keycode`。
const P1_KEYS := {
	"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN],
	"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT],
	"fire": [KEY_SPACE, KEY_J, KEY_Z],
}
const P2_KEYS := {
	"forward": [KEY_UP], "back": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
	"fire": [KEY_ENTER, KEY_KP_ENTER],
}
## 本节点用到的「菜单键」。宿主看到这些键就别再转给终端/浏览器了。
const MENU_KEYS := [KEY_ESCAPE, KEY_P, KEY_SPACE, KEY_M, KEY_R, KEY_ENTER, KEY_KP_ENTER,
	KEY_1, KEY_2, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_W, KEY_A, KEY_S, KEY_D]
var _keys_down := {}
## 这一帧新按下的键（`feed()` 里进、`_process()` 里清）
var _keys_pressed := {}
## 鼠标左键当前按住没有（`mouse_joystick_active` 那套仍然沿用原版）
var _mouse_down := false

func feed(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null:
		var code := int(k.physical_keycode) if int(k.physical_keycode) != 0 else int(k.keycode)
		if code == 0:
			return
		if k.pressed:
			if not _keys_down.has(code):
				_keys_pressed[code] = true
			_keys_down[code] = true
		else:
			_keys_down.erase(code)
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_mouse_down = mb.pressed


## 宿主用：把**界面**那一路也走一遍。
##
## ⚠️ 以前宿主只调 `feed()`，结果整套菜单是**点不动**的：
##    菜单按键在 `_handle_menu_keys` 里、按钮点击在 `_handle_gameplay_mouse` 里，
##    两者原本挂在 `_unhandled_input` 上；本节点在主工程里装在
##    `SubViewport`（`handle_input_locally = false`）下，那两个回调永远不触发。
##    表现就是「能进菜单，但「开始对战」怎么点都没反应」。
##    `feed()` 只管键位表（玩法），所以界面必须单独喂这一口。
##
## 独立加载（探针 / 原工程）时没人调这个，`_input` / `_unhandled_input` 照旧生效，
## 两条路互不影响。
func ui_event(event: InputEvent) -> void:
	_handle_menu_keys(event)
	_handle_gameplay_mouse(event)

## ⚠️ 拼错键名 / 写错字不会报错，只会「点了没反应」—— 所以这里一并自检。
func is_down(action: String, player := 1) -> bool:
	var table := P1_KEYS if player == 1 else P2_KEYS
	if not table.has(action):
		push_warning("[坦克] 键位表里没有 `%s`（玩家 %d）" % [action, player])
		return false
	var codes: Array = table[action]
	for code in codes:
		if _keys_down.has(code):
			return true
	return false

func just_pressed(action: String, player := 1) -> bool:
	var table := P1_KEYS if player == 1 else P2_KEYS
	if not table.has(action):
		push_warning("[坦克] 键位表里没有 `%s`（玩家 %d）" % [action, player])
		return false
	var codes: Array = table[action]
	for code in codes:
		if _keys_pressed.has(code):
			return true
	return false

## ⚠️ `_keys_pressed` 必须每帧清空，否则「按一下 → 一直开火」。
##    `_process()` 处理完输入后调一次，菜单里也要清，免得攒着。
func _clear_frame_presses() -> void:
	_keys_pressed.clear()

## 宿主用：小游戏被关掉 / 暂停时把按键状态清干净，免得回到游戏里人还在跑。
func release_all() -> void:
	_keys_down.clear()
	_keys_pressed.clear()
	suppress_space_fire = false
	_mouse_down = false
	mouse_joystick_active = false
	touch_move = Vector2.ZERO


func shutdown() -> void:
	release_all()
	paused = true
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	process_mode = Node.PROCESS_MODE_DISABLED

func update_human(index: int, delta: float) -> void:
	if not tanks[index].alive: return
	var player := index + 1
	var drive := (1.0 if is_down("forward", player) else 0.0) - (1.0 if is_down("back", player) else 0.0)
	var turn := (1.0 if is_down("right", player) else 0.0) - (1.0 if is_down("left", player) else 0.0)
	var direct_control := false
	if index == 0 and (mobile or mouse_joystick_active):
		direct_control = true
		move_tank_direct(index, touch_move, delta)
	elif index == 1 and mobile and mode == 2:
		direct_control = true
		move_tank_direct(index, p2_touch_move, delta)
	elif index == 0:
		var keyboard_direction := Vector2(
			(1.0 if is_down("right", 1) else 0.0) - (1.0 if is_down("left", 1) else 0.0),
			(1.0 if is_down("back", 1) else 0.0) - (1.0 if is_down("forward", 1) else 0.0)
		).limit_length(1.0)
		if keyboard_direction.length_squared() > 0.0:
			direct_control = true
			move_tank_direct(index, keyboard_direction, delta)
	if not direct_control:
		move_tank(index, drive, turn, delta)
	tanks[index].cooldown = maxf(0.0, tanks[index].cooldown - delta)
	var blocked_space := index == 0 and suppress_space_fire and not (_keys_pressed.has(KEY_J) or _keys_pressed.has(KEY_Z))
	if just_pressed("fire", player) and not blocked_space:
		fire(index)

func move_tank_direct(index: int, stick: Vector2, delta: float, max_speed := 120.0) -> void:
	if not tanks[index].alive or stick.length() < 0.08: return
	var t := tanks[index]
	var strength := minf(stick.length(), 1.0)
	var direction := stick.normalized()
	var desired_angle := direction.angle()
	var old_angle: float = float(t.angle)
	t.angle = lerp_angle(float(t.angle), desired_angle, minf(1.0, delta * 13.0))
	if tank_hits_wall(t.pos, float(t.angle)) or tank_hits_other_tank(index, t.pos, float(t.angle)): t.angle = old_angle
	var motion := direction * strength * max_speed * delta
	var p: Vector2 = t.pos
	var steps := maxi(1, ceili(motion.length() / 4.0))
	var step := motion / float(steps)
	for i in steps:
		var candidate_x := Vector2(p.x + step.x, p.y)
		if not tank_hits_wall(candidate_x, float(t.angle)) and not tank_hits_other_tank(index, candidate_x, float(t.angle)): p.x += step.x
		var candidate_y := Vector2(p.x, p.y + step.y)
		if not tank_hits_wall(candidate_y, float(t.angle)) and not tank_hits_other_tank(index, candidate_y, float(t.angle)): p.y += step.y
	t.pos = p
	tanks[index] = t

func move_tank(index: int, drive: float, turn: float, delta: float, max_speed := 120.0) -> void:
	if not tanks[index].alive: return
	var t := tanks[index]
	var direction: float = 1.0 if absf(drive) < 0.05 or drive > 0.0 else -1.0
	var old_angle: float = float(t.angle)
	t.angle += turn * 2.7 * delta * direction
	if tank_hits_wall(t.pos, float(t.angle)) or tank_hits_other_tank(index, t.pos, float(t.angle)): t.angle = old_angle
	var motion := Vector2.from_angle(t.angle) * drive * max_speed * delta
	var p: Vector2 = t.pos
	var candidate_x := Vector2(p.x + motion.x, p.y)
	if not tank_hits_wall(candidate_x, float(t.angle)) and not tank_hits_other_tank(index, candidate_x, float(t.angle)): p.x += motion.x
	var candidate_y := Vector2(p.x, p.y + motion.y)
	if not tank_hits_wall(candidate_y, float(t.angle)) and not tank_hits_other_tank(index, candidate_y, float(t.angle)): p.y += motion.y
	t.pos = p
	tanks[index] = t

func ai_skill(index: int) -> float:
	match str(tanks[index].name):
		"才羽桃井": return 0.62
		"凯伊": return 0.70
	return 1.0

func ai_laser_skill(index: int) -> float:
	match str(tanks[index].name):
		"柚子": return 0.72
		"凯伊": return 0.58
	return ai_skill(index)

func update_ai(index: int, delta: float) -> void:
	if not tanks[index].alive: return
	var ai := tanks[index]
	var is_yuzu := str(ai.name) == "柚子"
	var is_midori := str(ai.name) == "才羽绿"
	var has_midori_laser := is_midori and str(ai.weapon) == "laser"
	var kei_rage := bool(ai.get("kei_rage", false))
	var movement_scale := 2.0 if kei_rage else 1.0
	var skill := ai_skill(index)
	var target_index := homing_target(index, ai.pos)
	if target_index < 0: return
	var opponent: Dictionary = tanks[target_index]
	ai.cooldown = maxf(0.0, ai.cooldown - delta)
	ai.danger_timer -= delta
	if is_yuzu and _yuzu_immediate_threat(index):
		ai.danger_timer = minf(float(ai.danger_timer), 0.0)
	# 预测错峰运行，每帧共享一次完整预算；低难度角色的反应间隔更长。
	var my_squad := int(ai.get("squad", 0))
	if ai.danger_timer <= 0.0 and ai_danger_budget > 0 and (is_yuzu or my_squad == frame_squad):
		ai.danger_timer = (0.035 if is_yuzu else ai_danger_interval) / (skill * skill)
		ai.danger_velocity = find_ai_evasion(ai.pos, float(ai.angle), index)
		ai_danger_budget -= 1
	var midori_laser_fired := false
	ai.laser_solver_timer = maxf(0.0, float(ai.get("laser_solver_timer", 0.0)) - delta)
	var laser_target_moved := int(ai.get("laser_search_target", -1)) != target_index or Vector2(ai.get("laser_search_target_pos", Vector2.ZERO)).distance_to(opponent.pos) > 64.0 or Vector2(ai.get("laser_search_origin", Vector2.ZERO)).distance_to(ai.pos) > 12.0
	if has_midori_laser and float(ai.cooldown) <= 0.0 and float(ai.reposition_timer) <= 0.0 and (float(ai.laser_solver_timer) <= 0.0 or laser_target_moved):
		tanks[index] = ai
		var laser_angle := find_laser_bank_angle(index, target_index)
		ai = tanks[index]
		if not is_nan(laser_angle):
			ai.angle = laser_angle
			tanks[index] = ai
			fire(index)
			ai = tanks[index]
			midori_laser_fired = true
		elif int(ai.get("laser_search_next_degree", 0)) > 0:
			tanks[index] = ai
			return
	# Fire at a visible opponent before moving or evading. Yuzu only uses the
	# instant normal-shot path; laser shots turn and fire at her imperfect aim.
	if not midori_laser_fired and ((is_midori and not has_midori_laser) or (kei_rage and str(ai.weapon) != "laser") or (is_yuzu and str(ai.weapon) != "laser")) and float(ai.cooldown) <= 0.0 and float(ai.reposition_timer) <= 0.0 and int(ai.burst_remaining) <= 0 and clear_line(ai.pos, opponent.pos):
		var shot_angle := (ai.pos as Vector2).angle_to_point(opponent.pos)
		var predicted_weapon := "minigun" if is_midori and str(ai.weapon) == "normal" else str(ai.weapon)
		var safe_angle := _safe_ai_aim(index, target_index, shot_angle, predicted_weapon)
		if is_nan(safe_angle):
			_reposition_after_unsafe_shot(index, shot_angle)
			ai = tanks[index]
		else:
			ai.angle = safe_angle
			if is_midori and str(ai.weapon) == "normal":
				ai.burst_remaining = 5
				ai.burst_timer = 0.0
				ai.burst_is_skill = false
				ai.cooldown = 0.48
				tanks[index] = ai
			else:
				tanks[index] = ai
				if not (is_yuzu and str(ai.weapon) == "normal" and Vector2(ai.danger_velocity).is_zero_approx() and not _yuzu_immediate_threat(index) and _yuzu_predictive_volley(index, target_index)):
					fire(index)
				ai = tanks[index]
				if not bool(opponent.alive) or round_over: return
	var evade_direction: Vector2 = ai.danger_velocity
	if evade_direction.length_squared() > 0.0:
		tanks[index] = ai
		move_tank_direct(index, evade_direction, delta, ai_speed_evade * movement_scale * (1.25 if is_yuzu else 1.0))
		return
	if float(ai.reposition_timer) > 0.0:
		ai.reposition_timer = maxf(0.0, float(ai.reposition_timer) - delta)
		tanks[index] = ai
		move_tank_direct(index, ai.reposition_direction, delta, ai_speed_path * movement_scale)
		return
	ai.ai_timer -= delta
	var has_sight: bool = clear_line(ai.pos, opponent.pos)
	var pickup_target := Vector2.ZERO
	var wants_pickup := false
	var wants_laser := false
	if is_midori and str(ai.weapon) != "laser":
		var nearest_laser_distance := INF
		for pickup in pickups:
			if str(pickup.kind) != "laser": continue
			var distance: float = (ai.pos as Vector2).distance_squared_to(pickup.pos)
			if distance < nearest_laser_distance:
				nearest_laser_distance = distance
				pickup_target = pickup.pos
				wants_pickup = true
				wants_laser = true
	if not wants_laser and str(ai.weapon) == "normal" and int(ai.burst_remaining) <= 0:
		var nearest_pickup_distance := INF
		for pickup in pickups:
			var pickup_position: Vector2 = pickup.pos
			var distance: float = (ai.pos as Vector2).distance_squared_to(pickup_position)
			if distance < nearest_pickup_distance:
				nearest_pickup_distance = distance
				pickup_target = pickup_position
				wants_pickup = true
	# A visible nearby opponent takes precedence over a distant pickup.
	if not wants_laser and has_sight and (kei_rage or (ai.pos as Vector2).distance_to(opponent.pos) < 320.0):
		wants_pickup = false
	var objective_cell := point_cell(pickup_target) if wants_pickup else tactical_cell(index)
	if ai.ai_timer <= 0.0 or int(ai.get("target_index", -1)) != target_index or ai.get("path_goal", Vector2i(-1, -1)) != objective_cell or (not ai.ai_path.is_empty() and ai.ai_path[0] != point_cell(ai.pos)):
		ai.ai_timer = 0.4 / skill
		ai.target_index = target_index
		if str(ai.weapon) == "laser" and (is_yuzu or str(ai.name) == "凯伊"):
			var laser_error := 0.075 if is_yuzu else 0.13
			ai.aim_bias = rng.randf_range(-laser_error, laser_error)
		else:
			ai.aim_bias = rng.randf_range(-0.22, 0.22) * (1.0 - skill)
		ai.path_goal = objective_cell
		ai.ai_path = find_path(point_cell(ai.pos), objective_cell)
		ai.attack_angle = NAN
	var target: Vector2 = pickup_target if wants_pickup else (opponent.pos if has_sight else cell_center(tactical_cell(index)))
	if ai.ai_path.size() > 1:
		if wants_pickup or not has_sight:
			var center := cell_center(ai.ai_path[0])
			var next := cell_center(ai.ai_path[1])
			var travel := (next - center).normalized()
			var offset: Vector2 = ai.pos - center
			var cross_track := absf(offset.cross(travel))
			target = center if cross_track > 4.0 else next
	var desired: float = (ai.pos as Vector2).angle_to_point(target) + float(ai.get("aim_bias", 0.0))
	if not wants_pickup and not has_sight and not is_nan(float(ai.attack_angle)): desired = float(ai.attack_angle)
	var diff: float = wrapf(desired - float(ai.angle), -PI, PI)
	var turn: float = clampf(diff * 3.2, -1.0, 1.0)
	var distance_to_player: float = ai.pos.distance_to(opponent.pos)
	var drive: float = 1.0 if absf(diff) < 0.9 else 0.15
	if not wants_pickup and not has_sight and not is_nan(float(ai.attack_angle)): drive = 0.0
	if has_sight and not wants_pickup:
		# Suppressors hold ground, bait units reverse, assault units close in.
		if int(ai.role) == 3: drive = 0.0
		elif int(ai.role) == 4 and distance_to_player < 230.0: drive = -0.75
		elif distance_to_player < 115.0: drive = 0.0
		if is_yuzu:
			var preferred := 180.0 if str(ai.weapon) == "shotgun" else 260.0
			drive = -0.8 if distance_to_player < preferred - 45.0 else (0.65 if distance_to_player > preferred + 45.0 else 0.0)
		elif is_midori:
			drive = 1.0 if distance_to_player > 135.0 else 0.0
	tanks[index] = ai
	if (wants_pickup or not has_sight) and is_nan(float(ai.attack_angle)):
		# Omnidirectional path following prevents rectangular tanks wedging at corners.
		move_tank_direct(index, (target - ai.pos).normalized(), delta, ai_speed_path * lerpf(0.65, 1.0, skill) * movement_scale)
	else:
		# 巡航速度取 chase / evade 的中间值（优香 120 / 142 ⇒ 136；原版普通 AI 是 120）
		# move_tank reverses steering while backing up; compensate when aiming.
		var steering := -turn if drive < -0.05 else turn
		var turn_scale := 0.48 if str(ai.weapon) == "laser" and (is_yuzu or str(ai.name) == "凯伊") else 1.0
		move_tank(index, drive, steering * skill * turn_scale, delta, (ai_speed_chase + ai_speed_evade) * 0.5 * lerpf(0.65, 1.0, skill) * movement_scale)
	ai = tanks[index]
	var player_angle: float = (ai.pos as Vector2).angle_to_point(opponent.pos as Vector2) + float(ai.get("aim_bias", 0.0))
	var firing_angle: float = player_angle if has_sight else float(ai.attack_angle)
	var aim_error: float = INF if is_nan(firing_angle) else absf(wrapf(firing_angle - float(ai.angle), -PI, PI))
	var fire_skill := ai_laser_skill(index) if str(ai.weapon) == "laser" else skill
	var fire_tolerance := lerpf(0.09, ai_fire_tolerance, fire_skill)
	if has_sight and aim_error < fire_tolerance and float(ai.cooldown) <= 0.0 and int(ai.burst_remaining) <= 0:
		if rng.randf() <= fire_skill and not circle_hits_wall(Vector2(ai.pos) + Vector2.from_angle(float(ai.angle)) * MUZZLE_OFFSET, BULLET_R):
			if is_midori and str(ai.weapon) == "normal" and int(ai.burst_remaining) <= 0:
				var safe_angle := _safe_ai_aim(index, target_index, float(ai.angle), "minigun")
				if not is_nan(safe_angle):
					ai.angle = safe_angle
					ai.burst_remaining = 5
					ai.burst_timer = 0.0
					ai.burst_is_skill = false
					ai.cooldown = 0.9
					tanks[index] = ai
				else:
					_reposition_after_unsafe_shot(index, float(ai.angle))
			else:
				fire(index)
		ai.cooldown = maxf(float(ai.cooldown), 0.12 if kei_rage else (0.28 if is_yuzu else 0.45 / skill))

func _yuzu_immediate_threat(index: int) -> bool:
	var ai: Dictionary = tanks[index]
	for bullet in bullets:
		if int(bullet.owner) == index and float(bullet.grace) > 0.0: continue
		var start: Vector2 = bullet.pos
		var end: Vector2 = start + Vector2(bullet.vel) * 0.35
		if segment_hits_tank_rect(start, end, ai.pos, float(ai.angle), BULLET_R + 5.0):
			return true
	return false

func _yuzu_predictive_volley(index: int, target_index: int) -> bool:
	var shooter: Dictionary = tanks[index]
	var target: Dictionary = tanks[target_index]
	var origin: Vector2 = shooter.pos
	var target_pos: Vector2 = target.pos
	var distance := origin.distance_to(target_pos)
	if distance < 200.0 or normal_bullet_count(index) > 0:
		return false
	var velocity: Vector2 = Vector2(target.get("measured_velocity", Vector2.ZERO)).limit_length(250.0)
	var forward := Vector2.from_angle(float(target.angle)) * maxf(velocity.length(), 100.0)
	if velocity.length() > 10.0: forward = velocity
	var error := (target_pos - origin).normalized().orthogonal() * (TANK_WIDTH * 0.6)
	var points := [target_pos, _yuzu_intercept(origin, target_pos, forward), _yuzu_intercept(origin, target_pos, -forward), target_pos + error, target_pos - error]
	var angles: Array[float] = []
	for point: Vector2 in points:
		var angle := origin.angle_to_point(point)
		if not clear_line(origin, point) or tank_hits_wall(origin, angle) or tank_hits_other_tank(index, origin, angle) or circle_hits_wall(origin + Vector2.from_angle(angle) * MUZZLE_OFFSET, BULLET_R) or not _ai_shot_safe(index, angle, "normal"):
			return false
		angles.append(angle)
	for angle in angles:
		bullets.append({"pos": origin + Vector2.from_angle(angle) * MUZZLE_OFFSET,
			"vel": Vector2.from_angle(angle) * 200.0, "owner": index, "life": 60.0,
			"grace": 0.24, "homing": false, "weapon": "normal", "bounces": 0, "kei_rage": false})
	shooter.angle = angles[0]
	shooter.cooldown = 0.34
	tanks[index] = shooter
	play_sound(sound_shoot, rng.randf_range(0.92, 1.08))
	return true

func _yuzu_intercept(origin: Vector2, target: Vector2, velocity: Vector2) -> Vector2:
	var offset := target - origin
	var a := velocity.length_squared() - 200.0 * 200.0
	var b := 2.0 * (offset.dot(velocity) - 200.0 * MUZZLE_OFFSET)
	var c := offset.length_squared() - MUZZLE_OFFSET * MUZZLE_OFFSET
	var time := INF
	if absf(a) < 0.001:
		if absf(b) > 0.001: time = -c / b
	else:
		var discriminant := b * b - 4.0 * a * c
		if discriminant >= 0.0:
			var root := sqrt(discriminant)
			for candidate in [(-b - root) / (2.0 * a), (-b + root) / (2.0 * a)]:
				if candidate > 0.0: time = minf(time, candidate)
	return target + velocity * time if is_finite(time) and time > 0.0 else target

func tactical_cell(index: int) -> Vector2i:
	var target_index := homing_target(index, tanks[index].pos)
	return point_cell(tanks[target_index].pos) if target_index >= 0 else point_cell(tanks[index].pos)

func find_laser_bank_angle(owner: int, target: int) -> float:
	if target < 0 or target >= tanks.size() or not tanks[target].alive: return NAN
	var shooter: Dictionary = tanks[owner]
	var origin: Vector2 = shooter.pos
	var destination: Vector2 = tanks[target].pos
	if int(shooter.get("laser_search_target", -1)) != target or Vector2(shooter.get("laser_search_target_pos", Vector2.ZERO)).distance_to(destination) > 64.0 or Vector2(shooter.get("laser_search_origin", Vector2.ZERO)).distance_to(origin) > 12.0:
		shooter.laser_search_target = target
		shooter.laser_search_target_pos = destination
		shooter.laser_search_origin = origin
		shooter.laser_search_next_degree = 0
		shooter.laser_solver_timer = 0.0
		tanks[owner] = shooter
	var direct := origin.angle_to_point(destination)
	if _laser_path_hits_target(owner, target, direct):
		shooter.laser_search_next_degree = 0
		tanks[owner] = shooter
		return direct
	for _ray_index in LASER_SEARCH_RAYS_PER_FRAME:
		var degrees := int(shooter.get("laser_search_next_degree", 0))
		if degrees >= 360:
			shooter.laser_search_next_degree = 0
			shooter.laser_solver_timer = 0.35
			tanks[owner] = shooter
			return NAN
		shooter.laser_search_next_degree = degrees + 1
		var candidate := deg_to_rad(float(degrees))
		if _laser_path_hits_target(owner, target, candidate):
			shooter.laser_search_next_degree = 0
			tanks[owner] = shooter
			return candidate
	if int(shooter.laser_search_next_degree) >= 360:
		shooter.laser_search_next_degree = 0
		shooter.laser_solver_timer = 0.35
	tanks[owner] = shooter
	return NAN

func _laser_path_hits_target(owner: int, target: int, angle: float) -> bool:
	var shooter: Dictionary = tanks[owner]
	var position: Vector2 = shooter.pos + Vector2.from_angle(angle) * (TANK_LENGTH / 2.0 + 2.0)
	var velocity := Vector2.from_angle(angle) * 2.0
	var bounces := 0
	var segment_start := position
	var segment_start_step := 0
	for step_index in 2600:
		var bounced := false
		if fast_wall(Vector2(position.x + velocity.x, position.y)): velocity.x *= -1.0; bounced = true
		if fast_wall(Vector2(position.x, position.y + velocity.y)): velocity.y *= -1.0; bounced = true
		if bounced:
			if step_index >= 12 and segment_hits_tank_rect(segment_start, position, tanks[target].pos, float(tanks[target].angle), 1.25):
				return _laser_path_hits_target_exact(owner, target, angle)
			bounces += 1
			if bounces >= 10: return false
			segment_start = position
			segment_start_step = step_index
		position += velocity
		if step_index - segment_start_step >= 3:
			if step_index >= 12 and segment_hits_tank_rect(segment_start, position, tanks[target].pos, float(tanks[target].angle), 1.25):
				return _laser_path_hits_target_exact(owner, target, angle)
			segment_start = position
			segment_start_step = step_index
	return false

func _laser_path_hits_target_exact(owner: int, target: int, angle: float) -> bool:
	var shooter: Dictionary = tanks[owner]
	var target_positions: Array[Vector2] = []
	var target_angles: Array[float] = []
	var target_indices: Array[int] = []
	for tank_index in tanks.size():
		if not tanks[tank_index].alive or _kei_protects_alice(owner, tank_index): continue
		target_positions.append(tanks[tank_index].pos)
		target_angles.append(float(tanks[tank_index].angle))
		target_indices.append(tank_index)
	var position: Vector2 = shooter.pos + Vector2.from_angle(angle) * (TANK_LENGTH / 2.0 + 2.0)
	var velocity := Vector2.from_angle(angle) * 2.0
	var bounces := 0
	for step_index in 2600:
		var bounced := false
		if fast_wall(Vector2(position.x + velocity.x, position.y)): velocity.x *= -1.0; bounced = true
		if fast_wall(Vector2(position.x, position.y + velocity.y)): velocity.y *= -1.0; bounced = true
		if bounced:
			bounces += 1
			if bounces >= 10: return false
		position += velocity
		for tank_slot in target_positions.size():
			var tank_index := target_indices[tank_slot]
			if tank_index == owner and step_index < 12: continue
			if position.distance_squared_to(target_positions[tank_slot]) > 500.0: continue
			if bullet_hits_tank_at(position, target_positions[tank_slot], target_angles[tank_slot], 1.25):
				return tank_index == target
	return false

func find_bank_angle(origin: Vector2, target: Vector2) -> float:
	var direct := origin.angle_to_point(target)
	if trajectory_miss_distance(origin, direct, target) <= 0.0 and trajectory_hits_target_real(origin, direct, target): return direct
	var best_angle := direct
	var best_miss := INF
	for degrees in range(0, 360, 6):
		var candidate := deg_to_rad(float(degrees))
		var miss := trajectory_miss_distance(origin, candidate, target)
		if miss < best_miss: best_miss = miss; best_angle = candidate
	for refinement in range(-12, 13):
		var candidate := best_angle + deg_to_rad(float(refinement) * 0.5)
		if trajectory_miss_distance(origin, candidate, target) <= 0.0 and trajectory_hits_target_real(origin, candidate, target): return candidate
	return NAN

func trajectory_hits_target_real(origin: Vector2, angle: float, target: Vector2) -> bool:
	var p := origin + Vector2.from_angle(angle) * MUZZLE_OFFSET
	var v := Vector2.from_angle(angle) * 2.5
	var bounce_count := 0
	for step_index in 1680:
		var bounced := false
		if circle_hits_wall(Vector2(p.x + v.x, p.y), BULLET_R): v.x *= -1.0; bounced = true
		if circle_hits_wall(Vector2(p.x, p.y + v.y), BULLET_R): v.y *= -1.0; bounced = true
		if bounced:
			bounce_count += 1
			if bounce_count >= 10: return false
		p += v
		if bullet_hits_tank_at(p, target, float(tanks[0].angle), BULLET_R): return true
		if step_index > 20 and bullet_hits_tank_at(p, origin, angle, BULLET_R): return false
	return false

func trajectory_miss_distance(origin: Vector2, angle: float, target: Vector2) -> float:
	var p := origin + Vector2.from_angle(angle) * MUZZLE_OFFSET
	var v := Vector2.from_angle(angle) * MASK_SCALE
	var closest := distance_to_tank_rect(p, target, float(tanks[0].angle)) - BULLET_R
	var bounce_count := 0
	for _step in 1400:
		var bounced := false
		if fast_wall(Vector2(p.x + v.x, p.y)): v.x *= -1.0; bounced = true
		if fast_wall(Vector2(p.x, p.y + v.y)): v.y *= -1.0; bounced = true
		if bounced:
			bounce_count += 1
			if bounce_count >= 10: break
		p += v
		var target_distance := distance_to_tank_rect(p, target, float(tanks[0].angle)) - BULLET_R
		closest = minf(closest, target_distance)
		if closest <= 0.0: return closest
		# Reject a solution that returns to the shooter before reaching the target.
		if _step > 18 and bullet_hits_tank_at(p, origin, angle, BULLET_R): return INF
	return closest

func friendly_in_line(owner: int, origin: Vector2, end: Vector2) -> bool:
	for i in range(1, tanks.size()):
		if i == owner or not tanks[i].alive: continue
		var segment := end - origin
		var length_squared := segment.length_squared()
		if length_squared <= 0.0: continue
		var t: float = (tanks[i].pos - origin).dot(segment) / length_squared
		if t <= 0.05 or t >= 0.95: continue
		if tanks[i].pos.distance_to(origin + segment * t) < TANK_R * 2.2: return true
	return false

func find_ai_evasion(ai_pos: Vector2, ai_angle: float, ai_index: int) -> Vector2:
	# Predict bullet and tank positions at the same moments. This prevents reacting
	# to harmless near misses and catches ricochets which arrive much later.
	const PREDICT_DT := 0.10
	# 方向数与预测步数由人数档位统一控制，运行资格由每帧预算控制。
	var evade_directions := ai_evade_directions
	var evade_step_count := ai_evade_steps
	var predict_steps := evade_step_count
	var trajectories: Array[Dictionary] = []
	var predicted_minigun_bullets := 0
	# Nearby incoming shots matter more than the oldest projectiles in the arena.
	var threats := bullets.duplicate()
	threats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.pos as Vector2).distance_squared_to(ai_pos) < (b.pos as Vector2).distance_squared_to(ai_pos))
	var limit := 4 if str(tanks[ai_index].name) == "柚子" else ai_max_predicted_bullets
	for bullet in threats:
		if trajectories.size() >= limit:
			break
		var owner := int(bullet.owner)
		if str(bullet.weapon) == "minigun":
			if predicted_minigun_bullets >= (2 if limit > ai_max_predicted_bullets else ai_max_predicted_minigun_bullets):
				continue
			predicted_minigun_bullets += 1
		# Friendly fire is enabled, so every projectile can be dangerous.
		var segments_by_step: Array = []
		var future: Vector2 = bullet.pos
		var velocity: Vector2 = bullet.vel
		var remaining_life: float = float(bullet.life)
		var bounce_count: int = int(bullet.bounces)
		for step_index in predict_steps:
			if remaining_life <= 0.0 or bounce_count >= 10: break
			var step_segments := PackedVector2Array()
			var travel := velocity.length() * PREDICT_DT
			var substeps := maxi(1, ceili(travel / MASK_SCALE))
			var sub_delta := PREDICT_DT / float(substeps)
			for _substep in substeps:
				var segment_start := future
				var motion := velocity * sub_delta
				var bounced := false
				if fast_wall(Vector2(future.x + motion.x, future.y)):
					velocity.x *= -1.0
					bounced = true
				if fast_wall(Vector2(future.x, future.y + motion.y)):
					velocity.y *= -1.0
					bounced = true
				if bounced: bounce_count += 1
				future += velocity * sub_delta
				step_segments.append(segment_start)
				step_segments.append(future)
			segments_by_step.append(step_segments)
			remaining_life -= PREDICT_DT
		trajectories.append({"segments": segments_by_step, "owner": owner, "grace": float(bullet.grace)})
	if trajectories.is_empty(): return Vector2.ZERO

	# First test standing still. Dodge only an actual predicted collision.
	var standing_safe := true
	for trajectory in trajectories:
		var steps: Array = trajectory.segments
		for step_index in steps.size():
			if int(trajectory.owner) == ai_index and (step_index + 1) * PREDICT_DT < float(trajectory.grace): continue
			var segments: PackedVector2Array = steps[step_index]
			for segment_index in range(0, segments.size(), 2):
				if segment_hits_tank_rect(segments[segment_index], segments[segment_index + 1], ai_pos, ai_angle, BULLET_R + 1.5):
					standing_safe = false
					break
			if not standing_safe: break
		if not standing_safe: break
	if standing_safe: return Vector2.ZERO

	# Score a full circle of escape routes. The winner maximizes the smallest
	# time-aligned clearance and is rejected if a wall blocks its movement.
	var best_direction := Vector2.ZERO
	var best_score := -INF
	for direction_index in evade_directions:
		var direction := Vector2.from_angle(TAU * float(direction_index) / float(evade_directions))
		var candidate_pos := ai_pos
		var candidate_angle := ai_angle
		var score := INF
		var blocked_steps := 0
		for step_index in evade_step_count:
			candidate_angle = lerp_angle(candidate_angle, direction.angle(), minf(1.0, PREDICT_DT * 13.0))
			var motion := direction * 126.0 * PREDICT_DT
			var old_pos := candidate_pos
			if not tank_hits_wall(Vector2(candidate_pos.x + motion.x, candidate_pos.y), candidate_angle): candidate_pos.x += motion.x
			if not tank_hits_wall(Vector2(candidate_pos.x, candidate_pos.y + motion.y), candidate_angle): candidate_pos.y += motion.y
			if candidate_pos.distance_squared_to(old_pos) < motion.length_squared() * 0.12: blocked_steps += 1
			for trajectory in trajectories:
				var steps: Array = trajectory.segments
				if step_index >= steps.size(): continue
				if int(trajectory.owner) == ai_index and (step_index + 1) * PREDICT_DT < float(trajectory.grace): continue
				var segments: PackedVector2Array = steps[step_index]
				for segment_index in range(0, segments.size(), 2):
					var segment_start: Vector2 = segments[segment_index]
					var segment_end: Vector2 = segments[segment_index + 1]
					var clearance := minf(
						distance_to_tank_rect(segment_start, candidate_pos, candidate_angle),
						distance_to_tank_rect(segment_end, candidate_pos, candidate_angle)
					) - BULLET_R
					if segment_hits_tank_rect(segment_start, segment_end, candidate_pos, candidate_angle, BULLET_R):
						clearance = -float(predict_steps - step_index) * 2.0
					score = minf(score, clearance)
		score -= float(blocked_steps) * 3.0
		# A tiny continuity bonus avoids switching between equally safe directions.
		var previous: Vector2 = tanks[ai_index].danger_velocity
		if previous.length_squared() > 0.0: score += direction.dot(previous.normalized()) * 1.5
		if score > best_score:
			best_score = score
			best_direction = direction
	return best_direction

func segment_hits_tank_rect(segment_start: Vector2, segment_end: Vector2, tank_pos: Vector2, tank_angle: float, radius: float) -> bool:
	# Transform the swept bullet segment into the tank's local coordinates, then
	# use a slab test against the rectangle expanded by the bullet radius.
	var forward := Vector2.from_angle(tank_angle)
	var side := forward.rotated(PI / 2.0)
	var start_relative := segment_start - tank_pos
	var end_relative := segment_end - tank_pos
	var local_start := Vector2(start_relative.dot(forward), start_relative.dot(side))
	var local_end := Vector2(end_relative.dot(forward), end_relative.dot(side))
	var segment_delta := local_end - local_start
	var half_size := Vector2(TANK_LENGTH / 2.0 + radius, TANK_WIDTH / 2.0 + radius)
	var enter_time := 0.0
	var exit_time := 1.0
	for axis in 2:
		var start_value: float = local_start[axis]
		var delta_value: float = segment_delta[axis]
		var half_extent: float = half_size[axis]
		if absf(delta_value) < 0.00001:
			if absf(start_value) > half_extent: return false
			continue
		var first_time := (-half_extent - start_value) / delta_value
		var second_time := (half_extent - start_value) / delta_value
		if first_time > second_time:
			var swap_time := first_time
			first_time = second_time
			second_time = swap_time
		enter_time = maxf(enter_time, first_time)
		exit_time = minf(exit_time, second_time)
		if enter_time > exit_time: return false
	return true

func ai_shot_safe(origin: Vector2, angle: float, target_pos: Vector2, target_angle: float) -> bool:
	# Fire only when the real ten-bounce path reaches the player before returning
	# to the shooter. Direct shots no longer bypass this check near a wall.
	var p := origin + Vector2.from_angle(angle) * MUZZLE_OFFSET
	var v := Vector2.from_angle(angle) * 3.0
	var bounce_count := 0
	for step_index in 1800:
		var bounced := false
		if circle_hits_wall(Vector2(p.x + v.x, p.y), BULLET_R): v.x *= -1.0; bounced = true
		if circle_hits_wall(Vector2(p.x, p.y + v.y), BULLET_R): v.y *= -1.0; bounced = true
		if bounced:
			bounce_count += 1
			if bounce_count >= 10: return false
		p += v
		if bullet_hits_tank_at(p, target_pos, target_angle, BULLET_R): return true
		if step_index > 18 and bullet_hits_tank_at(p, origin, angle, BULLET_R): return false
	return false

func _ai_shot_safe(owner: int, shot_angle: float, weapon: String) -> bool:
	# Predict a stationary shooter and current tank positions. The wall mask is
	# conservative; moving tanks and homing course changes remain unpredictable.
	var shooter: Dictionary = tanks[owner]
	var origin: Vector2 = shooter.pos
	var laser := weapon == "laser"
	var speed := 2.0 if laser else MASK_SCALE
	var muzzle := TANK_LENGTH / 2.0 + 2.0 if laser else MUZZLE_OFFSET
	var position := origin + Vector2.from_angle(shot_angle) * muzzle
	var velocity := Vector2.from_angle(shot_angle) * speed
	var bounces := 0
	var steps := 2600 if laser else 200
	var grace_steps := 12 if laser else (20 if weapon == "minigun" else 13)
	for step in steps:
		var bounced := false
		if fast_wall(Vector2(position.x + velocity.x, position.y)):
			velocity.x *= -1.0
			bounced = true
		if fast_wall(Vector2(position.x, position.y + velocity.y)):
			velocity.y *= -1.0
			bounced = true
		if bounced:
			bounces += 1
			if bounces >= 10: break
		position += velocity
		for i in tanks.size():
			if not tanks[i].alive or (i == owner and step < grace_steps): continue
			if _kei_protects_alice(owner, i): continue
			if bullet_hits_tank_at(position, tanks[i].pos, float(tanks[i].angle), 1.25 if laser else BULLET_R):
				return i != owner
	return true

func _safe_ai_aim(owner: int, target: int, desired: float, weapon: String) -> float:
	if target < 0 or target >= tanks.size() or not tanks[target].alive: return NAN
	var shooter: Dictionary = tanks[owner]
	var target_tank: Dictionary = tanks[target]
	var distance: float = (shooter.pos as Vector2).distance_to(target_tank.pos)
	var max_offset := minf(0.32, atan2(TANK_WIDTH * 0.35, maxf(distance, 1.0)))
	var target_angle := (shooter.pos as Vector2).angle_to_point(target_tank.pos)
	for angle in [desired, target_angle, target_angle - max_offset * 0.5, target_angle + max_offset * 0.5, target_angle - max_offset, target_angle + max_offset]:
		if tank_hits_wall(shooter.pos, angle) or tank_hits_other_tank(owner, shooter.pos, angle): continue
		var muzzle := Vector2(shooter.pos) + Vector2.from_angle(angle) * MUZZLE_OFFSET
		if circle_hits_wall(muzzle, BULLET_R): continue
		var end: Vector2 = shooter.pos + Vector2.from_angle(angle) * (distance + TANK_LENGTH)
		if not segment_hits_tank_rect(shooter.pos, end, target_tank.pos, float(target_tank.angle), BULLET_R): continue
		var safe := true
		var offsets := [-0.24, -0.12, 0.0, 0.12, 0.24] if weapon == "shotgun" else [0.0]
		for offset in offsets:
			if not _ai_shot_safe(owner, angle + float(offset), weapon):
				safe = false
				break
		if safe: return angle
	return NAN

func _reposition_after_unsafe_shot(index: int, angle: float) -> void:
	var ai := tanks[index]
	var side := Vector2.from_angle(angle + PI / 2.0)
	if tank_hits_wall(Vector2(ai.pos) + side * 20.0, float(ai.angle)):
		side = -side
	ai.reposition_direction = side
	ai.reposition_timer = 0.3
	tanks[index] = ai

func find_path(start: Vector2i, goal: Vector2i) -> Array:
	var queue: Array[Vector2i] = [start]
	var came := {start: start}
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		if p == goal: break
		for d: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var q: Vector2i = p + d
			if q.x < 0 or q.x >= COLS or q.y < 0 or q.y >= ROWS or came.has(q): continue
			if not cells_connected(p, q): continue
			came[q] = p; queue.append(q)
	var path: Array = []
	if not came.has(goal): return [start]
	var cur := goal
	while cur != start:
		path.push_front(cur); cur = came[cur]
	path.push_front(start)
	return path

func cells_connected(a: Vector2i, b: Vector2i) -> bool:
	# 使用迷宫生成时的通路图，寻路不再为每条边扫描全部墙体。
	return maze_links.has(edge_key(a, b))

func clear_line(a: Vector2, b: Vector2) -> bool:
	var direction := b - a
	for wall in walls:
		var expanded := wall.grow(5.0)
		var enter := 0.0
		var leave := 1.0
		for axis in 2:
			if absf(direction[axis]) < 0.00001:
				if a[axis] < expanded.position[axis] or a[axis] > expanded.end[axis]:
					enter = 2.0
					break
			else:
				var first := (expanded.position[axis] - a[axis]) / direction[axis]
				var second := (expanded.end[axis] - a[axis]) / direction[axis]
				enter = maxf(enter, minf(first, second))
				leave = minf(leave, maxf(first, second))
		if enter <= leave: return false
	return true

func ricochet_shot_available(origin: Vector2, angle: float, target: Vector2) -> bool:
	# Use a step smaller than the wall so tactical prediction cannot tunnel through it.
	var p := origin + Vector2.from_angle(angle) * MUZZLE_OFFSET
	var v := Vector2.from_angle(angle) * 3.0
	var bounced := false
	for _step_index in 280:
		if circle_hits_wall(Vector2(p.x + v.x, p.y), 5.0): v.x *= -1.0; bounced = true
		if circle_hits_wall(Vector2(p.x, p.y + v.y), 5.0): v.y *= -1.0; bounced = true
		p += v
		if bounced and p.distance_to(target) < TANK_R + 7.0: return true
	return false

func fire(index: int) -> void:
	if mode == 0 or round_over or paused or not tanks[index].alive: return
	var t := tanks[index]
	var kei_rage := bool(t.get("kei_rage", false))
	var weapon: String = t.weapon
	if t.cooldown > 0.0 or (not kei_rage and weapon == "normal" and normal_bullet_count(index) >= MAX_OWN_NORMAL_BULLETS): return
	if index > 0 and (mode == 1 or mode == 3):
		var target := homing_target(index, t.pos)
		if weapon == "laser" and str(t.name) == "才羽绿":
			if not _laser_path_hits_target(index, target, float(t.angle)): return
		elif weapon == "laser" and (str(t.name) == "柚子" or str(t.name) == "凯伊"):
			if not _ai_shot_safe(index, float(t.angle), "laser"): return
		else:
			var safe_angle := _safe_ai_aim(index, target, float(t.angle), weapon)
			if is_nan(safe_angle):
				_reposition_after_unsafe_shot(index, float(t.angle))
				return
			t.angle = safe_angle
			tanks[index] = t
	if weapon == "laser":
		fire_laser(index)
		play_sound(sound_shoot, 1.35)
		t.cooldown = 0.55
		t.ammo -= 1
		if t.ammo <= 0: t.weapon = "normal"
		tanks[index] = t
		return
	if weapon == "minigun":
		# 一次道具触发一小段自动弹幕，后续子弹由计时器依次发射。
		t.burst_remaining = 5
		t.burst_timer = 0.0
		t.burst_is_skill = true
		t.weapon = "normal"
		t.ammo = 0
		t.cooldown = 0.78
		tanks[index] = t
		return
	var shots := [0.0]
	var speed := 200.0
	var life := 60.0
	if kei_rage: life = 2.4
	var homing := false
	if weapon == "shotgun": shots = [-0.24, -0.12, 0.0, 0.12, 0.24]; speed = 185.0; life = 3.2
	elif weapon == "minigun": speed = 250.0; life = 2.4
	elif weapon == "homing": speed = 165.0; life = 9.0; homing = true
	if kei_rage: life = minf(life, 2.4)
	for spread in shots:
		var a: float = t.angle + float(spread)
		bullets.append({"pos": t.pos + Vector2.from_angle(a) * MUZZLE_OFFSET,
			"vel": Vector2.from_angle(a) * speed, "owner": index, "life": life, "grace": 0.24,
			"homing": homing, "weapon": weapon, "bounces": 0, "kei_rage": kei_rage})
	play_sound(sound_shoot, rng.randf_range(0.92, 1.08))
	if bool(t.boss_unit):
		t.cooldown = ai_minigun_cooldown if weapon == "minigun" else 0.20
	else:
		t.cooldown = 0.12 if kei_rage else (0.10 if weapon == "minigun" else 0.34)
	if weapon != "normal":
		t.ammo -= 1
		if t.ammo <= 0: t.weapon = "normal"
	tanks[index] = t

func normal_bullet_count(owner: int) -> int:
	var count := 0
	for bullet in bullets:
		if int(bullet.owner) == owner and str(bullet.weapon) in ["normal", "minigun"] and not bool(bullet.get("kei_rage", false)) and not bool(bullet.get("skill", false)):
			count += 1
	return count

func update_weapon_bursts(delta: float) -> void:
	for index in tanks.size():
		if not tanks[index].alive or int(tanks[index].burst_remaining) <= 0: continue
		var t := tanks[index]
		if not bool(t.get("burst_is_skill", false)) and not bool(t.get("kei_rage", false)) and normal_bullet_count(index) >= MAX_OWN_NORMAL_BULLETS:
			t.burst_remaining = 0
			tanks[index] = t
			continue
		t.burst_timer -= delta
		if float(t.burst_timer) <= 0.0:
			var spread := rng.randf_range(-0.035, 0.035)
			var angle: float = float(t.angle) + spread
			if index > 0 and (mode == 1 or mode == 3) and not _ai_shot_safe(index, angle, "minigun"):
				var target := homing_target(index, t.pos)
				var adjusted := _safe_ai_aim(index, target, float(t.angle), "minigun")
				if is_nan(adjusted) or not _ai_shot_safe(index, adjusted + spread, "minigun"):
					t.burst_remaining = 0
					tanks[index] = t
					_reposition_after_unsafe_shot(index, float(t.angle))
					continue
				t.angle = adjusted
				angle = adjusted + spread
			bullets.append({"pos": t.pos + Vector2.from_angle(angle) * MUZZLE_OFFSET,
				"vel": Vector2.from_angle(angle) * 250.0, "owner": index, "life": 2.4,
				"grace": 0.24, "homing": false, "weapon": "minigun", "bounces": 0,
				"kei_rage": bool(t.get("kei_rage", false)), "skill": bool(t.get("burst_is_skill", false))})
			t.burst_remaining -= 1
			t.burst_timer = 0.05 if str(t.name) == "才羽绿" else 0.085
			# 每隔一发播放音效，避免同时创建过多音频节点。
			if int(t.burst_remaining) % 2 == 0: play_sound(sound_shoot, rng.randf_range(1.15, 1.28))
		tanks[index] = t

func fire_laser(owner: int) -> void:
	var shooter := tanks[owner]
	var position: Vector2 = shooter.pos + Vector2.from_angle(float(shooter.angle)) * (TANK_LENGTH / 2.0 + 2.0)
	var velocity := Vector2.from_angle(float(shooter.angle)) * 2.0
	var points := PackedVector2Array([position])
	var bounce_count := 0
	for step_index in 2600:
		var bounced := false
		if circle_hits_wall(Vector2(position.x + velocity.x, position.y), 1.0): velocity.x *= -1.0; bounced = true
		if circle_hits_wall(Vector2(position.x, position.y + velocity.y), 1.0): velocity.y *= -1.0; bounced = true
		if bounced:
			points.append(position)
			bounce_count += 1
			if bounce_count >= 10: break
		position += velocity
		for tank_index in tanks.size():
			if not tanks[tank_index].alive: continue
			if _kei_protects_alice(owner, tank_index): continue
			if tank_index == owner and step_index < 12: continue
			if bullet_hits_tank_at(position, tanks[tank_index].pos, float(tanks[tank_index].angle), 1.25):
				points.append(position)
				tank_was_hit(tank_index)
				laser_beams.append({"points": points, "life": 0.14, "max_life": 0.14})
				return
	points.append(position)
	laser_beams.append({"points": points, "life": 0.14, "max_life": 0.14})

func update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		if b.homing:
			var target_index: int = homing_target(int(b.owner), b.pos)
			if target_index >= 0 and tanks[target_index].alive:
				var wanted: Vector2 = b.pos.direction_to(tanks[target_index].pos) * b.vel.length()
				b.vel = b.vel.lerp(wanted, minf(1.0, delta * 2.4))
		b.life -= delta; b.grace -= delta
		var hit := false
		# Sub-step fast projectiles so lasers and close-range shots cannot tunnel through walls.
		var travel: float = b.vel.length() * delta
		var substeps: int = maxi(1, ceili(travel / 3.0))
		var sub_delta: float = delta / float(substeps)
		for substep in substeps:
			var step: Vector2 = b.vel * sub_delta
			var p: Vector2 = b.pos
			var bounced := false
			if circle_hits_wall(Vector2(p.x + step.x, p.y), BULLET_R):
				b.vel.x *= -1.0; bounced = true
			if circle_hits_wall(Vector2(p.x, p.y + step.y), BULLET_R):
				b.vel.y *= -1.0; bounced = true
			if bounced:
				b.bounces += 1
				play_sound(sound_bounce, rng.randf_range(0.9, 1.15))
			b.pos += b.vel * sub_delta
			for ti in tanks.size():
				if not tanks[ti].alive: continue
				if _kei_protects_alice(int(b.owner), ti): continue
				if ti == b.owner and b.grace > 0.0: continue
				# Full friendly fire: department projectiles can hit any teammate.
				if bullet_hits_tank_at(b.pos, tanks[ti].pos, float(tanks[ti].angle), BULLET_R):
					tank_was_hit(ti); hit = true; break
			if hit: break
		if hit or b.life <= 0.0 or int(b.bounces) >= 10: bullets.remove_at(i)
		else: bullets[i] = b

func homing_target(owner: int, bullet_pos: Vector2) -> int:
	var result := -1
	var closest := INF
	for i in tanks.size():
		if i != owner and tanks[i].alive and not _kei_protects_alice(owner, i) and bullet_pos.distance_squared_to(tanks[i].pos) < closest:
			closest = bullet_pos.distance_squared_to(tanks[i].pos); result = i
	return result

func _kei_protects_alice(owner: int, target: int) -> bool:
	return owner >= 0 and owner < tanks.size() and target >= 0 and target < tanks.size() and str(tanks[owner].name) == "凯伊" and str(tanks[target].name) == "爱丽丝"

func update_pickups(delta: float) -> void:
	pickup_timer -= delta
	if pickup_timer <= 0.0 and pickups.size() < 2:
		pickup_timer = rng.randf_range(5.0, 8.0)
		var c := Vector2i(rng.randi_range(1, COLS - 2), rng.randi_range(1, ROWS - 2))
		var kinds := ["shotgun", "laser", "minigun", "homing"]
		pickups.append({"pos": cell_center(c), "kind": kinds[rng.randi_range(0, kinds.size() - 1)]})
	for pi in range(pickups.size() - 1, -1, -1):
		for ti in tanks.size():
			if tanks[ti].alive and tanks[ti].pos.distance_to(pickups[pi].pos) < TANK_R + 16.0:
				var t := tanks[ti]
				t.weapon = pickups[pi].kind
				# 每个道具只提供一次特殊攻击，发射后自动恢复普通攻击。
				t.ammo = 1
				tanks[ti] = t
				play_sound(sound_pickup, rng.randf_range(0.96, 1.08))
				pickups.remove_at(pi)
				break

func tank_was_hit(index: int) -> void:
	if round_over: return
	if not tanks[index].alive: return
	if int(tanks[index].hp) > 1:
		tanks[index].hp -= 1
		spawn_armor_hit(tanks[index].pos, tanks[index].color)
		return
	tanks[index].alive = false
	if mode == 1 and str(tanks[index].name) == "爱丽丝":
		for fighter in tanks:
			if str(fighter.name) == "凯伊" and bool(fighter.alive):
				fighter.kei_rage = true
				fighter.cooldown = 0.0
	var defeat_sound: AudioStream = SOUND_MOMOI_DEFEAT if str(tanks[index].name) == "才羽桃井" else null
	spawn_explosion(tanks[index].pos, tanks[index].color, defeat_sound)
	var survivors: Array[int] = []
	for i in tanks.size():
		if tanks[i].alive: survivors.append(i)
	if survivors.size() > 1: return
	round_over = true
	if survivors.is_empty():
		round_message = "平局"
	else:
		var winner := survivors[0]
		scores[winner] += 1
		round_message = "%s获胜！" % tanks[winner].name
		if str(tanks[winner].name) == "爱丽丝":
			play_sound(SOUND_ALICE_VICTORY)
	next_round_timer = 0.45

func spawn_armor_hit(pos: Vector2, color: Color) -> void:
	play_sound(sound_bounce, 0.65)
	for i in 14:
		var angle := rng.randf_range(0.0, TAU)
		particles.append({"pos": pos, "vel": Vector2.from_angle(angle) * rng.randf_range(45.0, 150.0),
			"life": rng.randf_range(0.18, 0.45), "max_life": 0.45,
			"color": color if i % 2 else Color("ffffff")})

func spawn_explosion(pos: Vector2, color: Color, defeat_sound: AudioStream = null) -> void:
	if defeat_sound != null: play_sound(defeat_sound)
	else: play_sound(sound_explode, rng.randf_range(0.88, 1.05))
	for i in 26:
		var a := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(55.0, 230.0)
		particles.append({"pos": pos, "vel": Vector2.from_angle(a) * speed,
			"life": rng.randf_range(0.35, 0.9), "max_life": 0.9,
			"color": color if i % 3 else Color("ffad33")})

func update_particles(delta: float) -> void:
	for beam_index in range(laser_beams.size() - 1, -1, -1):
		laser_beams[beam_index].life -= delta
		if laser_beams[beam_index].life <= 0.0: laser_beams.remove_at(beam_index)
	for i in range(particles.size() - 1, -1, -1):
		particles[i].pos += particles[i].vel * delta
		particles[i].vel *= pow(0.04, delta)
		particles[i].life -= delta
		if particles[i].life <= 0.0: particles.remove_at(i)

func distance_to_tank_rect(point: Vector2, tank_pos: Vector2, tank_angle: float) -> float:
	var forward := Vector2.from_angle(tank_angle)
	var side := forward.rotated(PI / 2.0)
	var relative := point - tank_pos
	var local := Vector2(relative.dot(forward), relative.dot(side))
	var nearest := Vector2(
		clampf(local.x, -TANK_LENGTH / 2.0, TANK_LENGTH / 2.0),
		clampf(local.y, -TANK_WIDTH / 2.0, TANK_WIDTH / 2.0)
	)
	return local.distance_to(nearest)

func bullet_hits_tank_at(bullet_pos: Vector2, tank_pos: Vector2, tank_angle: float, radius: float) -> bool:
	return distance_to_tank_rect(bullet_pos, tank_pos, tank_angle) <= radius

func tank_hits_wall(pos: Vector2, angle: float) -> bool:
	var forward := Vector2.from_angle(angle)
	var side := forward.rotated(PI / 2.0)
	var extent := Vector2(absf(forward.x) * TANK_LENGTH + absf(side.x) * TANK_WIDTH, absf(forward.y) * TANK_LENGTH + absf(side.y) * TANK_WIDTH) * 0.5
	var bounds := Rect2(pos - extent, extent * 2.0).grow(0.001)
	for wall in walls:
		if not bounds.intersects(wall, true): continue
		var wall_center := wall.get_center()
		var wall_half := wall.size / 2.0
		var center_delta := wall_center - pos
		var overlaps := true
		for axis in [Vector2.RIGHT, Vector2.DOWN, forward, side]:
			var tank_radius := absf(axis.dot(forward)) * TANK_LENGTH / 2.0 + absf(axis.dot(side)) * TANK_WIDTH / 2.0
			var wall_radius := absf(axis.x) * wall_half.x + absf(axis.y) * wall_half.y
			if absf(center_delta.dot(axis)) > tank_radius + wall_radius:
				overlaps = false
				break
		if overlaps: return true
	return false

func tank_hits_other_tank(tank_index: int, candidate_pos: Vector2, candidate_angle: float) -> bool:
	for other_index in tanks.size():
		if other_index == tank_index or not tanks[other_index].alive: continue
		if oriented_tanks_overlap(candidate_pos, candidate_angle, tanks[other_index].pos, float(tanks[other_index].angle)):
			return true
	return false

func oriented_tanks_overlap(pos_a: Vector2, angle_a: float, pos_b: Vector2, angle_b: float) -> bool:
	var forward_a := Vector2.from_angle(angle_a)
	var side_a := forward_a.rotated(PI / 2.0)
	var forward_b := Vector2.from_angle(angle_b)
	var side_b := forward_b.rotated(PI / 2.0)
	var center_delta := pos_b - pos_a
	for axis in [forward_a, side_a, forward_b, side_b]:
		var radius_a := absf(axis.dot(forward_a)) * TANK_LENGTH / 2.0 + absf(axis.dot(side_a)) * TANK_WIDTH / 2.0
		var radius_b := absf(axis.dot(forward_b)) * TANK_LENGTH / 2.0 + absf(axis.dot(side_b)) * TANK_WIDTH / 2.0
		if absf(center_delta.dot(axis)) >= radius_a + radius_b: return false
	return true

func circle_hits_wall(p: Vector2, radius: float) -> bool:
	for r in walls:
		var nearest := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		if p.distance_squared_to(nearest) < radius * radius: return true
	return false

func _input(event: InputEvent) -> void:
	# 主工程里本节点挂在 SubViewport 下面，正常情况下宿主会调 `feed()` 喂事件；
	# 独立加载（探针）时没人喂，这里接一下，保证两条路都能操作。
	feed(event)
	_handle_gameplay_mouse(event)

func _unhandled_input(event: InputEvent) -> void:
	_handle_menu_keys(event)
	_handle_gameplay_mouse(event)

func _handle_menu_keys(event: InputEvent) -> void:
	var key := event as InputEventKey
	var code := int(key.physical_keycode) if key != null and key.physical_keycode != 0 else (int(key.keycode) if key != null else 0)
	if intro_playing:
		# Permit a tap/click/Space to skip the startup video on touch devices too.
		var skip_intro: bool = (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed) or (key != null and key.pressed and not key.echo and (code == KEY_SPACE or code == KEY_ESCAPE))
		if skip_intro:
			finish_intro()
		return
	if key != null and code == KEY_SPACE and not key.pressed:
		suppress_space_fire = false
	if key != null and key.pressed and not key.echo:
		if code == KEY_ESCAPE and pause_settings_open:
			pause_settings_open = false
			queue_redraw()
		elif code == KEY_SPACE and countdown > 0.0:
			suppress_space_fire = true
			countdown = 0.0
			queue_redraw()
		elif code == KEY_SPACE and round_over and next_round_timer <= 0.0: new_round()
		elif code == KEY_1: start_game(1)
		elif code == KEY_2: start_game(2)
		elif (code == KEY_ESCAPE or code == KEY_P) and mode > 0: paused = not paused
		elif code == KEY_M and paused: return_to_menu()
		elif code == KEY_R and mode > 0: scores = [0, 0, 0, 0, 0]; new_round()

func _handle_gameplay_mouse(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		handle_touch(event.index, event.position - view_offset(), event.pressed)
	elif event is InputEventScreenDrag:
		var drag_pos: Vector2 = event.position - view_offset()
		if settings_active() and event.index == settings_slider_touch_id and settings_slider_drag >= 0:
			update_audio_slider(settings_slider_drag, drag_pos.x)
		elif event.index == move_touch_id:
			touch_move = ((drag_pos - p1_move_center()) / TOUCH_JOYSTICK_RESPONSE_RADIUS).limit_length(1.0)
		elif event.index == p2_move_touch_id:
			p2_touch_move = ((drag_pos - p2_move_center()) / TOUCH_JOYSTICK_RESPONSE_RADIUS).limit_length(1.0)
	elif event is InputEventMouseMotion and not mobile:
		var mouse_pos: Vector2 = event.position - view_offset()
		if settings_active() and settings_slider_drag >= 0:
			update_audio_slider(settings_slider_drag, mouse_pos.x)
		elif mouse_joystick_active:
			touch_move = ((mouse_pos - p1_move_center()) / TOUCH_JOYSTICK_RESPONSE_RADIUS).limit_length(1.0)
	elif event is InputEventMouseButton and not mobile:
		var mouse_pos: Vector2 = event.position - view_offset()
		if event.button_index == MOUSE_BUTTON_LEFT and settings_active():
			if event.pressed:
				handle_settings_press(mouse_pos)
			elif settings_slider_drag >= 0:
				settings_slider_drag = -1
				save_progress()
			return
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and mode > 0:
			fire(0)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and paused:
				handle_pause_press(mouse_pos)
			elif event.pressed:
				if mode == 0:
					handle_menu_press(mouse_pos)
				elif round_over and Rect2(190, 300, 620, 170).has_point(mouse_pos) and next_round_timer <= 0.0:
					new_round()

func handle_touch(id: int, pos: Vector2, pressed: bool) -> void:
	if settings_active():
		if pressed:
			var slider_index := audio_slider_at(pos)
			if slider_index >= 0:
				settings_slider_drag = slider_index
				settings_slider_touch_id = id
				update_audio_slider(slider_index, pos.x)
			else:
				handle_settings_press(pos)
		elif id == settings_slider_touch_id:
			settings_slider_drag = -1
			settings_slider_touch_id = -1
			save_progress()
		return
	if mode == 0:
		if pressed: handle_menu_press(pos)
		return
	if paused:
		if pressed: handle_pause_press(pos)
		return
	if round_over and pressed and Rect2(190, 300, 620, 170).has_point(pos) and next_round_timer <= 0.0:
		new_round(); return
	if countdown > 0.0 and pressed:
		countdown = 0.0
		queue_redraw()
		return
	if not pressed:
		if id == move_touch_id: move_touch_id = -1; touch_move = Vector2.ZERO
		elif id == fire_touch_id: fire_touch_id = -1
		elif id == p2_move_touch_id: p2_move_touch_id = -1; p2_touch_move = Vector2.ZERO
		elif id == p2_fire_touch_id: p2_fire_touch_id = -1
		return
	if mode == 2:
		if pos.x < W / 2.0:
			if pos.distance_to(p1_move_center()) <= TOUCH_JOYSTICK_INPUT_RADIUS and move_touch_id < 0:
				move_touch_id = id; touch_move = ((pos - p1_move_center()) / TOUCH_JOYSTICK_RESPONSE_RADIUS).limit_length(1.0)
			elif pos.distance_to(p1_fire_center()) <= TOUCH_FIRE_INPUT_RADIUS and fire_touch_id < 0:
				fire_touch_id = id; fire(0)
		else:
			if pos.distance_to(p2_move_center()) <= TOUCH_JOYSTICK_INPUT_RADIUS and p2_move_touch_id < 0:
				p2_move_touch_id = id; p2_touch_move = ((pos - p2_move_center()) / TOUCH_JOYSTICK_RESPONSE_RADIUS).limit_length(1.0)
			elif pos.distance_to(p2_fire_center()) <= TOUCH_FIRE_INPUT_RADIUS and p2_fire_touch_id < 0:
				p2_fire_touch_id = id; fire(1)
	else:
		if pos.distance_to(p1_move_center()) <= TOUCH_JOYSTICK_INPUT_RADIUS and move_touch_id < 0:
			move_touch_id = id; touch_move = ((pos - p1_move_center()) / TOUCH_JOYSTICK_RESPONSE_RADIUS).limit_length(1.0)
		elif pos.distance_to(single_fire_center()) <= TOUCH_FIRE_INPUT_RADIUS and fire_touch_id < 0:
			fire_touch_id = id; fire(0)

func touch_control_y() -> float:
	return [H - 250.0, H - 190.0, H - 165.0][touch_height_index]

func touch_outer_x() -> float:
	return [140.0, 110.0, 85.0][touch_spacing_index]

func touch_inner_x() -> float:
	return [350.0, 390.0, 430.0][touch_spacing_index]

func p1_move_center() -> Vector2:
	if mode == 2:
		return Vector2(-view_offset().x + 170.0, touch_control_y())
	return Vector2(-view_offset().x + touch_outer_x(), touch_control_y())

func p1_fire_center() -> Vector2:
	if mode == 2:
		return Vector2(-view_offset().x + 410.0, touch_control_y() - 130.0)
	return Vector2(-view_offset().x + touch_inner_x(), touch_control_y())

func p2_move_center() -> Vector2:
	if mode == 2:
		return Vector2(W + view_offset().x - 170.0, touch_control_y())
	return Vector2(W + view_offset().x - touch_outer_x(), touch_control_y())

func p2_fire_center() -> Vector2:
	if mode == 2:
		return Vector2(W + view_offset().x - 410.0, touch_control_y() - 130.0)
	return Vector2(W + view_offset().x - touch_inner_x(), touch_control_y())

func single_fire_center() -> Vector2:
	return Vector2(W + view_offset().x - touch_outer_x(), touch_control_y())

func handle_pause_press(pos: Vector2) -> void:
	if pause_settings_open:
		handle_settings_press(pos)
		return
	if Rect2(330, 290, 340, 52).has_point(pos):
		play_sound(sound_click)
		paused = false
	elif Rect2(330, 355, 340, 52).has_point(pos):
		play_sound(sound_click)
		pause_settings_open = true
	elif Rect2(330, 420, 340, 52).has_point(pos):
		play_sound(sound_click, 0.88)
		return_to_menu()
	queue_redraw()

func settings_active() -> bool:
	return settings_open or pause_settings_open

func return_to_menu() -> void:
	mode = 0
	local_setup_open = false
	settings_open = false
	pause_settings_open = false
	paused = false
	round_over = false
	mouse_joystick_active = false
	move_touch_id = -1
	fire_touch_id = -1
	touch_move = Vector2.ZERO
	p2_touch_move = Vector2.ZERO
	p2_move_touch_id = -1
	p2_fire_touch_id = -1
	bullets.clear()
	laser_beams.clear()
	pickups.clear()
	particles.clear()
	if static_map_layer != null: static_map_layer.visible = false
	queue_redraw()

func handle_menu_press(pos: Vector2) -> void:
	if settings_active():
		handle_settings_press(pos)
		return
	# 菜单只剩三件事：调地图大小 / 开打 / 设置。
	# 「电脑数量」「本地双人」「BOSS 战」三个按钮在 2026-11-14 的五人模式里删掉了 ——
	# 编队固定成爱丽丝 vs 四队友，选了也没用。占位坐标空着，别再把按钮画回来。
	if Rect2(370, 155, 52, 38).has_point(pos): play_sound(sound_click); COLS = maxi(MAP_COLS_MIN, COLS - 1)
	elif Rect2(578, 155, 52, 38).has_point(pos): play_sound(sound_click); COLS = mini(MAP_COLS_MAX, COLS + 1)
	elif Rect2(370, 201, 52, 38).has_point(pos): play_sound(sound_click); ROWS = maxi(MAP_ROWS_MIN, ROWS - 1)
	elif Rect2(578, 201, 52, 38).has_point(pos): play_sound(sound_click); ROWS = mini(MAP_ROWS_MAX, ROWS + 1)
	elif Rect2(270, 315, 460, 54).has_point(pos): play_sound(sound_click, 1.12); start_game(1)
	elif Rect2(270, 381, 460, 54).has_point(pos):
		# 设置（原来的「本地双人」按钮位置）
		play_sound(sound_click)
		settings_open = true
	queue_redraw()

func handle_settings_press(pos: Vector2) -> void:
	var changed := false
	var slider_index := audio_slider_at(pos)
	if slider_index >= 0:
		settings_slider_drag = slider_index
		update_audio_slider(slider_index, pos.x)
	elif mobile and Rect2(370, 420, 52, 42).has_point(pos): touch_height_index = maxi(0, touch_height_index - 1); changed = true
	elif mobile and Rect2(578, 420, 52, 42).has_point(pos): touch_height_index = mini(2, touch_height_index + 1); changed = true
	elif mobile and Rect2(370, 480, 52, 42).has_point(pos): touch_spacing_index = maxi(0, touch_spacing_index - 1); changed = true
	elif mobile and Rect2(578, 480, 52, 42).has_point(pos): touch_spacing_index = mini(2, touch_spacing_index + 1); changed = true
	elif Rect2(370, 540 if mobile else 420, 52, 42).has_point(pos) or Rect2(578, 540 if mobile else 420, 52, 42).has_point(pos): dark_mode = not dark_mode; changed = true; refresh_static_map()
	elif Rect2(270, 625 if mobile else 505, 460, 54).has_point(pos):
		play_sound(sound_click)
		if pause_settings_open: pause_settings_open = false
		else: settings_open = false
	if changed:
		apply_audio_levels()
		play_sound(sound_click)
		save_progress()
	queue_redraw()

## 设置页只剩两段滑条：总音量（0）/ 音效（1）。
## 原来第三段是「音乐」，而本版音乐由电竞房负责 → 滑条删掉（见 `draw_settings()`）。
func audio_slider_at(pos: Vector2) -> int:
	for slider_index in 2:
		if Rect2(380, 180.0 + slider_index * 60.0, 300, 42).has_point(pos): return slider_index
	return -1

func update_audio_slider(slider_index: int, pointer_x: float) -> void:
	var value := clampf((pointer_x - 400.0) / 240.0, 0.0, 1.0)
	if slider_index == 0: master_volume = value
	else: sfx_volume = value
	play_sound(sound_click)
	save_progress()
	queue_redraw()

func music_scroll_limit() -> float:
	return maxf(0.0, float(MUSIC_NAMES.size()) * 54.0 - 470.0)

## 歌单页的点击处理。**入口已经删了**（`handle_settings_press` 里再也不会把
## `music_picker_open` 置 true），函数留着只为少改一处引用。
func handle_music_picker_press(pos: Vector2) -> void:
	return

## 本地双人选人页**已停用**（菜单入口删掉了，`local_setup_open` 永远是 false）。
## 和 `draw_local_setup()` / `cycle_local_character()` 一起留着当死代码，
## 以后想做「双人插手柄」时这套 UI 还能直接接回来。
func handle_local_setup_press(pos: Vector2) -> void:
	return

func cycle_local_character(player: int, direction: int) -> void:
	var count := selectable_character_count()
	if player == 1:
		p1_character = posmod(p1_character + direction, count)
		while p1_character == p2_character: p1_character = posmod(p1_character + direction, count)
	else:
		p2_character = posmod(p2_character + direction, count)
		while p2_character == p1_character: p2_character = posmod(p2_character + direction, count)

func _draw() -> void:
	if mode == 0:
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), ui_background())
		draw_set_transform(view_offset())
		draw_menu(); return
	draw_set_transform(view_offset())
	for p in pickups: draw_pickup(p)
	for beam in laser_beams:
		var beam_alpha: float = clampf(float(beam.life) / float(beam.max_life), 0.0, 1.0)
		draw_polyline(beam.points, Color(1.0, 0.08, 0.04, beam_alpha * 0.35), 7.0, true)
		draw_polyline(beam.points, Color(1.0, 0.92, 0.65, beam_alpha), 2.0, true)
	for b in bullets:
		draw_circle(b.pos, BULLET_R, Color("f1f4ff") if dark_mode else Color("111827"))
	for tank_index in tanks.size(): draw_tank(tanks[tank_index])
	for p in particles:
		var alpha: float = clampf(p.life / p.max_life, 0.0, 1.0)
		var pc: Color = p.color; pc.a = alpha
		draw_circle(p.pos, 3.0 + alpha * 3.0, pc)
	var score_parts := PackedStringArray()
	for i in tanks.size():
		score_parts.append("%s %d" % [tanks[i].name, scores[i]])
	draw_string(ThemeDB.fallback_font, Vector2(325, 30), " · ".join(score_parts), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ui_text())
	var mode_text := "五人个人战 · 最后存活者获胜" if mode == 1 else ("单人调试" if mode == 2 else "BOSS 调试")
	if mode == 1 and not tanks[0].alive and not round_over:
		mode_text = "爱丽丝已出局 · 正在观战"
	draw_string(ThemeDB.fallback_font, Vector2(325, 55), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ui_muted())
	if mode == 3 and tanks.size() > 1 and tanks[1].alive:
		draw_string(ThemeDB.fallback_font, Vector2(790, 68), "BOSS 耐久", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("6f2ca8"))
		for hp_index in int(tanks[1].max_hp):
			var hp_color := Color("8e44d6") if hp_index < int(tanks[1].hp) else Color("d8d8d8")
			draw_rect(Rect2(875 + hp_index * 25, 54, 18, 12), hp_color)
			draw_rect(Rect2(875 + hp_index * 25, 54, 18, 12), Color("333333"), false, 1.0)
	if mobile: draw_touch_controls()
	if not mobile:
		draw_string(ThemeDB.fallback_font, Vector2(175, H - 12.0), "WASD 移动转向 · 空格 / J 开火 · 鼠标右键也能开火 · P 暂停 · Esc 退出", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("666666"))
	if paused:
		if pause_settings_open:
			draw_rect(Rect2(-view_offset(), get_viewport_rect().size), ui_background())
			draw_settings()
		else:
			draw_neu_panel(Rect2(300, 190, 400, 330), 26.0)
			draw_string(ThemeDB.fallback_font, Vector2(350, 258), "游戏暂停", HORIZONTAL_ALIGNMENT_CENTER, 300, 31, ui_text())
			draw_button(Rect2(330, 290, 340, 52), "继续游戏（Esc）", Color("46a96b"))
			draw_button(Rect2(330, 355, 340, 52), "设置", Color("5d8df7"))
			draw_button(Rect2(330, 420, 340, 52), "返回主页（M）", Color("8e44d6"))
	elif round_over:
		draw_neu_panel(Rect2(190, 300, 620, 170), 26.0)
		var sub := "轻触或按空格开始下一局" if mobile else "按空格开始下一局"
		draw_string(ThemeDB.fallback_font, Vector2(220, 370), round_message, HORIZONTAL_ALIGNMENT_CENTER, 560, 27, ui_text())
		draw_string(ThemeDB.fallback_font, Vector2(300, 426), sub, HORIZONTAL_ALIGNMENT_CENTER, 400, 17, ui_muted())
	elif countdown > 0.0:
		var count_text := "GO!" if countdown < 0.7 else str(ceili((countdown - 0.7) / 0.7))
		var count_center := Vector2(W / 2.0, H / 2.0)
		var count_font := ThemeDB.fallback_font
		draw_circle(count_center, 54, Color(1, 1, 1, 0.88))
		var count_baseline := count_center.y + count_font.get_ascent(48) * 0.5
		draw_string(count_font, Vector2(count_center.x - 55.0, count_baseline), count_text, HORIZONTAL_ALIGNMENT_CENTER, 110, 48, Color("333333"))
		var skip_hint := "点击屏幕或按空格跳过" if mobile else "按空格跳过"
		draw_string(count_font, Vector2(count_center.x - 150.0, count_center.y + 82.0), skip_hint, HORIZONTAL_ALIGNMENT_CENTER, 300, 15, ui_muted())

func view_offset() -> Vector2:
	return (get_viewport_rect().size - Vector2(W, H)) * 0.5

func ui_background() -> Color:
	return Color("171b26") if dark_mode else Color("e9edf7")

func ui_surface() -> Color:
	return Color("242a39") if dark_mode else Color("edf1fa")

func ui_text() -> Color:
	return Color("eef2ff") if dark_mode else Color("30384d")

func ui_muted() -> Color:
	return Color("a9b2c8") if dark_mode else Color("68738c")

func ui_shadow() -> Color:
	return Color(0.02, 0.025, 0.045, 0.72) if dark_mode else Color(0.38, 0.44, 0.58, 0.25)

func ui_highlight() -> Color:
	return Color(0.34, 0.39, 0.52, 0.28) if dark_mode else Color(1.0, 1.0, 1.0, 0.92)

func draw_round_rect(rect: Rect2, color: Color, radius: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var corner := maxi(0, int(radius))
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	draw_style_box(style, rect)

func draw_neu_panel(rect: Rect2, radius := 28.0) -> void:
	draw_round_rect(Rect2(rect.position + Vector2(10, 12), rect.size), ui_shadow(), radius)
	draw_round_rect(Rect2(rect.position - Vector2(4, 4), rect.size), ui_highlight(), radius)
	draw_round_rect(rect, ui_surface(), radius)

func draw_neu_inset(rect: Rect2, radius := 18.0) -> void:
	draw_round_rect(rect, ui_shadow(), radius)
	draw_round_rect(Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 6)), ui_background(), maxf(2.0, radius - 3.0))

func draw_menu() -> void:
	if settings_open:
		draw_settings()
		return
	draw_neu_panel(Rect2(175, 30, 650, 690), 34.0)
	draw_circle(Vector2(232, 82), 22.0, Color("67a5ff"))
	draw_circle(Vector2(768, 82), 8.0, Color("69dfdf"))
	draw_circle(Vector2(792, 82), 8.0, Color("a884ff"))
	draw_string(ThemeDB.fallback_font, Vector2(235, 90), "TANK  TROUBLE", HORIZONTAL_ALIGNMENT_CENTER, 530, 42, ui_text())
	draw_string(ThemeDB.fallback_font, Vector2(235, 126), "电竞房 · 五人混战", HORIZONTAL_ALIGNMENT_CENTER, 530, 16, ui_muted())
	draw_setting_row(155, "地图宽度", str(COLS), 38.0)
	draw_setting_row(201, "地图高度", str(ROWS), 38.0)
	# 原来这里有三行按钮（挑战 / BOSS / 本地双人）。五人模式把它们合并成一行：
	# 五个角色各自作战，出局后观战，最后存活者独立计分。
	draw_string(ThemeDB.fallback_font, Vector2(245, 259), "规则", HORIZONTAL_ALIGNMENT_RIGHT, 110, 17, ui_muted())
	draw_neu_inset(Rect2(370, 243, 260, 38), 19.0)
	draw_string(ThemeDB.fallback_font, Vector2(374, 268), "五人个人战 · 存活到最后", HORIZONTAL_ALIGNMENT_CENTER, 252, 17, ui_text())
	draw_button(Rect2(270, 315, 460, 54), "开始对战", Color("46a96b"))
	draw_button(Rect2(270, 381, 460, 54), "设置", Color("537a8a"))
	draw_string(ThemeDB.fallback_font, Vector2(235, 470), "WASD 移动 · 空格开火 · P 暂停 · M 回主页 · Esc 退出", HORIZONTAL_ALIGNMENT_CENTER, 530, 15, ui_muted())
	draw_string(ThemeDB.fallback_font, Vector2(235, 496), "音乐由电竞房统一播放", HORIZONTAL_ALIGNMENT_CENTER, 530, 14, ui_muted())

func draw_settings() -> void:
	draw_neu_panel(Rect2(175, 26, 650, 728 if mobile else 628), 34.0)
	draw_string(ThemeDB.fallback_font, Vector2(235, 92), "游戏设置", HORIZONTAL_ALIGNMENT_CENTER, 530, 38, ui_text())
	var settings_subtitle := "声音 · 外观 · 手机触控" if mobile else "声音 · 外观"
	draw_string(ThemeDB.fallback_font, Vector2(300, 132), settings_subtitle, HORIZONTAL_ALIGNMENT_CENTER, 400, 17, ui_muted())
	draw_audio_slider(180, "总音量", master_volume)
	draw_audio_slider(240, "音效", sfx_volume)
	# ── 「音乐」滑条 + 「背景曲目」按钮整块删掉（用户 2026-11-14）──
	# 曲库不并入，BGM 全程由电竞房负责，这里留个滑条只会误导。
	# 空出来的 y≈300~400 放一行说明。
	draw_string(ThemeDB.fallback_font, Vector2(235, 352), "背景音乐由电竞房统一播放", HORIZONTAL_ALIGNMENT_CENTER, 530, 16, ui_muted())
	if mobile:
		draw_setting_row(420, "按钮高度", ["高", "中", "低"][touch_height_index])
		draw_setting_row(480, "按钮间距", ["紧凑", "标准", "宽"][touch_spacing_index])
	draw_setting_row(540 if mobile else 420, "深色模式", "开启" if dark_mode else "关闭")
	var save_label := "保存并返回暂停菜单" if pause_settings_open else "保存并返回主页"
	draw_button(Rect2(270, 625 if mobile else 505, 460, 54), save_label, Color("5d8df7"))

## 歌单页**已停用**（入口删掉了，`music_picker_open` 永远是 false）。
## 留着空函数只是为了少改一处引用；真要清就把它和 `music_picker_*` 那组变量一起删。
func draw_music_picker() -> void:
	pass

## 本地双人选人页**已停用**（菜单入口删掉了，`local_setup_open` 永远是 false）。
## 删掉这个函数会把 `draw_character_row()` / `draw_character_thumbnail()` 变成
## 没被引用的死函数（GDScript 对没人调的函数不报错，但读代码的人会被误导）。
## 留着：以后要做「双人插手柄」时这套 UI 能直接接回来。
func draw_local_setup() -> void:
	draw_neu_panel(Rect2(175, 52, 650, 560), 34.0)
	draw_string(ThemeDB.fallback_font, Vector2(235, 105), "本地双人角色选择", HORIZONTAL_ALIGNMENT_CENTER, 530, 38, ui_text())
	draw_string(ThemeDB.fallback_font, Vector2(300, 158), "双方不能选择相同角色", HORIZONTAL_ALIGNMENT_CENTER, 400, 17, ui_muted())
	draw_character_row(220, "玩家一", p1_character, 42.0)
	draw_character_row(282, "玩家二", p2_character, 42.0)
	draw_button(Rect2(270, 365, 460, 60), "开始双人对战", Color("ff5c74"))
	draw_button(Rect2(270, 445, 460, 54), "返回主页", Color("777777"))
	draw_string(ThemeDB.fallback_font, Vector2(250, 545), "五人模式里本页不出现", HORIZONTAL_ALIGNMENT_CENTER, 500, 16, ui_muted())

func draw_setting_row(y: float, label: String, value: String, row_height := 42.0) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(245, y + row_height * 0.5 + 7), label, HORIZONTAL_ALIGNMENT_RIGHT, 110, 17, ui_muted())
	draw_button(Rect2(370, y, 52, row_height), "−", Color("888888"))
	draw_neu_inset(Rect2(434, y, 132, row_height), row_height / 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(438, y + row_height * 0.5 + 8), value, HORIZONTAL_ALIGNMENT_CENTER, 124, 18, ui_text())
	draw_button(Rect2(578, y, 52, row_height), "+", Color("888888"))

func draw_audio_slider(y: float, label: String, value: float) -> void:
	draw_string(ThemeDB.fallback_font, Vector2(245, y + 28), label, HORIZONTAL_ALIGNMENT_RIGHT, 110, 17, ui_muted())
	var track := Rect2(400, y + 13, 240, 16)
	draw_neu_inset(track, 8.0)
	var fill_width := maxf(0.0, track.size.x * value)
	if fill_width > 1.0: draw_round_rect(Rect2(track.position, Vector2(fill_width, track.size.y)), Color("618df7").lerp(Color("a36cff"), value), 8.0)
	var knob := Vector2(track.position.x + track.size.x * value, track.get_center().y)
	draw_circle(knob + Vector2(3, 4), 12.0, Color(0.02, 0.04, 0.1, 0.22))
	draw_circle(knob, 12.0, Color("eef2ff") if not dark_mode else Color("d9e1f5"))
	draw_string(ThemeDB.fallback_font, Vector2(650, y + 28), "%d%%" % int(round(value * 100.0)), HORIZONTAL_ALIGNMENT_LEFT, 58, 16, ui_text())

func draw_character_row(y: float, label: String, character_index: int, row_height := 38.0) -> void:
	var data := character_data(character_index)
	draw_string(ThemeDB.fallback_font, Vector2(180, y + row_height * 0.5 + 7), label, HORIZONTAL_ALIGNMENT_RIGHT, 100, 17, ui_muted())
	draw_button(Rect2(300, y, 52, row_height), "‹", Color("888888"))
	draw_round_rect(Rect2(360, y, 280, row_height), ui_surface(), row_height / 2.0)
	var border_color: Color = Color("222222") if character_index == 4 else data.color
	draw_rect(Rect2(360, y, 280, row_height), border_color, false, 2.0)
	draw_character_thumbnail(data.portrait, Vector2(385, y + row_height / 2.0), minf(32.0, row_height - 6.0))
	draw_string(ThemeDB.fallback_font, Vector2(410, y + row_height * 0.5 + 7), data.name, HORIZONTAL_ALIGNMENT_CENTER, 215, 17, ui_text())
	draw_button(Rect2(648, y, 52, row_height), "›", Color("888888"))

func draw_character_thumbnail(portrait: Texture2D, center: Vector2, max_side: float) -> void:
	var source_size := portrait.get_size()
	var scale_factor := minf(max_side / source_size.x, max_side / source_size.y)
	var display_size := source_size * scale_factor
	var portrait_rect := Rect2(center - display_size / 2.0, display_size)
	draw_texture_rect(portrait, portrait_rect, false)

func draw_button(r: Rect2, text: String, color: Color) -> void:
	draw_round_rect(Rect2(r.position + Vector2(6, 7), r.size), ui_shadow(), minf(22.0, r.size.y / 2.0))
	draw_round_rect(Rect2(r.position - Vector2(2, 2), r.size), ui_highlight(), minf(22.0, r.size.y / 2.0))
	var face := ui_surface().lerp(color, 0.16 if not dark_mode else 0.25)
	draw_round_rect(r, face, minf(22.0, r.size.y / 2.0))
	draw_string(ThemeDB.fallback_font, r.position + Vector2(8, r.size.y * 0.5 + 8), text, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 16, 20, ui_text())

func draw_tank(t: Dictionary) -> void:
	if not t.alive:
		for i in 10:
			var v := Vector2.from_angle(i * TAU / 10.0) * 30.0
			draw_line(t.pos, t.pos + v, Color("ffb347"), 3)
		return
	var outer := tank_box_points(t.pos, float(t.angle), TANK_LENGTH, TANK_WIDTH)
	var inner := tank_box_points(t.pos, float(t.angle), TANK_LENGTH - 5.0, TANK_WIDTH - 5.0)
	# The visible hull uses the exact same 28 x 20 oriented rectangle as collision.
	draw_colored_polygon(outer, Color("0b1016"))
	draw_colored_polygon(inner, t.color)
	draw_line(t.pos, t.pos + Vector2.from_angle(t.angle) * 21.0, t.color, 7, true)
	draw_circle(t.pos, 4, Color("192330"))
	if t.portrait != null:
		draw_tank_portrait(t.pos, t.portrait)
	if t.weapon != "normal":
		draw_string(ThemeDB.fallback_font, t.pos + Vector2(-20, -25), weapon_code(t.weapon), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, Color("222222"))

func draw_tank_portrait(tank_pos: Vector2, portrait: Texture2D) -> void:
	# Keep the portrait upright at the tank center. It is purely visual and never
	# changes the physical 28 x 20 collision rectangle.
	var source_size := portrait.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0: return
	var max_side := clampf(CELL * 0.65, 28.0, 44.0)
	var portrait_scale := minf(max_side / source_size.x, max_side / source_size.y)
	var display_size := source_size * portrait_scale
	var portrait_rect := Rect2(tank_pos - display_size / 2.0, display_size)
	draw_texture_rect(portrait, portrait_rect, false)

func tank_box_points(center: Vector2, angle: float, length: float, width: float) -> PackedVector2Array:
	var forward := Vector2.from_angle(angle) * length / 2.0
	var side := Vector2.from_angle(angle + PI / 2.0) * width / 2.0
	return PackedVector2Array([
		center + forward + side,
		center + forward - side,
		center - forward - side,
		center - forward + side
	])

func draw_pickup(p: Dictionary) -> void:
	var r := Rect2(p.pos - Vector2(15, 15), Vector2(30, 30))
	draw_rect(r, Color("f4c542")); draw_rect(r, Color("333333"), false, 3)
	var center: Vector2 = p.pos
	match p.kind:
		"shotgun":
			for a in [-0.45, 0.0, 0.45]: draw_line(center - Vector2(8, 0), center + Vector2.from_angle(a) * 11, Color("222222"), 2)
		"laser": draw_line(center - Vector2(10, 0), center + Vector2(10, 0), Color("e84141"), 4)
		"minigun":
			for y in [-5.0, 0.0, 5.0]: draw_line(center + Vector2(-9, y), center + Vector2(10, y), Color("222222"), 2)
		"homing":
			draw_arc(center, 9, -1.4, 1.4, 12, Color("222222"), 2); draw_circle(center + Vector2(8, 0), 3, Color("222222"))

func weapon_code(kind: String) -> String:
	return {"shotgun": "S", "laser": "L", "minigun": "M", "homing": "H"}.get(kind, "")


func draw_touch_controls() -> void:
	if mode == 2 and mobile:
		draw_circle(p1_move_center(), 72.0 * TOUCH_CONTROL_SCALE, Color(0.25, 0.82, 0.65, 0.16))
		draw_circle(p1_move_center() + touch_move * 42.0 * TOUCH_CONTROL_SCALE, 28.0 * TOUCH_CONTROL_SCALE, Color(0.35, 0.95, 0.72, 0.42))
		draw_circle(p1_fire_center(), 57.0 * TOUCH_CONTROL_SCALE, Color(0.25, 0.82, 0.65, 0.20))
		draw_string(ThemeDB.fallback_font, p1_fire_center() + Vector2(-90, 14), "P1 开火", HORIZONTAL_ALIGNMENT_CENTER, 180, 32, Color("27966f"))
		draw_circle(p2_move_center(), 72.0 * TOUCH_CONTROL_SCALE, Color(1.0, 0.36, 0.45, 0.16))
		draw_circle(p2_move_center() + p2_touch_move * 42.0 * TOUCH_CONTROL_SCALE, 28.0 * TOUCH_CONTROL_SCALE, Color(1.0, 0.48, 0.56, 0.42))
		draw_circle(p2_fire_center(), 57.0 * TOUCH_CONTROL_SCALE, Color(1.0, 0.36, 0.45, 0.20))
		draw_string(ThemeDB.fallback_font, p2_fire_center() + Vector2(-90, 14), "P2 开火", HORIZONTAL_ALIGNMENT_CENTER, 180, 32, Color("cf4054"))
	else:
		draw_circle(p1_move_center(), TOUCH_JOYSTICK_RADIUS, Color(0.7, 0.8, 0.85, 0.12))
		draw_circle(p1_move_center() + touch_move * TOUCH_JOYSTICK_KNOB_TRAVEL, TOUCH_JOYSTICK_KNOB_RADIUS, Color(0.8, 0.9, 0.9, 0.35))
		draw_circle(single_fire_center(), TOUCH_FIRE_RADIUS, Color(1.0, 0.36, 0.45, 0.22))
		draw_string(ThemeDB.fallback_font, single_fire_center() + Vector2(-100, 16), "开 火", HORIZONTAL_ALIGNMENT_CENTER, 200, 40, Color("ff8495"))

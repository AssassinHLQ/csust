extends SceneTree
## 电竞房「坐下开黑」过场 · 无窗口自检（2026-11-14）
##
## 用户要的流程：爱丽丝在自己椅子旁按 F → 五人坐上椅子（只平移、不动骨骼）→
## 五台电脑亮起游戏开发部标 → 玩家窗口切进坦克动荡 → 按 Esc 退出 → 五人跳下来。
##
## ⚠️ 写法跟着 `_verify_tank.gd` 走：**用真实帧驱动，不 `await`**。
##    实测 `--headless --script` 里 `await process_frame` 的信号不一定发，
##    一 await 协程就永远挂着、进程不退出。这里用 `_process(delta)` 帧计数当状态机，
##    过场本身也是 `_process` 驱动的，正好一起走。
##
##   godot --headless --path . --script res://scripts/_verify_esports_play.gd -- --no-capture

const SCRIPT_PATH := "res://scripts/esports_desk_play.gd"
const LOGO_PATH := "res://assets/story/gamedev_logo.png"

var _fails := 0
var _checks := 0
var _stage := 0
var _frames := 0
var _host: Node3D
var _player: CharacterBody3D
var _tp := Vector3.ZERO
var _phase_names: Array = ["IDLE", "SIT", "GLOW", "PLAY", "STAND"]


func _init() -> void:
	print("========== 电竞房 · 坐下开黑过场自检 ==========")
	var script := load(SCRIPT_PATH) as Script
	_check(script != null, "过场脚本能加载：%s" % SCRIPT_PATH)
	if script == null:
		_finish()
		return

	# ── ① 五个位置是「实测常量」──
	var c: Dictionary = script.get_script_constant_map()
	_check(is_equal_approx(float(c.get("SEAT_X", 0.0)), 53.45),
		"落座点 X = 椅心 53.32 + 0.13（实际 %.2f）" % float(c.get("SEAT_X", 0.0)))
	var seat_z: Array = c.get("SEAT_Z", [])
	_check(seat_z.size() == 5, "五把椅子（实际 %d 把）" % seat_z.size())
	if seat_z.size() == 5:
		var ok := true
		for i in range(1, 5):
			var d := float(seat_z[i]) - float(seat_z[i - 1])
			if d < 1.3 or d > 1.7:
				ok = false
		_check(ok, "椅子间距约 1.49 m（实测 %s）" % str(seat_z))
	var scr_z: Array = c.get("SCREEN_Z", [])
	_check(scr_z.size() == 5, "五台显示器（实际 %d 台）" % scr_z.size())
	var alice := int(c.get("ALICE_SEAT", -1))
	_check(alice == 2, "爱丽丝坐中间那把（实际第 %d 把）" % alice)
	# 凯伊必须紧挨爱丽丝（用户 2026-11-15 提过：「凯伊为什么不和爱丽丝坐一起」）
	var plan: Dictionary = c.get("SEAT_BY_NAME", {})
	var kei := int(plan.get("CompanionKei", -1))
	_check(kei >= 0 and absi(kei - alice) == 1,
		"凯伊紧挨爱丽丝（凯伊 %d 号，爱丽丝 %d 号）" % [kei, alice])
	var momoi := int(plan.get("CompanionMomoi", -1))
	_check(momoi >= 0 and absi(momoi - alice) == 1,
		"桃井也挨着爱丽丝（桃井 %d 号）" % momoi)
	var seats_used := {}
	for k in plan.keys():
		seats_used[int(plan[k])] = true
	seats_used[alice] = true
	_check(seats_used.size() == 5, "五个人五个不同座位（实际 %d 个）" % seats_used.size())
	_tp = c.get("TRIGGER_POS", Vector3.ZERO)
	if seat_z.size() == 5 and alice >= 0:
		_check(absf(_tp.z - float(seat_z[alice])) < 0.02,
			"触发点就在爱丽丝椅子正前方（触发 z=%.2f，椅子 z=%.2f）"
			% [_tp.z, float(seat_z[alice])])
		_check(_tp.x < float(c.get("SEAT_X", 0.0)) - 1.0,
			"触发点在桌前走道上（x=%.2f，椅子 x=%.2f）"
			% [_tp.x, float(c.get("SEAT_X", 0.0))])
	_check(is_equal_approx(float(c.get("SEAT_Y", 0.0)), 1.0),
		"座面高 = 实测 1.00（人物平移到座面上）")

	# ── ② 素材（还没 import 时过场脚本会退回读原始 PNG，所以这里不断言 .import）──
	_check(FileAccess.file_exists(LOGO_PATH), "游戏开发部标的文件在：%s" % LOGO_PATH)
	var logo_tex := _load_logo_like_host()
	_check(logo_tex != null and logo_tex.get_width() >= 512,
		"标能取到纹理（%d×%d）"
		% [logo_tex.get_width() if logo_tex else 0, logo_tex.get_height() if logo_tex else 0])

	# ── ③ 建场景：等真实帧，因为 `_ready` 是引擎在入树后调的 ──
	_player = CharacterBody3D.new()
	_player.name = "FakePlayer"
	_player.add_to_group("player")
	get_root().add_child(_player)

	# 假电竞房：只放一块「形状像五连屏材质桶」的盒子（x 极薄 / y 0.40 / z 6.69）
	var fake_room := Node3D.new()
	fake_room.name = "EsportsRoom"
	var low := Node3D.new()
	low.name = "Room"
	fake_room.add_child(low)
	var bucket := MeshInstance3D.new()
	bucket.name = "FakeScreenBucket"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.045, 0.40, 6.69)
	bucket.mesh = bm
	low.add_child(bucket)
	get_root().add_child(fake_room)

	_host = script.new() as Node3D
	_host.name = "FakeDeskPlay"
	get_root().add_child(_host)
	_run.call_deferred()


func _load_logo_like_host() -> Texture2D:
	if ResourceLoader.exists(LOGO_PATH):
		return load(LOGO_PATH) as Texture2D
	var img := Image.load_from_file(LOGO_PATH)
	if img != null and not img.is_empty():
		return ImageTexture.create_from_image(img)
	return null


func _run() -> void:
	_stage = 1
	_frames = 0


func _process(_delta: float) -> bool:
	if _stage == 0:
		return false
	_frames += 1
	match _stage:
		1:      # 等 _ready 建完显示器
			if _frames >= 3:
				_check_ready()
				_stage = 2
				_frames = 0
		2:      # 站到触发点 → 按 F（物理帧手动推，避开「等几帧」的时序抖动）
			_player.global_position = _tp
			_host.call("tick_physics_for_test", 1.0 / 60.0)
			if _frames >= 3:
				_check(bool(_host.call("in_range")), "站到触发点：判定「在范围内」")
				var ev := InputEventKey.new()
				ev.keycode = KEY_F
				ev.physical_keycode = KEY_F
				ev.pressed = true
				_host.call("_input", ev)
				_check(_host.call("phase_name") == "SIT",
					"按 F 触发过场（阶段 %s）" % str(_host.call("phase_name")))
				_check(not bool(_host.call("in_range")), "触发后提示收起")
				_stage = 3
				_frames = 0
		3:      # 等 SIT → GLOW → PLAY
			if _host.call("phase_name") == "PLAY":
				_check_play()
				_stage = 4
				_frames = 0
			elif _frames > 240:
				_check(false, "240 帧内没进 PLAY（当前 %s）" % str(_host.call("phase_name")))
				_stage = 4
				_frames = 0
		4:      # 按 Esc 退出 → 等 STAND → IDLE
			if _frames == 1:
				var esc := InputEventKey.new()
				esc.keycode = KEY_ESCAPE
				esc.physical_keycode = KEY_ESCAPE
				esc.pressed = true
				_host.call("_input", esc)
				_check(_host.call("phase_name") == "STAND",
					"按 Esc 退出小游戏（阶段 %s）" % str(_host.call("phase_name")))
			if _host.call("phase_name") == "IDLE" and _frames > 3:
				_check_idle()
				_stage = 5
				_finish()
			elif _frames > 240:
				_check(false, "240 帧内没回到 IDLE（当前 %s）" % str(_host.call("phase_name")))
				_stage = 5
				_finish()
	return false


func _check_ready() -> void:
	var screens: Array = _host.call("screens")
	_check(screens.size() == 5, "建出 5 块屏幕贴片（实际 %d 块）" % screens.size())
	if screens.size() == 5:
		var all_off := true
		for s in screens:
			if (s as MeshInstance3D).visible:
				all_off = false
		_check(all_off, "一开始五块屏幕都是灭的")
		var mat := (screens[0] as MeshInstance3D).material_override as StandardMaterial3D
		_check(mat != null and mat.albedo_texture != null, "贴片材质挂着游戏开发部标")
		_check(mat != null and mat.emission_enabled, "贴片自发光（会真的亮起来）")
		# 贴片必须和屏面等大：大了溢到显示器边框、小了留一圈亮屏
		var q := (screens[0] as MeshInstance3D).mesh as QuadMesh
		_check(q != null and is_equal_approx(q.size.x, 0.645) and is_equal_approx(q.size.y, 0.425),
			"贴片尺寸 = 屏面 0.645×0.425（实际 %s）" % (str(q.size) if q else "无"))
	_check(is_equal_approx(_host.call("screen_level"), 0.0), "屏幕亮度初值 0")


func _check_play() -> void:
	_check(true, "过场推进到「窗口已是小游戏」")
	_check(bool(_host.call("is_playing")), "is_playing() = true")
	_check(float(_host.call("screen_level")) > 0.9,
		"五块屏已全亮（亮度 %.2f）" % float(_host.call("screen_level")))
	var lit: Array = _host.call("screens")
	if lit.size() >= 1:
		var lmat := (lit[0] as MeshInstance3D).material_override as StandardMaterial3D
		_check(lmat != null and lmat.albedo_texture != null, "亮屏时材质贴的是游戏开发部标")
		_check(lmat != null and lmat.emission_enabled, "亮屏材质自发光（会真的亮起来）")
	var tank: Node = _host.get("tank")
	_check(tank != null and is_instance_valid(tank), "坦克动荡已实例化进画布")
	var actors: Array = _host.call("actors")
	_check(actors.size() >= 1, "至少把玩家放上了椅子（%d 人）" % actors.size())
	if actors.size() >= 1:
		var seat_pos: Vector3 = actors[0]["seat_pos"]
		_check(_player.global_position.distance_to(seat_pos) < 0.06,
			"玩家确实在座面上（位置 %s，座面 %s）"
			% [str(_player.global_position.snappedf(0.01)), str(seat_pos.snappedf(0.01))])
		_check(_player.is_physics_processing() == false, "过场期间玩家物理被冻结")
	# 菜单点得动吗？（「开始对战」按钮在画布上大约 (500, 342)）
	if tank != null and is_instance_valid(tank) and tank.has_method("ui_event"):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(500, 342)
		press.global_position = press.position
		tank.call("ui_event", press)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = press.position
		release.global_position = press.position
		tank.call("ui_event", release)
		_check(int(tank.get("mode")) > 0,
			"菜单「开始对战」点得动（mode=%d）" % int(tank.get("mode")))
	else:
		_check(false, "小游戏没有 ui_event()，菜单点不动")


func _check_idle() -> void:
	_check(is_equal_approx(_host.call("screen_level"), 0.0), "人走了屏幕也灭了")
	_check(_player.global_position.distance_to(_tp) < 0.06,
		"玩家被放回原位（%s）" % str(_player.global_position.snappedf(0.01)))
	_check(_player.is_physics_processing(), "玩家物理处理已恢复（不会卡在冻结状态）")
	_check(_host.call("phase_name") == "IDLE", "回到常态（阶段 %s）"
		% str(_host.call("phase_name")))


func _check(ok: bool, what: String) -> void:
	if what == "":
		return
	_checks += 1
	if ok:
		print("  ✓ %s" % what)
	else:
		_fails += 1
		print("  ✗ %s" % what)


func _finish() -> void:
	print("---------- %d 项，失败 %d ----------" % [_checks, _fails])
	print("★ 全部通过" if _fails == 0 else "✗ 有 %d 项没过" % _fails)
	quit(0 if _fails == 0 else 1)

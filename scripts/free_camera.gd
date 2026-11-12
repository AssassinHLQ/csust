extends Camera3D
## 自由摄像头（开发者模式 F7，2026-11-12 用户要求）。
##
## 用户原话：「f3 模式新增 f7，切换自由摄像头 WASD QE 方便拍摄」。
## 目标不是做一套飞行玩法，而是**拍摄工具**：自由飞、干净构图、能拍真 4K 静帧，
## 拿去替换开场 PV 里那些「实机截图太糊」的图。
##
## ── 键位 ──
##   F7 / Esc   退出自由摄像头（回到第三人称）
##   W A S D    沿视线前后左右平移
##   Q / E      世界坐标下降 / 上升
##   鼠标       转视角（进入时自动捕获光标）
##   Shift      加速 ×4；Ctrl 减速 ×0.25
##   滚轮       调基础速度（1 ~ 60 m/s）
##   F8       4K 截图：**离屏**用 SubViewport 重画一帧（窗口全程不动）
##
## ── 为什么 4K 是「离屏渲染」而不是把窗口拉大 ──
## 第一版是「临时把窗口拉到 4K、拍完还原」。用户实测**三次**闪退，日志最后一行
## 都是 `_fit_render_scale 渲染尺寸 (3840, 2000)`；而探针从窗口化 1600×900 起步
## 一直复现不出来 —— 真正会崩的是「**最大化 → 切窗口化 → 瞬间拉 3840×2000**」
## 这条路径（Vulkan swapchain 重建在这台机器/多显示器上不稳，直接进程消失）。
##
## 现在改成：新建 `3840 × 当前宽高比` 的 `SubViewport`，共享同一个 `World3D`，
## 复制当前相机渲染一帧，再从它自己的贴图 `get_image()`。窗口尺寸/模式全程不变，
## 因此**不可能**再触发那条崩溃路径。探针实测含高斯泼溅通过 —— 关键是必须把
## 相机上的 `compositor` 一并复制给离屏相机，否则 GDGS Compute 后端一格泼溅都不画。
##
## ── 不进图的东西 ──
## 离屏视口里**只有 3D**，HUD / 帮助条（都是 CanvasLayer）天然不会入画。
## 玩家角色**不藏**（它是构图的一部分），所以这里**不用** `set_ride_lock()`
## （那个会顺带把角色网格藏起来）。改成临时关掉玩家的输入与物理：
##   输入关掉 → 鼠标转视角不会带着角色转头、左键不会开枪；
##   物理关掉 → 人停在原地不动（F4 换场景会重建玩家，不受影响）。

const UiSkin := preload("res://scripts/ui_skin.gd")

## 基础飞行速度（米/秒），滚轮可调。
const BASE_SPEED := 8.0
const SPEED_MIN := 1.0
const SPEED_MAX := 60.0
## 鼠标灵敏度（弧度 / 像素），和 `player.gd` 同一数量级。
const MOUSE_SENS := 0.0025
## 俯仰限位（弧度）
const PITCH_LIMIT := 1.5533   # ±89°

## 自由摄像头自己的 InputMap 动作（运行期注册，不动 `project.godot`）。
## 用**动作**而不是直接读物理键有两个好处：
##   ① 自检 / 探针能用 `Input.action_press()` 模拟（物理键状态模拟不了）；
##   ② 以后想换键位只改这里。
## WASD 复用项目已有的 `move_forward/back/left/right`（键位与玩家一致）。
const ACT_UP := "freecam_up"
const ACT_DOWN := "freecam_down"
const ACT_FAST := "freecam_fast"
const ACT_SLOW := "freecam_slow"

var _game: Node
var _active := false
var _speed := BASE_SPEED
var _yaw := 0.0
var _pitch := 0.0

## 借来的玩家相机（见 `start()` 里那段崩溃记录：**全场只能有一台相机**）
var _borrowed: Camera3D
var _borrowed_parent: Node
var _borrowed_xform := Transform3D.IDENTITY
var _borrowed_fov := 70.0
var _borrowed_near := 0.05

var _help_layer: CanvasLayer
var _help_label: Label
var _toast_label: Label
var _toast_until := 0.0

## 进入自由摄像头时存下来的、退出时要还回去的状态
var _stored := {}

var _shots_dir_cache := ""
var _shot_index := 0
var _capturing := false


func setup(game: Node) -> void:
	_game = game
	# 自由摄像头不继承父节点变换（游戏根节点一般是原点，但不赌这个）
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ⚠️ 本节点**不再自己当相机**（见 `start()` 里 F8 崩溃那段）：它只是个
	#    「拿着玩家相机飞的支架」。fov / near / far 也改成在 `start()` 里
	#    设给**借来的**那台相机，否则设了也没人用。
	_ensure_input_map()


func _ensure_input_map() -> void:
	_add_key_action(ACT_UP, KEY_E)
	_add_key_action(ACT_DOWN, KEY_Q)
	_add_key_action(ACT_FAST, KEY_SHIFT)
	_add_key_action(ACT_SLOW, KEY_CTRL)


func _add_key_action(action: StringName, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func is_active() -> bool:
	return _active


func toggle() -> void:
	if _active:
		stop()
	else:
		start()


# ── 进入 / 退出 ──────────────────────────────────────────────────────────

func start() -> void:
	if _active:
		return
	if _game == null or not is_instance_valid(_game):
		return
	if get_tree().paused:
		print("[FreeCam] 游戏是暂停的（菜单 / 剧情），先关掉再按 F7")
		return
	var player := _player()
	if player == null:
		push_warning("[FreeCam] 找不到 Player，自由摄像头不开")
		return
	if player.has_method("is_riding") and bool(player.call("is_riding")):
		print("[FreeCam] 正在骑火箭，先下来再按 F7")
		return

	# 初始机位 = 当前玩家相机（所见即所得，不用重新找角度）
	var cur := get_viewport().get_camera_3d()
	if cur != null and cur != self:
		global_transform = cur.global_transform
	elif player is Node3D:
		global_transform = Transform3D(Basis(), (player as Node3D).global_position + Vector3.UP * 1.6)
	var b := global_transform.basis
	_pitch = clampf(asin(clampf(-b.z.y, -1.0, 1.0)), -PITCH_LIMIT, PITCH_LIMIT)
	_yaw = atan2(b.z.x, b.z.z)
	rotation = Vector3(_pitch, _yaw, 0.0)

	# ⚠️⚠️ 2026-11-12 用户报「f8 崩溃，直接闪退」——真凶在这儿：
	#
	#    `splat_compositor.gd` 会**给「当前相机」挂 Compositor**（Compute 后端必须，
	#    否则一张泼溅都渲不出来）。本节点是**第二台**相机，切 `current = true` 那一刻
	#    它也给本节点挂了一份 —— 日志里那句「已为相机「FreeCam」挂上 Compositor…
	#    （累计 2 台）」就是证据。
	#    然后 F8 把窗口放大到 4K：视口尺寸突变，**两台相机各持一份 Compositor**
	#    同时重建 render buffers → Vulkan 直接崩，进程没了，什么 GDScript 报错都留不下。
	#
	#    修法：**不抢相机**。把玩家自己的那台 `Camera3D` 从弹簧臂上摘下来、
	#    临时挂到本节点下面当子相机 —— 全场始终只有一台相机，Compositor 只有一份。
	#    退出时再挂回弹簧臂、恢复本地变换。
	_borrowed = _find_player_camera(player)
	if _borrowed == null:
		push_warning("[FreeCam] 找不到玩家相机，自由摄像头不开（避免出现第二台相机）")
		return
	_borrowed_parent = _borrowed.get_parent()
	_borrowed_xform = _borrowed.transform
	# 相机的取景参数也一起存，退出时还原
	_borrowed_fov = _borrowed.fov
	_borrowed_near = _borrowed.near
	_borrowed_parent.remove_child(_borrowed)
	add_child(_borrowed)
	_borrowed.transform = Transform3D.IDENTITY
	# 拍摄用：视野略宽、近裁剪收小（不碰 far —— 它由 `RenderEnv` 按渲染距离管着）
	_borrowed.fov = 70.0
	_borrowed.near = 0.05
	_borrowed.current = true
	# 本节点自己不当前相机：**一台就够**（上面那段崩溃记录）
	current = false

	_stored = {
		"player_input": player.is_processing_input(),
		"player_physics": player.is_physics_processing(),
		"player_process": player.is_processing(),
		"mouse": Input.mouse_mode,
		"hud": null,
		"hud_visible": false,
		"perf": null,
		"perf_visible": false,
	}
	player.set_process_input(false)
	player.set_physics_process(false)

	var hud := _game.get_node_or_null("HUD")
	if hud != null:
		_stored["hud"] = hud
		_stored["hud_visible"] = bool(hud.get("visible"))
		hud.set("visible", false)
	var perf: Variant = _game.get("_perf_layer")
	if perf is CanvasLayer:
		_stored["perf"] = perf
		_stored["perf_visible"] = bool((perf as CanvasLayer).visible)
		(perf as CanvasLayer).visible = false

	if DisplayServer.get_name() != "headless" and not _no_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_active = true
	_build_help()
	print("[FreeCam] 开：WASD 平移 / QE 升降 / 鼠标转视角 / Shift 加速 / F8 4K 截图 / F7 退出")


func stop() -> void:
	if not _active:
		return
	_active = false
	# 把相机还回弹簧臂（顺序：先挂回去、恢复本地变换，再放开玩家物理）
	if _borrowed != null and is_instance_valid(_borrowed) and _borrowed_parent != null \
			and is_instance_valid(_borrowed_parent):
		if _borrowed.get_parent() == self:
			remove_child(_borrowed)
		_borrowed_parent.add_child(_borrowed)
		_borrowed.transform = _borrowed_xform
		_borrowed.fov = _borrowed_fov
		_borrowed.near = _borrowed_near
	_borrowed = null
	_borrowed_parent = null
	var player := _player()
	if player != null:
		player.set_process_input(bool(_stored.get("player_input", true)))
		player.set_physics_process(bool(_stored.get("player_physics", true)))
		# 玩家相机重新拿回控制权
		var cam := player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
		if cam != null:
			cam.current = true
	var hud: Variant = _stored.get("hud")
	if hud is Node and is_instance_valid(hud):
		(hud as Node).set("visible", bool(_stored.get("hud_visible", true)))
	var perf: Variant = _stored.get("perf")
	if perf is CanvasLayer and is_instance_valid(perf):
		(perf as CanvasLayer).visible = bool(_stored.get("perf_visible", false))
	Input.mouse_mode = int(_stored.get("mouse", Input.MOUSE_MODE_CAPTURED))
	_free_help()
	_stored.clear()
	print("[FreeCam] 关：回到第三人称")


## 玩家那台 `Camera3D`（`player.tscn` 里叫 `CameraRig/SpringArm3D/Camera3D`）。
## 拿不到就退回「视口当前相机」——但那台可能不是玩家的，所以这里按名字找更稳。
func _find_player_camera(player: Node3D) -> Camera3D:
	var by_path := player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	if by_path != null:
		return by_path
	for n in player.find_children("*", "Camera3D", true, false):
		return n as Camera3D
	return null


# ── 每帧：飞行 ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _active:
		return
	if _toast_label != null and is_instance_valid(_toast_label) \
			and _toast_label.visible and _now() > _toast_until:
		_toast_label.visible = false
	if _capturing:
		return
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir -= basis.z
	if Input.is_action_pressed("move_back"):
		dir += basis.z
	if Input.is_action_pressed("move_left"):
		dir -= basis.x
	if Input.is_action_pressed("move_right"):
		dir += basis.x
	if Input.is_action_pressed(ACT_UP):
		dir += Vector3.UP
	if Input.is_action_pressed(ACT_DOWN):
		dir -= Vector3.UP
	if dir == Vector3.ZERO:
		return
	dir = dir.normalized()
	var mult := 1.0
	if Input.is_action_pressed(ACT_FAST):
		mult = 4.0
	if Input.is_action_pressed(ACT_SLOW):
		mult = 0.25
	global_position += dir * _speed * mult * delta


# ── 输入（本节点是场景里最后一个子节点，`_input` 倒序派发时最先收到）──

func _input(event: InputEvent) -> void:
	if not _active:
		return
	if _capturing:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * MOUSE_SENS
		_pitch = clampf(_pitch - mm.relative.y * MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
		rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_speed(_speed * 1.15)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_speed(_speed / 1.15)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and (event as InputEventKey).pressed \
			and not (event as InputEventKey).echo:
		var key := event as InputEventKey
		if key.keycode == KEY_F7 or key.physical_keycode == KEY_F7 \
				or key.keycode == KEY_ESCAPE:
			stop()
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_F8 or key.physical_keycode == KEY_F8:
			capture_4k()
			get_viewport().set_input_as_handled()
			return


func _set_speed(v: float) -> void:
	_speed = clampf(v, SPEED_MIN, SPEED_MAX)
	_update_help()


# ── 4K 截图 ─────────────────────────────────────────────────────────────

## 拍一张当前画面的 4K 静帧（保持当前画幅比例），存 PNG + 机位参数 txt。
## 全程自动恢复窗口尺寸、窗口模式、渲染缩放与 UI。
func capture_4k() -> void:
	if not _active or _capturing:
		return
	if DisplayServer.get_name() == "headless":
		push_warning("[FreeCam] headless 下拍不了 4K（没有渲染后端）")
		return
	_capturing = true

	# ⚠️⚠️ 2026-11-12 第三次修：**别再动窗口了**。
	#
	#    前两版是「临时把窗口拉大到 4K、拍完还原」。用户实测两次闪退，
	#    日志最后一行都是 `_fit_render_scale 渲染尺寸 (3840, 2000)`；
	#    而本喵的探针从**窗口化 1600×900** 起步，所以一直复现不出来 ——
	#    真正会崩的是「**最大化 → 切窗口化 → 瞬间拉 3840×2000**」这条路径
	#    （窗口是 DWM/Vulkan swapchain 重建，在多显示器/虚拟显示器上不稳）。
	#
	#    新方案：**窗口全程不动**。新建一个 3840 宽的 SubViewport，
	#    共享同一个 World3D、复制当前相机渲染一帧，再从它自己的贴图取图。
	#    这条路探针实测通过（含高斯泼溅：要把相机上的 `compositor` 复制过来，
	#    否则 GDGS 的 Compute 后端在离屏视口里一张泼溅都不画）。
	#
	#    附带好处：SubViewport 里只有 3D，不会拍到 HUD / 帮助条，连藏 UI 都省了。
	var vp := get_viewport()
	var src_cam := vp.get_camera_3d() if vp != null else null
	if src_cam == null:
		push_warning("[FreeCam] 4K 截图失败：找不到当前相机")
		_capturing = false
		_show_toast("4K 截图失败：找不到当前相机")
		return
	var vp_size := Vector2(vp.get_visible_rect().size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = Vector2(1600, 900)
	var want_w := 3840
	var want_h := int(round(float(want_w) * vp_size.y / vp_size.x))
	if want_h % 2 != 0:
		want_h -= 1
	want_h = maxi(want_h, 720)

	var sub := SubViewport.new()
	sub.name = "FreeCam4K"
	sub.size = Vector2i(want_w, want_h)
	sub.own_world_3d = false
	sub.world_3d = vp.world_3d
	sub.transparent_bg = false
	sub.msaa_3d = vp.msaa_3d
	sub.screen_space_aa = vp.screen_space_aa
	sub.use_taa = vp.use_taa
	sub.scaling_3d_scale = 1.0
	add_child(sub)

	var shot_cam := Camera3D.new()
	shot_cam.name = "ShotCam"
	shot_cam.fov = src_cam.fov
	shot_cam.near = src_cam.near
	shot_cam.far = src_cam.far
	shot_cam.cull_mask = src_cam.cull_mask
	shot_cam.environment = src_cam.environment
	shot_cam.attributes = src_cam.attributes
	# ★ 关键：GDGS Compute 后端靠相机上的 Compositor 合成泼溅；不复制就渲不出来
	shot_cam.compositor = src_cam.compositor
	sub.add_child(shot_cam)
	shot_cam.global_transform = src_cam.global_transform
	shot_cam.current = true

	# 渲染几帧：第一帧要建 4K 渲染目标 + 泼溅排序
	var img: Image = null
	for i in 4:
		sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	img = sub.get_texture().get_image()

	var path := ""
	if img != null and img.get_width() >= 3200:
		var dir := _shots_dir()
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
		var base_name := "4k_%s_%03d" % [stamp, _shot_index]
		_shot_index += 1
		path = dir.path_join(base_name + ".png")
		var err := img.save_png(path)
		if err != OK:
			push_warning("[FreeCam] 4K 截图保存失败（错误 %d）：%s" % [err, path])
			path = ""
		else:
			_write_meta(path, img.get_size(), DisplayServer.window_get_size())
			print("[FreeCam] 4K 截图 → %s（%d×%d，离屏渲染，未动窗口）" % [
				path, img.get_size().x, img.get_size().y])
	else:
		push_warning("[FreeCam] 4K 截图失败：读到的是 %s"
			% (str(img.get_size()) if img != null else "null"))

	# 收掉离屏资源（相机先摘，避免它仍挂着 compositor 被释放）
	if is_instance_valid(shot_cam):
		shot_cam.current = false
		sub.remove_child(shot_cam)
		shot_cam.queue_free()
	if is_instance_valid(sub):
		sub.queue_free()
	await get_tree().process_frame

	_capturing = false
	if path.is_empty():
		_show_toast("4K 截图失败：详见控制台")
	else:
		_show_toast("4K 截图已保存：%s" % path.get_file())


## 截图目录：优先项目里的 `_arisu_captures/_shots/`（开发期方便翻）；
## 导出版游戏 res:// 不可写，自动退回 `user://screenshots/`。
func _shots_dir() -> String:
	if not _shots_dir_cache.is_empty():
		return _shots_dir_cache
	var project := ProjectSettings.globalize_path("res://")
	if not project.is_empty():
		var d := project.path_join("_arisu_captures").path_join("_shots")
		if DirAccess.make_dir_recursive_absolute(d) == OK:
			var probe := d.path_join(".write_test")
			var f := FileAccess.open(probe, FileAccess.WRITE)
			if f != null:
				f.store_string("ok")
				f.close()
				DirAccess.remove_absolute(probe)
				_shots_dir_cache = d
				return d
	var u := ProjectSettings.globalize_path("user://").path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(u)
	_shots_dir_cache = u
	return u


## 机位参数另存一份：以后想复现同一张图，照这个机位摆就行。
func _write_meta(png_path: String, img_size: Vector2i, window_before: Vector2i) -> void:
	var scene_path := ""
	var cs := get_tree().current_scene
	if cs != null:
		scene_path = cs.scene_file_path
	var meta := {
		"time": Time.get_datetime_string_from_system(),
		"png": png_path.get_file(),
		"resolution": [img_size.x, img_size.y],
		"window_before": [window_before.x, window_before.y],
		"scene": scene_path,
		"camera_position": [snappedf(global_position.x, 0.001), snappedf(global_position.y, 0.001),
			snappedf(global_position.z, 0.001)],
		"camera_rotation_degrees": [snappedf(rotation_degrees.x, 0.01),
			snappedf(rotation_degrees.y, 0.01), snappedf(rotation_degrees.z, 0.01)],
		"fov": fov,
	}
	var f := FileAccess.open(png_path.get_basename() + "_meta.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "  "))
		f.close()


# ── 帮助条 / 提示 ────────────────────────────────────────────────────────

func _build_help() -> void:
	if _help_layer != null and is_instance_valid(_help_layer):
		_help_layer.queue_free()
	_help_layer = CanvasLayer.new()
	_help_layer.name = "FreeCamHelp"
	_help_layer.layer = 245          # 比 HUD / 开场 PV 都高，拍摄时自己会藏掉
	_help_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_help_layer)
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := PanelContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 0.0
	box.anchor_top = 1.0
	box.anchor_right = 0.0
	box.anchor_bottom = 1.0
	box.offset_left = 24.0
	box.offset_top = -178.0
	box.offset_right = 660.0
	box.offset_bottom = -24.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.01, 0.05, 0.10, 0.72)
	sb.border_color = Color(0.42, 0.78, 0.96, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	box.add_theme_stylebox_override("panel", sb)
	root.add_child(box)

	_help_label = Label.new()
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := UiSkin.ui_font()
	if font != null:
		_help_label.add_theme_font_override("font", font)
	_help_label.add_theme_font_size_override("font_size", 15)
	_help_label.add_theme_color_override("font_color", Color(0.93, 0.97, 1.0, 1.0))
	box.add_child(_help_label)
	_update_help()

	_toast_label = Label.new()
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.visible = false
	_toast_label.anchor_left = 1.0
	_toast_label.anchor_top = 0.0
	_toast_label.anchor_right = 1.0
	_toast_label.anchor_bottom = 0.0
	_toast_label.offset_left = -640.0
	_toast_label.offset_top = 24.0
	_toast_label.offset_right = -24.0
	_toast_label.offset_bottom = 64.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if font != null:
		_toast_label.add_theme_font_override("font", font)
	_toast_label.add_theme_font_size_override("font_size", 17)
	_toast_label.add_theme_color_override("font_color", Color(0.62, 0.95, 1.0, 1.0))
	_toast_label.add_theme_color_override("font_outline_color", Color(0.0, 0.04, 0.08, 0.9))
	_toast_label.add_theme_constant_override("outline_size", 4)
	root.add_child(_toast_label)


func _update_help() -> void:
	if _help_label == null or not is_instance_valid(_help_label):
		return
	_help_label.text = """自由摄像头（开发者模式）
WASD 平移 · Q 下降 / E 上升 · 鼠标转视角
Shift 加速 ×4 · Ctrl 减速 ×0.25 · 滚轮调速度（当前 %.1f m/s）
F8  4K 截图（HUD/帮助条自动隐藏）  ·  F7 / Esc 退出""" % _speed


func _show_toast(text: String) -> void:
	if _toast_label == null or not is_instance_valid(_toast_label):
		return
	_toast_label.text = text
	_toast_label.visible = true
	_toast_until = _now() + 5.0


func _free_help() -> void:
	if _help_layer != null and is_instance_valid(_help_layer):
		_help_layer.queue_free()
	_help_layer = null
	_help_label = null
	_toast_label = null


# ── 小工具 ──────────────────────────────────────────────────────────────

func _player() -> Node3D:
	if _game == null or not is_instance_valid(_game):
		return null
	return _game.get_node_or_null("Player") as Node3D


func _no_capture() -> bool:
	return OS.get_cmdline_user_args().has("--no-capture")


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func is_capturing() -> bool:
	return _capturing

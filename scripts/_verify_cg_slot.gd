extends SceneTree
## 验：CG 插槽（2026-11-11）。
##
## 用户：「这个不好看,我还是自己做cg吧」+ 格式答「mp4」。
## 于是 `title_intro.gd` 改成三级优先：`opening.ogv` → PNG 帧序列 → 程序化标题卡。
##
## 本探针要回答**四个能翻车的点**，不能只写不验：
##   ① `.ogv` 到底要不要 import？—— Godot 4 把它当**原生资源**直接读，
##      只生 `.uid` 不生 `.import`。（这一点本喵一开始写进文档里写错了，这里钉住。）
##   ② `load()` 拿得到 `VideoStream` 吗？拿不到就等于 CG 永远播不了。
##   ③ 视频里的音轨**在不在**（mp4 转 ogv 时音频没转 Vorbis 会静音，最容易漏）。
##   ④ 三级优先**真的**按顺序降级：有 ogv 报 video、只有帧报 frames、都没有报 procedural。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_verify_cg_slot.gd -- --splat=off

const TitleIntroScript := preload("res://scripts/title_intro.gd")
const CG_VIDEO := "res://assets/cg/opening.ogv"
const CG_FRAMES_DIR := "res://assets/cg/opening"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


## 建一个 TitleIntro 只为问 `kind()`（它不播放、不改任何东西）
func _kind_now() -> String:
	var host := Node.new()
	root.add_child(host)
	var intro := TitleIntroScript.new() as Node
	host.add_child(intro)
	var k := String(intro.call("kind"))
	host.queue_free()
	return k


func _run() -> void:
	print("========== CG 插槽 ==========")

	# ── ① / ② / ③：ogv 本身 ──
	print("\n── ① `.ogv` 是原生资源，不需要 .import ──")
	var has_ogv := FileAccess.file_exists(CG_VIDEO)
	print("  %s 存在 = %s" % [CG_VIDEO, str(has_ogv)])
	if has_ogv:
		var import_side := CG_VIDEO + ".import"
		var uid_side := CG_VIDEO + ".uid"
		print("  旁边有 .import = %s；有 .uid = %s" % [
			str(FileAccess.file_exists(import_side)), str(FileAccess.file_exists(uid_side))])
		_check(not FileAccess.file_exists(import_side),
			"`.ogv` **没有** `.import`（Godot 4 当原生资源直接读，不走导入管线）")

		print("\n── ② / ③ 能不能 load、时长和音轨 ──")
		_check(ResourceLoader.exists(CG_VIDEO), "`ResourceLoader.exists()` 认得它")
		var vs := load(CG_VIDEO) as VideoStream
		_check(vs != null, "`load()` 拿到 `VideoStream`（拿不到就等于 CG 永远播不了）")
		if vs != null:
			print("  VideoStream 类型 = %s" % vs.get_class())
			var player := VideoStreamPlayer.new()
			player.stream = vs
			root.add_child(player)
			# ⚠️ GDScript 里**没有** `VideoStream.instantiate_playback()`
			#    （那个 `_instantiate_playback` 是 C++ 内部接口，ClassDB 里带下划线）。
			#    所以"有没有音轨"只能间接看：`get_stream_length()` 能给出时长，
			#    就说明容器解出来了；音轨本身交给转码脚本保证（固定 libvorbis）。
			var length := player.get_stream_length()
			print("  时长 = %.2f s；可切换音频轨道 = %d" % [
				length, player.get_audio_track()])
			_check(length > 0.0, "解得出时长（%.2f s > 0）—— 容器和视频轨是好的" % length)
			player.queue_free()
		else:
			_check(false, "（拿不到 VideoStream，后面没法验）")
	else:
		print("  （没放 ogv，跳过 ①②③ —— 这正是「使用者还没做 CG」的状态）")

	# ── ④ 三级降级 ──
	print("\n── ④ 三级优先真的按顺序降级 ──")
	var k := _kind_now()
	print("  现在报的正片 = %s" % k)
	if has_ogv:
		_check(k == "video", "有 ogv 时报 `video`（实际 %s）" % k)
	else:
		_check(k == "frames" or k == "procedural",
			"没 ogv 时不报 `video`（实际 %s）" % k)

	# 帧序列目录存不存在，要和报出来的 kind 对得上
	var has_frames_dir := DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(CG_FRAMES_DIR))
	print("  `%s` 目录存在 = %s" % [CG_FRAMES_DIR, str(has_frames_dir)])
	if not has_ogv and has_frames_dir:
		_check(k == "frames", "只有帧序列时报 `frames`（实际 %s）" % k)
	if not has_ogv and not has_frames_dir:
		_check(k == "procedural", "两样都没有时报 `procedural`（兜底，实际 %s）" % k)

	# ── ⑤ 兜底那版仍然能播完（不因为加了 CG 分支而坏掉）──
	print("\n── ⑤ 兜底路径仍然能跑完 ──")
	var host := Node.new()
	root.add_child(host)
	var intro := TitleIntroScript.new() as Node
	host.add_child(intro)
	var t0 := Time.get_ticks_msec()
	await intro.call("play", func() -> bool: return true)
	var took := float(Time.get_ticks_msec() - t0) / 1000.0
	print("  播完用了 %.2f s，正片 = %s" % [took, k])
	_check(took > 0.5, "播得完（%.2f s，没有卡死）" % took)
	_check(not bool(intro.call("is_playing")), "播完 `is_playing()` 为假")
	host.queue_free()

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ CG 插槽就绪：放 ogv 就播 ogv，没有就自动降级" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)

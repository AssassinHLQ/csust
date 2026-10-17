extends SceneTree
## 探针：**不导入**的音频文件能不能在运行时读出来。
##
## 为什么需要：用户把 `xxx.wav` 丢进 `res://story/voice/` 之后，只要没打开过编辑器，
## 就没有 `.import`，`ResourceLoader.load()` 会失败。若 `AudioStreamWAV` 有从原始
## 文件读的静态方法，我们就能兜住这一种情况（语音文件可能随时加进来）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_audio_api.gd

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for cls in ["AudioStreamWAV", "AudioStreamOggVorbis", "AudioStreamMP3", "AudioStream"]:
		var hits: Array[String] = []
		for m in ClassDB.class_get_method_list(cls, true):
			var name := String(m["name"])
			if name.contains("load") or name.contains("save") or name.contains("file"):
				hits.append("%s(%s)" % [name, str(m.get("args", []).map(func(a): return a["name"]))])
		print("[%s] %s" % [cls, str(hits)])

	print("ClassDB 有 AudioStreamWAV.load_from_wav = %s"
		% ClassDB.class_has_method("AudioStreamWAV", "load_from_wav", true))
	print("ClassDB 有 AudioStreamOggVorbis.load_from_file = %s"
		% ClassDB.class_has_method("AudioStreamOggVorbis", "load_from_file", true))
	print("ClassDB 有 AudioStreamMP3.load_from_file = %s"
		% ClassDB.class_has_method("AudioStreamMP3", "load_from_file", true))

	# 真造一个 wav 到 res:// 里，看能不能不经导入就读回来
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.stereo = false
	var frames := 2205
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var v := int(sin(TAU * 440.0 * float(i) / 22050.0) * 8000.0)
		data.encode_s16(i * 2, v)
	w.data = data
	var probe_path := "res://story/voice/_probe_api.wav"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://story/voice"))
	var err := w.save_to_wav(probe_path)
	print("save_to_wav → %s" % error_string(err))
	print("FileAccess 能看到 = %s" % FileAccess.file_exists(probe_path))
	print("ResourceLoader.exists = %s" % ResourceLoader.exists(probe_path))

	var res := ResourceLoader.load(probe_path)
	print("ResourceLoader.load → %s" % ("null" if res == null else str(res)))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))
	quit()

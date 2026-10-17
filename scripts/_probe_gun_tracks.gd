extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	var p := game.get_node_or_null("Player") as Player
	var ap: AnimationPlayer = (p.anim as AnimDriver).player
	for clip in ["RunFire_Ing", "Normal_Attack_Ing", "Move_Ing"]:
		if not ap.has_animation(clip):
			print("[trk] 没有 ", clip); continue
		var a := ap.get_animation(clip)
		print("[trk] %s：%d 条轨道" % [clip, a.get_track_count()])
		for t in a.get_track_count():
			var path := String(a.track_get_path(t))
			if path.contains("Weapon") or path.contains("magazine") or path.contains("Muzzle"):
				print("[trk]    type=%d  %s  键 %d" % [a.track_get_type(t), path, a.track_get_key_count(t)])
	quit(0)

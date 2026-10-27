extends RefCounted
## 进场加载的「按距离 / 超时」小工具（2026-10-27 用户的分阶段加载策略）。
##
## 静态 NPC（Boss / 老师）刚进场景时先不建模型：玩家从蒙德里安二层的门出生，
## 离它们几十米，等走近了再建 —— 或者最多等 `max_wait` 秒兜底。
## 这样进场时主线程只做「蒙德里安 + 天空 + 玩家自己」，剩下的边走过去边建。
##
## 为什么用 Timer + 信号而不是 `await`：场景切换会把旧场景整棵 free，
## 一个 await 的协程恢复在已释放的实例上会报错；信号连接在接收者释放时自动断开。
##
## 用法：
##   BootGate.when_near(self, boot_distance, boot_max_wait, _build_model)
## `distance` 和 `max_wait` 都为 0 时**立即**同步调用，行为和以前一样。
static func when_near(owner: Node3D, distance: float, max_wait: float,
		callback: Callable) -> void:
	if owner == null or not callback.is_valid():
		return
	if distance <= 0.0 and max_wait <= 0.0:
		callback.call()
		return
	var tree := owner.get_tree()
	if tree == null:
		return
	var deadline := float(Time.get_ticks_msec()) / 1000.0 + max_wait
	var poll := Timer.new()
	poll.name = "BootGate"
	poll.wait_time = 0.25
	poll.one_shot = false
	poll.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(poll)
	poll.timeout.connect(func() -> void:
		if not is_instance_valid(owner) or not owner.is_inside_tree():
			poll.queue_free()
			return
		var player := owner.get_tree().get_first_node_in_group("player") as Node3D
		var near := distance > 0.0 and player != null \
			and player.global_position.distance_to(owner.global_position) <= distance
		var timeout := max_wait > 0.0 \
			and float(Time.get_ticks_msec()) / 1000.0 >= deadline
		if near or timeout:
			poll.stop()
			poll.queue_free()
			callback.call()
	)
	poll.start()

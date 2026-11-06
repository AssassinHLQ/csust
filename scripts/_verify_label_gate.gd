extends SceneTree
## 校验 `parkour.gd::_gate_world_labels()` 是否真的把全部世界招牌压成近距离显示。
##
## ⚠️ 门控有一次 `call_deferred()`（用来覆盖运行时动态生成的「第 N 段」规则牌），
##    所以必须等几帧再断言，不能在 `_initialize()` 里立刻检查。
##
## 用法：_tools/run_probe.sh res://scripts/_verify_label_gate.gd

const SCENE := "res://scenes/parkour.tscn"
const WANT_END := 6.0

var _inst: Node
var _frames := 0


func _initialize() -> void:
	var ps: PackedScene = load(SCENE)
	if ps == null:
		print("[gate] FAIL: 载不动 %s" % SCENE)
		quit()
		return
	_inst = ps.instantiate()
	root.add_child(_inst)          # add_child 同步触发 _ready()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:                # 等 _ready + deferred + 子场景动态生成都跑完
		return false

	var total := 0
	var bad: Array = []
	for n in _inst.find_children("*", "Label3D", true, false):
		total += 1
		var l := n as Label3D
		if l == null:
			continue
		if l.no_depth_test or not is_equal_approx(l.visibility_range_end, WANT_END):
			bad.append("%s (no_depth_test=%s, end=%.1f)"
				% [String(_inst.get_path_to(n)), str(l.no_depth_test), l.visibility_range_end])

	print("[gate] Label3D 共 %d 个，不合格 %d 个" % [total, bad.size()])
	for i in mini(bad.size(), 10):
		print("   x " + String(bad[i]))
	print("[gate] 结果: %s" % ("PASS" if (total > 0 and bad.is_empty()) else "FAIL"))
	_inst.queue_free()
	quit()
	return true

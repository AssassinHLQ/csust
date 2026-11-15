extends Node
## Hold summoned model resources for one arena; never join a loading worker on
## the main thread. An abandoned warmup drains outstanding requests then frees.
const PATHS := [
	"res://models/companions/Yuuka.glb",
	"res://models/boss_pig/猪猪优香.fbx",
	"res://models/boss_pig/tex/pig_halo.png",
	"res://models/boss_pig/tex/pig_untitled1.png",
	"res://models/boss_pig/tex/pig_nose.png",
	"res://models/boss_pig/tex/pig_tail.png",
]
var _pending: Array[String] = []
var _resources: Array[Resource] = []
var _abandoned := false

func start(owner_node: Node) -> void:
	owner_node.tree_exiting.connect(_on_owner_exiting, CONNECT_ONE_SHOT)
	for path in PATHS:
		if ResourceLoader.exists(path) and ResourceLoader.load_threaded_request(path) == OK:
			_pending.append(path)
	set_process(not _pending.is_empty())

func _process(_delta: float) -> void:
	for index in range(_pending.size() - 1, -1, -1):
		var path := _pending[index]
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: continue
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path)
			if resource != null and not _abandoned: _resources.append(resource)
		_pending.remove_at(index)
	if _pending.is_empty():
		set_process(false)
		if _abandoned: queue_free()

func _on_owner_exiting() -> void:
	_abandoned = true
	_resources.clear()
	if _pending.is_empty(): queue_free()

func status() -> Dictionary:
	return {"pending": _pending.size(), "held": _resources.size(), "abandoned": _abandoned}

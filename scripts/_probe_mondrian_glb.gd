extends SceneTree
## 一次性检查：把蒙德里安 GLB 装进空场景，打印包围盒/材质/树结构。
##   godot --path . --headless --script res://scripts/_probe_mondrian_glb.gd

var _root: Node
var _aabb := AABB()
var _first := true
var _meshes := 0
var _mats := {}
var _solids := 0


func _init() -> void:
	var packed := load("res://models/mondrian/mondrian_building.glb") as PackedScene
	if packed == null:
		print("PROBE FAIL: 载入失败")
		quit()
		return
	_root = packed.instantiate()
	_walk(_root, Transform3D.IDENTITY)
	print("PROBE meshes=%d solids=%d mats=%s" % [_meshes, _solids, str(_mats.keys())])
	print("PROBE aabb pos=%s size=%s" % [_aabb.position, _aabb.size])
	quit()


func _walk(n: Node, xf: Transform3D) -> void:
	if n is MeshInstance3D:
		_meshes += 1
		var mi := n as MeshInstance3D
		var box: AABB = xf * mi.get_aabb()
		_aabb = box if _first else _aabb.merge(box)
		_first = false
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var m := mi.mesh.surface_get_material(s)
				if m:
					_mats[m.resource_name] = true
	elif n is CollisionObject3D:
		_solids += 1
	for c in n.get_children():
		_walk(c, xf * (c as Node3D).transform if c is Node3D else xf)

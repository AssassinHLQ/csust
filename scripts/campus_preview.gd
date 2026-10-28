@tool
extends Node3D
## 编辑器专用：校园低模点云预览（由 scripts/_bake_campus_preview.gd 烘出）。
## 运行时自动隐藏，避免和真正的泼溅叠在一起；在编辑器里始终显示，
## 方便对照着拖碰撞体。

func _ready() -> void:
	visible = Engine.is_editor_hint()

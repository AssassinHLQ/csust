extends MeshInstance3D
## 可选贴图：本机有这张图就贴上去，没有就保持材质本来的纯色。
##
## 为什么需要它 —— 有些图的授权不允许随仓库分发（例如《碧蓝档案》游戏内截图）。
## 如果把它写进 `.tscn` 的 `[ext_resource]`，那么「图不在」会被 Godot 判成
## **整个场景加载失败**：
##
##     ERROR: Parse Error: [ext_resource] referenced non-existent resource
##     ERROR: Failed loading resource: res://scenes/esports_room.tscn
##
## 而 `game.tscn` 又引用了那个场景，于是克隆下来的工程**根本起不来**。
## 改成运行时按路径 `load()` 之后，缺图只是这张海报变成纯色，场景照常加载。
##
## 这和工程里已有的做法是同一套：
##   - `dialogue_box.gd::_show_image()`  剧情插图，找不到就跳过这一步
##   - `dialogue_box.gd` 零件图悬停       找不到就不接悬停
##   - `shop_clerk.gd` 配置单             缺图时单子照常显示
##
## 用法：挂在 MeshInstance3D 上，把 `texture_path` 指向图片。


## 要贴的图。空 = 不贴，保持材质原样。
## 用普通 String 而不是 @export_file，是为了让生成脚本能直接 set() 一个路径，
## 也不依赖编辑器的文件选择器。
@export var texture_path := ""

## 贴图后材质的粗糙度（0 = 镜面，1 = 全漫反射）。
@export var roughness := 0.8

## 图不在时的底色（只在材质本身就是这个脚本新建的时候用得上）。
@export var fallback_color := Color(0.10, 0.10, 0.12)


func _ready() -> void:
	if texture_path.is_empty():
		return

	# 图允许缺：这里只警告，不 push_error —— 它在仓库里本来就该缺。
	if not ResourceLoader.exists(texture_path):
		push_warning("[OptionalTexture] 图不在（按设计允许），保持纯色：%s" % texture_path)
		return

	var tex := load(texture_path) as Texture2D
	if tex == null:
		push_warning("[OptionalTexture] 加载失败（按设计允许），保持纯色：%s" % texture_path)
		return

	# 材质可能是场景里的共享 sub_resource，复制一份再改，别污染别人。
	var src := material_override as StandardMaterial3D
	var mat: StandardMaterial3D
	if src == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = fallback_color
	else:
		mat = src.duplicate() as StandardMaterial3D
	apply_texture(mat, tex)


## 把贴图装上并挂回节点。单独拆出来，方便自检脚本直接调。
func apply_texture(mat: StandardMaterial3D, tex: Texture2D) -> void:
	mat.albedo_texture = tex
	mat.roughness = roughness
	material_override = mat

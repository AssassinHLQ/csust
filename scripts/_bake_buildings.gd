extends SceneTree
## 把**代码构建**的商店 / 蒙德里安大楼烘焙成独立场景，之后由 `game.tscn` 直接摆实例，
## 这样在编辑器里就能看到、能拖动，运行时不再调 `build()`。
##
## 用法：_tools/run_shot.sh res://scripts/_bake_buildings.gd
##       _tools/run_shot.sh res://scripts/_bake_buildings.gd -- --force   （覆盖已有产物）
## 产物：res://scenes/shop_baked.tscn、res://scenes/mondrian_house_baked.tscn
## ⚠️ 产物烘焙完就可以在编辑器里手改（`game.tscn` 现在是它的实例）。手改之后再跑
##    本工具会把改动覆盖掉 —— 所以默认拒绝覆盖，必须显式 `-- --force`。
##
## 烘焙内容：
##   · 商店：屋壳、屋顶、三面墙、店面幕墙、货架、柜台、灯、招牌、**Deck 半边地板**；
##   · 大楼：两层墙体、楼板、楼梯、立面线条、吊灯。
## 不烘焙：芹香（`ShopClerk` 的 `_ready()` 会自己实例化模型，烘焙进去会加载两份），
##         以及所有每帧要重连的信号 —— 这些由 `shop.gd::_wire_baked()` 在运行时补。

const SHOP_OUT := "res://scenes/shop_baked.tscn"
const MONDRIAN_OUT := "res://scenes/mondrian_house_baked.tscn"
const ROOM_OUT := "res://scenes/room609_proxy_baked.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 烘焙产物是**可以手改的**（用户要在编辑器里拖），所以默认不覆盖；
	# 真要重新生成就加 `-- --force`。
	var force := "--force" in OS.get_cmdline_user_args()
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1]
	for p in [SHOP_OUT, MONDRIAN_OUT, ROOM_OUT]:
		if FileAccess.file_exists(p) and not force:
			print("[bake] %s 已存在，本次跳过（会覆盖手改内容；要重烘请加 -- --force）" % p)

	var ps := load("res://scenes/game.tscn") as PackedScene
	if ps == null:
		print("[bake] 打不开 game.tscn")
		quit(1)
		return
	var game := ps.instantiate()
	root.add_child(game)
	for _i in 120:
		await process_frame

	# 重复烘焙时先把场景里已有的烘焙实例摘掉，避免叠加两份
	var old: Array[Node] = []
	for c in game.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path in ["res://scripts/shop.gd",
				"res://scripts/mondrian_house.gd"]:
			old.append(c)
		elif String(c.name) == "RoomProxy":
			old.append(c)
	for n in old:
		print("[bake] 摘掉场景里已有的 %s" % n.name)
		n.get_parent().remove_child(n)
		n.queue_free()
	if not old.is_empty():
		await process_frame

	game.call("_build_shop")
	game.call("_build_mondrian")
	# 609 的代理房子（墙 + 黑屋顶 + 门板）：照碰撞盒重生成一遍再打包
	game.call("_build_room_proxy")
	for _i in 10:
		await process_frame

	var shop := _find(game, "res://scripts/shop.gd")
	var house := _find(game, "res://scripts/mondrian_house.gd")
	if shop == null or house == null:
		print("[bake] 没找到构建结果：shop=%s mondrian=%s" % [str(shop), str(house)])
		quit(1)
		return

	# 芹香不入烘焙（理由见文件头）
	for c in shop.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path == "res://scripts/shop_clerk.gd":
			print("[bake] 摘掉 %s（运行时再建）" % c.name)
			shop.remove_child(c)
			c.queue_free()
	await process_frame

	# 把构建时量出来的尺寸存成 meta，运行时 `_wire_baked()` 读回来（探针要用）
	shop.set_meta("baked_shop_len", shop.get("shop_len"))
	shop.set_meta("baked_shop_depth", shop.get("shop_depth"))
	shop.set_meta("baked_shop_height", shop.get("shop_height"))
	shop.set_meta("baked_deck_rect", shop.get("deck_rect"))
	shop.set_meta("baked_built_count", shop.get("built_count"))
	shop.set_meta("baked_decor_count", shop.get("decor_count"))

	if _can_write(SHOP_OUT, force) and (only == "" or only == "shop"):
		_bake(shop, SHOP_OUT)
	if _can_write(MONDRIAN_OUT, force) and (only == "" or only == "mondrian"):
		_bake(house, MONDRIAN_OUT)
	if _can_write(ROOM_OUT, force) and (only == "" or only == "room609"):
		var proxy := game.get_node_or_null("RoomProxy")
		if proxy != null:
			_bake(proxy, ROOM_OUT)
		else:
			print("[bake] 没找到 RoomProxy，609 代理房子跳过")
	quit(0)


## 已存在且没加 --force 的不写（产物可以手改，别悄悄覆盖）
func _can_write(path: String, force: bool) -> bool:
	return force or not FileAccess.file_exists(path)


## 按脚本路径找构建出来的那个根节点
func _find(root_node: Node, script_path: String) -> Node:
	for c in root_node.get_children():
		var sc: Script = c.get_script()
		if sc != null and sc.resource_path == script_path:
			return c
	return null


## 递归把 owner 设成根，再打包存盘
func _bake(node: Node, path: String) -> void:
	_own(node, node)
	var ps := PackedScene.new()
	var err := ps.pack(node)
	if err != OK:
		print("[bake] pack 失败 %s：%d" % [path, err])
		return
	err = ResourceSaver.save(ps, path)
	if err != OK:
		print("[bake] save 失败 %s：%d" % [path, err])
		return
	var filesize := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)).size()
	print("[bake] %s ← %s（%d 节点，%.1f KB）"
		% [path.get_file(), node.name, _count(node), float(filesize) / 1024.0])


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)


func _count(n: Node) -> int:
	var k := 1
	for c in n.get_children():
		k += _count(c)
	return k

class_name Credits
extends RefCounted
## 全项目素材的**署名与许可**，唯一事实来源。
##
## 三处显示都从这里取，改一处三处同步：
##   · 游戏里：Esc → 设置 → 「致谢与素材署名」（`settings_menu.gd::_build_credits`）
##   · 仓库里：`CREDITS.md`（同一份内容的人读版）
##   · 文档里：`README.md` 末尾与 `THIRD_PARTY.md` 的表格
##
## ⚠️ `_verify_credits.gd` 会扫 `models/`、`assets/`、`addons/`、`splatdata/`
##    下的**每一个目录**，断言它们都被下面的某一条 `path` 覆盖 ——
##    所以以后新加一套素材（新 Boss、新音效包），**必须在这里登记**，
##    否则自检直接红。这是「所有资源都要署名」这条要求的机械保证。
##
## 字段：
##   group       分组（显示顺序见 GROUPS）
##   path        仓库内的相对路径（文件或目录）
##   title       人读的名字
##   author      作者 / 版权方
##   license     许可（自由文本，写清楚能不能商用 / 能不能再分发）
##   distributed 是否**随本仓库分发**（false = 被 .gitignore 排除，克隆者要自己补）
##   source      来源链接或出处（没有就空串）
##   license_file 许可原文在本仓库里的位置（没有就空串）
##   note        补充说明（没有就空串）

const GROUPS := [
	"代码与插件",
	"角色与 Boss 模型",
	"界面与字体",
	"音效",
	"剧情与图标",
]

const ENTRIES := [
	{
		"group": "界面与字体",
		"path": "assets/sky",
		"title": "全景天空盒（粉 / 日 / 夜 / 黄昏四张）",
		"author": "AllSky Free（Richard Whitelock）",
		"license": "MIT（可分发、可商用）",
		"distributed": true,
		"source": "https://github.com/rpgwhitelock/AllSkyFree_Godot",
		"license_file": "",
		"note": "8192~16384 原图缩到 4096×2048 JPEG；`--sky=` 切换",
	},
	{
		"group": "界面与字体",
		"path": "assets/tex",
		"title": "空地地砖贴图 + 法线图",
		"author": "本项目作者（程序生成）",
		"license": "MIT",
		"distributed": true,
		"source": "",
		"license_file": "LICENSE",
		"note": "`tools/make_lot_paver.py` 生成，完全可平铺，不依赖外网素材",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/rtx5090",
		"title": "RTX 5090 显卡模型（最后平台房顶那件资产）",
		"author": "爱给网（aigei.com）用户上传，作者未署名",
		"license": "爱给网模型：仅限学习交流，不可商用；本仓库不分发，克隆者需自行合法取得",
		"distributed": false,
		"source": "https://www.aigei.com/（用户本地下载的 RTX5090simplified.obj）",
		"license_file": "",
		"note": "2026-10-20 用户提供；`.gitignore` 排除了整个目录。缺这个文件时屋顶只是没有卡，游戏照常跑",
	},
	# ---------- 代码与插件 ----------
	{
		"group": "代码与插件",
		"path": "scripts",
		"title": "全部 GDScript 代码、场景与着色器",
		"author": "本项目作者",
		"license": "MIT",
		"distributed": true,
		"source": "",
		"license_file": "LICENSE",
		"note": "含 scripts/、scenes/、addons 之外的着色器与 project.godot",
	},
	{
		"group": "代码与插件",
		"path": "addons/gdgs",
		"title": "GDGS 高斯泼溅渲染插件 3.3.0",
		"author": "ReconWorldLab",
		"license": "MIT",
		"distributed": true,
		"source": "https://github.com/ReconWorldLab/godot-gaussian-splatting",
		"license_file": "addons/gdgs/LICENSE",
		"note": "画室609 / 校园两块泼溅场地靠它渲染",
	},

	# ---------- 角色与 Boss 模型 ----------
	{
		"group": "角色与 Boss 模型",
		"path": "models/boss_binah",
		"title": "比纳（第六位 Boss，备用）FBX + 贴图",
		"author": "一个睿智",
		"license": "专有版权（派生自 Blue Archive，玩家二创）",
		"distributed": false,
		"source": "比纳_by_一个睿智.zip",
		"license_file": "",
		"note": "Binah_Original.fbx，44 骨、无动画；3 个材质（本体/环、武器面、光环）；*_Mask.png 是作者渲染遮罩，游戏里不绑",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/boss_goliath",
		"title": "哥利亚（第七位 Boss，备用）FBX + 贴图",
		"author": "一个睿智",
		"license": "专有版权（派生自 Blue Archive，玩家二创）",
		"distributed": false,
		"source": "哥利亚_by_一个睿智.zip",
		"license_file": "",
		"note": "Goliath_Decagram_Vulcan.fbx，34 骨、单网格单材质；*_Mask.png 同上",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/boss_hod",
		"title": "霍德（第四位 Boss）FBX + 贴图",
		"author": "一个睿智",
		"license": "专有版权（派生自 Blue Archive，玩家二创）",
		"distributed": false,
		"source": "霍德_by_一个睿智.zip",
		"license_file": "",
		"note": "HOD_Original.fbx，164 骨、无动画；3 个材质，2 张 *_Mask.png 是原作者渲染用的遮罩，游戏里不绑",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/boss_perorozilla",
		"title": "佩洛洛斯拉（第五位 Boss）FBX + 贴图",
		"author": "一个睿智",
		"license": "专有版权（派生自 Blue Archive，玩家二创）",
		"distributed": false,
		"source": "佩洛洛斯拉_by_一个睿智.zip",
		"license_file": "",
		"note": "Perorozilla_Original.fbx，47 骨、无动画；6 网格共用 1 个材质；5 张表情变体只留一张（见 peroro_boss.gd）",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/boss_squash",
		"title": "倭瓜优香（第三位 Boss）OBJ + 贴图",
		"author": "一个睿智",
		"license": "专有版权（派生自 Blue Archive，玩家二创）",
		"distributed": false,
		"source": "倭瓜优香压缩文件_by_一个睿智.zip",
		"license_file": "",
		"note": "倭瓜优香.obj，纯静态网格、无骨架；4 个材质",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/boss_pig",
		"title": "飞猪优香（第二位 Boss）FBX + 贴图",
		"author": "一个睿智",
		"license": "专有版权（派生自 Blue Archive，玩家二创）",
		"distributed": false,
		"source": "飞猪优香 (2)_by_一个睿智.zip",
		"license_file": "",
		"note": "猪猪优香.fbx，纯静态网格；uv/ 里两张是**作者的成品渲染图**，挪到 ref/ 当贴图分配基准",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/boss",
		"title": "霸王龙优香（第一位 Boss）FBX + 贴图",
		"author": "Blue Archive 玩家二创（原作者未标注）",
		"license": "专有版权（派生自 Blue Archive）",
		"distributed": false,
		"source": "",
		"license_file": "",
		"note": "优香霸王龙.fbx，73 骨、无动画；贴图要按材质名手工绑（见 boss.gd 的 TEXTURES）",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/companions",
		"title": "七名同伴模型（小雪 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊）",
		"author": "NEXON Games / Yostar（Blue Archive）",
		"license": "专有版权",
		"distributed": false,
		"source": "https://github.com/lihaohong6/BlueArchiveModels",
		"license_file": "",
		"note": "官方素材解包（整理者 lihaohong6 / Peterli），均取初始形态；凯伊用 Kei_ext.glb（跑动前折已修）",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models",
		"title": "主角 Arisu 模型与贴图、校园碰撞网格",
		"author": "NEXON Games / Yostar（Blue Archive）",
		"license": "专有版权；校园碰撞网格派生自泼溅扫描",
		"distributed": false,
		"source": "https://github.com/lihaohong6/BlueArchiveModels",
		"license_file": "",
		"note": "官方素材解包（整理者 lihaohong6 / Peterli）；Arisu.glb / Arisu_ext.glb / Arisu*.png（导入时自动解包）/ school.collision.glb",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "models/npc",
		"title": "老师（sensei）NPC 模型与贴图",
		"author": "食小派蒙辣",
		"license": "专有版权（派生自 Blue Archive，玩家二创）",
		"distributed": false,
		"source": "sensei_by_食小派蒙辣.zip",
		"license_file": "",
		"note": "sensei.blend（MMD/PMX 导出，313 骨、**0 条动作**）；本工程重导出为 sensei.glb：剔除 307 个刚体、贴图降到 1024、材质重建（MMD 材质树 glTF 导出器认不出，会丢贴图）。待机是程序化的（scripts/sensei_npc.gd）",
	},
	{
		"group": "角色与 Boss 模型",
		"path": "splatdata",
		"title": "校园 / 画室609 高斯泼溅扫描数据",
		"author": "由使用者提供（权利状态未核实）",
		"license": "未核实 —— 拍摄权、场地权、肖像权、再分发权均未确认",
		"distributed": false,
		"source": "",
		"license_file": "",
		"note": "*.sogdata / *.sog；缺失时用 -- --splat=off 照样能跑",
	},

	# ---------- 界面与字体 ----------
	{
		"group": "界面与字体",
		"path": "assets/ui",
		"title": "UI Pack: Pixel Adventure 2.0（九宫格面板 / 按钮切片）",
		"author": "Kenney",
		"license": "CC0 1.0（公有领域，可商用、无需署名）",
		"distributed": true,
		"source": "https://kenney.nl/assets/ui-pack-pixel-adventure",
		"license_file": "assets/ui/LICENSE_Kenney_UI-Pack_CC0.md",
		"note": "tile_panel.png / tile_button_hover.png 的中心被填成白色（原图中空），CC0 允许修改",
	},
	{
		"group": "界面与字体",
		"path": "assets/ui/font.ttf",
		"title": "Fusion Pixel Font 12px（中文像素字体，整套 UI 的兜底字）",
		"author": "TakWolf",
		"license": "SIL OFL 1.1（允许随软件分发）",
		"distributed": true,
		"source": "https://github.com/TakWolf/fusion-pixel-font",
		"license_file": "assets/ui/LICENSE_FusionPixel_OFL.txt",
		"note": "覆盖 19214/20992 个 CJK 汉字；assets/ui_font/ 没放字时就用它",
	},
	{
		"group": "界面与字体",
		"path": "assets/ui_font",
		"title": "Aa 字库「Aa暗夜深渊」（界面显示字体）",
		"author": "Aa 字库",
		"license": "商用需授权；个人学习 / 非商业使用",
		"distributed": false,
		"source": "",
		"license_file": "",
		"note": "不可再分发，故被 .gitignore 排除；发布产物前请自行取得商用授权或换 OFL 字体",
	},
	{
		"group": "界面与字体",
		"path": "assets/ui_sprout",
		"title": "Sprout Lands UI Pack（设置界面皮肤）",
		"author": "Cup Nooble",
		"license": "免费但限非商业，禁止再分发或转售（即使修改过）",
		"distributed": false,
		"source": "https://cupnooble.itch.io/sprout-lands-ui-pack",
		"license_file": "assets/ui_sprout/LICENSE_SproutLands.txt",
		"note": "不可再分发，故被 .gitignore 排除；没有它时自动回退到上面的 Kenney 皮肤",
	},

	# ---------- 音效 ----------
	{
		"group": "音效",
		"path": "assets/sfx",
		"title": "界面 / 武器 / 换弹音效（Interface Sounds、Sci-fi Sounds、RPG Audio）",
		"author": "Kenney",
		"license": "CC0 1.0（公有领域，可商用、无需署名）",
		"distributed": true,
		"source": "https://kenney.nl/assets/interface-sounds",
		"license_file": "assets/sfx/LICENSE_Kenney_CC0.md",
		"note": "click_* / toggle_* / tick_* / open_* / close_*、laserSmall_000..004、metalLatch、metalClick",
	},
	{
		"group": "音效",
		"path": "assets/sfx/gunshot_000.wav",
		"title": "枪声 gunshot_000..004（5 条）",
		"author": "本项目作者（Python 合成：噪声 + 包络 + 带通）",
		"license": "MIT",
		"distributed": true,
		"source": "",
		"license_file": "LICENSE",
		"note": "不是采样，是算出来的；替换 laserSmall_*.ogg 是为了听起来像枪（见 README §1.19）",
	},

	# ---------- 剧情与图标 ----------
	{
		"group": "剧情与图标",
		"path": "story",
		"title": "剧情文本（开场 / 设定）",
		"author": "本项目作者",
		"license": "MIT",
		"distributed": true,
		"source": "",
		"license_file": "LICENSE",
		"note": "story/开场.txt、story/设定.md；角色名来自 Blue Archive，属同人创作",
	},
	{
		"group": "剧情与图标",
		"path": "icon.png",
		"title": "项目图标",
		"author": "待确认",
		"license": "待确认（若不是原创请替换）",
		"distributed": true,
		"source": "",
		"license_file": "",
		"note": "",
	},
]


## 供自检 / 文档生成用：所有登记过的路径。
static func all_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	for e in ENTRIES:
		out.append(e["path"])
	return out


## 某条路径是否被登记（含「父目录已登记」的情况）。
static func covers(path: String) -> bool:
	var p := path.replace("\\", "/").trim_suffix("/")
	for e in ENTRIES:
		var q: String = e["path"].replace("\\", "/").trim_suffix("/")
		if p == q or p.begins_with(q + "/"):
			return true
	return false


static func entry_for(path: String) -> Dictionary:
	var p := path.replace("\\", "/").trim_suffix("/")
	for e in ENTRIES:
		if e["path"].replace("\\", "/").trim_suffix("/") == p:
			return e
	return {}


## 游戏内「致谢」面板用的纯文本（按 GROUPS 分组）。
static func plain_text() -> String:
	var out: PackedStringArray = []
	out.append("本项目自己的代码以 MIT 授权；下面这些素材各有各的作者与许可。")
	out.append("标「不随仓库分发」的素材不在本仓库里，克隆后需要自己合法取得。")
	out.append("")
	for g in GROUPS:
		out.append("【%s】" % g)
		for e in ENTRIES:
			if e["group"] != g:
				continue
			out.append("· %s" % e["title"])
			out.append("    作者：%s" % e["author"])
			out.append("    许可：%s" % e["license"])
			if e["source"] != "":
				out.append("    来源：%s" % e["source"])
			out.append("    位置：%s%s" % [
				e["path"], "" if e["distributed"] else "（不随仓库分发）"])
			if e["note"] != "":
				out.append("    备注：%s" % e["note"])
		out.append("")
	out.append("完整表格见仓库根目录 CREDITS.md / THIRD_PARTY.md。")
	return "\n".join(out)

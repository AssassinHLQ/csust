# 素材署名与许可（CREDITS）

> **这份文件是 `scripts/credits.gd` 的人读版。** 游戏里 Esc → 设置 →「致谢与素材署名」
> 显示的是同一份数据；`scripts/_verify_credits.gd` 会断言 `models/`、`assets/`、
> `addons/`、`splatdata/` 下的**每一个目录**都在这张表里登记过 ——
> 也就是说：**新加一套素材却没署名，自检直接红。**

本项目自己的代码、场景、着色器、文档以 **MIT** 授权，见 [LICENSE](LICENSE)。
许可分两类：能随仓库分发的（✅）与**只能本地使用、不可再分发**的（❌，已被
`.gitignore` 排除，克隆者需自己合法取得才能运行对应部分）。

## 画面上最重要的三件事

1. **主角、七名同伴、两位 Blue Archive 角色的 Boss、泼溅扫描** —— 版权不属于本项目，
   只用于本地学习研究，**不得再分发、不得商用、不得用于任何发布产物**。
   这些模型取自 [BlueArchiveModels](https://github.com/lihaohong6/BlueArchiveModels)
   （Blue Archive 官方素材的解包整理版，整理者 **lihaohong6 / Peterli**）——
   **解包不改变版权**，它们仍然是 NEXON Games / Yostar 的专有素材。
2. **四位玩家二创的 Boss（飞猪 / 倭瓜 / 霍德 / 佩洛洛斯拉）出自「一个睿智」**，
   派生自 Blue Archive，同样是专有版权。署名照下面表格写。
3. **界面字体 `assets/ui_font/Aa暗夜深渊.ttf` 商用需授权**。发布前要么取得授权，
   要么删掉它（会自动回退到 OFL 授权的 Fusion Pixel）。

## 一、代码与插件

| 素材 | 作者 / 版权方 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| 全部 GDScript 代码、场景、着色器 | 本项目作者 | MIT | ✅ | `scripts/`、`scenes/`、`project.godot` | 见 [LICENSE](LICENSE) |
| 全景天空盒（粉/日/夜/黄昏） | AllSky Free（Richard Whitelock） | MIT | ✅ | `assets/sky/`，[AllSkyFree_Godot](https://github.com/rpgwhitelock/AllSkyFree_Godot) | 原图 8192~16384 缩到 4096×2048 JPEG |
| 空地地砖贴图 + 法线图 | 本项目作者（程序生成） | MIT | ✅ | `assets/tex/`，`tools/make_lot_paver.py` | 完全可平铺 |
| [GDGS](https://github.com/ReconWorldLab/godot-gaussian-splatting) 3.3.0 | ReconWorldLab | MIT | ✅ | `addons/gdgs/` | 高斯泼溅渲染插件；原许可保留在 `addons/gdgs/LICENSE` |
| 校园 GGS 泼溅光栅器（Godot 4.7 移植版） | **2Retr0**（GodotGSplat 原作者）；本项目移植到 4.7，并加了校园专用的 bin 加载与全屏合成 | MIT | ✅ | `addons/ggs_campus/`，[GodotGSplat](https://github.com/2Retr0/GodotGSplat)，许可原文 `addons/ggs_campus/NOTICE.md` | 6.14M 高斯校园 72–83 fps、约 5 GB 显存；不用 Compositor，走全屏 quad + 天空

## 二、角色与 Boss 模型

> 场上默认**只有飞猪优香**一位（不挤）；其余六位在 `scenes/bosses_standby.tscn`
> 里待命，`-- --bosses=all` 才上场。
>
> **「分发」一列**：❌ = 不随仓库分发（克隆后要自己合法取得）；✅ = 真的在这仓库里。

| 素材 | 作者 / 版权方 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| 比纳（第六位 Boss，备用） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_binah/`，来源 `比纳_by_一个睿智.zip` | `Binah_Original.fbx`，44 骨；3 个材质（本体/环、武器面、光环）；`*_Mask.png` 同上 |
| 哥利亚（第七位 Boss，备用） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_goliath/`，来源 `哥利亚_by_一个睿智.zip` | `Goliath_Decagram_Vulcan.fbx`，34 骨、单网格单材质 |
| 霍德（第四位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_hod/`，来源 `霍德_by_一个睿智.zip` | `HOD_Original.fbx`，164 骨、无动画；3 个材质；`*_Mask.png` 是原作者渲染遮罩，游戏里不绑 |
| 佩洛洛斯拉（第五位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_perorozilla/`，来源 `佩洛洛斯拉_by_一个睿智.zip` | `Perorozilla_Original.fbx`，47 骨、无动画；6 网格共用 1 材质；5 张表情变体只留 1 张 |
| 倭瓜优香（第三位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_squash/`，来源 `倭瓜优香压缩文件_by_一个睿智.zip` | `倭瓜优香.obj`，纯静态网格、无骨架；4 个材质 |
| 飞猪优香（第二位 Boss） | **一个睿智** | 专有（Blue Archive 二创） | ❌ | `models/boss_pig/`，来源 `飞猪优香 (2)_by_一个睿智.zip` | `猪猪优香.fbx`；`uv/` 里两张是作者的成品渲染图，已挪到 `ref/` 当贴图基准 |
| 霸王龙优香（第一位 Boss） | Blue Archive 玩家二创（原作者未标注） | 专有 | ❌ | `models/boss/` | `优香霸王龙.fbx`，73 骨、无动画 |
| 七名同伴（小雪 / 优香 / 诺亚 / 小桃 / 小绿 / 柚子 / 凯伊） | NEXON Games / Yostar（Blue Archive） | 专有 | ❌ | `models/companions/`，来源 [BlueArchiveModels](https://github.com/lihaohong6/BlueArchiveModels)（官方素材解包，整理者 lihaohong6 / Peterli） | 均取初始形态；凯伊用 `Kei_ext.glb` |
| RTX 5090 显卡模型（最后平台房顶的资产） | 爱给网（aigei.com）用户上传，作者未署名 | 专有（仅限学习交流，不可商用） | ❌ | `models/rtx5090/`，来源：爱给网下载的 `RTX5090.obj`（4.5 MB，29,480 面） | 2026-10-20 用户提供并当天换成高模（同目录还留着 945 KB 的 `RTX5090simplified.obj`）；`.gitignore` 排除了整个目录，缺它时屋顶用程序化占位卡 |
| BANK 招牌模型（最后平台小屋屋顶） | **使用者自制**（Rhino 导出 OBJ） | 归使用者所有 | ✅ `models/bank/BANK.obj` | `models/bank/`，2026-10-20 桌面提供 | 1765 面；文件自带一圈 `Default` 包围盒，`bank_sign.gd` 按材质名剔掉；原 `mtllib` 缺失，仓库补了一份最小 `BANK.mtl` |
| AMD Ryzen 9 9950X3D 处理器模型（609 屋顶的 149 颗，Rhino 源） | 基于用户 Rhino 导出的 9950X3D GLB 减面与分材质；参考模型来自爱给网用户上传 | 处理后的低模随仓库分发；原始 SLDPRT 仅学习交流、不可商用；AMD / RYZEN 是 AMD 商标 | ✅ `models/cpu_9950x3d/ryzen_9950x3d.glb` | `models/cpu_9950x3d/`；参考用户提供的爱给网 `.SLDPRT`（Godot/Blender 读不了）与 `P1.PNG` | Rhino 源减到 12,192 面；蓝基板 + 银 IHS + 32 颗金手指 + IHS 丝印；149 颗摆 609 画室屋顶（模型 ×3 → 36 cm），¥4,599/颗直接进银行卡（京东 2026-10 行情），合计 ¥685,251 |
| **游戏开发部部室**（商店东侧新地块） | 模型：**起航扬帆了**（Sketchfab）；围合四面墙、天花板与 Rhino 导出由使用者完成 | 授权未核实（下载包无许可文件，原模型页 UID 查 API 返回 404）——仅本地学习演示，不可再分发、不可商用 | ❌ | `models/gamedev_room/`，来源：Sketchfab《游戏开发部部室》by 起航扬帆了，下载包目录名 `游戏开发部部室_by_起航扬帆了_ebd4291471b4ef51514e232113d2c349` | Rhino 导出 6.95 MB（整屋重复一份 + Draco + 坐标轴未转）→ Blender 去重、摆正、合并成 31 个材质面 / 21,892 面，导出 4.56 MB 无 Draco GLB（`tools/build_gamedev_room.py`）；地块东延 24 m 后摆在 (52, 0.01, 0)，门朝西。**2026-11-04**：粉熊那一面改成平滑着色（原为硬边平面着色，顶点法线贴平面 2.1°）—— 面数不变（21,892 → 21,892），脚本 `tools/_smooth_gamedev_bear.py`（模型本体被 gitignore，脚本是唯一记录） |
| 游戏开发部部室碰撞 | 本项目作者（由部室 GLB 的 31 个材质面推导） | 跟随源模型：仅本地学习演示，不可再分发、不可商用 | ✅ `scenes/gamedev_room.tscn`（`Model/Collision` 下 24 块 `BoxShape3D`） | `scripts/_build_gamedev_collision.gd` 生成（幂等，可重跑） | 2026-11-03 由「1 块 21,892 面凹面 trimesh」换成 24 块具名盒子：墙 4 面（门洞那面拆成左垛 / 右垛 / 门楣）+ 地板 + 天花板 + 16 件家具。盒子在编辑器里能拖、能改 `size`。物理同机位 A/B（240 Hz 物理放大）：旧 trimesh 57.5 fps / 17.40 ms → 盒子 108.7 fps / 9.20 ms。旧 `assets/collision/gamedev_room_trimesh.res` 仍留在盘上做回退 |
| **壁挂 8×5090 机箱外壳**（游戏开发部活动室） | 爱给网（aigei.com）用户上传的 **CUSTOM GAMING PC**，作者未署名；减面 / 开窗 / 改白漆由本项目完成 | 原始模型仅限学习交流、不可商用；处理后的 2,917 面外壳随仓库分发（非商用同人） | ✅ `models/pc_case/pc_case_shell.glb` | `models/pc_case/`，来源：用户下载的 `游戏电脑机箱主机，白色 i7 RTX3090…_爱给网_aigei_com.zip` 中的 `CUSTOM GAMING PC.blend` | 94 MB / 1,035,668 面 → 只取外壳 Cube.007、开窗、白漆、0.1 比例，导出 2,917 面 / 143 KB（`tools/_export_pc_case_shell.py`）；放大 2.6× 挂南墙，内部 8 张 5090 用 `models/rtx5090_card` 的低模副本、门边双显示器用 `models/monitor`；托板 + 玻璃 + 灯由 `scripts/_build_pc_wall_case.gd` 程序化生成 |
| **RTX 5090 低模副本**（壁挂机箱里的 8 张） | 爱给网用户上传的 `RTX5090simplified.obj`，作者未署名；低模导出/居中由本项目完成 | 原始模型仅学习交流、不可商用；处理后的 6,854 面低模随仓库分发（非商用同人） | ✅ `models/rtx5090_card/rtx5090_card.glb` | `models/rtx5090_card/`，源：用户 2026-10-20 的 `RTX5090simplified.obj`（945 KB） | 6,854 面 / 299 KB；长边 0.40 m，风扇朝玻璃；8 张两列×四层（`tools/_export_rtx5090_card.py`） |
| **AM261_029 超宽显示器**（壁挂机箱旁） | 爱给网用户上传的 AM261_029，作者未署名；材质重做/屏幕程序化由本项目完成 | 原始模型仅学习交流、不可商用；处理后的 28,733 面模型随仓库分发；不使用原图贴图 | ✅ `models/monitor/monitor.glb` | `models/monitor/`，源：用户 2026-11-03 的 `29 显示器 屏幕_爱给网_aigei_com/AM261_029.fbx` | 28,733 面 / 897 KB；0.897×0.280×0.463 m；门边并排 2 台；配置单目标是 2×27" 4K 160Hz，这台是过渡（`tools/_export_monitor.py`） |
| **三星 970 EVO Plus 2TB M.2 固态**（壁挂机箱内 2 颗） | 爱给网（aigei.com）用户上传的 970 EVO Plus M.2，作者未署名；导出/摆位由本项目完成 | 原始模型仅学习交流、不可商用；**不随仓库分发**（用户 2026-11-04 明确要求：第三方素材一律 gitignore，同 `/models/rtx5090/`） | ❌ `models/ssd_970evo/`（`.gitignore` 排除） | 本地目录 `models/ssd_970evo/`，源：用户 2026-11-04 的 `三星970EVOPlus2TB m2固态硬盘ssd_爱给网_aigei_com.zip`（2.4 MB，内含 `.blend`） | 缺文件时 `_build_pc_wall_case.gd` 只 push_warning 并跳过这 2 颗硬盘，机箱照常生成（与 `gamedev_room` 同一套路）。Blender 5.2 导 GLB（脚本见工作区 `_tmp_assets/export_ssd.py`）：9,364 面 / 3.48 MB / 10 材质 / 8 张内嵌贴图；真实尺寸 80.1 × 22.2 × 1.24 mm。缩放 `0.40/0.304 ≈ 1.316`（与 5090 同一比例），两颗贴在 `pc_wall_case` 的主板背板、显卡堆下方，标签朝玻璃（`_build_pc_wall_case.gd` 的 `SSD_SCALE` 可调） |
| **DDR4 内存条**（跑酷第 9~10 段「内存条市场」，121 根） | **suuugar_mommy**（Sketchfab） | **CC BY-NC 4.0**：必须署名、**不可商用** | ✅ `models/ram/random_access_memory_ram_ddr4.glb` | `models/ram/`，来源 <https://sketchfab.com/3d-models/random-access-memory-ram-ddr4-6f37195ac2b84b21a901471485351b37> | ⚠️ 带 **NC（非商用）** 条款。GLB 的 `asset.extras` 自带这条声明，`tools/glb_meta.py` 可复核。要放进商业版本必须换成程序化盒子模型。**2026-11-03 补登记**：之前只在 README §1.16.4 提过，`credits.gd` 里没有条目，被 `models` 那条整体条目盖住，自检没报 |
| **SpaceX Falcon 9**（跑酷去程 / 回程的载具，两枚） | 模型：**Forest Katsch**（Sketchfab）；剔特效 / 材质重建 / 降贴图 / 缩放导出由本项目完成 | **CC BY-NC 4.0**：必须署名、**不可商用** —— 本工程是个人非商业同人，符合 NC 条款 | ❌ `models/rocket_falcon9/`（`.gitignore` 排除） | `models/rocket_falcon9/falcon9.glb`，来源 <https://sketchfab.com/3d-models/spacex-falcon-9-block-45-12285ccc02de4d5c91b00632f0722c92>（下载凭证存工作区 `_模型授权存档/12285ccc02de4d5c91b00632f0722c92_授权凭证.txt`） | ⚠️ **带 NC 条款，商业版本必须换掉**。下载包只有 `source/f9-block-5.blend` + 11 张 PNG、**没有 glTF**；GLB 由 `_tools/_blender_export_f9_v4.py` 转出：剔掉 47 个特效占位、把作者的自定义节点组材质**重建成标准 Principled BSDF**（glTF 导出器只认这个，否则贴图全丢）、贴图 4096→1024（12.4 MB→0.86 MB，显存约 1.3 GB→36 MB）、缩放到真实 70 m、原点挪到箭体底面中心。最终 **116,575 面 / 3 材质 / 4.81 MB**。**改动已声明**。缺文件时 `rocket_ride.gd` 用程序化占位火箭顶上，跑酷照常能飞完 |
| **柴关电脑城的新屋壳**（Sketchfab「Shop」） | 模型：**Nikitos & 3130**（Sketchfab，`vrcityphoto`）；缩放 / 居中 / 碰撞 / 只保留招牌由本项目完成 | **CC BY 4.0**：必须署名，**可商用、可再分发** | ✅ `models/shop_building/shop.glb` | `models/shop_building/`，来源 <https://sketchfab.com/3d-models/42510bda855c4e60bf5cf7ecb9a2a57c> | 极简白色店铺（白墙 + 玻璃隔断 + 吊顶灯带 + 两组玻璃展柜），原生 6.357 × 2.884 × 5.201 m / **1,158 面** / 无贴图。按用户选的「长度对齐」缩放 2.0764 → **13.20 × 10.80 × 5.99 m**，正面 z 对齐老壳，多出的进深往 −Z 长，柜台/芹香位置不动。**只保留招牌**：原程序化屋顶/三面墙/门柱/幕墙/货架全部移除，改为 GLB + 5 块不可见碰撞盒。GLB 原点离网格很远（中心 212.2, −242.0, 1.1），`shop.gd::_build_shell_from_glb()` 现量包围盒再居中；烘焙时保持 instance 引用 |
| **蒙德里安大楼外壳**（第二关） | 使用者提供（来源未注明） | 授权未核实 —— 暂按「使用者自有」处理，对外发布前必须补证 | ✅ `models/mondrian/mondrian_building.glb` | `models/mondrian/`，源：工作区的 `蒙德里安建筑/mondrian_building.blend`（2026-10-31） | ⚠️ 待补证：GLB 的 `asset` 段没有 `copyright` / `extras`，仓库里也没有对应的导出脚本记录。158 网格 / 8 材质 / 0 贴图；导出时对正门、北门做了布尔切洞。**2026-11-03 补登记**，同样是被 `models` 整体条目盖住 |
| 主角 Arisu 模型与贴图、校园碰撞网格 | NEXON Games / Yostar（Blue Archive） | 专有 | ❌ | `models/Arisu*.glb`、`Arisu*.png`、`school.collision.glb`，来源同上 | 贴图由 Godot 导入 glb 时自动解包。**2026-11-05 补**：同一套模型站（`BlueArchiveModels`）里还有 4 个爱丽丝形态，已收进本地：`Arisu_Maid.glb`（女仆，184 骨 / 32 动作）、`Arisu_Battle.glb`（临战机甲，191 骨 / 35 动作）、`Arisu_Battle_Scenario.glb`（机甲·剧情，137 骨 / 11 动作）、`Arisu_Battle_Carrier.glb`（机甲·载具，191 骨但**只有 Idle/Walk** 两条动作，当皮肤用会缺待机/攻击）。5 套骨架同族（`Bip001`），关键骨（手/头/眼）全在；差异只在网格根名（`Aris_Original_*` / `CH0200_*` / `CH0334_*`）与动作名 |
| 校园 / 画室609 高斯泼溅数据 | **知天下 AI 生成**（由使用者提供） | 权利状态未核实（再分发权由使用者确认） | ❌ | `splatdata/*.sogdata` | 校园与画室609 的泼溅由 **知天下 AI** 生成；缺失时用 `-- --splat=off` |
| 老师（sensei）NPC 模型 | **张伟事务所** | 专有（Blue Archive 二创） | ❌ | `models/npc/`，来源 `Sensei_by_张伟事务所.zip` | **卡通版**：Rigify 骨架 338 骨、**0 条动作**、**0 张贴图**（颜色全在顶点色里）。带 55 个 `cs_*` 控制器网格，载入即删；网格几乎整块绑在 `head.x` 上，手臂只能掰顶点。见 `scripts/sensei_npc.gd` 与 README §8.9 |
| 老师（sensei）旧版模型与贴图 | **食小派蒙辣** | 专有（Blue Archive 二创） | ❌ | 已换成上面的卡通版；旧文件留在 `_sensei_out/sensei_tex.glb` | MMD/PMX 导出，313 骨、0 动作；本工程曾重导出为 `sensei.glb`（删 307 个刚体、贴图降到 1024、材质重建 —— MMD 材质树 glTF 导出器认不出，会静默丢贴图） |
| **柴关电脑城店员「黑见芹香」（Serika，校服版）** | 原作 © **NEXON Games / Yostar**（Blue Archive），模型包整理者未署名 | 专有（Blue Archive） | ❌ | `models/npc/serika/serika.glb`，来源：BlueArchiveModels 模型包（2026-10-22 用户指路 `Downloads/BlueArchiveModels-main`） | 93 骨 `Bip001` 骨架、40 条动画，待机播 `Normal_Idle`；包围盒 0.67×1.39×0.50 m、原点在脚上方 0.27 m（`shop_clerk.gd` 自动抬到踩地）。手骨 `Bip001 L/R Hand` 高 0.72 m 低于台面 0.88 m，藏在柜台后；光环 `Serika_Halo` 走 `HaloFix` 抛光。见 `scripts/shop_clerk.gd`。店名 2026-10-26 从「天使24」改成「柴关电脑城」（便利店 → 电脑城，她才有理由站在这儿） |
| （已停用）天使24 店员「小空」（Sora） | 薛定谔的小问号 | 专有（Blue Archive 二创） | ❌ | `models/npc/sora/`（文件仍在，不再上场） | 2026-10-22 起停用：用户要求「小空出差」，且 338 骨 MMD 精细模型与卡通大头小人的同伴画风不统一 |

## 三、界面与字体

| 素材 | 作者 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| [UI Pack: Pixel Adventure](https://kenney.nl/assets/ui-pack-pixel-adventure) 2.0 | Kenney | **CC0 1.0** | ✅ | `assets/ui/`，许可原文 `assets/ui/LICENSE_Kenney_UI-Pack_CC0.md` | 九宫格面板 / 按钮切片；`tile_panel.png`、`tile_button_hover.png` 的中心被填成白色（原图中空），CC0 允许修改 |
| [Fusion Pixel Font](https://github.com/TakWolf/fusion-pixel-font) 12px | TakWolf | **SIL OFL 1.1** | ✅ | `assets/ui/font.ttf`，许可原文 `assets/ui/LICENSE_FusionPixel_OFL.txt` | 中文像素字体，覆盖 19214/20992 个 CJK 汉字；整套 UI 的兜底字 |
| Fusion Pixel Font 12px · 游戏开发部招牌子集 | TakWolf | **SIL OFL 1.1** | ✅ | `assets/ui/gamedev_sign_12px.ttf`，许可原文同左 | 只保留招牌/铭牌用字（游戏开发部、楼梯、临时服务器据点、终点、8×5090x、按F开机、已在线等，7.5 KB）；12 px 原生网格、关抗锯齿 + nearest 采样，3D 招牌显示为硬边像素字 |
| Aa 字库「Aa暗夜深渊」 | Aa 字库 | **商用需授权**（个人学习 / 非商业可用） | ❌ | `assets/ui_font/` | 现在实际使用的界面字体；不可再分发，故被 `.gitignore` 排除 |
| [Sprout Lands UI Pack](https://cupnooble.itch.io/sprout-lands-ui-pack) | Cup Nooble | 免费但**限非商业、禁再分发** | ❌ | `assets/ui_sprout/`，许可原文 `assets/ui_sprout/LICENSE_SproutLands.txt` | 没有它时自动回退到上面的 Kenney 皮肤 |

## 四、音效

| 素材 | 作者 | 许可 | 分发 | 位置 / 来源 | 说明 |
|---|---|---|---|---|---|
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) / [Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) / [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | **CC0 1.0** | ✅ | `assets/sfx/`，许可原文 `assets/sfx/LICENSE_Kenney_CC0.md` | `click_*`、`toggle_*`、`tick_*`、`open_*`、`close_*`、`laserSmall_000..004`、`metalLatch`、`metalClick` |
| 枪声 | 本项目作者（Python 合成） | MIT | ✅ | `assets/sfx/gunshot_000.wav` ~ `gunshot_004.wav` | 不是采样，是算出来的：噪声 + 包络 + 带通，见 README §1.19 |
| 商店配音（芹香 / 小桃 / 爱丽丝，GPT-SoVITS） | 音色模型：**SLNeil**（B站）；台词由本项目撰写（[B站空间](https://space.bilibili.com/523537077)） | 模型免费、仅供学习交流，禁止商用与违法用途；生成音频沿用 Blue Archive 角色声音，仅本地演示，不可再分发 | ❌ | `story/voice/shop/` | GPT-SoVITS 生成 12 句（serika_01…09 / momoi_01…02 / aris_01）；爱丽丝前半句「邦邦咔邦」替换为用户提供的 DSH 余额挂件皮肤视频原声（BA 角色声音，NEXON/Yostar，仅本地），与 TTS「就这套了」拼接成 aris_01，候选 `aris_01_authentic_v1..3`；整个目录被 `.gitignore` 排除 |
| 商店 BGM：UNDERTALE「Tem Shop」（40.2094 s 无缝循环版） | Toby Fox / Materia Collective | 专有版权 —— 仅本地学习，不得再分发、不得用于任何发布产物 | ❌ | `assets/music/`，来源 UNDERTALE | 音频本体被 `.gitignore` 排除；`*.ogg.import` 进仓库（循环开关在里面），克隆者需自备文件 |

## 五、剧情与图标

| 素材 | 作者 | 许可 | 分发 | 位置 | 说明 |
|---|---|---|---|---|---|
| 剧情文本（开场 / 设定） | 本项目作者 | MIT | ✅ | `story/` | 角色名来自 Blue Archive，属同人创作 |
| 项目图标 `icon.png` | **待确认** | 待确认 | ✅ | `icon.png` | 若不是原创请替换为自有图标 |
| 工具墙图标（7-Zip / GitHub / hashcat / Ollama / 知天下） | Simple Icons（CC0 矢量）+ 各商标持有人；hashcat / 知天下 图标由使用者提供 | 矢量图 CC0 1.0；图标本身是各厂商商标，仅作演示与识别用 | ✅ | `assets/icons/`，[simpleicons.org](https://simpleicons.org/) | CC0 只覆盖著作权、不授予商标权；知天下图标对外发布前需向主办方确认 |
| 柴关电脑城配置单插图（B300 / 八卡 5090 两张） | 本项目作者（Pillow 排版）+ AI 生成（GPT-Image 2.5，接口 [usa0.top](https://usa0.top)） | 排版与文案原创（MIT）；B300 那张右侧为 AI 生成图，5090 那张右侧为网络整机图（见 SOURCES.md） | ✅ | `assets/story/config_sheet.png`、`config_sheet_5090.png`、`hero_b300.png` | 两张都是 1600×970；中文用微软雅黑排版（AI 直接画中文字会糊） |
| 配置单悬停用的零件照片（19 张） | NVIDIA / Intel / AMD / 三星 / 金百达 / 超花（Super Flower）/ Corsair 等厂商及知乎、IT之家、搜狐、什么值得买、阿里巴巴、中国制造网等媒体/商城 | 第三方新闻 / 商品图，**未获授权**：仅限本地学习演示，不得再分发、不得商用 | ❌ | `assets/story/parts/` | gpu / server / cpu / ram / ssd_m2b / ssd / nic / cooling / psu / gpu5090 / hero_5090 / frame / cpu_tr / ram_udimm / ssd_m2 / ssd_t705 / psu_atx / cooling_fan / monitor，统一裁成 492×560 深色底；两张单九行都是各自独立的照片，没有一张重复；**逐张出处见 [`assets/story/parts/SOURCES.md`](assets/story/parts/SOURCES.md)**；缺图时配置单照常显示，只是悬停不换图 |
| 游戏开发部活动室配图（买完电脑 · 确认收货地址） | Blue Archive 游戏内场景（NEXON Games / Yostar）；截图由使用者提供 | 专有：仅本地学习演示，不可商用、不可再分发 | ❌ `assets/story/gamedev_room.jpg` | `资产/story/`；用户 2026-11 提供 `BG_GameDevRoom.jpg` | 商店买完整机后「确认收货地址」弹图，配文「千禧年学院一年级游戏开发部活动室」；`.gitignore` 排除 |

> ⚠️ `assets/story/parts/` 里那 19 张是网上找来的产品照，**没有授权**。
> 本地玩没问题，**任何形式的发布前必须换成**厂商 press kit、CC0 图或自己拍的，
> 换完记得同步 `SOURCES.md` 与本表，再跑 `_verify_credits.gd`。

## 怎么改

1. 加一套素材 → 在 `scripts/credits.gd` 的 `ENTRIES` 里加一条（`path` 写目录即可覆盖其下全部文件）。
2. 同步这张表与 `THIRD_PARTY.md`（前者面向「谁做了什么」，后者面向「许可合规」）。
3. 跑 `--script res://scripts/_verify_credits.gd`：漏登记、缺许可原文、把私有素材漏进仓库，都会红。

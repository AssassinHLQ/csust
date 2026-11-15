# 校园 gsplat-stream 接入与实测

2026-11-15，校园使用本项目修改版 `godot-gsplat-stream` 的
`GaussianStreamNode`。`scripts/campus_stream.gd` 保持原有加载接口。
当前默认关闭 LOD，加载全部 6,144,827 点；可显式开启流式 LOD。
下文 96 / 192 节点性能数据指开启 LOD 的早期对照，不是当前默认画质。

插件取自相邻 `godot-gsplat-stream` 工作区，基础版本为
`448e0f6a57bbffb6ca19b6bde3005c7eeb5178a3`，同时包含该工作区当时未提交的
LOD 重试缓存优化。文件清单与原始 SHA256 见
`tools/fixtures/campus_stream_installation.json`。既有碰撞管线修改未被覆盖。
游戏已有的 Raster 动态效果与分组排序、光照变化容差、RenderingDevice 辅助函数
继续保留；场景切换接口适配为同时清空常规与流式注册表，并释放共享 GPU 工作区。

## 坐标与数据

- 源扫描为现有校园 fine SOG 分块，共 6,144,827 点。
- 对位置应用现有 `chunks.json` 中的 `frame.axes` / `frame.origin`，对协方差
  应用 `A C Aᵀ`。这与当前 SplatTransform 碰撞使用的坐标一致。
- 包内数据已经是世界坐标，流式子节点采用 `top_level` 和单位变换。
  不再叠乘 Campus 父节点变换、75 倍缩放或自动居中偏移。
- 对旧校园 packed 数据抽取 6,091 个点匹配，位置误差 p95 为 0.0615 mm、
  最大 0.1304 mm；协方差相对误差最大约 0.00000160。
- q24 / SH0，区块容量 16,384 点；1,952 个节点，含 1,666 个叶节点。
  LOD 代表点使磁盘总记录数为 10,830,651；二进制大小 259,935,624 字节。
- `campus.nodes.bin` SHA256：
  `8f4852c3062e4360e6b52a6211cb54d53245da915b477b3d564f3cd61f18f6d0`。

开启 LOD 时预算 96 节点、请求 SSE 1 px、每帧最多启动两次区块读取。
节点预算不足时选择器会提高实际 SSE：入口实测为 8.3521 px。
这不是与完整 SH 高阶数据等画质的替换；远景会简化，方向相关颜色只保留 DC。
已查看入口、机甲落地和返回大厅的实际 GPU 截图；原航拍扫描贴地观察仍有拉伸和模糊。
增大到 192 节点后入口实际 SSE 为 4.913 px，但部分路线帧率下降，因此 LOD 模式保留 96 预算。

## 关闭 LOD（当前默认）

此插件没有“一千万点以下不触发 LOD”的运行时判断。`GaussianStreamLod.select()`
始终按 SSE 和节点预算选择代表点；离线 `ply_to_packed.py --target=10000000`
是目标数据量参数，与运行时是否简化无关。

用户要求关闭 LOD 后，默认 `stream_lod_enabled = false`。加载
`campus_full.manifest.json` / `campus_full.nodes.bin`：完整读取原包 1,666 个叶节点的
6,144,827 点，排除全部父节点代表点，按 q24 投影着色器的公式解码成 52 B f32
记录并合并成单个叶节点。没有抽样、协方差加粗或重定位，节点预算不能再使其降级。
这保持既有叶节点的量化精度与 SH0，不会恢复转换前已省略的高阶 SH。

完整点包为 319,531,004 字节，SHA256：
`ae93c52376fad9e69b42506ed8ca4d0afc8f4818244ea853965e3f1cd12768b8`。
它与 LOD 包都位于现有导出包含目录，派生二进制仍不入 Git。
`tools/build_campus_stream.py` 重建时同时生成这份包；已有 LOD 包时可单独运行
`python tools/build_campus_full_detail.py`。

最终关闭 LOD 的相同实景路线：入口平均 45.52 FPS、返回大厅 60.01 FPS、
接缝 42.14 / 56.58 / 45.15 / 44.42 FPS、机甲下降 42.04 FPS。
全部 6,144,827 点驻留；GPU 缓冲申报 1,442.9 MiB
（约 1.409 GiB，不是整个游戏的物理显存占用）。40 项通过，无 ERROR / SCRIPT ERROR。
该对照还改变了存储布局与上传粒度，不能把所有性能差异只归因于 LOD 算法本身。
在同一关卡回大厅时仍保留完整缓冲；切换场景清理与再进入重建均通过。

完整点模式的最终报告和截图在 `_tools/_tmp/gsplat_stream/full_detail_final/`。
另通过完整点包 PCK 包含/挂载/字节一致性 14 项、转换测试 2 项、
原有四组插件测试；主场景在独立后台桌面完成 12 项冒烟，无引擎错误。
早先 headless 主场景的 12 项断言也通过，但 dummy 渲染器报告 HUD 材质 RID
错误，因此以真实渲染冒烟为准。所有图形测试均未切换用户桌面，前台句柄保持一致。

命令行 `--campus-lod=on` 显式恢复原流式简化，`--campus-lod=off` 强制完整点数。
原始直接渲染路径仍可用 `--campus-renderer=gdgs` 选择。

## 修复流式数据搬移

真实移动测试发现原插件在 IO 完成与淘汰同帧发生时，会先为新数据分配槽位，
再压紧槽位。GPU 快照按“先 move、后 upload”回放，这会搬走尚未上传的数据，
并把新数据留在旧地址，产生大片错位/放大的泼溅。

已改为先淘汰压紧、再接收完成的 IO。字节级回放回归在修复前稳定失败，
修复后 101 个移动前沿、102 次修订均一致。
另修正 GPU 消费者的修订确认：只确认实际消费的快照末尾，避免把并发新发布的
修订误当成已应用而跳过。修复位于本游戏的插件副本，未修改相邻插件仓库。

## 实景性能

同一正式 `next_level.tscn`、1600×900、RTX 4060 Laptop / Vulkan Forward+、
默认画质与 60 FPS 上限。使用真实玩家输入、物理和实时渲染；冻结敌人攻击与自动流程。
旧版数据取自同目录此前的完整点云验收，具体条件见 `CAMPUS_COLLISION.md`。

| 阶段 | 旧版平均 FPS | 流式 96 平均 FPS | 旧版 p95 | 流式 96 p95 |
| --- | ---: | ---: | ---: | ---: |
| 大厅进入校园 | 44.16 | 60.01 | 34.17 ms | 17.07 ms |
| 校园返回大厅 | 50.61 | 60.01 | 24.63 ms | 17.10 ms |
| 接缝 0 正向 / 反向 | 31.44 / 43.16 | 60.22 / 60.21 | 36.16 / 27.21 ms | 17.05 / 17.16 ms |
| 接缝 1 正向 / 反向 | 40.34 / 29.43 | 60.20 / 60.09 | 27.19 / 46.18 ms | 17.30 / 17.01 ms |
| 机甲下降 | 29.59 | 60.00 | 39.38 ms | 17.44 ms |

入口路线最大单帧由 2,564.78 ms 降为 18.50 ms；最终轮首批区块驻留约 2.359 秒，
此前修复后 96 预算轮为 1.422 秒。
首批驻留不代表完整精度收敛，不能和旧版 13.9 秒全量解码直接作为等量加载比较。
入口驻留约 780,296 点，整条路线峰值 922,924 点；插件声明的 GPU 缓冲约
310.6 MiB，不是整个游戏的物理显存占用。
192 节点对比轮入口约 59.30 FPS，接缝 1 正向约 50.27 FPS。

修复后的 96 与 192 预算初轮均为 **35 通过 / 0 失败**；最终兼容适配后
96 预算轮为 **38 通过 / 0 失败**，实际渲染日志无 ERROR / SCRIPT ERROR。
覆盖桥往返、两处接缝双向、地面和空中五秒原地复活、机甲落地、屏幕外窗口及
鼠标不捕获。新增覆盖场景释放 GPU 缓冲、同一包重新加载与 GPU 状态重建。
独立 Windows desktop 不切换用户桌面，测试配置与存档隔离。
其他程序可能共享 GPU，短接缝样本有限；未测试最终打包 exe 和 Boss 混战性能。

## 复现与打包

```powershell
# numpy / scipy / Pillow；默认读取相邻 godot-gsplat-stream 的离线工具。
python tools/build_campus_stream.py
# 已有 raw 工作文件时使用新的 --work；不覆盖工作文件。

$gd = 'D:/SOFTWARE/Godot-4.7.1-dotnet/Godot_v4.7.1-stable_mono_win64/Godot_v4.7.1-stable_mono_win64.exe'
python tools/run_godot_private_desktop.py --godot $gd --project . --script res://scripts/_verify_campus_rendered.gd --out _tools/_tmp/gsplat_stream/check --timeout 360 -- --rendered-out=res://_tools/_tmp/gsplat_stream/check --stream-reentry
# 末尾追加 --campus-lod=on 可对比流式简化。
# --campus-lod=on --campus-stream-budget=192 可对比更高预算。
# 末尾追加 --campus-renderer=gdgs 可回退原直接渲染路径。
```

离线重建已完整跑通，并复现上面的二进制 SHA256。
资源位于 `splatdata/campus_stream/`，manifest 使用同目录相对路径。
`export_presets.cfg` 显式包含整个目录；Git 忽略派生二进制与导出无关，数据仍随打包携带。
`_verify_campus_stream_pack.gd` 的 14 项检查证明过滤规则允许两份文件，并实际建立、
挂载包含完整二进制的 PCK，以 115 个分散节点的随机读取验证字节一致。
这不等于已导出并实测完整发行 exe。

`tools/gsplat_stream_tests/` 中的 LOD、运行时、排序预算、可见预算四组测试通过；
主场景 `_smoke_build.gd` 为 12 通过 / 0 失败。
结果、日志、截图和 PCK 检查产物位于忽略的 `_tools/_tmp/gsplat_stream/`，不入库。
最终完整报告与截图为 `_tools/_tmp/gsplat_stream/final96_reentry/`；最终轮启动前后
用户前台窗口句柄一致，进程退出码为 0。

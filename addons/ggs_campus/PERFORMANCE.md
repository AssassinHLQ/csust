# 校园渲染性能验证

目标：后台 AI 模型运行时，第二场景校园争取稳定 165 FPS，帧时间预算约 6.06 ms。

## 2026-11-14：静止复用和上传预算

- 静止复用使用上一次实际提交的相机矩阵、位置、分辨率、模型缩放、协方差参数及热图开关作为缓存键。主线程连续更新两次相机不会吞掉待渲染的移动。
- 每次真正渲染前重置间接调度尺寸，避免沿用历史密集视角的最大工作组数量。
- 删除每帧重复的 RGBA32F 清屏：光栅化着色器覆盖所有 tile 内的像素，空 tile 写透明。初始化时仍清屏，确保上传期间透明。
- GPU 时间戳默认关闭，诊断时设置 `profile_timestamps = true`。
- 同一渲染设备按路径及完整源码复用 CPU 编译的 SPIR-V；源码改变会重新编译，失败结果不缓存。GPU shader RID 仍由各 context 独立持有及释放。
- 每层上传使用累计 1 ms 软预算，包含读取、时间字段采样与所有上传调用；从 128 KiB 开始，在 64 KiB 至 4 MiB 之间自适应。单次驱动调用无法抢占，因此不构成硬性帧时间保证。
- 不改分辨率、SH 阶数、校园默认开关或后台 AI 设置。

## 可重复的无窗口检查

使用 Godot 4.7.1，在本工程目录执行：

```powershell
& '<Godot console executable>' --headless --path . --audio-driver Dummy --script res://scripts/_test_campus_render_idle.gd -- --no-capture --splat=off --story=off
& '<Godot console executable>' --headless --path . --audio-driver Dummy --script res://scripts/_smoke_build.gd -- --no-capture --splat=off --story=off
```

第一项用设备替身记录 GPU 命令，覆盖静止 1000 tick、相机/参数变化、调度重置、时间戳开关和累计上传预算，并核对上传字节完整性。第二项为工程既有的 12 项构建冒烟检查。

这些检查验证控制流程和数据完整性，不能代表实际 GPU 帧率。165 FPS 尚需在相同后台 AI 负载、分辨率和校园路径下，记录加载及移动阶段的帧时间分布后验收。

## 隔离桌面 GPU 检查

2026-11-14 在 RTX 4060 Laptop / Godot 4.7.1 / Vulkan Mobile 上，用校园粗层均匀抽取的 32,768 点、800×450 目标做限规模检查。测试进程通过 Windows 独立桌面启动，始终不切换输入桌面，运行前后输入桌面均为 `Default`。

- 真正执行投影、排序及光栅化着色器后有非透明输出；静止 60 tick 的复用纹理保持一致；把相机移到校园外，所有像素恢复透明。
- 在同一进程内释放并重建三次。未加 SPIR-V 缓存的完整 `init_gpu()` 调用为 204.2 / 31.5 / 27.9 ms；加缓存后为 159.6 / 12.7 / 12.1 ms。可比的后两次重建下降约 56%–60%，首次创建仍有明显编译开销，尚未满足 6.06 ms 加载帧预算。
- 后台负载在测试间变化，抽样渲染的 GPU p95 出现约 0.15–7.84 ms 的波动。这是单层抽样的 compute 时间，不是完整校园或游戏 FPS，不能外推到 165 FPS 验收。
- Godot 在编译时打印 `OpArrayLength is not supported yet.`，基线与修改后均存在；最终检查没有 `SCRIPT ERROR` 或失效资源报错。

GPU 探针及原始日志保存在独立插件的 `_tools/_tmp/` 下，属于验证产物，不纳入 Git。

专项回归为 40/40。2026-11-14 公共脚本恢复后，重新运行整工程冒烟 12/12 通过，没有脚本解析错误。

工程原有 headless 冒烟在退出时会打印 dummy 后端 `material_set_shader` 的空材质错误；优化前的基线同样存在。应单独追踪，不能据此认定本次引入回归。

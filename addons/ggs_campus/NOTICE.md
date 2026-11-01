# 校园 GGS 泼溅光栅器 · 来源与许可

本目录（`addons/ggs_campus/`）是校园高斯泼溅（3DGS）的 GPU 光栅化实现，
**移植自 2Retr0 的 GodotGSplat**，并按本项目需要做了改动：

- 移植到 Godot 4.7（`RenderingDevice` 接口对齐）
- 增加校园专用的 `campus_ggs.bin` 打包格式加载（`ply_file.gd` 里的 bin 分支）
- 去掉 Compositor，改走全屏 quad + 天空合成（`scripts/campus_ggs.gd` 驱动）
- 去掉训练/可视化用不到的部分，只留渲染

- 上游项目：https://github.com/2Retr0/GodotGSplat
- 上游作者：2Retr0
- 上游许可：MIT

```
MIT License

Copyright (c) 2024 2Retr0

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

> 移植部分的改动同样以 MIT 发布。如果上游许可有更新，以
> https://github.com/2Retr0/GodotGSplat 仓库内的 LICENSE 为准。

# GDGS attribution / GDGS 作者与来源

## Original plugin / 原插件

**GDGS is developed by ReconWorldLab and its upstream contributors.**

- Original project: https://github.com/ReconWorldLab/godot-gaussian-splatting
- Original copyright: `Copyright (c) 2026 ReconWorldLab`
- License: [MIT](LICENSE), retained without replacing the original author.

原插件 GDGS 由 ReconWorldLab 与上游贡献者开发。原有 Compute 与 Raster 渲染器、
导入器、编辑器集成、碰撞生成和重新打光等功能来自 GDGS。原作者与相应贡献者应获得这些工作的署名。

## This modified distribution / 本修改版

`gsplat-stream` is maintained by AssassinHLQ:
https://github.com/AssassinHLQ/godot-gaussian-splatting

AssassinHLQ maintains modifications on top of GDGS, including Compute memory
optimizations, packed records, streaming LOD, tests and documentation. This is
not a claim to authorship of the original plugin. The modifications are also
distributed under MIT. The fork is not an official ReconWorldLab or Godot
Engine release and does not imply their endorsement.

AssassinHLQ 仅维护在 GDGS 基础上的修改，包括显存优化、紧凑数据、流式 LOD、
测试及文档整理，不是 GDGS 原作者。修改部分同样采用 MIT 许可证。

## Upstream acknowledgements / 上游致谢

The following acknowledgements follow GDGS's upstream documentation and shader
headers. Existing source attribution headers remain in place.

- **PlayCanvas Ltd. / splat-transform**: GDGS's collision pipeline ports its
  voxelization and collision approach. Project:
  https://github.com/playcanvas/splat-transform
  Full MIT notice: [third_party/splat-transform.LICENSE](third_party/splat-transform.LICENSE).
- **2Retr0 / Ethan Truong / GodotGaussianSplatting**: reference for GDGS's
  shader work. Project: https://github.com/2Retr0/GodotGaussianSplatting
  Full MIT notice: [third_party/GodotGaussianSplatting.LICENSE](third_party/GodotGaussianSplatting.LICENSE).
- **jaesung-cs / vulkan_radix_sort**: source identified by the upsweep, spine
  and downsweep radix-sort shader headers. Project:
  https://github.com/jaesung-cs/vulkan_radix_sort
  Full MIT notice: [third_party/vulkan_radix_sort.LICENSE](third_party/vulkan_radix_sort.LICENSE).
- **@4321ba**: upstream editor icons, visibility handling and shared-data
  instancing support: https://github.com/ReconWorldLab/godot-gaussian-splatting/pull/6

License texts were retrieved on 2026-11-14 from these source revisions:

| Project | Revision | License file |
| --- | --- | --- |
| PlayCanvas splat-transform | `6f642939dd5d5db3094bf749d5821ce84e3938da` | `LICENSE` |
| 2Retr0 GodotGaussianSplatting | `181ef73989adc9a80ef382cca282751cb8551279` | `LICENSE` |
| jaesung-cs vulkan_radix_sort | `b0db22b0c65e17a9b803bc4daf20354898b820eb` | `LICENSE` |

Keep the applicable copyright and permission notices with redistributed copies.
Third-party components retain their own copyright notices; the fork's MIT
license does not replace them. Imported scans and other external assets retain
their own terms and are not relicensed by this notice.

# assets/icons —— 「工具墙」用的图标

2026-10-22 用户：「后续需要找 7zip 图标素材、hashcat 图标、github、ollama、知天下 AI 图标」

| 文件 | 尺寸 | 来源 | 许可 / 权利 | 状态 |
|---|---|---|---|---|
| `7zip.svg` | 24×24 矢量 | [Simple Icons](https://simpleicons.org/) `7zip.svg` | **CC0 1.0**（著作权放弃） | ✅ 社区重绘的单色版，不是 7-Zip 官方位图 |
| `github.svg` | 24×24 矢量 | 同上 `github.svg` | **CC0 1.0**（著作权放弃） | ✅ |
| `ollama.svg` | 24×24 矢量 | 同上 `ollama.svg` | **CC0 1.0**（著作权放弃） | ✅ |
| `hashcat.png` | 256×256 RGBA | **用户 2026-10-22 提供**（原 128×128） | 图标版权归 hashcat 作者（软件本身是 MIT，**图标不在 MIT 里**） | ✅ 已裁掉白边 + 自己切 22% 圆角 |
| `zhitianxia.png` | 512×512 RGBA | **用户 2026-10-22 提供**（原 700×700 JPG） | 著作权归**主办方「知天下」** | ⚠️ 本项目演示/答辩可用；对外发布前请向主办方确认 |

## ⚠️ CC0 ≠ 商标随便用（用户 2026-10-22 的疑问）

「CC0 1.0，可随便用？为什么他们居然是 CC0？」

两件事要分开：

1. **著作权**：Simple Icons 把 `icons/*.svg` 这些**矢量文件本身**的著作权放弃掉
   （CC0 1.0 = 公有领域），所以你可以随便复制、改色、缩放、再分发，商用也不用署名。
2. **商标权**：CC0 1.0 的法律文本明确**不授予商标权和专利权**。GitHub 的猫、
   Ollama 的羊驼、7-Zip 的 logo 仍然是各家的**商标**。所以：
   - ✅ 放进自己的游戏/演示里当图标：没问题
   - ❌ 当成自己产品的标识、或暗示「GitHub 官方合作」：不行
   - ⚠️ 厂商自己的 brand guidelines（比如 GitHub 的 logo 规范）是**商标使用规范**，
     不是著作权，但它依然是约束 —— 商用前最好扫一眼

一句话：**CC0 管的是「这张图能不能抄」，商标管的是「你能不能拿它当招牌」。**

## 用法

SVG / PNG 在 Godot 里都当 `Texture2D` 用：

```gdscript
var tex: Texture2D = load("res://assets/icons/github.svg")   # SVG 任意尺寸栅格化不糊
var hc: Texture2D = load("res://assets/icons/hashcat.png")    # 位图，按原尺寸用
```

- `hashcat.png` / `zhitianxia.png` 都是 **RGBA 透明底**，深色/浅色面板都能直接贴
  （本喵用深灰 #1C1E22 实际合成验过，没有白方框）。
- 两个 SVG 是**单色**（`fill` 是黑色），要跟主题走就把 `fill` 改成 `currentColor`，
  再用 `modulate` 上色。

## 还差什么

- **7-Zip 官方图标**是位图（`7zFM.exe` 内的 ico），这里用的是 Simple Icons 的社区
  重绘版（单色、更干净）；要原版得从 7-Zip 安装目录抠。
- **知天下**建议再向主办方要一份**矢量**（SVG/AI），现在这张 700×700 放大到 4K 会糊。

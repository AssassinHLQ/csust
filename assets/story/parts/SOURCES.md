# 配置单零件照片 · 逐张出处

> 这 10 张是**第三方新闻 / 商品图**，未经授权。
> 按 `CREDITS.md` 的规矩：**只允许本地学习演示，不得再分发、不得商用**，
> 所以 `/assets/story/parts/*.png` 已被 `.gitignore` 排除 —— 克隆者需要自己取得，
> 缺失时配置单照常显示，只是鼠标悬停不会换图（`dialogue_box.gd` 会 warning 后跳过）。
>
> 统一处理：Pillow 居中缩放进 492×560 深色底，仅作排版。

| 文件 | 对应行 | 出处（原始图片地址） | 来源站点 | 说明 |
|---|---|---|---|---|
| `gpu.png` | 显卡 | `https://picx.zhimg.com/v2-3dcf1b1371b776944589f5d87093e942_r.jpg` | 知乎图床 | 文章《英伟达推出新一代 AI 芯片 Blackwell…》配图，B300/Blackwell 模块实物 |
| `server.png` | 整机 | `https://i0.hdslb.com/bfs/new_dyn/18c7e2fd5b2fc055f8ebaa2b12f85fb91213234632.jpg` | 哔哩哔哩动态图床 | 标题《5, nvidia hgx h200 8-GPU…》，HGX 八卡基板实物 |
| `cpu.png` | 处理器 | `https://q4.itc.cn/q_70/images03/20260302/be5ff6c985f24adc9403d5529cb0cc57.jpeg` | 搜狐（ITC 图床） | 《"Clearwater Forest" 处理器更多详情…》配图，手持服务器 CPU |
| `ram.png` | 内存 | `https://assets.corsair.com/image/upload/c_pad,q_85,h_1100,w_1100,f_auto/products/Memory/base-ws-ddr5-config/gallery/4-up/WS_DDR5_01.webp` | 海盗船官方网站 | WS DDR5 RDIMM 产品渲染图 |
| `ssd.png` | 系统盘 / 数据盘 | `https://q5.itc.cn/q_70/images01/20260327/97a627c81ce240de9ec9ffed0447cf3a.png` | 搜狐（ITC 图床） | 《U.2 工业级 SSD 在工业场景中的选型…》配图 |
| `nic.png` | 网络 | `https://img.ithome.com/newsuploadfiles/2025/8/278c2c8d-fcb1-4b9a-92ad-22cbea14a866.jpg` | IT之家 | 《CX-8 超级网卡：PCIe 6.0 接口，800 Gb/s》配图（图上有 IT之家水印） |
| `cooling.png` | 液冷 | `https://pica.zhimg.com/v2-d70d3e37cda7f008f18594bd5d218ac0_r.jpg` | 知乎图床 | 《海悟液冷分配单元 CDU…》配图，机柜式 CDU + 管路 |
| `psu.png` | 配电 | `https://upload.ca168.com/202509/05/18-21-15-86-544552.png` | 中国自动化网（ca168.com） | 《麦米电气 AI 服务器电源解决方案》配图，Power shelf / PCS / BBU shelf 结构 |
| `gpu5090.png` | 显卡（5090 那张单） | `https://n.sinaimg.cn/spider20260305/240/w1440h1200/20260305/2592-4c5c20389afd98b8a97704418500d0f2.jpg` | 新浪（转华硕 ProArt 参数稿） | 华硕 ProArt RTX 5090 产品图 |
| `hero_5090.png` | 5090 那张单的右侧整机照 | `http://i1.hdslb.com/bfs/archive/5e25e08f0855e275cda7c4b86ad264258b0da561.jpg` | 哔哩哔哩 | 《8 张 5090 显卡 + 512GB 内存 组装工作站》，裁掉右下角水印 |

## 换图时怎么做

1. 找到**有明确授权**的替代图（厂商 press kit、CC0、自己拍）；
2. 覆盖同名文件即可，不用改代码；
3. 同步更新本表与 `CREDITS.md` 里 `assets/story/parts` 那条；
4. 跑 `_verify_credits.gd`，它要求 `CREDITS.md` 与 `credits.gd` 两条路径/作者一致。

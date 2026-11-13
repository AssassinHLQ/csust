# 把「阿洛娜」绿幕视频抠成 PNG 序列（电脑屏幕右半屏那个立绘，终端敲 `arona`）。
#
# 用法：
#     powershell.exe -NoProfile -ExecutionPolicy Bypass -File _tools\fetch_arona_frames.ps1
#
# 产物：`assets/arona_frames/f_0001.png …`（约 389 帧）
#       ⚠️ 第三方素材派生物，`/assets/arona_frames/` 已被 .gitignore 排除，不随仓库分发。
#
# ── 参数理由（都实测过）──
# 源视频：720×1232 / 30 fps / 32.43 s，绿幕底色实测 **(46,220,1) = #2EDC01**。
#   · **crop=720:1172:0:60** —— 先把顶部 60 px 裁掉：源视频右上角有上传者的水印
#     「浅羽香草 bilibili」。抠像只去绿色，白色水印会留在画面上飘着，很难看。
#     水印在 y≈35~55，光环从 y≈70 才开始，所以裁 60 px 是安全的。
#   · chromakey / despill 的参数与 `fetch_plana_frames.ps1` 同口径
#     （那支脚本里有详细的「为什么必须 despill」说明）。
#   · fps=12：素材 32 秒、全身立绘动作很缓，12 fps 够，帧数比 15 少两成。
#   · scale=720:-1：**按原视频宽度出**，不再缩到 300。
#     ⚠️ 2026-11-13 用户实测「arona 画质怎么变差了」：原来 300 宽是为
#        832×664 的旧画布定的，缩过头了；新画布 1280×720 里立绘要占 ~415 px，
#        窗口再放大 2× 之后 300 px 的图等于被拉 2.7 倍 → 一片糊。
#        现在出 720×1172 原尺寸，画布里只是**缩小**，不会糊。
#        代价：显存/磁盘变大，所以 `frame_anim.gd` 的 CACHE_MAX 从 48 降到 16。
#
# ⚠️ 本文件必须存成**带 BOM 的 UTF-8**（同 fetch_plana_frames.ps1 的坑：
#    Windows PowerShell 5.1 会把无 BOM 的 UTF-8 当 ANSI 读，中文路径变乱码）。

$ErrorActionPreference = "Stop"

$ffmpeg = "D:\SOFTWARE\ffmpeg\bin\ffmpeg.exe"
# 用户重下过一次素材：文件名从 `…_视频.mp4` 变成了 `…_视频(1).mp4`，
# 而且分辨率也不一样（720×1232 → **1080×1848**）。所以这里按候选列表找，
# 裁切参数也全部写成**相对表达式**，换分辨率不会裁歪。
$candidates = @(
    "C:\Users\WY157\Downloads\公益绿幕素材._视频.mp4",
    "C:\Users\WY157\Downloads\公益绿幕素材._视频(1).mp4"
)
$src = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$dst = Join-Path $PSScriptRoot "..\assets\arona_frames"

if (-not (Test-Path $ffmpeg)) { throw "找不到 ffmpeg: $ffmpeg" }
if (-not $src) { throw "找不到源视频，试过：$($candidates -join ' / ')" }

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem $dst -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

# ── 滤镜链 ──
# ① crop：把顶部 4.87% 裁掉（水印所在的横带）。用相对量，换分辨率也对。
# ② drawbox：**把右上角一块刷成纯绿**。
#    为什么还要这一步：水印是**白色半透明字**，chromakey 只去绿色，白字会留下来
#    （300 宽那版在立绘右上角就飘着一行隐约的白字）。纯绿正好是 key 色，
#    抠完这块 alpha=0，既不留字、也不用把光环尖一起裁掉。
# ③ chromakey 0x2EDC01 + despill：去绿幕、去绿边（参数与 plana 那支同口径）。
# ④ fps=12 / scale=720：见上面第 17 行的说明。
$filter = "crop=iw:trunc(ih*0.9513/2)*2:0:trunc(ih*0.0487/2)*2," +
          "drawbox=x=iw-240:y=0:w=240:h=80:color=0x2EDC01:t=fill," +
          "chromakey=0x2EDC01:0.16:0.06," +
          "despill=type=green:mix=1:expand=0.3," +
          "fps=12,scale=720:-1:flags=lanczos,format=rgba"

& $ffmpeg -v error -i $src -vf $filter -vsync 0 -compression_level 6 `
    -y (Join-Path $dst "f_%04d.png")

$n = (Get-ChildItem $dst -Filter *.png).Count
$mb = [math]::Round(((Get-ChildItem $dst -Filter *.png | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "[arona] 抠像完成：$n 帧 / $mb MB → $dst"
if ($n -lt 100) { Write-Warning "[arona] 帧数异常偏少，检查源视频路径与 chromakey 参数" }

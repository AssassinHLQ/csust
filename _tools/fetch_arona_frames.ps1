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
#   · scale=300:-1：屏幕 SubViewport 是 832×664，她占右半屏（约 300 px 宽）刚好。
#
# ⚠️ 本文件必须存成**带 BOM 的 UTF-8**（同 fetch_plana_frames.ps1 的坑：
#    Windows PowerShell 5.1 会把无 BOM 的 UTF-8 当 ANSI 读，中文路径变乱码）。

$ErrorActionPreference = "Stop"

$ffmpeg = "D:\SOFTWARE\ffmpeg\bin\ffmpeg.exe"
$src = "C:\Users\WY157\Downloads\公益绿幕素材._视频.mp4"
$dst = Join-Path $PSScriptRoot "..\assets\arona_frames"

if (-not (Test-Path $ffmpeg)) { throw "找不到 ffmpeg: $ffmpeg" }
if (-not (Test-Path $src)) { throw "找不到源视频: $src" }

New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem $dst -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

$filter = "crop=720:1172:0:60,chromakey=0x2EDC01:0.16:0.06," +
          "despill=type=green:mix=1:expand=0.3," +
          "fps=12,scale=300:-1:flags=lanczos,format=rgba"

& $ffmpeg -v error -i $src -vf $filter -vsync 0 -compression_level 6 `
    -y (Join-Path $dst "f_%04d.png")

$n = (Get-ChildItem $dst -Filter *.png).Count
$mb = [math]::Round(((Get-ChildItem $dst -Filter *.png | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "[arona] 抠像完成：$n 帧 / $mb MB → $dst"
if ($n -lt 100) { Write-Warning "[arona] 帧数异常偏少，检查源视频路径与 chromakey 参数" }

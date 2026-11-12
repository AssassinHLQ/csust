# 开场 PV 图 AI 超分（Real-ESRGAN 4× → 降采样到高 1440）
#
# 背景：`assets/cg/pv/` 里的实机截图本身很软（视频截帧），直接铺满 1600×900
# 放大后会「糊」。这个脚本用 Real-ESRGAN ncnn 版做 4× 超分，再用 ffmpeg
# Lanczos 降采样到高 1440（显示时约 1.6× 超采样），输出到 `assets/cg/pv_hd/`。
# `scripts/title_intro.gd` 会自动优先用同名的 HD 版，缺哪张就退回原图。
#
# 用法（Windows PowerShell，不要用 cmd）：
#   powershell -File _tools/upscale_pv_images.ps1
#   powershell -File _tools/upscale_pv_images.ps1 -Height 1800 -Force
#
# 依赖（都不入仓库）：
#   · Real-ESRGAN ncnn 便携版：https://github.com/xinntao/Real-ESRGAN/releases
#     解压到 `GODOT/_tools/realesrgan/`（与 `_arisu_learn` 平级），或用 -Exe 指定；
#   · ffmpeg 在 PATH 里，或用 -Ffmpeg 指定。
#
# ⚠️ 换图之后要重新跑一次；没重跑也不会错，只是那张退回原图（软一点）。

param(
    [int]$Height = 1440,
    [string]$Exe = "",
    [string]$Ffmpeg = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$src = Join-Path $repo "assets\cg\pv"
$out = Join-Path $repo "assets\cg\pv_hd"
$tmp = Join-Path $repo "_log\pv_upscale"

if (-not (Test-Path $src)) { throw "找不到 PV 原图目录：$src" }
if (-not $Exe) {
    $candidates = @(
        (Join-Path $repo "..\_tools\realesrgan\realesrgan-ncnn-vulkan.exe"),
        (Join-Path $repo "_tools\realesrgan\realesrgan-ncnn-vulkan.exe")
    )
    $Exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Exe -or -not (Test-Path $Exe)) {
    throw "找不到 realesrgan-ncnn-vulkan.exe，请用 -Exe 指定（见文件头说明）"
}
if (-not $Ffmpeg) {
    $cmd = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "ffmpeg 不在 PATH 里，请用 -Ffmpeg 指定" }
    $Ffmpeg = $cmd.Source
}

New-Item -ItemType Directory -Force -Path $out, $tmp | Out-Null

$files = Get-ChildItem $src -File |
    Where-Object { $_.Extension -in ".jpg", ".jpeg", ".png", ".webp" } |
    Sort-Object Name
if ($files.Count -eq 0) { throw "$src 里没有图片" }

Write-Host ("Real-ESRGAN：{0}" -f $Exe)
Write-Host ("ffmpeg     ：{0}" -f $Ffmpeg)
Write-Host ("目标高度   ：{0}px，共 {1} 张" -f $Height, $files.Count)

foreach ($f in $files) {
    $base = $f.BaseName
    $png = Join-Path $tmp ("$base.png")
    $final = Join-Path $out ("$base.jpg")
    if ($Force -or -not (Test-Path $png)) {
        Write-Host ("[4×] {0}" -f $f.Name)
        & $Exe -i $f.FullName -o $png -s 4 -n realesrgan-x4plus -f png *> (Join-Path $tmp "$base.log")
        if (-not (Test-Path $png)) { Write-Warning "超分失败：$($f.Name)（看 $tmp\$base.log）"; continue }
    }
    & $Ffmpeg -y -loglevel error -i $png -vf "scale=-2:$($Height):flags=lanczos" -q:v 2 $final
    if (Test-Path $final) {
        $kb = [math]::Round((Get-Item $final).Length / 1KB)
        Write-Host ("[OK] {0} → {1}（{2} KB）" -f $f.Name, (Split-Path $final -Leaf), $kb)
    } else {
        Write-Warning "降采样失败：$($f.Name)"
    }
}

Write-Host "全部完成。`n⚠️ 新图要在 Godot 里导入一次："
Write-Host "   <godot> --headless --path . --import"
Write-Host "   或在编辑器里打开项目自动导入。"

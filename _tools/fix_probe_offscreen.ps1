<#
.SYNOPSIS
    给旧出图探针批量补上「不抢用户前台」的运行时保护。

.DESCRIPTION
    AGENTS.md 硬要求（2026-11-09）：跑测试不许抢用户前台。

    老探针大多没有这层保护，本脚本统一补齐。插入的三行在脚本运行时执行，
    因此不受 project.godot 里 window/size/mode=2（最大化）的干扰：

        DisplayServer.window_set_mode(WINDOW_MODE_WINDOWED)        取消最大化
        DisplayServer.window_set_flag(WINDOW_FLAG_NO_FOCUS, true)  禁止后续聚焦
        DisplayServer.window_set_position(Vector2i(-4000, -4000))  挪出屏幕

    只处理「要出图 + 非 headless + 无任何现有保护」的脚本。
    已有保护（OffWin / window_set_* / --headless）一律跳过，不改动。

    局限：窗口创建瞬间的那一次聚焦无法从 Godot 内部撤销，
    需要配合 _tools/run_shot.ps1 的外部焦点归还。

.PARAMETER ScriptDir
    脚本目录，默认 _arisu_learn/scripts。

.PARAMETER DryRun
    只报告将修改哪些文件，不写入磁盘。

.EXAMPLE
    pwsh -File fix_probe_offscreen.ps1 -DryRun
    pwsh -File fix_probe_offscreen.ps1
#>
param(
    [string]$ScriptDir = 'C:\Users\WY157\Desktop\GODOT\_arisu_learn\scripts',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$guardLines = @(
    '# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕',
    'DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)',
    'DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)',
    'DisplayServer.window_set_position(Vector2i(-4000, -4000))'
) | ForEach-Object { "`t$_" }

$initPattern = 'func _initialize\(\)\s*->\s*void:\s*\r?\n'

$changed = 0
$skipped = 0
$noInit  = New-Object System.Collections.ArrayList

Get-ChildItem -Path $ScriptDir -Filter '*.gd' |
    Where-Object { $_.Name -match '^_' } |
    Sort-Object Name |
    ForEach-Object {
        $path = $_.FullName
        $bytes = [IO.File]::ReadAllBytes($path)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $enc = New-Object System.Text.UTF8Encoding($hasBom)
        $text = [IO.File]::ReadAllText($path)

        # 已有保护 / 不需要保护 —— 一律不动
        if ($text -match '--headless') { $skipped++; return }
        if ($text -match 'offscreen_window|OffWin') { $skipped++; return }
        if ($text -match 'window_set_position|WINDOW_FLAG_NO_FOCUS|window_set_flag|window_set_mode') { $skipped++; return }
        if ($text -notmatch 'get_texture|get_image') { $skipped++; return }

        if ($text -notmatch $initPattern) {
            [void]$noInit.Add($_.Name)
            return
        }

        if ($DryRun) {
            Write-Output ("  [将修改] " + $_.Name)
            $changed++
            return
        }

        $nl = if ($text -match "`r`n") { "`r`n" } else { "`n" }
        $guard = ($guardLines -join $nl) + $nl
        $rx = New-Object System.Text.RegularExpressions.Regex($initPattern)
        $new = $rx.Replace($text, ('$1' + $guard), 1)

        [IO.File]::WriteAllText($path, $new, $enc)
        $changed++
    }

Write-Output ''
if ($DryRun) { Write-Output ("[干跑] 将修改 {0} 个，跳过 {1} 个" -f $changed, $skipped) }
else         { Write-Output ("[完成] 已修改 {0} 个，跳过 {1} 个" -f $changed, $skipped) }

if ($noInit.Count -gt 0) {
    Write-Output ''
    Write-Output ("没有 _initialize() 需要手工处理的 {0} 个：" -f $noInit.Count)
    $noInit | ForEach-Object { Write-Output ("  " + $_) }
}

<#
.SYNOPSIS
    记录 / 归还 Windows 前台窗口。配合 run_shot.sh，让出图探针不占用用户前台。

.DESCRIPTION
    背景（2026-11-09 实测）：
      Godot 创建窗口时会抢一次系统前台，而运行时 API 撤不回来：
        - 命令行 --position / --windowed        被 project.godot 的 mode=2 顶掉
        - override.cfg                            --path 模式下 Godot 根本不读
        - window_set_flag(WINDOW_FLAG_NO_FOCUS)   设置得太晚，只能阻止"以后"的聚焦
        - --feature / --no-focus                  Godot 4.7 没有这些参数

      所以唯一的办法是**从进程外把焦点还回去**。本脚本做这件事。

    用法（由 run_shot.sh 自动调用，一般不用手动跑）：
        powershell -ExecutionPolicy Bypass -File _focus.ps1 save      # 记下当前前台
        powershell -ExecutionPolicy Bypass -File _focus.ps1 restore   # 把焦点还回去

    退出码：
        save     0 = 已记录
        restore  0 = 归还成功
                 1 = 没有记录文件
                 2 = 目标窗口已不存在（用户自己切走了，正常）
                 3 = SetForegroundWindow 被系统拒绝（前台锁定）

.PARAMETER Action
    save 记录当前前台窗口；restore 归还给它。
#>
param(
    [ValidateSet('save', 'restore')]
    [string]$Action = 'restore'
)

$ErrorActionPreference = 'Stop'
$stateFile = Join-Path $env:TEMP '_dsh_prev_foreground.txt'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FocusGuard {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
}
"@

if ($Action -eq 'save') {
    $h = [FocusGuard]::GetForegroundWindow()
    [string]$h.ToInt64() | Set-Content -Path $stateFile -Encoding ascii
    Write-Output $h.ToInt64()
    exit 0
}

if (-not (Test-Path $stateFile)) { exit 1 }
$raw = (Get-Content $stateFile -Raw).Trim()
if (-not $raw) { exit 1 }

$target = [IntPtr][int64]$raw
if (-not [FocusGuard]::IsWindow($target)) { exit 2 }

# 归还一次。AttachThreadInput 技巧：先把自己附加到"当前前台"的线程输入队列，
# Windows 才允许我们改前台（否则会被前台锁定策略拒绝）。
# 注意 GetForegroundWindow() 可能返回 0（焦点正在切换的瞬间），必须判空。
function Invoke-Restore([IntPtr]$h) {
    $cur = [FocusGuard]::GetForegroundWindow()
    if ($cur -ne [IntPtr]::Zero -and $cur -eq $h) { return $true }

    $fgThread = 0
    if ($cur -ne [IntPtr]::Zero) {
        $p = [uint32]0
        try { $fgThread = [FocusGuard]::GetWindowThreadProcessId($cur, [ref]$p) } catch { $fgThread = 0 }
    }
    $myThread = [FocusGuard]::GetCurrentThreadId()

    if ($fgThread -ne 0 -and $fgThread -ne $myThread) {
        [void][FocusGuard]::AttachThreadInput($myThread, $fgThread, $true)
        [void][FocusGuard]::BringWindowToTop($h)
        $ok = [FocusGuard]::SetForegroundWindow($h)
        [void][FocusGuard]::AttachThreadInput($myThread, $fgThread, $false)
        if ($ok) { return $true }
    }

    # 退路：附加不成功（前台为 0 或同线程）时直接试一次
    [void][FocusGuard]::BringWindowToTop($h)
    return [FocusGuard]::SetForegroundWindow($h)
}

$ok = $false
for ($i = 0; $i -lt 6 -and -not $ok; $i++) {
    $ok = Invoke-Restore $target
    if (-not $ok) { Start-Sleep -Milliseconds 120 }
}

if ($ok) { exit 0 } else { exit 3 }

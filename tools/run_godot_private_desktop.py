"""Run a rendered Godot probe on an isolated Windows desktop without switching to it."""
import argparse
import ctypes as ct
from ctypes import wintypes as wt
import json
import os
from pathlib import Path
import subprocess
import time
import uuid


class StartupInfo(ct.Structure):
    _fields_ = [('cb', wt.DWORD), ('lpReserved', wt.LPWSTR),
                ('lpDesktop', wt.LPWSTR), ('lpTitle', wt.LPWSTR),
                ('dwX', wt.DWORD), ('dwY', wt.DWORD),
                ('dwXSize', wt.DWORD), ('dwYSize', wt.DWORD),
                ('dwXCountChars', wt.DWORD), ('dwYCountChars', wt.DWORD),
                ('dwFillAttribute', wt.DWORD), ('dwFlags', wt.DWORD),
                ('wShowWindow', wt.WORD), ('cbReserved2', wt.WORD),
                ('lpReserved2', ct.POINTER(ct.c_byte)),
                ('hStdInput', wt.HANDLE), ('hStdOutput', wt.HANDLE),
                ('hStdError', wt.HANDLE)]


class ProcessInfo(ct.Structure):
    _fields_ = [('hProcess', wt.HANDLE), ('hThread', wt.HANDLE),
                ('dwProcessId', wt.DWORD), ('dwThreadId', wt.DWORD)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--project', required=True, type=Path)
    parser.add_argument('--script', required=True)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--timeout', type=int, default=360)
    parser.add_argument('extra', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    user32 = ct.WinDLL('user32', use_last_error=True)
    kernel32 = ct.WinDLL('kernel32', use_last_error=True)
    user32.CreateDesktopW.argtypes = [wt.LPCWSTR, wt.LPCWSTR, ct.c_void_p, wt.DWORD, wt.DWORD, ct.c_void_p]
    user32.CreateDesktopW.restype = wt.HANDLE
    user32.CloseDesktop.argtypes = [wt.HANDLE]
    user32.GetForegroundWindow.restype = wt.HWND
    kernel32.CreateProcessW.argtypes = [wt.LPCWSTR, wt.LPWSTR, ct.c_void_p, ct.c_void_p, wt.BOOL, wt.DWORD, ct.c_void_p, wt.LPCWSTR, ct.POINTER(StartupInfo), ct.POINTER(ProcessInfo)]
    kernel32.WaitForSingleObject.argtypes = [wt.HANDLE, wt.DWORD]
    kernel32.GetExitCodeProcess.argtypes = [wt.HANDLE, ct.POINTER(wt.DWORD)]
    kernel32.TerminateProcess.argtypes = [wt.HANDLE, wt.UINT]
    kernel32.CloseHandle.argtypes = [wt.HANDLE]
    args.out.mkdir(parents=True, exist_ok=True)
    out = args.out.resolve()
    # Keep player saves separate. The existing read-only runtime cache may be
    # reused; the GDGS probe does not write GGS streaming-window cache files.
    os.environ['APPDATA'] = str(out / 'userdata/Roaming')
    os.environ['LOCALAPPDATA'] = str(out / 'userdata/Local')
    Path(os.environ['APPDATA']).mkdir(parents=True, exist_ok=True)
    Path(os.environ['LOCALAPPDATA']).mkdir(parents=True, exist_ok=True)
    name = 'CodexGodotProbe_' + uuid.uuid4().hex[:12]
    desktop = user32.CreateDesktopW(name, None, None, 0, 0x01ff, None)
    if not desktop:
        raise ct.WinError(ct.get_last_error())
    info = StartupInfo()
    info.cb = ct.sizeof(info)
    info.lpDesktop = name
    info.dwFlags = 1  # STARTF_USESHOWWINDOW
    info.wShowWindow = 0  # SW_HIDE; no switching of the user's input desktop
    process = ProcessInfo()
    before = int(user32.GetForegroundWindow() or 0)
    extra = args.extra[1:] if args.extra[:1] == ['--'] else args.extra
    command = [str(args.godot.resolve()), '--path', str(args.project.resolve()),
               '--audio-driver', 'Dummy', '--render-thread', 'safe',
               '--log-file', str(out / 'engine.log'), '--script', args.script,
               '--', '--no-capture', '--story=off', *extra]
    started = time.monotonic()
    try:
        if not kernel32.CreateProcessW(str(args.godot.resolve()),
                ct.create_unicode_buffer(subprocess.list2cmdline(command)),
                None, None, False, 0x08000000, None,
                str(args.project.resolve()), ct.byref(info), ct.byref(process)):
            raise ct.WinError(ct.get_last_error())
        print(json.dumps({'pid': process.dwProcessId, 'desktop': name,
                          'input_desktop_switched': False,
                          'foreground_before': before}), flush=True)
        status = kernel32.WaitForSingleObject(process.hProcess, args.timeout * 1000)
        if status == 0x102:
            kernel32.TerminateProcess(process.hProcess, 124)
            kernel32.WaitForSingleObject(process.hProcess, 5000)
        code = wt.DWORD()
        kernel32.GetExitCodeProcess(process.hProcess, ct.byref(code))
        report = {'pid': process.dwProcessId, 'desktop': name, 'exit_code': code.value,
                  'seconds': round(time.monotonic() - started, 3),
                  'foreground_before': before,
                  'foreground_after': int(user32.GetForegroundWindow() or 0),
                  'input_desktop_switched': False, 'command': command}
        (out / 'launcher.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report), flush=True)
        return code.value
    finally:
        if process.hThread:
            kernel32.CloseHandle(process.hThread)
        if process.hProcess:
            kernel32.CloseHandle(process.hProcess)
        user32.CloseDesktop(desktop)


if __name__ == '__main__':
    raise SystemExit(main())

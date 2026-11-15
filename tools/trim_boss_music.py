"""Trim the boss theme and refresh its Godot import cache without a window."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--ffmpeg', required=True, type=Path)
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.project.resolve()
    stage = root / '_tools/_tmp/boss_audio_refresh'
    target = stage / 'assets/music/doom_theme.ogg'
    target.parent.mkdir(parents=True, exist_ok=True)
    flags = {'creationflags': subprocess.CREATE_NO_WINDOW}
    subprocess.run([str(args.ffmpeg), '-nostdin', '-y', '-v', 'error', '-i',
                    str(args.source.resolve()), '-t', '112.5', '-c:a', 'libvorbis',
                    '-q:a', '5', str(target)], check=True, **flags)
    config = root / 'assets/music/doom_theme.ogg.import'
    shutil.copy2(config, target.with_suffix('.ogg.import'))
    (stage / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="Boss Audio Import"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    result = subprocess.run([str(args.godot), '--headless', '--audio-driver', 'Dummy',
                             '--path', str(stage), '--editor', '--import'],
                            capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90, **flags)
    (stage / 'import.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f'Import exited {result.returncode}; see {stage / "import.log"}')
    cache = re.search(r'^path="res://([^\"]+)"', config.read_text(), re.M).group(1)
    if not (stage / cache).is_file():
        raise RuntimeError('Godot import did not produce the audio stream')
    shutil.copy2(target, root / 'assets/music/doom_theme.ogg')
    for path in [(stage / cache), (stage / cache).with_suffix('.md5')]:
        shutil.copy2(path, root / path.relative_to(stage))
    print('Boss theme trimmed to 112.5 seconds and import cache refreshed.')

if __name__ == '__main__':
    main()

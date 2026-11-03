"""读 GLB 头部的 JSON chunk，把 asset.extras / generator / copyright 打出来。

用来核实「这个模型自己声明的许可」，不靠 README 的转述。

    python tools/glb_meta.py models/ram/random_access_memory_ram_ddr4.glb
"""
from __future__ import annotations

import json
import struct
import sys


def read_glb_json(path: str) -> dict:
    with open(path, "rb") as f:
        magic, version, length = struct.unpack("<III", f.read(12))
        if magic != 0x46546C67:  # 'glTF'
            raise SystemExit(f"不是 GLB：{path}")
        chunk_len, chunk_type = struct.unpack("<II", f.read(8))
        if chunk_type != 0x4E4F534A:  # 'JSON'
            raise SystemExit("第一个 chunk 不是 JSON")
        raw = f.read(chunk_len)
    return json.loads(raw.decode("utf-8"))


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    for path in sys.argv[1:]:
        print(f"===== {path} =====")
        try:
            g = read_glb_json(path)
        except (OSError, struct.error, json.JSONDecodeError) as e:
            print(f"  读取失败：{e}")
            continue
        a = g.get("asset", {})
        print(f"  generator : {a.get('generator', '<无>')}")
        print(f"  version   : {a.get('version', '<无>')}")
        for k in ("copyright", "extras"):
            if k in a:
                print(f"  {k:<10}: {json.dumps(a[k], ensure_ascii=False)}")
        if "extras" not in a and "copyright" not in a:
            print("  !! asset 里没有 copyright / extras，模型本身没声明许可")
        print(f"  网格 {len(g.get('meshes', []))} 个 / 材质 {len(g.get('materials', []))} 个 / 贴图 {len(g.get('images', []))} 张")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())

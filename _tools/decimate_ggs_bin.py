"""把 GGS 的 bin 按固定步长抽稀（每 N 个高斯点留 1 个），用于验证
「降采样全量常驻」能不能替代「10×10 分块窗口」。

GGS bin 格式：每个高斯点 240 字节定长记录（见 scripts/campus_ggs.gd 里
`count = file_length / 240` 的算法）。

用法：
    python _tools/decimate_ggs_bin.py <in.bin> <out.bin> <stride>
"""

import sys

REC = 240
CHUNK = REC * 50000          # 每次读 12 MB


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    src, dst, stride = sys.argv[1], sys.argv[2], int(sys.argv[3])
    if stride < 1:
        print("stride 必须 ≥ 1")
        return 2

    total_bytes = 0
    kept = 0
    buf = bytearray()
    with open(src, "rb") as fi, open(dst, "wb") as fo:
        while True:
            block = fi.read(CHUNK)
            if not block:
                break
            n = len(block) // REC
            buf.clear()
            for i in range(n):
                if (total_bytes // REC + i) % stride == 0:
                    buf += block[i * REC:(i + 1) * REC]
                    kept += 1
            fo.write(buf)
            total_bytes += len(block)

    pts = total_bytes // REC
    print("源 %d 点（%.1f MB）→ 留 %d 点（每 %d 个留 1）"
          % (pts, total_bytes / 1048576.0, kept, stride))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

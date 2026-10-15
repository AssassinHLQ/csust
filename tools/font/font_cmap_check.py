"""不依赖 fontTools，直接解析 TTF/OTF 的 cmap 表，统计覆盖了哪些码位。

这是底层工具（`font_needed.py` 会 import 它）。单独跑可以看**按 Unicode 区块**
的覆盖率统计 —— 判断一套字体是「只覆盖 GB2312 那 6763 字」还是「真的全」时很有用。

用法:
    python font_cmap_check.py <字体.ttf> [<字体2.ttf> ...]

为什么要自己解析: fontTools 属于第三方库，这台机器上装不了（没有网络），
而「字体到底有没有汉字」必须实测 —— 文件 7 MB 不等于有汉字，也可能是
拉丁文的很多字重。

输出里 `CJK 汉字（URO）` 那一行的比例是**最重要的一个数**：
    91.5%（19214/20992）≈ Fusion Pixel，够写任何中文
    32.7%（6864/20992） ≈ GB2312 级别，正常写作够用，生僻字会缺
"""
import struct
import sys


def read_tables(buf):
    if len(buf) < 12:
        raise ValueError("文件太短")
    tag = buf[0:4]
    if tag == b"ttcf":
        # TrueType Collection：取第一个 face 的表目录
        num_fonts, = struct.unpack(">I", buf[8:12])
        off, = struct.unpack(">I", buf[12:16])
        return read_tables_at(buf, off)
    if tag not in (b"\x00\x01\x00\x00", b"true", b"OTTO"):
        raise ValueError("不是 TTF/OTF: %r" % tag)
    return read_tables_at(buf, 0)


def read_tables_at(buf, base):
    num_tables, = struct.unpack(">H", buf[base + 4:base + 6])
    tables = {}
    p = base + 12
    for _ in range(num_tables):
        name = buf[p:p + 4].decode("latin-1")
        off, length = struct.unpack(">II", buf[p + 8:p + 16])
        tables[name] = (off, length)
        p += 16
    return tables


def parse_cmap(buf, off):
    """返回（覆盖的码位集合, 子表清单）。合并该 cmap 表里所有子表。"""
    covered = set()
    version, num_tables = struct.unpack(">HH", buf[off:off + 4])
    subtables = []
    for i in range(num_tables):
        p = off + 4 + i * 8
        plat, enc, sub_off = struct.unpack(">HHI", buf[p:p + 8])
        subtables.append((plat, enc, off + sub_off))
    for plat, enc, s in subtables:
        fmt, = struct.unpack(">H", buf[s:s + 2])
        try:
            if fmt == 4:
                covered |= _cmap4(buf, s)
            elif fmt == 12:
                covered |= _cmap12(buf, s)
            elif fmt == 6:
                covered |= _cmap6(buf, s)
            # fmt 0 / 2 / 13 / 14 对 CJK 不重要，跳过
        except Exception as exc:  # 子表坏了不该让整件事失败
            print("    [warn] 子表 platform=%d enc=%d fmt=%d 解析失败: %s"
                  % (plat, enc, fmt, exc))
    return covered, subtables


def _gid_from_cmap4(buf, s, seg, c):
    seg_count = seg // 2
    ends = struct.unpack(">%dH" % seg_count, buf[s + 14:s + 14 + seg])
    base = s + 14 + seg + 2
    starts = struct.unpack(">%dH" % seg_count, buf[base:base + seg])
    deltas = struct.unpack(">%dh" % seg_count, buf[base + seg:base + 2 * seg])
    range_off_pos = base + 2 * seg
    range_offs = struct.unpack(">%dH" % seg_count,
                               buf[range_off_pos:range_off_pos + seg])
    for i in range(seg_count):
        if starts[i] <= c <= ends[i]:
            if range_offs[i] == 0:
                return (c + deltas[i]) & 0xFFFF
            addr = range_off_pos + i * 2 + range_offs[i] + (c - starts[i]) * 2
            if addr + 2 > len(buf):
                return 0
            gid, = struct.unpack(">H", buf[addr:addr + 2])
            if gid == 0:
                return 0
            return (gid + deltas[i]) & 0xFFFF
    return 0


def _cmap4(buf, s):
    length, = struct.unpack(">H", buf[s + 2:s + 4])
    seg, = struct.unpack(">H", buf[s + 6:s + 8])
    out = set()
    seg_count = seg // 2
    ends = struct.unpack(">%dH" % seg_count, buf[s + 14:s + 14 + seg])
    base = s + 14 + seg + 2
    starts = struct.unpack(">%dH" % seg_count, buf[base:base + seg])
    for i in range(seg_count):
        if starts[i] > ends[i]:
            continue
        if ends[i] - starts[i] > 0x4000:      # 巨段，逐点太慢，跳过
            continue
        for c in range(starts[i], ends[i] + 1):
            if c == 0xFFFF:
                continue
            if _gid_from_cmap4(buf, s, seg, c) != 0:
                out.add(c)
    return out


def _cmap6(buf, s):
    first, count = struct.unpack(">HH", buf[s + 6:s + 10])
    gids = struct.unpack(">%dH" % count, buf[s + 10:s + 10 + count * 2])
    return {first + i for i, g in enumerate(gids) if g != 0}


def _cmap12(buf, s):
    n_groups, = struct.unpack(">I", buf[s + 12:s + 16])
    out = set()
    p = s + 16
    for _ in range(n_groups):
        start, end, gid = struct.unpack(">III", buf[p:p + 12])
        p += 12
        if gid == 0:
            continue
        if end - start > 0x20000:
            continue
        out.update(range(start, end + 1))
    return out


SAMPLES = {
    "ASCII": "Arisu 2067",
    "中文（游戏里会出现的）": "长沙理工剧情系统优香霸王龙飞猪同伴对话继续",
    "中文标点": "，。！？：；、「」（）…—·",
    "日文假名": "ありすアリス",
    "韩文": "아리수",
    "省略号/破折号": "……——",
}

BLOCKS = [
    ("基本拉丁", 0x0020, 0x007E),
    ("CJK 符号标点", 0x3000, 0x303F),
    ("平假名", 0x3040, 0x309F),
    ("片假名", 0x30A0, 0x30FF),
    ("CJK 汉字（URO）", 0x4E00, 0x9FFF),
    ("CJK 扩展A", 0x3400, 0x4DBF),
    ("全角字符", 0xFF00, 0xFFEF),
    ("谚文音节", 0xAC00, 0xD7A3),
    ("CJK 兼容汉字", 0xF900, 0xFAFF),
]


def report(path):
    with open(path, "rb") as fh:
        buf = fh.read()
    print("=" * 68)
    print("文件: %s" % path)
    print("大小: %.2f MB" % (len(buf) / 1048576.0))
    tables = read_tables(buf)
    print("表: %s" % ", ".join(sorted(tables)))
    if "cmap" not in tables:
        print("!! 没有 cmap 表")
        return
    off, _length = tables["cmap"]
    covered, subtables = parse_cmap(buf, off)
    print("子表: %s" % ", ".join("(%d,%d,fmt%d)" % (p, e, struct.unpack(
        ">H", buf[s:s + 2])[0]) for p, e, s in subtables))
    print("cmap 合计覆盖码位: %d" % len(covered))

    print("-" * 68)
    print("%-20s %10s %10s %8s" % ("区块", "覆盖", "该区总数", "比例"))
    for name, lo, hi in BLOCKS:
        total = hi - lo + 1
        got = sum(1 for c in range(lo, hi + 1) if c in covered)
        print("%-20s %10d %10d %7.1f%%" % (name, got, total, got * 100.0 / total))

    print("-" * 68)
    for label, text in SAMPLES.items():
        chars = sorted({ord(ch) for ch in text if ch.strip()})
        missing = [c for c in chars if c not in covered]
        mark = "OK  " if not missing else "缺字"
        detail = ""
        if missing:
            detail = "  缺: " + "".join(chr(c) for c in missing)
        print("[%s] %-22s %d 个不同字符%s" % (mark, label, len(chars), detail))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    for arg in sys.argv[1:]:
        try:
            report(arg)
        except Exception as exc:
            print("文件 %s 解析失败: %s" % (arg, exc))

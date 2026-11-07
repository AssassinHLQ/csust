import io
import os

PATH = r"C:\Users\WY157\Downloads\现代网咖_电竞酒店套房_宿舍上下铺_爱给网_aigei_com\06\h06_m210903.max"
OUT = r"C:\Users\WY157\Desktop\GODOT\_arisu_learn\_log\max_author_scan.txt"

MARKERS = [
    "作者".encode("utf-8"),
    "作者".encode("utf-16-le"),
    "设计".encode("utf-16-le"),
    "制作".encode("utf-16-le"),
    "版权".encode("utf-16-le"),
    "版权".encode("utf-8"),
    b"Author",
    b"Title",
    b"Subject",
    b"Comment",
    b"Designer",
    b"FileInfo",
    b"DocumentInformation",
    b"SummaryInfo",
]

CHUNK = 8 * 1024 * 1024
OVERLAP = 8192

hits = []
with open(PATH, "rb") as fh:
    base = 0
    prev_tail = b""
    while True:
        buf = fh.read(CHUNK)
        if not buf:
            break
        data = prev_tail + buf
        off_base = base - len(prev_tail)
        for m in MARKERS:
            start = 0
            while True:
                i = data.find(m, start)
                if i < 0:
                    break
                if len(hits) < 400:
                    hits.append((off_base + i, m, bytes(data[max(0, i - 200):min(len(data), i + 400)])))
                start = i + 1
        prev_tail = data[-OVERLAP:] if len(data) >= OVERLAP else data
        base += len(buf)


def show(raw: bytes) -> str:
    parts = []
    u = raw.decode("utf-16-le", errors="ignore")
    u = "".join(ch if (ch.isprintable() or ch in "\r\n\t") else "·" for ch in u)
    if any("\u4e00" <= ch <= "\u9fff" for ch in u) or sum(ch.isalnum() for ch in u) >= 6:
        parts.append("u16: " + u.strip())
    for enc in ("utf-8", "gb18030"):
        try:
            a = raw.decode(enc, errors="ignore")
        except Exception:
            continue
        a = "".join(ch if (ch.isprintable() or ch in "\r\n\t") else "·" for ch in a)
        if sum(ch.isalnum() for ch in a) >= 6:
            parts.append(enc + ": " + a.strip())
            break
    return "\n      ".join(parts) if parts else "（无可读文本）"


lines = []
lines.append("扫描文件：%s" % PATH)
lines.append("文件大小：%d 字节" % os.path.getsize(PATH))
lines.append("命中标记：%d 处" % len(hits))
lines.append("")
for off, marker, ctx in hits:
    lines.append("--- offset=0x%x  marker=%r" % (off, marker))
    lines.append("      " + show(ctx))
    lines.append("")

io.open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("wrote", OUT, "hits:", len(hits))

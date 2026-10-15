"""换 UI 字体之前，把「游戏里**实际会出现**的每一个字」对着字体的 cmap 查一遍。

只查「一句话样本」不够 —— HUD、设置界面、同伴名字、操作说明里散着很多字，
缺一个就是一个豆腐块，而且往往在很偏的角落（比如「灵敏度」的「敏」）。

用法：
    python font_needed.py <字体路径> [<字体路径2> ...]

「剧情」那一组的字**直接从工程的 story/*.txt 里读**（自己往上找 story 目录），
所以你改了剧本之后再跑，查的就是你真正写下的那些字。找不到 story 目录时
退回内置的那段样本（开场剧情）。
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import font_cmap_check as fc

# 剧本读不到时的内置样本
FALLBACK_STORY = (
    "2067 年，长沙。云层压得很低，太阳只剩一条橙色的缝。"
    "记忆平台悬在半空，脚下的校园陷进两百米下的阴影里。"
    "喂——这边这边！你又在对着下面那堆废墟发呆。"
    "身后传来一阵急促的脚步声。抱歉，来晚了。"
    "画室 609 的门锁换过了，我绕了一圈才上来。"
    "换过了？谁换的。不知道。但门缝里有光。"
)

# 按来源分组，哪一组缺字就能直接定位到哪个界面
NEEDED = {
    "同伴与 Boss 名字": "未花优香诺亚小桃小绿柚子凯伊霸王龙飞猪",
    "HUD": "HP血量弹药换弹继续空格回车左键鼠标瞄准 0123456789/ ",
    "设置界面（game_settings.LABELS）": "鼠标灵敏度视野主音量同伴开火攻击画质极致高中低省电恢复默认",
    "设置界面（settings_menu.HELP_TEXT）": (
        "WASD 移动 Shift 跑动 Ctrl 蹲行 空格 跳跃 右键 瞄准 左键 开火 "
        "R 换弹 滚轮 远近 名同伴会帮你打未花优香诺亚小桃小绿柚子凯伊 "
        "屋内是画室 609 平台下是校园"
    ),
    "剧情播放提示（dialogue_box）": "空格回车左键继续",
}


def find_story_root():
    """从本文件往上找带 `story/` 的目录（就是工程根）。找不到返回空串。"""
    d = os.path.dirname(os.path.abspath(__file__))
    for _ in range(5):
        if os.path.isdir(os.path.join(d, "story")):
            return os.path.join(d, "story")
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return ""


def displayed_chars(text):
    """按 `scripts/story_script.gd` 的语法，把**真正会显示出来的字**挑出来。

    ⚠️ 直接数整个文件会把注释行和 `@指令` 的语法字符也算进去 —— 那些永远不会
    出现在屏幕上，算进去只会让结论虚高（第一版就多算了 200 多个字，
    把 `#`、`@`、`═`、「指令」「注释」这些全算成了「游戏里会出现的字」）。
    """
    out = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("@"):
            continue
        if line.startswith("*"):                 # 无名字旁白：星号后面全是正文
            out.append(line[1:].strip())
            continue
        cuts = [i for i in (line.find(":"), line.find("：")) if i >= 0]
        if not cuts:
            continue
        cut = min(cuts)                          # 只在**第一个**冒号处切，和解析器一致
        out.append(line[:cut].strip())           # 说话人（名字牌上会显示）
        out.append(line[cut + 1:].strip())       # 正文
    return "".join(out)


def story_group():
    """（来源说明, 会显示的字）—— 优先用工程里真实的剧本文件。"""
    d = find_story_root()
    if not d:
        return "剧情样本（内置：找不到 story/ 目录）", FALLBACK_STORY
    files = sorted(glob.glob(os.path.join(d, "*.txt")))
    if not files:
        return "剧情样本（内置：story/ 里没有 .txt）", FALLBACK_STORY
    text = ""
    for p in files:
        with open(p, encoding="utf-8", errors="replace") as fh:
            text += fh.read()
    names = ", ".join(os.path.basename(p) for p in files)
    return "剧情（story/：%s）" % names, displayed_chars(text)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    label, story_text = story_group()
    groups = [(label, story_text)] + list(NEEDED.items())
    all_chars = sorted({c for _, s in groups for c in s if c.strip()})
    print("游戏里会出现的不同字符合计 %d 个" % len(all_chars))
    print("（剧情那一组来自 %s）\n" % label)

    any_missing = False
    for path in sys.argv[1:]:
        with open(path, "rb") as fh:
            buf = fh.read()
        covered, _ = fc.parse_cmap(buf, fc.read_tables(buf)["cmap"][0])
        print("=" * 72)
        print("%s（%.2f MB，cmap 共 %d 个码位）"
              % (os.path.basename(path), len(buf) / 1048576.0, len(covered)))
        total_missing = 0
        for group, text in groups:
            chars = sorted({c for c in text if c.strip()})
            miss = [c for c in chars if ord(c) not in covered]
            total_missing += len(miss)
            mark = "OK  " if not miss else "缺字"
            print("  [%s] %-40s %3d 字%s"
                  % (mark, group, len(chars),
                     "" if not miss else "   缺: " + "".join(miss)))
        if total_missing == 0:
            print("  → **可以整套换**（游戏里会出现的字一个不缺）")
        else:
            any_missing = True
            print("  → **不能整套换**：共缺 %d 个字" % total_missing)
    # 退出码：只要有一个字体缺字就是 1（方便丢进脚本里当门禁）
    return 1 if any_missing else 0


if __name__ == "__main__":
    sys.exit(main())

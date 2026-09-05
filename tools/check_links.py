#!/usr/bin/env python3
"""check-links.py — markdown link/image integrity for the public docs tree.

Scans every tracked .md file and verifies that relative link targets
(links, images) exist in the repository. Skips: absolute URLs (http/https/mailto),
anchors (#section — GitHub resolves them), and README.tr.md (its anchors target
README.md sections, validated by the same tool separately for files only).

Exit 0 = every relative target resolves; exit 1 = list of broken links.
This is documentation-evidence automation: doc rot is treated like test rot.
"""
import re
import subprocess
import sys
from pathlib import Path

LINK_RE = re.compile(r"\[([^\]]*)\]\(([^)]+)\)")
IMG_RE = re.compile(r'<(?:img|source)[^>]+src="([^"]+)"')


def tracked_files() -> list[str]:
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True)
    return [l for l in out.stdout.splitlines() if l.endswith(".md")]


def main() -> int:
    broken: list[str] = []
    checked = 0
    for md in tracked_files():
        base = Path(md).parent
        text = Path(md).read_text(encoding="utf-8")
        targets = [m.group(2) for m in LINK_RE.finditer(text)] + \
                  [m.group(1) for m in IMG_RE.finditer(text)]
        for t in targets:
            t = t.split("#")[0].strip()          # drop anchors for file-existence check
            if not t or t.startswith(("http://", "https://", "mailto:", "data:")):
                continue
            checked += 1
            if not (base / t).exists():
                broken.append(f"{md}: {t}")

    print(f"check-links: {checked} relative targets checked, {len(broken)} broken")
    for b in broken:
        print("  BROKEN:", b)
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())

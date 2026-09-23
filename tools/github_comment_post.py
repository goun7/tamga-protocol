#!/usr/bin/env python3
"""GitHub-yorum-gönderici — fail-closed-ek-çözümleme ( AT-179-sonrası-ders).

2026-09-20'de-iki-yorum-dosya-içeriği-YERİNE-literal-'@/tmp/x402-comment.md'-
yolu-olarak-gönderildi ( stillmarcus24-uyarısı, 3-gün-sonra). Kök-neden: aracın
'@yol'-sözdizimini-ÇÖZMEDEN-ham-metni-body'ye-yazması — fail-OPEN-yol-sızıntısı.

Bu-aracın-kuralı:
  * '@/tmp/x.md' → dosyayı-OKU, içeriği-gönder; dosya-yoksa-REDDET ( asla-yol-gönderme)
  * '@/tmp/x.md' geçersizse → yardım-bas, çık
  * stdin'den '-' → stdin'i-oku
  * iletişim-kanalı-yoksa ( GITHUB_TOKEN-yoksa) → KURU-ÇALIŞMA ( dry-run): içeriği
    bas, gönderme, çık-kodu-2 ( test-edilebilir, güvenli)
"""
from __future__ import annotations
import json
import os
import sys
import urllib.request
import urllib.error


def resolve_body(arg: str) -> str:
    """Bir girdi-argümanını-body'ye-çöz. '@yol' → dosya-içeriği; '-' → stdin;
    aksi → ham-metin. HATA-DURUMUNDA-YOL-ASLA-GERİ-DÖNDÜRÜLMEZ ( fail-closed)."""
    if arg == "-":
        return sys.stdin.read()
    if arg.startswith("@"):
        path = arg[1:]
        if not path:
            raise ValueError("boş-'@'-yolu")
        if not os.path.isfile(path):
            raise ValueError(f"ek-dosya-yok ( yol-ASLA-gönderilmez): {path}")
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    return arg


def post_comment(owner: str, repo: str, issue: int, body: str,
                 token: str | None = None) -> dict:
    """Bir-yorum-gönderir. Token-yoksa-REDDET ( dry-run-değil-güvenlik)."""
    if not token:
        raise PermissionError("GITHUB_TOKEN-yok — yorum-gönderilemez ( fail-closed)")
    url = f"https://api.github.com/repos/{owner}/{repo}/issues/{issue}/comments"
    data = json.dumps({"body": body}).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST", headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        out = json.loads(r.read().decode("utf-8"))
    return {"ok": True, "id": out.get("id"), "url": out.get("html_url"),
            "len": len(body)}


def main(argv: list) -> int:
    if len(argv) < 4:
        print(__doc__)
        return 1
    owner, repo, issue, body_arg = argv[0], argv[1], argv[2], argv[3]
    dry = "--dry-run" in argv
    try:
        body = resolve_body(body_arg)
    except ValueError as e:
        print(f"HATA ( fail-closed): {e}", file=sys.stderr)
        return 3
    if not body.strip():
        print("HATA ( fail-closed): body-boş", file=sys.stderr)
        return 4
    token = os.environ.get("GITHUB_TOKEN")
    if dry or not token:
        print(f"[DRY-RUN {'token-yok' if not token else 'bayrak'}] {owner}/{repo}#{issue}")
        print(f"body-uzunluğu: {len(body)}")
        print("---")
        print(body[:400] + ("…" if len(body) > 400 else ""))
        return 2 if not token else 0
    r = post_comment(owner, repo, int(issue), body, token)
    print(json.dumps(r, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

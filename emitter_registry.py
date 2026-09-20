#!/usr/bin/env python3
"""
Emitter-registry — Sester'ın-üçlü-kapsamının-2.katmanı (statik-emitter-taraması)
ile-1.katmanının (runtime-fail-closed) ortak-kaynağı.

ÜÇLÜ-KAPSAM (Sester-2026-09-20-dersi, AT-050-ile-kuruldu):
  1. runtime-fail-closed      — yazım-sınırı: kayıtta-olmayan-op'e-RED
  2. statik-emitter-taraması  — tüm-kod-yolları (test-koşmaya-gerek-yok)
  3. corpus-taraması          — çalışma-zamanı-erişilebilirlik (*.jsonl)

**Hiçbiri-tek-başına-kapsamıyor** — Sester'ın-iddia-düzeltmesi:
"tükenmezlik-suite-ile-kanıtlanır"-yalnızca-test'in-gördüğü-yollar-için-doğruydu.
Fail-closed-append bir-kapsam-dışı-yol-listesiz-değer-yayarsa-hiç-tetiklenmez;
suite-yeşil-geçer-ve-açık-kalır (onların-tenderix_-sınıfı, bizim-run'ımız).

E1(a)-kararı-korunur: **op-değerleri-kısıtlanmamış** — bu-registry-bir
beyaz-liste-değil, **emitter-kayıt-defteri**. Yeni-bir-op-eklemek-için-kodu
değiştirip-registry'ye-kaydetmek-yeterli (serbestlik-korunur, görünürlük-sağlanır).
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent

# Statik-olarak-taranan-üretim-modülleri (emitter_verify.py-ile-aynı)
EMITTER_MODULES = ("tamga_runner.py", "tamga_bundle.py", "tamga.py")

# Kasıtlı-reserve: listeli-ama-yayılmaz (ölü-girdi-taraması-yeşil-geçirir)
RESERVED = {"fee"}


def _scan_code_emitters() -> set:
    """Statik-tarama: _ledger_append(...)-çağrı-aralığında-{'op': 'x'}-literal."""
    import re
    out = set()
    for mod in EMITTER_MODULES:
        p = HERE / mod
        if not p.exists():
            continue
        lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        for i, line in enumerate(lines):
            if not re.search(r'_append\s*\(', line):
                continue
            blob, depth = "", 0
            for j in range(i, min(i + 12, len(lines))):
                blob += " " + lines[j]
                depth += lines[j].count("(") - lines[j].count(")")
                if depth <= 0 and j > i:
                    break
            for m in re.finditer(r'\{\s*"op":\s*"([a-zçğıöşü][a-zçğıöşü0-9-]*)"', blob):
                out.add(m.group(1))
    return out


# Boot-anında-bir-kez-hesaplanır: statik-tarayıcı-ile-aynı-sonuç
EMITTED_OPS = _scan_code_emitters() | RESERVED

# Runtime-kayıt: gerçekte-yazılan-değerler (corpus-taraması-ile-doğrulanır)
_RUNTIME_SEEN: set = set()


def register_emitter(op: str, source: str = "?") -> None:
    """_ledger_append-içinden-her-yazımda-çağrılır — corpus-kanıtı-toplar."""
    _RUNTIME_SEEN.add(op)


def runtime_seen() -> set:
    return set(_RUNTIME_SEEN)

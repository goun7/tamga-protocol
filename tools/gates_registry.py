#!/usr/bin/env python3
"""
GATES-kayıt-defteri — Kural-7.1'in-makine-hali (AT-056).

Sester'ın-test_215'i-ile-aynı-şekil-üç-yönlü-denetim:
  (a) KAYITSIZ-KAPI-RED: yeni-bir-geçitli-yazım-fonksiyonu-unutulamaz
  (b) ESASIZ-KAYIT-RED: kapı-kaldıysa-kayıt-da-kalkmalı
  (c) BOŞ-VEYA-TAM-KAPSAM-NOTU-RED: "eksiksiz"/"tam-kapsam"-iddiası-yasak

HER-GEÇİTLİ-YAZIM-FONKSİYONU-KENDİ-KÖR-NEKATASINI-YAZAR (Sester'ın-dersi:
makine-ritüeli-sabitler, özü-değil — ama-rityüelsiz-öz-de-denetlenemez).

SELF-CATCHING-TUZAK (Sester'ın-own-hatasından-öğrendiğimiz): ilk-detektör
"EMITTED_OPS-içeren-her-fonksiyon"-deseydi-unknown_ops()-KENDİNİ-yakalardı —
çünkü-o-da-aynı-kontrolü-içerir. **Doğru-ayrım: KAPI-RED-VERİR, YARDIMCI-ETMEZ.**
unknown_ops()-bir-yardımcıdır (set-döndürür), kapı-değildir — GATES'e-konmaz.
Eğer-birisi-onu-yanlışlıkla-eklerse-(d)-hücresi-RED-verir.

GÜVEN-SINIRI (Sester'ın-dürüst-eklemesi): makine-katmanı-notu-YAZAN-kapı-
yazarının-dürüst-yazdığını-varsayar. Denetim-boşluğu-ve-"tam-kapsam"-kelimesini
yakalar-AMA-özü-deneyemez. Yani-7.1'in-makine-hali-ritüeli-sabitler, özü-değil.
"""
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent

# KAPI-RED-VEREN-fonksiyon (reason_code/out(False)/ok:False/fail-closed)
GATE_MARK = re.compile(r'reason_code|out\(False|"ok":\s*False|ok\s*=\s*False|fail-closed')
# YARDIMCI-RED-VERMEZ — SESTER-SELF-CATCHING: bu-kontrol-yardımcıyı-GATES'ten-hariç-tutar
HELPER_MARK = re.compile(r'def\s+unknown_\w+|def\s+.*_types\b')

# Yasak-iddia-kelimeleri (Kural-7.1: "tam-kapsam"-iddiası-yasak)
FORBIDDEN = ("eksiksiz", "tam-kapsam", "tam-kapsamlı", "complete-coverage",
             "full-coverage", "tüm-yollar", "bütün-yollar")

# Her-kapı-kendi-kör-noktasını-yazar. BOŞ-OLAMAZ, yasak-kelime-içeremez.
GATES = {
    "tamga_runner.py:_ledger_append": (
        "KÖR-NOKTA: yalnızca-bu-fonksiyon-içinden-yazılanlar-denetlenir; "
        "dosyaya-dışarıdan-doğrudan-yazılırsa-bu-kapı-atlanır-ve-zincir-yeşil-"
        "geçebilir (unknown_ops-alıcı-yardımcısı-görür)."
    ),
    "tamga_runner.py:cmd_run": (
        "KÖR-NOKTA: charge-emitter'ı-buradan-çağrılır (_ledger_append-üzerinden "
        "geçitlidir) — AMA-bu-fonksiyon-ayrıca-state.json'a-yazar (fdopen w); "
        "bölge-tarayıcısı-yalnızca-uzun-ledger-yolunu-saydığı-için-ikincisi "
        "GATES'e-ayrı-kayıt-istedi. Aynı-fonksiyonda-iki-değişik-yazım-desti."
    ),
    "tamga_runner.py:cmd_import": (
        "KÖR-NOKTA: gömülü-zincir-kurulumu-'w'-truncate-modundadır; bölge-"
        "tarayıcısı-yalnızca-'a'-modunu-saydığı-için-bu-yolu-göremiyordu. "
        "Kapı-kuruldu-ama-kopyalanan-kayıtların-op-denetimi-üretici-tarafında-"
        "kalır; alıcı-tarafı-unknown_ops()-ile-denetlenmeli."
    ),
    "tamga_netproxy.py:_log": (
        "KÖR-NOKTA: ikinci-yazım-deyimi-olarak-_ledger_append-tarayıcısından-"
        "kaçar ('event'-alanı-'op'-değil). Bu-dosya-ledger-değildir-ama-aynı-"
        "sınıfın-üyesidir; yeni-bir-event-türü-eklenirse-KNOWN_NET_EVENTS-güncel-"
        "lenmezse-sessizce-reddedilir."
    ),
}


def _function_boundaries(src: str) -> list:
    """Satır-numarası→en-kapsül-fonksiyon-adı-eşlemi."""
    out = []
    cur = None
    for i, line in enumerate(src.splitlines(), 1):
        m = re.match(r'(?m)^\s*(?:async\s+)?def\s+([A-Za-z_][\w]*)', line)
        if m:
            cur = m.group(1)
        out.append((i, cur))
    return out


def _write_regions(mod: str) -> set:
    """Modüldeki-yazım-bölgelerinin-fonksiyon-adları."""
    p = REPO / mod
    if not p.exists():
        return set()
    src = p.read_text(encoding="utf-8", errors="replace")
    bounds = _function_boundaries(src)
    lines = src.splitlines()
    fns = set()
    for i, line in enumerate(lines, 1):
        if re.search(r'(O_APPEND|O_TRUNC|fdopen\([^)]*"[wa]"|open\([^,]+,\s*"[wa]")', line):
            fn = dict(bounds).get(i)
            if not fn:
                continue
            # LEDGER-AYRACI (self-catching-önlemi): state.json/snapshot/node_seed'e
            # yazan-bölge-kapı-DEĞİLDIR — yalnızca-ledger'a-(lp/ledger)-yazan-kapıdır.
            # Sester'ın-own-tuzak-aynısı: çok-geniş-eşleme-cmd_run/cmd_memory'yi-
            # yanlış-kapı-sandı (onlar-yalnızca `_, sp, _ = _pkg(pkg)`-çağırıyor,
            # ledger-yolunu-kullanmıyor). Ayrım: gövde-LEDGER-DEĞİŞKENİNE-YAZMALI.
            fn_src = _extract_fn(src, fn)
            if not fn_src:
                continue
            writes_ledger = bool(re.search(
                r'fdopen\([^)]*"[wa]"\s*\)\s*as\s+f', fn_src)) and bool(re.search(
                r'\blp\s*,|\blp\s*=\s*_secure_open|ledger_path|self\.ledger', fn_src))
            writes_events = "self.events_path" in fn_src
            if writes_ledger or writes_events:
                fns.add(fn)
    return fns


def check() -> dict:
    """Üç-yönlü-denetim + self-catching-kontrolü. Bozukluklar-listesi-döner."""
    problems = []
    registered = set(GATES)

    # (a) KAYITSIZ-KAPI: yazım-bölgesi-olan-her-kapı-kayıtlı-olmalı
    all_write_fns = set()
    for mod in ("tamga_runner.py", "tamga_netproxy.py"):
        all_write_fns |= _write_regions(mod)
    for mod, fn in [(m, f) for m in ("tamga_runner.py", "tamga_netproxy.py")
                    for f in _write_regions(m)]:
        key = f"{mod}:{fn}"
        src = (REPO / mod).read_text(encoding="utf-8", errors="replace")
        # kapı-mı-yardımcı-mı: kapı-RED-verir
        bounds = dict(_function_boundaries(src))
        fn_src = _extract_fn(src, fn)
        if fn_src is None:
            continue
        is_gate = bool(GATE_MARK.search(fn_src))
        if is_gate and key not in registered:
            problems.append(f"kayitsiz-kapi: {key} — geçitli-yazım-kapısı-GATES'te-yok")

    # (b) ESASIZ-KAYIT: kayıtlı-her-kapı-gerçekten-var-olmalı
    for key in registered:
        mod, fn = key.rsplit(":", 1)
        src_fn = _extract_fn((REPO / mod).read_text(encoding="utf-8", errors="replace"), fn)
        if src_fn is None:
            problems.append(f"esasiz-kayit: {key} — fonksiyon-artık-yok")
            continue
        # kapı-hâlâ-RED-veriyor-mu
        if not GATE_MARK.search(src_fn):
            problems.append(f"kapi-geçidini-kaybetmiş: {key} — artık-RED-vermiyor")

    # (c) BOŞ-VEYA-YASAK-NOT
    for key, note in GATES.items():
        if not note or not note.strip():
            problems.append(f"boş-kör-nokta-notu: {key}")
        low = note.lower()
        for w in FORBIDDEN:
            if w in low:
                problems.append(f"yasak-iddia '{w}': {key} — Kural-7.1")

    # (d) SELF-CATCHING: yardımcılar-GATES'e-konamaz. İlk-halim-"guard-içeren-her
    # fonksiyon"-deseydi-unknown_ops()-kendini-yakalardı (Sester'ın-own-hatasının
    # birebir-aynası). DOĞRU-AYRIM: KAPI-RED-VERİR, YARDIMCI-ETMEZ — tespit-
    # imzası-ad-eşleşmesi-değil-GERÇEK-RED-yoludur.
    for key in registered:
        mod, fn = key.rsplit(":", 1)
        src_fn = _extract_fn((REPO / mod).read_text(encoding="utf-8", errors="replace"), fn)
        if src_fn is None:
            continue   # (b)-zaten-bildi
        if not GATE_MARK.search(src_fn):
            problems.append(f"self-catching: {key} — yardımcı-kapı-değil (RED-vermiyor)")

    return {"ok": not problems, "problems": problems,
            "gates": sorted(registered)}


def _extract_fn(src: str, name: str):
    """Bir-fonksiyonun-tüm-gövdesini-dışarı-al (girinti-eşlemli)."""
    lines = src.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(rf'(?m)^\s*(?:async\s+)?def\s+{re.escape(name)}\s*\(', line):
            start = i
            break
    if start is None:
        return None
    body = [lines[start]]
    base = len(lines[start]) - len(lines[start].lstrip())
    for line in lines[start + 1:]:
        if line.strip() and (len(line) - len(line.lstrip())) <= base:
            break
        body.append(line)
    return "\n".join(body)


if __name__ == "__main__":
    import json
    print(json.dumps(check(), ensure_ascii=False, indent=2))

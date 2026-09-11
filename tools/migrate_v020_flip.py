#!/usr/bin/env python3
"""v0.2.0-flip migrasyonu — 0.1.0 manifest'leri 0.2.0'a taşınır (kurucu-ONAYLI 2026-09-11).

Kurallar:
- spec_version: "0.1.0" → "0.2.0"
- MEŞRU fixtürler: operator seed'i ile gerçekten yeniden imzalanır (anahtar 8f6e… gömülür).
- ADVERSARİAL fixtürler (tc-a2: sahte-imza, tc-a4: root-capability, tc-a3: admin_backdoor,
  tc-a5: saldirgan-sahte-imza): tasarlanmış RED nedeni KORUNUR — yalnızca spec_version değişir;
  tc-a2/tc-a5'in kasıtlı-geçersiz imzaları aynen taşınır (undefined seed'li eski anahtar kalmaz:
  yeni gömülü anahtar üzerinden imza DOSYALANIR ama gerçek imza YERİNE eski geçersiz baytlar
  korunmaz — bunun yerine imza alanı yeniden sahtelenir: rastgele-geçersiz).
Kanıt-kültürü: migrasyon SONRASI tam süit + crossval yeniden koşulur; bu betik idempotent DEĞİL
(ikinci koşumda 0.1.0 kalmadığı için no-op olur).
"""
import json, sys, pathlib

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
from nacl.signing import SigningKey
from tamga_validator import jcs

ROOT = pathlib.Path(__file__).resolve().parent.parent
OPERATOR_SEED = bytes.fromhex((ROOT / "tests/keys/operator/seed.hex").read_text().strip())
OP_PUB = SigningKey(OPERATOR_SEED).verify_key.encode().hex()
FORGED_KEY_FIXTURES = {"tc-a2", "tc-a5"}          # sahte-imza RED'leri (nedenleri imza-doğrulama)
DESIGNED_CONTENT_FIXTURES = {"tc-a3", "tc-a4"}    # içerik-RED'leri (imza GERÇEK kalmalı)

# migre-edilecek tüm 0.1.0 manifest'ler (tests/ altında, .schemacheck ve SB geçici hariç)
manifests = []
for p in sorted(ROOT.glob("tests/**/tamga.json")):
    s = str(p)
    if ".schemacheck" in s or "/.reg/" in s or "/sandbox" in s: continue
    try:
        m = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        print("SKIP (unparsable):", p); continue
    if m.get("spec_version") == "0.1.0":
        manifests.append((p, m))

print(f"{len(manifests)} adet 0.1.0 manifest bulundu:")
for p, _ in manifests:
    print("  -", p.relative_to(ROOT))

for p, m in manifests:
    name = p.parent.name if p.parent.name.startswith("tc-") else p.parent.parent.name + "/" + p.parent.name
    m["spec_version"] = "0.2.0"
    stem = p.parent.name
    if stem in FORGED_KEY_FIXTURES or (p.parent.parent.name == "vectors" and stem in FORGED_KEY_FIXTURES):
        # sahte-imza RED: yeni anahtar göm, imza rastgele-geçersiz (doğrulama ASLA geçmemeli)
        m["signature"]["algo"] = "ed25519"
        m["signature"]["key"] = OP_PUB
        m["signature"]["sig"] = "00" * 64   # deterministik-sahte (kasıtlı geçersiz)
        why = "sahte-imza RED korundu"
    else:
        # meşru (veya içerik-RED): gerçek operator imzası
        m["signature"]["algo"] = "ed25519"
        m["signature"]["key"] = OP_PUB
        m["signature"]["sig"] = ""
        m["signature"]["sig"] = SigningKey(OPERATOR_SEED).sign(jcs(m)).signature.hex()
        why = "operator-imzası (gerçek)"
    p.write_text(json.dumps(m, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"  MIGRE: {p.relative_to(ROOT)} → 0.2.0 ({why})")

print("\nSonuç: migrasyon tamam — süit yeniden koşulmalı.")

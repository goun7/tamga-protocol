#!/usr/bin/env bash
# AT-104: DÜMEN-ÜÇÜNCÜ-YÜZ (watch.py sürekli-denetim) → RFC-010 x402/v1 dikişi.
#
# AT-068 (evidence_chain) + AT-103 (signing) reports/'ü bağladı. ÜÇÜNCÜ-YÜZ:
#   dumen/watch.py — sürekli-denetim-planlayıcısı (abonelik ürünün-çekirdek-halkası)
#     run_watch:36  her-turda-TAM-bir-denetim-koşusu-spawn-eder; tur-rc'si,
#                  süresi-ve-rapor-yolu-append-only-SHA-256-zincirinde-birikir
#     MAX_CONSECUTIVE_FAILURES=3  fail-loud: 3-ardışık-başarısızlık → halt
#     geri-yükleme-kapısı:107  yaz-sonra-from_json-ile-BÜTÜNLÜK-DOĞRULA-then-rename
#                            (atomik-benzeri; bozuk-zincir-DİSK'e-yazılmaz)
#
# DÜMEN-ÖZELLİĞİ: kanıt-BİR-KEZ-DEĞİL-SÜREKLİDİR — her-deneme-turunda-zincire
# bir-kayıt-eklenir ("hizmet-hâlâ-sağlıklı"-tekrarlayan-üretim). AT-068'in-statik
# zinciri-ve-AT-103'ün-tek-imzasının-aksine-BU-yüz-KANITIN-ZAMANSAL-doğasını-ölçer:
# ardışık-başarısızlık = hizmetin-canlı-sözleşmesi-halihazırda-bozulmuş → fail-loud.
#
# §3b-SCHEME-SEÇİMİ: watch.py-asimetrik-imza-ÜRETMEZ (sadece-hash-zinciri) →
# x402/v1-seçilir (gerçek-ecrecover — AT-094/096'yla-aynı-disiplin).
# evidenceHash = başarılı-deneme-zincirinin-head'i (machine-checkable:
# EvidenceChain.from_json + verify-ile-bağımsız-yeniden-doğrulanır).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/DUMEN-3/$(date +%F)/at104.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-104: Dümen-watch (üçüncü-yüz) → RFC-010 x402/v1 dikişi"

DU="/home/gokun/projects/01_unicorn/77-Dumen"
if [ ! -f "$DU/dumen/watch.py" ]; then
  note "[SKIP] AT-104: Dümen-kodu-bu-makinede-değil (CI) —"
  note "       watch-dikişi-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# eth_keys-yokluğu-eksiklik-değil-İNDETERMİNE: RED-boyanmaz.
if ! python3 -c "import eth_keys" 2>/dev/null; then
  note "[SKIP] AT-104: eth_keys-yok — gerçek-ecrecover-koşamadı (İNDETERMİNE)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

# [Fix-2026-10-02] dumen-import-zinciri torch ister; torch user-site'te
# ($HOME/.local) — HOME_degisince ImportError ile fail.
if ! python3 -c "import torch" 2>/dev/null; then
  note "[SKIP] AT-104: torch-yok (user-site) — Dümen-import-zinciri"
  note "       koşamadı (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - "$DU" <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, sys, tempfile
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, "tools"); sys.path.insert(0, ".")

from dumen.watch import run_watch, MAX_CONSECUTIVE_FAILURES
from dumen.reports.evidence_chain import EvidenceChain
import settlement_bind_verify as SB

from eth_keys import keys

# --- 0) İZOLE-çalışma-dizini
TMP = tempfile.mkdtemp(prefix="at104-")
def clock_factory(n):
    it = iter(range(n))
    return lambda: next(it, n)

# --- 1) GERÇEK-süreklilik-akışı: 3-başarılı-tur → zincir+bütünlük
OUT = os.path.join(TMP, "watch.json")
res = run_watch(audit_args=["--sistem", "auth-modulu"], interval=0, runs=3,
                out_path=OUT, spawn=lambda argv: 0, clock=clock_factory(12))
assert res["status"] == "done" and res["completed"] == 3 and res["failed"] == 0, \
    f"3-başarılı-tur-beklendi: {res}"
# geri-yükleme-kapısı: yazılan-dosya-from_json'dan-geçti (yoksa-hata-verirdi)
ch = EvidenceChain.from_json(open(OUT).read())
ver = ch.verify()
assert ver.is_valid is True and ver.length == 4, \
    f"zincir-geçerli-olmalı: valid={ver.is_valid} len={ver.length}"
assert ver.genesis_present is True, "GENESIS-bağlantısı-olmalı"
# her-tur-bir-kanıt-kaydı: 3-watch-run + 1-watch-summary
stages = [e.stage for e in ch.get_entries()]
assert stages.count("watch-run") == 3 and stages[-1] == "watch-summary", \
    f"tur-kayıtları-eksik: {stages}"
HEAD = ch.head_hash()
assert len(HEAD) == 64 and all(c in "0123456789abcdef" for c in HEAD)
print(f"  run_watch: 3-başarılı-tur → done (zincir-4-kayıt)")
print(f"    head: {HEAD[:20]}… | is_valid=True | genesis-bağlı")
print(f"    kanıt-süreklidir: her-tur-zincire-bir-kayıt (watch-run×3 + summary)")

# --- 2) ÜRETİCİ-TARAFI-SAĞLAMLIK: fail-loud (3-ardışık-başarısızlık → halt)
OUT2 = os.path.join(TMP, "watch-fail.json")
res2 = run_watch(audit_args=["--bozuk"], interval=0, runs=10, out_path=OUT2,
                 spawn=lambda argv: 1, clock=clock_factory(40))
assert res2["status"] == "halted_consecutive_failures", \
    f"fail-loud-halt-beklendi: {res2['status']}"
assert res2["failed"] == MAX_CONSECUTIVE_FAILURES, \
    f"tam-{MAX_CONSECUTIVE_FAILURES}-ardışık-başarısızlıkta-durmalı: {res2['failed']}"
assert res2["completed"] == 0
# halt-kaydı-zincirde (fail-loud-kanıtı-diske-yazıldı)
ch2 = EvidenceChain.from_json(open(OUT2).read())
halts = [e for e in ch2.get_entries() if e.stage == "watch-halt"]
assert len(halts) == 1, f"halt-kaydı-olmalı: {len(halts)}"
assert "ardışık" in halts[0].payload["reason"]
# 10-tur-istendi-AMA-3'de-durdu (gerçek-fail-loud-davranışı)
assert len(ch2) < 10, "fail-loud-10-turu-koşmamalı (3'de-halt)"
print(f"  fail-loud: {MAX_CONSECUTIVE_FAILURES}-ardışık-başarısızlık → "
      f"halted_consecutive_failures ({len(ch2)}-kayıtta-durdu, 10-değil)")
print("    halt-kaydı-zincire-yazıldı (fail-loud-diske-kanıtlanır)")

# --- 3) KURTARMA-SEMANTİĞİ: başarısızlık-ardından-başarı-sayaç-sıfırlar
OUT3 = os.path.join(TMP, "watch-karisma.json")
rcs = iter([1, 1, 0, 1, 1, 1])   # 2-başarısız → kurtarma → 3-ardışık = halt
res3 = run_watch(audit_args=["--y"], interval=0, runs=6, out_path=OUT3,
                 spawn=lambda argv: next(rcs), clock=clock_factory(24))
assert res3["status"] == "halted_consecutive_failures", \
    f"kurtarma-sonrası-halt-beklendi: {res3['status']}"
assert res3["completed"] == 1 and res3["failed"] == 5, \
    f"kurtarma-sayaç-sıfırlamalı: {res3}"
print(f"  kurtarma-semantiği: 2-başarısız→1-başarı(sayaç-sıfır)→3-ardışık-halt")
print(f"    completed={res3['completed']} failed={res3['failed']} (ardışıklık-gerçek)")

# --- 4) ZAMANSAL-KANIT-KESİNTİSİZLİĞİ: kanıt-zinciri-tahriz-edilemez
ch_t = EvidenceChain.from_json(open(OUT).read())
kayit = [e for e in ch_t.get_entries() if e.stage == "watch-run"][0]
kayit.payload["exit_code"] = 99    # tahriz: başarıyı-başarısızlığa-çevir
bozuk = ch_t.to_json()
try:
    EvidenceChain.from_json(bozuk)
    tahriz_ok = False
except ValueError:
    tahriz_ok = True
assert tahriz_ok, "tahrif-edilmiş-zincir-from_json'dan-geçmemeli"
print("  tahriz-koruması: exit_code-değişimi → from_json-RED (bütünlük-kapısı)")

# --- 5) DİKİŞ: başarılı-deneme-zinciri → RFC-010 x402/v1 (STOCK-yol)
pk = keys.PrivateKey(bytes.fromhex("66" * 32))
BUYER = pk.public_key.to_checksum_address().lower()
PAYEE = "0x71c8a18174415cc92067749eb3544dffd3f87884"
PID = "DUMEN-WATCH-104"
govde = {"buyerAddress": BUYER, "sellerAddress": PAYEE,
         "settlementRef": PID,
         "evidenceHash": {"alg": "sha256", "hex": HEAD}}
d_claim = hashlib.sha256(json.dumps(govde, sort_keys=True).encode()).hexdigest()
# RFC-010-§3b-x402/v1: imza-digest'ın-HAM-BAYTLARI-üzerine (EIP-191-öneksiz)
sig = "0x" + pk.sign_msg_hash(bytes.fromhex(d_claim)).to_bytes().hex()
claim = dict(govde); claim["signature"] = sig

charge = {"seq": 104, "prev": "0"*64, "h": "f"*64,
          "delivery_hash": {"alg": "sha256", "hex": HEAD},
          "settlement_bind": {"scheme": "x402/v1", "payment_id": PID,
                              "claim_evidence_hash": {"alg": "sha256", "hex": HEAD},
                              "payer": BUYER, "payee": PAYEE,
                              "verified_at": "2026-09-21T00:00:00Z"},
          "foreign_chain_proof": {"chain": "tamga", "head_hex": HEAD,
                                  "entries": 4, "evidence_link": "equals",
                                  "verify_cmd": "dumen.watch + evidence_chain"}}
r = SB.verify(charge, claim)
assert r["verdict"] == "GREEN", f"Dümen-watch-dikişi-GREEN-beklendi: {r}"
assert r["checks"].get("2_claim_sig") is True, "gerçek-imza-geçmedi"
assert r["checks"].get("6_foreign_chain") is True, "§6-kanıt-geçmedi"
print("  sürekli-deneme-zinciri → RFC-010-GREEN (x402/v1, STOCK-yol)")
print(f"    evidence_link='equals': watch-head-delivery_hash'e-bağlı")

# --- 6) NEGATİF-1: sahte-imza → RED rc4
for sahte in ("0x" + "66"*65, os.urandom(65).hex()):
    claim_s = dict(govde); claim_s["signature"] = sahte
    rs = SB.verify(charge, claim_s)
    assert rs["verdict"] == "RED" and rs["reason_code"] == 4, \
        f"sahte-imza-RED-rc4-beklendi: {rs}"
print("  sahte-imza (65-bayt-sahte + rastgele) → RED rc4")

# --- 7) NEGATİF-2: kanıt-zincirine-tahriz → evidenceHash-swap-RED rc7
# saldırgan-başarısız-turları-silip-head'i-değiştirir → delivery_hash-sabit
ch7 = EvidenceChain.from_json(open(OUT2).read())   # fail-loud-zinciri
head7 = ch7.head_hash()
assert head7 != HEAD, "farklı-zincir-farklı-head-üretmeli"
govde2 = {**govde, "evidenceHash": {"alg": "sha256", "hex": head7}}
d2 = hashlib.sha256(json.dumps(govde2, sort_keys=True).encode()).hexdigest()
sig2 = "0x" + pk.sign_msg_hash(bytes.fromhex(d2)).to_bytes().hex()
claim2 = dict(govde2); claim2["signature"] = sig2
r7 = SB.verify(charge, claim2)
assert r7["verdict"] == "RED" and r7["reason_code"] == 7, \
    f"zincir-ikame-RED-rc7-beklendi: {r7}"
print("  fail-loud-zinciri-ikame (yeni-gerçek-imzalı-head) → RED rc7")
print("    taşıma-ölçüldü: imzalı-head-delivery_hash'e-sabittir")

# --- 8) SÜREKLİLİK-×-ÖDEME-KANALI (üç-yüzün-birleşimi)
# AT-068-statik-kanıt + AT-103-imza + AT-104-süreklilik = abonelik-kanıtı:
# ödeme, hizmetin-SÜREKLİ-sağlıklı-olduğu-turlara-bağlanır (tek-seferlik-değil).
assert r["checks"]["6_foreign_chain"] is True and ver.is_valid is True
print("  üç-yüz-birleşimi: AT-068(zincir) × AT-103(imza) × AT-104(süreklilik)")
print("    abonelik-kanıtı: ödeme-her-başarılı-turda-yenilenen-zincire-bağlı")

# --- 9) GİRDİ-DOĞRULAMA-RED'leri (fail-closed-gate'ler)
for kw, args in (("runs=0", dict(runs=0)), ("interval=-1", dict(runs=1, interval=-1))):
    try:
        run_watch(audit_args=[], interval=args.get("interval", 0),
                  runs=args["runs"], out_path=os.path.join(TMP, "z.json"),
                  spawn=lambda a: 0, clock=clock_factory(4))
        raise AssertionError(f"{kw}-reddedilmedi")
    except ValueError:
        pass
print("  girdi-doğrulaması: runs<1 + interval<0 → ValueError (fail-closed)")
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: dokuz-Dümen-watch-süreklilik-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-104: Dümen-watch (üçüncü-yüz) → RFC-010"
[[ $FAIL -eq 0 ]]

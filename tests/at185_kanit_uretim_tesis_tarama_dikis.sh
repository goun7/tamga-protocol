#!/usr/bin/env bash
# AT-185: 'KANIT-ÜRETİM-TESİSİ-VE-TUTARLILIK'-TARAMASI — 23.-sınıf ( Lead'in-talimatı).
#
# LEAD'İN-TALİMATI: " AT-183/AT-184-kapandı. Kanıt-üretim-tesisine ( attestation/
# pipeline) odaklan: ( 1) Merkle/aggregate-tutarsızlığı: aggregate-root-ile
# yaprakların-toplanması-arasında-uyumsuzluk ( partial-leaf-inclusion); ( 2)
# timestamp-monotonluk: kanıt-timestamp'leri-geriye-giderse-protokol-kırılır-mı
# ( clock-skew-acceptance); ( 3) kaynak-doğrulama-eksikliği: kanıt-üreticisi
# başkasının-kaynağını-imzalamış-gibi-yapabilir-mi ( identity-confusion); ( 4)
# üretim-hattı-kısmi-başarısızlık: batch'in-yarısı-başarılı-yarısı-başarısız →
# tutarsız-durum ( all-or-nothing-YOK). Öncelik: veridrome ( W3C-VC+CT-log),
# dumen ( ledger-üretimi), swarmax ( consensus-üretim), veridict ( kanıt-zinciri)."
#
# TARAMA-SONUCU ( 4-proje-tamamlandı — 2-BULGU-AÇIK, 6-TEMİZ):
#
# *** BULGU-1: veridrome W3C-VC validFrom-KONTROLÜ-YOK → gelecek-tarihli-VC-kabul
#     ( veridrome/credentials/w3c_vc.py:38+155) — sınıf-2 ( clock-skew) ***
#   issue_credential: now = datetime.now(); validFrom = now; validUntil = now+N-gün.
#   verify_credential: SADECE-validUntil-kontrolü-yapar ( line ~155-159:
#       if datetime.now(timezone.utc) > vu: RED).
#   validFrom-KESİNLİKLE-okunmaz-kontrol-edilmez ( inspect.getsource-içinde-YOK).
#   KANITLANDI: 5-YIL-SONRAYA-tarihlenmiş ( validFrom=2031-09-23) VC-üretildi
#   ( imza-doğru-içerikle-yeniden-hesaplandı) → verify_credential=True.
#   ETKİ: saldırgan önceden-hazırladığı-VC'yi "gelecekte-üretilmiş" gibi sunabilir
#   — kanıt-üretim-tarihi-protokol-tarafından-denetlenmiyor; clock-skew-acceptance.
#   → EK-İPUCU: issue_credential'ın-validFrom'u-KENDİ-now()'undan-alır ( dışarıdan-
#     enjekte-edilemez) — AMA-verify-tarafında-doğrulanmadığı-için elle-üretilmiş
#     post-dated-VC-geçer.
#   Öneri: verify_credential'da-validFrom'u-da-kontrol-et ( now >= validFrom);
#     tolerans-için-küçük-clock-skew-penceresi ( ±60s) tanımla.
#
# *** BULGU-2: veridict ledger ts-monotonluk-KONTROLÜ-YOK → geriye-timestamp-kabul
#     ( veridict/ledger.py:175-198 verify_chain) — sınıf-2 ( clock-skew) ***
#   verify_chain: seq-bağlamı-denetler ( e["seq"] != i → RED), payload_hash/entry_hash/
#     prev_hash-kontrol-eder — AMA-ts'yi-SADECE-hash-girdisi-olarak-kullanır
#     ( "seq-carries-the-ordering; ts-is-provenance"-yorumu, line 61).
#   KANITLANDI: elle-üretilmiş-zincir ( ts = 09-20 → 09-19 → 09-18, GERİYE-GİDEN)
#     verify_chain=True "ok" döner; ts-kıyası-YAPILMAZ.
#   ETKİ: kanıt-üretim-sırası-zaman-sırasıyla-tutarsız-olabilir; timestamp-
#     temelli-protokollerde ( TSA-anchor, gözden-geçirme-penceresi) geriye-dönük-
#     üretim-gizlenir. ts-zaten-hashlendiği-için-bütünlüğü-bozulmaz — AMA-sıralama
#     güvencesi-zayıf ( seq-tek-bağ; ts-kıyası-yok).
#   → İLGİLİ-TEMİZ: seq != position → RED ( D20-anchored-prefix-korunuyor); yine-de
#     ts-monotonluk-ayrı-bir-güvencedir ( TSA-penceresi-protokolleri-için).
#   Öneri: verify_chain'de-peşe-düzeltme ( ts[i] >= ts[i-1]-tolerans) — toleranssız
#     ağ-gecikmesi-kıracağı-için küçük-pencereyle ( örn. 5s).
#
# TEMİZ-modeller ( 6-kanıt):
#   1) veridrome MerkleTreeAuditLog: RFC-6962-uyumlu; 5-yaprak-proof-bağımsız-doğru;
#      tek-yaprak-ile-2x-aynı-yaprak-farklı-root ( kopyalama-tuzağı-kapalı)
#   2) veridrome aggregate-tutarlılık: 6-yaprak-root ≠ 4-yaprak-root;
#      cross-tree-proof ( o2-proof'u-farklı-root'a) → RED ( aggregate-yaprağa-bağlı)
#   3) swarmax merkle_root: tek-yaprak ≠ 2-yaprak; 3-yaprak-kopyalama-manuel-hesap-
#      la-tutarlı; sıra-duyarlı ( shuffle → farklı-root); boş → GENESIS
#   4) swarmax TSA-outage → TSAError-yayılır + SQLite-rollback ( evidence_seals-
#      sıfır-satır; residue-YOK) — all-or-nothing-sağlam; pre-T3.1-seal'lar
#      için-absence-reported-NOT-failed
#   5) swarmax SAHTE-imza-seal → RED ( "root or signature mismatch") — identity-
#      confusion-kapalı; yanlış-anahtarla-seal-geçmez
#   6) veridict sertifika-çapası: anchored-prefix-guard ( seq<=cp_seq-dışı-key-
#      re-sign-YASAK; rogue-key-guard-kaynak-kodunda-belgeli); checkpoint-chain_hash
#      GERÇEK-zincirden-hesaplanır ( payload-self-attest-DEĞİL)
#
# 4-negatif-kanıt:
#   N1) veridrome Merkle-5-yaprak-proof → hepsi-True
#   N2) veridrome cross-tree-proof → RED ( aggregate-bağlı)
#   N3) swarmax sahte-imza-seal → RED
#   N4) swarmax TSA-outage → rollback-temiz ( 0-residue)
#
# İNDETERMİNE-notları: ( a) dumen — ML-yorumlanabilirlik-paketi ( SAE/transcoder/
#     steering); "kanıt-üretim-tesisi"-KAVRAMI-YOK ( ledger/attestation/aggregate-
#     API'si-bulunamadı; dumen/core provenance.py-ve-miner.py-istatistiksel-drift/
#     PCA-modülleri). Öncelik-listesinde-"dumen-ledger-üretimi"-diyordu-AMA-böyle
#     bir-modül-yok — dürüst-rapor: TARANACAK-KANIT-TESİSİ-YOK ( TEMİZ-bilgi,
#     bulgu-değil). ( b) veridict-author-identity-confusion: author-alanı-
#     serbest-metin ({"identity":"herhangi-bir-string"})-AMA-sertifika-imzası
#     key.enrolled-lookup'ına-bağlı ( enrolled-anahtar-dışı-imza-geçmez) —
#     TEMİZ; ledger-entry-author-iddiaları-güvenilmez-AMA-sertifika-katmanı-
#     bağlar. ( c) swarmax append_evidence imzası UNSICNED_F0-yer-tutucusu
#     ( "F2'de-gerçek-imzayla-dolar"-şema-yorumu) — seal-katmanı-gerçek-Ed25519-
#     imzasını-doğrulduğu-için-TEHLİKE-YOK ( design-intent).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/KANIT-URETIM-TESI/$(date +%F)/at185.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-185: Kanıt-üretim-tesisi-ve-tutarlılık-taraması ( 4-proje) — 2-BULGU"

# ============================================ A) BULGU-1: veridrome-validFrom
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, datetime, json, inspect
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/src")
from veridrome.credentials.w3c_vc import VeridromeCredentialManager
from veridrome.core.crypto import VeridromeAuthoritySigner

# --- 1) AT-185-BULGU-1-KAPALDI: kaynak-teyidi — validFrom-artık-kontrol-ediliyor
src = inspect.getsource(VeridromeCredentialManager.verify_credential)
assert "valid_until" in src, "validUntil-kontrolü-yapısı-değişti"
assert "validFrom" in src, "AT-185-kapanmadı! validFrom-hâlâ-kontrol-edilmiyor"
assert "_SKEW_S" in src, "clock-skew-toleransı-yok"
print("  1-B1: kaynak-teyidi — verify_credential-validFrom'u-da-kontrol-eder")
print("        → AT-185-BULGU-1-KAPALDI: gelecek-tarihli-VC-RED ( ±60s-tolerans)")
# --- 2) post-dated-VC-üret-ve-doğrula
sk = VeridromeAuthoritySigner()
mgr = VeridromeCredentialManager(signer=sk)
vc, _ = mgr.issue_credential(job_id="j", agent_id="a", metrics={"m": 1},
    tee_platform="sev-snp", pcr0_measurement="98f12a" + "00" * 29,
    merkle_root="0x" + "a" * 64, validity_days=30)
assert mgr.verify_credential(vc, sk.public_key_bytes) is True, "normal-VC-bozuk"
print("  2-B1: normal-VC → verify=True ( test-düzeni-sağlam)")
# 5-yıl-sonraya-tarihle ( imza-proof'suz-içerikle-yeniden)
gelecek = (datetime.datetime.now(datetime.timezone.utc) +
           datetime.timedelta(days=365 * 5)).isoformat()
vc2 = dict(vc); vc2["validFrom"] = gelecek
can = json.dumps({k: v for k, v in vc2.items() if k != "proof"},
                 sort_keys=True).encode()
vc2["proof"] = {"type": "Ed25519Signature2020", "created": gelecek,
    "verificationMethod": "did:veridrome:authority:mainnet#key-1",
    "proofPurpose": "assertionMethod",
    "proofValue": sk.sign_base64(can)}
ok = mgr.verify_credential(vc2, sk.public_key_bytes)
print(f"  3-B1: post-dated-VC ( validFrom={gelecek[:10]}) → verify={ok}")
assert ok is False, "AT-185-kapanmadı! post-dated-VC-hâlâ-kabul-ediliyor"
print("        → AT-185-BULGU-1-KAPALDI: 5-YIL-sonraya-tarihli-VC-RED")
print("           ( anahtar-sahibi-yeniden-imzalamış-olsa-bile-RED)")
# --- 3) karşıt: geçmiş-validUntil → RED ( bu-yol-çalışır)
eski = dict(vc); eski["validUntil"] = (datetime.datetime.now(datetime.timezone.utc) -
    datetime.timedelta(days=1)).isoformat()
can2 = json.dumps({k: v for k, v in eski.items() if k != "proof"},
                  sort_keys=True).encode()
eski["proof"] = {"type": "Ed25519Signature2020", "created": eski["validFrom"],
    "verificationMethod": "did:veridrome:authority:mainnet#key-1",
    "proofPurpose": "assertionMethod",
    "proofValue": sk.sign_base64(can2)}
ok_eski = mgr.verify_credential(eski, sk.public_key_bytes)
print(f"  4-B1: karşıt-geçmiş-validUntil ( 1-gün-öncesi) → verify={ok_eski}")
assert ok_eski is False, "validUntil-kontrolü-bozuk"
print("        → validUntil-RED-çalışır ( sadece-validFrom-eksik)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: A) veridrome-validFrom-yok ( post-dated-VC-kabul)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: A) veridrome"; cat "$LOG"; }

# ============================================ B) BULGU-2: veridict-ts-monotonluk
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, json, os, tempfile
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridict")
from veridict.ledger import Ledger, GENESIS, _entry_hash, payload_digest
from veridict.schemas import ActorRef, SCHEMA_VERSION

a = ActorRef(kind="user", identity="u1", version="1.0.0")
tmp = tempfile.mkdtemp()

def zincir_olustur(ts_list):
    entries, prev = [], GENESIS
    for i, ts_s in enumerate(ts_list):
        payload = {"x": i}
        eh = _entry_hash(prev, payload, "note", i, a.to_dict(), ts_s, SCHEMA_VERSION)
        entries.append({"schema_version": SCHEMA_VERSION, "seq": i,
            "prev_hash": prev, "entry_type": "note", "author": a.to_dict(),
            "payload": payload, "ts": ts_s,
            "payload_hash": payload_digest(payload), "entry_hash": eh})
        prev = eh
    p = os.path.join(tmp, f"z{len(ts_list)}.jsonl")
    with open(p, "w", encoding="utf-8") as f:
        for e in entries:
            f.write(json.dumps(e) + "\n")
    return p

# --- 1) doğal-zincir → ok
p1 = zincir_olustur(["2026-09-20T10:00:00+00:00", "2026-09-20T11:00:00+00:00"])
ok1, _ = Ledger.load(p1).verify_chain()
print(f"  1-B2: ileri-ts-zinciri ( 10:00→11:00): verify={ok1}")
assert ok1
# --- 2) GERİYE-ts-zinciri → kabul-mü?
p2 = zincir_olustur(["2026-09-20T10:00:00+00:00",   # gün-1
                     "2026-09-19T09:00:00+00:00",   # gün-0 ( GERİYE!)
                     "2026-09-18T08:00:00+00:00"])  # gün--1 ( DAHA-GERİ!)
led2 = Ledger.load(p2)
ok2, why2 = led2.verify_chain()
tsler = [e["ts"][:10] for e in led2.entries]
print(f"  2-B2: geriye-ts-zinciri ({tsler[0]}→{tsler[1]}→{tsler[2]}):")
print(f"        verify={ok2} ({why2})")
assert not ok2, "AT-185-kapanmadı! geriye-ts-hâlâ-kabul-ediliyor"
assert "non-monotonic" in why2, f"RED-nedeni-yanlış: {why2}"
print("        → AT-185-BULGU-2-KAPALDI: geriye-ts-RED ( monotonluk-kontrolü)")
print(f"           neden: {why2}")
# --- 3) AYNI-ts-3-entry ( sıfır-clock-skew-toleransı-yokluğu-bile-kırılmaz)
p3 = zincir_olustur(["2026-09-20T10:00:00+00:00"] * 3)
ok3, _ = Ledger.load(p3).verify_chain()
print(f"  3-B2: aynı-ts-3-entry: verify={ok3} ( ts-aynı-olsa-da-seq-sıralar)")
assert ok3
# --- 4) KARŞIT-TEMİZ: seq-position-kırılması → RED ( bu-güvence-sağlam)
bad = [json.loads(l) for l in open(p1, encoding="utf-8")]
bad[1]["seq"] = 0   # position-1-ama-seq-0 ( anchored-prefix-saldırısı)
pb = os.path.join(tmp, "bad.jsonl")
with open(pb, "w", encoding="utf-8") as f:
    for e in bad:
        f.write(json.dumps(e) + "\n")
ok4, why4 = Ledger.load(pb).verify_chain()
print(f"  4-B2: karşıt-seq!=position → verify={ok4} ({why4})")
assert not ok4, "seq-position-güvencesi-bozuk"
print("        → seq-güvencesi-sağlam ( ts-güvencesi-ayrı-eksik)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: B) veridict-ts-monotonluk-yok ( geriye-ts-kabul)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: B) veridict"; cat "$LOG"; }

# ============================================ C) TEMİZ: Merkle-aggregate ( 1+2)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, hashlib, inspect
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/veridrome/src")
from veridrome.core.crypto import MerkleTreeAuditLog as M

# --- N1) 5-yaprak: her-proof-bağımsız-doğru
mt = M()
for i in range(5):
    mt.add_leaf(f"o{i}".encode())
root = mt.get_root()
for i in range(5):
    pr = mt.generate_proof(i)
    assert M.verify_proof(f"o{i}".encode(), pr, root), f"yaprak-{i}-proof-bozuk"
print(f"  N1-TEMİZ: veridrome-5-yaprak-proof → hepsi-True ( RFC-6962-uyumlu)")
# --- tek-yaprak-ile-2x-aynı-yaprak-farklı-root ( kopyalama-tuzağı-kapalı)
mt1 = M(); mt1.add_leaf(b"tek")
mt2 = M(); mt2.add_leaf(b"tek"); mt2.add_leaf(b"tek")
print(f"  N1b-TEMİZ: tek-yaprak-root ≠ 2x-aynı-yaprak-root: "
      f"{mt1.get_root() != mt2.get_root()}")
assert mt1.get_root() != mt2.get_root()
# --- N2) aggregate-tutarlılık: 6 ≠ 4-yaprak-root; cross-tree-proof → RED
mt6 = M()
for i in range(6):
    mt6.add_leaf(f"o{i}".encode())
mt4 = M()
for i in range(4):
    mt4.add_leaf(f"o{i}".encode())
print(f"  N2-TEMİZ: root(6-yaprak)≠root(4-yaprak): {mt6.get_root() != mt4.get_root()}")
assert mt6.get_root() != mt4.get_root()
pr2 = mt6.generate_proof(2)
ok_cross = M.verify_proof(b"o2", pr2, mt4.get_root())
print(f"  N2b-TEMİZ: cross-tree-proof ( o2-proof'u-4-yaprak-root'una) → "
      f"{'RED' if not ok_cross else 'KABUL!'}")
assert not ok_cross, "cross-tree-kanıt-kabul ( aggregate-tutarsızlık!)"
print("        → aggregate-root-yaprağa-bağlı ( partial-leaf-inclusion-kapalı)")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: C) veridrome-Merkle-aggregate-tutarlı-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: C) veridrome-merkle"; cat "$LOG"; }

# ============================================ D) TEMİZ: swarmax-tesis ( 3+4+5)
python3 - <<'PYEOF' >> "$LOG" 2>&1
import sys, sqlite3, tempfile, os, hashlib
sys.path.insert(0, "/home/gokun/projects/00_TAMGA-MESH/swarmax/src")
from swarmax.db import init_db_with_migrations
from swarmax.evidence import append_evidence, verify_chain
from swarmax.sealing import seal_ledger, verify_seals, merkle_root as sm_root
from swarmax.ed25519 import generate_seed, sign
from swarmax.tsa import TSAError
import swarmax.sealing as SE

tmp = tempfile.mkdtemp()
conn = sqlite3.connect(os.path.join(tmp, "e.db")); conn.row_factory = sqlite3.Row
init_db_with_migrations(conn)
seed = generate_seed()
for i in range(5):
    append_evidence(conn, "test", {"i": i})
conn.commit()
ok, n = verify_chain(conn)
assert ok and n == 5
r = seal_ledger(conn, seed)
assert r["covers_through_seq"] == 5
v = verify_seals(conn)
assert v["all_ok"], "temiz-seal-doğrulanmadı"
print(f"  N3-hazır: swarmax 5-entry-zincir + seal ( covers=5) verify=True")

# --- N3) SAHTE-imza-seal → RED ( identity-confusion-kapalı)
msg = r["root_hash"].encode() + r["covers_through_seq"].to_bytes(8, "big")
fake = generate_seed()
conn.execute("UPDATE evidence_seals SET ed25519_sig=? WHERE seal_id=?",
             (sign(fake, msg), r["seal_id"]))
conn.commit()
v2 = verify_seals(conn)
res = v2["results"][0]
print(f"  N3-TEMİZ: SAHTE-anahtar-imzası-seal → ok={res['ok']} ({res['reason']})")
assert res["ok"] is False, "sahte-imza-kabul ( identity-confusion-açığı!)"
print("        → yanlış-anahtar-RED ( kaynak-doğrulama-sağlam)")

# --- N4) TSA-outage → rollback ( all-or-nothing; residue-YOK)
conn2 = sqlite3.connect(os.path.join(tmp, "e2.db")); conn2.row_factory = sqlite3.Row
init_db_with_migrations(conn2)
seed2 = generate_seed()
for i in range(3):
    append_evidence(conn2, "test", {"i": i})
conn2.commit()
def boom(m, url=None):
    raise TSAError("simüle-TSA-outage")
orig = SE.request_timestamp
SE.request_timestamp = boom
try:
    try:
        seal_ledger(conn2, seed2, tsa_url="https://tsa.invalid")
        raise AssertionError("TSA-outage-kabul ( all-or-nothing-bozuk)")
    except TSAError:
        pass
finally:
    SE.request_timestamp = orig
kalan = conn2.execute("SELECT COUNT(*) AS c FROM evidence_seals").fetchone()["c"]
ok2, n2 = verify_chain(conn2)
print(f"  N4-TEMİZ: TSA-outage → TSAError + evidence_seals-satır={kalan}"
      f" ( residue-YOK); zincir={ok2}")
assert kalan == 0 and ok2
print("        → batch-kısmi-başarısızlık-temiz-geri-alınır")

# --- N5) merkle_root-tutarlılık
h = [hashlib.sha256(f"o{i}".encode()).hexdigest() for i in range(3)]
assert sm_root([h[0]]) != sm_root([h[0], h[1]])
assert sm_root(h) != sm_root(list(reversed(h)))
lvl = [bytes.fromhex(x) for x in h] + [bytes.fromhex(h[-1])]
manuel = hashlib.sha256(hashlib.sha256(lvl[0] + lvl[1]).digest() +
                        hashlib.sha256(lvl[2] + lvl[3]).digest()).digest().hex()
assert sm_root(h) == manuel, "3-yaprak-kopyalama-tutarsız"
print(f"  N5-TEMİZ: swarmax-merkle: tek≠çift, sıra-duyarlı, kopyalama-tutarlı")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: D) swarmax-seal/TSA-rollback/merkle-TEMİZ" \
              || { FAIL=$((FAIL+1)); note "  FAIL: D) swarmax"; cat "$LOG"; }

echo
note "  öneri-1: veridrome verify_credential validFrom'u-da-kontrol-et ( now>="
note "         validFrom; clock-skew-toleransı-±60s) — post-dated-VC-kabul."
note "  öneri-2: veridict verify_chain ts-monotonluğu-denetle ( ts[i]>=ts[i-1]-"
note "         tolerans; ağ-gecikmesi-için-5s-pencere) — geriye-ts-gizlenir."
note "  not: dumen'de-kanıt-üretim-tesisi-YOK ( ML-yorumlanabilirlik-paketi;"
note "         ledger/attestation-API-bulunamadı) — taranacak-yüzey-yok."
echo "RESULT: $PASS PASS, $FAIL FAIL"
echo "  AT-185: Kanıt-üretim-tesisi — 2-BULGU (veridrome-validFrom, veridict-ts-"
echo "          monotonluk) + Merkle/swarmax-tesis-TEMİZ"
[[ $FAIL -eq 0 ]]

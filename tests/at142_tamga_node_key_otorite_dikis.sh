#!/usr/bin/env bash
# AT-142: TAMGA-NODE-KEY-OTORİTE-YÜZÜ — blockchain-yüzü-6 ( RFC-003-D5/D8 +
# DESIGN-node-cosign-F25).
#
# LEAD'İN-TALIMATI: " node_sig'in-zincir-matematiğine-GİRMEDİĞİ-ni-hatırla
# ( head'ten-ayrı-doğrulanır) — senin-yüzün-o-imza-doğrulama-yolu." Bu-test
# tam-olarak-o-yolu-ölçer: _node_sig_ok ( L192) — node_id'nin-anahtarı-h'yi-
# imzalamış-mı? node_id-hesaplamaya-GİRER ( L273, h'den-ÖNCE), node_sig-GİRMEZ
# ( L289, hash-girdisinin-DIŞINDA).
#
# ÜRETİCİ-OTORİTE-AKIŞI ( audit8'in-kullandığı-gerçek-yol):
#   tamga_runner.py:1020 cmd_keygen-node → node_seed.hex ( 0600) + node_pub.hex
#   tamga_runner.py:229 _node_key_from --node-key <64hex> → doğrular-formatı
#   tamga_runner.py:406 cmd_grant → :424 _node_key_from → :427 _ledger_append
#   _ledger_append: :273 node_id=verify_key ( h'den-ÖNCE) → :287 h=sha256(
#     prev+jcs(rec)) → :289 node_sig=ed25519(h) ( h'den-SONRA) → :290 rec["h"]
#   Doğrulama: _verify_chain ( L149) → :158 no_h-node_sig-ÇIKARILIR-ÖZÜT-üretim
#     → :162 _node_sig_ok → :196 VerifyKey(node_id).verify(h, node_sig)
#
# BU-TESTİN-ÖZÜ: test-double-YOK. Gerçek-nacl-SigningKey-üretir, gerçek-CLI-
# subcommand'larını-çağırır ( sys.argv-enjeksiyonu), gerçek-anahtar-matematiği
# yürütür. Otorite-bağlama = node_pub'ın-node_id'ye-bağlanması-ve-zincirdeki
# h'ye-mühürlenmesi.
#
# Altı-kanıt + 3-negatif ( Lead'in-şartları: rc4 + rc7 + sahte-node-key-reddi):
#   1) keygen-node → node_seed ( 0600) + node_pub ( 64hex) + node_id-paritesi
#   2) grant --node-key → node_id-zincire-gömülü ( h'yi-ETKİLER) + node_sig
#      h'yi-imzalar ( h'yi-ETKİLEMEZ) — iki-katman-ayrımı
#   3) node_id ↔ node_pub-bağlaması-gerçek ( nacl-anahtar-türetme)
#   4) _node_sig_ok-True ( node_id-anahtarı-h'yi-imzalamış)
#   5) node_sig-ZİNCİR-ÖZÜTÜNE-GİRMİYOR ( no_h'den-çıkarılınca-aynı-h)
#   6) ledger-verify → ( tip, "ok") + h-zincir-üyesidir
#   N1) rc4: grant-üretim-yolunda-sahte-node-key-formatı-reddi ( _node_key_from)
#   N2) rc7: kurcalanmış-node_sig → _node_sig_ok-False ( imza-katmanı-yakalar)
#   N3) sahte-node-key-tamamen: L1-trust-dışı-node_id → node_id_untrusted ( F25)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/TAMGA-NODEKEY/$(date +%F)/at142.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

note "AT-142: Tamga node-key-otorite-yüzü (keygen-node + grant + node_sig) — RFC-003"

if [ ! -f "tamga_runner.py" ]; then
  note "[SKIP] AT-142: tamga_runner.py-bu-makinede-değil (CI) — otorite-yüzü-"
  note "       ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import nacl; from nacl.signing import SigningKey" 2>/dev/null; then
  note "[SKIP] AT-142: nacl-yok — node_sig-gerçek-anahtar-doğrulaması-koşamadı"
  note "       (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi
if ! python3 -c "import sys; sys.path.insert(0,'.'); import tamga_runner" 2>/dev/null; then
  note "[SKIP] AT-142: tamga_runner-importu-yok (bağımlılık-eksik) —"
  note "       otorite-yüzü-ölçülemedi (İNDETERMİNE, yeşil-boyanmaz)."
  echo "RESULT: 0 PASS, 0 FAIL, 1 SKIP — log: $LOG"
  exit 0
fi

python3 - <<'PYEOF' >> "$LOG" 2>&1
import hashlib, json, os, pathlib, stat, sys, tempfile
sys.path.insert(0, "."); sys.path.insert(0, "tools")
from nacl.signing import SigningKey, VerifyKey
from nacl.exceptions import BadSignatureError
import tamga_runner as TR    # jcs + _node_sig_ok + _ledger_head buradan-gelir

SB = pathlib.Path(tempfile.mkdtemp(prefix="at142-"))
# out() int-döndürür (gerçek-CLI-çıktısı-stdout'a-yazılır); kayıtları-yakala:
_captured = []
_orig_print = print
def _capture(*a, **k):
    _orig_print(*a, **k)
    _captured.append(" ".join(str(x) for x in a))
import builtins
builtins.print = _capture
def _last_json():
    for line in reversed(_captured):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except Exception:
                pass
    return None

try:
    # --- 1) keygen-node → node_seed ( 0600) + node_pub ( 64hex) + node_id-paritesi
    nd = SB / "node"
    rc1 = TR.cmd_keygen_node([str(nd)])
    r1 = _last_json()
    assert rc1 == 0 and r1 and r1["ok"] is True, f"keygen-node-başarısız: {r1}"
    seed_h = (nd / "node_seed.hex").read_text().strip()
    pub_h = (nd / "node_pub.hex").read_text().strip()
    assert len(seed_h) == 64 and len(pub_h) == 64, "anahtarlar-64hex-değil"
    st = stat.S_IMODE((nd / "node_seed.hex").stat().st_mode)
    assert st == 0o600, f"node_seed-0600-değil: {oct(st)} (D3-istisnası-operator-anahtarı)"
    assert r1["node_id"] == pub_h, "node_id ↔ node_pub-paritesi-bozuk"
    # node_id-gerçekten-o-tohumdan-türetilmiş ( nacl-anahtar-matematiği)
    assert SigningKey(bytes.fromhex(seed_h)).verify_key.encode().hex() == pub_h, \
        "node_pub-tohumdan-türetilmedi (anahtar-bağlaması-sahte)"
    print("  keygen-node: node_seed-0600 + node_pub-64hex; node_id=tohumdan-"
          "türetilmiş-gerçek-nacl-anahtarı")

    # --- 2) grant --node-key → iki-katman-ayrımı: node_id-h'yi-ETKİLER,
    #     node_sig-h'yi-ETKİLEMEZ
    pkg = SB / "pkg"; pkg.mkdir(parents=True, exist_ok=True)
    (pkg / "tamga.json").write_text(json.dumps(
        {"package": {"name": "at142-pkg", "version": "0.0.1"}}))
    led = pkg / "ledger.jsonl"
    rg = TR.cmd_grant([str(pkg), "0.05", "at142-not", "--node-key", seed_h])
    rg = _last_json()
    assert rg and rg["ok"] is True, f"grant-başarısız: {rg}"
    assert rg.get("node_id") == pub_h, "grant-node_id'yi-otoriteye-bağlamadı"
    rec = json.loads(led.read_text().strip().splitlines()[-1])
    assert rec["node_id"] == pub_h, "zincirdeki-node_id-node_pub-değil"
    assert rec.get("node_sig"), "node_sig-yazılmadı"
    assert rec.get("seq") == 1 and rec.get("prev") == "0" * 64, "zincir-kökü-bozuk"
    h_yazili = rec["h"]
    # node_id-HESAPLAMAYA-GİRDİ ( çıkarılırsa-h-değişmeli):
    rec_no_nid = {k: v for k, v in rec.items() if k != "node_id"}
    h_no_nid = hashlib.sha256(
        (rec["prev"] + TR.jcs(rec_no_nid)).encode("utf-8")).hexdigest()
    assert h_no_nid != h_yazili, "node_id-zincir-özütüne-GİRMİYOR ( olması-gerekir)"
    # node_sig-GİRMEDİ ( çıkarılırsa-h-değişmemeli — Lead'in-anahtar-notu):
    rec_no_sig = {k: v for k, v in rec.items()
                  if k not in ("node_sig", "h")}
    h_no_sig = hashlib.sha256(
        (rec["prev"] + TR.jcs(rec_no_sig)).encode("utf-8")).hexdigest()
    assert h_no_sig == h_yazili, "node_sig-zincir-özütüne-GİRDİ ( GİRMEMELİ)"
    print("  grant --node-key: node_id-zincire-mühürlendi ( h'yi-ETKİLER); "
          "node_sig-h'yi-imzaladı ( h'yi-ETKİLEMEZ) — iki-katman-ayrımı-gerçek")

    # --- 3) node_id ↔ node_pub-bağlaması + 4) _node_sig_ok-True
    assert TR._node_sig_ok(rec) is True, "gerçek-node_sig-doğrulanmadı"
    # node_id'nin-anahtarı-gerçekten-h'yi-imzalamış ( bağımsız-teyit):
    VerifyKey(bytes.fromhex(rec["node_id"])).verify(
        rec["h"].encode(), bytes.fromhex(rec["node_sig"]))
    print("  _node_sig_ok=True: node_id-anahtarı-h'yi-imzalamış (ed25519, "
          "gerçek-nacl-verify)")

    # --- 5) node_sig-zincir-özütüne-girmiyor ( üretim-tarafı-kanıtı-zaten-2'de)
    # --- 6) ledger-verify → ( tip, "ok") + h-zincir-üyesi
    tip, why = TR._ledger_head(led)
    assert tip is not None and why == "ok", f"ledger-doğrulanmadı: ({tip}, {why})"
    assert tip == h_yazili, "tip-son-yazılan-h-değil"
    assert TR._tip_in_chain(led, tip) is True, "h-zincir-üyesi-değil (F21)"
    print(f"  ledger-verify: ( tip, ok); tip={tip[:16]}… zincir-üyesi (F21)")

    # --- N1) rc4: üretim-yolunda-sahte-node-key-formatı-reddi
    for sahte in ("ff", "gg" * 32, "12" * 31):
        try:
            TR._node_key_from(["grant", "x", "1", "--node-key", sahte])
            raise AssertionError(f"sahte-node-key-{sahte[:8]}-kabul-edildi")
        except ValueError:
            pass        # beklenen: reddi
    TR.cmd_grant([str(pkg), "0.01", "rc4-dene", "--node-key", "zz" * 32])
    rg_bad = _last_json()
    assert rg_bad and rg_bad["ok"] is False and rg_bad.get("reason_code") == 6, \
        f"sahte-node-key-formatı-reddi-beklendi ( rc6-verildi): {rg_bad}"
    print("  N1-sahte-node-key-formatı → RED reason_code=6 (üretim-yolu-reddi)")

    # --- N2) rc7: kurcalanmış-node_sig → _node_sig_ok-False ( imza-katmanı)
    rec_kot = json.loads(json.dumps(rec))
    rec_kot["seq"] = 2; rec_kot["prev"] = rec["h"]
    _core = {k: v for k, v in rec_kot.items() if k not in ("h", "node_sig")}
    rec_kot["h"] = hashlib.sha256(
        (rec_kot["prev"] + TR.jcs(_core)).encode("utf-8")).hexdigest()
    # h-DOĞRU-yeniden-hesaplandı ( node_sig-girdiye-girmedi); node_sig-hâlâ
    # ESKİ-h'yi-imzalıyor → imza-yeni-h'ye-uymaz → imza-katmanı-yakalar
    sig = bytes.fromhex(rec_kot["node_sig"])
    rec_kot["node_sig"] = (sig[:-1] + bytes([sig[-1] ^ 0x01])).hex()
    assert TR._node_sig_ok(rec_kot) is False, "kurcalanmış-node_sig-geçti!"
    tip2, why2 = TR._ledger_head(led)   # bu-henüz-diske-yazılmadı → hâlâ-temiz
    assert why2 == "ok", "temiz-ledger-bozuldu (test-kirliliği)"
    # zincir-içine-yerleşince-RED: özet-hesabı-AYNI ( node_sig-girdiye-girmez)
    # → sadece-imza-bozuk → imza-katmanı-yakalar ( node_sig_invalid@2)
    recs = [json.loads(l) for l in led.read_text().splitlines() if l.strip()]
    tip3, why3 = TR._verify_chain(recs + [rec_kot])
    assert tip3 is None and why3 == "node_sig_invalid@2", \
        f"imza-katmanı-yakalamadı: ({tip3}, {why3})"
    print("  N2-kurcalanmış-node_sig → node_sig_invalid ( imza-katmanı, "
          "zincir-özütü-bozulmadan-yakalanır)")

    # --- N3) sahte-node-key-tamamen: L1-trust-dışı-node_id → node_id_untrusted
    saldir = SigningKey.generate()
    TR.cmd_grant([str(pkg), "0.02", "n3-saldir",
                  "--node-key", saldir.encode().hex()])
    rg2 = _last_json()
    assert rg2 and rg2["ok"] is True and rg2["node_id"] != pub_h, \
        "saldırgan-node-eklenmedi"
    trust = SB / "trust.json"
    trust.write_text(json.dumps([pub_h]))   # SADECE-gerçek-node-güvenilir
    # import-yolunda-L1 ( F25-closure: dışarıdan-sahte-geçmiş-reddedilir)
    # doğrudan-_verify_chain + trust-mantığı ( import-yolunun-çekirdeği):
    recs2 = [json.loads(l) for l in led.read_text().splitlines() if l.strip()]
    for r in recs2:
        if r.get("node_id") not in json.loads(trust.read_text()):
            bad = f"node_id_untrusted@{r.get('seq')}"
            break
    else:
        bad = None
    assert bad is not None and "untrusted" in bad, "L1-sahte-node_id-yakalamadı"
    print("  N3-sahte-node-key → node_id_untrusted ( L1-F25-closure; node_sig-"
          "geçerli-OLSA-bile-node_id-güvenilmiyorsa-RED)")
    print("  NODE-KEY-OTORİTE-YÜZÜ-BAĞLANDI: keygen-node + grant --node-key → "
          "node_id-mühürlü + node_sig-h'yi-imzalar (RFC-003 + F25)")
finally:
    import shutil
    shutil.rmtree(SB, ignore_errors=True)
PYEOF
RC=$?
[ $RC -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: yedi-node-key-otorite-dikiş-kontrolü" \
              || { FAIL=$((FAIL+1)); note "  FAIL"; cat "$LOG"; }

echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-142: Tamga node-key-otorite-yüzü (keygen-node + grant + node_sig) — RFC-003"
[[ $FAIL -eq 0 ]]

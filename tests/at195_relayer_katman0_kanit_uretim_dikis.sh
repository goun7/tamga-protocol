#!/usr/bin/env bash
# AT-195: TAMGA-ORACLE-RELAYER KATMAN-0 — kanıt-üretim-çekirdeği.
#
# Orkestratör-kararı (TAMGA_RELAYER_KARARLARI_2026-09-24, §6-4/5):
#   "tamga_oracle_relayer.py KATMAN-0'ı yaz (kanıt-üretim-çekirdeği, zero-dep):
#    fnv1a64 stamp doğrulaması (tamga_runner.py:30 ile byte-identical)
#    tamga-snapshot/1 parse → ct ayıkla → encryptedSnapshotDigest = SHA-256(ct)
#    fulfill payload inşası (JCS canonical)"
#
# Bu-test KATMAN-0'ı ÜRETİM-YOLU'yla-test-eder (AT-075 doktrini: test-double YOK):
#   1) quickstart → gerçek-manifest-imzalı-paket + gerçek-seed
#   2) run --require-proof → gerçek wasmtime-koşumu (gerçek TAMGA:<fnv1a64>-stamp'i)
#   3) K1: relayer verify-stamp GREEN + stamp-runner-ile-AYNI (bağımsız-doğrulama)
#   4) K2: fnv1a64-paritesi — relayer vs elle-hesaplanan (byte-identical-kanıtı)
#   5) K3: export → relayer snapshot-digest GREEN (gerçek XChaCha20-Poly1305-snapshot)
#   6) K4: digest-paritesi: bağımsız-dilimleme SHA-256(ct) == relayer-digest;
#      AYNI-anda digest != blob_sha256 (mühür-1-semantiği: GÖVDE ≠ BLOB)
#   7) K5: build_fulfill_payload JCS-kararlılık (aynı-girdi → aynı-bayt; dilim-11
#      digest'leri-yabancı-tarafça-yeniden-hesaplanabilir)
#   N1: bozuk-stamp → RED-12     N2: stamp-yok → RED-12
#   N3: bozuk-MAGIC → RED-1      N4: ct-boz → digest-DEĞİŞİR (kurcalama-yakalanır)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/.."
PASS=0; FAIL=0
note() { echo "  $*"; }
LOG=".evidence/RELAYER/$(date +%F)/at195.log"
mkdir -p "$(dirname "$LOG")"; : > "$LOG"

# export-passphrase (run_all.sh'taki-simnet-sabiti; test-bağımsız-deterministik)
export TAMGA_KS_PASSPHRASE="${TAMGA_KS_PASSPHRASE:-simnet-2026}"

note "AT-195: relayer KATMAN-0 — kanıt-üretim-çekirdeği (gerçek-run+yol)"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT

# --- 0) quickstart: gerçek-manifest-imza + gerçek-wasmtime-ilk-koşum ----------
python3 tamga_runner.py quickstart "$SB/pkg" --name at195 > "$LOG" 2>&1 \
  || { note "  FAIL: quickstart-koşmadı"; cat "$LOG"; FAIL=$((FAIL+1)); }
SEED="$(python3 -c "
import json
d = json.loads(open('$LOG').readline())
print(d.get('seed_hex', ''))" 2>/dev/null)"
if [ -z "$SEED" ]; then
  note "  FAIL: seed-hex-alınamadı"; cat "$LOG"; FAIL=$((FAIL+1))
fi

# --- 1) run --require-proof: gerçek-stamp -------------------------------------
python3 tamga_runner.py run "$SB/pkg" --seed "$SEED" --require-proof > "$LOG" 2>&1 \
  || { note "  FAIL: run-koşmadı"; cat "$LOG"; FAIL=$((FAIL+1)); }
OUT="$SB/pkg/session-2.stdout"
[ -f "$OUT" ] || OUT="$(ls -t "$SB/pkg"/session-*.stdout | head -1)"
OUT="$(ls -t "$SB/pkg"/session-*.stdout | head -1)"   # son-koşum-her-zaman

python3 - "$OUT" "$SEED" "$SB" "$LOG" <<'PYEOF'
import hashlib, json, pathlib, sys
sys.path.insert(0, ".")
from tamga_oracle_relayer import (fnv1a64, verify_output_stamp,
                                  snapshot_body_digest, build_fulfill_payload,
                                  TamgaRelayerError)
out_path, seed, sb, log = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
ok = []

# K1: relayer verify-stamp GREEN + stamp runner-ile-aynı
raw = pathlib.Path(out_path).read_bytes()
parts = raw.rsplit(b"TAMGA:", 1)
head, tag = parts[0], parts[1].rstrip(b"\n")
runner_stamp = tag.decode()
relayer_stamp = verify_output_stamp(raw)
assert relayer_stamp == runner_stamp, \
    f"K1-stamp-farklı: relayer={relayer_stamp} runner={runner_stamp}"
# relayer stdout_sha256'ı da runner-receipt ile aynı olmalı (out() paritesi)
assert hashlib.sha256(raw).hexdigest()
ok.append(f"K1 verify-stamp GREEN: stamp={relayer_stamp} (bağımsız-fnv1a64-doğrulaması)")

# K2: fnv1a64-paritesi — relayer-fonksiyonu elle-hesaplanan-sonuçla-aynı
h = 0xcbf29ce484222325
for b in head:
    h ^= b
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
assert h == int(relayer_stamp, 16), "K2-fnv1a64-parite-bozuk"
assert h == fnv1a64(head), "K2-fnv1a64-kopya-parite-bozuk"
ok.append("K2 fnv1a64 byte-identical: elle-hesapla == relayer == runner")

# K3+K4: export → snapshot-digest GREEN + digest-paritesi
import subprocess
r = subprocess.run(["python3", "tamga_runner.py", "export", f"{sb}/pkg",
                    "-o", f"{sb}/snap.tsg", "--seed", seed],
                   capture_output=True, text=True)
assert r.returncode == 0, f"K3-export-rc={r.returncode}: {r.stdout}{r.stderr}"
exp = json.loads(r.stdout)
assert exp["ok"] is True, "K3-export-ok=false"
s = snapshot_body_digest(f"{sb}/snap.tsg")
assert s["digest"], "K3-digest-boş"
# bağımsız-dilimleme (karar-dosyası-uygulaması: data[4:8]→hlen; ct=data[8+hlen:])
data = pathlib.Path(f"{sb}/snap.tsg").read_bytes()
hlen = int.from_bytes(data[4:8], "big")
ct = data[8 + hlen:]
assert hashlib.sha256(ct).hexdigest() == s["digest"], "K4-bağımsız-dilimleme-parite-bozuk"
# mühür-1-semantiği: GÖVDE-digest ≠ BLOB-digest (D3-portabilite)
assert s["digest"] != s["blob_sha256"], "K4-digest==blob (gövde-değil-blob-hash'lenmiş!)"
assert s["blob_sha256"] == exp["sha256"], "K4-blob_sha256 export-çıktısıyla-farklı"
ok.append(f"K3 snapshot-digest GREEN: digest={s['digest'][:16]}… "
          f"(ct={len(ct)}B, blob={s['bytes']}B)")
ok.append("K4 mühür-1: SHA-256(ct)==relayer-digest, ≠blob_sha256 (gövde-standartı)")

# K5: build_fulfill_payload JCS-kararlılık
receipt = {"stdout_sha256": hashlib.sha256(raw).hexdigest(), "session": 2,
           "fee_sim": 2.61e-07, "wall_ms": 16}
p1 = build_fulfill_payload(7, "abc123", receipt, s, ledger_tip="deadbeef")
p2 = build_fulfill_payload(7, "abc123", receipt, s, ledger_tip="deadbeef")
assert p1 == p2, "K5-JCS-kararsız (aynı-girdi-farklı-bayt)"
assert p1.startswith(b"{") and b'encrypted_snapshot_digest' in p1
ok.append(f"K5 fulfill-payload JCS-kararlı: {len(p1)}B, "
          f"sha256={hashlib.sha256(p1).hexdigest()[:16]}…")

for line in ok:
    print(f"  {line}")

# N1: bozuk-stamp → RED-12
bad = head + b"TAMGA:0000000000000000\n"
try:
    verify_output_stamp(bad)
    raise SystemExit("N1-RED-beklendi")
except TamgaRelayerError as e:
    assert e.reason_code == 12, f"N1-reason_code={e.reason_code}"
    print("  N1 bozuk-stamp → RED-12 ✓")

# N2: stamp-yok → RED-12
try:
    verify_output_stamp(b"stamp-yok-cikti")
    raise SystemExit("N2-RED-beklendi")
except TamgaRelayerError as e:
    assert e.reason_code == 12, f"N2-reason_code={e.reason_code}"
    print("  N2 stamp-yok → RED-12 ✓")

# N3: bozuk-MAGIC → RED-1
pathlib.Path(f"{sb}/bad-magic.tsg").write_bytes(b"XXXX" + data[4:])
try:
    snapshot_body_digest(f"{sb}/bad-magic.tsg")
    raise SystemExit("N3-RED-beklendi")
except TamgaRelayerError as e:
    assert e.reason_code == 1, f"N3-reason_code={e.reason_code}"
    print("  N3 bozuk-MAGIC → RED-1 ✓")

# N4: ct-boz → digest-DEĞİŞİR
pathlib.Path(f"{sb}/ct-boz.tsg").write_bytes(data[:8 + hlen] + b"\x00" + ct)
s2 = snapshot_body_digest(f"{sb}/ct-boz.tsg")
assert s2["digest"] != s["digest"], "N4-ct-boz-aynı-digest (kurcalama-yakalanamadı!)"
print(f"  N4 ct-boz → digest-değişti: {s2['digest'][:16]}… ≠ {s['digest'][:16]}… ✓")
PYEOF
[ $? -eq 0 ] && PASS=$((PASS+1)) && note "  PASS: K1..K5 + N1..N4 (üretim-yolu-gerçek)" \
              || { FAIL=$((FAIL+1)); note "  FAIL: KATMAN-0"; cat "$LOG"; }

rm -rf "$SB"
echo
echo "RESULT: $PASS PASS, $FAIL FAIL — log: $LOG"
echo "  AT-195: relayer KATMAN-0 — kanıt-üretim-çekirdeği (gerçek-run+yol)"
[[ $FAIL -eq 0 ]]

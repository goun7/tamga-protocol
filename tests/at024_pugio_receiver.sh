#!/usr/bin/env bash
# AT-024 - PUGIO köprüsü alıcısı: external_anchor kanıt-bundle doğrulaması (K0 §5 / RFC-009 receiver-tarafı)
set -u
PASS=0; FAIL=0; LOG="${TAMGA_EVIDENCE_DIR:-.evidence/AT-024/$(date +%F)}/at024.log"
mkdir -p "$(dirname "$LOG")"
ok() { if [ "$1" -eq 0 ]; then PASS=$((PASS+1)); echo "  PASS: $2" | tee -a "$LOG"; else FAIL=$((FAIL+1)); echo "  FAIL: $2" | tee -a "$LOG"; fi; }
cd "$(cd "$(dirname "$0")/.." && pwd)"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# 1) selftest: temiz-çıpa PASS + tek-alan bozulma RED (fail-loud doktrini)
python3 tamga_pugio_receiver.py --selftest > "$LOG.st" 2>&1
ok $? "selftest: temiz→PASS, bozuk→RED (fail-loud)"

# 2) gerçek-çıpa-akışı: sentetik-zarf üret → doğrula → SAĞLAM
python3 - > "$W/mint.py.out" 2>&1 <<PYEOF
import hashlib, json, pathlib
head = hashlib.sha256(b"at024-head").hexdigest()
merkle = hashlib.sha256(b"at024-merkle").hexdigest()
a = {"type": "external_anchor", "bridge_version": 1, "source": "pugio", "agent": "at024",
     "anchor_id": hashlib.sha256(f"{head}|{merkle}|7".encode()).hexdigest()[:32],
     "head": head, "merkle_root": merkle, "event_count": 7}
pathlib.Path("$W/temiz.jsonl").write_text(json.dumps(a, sort_keys=True, separators=(",", ":")) + "\n")
PYEOF
python3 tamga_pugio_receiver.py "$W/temiz.jsonl" > "$W/temiz.out" 2>&1
[ $? -eq 0 ] && grep -q "SAĞLAM" "$W/temiz.out"
ok $? "temiz-zarf: doğrulama-PASS + SAĞLAM"

# 3) bozuk-çıpa (head-değişikliği): bağı kopmalı → RED exit-1
python3 - <<PYEOF
import pathlib, json
raw = pathlib.Path("$W/temiz.jsonl").read_text().strip()
a = json.loads(raw); a["head"] = "f" * 64
pathlib.Path("$W/bozuk.jsonl").write_text(json.dumps(a, sort_keys=True, separators=(",", ":")) + "\n")
PYEOF
python3 tamga_pugio_receiver.py "$W/bozuk.jsonl" > "$W/bozuk.out" 2>&1
[ $? -ne 0 ] && grep -q "kopuk" "$W/bozuk.out"
ok $? "head-değişikliği: anchor_id bağı kopuk → RED"

# 4) zarf-tip/zarar-kaynağı RED (type != external_anchor)
python3 - <<PYEOF
import json, pathlib
pathlib.Path("$W/yanlis-tip.jsonl").write_text(json.dumps({"type": "internal_note", "source": "pugio"}) + "\n")
PYEOF
python3 tamga_pugio_receiver.py "$W/yanlis-tip.jsonl" > "$W/yt.out" 2>&1
[ $? -ne 0 ] && grep -q "zarf-tipi" "$W/yt.out"
ok $? "yanlış-zarf-tipi → RED"

# 4b) kaynak-çift-ad-okuma sözleşmesi (K0 §5 read-compat, 2026-09-13 SESTER-göçü):
# donuk-birincil "sikke" KABUL + tarihsel "pugio" KABUL + bilinmeyen-kaynak RED.
# Bu kontrol bilinçli-genişletme-sözleşmesinin yürürlük noktasıdır: kabul-listesi
# burada değiştirilmeden verify-anchor kaynağı gevşetilemez (fail-loud dilation).
python3 - <<PYEOF
import hashlib, json, pathlib
head = hashlib.sha256(b"h1").hexdigest(); merkle = hashlib.sha256(b"m1").hexdigest()
def mk(src):
    a = {"type": "external_anchor", "bridge_version": 1, "source": src,
         "anchor_id": hashlib.sha256(f"{head}|{merkle}|1".encode()).hexdigest()[:32],
         "head": head, "merkle_root": merkle, "event_count": 1}
    return json.dumps(a, sort_keys=True, separators=(",", ":"))
pathlib.Path("$W/sikke.jsonl").write_text(mk("sikke") + "\n")   # donuk-birincil: KABUL
pathlib.Path("$W/taninmayan.jsonl").write_text(mk("bilinmeyen-kaynak-63") + "\n")  # RED
PYEOF
python3 tamga_pugio_receiver.py "$W/sikke.jsonl" > "$W/sk.out" 2>&1
[ $? -eq 0 ] && grep -q "SAĞLAM" "$W/sk.out"
ok $? "donuk-birincil-kaynak (sikke) → KABUL (K0 §5 read-compat)"
python3 tamga_pugio_receiver.py "$W/taninmayan.jsonl" > "$W/tk.out" 2>&1
[ $? -ne 0 ] && grep -q "kaynak" "$W/tk.out"
ok $? "bilinmeyen-kaynak → RED (kaynak-kapısı-kapalı)"

# 4c) SESTER-üretim-şeması-çaprazı (canlı-çapraz-kanıt 2026-09-13'ün gömülü-hali):
# gerçek producer (63-Sester/sester/bridges.py tamga_anchor_json) satır-şemasını
# birebir taklit eden bir zarf — source=sikke + pugio_bundle_version alanı dahil —
# KABUL görmeli. Ağ-bağımlılık YOK: şema 2026-09-13'te canlı-doğrulandı
# (SESTER-producer'dan-üretilen-satır bu-alıcıda-SAĞLAM); bu-vektör o-tarifin
# deterministik-izi.
python3 - <<PYEOF
import hashlib, json, pathlib
head = hashlib.sha256(b"h1").hexdigest(); merkle = hashlib.sha256(b"m1").hexdigest()
# SESTER üretim-tarifi (bridges.py tamga_anchor): anchor_id = SHA256(head|merkle|count)[:32]
a = {"type": "external_anchor", "bridge_version": 1, "source": "sikke",
     "pugio_bundle_version": "K0/1", "agent": "at024-sester-capraz",
     "anchor_id": hashlib.sha256(f"{head}|{merkle}|3".encode()).hexdigest()[:32],
     "head": head, "merkle_root": merkle, "event_count": 3}
pathlib.Path("$W/sester-sema.jsonl").write_text(
    json.dumps(a, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
PYEOF
python3 tamga_pugio_receiver.py "$W/sester-sema.jsonl" > "$W/ss.out" 2>&1
[ $? -eq 0 ] && grep -q "SAĞLAM" "$W/ss.out"
ok $? "SESTER-üretim-şeması-çaprazı (sikke+pugio_bundle_version) → KABUL"

# 5) tek-satırlık-dosyada-tek-RED: süreç-exit-1 (fail-loud, sessiz-geçiş yok)
printf '%s\n' '{"type": "external_anchor", "source": "pugio", "bridge_version": 1, "anchor_id": "x", "head": "a", "merkle_root": "b", "event_count": 1}' '{"type": "external_anchor", "source": "pugio", "bridge_version": 1, "anchor_id": "y", "head": "c", "merkle_root": "d", "event_count": 2}' > "$W/karisik.jsonl"
python3 tamga_pugio_receiver.py "$W/karisik.jsonl" > "$W/kx.out" 2>&1
[ $? -ne 0 ]
ok $? "tek-RED-satırı → tüm-dosya-RED (fail-loud)"

# 6) bridge_version-2 (gelecek-sürüm) → RED: sürüm-kapısı-kapalı
python3 - <<PYEOF
import hashlib, json, pathlib
head = hashlib.sha256(b"v2").hexdigest(); merkle = hashlib.sha256(b"m2").hexdigest()
a = {"type": "external_anchor", "bridge_version": 2, "source": "pugio",
     "anchor_id": hashlib.sha256(f"{head}|{merkle}|1".encode()).hexdigest()[:32],
     "head": head, "merkle_root": merkle, "event_count": 1}
pathlib.Path("$W/v2.jsonl").write_text(json.dumps(a, sort_keys=True, separators=(",", ":")) + "\n")
PYEOF
python3 tamga_pugio_receiver.py "$W/v2.jsonl" > "$W/v2.out" 2>&1
[ $? -ne 0 ] && grep -q "bridge_version" "$W/v2.out"
ok $? "bilinmeyen-bridge_version → RED (sürüm-kapısı)"

echo "RESULT: $PASS PASS, $FAIL FAIL - log: $LOG"
[ "$FAIL" -eq 0 ]

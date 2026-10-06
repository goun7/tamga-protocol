"""Çekirdek kanıt-doğrulama unit testleri — TamgaProtocol mesh'inin KALBİ.

Kapsanan en-kritik 6 fonksiyon (pytest'te daha önce hiç kaplanmamış; yalnızca
 .sh entegrasyon testlerinde dolaylı-yol):

  zincir-hash        IVerifier.verify_charge      tamga_verifier.py:210
  kanonikleştirme    IVerifier.verify_payload     tamga_verifier.py:191
  snapshot mührü     IVerifier.verify_snapshot    tamga_verifier.py:168
  stamp mührü        IVerifier.verify_stamp       tamga_verifier.py:150
  üst-seviye         IVerifier.verify_bundle      tamga_verifier.py:305
  oracle/epoch       verify_inclusion             tamga_epoch_verify.py:48

  + yardımcı-çekirdek: fnv1a64 (tamga_verifier.py:339 — mühür-2 hash'i)
  + receipt kanoniklik: tamga_cr_verify (tensor_digest / named_digest / digest_bytes)

Disiplin (görev-kuralları):
  • SADECE YENİ DOSYA — mevcut test/kod DEĞİŞTİRİLMEDİ.
  • MOCK YOK — tüm fixture'lar gerçek crypto ile üretilir (hashlib + tamga_keccak
    + tamga_canon.jcs). Dış ağ/RPC çağrısı içermez.
  • Bağımsız-JCS paritesi: payload baytları tamga_canon.jcs ile üretilip
    tamga_verifier'ın KENDİ jcs kopyasıyla doğrulanır (iki kasıtlı-kopya,
    RFC 8785 byte-paritesi — vauban_conformance'ın makine-iddiasının unittest'deki
    hali).
  • Gerçek zincir-verisi: unpump-bridge/ledger.jsonl (repo içindeki canlı
    defter) verify_charge ile baştan sona yürünür.
"""

import base64
import hashlib
import json
import pathlib

import pytest

import tamga_canon
import tamga_keccak
from tamga_cr_verify import digest_bytes, named_digest, tensor_digest
from tamga_epoch_verify import verify_inclusion
from tamga_verifier import FNV_OFFSET, FNV_PRIME, GENESIS, IVerifier, fnv1a64

ROOT = pathlib.Path(__file__).resolve().parent.parent
REAL_LEDGER = ROOT / "unpump-bridge" / "ledger.jsonl"


# --- fixture üreticileri (gerçek crypto, mock YOK) -----------------------------

def _merkle_root(leaves: list) -> bytes:
    """OpenZeppelin tarifi sorted-pairs yürüyüşü (epoch_verify ile aynı kural)."""
    layer = list(leaves)
    while len(layer) > 1:
        nxt = []
        for i in range(0, len(layer), 2):
            lo, hi = sorted([layer[i], layer[i + 1]])
            nxt.append(tamga_keccak.keccak256(lo + hi))
        layer = nxt
    return layer[0]


def _merkle_proof(leaves: list, idx: int) -> list[str]:
    layer, i, proof = list(leaves), idx, []
    while len(layer) > 1:
        proof.append("0x" + layer[i ^ 1].hex())
        nxt = []
        for k in range(0, len(layer), 2):
            lo, hi = sorted([layer[k], layer[k + 1]])
            nxt.append(tamga_keccak.keccak256(lo + hi))
        layer, i = nxt, i // 2
    return proof


def make_snapshot(ct: bytes = b"encrypted-govde", extra: dict | None = None):
    """tamga-snapshot/1: b'TSG1' + hlen(big) + header-JCS + ct → (data, sha256(ct))."""
    header = {"format": "tamga-snapshot/1", "cipher": "XChaCha20-Poly1305"}
    if extra:
        header.update(extra)
    hjcs = tamga_canon.jcs(header)
    data = b"TSG1" + len(hjcs).to_bytes(4, "big") + hjcs + ct
    return data, hashlib.sha256(ct).hexdigest()


def make_stdout(head: bytes = b"agent: merhaba\nstdout-satir\n") -> bytes:
    """Mühür-2: son satır 'TAMGA:<fnv1a64(head):016x>'."""
    return head + b"TAMGA:" + f"{fnv1a64(head):016x}".encode("ascii")


def make_payload(*, snapshot_digest: str, stdout_sha: str, input_sha: str | None = "e" * 64):
    """TAMGA_FULFILL/1 payload'u — baytlar BAĞIMSIZ tamga_canon.jcs kopyasıyla üretilir."""
    obj = {"kind": "TAMGA_FULFILL/1", "request_id": 42, "wasi_module_hash": "a" * 64,
           "encrypted_snapshot_digest": snapshot_digest, "stdout_sha256": stdout_sha,
           "ledger_tip": "d" * 64, "fee_sim": 0.00000128, "wall_ms": 135}
    if input_sha is not None:
        obj["input_sha256"] = input_sha
    return obj, tamga_canon.jcs(obj)


def make_charge(prev: str = GENESIS, seq: int = 1, stdout_sha: str = "c" * 64, **over):
    """JSONL charge kaydı; h = sha256(prev + jcs(h-siz)) — relayer kuralı."""
    rec = {"op": "charge", "pkg": "demo", "engine": "wasmtime-v48.0.1",
           "cpu_saat": 0.000005, "fee_sim": 0.00000128, "io_mb": 0.0001,
           "ram_gb_sn": 0.0023, "wall_ms": 135, "stdout_sha256": stdout_sha,
           "request_id": "1", "prev": prev, "seq": seq,
           "ts": "2026-10-06T19:00:00+0300"}
    rec.update(over)
    no_h = {k: v for k, v in rec.items() if k != "h"}
    preimage = (rec["prev"] + tamga_canon.jcs(no_h).decode("utf-8")).encode("utf-8")
    rec["h"] = hashlib.sha256(preimage).hexdigest()
    return rec


def make_bundle():
    """Relayer run-request çıktısından üretilen tam kanıt-paketi (6 mühür)."""
    snap, snap_dig = make_snapshot()
    stdout = make_stdout()
    stdout_sha = hashlib.sha256(stdout).hexdigest()
    _, payload = make_payload(
        snapshot_digest=snap_dig,
        stdout_sha=stdout_sha,
        input_sha=hashlib.sha256(b"istek-girdisi").hexdigest())
    charge = make_charge(prev=GENESIS, seq=1, stdout_sha=stdout_sha)
    return {"stdout_b64": base64.b64encode(stdout).decode(),
            "snapshot_b64": base64.b64encode(snap).decode(),
            "payload": payload.decode("utf-8"), "charge": charge, "prev_h": GENESIS,
            "delivery_hash": tamga_keccak.keccak256(payload).hex(),
            "input_b64": base64.b64encode(b"istek-girdisi").decode()}


# =====================================================================
# MÜHÜR-2 HASH: fnv1a64 — relayer:122 / tamga_runner:30 / agent Rust ile birebir
# =====================================================================

def test_fnv1a64_empty_input_is_offset_basis():
    assert fnv1a64(b"") == FNV_OFFSET == 0xcbf29ce484222325


def test_fnv1a64_single_byte_matches_known_vector():
    # FNV-1a 64 bilinen-yanıtı: hash("a") = 0xaf63dc4c8601ec8c
    assert fnv1a64(b"a") == 0xAF63DC4C8601EC8C


def test_fnv1a64_matches_spec_reference_loop():
    # Yayınlanmış FNV-1a tanımıyla bağımsız yeniden-hesap
    data = b"The quick brown fox"
    h = FNV_OFFSET
    for byte in data:
        h ^= byte
        h = (h * FNV_PRIME) & 0xFFFFFFFFFFFFFFFF
    assert fnv1a64(data) == h


def test_fnv1a64_is_order_sensitive():
    assert fnv1a64(b"ab") != fnv1a64(b"ba")


def test_fnv1a64_is_stable_and_distinct_over_sequences():
    a, b = b"jcs-parite", b"jcs-paritf"
    assert fnv1a64(a) == fnv1a64(a)
    assert fnv1a64(a) != fnv1a64(b)


# =====================================================================
# MÜHÜR-2: verify_stamp — fnv1a64 stamp satırı
# =====================================================================

def test_verify_stamp_valid_green():
    raw = make_stdout(b"agent: cikti\n")
    r = IVerifier.verify_stamp(raw, None)
    assert r["ok"] is True
    assert r["stamp"] == f"{fnv1a64(b'agent: cikti\n'):016x}"


def test_verify_stamp_honours_expected_hex():
    stamp = f"{fnv1a64(b'head\n'):016x}"
    raw = b"head\nTAMGA:" + stamp.encode()
    assert IVerifier.verify_stamp(raw, stamp)["ok"] is True


def test_verify_stamp_rejects_mismatching_expected_hex():
    stamp = f"{fnv1a64(b'head\n'):016x}"
    raw = b"head\nTAMGA:" + stamp.encode()
    r = IVerifier.verify_stamp(raw, "0" * 16)
    assert r["ok"] is False and r["reason"] == "stamp-expected-mismatch"


def test_verify_stamp_detects_tampered_head():
    good = make_stdout(b"dogru cikti\n")
    tag = good.rsplit(b"TAMGA:", 1)[1]
    r = IVerifier.verify_stamp(b"bozuk cikti\n" + b"TAMGA:" + tag, None)
    assert r["ok"] is False and r["reason"].startswith("stamp-mismatch")


def test_verify_stamp_missing_marker_is_red():
    r = IVerifier.verify_stamp("çıktıda-stamp-yok\n".encode("utf-8"), None)
    assert r["ok"] is False and r["reason"].startswith("stamp-yok")


def test_verify_stamp_rejects_short_tag():
    r = IVerifier.verify_stamp(b"x\nTAMGA:" + b"00" * 7, None)
    assert r["ok"] is False and r["reason"].startswith("stamp-format")


def test_verify_stamp_rejects_non_hex_tag():
    r = IVerifier.verify_stamp(b"x\nTAMGA:" + b"z" * 16, None)
    assert r["ok"] is False and r["reason"].startswith("stamp-format")


def test_verify_stamp_splits_only_on_last_marker():
    # ortaya gömülü 'TAMGA:' gövde-parçasıdır; yalnızca sonuncusu mühürdür
    head = "önek TAMGA: gövde\n".encode("utf-8")   # gömülü 'TAMGA:' gövde-parçasıdır
    raw = head + b"TAMGA:" + f"{fnv1a64(head):016x}".encode()
    assert IVerifier.verify_stamp(raw, None)["ok"] is True


# =====================================================================
# MÜHÜR-1: verify_snapshot — tamga-snapshot/1, SHA-256(ct)
# =====================================================================

def test_verify_snapshot_valid_green():
    data, dig = make_snapshot()
    r = IVerifier.verify_snapshot(data, dig)
    assert r["ok"] is True
    assert r["digest"] == dig
    assert r["ct_len"] == len(b"encrypted-govde")


def test_verify_snapshot_rejects_bad_magic():
    data, dig = make_snapshot()
    r = IVerifier.verify_snapshot(b"XXXX" + data[4:], dig)
    assert r["ok"] is False and r["reason"].startswith("snapshot-magic")


def test_verify_snapshot_rejects_invalid_header_length():
    data, dig = make_snapshot()
    bad = b"TSG1" + (10 ** 6).to_bytes(4, "big") + data[8:]
    r = IVerifier.verify_snapshot(bad, dig)
    assert r["ok"] is False and "uzunluğu geçersiz" in r["reason"]


def test_verify_snapshot_rejects_non_json_header():
    bad = b"TSG1" + len(b"{oops}").to_bytes(4, "big") + b"{oops}" + b"ct"
    r = IVerifier.verify_snapshot(bad, hashlib.sha256(b"ct").hexdigest())
    assert r["ok"] is False and "header-JSON-değil" in r["reason"]


def test_verify_snapshot_detects_tampered_ciphertext():
    data, dig = make_snapshot()
    bad = bytearray(data)
    bad[-1] ^= 0x01
    r = IVerifier.verify_snapshot(bytes(bad), dig)
    assert r["ok"] is False and r["reason"].startswith("digest-mismatch")


def test_verify_snapshot_digest_binds_only_to_ciphertext():
    # Aynı ct + farklı header → aynı digest (mühür gövdeye bağlıdır)
    d1, dig1 = make_snapshot(ct=b"govde")
    d2, dig2 = make_snapshot(ct=b"govde", extra={"nonce": "farkli-header"})
    assert dig1 == dig2
    assert len(d1) != len(d2)                      # header gerçekten farklı
    assert IVerifier.verify_snapshot(d1, dig1)["ok"] is True
    assert IVerifier.verify_snapshot(d2, dig2)["ok"] is True


# =====================================================================
# KANONİKLEŞTİRME: verify_payload — RFC 8785 JCS byte-paritesi
# =====================================================================

def test_verify_payload_valid_green_via_independent_jcs_copy():
    obj, payload = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    r = IVerifier.verify_payload(payload)
    assert r["ok"] is True
    assert r["payload"] == obj


def test_verify_payload_rejects_non_canonical_byte_order():
    # GEÇERLİ JSON ama anahtar-sırası kanonik değil → yeniden-serileştir farklı bayt
    obj, _ = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    alt = json.dumps({"wall_ms": 135, "fee_sim": 0.00000128, "kind": obj["kind"],
                      "request_id": obj["request_id"],
                      "wasi_module_hash": obj["wasi_module_hash"],
                      "encrypted_snapshot_digest": obj["encrypted_snapshot_digest"],
                      "stdout_sha256": obj["stdout_sha256"],
                      "ledger_tip": obj["ledger_tip"],
                      "input_sha256": obj["input_sha256"]}, separators=(",", ":"))
    assert json.loads(alt) == obj                      # aynı JSON DEĞERİ
    r = IVerifier.verify_payload(alt.encode())
    assert r["ok"] is False and "jcs-parite" in r["reason"]


def test_verify_payload_rejects_whitespace_in_canonical_bytes():
    _, payload = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    padded = payload.replace(b'":"', b'" : "')        # geçerli JSON, kanonik-değil
    assert json.loads(padded)                          # hala parse-edilebilir
    assert IVerifier.verify_payload(padded)["ok"] is False


def test_verify_payload_rejects_wrong_kind():
    obj, _ = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    obj["kind"] = "TAMGA_FULFILL/2"
    r = IVerifier.verify_payload(tamga_canon.jcs(obj))
    assert r["ok"] is False and r["reason"].startswith("payload-kind")


def test_verify_payload_rejects_missing_required_field():
    obj, _ = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    del obj["ledger_tip"]
    r = IVerifier.verify_payload(tamga_canon.jcs(obj))
    assert r["ok"] is False and "eksik-alan" in r["reason"]
    assert "ledger_tip" in r["reason"]


def test_verify_payload_rejects_null_required_field():
    obj, _ = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    obj["request_id"] = None
    r = IVerifier.verify_payload(tamga_canon.jcs(obj))
    assert r["ok"] is False and "request_id" in r["reason"]


def test_verify_payload_rejects_invalid_json():
    r = IVerifier.verify_payload(b"{bu json degil}")
    assert r["ok"] is False and r["reason"].startswith("payload-JSON-değil")


def test_verify_payload_number_canonicalization_is_ecmascript():
    # 1.0 → "1" (Python "1.0" der); byte-paritesi bu farkı yakalar
    obj, _ = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    obj["wall_ms"] = 135.0
    assert IVerifier.verify_payload(tamga_canon.jcs(obj))["ok"] is True
    pythonish = json.dumps(obj, separators=(",", ":")).encode()
    assert IVerifier.verify_payload(pythonish)["ok"] is False


# =====================================================================
# ZİNCİR-HASH: verify_charge — ledger hash-chain üyeliği (mesh'in kalbi)
# =====================================================================

def test_verify_charge_valid_green():
    rec = make_charge()
    r = IVerifier.verify_charge(rec, GENESIS, rec["h"])
    assert r["ok"] is True
    assert r["h"] == rec["h"]


def test_verify_charge_formula_matches_relayer_rule():
    rec = make_charge()
    no_h = {k: v for k, v in rec.items() if k != "h"}
    # bağımsız JCS kopyasıyla yeniden-hesap (relayer: charge["prev"] + jcs(h-siz))
    want = hashlib.sha256(
        (rec["prev"] + tamga_canon.jcs(no_h).decode("utf-8")).encode("utf-8")
    ).hexdigest()
    assert IVerifier.verify_charge(rec, GENESIS, want)["ok"] is True


def test_verify_charge_is_invariant_under_key_insertion_order():
    a = make_charge()
    b = dict(sorted(json.loads(json.dumps(a)).items(), reverse=True))
    assert a == b                                     # dict eşitlik sıraya bakmaz
    assert IVerifier.verify_charge(b, GENESIS, a["h"])["ok"] is True


def test_verify_charge_rejects_prev_mismatch():
    rec = make_charge()
    r = IVerifier.verify_charge(rec, "1" * 64, rec["h"])
    assert r["ok"] is False and r["reason"] == "charge-prev-uyumsuz"


def test_verify_charge_detects_tampered_field():
    rec = make_charge()
    bad = dict(rec, wall_ms=99999)
    r = IVerifier.verify_charge(bad, GENESIS, rec["h"])
    assert r["ok"] is False and "üyelik-mismatch" in r["reason"]


def test_verify_charge_detects_wrong_expected_h():
    rec = make_charge()
    r = IVerifier.verify_charge(rec, GENESIS, "0" * 64)
    assert r["ok"] is False and "üyelik-mismatch" in r["reason"]


def test_verify_charge_chain_of_three_links_cascade():
    c1 = make_charge(prev=GENESIS, seq=1)
    c2 = make_charge(prev=c1["h"], seq=2)
    c3 = make_charge(prev=c2["h"], seq=3)
    for rec, prev in ((c1, GENESIS), (c2, c1["h"]), (c3, c2["h"])):
        assert IVerifier.verify_charge(rec, prev, rec["h"])["ok"] is True
    # ara-halka kırılınca c3'ün prev-uyumu da bozulur (zincir kaskad-kırılır)
    c2b = dict(c2, fee_sim=99.0)
    assert IVerifier.verify_charge(c2b, c1["h"], c2["h"])["ok"] is False
    assert IVerifier.verify_charge(c3, c1["h"], c3["h"])["ok"] is False


@pytest.mark.skipif(not REAL_LEDGER.exists(), reason="repo-local ledger yok")
def test_verify_charge_walks_real_repo_ledger_end_to_end():
    """unpump-bridge/ledger.jsonl: canlı defterin TÜM halkaları baştan-sona."""
    prev, seen = GENESIS, 0
    for line in REAL_LEDGER.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        r = IVerifier.verify_charge(rec, prev, rec["h"])
        assert r["ok"] is True, f"ledger kirildi seq={rec.get('seq')}: {r['reason']}"
        prev, seen = rec["h"], seen + 1
    assert seen >= 3, "beklenen-en-az-3-üye canlı-defter"


@pytest.mark.skipif(not REAL_LEDGER.exists(), reason="repo-local ledger yok")
def test_verify_charge_real_ledger_rejects_wrong_expected_h():
    """Gerçek zincirde beklenen-h halkanın kendi h'si değilse üyelik RED."""
    recs = [json.loads(l) for l in
            REAL_LEDGER.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(recs) >= 2
    assert IVerifier.verify_charge(recs[1], recs[1]["prev"], recs[0]["h"])["ok"] is False


# =====================================================================
# DELIVERY + INPUT mühürleri
# =====================================================================

def test_verify_delivery_valid_green():
    _, payload = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    r = IVerifier.verify_delivery(payload, tamga_keccak.keccak256(payload).hex())
    assert r["ok"] is True and r["digest"] == tamga_keccak.keccak256(payload).hex()


def test_verify_delivery_is_keccak_not_fips_sha3():
    """Legacy-padding domain (0x01) — hashlib.sha3_256 UYUŞMAZ (AT-201 parite)."""
    data = b"outputData-bytes"
    r = IVerifier.verify_delivery(data, tamga_keccak.keccak256(data).hex())
    assert r["ok"] is True
    assert tamga_keccak.keccak256(data).hex() != hashlib.sha3_256(data).hexdigest()


def test_verify_delivery_detects_tamper():
    _, payload = make_payload(snapshot_digest="b" * 64, stdout_sha="c" * 64)
    r = IVerifier.verify_delivery(payload + b"x", tamga_keccak.keccak256(payload).hex())
    assert r["ok"] is False and r["reason"].startswith("delivery-mismatch")


def test_verify_input_valid_green():
    r = IVerifier.verify_input(b"girdi", hashlib.sha256(b"girdi").hexdigest())
    assert r["ok"] is True and r["sha256"] == hashlib.sha256(b"girdi").hexdigest()


def test_verify_input_detects_tamper():
    r = IVerifier.verify_input(b"girdi", hashlib.sha256(b"gidri").hexdigest())
    assert r["ok"] is False and r["reason"].startswith("input-mismatch")


# =====================================================================
# ÜST-SEVİYE: verify_bundle — 6 mühürün hep birlikte doğrulanması
# =====================================================================

def test_verify_bundle_all_six_checks_green():
    r = IVerifier.verify_bundle(make_bundle())
    assert r["ok"] is True
    assert r["checks"] == 6
    assert r["verified"] == ["payload", "stamp", "snapshot", "charge", "delivery", "input"]


def _bundle_tamper(fn):
    b = make_bundle()
    fn(b)
    return IVerifier.verify_bundle(b)


def test_verify_bundle_tampered_stdout_is_red():
    def m(b):
        raw = bytearray(base64.b64decode(b["stdout_b64"]))
        raw[0] ^= 0x01
        b["stdout_b64"] = base64.b64encode(bytes(raw)).decode()
    r = _bundle_tamper(m)
    assert r["ok"] is False and r["reason"].startswith("stamp:")


def test_verify_bundle_tampered_snapshot_is_red():
    def m(b):
        raw = bytearray(base64.b64decode(b["snapshot_b64"]))
        raw[-1] ^= 0x01
        b["snapshot_b64"] = base64.b64encode(bytes(raw)).decode()
    r = _bundle_tamper(m)
    assert r["ok"] is False and r["reason"].startswith("snapshot:")


def test_verify_bundle_tampered_payload_is_red():
    def m(b):
        obj = json.loads(b["payload"])
        b["payload"] = json.dumps({"wall_ms": 135, "kind": obj["kind"],
                                   "request_id": obj["request_id"],
                                   "wasi_module_hash": obj["wasi_module_hash"],
                                   "encrypted_snapshot_digest": obj["encrypted_snapshot_digest"],
                                   "stdout_sha256": obj["stdout_sha256"],
                                   "ledger_tip": obj["ledger_tip"],
                                   "input_sha256": obj["input_sha256"],
                                   "fee_sim": obj["fee_sim"]}, separators=(",", ":"))
    r = _bundle_tamper(m)
    assert r["ok"] is False and r["reason"].startswith("payload:")


def test_verify_bundle_tampered_charge_is_red():
    def m(b):
        b["charge"] = dict(b["charge"], h="0" * 64)
    r = _bundle_tamper(m)
    assert r["ok"] is False and r["reason"].startswith("charge:")


def test_verify_bundle_tampered_delivery_is_red():
    def m(b):
        b["delivery_hash"] = "f" * 64
    r = _bundle_tamper(m)
    assert r["ok"] is False and r["reason"].startswith("delivery:")


def test_verify_bundle_tampered_input_is_red():
    def m(b):
        b["input_b64"] = base64.b64encode(b"baska-girdi").decode()
    r = _bundle_tamper(m)
    assert r["ok"] is False and r["reason"].startswith("input:")


def test_verify_bundle_without_input_is_five_checks():
    b = make_bundle()
    del b["input_b64"]
    r = IVerifier.verify_bundle(b)
    assert r["ok"] is True and r["checks"] == 5
    assert "input" not in r["verified"]


def test_verify_bundle_charge_prev_h_defaults_to_genesis():
    b = make_bundle()
    del b["prev_h"]
    assert IVerifier.verify_bundle(b)["ok"] is True


def test_verify_bundle_rejects_wrong_prev_h():
    b = make_bundle()
    b["prev_h"] = "1" * 64
    r = IVerifier.verify_bundle(b)
    assert r["ok"] is False and r["reason"].startswith("charge:")


def test_verify_bundle_check_order_runs_payload_first():
    """Payload en-önce doğrulanır; kırık payload diğer mühürleri açmaz (short-circuit)."""
    b = make_bundle()
    b["payload"] = "{bu-geçersiz-json"
    r = IVerifier.verify_bundle(b)
    assert r["ok"] is False
    assert r["checks"] == 1 and r["verified"] == ["payload"]


# =====================================================================
# ORACLE / EPOCH: verify_inclusion — sorted-pairs merkle dahil-etme
# =====================================================================

def _facts(n=4):
    return [bytes([i + 1]) * 32 for i in range(n)]


def _leaves(facts):
    return [tamga_keccak.keccak256(tamga_keccak.keccak256(f)) for f in facts]


def test_inclusion_single_element_tree_matches_double_keccak_leaf():
    leaf = tamga_keccak.keccak256(tamga_keccak.keccak256(bytes(32)))
    ok, computed = verify_inclusion("0x" + bytes(32).hex(), [], "0x" + leaf.hex())
    assert ok is True
    assert computed == "0x" + leaf.hex()


def test_inclusion_four_leaf_tree_all_members_green():
    facts = _facts(4)
    leaves = _leaves(facts)
    root = _merkle_root(leaves)
    for i, fact in enumerate(facts):
        ok, _ = verify_inclusion("0x" + fact.hex(), _merkle_proof(leaves, i), "0x" + root.hex())
        assert ok is True, f"yaprak-{i} dahil-edilemedi"


def test_inclusion_eight_leaf_tree_all_members_green():
    facts = _facts(8)
    leaves = _leaves(facts)
    root = _merkle_root(leaves)
    for i, fact in enumerate(facts):
        ok, _ = verify_inclusion("0x" + fact.hex(), _merkle_proof(leaves, i), "0x" + root.hex())
        assert ok is True


def test_inclusion_wrong_fact_with_foreign_proof_is_red():
    facts = _facts(4)
    leaves = _leaves(facts)
    root = _merkle_root(leaves)
    ok, _ = verify_inclusion("0x" + facts[3].hex(), _merkle_proof(leaves, 0), "0x" + root.hex())
    assert ok is False


def test_inclusion_wrong_root_is_red():
    facts = _facts(4)
    leaves = _leaves(facts)
    ok, _ = verify_inclusion("0x" + facts[0].hex(), _merkle_proof(leaves, 0), "0x" + "a" * 64)
    assert ok is False


def test_inclusion_sorted_pairs_is_side_invariant():
    """sorted-pairs: kök kardeş-sırasından bağımsız — her iki yaprak da aynı kökü verir."""
    leaves = _leaves(_facts(2))
    root = _merkle_root(leaves)
    for i in (0, 1):
        ok, computed = verify_inclusion("0x" + bytes([i + 1] * 32).hex(),
                                        _merkle_proof(leaves, i), "0x" + root.hex())
        assert ok is True and computed == "0x" + root.hex()


def test_inclusion_rejects_corrupt_hex_sibling():
    facts = _facts(2)
    leaves = _leaves(facts)
    ok, msg = verify_inclusion("0x" + facts[0].hex(), ["zzzz"], "0x" + _merkle_root(leaves).hex())
    assert ok is False and "hex-bozuk" in msg


def test_inclusion_rejects_short_sibling():
    facts = _facts(2)
    leaves = _leaves(facts)
    ok, msg = verify_inclusion("0x" + facts[0].hex(), ["0x" + "ab"], "0x" + _merkle_root(leaves).hex())
    assert ok is False and "32-bayt" in msg


def test_inclusion_rejects_wrong_length_fact_hash():
    with pytest.raises(ValueError):
        verify_inclusion("0x" + "ab", [], "0x" + "a" * 64)


def test_inclusion_accepts_bare_hex_without_0x_prefix():
    leaf = tamga_keccak.keccak256(tamga_keccak.keccak256(bytes(32)))
    ok, computed = verify_inclusion(bytes(32).hex(), [], "0x" + leaf.hex())
    assert ok is True and computed == "0x" + leaf.hex()


# =====================================================================
# RECEIPT: tamga_cr_verify kanoniklik (CR v0.1)
# =====================================================================

def test_digest_bytes_matches_sha256_with_scheme_prefix():
    assert digest_bytes(b"x") == "sha256:" + hashlib.sha256(b"x").hexdigest()


def test_tensor_digest_is_deterministic_and_shape_sensitive():
    a = tensor_digest("f8", [2, 3], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
    b = tensor_digest("f8", [2, 3], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
    assert a == b
    assert tensor_digest("f8", [3, 2], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]) != a
    assert tensor_digest("i4", [2, 3], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]) != a


def test_tensor_digest_binds_dtype_and_values():
    base = tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
    assert tensor_digest("i1", [4], "<4b", [0, 1, 2, 3]) != base
    assert tensor_digest("i4", [4], "<4i", [0, 1, 2, 4]) != base


def test_named_digest_is_order_independent_cr32():
    """CR §3.2: isim-sırasından bağımsız — sorted-by-codepoint."""
    f64 = tensor_digest("f8", [2, 3], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
    i32 = tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
    a = named_digest({"w2": i32, "w1": f64})
    b = named_digest({"w1": f64, "w2": i32})
    c = named_digest(dict(sorted({"w2": i32, "w1": f64}.items())))
    assert a == b == c


def test_named_digest_is_content_sensitive():
    f64 = tensor_digest("f8", [2, 3], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0])
    i32 = tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
    other = tensor_digest("i4", [4], "<4i", [0, 1, 2, 4])
    assert named_digest({"w2": i32, "w1": f64}) != named_digest({"w2": other, "w1": f64})
    assert named_digest({"w3": i32, "w1": f64}) != named_digest({"w2": i32, "w1": f64})


def test_named_digest_entry_shape_is_canonical_name_digest_pair():
    """Her eleman canonical({"name","digest"}) — jcs ön-görüntüsüyle yeniden-hesap."""
    i32 = tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
    h = hashlib.sha256()
    h.update(tamga_canon.jcs({"name": "w1", "digest": i32}))
    assert named_digest({"w1": i32}) == "sha256:" + h.hexdigest()

#!/usr/bin/env python3
"""test_at231_epoch_receipt_anchor — kalan test-disi KRITIK cekirdek fonksiyonlar.

Kapsam (AST taramasiyla bulunan, tests/ altinda hic referans alinmayan halkalar):
  * tamga_epoch_verify  — _leaf / verify_inclusion / _selector / read_onchain_epoch
                          (epoch-mührü dahil-etme + zincir-çapa bacağı; RPC MOCK)
  * tamga_cr_verify     — digest_bytes / tensor_digest / named_digest / verify_single
                          (Computation-Receipt kanoniklik + sha256-digest; saf mantik)
  * tamga_pugio_receiver— verify_anchor_line (K0 §5 external_anchor bağı; pür sha256)
  * tamga_pugio_ingest  — _canonical / _merkle / verify_bundle / verification_receipt
                          (K0 §2-§4 zincir+kök+başlık; makbuz üretimi)
  * tamga_explain       — jcs_bytes / explain_receipt / explain_charge
                          (JCS kanonikalite + türetilebilir-bağ yeniden-hesabı)
  * tamga_netproxy      — validate_net_decl_dict (RFC-007 R1 katı şema; IP-sabit)
  * emitter_registry    — register_emitter / runtime_seen / RESERVED (fail-closed ailesi)

Kurallar:
  - MEVCUT testlere/koda DOKUNULMAZ; bu dosya SADECE yeni okuma-testi ekler.
  - Dis-cagrilari (JSON-RPC) monkeypatch ile MOCK eder; geri kalan fonksiyonlarin
    KENDI mantigini test eder (üretim DOS/veritabani/soket ACILMAZ).
"""
import hashlib
import io
import json
import struct

import pytest

import tamga_cr_verify
import tamga_epoch_verify
import tamga_explain
import tamga_keccak
import tamga_netproxy
import tamga_pugio_ingest
import tamga_pugio_receiver
import emitter_registry
from tamga_verify_mini import jcs


# =====================================================================
# tamga_epoch_verify — epoch-mührü: dahil-etme bacağı (saf) + çapa (MOCK RPC)
# =====================================================================

class TestEpochLeaf:
    def test_double_keccak_known_shape(self):
        raw = bytes(range(32))
        expect = tamga_keccak.keccak256(tamga_keccak.keccak256(raw))
        assert tamga_epoch_verify._leaf("0x" + raw.hex()) == expect

    def test_0x_prefix_strip_leniency(self):
        raw = bytes(32)
        assert tamga_epoch_verify._leaf(raw.hex()) == tamga_epoch_verify._leaf("0x" + raw.hex())

    def test_wrong_length_raises(self):
        with pytest.raises(ValueError):
            tamga_epoch_verify._leaf("0x" + "11" * 16)
        with pytest.raises(ValueError):
            tamga_epoch_verify._leaf("0x" + "11" * 33)


class TestVerifyInclusion:
    def test_single_element_empty_proof_root_equals_leaf(self):
        raw = bytes(32)
        leaf = tamga_keccak.keccak256(tamga_keccak.keccak256(raw))
        root = "0x" + leaf.hex()
        ok, comp = tamga_epoch_verify.verify_inclusion("0x" + raw.hex(), [], root)
        assert ok and comp == root

    def test_two_element_sorted_pairs_walk(self):
        fact = "11" * 32
        leaf = tamga_keccak.keccak256(tamga_keccak.keccak256(bytes.fromhex(fact)))
        s1 = tamga_keccak.keccak256(b"\x02" * 32)
        s2 = tamga_keccak.keccak256(b"\x03" * 32)
        n1 = tamga_keccak.keccak256(min(leaf, s1) + max(leaf, s1))
        root = tamga_keccak.keccak256(min(n1, s2) + max(n1, s2))
        # bir kardeş 0x'li, digeri 0x'siz — her iki hex kipini de ört
        ok, comp = tamga_epoch_verify.verify_inclusion(
            "0x" + fact, ["0x" + s1.hex(), s2.hex()], "0x" + root.hex())
        assert ok and comp == "0x" + root.hex()

    def test_sibling_order_independent(self):
        # iki gerçek fact'ın çift-hash yaprakları: düğüm/kardeş yer-değiştirince
        # ayni kök (sorted-pairs sözleşmesi)
        f1, f2 = "22" * 32, "33" * 32
        leaf1 = tamga_keccak.keccak256(tamga_keccak.keccak256(bytes.fromhex(f1)))
        leaf2 = tamga_keccak.keccak256(tamga_keccak.keccak256(bytes.fromhex(f2)))
        a, b = sorted([leaf1, leaf2])
        root = "0x" + tamga_keccak.keccak256(a + b).hex()
        r1 = tamga_epoch_verify.verify_inclusion("0x" + f1, ["0x" + leaf2.hex()], root)
        r2 = tamga_epoch_verify.verify_inclusion("0x" + f2, ["0x" + leaf1.hex()], root)
        assert r1[0] and r2[0] and r1[1] == r2[1] == root

    def test_corrupt_hex_proof_is_red(self):
        ok, msg = tamga_epoch_verify.verify_inclusion("0x" + "11" * 32, ["0xZZZZ"], "0x" + "22" * 32)
        assert not ok and "hex-bozuk" in msg

    def test_wrong_length_sibling_is_red(self):
        ok, msg = tamga_epoch_verify.verify_inclusion("0x" + "11" * 32, ["0x" + "22" * 16], "0x" + "22" * 32)
        assert not ok and "32-bayt" in msg

    def test_root_mismatch_returns_computed(self):
        raw = bytes.fromhex("11" * 32)
        comp_expect = "0x" + tamga_keccak.keccak256(tamga_keccak.keccak256(raw)).hex()
        ok, comp = tamga_epoch_verify.verify_inclusion("0x" + "11" * 32, [], "0x" + "22" * 32)
        assert not ok and comp == comp_expect


class TestSelector:
    def test_selector_is_keccak_prefix(self):
        assert tamga_epoch_verify._selector("epoch(uint64)") == \
            "0x" + tamga_keccak.keccak256(b"epoch(uint64)").hex()[:8]

    def test_selector_stable_and_short(self):
        s = tamga_epoch_verify._selector("epoch(uint64)")
        assert len(s) == 10 and s.startswith("0x")
        assert tamga_epoch_verify._selector("epoch(uint64)") == s
        # farkli imza → farkli selector
        assert tamga_epoch_verify._selector("factsCount()") != s


class _RPC:
    """Test-iskalesi: JSON-RPC zarflarini method'a göre döndürür (AĞ YOK)."""

    def __init__(self, envelopes):
        self.envelopes = envelopes
        self.requests = []

    def __call__(self, req, timeout=None):
        body = json.loads(req.data.decode("utf-8"))
        self.requests.append(body)
        env = self.envelopes.get(body["method"])
        if env is None:
            raise RuntimeError(f"test-iskalesi: beklenmedik method {body['method']}")
        return io.BytesIO(json.dumps(env).encode("utf-8"))


class TestReadOnchainEpoch:
    CONTRACT = "0x" + "ab" * 20
    ROOT_HEX = "cd" * 32

    def _envelope(self, result):
        return {"jsonrpc": "2.0", "id": 1, "result": result}

    def test_well_formed_parses_root_and_count(self, monkeypatch):
        rpc = _RPC({"eth_call": self._envelope("0x" + self.ROOT_HEX + format(7, "064x"))})
        monkeypatch.setattr(tamga_epoch_verify.urllib.request, "urlopen", rpc)
        root, count = tamga_epoch_verify.read_onchain_epoch(
            "http://test-rpc", self.CONTRACT, 3)
        assert root == "0x" + self.ROOT_HEX
        assert count == 7

    def test_eth_call_calldata_encoding(self, monkeypatch):
        rpc = _RPC({"eth_call": self._envelope("0x" + self.ROOT_HEX + format(7, "064x"))})
        monkeypatch.setattr(tamga_epoch_verify.urllib.request, "urlopen", rpc)
        tamga_epoch_verify.read_onchain_epoch("http://test-rpc", self.CONTRACT, 3)
        req = rpc.requests[0]
        assert req["method"] == "eth_call"
        assert req["params"][0]["to"] == self.CONTRACT
        assert req["params"][0]["data"] == \
            tamga_epoch_verify._selector("epoch(uint64)") + format(3, "064x")
        assert req["params"][1] == "latest"

    def test_matching_chainid_prequery_proceeds(self, monkeypatch):
        rpc = _RPC({
            "eth_chainId": self._envelope("0xaa36a7"),   # 11155111 = sepolia
            "eth_call": self._envelope("0x" + self.ROOT_HEX + format(2, "064x")),
        })
        monkeypatch.setattr(tamga_epoch_verify.urllib.request, "urlopen", rpc)
        root, count = tamga_epoch_verify.read_onchain_epoch(
            "http://test-rpc", self.CONTRACT, 9, expect_chainid=11155111)
        assert (root, count) == ("0x" + self.ROOT_HEX, 2)
        assert rpc.requests[0]["method"] == "eth_chainId"
        assert rpc.requests[1]["method"] == "eth_call"

    def test_wrong_chainid_raises(self, monkeypatch):
        rpc = _RPC({"eth_chainId": self._envelope("0xaa36a7")})
        monkeypatch.setattr(tamga_epoch_verify.urllib.request, "urlopen", rpc)
        with pytest.raises(RuntimeError) as exc:
            tamga_epoch_verify.read_onchain_epoch(
                "http://test-rpc", self.CONTRACT, 1, expect_chainid=1)
        assert "yanlış-zincir" in str(exc.value)

    def test_short_result_raises(self, monkeypatch):
        rpc = _RPC({"eth_call": self._envelope("0x" + self.ROOT_HEX)})
        monkeypatch.setattr(tamga_epoch_verify.urllib.request, "urlopen", rpc)
        with pytest.raises(RuntimeError):
            tamga_epoch_verify.read_onchain_epoch("http://test-rpc", self.CONTRACT, 1)

    def test_error_response_raises(self, monkeypatch):
        rpc = _RPC({"eth_call": {"jsonrpc": "2.0", "id": 1,
                                 "error": {"code": -32000, "message": "reverted"}}})
        monkeypatch.setattr(tamga_epoch_verify.urllib.request, "urlopen", rpc)
        with pytest.raises(RuntimeError):
            tamga_epoch_verify.read_onchain_epoch("http://test-rpc", self.CONTRACT, 1)


# =====================================================================
# tamga_cr_verify — Computation-Receipt kanoniklik + digest (saf mantik)
# =====================================================================

class TestDigestBytes:
    def test_known_vectors(self):
        # NIST SHA-256 bilinen-yanıtlar (boş + "abc")
        assert tamga_cr_verify.digest_bytes(b"") == \
            "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        assert tamga_cr_verify.digest_bytes(b"abc") == \
            "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    def test_hex_payload_equivalent_to_raw(self):
        assert tamga_cr_verify.digest_bytes(b"\x00\x01") == tamga_cr_verify.digest_bytes(bytes.fromhex("0001"))


class TestTensorDigest:
    def test_formula_lock(self):
        h = hashlib.sha256()
        h.update(jcs({"dtype": "f8", "shape": [2, 3]}))
        h.update(struct.pack("<6d", 0.0, 1.0, 2.0, 3.0, 4.0, 5.0))
        assert tamga_cr_verify.tensor_digest("f8", [2, 3], "<6d", [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]) \
            == "sha256:" + h.hexdigest()

    def test_deterministic(self):
        a = tamga_cr_verify.tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
        assert tamga_cr_verify.tensor_digest("i4", [4], "<4i", [0, 1, 2, 3]) == a

    def test_value_change_diverges(self):
        a = tamga_cr_verify.tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
        b = tamga_cr_verify.tensor_digest("i4", [4], "<4i", [0, 1, 2, 4])
        assert a != b and a.startswith("sha256:")

    def test_dtype_shape_change_diverges(self):
        a = tamga_cr_verify.tensor_digest("i4", [4], "<4i", [0, 1, 2, 3])
        b = tamga_cr_verify.tensor_digest("i1", [4], "<4b", [0, 1, 2, 3])
        assert a != b


class TestNamedDigest:
    def test_order_independent(self):
        entries = {"w2": "sha256:aaa", "w1": "sha256:bbb", "w9": "sha256:ccc"}
        forward = tamga_cr_verify.named_digest(dict(entries))
        reverse = tamga_cr_verify.named_digest({k: entries[k] for k in reversed(sorted(entries))})
        assert forward == reverse

    def test_formula_lock(self):
        entries = {"w2": "sha256:aaa", "w1": "sha256:bbb"}
        h = hashlib.sha256()
        for name in sorted(entries):
            h.update(jcs({"name": name, "digest": entries[name]}))
        assert tamga_cr_verify.named_digest(entries) == "sha256:" + h.hexdigest()

    def test_entry_change_diverges(self):
        a = tamga_cr_verify.named_digest({"w1": "sha256:x"})
        assert tamga_cr_verify.named_digest({"w1": "sha256:y"}) != a


class TestVerifySingle:
    @staticmethod
    def _write(tmp_path, obj, name="r.json"):
        p = tmp_path / name
        p.write_text(json.dumps(obj), encoding="utf-8")
        return str(p)

    def _measure(self, tmp_path, obj, capsys):
        rc = tamga_cr_verify.verify_single(self._write(tmp_path, obj), None)
        assert rc == 0
        out = json.loads(capsys.readouterr().out)
        return out["digest"]

    def test_measurement_mode_returns_zero(self, tmp_path, capsys):
        out = self._measure(tmp_path, {"a": 1, "b": 2}, capsys)
        assert out.startswith("sha256:")

    def test_green_full_expect(self, tmp_path, capsys):
        digest = self._measure(tmp_path, {"a": 1, "b": 2}, capsys)
        rc = tamga_cr_verify.verify_single(self._write(tmp_path, {"a": 1, "b": 2}), digest)
        assert rc == 0
        assert "[GREEN]" in capsys.readouterr().err

    def test_green_bare_hex_expect(self, tmp_path, capsys):
        digest = self._measure(tmp_path, {"a": 1}, capsys)
        bare = digest.split(":", 1)[1]
        assert tamga_cr_verify.verify_single(self._write(tmp_path, {"a": 1}), bare) == 0

    def test_green_0x_prefixed_hex_expect(self, tmp_path, capsys):
        digest = self._measure(tmp_path, {"a": 1}, capsys)
        bare = digest.split(":", 1)[1]
        assert tamga_cr_verify.verify_single(self._write(tmp_path, {"a": 1}), "0x" + bare) == 0

    def test_red_mismatch_returns_one(self, tmp_path, capsys):
        rc = tamga_cr_verify.verify_single(self._write(tmp_path, {"a": 1}), "sha256:" + "0" * 64)
        assert rc == 1
        assert "[RED]" in capsys.readouterr().err

    def test_corrupt_json_returns_one(self, tmp_path, capsys):
        p = tmp_path / "bad.json"
        p.write_text("{ not: json ", encoding="utf-8")
        assert tamga_cr_verify.verify_single(str(p), None) == 1
        assert "bozuk-JSON" in capsys.readouterr().err

    def test_canonical_key_order_independent(self, tmp_path, capsys):
        d1 = self._measure(tmp_path, {"a": 1, "b": 2}, capsys)
        # ayni icerik farkli anahtar-sirasi → ayni kanonik digest (JCS)
        rc = tamga_cr_verify.verify_single(self._write(tmp_path, {"b": 2, "a": 1}, "o2.json"), d1)
        assert rc == 0

    def test_content_change_diverges(self, tmp_path, capsys):
        d1 = self._measure(tmp_path, {"a": 1, "b": 2}, capsys)
        rc = tamga_cr_verify.verify_single(self._write(tmp_path, {"a": 1, "b": 3}, "o3.json"), d1)
        assert rc == 1


# =====================================================================
# tamga_pugio_receiver — K0 §5 external_anchor bağı (pür sha256)
# =====================================================================

class TestVerifyAnchorLine:
    @staticmethod
    def _good(source="sikke"):
        head = hashlib.sha256(b"pugio-chain-head").hexdigest()
        merkle = hashlib.sha256(b"pugio-merkle-root").hexdigest()
        return {
            "type": "external_anchor", "bridge_version": tamga_pugio_receiver.BRIDGE_VERSION,
            "source": source, "agent": "ag-test",
            "anchor_id": hashlib.sha256(f"{head}|{merkle}|3".encode()).hexdigest()[:32],
            "head": head, "merkle_root": merkle, "event_count": 3,
        }

    @staticmethod
    def _run(a):
        return tamga_pugio_receiver.verify_anchor_line(
            json.dumps(a, sort_keys=True, separators=(",", ":")))

    def test_clean_sikke_anchor_passes(self):
        ok, msg = self._run(self._good())
        assert ok and msg.startswith("PASS")

    def test_legacy_pugio_source_compat(self):
        ok, msg = self._run(self._good(source="pugio"))
        assert ok and msg.startswith("PASS")

    def test_corrupt_json_is_red(self):
        ok, msg = tamga_pugio_receiver.verify_anchor_line("{not json")
        assert not ok and "JSON bozuk" in msg

    def test_non_object_is_red(self):
        ok, msg = tamga_pugio_receiver.verify_anchor_line("[1,2,3]")
        assert not ok and "nesne değil" in msg

    def test_wrong_envelope_type_is_red(self):
        a = self._good(); a["type"] = "something_else"
        ok, msg = self._run(a)
        assert not ok and "zarf-tipi" in msg

    def test_unknown_source_is_red(self):
        a = self._good(); a["source"] = "evil"
        ok, msg = self._run(a)
        assert not ok and "kaynak uyuşmuyor" in msg

    def test_unknown_bridge_version_is_red(self):
        a = self._good(); a["bridge_version"] = 99
        ok, msg = self._run(a)
        assert not ok and "bridge_version" in msg

    def test_missing_head_is_red(self):
        a = self._good(); del a["head"]
        ok, msg = self._run(a)
        assert not ok and "zorunlu-alan" in msg

    def test_short_head_is_red(self):
        a = self._good(); a["head"] = "a" * 63
        ok, msg = self._run(a)
        assert not ok and "64-hex" in msg

    @pytest.mark.parametrize("bad", [3.9, "3", True])
    def test_non_integer_event_count_is_red(self, bad):
        a = self._good(); a["event_count"] = bad
        ok, msg = self._run(a)
        assert not ok and "tam-sayı" in msg

    def test_anchor_id_bond_break_is_red(self):
        # event_count değişti, anchor_id eski — bağ kopuk (veri-değişikliği)
        a = self._good(); a["event_count"] = 4
        ok, msg = self._run(a)
        assert not ok and "bağı kopuk" in msg

    def test_anchor_id_recomputed_matches(self):
        # bağı yeniden hesapla: formülün kendisini de doğrula
        a = self._good()
        expect = hashlib.sha256(
            f"{a['head']}|{a['merkle_root']}|{a['event_count']}".encode()).hexdigest()[:32]
        assert a["anchor_id"] == expect


# =====================================================================
# tamga_pugio_ingest — K0 §2-§4 bundle doğrulaması + makbuz
# =====================================================================

class TestPugioIngestCore:
    def test_canonical_format(self):
        ev = {"ts": 1000.5, "event_type": "charge_receipt", "agent_id": "ag",
              "host": "/x", "amount": 0.05, "payload": '{"i":1}'}
        expect = "|".join(["1000.500000", "charge_receipt", "ag", "/x", "0.050000", '{"i":1}', "P" * 64])
        assert tamga_pugio_ingest._canonical(ev, "P" * 64) == expect

    def test_canonical_integer_ts_is_float_formatted(self):
        ev = {"ts": 2, "event_type": "t", "agent_id": "a", "host": "h",
              "amount": 1, "payload": "p"}
        assert tamga_pugio_ingest._canonical(ev, "0" * 64).split("|")[0] == "2.000000"

    def test_merkle_empty_is_genesis(self):
        assert tamga_pugio_ingest._merkle([]) == tamga_pugio_ingest.GENESIS == "0" * 64

    def test_merkle_single_leaf(self):
        assert tamga_pugio_ingest._merkle(["abc"]) == "abc"

    def test_merkle_pair(self):
        assert tamga_pugio_ingest._merkle(["a", "b"]) == \
            hashlib.sha256(b"ab").hexdigest()

    def test_merkle_odd_count_duplicates_last(self):
        l0, l1, l2 = "aa", "bb", "cc"
        s0 = hashlib.sha256((l0 + l1).encode()).hexdigest()
        s1 = hashlib.sha256((l2 + l2).encode()).hexdigest()
        assert tamga_pugio_ingest._merkle([l0, l1, l2]) == hashlib.sha256((s0 + s1).encode()).hexdigest()


def _k0_events():
    """Testin KENDI üreticisi (modülün selftest'inden bagimsiz, spec-formülü)."""
    events = []
    prev = tamga_pugio_ingest.GENESIS
    for i, (et, amt, ag, host) in enumerate([
            ("charge_receipt", 0.05, "ag-1", "/weather"),
            ("permission_decision", 0.0, "ag-2", "/pay"),
            ("charge_receipt", 0.05, "ag-1", "/search")]):
        ev = {"seq": i + 1, "ts": 1000.0 + i, "event_type": et, "agent_id": ag,
              "host": host, "amount": amt, "payload": f'{{"i":{i}}}', "prev_proof": prev}
        ev["proof"] = hashlib.sha256(
            tamga_pugio_ingest._canonical(ev, prev).encode()).hexdigest()
        events.append(ev)
        prev = ev["proof"]
    return events, prev


def _k0_bundle():
    events, head = _k0_events()
    return {
        "pugio_bundle_version": tamga_pugio_ingest.BUNDLE_VERSION,
        "generated": 1234567.0, "agent": "ag-1", "head": head,
        "merkle_root": tamga_pugio_ingest._merkle([e["proof"] for e in events]),
        "event_count": len(events), "events": events,
    }


class TestVerifyBundle:
    def test_clean_bundle_is_saglam_with_audit(self):
        ok, msg, audit = tamga_pugio_ingest.verify_bundle(_k0_bundle())
        assert ok and msg.startswith("SAĞLAM")
        assert audit == {"charge_total": 0.1, "receipts": 2,
                         "decisions": 1, "agents": ["ag-1", "ag-2"]}

    def test_unknown_bundle_version_is_red(self):
        b = _k0_bundle(); b["pugio_bundle_version"] = 99
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(b)
        assert not ok and "bundle-sürümü" in msg

    def test_non_dict_bundle_is_red(self):
        ok, msg, _ = tamga_pugio_ingest.verify_bundle("not-a-bundle")
        assert not ok and "bundle-bozuk" in msg

    def test_events_not_list_is_red(self):
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(
            {"pugio_bundle_version": 1, "events": "nope"})
        assert not ok and "liste değil" in msg

    def test_empty_bundle_is_red_fail_closed(self):
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(
            {"pugio_bundle_version": 1, "events": []})
        assert not ok and "boş-bundle" in msg

    def test_seq_jump_is_red(self):
        b = _k0_bundle(); b["events"][1]["seq"] = 5
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(b)
        assert not ok and "seq-atlaması" in msg

    def test_chain_break_is_red(self):
        b = _k0_bundle(); b["events"][1]["prev_proof"] = "f" * 64
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(b)
        assert not ok and "zincir-kopması" in msg

    def test_amount_tamper_breaks_proof_is_red(self):
        b = _k0_bundle(); b["events"][0]["amount"] = 0.01
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(b)
        assert not ok and "proof-uyuşmazlığı" in msg

    def test_head_mismatch_is_red(self):
        b = _k0_bundle(); b["head"] = "a" * 64
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(b)
        assert not ok and "head uyuşmuyor" in msg

    def test_merkle_root_mismatch_is_red(self):
        b = _k0_bundle(); b["merkle_root"] = "b" * 64
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(b)
        assert not ok and "merkle-kökü" in msg

    def test_event_count_mismatch_is_red(self):
        b = _k0_bundle(); b["event_count"] = 99
        ok, msg, _ = tamga_pugio_ingest.verify_bundle(b)
        assert not ok and "event_count uyuşmuyor" in msg


class TestVerificationReceipt:
    BUNDLE = {"head": "h" * 64, "merkle_root": "m" * 64, "event_count": 4}
    AUDIT = {"charge_total": 0.1, "receipts": 1, "decisions": 0, "agents": ["ag"]}

    def test_receipt_id_bond(self):
        r = tamga_pugio_ingest.verification_receipt(self.BUNDLE, self.AUDIT)
        expect = hashlib.sha256(
            f"SAĞLAM|{'h' * 64}|{'m' * 64}|4".encode()).hexdigest()[:32]
        assert r["receipt_id"] == expect

    def test_fields_echo_bundle_and_audit(self):
        r = tamga_pugio_ingest.verification_receipt(self.BUNDLE, self.AUDIT)
        assert r["type"] == "pugio_bundle_verification"
        assert r["verifier"] == tamga_pugio_ingest.VERIFIER
        assert r["verdict"] == "SAĞLAM"
        assert r["bundle_head"] == "h" * 64
        assert r["merkle_root"] == "m" * 64
        assert r["event_count"] == 4
        assert r["audit"] == self.AUDIT

    def test_receipt_is_deterministic(self):
        a = tamga_pugio_ingest.verification_receipt(self.BUNDLE, self.AUDIT)
        assert tamga_pugio_ingest.verification_receipt(self.BUNDLE, self.AUDIT) == a

    def test_bundle_change_diverges_receipt_id(self):
        base = tamga_pugio_ingest.verification_receipt(self.BUNDLE, self.AUDIT)["receipt_id"]
        b2 = dict(self.BUNDLE); b2["event_count"] = 5
        assert tamga_pugio_ingest.verification_receipt(b2, self.AUDIT)["receipt_id"] != base


# =====================================================================
# tamga_explain — JCS + receipt/charge insan-dili render + bağ yeniden-hesabı
# =====================================================================

class TestExplainJcsBytes:
    def test_order_independent_canonical(self):
        assert tamga_explain.jcs_bytes({"b": 2, "a": 1}) == tamga_explain.jcs_bytes({"a": 1, "b": 2})

    def test_returns_canonical_bytes(self):
        assert tamga_explain.jcs_bytes({"a": 1, "b": 2}) == b'{"a":1,"b":2}'


class TestExplainReceipt:
    def test_canonical_payment_id_marker(self):
        out = tamga_explain.explain_receipt({
            "paymentId": "0x" + "a" * 64, "contentHash": "0x" + "b" * 64,
            "network": "sepolia", "txHash": "0x" + "c" * 64,
            "retentionUntil": 999, "pointer": "ipfs://x"})
        assert "kanonik" in out
        assert "Ödeme-kimliği" in out and "İçerik-mührü" in out
        assert "Blob-gösterici" in out and "Bekleme" in out

    def test_non_canonical_payment_id_marker(self):
        out = tamga_explain.explain_receipt(
            {"paymentId": "0x" + "A" * 64, "contentHash": "0x" + "b" * 64})
        assert "KANONİK-DEĞİL" in out

    def test_en_labels(self):
        out = tamga_explain.explain_receipt(
            {"paymentId": "0x" + "a" * 64, "contentHash": "0x" + "b" * 64},
            L=tamga_explain.LABELS_EN)
        assert "Payment id" in out and "canonical 0x+64-lower OK" in out
        assert "Content seal" in out and "Retention" in out


class TestExplainCharge:
    @staticmethod
    def _full_rec():
        rec = {"seq": 7, "pkg": "pkg-a", "session": "s1", "prev": "p" * 64,
               "wall_ms": 12, "fee_sim": 3, "cpu_saat": 1.5, "ram_gb_sn": 2.0,
               "io_mb": 4, "stdout_sha256": "a" * 64, "input_sha256": "c" * 64,
               "net_decl_sha256": "d" * 64, "net_mb": 5,
               "delivery_hash": {"alg": "sha256", "hex": "e" * 64}}
        no_h = dict(rec)
        rec["h"] = hashlib.sha256(
            (rec["prev"].encode() + tamga_explain.jcs_bytes(no_h))).hexdigest()
        return rec

    def test_full_record_all_branches_and_verified(self):
        out = tamga_explain.explain_charge(self._full_rec())
        assert "DOĞRULANDI" in out
        assert "== charge kaydı (seq 7) ==" in out
        assert "pkg-a" in out and "s1" in out
        assert "12 ms" in out and "3 birim" in out
        assert "cpu-saat" in out and "GB-saniye RAM" in out and "MiB I/O" in out
        assert "Çıktı-parmak-izi" in out and "Girdi-bağı (D11)" in out
        assert "Ağ-beyanı (D12)" in out and "Ağ-trafiği" in out
        assert "Teslim-bağı" in out and "Zincir-yeri" in out

    def test_tampered_record_is_mismatch(self):
        rec = self._full_rec()
        rec["wall_ms"] = 999
        assert "EŞLEŞMİYOR" in tamga_explain.explain_charge(rec)

    def test_en_labels_verified(self):
        out = tamga_explain.explain_charge(self._full_rec(), L=tamga_explain.LABELS_EN)
        assert "VERIFIED" in out and "== charge record (seq 7) ==" in out
        assert "Wall clock" in out and "Chain integrity" in out

    def test_minimal_record_has_no_verdict_line(self):
        out = tamga_explain.explain_charge({"seq": 1})
        assert "== charge kaydı (seq 1) ==" in out
        assert "Zincir-dürüstlüğü" not in out
        assert "ms" not in out and "birim" not in out


# =====================================================================
# tamga_netproxy — RFC-007 R1 katı net-beyan şeması (IP-sabit, DNS YOK)
# =====================================================================

class TestValidateNetDeclDict:
    @staticmethod
    def _good(**over):
        d = {"format": tamga_netproxy.NET_FORMAT,
             "egress": ["127.0.0.1:443", "10.0.0.1:80"],
             "max_bytes_per_run": 4096, "timeout_s": 30}
        d.update(over)
        return d

    def test_valid_decl_normalizes_and_pins_ips(self):
        r = tamga_netproxy.validate_net_decl_dict(self._good())
        assert r["format"] == tamga_netproxy.NET_FORMAT
        assert r["egress"] == ["127.0.0.1:443", "10.0.0.1:80"]
        assert r["_allowed"] == {"127.0.0.1:443", "10.0.0.1:80"}
        assert r["_pinned"] == {"127.0.0.1": "127.0.0.1", "10.0.0.1": "10.0.0.1"}
        assert r["max_bytes_per_run"] == 4096 and r["timeout_s"] == 30

    def test_wrong_format_is_red(self):
        with pytest.raises(tamga_netproxy.NetDeclError):
            tamga_netproxy.validate_net_decl_dict(self._good(format="tamga-net-declaration/0"))

    def test_unknown_key_is_red(self):
        with pytest.raises(tamga_netproxy.NetDeclError) as e:
            tamga_netproxy.validate_net_decl_dict(self._good(foo=1))
        assert "unknown keys" in str(e.value)

    def test_empty_egress_is_red(self):
        with pytest.raises(tamga_netproxy.NetDeclError):
            tamga_netproxy.validate_net_decl_dict(self._good(egress=[]))

    def test_too_many_endpoints_is_red(self):
        with pytest.raises(tamga_netproxy.NetDeclError):
            tamga_netproxy.validate_net_decl_dict(
                self._good(egress=[f"10.0.0.{i}:443" for i in range(tamga_netproxy.MAX_ENDPOINTS + 1)]))

    def test_duplicate_endpoints_are_red(self):
        with pytest.raises(tamga_netproxy.NetDeclError) as e:
            tamga_netproxy.validate_net_decl_dict(
                self._good(egress=["127.0.0.1:443", "127.0.0.1:443"]))
        assert "duplicate" in str(e.value)

    def test_egress_not_list_is_red(self):
        with pytest.raises(tamga_netproxy.NetDeclError):
            tamga_netproxy.validate_net_decl_dict(self._good(egress="127.0.0.1:443"))

    @pytest.mark.parametrize("bad", ["http://127.0.0.1:443",   # scheme karakteri
                                     "127.0.0.1",              # port yok
                                     "127.0.0.1:70000",        # port aralık dışı
                                     "127.0.0.1:0",            # port sıfır
                                     "127.0.0.1:abc",          # port sayı değil
                                     "",                       # boş dize
                                     "user@127.0.0.1:443"])    # userinfo
    def test_bad_endpoint_is_red(self, bad):
        with pytest.raises(tamga_netproxy.NetDeclError):
            tamga_netproxy.validate_net_decl_dict(self._good(egress=[bad]))

    @pytest.mark.parametrize("bad", [1023, tamga_netproxy.BYTES_MAX + 1, 1024.0, True, "4096"])
    def test_bad_max_bytes_is_red(self, bad):
        with pytest.raises(tamga_netproxy.NetDeclError):
            tamga_netproxy.validate_net_decl_dict(self._good(max_bytes_per_run=bad))

    @pytest.mark.parametrize("bad", [0, tamga_netproxy.TIMEOUT_S_MAX + 1, 30.5, True, "30"])
    def test_bad_timeout_is_red(self, bad):
        with pytest.raises(tamga_netproxy.NetDeclError):
            tamga_netproxy.validate_net_decl_dict(self._good(timeout_s=bad))

    def test_boundary_values_accepted(self):
        assert tamga_netproxy.validate_net_decl_dict(
            self._good(max_bytes_per_run=tamga_netproxy.BYTES_MIN,
                       timeout_s=tamga_netproxy.TIMEOUT_S_MIN))["timeout_s"] == 1
        assert tamga_netproxy.validate_net_decl_dict(
            self._good(max_bytes_per_run=tamga_netproxy.BYTES_MAX,
                       timeout_s=tamga_netproxy.TIMEOUT_S_MAX))["max_bytes_per_run"] == tamga_netproxy.BYTES_MAX


# =====================================================================
# emitter_registry — runtime fail-closed kayıt-defteri ailesi
# =====================================================================

class TestEmitterRegistry:
    def test_register_then_seen(self):
        emitter_registry.register_emitter("at231-probe-op")
        assert "at231-probe-op" in emitter_registry.runtime_seen()

    def test_runtime_seen_returns_copy(self):
        s = emitter_registry.runtime_seen()
        s.add("mutated-by-test")
        assert "mutated-by-test" not in emitter_registry.runtime_seen()

    def test_reserved_ops_are_listed(self):
        assert "fee" in emitter_registry.EMITTED_OPS
        assert all(isinstance(op, str) for op in emitter_registry.EMITTED_OPS)
        assert len(emitter_registry.EMITTED_OPS) >= 1

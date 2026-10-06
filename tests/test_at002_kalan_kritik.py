"""AT-002 kalan test-dışı kritik fonksiyonlar — time-axis / oracle / attest.

Bu dosya MEVCUT hiçbir testin/kodun dokunmadığı 6 public fonksiyonu kapsar
(AST taraması: tests/ altındaki hiçbir .py/.sh bunları ismen çağırmıyor):

  time-axis  verify_token          (tools/brandstrike_tsa.py:644)
  time-axis  parse_timestamp_resp  (tools/brandstrike_tsa.py:485)
  time-axis  build_signed_data     (tools/brandstrike_tsa.py:269)
  oracle     cmd_run_request       (tamga_oracle_relayer.py:985)
  oracle     export_snapshot       (tamga_oracle_relayer.py:450)
  attest     run_vectors           (tamga_attest_verify.py:200)

Yöntem — "dal-kesen" (her fonksiyonun kendi mantığı, her dalı ayrı ayrı):
  • brandstrike yüzeyi SAF gerçektir: Ed25519 imzaları PyNaCl ile gerçekten
    atılır, DER elle üretilir — hiçbir crypto stub yok.
  • oracle CLI fonksiyonlarının DIŞ çağrıları (tamga_runner subprocess,
    sester Ledger) monkeypatch ile değiştirilir; yalnızca fonksiyonun KENDİ
    mantığı (argv/env önceliği, hata eşleme, fail-closed rc) sınanır.
  • attest run_vectors deponun GERÇEK golden-vektör dosyasını okur
    (tests/vendor-capacity-attest/golden-vectors.json) — gerçek secp256k1
    ecrecover kanıtı, mock yok.
"""
import datetime
import hashlib
import json
import sys
from pathlib import Path

import pytest
from nacl.signing import SigningKey

# conftest.py repo-kökünü sys.path'e koyar; tools/ ayrıca eklenmeli.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import brandstrike_tsa as bst
import tamga_attest_verify as tav
import tamga_oracle_relayer as tor

VECTORS = Path(__file__).resolve().parent / "vendor-capacity-attest" / "golden-vectors.json"


# --- yardımcılar: gerçek DER + gerçek Ed25519 --------------------------------------------
def _digest_of(records):
    return bst.tip_imprint(records)[0]


def _two_record_ledger():
    base = {"op": "charge", "amount": "0.01", "ts": "2026-10-05T00:00:00Z"}
    recs, prev = [], "0" * 64
    for i, note in enumerate(("ilk", "iki"), start=1):
        rec = dict(base, note=f"{note}-kanit")
        rec["seq"] = i
        rec["prev"] = prev
        no_h = {k: v for k, v in rec.items() if k != "h"}
        rec["h"] = hashlib.sha256((prev + bst._jcs_str(no_h)).encode("utf-8")).hexdigest()
        recs.append(rec)
        prev = rec["h"]
    return recs


def _mint(digest, sk, *, nonce=0x4242, serial=7, policy=None, status=0,
          fail_info=None, status_string=None, stamp_over=None):
    """Gerçek bir RFC 3161 TimeStampResp üret — imza TSTInfo üzerinden atılır."""
    over = stamp_over if stamp_over is not None else digest
    imp = bst._message_imprint(over)
    tst = bst._tst_info(imp, serial, bst.DEMO_GEN_TIME, nonce, policy or bst.OID_DEMO_POLICY)
    return bst.build_timestamp_resp(
        imp, serial=serial, gen_time=bst.DEMO_GEN_TIME, nonce=nonce,
        signature=sk.sign(tst).signature, status=status,
        fail_info=fail_info, status_string=status_string)


@pytest.fixture
def recs():
    return _two_record_ledger()


@pytest.fixture
def key():
    return SigningKey(bytes.fromhex("9" * 64))


# === 1) verify_token — zaman-ekseni bağının kapısı ========================================
class TestVerifyToken:
    def test_green_over_true_imprint_with_policy_and_key(self, recs, key):
        digest = _digest_of(recs)
        resp = _mint(digest, key)
        v, r, d = bst.verify_token(resp, expected_imprint=digest, nonce=0x4242,
                                   tsa_key=key.verify_key.encode().hex(),
                                   policy=bst.OID_DEMO_POLICY)
        assert v == "ok" and r == "ok"
        assert "verified" in d["signature"]
        assert d["status"] == 0 and d["status_label"] == "granted"
        assert d["imprint"] == digest.hex()
        assert d["hash_alg"] == "sha256"
        assert d["tst"]["policy"] == bst.OID_DEMO_POLICY
        assert d["tst"]["serial"] == 7 and d["tst"]["nonce"] == 0x4242

    def test_policy_mismatch_is_red(self, recs, key):
        digest = _digest_of(recs)
        resp = _mint(digest, key)
        v, r, d = bst.verify_token(resp, expected_imprint=digest,
                                   policy="1.3.6.1.4.1.65535.9.9")
        assert v == "red"
        assert r.startswith("policy_mismatch")
        assert d["tst"]["policy"] == bst.OID_DEMO_POLICY

    def test_imprint_gate_runs_before_signature_gate(self, recs, key):
        """Güvenlik sıralaması: decoy-imprintli token GEÇERLİ imzalı olsa bile
        imprint-mismatch döner — imza kapısı hiç devreye girmez."""
        digest = _digest_of(recs)
        decoy = bst.evidence_imprint(b"not-the-ledger")
        resp = _mint(digest, key, stamp_over=decoy)
        v, r, d = bst.verify_token(resp, expected_imprint=digest,
                                   tsa_key=key.verify_key.encode().hex())
        assert v == "red" and r.startswith("imprint_mismatch")
        # imprint kapısı imza kapısından ÖNCE çalışır: detail'de imza kanıtı YOK
        assert "signature" not in d

    def test_nonce_mismatch_is_red(self, recs, key):
        digest = _digest_of(recs)
        resp = _mint(digest, key, nonce=0x9999)
        v, r, _ = bst.verify_token(resp, expected_imprint=digest, nonce=0x4242)
        assert v == "red" and r.startswith("nonce_mismatch")

    def test_granted_without_a_token_is_red(self, recs):
        """PKIStatus=granted ama token yok — bu durum build_timestamp_resp'tan
        üretilemez; elle DER kurulur (parser dalını keser)."""
        der = bst._tlv(0x30, bst._tlv(0x30, bst._tlv(0x02, bst._enc_int(0))))
        v, r, _ = bst.verify_token(der, expected_imprint=_digest_of(recs))
        assert v == "red" and r == "tsa_granted_without_token"

    def test_rejection_status_surfaces_failinfo(self, recs, key):
        digest = _digest_of(recs)
        resp = _mint(digest, key, status=2, status_string="unsupported policy",
                     fail_info=["unacceptedPolicy"])
        v, r, d = bst.verify_token(resp, expected_imprint=digest)
        assert v == "red" and r == "tsa_status_rejection"
        assert d["fail_info"] == ["unacceptedPolicy"]
        assert d["status_string"] == ["unsupported policy"]

    def test_no_tsa_key_is_not_a_pass(self, recs, key):
        digest = _digest_of(recs)
        resp = _mint(digest, key)
        v, _, d = bst.verify_token(resp, expected_imprint=digest)
        assert v == "ok" and "not-checked" in d["signature"]

    def test_malformed_der_is_red_never_a_crash(self, recs):
        for junk in (b"not-der-at-all", b"", b"\x30\x99"):
            v, r, _ = bst.verify_token(junk, expected_imprint=_digest_of(recs))
            assert v == "red" and r.startswith("response_malformed"), (junk, r)


# === 2) parse_timestamp_resp — RFC 3161 response parser ==================================
class TestParseTimestampResp:
    def test_granted_yields_full_tst_info(self, recs, key):
        digest = _digest_of(recs)
        resp = _mint(digest, key)
        p = bst.parse_timestamp_resp(resp)
        assert p["status"] == 0 and p["status_label"] == "granted"
        assert "signed_data" in p and "tst_info" in p
        tst = p["tst_info"]
        assert tst["imprint"]["imprint"] == digest.hex()
        assert tst["imprint"]["hash_oid"] == bst.OID_SHA256
        assert tst["policy"] == bst.OID_DEMO_POLICY
        assert tst["serial"] == 7 and tst["nonce"] == 0x4242
        assert tst["version"] == 1 and tst["accuracy_seconds"] == 1
        assert tst["gen_time"] == "2026-10-05T12:05:30Z"
        # gen_time_epoch, DEC'den çıkan UTC saniyesiyle birebir
        expect_epoch = int(datetime.datetime(2026, 10, 5, 12, 5, 30,
                                             tzinfo=datetime.timezone.utc).timestamp())
        assert tst["gen_time_epoch"] == expect_epoch

    def test_rejection_carries_status_string_and_failinfo(self, recs, key):
        digest = _digest_of(recs)
        resp = _mint(digest, key, status=2, status_string="bad policy",
                     fail_info=["badAlg", "unacceptedPolicy"])
        p = bst.parse_timestamp_resp(resp)
        assert p["status"] == 2 and p["status_label"] == "rejection"
        assert p["status_string"] == ["bad policy"]
        assert p["fail_info"] == ["badAlg", "unacceptedPolicy"]
        # rejection durumunda token geçirilmez
        assert "signed_data" not in p and "tst_info" not in p
    def test_granted_status_without_token_has_no_signed_data(self):
        der = bst._tlv(0x30, bst._tlv(0x30, bst._tlv(0x02, bst._enc_int(1))))
        p = bst.parse_timestamp_resp(der)
        assert p["status"] == 1 and p["status_label"] == "grantedWithMods"
        assert "signed_data" not in p

    @pytest.mark.parametrize("bad,match", [
        (b"", "missing tag"),
        (b"\x04\x01\x00", "outer tag is not SEQUENCE"),
        (bst._tlv(0x30, bst._tlv(0x04, b"x")), "not a SEQUENCE"),
        (bst._tlv(0x30, bst._tlv(0x30, bst._tlv(0x04, b"x")) + bst._tlv(0x02, bst._enc_int(7))),
         "missing status INTEGER"),
        (bst._tlv(0x30, bst._tlv(0x30, bst._tlv(0x02, bst._enc_int(99)))), "unknown status"),
    ])
    def test_malformed_responses_raise_value_error(self, bad, match):
        with pytest.raises(ValueError, match=match):
            bst.parse_timestamp_resp(bad)


# === 3) build_signed_data — CMS SignedData üreticisi =====================================
class TestBuildSignedData:
    def test_roundtrip_through_parse_signed_data(self):
        imp = bst._message_imprint(bytes(32))
        tst = bst._tst_info(imp, 11, bst.DEMO_GEN_TIME, 0x77)
        sig = bytes(range(64))
        sd = bst.build_signed_data(tst, sig)
        p = bst.parse_signed_data(sd)
        assert p["e_content"] == tst.hex()
        assert p["e_content_type"] == bst.OID_ID_CT_TST_INFO
        assert p["signer"]["sig_alg"] == bst.OID_EDDSA
        assert p["signer"]["signature"] == sig.hex()
        assert p["signer"]["version"] == 3
        assert p["tst_info"]["serial"] == 11 and p["tst_info"]["nonce"] == 0x77

    def test_sig_alg_is_overridable(self):
        imp = bst._message_imprint(bytes(32))
        tst = bst._tst_info(imp, 1, bst.DEMO_GEN_TIME, 1)
        sd = bst.build_signed_data(tst, b"\x02" * 64, sig_alg=bst.OID_ED448)
        assert bst.parse_signed_data(sd)["signer"]["sig_alg"] == bst.OID_ED448

    def test_built_signed_data_verifies_as_a_token(self, recs, key):
        """Üretilen SignedData gerçek verify_token kapısından geçer."""
        digest = _digest_of(recs)
        imp = bst._message_imprint(digest)
        tst = bst._tst_info(imp, 3, bst.DEMO_GEN_TIME, 0x31)
        sd = bst.build_signed_data(tst, key.sign(tst).signature)
        resp = bst._tlv(0x30, bst._tlv(0x30, bst._tlv(0x02, bst._enc_int(0)))
                        + bst._tlv(0x30, bst._tlv(0x06, bst._enc_oid(bst.OID_ID_SIGNED_DATA))
                                   + bst._tlv(0xA0, sd)))
        v, r, _ = bst.verify_token(resp, expected_imprint=digest, nonce=0x31,
                                   tsa_key=key.verify_key.encode().hex())
        assert v == "ok" and r == "ok"


# === 4) cmd_run_request — oracle KATMAN-0 run-request CLI ================================
class TestCmdRunRequest:
    def _patch(self, monkeypatch):
        seen = {}

        def fake_registry(path):
            seen["reg"] = path
            return {"_meta": 1, "abc123": {"pkg_path": "/tmp/x"}}

        def fake_execute(request, registry, seed_hex, workdir=".", ledger_secret=None):
            seen["req"] = request
            seen["secret"] = ledger_secret
            return {"receipt": {"stdout_sha256": "a" * 64}, "digest": "d" * 64,
                    "payload": "payload-bayt", "blob_sha256": "b" * 64}

        monkeypatch.setattr(tor, "load_registry", fake_registry)
        monkeypatch.setattr(tor, "execute_request", fake_execute)
        return seen

    def _run(self, capsys, args):
        rc = tor.cmd_run_request(list(args))
        return rc, json.loads(capsys.readouterr().out.strip().splitlines()[-1])

    def test_happy_path_builds_request_and_returns_ok(self, monkeypatch, capsys):
        seen = self._patch(monkeypatch)
        rc, out = self._run(capsys, ["--registry", "reg.json", "--seed", "a" * 64,
                                     "--module-hash", "b" * 64, "--cpu-ms", "300"])
        assert rc == 0 and out["ok"] is True
        assert out["op"] == "run-request"
        assert out["module"] == ("b" * 64)[:16]
        assert out["digest"] == "d" * 64
        assert seen["req"] == {"wasi_module_hash": "b" * 64, "max_cpu_ms_allowed": 300,
                               "request_id": 1, "input_payload": None}

    def test_default_cpu_ms_is_5000(self, monkeypatch, capsys):
        seen = self._patch(monkeypatch)
        self._run(capsys, ["--registry", "reg.json", "--seed", "a" * 64,
                           "--module-hash", "b" * 64])
        assert seen["req"]["max_cpu_ms_allowed"] == 5000

    def test_input_flag_is_forwarded(self, monkeypatch, capsys):
        seen = self._patch(monkeypatch)
        self._run(capsys, ["--registry", "reg.json", "--seed", "a" * 64,
                           "--module-hash", "b" * 64, "--input", "/tmp/in.bin"])
        assert seen["req"]["input_payload"] == "/tmp/in.bin"

    @pytest.mark.parametrize("args", [
        ["--registry", "reg.json", "--seed", "a" * 64],               # module-hash yok
        ["--seed", "a" * 64, "--module-hash", "b" * 64],               # registry yok
    ])
    def test_missing_required_args_are_usage_red(self, monkeypatch, capsys, args):
        self._patch(monkeypatch)
        rc, out = self._run(capsys, args)
        assert rc == 1 and out["ok"] is False and out["reason_code"] == 2
        assert "zorunlu" in out["reason"]

    def test_empty_argv_is_usage_red(self, monkeypatch, capsys):
        self._patch(monkeypatch)
        rc, out = self._run(capsys, [])
        assert rc == 1 and out["ok"] is False and out["reason_code"] == 2
        assert out["reason"].startswith("kullanim: run-request")

    def test_relayer_error_propagates_its_reason_code(self, monkeypatch, capsys):
        def boom(request, registry, seed_hex, workdir=".", ledger_secret=None):
            raise tor.TamgaRelayerError(tor.RC_MODULE_NOT_FOUND, "yok")

        monkeypatch.setattr(tor, "load_registry", lambda p: {})
        monkeypatch.setattr(tor, "execute_request", boom)
        rc, out = self._run(capsys, ["--registry", "reg.json", "--seed", "a" * 64,
                                     "--module-hash", "b" * 64])
        assert rc == 1 and out["reason_code"] == tor.RC_MODULE_NOT_FOUND
        assert out["reason"] == "yok"

    def test_value_error_becomes_parse_red(self, monkeypatch, capsys):
        def boom(request, registry, seed_hex, workdir=".", ledger_secret=None):
            raise ValueError("bad number")

        monkeypatch.setattr(tor, "load_registry", lambda p: {})
        monkeypatch.setattr(tor, "execute_request", boom)
        rc, out = self._run(capsys, ["--registry", "reg.json", "--seed", "a" * 64,
                                     "--module-hash", "b" * 64])
        assert rc == 1 and out["reason_code"] == 2
        assert out["reason"].startswith("parse-hatası")

    def test_argv_secret_wins_over_env(self, monkeypatch, capsys):
        seen = self._patch(monkeypatch)
        monkeypatch.setenv("TAMGA_RELAYER_LEDGER_SECRET", "ENV-SECRET")
        self._run(capsys, ["--registry", "reg.json", "--seed", "a" * 64,
                           "--module-hash", "b" * 64, "--ledger-secret", "ARGV-SECRET"])
        assert seen["secret"] == "ARGV-SECRET"

    def test_env_secret_used_when_argv_absent(self, monkeypatch, capsys):
        seen = self._patch(monkeypatch)
        monkeypatch.setenv("TAMGA_RELAYER_LEDGER_SECRET", "ENV-SECRET")
        self._run(capsys, ["--registry", "reg.json", "--seed", "a" * 64,
                           "--module-hash", "b" * 64])
        assert seen["secret"] == "ENV-SECRET"


# === 5) export_snapshot — oracle KATMAN-1 export sürücüsü ================================
class TestExportSnapshot:
    def test_ok_returns_out_path_with_runner_argv(self, monkeypatch):
        seen = {}

        def fake_runner(argv, cwd="."):
            seen["argv"] = argv
            return {"ok": True, "stdout_file": "/tmp/o"}

        monkeypatch.setattr(tor, "_runner", fake_runner)
        ret = tor.export_snapshot("/tmp/p.pkg", "a" * 64, "/tmp/snap.tsg", cwd="/tmp")
        assert ret == "/tmp/snap.tsg"
        assert seen["argv"] == ["export", "/tmp/p.pkg", "-o", "/tmp/snap.tsg",
                                "--seed", "a" * 64]

    def test_runner_failure_raises_run_failed(self, monkeypatch):
        monkeypatch.setattr(tor, "_runner", lambda argv, cwd=".": {"ok": False})
        with pytest.raises(tor.TamgaRelayerError) as ei:
            tor.export_snapshot("/tmp/p.pkg", "a" * 64, "/tmp/snap.tsg")
        assert ei.value.reason_code == tor.RC_RUN_FAILED

    def test_runner_error_propagates_unchanged(self, monkeypatch):
        def boom(argv, cwd="."):
            raise tor.TamgaRelayerError(tor.RC_SNAPSHOT_TOO_LARGE, "cok-buyuk")

        monkeypatch.setattr(tor, "_runner", boom)
        with pytest.raises(tor.TamgaRelayerError) as ei:
            tor.export_snapshot("/tmp/p.pkg", "a" * 64, "/tmp/snap.tsg")
        assert ei.value.reason_code == tor.RC_SNAPSHOT_TOO_LARGE


# === 6) run_vectors — attest bağımsız-koşumRunner'ı =======================================
class TestRunVectors:
    def test_real_golden_vectors_all_pass(self, capsys):
        assert VECTORS.exists(), "golden-vektör dosyası repoda yok"
        rc = tav.run_vectors(str(VECTORS))
        out = capsys.readouterr().out
        assert rc == 0
        assert "RESULT: 7/7" in out
        assert out.count("PASS:") == 7 and "FAIL:" not in out

    def test_flipped_expectation_is_detected(self, tmp_path, capsys):
        doc = json.loads(VECTORS.read_text(encoding="utf-8"))
        doc["vectors"][0]["expect_ok"] = not doc["vectors"][0]["expect_ok"]
        p = tmp_path / "flipped.json"
        p.write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")
        rc = tav.run_vectors(str(p))
        out = capsys.readouterr().out
        assert rc == 1
        assert "FAIL:" in out
        assert doc["vectors"][0]["name"] in out

    def test_wrong_expected_reason_is_detected(self, tmp_path, capsys):
        doc = json.loads(VECTORS.read_text(encoding="utf-8"))
        forged = next(v for v in doc["vectors"] if not v["expect_ok"])
        forged["expect_reason"] = "baska-bir-reason"
        p = tmp_path / "wrongreason.json"
        p.write_text(json.dumps(doc, ensure_ascii=False), encoding="utf-8")
        rc = tav.run_vectors(str(p))
        assert rc == 1
        assert "FAIL:" in capsys.readouterr().out

    def test_none_expected_reason_matches_ok(self, tmp_path, capsys):
        """expect_reason None → "ok" ile karşılaştırılır; GREEN vektörlerin
        referans-hüküm-reason'u budur. Doğrulanmış gerçek bir vektör (a1)
        tekrar-kullanılır — imza gerçek, sadece beklenti-satırı çıkarıldı."""
        doc = json.loads(VECTORS.read_text(encoding="utf-8"))
        a1 = dict(next(v for v in doc["vectors"] if v["name"] == "a1"))
        assert a1["expect_ok"] is True and a1["expect_reason"] is None
        p = tmp_path / "green-none-reason.json"
        p.write_text(json.dumps({"vectors": [a1]}, ensure_ascii=False), encoding="utf-8")
        rc = tav.run_vectors(str(p))
        assert rc == 0
        assert "RESULT: 1/1" in capsys.readouterr().out

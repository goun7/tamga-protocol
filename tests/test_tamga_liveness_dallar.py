"""tamga_liveness dal-kesen testleri — tek-komut canlılık-sondası (üç-sonuç).

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory — GERÇEK-AĞ YOK; urllib.request.urlopen monkeypatch
ile stub'lanır (JSON-RPC yanıtları bellekte üretilir), dosya-yazımı YOK.

DALLAR (3-fonksiyon):
  _rpc  : jsonrpc-2.0 POST + 30sn-timeout; result-döner; 'error'-anahtarı /
          result None/'0x'/'' → RuntimeError; urlopen-hatası yayılır
  probe : latest-okunamaz → İNDETERMİNE rc2 (evaluated:False); head=0 → RED rc1
          (jenezis: ilerleme-kanıtlanamaz); max_age_blocks=0 → rc2
          (salt-okuma, eşik-yok); eşik-öncesi-blok-okunamaz → rc2
          (evaluated:False); span<K → rc2 ('fark-yetersiz'); span>=K → GREEN rc0;
          rpc_kind: localhost/127.0.0.1 → 'local', yoksa 'public'
  main  : --rpc/--max-age-blocks argümanları; JSON stdout'a, insan-satırı
          stderr'e; dönüş-probe rc'si; bilinmeyen-argüman → SystemExit
  ORTAM-QUIRK: result dict-değilse (örn. string) veya 'number'-anahtarı-yoksa
          TypeError/KeyError probe'dan KORUNMADAN yayılır (karakterizasyon)
"""
from __future__ import annotations

import json
import sys

import pytest

sys.path.insert(0, ".")

import tamga_liveness as tl  # noqa: E402

GREEN, RED, IND = 0, 1, 2


# == yardımcılar ============================================================================

class _Yanit:
    """urllib dönen-benzeri: read() JSON-bayt-döner."""

    def __init__(self, payload):
        self.payload = payload

    def read(self):
        return json.dumps(self.payload).encode()


def _urlopen_stub(fn):
    """fn(method, params) -> deger | Exception (raise). Değer zaten zarfsa
    (result/error/jsonrpc anahtarı var) olduğu-gibi, değilse {'result': deger}
    zarfına-sarılır. Çağrıları kaydeder."""
    durum = {"calls": []}

    def _u(req, timeout=None):
        govde = json.loads(req.data.decode())
        durum["calls"].append({"govde": govde, "timeout": timeout,
                               "req": req})
        sonuc = fn(govde.get("method"), govde.get("params"))
        if isinstance(sonuc, Exception):
            raise sonuc
        if isinstance(sonuc, dict) and ("result" in sonuc or "error" in sonuc
                                        or "jsonrpc" in sonuc):
            payload = sonuc                     # zaten JSON-RPC-zarfı
        else:
            payload = {"jsonrpc": "2.0", "id": 1, "result": sonuc}
        return _Yanit(payload)

    _u.durum = durum
    return _u


def _blok(number_hex, **over):
    d = {"number": number_hex, "hash": "0x" + "ab" * 32,
         "timestamp": "0x65f0a1b2"}
    d.update(over)
    return d


def _iki_blok(head, k, past_ok=True):
    """head → latest; head-k → eşik-öncesi (past_ok False → hata)."""
    def _fn(method, params):
        if method != "eth_getBlockByNumber":
            return RuntimeError(f"beklenmeyen-method {method}")
        p = params[0] if params else None
        if p == "latest":
            return _blok(hex(head))
        if past_ok and int(p, 16) == max(head - k, 0):
            return _blok(hex(max(head - k, 0)))
        return RuntimeError("beklenmeyen-blok-param")
    return _fn


@pytest.fixture
def rpc(monkeypatch):
    """urlopen'u stub'la; test ucu olarak da geri-döner."""
    kutu = {}

    def _yerlestir(fn):
        stub = _urlopen_stub(fn)
        monkeypatch.setattr("urllib.request.urlopen", stub)
        kutu["stub"] = stub
        return stub

    kutu["koy"] = _yerlestir
    return kutu


# == _rpc =====================================================================================

class TestRpc:
    def test_result_doner(self, rpc):
        rpc["koy"](lambda m, p: {"number": "0x64"})
        assert tl._rpc("http://x", "eth_getBlockByNumber", ["latest", False]) \
            == {"number": "0x64"}

    def test_jsonrpc_govdesi_dogru(self, rpc):
        stub = rpc["koy"](lambda m, p: {"number": "0x1"})
        tl._rpc("http://x", "eth_getBlockByNumber", ["0x1", False])
        g = stub.durum["calls"][0]["govde"]
        assert g == {"jsonrpc": "2.0", "id": 1,
                     "method": "eth_getBlockByNumber",
                     "params": ["0x1", False]}

    def test_content_type_ve_user_agent(self, rpc):
        stub = rpc["koy"](lambda m, p: {"number": "0x1"})
        tl._rpc("http://x", "eth_getBlockByNumber", ["latest", False])
        req = stub.durum["calls"][0]["req"]
        assert req.get_header("Content-type") == "application/json"
        assert req.get_header("User-agent") == "tamga-liveness-probe/1"

    def test_timeout_30(self, rpc):
        stub = rpc["koy"](lambda m, p: {"number": "0x1"})
        tl._rpc("http://x", "eth_getBlockByNumber", ["latest", False])
        assert stub.durum["calls"][0]["timeout"] == 30

    def test_error_anahtari_runtime_error(self, rpc):
        rpc["koy"](lambda m, p: {"error": {"code": -32000, "message": "yok"}})
        with pytest.raises(RuntimeError, match="RPC error"):
            tl._rpc("http://x", "eth_getBlockByNumber", ["latest", False])

    @pytest.mark.parametrize("kotu", [None, "0x", ""])
    def test_bos_sonuc_runtime_error(self, rpc, kotu):
        rpc["koy"](lambda m, p: {"result": kotu})
        with pytest.raises(RuntimeError, match="boş yanıt"):
            tl._rpc("http://x", "eth_getBlockByNumber", ["latest", False])

    def test_result_anahtari_yok_runtime_error(self, rpc):
        rpc["koy"](lambda m, p: {"jsonrpc": "2.0", "id": 1})
        with pytest.raises(RuntimeError, match="boş yanıt"):
            tl._rpc("http://x", "eth_getBlockByNumber", ["latest", False])

    def test_urlopen_hatasi_yayilir(self, rpc):
        rpc["koy"](lambda m, p: ConnectionError("bağlantı-yok"))
        with pytest.raises(ConnectionError):
            tl._rpc("http://x", "eth_getBlockByNumber", ["latest", False])

    def test_sifir_int_sonuc_kabul(self, rpc):
        """0 'boş' listesinde DEĞİL → döner (probe'da patlar — bkz. aşağı)."""
        rpc["koy"](lambda m, p: {"result": 0})
        assert tl._rpc("http://x", "m", []) == 0


# == probe: GREEN ============================================================================

class TestProbeGreen:
    def test_span_esit_esik_green(self, rpc):
        rpc["koy"](_iki_blok(100, 10))
        rc, out = tl.probe("http://x", 10)
        assert rc == GREEN and out["verdict"] == "GREEN"
        assert out["head"] == 100
        assert out["blocks_since_threshold"] == 10

    def test_span_esikten_buyuk_green(self, rpc):
        """eşik-öncesi-blok K'dan DAHA geride → span>K → GREEN."""
        def _fn(method, params):
            if params[0] == "latest":
                return _blok(hex(100))
            return _blok(hex(80))          # span=20 > 5
        rpc["koy"](_fn)
        rc, out = tl.probe("http://x", 5)
        assert rc == GREEN and out["blocks_since_threshold"] == 20

    def test_reason_ilerleme_soylemi(self, rpc):
        rpc["koy"](_iki_blok(42, 10))
        _rc, out = tl.probe("http://x", 10)
        assert "en az 10 blok" in out["reason"].replace("-", " ") and "42" in out["reason"]

    def test_evaluated_true_green_yolda(self, rpc):
        rpc["koy"](_iki_blok(100, 10))
        _rc, out = tl.probe("http://x", 10)
        assert out["evaluated"] is True

    def test_claim_alani_dururluk_siniri(self, rpc):
        rpc["koy"](_iki_blok(100, 10))
        _rc, out = tl.probe("http://x", 10)
        assert "konsensüs" in out["claim"] and "DEĞİLDİR" in out["claim"]


# == probe: RED ==============================================================================

class TestProbeRed:
    def test_head_sifir_red_jenezis(self, rpc):
        rpc["koy"](_iki_blok(0, 10))
        rc, out = tl.probe("http://x", 10)
        assert rc == RED and out["verdict"] == "RED"
        assert out["head"] == 0
        assert "blok-üretmedi" in out["reason"] and out["head"] == 0

    def test_head_sifir_esik_sifirdan_once(self, rpc):
        """head=0 kontrolü max_age_blocks=0'dan ÖNCE gelir."""
        rpc["koy"](_iki_blok(0, 0))
        rc, out = tl.probe("http://x", 0)
        assert rc == RED and out["head"] == 0


# == probe: İNDETERMİNE =======================================================================

class TestProbeIndeterminate:
    def test_latest_okunamadi_ind(self, rpc):
        rpc["koy"](lambda m, p: ConnectionError("yok"))
        rc, out = tl.probe("http://x", 10)
        assert rc == IND and out["verdict"] == "İNDETERMİNE"
        assert out["evaluated"] is False
        assert "latest-okunamadı" in out["reason"]
        assert "head" not in out

    def test_latest_error_yaniti_ind(self, rpc):
        rpc["koy"](lambda m, p: {"error": {"message": "rate-limit"}})
        rc, out = tl.probe("http://x", 10)
        assert rc == IND and out["evaluated"] is False

    def test_esik_oncesi_okunamadi_ind(self, rpc):
        def _fn(method, params):
            if params and params[0] == "latest":
                return _blok(hex(100))
            return ConnectionError("esik-blok-yok")
        rpc["koy"](_fn)
        rc, out = tl.probe("http://x", 10)
        assert rc == IND and out["evaluated"] is False
        assert "eşik-öncesi-blok okunamadı" in out["reason"]
        assert out["head"] == 100

    def test_max_age_blocks_sifir_salt_okuma(self, rpc):
        rpc["koy"](_iki_blok(100, 0))
        rc, out = tl.probe("http://x", 0)
        assert rc == IND and out["verdict"] == "İNDETERMİNE"
        assert out["evaluated"] is True
        assert "eşik-tanım-sız" in out["reason"]
        assert "blocks_since_threshold" not in out

    @pytest.mark.parametrize("head,k", [(100, 200), (5, 10), (10, 11), (1, 10)])
    def test_fark_yetersiz_ind(self, rpc, head, k):
        """head < K → span=head < K (max(head-K,0)=0) → ilerleme-kanıtlanamaz."""
        rpc["koy"](_iki_blok(head, k))
        rc, out = tl.probe("http://x", k)
        assert rc == IND
        assert "fark-yetersiz" in out["reason"]
        assert out["blocks_since_threshold"] == head

    def test_fark_bir_eksik_ind(self, rpc):
        """span = K-1 → İNDETERMİNE (K-blok ilerleme KANITLANAMADI)."""
        def _fn(method, params):
            if params[0] == "latest":
                return _blok(hex(100))
            return _blok(hex(91))          # span=9 < 10
        rpc["koy"](_fn)
        rc, out = tl.probe("http://x", 10)
        assert rc == IND and out["blocks_since_threshold"] == 9


# == probe: yapı/yan-etkiler ==================================================================

class TestProbeYapi:
    @pytest.mark.parametrize("url,beklenen", [
        ("https://ethereum-sepolia-rpc.publicnode.com", "public"),
        ("http://localhost:8545", "local"),
        ("http://127.0.0.1:8545", "local"),
        ("http://localhost:8545/", "local"),
        ("http://192.168.1.10:8545", "public"),
        ("https://rpc.localhost.xyz", "local"),
    ])
    def test_rpc_kind(self, rpc, url, beklenen):
        rpc["koy"](_iki_blok(100, 10))
        _rc, out = tl.probe(url, 10)
        assert out["rpc_kind"] == beklenen

    def test_sabit_alanlar(self, rpc):
        rpc["koy"](_iki_blok(100, 10))
        _rc, out = tl.probe("http://x", 10)
        assert out["probe"] == "liveness"
        assert out["max_age_blocks"] == 10
        assert set(out) >= {"probe", "rpc_kind", "max_age_blocks", "evaluated",
                            "claim", "verdict", "reason"}

    def test_en_az_iki_rpc_cagrisi_green(self, rpc):
        stub = rpc["koy"](_iki_blok(100, 10))
        tl.probe("http://x", 10)
        assert len(stub.durum["calls"]) == 2
        methodlar = [c["govde"]["method"] for c in stub.durum["calls"]]
        assert methodlar == ["eth_getBlockByNumber"] * 2
        assert stub.durum["calls"][1]["govde"]["params"][0] == hex(90)

    def test_iki_cagri_esik_hatasinda_da(self, rpc):
        stub = rpc["koy"](_iki_blok(100, 10, past_ok=False))
        tl.probe("http://x", 10)
        assert len(stub.durum["calls"]) == 2

    def test_birinci_arama_latest(self, rpc):
        stub = rpc["koy"](_iki_blok(100, 10))
        tl.probe("http://x", 10)
        assert stub.durum["calls"][0]["govde"]["params"] == ["latest", False]

    def test_sonuc_dict_degilse_typeerror_yayilir(self, rpc):
        """ORTAM-QUIRK: _rpc string'i kabul eder, probe'da ['number'] patlar."""
        rpc["koy"](lambda m, p: "0xabc")
        with pytest.raises(TypeError):
            tl.probe("http://x", 10)

    def test_number_anahtari_yok_keyerror_yayilir(self, rpc):
        """ORTAM-QUIRK: dict-ama-number-yok → KeyError (korumasız-dal)."""
        rpc["koy"](lambda m, p: {"hash": "0x" + "cd" * 32})
        with pytest.raises(KeyError):
            tl.probe("http://x", 10)

    def test_number_int_degilse_valueerror_yayilir(self, rpc):
        rpc["koy"](lambda m, p: {"number": "merhaba"})
        with pytest.raises(ValueError):
            tl.probe("http://x", 10)

    def test_buyuk_head_hex_cozulur(self, rpc):
        buyuk = 2 ** 32
        rpc["koy"](_iki_blok(buyuk, 100))
        rc, out = tl.probe("http://x", 100)
        assert rc == GREEN and out["head"] == buyuk


# == main =====================================================================================

class TestMain:
    def test_yesil_rc0(self, rpc, capsys):
        rpc["koy"](_iki_blok(100, 10))
        assert tl.main(["--rpc", "http://x", "--max-age-blocks", "10"]) == 0

    def test_stdout_tek_satir_json(self, rpc, capsys):
        rpc["koy"](_iki_blok(100, 10))
        tl.main(["--rpc", "http://x", "--max-age-blocks", "10"])
        out, err = capsys.readouterr()
        ver = json.loads(out.strip().splitlines()[-1])
        assert ver["verdict"] == "GREEN"

    def test_stderr_insan_satiri(self, rpc, capsys):
        rpc["koy"](_iki_blok(100, 10))
        tl.main(["--rpc", "http://x", "--max-age-blocks", "10"])
        out, err = capsys.readouterr()
        assert "[GREEN]" in err and "en-az 10 blok" in err

    def test_red_rc1(self, rpc, capsys):
        rpc["koy"](_iki_blok(0, 10))
        assert tl.main(["--rpc", "http://x", "--max-age-blocks", "10"]) == 1
        assert "[RED]" in capsys.readouterr().err

    def test_ind_rc2(self, rpc, capsys):
        rpc["koy"](lambda m, p: ConnectionError("yok"))
        assert tl.main(["--rpc", "http://x", "--max-age-blocks", "10"]) == 2
        assert "[İNDETERMİNE]" in capsys.readouterr().err

    def test_varsayilan_rpc_url_publicnode(self, rpc):
        """--rpc verilmezse default publicnode-sepolia'ya gider (stub-tutar)."""
        stub = rpc["koy"](_iki_blok(100, 10))
        rc = tl.main(["--max-age-blocks", "10"])
        assert rc == 0
        assert stub.durum["calls"][0]["req"].full_url == \
            "https://ethereum-sepolia-rpc.publicnode.com"

    def test_bilinmeyen_arguman_systemexit(self, capsys):
        with pytest.raises(SystemExit):
            tl.main(["--rpc", "http://x", "--max-age-blocks", "10", "--baska"])

    def test_help_systemexit_sifir(self, capsys):
        with pytest.raises(SystemExit) as e:
            tl.main(["--help"])
        assert e.value.code == 0
        assert "liveness" in capsys.readouterr().out

    def test_negatif_esik_red_degil_ind(self, rpc):
        """max_age_blocks<0: hex(head-(-K))=head+|K| > head → RPC'de yok →
        eşik-öncesi-blok okunamadı → İNDETERMİNE (sessiz-RED değil)."""
        def _fn(method, params):
            if params[0] == "latest":
                return _blok(hex(100))
            return RuntimeError("block height not found")
        rpc["koy"](_fn)
        rc, out = tl.probe("http://x", -5)
        assert rc == IND
        assert "eşik-öncesi-blok okunamadı" in out["reason"]

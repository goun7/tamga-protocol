"""tamga_project_head dal-kesen testleri — chain-head → batch-leaf izdüşümü.

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory — alt-süreç/gerçek-paket YOK; ledger.jsonl'ler
tmp_path'te üretilir, -o çıktıları tmp_path'e yazılır.

DALLAR (4-fonksiyon):
  chain_head : ledger.jsonl D5-yeniden-oynar → (head, lines); defter-yok →
               ValueError; boş/yalnız-boş-satır → ("0"*64, 0); kayıt-nesne-
               değil → ValueError; prev/h/seq uyuşmazlığı →
               'zincir-kırık (reason-14): broken@N'; node_sig HASH-DIŞINDA;
               ekstra-anahtarlara izin-var
  project    : head-hex → {'projection_version':'TAMGA_PROJECT_HEAD_V1', ...};
               leaf = '0x' + k256(k256(bytes.fromhex(head))).hex();
               geçersiz-hex → ValueError ('' boş-digest GEÇERLİ — sınır)
  main       : pkg konumsal + -o/--out; hata-yakala (ValueError/AttributeError/
               TypeError/KeyError) → 'RED: {e}' stderr rc1; başarı → JSON stdout
               veya dosya + 'OK: ...' rc0; -o içermeyen-dizin → FileNotFoundError
               (try-DIŞINDA — korumasız yayılır)
  K (lambda) : keccak256 → bytes.fromhex → bytes (ara-adım karakterizasyonu)
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import sys

import pytest

sys.path.insert(0, ".")

import tamga_project_head as tph  # noqa: E402
from tamga_keccak import keccak256  # noqa: E402
from tamga_validator import jcs as jcs_v  # noqa: E402

GENESIS = "0" * 64


# == yardımcılar ============================================================================

def _h(prev, no_h):
    """D5: h = sha256(prev.encode() + jcs(h+node_sig-haric))."""
    j = jcs_v(no_h)
    j = j.encode() if isinstance(j, str) else j
    return hashlib.sha256(prev.encode("utf-8") + j).hexdigest()


def _zincir(adet, node_sig=None, **over):
    """Geçerli D5-zinciri; node_sig verilse bile hash-DIŞINDA kalır."""
    prev, out = GENESIS, []
    for i in range(1, adet + 1):
        no_h = {"seq": i, "op": "note", "prev": prev, "n": i}
        no_h.update(over)
        rec = {**no_h, "h": _h(prev, no_h)}
        if node_sig is not None:
            rec["node_sig"] = node_sig
        out.append(rec)
        prev = rec["h"]
    return out


def _paket(tmp_path, kayitlar=None, ham=None):
    pkg = tmp_path / "paket"
    pkg.mkdir()
    f = pkg / "ledger.jsonl"
    if ham is not None:
        f.write_text(ham, encoding="utf-8")
    else:
        f.write_text("".join(json.dumps(r) + "\n" for r in (kayitlar or [])),
                     encoding="utf-8")
    return pkg


@pytest.fixture(autouse=True)
def _sys_path_koruma():
    """modül importta sys.path'e repo-kökü ekler — geri al."""
    sp = list(sys.path)
    yield
    sys.path[:] = sp


# == K (lambda) ==============================================================================

class TestKFonksiyonu:
    def test_keccak_sonu_hex_bytes(self):
        """K: keccak256(b) → .hex() → bytes.fromhex → bytes — girdi-aynısı."""
        raw = bytes(range(32))
        assert tph.K(raw) == bytes.fromhex(keccak256(raw).hex())

    def test_cikti_32_byte(self):
        assert len(tph.K(b"abc")) == 32

    def test_girdiye_duyarli_avalanche(self):
        assert tph.K(b"a") != tph.K(b"b")

    def test_bos_girdi_sabit(self):
        assert tph.K(b"") == bytes.fromhex(keccak256(b"").hex())

    def test_ikili_uygulama_girdi_uyumsuz(self):
        """K(K(x)) ≠ K(x) — çift-sıkıştırma farklı-digest."""
        raw = bytes(range(32))
        assert tph.K(tph.K(raw)) != tph.K(raw)


# == chain_head: başarı ======================================================================

class TestChainHeadYesil:
    def test_tek_kayit(self, tmp_path):
        z = _zincir(1)
        head, n = tph.chain_head(_paket(tmp_path, z))
        assert head == z[0]["h"] and n == 1

    def test_uc_kayit_head_sonuncudur(self, tmp_path):
        z = _zincir(3)
        head, n = tph.chain_head(_paket(tmp_path, z))
        assert head == z[-1]["h"] and n == 3

    def test_bosluk_satirlari_atlanir(self, tmp_path):
        z = _zincir(2)
        pkg = _paket(tmp_path, z, ham=json.dumps(z[0]) + "\n\n" +
                     json.dumps(z[1]) + "\n   \n")
        head, n = tph.chain_head(pkg)
        assert head == z[-1]["h"] and n == 2

    def test_node_sig_hash_disinda(self, tmp_path):
        """node_sig anahtarı jcs-girdisine DAHİL EDİLMEZ — aynı head."""
        z = _zincir(2, node_sig="ed25519-imza-burada")
        head, n = tph.chain_head(_paket(tmp_path, z))
        assert head == _zincir(2)[-1]["h"] and n == 2

    def test_ekstra_anahtara_izin(self, tmp_path):
        z = _zincir(2, extra="veri", sayi=99)
        head, n = tph.chain_head(_paket(tmp_path, z))
        assert head == z[-1]["h"] and n == 2

    def test_h_formulu_tekrar_uretilebilir(self, tmp_path):
        z = _zincir(4, op="farklı")
        head, _n = tph.chain_head(_paket(tmp_path, z))
        prev = GENESIS
        for i, rec in enumerate(z, 1):
            no_h = {k: v for k, v in rec.items() if k not in ("h", "node_sig")}
            assert rec["h"] == _h(prev, no_h)
            assert rec["prev"] == prev and rec["seq"] == i
            prev = rec["h"]
        assert head == prev

    def test_bos_defter_jenezis_doner(self, tmp_path):
        head, n = tph.chain_head(_paket(tmp_path, ham=""))
        assert head == GENESIS and n == 0

    def test_yalniz_bosluk_defteri(self, tmp_path):
        head, n = tph.chain_head(_paket(tmp_path, ham="\n\n   \n\t\n"))
        assert head == GENESIS and n == 0

    def test_bosluklu_hex_gecerli(self, tmp_path):
        """kayıt-içi hex-değerlerin boşlukları tolerated (jcs-saf)."""
        z = _zincir(1, wid="0123 4567")
        head, n = tph.chain_head(_paket(tmp_path, z))
        assert head == z[-1]["h"] and n == 1


# == chain_head: başarısızlık =================================================================

class TestChainHeadKirmizi:
    def test_defter_yok(self, tmp_path):
        pkg = tmp_path / "bos"
        pkg.mkdir()
        with pytest.raises(ValueError, match="defter-yok") as e:
            tph.chain_head(pkg)
        assert "ledger.jsonl" in str(e.value)

    def test_paket_yok(self, tmp_path):
        with pytest.raises(ValueError, match="defter-yok"):
            tph.chain_head(tmp_path / "hiç-yok")

    def test_paket_bir_dosya(self, tmp_path):
        f = tmp_path / "bir-dosya"
        f.write_text("içerik", encoding="utf-8")
        with pytest.raises(ValueError, match="defter-yok"):
            tph.chain_head(f)

    def test_defter_bir_dizin(self, tmp_path):
        pkg = tmp_path / "paket"
        (pkg / "ledger.jsonl").mkdir(parents=True)
        with pytest.raises(ValueError, match="defter-yok"):
            tph.chain_head(pkg)

    @pytest.mark.parametrize("kotu", ["[1,2]", "42", '"metin"', "null", "true"])
    def test_kayit_nesne_degil(self, tmp_path, kotu):
        with pytest.raises(ValueError, match="nesne değil") as e:
            tph.chain_head(_paket(tmp_path, ham=kotu + "\n"))
        assert "satır 1" in str(e.value)

    def test_ikinci_satir_nesne_degil_sira_2(self, tmp_path):
        z = _zincir(1)
        with pytest.raises(ValueError, match="nesne değil") as e:
            tph.chain_head(_paket(tmp_path, ham=json.dumps(z[0]) + "\n42\n"))
        assert "satır 2" in str(e.value)

    def test_prev_zinciri_kirik_broken_at_2(self, tmp_path):
        z = _zincir(2)
        z[1]["prev"] = "f" * 64
        with pytest.raises(ValueError, match="zincir-kırık") as e:
            tph.chain_head(_paket(tmp_path, z))
        assert "broken@2" in str(e.value)

    def test_h_yanlis_broken_at_1(self, tmp_path):
        z = _zincir(1)
        z[0]["h"] = "a" * 64
        with pytest.raises(ValueError, match="broken@1"):
            tph.chain_head(_paket(tmp_path, z))

    def test_seq_yer_zamanli_broken_at_3(self, tmp_path):
        z = _zincir(3)
        z[2]["seq"] = 4
        with pytest.raises(ValueError, match="broken@3"):
            tph.chain_head(_paket(tmp_path, z))

    def test_seq_bir_degil_broken_at_1(self, tmp_path):
        z = _zincir(1)
        z[0]["seq"] = 0
        with pytest.raises(ValueError, match="broken@1"):
            tph.chain_head(_paket(tmp_path, z))

    def test_prev_eksik_broken_at_1(self, tmp_path):
        z = _zincir(1)
        del z[0]["prev"]
        with pytest.raises(ValueError, match="broken@1"):
            tph.chain_head(_paket(tmp_path, z))

    def test_h_eksik_broken_at_1(self, tmp_path):
        z = _zincir(1)
        del z[0]["h"]
        with pytest.raises(ValueError, match="broken@1"):
            tph.chain_head(_paket(tmp_path, z))

    def test_seq_eksik_broken_at_1(self, tmp_path):
        z = _zincir(1)
        del z[0]["seq"]
        with pytest.raises(ValueError, match="broken@1"):
            tph.chain_head(_paket(tmp_path, z))

    def test_prev_kisa_broken_at_1(self, tmp_path):
        z = _zincir(1)
        z[0]["prev"] = "0" * 63
        with pytest.raises(ValueError, match="broken@1"):
            tph.chain_head(_paket(tmp_path, z))

    def test_json_bozuk_jsondecodeerror(self, tmp_path):
        """JSONDecodeError ValueError ALT-sınıfı — zincir-hatası DEĞIL."""
        with pytest.raises(json.JSONDecodeError):
            tph.chain_head(_paket(tmp_path, ham="{bozuk\n"))

    def test_hesap_bozuk_broken_at_1(self, tmp_path):
        """h-formülü elle-bozulunca (değişen 'n' ama h-eski) broken@1."""
        z = _zincir(1)
        z[0]["n"] = 99
        with pytest.raises(ValueError, match="broken@1"):
            tph.chain_head(_paket(tmp_path, z))

    def test_ara_kayit_kirik_head_ileride_degil(self, tmp_path):
        """kırık 2. satırdaysa 3. satır OKUMAZ — fail-closed."""
        z = _zincir(3)
        z[1]["h"] = "b" * 64
        with pytest.raises(ValueError, match="broken@2"):
            tph.chain_head(_paket(tmp_path, z))


# == project ==================================================================================

class TestProject:
    def test_sabit_alanlar(self):
        d = tph.project(GENESIS)
        assert d["projection_version"] == "TAMGA_PROJECT_HEAD_V1"
        assert d["chain_head"] == GENESIS
        assert "sha256" in d["digest_family"]
        assert "keccak256(keccak256(" in d["leaf_encoding"]
        assert "presentation-only" in d["honest_boundary"]

    def test_leaf_formulu_cift_keccak(self):
        head = "ab" * 32
        d = tph.project(head)
        raw = bytes.fromhex(head)
        beklenen = "0x" + bytes.fromhex(
            keccak256(bytes.fromhex(keccak256(raw).hex())).hex()).hex()
        assert d["leaf_encoded"] == beklenen

    def test_leaf_0x_on_ekli(self):
        assert tph.project(GENESIS)["leaf_encoded"].startswith("0x")

    def test_leaf_128_hex_karakter(self):
        assert len(tph.project(GENESIS)["leaf_encoded"]) == 2 + 64

    def test_leaf_icerige_duyarli(self):
        a = tph.project("11" * 32)
        b = tph.project("22" * 32)
        assert a["leaf_encoded"] != b["leaf_encoded"]

    def test_chain_head_olduğu_gibi_yazilir(self):
        head = "deadbeef" + "00" * 30
        assert tph.project(head)["chain_head"] == head

    def test_basinda_sifir_korunur(self):
        """'0x' öneki + tam-hex — baştaki-sıfırlar KESİLMEZ."""
        d = tph.project("00" * 32)
        assert d["leaf_encoded"][2:4] != "" and len(d["leaf_encoded"]) == 66

    def test_buyuk_harf_hex_kabul(self):
        """bytes.fromhex büyük-harf kabul-eder — izdüşüm aynı."""
        kucuk = tph.project("ab" * 32)["leaf_encoded"]
        buyuk = tph.project("AB" * 32)["leaf_encoded"]
        assert kucuk == buyuk

    def test_bos_string_bos_digest_gecerli(self):
        """ORTAM-SINIR: project('') → bytes.fromhex('')=b'' → K(K(b''))."""
        d = tph.project("")
        assert d["chain_head"] == ""
        assert d["leaf_encoded"] == "0x" + bytes.fromhex(
            keccak256(bytes.fromhex(keccak256(b"").hex())).hex()).hex()

    @pytest.mark.parametrize("kotu", ["abc", "0" * 63, "0" * 65, "gg" * 32, "0"])
    def test_gecersiz_hex_valueerror(self, kotu):
        with pytest.raises(ValueError):
            tph.project(kotu)

    def test_json_serilesir_ascii_disi_korunur(self):
        """ana-değerlerde Türkçe-ünlü var — ensure_ascii=False (main'de)."""
        d = tph.project(GENESIS)
        assert "DEĞİL" in d["digest_family"]


# == main =====================================================================================

class TestMain:
    def test_yesil_stdout_json(self, tmp_path, capsys):
        z = _zincir(2)
        rc = tph.main([str(_paket(tmp_path, z))])
        out, _err = capsys.readouterr()
        ver = json.loads(out)
        assert rc == 0
        assert ver["chain_head"] == z[-1]["h"]
        assert ver["ledger_lines"] == 2
        assert ver["projection_version"] == "TAMGA_PROJECT_HEAD_V1"

    def test_cikti_alanlari_tam(self, tmp_path, capsys):
        z = _zincir(1)
        tph.main([str(_paket(tmp_path, z))])
        ver = json.loads(capsys.readouterr().out)
        assert set(ver) == {"projection_version", "chain_head", "digest_family",
                            "leaf_encoded", "leaf_encoding",
                            "honest_boundary", "ledger_lines"}

    def test_cikti_dosyasi_ok(self, tmp_path, capsys):
        z = _zincir(3)
        hedef = tmp_path / "head.json"
        rc = tph.main([str(_paket(tmp_path, z)), "-o", str(hedef)])
        out = capsys.readouterr().out
        assert rc == 0
        assert hedef.is_file()
        assert json.loads(hedef.read_text(encoding="utf-8"))["ledger_lines"] == 3
        assert "OK:" in out and "3 kayıt" in out

    def test_cikti_mesaji_head_on_ekini_icerir(self, tmp_path, capsys):
        z = _zincir(5)
        hedef = tmp_path / "h.json"
        tph.main([str(_paket(tmp_path, z)), "--out", str(hedef)])
        out = capsys.readouterr().out
        assert f"OK: {hedef}" in out
        assert "…, 5 kayıt" in out

    def test_cikti_dosyasi_json_govdesi_ayni(self, tmp_path):
        z = _zincir(2)
        hedef = tmp_path / "h.json"
        tph.main([str(_paket(tmp_path, z)), "-o", str(hedef)])
        from_dosya = json.loads(hedef.read_text(encoding="utf-8"))
        from_dosya.pop("ledger_lines")
        assert from_dosya == tph.project(z[-1]["h"])

    def test_defter_yok_red_rc1(self, tmp_path, capsys):
        pkg = tmp_path / "yok"
        pkg.mkdir()
        rc = tph.main([str(pkg)])
        out, err = capsys.readouterr()
        assert rc == 1 and out == ""
        assert "RED: defter-yok" in err

    def test_paket_yok_red_rc1(self, tmp_path, capsys):
        rc = tph.main([str(tmp_path / "hiç-yok")])
        assert rc == 1
        assert "RED:" in capsys.readouterr().err

    def test_zincir_kirik_red_rc1(self, tmp_path, capsys):
        z = _zincir(2)
        z[1]["prev"] = "f" * 64
        rc = tph.main([str(_paket(tmp_path, z))])
        assert rc == 1
        assert "RED: zincir-kırık" in capsys.readouterr().err

    def test_nesne_degil_red_rc1(self, tmp_path, capsys):
        rc = tph.main([str(_paket(tmp_path, ham="42\n"))])
        assert rc == 1
        assert "nesne değil" in capsys.readouterr().err

    def test_json_bozuk_red_rc1(self, tmp_path, capsys):
        rc = tph.main([str(_paket(tmp_path, ham="{bozuk\n"))])
        assert rc == 1
        assert "RED:" in capsys.readouterr().err

    def test_bos_defter_yesil_jenezis(self, tmp_path, capsys):
        """boş defter HATA DEĞİL — head=jenezis, lines=0."""
        rc = tph.main([str(_paket(tmp_path, ham=""))])
        ver = json.loads(capsys.readouterr().out)
        assert rc == 0
        assert ver["chain_head"] == GENESIS and ver["ledger_lines"] == 0

    def test_cikta_icermeyen_dizin_file_not_found(self, tmp_path):
        """ORTAM-QUIRK: -o'nun dizini yoksa write_text try-DIŞINDA patlar."""
        z = _zincir(1)
        hedef = tmp_path / "yok-dizin" / "h.json"
        with pytest.raises(FileNotFoundError):
            tph.main([str(_paket(tmp_path, z)), "-o", str(hedef)])

    def test_pkg_argumani_yok_systemexit(self, capsys):
        with pytest.raises(SystemExit):
            tph.main([])

    def test_help_systemexit_sifir(self, capsys):
        with pytest.raises(SystemExit) as e:
            tph.main(["--help"])
        assert e.value.code == 0
        assert "batch-leaf" in capsys.readouterr().out

    def test_bilinmeyen_arguman_systemexit(self, capsys):
        with pytest.raises(SystemExit):
            tph.main([str(pathlib.Path(".")), "--baska"])

    def test_argv_none_sistem_argv_kullanilir(self, monkeypatch, tmp_path, capsys):
        """argv=None → argparse sys.argv'yi okur (karakterizasyon)."""
        z = _zincir(2)
        pkg = _paket(tmp_path, z)
        monkeypatch.setattr(sys, "argv", ["prog", str(pkg)])
        rc = tph.main(None)
        assert rc == 0
        assert json.loads(capsys.readouterr().out)["ledger_lines"] == 2

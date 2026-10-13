"""tools/settlement_bind_verify dal-kesen testleri — RFC-010 ödeme-zinciri bağlama doğrulayıcısı.

Kural-1: mevcut dosyalara DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory — gerçek ağ/RPC/WASM/subprocess YOK; gerçek-anahtarlı
imzalar saf-python ile üretilir, dış-çağrı YOK, dosya yazımı yalnızca tmp_path.

DALLAR (6-fonksiyon):
  _d5_chain_ok : seq int>=1 + prev/h 64-küçük-hex → True; seq<0/0, tip-hatalı,
                 eksik, uzunluk≠64, BÜYÜK-hex, 0-9a-f-dışı-karakter → False
  _digest      : sha256 → str(hexdigest); diğerleri → keccak256 bayt (str DEĞİL)
  _claim_signer: x402/v1 ecrecover→adres | tamga/native ed25519 (buyer 64hex
                 doğrulanır, yanlış-imza None) | erc8004/v1 keccak(digest).hex()
                 | bilinmeyen-şema None
  _foreign_chain_ok: zincir-adı beyaz-liste + head 64hex + entries int>=1;
                 evidence_link equals/derived-ilişkisi; head_source dosyası
                 çözülür-ve-karşılaştırılır; 'derived'+geçersiz-hex receipt
                 ValueError-FIRLATIR (korunmamış dal — karakterizasyon)
  verify       : 7-kontrol fail-closed; rc1 bind-yok, rc2 bilinmeyen-şema
                 (İNDETERMİNE), rc3 receipt, rc4 imza, rc5 ref, rc6 taraf,
                 rc7 evidenceHash, rc8 yabancı-zincir, rc9 submitter≈payee,
                 rc0 GREEN; büyük/küçük-harf duyarsız adresler
  main         : argc≠3 → doc-bas rc1; GREEN rc0 / RED rc1 / İNDETERMİNE rc2
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import sys

import pytest
from nacl.encoding import HexEncoder
from nacl.signing import SigningKey

sys.path.insert(0, ".")
sys.path.insert(0, "tools")

from tamga_attest_verify import GX, GY, N, _mul  # noqa: E402
from tamga_keccak import keccak256  # noqa: E402

import settlement_bind_verify as sbv  # noqa: E402

GENESIS = "0" * 64
DH_HEX = hashlib.sha256(b"delivery-rfc010").hexdigest()


# == yardımcılar ============================================================================

def _addr(k: int) -> str:
    """secp256k1 gizli-anahtar k → Ethereum-adresi (saf-python)."""
    R = _mul(k, (GX, GY))
    pub = R[0].to_bytes(32, "big") + R[1].to_bytes(32, "big")
    return "0x" + keccak256(pub)[12:].hex()


def _secp_sign(z_hex: str, k: int) -> tuple[str, str]:
    """Gerçek secp256k1 imzala (r,s,v=27|28) → (65-bayt-hex, adres)."""
    z = int(z_hex, 16)
    while True:
        R = _mul(k, (GX, GY))
        if R[0] < N:                     # r = x_R mod N özdeş olmalı (kurtarım-şartı)
            break
        k += 1
    r = R[0] % N
    s = (pow(k, N - 2, N) * (z + r * k)) % N
    v = 27 + (R[1] & 1)
    return (r.to_bytes(32, "big") + s.to_bytes(32, "big") + bytes([v])).hex(), _addr(k)


BUYER_K, SELLER_K, OTHER_K = 12345, 777, 4242
BUYER, SELLER, OTHER = _addr(BUYER_K), _addr(SELLER_K), _addr(OTHER_K)


def _govde(claim: dict) -> str:
    """verify()'in imzasız-gövde formülünün birebir-halı (AT-077 ham-mesaj kaynağı)."""
    return json.dumps({k: v for k, v in claim.items() if k != "signature"},
                      sort_keys=True)


def _charge(**over) -> dict:
    c = {"seq": 1, "prev": "a" * 64, "h": "b" * 64,
         "delivery_hash": {"alg": "sha256", "hex": DH_HEX},
         "settlement_bind": {"scheme": "x402/v1", "payment_id": "pay-42",
                             "payer": BUYER, "payee": SELLER}}
    c.update(over)
    return c


def _claim_body(**over) -> dict:
    cl = {"buyerAddress": BUYER, "sellerAddress": SELLER,
          "settlementRef": "pay-42",
          "evidenceHash": {"alg": "sha256", "hex": DH_HEX}}
    cl.update(over)
    return cl


def _x402_claim(**over) -> dict:
    """x402/v1: imza sha256(gövde)-üzerine EIP-191 secp256k1."""
    cl = _claim_body(**over)
    sig, _a = _secp_sign(hashlib.sha256(_govde(cl).encode()).hexdigest(), BUYER_K)
    cl["signature"] = sig
    return cl


_ED_SEED = bytes(range(32))
_ED = SigningKey(_ED_SEED)
_ED_BUYER = bytes(_ED.verify_key).hex()


def _native_pair(**over):
    """tamga/native: ed25519 imzası sha256(gövde)-ün ham-baytları-üzerine."""
    bind = {"scheme": "tamga/native", "payment_id": "pay-42",
            "payer": _ED_BUYER, "payee": SELLER}
    cl = {"buyerAddress": _ED_BUYER, "sellerAddress": SELLER,
          "settlementRef": "pay-42",
          "evidenceHash": {"alg": "sha256", "hex": DH_HEX}}
    cl.update(over)
    cl["signature"] = _ED.sign(bytes.fromhex(
        hashlib.sha256(_govde(cl).encode()).hexdigest())).signature.hex()
    return bind, cl


_ERC_BUYER = keccak256(bytes.fromhex(DH_HEX)).hex()


def _erc_pair(**over):
    """erc8004/v1: buyer = keccak256(delivery-hash); gövde-özütü DEĞİL."""
    bind = {"scheme": "erc8004/v1", "payment_id": "pay-42",
            "payer": _ERC_BUYER, "payee": SELLER}
    cl = {"buyerAddress": _ERC_BUYER, "sellerAddress": SELLER,
          "settlementRef": "pay-42",
          "evidenceHash": {"alg": "keccak256", "hex": DH_HEX},
          "signature": "deadbeef"}
    cl.update(over)
    return bind, cl


# == _d5_chain_ok ============================================================================

class TestD5ChainOk:
    @pytest.mark.parametrize("seq", [1, 2, 10 ** 6])
    def test_gecerli(self, seq):
        assert sbv._d5_chain_ok({"seq": seq, "prev": "a" * 64, "h": "9" * 64}) is True

    def test_ek_alanlar_ivir_zivir(self):
        r = {"seq": 1, "prev": "0" * 64, "h": "f" * 64, "op": "note", "n": 7}
        assert sbv._d5_chain_ok(r) is True

    @pytest.mark.parametrize("seq", [0, -1, -99])
    def test_seq_sifir_veya_negatif(self, seq):
        assert sbv._d5_chain_ok({"seq": seq, "prev": "a" * 64, "h": "b" * 64}) is False

    @pytest.mark.parametrize("seq", ["1", 1.0, None])
    def test_seq_tip_hatali(self, seq):
        assert sbv._d5_chain_ok({"seq": seq, "prev": "a" * 64, "h": "b" * 64}) is False

    @pytest.mark.parametrize("seq", [True, False])
    def test_seq_bool_intin_alt_siniri_gecerli(self, seq):
        """ORTAM-QUIRK: bool, int'in alt-sınıfı — isinstance(True,int) True;
        True==1 (>=1) → kabul; False==0 (<1) → RED."""
        assert sbv._d5_chain_ok({"seq": seq, "prev": "a" * 64, "h": "b" * 64}) is (seq is True)

    @pytest.mark.parametrize("eksik", ["prev", "h"])
    def test_eksik_prev_veya_h(self, eksik):
        r = {"seq": 1, "prev": "a" * 64, "h": "b" * 64}
        del r[eksik]
        assert sbv._d5_chain_ok(r) is False

    @pytest.mark.parametrize("kotu", [None, 42, ["a" * 64], b"a" * 64])
    def test_prev_tip_hatali(self, kotu):
        assert sbv._d5_chain_ok({"seq": 1, "prev": kotu, "h": "b" * 64}) is False

    @pytest.mark.parametrize("uzunluk", [0, 1, 63, 65, 128])
    def test_uzunluk_64_degil(self, uzunluk):
        s = "a" * uzunluk
        assert sbv._d5_chain_ok({"seq": 1, "prev": s, "h": "b" * 64}) is False
        assert sbv._d5_chain_ok({"seq": 1, "prev": "a" * 64, "h": s}) is False

    def test_buyuk_har_hex_reddedilir(self):
        """yalnızca 0-9a-f — 'A'*64 geçmez."""
        assert sbv._d5_chain_ok({"seq": 1, "prev": "A" * 64, "h": "b" * 64}) is False
        assert sbv._d5_chain_ok({"seq": 1, "prev": "a" * 64, "h": "g" * 64}) is False

    def test_hex_olmayan_karakter(self):
        bad = "a" * 63 + "z"
        assert sbv._d5_chain_ok({"seq": 1, "prev": bad, "h": "b" * 64}) is False

    def test_bos_sozluk(self):
        assert sbv._d5_chain_ok({}) is False


# == _digest ==================================================================================

class TestDigest:
    def test_sha256_str_doner(self):
        d = sbv._digest("sha256", b"tamga")
        assert isinstance(d, str)
        assert d == hashlib.sha256(b"tamga").hexdigest()

    def test_sha256_bos_veri(self):
        assert sbv._digest("sha256", b"") == hashlib.sha256(b"").hexdigest()

    def test_keccak256_bayt_doner(self):
        d = sbv._digest("keccak256", b"tamga")
        assert isinstance(d, bytes)
        assert d == keccak256(b"tamga")

    @pytest.mark.parametrize("alg", ["", "sha512", "md5", "bilinmiyor"])
    def test_bilinmeyen_alg_keccaka_duser(self, alg):
        assert sbv._digest(alg, b"x") == keccak256(b"x")

    def test_sha256_vs_keccak_farkli(self):
        assert sbv._digest("sha256", b"x") != sbv._digest("keccak256", b"x").hex()


# == _claim_signer ===========================================================================

class TestClaimSignerX402:
    def test_gecerli_imza_adresi_cozer(self):
        d = hashlib.sha256(b"govde").hexdigest()
        sig, addr = _secp_sign(d, BUYER_K)
        assert sbv._claim_signer(d, sig, "x402/v1") == addr

    def test_ham_64hex_de_gecerli(self):
        d = hashlib.sha256(b"govde").hexdigest()
        sig, addr = _secp_sign(d, BUYER_K)
        assert sbv._claim_signer(d, "0x" + sig, "x402/v1") == addr

    def test_yanlis_imza_baska_adres_cozer(self):
        """ORTAM-KARAKTERİZASYON: ecrecover digest-BAĞLAMAZ — başka-bir-digest
        için üretilmiş imza, başka-bir-anahtara (BURAYA: BUYER-değil) çözülür;
        None-dönmez. Mesaj-bağlaması verify()'daki got≠buyer karşılaştırmasında."""
        d = hashlib.sha256(b"govde").hexdigest()
        sig, _a = _secp_sign(hashlib.sha256(b"baska").hexdigest(), BUYER_K)
        got = sbv._claim_signer(d, sig, "x402/v1")
        assert got is not None and got != BUYER

    def test_baska_anahtar_imzasi_baska_adres(self):
        d = hashlib.sha256(b"govde").hexdigest()
        sig, addr = _secp_sign(d, OTHER_K)
        assert sbv._claim_signer(d, sig, "x402/v1") == addr == OTHER

    @pytest.mark.parametrize("kotu", ["", "00", "zz", "0x" + "11", None, 42])
    def test_bozuk_imza_none(self, kotu):
        assert sbv._claim_signer(hashlib.sha256(b"g").hexdigest(), kotu,
                                 "x402/v1") is None

    def test_v_29_recid_2_gecersiz(self):
        """recid 0-3 aralıktadır; v>=27 → rec_id=v-27; 29 → 2 denenir."""
        d = hashlib.sha256(b"govde").hexdigest()
        sig, _a = _secp_sign(d, BUYER_K)
        raw = bytearray(bytes.fromhex(sig))
        raw[64] = 29
        # recid 2/3 x=r+2N ≥ P → None (gerçek-anahtar kurtarılamaz)
        assert sbv._claim_signer(d, raw.hex(), "x402/v1") is None


class TestClaimSignerTamgaNative:
    def test_gecerli_ed25519_buyer_doner(self):
        d = hashlib.sha256(b"govde").hexdigest()
        sig = _ED.sign(bytes.fromhex(d)).signature.hex()
        got = sbv._claim_signer(d, sig, "tamga/native", _ED_BUYER, "{}")
        assert got == _ED_BUYER

    def test_yanlis_imza_none(self):
        d = hashlib.sha256(b"govde").hexdigest()
        bad = SigningKey(bytes(range(1, 33))).sign(bytes.fromhex(d)).signature.hex()
        assert sbv._claim_signer(d, bad, "tamga/native", _ED_BUYER, "{}") is None

    @pytest.mark.parametrize("kotu", [None, "", "aa" * 31, "aa" * 33, "gg" * 32, 42])
    def test_buyer_64hex_degil_none(self, kotu):
        d = hashlib.sha256(b"g").hexdigest()
        sig = _ED.sign(bytes.fromhex(d)).signature.hex()
        assert sbv._claim_signer(d, sig, "tamga/native", kotu, "{}") is None

    def test_buyer_buyuk_hex_none(self):
        """sadece 0-9abcdef — büyük harf kabul edilmez."""
        d = hashlib.sha256(b"g").hexdigest()
        sig = _ED.sign(bytes.fromhex(d)).signature.hex()
        assert sbv._claim_signer(d, sig, "tamga/native", _ED_BUYER.upper(),
                                 "{}") is None

    def test_ham_mesaj_hash_baytlari(self):
        """sözleşme: imza digest'ın HAM baytları-üzerine (AT-077)."""
        d = hashlib.sha256(b"govde").hexdigest()
        # yanlış mesaj (gövde-metni) → None
        wrong = _ED.sign(b"govde-metni").signature.hex()
        assert sbv._claim_signer(d, wrong, "tamga/native", _ED_BUYER, "govde") is None

    def test_ham_mesaj_dogru_olunca_gecer(self):
        d = hashlib.sha256(b"govde").hexdigest()
        sig = _ED.sign(bytes.fromhex(d)).signature.hex()
        # digest-hex'i-yanlış-uzunlukta-ama-imza-dogru → None (fromhex patlar)
        assert sbv._claim_signer("nothex", sig, "tamga/native", _ED_BUYER,
                                 "{}") is None


class TestClaimSignerErc8004:
    def test_keccak_digest_buyer_eslesir(self):
        got = sbv._claim_signer(DH_HEX, "signature-önemsiz", "erc8004/v1")
        assert got == keccak256(bytes.fromhex(DH_HEX)).hex()

    def test_hex_str_doner(self):
        got = sbv._claim_signer(DH_HEX, "x", "erc8004/v1")
        assert isinstance(got, str) and len(got) == 64

    def test_bos_digest_none(self):
        assert sbv._claim_signer("", "x", "erc8004/v1") is None

    def test_gecersiz_hex_digest_hata_yayilir(self):
        """bytes.fromhex('zz') ValueError — korumasız dal (karakterizasyon)."""
        with pytest.raises(ValueError):
            sbv._claim_signer("zz", "x", "erc8004/v1")

    def test_buyer_govde_ozutten_bagimsiz(self):
        """erc8004 buyer = keccak(delivery-hash); gövde-özütü DEĞİL."""
        a = sbv._claim_signer(DH_HEX, "x", "erc8004/v1", "buyer1", "{}")
        b = sbv._claim_signer(DH_HEX, "x", "erc8004/v1", "buyer2", "baska")
        assert a == b


class TestClaimSignerBilinmeyen:
    @pytest.mark.parametrize("scheme", ["", "bilinmiyor", "x402/v2", "tamga/native2"])
    def test_bilinmeyen_none(self, scheme):
        assert sbv._claim_signer(DH_HEX, "x", scheme, "b", "{}") is None

    def test_varsayilan_x402dur(self):
        d = hashlib.sha256(b"g").hexdigest()
        sig, addr = _secp_sign(d, SELLER_K)
        assert sbv._claim_signer(d, sig) == addr


# == _foreign_chain_ok =======================================================================

class TestForeignChainOk:
    def _p(self, **over):
        p = {"chain": "swarmax", "head_hex": "c" * 64, "entries": 3}
        p.update(over)
        return p

    def test_gecerli(self):
        assert sbv._foreign_chain_ok(self._p(), BUYER, DH_HEX, "x402/v1") is True

    def test_proof_dict_degil(self):
        assert sbv._foreign_chain_ok(["swarmax"], BUYER, DH_HEX, "x402/v1") is False
        assert sbv._foreign_chain_ok(None, BUYER, DH_HEX, "x402/v1") is False
        assert sbv._foreign_chain_ok("swarmax", BUYER, DH_HEX, "x402/v1") is False

    @pytest.mark.parametrize("chain", ["swarmax", "dumen", "pqhaven", "tamga",
                                       "fleksa", "sester", "veridict", "pacta",
                                       "pactiva", "yieldix", "syntropion",
                                       "tenderix", "veridrome"])
    def test_beyaz_liste_zincirleri(self, chain):
        assert sbv._foreign_chain_ok(self._p(chain=chain), BUYER, DH_HEX,
                                     "x402/v1") is True

    @pytest.mark.parametrize("chain", ["", "SWARMAX", "bitcoin", "ethereum",
                                       "swarmax2", "sester "])
    def test_beyaz_liste_disi_reddedilir(self, chain):
        assert sbv._foreign_chain_ok(self._p(chain=chain), BUYER, DH_HEX,
                                     "x402/v1") is False

    def test_chain_eksik(self):
        p = self._p()
        del p["chain"]
        assert sbv._foreign_chain_ok(p, BUYER, DH_HEX, "x402/v1") is False

    @pytest.mark.parametrize("kotu", [None, 64, ["c" * 64], b"c" * 64])
    def test_head_tip_hatali(self, kotu):
        assert sbv._foreign_chain_ok(self._p(head_hex=kotu), BUYER, DH_HEX,
                                     "x402/v1") is False

    @pytest.mark.parametrize("uzunluk", [0, 1, 63, 65])
    def test_head_uzunluk_64_degil(self, uzunluk):
        assert sbv._foreign_chain_ok(self._p(head_hex="c" * uzunluk), BUYER,
                                     DH_HEX, "x402/v1") is False

    @pytest.mark.parametrize("kotu", [None, "3", 3.0])
    def test_entries_tip_hatali(self, kotu):
        assert sbv._foreign_chain_ok(self._p(entries=kotu), BUYER, DH_HEX,
                                     "x402/v1") is False

    def test_entries_bool_intin_alt_siniri_gecerli(self):
        """ORTAM-QUIRK: bool int'in alt-sınıfı — entries=True == 1 → geçerli."""
        assert sbv._foreign_chain_ok(self._p(entries=True), BUYER, DH_HEX,
                                     "x402/v1") is True

    @pytest.mark.parametrize("n", [0, -1, -1000])
    def test_entries_sifir_veya_negatif(self, n):
        assert sbv._foreign_chain_ok(self._p(entries=n), BUYER, DH_HEX,
                                     "x402/v1") is False

    def test_entries_bir_sinir_gecerli(self):
        assert sbv._foreign_chain_ok(self._p(entries=1), BUYER, DH_HEX,
                                     "x402/v1") is True

    # --- evidence_link ---

    def test_link_equals_head_eslesir(self):
        p = self._p(head_hex=DH_HEX, evidence_link="equals")
        assert sbv._foreign_chain_ok(p, BUYER, DH_HEX, "x402/v1") is True

    def test_link_equals_head_eslesmez(self):
        p = self._p(head_hex=DH_HEX, evidence_link="equals")
        assert sbv._foreign_chain_ok(p, BUYER, "d" * 64, "x402/v1") is False

    def test_link_equals_buyuk_kucuk_duyarsiz(self):
        p = self._p(head_hex=DH_HEX.upper(), evidence_link="equals")
        assert sbv._foreign_chain_ok(p, BUYER, DH_HEX, "x402/v1") is True

    def test_link_derived_head_sha256_receipt(self):
        derived = hashlib.sha256(bytes.fromhex(DH_HEX)).hexdigest()
        p = self._p(head_hex=derived, evidence_link="derived")
        assert sbv._foreign_chain_ok(p, BUYER, DH_HEX, "x402/v1") is True

    def test_link_derived_head_eslesmez(self):
        p = self._p(head_hex="e" * 64, evidence_link="derived")
        assert sbv._foreign_chain_ok(p, BUYER, DH_HEX, "x402/v1") is False

    def test_link_derived_gecersiz_hex_receipt_valueerror(self):
        """bytes.fromhex korumasız — ValueError _foreign_chain_ok'ten FIRLAR."""
        p = self._p(head_hex="e" * 64, evidence_link="derived")
        with pytest.raises(ValueError):
            sbv._foreign_chain_ok(p, BUYER, "gecersiz-hex", "x402/v1")

    @pytest.mark.parametrize("link", [None, "", "baska", "EQUALS", 42])
    def test_link_tanimsiz_gorulmez(self, link):
        assert sbv._foreign_chain_ok(self._p(evidence_link=link), BUYER, DH_HEX,
                                     "x402/v1") is True

    # --- head_source ---

    def test_head_source_dosya_eslesir(self, tmp_path):
        f = tmp_path / "head.txt"
        f.write_text("C" * 64, encoding="utf-8")
        assert sbv._foreign_chain_ok(self._p(head_source=str(f)), BUYER, DH_HEX,
                                     "x402/v1") is True

    def test_head_source_dosya_eslesmez(self, tmp_path):
        f = tmp_path / "head.txt"
        f.write_text("d" * 64, encoding="utf-8")
        assert sbv._foreign_chain_ok(self._p(head_source=str(f)), BUYER, DH_HEX,
                                     "x402/v1") is False

    def test_head_source_dosya_yok(self, tmp_path):
        assert sbv._foreign_chain_ok(self._p(head_source=str(tmp_path / "yok.txt")),
                                     BUYER, DH_HEX, "x402/v1") is False

    def test_head_source_dizin_yol_False(self, tmp_path):
        assert sbv._foreign_chain_ok(self._p(head_source=str(tmp_path)), BUYER,
                                     DH_HEX, "x402/v1") is False

    def test_head_source_bos_dosya_False(self, tmp_path):
        f = tmp_path / "bos.txt"
        f.write_text("", encoding="utf-8")
        assert sbv._foreign_chain_ok(self._p(head_source=str(f)), BUYER, DH_HEX,
                                     "x402/v1") is False

    def test_head_source_bos_string_gorulmez(self):
        assert sbv._foreign_chain_ok(self._p(head_source=""), BUYER, DH_HEX,
                                     "x402/v1") is True

    @pytest.mark.parametrize("kotu", [None, 42, ["x"], True])
    def test_head_source_tip_hatali_gorulmez(self, kotu):
        assert sbv._foreign_chain_ok(self._p(head_source=kotu), BUYER, DH_HEX,
                                     "x402/v1") is True

    def test_head_source_oku_hatasi_fail_closed(self, tmp_path, monkeypatch):
        f = tmp_path / "head.txt"
        f.write_text("c" * 64, encoding="utf-8")
        orig = pathlib.Path.read_text

        def _patla(self, *a, **kw):
            if str(self) == str(f):
                raise OSError("izin-yok")
            return orig(self, *a, **kw)

        monkeypatch.setattr(pathlib.Path, "read_text", _patla)
        assert sbv._foreign_chain_ok(self._p(head_source=str(f)), BUYER,
                                     DH_HEX, "x402/v1") is False

    def test_head_source_user_genisletme(self, tmp_path, monkeypatch):
        f = tmp_path / "head.txt"
        f.write_text("c" * 64, encoding="utf-8")
        monkeypatch.setenv("HOME", str(tmp_path))
        assert sbv._foreign_chain_ok(self._p(head_source="~/head.txt"), BUYER,
                                     DH_HEX, "x402/v1") is True

    def test_payer_ve_scheme_kullanilmaz(self):
        """imzada payer/scheme parametreleri gövüde-etkisiz (karakterizasyon)."""
        a = sbv._foreign_chain_ok(self._p(), BUYER, DH_HEX, "x402/v1")
        b = sbv._foreign_chain_ok(self._p(), OTHER, DH_HEX, "erc8004/v1")
        assert a is True and b is True


# == verify: başarı ===========================================================================

class TestVerifyGreen:
    def test_x402_tam_yesil(self):
        r = sbv.verify(_charge(), _x402_claim())
        assert r["verdict"] == "GREEN" and r["ok"] is True
        assert r["reason_code"] == 0

    def test_x402_checks_hepsi_dogru(self):
        r = sbv.verify(_charge(), _x402_claim())
        assert r["checks"] == {"1_receipt": True, "2_claim_sig": True,
                               "3_settlement_ref": True, "4_parties": True,
                               "5_evidence_hash": True}

    def test_tamga_native_tam_yesil(self):
        bind, claim = _native_pair()
        c = _charge(delivery_hash={"alg": "sha256", "hex": DH_HEX},
                    settlement_bind=bind)
        r = sbv.verify(c, claim)
        assert r["verdict"] == "GREEN" and r["reason_code"] == 0

    def test_erc8004_tam_yesil(self):
        bind, claim = _erc_pair()
        c = _charge(delivery_hash={"alg": "keccak256", "hex": DH_HEX},
                    settlement_bind=bind)
        r = sbv.verify(c, claim)
        assert r["verdict"] == "GREEN" and r["reason_code"] == 0

    def test_erc8004_buyer_govde_ozuttu_DEGIL(self):
        """gövde-değişse bile buyer = keccak(delivery-hash) sabit → GREEN."""
        bind, claim = _erc_pair()
        claim["extra"] = "herhangi-bir-alan"
        c = _charge(delivery_hash={"alg": "keccak256", "hex": DH_HEX},
                    settlement_bind=bind)
        r = sbv.verify(c, claim)
        assert r["verdict"] == "GREEN"

    def test_buyuk_kucuk_harf_duyarsiz_adresler(self):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER.upper(), "payee": SELLER.upper()})
        cl = _x402_claim(buyerAddress=BUYER.upper(), sellerAddress=SELLER.upper())
        # imza gövdedeki büyük-harf adresle hesaplanmalı
        sig, _a = _secp_sign(hashlib.sha256(_govde(cl).encode()).hexdigest(), BUYER_K)
        cl["signature"] = sig
        r = sbv.verify(c, cl)
        assert r["verdict"] == "GREEN"

    def test_foreign_proof_gecerli_yesil(self):
        c = _charge(foreign_chain_proof={"chain": "sester", "head_hex": "c" * 64,
                                         "entries": 5})
        r = sbv.verify(c, _x402_claim())
        assert r["verdict"] == "GREEN"
        assert r["checks"]["6_foreign_chain"] is True

    def test_submitter_farkli_yesil(self):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": SELLER,
                                     "submitter": OTHER})
        r = sbv.verify(c, _x402_claim())
        assert r["verdict"] == "GREEN"
        assert r["checks"]["7_submitter_payee"] is True

    def test_cikti_alanlari_tam(self):
        r = sbv.verify(_charge(), _x402_claim())
        assert set(r) == {"ok", "verdict", "reason", "reason_code", "checks"}
        assert r["reason"]

    def test_check_sira_7_kontrol_degil(self):
        """7-kontrol var ama checks'te 6/7 yalnızca ilgili-ise görünür."""
        r = sbv.verify(_charge(), _x402_claim())
        assert "6_foreign_chain" not in r["checks"]
        assert "7_submitter_payee" not in r["checks"]


# == verify: fail-closed kapıları ============================================================

class TestVerifyKapilar:
    def _r(self, charge, claim):
        return sbv.verify(charge, claim)

    @pytest.mark.parametrize("bind", [None, "yok", ["a"], 42])
    def test_rc1_bind_yok_veya_dict_degil(self, bind):
        c = _charge()
        c["settlement_bind"] = bind
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "RED" and r["reason_code"] == 1
        assert "settlement_bind_missing" in r["reason"]

    def test_bind_eksik_alan(self):
        c = _charge()
        del c["settlement_bind"]
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 1

    @pytest.mark.parametrize("scheme", ["", "bilinmiyor", "x402/v2", "tamga/native "])
    def test_rc2_bilinmeyen_sema_indeterminate(self, scheme):
        c = _charge(settlement_bind={"scheme": scheme, "payment_id": "pay-42",
                                     "payer": BUYER, "payee": SELLER})
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "İNDETERMİNE"
        assert r["reason_code"] == 2
        assert r["ok"] is None
        assert "unknown_scheme" in r["reason"]

    def test_rc2_sema_listesi_yansir(self):
        c = _charge(settlement_bind={"scheme": "x", "payment_id": "p",
                                     "payer": BUYER, "payee": SELLER})
        r = self._r(c, _x402_claim())
        assert "x402/v1" in r["reason"] and "erc8004/v1" in r["reason"]

    # --- rc3 receipt ---

    @pytest.mark.parametrize("seq", [0, "1", -1])
    def test_rc3_d5_ucsu_bozuk(self, seq):
        c = _charge(seq=seq)
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "RED" and r["reason_code"] == 3
        assert r["checks"]["1_receipt"] is False

    @pytest.mark.parametrize("dh", [None, "yok", {"alg": "sha256"},
                                    {"alg": "sha256", "hex": "a" * 63},
                                    {"alg": "md5", "hex": "a" * 64},
                                    {"hex": "a" * 64},
                                    {"alg": "sha256", "hex": "a" * 64, "extra": 1}])
    def test_rc3_delivery_hash_bozuk(self, dh):
        c = _charge(delivery_hash=dh)
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 3

    def test_rc3_devam_etmez(self):
        """ilk-RED-döner — sonraki-kontrollar-koşmaz."""
        c = _charge(seq=0)
        cl = _x402_claim()
        cl["settlementRef"] = "yanlis"
        r = self._r(c, cl)
        assert r["reason_code"] == 3
        assert "3_settlement_ref" not in r["checks"]

    # --- rc4 imza ---

    def test_rc4_yanlis_imza(self):
        cl = _x402_claim()
        sig, _a = _secp_sign(hashlib.sha256(b"baska-govde").hexdigest(), BUYER_K)
        cl["signature"] = sig
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 4
        assert r["checks"]["2_claim_sig"] is False

    def test_rc4_baska_imzalayan(self):
        cl = _x402_claim()
        sig, _a = _secp_sign(hashlib.sha256(_govde(cl).encode()).hexdigest(), OTHER_K)
        cl["signature"] = sig
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 4

    def test_rc4_baska_digestin_imzasi_mesaj_baglamasi(self):
        """imza doğru-anahtarla ama BAŞKA-digest-üzerine → got≠buyer → rc4."""
        cl = _x402_claim()
        sig, _a = _secp_sign(hashlib.sha256(b"baska-govde").hexdigest(), BUYER_K)
        cl["signature"] = sig
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 4

    @pytest.mark.parametrize("kotu", [None, 42, ["aa"]])
    def test_rc4_imza_tip_hatali(self, kotu):
        cl = _x402_claim()
        cl["signature"] = kotu
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 4

    def test_rc4_buyer_tip_hatali(self):
        cl = _x402_claim()
        cl["buyerAddress"] = None
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 4

    def test_rc4_imza_eksik(self):
        cl = _x402_claim()
        del cl["signature"]
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 4

    def test_rc4_native_yamuk_imza(self):
        bind, claim = _native_pair()
        claim["signature"] = SigningKey(bytes(range(1, 33))).sign(
            bytes.fromhex(hashlib.sha256(_govde(claim).encode()).hexdigest())
        ).signature.hex()
        c = _charge(settlement_bind=bind)
        r = self._r(c, claim)
        assert r["reason_code"] == 4

    def test_rc4_native_buyer_64hex_degil(self):
        bind, claim = _native_pair()
        claim["buyerAddress"] = "a" * 32
        bind["payer"] = claim["buyerAddress"]
        c = _charge(settlement_bind=bind)
        r = self._r(c, claim)
        assert r["reason_code"] == 4

    def test_rc4_erc8004_buyer_eslesmez(self):
        bind, claim = _erc_pair()
        claim["buyerAddress"] = "e" * 64
        bind["payer"] = claim["buyerAddress"]
        c = _charge(delivery_hash={"alg": "keccak256", "hex": DH_HEX},
                    settlement_bind=bind)
        r = self._r(c, claim)
        assert r["reason_code"] == 4

    # --- rc5 ref ---

    def test_rc5_ref_eslesmez(self):
        cl = _x402_claim(settlementRef="baska")
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 5
        assert r["checks"]["3_settlement_ref"] is False

    @pytest.mark.parametrize("ref", [None, 42, ["pay-42"]])
    def test_rc5_ref_tip_hatali(self, ref):
        r = self._r(_charge(), _x402_claim(settlementRef=ref))
        assert r["reason_code"] == 5

    def test_rc5_payment_id_eslesmez(self):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "baska",
                                     "payer": BUYER, "payee": SELLER})
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 5

    # --- rc6 taraflar ---

    @pytest.mark.parametrize("alan", ["buyerAddress", "sellerAddress"])
    def test_rc6_taraf_eslesmez(self, alan):
        cl = _claim_body()
        if alan == "buyerAddress":
            cl["buyerAddress"] = OTHER
            sig, _a = _secp_sign(hashlib.sha256(_govde(cl).encode()).hexdigest(),
                                 OTHER_K)
        else:
            cl["sellerAddress"] = OTHER
            sig, _a = _secp_sign(hashlib.sha256(_govde(cl).encode()).hexdigest(),
                                 BUYER_K)
        cl["signature"] = sig
        r = self._r(_charge(), cl)
        assert r["reason_code"] == 6
        assert r["checks"]["4_parties"] is False

    def test_rc6_payer_eslesmez(self):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": OTHER, "payee": SELLER})
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 6

    def test_rc6_payee_bos_string(self):
        """boş-payee: claim.sellerAddress ≠ '' → taraf-uyuşmazlığı (check-4)."""
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": ""})
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 6

    # --- rc7 evidenceHash ---

    @pytest.mark.parametrize("ev", [None, "yok", {"alg": "sha256"},
                                    {"alg": "sha256", "hex": "z" * 64},
                                    {"alg": "keccak256", "hex": DH_HEX},
                                    {"hex": DH_HEX}])
    def test_rc7_evidence_hash_bozuk(self, ev):
        r = self._r(_charge(), _x402_claim(evidenceHash=ev))
        assert r["reason_code"] == 7
        assert r["checks"]["5_evidence_hash"] is False

    def test_rc7_hex_bir_karakter_farkli(self):
        bad = DH_HEX[:-1] + ("0" if DH_HEX[-1] != "0" else "1")
        r = self._r(_charge(), _x402_claim(evidenceHash={"alg": "sha256",
                                                         "hex": bad}))
        assert r["reason_code"] == 7

    # --- rc8 yabancı zincir ---

    @pytest.mark.parametrize("kotu", [{"chain": "bitcoin"}, {"head_hex": "c" * 63},
                                      {"entries": 0}, {}])
    def test_rc8_yabanci_zincir_curuk(self, kotu):
        c = _charge(foreign_chain_proof=kotu)
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 8
        assert r["checks"]["6_foreign_chain"] is False

    def test_rc8_kanit_yoksa_yesil(self):
        """kanıt-opsiyonel: YOKSA GREEN (geri-uyumlu)."""
        c = _charge()
        assert "foreign_chain_proof" not in c
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "GREEN"

    def test_rc8_kanit_null_gecersiz_sayilmaz(self):
        r = self._r(_charge(foreign_chain_proof=None), _x402_claim())
        assert r["verdict"] == "GREEN"

    def test_rc8_link_equals_curuk(self):
        c = _charge(foreign_chain_proof={"chain": "tamga", "head_hex": "c" * 64,
                                         "entries": 1, "evidence_link": "equals"})
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 8

    def test_rc8_link_equals_saglam(self):
        c = _charge(foreign_chain_proof={"chain": "tamga", "head_hex": DH_HEX,
                                         "entries": 1, "evidence_link": "equals"})
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "GREEN"

    # --- rc9 submitter/payee ---

    def test_rc9_submitter_payee_ayni(self):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": SELLER,
                                     "submitter": SELLER})
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 9
        assert r["checks"]["7_submitter_payee"] is False
        assert "submitter_payee_conflation" in r["reason"]

    def test_rc9_submitter_payee_ayni_buyuk_harf(self):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": SELLER,
                                     "submitter": SELLER.upper()})
        r = self._r(c, _x402_claim())
        assert r["reason_code"] == 9

    @pytest.mark.parametrize("sub", ["", None])
    def test_rc9_submitter_bos_atlanir(self, sub):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": SELLER,
                                     "submitter": sub})
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "GREEN"
        assert "7_submitter_payee" not in r["checks"]

    @pytest.mark.parametrize("sub", [42, ["x"], True])
    def test_rc9_submitter_tip_hatali_atlanir(self, sub):
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": SELLER,
                                     "submitter": sub})
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "GREEN"

    def test_rc9_payee_bos_submitter_var(self):
        """payee='' + claim.sellerAddress='' (check-4 geçer) → ok7 falsy → rc9."""
        cl = _claim_body(sellerAddress="")
        sig, _a = _secp_sign(hashlib.sha256(_govde(cl).encode()).hexdigest(), BUYER_K)
        cl["signature"] = sig
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": "",
                                     "submitter": OTHER})
        r = self._r(c, cl)
        assert r["reason_code"] == 9

    def test_rc9_payee_tip_hatali(self):
        """payee=None + claim.sellerAddress='none' (str(None) ile eşleşir) → rc9."""
        cl = _claim_body(sellerAddress="none")
        sig, _a = _secp_sign(hashlib.sha256(_govde(cl).encode()).hexdigest(), BUYER_K)
        cl["signature"] = sig
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": None,
                                     "submitter": OTHER})
        r = self._r(c, cl)
        assert r["reason_code"] == 9

    def test_rc9_submitter_payere_esit_ama_payerdan_farkli(self):
        """submitter==payer serbest; yalnızca submitter==payee RED."""
        c = _charge(settlement_bind={"scheme": "x402/v1", "payment_id": "pay-42",
                                     "payer": BUYER, "payee": SELLER,
                                     "submitter": BUYER})
        r = self._r(c, _x402_claim())
        assert r["verdict"] == "GREEN"


# == main =====================================================================================

class TestMain:
    def _w(self, tmp_path, charge, claim):
        cp = tmp_path / "charge.json"
        cp.write_text(json.dumps(charge), encoding="utf-8")
        lp = tmp_path / "claim.json"
        lp.write_text(json.dumps(claim), encoding="utf-8")
        return [str(cp), str(lp)]

    def test_argc_yanlis_doc_basar_r1(self, capsys):
        rc = sbv.main(["prog", "a.json"])
        assert rc == 1
        assert "RFC-010" in capsys.readouterr().out

    def test_argc_fazla_da_r1(self, capsys):
        assert sbv.main(["prog", "a", "b", "c"]) == 1

    def test_green_r0(self, tmp_path):
        cp, lp = self._w(tmp_path, _charge(), _x402_claim())
        rc = sbv.main(["prog", cp, lp])
        assert rc == 0

    def test_green_stdout_json(self, tmp_path, capsys):
        cp, lp = self._w(tmp_path, _charge(), _x402_claim())
        sbv.main(["prog", cp, lp])
        r = json.loads(capsys.readouterr().out)
        assert r["verdict"] == "GREEN" and r["ok"] is True

    def test_red_r1(self, tmp_path):
        cp, lp = self._w(tmp_path, _charge(), _x402_claim(settlementRef="yanlis"))
        assert sbv.main(["prog", cp, lp]) == 1

    def test_indeterminate_r2(self, tmp_path):
        c = _charge(settlement_bind={"scheme": "bilinmiyor", "payment_id": "p",
                                     "payer": BUYER, "payee": SELLER})
        cp, lp = self._w(tmp_path, c, _x402_claim())
        assert sbv.main(["prog", cp, lp]) == 2

    def test_native_green_r0(self, tmp_path):
        bind, claim = _native_pair()
        c = _charge(settlement_bind=bind)
        cp, lp = self._w(tmp_path, c, claim)
        assert sbv.main(["prog", cp, lp]) == 0

    def test_erc8004_green_r0(self, tmp_path):
        bind, claim = _erc_pair()
        c = _charge(delivery_hash={"alg": "keccak256", "hex": DH_HEX},
                    settlement_bind=bind)
        cp, lp = self._w(tmp_path, c, claim)
        assert sbv.main(["prog", cp, lp]) == 0

    def test_bos_vektor_dahi_calismaz(self, tmp_path):
        cp, lp = self._w(tmp_path, {}, {})
        assert sbv.main(["prog", cp, lp]) == 1

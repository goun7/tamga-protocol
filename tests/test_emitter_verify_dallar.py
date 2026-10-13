"""tools/emitter_verify.py dal-kesen testleri (LEED) — emitter-tutarlılık kilidi.

Kural-1: MEVCUT DOSYALARA DOKUNULMADI, SADECE bu yeni dosya eklendi.
Kural-4: saf in-memory — emitter_verify.REPO modül-globali monkeypatch-ile
tmp_path'e-yönlendirilir; gerçek-üretim-koduna-ve-ledger'lara-DOKUNULMAZ,
disk-YAZIMI YOK (yalnızca tmp_path-üzerinde-okuma).

Kapsanan fonksiyonlar (7):
  _code_emitters      kod-içi _ledger_append-çağrı-aralığından op→kaynak çıkart
                      (çağrı-içi-iğne: yorum/parametre RED, gerçek-çağrı GREEN)
  _test_callin_needle iğne-sınıflandırma-özkontrolü (4-vasıtın-da-doğru-sınıfı)
  _ledger_evidence    op→görüldüğü-ledger-dosya-sayısı (seq+prev+h-üçlüsü-şartı;
                      .venv-dışlanır; OSError-atlanır)
  corpus_ops          corpus'taki-op'ler; production_only=True-test-fixture'leri-
                      dışlar (Veridict-canary-aynası)
  scan                (b)(c)(d)-yükümlülükleri-birleştirir → problems-listesi
  _read_spec          LEDGER-SPEC.md-okur (yoksa "")
  main                problems-yoksa rc0, varsa rc1

Dal listesi (başarı + başarısızlık + sınır):
  _code_emitters : boş-repo / yorum-iğnesi / parametre-iğnesi / tek-satır /
                   çok-satırlı (3-satırlı-12-sınır) / satır-numarası-doğruluğu /
                   3-modülün-ayrı-taranması / Türkçe-op-karakterleri /
                   büyük-harf-başlangıç-reddi / _append-olmadan-op-yok /
                   çağrı-aralığı-12-satır-üstü
  _ledger_evidence : seq+prev+h-üçlüsü / üçlü-yoksa-sayılma / op-yoksa-sayılma /
                     .venv-dışlanma / birden-fazla-dosya-sayısı /
                     dizin-olarak-.jsonl (OSError-atlama)
  corpus_ops : production_only-True-tests/·test-·fixture·.dbg-dışlanma /
               False-hepsi-dahil
  scan : temiz-GREEN / spec-yok / üretim-ledger-kanıtı-yok /
         ledger'da-var-kod-emitter'ı-yok / reserved-fee-atlanma /
         ghost-dal-erişilemez (karakterizasyon) / dönüş-anahtarları
  main : rc0-temiz / rc1-problemli / çıktı-biçimi
"""
from __future__ import annotations

import pathlib
import shutil
import sys
import tempfile

import pytest

sys.path.insert(0, ".")
sys.path.insert(0, "tools")
import emitter_verify as ev  # noqa: E402


@pytest.fixture
def repo(monkeypatch):
    """emitter_verify.REPO'yu-izole-geçici-dizine-yönlendir (gerçek-repoya-
    dokunma). DİKKAT: pytest'in-tmp_path'i-yol-olarak-'test-'-içerir-ve
    corpus_ops(production_only=True)'in-fixture-heuristiği-tarafından-dışlanır;
    bu-yüzden-temiz-adlı-bir-mkdtemp-kullanırız (bkv. TestCorpusOps-heuristik)."""
    d = pathlib.Path(tempfile.mkdtemp(prefix="ev-repo-"))
    monkeypatch.setattr(ev, "REPO", d)
    yield d
    shutil.rmtree(d, ignore_errors=True)


def _ledger_line(op: str, seq: int = 1, prev: str = "0" * 64) -> str:
    """seq+prev+h-üçlüsü-taşıyan-gerçek-ledger-satırı (h-değer-içermez — içerik
    bu-modül-için-önemli-değil, yalnızca üçlü-varlığı)."""
    import json
    return json.dumps({"seq": seq, "prev": prev, "h": "a" * 64, "op": op})


def _write(path, text: str) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return str(path)


# == _code_emitters: iğne-sınıflandırma ==========================================================

class TestCodeEmittersIgnesi:
    def test_empty_repo(self, repo):
        assert ev._code_emitters() == {}

    def test_comment_needle_ignored(self, repo):
        """Yorumdaki-op-emitter-sayılır-mı: HAYIR (çağrı-aralığında-değil)."""
        _write(repo / "tamga_runner.py", '# "op": "x-yorum"\n')
        assert ev._code_emitters() == {}

    def test_param_needle_ignored(self, repo):
        """Parametredeki-op-emitter-sayılır-mı: HAYIR (çağrı-değil)."""
        _write(repo / "tamga_runner.py", 'def f(op="x-param"): pass\n')
        assert ev._code_emitters() == {}

    def test_real_append_found(self, repo):
        _write(repo / "tamga_runner.py",
               '_ledger_append(lp, {"op": "x-gercek"})\n')
        assert ev._code_emitters() == {"x-gercek": ["tamga_runner.py:1"]}

    def test_multiline_append_found(self, repo):
        """Çok-satırlı-çağrı-aralığı-parantez-eşlemesiyle-tanınır."""
        _write(repo / "tamga_runner.py",
               '_ledger_append(lp,\n    {"op": "x-cok"},\n    "diger")\n')
        assert ev._code_emitters() == {"x-cok": ["tamga_runner.py:1"]}

    def test_append_on_later_line(self, repo):
        src = 'print("onc")\n\n_ledger_append(lp, {"op": "x"})\n'
        _write(repo / "tamga_runner.py", src)
        assert ev._code_emitters() == {"x": ["tamga_runner.py:3"]}

    def test_comment_before_real_append(self, repo):
        """Yorumdaki-op-RED-ama-aynı-dosyadaki-gerçek-çağrı-GREEN."""
        src = '# "op": "x-yorum"\n_ledger_append(lp, {"op": "x-gercek"})\n'
        _write(repo / "tamga_runner.py", src)
        assert ev._code_emitters() == {"x-gercek": ["tamga_runner.py:2"]}

    def test_no_append_call_no_emitter(self, repo):
        """_append-çağrısı-yoksa-op-hiç-taranmaz."""
        _write(repo / "tamga_runner.py", 'd = {"op": "y"}\n')
        assert ev._code_emitters() == {}

    def test_underscore_append_pattern_matched(self, repo):
        """Regex '_append\\s*(' — altçizgi-önekli-herhangi-append-yakalanır."""
        _write(repo / "tamga_bundle.py", '_x_append(lp, {"op": "y"})\n')
        assert ev._code_emitters() == {"y": ["tamga_bundle.py:1"]}

    def test_append_word_alone_not_matched(self, repo):
        """Sadece 'append(' (altçizgi-yok) eşleşmez."""
        _write(repo / "tamga.py", 'append(lp, {"op": "z"})\n')
        assert ev._code_emitters() == {}

    def test_missing_module_silently_skipped(self, repo):
        """Var-olmayan-modül-atlanır (tamga_runner-tek-dosya)."""
        _write(repo / "tamga_runner.py", '_ledger_append(lp, {"op": "a"})\n')
        assert ev._code_emitters() == {"a": ["tamga_runner.py:1"]}


# == _code_emitters: op-ad-kuralları ==============================================================

class TestCodeEmittersOpAdi:
    @pytest.mark.parametrize("op", [
        "a", "charge", "x-yorum", "migrate-net", "çığ", "öşü-1",
        "abcdef0123456789", "op-2",
    ])
    def test_valid_op_names(self, repo, op):
        """op-adı: [a-zçğıöşü]-başlangıç + [a-zçğıöşü0-9-]*-devam."""
        _write(repo / "tamga_runner.py", f'_ledger_append(lp, {{"op": "{op}"}})\n')
        assert op in ev._code_emitters()

    @pytest.mark.parametrize("op", ["X", "1op", "-op", " op", "A-op", "_op"])
    def test_invalid_op_names_ignored(self, repo, op):
        """Büyük-harf-başlangıç / rakam-başlangıç / tire-başlangıç-reddedilir."""
        _write(repo / "tamga_runner.py", f'_ledger_append(lp, {{"op": "{op}"}})\n')
        assert ev._code_emitters() == {}

    def test_uppercase_op_inside_valid_wrapper_ignored(self, repo):
        _write(repo / "tamga_runner.py", '_ledger_append(lp, {"op": "OP"})\n')
        assert ev._code_emitters() == {}

    def test_two_emitters_same_op_two_locations(self, repo):
        src = ('_ledger_append(lp, {"op": "alpha"})\n'
               'x = 1\n'
               '_ledger_append(lp, {"op": "alpha"})\n')
        _write(repo / "tamga_runner.py", src)
        got = ev._code_emitters()
        assert got["alpha"] == ["tamga_runner.py:1", "tamga_runner.py:3"]

    def test_two_modules_two_files(self, repo):
        _write(repo / "tamga_runner.py", '_ledger_append(lp, {"op": "a"})\n')
        _write(repo / "tamga.py", '_ledger_append(lp, {"op": "b"})\n')
        assert ev._code_emitters() == {"a": ["tamga_runner.py:1"],
                                       "b": ["tamga.py:1"]}

    def test_call_range_spanning_many_lines(self, repo):
        """Çağrı-aralığı-12-satıra-kadar-taranır (kapanış-parantezi-uzakta)."""
        src = ("_ledger_append(lp,\n" + "    1,\n" * 10 +
               '    {"op": "uzak"})\n')
        _write(repo / "tamga_runner.py", src)
        assert ev._code_emitters() == {"uzak": ["tamga_runner.py:1"]}

    def test_op_beyond_12_line_window_ignored(self, repo):
        """12-satır-pencerenin-dışındaki-op-yakalanmaz (karakterizasyon)."""
        src = ("_ledger_append(lp,\n" + "    1,\n" * 13 +
               '    {"op": "cok-uzak"})\n')
        _write(repo / "tamga_runner.py", src)
        assert "cok-uzak" not in ev._code_emitters()

    def test_nested_op_dict_still_found(self, repo):
        """ORTAM-KARAKTERİZASYON: iç-içe-dict'teki-op-da-yakalanır
        (regex-doğrudan-{'ardından-"op"'-arar — derinlik-denetimi-yok)."""
        _write(repo / "tamga_runner.py",
               '_ledger_append(lp, {"data": {"op": "ic"}})\n')
        assert ev._code_emitters() == {"ic": ["tamga_runner.py:1"]}

    def test_comment_shaped_append_still_scanned(self, repo):
        """ORTAM-KARAKTERİZASYON: '_append('-şekilli-YORUM-da-taranır —
        satır-filtresi-yalnızca-regex'e-bakar, sözdizimine-değil. Test-bulguyu
        belgeler (üretimde-bu-yanlış-pozitif-almaz: dosyalar-gerçek-kod)."""
        _write(repo / "tamga_runner.py", '# _ledger_append(x) {"op": "yorumda"}\n')
        assert ev._code_emitters() == {"yorumda": ["tamga_runner.py:1"]}


# == _test_callin_needle =========================================================================

class TestCallinNeedle:
    def test_self_check_passes_on_isolated_repo(self, repo):
        """Dört-vasıta-da-doğru-sınıflandırılır → boş-hata-listesi."""
        assert ev._test_callin_needle() == []

    def test_returns_list_of_str(self, monkeypatch):
        monkeypatch.setattr(ev, "REPO", ev.HERE.parent)  # gerçek-repo (salt-oku)
        r = ev._test_callin_needle()
        assert isinstance(r, list)
        assert all(isinstance(x, str) for x in r)

    def test_detects_bad_classification(self, repo, monkeypatch):
        """İğne-bozuksa-hata-döner: _code_emitters-boş-stub'la-'gerçek-append'
        kaybolduğu-için-özkontrol-fail-döndürür."""
        monkeypatch.setattr(ev, "_code_emitters", lambda: {})
        fails = ev._test_callin_needle()
        assert any("gercek-append" in f for f in fails)


# == _ledger_evidence =============================================================================

class TestLedgerEvidence:
    def test_empty_repo(self, repo):
        assert ev._ledger_evidence() == {}

    def test_valid_ledger_line_counted(self, repo):
        _write(repo / "prod.jsonl", _ledger_line("alpha") + "\n")
        assert ev._ledger_evidence() == {"alpha": 1}

    def test_missing_triple_not_counted(self, repo):
        """Yalnızca-'op'-olan-satır-sayılmaz (seq+prev+h-üçlüsü-şart)."""
        import json
        _write(repo / "noise.jsonl", json.dumps({"op": "beta"}) + "\n")
        assert ev._ledger_evidence() == {}

    def test_partial_triple_not_counted(self, repo):
        _write(repo / "partial.jsonl",
               '{"seq": 1, "prev": "x", "op": "gamma"}\n')
        assert ev._ledger_evidence() == {}

    def test_multiple_files_same_op_counts_files(self, repo):
        _write(repo / "a.jsonl", _ledger_line("alpha") + "\n")
        _write(repo / "b.jsonl", _ledger_line("alpha") + "\n")
        assert ev._ledger_evidence() == {"alpha": 2}

    def test_different_ops_separate_keys(self, repo):
        _write(repo / "a.jsonl", _ledger_line("alpha") + "\n")
        _write(repo / "b.jsonl", _ledger_line("beta") + "\n")
        assert ev._ledger_evidence() == {"alpha": 1, "beta": 1}

    def test_venv_excluded(self, repo):
        """.venv-altındaki-session-günlükleri-kanıt-sayılmaz (DSY-tuzağı)."""
        _write(repo / ".venv" / "session.v3.jsonl",
               _ledger_line("venv-op") + "\n")
        assert ev._ledger_evidence() == {}

    def test_non_jsonl_ignored(self, repo):
        _write(repo / "ledger.json", _ledger_line("alpha") + "\n")
        assert ev._ledger_evidence() == {}

    def test_directory_named_jsonl_skipped(self, repo):
        """IsADirectoryError → OSError → sessiz-atlama (karakterizasyon)."""
        (repo / "dir.jsonl").mkdir()
        assert ev._ledger_evidence() == {}

    def test_empty_file_no_evidence(self, repo):
        _write(repo / "empty.jsonl", "")
        assert ev._ledger_evidence() == {}


# == corpus_ops ===================================================================================

class TestCorpusOps:
    def _populate(self, repo):
        _write(repo / "prod.jsonl", _ledger_line("p1") + "\n")
        _write(repo / "tests" / "t.jsonl", _ledger_line("t1") + "\n")
        _write(repo / "test-x.jsonl", _ledger_line("t2") + "\n")
        _write(repo / "fixture" / "f.jsonl", _ledger_line("f1") + "\n")
        _write(repo / "a.dbg.jsonl", _ledger_line("d1") + "\n")

    def test_all_ops_inclusive(self, repo):
        self._populate(repo)
        assert ev.corpus_ops() == {"p1", "t1", "t2", "f1", "d1"}

    @pytest.mark.parametrize("tok", ["tests/", "test-", "fixture", ".dbg"])
    def test_production_only_excludes_token(self, repo, tok):
        """Her-dışlama-token'i-üretim-dışı-sayılır (Veridict-canary-aynası)."""
        _write(repo / "prod.jsonl", _ledger_line("p1") + "\n")
        if tok.endswith("/"):
            _write(repo / tok / "x.jsonl", _ledger_line("x1") + "\n")
        else:
            _write(repo / f"n{tok}.jsonl", _ledger_line("x1") + "\n")
        assert ev.corpus_ops(production_only=True) == {"p1"}

    @pytest.mark.parametrize("dirname", ["mytest-dir", "sub-test-x", "fixture"])
    def test_token_anywhere_in_path_excluded(self, repo, dirname):
        """ORTAM-KARAKTERİZASYON: heuristik-YOL-DİZİSİNDE-arar — dosya-adında-
        değil, herhangi-bir-üst-dizinde-'test-'/'fixture'-geçse-dışlanır.
        Bu-yüzden-pytest'in-tmp_path'i-altında-production_only=True-her-dosyayı-
        dışlar (tmp-yolu-'test_'-içerir). Test-bunu-belgeler."""
        _write(repo / "prod.jsonl", _ledger_line("p1") + "\n")
        _write(repo / dirname / "deep.jsonl", _ledger_line("deep") + "\n")
        assert "deep" in ev.corpus_ops()
        assert "deep" not in ev.corpus_ops(production_only=True)

    def test_production_only_empty_repo(self, repo):
        assert ev.corpus_ops(production_only=True) == set()

    def test_returns_set(self, repo):
        assert isinstance(ev.corpus_ops(), set)

    def test_venv_excluded(self, repo):
        _write(repo / ".venv" / "s.jsonl", _ledger_line("v1") + "\n")
        assert "v1" not in ev.corpus_ops()
        assert "v1" not in ev.corpus_ops(production_only=True)


# == _read_spec ===================================================================================

class TestReadSpec:
    def test_missing_spec_returns_empty(self, repo):
        assert ev._read_spec() == ""

    def test_existing_spec_returned(self, repo):
        p = repo / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md"
        _write(p, "# Spec\n\n- charge\n- grant\n")
        assert "charge" in ev._read_spec()

    def test_returns_str(self, repo):
        assert isinstance(ev._read_spec(), str)


# == scan =========================================================================================

class TestScan:
    def _clean(self, repo):
        """Temiz-üretim-kurulumu: kod-emitter'ı + üretim-ledger'ı + spec."""
        _write(repo / "tamga_runner.py",
               '_ledger_append(lp, {"op": "alpha"})\n')
        _write(repo / "prod.jsonl", _ledger_line("alpha") + "\n")
        _write(repo / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md",
               "## alpha\n")
        return repo

    def test_clean_repo_no_problems(self, repo):
        self._clean(repo)
        d = ev.scan()
        assert d["problems"] == []
        assert d["ops_total"] == 2  # alpha + reserved fee

    def test_scan_return_keys(self, repo):
        self._clean(repo)
        d = ev.scan()
        assert set(d) == {"emitters", "ledger_evidence", "reserved",
                          "problems", "ops_total", "production_corpus_ops"}

    def test_emitters_section_carries_code_sources(self, repo):
        self._clean(repo)
        d = ev.scan()
        assert d["emitters"]["alpha"] == ["tamga_runner.py:1"]

    def test_reserved_always_listed(self, repo):
        self._clean(repo)
        assert ev.scan()["reserved"] == ["fee"]

    def test_production_corpus_ops_reported(self, repo):
        self._clean(repo)
        assert ev.scan()["production_corpus_ops"] == ["alpha"]

    def test_missing_spec_is_problem(self, repo):
        self._clean(repo)
        (repo / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md").unlink()
        d = ev.scan()
        assert any("SPEC'TE" in p and "alpha" in p for p in d["problems"])

    def test_missing_production_evidence_is_problem(self, repo):
        """Veridict-canary-sınıfı: kod-emitter'ı-var-AMA-üretim-ledger'ında-yok."""
        self._clean(repo)
        (repo / "prod.jsonl").unlink()
        d = ev.scan()
        assert any("KANIT-YOK" in p and "alpha" in p for p in d["problems"])

    def test_ledger_evidence_without_code_emitter_is_problem(self, repo):
        """Ledger'da-op-var-ama-kod-emitter'ı-yok → dış-kaynak-gürültüsü."""
        _write(repo / "prod.jsonl", _ledger_line("orphan") + "\n")
        _write(repo / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md",
               "orphan\n")
        d = ev.scan()
        assert any("ledger-kanıtı-var-ama-ÜRETİM-KODUNDA-emitter-yok" in p
                   for p in d["problems"])

    def test_reserved_op_never_a_problem(self, repo):
        """RESERVED={'fee'} — yayılmaz-kasıtlı, hiçbir-problem-üretmez."""
        _write(repo / "prod.jsonl", _ledger_line("fee") + "\n")
        _write(repo / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md", "x\n")
        d = ev.scan()
        assert not any("fee" in p for p in d["problems"])

    def test_ghost_branch_unreachable(self, repo):
        """ORTAM-KARAKTERİZASYON: 'ne-kodda-ne-ledgerda'-dalı-erişilemez —
        all_ops = code|seen|RESERVED-olduğu-için-döngüdeki-her-op-ya-kodda-ya-
        ledger'dadır. Test-bu-ölü-dalı-belgeler."""
        self._clean(repo)
        d = ev.scan()
        assert not any("hayalet-girdi" in p for p in d["problems"])

    def test_ops_total_counts_union(self, repo):
        _write(repo / "tamga_runner.py", '_ledger_append(lp, {"op": "a"})\n')
        _write(repo / "tamga.py", '_ledger_append(lp, {"op": "b"})\n')
        assert ev.scan()["ops_total"] == 3  # a, b + fee


# == main =========================================================================================

class TestMain:
    def test_clean_rc0(self, repo, monkeypatch, capsys):
        self._clean(repo)
        assert ev.main([]) == 0
        out = capsys.readouterr().out
        assert "kanıtlandı" in out

    def test_problems_rc1(self, repo, capsys):
        self._clean(repo)
        (repo / "prod.jsonl").unlink()
        assert ev.main([]) == 1
        out = capsys.readouterr().out
        assert "EMITTER-DOĞRULAMA-BAŞARISIZ" in out
        assert "✗" in out

    def test_main_ignores_argv(self, repo):
        self._clean(repo)
        assert ev.main(["any", "args", "ignored"]) == 0

    def _clean(self, repo):
        _write(repo / "tamga_runner.py",
               '_ledger_append(lp, {"op": "alpha"})\n')
        _write(repo / "prod.jsonl", _ledger_line("alpha") + "\n")
        _write(repo / "tests" / "conformance" / "spec" / "LEDGER-SPEC.md",
               "## alpha\n")


# == gerçek-repo duman-testi (salt-oku) ============================================================

class TestGercekRepoDuman:
    """REPO'monkeypatch'siz-çağrılar — gerçek-üretim-dosyalarını-sadece-OKUR
    (Kural-4: yazım-yok). Üretim-emitter-tablosunun-boş-olmadığını-doğrular."""

    def test_code_emitters_nonempty_on_real_repo(self):
        assert len(ev._code_emitters()) >= 1

    def test_code_emitters_returns_dict_of_lists(self):
        for op, srcs in ev._code_emitters().items():
            assert isinstance(op, str)
            assert isinstance(srcs, list) and srcs

    def test_reserved_constant(self):
        assert ev.RESERVED == {"fee"}

    def test_supported_emitter_modules(self):
        assert ev.EMITTER_MODULES == ("tamga_runner.py", "tamga_bundle.py",
                                      "tamga.py")

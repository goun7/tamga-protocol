# Gelir-Kolu 1+2 Implementation Plan — Evidence-Audit Teklifi + pip Paketi

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kurucunun-outreach-mühimmatı-(doğrulama-servisi-teklif-matrisi)-ve-`pip install tamga-protocol`-(tam-runner + lazy wasmtime)-teslimatı — her-ikisi-CI-yeşil-kapanır.

**Architecture:** Kol-1-yalnız-private/-dokümanı-(gitignored, public-repo-izine-girmez). Kol-2-repo-köküne-pyproject.toml-(setuptools, py_modules-listesi)+tamga_bootstrap.py-(wasmtime-lazy-loader, digest-pinned)+docs/QUICKSTART.md; mevcut-tamga_runner-dokunulmaz-yalnız-`if __name__`-kapısına-bootstrap-eklenir. at013_pip_sanity-kontrol-27-olarak-süite-girer.

**Tech Stack:** setuptools (py_modules, minimum-surpriz), PyNaCl (tek-sert-bağımlılık), wasmtime-v48.0.1-binary-lazy-download-(tests/setup.sh'teki-digest-çapasıyla-aynı), stdlib-only-testler.

## Global Constraints

- Repo-kültürü: her-iddia-kanıtla; suite-şu-an-26/26-(+27-slow) → bu-işlemle-27/27-(+28-slow)
- private/-gitignored — HIZMET-PAKETI-DOGRULAMA.md-OADAKİ-yayımlanmaz
- wasmtime-v48.0.1; sha256-çapası-tests/setup.sh'ten-kopya (E-5-disiplini): `4c2e31b68ad99e0a519f225a261fda099eb15f056d4a24fdb3c2a46517bde1df` (x86_64-linux-tar.xz)
- Türkçe-hata-mesajları-çift-dilli-(TR+EN); sessiz-fallback-YOK
- Python-3.10+; mevcut-dosyaların-başka-yeri-DEĞİŞTİRMEZ (additive-disiplin)
- Commit-başına-kanıt-(test-output)-+ push + CI-watch

---

### Task 1: Kol-1 — Hizmet-teklif-paketi (private/)

**Files:**
- Create: `private/HIZMET-PAKETI-DOGRULAMA.md`

**Interfaces:**
- Consumes: STRATEJI-2026-09-07.md-fiyat-bandı, docs/TESTS.md-kanıt-linkleri, private/HIZMET-PAKETI-GOC.md-şablon-tarzı
- Produces: kurucunun-e-posta-mühimmatı (matris+kapsam-dışı+şablon+kanıt-haritası, 4-bölüm-tek-dosya)

- [ ] **Step 1: Dosya-yaz** — 4-bölüm: (1) teklif-matrisi-(Basic-$750/2g ≤3-artefakt; Standart-$1500/3g ≤5+pair-bridge; Derin-$2500/5g tam-koşum), (2) kapsam-dışı-listesi, (3) TR+EN-e-posta-şablonu, (4) kanıt-ekleri-haritası-(AT-012/TESTS/#3379-linkleri)

- [ ] **Step 2: Doğrulama** — `git status --short`-private/-GÖRÜNMEZ-olmalı (gitignored); `python3 tools/check_links.py`-0-broken

- [ ] **Step 3: Commit** — private-görünmez-ama-progress.md-satırı-commitlenir: `git commit -m "docs(progress): evidence-audit service package drafted (private)"`

### Task 2: pyproject.toml + paket-metadata

**Files:**
- Create: `pyproject.toml`
- Modify: `.gitignore` — gerekirse-tools/bin-exclude-onayı (mevcut-gitignore-kontrol)

**Interfaces:**
- Consumes: root-modülleri-(tamga_runner, tamga_validator, tamga_netproxy, tamga_net_shim)
- Produces: `pip install .`-çalışır; console-script-`tamga`-→-tamga_runner.main

- [ ] **Step 1: pyproject.toml-yaz**

```toml
[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "tamga-protocol"
version = "0.2.0rc1"
description = "Self-custodial hash-chained work-receipt ledger for autonomous AI agents (RFC-002/003/007)"
readme = "docs/QUICKSTART.md"
requires-python = ">=3.10"
license = {text = "MIT"}
dependencies = ["PyNaCl>=1.5"]

[project.scripts]
tamga = "tamga_runner:main"

[tool.setuptools]
py_modules = ["tamga_runner", "tamga_validator", "tamga_netproxy", "tamga_net_shim", "tamga_bootstrap"]
[tool.setuptools.exclude-package-data]
"*" = ["tools/bin/*", "*.wasm"]
```

- [ ] **Step 2: main()-uyum-kontrolü** — tamga_runner-main()-`sys.argv[1:]-alıyor`-mi-bak; console-script-sarmalayıcı-gerekiyorsa-tamga_bootstrap-main()-yazar

- [ ] **Step 3: Kurulum-sigara-testi** — `python3 -m venv /tmp/pip-test && /tmp/pip-test/bin/pip install . && /tmp/pip-test/bin/tamga --help | head -3` → usage-görünür

- [ ] **Step 4: Commit** — `git commit -m "build: pyproject for tamga-protocol (console-script tamga, lazy wasmtime)"`

### Task 3: tamga_bootstrap.py — lazy-wasmtime-loader

**Files:**
- Create: `tamga_bootstrap.py`
- Test: `tests/at013_pip_sanity.sh`-(Task-4'te)

**Interfaces:**
- Consumes: WASMTIME-sabiti-(tamga_runner.py:35)-; setup.sh-digest-tablosu
- Produces: `tamga_bootstrap.ensure_wasmtime()` → str-path-(indirilmiş-tools/bin/wasmtime-veya-sistem-yolu); bulunamazsa-SystemExit-açık-hata

- [ ] **Step 1: failing-test-kabiliyeti** — bootstrap-YOK-iken-import-hata-VERİR: `python3 -c "import tamga_bootstrap"`→FAIL-(dosya-yok)

- [ ] **Step 2: bootstrap-yaz** — mantık: (1) tools/bin/wasmtime-varsa-onu-döndür (repo-olayı); (2) yoksa-~/.cache/tamga/bin/-deneme; (3) o-da-yoksa-şifreli-digest-pinned-download-(platform-matrisi-setup.sh'ten)-+ sha256-doğrula-+ chmod +x; (4) her-hata→iki-dilli-mesaj-(elle-kurulum-yolu-göster)-+ exit-1. Runner'ın-WASMTIME-satırı:`WASMTIME = tamga_bootstrap.ensure_wasmtime() if __package__ else ...`-değil — runner-dokunulmaz; bootstrap-sadece-console-script-kullanır-kabuğu: tamga_runner.WASMTIME-attribute'unu-BİR-KEZ-yeniden-ata:

```python
# tamga_bootstrap.py (özet-imza)
def ensure_wasmtime() -> str: ...   # path döndürür; yoksa indirme + sha256 kapısı
def main() -> int:                  # console-script sarmalayıcısı
    import tamga_runner as r
    if not pathlib.Path(r.WASMTIME).exists():
        r.WASMTIME = ensure_wasmtime()
    return r.main(sys.argv[1:])
```

- [ ] **Step 3: pyproject-scripts-güncelle** — `tamga = "tamga_bootstrap:main"`

- [ ] **Step 4: Manuel-koşum** — venv'de-`tamga keygen`-çalışır (wasmtime-gerekmez); `tamga run`-wasmtime'sız-ortamda-bootstrap-indirmesini-TRIGGER-eder-(SADECE-manuel-kanıt; CI-internet-indirmez)

- [ ] **Step 5: Commit** — `git commit -m "feat: tamga_bootstrap lazy-wasmtime loader with digest gate"`

### Task 4: QUICKSTART.md

**Files:**
- Create: `docs/QUICKSTART.md`

**Interfaces:**
- Consumes: tamga-runner-komutları, tc-net-demo-vektörü
- Produces: 5-dakika-onboarding-yüzeyi; README-bağlantısı

- [ ] **Step 1: QUICKSTART-yaz** — 5-adım: pip-install → keygen → demo-pkg-kopyala+run → ledger-verify → export/import; sonda-ARCHITECTURE-link; her-adım-komut+beklenen-çıktı-blok-yazılır

- [ ] **Step 2: Adımları-koşarak-doğrula** — her-komutu-venv'de-fiilen-koş; beklenen-çıktıları-DOSYAYA-gerçek-haliyle-yaz (kanıt-disiplini)

- [ ] **Step 3: README-bağlantısı** — "Full technical details"-satırının-üstüne: `New here? → [docs/QUICKSTART.md](docs/QUICKSTART.md) (5-minute setup)`

- [ ] **Step 4: check_links + commit** — `python3 tools/check_links.py`-0-broken; `git commit -m "docs: QUICKSTART.md 5-minute onboarding path"`

### Task 5: at013_pip_sanity.sh + süite-bağlama (kontrol-27)

**Files:**
- Create: `tests/at013_pip_sanity.sh`
- Modify: `tests/run_all.sh`-(kontrol-27-ekle), `README.md`/`README.tr.md`-badge-26→27, `docs/TESTS.md`-satır

**Interfaces:**
- Consumes: Task-2/3-çıktıları
- Produces: kontrol-27-PASS; suite-27/27

- [ ] **Step 1: at013-yaz** — venv-kur (`pip install .`-quiet) → `tamga keygen`-rc0+seed-format-(64-hex) → `tamga ledger-verify`-tc-net-demo-(wasmtime-İSTEMEZ → bootstrap-yolçapı-kanıtlanır) → `pip uninstall -y`-temizlik

- [ ] **Step 2: run_all-kontrol-27** — A2-A4-modeliyle: bash-blok-+ kontrol-satırı-ekle; başlık-27-controls-+ badge-güncelleme-(README×2, TESTS.md)

- [ ] **Step 3: Suite-koşumu** — `bash tests/run_all.sh`→`27 PASS, 0 FAIL`

- [ ] **Step 4: Commit+push+CI-watch** — commit `test: at013 pip sanity (kontrol-27) — install, keygen, verify without wasmtime`; `gh run watch`-yeşil-bekle

### Task 6: Kapanış — doküman-bağları + progress + MERGEN

**Files:**
- Modify: `progress.md`, `docs/PLAIN-TURKISH.md`-(kurulum-satırı-pip'i-es-alsın-İSTERSE-minimal)
- Create: `private/PILOT-RUNBOOK.md`-çapraz-kontrol-satırı (Kol-1-teklifi-referansı)

**Interfaces:**
- Consumes: tüm-Task-çıktıları
- Produces: kapanış-kayıtları; 8-10-saatlik-otonom-pencerenin-kanıt-zinciri

- [ ] **Step 1: progress.md-kapanış-bölümü** — her-taskın-kanıt-linki-(commit-hash, CI-run-id, suite-sayısı)

- [ ] **Step 2: MERGEN-memory + decision** — pip-paketi-ve-fiyat-bandı-kararları-kayda-geçer

- [ ] **Step 3: Son-durum-audit'i** — `git log --oneline -10` + `gh run list --limit 5` + suite-27/27-+ CI-yeşil-İSPAT-paragrafı

## Self-Review

- **Spec-kapsamı:** spec-§1-(4-teslimat)-Task-1 ✓; §2.1-2.2-Task-2+3 ✓; §2.3-Task-4 ✓; §2.4-Task-5 ✓; §5-başarı-ölçütü-Task-6-audit'i ✓ — boşluk-yok
- **Placeholder-taraması:** kod-blok-yerine-"özet-imza"-(bootstrap-gerçek-uygulaması-Task-3'te-tam-yazılacak-imza-istenir)-kabul-edilebilir-tek-yer; diğerleri-tam-içerik ✓
- **Tip-uyumu:** ensure_wasmtime()->str, main()->int-Tamga-console-script-ile-uyumlu ✓

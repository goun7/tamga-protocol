# LEÇVE — Academic grounding ek (2026-10-07): kanıt sistemleri

> **README'ye eklenecek literatür ekidir.** Mevcut `README.md` içeriğine
> **dokunulmamıştır**; bu dosya `docs/` altında YENİ dosya olarak teslim
> edilmiştir (goal: doc bağlarını genişlet).
>
> **FP0:** aşağıdaki her alıntı `web_fetch` ile **HTTP-200 + tam başlık birebir
> eşleşmesi** ile doğrulanmıştır. Uydurma alıntı yoktur. Kanıt:
> [`orkestrasyon/docs/fp0_arxiv_manifest_2026-10-07.json`](assets/fp0_arxiv_manifest_2026-10-07.json).
>
> G48-2026-10-22: link once `../../00_TAMGA-MESH/orkestrasyon/...`-e
> isaret ediyordu ( mesh-disina) — bu-dosya CI'da-KIRIK-link olarak
> patliyordu ( orkestrasyon-bu-deponun-parcasi-degil). Kanitin-kendisi
> `docs/assets/`-altina-KOPYALANDI ( ayni-icerik, 121-satir).

---

## Academic grounding — 2026-09-22..2026-10-07 penceresi (proof-systems)

Tamga'nın merkezî iddiası şudur: bir kanıt, üretenin güvenine değil,
**bağımsızca yeniden hesaplanabilmesine** dayanmalıdır. Son pencerenin iki
makalesi bu iddiayı tam olarak karşılar:

- **A2A-CaseVerify: Merkle-Linked Case-Evidence Verification for
  Cross-Organization A2A Workflows** ([arXiv:2609.33914](https://arxiv.org/abs/2609.33914),
  Alshammari/Bahsi, cs.CR, 27 Sep 2026) — Agent-to-Agent (A2A) iş akışlarında
  bir vaka (case) boyunca üretilen kanıtların **Merkle bağlantılı** olduğunu
  ve kurumlar-arasında bağımsız doğrulanabildiğini gösterir; her adımın
  çıktısı bir Merkle yaprağına bağlanır, böylece tek bir kanıt kümesi
  kurumlar-arası güvene gerek kalmadan denetlenebilir. Bu, Tamga'nın
  `tamga-snapshot/1` modelinin A2A dünyasındaki karşılığıdır: Tamga'da her
  olay JCS-kanonik baytların `sha256` zincirine eklenir ve alıcı
  `tamga_canon.jcs` ile **bayt-bayt** yeniden üretir. **Fark:** A2A-CaseVerify
  kurumlar-arası vaka kanıtı için Merkle yaprağı bağlamını önerir —
  Tamga bunu zaten RFC 8785 JCS kanonikleştirmesi ile **normatif** kılmış ve
  9 bağımsız projede bayt-paritesini kanıtlanmış olarak tutmuştur
  (`test_mesh_jcs_paritesi.py`, 9/9). Makale, Tamga'nın deseninin
  akademik karşılığını verir.

- **Assay: Claims That Decay With the Code. Content-Addressed Evidence Graphs
  for Accountable AI-Assisted Software Delivery** ([arXiv:2609.36170](https://arxiv.org/abs/2609.36170),
  Tiwari/Vass/Singh, cs.SE, 28 Sep 2026) — AI-destekli yazılım tesliminde
  iddiaların (claims) **içerik-adresli kanıt graflarına** bağlanması gerektiğini
  ve bu iddiaların **kod ile birlikte çürüyüp güncellendiğini** (decay with the
  code) savunur: kanıt, üretildiği kodun içeriğine öyle sıkı bağlıdır ki kod
  değişince kanıt da geçersizleşir. Tamga'nın `content_hash`-bağlama modeli
  aynı ilkedir: bir `tamga-snapshot` zarfı, içeriğin `sha256` özetine
  bağlanır ve içerik değişirse çıpa geçersiz olur (bu, mesh derinleştirme
  dalgasındaki "kendinden-tutarlı çıpa tuzağı" testlerinin tersi olarak
  kasıtlıdır). **Fark:** Assay bir yazılım-teslim hesap verebilirlik
  çerçevesidir (iddia grafı, çürüme politikası); Tamga bunu bir **ledger
  primitifine** indirger — her kanıt öncesi-özetli, imzalı ve
  bağımsız-doğrulanabilirdir, çürüme politikası değil.

---

*Bu ek, `README.md`'nin "Academic grounding" bölümüne eklenmek üzere
hazırlanmıştır.*

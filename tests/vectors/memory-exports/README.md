# memory-exports — sürüm-pinli doğrulama vektörleri (P4, 2026-09-09)

Her dosya, adındaki araç-sürümünün **dokümante export şekline** uygun sentetik örnektir
(real-data-DEĞİL; şekil-kanıtı). Amaç: import-sınıfı-kararlarının-sürüme-duyarlılığını-
görünür-kılmak — araç-sürümü-değişince-buraya-yeni-dosya-eklenir, eski-KALIR (diff-görünür).

| Dosya | Araç-sürüm | Şekil-kaynağı |
|---|---|---|
| mem0-2.0.20-export.json | mem0ai 2.0.20 (PyPI, 2026-09-05) | list-of-{memory,...} |
| letta-0.16.8-export.json | letta 0.16.8 (PyPI, 2026-09-05) | {"archival_memory": [...]} |
| zep-3.28.0-export.json | zep-cloud 3.28.0 (PyPI, 2026-09-05) | {"facts": [...]} |

Kullanım: `python3 tools/memory_import.py <dosya> <çıktı> --format auto` (sniff-bekleneni-
vermeli) — AT-005-ailesinin-bu-vektörlerle-uzantısı.

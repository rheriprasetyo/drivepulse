# 🤝 Cara Kontribusi ke DrivePulse

Makasih udah mau bantu! Berikut panduan kontribusi.

---

## 🚀 Quick Start

```powershell
# 1. Clone repo
git clone https://github.com/user/drivepulse.git
cd drivepulse

# 2. Jalanin script utama (pastiin jalan)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\analyze.ps1

# 3. Buat branch baru
git checkout -b feature/nama-fitur
```

---

## 📋 Aturan Umum

1. **Baca PRD.md** sebelum mulai — pahami visi dan roadmap
2. **Bahasa Indonesia** untuk semua output yang dilihat user
3. **Komentar kode** boleh Bahasa Inggris atau Indonesia
4. **Jangan commit** file sampah (temp, cache, node_modules, output report)
5. **Test dulu** sebelum push — minimal jalanin script tanpa error

---

## 🌿 Branch Naming

| Tipe | Format | Contoh |
|------|--------|--------|
| Fitur baru | `feature/nama-fitur` | `feature/deep-scan` |
| Bug fix | `fix/deskripsi` | `fix/access-denied-crash` |
| Dokumentasi | `docs/topik` | `docs/update-guide` |
| Refactor | `refactor/scope` | `refactor/scanner-module` |

---

## 📝 Commit Message

Format: `tipe: deskripsi singkat`

```
feat: add deep scan mode
fix: handle access denied on Windows Temp
docs: update FAQ section
refactor: split scanner into modules
test: add categorization tests
```

---

## 🧪 Testing

```powershell
# Jalanin semua test
.\tests\test-scan.ps1
.\tests\test-categorize.ps1
.\tests\test-clean.ps1
```

Framework: Pester (opsional). Untuk sekarang, assertion manual cukup.

---

## 📁 Struktur Kode

- `scripts/` — Entry point yang dijalanin user langsung
- `src/scanner/` — Logic scanning (core)
- `src/reporter/` — Generate report
- `src/cleaner/` — Cleanup + backup + restore
- `src/ui/` — CLI menu interaktif
- `config/` — Rules dan konfigurasi default
- `tests/` — Test scripts
- `docs/` — Dokumentasi end-user

---

## ⚠️ Yang Perlu Diperhatikan

- **Safety first** — Jangan bikin fitur yang hapus file tanpa konfirmasi
- **Dry-run default** — Semua aksi destruktif harus preview dulu
- **Graceful error handling** — Access denied = skip, jangan crash
- **Target user awam** — Output harus jelas dan gak bikin takut

---

## 🎯 Prioritas Saat Ini

Lihat roadmap di PRD.md. Milestone aktif: **v1.1 — Core Scanner**.

---

> Ada pertanyaan? Buka Issue di GitHub atau hubungi @rheriprasetyo

# 🧹 DrivePulse

> **Analisis & petunjuk pembersihan drive Windows — dalam Bahasa Indonesia yang manusiawi.**

DrivePulse bantu kamu ngerti **kenapa** drive C: laptop hampir penuh dan **gimana** cara ngatasinnya. Bukan cuma nunjukin angka — tapi ngasih penjelasan dan langkah yang jelas, pakai bahasa yang gampang dipahami.

---

## ✨ Fitur

- 🔍 **Scan cepat** — tau folder mana yang makan ruang paling banyak (< 15 detik)
- ✅ **Kategorisasi cerdas** — item **aman dihapus** vs **perlu dicek manual**, lengkap dengan penjelasan efek samping
- 👀 **Dry-run mode** — lihat dulu apa yang bakal dihapus, tanpa beneran hapus
- 🧹 **Panduan langkah demi langkah** — tinggal ikutin, gak perlu panggil teknisi
- 📊 **Export report** — simpen hasil scan dalam HTML atau TXT
- 🛡️ **Safety first** — backup otomatis sebelum hapus, bisa di-rollback
- 🚀 **Siap diotomasi** — script PowerShell, tinggal jalanin

---

## 📸 Screenshot

> *Coming soon — screenshot akan ditambahkan setelah CLI selesai.*

---

## ⚡ Quick Start

### Syarat Minimum
- Windows 10 (build 1809+) atau Windows 11
- PowerShell 5.1 (sudah bawaan Windows)
- RAM: 2 GB
- Tidak butuh koneksi internet

### Cara Pakai

1. **Buka PowerShell** (klik kanan Start → Windows PowerShell)

2. **Set execution policy** (cuma untuk sesi ini, aman — gak mengubah setting Windows kamu secara permanen):
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

3. **Jalankan scan:**
```powershell
.\scripts\analyze.ps1
```

4. **Ikuti instruksi di layar** — DrivePulse akan kasih tau apa yang bisa dihapus dan gimana caranya.

### Butuh Panduan Lebih Detail?
Buka file [`docs/guide.md`](docs/guide.md) — panduan lengkap dengan penjelasan tiap langkah.

---

## 🔒 Keamanan & Privasi

- ✅ **100% lokal** — tidak ada data yang dikirim ke internet
- ✅ **No telemetry** — tidak ada tracking atau analytics
- ✅ **Open source** — kode bisa diperiksa siapa saja
- ✅ **Dry-run default** — tidak ada yang dihapus tanpa konfirmasi kamu
- ✅ **Backup sebelum hapus** — file dipindah ke staging area, bisa di-restore

---

## ❓ FAQ

**Q: Apakah laptop saya bakal lemot pas scan?**  
A: Enggak. Quick Scan cuma baca ukuran folder, gak berat. Deep Scan sedikit lebih intensif tapi tetap ringan.

**Q: Apakah file yang udah dihapus bisa dibalikin?**  
A: Ya! DrivePulse backup file ke staging area sebelum hapus. Dalam 7 hari (default), kamu bisa restore kapan aja.

**Q: Aman buat laptop kantor?**  
A: Aman. DrivePulse cuma scan dan kasih rekomendasi. Mode default adalah dry-run (preview only). Gak ada yang dihapus tanpa konfirmasi eksplisit dari kamu.

**Q: Kenapa perlu "Run as Administrator"?**  
A: Untuk scan folder sistem (Windows Temp, Update files). Kalau gak pakai admin, DrivePulse tetap jalan tapi skip folder yang butuh akses khusus.

**Q: Apakah butuh internet?**  
A: Tidak. Semua proses berjalan offline di laptop kamu.

---

## 📦 Tech Stack

- **PowerShell 5.1+** — bawaan Windows, zero-install
- **Windows 10/11 Only** (untuk sekarang)
- **No dependencies** — tinggal clone/download, langsung jalan
- **Roadmap**: GUI desktop app + HTML report visual

---

## 🗂️ Struktur Project

```
drivepulse/
├── scripts/        → Entry point utama (mulai dari sini)
├── src/            → Source code (scanner, reporter, cleaner)
├── docs/           → Dokumentasi & panduan
├── config/         → Default rules & konfigurasi
├── tests/          → Testing scripts
├── installer/      → Build installer
└── assets/         → Logo, screenshot
```

Detail lengkap ada di [PRD.md](PRD.md) section 9.

---

## 🛠️ Untuk Developer

```
┌──────────────────────────────────────────┐
│  Baca PRD.md dulu — itu blueprint produk │
│  Pahamin visi sebelum mulai coding       │
└──────────────────────────────────────────┘
```

### Setup Development
```powershell
git clone https://github.com/user/drivepulse.git
cd drivepulse
# Langsung bisa jalan, gak perlu install apa-apa
.\scripts\analyze.ps1
```

### Menjalankan Tests
```powershell
.\tests\test-scan.ps1
```

### Dokumen Penting
| File | Isi |
|------|-----|
| [PRD.md](PRD.md) | Product Requirements Document — visi, fitur, roadmap |
| [docs/guide.md](docs/guide.md) | Panduan cleanup untuk end-user |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Cara kontribusi (coming soon) |
| [CHANGELOG.md](CHANGELOG.md) | Riwayat perubahan |

---

## 🤝 Cara Kontribusi

1. Fork / Clone repo ini
2. Baca [PRD.md](PRD.md) — pahami visi dan roadmap
3. Buat branch baru: `git checkout -b feature/nama-fitur`
4. Coding + testing
5. Pull request ke `main`

Lihat [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) untuk panduan detail.

---

## 📋 Roadmap

| Versi | Status | Isi |
|-------|--------|-----|
| v1.0 | ✅ Done | PRD + Struktur project |
| v1.1 | 🔄 In Progress | Core Scanner + CLI interaktif |
| v1.2 | ⏳ Planned | HTML report + User preferences |
| v1.3 | ⏳ Planned | One-Click Cleanup + Backup + Rollback |
| v1.4 | ⏳ Planned | Installer (.exe) |
| v2.0 | ⏳ Planned | GUI desktop app |

---

## 📜 Lisensi

[MIT License](LICENSE) — bebas dipakai, dimodifikasi, dan disebarkan.

---

> Dibuat dengan 🦥 oleh **Yombi** & **Heri Prasetyo R**  
> Dikembangin dengan 🤖 oleh **Kiro AI**

# 🧹 DrivePulse

> **Analisis & petunjuk pembersihan drive Windows — dalam Bahasa Indonesia yang manusiawi.**

DrivePulse adalah tools untuk bantu kamu ngerti **kenapa** drive C: laptop hampir penuh dan **gimana** cara ngatasinnya. Bukan cuma nunjukin angka — tapi ngasih penjelasan dan langkah yang jelas.

## ✨ Fitur

- 🔍 **Scan cepat** — tau folder mana yang makan ruang paling banyak
- ✅ **Kategorisasi** — item **aman dihapus** vs **perlu dicek manual**
- 🧹 **Panduan langkah demi langkah** — tinggal ikutin, gak perlu panggil teknisi
- 📊 **Export report** — simpen hasil scan buat diliatin ke temen
- 🚀 **Siap diotomasi** — script PowerShell, tinggal jalanin

## 🚀 Cara Pake (Buat User)

### Opsi 1: Jalanin Script (Paling Cepet)
1. Buka **PowerShell** (klik kanan → Run as Administrator)
2. Ketik:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```
3. Jalanin:
```powershell
.\scripts\analyze.ps1
```

### Opsi 2: Ikutin Panduan Manual
Buka file `docs/guide.md` — semua ada di situ, lengkap dengan gambar.

## 🛠️ Untuk Developer

```
┌─────────────────────────────────┐
│  Baca PRD.md dulu — itu visi    │
│  produk. Pahamin sebelum coding  │
└─────────────────────────────────┘
```

- **PRD.md** → Product Requirements Document (blueprint produk)
- **scripts/** → Entry point utama
- **src/** → Source code yang lebih rapi
- **docs/** → Dokumentasi dan panduan

## 📦 Stack

- **PowerShell 5.1+** — masa depan: Python GUI / HTML report
- **Windows Only** (buat sekarang)
- **No dependencies** — tinggal git clone, langsung jalan

## 🤝 Cara Kontribusi

1. Fork / Clone repo ini
2. Baca PRD.md
3. Coding, testing
4. Pull request

Atau kalo dikerjain via **Kiro AI + Claude Opus**: clone repo → pelajari struktur → develop fitur sesuai roadmap di PRD.

## 📜 Lisensi

MIT — bebas dipake, dimodif, disebar. Tapi kalo laku, traktir kopi ☕

---

> Dibuat dengan 🦥 oleh **Yombi** & **Heri Prasetyo R**  
> Dikembangin dengan 🤖 oleh **Kiro AI + Claude Opus**

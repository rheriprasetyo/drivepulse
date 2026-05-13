# 🧹 DrivePulse — Product Requirements Document (PRD)

> **Versi:** 1.0
> **Tanggal:** 2026-05-14
> **Author:** Yombi (Personal Assistant) + Heri Prasetyo R (Product Owner)

---

## 1. Ringkasan Eksekutif

**DrivePulse** adalah tools untuk **menganalisis dan merekomendasikan pembersihan drive Windows** yang hampir penuh. Bedanya sama Disk Cleanup bawaan Windows: DrivePulse kasih **penjelasan dalam bahasa manusia** — bukan cuma centang-centang abstrak. Target utamanya: orang Indonesia awam yang laptopnya lemot karena C: penuh.

---

## 2. Visi Produk

> "Bikin orang ngerti **kenapa** laptopnya penuh dan **gampang** ngatasinnya, tanpa harus panggil tukang servis."

---

## 3. Target Pengguna

| Tipe User | Level Teknis | Kebutuhan |
|-----------|-------------|-----------|
| **Orang kantoran** | Rendah | Tinggal klik, dikasih tau apa yg harus dihapus |
| **Mahasiswa** | Rendah-Sedang | Gratis, simpel, bikin laptop kenceng lagi |
| **IT Support / Teknisi** | Tinggi | Mau liat breakdown detail + export report |
| **Dev / Programmer** | Tinggi | Mau script yang bisa diotomasi |

---

## 4. Masalah yang Diselesaikan

1. **C: Drive penuh** — notifikasi merah annoying
2. **User bingung** — gak tau folder mana yang aman dihapus
3. **Takut salah hapus** — khawatir file penting ilang
4. **Tools existing ribet** — WinDirStat terlalu teknis, CCleaner banyak iklan
5. **Gak ada panduan bahasa Indonesia** — dokumentasi kebanyakan Bahasa Inggris

---

## 5. Fitur Utama (MVP)

### 5.1 Scan & Analysis 🔍
- Scan folder C: drive — deteksi folder terbesar
- Kategorikan: **Aman dihapus** ✅ vs **Perlu dicek** ❓
- Hitung potensi ruang yang bisa dikosongkan

### 5.2 Visual Report 📊
- Tampilkan daftar folder/tipe file terbesar
- Presentase penggunaan vs kapasitas
- Kode warna: merah (kritis), kuning (warning), hijau (aman)

### 5.3 Cleanup Guide 📖
- Panduan langkah demi langkah tiap item
- Bahasa Indonesia
- Sertakan screenshot/ilustrasi

### 5.4 One-Click Cleanup (Advanced) 🚀
- Hapus otomatis item yang **aman** (temp, cache, npm, recycle bin)
- Konfirmasi sebelum hapus
- Rollback option (pindahkan ke folder backup dulu)

### 5.5 Report Export 📤
- Export ke file .txt atau .html
- Bisa dikirim ke teknisi/teman

---

## 6. Tech Stack

| Layer | Teknologi | Alasan |
|-------|-----------|--------|
| **Scripting** | PowerShell 5.1+ | Bawaan Windows, gak perlu install apa2 |
| **CLI Tool** | PowerShell + .ps1 | Jalan di semua Windows 10/11 |
| **GUI (Future)** | Python Tkinter / Electron | Buat user yang gak suka terminal |
| **Report** | HTML + CSS | Bisa dibuka di browser, cakep |
| **Storage** | File lokal (JSON) | Simpan history scan |
| **Platform** | Windows Only (dulu) | Target pertama: C: Drive |

---

## 7. Struktur Folder

```
c-drive-doctor/
├── README.md                  # Penjelasan project
├── PRD.md                     # Dokumen ini
├── LICENSE                    # Lisensi MIT
├── .gitignore                 # File yang gak usah di-push
│
├── src/                       # Source code utama
│   ├── scanner/               # Logic scanning drive
│   │   ├── scan.ps1           # Main scanner (PowerShell)
│   │   ├── categorize.ps1     # Kategorisasi aman/tidak
│   │   └── types.ps1          # Tipe-tipe file & folder
│   │
│   ├── reporter/              # Pembuat laporan
│   │   ├── report.ps1         # Generate report
│   │   └── template.html      # Template HTML report
│   │
│   └── ui/                    # User interface (nanti)
│       ├── cli.ps1            # CLI menu interaktif
│       └── gui.py             # GUI Python (future)
│
├── scripts/                   # Utility scripts
│   ├── analyze.ps1            # Analisis cepat (entry point)
│   ├── clean-safe.ps1         # Hapus item aman
│   └── restore.ps1            # Rollback (future)
│
├── docs/                      # Dokumentasi
│   ├── guide.md               # Panduan lengkap cleanup
│   └── CONTRIBUTING.md        # Cara kontribusi (kalo open source)
│
├── tests/                     # Testing
│   └── test-scan.ps1          # Test scanning logic
│
└── assets/                    # Gambar, icon, dll
    └── logo.png               # Logo product
```

---

## 8. User Flow

```
User buka DrivePulse
        │
        ▼
[1] Pilih mode: Quick Scan / Deep Scan
        │
        ▼
[2] Scanning C: Drive...
        │
        ▼
[3] Tampilkan hasil:
   ┌─────────────────────────────┐
   │ 🔴 C: Drive — 309/325 GB    │
   │                             │
   │ ✅ Aman dihapus: 25 GB      │
   │ ❓ Perlu dicek: 15 GB       │
   │                             │
   │ 📋 Lihat detail             │
   │ 🧹 Bersihin yang aman       │
   │ 📤 Export report            │
   │ 📖 Panduan lengkap          │
   └─────────────────────────────┘
        │
        ▼
[4] User pilih action
        │
        ├─→ Lihat detail → breakdown per folder
        ├─→ Bersihin → hapus item aman (konfirmasi)
        ├─→ Export → simpan report
        └─→ Panduan → buka docs/guide.md
```

---

## 9. Kriteria "Aman vs Perlu Dicek"

### ✅ Aman Dihapus (Direct Cleanup)
| Item | Keterangan |
|------|-----------|
| Temp Files (%temp%) | Sampah sementara |
| Windows Temp (C:\Windows\Temp) | Sampah sistem |
| npm-cache | Bisa di-re-download |
| pip cache | Bisa di-re-download |
| Browser Cache | Bisa di-re-build |
| Recycle Bin | Udah di-delete user |
| Windows Update Cleanup | File update lama |
| Prefetch | Cache boot, aman dihapus |
| Zoom cache/log | Cache meeting |

### ❓ Perlu Dicek Manual
| Item | Alasan |
|------|--------|
| Downloads | Mungkin ada file penting |
| CapCut cache | Project video mungkin dipake |
| 3uTools backup | Backup iPhone mungkin penting |
| Large folders > 5GB | Tergantung konteks |
| Windows.old | Backup setelah update Windows |

---

## 10. Non-Goals (Gak Akan Dibikin Dulu)

- ❌ Versi macOS / Linux
- ❌ Pembersihan registry
- ❌ Uninstaller aplikasi
- ❌ Antivirus / security scan
- ❌ Cloud backup integration

---

## 11. Metrik Kesuksesan

| Metrik | Target (MVP) |
|--------|-------------|
| ⏱️ Scan time | < 30 detik |
| 📊 Akurasi kategorisasi | > 90% |
| 🎯 User bisa kosongin >10GB | 80% user |
| 😊 User puas | Survey > 4/5 |

---

## 12. Roadmap

| Fase | Timeline | Isi |
|------|---------|-----|
| **v1.0 — MVP** | Sekarang | PRD + Struktur + Script dasar |
| **v1.1 — Core** | Milestone 1 | Scanner lengkap + CLI interaktif |
| **v1.2 — Report** | Milestone 2 | HTML report + visual |
| **v1.3 — Safety** | Milestone 3 | Backup sebelum hapus + rollback |
| **v2.0 — GUI** | Milestone 4 | Python GUI / Electron app |
| **v3.0 — Public** | Milestone 5 | Release publik + dokumentasi |

---

## 13. Cara Kontribusi untuk Kiro (Claude Opus)

1. Clone repo ini
2. Baca PRD.md dan pahami visi produk
3. Mulai dari `scripts/analyze.ps1` — ini entry point paling sederhana
4. Kembangin sesuai roadmap
5. Jangan commit file sampah (temp, cache, node_modules)
6. Target utama: **user non-teknis Indonesia** — jadi semua panduan harus Bahasa Indonesia yang santai

---

> *"Dibuat dengan 🦥 oleh Yombi + Heri. Dikembangin dengan 🤖 oleh Kiro AI + Claude Opus."*

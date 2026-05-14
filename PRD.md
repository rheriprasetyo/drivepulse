# 🧹 DrivePulse — Product Requirements Document (PRD)

> **Versi:** 1.1  
> **Tanggal:** 2026-05-14  
> **Author:** Yombi (Personal Assistant) + Heri Prasetyo R (Product Owner)  
> **Status:** Draft — iterasi aktif

---

## 1. Ringkasan Eksekutif

**DrivePulse** adalah tools untuk **menganalisis dan merekomendasikan pembersihan drive Windows** yang hampir penuh. Bedanya sama Disk Cleanup bawaan Windows: DrivePulse kasih **penjelasan dalam bahasa manusia** — bukan cuma centang-centang abstrak. Target utamanya: orang Indonesia awam yang laptopnya lemot karena C: penuh.

**Model bisnis:** SaaS (roadmap). MVP berjalan sepenuhnya lokal tanpa koneksi internet. Komponen cloud (dashboard, multi-device, subscription) akan dikembangkan di fase berikutnya.

---

## 2. Visi Produk

> "Bikin orang ngerti **kenapa** laptopnya penuh dan **gampang** ngatasinnya, tanpa harus panggil tukang servis."

---

## 3. Target Pengguna

| Tipe User | Level Teknis | Kebutuhan | Channel Akuisisi |
|-----------|-------------|-----------|-----------------|
| **Orang kantoran** | Rendah | Tinggal klik, dikasih tau apa yg harus dihapus | TikTok teknisi, WA group |
| **Mahasiswa** | Rendah-Sedang | Gratis, simpel, bikin laptop kenceng lagi | YouTube tutorial, kampus |
| **IT Support / Teknisi** | Tinggi | Breakdown detail + export report buat client | Forum teknisi, komunitas |
| **Dev / Programmer** | Tinggi | Script yang bisa diotomasi | GitHub, dev community |

---

## 4. Masalah yang Diselesaikan

1. **C: Drive penuh** — notifikasi merah annoying, laptop lemot
2. **User bingung** — gak tau folder mana yang aman dihapus
3. **Takut salah hapus** — khawatir file penting ilang
4. **Tools existing ribet** — WinDirStat terlalu teknis, CCleaner banyak iklan
5. **Gak ada panduan bahasa Indonesia** — dokumentasi kebanyakan Bahasa Inggris
6. **Gak ada trust** — user gak percaya tools random buat hapus file mereka

---

## 5. Diferensiasi vs Kompetitor

| Fitur | DrivePulse | Disk Cleanup | WinDirStat | CCleaner |
|-------|-----------|-------------|-----------|---------|
| Bahasa Indonesia | ✅ | ❌ | ❌ | ❌ |
| Penjelasan plain-language | ✅ | ❌ | ❌ | ⚠️ Minimal |
| No iklan / bloatware | ✅ | ✅ | ✅ | ❌ |
| Dry-run mode (preview dulu) | ✅ | ❌ | N/A | ❌ |
| Audit log (riwayat hapus) | ✅ | ❌ | ❌ | ❌ |
| Rollback / backup otomatis | ✅ (v1.3) | ❌ | N/A | ❌ |
| Open source | ✅ | ❌ | ✅ | ❌ |
| Zero-install (PowerShell) | ✅ | ✅ | ❌ | ❌ |
| Installer (.exe) | ✅ (v1.1+) | Built-in | ✅ | ✅ |

---

## 6. Fitur Utama

### 6.1 Scan & Analysis 🔍 (MVP — v1.1)
- Scan folder C: drive — deteksi folder terbesar
- **Quick Scan**: top-level folders + known junk locations (< 15 detik)
- **Deep Scan**: recursive scan semua subfolder (< 60 detik)
- Kategorikan: **Aman dihapus** ✅ vs **Perlu dicek** ❓
- Hitung potensi ruang yang bisa dikosongkan
- **Dry-run mode** sebagai default — tampilkan apa yang *akan* dihapus tanpa menghapus

### 6.2 Visual Report 📊 (v1.2)
- Tampilkan daftar folder/tipe file terbesar
- Persentase penggunaan vs kapasitas
- Kode warna: merah (kritis >90%), kuning (warning 75-90%), hijau (aman <75%)
- Export ke HTML (bisa dibuka di browser)
- Export ke TXT (plain text, bisa di-copy paste)

### 6.3 Cleanup Guide 📖 (v1.1)
- Panduan langkah demi langkah tiap item
- Bahasa Indonesia santai
- Sertakan penjelasan efek samping tiap pembersihan
- Peringatan untuk item yang butuh perhatian khusus

### 6.4 One-Click Cleanup 🚀 (v1.3 — Safety)
- Hapus otomatis item yang **aman** (temp, cache, recycle bin)
- **Wajib konfirmasi** sebelum hapus — tampilkan ringkasan
- **Backup otomatis** ke folder staging sebelum hapus permanen
- Retention period: 7 hari (configurable), auto-purge setelahnya
- **Audit log**: catat semua file yang dihapus (timestamp, path, size)

### 6.5 Rollback & Safety Net 🛡️ (v1.3)
- Pindahkan file ke `%LOCALAPPDATA%\DrivePulse\Backup\` sebelum hapus
- Restore individual file atau batch
- Auto-purge backup setelah retention period
- Log tersimpan di `%LOCALAPPDATA%\DrivePulse\Logs\`

### 6.6 User Preferences ⚙️ (v1.2)
- **Whitelist**: folder yang gak boleh disentuh (user-defined)
- **Blacklist tambahan**: folder custom yang mau selalu dihapus
- **Threshold configurable**: "Large folder" default 5GB, bisa diubah
- Simpan di `%LOCALAPPDATA%\DrivePulse\config.json`

---

## 7. Kriteria "Aman vs Perlu Dicek"

### ✅ Aman Dihapus (Direct Cleanup)

| Item | Keterangan | Efek Samping |
|------|-----------|-------------|
| Temp Files (%temp%) | Sampah sementara | Tidak ada |
| Windows Temp (C:\Windows\Temp) | Sampah sistem | Tidak ada |
| npm-cache | Bisa di-re-download | Install package lebih lambat sementara |
| pip cache | Bisa di-re-download | Install package lebih lambat sementara |
| Browser Cache | Bisa di-rebuild | Website loading lebih lambat sementara |
| Recycle Bin | Udah di-delete user | File gak bisa di-restore dari Recycle Bin |
| Windows Update Cleanup | File update lama | Gak bisa uninstall update lama |
| Prefetch | Cache boot | Boot pertama setelahnya sedikit lebih lambat |
| Zoom cache/log | Cache meeting | Tidak ada |
| Thumbnail cache | Cache preview gambar | Explorer loading gambar lebih lambat sementara |

### ❓ Perlu Dicek Manual

| Item | Alasan | Rekomendasi |
|------|--------|-------------|
| Downloads | Mungkin ada file penting | Tampilkan file terbesar, biarkan user pilih |
| CapCut cache | Project video mungkin dipake | Tanya user apakah masih ada project aktif |
| 3uTools backup | Backup iPhone mungkin penting | Warn: "Ini backup device, yakin mau hapus?" |
| Large folders > threshold | Tergantung konteks | Tampilkan nama + size, biarkan user decide |
| Windows.old | Backup setelah update Windows | Warn: "Kalau hapus, gak bisa rollback Windows" |
| Hibernation file | hiberfil.sys bisa besar | Jelaskan trade-off hibernate vs ruang |

---

## 8. Tech Stack

| Layer | Teknologi | Alasan |
|-------|-----------|--------|
| **Scripting (MVP)** | PowerShell 5.1+ | Bawaan Windows 10/11, zero-install |
| **CLI Tool** | PowerShell .ps1 | Entry point paling ringan |
| **Report** | HTML + CSS | Bisa dibuka di browser, visual |
| **Storage** | JSON lokal | Config, history, audit log |
| **Installer** | Inno Setup / NSIS | Bikin .exe installer untuk user awam |
| **GUI (v2.0)** | TBD (Tauri / Electron / Tkinter) | Keputusan di milestone 4 |
| **Platform** | Windows 10/11 Only | Target pertama |

### Minimum Requirements
- Windows 10 (build 1809+) atau Windows 11
- PowerShell 5.1 (bawaan)
- RAM: 2 GB minimum
- Ruang kosong: 100 MB (untuk backup staging)
- Tidak butuh koneksi internet

---

## 9. Struktur Folder Project

```
drivepulse/
├── README.md                  # Penjelasan project
├── PRD.md                     # Dokumen ini
├── CHANGELOG.md               # Riwayat perubahan
├── LICENSE                    # Lisensi MIT
├── .gitignore                 # File yang gak usah di-push
│
├── src/                       # Source code utama
│   ├── scanner/               # Logic scanning drive
│   │   ├── scan.ps1           # Main scanner (PowerShell)
│   │   ├── categorize.ps1     # Kategorisasi aman/tidak
│   │   └── types.ps1          # Definisi tipe file & folder
│   │
│   ├── reporter/              # Pembuat laporan
│   │   ├── report.ps1         # Generate report
│   │   └── template.html      # Template HTML report
│   │
│   ├── cleaner/               # Logic pembersihan
│   │   ├── clean.ps1          # Eksekusi cleanup
│   │   ├── backup.ps1         # Backup sebelum hapus
│   │   └── restore.ps1        # Rollback dari backup
│   │
│   └── ui/                    # User interface
│       ├── cli.ps1            # CLI menu interaktif
│       └── gui/               # GUI app (v2.0)
│
├── scripts/                   # Entry point scripts
│   ├── analyze.ps1            # Quick analysis (main entry)
│   ├── deep-scan.ps1          # Deep scan mode
│   └── clean-safe.ps1         # Cleanup dengan konfirmasi
│
├── config/                    # Default configuration
│   └── default-rules.json     # Aturan kategorisasi default
│
├── docs/                      # Dokumentasi
│   ├── guide.md               # Panduan lengkap cleanup
│   ├── faq.md                 # Frequently Asked Questions
│   ├── CONTRIBUTING.md        # Cara kontribusi
│   └── PRIVACY.md             # Privacy statement
│
├── installer/                 # Installer build files
│   └── setup.iss              # Inno Setup script
│
├── tests/                     # Testing
│   ├── test-scan.ps1          # Test scanning logic
│   ├── test-categorize.ps1    # Test kategorisasi
│   └── test-clean.ps1         # Test cleanup (mock)
│
└── assets/                    # Gambar, icon, dll
    ├── logo.png               # Logo product
    └── screenshots/           # Screenshot untuk docs/README
```

---

## 10. User Flow

```
User install DrivePulse (atau jalanin script)
        │
        ▼
[1] Pilih mode:
    • Quick Scan — folder utama + known junk (< 15 detik)
    • Deep Scan — recursive semua subfolder (< 60 detik)
        │
        ▼
[2] Scanning C: Drive...
    (progress bar + estimasi waktu)
        │
        ▼
[3] Tampilkan hasil:
   ┌─────────────────────────────────┐
   │ 🔴 C: Drive — 309/325 GB (95%) │
   │                                 │
   │ ✅ Aman dihapus: 25 GB          │
   │ ❓ Perlu dicek: 15 GB           │
   │                                 │
   │ [1] 📋 Lihat detail             │
   │ [2] 🧹 Bersihin yang aman       │
   │ [3] 📤 Export report            │
   │ [4] 📖 Panduan lengkap          │
   │ [5] ⚙️  Pengaturan              │
   └─────────────────────────────────┘
        │
        ▼
[4] User pilih action
        │
        ├─→ [1] Detail → breakdown per folder + efek samping
        ├─→ [2] Bersihin → DRY-RUN preview → konfirmasi → backup → hapus
        ├─→ [3] Export → pilih format (HTML/TXT) → simpan
        ├─→ [4] Panduan → buka guide step-by-step
        └─→ [5] Settings → whitelist, threshold, dll
```

### Error States
| Situasi | Handling |
|---------|----------|
| Akses ditolak (folder protected) | Skip + catat di log, lanjut scan |
| Drive offline / not found | Tampilkan error jelas + saran |
| Scan interrupted (user cancel) | Simpan partial result, bisa resume |
| Disk space 0% free | Warning mode: "Gak bisa bikin backup, mau lanjut tanpa safety net?" |
| Bukan admin (elevated needed) | Jelaskan kenapa perlu admin + cara run as admin |

---

## 11. Permission & Security

| Operasi | Level Akses | Keterangan |
|---------|------------|------------|
| Scan (read-only) | User biasa | Gak perlu admin |
| Hapus temp user | User biasa | Folder milik user |
| Hapus Windows Temp | Administrator | Folder sistem |
| Hapus Windows Update | Administrator | Butuh elevated |
| Export report | User biasa | Tulis ke folder user |

**Privacy Statement:**
- Semua proses berjalan 100% lokal
- Tidak ada telemetry, tracking, atau upload data
- Tidak ada koneksi internet yang dibutuhkan
- Source code terbuka untuk audit

---

## 12. Metrik Kesuksesan

| Metrik | Target (MVP) | Cara Ukur |
|--------|-------------|-----------|
| ⏱️ Quick Scan time | < 15 detik | Timer internal |
| ⏱️ Deep Scan time | < 60 detik | Timer internal |
| 📊 Akurasi kategorisasi | > 95% | Manual testing 50 PC berbeda |
| 🎯 User bisa kosongin >10GB | 80% user | Survey post-use |
| 😊 User puas | > 4/5 | In-app feedback (opsional) |
| 🐛 Zero data loss | 100% | Tidak ada laporan file penting terhapus |
| 📥 Download count (setelah release) | 1000 dalam 3 bulan | GitHub/installer analytics |

---

## 13. Non-Goals (Gak Akan Dibikin Dulu)

- ❌ Versi macOS / Linux
- ❌ Pembersihan registry
- ❌ Uninstaller aplikasi
- ❌ Antivirus / security scan
- ❌ Cloud backup integration (sampai SaaS phase)
- ❌ Real-time monitoring (background service)
- ❌ Scheduled automatic cleanup

---

## 14. Roadmap

| Fase | Scope | Deliverables |
|------|-------|-------------|
| **v1.0 — Foundation** | Sekarang | PRD v1.1 + Struktur folder + Skeleton scripts |
| **v1.1 — Core Scanner** | Milestone 1 | Scanner lengkap + CLI interaktif + Dry-run + Guide |
| **v1.2 — Report & Config** | Milestone 2 | HTML report + User preferences + Whitelist |
| **v1.3 — Safety & Cleanup** | Milestone 3 | One-Click Cleanup + Backup + Rollback + Audit log |
| **v1.4 — Installer** | Milestone 4 | .exe installer + Auto-update check |
| **v2.0 — GUI** | Milestone 5 | Desktop GUI app |
| **v3.0 — SaaS** | Milestone 6 | Cloud dashboard + Multi-device + Subscription |

---

## 15. Trust & Safety Principles

1. **Dry-run first** — Selalu preview sebelum hapus. User harus opt-in untuk aksi destruktif.
2. **Backup before delete** — Semua file dipindah ke staging area sebelum dihapus permanen.
3. **Audit everything** — Setiap aksi tercatat: apa yang dihapus, kapan, berapa besar.
4. **Transparent** — Open source, no telemetry, penjelasan jelas tiap aksi.
5. **Reversible** — Dalam retention period, semua bisa di-rollback.
6. **Least privilege** — Minta admin access hanya kalau benar-benar dibutuhkan.
7. **User in control** — Whitelist, threshold, dan rules bisa di-customize.

---

## 16. Acceptance Criteria (MVP — v1.1)

| ID | Kriteria | Testable? |
|----|----------|-----------|
| AC-1 | Quick Scan selesai dalam < 15 detik di drive 500GB | ✅ |
| AC-2 | Hasil scan menampilkan minimal: total used, total free, list folder terbesar | ✅ |
| AC-3 | Setiap item dikategorikan Aman/Perlu Dicek dengan penjelasan | ✅ |
| AC-4 | Dry-run mode tidak menghapus file apapun | ✅ |
| AC-5 | Output CLI readable di PowerShell tanpa karakter rusak | ✅ |
| AC-6 | Script berjalan tanpa error di Windows 10 & 11 fresh install | ✅ |
| AC-7 | Folder yang access denied di-skip tanpa crash | ✅ |
| AC-8 | Semua teks UI dalam Bahasa Indonesia | ✅ |

---

## 17. Cara Kontribusi

1. Clone repo ini
2. Baca PRD.md (dokumen ini) dan pahami visi produk
3. Mulai dari `scripts/analyze.ps1` — ini entry point utama
4. Kembangin sesuai roadmap
5. Jangan commit file sampah (temp, cache, node_modules)
6. Target utama: **user non-teknis Indonesia** — semua panduan harus Bahasa Indonesia yang santai
7. Baca `docs/CONTRIBUTING.md` untuk detail teknis

---

> *"Dibuat dengan 🦥 oleh Yombi + Heri. Dikembangin dengan 🤖 oleh Kiro AI."*

# 🔒 Privacy Statement — DrivePulse

> **Terakhir diperbarui:** 2026-05-14

---

## Ringkasan

DrivePulse **tidak mengumpulkan, mengirim, atau menyimpan data kamu ke server manapun**. Semua proses berjalan 100% lokal di komputer kamu.

---

## Detail

### Apa yang DrivePulse akses?
- **Membaca** ukuran folder dan file di drive C: (untuk analisis)
- **Membaca** nama folder dan path (untuk kategorisasi)
- **Menulis** file report ke lokasi yang kamu pilih
- **Menulis** backup ke `%LOCALAPPDATA%\DrivePulse\Backup\` (sebelum hapus)
- **Menulis** log ke `%LOCALAPPDATA%\DrivePulse\Logs\` (audit trail)
- **Menulis** config ke `%LOCALAPPDATA%\DrivePulse\config.json` (preferensi)

### Apa yang DrivePulse TIDAK lakukan?
- ❌ Tidak mengirim data ke internet
- ❌ Tidak ada telemetry atau analytics
- ❌ Tidak ada tracking penggunaan
- ❌ Tidak membaca isi file (hanya ukuran dan nama)
- ❌ Tidak mengakses file pribadi (dokumen, foto, dll) kecuali diminta user
- ❌ Tidak berjalan di background (hanya aktif saat dijalankan)

### Koneksi Internet
DrivePulse **tidak membutuhkan** dan **tidak membuat** koneksi internet apapun. Tool ini bisa dijalankan di komputer yang sepenuhnya offline.

### Data yang Disimpan Lokal
| Data | Lokasi | Tujuan | Bisa Dihapus? |
|------|--------|--------|---------------|
| Config | `%LOCALAPPDATA%\DrivePulse\config.json` | Preferensi user | ✅ Ya |
| Audit log | `%LOCALAPPDATA%\DrivePulse\Logs\` | Riwayat cleanup | ✅ Ya |
| Backup | `%LOCALAPPDATA%\DrivePulse\Backup\` | Safety net | ✅ Ya (auto-purge 7 hari) |

### Uninstall
Hapus folder `%LOCALAPPDATA%\DrivePulse\` untuk menghapus semua data yang pernah dibuat DrivePulse.

---

## Open Source
Kode sumber DrivePulse terbuka dan bisa diperiksa siapa saja. Kamu bisa verifikasi sendiri bahwa tidak ada kode yang mengirim data ke luar.

---

> Punya pertanyaan soal privasi? Buka Issue di GitHub.

# ❓ FAQ — DrivePulse

Pertanyaan yang sering ditanyakan.

---

## Umum

### Apa itu DrivePulse?
Tools untuk menganalisis drive C: yang hampir penuh dan kasih rekomendasi pembersihan dalam Bahasa Indonesia yang gampang dipahami.

### Apakah gratis?
Ya, DrivePulse gratis dan open source (MIT License).

### Apakah aman?
Ya. DrivePulse:
- Tidak menghapus apapun tanpa konfirmasi kamu
- Default mode adalah "preview only" (dry-run)
- Backup file sebelum dihapus
- Tidak butuh internet
- Open source — kode bisa diperiksa

---

## Penggunaan

### Apakah laptop saya bakal lemot pas scan?
Enggak. Quick Scan cuma baca ukuran folder (< 15 detik). Deep Scan sedikit lebih intensif tapi tetap ringan (< 60 detik).

### Apakah file yang udah dihapus bisa dibalikin?
Ya! DrivePulse backup file ke staging area sebelum hapus. Dalam 7 hari (default), kamu bisa restore kapan aja.

### Aman buat laptop kantor?
Aman. DrivePulse cuma scan dan kasih rekomendasi. Tidak ada yang dihapus tanpa konfirmasi eksplisit.

### Kenapa perlu "Run as Administrator"?
Untuk scan folder sistem (Windows Temp, Update files). Tanpa admin, DrivePulse tetap jalan tapi skip folder yang butuh akses khusus.

### Apakah butuh internet?
Tidak. Semua proses berjalan offline di laptop kamu.

### Bisa scan drive selain C:?
Untuk sekarang fokus di C: dulu. Support drive lain ada di roadmap.

---

## Teknis

### Windows versi berapa yang didukung?
Windows 10 (build 1809+) dan Windows 11.

### Perlu install sesuatu?
Tidak. DrivePulse pakai PowerShell yang sudah bawaan Windows.

### Kenapa harus ketik Set-ExecutionPolicy?
Ini cuma mengizinkan PowerShell menjalankan script untuk sesi ini saja. Tidak mengubah setting Windows secara permanen dan tidak membuat sistem rentan.

### Data DrivePulse disimpan di mana?
Di `%LOCALAPPDATA%\DrivePulse\`. Bisa dihapus kapan saja.

### Bagaimana cara uninstall?
Hapus folder DrivePulse dan `%LOCALAPPDATA%\DrivePulse\`. Selesai.

---

## Troubleshooting

### Script error "cannot be loaded because running scripts is disabled"
Jalankan dulu:
```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Beberapa folder menampilkan "Access Denied"
Normal. Itu folder sistem yang butuh admin access. Jalankan PowerShell sebagai Administrator, atau abaikan — DrivePulse tetap scan folder lainnya.

### Scan lama banget (> 60 detik)
Kemungkinan drive sangat penuh atau banyak file kecil. Coba Quick Scan dulu, Deep Scan bisa dijalankan nanti.

---

> Pertanyaan lain? Buka Issue di GitHub atau hubungi @rheriprasetyo

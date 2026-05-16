# Prompt Kiro — Task: Notif 7 Hari di Summary Cleanup

## Goal
Tambah notifikasi di akhir proses cleanup yang ngasih tau user bahwa file ada di staging selama 7 hari, dan apa yang bisa dilakukan.

## Branch
`feature/cleanup-notification` (dari master)

## File
`src/cleaner/clean.ps1`

## Lokasi Perubahan
Di function `Start-SafeCleanup`, di bagian **Ringkasan Pembersihan** (setelah baris `Write-Host "  Waktu         : $elapsedSeconds detik"` dan **sebelum** `Write-Host ""` yang terakhir).

## Yang ditambah

```powershell
        $expiryDate = (Get-Date).AddDays(7).ToString("dd MMMM yyyy")
        Write-Host ""
        Write-Host "  ⚠️ FILE ADA DI PENYIMPANAN (STAGING) SELAMA 7 HARI" -ForegroundColor Yellow
        Write-Host "     Lewat menu [6] Backup kamu bisa:" -ForegroundColor White
        Write-Host "       ✅ Restore file kalo nyesal" -ForegroundColor Gray
        Write-Host "       🗑️  Hapus permanen kalo udah yakin" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  📌 File akan otomatis terhapus permanen: $expiryDate" -ForegroundColor Cyan
```

## Cek hasil
Jalankan quick scan → cleanup → pilih item → y → notif muncul di summary.

## Commit
Setelah selesai, jangan commit dulu. Laporkan ke Yombi.

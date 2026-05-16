# Prompt Kiro — Task: Gabung Menu [6] Backup + [7] Staging jadi [6] Penyimpanan

## Goal
Gabung menu [6] Backup dan [7] Staging jadi satu menu **[6] Penyimpanan**. Karena backup module udah dihapus dari cleanup flow, menu backup gak perlu lagi. File hasil cleanup langsung masuk staging, dan user kelola semuanya dari 1 menu.

## Branch
`feature/cleanup-notification` (lanjutan)

## File
`src/ui/cli.ps1`

## Perubahan

### 1. Hapus dot-source backup module (baris ~19-23)
Before:
```powershell
# Import backup module for backup/restore CLI commands
$backupModulePath = "$PSScriptRoot\..\backup\backup.ps1"
if (Test-Path $backupModulePath) {
    . $backupModulePath
}
```
After: Hapus 6 baris ini.

### 2. Ubah menu utama (baris ~751-752)
Before:
```powershell
Write-Host "  [6] Backup      -- Kelola backup & restore" -ForegroundColor White
Write-Host "  [7] Staging     -- Lihat & kelola file staging" -ForegroundColor White
```
After:
```powershell
Write-Host "  [6] Penyimpanan -- Restore / Hapus / Export file backup" -ForegroundColor White
```

### 3. Hapus handler menu [6] dan [7] lama, ganti dengan [6] baru (baris ~974-980)
Before:
```powershell
            "6" {
                # Backup
                Show-BackupMenu
            }
            "7" {
                # Staging
                Show-StagingMenu
            }
```
After:
```powershell
            "6" {
                # Penyimpanan — gabungan staging area
                Show-StorageMenu
            }
```

### 4. Tambah fungsi baru `Show-StorageMenu`

Tempatkan setelah fungsi `Show-StagingMenu` (sekitar baris ~475, sebelum fungsi `Show-BackupMenu`). Atau yang lebih rapi: ganti `Show-BackupMenu` dengan `Show-StorageMenu`.

```powershell
function Show-StorageMenu {
    <#
    .SYNOPSIS
        Menampilkan menu penyimpanan terpadu untuk mengelola file hasil cleanup.
    .DESCRIPTION
        Menu ini menggantikan Backup + Staging. File hasil cleanup masuk ke
        staging area. User bisa: restore, hapus permanen, export ke drive lain.
    #>
    
    # Baca file dari staging
    $stagedFiles = @()
    if (Get-Command Get-StagedFiles -ErrorAction SilentlyContinue) {
        $stagedFiles = @(Get-StagedFiles)
    }
    
    Write-Host ""
    Write-Host "  === Penyimpanan ===" -ForegroundColor Cyan
    Write-Host ""
    
    if ($stagedFiles.Count -eq 0) {
        Write-Host "  Penyimpanan kosong. Tidak ada file hasil cleanup." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [Enter] Kembali ke menu" -ForegroundColor White
        Read-Host "  Tekan Enter"
        return
    }
    
    # Tampilkan daftar file
    Write-Host "  File dalam penyimpanan:" -ForegroundColor White
    Write-Host "  -----------------------" -ForegroundColor DarkGray
    
    for ($i = 0; $i -lt $stagedFiles.Count; $i++) {
        $file = $stagedFiles[$i]
        $sizeStr = Format-StagingSize -Bytes $file.sizeBytes
        $dateStr = ([DateTime]::Parse($file.stagingTimestamp)).ToString("yyyy-MM-dd HH:mm")
        $expiryDate = ([DateTime]::Parse($file.stagingTimestamp)).AddDays(7).ToString("dd MMM")
        Write-Host "  [$($i+1)] $($file.originalPath)" -ForegroundColor White
        Write-Host "         Ukuran: $sizeStr | Disimpan: $dateStr | Hapus otomatis: $expiryDate" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "  [nomor]  Restore file" -ForegroundColor White
    Write-Host "  [R]      Restore semua file" -ForegroundColor White
    Write-Host "  [H]      Hapus permanen dari penyimpanan" -ForegroundColor White
    Write-Host "  [Enter]  Kembali ke menu" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "  Pilihan"
    
    # Handle numeric selection (restore single file)
    if ($choice -match '^\d+$') {
        $index = [int]$choice - 1
        if ($index -ge 0 -and $index -lt $stagedFiles.Count) {
            $selectedFile = $stagedFiles[$index]
            Write-Host ""
            Write-Host "  Restore file: $($selectedFile.originalPath)?" -ForegroundColor Yellow
            $confirm = Read-Host "  Ketik 'y' untuk restore"
            if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                if (Get-Command Restore-FromStaging -ErrorAction SilentlyContinue) {
                    $result = Restore-FromStaging -OriginalPath $selectedFile.originalPath
                    if ($result.Success) {
                        Write-Host "  ✅ File berhasil dikembalikan." -ForegroundColor Green
                    } else {
                        Write-Host "  ❌ Gagal restore: $($result.Error)" -ForegroundColor Red
                    }
                }
            }
        }
        Read-Host "  Tekan Enter untuk kembali"
        return
    }
    
    switch ($choice.ToUpper()) {
        'R' {
            # Restore semua file
            $count = 0
            foreach ($file in $stagedFiles) {
                $result = Restore-FromStaging -OriginalPath $file.originalPath
                if ($result.Success) { $count++ }
            }
            Write-Host ""
            Write-Host "  ✅ $count dari $($stagedFiles.Count) file berhasil dikembalikan." -ForegroundColor Green
            Read-Host "  Tekan Enter untuk kembali"
        }
        'H' {
            # Hapus permanen
            Write-Host ""
            Write-Host "  ⚠️ Hapus permanen $($stagedFiles.Count) file dari penyimpanan?" -ForegroundColor Red
            $confirm = Read-Host "  Ketik 'y' untuk menghapus permanen"
            if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                $count = 0
                foreach ($file in $stagedFiles) {
                    if (Get-Command Remove-FromStaging -ErrorAction SilentlyContinue) {
                        $result = Remove-FromStaging -OriginalPath $file.originalPath
                        if ($result.Success) { $count++ }
                    }
                }
                Write-Host "  🗑️ $count file dihapus permanen." -ForegroundColor Yellow
            }
            Read-Host "  Tekan Enter untuk kembali"
        }
        default {
            # Enter atau input lain → kembali
            return
        }
    }
}
```

### 5. Hapus fungsi `Show-BackupMenu` (baris ~477-...)
Fungsi ini tidak terpakai lagi karena backup module dihapus. Hapus seluruh function `Show-BackupMenu` (dari `function Show-BackupMenu {` sampai `}` penutupnya).

### 6. Hapus fungsi `Format-BackupSize` (baris ~620-...)
Juga tidak terpakai. Hapus seluruh fungsi.

## Catatan
- Fungsi `Format-StagingSize` dan `Show-StagingMenu` TETAP dipertahankan — staging masih dipake
- Fungsi `Get-StagedFiles` dan `Restore-FromStaging` berasal dari `staging.ps1` yang sudah di-dot-source
- Fungsi `Remove-FromStaging` — cek dulu apakah ada di staging.ps1. Kalo gak ada, hapus aja bagian 'H' (hapus permanen) dari kode di atas.
- Fungsi export ke USB belum diimplementasi — skip dulu (placeholder di masa depan)

## Cek hasil
1. Menu utama: [6] Penyimpanan — Restore / Hapus / Export file backup
2. Menu [7] Staging hilang
3. Menu [6] Penyimpanan tampilkan daftar file staging kalo ada
4. Bisa restore individual / restore semua / hapus permanen

## Commit
Setelah selesai, jangan commit dulu. Laporkan ke Yombi.

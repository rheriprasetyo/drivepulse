# Prompt Kiro — Restruktur Backup & Staging + Notif + Export

## Overview
DrivePulse saat ini punya **2 mekanisme** yang redundant: Backup (copy) dan Staging (move). Ini bingungin user. Tujuan restruktur ini:
1. Gabung Backup + Staging jadi 1 menu **"Penyimpanan"**
2. File hasil cleanup langsung masuk staging (**tanpa backup double**)
3. Notif 7 hari pas selesai cleanup
4. Fitur Export ke USB/HDD
5. Restore bisa pilih sumber (staging / lokasi eksternal)

## Branch
Buat branch baru: `feature/unified-storage`

## Task List (urut)

---

### TASK 1: Hapus Backup Module dari Cleanup Flow

**File:** `src/cleaner/clean.ps1`

**Apa yang diubah:**
1. Hapus dot-source backup module (baris ~21-24)
2. Di loop item (baris ~542-550), hapus panggilan `Backup-BeforeDelete`. Item cukup di-**Move-ToStaging** aja, gak perlu backup dulu.
3. Di bagian purge (baris ~502-510), hapus panggilan `Remove-ExpiredBackups`. Cuma perlu purge staging.
4. Update komentar di header function (baris 6, 302): ubah "backup > stage" jadi "stage"

**Before (loop item):**
```powershell
# 1. Backup file
if (Get-Command Backup-BeforeDelete -ErrorAction SilentlyContinue) {
    $backupResult = Backup-BeforeDelete -SourcePath $itemPath -SessionId $SessionId
    if (-not $backupResult.Success) {
        $errors += "Backup gagal untuk '$itemPath': $($backupResult.Error)"
        Write-Warning "  Melewati item (backup gagal): $itemPath"
        continue
    }
}

# 2. Stage file (move to staging area)
if (Get-Command Move-ToStaging -ErrorAction SilentlyContinue) {
    $stageResult = Move-ToStaging -SourcePath $itemPath -SessionId $SessionId
    ...
}
```

**After:**
```powershell
# Stage file (move to staging area) — backup tidak lagi diperlukan
if (Get-Command Move-ToStaging -ErrorAction SilentlyContinue) {
    $stageResult = Move-ToStaging -SourcePath $itemPath -SessionId $SessionId
    ...
}
```

---

### TASK 2: Notif 7 Hari di Summary Cleanup

**File:** `src/cleaner/clean.ps1`

**Lokasi:** Di bagian summary (setelah "=== Ringkasan Pembersihan ===" dan sebelum fungsi return)

**Yang ditambah:**
```powershell
# Notif 7 hari (setelah summary statistik)
$expiryDate = (Get-Date).AddDays(7).ToString("dd MMMM yyyy")
Write-Host ""
Write-Host "  ⚠️ FILE ADA DI PENYIMPANAN SELAMA 7 HARI" -ForegroundColor Yellow
Write-Host "     Lewat menu [6] Penyimpanan kamu bisa:" -ForegroundColor White
Write-Host "       ✅ Restore file kalo nyesal" -ForegroundColor Gray
Write-Host "       🗑️  Hapus permanen kalo udah yakin" -ForegroundColor Gray
Write-Host "       💾 Export ke USB/HDD biar aman sebelum 7 hari" -ForegroundColor Gray
Write-Host ""
Write-Host "  📌 File akan otomatis terhapus permanen: $expiryDate" -ForegroundColor Cyan
Write-Host ""
```

**Tempatnya:** Letakkan setelah baris `Write-Host "  Waktu         : $elapsedSeconds detik"` dan sebelum `Write-Host ""` (baris kosong terakhir sebelum return).

**Note:** Untuk tanggal expiry, increment 7 hari dari tanggal cleanup, bukan dari staging timestamp.

---

### TASK 3: Gabung Menu [6] Backup + [7] Staging jadi [6] Penyimpanan

**File:** `src/ui/cli.ps1`

**Apa yang diubah:**

**3a. Dot-source** — hapus dot-source ke backup module (baris ~19-22). Staging module tetap di-load.

**3b. Main menu** (baris ~751-752):
```powershell
# Before:
Write-Host "  [6] Backup      -- Kelola backup & restore" -ForegroundColor White
Write-Host "  [7] Staging     -- Lihat & kelola file staging" -ForegroundColor White

# After:
# Hapus baris [7], ubah [6] jadi:
Write-Host "  [6] Penyimpanan -- Kelola file backup (restore / hapus / export)" -ForegroundColor White
```

**3c. Switch handler (baris ~975-980):**
```powershell
# Before:
"6" {
    # Backup
    Show-BackupMenu
}
"7" {
    # Staging
    Show-StagingMenu
}

# After:
"6" {
    # Penyimpanan — gabungan backup + staging
    Show-StorageMenu
}
```

**3d. Fungsi baru `Show-StorageMenu`:**

Buat function `Show-StorageMenu` yang menggabungkan fungsi `Show-BackupMenu` dan `Show-StagingMenu` + fitur export.

```powershell
function Show-StorageMenu {
    <#
    .SYNOPSIS Menampilkan menu penyimpanan terpadu (restore / hapus / export)
    .DESCRIPTION Menu ini menggantikan Backup + Staging. File yang dibersihkan
                 masuk ke staging area. User bisa restore, hapus permanen, atau
                 export ke drive eksternal.
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
        Write-Host "  Penyimpanan kosong. Tidak ada file backup yang tersedia." -ForegroundColor Yellow
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
    Write-Host "  [nomor] Restore file" -ForegroundColor White
    Write-Host "  [R] Restore semua file" -ForegroundColor White
    Write-Host "  [D] Hapus permanen dari staging" -ForegroundColor White  # ganti [H] biar gak bentrok
    Write-Host "  [E] Export ke drive lain / USB" -ForegroundColor White
    Write-Host "  [Enter] Kembali ke menu" -ForegroundColor White
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
        return
    }
    
    switch ($choice) {
        'R' { 
            # Restore semua
            ...
        }
        'r' { ... }
        'D' { ... }  # Hapus permanen (panggil fungsi hapus staging)
        'd' { ... }
        'E' { ... }  # Export — panggil Show-ExportStorageMenu
        'e' { ... }
        default { return }
    }
}
```

**Catatan:** Kode di atas adalah template. Kamu harus adaptasi dengan fungsi-fungsi yang sudah ada di staging.ps1. Cek fungsi yang tersedia:
- `Get-StagedFiles` (staging.ps1)
- `Restore-FromStaging` (staging.ps1)
- `Remove-FromStaging` (staging.ps1) — kalo ada

---

### TASK 4: Fungsi Export ke Drive Lain / USB

**File:** `src/staging/staging.ps1`

**Tambah 2 fungsi:**

**4a. `Export-StagingItem`** — Copy file dari staging ke lokasi tujuan + simpan manifest

```powershell
function Export-StagingItem {
    <#
    .SYNOPSIS Export file staging ke drive eksternal / USB
    .PARAMETER OriginalPath Path asli file (identifier di staging)
    .PARAMETER DestinationPath Folder tujuan (misal F:\DrivePulse-Backup\)
    .OUTPUTS [PSCustomObject] Success / Error
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OriginalPath,
        
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )
    
    # Cari file di staging berdasarkan originalPath
    $stagedFiles = Get-StagedFiles
    $targetFile = $stagedFiles | Where-Object { $_.originalPath -eq $OriginalPath }
    
    if (-not $targetFile) {
        return [PSCustomObject]@{ Success = $false; Error = "File tidak ditemukan di staging" }
    }
    
    # Cari lokasi asli file di staging directory
    $stagingRoot = [System.IO.Path]::Combine($env:LOCALAPPDATA, "DrivePulse", "Staging")
    $stagingFilePath = ...  # cari berdasarkan metadata
    
    # Buat folder tujuan dengan struktur tanggal
    $dateStr = Get-Date -Format "yyyy-MM-dd"
    $exportDir = Join-Path $DestinationPath "DrivePulse-Backup-$dateStr"
    if (-not (Test-Path $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }
    
    # Copy file ke tujuan
    $fileName = [System.IO.Path]::GetFileName($targetFile.originalPath)
    $destFile = Join-Path $exportDir $fileName
    Copy-Item -Path $stagingFilePath -Destination $destFile -Force
    
    # Simpan metadata (manifest.json) di folder tujuan
    $manifest = @{
        exportDate    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        originalPath  = $targetFile.originalPath
        fileSize      = $targetFile.sizeBytes
        exportedFile  = $fileName
    }
    $manifestPath = Join-Path $exportDir "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        $manifest | ConvertTo-Json | Out-File $manifestPath -Encoding utf8
    } else {
        # Append ke manifest array
        $existing = Get-Content $manifestPath -Raw | ConvertFrom-Json
        if ($existing -is [array]) {
            $existing += $manifest
        } else {
            $existing = @($existing, $manifest)
        }
        $existing | ConvertTo-Json | Out-File $manifestPath -Encoding utf8
    }
    
    return [PSCustomObject]@{ Success = $true; FilePath = $destFile }
}
```

**4b. `Export-AllStaging`** — Export semua file staging ke drive eksternal

```powershell
function Export-AllStaging {
    <#
    .SYNOPSIS Export semua file dari staging ke drive eksternal
    .PARAMETER DestinationPath Folder tujuan (root)
    #>
    param([string]$DestinationPath)
    
    $stagedFiles = Get-StagedFiles
    $successCount = 0
    $errors = @()
    
    foreach ($file in $stagedFiles) {
        $result = Export-StagingItem -OriginalPath $file.originalPath -DestinationPath $DestinationPath
        if ($result.Success) {
            $successCount++
        } else {
            $errors += $result.Error
        }
    }
    
    return [PSCustomObject]@{
        SuccessCount = $successCount
        ErrorCount   = $errors.Count
        Errors       = $errors
    }
}
```

---

### TASK 5: Export Menu di CLI

**File:** `src/ui/cli.ps1`

**Tambah fungsi `Show-ExportStorageMenu`:**

```powershell
function Show-ExportStorageMenu {
    <#
    .SYNOPSIS Menu untuk export file staging ke drive eksternal / USB
    #>
    
    $stagedFiles = @()
    if (Get-Command Get-StagedFiles -ErrorAction SilentlyContinue) {
        $stagedFiles = @(Get-StagedFiles)
    }
    
    if ($stagedFiles.Count -eq 0) {
        Write-Host "  Tidak ada file untuk di-export." -ForegroundColor Yellow
        return
    }
    
    Write-Host ""
    Write-Host "  === Export ke Drive Lain / USB ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Tujuan export (contoh: F:\ atau D:\Backup):" -ForegroundColor White
    $destPath = Read-Host "  Path"
    
    if ([string]::IsNullOrWhiteSpace($destPath)) {
        Write-Host "  Export dibatalkan." -ForegroundColor Yellow
        return
    }
    
    # Validasi path tujuan
    if (-not (Test-Path $destPath)) {
        Write-Host "  ❌ Path '$destPath' tidak ditemukan." -ForegroundColor Red
        return
    }
    
    # Cek drive info
    $driveRoot = [System.IO.Path]::GetPathRoot($destPath)
    $driveInfo = Get-PSDrive -Name $driveRoot[0] -ErrorAction SilentlyContinue
    if ($driveInfo) {
        Write-Host "  Drive: $($driveInfo.Name) | Tersedia: $(Format-StagingSize -Bytes $driveInfo.Free)" -ForegroundColor Gray
    }
    
    # Export semua
    Write-Host ""
    Write-Host "  Export $($stagedFiles.Count) file ke $destPath ?" -ForegroundColor Yellow
    $confirm = Read-Host "  Ketik 'y' untuk melanjutkan"
    
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "  Export dibatalkan." -ForegroundColor Yellow
        return
    }
    
    if (Get-Command Export-AllStaging -ErrorAction SilentlyContinue) {
        $result = Export-AllStaging -DestinationPath $destPath
        Write-Host ""
        if ($result.SuccessCount -gt 0) {
            Write-Host "  ✅ $($result.SuccessCount) file berhasil di-export ke $destPath" -ForegroundColor Green
            Write-Host "     Metadata disimpan di: DrivePulse-Backup-$(Get-Date -Format 'yyyy-MM-dd')" -ForegroundColor Gray
        }
        if ($result.ErrorCount -gt 0) {
            Write-Host "  ⚠️  $($result.ErrorCount) file gagal di-export" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "  Tekan Enter untuk kembali" -ForegroundColor White
    Read-Host
}
```

---

### TASK 6: Hapus File Backup Module yang Tidak Terpakai

**File:** `src/backup/backup.ps1` (opsional — bisa di-archive)

Kalau sudah tidak ada yang dot-source ke `src/backup/backup.ps1`, file ini bisa:
- Dihapus (git rm), atau
- Dipindah ke `src/_archive/backup.ps1` biar ada history

**Cek dependency:** Pastikan tidak ada file lain yang masih panggil fungsi dari backup.ps1:
- `src/cleaner/clean.ps1` — sudah dihapus di Task 1
- `src/ui/cli.ps1` — di Task 3 hapus dot-source

---

## Referensi

- Requirement: Diskusi dengan user (Bos/Heri) — lihat memory/drivepulse-progress.md
- Issue terkait: selective cleanup + backup-staging restruktur

## Commit Messages

```
Task 1: feat: hapus backup module dari cleanup flow, cukup staging aja
Task 2: feat: tambah notif 7 hari di summary cleanup
Task 3: feat: gabung menu Backup + Staging jadi [6] Penyimpanan
Task 4: feat: fungsi Export-StagingItem dan Export-AllStaging
Task 5: feat: menu export ke drive eksternal di CLI
Task 6: chore: archive backup.ps1 (tidak terpakai)
```

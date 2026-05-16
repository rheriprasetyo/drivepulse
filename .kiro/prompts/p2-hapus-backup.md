# Prompt Kiro — Task: Hapus Backup Module dari Cleanup Flow

## Goal
Hapus panggilan backup function dari proses cleanup. File hasil cleanup cukup di-Move-ToStaging aja, gak perlu double copy ke Backup dulu. Ini ngurangin ruang disk dan simplify workflow.

## Branch
`feature/cleanup-notification` (lanjut dari task sebelumnya)

## File
`src/cleaner/clean.ps1`

## Perubahan

### 1. Hapus dot-source backup module (baris ~21-24)
Before:
```powershell
$backupModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'backup\backup.ps1'
if (Test-Path $backupModulePath) {
    . $backupModulePath
}
```
After: Hapus 5 baris ini.

### 2. Hapus Remove-ExpiredBackups di bagian purge (baris ~502-510)
Before:
```powershell
    # Purge expired backups dan staging (Req 4.7, 9.2)
    Write-Host "  Membersihkan backup dan staging yang kedaluwarsa..." -ForegroundColor DarkGray
    try {
        if (Get-Command Remove-ExpiredBackups -ErrorAction SilentlyContinue) {
            Remove-ExpiredBackups | Out-Null
        }
    }
    catch {
        Write-Warning "  Gagal membersihkan backup kedaluwarsa: $($_.Exception.Message)"
    }

    try {
        if (Get-Command Remove-ExpiredStaged -ErrorAction SilentlyContinue) {
            Remove-ExpiredStaged | Out-Null
        }
    }
```
After: Hapus bagian Remove-ExpiredBackups, sisakan cuma Remove-ExpiredStaged:
```powershell
    # Purge expired staging (Req 9.2)
    Write-Host "  Membersihkan staging yang kedaluwarsa..." -ForegroundColor DarkGray
    try {
        if (Get-Command Remove-ExpiredStaged -ErrorAction SilentlyContinue) {
            Remove-ExpiredStaged | Out-Null
        }
    }
```

### 3. Hapus panggilan Backup-BeforeDelete di loop item (baris ~542-550)
Before:
```powershell
        try {
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
```
After: Hapus bagian backup, langsung ke staging:
```powershell
        try {
            # Stage file (move to staging area) — backup tidak lagi diperlukan
            if (Get-Command Move-ToStaging -ErrorAction SilentlyContinue) {
                $stageResult = Move-ToStaging -SourcePath $itemPath -SessionId $SessionId
```

### 4. Update komentar header (baris ~6, ~302)
Ubah "backup > stage" jadi cukup "stage" di komentar.

### 5. Update komentar notif (dari task sebelumnya)
Di notif 7 hari yang sudah ditambah, ubah teks "menu [6] Backup" jadi "menu [6] Penyimpanan".

## Cek hasil
Pastikan tidak ada lagi error "Backup gagal" saat cleanup. File langsung masuk staging.

## Commit
Setelah selesai, jangan commit dulu. Laporkan ke Yombi.

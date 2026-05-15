<#
.SYNOPSIS
    DrivePulse — Backup Module
.DESCRIPTION
    Modul backup untuk membuat salinan byte-for-byte sebelum penghapusan,
    memverifikasi integritas, mengelola retensi, dan mendukung restore.
    Backup disimpan di %LOCALAPPDATA%\DrivePulse\backups\ dengan struktur
    direktori yang dipertahankan menggunakan drive-encoded paths.
.NOTES
    Author: DrivePulse Team
    Version: 1.3
    Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6
#>

# ─── Dot-source audit logger ───────────────────────────────
$auditPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'audit\audit.ps1'
if (Test-Path $auditPath) {
    . $auditPath
}

# ─── Constants ──────────────────────────────────────────────

$Script:BackupRoot = Join-Path $env:LOCALAPPDATA 'DrivePulse\backups'
$Script:DefaultRetentionDays = 7
$Script:MinRetentionDays = 1
$Script:MaxRetentionDays = 90

# ─── Helper Functions ───────────────────────────────────────

function Get-BackupRoot {
    <#
    .SYNOPSIS
        Mengembalikan path root backup.
    .OUTPUTS
        [string] Path absolut ke backup root
    #>
    return $Script:BackupRoot
}

function Get-ValidRetentionDays {
    <#
    .SYNOPSIS
        Memvalidasi dan mengembalikan nilai retention days yang valid.
    .PARAMETER RetentionDays
        Nilai retention days yang akan divalidasi
    .OUTPUTS
        [int] Nilai retention days yang valid (1-90, default 7)
    #>
    param(
        [object]$RetentionDays
    )

    if ($null -eq $RetentionDays) {
        return $Script:DefaultRetentionDays
    }

    try {
        $value = [int]$RetentionDays
        if ($value -ge $Script:MinRetentionDays -and $value -le $Script:MaxRetentionDays) {
            return $value
        }
    }
    catch {
        # Non-numeric value
    }

    Write-Warning "Nilai retensi tidak valid ($RetentionDays). Menggunakan default: $($Script:DefaultRetentionDays) hari."
    return $Script:DefaultRetentionDays
}

function ConvertTo-DriveEncodedPath {
    <#
    .SYNOPSIS
        Mengkonversi path absolut Windows ke drive-encoded path.
    .DESCRIPTION
        Contoh: C:\Users\file.txt → C_drive\Users\file.txt
    .PARAMETER AbsolutePath
        Path absolut Windows (e.g., C:\Users\file.txt)
    .OUTPUTS
        [string] Drive-encoded relative path
    #>
    param(
        [Parameter(Mandatory)]
        [string]$AbsolutePath
    )

    # Extract drive letter and remaining path
    if ($AbsolutePath -match '^([A-Za-z]):\\(.*)$') {
        $driveLetter = $Matches[1].ToUpper()
        $relativePath = $Matches[2]
        return Join-Path "${driveLetter}_drive" $relativePath
    }

    # Fallback: return as-is if not a standard Windows path
    return $AbsolutePath
}

function ConvertFrom-DriveEncodedPath {
    <#
    .SYNOPSIS
        Mengkonversi drive-encoded path kembali ke path absolut Windows.
    .DESCRIPTION
        Contoh: C_drive\Users\file.txt → C:\Users\file.txt
    .PARAMETER EncodedPath
        Drive-encoded relative path
    .OUTPUTS
        [string] Path absolut Windows
    #>
    param(
        [Parameter(Mandatory)]
        [string]$EncodedPath
    )

    if ($EncodedPath -match '^([A-Za-z])_drive\\(.*)$') {
        $driveLetter = $Matches[1].ToUpper()
        $relativePath = $Matches[2]
        return "${driveLetter}:\$relativePath"
    }

    return $EncodedPath
}

function Get-ManifestPath {
    <#
    .SYNOPSIS
        Mengembalikan path ke backup-manifest.json untuk session tertentu.
    .PARAMETER SessionId
        ID session backup
    .OUTPUTS
        [string] Path absolut ke backup-manifest.json
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SessionId
    )

    return Join-Path (Join-Path $Script:BackupRoot $SessionId) 'backup-manifest.json'
}

function Read-BackupManifest {
    <#
    .SYNOPSIS
        Membaca backup-manifest.json untuk session tertentu.
    .PARAMETER SessionId
        ID session backup
    .OUTPUTS
        [PSCustomObject] Manifest object atau $null jika tidak ditemukan
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SessionId
    )

    $manifestPath = Get-ManifestPath -SessionId $SessionId
    if (-not (Test-Path $manifestPath)) {
        return $null
    }

    try {
        $content = [System.IO.File]::ReadAllText($manifestPath, [System.Text.UTF8Encoding]::new($false))
        return $content | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-BackupManifest {
    <#
    .SYNOPSIS
        Menulis atau memperbarui backup-manifest.json untuk session tertentu.
    .PARAMETER SessionId
        ID session backup
    .PARAMETER Manifest
        Object manifest yang akan ditulis
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SessionId,

        [Parameter(Mandatory)]
        [PSCustomObject]$Manifest
    )

    $manifestPath = Get-ManifestPath -SessionId $SessionId
    $manifestDir = Split-Path -Parent $manifestPath

    if (-not (Test-Path $manifestDir)) {
        New-Item -Path $manifestDir -ItemType Directory -Force | Out-Null
    }

    $json = $Manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($manifestPath, $json, [System.Text.UTF8Encoding]::new($false))
}

# ─── Core Functions ─────────────────────────────────────────

function Backup-BeforeDelete {
    <#
    .SYNOPSIS
        Membuat backup byte-for-byte dari file sebelum dihapus.
    .DESCRIPTION
        Menyalin file ke Backup_Root dengan struktur direktori yang dipertahankan,
        memverifikasi ukuran salinan, dan mencatat metadata ke manifest.
        Terintegrasi dengan audit logger untuk aksi "backup".
    .PARAMETER SourcePath
        Path absolut file yang akan di-backup
    .PARAMETER SessionId
        ID session cleanup saat ini
    .OUTPUTS
        [PSCustomObject] @{ Success; BackupPath; Error }
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$SessionId
    )

    try {
        # Validasi file sumber ada
        if (-not (Test-Path $SourcePath -PathType Leaf)) {
            return [PSCustomObject]@{
                Success    = $false
                BackupPath = $null
                Error      = "File sumber tidak ditemukan: $SourcePath"
            }
        }

        # Dapatkan info file sumber
        $sourceFile = Get-Item $SourcePath -Force
        $sourceSize = $sourceFile.Length

        # Bangun path backup dengan drive-encoded structure
        $driveEncoded = ConvertTo-DriveEncodedPath -AbsolutePath $SourcePath
        $backupPath = Join-Path (Join-Path $Script:BackupRoot $SessionId) $driveEncoded

        # Buat direktori tujuan jika belum ada
        $backupDir = Split-Path -Parent $backupPath
        if (-not (Test-Path $backupDir)) {
            New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        }

        # Salin file byte-for-byte
        Copy-Item -Path $SourcePath -Destination $backupPath -Force

        # Verifikasi ukuran salinan
        $backupFile = Get-Item $backupPath -Force
        if ($backupFile.Length -ne $sourceSize) {
            # Hapus salinan yang gagal
            Remove-Item -Path $backupPath -Force -ErrorAction SilentlyContinue
            return [PSCustomObject]@{
                Success    = $false
                BackupPath = $null
                Error      = "Verifikasi ukuran gagal: sumber=$sourceSize bytes, salinan=$($backupFile.Length) bytes"
            }
        }

        # Catat metadata ke manifest
        $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'
        $manifest = Read-BackupManifest -SessionId $SessionId

        if ($null -eq $manifest) {
            $manifest = [PSCustomObject]@{
                sessionId = $SessionId
                createdAt = $timestamp
                files     = @()
            }
        }

        $entry = [PSCustomObject]@{
            originalPath = $SourcePath
            backupPath   = Join-Path $SessionId $driveEncoded
            sizeBytes    = $sourceSize
            timestamp    = $timestamp
        }

        # Tambahkan entry ke manifest
        $filesList = @($manifest.files)
        $filesList += $entry
        $manifest = [PSCustomObject]@{
            sessionId = $manifest.sessionId
            createdAt = $manifest.createdAt
            files     = $filesList
        }

        Write-BackupManifest -SessionId $SessionId -Manifest $manifest

        # Catat ke audit log
        if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
            Write-AuditEntry -Action 'backup' -FilePath $SourcePath
        }

        return [PSCustomObject]@{
            Success    = $true
            BackupPath = $backupPath
            Error      = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success    = $false
            BackupPath = $null
            Error      = $_.Exception.Message
        }
    }
}

function Restore-FromBackup {
    <#
    .SYNOPSIS
        Mengembalikan file dari backup ke lokasi aslinya.
    .DESCRIPTION
        Mendukung restore file individual atau batch per session.
        Membuat ulang direktori parent yang hilang.
        Terintegrasi dengan audit logger untuk aksi "restore".
    .PARAMETER BackupPath
        Path spesifik file backup yang akan di-restore
    .PARAMETER SessionId
        ID session untuk batch restore
    .PARAMETER All
        Switch untuk restore semua file dari session
    .PARAMETER Force
        Switch untuk overwrite file yang sudah ada tanpa prompt
    .OUTPUTS
        [PSCustomObject] @{ Success; RestoredCount; FailedCount; TotalSize; Errors }
    #>
    param(
        [string]$BackupPath,
        [string]$SessionId,
        [switch]$All,
        [switch]$Force
    )

    $restoredCount = 0
    $failedCount = 0
    $totalSize = [long]0
    $errors = @()

    try {
        # Tentukan file mana yang akan di-restore
        $filesToRestore = @()

        if ($SessionId) {
            # Restore dari session
            $manifest = Read-BackupManifest -SessionId $SessionId
            if ($null -eq $manifest) {
                return [PSCustomObject]@{
                    Success       = $false
                    RestoredCount = 0
                    FailedCount   = 0
                    TotalSize     = [long]0
                    Errors        = @("Backup untuk session '$SessionId' tidak ditemukan atau sudah dihapus.")
                }
            }

            foreach ($fileEntry in $manifest.files) {
                $filesToRestore += [PSCustomObject]@{
                    OriginalPath = $fileEntry.originalPath
                    BackupPath   = Join-Path $Script:BackupRoot $fileEntry.backupPath
                    SizeBytes    = $fileEntry.sizeBytes
                }
            }
        }
        elseif ($BackupPath) {
            # Restore file individual - cari di semua manifest
            $sessions = Get-ChildItem -Path $Script:BackupRoot -Directory -ErrorAction SilentlyContinue
            $found = $false

            foreach ($session in $sessions) {
                $manifest = Read-BackupManifest -SessionId $session.Name
                if ($null -eq $manifest) { continue }

                foreach ($fileEntry in $manifest.files) {
                    $fullBackupPath = Join-Path $Script:BackupRoot $fileEntry.backupPath
                    if ($fullBackupPath -eq $BackupPath -or $fileEntry.originalPath -eq $BackupPath) {
                        $filesToRestore += [PSCustomObject]@{
                            OriginalPath = $fileEntry.originalPath
                            BackupPath   = $fullBackupPath
                            SizeBytes    = $fileEntry.sizeBytes
                        }
                        $found = $true
                        break
                    }
                }
                if ($found) { break }
            }

            if (-not $found) {
                return [PSCustomObject]@{
                    Success       = $false
                    RestoredCount = 0
                    FailedCount   = 0
                    TotalSize     = [long]0
                    Errors        = @("Backup tidak ditemukan untuk: $BackupPath")
                }
            }
        }
        else {
            return [PSCustomObject]@{
                Success       = $false
                RestoredCount = 0
                FailedCount   = 0
                TotalSize     = [long]0
                Errors        = @("Parameter BackupPath atau SessionId harus diberikan.")
            }
        }

        # Restore setiap file
        foreach ($file in $filesToRestore) {
            try {
                # Cek apakah file backup masih ada
                if (-not (Test-Path $file.BackupPath -PathType Leaf)) {
                    $failedCount++
                    $errors += "Backup sudah dihapus (retensi): $($file.OriginalPath)"
                    continue
                }

                # Cek apakah file tujuan sudah ada
                if ((Test-Path $file.OriginalPath) -and -not $Force) {
                    $failedCount++
                    $errors += "File sudah ada di lokasi asli (gunakan -Force untuk overwrite): $($file.OriginalPath)"
                    continue
                }

                # Buat direktori parent jika belum ada
                $parentDir = Split-Path -Parent $file.OriginalPath
                if (-not (Test-Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                }

                # Salin file dari backup ke lokasi asli
                Copy-Item -Path $file.BackupPath -Destination $file.OriginalPath -Force

                # Verifikasi
                $restoredFile = Get-Item $file.OriginalPath -Force
                if ($restoredFile.Length -ne $file.SizeBytes) {
                    $failedCount++
                    $errors += "Verifikasi ukuran gagal setelah restore: $($file.OriginalPath)"
                    continue
                }

                $restoredCount++
                $totalSize += $file.SizeBytes

                # Catat ke audit log
                if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                    Write-AuditEntry -Action 'restore' -FilePath $file.OriginalPath
                }
            }
            catch {
                $failedCount++
                $errors += "Gagal restore $($file.OriginalPath): $($_.Exception.Message)"
            }
        }

        return [PSCustomObject]@{
            Success       = ($failedCount -eq 0)
            RestoredCount = $restoredCount
            FailedCount   = $failedCount
            TotalSize     = $totalSize
            Errors        = $errors
        }
    }
    catch {
        return [PSCustomObject]@{
            Success       = $false
            RestoredCount = $restoredCount
            FailedCount   = $failedCount
            TotalSize     = $totalSize
            Errors        = @($_.Exception.Message)
        }
    }
}

function Get-AvailableBackups {
    <#
    .SYNOPSIS
        Menampilkan daftar backup yang tersedia.
    .DESCRIPTION
        Membaca semua session backup dan metadata-nya.
        Mendukung filter berdasarkan SessionId.
    .PARAMETER SessionId
        Filter opsional berdasarkan session ID
    .OUTPUTS
        [PSCustomObject[]] Array metadata backup
    #>
    param(
        [string]$SessionId
    )

    $results = @()

    if (-not (Test-Path $Script:BackupRoot)) {
        return $results
    }

    if ($SessionId) {
        # Filter session tertentu
        $manifest = Read-BackupManifest -SessionId $SessionId
        if ($null -ne $manifest) {
            foreach ($fileEntry in $manifest.files) {
                $results += [PSCustomObject]@{
                    SessionId    = $manifest.sessionId
                    OriginalPath = $fileEntry.originalPath
                    BackupPath   = $fileEntry.backupPath
                    SizeBytes    = $fileEntry.sizeBytes
                    Timestamp    = $fileEntry.timestamp
                    CreatedAt    = $manifest.createdAt
                }
            }
        }
    }
    else {
        # Semua session
        $sessions = Get-ChildItem -Path $Script:BackupRoot -Directory -ErrorAction SilentlyContinue
        foreach ($session in $sessions) {
            $manifest = Read-BackupManifest -SessionId $session.Name
            if ($null -eq $manifest) { continue }

            foreach ($fileEntry in $manifest.files) {
                $results += [PSCustomObject]@{
                    SessionId    = $manifest.sessionId
                    OriginalPath = $fileEntry.originalPath
                    BackupPath   = $fileEntry.backupPath
                    SizeBytes    = $fileEntry.sizeBytes
                    Timestamp    = $fileEntry.timestamp
                    CreatedAt    = $manifest.createdAt
                }
            }
        }
    }

    return $results
}

function Remove-ExpiredBackups {
    <#
    .SYNOPSIS
        Menghapus backup yang sudah melewati periode retensi.
    .DESCRIPTION
        Menghapus session backup yang timestamp-nya lebih tua dari RetentionDays.
        Terintegrasi dengan audit logger untuk aksi "auto-purge" dan "purge-failed".
    .PARAMETER RetentionDays
        Periode retensi dalam hari (1-90, default 7)
    .OUTPUTS
        [PSCustomObject] @{ PurgedCount; PurgedSize; Errors }
    #>
    param(
        [int]$RetentionDays = 7
    )

    $validRetention = Get-ValidRetentionDays -RetentionDays $RetentionDays
    $purgedCount = 0
    $purgedSize = [long]0
    $errors = @()
    $cutoffDate = (Get-Date).AddDays(-$validRetention)

    if (-not (Test-Path $Script:BackupRoot)) {
        return [PSCustomObject]@{
            PurgedCount = 0
            PurgedSize  = [long]0
            Errors      = @()
        }
    }

    $sessions = Get-ChildItem -Path $Script:BackupRoot -Directory -ErrorAction SilentlyContinue

    foreach ($session in $sessions) {
        $manifest = Read-BackupManifest -SessionId $session.Name
        if ($null -eq $manifest) {
            # Jika tidak ada manifest, cek berdasarkan folder creation time
            if ($session.CreationTime -lt $cutoffDate) {
                try {
                    Remove-Item -Path $session.FullName -Recurse -Force
                }
                catch {
                    $errors += "Gagal menghapus session tanpa manifest: $($session.Name)"
                }
            }
            continue
        }

        # Cek apakah session sudah expired berdasarkan createdAt
        try {
            $sessionDate = [DateTime]::Parse($manifest.createdAt)
            if ($sessionDate -ge $cutoffDate) {
                continue  # Belum expired
            }
        }
        catch {
            # Jika parsing gagal, gunakan folder creation time
            if ($session.CreationTime -ge $cutoffDate) {
                continue
            }
        }

        # Session sudah expired - hapus semua file
        foreach ($fileEntry in $manifest.files) {
            $fullBackupPath = Join-Path $Script:BackupRoot $fileEntry.backupPath
            try {
                if (Test-Path $fullBackupPath) {
                    Remove-Item -Path $fullBackupPath -Force -ErrorAction Stop
                    $purgedCount++
                    $purgedSize += $fileEntry.sizeBytes

                    # Catat ke audit log
                    if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                        Write-AuditEntry -Action 'auto-purge' -FilePath $fileEntry.originalPath
                    }
                }
            }
            catch {
                $errors += "Gagal menghapus: $($fileEntry.originalPath) - $($_.Exception.Message)"

                # Catat kegagalan ke audit log
                if (Get-Command Write-AuditEntry -ErrorAction SilentlyContinue) {
                    Write-AuditEntry -Action 'purge-failed' -FilePath $fileEntry.originalPath
                }
            }
        }

        # Hapus folder session dan manifest
        try {
            Remove-Item -Path $session.FullName -Recurse -Force -ErrorAction Stop
        }
        catch {
            $errors += "Gagal menghapus folder session: $($session.Name)"
        }
    }

    return [PSCustomObject]@{
        PurgedCount = $purgedCount
        PurgedSize  = $purgedSize
        Errors      = $errors
    }
}

function Test-BackupSpace {
    <#
    .SYNOPSIS
        Memeriksa apakah ruang disk cukup untuk backup.
    .DESCRIPTION
        Membandingkan ruang yang tersedia di drive Backup_Root
        dengan jumlah bytes yang dibutuhkan.
    .PARAMETER RequiredBytes
        Jumlah bytes yang dibutuhkan untuk backup
    .OUTPUTS
        [PSCustomObject] @{ Sufficient; AvailableBytes; RequiredBytes }
    #>
    param(
        [Parameter(Mandatory)]
        [long]$RequiredBytes
    )

    try {
        # Pastikan backup root ada
        if (-not (Test-Path $Script:BackupRoot)) {
            New-Item -Path $Script:BackupRoot -ItemType Directory -Force | Out-Null
        }

        # Dapatkan drive dari backup root
        $driveLetter = (Split-Path -Qualifier $Script:BackupRoot).TrimEnd(':')
        $drive = Get-PSDrive -Name $driveLetter -ErrorAction Stop
        $availableBytes = $drive.Free

        return [PSCustomObject]@{
            Sufficient     = ($availableBytes -ge $RequiredBytes)
            AvailableBytes = $availableBytes
            RequiredBytes  = $RequiredBytes
        }
    }
    catch {
        # Fallback: gunakan WMI/CIM
        try {
            $backupDrive = Split-Path -Qualifier $Script:BackupRoot
            $driveLetter = $backupDrive.TrimEnd(':')
            $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${driveLetter}:'" -ErrorAction Stop
            $availableBytes = $disk.FreeSpace

            return [PSCustomObject]@{
                Sufficient     = ($availableBytes -ge $RequiredBytes)
                AvailableBytes = $availableBytes
                RequiredBytes  = $RequiredBytes
            }
        }
        catch {
            # Jika semua gagal, asumsikan cukup (fail-open)
            return [PSCustomObject]@{
                Sufficient     = $true
                AvailableBytes = [long]0
                RequiredBytes  = $RequiredBytes
            }
        }
    }
}
